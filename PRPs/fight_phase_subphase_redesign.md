# Fight Phase Subphase Redesign - Implementation PRP

## Problem Statement

The current fight phase implementation lacks proper subphase structure and alternating activation mechanics required by Warhammer 40k 10th edition rules. The fight phase should be split into two distinct subphases with proper player alternation and clear UI feedback.

### Current State Issues

Based on analysis in `/Users/robertocallaghan/Documents/claude/godotv2/PRPs/fight_phase_analysis.md`:
- **BLOCKING BUG**: GameManager doesn't register modern fight action types (only legacy actions)
- No subphase structure (Fights First vs Remaining Combats)
- No alternating activation between players
- No clear UI showing fight sequence and whose turn it is
- No confirmation dialogs between activation steps

## Implementation Blueprint

### Solution Approach

Implement a comprehensive two-subphase fight system with:
1. **Fights First Subphase**: Units that charged or have Fights First ability
2. **Remaining Combats Subphase**: All other eligible units
3. **Alternating Activation**: Defending player selects first, then players alternate
4. **Sequential Confirmation**: Pile-in → Attack Assignment → Consolidate with dialog confirmations
5. **Automatic Progression**: Seamless transition between subphases

### Critical Context for Implementation

#### Official Warhammer 40k 10th Edition Rules

**Fight Phase Structure** (from web research 2025):
- Split into TWO steps: "Fights First" and "Remaining Combats"
- **Players alternate** unit selection in each step
- **Defending player** (non-active player) selects first unit in each step
- Units with Fights First ability or that charged fight in Fights First step
- Players MUST select a unit if they have eligible units
- If one player has no eligible units, other player continues selecting

**Each Unit Activation**:
1. **Pile In**: Move up to 3" toward closest enemy model
2. **Make Melee Attacks**: Hit rolls (WS) → Wound rolls → Saves → Damage
3. **Consolidate**: Move up to 3" toward closest enemy model

**Key Rules**:
- Only units within 1" horizontal engagement range can fight
- Movement must be toward closest enemy model
- All eligible units must fight (no skipping)

#### Existing Codebase Patterns to Follow

**1. Modal Dialog Pattern** (from WeaponOrderDialog.gd and NextWeaponDialog.gd):

```gdscript
extends AcceptDialog

signal dialog_confirmed(payload: Dictionary)

var phase_reference = null
var dialog_data = {}

func setup(data: Dictionary, phase) -> void:
    dialog_data = data
    phase_reference = phase
    _build_ui()

    # Connect to phase signals for real-time updates
    if phase.has_signal("dice_rolled"):
        phase.dice_rolled.connect(_on_dice_rolled)

func _build_ui() -> void:
    # Create UI programmatically
    var container = VBoxContainer.new()
    # ... add controls
    add_child(container)

func _on_confirm_pressed() -> void:
    emit_signal("dialog_confirmed", get_dialog_result())
    queue_free()
```

**Pattern Usage**:
- Extend AcceptDialog for modals
- setup() method receives context and phase reference
- Build UI programmatically in setup or _build_ui
- Connect to phase signals for live updates
- Emit signal + queue_free() when done

**2. Phase Signal Communication** (from ShootingPhase.gd:7-11):

```gdscript
signal dice_rolled(dice_data: Dictionary)
signal weapon_order_required(assignments: Array)
signal next_weapon_confirmation_required(data: Dictionary)
signal saves_required(wounds: Array, target_id: String)
signal shooting_complete()
```

**Pattern**: Phases emit signals for UI events; controllers/dialogs connect and respond

**3. Sequential Resolution with Dialogs** (from ShootingPhase.gd):

```gdscript
# After confirming targets
if weapon_count >= 2:
    emit_signal("weapon_order_required", assignments)
    # WeaponOrderDialog appears
    # Player reorders weapons
    # Dialog emits weapon_order_confirmed
    # Phase receives signal and continues

# After each weapon resolves
emit_signal("next_weapon_confirmation_required", {
    "remaining_weapons": remaining,
    "current_index": index,
    "last_result": result
})
# NextWeaponDialog appears
# Player clicks Continue or Complete
# Phase proceeds to next weapon or completes
```

**Pattern**: Pause at natural break points, show modal, wait for confirmation, continue

**4. Multiplayer Action Flow** (from GameManager.gd and NetworkManager.gd):

```gdscript
# GameManager.gd - Action delegation
func process_action(action):
    match action.type:
        "SELECT_SHOOTER", "CONFIRM_TARGETS":
            return _delegate_to_current_phase(action)

func _delegate_to_current_phase(action):
    var current_phase = PhaseManager.get_current_phase_instance()
    return current_phase.execute_action(action)

# Phase returns result with diffs
result = {
    "success": true,
    "changes": [
        {"op": "set", "path": "units.U_A.position", "value": Vector2(100, 200)}
    ],
    "dice": [...],
    "log_text": "Unit attacked..."
}

# NetworkManager broadcasts result to clients
# Both host and clients create same dialogs from result data
```

**CRITICAL**: GameManager must register all fight action types or it will fail in multiplayer!

**5. State Tracking** (from FightPhase.gd current implementation):

```gdscript
# Phase-level state
var active_fighter_id: String = ""
var fight_sequence: Array = []  # Ordered unit IDs
var current_fight_index: int = 0
var units_that_fought: Array = []

# Subphase state (NEW)
var current_subphase: String = "FIGHTS_FIRST"  # or "REMAINING_COMBATS"
var fights_first_sequence: Dictionary = {"1": [], "2": []}  # Player -> [unit_ids]
var normal_sequence: Dictionary = {"1": [], "2": []}
var current_subphase_player: int = 1  # Which player selects next
```

**6. Unit Flag Tracking** (from GameState):

```gdscript
# Unit flags structure
unit.flags = {
    "charged_this_turn": false,  # Set by ChargePhase
    "fights_first": false,  # From abilities
    "fights_last": false,  # From debuffs
    "has_fought": false,  # Set during FightPhase
}

# Set flag in action result
changes.append({
    "op": "set",
    "path": "units.%s.flags.has_fought" % unit_id,
    "value": true
})
```

