extends Node
const GameStateData = preload("res://autoloads/GameState.gd")

# StratagemManager - Central authority for stratagem validation, tracking, and execution
#
# Responsibilities:
# - Load and store stratagem definitions (Core stratagems + faction/detachment)
# - Track CP spending per player
# - Track usage restrictions (once per battle, once per turn, once per phase)
# - Validate whether a stratagem can be used (correct phase, timing, CP, target)
# - Provide available stratagems at any trigger point
# - Apply stratagem effects to game state

signal stratagem_used(player: int, stratagem_id: String, target_unit_id: String)
signal stratagem_available(player: int, stratagem_id: String, trigger: String)

# ============================================================================
# STRATAGEM DATA MODEL
# ============================================================================

# All loaded stratagem definitions keyed by id
var stratagems: Dictionary = {}

# Usage tracking per player: { "1": { "battle": [...], "turn_2": [...], "phase_command_2": [...] } }
var _usage_history: Dictionary = {
	"1": [],
	"2": []
}

# Active effects currently applied (cleared at appropriate times)
# Each entry: { "stratagem_id": String, "player": int, "target_unit_id": String,
#               "effects": Array, "expires": String, "applied_turn": int, "applied_phase": int }
var active_effects: Array = []

# Faction stratagem tracking: which faction stratagem IDs belong to each player
# { "1": ["faction_sm_gladius_storm_of_fire", ...], "2": ["faction_ork_war_horde_unbridled_carnage", ...] }
var _player_faction_stratagems: Dictionary = {
	"1": [],
	"2": []
}

# Faction stratagem loader instance
var _faction_loader: FactionStratagemLoaderData = null

# Custom-handler stratagems added in the Ork detachment sweep (2026-07). Names
# are compared after normalizing typographic apostrophes and uppercasing.
# Older custom handlers keep their individual checks in
# _mark_custom_implemented_stratagems for git-blame continuity.
const _CUSTOM_IMPLEMENTED_NAMES: Array = [
	# Green Tide
	"BRAGGIN' RIGHTS", "BULLDOZER BRUTALITY", "COME ON LADZ!",
	"COMPETITIVE STREAK", "GO GET 'EM!", "TIDE OF MUSCLE",
	# More Dakka!
	"CALL DAT DAKKA?", "ORKS IS STILL ORKS", "SPESHUL SHELLS",
	"GET STUCK IN, LADZ!", "HUGE SHOW-OFFS",
	# Bully Boyz (HULKING BRUTES is auto via effects_json worsen_ap)
	"ALWAYS LOOKIN' FER A FIGHT", "ARMED TO DA TEEF", "CRUSHING IMPACT",
	"CUT' EM DOWN", "TOO ARROGANT TO DIE",
	# Da Big Hunt
	"DAT ONE'S EVEN BIGGA!", "DRAG IT DOWN", "INSTINCTIVE HUNTERS",
	"UNSTOPPABLE MOMENTUM", "STALKIN' TAKTIKS", "WHERE D'YA FINK YOU'RE GOING?",
	# Kult of Speed
	"SPEEDIEST FREEKS", "SQUIG FLINGIN'", "BLITZA FIRE", "DAKKASTORM",
	"FULL THROTTLE!", "MORE GITZ OVER 'ERE!",
	# Dread Mob (EXTRA GUBBINZ + SUPERFUELLED BOILER are auto via effects_json)
	"BIGGER SHELLS FOR BIGGER GITZ", "DAKKA! DAKKA! DAKKA!",
	"KLANKIN' KLAWS", "CONNIVING RUNTS",
]

# Out-of-Phase Rules Restriction (P1-59)
# When a unit performs an out-of-phase action (e.g. Fire Overwatch during opponent's
# Movement/Charge phase), no other rules normally triggered in that simulated phase
# can be used. For example, if a unit shoots via Fire Overwatch, abilities like
# Sentinel Storm or Sanctified Flames (which trigger "after shooting") cannot be used.
# This flag is set when an out-of-phase action begins and cleared when it completes.
var _out_of_phase_action_active: bool = false
var _out_of_phase_player: int = 0  # The player performing the out-of-phase action
var _out_of_phase_unit_id: String = ""  # The unit performing the out-of-phase action

func _ready() -> void:
	_load_core_stratagems()
	_load_core_stratagems_11e()
	_init_faction_loader()
	print("StratagemManager: Loaded %d core stratagems" % stratagems.size())

func _init_faction_loader() -> void:
	"""Initialize the faction stratagem loader and load faction code mappings."""
	_faction_loader = FactionStratagemLoaderData.new()
	_faction_loader.load_faction_codes()

# ============================================================================
# STRATAGEM DEFINITIONS
# ============================================================================

func _load_core_stratagems() -> void:
	# Core stratagems available to all armies (10th Edition)
	# These are hardcoded for now; faction stratagems will be loaded from data later

	stratagems["insane_bravery"] = {
		"id": "insane_bravery",
		"name": "INSANE BRAVERY",
		"type": "Core – Epic Deed Stratagem",
		"cp_cost": 1,
		"timing": {
			"turn": "your",           # "your", "opponent", "either"
			"phase": "command",        # Phase when it can be used
			"trigger": "before_battle_shock_test"  # Specific trigger point
		},
		"target": {
			"type": "unit",
			"owner": "friendly",
			"conditions": ["needs_battle_shock_test"]
		},
		"effects": [
			{"type": "auto_pass_battle_shock"}
		],
		"restrictions": {
			"once_per": "battle",   # null, "turn", "phase", "battle"
		},
		"description": "Your unit automatically passes that Battle-shock test.",
		"when_text": "Battle-shock step of your Command phase, just before you take a Battle-shock test for a unit from your army.",
		"target_text": "That unit from your army.",
		"effect_text": "Your unit automatically passes that Battle-shock test.",
		"restriction_text": "You cannot use this Stratagem more than once per battle."
	}

	stratagems["command_re_roll"] = {
		"id": "command_re_roll",
		"name": "COMMAND RE-ROLL",
		"type": "Core – Battle Tactic Stratagem",
		"cp_cost": 1,
		"timing": {
			"turn": "either",
			"phase": "any",
			"trigger": "after_roll"
		},
		"target": {
			"type": "unit",
			"owner": "friendly",
			"conditions": []
		},
		"effects": [
			{"type": "reroll_last_roll"}
		],
		"restrictions": {
			"once_per": "phase",
		},
		"description": "You re-roll that roll, test or saving throw.",
		"when_text": "Any phase, just after you make a roll for a unit from your army.",
		"target_text": "That unit or model from your army.",
		"effect_text": "You re-roll that roll, test or saving throw.",
		"restriction_text": ""
	}

	stratagems["go_to_ground"] = {
		"id": "go_to_ground",
		"name": "GO TO GROUND",
		"type": "Core – Battle Tactic Stratagem",
		"cp_cost": 1,
		"timing": {
			"turn": "opponent",
			"phase": "shooting",
			"trigger": "after_target_selected"
		},
		"target": {
			"type": "unit",
			"owner": "friendly",
			"conditions": ["keyword:INFANTRY", "is_target_of_attack"]
		},
		"effects": [
			{"type": "grant_invuln", "value": 6},
			{"type": "grant_cover"}
		],
		"restrictions": {
			"once_per": "phase",
		},
		"description": "Until the end of the phase, all models in your unit have a 6+ invulnerable save and have the Benefit of Cover.",
		"when_text": "Your opponent's Shooting phase, just after an enemy unit has selected its targets.",
		"target_text": "One INFANTRY unit from your army that was selected as the target.",
		"effect_text": "Until the end of the phase, all models in your unit have a 6+ invulnerable save and have the Benefit of Cover.",
		"restriction_text": ""
	}

	stratagems["smokescreen"] = {
		"id": "smokescreen",
		"name": "SMOKESCREEN",
		"type": "Core – Wargear Stratagem",
		"cp_cost": 1,
		"timing": {
			"turn": "opponent",
			"phase": "shooting",
			"trigger": "after_target_selected"
		},
		"target": {
			"type": "unit",
			"owner": "friendly",
			"conditions": ["keyword:SMOKE", "is_target_of_attack"]
		},
		"effects": [
			{"type": "grant_cover"},
			{"type": "grant_stealth"}
		],
		"restrictions": {
			"once_per": "phase",
		},
		"description": "Until the end of the phase, all models in your unit have the Benefit of Cover and the Stealth ability.",
		"when_text": "Your opponent's Shooting phase, just after an enemy unit has selected its targets.",
		"target_text": "One SMOKE unit from your army that was selected as the target.",
		"effect_text": "Until the end of the phase, all models in your unit have the Benefit of Cover and the Stealth ability.",
		"restriction_text": ""
	}

	stratagems["epic_challenge"] = {
		"id": "epic_challenge",
		"name": "EPIC CHALLENGE",
		"type": "Core – Epic Deed Stratagem",
		"cp_cost": 1,
		"timing": {
			"turn": "either",
			"phase": "fight",
			"trigger": "fighter_selected"
		},
		"target": {
			"type": "model",
			"owner": "friendly",
			"conditions": ["keyword:CHARACTER", "in_engagement_range"]
		},
		"effects": [
			{"type": "grant_keyword", "keyword": "PRECISION", "scope": "melee"}
		],
		"restrictions": {
			"once_per": "phase",
		},
		"description": "Until the end of the phase, all melee attacks made by that model have the [PRECISION] ability.",
		"when_text": "Fight phase, when a CHARACTER unit from your army is selected to fight.",
		"target_text": "One CHARACTER model in your unit.",
		"effect_text": "Until the end of the phase, all melee attacks made by that model have the [PRECISION] ability.",
		"restriction_text": ""
	}

	stratagems["grenade"] = {
		"id": "grenade",
		"name": "GRENADE",
		"type": "Core – Wargear Stratagem",
		"cp_cost": 1,
		"timing": {
			"turn": "your",
			"phase": "shooting",
			"trigger": "shooting_phase_active"
		},
		"target": {
			"type": "unit",
			"owner": "friendly",
			"conditions": ["keyword:GRENADES", "not_advanced", "not_fell_back", "not_shot", "not_in_engagement"]
		},
		"effects": [
			{"type": "mortal_wounds", "dice": 6, "threshold": 4}
		],
		"restrictions": {
			"once_per": "phase",
		},
		"description": "Roll six D6: for each 4+, that enemy unit suffers 1 mortal wound.",
		"when_text": "Your Shooting phase.",
		"target_text": "One GRENADES unit from your army.",
		"effect_text": "Select one enemy unit within 8\" and visible. Roll six D6: for each 4+, that enemy unit suffers 1 mortal wound.",
		"restriction_text": ""
	}

	stratagems["tank_shock"] = {
		"id": "tank_shock",
		"name": "TANK SHOCK",
		"type": "Core – Strategic Ploy Stratagem",
		"cp_cost": 1,
		"timing": {
			"turn": "your",
			"phase": "charge",
			"trigger": "after_charge_move"
		},
		"target": {
			"type": "unit",
			"owner": "friendly",
			"conditions": ["keyword:VEHICLE", "charged_this_turn"]
		},
		"effects": [
			{"type": "mortal_wounds_toughness_based", "threshold": 5, "max": 6}
		],
		"restrictions": {
			"once_per": "phase",
		},
		"description": "Roll D6 equal to the Vehicle's Toughness. For each 5+, the enemy unit suffers 1 mortal wound (max 6).",
		"when_text": "Your Charge phase, just after a VEHICLE unit ends a Charge move.",
		"target_text": "That VEHICLE unit.",
		"effect_text": "Select one enemy unit within Engagement Range. Roll D6 equal to Toughness; for each 5+, 1 mortal wound (max 6).",
		"restriction_text": ""
	}

	# Balance Dataslate v3.3: Added TITANIC targeting restriction, "set up" trigger
	stratagems["fire_overwatch"] = {
		"id": "fire_overwatch",
		"name": "FIRE OVERWATCH",
		"type": "Core – Strategic Ploy Stratagem",
		"cp_cost": 1,
		"timing": {
			"turn": "opponent",
			"phase": "movement_or_charge",
			"trigger": "enemy_move_or_charge"
		},
		"target": {
			"type": "unit",
			"owner": "friendly",
			"conditions": ["within_24_of_enemy", "eligible_to_shoot", "not_titanic"]
		},
		"effects": [
			{"type": "overwatch_shoot", "hit_on": 6}
		],
		"restrictions": {
			"once_per": "turn",
		},
		"description": "Your unit can shoot that enemy unit, but only hit on unmodified 6s. Cannot target TITANIC units.",
		"when_text": "Your opponent's Movement or Charge phase, just after an enemy unit is set up or when an enemy unit starts or ends a Normal, Advance or Fall Back move, or declares a charge.",
		"target_text": "One unit from your army that is within 24\" of that enemy unit and that would be eligible to shoot if it were your Shooting phase.",
		"effect_text": "If that enemy unit is visible to your unit, your unit can shoot that enemy unit as if it were your Shooting phase. Until the end of the phase, each time a model in your unit makes a ranged attack, an unmodified Hit roll of 6 is required to score a hit.",
		"restriction_text": "You cannot target a TITANIC unit with this Stratagem. Once per turn."
	}

	# Balance Dataslate v3.3: CP cost reduced from 2 to 1, no longer denies Fights First,
	# instead denies Charge bonus. Target must be eligible to charge, not just "not in ER".
	stratagems["heroic_intervention"] = {
		"id": "heroic_intervention",
		"name": "HEROIC INTERVENTION",
		"type": "Core – Strategic Ploy Stratagem",
		"cp_cost": 1,
		"timing": {
			"turn": "opponent",
			"phase": "charge",
			"trigger": "after_enemy_charge_move"
		},
		"target": {
			"type": "unit",
			"owner": "friendly",
			"conditions": ["within_6_of_charging_enemy", "eligible_to_charge"]
		},
		"effects": [
			{"type": "counter_charge", "no_charge_bonus": true}
		],
		"restrictions": {
			"once_per": "phase",
		},
		"description": "Your unit declares a charge targeting only that enemy unit and resolves it. Does not receive Charge bonus.",
		"when_text": "Your opponent's Charge phase, just after an enemy unit ends a Charge move.",
		"target_text": "One unit from your army that is within 6\" of that enemy unit and would be eligible to declare a charge against that enemy unit if it were your Charge phase.",
		"effect_text": "Your unit now declares a charge that targets only that enemy unit, and you resolve that charge as if it were your Charge phase. Even if this charge is successful, your unit does not receive any Charge bonus this turn.",
		"restriction_text": "You can only select a VEHICLE unit from your army if it is a WALKER."
	}

	stratagems["counter_offensive"] = {
		"id": "counter_offensive",
		"name": "COUNTER-OFFENSIVE",
		"type": "Core – Strategic Ploy Stratagem",
		"cp_cost": 2,
		"timing": {
			"turn": "either",
			"phase": "fight",
			"trigger": "after_enemy_fought"
		},
		"target": {
			"type": "unit",
			"owner": "friendly",
			"conditions": ["in_engagement_range", "not_fought_this_phase"]
		},
		"effects": [
			{"type": "fight_next"}
		],
		"restrictions": {
			"once_per": "phase",
		},
		"description": "Your unit fights next.",
		"when_text": "Fight phase, just after an enemy unit has fought.",
		"target_text": "One unit from your army in Engagement Range that has not fought this phase.",
		"effect_text": "Your unit fights next.",
		"restriction_text": ""
	}

	stratagems["new_orders"] = {
		"id": "new_orders",
		"name": "NEW ORDERS",
		"type": "Core – Strategic Ploy Stratagem",
		"cp_cost": 1,
		"timing": {
			"turn": "your",
			"phase": "command",
			"trigger": "end_of_command_phase"
		},
		"target": {
			"type": "secondary_mission",
			"owner": "friendly",
			"conditions": []
		},
		"effects": [
			{"type": "discard_and_draw_secondary"}
		],
		"restrictions": {
			"once_per": "battle",
		},
		"description": "Discard one of your active Secondary Mission cards and draw a new one.",
		"when_text": "End of your Command phase.",
		"target_text": "One of your active Secondary Mission cards.",
		"effect_text": "Discard that Secondary Mission card. Then draw one card from your Secondary Mission deck.",
		"restriction_text": "You can only use this Stratagem once per battle."
	}

	# Balance Dataslate v3.3: Clarified Deep Strike clause — units with Deep Strike can use it
	# via Rapid Ingress even though it's not your Movement phase
	stratagems["rapid_ingress"] = {
		"id": "rapid_ingress",
		"name": "RAPID INGRESS",
		"type": "Core – Strategic Ploy Stratagem",
		"cp_cost": 1,
		"timing": {
			"turn": "opponent",
			"phase": "movement",
			"trigger": "end_of_enemy_movement"
		},
		"target": {
			"type": "unit",
			"owner": "friendly",
			"conditions": ["in_reserves"]
		},
		"effects": [
			{"type": "arrive_from_reserves", "allow_deep_strike": true}
		],
		"restrictions": {
			"once_per": "phase",
		},
		"description": "Your unit arrives on the battlefield as if it were the Reinforcements step. Deep Strike units can use their Deep Strike ability.",
		"when_text": "End of your opponent's Movement phase.",
		"target_text": "One unit from your army that is in Reserves.",
		"effect_text": "Your unit can arrive on the battlefield as if it were the Reinforcements step of your Movement phase, and if every model in that unit has the Deep Strike ability, you can set that unit up as described in the Deep Strike ability.",
		"restriction_text": "You cannot use this Stratagem to enable a unit to arrive on the battlefield during a battle round it would not normally be able to do so in."
	}

# ============================================================================
# FACTION STRATAGEM LOADING
# ============================================================================

func load_faction_stratagems_for_player(player: int) -> void:
	"""
	Load faction stratagems for a player based on their army's faction and detachment.
	Called after armies are loaded into GameState.
	"""
	if _faction_loader == null:
		_init_faction_loader()

	var faction_data = GameState.state.get("factions", {}).get(str(player), {})
	var faction_name = faction_data.get("name", "")
	var detachment_name = faction_data.get("detachment", "")

	if faction_name == "" or faction_name == "Unknown":
		print("StratagemManager: No faction data for player %d, skipping faction stratagems" % player)
		return

	print("StratagemManager: Loading faction stratagems for player %d — %s / %s" % [player, faction_name, detachment_name])

	var faction_strats = _faction_loader.load_faction_stratagems(faction_name, detachment_name)

	# Clear any previously loaded faction stratagems for this player
	_clear_player_faction_stratagems(player)

	# Add faction stratagems to the main stratagems dictionary
	var loaded_count = 0
	var implemented_count = 0
	for strat in faction_strats:
		var strat_id = strat.get("id", "")
		if strat_id == "":
			continue

		stratagems[strat_id] = strat
		_player_faction_stratagems[str(player)].append(strat_id)
		loaded_count += 1
		if strat.get("implemented", false):
			implemented_count += 1

	# Mark custom-implemented stratagems that can't be auto-detected from CSV effect text
	_mark_custom_implemented_stratagems(player)

	# Recount after marking
	implemented_count = 0
	for strat_id in _player_faction_stratagems[str(player)]:
		if stratagems.has(strat_id) and stratagems[strat_id].get("implemented", false):
			implemented_count += 1

	print("StratagemManager: Loaded %d faction stratagems for player %d (%d mechanically implemented)" % [loaded_count, player, implemented_count])

