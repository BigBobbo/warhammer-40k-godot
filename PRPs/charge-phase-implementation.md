# Charge Phase Implementation PRP

## Overview

Implement a complete **Charge Phase** for the Warhammer 40k Godot game following 10e core rules. This phase allows units to declare charges, roll 2D6 for charge distance, and move into engagement range with enemy units. Implementation must be deterministic, replayable, and integrate seamlessly with the existing action→result pipeline.

**Score: 9/10** - Comprehensive context provided for one-pass implementation success.

## Context & Documentation

### Core Documentation
- **Warhammer 40k 10e Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- **Godot 4.4 Documentation**: https://docs.godotengine.org/en/4.4/
- **Feature Specification**: `/Users/robertocallaghan/Documents/claude/godotv2/charge_phase.md`

### Key Rule References
From 10e Core Rules:
- Units can declare charges within **12"** (LOS not required)
- Roll **2D6** for charge distance 
- Must end **within Engagement Range (1" horiz/5" vert)** of **ALL** declared targets
- Must achieve **base-to-base contact if possible**
- Cannot end within ER of non-target enemy units
- Must maintain **unit coherency**
- Successful chargers gain **Fights First** until end of turn
- Units that Advanced or Fell Back cannot charge

## Existing Codebase Patterns

### Phase Structure Pattern
All phases extend `BasePhase.gd` which provides:
```gdscript
# BasePhase.gd:14-43
func enter_phase(state_snapshot: Dictionary) -> void
func exit_phase() -> void  
func validate_action(action: Dictionary) -> Dictionary
func process_action(action: Dictionary) -> Dictionary
func execute_action(action: Dictionary) -> Dictionary
func get_available_actions() -> Array
func _should_complete_phase() -> bool
```

### Action/Result Pipeline Pattern
Follow the same pattern as `ShootingPhase.gd`:
1. **Validation**: Check action legality in `validate_action()`
2. **Processing**: Execute action logic in `process_action()`
3. **State Changes**: Return `{"success": bool, "changes": Array, "dice": Array}`
4. **Signals**: Emit appropriate phase signals for UI updates

### Data Structure Patterns
From `GameState.gd`:
- Units have `flags` dictionary for temporary state
- State changes use JSON Patch format: `{"op": "set", "path": "units.X.flags.Y", "value": Z}`
- Models have `position: {"x": float, "y": float}` and `base_mm` for collision

### Measurement System
From `Measurement.gd`:
- Use `inches_to_px()` and `px_to_inches()` for conversions
- `distance_inches(pos1, pos2)` for edge-to-edge calculations
- `base_radius_px(base_mm)` for model collision circles

### RNG Pattern
From `RulesEngine.gd:88-104`:
```gdscript
class RNGService:
    func roll_d6(count: int) -> Array
```
Dice results format: `{"context": "charge_roll", "rolls": [3, 5], "total": 8}`

## Implementation Blueprint

### 1. Core Charge Phase Structure

**File**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/phases/ChargePhase.gd`

Replace the existing stub with full implementation following `ShootingPhase.gd` patterns:

```gdscript
extends BasePhase
class_name ChargePhase

# Charge state tracking
var active_charges: Dictionary = {}  # unit_id -> charge_data
var pending_charges: Dictionary = {}  # units awaiting resolution
var dice_log: Array = []
var units_that_charged: Array = []

# Signals (mirror ShootingPhase pattern)
signal unit_selected_for_charge(unit_id: String)
signal targets_declared(unit_id: String, target_ids: Array)
signal charge_roll_made(unit_id: String, distance: int, dice: Array)
signal charge_path_preview(unit_id: String, per_model_paths: Dictionary)
signal charge_resolved(unit_id: String, success: bool, result: Dictionary)
```

### 2. Action Types Implementation

Based on feature spec, implement these action handlers:

#### `DECLARE_CHARGE`
```gdscript
# Validation: Check 12" range, not Advanced/Fell Back, not in ER
func _validate_declare_charge(action: Dictionary) -> Dictionary:
    var unit_id = action.get("actor_unit_id", "")
    var target_ids = action.get("payload", {}).get("target_unit_ids", [])
    
    # Use RulesEngine.eligible_to_charge() pattern
    # Check each target within 12" using Measurement.distance_inches()
