extends Node

# FactionAbilityManager - Handles faction-wide abilities triggered during the Command Phase
#
# Per 10th Edition rules, many factions have a faction ability that triggers
# at the start of the Command Phase. This manager:
# 1. Detects which faction abilities are available for each player
# 2. Tracks active faction ability effects (e.g., Oath of Moment target)
# 3. Provides query functions for RulesEngine to check during combat resolution
#
# Currently supported faction abilities:
# - Oath of Moment (Space Marines / ADEPTUS ASTARTES):
#   At the start of your Command phase, select one enemy unit as your Oath of Moment target.
#   Each time a model with this ability makes an attack targeting the Oath of Moment target,
#   you can re-roll the Hit roll and add 1 to the Wound roll.
# - Waaagh! (Orks):
#   Once per battle, at the start of your Command phase, you can call a Waaagh!.
#   Until the start of your next Command phase:
#   (1) Units with this ability are eligible to charge in a turn they Advanced.
#   (2) Add 1 to Strength and Attacks of melee weapons.
#   (3) Models have a 5+ invulnerable save.
#
# Detachment abilities (P2-27):
# - Combat Doctrines (Space Marines / Gladius Task Force):
#   At the start of your Command phase, select one Combat Doctrine. Each once per battle.
#   Devastator: eligible to shoot after Advancing. Tactical: shoot+charge after Falling Back.
#   Assault: charge after Advancing.
# - Get Stuck In (Orks / War Horde):
#   Passive: Melee weapons equipped by ORKS models have Sustained Hits 1.
# - Martial Mastery (Adeptus Custodes / Shield Host):
#   At the start of the battle round, select one option:
#   (1) Crit on 5+ for melee attacks by models with Martial Ka'tah.
#   (2) Improve AP of melee weapons by 1 for models with Martial Ka'tah.

# ============================================================================
# CONSTANTS
# ============================================================================

# Detachment ability definitions (P2-27)
# Maps detachment name to its rule configuration
const DETACHMENT_ABILITIES = {
	"Gladius Task Force": {
		"faction_keyword": "ADEPTUS ASTARTES",
		"ability_name": "Combat Doctrines",
		"trigger": "command_phase_start",
		"once_per_battle_each": true,
		"options": {
			"devastator": {
				"display": "Devastator Doctrine",
				"description": "This unit is eligible to shoot in a turn in which it Advanced.",
				"effect": "advance_and_shoot"
			},
			"tactical": {
				"display": "Tactical Doctrine",
				"description": "This unit is eligible to shoot and declare a charge in a turn in which it Fell Back.",
				"effect": "fall_back_and_shoot_and_charge"
			},
			"assault": {
				"display": "Assault Doctrine",
				"description": "This unit is eligible to declare a charge in a turn in which it Advanced.",
				"effect": "advance_and_charge"
			}
		}
	},
	"War Horde": {
		"faction_keyword": "ORKS",
		"ability_name": "Get Stuck In",
		"trigger": "passive",
		"effect": "sustained_hits_1_melee",
		"description": "Melee weapons equipped by ORKS models from your army have the [SUSTAINED HITS 1] ability."
	},
	"Freebooter Krew": {
		"faction_keyword": "ORKS",
		"ability_name": "Here Be Loot",
		"trigger": "battle_round_start",
		"effect": "sustained_hits_near_loot",
		"description": "At the start of each battle round, select one objective marker as the Loot Objective. While an ORKS INFANTRY, MOUNTED, or WALKER unit from your army is within range of the Loot Objective, each time a model in that unit makes an attack, that attack has the [SUSTAINED HITS 1] ability. In addition, while an enemy unit is within range of the Loot Objective, each time a model from your army makes an attack against that unit, that attack has the [SUSTAINED HITS 1] ability."
	},
	"Shield Host": {
		"faction_keyword": "ADEPTUS CUSTODES",
		"ability_name": "Martial Mastery",
		"trigger": "battle_round_start",
		"requires_katah": true,
		"options": {
			"crit_on_5": {
				"display": "Martial Mastery — Critical Hit on 5+",
				"description": "Each time an ADEPTUS CUSTODES model with Martial Ka'tah makes a melee attack, a successful unmodified hit roll of 5+ scores a Critical Hit.",
				"effect": "crit_hit_on_5_melee"
			},
			"improve_ap": {
				"display": "Martial Mastery — Improve AP by 1",
				"description": "Improve the Armour Penetration characteristic of melee weapons equipped by ADEPTUS CUSTODES models with Martial Ka'tah by 1.",
				"effect": "improve_ap_1_melee"
			}
		}
	}
}

# ============================================================================
# FREEBOOTER KREW ENHANCEMENTS (OA-2)
# ============================================================================
# Enhancement abilities available to the Freebooter Krew detachment.
# Each enhancement can be equipped on a specific CHARACTER model.
# The enhancement name is stored in unit.meta.enhancements[].

const FREEBOOTER_ENHANCEMENTS = {
	"Da Kaptin": {
		"points": 10,
		"restriction": "WARBOSS",
		"trigger": "start_of_any_phase",
		"once_per_battle_round": true,
		"description": "At the start of any phase, select one Battle-shocked friendly ORKS unit within 12\" of the bearer. That unit suffers D3 mortal wounds but is no longer Battle-shocked."
	},
	"Git-spotter Squig": {
		"points": 20,
		"restriction": "ORKS",
		"trigger": "passive",
		"description": "Ranged weapons equipped by models in the bearer's unit have the [IGNORES COVER] ability."
	},
	"Bionik Workshop": {
		"points": 15,
		"restriction": ["BIG MEK", "PAINBOY"],
		"trigger": "start_of_battle",
		"description": "At the start of the battle, roll one D3: 1 = +1 Move, 2 = +1 Strength (melee), 3 = +1 to melee Hit rolls. Applies to the bearer's unit for the entire battle."
	},
	"Razgit's Magik Map": {
		"points": 25,
		"restriction": "ORKS",
		"trigger": "after_deployment",
		"description": "After both players have deployed their armies, select up to 3 friendly Orks INFANTRY units and redeploy them. Any of those units can be placed into Strategic Reserves."
	}
}

# Known faction ability definitions
# Each entry maps a faction ability name to its configuration
const FACTION_ABILITIES = {
	"Oath of Moment": {
		"faction_keyword": "ADEPTUS ASTARTES",
		"trigger": "command_phase_start",
		"requires_target": true,
		"target_type": "enemy_unit",
		"effect": "reroll_hits_plus_one_wound",
		"description": "Select one enemy unit as your Oath of Moment target. Each time a model with this ability makes an attack targeting the Oath of Moment target, you can re-roll the Hit roll and add 1 to the Wound roll."
	},
	"Martial Ka'tah": {
		"faction_keyword": "ADEPTUS CUSTODES",
		"trigger": "fight_phase_unit_selected",
		"requires_target": false,
		"effect": "stance_selection",
		"stances": {
			"dacatarai": {"keyword": "sustained_hits", "value": 1, "display": "Dacatarai (Sustained Hits 1)"},
			"rendax": {"keyword": "lethal_hits", "value": true, "display": "Rendax (Lethal Hits)"}
		},
		"description": "Each time a unit with this ability is selected to fight, select one Ka'tah Stance for it to assume: Dacatarai — Each time a model in this unit makes a melee attack, a successful unmodified Hit roll of 6 scores one additional hit. Rendax — Each time a model in this unit makes a melee attack, a successful unmodified Hit roll of 6 is always a successful Wound roll."
	},
	"Waaagh!": {
		"faction_keyword": "ORKS",
		"trigger": "command_phase_start",
		"requires_target": false,
		"once_per_battle": true,
		"effect": "waaagh_activation",
		"description": "Once per battle, at the start of your Command phase, you can call a Waaagh!. If you do, until the start of your next Command phase: units with this ability are eligible to charge in a turn in which they Advanced; add 1 to the Strength and Attacks characteristics of melee weapons equipped by models with this ability; models with this ability have a 5+ invulnerable save."
	}
}

# ============================================================================
# STATE
# ============================================================================

# Per-player tracking of active faction abilities
# Format: { "1": { "oath_of_moment_target": "U_BOYZ_A" }, "2": {} }
var _active_effects: Dictionary = {"1": {}, "2": {}}

# Cache of which faction abilities each player has (computed on phase enter)
# Format: { "1": ["Oath of Moment"], "2": [] }
var _player_abilities: Dictionary = {"1": [], "2": []}

# Waaagh! state tracking
# Per-player: whether Waaagh! has been called this battle (once per battle)
var _waaagh_used: Dictionary = {"1": false, "2": false}
# Per-player: whether Waaagh! is currently active (lasts until start of next Command phase)
var _waaagh_active: Dictionary = {"1": false, "2": false}

# Plant the Waaagh! Banner tracking (OA-46) — Nob with Waaagh! Banner
# Per-unit (unit_id key): whether the ability has been used this battle (once per battle)
var _plant_waaagh_banner_used: Dictionary = {}

# ============================================================================
# DETACHMENT ABILITY STATE (P2-27)
# ============================================================================

# Per-player: detected detachment name (e.g., "Gladius Task Force", "War Horde", "Shield Host")
var _player_detachment: Dictionary = {"1": "", "2": ""}

# Combat Doctrines tracking (Space Marines)
# Per-player: which doctrines have been used this battle
var _doctrines_used: Dictionary = {"1": [], "2": []}
# Per-player: currently active doctrine (empty string if none)
var _active_doctrine: Dictionary = {"1": "", "2": ""}

