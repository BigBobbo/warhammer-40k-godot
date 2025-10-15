# Interactive Wound Allocation System PRP
**Version**: 2.0
**Date**: 2025-10-13
**Scope**: Sequential wound allocation with board-based model selection

## 1. Executive Summary

This PRP defines the implementation of a **sequential, interactive wound allocation system** for the Warhammer 40K 10th edition game. The current system auto-resolves wound allocation without player interaction. This implementation will transfer full control to the defending player, allowing them to select which models take wounds by **clicking directly on the game board**, following the sequential allocation rules of 10th edition.

**Key Design Decisions:**
- **Sequential Allocation**: One wound at a time - select model → roll save → apply damage → next wound
- **Board-Based Selection**: Defender clicks models on the game board (not from a list/dialog)
- **Overlay UI**: Semi-transparent modal that shows save info without blocking board view
- **Manual Only**: No auto-allocation option - tactical decisions are core gameplay
- **Real-Time Sync**: Attacker sees model selection and dice rolls as they happen
- **No Damage Spillover**: Single shots don't carry excess damage to other models (per 10e rules)

---

## 2. Current State Analysis

### 2.1 Existing Implementation

**Current Flow (from SaveDialog.gd):**
```
1. Wounds calculated after to-wound rolls
2. SaveDialog.gd opens with auto-allocation
3. Defender clicks "Roll All Saves" (batch)
4. All damage applied at once
5. Dialog closes
```

**Problems with Current System:**
- ❌ No tactical choice in wound allocation
- ❌ Batch rolling removes decision points between saves
- ❌ Dialog blocks view of game board
- ❌ Models cannot be selected directly on the board
- ❌ No visual feedback on which models are being targeted

### 2.2 Existing Code to Leverage

**RulesEngine.gd** (lines 1980-2219):
- `prepare_save_resolution()` - Already builds save data
- `auto_allocate_wounds()` - Logic for priority (wounded models first) - reference only
- `roll_saves_batch()` - Can be adapted for single rolls
- `apply_save_damage()` - Damage application with diffs

**ShootingController.gd** (lines 1000-1108):
- `_on_saves_required()` signal handler
- Multiplayer player detection
- Dialog spawning logic

---

## 3. Core Requirements

### 3.1 Rules Compliance (10th Edition)

> **From Core Rules - Damage Allocation:**
> "If a model in the target unit has already lost one or more wounds, or has already had attacks allocated to it this phase, that attack must be allocated to that model."

**Implementation Requirements:**
1. **Priority Enforcement**: Models with lost wounds MUST be selected first
2. **Sequential Resolution**: One wound at a time, not batch
3. **Visual Clarity**: Defender must see which models are valid/required targets
4. **No Spillover**: A 3-damage attack that kills a 1-wound model doesn't carry damage forward
5. **Invulnerable Saves**: Defender uses best save (armor or invuln)
6. **Feel No Pain**: EXCLUDED from MVP (can be added later)

### 3.2 Architecture Requirements

- Integrate with existing Phase-Controller pattern
- Full NetworkManager support for multiplayer (attacker sees choices)
- Deterministic RNG through RulesEngine.RNGService (host-side rolls)
- State preservation for save/load mid-allocation
- Clear visual feedback on board and in UI

---

## 4. User Flow - Sequential Wound Allocation

### 4.1 Phase Entry (Defender Receives Wounds)

**Trigger**: Attacker's wound rolls complete with N successes

```
1. ShootingPhase emits `saves_required` signal
2. ShootingController checks if local player is defender
3. IF defender: Show WoundAllocationOverlay
4. IF attacker: Show "Waiting for Defender" message + spectator view
```

### 4.2 Wound #1 Allocation Flow

