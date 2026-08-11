# AI Plan Maker — implementation task list

Created 2026-08-10 on branch `claude/wh40k-ai-feasibility-ucj3hm`. Revised the
same day after a six-agent adversarial verification pass that checked every
mechanism below against the code; all `file:line` cites in this revision were
verified at commit time (they can still drift — re-grep before relying on one).
Companion: `research/ai_feasibility_2026-08-09.md` (the feasibility assessment
that motivates this work).

## What is being built, in one paragraph

A data-driven **plan system** for the game's AI: JSON "plans" that describe,
for a specific army list on a specific deployment map (and optionally a
specific terrain layout), (a) exactly how to deploy — order, per-model
positions, reserves, transport embarkations, leader attachments — and (b)
high-level per-unit intents for the game ("hold objective X", "push center",
"screen", …). Players author these plans **inside the game** (deploy the AI's
army by hand and hit *Save as Plan*, then paint intents on units), and can pit
plan against plan in an AI-vs-AI **simulator**. The AI consumes the same
artifact: when a plan matches the current game it follows it, degrading
gracefully to its existing logic whenever the plan does not apply. End state
after all tasks: the three player-facing stages work — **Deployment
Recorder**, **Intent Painter**, **Simulator** — plus the AI-side consumption
that makes plans meaningful, and one shipped real plan (recon_stomps) proven
against the current AI in the lab.

## Why (from the feasibility research — do not re-litigate)

- The AI's deployment today is a deterministic column formula
  (`AIDecisionMaker.gd:3912` `_decide_deployment`; picks `deploy_actions[0]`
  at 3923-3924, column `deployed_count % num_columns` at 4001-4004).
  Deployment "largely decides rounds 1-2" per the AI's own source.
- Every measured micro-tactical improvement in this repo's lab scored ~zero
  VP; the only large measured effect was a strategic pre-decision (reserves
  cap). Authored strategy is the evidence-backed lever. Precedents: chess
  opening books, StarCraft build orders, Combat Mission's authored
  per-scenario AI plans, paper automas.

## Design decisions LOCKED (revised where verification corrected them)

1. Plans are **data** (JSON), the same artifact whether authored by hand, by
   the recorder UI, or by an LLM offline. No separate authoring format.
2. Plans are **intents with fallback chains, never scripts**. A plan must be
   *unable* to produce an illegal game state: every placement resolves
   through validation with repair, every intent falls back to the AI's
   current logic when it cannot apply. (Cautionary tale: the
   Heroic-Intervention deadlock, `research/ai_improvement_status_2026-08-07.md` §6.)
3. Plans are keyed to **specific lists on specific deployments**. Archetype
   generalization is deferred; the fallback for a missing plan is simply the
   current AI behavior.
4. Units are referenced by **army-file unit id** (e.g. `U_STORMBOYZ_A`) with
   `unit_name` + `role_fallback` as the degradation path for edited lists.
   *(Revised: the draft said "by unit name, never ids" — but unit names are
   NOT unique: recon_stomps has 4× "Stormboyz", 4× "Warbikers"; the army-file
   ids are authored, stable keys that survive into `GameState.state.units`
   verbatim (`ArmyListManager.gd:333-350`; only a same-list-mirror P2 copy is
   re-keyed with a deterministic `_P2` suffix, 341-346).)*
5. **Plan coordinates are always authored in the player-1 zone frame.** A
   consumer seated as player 2 MUST transform placements by the 180° board
   rotation `[x, y] → [44 − x, 60 − y]` (board is 44×60 inches; all shipped
   deployment zones are point-symmetric — verify per map when adding new
   ones). Without this, every seat-2 placement fails wholly-in-own-zone
   validation (`DeploymentPhase.gd:147-158, 306-307`) and the plan silently
   degrades to formula — which would make the simulator's headline
   plan-vs-plan case measure nothing.
6. The plan maker lives **in Godot**, reusing the real phase flow in a
   sandbox session — never a forked editor scene, never a web app.
7. The intent vocabulary is **five verbs** (PM-0). `TRADE` was cut from v1
   (no per-unit parameter mechanism exists to implement it — a dead button
   erodes trust); the validator rejects it as "reserved for v2".
8. Dice are never fudged. Plans and the simulator use the normal engine.
9. Plans apply at **Normal, Hard and Competitive**; Easy ignores them by
   construction (EASY short-circuits to `_decide_random`,
   `AIDecisionMaker.gd:2279-2280`). The hooks plans use — deployment,
   `_assign_units_to_objectives`, screening pass, target scorers — all run at
   Normal+; only the unrelated `_build_phase_plan` (charge/lock plan) is
   HARD-gated (`AIDecisionMaker.gd:2342-2344`).

## Canonical names (use EXACTLY these everywhere)

- Schema/JSON/code word: **earmark**. "Intent" is the player-facing word in
  UI copy only.
- Session flag: `plan_editor: true` **inside `meta.game_config`** (config
  dict built at `MainMenu.gd:1424-1443`, stored to `meta.game_config` at
  1519/1583). All tasks read exactly this.
