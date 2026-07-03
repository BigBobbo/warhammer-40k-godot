extends RefCounted
class_name PrimaryMissionData11e

# 11th-edition (GDM 2026) primary missions — Force Disposition pairing system.
# Source: docs/rules/11th_edition_missions_gdm2026.md (provided by the project
# owner; card images at gdmissions.app/11th).
#
# Each player picks a Force Disposition before the game. The primary mission
# card each player scores is determined by THEIR deck paired against the
# OPPONENT's disposition — so the two players usually play different cards.
#
# Rule dict schema (consumed by MissionManager._score_primary_11e):
#   when: "command" — scored at the end of your Command phase (GDM: switches
#                     to end of turn in battle round 5)
#         "eot"     — scored at the end of your turn
#         "eog"     — scored once at the end of the game
#   type: hold_min | per_objective | hold_more | hold_enemy_home |
#         hold_central | hold_central_plus_nml | hold_new | destroyed_min |
#         destroyed_per_unit | killed_more_than_opponent_last_turn |
#         quarters | action
#   vp / vp_per / vp_by_round: victory points awarded
#   rounds: [from, to] inclusive battle-round window (default all rounds)
#   approximate: the GDM source row had no exact card text for this component
#   type "action" components are NOT implemented yet (bespoke marker/action
#   mechanics) — they score nothing and are logged once per game.
#
# VP caps (GDM 2026): 45 primary total, 15 per turn.

const MAX_PRIMARY_VP_11E: int = 45
const MAX_PRIMARY_VP_PER_TURN_11E: int = 15

const DISPOSITIONS := [
	"take_and_hold",
	"purge_the_foe",
	"reconnaissance",
	"priority_assets",
	"disruption",
]

const DISPOSITION_NAMES := {
	"take_and_hold": "Take and Hold",
	"purge_the_foe": "Purge the Foe",
	"reconnaissance": "Reconnaissance",
	"priority_assets": "Priority Assets",
	"disruption": "Disruption",
}

static var _cards: Dictionary = {}

static func _ensure_loaded() -> void:
	if _cards.is_empty():
		_load_cards()

static func _add(card: Dictionary) -> void:
	_cards["%s|%s" % [card["deck"], card["played_vs"]]] = card