func _mark_custom_implemented_stratagems(player: int) -> void:
	"""Mark stratagems with custom implementations as 'implemented'.
	These are stratagems whose CSV effect text can't be auto-parsed by FactionStratagemLoader
	but have manual handling in _apply_stratagem_effects / _clear_stratagem_flags."""
	var player_key = str(player)
	for strat_id in _player_faction_stratagems.get(player_key, []):
		if not stratagems.has(strat_id):
			continue
		var strat = stratagems[strat_id]
		# Data sources use typographic apostrophes (BOARDIN’ RUSH) — normalize
		# so the straight-quoted handler names below keep matching.
		var name_upper = strat.get("name", "").replace("’", "'").to_upper()
		# GRAB AND BASH (OA-4): Waaagh! effects on single unit — custom implementation
		if name_upper == "GRAB AND BASH":
			strat["implemented"] = true
			print("StratagemManager: Marked '%s' as implemented (custom handler)" % strat.get("name", ""))
		# BASH AND GRAB (OA-3): re-roll wounds vs enemies near the Loot Objective
		if name_upper == "BASH AND GRAB":
			strat["implemented"] = true
			print("StratagemManager: Marked '%s' as implemented (custom handler)" % strat.get("name", ""))
		# BOARDIN' RUSH (OA-5): Skip advance roll, add flat 6" to Move — custom implementation
		if name_upper == "BOARDIN' RUSH":
			strat["implemented"] = true
			print("StratagemManager: Marked '%s' as implemented (custom handler)" % strat.get("name", ""))
		# ROLLING LOOT-HEAP (OA-6): Grant Anti-Vehicle 4+ to Flash Gitz ranged weapons
		if name_upper == "ROLLING LOOT-HEAP":
			strat["implemented"] = true
			print("StratagemManager: Marked '%s' as implemented (custom handler)" % strat.get("name", ""))
		# DECK FRAGGERS (OA-7): Grant BLAST to ranged weapons targeting INFANTRY
		if name_upper == "DECK FRAGGERS":
			strat["implemented"] = true
			print("StratagemManager: Marked '%s' as implemented (custom handler)" % strat.get("name", ""))
		# KRUMP AND RUN (OA-8): Reactive Normal move after enemy falls back
		if name_upper == "KRUMP AND RUN":
			strat["implemented"] = true
			print("StratagemManager: Marked '%s' as implemented (custom handler)" % strat.get("name", ""))
		# DEFIANT TO THE LAST (Lions): D6 roll per dying model, +2 CHARACTER, 4+ swing back
		if name_upper == "DEFIANT TO THE LAST":
			strat["implemented"] = true
			print("StratagemManager: Marked '%s' as implemented (custom handler)" % strat.get("name", ""))
		# SWIFT AS THE EAGLE (Lions): D6" Normal move after being shot at
		if name_upper == "SWIFT AS THE EAGLE":
			strat["implemented"] = true
			print("StratagemManager: Marked '%s' as implemented (custom handler)" % strat.get("name", ""))
		# UNLEASH THE LIONS (Lions): Split Allarus/Aquilon into single-model units
		if name_upper == "UNLEASH THE LIONS":
			strat["implemented"] = true
			print("StratagemManager: Marked '%s' as implemented (custom handler)" % strat.get("name", ""))
		# SPESHUL AMMO (Speedwaaagh!): Anti-Monster/Vehicle 4+ on non-Torrent ranged weapons
		if name_upper == "SPESHUL AMMO":
			strat["implemented"] = true
			print("StratagemManager: Marked '%s' as implemented (custom handler)" % strat.get("name", ""))
		# DED KILLY CONSTRUCTION (Speedwaaagh!): melee LANCE + conditional +1 Damage on charge
		if name_upper == "DED KILLY CONSTRUCTION":
			strat["implemented"] = true
			print("StratagemManager: Marked '%s' as implemented (custom handler)" % strat.get("name", ""))
		# MOBILE DAKKASTORM (Speedwaaagh!): +2 S from Speed Freeks/Trukk vs a marked enemy
		if name_upper == "MOBILE DAKKASTORM":
			strat["implemented"] = true
			print("StratagemManager: Marked '%s' as implemented (custom handler)" % strat.get("name", ""))
		# EVASIVE MANOOVA (Speedwaaagh!): remove a unit to Strategic Reserves
		if name_upper == "EVASIVE MANOOVA":
			strat["implemented"] = true
			print("StratagemManager: Marked '%s' as implemented (custom handler)" % strat.get("name", ""))
		# FIGHT PROPPA (Taktikal Brigade): melee SUSTAINED HITS 1 or LETHAL HITS (player's choice)
		if name_upper == "FIGHT PROPPA":
			strat["implemented"] = true
			print("StratagemManager: Marked '%s' as implemented (custom handler)" % strat.get("name", ""))
		# KRUNCHIN' DESCENT (Taktikal Brigade): D6 per Stormboy in ER, 4+ = 1 MW (max 6)
		if name_upper == "KRUNCHIN' DESCENT":
			strat["implemented"] = true
			print("StratagemManager: Marked '%s' as implemented (custom handler)" % strat.get("name", ""))
		# ON TO DA NEXT (Taktikal Brigade): reactive 6" Normal move after enemy Falls Back
		if name_upper == "ON TO DA NEXT":
			strat["implemented"] = true
			print("StratagemManager: Marked '%s' as implemented (custom handler)" % strat.get("name", ""))
		# DED SNEAKY (Taktikal Brigade): remove Kommandos/Stormboyz to Strategic Reserves
		if name_upper == "DED SNEAKY":
			strat["implemented"] = true
			print("StratagemManager: Marked '%s' as implemented (custom handler)" % strat.get("name", ""))
		# Ork detachment sweep (Green Tide, More Dakka!, Bully Boyz, Da Big
		# Hunt, Kult of Speed, Dread Mob, Blitz Brigade): batch marker.
		# CRUSHING IMPACT only refers to the Bully Boyz stratagem here — the
		# 11e core stratagem of the same name is a core entry, not faction.
		if name_upper in _CUSTOM_IMPLEMENTED_NAMES:
			strat["implemented"] = true
			print("StratagemManager: Marked '%s' as implemented (custom handler)" % strat.get("name", ""))

func load_all_faction_stratagems() -> void:
	"""Load faction stratagems for both players. Call after armies are loaded."""
	load_faction_stratagems_for_player(1)
	load_faction_stratagems_for_player(2)

func _clear_player_faction_stratagems(player: int) -> void:
	"""Remove previously loaded faction stratagems for a player."""
	var player_key = str(player)
	if _player_faction_stratagems.has(player_key):
		for strat_id in _player_faction_stratagems[player_key]:
			stratagems.erase(strat_id)
		_player_faction_stratagems[player_key] = []

func is_faction_stratagem(stratagem_id: String) -> bool:
	"""Check if a stratagem is a faction-specific stratagem (not Core)."""
	return stratagem_id.begins_with("faction_")

func get_stratagem_owner(stratagem_id: String) -> int:
	"""
	Get which player owns a faction stratagem. Returns 0 if it's a Core stratagem
	(available to both) or if the stratagem is unknown.
	"""
	if not is_faction_stratagem(stratagem_id):
		return 0  # Core stratagems are available to all

	for player_key in _player_faction_stratagems:
		if stratagem_id in _player_faction_stratagems[player_key]:
			return int(player_key)

	return 0

func get_faction_stratagems_for_player(player: int) -> Array:
	"""Get all faction stratagem definitions loaded for a player."""
	var result: Array = []
	var player_key = str(player)
	if _player_faction_stratagems.has(player_key):
		for strat_id in _player_faction_stratagems[player_key]:
			if stratagems.has(strat_id):
				result.append(stratagems[strat_id])
	return result

func get_implemented_faction_stratagems_for_player(player: int) -> Array:
	"""Get only mechanically implemented faction stratagems for a player."""
	var result: Array = []
	for strat in get_faction_stratagems_for_player(player):
		if strat.get("implemented", false):
			result.append(strat)
	return result

# ============================================================================
# LORD OF DECEIT — CALLIDUS ASSASSIN AURA
# ============================================================================

func get_lord_of_deceit_cp_increase(player: int, target_unit_id: String) -> int:
	"""Check if Lord of Deceit aura increases stratagem cost.
	Returns 1 if the target unit is within 12\" of an enemy Callidus with the aura, else 0."""
	var board = GameState.state
	var units = board.get("units", {})
	var target_unit = units.get(target_unit_id, {})
	if target_unit.is_empty():
		return 0
	var target_owner = target_unit.get("owner", -1)
	if target_owner != player:
		return 0
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", -1) == player:
			continue
		var abilities = unit.get("meta", {}).get("abilities", [])
		var has_aura = false
		for ability in abilities:
			var name = ability.get("name", "") if ability is Dictionary else str(ability)
			if "Lord of Deceit" in name:
				has_aura = true
				break
		if not has_aura:
			continue
		var has_alive_model = false
		for m in unit.get("models", []):
			if m.get("alive", true):
				has_alive_model = true
				break
		if not has_alive_model:
			continue
		var min_dist = INF
		for t_model in target_unit.get("models", []):
			if not t_model.get("alive", true):
				continue
			var t_pos = t_model.get("position", {})
			var tx = float(t_pos.get("x", t_pos.x if t_pos is Vector2 else 0))
			var ty = float(t_pos.get("y", t_pos.y if t_pos is Vector2 else 0))
			for a_model in unit.get("models", []):
				if not a_model.get("alive", true):
					continue
				var a_pos = a_model.get("position", {})
				var ax = float(a_pos.get("x", a_pos.x if a_pos is Vector2 else 0))
				var ay = float(a_pos.get("y", a_pos.y if a_pos is Vector2 else 0))
				var dx = tx - ax
				var dy = ty - ay
				var dist_px = sqrt(dx * dx + dy * dy)
				var dist_inches = dist_px / 40.0
				if dist_inches < min_dist:
					min_dist = dist_inches
		if min_dist <= 12.0:
			print("StratagemManager: LORD OF DECEIT — target %s is within 12\" of Callidus (%.1f\"), +1 CP" % [target_unit_id, min_dist])
			return 1
	return 0

# ============================================================================
# VALIDATION
# ============================================================================

## A4: at edition >= 11 the retired 10e core stratagems map to their 11e
## variants (<id>_11e). Phases keep calling can_use_stratagem/use_stratagem with
## the canonical 10e id (insane_bravery, command_re_roll, rapid_ingress,
## fire_overwatch, heroic_intervention, …); this redirects the lookup, CP cost
## and usage-tracking to the live 11e definition so the 11e core set is reachable
## without touching every phase trigger site. Idempotent; 10e unaffected.
func _resolve_core_id(stratagem_id: String) -> String:
	if GameConstants.edition >= 11 and not stratagem_id.ends_with("_11e"):
		# Irregular renames: the 11e ids that are not just "<10e id>_11e".
		# Without this, counter_offensive resolved to the RETIRED 10e entry
		# and Counter-Offensive was unusable (never offered) at edition 11.
		match stratagem_id:
			"counter_offensive":
				return "counteroffensive_11e"
			"grenade":
				return "explosives"
			"tank_shock":
				return "crushing_impact"
		var v := stratagem_id + "_11e"
		if stratagems.has(v):
			return v
	return stratagem_id

func can_use_stratagem(player: int, stratagem_id: String, target_unit_id: String = "", context: Dictionary = {}) -> Dictionary:
	"""
	Check if a player can use a specific stratagem right now.
	Returns { "can_use": bool, "reason": String }
	"""
	stratagem_id = _resolve_core_id(stratagem_id)
	if not stratagems.has(stratagem_id):
		return {"can_use": false, "reason": "Unknown stratagem: %s" % stratagem_id}

	var strat = stratagems[stratagem_id]

	# ISS-056: edition-gated availability — the 11e core set (15.02-15.12)
	# replaces the retired 10e core entries at edition >= 11.
	if int(strat.get("edition", 0)) > GameConstants.edition:
		return {"can_use": false, "reason": "%s requires edition %d" % [strat.name, int(strat.edition)]}
	if strat.has("edition_max") and GameConstants.edition > int(strat.edition_max):
		return {"can_use": false, "reason": "%s was retired — use the 11e core set" % strat.name}

	# Check player ownership for faction stratagems
	if is_faction_stratagem(stratagem_id):
		var owner = get_stratagem_owner(stratagem_id)
		if owner != 0 and owner != player:
			return {"can_use": false, "reason": "This stratagem belongs to player %d" % owner}
		# Check if stratagem is mechanically implemented
		if not strat.get("implemented", false):
			return {"can_use": false, "reason": "%s is not yet mechanically implemented" % strat.name}

	# Check CP (account for possible Strategic Mastery discount and Lord of Deceit increase)
	var effective_cost = strat.cp_cost
	if target_unit_id != "" and effective_cost > 0:
		var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
		if ability_mgr and ability_mgr.has_strategic_mastery(target_unit_id):
			if not ability_mgr.is_once_per_round_used(player, "Strategic Mastery"):
				effective_cost = maxi(effective_cost - 1, 0)
	# LORD OF DECEIT: +1 CP if target unit is within 12" of enemy Callidus with Lord of Deceit aura
	if target_unit_id != "":
		effective_cost += get_lord_of_deceit_cp_increase(player, target_unit_id)
	var player_cp = _get_player_cp(player)
	if player_cp < effective_cost:
		return {"can_use": false, "reason": "Not enough CP (need %d, have %d)" % [effective_cost, player_cp]}

	# Check usage restrictions
	var restriction_check = _check_usage_restriction(player, stratagem_id, strat)
	if not restriction_check.can_use:
		return restriction_check

	# ISS-056 (11e 15.01): "each player cannot target the same unit with
	# more than one stratagem in the same phase" (unless otherwise stated).
	if GameConstants.edition >= 11 and target_unit_id != "":
		var current_turn_11e = GameState.get_battle_round()
		var current_phase_11e = GameState.get_current_phase()
		for usage in _usage_history.get(str(player), []):
			if usage.get("target_unit_id", "") == target_unit_id \
					and usage.get("turn", -1) == current_turn_11e \
					and usage.get("phase", -1) == current_phase_11e:
				return {"can_use": false, "reason": "That unit has already been targeted by a stratagem this phase (11e core rules 15.01)"}

	# P1-59: Out-of-phase rules restriction
	# When an out-of-phase action is active (e.g. Fire Overwatch), block all stratagems
	# except: (a) the stratagem that initiated the out-of-phase action, and
	# (b) stratagems with phase:"any" (like Command Re-roll) which are not phase-specific.
	# Also allow if explicitly bypassed via context (e.g. the initial fire_overwatch use).
	if _out_of_phase_action_active and not context.get("bypass_out_of_phase_check", false):
		if stratagem_id != "fire_overwatch":
			var strat_phase = strat.get("timing", {}).get("phase", "")
			if strat_phase != "any":
				return {"can_use": false, "reason": "Cannot use %s during an out-of-phase action (e.g. Fire Overwatch)" % strat.get("name", stratagem_id)}

	# Check battle-shocked (battle-shocked units can't be affected by stratagems)
	# Exception: Insane Bravery explicitly allows targeting battle-shocked units
	if target_unit_id != "" and stratagem_id != "insane_bravery":
		var unit = GameState.get_unit(target_unit_id)
		if not unit.is_empty() and unit.get("flags", {}).get("battle_shocked", false):
			return {"can_use": false, "reason": "Battle-shocked units cannot be targeted by Stratagems"}

	# P3-93: Also check if the source unit (the unit using the stratagem) is battle-shocked.
	# Per core rules, a player "cannot use Stratagems to affect" a battle-shocked unit.
	# This covers self-targeted stratagems where the source unit IS the target.
	# Exception: Insane Bravery (used before Battle-shock test, targets unit needing test)
	var source_unit_id = context.get("source_unit_id", "")
	if source_unit_id != "" and stratagem_id != "insane_bravery":
		var source_unit = GameState.get_unit(source_unit_id)
		if not source_unit.is_empty() and source_unit.get("flags", {}).get("battle_shocked", false):
			return {"can_use": false, "reason": "Battle-shocked units cannot use Stratagems"}

	# ROLLING LOOT-HEAP (OA-6): Only Flash Gitz units can be targeted
	if strat.get("name", "").to_upper() == "ROLLING LOOT-HEAP" and target_unit_id != "":
		if not is_flash_gitz_unit(target_unit_id):
			return {"can_use": false, "reason": "Rolling Loot-heap can only target Flash Gitz units"}
		# Must not have already shot
		var target_unit = GameState.get_unit(target_unit_id)
		if not target_unit.is_empty() and target_unit.get("flags", {}).get("has_shot", false):
			return {"can_use": false, "reason": "Target unit has already been selected to shoot this phase"}

	# DECK FRAGGERS (OA-7): Must target an ORKS unit that hasn't shot
	if strat.get("name", "").to_upper() == "DECK FRAGGERS" and target_unit_id != "":
		var target_unit = GameState.get_unit(target_unit_id)
		if not target_unit.is_empty():
			if not RulesEngine.unit_has_keyword(target_unit, "ORKS"):
				return {"can_use": false, "reason": "Deck Fraggers can only target ORKS units"}
			if target_unit.get("flags", {}).get("has_shot", false):
				return {"can_use": false, "reason": "Target unit has already been selected to shoot this phase"}

	# KRUMP AND RUN (OA-8): Must target an ORKS unit
	if strat.get("name", "").to_upper() == "KRUMP AND RUN" and target_unit_id != "":
		var target_unit = GameState.get_unit(target_unit_id)
		if not target_unit.is_empty():
			if not RulesEngine.unit_has_keyword(target_unit, "ORKS"):
				return {"can_use": false, "reason": "Krump and Run can only target ORKS units"}

	# Generic CSV-parsed target-condition enforcement for faction stratagems
	# (keyword / keyword_any / not_shot / not_fought / fell_back_this_phase /
	# charged_this_turn / engagement-range conditions). Engagement-range is
	# computed live here because flags.in_engagement is only refreshed at the
	# start of the Shooting phase and is stale in every other phase.
	if target_unit_id != "" and is_faction_stratagem(stratagem_id):
		var cond_target: Dictionary = strat.get("target", {})
		var conditions: Array = cond_target.get("conditions", [])
		var cond_unit = GameState.get_unit(target_unit_id)
		if not cond_unit.is_empty() and not conditions.is_empty():
			var cond_context = context.duplicate() if typeof(context) == TYPE_DICTIONARY else {}
			# is_target_of_attack is gated by the reactive offering flow (which
			# does not thread context through to this validation) — treat it as
			# satisfied unless the caller explicitly says otherwise.
			if not cond_context.has("is_target_of_attack"):
				cond_context["is_target_of_attack"] = true
			var check_unit = cond_unit
			if "in_engagement_range" in conditions or "not_in_engagement_range" in conditions:
				var live_engaged: bool = RulesEngine.is_unit_engaged(target_unit_id, GameState.create_snapshot())
				cond_context["in_engagement_range"] = live_engaged
				# unit_matches_target ORs flags.in_engagement with the context —
				# override the possibly-stale flag on a copy so the live check wins.
				check_unit = cond_unit.duplicate()
				var check_flags = cond_unit.get("flags", {}).duplicate()
				check_flags["in_engagement"] = live_engaged
				check_unit["flags"] = check_flags
			if not FactionStratagemLoaderData.unit_matches_target(check_unit, cond_target, cond_context):
				return {"can_use": false, "reason": "%s cannot target that unit (target conditions not met)" % strat.get("name", stratagem_id)}

	# Turn + phase gate: reject stratagems outside their allowed turn/phase.
	# Synthesis §2 #12: StratagemPanel showed all stratagems regardless of phase.
	if not context.get("bypass_phase_check", false):
		var strat_turn = strat.get("timing", {}).get("turn", "either")
		if strat_turn != "either":
			var active_player = GameState.get_active_player()
			var is_your_turn = (player == active_player)
			if strat_turn == "your" and not is_your_turn:
				return {"can_use": false, "reason": "%s can only be used on your turn" % strat.get("name", stratagem_id)}
			if strat_turn == "opponent" and is_your_turn:
				return {"can_use": false, "reason": "%s can only be used on your opponent's turn" % strat.get("name", stratagem_id)}
		var strat_phase = strat.get("timing", {}).get("phase", "any")
		if strat_phase != "any":
			var current_phase_name = _phase_to_string(GameState.get_current_phase())
			var phase_match = (strat_phase == current_phase_name)
			if not phase_match and "_or_" in strat_phase:
				phase_match = current_phase_name in strat_phase.split("_or_")
			if not phase_match:
				return {"can_use": false, "reason": "%s can only be used during the %s phase" % [strat.get("name", stratagem_id), strat_phase.replace("_or_", " or ").replace("_", " ")]}

	return {"can_use": true, "reason": ""}

func _check_usage_restriction(player: int, stratagem_id: String, strat: Dictionary) -> Dictionary:
	"""Check once-per restrictions for a stratagem."""
	# 11e 15.07: RAPID INGRESS "cannot be used during the first battle
	# round" — generic not_battle_round restriction.
	var blocked_round = int(strat.get("restrictions", {}).get("not_battle_round", 0))
	if blocked_round > 0 and GameState.get_battle_round() == blocked_round:
		return {"can_use": false, "reason": "%s cannot be used during battle round %d" % [strat.name, blocked_round]}

	var restriction = strat.get("restrictions", {}).get("once_per", null)
	if restriction == null:
		return {"can_use": true, "reason": ""}

	var player_history = _usage_history.get(str(player), [])
	var current_turn = GameState.get_battle_round()
	var current_phase = GameState.get_current_phase()

	match restriction:
		"battle":
			# Check if this stratagem was ever used this battle
			for usage in player_history:
				if usage.stratagem_id == stratagem_id:
					return {"can_use": false, "reason": "%s can only be used once per battle" % strat.name}
		"turn":
			# Check if used this turn
			for usage in player_history:
				if usage.stratagem_id == stratagem_id and usage.turn == current_turn:
					return {"can_use": false, "reason": "%s can only be used once per turn" % strat.name}
		"phase":
			# Check if used this phase (same turn + same phase)
			for usage in player_history:
				if usage.stratagem_id == stratagem_id and usage.turn == current_turn and usage.phase == current_phase:
					return {"can_use": false, "reason": "%s can only be used once per phase" % strat.name}

	return {"can_use": true, "reason": ""}

# ============================================================================
# USAGE / EXECUTION
# ============================================================================

func _safe_apply_state_changes(diffs: Array) -> void:
	"""Apply state changes via PhaseManager if available, otherwise apply directly."""
	if PhaseManager != null:
		PhaseManager.apply_state_changes(diffs)
	else:
		# Fallback: apply diffs directly to GameState (for tests where PhaseManager isn't loaded)
		for diff in diffs:
			if diff.get("op", "") == "set":
				var parts = diff.path.split(".")
				var current = GameState.state
				for i in range(parts.size() - 1):
					var part = parts[i]
					if current is Dictionary:
						if not current.has(part):
							current[part] = {}
						current = current[part]
				var final_key = parts[-1]
				if current is Dictionary:
					current[final_key] = diff.value