```

#### `CHARGE_ROLL`  
```gdscript
func _process_charge_roll(action: Dictionary) -> Dictionary:
    var rng = RulesEngine.RNGService.new()
    var rolls = rng.roll_d6(2)
    var total = rolls[0] + rolls[1]
    
    # Store in pending_charges[unit_id].distance
    # Return dice data for UI/logging
```

#### `APPLY_CHARGE_MOVE`
```gdscript
func _validate_charge_move(action: Dictionary) -> Dictionary:
    var paths = action.get("payload", {}).get("per_model_paths", {})
    
    # Validate all 4 constraints:
    # 1. All target ER (within 1")
    # 2. No non-target ER 
    # 3. Unit coherency
    # 4. Base-to-base if possible
    # 5. Path distance <= rolled distance
```

### 3. Movement Validation System

Create helper functions following `MovementPhase.gd` patterns:

```gdscript
func _validate_engagement_range_constraints(unit_id: String, final_positions: Dictionary, targets: Array) -> Dictionary:
    # Check all models end within 1" of at least one target model
    # Check no model ends within 1" of non-target enemy
    
func _validate_unit_coherency(unit_id: String, final_positions: Dictionary) -> Dictionary:
    # Use existing coherency rules from MovementPhase.gd:672+
    
func _validate_base_to_base_possible(unit_id: String, final_positions: Dictionary, targets: Array) -> Dictionary:
    # If any model CAN achieve base contact while satisfying constraints, it MUST
```

### 4. UI Integration Signals

Follow `ShootingPhase.gd` signal patterns for UI updates:

```gdscript
# Emit during different phases for UI state management
signal charge_targets_available(unit_id: String, eligible_targets: Dictionary)
signal charge_path_tools_enabled(unit_id: String, rolled_distance: int)
signal charge_validation_feedback(unit_id: String, validation_result: Dictionary)
```

### 5. RulesEngine Extensions

**File**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/autoloads/RulesEngine.gd`

Add charge helper functions following existing patterns:

```gdscript
static func eligible_to_charge(unit_id: String, board: Dictionary) -> bool:
    # Check not Advanced, not Fell Back, not in ER, not AIRCRAFT
    
static func charge_targets_within_12(unit_id: String, board: Dictionary) -> Dictionary:
    # Return eligible enemy units within 12" using edge-to-edge distance
    
static func validate_charge_paths(unit_id: String, targets: Array, roll: int, paths: Dictionary, board: Dictionary) -> Dictionary:
    # Master validation function returning {"valid": bool, "reasons": [], "auto_fix_suggestions": []}
```

## Error Handling Strategy

### Validation Failures
Return descriptive error messages following `ShootingPhase.gd` patterns:
- "Unit cannot charge after advancing this turn"
- "Target beyond 12\" charge range" 
- "Charge path would enter engagement range of non-target unit"
- "Cannot maintain unit coherency at destination"
- "Base-to-base contact possible but not achieved"

### UI Feedback
Emit validation results to UI for real-time path feedback:
```gdscript
charge_validation_feedback.emit(unit_id, {
    "valid": false,
    "primary_error": "Cannot reach all targets",
    "details": ["Target 'Boyz' unreachable", "Need 9\" but only rolled 7\""],
    "suggested_fix": "Select fewer targets or reposition models"
})
```

## Implementation Tasks

### Phase 1: Core Infrastructure
1. **Extend ChargePhase.gd** - Replace stub with full BasePhase implementation
2. **Add charge state tracking** - Dictionary structures for active charges, pending rolls
3. **Implement DECLARE_CHARGE** - Validation and target selection logic
4. **Add 12" range checking** - Using Measurement.distance_inches() for edge-to-edge
5. **Create charge eligibility checks** - Advanced, fell back, engagement range restrictions

