extends Node

const SecondaryMissionData = preload("res://scripts/data/SecondaryMissionData.gd")
const GameStateData = preload("res://autoloads/GameState.gd")

# SecondaryMissionManager - Manages the secondary mission system for Chapter Approved 2025-26
# Handles deck building, card drawing, discarding, scoring, and VP tracking
# Currently implements Tactical Missions mode only.

signal mission_drawn(player: int, mission_id: String)
signal mission_achieved(player: int, mission_id: String, vp_earned: int)
signal mission_discarded(player: int, mission_id: String, reason: String)
signal secondary_vp_scored(player: int, vp: int, mission_id: String)
signal deck_depleted(player: int)
signal when_drawn_requires_interaction(player: int, mission_id: String, interaction_type: String, details: Dictionary)

# VP caps per Chapter Approved 2025-26
const MAX_SECONDARY_VP = 40
const MAX_COMBINED_VP = 90  # primary + secondary + challenger combined
const MAX_ACTIVE_MISSIONS = 2

# Per-player secondary mission state
var _player_state: Dictionary = {
	"1": _create_default_player_state(),
	"2": _create_default_player_state(),
}

# Tracks units destroyed this turn for kill-based missions
var _units_destroyed_this_turn: Array = []

# Tracks objective control at start of turn for objective-based missions
var _objective_control_at_turn_start: Dictionary = {}

# Tracks actions being performed for action-based missions
var _active_actions: Dictionary = {
	"1": [],  # Array of ongoing action dicts
	"2": [],
}

# Track "while_active" VP accumulated per card this scoring window
var _while_active_vp_this_window: Dictionary = {}

var _rng: RandomNumberGenerator

func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.randomize()
	print("SecondaryMissionManager: Initialized")

static func _create_default_player_state() -> Dictionary:
	return {
		"mode": "tactical",  # "tactical" or "fixed"
		"deck": [],          # Array of mission IDs (shuffled for tactical)
		"active": [],        # Array of active mission dicts (max 2)
		"discard": [],       # Array of discarded mission IDs
		"secondary_vp": 0,   # Total secondary VP scored
		"initialized": false,
	}

# ============================================================================
# INITIALIZATION
# ============================================================================

func initialize_for_game() -> void:
	"""Initialize secondary missions for both players at game start."""
	_player_state = {
		"1": _create_default_player_state(),
		"2": _create_default_player_state(),
	}
	_units_destroyed_this_turn.clear()
	_objective_control_at_turn_start.clear()
	_active_actions = {"1": [], "2": []}
	_while_active_vp_this_window.clear()
	print("SecondaryMissionManager: Reset for new game")

func setup_tactical_deck(player: int) -> void:
	"""Build and shuffle a tactical mission deck for the specified player."""
	var player_key = str(player)
	var state = _player_state[player_key]

	# Get standard 18-card tactical deck
	var deck_ids = SecondaryMissionData.get_mission_ids_for_deck(false)

	# Shuffle
	_shuffle_array(deck_ids)

	state["deck"] = deck_ids
	state["mode"] = "tactical"
	state["active"] = []
	state["discard"] = []
	state["secondary_vp"] = 0
	state["initialized"] = true

	print("SecondaryMissionManager: Built tactical deck for Player %d (%d cards)" % [player, deck_ids.size()])

# ============================================================================
# CARD DRAWING
# ============================================================================

func draw_missions_to_hand(player: int) -> Array:
	"""
	Draw cards until player has MAX_ACTIVE_MISSIONS active cards.
	Returns array of newly drawn mission dicts.
	Called at the start of Command Phase.
	"""
	var player_key = str(player)
	var state = _player_state[player_key]

	if not state["initialized"]:
		push_warning("SecondaryMissionManager: Player %d deck not initialized" % player)
		return []

	var drawn = []
	while state["active"].size() < MAX_ACTIVE_MISSIONS and state["deck"].size() > 0:
		var mission_id = state["deck"].pop_front()
		var mission_data = SecondaryMissionData.get_mission_by_id(mission_id)

		if mission_data.is_empty():
			push_warning("SecondaryMissionManager: Unknown mission ID in deck: %s" % mission_id)
			continue

		# Check "When Drawn" conditions
		var when_drawn_result = _handle_when_drawn(player, mission_data)

		if when_drawn_result["action"] == "shuffle_back":
			# Put it back in the deck and shuffle
			state["deck"].append(mission_id)
			_shuffle_array(state["deck"])
			print("SecondaryMissionManager: Player %d shuffled %s back into deck" % [player, mission_data["name"]])
			# Draw another card instead
			continue
		elif when_drawn_result["action"] == "discard_and_draw":
			# Discard it and draw a new one
			state["discard"].append(mission_id)
			print("SecondaryMissionManager: Player %d discarded %s (when drawn condition)" % [player, mission_data["name"]])
			emit_signal("mission_discarded", player, mission_id, "when_drawn_condition")
			continue
		elif when_drawn_result["action"] == "requires_interaction":
			# Card needs opponent interaction before it can be fully activated
			# Add to active but mark as pending interaction
			var active_mission = _create_active_mission(mission_data)
			active_mission["pending_interaction"] = true
			active_mission["interaction_type"] = when_drawn_result.get("interaction_type", "")
			active_mission["interaction_details"] = when_drawn_result.get("details", {})
			state["active"].append(active_mission)
			drawn.append(active_mission)
			emit_signal("mission_drawn", player, mission_id)
			emit_signal("when_drawn_requires_interaction", player, mission_id,
				active_mission["interaction_type"], active_mission["interaction_details"])
			print("SecondaryMissionManager: Player %d drew %s (requires interaction)" % [player, mission_data["name"]])
			continue

		# Normal draw - add to active missions
		var active_mission = _create_active_mission(mission_data)
		state["active"].append(active_mission)
		drawn.append(active_mission)
		emit_signal("mission_drawn", player, mission_id)
		print("SecondaryMissionManager: Player %d drew %s" % [player, mission_data["name"]])

	if state["deck"].size() == 0 and state["active"].size() < MAX_ACTIVE_MISSIONS:
		emit_signal("deck_depleted", player)
		print("SecondaryMissionManager: Player %d deck is depleted!" % player)

	return drawn

