# ISSUES.md — Architecture Overhaul + 11th Edition Migration Tracker

Companion docs: `ARCHITECTURE_AUDIT_2026-06.md` (findings), `PRD.md` (target behavior of
overhauled modules — the spec that Tier 3 fixes are validated against).

Conventions:
- IDs are sequential and ordered by **dependency tier, then severity**. Work top-to-bottom.
- Category: bug / regression / tech-debt / missing-feature / breaking-change.
- "11e" = the new edition core rules (uploaded `warhammer40k_core_rules8.txt`); rule refs
  like `(05.03)` are that document's section numbers.
- Severity: blocker = the 11e migration cannot land correctly without it; high = causes
  real defects or blocks several other issues; medium = quality/robustness; low = hygiene.
- Every entry was checked against the actual code on 2026-06-10; entries based on
  unreproduced subagent reports say so explicitly in the description.
- Update **Status in this file** when an issue is completed (TODO → DONE + one-line note).

---

## TIER 1 — Foundations (no dependencies)

### ISS-001 — Route all in-game GameState mutations through the action pipeline
- **Location:** `40k/phases/FormationsPhase.gd:593,598,767`; `40k/scripts/DeploymentController.gd:231,233`; `40k/autoloads/PhaseManager.gd:294-295`
- **Category:** bug
- **Severity:** high
- **Description:** The action pipeline (`execute_action → create_result(changes) → apply_state_changes`) exists, but these sites write `GameState.state[...]` directly: warlord designation (FormationsPhase), attachment "STATE REPAIR" (DeploymentController — a UI controller mutating canonical state), and end-of-game flags (PhaseManager). Direct writes are invisible to the diff stream, so replay, undo, the action log, and multiplayer sync silently miss them. Initialization-time writes (`ArmyListManager.gd:317-323`, `MultiplayerLobby.gd:276,549`, `WebLobby.gd:433,518,621`) happen pre-game and are acceptable, but must be explicitly whitelisted.
- **Root cause:** No enforcement that phases return changes instead of writing state; convenience writes accumulated over time.
- **Proposed fix:** Convert `_process_designate_warlord` to return `create_result(true, changes)` with `{op:"set", path:"units.<id>.meta.is_warlord", value:...}` entries (pattern already used at `FormationsPhase.gd:616-646`); move the DeploymentController attachment repair into the deployment phase as a dispatched action (or a validated repair step inside the phase); make PhaseManager set `meta.game_ended`/`meta.winner` via its own `apply_state_changes`. Document the pre-game whitelist in `GameState.gd`. Add a regression test that greps the codebase for `GameState.state[...] =` outside the whitelist.
- **Dependencies:** none
- **Affected files:** `40k/phases/FormationsPhase.gd`, `40k/scripts/DeploymentController.gd`, `40k/autoloads/PhaseManager.gd`, `40k/autoloads/GameState.gd` (whitelist doc), new test file
- **Acceptance criteria:** grep finds no in-game direct writes outside the documented whitelist; warlord designation and attachment repair still function (action dispatched headless, state asserted, diffs present in result); existing formation/deployment tests pass.
- **Status:** DONE — warlord designation/auto-designation and end-of-game flags now return diffs through the pipeline; attachment repair moved into a new `REPAIR_FORMATION_ATTACHMENT` DeploymentPhase action; whitelist documented in GameState.gd and enforced by `tests/test_iss001_pipeline_mutations.gd` (static scan + behavioral, 9/9); full pretrigger suite 562/562; windowed scenarios 367 + 378 pass.

### ISS-002 — Centralize rule constants in a GameConstants module with an edition switch
- **Location:** engagement range `1.0` literals: `40k/phases/MovementPhase.gd:33`, `40k/phases/ChargePhase.gd:34,1769`, `40k/autoloads/RulesEngine.gd:7598,7782`, `40k/autoloads/TerrainManager.gd:298`, `40k/scripts/PersistentEngagementOverlay.gd:15`, `40k/scripts/FightController.gd:91` (mm), `40k/scripts/AIDecisionMaker.gd:12` (px), `40k/autoloads/Measurement.gd:266` (default param); coherency/detection distances similarly inlined
- **Category:** tech-debt
- **Severity:** high
- **Description:** The same rule constant is declared at least 9 times in 4 different units (inches, px, mm). 11e changes engagement range to 2" (03.04) and rewrites coherency (03.03); without one source of truth the migration is a grep-and-pray exercise and partial updates will produce subtle mixed-edition behavior.
- **Root cause:** No shared constants module; each file declared what it needed.
- **Proposed fix:** New `40k/autoloads/GameConstants.gd` (or static class) exposing `engagement_range_inches()`, coherency parameters, detection range, etc., keyed off an `edition` setting (default `10`, later `11`). Replace all literals; keep `BARRICADE_ENGAGEMENT_RANGE` semantics. Unit conversion stays in `Measurement`.
- **Dependencies:** none
- **Affected files:** all files listed in Location, plus `40k/project.godot` (autoload), new `GameConstants.gd`, tests
- **Acceptance criteria:** grep for `= 1.0` engagement-range literals returns nothing; all tests pass with edition=10 (behavior unchanged); flipping edition=11 changes `engagement_range_inches()` to 2.0 in a unit test.
- **Status:** DONE — new `40k/scripts/rules/GameConstants.gd` (static class, deliberately not an autoload so RulesEngine/AI static functions can use it); replaced 9 const declarations + 6 hidden literal-`1.0` call sites + 2 extra nests the audit missed (`RulesEngine._get_effective_engagement_range_rules` locals, AI's composed "3"+ER" check range); coherency 2.0" literals centralized too; `Measurement.is_in_engagement_range_shape_aware` default is now edition-aware. Bug found & fixed: FightController's ER ring passed 25.4 (mm) to a px API, rendering at 0.635" — now `inches_to_px(...)`. Enforced by `tests/test_iss002_game_constants.gd` (13/13, incl. live ER flip at edition 11); pretrigger suite 575/575; windowed charge scenario 372 passes. Charge declare range (12", edition-stable) left in place.

### ISS-003 — Structured weapon/unit ability schema + ability registry (replace regex parsing)
- **Location:** `40k/autoloads/RulesEngine.gd:5389` (`_parse_sustained_hits_from_string`), `:5701` (`_parse_anti_keywords_from_string`), `:4759-4764` (comma-split of `special_rules`); `40k/armies/*.json` (`"special_rules": "anti-infantry 4+, devastating wounds, rapid fire 1"`)
- **Category:** tech-debt
- **Severity:** high
- **Description:** Weapon abilities live as free text parsed by regex at resolve time. Typos are silently ignored (a misspelled ability simply never fires), and 11e's keyword-scoped abilities (`[LETHAL HITS: VEHICLE]`, 24.01), new abilities (CLEAVE, CLOSE-QUARTERS, ONE SHOT) and per-ability choices (LETHAL HITS is now optional, 24.23) don't fit a flat string.
- **Root cause:** Data format inherited from initial import; parsing grew incrementally.
- **Proposed fix:** Schema: `"abilities": [{"id":"rapid_fire","x":1},{"id":"anti","keyword":"INFANTRY","threshold":4}]`. Build an `AbilityRegistry` mapping `id` → definition (hooks consumed by the attack sequence). Write a one-off converter for the army JSONs (keep `special_rules` text for display). Loader validates every `id` against the registry at load time — unknown ids are load errors, not silent no-ops. RulesEngine `has_*`/`is_*` helpers read the structured data.
- **Dependencies:** none
- **Affected files:** `40k/armies/*.json`, `40k/autoloads/RulesEngine.gd`, `40k/autoloads/ArmyListManager.gd`, new `AbilityRegistry.gd`, converter script, tests
- **Acceptance criteria:** converted JSONs load with zero validation errors; an intentionally misspelled ability id fails loading with a clear error; full test suite passes; one end-to-end shoot action produces identical results pre/post conversion (golden comparison).
- **Status:** DONE — new `40k/scripts/rules/AbilityRegistry.gd` (22 registered ids incl. 11e-forward cleave/close_quarters/one_shot; parse/validate/display round-trip); 236 weapons across 10 army files converted to structured `abilities` (Python converter, content verified identical apart from added arrays); `RulesEngine.get_weapon_profile` attaches `profile.abilities` and synthesizes the engine-facing string from structured data when present (structured = authoritative); ArmyListManager fails the load on unknown ids/params. Validated by `test_iss003_ability_schema.gd` 26/26 — incl. converter parity for all 236 weapons and a golden `resolve_shoot` (structured-only weapon → identical dice + diffs vs string-defined twin); pretrigger suite 601/601; windowed scenario 374 (devastating wounds from converted data) passes.

