# Testing methodology — gameplay features

Patterns and gotchas for verifying gameplay features in this Godot 4.6 codebase. Distilled from the 2026-05 stratagem audit.

## TL;DR

For any test that requires specific unit positioning, an in-progress phase, or trigger-emission code paths:

1. **Build a save fixture.** Position units in the desired pre-trigger state, then `SaveLoadManager.save_game("name")`. Commit the `.w40ksave` to `tests/saves/`.
2. **Reload into a live scene.** `SaveLoadManager.load_game(name)` + set `meta.from_save = true` + `change_scene_to_file("res://scenes/Main.tscn")`. All three steps required.
3. **Drive actions through real handlers.** `phase_mgr.transition_to_phase(N)` then `phase.execute_action({...})` — same path the UI uses.
4. **Assert on the response.** Each phase action handler returns a dict; check `trigger_*=true`, eligible_units, and the phase's `awaiting_*` fields.
5. **For visual proof**, crop the screenshot to the relevant region and/or modulate the unit-of-interest token to a vivid color.

Reference implementation: `test_co_pretrigger.gd`, `test_hi_pretrigger.gd`, `test_ri_pretrigger.gd` plus the runner `run_pretrigger_tests.sh`.

---

## Why not just mutate state directly?

`execute_script` (or any direct `GameState.state.units[X].position.merge({...})`) updates the data but doesn't fire the diff/signal pipeline that the rendering layer subscribes to.

- `TokenLayer` (`/root/Main/BoardRoot/TokenLayer`) listens for state-change signals to reposition tokens
- Direct mutation of the underlying dict skips the signal entirely
- Result: data layer says units are in engagement, board still shows them at original deployment positions

Tests that operate purely on `GameState.state` will pass while UI rendering and signal-wired controllers remain unverified. This is fine for unit-testing pure logic but it is **not** end-to-end verification.

The fixture-save pattern works because `SaveLoadManager.save_game` serializes from `GameState`, and on reload the new `Main` scene's `_ready()` reads positions from the saved file — so `TokenLayer.instantiate_tokens()` (or equivalent) renders at the saved positions.

---

## Loading a fixture into the live scene

The MainMenu's "Load Game" button does this in three steps (`scripts/MainMenu.gd` around line 946):

```gdscript
SaveLoadManager.load_game(save_file, owner_id)
GameState.state.meta["from_save"] = true   # critical — see below
get_tree().change_scene_to_file("res://scenes/Main.tscn")
```

**The `from_save` flag is required.** `Main._ready()` checks it and either restores the saved phase state or reinitializes a fresh game. Skipping the flag silently dumps your loaded state.

