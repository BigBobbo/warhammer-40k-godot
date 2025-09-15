# PRP: Main Menu Implementation for Warhammer 40k Game

## Issue Context
GitHub Issue #69: Add a main menu that appears when the user starts the game. The menu should allow selection of mission parameters (terrain, primary mission, deployment zones) and armies for both players before starting a new game or loading an existing one.

## Research Findings

### Existing Codebase Architecture

1. **Current Game Initialization Flow**:
   - `project.godot` sets `res://scenes/Main.tscn` as main scene
   - `Main.gd` initializes in `_ready()` and calls `GameState.initialize_default_state()`
   - `GameState` automatically loads default armies (Custodes for P1, Orks for P2)
   - Game starts directly in deployment phase

2. **Available Components**:
   - **Terrain System**: `TerrainManager.gd` currently only has "layout_2" but structured for multiple layouts
   - **Mission System**: `MissionManager.gd` has "Take and Hold" mission with Strike Force deployment  
   - **Army System**: `ArmyListManager.gd` supports loading armies: "adeptus_custodes", "space_marines", "orks"
   - **Save/Load System**: `SaveLoadDialog.gd` provides UI for save/load operations

3. **UI Patterns in Codebase**:
   - Dialog pattern: `AcceptDialog` base (see `SaveLoadDialog.tscn`)
   - Dropdown pattern: `OptionButton` nodes (see `MathhhammerUI.gd`)
   - List pattern: `ItemList` nodes (see unit lists)
   - Scene structure: VBoxContainer/HBoxContainer for layout

4. **Configuration Storage**:
   - GameState stores mission info in `state.meta`
   - Terrain stored in `state.board.terrain_features`
   - Army data stored in `state.units` and `state.factions`

### Godot UI Best Practices

1. **Scene Management**:
   - Use `get_tree().change_scene_to_packed()` or `change_scene_to_file()` for transitions
   - Pass data between scenes via autoload singletons (GameState)

2. **Control Nodes**:
   - `OptionButton` for dropdowns with `.add_item()` and `.selected` property
   - `Button` with `.pressed` signal for actions
   - Container nodes for automatic layout

## Implementation Blueprint

### Phase 1: Create Main Menu Scene Structure

```gdscript
# New file: 40k/scenes/MainMenu.tscn
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/MainMenu.gd" id="1"]

[node name="MainMenu" type="Control"]
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")

[node name="Background" type="ColorRect" parent="."]
anchor_right = 1.0
anchor_bottom = 1.0
color = Color(0.1, 0.1, 0.15, 1)

[node name="MenuContainer" type="VBoxContainer" parent="."]
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -300.0
offset_top = -250.0
offset_right = 300.0
offset_bottom = 250.0

[node name="TitleLabel" type="Label" parent="MenuContainer"]
text = "Warhammer 40,000 Battle Simulator"
horizontal_alignment = 1
theme_override_font_sizes/font_size = 32

[node name="HSeparator" type="HSeparator" parent="MenuContainer"]

[node name="MissionSection" type="VBoxContainer" parent="MenuContainer"]
[node name="MissionLabel" type="Label" parent="MenuContainer/MissionSection"]
text = "Mission Settings"
theme_override_font_sizes/font_size = 20

[node name="TerrainContainer" type="HBoxContainer" parent="MenuContainer/MissionSection"]
[node name="TerrainLabel" type="Label" parent="MenuContainer/MissionSection/TerrainContainer"]
text = "Terrain Layout:"
minimum_size = Vector2(150, 0)
[node name="TerrainDropdown" type="OptionButton" parent="MenuContainer/MissionSection/TerrainContainer"]
minimum_size = Vector2(300, 0)

[node name="MissionContainer" type="HBoxContainer" parent="MenuContainer/MissionSection"]
[node name="MissionLabel" type="Label" parent="MenuContainer/MissionSection/MissionContainer"]
text = "Primary Mission:"
minimum_size = Vector2(150, 0)
[node name="MissionDropdown" type="OptionButton" parent="MenuContainer/MissionSection/MissionContainer"]
minimum_size = Vector2(300, 0)

[node name="DeploymentContainer" type="HBoxContainer" parent="MenuContainer/MissionSection"]
[node name="DeploymentLabel" type="Label" parent="MenuContainer/MissionSection/DeploymentContainer"]
text = "Deployment Zone:"
minimum_size = Vector2(150, 0)
[node name="DeploymentDropdown" type="OptionButton" parent="MenuContainer/MissionSection/DeploymentContainer"]
minimum_size = Vector2(300, 0)

[node name="HSeparator2" type="HSeparator" parent="MenuContainer"]

[node name="ArmySection" type="VBoxContainer" parent="MenuContainer"]
[node name="ArmyLabel" type="Label" parent="MenuContainer/ArmySection"]
text = "Army Selection"
theme_override_font_sizes/font_size = 20

[node name="Player1Container" type="HBoxContainer" parent="MenuContainer/ArmySection"]
[node name="Player1Label" type="Label" parent="MenuContainer/ArmySection/Player1Container"]
text = "Player 1 Army:"
minimum_size = Vector2(150, 0)
[node name="Player1Dropdown" type="OptionButton" parent="MenuContainer/ArmySection/Player1Container"]
minimum_size = Vector2(300, 0)

[node name="Player2Container" type="HBoxContainer" parent="MenuContainer/ArmySection"]
[node name="Player2Label" type="Label" parent="MenuContainer/ArmySection/Player2Container"]
text = "Player 2 Army:"
minimum_size = Vector2(150, 0)
[node name="Player2Dropdown" type="OptionButton" parent="MenuContainer/ArmySection/Player2Container"]
minimum_size = Vector2(300, 0)

[node name="HSeparator3" type="HSeparator" parent="MenuContainer"]

[node name="ButtonSection" type="VBoxContainer" parent="MenuContainer"]
[node name="StartButton" type="Button" parent="MenuContainer/ButtonSection"]
text = "Start Game"
minimum_size = Vector2(200, 40)

[node name="LoadButton" type="Button" parent="MenuContainer/ButtonSection"]
text = "Load Game"
minimum_size = Vector2(200, 40)
```