- Enable gate: numeric param `PLANS_ENABLED` (default 1) **inside the
  `parameters` object** of `40k/data/ai_config.json`, read via
  `AIDecisionMaker.get_param("PLANS_ENABLED", 1.0) > 0.5`. (Top-level keys
  are dead: the loader reads only `parameters` — `AIDecisionMaker.gd:313-318`
  and the file's own `_readme` say so.)
- Bench plan injection: `BENCH_P1_PLAN` / `BENCH_P2_PLAN` env vars +
  `--bench-p1-plan/--bench-p2-plan` flags (delivered in PM-2a), mirroring the
  existing profile flags (`AIBenchmarkRunner.gd:107-110`).
- px↔inch conversion: `Measurement.PX_PER_INCH = 40.0`
  (`40k/autoloads/Measurement.gd:7`, helpers `inches_to_px`/`px_to_inches` at
  14/17) for UI/board code; `AIDecisionMaker.PIXELS_PER_INCH = 40.0`
  (`AIDecisionMaker.gd:24`) inside AIDecisionMaker. Do not grab stray `40.0`
  literals.

## Global context every task instance needs

Work happens in this repo (`/home/user/warhammer-40k-godot` locally; adjust to
your checkout). Godot 4.4; game project root `40k/`. Read `CLAUDE.md` at repo
root first — it defines the validation gates, the screenshot-in-TLDR rule, and
how to run the game windowed in a container (`export PATH="$HOME/bin:$PATH";
godot --headless --import` once, then `godot --path 40k --rendering-method
gl_compatibility` under the shim's xvfb; the in-game MCP bridge on port 9080
provides `capture_screenshot`, `verify_delivery`, `read_debug_log`,
`simulate_click`, `dispatch_action`, `execute_script`).

**The designated git branch** is whatever branch this file is checked out on
when your session starts (`git branch --show-current`) — at revision time,
`claude/wh40k-ai-feasibility-ucj3hm`. Never create a new branch or push
elsewhere; if you find yourself on `main`, stop.

**Headless unit tests**: the maintained convention is a standalone
`extends SceneTree` script under `40k/tests/unit/` with a `_check(label,
cond)` helper printing `PASS:`/`FAIL:` lines and a final
`=== Results: N passed, M failed ===`, exiting nonzero on failure (imitate
`tests/unit/test_ai_against_all_odds.gd`). Run:
`cd 40k && godot --headless --path . -s tests/unit/test_x.gd` (after a
one-time `godot --headless --import`). Register new tests in the `TESTS`
array of `40k/tests/run_pretrigger_tests.sh`. Do NOT write GUT tests — the
GUT suite is legacy and unmaintained (`40k/tests/unit/README.md`), despite
what `RUN_TESTS.md` says.

**Windowed scenarios**: `40k/tests/scenarios/_schema.md` documents the format;
scenarios live in `40k/tests/scenarios/sp/`. `bash 40k/tests/run_scenario.sh
tests/scenarios/sp/<id>.json` runs ONE scenario; `run_scenarios.sh` is the
batch runner. Scenario steps are `click_unit` / `click_node` /
`click_item_list` / `click_board_at` / `drag_board` / `simulate_key` /
`dispatch_action` / `execute_script` / `wait_seconds` / `expect_state` /
`expect_node_visible` (polls with `timeout_s`) etc. — the full step inventory
is `ScenarioRunner.gd:476-568`. (`simulate_click` is an MCP *bridge* command,
not a scenario step — don't confuse them.) There is **no text-input step**:
set a LineEdit via a multiline `execute_script` step, or per-character
`simulate_key` with the undocumented `unicode` field
(`ScenarioRunner.gd:1183-1192`). Scenarios without a `fixture` start on the
main menu (precedent: `sp/main_menu_defaults.json`). Click-deploy exemplars:
`sp/deploy_reposition_rotate_mouse.json`, `sp/iss067_scout_reserves_deploy_11e.json`
(NOT `377_defender_deploys_first.json` — it contains only asserts).

Key code map (verified):

| Thing | Where | Notes |
|---|---|---|
| AI deployment decision | `40k/scripts/AIDecisionMaker.gd:3912` `_decide_deployment` | emits `{"type":"DEPLOY_UNIT","unit_id","model_positions"(px Vector2 array),"model_rotations","_ai_description"}` (4123-4129); `_record_choice("deployment",…)` at 4081-4083 |
| AI formations decision | `AIDecisionMaker.gd:3202` `_decide_formations`; reserves eval `_evaluate_reserves_declarations` (3632) | **reserves/embark/attach are FORMATIONS-phase decisions**, not deployment |
| AI objective assignment | `AIDecisionMaker.gd:7950` `_assign_units_to_objectives` | greedy (unit × objective) with named additive `_t_add` terms + `get_param` (8076-8139); screening/denial/corridor is **pass 3 over leftover units only** (8646, 8684-8706) |
| Per-attacker target scorers | `_score_shooting_target` (20194, CHARACTER ×1.2 at 20367-70), `_score_charge_target` (14595, `CHARGE_CHARACTER_BONUS` 14622-24), `_score_fight_target` (16232-34) | where HUNT_CHARACTERS hooks; NOT the army-wide `_calculate_target_value` (13404) |
| Deployment actions & legality | `40k/phases/DeploymentPhase.gd` | human confirm sends plain `DEPLOY_UNIT` normally; `COMPOSITE_DEPLOY` only with embark/attach (`DeploymentController.gd:1118-1199`); legality = wholly-in-own-zone, no overlaps, walls, coherency (90-195, 290-329); reserves cap check 463-479 |
| Formations phase | `40k/phases/FormationsPhase.gd` | `DECLARE_RESERVES`/`UNDECLARE_RESERVES` (105-112, 368-420); 50% points + unit caps (400-420); both players must `CONFIRM_FORMATIONS` (699-714) |
| Phase flow | `40k/autoloads/PhaseManager.gd` | new game: FORMATIONS → ROLL_OFF → DEPLOYMENT → REDEPLOYMENT → FIRST_TURN_ROLLOFF → …; completion auto-advance in `_on_phase_completed` (380-407); `reset()` 73-81 |
| Deployment alternation | `40k/autoloads/TurnManager.gd:112-175, 238-250` | defender deploys first; alternates per action; pins to the only side with undeployed units — an empty P2 needs no pass-AI |
| Profile machinery (mirror for plans) | `AIDecisionMaker.load_player_profile` (324) / `clear_player_profile` (331); `AIPlayer.configure()` clears profiles per game (`AIPlayer.gd:323-325`); `reset_caches()` (249) deliberately does NOT clear them | `set_player_plan` mirrors this; simulator must re-apply plans after each per-game `configure()` |
| Config layering | `get_param` (467): rule overrides → per-player profile → global config → default | `40k/data/ai_config.json` `parameters` only; `docs/AI_TUNING.md` |
| Suggest-action snapshot contract | `_snapshot_planning_state` / `_restore_planning_state` (`AIDecisionMaker.gd:2416-2455`) | any NEW mutable plan/earmark static MUST be added to both, or the human-hint preview corrupts live AI state |
| Army lists | `40k/autoloads/ArmyListManager.gd` (`load_army_list` 54, `apply_army_to_game_state` 312, display names `_assign_display_names` 719-749) | units keyed `U_*` (stable); `meta.name` NOT unique; Greek-suffixed `display_name` assigned at load |
| Deployment zones | `40k/deployment_zones/*.json` via `40k/scripts/data/DeploymentZoneData.gd` | inches, 44×60 board, `{player, poly:[{x,y}…]}`; `get_zones()` falls back to hammer_anvil on unknown id (48-50) so it is NOT an existence check; point-in-poly via `Geometry2D.is_point_in_polygon` (pattern: `DeploymentPhase.gd:367`) |
| Terrain layouts / objectives | `40k/terrain_layouts/*.json`, `MissionManager.gd` (`get_objective_ids_by_designation` 292) | objective ids `obj_home_1`… stable; `ObjectiveVisual` is NOT clickable (plain Node2D) |
| Game identity for matching | `meta.game_config.player1_army/player2_army/deployment/terrain/mission` (menu games only — **fixtures carry an empty `game_config`**); `meta.deployment_type` (`GameState.gd:51`); `board.terrain_layout` (`GameState.gd:1424`) | fixture fallback matching needed (PM-1) |
| Benchmark harness | `40k/autoloads/AIBenchmarkRunner.gd`, `40k/tests/run_ai_benchmark.sh` | **one game per process, cmdline-gated (`--ai-benchmark`, :95-97), fixture-only (`SaveLoadManager.load_game`, :274-277), quits on every exit path (`_write_and_quit`, :606-618)**; N games = shell loop; raises `_max_decision_record_batches` after `configure()` (:324-326) because the 500-batch ring drops game-start records |
| Seeding triple | `RulesEngine.set_test_seed` (`RulesEngine.gd:636-638`, −1 disables), `SecondaryMissionManager.set_test_seed` (:66-71), `AIDecisionMaker.set_ai_seed` (791-798, −1 re-randomizes) | applied per process at `AIBenchmarkRunner.gd:292-306`; all callable in-session |
| Replays | `40k/autoloads/ReplayManager.gd` (`auto_record_ai = true`, :39, 247-249); watch from menu `MainMenu.gd:1854-1881` | the real "rewatch a sim game" path; AITurnSummary/Replay panels are LIVE-only (no file loading) |
| Menu reality (11e) | Mission and Deployment dropdowns are HIDDEN derived displays (`MainMenu.gd:833-864`); deployment auto-snaps to the layout's `recommended_deployments[0]` (990-1006) | "select hammer_anvil" is not a UI action today; the Plan Editor needs its own zone picker |
| From-menu game bootstrap | `MainMenu._initialize_game_with_config` (`MainMenu.gd:1499-1591`) | armies + terrain + zones + mission + secondaries; the extraction target for the simulator |
| FileDialog precedent | `40k/scripts/SaveLoadDialog.gd:51-52, 1487-1547` | for any future import/export |
| Determinism check | `tools/ai_lab/determinism_check.py SEASON_A SEASON_B [--require all|trajectory|outcome]` | compares two pre-recorded record *seasons* (directories); it does NOT run games |
| Lab A/B | `tools/ai_lab/run_paired.py` (seed-paired, **side-swapped** — seat-2 consumption must work) | plus `run_ai_benchmark.sh` `BENCH_*` env contract |

Project gates for EVERY task (from `CLAUDE.md`): player-facing work needs a
windowed scenario under `tests/scenarios/sp/` proven passing AND a live
screenshot of the feature's effect (MCP bridge) in the task's end-of-task
TLDR; player-facing changes prepend an entry to
`40k/data/version_history.json`; never remove debug logs; never claim a
limitation you haven't reproduced; if blocked, record the failing command +
output in the Evidence block.

## Task protocol

- Tasks are ordered; each lists `Depends`. Do not start a task whose
  dependencies are not DONE in this file. (Exception: PM-8a has no
  dependencies and should run EARLY.)
- On completing a task: set Status to DONE, fill its **Evidence** block
  (commands run, key output, scenario ids, screenshot paths, commit SHAs),
  commit code + this file together, push to the designated branch.
- Keep to stated scope. Adjacent work → new task block at the bottom.
- Maintain `.llm/plan-maker-progress.md` (create on first task): one line per
  task — status, key result, timestamp.

## Dependency graph

```
PM-8a reset spike (NO dependencies — run early, in parallel with PM-0/PM-1)

PM-0 schema+validator
  └─ PM-1 PlanManager
       ├─ PM-2a AI deployment: order+placement+seat-mirror (+bench plan plumbing)
       │    └─ PM-2b AI formations: reserves+embark+attach
       ├─ PM-3 AI earmarks
       ├─ PM-4 sandbox editor session ─ PM-5 recorder (round-trip needs PM-2a)
       │                                 └─ PM-6 intent painter (needs PM-3)
       ├─ PM-7a assign plan in game setup (needs PM-2a)
       │    └─ PM-7b plan browser
       └─ PM-8b simulator backend (needs PM-2a + PM-8a)
            └─ PM-9 simulator UI (needs PM-7a)

PM-10 first real content + lab verdict (needs PM-2a, PM-2b, PM-3; PM-5 helpful)
PM-11 docs + release coherence (needs all)
```

---

## PM-8a — SPIKE: prove two back-to-back in-session AI games

**Status:** DONE
**Depends:** — (run early; results de-risk PM-8b)
**Player-facing:** no

**Goal.** Prove (or refute, with evidence) that this build can run two
consecutive from-menu AI-vs-AI games in one process with a clean state reset —
the load-bearing unknown of the whole simulator, because `AIBenchmarkRunner`
is one-game-per-process by design and no production code performs an
in-session multi-game reset.

**Context to load.** The Global-context rows on the benchmark harness, phase
flow, profile machinery, seeding triple, and from-menu bootstrap.
`MainMenu._initialize_game_with_config` (`MainMenu.gd:1499-1591`),
`Main.gd:695-715` (AI seat configuration), `AIPlayer.configure()`
(`AIPlayer.gd:256-302`), `StratagemManager.reset_for_new_game()`
(`StratagemManager.gd:4172-4182`) and `UnitAbilityManager.reset_for_new_game()`
(`UnitAbilityManager.gd:4626`) — note **neither has any production caller**
(grep it): once-per-battle stratagem/ability locks are a live leakage risk.

**Steps.** Script (headless is fine; the bench runs headless) a driver that:
launches game 1 via the from-menu config path (both seats AI, small Custodes
armies), seeds the triple, lets it run to completion or a low round cap;
returns to menu / re-invokes the bootstrap; launches game 2 the same way;
at each game start, asserts unit counts equal, stratagem usage history empty,
decision-record accumulators empty, `PhaseManager.game_ended` cleared
(`PhaseManager.gd:107-112`). Diff any leaked state you find and either reset
it in the driver or document it as PM-8b work.

**Validation gate.** A committed spike report
(`40k/tests/bench_baselines/<date>_pm8a_inline_reset_spike.md`) with: the
driver script path, both games' completion status, the state-diff at game-2
start, and a verdict: "in-session reset viable — reset list is X" or "not
viable because Y (reproduced output)". Subprocess-per-game is NOT the answer
to reach for: the only precedent (`tests/helpers/GameInstance.gd:104`) has
documented autoload-init flakiness (`tests/FINAL_STATUS.md`) and is
impossible on the web export.

**Evidence.**

VERIFIED: pure-state (no UI affordance) — PM-8a adds one headless spike driver
under `40k/tests/spikes/` and one committed report. No production code changed,
so nothing a player can see or click is different; the whole task IS a
measurement of autoload state.

**Verdict: in-session reset is VIABLE — and the task's candidate reset list is
necessary but NOT sufficient.** Report:
`40k/tests/bench_baselines/2026-08-11_pm8a_inline_reset_spike.md`.
Driver: `40k/tests/spikes/pm8a_inline_reset_spike.gd`.

```
$ godot --headless --path . -s tests/spikes/pm8a_inline_reset_spike.gd
game 1 (seed 8100): completed  round 5  205 actions  VP 35-66   11.4 s
game 2 (seed 8101): completed  round 5  264 actions  VP 55-37   14.0 s
game 3 (seed 8100): completed  round 5  205 actions  VP 35-66   10.4 s
determinism g1 vs g3: {"same_seed": true, "identical": true, "mismatches": {},
                       "first_action_divergence_index": -1}
stderr: 0 SCRIPT ERROR, 0 "Lambda capture was freed", 0 "update_control on Nil"
```

Three consecutive from-menu AI-vs-AI games completed in one process (~10-14 s
each for a 3-unit Custodes mirror at time_scale 10, running the FULL game from
FORMATIONS), no stalls, equal unit counts at every game start, and **two games
at the same seed produced byte-identical outcomes** while a third at a different
seed produced a genuinely different game.

**The load-bearing finding: with only the task's candidate resets
(StratagemManager / UnitAbilityManager / MissionManager+Secondary init /
PhaseManager.game_ended), two SAME-SEED in-session games diverged** — 205 vs 189
actions, VP 35-66 vs 42-66 — while the same seed in two *separate processes*
matched exactly (202 actions / 35-66 both runs). So the residual leakage was
real, and had to be closed before PM-8b could claim seeded runs.

The reset list that makes it deterministic (full table + per-step evidence in
the report):
1. `AIPlayer.configure({1:"HUMAN",2:"HUMAN"})` **before** tearing the game down
   — the AI is otherwise still live during the rebuild and Main'"'"'s later
   `configure()` erases the evidence by wiping `_action_log`. Fixing only this
   moved the first action-trace divergence from index 0 to index 23.
2. `StratagemManager.reset_for_new_game()` (proven: `_usage_history` 8/8 leaked).
3. `UnitAbilityManager.reset_for_new_game()` (no leak observed with this army —
   kept because the method has no production caller, so the risk is unproven
   rather than disproven).
4. `PhaseManager.reset()` **plus `_last_round_started = -1`**, which `reset()`
   misses.
5. **Re-initialise `FactionAbilityManager`'"'"'s per-game dictionaries — the actual
   determinism-breaker.** It has no reset entry point at all; `_active_mastery`
   / `_mastery_selected_round` carried into game 2, which then skipped
   `SELECT_MARTIAL_MASTERY` and diverged from there.
6. `MissionManager`: clear `_units_alive_at_round_start` and
   `objectives_visual_refs` (`initialize_mission()` clears neither).
7. `MissionManager`: disconnect the stale **lambda** receivers (below).
8. `ActionLogger` / `GameEventLog` / `ReplayManager`: no reset entry points,
   unbounded growth (257 actions, 570 entries at game 2'"'"'s bootstrap).
9. Seed a **fourth** RNG channel — the GLOBAL RNG (`seed(n)`), which
   `Array.shuffle()`/`randi()`/`randf()` draw from and which the documented
   "seeding triple" does not cover. A fresh process starts it from a fixed
   default (which is why separate processes agreed); in-session its state
   carries over.

**Ordering is part of the answer**: reset, THEN bootstrap. Resetting after the
bootstrap wipes what the bootstrap just populated —
`StratagemManager.reset_for_new_game()` clears the faction stratagems that
applying the armies had just loaded.

**Separate bug found (cosmetic, but it breaks the no-ERROR gate).**
`Main._setup_objectives()` (`scripts/Main.gd:5186-5191`) connects a lambda to the
`MissionManager.objective_control_changed` autoload signal that CAPTURES the
`ObjectiveVisual` scene node. The connection outlives the scene: receivers
accumulate 5 -> 10 -> 15 across three games, and every control change in game 2+
fires game 1'"'"'s dead lambdas — `Lambda capture at index 1 was freed` plus
`Nonexistent function '"'"'update_control'"'"' in base '"'"'Nil'"'"'` at Main.gd:5188. **105 such
ERROR lines in a 3-game run, zero in game 1.** Determinism holds with them
present, so they are cosmetic — but they would fail `verify_delivery` /
`read_debug_log`, which PM-9 has to pass. The guard that works is an
unconditional `Callable.is_custom()` sweep; `is_instance_valid(callable.get_object())`
does NOT work, because a lambda'"'"'s bound object outlives the scene while its
captures do not, so the connection still looks healthy.

Instruments built for this (reusable by PM-8b): a per-game capture of the first
60 `AIPlayer._action_log` entries with the **index of the first differing
action** between two runs, and `_autoload_fingerprint()` — the size/value of
every script-declared Array/Dictionary/bool/int on 17 autoloads, diffed between
identical bootstrap points. The fingerprint found the log/record leaks but NOT
the FactionAbilityManager one, because those are fixed-shape `{"1":…,"2":…}`
dictionaries whose size never changes; the action trace found it.

Also confirmed: a from-menu AI-vs-AI game works end to end (FORMATIONS confirm,
deployment roll-off, deployment) — a path `AIBenchmarkRunner` never exercises,
being fixture-only and post-deployment.

Commit: see `PM-8a: spike — in-session multi-game reset is viable`.

---

## PM-0 — Plan schema v1 + validator + example fixtures

**Status:** DONE
**Depends:** —
**Player-facing:** no

**Goal.** Define the `wh40k_ai_plan` JSON format v1, write a validator, and
commit two hand-written example plans as test fixtures.

**Context to load.** `40k/scripts/ProfileManager.gd` (imitate: all-static
RefCounted, `user://` bootstrap, `push_warning` + empty-dict error style,
`validate_profile` returning `{valid, errors}` at :111-137, format-tag check).
One deployment-zone and one terrain-layout JSON. `40k/armies/recon_stomps.json`
and `custodes_lions.json` — note the `U_*` unit keys and duplicate
`meta.name`s. The Canonical-names section above.

**Schema v1** (authoritative doc goes to `40k/docs/PLAN_FORMAT.md` with a full
annotated example using REAL recon_stomps ids):

```json
{
  "format": "wh40k_ai_plan",
  "version": 1,
  "name": "Recon Stomps — Hammer & Anvil",
  "description": "...",
  "author": "...",
  "keys": {
    "army_file": "recon_stomps",
    "detachment_hint": "Speedwaaagh!",
    "deployment_zone_id": "hammer_anvil",
    "terrain_layout_id": "disruption_vs_disruption_1",
    "mission_id": ""
  },
  "deployment": {
    "order": ["U_GRETCHIN_A", "U_STORMBOYZ_A", "U_STOMPA"],
    "placements": [
      { "unit": "U_STORMBOYZ_A",
        "unit_name": "Stormboyz",
        "role_fallback": "screen",
        "models_inches": [[10.5, 12.0], [11.5, 12.0]],
        "anchors": { "nearest_objective": "obj_home_1",
                      "depth_from_zone_edge_in": 4.0,
                      "nearest_terrain_piece": "area-large-2" } }
    ],
    "reserves": [ { "unit": "U_STORMBOYZ_B", "arrival_round": 2 } ],
    "embarkations": [ { "unit": "U_BOYZ_A", "transport": "U_STOMPA" } ],
    "attachments": [ { "character": "U_WARBOSS", "bodyguard": "U_BOYZ_A" } ]
  },
  "earmarks": [
    { "unit": "U_DEFFKILLA_A", "verb": "PUSH_CENTER" },
    { "unit": "U_GRETCHIN_A", "verb": "HOLD_OBJECTIVE", "target": "obj_home_1" }
  ],
  "profile_fragment": { "parameters": {}, "rules": [] }
}
```

Rules:
- **Verbs — exactly five**: `HOLD_OBJECTIVE` (requires `target` objective id),
  `PUSH_CENTER`, `SCREEN`, `RESERVE_UNTIL` (requires `round` 2-3),
  `HUNT_CHARACTERS`. `TRADE` is rejected with error "reserved for v2".
- `RESERVE_UNTIL` is UI sugar over `deployment.reserves` — **that list is the
  single source of truth**; validator ERRORS if an earmark and the reserves
  list contradict (same unit, different rounds / earmarked but not listed).
- `"unit"` = army-file unit id; `unit_name` optional (display/degradation);
  matching semantics for edited lists are PM-1's.
- `models_inches` in board inches, player-1 frame (locked decision 5).
  `anchors` recorded, never resolved in v1.
- `profile_fragment` reuses `wh40k_ai_profile` semantics verbatim — and
  inherits its documented traps (silent-zero multiply, unknown-condition-
  passes): see `tools/ai_lab/validate_profile.py:1-45`, the CI counterpart
  for any shipped plan's fragment.
- No `if_going_second` in v1 (cut — see Deferred; the two roll-offs' timing
  semantics were disputed under verification and the field invites false
  confidence).

**Deliverables.**
1. `40k/docs/PLAN_FORMAT.md` — format doc, annotated example, verb table,
   frame/transform rule, earmark-vs-intent terminology note.
2. `40k/scripts/PlanValidator.gd` (static, mirroring ProfileManager style):
   format/version checks; verb vocabulary (+TRADE reserved error);
   zone-id existence via `FileAccess.file_exists("res://deployment_zones/%s.json" % id)`
   or membership in `DeploymentZoneData.DEPLOYMENT_TYPES` (`get_zones()` is
   NOT an existence check — silent hammer_anvil fallback at :48-50);
   layout-id existence likewise; every placement has ≥1 model inside the
   **player-1** zone polygon (build `PackedVector2Array` from
   `DeploymentZoneData.get_zones(id)` in inches →
   `Geometry2D.is_point_in_polygon`; also validate the seat-2 transform
   `[44−x, 60−y]` lands inside the player-2 polygon); reserves-vs-earmark
   contradiction check; reserves within the 50% points + 50% unit caps
   (mirror `FormationsPhase.gd:400-420`, `GameState.get_reserves_points`);
   given an army dict, coverage: `{units_in_plan, units_in_army,
   unmatched: []}` — id match first, then unique-name match (warning), else
   `role_fallback` (warning). Duplicate-name armies are a REQUIRED test case.
3. Two fixture plans under **`40k/tests/fixtures/ai_plans/`** (NOT under
   `data/` — the runtime search path must not list fixtures in the player
   browser): one minimal-valid, one rich (all five verbs, reserves,
   embarkations, attachments). `"author": "fixture"`.
4. Headless test `40k/tests/unit/test_plan_validator.gd` — standalone
   `extends SceneTree` per the Global-context convention, registered in
   `run_pretrigger_tests.sh`. Cases: valid passes; each corruption class
   fails with its expected error (bad verb, TRADE, missing HOLD target,
   unknown zone id, placement outside P1 zone, transformed placement outside
   P2 zone, reserves contradiction, cap exceeded, unit not in army →
   warning).

**Validation gate.** `godot --headless --import` clean; the unit test green
via `godot --headless --path . -s tests/unit/test_plan_validator.gd`; output
pasted into Evidence.

**Out of scope.** Runtime loading (PM-1), AI behavior (PM-2x/3), anchor
resolution.

**Evidence.**

VERIFIED: pure-state (no UI affordance) — PM-0 ships only a format doc, a
static `RefCounted` validator with no scene, node, signal or input surface, two
JSON test fixtures, and a headless test. Nothing in this task is reachable from
the running UI: no menu entry, button, panel or overlay is added or changed, and
`PlanValidator` has no runtime caller yet (its first callers arrive in PM-1 and
PM-2a, both of which carry their own windowed gates). A windowed scenario here
could only screenshot an unchanged main menu, which CLAUDE.md explicitly calls a
marker rather than evidence.

Delivered:
- `40k/docs/PLAN_FORMAT.md` — annotated example on real recon_stomps ids, verb
  table, frame/transform rule, matching + fallback semantics, fragment merge
  order, earmark-vs-intent note.
- `40k/scripts/PlanValidator.gd` — static, ProfileManager-style.
- `40k/tests/fixtures/ai_plans/fixture_minimal_valid.json` and
  `fixture_recon_stomps_rich.json` (13 placements / 54 models / all five verbs /
  reserves / embarkation / attachment, `"author": "fixture"`).
- `40k/tests/unit/test_plan_validator.gd`, registered in the `TESTS` array of
  `40k/tests/run_pretrigger_tests.sh`.

Commands + output:
```
$ godot --headless --import          # clean, rc=0, no errors/warnings
$ godot --headless --path . -s tests/unit/test_plan_validator.gd
=== PlanValidator (PM-0) Tests ===
... 65 PASS lines ...
=== Results: 65 passed, 0 failed ===
```
(No `SCRIPT ERROR` lines. The only stderr at exit is the engine's standard
`RID allocations ... leaked at exit` / `resources still in use at exit` noise
that every headless run in this repo emits, including a bare
`godot --headless --import`.)

Two findings that changed the implementation from the task text:

1. **`DeploymentZoneData` cannot be preloaded from a `-s` SceneTree test.** It
   calls the `Measurement` autoload, whose identifier does not resolve in that
   compile context; preloading it yields
   `SCRIPT ERROR: Compile Error: Identifier not found: Measurement` and the
   preloaded script's static funcs then fail with
   `Invalid call. Nonexistent function 'get_zones' in base 'GDScript'`
   (reproduced, then fixed). PlanValidator therefore reads
   `res://deployment_zones/<id>.json` directly — the same JSON
   `DeploymentZoneData.get_zones()` itself prefers (`:29-34`) — and stays
   autoload-free. `test_deployment_types_all_have_zone_json` asserts every
   `DEPLOYMENT_TYPES` entry really has such a file (all 6 do), reading the const
   out of the source text so no ERROR line is emitted. **Consumers of the zone
   polygons in later PM tasks that run in-game (PM-2a) can use
   `DeploymentZoneData` normally; only `-s` test context is affected.**

2. **The "transformed placement outside P2 zone" corruption case is reachable
   with real shipped data.** All 6 selectable zones are exact point reflections
   (asserted for every vertex by `test_shipped_zones_are_point_symmetric`), so
   the P2 check can never fire for them. But
   `res://deployment_zones/crucible_of_battle_new.json` — a file on disk that is
   NOT in `DEPLOYMENT_TYPES` — is asymmetric (P1 is the triangle
   (0,0)-(44,0)-(0,30); P2 starts at y=33, not y=30). A placement at
   `[4.0, 26.0]` is inside its P1 zone and mirrors to `(40, 34)`, outside its P2
   zone, so the test exercises the real error path with real data rather than a
   fabricated polygon.

Also verified while building: reserves caps mirror `FormationsPhase.gd:400-420`
exactly — the unit-count cap counts reserves *entries* (`:814-816`) while the
points cap includes characters attached to a reserved bodyguard (`:802-812`);
both are asserted.

Commit: see `PM-0: wh40k_ai_plan v1 schema, validator, fixtures, tests`.

---

## PM-1 — PlanManager: storage, listing, matching

**Status:** DONE
**Depends:** PM-0
**Player-facing:** no

**Goal.** A `PlanManager` static utility that lists/loads/saves/deletes plans
and answers: *which plan, if any, applies to this game for player N?*

**Context to load.** `ProfileManager.gd` (structure to imitate); PM-0
validator + fixtures; the Global-context "Game identity for matching" row.

**Deliverables.**
1. `40k/scripts/PlanManager.gd`:
   - Search path: `user://ai_plans/` then `res://data/ai_plans/` (shipped;
     the dir may not exist yet — handle gracefully). NON-recursive listing.
     Test fixtures are loaded by explicit path, never listed.
   - `save_plan(dict)` → validate via PlanValidator, refuse invalid, write to
     `user://ai_plans/<slug>.json` (slug: lowercase, non-alphanumeric → `_`).
   - `find_plan_for(player, snapshot)`: resolve identity from, in order,
     `meta.game_config.player{N}_army` (menu games), else fallback-match
     `keys.army_file`/`keys.detachment_hint` against
     `state.factions[player]` name/detachment (fixtures have an EMPTY
     `game_config` — verified on `mirror_orks_2000_predeploy`); zone from
     `meta.deployment_type`; layout from `board.terrain_layout`. Matching
     rank: exact (army+zone+layout) → (army+zone, layout wildcard) → `{}`.
     Missing keys → `{}`; deterministic alphabetical tie-break; log the
     choice and the reason via the debug-log path.
   - Matching is seat-agnostic (the seat-2 coordinate transform is
     consumption's job, PM-2a).
   - `set_player_plan`/`clear_player_plan` live in `AIDecisionMaker`
     (PM-2a) mirroring `load_player_profile`/`clear_player_profile`
     (:324-341); PlanManager is pure storage/matching.
2. Headless test `40k/tests/unit/test_plan_manager.gd` (SceneTree
   convention, registered): fixtures load by path; exact beats wildcard;
   mismatched army → `{}`; fixture-style snapshot with empty `game_config`
   matches via faction fallback; save→load round-trip; invalid save refused;
   fabricated `meta.game_config` snapshot matches.

**Validation gate.** Unit test green; `--headless --import` clean; matching
decisions for two fabricated snapshots pasted into Evidence.

**Out of scope.** UI, AI consumption, recursive listing.

**Evidence.**

VERIFIED: pure-state (no UI affordance) — `PlanManager` is a static
`RefCounted` storage/matching utility with no scene, node, signal or input
surface, and no runtime caller yet (its first UI caller is PM-7a's dropdown,
its first AI caller is PM-2a; both carry their own windowed gates). Nothing a
player can see or click changed in this task.

Delivered:
- `40k/scripts/PlanManager.gd` — search path `user://ai_plans/` then
  `res://data/ai_plans/` (non-recursive, missing dir tolerated), `slugify`,
  `list_plans` (browser rows incl. the PlanValidator badge), `load_plan_file`
  (explicit path — how fixtures are loaded), `load_plan`/`find_plan_path`,
  `save_plan` (validates, refuses invalid), `delete_plan` (user:// only),
  `resolve_game_identity`, `rank_plan`, `find_plan_match_for`, `find_plan_for`.
- `40k/tests/unit/test_plan_manager.gd`, registered in
  `40k/tests/run_pretrigger_tests.sh`.
- `PLAN_FORMAT.md` gained a "`_P<player>` mirror suffix" subsection.

Commands + output:
```
$ godot --headless --path . -s tests/unit/test_plan_manager.gd
=== PlanManager (PM-1) Tests ===
... 55 PASS lines ...
=== Results: 55 passed, 0 failed ===
```

Matching decisions for two fabricated snapshots, quoted from the run:
```
game_config path:
  reason: army_file == game_config army 'recon_stomps',
          zone 'crucible_of_battle', layout 'take_and_hold_mirror_1'  (rank 0, exact)
faction-fallback path (NO game_config, fixture-style):
  reason: faction fallback: 'Orks'/'Speedwaaagh!',
          zone 'crucible_of_battle', layout 'take_and_hold_mirror_1'  (rank 0, exact)
```

Four findings that shaped the implementation:

1. **The predeploy fixtures have no `game_config` key at all** — not an empty
   dict, absent. Confirmed by decompressing all three
   (`tests/saves/*_predeploy.w40ksave` are base64-of-gzip JSON) and again
   in-engine: `test_real_predeploy_fixture_has_no_game_config` deserialises
   `mirror_orks_2000_predeploy` through `StateSerializer` and asserts
   `identity_source == "factions"`, `deployment_type == crucible_of_battle`,
   `terrain_layout == take_and_hold_mirror_1`, faction `Orks`/`Speedwaaagh!`.
   The fabricated snapshots in the test are checked against that real state, so
   they cannot drift into fiction.
2. **`state.factions` is keyed by the STRING player number** (`"1"`, `"2"` —
   `GameState.gd:162/211`), and holds the army file's whole `faction` dict
   including `detachment` (`ArmyListManager.gd:356-360`). Faction fallback
   therefore compares the *plan's army file's* faction to the live one, and
   requires the detachment to agree when both are known.
3. **The `_P<player>` mirror re-key is load-bearing, and owner-blind lookup gets
   it wrong.** When both seats pick the same list, player 2's units are
   `U_X_P2` (`ArmyListManager.gd:333-346`) — but `U_X` still exists, owned by
   player 1. A first cut of `resolve_unit_id` checked the plain id first and
   silently handed seat 2 the *opponent's* unit; the test caught it. It now
   tries the suffixed form first and verifies ownership. `units_for_player`
   strips the suffix so a plan lines up at either seat. PM-2a depends on this.
4. **Autoloads are not in the tree while a `-s` script's `_init()` runs.** This
   is the same root cause as PM-0's `Identifier not found: Measurement`, now
   pinned: the SceneTree script's `_init()` executes *before* autoload
   `_ready()`. Tests that need an autoload must defer, per the existing
   convention in `tests/test_new_game_reaches_rolloff.gd`
   (`create_timer(0.2).timeout.connect(_run)`), which this test does.

The test is hermetic: pre-existing `user://ai_plans/*.json` are moved to a
backup dir for the duration and restored afterwards, so matching assertions are
not perturbed by (and do not destroy) a developer's own plans.

Commit: see `PM-1: PlanManager — plan storage, listing and game matching`.

---

## PM-2a — AI consumes deployment: order, placement, seat mirror, bench plumbing

**Status:** DONE
**Depends:** PM-1
**Player-facing:** yes (AI behavior) — version_history entry required

**Goal.** When a plan matches (or is set), `_decide_deployment` follows it:
plan order, plan positions (seat-transformed when needed), per-unit fallback
to the formula. Plus the bench plumbing that makes plans measurable at all.

**Context to load.** `_decide_deployment` end to end (3912-4130): action dict
shape (4123-4129), `deploy_actions[0]` pick (3923-3924), column formula
(4001-4004), AAO spacing (4040-4042), `_record_choice` (4081-4083).
`DeploymentPhase.gd` legality (90-195, 290-329) and available-actions
enumeration (1377-1394 — one `DEPLOY_UNIT` per undeployed unit of the current
player). `TurnManager.gd:112-175, 238-250` (alternation). Repair helpers:
`_resolve_formation_collisions` (`AIDecisionMaker.gd:19656-19712` — accepts an
arbitrary positions array BUT clamps to a rect `zone_bounds`, so add a polygon
containment check for diagonal zones), `_find_wall_free_center` (4112-4117),
`_get_deployment_zone_polygon_pixels` + `Geometry2D.is_point_in_polygon`,
`_position_collides_with_deployed`, `Measurement.model_overlaps_any_wall`.
`AIPlayer._handle_failed_deployment` (`AIPlayer.gd:3469-3576`) — plan-unaware
random resampler; last resort only. The Canonical-names section.

**Implementation requirements.**
1. `AIDecisionMaker.set_player_plan(player, plan)` / `clear_player_plan`,
   mirroring the profile pattern. `AIPlayer.configure()` clears profiles per
   game (`AIPlayer.gd:323-325`) — decide and DOCUMENT whether plans clear
   with them (recommended: yes, cleared in `clear_all_profiles`-adjacent
   code; callers re-apply after configure — the simulator and Main.gd both
   will). Gate all behavior on `PLANS_ENABLED` (canonical param). Auto-match
   via `PlanManager.find_plan_for` when no explicit plan set.
2. **Order**: on each of the AI's own alternating deployment turns, select
   the `DEPLOY_UNIT` action from `available_actions` matching the earliest
   not-yet-deployed plan-order unit — instead of `deploy_actions[0]`. The
   interleave with the opponent, defender-first, and TITANIC skips are
   phase-controlled and untouched. Units missing from the plan deploy after
   planned units via the formula.
3. **Placement**: `models_inches` → px via `PIXELS_PER_INCH`; **if the AI's
   assigned zone is the player-2 polygon of `deployment_zone_id`, first
   apply `[x,y] → [44−x, 60−y]` in inches** (locked decision 5). Pre-validate
   in-decision (zone polygon, collisions, walls); repair via
   `_resolve_formation_collisions` plus a polygon containment guard; if
   repair fails → formula fallback for that unit. Every path ends in a valid
   action or a legal skip — never a stall.
4. **Instrumentation**: plan-driven placements emit `_record_choice` context
   `"source": "plan:<name>"`; fallbacks `"source": "formula_fallback"`.
   Adherence must be countable per game per seat.
5. **State discipline**: any new mutable static (plan cursor, per-unit
   consumed flags) is registered in `_snapshot_planning_state` /
   `_restore_planning_state` (2416-2455) — the human-hint preview calls a
   full decide() and must not corrupt live plan state. No unseeded RNG.
6. **Bench plumbing** (needed by this task's own gate): add
   `BENCH_P1_PLAN`/`BENCH_P2_PLAN` env + `--bench-p1-plan/--bench-p2-plan`
   flags to `AIBenchmarkRunner` + `run_ai_benchmark.sh`, mirroring the
   profile flags (`AIBenchmarkRunner.gd:107-110`): load the plan file, call
   `set_player_plan` after the per-game `configure()` (:322), stamp the plan
   name into the result JSON and record provenance.

**Validation gate.**
1. Headless `tests/unit/test_ai_plan_deployment.gd` (SceneTree convention):
   snapshot from a predeploy fixture + PM-0 fixture plan (matched via
   explicit `set_player_plan` — fixture `game_config` is empty) → order
   followed; positions within 0.5" of plan; uncovered unit fell back;
   **seat-2 case: same plan consumed as player 2 deploys legally inside the
   P2 zone** (transform verified).
2. Determinism: two identical runs
   `BENCH_P1_PLAN=<fixture plan> BENCH_P2_PLAN=<fixture plan> BENCH_SEED_BASE=5001 bash 40k/tests/run_ai_benchmark.sh 2 mirror_custodes_2000_predeploy`
   into two `BENCH_DATA_DIR`s → `python3 tools/ai_lab/determinism_check.py
   <dirA> <dirB>` PASS at `all`. (determinism_check compares two record
   seasons; it does not run games.)
3. Windowed scenario `sp/pm2a_ai_deploys_from_plan.json`: load a predeploy
   fixture, `execute_script` to set the plan for the AI player, let the AI
   deploy, assert ≥1 named unit at its planned position and `plan:`
   deployment records present; `verify_delivery` no-ERROR.
4. Screenshot of the deployed formation (visibly non-columnar) for the TLDR.

**Out of scope.** Reserves/embark/attach (PM-2b), earmarks (PM-3), UI.

**Evidence.**

Delivered (all in `40k/scripts/AIDecisionMaker.gd` unless noted):
- `set_player_plan` / `clear_player_plan` / `clear_all_plans` / `get_player_plan`
  / `plans_enabled`, mirroring `load_player_profile`. **Decision + doc:
  `clear_all_profiles()` now also clears plans**, so `AIPlayer.configure()`
  (`AIPlayer.gd:325`) resets them once per game and callers apply a plan AFTER
  configure, exactly like `Main.gd` does for `playerN_ai_profile`
  (`Main.gd:707-715`). Documented in the function docstring and in
  `PLAN_FORMAT.md`.
- `_resolve_plan_for` — explicit plan first, else ONE `PlanManager.find_plan_for`
  attempt per player per game. Gated on `plans_enabled()`.
- `_decide_deployment`: plan order replaces `deploy_actions[0]`; plan placement
  replaces the column formula; both degrade per-unit.
- `_plan_positions_px` (inches -> px + the seat-2 `[44-x, 60-y]` mirror),
  `_plan_positions_legal`, `_plan_shape_inside_polygon`, `_plan_shapes_overlap`,
  `_plan_deployment_action`.
- Instrumentation: deployment decision records carry
  `source: "plan:<name>" | "formula_fallback" | "formula"`, plus
  `seat_mirrored` and `repaired`.
- Snapshot contract: `_player_plans`, `_plan_auto_match_attempted` and
  `_plan_logged_once` are registered in BOTH `_snapshot_planning_state` and
  `_restore_planning_state`, and a test proves a preview cannot leak a plan.
- `PLANS_ENABLED: 1` added to the `parameters` object of `40k/data/ai_config.json`
  (with a `_readme` note).
- Bench plumbing: `--bench-p1-plan` / `--bench-p2-plan` +
  `BENCH_P1_PLAN` / `BENCH_P2_PLAN` in `AIBenchmarkRunner.gd` and
  `run_ai_benchmark.sh`; plan name/path/sha256 stamped into the result JSON and
  the record provenance. **An unloadable or invalid plan is FATAL**, matching the
  profile precedent — a silently-formula arm looks exactly like a null effect.
- New fixture `tests/fixtures/ai_plans/fixture_custodes_lions_crucible.json`
  keyed to the predeploy save's real identity, so the bench measures a plan
  actually being followed rather than 100% fallback.
- Docs: `PLAN_FORMAT.md` gained "How the AI consumes a plan (deployment)",
  adherence-measurement and benchmarking sections.
  `40k/data/version_history.json` 1.29.0 prepended.

**Gate 1 — headless.** `tests/unit/test_ai_plan_deployment.gd` (registered in
`run_pretrigger_tests.sh`):
```
$ godot --headless --path . -s tests/unit/test_ai_plan_deployment.gd
=== Results: 34 passed, 0 failed ===
```
covering: the phase's own first action is provably NOT the plan's first unit;
all 13 ordered units deploy in plan order; all 13 land within 0.5" of the
authored positions; an uncovered unit (the embarked Gretchin) falls back with
`source: formula_fallback`; seat 2 mirrors to within 0.000" and lands inside the
player-2 zone while the UNmirrored positions land 0/11 inside it;
`PLANS_ENABLED=0` reproduces `deploy_actions[0]` and records `source: formula`;
the snapshot contract holds; and the whole path runs on the REAL
`mirror_orks_2000_predeploy` save at both seats — a crucible_of_battle TRIANGLE
with `_P2`-re-keyed player-2 units — with 0 models outside either zone.

**Gate 2 — determinism.** Two independent seasons, same seeds, plans on BOTH
seats, via the new bench plumbing:
```
$ BENCH_P1_PLAN=40k/tests/fixtures/ai_plans/fixture_custodes_lions_crucible.json \
  BENCH_P2_PLAN=40k/tests/fixtures/ai_plans/fixture_custodes_lions_crucible.json \
  BENCH_SEED_BASE=5001 BENCH_DATA_DIR=/tmp/pm2a_seasonA \
  bash 40k/tests/run_ai_benchmark.sh 2 mirror_custodes_2000_predeploy      # and again -> seasonB
$ python3 tools/ai_lab/determinism_check.py /tmp/pm2a_seasonA /tmp/pm2a_seasonB
  seed     outcome   trajectory  decisions   actions A/B
  5002     match     match       match       744/744
  5003     match     match       match       758/758
PASS — 2 seed(s) reproduce EXACTLY: 1502 action lines and 408 decision
       records identical across independent runs.
```
Both games completed to battle round 5 with the plan loaded and stamped into
the result JSON (`p1_plan_name` / `p2_plan_name`), i.e. the plan path really was
exercised rather than silently falling back.

**Gate 3 — windowed scenario.** `tests/scenarios/sp/pm2a_ai_deploys_from_plan.json`:
```
$ bash 40k/tests/run_scenario.sh tests/scenarios/sp/pm2a_ai_deploys_from_plan.json
[ScenarioRunner] === pm2a_ai_deploys_from_plan: 41 passed, 0 failed ===
SCENARIO pm2a adherence 22/22 units within 0.5in, worst 0.000in
SCENARIO pm2a plan deployment records: seat1=11 seat2=11
SCENARIO pm2a seat-mirrored deployments: 11
SCENARIO pm2a seat-2 models inside own zone: 42/42
```
Live log lines from that run:
```
AIDecisionMaker: [plan] Player 1 deploying U_BLADE_CHAMPION_A from plan 'Fixture — Custodes Lions on Crucible'
AIDecisionMaker: [plan] Player 2 deploying U_BLADE_CHAMPION_A_P2 from plan 'Fixture — Custodes Lions on Crucible' (seat-2 mirrored)
```

**Gate 4 — live MCP evidence (both arms, same fixture, one process).**
Driver: `mcp_client.py` + `pm2a_capture.py` in the session scratchpad, driving
the running windowed game over the bridge on 127.0.0.1:9080.
```
arm plan_active     : deployment sources  plan p1=5 p2=6 | formula p1=0 p2=0
arm plans_disabled  : deployment sources  plan p1=0 p2=0 | formula p1=5 p2=6
verify_delivery     : verdict PASS, log_summary {error: 0, warning: 0}
```
(The per-seat counts are lower than the scenario's 11/11 only because this
driver does not raise `_max_decision_record_batches`, so the 500-batch ring
drops the earliest batches. The ratio is the point: 100% plan vs 0%.)

Screenshots (committed under `40k/docs/evidence/`):
- `pm2a_plan_active_deployment.png` — both armies in the plan's compact blocks,
  P1 top and P2 mirrored at the bottom; the game log narrates
  "P1: Deployed Prosecutors from plan 'Fixture — Custodes Lions on Crucible'"
  and the same for P2.
- `pm2a_plans_disabled_formula_deployment.png` — the SAME fixture with
  `PLANS_ENABLED = 0`: loose formula columns hugging the board edges.

**That control arm produced an unplanned finding worth acting on.** With plans
off, on the triangular `crucible_of_battle` zone the column formula repeatedly
emits placements the phase rejects — the log fills with
`"P2: Custodian Guard deployment failed (Model must be wholly within deployment
zone …) — retrying"`, `(retry 1)`, `(retry 2)` — and one unit
(Custodian Guard Zeta, 225 pts / 5 models) ends up dumped into **Strategic
Reserves** because it could not be placed at all. The plan path placed every
unit first time. This is measured behaviour of the PRE-EXISTING formula on a
diagonal zone, not a regression introduced here; it is logged as a follow-up at
the bottom of this file.

A caveat recorded honestly: in that same live driver a few placements logged
`(repaired)` where the headless test and the windowed scenario both had every
unit land verbatim. The driver reloads the fixture twice in one process without
the PM-8a reset list, which is exactly the residual in-session leakage PM-8a
measured; the clean-start runs (34/34 headless, 22/22 at 0.000" windowed) are
the ones to read for placement fidelity.

Four findings worth carrying forward:

1. **Plan pre-validation had to be made shape-accurate, not conservative.** The
   first cut approximated "wholly within the zone" with a bounding circle
   (`_model_bounding_radius_px`, which for an oval is half the DIAGONAL — 1.69"
   for a 42x75mm Warbiker vs 1.48" for its widest axis). That over-strictness
   silently degraded 8 of 13 legal placements to repaired ones. It now calls the
   very helpers `DeploymentPhase` calls (`Measurement.shape_wholly_in_polygon`,
   `create_base_shape().overlaps_with`), so a plan placement is rejected exactly
   when the phase would reject it: 13/13 now land verbatim.
2. **Coherency was a missing check, and it is not optional.** `DeploymentPhase`
   enforces 11e 03.03 (2" neighbour + 9" envelope) on the ACTION
   (`DeploymentPhase.gd:197-232`). Without the same check in the pre-validation,
   a plan that laid a unit out in a long line would emit an action the phase
   rejects — and a rejected deployment action is what stalls an AI deployment.
   `_plan_positions_legal` now calls `AttackSequence.check_unit_coherency`, and
   the fixtures are authored as compact per-unit blocks.
3. **Scenario `execute_script` resolves global class names only in MULTILINE
   mode.** A single-line `AIDecisionMaker.get_player_plan(1)` fails with
   "Invalid named index 'AIDecisionMaker' for base type Object" (the
   `Expression.parse` path); the same code as a multiline step works. Also
   `GameState.set_meta`/`get_meta` is Godot's Object metadata, NOT `state.meta` —
   reading it back via `GameState.state["meta"][key]` throws.
4. **Unit ids are not stable across a game.** The Lions detachment splits Allarus
   Custodians into `U_ALLARUS_CUSTODIANS_A_lion_1..4` mid-game, so a live unit
   count that is 22 at deployment becomes 26 later. Anything keyed on "the set of
   units" must not assume it is fixed.

---

## PM-2b — AI consumes formations: reserves, embarkations, attachments

**Status:** DONE
**Depends:** PM-2a
**Player-facing:** yes — version_history entry required

**Goal.** The plan's `reserves`, `embarkations`, and `attachments` sections
drive the AI's FORMATIONS-phase declarations (menu-started games), with the
deployment-phase `PLACE_IN_RESERVES` safety net (`DeploymentPhase.gd:419-479`,
excluded from available actions at 1390-1394) as the fixture-era fallback.

**Context to load.** `_decide_formations` (`AIDecisionMaker.gd:3202`, reserves
branch 3243-3248), `_evaluate_reserves_declarations` (3632),
`FormationsPhase.gd` (actions 105-112, caps 400-420, confirm 699-714).
Reserves coefficients: `RESERVES_SR_*` (`AIDecisionMaker.gd:635-643`) and the
`RESERVES_DS_*` table in `docs/AI_TUNING.md`. Predeploy fixtures start at
DEPLOYMENT with `meta.formations_declared` already set — the normal
declaration path is only reachable in menu-started (or formations-phase-
fixture) games.

**Implementation requirements.** In `_decide_formations`, when a plan is
active: declare exactly the plan's reserves (respecting the 50% caps — if the
plan exceeds them, trim deterministically in plan order and log), embark the
plan's embarkations, attach the plan's attachments; anything unspecified
falls through to existing logic; every plan-driven declaration emits a
decision record with `"source": "plan:<name>"`. For games already past
formations (fixtures), reserves may be honored via `PLACE_IN_RESERVES` during
deployment; embark/attach cannot be retrofitted post-formations — log and
skip. `RESERVE_UNTIL` earmark ↔ reserves-list consistency is already
validator-enforced (PM-0); in-game arrival round is consumed where the
reserves pathway asks (`_decide_reserves_arrival`, `AIDecisionMaker.gd:6604`).

**Validation gate.** Headless unit test on a fabricated formations-phase
state (plan declares 1 reserve + 1 embark + 1 attach → actions emitted match;
over-cap plan → trimmed + logged). Windowed scenario
`sp/pm2b_formations_from_plan.json`: menu-started AI game (scenario starts on
main menu — precedent `sp/main_menu_defaults.json` — configure a small AI
game via clicks/execute_script) with a plan set; assert the declared
reserves/embark state after FORMATIONS matches the plan; `verify_delivery`
clean; screenshot of the formations summary/board state.

**Out of scope.** Disembark timing intents, transport routing.

**Evidence.**

Delivered in `40k/scripts/AIDecisionMaker.gd`:
- `_decide_formations` runs a plan pass FIRST, emitting the plan's declarations
  in the phase's own order (attach -> embark -> reserve) and stopping once they
  are made, so anything unspecified still falls to existing logic.
- `_plan_owns_reserves` suppresses the formula's reserves evaluation while a
  plan is active — including for an EMPTY `reserves` list, which is a positive
  statement ("start everything on the table") rather than an absence.
- `_plan_reserve_units` trims an over-cap plan in PLAN ORDER and logs the trim,
  mirroring `FormationsPhase.gd:400-420` (unit cap counts entries; points cap
  includes a character attached to a reserved bodyguard, `:802-812`).
- `_plan_deployment_reserve_action` + `plan_post_formations_reserves` retrofit
  reserves through `PLACE_IN_RESERVES` for games already past FORMATIONS;
  embarkations/attachments cannot be retrofitted and log once, then skip.
- Every plan-driven declaration emits a `formations` decision record with
  `source: "plan:<name>"` and a `declaration` of attachment/embarkation/reserves.

```
$ godot --headless --path . -s tests/unit/test_ai_plan_formations.gd
=== Results: 27 passed, 0 failed ===

$ bash 40k/tests/run_scenario.sh tests/scenarios/sp/pm2b_formations_from_plan.json
[ScenarioRunner] === pm2b_formations_from_plan: 36 passed, 0 failed ===
SCENARIO pm2b P1 reserves=["U_STORMBOYZ_B", "U_DEFFKOPTAS_A"]
              embark={"U_STOMPA_A":["U_GRETCHIN_B"]}
              attach={"U_DEFFKILLA_WARTRIKE_A":"U_WARBIKERS_C",
                      "U_DEFFKILLA_WARTRIKE_B":"U_WARBIKERS_D"} missing=[]
SCENARIO pm2b P2 reserves=["U_STORMBOYZ_B_P2", "U_DEFFKOPTAS_A_P2"]
              embark={"U_STOMPA_A_P2":["U_GRETCHIN_B_P2"]}
              attach={"U_DEFFKILLA_WARTRIKE_A_P2":"U_WARBIKERS_C_P2",
                      "U_DEFFKILLA_WARTRIKE_B_P2":"U_WARBIKERS_D_P2"} missing=[]
SCENARIO pm2b plan formations records: seat1=4 seat2=4
```
The second attachment on each seat is the AI's own — the plan names one pairing,
so the rest still falls through, which is the designed behaviour.

Screenshot: `40k/docs/evidence/pm2b_formations_from_plan.png` — the HUD reserves
readout shows **"RESERVES You 2·205 P2 2·205 R2+"**, i.e. exactly the plan's two
reserved units and 205 points (Stormboyz 65 + Deffkoptas 140) on BOTH seats.

The scenario had to start from the main menu, because every shipped predeploy
fixture begins at DEPLOYMENT with formations already confirmed. It bootstraps a
menu-style game the way `MainMenu._initialize_game_with_config` does, then hands
both seats the plan.

Three findings:

1. **The fixture plan asked for an attachment the game cannot make.** It paired
   Wazdakka Gutsmek with Warbikers; `data/40kdc/leaderAttachments.json` has NO
   leader row for Wazdakka at all, and the only leader eligible for `warbikers`
   is `deffkilla-wartrike`. The AI therefore never matched an action and fell
   through to its own pairing — correct degradation, but it means **an authored
   plan can silently ask for an impossible attachment**. The fixture now pairs
   the Deffkilla Wartrike; validator-side legality is logged as PM-F2 below.
2. **The AI must be stood down until the plan is installed.** `Main` configures
   the AI seats from `meta.game_config` as the scene loads, and
   `AIPlayer.configure()` clears plans — so the AI began declaring formations
   with no plan, and the first run of this scenario produced a player 1 with
   formula-flavoured extras (two extra reserves, an extra passenger) next to a
   player 2 that followed the plan exactly. The scenario now boots with both
   seats HUMAN and flips them to AI after installing the plan. **PM-7a must do
   the same thing in production: set the plan after `configure()`, before the
   AI's first evaluation.**
3. **A transport's `DECLARE_TRANSPORT_EMBARKATION` stays on offer** while it has
   any eligible unit left, so "the action exists" does not mean the plan's
   embarkation is still outstanding — the first cut re-issued it forever and the
   phase never advanced. `meta.formations` cannot be used to tell, because it is
   only written at CONFIRM time (`FormationsPhase.gd:1062-1079`); the phase's
   own `DECLARE_RESERVES` action list is the reliable "still undeclared" set
   (`:1217-1223`).

Commit: see `PM-2b: the AI declares a plan's reserves, embarkations and attachments`.

---

## PM-3 — AI consumes earmarks + profile fragment

**Status:** TODO
**Depends:** PM-1 (recommended after PM-2a)
**Player-facing:** yes — version_history entry required

**Goal.** The five verbs bias the AI's existing machinery for the whole game,
with graceful decay: earmarks are priors, not orders.

**Context to load.** `_assign_units_to_objectives` (7950; scoring terms
8076-8139 via `_t_add` + `get_param` — an added term joins cleanly and lands
in `score_breakdown`). Screening = pass 3 over units left unassigned
(8646, 8684-8706; names `screen_protect`/`screen_denial`/`corridor_block`).
Per-attacker scorers (Global-context row). Profile layering + snapshot
contract rows. `_get_base_param_value` iterates ALL players' profiles
(432-442) — pre-existing cross-seat quirk; note it when both seats carry
fragments.

**Verb semantics (exactly this, one mechanism each):**
- `HOLD_OBJECTIVE(target)`: additive `_t_add` bonus for that (unit,
  objective) pair, `get_param("PLAN_EARMARK_HOLD_BONUS", …)`.
- `PUSH_CENTER`: same-shaped bonus toward mid objective(s)
  (`MissionManager.get_objective_ids_by_designation` / nearest-to-center).
- `SCREEN`: **withhold the unit from the objective passes** (heavy candidate
  penalty or exclusion) so it falls through to the existing pass-3 screening
  logic. There is no "offer first" entry point — pass 3 only sees leftovers.
- `RESERVE_UNTIL(round)`: consumed at formations/deployment (PM-2b); in-game
  via `_decide_reserves_arrival` (6604).
- `HUNT_CHARACTERS`: additive term in `_score_shooting_target` (20194 — note
  the existing CHARACTER bonus there is multiplicative ×1.2 at 20367-70, so
  ADD a term alongside, don't swap a constant), `_score_charge_target`
  (14595, near `CHARGE_CHARACTER_BONUS`), `_score_fight_target` (16232-34).
  One param `PLAN_EARMARK_HUNT_BONUS`.
- Decay: earmark ignored for a unit below `PLAN_EARMARK_RELEASE_AT` (0.5) of
  starting models/wounds; release logged once. Release tracking is mutable
  static → register in `_snapshot_planning_state`/`_restore_planning_state`.
- `profile_fragment` applied through the existing `load_player_profile`
  layering at game start; explicit per-player profile wins over the
  fragment; document the merge order in PLAN_FORMAT.md.
- Every earmark application emits decision-record context
  (`"earmark": "HOLD_OBJECTIVE:obj_home_1"`).

**Validation gate.**
1. Headless unit test: fabricated snapshot + plan → earmarked unit assigned
   to its objective; **differential assert**: the same state with plans
   disabled assigns that unit elsewhere (pick the fixture unit so the
   formula's choice provably differs — otherwise the gate is satisfiable by
   formula behavior); 40%-strength unit → earmark released (logged).
2. Determinism as PM-2a gate 2 (plan with earmarks active).
3. Windowed scenario `sp/pm3_earmarks_bias_assignment.json`: fixture +
   earmarked plan; drive one AI movement phase; assert decision records
   carry the earmark context AND the earmarked unit's assignment differs
   from a plans-disabled control (assert via records, not just position);
   `verify_delivery` clean.
4. Screenshot: AI turn with the earmarked unit visibly moved onto its
   objective.

**Out of scope.** New verbs, per-unit parameter systems, TRADE.

**Evidence.** _(fill)_

---

## PM-4 — Sandbox "Plan Editor" session

**Status:** TODO
**Depends:** PM-1
**Player-facing:** yes — version_history entry required

**Goal.** From the main menu, a player launches a planning sandbox: pick army
+ deployment zone + terrain layout, then traverse the REAL phase flow
(FORMATIONS → ROLL_OFF → DEPLOYMENT) controlling the target army with no
opponent pressure, and stay held at the end of deployment for PM-5/PM-6.

**Context to load.** `MainMenu.gd`: start flow (`_on_start_button_pressed` →
config dict 1424-1443 → `_initialize_game_with_config` 1499-1591), and the
11e derived-mode reality — Mission and Deployment dropdowns are HIDDEN
read-only labels (833-864), deployment auto-snaps to the layout's
`recommended_deployments[0]` (990-1006), so the editor needs its OWN
deployment-zone picker (defensible: plans key on `deployment_zone_id`).
`Main.gd:490-492` (new game enters FORMATIONS), `PhaseManager.gd` flow +
`_on_phase_completed` (380-407), `RollOffPhase.gd:235-237` (needs roll +
choice), `FormationsPhase.gd:699-714` (both players must CONFIRM),
`TurnManager.gd:158-175` (alternation pins to the only side with units),
`DeploymentPhase.gd:44-52` (Castellan's Mark hold — the precedent that
holding DEPLOYMENT open is safe; note completion fires from THREE emitters:
controller confirm `DeploymentController.gd:1233-1234`, `END_DEPLOYMENT`
`DeploymentPhase.gd:1093-1099`, on-enter auto-complete 44-52).

**Implementation requirements.**
1. Main menu: "Plan Editor" button → pickers for army (existing dropdown
   machinery), deployment zone (new explicit picker), terrain layout. Start
   sets `plan_editor: true` inside `meta.game_config` (canonical flag).
2. Seat setup: target army = player 1 (plans are authored in the P1 frame —
   locked decision 5). Player 2: after army application, clear player-2
   units from GameState (editor-path code); no pass-AI needed — TurnManager
   already skips a side with nothing to deploy.
3. Phase traversal: FORMATIONS runs for real for the target army (needed so
   PM-5 can record reserves/embark/attach) with P2's confirm auto-dispatched;
   ROLL_OFF auto-resolved (target army = defender); then DEPLOYMENT with the
   normal UI (drag, per-model staging undo Ctrl+Z exists —
   `DeploymentController.gd:194-197, 817, 943`; committed units cannot be
   un-deployed: v1 story is exit-and-restart).
4. Hold-open: one guard in `PhaseManager._on_phase_completed` (380-407)
   suppresses the DEPLOYMENT→advance when the flag is set — covers all three
   completion emitters. Assert `meta.phase` stays DEPLOYMENT after the final
   confirm.
5. A visible "PLAN EDITOR" banner + clean Exit-to-menu.

**Validation gate.** Windowed scenario `sp/pm4_plan_editor_session.json`
starting from the main menu (no fixture): enter the editor with recon_stomps
+ hammer_anvil, auto-traverse to DEPLOYMENT, deploy a unit via
`click_item_list`/`click_board_at`/`click_node` (imitate
`sp/deploy_reposition_rotate_mouse.json`), deploy the rest via
`execute_script`/`dispatch_action` for speed, assert phase holds (no advance)
and the banner is visible. `verify_delivery` clean. Screenshot: editor with
banner + deployed units.

**Out of scope.** Saving (PM-5), painting (PM-6), editing existing plans,
building undo.

**Evidence.** _(fill)_

---

## PM-5 — Deployment recorder: Save as Plan

**Status:** TODO
**Depends:** PM-4, PM-2a (round-trip), PM-1
**Player-facing:** yes — version_history entry required

**Goal.** In the editor after deployment, **Save as Plan** serializes what the
player did into a valid `wh40k_ai_plan` via PlanManager.

**Context to load.** PM-0 schema; PM-4 session; `state.phase_log` — every
executed action is appended in dispatch order with unit_id
(`BasePhase.gd:145` → `PhaseManager.gd:451-456` → `GameState.gd:1385-1389`)
and only cleared on phase transition (1391-1399), which the editor
suppresses — so **deployment order is derivable from the log at save time**
(live tracking optional). Actions to observe: `DEPLOY_UNIT`,
`COMPOSITE_DEPLOY`, `EMBARK_UNITS_DEPLOYMENT`, `ATTACH_CHARACTER_DEPLOYMENT`,
`PLACE_IN_RESERVES` (the human path sends plain `DEPLOY_UNIT` normally;
`COMPOSITE_DEPLOY` only with embark/attach — `DeploymentController.gd:1118-1199`).
Formations state for reserves/embark/attach (unit status `IN_RESERVES`,
formations meta).

**Implementation requirements.**
1. Serializer as a **static, headless-testable function**: order from
   phase_log; per-model positions px→inches (P1 frame — the editor seats the
   army as P1); reserves/embarkations/attachments from formations state;
   keys from the session config; `detachment_hint` from `faction.detachment`.
2. Auto-derive `anchors` (nearest objective id, depth from own zone edge,
   nearest terrain piece). Recorded only.
3. Save dialog: name (default-filled `"<army_file> — <zone_id>"` so scenarios
   need no typing), description, author; `PlanManager.save_plan`; validator
   errors/warnings surfaced in-dialog; success toast shows the path.
4. `earmarks` left empty (PM-6 adds them; schema allows absence).
5. **Round-trip proof**: the saved plan, consumed by PM-2a on the same
   config, reproduces the recorded deployment — from BOTH seats (P1 verbatim;
   P2 via the transform).

**Validation gate.**
1. Windowed scenario `sp/pm5_record_and_save_plan.json`: editor session →
   deploy ≥2 units → click Save as Plan → (name is default-filled; optionally
   set via an `execute_script` step assigning the LineEdit's `.text`) → save
   → assert the file exists under `user://ai_plans/` and PlanValidator
   passes it (`execute_script` assert).
2. Headless `tests/unit/test_plan_roundtrip.gd`: build a small deployment
   programmatically, serialize, feed to PM-2a consumption for seat 1 and
   seat 2, assert positions within 0.5" (transformed for seat 2).
3. Screenshot: save dialog over the completed deployment + success toast.

**Out of scope.** Editing existing plans (delete + re-record is the v1
story).

**Evidence.** _(fill)_

---

## PM-6 — Intent painter

**Status:** TODO
**Depends:** PM-5, PM-3
**Player-facing:** yes — version_history entry required

**Goal.** After deployment in the editor, the player paints earmarks: select
unit → one of five verbs → for `HOLD_OBJECTIVE` click an objective to bind
`target`; for `RESERVE_UNTIL` pick round 2/3 (writes the reserves list — the
single source of truth). Earmarks save into the plan.

**Context to load.** PM-0 verbs; PM-5 save path. Overlay reuse caveats:
`AIMovementPathVisual` auto-fades (2.5 s hold + 1 s fade,
`AIMovementPathVisual.gd:10-12`) and `AIUnitHighlight` is a text-less pulsing
ring — reuse the drawing STYLE only; earmark badges/arrows need their own
non-fading Node2D lifecycle. `ObjectiveVisual` is a plain Node2D with NO
input handling — the painter hit-tests board clicks against
`MissionManager` objective positions itself (scenarios click via
`click_board_at` at the objective's board position).

**Implementation requirements.** Painter panel visible only when
`meta.game_config.plan_editor` is set and deployment is complete: unit list
or click-to-select; five verb buttons; per-unit current earmark shown;
clear-earmark. Overlay badge (abbreviated verb) + line to bound objective
for HOLD/PUSH. Earmarks persist into the saved plan and reload within the
session. Vocabulary closed (five verbs).

**Validation gate.** Windowed scenario `sp/pm6_paint_intents.json`: editor
with ≥2 deployed units → select unit → HOLD_OBJECTIVE → `click_board_at` the
objective → assert overlay node exists and the saved JSON contains the
earmark (`execute_script` file read). `verify_delivery` clean. Screenshot:
board with ≥2 visible earmark badges/arrows (the feature's signature image).

**Out of scope.** New verbs, mid-battle repainting, TRADE.

**Evidence.** _(fill)_

---

## PM-7a — Assign plans in game setup

**Status:** TODO
**Depends:** PM-1, PM-2a
**Player-facing:** yes — version_history entry required

**Goal.** In main-menu game setup, an optional per-AI-seat "AI Plan" dropdown
(plans matching the selected army + current derived deployment; "Auto (best
match)"; "None"), wired through to the session.

**Context to load.** The exact per-seat precedent: difficulty dropdowns
(`MainMenu.gd:583-645`) → config keys (1406-1407, 1432-1433) →
`meta.game_config` (1519) → `Main.gd:695-705` → `AIPlayer.configure`; and the
even closer `playerN_ai_profile` chain (`Main.gd:707-715` →
`AIPlayer.load_player_profile` `AIPlayer.gd:337-346` → AIDecisionMaker) —
note it is applied AFTER `configure()` because configure clears profiles.
Dropdown repopulation must listen to `terrain_dropdown.item_selected` and the
disposition dropdowns — the deployment dropdown is invisible and changes only
programmatically (833-864, 990-1006).

**Implementation requirements.** Add `playerN_plan` to the config dict in
`_on_start_button_pressed` (1424-1443); read it in `Main.gd` next to the
ai_profile block; call `AIDecisionMaker.set_player_plan` AFTER `configure()`.
"Auto" = `find_plan_for` at game start; "None" forces formula. The active
plan (name + source) is logged at game start and shown as one line in the AI
turn summary panel.

**Validation gate.** Windowed scenario `sp/pm7a_assign_plan_from_menu.json`
(menu-start): select recon_stomps + an AI seat, open the plan dropdown, pick
a plan (copy a fixture plan into `user://ai_plans/` first via
`execute_script`), start, let deployment run, assert `plan:` deployment
records (per PM-2a) — proving the menu path reaches the AI. Screenshot:
setup screen with the dropdown populated.

**Out of scope.** Browser (PM-7b), import/export (Deferred).

**Evidence.** _(fill)_

---

## PM-7b — Plan browser

**Status:** TODO
**Depends:** PM-7a
**Player-facing:** yes — version_history entry required

**Goal.** A plan browser from the main menu: rows (name, army_file, zone,
layout, validation badge via PlanValidator, author); delete `user://` plans
with confirm (shipped `res://` plans show NO delete button — res files can't
be deleted in an export); rename.

**Validation gate.** Windowed scenario `sp/pm7b_plan_browser.json`: copy a
fixture plan to `user://ai_plans/` (`execute_script`), open browser, assert
the row + badge, delete it, assert file gone; shipped-plan row (if any
shipped yet) shows no delete. Screenshot: populated browser.

**Out of scope.** Editing, import/export dialogs (Deferred — FileDialog
precedent for v2: `SaveLoadDialog.gd:51-52, 1487-1547`).

**Evidence.** _(fill)_

---

## PM-8b — Simulator backend: plan vs plan, N seeded games

**Status:** TODO
**Depends:** PM-2a, PM-8a (its verdict dictates the reset implementation)
**Player-facing:** partially (backend; version_history entry lands with PM-9)

**Goal.** A `PlanSimulator` **autoload** that runs N AI-vs-AI games — same
mission/zone/layout, army per seat, plan A vs plan B (either may be None) —
sequentially in-process, seeded `seed_base + i`, with progress signals and
cancel; results to JSON + per-game records.

**Context to load.** PM-8a's spike report (follow its verdict). What to
extract vs. what to reuse: `AIBenchmarkRunner` is one-game-per-process,
cmdline-gated, fixture-only, and quits on every exit path — do NOT try to
"extend" it in place; **extract** its per-game watcher (progress-signature
stall detection, timeout-vs-stall, `_collect_result`, record write —
`AIBenchmarkRunner.gd:374-407, 454-618`) into a helper both callers share,
and build game construction on an extracted
`MainMenu._initialize_game_with_config` (1499-1591) bootstrap +
`change_scene_to_file("res://scenes/Main.tscn")` per game (games must run in
the live Main scene — `AIBenchmarkRunner.gd:308-309`). Subprocesses are
rejected (flaky precedent `tests/helpers/GameInstance.gd`; impossible on the
web export).

**Implementation requirements.**
1. API: `PlanSimulator.start({zone_id, layout_id, army1, army2, plan1,
   plan2, games, seed_base, difficulty})`; signals `game_finished(i,
   result)`, `run_finished(summary)`, `cancelled`. Mirror-match (same army
   both sides) is the headline case — MainMenu already allows it
   (`MainMenu.gd:1397-1400`, per-seat copies via `load_army_for_game`).
2. Per-game sequence: bootstrap game → **seed the triple**
   (`RulesEngine.set_test_seed`, `SecondaryMissionManager.set_test_seed`,
   `AIDecisionMaker.set_ai_seed`, each `seed_base + i`) → `configure()` both
   AI seats → **re-apply plans after configure** (configure clears them) →
   raise `_max_decision_record_batches` (as `AIBenchmarkRunner.gd:324-326` —
   the 500-batch ring otherwise drops the deployment records adherence needs)
   → run via the extracted watcher → harvest results/records BEFORE the next
   configure.
3. Explicit between-games reset list (from PM-8a, at minimum):
   `AIPlayer.configure()`, `StratagemManager.reset_for_new_game()`,
   `UnitAbilityManager.reset_for_new_game()` (NO production caller today —
   once-per-battle locks leak otherwise), `MissionManager.initialize_mission`,
   `SecondaryMissionManager` init (as `MainMenu.gd:1531-1564`),
   `PhaseManager` game_ended cleared. Assert equal unit counts at each game
   start.
4. After the run (or cancel): `RulesEngine.set_test_seed(-1)`,
   `AIDecisionMaker.set_ai_seed(-1)`, re-randomize the secondary deck RNG,
   `Engine.time_scale = 1.0`, return to menu cleanly.
5. Difficulty is an explicit parameter, default Normal (matching bench
   baselines — `BENCH_DIFFICULTY` default 1; plans are difficulty-
   independent per locked decision 9); recorded per run.
6. Result rows: seed, winner, vp per player, margin, rounds, **plan
   adherence counts per seat** (from PM-2a records — seat-2 adherence > 0 is
   a gate), wall seconds, difficulty. Summary: wins A/B/draws, mean margin ±
   sd, measured s/game (feeds PM-9's ETA). Write
   `user://plan_sim_results/<timestamp>.json` (timestamp via
   `Time.get_datetime_string_from_system` — wall clock never inside seeded
   game logic).
7. Decide and document `ReplayManager.auto_record_ai` for sim games
   (recommended: leave ON — the auto-recorded replays are the only rewatch
   mechanism, `ReplayManager.gd:39, 247-249`; note the N-files cost).

**Validation gate.** Headless driver: 2-game mirror run (small armies),
assert 2 result rows, correct summary math, differing seeds, equal unit
counts at both game starts, **seat-2 plan adherence > 0**, zero stalls; same
run twice at same seed_base → identical winners and margins;
`read_debug_log` no-ERROR.

**Out of scope.** UI (PM-9), parallelism, subprocesses, stats beyond
mean ± sd.

**Evidence.** _(fill)_

---

## PM-9 — Simulator UI

**Status:** TODO
**Depends:** PM-8b, PM-7a
**Player-facing:** yes — version_history entry required (covers PM-8b too)

**Goal.** "Battle Simulator" from the main menu: configure (army/plan per
side via PM-7a's pickers, zone/layout, games 1–20, difficulty), Run,
progress + ETA + Cancel, results table, per-game replay access, export.

**Context to load.** PM-8b API. **The UI must be an autoload `CanvasLayer`
overlay** — each game changes scene into Main.tscn, which would free a
menu-scene Control; games visibly play underneath the overlay. Wall-time
expectations from bench baselines: ~2.5 min/game Custodes, ~8 min Orks,
predeploy ≈3.4×— surface the measured s/game as ETA after game 1 and warn on
large runs. Summary/replay panels are LIVE-only; per game show the record
JSON path and, if auto-record stayed on (PM-8b), a "Watch replay" affordance
via the existing menu replay path (`MainMenu.gd:1854-1881`).

**Validation gate.** Windowed scenario `sp/pm9_simulator_run.json`: open
simulator, configure a 2-game mirror run (smallest armies) with a plan vs
None, Run, wait via `expect_node_visible` on the results table with a
generous `timeout_s`, assert 2 rows + summary text matches the backend JSON;
cancel path: start, cancel, assert clean return to menu. `verify_delivery`
clean after the run. Screenshots: configured setup; completed results table
(signature image).

**Out of scope.** Charts, Elo, parallel execution.

**Evidence.** _(fill)_

---

## PM-10 — First real content + lab verdict

**Status:** TODO
**Depends:** PM-2a, PM-2b, PM-3 (PM-5 helpful for authoring)
**Player-facing:** yes (shipped plans) — version_history entry required

**Goal.** Author and ship the first two real plans; measure them honestly.

**Fixture-key reality (why this task is worded carefully):** the predeploy
fixtures' actual identity is `deployment_type: crucible_of_battle`,
`board.terrain_layout: take_and_hold_mirror_1`, with an EMPTY `game_config`
(verified by decompressing `mirror_orks_2000_predeploy.w40ksave`). A plan
keyed `hammer_anvil` can never auto-match there. Therefore:

**Deliverables.**
1. **Two shipped plans** under `40k/data/ai_plans/` passing PlanValidator
   with zero warnings: (a) recon_stomps keyed to the Ork predeploy fixture's
   real identity (`crucible_of_battle` + `take_and_hold_mirror_1`) — the
   measured plan; strong-practice content: Gretchin on home objectives,
   screens vs deep strike, Stormboyz split (some reserved R2), Stompa +
   cargo pushing mid together, `"author": "claude-draft — owner review
   wanted"`; (b) a hammer_anvil recon_stomps variant for menu play (same
   content, transformed keys), or `custodes_lions` on its fixture identity —
   pick based on what PM-5 makes easy.
2. **Paired A/B** on `mirror_orks_2000_predeploy` via the PM-2a bench
   plumbing (`BENCH_P1_PLAN`/`BENCH_P2_PLAN` + side-swap, or
   `tools/ai_lab/run_paired.py` if extended for plans): plan-active vs
   plans-disabled (`PLANS_ENABLED: 0` profile arm), ≥6 paired seeds; ALSO
   one arm at **Normal** difficulty (the shipped default — the feasibility
   report's sharpest institutional critique was never measuring it).
3. **Honest gate**: primary = zero stalls/errors + plan adherence ≥90% of
   covered units **on both seats** + before/after deployment screenshots
   (plan vs formula — visibly different). E is REPORTED with its se and the
   minimum detectable effect at the run's n stated plainly (predeploy sd ≈
   20 VP ⇒ 6 pairs detect only ~±23 VP; say so); "E not significantly
   negative" is a sanity check, not a success claim. A null E with high
   adherence is an acceptable outcome — perceived-quality is the point.
4. **Owner evidence item**: one human-vs-AI game against the plan-driven AI
   (owner plays, or a scripted stand-in session if the owner is
   unavailable — then say so), with notes on where the plan looked smart or
   stupid. This is the feasibility report's #1 recommendation and it enters
   the record here.
5. Report: `40k/tests/bench_baselines/<date>_plan_vs_formula.md` in the
   neighbouring reports' style. Run `tools/ai_lab/validate_profile.py` (or
   its extension) over the shipped plans' `profile_fragment`s.
6. **Export check**: verify shipped plan JSONs are present in an exported
   build; `40k/export_presets.cfg` `include_filter` currently lists only
   `data/*.csv` + tutorial fixtures — add `data/ai_plans/*.json` to all
   presets if missing.

**Validation gate.** The bench report exists with real numbers + power
statement; both plans validate clean; adherence per seat reported;
screenshots in report + TLDR; export check done (or its failure documented).

**Out of scope.** Tuning earmark bonus params (defaults; note follow-up),
more factions.

**Evidence.** _(fill)_

---

## PM-11 — Docs, release notes, coherence pass

**Status:** TODO
**Depends:** all previous
**Player-facing:** yes — consolidated version_history entry if any gap

**Deliverables.**
1. `40k/docs/PLAN_FORMAT.md` final pass: five-verb table, frame/transform
   rule, matching + fallback semantics, fragment merge order, walkthrough
   with the PM-5/6/9 screenshots.
2. Player-facing help/README: "AI Plans" section (record, paint, assign,
   simulate).
3. `40k/data/version_history.json`: verify every player-facing PM task added
   its entry; add a consolidated "AI Plans" headline entry if fragmentary.
4. Coherence checks: `PLANS_ENABLED: 0` produces zero behavior change (A/A
   vs a pre-PM baseline commit, or determinism vs a recorded pre-change
   trajectory — document which); Plan Editor and Simulator survive
   entry→exit→re-entry (`sp/pm11_reentry.json`); `--headless --import`
   clean; all PM scenarios green in one
   `bash 40k/tests/run_scenarios.sh tests/scenarios/sp/pm*.json` batch.
5. Sweep for stray `print` spam introduced by PM tasks (file-logged debug
   stays, per project rules).

**Validation gate.** Batch scenario run output in Evidence; docs committed;
version history renders in the main menu (screenshot).

**Evidence.** _(fill)_

---

## Deferred (explicitly NOT in this workstream — add tasks only when reached)

- `if_going_second` / conditional pull-backs. Cut from v1: the game has TWO
  roll-offs (ROLL_OFF pre-deployment sets deploy order / `meta.defender`;
  FIRST_TURN_ROLLOFF post-redeployment sets the game's first turn) and
  verification produced conflicting readings of when `meta.first_turn_player`
  is authoritative. Before designing this, pin the timing down in code and
  define the trigger explicitly.
- `TRADE` verb (needs a per-unit parameter mechanism that does not exist).
- Anchor-based generalization across layouts; archetype-level plans;
  role-classifier improvements.
- Plan import/export dialogs (plans are plain JSON under `user://ai_plans/`;
  FileDialog precedent noted in PM-7b).
- Plan editing UI (v1: delete + re-record).
- Simulator parallelism; statistics beyond mean ± sd.
- Community sharing.
- Extending `run_paired.py` with first-class plan arms (PM-10 can work
  through `run_ai_benchmark.sh` env; promote if the lab adopts plans).

---

## PM-F1 — FOLLOW-UP: the deployment formula fails validation on diagonal zones

**Status:** TODO
**Depends:** — (pre-existing behaviour, found while gathering PM-2a evidence)
**Player-facing:** yes (AI behaviour)

**What was observed.** Running `mirror_custodes_2000_predeploy`
(`crucible_of_battle`, a TRIANGULAR zone) with `PLANS_ENABLED = 0`, the AI's
column-formula deployment repeatedly emits placements `DeploymentPhase` rejects:
```
P2: Custodian Guard deployment failed (Model must be wholly within deployment
    zone, Model must be wholly within deployment zone, …) — retrying
P2: Deployed Custodian Guard (retry 1)
P2: Prosecutors deployment failed (…) — retrying
P2: Deployed Prosecutors (retry 2)
```
and one unit — Custodian Guard Zeta, 225 pts / 5 models — could not be placed at
all and was dumped into **Strategic Reserves**, arriving R2+. Screenshot:
`40k/docs/evidence/pm2a_plans_disabled_formula_deployment.png`.

**Why.** `_decide_deployment` builds positions from a rectangular
`zone_bounds`, and `_resolve_formation_collisions` clamps to that rectangle
(`AIDecisionMaker.gd:19656-19712`). For hammer_anvil/dawn_of_war the rectangle
IS the zone; for `crucible_of_battle` (triangle), `search_and_destroy` and
`tipping_point` it is not, so the formula generates positions outside the real
polygon. PM-2a added a polygon + shape-aware check on the PLAN path only
(`_plan_shape_inside_polygon`); the formula path still has none.

**Suggested fix.** Give the formula the same polygon containment guard the plan
path now uses, i.e. re-project or reject-and-resample candidates against
`_get_deployment_zone_polygon_pixels` before emitting the action.

**Validation gate.** A windowed scenario on the crucible fixture with
`PLANS_ENABLED = 0` asserting ZERO `deployment failed` log lines and zero units
forced into reserves; plus a headless test over all six shipped zones.

**Evidence.** _(fill)_

---

## PM-F2 — FOLLOW-UP: the validator does not check attachment legality

**Status:** TODO
**Depends:** PM-0
**Player-facing:** no (authoring-time validation)

**What was observed.** A plan can name a leader/bodyguard pairing the game
cannot make, and nothing complains: `PlanValidator` checks only that both ids
are present and distinct. At play time the AI simply never matches an available
`DECLARE_LEADER_ATTACHMENT` and falls through to its own pairing, so the author
sees the plan "work" while the attachment it asked for never happens. This was
found because the PM-0 rich fixture paired Wazdakka Gutsmek with Warbikers —
`data/40kdc/leaderAttachments.json` has no leader row for Wazdakka at all, and
`warbikers` is only led by `deffkilla-wartrike`.

**Suggested fix.** Load `res://data/40kdc/leaderAttachments.json` in
`PlanValidator` and, when an army dict is supplied, resolve each attachment's
character and bodyguard to their datasheet ids and check membership. Emit a
WARNING rather than an error if the datasheet id cannot be resolved (so an
unusual army file cannot make a good plan unloadable), and an ERROR when the ids
resolve and the pairing is genuinely not eligible.

**Validation gate.** Headless cases in `test_plan_validator.gd`: the shipped
fixture pairing passes; the Wazdakka/Warbikers pairing is rejected with the
eligible leaders named; an unresolvable datasheet id warns instead of failing.

**Evidence.** _(fill)_

