extends Node
const GameStateData = preload("res://autoloads/GameState.gd")

# MissionManager - Handles mission objectives, control, and victory point scoring
# Supports multiple primary missions via MissionData registry

signal objective_control_changed(objective_id: String, controller: int, old_controller: int)
signal victory_points_scored(player: int, points: int, reason: String)
signal objective_removed(objective_id: String)
signal objective_burned(objective_id: String, player: int)

var current_mission: Dictionary = {}
var objective_control_state: Dictionary = {} # objective_id -> controlling_player
var objectives_visual_refs: Dictionary = {} # Store references to visual nodes

# Sticky objective tracking — objectives locked by abilities like "Get Da Good Bitz" / "Objective Secured"
# Key: objective_id, Value: { "player": int, "source_unit_id": String }
var _sticky_objectives: Dictionary = {}

# Kill tracking for Purge the Foe
var _kills_this_round: Dictionary = {"1": 0, "2": 0}  # player_key -> units destroyed this round

# Burn tracking for Scorched Earth — objectives burned and removed from play
# Key: objective_id, Value: { "player": int, "unit_id": String, "zone": String }
var _burned_objectives: Dictionary = {}

# Units that have been designated to burn an objective this turn (Shooting phase)
# Key: unit_id, Value: objective_id — resolves at end of Command phase
var _pending_burns: Dictionary = {}

# Ritual action tracking for The Ritual mission
# Key: objective_id, Value: { "player": int, "unit_id": String, "round_created": int }
var _ritual_objectives: Dictionary = {}

# Units performing ritual actions this turn (Shooting phase)
# Key: unit_id, Value: objective_id — action completes at end of turn
var _pending_rituals: Dictionary = {}

# Terraform tracking — objectives that have been terraformed by a player
# Key: objective_id, Value: player (1 or 2) who terraformed it
var _terraformed_objectives: Dictionary = {}

# Units performing terraform actions this turn (Shooting phase)
# Key: unit_id, Value: objective_id — action completes at end of turn
var _pending_terraforms: Dictionary = {}

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

	# Reset burn tracking
	_burned_objectives.clear()
	_pending_burns.clear()

	# Reset ritual tracking
	_ritual_objectives.clear()
	_pending_rituals.clear()

	# Reset terraform tracking
	_terraformed_objectives.clear()
	_pending_terraforms.clear()

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
	_sticky_objectives.clear()
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
			emit_signal("objective_control_changed", obj.id, controller, old_controller)
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

			# A model is within range of an objective if any part of its base
			# is within the control radius. Use shape-aware distance to correctly
			# handle oval and rectangular bases (not just circular).
			var edge_distance = Measurement.model_edge_to_point_distance_px(model, obj_pos)
			var edge_distance_inches = Measurement.px_to_inches(edge_distance)

			# Debug log for each model checked
			print("  Model from %s at %s, edge_distance: %.1f\" (%.1fpx), control_radius: %.1fpx, base_type: %s from %s at %s" % [
				unit_id, model_pos, edge_distance_inches, edge_distance, control_radius, model.get("base_type", "circular"), objective.id, obj_pos
			])

			if edge_distance <= control_radius:
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

	# Determine controller based on OC
	var oc_controller = 0
	if player1_oc > player2_oc:
		oc_controller = 1
	elif player2_oc > player1_oc:
		oc_controller = 2

	# If a player actively controls via OC, that overrides any sticky lock
	# (opponent "controls it at the start or end of any turn" breaks sticky)
	if oc_controller > 0:
		# If the opponent now controls via OC, clear any sticky lock
		var obj_id = objective.get("id", "")
		if _sticky_objectives.has(obj_id) and _sticky_objectives[obj_id].player != oc_controller:
			print("MissionManager: Sticky lock on %s broken — Player %d now controls via OC" % [obj_id, oc_controller])
			_sticky_objectives.erase(obj_id)
		return oc_controller

	# No one has OC presence — check for sticky lock
	var obj_id = objective.get("id", "")
	if _sticky_objectives.has(obj_id):
		var sticky_data = _sticky_objectives[obj_id]
		var sticky_player = sticky_data.player
		var source_unit_id = sticky_data.source_unit_id

		# Verify the source unit is still alive on the battlefield
		var source_unit = GameState.state.get("units", {}).get(source_unit_id, {})
		var source_alive = false
		for model in source_unit.get("models", []):
			if model.get("alive", true):
				source_alive = true
				break

		if source_alive:
			print("MissionManager: %s remains under Player %d control via sticky objective (source: %s)" % [obj_id, sticky_player, source_unit_id])
			return sticky_player
		else:
			print("MissionManager: Sticky lock on %s expired — source unit %s is destroyed" % [obj_id, source_unit_id])
			_sticky_objectives.erase(obj_id)

	return 0  # Contested or uncontrolled