### Phase 2: Main Menu Logic

```gdscript
# New file: 40k/scripts/MainMenu.gd
extends Control

@onready var terrain_dropdown: OptionButton = $MenuContainer/MissionSection/TerrainContainer/TerrainDropdown
@onready var mission_dropdown: OptionButton = $MenuContainer/MissionSection/MissionContainer/MissionDropdown
@onready var deployment_dropdown: OptionButton = $MenuContainer/MissionSection/DeploymentContainer/DeploymentDropdown
@onready var player1_dropdown: OptionButton = $MenuContainer/ArmySection/Player1Container/Player1Dropdown
@onready var player2_dropdown: OptionButton = $MenuContainer/ArmySection/Player2Container/Player2Dropdown
@onready var start_button: Button = $MenuContainer/ButtonSection/StartButton
@onready var load_button: Button = $MenuContainer/ButtonSection/LoadButton

# Configuration options
var terrain_options = [
    {"id": "layout_2", "name": "Chapter Approved Layout 2"}
    # Future: Add more layouts
]

var mission_options = [
    {"id": "take_and_hold", "name": "Take and Hold"}
    # Future: Add more missions
]

var deployment_options = [
    {"id": "hammer_anvil", "name": "Hammer and Anvil"}
    # Future: Add Dawn of War, Search and Destroy, etc.
]

var army_options = [
    {"id": "adeptus_custodes", "name": "Adeptus Custodes"},
    {"id": "space_marines", "name": "Space Marines"},
    {"id": "orks", "name": "Orks"}
]

var save_load_dialog: AcceptDialog

func _ready() -> void:
    _setup_dropdowns()
    _connect_signals()
    _setup_save_load_dialog()
    
    # Set defaults
    terrain_dropdown.selected = 0
    mission_dropdown.selected = 0
    deployment_dropdown.selected = 0
    player1_dropdown.selected = 0  # Custodes
    player2_dropdown.selected = 2  # Orks

func _setup_dropdowns() -> void:
    # Populate terrain dropdown
    for option in terrain_options:
        terrain_dropdown.add_item(option.name)
    
    # Populate mission dropdown
    for option in mission_options:
        mission_dropdown.add_item(option.name)
    
    # Populate deployment dropdown
    for option in deployment_options:
        deployment_dropdown.add_item(option.name)
    
    # Populate army dropdowns
    for option in army_options:
        player1_dropdown.add_item(option.name)
        player2_dropdown.add_item(option.name)

func _connect_signals() -> void:
    start_button.pressed.connect(_on_start_button_pressed)
    load_button.pressed.connect(_on_load_button_pressed)

func _setup_save_load_dialog() -> void:
    # Create save/load dialog
    var dialog_scene = load("res://scenes/SaveLoadDialog.tscn")
    if dialog_scene:
        save_load_dialog = dialog_scene.instantiate()
        add_child(save_load_dialog)
        save_load_dialog.load_requested.connect(_on_load_requested)

func _on_start_button_pressed() -> void:
    # Store configuration in GameState
    var config = {
        "terrain": terrain_options[terrain_dropdown.selected].id,
        "mission": mission_options[mission_dropdown.selected].id,
        "deployment": deployment_options[deployment_dropdown.selected].id,
        "player1_army": army_options[player1_dropdown.selected].id,
        "player2_army": army_options[player2_dropdown.selected].id
    }
    
    # Initialize game with configuration
    _initialize_game_with_config(config)
    
    # Transition to main game scene
    get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _initialize_game_with_config(config: Dictionary) -> void:
    # Initialize base game state
    GameState.initialize_default_state()
    
    # Apply terrain configuration
    TerrainManager.load_terrain_layout(config.terrain)
    
    # Apply mission configuration
    # MissionManager will use default "Take and Hold" for now
    
    # Load armies
    var player1_army = ArmyListManager.load_army_list(config.player1_army, 1)
    if not player1_army.is_empty():
        ArmyListManager.apply_army_to_game_state(player1_army, 1)
    
    var player2_army = ArmyListManager.load_army_list(config.player2_army, 2)
    if not player2_army.is_empty():
        ArmyListManager.apply_army_to_game_state(player2_army, 2)
    
    # Store configuration in game state for reference
    GameState.state.meta["game_config"] = config
    
    print("MainMenu: Initialized game with config: ", config)

func _on_load_button_pressed() -> void:
    if save_load_dialog:
        save_load_dialog.popup_centered(Vector2(600, 400))

func _on_load_requested(save_file: String) -> void:
    var success = SaveLoadManager.load_game(save_file)
    if success:
        print("MainMenu: Successfully loaded game: ", save_file)
        # Transition to main game scene
        get_tree().change_scene_to_file("res://scenes/Main.tscn")
    else:
        print("MainMenu: Failed to load game: ", save_file)
```

