# Gamepad / Steam Deck support — design doc

Status: **Phase 0 landed.** Phases 1–4 are planned. This is a living document; update as decisions change.

Branch: `claude/add-gamepad-support-9nfvP`

## 1. Goal

Make this game playable end-to-end with a gamepad, at a quality level
matching the "Steam Deck Verified" criteria, and have the codebase be
ready to ship on Steam eventually. Existing mouse + keyboard play must
be unaffected; gamepad is *additive*.

Non-goals:

- Replacing the mouse code path with a gamepad-only one.
- Touchscreen support (Deck has a touchscreen but it falls outside the
  current scope).
- Re-designing the board to be tile-based.

## 2. Why a hybrid input model

40k is a **continuous-positioning** game: coherency, engagement range,
charge distance, and line of sight all depend on the exact placement of
each model. We can't collapse position to a discrete grid without
changing what the game *is*.

Pure tile/discrete cycling (XCOM-style) breaks for the same reason
chess-on-controller is easy but Total War-on-controller is not: there is
no finite set of "next valid spots" for a model that's part way through
a 6" move.

Pure virtual-cursor (Tabletop Simulator-style) keeps the mouse mental
model but is slow and imprecise for actions where the game already
*knows* the discrete options — picking which weapon to fire, which
target to shoot, which model in a unit to allocate a wound to.

We adopt a **hybrid** model:

| Action type           | Input model                                    | Examples                                                                                 |
| ---                   | ---                                            | ---                                                                                      |
| **Selection**         | Discrete cycling (D-pad / LB-RB; A confirms)   | Active unit, eligible shooters, weapon Tree, target list, wound allocation, dice prompts |
| **Placement**         | Virtual cursor (right stick + snap-to-anchor)  | Movement drag, charge end position, pile-in, deployment ghost                            |
| **Modal actions**     | Face buttons + radial menu (Y opens radial)    | End phase, undo, advance/fall back, model rotation                                       |
| **Camera**            | Left stick (pan), triggers (zoom), R3 (rotate) | All phases                                                                               |

This mirrors what XCOM 2-on-controller, Wartales, and Total War Warhammer
do under the hood. The Steam Input action sets feature lets us bind the
same hardware button to different actions per game phase without engine
changes.

## 3. Architecture

### 3.1 Input flow today (mouse / keyboard)

```
InputEvent (mouse/key)
  → Node._unhandled_input  (in 12+ phase controllers)
  → controller-internal state machine
  → PhaseManager.execute_action  /  signal emission
```

Each phase controller owns its own input handling (e.g.
`MovementController.gd:1517–1579`). `KeybindingManager` provides a
single source of truth for keyboard shortcuts.

### 3.2 Input flow after the port

```
InputEvent (mouse/key)               InputEvent (joypad)
  ↓                                    ↓
Node._unhandled_input               GamepadInputAdapter (autoload)
  ↓                                    ↓
controller-internal state machine ←── action_pressed("confirm" | "cycle_unit_next" | …)
  ↓                                    stick_moved("right", v)
PhaseManager.execute_action            ↓
                                     VirtualCursor (Node2D over board)
                                       ↓
                                     synthesises InputEventMouseButton /
                                     MouseMotion at the cursor position
                                       ↓
                                     existing mouse path (unchanged)
```

Two patterns coexist:

1. **Semantic actions** (selection, modal, camera) bypass the mouse
   path entirely. Phase controllers subscribe to the new
   `action_pressed` / `action_released` signals and act on them
   directly. Example: `cycle_unit_next` calls the same code path that
   the existing `KEY_TAB` shortcut calls in `ShootingController`.

2. **Cursor-driven actions** (movement drag, charge placement) go
   through `VirtualCursor`, which translates stick motion + trigger
   presses into the same `InputEventMouseButton` events the mouse
   produces today. The drag-preview broadcast in `NetworkManager`,
   the ghost rendering, the rotation overlay — none of them need to
   know the input came from a stick.

This split is what lets us keep the controllers unchanged where it
matters and avoid writing parallel logic.

### 3.3 The `GamepadInputAdapter` autoload (Phase 0)

Lives at `40k/autoloads/GamepadInputAdapter.gd`. Already on `main`.

