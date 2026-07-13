extends RefCounted
class_name PrimaryMissionData11e

# 11th-edition primary missions — Force Disposition pairing system.
# Source: 40k/data/40kdc/missionCards.json (official 11e launch dataset,
# @alpaca-software/40kdc-data 1.0.19, effective 2026-06-20). Every card's
# rules below are a 1:1 translation of that file's award rows; the earlier
# hand-reconstructed numbers (review text / GDM summary table) are gone.
#
# Each player picks a Force Disposition before the game. The primary mission
# card each player scores is determined by THEIR deck paired against the
# OPPONENT's disposition — so the two players usually play different cards.
#
# Translation conventions (official award trigger -> rule dict):
#   end-of-phase command, your-turn, round{min:2} -> when:"command",
#       rounds:[2,5]. The engine already switches Command scoring to end of
#       turn in Round 5, so an official pair {command min2 max4} +
#       {end-of-turn min5 max5} carrying the same award is ONE command rule.
#   end-of-turn, your-turn   -> when:"eot"
#   end-of-turn, either      -> when:"eot_any"
#   end-of-battle            -> when:"eog"
#
# Rule dict schema (consumed by MissionManager._score_primary_11e):
#   when: "command" | "eot" | "eot_any" | "eog" (see above)
#   type: hold_min | per_objective | per_new_objective | hold_more |
#         hold_enemy_home | hold_central | hold_central_plus_nml | hold_new |
#         destroyed_min | destroyed_per_unit |
#         killed_more_than_opponent_last_turn | quarters
#         — plus the marker/action mechanics (auto-resolved by
#         MissionManager._run_primary_auto_actions_11e as the headless/AI
#         backstop, with player prompts for the target choices):
#         triangulated_count | consecrated_count | consecrated_enemy_home |
#         condemned_left | sabotage_per_objective | central_operation_markers |
#         destroyed_near_central | vanguard_terrain_area | sensor_sweep_vp |
#         relic_final_marker | decoyed_score | decoyed_total_eog |
#         no_enemy_markers | intel_tokens_placed | operation_markers_min |
#         intel_token_on_enemy_home | trapped_score |
#         destroyed_started_on_objective | destroyed_in_terrain_area |
#         no_enemy_wholly_in_my_dz | action (unimplemented placeholder — 0 VP)
#   vp / vp_per: victory points awarded (vp_by_round is still understood by
#       the engine for pre-40kdc save files but no longer used here)
#   rounds: [from, to] inclusive battle-round window (default all rounds)
#   exclusive_group: rules sharing a value are official OR tiers — only the
#       highest-scoring rule of the group applies in a scoring pass.
#   count_min / count_max: tier bounds for triangulated_count /
#       consecrated_count (legacy rules without count_min keep the old
#       hardcoded tiering so saved games stay valid).
#   require_hold_home: the per_objective rule only scores while the player
#       also controls their own home objective.
#   trapped_only: destroyed_in_terrain_area only counts kills in terrain the
#       player Booby Trapped (Death Trap).
#   approximate (rule level): the engine evaluates a defensible stand-in for
#       the official condition — each flagged rule carries a comment.
#   approximate (card level): set iff any of the card's rules is flagged.
#       Cards without it are exact translations of the official awards.
#
# VP caps (unchanged at the 11e launch): 45 primary total, 15 per turn.

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
			# EOT R1-2: objective majority vs the opponent
			{"when": "eot", "type": "hold_more", "vp": 2, "rounds": [1, 2]},
			# Command R2+: 3 VP per controlled objective
			{"when": "command", "type": "per_objective", "vp_per": 3, "exclude_home": false, "rounds": [2, 5]},
			# Command R2+ cumulative bonus: +2 per controlled NON-HOME objective
			# while also holding your own home objective
			{"when": "command", "type": "per_objective", "vp_per": 2, "exclude_home": true,
				"require_hold_home": true, "rounds": [2, 5]},
		],
	})
	_add({
		"id": "immovable_object", "name": "Immovable Object",
		"deck": "take_and_hold", "played_vs": "purge_the_foe",
		"rules": [
			{"when": "eot", "type": "hold_central", "vp": 3},
			{"when": "command", "type": "per_objective", "vp_per": 5, "exclude_home": true, "rounds": [2, 5]},
		],
	})
	_add({
		"id": "purge_and_secure", "name": "Purge and Secure",
		"deck": "take_and_hold", "played_vs": "reconnaissance",
		"approximate": true,  # kill-pair award below is a stand-in
		"rules": [
			# Official: TWO exclusive 3 VP branches — (a) a friendly unit on an
			# objective destroyed an enemy unit, or (b) an enemy unit that
			# started the turn on an objective was destroyed. The engine can't
			# attribute destroyer positions, so branch (b) stands for the pair
			# (dead-model position proxies "started the turn on an objective").
			{"when": "eot", "type": "destroyed_started_on_objective", "vp": 3,
				"exclusive_group": "purge_kill", "approximate": true},
			{"when": "command", "type": "per_objective", "vp_per": 4, "exclude_home": true, "rounds": [2, 5]},
			{"when": "eot", "type": "hold_new", "vp": 3, "exclude_home": true, "rounds": [2, 5]},
		],
	})
	_add({
		"id": "inescapable_dominion", "name": "Inescapable Dominion",
		"deck": "take_and_hold", "played_vs": "priority_assets",
		"rules": [
			{"when": "eot", "type": "hold_min", "min": 3, "exclude_home": false, "vp": 4},
			{"when": "command", "type": "hold_min", "min": 2, "exclude_home": false, "vp": 5, "rounds": [2, 5]},
			{"when": "command", "type": "hold_more", "vp": 4, "rounds": [2, 5]},
			{"when": "eog", "type": "hold_enemy_home", "vp": 5},
		],
	})
	_add({
		"id": "determined_acquisition", "name": "Determined Acquisition",
		"deck": "take_and_hold", "played_vs": "disruption",
		"rules": [
			# EOT: 2 VP per objective newly controlled this turn (no exclusion)
			{"when": "eot", "type": "per_new_objective", "vp_per": 2},
			{"when": "command", "type": "per_objective", "vp_per": 3, "exclude_home": false, "rounds": [2, 5]},
			# Command R2+ cumulative bonus: +3 per controlled objective in the
			# opponent's territory
			{"when": "command", "type": "per_objective", "vp_per": 3, "zone": "enemy_territory", "rounds": [2, 5]},
		],
	})

	# ---- Purge the Foe deck ----
	_add({
		"id": "unstoppable_force", "name": "Unstoppable Force",
		"deck": "purge_the_foe", "played_vs": "take_and_hold",
		"rules": [
			{"when": "eot", "type": "destroyed_min", "min": 1, "vp": 3},
			{"when": "command", "type": "per_objective", "vp_per": 4, "exclude_home": true, "rounds": [2, 5]},
			{"when": "eot", "type": "hold_new", "vp": 3, "exclude_home": true, "rounds": [2, 5]},
			{"when": "eog", "type": "hold_central", "vp": 5},
		],
	})
	_add({
		"id": "meatgrinder", "name": "Meatgrinder",
		"deck": "purge_the_foe", "played_vs": "purge_the_foe",
		"rules": [
			{"when": "eot", "type": "destroyed_min", "min": 1, "vp": 3},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4, "rounds": [2, 5]},
			{"when": "eot", "type": "killed_more_than_opponent_last_turn", "vp": 5, "rounds": [2, 5]},
			{"when": "eot", "type": "hold_enemy_home", "vp": 5, "rounds": [2, 5]},
		],
	})
	_add({
		"id": "punishment", "name": "Punishment",
		"deck": "purge_the_foe", "played_vs": "disruption",
		# Condemn eligibility is narrower than the card (enemy units in range
		# of an objective only; the destroyed-a-friendly-last-turn branch and
		# the any-one-unit fallback aren't tracked). The awards themselves are
		# exact and the Command-phase prompt lets the player revise the picks.
		"rules": [
			{"when": "eot_any", "type": "condemned_left", "vp": 5},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4, "rounds": [2, 5]},
			{"when": "command", "type": "hold_more", "vp": 5, "rounds": [2, 5]},
			{"when": "eog", "type": "hold_enemy_home", "vp": 8},
		],
	})
	_add({
		"id": "consecrate", "name": "Consecrate",
		"deck": "purge_the_foe", "played_vs": "reconnaissance",
		"rules": [
			# Official OR tiers: 1-2 consecrated objectives -> 3 VP, 3+ -> 6 VP
			{"when": "eot", "type": "consecrated_count", "count_min": 1, "count_max": 2, "vp": 3,
				"exclusive_group": "consecrated_tier"},
			{"when": "eot", "type": "consecrated_count", "count_min": 3, "vp": 6,
				"exclusive_group": "consecrated_tier"},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4, "rounds": [2, 5]},
			{"when": "command", "type": "hold_more", "vp": 4, "rounds": [2, 5]},
			{"when": "eog", "type": "consecrated_enemy_home", "vp": 5},
		],
	})
	_add({
		"id": "destroyers_wrath", "name": "Destroyer's Wrath",
		"deck": "purge_the_foe", "played_vs": "priority_assets",
		"rules": [
			{"when": "eot", "type": "destroyed_min", "min": 1, "vp": 3},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4, "rounds": [2, 5]},
			{"when": "command", "type": "hold_more", "vp": 6, "rounds": [2, 5]},
			{"when": "eot", "type": "killed_more_than_opponent_last_turn", "vp": 4, "rounds": [2, 5]},
		],
	})

	# ---- Reconnaissance deck ----
	_add({
		"id": "reconnaissance_sweep", "name": "Reconnaissance Sweep",
		"deck": "reconnaissance", "played_vs": "take_and_hold",
		"rules": [
			# Official OR tiers on engagement fronts (table quarters, none
			# within 6" of the centre): 3 quarters -> 3 VP, 4 quarters -> 6 VP
			{"when": "eot", "type": "quarters", "min": 3, "vp": 3, "exclusive_group": "quarters_tier"},
			{"when": "eot", "type": "quarters", "min": 4, "vp": 6, "exclusive_group": "quarters_tier"},
			{"when": "eot", "type": "destroyed_per_unit", "vp_per": 1},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 3, "rounds": [2, 5]},
		],
	})
	_add({
		"id": "triangulation", "name": "Triangulation",
		"deck": "reconnaissance", "played_vs": "purge_the_foe",
		# NOTE: the official Triangulate action only starts from Round 2; the
		# engine's auto-pick/prompt wiring still offers it in Round 1, but the
		# tier awards below only pay from Round 2 per the official windows.
		"rules": [
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4, "rounds": [2, 5]},
			# Official OR tiers: exactly 1 -> 3 VP, exactly 2 -> 6 VP, 3+ -> 10 VP
			{"when": "eot", "type": "triangulated_count", "count_min": 1, "count_max": 1, "vp": 3,
				"exclusive_group": "triangulated_tier", "rounds": [2, 5]},
			{"when": "eot", "type": "triangulated_count", "count_min": 2, "count_max": 2, "vp": 6,
				"exclusive_group": "triangulated_tier", "rounds": [2, 5]},
			{"when": "eot", "type": "triangulated_count", "count_min": 3, "vp": 10,
				"exclusive_group": "triangulated_tier", "rounds": [2, 5]},
			{"when": "eog", "type": "hold_min", "min": 4, "exclude_home": false, "vp": 10},
		],
	})
	_add({
		"id": "gather_intel", "name": "Gather Intel",
		"deck": "reconnaissance", "played_vs": "reconnaissance",
		"approximate": true,  # opponent-home marker award below
		"rules": [
			{"when": "eot", "type": "hold_central", "vp": 6, "rounds": [1, 1]},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4, "rounds": [2, 5]},
			{"when": "eot", "type": "intel_tokens_placed", "vp_per": 7, "rounds": [2, 5]},
			# EOG: 3+ of your operation markers on the battlefield
			{"when": "eog", "type": "operation_markers_min", "min": 3, "vp": 5},
			# EOG: a marker within range of the opponent's home objective. The
			# condition is evaluated exactly (intel tokens are keyed by
			# objective), but the placement wiring only targets No Man's Land
			# objectives (official: any non-home objective without one of your
			# markers), so this award is currently unreachable in play.
			{"when": "eog", "type": "intel_token_on_enemy_home", "vp": 5, "approximate": true},
		],
	})
	_add({
		"id": "search_and_scour", "name": "Search and Scour",
		"deck": "reconnaissance", "played_vs": "priority_assets",
		"approximate": true,
		"rules": [
			{"when": "eot", "type": "hold_central", "vp": 3},
			# Official: an enemy unit that STARTED THE TURN inside a terrain
			# area was destroyed; the engine checks the dead models' final
			# positions instead.
			{"when": "eot", "type": "destroyed_in_terrain_area", "vp": 2, "approximate": true},
			{"when": "command", "type": "per_objective", "vp_per": 4, "exclude_home": true, "rounds": [2, 5]},
			# Official: no enemy units wholly within YOUR TERRITORY; the engine
			# approximates territory with the deployment zone polygon.
			{"when": "eog", "type": "no_enemy_wholly_in_my_dz", "vp": 5, "approximate": true},
		],
	})
	_add({
		"id": "surveil_the_foe", "name": "Surveil the Foe",
		"deck": "reconnaissance", "played_vs": "disruption",
		"approximate": true,
		"rules": [
			# Official: 4 VP if an enemy unit was surveilled this turn (unless
			# every surveilled unit is shielded by the opponent's operation
			# markers). Surveil tagging isn't implemented — warn-once, 0 VP.
			{"when": "eot", "type": "action", "action_name": "Surveil the Foe", "vp": 4, "approximate": true},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4, "rounds": [2, 5]},
			{"when": "command", "type": "hold_more", "vp": 4, "rounds": [2, 5]},
			# R2+ EOT: none of the opponent's operation (decoy) markers remain
			{"when": "eot", "type": "no_enemy_markers", "vp": 5, "rounds": [2, 5]},
		],
	})

	# ---- Priority Assets deck ----
	_add({
		"id": "secure_asset", "name": "Secure Asset",
		"deck": "priority_assets", "played_vs": "take_and_hold",
		"approximate": true,
		"rules": [
			# Secure Asset action (once per turn, completes at EOT if the unit
			# controls the targeted non-home objective) — deliberately modelled
			# as the equivalent hold check (control implies a unit in range).
			{"when": "eot", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4},
			# Official: an enemy unit that started the turn on a CENTRAL
			# objective was destroyed; dead-model position proxy.
			{"when": "eot", "type": "destroyed_near_central", "vp": 2, "approximate": true},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4, "rounds": [2, 5]},
			# Official: 3+ controlled objectives, NO home exclusion
			{"when": "command", "type": "hold_min", "min": 3, "exclude_home": false, "vp": 4, "rounds": [2, 5]},
		],
	})
	_add({
		"id": "vital_link", "name": "Vital Link",
		"deck": "priority_assets", "played_vs": "purge_the_foe",
		"approximate": true,
		"rules": [
			# EOT: 2 VP for holding a central objective + 1 VP per operation
			# marker within range of it (cumulative row on the card). The
			# Maintain Control marker placement is fully automatic while the
			# central objective is held — the action's cost (a unit gives up
			# shooting, once per turn) is not modelled and there is no prompt.
			{"when": "eot", "type": "central_operation_markers", "vp": 2, "vp_per_marker": 1, "approximate": true},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4, "rounds": [2, 5]},
			# Command R2+ cumulative row: +4 when one of them is central
			{"when": "command", "type": "hold_central", "vp": 4, "rounds": [2, 5]},
			{"when": "eog", "type": "hold_enemy_home", "vp": 10},
		],
	})
	_add({
		"id": "vanguard_operation", "name": "Vanguard Operation",
		"deck": "priority_assets", "played_vs": "reconnaissance",
		"approximate": true,
		"rules": [
			# Official: the Vanguard Operation action completed in a terrain
			# area in the opponent's TERRITORY; the engine approximates
			# territory with the enemy deployment zone polygon.
			{"when": "eot", "type": "vanguard_terrain_area", "vp": 4, "approximate": true},
			{"when": "eot", "type": "destroyed_min", "min": 1, "vp": 2},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4, "rounds": [2, 5]},
			{"when": "eog", "type": "hold_enemy_home", "vp": 10},
		],
	})
	_add({
		"id": "sabotage", "name": "Sabotage",
		"deck": "priority_assets", "played_vs": "priority_assets",
		# Official pays per sabotaging UNIT; the engine pays per sabotaged
		# OBJECTIVE (one unit per objective in practice — only two units
		# committing sabotage at the same objective would differ).
		"rules": [
			{"when": "eot", "type": "sabotage_per_objective", "vp_per": 3, "enemy_territory_bonus": 2},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4, "rounds": [2, 5]},
		],
	})
	_add({
		"id": "extract_relic", "name": "Extract Relic",
		"deck": "priority_assets", "played_vs": "disruption",
		"approximate": true,
		"rules": [
			{"when": "eot", "type": "sensor_sweep_vp", "vp": 4},
			# Official: an enemy unit that started the turn on an objective was
			# destroyed; dead-model position proxy.
			{"when": "eot", "type": "destroyed_started_on_objective", "vp": 3, "approximate": true},
			# Exactly one opponent marker left, a friendly unit alone in its
			# terrain area — at EOT and again at EOG
			{"when": "eot", "type": "relic_final_marker", "vp": 4},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4, "rounds": [2, 5]},
			{"when": "eog", "type": "relic_final_marker", "vp": 5},
		],
	})

	# ---- Disruption deck ----
	_add({
		"id": "death_trap", "name": "Death Trap",
		"deck": "disruption", "played_vs": "take_and_hold",
		"approximate": true,
		"rules": [
			# 2 VP per terrain area trapped THIS TURN, +3 (cumulative row) when
			# the trapped terrain holds an objective
			{"when": "eot", "type": "trapped_score", "vp_per": 2, "objective_bonus": 3},
			# Official: an enemy unit that STARTED THE TURN in trapped terrain
			# was destroyed; the engine checks the dead models' final positions.
			{"when": "eot", "type": "destroyed_in_terrain_area", "vp": 3, "trapped_only": true, "approximate": true},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4, "rounds": [2, 5]},
		],
	})
	_add({
		"id": "delaying_action", "name": "Delaying Action",
		"deck": "disruption", "played_vs": "purge_the_foe",
		"rules": [
			{"when": "eot", "type": "destroyed_per_unit", "vp_per": 2},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4, "rounds": [2, 5]},
			# R2+ EOT: hold a central objective AND an expansion objective
			# (expansions are exactly the non-central NML objectives here)
			{"when": "eot", "type": "hold_central_plus_nml", "vp": 3, "rounds": [2, 5]},
		],
	})
	_add({
		"id": "outmanoeuvre", "name": "Outmanoeuvre",
		"deck": "disruption", "played_vs": "disruption",
		"rules": [
			# Any of your turns: 10 VP for holding the opponent's home objective
			{"when": "eot", "type": "hold_enemy_home", "vp": 10},
			# Escalating per-non-home-objective rate with the official
			# triggers: EOT in R1, Command phase in R2-3, EOT from R4
			{"when": "eot", "type": "per_objective", "vp_per": 4, "exclude_home": true, "rounds": [1, 1]},
			{"when": "command", "type": "per_objective", "vp_per": 5, "exclude_home": true, "rounds": [2, 3]},
			{"when": "eot", "type": "per_objective", "vp_per": 6, "exclude_home": true, "rounds": [4, 5]},
		],
	})
	_add({
		"id": "smoke_and_mirrors", "name": "Smoke and Mirrors",
		"deck": "disruption", "played_vs": "reconnaissance",
		# The official Decoyed tag never clears: every objective ever decoyed
		# keeps paying (decoyed_score reads decoyed_ever); removal of the
		# operation markers only matters for the opponent's no_enemy_markers
		# check on Surveil the Foe.
		"rules": [
			{"when": "eot", "type": "decoyed_score", "vp_per": 2, "enemy_territory_bonus": 2},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4, "rounds": [2, 5]},
			{"when": "eog", "type": "decoyed_total_eog", "min": 4, "vp": 10},
		],
	})
	_add({
		"id": "locate_and_deny", "name": "Locate and Deny",
		"deck": "disruption", "played_vs": "priority_assets",
		"approximate": true,
		"rules": [
			# Official: an enemy unit that started the turn on an objective was
			# destroyed; dead-model position proxy.
			{"when": "eot", "type": "destroyed_started_on_objective", "vp": 4, "approximate": true},
			# Exactly one of YOUR markers left, a friendly unit alone in its
			# terrain area — at EOT and again at EOG
			{"when": "eot", "type": "relic_final_marker", "vp": 4},
			{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4, "rounds": [2, 5]},
			{"when": "eog", "type": "relic_final_marker", "vp": 5},
		],
	})

	# Attach the official prose scoring blurbs (source of truth for the
	# human-readable card text shown in the Scoring panel).
	_attach_texts()

