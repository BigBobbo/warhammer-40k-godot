# Product Requirements Document: Unit Stats Panel Display

## Issue Reference
GitHub Issue #21: Show unit Stats

## Feature Description
Implement a comprehensive unit stats display panel that shows detailed unit information when a unit is selected. The panel should be collapsible and display all unit data from the JSON blob including stats, weapons, abilities, and composition.

## Requirements
1. Display unit stats when a unit is selected (via model click or unit list selection)
2. Show stats panel at the bottom of the screen (collapsible)
3. Move existing bottom panel to top of screen
4. Display all JSON data: stats, weapons, abilities, composition
5. Panel should be toggleable by user to save screen space

## Implementation Context

### Current Codebase Structure

#### File Organization
```
40k/
├── scripts/
│   ├── Main.gd                     # Main UI controller - line 510: _on_unit_selected()
│   ├── MovementController.gd       # Movement phase UI
│   ├── ShootingController.gd       # Shooting phase UI
│   └── DeploymentController.gd     # Deployment phase UI
├── scenes/
│   └── Main.tscn                   # Main scene definition
└── armies/
    └── *.json                      # Unit data files
```

#### Current Unit Selection Flow
```gdscript
# Main.gd line 510
func _on_unit_selected(index: int) -> void:
    var unit_id = unit_list.get_item_metadata(index)
    # Phase-specific selection logic
    show_unit_card(unit_id)  # Currently shows basic info only
```

#### UI Panel Structure
- **HUD_Bottom**: Currently at bottom (100px height) - needs moving to top
  - Contains: PhaseLabel, ActivePlayerBadge, StatusLabel, EndDeploymentButton
- **HUD_Right**: Side panel (400px width)
  - UnitListPanel: Unit selection list
  - UnitCard: Basic unit display (needs enhancement)

#### Unit Data Structure
```json
{
  "meta": {
    "name": "Intercessor Squad",
    "keywords": ["INFANTRY", "PRIMARIS"],
    "stats": {
      "move": 6,
      "toughness": 4,
      "save": 3,
      "wounds": 2,
      "leadership": 6,
      "objective_control": 2
    },
    "weapons": {
      "ranged": [{
        "name": "Bolt rifle",
        "range": 24,
        "attacks": "2",
        "bs": "3+",
        "strength": "4",
        "ap": "-1",
        "damage": "1",
        "abilities": ["Assault", "Heavy"]
      }],
      "melee": [{
        "name": "Close combat weapon",
        "range": "Melee",
        "attacks": "3",
        "ws": "3+",
        "strength": "4",
        "ap": "0",
        "damage": "1"
      }]
    },
    "abilities": [{
      "name": "Oath of Moment",
      "description": "Re-roll hits of 1"
    }],
    "unit_composition": {
      "models": 5,
      "model_type": "Intercessor"
    }
  }
}
```

### Reference Implementation (from listmaker HTML)
```html
<!-- Stats Display Format -->
<div style="background: rgba(0, 0, 0, 0.3);">
    <strong>Unit Stats:</strong>
    M6" | T4 | Sv3+ | W2 | Ld6+ | OC2
</div>

<!-- Weapon Table Format -->
<table>
    <thead>
        <tr style="background: #87CEEB;">
            <th>Range</th><th>A</th><th>BS</th><th>S</th><th>AP</th><th>D</th><th>Abilities</th>
        </tr>
    </thead>
    <!-- Weapon rows -->
</table>
```

## Technical Approach

### 1. UI Restructuring
```gdscript
# Main.gd modifications
func _ready():
    # Move HUD_Bottom to top position
    hud_bottom.anchor_top = 0.0
    hud_bottom.anchor_bottom = 0.0
    hud_bottom.margin_bottom = 100
    
    # Create new stats panel at bottom
    create_unit_stats_panel()
```

