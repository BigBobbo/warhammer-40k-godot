# PRP: Army List System Implementation

## Issue Information
- **Issue Number**: #13
- **Title**: Army List System Implementation
- **Priority**: High
- **Confidence Score**: 9/10

## Executive Summary
Implement a flexible army list system that replaces hardcoded placeholder armies with loadable JSON configurations. The system will allow users to select and manage their armies with detailed unit data including stats, weapons, abilities, and special rules. Initial implementation will replace the Space Marine army with the provided Adeptus Custodes list for testing.

## Current State Analysis

### Existing Implementation
The current system has hardcoded armies in `40k/autoloads/GameState.gd`:
- Lines 42-118 define placeholder units (Intercessors, Tactical Squad, Boyz, Gretchin)
- Units are directly initialized in `initialize_default_state()` method
- No mechanism for loading external army configurations
- Unit structure is simplified with minimal stats and no weapons/abilities

### Key Files to Modify
1. **40k/autoloads/GameState.gd** - Main state management, needs army loading capability
2. **40k/autoloads/StateSerializer.gd** - Already handles JSON serialization, can be extended
3. **40k/scripts/Main.gd** - UI initialization, needs army selection interface
4. **40k/autoloads/RulesEngine.gd** - Contains weapon profiles and rules logic

## Implementation Design

### Data Structure (Army List JSON Format)
```json
{
  "faction": {
    "name": "Adeptus Custodes",
    "points": 1000,
    "detachment": "Shield Host",
    "player_name": "",
    "team_name": ""
  },
  "units": {
    "U_BLADE_CHAMPION_A": {
      "id": "U_BLADE_CHAMPION_A",
      "squad_id": "U_BLADE_CHAMPION_A",
      "owner": 1,
      "status": "UNDEPLOYED",
      "meta": {
        "name": "Blade Champion",
        "keywords": ["ADEPTUS CUSTODES", "BLADE CHAMPION", "CHARACTER", "IMPERIUM", "INFANTRY"],
        "stats": {
          "move": 6,
          "toughness": 6,
          "save": 2,
          "wounds": 6,
          "leadership": 6,
          "objective_control": 2
        },
        "points": 145,
        "is_warlord": false,
        "enhancements": ["Adamantine Talisman (+25 pts)"],
        "wargear": [],
        "weapons": [...],
        "abilities": [...],
        "unit_composition": [...]
      },
      "models": [...]
    }
  }
}
```

### Architecture Overview

```
res://
├── armies/                     # New directory for army lists
│   ├── adeptus_custodes.json  # Initial test army
│   ├── space_marines.json     # Converted from existing
│   └── orks.json              # Converted from existing
├── autoloads/
│   ├── ArmyListManager.gd     # New autoload for army management
│   └── GameState.gd           # Modified to use ArmyListManager
```

## Implementation Tasks

### Task 1: Create Army List Directory and Files
1. Create `40k/armies/` directory
2. Create `adeptus_custodes.json` with provided data
3. Convert existing placeholder armies to JSON format

### Task 2: Implement ArmyListManager Autoload
Create `40k/autoloads/ArmyListManager.gd`:
```gdscript
extends Node

signal army_loaded(army_data: Dictionary)
signal army_load_failed(error: String)

var current_army_data: Dictionary = {}
var available_armies: Array = []

func _ready() -> void:
    scan_available_armies()

func scan_available_armies() -> void:
    var dir = DirAccess.open("res://armies/")
    if dir:
        dir.list_dir_begin()
        var file_name = dir.get_next()
        while file_name != "":
            if file_name.ends_with(".json"):
                available_armies.append(file_name.get_basename())
            file_name = dir.get_next()
        dir.list_dir_end()

func load_army_list(army_name: String, player: int = 1) -> Dictionary:
    var file_path = "res://armies/%s.json" % army_name
    
    if not FileAccess.file_exists(file_path):
        # For exported games, try user:// path
        file_path = "user://armies/%s.json" % army_name
        
    if not FileAccess.file_exists(file_path):
        emit_signal("army_load_failed", "Army file not found: " + army_name)
        return {}
    
    var file = FileAccess.open(file_path, FileAccess.READ)
    if not file:
        emit_signal("army_load_failed", "Failed to open army file")
        return {}
    
    var json_string = file.get_as_text()
    file.close()
    
    var json = JSON.new()
    var parse_result = json.parse(json_string)
    
    if parse_result != OK:
        emit_signal("army_load_failed", "JSON parse error: " + json.get_error_message())
        return {}
    
    var army_data = json.data
    
    # Process units to set owner
    if army_data.has("units"):
        for unit_id in army_data.units:
            army_data.units[unit_id]["owner"] = player
    
    current_army_data = army_data
    emit_signal("army_loaded", army_data)
    return army_data

func apply_army_to_game_state(army_data: Dictionary, player: int) -> void:
    # Replace units for the specified player in GameState
    var all_units = GameState.state.get("units", {})
    
    # Remove existing units for this player
    var units_to_remove = []
    for unit_id in all_units:
        if all_units[unit_id].get("owner", 0) == player:
            units_to_remove.append(unit_id)
    
    for unit_id in units_to_remove:
        all_units.erase(unit_id)
    
    # Add new units from army list
    if army_data.has("units"):
        for unit_id in army_data.units:
            var unit = army_data.units[unit_id]
            unit["owner"] = player
            unit["status"] = GameStateData.UnitStatus.UNDEPLOYED
            all_units[unit_id] = unit
    
    GameState.state["units"] = all_units
    
    # Store faction data
    if army_data.has("faction"):
        if not GameState.state.has("factions"):
            GameState.state["factions"] = {}
        GameState.state["factions"][str(player)] = army_data.faction
```