## Load the official prose scoring text from the 40kdc dataset and attach it to
## each card as card["text"]. Matched by id (underscore<->hyphen). Best-effort:
## if the file is missing/unreadable the cards simply carry no blurb and the UI
## falls back to the generated per-rule breakdown.
static func _attach_texts() -> void:
	var path := "res://data/40kdc/missionCards.json"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var raw := f.get_as_text()
	f.close()
	var data = JSON.parse_string(raw)
	if typeof(data) != TYPE_ARRAY:
		return
	var text_by_id := {}
	for entry in data:
		if typeof(entry) == TYPE_DICTIONARY and entry.get("card_type", "") == "primary":
			text_by_id[str(entry.get("id", ""))] = str(entry.get("text", ""))
	for key in _cards:
		var json_id: String = str(_cards[key].get("id", "")).replace("_", "-")
		if text_by_id.has(json_id):
			_cards[key]["text"] = text_by_id[json_id]

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

# ============================================================================
# HUMAN-READABLE SCORING TEXT (for the in-game primary-mission panel)
# ============================================================================

## Official prose description of a card's scoring, sourced verbatim from the
## 40kdc dataset (missionCards.json). Empty string if the card has no blurb.
static func get_card_text(card: Dictionary) -> String:
	return str(card.get("text", ""))

