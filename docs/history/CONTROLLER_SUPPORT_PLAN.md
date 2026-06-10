# Controller Support Plan (Steam Deck / Gamepad)

## Current State Analysis

### Input Architecture
- **Zero gamepad support** exists today — no `InputEventJoypadButton`, `InputEventJoypadMotion`, or `JOY_*` constants anywhere in the 432 GDScript files
- **100% mouse+keyboard** — all interactions use `InputEventMouseButton`, `InputEventMouseMotion`, and `InputEventKey`
- **Custom `KeybindingManager` autoload** manages ~30 keyboard shortcuts across 4 categories (Camera, Gameplay, Model, AI). Supports only `InputEventKey` — no gamepad awareness
- **Minimal Godot Input Map** — `project.godot` only defines 4 input actions (`ui_cancel`, `zoom_in`, `zoom_out`, `quick_save`, `quick_load`) with keyboard-only events

### Core Interactions That Must Be Replaced

| Interaction | Current Input | Files Involved |
|---|---|---|
| Select unit | Left-click on token | All 5 phase controllers |
| Drag model | Left-click + drag continuously | MovementController, ChargeController, FightController |
| Rotate model | Right-click drag OR Q/E keys | MovementController, DeploymentController |
| Place model | Left-click on board position | DeploymentController |
| Select target | Left-click on enemy unit | ShootingController, ChargeController |
| Hover/preview | Mouse motion (continuous) | All controllers — LoS lines, range circles, movement paths |
| Camera pan | WASD / Arrow keys (held in `_process`) | Main.gd line 3892 |
| Camera zoom | +/- keys (held) | Main.gd line 3912 |
| Board rotation | V key | Main.gd line 3766 |
| Context menu | Right-click on unit | Main.gd `_handle_right_click()` |
| UI buttons | Left-click on HUD | Phase action button, undo/reset/confirm, unit list |
| Dialog interaction | Mouse click on buttons/dropdowns | 26 dialog scripts in `dialogs/` |
| Multi-select | Ctrl+click or Shift+drag box | MovementController |
| Scroll rotation | Mouse wheel up/down | DeploymentController |
| Measuring tape | Hold T key + mouse position | Main.gd line 3798 |

### UI Layout
- **HUD_Bottom** (top bar): Phase label, active player badge, status label, phase action button, scores
- **HUD_Right** (400px panel): Unit list (`ItemList`), unit card with stats, undo/reset/confirm buttons
- **HUD_Left** (hidden by default): Mathhammer probability calculator
- **26 popup dialogs** (`AcceptDialog`-based): Weapon assignment, wound allocation, charge targets, pile-in, consolidate, stratagems, etc.
- **Board area**: Center, 2D `Node2D` with `Camera2D`, tokens in `TokenLayer`, ghosts in `GhostLayer`

