extends RefCounted
class_name SecondaryMissionData

# SecondaryMissionData - Static definitions for all 18 tactical secondary mission cards
# Based on Chapter Approved 2025-26 rules
#
# Each mission is defined with:
#   id, name, number, category, scoring conditions, when_drawn conditions,
#   action requirements, and display text.

# ============================================================================
# TIMING CONSTANTS
# ============================================================================

const TIMING_END_OF_YOUR_TURN = "end_of_your_turn"
const TIMING_END_OF_EITHER_TURN = "end_of_either_turn"
const TIMING_END_OF_OPPONENT_TURN = "end_of_opponent_turn"
const TIMING_WHILE_ACTIVE = "while_active"

# ============================================================================
# WHEN-DRAWN EFFECT CONSTANTS
# ============================================================================

const EFFECT_MANDATORY_SHUFFLE_BACK = "mandatory_shuffle_back"
const EFFECT_SHUFFLE_BACK = "shuffle_back"

# ============================================================================
# MISSION DEFINITIONS
# ============================================================================

static var _missions: Dictionary = {}

static func _ensure_loaded() -> void:
	if _missions.is_empty():
		_load_missions()

static func _load_missions() -> void:
	# ====================================================================
	# POSITIONAL MISSIONS
	# ====================================================================

	_missions["behind_enemy_lines"] = {
		"id": "behind_enemy_lines",
		"name": "Behind Enemy Lines",
		"number": 1,
		"category": "Shadow Operations",
		"description": "Get units wholly within your opponent's deployment zone.",
		"scoring": {
			"when": TIMING_END_OF_YOUR_TURN,
			"conditions": [
				{"check": "units_wholly_in_opponent_deployment_zone", "params": {"count": 2, "exclude": ["Battle-shocked"]}, "vp": 5},
				{"check": "units_wholly_in_opponent_deployment_zone", "params": {"count": 1, "exclude": ["Battle-shocked"]}, "vp": 2},
			],
		},
		"requires_action": false,
		"action": {},
		"when_drawn": {"condition": "first_battle_round", "effect": EFFECT_MANDATORY_SHUFFLE_BACK},
	}

	_missions["engage_on_all_fronts"] = {
		"id": "engage_on_all_fronts",
		"name": "Engage on All Fronts",
		"number": 2,
		"category": "Battlefield Supremacy",
		"description": "Have units in multiple table quarters, >6\" from the center.",
		"scoring": {
			"when": TIMING_END_OF_YOUR_TURN,
			"conditions": [
				{"check": "presence_in_table_quarters", "params": {"count": 4, "min_distance_from_center": 6.0, "exclude": ["Battle-shocked"]}, "vp": 5},
				{"check": "presence_in_table_quarters", "params": {"count": 3, "min_distance_from_center": 6.0, "exclude": ["Battle-shocked"]}, "vp": 3},
				{"check": "presence_in_table_quarters", "params": {"count": 2, "min_distance_from_center": 6.0, "exclude": ["Battle-shocked"]}, "vp": 2},
			],
		},
		"requires_action": false,
		"action": {},
		"when_drawn": {},
	}

	_missions["area_denial"] = {
		"id": "area_denial",
		"name": "Area Denial",
		"number": 3,
		"category": "Battlefield Supremacy",
		"description": "Have units within 6\" of the center with no enemies within 6\".",
		"scoring": {
			"when": TIMING_END_OF_YOUR_TURN,
			"conditions": [
				{"check": "units_within_center_no_enemies_within", "params": {"friendly_range": 6.0, "enemy_range": 6.0, "exclude": ["Battle-shocked"]}, "vp": 5},
				{"check": "units_within_center_no_enemies_within", "params": {"friendly_range": 6.0, "enemy_range": 3.0, "exclude": ["Battle-shocked"]}, "vp": 3},
			],
		},
		"requires_action": false,
		"action": {},
		"when_drawn": {},
	}

	_missions["display_of_might"] = {
		"id": "display_of_might",
		"name": "Display of Might",
		"number": 4,
		"category": "Battlefield Supremacy",
		"description": "Have more units wholly in No Man's Land than your opponent.",
		"scoring": {
			"when": TIMING_END_OF_YOUR_TURN,
			"conditions": [
				{"check": "more_units_wholly_in_no_mans_land_than_opponent", "params": {}, "vp": 5},
			],
		},
		"requires_action": false,
		"action": {},
		"when_drawn": {"condition": "fewer_than_3_units_or_incursion"},
	}

	# ====================================================================
	# OBJECTIVE CONTROL MISSIONS
	# ====================================================================

	_missions["storm_hostile_objective"] = {
		"id": "storm_hostile_objective",
		"name": "Storm Hostile Objective",
		"number": 5,
		"category": "Strategic Conquests",
		"description": "Control objectives your opponent controlled at the start of the turn.",
		"scoring": {
			"when": TIMING_END_OF_YOUR_TURN,
			"conditions": [
				{"check": "control_objectives_opponent_controlled_at_start", "params": {"count": 2}, "vp": 5},
				{"check": "control_objectives_opponent_controlled_at_start", "params": {"count": 1}, "vp": 2},
				{"check": "opponent_controlled_no_objectives_at_start_and_you_control_new", "params": {"min_round": 2}, "vp": 2},
			],
		},
		"requires_action": false,
		"action": {},
		"when_drawn": {},
	}

	_missions["defend_stronghold"] = {
		"id": "defend_stronghold",
		"name": "Defend Stronghold",
		"number": 6,
		"category": "Strategic Conquests",
		"description": "Control objectives in your own deployment zone.",
		"scoring": {
			"when": TIMING_END_OF_YOUR_TURN,
			"conditions": [
				{"check": "control_objectives_in_own_deployment_zone", "params": {"count": 2}, "vp": 5},
				{"check": "control_objectives_in_own_deployment_zone", "params": {"count": 1}, "vp": 2},
			],
		},
		"requires_action": false,
		"action": {},
		"when_drawn": {},
	}

	_missions["secure_no_mans_land"] = {
		"id": "secure_no_mans_land",
		"name": "Secure No Man's Land",
		"number": 7,
		"category": "Strategic Conquests",
		"description": "Control objectives in No Man's Land.",
		"scoring": {
			"when": TIMING_END_OF_YOUR_TURN,
			"conditions": [
				{"check": "control_objectives_in_no_mans_land", "params": {"count": 2}, "vp": 5},
				{"check": "control_objectives_in_no_mans_land", "params": {"count": 1}, "vp": 2},
			],
		},
		"requires_action": false,
		"action": {},
		"when_drawn": {},
	}

	_missions["a_tempting_target"] = {
		"id": "a_tempting_target",
		"name": "A Tempting Target",
		"number": 8,
		"category": "Strategic Conquests",
		"description": "Control the objective selected by your opponent.",
		"scoring": {
			"when": TIMING_END_OF_EITHER_TURN,
			"conditions": [
				{"check": "control_tempting_target", "params": {}, "vp": 5},
			],
		},
		"requires_action": false,
		"action": {},
		"when_drawn": {
			"condition": "opponent_selects_objective",
			"details": {"zone": "no_mans_land"},
		},
	}

	_missions["extend_battle_lines"] = {
		"id": "extend_battle_lines",
		"name": "Extend Battle Lines",
		"number": 9,
		"category": "Strategic Conquests",
		"description": "Control objectives in your deployment zone AND No Man's Land.",
		"scoring": {
			"when": TIMING_END_OF_YOUR_TURN,
			"conditions": [
				{"check": "control_own_zone_and_nml_objectives", "params": {"own_zone_count": 1, "nml_count": 1}, "vp": 5},
			],
		},
		"requires_action": false,
		"action": {},
		"when_drawn": {},
	}

	# ====================================================================
	# KILL MISSIONS
	# ====================================================================

	_missions["assassination"] = {
		"id": "assassination",
		"name": "Assassination",
		"number": 10,
		"category": "Purge the Enemy",
		"description": "Destroy enemy CHARACTER models.",
		"scoring": {
			"when": TIMING_END_OF_EITHER_TURN,
			"conditions": [
				{"check": "all_enemy_characters_destroyed", "params": {}, "vp": 5},
				{"check": "character_models_destroyed_this_turn", "params": {"count": 1}, "vp": 3},
			],
		},
		"requires_action": false,
		"action": {},
		"when_drawn": {},
	}

	_missions["bring_it_down"] = {
		"id": "bring_it_down",
		"name": "Bring it Down",
		"number": 11,
		"category": "Purge the Enemy",
		"description": "Destroy enemy MONSTER or VEHICLE units.",
		"scoring": {
			"when": TIMING_END_OF_EITHER_TURN,
			"conditions": [
				{"check": "monster_or_vehicle_destroyed_this_turn", "params": {"count": 2}, "vp": 5},
				{"check": "monster_or_vehicle_destroyed_this_turn", "params": {"count": 1}, "vp": 3},
			],
		},
		"requires_action": false,
		"action": {},
		"when_drawn": {"condition": "no_enemy_monster_or_vehicle"},
	}

	_missions["cull_the_horde"] = {
		"id": "cull_the_horde",
		"name": "Cull the Horde",
		"number": 12,
		"category": "Purge the Enemy",
		"description": "Destroy INFANTRY units with starting strength 13+.",
		"scoring": {
			"when": TIMING_END_OF_EITHER_TURN,
			"conditions": [
				{"check": "infantry_starting_strength_13_plus_destroyed_this_turn", "params": {"count": 2}, "vp": 5},
				{"check": "infantry_starting_strength_13_plus_destroyed_this_turn", "params": {"count": 1}, "vp": 3},
			],
		},
		"requires_action": false,
		"action": {},
		"when_drawn": {"condition": "no_enemy_infantry_starting_strength_13_plus"},
	}

	_missions["marked_for_death"] = {
		"id": "marked_for_death",
		"name": "Marked for Death",
		"number": 13,
		"category": "Purge the Enemy",
		"description": "Destroy specific marked enemy targets.",
		"scoring": {
			"when": TIMING_END_OF_EITHER_TURN,
			"conditions": [
				{"check": "alpha_target_destroyed_this_turn", "params": {"count": 1}, "vp": 5},
				{"check": "no_alpha_destroyed_but_gamma_destroyed_this_turn", "params": {}, "vp": 2},
			],
		},
		"requires_action": false,
		"action": {},
		"when_drawn": {
			"condition": "opponent_selects_units",
			"details": {"alpha_targets": 3, "fallback_if_fewer": true},
		},
	}

	_missions["no_prisoners"] = {
		"id": "no_prisoners",
		"name": "No Prisoners",
		"number": 14,
		"category": "Purge the Enemy",
		"description": "Destroy any enemy unit.",
		"scoring": {
			"when": TIMING_WHILE_ACTIVE,
			"max_vp_per_score": 5,
			"conditions": [
				{"check": "enemy_unit_destroyed", "params": {}, "vp": 2},
			],
		},
		"requires_action": false,
		"action": {},
		"when_drawn": {},
	}

	_missions["overwhelming_force"] = {
		"id": "overwhelming_force",
		"name": "Overwhelming Force",
		"number": 15,
		"category": "Purge the Enemy",
		"description": "Destroy enemy units within range of objectives.",
		"scoring": {
			"when": TIMING_WHILE_ACTIVE,
			"max_vp_per_score": 5,
			"conditions": [
				{"check": "enemy_unit_destroyed_within_objective_range", "params": {}, "vp": 3},
			],
		},
		"requires_action": false,
		"action": {},
		"when_drawn": {},
	}

	# ====================================================================
	# ACTION MISSIONS
	# ====================================================================

	_missions["establish_locus"] = {
		"id": "establish_locus",
		"name": "Establish Locus",
		"number": 16,
		"category": "Shadow Operations",
		"description": "Establish a locus near the center or in the opponent's deployment zone.",
		"scoring": {
			"when": TIMING_END_OF_YOUR_TURN,
			"conditions": [
				{"check": "locus_established_in_opponent_deployment_zone", "params": {}, "vp": 5},
				{"check": "locus_established_within_center", "params": {"range": 6.0}, "vp": 3},
			],
		},
		"requires_action": true,
		"action": {"name": "Establish Locus", "phase": "shooting"},
		"when_drawn": {},
	}

	_missions["cleanse"] = {
		"id": "cleanse",
		"name": "Cleanse",
		"number": 17,
		"category": "Shadow Operations",
		"description": "Cleanse objective markers by completing actions.",
		"scoring": {
			"when": TIMING_END_OF_YOUR_TURN,
			"conditions": [
				{"check": "objectives_cleansed", "params": {"count": 2}, "vp": 5},
				{"check": "objectives_cleansed", "params": {"count": 1}, "vp": 2},
			],
		},
		"requires_action": true,
		"action": {"name": "Cleanse", "phase": "shooting"},
		"when_drawn": {},
	}

	_missions["deploy_teleport_homer"] = {
		"id": "deploy_teleport_homer",
		"name": "Deploy Teleport Homer",
		"number": 18,
		"category": "Shadow Operations",
		"description": "Deploy a teleport homer in enemy territory.",
		"scoring": {
			"when": TIMING_END_OF_YOUR_TURN,
			"conditions": [
				{"check": "teleport_homer_deployed_in_opponent_zone", "params": {}, "vp": 5},
				{"check": "teleport_homer_deployed_not_in_opponent_zone", "params": {}, "vp": 3},
			],
		},
		"requires_action": true,
		"action": {"name": "Deploy Teleport Homer", "phase": "shooting"},
		"when_drawn": {},
	}