### Task 3: Modify GameState.gd
Update `initialize_default_state()` method:
```gdscript
func initialize_default_state() -> void:
    # Initialize base state structure
    state = {
        "meta": { ... },
        "board": { ... },
        "units": {},  # Start empty
        "players": { ... },
        "factions": {},  # New
        "phase_log": [],
        "history": []
    }
    
    # Load default armies
    _load_default_armies()

func _load_default_armies() -> void:
    # Check if ArmyListManager is available
    if not ArmyListManager:
        # Fall back to hardcoded armies if manager not available
        _initialize_placeholder_armies()
        return
    
    # Try to load test army for Player 1
    var army_data = ArmyListManager.load_army_list("adeptus_custodes", 1)
    if not army_data.is_empty():
        ArmyListManager.apply_army_to_game_state(army_data, 1)
    else:
        # Fallback to placeholder
        _initialize_placeholder_armies()
    
    # Load opponent army (can be orks or another custodes army)
    army_data = ArmyListManager.load_army_list("orks", 2)
    if not army_data.is_empty():
        ArmyListManager.apply_army_to_game_state(army_data, 2)
```

### Task 4: Update Project Settings
Add ArmyListManager to autoloads in `40k/project.godot`:
```ini
[autoload]
ArmyListManager="*res://autoloads/ArmyListManager.gd"
```

### Task 5: Extend RulesEngine.gd
Add weapon parsing methods:
```gdscript
static func parse_weapon_stats(weapon_data: Dictionary) -> Dictionary:
    var stats = {}
    
    # Handle dice notation (e.g., "D6", "2D6")
    if weapon_data.has("attacks"):
        var attacks = weapon_data.get("attacks", "1")
        if attacks is String:
            stats["attacks"] = _parse_dice_notation(attacks)
        else:
            stats["attacks"] = attacks
    
    # Parse other weapon stats
    stats["range"] = _parse_range(weapon_data.get("range", "Melee"))
    stats["weapon_skill"] = weapon_data.get("weapon_skill", null)
    stats["ballistic_skill"] = weapon_data.get("ballistic_skill", null)
    stats["strength"] = weapon_data.get("strength", 4)
    stats["ap"] = weapon_data.get("ap", "0").to_int() if weapon_data.get("ap") is String else weapon_data.get("ap", 0)
    stats["damage"] = _parse_damage(weapon_data.get("damage", "1"))
    stats["special_rules"] = weapon_data.get("special_rules", "")
    
    return stats

static func _parse_dice_notation(notation: String) -> Dictionary:
    if notation == "D3":
        return {"min": 1, "max": 3, "dice": "D3"}
    elif notation == "D6":
        return {"min": 1, "max": 6, "dice": "D6"}
    elif notation.begins_with("D6+"):
        var bonus = notation.split("+")[1].to_int()
        return {"min": 1 + bonus, "max": 6 + bonus, "dice": notation}
    else:
        return {"min": notation.to_int(), "max": notation.to_int(), "dice": ""}

static func _parse_damage(damage_str: String) -> Dictionary:
    if damage_str == "D3":
        return {"min": 1, "max": 3}
    elif damage_str == "D6":
        return {"min": 1, "max": 6}
    elif damage_str.begins_with("D6+"):
        var bonus = damage_str.split("+")[1].to_int()
        return {"min": 1 + bonus, "max": 6 + bonus}
    else:
        var value = damage_str.to_int()
        return {"min": value, "max": value}
```

