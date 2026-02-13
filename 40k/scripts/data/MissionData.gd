extends RefCounted
class_name MissionData

# MissionData - Static definitions for all primary missions
# Each mission defines its name, scoring rules, and special mechanics.

# All supported mission types
const MISSION_TYPES = [
	"take_and_hold",
	"scorched_earth",
	"supply_drop",
	"purge_the_foe",
	"sites_of_power"
]

# Returns the full mission definition for a given mission type
static func get_mission(mission_type: String) -> Dictionary:
	match mission_type:
		"take_and_hold":
			return _take_and_hold()
		"scorched_earth":
			return _scorched_earth()
		"supply_drop":
			return _supply_drop()
		"purge_the_foe":
			return _purge_the_foe()
		"sites_of_power":
			return _sites_of_power()
		_:
			push_warning("MissionData: Unknown mission type '%s', falling back to take_and_hold" % mission_type)
			return _take_and_hold()

# Returns display name for a mission type
static func get_display_name(mission_type: String) -> String:
	match mission_type:
		"take_and_hold":
			return "Take and Hold"
		"scorched_earth":
			return "Scorched Earth"
		"supply_drop":
			return "Supply Drop"
		"purge_the_foe":
			return "Purge the Foe"
		"sites_of_power":
			return "Sites of Power"
		_:
			return mission_type

# ============================================================
# MISSION DEFINITIONS
# ============================================================

# Take and Hold: Simple objective holding
# - 5VP per objective held, max 15VP per turn
# - Scoring from Round 2 Command phase
# - Player going second scores end of Turn 5
static func _take_and_hold() -> Dictionary:
	return {
		"id": "take_and_hold",
		"name": "Take and Hold",
		"type": "primary",
		"max_vp": 50,
		"scoring_type": "hold_objectives",
		"scoring_rules": {
			"when": "command_phase_end",
			"start_round": 2,
			"vp_per_objective": 5,
			"max_vp_per_turn": 15,
			"count_home_objectives": true  # Home objectives count for scoring
		},
		"special_rules": []
	}

# Scorched Earth: Hold objectives + burn enemy objectives for bonus VP
# - 5VP per objective held, max 10VP per turn (lower than Take and Hold)
# - Starting Round 2, one unit can start a burn action on a non-home objective
# - Burn completes at end of opponent's next turn
# - Burned objective is removed; +5VP for NML burn, +10VP for enemy home burn
static func _scorched_earth() -> Dictionary:
	return {
		"id": "scorched_earth",
		"name": "Scorched Earth",
		"type": "primary",
		"max_vp": 50,
		"scoring_type": "hold_and_burn",
		"scoring_rules": {
			"when": "command_phase_end",
			"start_round": 2,
			"vp_per_objective": 5,
			"max_vp_per_turn": 10,  # Lower cap than Take and Hold
			"count_home_objectives": true
		},
		"special_rules": ["burn_objectives"],
		"burn_rules": {
			"start_round": 2,
			"can_burn_home": false,  # Cannot burn your own home objective
			"can_burn_nml": true,
			"can_burn_enemy_home": true,
			"nml_burn_bonus_vp": 5,
			"enemy_home_burn_bonus_vp": 10,
			"completion_delay": "opponent_next_turn_end"  # Burns complete at end of opponent's next turn
		}
	}

# Supply Drop: Score only from no-man's-land objectives
# - 5VP per NML objective held, starting Round 2
# - Turn 4: Randomly remove one NML objective
# - Turn 5: Only one NML objective remains, worth bonus VP
static func _supply_drop() -> Dictionary:
	return {
		"id": "supply_drop",
		"name": "Supply Drop",
		"type": "primary",
		"max_vp": 50,
		"scoring_type": "supply_drop",
		"scoring_rules": {
			"when": "command_phase_end",
			"start_round": 2,
			"vp_per_objective": 5,
			"max_vp_per_turn": 15,
			"count_home_objectives": false  # Only NML objectives score
		},
		"special_rules": ["objective_removal"],
		"removal_rules": {
			"round_4_remove_count": 1,  # Remove 1 NML objective at start of Round 4
			"round_5_bonus_vp": 10  # Remaining NML objective is worth bonus VP in Round 5
		}
	}

# Purge the Foe: Comparative scoring based on holding AND destroying
# - 4VP for holding any objective, 8VP if holding more than opponent
# - 4VP for destroying any enemy unit that round, 8VP if destroyed more than opponent
# - Scored each Command phase from Round 2
static func _purge_the_foe() -> Dictionary:
	return {
		"id": "purge_the_foe",
		"name": "Purge the Foe",
		"type": "primary",
		"max_vp": 50,
		"scoring_type": "purge_the_foe",
		"scoring_rules": {
			"when": "command_phase_end",
			"start_round": 2,
			"hold_any_vp": 4,
			"hold_more_vp": 8,
			"kill_any_vp": 4,
			"kill_more_vp": 8,
			"max_vp_per_turn": 16,  # 8 (hold more) + 8 (kill more)
			"count_home_objectives": true
		},
		"special_rules": ["track_kills"]
	}

# Sites of Power: Character-based objective scoring
# - Place a CHARACTER on a NML objective to claim it
# - 5VP when character first claims the objective
# - Continues to award 3VP each round the character stays, even if opponent takes control
static func _sites_of_power() -> Dictionary:
	return {
		"id": "sites_of_power",
		"name": "Sites of Power",
		"type": "primary",
		"max_vp": 50,
		"scoring_type": "sites_of_power",
		"scoring_rules": {
			"when": "command_phase_end",
			"start_round": 2,
			"vp_per_objective": 5,
			"max_vp_per_turn": 15,
			"character_claim_vp": 5,  # VP for first claiming with a character
			"character_hold_vp": 3,  # VP each round character stays
			"count_home_objectives": true
		},
		"special_rules": ["character_objectives"]
	}
