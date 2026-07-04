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
		# 11e official (40kdc launch data): 3 VP PER qualifying unit, max 5.
		"scoring_11e": {
			"when": TIMING_END_OF_YOUR_TURN,
			"conditions": [
				{"check": "units_wholly_in_opponent_deployment_zone", "per_count": true, "params": {"exclude": ["Battle-shocked", "Aircraft"]}, "vp": 3, "vp_max": 5},
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
		# 11e official: mode-split tiers — Fixed 2/4, Tactical 3/5 (quarters 3/4).
		"scoring_11e": {
			"when": TIMING_END_OF_YOUR_TURN,
			"conditions": [
				{"check": "presence_in_table_quarters", "params": {"count": 3, "min_distance_from_center": 6.0, "exclude": ["Battle-shocked", "Aircraft"]}, "vp": 2, "mode": "fixed"},
				{"check": "presence_in_table_quarters", "params": {"count": 4, "min_distance_from_center": 6.0, "exclude": ["Battle-shocked", "Aircraft"]}, "vp": 4, "mode": "fixed"},
				{"check": "presence_in_table_quarters", "params": {"count": 3, "min_distance_from_center": 6.0, "exclude": ["Battle-shocked", "Aircraft"]}, "vp": 3, "mode": "tactical"},
				{"check": "presence_in_table_quarters", "params": {"count": 4, "min_distance_from_center": 6.0, "exclude": ["Battle-shocked", "Aircraft"]}, "vp": 5, "mode": "tactical"},
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
		# 11e official: 2 VP at the end of YOUR turn, 5 VP at the end of the
		# OPPONENT's turn (more units wholly in NML than the opponent).
		"scoring_11e": {
			"when": TIMING_END_OF_EITHER_TURN,
			"conditions": [
				{"check": "more_units_wholly_in_no_mans_land_than_opponent", "params": {"exclude": ["Battle-shocked", "Aircraft"]}, "vp": 2, "timing": "your_turn"},
				{"check": "more_units_wholly_in_no_mans_land_than_opponent", "params": {"exclude": ["Battle-shocked", "Aircraft"]}, "vp": 5, "timing": "opponent_turn"},
			],
		},
		"requires_action": false,
		"action": {},
		"when_drawn": {"condition": "fewer_than_3_units_or_incursion"},
		"when_drawn_11e": {},  # official 11e card has no when-drawn effect
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
		# 11e official: from round 2, at the end of the OPPONENT's turn —
		# 3 VP for holding your home objective + cumulative 2 VP if no enemy
		# units are wholly within your deployment zone. Redraw in round 1.
		"scoring_11e": {
			"when": TIMING_END_OF_OPPONENT_TURN,
			"min_round": 2,
			"conditions": [
				{"check": "control_objectives_in_own_deployment_zone", "params": {"count": 1}, "vp": 3},
				{"check": "no_enemy_units_wholly_in_own_deployment_zone", "params": {}, "vp": 2, "cumulative": true},
			],
		},
		"requires_action": false,
		"action": {},
		"when_drawn": {},
		"when_drawn_11e": {"condition": "first_battle_round", "effect": EFFECT_MANDATORY_SHUFFLE_BACK},
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
		# 11e official: flat 5 VP for controlling 2+ NML objectives (no 2 VP tier).
		"scoring_11e": {
			"when": TIMING_END_OF_YOUR_TURN,
			"conditions": [
				{"check": "control_objectives_in_no_mans_land", "params": {"count": 2, "exclude": "home"}, "vp": 5},
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
		# 11e official: scored at the end of YOUR turn only.
		"scoring_11e": {
			"when": TIMING_END_OF_YOUR_TURN,
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
		# 11e official — mode split:
		#   Fixed: 3 VP per enemy CHARACTER model destroyed this turn
		#          + cumulative 1 VP per such model with W4+ (uncapped).
		#   Tactical: flat 5 VP when 1+ destroyed this turn (either turn).
		"scoring_11e": {
			"when": TIMING_END_OF_EITHER_TURN,
			"conditions": [
				{"check": "enemy_character_models_destroyed_this_turn", "per_count": true, "params": {}, "vp": 3, "mode": "fixed"},
				{"check": "enemy_character_models_destroyed_this_turn", "per_count": true, "params": {"min_wounds": 4}, "vp": 1, "cumulative": true, "mode": "fixed"},
				{"check": "character_models_destroyed_this_turn", "params": {"count": 1}, "vp": 5, "mode": "tactical"},
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
		# 11e official — per-MODEL scoring for enemy models with W10+:
		#   Fixed: 4 VP per model (uncapped). Tactical: 5 VP per model, max 5.
		"scoring_11e": {
			"when": TIMING_END_OF_EITHER_TURN,
			"conditions": [
				{"check": "enemy_models_wounds_10_plus_destroyed_this_turn", "per_count": true, "params": {"min_wounds": 10}, "vp": 4, "mode": "fixed"},
				{"check": "enemy_models_wounds_10_plus_destroyed_this_turn", "per_count": true, "params": {"min_wounds": 10}, "vp": 5, "vp_max": 5, "mode": "tactical"},
			],
		},
		"requires_action": false,
		"action": {},
		"when_drawn": {"condition": "no_enemy_monster_or_vehicle"},
		# 11e official: replace (discard and redraw) if the opponent has no
		# unit containing a model with a Wounds characteristic of 10+.
		"when_drawn_11e": {"condition": "no_enemy_model_wounds_10_plus", "details": {"min_wounds": 10}},
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
		# 11e official: 2 VP per enemy unit destroyed this turn, max 5,
		# tallied at the end of either player's turn.
		"scoring_11e": {
			"when": TIMING_END_OF_EITHER_TURN,
			"conditions": [
				{"check": "enemy_units_destroyed_this_turn", "per_count": true, "params": {}, "vp": 2, "vp_max": 5},
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
		# 11e official: 3 VP per enemy unit destroyed while within range of
		# an objective, max 5, tallied at the end of either player's turn.
		"scoring_11e": {
			"when": TIMING_END_OF_EITHER_TURN,
			"conditions": [
				{"check": "enemy_units_destroyed_near_objective_this_turn", "per_count": true, "params": {}, "vp": 3, "vp_max": 5},
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
		# 11e official: scoring tiers are identical to 10e (1 cleansed = 2 VP,
		# 2+ = 5 VP), but Plunder and Cleanse mutually redraw — if Plunder is
		# active for you when this is drawn, shuffle it back and draw again.
		"when_drawn_11e": {"condition": "other_mission_active", "details": {"mission_id": "plunder"}, "effect": EFFECT_MANDATORY_SHUFFLE_BACK},
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

	# ====================================================================
	# 11e DECK ADDITIONS — official launch data from the 40kdc dataset
	# (@alpaca-software/40kdc-data 1.0.19, 40k/data/40kdc/*.json). These
	# cards only exist in the 11e deck, so their official awards live in
	# the plain "scoring"/"when_drawn" keys. Cards whose full mechanic is
	# not modelled in-engine (Beacon designation, Burden of Trust guard
	# selection) keep "approximate": true.
	# ====================================================================

	_missions["a_grievous_blow"] = {
		"id": "a_grievous_blow",
		"name": "A Grievous Blow",
		"number": 19,
		"category": "Purge the Enemy",
		"edition": 11,
		"description": "Destroy enemy units with a Starting Strength of 13+ models.",
		# Official: per enemy 13+-strong unit destroyed this turn —
		# Fixed 4 VP each (uncapped); Tactical 5 VP each, max 5.
		"scoring": {
			"when": TIMING_END_OF_EITHER_TURN,
			"conditions": [
				{"check": "enemy_units_13_plus_destroyed_this_turn", "per_count": true, "params": {"min_models": 13}, "vp": 4, "mode": "fixed"},
				{"check": "enemy_units_13_plus_destroyed_this_turn", "per_count": true, "params": {"min_models": 13}, "vp": 5, "vp_max": 5, "mode": "tactical"},
			],
		},
		"requires_action": false,
		"action": {},
		# Official: replace (discard and redraw) if the opponent has no unit
		# with a Starting Strength of 13+ models on the battlefield.
		"when_drawn": {"condition": "no_enemy_unit_13_plus_models", "details": {"min_models": 13}},
	}

	_missions["forward_position"] = {
		"id": "forward_position",
		"name": "Forward Position",
		"number": 20,
		"category": "Battlefield Supremacy",
		"edition": 11,
		"description": "Control your opponent's home objective and/or an expansion objective.",
		# Official: 5 VP at the end of your turn while you control the
		# opponent's home objective OR 1+ expansion objective. Redraw round 1.
		"scoring": {
			"when": TIMING_END_OF_YOUR_TURN,
			"conditions": [
				{"check": "holds_enemy_home_objective", "params": {}, "vp": 5},
			],
		},
		"requires_action": false,
		"action": {},
		"when_drawn": {"condition": "first_battle_round", "effect": EFFECT_MANDATORY_SHUFFLE_BACK},
	}

	_missions["burden_of_trust"] = {
		"id": "burden_of_trust",
		"name": "Burden of Trust",
		"number": 21,
		"category": "Battlefield Supremacy",
		"edition": 11,
		# Guard-unit selection is auto-resolved: every objective you control
		# counts as guarded (controlling implies a friendly unit in range).
		"approximate": true,
		"description": "Guard objectives — score per guarded objective at the end of your opponent's turn.",
		# Official: 2 VP per guarded objective, max 5, end of OPPONENT's turn.
		"scoring": {
			"when": TIMING_END_OF_OPPONENT_TURN,
			"conditions": [
				{"check": "guarded_objectives", "per_count": true, "params": {}, "vp": 2, "vp_max": 5},
			],
		},
		"requires_action": false,
		"action": {},
		"when_drawn": {},
	}

	_missions["centre_ground"] = {
		"id": "centre_ground",
		"name": "Centre Ground",
		"number": 22,
		"category": "Battlefield Supremacy",
		"edition": 11,
		"description": "Own the middle: friendly units within 3\" of the centre, enemies pushed back.",
		# Official tiers (exclusive — best applies): 3 VP while 1+ friendly
		# units are within 3" of the centre with no enemy within 3" of it;
		# 5 VP when no enemy units are within 6" of the centre.
		"scoring": {
			"when": TIMING_END_OF_YOUR_TURN,
			"conditions": [
				{"check": "units_within_center_no_enemies_within", "params": {"friendly_range": 3.0, "enemy_range": 3.0, "exclude": ["Battle-shocked", "Aircraft"]}, "vp": 3},
				{"check": "units_within_center_no_enemies_within", "params": {"friendly_range": 3.0, "enemy_range": 6.0, "exclude": ["Battle-shocked", "Aircraft"]}, "vp": 5},
			],
		},
		"requires_action": false,
		"action": {},
		"when_drawn": {},
	}

	_missions["beacon"] = {
		"id": "beacon",
		"name": "Beacon",
		"number": 23,
		"category": "Shadow Operations",
		"edition": 11,
		# Beacon designation is auto-resolved (any qualifying friendly unit
		# counts) and "your territory" is approximated as your board half.
		"approximate": true,
		"description": "Your Beacon unit pushes into enemy-held ground; scored at the end of your opponent's turn.",
		# Official tiers (exclusive — best applies): 3 VP if the beacon unit
		# is on the battlefield and not within your deployment zone; 5 VP if
		# it is on the battlefield and not within your territory.
		"scoring": {
			"when": TIMING_END_OF_OPPONENT_TURN,
			"conditions": [
				{"check": "unit_outside_own_dz", "params": {}, "vp": 3},
				{"check": "unit_outside_own_territory", "params": {}, "vp": 5},
			],
		},
		"requires_action": false,
		"action": {},
		"when_drawn": {},
	}

	_missions["outflank"] = {
		"id": "outflank",
		"name": "Outflank",
		"number": 24,
		"category": "Battlefield Supremacy",
		"edition": 11,
		"description": "Sweep the flanks: units within 6\" of battlefield edges, outside your territory.",
		# Official tiers (exclusive — best applies): 3 VP for 1+ units within
		# 6" of a battlefield edge and not within your territory; 5 VP for 2+
		# such units within 6" of OPPOSITE (parallel) edges with at least one
		# of them not within your territory.
		"scoring": {
			"when": TIMING_END_OF_YOUR_TURN,
			"conditions": [
				{"check": "units_near_board_edges", "params": {"count": 1, "edge_inches": 6.0, "outside_own_territory": true, "exclude": ["Battle-shocked", "Aircraft"]}, "vp": 3},
				{"check": "units_near_board_edges", "params": {"opposite_edges": true, "edge_inches": 6.0, "exclude": ["Battle-shocked", "Aircraft"]}, "vp": 5},
			],
		},
		"requires_action": false,
		"action": {},
		"when_drawn": {},
	}

	_missions["plunder"] = {
		"id": "plunder",
		"name": "Plunder",
		"number": 25,
		"category": "Shadow Operations",
		"edition": 11,
		"description": "Plunder a terrain feature (Shooting-phase action, once per turn).",
		# Official: flat 5 VP at the end of your turn if the Plunder action
		# was completed this turn (Shooting phase; one unit within a terrain
		# area outside your territory; once per turn).
		"scoring": {
			"when": TIMING_END_OF_YOUR_TURN,
			"conditions": [
				{"check": "action_completed_this_turn", "params": {"count": 1, "action_name": "Plunder"}, "vp": 5},
			],
		},
		"requires_action": true,
		"action": {"name": "Plunder", "phase": "shooting"},
		# Official: Plunder and Cleanse mutually redraw — if Cleanse is active
		# for you when this is drawn, shuffle it back and draw again.
		"when_drawn": {"condition": "other_mission_active", "details": {"mission_id": "cleanse"}, "effect": EFFECT_MANDATORY_SHUFFLE_BACK},
	}

# ============================================================================
# PUBLIC API
# ============================================================================

static func get_mission_by_id(mission_id: String) -> Dictionary:
	"""Get a single mission definition by ID. Returns empty dict if not found."""
	_ensure_loaded()
	return _missions.get(mission_id, {})

## 11e (GDM 2026) 18-card tactical deck — the four returning-with-tweaks
## cards keep their existing implementations; new cards are authored above.
static func get_mission_ids_for_deck_11e() -> Array:
	_ensure_loaded()
	return [
		"assassination", "a_grievous_blow", "bring_it_down", "engage_on_all_fronts",
		"behind_enemy_lines", "no_prisoners", "cleanse", "defend_stronghold",
		"overwhelming_force", "forward_position", "burden_of_trust", "centre_ground",
		"a_tempting_target", "secure_no_mans_land", "beacon", "display_of_might",
		"outflank", "plunder",
	]

## 11e Fixed mode: exactly these four cards are fixed-eligible.
static func get_fixed_eligible_11e() -> Array:
	return ["assassination", "a_grievous_blow", "bring_it_down", "engage_on_all_fronts"]

static func get_mission_ids_for_deck(include_challenger: bool = false) -> Array:
	"""Get the list of 10e mission IDs for building a tactical deck (18 cards).
	Cards tagged edition: 11 are 11e-only and must NOT leak into the 10e deck."""
	_ensure_loaded()
	var ids = []
	for id in _missions:
		if int(_missions[id].get("edition", 10)) >= 11:
			continue
		ids.append(id)
	return ids

## Resolve the scoring block for the active edition. Cards shared between
## editions carry their official 11e awards under "scoring_11e"; cards
## without an override use "scoring" in both editions.
static func get_scoring(mission: Dictionary) -> Dictionary:
	if GameConstants.edition >= 11 and mission.has("scoring_11e"):
		return mission["scoring_11e"]
	return mission.get("scoring", {})

## Resolve the when-drawn block for the active edition (see get_scoring).
static func get_when_drawn(mission: Dictionary) -> Dictionary:
	if GameConstants.edition >= 11 and mission.has("when_drawn_11e"):
		return mission["when_drawn_11e"]
	return mission.get("when_drawn", {})

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
	var scoring = get_scoring(mission)
	var conditions = scoring.get("conditions", [])

	var vp_text = ""
	if conditions.size() > 0:
		var max_vp = 0
		for c in conditions:
			max_vp = max(max_vp, c.get("vp", 0))
		vp_text = "Up to %d VP" % max_vp

	return "%s\n%s" % [desc, vp_text]

static func get_mission_instructions(mission_id: String) -> String:
	"""Get detailed instructions for a mission, suitable for display on a card.
	At 11e, cards in the 11e deck return their official launch-data text."""
	if GameConstants.edition >= 11:
		var text_11e = _get_mission_instructions_11e(mission_id)
		if text_11e != "":
			return text_11e
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

static func _get_mission_instructions_11e(mission_id: String) -> String:
	"""Official 11e (40kdc launch data) instruction text for the 18-card deck."""
	match mission_id:
		"behind_enemy_lines":
			return "At the end of your turn, score 3 VP for each of your units (excluding AIRCRAFT and Battle-shocked) wholly within your opponent's deployment zone, up to a maximum of 5 VP.\n\nIf drawn in the first battle round, draw a new card and shuffle this one back into your deck."
		"engage_on_all_fronts":
			return "You have a presence in a table quarter while one or more of your units (excluding AIRCRAFT and Battle-shocked) are wholly within it and more than 6\" from the centre of the battlefield. At the end of your turn:\n• Fixed: 3 quarters = 2 VP, 4 quarters = 4 VP\n• Tactical: 3 quarters = 3 VP, 4 quarters = 5 VP\nOnly the better tier scores."
		"display_of_might":
			return "While more of your units than enemy units (excluding AIRCRAFT and Battle-shocked) are wholly within No Man's Land:\n• End of your turn: 2 VP\n• End of your opponent's turn: 5 VP"
		"assassination":
			return "Fixed: at the end of either player's turn, score 3 VP for each enemy CHARACTER model destroyed this turn, plus 1 VP for each such model that had a Wounds characteristic of 4 or more.\n\nTactical: score 5 VP at the end of either player's turn if one or more enemy CHARACTER models were destroyed this turn."
		"bring_it_down":
			return "At the end of either player's turn, score for each enemy model with a Wounds characteristic of 10 or more destroyed this turn:\n• Fixed: 4 VP each (uncapped)\n• Tactical: 5 VP each (max 5 VP)\n\nIf the opponent has no such models on the battlefield when drawn, discard this card and draw a new one."
		"a_grievous_blow":
			return "At the end of either player's turn, score for each enemy unit with a Starting Strength of 13 or more models destroyed this turn:\n• Fixed: 4 VP each (uncapped)\n• Tactical: 5 VP each (max 5 VP)\n\nIf the opponent has no such units on the battlefield when drawn, discard this card and draw a new one."
		"no_prisoners":
			return "At the end of either player's turn, score 2 VP for each enemy unit destroyed this turn, up to a maximum of 5 VP."
		"overwhelming_force":
			return "At the end of either player's turn, score 3 VP for each enemy unit destroyed this turn that was within range of an objective marker, up to a maximum of 5 VP."
		"centre_ground":
			return "At the end of your turn:\n• 3 VP if one or more of your units (excluding AIRCRAFT and Battle-shocked) are within 3\" of the centre of the battlefield and no enemy units are within 3\" of it\n• 5 VP if additionally no enemy units are within 6\" of the centre\nOnly the better tier scores."
		"outflank":
			return "At the end of your turn:\n• 3 VP if one or more of your units (excluding AIRCRAFT and Battle-shocked) are within 6\" of a battlefield edge and not within your territory\n• 5 VP if two or more such units are within 6\" of opposite battlefield edges and at least one of them is not within your territory\nOnly the better tier scores."
		"secure_no_mans_land":
			return "At the end of your turn, score 5 VP while you control two or more objective markers in No Man's Land (not counting your home objective)."
		"forward_position":
			return "At the end of your turn, score 5 VP while you control your opponent's home objective and/or an expansion objective.\n\nIf drawn in the first battle round, draw a new card and shuffle this one back into your deck."
		"a_tempting_target":
			return "When drawn, your opponent selects one objective marker (excluding home objectives) in No Man's Land as your tempting target. At the end of your turn, score 5 VP while you control it."
		"defend_stronghold":
			return "From the second battle round, at the end of your opponent's turn:\n• 3 VP if you control your home objective\n• +2 VP while no enemy units are wholly within your deployment zone\n\nIf drawn in the first battle round, draw a new card and shuffle this one back into your deck."
		"burden_of_trust":
			return "At the start of each of your turns you can select one friendly unit per objective to guard it. At the end of your opponent's turn, score 2 VP for each guarded objective you control, up to a maximum of 5 VP."
		"beacon":
			return "When drawn, one of your units on the battlefield becomes your beacon unit. At the end of your opponent's turn:\n• 3 VP if the beacon unit is on the battlefield and not within your deployment zone\n• 5 VP if it is on the battlefield and not within your territory\nOnly the better tier scores."
		"cleanse":
			return "Your units within range of a non-home objective marker can perform the 'Cleanse' action during the Shooting phase. At the end of your turn:\n• 1 objective cleansed: 2 VP\n• 2 or more objectives cleansed: 5 VP\n\nIf Plunder is active for you when this is drawn, draw a new card and shuffle this one back into your deck."
		"plunder":
			return "One of your units within a terrain feature outside your territory can perform the 'Plunder' action during the Shooting phase (once per turn). At the end of your turn, score 5 VP if a terrain feature was plundered this turn.\n\nIf Cleanse is active for you when this is drawn, draw a new card and shuffle this one back into your deck."
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
		# 11e (official launch data) checks
		"enemy_units_destroyed_this_turn":
			return "Per enemy unit destroyed this turn"
		"enemy_units_destroyed_near_objective_this_turn":
			return "Per enemy unit destroyed within range of an objective"
		"enemy_character_models_destroyed_this_turn":
			var min_w = int(params.get("min_wounds", 0))
			if min_w > 0:
				return "Per enemy CHARACTER model (W%d+) destroyed this turn" % min_w
			return "Per enemy CHARACTER model destroyed this turn"
		"enemy_models_wounds_10_plus_destroyed_this_turn":
			return "Per enemy model (W%d+) destroyed this turn" % int(params.get("min_wounds", 10))
		"enemy_units_13_plus_destroyed_this_turn":
			return "Per enemy unit (%d+ models) destroyed this turn" % int(params.get("min_models", 13))
		"guarded_objectives":
			return "Per objective you guard (control)"
		"no_enemy_units_wholly_in_own_deployment_zone":
			return "No enemy units wholly within your deployment zone"
		"holds_enemy_home_objective":
			return "Control opponent's home or an expansion objective"
		"units_near_board_edges":
			if params.get("opposite_edges", false):
				return "Units within %d\" of opposite battlefield edges" % int(params.get("edge_inches", 6.0))
			return "Unit within %d\" of a battlefield edge, outside your territory" % int(params.get("edge_inches", 6.0))
		"unit_outside_own_dz":
			return "Beacon unit outside your deployment zone"
		"unit_outside_own_territory":
			return "Beacon unit outside your territory"
		"action_completed_this_turn":
			return "%s action completed this turn" % str(params.get("action_name", "Mission"))
		_:
			return check.replace("_", " ").capitalize()