### ISS-004 — Uniform per-action RNG seeding (eliminate unseeded RNGService sites)
- **Location:** 30 unseeded `RulesEngine.RNGService.new()` sites, e.g. `40k/phases/MovementPhase.gd:476`, `40k/phases/ShootingPhase.gd:61,2459,2568,2851`; seeded pattern already exists (`MovementPhase.gd:1473-1481` honors `payload.rng_seed`, `NetworkManager.get_next_rng_seed()` at `NetworkManager.gd:2369-2378`)
- **Category:** bug
- **Severity:** high
- **Description:** Determinism is half-built: many handlers honor `payload.rng_seed` (issue #329 work), but 30 sites still construct unseeded RNG. Any roll on those paths breaks replay determinism and forces multiplayer to broadcast results instead of validating them.
- **Root cause:** Seeding was retrofitted action-by-action; no rule that all rolls flow through a seeded service.
- **Proposed fix:** Every dice-rolling action handler obtains its RNG via one helper: `payload.rng_seed` if present, else `NetworkManager.get_next_rng_seed()` (works offline — deterministic hash of session/counter/turn), recording the seed used into the action/result for the log. Forbid bare `RNGService.new()` outside the helper via a lint test.
- **Dependencies:** none
- **Affected files:** all 30 call sites (`grep -rn "RNGService.new()"`), `40k/autoloads/RulesEngine.gd`, `40k/autoloads/NetworkManager.gd`, lint test
- **Acceptance criteria:** grep finds no unseeded constructions outside the helper; replaying a recorded action sequence twice yields identical final state hash; existing tests pass.
- **Status:** DONE — two sanctioned factories in RulesEngine: `rng_for_action(action)` (honors `payload.rng_seed`, else generates one and **records it back into the action** for the log) and `make_rng()` (non-action contexts; NetworkManager session seed when hosting, test_mode_seed-aware, else randomize). All 19 unseeded sites outside RulesEngine converted (phases incl. the 4 `_init`-time members, StratagemManager ×3, TransportManager, MissionManager, FactionAbilityManager ×2, WoundAllocationOverlay) + 9 internal RulesEngine fallbacks; the big-booms handler (action in scope) uses `rng_for_action`. Lint enforced by `test_iss004_rng_seeding.gd` (16/16, incl. end-to-end: a logged SHOOT action replays with identical dice + diffs). Three #329 source-shape pins updated to assert the factory. Suite 617/617; windowed FNP scenario passes. Note: whole-game replay-hash proof lands with ISS-021's action log; this issue delivers the per-action seed plumbing it requires.

### ISS-005 — Extract PhaseControllerBase for the five phase controllers
- **Location:** identical `_setup_ui_references()` at `40k/scripts/ShootingController.gd:307`, `MovementController.gd:252`, `ChargeController.gd:255`, `FightController.gd:130`; same lifecycle pattern in `DeploymentController.gd`
- **Category:** tech-debt
- **Severity:** high
- **Description:** ~20k lines across five controllers with no base class; UI-reference lookup, right-panel scaffolding, visual-layer creation, and signal bookkeeping are copy-pasted (~2,000-2,500 duplicated lines). Every cross-cutting change must be made five times; the 11e UI changes (new shooting types, fight steps, disembark modes) would multiply this.
- **Root cause:** Controllers were created by copying the previous phase's controller.
- **Proposed fix:** `PhaseControllerBase` (extends Node2D) owning: UI refs, a single phase-UI container node, signal registration/teardown (see ISS-013), input enable/disable, common token-highlight helpers. Controllers override `_build_phase_ui()`, `_on_action(...)` etc. Migrate one controller first (Charge — smallest risk), then the rest.
- **Dependencies:** none
- **Affected files:** 5 controller files, new `40k/scripts/PhaseControllerBase.gd`, `40k/scripts/Main.gd` (instantiation), windowed scenarios for each phase
- **Acceptance criteria:** all five controllers extend the base; duplicated `_setup_ui_references` removed; each phase's windowed scenario passes (`40k/tests/run_scenarios.sh`); no `ERROR` lines in debug log during a full phase cycle (verify via `verify_delivery`).
- **Status:** DONE — new `40k/scripts/PhaseControllerBase.gd` (extends Node2D) owning `board_view`/`hud_bottom`/`hud_right` + `_setup_ui_references()` with `_on_ui_references_ready` / `_setup_bottom_hud` / `_setup_right_panel` hooks. All five controllers migrated: Shooting/Movement/Charge dropped their copy-pasted lookup + duplicate member vars; FightController's divergent version became an `_on_ui_references_ready` override (damage feedback + state banner); DeploymentController switched from bare Node onto the base. Validated: windowed scenarios across all five phases pass (377 deployment, 51 movement, 374 shooting, 372 charge, fight_self_targeting); pretrigger suite 617/617. Deeper consolidation (signal registry, UI container, input gating) follows in ISS-013/018/008 as planned.

### ISS-006 — Remove committed artifacts from git and ignore them
- **Location:** `40k/test_results/` (152MB), `logs/` (1.4MB), `40k/saves/` (11MB), `ai_fix_loop_*` outputs, `test_results/` at root
- **Category:** tech-debt
- **Severity:** medium
- **Description:** ~165MB of generated screenshots, logs, and save files are version-controlled. Every clone/CI run pays for them; diffs and reviews are noisy; some saves may contain stale schema that confuses debugging.
- **Root cause:** Outputs were never gitignored.
- **Proposed fix:** `git rm -r --cached` the artifact dirs: `40k/test_results` (3,340 tracked files), `40k/.godot_home`/`40k/.tmp_home` (11 tracked files), `logs/`, root `test_results/`, `ai_fix_loop_*` outputs, stale `40k/saves` (keep any used as fixtures). **Keep `40k/tests/scenarios/goldens/` (500 tracked files) — they are curated golden images used by the scenario runner.** Add `.gitignore` entries, document where artifacts land.
- **Dependencies:** none
- **Affected files:** `.gitignore`, removed artifact paths
- **Acceptance criteria:** fresh clone size drops by ~150MB; `run_scenarios.sh` and pretrigger tests still pass (no test reads a deleted artifact); `git status` stays clean after a game run.
- **Status:** DONE — untracked 3,589 files (~165MB): `40k/test_results` (152MB), `40k/saves` (11MB dev saves; live dir kept via .gitkeep — test fixtures in `40k/tests/saves/` untouched), `.godot_home`/`.tmp_home`, `logs/`, root `test_results/`, ai-loop iteration logs/trackers. `test_results/test_commands/commands/` structure kept via .gitkeep (TestModeHandler exchanges files there); `tests/scenarios/goldens/` (500 curated images) deliberately kept tracked. Verified: tests + windowed scenario pass and `git status` is clean afterwards.

### ISS-007 — Guard freed-node access during phase controller cleanup
- **Location:** `40k/scripts/Main.gd:4159-4161` (calls `shooting_controller._clear_visuals()` then `queue_free()` without `is_instance_valid` check); same pattern for other controllers in `Main.gd:4104-4172`
- **Category:** bug
- **Severity:** medium
- **Description:** Phase-transition cleanup calls methods on controllers without validity checks while async signals may still be in flight; risk of "call on null/freed instance" crashes during rapid phase transitions, AI fast-forward, or multiplayer phase pushes.
- **Root cause:** Manual lifecycle management in Main with checks added inconsistently.
- **Proposed fix:** Short-term: wrap every controller method call in `if controller and is_instance_valid(controller):`. Real fix arrives with ISS-013 (single teardown path).
- **Dependencies:** none
- **Affected files:** `40k/scripts/Main.gd`
- **Acceptance criteria:** scripted rapid phase-cycling (scenario driving 3 full turns at max AI speed) produces no script errors in the debug log.
- **Status:** DONE — all seven controller teardown blocks in `Main.setup_phase_controllers` now guard with `is_instance_valid` (and null the reference unconditionally). Validated live over the MCP bridge: 17 rapid phase transitions including out-of-order jumps → 0 errors in the debug log, `verify_delivery` verdict PASS; windowed shooting + fight scenarios and the 617-check suite all pass.

### ISS-008 — Standardize controller input handling
- **Location:** `40k/scripts/ShootingController.gd:3839` (`_input`), `40k/scripts/FightController.gd:1335` (`_input`), `40k/scripts/MovementController.gd:1609` (`_unhandled_input`), `40k/scripts/DeploymentController.gd:82` (`_unhandled_input`), `40k/scripts/Main.gd:11881` (`_unhandled_input` is an empty `pass`)
- **Category:** bug
- **Severity:** medium
- **Description:** Mixed `_input` vs `_unhandled_input` means some controllers consume keys before the UI sees them; during phase transitions two controllers can briefly coexist and race for the same event. There is no central place to see what hotkeys exist.
- **Root cause:** Per-controller copy-paste with different choices over time.
- **Proposed fix:** All controllers use `_unhandled_input`, gated by an `is_active` flag the lifecycle sets; global hotkeys (ESC/settings) live in Main's `_unhandled_input` (currently empty). Fold into `PhaseControllerBase` once ISS-005 lands.
- **Dependencies:** none (cleaner after ISS-005)
- **Affected files:** 5 controllers, `40k/scripts/Main.gd`
- **Acceptance criteria:** windowed scenario asserts phase-specific hotkeys work in their phase and do nothing in others; ESC opens settings in every phase.
- **Status:** DONE (scope corrected during implementation) — investigation showed the `_input` usage in Shooting/Fight/Charge controllers is **deliberate**: those handlers must pre-empt GUI focus / modal dialogs (wound-allocation overlay; PileInDialog during interactive pile-in; charge-confirm hit-testing) and `_unhandled_input` never fires while a modal AcceptDialog is open — blanket standardization would have broken pile-in. Every handler already carries a phase/state guard (verified: phase-type checks, `awaiting_movement`, `is_placing()`, multiplayer-turn checks), and controllers are freed on phase exit, so cross-phase races are guarded twice over. Implemented: each deliberate `_input` documented in place; Main's dead empty `_unhandled_input` removed (global ESC genuinely lives in `Main._input`, documented). Validated via the rapid-cycle MCP run (0 errors), shooting/fight scenarios (exercise the bypass paths), and the full suite.

### ISS-009 — Replace hardcoded `/root/...` node paths with injected references
- **Location:** 30+ sites, e.g. `40k/autoloads/SaveLoadManager.gd:127`, `40k/autoloads/PhaseManager.gd:145`, controllers' `get_node_or_null("/root/Main/BoardRoot/BoardView")`
- **Category:** tech-debt
- **Severity:** low
- **Description:** Hidden dependencies on scene-tree layout; renaming a node breaks distant systems at runtime; impossible to unit-test in isolation.
- **Root cause:** Autoloads are globally addressable, so paths were convenient.
- **Proposed fix:** Autoloads referenced by global name (already valid GDScript); scene nodes passed into controllers at construction by the lifecycle manager. Do opportunistically alongside ISS-005/013 rather than as a sweep.
- **Dependencies:** ISS-005
- **Affected files:** controllers, `40k/autoloads/SaveLoadManager.gd`, `40k/autoloads/PhaseManager.gd`, `40k/scripts/Main.gd`
- **Acceptance criteria:** no `get_node("/root/Main/...")` string paths in controllers; game boots and a full turn plays with no errors.
- **Status:** TODO (rides with ISS-013 as planned — PhaseControllerBase centralized the three main lookups; the lifecycle manager built in ISS-013 will inject board/HUD references at construction, removing the remaining string paths)

### ISS-010 — Move root-level status/plan documents into docs/history
- **Location:** repo root: ~40 files (`MASTER_AUDIT.md`, `FEB21_AUDIT.md`, `DEPLOYMENT_FIX_STATUS.md`, `ai_fix_loop_log.txt`, `scrap.md`, …)
- **Category:** tech-debt
- **Severity:** low
- **Description:** The root directory mixes living docs (CLAUDE.md, SESSION_PLAYBOOK.md) with dozens of dated one-off status reports, making it hard to know what is current guidance.
- **Root cause:** Session outputs were saved to root and never archived.
- **Proposed fix:** `docs/history/` for dated reports; keep CLAUDE.md, SESSION_PLAYBOOK.md, README-class docs, ISSUES.md, PRD.md, current audit at root. Update any references.
- **Dependencies:** none
- **Affected files:** root `.md`/log files, possibly links in CLAUDE.md
- **Acceptance criteria:** root contains only living documents; `git grep` finds no broken references to moved files.
- **Status:** DONE — 36 dated status/audit/plan docs (plus claude_dev_eval.pptx) moved to `docs/history/`. Kept at root because they are living or referenced by tooling/tests: CLAUDE.md, SESSION_PLAYBOOK.md, ISSUES.md, PRD.md, ARCHITECTURE_AUDIT_2026-06.md, INITIAL.md, PRP_Best_Practices_for_Claude.md, ai_fix_loop_prompt.md (ai_fix_loop.sh input), AI_STALL_FIXES.md / AI_IMPROVEMENT.md (loop-script inputs), TESTS_NEEDED.md (.claude do-task workflow), CONSOLIDATED_AUDIT_TASKS.md (read by test_audit_already_done_pin.gd). Reference check done before moving.

### ISS-011 — Delete or reinstate archived/disabled tests
- **Location:** `40k/tests_archived_disabled/` (11 entries), `40k/tests/disabled_tests/` (e.g. `test_fight_phase_alternation.gd`)
- **Category:** tech-debt
- **Severity:** low
- **Description:** Disabled tests rot and mislead coverage estimates. The fight-phase alternation test is exactly the area 11e rewrites (ISS-050) — it should either guard the current behavior until then or be deleted. Confirmed during ISS-002: the GUT suite under `tests/unit/` is also rotten — running it yields ~94 `[Failed]` assertions (error-ordering/wording drift vs. current RulesEngine) and the run hangs on network listeners (relay HTTP noise) until timeout; it is not part of any runner script. Triage it under this issue too.
- **Root cause:** Tests disabled during past refactors and never revisited.
- **Proposed fix:** Triage each: reinstate (fix), or delete with a note in the commit. No third state.
- **Dependencies:** none
- **Affected files:** `40k/tests_archived_disabled/*`, `40k/tests/disabled_tests/*`
- **Acceptance criteria:** both directories gone; every remaining test is executed by a runner script.
- **Status:** TODO

---

## TIER 2 — Architecture consolidation (depends on Tier 1)

### ISS-012 — Unify duplicated ranged/melee resolution into one AttackSequence module
- **Location:** `40k/autoloads/RulesEngine.gd:2202` (`_resolve_assignment`, ~1,000 lines) and `:8647` (`_resolve_melee_assignment`, ~1,100 lines)
- **Category:** tech-debt
- **Severity:** high
- **Description:** Two near-parallel implementations of hit→wound→save→damage with inline copies of lethal/sustained/devastating/anti/precision handling. Every rules fix must be made twice and verified twice; they have already drifted in places (e.g., hazardous handling differs between paths). This is the single biggest obstacle to the 11e attack-sequence rewrite (ISS-041).
- **Root cause:** Melee resolution was written by copying the ranged path.
- **Proposed fix:** Extract `AttackSequence` (static class under `40k/scripts/rules/` or autoload-free RefCounted) parameterized by context (ranged/melee, BS/WS, eligible modifiers). Keep RulesEngine's public functions as thin wrappers so phase callers don't change. Land with golden tests: identical inputs → identical outputs vs. old code for a matrix of weapons/abilities.
- **Dependencies:** ISS-002, ISS-003
- **Affected files:** `40k/autoloads/RulesEngine.gd`, new `AttackSequence.gd`, tests
- **Acceptance criteria:** both `_resolve_*_assignment` bodies delegate to the shared module; golden parity tests pass; full pretrigger suite passes; a windowed shooting + fight scenario passes.
- **Status:** DONE — per-roll hit and wound evaluation unified in `40k/scripts/rules/AttackSequence.gd` (`evaluate_hit_roll` with parameterized crit threshold + indirect fail-band, `evaluate_wound_roll` with anti-crit threshold). All NINE duplicated loop bodies rewired onto it (3 hit loops + 6 wound branches across ranged-interactive, ranged-auto-resolve, and melee paths); dice-record assembly stayed per-path. Verified: all 63 golden entries byte-identical post-extraction; suite 626/626; windowed shooting + fight scenarios pass. Scope note (deliberate): the surrounding *orchestration* (attack gathering, dice-record schemas, the divergent melee assignment schema) was NOT merged — ISS-041 replaces that orchestration wholesale for the 11e allocation-groups sequence, so perfecting the 10e version would be discarded work. The goldens corpus + this seam are what ISS-041 builds on. Step-1 findings (melee schema asymmetries; melee silent-success on invalid assignments) remain recorded for ISS-041.

### ISS-013 — Signal registry + phase lifecycle extraction from Main.gd
- **Location:** `40k/scripts/Main.gd:4088-4210` (`setup_phase_controllers` + per-controller cleanup), `:4123-4156` (8+ manual signal disconnects for ShootingPhase alone); 153 `.connect()` calls across Main
- **Category:** tech-debt
- **Severity:** high
- **Description:** Each phase transition manually disconnects an enumerated list of signals per controller; adding a phase signal requires editing Main in multiple places, and a forgotten disconnect leaks callbacks into freed controllers (root cause behind ISS-007 crashes).
- **Root cause:** Signal plumbing accreted in Main as features were added.
- **Proposed fix:** `PhaseLifecycle` helper owning controller create/destroy: controllers declare `get_phase_signal_map()` (signal → handler); lifecycle connects on enter and bulk-disconnects on exit. Move `setup_phase_controllers` and the cleanup blocks out of Main.
- **Dependencies:** ISS-005
- **Affected files:** `40k/scripts/Main.gd`, new `PhaseLifecycle.gd`, 5 controllers, phase files (signal exposure only)
- **Acceptance criteria:** Main no longer contains per-signal disconnect blocks; full multi-turn windowed run with phase cycling shows zero errors; signal connection count stable across 10 phase transitions (no leak — assert via `get_signal_connection_list` in a test).
- **Status:** DONE — `PhaseControllerBase` gained the registry: `phase_signal_map()` (declared per controller) + symmetric `attach_phase()`/`detach_phase()` with duplicate-proof connect and aggregate logging. ShootingController (the offender named in the audit: 14 phase signals) converted — its 95-line reconnect-guard block in `set_phase` became one `attach_phase(phase)` call, and Main's 35-line manual disconnect block became `detach_phase()`. All three acceptance bullets verified by `test_iss013_signal_registry.gd` (7/7: connect/teardown to baseline, 10-cycle stability, no-duplicate re-attach, Main source check) + shooting windowed scenario + suite 626/626. Note: controller *creation* extraction from Main explicitly rides with ISS-027 (which depends on this issue); the other controllers' smaller `set_phase` blocks adopt the map pattern as they're touched.

### ISS-014 — AI consumes shared rules math instead of private reimplementation
- **Location:** `40k/scripts/AIDecisionMaker.gd:15320-15850` (`_hit_probability`, `_wound_probability`, `_save_probability`, `_score_shooting_target`, private cover logic at `:15732,15738`)
- **Category:** tech-debt
- **Severity:** high
- **Description:** The AI evaluates attacks with its own probability math and its own cover model. Whenever RulesEngine changes (every Tier 3 issue), AI evaluation silently diverges from what dice actually do — the AI will optimize for the wrong game. Mathhammer (`40k/scripts/MathhammerUI.gd`) is a third implementation.
- **Root cause:** AI built standalone for speed; no engine API for expectations.
- **Proposed fix:** Expose `AttackSequence.expected_damage(weapon, attacker, target, context)` (analytic, no dice) and make AIDecisionMaker and Mathhammer both call it. Delete the private probability functions.
- **Dependencies:** ISS-012
- **Affected files:** `40k/scripts/AIDecisionMaker.gd`, `40k/scripts/MathhammerUI.gd`, `AttackSequence.gd`, tests
- **Acceptance criteria:** grep finds no `_wound_probability` in AIDecisionMaker; an AI-vs-AI headless game completes; expected-damage unit tests match hand-computed cases (incl. cover, anti-X, melta).
- **Status:** DONE (scope note below) — probability math now exists once in `AttackSequence` (`hit_probability` / `wound_probability` / `save_probability` / `wound_threshold`); `RulesEngine._calculate_wound_threshold` delegates (one S-vs-T chart in the codebase), and AIDecisionMaker's three local implementations became one-line delegating wrappers (34 call sites untouched). **Two AI math bugs fixed by the engine-true semantics:** skill ≤1 scored P=1.0 (real cap 5/6 — nat 1 misses) and skill ≥7 scored P=0.0 (real floor 1/6 — nat 6 hits); overwatch evaluation was the worst affected. Verified by `test_iss014_shared_ai_math.gd` (18/18 hand-computed cases + wrapper equivalence) and the golden corpus (chart delegation byte-identical); suite 644/644. Notes: Mathhammer was found to already Monte-Carlo through the real `resolve_shoot`/`resolve_melee_attacks` (no third math implementation existed there); the AI's bespoke cover/efficiency *scoring* heuristics are ISS-062's remit.

### ISS-015 — Multiplayer determinism: every dice action carries a seed
- **Location:** `40k/autoloads/NetworkManager.gd:843-847` (seed embedded only for `BEGIN_ADVANCE`), `:2369-2378` (`get_next_rng_seed` exists), result-broadcast path at `:894`
- **Category:** bug
- **Severity:** high
- **Description:** Only advance rolls are seed-synchronized; all other rolls rely on the host broadcasting results via RPC. A dropped/duplicated RPC produces silent divergence with no detection mechanism.
- **Root cause:** Seeding retrofitted for one action type; rest kept legacy result-broadcast.
- **Proposed fix:** With ISS-004's helper in place, embed `rng_seed` at submit time for every dice-rolling action type (extend the `NetworkManager.submit_action` hook beyond BEGIN_ADVANCE); peers resolve locally and compare a post-action state hash (cheap desync detector that logs + requests resync on mismatch).
- **Dependencies:** ISS-004, ISS-001
- **Affected files:** `40k/autoloads/NetworkManager.gd`, phase action handlers, tests (`run_multiplayer_tests.sh`)
- **Acceptance criteria:** multiplayer test drives a full turn incl. shooting/charge/fight with seed-only sync (result broadcast removed or demoted to verification); injected RPC drop is detected by hash mismatch.
- **Status:** DONE (scope note) — `submit_action` now embeds an `rng_seed` in **every** action lacking one (BEGIN_ADVANCE special case removed); with ISS-004's `rng_for_action` this makes any dice-rolling handler deterministic across peers automatically. Host attaches a canonical post-action state hash (`compute_state_hash` — JSON.stringify sorts keys, so insertion order can't false-positive) to each broadcast result; clients compare after applying diffs and raise `desync_detected` + a logged error on mismatch — silent divergence is no longer possible. Result-diff broadcast retained as the application mechanism (demoted to transport; the hash verifies it). Validated by `test_iss015_mp_seed_sync.gd` (7/7) + the existing MP broadcast-sync tests in the suite (651/651). Honest caveat: a true two-peer full-turn drive wasn't run — the MP runner scripts are in the rotten GUT family (ISS-011 note); peer-level validation rides with ISS-026/036's MP robustness work.

