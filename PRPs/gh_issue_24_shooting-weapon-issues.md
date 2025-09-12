# 🎯 Shooting Weapon Issues - Implementation PRP

## Problem Statement
GitHub Issue #24: "It appears that the updated data format for units has broken the shooting phase. When I select a unit to shoot now in the shooting phase none of the units weapons show up in the shooting panel to select a target. This is despite the weapons showing up in the units stats. For example the Caladius grav tank has a Twin arachnus heavy blaze cannon and a Twin lastrum bolt cannon but neither are showing."

### Root Cause Analysis
After comprehensive investigation of the shooting phase and weapon data systems:

1. **Data Format Evolution**: The game has evolved to use a comprehensive army data format where units store their weapons in `meta.weapons` array with full weapon profiles
2. **Legacy System Dependency**: The shooting phase still relies on the old simplified `UNIT_WEAPONS` dictionary in RulesEngine.gd
3. **Missing Unit Entries**: The `UNIT_WEAPONS` dictionary only contains 4 basic units:
   - `U_INTERCESSORS_A`
   - `U_TACTICAL_A`
   - `U_BOYZ_A`
   - `U_GRETCHIN_A`
4. **Modern Units Not Supported**: Units like `U_CALADIUS_GRAV-TANK_E`, `U_BLADE_CHAMPION_A`, `U_CUSTODIAN_GUARD_B`, etc. are not in the dictionary

**The core issue**: `ShootingController._refresh_weapon_tree()` calls `RulesEngine.get_unit_weapons(active_shooter_id)` which returns an empty dictionary for modern units, causing no weapons to display in the UI.

### Impact Analysis
- **Affected Units**: All units except the 4 basic ones (95%+ of units in the game)
- **User Experience**: Shooting phase appears broken for modern army compositions
- **Data Inconsistency**: Weapons visible in unit stats but not in shooting interface

## Implementation Blueprint

### Solution Approach
Migrate the shooting system from the legacy `UNIT_WEAPONS` dictionary to the modern army data format:

1. **Update RulesEngine**: Modify `get_unit_weapons()` to read from unit `meta.weapons` data
2. **Create Weapon ID System**: Generate consistent weapon IDs from weapon names for targeting
3. **Update Weapon Profile Lookup**: Modify `get_weapon_profile()` to work with new weapon data
4. **Maintain Backward Compatibility**: Ensure existing functionality continues to work
5. **Validate Implementation**: Test with both legacy and modern units

### Critical Context for Implementation

#### Current Data Format Examples

**Legacy Format** (RulesEngine.gd:52-86):
```gdscript
const UNIT_WEAPONS = {
    "U_INTERCESSORS_A": {
        "m1": ["bolt_rifle"],
        "m2": ["bolt_rifle"],
        "m3": ["bolt_rifle"],
        "m4": ["bolt_rifle"],
        "m5": ["bolt_rifle", "plasma_pistol"]
    }
}
```

**Modern Format** (adeptus_custodes.json:528-550 & save files):
```json
{
    "meta": {
        "weapons": [
            {
                "name": "Twin arachnus heavy blaze cannon",
                "type": "Ranged",
                "range": "48",
                "attacks": "4",
                "ballistic_skill": "2",
                "strength": "12",
                "ap": "-3",
                "damage": "D6+2",
                "special_rules": "twin-linked"
            },
            {
                "name": "Twin lastrum bolt cannon",
                "type": "Ranged",
                "range": "36",
                "attacks": "3",
                "ballistic_skill": "2",
                "strength": "6",
                "ap": "-1",
                "damage": "1",
                "special_rules": "sustained hits 1"
            }
        ]
    }
}
```

#### Key Files and Functions

**ShootingController.gd:346** - Weapon retrieval:
```gdscript
var unit_weapons = RulesEngine.get_unit_weapons(active_shooter_id)
```

**RulesEngine.gd:667-668** - Current implementation:
```gdscript
static func get_unit_weapons(unit_id: String) -> Dictionary:
    return UNIT_WEAPONS.get(unit_id, {})
```

**ShootingController.gd:358** - Weapon profile lookup:
```gdscript
var weapon_profile = RulesEngine.get_weapon_profile(weapon_id)
```

#### External Documentation References

- **Warhammer 40k Shooting Phase Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#SHOOTING-PHASE
  - Target selection and weapon assignment principles
  - Attack sequence: Hit, Wound, Allocate, Save, Damage
  - Line of sight and targeting restrictions

- **Godot 4.4 Dictionary Documentation**: https://docs.godotengine.org/en/4.4/classes/class_dictionary.html
  - Dictionary manipulation and access patterns
  - Safe key access with default values