# ============================================================================
# STICKY OBJECTIVES — "Get Da Good Bitz", "Objective Secured", etc.
# ============================================================================
# At the end of the Command phase, if a unit with a sticky objective ability
# is within range of an objective marker you control, that objective remains
# under your control even if you have no models within range, until the
# opponent controls it at the start or end of any turn.

func apply_sticky_objectives(player: int) -> void:
	"""Called at end of Command phase. Locks objectives controlled by the player
	where a unit with a sticky objective ability is within range."""
	var objectives = GameState.state.board.get("objectives", [])
	var units = GameState.state.get("units", {})
	var control_radius = Measurement.inches_to_px(3.78740157)

	var unit_ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if not unit_ability_mgr:
		print("MissionManager: UnitAbilityManager not available — skipping sticky objectives")
		return

	for obj in objectives:
		var obj_id = obj.get("id", "")
		var controller = objective_control_state.get(obj_id, 0)

		# Only apply sticky to objectives the player currently controls
		if controller != player:
			continue

		# Check if any unit with sticky objective ability is within range
		for unit_id in units:
			var unit = units[unit_id]
			if unit.get("owner", 0) != player:
				continue

			# Check if unit has a sticky objective ability
			if not unit_ability_mgr.has_sticky_objectives_ability(unit_id):
				continue

			# Skip battle-shocked units (they don't contribute to OC or abilities)
			if unit.get("flags", {}).get("battle_shocked", false):
				continue

			# Check if any alive model is within range of the objective
			# (any part of the base overlapping counts — shape-aware for oval/rect bases)
			var unit_in_range = false
			for model in unit.get("models", []):
				if not model.get("alive", true):
					continue
				var model_pos = model.get("position")
				if model_pos == null:
					continue
				if model_pos is Dictionary:
					model_pos = Vector2(model_pos.x, model_pos.y)
				var edge_distance = Measurement.model_edge_to_point_distance_px(model, obj.position)
				if edge_distance <= control_radius:
					unit_in_range = true
					break

			if unit_in_range:
				_sticky_objectives[obj_id] = {"player": player, "source_unit_id": unit_id}
				var unit_name = unit.get("meta", {}).get("name", unit_id)
				print("MissionManager: Sticky objective — %s locked by %s (%s) for Player %d" % [obj_id, unit_name, unit_id, player])
				break  # Only need one qualifying unit per objective

func clear_sticky_objectives_for_player(player: int) -> void:
	"""Clear all sticky locks for a player. Called if needed for game reset."""
	var to_erase = []
	for obj_id in _sticky_objectives:
		if _sticky_objectives[obj_id].player == player:
			to_erase.append(obj_id)
	for obj_id in to_erase:
		_sticky_objectives.erase(obj_id)
	if to_erase.size() > 0:
		print("MissionManager: Cleared %d sticky objective(s) for Player %d" % [to_erase.size(), player])

func get_sticky_objectives() -> Dictionary:
	"""Get current sticky objective state (for save/load and debugging)."""
	return _sticky_objectives.duplicate(true)

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
			_score_hold_and_burn(active_player, battle_round)
		"ritual":
			_score_ritual(active_player, battle_round)
		"terraform":
			_score_terraform(active_player, battle_round)
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
			# (any part of the base overlapping counts — shape-aware for oval/rect bases)
			for model in unit.get("models", []):
				if not model.get("alive", true):
					continue
				var model_pos = model.get("position")
				if model_pos == null:
					continue
				if model_pos is Dictionary:
					model_pos = Vector2(model_pos.x, model_pos.y)
				var edge_distance = Measurement.model_edge_to_point_distance_px(model, obj_pos)
				if edge_distance <= control_radius:
					characters_on_nml += 1
					print("MissionManager: Sites of Power - Character %s on NML objective %s" % [unit_id, obj.id])
					break  # Only count this character once

	var vp_earned = mini(characters_on_nml * vp_per_char, max_per_turn)
	_apply_primary_vp(active_player, vp_earned, "%d characters on NML objectives" % characters_on_nml)