static func _load_cards() -> void:
	# ---- Take and Hold deck ----
	_add({
		"id": "battlefield_dominance", "name": "Battlefield Dominance",
		"deck": "take_and_hold", "played_vs": "take_and_hold",
		"rules": [
			{"when": "command", "type": "hold_more", "vp": 2, "rounds": [1, 2]},
			{"when": "command", "type": "per_objective", "vp_per": 3, "exclude_home": false, "rounds": [2, 5]},
		],
	})
	_add({
		"id": "immovable_object", "name": "Immovable Object",
		"deck": "take_and_hold", "played_vs": "purge_the_foe",
		"approximate": true,
		"rules": [
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": false, "vp": 4, "approximate": true},
			{"when": "command", "type": "hold_min", "min": 2, "exclude_home": false, "vp": 4, "approximate": true},
		],
	})
	_add({
		"id": "purge_and_secure", "name": "Purge and Secure",
		"deck": "take_and_hold", "played_vs": "reconnaissance",
		"approximate": true,
		"rules": [
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4},
			{"when": "command", "type": "hold_more", "vp": 4},
			{"when": "command", "type": "action", "action_name": "Kill on objectives / capture new"},
		],
	})
	_add({
		"id": "inescapable_dominion", "name": "Inescapable Dominion",
		"deck": "take_and_hold", "played_vs": "priority_assets",
		"approximate": true,  # card assumes 6-objective maps; ours have 5
		"rules": [
			{"when": "eot", "type": "hold_min", "min": 3, "exclude_home": false, "vp": 4},
			{"when": "command", "type": "hold_min", "min": 2, "exclude_home": false, "vp": 5},
			{"when": "command", "type": "hold_more", "vp": 4},
			{"when": "eog", "type": "hold_enemy_home", "vp": 5},
		],
	})
	_add({
		"id": "determined_acquisition", "name": "Determined Acquisition",
		"deck": "take_and_hold", "played_vs": "disruption",
		"approximate": true,
		"rules": [
			{"when": "command", "type": "hold_new", "vp": 2, "exclude_home": true, "approximate": true},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "zone": "not_enemy_territory", "vp": 3},
			{"when": "command", "type": "hold_min", "min": 1, "zone": "enemy_territory", "vp": 6},
		],
	})

	# ---- Purge the Foe deck ----
	_add({
		"id": "unstoppable_force", "name": "Unstoppable Force",
		"deck": "purge_the_foe", "played_vs": "take_and_hold",
		"rules": [
			{"when": "eot", "type": "destroyed_min", "min": 1, "vp": 3},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4},
			{"when": "command", "type": "hold_new", "vp": 3, "exclude_home": true, "approximate": true},
			{"when": "eog", "type": "hold_central", "vp": 5},
		],
	})
	_add({
		"id": "meatgrinder", "name": "Meatgrinder",
		"deck": "purge_the_foe", "played_vs": "purge_the_foe",
		"rules": [
			{"when": "eot", "type": "destroyed_min", "min": 1, "vp": 3},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4},
			{"when": "eot", "type": "killed_more_than_opponent_last_turn", "vp": 4},
			{"when": "eog", "type": "hold_enemy_home", "vp": 5, "approximate": true},
		],
	})
	_add({
		"id": "punishment", "name": "Punishment",
		"deck": "purge_the_foe", "played_vs": "disruption",
		"approximate": true,
		"rules": [
			{"when": "command", "type": "action", "action_name": "Condemn"},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4},
			{"when": "command", "type": "hold_more", "vp": 5},
			{"when": "eog", "type": "hold_enemy_home", "vp": 8},
		],
	})
	_add({
		"id": "consecrate", "name": "Consecrate",
		"deck": "purge_the_foe", "played_vs": "reconnaissance",
		"approximate": true,
		"rules": [
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4},
			{"when": "command", "type": "hold_more", "vp": 4},
			{"when": "command", "type": "action", "action_name": "Consecrate"},
		],
	})
	_add({
		"id": "destroyers_wrath", "name": "Destroyer's Wrath",
		"deck": "purge_the_foe", "played_vs": "priority_assets",
		"rules": [
			{"when": "eot", "type": "destroyed_min", "min": 1, "vp": 3},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4},
			{"when": "command", "type": "hold_more", "vp": 4},
			{"when": "eot", "type": "killed_more_than_opponent_last_turn", "vp": 5},
		],
	})

	# ---- Reconnaissance deck ----
	_add({
		"id": "reconnaissance_sweep", "name": "Reconnaissance Sweep",
		"deck": "reconnaissance", "played_vs": "take_and_hold",
		"approximate": true,
		"rules": [
			{"when": "eot", "type": "quarters", "min": 3, "vp": 6, "approximate": true},
			{"when": "eot", "type": "destroyed_per_unit", "vp_per": 1},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4, "approximate": true},
		],
	})
	_add({
		"id": "triangulation", "name": "Triangulation",
		"deck": "reconnaissance", "played_vs": "purge_the_foe",
		"approximate": true,
		"rules": [
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4},
			{"when": "eot", "type": "action", "action_name": "Triangulate"},
		],
	})
	_add({
		"id": "gather_intel", "name": "Gather Intel",
		"deck": "reconnaissance", "played_vs": "reconnaissance",
		"approximate": true,
		"rules": [
			{"when": "command", "type": "action", "action_name": "Extract Intelligence"},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4, "approximate": true},
		],
	})
	_add({
		"id": "search_and_scour", "name": "Search and Scour",
		"deck": "reconnaissance", "played_vs": "priority_assets",
		"approximate": true,
		"rules": [
			{"when": "command", "type": "action", "action_name": "Sweep operation markers"},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4, "approximate": true},
		],
	})
	_add({
		"id": "surveil_the_foe", "name": "Surveil the Foe",
		"deck": "reconnaissance", "played_vs": "disruption",
		"approximate": true,
		"rules": [
			{"when": "command", "type": "action", "action_name": "Surveil / scrub decoys"},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4, "approximate": true},
		],
	})

	# ---- Priority Assets deck ----
	_add({
		"id": "secure_asset", "name": "Secure Asset",
		"deck": "priority_assets", "played_vs": "take_and_hold",
		"approximate": true,
		"rules": [
			{"when": "command", "type": "action", "action_name": "Secure Asset"},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4},
			{"when": "command", "type": "hold_min", "min": 3, "exclude_home": true, "vp": 4},
		],
	})
	_add({
		"id": "vital_link", "name": "Vital Link",
		"deck": "priority_assets", "played_vs": "purge_the_foe",
		"approximate": true,
		"rules": [
			{"when": "command", "type": "hold_central", "vp": 2, "approximate": true},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4},
			{"when": "command", "type": "hold_central", "vp": 4},
			{"when": "eog", "type": "hold_enemy_home", "vp": 10},
		],
	})
	_add({
		"id": "vanguard_operation", "name": "Vanguard Operation",
		"deck": "priority_assets", "played_vs": "reconnaissance",
		"approximate": true,
		"rules": [
			{"when": "command", "type": "action", "action_name": "Vanguard Op"},
			{"when": "eot", "type": "destroyed_min", "min": 1, "vp": 2},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4},
			{"when": "eog", "type": "hold_enemy_home", "vp": 10},
		],
	})
	_add({
		"id": "sabotage", "name": "Sabotage",
		"deck": "priority_assets", "played_vs": "priority_assets",
		"approximate": true,
		"rules": [
			{"when": "command", "type": "action", "action_name": "Sabotage"},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4},
		],
	})
	_add({
		"id": "extract_relic", "name": "Extract Relic",
		"deck": "priority_assets", "played_vs": "disruption",
		"approximate": true,
		"rules": [
			{"when": "command", "type": "action", "action_name": "Sensor Sweep"},
			{"when": "eot", "type": "destroyed_min", "min": 1, "vp": 3, "approximate": true},
		],
	})

	# ---- Disruption deck ----
	_add({
		"id": "death_trap", "name": "Death Trap",
		"deck": "disruption", "played_vs": "take_and_hold",
		"approximate": true,
		"rules": [
			{"when": "command", "type": "action", "action_name": "Booby Trap"},
		],
	})
	_add({
		"id": "delaying_action", "name": "Delaying Action",
		"deck": "disruption", "played_vs": "purge_the_foe",
		"rules": [
			{"when": "eot", "type": "destroyed_per_unit", "vp_per": 2},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4},
			{"when": "command", "type": "hold_central_plus_nml", "vp": 3},
		],
	})
	_add({
		"id": "outmanoeuvre", "name": "Outmanoeuvre",
		"deck": "disruption", "played_vs": "disruption",
		"rules": [
			{"when": "command", "type": "hold_enemy_home", "vp": 10},
			{"when": "command", "type": "per_objective", "exclude_home": true,
				"vp_by_round": {1: 4, 2: 5, 3: 5, 4: 6, 5: 6}},
		],
	})
	_add({
		"id": "smoke_and_mirrors", "name": "Smoke and Mirrors",
		"deck": "disruption", "played_vs": "reconnaissance",
		"approximate": true,
		"rules": [
			{"when": "command", "type": "action", "action_name": "Decoy markers"},
		],
	})
	_add({
		"id": "locate_and_deny", "name": "Locate and Deny",
		"deck": "disruption", "played_vs": "priority_assets",
		"approximate": true,
		"rules": [
			{"when": "command", "type": "action", "action_name": "Locate and Deny"},
		],
	})

# ============================================================================
# PUBLIC API
# ============================================================================

## The primary mission card a player plays: their own deck paired against the
## opponent's disposition. Returns {} for unknown dispositions.
static func get_card(own_disposition: String, opponent_disposition: String) -> Dictionary:
	_ensure_loaded()
	var key := "%s|%s" % [own_disposition, opponent_disposition]
	if not _cards.has(key):
		return {}
	return _cards[key].duplicate(true)

static func get_card_by_id(card_id: String) -> Dictionary:
	_ensure_loaded()
	for key in _cards:
		if _cards[key].get("id", "") == card_id:
			return _cards[key].duplicate(true)
	return {}

static func get_all_cards() -> Array:
	_ensure_loaded()
	var out := []
	for key in _cards:
		out.append(_cards[key].duplicate(true))
	return out

static func is_valid_disposition(disposition: String) -> bool:
	return disposition in DISPOSITIONS

static func get_disposition_name(disposition: String) -> String:
	return DISPOSITION_NAMES.get(disposition, disposition)