func use_stratagem(player: int, stratagem_id: String, target_unit_id: String = "", context: Dictionary = {}) -> Dictionary:
	"""
	Use a stratagem. Validates, deducts CP, records usage, and returns effect data.
	Returns { "success": bool, "effects": Array, "diffs": Array, "message": String }
	"""
	stratagem_id = _resolve_core_id(stratagem_id)
	# Validate
	var validation = can_use_stratagem(player, stratagem_id, target_unit_id, context)
	if not validation.can_use:
		return {"success": false, "error": validation.reason, "diffs": []}

	var strat = stratagems[stratagem_id]
	var diffs = []

	# Calculate effective CP cost (check for Strategic Mastery discount and Lord of Deceit increase)
	var effective_cp_cost = strat.cp_cost
	var strategic_mastery_applied = false
	if target_unit_id != "" and effective_cp_cost > 0:
		var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
		if ability_mgr and ability_mgr.has_strategic_mastery(target_unit_id):
			if not ability_mgr.is_once_per_round_used(player, "Strategic Mastery"):
				effective_cp_cost = maxi(effective_cp_cost - 1, 0)
				strategic_mastery_applied = true
				ability_mgr.mark_once_per_round_used(player, "Strategic Mastery")
				print("StratagemManager: Strategic Mastery reduces CP cost of %s by 1 (was %d, now %d)" % [strat.name, strat.cp_cost, effective_cp_cost])
	# LORD OF DECEIT: +1 CP if target unit is within 12" of enemy Callidus
	var lord_of_deceit_increase = 0
	if target_unit_id != "":
		lord_of_deceit_increase = get_lord_of_deceit_cp_increase(player, target_unit_id)
		if lord_of_deceit_increase > 0:
			effective_cp_cost += lord_of_deceit_increase
			print("StratagemManager: Lord of Deceit increases CP cost of %s by %d (now %d)" % [strat.name, lord_of_deceit_increase, effective_cp_cost])

	# Deduct CP
	var current_cp = _get_player_cp(player)
	var new_cp = current_cp - effective_cp_cost
	diffs.append({
		"op": "set",
		"path": "players.%s.cp" % str(player),
		"value": new_cp
	})

	# Record usage
	var usage_record = {
		"stratagem_id": stratagem_id,
		"player": player,
		"target_unit_id": target_unit_id,
		"turn": GameState.get_battle_round(),
		"phase": GameState.get_current_phase(),
		"timestamp": Time.get_unix_time_from_system()
	}
	_usage_history[str(player)].append(usage_record)

	# Apply the CP diff immediately
	_safe_apply_state_changes(diffs)

	var cost_msg = "%d CP" % effective_cp_cost
	if strategic_mastery_applied:
		cost_msg += " (reduced from %d by Strategic Mastery)" % strat.cp_cost
	print("StratagemManager: Player %d used %s on %s (cost %s, %d -> %d)" % [
		player, strat.name, target_unit_id if target_unit_id != "" else "N/A",
		cost_msg, current_cp, new_cp
	])

	# Log to GameEventLog for player-visible game log
	var game_event_log = get_node_or_null("/root/GameEventLog")
	if game_event_log:
		var target_display = ""
		if target_unit_id != "":
			var target_unit = GameState.state.get("units", {}).get(target_unit_id, {})
			target_display = target_unit.get("meta", {}).get("name", target_unit_id)
		var log_msg = "Used %s (%s)" % [strat.name, cost_msg]
		if target_display != "":
			log_msg += " on %s" % target_display
		game_event_log.add_player_entry(player, log_msg)

	# Log to phase log
	GameState.add_action_to_phase_log({
		"type": "STRATAGEM_USED",
		"stratagem_id": stratagem_id,
		"stratagem_name": strat.name,
		"player": player,
		"target_unit_id": target_unit_id,
		"cp_cost": effective_cp_cost,
		"original_cp_cost": strat.cp_cost,
		"strategic_mastery_discount": strategic_mastery_applied,
		"turn": GameState.get_battle_round()
	})

	# Apply stratagem-specific effects to game state (unit flags for RulesEngine)
	var effect_diffs = _apply_stratagem_effects(stratagem_id, target_unit_id, strat, context)
	if not effect_diffs.is_empty():
		_safe_apply_state_changes(effect_diffs)
		diffs.append_array(effect_diffs)

	# Track active effect for duration management
	# Issue #368: parse duration from the stratagem's effect text. Wahapedia uses
	# "Until the end of the turn" for whole-turn effects (MULTIPOTENTIALITY,
	# RELENTLESS PERSECUTION, etc.) and "Until the end of the phase" for
	# single-phase effects. Default to end_of_phase if neither phrase matches.
	# GRAB AND BASH (OA-4) is a name-based exception kept for back-compat.
	var expires = "end_of_phase"
	var effect_text_lower = str(strat.get("effect_text", "")).to_lower()
	if "until the end of the turn" in effect_text_lower or "until the end of your turn" in effect_text_lower:
		expires = "end_of_turn"
	# DAT'S OURS (Taktikal Brigade): "Until the start of the next Command
	# phase" — end_of_turn effects are cleared by on_turn_start(), which
	# CommandPhase calls at the start of every Command phase, so the mapping
	# is exact.
	if "until the start of the next command phase" in effect_text_lower:
		expires = "end_of_turn"
	# "Until the start of YOUR next Command phase" (GRAB AND BASH, GET STUCK
	# IN LADZ!, HUGE SHOW-OFFS, ...) lasts a full battle round — cleared
	# owner-aware in on_turn_start via next_own_command_phase.
	if "until the start of your next command phase" in effect_text_lower:
		expires = "next_own_command_phase"
	if strat.get("name", "").to_upper() == "GRAB AND BASH":
		expires = "next_own_command_phase"
	add_active_effect({
		"stratagem_id": stratagem_id,
		"player": player,
		"target_unit_id": target_unit_id,
		"effects": strat.effects,
		"expires": expires,
		"applied_turn": GameState.get_battle_round(),
		"applied_phase": GameState.get_current_phase()
	})

	# Emit signal
	emit_signal("stratagem_used", player, stratagem_id, target_unit_id)

	return {
		"success": true,
		"effects": strat.effects,
		"diffs": diffs,
		"message": "Used %s" % strat.name
	}

# ============================================================================
# QUERIES
# ============================================================================

func get_available_stratagems_for_trigger(player: int, trigger: String, context: Dictionary = {}) -> Array:
	"""
	Get all stratagems a player could use at a specific trigger point.
	Returns array of stratagem definitions that pass validation.
	"""
	var available = []

	for strat_id in stratagems:
		var strat = stratagems[strat_id]

		# Check trigger matches
		if strat.timing.trigger != trigger:
			continue

		# Check turn timing
		var active_player = GameState.get_active_player()
		var is_your_turn = (player == active_player)
		match strat.timing.turn:
			"your":
				if not is_your_turn:
					continue
			"opponent":
				if is_your_turn:
					continue
			"either":
				pass  # Always available

		# Check phase
		var current_phase = GameState.get_current_phase()
		var phase_name = _phase_to_string(current_phase)
		if strat.timing.phase != "any" and strat.timing.phase != phase_name:
			# Also check compound phases like "movement_or_charge"
			if "_or_" in strat.timing.phase:
				var valid_phases = strat.timing.phase.split("_or_")
				if phase_name not in valid_phases:
					continue
			else:
				continue

		# Check if can be used (CP, restrictions)
		var target_unit_id = context.get("target_unit_id", "")
		var validation = can_use_stratagem(player, strat_id, target_unit_id, context)
		if validation.can_use:
			available.append(strat)

	return available

func get_stratagem(stratagem_id: String) -> Dictionary:
	"""Get a stratagem definition by ID."""
	return stratagems.get(stratagem_id, {})

func find_faction_stratagem_by_name(player: int, stratagem_name: String) -> String:
	"""Find a faction stratagem ID by its display name for a given player.
	Returns the stratagem ID or empty string if not found. Typographic
	apostrophes are normalized so "Where D'ya Fink You're Going?" matches the
	CSV's "WHERE D’YA FINK YOU’RE GOING?"."""
	var name_upper = stratagem_name.replace("’", "'").to_upper()
	var player_key = str(player)
	for strat_id in _player_faction_stratagems.get(player_key, []):
		if stratagems.has(strat_id):
			if stratagems[strat_id].get("name", "").replace("’", "'").to_upper() == name_upper:
				return strat_id
	return ""

func get_player_cp(player: int) -> int:
	"""Public accessor for player CP."""
	return _get_player_cp(player)

# ============================================================================
# TURN/PHASE LIFECYCLE
# ============================================================================

func on_phase_start(phase: int) -> void:
	"""Called when a new phase starts. Clears phase-scoped active effects."""
	_clear_expired_effects("end_of_phase")
	print("StratagemManager: Phase %s started, cleared phase-scoped effects" % _phase_to_string(phase))

func on_phase_end(phase: int) -> void:
	"""Called when a phase ends."""
	_clear_expired_effects("end_of_phase")

func on_turn_start(player: int) -> void:
	"""Called when a new turn starts for a player."""
	_clear_expired_effects("end_of_turn")
	# Owner-aware round-long effects ("until the start of YOUR next Command
	# phase" — GRAB AND BASH, GET STUCK IN LADZ!, HUGE SHOW-OFFS, ...): clear
	# only when the effect owner's own Command phase begins.
	_clear_expired_effects_for_player("next_own_command_phase", player)
	print("StratagemManager: Turn started for player %d, cleared turn-scoped effects" % player)

func on_battle_round_start(round_number: int) -> void:
	"""Called at the start of a new battle round."""
	# P3-106: Clear battle-round-scoped effects
	_clear_expired_effects("end_of_battle_round")
	print("StratagemManager: Battle round %d started, cleared battle-round-scoped effects" % round_number)
	# Note: Bonus CP tracking is reset in CommandPhase._on_phase_enter() via GameState.reset_bonus_cp_tracking()

func can_player_gain_bonus_cp(player: int) -> bool:
	"""Check if a player can still gain non-automatic CP this battle round.
	Per core rules FAQ: each player can only gain 1 bonus CP per battle round
	(beyond the 1 CP auto-generated each Command Phase)."""
	return GameState.can_gain_bonus_cp(player)

# ============================================================================
# OUT-OF-PHASE RULES RESTRICTION (P1-59)
# ============================================================================
# Per 10th Edition core rules: "When using out-of-phase rules to perform an action
# as if it were one of your phases, you cannot use any other rules that are normally
# triggered in that phase." E.g. Fire Overwatch allows shooting, but you cannot use
# Sentinel Storm, Sanctified Flames, or any shooting-phase stratagems during it.

func set_out_of_phase_active(active: bool, player: int = 0, unit_id: String = "") -> void:
	"""Set/clear the out-of-phase action flag. Call before resolving reactive actions."""
	_out_of_phase_action_active = active
	_out_of_phase_player = player if active else 0
	_out_of_phase_unit_id = unit_id if active else ""
	if active:
		print("StratagemManager: OUT-OF-PHASE action started — Player %d, Unit %s (phase-specific rules blocked)" % [player, unit_id])
	else:
		print("StratagemManager: OUT-OF-PHASE action ended — phase-specific rules unblocked")

func is_out_of_phase_active() -> bool:
	"""Check if an out-of-phase action is currently in progress."""
	return _out_of_phase_action_active

func get_out_of_phase_unit_id() -> String:
	"""Get the unit ID performing the out-of-phase action."""
	return _out_of_phase_unit_id

# ============================================================================
# ACTIVE EFFECTS
# ============================================================================

func add_active_effect(effect: Dictionary) -> void:
	"""Add an active stratagem effect that lasts for a duration."""
	active_effects.append(effect)

func get_active_effects_for_unit(unit_id: String) -> Array:
	"""Get all active stratagem effects targeting a specific unit."""
	var effects = []
	for effect in active_effects:
		if effect.get("target_unit_id", "") == unit_id:
			effects.append(effect)
	return effects

func has_active_effect(unit_id: String, effect_type: String) -> bool:
	"""Check if a unit has a specific active effect."""
	for effect in active_effects:
		if effect.get("target_unit_id", "") == unit_id:
			for e in effect.get("effects", []):
				if e.get("type", "") == effect_type:
					return true
	return false

func _clear_expired_effects(expiry_type: String) -> void:
	"""Remove effects that have expired. Also clears unit flags set by expired stratagems."""
	var remaining = []
	for effect in active_effects:
		if effect.get("expires", "") != expiry_type:
			remaining.append(effect)
		else:
			# Clear unit flags for this expired effect
			var unit_id = effect.get("target_unit_id", "")
			var strat_id = effect.get("stratagem_id", "")
			if unit_id != "":
				_clear_stratagem_flags(unit_id, strat_id)
	active_effects = remaining

func _clear_expired_effects_for_player(expiry_type: String, player: int) -> void:
	"""Owner-aware variant: only clears matching effects owned by `player`.
	Used for 'until the start of YOUR next Command phase' durations."""
	var remaining = []
	for effect in active_effects:
		if effect.get("expires", "") != expiry_type or int(effect.get("player", 0)) != player:
			remaining.append(effect)
		else:
			var unit_id = effect.get("target_unit_id", "")
			var strat_id = effect.get("stratagem_id", "")
			if unit_id != "":
				_clear_stratagem_flags(unit_id, strat_id)
	active_effects = remaining

# ============================================================================
# STRATAGEM EFFECT APPLICATION
# ============================================================================

