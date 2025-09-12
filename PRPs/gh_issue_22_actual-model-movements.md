# Product Requirements Document: Actual Model Movements

## Issue Reference
GitHub Issue #22: Actual Model Movements

## Feature Description
Fix the movement phase to use each unit's actual movement stat from their profile data instead of the hardcoded default value of 6 inches. Currently, all models are moving 6 inches regardless of their profile's movement characteristic. For example, the Caladius Grav tank has a movement of 10 inches in its profile but is limited to 6 inches during gameplay.

## Requirements
1. Use unit's actual movement stat from their profile data (unit.meta.stats.move)
2. Remove hardcoded 6-inch fallback values in movement calculations
3. Ensure all movement types (Normal, Advance, Fall Back) use correct movement values
4. Update UI to display correct movement values
5. Update tests to validate variable movement values

## Implementation Context

### Current Issue Analysis

The movement system is already correctly architected to read from `unit.meta.stats.move`, but the fallback value of 6 is being used instead of the actual profile value. Investigation shows:

1. **Data Structure is Correct**: Units have proper movement stats in their profiles
2. **Code Pattern is Correct**: The system uses `unit.get("meta", {}).get("stats", {}).get("move", 6)`
3. **Issue**: The fallback is being triggered, suggesting the data path is not matching the actual structure

### File Locations and Current Implementation

#### Movement Phase Logic
**File: `/Users/robertocallaghan/Documents/claude/godotv2/40k/phases/MovementPhase.gd`**

Current hardcoded fallbacks:
- Line 336: Normal Move - `var move_inches = unit.get("meta", {}).get("stats", {}).get("move", 6)`
- Line 362: Advance Move - `var move_inches = unit.get("meta", {}).get("stats", {}).get("move", 6)`
- Line 407: Fall Back Move - `var move_inches = unit.get("meta", {}).get("stats", {}).get("move", 6)`

#### UI Display
**File: `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/MovementController.gd`**
- Line 480: UI fallback - `move_cap_inches = unit.get("flags", {}).get("move_cap_inches", 6.0)`

#### Test File
**File: `/Users/robertocallaghan/Documents/claude/godotv2/40k/tests/phases/test_movement_phase.gd`**
- Line 60: Currently expects 6.0 - needs updating for variable movement

### Profile Data Structure (Verified)

**Example from `/Users/robertocallaghan/Documents/claude/godotv2/40k/armies/adeptus_custodes.json`:**
```json
{
  "meta": {
    "name": "Caladius Grav-tank",
    "stats": {
      "move": 10,
      "toughness": 11,
      "save": 2,
      "wounds": 14,
      "leadership": 6,
      "objective_control": 4
    }
  }
}
```

### Existing Pattern for Accessing Stats

**From `/Users/robertocallaghan/Documents/claude/godotv2/40k/autoloads/RulesEngine.gd`:**
```gdscript
var toughness = target_unit.get("meta", {}).get("stats", {}).get("toughness", 4)
var base_save = target_unit.get("meta", {}).get("stats", {}).get("save", 7)
```

## Root Cause Analysis

After investigation, the likely issue is that the unit data being passed to the movement phase might not have the expected structure. The unit data may be:
1. Missing the meta/stats structure at runtime
2. Being transformed/flattened somewhere in the data pipeline
3. Not being properly loaded from the JSON files

## Technical Approach

### 1. Debug and Verify Data Structure
```gdscript
# Add debugging to MovementPhase.gd to verify unit structure
func _process_normal_move(unit_id: String, _destination: Vector2, _nodes: Array) -> bool:
    var unit = BattleState.get_unit(unit_id)
    
    # DEBUG: Log unit structure to verify data
    print("DEBUG: Unit structure for ", unit_id, ":")
    print("  Has meta? ", unit.has("meta"))
    if unit.has("meta"):
        print("  Has stats? ", unit.meta.has("stats"))
        if unit.meta.has("stats"):
            print("  Movement value: ", unit.meta.stats.get("move", "NOT FOUND"))
    
    # Get movement with proper error handling
    var move_inches = 6  # Default fallback
    if unit.has("meta") and unit.meta.has("stats") and unit.meta.stats.has("move"):
        move_inches = unit.meta.stats.move
    else:
        push_warning("Unit %s missing movement stat, using default: 6" % unit_id)
```

