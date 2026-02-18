extends RefCounted
class_name MissionData

# MissionData - Static definitions for all primary missions
# Based on Chapter Approved 2025-26 rules
#
# Each mission is defined with:
#   id, name, description, scoring_type, scoring rules (VP values, caps, start round),
#   special_rules flags, and objective_count.
#
# Scoring types:
#   "hold_objectives" — VP based on number of objectives controlled (Take and Hold, Vital Ground)
#   "hold_and_burn" — VP for holding + bonus VP for burning objectives (Scorched Earth)
#   "hold_and_kill" — VP for holding objectives AND destroying enemy units (Purge the Foe)
#   "supply_drop" — Only NML objectives score; objectives removed mid-game (Supply Drop)
#   "sites_of_power" — Character-on-objective tracking (Sites of Power)
#   "ritual" — Action-based objective creation (The Ritual)
#   "terraform" — Flip objectives between players (Terraform)
#   "hidden_supplies" — Extra objectives placed during the game (Hidden Supplies)
#   "linchpin" — Central objective worth more VP (Linchpin)

# ============================================================================
# CONSTANTS
# ============================================================================

const MAX_PRIMARY_VP: int = 50
const MAX_COMBINED_VP: int = 90  # Primary + Secondary cap

# ============================================================================
# MISSION REGISTRY
# ============================================================================

static var _missions: Dictionary = {}

static func _ensure_loaded() -> void:
	if _missions.is_empty():
		_load_missions()

static func _load_missions() -> void:
	# ====================================================================
	# TAKE AND HOLD — The default / simplest primary mission
	# ====================================================================
	_missions["take_and_hold"] = {
		"id": "take_and_hold",
		"name": "Take and Hold",
		"description": "Score VP by controlling objectives at the end of your Command phase.",
		"scoring_type": "hold_objectives",
		"start_round": 2,
		"objectives_used": "all",  # all 5 objectives
		"scoring": {
			"vp_per_objective": 5,
			"max_vp_per_turn": 15,
		},
		"max_vp": MAX_PRIMARY_VP,
		"special_rules": [],
	}

	# ====================================================================
	# SUPPLY DROP — Only no-man's-land objectives; objectives removed mid-game
	# ====================================================================
	_missions["supply_drop"] = {
		"id": "supply_drop",
		"name": "Supply Drop",
		"description": "Only no-man's-land objectives score VP. One is removed in Round 4.",
		"scoring_type": "supply_drop",
		"start_round": 2,
		"objectives_used": "no_mans_land",  # Only NML objectives score
		"scoring": {
			"vp_per_objective": 5,
			"max_vp_per_turn": 15,
			"remove_random_nml_round": 4,  # Remove one NML objective at start of Round 4
		},
		"max_vp": MAX_PRIMARY_VP,
		"special_rules": ["nml_only_scoring", "objective_removal"],
	}

	# ====================================================================
	# PURGE THE FOE — Holding objectives + destroying enemy units
	# ====================================================================
	_missions["purge_the_foe"] = {
		"id": "purge_the_foe",
		"name": "Purge the Foe",
		"description": "Score VP for controlling objectives AND destroying enemy units.",
		"scoring_type": "hold_and_kill",
		"start_round": 2,
		"objectives_used": "all",
		"scoring": {
			# Holding component
			"hold_any_vp": 4,       # 4VP if you control any objective
			"hold_more_vp": 4,      # +4VP if you control more than opponent (total 8)
			# Kill component
			"kill_any_vp": 4,       # 4VP if you destroyed any enemy unit this turn
			"kill_more_vp": 4,      # +4VP if you destroyed more than opponent (total 8)
			"max_vp_per_turn": 16,  # Max 16VP per turn (8 hold + 8 kill)
		},
		"max_vp": MAX_PRIMARY_VP,
		"special_rules": ["kill_tracking"],
	}

	# ====================================================================
	# SCORCHED EARTH — Hold objectives + burn enemy/NML objectives
	# ====================================================================
	_missions["scorched_earth"] = {
		"id": "scorched_earth",
		"name": "Scorched Earth",
		"description": "Score VP for holding objectives. Burn NML/enemy objectives for bonus VP.",
		"scoring_type": "hold_and_burn",
		"start_round": 2,
		"objectives_used": "all",
		"scoring": {
			"vp_per_objective": 5,
			"max_vp_per_turn": 10,
			"burn_nml_vp": 5,       # +5VP for burning a NML objective
			"burn_enemy_vp": 10,    # +10VP for burning an enemy deployment zone objective
		},
		"max_vp": MAX_PRIMARY_VP,
		"special_rules": ["burn_objectives"],
	}

	# ====================================================================
	# THE RITUAL — Action-based: complete rituals to create scoring areas
	# ====================================================================
	_missions["the_ritual"] = {
		"id": "the_ritual",
		"name": "The Ritual",
		"description": "Perform ritual actions at objectives to create scoring zones.",
		"scoring_type": "ritual",
		"start_round": 2,
		"objectives_used": "all",
		"scoring": {
			"vp_per_ritual_complete": 5,
			"max_vp_per_turn": 15,
		},
		"max_vp": MAX_PRIMARY_VP,
		"special_rules": ["ritual_action"],
	}

	# ====================================================================
	# SITES OF POWER — Characters on NML objectives
	# ====================================================================
	_missions["sites_of_power"] = {
		"id": "sites_of_power",
		"name": "Sites of Power",
		"description": "Score VP by having Characters on no-man's-land objectives.",
		"scoring_type": "sites_of_power",
		"start_round": 2,
		"objectives_used": "all",
		"scoring": {
			"vp_per_character_on_nml_objective": 5,
			"max_vp_per_turn": 15,
		},
		"max_vp": MAX_PRIMARY_VP,
		"special_rules": ["character_objective_tracking"],
	}

	# ====================================================================
	# TERRAFORM — Flip objectives between players
	# ====================================================================
	_missions["terraform"] = {
		"id": "terraform",
		"name": "Terraform",
		"description": "Control and flip objectives to your side for VP.",
		"scoring_type": "terraform",
		"start_round": 2,
		"objectives_used": "all",
		"scoring": {
			"vp_per_flipped_objective": 5,
			"max_vp_per_turn": 15,
		},
		"max_vp": MAX_PRIMARY_VP,
		"special_rules": ["objective_flipping"],
	}

	# ====================================================================
	# LINCHPIN — Central objective worth extra VP
	# ====================================================================
	_missions["linchpin"] = {
		"id": "linchpin",
		"name": "Linchpin",
		"description": "The center objective is worth extra VP. Other objectives score normally.",
		"scoring_type": "hold_objectives",
		"start_round": 2,
		"objectives_used": "all",
		"scoring": {
			"vp_per_objective": 4,
			"vp_center_bonus": 4,   # Center objective worth 4+4=8 VP
			"max_vp_per_turn": 16,
		},
		"max_vp": MAX_PRIMARY_VP,
		"special_rules": ["center_bonus"],
	}

	# ====================================================================
	# HIDDEN SUPPLIES — Extra objectives placed during the game
	# ====================================================================
	_missions["hidden_supplies"] = {
		"id": "hidden_supplies",
		"name": "Hidden Supplies",
		"description": "Additional objectives appear mid-game for bonus scoring.",
		"scoring_type": "hold_objectives",
		"start_round": 2,
		"objectives_used": "all",
		"scoring": {
			"vp_per_objective": 5,
			"max_vp_per_turn": 15,
			"extra_objectives_round": 3,  # New objectives placed in Round 3
		},
		"max_vp": MAX_PRIMARY_VP,
		"special_rules": ["extra_objectives"],
	}