# ============================================================================
# PUBLIC API
# ============================================================================

static func get_mission_by_id(mission_id: String) -> Dictionary:
	"""Get a single mission definition by ID. Returns empty dict if not found."""
	_ensure_loaded()
	return _missions.get(mission_id, {})

static func get_mission_ids_for_deck(include_challenger: bool = false) -> Array:
	"""Get the list of all mission IDs for building a tactical deck (18 cards)."""
	_ensure_loaded()
	var ids = []
	for id in _missions:
		ids.append(id)
	return ids

static func get_all_missions() -> Dictionary:
	"""Get the full missions dictionary."""
	_ensure_loaded()
	return _missions.duplicate(true)

static func get_missions_by_category(category: String) -> Array:
	"""Get all missions in a given category."""
	_ensure_loaded()
	var result = []
	for id in _missions:
		if _missions[id]["category"] == category:
			result.append(_missions[id])
	return result

static func get_mission_display_text(mission: Dictionary) -> String:
	"""Get a short display summary of a mission for UI."""
	var desc = mission.get("description", "")
	var category = mission.get("category", "")
	var scoring = mission.get("scoring", {})
	var conditions = scoring.get("conditions", [])

	var vp_text = ""
	if conditions.size() > 0:
		var max_vp = 0
		for c in conditions:
			max_vp = max(max_vp, c.get("vp", 0))
		vp_text = "Up to %d VP" % max_vp

	return "%s\n%s" % [desc, vp_text]