Responsibilities:

- Detect connected joypads, hot-plug.
- Translate raw `InputEventJoypadButton` into named **actions**.
- Expose stick positions as a pollable `Vector2` (per-frame).
- Gate everything behind an `enabled` flag (off by default).
- Provide a test hook (`set_enabled_for_tests`) for scenario tests.

Default button → action mapping (Xbox/Deck face):

| Button                 | Action               | Notes                                       |
| ---                    | ---                  | ---                                         |
| A                      | `confirm`            | Primary action; left-click equivalent       |
| B                      | `cancel`             | Back out, deselect                          |
| X                      | `context_action`     | Secondary; right-click equivalent           |
| Y                      | `open_radial`        | Opens the per-phase radial menu             |
| LB / RB                | `cycle_unit_prev/next` | Cycles whatever the active list is (units/weapons/targets) |
| L3 (left stick click)  | `snap_cursor_to_unit`  | Quick-snap cursor to current selection      |
| R3 (right stick click) | `toggle_measure`     | Activates measuring tape                    |
| Back                   | `open_menu`          | Pause menu                                  |
| Start                  | `end_phase`          | End current phase                           |
| D-pad ↑↓←→             | `focus_up/down/left/right` | UI focus nav inside Controls          |

When Steam Input is active (Phase 4), this raw mapping is the fallback;
Steam Input action sets override per-phase at the OS layer and the
adapter just sees the *output* actions.

### 3.4 The `VirtualCursor` (Phase 3)

Not yet implemented. Design:

- A `Node2D` parented under `BoardRoot`, drawn as an on-screen ring
  cursor when the active input device is a gamepad.
- Position updated each frame from `GamepadInputAdapter.get_stick("right")`,
  with acceleration curve and per-second-pixels tuned by `SettingsService`.
- Calls `Input.warp_mouse(cursor_pos_in_window)` so the existing mouse
  hover / drag code observes the cursor position as the OS mouse
  position. (This is the standard Godot pattern; see Vortex Basis's
  "Godot: Control mouse with gamepad" writeup.)
- Right-trigger → synthesises `InputEventMouseButton(MOUSE_BUTTON_LEFT)`
  press; release on release. Left-trigger → right-click.
- "Snap anchors": for placement actions, pressing L3 finds the nearest
  significant point (max-range edge, engagement range circle, terrain
  edge, model centre) and warps to it. Each phase controller registers
  the anchors that are valid in its current state via a new
  `register_snap_anchors(positions: Array[Vector2])` method on the
  cursor. **This is the highest-risk piece of the port** — the feel of
  charges and pile-ins lives here.

### 3.5 UI focus navigation (Phase 1)

Every interactive `Control` gets `focus_mode = FOCUS_ALL` and a
`focus_neighbor_*` chain. The dpad-bound `focus_up/down/left/right`
actions drive Godot's built-in `gui_focus_*` accept-event flow, so
this stays standard-library territory.

A new lightweight `ControllerGlyph` scene shows a button glyph next to
focused affordances when the active input device is a gamepad. Glyph
art swaps between Xbox / PlayStation / Steam Deck on the fly based on
`Input.get_joy_name(0)` heuristics, until Phase 4 swaps it for the
Steam Input API which provides this directly.

### 3.6 Active-device tracking

A small `InputDeviceTracker` (can live inside `GamepadInputAdapter`
for now) emits `device_changed(kind: "mouse" | "gamepad")` whenever
the user actually uses one or the other. The cursor is hidden /
shown, glyphs swap, hover highlights toggle, all from this signal.
Steam Deck users typically never touch the mouse, but desktop users
with a controller plugged in absolutely will swap mid-session.

## 4. Test strategy

The project gate (`CLAUDE.md`) requires windowed scenarios for any
player-facing behaviour. The runner already injects mouse + keyboard
events via `Input.parse_input_event`. Phase 0 added the same path for
joypad events.

**New scenario step types** (`ScenarioRunner.gd`):

```json
{ "act": "set_gamepad_enabled", "enabled": true }
{ "act": "simulate_joy_button", "button": "JOY_BUTTON_A", "device": 0 }
{ "act": "simulate_joy_motion", "axis": "JOY_AXIS_RIGHT_X",
  "value": 0.9, "device": 0, "duration_s": 0.2 }
```

