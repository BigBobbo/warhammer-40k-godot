# AI Plan Maker — implementation task list

Created 2026-08-10 on branch `claude/wh40k-ai-feasibility-ucj3hm`. Companion
to `research/ai_feasibility_2026-08-09.md` (the feasibility assessment that
motivates this work) and the conversation that designed it.

## What is being built, in one paragraph

A data-driven **plan system** for the game's AI: JSON "plans" that describe,
for a specific army list on a specific deployment map (and optionally a
specific terrain layout), (a) exactly how to deploy — order, per-model
positions, reserves — and (b) high-level per-unit intents for the game
("hold objective X", "push center", "screen", …). Players author these plans
**inside the game** (deploy the AI's army by hand and hit *Save as Plan*,
then paint intents on units), and can pit plan against plan in an AI-vs-AI
**simulator**. The AI consumes the same artifact: when a plan matches the
current game it follows it, degrading gracefully to its existing logic
whenever the plan does not apply. The end state after all tasks: the three
player-facing stages work — **Deployment Recorder**, **Intent Painter**,
**Simulator** — plus the AI-side consumption that makes plans meaningful,
and one shipped real plan (recon_stomps) proven against the current AI in
the lab.

## Why (context from the feasibility research — do not re-litigate)

- The AI's deployment today is a deterministic column formula
  (`AIDecisionMaker.gd` `_decide_deployment`, ~line 3912): deployment order
  is not even a decision, and placement is `deployed_count % columns` with
  nudges. Deployment "largely decides rounds 1-2" per the AI's own source.
- Every measured micro-tactical improvement in this repo's lab scored ~zero
  VP; the only large measured effect was a strategic pre-decision (reserves
  cap). Authored strategy is the evidence-backed lever. Precedents: chess
  opening books, StarCraft build orders, Combat Mission's authored
  per-scenario AI plans, paper automas (Five Parsecs, OPR solo rules).
- Design decisions **locked** by that research + the owner's direction:
  1. Plans are **data** (JSON), same artifact whether authored by hand, by
     the recorder UI, or by an LLM offline. No separate authoring format.
  2. Plans are **intents with fallback chains, never scripts**. A plan must
     be *unable* to produce an illegal game state: every placement resolves
     through existing deployment validation with repair, every intent falls
     back to the AI's current logic when it cannot apply.
  3. Plans are keyed to **specific lists on specific deployments** (the
     owner explicitly wants e.g. "recon_stomps on Hammer and Anvil").
     Archetype-level generalization is deferred — the fallback for a
     missing plan is simply the current AI behavior.
  4. Units are referenced **by unit name with role fallback**, never by
     transient unit ids, so an edited list degrades gracefully (validator
     reports "plan covers 15/17 units").
  5. The plan maker lives **in Godot**, reusing the real DeploymentPhase in
     a sandbox session — never a forked editor scene, never a web app
     (geometry/validation drift).
  6. The intent vocabulary is **deliberately tiny** (6 verbs, listed in
     PM-0). Resist expanding it.
  7. Dice are never fudged. Plans and the simulator use the normal engine.

## Global context every task instance needs

Work happens in this repo (`/home/user/warhammer-40k-godot` locally; adjust
to your checkout). The game is Godot 4.4, project root `40k/`. Read
`CLAUDE.md` at repo root first — it defines the validation gates, the
screenshot-in-TLDR rule, and how to run the game windowed in a container
(`export PATH="$HOME/bin:$PATH"; godot --headless --import` once, then
`godot --path 40k --rendering-method gl_compatibility` under the shim's
xvfb; the in-game MCP bridge on port 9080 provides `capture_screenshot`,
`verify_delivery`, `read_debug_log`, `simulate_click`, `dispatch_action`).

Key existing code you will touch or imitate (verify line numbers by grep —
they drift):

