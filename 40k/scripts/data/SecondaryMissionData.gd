extends RefCounted
class_name SecondaryMissionData

# SecondaryMissionData - Static data for all 19 secondary mission cards
# from Warhammer 40k Chapter Approved 2025-26.
#
# Cards 1-9 can be used as Fixed or Tactical missions.
# Cards 10-19 are Tactical only.
# Card 19 (Display of Might) is not in the standard tournament deck.
# Card 7 (No Prisoners) cannot be used as a Fixed mission in tournament play.

# Categories
const CATEGORY_POSITIONAL = "positional"
const CATEGORY_OBJECTIVE_CONTROL = "objective_control"
const CATEGORY_KILL = "kill"
const CATEGORY_ACTION = "action"

# Scoring timing
const TIMING_END_OF_YOUR_TURN = "end_of_your_turn"
const TIMING_END_OF_OPPONENT_TURN = "end_of_opponent_turn"
const TIMING_END_OF_EITHER_TURN = "end_of_either_turn"
const TIMING_WHILE_ACTIVE = "while_active"

# When-drawn effects
const EFFECT_SHUFFLE_BACK = "shuffle_back"
const EFFECT_DISCARD_AND_DRAW = "discard_and_draw"
const EFFECT_MANDATORY_SHUFFLE_BACK = "mandatory_shuffle_back"
const EFFECT_OPPONENT_SELECTS_UNITS = "opponent_selects_units"
const EFFECT_OPPONENT_SELECTS_OBJECTIVE = "opponent_selects_objective"

# All mission IDs in card order
const MISSION_IDS = [
	"behind_enemy_lines",
	"storm_hostile_objective",
	"engage_on_all_fronts",
	"establish_locus",
	"cleanse",
	"assassination",
	"no_prisoners",
	"cull_the_horde",
	"bring_it_down",
	"defend_stronghold",
	"marked_for_death",
	"secure_no_mans_land",
	"sabotage",
	"area_denial",
	"recover_assets",
	"a_tempting_target",
	"extend_battle_lines",
	"overwhelming_force",
	"display_of_might",
]

# ============================================================
# MISSION DATA
# ============================================================

