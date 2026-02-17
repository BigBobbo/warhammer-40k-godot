extends Node
const GameStateData = preload("res://autoloads/GameState.gd")

# MissionManager - Handles mission objectives, control, and victory point scoring
# Implements the "Take and Hold" primary mission for the MVP

signal objective_control_changed(objective_id: String, controller: int)
signal victory_points_scored(player: int, points: int, reason: String)

var current_mission: Dictionary = {}
var objective_control_state: Dictionary = {} # objective_id -> controlling_player
var objectives_visual_refs: Dictionary = {} # Store references to visual nodes

func _ready() -> void:
	print("MissionManager: Initializing mission system")
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

	# Initialize objectives based on deployment type
	var deployment_type = GameState.get_deployment_type()
	_setup_objectives_for_deployment(deployment_type)

	print("MissionManager: Initialized %s mission" % current_mission.name)

func _setup_objectives_for_deployment(deployment_type: String) -> void:
	# Get objective positions from centralized data source (already in pixels)
	var objectives = DeploymentZoneData.get_objectives_px(deployment_type)

	# Store objectives in GameState
	GameState.state.board["objectives"] = objectives

	# Initialize control state
	objective_control_state.clear()
	for obj in objectives:
		objective_control_state[obj.id] = 0  # 0 = contested/uncontrolled

	print("MissionManager: Set up %d objectives for %s deployment" % [objectives.size(), deployment_type])
	for obj in objectives:
		print("  - %s at position %s (zone: %s)" % [obj.id, obj.position, obj.get("zone", "unknown")])

func check_all_objectives() -> void:
	var objectives = GameState.state.board.get("objectives", [])
	
	# If objectives are missing, reinitialize them
	if objectives.size() == 0:
		print("MissionManager: No objectives found, reinitializing...")
		var deployment_type = GameState.get_deployment_type()
		_setup_objectives_for_deployment(deployment_type)
		objectives = GameState.state.board.get("objectives", [])
	
	var units = GameState.state.get("units", {})
	
	print("MissionManager: Checking control for %d objectives with %d units" % [objectives.size(), units.size()])
	
	for obj in objectives:
		print("\nChecking objective: %s at position %s" % [obj.id, obj.position])
		var controller = _check_objective_control(obj, units)
		var old_controller = objective_control_state.get(obj.id, 0)
		
		if controller != old_controller:
			objective_control_state[obj.id] = controller
			emit_signal("objective_control_changed", obj.id, controller)
			print("MissionManager: %s control changed from %d to %d" % [obj.id, old_controller, controller])