func _apply_stratagem_effects(_stratagem_id: String, target_unit_id: String, strat: Dictionary, context: Dictionary = {}) -> Array:
	"""
	Apply stratagem effects to unit flags in game state using EffectPrimitives.
	Returns an array of diffs that set the appropriate flags.
	These flags are read by RulesEngine during combat resolution.
	"""
	# ── A4: 11e core stratagem effects (15.02-15.12). The 10e core entries are
	# retired at edition 11 (edition_max), so these structured-effect handlers
	# only fire for the *_11e definitions. Effects that map to a concrete unit
	# flag or an immediate dice resolution are applied here; the phase-flow
	# triggers (ingress/snap/charge/reroll/auto-pass/fights-first) fall through
	# to their phase handlers. ──
	if int(strat.get("edition", 10)) >= 11:
		var diffs11: Array = []
		for eff in strat.get("effects", []):
			match str(eff.get("type", "")):
				"grant_weapon_ability":
					# EPIC CHALLENGE (15.03): [PRECISION] for one CHARACTER's melee weapons.
					if str(eff.get("ability", "")) == "precision":
						diffs11.append({"op": "set", "path": "units.%s.flags.effect_precision_melee" % target_unit_id, "value": true})
						print("StratagemManager: [11e] EPIC CHALLENGE — %s melee weapons gain [PRECISION]" % target_unit_id)
				"benefit_of_cover_aura":
					# SMOKESCREEN (15.10): the SMOKE unit gains the benefit of cover.
					# At 11e cover worsens the attacker's BS on the HIT side —
					# ModifierStack.collect_hit_context_11e reads
					# flags.stratagem_cover, so that flag is the one that makes
					# the effect real; effect_cover stays for the 10e save-side
					# readers and AI heuristics.
					diffs11.append({"op": "set", "path": "units.%s.flags.stratagem_cover" % target_unit_id, "value": true})
					diffs11.append({"op": "set", "path": "units.%s.flags.effect_cover" % target_unit_id, "value": true})
					print("StratagemManager: [11e] SMOKESCREEN — %s has the benefit of cover" % target_unit_id)
				"grant_fights_first":
					# COUNTEROFFENSIVE (15.12): the unit gains Fights First (the 11e
					# FightSequencer reads flags.fights_first).
					diffs11.append({"op": "set", "path": "units.%s.flags.fights_first" % target_unit_id, "value": true})
					print("StratagemManager: [11e] COUNTEROFFENSIVE — %s gains Fights First" % target_unit_id)
				"explosives_11e":
					# EXPLOSIVES (15.05): 6D6, 4+ = 1 MW to an enemy unit within 8".
					var enemy_e := str(context.get("enemy_unit_id", context.get("target_enemy_unit_id", "")))
					if enemy_e != "":
						var re = RulesEngine.resolve_explosives_11e(enemy_e, GameState.create_snapshot(), RulesEngine.make_rng())
						diffs11.append_array(re.get("diffs", []))
						print("StratagemManager: [11e] EXPLOSIVES — %d MW to %s" % [int(re.get("total_mortal_wounds", re.get("mortal_wounds", 0))), enemy_e])
				"crushing_impact_11e":
					# CRUSHING IMPACT (15.06): T-dice ram vs an engaged enemy.
					var enemy_c := str(context.get("enemy_unit_id", context.get("target_enemy_unit_id", "")))
					if enemy_c != "" and target_unit_id != "":
						var rc = RulesEngine.resolve_crushing_impact_11e(target_unit_id, enemy_c, GameState.create_snapshot(), RulesEngine.make_rng())
						diffs11.append_array(rc.get("diffs", []))
						print("StratagemManager: [11e] CRUSHING IMPACT — %d diffs vs %s" % [rc.get("diffs", []).size(), enemy_c])
		if not diffs11.is_empty():
			return diffs11

	# GRAB AND BASH (OA-4): Apply per-unit Waaagh! effects to a single unit.
	# Sets waaagh_active flag so RulesEngine applies +1S/+1A melee bonuses,
	# plus 5+ invuln and advance+charge eligibility.
	# Effects last until start of next Command phase (expires: "end_of_turn").
	if strat.get("name", "").to_upper() == "GRAB AND BASH":
		var diffs = [
			{"op": "set", "path": "units.%s.flags.waaagh_active" % target_unit_id, "value": true},
			{"op": "set", "path": "units.%s.flags.grab_and_bash_active" % target_unit_id, "value": true},
			{"op": "set", "path": "units.%s.flags.effect_invuln" % target_unit_id, "value": 5},
			{"op": "set", "path": "units.%s.flags.effect_invuln_source" % target_unit_id, "value": "Grab and Bash"},
			{"op": "set", "path": "units.%s.flags.effect_advance_and_charge" % target_unit_id, "value": true},
		]
		print("StratagemManager: Applied Grab and Bash — Waaagh! effects active for %s (5+ invuln, +1S/A melee, advance+charge)" % target_unit_id)
		return diffs

	# BOARDIN' RUSH (OA-5): Skip advance roll, add flat 6" to Move.
	# Sets a flag so MovementPhase._process_begin_advance() skips the D6 roll
	# and uses a flat 6" bonus instead. Expires at end of phase.
	if strat.get("name", "").replace("’", "'").to_upper() == "BOARDIN' RUSH":
		var diffs = [{
			"op": "set",
			"path": "units.%s.flags.effect_boardin_rush" % target_unit_id,
			"value": true
		}]
		print("StratagemManager: Applied Boardin' Rush to %s (flag: effect_boardin_rush — advance = flat +6\")" % target_unit_id)
		return diffs

	# BASH AND GRAB (OA-3): Conditional re-roll wounds — only vs targets near loot objective.
	# Override the generic REROLL_WOUNDS effect with a custom flag so RulesEngine can
	# apply the condition check at combat resolution time.
	if strat.get("name", "").to_upper() == "BASH AND GRAB":
		var diffs = [{
			"op": "set",
			"path": "units.%s.flags.effect_bash_and_grab" % target_unit_id,
			"value": true
		}]
		print("StratagemManager: Applied Bash and Grab effect to %s (flag: effect_bash_and_grab)" % target_unit_id)
		return diffs

	# ROLLING LOOT-HEAP (OA-6): Grant Anti-Vehicle 4+ to all ranged weapons until end of phase.
	# Sets a flag so RulesEngine lowers the critical wound threshold to 4+ vs VEHICLE targets.
	if strat.get("name", "").to_upper() == "ROLLING LOOT-HEAP":
		var diffs = [{
			"op": "set",
			"path": "units.%s.flags.effect_rolling_loot_heap" % target_unit_id,
			"value": true
		}]
		print("StratagemManager: Applied Rolling Loot-heap to %s (flag: effect_rolling_loot_heap — Anti-Vehicle 4+)" % target_unit_id)
		return diffs

	# DECK FRAGGERS (OA-7): Grant BLAST to ranged weapons when targeting INFANTRY.
	# Sets a flag so RulesEngine treats ranged weapons as BLAST vs INFANTRY targets.
	if strat.get("name", "").to_upper() == "DECK FRAGGERS":
		var diffs = [{
			"op": "set",
			"path": "units.%s.flags.effect_deck_fraggers" % target_unit_id,
			"value": true
		}]
		print("StratagemManager: Applied Deck Fraggers to %s (flag: effect_deck_fraggers — BLAST vs INFANTRY)" % target_unit_id)
		return diffs

	# KRUMP AND RUN (OA-8): No persistent flags — the effect is a reactive Normal move
	# handled by MovementPhase. Just log for tracking.
	if strat.get("name", "").to_upper() == "KRUMP AND RUN":
		print("StratagemManager: Applied Krump and Run to %s (reactive 6\" Normal move)" % target_unit_id)
		return []

	# DEFIANT TO THE LAST (Lions): D6 per dying model, +2 for CHARACTER, 4+ to swing back.
	# Uses a separate flag from ORKS IS NEVER BEATEN so RulesEngine applies the roll.
	if strat.get("name", "").to_upper() == "DEFIANT TO THE LAST":
		var diffs = [{
			"op": "set",
			"path": "units.%s.flags.%s" % [target_unit_id, EffectPrimitivesData.FLAG_DEFIANT_TO_THE_LAST],
			"value": true
		}]
		print("StratagemManager: Applied Defiant to the Last to %s (D6 roll per dying model, +2 CHARACTER, 4+ swing back)" % target_unit_id)
		return diffs

	# SWIFT AS THE EAGLE (Lions): D6" Normal move after being shot at.
	# Sets a flag so the shooting resolution can trigger the reactive move.
	if strat.get("name", "").to_upper() == "SWIFT AS THE EAGLE":
		var diffs = [{
			"op": "set",
			"path": "units.%s.flags.effect_swift_as_the_eagle" % target_unit_id,
			"value": true
		}]
		print("StratagemManager: Applied Swift as the Eagle to %s (D6\" Normal move after being shot)" % target_unit_id)
		return diffs

	# UNLEASH THE LIONS (Lions): Split unit into single-model units.
	# The actual splitting is handled by CommandPhase; we just set the flag here.
	if strat.get("name", "").to_upper() == "UNLEASH THE LIONS":
		var diffs = [{
			"op": "set",
			"path": "units.%s.flags.effect_unleash_the_lions" % target_unit_id,
			"value": true
		}]
		print("StratagemManager: Applied Unleash the Lions to %s (unit will be split)" % target_unit_id)
		return diffs

	# CAREEN! (War Horde): arm the just-destroyed ORKS VEHICLE to slide to
	# context.destination before its Deadly Demise mortal-wound roll resolves
	# (Issue #390 — RulesEngine.resolve_deadly_demise honours the pending-move
	# flags). The action layer supplies {"destination": {"x":..,"y":..}}.
	if strat.get("name", "").to_upper() == "CAREEN!":
		var careen_dest = context.get("destination", null) if typeof(context) == TYPE_DICTIONARY else null
		if careen_dest != null:
			var dest_vec: Vector2
			if careen_dest is Dictionary:
				dest_vec = Vector2(float(careen_dest.get("x", 0.0)), float(careen_dest.get("y", 0.0)))
			else:
				dest_vec = careen_dest
			RulesEngine.queue_careen_move(target_unit_id, dest_vec, GameState.state)
		else:
			print("StratagemManager: CAREEN! used without context.destination — no pending move queued")
		return []

	# SPESHUL AMMO (Speedwaaagh!): non-Torrent ranged weapons gain
	# [ANTI-MONSTER 4+] and [ANTI-VEHICLE 4+] until end of phase. RulesEngine
	# lowers the critical wound threshold to 4+ vs MONSTER/VEHICLE for this
	# unit's non-Torrent ranged weapons while the flag is set.
	if strat.get("name", "").to_upper() == "SPESHUL AMMO":
		var diffs_sa = [{
			"op": "set",
			"path": "units.%s.flags.effect_speshul_ammo" % target_unit_id,
			"value": true
		}]
		print("StratagemManager: Applied Speshul Ammo to %s (Anti-Monster/Vehicle 4+ on non-Torrent ranged weapons)" % target_unit_id)
		return diffs_sa

	# EVASIVE MANOOVA (Speedwaaagh!): remove the target unit from the battlefield
	# and place it into Strategic Reserves (it can arrive again on a later turn via
	# the normal reserves flow). Mirrors GameState.return_aircraft_to_reserves.
	if strat.get("name", "").to_upper() == "EVASIVE MANOOVA":
		var diffs_em = [
			{"op": "set", "path": "units.%s.status" % target_unit_id, "value": GameState.UnitStatus.IN_RESERVES},
			{"op": "set", "path": "units.%s.reserve_type" % target_unit_id, "value": "strategic_reserves"},
			{"op": "set", "path": "units.%s.flags.evasive_manoova_reserved" % target_unit_id, "value": true},
		]
		print("StratagemManager: Applied Evasive Manoova — %s removed to Strategic Reserves" % target_unit_id)
		return diffs_em

	# MOBILE DAKKASTORM (Speedwaaagh!): mark one enemy unit; until end of phase,
	# attacks from the user's SPEED FREEKS/TRUKK units targeting it get +2 Strength.
	# (target_unit_id is the marked enemy unit.)
	if strat.get("name", "").to_upper() == "MOBILE DAKKASTORM":
		var diffs_mob = [{
			"op": "set",
			"path": "units.%s.flags.mobile_dakkastorm_marked" % target_unit_id,
			"value": true
		}]
		print("StratagemManager: Applied Mobile Dakkastorm — %s marked (+2 S from Speed Freeks/Trukk)" % target_unit_id)
		return diffs_mob

	# DED KILLY CONSTRUCTION (Speedwaaagh!): melee weapons gain [LANCE]; if the
	# unit made a Charge move this turn, also +1 Damage to those weapons.
	if strat.get("name", "").to_upper() == "DED KILLY CONSTRUCTION":
		var ded_unit = GameState.state.get("units", {}).get(target_unit_id, {})
		var ded_charged = ded_unit.get("flags", {}).get("charged_this_turn", false)
		var diffs_dk = [{
			"op": "set",
			"path": "units.%s.flags.effect_grant_lance" % target_unit_id,
			"value": true
		}]
		if ded_charged:
			diffs_dk.append({
				"op": "set",
				"path": "units.%s.flags.effect_plus_damage" % target_unit_id,
				"value": 1
			})
		print("StratagemManager: Applied Ded Killy Construction to %s (LANCE%s)" % [target_unit_id, " + charged: +1 Damage" if ded_charged else ""])
		return diffs_dk

	# FIGHT PROPPA (Taktikal Brigade): melee weapons gain the player's choice of
	# [SUSTAINED HITS 1] or [LETHAL HITS] until end of phase. The choice arrives
	# as context.chosen_ability ("sustained" | "lethal"); default to sustained.
	# Melee-scoped flags so the grant does NOT leak into shooting resolution.
	if strat.get("name", "").to_upper() == "FIGHT PROPPA":
		var choice = str(context.get("chosen_ability", "sustained")).to_lower() if typeof(context) == TYPE_DICTIONARY else "sustained"
		var fp_flag = EffectPrimitivesData.FLAG_LETHAL_HITS_MELEE if choice.begins_with("lethal") else EffectPrimitivesData.FLAG_SUSTAINED_HITS_MELEE
		var diffs_fp = [{
			"op": "set",
			"path": "units.%s.flags.%s" % [target_unit_id, fp_flag],
			"value": true
		}]
		print("StratagemManager: Applied Fight Proppa to %s (melee %s)" % [target_unit_id, "LETHAL HITS" if choice.begins_with("lethal") else "SUSTAINED HITS 1"])
		return diffs_fp

	# KRUNCHIN' DESCENT (Taktikal Brigade): after a Stormboyz unit ends a Charge
	# move, roll one D6 per model within Engagement Range of the chosen enemy
	# unit; each 4+ is 1 mortal wound (max 6). Instant — no persistent flags.
	if strat.get("name", "").replace("’", "'").to_upper() == "KRUNCHIN' DESCENT":
		var enemy_kd := str(context.get("enemy_unit_id", context.get("target_enemy_unit_id", ""))) if typeof(context) == TYPE_DICTIONARY else ""
		if enemy_kd != "" and target_unit_id != "":
			var rk = RulesEngine.resolve_krunchin_descent(target_unit_id, enemy_kd, GameState.create_snapshot(), RulesEngine.make_rng())
			print("StratagemManager: KRUNCHIN' DESCENT — %d mortal wounds to %s" % [int(rk.get("mortal_wounds", 0)), enemy_kd])
			return rk.get("diffs", [])
		print("StratagemManager: KRUNCHIN' DESCENT used without context.enemy_unit_id — no dice rolled")
		return []

	# ON TO DA NEXT (Taktikal Brigade): no persistent flags — the effect is a
	# reactive 6" Normal move handled by MovementPhase (same scaffolding as
	# KRUMP AND RUN). Just log for tracking.
	if strat.get("name", "").to_upper() == "ON TO DA NEXT":
		print("StratagemManager: Applied On to da Next to %s (reactive 6\" Normal move)" % target_unit_id)
		return []

	# DED SNEAKY (Taktikal Brigade): remove the target Kommandos/Stormboyz unit
	# from the battlefield into Strategic Reserves (mirrors EVASIVE MANOOVA).
	if strat.get("name", "").to_upper() == "DED SNEAKY":
		var diffs_ds = [
			{"op": "set", "path": "units.%s.status" % target_unit_id, "value": GameState.UnitStatus.IN_RESERVES},
			{"op": "set", "path": "units.%s.reserve_type" % target_unit_id, "value": "strategic_reserves"},
			{"op": "set", "path": "units.%s.flags.ded_sneaky_reserved" % target_unit_id, "value": true},
		]
		print("StratagemManager: Applied Ded Sneaky — %s removed to Strategic Reserves" % target_unit_id)
		return diffs_ds

	# Ork detachment sweep (Green Tide, More Dakka!, Bully Boyz, Da Big Hunt,
	# Kult of Speed, Dread Mob, Blitz Brigade): grouped custom handlers.
	var sweep_diffs = _apply_ork_sweep_effects(strat, target_unit_id, context)
	if sweep_diffs != null:
		return sweep_diffs

	var effects = strat.get("effects", [])
	var diffs = EffectPrimitivesData.apply_effects(effects, target_unit_id)

	# Track invuln source for UI display (P3-97)
	for effect in effects:
		if effect.get("type", "") == EffectPrimitivesData.GRANT_INVULN:
			diffs.append({
				"op": "set",
				"path": "units.%s.flags.effect_invuln_source" % target_unit_id,
				"value": strat.get("name", _stratagem_id)
			})
			break

	# Issue #392 VIGILANCE ETERNAL (Shield Host): the parser-emitted
	# STICKY_OBJECTIVE_CONTROL effect needs an objective_id to bind to. Find
	# the bearer's nearest controlled objective at use-time and lock it via
	# MissionManager. Also write the unit flag so the lock survives save/load
	# and the per-unit lock can be inspected/cleared.
	for effect in effects:
		if effect.get("type", "") == EffectPrimitivesData.STICKY_OBJECTIVE_CONTROL:
			var mm = get_node_or_null("/root/MissionManager")
			if mm == null:
				print("StratagemManager: VIGILANCE ETERNAL — MissionManager unavailable, skipping sticky lock")
				break
			var nearest_obj_id: String = mm.find_nearest_controlled_objective(target_unit_id)
			if nearest_obj_id.is_empty():
				print("StratagemManager: VIGILANCE ETERNAL — no controlled objective in range of %s" % target_unit_id)
				break
			var unit = GameState.get_unit(target_unit_id)
			var bearer_player = int(unit.get("owner", 0))
			var locked: bool = mm.lock_objective_via_stratagem(nearest_obj_id, bearer_player, target_unit_id)
			if locked:
				diffs.append({
					"op": "set",
					"path": "units.%s.flags.effect_sticky_objective_control" % target_unit_id,
					"value": nearest_obj_id
				})
				print("StratagemManager: VIGILANCE ETERNAL — locked %s via %s (Player %d)" % [nearest_obj_id, target_unit_id, bearer_player])
			break

	# Issue #375 MOB RULE: REMOVE_BATTLE_SHOCK clears the target's battle_shocked
	# flag instantly. Per Wahapedia: "That ORKS INFANTRY unit is no longer
	# Battle-shocked." Note that the actual battle-shock target may differ
	# from the stratagem's primary target (the Mob unit); the calling layer
	# should pass the secondary target as `context.battle_shock_target_id`.
	for effect in effects:
		if effect.get("type", "") == EffectPrimitivesData.REMOVE_BATTLE_SHOCK:
			var bs_target_id = context.get("battle_shock_target_id", target_unit_id) if typeof(context) == TYPE_DICTIONARY else target_unit_id
			diffs.append({
				"op": "set",
				"path": "units.%s.flags.battle_shocked" % bs_target_id,
				"value": false
			})
			print("StratagemManager: REMOVE_BATTLE_SHOCK clears battle_shocked on %s" % bs_target_id)
			break

	if not diffs.is_empty():
		var flag_names = EffectPrimitivesData.get_flag_names_for_effects(effects)
		print("StratagemManager: Applied %s effects to %s (flags: %s)" % [strat.name, target_unit_id, str(flag_names)])

	return diffs

func _clear_stratagem_flags(unit_id: String, stratagem_id: String) -> void:
	"""Clear stratagem-specific flags from a unit when the effect expires."""
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return

	var flags = unit.get("flags", {})
	var strat = stratagems.get(stratagem_id, {})

	# A4/11e core set: the structured-effect handlers in
	# _apply_stratagem_effects set flags EffectPrimitives doesn't know
	# about — clear them here or they leak past the phase (a unit that
	# used COUNTEROFFENSIVE would keep Fights First all battle).
	if int(strat.get("edition", 10)) >= 11:
		for eff in strat.get("effects", []):
			match str(eff.get("type", "")):
				"grant_weapon_ability":
					if str(eff.get("ability", "")) == "precision":
						flags.erase("effect_precision_melee")
				"benefit_of_cover_aura":
					flags.erase("stratagem_cover")
					flags.erase("effect_cover")
				"grant_fights_first":
					flags.erase("fights_first")
		print("StratagemManager: Cleared [11e] %s flags from %s" % [stratagem_id, unit_id])
		return

	# GRAB AND BASH (OA-4): Clear per-unit Waaagh! effects
	if strat.get("name", "").to_upper() == "GRAB AND BASH":
		if flags.has("grab_and_bash_active"):
			flags.erase("grab_and_bash_active")
			flags.erase("waaagh_active")
			flags.erase("effect_advance_and_charge")
			# Only clear invuln if it was set by Grab and Bash (don't clobber other sources)
			if flags.get("effect_invuln_source", "") == "Grab and Bash":
				flags.erase("effect_invuln")
				flags.erase("effect_invuln_source")
			print("StratagemManager: Cleared Grab and Bash (Waaagh!) effects from %s" % unit_id)
		return

	# BOARDIN' RUSH (OA-5): Clear custom flag
	if strat.get("name", "").replace("’", "'").to_upper() == "BOARDIN' RUSH":
		if flags.has("effect_boardin_rush"):
			flags.erase("effect_boardin_rush")
			print("StratagemManager: Cleared effect_boardin_rush from %s" % unit_id)
		return

	# BASH AND GRAB (OA-3): Clear custom flag
	if strat.get("name", "").to_upper() == "BASH AND GRAB":
		if flags.has("effect_bash_and_grab"):
			flags.erase("effect_bash_and_grab")
			print("StratagemManager: Cleared effect_bash_and_grab from %s" % unit_id)
		return

	# ROLLING LOOT-HEAP (OA-6): Clear Anti-Vehicle 4+ flag
	if strat.get("name", "").to_upper() == "ROLLING LOOT-HEAP":
		if flags.has("effect_rolling_loot_heap"):
			flags.erase("effect_rolling_loot_heap")
			print("StratagemManager: Cleared effect_rolling_loot_heap from %s" % unit_id)
		return

	# DECK FRAGGERS (OA-7): Clear BLAST-vs-INFANTRY flag
	if strat.get("name", "").to_upper() == "DECK FRAGGERS":
		if flags.has("effect_deck_fraggers"):
			flags.erase("effect_deck_fraggers")
			print("StratagemManager: Cleared effect_deck_fraggers from %s" % unit_id)
		return

	# DEFIANT TO THE LAST (Lions): Clear D6 swing-back flag
	if strat.get("name", "").to_upper() == "DEFIANT TO THE LAST":
		if flags.has(EffectPrimitivesData.FLAG_DEFIANT_TO_THE_LAST):
			flags.erase(EffectPrimitivesData.FLAG_DEFIANT_TO_THE_LAST)
			print("StratagemManager: Cleared %s from %s" % [EffectPrimitivesData.FLAG_DEFIANT_TO_THE_LAST, unit_id])
		return

	# SWIFT AS THE EAGLE (Lions): Clear reactive move flag
	if strat.get("name", "").to_upper() == "SWIFT AS THE EAGLE":
		if flags.has("effect_swift_as_the_eagle"):
			flags.erase("effect_swift_as_the_eagle")
			print("StratagemManager: Cleared effect_swift_as_the_eagle from %s" % unit_id)
		return

	# UNLEASH THE LIONS (Lions): Clear split flag
	if strat.get("name", "").to_upper() == "UNLEASH THE LIONS":
		if flags.has("effect_unleash_the_lions"):
			flags.erase("effect_unleash_the_lions")
			print("StratagemManager: Cleared effect_unleash_the_lions from %s" % unit_id)
		return

	# SPESHUL AMMO (Speedwaaagh!): Clear Anti-Monster/Vehicle flag
	if strat.get("name", "").to_upper() == "SPESHUL AMMO":
		if flags.has("effect_speshul_ammo"):
			flags.erase("effect_speshul_ammo")
			print("StratagemManager: Cleared effect_speshul_ammo from %s" % unit_id)
		return

	# EVASIVE MANOOVA (Speedwaaagh!): instant removal to Strategic Reserves — the
	# unit STAYS in reserves, so there is nothing to undo at end of phase.
	if strat.get("name", "").to_upper() == "EVASIVE MANOOVA":
		return

	# MOBILE DAKKASTORM (Speedwaaagh!): Clear the enemy mark
	if strat.get("name", "").to_upper() == "MOBILE DAKKASTORM":
		if flags.has("mobile_dakkastorm_marked"):
			flags.erase("mobile_dakkastorm_marked")
			print("StratagemManager: Cleared mobile_dakkastorm_marked from %s" % unit_id)
		return

	# DED KILLY CONSTRUCTION (Speedwaaagh!): Clear LANCE grant + any charge damage
	if strat.get("name", "").to_upper() == "DED KILLY CONSTRUCTION":
		if flags.has("effect_grant_lance"):
			flags.erase("effect_grant_lance")
		if flags.has("effect_plus_damage"):
			flags.erase("effect_plus_damage")
		print("StratagemManager: Cleared Ded Killy Construction flags from %s" % unit_id)
		return

	# FIGHT PROPPA (Taktikal Brigade): Clear whichever melee grant was chosen
	if strat.get("name", "").to_upper() == "FIGHT PROPPA":
		flags.erase(EffectPrimitivesData.FLAG_SUSTAINED_HITS_MELEE)
		flags.erase(EffectPrimitivesData.FLAG_LETHAL_HITS_MELEE)
		print("StratagemManager: Cleared Fight Proppa melee flags from %s" % unit_id)
		return

	# KRUNCHIN' DESCENT (Taktikal Brigade): instant mortal wounds — nothing to clear
	if strat.get("name", "").replace("’", "'").to_upper() == "KRUNCHIN' DESCENT":
		return

	# ON TO DA NEXT (Taktikal Brigade): the effect is the reactive move itself
	if strat.get("name", "").to_upper() == "ON TO DA NEXT":
		return

	# DED SNEAKY (Taktikal Brigade): instant removal to Strategic Reserves — the
	# unit STAYS in reserves, so there is nothing to undo at end of phase.
	if strat.get("name", "").to_upper() == "DED SNEAKY":
		return

	# Ork detachment sweep: grouped clear handlers.
	if _clear_ork_sweep_flags(strat, unit_id, flags):
		print("StratagemManager: Cleared %s flags from %s (Ork sweep)" % [stratagem_id, unit_id])
		return

	var effects = strat.get("effects", [])

	EffectPrimitivesData.clear_effects(effects, unit_id, flags)
	# Also clear invuln source when clearing invuln effect (P3-97)
	for effect in effects:
		if effect.get("type", "") == EffectPrimitivesData.GRANT_INVULN:
			flags.erase("effect_invuln_source")
			break
	print("StratagemManager: Cleared %s flags from %s" % [stratagem_id, unit_id])

# ============================================================================
# ORK DETACHMENT SWEEP — grouped custom stratagem handlers (2026-07)
# ============================================================================