static func _get_all_mission_data() -> Array:
	return [
		# ----------------------------------------------------------
		# Card 1: Behind Enemy Lines
		# ----------------------------------------------------------
		{
			"id": "behind_enemy_lines",
			"name": "Behind Enemy Lines",
			"number": 1,
			"category": CATEGORY_POSITIONAL,
			"can_be_fixed": true,
			"tournament_legal_fixed": true,
			"in_standard_deck": true,
			"flavour": "Your orders are clear: break through the enemy and cut off their escape routes.",
			"when_drawn": {
				"condition": "first_battle_round",
				"effect": EFFECT_SHUFFLE_BACK,
			},
			"scoring": {
				"when": TIMING_END_OF_YOUR_TURN,
				"min_round": 1,
				"conditions": [
					{
						"check": "units_wholly_in_opponent_deployment_zone",
						"params": {"count": 1, "exclude": ["AIRCRAFT", "Battle-shocked"]},
						"vp": 3,
					},
					{
						"check": "units_wholly_in_opponent_deployment_zone",
						"params": {"count": 2, "exclude": ["AIRCRAFT", "Battle-shocked"]},
						"vp": 4,
					},
				],
				"max_vp_per_score": 4,
			},
			"requires_action": false,
			"action": {},
		},

		# ----------------------------------------------------------
		# Card 2: Storm Hostile Objective
		# ----------------------------------------------------------
		{
			"id": "storm_hostile_objective",
			"name": "Storm Hostile Objective",
			"number": 2,
			"category": CATEGORY_OBJECTIVE_CONTROL,
			"can_be_fixed": true,
			"tournament_legal_fixed": true,
			"in_standard_deck": true,
			"flavour": "You must dominate the field of battle. Storm every site of tactical import and leave the foe with no place to hide.",
			"when_drawn": {
				"condition": "first_battle_round",
				"effect": EFFECT_SHUFFLE_BACK,
			},
			"scoring": {
				"when": TIMING_END_OF_YOUR_TURN,
				"min_round": 1,
				"conditions": [
					{
						"check": "control_objectives_opponent_controlled_at_start",
						"params": {"count": 1},
						"vp": 4,
					},
					{
						"check": "opponent_controlled_no_objectives_at_start_and_you_control_new",
						"params": {"count": 1, "min_round": 2},
						"vp": 4,
					},
				],
				"max_vp_per_score": 4,
			},
			"requires_action": false,
			"action": {},
		},

		# ----------------------------------------------------------
		# Card 3: Engage on All Fronts
		# ----------------------------------------------------------
		{
			"id": "engage_on_all_fronts",
			"name": "Engage on All Fronts",
			"number": 3,
			"category": CATEGORY_POSITIONAL,
			"can_be_fixed": true,
			"tournament_legal_fixed": true,
			"in_standard_deck": true,
			"flavour": "This area is of extreme importance. You are to lead an immediate all-out assault to capture it and deny it to our enemy for good.",
			"when_drawn": {},
			"scoring": {
				"when": TIMING_END_OF_YOUR_TURN,
				"min_round": 1,
				"conditions": [
					{
						"check": "presence_in_table_quarters",
						"params": {"count": 2, "min_distance_from_center": 6.0, "exclude": ["AIRCRAFT", "Battle-shocked"]},
						"vp": 1,
					},
					{
						"check": "presence_in_table_quarters",
						"params": {"count": 3, "min_distance_from_center": 6.0, "exclude": ["AIRCRAFT", "Battle-shocked"]},
						"vp": 2,
					},
					{
						"check": "presence_in_table_quarters",
						"params": {"count": 4, "min_distance_from_center": 6.0, "exclude": ["AIRCRAFT", "Battle-shocked"]},
						"vp": 4,
					},
				],
				"max_vp_per_score": 4,
			},
			"requires_action": false,
			"action": {},
		},

		# ----------------------------------------------------------
		# Card 4: Establish Locus
		# ----------------------------------------------------------
		{
			"id": "establish_locus",
			"name": "Establish Locus",
			"number": 4,
			"category": CATEGORY_ACTION,
			"can_be_fixed": true,
			"tournament_legal_fixed": true,
			"in_standard_deck": true,
			"flavour": "You must guide allied forces onto the battlefield by any means necessary; this objective must be completed swiftly to pave the road to victory.",
			"when_drawn": {},
			"scoring": {
				"when": TIMING_END_OF_YOUR_TURN,
				"min_round": 1,
				"conditions": [
					{
						"check": "locus_established_within_center",
						"params": {"distance": 6.0},
						"vp": 2,
					},
					{
						"check": "locus_established_in_opponent_deployment_zone",
						"params": {},
						"vp": 4,
					},
				],
				"max_vp_per_score": 4,
			},
			"requires_action": true,
			"action": {
				"action_name": "Establish Locus",
				"starts": "shooting_phase",
				"units_description": "One unit from your army.",
				"completes_description": "End of your turn, if that unit is within your opponent's deployment zone or within 6\" of the centre of the battlefield.",
				"completed_effect": "Your unit establishes a locus.",
			},
		},

		# ----------------------------------------------------------
		# Card 5: Cleanse
		# ----------------------------------------------------------
		{
			"id": "cleanse",
			"name": "Cleanse",
			"number": 5,
			"category": CATEGORY_ACTION,
			"can_be_fixed": true,
			"tournament_legal_fixed": true,
			"in_standard_deck": true,
			"flavour": "Your forces have identified a series of tainted objectives in this area; these locations must be purified.",
			"when_drawn": {},
			"scoring": {
				"when": TIMING_END_OF_YOUR_TURN,
				"min_round": 1,
				"conditions": [
					{
						"check": "objectives_cleansed",
						"params": {"count": 1},
						"vp": 2,
					},
					{
						"check": "objectives_cleansed",
						"params": {"count": 2, "fixed_vp": 4, "tactical_vp": 5},
						"vp": 5,
					},
				],
				"max_vp_per_score": 5,
			},
			"requires_action": true,
			"action": {
				"action_name": "Cleanse",
				"starts": "shooting_phase",
				"units_description": "One or more units from your army within range of an objective marker that is not within your deployment zone.",
				"completes_description": "End of your turn, if the unit performing this Action is still within range of the same objective marker and you control that objective marker.",
				"completed_effect": "That objective marker is cleansed by your army.",
			},
		},

		# ----------------------------------------------------------
		# Card 6: Assassination
		# ----------------------------------------------------------
		{
			"id": "assassination",
			"name": "Assassination",
			"number": 6,
			"category": CATEGORY_KILL,
			"can_be_fixed": true,
			"tournament_legal_fixed": true,
			"in_standard_deck": true,
			"flavour": "The enemy looks to their champions for courage. You must identify and eliminate such targets with extreme prejudice.",
			"when_drawn": {},
			"scoring": {
				"when": TIMING_END_OF_EITHER_TURN,
				"min_round": 1,
				"conditions": [
					{
						"check": "character_models_destroyed_this_turn",
						"params": {"count": 1},
						"vp": 5,
					},
					{
						"check": "all_enemy_characters_destroyed",
						"params": {},
						"vp": 5,
					},
				],
				"max_vp_per_score": 5,
				"fixed_scoring": {
					"when": TIMING_WHILE_ACTIVE,
					"conditions": [
						{
							"check": "character_model_destroyed_wounds_4_plus",
							"params": {},
							"vp": 4,
						},
						{
							"check": "character_model_destroyed_wounds_under_4",
							"params": {},
							"vp": 3,
						},
					],
				},
			},
			"requires_action": false,
			"action": {},
		},

		# ----------------------------------------------------------
		# Card 7: No Prisoners
		# ----------------------------------------------------------
		{
			"id": "no_prisoners",
			"name": "No Prisoners",
			"number": 7,
			"category": CATEGORY_KILL,
			"can_be_fixed": true,
			"tournament_legal_fixed": false,
			"in_standard_deck": true,
			"flavour": "Show no mercy. Exterminate your enemies.",
			"when_drawn": {},
			"scoring": {
				"when": TIMING_WHILE_ACTIVE,
				"min_round": 1,
				"conditions": [
					{
						"check": "enemy_unit_destroyed",
						"params": {},
						"vp": 2,
					},
				],
				"max_vp_per_score": 5,
				"fixed_scoring": {
					"when": TIMING_WHILE_ACTIVE,
					"conditions": [
						{
							"check": "enemy_bodyguard_or_non_character_unit_destroyed",
							"params": {},
							"vp": 2,
						},
					],
					"max_vp_per_score": 5,
				},
			},
			"requires_action": false,
			"action": {},
		},

		# ----------------------------------------------------------
		# Card 8: Cull the Horde
		# ----------------------------------------------------------
		{
			"id": "cull_the_horde",
			"name": "Cull the Horde",
			"number": 8,
			"category": CATEGORY_KILL,
			"can_be_fixed": true,
			"tournament_legal_fixed": true,
			"in_standard_deck": true,
			"flavour": "The enemy come forth in teeming masses. Their ranks must be thinned if the day is to be won.",
			"when_drawn": {
				"condition": "no_enemy_infantry_starting_strength_13_plus",
				"effect": EFFECT_DISCARD_AND_DRAW,
			},
			"scoring": {
				"when": TIMING_END_OF_EITHER_TURN,
				"min_round": 1,
				"conditions": [
					{
						"check": "infantry_starting_strength_13_plus_destroyed_this_turn",
						"params": {"count": 1},
						"vp": 5,
					},
				],
				"max_vp_per_score": 5,
				"fixed_scoring": {
					"when": TIMING_WHILE_ACTIVE,
					"conditions": [
						{
							"check": "infantry_starting_strength_13_plus_destroyed",
							"params": {},
							"vp": 5,
						},
					],
				},
			},
			"requires_action": false,
			"action": {},
		},

		# ----------------------------------------------------------
		# Card 9: Bring It Down
		# ----------------------------------------------------------
		{
			"id": "bring_it_down",
			"name": "Bring It Down",
			"number": 9,
			"category": CATEGORY_KILL,
			"can_be_fixed": true,
			"tournament_legal_fixed": true,
			"in_standard_deck": true,
			"flavour": "The opposing army contains numerous heavily armoured units. You must prioritise their destruction.",
			"when_drawn": {
				"condition": "no_enemy_monster_or_vehicle",
				"effect": EFFECT_DISCARD_AND_DRAW,
			},
			"scoring": {
				"when": TIMING_END_OF_EITHER_TURN,
				"min_round": 1,
				"conditions": [
					{
						"check": "monster_or_vehicle_destroyed_this_turn",
						"params": {"count": 1},
						"vp": 4,
					},
				],
				"max_vp_per_score": 4,
				"fixed_scoring": {
					"when": TIMING_WHILE_ACTIVE,
					"conditions": [
						{
							"check": "monster_or_vehicle_destroyed",
							"params": {},
							"vp": 2,
						},
						{
							"check": "monster_or_vehicle_destroyed_wounds_15_plus",
							"params": {"cumulative": true},
							"vp": 2,
						},
						{
							"check": "monster_or_vehicle_destroyed_wounds_20_plus",
							"params": {"cumulative": true},
							"vp": 2,
						},
					],
				},
			},
			"requires_action": false,
			"action": {},
		},

		# ----------------------------------------------------------
		# Card 10: Defend Stronghold
		# ----------------------------------------------------------
		{
			"id": "defend_stronghold",
			"name": "Defend Stronghold",
			"number": 10,
			"category": CATEGORY_OBJECTIVE_CONTROL,
			"can_be_fixed": false,
			"tournament_legal_fixed": false,
			"in_standard_deck": true,
			"flavour": "You are charged with the defence of a critical objective. It must not be permitted to fall into enemy hands.",
			"when_drawn": {
				"condition": "first_battle_round",
				"effect": EFFECT_MANDATORY_SHUFFLE_BACK,
			},
			"scoring": {
				"when": TIMING_END_OF_OPPONENT_TURN,
				"min_round": 2,
				"conditions": [
					{
						"check": "control_objectives_in_own_deployment_zone",
						"params": {"count": 1},
						"vp": 3,
					},
				],
				"max_vp_per_score": 3,
			},
			"requires_action": false,
			"action": {},
		},

		# ----------------------------------------------------------
		# Card 11: Marked for Death
		# ----------------------------------------------------------
		{
			"id": "marked_for_death",
			"name": "Marked for Death",
			"number": 11,
			"category": CATEGORY_KILL,
			"can_be_fixed": false,
			"tournament_legal_fixed": false,
			"in_standard_deck": true,
			"flavour": "You have been ordered to eliminate specific enemy assets to ensure victory, no matter how insignificant they may seem.",
			"when_drawn": {
				"condition": "opponent_selects_units",
				"effect": EFFECT_OPPONENT_SELECTS_UNITS,
				"details": {
					"alpha_targets": 3,
					"gamma_targets": 1,
					"fallback_if_fewer": true,
					"discard_if_no_enemy_units": true,
				},
			},
			"scoring": {
				"when": TIMING_END_OF_EITHER_TURN,
				"min_round": 1,
				"conditions": [
					{
						"check": "alpha_target_destroyed_this_turn",
						"params": {"count": 1},
						"vp": 5,
					},
					{
						"check": "no_alpha_destroyed_but_gamma_destroyed_this_turn",
						"params": {},
						"vp": 2,
					},
				],
				"max_vp_per_score": 5,
			},
			"requires_action": false,
			"action": {},
		},

		# ----------------------------------------------------------
		# Card 12: Secure No Man's Land
		# ----------------------------------------------------------
		{
			"id": "secure_no_mans_land",
			"name": "Secure No Man's Land",
			"number": 12,
			"category": CATEGORY_OBJECTIVE_CONTROL,
			"can_be_fixed": false,
			"tournament_legal_fixed": false,
			"in_standard_deck": true,
			"flavour": "You must advance swiftly into no man's land and seize it before the enemy can, lest they take control of the entire battlefield.",
			"when_drawn": {},
			"scoring": {
				"when": TIMING_END_OF_YOUR_TURN,
				"min_round": 1,
				"conditions": [
					{
						"check": "control_objectives_in_no_mans_land",
						"params": {"count": 1},
						"vp": 2,
					},
					{
						"check": "control_objectives_in_no_mans_land",
						"params": {"count": 2},
						"vp": 5,
					},
				],
				"max_vp_per_score": 5,
			},
			"requires_action": false,
			"action": {},
		},

		# ----------------------------------------------------------
		# Card 13: Sabotage
		# ----------------------------------------------------------
		{
			"id": "sabotage",
			"name": "Sabotage",
			"number": 13,
			"category": CATEGORY_ACTION,
			"can_be_fixed": false,
			"tournament_legal_fixed": false,
			"in_standard_deck": true,
			"flavour": "This region is replete with strategic assets or supply caches vital to your foe. See to it that they are reduced to just so much flaming wreckage.",
			"when_drawn": {},
			"scoring": {
				"when": TIMING_END_OF_OPPONENT_TURN,
				"min_round": 1,
				"conditions": [
					{
						"check": "sabotage_committed_not_in_opponent_zone",
						"params": {},
						"vp": 3,
					},
					{
						"check": "sabotage_committed_in_opponent_zone",
						"params": {},
						"vp": 6,
					},
				],
				"max_vp_per_score": 6,
			},
			"requires_action": true,
			"action": {
				"action_name": "Sabotage",
				"starts": "shooting_phase",
				"units_description": "One unit from your army that is within a terrain feature and not within your deployment zone.",
				"completes_description": "End of your opponent's next turn or the end of the battle (whichever comes first), if your unit is on the battlefield.",
				"completed_effect": "Your unit commits sabotage.",
			},
		},

		# ----------------------------------------------------------
		# Card 14: Area Denial
		# ----------------------------------------------------------
		{
			"id": "area_denial",
			"name": "Area Denial",
			"number": 14,
			"category": CATEGORY_POSITIONAL,
			"can_be_fixed": false,
			"tournament_legal_fixed": false,
			"in_standard_deck": true,
			"flavour": "It is critical that this area is dominated. No enemy vanguard or guerrilla units can be allowed to disrupt your plans.",
			"when_drawn": {},
			"scoring": {
				"when": TIMING_END_OF_YOUR_TURN,
				"min_round": 1,
				"conditions": [
					{
						"check": "units_within_center_no_enemies_within",
						"params": {"friendly_range": 3.0, "enemy_range": 3.0, "exclude": ["AIRCRAFT", "Battle-shocked"]},
						"vp": 2,
					},
					{
						"check": "units_within_center_no_enemies_within",
						"params": {"friendly_range": 3.0, "enemy_range": 6.0, "exclude": ["AIRCRAFT", "Battle-shocked"]},
						"vp": 5,
					},
				],
				"max_vp_per_score": 5,
			},
			"requires_action": false,
			"action": {},
		},

		# ----------------------------------------------------------
		# Card 15: Recover Assets
		# ----------------------------------------------------------
		{
			"id": "recover_assets",
			"name": "Recover Assets",
			"number": 15,
			"category": CATEGORY_ACTION,
			"can_be_fixed": false,
			"tournament_legal_fixed": false,
			"in_standard_deck": true,
			"flavour": "You must locate and reclaim scattered strategic assets.",
			"when_drawn": {
				"condition": "fewer_than_3_units_or_incursion",
				"effect": EFFECT_DISCARD_AND_DRAW,
			},
			"scoring": {
				"when": TIMING_END_OF_YOUR_TURN,
				"min_round": 1,
				"conditions": [
					{
						"check": "units_recovered_assets",
						"params": {"count": 2},
						"vp": 3,
					},
					{
						"check": "units_recovered_assets",
						"params": {"count": 3},
						"vp": 5,
					},
				],
				"max_vp_per_score": 5,
			},
			"requires_action": true,
			"action": {
				"action_name": "Recover Assets",
				"starts": "shooting_phase",
				"units_description": "Two or more units from your army, if each of those units is wholly within a different one of the following areas: your deployment zone; No Man's Land; your opponent's deployment zone.",
				"completes_description": "End of your turn, if either two or three of those units are on the battlefield.",
				"completed_effect": "Those units recover assets.",
			},
		},

		# ----------------------------------------------------------
		# Card 16: A Tempting Target
		# ----------------------------------------------------------
		{
			"id": "a_tempting_target",
			"name": "A Tempting Target",
			"number": 16,
			"category": CATEGORY_OBJECTIVE_CONTROL,
			"can_be_fixed": false,
			"tournament_legal_fixed": false,
			"in_standard_deck": true,
			"flavour": "An opportunity to seize a valuable asset has been identified, but the enemy are likely to use it as bait in a trap. Move to secure the site, but be wary of enemy ambushes.",
			"when_drawn": {
				"condition": "opponent_selects_objective",
				"effect": EFFECT_OPPONENT_SELECTS_OBJECTIVE,
				"details": {
					"zone": "no_mans_land",
					"label": "Tempting Target",
				},
			},
			"scoring": {
				"when": TIMING_END_OF_EITHER_TURN,
				"min_round": 1,
				"conditions": [
					{
						"check": "control_tempting_target",
						"params": {},
						"vp": 5,
					},
				],
				"max_vp_per_score": 5,
			},
			"requires_action": false,
			"action": {},
		},

		# ----------------------------------------------------------
		# Card 17: Extend Battle Lines
		# ----------------------------------------------------------
		{
			"id": "extend_battle_lines",
			"name": "Extend Battle Lines",
			"number": 17,
			"category": CATEGORY_OBJECTIVE_CONTROL,
			"can_be_fixed": false,
			"tournament_legal_fixed": false,
			"in_standard_deck": true,
			"flavour": "The battleground is conquered one yard at a time. Lead your forces forward and establish a strong presence in the area.",
			"when_drawn": {},
			"scoring": {
				"when": TIMING_END_OF_YOUR_TURN,
				"min_round": 1,
				"conditions": [
					{
						"check": "control_own_zone_and_nml_objectives",
						"params": {"own_zone_count": 1, "nml_count": 1},
						"vp": 4,
					},
					{
						"check": "control_objectives_in_no_mans_land",
						"params": {"count": 1},
						"vp": 2,
					},
				],
				"max_vp_per_score": 4,
			},
			"requires_action": false,
			"action": {},
		},

		# ----------------------------------------------------------
		# Card 18: Overwhelming Force
		# ----------------------------------------------------------
		{
			"id": "overwhelming_force",
			"name": "Overwhelming Force",
			"number": 18,
			"category": CATEGORY_KILL,
			"can_be_fixed": false,
			"tournament_legal_fixed": false,
			"in_standard_deck": true,
			"flavour": "You must scour the enemy from the face of the battlefield.",
			"when_drawn": {},
			"scoring": {
				"when": TIMING_WHILE_ACTIVE,
				"min_round": 1,
				"conditions": [
					{
						"check": "enemy_unit_destroyed_within_objective_range",
						"params": {},
						"vp": 3,
					},
				],
				"max_vp_per_score": 5,
			},
			"requires_action": false,
			"action": {},
		},

		# ----------------------------------------------------------
		# Card 19: Display of Might
		# ----------------------------------------------------------
		{
			"id": "display_of_might",
			"name": "Display of Might",
			"number": 19,
			"category": CATEGORY_POSITIONAL,
			"can_be_fixed": false,
			"tournament_legal_fixed": false,
			"in_standard_deck": false,
			"flavour": "Intimidation is the most potent of weapons. Degrade the combat abilities of your opponent to demonstrate your superiority and erode enemy morale.",
			"when_drawn": {
				"condition": "first_battle_round",
				"effect": EFFECT_MANDATORY_SHUFFLE_BACK,
			},
			"scoring": {
				"when": TIMING_END_OF_YOUR_TURN,
				"min_round": 1,
				"conditions": [
					{
						"check": "more_units_wholly_in_no_mans_land_than_opponent",
						"params": {},
						"vp": 4,
					},
				],
				"max_vp_per_score": 4,
			},
			"requires_action": false,
			"action": {},
		},
	]