# ============================================================================
# SCORCHED EARTH — Hold objectives + burn NML/enemy objectives
# ============================================================================
# Rules: From round 2, during Shooting phase, a non-battle-shocked unit eligible
# to shoot can give up shooting and charging to burn a nearby objective the player
# controls. At the next Command phase, if the unit is still within range of that
# controlled objective, the objective is burned and removed.
#
# Per-turn scoring: 5 VP per controlled objective (max 10 VP per turn).
# End-of-battle bonus: +5 VP per burned NML objective, +10 VP per burned enemy DZ objective.

func _score_hold_and_burn(active_player: int, _battle_round: int) -> void:
	var scoring_rules = current_mission.get("scoring_rules", {})
	var vp_per_obj = scoring_rules.get("vp_per_objective", 5)
	var max_per_turn = scoring_rules.get("max_vp_per_turn", 10)

	# Count controlled objectives (excluding burned/removed ones)
	var controlled_objectives = []
	for obj_id in objective_control_state:
		if objective_control_state[obj_id] == active_player:
			controlled_objectives.append(obj_id)

	var controlled_count = controlled_objectives.size()

	if controlled_count > 0:
		print("MissionManager: Scorched Earth - Player %d controls %d objectives: %s" % [active_player, controlled_count, controlled_objectives])
	else:
		print("MissionManager: Scorched Earth - Player %d controls no objectives" % active_player)

	# Calculate VP from holding
	var vp_earned = mini(controlled_count * vp_per_obj, max_per_turn)

	_apply_primary_vp(active_player, vp_earned, "Scorched Earth: Controlled %d objectives" % controlled_count)

func is_scorched_earth_mission() -> bool:
	"""Check if the current mission uses burn mechanics."""
	return current_mission.get("scoring_type", "") == "hold_and_burn"

func get_burnable_objectives_for_unit(unit_id: String) -> Array:
	"""Get objectives that a unit can burn. Returns array of objective dictionaries.
	A unit can burn an objective if:
	- Current mission is Scorched Earth (hold_and_burn)
	- The objective is in NML or the ENEMY deployment zone (not the player's own DZ)
	- The objective is currently controlled by the unit's owner
	- The objective hasn't already been burned
	- The unit has a model within range of the objective (3" + marker radius)"""
	if not is_scorched_earth_mission():
		return []

	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return []

	var owner = unit.get("owner", 0)
	if owner == 0:
		return []

	# Determine which zones the player can burn (NML + enemy DZ)
	var enemy_zone = "player2" if owner == 1 else "player1"
	var burnable_zones = ["no_mans_land", enemy_zone]

	var objectives = GameState.state.board.get("objectives", [])
	var control_radius = Measurement.inches_to_px(3.78740157)
	var result = []

	for obj in objectives:
		var obj_id = obj.get("id", "")

		# Skip already burned objectives
		if _burned_objectives.has(obj_id):
			continue

		# Skip objectives not in burnable zones
		var zone = obj.get("zone", "")
		if zone not in burnable_zones:
			continue

		# Must be controlled by the unit's owner
		if objective_control_state.get(obj_id, 0) != owner:
			continue

		# Check if any alive model is within range
		var obj_pos = obj.get("position", Vector2.ZERO)
		var unit_in_range = false
		for model in unit.get("models", []):
			if not model.get("alive", true):
				continue
			var model_pos = model.get("position")
			if model_pos == null:
				continue
			if model_pos is Dictionary:
				model_pos = Vector2(model_pos.x, model_pos.y)
			var edge_distance = Measurement.model_edge_to_point_distance_px(model, obj_pos)
			if edge_distance <= control_radius:
				unit_in_range = true
				break

		if unit_in_range:
			# Determine VP value for burning this objective
			var burn_vp = 0
			if zone == "no_mans_land":
				burn_vp = current_mission.get("scoring_rules", {}).get("burn_nml_vp", 5)
			else:
				burn_vp = current_mission.get("scoring_rules", {}).get("burn_enemy_vp", 10)

			result.append({
				"objective_id": obj_id,
				"zone": zone,
				"burn_vp": burn_vp,
				"position": obj_pos,
			})

	return result