func _apply_ork_sweep_effects(strat: Dictionary, target_unit_id: String, context) -> Variant:
	"""Grouped apply handlers for the Ork detachment sweep. Returns an Array of
	diffs when the stratagem matched, or null to fall through to the generic
	EffectPrimitives path."""
	var name_upper = strat.get("name", "").replace("’", "'").to_upper()
	match name_upper:
		# ---- GREEN TIDE ----------------------------------------------------
		"BRAGGIN' RIGHTS":
			# Two Boyz units within 6" of each other both count as 10+ models
			# until the start of your next Command phase. The second unit comes
			# from context.second_unit_id or defaults to the nearest other
			# BOYZ unit within 6" (logged).
			var buddy_id = str(context.get("second_unit_id", "")) if typeof(context) == TYPE_DICTIONARY else ""
			if buddy_id == "":
				buddy_id = _find_nearest_friendly_keyword_unit(target_unit_id, "BOYZ", 6.0)
			var br_diffs = [{"op": "set", "path": "units.%s.flags.%s" % [target_unit_id, EffectPrimitivesData.FLAG_COUNTS_AS_10], "value": true}]
			if buddy_id != "":
				br_diffs.append({"op": "set", "path": "units.%s.flags.%s" % [buddy_id, EffectPrimitivesData.FLAG_COUNTS_AS_10], "value": true})
				# Register the buddy for owner-aware expiry alongside the primary target.
				add_active_effect({
					"stratagem_id": strat.get("id", "braggin_rights"),
					"player": int(GameState.get_unit(target_unit_id).get("owner", 0)),
					"target_unit_id": buddy_id,
					"effects": [{"type": EffectPrimitivesData.COUNTS_AS_10}],
					"expires": "next_own_command_phase",
					"applied_turn": GameState.get_battle_round(),
					"applied_phase": GameState.get_current_phase()
				})
				print("StratagemManager: BRAGGIN' RIGHTS — %s and %s both count as 10+ models" % [target_unit_id, buddy_id])
			else:
				print("StratagemManager: BRAGGIN' RIGHTS — no second BOYZ unit within 6\" of %s (single grant)" % target_unit_id)
			return br_diffs
		"BULLDOZER BRUTALITY":
			# Models within 3" become eligible to fight (melee eligibility
			# extension read in RulesEngine.get_eligible_melee_model_indices).
			print("StratagemManager: BULLDOZER BRUTALITY — %s fights at 3\" eligibility this phase" % target_unit_id)
			return [{"op": "set", "path": "units.%s.flags.effect_fight_range_3" % target_unit_id, "value": true}]
		"COME ON LADZ!":
			# Return up to D3+2 destroyed models to the unit. Simplification:
			# models are revived at the position they died at.
			var rng_cl = RulesEngine.make_rng()
			var to_return = rng_cl.rng.randi_range(1, 3) + 2
			var unit_cl = GameState.get_unit(target_unit_id)
			var cl_diffs: Array = []
			var revived := 0
			var models = unit_cl.get("models", [])
			for i in range(models.size()):
				if revived >= to_return:
					break
				var m = models[i]
				if not m.get("alive", true):
					cl_diffs.append({"op": "set", "path": "units.%s.models.%d.alive" % [target_unit_id, i], "value": true})
					cl_diffs.append({"op": "set", "path": "units.%s.models.%d.current_wounds" % [target_unit_id, i], "value": int(m.get("wounds", 1))})
					revived += 1
			print("StratagemManager: COME ON LADZ! — rolled D3+2=%d, returned %d destroyed model(s) to %s" % [to_return, revived, target_unit_id])
			return cl_diffs
		"COMPETITIVE STREAK":
			# Re-roll wound rolls of 1 (all failed while the unit counts as
			# 10+ models). Fight-phase only, so the unscoped wound-reroll flag
			# cannot leak into shooting before it expires at end of phase.
			var unit_cs = GameState.get_unit(target_unit_id)
			var cs_scope = "failed" if FactionAbilityManager.unit_counts_as_10(unit_cs) else "ones"
			print("StratagemManager: COMPETITIVE STREAK — %s re-rolls wound rolls (%s) this phase" % [target_unit_id, cs_scope])
			return [{"op": "set", "path": "units.%s.flags.%s" % [target_unit_id, EffectPrimitivesData.FLAG_REROLL_WOUNDS], "value": cs_scope}]
		"GO GET 'EM!":
			# Reactive D6" move after the attacking unit shoots — offered and
			# resolved by ShootingPhase via the Swift-as-the-Eagle scaffolding.
			print("StratagemManager: GO GET 'EM! applied to %s (reactive move handled by ShootingPhase)" % target_unit_id)
			return []
		"TIDE OF MUSCLE":
			var unit_tm = GameState.get_unit(target_unit_id)
			var tm_diffs = [{"op": "set", "path": "units.%s.flags.%s" % [target_unit_id, EffectPrimitivesData.FLAG_PLUS_CHARGE], "value": 1}]
			var tm_big = FactionAbilityManager.unit_counts_as_10(unit_tm)
			if tm_big:
				tm_diffs.append({"op": "set", "path": "units.%s.flags.%s" % [target_unit_id, EffectPrimitivesData.FLAG_REROLL_CHARGE], "value": true})
			print("StratagemManager: TIDE OF MUSCLE — %s +1 to charge rolls%s" % [target_unit_id, " + re-roll (10+ models)" if tm_big else ""])
			return tm_diffs
		# ---- MORE DAKKA! ---------------------------------------------------
		"CALL DAT DAKKA?":
			# Shoot back at the unit that just shot: full shooting sequence at
			# unmodified BS (no hit modifiers — documented simplification),
			# resolved through the overwatch machinery with hit_on_six=false.
			var cdd_enemy := str(context.get("enemy_unit_id", context.get("target_enemy_unit_id", ""))) if typeof(context) == TYPE_DICTIONARY else ""
			if cdd_enemy == "" or target_unit_id == "":
				print("StratagemManager: CALL DAT DAKKA? used without context.enemy_unit_id — no shots fired")
				return []
			var cdd = RulesEngine.resolve_overwatch_shooting(target_unit_id, cdd_enemy, GameState.create_snapshot(), RulesEngine.make_rng(), false)
			print("StratagemManager: CALL DAT DAKKA? — %s shoots back at %s: %d hits, %d casualties" % [
				target_unit_id, cdd_enemy, int(cdd.get("total_hits", 0)), int(cdd.get("total_casualties", 0))])
			return cdd.get("diffs", [])
		"ORKS IS STILL ORKS":
			# Melee wound re-roll 1s (full vs targets near objectives) — the
			# per-target scope is resolved live in the melee wound block.
			print("StratagemManager: ORKS IS STILL ORKS — %s re-rolls melee wounds this phase" % target_unit_id)
			return [{"op": "set", "path": "units.%s.flags.effect_orks_is_still_orks" % target_unit_id, "value": true}]
		"SPESHUL SHELLS":
			print("StratagemManager: SPESHUL SHELLS — %s +1 AP on ranged attacks vs targets within 18\" this phase" % target_unit_id)
			return [{"op": "set", "path": "units.%s.flags.effect_speshul_shells_md" % target_unit_id, "value": true}]
		"GET STUCK IN, LADZ!":
			# Unit-scoped Waaagh! until the start of your next Command phase —
			# mirrors GRAB AND BASH (Freebooter Krew).
			var gsl_diffs = [
				{"op": "set", "path": "units.%s.flags.waaagh_active" % target_unit_id, "value": true},
				{"op": "set", "path": "units.%s.flags.get_stuck_in_ladz_active" % target_unit_id, "value": true},
				{"op": "set", "path": "units.%s.flags.effect_invuln" % target_unit_id, "value": 5},
				{"op": "set", "path": "units.%s.flags.effect_invuln_source" % target_unit_id, "value": "Get Stuck In, Ladz!"},
				{"op": "set", "path": "units.%s.flags.effect_advance_and_charge" % target_unit_id, "value": true},
			]
			print("StratagemManager: GET STUCK IN, LADZ! — Waaagh! active for %s until your next Command phase" % target_unit_id)
			return gsl_diffs
		"HUGE SHOW-OFFS":
			# +1 Move / Leadership / OC and +1 to Hit until your next Command phase.
			var hso_diffs = [
				{"op": "set", "path": "units.%s.flags.%s" % [target_unit_id, EffectPrimitivesData.FLAG_PLUS_MOVE], "value": 1},
				{"op": "set", "path": "units.%s.flags.%s" % [target_unit_id, EffectPrimitivesData.FLAG_PLUS_OC], "value": 1},
				{"op": "set", "path": "units.%s.flags.%s" % [target_unit_id, EffectPrimitivesData.FLAG_PLUS_ONE_HIT], "value": true},
				{"op": "set", "path": "units.%s.flags.effect_improve_leadership" % target_unit_id, "value": 1},
			]
			print("StratagemManager: HUGE SHOW-OFFS — %s +1 Move/Ld/OC and +1 to hit until your next Command phase" % target_unit_id)
			return hso_diffs
		# ---- BULLY BOYZ ----------------------------------------------------
		"ALWAYS LOOKIN' FER A FIGHT":
			# Consolidation cap D3+3" (flat 6" while a Waaagh! is active).
			var alf_unit = GameState.get_unit(target_unit_id)
			var alf_cap := 6.0
			var alf_roll := 0
			if not FactionAbilityManager.is_waaagh_active_for_unit(alf_unit):
				var alf_rng = RulesEngine.make_rng()
				alf_roll = alf_rng.rng.randi_range(1, 3)
				alf_cap = float(alf_roll + 3)
			print("StratagemManager: ALWAYS LOOKIN' FER A FIGHT — %s consolidates up to %.0f\"%s" % [
				target_unit_id, alf_cap, " (D3=%d +3)" % alf_roll if alf_roll > 0 else " (Waaagh! active)"])
			return [{"op": "set", "path": "units.%s.flags.effect_consolidate_max" % target_unit_id, "value": alf_cap}]
		"ARMED TO DA TEEF":
			var att_unit = GameState.get_unit(target_unit_id)
			var att_scope = "failed" if FactionAbilityManager.is_waaagh_active_for_unit(att_unit) else "ones"
			print("StratagemManager: ARMED TO DA TEEF — %s re-rolls hit rolls (%s) this phase" % [target_unit_id, att_scope])
			return [{"op": "set", "path": "units.%s.flags.%s" % [target_unit_id, EffectPrimitivesData.FLAG_REROLL_HITS], "value": att_scope}]
		"CRUSHING IMPACT":
			# Bully Boyz variant: D6 per Nobz/Meganobz model in ER of the chosen
			# enemy; 5+ = 1 MW (4+ while a Waaagh! is active), max 6.
			var ci_enemy := str(context.get("enemy_unit_id", context.get("target_enemy_unit_id", ""))) if typeof(context) == TYPE_DICTIONARY else ""
			if ci_enemy == "" or target_unit_id == "":
				print("StratagemManager: CRUSHING IMPACT (Bully Boyz) used without context.enemy_unit_id — no dice rolled")
				return []
			var ci_unit = GameState.get_unit(target_unit_id)
			var ci_threshold = 4 if FactionAbilityManager.is_waaagh_active_for_unit(ci_unit) else 5
			var ci = RulesEngine.resolve_krunchin_descent(target_unit_id, ci_enemy, GameState.create_snapshot(), RulesEngine.make_rng(), ci_threshold)
			print("StratagemManager: CRUSHING IMPACT (Bully Boyz) — %d mortal wounds to %s (threshold %d+)" % [int(ci.get("mortal_wounds", 0)), ci_enemy, ci_threshold])
			return ci.get("diffs", [])
		"CUT' EM DOWN":
			# Mark the falling-back enemy: it must take Desperate Escape tests
			# for all models (FallBackMove.select_mode), at -1 while a Waaagh!
			# is active for the Nobz/Meganobz unit.
			var ced_enemy := str(context.get("enemy_unit_id", context.get("target_enemy_unit_id", ""))) if typeof(context) == TYPE_DICTIONARY else ""
			if ced_enemy == "":
				print("StratagemManager: CUT' EM DOWN used without context.enemy_unit_id — no effect")
				return []
			var ced_unit = GameState.get_unit(target_unit_id)
			var ced_diffs = [{"op": "set", "path": "units.%s.flags.effect_cut_em_down" % ced_enemy, "value": true}]
			if FactionAbilityManager.is_waaagh_active_for_unit(ced_unit):
				ced_diffs.append({"op": "set", "path": "units.%s.flags.effect_cut_em_down_minus1" % ced_enemy, "value": true})
			# Register the enemy for end-of-phase flag clearing.
			add_active_effect({
				"stratagem_id": strat.get("id", "cut_em_down"),
				"player": int(ced_unit.get("owner", 0)),
				"target_unit_id": ced_enemy,
				"effects": [{"type": "custom:cut_em_down"}],
				"expires": "end_of_phase",
				"applied_turn": GameState.get_battle_round(),
				"applied_phase": GameState.get_current_phase()
			})
			print("StratagemManager: CUT' EM DOWN — %s must take Desperate Escape tests when it Falls Back%s" % [
				ced_enemy, " (-1, Waaagh! active)" if ced_diffs.size() > 1 else ""])
			return ced_diffs
		"TOO ARROGANT TO DIE":
			print("StratagemManager: TOO ARROGANT TO DIE — %s's dying models swing back on 5+ (+2 in Waaagh!) this phase" % target_unit_id)
			return [{"op": "set", "path": "units.%s.flags.effect_too_arrogant_to_die" % target_unit_id, "value": true}]
		# ---- DA BIG HUNT ---------------------------------------------------
		"DAT ONE'S EVEN BIGGA!":
			# Eligible to charge after Advancing or Falling Back this phase.
			# The "re-roll Charge rolls vs your Prey" clause is the Prey rule's
			# own re-roll (FactionAbilityManager.unit_has_prey_charge_reroll),
			# which ChargePhase already offers to every BEAST SNAGGA unit.
			print("StratagemManager: DAT ONE'S EVEN BIGGA! — %s can charge after Advancing/Falling Back this phase" % target_unit_id)
			return [
				{"op": "set", "path": "units.%s.flags.effect_advance_and_charge" % target_unit_id, "value": true},
				{"op": "set", "path": "units.%s.flags.%s" % [target_unit_id, EffectPrimitivesData.FLAG_FALL_BACK_AND_CHARGE], "value": true},
			]
		"DRAG IT DOWN":
			# Melee weapons gain SUSTAINED HITS 1; melee crits on 5+ vs your
			# Prey (live per-target check in the melee resolver).
			print("StratagemManager: DRAG IT DOWN — %s melee SUSTAINED HITS 1 + crit 5+ vs Prey this phase" % target_unit_id)
			return [
				{"op": "set", "path": "units.%s.flags.%s" % [target_unit_id, EffectPrimitivesData.FLAG_SUSTAINED_HITS_MELEE], "value": true},
				{"op": "set", "path": "units.%s.flags.effect_drag_it_down" % target_unit_id, "value": true},
			]
		"INSTINCTIVE HUNTERS":
			# Remove the unengaged Beast Snagga unit into Strategic Reserves
			# (DED SNEAKY / EVASIVE MANOOVA pattern).
			print("StratagemManager: INSTINCTIVE HUNTERS — %s removed to Strategic Reserves" % target_unit_id)
			return [
				{"op": "set", "path": "units.%s.status" % target_unit_id, "value": GameState.UnitStatus.IN_RESERVES},
				{"op": "set", "path": "units.%s.reserve_type" % target_unit_id, "value": "strategic_reserves"},
				{"op": "set", "path": "units.%s.flags.instinctive_hunters_reserved" % target_unit_id, "value": true},
			]
		"UNSTOPPABLE MOMENTUM":
			# D6 per model in the unit (not just those in ER); 4+ = 1 MW, max
			# 6. Three extra dice when the chosen enemy is your Prey.
			var um_enemy := str(context.get("enemy_unit_id", context.get("target_enemy_unit_id", ""))) if typeof(context) == TYPE_DICTIONARY else ""
			if um_enemy == "" or target_unit_id == "":
				print("StratagemManager: UNSTOPPABLE MOMENTUM used without context.enemy_unit_id — no dice rolled")
				return []
			var um_unit = GameState.get_unit(target_unit_id)
			var um_owner = int(um_unit.get("owner", 0))
			var um_is_prey = GameState.get_unit(um_enemy).get("flags", {}).get("is_prey_of_%d" % um_owner, false)
			var um_bonus = 3 if um_is_prey else 0
			var um = RulesEngine.resolve_krunchin_descent(target_unit_id, um_enemy, GameState.create_snapshot(), RulesEngine.make_rng(), 4, false, um_bonus)
			print("StratagemManager: UNSTOPPABLE MOMENTUM — %d mortal wounds to %s%s" % [
				int(um.get("mortal_wounds", 0)), um_enemy, " (Prey: +3 dice)" if um_is_prey else ""])
			return um.get("diffs", [])
		"STALKIN' TAKTIKS":
			# Benefit of Cover vs ranged attacks; INFANTRY additionally gain
			# Stealth. Both until end of phase.
			var st_diffs = [{"op": "set", "path": "units.%s.flags.%s" % [target_unit_id, EffectPrimitivesData.FLAG_COVER], "value": true}]
			var st_infantry = RulesEngine.unit_has_keyword(GameState.get_unit(target_unit_id), "INFANTRY")
			if st_infantry:
				st_diffs.append({"op": "set", "path": "units.%s.flags.%s" % [target_unit_id, EffectPrimitivesData.FLAG_STEALTH], "value": true})
			print("StratagemManager: STALKIN' TAKTIKS — %s gains Benefit of Cover%s this phase" % [target_unit_id, " + Stealth (INFANTRY)" if st_infantry else ""])
			return st_diffs
		"WHERE D'YA FINK YOU'RE GOING?":
			# Reactive 6" Normal move after an enemy Falls Back — offered and
			# resolved by MovementPhase via the Krump-and-Run scaffolding.
			print("StratagemManager: WHERE D'YA FINK YOU'RE GOING? applied to %s (reactive move handled by MovementPhase)" % target_unit_id)
			return []
		# ---- KULT OF SPEED -------------------------------------------------
		"SPEEDIEST FREEKS":
			# 5+ invulnerable save; 4+ instead for VEHICLE units with an
			# unmodified Toughness of 8 or less.
			var sf_unit = GameState.get_unit(target_unit_id)
			var sf_inv := 5
			if RulesEngine.unit_has_keyword(sf_unit, "VEHICLE") \
					and int(sf_unit.get("meta", {}).get("stats", {}).get("toughness", 99)) <= 8:
				sf_inv = 4
			print("StratagemManager: SPEEDIEST FREEKS — %s gains a %d+ invulnerable save this phase" % [target_unit_id, sf_inv])
			return [
				{"op": "set", "path": "units.%s.flags.effect_invuln" % target_unit_id, "value": sf_inv},
				{"op": "set", "path": "units.%s.flags.effect_invuln_source" % target_unit_id, "value": "Speediest Freeks"},
			]
		"SQUIG FLINGIN'":
			# Chosen enemy within 9" takes a Battle-shock test at -1.
			var sq_enemy := str(context.get("enemy_unit_id", context.get("target_enemy_unit_id", ""))) if typeof(context) == TYPE_DICTIONARY else ""
			if sq_enemy == "":
				print("StratagemManager: SQUIG FLINGIN' used without context.enemy_unit_id — no test forced")
				return []
			var sq = FactionAbilityManager.force_battle_shock_test(sq_enemy, -1, "Squig Flingin'")
			print("StratagemManager: SQUIG FLINGIN' — %s takes a Battle-shock test at -1 (%s)" % [
				sq_enemy, "FAILED" if sq.get("failed", false) else "passed"])
			return []
		"BLITZA FIRE":
			# Ranged LETHAL HITS + crit 5+ vs targets within 9" (live checks in
			# the ranged resolvers). 11e 15.01 already prevents the same unit
			# being targeted by this and DAKKASTORM in one phase.
			print("StratagemManager: BLITZA FIRE — %s ranged LETHAL HITS + crit 5+ within 9\" this phase" % target_unit_id)
			return [
				{"op": "set", "path": "units.%s.flags.effect_lethal_hits_ranged" % target_unit_id, "value": true},
				{"op": "set", "path": "units.%s.flags.effect_blitza_fire" % target_unit_id, "value": true},
			]
		"DAKKASTORM":
			# Ranged SUSTAINED HITS 1 (2 while targeting a unit within 9") —
			# live per-target check in the ranged resolvers.
			print("StratagemManager: DAKKASTORM — %s ranged SUSTAINED HITS 1 (2 within 9\") this phase" % target_unit_id)
			return [{"op": "set", "path": "units.%s.flags.effect_dakkastorm_kos" % target_unit_id, "value": true}]
		"FULL THROTTLE!":
			# +1 to melee Wound rolls until the end of the turn.
			print("StratagemManager: FULL THROTTLE! — %s +1 to melee wound rolls until end of turn" % target_unit_id)
			return [{"op": "set", "path": "units.%s.flags.effect_full_throttle" % target_unit_id, "value": true}]
		"MORE GITZ OVER 'ERE!":
			# Reactive 6" Normal move after an enemy ends any move within 9" —
			# offered and resolved by MovementPhase via the Scatter! scaffolding.
			print("StratagemManager: MORE GITZ OVER 'ERE! applied to %s (reactive move handled by MovementPhase)" % target_unit_id)
			return []
		# ---- DREAD MOB -----------------------------------------------------
		"BIGGER SHELLS FOR BIGGER GITZ":
			# +1 to Wound vs MONSTER/VEHICLE; pushed: +1 Damage vs M/V too and
			# ranged weapons gain HAZARDOUS. Live per-target checks in the
			# ranged resolvers (get_bigger_shells_*_bonus).
			var bs_push = bool(context.get("push_it", false)) if typeof(context) == TYPE_DICTIONARY else false
			var bs_diffs = [{"op": "set", "path": "units.%s.flags.effect_bigger_shells" % target_unit_id, "value": true}]
			if bs_push:
				bs_diffs.append({"op": "set", "path": "units.%s.flags.effect_bigger_shells_push" % target_unit_id, "value": true})
				bs_diffs.append({"op": "set", "path": "units.%s.flags.effect_grant_hazardous" % target_unit_id, "value": true})
			print("StratagemManager: BIGGER SHELLS FOR BIGGER GITZ — %s +1 wound vs MONSTER/VEHICLE%s this phase" % [
				target_unit_id, " (+1 damage, HAZARDOUS — pushed)" if bs_push else ""])
			return bs_diffs
		"DAKKA! DAKKA! DAKKA!":
			# Re-roll hit 1s; pushed: full hit re-roll + ranged HAZARDOUS.
			var d3_push = bool(context.get("push_it", false)) if typeof(context) == TYPE_DICTIONARY else false
			var d3_scope = "failed" if d3_push else "ones"
			var d3_diffs = [{"op": "set", "path": "units.%s.flags.%s" % [target_unit_id, EffectPrimitivesData.FLAG_REROLL_HITS], "value": d3_scope}]
			if d3_push:
				d3_diffs.append({"op": "set", "path": "units.%s.flags.effect_grant_hazardous" % target_unit_id, "value": true})
			print("StratagemManager: DAKKA! DAKKA! DAKKA! — %s re-rolls hit rolls (%s)%s this phase" % [
				target_unit_id, d3_scope, " + HAZARDOUS (pushed)" if d3_push else ""])
			return d3_diffs
		"KLANKIN' KLAWS":
			# +2 S on melee weapons; pushed: +1 Damage and melee HAZARDOUS too.
			# The +Damage rides FLAG_PLUS_DAMAGE, whose only consumer is the
			# melee damage roll — safe for a Fight-phase-scoped effect.
			var kk_push = bool(context.get("push_it", false)) if typeof(context) == TYPE_DICTIONARY else false
			var kk_diffs = [{"op": "set", "path": "units.%s.flags.effect_klankin_klaws" % target_unit_id, "value": 2}]
			if kk_push:
				kk_diffs.append({"op": "set", "path": "units.%s.flags.%s" % [target_unit_id, EffectPrimitivesData.FLAG_PLUS_DAMAGE], "value": 1})
				kk_diffs.append({"op": "set", "path": "units.%s.flags.effect_grant_hazardous_melee" % target_unit_id, "value": true})
			print("StratagemManager: KLANKIN' KLAWS — %s melee +2 S%s this phase" % [
				target_unit_id, " (+1 damage, HAZARDOUS — pushed)" if kk_push else ""])
			return kk_diffs
		"CONNIVING RUNTS":
			# Reactive: D6 4+ = D3+1 mortal wounds to the enemy that just
			# moved, then a Normal move — offered and resolved by MovementPhase
			# via the Scatter! scaffolding.
			print("StratagemManager: CONNIVING RUNTS applied to %s (reactive resolution handled by MovementPhase)" % target_unit_id)
			return []
	return null