#### Files to Create/Modify

**Create New Files**:
1. `40k/dialogs/FightSelectionDialog.gd` - Main fight sequence selection modal
2. `40k/dialogs/PileInDialog.gd` - Pile-in movement confirmation
3. `40k/dialogs/AttackAssignmentDialog.gd` - Weapon and target selection
4. `40k/dialogs/ConsolidateDialog.gd` - Consolidate movement confirmation
5. `40k/tests/unit/test_fight_subphases.gd` - Subphase logic tests
6. `40k/tests/integration/test_fight_phase_full_flow.gd` - Complete activation tests

**Modify Existing Files**:
1. `40k/phases/FightPhase.gd` - Add subphase logic and dialog signals
2. `40k/scripts/FightController.gd` - Connect to new dialogs and signals
3. `40k/scripts/GameManager.gd` - **CRITICAL**: Register all fight action types
4. `40k/autoloads/RulesEngine.gd` - Add subphase sequencing helpers
5. `40k/scripts/Main.gd` - Connect fight dialogs to phase

#### External Documentation References

- **Warhammer 40k Core Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#FIGHT-PHASE
  - Fight phase structure: Fights First → Remaining Combats
  - Alternating activation: Defending player selects first
  - Unit activation sequence: Pile In → Fight → Consolidate

- **10th Edition Fight Rules**: https://spikeybits.com/10th-edition-40k-core-rules-charge-fight-phases/
  - Detailed explanation of alternating activation
  - Fights First priority system
  - Player must select if they have eligible units

- **Godot 4.4 AcceptDialog**: https://docs.godotengine.org/en/4.4/classes/class_acceptdialog.html
  - popup_centered() to show modal
  - confirmed signal when OK pressed
  - Custom buttons via add_button()

- **Godot 4.4 Signals**: https://docs.godotengine.org/en/4.4/getting_started/step_by_step/signals.html
  - Signal emission: `signal_name.emit(args)`
  - Connection: `signal.connect(callable)`
  - Disconnection safety checks

## Tasks to Complete (In Order)

### Phase 1: Fix GameManager Action Registration (BLOCKING)

#### Task 1: Register Modern Fight Actions in GameManager
**File**: `40k/scripts/GameManager.gd`
**Lines**: ~200-250 (in process_action function)

**Problem**: GameManager only recognizes legacy fight actions, causing multiplayer to fail.

**Fix**:
```gdscript
match action.type:
    # ... existing cases ...

    # FIGHT PHASE - Add all modern action types
    "SELECT_FIGHTER", "SELECT_MELEE_WEAPON":
        return _delegate_to_current_phase(action)
    "PILE_IN", "ASSIGN_ATTACKS", "CONFIRM_AND_RESOLVE_ATTACKS":
        return _delegate_to_current_phase(action)
    "ROLL_DICE", "CONSOLIDATE", "HEROIC_INTERVENTION":
        return _delegate_to_current_phase(action)
    "SKIP_UNIT":  # Future use
        return _delegate_to_current_phase(action)
```

**Verification**: Run existing fight phase tests and check logs for "Unknown action type" errors.

### Phase 2: Implement Subphase Logic in FightPhase

#### Task 2: Add Subphase State and Signals
**File**: `40k/phases/FightPhase.gd`
**Location**: Add after existing var declarations (around line 20)

```gdscript
# Subphase tracking
enum Subphase {
    FIGHTS_FIRST,
    REMAINING_COMBATS,
    COMPLETE
}

var current_subphase: Subphase = Subphase.FIGHTS_FIRST
var fights_first_units: Dictionary = {"1": [], "2": []}  # Player -> [unit_ids]
var remaining_units: Dictionary = {"1": [], "2": []}
var current_selecting_player: int = 2  # Defending player starts

# New signals for subphase system
signal fight_selection_required(data: Dictionary)
signal pile_in_required(unit_id: String, max_distance: float)
signal attack_assignment_required(unit_id: String, eligible_targets: Dictionary)
signal consolidate_required(unit_id: String, max_distance: float)
signal subphase_transition(from_subphase: String, to_subphase: String)
```

#### Task 3: Build Subphase Sequences on Phase Entry
**File**: `40k/phases/FightPhase.gd`
**Function**: `_initialize_fight_sequence()` (modify existing)

```gdscript
func _initialize_fight_sequence() -> void:
    fights_first_units = {"1": [], "2": []}
    remaining_units = {"1": [], "2": []}
    units_that_fought.clear()

    # Categorize all units in combat by subphase and owner
    for unit_id in _get_all_unit_ids():
        var unit = _get_unit(unit_id)
        if not _is_unit_in_combat(unit):
            continue

        var owner = unit.owner
        var priority = _get_fight_priority(unit)

        if priority == FIGHTS_FIRST:
            fights_first_units[str(owner)].append(unit_id)
        else:  # NORMAL priority
            remaining_units[str(owner)].append(unit_id)

    # Start with Fights First subphase
    current_subphase = Subphase.FIGHTS_FIRST
    current_selecting_player = _get_defending_player()

    log_phase_message("Fight Phase: %d Fights First units, %d Remaining units" % [
        fights_first_units["1"].size() + fights_first_units["2"].size(),
        remaining_units["1"].size() + remaining_units["2"].size()
    ])

    # Emit signal to show selection dialog
    _emit_fight_selection_required()

func _get_defending_player() -> int:
    var active_player = GameState.get_active_player()
    return 2 if active_player == 1 else 1

func _get_fight_priority(unit: Dictionary) -> int:
    # Check charged_this_turn flag
    if unit.get("flags", {}).get("charged_this_turn", false):
        return FIGHTS_FIRST

    # Check abilities (future expansion)
    var abilities = unit.get("meta", {}).get("abilities", [])
    if "fights_first" in abilities:
        return FIGHTS_FIRST

    return NORMAL  # Default priority
```

#### Task 4: Implement Fight Selection Logic
**File**: `40k/phases/FightPhase.gd`
**Location**: Add new function