func register_burn_action(unit_id: String, objective_id: String) -> bool:
	"""Register a unit's intent to burn an objective (during Shooting phase).
	The unit gives up shooting and charging. The burn resolves at end-of-Command.
	For simplicity, we resolve the burn immediately since the Shooting phase
	already validates proximity and control."""
	if not is_scorched_earth_mission():
		print("MissionManager: Cannot burn — not a Scorched Earth mission")
		return false

	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		print("MissionManager: Cannot burn — unit %s not found" % unit_id)
		return false

	var owner = unit.get("owner", 0)
	var unit_name = unit.get("meta", {}).get("name", unit_id)

	# Verify objective is burnable
	var burnable = get_burnable_objectives_for_unit(unit_id)
	var target_obj = null
	for b in burnable:
		if b.objective_id == objective_id:
			target_obj = b
			break

	if target_obj == null:
		print("MissionManager: Cannot burn — %s is not a valid burn target for %s" % [objective_id, unit_id])
		return false

	# Record the burn
	_burned_objectives[objective_id] = {
		"player": owner,
		"unit_id": unit_id,
		"zone": target_obj.zone,
	}

	print("MissionManager: OBJECTIVE BURNED — %s burned %s (%s zone) for Player %d" % [
		unit_name, objective_id, target_obj.zone, owner])

	# Remove the objective from the board
	var objectives = GameState.state.board.get("objectives", [])
	for i in range(objectives.size()):
		if objectives[i].get("id", "") == objective_id:
			objectives.remove_at(i)
			break

	# Remove from control state
	objective_control_state.erase(objective_id)

	# Remove any sticky lock
	_sticky_objectives.erase(objective_id)

	emit_signal("objective_burned", objective_id, owner)
	emit_signal("objective_removed", objective_id)

	return true

func score_end_of_game_burn_bonus() -> void:
	"""Score end-of-battle burn bonuses for Scorched Earth.
	Called at end of battle round 5 (or whenever the game ends).
	+5 VP per burned NML objective, +10 VP per burned enemy DZ objective."""
	if not is_scorched_earth_mission():
		return

	var scoring_rules = current_mission.get("scoring_rules", {})
	var burn_nml_vp = scoring_rules.get("burn_nml_vp", 5)
	var burn_enemy_vp = scoring_rules.get("burn_enemy_vp", 10)

	# Tally burn bonuses per player
	var player_burn_vp = {1: 0, 2: 0}
	var player_burn_reasons = {1: [], 2: []}

	for obj_id in _burned_objectives:
		var burn_data = _burned_objectives[obj_id]
		var player = burn_data.player
		var zone = burn_data.zone

		if zone == "no_mans_land":
			player_burn_vp[player] += burn_nml_vp
			player_burn_reasons[player].append("%s (NML +%d)" % [obj_id, burn_nml_vp])
		else:
			# Enemy deployment zone objective
			player_burn_vp[player] += burn_enemy_vp
			player_burn_reasons[player].append("%s (Enemy DZ +%d)" % [obj_id, burn_enemy_vp])

	for player in [1, 2]:
		if player_burn_vp[player] > 0:
			var reason = "Burn bonus: " + ", ".join(player_burn_reasons[player])
			_apply_primary_vp(player, player_burn_vp[player], reason)
			print("MissionManager: Scorched Earth end-of-game burn bonus — Player %d: +%d VP (%s)" % [
				player, player_burn_vp[player], reason])

func get_burned_objectives() -> Dictionary:
	"""Get current burned objectives state (for save/load and debugging)."""
	return _burned_objectives.duplicate(true)

# ============================================================================
# THE RITUAL — Action-based objective scoring
# ============================================================================
# Rules (Chapter Approved 2025-26): All NML objectives remain on board. During
# a player's Shooting phase, a unit can perform a ritual action (giving up
# shooting and charging). At end of turn, if the unit is still eligible, a new
# objective marker is placed wholly within NML, within 1" of the unit, exactly
# 12" from one existing NML objective, and not within 6" of any other objective.
#
# Scoring: From round 2, at start of Command phase, 5 VP per controlled NML
# objective (max 15 VP per turn). For simplicity, we score all NML objectives
# the player controls (including any created by ritual actions).
#
# Since we don't have visual placement of new objectives on the board, the
# ritual action instead creates a new objective at a valid position near the
# acting unit (auto-placed), following the distance rules as closely as
# possible given the grid/board state.