| Thing | Where | Notes |
|---|---|---|
| AI deployment decision | `40k/scripts/AIDecisionMaker.gd` `_decide_deployment` (~3912) | column formula; emits `DEPLOY_UNIT` actions with per-model positions |
| AI objective assignment | same file, `_assign_units_to_objectives` (~7950) | greedy (unit × objective/screen/attack) assignment — earmarks pre-seed this |
| Deployment actions | `40k/phases/DeploymentPhase.gd` | `DEPLOY_UNIT` (AI path, all models at once), `COMPOSITE_DEPLOY` (human path); `validate_action`/`process_action` |
| Profile format + manager | `40k/scripts/ProfileManager.gd` | `wh40k_ai_profile` JSON in `user://ai_profiles/`; PlanManager imitates this |
| Parameter layering | `AIDecisionMaker.get_param`, `40k/data/ai_config.json`, `docs/AI_TUNING.md` | rule overrides → per-player profile → global config → default |
| Army lists | `40k/autoloads/ArmyListManager.gd` (`load_army_list`, `apply_army_to_game_state`), lists in `40k/armies/*.json` | e.g. `recon_stomps.json`, `custodes_lions.json` |
| Deployment zones | `40k/deployment_zones/*.json`, loaded via `40k/scripts/data/DeploymentZoneData.gd` | polygons in board inches, 44×60 portrait board |
| Terrain layouts + objectives | `40k/terrain_layouts/*.json`, `40k/autoloads/TerrainManager.gd`, `40k/autoloads/MissionManager.gd` | objectives have stable ids (`obj_home_1` …); layouts have `mission_matchup_id`, `recommended_deployments` |
| Main menu game setup | `40k/scripts/MainMenu.gd` | already has mission/terrain/deployment dropdowns, per-player type (Human/AI), difficulty, AI speed |
| AI benchmark harness | `40k/tests/run_ai_benchmark.sh`, `40k/autoloads/AIBenchmarkRunner.gd` | headless AI-vs-AI, seeds, per-player profile injection, game records; fixtures like `mirror_orks_2000_predeploy` |
| Windowed scenarios | `40k/tests/scenarios/_schema.md`, `sp/*.json`, `bash 40k/tests/run_scenario.sh tests/scenarios/sp/<id>.json` | the project's correctness gate for anything player-facing |
| Determinism check | `tools/ai_lab/determinism_check.py` | run when AI behavior changes; `--require trajectory` for instrumentation-only changes |
| Game records / summaries | `40k/scripts/AIGameRecord.gd`, `AITurnSummaryPanel.gd`, `AITurnReplayPanel.gd` | reuse for simulator results |
| Units | board is 44×60 **inches**; rendering in px | find the px-per-inch constant by grep before converting anything; store plan coordinates in **inches** like deployment_zones JSONs |

Project gates that apply to EVERY task here (from `CLAUDE.md`):

- Anything player-facing needs a **windowed scenario** under
  `40k/tests/scenarios/sp/` proven passing, and a **screenshot of the
  feature's effect** captured live via the MCP bridge, shared in the task's
  end-of-task TLDR. Headless-only evidence is not sufficient for UI.
- Player-facing changes **prepend an entry to
  `40k/data/version_history.json`** (bump version, date, player-readable
  summary).
- Do not remove debug logs. All logging must also reach the
  `user://logs/debug_*.log` files.
- Never claim a limitation you have not reproduced; never claim done
  without the gate's evidence. If blocked, record the failing command and
  its output in the evidence block.

## Task protocol

- Tasks are ordered; each lists `Depends`. Do not start a task whose
  dependencies are not DONE in this file.
- On completing a task: set its Status to DONE, fill its **Evidence** block
  (commands run, key output, scenario ids, screenshot paths, commit SHAs),
  commit code + this file together, push to the designated branch.
- Keep each task to its stated scope. If you find adjacent work, add a new
  task block at the bottom instead of expanding the current one.
- Update `.llm/plan-maker-progress.md` (create on first task) with one line
  per task: status, key result, timestamp.

## Dependency graph

```
PM-0 schema+validator
  └─ PM-1 PlanManager
       ├─ PM-2 AI deployment consumption ──┐
       ├─ PM-3 AI earmark consumption      │
       ├─ PM-4 sandbox session ─ PM-5 recorder (needs PM-2 for round-trip)
       │                          └─ PM-6 intent painter (needs PM-3)
       ├─ PM-7 plan browser + assignment (needs PM-2)
       └─ PM-8 simulator backend (needs PM-2; PM-3 recommended)
            └─ PM-9 simulator UI
PM-10 first real content + lab A/B (needs PM-2, PM-3; PM-5 helpful)
PM-11 docs + release polish (needs all)
```

---

## PM-0 — Plan schema v1 + validator + example fixtures

**Status:** TODO
**Depends:** —
**Player-facing:** no (data + tests only; no version_history entry)

**Goal.** Define the `wh40k_ai_plan` JSON format v1, write a validator, and
commit two hand-written example plans that every later task uses as test
fixtures.

**Context to load.** `40k/scripts/ProfileManager.gd` (the `wh40k_ai_profile`
format and its `validate` pattern — imitate both), one file each from
`40k/deployment_zones/` and `40k/terrain_layouts/` (source of the ids plans
reference), `40k/armies/recon_stomps.json` and `custodes_lions.json` (unit
names plans reference), `40k/tests/scenarios/_schema.md` (how this repo
documents formats).

**Schema v1 — required shape** (write the authoritative version to
`40k/docs/PLAN_FORMAT.md` with a full annotated example):

