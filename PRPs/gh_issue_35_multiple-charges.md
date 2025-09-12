# PRP: Enable Multiple Unit Charges in Charge Phase (GitHub Issue #35)

## Problem Statement
Currently, after one unit completes its charge in the charge phase, the only option available is to "end charge." Players should be able to select additional eligible units to charge, continuing the cycle until all desired charges are complete, following the Warhammer 40k 10th edition rules.

## Current Behavior
1. Player selects a unit to charge
2. Player selects target(s) and declares charge
3. Player rolls 2D6 for charge distance
4. Player moves models if charge is successful
5. **ISSUE**: Only option is "End Charge" - no ability to charge with another unit

## Expected Behavior
1. Player selects a unit to charge
2. Player selects target(s) and declares charge
3. Player rolls 2D6 for charge distance
4. Player moves models if charge is successful
5. **NEW**: Player can either:
   - Select another eligible unit to charge (repeat from step 1)
   - End charge phase when all desired charges are complete

## Game Rules Context
According to Warhammer 40k 10th edition rules (https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#CHARGE-PHASE):
- In the Charge phase, players declare and resolve charges one unit at a time
- Each charge is resolved completely (declare targets, roll, move) before moving to the next unit
- The phase continues until the player has no more units they wish to charge with
- This is NOT an alternating activation system (that's the Fight phase)

## Technical Context

### Current Architecture
**Key Files:**
- `40k/phases/ChargePhase.gd` - Core charge logic and state management
- `40k/scripts/ChargeController.gd` - UI and user interaction handling
- `40k/scripts/Main.gd` - Signal routing between controller and phase
- `40k/autoloads/PhaseManager.gd` - Phase state management

### Current State Management
```gdscript
# ChargePhase.gd state tracking
var active_charges = {}  # Currently charging units
var pending_charges = {} # Units that have declared but not rolled
var units_that_charged = [] # Units that completed charges this turn
```

### Current Actions
- `DECLARE_CHARGE` - Declare charge with target(s)
- `CHARGE_ROLL` - Roll 2D6 for distance
- `APPLY_CHARGE_MOVE` - Apply model movements
- `SKIP_CHARGE` - Skip charging with a unit
- `END_CHARGE` - End the entire charge phase

### Similar Pattern: Movement Phase
The Movement Phase (`40k/phases/MovementPhase.gd`) already handles multiple units:
```gdscript
# MovementPhase.gd pattern for multiple units
var active_moves = {}  # Track multiple simultaneous movements
# Units can be selected, moved, confirmed independently
# END_MOVEMENT only when all units are done
```

## Implementation Blueprint

### 1. Add New Action Types
```gdscript
# In ChargePhase.gd
const ChargeAction = {
    SELECT_CHARGE_UNIT = "SELECT_CHARGE_UNIT",  # NEW
    DECLARE_CHARGE = "DECLARE_CHARGE",
    CHARGE_ROLL = "CHARGE_ROLL", 
    APPLY_CHARGE_MOVE = "APPLY_CHARGE_MOVE",
    SKIP_CHARGE = "SKIP_CHARGE",
    COMPLETE_UNIT_CHARGE = "COMPLETE_UNIT_CHARGE",  # NEW - finish one unit
    END_CHARGE = "END_CHARGE"  # End entire phase
}
```

### 2. Enhanced State Tracking
```gdscript
# In ChargePhase.gd
var current_charging_unit = null  # Track which unit is actively charging
var eligible_units = []  # Units that can still charge
var completed_charges = []  # Units that finished charging this phase

func _get_eligible_charge_units(game_state: Dictionary) -> Array:
    # Return units that haven't charged yet and are eligible
    var eligible = []
    for unit_id in game_state.units:
        if unit_id not in completed_charges and not _is_in_engagement_range(unit):
            eligible.append(unit_id)
    return eligible
```

### 3. Modified UI Flow in ChargeController.gd
```gdscript
# After successful charge move confirmation
func _on_confirm_charge_moves() -> void:
    # Apply the charge move
    _send_action("APPLY_CHARGE_MOVE", {
        "unit_id": selected_unit_id,
        "per_model_paths": _get_model_paths()
    })
    
    # Mark this unit as complete
    _send_action("COMPLETE_UNIT_CHARGE", {"unit_id": selected_unit_id})
    
    # Check for more eligible units
    _update_ui_for_next_charge()

func _update_ui_for_next_charge() -> void:
    var eligible = phase_manager.get_eligible_charge_units()
    
    if eligible.size() > 0:
        # Show unit selection list again
        _populate_unit_list(eligible)
        _show_charge_or_end_buttons()
    else:
        # No more units can charge
        _show_end_charge_only()

func _show_charge_or_end_buttons() -> void:
    # Show both "Select Next Unit" and "End Charge Phase" buttons
    next_unit_button.visible = true
    end_charge_button.visible = true
```

### 4. Phase Logic Updates
```gdscript
# In ChargePhase.gd process_action()
match action.type:
    ChargeAction.COMPLETE_UNIT_CHARGE:
        var unit_id = action.payload.unit_id
        completed_charges.append(unit_id)
        current_charging_unit = null
        # Don't end phase, allow selection of next unit
        
    ChargeAction.SELECT_CHARGE_UNIT:
        if action.payload.unit_id in eligible_units:
            current_charging_unit = action.payload.unit_id
            # Enable target selection UI
```

### 5. UI Component Updates
```gdscript
# Add new UI elements in ChargeController scene
@onready var next_unit_button = $UI/NextUnitButton
@onready var charge_status_label = $UI/ChargeStatusLabel

# Update status display
func _update_charge_status() -> void:
    var completed = completed_charges.size()
    var eligible = _get_eligible_units().size()
    charge_status_label.text = "Charges: %d completed, %d eligible" % [completed, eligible]
```

## Implementation Tasks

1. **Update ChargePhase.gd**
   - Add `COMPLETE_UNIT_CHARGE` and `SELECT_CHARGE_UNIT` actions
   - Track `current_charging_unit` and `completed_charges`
   - Implement `_get_eligible_charge_units()` method
   - Modify `END_CHARGE` to only end when explicitly chosen

2. **Update ChargeController.gd**
   - Add UI for "Select Next Unit" vs "End Charge Phase" choice
   - Implement `_update_ui_for_next_charge()` after each charge completion
   - Add charge status display showing completed/eligible units
   - Reset UI state properly between units

3. **Update UI Scene (ChargeController.tscn)**
   - Add NextUnitButton and wire signals
   - Add ChargeStatusLabel for phase progress
   - Ensure proper button visibility toggling

4. **Update Tests**
   - Modify `test_charge_phase.gd` to test multiple unit charges
   - Add test case for charge → next unit → charge flow
   - Test edge cases (no more eligible units, all units charged)

5. **Fix Method Call Issue**
   - In Main.gd, ensure correct method calls to phase objects
   - Verify state synchronization between controller and phase

## Testing Strategy

### Unit Tests
```gdscript
# In test_charge_phase.gd
func test_multiple_unit_charges():
    # Setup multiple eligible units
    var unit1 = _create_test_unit("unit1")
    var unit2 = _create_test_unit("unit2")
    
    # First unit charges
    phase.process_action(_make_action("SELECT_CHARGE_UNIT", {"unit_id": "unit1"}))
    phase.process_action(_make_action("DECLARE_CHARGE", {...}))
    phase.process_action(_make_action("CHARGE_ROLL", {}))
    phase.process_action(_make_action("APPLY_CHARGE_MOVE", {...}))
    phase.process_action(_make_action("COMPLETE_UNIT_CHARGE", {"unit_id": "unit1"}))
    
    # Verify unit1 is marked complete but phase continues
    assert(phase.completed_charges.has("unit1"))
    assert(not phase.is_complete)
    
    # Second unit can still charge
    var eligible = phase._get_eligible_charge_units(game_state)
    assert("unit2" in eligible)
    
    # Complete all charges
    phase.process_action(_make_action("END_CHARGE", {}))
    assert(phase.is_complete)
```

### Integration Tests
```gdscript
func test_ui_flow_multiple_charges():
    # Test UI properly resets between units
    # Test button visibility states
    # Test status label updates
```

## Validation Gates

```bash
# Run Godot tests
godot --headless -s addons/gut/gut_cmdln.gd -gtest=test_charge_phase.gd

# Check for syntax errors
godot --check-only

# Run specific charge phase tests
godot --headless -s addons/gut/gut_cmdln.gd -gtest=test_charge_phase.gd::test_multiple_unit_charges

# Run integration tests
godot --headless -s addons/gut/gut_cmdln.gd -gtest=test_*_phase.gd
```

## Error Handling

1. **No Eligible Units**: Gracefully handle when no units can charge
2. **Phase Interruption**: Handle if phase is ended mid-charge
3. **State Consistency**: Ensure UI and phase state stay synchronized
4. **Invalid Actions**: Reject attempts to charge with ineligible units

## Documentation References

- Warhammer 40k Core Rules: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#CHARGE-PHASE
- Godot Signals: https://docs.godotengine.org/en/4.4/getting_started/step_by_step/signals.html
- Godot UI Controls: https://docs.godotengine.org/en/4.4/classes/class_control.html

## Gotchas & Considerations

1. **State Synchronization**: ChargeController bypasses formal action system for model moves - need to ensure proper state updates
2. **Visual vs GameState**: Model positions update immediately during drag, not during confirmation
3. **Method Mismatch**: Main.gd may be calling wrong method names on phase objects
4. **UI Complexity**: Multiple overlapping UI states need careful management
5. **Turn Order**: Remember charge phase is NOT alternating - active player completes all charges

## Success Criteria

- [ ] Players can charge with multiple units in sequence
- [ ] Clear UI distinction between "next unit" and "end phase"
- [ ] Proper state tracking for all charging units
- [ ] Tests pass for multiple charge scenarios
- [ ] No regression in single unit charge functionality

## Confidence Score: 8/10

High confidence due to:
- Clear understanding of current architecture
- Similar pattern exists in Movement Phase
- Well-defined game rules
- Comprehensive test coverage plan

Minor risks:
- UI state management complexity
- Potential for state desync bugs

## Next Steps for Implementation

1. Start with ChargePhase.gd changes (new actions, state tracking)
2. Update ChargeController.gd for UI flow
3. Add UI components to scene
4. Write and run tests
5. Manual testing with multiple units
6. Edge case validation