# ============================================================
# STATIC ACCESS FUNCTIONS
# ============================================================

# Cache for mission data to avoid repeated array construction
static var _mission_cache: Array = []
static var _mission_id_map: Dictionary = {}

static func _ensure_cache() -> void:
	if _mission_cache.size() == 0:
		_mission_cache = _get_all_mission_data()
		for mission in _mission_cache:
			_mission_id_map[mission["id"]] = mission

# Returns all 19 secondary mission cards
static func get_all_missions() -> Array:
	_ensure_cache()
	return _mission_cache.duplicate(true)

# Returns a single mission by its string ID, or an empty dictionary if not found
static func get_mission_by_id(id: String) -> Dictionary:
	_ensure_cache()
	if _mission_id_map.has(id):
		return _mission_id_map[id].duplicate(true)
	push_warning("SecondaryMissionData: Unknown mission ID '%s'" % id)
	return {}

# Returns a single mission by its card number (1-19), or an empty dictionary if not found
static func get_mission_by_number(number: int) -> Dictionary:
	_ensure_cache()
	for mission in _mission_cache:
		if mission["number"] == number:
			return mission.duplicate(true)
	push_warning("SecondaryMissionData: Unknown mission number %d" % number)
	return {}

# Returns the standard 18-card tactical tournament deck (excludes Display of Might)
static func get_tactical_deck() -> Array:
	_ensure_cache()
	var deck: Array = []
	for mission in _mission_cache:
		if mission["in_standard_deck"]:
			deck.append(mission.duplicate(true))
	return deck