func _clear_ork_sweep_flags(strat: Dictionary, _unit_id: String, flags: Dictionary) -> bool:
	"""Grouped clear handlers for the Ork detachment sweep. Returns true when
	the stratagem was handled here."""
	var name_upper = strat.get("name", "").replace("’", "'").to_upper()
	match name_upper:
		# ---- GREEN TIDE ----------------------------------------------------
		"BRAGGIN' RIGHTS":
			flags.erase(EffectPrimitivesData.FLAG_COUNTS_AS_10)
			return true
		"BULLDOZER BRUTALITY":
			flags.erase("effect_fight_range_3")
			return true
		"COME ON LADZ!", "GO GET 'EM!":
			return true  # instant effects — nothing to clear
		"COMPETITIVE STREAK":
			flags.erase(EffectPrimitivesData.FLAG_REROLL_WOUNDS)
			return true
		"TIDE OF MUSCLE":
			flags.erase(EffectPrimitivesData.FLAG_PLUS_CHARGE)
			flags.erase(EffectPrimitivesData.FLAG_REROLL_CHARGE)
			return true
		# ---- MORE DAKKA! ---------------------------------------------------
		"CALL DAT DAKKA?":
			return true  # instant shoot-back — nothing to clear
		"ORKS IS STILL ORKS":
			flags.erase("effect_orks_is_still_orks")
			return true
		"SPESHUL SHELLS":
			flags.erase("effect_speshul_shells_md")
			return true
		"GET STUCK IN, LADZ!":
			if flags.has("get_stuck_in_ladz_active"):
				flags.erase("get_stuck_in_ladz_active")
				flags.erase("waaagh_active")
				flags.erase("effect_advance_and_charge")
				if flags.get("effect_invuln_source", "") == "Get Stuck In, Ladz!":
					flags.erase("effect_invuln")
					flags.erase("effect_invuln_source")
			return true
		"HUGE SHOW-OFFS":
			flags.erase(EffectPrimitivesData.FLAG_PLUS_MOVE)
			flags.erase(EffectPrimitivesData.FLAG_PLUS_OC)
			flags.erase(EffectPrimitivesData.FLAG_PLUS_ONE_HIT)
			flags.erase("effect_improve_leadership")
			return true
		# ---- BULLY BOYZ ----------------------------------------------------
		"ALWAYS LOOKIN' FER A FIGHT":
			flags.erase("effect_consolidate_max")
			return true
		"ARMED TO DA TEEF":
			flags.erase(EffectPrimitivesData.FLAG_REROLL_HITS)
			return true
		"CRUSHING IMPACT":
			return true  # instant mortal wounds — nothing to clear
		"CUT' EM DOWN":
			flags.erase("effect_cut_em_down")
			flags.erase("effect_cut_em_down_minus1")
			return true
		"TOO ARROGANT TO DIE":
			flags.erase("effect_too_arrogant_to_die")
			return true
		# ---- DA BIG HUNT ---------------------------------------------------
		"DAT ONE'S EVEN BIGGA!":
			flags.erase("effect_advance_and_charge")
			flags.erase(EffectPrimitivesData.FLAG_FALL_BACK_AND_CHARGE)
			return true
		"DRAG IT DOWN":
			flags.erase(EffectPrimitivesData.FLAG_SUSTAINED_HITS_MELEE)
			flags.erase("effect_drag_it_down")
			return true
		"INSTINCTIVE HUNTERS", "UNSTOPPABLE MOMENTUM", "WHERE D'YA FINK YOU'RE GOING?":
			return true  # instant effects — nothing to clear
		"STALKIN' TAKTIKS":
			flags.erase(EffectPrimitivesData.FLAG_COVER)
			flags.erase(EffectPrimitivesData.FLAG_STEALTH)
			return true
		# ---- KULT OF SPEED -------------------------------------------------
		"SPEEDIEST FREEKS":
			if flags.get("effect_invuln_source", "") == "Speediest Freeks":
				flags.erase("effect_invuln")
				flags.erase("effect_invuln_source")
			return true
		"SQUIG FLINGIN'", "MORE GITZ OVER 'ERE!":
			return true  # instant effects — nothing to clear
		"BLITZA FIRE":
			flags.erase("effect_lethal_hits_ranged")
			flags.erase("effect_blitza_fire")
			return true
		"DAKKASTORM":
			flags.erase("effect_dakkastorm_kos")
			return true
		# ---- DREAD MOB -----------------------------------------------------
		"BIGGER SHELLS FOR BIGGER GITZ":
			flags.erase("effect_bigger_shells")
			flags.erase("effect_bigger_shells_push")
			flags.erase("effect_grant_hazardous")
			return true
		"DAKKA! DAKKA! DAKKA!":
			flags.erase(EffectPrimitivesData.FLAG_REROLL_HITS)
			flags.erase("effect_grant_hazardous")
			return true
		"KLANKIN' KLAWS":
			flags.erase("effect_klankin_klaws")
			flags.erase(EffectPrimitivesData.FLAG_PLUS_DAMAGE)
			flags.erase("effect_grant_hazardous_melee")
			return true
		"CONNIVING RUNTS":
			return true  # instant effect — nothing to clear
		"FULL THROTTLE!":
			flags.erase("effect_full_throttle")
			return true
	return false

func _find_nearest_friendly_keyword_unit(unit_id: String, keyword: String, max_inches: float) -> String:
	"""Nearest other friendly unit with `keyword` whose closest model is within
	max_inches of the reference unit. Returns "" when none qualifies."""
	var units = GameState.state.get("units", {})
	var unit = units.get(unit_id, {})
	var owner = int(unit.get("owner", 0))
	var best_id := ""
	var best_dist := INF
	var max_px = Measurement.inches_to_px(max_inches)
	for uid in units:
		if uid == unit_id:
			continue
		var other = units[uid]
		if int(other.get("owner", 0)) != owner:
			continue
		if not RulesEngine.unit_has_keyword(other, keyword):
			continue
		for m in unit.get("models", []):
			if not m.get("alive", true) or m.get("position") == null:
				continue
			for om in other.get("models", []):
				if not om.get("alive", true) or om.get("position") == null:
					continue
				var d = Measurement.model_to_model_distance_px(m, om)
				if d <= max_px and d < best_dist:
					best_dist = d
					best_id = uid
	return best_id

## Audit #11: enemy targets for the two attacker-driven 11e core stratagems.
## explosives (15.05): unengaged enemy units with a model within 8" of (and
## visible to) a model in the friendly unit. crushing_impact (15.06): enemy
## units the friendly MONSTER/VEHICLE is engaged with.
func get_stratagem_enemy_targets(stratagem_id: String, friendly_unit_id: String) -> Array:
	var out: Array = []
	# KRUNCHIN' DESCENT (Taktikal Brigade), CRUSHING IMPACT / CUT' EM DOWN
	# (Bully Boyz) and UNSTOPPABLE MOMENTUM (Da Big Hunt) share the
	# crushing_impact target rule: enemy units the friendly unit is in
	# Engagement Range of.
	# CALL DAT DAKKA? (More Dakka!) may target any enemy unit (weapons out of
	# range simply produce no shots when the shoot-back resolves).
	var _strat_name = str(stratagems.get(stratagem_id, {}).get("name", "")).replace("’", "'").to_upper()
	if _strat_name in ["KRUNCHIN' DESCENT", "CRUSHING IMPACT", "CUT' EM DOWN", "UNSTOPPABLE MOMENTUM"]:
		# Enemy units the friendly unit is in Engagement Range of.
		stratagem_id = "krunchin_descent"
	elif _strat_name == "CALL DAT DAKKA?":
		stratagem_id = "any_enemy"
	elif _strat_name == "SQUIG FLINGIN'":
		# Enemy units within 9" of the friendly unit.
		stratagem_id = "within_9_enemy"
	var snapshot = GameState.create_snapshot()
	var friendly = snapshot.get("units", {}).get(friendly_unit_id, {})
	if friendly.is_empty():
		return out
	var enemy_player = 3 - int(friendly.get("owner", 0))
	var tm = get_node_or_null("/root/TerrainManager")
	for uid in snapshot.get("units", {}):
		var enemy = snapshot.units[uid]
		if int(enemy.get("owner", 0)) != enemy_player:
			continue
		if enemy.get("embarked_in", null) != null:
			continue
		var has_alive := false
		for m in enemy.get("models", []):
			if m.get("alive", true) and m.get("position") != null:
				has_alive = true
				break
		if not has_alive:
			continue
		match stratagem_id:
			"crushing_impact", "krunchin_descent":
				if RulesEngine.check_units_in_engagement_range(friendly, enemy, snapshot):
					out.append(uid)
			"any_enemy":
				out.append(uid)
			"within_9_enemy":
				if RulesEngine.is_target_within_range_inches(friendly, enemy, 9.0):
					out.append(uid)
			"explosives":
				if RulesEngine.is_unit_engaged(uid, snapshot):
					continue
				var in_range_and_visible := false
				var range_px = Measurement.inches_to_px(8.0)
				for fm in friendly.get("models", []):
					if not fm.get("alive", true) or fm.get("position") == null:
						continue
					for em in enemy.get("models", []):
						if not em.get("alive", true) or em.get("position") == null:
							continue
						if Measurement.model_to_model_distance_px(fm, em) > range_px:
							continue
						if tm != null and not tm.model_visible_11e(fm, em):
							continue
						in_range_and_visible = true
						break
					if in_range_and_visible:
						break
				if in_range_and_visible:
					out.append(uid)
	return out

func get_grenade_eligible_units(player: int) -> Array:
	"""
	Get units that can use the GRENADE stratagem for the given player.
	Requirements: GRENADES keyword, not advanced, not fell back, not shot, not in engagement.
	Returns array of { unit_id: String, unit_name: String }
	"""
	var eligible = []

	# Check if grenade stratagem can be used at all (CP, restrictions)
	var validation = can_use_stratagem(player, "grenade")
	if not validation.can_use:
		return eligible

	var units = GameState.state.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue

		var flags = unit.get("flags", {})
		var keywords = unit.get("meta", {}).get("keywords", [])

		# Check GRENADES keyword
		var has_grenades = false
		for kw in keywords:
			if kw.to_upper() == "GRENADES":
				has_grenades = true
				break
		if not has_grenades:
			continue

		# Check exclusions
		if flags.get("advanced", false):
			continue
		if flags.get("fell_back", false):
			continue
		if flags.get("has_shot", false):
			continue
		if flags.get("in_engagement", false):
			continue
		if flags.get("battle_shocked", false):
			continue

		# Must be deployed/moved
		var status = unit.get("status", 0)
		if status != GameStateData.UnitStatus.DEPLOYED and status != GameStateData.UnitStatus.MOVED:
			continue

		# Check if unit has alive models
		var has_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue

		eligible.append({
			"unit_id": unit_id,
			"unit_name": unit.get("meta", {}).get("name", unit_id)
		})

	return eligible

func get_rolling_loot_heap_eligible_units(player: int) -> Array:
	"""
	Get units eligible for the ROLLING LOOT-HEAP stratagem for the given player.
	Requirements: Must be a Flash Gitz unit, not already shot, not battle-shocked.
	Returns array of { unit_id: String, unit_name: String }
	"""
	var eligible = []

	# Find the Rolling Loot-heap stratagem ID
	var strat_id = ""
	for sid in stratagems:
		if stratagems[sid].get("name", "").to_upper() == "ROLLING LOOT-HEAP":
			strat_id = sid
			break
	if strat_id == "":
		return eligible

	# Check if Rolling Loot-heap can be used at all (CP, restrictions)
	var validation = can_use_stratagem(player, strat_id)
	if not validation.can_use:
		return eligible

	var units = GameState.state.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue

		# Must be a Flash Gitz unit (check unit name)
		var unit_name = unit.get("meta", {}).get("name", "").to_upper()
		if "FLASH GITZ" not in unit_name:
			continue

		var flags = unit.get("flags", {})

		# Cannot have already shot
		if flags.get("has_shot", false):
			continue
		# Cannot be battle-shocked
		if flags.get("battle_shocked", false):
			continue

		# Must be deployed/moved
		var status = unit.get("status", 0)
		if status != GameStateData.UnitStatus.DEPLOYED and status != GameStateData.UnitStatus.MOVED:
			continue

		# Must have alive models
		var has_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue

		eligible.append({
			"unit_id": unit_id,
			"unit_name": unit.get("meta", {}).get("name", unit_id)
		})

	return eligible

func get_deck_fraggers_eligible_units(player: int) -> Array:
	"""
	Get units eligible for the DECK FRAGGERS stratagem for the given player.
	Requirements: Must be an ORKS unit, not already shot, not battle-shocked.
	Returns array of { unit_id: String, unit_name: String }
	"""
	var eligible = []

	# Find the Deck Fraggers stratagem ID
	var strat_id = ""
	for sid in stratagems:
		if stratagems[sid].get("name", "").to_upper() == "DECK FRAGGERS":
			strat_id = sid
			break
	if strat_id == "":
		return eligible

	# Check if Deck Fraggers can be used at all (CP, restrictions)
	var validation = can_use_stratagem(player, strat_id)
	if not validation.can_use:
		return eligible

	var units = GameState.state.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue

		# Must be an ORKS unit
		if not RulesEngine.unit_has_keyword(unit, "ORKS"):
			continue

		var flags = unit.get("flags", {})

		# Cannot have already shot
		if flags.get("has_shot", false):
			continue
		# Cannot be battle-shocked
		if flags.get("battle_shocked", false):
			continue

		# Must be deployed/moved
		var status = unit.get("status", 0)
		if status != GameStateData.UnitStatus.DEPLOYED and status != GameStateData.UnitStatus.MOVED:
			continue

		# Must have alive models
		var has_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue

		eligible.append({
			"unit_id": unit_id,
			"unit_name": unit.get("meta", {}).get("name", unit_id)
		})

	return eligible

func is_flash_gitz_unit(unit_id: String) -> bool:
	"""Check if a unit is a Flash Gitz unit (by name)."""
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return false
	return "FLASH GITZ" in unit.get("meta", {}).get("name", "").to_upper()

func execute_grenade(player: int, grenade_unit_id: String, target_unit_id: String) -> Dictionary:
	"""
	Execute the GRENADE stratagem: roll 6D6, each 4+ deals 1 mortal wound to target.
	Handles CP deduction, usage tracking, dice rolling, and mortal wound application.
	Returns { success: bool, diffs: Array, dice_rolls: Array, mortal_wounds: int,
	          casualties: int, message: String }
	"""
	# Validate
	var validation = can_use_stratagem(player, "grenade", grenade_unit_id)
	if not validation.can_use:
		return {"success": false, "error": validation.reason, "diffs": [], "dice_rolls": [], "mortal_wounds": 0, "casualties": 0}

	var strat = stratagems["grenade"]
	var diffs = []

	# Deduct CP
	var current_cp = _get_player_cp(player)
	var new_cp = current_cp - strat.cp_cost
	diffs.append({
		"op": "set",
		"path": "players.%s.cp" % str(player),
		"value": new_cp
	})

	# Record usage
	var usage_record = {
		"stratagem_id": "grenade",
		"player": player,
		"target_unit_id": grenade_unit_id,
		"turn": GameState.get_battle_round(),
		"phase": GameState.get_current_phase(),
		"timestamp": Time.get_unix_time_from_system()
	}
	_usage_history[str(player)].append(usage_record)

	# Apply CP diff
	_safe_apply_state_changes(diffs)

	print("StratagemManager: Player %d used GRENADE with %s targeting %s (cost %d CP, %d -> %d)" % [
		player, grenade_unit_id, target_unit_id, strat.cp_cost, current_cp, new_cp
	])

	# Log to phase log
	GameState.add_action_to_phase_log({
		"type": "STRATAGEM_USED",
		"stratagem_id": "grenade",
		"stratagem_name": strat.name,
		"player": player,
		"target_unit_id": grenade_unit_id,
		"enemy_target_unit_id": target_unit_id,
		"cp_cost": strat.cp_cost,
		"turn": GameState.get_battle_round()
	})

	# Roll 6D6
	var rng = RulesEngine.make_rng()
	var rolls = rng.roll_d6(6)

	# Count successes (4+)
	var mortal_wounds = 0
	for roll in rolls:
		if roll >= 4:
			mortal_wounds += 1

	print("StratagemManager: GRENADE rolled %s — %d mortal wound(s)" % [str(rolls), mortal_wounds])

	# Apply mortal wounds to the enemy target
	var mw_diffs = []
	var casualties = 0
	if mortal_wounds > 0:
		var board = GameState.create_snapshot()
		var mw_result = RulesEngine.apply_mortal_wounds(target_unit_id, mortal_wounds, board, rng)
		mw_diffs = mw_result.get("diffs", [])
		casualties = mw_result.get("casualties", 0)

		if not mw_diffs.is_empty():
			_safe_apply_state_changes(mw_diffs)
			diffs.append_array(mw_diffs)

		print("StratagemManager: GRENADE applied %d mortal wounds to %s (%d casualties)" % [mortal_wounds, target_unit_id, casualties])

	# Mark the grenade unit as having shot (it uses its shooting for this phase)
	var shot_diff = {
		"op": "set",
		"path": "units.%s.flags.has_shot" % grenade_unit_id,
		"value": true
	}
	_safe_apply_state_changes([shot_diff])
	diffs.append(shot_diff)

	# Track active effect (no persistent flags needed for grenade - it's instant)
	add_active_effect({
		"stratagem_id": "grenade",
		"player": player,
		"target_unit_id": grenade_unit_id,
		"effects": strat.effects,
		"expires": "end_of_phase",
		"applied_turn": GameState.get_battle_round(),
		"applied_phase": GameState.get_current_phase()
	})

	# Emit signal
	emit_signal("stratagem_used", player, "grenade", grenade_unit_id)

	# Log mortal wound results to phase log
	var target_unit = GameState.get_unit(target_unit_id)
	var target_name = target_unit.get("meta", {}).get("name", target_unit_id)
	var grenade_unit = GameState.get_unit(grenade_unit_id)
	var grenade_name = grenade_unit.get("meta", {}).get("name", grenade_unit_id)

	GameState.add_action_to_phase_log({
		"type": "GRENADE_RESULT",
		"player": player,
		"grenade_unit_id": grenade_unit_id,
		"grenade_unit_name": grenade_name,
		"target_unit_id": target_unit_id,
		"target_unit_name": target_name,
		"rolls": rolls,
		"mortal_wounds": mortal_wounds,
		"casualties": casualties
	})

	return {
		"success": true,
		"diffs": diffs,
		"dice_rolls": rolls,
		"mortal_wounds": mortal_wounds,
		"casualties": casualties,
		"message": "%s threw GRENADE at %s: rolled %s — %d mortal wound(s), %d casualt%s" % [
			grenade_name, target_name, str(rolls), mortal_wounds, casualties,
			"y" if casualties == 1 else "ies"
		]
	}

func is_epic_challenge_available(player: int, unit_id: String) -> Dictionary:
	"""
	Check if Epic Challenge stratagem is available for a fighter unit.
	The unit must contain a CHARACTER keyword to be eligible.
	Returns { available: bool, reason: String }
	"""
	# Check if the stratagem can be used at all (CP, restrictions)
	var validation = can_use_stratagem(player, "epic_challenge", unit_id)
	if not validation.can_use:
		return {"available": false, "reason": validation.reason}

	# Check CHARACTER keyword on the unit
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return {"available": false, "reason": "Unit not found"}

	var keywords = unit.get("meta", {}).get("keywords", [])
	var has_character = false
	for kw in keywords:
		if kw.to_upper() == "CHARACTER":
			has_character = true
			break

	if not has_character:
		return {"available": false, "reason": "Unit does not have CHARACTER keyword"}

	# Check unit is not battle-shocked
	var flags = unit.get("flags", {})
	if flags.get("battle_shocked", false):
		return {"available": false, "reason": "Battle-shocked units cannot use Stratagems"}

	return {"available": true, "reason": ""}

func is_command_reroll_available(player: int) -> Dictionary:
	"""
	Check if Command Re-roll is available for a player in the current phase.
	Returns { available: bool, reason: String }
	"""
	var validation = can_use_stratagem(player, "command_re_roll")
	if not validation.can_use:
		return {"available": false, "reason": validation.reason}
	return {"available": true, "reason": ""}

