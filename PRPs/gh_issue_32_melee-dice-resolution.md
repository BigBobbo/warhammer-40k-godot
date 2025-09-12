# PRP: Fix Melee Combat Dice Rolling and Debug Logging (GitHub Issue #32)

## Summary

Fix critical issues preventing melee combat dice results from displaying correctly, implement proper debug logging controls, and ensure compliance with Warhammer 40K 10th Edition core rules for melee attack resolution.

## Problem Analysis

Based on comprehensive codebase research and issue analysis:

### Core Issues Identified

1. **Dice Display Format Mismatch** 
   - `FightController._on_dice_rolled()` expects `rolls_raw` and `successes` fields
   - `RulesEngine._resolve_melee_assignment()` sends individual dice objects with `roll`, `target`, `success` fields
   - Result: "Hit Roll Melee: [] -> 0 successes" instead of actual dice results

2. **Debug Output Overflow**
   - Excessive logging is truncating Godot debug output
   - No debug mode toggle for melee/fight phase logging
   - Prevents effective debugging of combat resolution

3. **Melee Attack Resolution Display**
   - Missing proper breakdown by weapon type
   - No clear display of attack sequence (hits → wounds → saves → damage)
   - Duplicate weapons not properly grouped in output

## Technical Context

### Current Implementation Analysis

**File**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/autoloads/RulesEngine.gd:1383-1483`

The melee attack resolution is functionally correct:
- Uses weapon_skill from weapon profile (e.g., "3" = 3+ to hit)
- Rolls `total_attacks` dice vs weapon_skill threshold
- Follows proper hit → wound → save → damage sequence

**File**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/FightController.gd:1161-1170`

The UI display handler expects different data format:
```gdscript
var rolls = dice_data.get("rolls_raw", [])  # Expected but not provided
var successes = dice_data.get("successes", 0)  # Expected but not provided
```

### Reference Implementation Pattern

**From ShootingPhase**: Similar combat resolution that works correctly
- Groups dice results by roll type
- Provides summary statistics
- Handles weapon-specific display

## Implementation Blueprint

### Phase 1: Fix Dice Display Format (Priority 1)

**File**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/autoloads/RulesEngine.gd`

#### Task 1.1: Standardize Dice Result Format
```gdscript
# In _resolve_melee_assignment(), add result aggregation:

# After hit rolls loop
var hit_summary = {
    "context": "hit_roll_melee",
    "rolls_raw": hit_rolls,
    "successes": hits,
    "target": weapon_skill,
    "weapon": weapon_id,
    "total_attacks": total_attacks
}
result.dice.append(hit_summary)

# After wound rolls loop  
var wound_summary = {
    "context": "wound_roll",
    "rolls_raw": wound_rolls,
    "successes": wounds,
    "target": wound_target,
    "weapon": weapon_id
}
result.dice.append(wound_summary)

# After save rolls loop
var save_summary = {
    "context": "armor_save",
    "rolls_raw": save_rolls,
    "successes": successful_saves,
    "target": modified_save,
    "weapon": weapon_id
}
result.dice.append(save_summary)
```

#### Task 1.2: Remove Individual Dice Entries
Remove the individual dice object creation inside the roll loops to prevent format confusion.

### Phase 2: Implement Debug Logging Controls (Priority 2)

**File**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/phases/FightPhase.gd`

#### Task 2.1: Add Debug Mode Toggle
```gdscript
# Add debug mode control at top of class
var melee_debug_mode: bool = false  # Toggle for melee combat debug output

# Add debug mode setter
func set_melee_debug_mode(enabled: bool) -> void:
    melee_debug_mode = enabled
    log_phase_message("Melee debug mode: %s" % ("ON" if enabled else "OFF"))

# Wrap all debug prints with debug mode check
func log_melee_debug(message: String) -> void:
    if melee_debug_mode:
        print("MELEE_DEBUG: " + message)
```

#### Task 2.2: Replace Debug Print Statements
Replace all `print("DEBUG: ...")` statements in melee-related functions with `log_melee_debug()`.

**Files affected**:
- `FightPhase.gd`: Lines 492-494, 513-514, 543, 557
- `FightController.gd`: Various debug prints in fight-related methods

#### Task 2.3: Add Debug Mode UI Control
```gdscript
# In FightController._setup_right_panel(), add debug toggle
var debug_container = HBoxContainer.new()
var debug_label = Label.new()
debug_label.text = "Debug Mode:"
debug_container.add_child(debug_label)

var debug_checkbox = CheckBox.new()
debug_checkbox.button_pressed = false
debug_checkbox.toggled.connect(_on_debug_mode_toggled)
debug_container.add_child(debug_checkbox)
fight_panel.add_child(debug_container)

func _on_debug_mode_toggled(pressed: bool) -> void:
    if current_phase and current_phase.has_method("set_melee_debug_mode"):
        current_phase.set_melee_debug_mode(pressed)
```

### Phase 3: Enhance Combat Results Display (Priority 3)

**File**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/FightController.gd`

#### Task 3.1: Update Dice Display Handler
```gdscript
func _on_dice_rolled(dice_data: Dictionary) -> void:
    if not dice_log_display:
        return
    
    var context = dice_data.get("context", "")
    
    # Handle different contexts with proper formatting
    match context:
        "hit_roll_melee":
            _display_hit_results(dice_data)
        "wound_roll":
            _display_wound_results(dice_data)  
        "armor_save":
            _display_save_results(dice_data)
        "mathhammer_prediction":
            _display_prediction(dice_data)
        "resolution_start":
            _display_resolution_start(dice_data)
        _:
            # Fallback for legacy format
            _display_generic_dice_result(dice_data)

