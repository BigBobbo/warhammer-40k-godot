extends Node
const GameStateData = preload("res://autoloads/GameState.gd")

# MissionManager - Handles mission objectives, control, and victory point scoring
# Supports multiple primary missions via MissionData registry

signal objective_control_changed(objective_id: String, controller: int)
signal victory_points_scored(player: int, points: int, reason: String)
signal objective_removed(objective_id: String)

var current_mission: Dictionary = {}
var objective_control_state: Dictionary = {} # objective_id -> controlling_player
var objectives_visual_refs: Dictionary = {} # Store references to visual nodes

# Kill tracking for Purge the Foe
var _kills_this_round: Dictionary = {"1": 0, "2": 0}  # player_key -> units destroyed this round

func _ready() -> void:
	print("MissionManager: Initializing mission system")
	initialize_default_mission()

func initialize_default_mission() -> void:
	# Check if a mission was specified in the game config
	var mission_id = _get_configured_mission_id()
	initialize_mission(mission_id)

func _get_configured_mission_id() -> String:
	var config = GameState.state.get("meta", {}).get("game_config", {})
	var mission_id = config.get("mission", "take_and_hold")
	print("MissionManager: Configured mission ID: %s" % mission_id)
	return mission_id

func initialize_mission(mission_id: String) -> void:
	# Load mission data from registry
	var mission_data = MissionData.get_mission(mission_id)
	if mission_data.is_empty():
		print("MissionManager: Unknown mission '%s', falling back to take_and_hold" % mission_id)
		mission_data = MissionData.get_mission("take_and_hold")
		mission_id = "take_and_hold"

	current_mission = {
		"id": mission_id,
		"name": mission_data.name,
		"type": "primary",
		"scoring_type": mission_data.scoring_type,
		"max_vp": mission_data.max_vp,
		"scoring_rules": mission_data.scoring.duplicate(true),
		"start_round": mission_data.start_round,
		"special_rules": mission_data.special_rules.duplicate(),
		"objectives_used": mission_data.objectives_used,
	}

	# Initialize objectives based on deployment type
	var deployment_type = GameState.get_deployment_type()
	_setup_objectives_for_deployment(deployment_type)

	# Reset kill tracking
	_kills_this_round = {"1": 0, "2": 0}

	# Store mission type in GameState meta for reference
	GameState.state.meta["mission_type"] = mission_id

	print("MissionManager: Initialized '%s' mission (scoring_type: %s)" % [current_mission.name, current_mission.scoring_type])

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

# ============================================================================
# PRIMARY SCORING — dispatches to mission-specific scoring logic
# ============================================================================

func score_primary_objectives() -> void:
	var battle_round = GameState.get_battle_round()
	var active_player = GameState.get_active_player()
	var start_round = current_mission.get("start_round", 2)

	print("MissionManager: Checking primary scoring for Player %d in battle round %d (mission: %s)" % [active_player, battle_round, current_mission.name])

	# Check if scoring conditions are met
	if battle_round < start_round:
		print("MissionManager: No scoring before battle round %d" % start_round)
		return

	# Dispatch to mission-specific scoring
	var scoring_type = current_mission.get("scoring_type", "hold_objectives")
	match scoring_type:
		"hold_objectives":
			_score_hold_objectives(active_player, battle_round)
		"hold_and_kill":
			_score_hold_and_kill(active_player, battle_round)
		"supply_drop":
			_score_supply_drop(active_player, battle_round)
		"sites_of_power":
			_score_sites_of_power(active_player, battle_round)
		"hold_and_burn":
			# Scorched Earth: scoring uses hold_objectives base + burn bonuses (burn not yet implemented)
			_score_hold_objectives(active_player, battle_round)
		"ritual":
			# The Ritual: falls back to hold scoring (ritual actions not yet implemented)
			_score_hold_objectives(active_player, battle_round)
		"terraform":
			# Terraform: falls back to hold scoring (flipping not yet implemented)
			_score_hold_objectives(active_player, battle_round)
		_:
			print("MissionManager: Unknown scoring type '%s', falling back to hold_objectives" % scoring_type)
			_score_hold_objectives(active_player, battle_round)

# ============================================================================
# TAKE AND HOLD / LINCHPIN / basic hold_objectives scoring
# ============================================================================