```gdscript
func _emit_fight_selection_required() -> void:
    # Get eligible units for current player and subphase
    var eligible_units = _get_eligible_units_for_selection()

    if eligible_units.is_empty():
        # Current player has no units, switch to opponent
        _switch_selecting_player()
        eligible_units = _get_eligible_units_for_selection()

        if eligible_units.is_empty():
            # No units left in this subphase, transition
            _transition_subphase()
            return

    # Build dialog data
    var dialog_data = {
        "current_subphase": Subphase.keys()[current_subphase],
        "selecting_player": current_selecting_player,
        "eligible_units": eligible_units,
        "fights_first_units": fights_first_units,
        "remaining_units": remaining_units,
        "units_that_fought": units_that_fought
    }

    emit_signal("fight_selection_required", dialog_data)

func _get_eligible_units_for_selection() -> Dictionary:
    var eligible = {}
    var player_key = str(current_selecting_player)
    var source_list = fights_first_units if current_subphase == Subphase.FIGHTS_FIRST else remaining_units

    for unit_id in source_list.get(player_key, []):
        if unit_id not in units_that_fought:
            var unit = _get_unit(unit_id)
            eligible[unit_id] = {
                "name": unit.meta.name,
                "weapons": _get_melee_weapons(unit),
                "targets": _get_eligible_melee_targets(unit_id)
            }

    return eligible

func _switch_selecting_player() -> void:
    current_selecting_player = 2 if current_selecting_player == 1 else 1
    log_phase_message("Selection switches to Player %d" % current_selecting_player)

func _transition_subphase() -> void:
    if current_subphase == Subphase.FIGHTS_FIRST:
        log_phase_message("Fights First complete. Starting Remaining Combats.")
        emit_signal("subphase_transition", "FIGHTS_FIRST", "REMAINING_COMBATS")

        current_subphase = Subphase.REMAINING_COMBATS
        current_selecting_player = _get_defending_player()  # Reset to defender

        # Check if there are any remaining combats
        if remaining_units["1"].is_empty() and remaining_units["2"].is_empty():
            log_phase_message("No remaining combats. Fight Phase complete.")
            emit_signal("phase_completed")
        else:
            _emit_fight_selection_required()
    else:
        # Remaining Combats complete
        log_phase_message("Fight Phase complete.")
        emit_signal("phase_completed")
```

#### Task 5: Implement SELECT_FIGHTER Action
**File**: `40k/phases/FightPhase.gd`
**Location**: Modify existing _process_select_fighter

```gdscript
func _validate_select_fighter(action: Dictionary) -> Dictionary:
    var unit_id = action.get("unit_id", "")

    # Check it's the right player's turn
    var unit = _get_unit(unit_id)
    if unit.owner != current_selecting_player:
        return {"valid": false, "errors": ["Not your turn to select"]}

    # Check unit is eligible in current subphase
    var player_key = str(current_selecting_player)
    var source_list = fights_first_units if current_subphase == Subphase.FIGHTS_FIRST else remaining_units

    if unit_id not in source_list.get(player_key, []):
        return {"valid": false, "errors": ["Unit not eligible in this subphase"]}

    # Check unit hasn't already fought
    if unit_id in units_that_fought:
        return {"valid": false, "errors": ["Unit has already fought"]}

    # Check unit is in engagement range
    if not _is_unit_in_combat(unit):
        return {"valid": false, "errors": ["Unit not in engagement range"]}

    return {"valid": true}

func _process_select_fighter(action: Dictionary) -> Dictionary:
    active_fighter_id = action.unit_id

    log_phase_message("Player %d selects %s to fight" % [
        current_selecting_player,
        _get_unit(active_fighter_id).meta.name
    ])

    emit_signal("unit_selected_for_fighting", active_fighter_id)

    # Start unit activation sequence: Pile In → Attack → Consolidate
    emit_signal("pile_in_required", active_fighter_id, 3.0)

    return create_result(true, [])
```

### Phase 3: Create Fight Selection Dialog

#### Task 6: Implement FightSelectionDialog
**File**: `40k/dialogs/FightSelectionDialog.gd` (NEW)