func _check_objective_control(objective: Dictionary, units: Dictionary) -> int:
	# Control radius is 3" + 20mm (radius of objective marker)
	# 20mm = 0.78740157 inches, so total is 3.78740157 inches
	var control_radius = Measurement.inches_to_px(3.78740157)
	var obj_pos = objective.position
	
	var player1_oc = 0
	var player2_oc = 0
	var units_in_range = []
	
	for unit_id in units:
		var unit = units[unit_id]
		var owner = unit.get("owner", 0)
		
		# Skip if unit has no OC value
		var oc_value = unit.get("meta", {}).get("stats", {}).get("objective_control", 0)
		if oc_value <= 0:
			print("  Skipping %s - no OC value (OC: %d)" % [unit_id, oc_value])
			continue
		
		# Check if unit is battle-shocked
		if unit.get("flags", {}).get("battle_shocked", false):
			print("  Skipping %s - battle shocked" % unit_id)
			continue
		
		# Check if unit has deployed status
		var status = unit.get("status", GameStateData.UnitStatus.UNDEPLOYED)
		if status == GameStateData.UnitStatus.UNDEPLOYED:
			print("  Skipping %s - not deployed (status: %d)" % [unit_id, status])
			continue
		
		print("  Checking unit %s (Player %d, OC: %d, %d models)" % [
			unit_id, owner, oc_value, unit.get("models", []).size()
		])
		
		# Check each model in the unit
		var unit_counted = false
		for model in unit.get("models", []):
			if unit_counted:
				break
				
			if not model.get("alive", true):
				continue
			
			var model_pos = model.get("position")
			if model_pos == null:
				continue
			
			# Convert position if needed
			if model_pos is Dictionary:
				model_pos = Vector2(model_pos.x, model_pos.y)
			
			# Check if within control range
			var distance = model_pos.distance_to(obj_pos)
			var distance_inches = Measurement.px_to_inches(distance)
			
			# Debug log for each model checked
			print("  Model from %s at %s, distance: %.1f\" (%.1fpx) from %s at %s" % [
				unit_id, model_pos, distance_inches, distance, objective.id, obj_pos
			])
			
			if distance <= control_radius:
				units_in_range.append("%s (Player %d, OC: %d)" % [unit_id, owner, oc_value])
				if owner == 1:
					player1_oc += oc_value
				elif owner == 2:
					player2_oc += oc_value
				unit_counted = true  # Only count unit once
				print("    -> Within control range! Adding OC: %d for Player %d" % [oc_value, owner])
	
	# Log units in range if any
	if units_in_range.size() > 0:
		print("MissionManager: Units within control range (3.79\") of %s:" % objective.id)
		for unit_desc in units_in_range:
			print("  - %s" % unit_desc)
		print("  Total OC - Player 1: %d, Player 2: %d" % [player1_oc, player2_oc])
	
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
	
	print("MissionManager: Checking primary scoring for Player %d in battle round %d" % [active_player, battle_round])
	
	# Check if scoring conditions are met
	if battle_round < 2:
		print("MissionManager: No scoring in battle round 1")
		return
	
	if current_mission.name != "Take and Hold":
		return
	
	# Count controlled objectives
	var controlled_objectives = []
	for obj_id in objective_control_state:
		if objective_control_state[obj_id] == active_player:
			controlled_objectives.append(obj_id)
	
	var controlled_count = controlled_objectives.size()
	
	if controlled_count > 0:
		print("MissionManager: Player %d controls %d objectives: %s" % [active_player, controlled_count, controlled_objectives])
	else:
		print("MissionManager: Player %d controls no objectives" % active_player)
	
	# Calculate VP
	var vp_earned = min(
		controlled_count * current_mission.scoring_rules.vp_per_objective,
		current_mission.scoring_rules.max_vp_per_turn
	)
	
	if vp_earned > 0:
		# Update player VP
		var player_key = str(active_player)
		if not GameState.state.players.has(player_key):
			GameState.state.players[player_key] = {}
		
		var current_vp = GameState.state.players[player_key].get("vp", 0)
		var primary_vp = GameState.state.players[player_key].get("primary_vp", 0)
		
		# Cap at max primary VP
		var new_primary_vp = min(primary_vp + vp_earned, current_mission.max_vp)
		var actual_vp_earned = new_primary_vp - primary_vp
		
		GameState.state.players[player_key]["vp"] = current_vp + actual_vp_earned
		GameState.state.players[player_key]["primary_vp"] = new_primary_vp
		
		emit_signal("victory_points_scored", active_player, actual_vp_earned, 
				   "Controlled %d objectives" % controlled_count)
		
		print("MissionManager: Player %d scored %d VP (controlled %d objectives)" % 
			  [active_player, actual_vp_earned, controlled_count])
		print("MissionManager: Player %d total VP: %d (Primary: %d)" % 
			  [active_player, current_vp + actual_vp_earned, new_primary_vp])
	else:
		print("MissionManager: Player %d scored 0 VP" % active_player)

func get_objective_control_summary() -> Dictionary:
	var summary = {
		"objectives": {},
		"player1_controlled": 0,
		"player2_controlled": 0,
		"contested": 0
	}
	
	for obj_id in objective_control_state:
		var controller = objective_control_state[obj_id]
		summary.objectives[obj_id] = controller
		
		match controller:
			1:
				summary.player1_controlled += 1
			2:
				summary.player2_controlled += 1
			_:
				summary.contested += 1
	
	return summary

func get_vp_summary() -> Dictionary:
	var p1_vp = GameState.state.players.get("1", {}).get("vp", 0)
	var p1_primary = GameState.state.players.get("1", {}).get("primary_vp", 0)
	var p1_secondary = GameState.state.players.get("1", {}).get("secondary_vp", 0)
	var p2_vp = GameState.state.players.get("2", {}).get("vp", 0)
	var p2_primary = GameState.state.players.get("2", {}).get("primary_vp", 0)
	var p2_secondary = GameState.state.players.get("2", {}).get("secondary_vp", 0)

	return {
		"player1": {
			"total": p1_vp,
			"primary": p1_primary,
			"secondary": p1_secondary,
		},
		"player2": {
			"total": p2_vp,
			"primary": p2_primary,
			"secondary": p2_secondary,
		}
	}
