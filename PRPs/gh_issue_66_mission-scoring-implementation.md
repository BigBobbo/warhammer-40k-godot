# PRP: Mission Scoring Implementation for Warhammer 40k Game

## Issue Context
GitHub Issue #66: Implement primary mission scoring system with "Take and Hold" mission and Strike Force deployment for the MVP. Players score victory points by holding objectives at the start of their command phase.

## Research Findings

### Existing Codebase Architecture

1. **Phase System**:
   - Command phase implemented in `40k/phases/CommandPhase.gd` and `40k/scripts/CommandController.gd`
   - Scoring phase implemented in `40k/phases/ScoringPhase.gd` and `40k/scripts/ScoringController.gd`
   - Phase flow: Deployment → Command → Movement → Shooting → Charge → Fight → Scoring
   - PhaseManager controls transitions in `40k/autoloads/PhaseManager.gd`

2. **Board Layout**:
   - Board size: 44" x 60" (1760 x 2400 pixels at 40px per inch)
   - Coordinate system: top-left origin, x-axis horizontal, y-axis vertical
   - Deployment zones already defined in `GameState._get_dawn_of_war_zone_1_coords()` and `_get_dawn_of_war_zone_2_coords()`
   - Measurement system in `40k/autoloads/Measurement.gd` handles inches to pixels conversion

3. **Unit Data Structure**:
   - Units already have `objective_control` stat in their meta.stats (e.g., Intercessors have OC: 2)
   - Unit positions stored as Vector2 in model data
   - Army lists in `40k/armies/*.json` contain OC values

4. **Game State**:
   - `GameState.state.board.objectives` array ready for objective data
   - Battle round tracking in `GameState.get_battle_round()`
   - Player victory points stored in `GameState.state.players[player_id].vp`

### Mission Rules (from Wahapedia)

**Take and Hold Primary Mission**:
- Score from battle round 2 onwards
- Score at end of Command phase (or end of turn if round 5 and going second)
- 5VP per controlled objective (max 15VP per turn)
- Max 50VP from primary across whole game

**Strike Force Deployment**:
- 5 objectives total:
  - 1 in center of board (22", 30")
  - 4 in table quarters:
    - Top-left: (10", 14") - 10" from short edge, 14" from long edge
    - Top-right: (34", 14") - 10" from short edge, 14" from long edge  
    - Bottom-left: (10", 46") - 10" from short edge, 14" from long edge
    - Bottom-right: (34", 46") - 10" from short edge, 14" from long edge

**Objective Control Rules**:
- Objectives are 40mm diameter markers
- Controlled by player with most OC value within 3" of center
- Only models with OC > 0 can control (Battle-shocked units have OC = 0)

## Implementation Blueprint

### Phase 1: Mission Manager System

```gdscript
# New file: 40k/autoloads/MissionManager.gd
extends Node

signal objective_control_changed(objective_id: String, controller: int)
signal victory_points_scored(player: int, points: int, reason: String)

var current_mission: Dictionary = {}
var objective_control_state: Dictionary = {} # objective_id -> controlling_player

func _ready() -> void:
    initialize_default_mission()
    
func initialize_default_mission() -> void:
    current_mission = {
        "name": "Take and Hold",
        "type": "primary",
        "deployment": "strike_force",
        "max_vp": 50,
        "scoring_rules": {
            "when": "command_phase_end",
            "start_round": 2,
            "vp_per_objective": 5,
            "max_vp_per_turn": 15
        }
    }
    
    # Initialize objectives for Strike Force
    _setup_strike_force_objectives()

func _setup_strike_force_objectives() -> void:
    var objectives = [
        {"id": "obj_center", "position": Vector2(880, 1200), "radius_mm": 40},
        {"id": "obj_tl", "position": Vector2(400, 560), "radius_mm": 40},  
        {"id": "obj_tr", "position": Vector2(1360, 560), "radius_mm": 40},
        {"id": "obj_bl", "position": Vector2(400, 1840), "radius_mm": 40},
        {"id": "obj_br", "position": Vector2(1360, 1840), "radius_mm": 40}
    ]
    
    GameState.state.board["objectives"] = objectives
    
    # Initialize control state
    for obj in objectives:
        objective_control_state[obj.id] = 0  # 0 = contested/uncontrolled
```