```gdscript
extends AcceptDialog
class_name FightSelectionDialog

signal fighter_selected(unit_id: String)

var phase_reference = null
var dialog_data: Dictionary = {}
var selected_unit_id: String = ""

func setup(data: Dictionary, phase) -> void:
    dialog_data = data
    phase_reference = phase

    title = "Select Unit to Fight - Player %d" % data.selecting_player

    _build_ui()

func _build_ui() -> void:
    # Main container
    var main_container = VBoxContainer.new()
    main_container.custom_minimum_size = Vector2(600, 400)

    # Current subphase header
    var subphase_label = Label.new()
    subphase_label.text = "Current: %s Subphase" % dialog_data.current_subphase
    subphase_label.add_theme_font_size_override("font_size", 18)
    main_container.add_child(subphase_label)

    main_container.add_child(HSeparator.new())

    # Scroll container for unit list
    var scroll = ScrollContainer.new()
    scroll.custom_minimum_size = Vector2(580, 300)

    var units_container = VBoxContainer.new()

    # Show all units organized by subphase
    _add_subphase_units(units_container, "FIGHTS_FIRST", dialog_data.fights_first_units)
    _add_subphase_units(units_container, "REMAINING_COMBATS", dialog_data.remaining_units)

    scroll.add_child(units_container)
    main_container.add_child(scroll)

    # Instructions
    var instructions = Label.new()
    instructions.text = "Select a unit from the highlighted section to activate"
    instructions.add_theme_color_override("font_color", Color.YELLOW)
    main_container.add_child(instructions)

    add_child(main_container)

    # Connect OK button
    confirmed.connect(_on_confirmed)

func _add_subphase_units(container: VBoxContainer, subphase_name: String, units_by_player: Dictionary) -> void:
    var subphase_header = Label.new()
    subphase_header.text = "=== %s ===" % subphase_name
    subphase_header.add_theme_font_size_override("font_size", 16)

    # Highlight if this is current subphase
    var is_current = subphase_name == dialog_data.current_subphase
    if is_current:
        subphase_header.add_theme_color_override("font_color", Color.GREEN)
    else:
        subphase_header.add_theme_color_override("font_color", Color.GRAY)

    container.add_child(subphase_header)

    # Add units for each player
    for player in ["1", "2"]:
        var player_units = units_by_player.get(player, [])
        if player_units.is_empty():
            continue

        var player_label = Label.new()
        player_label.text = "  Player %s:" % player
        container.add_child(player_label)

        for unit_id in player_units:
            var has_fought = unit_id in dialog_data.units_that_fought
            var is_eligible = dialog_data.eligible_units.has(unit_id)

            var unit_button = Button.new()
            var unit_data = dialog_data.eligible_units.get(unit_id, {})
            var unit_name = unit_data.get("name", unit_id)

            unit_button.text = "    %s%s" % [
                unit_name,
                " (Fought)" if has_fought else ""
            ]

            # Style based on state
            if has_fought:
                unit_button.disabled = true
                unit_button.modulate = Color.GRAY
            elif not is_eligible:
                unit_button.disabled = true
            elif is_current:
                unit_button.modulate = Color.LIGHT_GREEN

            if is_eligible and not has_fought:
                unit_button.pressed.connect(_on_unit_selected.bind(unit_id))

            container.add_child(unit_button)

    container.add_child(HSeparator.new())

func _on_unit_selected(unit_id: String) -> void:
    selected_unit_id = unit_id

    # Visual feedback
    for child in get_tree().get_nodes_in_group("unit_buttons"):
        if child is Button:
            child.modulate = Color.WHITE

    # Highlight selected (would need to track button reference)
    # For now, just store selection

func _on_confirmed() -> void:
    if selected_unit_id.is_empty():
        # Show error
        push_warning("No unit selected")
        return

    emit_signal("fighter_selected", selected_unit_id)
    queue_free()
```

### Phase 4: Create Activation Dialogs

#### Task 7: Implement PileInDialog
**File**: `40k/dialogs/PileInDialog.gd` (NEW)

```gdscript
extends AcceptDialog
class_name PileInDialog

signal pile_in_confirmed(movements: Dictionary)
signal pile_in_skipped()

var unit_id: String = ""
var max_distance: float = 3.0
var phase_reference = null
var model_movements: Dictionary = {}

func setup(fighter_id: String, max_dist: float, phase) -> void:
    unit_id = fighter_id
    max_distance = max_dist
    phase_reference = phase

    var unit = phase._get_unit(unit_id)
    title = "Pile In: %s" % unit.meta.name

    _build_ui()

func _build_ui() -> void:
    var container = VBoxContainer.new()

    var instruction = Label.new()
    instruction.text = "Move models up to %.1f\" toward closest enemy\nClick and drag models on the battlefield" % max_distance
    container.add_child(instruction)

    # Skip pile in button
    var skip_button = Button.new()
    skip_button.text = "No Pile In Movement"
    skip_button.pressed.connect(_on_skip_pressed)
    container.add_child(skip_button)

    # Info label
    var info = Label.new()
    info.text = "(Models must move toward closest enemy model)"
    info.add_theme_font_size_override("font_size", 12)
    info.add_theme_color_override("font_color", Color.GRAY)
    container.add_child(info)

    add_child(container)

    confirmed.connect(_on_confirmed)

func update_movements(movements: Dictionary) -> void:
    # Called by FightController when user drags models
    model_movements = movements

func _on_skip_pressed() -> void:
    emit_signal("pile_in_skipped")
    queue_free()

func _on_confirmed() -> void:
    emit_signal("pile_in_confirmed", model_movements)
    queue_free()
```

#### Task 8: Implement AttackAssignmentDialog
**File**: `40k/dialogs/AttackAssignmentDialog.gd` (NEW)

```gdscript
extends AcceptDialog
class_name AttackAssignmentDialog

signal attacks_confirmed(assignments: Array)

var unit_id: String = ""
var eligible_targets: Dictionary = {}
var phase_reference = null
var assignments: Array = []

func setup(fighter_id: String, targets: Dictionary, phase) -> void:
    unit_id = fighter_id
    eligible_targets = targets
    phase_reference = phase

    var unit = phase._get_unit(unit_id)
    title = "Assign Attacks: %s" % unit.meta.name

    _build_ui()

func _build_ui() -> void:
    var container = VBoxContainer.new()
    container.custom_minimum_size = Vector2(500, 300)

    var instruction = Label.new()
    instruction.text = "Select weapon and target for melee attacks"
    container.add_child(instruction)

    # Get unit's melee weapons
    var unit = phase_reference._get_unit(unit_id)
    var weapons = phase_reference._get_melee_weapons(unit)

    # Weapon selector
    var weapon_label = Label.new()
    weapon_label.text = "Weapon:"
    container.add_child(weapon_label)

    var weapon_list = ItemList.new()
    weapon_list.custom_minimum_size = Vector2(480, 100)
    for weapon_id in weapons:
        var weapon = weapons[weapon_id]
        weapon_list.add_item("%s (A:%s S:%s AP:%s D:%s)" % [
            weapon.get("name", weapon_id),
            weapon.get("attacks", "1"),
            weapon.get("strength", "User"),
            weapon.get("ap", "0"),
            weapon.get("damage", "1")
        ])
        weapon_list.set_item_metadata(weapon_list.item_count - 1, weapon_id)
    container.add_child(weapon_list)

    # Target selector
    var target_label = Label.new()
    target_label.text = "Target:"
    container.add_child(target_label)

    var target_list = ItemList.new()
    target_list.custom_minimum_size = Vector2(480, 100)
    for target_id in eligible_targets:
        var target_data = eligible_targets[target_id]
        target_list.add_item("%s (in engagement range)" % target_data.get("name", target_id))
        target_list.set_item_metadata(target_list.item_count - 1, target_id)
    container.add_child(target_list)

    # Assign button
    var assign_button = Button.new()
    assign_button.text = "Add Assignment"
    assign_button.pressed.connect(_on_assign_pressed.bind(weapon_list, target_list))
    container.add_child(assign_button)

    # Current assignments display
    var assignments_label = Label.new()
    assignments_label.text = "Assignments:"
    assignments_label.name = "AssignmentsLabel"
    container.add_child(assignments_label)

    var assignments_display = RichTextLabel.new()
    assignments_display.custom_minimum_size = Vector2(480, 60)
    assignments_display.name = "AssignmentsDisplay"
    container.add_child(assignments_display)

    add_child(container)

    confirmed.connect(_on_confirmed)

func _on_assign_pressed(weapon_list: ItemList, target_list: ItemList) -> void:
    var weapon_idx = weapon_list.get_selected_items()
    var target_idx = target_list.get_selected_items()

    if weapon_idx.is_empty() or target_idx.is_empty():
        push_warning("Select both weapon and target")
        return

    var weapon_id = weapon_list.get_item_metadata(weapon_idx[0])
    var target_id = target_list.get_item_metadata(target_idx[0])

    assignments.append({
        "attacker": unit_id,
        "weapon": weapon_id,
        "target": target_id
    })

    _update_assignments_display()

func _update_assignments_display() -> void:
    var display = get_node_or_null("VBoxContainer/AssignmentsDisplay")
    if not display:
        return

    display.clear()
    for assignment in assignments:
        display.append_text("- %s → %s\n" % [assignment.weapon, assignment.target])

func _on_confirmed() -> void:
    if assignments.is_empty():
        push_warning("No attacks assigned")
        return

    emit_signal("attacks_confirmed", assignments)
    queue_free()
```