### Task 6: Create Army Selection UI (Future Enhancement)
Add army selection dropdown to Main menu (future implementation):
```gdscript
# In Main.gd or new ArmySelectionMenu.gd
func _show_army_selection() -> void:
    var armies = ArmyListManager.available_armies
    # Create UI for army selection
    pass
```

## Testing Strategy

### Unit Tests
1. Test JSON parsing of army lists
2. Test unit structure conversion
3. Test weapon stat parsing
4. Test ability loading

### Integration Tests
1. Test loading army from file
2. Test applying army to game state
3. Test deployment with new units
4. Test save/load with custom armies

### Validation Script
```gdscript
# 40k/tests/unit/test_army_list_manager.gd
extends GutTest

func test_load_army_list():
    var manager = ArmyListManager.new()
    var army = manager.load_army_list("adeptus_custodes", 1)
    
    assert_not_null(army)
    assert_has(army, "faction")
    assert_has(army, "units")
    assert_true(army.units.size() > 0)

func test_apply_army_to_game_state():
    # Test replacing existing units
    pass

func test_weapon_parsing():
    var weapon = {
        "name": "Guardian spear",
        "type": "Ranged",
        "range": "24",
        "attacks": "2",
        "ballistic_skill": "2",
        "strength": "4",
        "ap": "-1",
        "damage": "2",
        "special_rules": "assault"
    }
    
    var parsed = RulesEngine.parse_weapon_stats(weapon)
    assert_eq(parsed.attacks.min, 2)
    assert_eq(parsed.ap, -1)
```

## Validation Gates

```bash
# Run Godot tests
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_army_list_manager.gd

# Check JSON validity
python3 -m json.tool 40k/armies/adeptus_custodes.json > /dev/null && echo "JSON valid" || echo "JSON invalid"

# Run integration tests
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/integration/test_army_loading.gd
```

## Error Handling Strategy

1. **File Not Found**: Fallback to placeholder armies
2. **JSON Parse Error**: Log error, use default armies
3. **Missing Required Fields**: Use defaults from unit templates
4. **Invalid Weapon Stats**: Use base weapon profile
5. **Export Compatibility**: Check both res:// and user:// paths

## Migration Path

1. Phase 1: Load JSON armies alongside hardcoded (this PRP)
2. Phase 2: UI for army selection  
3. Phase 3: Army builder/editor
4. Phase 4: Download armies from repository

## External References

- **Godot JSON Documentation**: https://docs.godotengine.org/en/4.4/classes/class_json.html
- **FileAccess Documentation**: https://docs.godotengine.org/en/4.4/classes/class_fileaccess.html
- **Warhammer 40k Core Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- **Existing Pattern Reference**: `40k/autoloads/StateSerializer.gd` lines 64-86 (JSON parsing)
- **Save/Load Pattern**: `40k/scripts/Main.gd` lines 885-914 (file operations)

## Implementation Order

1. Create armies directory and JSON files
2. Implement ArmyListManager.gd
3. Update project.godot autoloads
4. Modify GameState.gd to use ArmyListManager
5. Extend RulesEngine.gd for weapon parsing
6. Create unit tests
7. Test with provided Adeptus Custodes army
8. Update documentation

## Success Criteria

- [ ] Adeptus Custodes army loads from JSON file
- [ ] Units display correctly in deployment phase
- [ ] Weapons and abilities are parsed properly
- [ ] Game functions normally with new army data
- [ ] Tests pass validation gates
- [ ] No regression in existing functionality

## Notes for AI Implementation

- The codebase already has robust JSON handling in StateSerializer.gd
- Follow existing patterns for error handling and logging
- Use the existing UnitStatus enum from GameStateData
- Preserve backward compatibility with saved games
- The armies/ directory should be at 40k/armies/ parallel to autoloads/
- Ensure exported games can load army files from user:// directory

## Confidence Score: 9/10

High confidence due to:
- Clear existing patterns for JSON handling
- Well-defined unit structure already in place
- Comprehensive test data provided in issue
- Strong foundation in existing codebase

Minor uncertainty around:
- Exact integration with weapon special rules
- Performance with large army lists