func _score_hold_objectives(active_player: int, _battle_round: int) -> void:
	var scoring_rules = current_mission.get("scoring_rules", {})
	var vp_per_obj = scoring_rules.get("vp_per_objective", 5)
	var center_bonus = scoring_rules.get("vp_center_bonus", 0)
	var max_per_turn = scoring_rules.get("max_vp_per_turn", 15)

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
	var vp_earned = controlled_count * vp_per_obj

	# Add center bonus if applicable (Linchpin)
	if center_bonus > 0 and "obj_center" in controlled_objectives:
		vp_earned += center_bonus
		print("MissionManager: Center objective bonus: +%d VP" % center_bonus)

	vp_earned = mini(vp_earned, max_per_turn)

	_apply_primary_vp(active_player, vp_earned, "Controlled %d objectives" % controlled_count)

# ============================================================================
# PURGE THE FOE — hold objectives + destroy enemy units
# ============================================================================

func _score_hold_and_kill(active_player: int, _battle_round: int) -> void:
	var scoring_rules = current_mission.get("scoring_rules", {})
	var hold_any_vp = scoring_rules.get("hold_any_vp", 4)
	var hold_more_vp = scoring_rules.get("hold_more_vp", 4)
	var kill_any_vp = scoring_rules.get("kill_any_vp", 4)
	var kill_more_vp = scoring_rules.get("kill_more_vp", 4)
	var max_per_turn = scoring_rules.get("max_vp_per_turn", 16)

	var opponent = 3 - active_player
	var vp_earned = 0
	var reasons = []

	# Holding component
	var player_objectives = 0
	var opponent_objectives = 0
	for obj_id in objective_control_state:
		var controller = objective_control_state[obj_id]
		if controller == active_player:
			player_objectives += 1
		elif controller == opponent:
			opponent_objectives += 1

	if player_objectives > 0:
		vp_earned += hold_any_vp
		reasons.append("holds %d objectives" % player_objectives)
	if player_objectives > opponent_objectives:
		vp_earned += hold_more_vp
		reasons.append("holds more than opponent")

	# Kill component
	var player_kills = _kills_this_round.get(str(active_player), 0)
	var opponent_kills = _kills_this_round.get(str(opponent), 0)

	if player_kills > 0:
		vp_earned += kill_any_vp
		reasons.append("destroyed %d units" % player_kills)
	if player_kills > opponent_kills:
		vp_earned += kill_more_vp
		reasons.append("destroyed more than opponent")

	vp_earned = mini(vp_earned, max_per_turn)

	var reason_text = "; ".join(reasons) if reasons.size() > 0 else "No scoring conditions met"
	print("MissionManager: Purge the Foe - %s" % reason_text)
	_apply_primary_vp(active_player, vp_earned, reason_text)

# ============================================================================
# SUPPLY DROP — Only NML objectives score; remove one in Round 4
# ============================================================================

func _score_supply_drop(active_player: int, battle_round: int) -> void:
	var scoring_rules = current_mission.get("scoring_rules", {})
	var vp_per_obj = scoring_rules.get("vp_per_objective", 5)
	var max_per_turn = scoring_rules.get("max_vp_per_turn", 15)
	var remove_round = scoring_rules.get("remove_random_nml_round", 4)

	# Handle objective removal at start of the specified round
	if battle_round == remove_round and active_player == 1:
		# Remove one random NML objective (only do this once, when P1 scores)
		_remove_random_nml_objective()

	# Only count NML objectives
	var controlled_nml = []
	var objectives = GameState.state.board.get("objectives", [])
	for obj in objectives:
		var zone = obj.get("zone", "")
		if zone == "no_mans_land" and objective_control_state.get(obj.id, 0) == active_player:
			controlled_nml.append(obj.id)

	var controlled_count = controlled_nml.size()

	if controlled_count > 0:
		print("MissionManager: Supply Drop - Player %d controls %d NML objectives: %s" % [active_player, controlled_count, controlled_nml])
	else:
		print("MissionManager: Supply Drop - Player %d controls no NML objectives" % active_player)

	var vp_earned = mini(controlled_count * vp_per_obj, max_per_turn)
	_apply_primary_vp(active_player, vp_earned, "Controlled %d NML objectives" % controlled_count)

