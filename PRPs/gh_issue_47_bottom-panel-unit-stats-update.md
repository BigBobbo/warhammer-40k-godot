# PRP: Update Bottom Panel to Include Enemy Stats (Issue #47)

**Issue Number**: 47  
**Feature Name**: Bottom Panel Unit Stats Update  
**Author**: AI-Generated PRP  
**Date**: 2025-09-04  
**Confidence Level**: 8/10

## Summary
Transform the current bottom panel into a 4-section horizontal layout displaying both player and enemy unit lists with their respective stats panels. This moves unit lists from the right panel to the bottom panel and creates a symmetric view of both players' forces.

## Background and Context

### Current Architecture
The UI currently uses these panels:
- **HUD_Bottom** (now at top): Phase controls and status
- **HUD_Right**: Unit list (ItemList) and unit card display
- **HUD_Left**: Mathhammer statistical analysis  
- **UnitStatsPanel** (bottom): Collapsible unit stats (40px collapsed, 300px expanded)

### Key Files to Modify
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/scenes/Main.tscn` - Scene structure
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/Main.gd` - UI coordination
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/UnitStatsPanel.gd` - Bottom panel logic
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/scenes/UnitStatsPanel.tscn` - Bottom panel scene

## Detailed Requirements

### Layout Structure
Create a 4-section horizontal layout in the bottom panel:
1. **Section 1**: Player unit list (migrated from right panel)
2. **Section 2**: Selected player unit stats
3. **Section 3**: Enemy unit list  
4. **Section 4**: Selected enemy unit stats

### Functional Requirements
- Maintain collapsible functionality (40px collapsed, 300px expanded)
- Both unit lists should be ItemList widgets showing "Unit Name (X models) [STATUS]"
- Selection in either list updates corresponding stats panel
- Phase-aware filtering (deployment/movement/other phases)
- Preserve existing metadata storage pattern

## Implementation Blueprint

### Step 1: Restructure UnitStatsPanel Scene
```gdscript
# New structure for UnitStatsPanel.tscn:
UnitStatsPanel (PanelContainer)
├── HBoxContainer (main container)
│   ├── PlayerSection (VBoxContainer, stretch_ratio: 0.5)
│   │   ├── HBoxContainer
│   │   │   ├── PlayerUnitsPanel (PanelContainer, stretch_ratio: 0.5)
│   │   │   │   └── VBoxContainer
│   │   │   │       ├── Label ("Player Units")
│   │   │   │       └── PlayerUnitsList (ItemList)
│   │   │   └── PlayerStatsPanel (PanelContainer, stretch_ratio: 0.5)
│   │   │       └── ScrollContainer
│   │   │           └── PlayerStatsContent (VBoxContainer)
│   └── EnemySection (VBoxContainer, stretch_ratio: 0.5)
│       └── HBoxContainer
│           ├── EnemyUnitsPanel (PanelContainer, stretch_ratio: 0.5)
│           │   └── VBoxContainer
│           │       ├── Label ("Enemy Units")
│           │       └── EnemyUnitsList (ItemList)
│           └── EnemyStatsPanel (PanelContainer, stretch_ratio: 0.5)
│               └── ScrollContainer
│                   └── EnemyStatsContent (VBoxContainer)
```

### Step 2: Update UnitStatsPanel.gd
```gdscript
extends PanelContainer

# Node references
@onready var player_units_list: ItemList = $HBoxContainer/PlayerSection/HBoxContainer/PlayerUnitsPanel/VBoxContainer/PlayerUnitsList
@onready var enemy_units_list: ItemList = $HBoxContainer/EnemySection/HBoxContainer/EnemyUnitsPanel/VBoxContainer/EnemyUnitsList
@onready var player_stats_content: VBoxContainer = $HBoxContainer/PlayerSection/HBoxContainer/PlayerStatsPanel/ScrollContainer/PlayerStatsContent
@onready var enemy_stats_content: VBoxContainer = $HBoxContainer/EnemySection/HBoxContainer/EnemyStatsPanel/ScrollContainer/EnemyStatsContent

var is_expanded: bool = false
const COLLAPSED_HEIGHT: int = 40
const EXPANDED_HEIGHT: int = 300

signal unit_selected(unit_id: String, is_enemy: bool)

func _ready():
    player_units_list.item_selected.connect(_on_player_unit_selected)
    enemy_units_list.item_selected.connect(_on_enemy_unit_selected)
    custom_minimum_size = Vector2(0, COLLAPSED_HEIGHT)

func populate_unit_lists(current_phase: String):
    var active_player = GameState.get_active_player()
    var enemy_player = 3 - active_player
    
    # Populate player units
    _populate_list(player_units_list, active_player, current_phase)
    
    # Populate enemy units  
    _populate_list(enemy_units_list, enemy_player, current_phase)

func _populate_list(list: ItemList, player: int, phase: String):
    list.clear()
    var units = GameState.get_units_for_player(player)
    
    for unit_id in units:
        var unit = units[unit_id]
        var display_text = _get_unit_display_text(unit, phase)
        if _should_show_unit(unit, phase):
            var idx = list.add_item(display_text)
            list.set_item_metadata(idx, unit_id)
```