func _handle_when_drawn(player: int, mission_data: Dictionary) -> Dictionary:
	"""Process when-drawn conditions. Returns action to take."""
	var when_drawn = mission_data.get("when_drawn", {})
	if when_drawn.is_empty():
		return {"action": "add_to_active"}

	var condition = when_drawn.get("condition", "")
	var effect = when_drawn.get("effect", "")
	var battle_round = GameState.get_battle_round()

	match condition:
		"first_battle_round":
			if battle_round == 1:
				if effect == SecondaryMissionData.EFFECT_MANDATORY_SHUFFLE_BACK:
					return {"action": "shuffle_back"}
				elif effect == SecondaryMissionData.EFFECT_SHUFFLE_BACK:
					# Optional shuffle back - for now, auto-shuffle back in round 1
					# TODO: Could add UI choice here
					return {"action": "shuffle_back"}
			return {"action": "add_to_active"}

		"no_enemy_infantry_starting_strength_13_plus":
			if not _has_enemy_infantry_13_plus(player):
				return {"action": "discard_and_draw"}
			return {"action": "add_to_active"}

		"no_enemy_monster_or_vehicle":
			if not _has_enemy_monster_or_vehicle(player):
				return {"action": "discard_and_draw"}
			return {"action": "add_to_active"}

		"fewer_than_3_units_or_incursion":
			if _count_player_units_on_battlefield(player) < 3:
				return {"action": "discard_and_draw"}
			return {"action": "add_to_active"}

		"opponent_selects_units":
			# Marked for Death - needs opponent interaction
			var opponent = 2 if player == 1 else 1
			var opponent_units = _get_opponent_units_on_battlefield(player)
			if opponent_units.size() == 0:
				return {"action": "discard_and_draw"}
			return {
				"action": "requires_interaction",
				"interaction_type": "opponent_selects_units",
				"details": when_drawn.get("details", {}),
			}

		"opponent_selects_objective":
			# A Tempting Target - opponent picks an objective in NML
			return {
				"action": "requires_interaction",
				"interaction_type": "opponent_selects_objective",
				"details": when_drawn.get("details", {}),
			}

	return {"action": "add_to_active"}

func _create_active_mission(mission_data: Dictionary) -> Dictionary:
	"""Create an active mission instance from mission data."""
	return {
		"id": mission_data["id"],
		"name": mission_data["name"],
		"number": mission_data["number"],
		"category": mission_data["category"],
		"scoring": mission_data["scoring"],
		"requires_action": mission_data["requires_action"],
		"action": mission_data["action"],
		"vp_scored": 0,  # VP scored from this specific card instance
		"achieved": false,
		"pending_interaction": false,
		"interaction_type": "",
		"interaction_details": {},
		# Mission-specific tracking
		"mission_data": {},  # e.g., alpha/gamma targets for Marked for Death
	}

# ============================================================================
# NEW ORDERS STRATAGEM
# ============================================================================

func use_new_orders(player: int, mission_index: int) -> Dictionary:
	"""
	Discard one active mission and draw a new one (New Orders stratagem).
	CP deduction is handled by StratagemManager (called by CommandPhase before this).
	mission_index: 0 or 1 (which active mission to discard)
	Returns result dict.
	"""
	var player_key = str(player)
	var state = _player_state[player_key]

	if mission_index < 0 or mission_index >= state["active"].size():
		return {"success": false, "error": "Invalid mission index"}

	if state["deck"].size() == 0:
		return {"success": false, "error": "Deck is empty, cannot draw replacement"}

	# Discard the selected mission
	var discarded = state["active"][mission_index]
	state["active"].remove_at(mission_index)
	state["discard"].append(discarded["id"])
	emit_signal("mission_discarded", player, discarded["id"], "new_orders")
	print("SecondaryMissionManager: Player %d used New Orders to discard %s" % [player, discarded["name"]])

	# Draw a replacement
	var drawn = draw_missions_to_hand(player)

	return {
		"success": true,
		"discarded": discarded["name"],
		"drawn": drawn[0]["name"] if drawn.size() > 0 else "none (deck depleted)",
	}

# ============================================================================
# VOLUNTARY DISCARD
# ============================================================================

func voluntary_discard(player: int, mission_index: int) -> Dictionary:
	"""
	Voluntarily discard an active mission at end of turn.
	If it's the player's turn, they gain 1 CP.
	"""
	var player_key = str(player)
	var state = _player_state[player_key]

	if mission_index < 0 or mission_index >= state["active"].size():
		return {"success": false, "error": "Invalid mission index"}

	var discarded = state["active"][mission_index]
	state["active"].remove_at(mission_index)
	state["discard"].append(discarded["id"])

	# Grant 1 CP if it's the player's turn
	var cp_gained = 0
	if GameState.get_active_player() == player:
		var current_cp = GameState.state.get("players", {}).get(str(player), {}).get("cp", 0)
		var changes = [{
			"op": "set",
			"path": "players.%s.cp" % str(player),
			"value": current_cp + 1,
		}]
		PhaseManager.apply_state_changes(changes)
		cp_gained = 1
		print("SecondaryMissionManager: Player %d gained 1 CP for voluntary discard" % player)

	emit_signal("mission_discarded", player, discarded["id"], "voluntary")
	print("SecondaryMissionManager: Player %d voluntarily discarded %s" % [player, discarded["name"]])

	return {
		"success": true,
		"discarded": discarded["name"],
		"cp_gained": cp_gained,
	}

# ============================================================================
# SCORING
# ============================================================================