### Phase 2: Dice and Movement
6. **Implement CHARGE_ROLL** - 2D6 rolling with RNGService, dice logging
7. **Add APPLY_CHARGE_MOVE validation** - All four constraint checking functions
8. **Implement movement distance validation** - Path length vs rolled distance
9. **Add engagement range validation** - All targets in ER, no non-targets in ER
10. **Implement unit coherency checking** - Reuse MovementPhase patterns

### Phase 3: Advanced Rules
11. **Add base-to-base enforcement** - "If possible" constraint checking
12. **Implement multi-target charges** - Must reach ALL declared targets
13. **Add Fights First flag** - Set for successful chargers
14. **Create overwatch hooks** - Signal emission for future Stratagem system
15. **Add terrain interaction** - Vertical movement costs, impassable terrain

### Phase 4: UI Integration & Testing
16. **Add phase signals** - For UI state management and visual feedback
17. **Implement get_available_actions()** - Dynamic action list based on game state
18. **Create comprehensive unit tests** - Following test_charge_phase.gd patterns
19. **Add integration tests** - Full charge sequence validation
20. **Test edge cases** - Multiple targets, terrain, failed charges

## Validation Gates

### Syntax & Style
```bash
# Run from project root
godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests/phases/ -gprefix=test_charge_phase -gexit
```

### Unit Tests  
```bash
# Charge phase specific tests
godot --headless --script addons/gut/gut_cmdln.gd -gtest=test_charge_phase.gd -gexit
```

### Integration Tests
```bash
# Full phase integration 
godot --headless --script addons/gut/gut_cmdln.gd -gtest=test_phase_transitions.gd -gexit
```

### Manual Validation
1. **Declare charge within 12"** - Should succeed
2. **Declare charge beyond 12"** - Should fail with clear message
3. **Roll 2D6 and move** - Models should reach engagement range
4. **Multi-target charge** - Must reach ALL targets or fail
5. **Base-to-base enforcement** - Models should contact enemy bases when possible
6. **Coherency maintenance** - Unit must stay in coherency during charge
7. **Advanced/Fell Back units** - Should be unable to charge
8. **Fights First application** - Successful chargers should gain priority

## Critical References

### Code Files to Reference
- **BasePhase.gd** - Phase interface and execution patterns
- **ShootingPhase.gd** - Complete phase implementation example  
- **MovementPhase.gd** - Model movement and engagement range logic
- **RulesEngine.gd** - Validation functions and dice rolling patterns
- **Measurement.gd** - Distance calculations and conversions
- **GameState.gd** - Data structures and flag patterns

### Test Files to Reference  
- **test_charge_phase.gd** - Test structure and validation patterns
- **test_shooting_phase.gd** - Phase testing methodology
- **test_movement_phase.gd** - Movement validation testing

### Key Implementation Gotchas
1. **Edge-to-edge distances** - Always use `Measurement.distance_inches()` with base radii
2. **Multiple target validation** - Must reach ALL targets, not just one
3. **Base-to-base enforcement** - Check if possible BEFORE requiring it
4. **Unit coherency** - Models must stay within 2" of another model after move
5. **State change format** - Use JSON Patch format for all game state modifications
6. **Signal emission timing** - Emit BEFORE applying state changes for UI responsiveness
7. **RNG determinism** - Always use RNGService for reproducible dice rolls
8. **Engagement range** - 1" horizontal, use consistent measurement throughout

## Expected Deliverables

1. **Complete ChargePhase.gd** - Full implementation replacing stub
2. **RulesEngine charge helpers** - Support functions for validation
3. **Comprehensive test suite** - Unit and integration tests
4. **UI signal integration** - Proper state communication
5. **Documentation updates** - Code comments and integration notes

## Success Metrics

- All existing tests continue to pass
- New charge phase tests achieve 100% pass rate  
- Manual gameplay testing shows correct 10e rule implementation
- Deterministic replay works correctly with charge actions
- UI provides clear feedback for all validation failures
- Performance remains acceptable with complex multi-model charges

This PRP provides complete context for implementing a production-ready charge phase that integrates seamlessly with the existing Warhammer 40k Godot game architecture.