static func get_mission_instructions(mission_id: String) -> String:
	"""Get detailed instructions for a mission, suitable for display on a card."""
	match mission_id:
		"behind_enemy_lines":
			return "At the end of your turn, if two or more of your units (excluding Battle-shocked) are wholly within your opponent's deployment zone, you score 5 VP. Otherwise, if one or more such units are wholly within the opponent's deployment zone, you score 2 VP.\n\nNote: If drawn in the first battle round, this card must be shuffled back into your deck."
		"engage_on_all_fronts":
			return "At the end of your turn, score VP based on how many different table quarters contain at least one of your units (excluding Battle-shocked) that is more than 6\" from the centre of the battlefield.\n• 4 quarters: 5 VP\n• 3 quarters: 3 VP\n• 2 quarters: 2 VP"
		"area_denial":
			return "At the end of your turn, if you have one or more units (excluding Battle-shocked) within 6\" of the centre of the battlefield:\n• If no enemy units are within 6\" of the centre: 5 VP\n• If no enemy units are within 3\" of the centre: 3 VP"
		"display_of_might":
			return "At the end of your turn, if you have more units wholly within No Man's Land than your opponent, you score 5 VP."
		"storm_hostile_objective":
			return "At the end of your turn, score VP for controlling objective markers that were controlled by your opponent at the start of the turn.\n• 2 or more such objectives: 5 VP\n• 1 such objective: 2 VP\n\nIf your opponent controlled no objectives at the start of your turn (from round 2 onwards) and you control at least one, score 2 VP."
		"defend_stronghold":
			return "At the end of your turn, score VP for controlling objective markers that are within your own deployment zone.\n• 2 or more objectives: 5 VP\n• 1 objective: 2 VP"
		"secure_no_mans_land":
			return "At the end of your turn, score VP for controlling objective markers that are in No Man's Land.\n• 2 or more objectives: 5 VP\n• 1 objective: 2 VP"
		"a_tempting_target":
			return "When this card is drawn, your opponent selects one objective marker in No Man's Land. At the end of either player's turn, if you control that objective marker, you score 5 VP."
		"extend_battle_lines":
			return "At the end of your turn, if you control at least one objective marker in your deployment zone AND at least one objective marker in No Man's Land, you score 5 VP."
		"assassination":
			return "At the end of either player's turn:\n• If all enemy CHARACTER models have been destroyed: 5 VP\n• If at least one enemy CHARACTER model was destroyed this turn: 3 VP"
		"bring_it_down":
			return "At the end of either player's turn, score VP for enemy MONSTER or VEHICLE units destroyed this turn.\n• 2 or more destroyed: 5 VP\n• 1 destroyed: 3 VP"
		"cull_the_horde":
			return "At the end of either player's turn, score VP for enemy INFANTRY units (starting strength 13+) destroyed this turn.\n• 2 or more destroyed: 5 VP\n• 1 destroyed: 3 VP"
		"marked_for_death":
			return "When this card is drawn, your opponent selects 3 of their units as Alpha targets and you select 1 Gamma target from remaining units. At the end of either player's turn:\n• If an Alpha target was destroyed this turn: 5 VP\n• If no Alpha target was destroyed, but a Gamma target was: 2 VP"
		"no_prisoners":
			return "While this mission is active, each time an enemy unit is destroyed, you score 2 VP (max 5 VP per scoring)."
		"overwhelming_force":
			return "While this mission is active, each time an enemy unit is destroyed within range of an objective marker, you score 3 VP (max 5 VP per scoring)."
		"establish_locus":
			return "One of your units can perform the 'Establish Locus' action during the Shooting phase. At the end of your turn:\n• If a locus was established in the opponent's deployment zone: 5 VP\n• If a locus was established within 6\" of the centre: 3 VP"
		"cleanse":
			return "One of your units can perform the 'Cleanse' action during the Shooting phase to cleanse an objective marker it controls. At the end of your turn:\n• 2 or more objectives cleansed: 5 VP\n• 1 objective cleansed: 2 VP"
		"deploy_teleport_homer":
			return "One of your units can perform the 'Deploy Teleport Homer' action during the Shooting phase. At the end of your turn:\n• Homer deployed in opponent's deployment zone: 5 VP\n• Homer deployed elsewhere (not in opponent's zone): 3 VP"
		_:
			return ""