func score_secondary_missions_for_player(player: int) -> Array:
	"""
	Evaluate and score all active secondary missions for a player.
	Called at end of player's turn (for end_of_your_turn missions)
	or at end of either player's turn (for end_of_either_turn missions).
	Returns array of scoring results.
	"""
	var player_key = str(player)
	var state = _player_state[player_key]
	var results = []
	var active_player = GameState.get_active_player()
	var battle_round = GameState.get_battle_round()

	for i in range(state["active"].size() - 1, -1, -1):
		var mission = state["active"][i]

		# Skip missions pending interaction
		if mission.get("pending_interaction", false):
			continue

		var scoring = mission["scoring"]
		var when = scoring.get("when", "")

		# Check timing
		var should_score = false
		match when:
			SecondaryMissionData.TIMING_END_OF_YOUR_TURN:
				should_score = (active_player == player)
			SecondaryMissionData.TIMING_END_OF_EITHER_TURN:
				should_score = true
			SecondaryMissionData.TIMING_END_OF_OPPONENT_TURN:
				should_score = (active_player != player)
			SecondaryMissionData.TIMING_WHILE_ACTIVE:
				# While-active missions are scored via events (unit destruction etc.)
				# At end of turn we just finalize the accumulated VP
				should_score = false

		if not should_score:
			continue

		# Check min round
		if battle_round < scoring.get("min_round", 1):
			continue

		# Evaluate conditions (highest matching VP wins)
		var vp_earned = _evaluate_mission_conditions(player, mission)

		if vp_earned > 0:
			var actual_vp = _award_secondary_vp(player, vp_earned, mission["id"])
			if actual_vp > 0:
				mission["vp_scored"] += actual_vp
				mission["achieved"] = true
				results.append({
					"mission_id": mission["id"],
					"mission_name": mission["name"],
					"vp_earned": actual_vp,
				})
				emit_signal("secondary_vp_scored", player, actual_vp, mission["id"])
				emit_signal("mission_achieved", player, mission["id"], actual_vp)
				print("SecondaryMissionManager: Player %d scored %d VP from %s" % [player, actual_vp, mission["name"]])

	# Discard achieved missions
	_discard_achieved_missions(player)

	return results

func _evaluate_mission_conditions(player: int, mission: Dictionary) -> int:
	"""
	Evaluate the scoring conditions for a mission.
	Returns the VP to award (highest matching condition).
	Conditions are evaluated from last to first (highest VP first).
	"""
	var scoring = mission["scoring"]
	var conditions = scoring.get("conditions", [])

	# Evaluate from highest VP to lowest - first match wins
	var sorted_conditions = conditions.duplicate()
	sorted_conditions.sort_custom(func(a, b): return a.get("vp", 0) > b.get("vp", 0))

	for condition in sorted_conditions:
		var check = condition.get("check", "")
		var params = condition.get("params", {})
		var vp = condition.get("vp", 0)

		if _check_condition(player, check, params, mission):
			return vp

	return 0

func _check_condition(player: int, check: String, params: Dictionary, mission: Dictionary) -> bool:
	"""Route to the appropriate condition checker."""
	match check:
		# Positional checks
		"units_wholly_in_opponent_deployment_zone":
			return _check_units_in_opponent_zone(player, params)
		"presence_in_table_quarters":
			return _check_table_quarter_presence(player, params)
		"units_within_center_no_enemies_within":
			return _check_area_denial(player, params)
		"more_units_wholly_in_no_mans_land_than_opponent":
			return _check_display_of_might(player)

		# Objective control checks
		"control_objectives_opponent_controlled_at_start":
			return _check_storm_hostile_objective(player, params)
		"opponent_controlled_no_objectives_at_start_and_you_control_new":
			return _check_storm_hostile_alt(player, params)
		"control_objectives_in_own_deployment_zone":
			return _check_own_zone_objectives(player, params)
		"control_objectives_in_no_mans_land":
			return _check_nml_objectives(player, params)
		"control_tempting_target":
			return _check_tempting_target(player, mission)
		"control_own_zone_and_nml_objectives":
			return _check_extend_battle_lines(player, params)

		# Kill-based checks
		"character_models_destroyed_this_turn":
			return _check_characters_destroyed_this_turn(player, params)
		"all_enemy_characters_destroyed":
			return _check_all_enemy_characters_destroyed(player)
		"enemy_unit_destroyed":
			return _check_enemy_unit_destroyed_this_turn(player)
		"infantry_starting_strength_13_plus_destroyed_this_turn":
			return _check_infantry_horde_destroyed(player, params)
		"monster_or_vehicle_destroyed_this_turn":
			return _check_monster_vehicle_destroyed(player, params)
		"alpha_target_destroyed_this_turn":
			return _check_alpha_target_destroyed(player, mission, params)
		"no_alpha_destroyed_but_gamma_destroyed_this_turn":
			return _check_gamma_target_destroyed(player, mission)
		"enemy_unit_destroyed_within_objective_range":
			return _check_overwhelming_force(player)

		# Action-based checks
		"locus_established_within_center":
			return _check_locus_center(player, params)
		"locus_established_in_opponent_deployment_zone":
			return _check_locus_opponent_zone(player)
		"objectives_cleansed":
			return _check_objectives_cleansed(player, params)
		"teleport_homer_deployed_not_in_opponent_zone":
			return _check_teleport_homer(player, false)
		"teleport_homer_deployed_in_opponent_zone":
			return _check_teleport_homer(player, true)
		"units_recovered_assets":
			return _check_recovered_assets(player, params)

		_:
			push_warning("SecondaryMissionManager: Unknown condition check: %s" % check)
			return false

# ============================================================================
# CONDITION CHECKERS - POSITIONAL
# ============================================================================

func _check_units_in_opponent_zone(player: int, params: Dictionary) -> bool:
	"""Check how many units are wholly within opponent's deployment zone."""
	var required = params.get("count", 1)
	var exclude = params.get("exclude", [])
	var opponent = 2 if player == 1 else 1
	var opponent_zone = _get_deployment_zone_polygon(opponent)

	if opponent_zone.is_empty():
		return false

	var qualifying_count = 0
	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue
		if _is_unit_excluded(unit, exclude):
			continue
		if _is_unit_wholly_in_zone(unit, opponent_zone):
			qualifying_count += 1

	return qualifying_count >= required

