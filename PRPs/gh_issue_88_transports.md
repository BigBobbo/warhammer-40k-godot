# PRP: Transport System Implementation
**GitHub Issue:** #88
**Feature Name:** Transports
**Author:** Claude Code AI
**Date:** 2025-09-27
**Confidence Score:** 8/10

## Problem Statement

Vehicles in Warhammer 40k can transport troops, allowing units to embark within them and move across the battlefield protected. The game currently has no transport mechanics implemented, requiring a comprehensive system for embarking, disembarking, transport capacity management, and firing deck functionality.

## Requirements Analysis

### Core Requirements (from GitHub Issue #88):

#### Deployment Phase:
1. Units can begin the game deployed within a transport if sufficient space
2. Pop-up panel when deploying transport to select units to embark
3. Checkbox selection for units with capacity validation
4. Deployed embarked units count as deployed (removed from deployment panel)

#### Movement Phase (Already Embarked):
1. Pop-up asking "Do you want to disembark?" when selecting embarked unit
2. Disembark units wholly within 3" of transport, not in Engagement Range
3. Movement restrictions based on transport's prior movement:
   - If transport moved: disembarked unit cannot move or charge
   - If transport hasn't moved: disembarked unit can move normally
4. Cannot disembark from transport that Advanced or Fell Back

#### Movement Phase (Not Embarked):
1. Units ending Normal/Advance/Fall Back move within 3" of friendly transport can embark
2. Prompt to embark if within range and space available
3. Remove embarked units from board until disembark
4. Cannot embark if already disembarked same phase

#### Firing Deck:
1. Some transports have 'Firing Deck x' ability
2. Select up to 'x' embarked models to shoot through transport
3. Transport counts as equipped with selected weapons
4. Selected models' units cannot shoot again that phase

### Warhammer 40k Transport Rules:
- **Transport Capacity**: Listed on datasheet (e.g., "22 ORKS INFANTRY models")
- **Embark/Disembark Restrictions**: Phase and movement-based limitations
- **Firing Deck**: Allows limited shooting from embarked units
- **Destroyed Transport**: Rules for emergency disembark (not in initial scope)

## Current System Analysis

### Existing Transport References:
Found in army JSON files (/Users/robertocallaghan/Documents/claude/godotv2/40k/armies/orks.json):
```json
{
  "name": "Battlewagon",
  "keywords": ["VEHICLE", "TRANSPORT"],
  "abilities": [
    {
      "name": "TRANSPORT",
      "description": "This model has a transport capacity of 22 ORKS INFANTRY models..."
    },
    {
      "name": "FIRING DECK",
      "description": "Firing Deck 22: Each time this TRANSPORT shoots..."
    }
  ]
}
```

### Key Architecture Patterns to Follow:

#### Action-Based Phase System:
```gdscript
# From MovementPhase.gd pattern
const ACTIONS = {
  EMBARK_UNIT = "embark_unit",
  DISEMBARK_UNIT = "disembark_unit",
  CONFIRM_EMBARK = "confirm_embark",
  CONFIRM_DISEMBARK = "confirm_disembark"
}

func validate_action(action: Dictionary) -> Dictionary:
  match action.type:
    ACTIONS.EMBARK_UNIT:
      return _validate_embark(action)
```

#### State Structure Addition:
```gdscript
# Add to unit state structure
"transport_data": {
  "capacity": 22,  # From datasheet
  "capacity_type": "ORKS INFANTRY",  # Keywords required
  "embarked_units": [],  # Array of unit IDs
  "firing_deck": 22  # Number of models that can fire
},
"embarked_in": null  # Transport unit ID if embarked
```

#### Dialog Pattern (from SaveLoadDialog.gd):
```gdscript
extends AcceptDialog

signal embark_confirmed(units: Array)

func show_embark_dialog(transport_id: String, available_units: Array):
  self.title = "Select Units to Embark"
  # Add checkboxes for each unit
  popup_centered()
```

## Technical Research

