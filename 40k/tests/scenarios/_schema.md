# Scenario file format

A scenario describes a player-driven test: a save fixture to load, an optional
RNG seed for deterministic dice, and an ordered list of steps that simulate
player input or assert against the game state. Scenarios live under
`40k/tests/scenarios/sp/` (single-player) or `40k/tests/scenarios/mp/`
(multi-peer) and are committed to the repo.

The runner is `40k/autoloads/ScenarioRunner.gd` (autoload, activates when
`--scenario-file=PATH` is on the cmdline). Run via:

```bash
bash 40k/tests/run_scenario.sh tests/scenarios/sp/<id>.json
```

## Top-level shape

```json
{
  "id": "co_offer_after_charge",
  "covers": ["fight.stratagem.counter_offensive"],
  "fixture": "co_pretrigger.w40ksave",
  "rng_seed": 42,
  "transition_to_phase": 10,
  "steps": [ ... ],
  "multiplayer": false,
  "description": "Optional human-readable summary"
}
```

| Field | Required | Type | Notes |
|---|---|---|---|
| `id` | yes | string | Unique. Used as filename and in coverage.json. |
| `covers` | yes | string[] | Coverage tile tags, e.g. `"fight.stratagem.counter_offensive"`. |
| `fixture` | no | string | Save fixture name (without `.w40ksave`). Loaded from `40k/saves/` or `40k/tests/saves/` via `SaveLoadManager.load_game()`. |
| `rng_seed` | no | int | If present and ≥0, sets `RulesEngine.RNGService.test_mode_seed`. -1 disables. |
| `transition_to_phase` | no | int | After fixture load + scene swap, drive `PhaseManager.transition_to_phase(N)`. See enum below. |
| `steps` | yes | array | Ordered list of step objects. |
| `multiplayer` | no | bool | If true, requires `peers: { host: { steps }, client: { steps } }` instead of top-level `steps`. |

## Phase enum (use these values in `transition_to_phase`)

| Phase | Value |
|---|---|
| FORMATIONS | 0 |
| DEPLOYMENT | 1 |
| REDEPLOYMENT | 2 |
| ROLL_OFF | 3 |
| SCOUT | 4 |
| SCOUT_MOVES | 5 |
| COMMAND | 6 |
| MOVEMENT | 7 |
| SHOOTING | 8 |
| CHARGE | 9 |
| FIGHT | 10 |
| SCORING | 11 |
| MORALE | 12 |

## Step types

Each step is a dict with an `act` field plus act-specific keys.

### Programmatic / setup

- `wait_seconds`: pause N seconds
  ```json
  { "act": "wait_seconds", "seconds": 0.5 }
  ```

- `wait_frames`: pause N rendered frames
  ```json
  { "act": "wait_frames", "frames": 3 }
  ```

- `wait_for_tweens`: block until all SceneTree-managed Tweens finish
  (or `timeout_s` elapses, default 10s). Use between rapid
  `dispatch_action` steps when the per-step screenshot would otherwise
  capture mid-tween state (camera pans, token reposition, dialog open).
  Pass records `tween_clear_at` (seconds elapsed before clear) on
  success. Fail is non-fatal but logged.
  ```json
  { "act": "wait_for_tweens", "timeout_s": 5.0 }
  ```

- `dispatch_action`: drive a phase action through the current phase instance.
  Use sparingly — bypasses UI. Prefer `click_unit` / `click_button` for player
  paths. Result captured as `last_action_result` for downstream
  `expect_action_result`.
  ```json
  { "act": "dispatch_action", "action": { "type": "SELECT_FIGHTER", "unit_id": "U_WARBOSS_B" } }
  ```

- `screenshot`: save PNG to `user://test_results/scenarios/<scenario_id>_<label>.png`
  ```json
  { "act": "screenshot", "label": "01_loaded" }
  { "act": "screenshot", "label": "02_dialog", "region": [200, 300, 400, 400] }
  ```

### UI-driving

- `click_unit`: locate the token for `unit_id` in `/root/Main/BoardRoot/TokenLayer`
  and dispatch a real mouse-button event at its global position.
  ```json
  { "act": "click_unit", "unit_id": "U_WARBOSS_B" }
  ```

- `click_node`: locate a node by NodePath and dispatch a real click at its
  centre. Buttons should also accept an `emit_pressed: true` shortcut that
  emits the `pressed` signal directly.
  ```json
  { "act": "click_node", "node": "/root/Main/UI/ChargeButton" }
  { "act": "click_node", "node": "/root/Main/UI/CO/AcceptButton", "emit_pressed": true }
  ```

- `click_item_list`: real-mouse-click one row of an `ItemList` (by item
  `index`), warping the cursor to the row's rect centre — so the list's own
  input handling (selection replace, Ctrl+Click toggle, deferred single-select)
  runs exactly as for a player. `ctrl: true` holds Ctrl through the click
  (multi-select toggle). `empty: true` clicks the free strip below the last
  row instead (e.g. to assert empty-click-clears-selection).
  ```json
  { "act": "click_item_list", "node": "/root/Main/.../ChargeTargetList", "index": 1 }
  { "act": "click_item_list", "node": "/root/Main/.../ChargeTargetList", "index": 0, "ctrl": true }
  { "act": "click_item_list", "node": "/root/Main/.../ChargeTargetList", "empty": true }
  ```