## One readable line per scoring rule, in card order — e.g.
## "Command phase (R2+): +3VP — per objective you control". Rendered under the
## card name in the Scoring panel so a player can read exactly what the card
## awards instead of only its title. Derived from the SAME structured rules the
## engine scores, so the text can never drift from the actual behaviour.
static func get_scoring_lines(card: Dictionary) -> Array:
	var lines: Array = []
	for rule in card.get("rules", []):
		lines.append(describe_rule(rule))
	return lines

static func describe_rule(rule: Dictionary) -> String:
	return "%s: %s — %s" % [_describe_timing(rule), _describe_vp(rule), _describe_condition(rule)]

static func _describe_timing(rule: Dictionary) -> String:
	var base := ""
	match str(rule.get("when", "")):
		"command": base = "Command phase"
		"eot": base = "End of turn"
		"eot_any": base = "End of any turn"
		"eog": base = "End of game"
		_: base = str(rule.get("when", "?"))
	var rtxt := _describe_rounds(rule.get("rounds", []))
	return base if rtxt == "" else "%s %s" % [base, rtxt]

static func _describe_rounds(rounds) -> String:
	if typeof(rounds) != TYPE_ARRAY or rounds.size() < 2:
		return ""
	var lo := int(rounds[0])
	var hi := int(rounds[1])
	if lo <= 1 and hi >= 5:
		return ""  # every round — no qualifier needed
	if lo == hi:
		return "(R%d)" % lo
	if hi >= 5:
		return "(R%d+)" % lo
	return "(R%d–%d)" % [lo, hi]