#### Task 9: Implement ConsolidateDialog
**File**: `40k/dialogs/ConsolidateDialog.gd` (NEW)

```gdscript
extends AcceptDialog
class_name ConsolidateDialog

signal consolidate_confirmed(movements: Dictionary)
signal consolidate_skipped()

var unit_id: String = ""
var max_distance: float = 3.0
var phase_reference = null
var model_movements: Dictionary = {}

func setup(fighter_id: String, max_dist: float, phase) -> void:
    unit_id = fighter_id
    max_distance = max_dist
    phase_reference = phase

    var unit = phase._get_unit(unit_id)
    title = "Consolidate: %s" % unit.meta.name

    _build_ui()

func _build_ui() -> void:
    var container = VBoxContainer.new()

    var instruction = Label.new()
    instruction.text = "Move models up to %.1f\" toward closest enemy\nClick and drag models on the battlefield" % max_distance
    container.add_child(instruction)

    # Skip consolidate button
    var skip_button = Button.new()
    skip_button.text = "No Consolidate Movement"
    skip_button.pressed.connect(_on_skip_pressed)
    container.add_child(skip_button)

    # Info label
    var info = Label.new()
    info.text = "(Models must move toward closest enemy model)"
    info.add_theme_font_size_override("font_size", 12)
    info.add_theme_color_override("font_color", Color.GRAY)
    container.add_child(info)

    add_child(container)

    confirmed.connect(_on_confirmed)

func update_movements(movements: Dictionary) -> void:
    model_movements = movements

func _on_skip_pressed() -> void:
    emit_signal("consolidate_skipped")
    queue_free()

func _on_confirmed() -> void:
    emit_signal("consolidate_confirmed", model_movements)
    queue_free()
```

### Phase 5: Connect Dialogs to Phase

#### Task 10: Update FightPhase Dialog Signal Handling
**File**: `40k/phases/FightPhase.gd`
**Location**: Add in _ready() or enter_phase()

```gdscript
func enter_phase(snapshot: Dictionary) -> void:
    super.enter_phase(snapshot)

    _initialize_fight_sequence()

func _connect_dialog_signals(dialog) -> void:
    # Called by Main.gd when dialog is created
    # Connections handled by dialog emitting to Main, which calls phase
    pass
```

#### Task 11: Update FightController to Show Dialogs
**File**: `40k/scripts/FightController.gd`
**Location**: Add signal connections