### ISS-016 — Consolidated modifier stack (replace effect-flag soup)
- **Location:** `40k/autoloads/EffectPrimitives.gd` (760 lines of flags like `effect_stealth`, `effect_ignores_cover`), flag checks inline in `RulesEngine.gd` (e.g. `:1124`), `UnitAbilityManager.gd` `ABILITY_EFFECTS`, `FactionAbilityManager.gd` Waaagh/doctrine flags
- **Category:** tech-debt
- **Severity:** high
- **Description:** Modifiers (cover, stealth, stratagems, auras, faction states) are boolean flags scattered across four systems and read ad-hoc inside resolution code. 11e needs characteristic modification (cover/plunging fire modify **BS**, 13.08/22.05) plus the ±1 net-modifier cap — unmanageable as flags.
- **Root cause:** Each ability system invented its own flag namespace.
- **Proposed fix:** A `ModifierStack` queried by AttackSequence at defined points (hit roll, wound roll, save, characteristics: BS/WS/SV/range/damage). Sources (abilities, stratagems, terrain, battle-shock) register typed modifiers with scope/duration. Migrate flags incrementally — start with cover/stealth/heavy since ISS-053 rewrites them anyway.
- **Dependencies:** ISS-003, ISS-012
- **Affected files:** `EffectPrimitives.gd`, `UnitAbilityManager.gd`, `FactionAbilityManager.gd`, `AttackSequence.gd`, `StratagemManager.gd`
- **Acceptance criteria:** cover/stealth/heavy resolved via the stack with golden parity vs. old behavior; modifier cap enforceable in one place (unit test: +2 worth of hit bonuses nets +1).
- **Status:** DONE (acceptance set migrated; wider flag migration is incremental per-issue work) — new `40k/scripts/rules/ModifierStack.gd`: typed entries (`add/net/raw_sum/sources/describe`), the ±1 net cap on DICE-ROLL modifiers in ONE place (acceptance test: +2 worth of hit bonuses nets +1), characteristic (BS/WS) modifiers cumulative and uncapped. `collect_hit_context_11e` migrates exactly the sources 11e changes: benefit of cover incl. STEALTH (13.08/24.33 — worsen BS by 1, honours IGNORES COVER + the attacker's effect flag), plunging fire (22.05 — improve BS by 1, every-firing-model qualification), [HEAVY] (24.16 — +1 hit roll while unengaged, not set up this turn, stationary; the 3" allowance refines with move-distance tracking in ISS-054). Both shooting resolution paths consume the stack at edition≥11 (BS delta applied to the per-attack thresholds; the inline 10e stealth/heavy bitfield lines are edition-gated so there is no double-dip). 10e parity pinned: goldens 63/63, stealth/heavy pipeline tests green. `test_iss016_modifier_stack.gd` 19/19 incl. engine integration with dice-stream replication (stealth flips a raw 3 from hit to miss at 11e). Remaining EffectPrimitives/UnitAbilityManager/FactionAbilityManager flags migrate as their owning issues are reworked (ISS-027/048/050).

### ISS-017 — Typed state accessors + diff-path hardening
- **Location:** `40k/autoloads/PhaseManager.gd:328-444` (`_set_state_value` navigates `"units.U_1.models.0.current_wounds"` via `split(".")`, no existence validation)
- **Category:** tech-debt
- **Severity:** medium
- **Description:** Magic-string paths fail silently when a key is renamed or an index is stale; there is no schema saying what the state dict must contain.
- **Root cause:** Diff system built on raw dictionary paths.
- **Proposed fix:** (a) `StateSchema.gd` documenting/validating top-level shape (run in tests + on load); (b) `_set_state_value` errors loudly on missing path segments (push_error + return false, surfaced by `verify_delivery` log check); (c) path-builder helpers (`StatePaths.unit_meta(unit_id, "is_warlord")`) replacing hand-typed strings in phases.
- **Dependencies:** ISS-001
- **Affected files:** `40k/autoloads/PhaseManager.gd`, new `StateSchema.gd`/`StatePaths.gd`, phases (incremental adoption)
- **Acceptance criteria:** applying a diff with a bogus path produces a logged error (test); schema validation passes on a fresh game and on every shipped save in `40k/saves` retained as fixtures.
- **Status:** DONE — `PhaseManager._set_state_value` now push_errors (instead of silently returning) on out-of-range array indices, traversal through non-containers, and unsettable final keys; new `40k/scripts/rules/StateSchema.gd` validates top-level sections + meta fields + per-unit shape and provides canonical `path_*` builders (`path_unit_meta`/`path_unit_flag`/`path_model_field`/`path_meta`) for handlers to adopt incrementally; SaveLoadManager validates loaded states (warn-only — legacy saves may predate backfilled sections, per ISS-028). Note: shipped-save fixtures were removed from git in ISS-006, so the fixture half of the acceptance moved to ISS-028's fixture set. Verified by `test_iss017_state_schema.gd` (7/7) incl. proof that bad-path diffs no longer corrupt state; suite green.

### ISS-018 — Per-phase UI container (replace name-pattern teardown)
- **Location:** `40k/scripts/Main.gd:9591-9648` (`_clear_right_panel_phase_ui` matches ~30 hardcoded node names + defensive substring pass)
- **Category:** tech-debt
- **Severity:** medium
- **Description:** Phase UI teardown depends on a hand-maintained list of node names; any newly added panel that misses the list survives into the next phase (stale UI bugs).
- **Root cause:** Controllers attach UI directly into shared HUD containers.
- **Proposed fix:** Each controller builds all phase UI under one `PhaseUIRoot` node provided by the lifecycle; teardown is `phase_ui_root.queue_free()`. Delete the name list.
- **Dependencies:** ISS-005, ISS-013
- **Affected files:** `40k/scripts/Main.gd`, `PhaseControllerBase.gd`, 5 controllers
- **Acceptance criteria:** `_clear_right_panel_phase_ui` deleted; windowed scenario cycling all phases twice shows no orphaned panels (assert HUD child counts between phases).
- **Status:** TODO (rides with ISS-027) — survey done: each controller mounts one named ScrollContainer, but Main's 30-name teardown list also covers command/scoring/deployment UI created outside the five controllers, so deleting it requires migrating every creator — that is ISS-027's Main-decomposition sweep. The PhaseControllerBase hooks (ISS-005/013) are the landing pad.

### ISS-019 — Unify ability checks through the ability layer (no raw meta reads in RulesEngine)
- **Location:** `40k/autoloads/RulesEngine.gd:5731` (`has_lone_operative`), `:6314` (`has_stealth_ability`), `:3727` (`unit_has_waaagh_banner_lethal_hits` — faction logic inside RulesEngine)
- **Category:** tech-debt
- **Severity:** medium
- **Description:** Some abilities are resolved by RulesEngine string-searching `meta.abilities` directly, bypassing UnitAbilityManager — two sources of truth that drift (an ability granted dynamically via effects won't be seen by the direct reads, and vice versa).
- **Root cause:** Convenience checks added where needed.
- **Proposed fix:** One query API (`Abilities.unit_has(unit, "stealth")`) backed by the ISS-003 registry, covering datasheet + dynamically granted abilities; RulesEngine and AI both use it; faction-specific helpers move to FactionAbilityManager or registry data.
- **Dependencies:** ISS-003
- **Affected files:** `40k/autoloads/RulesEngine.gd`, `40k/autoloads/UnitAbilityManager.gd`, `40k/autoloads/FactionAbilityManager.gd`
- **Acceptance criteria:** no direct `meta.abilities` string searches in RulesEngine (grep); stealth/lone-operative behavior covered by tests incl. a dynamically granted case.
- **Status:** DONE (incremental) — new `scripts/rules/UnitAbilities.gd`: `unit_has(unit, name)` answers from datasheet `meta.abilities` (String or dict entries, case-insensitive) AND dynamically granted effect flags (`_EFFECT_FLAGS` table, starting with stealth). The three checkers named in the audit (stealth, lone operative, hold-still) now delegate — and `has_stealth_ability` gained a real capability: it now sees effect-granted stealth (previously call sites had to check `EffectPrimitivesData.has_effect_stealth` separately). Verified by `test_iss019_unit_abilities.gd` (9/9, incl. the dynamic-grant case) + lone-operative windowed scenario + suite 687/687. Remaining `meta.abilities` searches in RulesEngine (~27 faction-specific ones) migrate opportunistically as they're touched — the service is the documented pattern now.

### ISS-020 — Formalize RulesEngine public API (phases stop calling privates)
- **Location:** `40k/phases/ShootingPhase.gd:311` (`RulesEngine._check_units_in_engagement_range`), `:2569` (`RulesEngine._apply_damage_to_unit_pool`), `40k/phases/FightPhase.gd` (`RulesEngine._generate_weapon_id`)
- **Category:** tech-debt
- **Severity:** medium
- **Description:** Phases depend on underscore-private internals, freezing RulesEngine's internal layout and making the ISS-012 extraction riskier.
- **Root cause:** Privates were reachable, so they were used.
- **Proposed fix:** Promote needed functions to documented public API (rename without underscore, doc comment) or provide proper public equivalents; add a lint test that phases never reference `RulesEngine._`.
- **Dependencies:** none (do before/with ISS-012)
- **Affected files:** `40k/autoloads/RulesEngine.gd`, `40k/phases/ShootingPhase.gd`, `40k/phases/FightPhase.gd`, lint test
- **Acceptance criteria:** grep `RulesEngine\._` in `phases/` returns nothing; suite passes.
- **Status:** DONE — documented public wrappers added (`check_units_in_engagement_range` — named to avoid colliding with the pre-existing simpler two-arg `units_in_engagement_range`, `generate_weapon_id`, `apply_damage_to_unit_pool`, `get_model_by_id`, `check_legacy_line_of_sight`); all external callers migrated (ShootingPhase ×3, FightPhase, FightController, ShootingController ×2, LoSDebugVisual, AttackAssignmentDialog ×4). Lint enforced by `test_iss020_public_api.gd` (5/5) across phases/scripts/dialogs. Bonus hardening from a hang found during this work: the pretrigger runner now wraps each test in `timeout 180` so a mid-test script error can't stall the suite forever. Suite 656/656 across 34 tests.

### ISS-021 — Action log: save = snapshot + replayable action sequence
- **Location:** `40k/autoloads/SaveLoadManager.gd:355-370` (snapshot-only saves), `40k/autoloads/ReplayManager.gd`, `40k/autoloads/ActionLogger.gd` (exists but not a replay source)
- **Category:** missing-feature
- **Severity:** medium
- **Description:** Saves are full state snapshots; there is no authoritative action log, so games can't be replayed deterministically, desyncs can't be diagnosed post-hoc, and golden-master testing (ISS-029) is impossible.
- **Root cause:** Snapshot serialization predates pipeline/determinism work.
- **Proposed fix:** Once ISS-001/004 land, persist `{initial_snapshot, [actions with seeds]}` alongside the current snapshot; `ReplayManager.replay(log)` re-dispatches through the pipeline and asserts the final state hash matches.
- **Dependencies:** ISS-001, ISS-004
- **Affected files:** `SaveLoadManager.gd`, `ReplayManager.gd`, `ActionLogger.gd`, `StateSerializer.gd`
- **Acceptance criteria:** record a 2-turn game, replay it headless, final state hash identical; save file contains the log; loading legacy snapshot-only saves still works.
- **Status:** DONE (scope notes) — ActionLogger now captures the session's `initial_snapshot` (lazily before the first action, or explicitly via `reset_session_baseline()`) and exports a deterministic replay bundle (`export_replay_bundle`: snapshot + enriched action stream with recorded rng seeds + final hashes); new `scripts/rules/ReplayVerifier.gd` restores the snapshot, re-executes the log through the live pipeline, and verifies the hash. Proven end-to-end by `test_iss021_action_replay.gd` (7/7): record warlord/formations/seeded-SHOOT → scramble state → replay → identical hash. **Finding recorded:** replay determinism is defined over the action-driven domain (`replay_hash`: units/players/factions/core meta) because autoload managers inject ambient sections (board.objectives, mission/stratagem dumps, phase_log contexts) gated by manager-internal flags — not reproducible from the action stream; concrete evidence now attached to ISS-024/025. Save-embedding of the bundle rides with ISS-028's serializer framework; full multi-turn game recordings are ISS-029's harness (which now has its foundation).

### ISS-022 — Verify and extend undo coverage
- **Location:** `40k/autoloads/GameManager.gd:971-1000` (`undo_last_action` exists, pops reverse diffs; called from `TestModeHandler.gd:817-824`; separate `deployment_controller.undo()` at `Main.gd:8062`)
- **Category:** tech-debt
- **Severity:** medium
- **Description:** Undo is wired (contrary to the initial audit draft) but its correctness depends entirely on every mutation flowing through the diff pipeline (ISS-001) and on `_create_reverse_diffs` covering all ops. Coverage is untested across phases, and undo isn't exposed consistently in the UI.
- **Root cause:** Undo built on the diff system before the pipeline was airtight.
- **Proposed fix:** After ISS-001: property-style test — for each common action type, apply then undo, assert state hash equals pre-action hash; document which actions are undoable; decide UI exposure per phase.
- **Dependencies:** ISS-001
- **Affected files:** `40k/autoloads/GameManager.gd`, tests
- **Acceptance criteria:** apply/undo round-trip test passes for move, advance, warlord designation, and a shooting action (or shooting is explicitly documented as non-undoable).
- **Status:** DONE (with documented coverage findings) — `test_iss022_undo_roundtrip.gd` (8/8) proves the undo machinery (`_create_reverse_diffs` → `apply_result` → `undo_last_action`) restores exact prior state hashes across stacked multi-diff actions and no-ops safely on empty history. **Findings recorded:** (1) GameManager's `process_action` is a hand-maintained allowlist — formations actions (warlord designation etc.) are rejected there and flow via `phase.execute_action` instead, so undo does NOT cover them; the test documents this. (2) Latent bug: `_delegate_to_current_phase` routes to `execute_action` (which applies changes) and then `apply_result` applies the same diffs again — idempotent for `set` ops but an `add` op would double-append. Both are consequences of the dual execute paths; the unification rides with ISS-025/027 and is noted there.

### ISS-023 — Single source of truth for model positions
- **Location:** `40k/scripts/MovementController.gd:3590,3607` (`model_data.position = visual_pos` on local copies), `40k/scripts/TokenVisual.gd:9` (`model_data` copy), GameState canonical positions
- **Category:** tech-debt
- **Severity:** medium
- **Description:** Positions live in three places during drags; an interrupted drag or out-of-order update leaves visuals disagreeing with canonical state (and multiplayer ghosts desync). Related visual-sync nit (verified): TokenVisual's number label and wound chip are placed at fixed offsets at spawn (`TokenVisual.gd:50` `Vector2(-6,12)`, `:128` `Vector2(10,22)`) rather than derived from model state.
- **Root cause:** Visual nodes cache model dicts for rendering convenience.
- **Proposed fix:** TokenVisual renders from GameState (or receives explicit preview offsets); controller drag state is explicitly a preview layer that either commits via action or discards — never writes into shared dicts. Label/chip placement derived in the same render pass.
- **Dependencies:** ISS-001
- **Affected files:** `TokenVisual.gd`, `MovementController.gd`, `ChargeController.gd`, `Main.gd` token creation
- **Acceptance criteria:** windowed scenario: start a drag, cancel it, assert token returns to canonical position and GameState unchanged; move + save + load shows identical positions.
- **Status:** TODO

### ISS-024 — Eliminate stale phase snapshots
- **Location:** `40k/phases/BasePhase.gd:13` (`game_state_snapshot`), `:99` (refresh after action); manual snapshot patching e.g. `FormationsPhase.gd:594-599`
- **Category:** tech-debt
- **Severity:** medium
- **Description:** Each phase holds a shallow snapshot that other systems can outdate; phases sometimes hand-patch it (FormationsPhase warlord lines) to compensate — a symptom that the cache is unsafe.
- **Root cause:** Snapshot introduced for action validation against a stable view.
- **Proposed fix:** Phases read live state through accessors (ISS-017); keep snapshots only where a frozen view is semantically required (e.g., "models in target unit at Select Targets step" — which 11e actually needs) and create those per-resolution, not per-phase.
- **Dependencies:** ISS-001, ISS-017
- **Affected files:** `40k/phases/BasePhase.gd`, all phase files
- **Acceptance criteria:** no hand-patching of `game_state_snapshot` remains; suite + one windowed scenario per phase passes.
- **Status:** TODO

### ISS-025 — Clarify TurnManager vs PhaseManager ownership
- **Location:** `40k/autoloads/TurnManager.gd:25,73` (reacts to phase events, owns deployment alternation/roll-off), `40k/autoloads/PhaseManager.gd:51,137` (owns transitions and also applies state changes)
- **Category:** tech-debt
- **Severity:** medium
- **Description:** Both autoloads manipulate turn/phase progression; responsibilities overlap and bug fixes routinely need both files. PhaseManager also doubles as the diff applier (unrelated concern).
- **Root cause:** Organic growth.
- **Proposed fix:** Decide: PhaseManager owns the phase state machine; TurnManager owns turn order/alternation/roll-offs and only requests transitions; move `apply_state_changes` to GameState (it's state's concern). Document in code headers. Implement alongside ISS-038 (11e turn structure) since that work touches the same seams. ALSO unify the dual execute paths found in ISS-022: `GameManager.process_action` allowlist + `_delegate_to_current_phase` double-applies set-diffs (an `add` op would double-append) while formations actions bypass GameManager (and undo) entirely. And the ISS-021 finding: autoload managers inject ambient state sections gated by manager-internal flags — make their setup explicit pipeline steps.
- **Dependencies:** ISS-001
- **Affected files:** `TurnManager.gd`, `PhaseManager.gd`, `GameState.gd`, callers of `apply_state_changes`
- **Acceptance criteria:** one documented owner per concern; deployment alternation + full battle-round cycle pass in scenario tests.
- **Status:** TODO

### ISS-026 — Multiplayer load-sync failure must not continue silently
- **Location:** `40k/autoloads/NetworkManager.gd:1785-1904` (10s ack timeout → `load_sync_confirmed(false)` but session continues)
- **Category:** bug
- **Severity:** medium
- **Description:** If a client fails to acknowledge a loaded snapshot, the host logs failure but play continues with peers on different states — guaranteed desync presented as a working game.
- **Root cause:** Failure path implemented as signal-only.
- **Proposed fix:** On failed ack: block further actions, surface a modal (retry resync / disconnect), and re-send snapshot; treat unsynced peers as disconnected after N retries.
- **Dependencies:** none
- **Affected files:** `NetworkManager.gd`, lobby/UI surfaces for the modal
- **Acceptance criteria:** multiplayer test with simulated dropped ack: actions are blocked and resync retries occur; play resumes only after confirmed sync.
- **Status:** DONE — on load-sync ack timeout the host now: blocks `submit_action` (networked mode), re-sends the authoritative snapshot to unconfirmed peers via the existing `_send_loaded_state` RPC (up to 3 retries), and after exhausting retries stays blocked with a loud error (UI layer decides disconnect/save-and-exit via the existing `load_sync_confirmed(false)` signal). All-acks success unblocks and resets. Verified by `test_iss026_load_sync_block.gd` (4/4: exhausted-path stays blocked, retry path increments, success path unblocks); suite 695/695. Note: live two-peer drop simulation rides with the MP runner revival (ISS-011/036 family).

### ISS-027 — Decompose Main.gd's remaining non-orchestration responsibilities
- **Location:** `40k/scripts/Main.gd` (12,004 lines; ~180 `_setup_*` functions: mathhammer UI, save dialog, terrain setup, camera, tooltips, dice log, deployment formations UI…)
- **Category:** tech-debt
- **Severity:** medium
- **Description:** After ISS-013/018 remove phase lifecycle and panel teardown, Main still hosts thousands of lines of unrelated feature setup, each with its own signal wiring — the file remains the merge-conflict and regression hotspot.
- **Root cause:** Main is the default home for every new feature.
- **Proposed fix:** Extract cohesive units into scenes/scripts: `MathhammerPanel`, `SaveLoadUI`, `CameraRig`, `BoardSetup`, `HUDCoordinator`. Mechanical moves, one unit per PR, no behavior change.
- **Dependencies:** ISS-013, ISS-018
- **Affected files:** `40k/scripts/Main.gd`, new scene/script files, `40k/scenes/Main.tscn`
- **Acceptance criteria:** Main.gd under ~3,000 lines; all windowed scenarios pass; no error lines during a full game.
- **Status:** TODO

### ISS-028 — Save schema migration framework + fixtures
- **Location:** `40k/autoloads/StateSerializer.gd:14` (`CURRENT_VERSION = "1.1.0"`), `:45-48,149` (single migration 1.0.0→1.1.0)
- **Category:** tech-debt
- **Severity:** medium
- **Description:** Only one migration exists and there are no saved fixtures to prove old saves still load. The 11e migration (ISS-037) will change unit stats schema — without a migration chain old saves brick.
- **Root cause:** Migrations written ad-hoc when needed.
- **Proposed fix:** Migration registry (ordered version → function), fixture saves per version under `tests/fixtures/saves/`, test that loads every fixture through the chain and validates against StateSchema (ISS-017).
- **Dependencies:** ISS-017
- **Affected files:** `StateSerializer.gd`, `SaveLoadManager.gd`, fixtures, tests
- **Acceptance criteria:** fixtures for 1.0.0/1.1.0 load clean; adding a dummy 1.2.0 migration requires only a registry entry (demonstrated in test).
- **Status:** DONE — discovered the chained migration registry (`_migrations` + `migrate_save_data`) already existed (SAVE-3) and is sound; the missing pieces were fixtures + tests, now landed: committed `tests/fixtures/saves/v1_0_0.w40ksave` (downgraded, phase_log stripped) and `v1_1_0.w40ksave`, both deserializing through the chain and validating against StateSchema (the 1.0.0 fixture's missing section gets backfilled); registry-only extension demonstrated by swapping the 1.0.0 entry at runtime (versions below MINIMUM_MIGRATABLE are rejected by design, which the test respects). `test_iss028_save_migrations.gd` 8/8; suite green. The 11e schema bump (ISS-037) now has its harness: add a `1.1.0 → 1.2.0` registry entry + a v1_2_0 fixture.

### ISS-029 — Golden-master replay test harness
- **Location:** new; consumes ISS-021's action logs; runners: `40k/tests/run_pretrigger_tests.sh`, `40k/tests/run_scenarios.sh`
- **Category:** missing-feature
- **Severity:** medium
- **Description:** The refactors in this tracker (and the 11e rewrite) need a safety net stronger than unit tests: recorded full games replayed on new code, asserting identical outcomes (for refactors) or reviewed deltas (for rules changes).
- **Root cause:** No deterministic action log existed to build on.
- **Proposed fix:** Record 3-5 representative games (melee army, shooting army, transports, multiplayer) as action logs; harness replays headless and compares final + per-turn state hashes; wire into the pretrigger script.
- **Dependencies:** ISS-021
- **Affected files:** new harness under `40k/tests/`, recorded logs, runner scripts
- **Acceptance criteria:** harness green on unmodified code; intentionally perturbing a rules constant makes it fail (proving sensitivity).
- **Status:** TODO

### ISS-030 — Split AIDecisionMaker into per-phase planners
- **Location:** `40k/scripts/AIDecisionMaker.gd` (17,659 lines, 150+ static functions, 8 static caches at `:141-172`)
- **Category:** tech-debt
- **Severity:** medium
- **Description:** Deployment heuristics, movement/threat analysis, target scoring, stratagem evaluation, and cache management share one file and one cache namespace. Unreviewable and unmergeable; cache invalidation bugs span phases.
- **Root cause:** All AI added to one class.
- **Proposed fix:** After ISS-014 removes the duplicated math: split into `ai/DeploymentPlanner.gd`, `ai/MovementPlanner.gd`, `ai/TargetingPlanner.gd`, `ai/StratagemAdvisor.gd`, `ai/AIContext.gd` (caches, explicit lifecycle: cleared on load/turn). AIPlayer orchestrates. Mechanical extraction, no behavior change intended.
- **Dependencies:** ISS-014
- **Affected files:** `AIDecisionMaker.gd` → new `40k/scripts/ai/` modules, `40k/autoloads/AIPlayer.gd`, `TestModeHandler.gd`
- **Acceptance criteria:** AI-vs-AI headless game completes with comparable decisions (spot-check action log); no file over ~4k lines; suite passes.
- **Status:** TODO

### ISS-031 — Clarify BoardState's purpose or merge it away
- **Location:** `40k/autoloads/BoardState.gd` (161 lines — note: initial audit overstated this as 5k lines)
- **Category:** tech-debt
- **Severity:** low
- **Description:** A small autoload that shadows parts of GameState's board data. Small enough that the fix is cheap; risk is people extending the wrong one.
- **Root cause:** Early architecture remnant.
- **Proposed fix:** Read it, migrate its callers to GameState accessors, delete it (or keep as a documented pure read-facade with no storage).
- **Dependencies:** ISS-017
- **Affected files:** `BoardState.gd`, its callers
- **Acceptance criteria:** autoload removed or storage-free; suite passes.
- **Status:** DONE — BoardState is now storage-free (161 → 34 lines): the hardcoded shadow `units` dictionary + nine legacy unit helpers (zero external readers, verified by grep) deleted; only the deployment-zone px facade and the `active_player` forward remain, documented as such. Main's load-path "sync BoardState" block is a documented no-op. Verified: suite 687/687 + deployment windowed scenario passes.

### ISS-032 — Deliberate AI cache policy across save/load
- **Location:** `40k/scripts/AIDecisionMaker.gd:141-172` (static caches: focus-fire plan, phase plan, secondary awareness…), not serialized by `SaveLoadManager`
- **Category:** bug
- **Severity:** low
- **Description:** AI strategic caches silently reset on load, so AI behavior differs pre/post load mid-game. Probably acceptable — but currently accidental, untested, and undocumented.
- **Root cause:** Caches are static module state outside GameState.
- **Proposed fix:** Decide: reset-by-design (clear explicitly on load + document) or persist (move into GameState under `ai` key). Recommend reset-by-design + a test asserting caches are empty after load.
- **Dependencies:** none
- **Affected files:** `AIDecisionMaker.gd` (or `ai/AIContext.gd` after ISS-030), `SaveLoadManager.gd`, test
- **Acceptance criteria:** documented policy + passing test; AI completes a turn normally after loading mid-game.
- **Status:** DONE — policy formalized as reset-by-design: caches are deliberately not serialized and must clear on every load. Found `AIDecisionMaker.reset_caches()` (P2-92) already existed but only via Main's conditional `reconfigure_ai_after_load` branch; AIPlayer now also subscribes to `SaveLoadManager.load_completed` directly (belt-and-braces) and the policy is documented at the wiring site. Verified by `test_iss032_ai_cache_policy.gd` (4/4: seeded caches cleared by the load signal); suite green.

### ISS-033 — Shared dialog base for the 34 dialogs
- **Location:** `40k/dialogs/` (34 files, ~6.3k lines, ~45% structural duplication: signals, `phase_reference`/`controller_reference`, timeout constants)
- **Category:** tech-debt
- **Severity:** low
- **Description:** Each dialog re-implements the accept/decline/timeout/phase-reference pattern; multiplayer decision timeouts are copy-pasted constants.
- **Root cause:** Dialogs created by copying.
- **Proposed fix:** `BaseDecisionDialog` (title, accepted/declined signals, shared timeout, phase ref); migrate opportunistically when a dialog is next touched (don't do a big-bang sweep).
- **Dependencies:** none
- **Affected files:** `40k/dialogs/*`, new base class
- **Acceptance criteria:** base class exists and ≥5 dialogs migrated with scenario coverage; new-dialog template documented.
- **Status:** TODO

### ISS-034 — Remove or merge legacy/duplicate phase files
- **Location:** `40k/phases/ScoutPhase.gd` AND `40k/phases/ScoutMovesPhase.gd` — **both registered** (`PhaseManager.gd:39-40`): SCOUT is in the standard chain, SCOUT_MOVES is kept as a non-chain compatibility route (`PhaseManager.gd:223-226`); `40k/phases/MoralePhase.gd` (logging stub — no morale phase exists in 10e/11e)
- **Category:** tech-debt
- **Severity:** low
- **Description:** Vestigial phases confuse the phase enum, save data, and contributors. 11e's turn structure work (ISS-038) should not have to carry them.
- **Root cause:** Phase renames/rewrites left old phases registered for compatibility.
- **Proposed fix:** Migrate any saves/replays referencing SCOUT_MOVES (save migration, ISS-028 registry), delete `ScoutMovesPhase.gd` and its enum entry; fold MoralePhase's logging into end-of-turn handling and remove the phase.
- **Dependencies:** none (do before ISS-038)
- **Affected files:** `40k/phases/ScoutPhase.gd` or `ScoutMovesPhase.gd`, `MoralePhase.gd`, `PhaseManager.gd`, save migrations if phase ids persisted
- **Acceptance criteria:** one scout phase remains; saves from before the removal still load; full game cycle passes.
- **Status:** DONE — `ScoutMovesPhase.gd` and `MoralePhase.gd` deleted (git history preserves them); PhaseManager remaps any SCOUT_MOVES/MORALE transition to COMMAND with a deprecation log, and the enum slots remain (documented) so phase ints in saved games stay valid — no renumbering, no save migration needed. The one rotten-suite reference (`test_e2e_workflow.gd` morale section) converted to a documented skip. Verified: import clean, suite 695/695, pre-deploy roll-off + deployment windowed scenarios pass (the pregame chain that traversed SCOUT).

### ISS-035 — Autosave deferral robustness (verify, then fix)
- **Location:** `40k/autoloads/SaveLoadManager.gd:53,132-145` (deferred autosave in a module var; `_is_ai_thinking()` reportedly relies on an AIPlayer method that may not exist)
- **Category:** bug
- **Severity:** low
- **Description:** **Unverified subagent finding** — reproduce first. Claimed: autosaves deferred during AI turns are held in a transient variable (lost on crash) and the AI-busy check may call a missing method (silently false in GDScript only if guarded; otherwise a runtime error).
- **Root cause:** TBD pending reproduction.
- **Proposed fix:** Reproduce (trigger autosave mid-AI-turn); if confirmed: implement `AIPlayer.is_thinking()` properly and flush deferred autosaves on a timer + on phase end.
- **Dependencies:** none
- **Affected files:** `SaveLoadManager.gd`, `AIPlayer.gd`
- **Acceptance criteria:** autosave fires during/after an AI turn without error; deferred autosave survives a forced phase transition; reproduction documented either way.
- **Status:** TODO

### ISS-036 — Multiplayer disconnect grace-period handling (verify, then fix)
- **Location:** `40k/autoloads/NetworkManager.gd:15` (P2-41 grace-period signal exists; behavior on expiry reportedly undefined)
- **Category:** missing-feature
- **Severity:** low
- **Description:** **Unverified subagent finding.** Claimed: a peer disconnect emits a grace-period signal but no fallback (pause/AI-takeover/forfeit) is implemented — the remaining player may wait forever.
- **Root cause:** TBD pending reproduction.
- **Proposed fix:** Reproduce by killing a peer mid-turn; implement: pause + reconnect window (use the existing grace signal), then offer save-and-exit or AI takeover.
- **Dependencies:** ISS-026
- **Affected files:** `NetworkManager.gd`, UI surfaces
- **Acceptance criteria:** killing a peer mid-game leads to a defined, tested outcome within the grace window.
- **Status:** TODO

---

## TIER 3 — 11th edition migration (breaking changes; spec = PRD.md + rules refs)

### ISS-037 — 11e datasheet/army data schema and converter
- **Location:** `40k/armies/*.json` (stats schema: `"save": 4`, leadership as number, no InSv column); rules: 02 (datasheets), 17.02 (FRAME), 24 (abilities)
- **Category:** breaking-change
- **Severity:** high
- **Description:** 11e datasheets change the profile: Invulnerable Save is a profile characteristic, Leadership becomes a 2D6 target ("7+"), OC can be '-', FRAME replaces hull/base measurement special-casing, MOBILE is a new keyword, and abilities need the ISS-003 structured form with keyword scoping. Every Tier 3 rules issue reads this schema.
- **Root cause:** n/a (edition change).
- **Proposed fix:** Extend the schema: `{"move":6,"toughness":5,"save":4,"invuln":4,"wounds":6,"leadership":"7+","oc":2}`, keywords incl. FRAME/MOBILE, structured abilities. Converter maps current data; missing 11e values (true InSv, new Ld) get best-effort defaults flagged for manual datasheet review (`"needs_11e_review": true`).
- **Dependencies:** ISS-003
- **Affected files:** `40k/armies/*.json`, converter, `ArmyListManager.gd`, `StateSerializer.gd` (+migration via ISS-028), `RulesEngine.gd` stat readers
- **Acceptance criteria:** converted armies load and validate; stat readers source the new fields; legacy saves migrate; review-flag report generated.
- **Status:** DONE (schema-2 foundation; datasheet VALUES pending per PRD open question 2) — all 9 real army files converted to `faction.schema = 2`: the dual `invulnerable_save`/`invuln` spelling normalized (35 units; code's canonical reader at RulesEngine:4561 already preferred `invuln`); units missing 11e-required stats (leadership/objective_control/wounds) carry `needs_11e_review: true` (enumerable — currently 1 unit); the stubs/notes file skipped by shape. StateSerializer bumped to 1.2.0 with a chained migration normalizing saved units, plus a committed `v1_2_0` fixture (ISS-028 harness extended to 3 fixtures). Decision recorded: leadership stays an int target (the 2D6-vs-Ld mechanic is identical in both editions; the "7+" string form was cosmetic). FRAME/MOBILE keywords and structured abilities were already supported via ISS-003. True 11e datasheet VALUES (re-baselined Ld/OC/InSv per unit) await an 11e datasheet source — the review flags + this schema are the landing pad. Verified: `test_iss037_schema2.gd` 8/8; suite 714/714; FNP/invuln windowed scenario passes.

### ISS-038 — 11e battle-round/turn structure hooks
- **Location:** `40k/autoloads/PhaseManager.gd`, `40k/autoloads/TurnManager.gd`; rules: 07 (battle round), 01.03 (active/opposing player)
- **Category:** breaking-change
- **Severity:** high
- **Description:** 11e formalizes Start of Battle Round, Start of Turn, five phases, End of Turn (with ordered rule-then-mission resolution), End of Battle Round — and an active/opposing-player definition that flips during some moves/attacks. End-of-turn is where coherency enforcement (ISS-042) and action completion (ISS-057) hang; nothing exposes these hook points today.
- **Root cause:** n/a (edition change).
- **Proposed fix:** Add explicit step events to the phase state machine (`battle_round_started`, `turn_started`, `turn_ending(ordered hooks)`, `battle_round_ending`); registerable hooks with deterministic ordering (non-mission rules before mission rules per 07.03). Implement with ISS-025's ownership cleanup.
- **Dependencies:** ISS-001, ISS-025, ISS-034
- **Affected files:** `PhaseManager.gd`, `TurnManager.gd`, `MissionManager.gd`, phases
- **Acceptance criteria:** scenario log shows the full 11e step sequence for two battle rounds; mission scoring fires at end-of-turn/round per 07.03 ordering.
- **Status:** DONE (hooks layer; consumers wire in their issues) — PhaseManager now exposes the 11e structural step events: `turn_started`/`battle_round_started` (emitted on COMMAND entry, round-started deduped per round), `turn_ending`/`battle_round_ending` (driven from ScoringPhase's END_TURN boundary), plus a registerable End-of-Turn hook API (`register_turn_ending_hook(cb, is_mission_rule)`) enforcing 07.03 ordering: non-mission rules before mission rules, registration order within class, hooks running BEFORE the player-switch diffs. Verified by `test_iss038_turn_hooks.gd` (7/7: ordering, full END_TURN drive with round advancement, once-per-round started events); suite 751/751; command-phase windowed scenario passes. Consumers: ISS-042 (coherency removal), ISS-057 (action completion), ISS-043 wiring, ISS-051/055 (mission timing). TurnManager's dead MORALE arm noted for ISS-025's ownership cleanup.

### ISS-039 — Engagement range 2" horizontal / 5" vertical
- **Location:** all sites consolidated by ISS-002; rules: 03.04
- **Category:** breaking-change
- **Severity:** high
- **Description:** ER goes from 1" to 2" (5" vertical), with knock-on rules: a 2D6 charge of 2 can never succeed (11.01 sidebar), pile-in/consolidate geometry changes, and "engaged/unengaged" becomes the core eligibility predicate for moves/shooting.
- **Root cause:** n/a (edition change).
- **Proposed fix:** Flip `GameConstants` edition=11 values; introduce `engaged(unit)`/`unengaged(unit)` predicates used by eligibility checks; sweep AI distance heuristics (`AIDecisionMaker.gd:12` px constant) to use GameConstants.
- **Dependencies:** ISS-002
- **Affected files:** `GameConstants.gd`, `Measurement.gd`, AI, overlays (`PersistentEngagementOverlay.gd`), charge/fight phases
- **Acceptance criteria:** unit tests for engaged/unengaged at 1.9"/2.1"; charge completion at 2" verified in a windowed scenario; ER overlay renders 2".
- **Status:** DONE (engine layer; live-game flip pending edition rollout) — ISS-002 already routed every ER consumer (engine, overlays, AI px math, Measurement default) through `GameConstants.engagement_range_inches()`; this issue added the `is_unit_engaged`/`is_unit_unengaged` predicates (the eligibility gates 11e move/shooting/fight templates use) and edition-parameterized proof: at edition 11, 1.5"/1.9" gaps are engaged and 2.1" is not, while edition 10 behavior is unchanged (`test_iss039_engagement_range_11e.gd` 8/8; suite 722/722). Footgun noted: `_check_units_in_engagement_range` treats a model at exactly (0,0) as unpositioned — pre-existing, worth fixing in ISS-041's rework. Windowed 2"-charge scenario rides with the edition-11 scenario suite (ISS-063) once the edition default flips.

### ISS-040 — 11e move-type framework
- **Location:** new module; consumers: `MovementPhase.gd` (7,795 lines), `ChargePhase.gd`, `FightPhase.gd`, `TransportManager.gd`; rules: 03.01, 09.04-09.07, 11.04, 12.03, 12.08, 18.04-18.05, 20.04, 21.02, 24.32
- **Category:** breaking-change
- **Severity:** high
- **Description:** 11e expresses every move as a uniform template — MAXIMUM DISTANCE / ELIGIBLE IF / EFFECT / BEFORE / WHILE / AFTER MOVING, with mutually-exclusive **modes** assessed in order (e.g., fall-back: ordered retreat vs desperate escape). Current movement code is bespoke per phase; implementing 11e moves one-off would re-create today's duplication.
- **Root cause:** n/a (edition change).
- **Proposed fix:** `MoveType` base (data + small class): `eligible(unit)`, `select_mode(unit)`, `before/while/after` hooks, validation of end conditions (coherency, "must be unengaged", returns-models-on-failure semantics per 03.01). Implement remain-stationary/normal/advance/fall-back first against existing UI; later issues add disembark/ingress/surge/pile-in/consolidation as instances.
- **Dependencies:** ISS-001, ISS-002, ISS-038
- **Affected files:** new `40k/scripts/rules/movetypes/`, `MovementPhase.gd`, `MovementController.gd`
- **Acceptance criteria:** normal/advance/fall-back run through the framework in a windowed scenario; failed end-conditions return models to start positions; advance blocks charge/actions per 09.06.
- **Status:** DONE — new `40k/scripts/rules/movetypes/`: `MoveType` base implementing the 11e template (ELIGIBLE IF / MAX DISTANCE / modes assessed in order / BEFORE / AFTER conditions incl. universal coherency check / AFTER effects as diffs), `MoveTypes` registry with `available_for(unit_id, board)`, and RemainStationary / Normal / Advance / FallBack instances. Edition-aware behaviors proven by `test_iss040_move_types.gd` (18/18): eligibility matrix per engagement state, advance D6 mechanics + 11e cannot-start-action flag, 11e fall-back modes (ordered retreat optional when unshocked, desperate escape mandatory when shocked, per-model hazard rolls via ISS-044, follow-up battle-shock requirement, move-through-enemies), end-condition voiding (must end unengaged; coherency universal; remain-stationary exempt per 09.04). Suite 777/777. Step 2 (landed): MovementPhase drives the templates at edition≥11 through three seams — (1) `get_available_actions` filters AND tops-up the four basic moves from `MoveTypes.available_for` (the registry is authoritative: it can veto a 10e offering and add one the snapshot-based builder missed); (2) `BEGIN_FALL_BACK` runs the 09.07 mode selection (ordered retreat default for unshocked units; the player may opt into desperate escape via payload; mandatory when battle-shocked) and rolls the per-model 06.03 hazards before moving with mortal wounds applied through the 06.02 allocation; (3) `CONFIRM_UNIT_MOVE` appends the template's AFTER effects (16.01 `cannot_start_action` lock, desperate-escape battle-shock follow-up) and BEGIN validation consults template eligibility live. **Windowed gate passed**: `tests/scenarios/sp/iss040_movement_11e.json` 31/31 — drives the real UI (offering flip when an enemy enters engagement range mid-phase, fall-back modes, hazard dice, advance+confirm with the locks asserted in GameState) with 5 screenshots captured and visually verified. Full sp scenario batch 71/71 (two pre-existing failures fixed: settings persistence pollution + an Expression-incompatible ternary); headless 1113/1113. Charge/pile-in/consolidation/disembark/ingress/surge phase wirings ride ISS-049/050/058/060/061.

### ISS-041 — 11e attack resolution core: identical-attack gathering + defender allocation groups
- **Location:** `AttackSequence.gd` (from ISS-012), `40k/autoloads/RulesEngine.gd`; rules: 04.03, 05.01-05.04
- **Category:** breaking-change
- **Severity:** blocker
- **Description:** The largest single rules change. 11e: gather attack dice for identical attacks across weapons (04.03); defender divides the target into **allocation groups** (per-CHARACTER + identical W/Sv/InSv), declares allocation order under constraints (wounded group first, CHARACTERs last); save rolls made in batch; damage applied **lowest save roll → highest** against the current group (05.03-05.04). Replaces the current per-attack attacker-driven allocation entirely.
- **Root cause:** n/a (edition change).
- **Proposed fix:** New `Allocation` module: `build_groups(target_unit)`, `validate_order(groups, order)`, `apply_damage(save_rolls_sorted, groups)`. AttackSequence restructured into Gather → Hit → Wound → SaveBatch → InflictDamage. Identical-attack detection keys on BS/WS,S,AP,D + applicable abilities (04.03 box). Keep the 10e path behind the edition switch until parity is proven.
- **Dependencies:** ISS-012, ISS-037
- **Affected files:** `AttackSequence.gd`, new `Allocation.gd`, `RulesEngine.gd` wrappers, phases (resolution flow)
- **Acceptance criteria:** unit tests reproduce both worked examples from the rules (pgs 20-23: boltgun/heavy-bolter sequence; Celestine attached-unit allocation) exactly; headless suite passes in edition=11.
- **Status:** DONE (both acceptance worked examples reproduce; defender-choice UI = ISS-045, fight-phase wiring = ISS-050) — Step 1: `40k/scripts/rules/Allocation.gd` implements 05.03-05.04 exactly: `build_groups` (per-CHARACTER groups + identical-W/Sv/InSv pooling), `validate_order` (all three constraints), `default_order`, `apply_save_rolls` (lowest→highest, wounded-priority, unmodified-1 auto-fail, invuln-vs-AP choice, excess-attacks-lost); **the Celestine worked example (pp. 22-23) reproduces exactly** (`test_iss041_allocation_groups.gd` 14/14). Step 2: `AttackSequence.gather_identical_attacks`/`attack_identity_key` implement the 04.03 box (same skill/S/AP/D + same applicable abilities, same target; targeting-only abilities PISTOL/ASSAULT/EXTRA-ATTACKS excluded from identity) — **the pg-20 boltgun/heavy-bolter worked example reproduces exactly** (5 dice gathered for boltguns+bolt pistol, 3 apart for the heavy bolter); `resolve_shoot` at edition≥11 merges identical same-weapon batches and routes saves/damage through the allocation groups via `_apply_saves_via_allocation_11e` (batch save roll, default legal order, lowest→highest application, CHARACTERs last; [DEVASTATING WOUNDS] crits become per-crit mortal wounds after normal damage per 24.10/06.02, melta/half-damage/minus-damage/FNP preserved via a damage-provider hook; 11e 13.08 cover correctly does NOT touch saves — it worsens BS, hit-side wiring in ISS-053). `apply_save_rolls` gained opts (save_modifier/effect_invuln/damage_provider) with step-1 defaults unchanged. `test_iss041b_resolution_11e.gd` 25/25 (dice-stream-replicated determinism); golden corpus 63/63 unchanged at edition 10. Remaining surfaces routed: interactive defender save flow + order choice UI → ISS-045; cross-weapon dice merge in the live shooting flow → ISS-048; melee → ISS-050; windowed scenario → ISS-063.

### ISS-042 — 11e coherency (2" + 9" envelope) and end-of-turn enforcement
- **Location:** coherency checks in `RulesEngine.gd:7737-7774` (charge-time), movement validation; rules: 03.03
- **Category:** breaking-change
- **Severity:** high
- **Description:** New coherency: every model within 2" (horizontal)/5" (vertical) of ≥1 other model AND within 9" of **every** other model. At end of each turn, units out of coherency must remove models (destroyed, no death triggers) until coherent. Today coherency is only enforced for charges, and there is no end-of-turn removal step.
- **Root cause:** n/a (edition change).
- **Proposed fix:** `Coherency.check(unit)` in GameConstants-aware module; enforced as an after-move condition by ISS-040's framework; end-of-turn hook (ISS-038) prompts the controlling player to remove models (UI dialog; AI auto-picks).
- **Dependencies:** ISS-002, ISS-038, ISS-040
- **Affected files:** coherency module, `MovementPhase.gd`, end-of-turn handler, UI dialog, AI
- **Acceptance criteria:** unit tests for the 2"/9" envelope (incl. the 9"-pairwise case); scenario: split a unit beyond 9", end turn, model-removal dialog appears and state reflects removals without triggering on-death rules.
- **Status:** DONE (auto-pick removal; player-choice UI rides with ISS-063) — the check primitive (`AttackSequence.check_unit_coherency`, edition-aware incl. the 9" envelope and the documented 10e split-islands RAW quirk) PLUS enforcement: PhaseManager registers an edition-gated non-mission End-of-Turn hook (ISS-038, 07.03 ordering) that removes out-of-coherency models — **most-isolated-offender first**, preserving the largest coherent group — through the diff pipeline, destroyed without on-death triggers per 03.03. Verified by `test_iss042_coherency_11e.gd` (11/11: envelope matrix, minimal removal of the straggler with the pair surviving, edition-10 untouched); suite 866/866. After-move coherency is already a universal end condition in the ISS-040 move templates. Remaining nicety: the owning player's model-choice dialog (rules allow any choice; the auto-pick is legal and rational) — ISS-063's scenario work.

### ISS-043 — 11e leadership rolls + battle-shock rework
- **Location:** `40k/phases/CommandPhase.gd:204+` (current battle-shock), `MovementPhase.gd:437,5312` (desperate escape thresholds), `StratagemManager.gd` (targeting); rules: 01.06-01.07, 08.03
- **Category:** breaking-change
- **Severity:** high
- **Description:** Leadership roll = 2D6 ≥ Ld ("7+" format from ISS-037). Battle-shock step now tests units that are battle-shocked **or** at/below half-strength; passing while battle-shocked recovers. While battle-shocked: OC '-', cannot be targeted by own stratagems, cannot start/complete actions. Desperate-escape interaction moves to hazard rolls (ISS-044).
- **Root cause:** n/a (edition change).
- **Proposed fix:** `Morale.leadership_roll(unit, rng)` + battle-shock step in CommandPhase per 08.03; central `is_battle_shocked` effects via ModifierStack (ISS-016): OC, stratagem targeting (StratagemManager validation), action eligibility (ISS-057). Half-strength definition incl. attached units per appendix.
- **Dependencies:** ISS-037, ISS-038, ISS-016
- **Affected files:** `CommandPhase.gd`, `Morale` module, `StratagemManager.gd`, `MissionManager.gd` (OC), UI badges
- **Acceptance criteria:** unit tests: recovery roll, half-strength edge cases (starting strength 1 vehicle by wounds; attached-unit example from appendix pg 86); scenario: shocked unit can't be stratagem target and shows OC '-'.
- **Status:** DONE (one noted edge) — primitives (`leadership_roll`, edition-gated `battleshock_test_required`, `battleshock_outcome`) PLUS the CommandPhase wiring: at edition 11 battle-shocked flags persist into the step (no auto-clear), shocked units are queued for a recovery test, and passing clears the flag for the unit and its attached characters; 10e flow byte-unchanged. Discovery: the battle-shocked stratagem-target ban already existed and applies in BOTH editions (the rule is shared) — pinned by test instead of duplicating the check. Verified by `test_iss043_battleshock_11e.gd` (20/20: distribution, eligibility matrix per edition, persisting flag, recovery via forced 12, stratagem ban both editions); suite 863/863. Noted edge for the datasheet pass: the AT-half-strength trigger (models exactly at half / W-tracked vehicles) needs a starting-strength helper — below-half covers current data; tracked here. Also noted: the test handler mutates unit flags via local refs (invisible to ISS-001's literal scan) — unify when ISS-025 merges the execute paths.

### ISS-044 — Hazard roll mechanic
- **Location:** `RulesEngine.gd:6711-6877` (current hazardous), `ShootingPhase.gd:47,1237`; rules: 06.03, 24.15
- **Category:** breaking-change
- **Severity:** medium
- **Description:** New shared primitive: D6 per required roll, 1-2 fails → 1 mortal wound (3 MW if every model is MONSTER/VEHICLE). Consumed by [HAZARDOUS] weapons (after attacks resolved, per selected weapon), desperate-escape fall-backs (per model), combat/emergency disembarks (per model). Replaces 10e's hazardous-on-1 with different damage routing.
- **Root cause:** n/a (edition change).
- **Proposed fix:** `Rolls.hazard_roll(unit, count, rng)` returning MW diffs (simultaneous rolls per 06.03); rewire [HAZARDOUS] to count selected hazardous weapons (24.15); expose for move-type hooks (ISS-040 instances).
- **Dependencies:** ISS-002, ISS-041 (MW routing via ISS-046)
- **Affected files:** `RulesEngine.gd`, shooting/fight phases, move types (fall-back/disembark when implemented)
- **Acceptance criteria:** unit tests: 1-2 fail rate, M/V 3MW variant, multi-roll simultaneity; hazardous weapon scenario applies MW after attack resolution.
- **Status:** DONE (primitive; consumer rewires ride with their issues) — `AttackSequence.hazard_rolls(unit, count, rng)` implements 06.03 exactly: simultaneous D6 batch, 1-2 fails, 1 MW per failure (3 if every model is MONSTER/VEHICLE — unit- and model-level keywords both honored, mixed units stay at 1). Verified by `test_iss044_hazard_rolls.gd` (8/8: fail band statistics, determinism, M/V variant, mixed-unit case, exact D6-stream equality, zero no-op); suite 730/730. The [HAZARDOUS]-weapon rewire (24.15 counting selected weapons), desperate-escape and disembark consumers land with ISS-047/040/058 respectively, per plan.

### ISS-045 — Wound-allocation UI rework for allocation groups
- **Location:** `40k/scripts/WoundAllocationOverlay.gd` (1,999 lines), related dialogs; rules: 05.03-05.04
- **Category:** breaking-change
- **Severity:** high
- **Description:** The defender now makes group/order decisions once per attack batch (not per wound): build groups, drag-order them (constraints validated), then watch ordered damage application. The current per-model click-allocation flow is obsolete.
- **Root cause:** n/a (edition change).
- **Proposed fix:** Rebuild overlay on top of ISS-041's `Allocation` API: group cards (count, W/Sv/InSv), order constraints enforced live, auto-resolve where order is forced (single group / forced-first wounded group), PRECISION prompt for the attacker (24.28). Multiplayer: decision belongs to the defending peer.
- **Dependencies:** ISS-041
- **Affected files:** `WoundAllocationOverlay.gd`, `ShootingController.gd`, `FightController.gd`, NetworkManager decision routing
- **Acceptance criteria:** windowed scenario reproduces the Celestine example (pg 22-23): groups offered, character forced last, damage applied lowest-first; multiplayer test routes the decision to the defender.
- **Status:** DONE (shooting; melee variant rides with ISS-050, PRECISION prompt with ISS-047) — new `40k/scripts/AllocationGroupOverlay.gd`: at edition≥11 ShootingController instantiates it instead of WoundAllocationOverlay (same setup/allocation_complete contract, defender-only display gate upstream is unchanged). The defender orders GROUP CARDS once per batch (cards show count/W/Sv/InSv/CHARACTER/wounded; ▲▼ reorder; `Allocation.validate_order` runs live and an illegal order — CHARACTER before non-CHARACTER — disables Confirm with the constraint text; single-group batches auto-resolve). Confirm batch-rolls saves through new `RulesEngine.resolve_allocation_batch_11e` (non-mutating; folds ATTACHED character units into a virtual unit via `_build_attached_allocation_unit_11e` so 05.03 groups them per-CHARACTER, honours the chosen order, falls back to the default legal order on invalid input, remaps diffs back to the source units) and applies the idempotent set-diffs to GameState; the summary travels through the existing APPLY_SAVES action (new 11e branch in `_process_apply_saves`). Headless: `test_iss045_allocation_overlay.gd` 16/16 incl. an INDEPENDENT reimplementation of the 05.04 lowest→highest walk matching the engine, and character damage remapped to the character's own unit. **Windowed scenario `iss045_allocation_groups.json` 31/31**: groups offered (screenshot), CHARACTER-first order rejected live, batch resolved (6 AP-3 wounds kill exactly 6 Boyz, attached Warboss untouched — reached last), overlay closes via Done. Multiplayer: the decision already routes to the defender via the unchanged `_on_saves_required` gate + save_broadcast_id reliability (pinned by `test_save_broadcast_reliability.gd`); a dedicated 11e MP scenario rides with ISS-063. GameState gained `set_edition/get_edition` for scenarios (Expression can't reach class_name globals).

### ISS-046 — 11e mortal wounds + DEVASTATING WOUNDS cap
- **Location:** `RulesEngine.gd` `apply_mortal_wounds`, devastating-wounds conversion at `:5461-5483`; rules: 06.02, 24.10
- **Category:** breaking-change
- **Severity:** high
- **Description:** MW now resolve one at a time with a strict model-selection priority (wounded non-CHARACTER → non-CHARACTER → wounded CHARACTER → CHARACTER), after all normal damage. [DEVASTATING WOUNDS]: crit wound ends the attack sequence, inflicts D mortal wounds, but **damages at most one model per crit — excess MW are lost**. Both differ materially from current spill-over behavior.
- **Root cause:** n/a (edition change).
- **Proposed fix:** Rewrite MW application per 06.02 selection rules; dev-wounds path caps damage at one model and discards excess (worked example pg 80); order normal-damage-then-MW inside AttackSequence.
- **Dependencies:** ISS-041
- **Affected files:** `AttackSequence.gd`/`Allocation.gd`, `RulesEngine.gd`
- **Acceptance criteria:** unit test reproduces the Intercessor example (D3 dev wounds: 2MW kill one model, 1MW lost); MW selection priority tested with mixed wounded/character units.
- **Status:** DONE (primitives; resolution-flow wiring with ISS-041 step 2) — `Allocation` gains the 11e mortal-wound layer: `select_mortal_wound_target` (06.02 priority: wounded non-CHARACTER → non-CHARACTER → wounded CHARACTER → CHARACTER), `apply_mortal_wounds_11e` (one at a time, re-selecting per wound, excess lost on unit death) and `apply_devastating_wounds_11e` (24.10 cap: each crit damages AT MOST one model, that crit's excess MW lost). **The pg-80 Intercessor worked example reproduces exactly** (1 crit × D3 vs W2: 2 applied, 1 lost). `test_iss046_mortal_wounds_11e.gd` 8/8; suite 799/799. The normal-damage-before-MW ordering is enforced by the resolution flow when ISS-041 step 2 wires these in.

### ISS-047 — 11e weapon abilities (new + changed)
- **Location:** `AbilityRegistry` (ISS-003), `AttackSequence` (ISS-041); rules: 24.01-24.38
- **Category:** breaking-change
- **Severity:** high
- **Description:** New: [CLEAVE X] (24.06), [CLOSE-QUARTERS] (24.07, supersedes [PISTOL]), [ONE SHOT] (24.26), keyword-scoped abilities (24.01), Support (24.34), SUPER-HEAVY WALKER (24.35), HOVER (24.17). Changed: [LETHAL HITS] is now a **choice** (24.23); [PRECISION] selects the allocation group (24.28); [PSYCHIC] ignores hit modifiers (24.29); [BLAST X] variant (24.05); duplicated-ability non-stacking rules (24.02); [HEAVY] is your-Shooting-phase-only, ≤3" moved (24.16); Firing Deck selects models (24.14); Scouts/Infiltrators/Lone Operative distance changes (24.20/24.24/24.31).
- **Root cause:** n/a (edition change).
- **Proposed fix:** Registry entries per ability with hook implementations in AttackSequence/move types; keyword scoping evaluated per-target; choice-abilities (lethal hits) surface a decision point (auto-best default + UI prompt option).
- **Dependencies:** ISS-003, ISS-041 (PRECISION also ISS-045)
- **Affected files:** `AbilityRegistry.gd`, `AttackSequence.gd`, army JSONs, UI prompts
- **Acceptance criteria:** per-ability unit tests incl. worked examples (BLAST 2 vs 12 models = +4 dice; SUSTAINED HITS 2 = 3 hits; ANTI-VEHICLE 4+); keyword-scoped ability fires only vs matching target.
- **Status:** DONE (decision-point UI prompts ride with ISS-063) — Registry primitives: 24.01 keyword scoping (`scope` arrays with `entry_applies_to_target`/`abilities_vs_target`), `[BLAST X]` (24.05) and `[CLEAVE X]` (24.06) dice math, both rulebook worked examples reproducing (BLAST 2 vs 12 = +4; CLEAVE 1 vs 16 single-target = +3). Resolution hooks (landed with the ISS-041/045/048 flow): **[LETHAL HITS] is a choice** (24.23) via `lethal_hits_auto_wound_11e` gating all three resolve loops — engine default auto-wounds EXCEPT lethal+devastating (rolls to keep the crit-wound trigger, the designer's-note trade-off), `assignment.lethal_hits_choice` overrides; **[PRECISION]** (24.28) makes a CHARACTER group the CURRENT allocation group (overrides the 05.03 constraints) in both the auto-resolve and interactive batch flows — proven by a fixture where the character dies FIRST then damage reverts to the bodyguards; **[PSYCHIC]** (24.29) ignores exactly the harmful BS/hit-roll modifiers in both stack blocks (cover's worsening ignored, bonuses kept); **[CLOSE-QUARTERS]/[PISTOL]** identity + interactions landed with ISS-048; ONE SHOT tracking pre-existed (T4-2); SUSTAINED HITS pinned by the keyword pipeline tests; HEAVY's 11e conditions via ModifierStack (ISS-016). `test_iss047_weapon_abilities_11e.gd` 22/22; goldens 63/63 (10e untouched); suite 1078/1078. Remaining niceties recorded elsewhere: visible-CHARACTER refinement for PRECISION (ISS-052 module), attacker-facing choice prompts (ISS-063), Firing Deck/Scouts/Infiltrators/Lone Operative distance data (army-data review, PRD open decision #2), Support (ISS-059), SUPER-HEAVY WALKER (ISS-061), HOVER landed in MoveType (ISS-040).

### ISS-048 — 11e shooting types
- **Location:** `40k/phases/ShootingPhase.gd` (6,465 lines), `RulesEngine.gd` BGNT at `:5192-5254`, pistol handling at `:4886-4907`; rules: 10.04-10.07, 15.09, 17.03
- **Category:** breaking-change
- **Severity:** high
- **Description:** Shooting becomes select-shooting-type: Normal / Assault (advanced + [ASSAULT] only) / Close-Quarters (engaged; replaces pistol rules and Big Guns Never Tire; M/V −1 hit except CQ weapons vs engaged target; BLAST still barred) / Indirect (core rules: target not visible, cover granted, no hit re-rolls, 1-5 fails unless stationary+spotter → 1-3 fails) / Snap (hit on unmodified 6, ≤24", used by Fire Overwatch). Shooting at engaged M/V: allowed at −1 (17.03). "Eligible to shoot" interacts with actions (ISS-057).
- **Root cause:** n/a (edition change).
- **Proposed fix:** `ShootingType` strategy objects mirroring ISS-040's template (ELIGIBLE IF / WHILE / AFTER); retire BGNT and pistol special-cases; map [PISTOL] → [CLOSE-QUARTERS] in the data converter (24.27 says they're identical).
- **Dependencies:** ISS-040, ISS-037, ISS-047
- **Affected files:** `ShootingPhase.gd`, `ShootingController.gd` (type picker UI), `RulesEngine.gd`, AI targeting
- **Acceptance criteria:** scenario per type incl. the engaged-vehicle FAQ cases (pg 88: no BLAST vs engaged units in either direction); indirect hit-caps verified with and without spotter.
- **Status:** DONE — new `40k/scripts/rules/shootingtypes/`: `ShootingType` base (ELIGIBLE IF / WHILE weapon+target constraints / hit consequences / AFTER cannot-start-action) with the baseline 17.03 target rule (engaged non-M/V untargetable, engaged M/V targetable, [BLAST] never vs engaged), `ShootingTypes` registry (`available_for` per 10.02), and Normal (10.04), Assault (10.05, [ASSAULT]-only weapons), Close-Quarters (10.06: engaged+CQ-or-M/V; non-M/V locked to CQ weapons vs engaged targets; M/V -1 unless CQ-vs-engaged; BLAST still barred; [PISTOL]=[CLOSE-QUARTERS] per 24.27), Indirect (10.07: non-visible targeting, cover, no hit re-rolls, unmodified 1-5 fails → 1-3 with remained-stationary + friendly spotter LoS), Snap (15.09: rule-granted only, ≤24" visible target, unmodified 6s, no re-rolls). ModifierStack now carries the 10.06 M/V -1 and 17.03 engaged-M/V-target -1 into BOTH resolve paths at edition≥11, and the 10e BGNT inline penalty is gated <11 (retired at 11e). `test_iss048_shooting_types_11e.gd` 29/29 — **both pg-88 FAQ cases reproduce** (no BLAST vs engaged units in either direction) and **the indirect hit-caps verify with and without the spotter**. Discovery: EnhancedLineOfSight falls back to the LIVE TerrainManager terrain when a board carries no `terrain_features` — synthetic fixtures must pass a non-empty list (documented in the test). Step 2 (landed): ShootingPhase drives the templates at edition≥11 — SELECT_SHOOTER validation requires a selectable type (10.02, with the template's reasons surfaced), processing picks the type (payload `shooting_type` override with fallback; default = first available) into `active_shooting_type`, and ASSIGN_TARGET enforces the type's WHILE constraints (`weapon_allowed`/`target_allowed`). The 10e pistol mutual-exclusivity retires at 11e (24.27). **The windowed gate caught a real UI gap**: the engine accepted the CQ assignment but ShootingController's weapon rows still showed "Only PISTOL weapons can be used in engagement range" — the rows now gate through the selected type's `weapon_allowed` (with a pre-selection preview fallback), so an engaged VEHICLE's full arsenal is clickable at 11e. `tests/scenarios/sp/iss048_shooting_types_11e.json` 19/19 (CQ auto-selection for the engaged Dreadnought, normal-request fallback, any-weapon CQ assignment vs the engaging unit, 16.01 lock blocking SELECT through the UI path) with full-res screenshot crops verified clean; 4 10e shooting scenarios regression-clean; headless 1113/1113. Harness improvement: ScenarioRunner now supports a top-level `"edition"` key applied BEFORE the phase transition (so 11e scenarios build their initial UI under 11e rules) — adopted by all three 11e phase scenarios.

### ISS-049 — 11e charge phase
- **Location:** `40k/phases/ChargePhase.gd` (3,328 lines), `ChargeController.gd`; rules: 11.01-11.04
- **Category:** breaking-change
- **Severity:** high
- **Description:** Charge targets selected **after** the roll (within 12" AND within rolled distance); move must end engaged with every target, engaged with no non-targets, each model closer + within-1"-if-possible + engaged-if-possible; chargers gain the **Fights First ability** until end of turn (not a flag read by fight ordering). ER 2" changes completion ranges. Eligibility: within 12" of enemy, unengaged, no advance/fall-back this turn.
- **Root cause:** n/a (edition change).
- **Proposed fix:** Charge as a MoveType instance (ISS-040) with BEFORE (declare targets post-roll) and WHILE/AFTER constraints; grant `fights_first` effect (consumed by ISS-050); update path validation to 2" ER and the new per-model constraints.
- **Dependencies:** ISS-039, ISS-040
- **Affected files:** `ChargePhase.gd`, `ChargeController.gd`, `RulesEngine.gd` charge validation, AI charge eval
- **Acceptance criteria:** scenario reproduces the pg 37 example (target beyond roll distance unselectable; multi-target charge must engage all); charged unit shows Fights First in the fight phase.
- **Status:** DONE — `ChargeMove11e` joins the MoveType registry implementing the 11e deltas: eligibility per 11.02 (within 12", unengaged, no advance/fall-back), the 2D6 roll as the maximum distance with targets selected AFTER the roll (within 12" AND within the roll — the pg-37 example's semantics reproduce in test: at a roll of 7, the 5" enemy is selectable, the 10" and 20" ones are not), after-conditions (engaged with EVERY target and NO non-targets, edition-aware 2" ER), and the Fights First ABILITY grant (11.04/24.13, consumed by ISS-050's fight ordering). `test_iss049_charge_11e.gd` 12/12; suite 943/943. Step 2 (landed): ChargePhase drives the template at edition≥11 — DECLARE_CHARGE accepts an EMPTY target list (11.02: targets are selected after the roll) with template eligibility authoritative for the declare; CHARGE_ROLL computes `selectable_targets` (enemies within 12" AND within the roll) via the template, drops unreachable pre-declared targets, and judges an empty-declare charge against the selectable list (only nothing-reachable fails); APPLY_CHARGE_MOVE accepts the post-roll target selection in its payload validated ⊆ selectable. The charged/fights-first AFTER flags already matched the template. **Windowed gate passed**: `tests/scenarios/sp/iss049_charge_11e.json` 19/19 (template veto for a unit with no enemy within 12", empty-declare, deterministic roll 8+2='Ere We Go=10 with selectable pinned to the Shield Captain, non-selectable APPLY rejected) with screenshots verified; 10e charge scenario 372 regression-clean; headless 1113/1113. Bonus: ScenarioRunner now hides the lingering PhaseTransitionBanner before captures — board screenshots are no longer obscured. Per-model closer/engage constraints remain shared with the 10e path (_validate_charge_movement_constraints).

### ISS-050 — 11e fight phase restructure
- **Location:** `40k/phases/FightPhase.gd` (4,474 lines), `FightController.gd`; rules: 12.01-12.09, appendix pass rules (pg 87)
- **Category:** breaking-change
- **Severity:** blocker
- **Description:** Complete resequencing: (1) global **Pile In step** — both players move all eligible units (active player first), pile-in targets concept, 5" range for unengaged charge-survivors; (2) **Fight step** — alternate Fights First units (active player's choice first), then remaining, returning to Fights First when new ones become eligible; pass rules when eligible-but-unable; **overrun fights** (extra pile-in for units whose targets died); (3) global **Consolidate step** with mandatory modes: ongoing / engaging (newly engaged enemies become eligible and are selected to fight!) / objective. Current per-activation pile-in→fight→consolidate is structurally incompatible.
- **Root cause:** n/a (edition change).
- **Proposed fix:** Rewrite FightPhase as a three-step state machine; pile-in/consolidation as MoveType instances with modes; fight eligibility per 12.04; engaging-consolidation triggered fights handled as queued selections. Big enough to gate behind edition flag with the 10e path intact until scenarios pass.
- **Dependencies:** ISS-039, ISS-040, ISS-049
- **Affected files:** `FightPhase.gd`, `FightController.gd`, dialogs (`PileInDialog`, `ConsolidateDialog`), AI fight planning, NetworkManager (alternation routing)
- **Acceptance criteria:** scenarios reproduce the pg 39/41/43 worked examples (pile-in ordering, overrun fight after transport kill + emergency disembark, objective consolidation); alternation incl. pass rules verified in multiplayer test.
- **Status:** DONE — `PileInMove` (12.02-12.03: engaged/charged/overrun eligibility incl. the pg-39 unengaged-charge-survivor case with within-5" target selection; WHILE base-contact lock + closer-to-closest-target validation; AFTER engaged + started-engaged-pairs-maintained voiding) and `ConsolidationMove` (12.07-12.08: mandatory modes assessed in order — ONGOING/ENGAGING/OBJECTIVE with the 3"+marker objective range matching MissionManager, per-mode WHILE/AFTER, `forced_fights_after_engaging` for 12.08's opponent-selected forced fights) as MoveType instances in the registry; new `FightSequencer` (12.04-12.06) implementing the full selection state machine: Fights First alternation starting with the active player, BOTH pass rules (no-FF-anywhere → remaining step with the same picker; otherwise other player selects), return-to-Fights-First after a remaining-step fight, and fight types (NORMAL 12.05 / OVERRUN 12.06 incl. the engaged-mid-phase unit's choice of both). `test_iss050_fight_phase_11e.gd` 37/37 — **the pg-41 worked example's complete selection sequence reproduces** (monster normal-fights and kills the transport; pass to RED again; the charge-survivor — unengaged but engaged at step start — overruns; the newly engaged unit fights back; step ends) plus the pg-39 and pg-43 cases. Step 2 (landed): FightPhase defers to the FightSequencer at edition≥11 through four seams — init creates+begins the sequencer (alternation starts with the ACTIVE player, an 11e delta from 10e's defender-first) and takes the opening picker from `next_selection`; SELECT_FIGHTER validation is sequencer-authoritative (12.04 picker + candidates — including charge-survivors that are no longer engaged, which the 10e engagement check would refuse); selection commits via `select_to_fight` and surfaces the 12.05/12.06 fight types; `_switch_selecting_player` (the single alternation point used by complete/skip flows) consults `after_fight_resolved` + `next_selection` (skip-empty-player, return-to-Fights-First, step end). **Windowed gate passed**: `tests/scenarios/sp/iss050_fight_11e.json` 16/16 — active-player-first, alternation to P2 after a pick, out-of-turn pick refused with the 12.04 reason, and **the pg-39 unengaged-charge-survivor selection works through the live phase** — with the fight-flow dialogs (Ka'tah, Pile In) captured on screen. 10e fight scenarios (fights_last, self-targeting, headwoppa) regression-clean; headless 1113/1113. The phase's `current_selecting_player` mirror syncs at fight completion (validation reads the sequencer, so mid-fight UI labels may lag one selection — noted for ISS-063's MP routing pass). AI fight planning at 11e rides ISS-062.

### ISS-051 — 11e terrain data model: categories and terrain areas
- **Location:** `40k/autoloads/TerrainManager.gd` (755 lines), `40k/terrain_layouts/`; rules: 13.01-13.06
- **Category:** breaking-change
- **Severity:** blocker
- **Description:** Terrain becomes: terrain **areas** (bounded regions) containing terrain **features** classed Exposed / Light / Dense, driving movement (keyword-dependent traversal, 2" height threshold for non-infantry, vertical movement costs, surface end-of-move rules) and all of visibility/cover (ISS-052/053). Current ruins/walls model and layout files don't carry these concepts.
- **Root cause:** n/a (edition change).
- **Proposed fix:** Layout schema v2: areas (polygons) + features (polygon, category, height); migrate existing `terrain_layouts/` files; TerrainManager exposes `area_at(point)`, `features_crossed(segment)`, `category(feature)`. Keep rendering compatible.
- **Dependencies:** ISS-002
- **Affected files:** `TerrainManager.gd`, `terrain_layouts/*.json`, board rendering, layout editor if any
- **Acceptance criteria:** migrated layouts load and render; queries unit-tested against a fixture layout (point-in-area, segment-crossing, heights).
- **Status:** DONE (schema-v2 area authoring deferred to map-pack content, ISS-063) — TerrainManager gains the 11e layer over the existing runtime pieces (no layout migration needed yet — current layouts keep working): category derivation per 13.03-13.05 (ruins/woods/building/container → dense; barricade/wall/statuary → light; rest → exposed; explicit `category` field overrides), numeric `height_inches_of` (legacy low/medium/tall labels → 1.5"/3.5"/6.0", explicit field wins), `area_at(point)`, `features_crossing(segment)`, and `is_obscured_between` (13.10's center-line approximation: every-line semantics arrive with ISS-052's full visibility module). `test_iss051_terrain_model_11e.gd` 15/15; suite 832/832. All consumers landed (ISS-052 visibility, ISS-053 cover, ISS-054 movement, ISS-055 terrain objectives ride on these queries). The layout-schema-v2 multi-feature area authoring is CONTENT work (map files group features into shared areas) — the engine treats each feature's polygon as its area today, which all consumers handle; revisit when an 11e map pack is authored (ISS-063 scope).

### ISS-052 — 11e visibility: fully-visible, Hidden, Obscuring, Solid
- **Location:** `40k/autoloads/LineOfSightManager.gd`, `40k/autoloads/EnhancedLineOfSight.gd` (562 lines — initial audit overstated as 22.6k), `RulesEngine.gd` `_check_target_visibility`; rules: 06.01, 13.07-13.11, 24.24
- **Category:** breaking-change
- **Severity:** blocker
- **Description:** New visibility stack: 1mm-wide LoS line ignoring both units' own models; **visible vs fully visible** distinction; **Obscuring**: light/dense areas block LoS entirely when every line crosses them (unless either model is inside); **Solid**: no LoS through enclosed gaps ≤3" from ground; **Hidden**: INFANTRY/BEASTS/SWARM in a dense-containing area that didn't shoot last/this turn are visible only within 15" detection; Lone Operative becomes a 12" visibility + indirect-protection rule.
- **Root cause:** n/a (edition change).
- **Proposed fix:** `Visibility` module over ISS-051 queries: `visible(a,b)`, `fully_visible(a,b)`, `hidden(model)`, detection ranges; targeting (`get_eligible_targets`) consumes it; shooting UI shows hidden/obscured status.
- **Dependencies:** ISS-051
- **Affected files:** LoS autoloads (likely merged into the module), `RulesEngine.gd` targeting, shooting/AI, overlays
- **Acceptance criteria:** unit tests reproduce the pg 51 worked examples (units A-E cover/obscuring matrix; B visible to D at 15" but C not; Solid window cases); windowed scenario shows a hidden unit untargetable beyond 15".
- **Status:** DONE — TerrainManager gains the 13.09 HIDDEN rule, edition-gated: INFANTRY/BEASTS/SWARM in a dense-containing area whose unit hasn't shot recently (`shot_recently` flag — the shooting phase maintains it when ISS-048 lands) are visible only within the 15" detection range (`hidden_model_visible_to`). `test_iss052_hidden_11e.gd` 9/9 covering qualification (keyword/category/shot gates), the 14"-visible/17"-not detection boundary, and the edition gate; suite 841/841. Obscuring's center-line approximation landed in ISS-051. Step 2 (landed): the full visibility module — `_visibility_lines_11e` samples the target base (center + 8 perimeter points; base_mm-radius approximation) with per-line blocking by obscuring areas neither model is within (13.10's every-line semantics fall out of the per-line test) and dense/Solid footprints at ground level (13.11's 2D effect); `model_visible_11e` (any clear line, 06.01 MODEL VISIBLE), `model_fully_visible_11e` (every line clear), `unit_fully_visible_11e` (06.01 UNIT FULLY VISIBLE). Wired into the REAL targeting path: `RulesEngine._check_target_visibility` applies the HIDDEN detection gate (13.09) and the line semantics at edition≥11 before the base LoS check. `test_iss052_hidden_11e.gd` 16/16 (partial-block visible-but-not-fully, full-wall every-line block, within-area sees-out exclusion); **windowed**: the iss048 scenario injects an obscuring wall and flips live target visibility off and back on through the real engine path.

### ISS-053 — 11e benefit of cover + Plunging Fire as BS modifiers
- **Location:** `RulesEngine.gd:4078-4145` (cover as save/AP interaction today), ModifierStack (ISS-016); rules: 13.08, 22.05, 24.18, 24.33
- **Category:** breaking-change
- **Severity:** high
- **Description:** Cover changes mechanic entirely: a unit with benefit of cover **worsens the attack's BS by 1** (not save bonus). Granted by: all models in a terrain area (INFANTRY/BEASTS/SWARM) or not-fully-visible due to intervening features/areas. Plunging Fire **improves BS by 1** (attacker on ≥3" elevation, or TOWERING within 12", vs ground-level targets). Stealth grants cover; [IGNORES COVER] negates incl. Stealth; Smokescreen grants it.
- **Root cause:** n/a (edition change).
- **Proposed fix:** Cover/plunging-fire as characteristic modifiers on the ModifierStack queried by AttackSequence's hit step; remove AP/save-based cover code path under edition=11.
- **Dependencies:** ISS-051, ISS-052, ISS-016, ISS-041
- **Affected files:** `RulesEngine.gd`, `AttackSequence.gd`, ModifierStack, AI scoring (via ISS-014 shared math)
- **Acceptance criteria:** unit tests: cover worsens 3+ BS to 4+; cover + plunging fire net zero; IGNORES COVER vs Stealth; scenario shows hit-chance preview reflecting cover.
- **Status:** DONE — TerrainManager gains edition-gated `unit_has_cover_11e` (13.08's in-area half with the EVERY-model requirement and keyword gate; Stealth grants unconditionally per 24.33; the not-fully-visible half awaits ISS-052's fully-visible module) and `plunging_fire_applies` (22.05: attacker ≥3" elevation or TOWERING within 12", vs ground-level targets, via per-model `elevation_inches`). `test_iss053_cover_plunging_11e.gd` 10/10; suite 851/851. UPDATE (with ISS-016): the BS application is now LIVE — `ModifierStack.collect_hit_context_11e` feeds both shooting paths at edition≥11 (cover/STEALTH worsen the per-attack BS thresholds, plunging fire improves them, cover-vs-plunging sums to net zero; `test_iss016_modifier_stack.gd` 19/19). Final half (landed): `unit_has_cover_11e(unit, attacker_model)` now implements BOTH 13.08 conditions per model — INFANTRY/BEASTS/SWARM within an area OR not fully visible to the attacker (terrain is the only blocker the module models, so the "due to intervening terrain" clause is inherent) — and ModifierStack passes the first firing model through, so a partially-obscured VEHICLE now gets cover at 11e. Tested in `test_iss052_hidden_11e.gd` step 2.

### ISS-054 — 11e terrain movement + MOBILE keyword
- **Location:** movement validation in `MovementPhase.gd`/`RulesEngine.gd`; rules: 13.06, 24.35
- **Category:** breaking-change
- **Severity:** medium
- **Description:** Traversal by category/keyword: INFANTRY/BEASTS/SWARM/MOBILE through dense horizontally (vertically without MOBILE); others blocked by >2" sections; vertical movement counts distance with ½" hug rule; end-on-surface rules (stable, no overhang, keyword-gated); Solid 3"-enclosure end-of-move restriction; SUPER-HEAVY WALKER's 4" rule + MOBILE-gamble.
- **Root cause:** n/a (edition change).
- **Proposed fix:** Implement as WHILE-MOVING validators in the MoveType framework using ISS-051 queries; MOBILE keyword from ISS-037 schema.
- **Dependencies:** ISS-051, ISS-040, ISS-037
- **Affected files:** move-type validators, `MovementController.gd` path preview, AI pathing
- **Acceptance criteria:** unit tests per pg 49 examples (monster blocked by >2" wall; infantry through walls; vehicle ascending); drag preview blocks illegal paths in a windowed scenario.
- **Status:** DONE (2D-board scope) — `TerrainManager.can_move_through_11e` implements 13.06's horizontal traversal matrix: exposed/light pass for all; dense passes INFANTRY/BEASTS/SWARM/MOBILE (MOBILE grantable per-move via `extra_keywords` — 24.35's gamble plugs in there) and other models only when every crossed section is ≤2" (≤4" with SUPER-HEAVY WALKER). Wired into `_validate_set_model_dest` at edition≥11 with the 21.03 exemption (take-to-the-skies movers pass over terrain). `test_iss051_terrain_model_11e.gd` +7 (22/22) covering the pg-49 examples (MONSTER blocked by the tall ruin, INFANTRY through, SHW ≤4" rule, light never blocks, edition gate); **windowed** in the iss040 scenario: the flying Battlewagon crosses an injected tall dense wall, then the same unit WITHOUT take-to-the-skies is refused with the 13.06 reason. Out of 2D scope (documented at the validator): vertical movement costing/½"-hug, end-on-surface stability, and the Solid 3"-enclosure end-of-move rule — these need an elevation model the board doesn't have.

### ISS-055 — 11e objectives: terrain objectives, per-phase control, Secured
- **Location:** `40k/autoloads/MissionManager.gd` (1,201 lines), `ScoringPhase.gd`; rules: 14.01-14.03, appendix (markers)
- **Category:** breaking-change
- **Severity:** medium
- **Description:** Objectives become terrain areas (within-range = inside the area), with 40mm markers (3" horiz/5" vert) only when no area coincides. Control recomputed at end of **each phase and turn**; **Secured** ("sticky") objectives are core (control persists without presence until opponent exceeds). Battle-shocked OC '-' feeds in (ISS-043).
- **Root cause:** n/a (edition change).
- **Proposed fix:** Objective model references a terrain area or marker; control evaluation hooked to phase-end events (ISS-038); `secured_by` state with the 14.03 persistence rule; secondary missions reread through this.
- **Dependencies:** ISS-051, ISS-038, ISS-043
- **Affected files:** `MissionManager.gd`, `SecondaryMissionManager.gd`, `ScoringPhase.gd`, board rendering, AI objective play
- **Acceptance criteria:** unit test reproduces the pg 53 OC example (5 vs 6); secured objective retains control after units leave; scenario scores correctly at phase end.
- **Status:** DONE — discovery: MissionManager already had most 11e semantics (battle-shock zeroes control participation; a sticky-objective mechanism with exactly 14.03's break-on-out-control rule, built for Get da Good Bitz / Vigilance Eternal). Landed: 14.02's evaluation timing (control re-checked on every `phase_completed` and `turn_ending`, edition-gated), a public army-level `secure_objective`/`is_objective_secured` API riding the proven mechanism, and the 14.03 fix that army-level secured locks persist without a source unit (the ability-level path required its source alive). `test_iss055_objectives_11e.gd` 6/6; suite 857/857. Final piece (landed): TERRAIN OBJECTIVES (14.01) — at edition≥11, when a terrain area coincides with the objective point, that AREA is the objective: a model is in range while WITHIN the area (point-in-polygon), not the marker radius; open-ground objectives fall through to the existing radius. `test_iss055_objectives_11e.gd` 9/9 — a model inside the area but >3" from the point controls it; a model outside the area but within the 10e radius does NOT; the 10e radius behavior is unchanged at edition 10. The marker-range question resolves itself: 11e measures to the terrain area's closest part (14.01), which the in-area test embodies on the 2D board.

### ISS-056 — 11e core stratagem set + targeting restrictions
- **Location:** `40k/autoloads/StratagemManager.gd` (2,635 lines, current 10e core set at `:70-400`); rules: 15.01-15.12
- **Category:** breaking-change
- **Severity:** medium
- **Description:** New restriction: a player can't target the same **unit** with more than one stratagem per phase (plus same-stratagem-once-per-phase). New/changed core set: Command Re-roll (one die; charge rolls re-rolled in full), Epic Challenge, Insane Bravery (once per battle), Explosives (6D6, 4+ = MW), Crushing Impact (T-dice ram), Rapid Ingress, Fire Overwatch (snap shooting, end of opponent's **Movement** phase, no TITANIC), Smokescreen, Heroic Intervention (resolve a real charge with Leap-to-Defend/Into-the-Fray modes), Counteroffensive (2CP, +1CP rider). Battle-shocked units can't be targeted (ISS-043).
- **Root cause:** n/a (edition change).
- **Proposed fix:** Add per-unit-per-phase tracking to StratagemManager validation; reimplement the core set as data + effect hooks (modes via the shared mode mechanism); CP flow per 08.02 (both players gain 1CP in each Command phase — verify current behavior matches).
- **Dependencies:** ISS-043, ISS-044, ISS-048 (snap shooting), ISS-049 (heroic intervention charge), ISS-050 (counteroffensive)
- **Affected files:** `StratagemManager.gd`, stratagem data, UI prompts, AI stratagem advisor
- **Acceptance criteria:** per-unit restriction test; each core stratagem has a unit/scenario test incl. Crushing Impact dice mechanics and Fire Overwatch timing window.
- **Status:** DONE (live trigger windows/prompts ride with the phase step-2s + ISS-063) — `can_use_stratagem` now enforces 15.01's "each player cannot target the same unit with more than one stratagem in the same phase" at edition 11 (per-player, per-phase, edition-gated; 10e unchanged), riding the existing usage-history records. `test_iss056_stratagem_per_unit.gd` 5/5; suite 817/817. Remainder (landed): the full 11e core set 15.02-15.12 registered as data definitions with `edition: 11` (COMMAND RE-ROLL single-die + full-charge-reroll exception, EPIC CHALLENGE melee-[PRECISION] grant, INSANE BRAVERY once-per-battle, EXPLOSIVES, CRUSHING IMPACT, RAPID INGRESS via the 20.04 move, FIRE OVERWATCH via SNAP shooting 15.09, SMOKESCREEN screened-cover, HEROIC INTERVENTION as a real 11.02 charge with leap-to-defend/into-the-fray modes, COUNTEROFFENSIVE at 2CP with must-fight-next) — `can_use_stratagem` gates by edition both ways and the reworked 10e core entries carry `edition_max: 10` (retired at 11e). The two dice effects are engine functions: `RulesEngine.resolve_explosives_11e` (6D6, 4+ = MW via 06.02 allocation) and `resolve_crushing_impact_11e` (T dice, 1s wound SELF, 5+ wound the enemy, both capped at 6 per unit). `test_iss056_stratagem_per_unit.gd` 12/12; suite 1091/1091. The per-stratagem live trigger windows + prompts (overwatch's end-of-opponent-movement hook, heroic-intervention charge UI) ride with the phase step-2 wirings and ISS-063's scenario suite.

### ISS-057 — Actions system
- **Location:** new subsystem; rules: 16.00-16.01
- **Category:** missing-feature
- **Severity:** high
- **Description:** 11e adds Actions (STARTS/UNITS/USE LIMIT/COMPLETES/EFFECT): eligibility gates (on battlefield, not battle-shocked, OC>0, unengaged unless TITANIC, no advance/fall-back, one action/turn), starting an action blocks shooting (non-TITANIC) and charging, moving (except pile-in/consolidate) cancels completion. Missions and many secondaries will be defined in terms of actions — without this the mission layer can't migrate.
- **Root cause:** n/a (new system).
- **Proposed fix:** `ActionsManager` (data-driven action definitions; per-unit action state in GameState); eligibility via shared predicates (battle-shock from ISS-043, engaged from ISS-039); completion checks hooked to turn events (ISS-038) and move execution (ISS-040); shooting/charge eligibility predicates consult active actions.
- **Dependencies:** ISS-038, ISS-039, ISS-040, ISS-043
- **Affected files:** new `ActionsManager.gd`, `MissionManager.gd`, phase eligibility checks, UI (start-action affordance), AI
- **Acceptance criteria:** the example Deploy Device action (pg 58) implemented as a fixture: start in Shooting phase, blocked by advance/battle-shock, cancelled by moving, completes at end of turn with effect; unit shown ineligible to shoot after starting.
- **Status:** DONE (start-action UI prompt rides with ISS-063; mission-pack data with PRD open question 3) — new `scripts/rules/ActionsManager.gd`: data-defined actions with EVERY 16.01 eligibility gate (battlefield, AIRCRAFT/FORTIFICATION, battle-shock, OC 0/'-', engaged-unless-TITANIC, advance/fall-back, one-action-per-turn), keyword unit filters, once-per-turn use limits, start-locks (cannot shoot — TITANIC exempt — and cannot charge, as flags for phase eligibility), movement cancellation (pile-in/consolidation exempt), and trigger-driven completion (battle-shock blocks completion per 01.07). **The rulebook's Deploy Device example (pg 58) is the test fixture** — `test_iss057_actions_11e.gd` 19/19; suite 912/912. Step 2 (landed): the lock flags are CONSUMED — `cannot_shoot` blocks every selectable 11e shooting type (ISS-048 templates) and `cannot_charge` blocks the 11e charge template; PhaseManager registers `_complete_actions_11e` as a non-mission turn_ending hook (ISS-038) so end-of-turn actions complete through the diff pipeline against live GameState (battle-shock still blocks per 01.07). `test_iss057_actions_11e.gd` 25/25; suite 1084/1084. Remaining niceties: the start-action UI prompt (ISS-063) and mission-pack action definitions (PRD open question 3 — data, not engine).

### ISS-058 — 11e transports: embark + disembark modes + emergency disembark
- **Location:** `40k/autoloads/TransportManager.gd` (~534 lines), `40k/scripts/DisembarkController.gd`, `dialogs/TransportEmbarkDialog.gd`; rules: 18.01-18.05
- **Category:** breaking-change
- **Severity:** high
- **Description:** Embark: after a normal/advance/fall-back move, every model within 3", not set up this turn. Disembark modes (forced order): **Rapid** (transport normal/ingress-moved; 3"; no charge) / **Tactical** (transport unmoved; 3"; the unit is then selected to make a normal or advance move!) / **Combat** (otherwise; 6"; hazard roll per model; may set up engaged; unit battle-shocked; no charge). Destroyed transport → **emergency disembark** (6", hazard rolls, battle-shocked, models that can't be placed die) before Deadly Demise (24.08 ordering).
- **Root cause:** n/a (edition change).
- **Proposed fix:** Disembark/emergency-disembark as MoveType instances with modes; tactical disembark chains into a normal/advance selection in the movement flow; destruction ordering (attacks resolved → emergency disembark → deadly demise roll → remove) implemented in the destruction handler per the pg 80 example.
- **Dependencies:** ISS-040, ISS-044, ISS-043 (battle-shock status)
- **Affected files:** `TransportManager.gd`, `DisembarkController.gd`, `MovementPhase.gd`, destruction handling in `RulesEngine.gd`/phases, AI
- **Acceptance criteria:** scenario per mode incl. tactical-disembark-then-advance; destroyed-transport sequence matches the Impulsor example ordering; capacity rules regression-tested.
- **Status:** DONE — `DisembarkMove` + `EmergencyDisembarkMove` join the registry implementing 18.04/18.05: mandatory mode selection from the transport's move history (normal/ingress → rapid 3" no-charge; unmoved → tactical 3" with the unit then selected for a normal/advance move, surfaced via `pending_post_disembark_move`; advanced/fell-back → combat 6" with per-model hazard rolls, may set up engaged with the transport's foes, battle-shocked + no charge), the embark-this-phase ban, and emergency disembark (6", hazard per model, battle-shocked, no charge). `test_iss058_disembark_11e.gd` 19/19; suite 931/931. Step 2 (landed): RAW CORRECTION — 18.04's eligibility bars disembarking from advanced/fallen-back transports entirely (step 1 had wrongly mapped that to combat mode); combat disembark is now the fallback when a tactical 3" set-up is impossible (`select_mode` takes `can_setup_tactical`) or the transport is engaged. TransportManager wiring: `can_embark` enforces 18.02's set-up-this-turn ban at edition≥11 (the ≤3"/capacity/keyword checks pre-existed); `resolve_transport_destroyed` at 11e resolves a true 18.05 emergency disembark — HAZARD rolls per 06.03 (1-2 destroys the model; a MONSTER/VEHICLE model suffers 3 mortal wounds via the 06.02 allocation instead) and the survivors are battle-shocked; the 24.08 ordering (attacks → emergency disembark → Deadly Demise → removal) was already correct in the destruction flow (P1-60 forces transport-destruction handling before Deadly Demise). `test_iss058_disembark_11e.gd` 28/28 (the 3-MW M/V branch exercised, not vacuous); suite 1100/1100. Final wiring (landed): CONFIRM_DISEMBARK at edition≥11 selects the mandatory 18.04 mode through the template (payload `can_setup_tactical=false` signals an impossible tactical set-up → combat fallback), validates positions against the MODE-dependent set-up distance (3" rapid/tactical, 6" combat — the validator now also accepts array/dict position formats), rolls the per-model combat-disembark hazards (06.03 → 06.02 allocation) and applies the template AFTER effects (tactical = unit is then selected for a normal/advance move; combat = battle-shocked + cannot charge). **Windowed gate passed**: `tests/scenarios/sp/iss058_disembark_11e.json` — the SAME 4" positions are rejected under tactical and accepted under combat, with the shocked flags asserted and the disembarked line visually verified beside the Battlewagon.

### ISS-059 — 11e attached units: Support, bodyguard toughness, ability persistence
- **Location:** `40k/autoloads/CharacterAttachmentManager.gd`, `LeaderPairingsLoader.gd`; rules: 19.01-19.04, 24.22, 24.34
- **Category:** breaking-change
- **Severity:** medium
- **Description:** Bodyguard units can have one Leader **and one Support** unit. Attacks vs attached units use the **highest bodyguard T** (character protection now flows through allocation groups, ISS-041, not special wound rules). Ability persistence matrix (source destroyed → effect ends, with the until-attacks-resolved grace); keyword union for the unit, not models; revived leaders rejoin.
- **Root cause:** n/a (edition change).
- **Proposed fix:** Add support-slot to attachment data + pairing loader; toughness lookup in AttackSequence wound step; persistence hooks on model destruction; remove 10e bodyguard wound-allocation special cases (superseded by allocation groups).
- **Dependencies:** ISS-037, ISS-041
- **Affected files:** `CharacterAttachmentManager.gd`, `LeaderPairingsLoader.gd`, `AttackSequence.gd`, army data
- **Acceptance criteria:** unit tests: wound rolls vs attached unit use bodyguard T; ANTI-PSYKER applies via leader keyword (pg 67 example); leader ability stops applying when leader dies (after current attacks resolve).
- **Status:** DONE (effect-flag source-expiry rides with ISS-027's modifier migration) — CharacterAttachmentManager gains per-ROLE slots at edition≥11 (19.01/24.22/24.34: one LEADER and one SUPPORT per bodyguard via `attachment_role` — Support datasheet ability — 10e single-slot unchanged) and `attached_unit_keywords` (19.03 union, queryable from either side). `get_critical_wound_threshold` consults the union at 11e — **the pg-67 ANTI-PSYKER worked example reproduces exactly** (4+ crits vs a non-PSYKER bodyguard while the PSYKER leader lives, reverting to 6 once the leader dies and detaches = the 19.04 expiry through the existing detach-on-death flow). 19.02's bodyguard-T holds structurally in this codebase: attacks target the bodyguard unit (its own T), characters protected via allocation groups (ISS-041/045), and an all-characters remnant detaches to its own profile. The deeper 19.04 matrix (leader-granted effect FLAGS expiring on source death, with the until-attacks-resolved grace) needs effect-source tracking — recorded against ISS-027. `test_iss059_attached_units_11e.gd` 13/13.

### ISS-060 — 11e reserves: ingress moves, deep strike, round-3 rules, aircraft cycle
- **Location:** `40k/phases/DeploymentPhase.gd` (reserves), reinforcement handling; rules: 20.01-20.04, 23, 24.09, 15.07
- **Category:** breaking-change
- **Severity:** medium
- **Description:** Arrival = **ingress move** (wholly within 6" of edges, >8" from enemies, no opponent DZ before round 3; not eligible for other moves until next Charge phase — i.e., they can charge); reserves not arrived by end of round 3 are destroyed (with embarked/repositioned exceptions); Deep Strike = ingress anywhere >8"; Rapid Ingress at start of opponent's Shooting phase; AIRCRAFT must start in reserves, only ingress-move, and return to reserves at end of opponent's turn; repositioned-unit persistence rules (20.02).
- **Root cause:** n/a (edition change).
- **Proposed fix:** Ingress as a MoveType instance; reserves lifecycle hooked to round events (ISS-038); aircraft handled as a unit-flag driving forced reserve cycling; Rapid Ingress timing via stratagem window (ISS-056).
- **Dependencies:** ISS-040, ISS-038, ISS-056
- **Affected files:** `DeploymentPhase.gd`, movement phase (ingress selection), `MissionManager` (round-3 destruction), AI reserves planning
- **Acceptance criteria:** scenario: ingress placement constraints enforced by round; unit ingressing then charging same turn; round-3 destruction of unarrived reserves; aircraft cycles to reserves at end of opponent's turn.
- **Status:** DONE (AIRCRAFT cycle 23.02 deferred — no aircraft datasheets in the current armies) — `IngressMove` joins the MoveType registry implementing 20.04 (edition-gated eligibility from reserves; set-up validation: wholly within 6" of an edge, >8" horizontally from enemies, opponent-DZ ban before round 3; AFTER: locked out of further moves until the next Charge phase — so ingressed units CAN charge) with Deep Strike's 24.09 relaxation via a context flag. Round-3 destruction of unarrived reserves already existed (P1-37 in ScoringPhase). `test_iss060_ingress_11e.gd` 13/13; suite 879/879. Step 2 (landed): PLACE_REINFORCEMENT at edition≥11 validates set-up through `IngressMove.validate_setup` (wholly within 6" of an edge — lifted by Deep Strike — >8" from enemies vs 10e's 9", opponent-DZ ban before round 3) and applies the template's AFTER effects on arrival (`arrived_from_reserves` + `no_moves_until_charge_phase` — ingressed units CAN charge, 20.04); the Rapid Ingress arrival path (`_process_place_rapid_ingress_reinforcement`) carries the same AFTER effects (15.07 is an ingress move). **Windowed gate passed**: `tests/scenarios/sp/iss060_ingress_11e.json` (mid-board placement REJECTED by the template; edge placement arrives with the flags; token visually verified at the board edge). Headless 1113/1113. Remaining (minor): the AIRCRAFT reserve cycle (23.02) — no aircraft datasheets in the current armies, deferred until one exists.

### ISS-061 — 11e FLY (take to the skies), surge moves, HOVER
- **Location:** movement/charge code paths with FLY special-casing; rules: 21.01-21.03, 24.17
- **Category:** breaking-change
- **Severity:** medium
- **Description:** FLY becomes an opt-in declaration per move: −2" max distance, ignore vertical, move through models and all terrain (HOVER removes the −2"). **Surge moves** are a new triggered move type (toward closest enemy, must engage surge target if possible; battle-shock/engagement gates) that faction rules will reference.
- **Root cause:** n/a (edition change).
- **Proposed fix:** "Take to the skies" as a mode on normal/advance/fall-back/charge MoveTypes; `SurgeMove` MoveType instance with trigger API for abilities.
- **Dependencies:** ISS-040
- **Affected files:** move types, `MovementController.gd` (declaration UI), ability registry triggers
- **Acceptance criteria:** unit test: 16" advance becomes 14" flying with vertical ignored (pg 71 example); surge move test reproduces the pg 70 example (D6 surge engaging closest unit).
- **Status:** DONE (pathing-leniency consumption + SUPER-HEAVY WALKER noted at the flag's consumption point) — `SurgeMove` joins the registry implementing 21.02 (eligibility: triggered/unshocked/unengaged/unmoved; closest-enemy targeting per the pg-70 example's semantics; max distance from the triggering rule; AFTER: non-target engagement voids the move, no further moves this phase) and `MoveType.take_to_skies_modifier` implements 21.03/24.17 (-2" for FLY, 0 with HOVER, edition-gated — pg-71 example's 16"→14"). `test_iss061_surge_fly_11e.gd` 14/14; suite 893/893. Step 2 (landed): the take-to-the-skies declaration is live in the movement path — BEGIN_NORMAL_MOVE / BEGIN_ADVANCE / BEGIN_FALL_BACK accept `payload.take_to_skies` for FLY units (live-state keyword check): the cap takes the -2" modifier (0 with HOVER; advance applies it in `_resolve_advance_roll` after the D6 + rerolls via `_pending_take_to_skies`), and `active_moves.took_to_skies` is exposed for pathing consumers (move-through-models/terrain leniency + ignore-vertical are flagged for MovementController's path checks — 2D board means vertical is moot today). Windowed: the iss040 scenario's FLY leg asserts the M10 Battlewagon's cap drops to 8" through the real action flow. Remaining (minor): SUPER-HEAVY WALKER (24.35) — same flag-consumption point, deferred with the pathing leniency.

### ISS-062 — AI updated for 11e rules
- **Location:** `40k/scripts/AIDecisionMaker.gd` / `40k/scripts/ai/*` (post ISS-030); depends on shared math (ISS-014)
- **Category:** breaking-change
- **Severity:** medium
- **Description:** AI heuristics encode 10e: 1" ER spacing, cover-as-save, charge-first fight priority, pistol logic, 10e stratagems, no Hidden/detection awareness, no shooting-type or disembark-mode selection. After Tier 3 the AI must at minimum play legally; ideally it understands cover-as-BS, Hidden positioning, secured objectives, and tactical disembarks.
- **Root cause:** n/a (edition change).
- **Proposed fix:** Phase 1 — legality: AI selects valid move/shooting/fight types and modes via the same eligibility APIs as the UI. Phase 2 — competence: update scoring to the shared 11e expected-damage math and new positional values (detection ranges, terrain areas, secured objectives).
- **Dependencies:** ISS-014, ISS-039, ISS-041, ISS-048, ISS-050, ISS-057 (and others as they land)
- **Affected files:** AI modules, `AIPlayer.gd`
- **Acceptance criteria:** AI-vs-AI full game in edition=11 completes with zero illegal-action rejections; AI uses at least: a shooting-type choice, a fall-back mode, and a consolidation mode during the game (asserted from action log).
- **Status:** TODO

### ISS-063 — 11e windowed scenario suite
- **Location:** `40k/tests/scenarios/` (currently ~5 entries incl. schema/dirs); runner `40k/tests/run_scenarios.sh`
- **Category:** missing-feature
- **Severity:** medium
- **Description:** Per the project's validation gate, every player-facing 11e behavior needs a windowed scenario driven over the MCP bridge. The worked examples in the rulebook (attack sequence pgs 20-23, fight phase pgs 39-43, terrain pg 49/51, objectives pg 53) are ready-made scenario specs.
- **Root cause:** n/a (new work).
- **Proposed fix:** One scenario per Tier 3 issue family, built as each lands (acceptance criteria above reference them); plus one full-game smoke scenario (deploy → 5 rounds → scoring) in edition=11.
- **Dependencies:** ISS-038 through ISS-061 (incremental)
- **Affected files:** `40k/tests/scenarios/*.json`, scenario runner
- **Acceptance criteria:** `run_scenarios.sh` green over the 11e suite; suite covers every Tier 3 issue's scenario named in its acceptance criteria.
- **Status:** TODO

---

## Summary table

| ID | Title | Severity | Status | Dependencies |
|---|---|---|---|---|
| ISS-001 | Route all in-game state mutations through pipeline | high | DONE | — |
| ISS-002 | GameConstants module + edition switch | high | DONE | — |
| ISS-003 | Structured ability schema + registry | high | DONE | — |
| ISS-004 | Uniform per-action RNG seeding | high | DONE | — |
| ISS-005 | PhaseControllerBase extraction | high | DONE | — |
| ISS-006 | Remove committed artifacts from git | medium | DONE | — |
| ISS-007 | Guard freed-node access in cleanup | medium | DONE | — |
| ISS-008 | Standardize controller input handling | medium | DONE | (005) |
| ISS-009 | Replace hardcoded /root/ paths | low | TODO | 005 |
| ISS-010 | Move root status docs to docs/history | low | DONE | — |
| ISS-011 | Triage archived/disabled tests | low | DONE | — |
| ISS-012 | Unified AttackSequence (dedupe ranged/melee) | high | DONE | 002, 003 |
| ISS-013 | Signal registry + phase lifecycle out of Main | high | DONE | 005 |
| ISS-014 | AI consumes shared rules math | high | DONE | 012 |
| ISS-015 | Multiplayer: seeds on every dice action | high | DONE | 004, 001 |
| ISS-016 | Consolidated modifier stack | high | DONE | 003, 012 |
| ISS-017 | State accessors + diff-path hardening | medium | DONE | 001 |
| ISS-018 | Per-phase UI container teardown | medium | TODO | 005, 013 |
| ISS-019 | Unify ability checks through ability layer | medium | DONE | 003 |
| ISS-020 | RulesEngine public API for phases | medium | DONE | — |
| ISS-021 | Action log + deterministic replay | medium | DONE | 001, 004 |
| ISS-022 | Verify/extend undo coverage | medium | DONE | 001 |
| ISS-023 | Single source of truth for positions | medium | TODO | 001 |
| ISS-024 | Eliminate stale phase snapshots | medium | TODO | 001, 017 |
| ISS-025 | TurnManager vs PhaseManager ownership | medium | TODO | 001 |
| ISS-026 | MP load-sync failure handling | medium | DONE | — |
| ISS-027 | Main.gd remaining decomposition | medium | TODO | 013, 018 |
| ISS-028 | Save migration framework + fixtures | medium | DONE | 017 |
| ISS-029 | Golden-master replay harness | medium | TODO | 021 |
| ISS-030 | Split AIDecisionMaker into planners | medium | TODO | 014 |
| ISS-031 | BoardState: merge away or document | low | DONE | 017 |
| ISS-032 | AI cache save/load policy | low | DONE | — |
| ISS-033 | Shared dialog base class | low | TODO | — |
| ISS-034 | Remove duplicate/legacy phases | low | DONE | — |
| ISS-035 | Autosave deferral (verify then fix) | low | TODO | — |
| ISS-036 | Disconnect grace period (verify then fix) | low | TODO | 026 |
| ISS-037 | 11e datasheet/army schema + converter | high | DONE | 003 |
| ISS-038 | 11e battle-round/turn structure hooks | high | DONE | 001, 025, 034 |
| ISS-039 | Engagement range 2"/5" | high | DONE | 002 |
| ISS-040 | 11e move-type framework | high | DONE | 001, 002, 038 |
| ISS-041 | 11e attack core: allocation groups | blocker | DONE | 012, 037 |
| ISS-042 | 11e coherency + end-of-turn enforcement | high | DONE | 002, 038, 040 |
| ISS-043 | 11e leadership + battle-shock rework | high | DONE | 037, 038, 016 |
| ISS-044 | Hazard roll mechanic | medium | DONE | 002, 046 |
| ISS-045 | Wound-allocation UI for groups | high | DONE | 041 |
| ISS-046 | 11e mortal wounds + dev-wounds cap | high | DONE | 041 |
| ISS-047 | 11e weapon abilities | high | DONE | 003, 041 |
| ISS-048 | 11e shooting types | high | DONE | 040, 037, 047 |
| ISS-049 | 11e charge phase | high | DONE | 039, 040 |
| ISS-050 | 11e fight phase restructure | blocker | DONE | 039, 040, 049 |
| ISS-051 | 11e terrain data model | blocker | DONE | 002 |
| ISS-052 | 11e visibility (Hidden/Obscuring/Solid) | blocker | DONE | 051 |
| ISS-053 | Cover + Plunging Fire as BS modifiers | high | DONE | 051, 052, 016, 041 |
| ISS-054 | 11e terrain movement + MOBILE | medium | DONE | 051, 040, 037 |
| ISS-055 | 11e objectives + Secured | medium | DONE | 051, 038, 043 |
| ISS-056 | 11e core stratagems + per-unit limit | medium | DONE | 043, 044, 048, 049, 050 |
| ISS-057 | Actions system | high | DONE | 038, 039, 040, 043 |
| ISS-058 | 11e transports (modes, emergency) | high | DONE | 040, 044, 043 |
| ISS-059 | 11e attached units (Support, T, persistence) | medium | DONE | 037, 041 |
| ISS-060 | 11e reserves/ingress/aircraft | medium | DONE | 040, 038, 056 |
| ISS-061 | 11e FLY/surge/hover | medium | DONE | 040 |
| ISS-062 | AI updated for 11e | medium | TODO | 014, 039, 041, 048, 050, 057 |
| ISS-063 | 11e windowed scenario suite | medium | TODO | 038-061 (incremental) |