- **JSON Data Structure Best Practices**: https://docs.godotengine.org/en/4.4/tutorials/io/data_paths.html
  - Loading and parsing game data files
  - Data validation and error handling

## Tasks to Complete (In Order)

### Task 1: Update RulesEngine.get_unit_weapons() Method
**File**: 40k/autoloads/RulesEngine.gd
**Function**: Replace existing method (line 667-668)

```gdscript
static func get_unit_weapons(unit_id: String) -> Dictionary:
    # First try legacy format for backward compatibility
    if UNIT_WEAPONS.has(unit_id):
        return UNIT_WEAPONS.get(unit_id, {})
    
    # Get unit from current game state
    var game_state = GameState.get_board()
    var units = game_state.get("units", {})
    var unit = units.get(unit_id, {})
    
    if unit.is_empty():
        print("WARNING: Unit not found: ", unit_id)
        return {}
    
    # Convert modern weapons format to model-weapon mapping
    var weapons = unit.get("meta", {}).get("weapons", [])
    var models = unit.get("models", [])
    var result = {}
    
    # Assign all weapons to all alive models (simplified approach)
    for model in models:
        var model_id = model.get("id", "")
        if model_id != "" and model.get("alive", true):
            result[model_id] = []
            for weapon in weapons:
                if weapon.get("type", "") == "Ranged":  # Only include ranged weapons for shooting
                    var weapon_id = _generate_weapon_id(weapon.get("name", ""))
                    result[model_id].append(weapon_id)
    
    return result

# Helper function to generate consistent weapon IDs from names
static func _generate_weapon_id(weapon_name: String) -> String:
    # Convert weapon name to consistent ID format
    var weapon_id = weapon_name.to_lower()
    weapon_id = weapon_id.replace(" ", "_")
    weapon_id = weapon_id.replace("-", "_")
    weapon_id = weapon_id.replace("'", "")
    return weapon_id
```

### Task 2: Update RulesEngine.get_weapon_profile() Method
**File**: 40k/autoloads/RulesEngine.gd
**Function**: Replace existing method (line 671-672)

```gdscript
static func get_weapon_profile(weapon_id: String) -> Dictionary:
    # First try legacy weapon profiles
    if WEAPON_PROFILES.has(weapon_id):
        return WEAPON_PROFILES.get(weapon_id, {})
    
    # Search through all units for matching weapon
    var game_state = GameState.get_board()
    var units = game_state.get("units", {})
    
    for unit_id in units:
        var unit = units[unit_id]
        var weapons = unit.get("meta", {}).get("weapons", [])
        
        for weapon in weapons:
            var weapon_name = weapon.get("name", "")
            var generated_id = _generate_weapon_id(weapon_name)
            
            if generated_id == weapon_id:
                # Convert weapon format to profile format expected by UI
                return {
                    "name": weapon_name,
                    "type": weapon.get("type", ""),
                    "range": weapon.get("range", "0"),
                    "attacks": weapon.get("attacks", "1"),
                    "ballistic_skill": weapon.get("ballistic_skill", "4"),
                    "weapon_skill": weapon.get("weapon_skill", "4"),
                    "strength": weapon.get("strength", "3"),
                    "ap": weapon.get("ap", "0"),
                    "damage": weapon.get("damage", "1"),
                    "special_rules": weapon.get("special_rules", "")
                }
    
    print("WARNING: Weapon profile not found: ", weapon_id)
    return {}
```

### Task 3: Update Weapon Count Logic in ShootingController
**File**: 40k/scripts/ShootingController.gd
**Function**: Update _refresh_weapon_tree() method (line 338-372)

```gdscript
func _refresh_weapon_tree() -> void:
    if not weapon_tree or active_shooter_id == "":
        return
    
    weapon_tree.clear()
    var root = weapon_tree.create_item()
    
    # Get unit weapons from RulesEngine (now works with modern format)
    var unit_weapons = RulesEngine.get_unit_weapons(active_shooter_id)
    var weapon_counts = {}
    
    # Count weapons by type
    for model_id in unit_weapons:
        for weapon_id in unit_weapons[model_id]:
            if not weapon_counts.has(weapon_id):
                weapon_counts[weapon_id] = 0
            weapon_counts[weapon_id] += 1
    
    # Create tree items for each weapon type
    for weapon_id in weapon_counts:
        var weapon_profile = RulesEngine.get_weapon_profile(weapon_id)
        
        # Skip if weapon profile not found (defensive programming)
        if weapon_profile.is_empty():
            print("WARNING: Skipping weapon with missing profile: ", weapon_id)
            continue
            
        var weapon_item = weapon_tree.create_item(root)
        weapon_item.set_text(0, "%s (x%d)" % [weapon_profile.get("name", weapon_id), weapon_counts[weapon_id]])
        weapon_item.set_metadata(0, weapon_id)
        
        # Add target selector in second column
        if eligible_targets.size() > 0:
            weapon_item.set_text(1, "[Click to Select]")
            weapon_item.set_selectable(0, true)
            weapon_item.set_selectable(1, false)
            
            # Add auto-assign button
            weapon_item.add_button(1, preload("res://icon.svg"), 0, false, "Auto-assign first target")
```