# Returns mission IDs suitable for building a deck
# By default excludes Display of Might (#19); set include_display_of_might=true to include it
static func get_mission_ids_for_deck(include_display_of_might: bool = false) -> Array:
	_ensure_cache()
	var ids: Array = []
	for mission in _mission_cache:
		if include_display_of_might or mission["in_standard_deck"]:
			ids.append(mission["id"])
	return ids

# Returns all missions that can be used as Fixed missions
static func get_fixed_eligible_missions() -> Array:
	_ensure_cache()
	var missions: Array = []
	for mission in _mission_cache:
		if mission["can_be_fixed"]:
			missions.append(mission.duplicate(true))
	return missions

# Returns all missions that are legal as Fixed missions in tournament play
static func get_tournament_fixed_missions() -> Array:
	_ensure_cache()
	var missions: Array = []
	for mission in _mission_cache:
		if mission["tournament_legal_fixed"]:
			missions.append(mission.duplicate(true))
	return missions

# Returns all missions of a given category
static func get_missions_by_category(category: String) -> Array:
	_ensure_cache()
	var missions: Array = []
	for mission in _mission_cache:
		if mission["category"] == category:
			missions.append(mission.duplicate(true))
	return missions

# Returns all missions that require an action to be performed
static func get_action_missions() -> Array:
	_ensure_cache()
	var missions: Array = []
	for mission in _mission_cache:
		if mission["requires_action"]:
			missions.append(mission.duplicate(true))
	return missions

# Clear the mission data cache (useful if data needs to be reloaded)
static func clear_cache() -> void:
	_mission_cache.clear()
	_mission_id_map.clear()
