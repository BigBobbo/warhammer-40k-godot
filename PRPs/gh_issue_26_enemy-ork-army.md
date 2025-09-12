# PRP: Enemy Ork Army Implementation

## Issue Information
- **Issue Number**: #26
- **Title**: Enemy Ork army
- **Priority**: Medium (MVP label)
- **Confidence Score**: 9/10

## Executive Summary
Replace the current placeholder Ork army (simple Boyz and Gretchin units) with a comprehensive enemy army featuring detailed unit composition including Warbosses, enhanced Boyz squads, Battlewagon, and Strike Force units. This implementation leverages the existing ArmyListManager system to provide a more realistic and engaging enemy force while maintaining the current army loading architecture.

## Current State Analysis

### Existing Implementation
The current Ork army (`40k/armies/orks.json`) contains minimal placeholder units:
- **U_BOYZ_A**: Basic 10-model Boyz squad with simplified stats
- **U_GRETCHIN_A**: Basic 5-model Gretchin squad with minimal weapons
- **Owner**: Correctly set to `2` for enemy player
- **Structure**: Basic weapons (Slugga, Choppa, Grot blasta) without comprehensive rules

**Reference Files:**
- `/40k/armies/orks.json:10-150` - Current placeholder army
- `/40k/autoloads/GameState.gd:78-82` - Enemy army loading logic
- `/40k/autoloads/ArmyListManager.gd:46-139` - Army loading and processing system

### Current Army Loading System
The enemy army is loaded via:
```gdscript
var player2_army = ArmyListManager.load_army_list("orks", 2)
ArmyListManager.apply_army_to_game_state(player2_army, 2)
```

### Key Integration Points
1. **GameState.gd:78-85** - Loads Ork army for Player 2 on initialization
2. **ArmyListManager.gd:104-139** - Processes units and sets owner to Player 2
3. **Existing Tests** - `/40k/tests/integration/test_army_loading.gd:71-87` validates Ork army loading

## Implementation Design

### Target Army Composition
Based on the GitHub issue specification, the new enemy army includes:

#### Command Units
- **U_STRIKE_FORCE_A**: Single elite unit (2000 points)
- **U_WARBOSS_B**: Warlord with advanced weapons and abilities
- **U_WARBOSS_C**: Secondary Warboss character
- **U_WARBOSS_IN_MEGA_ARMOUR_D**: Heavy armored leader with Tellyporta enhancement

#### Troops
- **U_BOYZ_E**: 17-model squad with diverse weapons and special rules
- **U_BOYZ_F**: Second 17-model squad for tactical flexibility

#### Heavy Support
- **U_BATTLEWAGON_G**: Transport vehicle with heavy weapons
- **U_GRETCHIN_H**: Support squad with enhanced composition
- **U_GRETCHIN_I**: Additional support models

### Data Structure Enhancements

The new army features comprehensive unit metadata:

```json
{
  "faction": {
    "name": "Unknown",  // As specified in issue
    "points": 2000,
    "detachment": "",
    "player_name": "",
    "team_name": ""
  },
  "units": {
    "UNIT_ID": {
      "owner": 2,  // Critical: Must be 2 for enemy (not 1 as in issue)
      "meta": {
        "weapons": [...],     // Comprehensive weapon profiles
        "abilities": [...],   // Unit special abilities
        "stats": {...},      // Full stat profiles
        "enhancements": [...] // Equipment upgrades
      },
      "models": [...]  // Individual model data
    }
  }
}
```

### Implementation Tasks

#### Task 1: Update Ork Army JSON
**File**: `40k/armies/orks.json`

1. **Replace entire file content** with comprehensive army data from GitHub issue
2. **Critical Fix**: Change all `"owner": 1` to `"owner": 2` for enemy units
3. **Preserve structure** that matches existing ArmyListManager expectations
4. **Validate JSON** formatting and required fields

**Key Requirements:**
- All units must have `owner: 2` (enemy player)
- Maintain `"status": "UNDEPLOYED"` for all units
- Include comprehensive weapon profiles with:
  - Range, attacks, ballistic_skill/weapon_skill
  - Strength, AP, damage values
  - Special rules (e.g., "anti-infantry 4+", "devastating wounds")

#### Task 2: Verify Integration Points
**Files to validate:**
- `40k/autoloads/GameState.gd:78-85` - Ensure enemy loading still works
- `40k/autoloads/ArmyListManager.gd:104-139` - Verify owner assignment logic
- Existing save games should be unaffected due to owner correction