# Martial Mastery tracking (Custodes)
# Per-player: currently active mastery option ("crit_on_5" or "improve_ap", empty if none)
var _active_mastery: Dictionary = {"1": "", "2": ""}
# Per-player: battle round in which mastery was last selected (to detect new round)
var _mastery_selected_round: Dictionary = {"1": 0, "2": 0}

# Loot Objective tracking (Orks — Freebooter Krew) (OA-1)
# Per-player: which objective is the current loot objective (objective_id string)
var _loot_objective: Dictionary = {"1": "", "2": ""}
# Per-player: battle round in which loot objective was last selected
var _loot_objective_round: Dictionary = {"1": 0, "2": 0}

# ============================================================================
# FREEBOOTER KREW ENHANCEMENT STATE (OA-2)
# ============================================================================

# Da Kaptin: per-player battle round in which it was last used (once per battle round)
var _da_kaptin_used_round: Dictionary = {"1": 0, "2": 0}

# Bionik Workshop: per-unit result of the D3 roll at battle start
# Key: unit_id (the bearer's CHARACTER unit), Value: {roll: int, bonus_type: String}
# bonus_type: "move" (+1 Move), "strength" (+1 Strength melee), "hit" (+1 to melee Hit rolls)
var _bionik_workshop_results: Dictionary = {}
# Whether Bionik Workshop has been resolved this battle
var _bionik_workshop_resolved: bool = false

# Razgit's Magik Map: per-player tracking of redeployments used
# Key: player string, Value: number of units redeployed via Razgit's
var _razgit_redeploys_used: Dictionary = {"1": 0, "2": 0}
# Whether Razgit's Magik Map has been resolved this battle
var _razgit_resolved: bool = false

func _ready():
	print("FactionAbilityManager: Ready")

# ============================================================================
# ABILITY DETECTION
# ============================================================================

func detect_faction_abilities(player: int) -> Array:
	"""Scan player's army for faction abilities. Returns array of ability names."""
	var abilities = []
	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue

		# Skip destroyed units
		var has_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue

		var unit_abilities = unit.get("meta", {}).get("abilities", [])
		for ability in unit_abilities:
			var ability_name = ""
			if ability is String:
				ability_name = ability
			elif ability is Dictionary:
				ability_name = ability.get("name", "")

			# Only track known faction abilities (type == "Faction")
			var ability_type = ""
			if ability is Dictionary:
				ability_type = ability.get("type", "")

			if ability_type == "Faction" and ability_name in FACTION_ABILITIES:
				if ability_name not in abilities:
					abilities.append(ability_name)

	_player_abilities[str(player)] = abilities
	print("FactionAbilityManager: Player %d has faction abilities: %s" % [player, str(abilities)])
	return abilities

func get_player_faction_abilities(player: int) -> Array:
	"""Get cached list of faction abilities for a player."""
	return _player_abilities.get(str(player), [])

func player_has_ability(player: int, ability_name: String) -> bool:
	"""Check if a player's army has a specific faction ability."""
	return ability_name in _player_abilities.get(str(player), [])

# ============================================================================
# OATH OF MOMENT — TARGET SELECTION
# ============================================================================

func get_oath_of_moment_target(player: int) -> String:
	"""Get the current Oath of Moment target unit ID for a player. Returns empty string if none."""
	return _active_effects.get(str(player), {}).get("oath_of_moment_target", "")

func set_oath_of_moment_target(player: int, target_unit_id: String) -> Dictionary:
	"""Set the Oath of Moment target for a player. Returns result dict."""
	var player_key = str(player)

	# Validate the target is an enemy unit that's alive and deployed
	var target_unit = GameState.state.get("units", {}).get(target_unit_id, {})
	if target_unit.is_empty():
		return {"success": false, "error": "Target unit not found: %s" % target_unit_id}

	if target_unit.get("owner", 0) == player:
		return {"success": false, "error": "Cannot target own unit with Oath of Moment"}

	# Check target has alive models
	var has_alive = false
	for model in target_unit.get("models", []):
		if model.get("alive", true):
			has_alive = true
			break
	if not has_alive:
		return {"success": false, "error": "Target unit is destroyed"}

	# Clear previous oath target flag
	var old_target = get_oath_of_moment_target(player)
	if old_target != "":
		_clear_oath_flag(old_target)

	# Set new target
	if not _active_effects.has(player_key):
		_active_effects[player_key] = {}
	_active_effects[player_key]["oath_of_moment_target"] = target_unit_id

	# Set flag on the target unit
	if not target_unit.has("flags"):
		target_unit["flags"] = {}
	target_unit["flags"]["oath_of_moment_target"] = true
	target_unit["flags"]["oath_of_moment_owner"] = player

	var target_name = target_unit.get("meta", {}).get("name", target_unit_id)
	print("FactionAbilityManager: Player %d Oath of Moment target set to %s (%s)" % [player, target_name, target_unit_id])

	# Log Oath of Moment to GameEventLog
	var game_event_log = get_node_or_null("/root/GameEventLog")
	if game_event_log:
		game_event_log.add_player_entry(player, "Oath of Moment: %s marked for destruction (re-roll hits, +1 wound)" % target_name)

	return {
		"success": true,
		"target_unit_id": target_unit_id,
		"target_name": target_name,
		"message": "Oath of Moment: %s marked for destruction" % target_name
	}

func clear_oath_of_moment(player: int) -> void:
	"""Clear Oath of Moment target for a player (called at start of new Command Phase)."""
	var old_target = get_oath_of_moment_target(player)
	if old_target != "":
		_clear_oath_flag(old_target)
	_active_effects[str(player)]["oath_of_moment_target"] = ""
	print("FactionAbilityManager: Cleared Oath of Moment for player %d" % player)