### Phase 2: Objective Visual System

```gdscript
# New file: 40k/scripts/ObjectiveVisual.gd
extends Node2D
class_name ObjectiveVisual

var objective_data: Dictionary = {}
var control_indicator: Node2D
var objective_marker: Node2D

func setup(data: Dictionary) -> void:
    objective_data = data
    position = data.position
    _create_visuals()
    
func _create_visuals() -> void:
    # Create objective marker (40mm circle)
    objective_marker = Node2D.new()
    add_child(objective_marker)
    
    var radius_px = Measurement.mm_to_px(objective_data.radius_mm)
    
    # Base marker
    var base = Line2D.new()
    base.width = 2.0
    base.default_color = Color.GRAY
    base.add_point(Vector2.ZERO)
    for i in range(33):
        var angle = i * TAU / 32
        base.add_point(Vector2(cos(angle), sin(angle)) * radius_px)
    base.closed = true
    objective_marker.add_child(base)
    
    # Control range indicator (3" radius)
    var control_range = Line2D.new()
    control_range.width = 1.0
    control_range.default_color = Color(0.5, 0.5, 0.5, 0.3)
    var control_radius = Measurement.inches_to_px(3.0)
    for i in range(33):
        var angle = i * TAU / 32
        control_range.add_point(Vector2(cos(angle), sin(angle)) * control_radius)
    control_range.closed = true
    objective_marker.add_child(control_range)
    
    # Control indicator
    control_indicator = Label.new()
    control_indicator.text = "Uncontrolled"
    control_indicator.position = Vector2(-40, -radius_px - 20)
    add_child(control_indicator)

func update_control(player: int) -> void:
    match player:
        0:
            control_indicator.text = "Contested"
            control_indicator.modulate = Color.YELLOW
        1:
            control_indicator.text = "Player 1"
            control_indicator.modulate = Color.BLUE
        2:
            control_indicator.text = "Player 2"
            control_indicator.modulate = Color.RED
```

### Phase 3: Objective Control Logic

```gdscript
# Add to MissionManager.gd

func check_all_objectives() -> void:
    var objectives = GameState.state.board.get("objectives", [])
    var units = GameState.state.get("units", {})
    
    for obj in objectives:
        var controller = _check_objective_control(obj, units)
        var old_controller = objective_control_state.get(obj.id, 0)
        
        if controller != old_controller:
            objective_control_state[obj.id] = controller
            emit_signal("objective_control_changed", obj.id, controller)

func _check_objective_control(objective: Dictionary, units: Dictionary) -> int:
    var control_radius = Measurement.inches_to_px(3.0)
    var obj_pos = objective.position
    
    var player1_oc = 0
    var player2_oc = 0
    
    for unit_id in units:
        var unit = units[unit_id]
        var owner = unit.get("owner", 0)
        
        # Skip if unit has no OC value
        var oc_value = unit.get("meta", {}).get("stats", {}).get("objective_control", 0)
        if oc_value <= 0:
            continue
            
        # Check if unit is battle-shocked
        if unit.get("flags", {}).get("battle_shocked", false):
            continue
            
        # Check each model in the unit
        for model in unit.get("models", []):
            if not model.get("alive", true):
                continue
                
            var model_pos = model.get("position")
            if model_pos == null:
                continue
                
            # Convert position if needed
            if model_pos is Dictionary:
                model_pos = Vector2(model_pos.x, model_pos.y)
                
            # Check if within control range
            if model_pos.distance_to(obj_pos) <= control_radius:
                if owner == 1:
                    player1_oc += oc_value
                elif owner == 2:
                    player2_oc += oc_value
                break  # Only count unit once

    # Determine controller
    if player1_oc > player2_oc:
        return 1
    elif player2_oc > player1_oc:
        return 2
    else:
        return 0  # Contested or uncontrolled

func score_primary_objectives() -> void:
    var battle_round = GameState.get_battle_round()
    var active_player = GameState.get_active_player()
    
    # Check if scoring conditions are met
    if battle_round < 2:
        print("MissionManager: No scoring in battle round 1")
        return
        
    if current_mission.name != "Take and Hold":
        return
        
    # Count controlled objectives
    var controlled_count = 0
    for obj_id in objective_control_state:
        if objective_control_state[obj_id] == active_player:
            controlled_count += 1
    
    # Calculate VP
    var vp_earned = min(
        controlled_count * current_mission.scoring_rules.vp_per_objective,
        current_mission.scoring_rules.max_vp_per_turn
    )
    
    if vp_earned > 0:
        # Update player VP
        var current_vp = GameState.state.players[str(active_player)].get("vp", 0)
        var primary_vp = GameState.state.players[str(active_player)].get("primary_vp", 0)
        
        # Cap at max primary VP
        var new_primary_vp = min(primary_vp + vp_earned, current_mission.max_vp)
        var actual_vp_earned = new_primary_vp - primary_vp
        
        GameState.state.players[str(active_player)]["vp"] = current_vp + actual_vp_earned
        GameState.state.players[str(active_player)]["primary_vp"] = new_primary_vp
        
        emit_signal("victory_points_scored", active_player, actual_vp_earned, 
                   "Controlled %d objectives" % controlled_count)
        
        print("MissionManager: Player %d scored %d VP (controlled %d objectives)" % 
              [active_player, actual_vp_earned, controlled_count])
```