func is_ritual_mission() -> bool:
	"""Check if the current mission uses ritual action mechanics."""
	return current_mission.get("scoring_type", "") == "ritual"

func _score_ritual(active_player: int, _battle_round: int) -> void:
	"""Score The Ritual: 5 VP per controlled NML objective (max 15 VP per turn)."""
	var scoring_rules = current_mission.get("scoring_rules", {})
	var vp_per_obj = scoring_rules.get("vp_per_nml_objective", 5)
	var max_per_turn = scoring_rules.get("max_vp_per_turn", 15)

	# Count controlled NML objectives (including ritual-created ones)
	var controlled_nml = []
	var objectives = GameState.state.board.get("objectives", [])
	for obj in objectives:
		var zone = obj.get("zone", "")
		if zone == "no_mans_land" and objective_control_state.get(obj.id, 0) == active_player:
			controlled_nml.append(obj.id)

	var controlled_count = controlled_nml.size()

	if controlled_count > 0:
		print("MissionManager: The Ritual - Player %d controls %d NML objectives: %s" % [active_player, controlled_count, controlled_nml])
	else:
		print("MissionManager: The Ritual - Player %d controls no NML objectives" % active_player)

	var vp_earned = mini(controlled_count * vp_per_obj, max_per_turn)
	_apply_primary_vp(active_player, vp_earned, "The Ritual: Controlled %d NML objectives" % controlled_count)

func get_ritual_objectives_for_unit(unit_id: String) -> Array:
	"""Get objectives where a unit can perform a ritual action. Returns array of
	objective dictionaries with position and id.
	A unit can perform a ritual action if:
	- Current mission is The Ritual
	- The unit has a model within range of a controlled NML objective
	- The unit is not battle-shocked
	- The unit has OC > 0
	- The unit is not an Aircraft"""
	if not is_ritual_mission():
		return []

	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return []

	var owner = unit.get("owner", 0)
	if owner == 0:
		return []

	# Units must have OC > 0 to perform actions
	var oc_value = unit.get("meta", {}).get("stats", {}).get("objective_control", 0)
	if oc_value <= 0:
		return []

	# Aircraft cannot perform actions
	var keywords = unit.get("meta", {}).get("keywords", [])
	if "AIRCRAFT" in keywords:
		return []

	var objectives = GameState.state.board.get("objectives", [])
	var control_radius = Measurement.inches_to_px(3.78740157)
	var result = []

	for obj in objectives:
		var obj_id = obj.get("id", "")
		var zone = obj.get("zone", "")

		# Ritual actions are performed at NML objectives the player controls
		if zone != "no_mans_land":
			continue

		if objective_control_state.get(obj_id, 0) != owner:
			continue

		# Check if any alive model is within range
		var obj_pos = obj.get("position", Vector2.ZERO)
		var unit_in_range = false
		for model in unit.get("models", []):
			if not model.get("alive", true):
				continue
			var model_pos = model.get("position")
			if model_pos == null:
				continue
			if model_pos is Dictionary:
				model_pos = Vector2(model_pos.x, model_pos.y)
			var edge_distance = Measurement.model_edge_to_point_distance_px(model, obj_pos)
			if edge_distance <= control_radius:
				unit_in_range = true
				break

		if unit_in_range:
			result.append({
				"objective_id": obj_id,
				"position": obj_pos,
			})

	return result