**Test plan per phase**:

- Phase 1 (menus): scenario opens main menu, dpad-navigates to "New
  Game", presses A, asserts new game started. Same for save/load,
  lobby, in-game pause.
- Phase 2 (selection): per-phase scenarios that cycle the unit list,
  weapon tree, and target list via LB/RB and confirm via A, asserting
  the same `GameState` outcomes as the existing mouse scenarios
  produce.
- Phase 3 (placement): scenarios that drive a virtual-cursor model
  drag for movement, charge, and deployment. Asserts model position
  via `expect_state` against the same coordinates the mouse scenarios
  hit.
- Phase 4 (polish): a "Verified checklist" scenario that walks
  through the Deck Verified manual rubric (no mouse-only UI, default
  font legible, controller glyph present, etc.) and screenshots each
  required state.

Smoke test already in repo: `tests/scenarios/sp/gamepad_smoke.json`
(verifies the autoload exists, the flag flips, and joypad events
round-trip).

## 5. Phasing & off-ramps

Each phase produces something shippable. Stop after any phase and the
game is still better off.

### Phase 0 — Foundation **(DONE)**

- [x] Linux/Steam Deck export preset (`exports/linux/Warhammer40K.x86_64`)
- [x] `GamepadInputAdapter` autoload (feature-flagged off)
- [x] `ScenarioRunner` joypad event injection (`simulate_joy_button`,
      `simulate_joy_motion`, `set_gamepad_enabled`)
- [x] Smoke scenario `gamepad_smoke.json` — passes 8/8

Effort: ~5h. **Verified headless** in this sandbox; needs a Deck-or-equivalent
verification pass when a real device is available.

### Phase 1 — UI focus & glyphs (~60–100h)

**Foundation landed (~3h):**

- [x] Joypad bindings installed programmatically on Godot's built-in
      `ui_accept` / `ui_cancel` / `ui_up` / `ui_down` / `ui_left` /
      `ui_right` / `ui_focus_next` / `ui_focus_prev` actions, from
      `GamepadInputAdapter._install_ui_action_joypad_bindings()`. Done
      via `InputMap.action_add_event()` rather than editing
      `project.godot` directly, so the change is idempotent and
      reversible. Verified with `expect_input_map_has_joypad_button`
      in `gamepad_smoke.json` (16/16 PASS).
- [x] `InputDeviceTracker` capability folded into `GamepadInputAdapter`:
      `active_device` property + `device_changed(kind)` signal.
      Swap-on-use: mouse motion >5px or click → "mouse"; any joypad
      event → "gamepad". Drives focus-grab and (future) glyph swap.
- [x] `expect_focus_owner` + `expect_input_map_has_joypad_button`
      scenario step types so subsequent menu scenarios can assert the
      *visible* effect, not just that the event reached the engine.
- [x] **MainMenu pilot**: grabs focus on StartButton when gamepad
      becomes the active device (only if no other Control owns
      focus). Pattern documented for replication across other
      menus / dialogs.
- [x] `gamepad_mainmenu_nav.json` scenario asserts D-pad-down moves
      focus through StartButton → MultiplayerButton → LoadButton →
      ReplayButton, with screenshots between. **Awaiting dev-machine
      verification** — see "Sandbox verification caveat" below.

**Remaining for Phase 1 completion:**

- [ ] Audit every interactive `Control` in `scenes/` and `dialogs/`
      and confirm `focus_mode = FOCUS_ALL` (Button + OptionButton +
      LineEdit + Tree default to this, but custom Control subclasses
      may not). Wire `focus_neighbor_*` chains where the implicit
      visual order isn't right (vertical VBox is usually fine; nested
      HBox layouts need explicit chains).
- [ ] Replicate the MainMenu pilot pattern across: SaveLoadDialog,
      MultiplayerLobby, WebLobby, the mission-objectives panel, the
      shortcut overlay, the pause menu, the army-builder dropdowns.
      Each is ~30 min if structure is uniform, longer if nested
      dialogs / dropdowns need focus-restoration handling.