### 2. Stats Panel Implementation
```gdscript
# New UnitStatsPanel.gd
extends PanelContainer

@onready var toggle_button = $VBox/Header/ToggleButton
@onready var content_container = $VBox/Content
@onready var stats_label = $VBox/Content/StatsContainer/StatsLabel
@onready var weapons_container = $VBox/Content/WeaponsContainer
@onready var abilities_container = $VBox/Content/AbilitiesContainer

var is_collapsed = false
var unit_data = null

func _ready():
    toggle_button.pressed.connect(_on_toggle_pressed)
    set_collapsed(true)  # Start collapsed

func _on_toggle_pressed():
    set_collapsed(!is_collapsed)

func set_collapsed(collapsed: bool):
    is_collapsed = collapsed
    content_container.visible = !collapsed
    toggle_button.text = "▼ Unit Stats" if collapsed else "▲ Unit Stats"
    
    # Animate panel height
    var tween = create_tween()
    var target_height = 40 if collapsed else 300
    tween.tween_property(self, "custom_minimum_size:y", target_height, 0.3)

func display_unit(unit_data: Dictionary):
    self.unit_data = unit_data
    
    # Display stats line
    var stats = unit_data.meta.stats
    stats_label.text = "M%d\" | T%d | Sv%d+ | W%d | Ld%d+ | OC%d" % [
        stats.move, stats.toughness, stats.save, 
        stats.wounds, stats.leadership, stats.objective_control
    ]
    
    # Display weapons tables
    _create_weapons_tables()
    
    # Display abilities
    _create_abilities_list()
    
    # Auto-expand when unit selected
    set_collapsed(false)

func _create_weapons_tables():
    # Clear existing
    for child in weapons_container.get_children():
        child.queue_free()
    
    # Create ranged weapons table
    if unit_data.meta.has("weapons") and unit_data.meta.weapons.has("ranged"):
        var ranged_label = Label.new()
        ranged_label.text = "RANGED WEAPONS"
        ranged_label.add_theme_style_override("normal", preload("res://themes/header_style.tres"))
        weapons_container.add_child(ranged_label)
        
        var ranged_grid = GridContainer.new()
        ranged_grid.columns = 7
        
        # Headers
        for header in ["Range", "A", "BS", "S", "AP", "D", "Abilities"]:
            var label = Label.new()
            label.text = header
            label.add_theme_style_override("normal", preload("res://themes/table_header.tres"))
            ranged_grid.add_child(label)
        
        # Data rows
        for weapon in unit_data.meta.weapons.ranged:
            _add_weapon_row(ranged_grid, weapon, "ranged")
        
        weapons_container.add_child(ranged_grid)
    
    # Similar for melee weapons...

func _add_weapon_row(grid: GridContainer, weapon: Dictionary, type: String):
    var cells = []
    
    if type == "ranged":
        cells = [
            str(weapon.range) + "\"",
            weapon.attacks,
            weapon.bs,
            str(weapon.strength),
            str(weapon.ap),
            str(weapon.damage),
            ", ".join(weapon.get("abilities", []))
        ]
    else:  # melee
        cells = [
            "Melee",
            weapon.attacks,
            weapon.ws,
            str(weapon.strength),
            str(weapon.ap),
            str(weapon.damage),
            ", ".join(weapon.get("abilities", []))
        ]
    
    for cell_text in cells:
        var label = Label.new()
        label.text = cell_text
        label.add_theme_style_override("normal", preload("res://themes/table_cell.tres"))
        grid.add_child(label)
```

### 3. Integration with Main.gd
```gdscript
# Main.gd modifications
var unit_stats_panel: Control

func _ready():
    # ... existing code ...
    _setup_unit_stats_panel()

func _setup_unit_stats_panel():
    # Create stats panel scene instance
    var stats_panel_scene = preload("res://40k/scenes/UnitStatsPanel.tscn")
    unit_stats_panel = stats_panel_scene.instantiate()
    
    # Position at bottom
    unit_stats_panel.anchor_top = 1.0
    unit_stats_panel.anchor_bottom = 1.0
    unit_stats_panel.anchor_left = 0.0
    unit_stats_panel.anchor_right = 1.0
    unit_stats_panel.margin_top = -300  # Max expanded height
    
    add_child(unit_stats_panel)

func _on_unit_selected(index: int) -> void:
    var unit_id = unit_list.get_item_metadata(index)
    
    # Existing phase logic...
    
    # Show detailed stats in bottom panel
    var unit_data = get_unit_data(unit_id)
    if unit_data and unit_stats_panel:
        unit_stats_panel.display_unit(unit_data)
    
    show_unit_card(unit_id)  # Keep existing card display
```