func execute_command_reroll(player: int, unit_id: String, roll_context: Dictionary) -> Dictionary:
	"""
	Execute the Command Re-roll stratagem: deduct CP, record usage, signal.
	The actual re-rolling of dice is handled by the calling phase.
	roll_context should contain: { roll_type, original_rolls, unit_name }
	Returns { success: bool, diffs: Array, message: String }
	"""
	var validation = can_use_stratagem(player, "command_re_roll", unit_id)
	if not validation.can_use:
		return {"success": false, "error": validation.reason, "diffs": []}

	# Use the standard use_stratagem flow for CP deduction and usage tracking
	var result = use_stratagem(player, "command_re_roll", unit_id)
	if not result.success:
		return result

	var roll_type = roll_context.get("roll_type", "unknown")
	var original_rolls = roll_context.get("original_rolls", [])
	var unit_name = roll_context.get("unit_name", unit_id)

	print("StratagemManager: COMMAND RE-ROLL executed by player %d on %s (%s roll: %s)" % [
		player, unit_name, roll_type, str(original_rolls)
	])

	# Log the reroll to phase log
	GameState.add_action_to_phase_log({
		"type": "COMMAND_REROLL",
		"player": player,
		"unit_id": unit_id,
		"unit_name": unit_name,
		"roll_type": roll_type,
		"original_rolls": original_rolls,
		"turn": GameState.get_battle_round()
	})

	return {
		"success": true,
		"diffs": result.get("diffs", []),
		"message": "COMMAND RE-ROLL used on %s (%s)" % [unit_name, roll_type]
	}

func is_counter_offensive_available(player: int) -> Dictionary:
	"""
	Check if Counter-Offensive stratagem is available for a player.
	Returns { available: bool, reason: String }
	"""
	var validation = can_use_stratagem(player, "counter_offensive")
	if not validation.can_use:
		return {"available": false, "reason": validation.reason}
	return {"available": true, "reason": ""}

func get_counter_offensive_eligible_units(player: int, units_that_fought: Array, game_state_snapshot: Dictionary) -> Array:
	"""
	Get units eligible for Counter-Offensive for a given player.
	Requirements: owned by player, in engagement range, not fought this phase, not battle-shocked.
	Returns array of { unit_id: String, unit_name: String }
	"""
	var eligible = []

	# Check if the stratagem can be used at all (CP, restrictions)
	var validation = can_use_stratagem(player, "counter_offensive")
	if not validation.can_use:
		return eligible

	var all_units = game_state_snapshot.get("units", {})
	for unit_id in all_units:
		var unit = all_units[unit_id]
		if int(unit.get("owner", 0)) != player:
			continue

		# Must not have already fought this phase
		if unit_id in units_that_fought:
			continue

		# Must not be battle-shocked
		var flags = unit.get("flags", {})
		if flags.get("battle_shocked", false):
			continue

		# Must have alive models
		var has_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue

		# Must be in engagement range of at least one enemy
		var in_engagement = false
		var unit_owner = int(unit.get("owner", 0))
		for other_unit_id in all_units:
			var other_unit = all_units[other_unit_id]
			if int(other_unit.get("owner", 0)) == unit_owner:
				continue
			if _units_in_engagement_range(unit, other_unit):
				in_engagement = true
				break

		if not in_engagement:
			continue

		eligible.append({
			"unit_id": unit_id,
			"unit_name": unit.get("meta", {}).get("name", unit_id)
		})

	return eligible

func _units_in_engagement_range(unit1: Dictionary, unit2: Dictionary) -> bool:
	"""Check if any model from unit1 is within 1\" of any model from unit2."""
	var models1 = unit1.get("models", [])
	var models2 = unit2.get("models", [])

	for model1 in models1:
		if not model1.get("alive", true):
			continue
		var pos1_data = model1.get("position", {})
		if pos1_data == null:
			continue

		for model2 in models2:
			if not model2.get("alive", true):
				continue
			var pos2_data = model2.get("position", {})
			if pos2_data == null:
				continue

			if Measurement.is_in_engagement_range_shape_aware(model1, model2):
				return true

	return false

func is_tank_shock_available(player: int) -> Dictionary:
	"""
	Check if Tank Shock stratagem is available for a player.
	Returns { available: bool, reason: String }
	"""
	var validation = can_use_stratagem(player, "tank_shock")
	if not validation.can_use:
		return {"available": false, "reason": validation.reason}
	return {"available": true, "reason": ""}

func get_tank_shock_eligible_targets(vehicle_unit_id: String, game_state_snapshot: Dictionary) -> Array:
	"""
	Get enemy units within Engagement Range (1") of a VEHICLE unit that just charged.
	Returns array of { unit_id: String, unit_name: String, model_count: int }
	"""
	var eligible = []
	var vehicle_unit = game_state_snapshot.get("units", {}).get(vehicle_unit_id, {})
	if vehicle_unit.is_empty():
		return eligible

	var vehicle_owner = int(vehicle_unit.get("owner", 0))
	var all_units = game_state_snapshot.get("units", {})

	for unit_id in all_units:
		var unit = all_units[unit_id]
		# Must be an enemy unit
		if int(unit.get("owner", 0)) == vehicle_owner:
			continue

		# Must have alive models
		var alive_count = 0
		for model in unit.get("models", []):
			if model.get("alive", true):
				alive_count += 1
		if alive_count == 0:
			continue

		# Must be within Engagement Range (1") of the vehicle
		if _units_in_engagement_range(vehicle_unit, unit):
			eligible.append({
				"unit_id": unit_id,
				"unit_name": unit.get("meta", {}).get("name", unit_id),
				"model_count": alive_count
			})

	return eligible

func execute_tank_shock(player: int, vehicle_unit_id: String, target_unit_id: String) -> Dictionary:
	"""
	Execute the TANK SHOCK stratagem: roll D6 equal to Vehicle's Toughness (max 6),
	each 5+ deals 1 mortal wound to the target enemy unit.
	Handles CP deduction, usage tracking, dice rolling, and mortal wound application.
	Returns { success: bool, diffs: Array, dice_rolls: Array, mortal_wounds: int,
	          casualties: int, toughness: int, dice_count: int, message: String }
	"""
	# Validate
	var validation = can_use_stratagem(player, "tank_shock", vehicle_unit_id)
	if not validation.can_use:
		return {"success": false, "error": validation.reason, "diffs": [], "dice_rolls": [], "mortal_wounds": 0, "casualties": 0, "toughness": 0, "dice_count": 0}

	var strat = stratagems["tank_shock"]
	var diffs = []

	# Get vehicle toughness (from meta.stats.toughness per army JSON structure)
	var vehicle_unit = GameState.get_unit(vehicle_unit_id)
	var toughness = int(vehicle_unit.get("meta", {}).get("stats", {}).get("toughness", 4))
	var dice_count = mini(toughness, 6)  # Max 6 dice per Balance Dataslate v3.3

	# Deduct CP
	var current_cp = _get_player_cp(player)
	var new_cp = current_cp - strat.cp_cost
	diffs.append({
		"op": "set",
		"path": "players.%s.cp" % str(player),
		"value": new_cp
	})

	# Record usage
	var usage_record = {
		"stratagem_id": "tank_shock",
		"player": player,
		"target_unit_id": vehicle_unit_id,
		"turn": GameState.get_battle_round(),
		"phase": GameState.get_current_phase(),
		"timestamp": Time.get_unix_time_from_system()
	}
	_usage_history[str(player)].append(usage_record)

	# Apply CP diff
	_safe_apply_state_changes(diffs)

	var vehicle_name = vehicle_unit.get("meta", {}).get("name", vehicle_unit_id)
	print("StratagemManager: Player %d used TANK SHOCK with %s (T%d, %dD6) targeting %s (cost %d CP, %d -> %d)" % [
		player, vehicle_name, toughness, dice_count, target_unit_id, strat.cp_cost, current_cp, new_cp
	])

	# Log to phase log
	GameState.add_action_to_phase_log({
		"type": "STRATAGEM_USED",
		"stratagem_id": "tank_shock",
		"stratagem_name": strat.name,
		"player": player,
		"target_unit_id": vehicle_unit_id,
		"enemy_target_unit_id": target_unit_id,
		"cp_cost": strat.cp_cost,
		"turn": GameState.get_battle_round()
	})

	# Roll D6 equal to Toughness (max 6)
	var rng = RulesEngine.make_rng()
	var rolls = rng.roll_d6(dice_count)

	# Count successes (5+)
	var mortal_wounds = 0
	for roll in rolls:
		if roll >= 5:
			mortal_wounds += 1

	print("StratagemManager: TANK SHOCK rolled %dD6 %s — %d mortal wound(s)" % [dice_count, str(rolls), mortal_wounds])

	# Apply mortal wounds to the enemy target
	var mw_diffs = []
	var casualties = 0
	if mortal_wounds > 0:
		var board = GameState.create_snapshot()
		var mw_result = RulesEngine.apply_mortal_wounds(target_unit_id, mortal_wounds, board, rng)
		mw_diffs = mw_result.get("diffs", [])
		casualties = mw_result.get("casualties", 0)

		if not mw_diffs.is_empty():
			_safe_apply_state_changes(mw_diffs)
			diffs.append_array(mw_diffs)

		print("StratagemManager: TANK SHOCK applied %d mortal wounds to %s (%d casualties)" % [mortal_wounds, target_unit_id, casualties])

	# Track active effect (no persistent flags needed — instant effect)
	add_active_effect({
		"stratagem_id": "tank_shock",
		"player": player,
		"target_unit_id": vehicle_unit_id,
		"effects": strat.effects,
		"expires": "end_of_phase",
		"applied_turn": GameState.get_battle_round(),
		"applied_phase": GameState.get_current_phase()
	})

	# Emit signal
	emit_signal("stratagem_used", player, "tank_shock", vehicle_unit_id)

	# Log mortal wound results to phase log
	var target_unit = GameState.get_unit(target_unit_id)
	var target_name = target_unit.get("meta", {}).get("name", target_unit_id)

	GameState.add_action_to_phase_log({
		"type": "TANK_SHOCK_RESULT",
		"player": player,
		"vehicle_unit_id": vehicle_unit_id,
		"vehicle_unit_name": vehicle_name,
		"target_unit_id": target_unit_id,
		"target_unit_name": target_name,
		"toughness": toughness,
		"dice_count": dice_count,
		"rolls": rolls,
		"mortal_wounds": mortal_wounds,
		"casualties": casualties
	})

	return {
		"success": true,
		"diffs": diffs,
		"dice_rolls": rolls,
		"mortal_wounds": mortal_wounds,
		"casualties": casualties,
		"toughness": toughness,
		"dice_count": dice_count,
		"message": "%s used TANK SHOCK on %s: rolled %dD6 (T%d) %s — %d mortal wound(s), %d casualt%s" % [
			vehicle_name, target_name, dice_count, toughness, str(rolls), mortal_wounds, casualties,
			"y" if casualties == 1 else "ies"
		]
	}

func is_fire_overwatch_available(player: int) -> Dictionary:
	"""
	Check if Fire Overwatch stratagem is available for a player.
	Returns { available: bool, reason: String }
	"""
	var validation = can_use_stratagem(player, "fire_overwatch")
	if not validation.can_use:
		return {"available": false, "reason": validation.reason}
	return {"available": true, "reason": ""}

func get_fire_overwatch_eligible_units(player: int, enemy_unit_id: String, game_state_snapshot: Dictionary) -> Array:
	"""
	Get units eligible to Fire Overwatch for a given player against an enemy unit.
	Requirements (10e rules):
	  - Owned by player
	  - Within 24\" of the enemy unit
	  - Not battle-shocked
	  - Has alive models
	  - Eligible to shoot (has ranged weapons, not in engagement range)
	Returns array of { unit_id: String, unit_name: String }
	"""
	var eligible = []

	# Check if the stratagem can be used at all (CP, restrictions)
	var validation = can_use_stratagem(player, "fire_overwatch")
	if not validation.can_use:
		return eligible

	var all_units = game_state_snapshot.get("units", {})
	var enemy_unit = all_units.get(enemy_unit_id, {})
	if enemy_unit.is_empty():
		return eligible

	for unit_id in all_units:
		var unit = all_units[unit_id]
		if int(unit.get("owner", 0)) != player:
			continue

		# Balance Dataslate v3.3: Cannot target a TITANIC unit with Fire Overwatch
		var keywords = unit.get("meta", {}).get("keywords", [])
		var is_titanic = false
		for kw in keywords:
			if kw.to_upper() == "TITANIC":
				is_titanic = true
				break
		if is_titanic:
			continue

		# Sneaky Gitz (Kommandos, 40kdc 11e): this unit cannot fire Overwatch
		# (rule-state "fire-overwatch" suppressed on self).
		var has_sneaky_gitz = false
		for ab in unit.get("meta", {}).get("abilities", []):
			var ab_name = ab if ab is String else (ab.get("name", "") if ab is Dictionary else "")
			if ab_name == "Sneaky Gitz":
				has_sneaky_gitz = true
				break
		if has_sneaky_gitz:
			print("StratagemManager: %s has Sneaky Gitz — cannot Fire Overwatch" % unit_id)
			continue

		# Must not be battle-shocked
		var flags = unit.get("flags", {})
		if flags.get("battle_shocked", false):
			continue

		# Must have alive models
		var has_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue

		# Must NOT already be in engagement range of any enemy unit (can't shoot while in melee)
		var in_engagement = false
		var unit_owner = int(unit.get("owner", 0))
		for other_unit_id in all_units:
			var other_unit = all_units[other_unit_id]
			if int(other_unit.get("owner", 0)) == unit_owner:
				continue
			if _units_in_engagement_range(unit, other_unit):
				in_engagement = true
				break
		if in_engagement:
			continue

		# Must have at least one ranged weapon
		var has_ranged_weapon = _unit_has_ranged_weapons(unit)
		if not has_ranged_weapon:
			continue

		# Must be within 24" of the enemy unit
		var within_24 = _unit_within_distance_of_unit(unit, enemy_unit, 24.0)
		if not within_24:
			continue

		eligible.append({
			"unit_id": unit_id,
			"unit_name": unit.get("meta", {}).get("name", unit_id)
		})

	return eligible

func _unit_has_ranged_weapons(unit: Dictionary) -> bool:
	"""Check if a unit has any ranged weapons (non-melee)."""
	var weapons = unit.get("meta", {}).get("weapons", [])
	for weapon in weapons:
		var weapon_type = weapon.get("type", "").to_lower()
		# A weapon is ranged if it's not a melee weapon
		if weapon_type != "melee":
			return true
		# Also check the range field - if range > 0, it's ranged
		var weapon_range = weapon.get("range", "")
		if weapon_range is String and weapon_range != "" and weapon_range != "Melee":
			return true
		elif weapon_range is int and weapon_range > 0:
			return true
		elif weapon_range is float and weapon_range > 0.0:
			return true
	return false

func is_heroic_intervention_available(player: int) -> Dictionary:
	"""
	Check if Heroic Intervention stratagem is available for a player.
	Returns { available: bool, reason: String }
	"""
	var validation = can_use_stratagem(player, "heroic_intervention")
	if not validation.can_use:
		return {"available": false, "reason": validation.reason}
	return {"available": true, "reason": ""}

# 11e 15.11: eligibility for the END-of-charge-phase HI window — one
# friendly unit that is unengaged, not battle-shocked, not a VEHICLE (unless
# CHARACTER or WALKER), AND has a legal target for at least one of the two HI
# modes. The modes (see ChargePhase._closest_hi_target_11e / the HI dialog):
#   LEAP TO DEFEND: closest enemy that CHARGED this turn, within 12".
#   INTO THE FRAY:  closest enemy within 6" (regardless of whether it charged).
# Offering the window on "any enemy within 12"" over-triggers — an enemy that
# merely sits at 8-12" and did not charge satisfies NEITHER mode, so the prompt
# was un-actionable (Leap finds no charged target, Fray finds none within 6")
# and the player was shown a Heroic Intervention offer they could not use.
func get_heroic_intervention_eligible_units_11e(player: int) -> Array:
	var eligible: Array = []
	var snapshot = GameState.create_snapshot()
	var leap_range_px = Measurement.inches_to_px(12.0)  # LEAP TO DEFEND: charged enemy within 12"
	var fray_range_px = Measurement.inches_to_px(6.0)   # INTO THE FRAY:  any enemy within 6"
	for unit_id in snapshot.get("units", {}):
		var unit = snapshot.units[unit_id]
		if int(unit.get("owner", 0)) != player:
			continue
		if unit.get("flags", {}).get("battle_shocked", false):
			continue
		if unit.get("embarked_in", null) != null:
			continue
		var has_alive := false
		for m in unit.get("models", []):
			if m.get("alive", true) and m.get("position") != null:
				has_alive = true
				break
		if not has_alive:
			continue
		var keywords: Array = unit.get("meta", {}).get("keywords", [])
		if "VEHICLE" in keywords and not ("WALKER" in keywords or "CHARACTER" in keywords):
			continue
		if RulesEngine.is_unit_engaged(unit_id, snapshot):
			continue
		# A legal target for at least one HI mode (edge-to-edge):
		#   any enemy within 6" (Into the Fray), OR
		#   an enemy that charged this turn within 12" (Leap to Defend).
		var has_target := false
		for other_id in snapshot.get("units", {}):
			var other = snapshot.units[other_id]
			if int(other.get("owner", 0)) == player:
				continue
			var other_charged: bool = other.get("flags", {}).get("charged_this_turn", false)
			for m in unit.get("models", []):
				if not m.get("alive", true) or m.get("position") == null:
					continue
				for em in other.get("models", []):
					if not em.get("alive", true) or em.get("position") == null:
						continue
					var d = Measurement.model_to_model_distance_px(m, em)
					if d <= fray_range_px or (other_charged and d <= leap_range_px):
						has_target = true
						break
				if has_target:
					break
			if has_target:
				break
		if has_target:
			eligible.append({
				"unit_id": unit_id,
				"unit_name": unit.get("meta", {}).get("name", unit_id)
			})
	return eligible

func get_heroic_intervention_eligible_units(player: int, charging_enemy_unit_id: String, game_state_snapshot: Dictionary) -> Array:
	"""
	Get units eligible for Heroic Intervention for a given player after an enemy charge.
	Requirements:
	  - Owned by player
	  - Within 6" of the charging enemy unit
	  - Not already in engagement range of any enemy unit
	  - Not battle-shocked
	  - Has alive models
	  - Not a VEHICLE (unless it has WALKER keyword)
	Returns array of { unit_id: String, unit_name: String }
	"""
	var eligible = []

	# Check if the stratagem can be used at all (CP, restrictions)
	var validation = can_use_stratagem(player, "heroic_intervention")
	if not validation.can_use:
		return eligible

	var all_units = game_state_snapshot.get("units", {})
	var charging_unit = all_units.get(charging_enemy_unit_id, {})
	if charging_unit.is_empty():
		return eligible

	for unit_id in all_units:
		var unit = all_units[unit_id]
		if int(unit.get("owner", 0)) != player:
			continue

		# Must not be battle-shocked
		var flags = unit.get("flags", {})
		if flags.get("battle_shocked", false):
			continue

		# Must have alive models
		var has_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue

		# Check VEHICLE restriction: cannot select VEHICLE unless it has WALKER keyword
		var keywords = unit.get("meta", {}).get("keywords", [])
		var is_vehicle = false
		var is_walker = false
		for kw in keywords:
			var kw_upper = kw.to_upper()
			if kw_upper == "VEHICLE":
				is_vehicle = true
			if kw_upper == "WALKER":
				is_walker = true
		if is_vehicle and not is_walker:
			continue

		# Must NOT already be in engagement range of any enemy unit
		var in_engagement = false
		var unit_owner = int(unit.get("owner", 0))
		for other_unit_id in all_units:
			var other_unit = all_units[other_unit_id]
			if int(other_unit.get("owner", 0)) == unit_owner:
				continue
			if _units_in_engagement_range(unit, other_unit):
				in_engagement = true
				break
		if in_engagement:
			continue

		# Must be within 6" of the charging enemy unit
		var within_6 = _unit_within_distance_of_unit(unit, charging_unit, 6.0)
		if not within_6:
			continue

		eligible.append({
			"unit_id": unit_id,
			"unit_name": unit.get("meta", {}).get("name", unit_id)
		})

	return eligible

func _unit_within_distance_of_unit(unit1: Dictionary, unit2: Dictionary, distance_inches: float) -> bool:
	"""Check if any model from unit1 is within the given distance (in inches) of any model from unit2."""
	var models1 = unit1.get("models", [])
	var models2 = unit2.get("models", [])

	for model1 in models1:
		if not model1.get("alive", true):
			continue
		var pos1_data = model1.get("position", {})
		if pos1_data == null:
			continue

		for model2 in models2:
			if not model2.get("alive", true):
				continue
			var pos2_data = model2.get("position", {})
			if pos2_data == null:
				continue

			var dist = Measurement.model_to_model_distance_inches(model1, model2)
			if dist <= distance_inches:
				return true

	return false