- [ ] `ControllerGlyph` component + glyph atlas (start with Xbox+Deck;
      add PS5 later). Driven by `GamepadInputAdapter.active_device`.
- [ ] Per-screen windowed scenarios (one per pilot above) following
      the `gamepad_mainmenu_nav` pattern.

**Sandbox verification caveat**: this dev environment ships Godot
4.4.1 but the project targets 4.6. The project's `class_name`
globals (FactionPalettes, DeploymentZoneData) don't register on
4.4.1, which prevents `MainMenu.gd` from loading, which prevents the
`gamepad_mainmenu_nav` scenario's focus-traversal assertions from
running here. The *infrastructure* (joypad bindings on ui_* actions,
device tracking, scenario-runner extensions) IS validated headless
via `gamepad_smoke` and is environment-independent. The MainMenu
pilot must run once on the user's 4.6 dev machine to confirm focus
actually moves before the next slice merges.

**Off-ramp value**: every menu fully controller-navigable. Even if
in-game still needs a mouse, the menus stop being a Verified blocker.

### Phase 2 — Phase-controller selection paths (~80–120h)

For each of {Movement, Shooting, Charge, Fight, Command, Deployment}:

- [ ] Subscribe to `GamepadInputAdapter.action_pressed` from the phase
      controller.
- [ ] Route `cycle_unit_prev/next` to existing
      `_cycle_to_next_eligible_unit()` (already exists in
      `ShootingController` per the Tab keybinding — same path).
- [ ] Route `confirm` to the action the current state expects
      (confirm target, end activation, accept dialog choice).
- [ ] Route `cancel` to deselect / cancel modal.
- [ ] Wire the weapon `Tree` and target list to be focus-navigable
      with dpad ↑↓ and confirm with A.
- [ ] Wound allocation overlay: dpad picks model, A allocates.
- [ ] Dice prompts (re-roll? continue?): face buttons.
- [ ] Per-phase scenario coverage.

**Off-ramp value**: a player can finish a shooting + fight phase using
only a controller, as long as units and models stay where the mouse
put them.

### Phase 3 — Virtual cursor & placement (~80–120h)

- [ ] `VirtualCursor` Node2D + draw + screen-space ↔ board-space conv.
- [ ] Stick → cursor motion with acceleration curve, settings.
- [ ] Trigger → mouse-button synthesis (via `Input.parse_input_event`,
      reusing the same path the scenario runner uses).
- [ ] `Input.warp_mouse` integration so existing hover/drag code sees
      the cursor as the system mouse.
- [ ] Snap-anchor registration API. Controllers populate anchors:
      - Movement: max-range arc points, engagement range edges,
        cover edges within range.
      - Charge: target unit engagement-range perimeter.
      - Deployment: deployment zone boundary, coherency-valid points
        for the next model.
      - Pile-in: nearest engaged enemy edge.
- [ ] `NetworkManager.send_drag_preview` rate-limit to 30Hz (the
      stick-driven cursor will otherwise spam the relay).
- [ ] Model rotation: LB/RB while dragging (Q/E equivalents).
- [ ] Per-phase placement scenarios.

**Off-ramp value**: full controller play of single-player. This is the
"playable on Deck" milestone.

### Phase 4 — Steam Input + Verified polish (~40–80h)

- [ ] GodotSteam autoload integration (or stay engine-only if Steam
      shipping slips — adapter is forward-compatible).
- [ ] Steam Input action manifest (`game_actions_*.vdf`): one action
      set per phase, with sensible defaults that ship with the build.
- [ ] Glyph swap via Steam Input rather than `Input.get_joy_name`
      heuristics.
- [ ] Steam Deck virtual keyboard wiring for the three text-input
      sites (save name, lobby IP, chat).
- [ ] 1280×800 layout pass: font scaling, hit-target audit, ensure
      every text label is legible from arm's length.
- [ ] Controller rebinding screen (in-game, not via Steam Input) —
      mirrors `KeybindingManager`'s pattern.
- [ ] Verified checklist scenario walkthrough.
- [ ] Multiplayer-on-Deck pass: lobby IP entry, drag-preview rate
      limit verification under real network conditions.