static func get_human_readable_condition(check: String, params: Dictionary = {}, vp: int = 0) -> String:
	"""Convert a scoring condition check ID and params into human-readable text."""
	match check:
		"units_wholly_in_opponent_deployment_zone":
			var count = params.get("count", 1)
			return "%d+ units wholly in opponent's deployment zone" % count
		"presence_in_table_quarters":
			var count = params.get("count", 1)
			return "Units in %d+ table quarters (>6\" from centre)" % count
		"units_within_center_no_enemies_within":
			var enemy_range = params.get("enemy_range", 6.0)
			return "Your units within 6\" of centre, no enemies within %d\"" % int(enemy_range)
		"more_units_wholly_in_no_mans_land_than_opponent":
			return "More units wholly in No Man's Land than opponent"
		"control_objectives_opponent_controlled_at_start":
			var count = params.get("count", 1)
			return "Control %d+ objectives your opponent held at turn start" % count
		"opponent_controlled_no_objectives_at_start_and_you_control_new":
			return "Opponent held no objectives at turn start, you control one (round 2+)"
		"control_objectives_in_own_deployment_zone":
			var count = params.get("count", 1)
			return "Control %d+ objectives in your deployment zone" % count
		"control_objectives_in_no_mans_land":
			var count = params.get("count", 1)
			return "Control %d+ objectives in No Man's Land" % count
		"control_tempting_target":
			return "Control the objective your opponent selected"
		"control_own_zone_and_nml_objectives":
			return "Control 1+ objective in your zone AND 1+ in No Man's Land"
		"all_enemy_characters_destroyed":
			return "All enemy CHARACTER models destroyed"
		"character_models_destroyed_this_turn":
			var count = params.get("count", 1)
			return "%d+ enemy CHARACTER model(s) destroyed this turn" % count
		"monster_or_vehicle_destroyed_this_turn":
			var count = params.get("count", 1)
			return "%d+ enemy MONSTER/VEHICLE destroyed this turn" % count
		"infantry_starting_strength_13_plus_destroyed_this_turn":
			var count = params.get("count", 1)
			return "%d+ enemy INFANTRY (13+ starting strength) destroyed this turn" % count
		"alpha_target_destroyed_this_turn":
			return "An Alpha target destroyed this turn"
		"no_alpha_destroyed_but_gamma_destroyed_this_turn":
			return "No Alpha destroyed, but a Gamma target was destroyed"
		"enemy_unit_destroyed":
			return "An enemy unit is destroyed"
		"enemy_unit_destroyed_within_objective_range":
			return "An enemy unit destroyed within range of an objective"
		"locus_established_in_opponent_deployment_zone":
			return "Locus established in opponent's deployment zone"
		"locus_established_within_center":
			return "Locus established within 6\" of centre"
		"objectives_cleansed":
			var count = params.get("count", 1)
			return "%d+ objectives cleansed this turn" % count
		"teleport_homer_deployed_in_opponent_zone":
			return "Teleport Homer deployed in opponent's deployment zone"
		"teleport_homer_deployed_not_in_opponent_zone":
			return "Teleport Homer deployed (not in opponent's zone)"
		_:
			return check.replace("_", " ").capitalize()