```
┌─────────────────────────────────────────────────────────────┐
│ [DEFENDER VIEW]                                             │
│                                                              │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ WoundAllocationOverlay (60% opacity bg)                 │ │
│ │                                                          │ │
│ │  Incoming Attack: Bolt Rifle (AP-1, Damage 1)          │ │
│ │  Wounds to Allocate: Wound 1 of 5                      │ │
│ │                                                          │ │
│ │  Target Unit: Ork Boyz (8 models alive)                │ │
│ │  Save Required: 6+ (modified by AP-1)                  │ │
│ │  Cover Bonus: +1 (if in terrain)                       │ │
│ │                                                          │ │
│ │  ┌────────────────────────────────────────────────┐    │ │
│ │  │ INSTRUCTIONS:                                   │    │ │
│ │  │ Click on a model to allocate this wound        │    │ │
│ │  │                                                  │    │ │
│ │  │ ⚠ Boy #2 is wounded - must allocate to him!    │    │ │
│ │  └────────────────────────────────────────────────┘    │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                              │
│  GAME BOARD (Visible Behind Overlay):                      │
│  ┌────────────────────────────────────────────────┐        │
│  │  🟢 Boy #1  🔴 Boy #2*  🟢 Boy #3  🟢 Boy #4  │        │
│  │     (HP 1/1)  (HP 1/2)   (HP 1/1)   (HP 1/1)  │        │
│  │                                                 │        │
│  │  🟢 = Selectable (green highlight)              │        │
│  │  🔴 = MUST SELECT (red pulsing highlight)       │        │
│  │  * = Previously wounded                         │        │
│  └────────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

**Step-by-Step:**
1. Overlay appears with save stats and instructions
2. Game board remains visible (overlay has semi-transparent background)
3. All alive models in target unit get highlights:
   - **Red pulsing**: Models that MUST be selected (wounded)
   - **Green glow**: Models that CAN be selected (if no wounded models exist)
   - **Striped pattern**: Alternate pattern for color-blind accessibility
4. Defender clicks on a model on the board
5. Selected model flashes bright yellow (0.3s flash)

### 4.3 Save Roll Execution

```
┌─────────────────────────────────────────────────────────────┐
│ [IMMEDIATE AFTER MODEL SELECTION]                           │
│                                                              │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ WoundAllocationOverlay                                  │ │
│ │                                                          │ │
│ │  Wound #1 allocated to: Boy #2                         │ │
│ │  Save Required: 6+                                     │ │
│ │                                                          │ │
│ │  ┌────────────────────────────────────────────────┐    │ │
│ │  │ 🎲 Rolling Save...                              │    │ │
│ │  │                                                  │    │ │
│ │  │    [Simple fade-in with result]                 │    │ │
│ │  │                                                  │    │ │
│ │  │    Result: 4                                    │    │ │
│ │  │    Needed: 6+                                   │    │ │
│ │  │    ❌ SAVE FAILED                               │    │ │
│ │  │                                                  │    │ │
│ │  │    Boy #2 takes 1 damage                        │    │ │
│ │  │    HP: 1 → 0  [💀 DESTROYED]                    │    │ │
│ │  └────────────────────────────────────────────────┘    │ │
│ │                                                          │ │
│ │  Continuing to next wound in 1 second...               │ │
│ │                                      [Continue Now Btn] │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                              │
│  GAME BOARD:                                                │
│  • Boy #2 plays death animation (fade + X marker)          │
│  • Model removed from valid selections                     │
│  • Highlights update for next wound                        │
└─────────────────────────────────────────────────────────────┘
```

**Automatic Actions (No Player Input Needed):**
1. Save roll happens immediately after model selection (no confirmation)
2. Result displayed with clear pass/fail indicator (0.5s)
3. Damage applied to selected model
4. Model death animation plays on board if destroyed (1.0s)
5. Overlay automatically advances to next wound after 1.5 second delay
6. **Continue Now** button allows skipping delay

### 4.4 Subsequent Wounds (Same Flow)

```
Wound #2:
  → Check for wounded models again (Boy #2 is dead, no longer priority)
  → All remaining models highlighted green (any can be selected)
  → Defender clicks Boy #5
  → Roll save: 6 vs 6+ → SAVED ✓
  → Boy #5 takes no damage
  → Continue to wound #3 (1.5s delay or click Continue Now)

Wound #3:
  → [Same flow]
  → ...
```

### 4.5 Completion

```
All wounds allocated → Overlay shows summary (2s):

┌─────────────────────────────────────────────────────────────┐
│  Save Resolution Complete!                                  │
│                                                              │
│  Results:                                                   │
│  • 5 wounds allocated                                       │
│  • 2 saves passed                                           │
│  • 3 saves failed                                           │
│  • 3 damage dealt                                           │
│  • 2 models destroyed (Boy #2, Boy #7)                     │
│                                                              │
│  [OK - Return to Shooting Phase]                           │
└─────────────────────────────────────────────────────────────┘

→ Auto-closes after 2s or on [OK] click
→ Returns control to attacker
```

---

## 5. UI Design Specifications

### 5.1 WoundAllocationOverlay (New Component)

**Type**: Custom `Control` node (NOT `AcceptDialog` - more flexible)
**Position**: Centered on screen, anchored to top
**Size**: 450px wide × 250px tall
**Background**:
- Full-screen ColorRect (black, 60% opacity) behind overlay
- Overlay itself: PanelContainer with rounded corners
**Border**: Subtle glow effect (white, 10px blur)

**Layout Structure:**
```gdscript
WoundAllocationOverlay (Control)
├── BackgroundDim (ColorRect - full screen, 60% opacity)
├── OverlayPanel (PanelContainer)
│   └── MainVBox (VBoxContainer)
│       ├── HeaderHBox (HBoxContainer)
│       │   ├── AttackIcon (TextureRect) - ⚔️ icon
│       │   └── AttackInfoLabel (Label) - "Bolt Rifle (AP-1, D1)"
│       ├── HSeparator
│       ├── StatusLabel (Label) - "Wound 1 of 5"
│       ├── TargetInfoLabel (Label) - "Target: Ork Boyz (8 alive)"
│       ├── SaveInfoLabel (RichTextLabel) - Save details with BBCode
│       ├── HSeparator
│       ├── InstructionPanel (PanelContainer)
│       │   └── InstructionLabel (RichTextLabel) - Dynamic instructions
│       ├── HSeparator
│       ├── DiceResultPanel (PanelContainer) - Shows after roll
│       │   └── VBoxContainer
│       │       ├── DiceIcon (TextureRect) - 🎲
│       │       ├── ResultLabel (Label) - "4 vs 6+"
│       │       └── OutcomeLabel (Label) - "FAILED" or "SAVED"
│       ├── HSeparator (visible only when showing result)
│       └── ActionHBox (HBoxContainer)
│           └── ContinueButton (Button) - "Continue Now"
```

### 5.2 Board Visual Feedback

**Model Highlights (Shader-based for performance):**

```gdscript
# WoundAllocationBoardHighlights.gd
extends Node2D
class_name WoundAllocationBoardHighlights

# Highlight types
enum HighlightType {
    PRIORITY,    # Red pulsing - must select
    SELECTABLE,  # Green steady - can select
    SELECTED,    # Yellow flash - just selected
}

# Shader material for highlights (GPU-accelerated)
const HIGHLIGHT_SHADER = preload("res://shaders/model_highlight.gdshader")

func create_highlight(model_pos: Vector2, base_radius_mm: float, type: HighlightType) -> void:
    var highlight = Sprite2D.new()
    highlight.texture = preload("res://assets/ui/circle_highlight.png")
    highlight.position = model_pos

    var base_px = Measurement.base_radius_px(base_radius_mm)
    var scale_factor = (base_px + 15) / 64.0  # 64px texture size
    highlight.scale = Vector2(scale_factor, scale_factor)

    # Apply shader for effects
    var material = ShaderMaterial.new()
    material.shader = HIGHLIGHT_SHADER

    match type:
        HighlightType.PRIORITY:
            material.set_shader_parameter("base_color", Color(1.0, 0.2, 0.2, 0.6))
            material.set_shader_parameter("pulse", true)
            material.set_shader_parameter("pulse_speed", 2.0)
        HighlightType.SELECTABLE:
            material.set_shader_parameter("base_color", Color(0.2, 1.0, 0.2, 0.4))
            material.set_shader_parameter("pulse", false)
        HighlightType.SELECTED:
            material.set_shader_parameter("base_color", Color(1.0, 1.0, 0.0, 0.9))
            material.set_shader_parameter("pulse", false)
            # Add fade-out tween
            var tween = create_tween()
            tween.tween_property(material, "shader_parameter/base_color:a", 0.0, 0.5)
            tween.tween_callback(highlight.queue_free)

    highlight.material = material
    add_child(highlight)
```

**Hover Effect:**
- When mouse hovers over selectable model: Scale highlight by 1.15x (tween 0.1s)
- Cursor changes to pointing hand (`Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)`)
- Tooltip appears showing model HP and save value

**Click Feedback:**
- Selected model gets yellow flash (0.3s)
- Brief screen shake (2px amplitude, 0.1s)
- Sound effect: "click_confirm.wav"

### 5.3 Attacker View (Spectator Mode)

While defender is allocating:

```
┌─────────────────────────────────────────────────────────────┐
│ [ATTACKER VIEW]                                             │
│                                                              │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ Waiting for Defender...                                 │ │
│ │                                                          │ │
│ │  🎯 Defender is allocating wounds (Wound 2 of 5)       │ │
│ │  👉 Boy #5 selected                                    │ │
│ │                                                          │ │
│ │  🎲 Rolling save: 6 vs 6+                              │ │
│ │  ✓ SAVED - Boy #5 takes no damage                      │ │
│ │                                                          │ │
│ │  [Live Feed - Auto-Scrolling]                          │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                              │
│  GAME BOARD:                                                │
│  • Models highlighted in real-time as defender selects     │
│  • Dice results displayed above selected model            │
│  • Death animations play when models are destroyed         │
│  • Attacker CANNOT interact (read-only view)               │
└─────────────────────────────────────────────────────────────┘
```

**Attacker sees (in real-time):**
- Live updates of which model is selected (highlight synced)
- Dice roll results as they happen (via network broadcast)
- Model death animations
- Running log of allocation history
- **Cannot interact** - all inputs disabled except scroll

---

## 6. Technical Implementation

### 6.1 New Components

**File: `scripts/WoundAllocationOverlay.gd`**
```gdscript
extends Control
class_name WoundAllocationOverlay

# Signals for state changes
signal wound_allocated(model_id: String, wound_index: int)
signal save_rolled(result: Dictionary)
signal allocation_complete(summary: Dictionary)

# State
var save_data: Dictionary = {}  # From RulesEngine.prepare_save_resolution()
var current_wound_index: int = 0
var total_wounds: int = 0
var allocation_history: Array = []  # [{wound_index, model_id, roll, saved, damage}]
var defender_player: int = 0
var awaiting_selection: bool = false
var rng_service: RulesEngine.RNGService = null

# References
var board_view: Node2D
var target_unit: Dictionary
var board_highlighter: WoundAllocationBoardHighlights

# UI Nodes (created in _ready)
var attack_info_label: Label
var status_label: Label
var target_info_label: Label
var save_info_label: RichTextLabel
var instruction_label: RichTextLabel
var dice_result_panel: PanelContainer
var result_label: Label
var outcome_label: Label
var continue_button: Button

func _ready():
    # Setup full-screen background dim
    var bg_dim = ColorRect.new()
    bg_dim.color = Color(0, 0, 0, 0.6)
    bg_dim.anchor_right = 1.0
    bg_dim.anchor_bottom = 1.0
    add_child(bg_dim)

    # Create overlay panel
    _build_ui()

    # Get board reference
    board_view = get_node_or_null("/root/Main/BoardRoot/BoardView")

    # Create board highlighter
    board_highlighter = WoundAllocationBoardHighlights.new()
    board_highlighter.name = "WoundHighlights"
    board_view.add_child(board_highlighter)

    # Hide dice result panel initially
    dice_result_panel.visible = false

func setup(p_save_data: Dictionary, p_defender_player: int):
    save_data = p_save_data
    defender_player = p_defender_player
    total_wounds = save_data.wounds_to_save
    current_wound_index = 0

    # Initialize RNG (client-side preview only, host rolls for real)
    rng_service = RulesEngine.RNGService.new()

    # Get target unit
    target_unit = GameState.get_unit(save_data.target_unit_id)

    # Start first allocation
    _start_wound_allocation()

func _start_wound_allocation():
    """Begin allocation for current_wound_index"""
    awaiting_selection = true

    # Update UI labels
    _update_ui_for_current_wound()

    # Highlight valid models on board
    _highlight_valid_models()

    # Enable input
    set_process_input(true)

func _highlight_valid_models():
    """Add visual highlights to models based on allocation rules"""
    board_highlighter.clear_all()

    var wounded_models = _get_wounded_models()
    var all_models = target_unit.get("models", [])

    for i in range(all_models.size()):
        var model = all_models[i]
        if not model.get("alive", true):
            continue

        var model_id = model.get("id", "m%d" % i)
        var model_pos = RulesEngine._get_model_position(model)
        var base_mm = model.get("base_mm", 32)

        if wounded_models.has(model_id):
            # MUST SELECT - Red pulsing highlight
            board_highlighter.create_highlight(
                model_pos, base_mm,
                WoundAllocationBoardHighlights.HighlightType.PRIORITY
            )
        elif wounded_models.is_empty():
            # CAN SELECT - Green highlight (only if no wounded models)
            board_highlighter.create_highlight(
                model_pos, base_mm,
                WoundAllocationBoardHighlights.HighlightType.SELECTABLE
            )

func _input(event: InputEvent):
    if not awaiting_selection:
        return

    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        # Convert screen click to board position
        var click_pos = board_view.get_local_mouse_position()
        var clicked_model_id = _find_model_at_position(click_pos)

        if clicked_model_id != "":
            _on_model_clicked(clicked_model_id)

func _on_model_clicked(model_id: String):
    """Handle defender clicking a model"""
    # Validate selection
    if not _is_valid_selection(model_id):
        _show_error_flash("Must select wounded model first!")
        return

    awaiting_selection = false
    set_process_input(false)

    # Flash selected model
    var model = _get_model_by_id(model_id)
    var model_pos = RulesEngine._get_model_position(model)
    board_highlighter.create_highlight(
        model_pos, model.get("base_mm", 32),
        WoundAllocationBoardHighlights.HighlightType.SELECTED
    )

    # Play sound
    SoundManager.play("click_confirm")

    # Emit signal for multiplayer sync
    emit_signal("wound_allocated", model_id, current_wound_index)

    # In multiplayer, submit to host for validation
    if NetworkManager.is_networked():
        _submit_wound_allocation(model_id)
    else:
        # Single player - immediately roll save
        _roll_save_for_model(model_id)

func _roll_save_for_model(model_id: String):
    """Roll save and apply damage (host-side)"""
    # Find model profile
    var save_profile = _get_model_save_profile(model_id)

    # Roll save (on host in multiplayer, local in single-player)
    var roll = rng_service.roll_d6(1)[0]
    var needed = save_profile.save_needed
    var saved = roll >= needed

    # Build result
    var result = {
        "wound_index": current_wound_index,
        "model_id": model_id,
        "model_index": save_profile.model_index,
        "roll": roll,
        "needed": needed,
        "saved": saved,
        "damage": save_data.damage if not saved else 0,
        "model_destroyed": false
    }

    # Check if model dies
    if not saved:
        var current_wounds = save_profile.current_wounds
        var damage = save_data.damage
        if damage >= current_wounds:
            result.model_destroyed = true

    allocation_history.append(result)

    # Emit signal for multiplayer sync
    emit_signal("save_rolled", result)

    # Display result in UI
    _display_save_result(result)

    # Apply damage immediately
    if not saved:
        _apply_damage_to_model(model_id, save_profile.model_index, result.model_destroyed)

    # Wait 1.5s then continue (or user can skip)
    continue_button.disabled = false
    await get_tree().create_timer(1.5).timeout

    if is_inside_tree():  # Check still valid after timer
        _continue_to_next_wound()

func _continue_to_next_wound():
    """Move to next wound or complete allocation"""
    continue_button.disabled = true
    dice_result_panel.visible = false

    current_wound_index += 1

    if current_wound_index >= total_wounds:
        _complete_allocation()
    else:
        _start_wound_allocation()

func _complete_allocation():
    """All wounds allocated - show summary"""
    var summary = _build_summary()
    emit_signal("allocation_complete", summary)

    # Show summary UI
    _display_summary(summary)

    # Auto-close after 2s
    await get_tree().create_timer(2.0).timeout
    _close()

func _close():
    """Clean up and close overlay"""
    # Clear board highlights
    if board_highlighter and is_instance_valid(board_highlighter):
        board_highlighter.clear_all()
        board_highlighter.queue_free()

    # Remove from tree
    queue_free()

func _is_valid_selection(model_id: String) -> bool:
    """Check if model can be selected per 10e rules"""
    var wounded_models = _get_wounded_models()

    # If there are wounded models, MUST select one of them
    if not wounded_models.is_empty():
        return model_id in wounded_models

    # Otherwise, any alive model is valid
    var model = _get_model_by_id(model_id)
    return model.get("alive", true) if not model.is_empty() else false

func _get_wounded_models() -> Array:
    """Return array of model_ids that have lost wounds"""
    var wounded = []
    var models = target_unit.get("models", [])

    for i in range(models.size()):
        var model = models[i]
        if not model.get("alive", true):
            continue

        var current_wounds = model.get("current_wounds", model.get("wounds", 1))
        var max_wounds = model.get("wounds", 1)

        if current_wounds < max_wounds:
            wounded.append(model.get("id", "m%d" % i))

    return wounded

func _find_model_at_position(click_pos: Vector2) -> String:
    """Find which model was clicked based on position"""
    var models = target_unit.get("models", [])
    var closest_model_id = ""
    var closest_distance = INF

    for i in range(models.size()):
        var model = models[i]
        if not model.get("alive", true):
            continue

        var model_pos = RulesEngine._get_model_position(model)
        var base_mm = model.get("base_mm", 32)
        var base_radius_px = Measurement.base_radius_px(base_mm)

        # Generous click radius (base + 50px for easier selection)
        var click_radius = base_radius_px + 50

        var distance = model_pos.distance_to(click_pos)

        if distance <= click_radius and distance < closest_distance:
            closest_distance = distance
            closest_model_id = model.get("id", "m%d" % i)

    return closest_model_id

func _display_save_result(result: Dictionary):
    """Show dice result in overlay"""
    dice_result_panel.visible = true

    result_label.text = "%d vs %d+" % [result.roll, result.needed]

    if result.saved:
        outcome_label.text = "✓ SAVED"
        outcome_label.add_theme_color_override("font_color", Color.GREEN)
        SoundManager.play("save_passed")
    else:
        outcome_label.text = "✗ FAILED"
        outcome_label.add_theme_color_override("font_color", Color.RED)
        SoundManager.play("save_failed")

        # Show damage info
        var damage_text = "\n%s takes %d damage" % [result.model_id, result.damage]
        if result.model_destroyed:
            damage_text += " [💀 DESTROYED]"
            SoundManager.play("model_destroyed")

        outcome_label.text += damage_text

func _apply_damage_to_model(model_id: String, model_index: int, destroyed: bool):
    """Apply damage via NetworkManager action"""
    # This will be handled by submitting APPLY_WOUND_DAMAGE action
    # For now, visually update the model

    if destroyed:
        # Play death animation on board
        var model = target_unit.models[model_index]
        var model_pos = RulesEngine._get_model_position(model)
        _play_death_animation(model_pos)

func _play_death_animation(pos: Vector2):
    """Show death animation at position"""
    var death_marker = Sprite2D.new()
    death_marker.texture = preload("res://assets/ui/death_x.png")
    death_marker.position = pos
    death_marker.modulate = Color(1, 0, 0, 1)
    board_view.add_child(death_marker)

    # Fade out
    var tween = create_tween()
    tween.tween_property(death_marker, "modulate:a", 0.0, 1.0)
    tween.tween_callback(death_marker.queue_free)

func _build_summary() -> Dictionary:
    """Build allocation summary"""
    var passed = 0
    var failed = 0
    var total_damage = 0
    var destroyed = 0

    for entry in allocation_history:
        if entry.saved:
            passed += 1
        else:
            failed += 1
            total_damage += entry.damage
            if entry.model_destroyed:
                destroyed += 1

    return {
        "total_wounds": total_wounds,
        "saves_passed": passed,
        "saves_failed": failed,
        "total_damage": total_damage,
        "models_destroyed": destroyed,
        "allocation_history": allocation_history
    }
```

### 6.2 Integration with ShootingController

**Modifications to `ShootingController.gd`:**

```gdscript
func _on_saves_required(save_data_list: Array) -> void:
    """Show WoundAllocationOverlay when defender needs to make saves"""
    if save_data_list.is_empty():
        return

    # Process ONE target at a time (sequential)
    var save_data = save_data_list[0]

    # Get defender
    var target_unit_id = save_data.get("target_unit_id", "")
    var target_unit = GameState.get_unit(target_unit_id)
    var defender_player = target_unit.get("owner", 0)

    # Check if this player should show dialog
    var should_show_overlay = false

    if NetworkManager.is_networked():
        var local_peer_id = multiplayer.get_unique_id()
        var local_player = NetworkManager.peer_to_player_map.get(local_peer_id, -1)
        should_show_overlay = (local_player == defender_player)
    else:
        should_show_overlay = true

    if should_show_overlay:
        _show_wound_allocation_overlay(save_data, defender_player)
    else:
        _show_spectator_overlay(save_data, defender_player)

func _show_wound_allocation_overlay(save_data: Dictionary, defender_player: int):
    """Show interactive overlay for defender"""
    # Close any existing overlays
    _close_existing_overlays()

    # Create new overlay
    var overlay = preload("res://scripts/WoundAllocationOverlay.gd").new()

    # Connect signals
    overlay.wound_allocated.connect(_on_defender_wound_allocated)
    overlay.save_rolled.connect(_on_defender_save_rolled)
    overlay.allocation_complete.connect(_on_allocation_complete)

    # Add to scene (as direct child of Main for proper layering)
    var main = get_node("/root/Main")
    main.add_child(overlay)

    # Setup and show
    overlay.setup(save_data, defender_player)

func _show_spectator_overlay(save_data: Dictionary, defender_player: int):
    """Show read-only overlay for attacker"""
    # Create spectator version (simplified, non-interactive)
    var spectator = preload("res://scripts/SpectatorWoundOverlay.gd").new()

    var main = get_node("/root/Main")
    main.add_child(spectator)

    spectator.setup(save_data, defender_player)

    # Spectator receives updates via signals (same as defender)
    if current_phase:
        current_phase.wound_allocated_broadcast.connect(spectator.on_wound_allocated)
        current_phase.save_rolled_broadcast.connect(spectator.on_save_rolled)

func _on_defender_wound_allocated(model_id: String, wound_index: int):
    """Handle wound allocation from defender"""
    # Submit to host for validation and broadcast
    var action = {
        "type": "ALLOCATE_WOUND_TO_MODEL",
        "player": defender_player,
        "payload": {
            "model_id": model_id,
            "wound_index": wound_index
        }
    }

    NetworkManager.submit_action(action)

func _on_defender_save_rolled(result: Dictionary):
    """Handle save roll result"""
    # In single-player, this is local
    # In multiplayer, host validates and broadcasts

    if NetworkManager.is_networked():
        # Host will broadcast the official result
        pass
    else:
        # Single-player: apply damage locally
        _apply_wound_damage_local(result)

func _on_allocation_complete(summary: Dictionary):
    """Handle completion of wound allocation"""
    print("Wound allocation complete: ", summary)

    # Log to dice display
    if dice_log_display:
        dice_log_display.append_text(
            "[color=green]Wounds allocated: %d saved, %d failed, %d models destroyed[/color]\n" % [
                summary.saves_passed, summary.saves_failed, summary.models_destroyed
            ]
        )
```

### 6.3 Multiplayer Synchronization

**New Action Types (in ShootingPhase.gd):**

```gdscript
# Add to action_handlers dictionary

"ALLOCATE_WOUND_TO_MODEL": func(action):
    # Defender selects a model to take a wound
    var model_id = action.payload.model_id
    var wound_index = action.payload.wound_index

    # Validate selection (host-side)
    if not _validate_wound_allocation(model_id, wound_index):
        return {"success": false, "error": "Invalid model selection"}

    # Broadcast selection to all players for spectator view
    _broadcast_wound_selection(model_id, wound_index)

    # Roll save (deterministic on host)
    var save_result = _roll_save_on_host(model_id, wound_index)

    # Broadcast save result
    _broadcast_save_result(save_result)

    # Apply damage if failed
    if not save_result.saved:
        var diffs = _generate_damage_diffs(save_result)
        return {"success": true, "diffs": diffs, "save_result": save_result}

    return {"success": true, "save_result": save_result}

func _broadcast_wound_selection(model_id: String, wound_index: int):
    """Broadcast model selection to all players"""
    wound_allocated_broadcast.emit(model_id, wound_index)

func _broadcast_save_result(result: Dictionary):
    """Broadcast save roll result to all players"""
    save_rolled_broadcast.emit(result)
```

**Network Flow:**

```
DEFENDER CLIENT:
1. Clicks model → Local visual feedback (yellow flash)
2. Submit action "ALLOCATE_WOUND_TO_MODEL" to NetworkManager
3. Wait for host response

HOST:
4. Validate selection (wounded model priority check)
5. If valid:
   a. Broadcast selection to all clients (spectator update)
   b. Roll save (deterministic RNG on host)
   c. Broadcast save result to all clients
   d. Generate damage diffs
   e. Apply state update

ALL CLIENTS:
6. Receive model selection → Update highlights in spectator view
7. Receive save result → Display dice result
8. Receive state update → Update model HP/alive status
```

---

## 7. Data Structures

### 7.1 Save Data Structure (Enhanced)

```gdscript
# Returned by RulesEngine.prepare_save_resolution()
{
    "success": true,
    "wounds_to_save": 5,
    "target_unit_id": "U_BOYZ_A",
    "target_unit_name": "Ork Boyz",
    "shooter_unit_id": "U_INTERCESSORS_A",
    "weapon_name": "Bolt Rifle",
    "ap": -1,
    "damage": 1,
    "base_save": 6,
    "model_save_profiles": [
        {
            "model_id": "m1",
            "model_index": 1,
            "is_wounded": false,
            "current_wounds": 1,
            "max_wounds": 1,
            "has_cover": true,
            "save_needed": 5,  # 6+ improved to 5+ by cover, worsened to 6+ by AP-1, net 5+
            "using_invuln": false,
            "invuln_value": 0,
            "armour_value": 5
        },
        {
            "model_id": "m2",
            "model_index": 2,
            "is_wounded": true,  # Previously lost a wound
            "current_wounds": 1,
            "max_wounds": 2,
            "has_cover": false,
            "save_needed": 7,  # 6+ worsened to 7+ by AP-1
            "using_invuln": false,
            "invuln_value": 0,
            "armour_value": 7
        }
        // ... more models
    ],
    "allocation_priority": ["m2"]  # Models that MUST be allocated to first
}
```

### 7.2 Allocation Result Structure

```gdscript
# Stored for each wound in allocation_history
{
    "wound_index": 0,  # Which wound (0-4 for 5 wounds)
    "model_id": "m2",
    "model_index": 2,
    "roll": 4,
    "needed": 7,
    "saved": false,
    "damage": 1,
    "model_destroyed": true,
    "timestamp": 1234567890  # For spectator replay
}
```

### 7.3 Allocation Summary

```gdscript
# Displayed at end of allocation sequence
{
    "total_wounds": 5,
    "saves_passed": 2,
    "saves_failed": 3,
    "total_damage": 3,
    "models_destroyed": 2,
    "allocation_history": [...]  # Array of allocation_result dicts
}
```

---

## 8. State Management

### 8.1 Overlay State Machine

```gdscript
enum AllocationState {
    AWAITING_SELECTION,   # Waiting for defender to click model
    ROLLING_SAVE,         # Dice roll in progress (host-side)
    DISPLAYING_RESULT,    # Showing pass/fail (1.5s delay)
    APPLYING_DAMAGE,      # Updating game state (diffs)
    TRANSITIONING,        # Moving to next wound
    COMPLETE              # All wounds allocated
}

var current_state: AllocationState = AllocationState.AWAITING_SELECTION
```

### 8.2 Persistence for Save/Load

**Added to GameState:**

```gdscript
# New field in game state
"wound_allocation_in_progress": {
    "active": true,
    "save_data": {...},  # Full save data
    "current_wound_index": 2,  # Currently on wound #3
    "allocation_history": [...],  # History so far
    "defender_player": 1
}
```

**On Load:**
- Check if `wound_allocation_in_progress.active == true`
- If yes, re-open overlay at current_wound_index
- Replay allocation_history visually (fast-forward animation)
- Continue from where left off

---

## 9. Implementation Phases

### Phase 1: Core Sequential Allocation (Week 1-2)
**Goal**: Basic sequential workflow for single player

- [ ] Create WoundAllocationOverlay.gd (overlay UI)
- [ ] Create WoundAllocationBoardHighlights.gd (board visuals)
- [ ] Implement click detection on board models
- [ ] Add model highlights (priority vs. selectable)
- [ ] Sequential flow: select → roll → damage → next
- [ ] Basic result display with dice
- [ ] Integration with ShootingController
- [ ] Single-player testing

**Deliverables:**
- Working overlay that opens on saves_required
- Click model → roll save → apply damage → next wound
- Visual feedback on board
- Summary screen at end

### Phase 2: Multiplayer Synchronization (Week 3)
**Goal**: Real-time sync for attacker spectator view

- [ ] Add network action types (ALLOCATE_WOUND_TO_MODEL)
- [ ] Host-side validation of model selection
- [ ] Broadcast model selection to all clients
- [ ] Deterministic RNG on host for save rolls
- [ ] Create SpectatorWoundOverlay.gd (attacker view)
- [ ] Real-time highlight updates on attacker's board
- [ ] Testing with 2 players (local network)

**Deliverables:**
- Attacker sees defender's choices in real-time
- No desync issues
- Proper turn order (defender acts, then returns to attacker)

### Phase 3: Polish & Edge Cases (Week 4)
**Goal**: Production-ready quality

- [ ] Invulnerable save support (use best of armor/invuln)
- [ ] Cover detection and display in UI
- [ ] Death animations on board (fade + X marker)
- [ ] Dice roll animations (simple fade-in)
- [ ] Sound effects (click, save_passed, save_failed, model_destroyed)
- [ ] Summary statistics (total damage, models killed)
- [ ] Edge case handling:
  - All models dead mid-allocation
  - Multiple weapon assignments (sequential target resolution)
  - Multi-damage weapons (no spillover, correct handling)
- [ ] Save/load mid-allocation
- [ ] Continue Now button (skip 1.5s delay)
- [ ] Hover effects and tooltips

**Deliverables:**
- Polished, intuitive UI
- All edge cases handled
- Save/load works mid-allocation
- Ready for production

---

## 10. Testing Requirements

### 10.1 Unit Tests

**Test Cases:**
```gdscript
# test_wound_allocation_sequential.gd

func test_wounded_model_priority():
    # Given: Unit with 1 wounded model and 3 unwounded
    # When: Defender clicks unwounded model
    # Then: Selection rejected with error

func test_sequential_one_at_a_time():
    # Given: 5 wounds to allocate
    # When: Allocate wound #1
    # Then: Cannot allocate wound #2 until #1 complete

func test_no_damage_spillover():
    # Given: 3-damage attack kills 1-wound model
    # When: Damage applied
    # Then: Model dies, excess damage lost (no spillover)

func test_invuln_save_priority():
    # Given: Model has 6+ armor, 5+ invuln, AP-2 weapon
    # When: Calculate save needed
    # Then: Uses 5+ invuln (better than 8+ modified armor)

func test_save_immediate_after_selection():
    # Given: Model selected
    # When: Selection confirmed
    # Then: Save roll happens immediately (no confirmation step)

func test_auto_advance_to_next_wound():
    # Given: Save rolled and damage applied
    # When: 1.5s elapses
    # Then: Automatically start next wound allocation

func test_continue_button_skip():
    # Given: Save rolled and damage applied
    # When: User clicks "Continue Now"
    # Then: Immediately start next wound (skip delay)
```

### 10.2 Integration Tests

**Scenarios:**
1. **Full Sequential Allocation**
   - 5 wounds against 10-model unit
   - Mix of passed and failed saves
   - Verify state consistency at end
   - Verify each wound processed sequentially

2. **Multiplayer Sync**
   - Defender allocates wounds sequentially
   - Attacker sees each selection + roll in real-time
   - No desync or race conditions
   - Verify spectator view matches defender view

3. **Save/Load Mid-Allocation**
   - Allocate 2 of 5 wounds
   - Save game
   - Load game
   - Verify resume at wound #3 with correct state

4. **Multiple Weapon Targets**
   - Attacker shoots 2 different target units
   - Each target's saves resolved sequentially
   - No interference between allocations

### 10.3 UI/UX Tests

**User Testing:**
- First-time user can complete allocation without instructions
- Model highlights are clear and unambiguous (priority vs. selectable)
- Dice rolls are clear and immediate
- Spectator view is informative for attacker
- No confusion about which models are valid targets
- Summary is clear and accurate
- Overlay doesn't block critical board information

### 10.4 Edge Case Tests

**Edge Cases:**
```
1. Last model destroyed mid-allocation
   → Remaining wounds cannot be allocated (no targets)
   → Show error: "No models remaining"
   → Auto-complete with partial summary

2. All wounds saved
   → Summary shows 100% success rate
   → No damage applied

3. One-wound model, multi-damage weapon
   → Model dies, no spillover, no errors

4. Unit has invuln, armor, and cover
   → Always uses best available save

5. Click outside all models
   → No selection, no error (just ignore click)

6. Rapid clicking during delay
   → Prevent duplicate selections
```

---

## 11. Multiplayer Considerations

### 11.1 Authority Model

**Host Authority:**
- Host validates all model selections (enforce wounded priority)
- Host performs all RNG rolls (deterministic, seeded)
- Host applies all damage (via diffs)
- Host broadcasts all updates to clients

**Client Authority:**
- Defender client initiates model selection (input)
- Defender client controls timing (Continue Now button)
- All clients render highlights and animations locally

### 11.2 Network Protocol

**Messages:**

```gdscript
# 1. Host → All: Saves Required
{
    "type": "SAVES_REQUIRED",
    "save_data": {...},
    "defender_player": 1
}

# 2. Defender → Host: Model Selection
{
    "type": "SELECT_MODEL_FOR_WOUND",
    "player": 1,
    "payload": {
        "model_id": "m2",
        "wound_index": 0
    }
}

# 3. Host → All: Selection Validated & Broadcasted
{
    "type": "WOUND_MODEL_SELECTED",
    "model_id": "m2",
    "wound_index": 0
}

# 4. Host → All: Save Result
{
    "type": "WOUND_SAVE_RESULT",
    "wound_index": 0,
    "model_id": "m2",
    "roll": 4,
    "needed": 7,
    "saved": false,
    "damage": 1,
    "model_destroyed": true
}

# 5. Host → All: Damage Applied (via state diff)
{
    "type": "STATE_UPDATE",
    "diffs": [
        {"op": "set", "path": "units.U_BOYZ_A.models.2.current_wounds", "value": 0},
        {"op": "set", "path": "units.U_BOYZ_A.models.2.alive", "value": false}
    ]
}

# 6. Repeat 2-5 for each wound

# 7. Defender → Host: Allocation Complete (optional, can be inferred)
{
    "type": "WOUND_ALLOCATION_COMPLETE",
    "summary": {...}
}
```

### 11.3 Latency Handling

**Optimistic Updates:**
- Defender sees immediate local feedback (model highlight flash)
- Dice roll animation starts before host confirmation
- Roll result shown only after host validates

**Rollback on Rejection:**
```
Defender clicks invalid model (e.g., unwounded when wounded exists)
→ Local highlight flash
→ Submit to host
→ Host rejects (validation fails)
→ Show error flash: "Must select wounded model first"
→ Clear selection, reset to awaiting_selection
```

**Timeout Handling:**
```
If defender disconnects or times out (future feature):
→ Host auto-allocates remaining wounds using rules
→ Broadcast auto-allocation results
→ Continue game
```

---

## 12. Edge Cases & Special Scenarios

### 12.1 Unit Wiped Out Mid-Allocation

**Scenario**: 5 wounds to allocate, but unit only has 3 models with 1 wound each

**Handling:**
```
Wound #1 → Model dies
Wound #2 → Model dies
Wound #3 → Model dies (last model)
Wound #4 → Overlay shows: "No models remaining - allocation incomplete"
          → Automatically close overlay
          → Summary: "3/5 wounds allocated, 2 wounds lost (no targets)"
```

### 12.2 Invulnerable Saves

**Scenario**: Marine with 3+ armor and 4+ invuln, against AP-3 weapon

**Handling:**
```
Armor save: 3+ modified by AP-3 = 6+
Invuln save: 4+ (unaffected by AP)
→ System automatically uses 4+ invuln (better)
→ UI shows: "Save: 4+ (invulnerable)" in save info label
→ Dice roll compares against 4+
```

### 12.3 Multi-Damage Weapons Without Spillover

**Scenario**: Lascannon (damage 3) vs. 1-wound Guardsman

**Handling:**
```
Roll save → Failed
Apply 3 damage to Guardsman (max 1 wound)
→ Guardsman dies
→ 2 excess damage is LOST (no spillover per 10e rules and user requirement)
→ Result shows: "1 damage dealt (model destroyed)"
→ Move to next wound (no spillover to next model)
```

### 12.4 Multiple Targets Sequential Resolution

**Scenario**: Attacker shoots Boyz (5 wounds) and Grots (3 wounds)

**Handling:**
```
1. Show WoundAllocationOverlay for Boyz
2. Defender allocates all 5 wounds sequentially (5 clicks)
3. Overlay closes
4. Immediately show NEW WoundAllocationOverlay for Grots
5. Defender allocates all 3 wounds sequentially (3 clicks)
6. Both summaries shown in dice log
```

### 12.5 Save/Load During Allocation

**Scenario**: Defender saves game after allocating 2 of 5 wounds

**Save Data:**
```json
{
    "wound_allocation_in_progress": {
        "active": true,
        "save_data": {...},
        "current_wound_index": 2,
        "allocation_history": [
            {"wound_index": 0, "model_id": "m2", "saved": false, "model_destroyed": true, ...},
            {"wound_index": 1, "model_id": "m5", "saved": true, ...}
        ]
    }
}
```

**On Load:**
```
1. Detect allocation in progress
2. Re-open WoundAllocationOverlay
3. Fast-forward through wounds 0-1 (show in log: "Wound 0: m2 failed, Wound 1: m5 saved")
4. Resume at wound #2 (awaiting selection)
5. Continue normally
```

---

## 13. Success Metrics

### 13.1 Gameplay Metrics
- **Allocation Decision Time**: Average < 5 seconds per wound
- **Error Rate**: < 3% invalid model selections
- **Completion Rate**: 100% of allocations finish (no crashes/hangs)

### 13.2 Technical Metrics
- **Network Sync**: 0 desync errors in multiplayer
- **State Consistency**: 100% correct damage application
- **Performance**: < 16ms frame time during allocation (60 FPS maintained)
- **Memory**: < 50MB additional memory during allocation

### 13.3 User Experience Metrics
- **Clarity**: 90%+ users understand priority rules without help
- **Satisfaction**: 80%+ users prefer manual sequential over auto-allocation
- **Efficiency**: Average 30 seconds for 5-wound allocation (faster than batch with careful thought)

---

## 14. Open Questions & Decisions

### 14.1 Resolved

✅ **Sequential vs. Batch**: Sequential, one at a time
✅ **UI Type**: Overlay (doesn't block board)
✅ **Auto-Allocation**: No auto option - always manual
✅ **Damage Spillover**: None (no spillover for single shots)
✅ **Spectator View**: Attacker sees real-time selections and rolls
✅ **Feel No Pain**: Excluded from MVP
✅ **Model Selection**: By clicking directly on board
✅ **Confirmation**: No confirmation step - save rolls immediately after selection
✅ **Highlight Colors**: Red for priority, green for selectable, yellow for selected

### 14.2 Remaining

❓ **Death Animation Style**:
- Current design: Simple fade + X marker
- Alternative: More elaborate explosion/ragdoll?
- **Recommendation**: Simple fade for MVP, fancy animation as option later

❓ **Sound Volume**:
- Should sound effects be prominent or subtle?
- **Recommendation**: Medium volume with user control in settings

❓ **Tooltip Content**:
- What should hover tooltips show?
- Model HP, save value, cover status?
- **Recommendation**: "Model HP: X/Y, Save: Z+"

❓ **Auto-Advance Delay**:
- Current design: 1.5s delay after each save
- Alternative: User setting for delay (0.5s - 3.0s)?
- **Recommendation**: 1.5s default with "Continue Now" button to skip

❓ **Multiple Wounds to Same Model**:
- If allocating 3 wounds to same model (3W model), should all 3 allocate at once or one-by-one?
- **Recommendation**: One-by-one for consistency (each wound is a separate roll)

---

## 15. Risk Mitigation

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Model click detection fails on small bases | High | Medium | Large click radius (50px+), hover feedback, generous hitbox |
| Multiplayer latency causes frustration | High | Medium | Optimistic UI updates, loading indicators, rollback on rejection |
| Wounded model priority confusing to new users | Medium | High | Clear visual indicators (red pulsing), instruction text, error messages |
| Overlay blocks critical board info | Medium | Low | Semi-transparent background (60% opacity), small overlay size |
| Save/load mid-allocation corrupts state | High | Low | Comprehensive testing, state validation on load, rollback if invalid |
| Performance issues with many models | Medium | Low | Shader-based highlights (GPU), pooling, LOD for 20+ models |
| Sequential allocation too slow | Medium | Medium | Continue Now button, fast animations, minimal delays |

---

## 16. Dependencies

### 16.1 Existing Systems
- **RulesEngine.gd**: Save calculation, damage application, priority detection
- **GameState.gd**: Unit/model data access, state updates
- **NetworkManager.gd**: Action submission, multiplayer sync, host validation
- **ShootingController.gd**: Signal handling, dialog spawning
- **Measurement.gd**: Base sizes, distance calculations, px↔inches conversion

### 16.2 New Assets Needed

**Sounds:**
- `click_confirm.wav` - Model selected
- `save_passed.wav` - Save successful
- `save_failed.wav` - Save failed
- `model_destroyed.wav` - Model killed

**Textures:**
- `circle_highlight.png` - Base highlight circle (64×64, white)
- `death_x.png` - Death marker X (32×32, red)
- `dice_icon.png` - D6 icon (32×32)

**Shaders:**
- `model_highlight.gdshader` - Pulsing/color highlight effect

---

## 17. Migration Path

### 17.1 Backward Compatibility

**During Development:**
- Keep old SaveDialog.gd as fallback
- Add feature flag: `GameSettings.use_sequential_wound_allocation`
- If `false`: Use old batch system
- If `true`: Use new sequential system

**Rollout Plan:**
1. **Week 1-2**: New system available in dev builds
2. **Week 3**: Beta testers use new system, feedback collected
3. **Week 4**: Refinements based on feedback
4. **Week 5**: Flag defaults to `true` for all users
5. **Week 6+**: Remove old SaveDialog.gd, delete flag

### 17.2 Data Migration

**Old save files with batch allocation in progress:**
```
If load detects old format:
  → Complete allocation using old system (auto-resolve)
  → Continue to next phase
  → New allocations use sequential system
```

---

## 18. Documentation Requirements

### 18.1 User Documentation
- **Tutorial**: "How Sequential Wound Allocation Works" (video + text)
- **Rules Reference**: Link to Wahapedia wound allocation rules
- **FAQ**:
  - Why can't I select this model? (priority rule)
  - How do I speed up allocation? (Continue Now button)
  - What happens if I disconnect? (auto-completes)
- **Tooltips**: Hover over highlighted models shows "Click to allocate wound (HP: X/Y, Save: Z+)"

### 18.2 Developer Documentation
- **Architecture Doc**: WoundAllocationOverlay integration with ShootingPhase
- **Network Protocol**: Message format for multiplayer wound allocation
- **State Persistence**: Save/load format documentation
- **API Reference**: Public methods of WoundAllocationOverlay

---

## 19. Future Enhancements (Post-MVP)

### 19.1 Quality of Life
- **Variable Auto-Advance Delay**: User setting for 0.5s - 3.0s
- **Batch Mode Toggle**: Option to allocate multiple wounds at once if desired
- **Undo Last Allocation**: Roll back one wound (single-player only)
- **Fast-Forward Replay**: Quickly review allocation history
- **Model HP Bars**: Floating HP bars above models on board

### 19.2 Advanced Rules
- **Feel No Pain**: Separate roll after failed saves (6+ to ignore wound)
- **Mortal Wounds**: Bypass saves entirely
- **Damage Spillover Toggle**: Optional rule variant for custom games
- **Mixed Saves in Unit**: Characters with different saves (rare)

### 19.3 Analytics & Stats
- **Save Statistics**: Track save percentages per unit type
- **Heatmap**: Which models die most often in a unit
- **Replay System**: Watch allocation sequence again
- **Battle Report**: Export allocation summary to PDF

---

## 20. Appendix: UI Mockups

### 20.1 Model Highlight Visual Guide

```
PRIORITY HIGHLIGHT (Wounded Model - MUST SELECT):
┌─────────────────┐
│   🔴 Pulsing    │  ← Red circle, scale 1.0 → 1.15 → 1.0 (1s loop)
│   ╱▔▔▔▔▔╲       │  ← Thick border (4px), with stripes for color-blind
│  │ MODEL │      │  ← Model sprite in center
│   ╲_____╱       │
│   HP: 1/2       │  ← HP text below (orange)
│   ⚠ Priority    │  ← Status label
└─────────────────┘

SELECTABLE HIGHLIGHT (Unwounded Model - CAN SELECT):
┌─────────────────┐
│   🟢 Static     │  ← Green circle, solid (no animation)
│   ╱────╲        │  ← Thin border (2px)
│  │ MODEL │      │
│   ╲____╱        │
│   HP: 1/1       │  ← HP text below (green)
└─────────────────┘

SELECTED FLASH (Just Clicked):
┌─────────────────┐
│   🟡 Flash      │  ← Yellow flash, fade out (0.3s)
│   ╱▔▔▔▔▔╲       │  ← Thick border (5px)
│  │ MODEL │      │
│   ╲_____╱       │
│   ✓ Selected    │  ← Checkmark feedback
└─────────────────┘
```

### 20.2 Overlay Layout (Detailed)

```
┌─────────────────────────────────────────────────────────────┐
│ WoundAllocationOverlay                           [X Close]  │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ⚔️ INCOMING ATTACK                                         │
│  ═══════════════════════════════════════════                │
│  Weapon: Bolt Rifle (AP-1, Damage 1)                       │
│  Attacker: Space Marine Intercessors                        │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  🎯 ALLOCATION PROGRESS                                     │
│  ═══════════════════════════════════════════                │
│  Wound: [████░░░░░░] 2 of 5                                │
│                                                              │
│  Target: Ork Boyz (8 models alive, 2 wounded)              │
│  Save Required: 6+ (base 6+, negated by AP-1)             │
│  Cover: +1 if in terrain                                   │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  📋 INSTRUCTIONS:                                           │
│  ┌───────────────────────────────────────────────────────┐ │
│  │  Click on a model on the board to allocate wound #2  │ │
│  │                                                        │ │
│  │  ⚠️ Boy #3 is wounded - you MUST select him first!   │ │
│  └───────────────────────────────────────────────────────┘ │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│  [DICE RESULT APPEARS HERE AFTER SELECTION]                │
└─────────────────────────────────────────────────────────────┘
```

---

## 21. Version History

- **v1.0** (2025-10-13): Initial PRP (batch allocation approach)
- **v2.0** (2025-10-13): Complete rewrite for sequential allocation with board-based selection

---

## 22. Sign-off

- [ ] Product Owner
- [ ] Tech Lead
- [ ] UX Designer
- [ ] QA Lead
- [ ] Network Engineer

---

## 23. References

- **Core Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- **Damage Allocation**: Core Rules Section 19
- **Saving Throws**: Core Rules Section 18
- **Invulnerable Saves**: Core Rules Section 18.3
- **Existing PRPs**:
  - `shooting_phase_enhanced_prp.md` - Shooting mechanics
  - `saves_and_damage_allocation_prp.md` - Original save system (batch, to be deprecated)