- `click_board_at`: click an arbitrary **board/world** position (`x`/`y` in
  board px — the coordinate system used by deployment zones and model
  positions). The world point is projected to screen via the live canvas
  transform, the cursor is warped there, and a real mouse click is injected.
  Use for model placement, scout-move drops, or any click on empty board where
  there is no node/token to target (`click_node`/`click_unit` need an existing
  node). Board input handlers read the live cursor, so the warp — also applied
  by `click_unit`/`click_node`/`_send_click` — is what makes the placement land.
  ```json
  { "act": "click_board_at", "x": 170.0, "y": 170.0 }
  ```

- `drag_board`: drag from one **board/world** position to another with real
  input events — warp + LMB press at `from`, interpolated
  `InputEventMouseMotion` steps (default 8, override with `steps`), LMB
  release at `to`. This is the player path for drag-to-move flows (fight-phase
  pile-in/consolidate model movement); no controller state is poked.
  Coordinates are board px, projected like `click_board_at`.
  ```json
  { "act": "drag_board", "from_x": 200, "from_y": 100, "to_x": 255, "to_y": 170 }
  ```

- `hover_unit`: locate the token for `unit_id` (like `click_unit`), warp the
  cursor there and dispatch a real buttonless `InputEventMouseMotion`. The
  player path for hover-driven UI (board token tooltip, hover forecasts).
  ```json
  { "act": "hover_unit", "unit_id": "U_WARBOSS_B" }
  ```

- `hover_board_at`: like `hover_unit` but for an arbitrary **board/world**
  position (board px, projected like `click_board_at`). Use to hover empty
  board — e.g. to assert a tooltip hides.
  ```json
  { "act": "hover_board_at", "x": 880.0, "y": 1200.0 }
  ```

- `hover_node`: warp the cursor to the centre of a Control (resolved by
  NodePath) and dispatch a real buttonless `InputEventMouseMotion`. The player
  path for hover-driven menu/panel UI — e.g. positioning the cursor over a
  ScrollContainer before a `simulate_wheel`.
  ```json
  { "act": "hover_node", "node": "/root/MainMenu/ScrollContainer" }
  ```

- `simulate_key`: dispatch a keypress.
  ```json
  { "act": "simulate_key", "keycode": "KEY_ESCAPE" }
  ```

- `simulate_joy_button`: dispatch a joypad button press+release through the
  OS-event pipeline — drives InputMap actions, `ui_*` focus navigation and
  InputDeviceManager device detection like a real pad. `button_index` uses
  the JoyButton enum ints: 0=A 1=B 2=X 3=Y 4=Back(View) 6=Start(Menu) 9=LB
  10=RB 11–14=D-pad up/down/left/right. Optional `device` (default 0).
  ```json
  { "act": "simulate_joy_button", "button_index": 12 }
  ```

- `simulate_joy_axis`: push a joypad axis to `value`, hold it for `hold_s`
  seconds (default 0.3), then return it to neutral unless
  `"auto_release": false`. While held, the axis feeds action strengths, so
  per-frame consumers (pad camera pan, trigger zoom) integrate over the
  hold. `axis` uses the JoyAxis enum ints: 0/1 left stick, 2/3 right stick,
  4/5 triggers (0..1). Optional `device` (default 0).
  ```json
  { "act": "simulate_joy_axis", "axis": 2, "value": 1.0, "hold_s": 0.7 }
  ```
  `simulate_joy_button` also accepts `"state"`: `"tap"` (default,
  press+release), `"press"` (hold — e.g. start a virtual-cursor drag), or
  `"release"` (end a held press).

- `pad_cursor_glide`: drive the M1 virtual cursor to a target through the
  same per-frame move/warp/motion-synthesis pipeline the left stick uses
  (only the steering is deterministic). If the target starts off-screen the
  cursor's edge-push pans the camera, so the act re-resolves the target and
  re-glides until the cursor rests on it. Target one of: `unit_id` (token),
  `node` (a Control's NodePath), `button_text` (first visible enabled
  Button with that exact text — for procedurally-built panels with no
  stable path), or `x`/`y` board px (`"space": "screen"` for raw screen
  px). Combine with `simulate_joy_button` 0 for clicks and
  `state: press/release` pairs for drags.
  ```json
  { "act": "pad_cursor_glide", "unit_id": "U_BLADE_CHAMPION_A" }
  { "act": "pad_cursor_glide", "button_text": "Confirm Move" }
  { "act": "pad_cursor_glide", "x": 120.0, "y": 220.0 }
  ```

### State asserts