**Off-ramp value**: ready for Verified submission.

## 6. Risks & mitigations

| Risk                                                                                              | Likelihood | Mitigation                                                                                                                                                              |
| ---                                                                                               | ---        | ---                                                                                                                                                                     |
| Snap-anchor heuristics feel bad in practice; charge placement feels worse than mouse              | High       | Prototype Phase 3 against a real Deck early. Budget time for iteration. Always allow free cursor (snap is opt-in via L3, not mandatory).                                |
| Stick-driven cursor spams `NetworkManager.send_drag_preview`, causing MP lag                      | Medium     | Rate-limit broadcast to 30Hz in Phase 3. (Should arguably already be done for mouse drags on slow networks.)                                                            |
| Existing phase controllers have implicit assumptions about input ordering (mouse-down → -motion → -up) | Medium | `VirtualCursor` synthesises the same event sequence the OS mouse produces, in the same order. Validate per-phase with scenarios in Phase 3.                            |
| Godot 4.4 vs 4.6 — sandbox here runs 4.4.1 but project targets 4.6                                | Low        | Confirmed 4.4.1 still loads the project for Phase 0. Verified scenarios need to run on the project's actual Godot (4.6). All work targets 4.6 features.                |
| Steam Input action set switching mid-phase produces glyph mismatches                              | Low        | Steam Input handles this natively; the adapter only sees output actions. Test in Phase 4.                                                                              |
| Mouse and gamepad both connected → ambiguous "active input device"                                | Low        | `InputDeviceTracker` switches on actual *use*, not connection. Mouse motion of >5px or any mouse-button click swaps to mouse; any joypad event swaps to gamepad.       |
| Tree (weapon list) and ItemList (targets) controls don't expose clean dpad-cycling API in Godot 4 | Medium     | Both are subclassable; we'll wrap them in a `FocusableList` helper. Worst case, replace with a VBoxContainer of Buttons we control.                                    |

## 7. Effort summary

| Phase                                            | Estimate     | Cumulative   |
| ---                                              | ---          | ---          |
| 0 — Foundation                                   | done (~5h)   | done         |
| 1 — UI focus & glyphs                            | 60–100h      | 60–105h      |
| 2 — Selection paths                              | 80–120h      | 140–225h     |
| 3 — Virtual cursor & placement                   | 80–120h      | 220–345h     |
| 4 — Steam Input & Verified polish                | 40–80h       | 260–425h     |

These are wall-clock engineering hours for one developer who knows
the codebase, excluding QA on a real Deck. Hardware verification adds
~20–40h spread across phases.

## 8. Open questions / decisions for later

1. **Steamworks SDK now or Phase 4?** Going GodotSteam from the
   start gives us Steam Input glyphs and lobby integration for free;
   delaying means writing throwaway code. Recommend: spike in Phase 1
   if shipping on Steam is firm, otherwise defer.
2. **Multiplayer-on-Deck**: still open. Phase 3 will surface whether
   the drag-preview broadcast needs rework. Re-evaluate then.
3. **Rebinding UI**: does the in-game rebinding screen need to support
   gamepad rebinding, or is Steam Input config enough? Steam Input is
   the gold standard but only available on Steam — for a sideloaded
   build we'd want our own.
4. **PS5 / Switch Pro glyphs**: scope creep candidate. Defer to a
   post-Verified follow-up unless we know we have PS5 players.

## 9. References

- Godot virtual cursor pattern — <https://godotforums.org/d/32118-gamepadmouse-virtual-cursor>
- Godot controllers / gamepads docs — <https://docs.godotengine.org/en/stable/tutorials/inputs/controllers_gamepads_joysticks.html>
- Steam Input radial menus (Steamworks) — <https://partner.steamgames.com/doc/features/steam_controller/radial_menus>
- XCOM 2 controller scheme — <https://strategywiki.org/wiki/XCOM_2/Controls>
- Tabletop Simulator controller bindings — <https://www.steamcontrollerdb.com/config/tabletop-simulator/default-tabletop-simulator-binding/2341/>
- Wartales Steam Deck controls — <https://steamcommunity.com/app/1527950/discussions/0/5230393378268699446/>