```json
{
  "format": "wh40k_ai_plan",
  "version": 1,
  "name": "Recon Stomps — Hammer & Anvil",
  "description": "...",
  "author": "...",
  "keys": {
    "army_file": "recon_stomps",
    "army_name_hint": "Speedwaaagh!",
    "deployment_zone_id": "hammer_anvil",
    "terrain_layout_id": "disruption_vs_disruption_1",
    "mission_id": ""
  },
  "deployment": {
    "order": ["Gretchin", "Boyz A", "..."],
    "placements": [
      { "unit": "Boyz A",
        "role_fallback": "screen",
        "models_inches": [[10.5, 12.0], [11.5, 12.0]],
        "anchors": { "nearest_objective": "obj_home_1",
                      "depth_from_zone_edge_in": 4.0,
                      "nearest_terrain_piece": "area-large-2" } }
    ],
    "reserves": [ { "unit": "Stormboyz", "arrival_round": 2 } ],
    "if_going_second": { "pull_back_inches": 3.0, "units": ["Boyz A"] }
  },
  "earmarks": [
    { "unit": "Warboss unit", "verb": "PUSH_CENTER" },
    { "unit": "Gretchin", "verb": "HOLD_OBJECTIVE", "target": "obj_home_1" }
  ],
  "profile_fragment": { "parameters": {}, "rules": [] }
}
```

Locked vocabulary — exactly six verbs, schema rejects others:
`HOLD_OBJECTIVE` (requires `target` = objective id), `PUSH_CENTER`,
`SCREEN`, `RESERVE_UNTIL` (requires `round`), `HUNT_CHARACTERS`, `TRADE`.
`profile_fragment` reuses `wh40k_ai_profile` semantics verbatim (parameters
+ rules DSL) so stances need no new mechanism. `models_inches` are board
inches (same space as deployment_zones JSON). `anchors` are **recorded but
not resolved in v1** — they exist so a future task can generalize across
layouts; nothing in this workstream may depend on them.

**Deliverables.**
1. `40k/docs/PLAN_FORMAT.md` — the format doc with annotated example and
   the verb vocabulary table.