### Godot UI Dialog Implementation:
- **AcceptDialog**: Base class for modal dialogs (https://docs.godotengine.org/en/4.4/classes/class_acceptdialog.html)
- **ItemList/Tree**: For unit selection with checkboxes
- **Signal Pattern**: For dialog responses

### Movement Validation Pattern (from MovementPhase.gd:595-650):
```gdscript
func _validate_model_position(unit_id: String, model_idx: int, new_pos: Vector2) -> Dictionary:
  # Check engagement range
  # Check terrain collision
  # Check model overlap
  return {"valid": true/false, "reason": "error message"}
```

### UI Panel Creation (from Main.gd patterns):
```gdscript
func _create_transport_panel(unit_data: Dictionary) -> PanelContainer:
  var panel = PanelContainer.new()
  var vbox = VBoxContainer.new()
  # Add embarked units list
  # Add capacity display
  return panel
```

## Implementation Strategy

### Phase 1: Core Data Structures

#### 1.1 Enhance Unit State (GameState.gd)
```gdscript
# Add to unit structure
"transport_data": {
  "capacity": 0,  # Total capacity
  "capacity_keywords": [],  # Required keywords for embarking
  "embarked_units": [],  # Unit IDs currently embarked
  "firing_deck": 0  # Number of models that can fire
},
"embarked_in": null,  # Transport unit_id if embarked
"disembarked_this_phase": false  # Track disembark status
```

#### 1.2 Transport Manager (New: /40k/autoloads/TransportManager.gd)
```gdscript
extends Node

signal embark_requested(transport_id: String, unit_id: String)
signal disembark_requested(transport_id: String, unit_id: String)

func can_embark(unit_id: String, transport_id: String) -> Dictionary:
  var unit = GameState.get_unit(unit_id)
  var transport = GameState.get_unit(transport_id)

  # Check capacity
  var current_count = _get_embarked_model_count(transport_id)
  var unit_model_count = unit.models.filter(func(m): return m.alive).size()

  if current_count + unit_model_count > transport.transport_data.capacity:
    return {"valid": false, "reason": "Insufficient capacity"}

  # Check keywords
  if not _has_required_keywords(unit, transport.transport_data.capacity_keywords):
    return {"valid": false, "reason": "Unit type cannot embark"}

  # Check if already disembarked
  if unit.get("disembarked_this_phase", false):
    return {"valid": false, "reason": "Already disembarked this phase"}

  return {"valid": true}

func embark_unit(unit_id: String, transport_id: String) -> void:
  var changes = [
    {"op": "set", "path": "units.%s.embarked_in" % unit_id, "value": transport_id},
    {"op": "append", "path": "units.%s.transport_data.embarked_units" % transport_id, "value": unit_id},
    {"op": "set", "path": "units.%s.visible" % unit_id, "value": false}
  ]
  GameState.apply_state_changes(changes)

func disembark_unit(unit_id: String, positions: Array) -> void:
  var transport_id = GameState.get_unit(unit_id).embarked_in
  var changes = []

  # Update positions for all models
  for i in range(positions.size()):
    changes.append({
      "op": "set",
      "path": "units.%s.models.%d.position" % [unit_id, i],
      "value": {"x": positions[i].x, "y": positions[i].y}
    })

  # Clear embark status
  changes.append({"op": "set", "path": "units.%s.embarked_in" % unit_id, "value": null})
  changes.append({"op": "set", "path": "units.%s.visible" % unit_id, "value": true})
  changes.append({"op": "set", "path": "units.%s.disembarked_this_phase" % unit_id, "value": true})

  # Remove from transport
  var embarked = GameState.get_unit(transport_id).transport_data.embarked_units
  embarked.erase(unit_id)
  changes.append({
    "op": "set",
    "path": "units.%s.transport_data.embarked_units" % transport_id,
    "value": embarked
  })

  GameState.apply_state_changes(changes)
```

### Phase 2: Deployment Phase Integration

#### 2.1 Transport Selection Dialog (New: /40k/scripts/TransportEmbarkDialog.gd)
```gdscript
extends AcceptDialog

signal units_selected(unit_ids: Array)

var transport_id: String
var available_units: Array = []
var selected_units: Array = []
var capacity: int = 0
var checkboxes: Dictionary = {}

func setup(p_transport_id: String, p_available_units: Array):
  transport_id = p_transport_id
  available_units = p_available_units
  var transport = GameState.get_unit(transport_id)
  capacity = transport.transport_data.capacity

  title = "Select Units to Deploy in %s" % transport.meta.name

  # Clear previous content
  for child in $VBoxContainer.get_children():
    child.queue_free()

  var vbox = $VBoxContainer

  # Capacity label
  var cap_label = Label.new()
  cap_label.text = "Transport Capacity: %d models" % capacity
  vbox.add_child(cap_label)

  # Unit checkboxes
  for unit in available_units:
    var hbox = HBoxContainer.new()

    var checkbox = CheckBox.new()
    checkbox.text = "%s (%d models)" % [unit.meta.name, unit.models.size()]
    checkbox.toggled.connect(_on_unit_toggled.bind(unit.id))
    checkboxes[unit.id] = checkbox
    hbox.add_child(checkbox)

    vbox.add_child(hbox)

  # Confirm button
  get_ok_button().text = "Confirm Embarkation"
  get_ok_button().pressed.connect(_on_confirm)

func _on_unit_toggled(pressed: bool, unit_id: String):
  if pressed:
    selected_units.append(unit_id)
  else:
    selected_units.erase(unit_id)

  # Validate capacity
  var total_models = 0
  for id in selected_units:
    var unit = available_units.filter(func(u): return u.id == id)[0]
    total_models += unit.models.size()

  if total_models > capacity:
    checkboxes[unit_id].set_pressed_no_signal(false)
    selected_units.erase(unit_id)
    OS.alert("Exceeds transport capacity!")

func _on_confirm():
  emit_signal("units_selected", selected_units)
  hide()
```

#### 2.2 Modify DeploymentPhase.gd
```gdscript
# Add to process_action()
func process_action(action: Dictionary) -> void:
  match action.type:
    "DEPLOY_UNIT":
      # After deploying transport, check for embark dialog
      if _unit_has_transport_capacity(action.unit_id):
        _show_embark_dialog(action.unit_id)
    "EMBARK_DEPLOYMENT":
      _process_deployment_embark(action)

func _show_embark_dialog(transport_id: String):
  var dialog = preload("res://scripts/TransportEmbarkDialog.gd").new()
  var available = _get_available_units_for_embark(transport_id)
  dialog.setup(transport_id, available)
  dialog.units_selected.connect(_on_deployment_embark_selected.bind(transport_id))
  get_tree().root.add_child(dialog)
  dialog.popup_centered()

func _on_deployment_embark_selected(unit_ids: Array, transport_id: String):
  for unit_id in unit_ids:
    TransportManager.embark_unit(unit_id, transport_id)
    # Mark as deployed
    var changes = [
      {"op": "set", "path": "units.%s.status" % unit_id, "value": "DEPLOYED"}
    ]
    GameState.apply_state_changes(changes)
```

### Phase 3: Movement Phase Integration

#### 3.1 Disembark Dialog (New: /40k/scripts/DisembarkDialog.gd)
```gdscript
extends ConfirmationDialog

signal disembark_confirmed()
signal disembark_cancelled()

var unit_id: String
var transport_id: String
var transport_moved: bool = false

func setup(p_unit_id: String):
  unit_id = p_unit_id
  var unit = GameState.get_unit(unit_id)
  transport_id = unit.embarked_in
  var transport = GameState.get_unit(transport_id)
  transport_moved = transport.flags.get("moved", false)

  title = "Disembark Unit"
  dialog_text = "Do you want to disembark %s from %s?" % [
    unit.meta.name,
    transport.meta.name
  ]

  if transport_moved:
    dialog_text += "\n\nNote: The transport has already moved. This unit will not be able to move or charge this turn."

  get_ok_button().text = "Disembark"
  get_cancel_button().text = "Stay Embarked"

func _on_confirmed():
  emit_signal("disembark_confirmed")

func _on_cancelled():
  emit_signal("disembark_cancelled")
```

#### 3.2 Disembark Controller (New: /40k/scripts/DisembarkController.gd)
```gdscript
extends Node2D

signal disembark_completed(unit_id: String, positions: Array)
signal disembark_cancelled(unit_id: String)

var unit_id: String
var transport_id: String
var model_positions: Array = []
var ghost_visuals: Array = []
var current_model_idx: int = 0
var transport_position: Vector2

func start_disembark(p_unit_id: String):
  unit_id = p_unit_id
  var unit = GameState.get_unit(unit_id)
  transport_id = unit.embarked_in
  var transport = GameState.get_unit(transport_id)

  # Get transport position (average of all models)
  transport_position = _calculate_transport_center(transport)

  # Initialize positions array
  model_positions.clear()
  for i in range(unit.models.size()):
    model_positions.append(Vector2.ZERO)

  # Create first ghost
  _create_ghost_for_model(0)

  set_process_unhandled_input(true)

func _create_ghost_for_model(idx: int):
  var unit = GameState.get_unit(unit_id)
  var model = unit.models[idx]

  var ghost = preload("res://scripts/GhostVisual.gd").new()
  ghost.radius = Measurement.base_radius_px(model.base_mm)
  ghost.owner_player = unit.owner
  ghost.set_model_data(model)
  add_child(ghost)
  ghost_visuals.append(ghost)

func _validate_disembark_position(pos: Vector2) -> Dictionary:
  # Must be within 3" of transport
  var dist_inches = Measurement.distance_inches(pos, transport_position)
  if dist_inches > 3.0:
    return {"valid": false, "reason": "Must be within 3\" of transport"}

  # Cannot be in engagement range
  for enemy_unit in GameState.get_enemy_units():
    if enemy_unit.embarked_in:
      continue  # Skip embarked units
    for model in enemy_unit.models:
      if not model.alive:
        continue
      var model_pos = Vector2(model.position.x, model.position.y)
      if Measurement.distance_inches(pos, model_pos) <= 1.0:
        return {"valid": false, "reason": "Cannot disembark within Engagement Range"}

  # Check for overlaps
  if BoardState.check_model_overlap_at_position(pos, unit_id, current_model_idx):
    return {"valid": false, "reason": "Model would overlap"}

  return {"valid": true}

func _unhandled_input(event: InputEvent):
  if event is InputEventMouseButton:
    if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
      var world_pos = get_global_mouse_position()
      var validation = _validate_disembark_position(world_pos)

      if validation.valid:
        model_positions[current_model_idx] = world_pos
        current_model_idx += 1

        if current_model_idx >= model_positions.size():
          _complete_disembark()
        else:
          _create_ghost_for_model(current_model_idx)
      else:
        OS.alert(validation.reason)

  elif event is InputEventMouseMotion:
    if ghost_visuals.size() > 0:
      var world_pos = get_global_mouse_position()
      var ghost = ghost_visuals[-1]
      ghost.position = world_pos
      var validation = _validate_disembark_position(world_pos)
      ghost.set_validity(validation.valid)

func _complete_disembark():
  emit_signal("disembark_completed", unit_id, model_positions)
  _cleanup()

func _cleanup():
  for ghost in ghost_visuals:
    ghost.queue_free()
  ghost_visuals.clear()
  set_process_unhandled_input(false)
```

#### 3.3 Modify MovementPhase.gd
```gdscript
# Add new actions
const ACTIONS = {
  # ... existing actions ...
  CHECK_DISEMBARK = "check_disembark",
  START_DISEMBARK = "start_disembark",
  CONFIRM_DISEMBARK = "confirm_disembark",
  CHECK_EMBARK = "check_embark",
  CONFIRM_EMBARK = "confirm_embark"
}

# In SELECT_UNIT action handler
func process_action(action: Dictionary) -> void:
  match action.type:
    ACTIONS.SELECT_UNIT:
      var unit = GameState.get_unit(action.unit_id)
      if unit.embarked_in:
        # Show disembark dialog
        _show_disembark_dialog(action.unit_id)
      else:
        # Normal movement selection
        _process_normal_selection(action)

    ACTIONS.CONFIRM_UNIT_MOVE:
      # After confirming move, check for embark opportunity
      _check_embark_opportunity(action.unit_id)

func _show_disembark_dialog(unit_id: String):
  var dialog = preload("res://scripts/DisembarkDialog.gd").new()
  dialog.setup(unit_id)
  dialog.disembark_confirmed.connect(_on_disembark_confirmed.bind(unit_id))
  dialog.disembark_cancelled.connect(_on_disembark_cancelled.bind(unit_id))
  get_tree().root.add_child(dialog)
  dialog.popup_centered()

func _on_disembark_confirmed(unit_id: String):
  var controller = preload("res://scripts/DisembarkController.gd").new()
  controller.disembark_completed.connect(_on_disembark_completed)
  controller.disembark_cancelled.connect(_on_disembark_cancelled)
  get_tree().root.add_child(controller)
  controller.start_disembark(unit_id)

func _on_disembark_completed(unit_id: String, positions: Array):
  TransportManager.disembark_unit(unit_id, positions)

  # Apply movement restrictions if transport moved
  var unit = GameState.get_unit(unit_id)
  var transport = GameState.get_unit(unit.embarked_in)
  if transport.flags.get("moved", false):
    var changes = [
      {"op": "set", "path": "units.%s.flags.cannot_move" % unit_id, "value": true},
      {"op": "set", "path": "units.%s.flags.cannot_charge" % unit_id, "value": true}
    ]
    GameState.apply_state_changes(changes)

func _check_embark_opportunity(unit_id: String):
  var unit = GameState.get_unit(unit_id)
  var unit_pos = _get_unit_center_position(unit_id)

  # Find transports within 3"
  for transport_id in GameState.get_player_units(unit.owner):
    var transport = GameState.get_unit(transport_id)
    if not transport.meta.keywords.has("TRANSPORT"):
      continue

    var transport_pos = _get_unit_center_position(transport_id)
    var dist = Measurement.distance_inches(unit_pos, transport_pos)

    if dist <= 3.0:
      var can_embark = TransportManager.can_embark(unit_id, transport_id)
      if can_embark.valid:
        _show_embark_prompt(unit_id, transport_id)
        break

func _show_embark_prompt(unit_id: String, transport_id: String):
  var dialog = ConfirmationDialog.new()
  var unit = GameState.get_unit(unit_id)
  var transport = GameState.get_unit(transport_id)

  dialog.title = "Embark Unit"
  dialog.dialog_text = "Do you want to embark %s into %s?" % [
    unit.meta.name,
    transport.meta.name
  ]

  dialog.get_ok_button().text = "Embark"
  dialog.get_cancel_button().text = "Stay Deployed"

  dialog.confirmed.connect(func():
    TransportManager.embark_unit(unit_id, transport_id)
    dialog.queue_free()
  )

  dialog.cancelled.connect(func():
    dialog.queue_free()
  )

  get_tree().root.add_child(dialog)
  dialog.popup_centered()
```

### Phase 4: Firing Deck Implementation

#### 4.1 Modify ShootingPhase.gd
```gdscript
# Add to shooting selection
func _get_eligible_shooters() -> Array:
  var shooters = []
  var player = GameState.get_active_player()

  for unit_id in GameState.get_player_units(player):
    var unit = GameState.get_unit(unit_id)

    # Skip embarked units (they shoot through transport)
    if unit.embarked_in:
      continue

    # Add transport with firing deck
    if unit.transport_data.firing_deck > 0 and unit.transport_data.embarked_units.size() > 0:
      shooters.append(unit_id)

    # Normal shooting units
    if not unit.flags.get("has_shot", false):
      shooters.append(unit_id)

  return shooters

func _process_transport_shooting(transport_id: String):
  var transport = GameState.get_unit(transport_id)
  var firing_deck_count = transport.transport_data.firing_deck

  # Get embarked units that haven't shot
  var eligible_embarked = []
  for unit_id in transport.transport_data.embarked_units:
    var unit = GameState.get_unit(unit_id)
    if not unit.flags.get("has_shot", false):
      eligible_embarked.append(unit_id)

  if eligible_embarked.is_empty():
    return

  # Show firing deck selection dialog
  _show_firing_deck_dialog(transport_id, eligible_embarked, firing_deck_count)

func _show_firing_deck_dialog(transport_id: String, embarked_units: Array, max_models: int):
  var dialog = preload("res://scripts/FiringDeckDialog.gd").new()
  dialog.setup(transport_id, embarked_units, max_models)
  dialog.models_selected.connect(_on_firing_deck_selected.bind(transport_id))
  get_tree().root.add_child(dialog)
  dialog.popup_centered()

func _on_firing_deck_selected(selected_weapons: Array, transport_id: String):
  # Add selected weapons to transport temporarily
  phase_state["firing_deck_weapons"][transport_id] = selected_weapons

  # Mark those units as having shot
  for weapon_data in selected_weapons:
    var changes = [
      {"op": "set", "path": "units.%s.flags.has_shot" % weapon_data.unit_id, "value": true}
    ]
    GameState.apply_state_changes(changes)
```

### Phase 5: UI Integration

#### 5.1 Transport Status Panel (Add to Main.gd)
```gdscript
func _create_transport_panel(unit_id: String) -> PanelContainer:
  var unit = GameState.get_unit(unit_id)
  if not unit.meta.keywords.has("TRANSPORT"):
    return null

  var panel = PanelContainer.new()
  var vbox = VBoxContainer.new()
  panel.add_child(vbox)

  # Transport header
  var header = Label.new()
  header.text = "Transport Status"
  header.add_theme_style_override("font", preload("res://fonts/bold.tres"))
  vbox.add_child(header)

  # Capacity display
  var capacity_label = Label.new()
  var used = _count_embarked_models(unit_id)
  var total = unit.transport_data.capacity
  capacity_label.text = "Capacity: %d / %d" % [used, total]
  vbox.add_child(capacity_label)

  # Embarked units list
  if unit.transport_data.embarked_units.size() > 0:
    var sep = HSeparator.new()
    vbox.add_child(sep)

    var embarked_label = Label.new()
    embarked_label.text = "Embarked Units:"
    vbox.add_child(embarked_label)

    for embarked_id in unit.transport_data.embarked_units:
      var embarked_unit = GameState.get_unit(embarked_id)
      var unit_label = Label.new()
      unit_label.text = "• %s" % embarked_unit.meta.name
      vbox.add_child(unit_label)

  return panel
```

## Validation Plan

### Unit Tests:
```bash
# Create test file: 40k/tests/unit/test_transport_system.gd
extends GutTest

func test_embark_capacity_check():
  var transport = _create_test_transport(capacity=10)
  var unit = _create_test_unit(model_count=5)
  var result = TransportManager.can_embark(unit.id, transport.id)
  assert_true(result.valid)

  var large_unit = _create_test_unit(model_count=15)
  result = TransportManager.can_embark(large_unit.id, transport.id)
  assert_false(result.valid)
  assert_eq(result.reason, "Insufficient capacity")

func test_disembark_range_validation():
  var controller = DisembarkController.new()
  controller.transport_position = Vector2(0, 0)

  # Within 3"
  var result = controller._validate_disembark_position(Vector2(2.5 * 48, 0))
  assert_true(result.valid)

  # Outside 3"
  result = controller._validate_disembark_position(Vector2(3.5 * 48, 0))
  assert_false(result.valid)
  assert_eq(result.reason, "Must be within 3\" of transport")

func test_movement_restrictions_after_disembark():
  var transport = _create_test_transport()
  var unit = _create_test_unit()

  # Transport moves first
  GameState.apply_state_changes([
    {"op": "set", "path": "units.%s.flags.moved" % transport.id, "value": true}
  ])

  # Disembark unit
  TransportManager.disembark_unit(unit.id, [Vector2(100, 100)])

  # Check restrictions
  var updated_unit = GameState.get_unit(unit.id)
  assert_true(updated_unit.flags.cannot_move)
  assert_true(updated_unit.flags.cannot_charge)

# Run with:
godot --headless -s 40k/tests/unit/test_transport_system.gd
```

### Integration Tests:
```bash
# Create test file: 40k/tests/phases/test_transport_integration.gd
extends GutTest

func test_deployment_embark_flow():
  # Deploy transport
  # Show embark dialog
  # Select units
  # Verify embarked state
  pass

func test_movement_disembark_flow():
  # Select embarked unit
  # Confirm disembark
  # Place models
  # Verify positions and restrictions
  pass

func test_firing_deck_flow():
  # Select transport with embarked units
  # Select firing deck models
  # Verify weapons added to transport
  # Verify units marked as shot
  pass
```

## Implementation Tasks (In Order)

1. **Core Data Structures** (/40k/autoloads/GameState.gd)
   - Add transport_data to unit structure
   - Add embarked_in field
   - Add disembarked_this_phase flag

2. **Transport Manager** (New: /40k/autoloads/TransportManager.gd)
   - Implement can_embark validation
   - Create embark_unit function
   - Create disembark_unit function
   - Add capacity checking utilities

3. **Deployment Embark Dialog** (New: /40k/scripts/TransportEmbarkDialog.gd)
   - Create AcceptDialog-based UI
   - Add unit checkboxes with capacity validation
   - Connect signals for confirmation

4. **Deployment Phase Integration** (/40k/phases/DeploymentPhase.gd)
   - Add transport detection after deployment
   - Show embark dialog for transports
   - Process embark selections
   - Mark embarked units as deployed

5. **Disembark Dialog** (New: /40k/scripts/DisembarkDialog.gd)
   - Create confirmation dialog
   - Show movement restrictions warning
   - Connect confirmation signals

6. **Disembark Controller** (New: /40k/scripts/DisembarkController.gd)
   - Handle model-by-model placement
   - Validate 3" range from transport
   - Check engagement range restrictions
   - Create ghost visuals for placement

7. **Movement Phase Integration** (/40k/phases/MovementPhase.gd)
   - Detect embarked units on selection
   - Show disembark dialog
   - Handle disembark placement
   - Check embark opportunities after movement
   - Apply movement/charge restrictions

8. **Shooting Phase Firing Deck** (/40k/phases/ShootingPhase.gd)
   - Detect transports with firing deck
   - Create weapon selection dialog
   - Add selected weapons to transport
   - Mark embarked units as having shot

9. **UI Integration** (/40k/scripts/Main.gd)
   - Add transport status panel
   - Show capacity and embarked units
   - Update when units embark/disembark

10. **Testing**
    - Create unit tests for validation logic
    - Test capacity calculations
    - Test range validations
    - Integration tests for full flows

## External Documentation References

- **Warhammer 40k Transport Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#Transports
- **Godot AcceptDialog**: https://docs.godotengine.org/en/4.4/classes/class_acceptdialog.html
- **Godot ConfirmationDialog**: https://docs.godotengine.org/en/4.4/classes/class_confirmationdialog.html
- **Godot Signals**: https://docs.godotengine.org/en/4.4/getting_started/step_by_step/signals.html

## Risk Mitigation

1. **Complex State Management**: Use atomic state changes through GameState.apply_state_changes()
2. **UI Complexity**: Follow existing dialog patterns from SaveLoadDialog.gd
3. **Movement Validation**: Reuse existing validation functions from MovementPhase
4. **Save/Load Compatibility**: Ensure embarked state is properly serialized

## Success Criteria

1. Units can be deployed inside transports during deployment
2. Embarked units can disembark within 3" during movement
3. Movement/charge restrictions apply correctly after disembark
4. Units can embark during movement if within range
5. Firing deck allows shooting through transport
6. UI clearly shows transport capacity and contents
7. All validations prevent illegal moves
8. Save/load preserves transport state

## Confidence Assessment: 8/10

High confidence due to:
- Clear requirements from issue description
- Excellent existing patterns in codebase for phases and actions
- Strong validation system already in place
- Dialog patterns exist to follow

Moderate uncertainty around:
- Exact UI/UX flow preferences
- Interaction with other complex systems (line of sight, terrain)
- Performance with many embarked units
- Edge cases in rule interactions

## Notes for AI Agent

This PRP provides comprehensive context for implementing the transport system. Key points:

1. **Follow existing patterns**: The codebase has excellent patterns for phase actions, state management, and UI. Study the MovementPhase and DeploymentPhase carefully.

2. **Use atomic state changes**: Always use GameState.apply_state_changes() with proper operation structures.

3. **Test incrementally**: Build and test each component before moving to the next. The transport system touches many phases.

4. **Validation is critical**: Ensure all game rules are enforced (3" range, engagement range, capacity limits).

5. **UI consistency**: Match the existing UI patterns for dialogs and panels. Look at SaveLoadDialog.gd for dialog examples.

6. **Signal-based communication**: Use Godot signals for loose coupling between components.

The implementation should be done in the order listed in the tasks section, as each builds on the previous. Start with data structures, then the manager, then integrate with phases.