```gdscript
func _ready() -> void:
    _setup_ui_references()
    _connect_phase_signals()

func _connect_phase_signals() -> void:
    if not current_phase:
        return

    # Connect to new dialog signals
    if not current_phase.fight_selection_required.is_connected(_on_fight_selection_required):
        current_phase.fight_selection_required.connect(_on_fight_selection_required)

    if not current_phase.pile_in_required.is_connected(_on_pile_in_required):
        current_phase.pile_in_required.connect(_on_pile_in_required)

    if not current_phase.attack_assignment_required.is_connected(_on_attack_assignment_required):
        current_phase.attack_assignment_required.connect(_on_attack_assignment_required)

    if not current_phase.consolidate_required.is_connected(_on_consolidate_required):
        current_phase.consolidate_required.connect(_on_consolidate_required)

    if not current_phase.subphase_transition.is_connected(_on_subphase_transition):
        current_phase.subphase_transition.connect(_on_subphase_transition)

func _on_fight_selection_required(data: Dictionary) -> void:
    var dialog = FightSelectionDialog.new()
    dialog.setup(data, current_phase)
    dialog.fighter_selected.connect(_on_fighter_selected)
    get_tree().root.add_child(dialog)
    dialog.popup_centered()

func _on_fighter_selected(unit_id: String) -> void:
    # Submit SELECT_FIGHTER action
    var action = {
        "type": "SELECT_FIGHTER",
        "unit_id": unit_id,
        "player": GameState.get_current_player_for_peer()
    }
    emit_signal("fight_action_requested", action)

func _on_pile_in_required(unit_id: String, max_distance: float) -> void:
    var dialog = PileInDialog.new()
    dialog.setup(unit_id, max_distance, current_phase)
    dialog.pile_in_confirmed.connect(_on_pile_in_confirmed.bind(unit_id))
    dialog.pile_in_skipped.connect(_on_pile_in_skipped.bind(unit_id))
    get_tree().root.add_child(dialog)
    dialog.popup_centered()

    # TODO: Enable model dragging for pile-in movement

func _on_pile_in_confirmed(movements: Dictionary, unit_id: String) -> void:
    var action = {
        "type": "PILE_IN",
        "unit_id": unit_id,
        "movements": movements,
        "player": GameState.get_current_player_for_peer()
    }
    emit_signal("fight_action_requested", action)

func _on_pile_in_skipped(unit_id: String) -> void:
    # Proceed without pile-in movement
    _on_pile_in_confirmed({}, unit_id)

func _on_attack_assignment_required(unit_id: String, targets: Dictionary) -> void:
    var dialog = AttackAssignmentDialog.new()
    dialog.setup(unit_id, targets, current_phase)
    dialog.attacks_confirmed.connect(_on_attacks_confirmed)
    get_tree().root.add_child(dialog)
    dialog.popup_centered()

func _on_attacks_confirmed(assignments: Array) -> void:
    # Process assignments and resolve attacks
    var action = {
        "type": "CONFIRM_AND_RESOLVE_ATTACKS",
        "assignments": assignments,
        "player": GameState.get_current_player_for_peer()
    }
    emit_signal("fight_action_requested", action)

func _on_consolidate_required(unit_id: String, max_distance: float) -> void:
    var dialog = ConsolidateDialog.new()
    dialog.setup(unit_id, max_distance, current_phase)
    dialog.consolidate_confirmed.connect(_on_consolidate_confirmed.bind(unit_id))
    dialog.consolidate_skipped.connect(_on_consolidate_skipped.bind(unit_id))
    get_tree().root.add_child(dialog)
    dialog.popup_centered()

func _on_consolidate_confirmed(movements: Dictionary, unit_id: String) -> void:
    var action = {
        "type": "CONSOLIDATE",
        "unit_id": unit_id,
        "movements": movements,
        "player": GameState.get_current_player_for_peer()
    }
    emit_signal("fight_action_requested", action)

func _on_consolidate_skipped(unit_id: String) -> void:
    _on_consolidate_confirmed({}, unit_id)

func _on_subphase_transition(from_subphase: String, to_subphase: String) -> void:
    # Show notification
    log_message("=== %s Complete ===" % from_subphase)
    log_message("Starting %s..." % to_subphase)

    # Could show a brief popup notification here
```

### Phase 6: Update Action Processing Flow

#### Task 12: Add Dialog Flow to Action Processing
**File**: `40k/phases/FightPhase.gd`
**Location**: Modify action processing functions

```gdscript
func _process_pile_in(action: Dictionary) -> Dictionary:
    var changes = []
    var movements = action.get("movements", {})

    # Apply movements (if any provided)
    for model_id in movements:
        changes.append({
            "op": "set",
            "path": "units.%s.models.%s.position" % [action.unit_id, model_id],
            "value": movements[model_id]
        })

    # After pile-in, request attack assignment
    var targets = _get_eligible_melee_targets(action.unit_id)
    emit_signal("attack_assignment_required", action.unit_id, targets)

    return create_result(true, changes)

func _process_confirm_and_resolve_attacks(action: Dictionary) -> Dictionary:
    var assignments = action.get("assignments", [])

    # Resolve attacks using RulesEngine
    var melee_action = {
        "type": "FIGHT",
        "actor_unit_id": active_fighter_id,
        "payload": {"assignments": assignments}
    }

    var rng_service = RulesEngine.RNGService.new()
    var result = RulesEngine.resolve_melee_attacks(melee_action, game_state_snapshot, rng_service)

    if result.success:
        emit_signal("attacks_resolved", active_fighter_id, assignments, result)
        emit_signal("dice_rolled", result.get("dice", {}))

        # After attacks, request consolidate
        emit_signal("consolidate_required", active_fighter_id, 3.0)

    return result

func _process_consolidate(action: Dictionary) -> Dictionary:
    var changes = []
    var movements = action.get("movements", {})

    # Apply movements
    for model_id in movements:
        changes.append({
            "op": "set",
            "path": "units.%s.models.%s.position" % [action.unit_id, model_id],
            "value": movements[model_id]
        })

    # Mark unit as having fought
    changes.append({
        "op": "set",
        "path": "units.%s.flags.has_fought" % action.unit_id,
        "value": true
    })
    units_that_fought.append(action.unit_id)

    # Switch to next player
    _switch_selecting_player()

    # Request next fight selection
    _emit_fight_selection_required()

    return create_result(true, changes)
```

### Phase 7: Testing

#### Task 13: Write Unit Tests for Subphase Logic
**File**: `40k/tests/unit/test_fight_subphases.gd` (NEW)