func get_reactive_stratagems_for_shooting(defending_player: int, target_unit_ids: Array) -> Array:
	"""
	Get reactive stratagems available to the defending player during opponent's shooting.
	Checks both Core stratagems (Go to Ground, Smokescreen) and faction stratagems
	that trigger on after_target_selected during opponent's shooting phase.
	Returns array of { stratagem: Dictionary, eligible_units: Array[String] }
	"""
	var results = []

	# Check Go to Ground (INFANTRY targets)
	var gtg_eligible_units = []
	for unit_id in target_unit_ids:
		var unit = GameState.get_unit(unit_id)
		if unit.is_empty():
			continue
		if unit.get("owner", 0) != defending_player:
			continue
		var keywords = unit.get("meta", {}).get("keywords", [])
		var has_infantry = false
		for kw in keywords:
			if kw.to_upper() == "INFANTRY":
				has_infantry = true
				break
		if has_infantry:
			gtg_eligible_units.append(unit_id)

	if not gtg_eligible_units.is_empty():
		var validation = can_use_stratagem(defending_player, "go_to_ground")
		if validation.can_use:
			results.append({
				"stratagem": stratagems["go_to_ground"],
				"eligible_units": gtg_eligible_units
			})

	# Check Smokescreen (SMOKE keyword targets)
	var smoke_eligible_units = []
	for unit_id in target_unit_ids:
		var unit = GameState.get_unit(unit_id)
		if unit.is_empty():
			continue
		if unit.get("owner", 0) != defending_player:
			continue
		var keywords = unit.get("meta", {}).get("keywords", [])
		var has_smoke = false
		for kw in keywords:
			if kw.to_upper() == "SMOKE":
				has_smoke = true
				break
		if has_smoke:
			smoke_eligible_units.append(unit_id)

	if not smoke_eligible_units.is_empty():
		var validation = can_use_stratagem(defending_player, "smokescreen")
		if validation.can_use:
			results.append({
				# A4: offer the definition the use will actually resolve to
				# (smokescreen_11e at edition >= 11, the 10e entry otherwise)
				"stratagem": stratagems[_resolve_core_id("smokescreen")],
				"eligible_units": smoke_eligible_units
			})

	# Check faction stratagems that trigger on after_target_selected in shooting phase
	results.append_array(_get_faction_reactive_stratagems(defending_player, target_unit_ids, "after_target_selected", "shooting"))

	return results

func _get_faction_reactive_stratagems(defending_player: int, target_unit_ids: Array, trigger: String, phase: String) -> Array:
	"""
	Get faction stratagems that trigger reactively when target units are attacked.
	Checks each faction stratagem's target conditions against the target units.
	Returns array of { stratagem: Dictionary, eligible_units: Array[String] }
	"""
	var results: Array = []

	for strat_id in _player_faction_stratagems.get(str(defending_player), []):
		if not stratagems.has(strat_id):
			continue
		var strat = stratagems[strat_id]

		# Must be implemented
		if not strat.get("implemented", false):
			continue

		# Must match trigger
		if strat.timing.get("trigger", "") != trigger:
			continue

		# Must be usable on opponent's turn
		if strat.timing.get("turn", "") != "opponent" and strat.timing.get("turn", "") != "either":
			continue

		# Must match phase (or be "any" or compound)
		var strat_phase = strat.timing.get("phase", "")
		if strat_phase != "any" and strat_phase != phase:
			if "_or_" in strat_phase:
				if phase not in strat_phase.split("_or_"):
					continue
			else:
				continue

		# Can we use this stratagem at all? (CP, restrictions)
		var validation = can_use_stratagem(defending_player, strat_id)
		if not validation.can_use:
			continue

		# Check which target units match this stratagem's target conditions
		var eligible_units: Array = []
		var target_conditions = strat.get("target", {})
		var context = {"is_target_of_attack": true}

		for unit_id in target_unit_ids:
			var unit = GameState.get_unit(unit_id)
			if unit.is_empty():
				continue
			if unit.get("owner", 0) != defending_player:
				continue

			# P3-93: Battle-shocked units cannot be affected by stratagems
			if unit.get("flags", {}).get("battle_shocked", false):
				continue

			if FactionStratagemLoaderData.unit_matches_target(unit, target_conditions, context):
				eligible_units.append(unit_id)

		if not eligible_units.is_empty():
			results.append({
				"stratagem": strat,
				"eligible_units": eligible_units
			})

	return results

func get_reactive_stratagems_for_fight(defending_player: int, target_unit_ids: Array) -> Array:
	"""
	Get reactive stratagems available to the defending player during fight phase.
	Checks both Core stratagems and faction stratagems that trigger on
	after_target_selected during fight phase.
	Returns array of { stratagem: Dictionary, eligible_units: Array[String] }
	"""
	var results = []

	# Check faction stratagems that trigger on after_target_selected in fight phase
	results.append_array(_get_faction_reactive_stratagems(defending_player, target_unit_ids, "after_target_selected", "fight"))

	# Also check for shooting_or_fight phase stratagems
	results.append_array(_get_faction_reactive_stratagems(defending_player, target_unit_ids, "after_target_selected", "shooting_or_fight"))

	return results

func get_proactive_stratagems_for_phase(player: int, phase: String, available_units: Array) -> Array:
	"""
	Get proactive faction stratagems a player can use during their active phase.
	Checks for stratagems like STORM OF FIRE (your shooting phase, shooter_selected)
	or UNBRIDLED CARNAGE (fight phase, fighter_selected).
	Returns array of { stratagem: Dictionary, eligible_units: Array[String] }
	"""
	var results: Array = []
	var trigger = ""

	match phase:
		"shooting":
			trigger = "shooter_selected"
		"fight":
			trigger = "fighter_selected"
		_:
			return results

	for strat_id in _player_faction_stratagems.get(str(player), []):
		if not stratagems.has(strat_id):
			continue
		var strat = stratagems[strat_id]

		if not strat.get("implemented", false):
			continue

		if strat.timing.get("trigger", "") != trigger:
			continue

		# Must be usable on your turn
		if strat.timing.get("turn", "") != "your" and strat.timing.get("turn", "") != "either":
			continue

		# Must match phase
		var strat_phase = strat.timing.get("phase", "")
		if strat_phase != "any" and strat_phase != phase:
			if "_or_" in strat_phase:
				if phase not in strat_phase.split("_or_"):
					continue
			else:
				continue

		var validation = can_use_stratagem(player, strat_id)
		if not validation.can_use:
			continue

		# Check which units match target conditions
		var eligible_units: Array = []
		var target_conditions = strat.get("target", {})

		for unit_id in available_units:
			var unit = GameState.get_unit(unit_id)
			if unit.is_empty():
				continue
			if unit.get("owner", 0) != player:
				continue

			# P3-93: Battle-shocked units cannot be affected by stratagems
			if unit.get("flags", {}).get("battle_shocked", false):
				continue

			if FactionStratagemLoaderData.unit_matches_target(unit, target_conditions):
				eligible_units.append(unit_id)

		if not eligible_units.is_empty():
			results.append({
				"stratagem": strat,
				"eligible_units": eligible_units
			})

	return results

# ============================================================================
# FIRE OVERWATCH — Execution
# ============================================================================

# Alias for backward-compatibility with tests that use the shorter name
func get_overwatch_eligible_units(player: int, enemy_unit_id: String, game_state_snapshot: Dictionary) -> Array:
	return get_fire_overwatch_eligible_units(player, enemy_unit_id, game_state_snapshot)

func execute_fire_overwatch(player: int, shooter_unit_id: String, target_unit_id: String, game_state_snapshot: Dictionary) -> Dictionary:
	"""
	Execute the Fire Overwatch stratagem: shooting at the target with hit-on-6-only.
	Handles CP deduction, usage tracking, overwatch shooting resolution.
	Returns { success: bool, diffs: Array, shooting_result: Dictionary, message: String }
	"""
	var validation = can_use_stratagem(player, "fire_overwatch", shooter_unit_id)
	if not validation.can_use:
		return {"success": false, "error": validation.reason, "diffs": [], "shooting_result": {}}

	# Use the standard use_stratagem flow for CP deduction and usage tracking
	var result = use_stratagem(player, "fire_overwatch", shooter_unit_id)
	if not result.success:
		return {"success": false, "error": result.get("error", "Failed"), "diffs": [], "shooting_result": {}}

	var shooter_unit = GameState.get_unit(shooter_unit_id)
	var shooter_name = shooter_unit.get("meta", {}).get("name", shooter_unit_id)
	var target_unit = GameState.get_unit(target_unit_id)
	var target_name = target_unit.get("meta", {}).get("name", target_unit_id)

	print("StratagemManager: FIRE OVERWATCH — %s (player %d) fires at %s" % [shooter_name, player, target_name])

	# Build an action for RulesEngine.resolve_overwatch_shooting()
	var board = GameState.create_snapshot()
	var rng = RulesEngine.make_rng()
	var shooting_result = RulesEngine.resolve_overwatch_shooting(shooter_unit_id, target_unit_id, board, rng)

	# Apply the diffs from shooting
	var shooting_diffs = shooting_result.get("diffs", [])
	if not shooting_diffs.is_empty():
		_safe_apply_state_changes(shooting_diffs)

	# Log the overwatch to phase log
	GameState.add_action_to_phase_log({
		"type": "FIRE_OVERWATCH",
		"player": player,
		"shooter_unit_id": shooter_unit_id,
		"shooter_unit_name": shooter_name,
		"target_unit_id": target_unit_id,
		"target_unit_name": target_name,
		"hits": shooting_result.get("total_hits", 0),
		"wounds": shooting_result.get("total_wounds", 0),
		"damage": shooting_result.get("total_damage", 0),
		"casualties": shooting_result.get("total_casualties", 0),
		"turn": GameState.get_battle_round()
	})

	return {
		"success": true,
		"diffs": shooting_diffs,
		"shooting_result": shooting_result,
		"message": "FIRE OVERWATCH: %s shot at %s — %d hit(s), %d wound(s), %d damage, %d casualt%s" % [
			shooter_name, target_name,
			shooting_result.get("total_hits", 0),
			shooting_result.get("total_wounds", 0),
			shooting_result.get("total_damage", 0),
			shooting_result.get("total_casualties", 0),
			"y" if shooting_result.get("total_casualties", 0) == 1 else "ies"
		]
	}

func _is_within_range(unit1: Dictionary, unit2: Dictionary, range_inches: float) -> bool:
	"""Check if any alive model from unit1 is within range_inches of any alive model from unit2."""
	var models1 = unit1.get("models", [])
	var models2 = unit2.get("models", [])

	for model1 in models1:
		if not model1.get("alive", true):
			continue

		for model2 in models2:
			if not model2.get("alive", true):
				continue

			var distance = Measurement.model_to_model_distance_inches(model1, model2)
			if distance <= range_inches:
				return true

	return false

func _is_unit_in_engagement_range(unit: Dictionary, all_units: Dictionary, owner: int) -> bool:
	"""Check if any model in unit is within engagement range (1\") of any enemy model."""
	var models = unit.get("models", [])

	for model in models:
		if not model.get("alive", true):
			continue

		for other_unit_id in all_units:
			var other_unit = all_units[other_unit_id]
			if int(other_unit.get("owner", 0)) == owner:
				continue  # Skip friendly units

			for other_model in other_unit.get("models", []):
				if not other_model.get("alive", true):
					continue

				if Measurement.is_in_engagement_range_shape_aware(model, other_model):
					return true

	return false

# ============================================================================
# HELPERS
# ============================================================================

func _get_player_cp(player: int) -> int:
	return GameState.state.get("players", {}).get(str(player), {}).get("cp", 0)

func _phase_to_string(phase: int) -> String:
	match phase:
		GameStateData.Phase.DEPLOYMENT: return "deployment"
		GameStateData.Phase.ROLL_OFF: return "roll_off"
		GameStateData.Phase.FIRST_TURN_ROLLOFF: return "first_turn_rolloff"
		GameStateData.Phase.COMMAND: return "command"
		GameStateData.Phase.MOVEMENT: return "movement"
		GameStateData.Phase.SHOOTING: return "shooting"
		GameStateData.Phase.CHARGE: return "charge"
		GameStateData.Phase.FIGHT: return "fight"
		GameStateData.Phase.SCORING: return "scoring"
		GameStateData.Phase.MORALE: return "morale"
		_: return "unknown"

func reset_for_new_game() -> void:
	"""Reset all tracking for a new game."""
	_usage_history = {"1": [], "2": []}
	active_effects.clear()
	_out_of_phase_action_active = false
	_out_of_phase_player = 0
	_out_of_phase_unit_id = ""
	# Clear faction stratagems (they'll be reloaded when armies are set up)
	_clear_player_faction_stratagems(1)
	_clear_player_faction_stratagems(2)
	print("StratagemManager: Reset for new game")

# ============================================================================
# SAVE/LOAD SUPPORT (Issue #338)
# Persist per-game member-field state so once-per-battle/turn/phase usage
# locks survive save/load round-trips. Without this, save-scumming can defeat
# stratagem usage restrictions.
# ============================================================================

func get_state_for_save() -> Dictionary:
	"""Return state data for save games."""
	return {
		"usage_history": _usage_history.duplicate(true),
		"active_effects": active_effects.duplicate(true),
		"player_faction_stratagems": _player_faction_stratagems.duplicate(true)
	}

func load_state(data: Dictionary) -> void:
	"""Restore state from save data. Defaults match initial values for old saves."""
	_usage_history = data.get("usage_history", {"1": [], "2": []})
	active_effects = data.get("active_effects", [])
	_player_faction_stratagems = data.get("player_faction_stratagems", {"1": [], "2": []})
	print("StratagemManager: State loaded — usage_history sizes: P1=%d P2=%d, active_effects=%d, faction_stratagems: P1=%d P2=%d" % [
		_usage_history.get("1", []).size(),
		_usage_history.get("2", []).size(),
		active_effects.size(),
		_player_faction_stratagems.get("1", []).size(),
		_player_faction_stratagems.get("2", []).size()
	])


## ISS-056: the 11e core stratagem set (15.02-15.12). Definitions carry
## "edition": 11 so can_use_stratagem hides them at 10e; the reworked 10e
## entries above are retired at 11e via "edition_max": 10 (applied in
## _retire_10e_core_at_11e). Dice effects resolve through
## RulesEngine.resolve_explosives_11e / resolve_crushing_impact_11e;
## Fire Overwatch grants SNAP shooting (15.09, ShootingTypes), Rapid
## Ingress an ingress move (20.04, MoveTypes), Heroic Intervention a
## charge with modes (11.02 + 15.11).
func _load_core_stratagems_11e() -> void:
	stratagems["command_re_roll_11e"] = {
		"id": "command_re_roll_11e", "name": "COMMAND RE-ROLL", "type": "Core Stratagem",
		"cp_cost": 1, "edition": 11,
		"timing": {"turn": "either", "phase": "any", "trigger": "after_roll"},
		"target": {"type": "unit", "owner": "friendly", "conditions": []},
		"effects": [{"type": "reroll_single_die", "full_reroll_for": ["charge"]}],
		"restrictions": {"once_per": "phase"},
		"description": "Re-roll that roll. If rolling more than one dice together, select ONE die to re-roll — except charge rolls, which are re-rolled in full (15.02).",
	}
	stratagems["epic_challenge_11e"] = {
		"id": "epic_challenge_11e", "name": "EPIC CHALLENGE", "type": "Core Stratagem",
		"cp_cost": 1, "edition": 11,
		"timing": {"turn": "either", "phase": "fight", "trigger": "after_selected_to_fight"},
		"target": {"type": "unit", "owner": "friendly", "conditions": ["is_character"]},
		"effects": [{"type": "grant_weapon_ability", "ability": "precision", "scope": "melee", "duration": "end_of_phase", "model_choice": "one_character"}],
		"restrictions": {},
		"description": "One CHARACTER model's melee weapons gain [PRECISION] until the end of the phase (15.03).",
	}
	stratagems["insane_bravery_11e"] = {
		"id": "insane_bravery_11e", "name": "INSANE BRAVERY", "type": "Core Stratagem",
		"cp_cost": 1, "edition": 11,
		"timing": {"turn": "your", "phase": "command", "trigger": "before_battle_shock_roll"},
		"target": {"type": "unit", "owner": "friendly", "conditions": ["needs_battle_shock_test"]},
		"effects": [{"type": "auto_pass_battle_shock"}],
		"restrictions": {"once_per": "battle"},
		"description": "That battle-shock roll is automatically successful (15.04).",
	}
	stratagems["explosives"] = {
		"id": "explosives", "name": "EXPLOSIVES", "type": "Core Stratagem",
		"cp_cost": 1, "edition": 11,
		"timing": {"turn": "your", "phase": "shooting", "trigger": "instead_of_shooting"},
		"target": {"type": "unit", "owner": "friendly",
			"conditions": ["unengaged", "eligible_to_shoot", "did_not_advance", "has_keyword:EXPLOSIVES|GRENADES"]},
		"effects": [{"type": "explosives_11e", "dice": 6, "threshold": 4, "range": 8}],
		"restrictions": {},
		"description": "Select one EXPLOSIVES/GRENADES model; one unengaged enemy unit within 8\" and visible: roll 6D6 — each 4+ inflicts 1 mortal wound (15.05).",
	}
	stratagems["crushing_impact"] = {
		"id": "crushing_impact", "name": "CRUSHING IMPACT", "type": "Core Stratagem",
		"cp_cost": 1, "edition": 11,
		"timing": {"turn": "your", "phase": "charge", "trigger": "after_charge_move"},
		"target": {"type": "unit", "owner": "friendly", "conditions": ["has_keyword:MONSTER|VEHICLE", "charged_this_turn"]},
		"effects": [{"type": "crushing_impact_11e", "max_mortals": 6}],
		"restrictions": {},
		"description": "Roll T dice for one engaged model: each 1 = 1 mortal wound to your unit, each 5+ = 1 mortal wound to the enemy (max 6) (15.06).",
	}
	stratagems["rapid_ingress_11e"] = {
		"id": "rapid_ingress_11e", "name": "RAPID INGRESS", "type": "Core Stratagem",
		"cp_cost": 1, "edition": 11,
		"timing": {"turn": "opponent", "phase": "shooting", "trigger": "start_of_phase"},
		"target": {"type": "unit", "owner": "friendly", "conditions": ["in_strategic_reserves", "not_keyword:AIRCRAFT"]},
		"effects": [{"type": "move_type", "move": "ingress"}],
		"restrictions": {"not_battle_round": 1},
		"description": "Your reserves unit makes an ingress move (20.04); not during the first battle round (15.07).",
	}
	stratagems["fire_overwatch_11e"] = {
		"id": "fire_overwatch_11e", "name": "FIRE OVERWATCH", "type": "Core Stratagem",
		"cp_cost": 1, "edition": 11,
		"timing": {"turn": "opponent", "phase": "movement", "trigger": "end_of_phase"},
		"target": {"type": "unit", "owner": "friendly", "conditions": ["unengaged", "not_keyword:TITANIC"]},
		"effects": [{"type": "shooting_type", "shooting": "snap"}],
		"restrictions": {"once_per": "turn"},
		"description": "Your unit shoots using SNAP shooting (15.08/15.09): one visible target within 24\", unmodified 6s hit, no re-rolls.",
	}
	stratagems["smokescreen_11e"] = {
		"id": "smokescreen_11e", "name": "SMOKESCREEN", "type": "Core Stratagem",
		"cp_cost": 1, "edition": 11,
		"timing": {"turn": "opponent", "phase": "shooting", "trigger": "start_of_phase"},
		"target": {"type": "unit", "owner": "friendly", "conditions": ["has_keyword:SMOKE"]},
		"effects": [{"type": "benefit_of_cover_aura", "duration": "end_of_phase", "covers_screened": true}],
		"restrictions": {},
		"description": "Until end of phase, attacks against your SMOKE unit — or units screened by it — get the benefit of cover (15.10/13.08).",
	}
	stratagems["heroic_intervention_11e"] = {
		"id": "heroic_intervention_11e", "name": "HEROIC INTERVENTION", "type": "Core Stratagem",
		"cp_cost": 1, "edition": 11,
		"timing": {"turn": "opponent", "phase": "charge", "trigger": "end_of_phase"},
		"target": {"type": "unit", "owner": "friendly",
			"conditions": ["unengaged", "enemy_within:12", "vehicle_only_if_character_or_walker"]},
		"effects": [{"type": "charge_with_modes", "modes": ["leap_to_defend", "into_the_fray"]}],
		"restrictions": {},
		"description": "Resolve a charge (11.02) choosing a mode: LEAP TO DEFEND (only chargers as targets) or INTO THE FRAY (roll capped at 6; targets within 6\") (15.11).",
	}
	stratagems["counteroffensive_11e"] = {
		"id": "counteroffensive_11e", "name": "COUNTEROFFENSIVE", "type": "Core Stratagem",
		"cp_cost": 2, "edition": 11,
		"timing": {"turn": "opponent", "phase": "fight", "trigger": "after_enemy_fight_resolved"},
		"target": {"type": "unit", "owner": "friendly", "conditions": ["eligible_to_fight"]},
		"effects": [{"type": "grant_fights_first", "duration": "end_of_phase", "must_be_next_selection": true}],
		"restrictions": {},
		"description": "Until end of phase your unit has Fights First and must be your next selection to fight (15.12).",
	}
	# The reworked 10e core entries are retired at edition >= 11.
	for retired_id in ["insane_bravery", "command_re_roll", "go_to_ground", "smokescreen",
			"epic_challenge", "grenade", "tank_shock", "fire_overwatch",
			"heroic_intervention", "counter_offensive", "new_orders", "rapid_ingress"]:
		if stratagems.has(retired_id):
			stratagems[retired_id]["edition_max"] = 10

