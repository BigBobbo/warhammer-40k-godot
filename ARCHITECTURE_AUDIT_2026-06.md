# Architecture Audit — June 2026

Scope: full-codebase architecture review of the Godot 4.4 Warhammer 40k implementation,
plus a delta analysis against the **new-edition core rules** (the uploaded
`warhammer40k_core_rules8.txt`, which is the next edition: 2" engagement range,
defender-ordered save allocation, terrain categories, Actions, Ingress/Surge moves, etc.).

Method: four parallel deep-dive reviews (core state/phases, rules layer, UI/controllers,
AI/network/save) plus first-hand verification of the highest-impact claims. Findings that
were verified by reading/grepping the code directly are cited `file:line`. A small number
of subagent claims were found to be **wrong** during verification and are corrected here
(noted inline) — treat any "missing rule" claim below that lacks a ✅verified tag as a
lead to confirm, not a settled fact.

---

## 1. Executive summary

The game is feature-rich and clearly works, but it has the classic shape of a codebase
grown by many incremental edits with no periodic consolidation:

- **~177k lines of non-test GDScript**, with four god objects accounting for ~47k of them:
  `AIDecisionMaker.gd` (17,659 lines), `Main.gd` (12,004), `RulesEngine.gd` (11,716),
  `MovementPhase.gd` (7,795).
- **45 autoloads** (~49k lines) with overlapping ownership of state, rules, and UI.
- **State mutation has no single gate.** There is an action/diff pipeline
  (`execute_action → validate → process → apply_state_changes`), but code also mutates
  `GameState.state` directly (verified: `phases/FormationsPhase.gd:593,598,767`), which
  silently bypasses replay, undo, and network sync.