func _clear_oath_flag(unit_id: String) -> void:
	"""Remove the oath_of_moment_target flag from a unit."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if not unit.is_empty() and unit.has("flags"):
		unit["flags"]["oath_of_moment_target"] = false
		unit["flags"].erase("oath_of_moment_owner")

# ============================================================================
# WAAAGH! — ACTIVATION AND EFFECT APPLICATION
# ============================================================================

func is_waaagh_available(player: int) -> bool:
	"""Check if Waaagh! can be called (player has it, hasn't used it, not currently active)."""
	if not player_has_ability(player, "Waaagh!"):
		return false
	var player_key = str(player)
	if _waaagh_used.get(player_key, false):
		return false
	if _waaagh_active.get(player_key, false):
		return false
	return true

func is_waaagh_active(player: int) -> bool:
	"""Check if Waaagh! is currently active for a player."""
	return _waaagh_active.get(str(player), false)

func activate_waaagh(player: int) -> Dictionary:
	"""Activate Waaagh! for a player. Called during Command Phase."""
	var player_key = str(player)

	if not player_has_ability(player, "Waaagh!"):
		return {"success": false, "error": "Player %d does not have Waaagh! ability" % player}

	if _waaagh_used.get(player_key, false):
		return {"success": false, "error": "Waaagh! already used this battle"}

	if _waaagh_active.get(player_key, false):
		return {"success": false, "error": "Waaagh! is already active"}

	# Activate Waaagh!
	_waaagh_used[player_key] = true
	_waaagh_active[player_key] = true

	# Apply Waaagh! effects to all Ork units
	_apply_waaagh_effects(player)

	print("FactionAbilityManager: WAAAGH! Player %d calls a Waaagh! — effects active until next Command phase" % player)

	# Log Waaagh! activation to GameEventLog
	var game_event_log = get_node_or_null("/root/GameEventLog")
	if game_event_log:
		game_event_log.add_player_entry(player, "WAAAGH! Called — +1 S/A melee, 5+ invuln, advance and charge!")

	return {
		"success": true,
		"message": "WAAAGH! Called — advance and charge, +1 S/A melee, 5+ invuln active!"
	}

func deactivate_waaagh(player: int) -> void:
	"""Deactivate Waaagh! at the start of the player's next Command Phase."""
	var player_key = str(player)
	if _waaagh_active.get(player_key, false):
		_waaagh_active[player_key] = false
		_clear_waaagh_effects(player)
		print("FactionAbilityManager: Waaagh! deactivated for player %d" % player)

func _apply_waaagh_effects(player: int) -> void:
	"""Apply Waaagh! flags to all Ork units with the Waaagh! ability."""
	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue

		# Skip destroyed units
		var has_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue

		# Check if unit has Waaagh! ability
		if not _unit_has_waaagh_ability(unit):
			continue

		# Apply Waaagh! flags
		if not unit.has("flags"):
			unit["flags"] = {}
		unit["flags"]["waaagh_active"] = true
		# 5+ invulnerable save
		unit["flags"]["effect_invuln"] = 5
		unit["flags"]["effect_invuln_source"] = "Waaagh!"
		# Advance and charge eligibility
		unit["flags"]["effect_advance_and_charge"] = true

		# OA-17: Krumpin' Time — FNP 5+ while Waaagh! active (Meganobz)
		if _unit_has_ability(unit, "Krumpin' Time"):
			# Only set FNP if no better (lower) FNP already present
			var current_fnp = unit["flags"].get("effect_fnp", 0)
			if current_fnp == 0 or 5 <= current_fnp:
				unit["flags"]["effect_fnp"] = 5
				unit["flags"]["effect_fnp_source"] = "Krumpin' Time"
				print("FactionAbilityManager: Krumpin' Time FNP 5+ applied to %s (%s)" % [unit.get("meta", {}).get("name", unit_id), unit_id])

		# OA-41: Big an' Shooty — +1 to Hit for ranged attacks while Waaagh! active (Morkanaut)
		if _unit_has_ability(unit, "Big an' Shooty"):
			unit["flags"]["big_an_shooty_active"] = true
			print("FactionAbilityManager: Big an' Shooty +1 Hit (ranged) applied to %s (%s)" % [unit.get("meta", {}).get("name", unit_id), unit_id])

		# OA-41: Big an' Stompy — +1 to Hit for melee attacks while Waaagh! active (Gorkanaut)
		if _unit_has_ability(unit, "Big an' Stompy"):
			unit["flags"]["big_an_stompy_active"] = true
			print("FactionAbilityManager: Big an' Stompy +1 Hit (melee) applied to %s (%s)" % [unit.get("meta", {}).get("name", unit_id), unit_id])

		# OA-20: Prophet of Da Great Waaagh! — Crit Hit on 5+ while Waaagh! active (Ghazghkull leading)
		# Check if any attached character has this ability and apply crit threshold to the led unit
		var attachment_data = unit.get("attachment_data", {})
		var attached_characters = attachment_data.get("attached_characters", [])
		for char_id in attached_characters:
			var char_unit = units.get(char_id, {})
			if char_unit.is_empty():
				continue
			if _unit_has_ability(char_unit, "Prophet of Da Great Waaagh!"):
				# Only set crit threshold if no better (lower) threshold already present
				var current_crit = unit["flags"].get("effect_crit_hit_on", 0)
				if current_crit == 0 or 5 < current_crit:
					unit["flags"]["effect_crit_hit_on"] = 5
					unit["flags"]["effect_crit_hit_on_source"] = "Prophet of Da Great Waaagh!"
					print("FactionAbilityManager: Prophet of Da Great Waaagh! Crit Hit 5+ applied to %s (%s)" % [unit.get("meta", {}).get("name", unit_id), unit_id])
				break

		# OA-46: Da Boss Iz Watchin' — 4+ invuln and OC 5 while Waaagh! active (Nob with Waaagh! Banner)
		# Upgrade invuln from 5+ to 4+ and set OC 5 for units with this ability
		if _unit_has_ability(unit, "Da Boss Iz Watchin'"):
			_apply_da_boss_iz_watchin(unit, unit_id)

		var unit_name = unit.get("meta", {}).get("name", unit_id)
		print("FactionAbilityManager: Waaagh! effects applied to %s (%s) — 5+ invuln, advance+charge" % [unit_name, unit_id])

func _clear_waaagh_effects(player: int) -> void:
	"""Clear Waaagh! flags from all Ork units."""
	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue

		var flags = unit.get("flags", {})
		if flags.get("waaagh_active", false):
			flags.erase("waaagh_active")
			flags.erase("effect_advance_and_charge")
			# Clear invuln if it was from Waaagh! effects (5+ base or 4+ from Da Boss Iz Watchin')
			# Use source-based check to avoid clobbering other invuln sources
			if flags.get("effect_invuln_source", "") in ["Waaagh!", "Da Boss Iz Watchin'"]:
				flags.erase("effect_invuln")
				flags.erase("effect_invuln_source")
			# OA-46: Clear OC override from Da Boss Iz Watchin' (don't clobber other sources)
			if flags.get("effect_oc_source", "") == "Da Boss Iz Watchin'":
				flags.erase("effect_oc_override")
				flags.erase("effect_oc_source")
				print("FactionAbilityManager: Da Boss Iz Watchin' OC 5 cleared from %s (%s)" % [unit.get("meta", {}).get("name", unit_id), unit_id])
			# OA-17: Only clear FNP if it was from Krumpin' Time (don't clobber other sources)
			if flags.get("effect_fnp_source", "") == "Krumpin' Time":
				flags.erase("effect_fnp")
				flags.erase("effect_fnp_source")
				print("FactionAbilityManager: Krumpin' Time FNP 5+ cleared from %s (%s)" % [unit.get("meta", {}).get("name", unit_id), unit_id])
			# OA-20: Only clear crit hit if it was from Prophet of Da Great Waaagh! (don't clobber other sources)
			if flags.get("effect_crit_hit_on_source", "") == "Prophet of Da Great Waaagh!":
				flags.erase("effect_crit_hit_on")
				flags.erase("effect_crit_hit_on_source")
				print("FactionAbilityManager: Prophet of Da Great Waaagh! Crit Hit 5+ cleared from %s (%s)" % [unit.get("meta", {}).get("name", unit_id), unit_id])
			# OA-41: Clear Big an' Shooty / Big an' Stompy flags
			if flags.get("big_an_shooty_active", false):
				flags.erase("big_an_shooty_active")
				print("FactionAbilityManager: Big an' Shooty +1 Hit (ranged) cleared from %s (%s)" % [unit.get("meta", {}).get("name", unit_id), unit_id])
			if flags.get("big_an_stompy_active", false):
				flags.erase("big_an_stompy_active")
				print("FactionAbilityManager: Big an' Stompy +1 Hit (melee) cleared from %s (%s)" % [unit.get("meta", {}).get("name", unit_id), unit_id])
			var unit_name = unit.get("meta", {}).get("name", unit_id)
			print("FactionAbilityManager: Waaagh! effects cleared from %s (%s)" % [unit_name, unit_id])

func _unit_has_waaagh_ability(unit: Dictionary) -> bool:
	"""Check if a unit has the Waaagh! faction ability."""
	return _unit_has_ability(unit, "Waaagh!")

func _unit_has_ability(unit: Dictionary, target_ability_name: String) -> bool:
	"""Check if a unit has a specific ability by name."""
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")
		if ability_name == target_ability_name:
			return true
	return false

static func is_waaagh_active_for_unit(unit: Dictionary) -> bool:
	"""Static query: Check if a unit currently has Waaagh! active (for RulesEngine)."""
	return unit.get("flags", {}).get("waaagh_active", false)

# ============================================================================
# PLANT THE WAAAGH! BANNER (OA-46) — Nob with Waaagh! Banner
# ============================================================================

func _apply_da_boss_iz_watchin(unit: Dictionary, unit_id: String) -> void:
	"""Apply Da Boss Iz Watchin' effects: 4+ invuln save and OC 5 while Waaagh! active."""
	unit["flags"]["effect_invuln"] = 4
	unit["flags"]["effect_invuln_source"] = "Da Boss Iz Watchin'"
	unit["flags"]["effect_oc_override"] = 5
	unit["flags"]["effect_oc_source"] = "Da Boss Iz Watchin'"
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	print("FactionAbilityManager: Da Boss Iz Watchin' — 4+ invuln + OC 5 applied to %s (%s)" % [unit_name, unit_id])

func can_plant_waaagh_banner(unit_id: String) -> bool:
	"""Check if a unit can use Plant the Waaagh! Banner (has ability, deployed, alive, once per battle)."""
	if _plant_waaagh_banner_used.get(unit_id, false):
		return false
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false
	if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
		return false
	var has_alive = false
	for model in unit.get("models", []):
		if model.get("alive", true):
			has_alive = true
			break
	if not has_alive:
		return false
	return _unit_has_ability(unit, "Plant the Waaagh! Banner")

func get_plant_waaagh_banner_eligible_units(player: int) -> Array:
	"""Get all units that can use Plant the Waaagh! Banner this turn."""
	var eligible = []
	var units = GameState.state.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue
		if can_plant_waaagh_banner(unit_id):
			var unit_name = unit.get("meta", {}).get("name", unit_id)
			eligible.append({"unit_id": unit_id, "unit_name": unit_name})
	print("FactionAbilityManager: Plant the Waaagh! Banner — %d eligible units for player %d" % [eligible.size(), player])
	return eligible

func activate_plant_waaagh_banner(unit_id: String) -> Dictionary:
	"""Activate Plant the Waaagh! Banner for a specific unit (once per battle). Called during Command Phase."""
	if _plant_waaagh_banner_used.get(unit_id, false):
		return {"success": false, "error": "Plant the Waaagh! Banner already used this battle for unit %s" % unit_id}

	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return {"success": false, "error": "Unit not found: %s" % unit_id}

	if not _unit_has_ability(unit, "Plant the Waaagh! Banner"):
		return {"success": false, "error": "Unit %s does not have Plant the Waaagh! Banner ability" % unit_id}

	# Mark as used (once per battle)
	_plant_waaagh_banner_used[unit_id] = true

	# Apply Waaagh! effects to this unit
	if not unit.has("flags"):
		unit["flags"] = {}
	unit["flags"]["waaagh_active"] = true
	unit["flags"]["plant_waaagh_banner_active"] = true
	unit["flags"]["effect_advance_and_charge"] = true

	# Da Boss Iz Watchin': 4+ invuln and OC 5
	_apply_da_boss_iz_watchin(unit, unit_id)

	var unit_name = unit.get("meta", {}).get("name", unit_id)
	print("FactionAbilityManager: Plant the Waaagh! Banner — %s gains Waaagh! effects (4+ invuln, OC 5, advance+charge)" % unit_name)

	# Log to GameEventLog
	var game_event_log = get_node_or_null("/root/GameEventLog")
	if game_event_log:
		game_event_log.add_player_entry(unit.get("owner", 1), "Plant the Waaagh! Banner: %s — Waaagh! active (4+ invuln, OC 5, advance+charge)!" % unit_name)

	return {
		"success": true,
		"unit_name": unit_name,
		"message": "Plant the Waaagh! Banner: %s gains Waaagh! effects (4+ invuln, OC 5, advance+charge)!" % unit_name
	}

func _clear_plant_waaagh_banner_effects(player: int) -> void:
	"""Clear Plant the Waaagh! Banner per-unit effects at the start of the next Command Phase."""
	var units = GameState.state.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue
		var flags = unit.get("flags", {})
		if not flags.get("plant_waaagh_banner_active", false):
			continue

		flags.erase("plant_waaagh_banner_active")
		# Clear waaagh_active and advance_and_charge (army Waaagh! already deactivated by this point)
		flags.erase("waaagh_active")
		flags.erase("effect_advance_and_charge")
		# Clear Da Boss Iz Watchin' invuln (4+)
		if flags.get("effect_invuln_source", "") == "Da Boss Iz Watchin'":
			flags.erase("effect_invuln")
			flags.erase("effect_invuln_source")
		# Clear Da Boss Iz Watchin' OC override
		if flags.get("effect_oc_source", "") == "Da Boss Iz Watchin'":
			flags.erase("effect_oc_override")
			flags.erase("effect_oc_source")

		var unit_name = unit.get("meta", {}).get("name", unit_id)
		print("FactionAbilityManager: Plant the Waaagh! Banner effects cleared from %s (%s)" % [unit_name, unit_id])

# ============================================================================
# COMBAT MODIFIER QUERIES (called by RulesEngine)
# ============================================================================

static func is_oath_of_moment_target(target_unit: Dictionary) -> bool:
	"""Check if a target unit is currently marked by Oath of Moment."""
	return target_unit.get("flags", {}).get("oath_of_moment_target", false)

static func attacker_benefits_from_oath(attacker_unit: Dictionary, target_unit: Dictionary) -> bool:
	"""Check if an attacker benefits from Oath of Moment against this target.
	Requires: target has oath flag, attacker has ADEPTUS ASTARTES keyword,
	and attacker belongs to the player who set the oath."""
	if not is_oath_of_moment_target(target_unit):
		return false

	var oath_owner = target_unit.get("flags", {}).get("oath_of_moment_owner", 0)
	if attacker_unit.get("owner", 0) != oath_owner:
		return false

	# Check if attacker has ADEPTUS ASTARTES keyword
	var keywords = attacker_unit.get("meta", {}).get("keywords", [])
	for keyword in keywords:
		if keyword is String and keyword.to_upper() == "ADEPTUS ASTARTES":
			return true

	return false

# ============================================================================
# GET ELIGIBLE TARGETS (for UI)
# ============================================================================

func get_eligible_oath_targets(player: int) -> Array:
	"""Get list of enemy units that can be targeted by Oath of Moment."""
	var targets = []
	var opponent = 1 if player == 2 else 2
	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != opponent:
			continue

		# Must be deployed
		var status = unit.get("status", "UNDEPLOYED")
		if status == GameStateData.UnitStatus.UNDEPLOYED if typeof(status) == TYPE_INT else status == "UNDEPLOYED":
			continue

		# Must have alive models
		var has_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue

		var unit_name = unit.get("meta", {}).get("name", unit_id)
		targets.append({
			"unit_id": unit_id,
			"unit_name": unit_name
		})

	return targets

# ============================================================================
# DETACHMENT ABILITIES (P2-27)
# ============================================================================

func detect_player_detachment(player: int) -> String:
	"""Detect which detachment a player is using from their faction data."""
	var factions = GameState.state.get("factions", {})
	var faction_data = factions.get(str(player), {})

	var detachment = faction_data.get("detachment", "")
	if detachment != "":
		_player_detachment[str(player)] = detachment
		print("FactionAbilityManager: Player %d detachment: %s" % [player, detachment])
	return detachment

func get_player_detachment(player: int) -> String:
	"""Get cached detachment for a player."""
	return _player_detachment.get(str(player), "")

func has_detachment_ability(player: int) -> bool:
	"""Check if a player's detachment has a known detachment ability."""
	var detachment = get_player_detachment(player)
	return detachment in DETACHMENT_ABILITIES

# ---- COMBAT DOCTRINES (Space Marines — Gladius Task Force) ----

func get_available_doctrines(player: int) -> Array:
	"""Get list of Combat Doctrines that haven't been used yet this battle."""
	var detachment = get_player_detachment(player)
	if detachment != "Gladius Task Force":
		return []

	var used = _doctrines_used.get(str(player), [])
	var available = []
	var options = DETACHMENT_ABILITIES["Gladius Task Force"]["options"]
	for key in options:
		if key not in used:
			available.append({
				"key": key,
				"display": options[key]["display"],
				"description": options[key]["description"]
			})
	return available

func get_active_doctrine(player: int) -> String:
	"""Get the currently active Combat Doctrine for a player."""
	return _active_doctrine.get(str(player), "")

func select_combat_doctrine(player: int, doctrine_key: String) -> Dictionary:
	"""Select a Combat Doctrine for this Command Phase. Once per battle each."""
	var player_key = str(player)
	var detachment = get_player_detachment(player)

	if detachment != "Gladius Task Force":
		return {"success": false, "error": "Player %d is not using Gladius Task Force detachment" % player}

	var options = DETACHMENT_ABILITIES["Gladius Task Force"]["options"]
	if doctrine_key not in options:
		return {"success": false, "error": "Unknown doctrine: %s" % doctrine_key}

	var used = _doctrines_used.get(player_key, [])
	if doctrine_key in used:
		return {"success": false, "error": "%s already used this battle" % options[doctrine_key]["display"]}

	# Clear previous doctrine effects
	_clear_doctrine_effects(player)

	# Mark as used and set active
	used.append(doctrine_key)
	_doctrines_used[player_key] = used
	_active_doctrine[player_key] = doctrine_key

	# Apply doctrine effects to all ADEPTUS ASTARTES units
	_apply_doctrine_effects(player, doctrine_key)

	var display = options[doctrine_key]["display"]
	print("FactionAbilityManager: Player %d selected %s — effects active until next Command Phase" % [player, display])

	return {
		"success": true,
		"doctrine": doctrine_key,
		"doctrine_display": display,
		"message": "Combat Doctrines: %s active" % display
	}

func _apply_doctrine_effects(player: int, doctrine_key: String) -> void:
	"""Apply Combat Doctrine flags to all ADEPTUS ASTARTES units."""
	var units = GameState.state.get("units", {})
	var options = DETACHMENT_ABILITIES["Gladius Task Force"]["options"]
	var doctrine = options.get(doctrine_key, {})

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue

		# Skip destroyed units
		var has_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue

		# Must be ADEPTUS ASTARTES
		if not _unit_has_keyword(unit, "ADEPTUS ASTARTES"):
			continue

		if not unit.has("flags"):
			unit["flags"] = {}

		match doctrine_key:
			"devastator":
				unit["flags"]["effect_advance_and_shoot"] = true
			"tactical":
				unit["flags"]["effect_fall_back_and_shoot"] = true
				unit["flags"]["effect_fall_back_and_charge"] = true
			"assault":
				unit["flags"]["effect_advance_and_charge"] = true

		unit["flags"]["combat_doctrine_active"] = doctrine_key

		var unit_name = unit.get("meta", {}).get("name", unit_id)
		print("FactionAbilityManager: %s applied to %s (%s)" % [doctrine.get("display", doctrine_key), unit_name, unit_id])

func _clear_doctrine_effects(player: int) -> void:
	"""Clear Combat Doctrine flags from all units."""
	var units = GameState.state.get("units", {})
	var player_key = str(player)
	var old_doctrine = _active_doctrine.get(player_key, "")

	if old_doctrine == "":
		return

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue

		var flags = unit.get("flags", {})
		if flags.get("combat_doctrine_active", "") != "":
			match old_doctrine:
				"devastator":
					flags.erase("effect_advance_and_shoot")
				"tactical":
					flags.erase("effect_fall_back_and_shoot")
					flags.erase("effect_fall_back_and_charge")
				"assault":
					flags.erase("effect_advance_and_charge")
			flags.erase("combat_doctrine_active")

	_active_doctrine[player_key] = ""
	print("FactionAbilityManager: Cleared Combat Doctrine effects for player %d (was: %s)" % [player, old_doctrine])

# ---- GET STUCK IN (Orks — War Horde) ----
# This is a passive ability — no activation needed.
# The flag is set on all ORKS units at detection time and checked in RulesEngine.

func is_get_stuck_in_active(player: int) -> bool:
	"""Check if player has War Horde detachment (Get Stuck In is always active)."""
	return get_player_detachment(player) == "War Horde"

static func unit_has_get_stuck_in(unit: Dictionary) -> bool:
	"""Static query: Check if a unit has the Get Stuck In detachment buff active."""
	return unit.get("flags", {}).get("get_stuck_in", false)

func _apply_get_stuck_in(player: int) -> void:
	"""Apply Get Stuck In flag to all ORKS units. Called once at detection."""
	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue

		var has_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue

		if not _unit_has_keyword(unit, "ORKS"):
			continue

		if not unit.has("flags"):
			unit["flags"] = {}
		unit["flags"]["get_stuck_in"] = true

		var unit_name = unit.get("meta", {}).get("name", unit_id)
		print("FactionAbilityManager: Get Stuck In (Sustained Hits 1 melee) applied to %s (%s)" % [unit_name, unit_id])

# ---- MARTIAL MASTERY (Adeptus Custodes — Shield Host) ----

func get_active_mastery(player: int) -> String:
	"""Get the currently active Martial Mastery option for a player."""
	return _active_mastery.get(str(player), "")

func is_martial_mastery_available(player: int) -> bool:
	"""Check if Martial Mastery selection is needed (new battle round, Custodes player)."""
	var detachment = get_player_detachment(player)
	if detachment != "Shield Host":
		return false

	# Only Player 1 triggers the selection at battle round start
	# (Martial Mastery affects both players' Custodes units, but the choice belongs to the army owner)
	var current_round = GameState.get_battle_round()
	var last_selected = _mastery_selected_round.get(str(player), 0)
	return current_round > last_selected

func get_mastery_options() -> Array:
	"""Get the Martial Mastery options for display."""
	var options = DETACHMENT_ABILITIES["Shield Host"]["options"]
	var result = []
	for key in options:
		result.append({
			"key": key,
			"display": options[key]["display"],
			"description": options[key]["description"]
		})
	return result

func select_martial_mastery(player: int, mastery_key: String) -> Dictionary:
	"""Select a Martial Mastery option for this battle round."""
	var player_key = str(player)
	var detachment = get_player_detachment(player)

	if detachment != "Shield Host":
		return {"success": false, "error": "Player %d is not using Shield Host detachment" % player}

	var options = DETACHMENT_ABILITIES["Shield Host"]["options"]
	if mastery_key not in options:
		return {"success": false, "error": "Unknown mastery option: %s" % mastery_key}

	# Clear previous mastery effects
	_clear_mastery_effects(player)

	# Set active mastery
	_active_mastery[player_key] = mastery_key
	_mastery_selected_round[player_key] = GameState.get_battle_round()

	# Apply mastery effects to all ADEPTUS CUSTODES units with Martial Ka'tah
	_apply_mastery_effects(player, mastery_key)

	var display = options[mastery_key]["display"]
	print("FactionAbilityManager: Player %d selected %s — active until next battle round" % [player, display])

	return {
		"success": true,
		"mastery": mastery_key,
		"mastery_display": display,
		"message": "%s active" % display
	}

func _apply_mastery_effects(player: int, mastery_key: String) -> void:
	"""Apply Martial Mastery flags to all Custodes units with Martial Ka'tah."""
	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue

		var has_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue

		# Must have Martial Ka'tah ability
		if not unit_has_katah(unit_id):
			continue

		if not unit.has("flags"):
			unit["flags"] = {}

		match mastery_key:
			"crit_on_5":
				unit["flags"]["martial_mastery_crit_5"] = true
			"improve_ap":
				unit["flags"]["martial_mastery_improve_ap"] = true

		unit["flags"]["martial_mastery_active"] = mastery_key

		var unit_name = unit.get("meta", {}).get("name", unit_id)
		print("FactionAbilityManager: Martial Mastery (%s) applied to %s (%s)" % [mastery_key, unit_name, unit_id])

func _clear_mastery_effects(player: int) -> void:
	"""Clear Martial Mastery flags from all units."""
	var units = GameState.state.get("units", {})
	var player_key = str(player)
	var old_mastery = _active_mastery.get(player_key, "")

	if old_mastery == "":
		return

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue

		var flags = unit.get("flags", {})
		if flags.get("martial_mastery_active", "") != "":
			flags.erase("martial_mastery_crit_5")
			flags.erase("martial_mastery_improve_ap")
			flags.erase("martial_mastery_active")

	_active_mastery[player_key] = ""
	print("FactionAbilityManager: Cleared Martial Mastery effects for player %d (was: %s)" % [player, old_mastery])

# ---- HERE BE LOOT (Orks — Freebooter Krew) (OA-1) ----

func is_loot_objective_available(player: int) -> bool:
	"""Check if loot objective selection is needed (new battle round, Freebooter Krew player)."""
	var detachment = get_player_detachment(player)
	if detachment != "Freebooter Krew":
		return false
	var current_round = GameState.get_battle_round()
	var last_selected = _loot_objective_round.get(str(player), 0)
	return current_round > last_selected

func get_loot_objective(player: int) -> String:
	"""Get the current loot objective ID for a player. Returns empty string if none."""
	return _loot_objective.get(str(player), "")

func get_eligible_loot_objectives() -> Array:
	"""Get all objective markers on the board for loot selection."""
	var objectives = GameState.state.get("board", {}).get("objectives", [])
	var result = []
	for obj in objectives:
		var obj_id = obj.get("id", "")
		if obj_id == "":
			continue
		# Skip burned objectives
		var mission_mgr = get_node_or_null("/root/MissionManager")
		if mission_mgr and mission_mgr._burned_objectives.has(obj_id):
			continue
		result.append({
			"id": obj_id,
			"position": obj.get("position", Vector2.ZERO),
			"zone": obj.get("zone", "")
		})
	return result

func set_loot_objective(player: int, objective_id: String) -> Dictionary:
	"""Set the loot objective for a player. Returns result dict."""
	var player_key = str(player)
	var detachment = get_player_detachment(player)

	if detachment != "Freebooter Krew":
		return {"success": false, "error": "Player %d is not using Freebooter Krew detachment" % player}

	# Validate objective exists
	var objectives = GameState.state.get("board", {}).get("objectives", [])
	var found = false
	for obj in objectives:
		if obj.get("id", "") == objective_id:
			found = true
			break
	if not found:
		return {"success": false, "error": "Objective %s not found" % objective_id}

	# Set the loot objective
	_loot_objective[player_key] = objective_id
	_loot_objective_round[player_key] = GameState.get_battle_round()

	# Write to GameState.state.board for static combat function access
	if not GameState.state.board.has("loot_objective"):
		GameState.state.board["loot_objective"] = {}
	GameState.state.board["loot_objective"][player_key] = objective_id

	print("FactionAbilityManager: Player %d loot objective set to %s (round %d)" % [
		player, objective_id, GameState.get_battle_round()])

	# Update visual indicator on the objective
	_update_loot_objective_visual(objective_id, player)

	# Log to GameEventLog
	var game_event_log = get_node_or_null("/root/GameEventLog")
	if game_event_log:
		game_event_log.add_player_entry(player, "HERE BE LOOT: %s designated as Loot Objective — Sustained Hits 1 near it!" % objective_id.replace("obj_", "Objective ").to_upper())

	return {
		"success": true,
		"objective_id": objective_id,
		"message": "Here Be Loot: %s designated as Loot Objective" % objective_id.replace("obj_", "Objective ").to_upper()
	}

func _clear_loot_objective(player: int) -> void:
	"""Clear loot objective for a player (called at start of new battle round)."""
	var player_key = str(player)
	var old_loot = _loot_objective.get(player_key, "")
	if old_loot != "":
		# Clear visual indicator on old objective
		_clear_loot_objective_visual(old_loot)
		_loot_objective[player_key] = ""
		# Also clear from GameState.state.board
		if GameState.state.board.has("loot_objective"):
			GameState.state.board["loot_objective"][player_key] = ""
		print("FactionAbilityManager: Cleared loot objective for player %d (was: %s)" % [player, old_loot])

func _update_loot_objective_visual(objective_id: String, player: int) -> void:
	"""Mark an objective on the board as the Loot Objective for the given player."""
	var mission_mgr = get_node_or_null("/root/MissionManager")
	if not mission_mgr:
		return
	# Clear any previous loot objective visual for this player
	for obj_id in mission_mgr.objectives_visual_refs:
		var obj_vis = mission_mgr.objectives_visual_refs[obj_id]
		if obj_vis and obj_vis.has_method("set_loot_objective"):
			obj_vis.set_loot_objective(false)
	# Set new loot objective visual
	var obj_visual = mission_mgr.objectives_visual_refs.get(objective_id, null)
	if obj_visual and obj_visual.has_method("set_loot_objective"):
		obj_visual.set_loot_objective(true, player)
	else:
		print("FactionAbilityManager: Could not find ObjectiveVisual for %s to mark as Loot Objective" % objective_id)

func _clear_loot_objective_visual(objective_id: String) -> void:
	"""Remove the Loot Objective visual indicator from an objective."""
	var mission_mgr = get_node_or_null("/root/MissionManager")
	if not mission_mgr:
		return
	var obj_visual = mission_mgr.objectives_visual_refs.get(objective_id, null)
	if obj_visual and obj_visual.has_method("set_loot_objective"):
		obj_visual.set_loot_objective(false)

static func _is_any_model_near_objective(unit: Dictionary, objective_pos, board: Dictionary) -> bool:
	"""Check if any alive model in the unit is within objective control range of a position."""
	# Convert objective position to Vector2 if needed
	var obj_vec = Vector2.ZERO
	if objective_pos is Vector2:
		obj_vec = objective_pos
	elif objective_pos is Dictionary:
		obj_vec = Vector2(objective_pos.get("x", 0), objective_pos.get("y", 0))
	else:
		return false

	# Objective control range: 3" + 20mm base = 3.78740157"
	var control_radius_px = 3.78740157 * 40.0  # PX_PER_INCH = 40.0

	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		var model_pos = model.get("position", null)
		if model_pos == null:
			continue
		if model_pos is Dictionary:
			model_pos = Vector2(model_pos.get("x", 0), model_pos.get("y", 0))
		elif not (model_pos is Vector2):
			continue

		# Edge-to-edge distance from model to objective center
		# Use model base radius for edge-to-edge calculation
		var base_mm = model.get("base_mm", 32)
		var base_radius_px = (base_mm / 25.4) * 40.0 / 2.0  # mm to inches to px, halved for radius
		var center_distance = model_pos.distance_to(obj_vec)
		var edge_distance = max(0.0, center_distance - base_radius_px)

		if edge_distance <= control_radius_px:
			return true

	return false

static func _unit_has_ork_loot_keyword(unit: Dictionary) -> bool:
	"""Check if unit has ORKS keyword AND is INFANTRY, MOUNTED, or WALKER."""
	var keywords = unit.get("meta", {}).get("keywords", [])
	var has_orks = false
	var has_type = false
	for kw in keywords:
		if kw is String:
			var upper = kw.to_upper()
			if upper == "ORKS":
				has_orks = true
			if upper == "INFANTRY" or upper == "MOUNTED" or upper == "WALKER":
				has_type = true
	return has_orks and has_type

static func check_here_be_loot_sustained_hits(attacker_unit: Dictionary, target_unit: Dictionary, board: Dictionary) -> bool:
	"""Static query: Check if Here Be Loot grants Sustained Hits 1 for this attack.
	Returns true if either:
	  1. Attacker is ORKS INFANTRY/MOUNTED/WALKER within range of their loot objective, OR
	  2. Target is within range of the attacker's loot objective.
	Called from RulesEngine static combat functions."""
	var attacker_owner = attacker_unit.get("owner", 0)
	if attacker_owner == 0:
		return false

	var player_key = str(attacker_owner)

	# Get loot objective from board state
	var loot_objectives = board.get("board", {}).get("loot_objective", {})
	var loot_obj_id = loot_objectives.get(player_key, "")
	if loot_obj_id == "":
		return false

	# Find the objective's position
	var objectives = board.get("board", {}).get("objectives", [])
	var loot_pos = null
	for obj in objectives:
		if obj.get("id", "") == loot_obj_id:
			loot_pos = obj.get("position", null)
			break

	if loot_pos == null:
		return false

	# Check condition 1: Attacker is ORKS INFANTRY/MOUNTED/WALKER within range
	if _unit_has_ork_loot_keyword(attacker_unit):
		if _is_any_model_near_objective(attacker_unit, loot_pos, board):
			return true

	# Check condition 2: Target (enemy) is within range of loot objective
	if _is_any_model_near_objective(target_unit, loot_pos, board):
		return true

	return false

static func check_bash_and_grab_reroll_wounds(attacker_unit: Dictionary, target_unit: Dictionary, board: Dictionary) -> bool:
	"""Static query: Check if Bash and Grab grants re-roll Wound rolls for this attack.
	Returns true if the target enemy unit is within range of the attacker's loot objective.
	Called from RulesEngine melee combat when the attacker has effect_bash_and_grab flag."""
	var attacker_owner = attacker_unit.get("owner", 0)
	if attacker_owner == 0:
		return false

	var player_key = str(attacker_owner)

	# Get loot objective from board state
	var loot_objectives = board.get("board", {}).get("loot_objective", {})
	var loot_obj_id = loot_objectives.get(player_key, "")
	if loot_obj_id == "":
		return false

	# Find the objective's position
	var objectives = board.get("board", {}).get("objectives", [])
	var loot_pos = null
	for obj in objectives:
		if obj.get("id", "") == loot_obj_id:
			loot_pos = obj.get("position", null)
			break

	if loot_pos == null:
		return false

	# Check if target is within range of loot objective
	if _is_any_model_near_objective(target_unit, loot_pos, board):
		return true

	return false

# ---- GRAB AND BASH (OA-4) ----

func get_grab_and_bash_eligible_units(player: int) -> Array:
	"""Get all eligible target units for Grab and Bash stratagem.
	Requirements: non-Gretchin ORKS unit, deployed, alive, within range of loot objective.
	Returns array of { unit_id: String, unit_name: String }."""
	var eligible = []
	var detachment = get_player_detachment(player)
	if detachment != "Freebooter Krew":
		return eligible

	var player_key = str(player)
	var loot_obj_id = _loot_objective.get(player_key, "")
	if loot_obj_id == "":
		print("FactionAbilityManager: Grab and Bash — no loot objective set for player %d" % player)
		return eligible

	# Find loot objective position
	var objectives = GameState.state.get("board", {}).get("objectives", [])
	var loot_pos = null
	for obj in objectives:
		if obj.get("id", "") == loot_obj_id:
			loot_pos = obj.get("position", null)
			break

	if loot_pos == null:
		print("FactionAbilityManager: Grab and Bash — loot objective %s position not found" % loot_obj_id)
		return eligible

	var units = GameState.state.get("units", {})
	var board = GameState.state

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue
		# Must be deployed
		if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
			continue
		# Must have alive models
		var has_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue
		# Must have ORKS keyword
		if not _unit_has_keyword(unit, "ORKS"):
			continue
		# Must NOT be GRETCHIN
		if _unit_has_keyword(unit, "GRETCHIN"):
			continue
		# Must be within range of loot objective
		if not _is_any_model_near_objective(unit, loot_pos, board):
			continue

		var unit_name = unit.get("meta", {}).get("name", unit_id)
		eligible.append({"unit_id": unit_id, "unit_name": unit_name})

	print("FactionAbilityManager: Grab and Bash — %d eligible units for player %d" % [eligible.size(), player])
	return eligible

# ---- DETACHMENT HELPER ----

func _unit_has_keyword(unit: Dictionary, keyword: String) -> bool:
	"""Check if a unit has a specific keyword (case-insensitive)."""
	var keywords = unit.get("meta", {}).get("keywords", [])
	for kw in keywords:
		if kw is String and kw.to_upper() == keyword.to_upper():
			return true
	return false

# ============================================================================
# FREEBOOTER KREW ENHANCEMENTS (OA-2)
# ============================================================================

# ---- ENHANCEMENT HELPERS ----

func _find_enhancement_bearer(player: int, enhancement_name: String) -> Dictionary:
	"""Find the CHARACTER unit that has a specific enhancement.
	Returns {bearer_id, combined_unit_id, bearer_name} or empty dict.
	combined_unit_id is the bodyguard unit the bearer is attached to (or bearer_id if standalone)."""
	var units = GameState.state.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue
		var enhancements = unit.get("meta", {}).get("enhancements", [])
		if enhancement_name in enhancements:
			# Check unit has alive models
			var has_alive = false
			for model in unit.get("models", []):
				if model.get("alive", true):
					has_alive = true
					break
			if not has_alive:
				continue
			# Find the combined unit (bodyguard this character is attached to, or self)
			var combined_unit_id = _get_combined_unit_for_character(unit_id)
			return {
				"bearer_id": unit_id,
				"combined_unit_id": combined_unit_id,
				"bearer_name": unit.get("meta", {}).get("name", unit_id)
			}
	return {}

func _get_combined_unit_for_character(char_unit_id: String) -> String:
	"""Get the bodyguard unit this character is attached to, or the char_unit_id if standalone."""
	var units = GameState.state.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		var attached = unit.get("attachment_data", {}).get("attached_characters", [])
		if char_unit_id in attached:
			return unit_id
	return char_unit_id

func _is_unit_within_range_inches(unit_a: Dictionary, unit_b: Dictionary, range_inches: float) -> bool:
	"""Check if any alive model in unit_a is within range_inches of any alive model in unit_b.
	Uses center-to-center distance minus base radii (edge-to-edge)."""
	var px_per_inch: float = 40.0
	var range_px = range_inches * px_per_inch

	for model_a in unit_a.get("models", []):
		if not model_a.get("alive", true):
			continue
		var pos_a = model_a.get("position", null)
		if pos_a == null:
			continue
		var vec_a = Vector2.ZERO
		if pos_a is Vector2:
			vec_a = pos_a
		elif pos_a is Dictionary:
			vec_a = Vector2(pos_a.get("x", 0), pos_a.get("y", 0))
		else:
			continue
		var base_a_mm = model_a.get("base_mm", 32)
		var radius_a_px = (base_a_mm / 25.4) * px_per_inch / 2.0

		for model_b in unit_b.get("models", []):
			if not model_b.get("alive", true):
				continue
			var pos_b = model_b.get("position", null)
			if pos_b == null:
				continue
			var vec_b = Vector2.ZERO
			if pos_b is Vector2:
				vec_b = pos_b
			elif pos_b is Dictionary:
				vec_b = Vector2(pos_b.get("x", 0), pos_b.get("y", 0))
			else:
				continue
			var base_b_mm = model_b.get("base_mm", 32)
			var radius_b_px = (base_b_mm / 25.4) * px_per_inch / 2.0

			var center_distance = vec_a.distance_to(vec_b)
			var edge_distance = max(0.0, center_distance - radius_a_px - radius_b_px)
			if edge_distance <= range_px:
				return true
	return false

func has_enhancement(player: int, enhancement_name: String) -> bool:
	"""Check if any unit owned by player has the given enhancement."""
	return not _find_enhancement_bearer(player, enhancement_name).is_empty()

# ---- DA KAPTIN (10pts, Warboss only) ----
# Start of any phase: select Battle-shocked friendly ORKS unit within 12" of bearer.
# That unit suffers D3 mortal wounds but is no longer Battle-shocked.
# Once per battle round.

func is_da_kaptin_available(player: int) -> bool:
	"""Check if Da Kaptin can be used this battle round."""
	if get_player_detachment(player) != "Freebooter Krew":
		return false
	# Check once-per-round
	var current_round = GameState.get_battle_round()
	if _da_kaptin_used_round.get(str(player), 0) >= current_round:
		return false
	# Must have a bearer
	var bearer = _find_enhancement_bearer(player, "Da Kaptin")
	if bearer.is_empty():
		return false
	# Must have at least one eligible target
	return get_da_kaptin_targets(player).size() > 0

func get_da_kaptin_targets(player: int) -> Array:
	"""Get all Battle-shocked friendly ORKS units within 12\" of the Da Kaptin bearer."""
	var bearer_info = _find_enhancement_bearer(player, "Da Kaptin")
	if bearer_info.is_empty():
		return []

	var bearer_unit_id = bearer_info.bearer_id
	var bearer_unit = GameState.state.get("units", {}).get(bearer_unit_id, {})
	if bearer_unit.is_empty():
		return []

	var targets = []
	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue
		# Can't target the bearer's own unit
		if unit_id == bearer_unit_id or unit_id == bearer_info.combined_unit_id:
			continue
		# Must be Battle-shocked
		if not unit.get("flags", {}).get("battle_shocked", false):
			continue
		# Must have ORKS keyword
		if not _unit_has_keyword(unit, "ORKS"):
			continue
		# Must have alive models
		var has_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue
		# Must be deployed (have positions)
		if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED and unit.get("status", "") != "DEPLOYED":
			continue
		# Must be within 12" of bearer
		if _is_unit_within_range_inches(bearer_unit, unit, 12.0):
			targets.append({
				"unit_id": unit_id,
				"unit_name": unit.get("meta", {}).get("name", unit_id)
			})

	return targets

func use_da_kaptin(player: int, target_unit_id: String) -> Dictionary:
	"""Activate Da Kaptin: D3 mortal wounds to target, remove Battle-shocked."""
	if not is_da_kaptin_available(player):
		return {"success": false, "error": "Da Kaptin is not available"}

	# Validate target
	var targets = get_da_kaptin_targets(player)
	var target_found = false
	for t in targets:
		if t.unit_id == target_unit_id:
			target_found = true
			break
	if not target_found:
		return {"success": false, "error": "Target %s is not an eligible Da Kaptin target" % target_unit_id}

	# Roll D3 for mortal wounds
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var d3_roll = rng.randi_range(1, 3)

	# Apply mortal wounds
	var board = GameState.create_snapshot()
	var mw_result = RulesEngine.apply_mortal_wounds(target_unit_id, d3_roll, board)

	# Apply damage diffs
	if mw_result.diffs.size() > 0:
		PhaseManager.apply_state_changes(mw_result.diffs)

	# Remove Battle-shocked status from target
	var target_unit = GameState.state.get("units", {}).get(target_unit_id, {})
	if target_unit.has("flags"):
		target_unit["flags"]["battle_shocked"] = false

	# Also remove Battle-shocked from any attached characters
	var attached_chars = GameState.get_attached_characters(target_unit_id)
	for char_id in attached_chars:
		var char_unit = GameState.state.get("units", {}).get(char_id, {})
		if not char_unit.is_empty() and char_unit.has("flags"):
			char_unit["flags"]["battle_shocked"] = false
			print("FactionAbilityManager: Da Kaptin — attached character %s also no longer Battle-shocked" % char_id)

	# Mark as used this round
	_da_kaptin_used_round[str(player)] = GameState.get_battle_round()

	var target_name = target_unit.get("meta", {}).get("name", target_unit_id)
	var bearer_info = _find_enhancement_bearer(player, "Da Kaptin")
	var bearer_name = bearer_info.get("bearer_name", "Da Kaptin bearer")
	print("FactionAbilityManager: DA KAPTIN — %s suffers %d mortal wounds (%d casualties), no longer Battle-shocked (bearer: %s)" % [
		target_name, d3_roll, mw_result.casualties, bearer_name])

	# Log to GameEventLog
	var game_event_log = get_node_or_null("/root/GameEventLog")
	if game_event_log:
		game_event_log.add_player_entry(player,
			"DA KAPTIN: %s suffers %d mortal wounds but is no longer Battle-shocked!" % [target_name, d3_roll])

	return {
		"success": true,
		"target_unit_id": target_unit_id,
		"target_name": target_name,
		"d3_roll": d3_roll,
		"mortal_wounds": d3_roll,
		"casualties": mw_result.casualties,
		"message": "Da Kaptin: %s suffers %d mortal wounds but is no longer Battle-shocked!" % [target_name, d3_roll]
	}

# ---- GIT-SPOTTER SQUIG (20pts, ORKS model) ----
# Passive: Bearer's unit ranged weapons have [IGNORES COVER].
# Handled via UnitAbilityManager ABILITY_EFFECTS (applied at phase start).
# See UnitAbilityManager.gd for the effect definition.

func has_git_spotter_squig(player: int) -> bool:
	"""Check if any unit has the Git-spotter Squig enhancement."""
	return has_enhancement(player, "Git-spotter Squig")

func get_git_spotter_squig_unit(player: int) -> Dictionary:
	"""Get the combined unit that has Git-spotter Squig active.
	Returns {bearer_id, combined_unit_id} or empty dict."""
	return _find_enhancement_bearer(player, "Git-spotter Squig")

# ---- BIONIK WORKSHOP (15pts, Big Mek or Painboy) ----
# At the start of the battle, roll D3:
# 1 = +1 Move, 2 = +1 Strength (melee), 3 = +1 to melee Hit rolls.
# Applies to the bearer's unit for the entire battle.

func resolve_bionik_workshop(player: int) -> Dictionary:
	"""Roll D3 at the start of the battle to determine the bionik bonus.
	Should be called once, at the start of the first battle round."""
	var bearer_info = _find_enhancement_bearer(player, "Bionik Workshop")
	if bearer_info.is_empty():
		return {"success": false, "error": "No unit with Bionik Workshop found"}

	var bearer_id = bearer_info.bearer_id
	# Check if already resolved for this bearer
	if _bionik_workshop_results.has(bearer_id):
		return {"success": false, "error": "Bionik Workshop already resolved for %s" % bearer_id}

	# Roll D3
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var d3_roll = rng.randi_range(1, 3)

	var bonus_type = ""
	var bonus_description = ""
	match d3_roll:
		1:
			bonus_type = "move"
			bonus_description = "+1 Move"
		2:
			bonus_type = "strength"
			bonus_description = "+1 Strength (melee weapons)"
		3:
			bonus_type = "hit"
			bonus_description = "+1 to melee Hit rolls"

	_bionik_workshop_results[bearer_id] = {
		"roll": d3_roll,
		"bonus_type": bonus_type,
		"combined_unit_id": bearer_info.combined_unit_id
	}

	# Apply the bonus as a persistent flag on the combined unit
	var combined_unit = GameState.state.get("units", {}).get(bearer_info.combined_unit_id, {})
	if not combined_unit.is_empty():
		if not combined_unit.has("flags"):
			combined_unit["flags"] = {}
		combined_unit["flags"]["bionik_workshop_bonus"] = bonus_type
		combined_unit["flags"]["bionik_workshop_bearer"] = bearer_id
		print("FactionAbilityManager: BIONIK WORKSHOP — %s grants %s to unit %s (rolled D3 = %d)" % [
			bearer_info.bearer_name, bonus_description, bearer_info.combined_unit_id, d3_roll])

	# Log to GameEventLog
	var game_event_log = get_node_or_null("/root/GameEventLog")
	if game_event_log:
		game_event_log.add_player_entry(player,
			"BIONIK WORKSHOP: %s rolled D3 = %d — %s for bearer's unit!" % [bearer_info.bearer_name, d3_roll, bonus_description])

	return {
		"success": true,
		"bearer_id": bearer_id,
		"bearer_name": bearer_info.bearer_name,
		"combined_unit_id": bearer_info.combined_unit_id,
		"d3_roll": d3_roll,
		"bonus_type": bonus_type,
		"bonus_description": bonus_description,
		"message": "Bionik Workshop: Rolled D3 = %d — %s!" % [d3_roll, bonus_description]
	}

func get_bionik_workshop_result(bearer_id: String) -> Dictionary:
	"""Get the Bionik Workshop result for a specific bearer. Returns empty dict if none."""
	return _bionik_workshop_results.get(bearer_id, {})

func get_bionik_workshop_bonus_for_unit(unit_id: String) -> String:
	"""Get the Bionik Workshop bonus type active on a unit. Returns empty string if none."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	return unit.get("flags", {}).get("bionik_workshop_bonus", "")

# ---- RAZGIT'S MAGIK MAP (25pts, ORKS model) ----
# After deployment, select up to 3 friendly Orks INFANTRY units and redeploy them.
# Any of those units can be placed into Strategic Reserves.

func has_razgit_magik_map(player: int) -> bool:
	"""Check if a player has the Razgit's Magik Map enhancement."""
	return has_enhancement(player, "Razgit's Magik Map")

func get_razgit_eligible_units(player: int) -> Array:
	"""Get all Orks INFANTRY units eligible for Razgit's Magik Map redeployment."""
	if not has_razgit_magik_map(player):
		return []

	var bearer_info = _find_enhancement_bearer(player, "Razgit's Magik Map")
	if bearer_info.is_empty():
		return []

	var eligible = []
	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue
		# Skip the bearer's own unit (bearer doesn't redeploy themselves)
		if unit_id == bearer_info.bearer_id:
			continue
		# Must be deployed
		if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED and unit.get("status", "") != "DEPLOYED":
			continue
		# Must be ORKS INFANTRY
		if not _unit_has_keyword(unit, "ORKS"):
			continue
		if not _unit_has_keyword(unit, "INFANTRY"):
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

func get_razgit_redeploys_remaining(player: int) -> int:
	"""Get how many Razgit's Magik Map redeployments remain (max 3)."""
	return 3 - _razgit_redeploys_used.get(str(player), 0)

func mark_razgit_redeploy_used(player: int) -> void:
	"""Mark one Razgit's Magik Map redeployment as used."""
	var pk = str(player)
	_razgit_redeploys_used[pk] = _razgit_redeploys_used.get(pk, 0) + 1
	print("FactionAbilityManager: Razgit's Magik Map — player %d used redeploy %d/3" % [
		player, _razgit_redeploys_used[pk]])

func is_razgit_redeploy_available(player: int) -> bool:
	"""Check if Razgit's Magik Map redeployment slots are still available."""
	return has_razgit_magik_map(player) and get_razgit_redeploys_remaining(player) > 0

# ============================================================================
# PHASE LIFECYCLE
# ============================================================================

# ============================================================================
# MARTIAL KA'TAH — STANCE SELECTION (Fight Phase)
# ============================================================================

func unit_has_katah(unit_id: String) -> bool:
	"""Check if a unit has the Martial Ka'tah faction ability."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")
		if ability_name == "Martial Ka'tah":
			return true
	return false

func apply_katah_stance(unit_id: String, stance: String) -> Dictionary:
	"""Apply a Ka'tah stance to a unit. Sets effect flags for RulesEngine.
	stance: 'dacatarai', 'rendax', or 'both' (Master of the Stances)"""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return {"success": false, "error": "Unit not found: %s" % unit_id}

	if stance != "dacatarai" and stance != "rendax" and stance != "both":
		return {"success": false, "error": "Invalid stance: %s (must be 'dacatarai', 'rendax', or 'both')" % stance}

	# Clear any previous stance flags
	clear_katah_stance(unit_id)

	# Set the appropriate effect flag
	if not unit.has("flags"):
		unit["flags"] = {}

	if stance == "both":
		# Master of the Stances: both Sustained Hits 1 AND Lethal Hits
		unit["flags"]["effect_sustained_hits"] = true
		unit["flags"]["effect_lethal_hits"] = true
		unit["flags"]["katah_stance"] = "both"
		unit["flags"]["katah_sustained_hits_value"] = 1
	elif stance == "dacatarai":
		# Sustained Hits 1 on melee attacks
		unit["flags"]["effect_sustained_hits"] = true
		unit["flags"]["katah_stance"] = "dacatarai"
		unit["flags"]["katah_sustained_hits_value"] = 1
	elif stance == "rendax":
		# Lethal Hits on melee attacks
		unit["flags"]["effect_lethal_hits"] = true
		unit["flags"]["katah_stance"] = "rendax"

	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var stance_display = ""
	if stance == "both":
		stance_display = "Master of the Stances (Dacatarai + Rendax)"
	else:
		stance_display = FACTION_ABILITIES["Martial Ka'tah"]["stances"][stance]["display"]
	print("FactionAbilityManager: Martial Ka'tah — %s (%s) assumes %s stance" % [unit_name, unit_id, stance_display])

	return {
		"success": true,
		"unit_id": unit_id,
		"stance": stance,
		"stance_display": stance_display,
		"message": "Martial Ka'tah: %s assumes %s" % [unit_name, stance_display]
	}

func clear_katah_stance(unit_id: String) -> void:
	"""Clear Ka'tah stance flags from a unit (called after unit finishes fighting)."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return

	var flags = unit.get("flags", {})
	var had_stance = flags.get("katah_stance", "") != ""

	# Clear all Ka'tah-related flags
	flags.erase("effect_sustained_hits")
	flags.erase("effect_lethal_hits")
	flags.erase("katah_stance")
	flags.erase("katah_sustained_hits_value")

	if had_stance:
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		print("FactionAbilityManager: Martial Ka'tah — cleared stance for %s (%s)" % [unit_name, unit_id])

func get_katah_stance(unit_id: String) -> String:
	"""Get the current Ka'tah stance for a unit. Returns empty string if none."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	return unit.get("flags", {}).get("katah_stance", "")

# ============================================================================
# PHASE LIFECYCLE
# ============================================================================

func on_command_phase_start(player: int) -> void:
	"""Called at the start of each Command Phase. Detects abilities and clears old targets."""
	detect_faction_abilities(player)

	# Detect detachment (P2-27)
	detect_player_detachment(player)

	# Deactivate Waaagh! if it was active (it lasts "until the start of your next Command phase")
	if _waaagh_active.get(str(player), false):
		deactivate_waaagh(player)

	# OA-46: Clear Plant the Waaagh! Banner per-unit effects (lasts until start of next battle round)
	_clear_plant_waaagh_banner_effects(player)

	# Clear previous Combat Doctrine effects (they last until next Command phase)
	_clear_doctrine_effects(player)

	# Apply passive detachment abilities (Get Stuck In)
	var detachment = get_player_detachment(player)
	if detachment == "War Horde":
		_apply_get_stuck_in(player)

	# Clear loot objective from previous round (Freebooter Krew — OA-1)
	# Loot objective resets each battle round; selection happens via action in CommandPhase
	if detachment == "Freebooter Krew":
		_clear_loot_objective(player)
		print("FactionAbilityManager: Player %d has Freebooter Krew — awaiting loot objective selection" % player)

	# Bionik Workshop — resolve on first Command Phase (start of battle) (OA-2)
	if detachment == "Freebooter Krew" and not _bionik_workshop_resolved:
		if has_enhancement(player, "Bionik Workshop"):
			var bw_result = resolve_bionik_workshop(player)
			if bw_result.success:
				print("FactionAbilityManager: Bionik Workshop resolved for player %d — %s" % [player, bw_result.bonus_description])
		_bionik_workshop_resolved = true

	# Clear previous Oath of Moment (it's re-selected each Command Phase)
	if player_has_ability(player, "Oath of Moment"):
		clear_oath_of_moment(player)
		print("FactionAbilityManager: Player %d has Oath of Moment — awaiting target selection" % player)

func on_command_phase_end(player: int) -> void:
	"""Called when Command Phase ends. Auto-select if player forgot to choose."""
	if player_has_ability(player, "Oath of Moment"):
		var current_target = get_oath_of_moment_target(player)
		if current_target == "":
			# Auto-select first available enemy unit
			var targets = get_eligible_oath_targets(player)
			if targets.size() > 0:
				var auto_result = set_oath_of_moment_target(player, targets[0].unit_id)
				print("FactionAbilityManager: Auto-selected Oath of Moment target: %s" % auto_result.get("target_name", "?"))
			else:
				print("FactionAbilityManager: No eligible Oath of Moment targets available")

# ============================================================================
# SAVE/LOAD SUPPORT
# ============================================================================

func get_state_for_save() -> Dictionary:
	"""Return state data for save games."""
	return {
		"active_effects": _active_effects.duplicate(true),
		"player_abilities": _player_abilities.duplicate(true),
		"waaagh_used": _waaagh_used.duplicate(true),
		"waaagh_active": _waaagh_active.duplicate(true),
		# Detachment ability state (P2-27)
		"player_detachment": _player_detachment.duplicate(true),
		"doctrines_used": _doctrines_used.duplicate(true),
		"active_doctrine": _active_doctrine.duplicate(true),
		"active_mastery": _active_mastery.duplicate(true),
		"mastery_selected_round": _mastery_selected_round.duplicate(true),
		# Loot objective state (OA-1)
		"loot_objective": _loot_objective.duplicate(true),
		"loot_objective_round": _loot_objective_round.duplicate(true),
		# Enhancement state (OA-2)
		"da_kaptin_used_round": _da_kaptin_used_round.duplicate(true),
		"bionik_workshop_results": _bionik_workshop_results.duplicate(true),
		"bionik_workshop_resolved": _bionik_workshop_resolved,
		"razgit_redeploys_used": _razgit_redeploys_used.duplicate(true),
		"razgit_resolved": _razgit_resolved,
		# OA-46: Plant the Waaagh! Banner state
		"plant_waaagh_banner_used": _plant_waaagh_banner_used.duplicate(true)
	}

func load_state(data: Dictionary) -> void:
	"""Restore state from save data."""
	_active_effects = data.get("active_effects", {"1": {}, "2": {}})
	_player_abilities = data.get("player_abilities", {"1": [], "2": []})
	_waaagh_used = data.get("waaagh_used", {"1": false, "2": false})
	_waaagh_active = data.get("waaagh_active", {"1": false, "2": false})
	# Detachment ability state (P2-27)
	_player_detachment = data.get("player_detachment", {"1": "", "2": ""})
	_doctrines_used = data.get("doctrines_used", {"1": [], "2": []})
	_active_doctrine = data.get("active_doctrine", {"1": "", "2": ""})
	_active_mastery = data.get("active_mastery", {"1": "", "2": ""})
	_mastery_selected_round = data.get("mastery_selected_round", {"1": 0, "2": 0})
	# Loot objective state (OA-1)
	_loot_objective = data.get("loot_objective", {"1": "", "2": ""})
	_loot_objective_round = data.get("loot_objective_round", {"1": 0, "2": 0})
	# Restore loot objective to GameState.state.board for static access
	for pk in _loot_objective:
		if _loot_objective[pk] != "":
			if not GameState.state.board.has("loot_objective"):
				GameState.state.board["loot_objective"] = {}
			GameState.state.board["loot_objective"][pk] = _loot_objective[pk]
	# Enhancement state (OA-2)
	_da_kaptin_used_round = data.get("da_kaptin_used_round", {"1": 0, "2": 0})
	_bionik_workshop_results = data.get("bionik_workshop_results", {})
	_bionik_workshop_resolved = data.get("bionik_workshop_resolved", false)
	_razgit_redeploys_used = data.get("razgit_redeploys_used", {"1": 0, "2": 0})
	_razgit_resolved = data.get("razgit_resolved", false)
	# OA-46: Plant the Waaagh! Banner state
	_plant_waaagh_banner_used = data.get("plant_waaagh_banner_used", {})
	# Restore bionik workshop flags on units
	for bearer_id in _bionik_workshop_results:
		var bw_data = _bionik_workshop_results[bearer_id]
		var combined_unit_id = bw_data.get("combined_unit_id", "")
		if combined_unit_id != "":
			var unit = GameState.state.get("units", {}).get(combined_unit_id, {})
			if not unit.is_empty():
				if not unit.has("flags"):
					unit["flags"] = {}
				unit["flags"]["bionik_workshop_bonus"] = bw_data.get("bonus_type", "")
				unit["flags"]["bionik_workshop_bearer"] = bearer_id
	print("FactionAbilityManager: State loaded — effects: %s, waaagh_active: %s, detachments: %s" % [str(_active_effects), str(_waaagh_active), str(_player_detachment)])