func _check_table_quarter_presence(player: int, params: Dictionary) -> bool:
	"""Check presence in table quarters (>6\" from center)."""
	var required = params.get("count", 1)
	var min_dist = params.get("min_distance_from_center", 6.0)
	var exclude = params.get("exclude", [])

	var board_width = GameState.state.get("board", {}).get("size", {}).get("width", 44)
	var board_height = GameState.state.get("board", {}).get("size", {}).get("height", 60)
	var center_x = board_width / 2.0
	var center_y = board_height / 2.0

	# Define quarters: TL, TR, BL, BR
	var quarters_with_presence = 0
	var quarter_bounds = [
		{"min_x": 0, "max_x": center_x, "min_y": 0, "max_y": center_y},          # TL
		{"min_x": center_x, "max_x": board_width, "min_y": 0, "max_y": center_y}, # TR
		{"min_x": 0, "max_x": center_x, "min_y": center_y, "max_y": board_height},          # BL
		{"min_x": center_x, "max_x": board_width, "min_y": center_y, "max_y": board_height}, # BR
	]

	var units = GameState.state.get("units", {})
	var min_dist_px = Measurement.inches_to_px(min_dist)
	var center_px = Vector2(Measurement.inches_to_px(center_x), Measurement.inches_to_px(center_y))

	for quarter in quarter_bounds:
		var has_presence = false
		var q_min = Vector2(Measurement.inches_to_px(quarter["min_x"]), Measurement.inches_to_px(quarter["min_y"]))
		var q_max = Vector2(Measurement.inches_to_px(quarter["max_x"]), Measurement.inches_to_px(quarter["max_y"]))

		for unit_id in units:
			if has_presence:
				break
			var unit = units[unit_id]
			if unit.get("owner", 0) != player:
				continue
			if _is_unit_excluded(unit, exclude):
				continue
			# Check if unit is wholly within this quarter AND >6" from center
			if _is_unit_wholly_in_rect(unit, q_min, q_max) and _is_unit_far_from_point(unit, center_px, min_dist_px):
				has_presence = true

		if has_presence:
			quarters_with_presence += 1

	return quarters_with_presence >= required

func _check_area_denial(player: int, params: Dictionary) -> bool:
	"""Check units within center range and no enemies within enemy range."""
	var friendly_range = params.get("friendly_range", 3.0)
	var enemy_range = params.get("enemy_range", 3.0)
	var exclude = params.get("exclude", [])

	var board_width = GameState.state.get("board", {}).get("size", {}).get("width", 44)
	var board_height = GameState.state.get("board", {}).get("size", {}).get("height", 60)
	var center_px = Vector2(Measurement.inches_to_px(board_width / 2.0), Measurement.inches_to_px(board_height / 2.0))
	var friendly_range_px = Measurement.inches_to_px(friendly_range)
	var enemy_range_px = Measurement.inches_to_px(enemy_range)

	var opponent = 2 if player == 1 else 1
	var units = GameState.state.get("units", {})

	# Check if any friendly unit is within friendly_range of center
	var has_friendly = false
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue
		if _is_unit_excluded(unit, exclude):
			continue
		if _has_model_within_range(unit, center_px, friendly_range_px):
			has_friendly = true
			break

	if not has_friendly:
		return false

	# Check no enemies within enemy_range of center
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != opponent:
			continue
		if _has_model_within_range(unit, center_px, enemy_range_px):
			return false

	return true

func _check_display_of_might(player: int) -> bool:
	"""Check if player has more units wholly in NML than opponent."""
	var opponent = 2 if player == 1 else 1
	var player_count = _count_units_wholly_in_nml(player)
	var opponent_count = _count_units_wholly_in_nml(opponent)
	return player_count > opponent_count

# ============================================================================
# CONDITION CHECKERS - OBJECTIVE CONTROL
# ============================================================================

func _check_storm_hostile_objective(player: int, params: Dictionary) -> bool:
	"""Check if player controls objectives that opponent controlled at start of turn."""
	var required = params.get("count", 1)
	var count = 0

	for obj_id in MissionManager.objective_control_state:
		var current_controller = MissionManager.objective_control_state[obj_id]
		var start_controller = _objective_control_at_turn_start.get(obj_id, 0)
		var opponent = 2 if player == 1 else 1

		if current_controller == player and start_controller == opponent:
			count += 1

	return count >= required

func _check_storm_hostile_alt(player: int, params: Dictionary) -> bool:
	"""Alt condition: opponent controlled no objectives at start AND you control new ones."""
	var min_round = params.get("min_round", 2)
	if GameState.get_battle_round() < min_round:
		return false

	var opponent = 2 if player == 1 else 1

	# Check opponent controlled no objectives at start
	for obj_id in _objective_control_at_turn_start:
		if _objective_control_at_turn_start[obj_id] == opponent:
			return false

	# Check you control at least 1 you didn't at start
	for obj_id in MissionManager.objective_control_state:
		var current = MissionManager.objective_control_state[obj_id]
		var start = _objective_control_at_turn_start.get(obj_id, 0)
		if current == player and start != player:
			return true

	return false

func _check_own_zone_objectives(player: int, params: Dictionary) -> bool:
	"""Check if player controls objectives in their own deployment zone."""
	var required = params.get("count", 1)
	var count = 0
	var objectives = GameState.state.board.get("objectives", [])
	var player_zone = "player%d" % player

	for obj in objectives:
		var zone = obj.get("zone", "")
		if zone == player_zone:
			var controller = MissionManager.objective_control_state.get(obj["id"], 0)
			if controller == player:
				count += 1

	return count >= required