2. `40k/scripts/PlanValidator.gd` (static, RefCounted, mirroring
   ProfileManager's validate style): checks format/version/keys, verb
   vocabulary, that `deployment_zone_id` and `terrain_layout_id` exist on
   disk, that every placement has ≥1 model position inside the referenced
   player-1 zone polygon (point-in-poly against `DeploymentZoneData`), and
   returns `{valid, errors: [], warnings: [], coverage: {units_in_plan,
   units_in_army, unmatched: []}}` when given an army dict to check against.
   Unit matching: exact unit-name match, else warn + `role_fallback`.
3. Two example plans committed under `40k/data/ai_plans/examples/`:
   one minimal-valid, one deliberately rich (all six verbs, reserves,
   if_going_second) — these are TEST FIXTURES, not shipped content; mark
   them `"author": "fixture"`.
4. Headless test `40k/tests/unit/test_plan_validator.gd` following the
   conventions of neighbouring `tests/unit/test_*.gd` files (check
   `40k/RUN_TESTS.md` / `README_TESTING.md` for the runner): valid plan
   passes; each corruption class fails with the expected error (bad verb,
   missing target on HOLD_OBJECTIVE, unknown zone id, placement outside
   zone, unit not in army → warning not error).

**Validation gate.** `godot --headless --import` clean; the unit test file
runs green via the repo's test runner; `PlanValidator` rejects/accepts the
fixtures as designed (paste the test output into Evidence).

**Out of scope.** Any loading at runtime (PM-1), any AI behavior (PM-2/3),
anchor resolution.

**Evidence.** _(fill on completion)_

---

## PM-1 — PlanManager: storage, listing, matching

**Status:** TODO
**Depends:** PM-0
**Player-facing:** no

**Goal.** A `PlanManager` static utility (mirroring `ProfileManager.gd`)
that lists/loads/saves/deletes plans and answers the one question the AI
will ask: *“which plan, if any, applies to this game for player N?”*

**Context to load.** `40k/scripts/ProfileManager.gd` (imitate structure,
user-dir bootstrap, error handling), PM-0's validator + fixtures,
`40k/autoloads/GameState.gd` (grep for how the current mission /
deployment / terrain selections and per-player army identity are stored in
state or meta — you need to read them for matching).

**Deliverables.**
1. `40k/scripts/PlanManager.gd`:
   - Search path: `user://ai_plans/` first, then `res://data/ai_plans/`
     (shipped). `list_plans()` returns name/path/keys/validation summary.
   - `save_plan(dict)` → validates via PlanValidator, refuses invalid,
     writes to `user://ai_plans/<slug>.json`.
   - `find_plan_for(player, snapshot)` → resolves the game's
     `(army_file, deployment_zone_id, terrain_layout_id)` from
     state/meta and matches: exact (army+zone+layout) → (army+zone,
     layout wildcard) → `{}` . Deterministic tie-break (alphabetical by
     name) if several match at the same rank; log the choice via the
     debug-log path.
   - No caching that survives across games without an explicit
     `reset()` — follow the pattern of `AIDecisionMaker.reset_caches()`.
2. Headless test `40k/tests/unit/test_plan_manager.gd`: fixture plans are
   found; exact beats wildcard; mismatched army returns `{}`; save→list→load
   round-trip preserves content; invalid save refused.

**Validation gate.** Unit test green; `--headless --import` clean; a
5-line `godot --headless --script` smoke (or the unit test itself) showing
`find_plan_for` output for a fabricated snapshot pasted into Evidence.

**Out of scope.** UI, AI consumption.

**Evidence.** _(fill)_

---

## PM-2 — AI consumes the deployment section

**Status:** TODO
**Depends:** PM-1
**Player-facing:** yes (AI behavior) — version_history entry required

**Goal.** When a plan matches, `_decide_deployment` follows it: deploys in
plan order, at plan positions, honoring the reserves manifest and (when the
AI is deploying second — detectable from state) the `if_going_second`
adjustment. Per-unit fallback: any unit the plan does not cover, or whose
placement cannot be made legal, uses the existing formula.

**Context to load.** `40k/scripts/AIDecisionMaker.gd` `_decide_deployment`
(~3912) end to end — understand: first-undeployed-unit selection, the
column formula, how `DEPLOY_UNIT` actions are built (per-model positions in
px), the AAO spacing adjustment, and `_record_choice("deployment", ...)`
instrumentation. `40k/phases/DeploymentPhase.gd` `validate_action` for
`DEPLOY_UNIT` (what legality means). PM-1's `find_plan_for`. Find the
px-per-inch conversion by grep and reuse the existing constant — do not
hardcode a number.

**Implementation requirements.**
1. Gate everything behind a config: `ai_config.json` key
   `"plans_enabled": true` default ON, plus per-player plan override
   (see PM-7/PM-8 for how a specific plan is assigned; for this task, the
   assignment mechanism is: `AIDecisionMaker.set_player_plan(player, plan)`
   + automatic `find_plan_for` when none set).
2. Deployment **order**: deploy units in plan order (this is new — today
   order is "first undeployed"). Units missing from the plan deploy after
   planned units, via the formula.
3. **Placement**: convert `models_inches` → px, submit as `DEPLOY_UNIT`.
   If validation rejects (occupied/out-of-zone after a terrain change),
   run the existing spiral/repair search from the plan position; if repair
   fails, fall back to formula for that unit. Never stall the phase — the
   Heroic-Intervention deadlock post-mortem
   (`research/ai_improvement_status_2026-08-07.md` §6) is the cautionary
   tale; every path must end in a valid action or an explicit legal skip.
4. **Reserves**: units with a `reserves` entry use the existing strategic
   reserves pathway (grep `_decide_deployment` and the todo's reserves
   coefficients for where reserves declarations happen); respect the
   rules-legal reserves points cap — if the plan exceeds it, log + trim
   deterministically (plan order) and surface a validator warning in PM-0
   (add the check there if missing).
5. **Instrumentation**: every plan-driven placement emits
   `_record_choice("deployment", ...)` with a `"source": "plan:<name>"`
   context field, and fallbacks record `"source": "formula_fallback"` —
   the lab must be able to count plan adherence per game.
6. Determinism: no new unseeded RNG. Same plan + seed ⇒ identical
   deployment.

**Validation gate.**
1. Headless: new test `40k/tests/unit/test_ai_plan_deployment.gd` — build a
   snapshot from a predeploy fixture (see
   `40k/tests/make_2000pt_fixture.gd` and existing predeploy fixtures),
   inject a PM-0 fixture plan, assert: order followed, positions within
   0.5" of plan, uncovered unit fell back, reserves declared as manifest.
2. Determinism: `tools/ai_lab/determinism_check.py` (full `all` mode) on
   one predeploy fixture, 2 seeds, with the plan active — identical runs.
3. Windowed scenario `sp/pm2_ai_deploys_from_plan.json`: load a predeploy
   fixture, assign the fixture plan to the AI player, let the AI deploy,
   assert via `get_node_info`/state that ≥1 named unit sits at its planned
   position and the debug log carries `plan:` deployment records with no
   ERROR lines (`verify_delivery`).
4. Screenshot of the deployed formation (the plan's shape must be visibly
   non-columnar) for the TLDR.

**Out of scope.** Earmarks (PM-3), any UI.

**Evidence.** _(fill)_

---

## PM-3 — AI consumes earmarks + profile fragment

**Status:** TODO
**Depends:** PM-1 (PM-2 not required but recommended first)
**Player-facing:** yes — version_history entry required

**Goal.** The six verbs bias the AI's existing machinery for the whole
game, with graceful decay: earmarks are priors, not orders.

**Context to load.** `AIDecisionMaker.gd` `_assign_units_to_objectives`
(~7950) — how (unit × objective/screen/attack) pairs are scored and
assigned; `_build_phase_plan` (~2794); how
`load_player_profile`/`get_param` layering works (~324, ~467);
`MissionManager.gd` objective ids; PM-0 verb table.

**Implementation requirements — verb semantics (keep exactly this simple):**
- `HOLD_OBJECTIVE(target)`: large additive bonus for that (unit, objective)
  pair in `_assign_units_to_objectives`; expose the bonus via
  `get_param("PLAN_EARMARK_HOLD_BONUS", <default>)` so the lab can tune it.
- `PUSH_CENTER`: same-shaped bonus toward the mid objective(s)
  (`MissionManager.get_objective_ids_by_designation` or nearest-to-center).
- `SCREEN`: unit is offered to the existing screening assignment first
  (grep `SCREEN-PROTECT` / screening functions) before objective duty.
- `RESERVE_UNTIL(round)`: consumed at deployment (PM-2) if present; in-game
  it only gates early arrival if the reserves pathway asks.
- `HUNT_CHARACTERS`: additive bonus on CHARACTER-keyword targets in the
  existing target-value scoring (find the shooting/charge target-value
  functions; single param `PLAN_EARMARK_HUNT_BONUS`).
- `TRADE`: applies the plan's `profile_fragment` aggression-style
  parameters to this unit if per-unit params exist; if the profile layer
  is global-only, implement TRADE as a documented no-op for v1 **and say
  so in PLAN_FORMAT.md** rather than inventing a per-unit param system.
- Decay rule (uniform, one place): an earmark is ignored for a unit below
  half its starting models/wounds, and logged as released. Param:
  `PLAN_EARMARK_RELEASE_AT` (0.5).
- `profile_fragment` is applied through the **existing**
  `load_player_profile` layering at game start when a plan is active
  (merge order: plan fragment sits where a per-player profile sits; if a
  real per-player profile is also set, profile wins; document this).
- All earmark applications emit decision-record context
  (`"earmark": "HOLD_OBJECTIVE:obj_home_1"`) so records show adherence.

**Validation gate.**
1. Headless unit test: fabricated snapshot + plan → assignment output shows
   the earmarked unit on its objective in round 1; same unit at 40%
   strength → earmark released (assert the log/record).
2. Determinism check as in PM-2.
3. Windowed scenario `sp/pm3_earmarks_bias_assignment.json` on a predeploy
   or postdeploy fixture with the plan assigned: drive one AI movement
   phase; assert via decision records / state that the HOLD unit moved
   toward its objective and records carry the earmark context; zero ERROR
   lines.
4. Screenshot: AI turn with the earmarked unit visibly moved onto its
   objective (before/after or the AI movement-path visual).

**Out of scope.** New per-unit parameter systems, new verbs, UI.

**Evidence.** _(fill)_

---

## PM-4 — Sandbox "Plan Editor" session

**Status:** TODO
**Depends:** PM-1
**Player-facing:** yes — version_history entry required

**Goal.** A player can launch a planning sandbox from the main menu: pick
mission / deployment map / terrain layout / army (reusing the existing
dropdown machinery in `MainMenu.gd`), then play the **real deployment
phase** controlling the target army, with no opponent pressure: opponent
side empty or auto-skipping, both deployment zones visible, unlimited time.
This is the substrate for the recorder (PM-5) and painter (PM-6).

**Context to load.** `40k/scripts/MainMenu.gd` (how Start Game gathers
config and what it passes to the game scene — grep the start-button
handler and follow it), `40k/scripts/Main.gd`, `PhaseManager.gd`
transitions, `DeploymentPhase.gd` (human path: `COMPOSITE_DEPLOY`),
`ArmyListManager` application, how player types (Human/AI) are configured
per seat. **Do not fork the deployment scene** — run the real one with a
session flag (e.g. `GameState.meta.plan_editor = true`) that the phase and
UI read.

**Implementation requirements.**
1. Main menu: a "Plan Editor" button (place near Load/Replay) opening the
   same mission/army pickers (reuse, don't duplicate, the dropdown
   population code — extract helpers if needed) + a Start.
2. In-session: player 1 seat is Human controlling the chosen army;
   player 2 seat empty or a do-nothing AI that instantly passes its
   deployment turns (pick whichever is least invasive — alternating
   deployment must not block; document the choice).
3. Both zones and all objectives visible; the normal deployment UI works
   unmodified (drag, formation deploy, undo if it exists — do not build
   undo in this task).
4. A visible "PLAN EDITOR" banner/badge so screenshots are unambiguous,
   and an Exit-to-menu control that discards cleanly.
5. The session must reach "all units deployed" without entering the
   battle rounds: after deployment completes, hold in a terminal
   "editor idle" state (PM-5 adds Save; PM-6 adds painting) rather than
   transitioning to round 1.

**Validation gate.**
1. Windowed scenario `sp/pm4_plan_editor_session.json`: from the main menu
   (or a scenario-supported entry), enter the editor with recon_stomps on
   hammer_anvil, `simulate_click` a unit deployment (imitate existing
   deployment-scenario steps — grep scenarios for `COMPOSITE_DEPLOY` or
   deployment clicks, e.g. `377_defender_deploys_first.json`), assert the
   model count on the board increased and phase did not advance to round 1
   after final deployment.
2. `verify_delivery`: no ERROR lines for the whole drive.
3. Screenshot: editor session with banner + a deployed unit.

**Out of scope.** Saving (PM-5), intents (PM-6), editing an existing plan.

**Evidence.** _(fill)_

---

## PM-5 — Deployment recorder: Save as Plan

**Status:** TODO
**Depends:** PM-4, PM-2 (for the round-trip test), PM-1
**Player-facing:** yes — version_history entry required

**Goal.** In the editor session, after deployment is complete, a **Save as
Plan** button serializes what the player just did into a valid
`wh40k_ai_plan` and stores it via PlanManager.

**Context to load.** PM-0 schema, PM-1 PlanManager, PM-4's editor state,
`GameState` unit/model position access (grep how positions are stored —
px), deployment zone + terrain layout data for anchor derivation.

**Implementation requirements.**
1. Serialize: deployment **order as actually deployed** (track it during
   the session), per-model positions converted px→inches, units placed in
   reserves via the normal UI recorded into `reserves` (arrival round
   default 2, editable later — not in this task), keys filled from the
   session config, `author` from a text field.
2. Auto-derive `anchors` per placement (nearest objective id, depth from
   own zone edge in inches, nearest terrain piece id) — recorded only.
3. Save dialog: name + description fields, then `PlanManager.save_plan`;
   surface validator errors/warnings in the dialog (e.g. unit-coverage
   warnings). Success toast shows the file path.
4. `if_going_second` and `earmarks` are left empty by the recorder (PM-6
   adds earmarks); schema allows their absence.
5. **Round-trip proof** (the point of the whole task): a saved plan, fed to
   PM-2's consumption on the same mission/zone/layout/army, reproduces the
   recorded deployment.

**Validation gate.**
1. Windowed scenario `sp/pm5_record_and_save_plan.json`: editor session →
   deploy 2+ units via clicks → click Save as Plan → type a name (scenario
   text-input step; check `_schema.md` for input steps) → assert the file
   exists under `user://ai_plans/` and `PlanValidator` passes it (assert
   via `execute_script`).
2. Headless round-trip test `40k/tests/unit/test_plan_roundtrip.gd`:
   programmatically build a small deployment, serialize with the recorder's
   serializer (factor it as a static function so it is testable headless),
   feed to PM-2, assert positions within 0.5".
3. Screenshot: the save dialog over the completed deployment, and/or the
   success toast.

**Out of scope.** Editing/updating existing plans (delete + re-record is
the v1 story), painter.

**Evidence.** _(fill)_

---

## PM-6 — Intent painter

**Status:** TODO
**Depends:** PM-5, PM-3
**Player-facing:** yes — version_history entry required

**Goal.** After deployment in the editor (or when re-opening a recorded
plan's session — only if trivially available; otherwise same-session only,
documented), the player paints intents: select a unit → pick one of the six
verbs → for `HOLD_OBJECTIVE`, click an objective marker to bind `target`;
for `RESERVE_UNTIL`, pick a round (2/3). Earmarks save into the plan.

**Context to load.** PM-0 verb table, PM-5 save path, existing selection +
overlay machinery: `40k/scripts/AIUnitHighlight.gd`,
`AIMovementPathVisual.gd`, `AIThoughtLinkVisual.gd` (reuse the drawing
style), unit selection handling in the deployment/board controller (grep
how clicking a unit selects it), `MissionManager` objective markers.

**Implementation requirements.**
1. A compact painter panel (visible only in editor sessions, after
   deployment): unit list or click-to-select on board; six verb buttons;
   current earmark shown per unit; clear-earmark.
2. Visual overlay per earmarked unit: a badge with the verb (abbreviated)
   and, for HOLD/PUSH, a line/arrow to the bound objective — reusing the
   existing overlay visual conventions.
3. Earmarks persist into the saved plan (PM-5's dialog saves both) and
   reload if the painter reopens within the session.
4. Vocabulary is closed: exactly the six verbs, no free text.

**Validation gate.**
1. Windowed scenario `sp/pm6_paint_intents.json`: editor session with ≥2
   deployed units → select unit → click HOLD_OBJECTIVE → click an
   objective → assert overlay node exists and the saved plan JSON contains
   the earmark (assert file content via `execute_script`).
2. `verify_delivery` clean.
3. Screenshot: board with ≥2 visible earmark badges/arrows — this is the
   signature image of the feature.

**Out of scope.** New verbs, per-verb parameters beyond target/round,
mid-battle repainting.

**Evidence.** _(fill)_

---

## PM-7 — Plan browser + assigning plans to games

**Status:** TODO
**Depends:** PM-1, PM-2
**Player-facing:** yes — version_history entry required

**Goal.** Players can see their plans and make the AI use one: a plan
browser (list, inspect keys/coverage, delete, import/export via file
dialog) and, in the main-menu game setup, an optional per-AI-seat "AI
Plan" dropdown listing plans matching the currently selected army + map
(plus "Auto (best match)" and "None").

**Context to load.** `MainMenu.gd` (how difficulty/AI dropdowns are built
per seat — imitate), PM-1 `list_plans`/`find_plan_for`,
`ProfileManager`-style file dialogs if any exist (grep for FileDialog
usage in scripts/).

**Implementation requirements.**
1. Browser reachable from the main menu (modal or section): rows show
   name, army_file, zone, layout, validation status (green/warn/error via
   PlanValidator), author. Delete with confirm; Export copies JSON to a
   user-chosen path; Import validates before accepting.
2. Game-setup dropdown per AI seat, repopulating when army/deployment
   selection changes; selection is passed into the session and applied via
   `AIDecisionMaker.set_player_plan` (PM-2). "Auto" = `find_plan_for` at
   game start; "None" forces formula behavior.
3. The active plan (name + source) is logged at game start and shown in
   the AI turn summary (one line — grep `AITurnSummaryPanel`).

**Validation gate.**
1. Windowed scenario `sp/pm7_assign_plan_from_menu.json`: from main menu,
   select recon_stomps + hammer_anvil + AI seat, open the plan dropdown,
   pick the fixture/recorded plan, start, let deployment run, assert
   `plan:` deployment records (as PM-2) — proving the menu path reaches the
   AI.
2. Windowed scenario `sp/pm7_plan_browser.json`: open browser, assert the
   fixture plans list with correct validation badges; delete a copy;
   assert file gone.
3. Screenshots: browser; setup screen with the plan dropdown populated.

**Out of scope.** In-browser editing, cloud sharing.

**Evidence.** _(fill)_

---

## PM-8 — Simulator backend: plan vs plan, N seeded games

**Status:** TODO
**Depends:** PM-2 (PM-3 recommended), PM-1
**Player-facing:** partially (backend of a player feature; version_history
comes with PM-9)

**Goal.** A `PlanSimulator` that runs N AI-vs-AI games — same mission/map/
armies, player 1 using plan A, player 2 using plan B (either may be
"None") — sequentially in the running session at maximum AI speed, seeded
`seed_base + i`, with progress signals and cancel. Results collected to a
JSON summary + per-game `AIGameRecord`s.

**Context to load.** `40k/autoloads/AIBenchmarkRunner.gd` end to end —
it already solves in-scene AI-vs-AI games with seeds, stall caps, per-game
result JSON, and record export; your job is to REUSE it (extend/parametrize)
rather than re-implement. Also `run_ai_benchmark.sh` env contract,
`AIDifficultyConfig` (sim runs at HARD by default — the difficulty where
planning is on), AI speed / time_scale handling (note: the lab measured
time_scale barely moves wall clock; do not promise speed you haven't
measured).

**Implementation requirements.**
1. API: `PlanSimulator.start({mission, zone_id, layout_id, army1, army2,
   plan1, plan2, games, seed_base, difficulty})`, signals
   `game_finished(i, result)`, `run_finished(summary)`, `cancelled`.
   Mirror-match support (same army both sides, plan A vs plan B) is the
   headline case — make sure army identity per seat supports it (the lab's
   mirror fixtures prove the engine can).
2. Between games: full state reset through the same pathway
   AIBenchmarkRunner uses (fixture reload or re-apply armies +
   deployment). No leakage — assert unit counts equal at each game start.
3. Per-game result rows: seed, winner, vp per player, margin, rounds,
   plan adherence counts (from PM-2's `source` records), wall seconds.
   Summary: wins A/B/draws, mean margin ± sd. Write to
   `user://plan_sim_results/<timestamp>.json` (and remember: no
   `Date.now`-style non-determinism inside any workflow-scripted context —
   plain runtime code may timestamp normally).
4. Honest cost display inputs: measure one game's wall time on first run
   and expose it so PM-9 can show an ETA.
5. Cancel must leave the session in a state from which returning to the
   main menu works (scenario-verified in PM-9).

**Validation gate.**
1. Headless: drive `PlanSimulator` for 2 games (small/custodes armies for
   speed) via a `--headless` script or a GUT test; assert 2 result rows,
   summary math correct, differing seeds, state reset (equal unit counts
   at both game starts), zero stalls.
2. Same 2-game run twice at the same seed_base ⇒ identical winners and
   margins (determinism).
3. Log check: no ERROR lines (`read_debug_log` levels).

**Out of scope.** UI (PM-9), parallelism/subprocesses, statistics beyond
mean ± sd.

**Evidence.** _(fill)_

---

## PM-9 — Simulator UI

**Status:** TODO
**Depends:** PM-8, PM-7
**Player-facing:** yes — version_history entry required (cover PM-8 too)

**Goal.** "Battle Simulator" screen from the main menu: pick mission/map,
army/plan per side (reuse PM-7's pickers), number of games (1–20), Run.
Progress bar with per-game ticks + ETA from PM-8's measured game time +
Cancel. Results table (game #, seed, winner, VP A–B) + summary line
("Plan A 4 – 1 Plan B, mean margin +7.2"), a button to open the existing
turn-summary/replay for a finished game if the existing panels support
loading a record (if they don't, link the record file path instead —
do not build a replay system in this task), and Export results.

**Context to load.** PM-8 API, PM-7 pickers, `AITurnSummaryPanel.gd` /
`AITurnReplayPanel.gd` / `AIGameRecord.gd` (what "open a game" can mean
today), MainMenu button conventions.

**Validation gate.**
1. Windowed scenario `sp/pm9_simulator_run.json`: open simulator, configure
   a 2-game mirror run with a fixture plan vs None, Run, wait for
   completion (scenario wait/poll steps — check `_schema.md`; use generous
   timeout, small armies), assert results table has 2 rows and the summary
   node text matches the backend JSON; Cancel path: start a run, cancel,
   assert return to menu works.
2. `verify_delivery` clean after the run.
3. Screenshots: configured setup screen; completed results table (the
   second is the feature's signature image).

**Out of scope.** Charts, Elo, parallel execution.

**Evidence.** _(fill)_

---

## PM-10 — First real content: recon_stomps plan + lab verdict

**Status:** TODO
**Depends:** PM-2, PM-3 (PM-5 helpful for authoring)
**Player-facing:** yes (shipped plan) — version_history entry required

**Goal.** Author and ship the first two real plans and measure them:
`recon_stomps` on `hammer_anvil` (the owner has a plan in mind — author a
strong-practice one: screens forward vs deep strike, Gretchin on home
objectives, Stormboyz reserved, transports+cargo pushing mid together,
if_going_second pull-back; mark the plan file with
`"author": "claude-draft — owner review wanted"`), and `custodes_lions` on
one deployment. Then run the lab: plan vs formula.

**Context to load.** PM-0 format, the army JSONs, the deployment zone +
layout data, `40k/tests/run_ai_benchmark.sh` + predeploy fixtures
(`mirror_orks_2000_predeploy` etc. — note the Ork fixture's cost, ~8-16
min/game; budget accordingly), `tools/ai_lab/run_paired.py` (the paired
side-swapped evaluator) and `.llm/ai-overhaul-progress.md` §"deployment
coverage" (why predeploy measurement costs 3-4× — set expectations in the
report honestly).

**Deliverables.**
1. Two shipped plans under `40k/data/ai_plans/` passing PlanValidator with
   zero warnings against their armies.
2. A paired A/B: ≥6 paired seeds (12 games) per matchup, plan-active vs
   plans-disabled, on the matching predeploy fixture, via the existing
   paired tooling (BENCH env or run_paired — reuse, don't reinvent).
   Report E ± se. Given deployment's variance, a null is a possible
   honest outcome — the gate is (a) zero stalls/errors, (b) plan adherence
   ≥90% of covered units (from PM-2 records), (c) E not significantly
   NEGATIVE. A visible screenshot comparison of plan vs formula deployment
   is part of the deliverable regardless of E.
3. Write the result to `40k/tests/bench_baselines/<date>_plan_vs_formula.md`
   in the style of the neighbouring reports (numbers, seeds, fixture,
   honest reading).

**Validation gate.** The bench_baselines report exists with real numbers;
both plans validate; adherence metric present; screenshots of both
deployments in the report/TLDR.

**Out of scope.** Tuning earmark bonus params (leave at defaults; note as
follow-up), more factions.

**Evidence.** _(fill)_

---

## PM-11 — Docs, release notes, coherence pass

**Status:** TODO
**Depends:** all previous
**Player-facing:** yes — one consolidated version_history entry if any gap

**Goal.** Make the feature discoverable and the docs truthful.

**Deliverables.**
1. `40k/docs/PLAN_FORMAT.md` final pass: verb table, matching rules,
   fallback semantics, TRADE's v1 status, recorder/painter/simulator
   walkthrough with the PM-5/6/9 screenshots.
2. README / player-facing help: a short "AI Plans" section (how to record,
   paint, simulate, assign).
3. `40k/data/version_history.json`: verify every player-facing PM task
   added its entry; add a consolidated "AI Plans" headline entry for the
   release if the individual entries are fragmentary.
4. Coherence checks: plan features OFF cause zero behavior change
   (run one A/A: plans_disabled arm vs pre-PM baseline commit if
   available, or determinism vs recorded pre-change trajectory — document
   which); Plan Editor and Simulator both survive entry→exit→re-entry
   (windowed scenario `sp/pm11_reentry.json`); `--headless --import` clean;
   full new-scenario set green in one batch run.
5. Sweep for stray debug `print` spam introduced by PM tasks (keep
   file-logged debug, per project rules).

**Validation gate.** All PM scenarios green in one `run_scenario.sh` batch
(list ids + output in Evidence); docs committed; version history renders in
the main menu (screenshot).

**Evidence.** _(fill)_

---

## Deferred (explicitly NOT in this workstream — add tasks only when reached)

- Anchor-based generalization of plans across terrain layouts.
- Archetype-level plans / role-classifier improvements.
- Per-unit parameter overrides (real TRADE semantics).
- LLM-drafted plans pipeline (offline; plans are already the right
  artifact — this is authoring tooling, not engine work).
- Plan editing UI (v1 story: delete + re-record).
- Simulator parallelism or statistics beyond mean ± sd.
- Community sharing beyond file import/export.