### Step 3: Update Main.gd Integration
```gdscript
# In Main.gd, modify refresh_unit_list() to use new bottom panel lists:
func refresh_unit_list():
    if unit_stats_panel:
        unit_stats_panel.populate_unit_lists(current_phase)
    
    # Remove or repurpose the right panel unit list
    # Could use right panel for detailed unit card view only

# Add handlers for unit selection from bottom panel:
func _on_unit_stats_panel_unit_selected(unit_id: String, is_enemy: bool):
    var unit = GameState.get_unit(unit_id)
    if unit:
        if is_enemy:
            # Display enemy unit in right panel or designated area
            display_enemy_unit_card(unit)
        else:
            # Display player unit in right panel or designated area  
            display_player_unit_card(unit)
```

### Step 4: Implement Unit Stats Display
```gdscript
# In UnitStatsPanel.gd
func display_unit_stats(unit_data: Dictionary, target_container: VBoxContainer):
    # Clear previous content
    for child in target_container.get_children():
        child.queue_free()
    
    # Create stats display following existing pattern
    _create_keywords_section(unit_data, target_container)
    _create_stats_section(unit_data, target_container)
    _create_weapons_section(unit_data, target_container)
    _create_abilities_section(unit_data, target_container)
    _create_composition_section(unit_data, target_container)
    
    # Auto-expand if not already
    if not is_expanded:
        expand()
```

## Critical Patterns to Follow

### 1. Player Differentiation
```gdscript
# Always use this pattern for enemy player:
var active_player = GameState.get_active_player()  
var enemy_player = 3 - active_player
```

### 2. Unit List Population Pattern
```gdscript
# Follow existing pattern from Main.gd lines 783-833
func _get_unit_display_text(unit: Dictionary, phase: String) -> String:
    var text = unit.meta.display_name
    var model_count = _count_active_models(unit)
    text += " (" + str(model_count) + " models)"
    
    # Add phase-specific status flags
    if phase == "MOVEMENT":
        if unit.status.has("MOVED"):
            text += " [MOVED]"
        if unit.status.has("ADVANCED"):  
            text += " [ADV]"
        if unit.status.has("FELL_BACK"):
            text += " [FELL BACK]"
    return text
```

### 3. Signal Communication
```gdscript
# Use signals for loose coupling:
signal unit_selected(unit_id: String, is_enemy: bool)
signal stats_panel_toggled(is_expanded: bool)
```

## Testing and Validation Gates

### Automated Tests
```bash
# Run Godot tests
export PATH="$HOME/bin:$PATH"
godot --headless --script res://40k/tests/ui/test_unit_stats_panel_update.gd

# Check for errors
godot --check-only
```

### Manual Validation Checklist
- [ ] Both unit lists populate correctly
- [ ] Phase-aware filtering works for both players  
- [ ] Unit selection updates correct stats panel
- [ ] Collapse/expand animation smooth
- [ ] Enemy units show correct owner
- [ ] Status flags display properly
- [ ] No errors in console during phase transitions

## Error Handling Strategy

1. **Null Checks**: Always verify unit exists before accessing
2. **Player Validation**: Ensure player is 1 or 2
3. **Phase Validation**: Handle unknown phases gracefully
4. **Node References**: Use `@onready` with null checks
5. **Signal Safety**: Disconnect signals in `_exit_tree()`

## Implementation Tasks (In Order)

1. [ ] Create backup of current UnitStatsPanel implementation
2. [ ] Restructure UnitStatsPanel.tscn with 4-section layout
3. [ ] Update UnitStatsPanel.gd with dual list management
4. [ ] Implement unit list population for both players
5. [ ] Add selection handlers for both lists
6. [ ] Implement stats display for selected units
7. [ ] Update Main.gd integration points
8. [ ] Remove/repurpose old right panel unit list
9. [ ] Test phase transitions and filtering
10. [ ] Add error handling and edge cases
11. [ ] Write automated test for new functionality
12. [ ] Perform full manual testing across all phases

## Gotchas and Known Issues

1. **Bug to Fix**: FightController.gd line 541 has incorrect player switching logic
2. **Memory Management**: Clear unit list items properly to avoid leaks
3. **Metadata Storage**: ItemList metadata must be unit_id string
4. **Phase Timing**: Unit lists must refresh after phase changes complete
5. **Animation Conflicts**: Ensure expand/collapse doesn't conflict with other tweens

## External Documentation References

- Godot ItemList: https://docs.godotengine.org/en/4.4/classes/class_itemlist.html
- Godot Signals: https://docs.godotengine.org/en/4.4/getting_started/scripting/gdscript/gdscript_basics.html#signals
- Godot UI Containers: https://docs.godotengine.org/en/4.4/tutorials/ui/gui_containers.html

## Confidence Score: 8/10

**Reasoning**: 
- Strong existing codebase patterns to follow (9/10)
- Clear requirements and UI structure (9/10)  
- Some complexity in managing dual lists and selections (7/10)
- Phase-aware filtering adds complexity (7/10)

The implementation path is clear with good existing patterns to follow. Main risks are in coordinating the four panels and ensuring smooth user experience across phase transitions.