### Phase 4: Integration with Command Phase

```gdscript
# Modify 40k/phases/CommandPhase.gd

func _on_phase_enter() -> void:
    phase_type = GameStateData.Phase.COMMAND
    print("CommandPhase: Entering command phase for player ", get_current_player())
    print("CommandPhase: Battle round ", GameState.get_battle_round())
    
    # Check objectives at start of command phase
    if MissionManager:
        MissionManager.check_all_objectives()

func _handle_end_command() -> Dictionary:
    var current_player = get_current_player()
    
    print("CommandPhase: Player %d ending command phase" % current_player)
    
    # Score primary objectives before ending phase
    if MissionManager:
        MissionManager.score_primary_objectives()
    
    emit_signal("phase_completed")
    
    return {
        "success": true,
        "message": "Command phase ended, objectives scored"
    }
```

### Phase 5: UI Updates

```gdscript
# Modify 40k/scripts/CommandController.gd - add to _setup_right_panel()

# After existing panel setup, add objective status
var objectives_section = VBoxContainer.new()
objectives_section.name = "ObjectivesSection"
command_panel.add_child(objectives_section)

command_panel.add_child(HSeparator.new())

var obj_title = Label.new()
obj_title.text = "Objectives"
obj_title.add_theme_font_size_override("font_size", 14)
objectives_section.add_child(obj_title)

# Show objective control status
if MissionManager:
    for obj_id in MissionManager.objective_control_state:
        var obj_label = Label.new()
        var controller = MissionManager.objective_control_state[obj_id]
        var control_text = "Uncontrolled"
        if controller == 1:
            control_text = "Player 1"
        elif controller == 2:
            control_text = "Player 2"
        obj_label.text = "%s: %s" % [obj_id.replace("obj_", "").to_upper(), control_text]
        objectives_section.add_child(obj_label)

# Show VP status
command_panel.add_child(HSeparator.new())

var vp_label = Label.new()
var p1_vp = GameState.state.players["1"].get("vp", 0)
var p2_vp = GameState.state.players["2"].get("vp", 0)
vp_label.text = "Victory Points\nPlayer 1: %d\nPlayer 2: %d" % [p1_vp, p2_vp]
command_panel.add_child(vp_label)
```

### Phase 6: Visual Board Integration

```gdscript
# Modify 40k/scripts/Main.gd - add to _ready()

# After existing setup
_setup_objectives()

func _setup_objectives() -> void:
    var objectives_container = Node2D.new()
    objectives_container.name = "Objectives"
    objectives_container.z_index = -8  # Between board and deployment zones
    board_visual.add_child(objectives_container)
    
    if MissionManager:
        var objectives = GameState.state.board.get("objectives", [])
        for obj in objectives:
            var obj_visual = preload("res://scripts/ObjectiveVisual.gd").new()
            obj_visual.setup(obj)
            objectives_container.add_child(obj_visual)
            
            # Connect to control changes
            MissionManager.objective_control_changed.connect(
                func(obj_id, controller):
                    if obj_id == obj.id:
                        obj_visual.update_control(controller)
            )
```