func _check_nml_objectives(player: int, params: Dictionary) -> bool:
	"""Check if player controls objectives in No Man's Land."""
	var required = params.get("count", 1)
	var count = 0
	var objectives = GameState.state.board.get("objectives", [])

	for obj in objectives:
		if obj.get("zone", "") == "no_mans_land":
			var controller = MissionManager.objective_control_state.get(obj["id"], 0)
			if controller == player:
				count += 1

	return count >= required

func _check_tempting_target(player: int, mission: Dictionary) -> bool:
	"""Check if player controls the Tempting Target objective."""
	var target_obj_id = mission.get("mission_data", {}).get("tempting_target_id", "")
	if target_obj_id == "":
		return false
	var controller = MissionManager.objective_control_state.get(target_obj_id, 0)
	return controller == player

func _check_extend_battle_lines(player: int, params: Dictionary) -> bool:
	"""Check if player controls objectives in own zone AND NML."""
	var own_required = params.get("own_zone_count", 1)
	var nml_required = params.get("nml_count", 1)
	return _check_own_zone_objectives(player, {"count": own_required}) and _check_nml_objectives(player, {"count": nml_required})

# ============================================================================
# CONDITION CHECKERS - KILL-BASED
# ============================================================================

func _check_characters_destroyed_this_turn(_player: int, params: Dictionary) -> bool:
	"""Check if CHARACTER models were destroyed this turn."""
	var required = params.get("count", 1)
	var count = 0
	for destroyed in _units_destroyed_this_turn:
		if destroyed.get("is_character", false):
			count += 1
	return count >= required

func _check_all_enemy_characters_destroyed(player: int) -> bool:
	"""Check if ALL enemy CHARACTER models have been destroyed."""
	var opponent = 2 if player == 1 else 1
	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != opponent:
			continue
		var keywords = unit.get("meta", {}).get("keywords", [])
		var is_char = false
		for kw in keywords:
			if kw.to_upper() == "CHARACTER":
				is_char = true
				break
		if not is_char:
			continue

		# Check if any models are still alive
		for model in unit.get("models", []):
			if model.get("alive", true):
				return false

	return true

func _check_enemy_unit_destroyed_this_turn(_player: int) -> bool:
	"""Check if any enemy unit was destroyed this turn."""
	return _units_destroyed_this_turn.size() > 0

func _check_infantry_horde_destroyed(_player: int, params: Dictionary) -> bool:
	"""Check if INFANTRY units with starting strength 13+ were destroyed."""
	var required = params.get("count", 1)
	var count = 0
	for destroyed in _units_destroyed_this_turn:
		if destroyed.get("is_infantry", false) and destroyed.get("starting_strength", 0) >= 13:
			count += 1
	return count >= required

func _check_monster_vehicle_destroyed(_player: int, params: Dictionary) -> bool:
	"""Check if MONSTER or VEHICLE units were destroyed this turn."""
	var required = params.get("count", 1)
	var count = 0
	for destroyed in _units_destroyed_this_turn:
		if destroyed.get("is_monster", false) or destroyed.get("is_vehicle", false):
			count += 1
	return count >= required

func _check_alpha_target_destroyed(_player: int, mission: Dictionary, params: Dictionary) -> bool:
	"""Check if any Marked for Death alpha targets were destroyed this turn."""
	var alpha_targets = mission.get("mission_data", {}).get("alpha_targets", [])
	var required = params.get("count", 1)
	var count = 0
	for destroyed in _units_destroyed_this_turn:
		if destroyed.get("unit_id", "") in alpha_targets:
			count += 1
	return count >= required

func _check_gamma_target_destroyed(_player: int, mission: Dictionary) -> bool:
	"""Check if gamma target destroyed but no alpha targets destroyed."""
	var alpha_targets = mission.get("mission_data", {}).get("alpha_targets", [])
	var gamma_target = mission.get("mission_data", {}).get("gamma_target", "")

	# Check no alpha destroyed
	for destroyed in _units_destroyed_this_turn:
		if destroyed.get("unit_id", "") in alpha_targets:
			return false

	# Check gamma destroyed
	for destroyed in _units_destroyed_this_turn:
		if destroyed.get("unit_id", "") == gamma_target:
			return true

	return false

func _check_overwhelming_force(_player: int) -> bool:
	"""Check if enemy units near objectives were destroyed."""
	for destroyed in _units_destroyed_this_turn:
		if destroyed.get("was_near_objective", false):
			return true
	return false

# ============================================================================
# CONDITION CHECKERS - ACTION-BASED (stubs for future implementation)
# ============================================================================

func _check_locus_center(player: int, _params: Dictionary) -> bool:
	"""Check if a locus was established within 6\" of center."""
	for action in _active_actions[str(player)]:
		if action.get("action_name", "") == "Establish Locus" and action.get("completed", false):
			if action.get("location", "") == "center":
				return true
	return false

func _check_locus_opponent_zone(player: int) -> bool:
	"""Check if a locus was established in opponent's deployment zone."""
	for action in _active_actions[str(player)]:
		if action.get("action_name", "") == "Establish Locus" and action.get("completed", false):
			if action.get("location", "") == "opponent_zone":
				return true
	return false

func _check_objectives_cleansed(player: int, params: Dictionary) -> bool:
	"""Check if objectives were cleansed this turn."""
	var required = params.get("count", 1)
	var count = 0
	for action in _active_actions[str(player)]:
		if action.get("action_name", "") == "Cleanse" and action.get("completed", false):
			count += 1
	return count >= required

func _check_teleport_homer(player: int, in_opponent_zone: bool) -> bool:
	"""Check if a teleport homer was deployed."""
	for action in _active_actions[str(player)]:
		if action.get("action_name", "") == "Deploy Teleport Homer" and action.get("completed", false):
			if in_opponent_zone:
				return action.get("location", "") == "opponent_zone"
			else:
				return action.get("location", "") != "opponent_zone"
	return false

func _check_recovered_assets(player: int, params: Dictionary) -> bool:
	"""Check if assets were recovered."""
	var required = params.get("count", 2)
	var count = 0
	for action in _active_actions[str(player)]:
		if action.get("action_name", "") == "Recover Assets" and action.get("completed", false):
			count += 1
	return count >= required