### 2. Fix Data Access Pattern
```gdscript
# Ensure consistent data access pattern across all movement types
func get_unit_movement(unit: Dictionary) -> float:
    # Try multiple data paths to be robust
    # First try the expected path
    if unit.has("meta") and unit.meta.has("stats") and unit.meta.stats.has("move"):
        return float(unit.meta.stats.move)
    
    # Try nested get with type safety
    var stats = unit.get("meta", {}).get("stats", {})
    if stats and stats.has("move"):
        return float(stats.get("move"))
    
    # Log warning and return default
    push_warning("Unit missing movement stat: %s" % unit.get("meta", {}).get("name", "Unknown"))
    return 6.0
```

### 3. Update Movement Phase Implementation
```gdscript
# MovementPhase.gd - Update all movement processing functions
func _process_normal_move(unit_id: String, destination: Vector2, nodes: Array) -> bool:
    var unit = BattleState.get_unit(unit_id)
    var move_inches = get_unit_movement(unit)  # Use helper function
    
    # Calculate actual pixels based on unit's movement stat
    var move_cap_pixels = move_inches * PIXELS_PER_INCH
    # ... rest of movement logic
```

### 4. Update Movement Controller UI
```gdscript
# MovementController.gd - Update UI to show correct movement
func _update_selected_unit(unit_id: String):
    var unit = BattleState.get_unit(unit_id)
    
    # Get actual movement from profile
    var move_inches = get_unit_movement(unit)
    
    # Update UI display
    move_cap_inches = move_inches
    
    # Update range indicator
    _update_movement_range_indicator(move_inches * PIXELS_PER_INCH)
```

### 5. Fix Tests
```gdscript
# test_movement_phase.gd - Update to use actual unit movement values
func test_movement_cap_calculation():
    # Create test unit with specific movement value
    var test_unit = {
        "meta": {
            "name": "Test Unit",
            "stats": {
                "move": 8  # Test with 8" movement
            }
        }
    }
    
    var movement_phase = MovementPhase.new()
    var move_data = movement_phase.calculate_movement_data(test_unit)
    
    # Should match unit's actual movement stat
    assert_eq(8.0, move_data.move_cap_inches, "Move cap should match unit's movement stat")
```

## Implementation Tasks

1. **Add Debug Logging** (Priority: High)
   - Add comprehensive logging to understand data structure at runtime
   - Log unit data when movement is calculated
   - Identify where data structure diverges from expected format

2. **Create Movement Helper Function** (Priority: High)
   - Implement `get_unit_movement()` helper function
   - Use consistent data access pattern
   - Add proper error handling and logging

3. **Update Movement Phase** (Priority: High)
   - Replace all hardcoded 6 fallbacks with helper function
   - Update Normal Move processing (line 336)
   - Update Advance Move processing (line 362)
   - Update Fall Back Move processing (line 407)

4. **Update Movement Controller UI** (Priority: High)
   - Fix UI to display correct movement values (line 480)
   - Ensure movement range indicators use actual stats
   - Update any movement previews

5. **Verify Data Pipeline** (Priority: High)
   - Trace how unit data flows from JSON to runtime
   - Ensure BattleState.get_unit() returns complete data
   - Check if data is being transformed anywhere

6. **Update and Run Tests** (Priority: High)
   - Update test expectations for variable movement
   - Add tests for different unit types with different movement values
   - Test edge cases (missing data, invalid values)