### 4. Scene Structure (UnitStatsPanel.tscn)
```
UnitStatsPanel (PanelContainer)
├── VBox
    ├── Header (HBoxContainer)
    │   ├── ToggleButton
    │   └── TitleLabel "Unit Statistics"
    └── Content (ScrollContainer)
        └── ContentVBox
            ├── StatsContainer
            │   └── StatsLabel (RichTextLabel)
            ├── WeaponsContainer (VBoxContainer)
            │   ├── RangedWeaponsGrid (GridContainer)
            │   └── MeleeWeaponsGrid (GridContainer)
            ├── AbilitiesContainer (VBoxContainer)
            └── CompositionContainer (VBoxContainer)
```

## Implementation Tasks

1. **Restructure UI Layout** (Priority: High)
   - Move HUD_Bottom to top position
   - Adjust anchors and margins for all panels
   - Test layout with different screen sizes

2. **Create UnitStatsPanel Scene** (Priority: High)
   - Design panel structure in Godot editor
   - Implement collapsible functionality
   - Add smooth animation for expand/collapse

3. **Implement Stats Display** (Priority: High)
   - Parse unit JSON data
   - Format stats string (M/T/Sv/W/Ld/OC)
   - Display keywords as tags

4. **Create Weapon Tables** (Priority: High)
   - Implement GridContainer-based tables
   - Separate ranged/melee weapons
   - Apply appropriate styling

5. **Display Abilities** (Priority: Medium)
   - List abilities with names and descriptions
   - Format as expandable items if many

6. **Show Unit Composition** (Priority: Medium)
   - Display model count and types
   - Show base sizes if available

7. **Integration & Testing** (Priority: High)
   - Hook into existing selection system
   - Test with all unit types
   - Verify data displays correctly

8. **Polish & Optimization** (Priority: Low)
   - Add icons for stats
   - Implement theme consistency
   - Optimize for performance with large armies

## Validation Gates

```bash
# Since this is Godot, validation is done through the editor
# 1. Open Godot editor
export PATH="$HOME/bin:$PATH"
godot --editor

# 2. Run the project
godot

# 3. Manual testing checklist:
# - Select unit from list → stats panel appears
# - Click unit model → stats panel updates
# - Toggle collapse button → panel animates smoothly
# - All unit data displays correctly
# - Panel stays at bottom when phases change
# - Bottom panel successfully moved to top
```

## External Resources

### Godot Documentation
- Panel Containers: https://docs.godotengine.org/en/4.4/classes/class_panelcontainer.html
- GridContainer: https://docs.godotengine.org/en/4.4/classes/class_gridcontainer.html
- RichTextLabel Tables: https://docs.godotengine.org/en/stable/tutorials/ui/bbcode_in_richtextlabel.html
- ScrollContainer: https://docs.godotengine.org/en/stable/classes/class_scrollcontainer.html

### Warhammer Rules Reference
- Core Rules: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- Unit Datasheets format reference

### UI Implementation Examples
- CollapsibleContainer Plugin: https://godotengine.org/asset-library/asset/2050
- Dynamic Data Table: https://github.com/jospic/dynamicdatatable
- Creating Tables in Godot: https://medium.com/@jmazurevich/creating-simple-text-tables-in-godot-engine-e50d386d497d

## Common Pitfalls to Avoid

1. **Container Animation**: Cannot directly animate container children - use intermediary Control nodes
2. **BBCode Tables**: Limited functionality - use GridContainer for complex tables
3. **Performance**: Large weapon lists may need virtualization for smooth scrolling
4. **Data Access**: Ensure unit data is properly loaded before display
5. **Theme Consistency**: Use existing theme resources for consistent styling

## Success Criteria

1. Unit stats panel displays at bottom of screen
2. Panel is collapsible with smooth animation
3. All unit data from JSON is visible and formatted correctly
4. Weapon tables clearly separate ranged/melee with proper columns
5. Panel integrates seamlessly with existing selection system
6. Original bottom panel successfully relocated to top
7. UI remains responsive during gameplay

## Confidence Score: 8/10

**Rationale**: High confidence due to:
- Clear requirements and reference implementation
- Existing codebase patterns to follow
- Well-documented Godot UI system
- Straightforward integration points

**Risk factors**:
- Complex table formatting may require iteration
- Animation timing with gameplay phases
- Potential performance issues with many units

## Notes for Implementation

- Start with basic panel structure and collapsibility
- Implement stats display first (simplest)
- Build weapon tables incrementally
- Test with various unit types early
- Consider adding unit portrait/icon if available
- Preserve existing unit card functionality as supplementary display