### Phase 3: Update Project Settings

```gdscript
# Update in project.godot
# Change main scene from Main.tscn to MainMenu.tscn
# run/main_scene="res://scenes/MainMenu.tscn"
```

### Phase 4: Modify Main.gd Initialization

```gdscript
# Update 40k/scripts/Main.gd _ready() function
func _ready() -> void:
    # Check if we're coming from main menu or loading a save
    var from_menu = GameState.state.meta.has("game_config")
    
    if not from_menu:
        # Legacy path: direct load for testing
        GameState.initialize_default_state()
    
    # Rest of initialization continues as normal...
    view_zoom = 0.3
    view_offset = Vector2(0, 0)
    update_view_transform()
    # ... rest of _ready() function
```

## Implementation Tasks

1. **Create MainMenu.tscn scene file** with UI layout
2. **Create MainMenu.gd script** with menu logic
3. **Update project.godot** to set MainMenu.tscn as main scene
4. **Modify Main.gd** to handle initialization from menu
5. **Test menu flow** with different configurations
6. **Test save/load integration** from menu
7. **Add input validation** (prevent same army for both players if desired)
8. **Add visual polish** (backgrounds, fonts, hover states)

## Validation Gates

```bash
# Run from 40k directory
# Check that Godot project runs without errors
timeout 30 godot --headless --quit

# Verify scene files are valid
ls -la scenes/MainMenu.tscn
ls -la scripts/MainMenu.gd

# Check that the menu loads properly
echo "Manual testing required:"
echo "1. Start game - should show main menu"
echo "2. Select different options in dropdowns"
echo "3. Click Start Game - should load battle with selected config"
echo "4. Click Load Game - should show save/load dialog"
echo "5. Load a save - should transition to game"
```

## Error Handling

1. **Missing Resources**: Gracefully handle if army/terrain files don't exist
2. **Scene Transition**: Add error handling for scene loading failures
3. **Save/Load**: Handle corrupted or incompatible save files
4. **Configuration Validation**: Ensure all required fields are selected before starting

## Testing Considerations

1. **Menu Navigation**: Test all dropdown combinations
2. **Scene Transitions**: Verify smooth transitions to/from game
3. **State Persistence**: Ensure configuration is properly applied to game
4. **Load Integration**: Test that loading from menu works correctly
5. **Edge Cases**: Test with missing armies, invalid configurations

## Future Enhancements

1. **Additional Terrain Layouts**: Add more Chapter Approved layouts
2. **More Missions**: Implement additional primary missions
3. **Deployment Zones**: Add Dawn of War, Search and Destroy options
4. **Army Builder**: Link to army customization screen
5. **Settings Menu**: Add graphics, audio, gameplay options
6. **Campaign Mode**: Track victories across multiple games

## External Documentation

- Wahapedia Core Rules: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- Godot UI Documentation: https://docs.godotengine.org/en/4.4/tutorials/ui/
- Godot Scene Management: https://docs.godotengine.org/en/4.4/tutorials/scripting/scene_tree.html

## Confidence Score: 8/10

The implementation is straightforward with clear patterns to follow from existing code. The main complexity is ensuring proper data flow between menu and game initialization. The score would be higher with more Godot UI examples, but the existing SaveLoadDialog provides a good reference pattern.