- `execute_script`: evaluate GDScript and (optionally) compare the result via
  `equals` / `not_equals` / `exists` / `expect_min` / `expect_max`. Two modes:
  - **Expression mode** (default): a single expression. Bound identifiers:
    every child of `/root` by node name (autoloads AND root-level dialogs,
    e.g. `WeaponOrderDialog`), engine singletons, `main` (the live battle
    scene), `tree` (the SceneTree) and `node` (`/root`).
  - **Statement mode** (`"multiline": true` — explicit, never auto-detected):
    the snippet is compiled into a throwaway GDScript so `var` / `if` / `for`
    / `return` work. It runs as `_run(node, tree)` — `node` is `/root` (or
    the node at the optional `node` step key), `tree` is the SceneTree;
    autoloads are reachable by global name, but root-level dialogs must be
    fetched via `tree.root.get_node_or_null(...)`. `return <value>` feeds the
    expectation.
  ```json
  { "act": "execute_script", "script": "WeaponOrderDialog.weapon_list_container.get_child_count()", "equals": 1 }
  { "act": "execute_script", "script": "var d=tree.root.get_node_or_null(\"WeaponOrderDialog\")\nreturn d.is_resolving", "multiline": true, "equals": true }
  ```

- `expect_state`: assert against `GameState.state` via dot-separated path.
  ```json
  { "act": "expect_state", "path": "units.U_CUSTODIAN_GUARD_B.flags.fights_first", "equals": true }
  ```

- `expect_cp`: shortcut for `players.<N>.cp`.
  ```json
  { "act": "expect_cp", "player": 1, "equals": 2 }
  { "act": "expect_cp", "player": 1, "delta_from_start": -2 }
  ```

- `expect_action_result`: assert against the dict returned by the most-recent
  `dispatch_action` step.
  ```json
  { "act": "expect_action_result", "path": "trigger_counter_offensive", "equals": true }
  ```

- `expect_phase`: assert current phase number.
  ```json
  { "act": "expect_phase", "equals": 10 }
  ```

### UI asserts

- `expect_node_visible`: assert a node exists and `is_visible_in_tree()` is true.
  Polls until `timeout_s` (default 2.0).
  ```json
  { "act": "expect_node_visible", "node": "/root/Main/UI/CounterOffensiveDialog", "timeout_s": 2.0 }
  ```

- `expect_node_property`: assert a property of a node.
  ```json
  { "act": "expect_node_property", "node": "/root/Main/UI/CO/AcceptButton", "property": "disabled", "equals": false }
  ```

- `expect_token_visible`: like `expect_node_visible` but resolves a token by
  unit_id instead of NodePath.
  ```json
  { "act": "expect_token_visible", "unit_id": "U_WARBOSS_B" }
  ```

## Output

The runner writes a results file to
`user://test_results/scenarios/<scenario_id>.json`:

```json
{
  "scenario_id": "co_offer_after_charge",
  "passed": 7,
  "failed": 0,
  "steps": [
    { "step": 0, "act": "screenshot", "pass": true, "path": "..." },
    { "step": 1, "act": "click_unit", "pass": true },
    ...
  ]
}
```

On any failure, the runner auto-captures a screenshot to
`user://test_results/scenarios/<scenario_id>_FAIL_step_<n>.png`.

Process exit code: 0 if all asserts pass, 1 otherwise. The `run_scenarios.sh`
runner aggregates exit codes and reports overall pass/fail.

## Multi-peer scenarios

The single-player runner (`ScenarioRunner`) drives one Godot instance
through `simulate_click` / `dispatch_action`. For multi-peer tests
(host + client sync, network broadcast assertions, etc.) we leverage
the existing GUT-based harness:

- Test files live under `40k/tests/integration/test_multiplayer_*.gd`
- The runner spawns two `--test-mode` subprocesses (host + client) and
  drives them via the command-file IPC in `TestModeHandler`
- Run via `bash 40k/tests/run_multiplayer_tests.sh`

**Coverage tile referencing a multi-peer test:**

```json
{
  "id": "multiplayer.deployment.host_to_client_sync",
  "description": "...",
  "scenarios": ["mp:tests/integration/test_multiplayer_deployment.gd"],
  "last_verified_commit": "<sha>",
  "status": "covered"
}
```

The `mp:` prefix tells `check_coverage.py` to look for the file at the
named path rather than expect a JSON scenario id.

CI runs the multi-peer suite as a separate job
(`multipeer-tests` in `.github/workflows/scenarios.yml`). It does NOT
need Xvfb because the multi-peer subprocesses run `--headless` and the
network sync is the unit under test, not the UI rendering.

## Anti-patterns

- **`dispatch_action` for the player-facing trigger.** If a player would have
  to click a button to trigger this, the scenario MUST use `click_button`
  (or equivalent) not `dispatch_action`. Past sessions have closed features
  as "verified" using `dispatch_action` only and the player could not
  actually reach the button. See `CLAUDE.md` feature-validation rule.
- **Skipping screenshots on UI flows.** A screenshot every 2-3 steps catches
  silent visual regressions and gives a human auditor something to check
  when results look ambiguous.
- **Hardcoded global positions.** Use NodePath-relative or unit_id-relative
  resolution; absolute mouse coordinates break when the window is resized
  or the camera scrolls.