#### Task 3: Validation Testing
**Required validations:**
1. **Army Structure**: Use existing `ArmyListManager.validate_army_structure()`
2. **Unit Integrity**: Verify all units have required fields (`meta`, `models`, etc.)
3. **Weapon Parsing**: Ensure `RulesEngine.parse_weapon_stats()` handles new weapons
4. **Owner Assignment**: Confirm all units have `owner: 2` after loading

### Validation Gates (Executable)

```bash
# 1. JSON Syntax Validation
python -m json.tool 40k/armies/orks.json > /dev/null && echo "JSON Valid" || echo "JSON Invalid"

# 2. Godot Integration Test
godot --headless --script="res://test_army_validation.gd"

# 3. Run Existing Army Loading Tests  
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/integration/test_army_loading.gd -gmaximize_test_output=true
```

## Implementation Blueprint

### Step 1: Army Data Preparation
```gdscript
# Pseudocode for army data transformation
func transform_issue_data_to_enemy():
    var issue_army_data = load_github_issue_json()
    
    # Critical fix: Change owner from 1 to 2 for all units
    for unit_id in issue_army_data.units:
        issue_army_data.units[unit_id].owner = 2
        
    # Validate structure matches ArmyListManager expectations
    var validation = ArmyListManager.validate_army_structure(issue_army_data)
    if not validation.valid:
        push_error("Army validation failed: " + str(validation.errors))
    
    return issue_army_data
```

### Step 2: Integration Verification
```gdscript
# Verify enemy army loading works correctly
func verify_enemy_army_loading():
    GameState.initialize_default_state()
    
    var enemy_units = GameState.get_units_for_player(2)
    assert(enemy_units.size() > 2, "Should have more than basic placeholder units")
    assert(enemy_units.has("U_WARBOSS_B"), "Should have Warboss units")
    assert(enemy_units.has("U_BATTLEWAGON_G"), "Should have heavy support")
    
    # Verify faction data
    var enemy_faction = GameState.state.factions.get("2", {})
    assert(enemy_faction.points == 2000, "Should have 2000 point army")
```

## Risk Analysis and Mitigation

### Risk: Owner Assignment Confusion
**Issue**: GitHub issue shows `owner: 1` but enemy should be `owner: 2`
**Mitigation**: Explicitly change all ownership values and validate in tests

### Risk: Save Game Compatibility  
**Issue**: Existing saves might reference old unit IDs
**Mitigation**: ArmyListManager loads armies fresh on game start, saves contain state not army definitions

### Risk: Weapon Parsing Complexity
**Issue**: New weapons have complex special rules that might not parse correctly
**Mitigation**: Leverage existing `RulesEngine.parse_weapon_stats()` and add validation tests

## Context References

### Core Documentation
- **Warhammer 40k Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- **Godot Documentation**: https://docs.godotengine.org/en/4.4/

### Codebase Patterns to Follow
- **Army Structure**: Follow `/40k/armies/adeptus_custodes.json` for comprehensive examples  
- **Testing Pattern**: Use `/40k/tests/integration/test_army_loading.gd:71-87` as validation template
- **Weapon Format**: Match existing weapon structures in Space Marines army
- **Error Handling**: Follow `ArmyListManager.gd:82-86` pattern for JSON parsing errors

### Implementation Files
```
40k/
├── armies/
│   └── orks.json              # TARGET: Replace with comprehensive army
├── autoloads/
│   ├── ArmyListManager.gd     # REFERENCE: Loading and validation logic
│   └── GameState.gd           # REFERENCE: Enemy army initialization (lines 78-82)  
└── tests/
    └── integration/
        └── test_army_loading.gd # REFERENCE: Ork army validation tests (lines 71-87)
```

## Success Criteria

1. **Functional**: Enemy army loads successfully with all 9 units
2. **Ownership**: All enemy units have `owner: 2` after loading
3. **Weapons**: All weapon profiles parse correctly through RulesEngine
4. **Integration**: Existing tests pass without modification
5. **Performance**: Army loading completes in under 1 second (existing test requirement)

## Confidence Assessment: 9/10

**High Confidence Factors:**
- Existing army loading system is mature and well-tested
- Clear data structure requirements from GitHub issue  
- Comprehensive validation system already in place
- Simple file replacement with data transformation

**Risk Factors:**
- Complex weapon special rules might need RulesEngine updates (-1 point)
- Large army data might impact loading performance (mitigated by existing perf tests)

This PRP provides a complete implementation path with minimal risk, leveraging existing architecture while delivering a significantly enhanced enemy army experience.