```gdscript
extends GutTest

var fight_phase: FightPhase

func before_each():
    fight_phase = FightPhase.new()
    add_child_autofree(fight_phase)

func test_fights_first_categorization():
    # Create test state with charged unit
    var test_state = {
        "units": {
            "U_CHARGED": {
                "id": "U_CHARGED",
                "owner": 1,
                "flags": {"charged_this_turn": true},
                "meta": {"name": "Chargers"},
                "models": [{"position": Vector2(0, 0)}]
            },
            "U_NORMAL": {
                "id": "U_NORMAL",
                "owner": 2,
                "flags": {},
                "meta": {"name": "Defenders"},
                "models": [{"position": Vector2(10, 0)}]
            }
        }
    }

    fight_phase.enter_phase(test_state)

    assert_eq(fight_phase.fights_first_units["1"].size(), 1, "Should have 1 fights first unit")
    assert_true("U_CHARGED" in fight_phase.fights_first_units["1"], "Charged unit should be in fights first")
    assert_eq(fight_phase.remaining_units["2"].size(), 1, "Should have 1 normal unit")

func test_defending_player_selects_first():
    var test_state = _create_basic_combat_state()

    # Active player is 1
    GameState.set_active_player(1)

    fight_phase.enter_phase(test_state)

    # Defending player (2) should select first
    assert_eq(fight_phase.current_selecting_player, 2, "Defending player should select first")

func test_player_alternation():
    var test_state = _create_multi_unit_state()
    fight_phase.enter_phase(test_state)

    # Player 2 selects first
    assert_eq(fight_phase.current_selecting_player, 2)

    # Process selection
    fight_phase._switch_selecting_player()

    # Should switch to player 1
    assert_eq(fight_phase.current_selecting_player, 1)

func test_subphase_transition():
    var test_state = _create_basic_combat_state()
    fight_phase.enter_phase(test_state)

    var transition_fired = false
    fight_phase.subphase_transition.connect(func(from, to):
        transition_fired = true
        assert_eq(from, "FIGHTS_FIRST")
        assert_eq(to, "REMAINING_COMBATS")
    )

    # Complete all fights first units
    fight_phase.units_that_fought.append("U_CHARGED")
    fight_phase._transition_subphase()

    assert_true(transition_fired, "Should emit subphase transition signal")
    assert_eq(fight_phase.current_subphase, fight_phase.Subphase.REMAINING_COMBATS)

func _create_basic_combat_state() -> Dictionary:
    return {
        "units": {
            "U_CHARGED": {
                "id": "U_CHARGED",
                "owner": 1,
                "flags": {"charged_this_turn": true},
                "meta": {"name": "Chargers"},
                "models": [{"position": Vector2(0, 0)}]
            },
            "U_DEFENDER": {
                "id": "U_DEFENDER",
                "owner": 2,
                "flags": {},
                "meta": {"name": "Defenders"},
                "models": [{"position": Vector2(10, 0)}]
            }
        }
    }

func _create_multi_unit_state() -> Dictionary:
    return {
        "units": {
            "P1_CHARGED_1": {"owner": 1, "flags": {"charged_this_turn": true}},
            "P1_CHARGED_2": {"owner": 1, "flags": {"charged_this_turn": true}},
            "P2_CHARGED_1": {"owner": 2, "flags": {"charged_this_turn": true}},
            "P2_NORMAL_1": {"owner": 2, "flags": {}}
        }
    }
```

#### Task 14: Write Integration Test for Full Flow
**File**: `40k/tests/integration/test_fight_phase_full_flow.gd` (NEW)

```gdscript
extends GutTest

var fight_phase: FightPhase
var test_state: Dictionary

func before_each():
    fight_phase = FightPhase.new()
    add_child_autofree(fight_phase)
    test_state = _create_full_combat_scenario()

func test_complete_fight_sequence():
    fight_phase.enter_phase(test_state)

    # Step 1: Phase should emit fight_selection_required
    var selection_emitted = false
    fight_phase.fight_selection_required.connect(func(data):
        selection_emitted = true
        assert_eq(data.current_subphase, "FIGHTS_FIRST")
        assert_eq(data.selecting_player, 2)  # Defender
    )

    await get_tree().process_frame
    assert_true(selection_emitted, "Should request fight selection")

    # Step 2: Player 2 selects a unit
    var select_result = fight_phase.execute_action({
        "type": "SELECT_FIGHTER",
        "unit_id": "P2_CHARGED"
    })
    assert_true(select_result.success, "Should accept fighter selection")

    # Step 3: Pile-in (skip for test)
    var pile_result = fight_phase.execute_action({
        "type": "PILE_IN",
        "unit_id": "P2_CHARGED",
        "movements": {}
    })
    assert_true(pile_result.success, "Should accept pile-in")

    # Step 4: Attack assignment and resolution
    var attack_result = fight_phase.execute_action({
        "type": "CONFIRM_AND_RESOLVE_ATTACKS",
        "assignments": [{
            "attacker": "P2_CHARGED",
            "weapon": "chainsword",
            "target": "P1_CHARGED"
        }]
    })
    assert_true(attack_result.success, "Should resolve attacks")
    assert_true(attack_result.has("dice"), "Should have dice results")

    # Step 5: Consolidate
    var consolidate_result = fight_phase.execute_action({
        "type": "CONSOLIDATE",
        "unit_id": "P2_CHARGED",
        "movements": {}
    })
    assert_true(consolidate_result.success, "Should accept consolidate")

    # Verify unit marked as fought
    assert_true("P2_CHARGED" in fight_phase.units_that_fought)

    # Verify turn switched to player 1
    assert_eq(fight_phase.current_selecting_player, 1)

func _create_full_combat_scenario() -> Dictionary:
    return {
        "units": {
            "P1_CHARGED": {
                "id": "P1_CHARGED",
                "owner": 1,
                "flags": {"charged_this_turn": true},
                "meta": {
                    "name": "Space Marines",
                    "stats": {"weapon_skill": 3, "strength": 4, "toughness": 4},
                    "weapons": {
                        "chainsword": {
                            "type": "melee",
                            "attacks": 2,
                            "strength": 4,
                            "ap": 0,
                            "damage": 1
                        }
                    }
                },
                "models": [
                    {"id": "m1", "position": Vector2(0, 0), "alive": true, "current_wounds": 2, "max_wounds": 2}
                ]
            },
            "P2_CHARGED": {
                "id": "P2_CHARGED",
                "owner": 2,
                "flags": {"charged_this_turn": true},
                "meta": {
                    "name": "Orks",
                    "stats": {"weapon_skill": 3, "strength": 5, "toughness": 5},
                    "weapons": {
                        "choppa": {
                            "type": "melee",
                            "attacks": 3,
                            "strength": 5,
                            "ap": -1,
                            "damage": 1
                        }
                    }
                },
                "models": [
                    {"id": "m1", "position": Vector2(10, 0), "alive": true, "current_wounds": 2, "max_wounds": 2}
                ]
            }
        }
    }
```

## Validation Gates

### Automated Testing

```bash
# Fix syntax errors first
export PATH="$HOME/bin:$PATH"
godot --headless --check-only 40k/phases/FightPhase.gd
godot --headless --check-only 40k/dialogs/FightSelectionDialog.gd
godot --headless --check-only 40k/dialogs/PileInDialog.gd
godot --headless --check-only 40k/dialogs/AttackAssignmentDialog.gd
godot --headless --check-only 40k/dialogs/ConsolidateDialog.gd

# Run unit tests
godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://40k/tests/unit/test_fight_subphases.gd -gexit

# Run integration tests
godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://40k/tests/integration/test_fight_phase_full_flow.gd -gexit

# Run all fight tests
godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://40k/tests/ -ginclude_subdirs -gprefix=test_fight -gexit

# Manual gameplay test
godot res://40k/Main.tscn
```