static func _describe_vp(rule: Dictionary) -> String:
	if rule.has("vp_per"):
		return "+%dVP" % int(rule["vp_per"])
	if rule.has("vp"):
		return "+%dVP" % int(rule["vp"])
	return "VP"

static func _describe_condition(rule: Dictionary) -> String:
	var t := str(rule.get("type", ""))
	var excl := " (excl. home)" if rule.get("exclude_home", false) else ""
	match t:
		"hold_min":
			var n := int(rule.get("min", 1))
			return "control %d+ objective%s%s" % [n, "s" if n != 1 else "", excl]
		"per_objective":
			var s := "per objective you control"
			if rule.get("zone", "") == "enemy_territory":
				s += " in enemy territory"
			elif rule.get("exclude_home", false):
				s += " (excl. home)"
			if rule.get("require_hold_home", false):
				s += ", while you hold your own home"
			return s
		"per_new_objective":
			return "per objective newly taken this turn"
		"hold_more":
			return "control more objectives than your opponent"
		"hold_enemy_home":
			return "control the enemy's home objective"
		"hold_central":
			return "control the central objective"
		"hold_central_plus_nml":
			return "control the central objective + another No Man's Land objective"
		"hold_new":
			return "control an objective you didn't hold at the start of your turn%s" % excl
		"destroyed_min":
			var dn := int(rule.get("min", 1))
			return "destroy %d+ enemy unit%s" % [dn, "s" if dn != 1 else ""]
		"destroyed_per_unit":
			return "per enemy unit you destroy this turn"
		"killed_more_than_opponent_last_turn":
			return "destroy more units than your opponent did on their last turn"
		"quarters":
			return "have units in %d+ table quarters" % int(rule.get("min", 3))
		"triangulated_count":
			return "Triangulate %s objective(s)" % _tier_text(rule)
		"consecrated_count":
			return "Consecrate %s objective(s)" % _tier_text(rule)
		"consecrated_enemy_home":
			return "Consecrate the enemy's home objective"
		"condemned_left":
			return "a Condemned enemy unit leaves the battlefield"
		"sabotage_per_objective":
			return "per objective you Sabotage (bonus in enemy territory)"
		"central_operation_markers":
			return "control the central objective, +1VP per operation marker on it"
		"destroyed_near_central":
			return "destroy an enemy unit on a central objective"
		"vanguard_terrain_area":
			return "complete a Vanguard Operation in enemy territory"
		"sensor_sweep_vp":
			return "complete a Sensor Sweep action"
		"relic_final_marker":
			return "be the last player holding a relic marker"
		"decoyed_score":
			return "per objective you Decoy (bonus in enemy territory)"
		"decoyed_total_eog":
			return "Decoy %d+ objectives in total" % int(rule.get("min", 4))
		"no_enemy_markers":
			return "no enemy operation markers remain"
		"intel_tokens_placed":
			return "per Extract Intelligence action you complete"
		"operation_markers_min":
			return "have %d+ operation markers on the battlefield" % int(rule.get("min", 3))
		"intel_token_on_enemy_home":
			return "place a marker near the enemy's home objective"
		"trapped_score":
			return "per terrain area you Booby Trap this turn (bonus if it holds an objective)"
		"destroyed_started_on_objective":
			return "destroy an enemy unit that started the turn on an objective"
		"destroyed_in_terrain_area":
			return "destroy an enemy unit in %s terrain area" % ("a trapped" if rule.get("trapped_only", false) else "a")
		"no_enemy_wholly_in_my_dz":
			return "no enemy units are wholly within your territory"
		"action":
			return "complete the '%s' action" % str(rule.get("action_name", "mission"))
		_:
			return t.replace("_", " ")

## Tier label for the exclusive_group count rules (Triangulate / Consecrate):
## "exactly 2", "1–2" or "3+" depending on the rule's count bounds.
static func _tier_text(rule: Dictionary) -> String:
	var lo := int(rule.get("count_min", 1))
	if rule.has("count_max"):
		var hi := int(rule["count_max"])
		return str(lo) if lo == hi else "%d–%d" % [lo, hi]
	return "%d+" % lo