func register_ritual_action(unit_id: String, objective_id: String) -> bool:
	"""Register a unit performing a ritual action at an objective (during Shooting phase).
	The unit gives up shooting and charging. On completion, a new objective marker
	is placed near the unit in NML (auto-placed following distance rules).
	For simplicity, the new objective is placed immediately."""
	if not is_ritual_mission():
		print("MissionManager: Cannot perform ritual — not The Ritual mission")
		return false

	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		print("MissionManager: Cannot perform ritual — unit %s not found" % unit_id)
		return false

	var owner = unit.get("owner", 0)
	var unit_name = unit.get("meta", {}).get("name", unit_id)

	# Verify objective is valid for ritual
	var valid_objectives = get_ritual_objectives_for_unit(unit_id)
	var target_obj = null
	for v in valid_objectives:
		if v.objective_id == objective_id:
			target_obj = v
			break

	if target_obj == null:
		print("MissionManager: Cannot perform ritual — %s is not a valid ritual target for %s" % [objective_id, unit_id])
		return false

	# Try to place a new objective near the unit
	var new_obj = _try_place_ritual_objective(unit, target_obj)
	if new_obj != null:
		# Add the new objective to the board
		var objectives = GameState.state.board.get("objectives", [])
		objectives.append(new_obj)
		objective_control_state[new_obj.id] = owner  # New objective starts controlled by creator

		_ritual_objectives[new_obj.id] = {
			"player": owner,
			"unit_id": unit_id,
			"round_created": GameState.get_battle_round(),
		}

		print("MissionManager: RITUAL COMPLETE — %s created new objective %s at %s for Player %d" % [
			unit_name, new_obj.id, new_obj.position, owner])
	else:
		# No valid placement found — the ritual still completes (unit sacrificed shooting)
		# but no new objective is created (board is too crowded)
		print("MissionManager: RITUAL — %s performed ritual at %s but no valid placement found for new objective" % [
			unit_name, objective_id])

	return true

func _try_place_ritual_objective(unit: Dictionary, source_obj: Dictionary) -> Variant:
	"""Try to find a valid position for a new ritual objective.
	Rules: Must be wholly within NML, within 1" of the unit, 12" from one
	existing NML objective, and not within 6" of any other objective.
	Returns objective dict or null if no valid position found."""
	var objectives = GameState.state.board.get("objectives", [])

	# Collect NML objective positions for distance checks
	var nml_obj_positions = []
	var all_obj_positions = []
	for obj in objectives:
		var pos = obj.get("position", Vector2.ZERO)
		if pos is Dictionary:
			pos = Vector2(pos.x, pos.y)
		all_obj_positions.append(pos)
		if obj.get("zone", "") == "no_mans_land":
			nml_obj_positions.append(pos)

	# Get unit model positions to find placement near unit
	var model_positions = []
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		var pos = model.get("position")
		if pos == null:
			continue
		if pos is Dictionary:
			pos = Vector2(pos.x, pos.y)
		model_positions.append(pos)

	if model_positions.is_empty():
		return null

	# Use the first alive model position as reference
	var ref_pos = model_positions[0]

	# Distance constants in pixels
	var distance_12 = Measurement.inches_to_px(12.0)
	var distance_6 = Measurement.inches_to_px(6.0)
	var distance_1 = Measurement.inches_to_px(1.0)

	# Get NML zone boundaries (approximate using board dimensions)
	# NML is roughly the middle third of the board in standard deployments
	var board_width_px = Measurement.inches_to_px(GameState.state.get("board", {}).get("size", {}).get("width", 44))
	var board_height_px = Measurement.inches_to_px(GameState.state.get("board", {}).get("size", {}).get("height", 60))

	# Try angles around the reference position to find a valid spot
	# The new objective should be ~12" from an existing NML objective
	for nml_pos in nml_obj_positions:
		# Try placing at 12" from this NML objective, near the unit
		var dir_to_unit = (ref_pos - nml_pos).normalized()
		if dir_to_unit.length() < 0.01:
			dir_to_unit = Vector2(1, 0)  # Default direction if positions overlap

		# Try the direction toward the unit first, then rotate around
		for angle_offset in [0, 15, -15, 30, -30, 45, -45, 60, -60, 90, -90]:
			var angle_rad = deg_to_rad(angle_offset)
			var rotated_dir = dir_to_unit.rotated(angle_rad)
			var candidate_pos = nml_pos + rotated_dir * distance_12

			# Check: must be within 1" of a model
			var near_model = false
			for mpos in model_positions:
				if candidate_pos.distance_to(mpos) <= distance_1 + Measurement.inches_to_px(2.0):
					# Allow a bit more flexibility (within ~3" of model) for practical placement
					near_model = true
					break

			if not near_model:
				continue

			# Check: must be on the board
			if candidate_pos.x < 0 or candidate_pos.x > board_width_px:
				continue
			if candidate_pos.y < 0 or candidate_pos.y > board_height_px:
				continue

			# Check: must not be within 6" of any OTHER objective
			var too_close = false
			for obj_pos in all_obj_positions:
				if candidate_pos.distance_to(obj_pos) < distance_6:
					# Allow being exactly 12" from the source NML objective
					if candidate_pos.distance_to(obj_pos) > distance_12 - Measurement.inches_to_px(0.5) and candidate_pos.distance_to(obj_pos) < distance_12 + Measurement.inches_to_px(0.5):
						continue  # This is the 12" placement target, not a violation
					too_close = true
					break

			if too_close:
				continue

			# Valid placement found! Create the objective
			var new_id = "ritual_obj_%d_%d" % [unit.get("owner", 0), _ritual_objectives.size() + 1]
			return {
				"id": new_id,
				"position": candidate_pos,
				"zone": "no_mans_land",
				"radius_mm": 40,
				"ritual_created": true,
			}

	# No valid position found
	print("MissionManager: No valid position for ritual objective (board too crowded)")
	return null