- **The same rules math exists in 3+ places** (RulesEngine ranged path, RulesEngine melee
  path, AIDecisionMaker's private probability functions, Mathhammer), and rule constants
  are duplicated literals (verified: engagement range `1.0` hardcoded at
  `RulesEngine.gd:7598`, `RulesEngine.gd:7782`, and as the default in
  `Measurement.gd:266`).
- **Weapon abilities are comma-separated strings parsed by regex** at resolve time
  instead of structured data — brittle today, and a direct blocker for the new edition's
  keyword-scoped abilities (`[LETHAL HITS: VEHICLE]`).
- The new edition is **not a patch — it rewrites the attack sequence, terrain, the fight
  phase, transports, and movement**. Porting it onto the current architecture would mean
  re-editing all four god objects in their most tangled regions. The edition migration is
  the right forcing function for the refactor.

**Core recommendation:** don't refactor *and then* port, and don't port *without*
refactoring. Stand up a small, clean rules core shaped like the new rulebook itself
(it is practically an architecture spec — every move/shooting/fight type follows the same
`ELIGIBLE IF / BEFORE / WHILE / AFTER` template), migrate systems onto it incrementally,
and route every actor (human UI, AI, network, replay, tests) through one action pipeline.

---

## 2. Codebase metrics (verified)

| Area | Files | Lines |
|---|---|---|
| `autoloads/` | 45 | 48,872 |
| `phases/` | 15 | 30,916 |
| `scripts/` | 109 | 90,263 |
| `dialogs/` | 34 | 6,328 |
| `tests/` | 267 | 81,431 |
| `addons/` | 75 | 18,214 |

Largest non-test files: `AIDecisionMaker.gd` 17,659 · `Main.gd` 12,004 ·
`RulesEngine.gd` 11,716 · `MovementPhase.gd` 7,795 · `ShootingPhase.gd` 6,465 ·
`ShootingController.gd` 5,664 · `MovementController.gd` 4,873 · `FightPhase.gd` 4,474 ·
`UnitAbilityManager.gd` 4,171.

Repo hygiene (verified): **152MB** of artifacts committed under `40k/test_results/`,
11MB under `40k/saves/`, 1.4MB `logs/`, plus ~40 status/plan markdown files and
`ai_fix_loop_*` artifacts at the repo root. `tests_archived_disabled/` holds 11 entries
(subagent counted 52 test files inside it, unverified).

---

## 3. Top cross-cutting problems (ranked)

### P1. No single state-mutation gate
`GameState.state` is one big untyped Dictionary. Mutations happen via at least four
routes: direct dict writes (✅verified `FormationsPhase.gd:593`), `apply_state_changes()`
string-path diffs (`PhaseManager.gd:328-444`), explicit setters
(`GameState.set_phase()` etc.), and convenience methods (`advance_turn()`).
Direct writes are invisible to replay, undo, and multiplayer. The diff system itself
navigates `"units.U_1.models.0.current_wounds"` by `split(".")` — magic strings with no
existence validation. (Correction vs. an earlier draft: undo is *not* dead code —
`GameManager.undo_last_action()` at GameManager.gd:975 pops and applies reverse diffs —
but its correctness depends on every mutation flowing through the diff pipeline, which
the direct writes above break.)

### P2. Rules math duplicated across actors
- RulesEngine has parallel ~1,000-line ranged (`_resolve_assignment`, ~line 2202) and
  melee (`_resolve_melee_assignment`, ~line 8647) resolution bodies with inline
  copies of ability handling (lethal/sustained/devastating/anti/precision).
- AIDecisionMaker reimplements hit/wound/save probability privately
  (`_hit_probability`/`_wound_probability`/`_save_probability`, ~lines 15320-15850)
  including its own cover logic, instead of calling RulesEngine.
- Mathhammer UI computes expectations separately again.
Any rules change must now be made 3-4 times, and the AI's evaluation can silently
diverge from what the dice actually do.

### P3. Rule constants are scattered literals
✅verified: engagement range is `const ENGAGEMENT_RANGE_INCHES = 1.0` declared *locally
inside two different functions* (`RulesEngine.gd:7598,7782`) and again as a default
parameter (`Measurement.gd:266`). Coherency distances, detection ranges, and similar are
likewise inline. The new edition changes engagement range to 2" and rewrites coherency —
under the current layout that's a grep-and-pray exercise.

### P4. Main.gd is a 12k-line orchestrator
153 `.connect()` calls; instantiates/destroys all five phase controllers with per-signal
manual disconnects (`Main.gd:4123-4156` hand-disconnects 8+ ShootingPhase signals);
clears phase UI by matching against a hardcoded list of ~30 node-name strings
(`Main.gd:9599-9627`); holds 200+ UI references; its own `_unhandled_input` is an empty
`pass` (`Main.gd:11881`) while real input handling is scattered across controllers.

### P5. Five phase controllers are copy-paste siblings (~20k lines, no base class)
`_setup_ui_references()` is byte-identical across controllers
(`ShootingController.gd:307`, `MovementController.gd:252`, `ChargeController.gd:255`,
`FightController.gd:130`); each rebuilds the right panel from scratch in code
(~75% similar); input handling is inconsistent (`_input` in Shooting/Fight,
`_unhandled_input` in Movement/Deployment), risking hotkey conflicts during phase
transitions. Estimated 2,000–2,500 lines are pure duplication. Almost all UI is built in
code; `Main.tscn` is the only meaningful scene and dialogs have no .tscn at all.

### P6. AIDecisionMaker is a 17.7k-line monolith outside the rules pipeline
150+ static functions, 8 static caches (not serialized — AI behavior changes after
save/load), per-stratagem hardcoded heuristics, its own deployment/movement validity
logic. It produces decisions that are only validated when the phase executes them.

### P7. Determinism is partial, so replay/multiplayer rest on sand
RulesEngine has an RNGService with test seeding, but in live play RNG isn't centrally
seeded per action. NetworkManager embeds an RNG seed **only for `BEGIN_ADVANCE`**
(`NetworkManager.gd:840-847`); other rolls rely on broadcasting results via RPC.
Saves are full snapshots, not action logs — no deterministic replay from turn 1, and no
way to diagnose a desync after the fact.

### P8. Phases reach into RulesEngine internals
`ShootingPhase` calls `RulesEngine._check_units_in_engagement_range()` and
`_apply_damage_to_unit_pool()`; FightPhase uses `_generate_weapon_id()`. The "public API
returns diffs" discipline exists but is leaky, which makes decomposing RulesEngine harder
the longer it waits.

### P9. State duplicated across layers
Model positions live in `GameState`, in `TokenVisual.model_data`, and in controller-local
drag state (`MovementController.gd:3590,3607`); `BoardState` (161 lines — a small shadow
of GameState's board data, sizes corrected from an earlier draft) overlaps GameState;
each phase keeps a `game_state_snapshot` shallow copy that can go stale
(`BasePhase.gd:13,99`).

### P10. Repo and test hygiene
152MB of committed screenshots/test artifacts; root directory full of one-off status
docs; a custom `extends SceneTree` test harness with a known mix of behavioral tests and
shape-only "pin tests" (already documented as an anti-pattern in CLAUDE.md);
disabled/archived test directories that no runner executes.

Corrections to subagent claims, found during verification:
- "AIDecisionMaker is 762k lines" — **wrong**, it is 17,659 lines (~762KB).
- "HEAVY +1-to-hit not implemented" — **wrong**, it is implemented
  (`RulesEngine.gd:1602,2156,2500,3307`).
- "Hazardous missing in melee" — at least partially wrong; FightPhase carries hazardous
  self-damage diffs from the hit/wound step (`FightPhase.gd:1605`). Full-path correctness
  not verified either way.

---

## 4. Rules coverage today (10th edition)

Broadly solid: the full attack sequence with modifiers; weapon abilities
(LETHAL/SUSTAINED/DEVASTATING/ANTI-X/BLAST/TORRENT/RAPID FIRE/MELTA/TWIN-LINKED/LANCE/
HEAVY/PISTOL/ASSAULT/IGNORES COVER/PRECISION/HAZARDOUS/INDIRECT); battle-shock; cover;
Big Guns Never Tire; overwatch; charges incl. terrain penalties; pile-in/consolidate;
transports; deep strike/reserves/infiltrators/scouts; leader attachment; FNP; deadly
demise; lone operative; stealth; 12 core stratagems plus faction stratagems; Waaagh!,
Oath of Moment, Combat Doctrines; missions/secondaries.

Reported gaps to confirm (unverified leads from the rules review): aircraft rules,
Firing Deck, disembark-then-charge restriction enforcement, coherency enforcement during
normal moves (vs. charges where it is checked), desperate-escape edge cases. The
implemented-rules table in the review showed the engine is at roughly "75%+ of core,
nearly all of the commonly-played core."

---

## 5. New-edition delta — what the uploaded rules change

This is the next edition, not a 10th-edition revision. The mechanically significant
changes, mapped to the systems they hit:

| Change (new edition) | Replaces (10th, as implemented) | Code impacted |
|---|---|---|
| **Engagement range 2"** (5" vertical) (03.04) | 1" | `RulesEngine.gd:7598,7782`, `Measurement.gd:266`, every charge/fight/pile-in path, AI threat ranges |
| **Coherency: 2" of one model AND 9" of every model**; end-of-turn removal of stragglers as destroyed-without-triggers (03.03) | 2" of 1 (2 if 7+ models) | Movement validation, end-of-turn step (doesn't exist as a rules hook today) |
| **Attack sequence: identical attacks gathered; defender creates allocation groups (per-CHARACTER + same W/Sv/InSv), declares allocation order, damage applied lowest→highest save** (04-05) | Attacker resolves per-attack; defender allocates per wound | The single biggest hit: both RulesEngine resolve paths, `WoundAllocationOverlay.gd` (1,999 lines), save UI, AI damage estimates, Mathhammer |
| **Mortal wounds: per-MW model-selection priority (wounded non-CHARACTER first, CHARACTER last); normal damage fully resolved before MW** (06.02) | MW allocation like normal wounds, spillover | RulesEngine `apply_mortal_wounds`, devastating wounds path |
| **DEVASTATING WOUNDS: ends attack sequence, D mortal wounds, max one model damaged per crit — excess lost** (24.10) | MW pool spills | RulesEngine dev-wounds conversion |
| **Leadership = 2D6 roll vs Ld "X+"; battle-shock step rolls for battle-shocked AND at-or-below-half-strength units; shocked units can recover; shocked units can't be stratagem targets or start actions** (01.06-07, 08.03) | Below-half only; shock until next command phase | CommandPhase, datasheet stats schema (Ld format), StratagemManager targeting, OC |
| **Hazard rolls: D6, 1-2 fails → 1 MW (3 if all M/V)** — used by HAZARDOUS, desperate escape, combat/emergency disembark (06.03) | Hazardous fails on 1 only, different damage | RulesEngine hazardous, plus new call sites in movement/transport |
| **Move types as uniform templates** — remain stationary / normal / advance / fall back (modes: ordered retreat vs desperate escape) / disembark (rapid/tactical/combat modes) / ingress / scout / surge / pile-in / consolidation / charge, each with ELIGIBLE IF / BEFORE / WHILE / AFTER blocks (03, 09, 18, 20, 21) | Ad-hoc per-phase movement code | MovementPhase (7.8k lines), TransportManager, ChargePhase, FightPhase |
| **Shooting types**: normal / assault / **close-quarters** (replaces PISTOL & Big Guns Never Tire; M/V get -1 hit vs engaged) / indirect (core: 1-5 fails unless stationary + spotter, then 1-3) / snap shooting (10, 15.09, 17.03, 24.07) | Pistol + BGNT special cases | ShootingPhase, RulesEngine targeting/modifiers, AI |
| **Charge: targets ≤12" AND ≤roll; must engage all targets, none else; charging grants the Fights First *ability*** (11) | Similar but 1" completion, "charged" flag ordering | ChargePhase, FightPhase ordering |
| **Fight phase restructured: global Pile In step (both players) → Fight step (alternate Fights First, then remaining, with pass rules) → global Consolidate step; overrun fights; consolidation modes (ongoing/engaging/objective)** (12) | Pile-in → attacks → consolidate *per activation* | FightPhase (4.5k lines) — near rewrite |
| **Terrain: categories (exposed/light/dense) + terrain *areas*; benefit of cover = worsen BS by 1; Hidden (15" detection); Obscuring areas; Solid (no LoS through ≤3" gaps); Plunging Fire (+1 BS); MOBILE keyword** (13, 22.05) | Ruins/obscuring walls, cover = save modifier | TerrainManager, `EnhancedLineOfSight`/`LineOfSightManager` autoloads, cover checks in RulesEngine, terrain layouts, AI cover logic |
| **Objectives: terrain areas as objectives; 40mm marker fallback (3" horiz/5" vert); control evaluated end of each phase; Secured ("sticky") objectives core** (14) | 40mm markers, end-of-turn checks | MissionManager, ScoringPhase |
| **Stratagem rules: same stratagem 1×/phase AND ≤1 stratagem per unit per phase; new core set** — Explosives, Crushing Impact, Fire Overwatch (snap shooting, end of opponent's Movement only), Heroic Intervention (a real charge with modes), Counteroffensive (2CP +1CP option), Rapid Ingress, Smokescreen, Epic Challenge, Insane Bravery (1×/battle), Command Re-roll (single die; charge rolls in full) (15) | 10th core set, Grenade/Tank Shock | StratagemManager, AI stratagem heuristics |
| **Actions system** (start/complete, eligibility, OC/battle-shock interplay) (16) | n/a | New subsystem; missions will depend on it |
| **Transports: embark after any move ≤3"; disembark modes — rapid 3", tactical 3" *then the unit makes a normal/advance move*, combat 6" + hazard rolls + set up engaged + battle-shocked; emergency 6" + hazard rolls** (18) | 3" disembark, no modes | TransportManager, MovementPhase, AI |
| **Attached units: Leader AND new Support slot; attacks use highest bodyguard T; ability-persistence matrix; revived-model rules** (19) | Leader only | CharacterAttachmentManager, RulesEngine targeting |
| **Reserves: ingress move (6" from edges, >8" enemies, no opponent DZ before round 3); reserves die end of round 3; Deep Strike = ingress anywhere >8"; Rapid Ingress at start of opponent's Shooting phase; AIRCRAFT cycle via reserves every turn** (20, 23, 24.09) | 10th reserves | DeploymentPhase/reinforcements, AI |
| **FLY = optional "take to the skies" (−2" but move through everything); HOVER; Surge moves; SUPER-HEAVY WALKER rework** (21, 24) | 10th FLY | Movement |
| **New/changed weapon abilities: CLEAVE, CLOSE-QUARTERS, ONE SHOT, keyword-scoped abilities (`[LETHAL HITS: VEHICLE]`), PRECISION now manipulates allocation-group order, [PSYCHIC] ignores hit modifiers, LETHAL HITS is now a *choice*** (24) | string-parsed ability set | Weapon data schema + RulesEngine — this is where regex parsing breaks down |
| **Lone Operative: 12" visibility AND indirect-fire protection; Infiltrators >8"; Scouts can redeploy from reserves; HEAVY = +1 hit if ≤3" moved, your Shooting phase only** (24) | 10th versions | RulesEngine ability checks |

**Implication:** the changes concentrate exactly where the architecture is weakest — the
two duplicated resolve paths, wound allocation UI, the fight phase, terrain/LoS, and the
string-parsed weapon abilities. A straight port would mean simultaneous surgery on all
four god objects.

---

## 6. Recommended target architecture

The new rulebook's own structure is the best design document available: numbered rule
modules, and every move/shooting/fight type expressed as a uniform template
(`ELIGIBLE IF / BEFORE / WHILE / AFTER`, with named *modes*). Mirror it:

1. **One action pipeline, no exceptions.**
   `submit_action(action) → validate → resolve → diffs → apply + broadcast + log`.
   Human UI, AI, network peers, replays, and tests all enter here. Direct
   `GameState.state[...] =` writes become lint-failures. Reverse diffs from the same
   pipeline give undo for free; logging actions (with RNG seeds) gives replay and
   multiplayer determinism for free.

2. **Typed-ish state with a schema.** Full typed-object migration is optional, but at
   minimum: one schema definition, accessor functions instead of raw paths, and a
   validator run in tests and on load. Eliminate `BoardState`/snapshot duplication; make
   visuals pure derivations of GameState.

3. **Decompose RulesEngine along the rulebook's seams** (each a plain `RefCounted`/static
   class, not an autoload):
   - `AttackSequence` — hit/wound/save/damage, **one** implementation parameterized by
     ranged/melee context (kills the 2×1,000-line duplication).
   - `Allocation` — the new defender-ordered allocation groups, used by both the engine
     and the wound UI.
   - `MoveTypes` — one small class per move type implementing the shared template;
     phases just ask "which move types is this unit eligible for".
   - `ShootingTypes`, `FightSequence`, `TargetingAndVisibility` (terrain categories,
     Hidden, Obscuring, Solid, cover), `Morale`, `Reserves`, `Transports`.
   - `GameConstants` — engagement range, coherency, detection range, defined once
     (and edition-switchable if you want to keep 10th playable during migration).

4. **Structured ability data, registry-driven.** Replace
   `"special_rules": "anti-infantry 4+, devastating wounds, rapid fire 1"` with
   `"abilities": [{"id":"anti","keyword":"INFANTRY","x":4},{"id":"devastating_wounds"},
   {"id":"rapid_fire","x":1}]`. A loader validates every ability id against a registry at
   import time (typos become load errors, not silently-ignored rules). The registry entry
   owns the hook implementation (on_hit_crit, gather_dice, etc.). This is the only sane
   way to support keyword-scoped abilities and the new-edition additions.

5. **Modifier stack.** A single place where effects (cover worsens BS, Plunging Fire
   improves BS, stratagems, auras, battle-shock) register modifiers that the attack
   sequence queries — replacing flag soup spread across EffectPrimitives,
   UnitAbilityManager, FactionAbilityManager, and inline RulesEngine checks.

6. **UI: one `PhaseControllerBase`,** owning the shared lifecycle
   (ui refs, panel container, input enable/disable, signal registry with bulk
   disconnect). Each phase controller shrinks to: input → action mapping, plus
   phase-specific visuals. Give each phase a single named container node so teardown is
   one `queue_free()`, not 30 name-pattern matches. Standardize on `_unhandled_input`
   and gate by "am I the active controller".

7. **AI consumes the engine.** Expose `AttackSequence.expected_damage(weapon, target,
   modifiers)` and reuse it from AI and Mathhammer. Split AIDecisionMaker into per-phase
   planners that emit actions into the pipeline like any other player.

8. **Determinism as a property, not a feature.** Central seeded `RNGService`; every
   dice-rolling action either carries a seed or is resolved host-side with results in the
   diffs. Then a save = initial state + action log (snapshots become a cache), replay is
   exact, and desyncs are diagnosable.

---

## 7. Suggested roadmap

- **Phase 0 — hygiene (cheap, immediate):** remove `40k/test_results/` (152MB), `logs/`,
  `ai_fix_loop_*` outputs and stale saves from git (+.gitignore); move the ~40 root
  status .md files into `docs/history/`; delete or revive archived/disabled tests.
- **Phase 1 — state integrity:** route the known direct mutations
  (FormationsPhase warlord writes, any others a lint pass finds) through the pipeline;
  add a debug-build guard that asserts GameState is only mutated inside
  `apply_state_changes`; centralize RNG seeding per action.
- **Phase 2 — UI consolidation:** `PhaseControllerBase`, signal registry, per-phase UI
  container. ~2-2.5k lines deleted, phase transitions become robust. Pull phase-lifecycle
  and controller management out of Main.gd.
- **Phase 3 — rules core:** extract `GameConstants`; build `AttackSequence` +
  ability registry + structured weapon schema (write a one-off converter for the army
  JSONs); make RulesEngine delegate to them so existing behavior is preserved and tested
  before anything is deleted.
- **Phase 4 — new edition on the new core:** implement move/shooting/fight type
  templates, terrain categories, allocation groups, Actions — as registry/data additions
  rather than monolith edits. Keep an edition flag if 10th must stay playable.
- **Phase 5 — AI rebase:** point AI scoring at the shared expected-damage API; split the
  monolith per phase; serialize or deliberately discard AI caches on save.

Validation per the project's own gate: every player-facing change lands with a windowed
scenario (`40k/tests/run_scenarios.sh`) driven over the MCP bridge; pure-math extraction
phases (3) should additionally use golden-master tests — record action logs of full games
on the old code, replay on the new code, assert identical final state.