func _remove_random_nml_objective() -> void:
	var objectives = GameState.state.board.get("objectives", [])
	var nml_objectives = []
	for i in range(objectives.size()):
		if objectives[i].get("zone", "") == "no_mans_land":
			nml_objectives.append(i)

	if nml_objectives.is_empty():
		print("MissionManager: Supply Drop - No NML objectives to remove")
		return

	# Pick a random NML objective to remove
	var remove_index = nml_objectives[randi() % nml_objectives.size()]
	var removed_obj = objectives[remove_index]
	var removed_id = removed_obj.id

	print("MissionManager: Supply Drop - Removing NML objective '%s' in Round 4" % removed_id)
	objectives.remove_at(remove_index)
	objective_control_state.erase(removed_id)
	emit_signal("objective_removed", removed_id)

# ============================================================================
# SITES OF POWER — Characters on NML objectives
# ============================================================================

func _score_sites_of_power(active_player: int, _battle_round: int) -> void:
	var scoring_rules = current_mission.get("scoring_rules", {})
	var vp_per_char = scoring_rules.get("vp_per_character_on_nml_objective", 5)
	var max_per_turn = scoring_rules.get("max_vp_per_turn", 15)

	var control_radius = Measurement.inches_to_px(3.78740157)
	var objectives = GameState.state.board.get("objectives", [])
	var units = GameState.state.get("units", {})
	var characters_on_nml = 0

	for obj in objectives:
		if obj.get("zone", "") != "no_mans_land":
			continue
		var obj_pos = obj.position

		for unit_id in units:
			var unit = units[unit_id]
			if unit.get("owner", 0) != active_player:
				continue
			var keywords = unit.get("meta", {}).get("keywords", [])
			if "CHARACTER" not in keywords:
				continue
			if unit.get("flags", {}).get("battle_shocked", false):
				continue

			# Check if any model of this character unit is within range
			for model in unit.get("models", []):
				if not model.get("alive", true):
					continue
				var model_pos = model.get("position")
				if model_pos == null:
					continue
				if model_pos is Dictionary:
					model_pos = Vector2(model_pos.x, model_pos.y)
				if model_pos.distance_to(obj_pos) <= control_radius:
					characters_on_nml += 1
					print("MissionManager: Sites of Power - Character %s on NML objective %s" % [unit_id, obj.id])
					break  # Only count this character once

	var vp_earned = mini(characters_on_nml * vp_per_char, max_per_turn)
	_apply_primary_vp(active_player, vp_earned, "%d characters on NML objectives" % characters_on_nml)

# ============================================================================
# VP APPLICATION — common VP bookkeeping
# ============================================================================

func _apply_primary_vp(active_player: int, vp_earned: int, reason: String) -> void:
	if vp_earned > 0:
		var player_key = str(active_player)
		if not GameState.state.players.has(player_key):
			GameState.state.players[player_key] = {}

		var current_vp = GameState.state.players[player_key].get("vp", 0)
		var primary_vp = GameState.state.players[player_key].get("primary_vp", 0)

		# Cap at max primary VP
		var max_vp = current_mission.get("max_vp", MissionData.MAX_PRIMARY_VP)
		var new_primary_vp = mini(primary_vp + vp_earned, max_vp)
		var actual_vp_earned = new_primary_vp - primary_vp

		GameState.state.players[player_key]["vp"] = current_vp + actual_vp_earned
		GameState.state.players[player_key]["primary_vp"] = new_primary_vp

		emit_signal("victory_points_scored", active_player, actual_vp_earned, reason)

		print("MissionManager: Player %d scored %d VP (%s)" % [active_player, actual_vp_earned, reason])
		print("MissionManager: Player %d total VP: %d (Primary: %d)" %
			  [active_player, current_vp + actual_vp_earned, new_primary_vp])
	else:
		print("MissionManager: Player %d scored 0 VP" % active_player)

# ============================================================================
# KILL TRACKING — for Purge the Foe
# ============================================================================

## Call this when an enemy unit is destroyed during a battle round.
func record_unit_destroyed(destroyed_by_player: int) -> void:
	var player_key = str(destroyed_by_player)
	_kills_this_round[player_key] = _kills_this_round.get(player_key, 0) + 1
	print("MissionManager: Player %d destroyed a unit (total this round: %d)" % [destroyed_by_player, _kills_this_round[player_key]])

## Reset kill counts at the start of each battle round.
func reset_round_kills() -> void:
	_kills_this_round = {"1": 0, "2": 0}
	print("MissionManager: Reset round kill counts")

# ============================================================================
# ACCESSORS
# ============================================================================

func get_current_mission_id() -> String:
	return current_mission.get("id", "take_and_hold")

func get_current_mission_name() -> String:
	return current_mission.get("name", "Take and Hold")

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