## Implementation Tasks

1. **Create MissionManager autoload** (40k/autoloads/MissionManager.gd)
   - Initialize Take and Hold mission
   - Setup Strike Force objectives
   - Implement objective control checking
   - Handle VP scoring

2. **Create ObjectiveVisual scene** (40k/scripts/ObjectiveVisual.gd)
   - Display 40mm objective markers
   - Show 3" control radius
   - Update control indicators

3. **Integrate with Command Phase**
   - Check objectives at phase start
   - Score VP at phase end (from round 2+)
   - Update UI with objective status

4. **Update UI Controllers**
   - Show objective control in CommandController
   - Display VP totals
   - Add scoring log to ScoringController

5. **Update Main.gd**
   - Add objectives to board visual
   - Connect control change signals

6. **Add to project.godot autoloads**
   - Register MissionManager as autoload

## Validation Gates

```bash
# Run Godot in headless mode to validate
export PATH="$HOME/bin:$PATH"
timeout 30 godot --headless --script 40k/tests/unit/test_mission_scoring.gd

# Check that objectives are placed correctly
grep -r "obj_center\|obj_tl\|obj_tr\|obj_bl\|obj_br" 40k/

# Verify MissionManager is added to autoloads
grep "MissionManager" 40k/project.godot

# Test objective control calculation
# Create test file: 40k/tests/unit/test_mission_scoring.gd
```

## Test Validation Script

```gdscript
# 40k/tests/unit/test_mission_scoring.gd
extends GutTest

func test_objective_placement():
    var objectives = GameState.state.board.get("objectives", [])
    assert_eq(objectives.size(), 5, "Should have 5 objectives")
    
    # Check center objective
    var center = objectives[0]
    assert_eq(center.position, Vector2(880, 1200), "Center objective position")
    
func test_objective_control():
    # Place a unit near objective
    var test_unit = {
        "owner": 1,
        "meta": {"stats": {"objective_control": 2}},
        "models": [{"position": Vector2(880, 1200), "alive": true}]
    }
    GameState.state.units["TEST"] = test_unit
    
    MissionManager.check_all_objectives()
    assert_eq(MissionManager.objective_control_state["obj_center"], 1)
    
func test_vp_scoring():
    GameState.state.meta.battle_round = 2
    GameState.state.meta.active_player = 1
    MissionManager.objective_control_state = {
        "obj_center": 1,
        "obj_tl": 1,
        "obj_tr": 0
    }
    
    MissionManager.score_primary_objectives()
    var p1_vp = GameState.state.players["1"].get("vp", 0)
    assert_eq(p1_vp, 10, "Should score 10 VP for 2 objectives")
```

## Common Pitfalls to Avoid

1. **Coordinate System**: Remember board uses top-left origin (0,0) at top-left corner
2. **Pixel Conversion**: Always use Measurement functions for inches to pixels
3. **OC Calculation**: Only count each unit once, even if multiple models are in range
4. **Battle-shocked**: Units with battle-shocked flag have OC = 0
5. **VP Capping**: Primary objectives cap at 15 VP per turn, 50 VP total

## Success Criteria

- [ ] 5 objectives appear on Strike Force board layout
- [ ] Objectives show control status visually
- [ ] Control calculated correctly based on OC values within 3"
- [ ] VP scored at end of command phase from round 2+
- [ ] VP capped at 15 per turn, 50 total for primary
- [ ] UI shows objective control and VP totals
- [ ] All existing phases continue to work

## Confidence Score: 8/10

**Reasoning:**
- Clear integration points with existing phase system
- OC values already present in unit data
- Board coordinate system well understood
- Measurement utilities already available
- Similar visual patterns exist (deployment zones)

**Risk Factors:**
- Need to ensure MissionManager autoload is registered properly
- Must handle null position checks for undeployed units
- Visual z-ordering needs careful management

This PRP provides comprehensive context for one-pass implementation with clear validation steps and integration patterns matching the existing codebase architecture.