For tests, do these in `_run_tests()` (after autoloads' `_ready` has fired — see headless tests below).

---

## Screenshot capture

**Direct viewport call:**

```gdscript
get_viewport().get_texture().get_image().save_png(absolute_path)
```

This is more reliable than the addons/godot_mcp `capture_screenshot` tool, which awaits `RenderingServer.frame_post_draw` and times out (30s default) when the engine isn't drawing.

**macOS gotcha (verified):** when the Godot window is backgrounded, macOS suspends rendering for that window. `viewport.get_texture()` then returns the last-rendered frame, which can be **md5-identical to a frame from minutes earlier**. Before any screenshot:

```bash
osascript -e 'tell application "Godot" to activate'
```

Wait ~2 seconds after activate before capturing — the render thread needs at least one frame to refresh. Verified during the 2026-05 audit: same `image.save_png()` returned the SAME bytes (verified by md5) when the window was backgrounded. Activating the window made the next call return a fresh frame.

**Cropping:**

```gdscript
get_viewport().get_texture().get_image().get_region(Rect2i(x, y, w, h)).save_png(path)
```

Region values are in **viewport pixel coordinates**, not game-world coordinates. With a default 2560×1600 game window and a board ~1760 game-units wide, individual tokens render at ~30 screen-pixels — too small to identify by eye in full-board screenshots. Crop or zoom in.

**Modulate-highlighting (if team colors aren't distinct enough):**

```gdscript
# Tokens are children of /root/Main/BoardRoot/TokenLayer
# Each has unit_id and model_id metadata
get_tree().get_root().get_node("Main/BoardRoot/TokenLayer").get_child(N).set("modulate", Color(1.0, 0.0, 0.0, 1.0))
```

To find a specific unit's token, iterate `TokenLayer.get_children()` and match `get_meta("unit_id")` against the unit_id you're looking for.

---

## Headless GDScript regression tests

Tests extend `SceneTree` and run via:

```bash
godot --headless --path . -s tests/test_<name>.gd
```

Exit code is 0 on success, 1 on failure (set via `quit(N)`).

### Critical timing gotcha

**`SceneTree._init()` runs BEFORE autoloads' `_ready` fires.** Autoload setup (e.g., `PhaseManager.register_phase_classes()`) hasn't happened yet, so calls into them silently no-op or fail.

Defer the test body until autoloads are ready:

```gdscript
extends SceneTree

func _init():
    # Belt-and-suspenders: connect to root's ready signal, plus a timer fallback.
    root.connect("ready", Callable(self, "_run_tests"))
    create_timer(0.1).timeout.connect(_run_tests)

func _run_tests():
    if passed > 0 or failed > 0:
        return  # guard against double-firing

    # Now safe to use autoloads:
    var save_mgr = root.get_node("SaveLoadManager")
    var phase_mgr = root.get_node("PhaseManager")
    # ...
```

`await process_frame` inside `_init` does NOT work as expected — control returns to the engine before assertions run, so "Result: 0 passed, 0 failed" prints first, then the actual `PASS:` lines print after.

### Test pattern

```gdscript
var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
    if cond:
        passed += 1
        print("  PASS: %s" % label)
    else:
        failed += 1
        print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _run_tests():
    # 1) Load fixture
    var save_mgr = root.get_node("SaveLoadManager")
    var phase_mgr = root.get_node("PhaseManager")
    var game_state = root.get_node("GameState")

    _check("Fixture load", save_mgr.load_game("co_pretrigger"))
    game_state.state["meta"]["from_save"] = true

    # 2) Verify saved state survived
    _check("Phase = FIGHT (10)", game_state.state["meta"].get("phase") == 10)
    # ... more state assertions

    # 3) Instantiate the phase
    phase_mgr.transition_to_phase(10)
    var phase = phase_mgr.get_current_phase_instance()
    _check("FightPhase instance present",
        phase != null and phase.get_script().resource_path.ends_with("FightPhase.gd"))
    if phase == null:
        _finish()
        return

    # 4) Drive actions
    phase.execute_action({"type": "SELECT_FIGHTER", "unit_id": "U_WARBOSS_B"})
    var result = phase.execute_action({"type": "CONSOLIDATE", ...})

    # 5) Assert on the response
    _check("Trigger fired", result.get("trigger_counter_offensive") == true)
    _check("Phase awaiting flag set", phase.awaiting_counter_offensive == true)

    _finish()

func _finish():
    print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
    quit(1 if failed > 0 else 0)
```

### Phase enum reference

`GameStateData.Phase` enum order (use these integer values in `transition_to_phase`):

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

---

## MCP bridge — `per_model_paths` Vector2 conversion

The MCP bridge's `_normalize_action_positions` (in `addons/godot_mcp/handlers/wh40k_handlers.gd`) coerces position-shaped JSON fields to `Vector2` before passing actions to phase handlers. Position dicts (`{x: 491, y: 100}`) and arrays (`[491, 100]`) both work.

This applies recursively to `payload.per_model_paths` (used by `APPLY_CHARGE_MOVE`, `APPLY_HEROIC_INTERVENTION_MOVE`, `STAGE_MODEL_MOVE`, etc.). Without this coercion, `Measurement.distance_polyline_px` silently sums non-Vector2 elements as 0 and these multi-model move actions silently no-op while their validators report success.

If you write new actions with nested position fields, extend `_normalize_action_positions` accordingly.

---

## Anti-patterns

- **Claiming end-to-end coverage from data-layer-only tests.** If you only mutated `GameState.state` and inspected the response, you tested logic — not UI/visual rendering.
- **Relying on the MCP `capture_screenshot` tool when the window is backgrounded.** It will hang. Use the direct `viewport.get_texture()` call.
- **Using `await process_frame` inside `SceneTree._init`.** Control returns to the engine before your assertions run; output is out of order.
- **Skipping the `from_save = true` flag.** `Main._ready()` will reinitialize a fresh game and your loaded state vanishes.
- **Trusting that the Godot window is visible.** macOS may have suspended rendering. Always `osascript activate` before screenshot if visual verification matters.

---

## Reference

- Fixtures: `tests/saves/co_pretrigger.w40ksave`, `hi_pretrigger.w40ksave`, `ri_pretrigger.w40ksave`
- Tests: `tests/test_co_pretrigger.gd`, `test_hi_pretrigger.gd`, `test_ri_pretrigger.gd`
- Runner: `tests/run_pretrigger_tests.sh`
- Save generator pattern: `tests/helpers/TestSaveGenerator.gd` + `tests/run_save_generator.gd`
- Audit narrative: `test_results/audit_2026_05/AUDIT_REPORT.md`

---

## Design-guidelines visual tasks (T01–T45)

Tasks T01 through T45 (see `.llm/todo.md`) implement
`docs/design_guidelines_2d_topdown.md`. They use a stricter scenario format
that requires every claim to be falsifiable — *no* screenshot-only acceptance,
*no* pin-tests masquerading as validation. Three Tier-A step types added in
T02 enforce this.

### Three new step types

1. **`execute_script`** — evaluate a GDScript expression with access to every
   autoload by name (plus `main` = current_scene). Supports `equals`,
   `not_equals`, `exists`, `expect_min`, `expect_max`.
   ```json
   { "act": "execute_script",
     "script": "MovementController.current_drag_segments[-1].color_slot",
     "equals": "MARGINAL_YELLOW" }
   ```
   Use this to read state the feature exposes — every task in `.llm/todo.md`
   declares the property/method it adds for this purpose. If a task can't be
   asserted, the task is rejected — design the change so the relevant state
   IS observable.

2. **`pixel_diff`** — compare two screenshots captured earlier in the same
   scenario, optionally clipped to a named region declared at the scenario
   top level. Requires `expect_min_pct` or `expect_max_pct` — a diff without
   a bound is a screenshot in disguise and is banned.
   ```json
   { "act": "pixel_diff",
     "before": "T03_at_M", "after": "T03_at_advance",
     "region": "drag_path", "expect_min_pct": 3.0 }
   ```

3. **`expect_baseline_unchanged`** — sanity-check that
   `tests/scenarios/visual/_baseline.json` is well-formed. The cross-scenario
   regression check (passing-count vs baseline.count) lives in
   `run_scenarios.sh` because it needs cross-scenario visibility.

See `tests/scenarios/visual/_schema.md` for the full reference and
`tests/scenarios/visual/_template.json` for the copy-paste starting point.

### Running

```bash
# Just the visual suite
bash 40k/tests/run_scenarios.sh --visual

# Single task
bash 40k/tests/run_scenarios.sh tests/scenarios/visual/T03_drag_ruler.json
```

Exit codes for visual runs:
- 0: all pass
- 1: assertion failure
- 2: infra error
- **3: regression — passing count fell below `_baseline.json.count`**

When any `visual/T##_*.json` ran in the batch, screenshots and the per-scenario
result JSON are copied to `40k/test_results/design_guidelines/T##/` for stable
review locations.

### Unit-testing the pixel-diff helper

The math in `tests/tools/pixel_diff.gd` has its own headless self-test:

```bash
godot --headless --path 40k --script tests/tools/pixel_diff_unit_test.gd
```

Exercises identical-images = 0%, black-vs-white > 95%, region clipping, and
error paths. Run before changing the diff implementation.

### Banned anti-patterns (per the playbook)

- Screenshot-only acceptance.
- `pixel_diff` without an `expect_*_pct` bound.
- "Node exists" / "child count > N" without a paired property read of the
  thing that actually controls the pixel.
- Subjective adjectives in Tier A (`readable`, `smooth`, `performant`).
- Lowering `_baseline.json.count` to make a failing task green.

The playbook
(`docs/design_guidelines_implementation_plan.md`) is the canonical reference.