# ============================================================================
# VP MANAGEMENT
# ============================================================================

func _award_secondary_vp(player: int, vp: int, mission_id: String) -> int:
	"""Award secondary VP, respecting caps. Returns actual VP awarded."""
	var player_key = str(player)
	var state = _player_state[player_key]
	var current_secondary = state["secondary_vp"]

	# Cap at MAX_SECONDARY_VP
	var available = MAX_SECONDARY_VP - current_secondary
	var actual_vp = mini(vp, available)

	if actual_vp <= 0:
		print("SecondaryMissionManager: Player %d at secondary VP cap (%d)" % [player, MAX_SECONDARY_VP])
		return 0

	# Also check combined cap
	var primary_vp = GameState.state.get("players", {}).get(player_key, {}).get("primary_vp", 0)
	var combined_available = MAX_COMBINED_VP - primary_vp - current_secondary
	actual_vp = mini(actual_vp, combined_available)

	if actual_vp <= 0:
		print("SecondaryMissionManager: Player %d at combined VP cap (%d)" % [player, MAX_COMBINED_VP])
		return 0

	# Award VP
	state["secondary_vp"] += actual_vp

	# Update GameState total VP
	var total_vp = GameState.state.get("players", {}).get(player_key, {}).get("vp", 0)
	var changes = [
		{
			"op": "set",
			"path": "players.%s.vp" % player_key,
			"value": total_vp + actual_vp,
		},
		{
			"op": "set",
			"path": "players.%s.secondary_vp" % player_key,
			"value": state["secondary_vp"],
		},
	]
	PhaseManager.apply_state_changes(changes)

	print("SecondaryMissionManager: Player %d awarded %d secondary VP from %s (total secondary: %d)" % [
		player, actual_vp, mission_id, state["secondary_vp"]])

	return actual_vp

func _discard_achieved_missions(player: int) -> void:
	"""Discard missions that were achieved this turn."""
	var player_key = str(player)
	var state = _player_state[player_key]
	var remaining = []

	for mission in state["active"]:
		if mission["achieved"]:
			state["discard"].append(mission["id"])
			print("SecondaryMissionManager: Player %d achieved and discarded %s" % [player, mission["name"]])
		else:
			remaining.append(mission)

	state["active"] = remaining

# ============================================================================
# EVENT HOOKS - Called by other systems to track game events
# ============================================================================

func on_turn_start(player: int) -> void:
	"""Called at the start of a player's turn. Snapshot objective control."""
	_units_destroyed_this_turn.clear()
	_while_active_vp_this_window.clear()
	_objective_control_at_turn_start = MissionManager.objective_control_state.duplicate()
	# Clear completed actions from previous turn
	_active_actions[str(player)].clear()
	print("SecondaryMissionManager: Turn start for Player %d - snapshot objectives" % player)

func on_unit_destroyed(destroyed_unit: Dictionary) -> void:
	"""
	Called when a unit is destroyed. Records info for kill-based missions.
	destroyed_unit should contain: unit_id, owner, keywords, starting_strength, wounds, was_near_objective
	"""
	_units_destroyed_this_turn.append(destroyed_unit)

	var unit_name = destroyed_unit.get("unit_name", destroyed_unit.get("unit_id", "unknown"))
	print("SecondaryMissionManager: Recorded unit destruction: %s" % unit_name)

	# Check "while_active" missions immediately for both players
	for p in [1, 2]:
		if destroyed_unit.get("owner", 0) == p:
			continue  # Skip the owner - they don't score for their own destruction
		_check_while_active_missions(p, destroyed_unit)

func _check_while_active_missions(player: int, destroyed_unit: Dictionary) -> void:
	"""Check while_active missions after a unit destruction event."""
	var player_key = str(player)
	var state = _player_state[player_key]

	for mission in state["active"]:
		if mission.get("pending_interaction", false):
			continue

		var scoring = mission["scoring"]
		if scoring.get("when", "") != SecondaryMissionData.TIMING_WHILE_ACTIVE:
			continue

		var max_vp = scoring.get("max_vp_per_score", 999)
		var window_key = "%s_%s" % [player_key, mission["id"]]
		var accumulated = _while_active_vp_this_window.get(window_key, 0)

		if accumulated >= max_vp:
			continue  # Already hit cap for this scoring window

		for condition in scoring.get("conditions", []):
			var check = condition.get("check", "")
			var vp = condition.get("vp", 0)

			var matches = false
			match check:
				"enemy_unit_destroyed":
					matches = true
				"enemy_bodyguard_or_non_character_unit_destroyed":
					matches = not destroyed_unit.get("is_character", false) or destroyed_unit.get("is_bodyguard", false)
				"enemy_unit_destroyed_within_objective_range":
					matches = destroyed_unit.get("was_near_objective", false)

			if matches:
				var remaining = max_vp - accumulated
				var award = mini(vp, remaining)
				if award > 0:
					var actual = _award_secondary_vp(player, award, mission["id"])
					if actual > 0:
						mission["vp_scored"] += actual
						_while_active_vp_this_window[window_key] = accumulated + actual
						emit_signal("secondary_vp_scored", player, actual, mission["id"])
						print("SecondaryMissionManager: Player %d scored %d VP (while active) from %s" % [player, actual, mission["name"]])

func on_action_completed(player: int, action_data: Dictionary) -> void:
	"""Called when a unit completes an action (for action-based missions)."""
	_active_actions[str(player)].append(action_data)
	print("SecondaryMissionManager: Player %d completed action: %s" % [player, action_data.get("action_name", "")])