func get_ritual_objectives() -> Dictionary:
	"""Get current ritual objectives state (for save/load and debugging)."""
	return _ritual_objectives.duplicate(true)

func clear_pending_rituals() -> void:
	"""Clear pending ritual actions at start of a new turn."""
	_pending_rituals.clear()

# ============================================================================
# TERRAFORM — Objective flipping mission
# ============================================================================
# Rules (Chapter Approved 2025-26): During the Shooting phase, a unit can
# perform the Terraform action on an objective it controls that is NOT in
# the player's own deployment zone. The unit gives up shooting and charging.
# At end of turn, if the unit is still within range and the player still
# controls the objective, the objective is "terraformed by" that player.
# If the opponent had already terraformed it, their terraform is removed
# and the new player's terraform replaces it (flip mechanic).
#
# Scoring (from round 2): At end of Command phase, each player scores
# 4 VP per controlled objective (max 12 VP). Additionally, each player
# scores 1 VP per objective they have terraformed.

func is_terraform_mission() -> bool:
	"""Check if the current mission uses terraform/flip mechanics."""
	return current_mission.get("scoring_type", "") == "terraform"

func _score_terraform(active_player: int, _battle_round: int) -> void:
	"""Score Terraform mission: 4 VP per controlled objective (max 12),
	plus 1 VP per terraformed objective."""
	var scoring_rules = current_mission.get("scoring_rules", {})
	var vp_per_obj = scoring_rules.get("vp_per_controlled", 4)
	var max_control_vp = scoring_rules.get("max_control_vp_per_turn", 12)
	var vp_per_terraform = scoring_rules.get("vp_per_terraformed", 1)
	var max_per_turn = scoring_rules.get("max_vp_per_turn", 15)

	# Count controlled objectives
	var controlled_objectives = []
	for obj_id in objective_control_state:
		if objective_control_state[obj_id] == active_player:
			controlled_objectives.append(obj_id)

	var controlled_count = controlled_objectives.size()
	var control_vp = mini(controlled_count * vp_per_obj, max_control_vp)

	# Count terraformed objectives (these score regardless of current control)
	var terraform_count = 0
	for obj_id in _terraformed_objectives:
		if _terraformed_objectives[obj_id] == active_player:
			terraform_count += 1
	var terraform_vp = terraform_count * vp_per_terraform

	var total_vp = mini(control_vp + terraform_vp, max_per_turn)

	if controlled_count > 0 or terraform_count > 0:
		print("MissionManager: Terraform - Player %d controls %d objectives (+%d VP), has %d terraformed (+%d VP)" % [
			active_player, controlled_count, control_vp, terraform_count, terraform_vp])
	else:
		print("MissionManager: Terraform - Player %d controls no objectives and has no terraformed objectives" % active_player)

	var reason = "Terraform: %d controlled (+%d VP), %d terraformed (+%d VP)" % [
		controlled_count, control_vp, terraform_count, terraform_vp]
	_apply_primary_vp(active_player, total_vp, reason)