### Manual Validation Checklist

- [ ] Fight phase starts and shows selection dialog
- [ ] Dialog lists all units in both subphases with correct labels
- [ ] Defending player (non-active) selects first unit
- [ ] Only eligible units in current subphase are selectable
- [ ] Pile-in dialog appears after selecting unit
- [ ] Attack assignment dialog shows weapons and targets
- [ ] Dice rolls execute and show results
- [ ] Consolidate dialog appears after attacks
- [ ] Unit is marked as fought after consolidating
- [ ] Selection switches to other player
- [ ] Players alternate correctly within subphase
- [ ] Fights First completes and transitions to Remaining Combats
- [ ] Notification shows when subphase transitions
- [ ] Remaining Combats follows same alternation pattern
- [ ] Phase completes when all units have fought
- [ ] Multiplayer synchronization works (both players see same state)

## Error Handling Strategy

1. **Validation Errors**:
   - Check player ownership before allowing selection
   - Verify unit is in correct subphase
   - Ensure unit hasn't already fought
   - Validate movement distances for pile-in/consolidate

2. **Dialog Safety**:
   - Check dialog exists before accessing
   - Use queue_free() to cleanup dialogs
   - Disconnect signals when dialog closes
   - Handle user closing dialog without selection

3. **State Consistency**:
   - Track units_that_fought to prevent double-fighting
   - Verify subphase matches expected state
   - Check eligible units exist before showing dialog
   - Handle empty unit lists gracefully

4. **Multiplayer Safety**:
   - Ensure GameManager registers all action types
   - Verify action ownership matches current selecting player
   - Broadcast results to all clients
   - Both players create same dialogs from result data

## Common Pitfalls to Avoid

1. **GameManager Registration**: MUST add all fight action types or multiplayer breaks
2. **Player Alternation**: Remember defending player selects first, then alternate
3. **Subphase Transition**: Check both players have no eligible units before transitioning
4. **Dialog Lifecycle**: Always queue_free() dialogs to prevent memory leaks
5. **Signal Connections**: Check is_connected() before connecting to prevent duplicates
6. **State Updates**: Mark units as fought AFTER consolidate, not before
7. **Empty Lists**: Handle case where subphase has no eligible units
8. **Model Movements**: Validate pile-in/consolidate toward closest enemy

## Implementation Verification Checklist

### Core Functionality
- [ ] Fights First subphase identifies charged units correctly
- [ ] Remaining Combats subphase includes non-charged units
- [ ] Defending player selects first in each subphase
- [ ] Players alternate selection correctly
- [ ] Units cannot be selected twice
- [ ] Subphase transitions automatically when complete

### Dialog Flow
- [ ] FightSelectionDialog shows all units with correct labels
- [ ] PileInDialog allows model movement up to 3"
- [ ] AttackAssignmentDialog lists weapons and targets
- [ ] ConsolidateDialog allows post-combat movement
- [ ] Dialogs appear in correct sequence
- [ ] Dialogs cleanup properly after use

### Combat Resolution
- [ ] Pile-in validates movement toward closest enemy
- [ ] Attack resolution uses RulesEngine correctly
- [ ] Dice rolls show in log/dialog
- [ ] Damage applies to target models
- [ ] Consolidate movement validates correctly
- [ ] Unit marked as fought after completion

### Multiplayer
- [ ] GameManager registers all action types
- [ ] Actions sync between host and client
- [ ] Both players see same dialog states
- [ ] Results broadcast correctly
- [ ] No desync issues during fight sequence

## Success Metrics

- All new tests pass (100% success rate)
- Existing fight phase tests continue to pass
- Manual gameplay shows correct alternating activation
- Defending player consistently selects first
- Subphase transition happens automatically
- Dialogs appear and cleanup correctly
- No memory leaks from dialog creation
- Multiplayer synchronization maintains consistency
- UI clearly shows current subphase and eligible units
- Fight sequence matches official 10th edition rules

## Confidence Score: 8/10

**High confidence due to**:
- Clear official 10th edition rules from multiple sources
- Extensive existing dialog patterns to follow (WeaponOrderDialog, NextWeaponDialog)
- Well-established phase signal architecture
- Comprehensive exploration of current implementation
- Similar sequential resolution pattern from shooting phase
- User clarification on all UX questions

**Points deducted for**:
- Complexity of model drag-and-drop for pile-in/consolidate (may need iteration)
- Potential edge cases in player alternation with uneven unit counts
- Integration with existing FightController may need adjustments

## Additional Notes

### Key Design Decisions

1. **Modal-Based Flow**: Using AcceptDialog modals (like shooting phase) provides clear pause points and matches existing patterns

2. **Show All Units Upfront**: Displaying both subphases with visual indicators (green highlight, gray-out) gives players full visibility of fight order

3. **Automatic Progression**: Seamlessly transitioning between subphases reduces clicks and matches tabletop flow where players naturally move from Fights First to remaining combats

4. **Sequential Confirmations**: Breaking activation into Pile-in → Attack → Consolidate dialogs follows the shooting phase pattern and gives clear feedback at each step

### Integration Points

- **From ChargePhase**: Reads `charged_this_turn` flag to populate Fights First
- **To GameState**: Updates unit positions, model wounds, and fight flags
- **With RulesEngine**: Uses `resolve_melee_attacks()` for dice resolution
- **With NetworkManager**: All actions must be registered in GameManager

### Future Enhancements

- Heroic Intervention mechanic
- Fights Last debuff support
- Fight on death abilities
- Interrupt combat abilities
- More sophisticated target priority suggestions

This PRP provides a complete implementation path for a production-ready fight phase subphase system that integrates seamlessly with existing code while adding proper 10th edition rule support.