### Task 4: Add Validation and Error Handling
**File**: 40k/autoloads/RulesEngine.gd
**Function**: Add after existing methods

```gdscript
# Validation function to check if unit has weapons
static func unit_has_weapons(unit_id: String) -> bool:
    var unit_weapons = get_unit_weapons(unit_id)
    
    for model_id in unit_weapons:
        if not unit_weapons[model_id].is_empty():
            return true
    
    return false

# Debug function to list all weapons for a unit
static func debug_unit_weapons(unit_id: String) -> void:
    print("=== DEBUGGING WEAPONS FOR UNIT: ", unit_id, " ===")
    
    var unit_weapons = get_unit_weapons(unit_id)
    if unit_weapons.is_empty():
        print("NO WEAPONS FOUND")
        return
    
    for model_id in unit_weapons:
        print("Model ", model_id, ":")
        for weapon_id in unit_weapons[model_id]:
            var profile = get_weapon_profile(weapon_id)
            print("  - ", weapon_id, " (", profile.get("name", "Unknown"), ")")
    
    print("=== END WEAPON DEBUG ===")
```

### Task 5: Add Logging for Troubleshooting
**File**: 40k/scripts/ShootingController.gd
**Function**: Update _on_unit_selected_for_shooting() (line 683-688)

```gdscript
func _on_unit_selected_for_shooting(unit_id: String) -> void:
    active_shooter_id = unit_id
    weapon_assignments.clear()
    
    # Debug logging
    print("Selected shooter: ", unit_id)
    if RulesEngine.has_method("debug_unit_weapons"):
        RulesEngine.debug_unit_weapons(unit_id)
    
    _refresh_weapon_tree()
    _update_ui_state()
    _show_range_indicators()
```

## Validation Gates

### Automated Tests
```bash
# Run Godot test suite
godot --headless --script addons/gut/gut_cmdln.gd -gexit

# Focus on shooting phase tests
godot --headless --script addons/gut/gut_cmdln.gd -gdir=40k/tests/phases -gexit
```

### Manual Validation Steps
1. **Legacy Units Test**: Verify Intercessors, Tactical Marines, Boyz, and Gretchin still work
2. **Modern Units Test**: Load save with Caladius Grav-tank, verify weapons appear
3. **Weapon Display Test**: Confirm "Twin arachnus heavy blaze cannon" and "Twin lastrum bolt cannon" show in UI
4. **Target Assignment Test**: Verify weapon assignment and shooting resolution works
5. **Profile Accuracy Test**: Check weapon stats match army data files

### Test Scenarios
1. Load quicksave.w40ksave (contains Caladius Grav-tank)
2. Enter shooting phase
3. Select Caladius Grav-tank
4. Verify 2 ranged weapons appear in weapon tree
5. Assign targets and confirm shooting works

## Success Criteria
- [ ] All units in game can shoot (not just the 4 legacy ones)
- [ ] Caladius Grav-tank shows "Twin arachnus heavy blaze cannon" and "Twin lastrum bolt cannon"
- [ ] Weapon assignment and targeting works for modern units
- [ ] Legacy units continue to work without issues
- [ ] No weapons appear duplicated or missing
- [ ] Weapon profiles display correct stats

## Error Handling Strategy
1. **Graceful Degradation**: If weapon profile missing, skip weapon with warning
2. **Defensive Programming**: Check for empty dictionaries before accessing data
3. **Debug Logging**: Add comprehensive logging for troubleshooting
4. **Backward Compatibility**: Maintain support for legacy UNIT_WEAPONS format

## Implementation Notes
- This fix addresses the core data format mismatch between legacy and modern systems
- The solution maintains backward compatibility while enabling modern army data
- Weapon ID generation creates consistent identifiers from weapon names
- All existing shooting phase logic remains unchanged (targeting, dice rolling, etc.)

## Confidence Score: 9/10
This PRP provides comprehensive context for one-pass implementation with:
- ✅ Clear root cause identification
- ✅ Detailed code examples from existing codebase  
- ✅ External documentation references
- ✅ Step-by-step implementation plan
- ✅ Validation gates and test scenarios
- ✅ Error handling and backward compatibility considerations