func _display_hit_results(data: Dictionary) -> void:
    var weapon = data.get("weapon", "Unknown")
    var weapon_name = RulesEngine.get_weapon_profile(weapon).get("name", weapon)
    var rolls = data.get("rolls_raw", [])
    var hits = data.get("successes", 0)
    var total = data.get("total_attacks", rolls.size())
    var target = data.get("target", 4)
    
    var roll_display = []
    for roll in rolls:
        if roll >= target:
            roll_display.append("[color=green]%d[/color]" % roll)
        else:
            roll_display.append("[color=red]%d[/color]" % roll)
    
    dice_log_display.append_text("[b]%s Hit Rolls (need %d+):[/b] [%s] → %d/%d hits\n" % 
        [weapon_name, target, ", ".join(roll_display), hits, total])
```

#### Task 3.2: Group Duplicate Weapons
```gdscript
# In _display_hit_results() and similar functions, group by weapon type
var weapon_groups = {}  # weapon_id -> {total_attacks: int, total_hits: int, all_rolls: Array}

# Process all dice results and group by weapon before displaying
```

### Phase 4: Validation and Testing

#### Task 4.1: Unit Tests
Create comprehensive test coverage:

**File**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/tests/unit/test_melee_dice_display.gd`
```gdscript
extends GutTest

func test_melee_dice_format():
    # Test dice result format matches expected structure
    var rng = RulesEngine.RNGService.new()
    var action = _create_test_melee_action()
    var board = _create_test_board_state()
    
    var result = RulesEngine.resolve_melee_attacks(action, board, rng)
    
    assert_true(result.success, "Melee resolution should succeed")
    assert_gt(result.dice.size(), 0, "Should have dice results")
    
    # Check hit roll format
    var hit_result = result.dice[0]
    assert_eq(hit_result.context, "hit_roll_melee")
    assert_true(hit_result.has("rolls_raw"))
    assert_true(hit_result.has("successes"))

func test_debug_mode_toggle():
    var fight_phase = FightPhase.new()
    fight_phase.set_melee_debug_mode(true)
    assert_eq(fight_phase.melee_debug_mode, true)
```

#### Task 4.2: Integration Tests
**File**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/tests/integration/test_melee_combat_flow.gd`
```gdscript
func test_full_melee_combat_display():
    # Test complete melee combat from selection to dice display
    var fight_controller = _setup_fight_controller()
    var fight_phase = _setup_test_fight_phase()
    
    # Simulate complete combat sequence
    _select_fighter("space_marine_tactical")
    _assign_attacks("chainsword", "ork_boyz")
    _confirm_attacks()
    _roll_dice()
    
    # Verify dice display shows proper results
    var dice_log_text = fight_controller.dice_log_display.get_parsed_text()
    assert_true("hit" in dice_log_text.to_lower())
    assert_true("wound" in dice_log_text.to_lower())
```

## Validation Gates

### Automated Testing
```bash
# Export Godot path if not available
export PATH="$HOME/bin:$PATH"

# Run melee-specific tests
godot --headless --script addons/gut/gut_cmdln.gd -gtest="test_melee_dice" -gexit

# Integration test for full combat flow  
godot --headless --script addons/gut/gut_cmdln.gd -gtest="test_melee_combat_flow" -gexit

# Performance test for debug logging
godot --headless --script addons/gut/gut_cmdln.gd -gtest="test_debug_performance" -gexit
```

### Manual Validation Checklist
1. **Dice Display**: Melee attacks show individual dice results with proper success/failure coloring
2. **Debug Mode**: Toggle successfully reduces debug output in Godot console
3. **Weapon Grouping**: Duplicate weapons display together with combined statistics
4. **Rules Compliance**: Attack resolution follows https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#Making-Attacks

## Implementation Tasks (Ordered)

1. **Fix dice result format in RulesEngine._resolve_melee_assignment()** - Creates proper summary objects
2. **Update FightController._on_dice_rolled()** - Handles new dice format with proper display
3. **Add debug mode controls to FightPhase** - Reduces console output overflow
4. **Implement weapon grouping in dice display** - Shows duplicate weapons together
5. **Add debug mode UI toggle** - User-controllable debug output
6. **Remove excessive debug prints** - Replace with conditional logging
7. **Write unit tests for dice format** - Ensures format consistency
8. **Write integration tests for combat flow** - Full sequence validation
9. **Add performance tests for logging** - Verify debug mode impact

## Expected Outcome

After implementation:
- Melee attacks display: "Chainsword Hit Rolls (need 3+): [4, 6, 2, 5] → 3/4 hits"
- Wound rolls: "Wound Rolls (need 4+): [3, 5, 6] → 2/3 wounds" 
- Save rolls: "Armor Saves (need 6+): [4, 2] → 0/2 saves"
- Final damage: "2 wounds caused to Ork Boyz"
- Debug mode toggle reduces console spam
- Combat follows proper Warhammer 40K sequence

## Risk Assessment

**Low Risk**: Core melee resolution logic is correct, only display formatting needs changes
**Medium Risk**: Debug mode changes require careful testing to avoid breaking existing functionality
**Mitigation**: Comprehensive unit tests and integration tests ensure no regressions

## Documentation References

- **Warhammer 40K Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#Making-Attacks
- **Godot Documentation**: https://docs.godotengine.org/en/4.4/
- **Existing Shooting Phase**: Reference implementation for dice display patterns

## Quality Score: 9/10

High confidence for one-pass implementation success due to:
- Clear root cause identification
- Comprehensive codebase analysis  
- Reference patterns from working shooting phase
- Well-defined validation gates
- Modular task breakdown with minimal interdependencies

The remaining 10% risk accounts for potential edge cases in weapon grouping and UI threading considerations.