7. **Test with Multiple Units** (Priority: High)
   - Test with Caladius Grav-tank (10" movement)
   - Test with standard infantry (6" movement)
   - Test with other unit types to ensure variety works

8. **Remove Debug Logging** (Priority: Low)
   - Once fixed, remove or comment debug statements
   - Keep useful warnings for missing data

## Validation Gates

```bash
# Run Godot editor to test
export PATH="$HOME/bin:$PATH"

# 1. Run automated tests
godot --headless --script res://40k/tests/phases/test_movement_phase.gd

# 2. Manual testing checklist:
# - Load a game with Caladius Grav-tank
# - Select the Caladius in movement phase
# - Verify movement range shows 10" (not 6")
# - Move the unit and verify it can move full 10"
# - Test with infantry unit (should be 6")
# - Test advance move (should add D6 to base movement)
# - Test fall back move (should use base movement)

# 3. Verify no regression in save/load
godot --headless --script res://40k/tests/test_save_load.gd
```

## External Resources

### Warhammer 40k Rules
- Core Rules (Movement): https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- Movement Phase Details: Standard units move their Movement characteristic in inches
- Advance: Add D6" to movement but cannot shoot/charge
- Fall Back: Move up to Movement characteristic when leaving engagement

### Godot Documentation
- Dictionary Access: https://docs.godotengine.org/en/4.4/classes/class_dictionary.html
- Debugging in Godot: https://docs.godotengine.org/en/4.4/tutorials/scripting/debug/overview.html
- Unit Testing: https://docs.godotengine.org/en/4.4/tutorials/scripting/debug/unit_testing.html

## Common Pitfalls to Avoid

1. **Type Conversion**: Movement values may be stored as int but need float for calculations
2. **Data Loading**: Ensure JSON data is fully loaded before accessing
3. **Reference vs Copy**: Be careful with Dictionary references when modifying unit data
4. **Save/Load Compatibility**: Ensure changes don't break existing save files
5. **UI Sync**: Movement indicators must update when unit selection changes

## Implementation Blueprint (Pseudocode)

```
FUNCTION get_unit_movement(unit):
    IF unit has proper nested structure:
        RETURN unit.meta.stats.move as float
    ELSE:
        LOG warning with unit name
        RETURN 6.0

FUNCTION process_movement(unit_id, destination):
    unit = get_unit_from_state(unit_id)
    base_movement = get_unit_movement(unit)
    
    IF movement_type == ADVANCE:
        movement = base_movement + roll_d6()
    ELSE:
        movement = base_movement
    
    pixels_allowed = movement * PIXELS_PER_INCH
    
    IF distance_to_destination <= pixels_allowed:
        ALLOW movement
    ELSE:
        RESTRICT to maximum distance

FUNCTION update_movement_ui(unit):
    movement = get_unit_movement(unit)
    display_range_indicator(movement * PIXELS_PER_INCH)
    update_movement_label(movement + " inches")
```

## Success Criteria

1. Caladius Grav-tank can move 10" (not limited to 6")
2. Standard infantry still move 6" correctly
3. All unit types use their profile movement values
4. Movement UI displays correct values for each unit
5. Advance adds D6 to unit's base movement (not to 6)
6. Fall Back uses unit's base movement
7. Tests pass with variable movement values
8. No regression in save/load functionality

## Confidence Score: 9/10

**Rationale**: Very high confidence due to:
- Problem is well-defined and isolated
- Code structure already supports the feature
- Clear pattern exists in codebase for accessing stats
- Minimal changes required (mainly removing fallbacks)
- Low risk of breaking other features

**Risk factors**:
- Data pipeline issue might be more complex than anticipated
- Potential edge cases with certain unit types
- May need to handle legacy save files

## Notes for AI Implementation Agent

### CRITICAL FIRST STEP
Before making any changes, add debug logging to understand why the fallback is being triggered. The issue may be:
1. Data structure mismatch (check exact Dictionary keys)
2. Type issues (int vs float)
3. Data not being loaded properly from JSON

### Key Files to Modify
1. `/Users/robertocallaghan/Documents/claude/godotv2/40k/phases/MovementPhase.gd` - Lines 336, 362, 407
2. `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/MovementController.gd` - Line 480
3. `/Users/robertocallaghan/Documents/claude/godotv2/40k/tests/phases/test_movement_phase.gd` - Line 60

### Testing Priority
1. Test with Caladius Grav-tank first (known 10" movement)
2. Verify standard infantry still work (6" movement)
3. Check save/load compatibility

### Do NOT
- Change the data structure in JSON files
- Modify how units are stored in BattleState
- Break existing save file compatibility
- Remove the fallback entirely (keep it for error cases)

The fix should be surgical - identify why the data isn't being read correctly and fix that specific issue.