### Display Considerations
- Game targets **1920x1080** with `canvas_items` stretch mode and `expand` aspect
- Steam Deck screen is **1280x800** — the stretch mode will auto-scale, but small text and buttons may be hard to read/press
- Font: Rajdhani-SemiBold at default sizes
- Renderer: GL Compatibility (good for Steam Deck's AMD APU)

---

## How Other Strategy Games Handle This

### XCOM 2 (closest reference — turn-based tactics with unit selection + targeting)
- Added native controller support post-launch via a major update
- **Virtual cursor** on the tactical map — left stick moves a cursor, A button selects
- **Radial action menu** replaces right-click context menus
- **Bumpers (LB/RB)** cycle between units
- **D-pad** navigates UI menus/lists
- Camera: right stick for pan, triggers for zoom/rotate

### Baldur's Gate 3 (complex RPG with many UI elements)
- **Cursor mode** for world interaction (left stick moves cursor)
- **Radial menus** for spells/abilities (hold button, use stick to select)
- **Context-sensitive button prompts** that change based on what cursor hovers over
- Bumpers cycle between party members

### Into the Breach / Slay the Spire (grid-based strategy)
- **Grid snapping** — cursor snaps to valid tiles/positions rather than free-floating
- Highlight valid targets, use bumpers to cycle between them
- All menus navigable with D-pad + A/B buttons

### Warhammer 40K: Mechanicus
- Virtual cursor on the tactical grid
- Bumpers to cycle between units
- Context-sensitive action menus

### Steam Deck Specifics
- Has two **trackpads** that can emulate mouse movement (decent fallback without any code changes)
- **Steam Input** can remap any controller input to keyboard/mouse actions
- **Touchscreen** — existing mouse handlers may partially work for touch
- Native controller support is always significantly better than Steam Input overlays

---

## Implementation Plan

### Phase 0: Steam Input Profile (No Code Changes)

**Goal:** Immediate basic playability on Steam Deck through Steam's built-in controller remapping.

Create a Steam Input configuration `.vdf` file with these mappings:
```
Left Trackpad    → Mouse cursor movement
Right Trackpad   → WASD (camera pan)
A button         → Left mouse click
B button         → Escape
X button         → Right mouse click
Right Trigger    → Left mouse click (for drag operations)
Left Trigger     → Right mouse click
LB               → Q (rotate left)
RB               → E (rotate right)
D-pad Up/Down    → +/- (zoom)
D-pad Left/Right → [ / ] (quick save/load)
Start            → Escape (settings)
Select           → Shift+/ (shortcut overlay)
```

**Deliverable:** A `.vdf` file in the repo root that players can import into Steam Input. Document in README.

**Limitation:** Drag operations will be clunky, dialog navigation will be poor, no visual button prompts. But the game becomes *playable*.

---

### Phase 1: Input Abstraction Layer

**Goal:** Decouple game logic from raw mouse/keyboard events. This is the foundation everything else builds on.

#### 1a. Extend `KeybindingManager` for Gamepad

Add gamepad button/axis fields alongside existing keyboard fields:

```
New fields per binding:
  - joypad_button: int (JOY_BUTTON_* constant, -1 = none)
  - joypad_axis: int (JOY_AXIS_* constant, -1 = none)
  - joypad_axis_direction: float (+1.0 or -1.0)
```

Add methods:
- `matches_joypad_action(event: InputEventJoypadButton, action_id: String) -> bool`
- `is_joypad_action_pressed(action_id: String) -> bool` (for held-button checks in `_process`)

Add default gamepad mappings for all 30+ existing actions.

#### 1b. Create `InputMode` Autoload

New autoload that tracks whether the player is using keyboard/mouse or gamepad:
- Auto-detect based on last `InputEvent` type received
- Expose `is_gamepad_mode() -> bool`
- Emit `input_mode_changed(is_gamepad: bool)` signal
- Used by UI to show/hide button prompts and switch interaction styles

#### 1c. Create `VirtualCursor` System

New `Node2D` that acts as a gamepad-controlled cursor on the board:
- Visible cursor sprite that moves with the **left analog stick**
- Configurable speed, acceleration curve, dead zone
- Handles board-space coordinate conversion (mirrors `screen_to_world_position()` in Main.gd)
- **Snap-to-unit mode:** When cursor is near a valid selectable unit, snap to it (magnetism)
- Provides `get_cursor_world_position() -> Vector2` that all controllers can call instead of `get_global_mouse_position()`
- Hidden when in keyboard/mouse mode, visible when in gamepad mode

**Files to modify:** KeybindingManager.gd, project.godot (add input actions)
**Files to create:** InputMode.gd (autoload), VirtualCursor.gd

---

### Phase 2: Camera Controls

**Goal:** Smooth camera control with analog sticks. This is quick to implement since camera logic is already cleanly isolated in `Main._process()`.

**Mapping:**
- **Right analog stick** → Camera pan (replaces WASD, already uses `KeybindingManager.is_action_pressed()` — extend to read stick axes)
- **Left/Right triggers** → Zoom in/out (analog, pressure-sensitive — much nicer than binary +/- keys)
- **D-pad Up/Down** → Board rotate 90° (replaces V key)
- **R3 (click right stick)** → Reset camera / focus on action

**Changes in Main.gd `_process()`:**
```gdscript
# Read right stick for camera pan
var joy_pan = Vector2(
    Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
    Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
)
if joy_pan.length() > 0.15:  # dead zone
    view_offset += joy_pan.rotated(-view_rotation) * pan_speed * 2.0
    view_changed = true

# Read triggers for zoom
var zoom_in_val = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)
var zoom_out_val = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
if zoom_in_val > 0.1:
    view_zoom *= 1.0 + (0.03 * zoom_in_val)
    view_zoom = clamp(view_zoom, 0.1, 3.0)
    view_changed = true
```

**Files to modify:** Main.gd (`_process()` and `_input()`)

---

### Phase 3: Board Interaction Controllers

**Goal:** Make all 5 phase controllers work with gamepad. This is the largest and most complex phase.

#### 3a. Unit Selection

Two complementary methods:
1. **Virtual cursor + A button:** Move cursor over unit → press A to select (mirrors left-click)
2. **LB/RB cycling:** Cycle through available units for the current phase
   - During Movement: cycles through unmoved units
   - During Shooting: cycles through units that haven't shot
   - During Charge: cycles through units eligible to charge
   - Visual "focus ring" highlights the currently focused (but not yet selected) unit

#### 3b. Model Movement (Biggest Challenge)

Current flow: Click model → drag to new position → release to place.

**Proposed controller flow:**
1. Select unit (A button or LB/RB cycle)
2. Select model within unit (D-pad left/right to cycle models, or auto-select leader)
3. Enter **Move Mode** — left stick now controls the selected model's position directly
   - Show movement range circle
   - Show coherency indicators in real-time
   - Snap to coherency-friendly positions when near other models
4. **A button** confirms placement
5. **B button** cancels and returns model to original position
6. **Right stick** controls model rotation (replacing right-click drag)

**Multi-model movement (formation drag):**
- Hold **LB** while in move mode to move all selected models as a group
- Or use "Select All" (mapped to a button combo) then enter group move mode

#### 3c. Deployment Placement

Similar to movement but simpler:
1. Select unit from list (D-pad navigates unit list, A selects)
2. Left stick moves ghost preview on board
3. A button places model
4. Right stick rotates model
5. B button undoes last placement
6. LB/RB cycles formation mode (SINGLE/SPREAD/TIGHT)

#### 3d. Target Selection (Shooting & Charge)

1. After selecting attacker, game highlights eligible targets
2. **LB/RB cycles through eligible targets** (much better than hunting with cursor)
3. Current target highlighted with prominent indicator + LoS line preview
4. **A button** assigns target / confirms selection
5. **Y button** confirms all assignments (replaces "Confirm Targets" button)
6. **B button** deselects / goes back

#### 3e. Fight Phase (Pile-in / Consolidate)

1. Unit auto-selected based on fight order
2. For pile-in/consolidate movement: same as model movement (left stick + A to confirm)
3. Attack assignment: same as target selection (LB/RB cycle + A to assign)

**Files to modify:**
- `DeploymentController.gd` (`_unhandled_input`)
- `MovementController.gd` (`_unhandled_input`)
- `ShootingController.gd` (`_input`)
- `ChargeController.gd` (`_input`)
- `FightController.gd` (`_input`)
- `DisembarkController.gd` (`_unhandled_input`)

---

### Phase 4: UI & Dialog Navigation

**Goal:** All menus, HUD elements, and dialogs usable without mouse.

#### 4a. Godot Focus System

Godot's built-in `Control` node focus system (`focus_neighbor_*` properties, `focus_next`, `focus_previous`) handles most of the heavy lifting for UI navigation. The work is:

1. **Set `focus_neighbor` properties** on all interactive controls in:
   - Main menu dropdowns and buttons
   - HUD_Right unit list and action buttons
   - HUD_Bottom phase action button
   - All 26 dialog scripts

2. **Map D-pad to UI navigation:**
   - D-pad Up/Down → Focus previous/next (Godot handles this if focus neighbors are set)
   - A button → "Accept" / click focused control
   - B button → Cancel / close dialog

3. **Auto-focus:** When a dialog opens, auto-focus the most common button (usually "Confirm" or the first option)

#### 4b. ItemList / Tree Navigation

The unit list (`ItemList`) and weapon trees (`Tree`) in ShootingController/FightController need:
- D-pad Up/Down to navigate items
- A to select/toggle
- These Godot controls already support keyboard navigation when focused

#### 4c. Context-Sensitive Button Prompts

Display a small overlay showing available actions:
```
When hovering a unit:     [A] Select    [RB] Next Unit
When unit selected:       [A] Confirm   [B] Cancel     [LB/RB] Cycle
When in dialog:           [A] OK        [B] Cancel     [D-pad] Navigate
```

This overlay appears at the bottom of the screen, auto-hides in mouse/keyboard mode.

**Files to modify:** All 26 dialog scripts, Main.gd (HUD setup), MainMenu.gd
**Files to create:** ButtonPromptOverlay.gd (new HUD element)

---

### Phase 5: Steam Deck Polish

**Goal:** Optimize specifically for Steam Deck hardware.

#### 5a. UI Scaling
- Add a "Steam Deck Mode" toggle in Settings that increases:
  - Minimum button sizes (from ~30px to ~48px touch targets)
  - Font sizes for unit cards, weapon stats, dice results
  - HUD panel widths
- The `canvas_items` stretch mode already handles resolution scaling, but elements may be too small to read comfortably at 1280x800

#### 5b. Touch Input
- Steam Deck has a touchscreen — test that existing `InputEventMouseButton` handlers work for touch
- Ensure touch-friendly hit areas on all buttons (minimum 44x44px)

#### 5c. Performance Profiling
- The 2D GL Compatibility renderer should run well on Steam Deck's AMD APU
- Profile to verify: token rendering with many units, LoS calculations, dice animations

#### 5d. Steam Deck Verified Metadata
- Add appropriate controller glyphs
- Ensure proper suspend/resume behavior (save state)
- Test with Steam Deck's native resolution and scaling

---

## Proposed Controller Layout (Default)

```
┌─────────────────────────────────────────────┐
│                STEAM DECK / GAMEPAD          │
│                                              │
│  [LB] Prev Unit          [RB] Next Unit     │
│  [LT] Zoom Out           [RT] Zoom In       │
│                                              │
│  [Left Stick]             [Right Stick]      │
│  Move cursor /            Camera pan /       │
│  Move model               Model rotation     │
│  [L3] Snap toggle         [R3] Reset camera  │
│                                              │
│  [D-pad]                  [Face Buttons]     │
│  ↑↓ Navigate UI           [A] Select/Confirm │
│  ←→ Cycle models/         [B] Cancel/Back    │
│     formation mode         [X] Context action │
│                            [Y] End phase /    │
│                               Confirm all    │
│                                              │
│  [Start] Settings (ESC)                      │
│  [Select] Shortcut overlay                   │
└─────────────────────────────────────────────┘
```

---

## Risk Assessment

### High Complexity
1. **Model dragging → stick movement** — The movement system tracks continuous mouse positions via `InputEventMouseMotion` across 15+ `get_global_mouse_position()` calls in MovementController alone. Converting to stick-driven positioning requires rethinking the drag paradigm.

2. **26 dialogs need focus chains** — Each dialog was built assuming mouse. Setting `focus_neighbor` properties on every button, dropdown, and tree across all dialogs is tedious but mechanical.

3. **Hover previews** — LoS lines, range circles, movement path previews all trigger on `InputEventMouseMotion`. With gamepad, these need to trigger based on virtual cursor position updates.

### Medium Complexity
4. **Multi-model selection** — Ctrl+click and Shift+drag box in MovementController needs a gamepad equivalent. Suggestion: hold LB + A to add to selection, or a "Select All" shortcut.

5. **Weapon assignment trees** — ShootingController and FightController use `Tree` nodes with clickable items. These support keyboard focus but need testing.

### Low Complexity
6. **Camera controls** — Already cleanly isolated in `Main._process()`, easy to extend with analog stick input.

7. **Main menu** — Standard Godot Controls with built-in focus support.

8. **Performance** — 2D game with GL Compatibility renderer. Not a concern on Steam Deck.

---

## Recommended Implementation Order

```
Phase 0  →  Ship immediately (Steam Input profile, no code)
Phase 1  →  Foundation (InputMode + VirtualCursor + KeybindingManager extension)
Phase 2  →  Camera controls (quick win, high impact)
Phase 3  →  Board interactions (biggest effort, highest value)
  3d first  →  Target selection (most natural for controller)
  3c next   →  Deployment placement
  3b then   →  Model movement (hardest)
  3e last   →  Fight phase
Phase 4  →  UI/dialog navigation
Phase 5  →  Steam Deck polish
```

Phase 0 gives immediate value. Phases 1+2 together create a solid foundation. Phase 3 is where most of the work lives. Phases 4+5 are polish that can be done incrementally.