func get_terraformable_objectives_for_unit(unit_id: String) -> Array:
	"""Get objectives that a unit can terraform. Returns array of objective dicts.
	A unit can terraform an objective if:
	- Current mission is Terraform
	- The objective is NOT in the unit owner's deployment zone
	- The objective is currently controlled by the unit's owner
	- The unit has a model within range of the objective (3" + marker radius)
	- The objective hasn't already been terraformed by this player"""
	if not is_terraform_mission():
		return []

	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return []

	var owner = unit.get("owner", 0)
	if owner == 0:
		return []

	# Units must have OC > 0 to perform actions
	var oc_value = unit.get("meta", {}).get("stats", {}).get("objective_control", 0)
	if oc_value <= 0:
		return []

	# Aircraft cannot perform actions
	var keywords = unit.get("meta", {}).get("keywords", [])
	if "AIRCRAFT" in keywords:
		return []

	# Determine which zone is the player's OWN deployment zone (cannot terraform there)
	var own_zone = "player1" if owner == 1 else "player2"

	var objectives = GameState.state.board.get("objectives", [])
	var control_radius = Measurement.inches_to_px(3.78740157)
	var result = []

	for obj in objectives:
		var obj_id = obj.get("id", "")
		var zone = obj.get("zone", "")

		# Cannot terraform objectives in your own deployment zone
		if zone == own_zone:
			continue

		# Must be controlled by the unit's owner
		if objective_control_state.get(obj_id, 0) != owner:
			continue

		# Skip objectives already terraformed by this player
		if _terraformed_objectives.get(obj_id, 0) == owner:
			continue

		# Check if any alive model is within range
		var obj_pos = obj.get("position", Vector2.ZERO)
		var unit_in_range = false
		for model in unit.get("models", []):
			if not model.get("alive", true):
				continue
			var model_pos = model.get("position")
			if model_pos == null:
				continue
			if model_pos is Dictionary:
				model_pos = Vector2(model_pos.x, model_pos.y)
			var edge_distance = Measurement.model_edge_to_point_distance_px(model, obj_pos)
			if edge_distance <= control_radius:
				unit_in_range = true
				break

		if unit_in_range:
			var is_opponent_terraformed = _terraformed_objectives.get(obj_id, 0) != 0 and _terraformed_objectives[obj_id] != owner
			result.append({
				"objective_id": obj_id,
				"zone": zone,
				"position": obj_pos,
				"is_flip": is_opponent_terraformed,
			})

	return result

func register_terraform_action(unit_id: String, objective_id: String) -> bool:
	"""Register a unit performing a terraform action at an objective (during Shooting phase).
	The unit gives up shooting and charging. The terraform resolves immediately
	for simplicity (same pattern as burn/ritual)."""
	if not is_terraform_mission():
		print("MissionManager: Cannot terraform — not a Terraform mission")
		return false

	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		print("MissionManager: Cannot terraform — unit %s not found" % unit_id)
		return false

	var owner = unit.get("owner", 0)
	var unit_name = unit.get("meta", {}).get("name", unit_id)

	# Verify objective is valid for terraforming
	var valid_targets = get_terraformable_objectives_for_unit(unit_id)
	var target_obj = null
	for v in valid_targets:
		if v.objective_id == objective_id:
			target_obj = v
			break

	if target_obj == null:
		print("MissionManager: Cannot terraform — %s is not a valid terraform target for %s" % [objective_id, unit_id])
		return false

	# Check if opponent had terraformed this objective (flip)
	var old_owner = _terraformed_objectives.get(objective_id, 0)
	if old_owner > 0 and old_owner != owner:
		print("MissionManager: TERRAFORM FLIP — %s flips %s from Player %d to Player %d" % [
			unit_name, objective_id, old_owner, owner])
	else:
		print("MissionManager: TERRAFORM — %s terraforms %s for Player %d" % [
			unit_name, objective_id, owner])

	# Set the terraform state (replaces any previous terraform by opponent)
	_terraformed_objectives[objective_id] = owner

	return true

func get_terraformed_objectives() -> Dictionary:
	"""Get current terraformed objectives state (for save/load and debugging)."""
	return _terraformed_objectives.duplicate(true)

func clear_pending_terraforms() -> void:
	"""Clear pending terraform actions at start of a new turn."""
	_pending_terraforms.clear()

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