func check_and_report_unit_destroyed(unit_id: String) -> void:
	"""
	Check if ALL models in a unit are dead. If so, build a destroyed_unit dict
	and call on_unit_destroyed(). Deduplicates via _units_destroyed_this_turn.
	Also recursively checks attached characters (they may have died too).
	"""
	# Dedup: skip if already reported this turn
	for already in _units_destroyed_this_turn:
		if already.get("unit_id", "") == unit_id:
			return

	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return

	# Check if ALL models are dead
	var models = unit.get("models", [])
	if models.is_empty():
		return

	for model in models:
		if model.get("alive", true):
			return  # At least one model still alive — not destroyed

	# Unit is fully destroyed — build info dict
	var keywords = unit.get("meta", {}).get("keywords", [])
	var upper_keywords = []
	for kw in keywords:
		upper_keywords.append(kw.to_upper())

	var starting_strength = models.size()
	var owner = unit.get("owner", 0)
	var unit_name = unit.get("meta", {}).get("name", unit_id)

	var destroyed_dict = {
		"unit_id": unit_id,
		"unit_name": unit_name,
		"owner": owner,
		"keywords": keywords,
		"starting_strength": starting_strength,
		"is_character": "CHARACTER" in upper_keywords,
		"is_infantry": "INFANTRY" in upper_keywords,
		"is_monster": "MONSTER" in upper_keywords,
		"is_vehicle": "VEHICLE" in upper_keywords,
		"is_bodyguard": unit.get("attachment_data", {}).get("attached_characters", []).size() > 0 or "BODYGUARD" in upper_keywords,
		"was_near_objective": _check_unit_near_any_objective(unit),
	}

	print("SecondaryMissionManager: Unit %s (%s) fully destroyed! Reporting..." % [unit_id, unit_name])
	on_unit_destroyed(destroyed_dict)

	# Recursively check attached characters — when a bodyguard dies, characters
	# may have been killed too (or detached and killed separately)
	var attached_chars = unit.get("attachment_data", {}).get("attached_characters", [])
	for char_id in attached_chars:
		check_and_report_unit_destroyed(char_id)

func _check_unit_near_any_objective(unit: Dictionary) -> bool:
	"""Check if any model in the unit (alive or dead) is within 3\" of any objective."""
	var objectives = GameState.state.get("board", {}).get("objectives", [])
	if objectives.is_empty():
		return false

	var range_px = Measurement.inches_to_px(3.0)

	for obj in objectives:
		var obj_pos = obj.get("position", null)
		if obj_pos == null:
			continue
		if obj_pos is Dictionary:
			obj_pos = Vector2(obj_pos.x, obj_pos.y)

		for model in unit.get("models", []):
			var pos = model.get("position", null)
			if pos == null:
				continue
			if pos is Dictionary:
				pos = Vector2(pos.x, pos.y)
			# Any part of the model's base overlapping counts
			var model_base_radius = Measurement.base_radius_px(model.get("base_mm", 32))
			if pos.distance_to(obj_pos) <= range_px + model_base_radius:
				return true

	return false

# ============================================================================
# INTERACTION RESOLUTION
# ============================================================================

func resolve_marked_for_death(player: int, alpha_targets: Array, gamma_target: String) -> void:
	"""Resolve Marked for Death interaction - set the alpha and gamma targets."""
	var player_key = str(player)
	var state = _player_state[player_key]

	for mission in state["active"]:
		if mission["id"] == "marked_for_death" and mission.get("pending_interaction", false):
			mission["mission_data"]["alpha_targets"] = alpha_targets
			mission["mission_data"]["gamma_target"] = gamma_target
			mission["pending_interaction"] = false
			print("SecondaryMissionManager: Marked for Death resolved - Alpha: %s, Gamma: %s" % [str(alpha_targets), gamma_target])
			return

func resolve_tempting_target(player: int, objective_id: String) -> void:
	"""Resolve A Tempting Target interaction - set the target objective."""
	var player_key = str(player)
	var state = _player_state[player_key]

	for mission in state["active"]:
		if mission["id"] == "a_tempting_target" and mission.get("pending_interaction", false):
			mission["mission_data"]["tempting_target_id"] = objective_id
			mission["pending_interaction"] = false
			print("SecondaryMissionManager: A Tempting Target resolved - Objective: %s" % objective_id)
			return

# ============================================================================
# QUERIES
# ============================================================================

func get_active_missions(player: int) -> Array:
	"""Get the active secondary missions for a player."""
	return _player_state[str(player)]["active"].duplicate(true)

func get_secondary_vp(player: int) -> int:
	"""Get total secondary VP for a player."""
	return _player_state[str(player)]["secondary_vp"]

func get_deck_size(player: int) -> int:
	"""Get remaining cards in deck."""
	return _player_state[str(player)]["deck"].size()

func get_discard_size(player: int) -> int:
	"""Get number of discarded cards."""
	return _player_state[str(player)]["discard"].size()

func is_initialized(player: int) -> bool:
	"""Check if player's secondary missions are set up."""
	return _player_state[str(player)]["initialized"]

func get_vp_summary() -> Dictionary:
	"""Get VP summary for both players including secondary VP."""
	return {
		"player1": {
			"secondary_vp": _player_state["1"]["secondary_vp"],
			"active_count": _player_state["1"]["active"].size(),
			"deck_remaining": _player_state["1"]["deck"].size(),
		},
		"player2": {
			"secondary_vp": _player_state["2"]["secondary_vp"],
			"active_count": _player_state["2"]["active"].size(),
			"deck_remaining": _player_state["2"]["deck"].size(),
		},
	}

# ============================================================================
# GEOMETRY HELPERS
# ============================================================================

func _get_deployment_zone_polygon(player: int) -> PackedVector2Array:
	"""Get the deployment zone polygon for a player (in pixels)."""
	var zones = GameState.state.get("board", {}).get("deployment_zones", [])
	for zone in zones:
		if zone.get("player", 0) == player:
			var poly = PackedVector2Array()
			for point in zone.get("poly", []):
				poly.append(Vector2(
					Measurement.inches_to_px(point.get("x", 0)),
					Measurement.inches_to_px(point.get("y", 0))
				))
			return poly
	return PackedVector2Array()