# ============================================================================
# PUBLIC API
# ============================================================================

## Get a mission definition by ID. Returns empty dict if not found.
static func get_mission(mission_id: String) -> Dictionary:
	_ensure_loaded()
	return _missions.get(mission_id, {})

## Get all mission IDs.
static func get_all_mission_ids() -> Array:
	_ensure_loaded()
	return _missions.keys()

## Get all mission definitions as a dictionary.
static func get_all_missions() -> Dictionary:
	_ensure_loaded()
	return _missions.duplicate(true)

## Get missions that only use basic "hold_objectives" scoring (no special mechanics needed).
## These are fully playable without additional game systems.
static func get_simple_missions() -> Array:
	_ensure_loaded()
	var simple = []
	for mission_id in _missions:
		var m = _missions[mission_id]
		if m.scoring_type == "hold_objectives" and m.special_rules.is_empty():
			simple.append(mission_id)
	return simple

## Get missions that are fully implemented (have scoring logic in MissionManager).
static func get_implemented_mission_ids() -> Array:
	_ensure_loaded()
	# These missions have full scoring logic implemented in MissionManager
	return [
		"take_and_hold",
		"supply_drop",
		"purge_the_foe",
		"linchpin",
		"sites_of_power",
	]

## Get display name for a mission.
static func get_display_name(mission_id: String) -> String:
	_ensure_loaded()
	var mission = _missions.get(mission_id, {})
	return mission.get("name", mission_id)

## Get description for a mission.
static func get_description(mission_id: String) -> String:
	_ensure_loaded()
	var mission = _missions.get(mission_id, {})
	return mission.get("description", "")

## Check if a mission has a particular special rule.
static func has_special_rule(mission_id: String, rule: String) -> bool:
	_ensure_loaded()
	var mission = _missions.get(mission_id, {})
	return rule in mission.get("special_rules", [])

## Get the maximum VP for a given mission.
static func get_max_vp(mission_id: String) -> int:
	_ensure_loaded()
	var mission = _missions.get(mission_id, {})
	return mission.get("max_vp", MAX_PRIMARY_VP)