func _is_unit_excluded(unit: Dictionary, exclusions: Array) -> bool:
	"""Check if a unit should be excluded based on keywords/flags."""
	var keywords = unit.get("meta", {}).get("keywords", [])
	var flags = unit.get("flags", {})

	for excl in exclusions:
		if excl == "Battle-shocked" and flags.get("battle_shocked", false):
			return true
		for kw in keywords:
			if kw.to_upper() == excl.to_upper():
				return true

	# Also exclude non-deployed units
	var status = unit.get("status", GameStateData.UnitStatus.UNDEPLOYED)
	if status == GameStateData.UnitStatus.UNDEPLOYED:
		return true

	# Exclude units with no alive models
	var has_alive = false
	for model in unit.get("models", []):
		if model.get("alive", true):
			has_alive = true
			break
	if not has_alive:
		return true

	return false

func _is_unit_wholly_in_zone(unit: Dictionary, zone_polygon: PackedVector2Array) -> bool:
	"""Check if ALL alive models in a unit are within a polygon."""
	if zone_polygon.is_empty():
		return false

	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		var pos = model.get("position")
		if pos == null:
			return false
		if pos is Dictionary:
			pos = Vector2(pos.x, pos.y)
		if not Geometry2D.is_point_in_polygon(pos, zone_polygon):
			return false

	return true

func _is_unit_wholly_in_rect(unit: Dictionary, rect_min: Vector2, rect_max: Vector2) -> bool:
	"""Check if ALL alive models are within a rectangle."""
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		var pos = model.get("position")
		if pos == null:
			return false
		if pos is Dictionary:
			pos = Vector2(pos.x, pos.y)
		if pos.x < rect_min.x or pos.x > rect_max.x or pos.y < rect_min.y or pos.y > rect_max.y:
			return false
	return true

func _is_unit_far_from_point(unit: Dictionary, point: Vector2, min_distance: float) -> bool:
	"""Check if ALL alive models are farther than min_distance from a point."""
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		var pos = model.get("position")
		if pos == null:
			return false
		if pos is Dictionary:
			pos = Vector2(pos.x, pos.y)
		if pos.distance_to(point) <= min_distance:
			return false
	return true

func _has_model_within_range(unit: Dictionary, point: Vector2, max_range: float) -> bool:
	"""Check if ANY alive model is within range of a point."""
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		var pos = model.get("position")
		if pos == null:
			continue
		if pos is Dictionary:
			pos = Vector2(pos.x, pos.y)
		if pos.distance_to(point) <= max_range:
			return true
	return false

func _count_units_wholly_in_nml(player: int) -> int:
	"""Count units wholly within No Man's Land."""
	# NML is the area between both deployment zones
	# For simplicity, use the NML definition based on deployment type
	var units = GameState.state.get("units", {})
	var p1_zone = _get_deployment_zone_polygon(1)
	var p2_zone = _get_deployment_zone_polygon(2)
	var count = 0

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue
		if _is_unit_excluded(unit, []):
			continue
		# Unit is in NML if wholly NOT in either deployment zone
		var in_p1 = false
		var in_p2 = false
		var all_models_valid = true

		for model in unit.get("models", []):
			if not model.get("alive", true):
				continue
			var pos = model.get("position")
			if pos == null:
				all_models_valid = false
				break
			if pos is Dictionary:
				pos = Vector2(pos.x, pos.y)
			if not p1_zone.is_empty() and Geometry2D.is_point_in_polygon(pos, p1_zone):
				in_p1 = true
			if not p2_zone.is_empty() and Geometry2D.is_point_in_polygon(pos, p2_zone):
				in_p2 = true

		if all_models_valid and not in_p1 and not in_p2:
			count += 1

	return count

# ============================================================================
# UNIT QUERY HELPERS
# ============================================================================

func _has_enemy_infantry_13_plus(player: int) -> bool:
	"""Check if opponent has any INFANTRY with starting strength 13+."""
	var opponent = 2 if player == 1 else 1
	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != opponent:
			continue
		var keywords = unit.get("meta", {}).get("keywords", [])
		var is_infantry = false
		for kw in keywords:
			if kw.to_upper() == "INFANTRY":
				is_infantry = true
				break
		if not is_infantry:
			continue
		var starting_strength = unit.get("models", []).size()
		if starting_strength >= 13:
			return true

	return false

func _has_enemy_monster_or_vehicle(player: int) -> bool:
	"""Check if opponent has any MONSTER or VEHICLE units on the battlefield."""
	var opponent = 2 if player == 1 else 1
	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != opponent:
			continue
		if unit.get("status", GameStateData.UnitStatus.UNDEPLOYED) == GameStateData.UnitStatus.UNDEPLOYED:
			continue
		var keywords = unit.get("meta", {}).get("keywords", [])
		for kw in keywords:
			var upper = kw.to_upper()
			if upper == "MONSTER" or upper == "VEHICLE":
				return true

	return false

func _count_player_units_on_battlefield(player: int) -> int:
	"""Count units from a player on the battlefield."""
	var count = 0
	var units = GameState.state.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue
		if unit.get("status", GameStateData.UnitStatus.UNDEPLOYED) == GameStateData.UnitStatus.UNDEPLOYED:
			continue
		var has_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if has_alive:
			count += 1
	return count

func _get_opponent_units_on_battlefield(player: int) -> Array:
	"""Get list of opponent unit IDs on the battlefield."""
	var opponent = 2 if player == 1 else 1
	var result = []
	var units = GameState.state.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != opponent:
			continue
		if unit.get("status", GameStateData.UnitStatus.UNDEPLOYED) == GameStateData.UnitStatus.UNDEPLOYED:
			continue
		var has_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if has_alive:
			result.append(unit_id)
	return result

# ============================================================================
# UTILITY
# ============================================================================

func _shuffle_array(arr: Array) -> void:
	"""Fisher-Yates shuffle."""
	for i in range(arr.size() - 1, 0, -1):
		var j = _rng.randi_range(0, i)
		var temp = arr[i]
		arr[i] = arr[j]
		arr[j] = temp
