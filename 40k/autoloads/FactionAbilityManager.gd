extends Node

# Codex: Orks (11e) army rules + detachment rules (WP-O34). At edition 11 the
# 10e-era Ork detachment code below is gated off and these modules decide.
const Ork11eArmyRules = preload("res://scripts/codex/orks/OrkArmyRules11e.gd")
const Ork11eDetachments = preload("res://scripts/codex/orks/OrkDetachments11e.gd")
const ArmyDetachments11e = preload("res://scripts/codex/ArmyDetachments11e.gd")

# FactionAbilityManager - Handles faction-wide abilities triggered during the Command Phase
#
# Per 10th Edition rules, many factions have a faction ability that triggers
# at the start of the Command Phase. This manager:
# 1. Detects which faction abilities are available for each player
# 2. Tracks active faction ability effects (e.g., Waaagh! activation)
# 3. Provides query functions for RulesEngine to check during combat resolution
#
# Currently supported faction abilities:
# (The 10th-edition Oath of Moment army rule was removed: Codex: Space Marines
#  (11e) replaced it with Combat Doctrines — scripts/codex/space_wolves/SWArmyRules11e.gd.)
# - Waaagh! (Orks):
#   Once per battle, at the start of your Command phase, you can call a Waaagh!.
#   Until the start of your next Command phase:
#   (1) Units with this ability are eligible to charge in a turn they Advanced.
#   (2) Add 1 to Strength and Attacks of melee weapons.
#   (3) Models have a 5+ invulnerable save.
#
# Detachment abilities (P2-27):
# - Combat Doctrines (Space Marines / Gladius Task Force) — EDITION 10 ONLY:
#   At the start of your Command phase, select one Combat Doctrine. Each once per battle.
#   (11e: the Codex: Space Marines army rule of every Space Marine army,
#   scripts/codex/space_wolves/SWArmyRules11e.gd — WP-M2a.)
#   Devastator: eligible to shoot after Advancing. Tactical: shoot+charge after Falling Back.
#   Assault: charge after Advancing.
# - Get Stuck In (Orks / War Horde):
#   Passive: Melee weapons equipped by ORKS models have Sustained Hits 1.
# - Codex: Adeptus Custodes (11e) detachments + enhancements live in
#   scripts/codex/custodes/CustodesDetachments.gd / CustodesEnhancements.gd
#   (WP-C46); the 10e Shield Host / Lions of the Emperor / Silent Hunters /
#   Talons / Tharanatoi / Solar Spearhead code that lived here is gone.

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
}

# ============================================================================
# FREEBOOTER KREW ENHANCEMENTS (OA-2)
# ============================================================================
# Enhancement abilities available to the Freebooter Krew detachment.
# Each enhancement can be equipped on a specific CHARACTER model.
# The enhancement name is stored in unit.meta.enhancements[].
# Points verified against 11e data (data/40kdc/enhancements.json,
# detachment_id "freebooter-krew"): Da Kaptin 10, Git-spotter Squig 20,
# Bionik Workshop 15, Razgit's Magik Map 25 — all four still exist in 11e.

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
	# Codex: Adeptus Custodes (11e) — resolved by scripts/codex/custodes/
	# CustodesKatah.gd (readied step, the six ka'tah abilities in their
	# stratagem windows). Listed here so the army's faction abilities report it.
	"Martial Ka'tah": {
		"faction_keyword": "ADEPTUS CUSTODES",
		"trigger": "command_phase_start",
		"requires_target": false,
		"effect": "readied",
		"description": "At the start of your Command phase, friendly ADEPTUS CUSTODES units with this ability are readied. While a unit is readied it can use one ka'tah ability (Conservai, Calistus, Salvus, Dacatarai, Kaptaris, Rendax) in that ability's WHEN; it is then no longer readied."
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
# Format: { "1": { <effect_key>: <value> }, "2": {} }
var _active_effects: Dictionary = {"1": {}, "2": {}}

# Cache of which faction abilities each player has (computed on phase enter)
# Format: { "1": ["Waaagh!"], "2": [] }
var _player_abilities: Dictionary = {"1": [], "2": []}

# Waaagh! state tracking
# Per-player: whether Waaagh! has been called this battle (once per battle)
var _waaagh_used: Dictionary = {"1": false, "2": false}
# Per-player: whether Waaagh! is currently active (lasts until start of next Command phase)
var _waaagh_active: Dictionary = {"1": false, "2": false}
# Da Boss Is Watchin' (Bully Boyz): whether the second, scoped Waaagh! has
# been called this battle (WARBOSS/NOBZ/MEGANOBZ units only)
var _boss_watchin_used: Dictionary = {"1": false, "2": false}

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
	# 11e War Cry: riled up "until the end of the next turn" (WP-O34).
	Ork11eArmyRules.on_war_cry_used(player)

	# Apply Waaagh! effects to all Ork units
	_apply_waaagh_effects(player)

	print("FactionAbilityManager: WAAAGH! Player %d calls a Waaagh! — effects active until next Command phase" % player)

	# Log Waaagh! activation to GameEventLog
	var game_event_log = get_node_or_null("/root/GameEventLog")
	if game_event_log:
		game_event_log.add_player_entry(player, "WAAAGH! Called — %s!" % waaagh_effects_summary())

	return {
		"success": true,
		"message": "WAAAGH! Called — %s active!" % waaagh_effects_summary()
	}

func deactivate_waaagh(player: int) -> void:
	"""Deactivate Waaagh! at the start of the player's next Command Phase."""
	var player_key = str(player)
	if _waaagh_active.get(player_key, false):
		_waaagh_active[player_key] = false
		_clear_waaagh_effects(player)
		print("FactionAbilityManager: Waaagh! deactivated for player %d" % player)

# The persistent effect_* flags a Waaagh! (army Waaagh!, Da Boss Is Watchin',
# Plant the Waaagh! Banner, Grab and Bash — all set waaagh_active) grants to a
# unit. Per the core rules these last "until the start of your next Command
# phase", so a per-phase blanket effect-flag clear (e.g. ShootingPhase's
# end-of-phase stratagem cleanup) must NOT strip them.
const WAAAGH_PERSISTENT_EFFECT_FLAGS := [
	"effect_advance_and_charge",
	"effect_invuln", "effect_invuln_source",
	"effect_fnp", "effect_fnp_source",
	"effect_crit_hit_on", "effect_crit_hit_on_source",
	"effect_oc_override", "effect_oc_source",
]

func snapshot_persistent_ability_flags(flags: Dictionary) -> Dictionary:
	"""Return a copy of the Waaagh!-granted effect_* flags on a unit so a
	phase-end blanket effect-flag clear can restore them afterwards. Returns an
	empty dict when the unit has no active Waaagh! (waaagh_active is set by every
	Waaagh! variant, so it is the single gate). Bug (2026-07): units that
	Advanced during an active Waaagh! lost effect_advance_and_charge at the end
	of the Shooting phase and so could not charge; the 5+ invuln vanished too."""
	if not flags.get("waaagh_active", false):
		return {}
	var preserved := {}
	for flag_name in WAAAGH_PERSISTENT_EFFECT_FLAGS:
		if flags.has(flag_name):
			preserved[flag_name] = flags[flag_name]
	return preserved

# ---- DA BOSS IS WATCHIN' (Bully Boyz detachment rule) ----
# At the start of your Command phase, in a turn in which you have not called
# a Waaagh!, if you have one or more WARBOSS models on the battlefield (or
# embarked within a TRANSPORT that is on the battlefield), you can call a
# Waaagh! for a SECOND time this battle. That second Waaagh! only counts as
# having been called for WARBOSS, NOBZ and MEGANOBZ units from your army.

func is_boss_watchin_waaagh_available(player: int) -> bool:
	"""Second Waaagh! availability: Bully Boyz, first Waaagh! spent (and no
	longer active), second not yet used, and a WARBOSS alive."""
	# 10e Bully Boyz rule — the 11e rule is Displays of Savagery (WP-O34).
	if GameConstants.edition >= 11:
		return false
	if not player_has_detachment(player, "Bully Boyz"):
		return false
	var player_key = str(player)
	if not _waaagh_used.get(player_key, false):
		return false  # the regular Waaagh! comes first
	if _waaagh_active.get(player_key, false):
		return false  # "in a turn in which you have not called a Waaagh!"
	if _boss_watchin_used.get(player_key, false):
		return false
	return _player_has_alive_warboss(player)

func _player_has_alive_warboss(player: int) -> bool:
	"""A WARBOSS model on the battlefield or embarked in a Transport. Units in
	Strategic Reserves do not count."""
	var units = GameState.state.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if int(unit.get("owner", 0)) != player:
			continue
		if not _unit_has_keyword(unit, "WARBOSS"):
			continue
		if unit.get("status", 0) == GameStateData.UnitStatus.IN_RESERVES:
			continue
		for model in unit.get("models", []):
			if model.get("alive", true):
				return true
	return false

func activate_boss_watchin_waaagh(player: int) -> Dictionary:
	"""Call the second, scoped Waaagh! (Da Boss Is Watchin')."""
	if not is_boss_watchin_waaagh_available(player):
		return {"success": false, "error": "Da Boss Is Watchin' second Waaagh! is not available"}

	var player_key = str(player)
	_boss_watchin_used[player_key] = true
	_waaagh_active[player_key] = true

	_apply_waaagh_effects(player, ["WARBOSS", "NOBZ", "MEGANOBZ"])

	print("FactionAbilityManager: DA BOSS IS WATCHIN' — Player %d calls a second Waaagh! (Warboss/Nobz/Meganobz only)" % player)
	var game_event_log = get_node_or_null("/root/GameEventLog")
	if game_event_log:
		game_event_log.add_player_entry(player, "DA BOSS IS WATCHIN' — second WAAAGH! called for Warboss, Nobz and Meganobz units!")

	return {
		"success": true,
		"message": "DA BOSS IS WATCHIN' — second WAAAGH! for Warboss/Nobz/Meganobz units!"
	}

func _apply_waaagh_effects(player: int, keyword_scope: Array = []) -> void:
	"""Apply Waaagh! flags to all Ork units with the Waaagh! ability. With a
	non-empty keyword_scope, only units having at least one of those keywords
	are affected (Da Boss Is Watchin' scopes the second Waaagh! to
	WARBOSS/NOBZ/MEGANOBZ units)."""
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

		# Scoped Waaagh! (Da Boss Is Watchin'): keyword gate
		if not keyword_scope.is_empty():
			var in_scope := false
			for kw in keyword_scope:
				if _unit_has_keyword(unit, kw):
					in_scope = true
					break
			if not in_scope:
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
		# 11e (Codex: Orks army rule): while riled up, the unit's ranged attacks
		# have [ASSAULT]. WAAAGH_ASSAULT_MARKER records that the Waaagh! set it so
		# the clear never strips an [ASSAULT] grant from another source.
		if GameConstants.edition >= 11 and not unit["flags"].get("effect_advance_and_shoot", false):
			unit["flags"]["effect_advance_and_shoot"] = true
			unit["flags"][WAAAGH_ASSAULT_MARKER] = true

		# (WP-O6: the pre-codex Krumpin' Time / Big an' Shooty / Big an' Stompy /
		# Prophet of Da Great Waaagh! / Special Dose riders are gone — the Codex:
		# Orks (11e) datasheet abilities live in OrkAbilities11e.gd.)

		# OA-46: Da Boss Iz Watchin' — 4+ invuln and OC 5 while Waaagh! active (Nob with Waaagh! Banner)
		# Upgrade invuln from 5+ to 4+ and set OC 5 for units with this ability
		if _unit_has_ability(unit, "Da Boss Iz Watchin'"):
			_apply_da_boss_iz_watchin(unit, unit_id)

		var unit_name = unit.get("meta", {}).get("name", unit_id)
		print("FactionAbilityManager: Waaagh! effects applied to %s (%s) — %s" % [unit_name, unit_id, waaagh_effects_summary()])

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
			# 11e riled-up [ASSAULT]: only when the Waaagh! granted it.
			if flags.get(WAAAGH_ASSAULT_MARKER, false):
				flags.erase("effect_advance_and_shoot")
			flags.erase(WAAAGH_ASSAULT_MARKER)
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

# Marker (no effect_ prefix, so phase-end effect wipes leave it alone): the
# army Waaagh! set effect_advance_and_shoot (11e riled-up [ASSAULT]).
const WAAAGH_ASSAULT_MARKER := "waaagh_assault_granted"

static func waaagh_melee_bonus_applies(unit: Dictionary) -> bool:
	"""The 10e Waaagh! adds 1 to the Strength and Attacks of melee weapons. The
	11e Waaagh! has no such bonus: a riled-up unit gets a 5+ invulnerable save,
	[ASSAULT] on its ranged attacks and may charge after advancing (Codex: Orks
	army rule). Every melee consumer (RulesEngine, AI estimates) goes through
	this gate so the 10e bonus can never leak into an 11e game."""
	return GameConstants.edition < 11 and is_waaagh_active_for_unit(unit)

static func waaagh_effects_summary() -> String:
	"""Player-facing list of what a Waaagh! grants, for logs and tooltips."""
	if GameConstants.edition >= 11:
		return "riled up: 5+ invuln, ranged [ASSAULT], advance and charge"
	return "advance and charge, +1 S/A melee, 5+ invuln"

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
	"""Get cached detachment for a player (the PRIMARY one — 11e armies may
	take several; use player_has_detachment / get_player_detachments)."""
	return _player_detachment.get(str(player), "")

func get_player_detachments(player: int) -> Array:
	"""Every detachment the player took (11e multi-detachment armies), primary
	first — all of them are active."""
	var names: Array = ArmyDetachments11e.player_detachments(player)
	# The cached primary (detect_player_detachment) owns the primary slot, as
	# it did before multi-detachment armies; extras come from the faction block.
	var cached := get_player_detachment(player)
	if cached != "":
		if names.is_empty():
			names = [cached]
		elif ArmyDetachments11e.det_key(str(names[0])) != ArmyDetachments11e.det_key(cached):
			var rest: Array = names.slice(1).filter(func(n): return ArmyDetachments11e.det_key(str(n)) != ArmyDetachments11e.det_key(cached))
			names = [cached] + rest
	return names

func player_has_detachment(player: int, detachment_name: String) -> bool:
	"""Did the player take this detachment (any of their detachments)?"""
	var key := ArmyDetachments11e.det_key(detachment_name)
	for d in get_player_detachments(player):
		if ArmyDetachments11e.det_key(str(d)) == key:
			return true
	return false

func has_detachment_ability(player: int) -> bool:
	"""Check if any of a player's detachments has a known detachment ability."""
	for d in get_player_detachments(player):
		if d in DETACHMENT_ABILITIES:
			return true
	return false

# ---- COMBAT DOCTRINES (Space Marines — Gladius Task Force) ----

func get_available_doctrines(player: int) -> Array:
	"""Get list of Combat Doctrines that haven't been used yet this battle."""
	# 10e only: at 11e Combat Doctrines is the Codex: Space Marines army rule of
	# every Space Marine army (SWArmyRules11e.gd, WP-M2a) — no Gladius-only path.
	if GameConstants.edition >= 11:
		return []
	if not player_has_detachment(player, "Gladius Task Force"):
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

	# 10e only (WP-M2a): the 11e army rule lives in SWArmyRules11e.gd.
	if GameConstants.edition >= 11:
		return {"success": false, "error": "Combat Doctrines (11e) is the Codex: Space Marines army rule — select it in the Command panel (SWArmyRules11e)"}
	if not player_has_detachment(player, "Gladius Task Force"):
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
	return player_has_detachment(player, "War Horde")

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

# ============================================================================
# PASSIVE ORK DETACHMENT RULES (2026-07 sweep follow-up)
# ============================================================================

func _apply_mob_mentality(player: int) -> void:
	"""Green Tide — Mob Mentality: BOYZ units have a 6+ invulnerable save,
	5+ while containing 10 or more models (counts-as-10 effects included).
	Applied as effect_invuln flags at each Command phase start; never
	overwrites a better invulnerable save from another source. Mid-round
	casualties only downgrade at the next refresh (documented simplification
	— RAW checks the model count per attack)."""
	var units = GameState.state.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue
		if not _unit_has_keyword(unit, "BOYZ"):
			continue
		var alive := 0
		for model in unit.get("models", []):
			if model.get("alive", true):
				alive += 1
		if alive == 0:
			continue
		var inv = 5 if (alive >= 10 or unit_counts_as_10(unit)) else 6
		if not unit.has("flags"):
			unit["flags"] = {}
		var current = int(unit["flags"].get("effect_invuln", 0))
		if current > 0 and current <= inv:
			continue
		unit["flags"]["effect_invuln"] = inv
		unit["flags"]["effect_invuln_source"] = "Mob Mentality"
		print("FactionAbilityManager: Mob Mentality — %s has a %d+ invulnerable save (%d models)" % [unit_id, inv, alive])

func _apply_detachment_keyword_grants(player: int, detachment: String) -> void:
	"""11e detachment keyword grants: Dread Mob Gretchin and Taktikal Brigade
	Stormboyz gain BATTLELINE."""
	var match_kw := ""
	if detachment == "Dread Mob":
		match_kw = "GRETCHIN"
	elif detachment == "Taktikal Brigade":
		match_kw = "STORMBOYZ"
	else:
		return
	var units = GameState.state.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue
		if not _unit_has_keyword(unit, match_kw):
			continue
		var kws: Array = unit.get("meta", {}).get("keywords", [])
		if not "BATTLELINE" in kws:
			kws.append("BATTLELINE")
			print("FactionAbilityManager: %s — %s gains BATTLELINE" % [detachment, unit_id])

func unit_has_detachment_assault(unit: Dictionary) -> bool:
	"""Unit-wide ranged-ASSAULT detachment rules: More Dakka!'s Dakka! Dakka!
	Dakka! (ORKS INFANTRY/WALKER weapons have ASSAULT) and Kult of Speed's
	Adrenaline Junkies (Speed Freeks eligible to shoot after Advancing)."""
	# 10e rules; at 11e [ASSAULT] comes from EffectPrimitives.has_effect_advance_and_shoot (WP-O34).
	if GameConstants.edition >= 11:
		return false
	var owner = int(unit.get("owner", 0))
	if owner <= 0:
		return false
	if player_has_detachment(owner, "More Dakka!") and _unit_has_keyword(unit, "ORKS") \
			and (_unit_has_keyword(unit, "INFANTRY") or _unit_has_keyword(unit, "WALKER")):
		return true
	if player_has_detachment(owner, "Kult of Speed") and _unit_has_keyword(unit, "SPEED FREEKS"):
		return true
	return false

func unit_has_adrenaline_junkies(unit: Dictionary) -> bool:
	"""Kult of Speed — Adrenaline Junkies: Speed Freeks units are eligible to
	shoot and declare a charge in a turn in which they Advanced or Fell Back."""
	# 10e rule; at 11e the charge part is EffectPrimitives' advance/fall-back-and-charge
	# hook and falling back still forbids shooting (09.07) (WP-O34).
	if GameConstants.edition >= 11:
		return false
	var owner = int(unit.get("owner", 0))
	if owner <= 0:
		return false
	return player_has_detachment(owner, "Kult of Speed") and _unit_has_keyword(unit, "SPEED FREEKS")

func unit_has_more_dakka_waaagh_sustained(unit: Dictionary) -> bool:
	"""More Dakka! — while the Waaagh! is active, ranged weapons on ORKS
	INFANTRY/WALKER models also have SUSTAINED HITS 1."""
	var owner = int(unit.get("owner", 0))
	if owner <= 0 or not player_has_detachment(owner, "More Dakka!"):
		return false
	if not (_unit_has_keyword(unit, "ORKS") and (_unit_has_keyword(unit, "INFANTRY") or _unit_has_keyword(unit, "WALKER"))):
		return false
	return is_waaagh_active_for_unit(unit)

func _unit_is_thundering_wagon(unit: Dictionary) -> bool:
	return _unit_has_keyword(unit, "BATTLEWAGON") or _unit_has_keyword(unit, "KILL RIG") or _unit_has_keyword(unit, "HUNTA RIG")

func unit_has_detachment_charge_reroll(unit: Dictionary) -> bool:
	"""Charge re-roll detachment rules: Blitz Brigade's Eager for the Fight
	(ORKS units that disembarked this turn) and Rollin' Deff's Thundering
	Wagons (Battlewagon / Kill Rig / Hunta Rig units)."""
	# 11e Blitz Brigade — Unstoppable Momentum: WAGON units re-roll charges (WP-O34).
	# Codex: Adeptus Custodes (11e) Dread Host / Combat Deployment (CustodesDetachments.gd, WP-C46).
	if GameConstants.edition >= 11:
		return Ork11eDetachments.charge_reroll_source(unit) != "" \
			or load("res://scripts/codex/custodes/CustodesDetachments.gd").charge_reroll_source(unit) != "" \
			or load("res://scripts/codex/space_wolves/SWDetachments11e.gd").charge_reroll_source(unit) != "" \
			or load("res://scripts/codex/space_marines/SMDetachmentsA.gd").charge_reroll_source(unit) != ""  # Codex: Space Marines (11e) Preyslayer (WP-S2); Linebreaker Onslaught (WP-M2a)
	var owner = int(unit.get("owner", 0))
	if owner <= 0:
		return false
	if player_has_detachment(owner, "Blitz Brigade") and unit.get("disembarked_this_phase", false) and _unit_has_keyword(unit, "ORKS"):
		return true
	if player_has_detachment(owner, "Rollin' Deff") and _unit_is_thundering_wagon(unit):
		return true
	return false

func unit_has_detachment_advance_reroll(unit: Dictionary) -> bool:
	"""Blitz Brigade — Eager for the Fight: re-roll Advance rolls for ORKS
	units that disembarked from a Transport this turn."""
	# 10e rule (the 11e Blitz Brigade rule changes WAGON advance rolls to a 6 — WP-O34).
	if GameConstants.edition >= 11:
		return false
	var owner = int(unit.get("owner", 0))
	if owner <= 0:
		return false
	return player_has_detachment(owner, "Blitz Brigade") \
		and unit.get("disembarked_this_phase", false) and _unit_has_keyword(unit, "ORKS")

func get_thundering_wagons_advance_override(unit: Dictionary) -> int:
	"""Rollin' Deff — Thundering Wagons: the rigs do not roll for Advance —
	their Advance is a flat 6". Returns 0 when not applicable."""
	var owner = int(unit.get("owner", 0))
	if owner <= 0:
		return 0
	if not player_has_detachment(owner, "Rollin' Deff"):
		return 0
	return 6 if _unit_is_thundering_wagon(unit) else 0

func unit_can_turbo_boost(unit: Dictionary) -> bool:
	"""Speedwaaagh! — Turbo Boostas: when a SPEED FREEKS or TRUKK unit
	(excluding AIRCRAFT) Advances, it can use its turbo instead of rolling —
	Move becomes a flat 24" this phase, ranged weapons gain ASSAULT until end
	of turn and the unit cannot declare a charge. The one-straight-line /
	no-pivot movement rider is not enforced (documented simplification)."""
	var owner = int(unit.get("owner", 0))
	if owner <= 0:
		return false
	if not player_has_detachment(owner, "Speedwaaagh!"):
		return false
	if _unit_has_keyword(unit, "AIRCRAFT"):
		return false
	return _unit_has_keyword(unit, "SPEED FREEKS") or _unit_has_keyword(unit, "TRUKK")

func process_try_dat_button(unit_id: String, scope: String) -> void:
	"""Dread Mob — Try Dat Button!: when a Mek / Orks Walker / Grots Vehicle
	unit is selected to shoot (scope "ranged") or fight (scope "melee"), roll
	one D6 for the Button Effect — 1-2: SUSTAINED HITS 1; 3-4: LETHAL HITS;
	5-6: +2 AP (the 40kdc dataset's flatten of the Critical-Wound-only rider,
	documented). Press It Fasta!: the bearer's unit rolls one additional D6
	and gains both Button Effects (duplicates add nothing). Effects last
	until the end of the phase (cleared by the phase exit hooks). The rules'
	optional choose-instead-of-rolling path (which adds HAZARDOUS) is not
	offered — the roll is always taken."""
	# 10e Dread Mob rule; the 11e Try Dat Button! is a window choice (OrkDetachments11e, WP-O34).
	if GameConstants.edition >= 11:
		return
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return
	var owner = int(unit.get("owner", 0))
	if owner <= 0 or not player_has_detachment(owner, "Dread Mob"):
		return
	if not (_unit_has_keyword(unit, "MEK") or _unit_has_keyword(unit, "WALKER")
			or (_unit_has_keyword(unit, "GROTS") and _unit_has_keyword(unit, "VEHICLE"))):
		return
	if not unit.has("flags"):
		unit["flags"] = {}
	# Re-selecting the same unit in the same phase keeps the first result.
	if unit["flags"].get("try_dat_rolled_this_phase", false):
		return
	var rng = RulesEngine.make_rng()
	var dice_count = 2 if _unit_or_attached_has_enhancement(unit, "Press It Fasta!", GameState.state.get("units", {})) else 1
	var results: Array = []
	for _i in range(dice_count):
		results.append(rng.rng.randi_range(1, 6))
	unit["flags"]["try_dat_rolled_this_phase"] = true
	var granted: Array = []
	for roll in results:
		if roll <= 2:
			unit["flags"]["effect_try_dat_sustained_%s" % scope] = true
			granted.append("SUSTAINED HITS 1")
		elif roll <= 4:
			unit["flags"]["effect_try_dat_lethal_%s" % scope] = true
			granted.append("LETHAL HITS")
		else:
			unit["flags"]["effect_try_dat_ap2"] = true
			granted.append("+2 AP")
	print("FactionAbilityManager: Try Dat Button! — %s rolled %s -> %s (%s)%s" % [
		unit_id, str(results), str(granted), scope, " [Press It Fasta!]" if dice_count == 2 else ""])
	var gel = get_node_or_null("/root/GameEventLog")
	if gel and gel.has_method("add_player_entry"):
		gel.add_player_entry(owner, "Try Dat Button!: %s rolled %s — %s" % [
			unit.get("meta", {}).get("name", unit_id), str(results), ", ".join(PackedStringArray(granted))])

func clear_try_dat_flags(scope: String) -> void:
	"""Clear Try Dat Button! Button Effects at the end of the phase."""
	for uid in GameState.state.get("units", {}):
		var uflags = GameState.state["units"][uid].get("flags", {})
		if uflags.get("try_dat_rolled_this_phase", false):
			uflags.erase("try_dat_rolled_this_phase")
			uflags.erase("effect_try_dat_sustained_%s" % scope)
			uflags.erase("effect_try_dat_lethal_%s" % scope)
			uflags.erase("effect_try_dat_ap2")
			print("FactionAbilityManager: Try Dat Button! effects on %s expired (end of phase)" % uid)

# ============================================================================
# LISSEN 'ERE — TAKTIKS (Taktikal Brigade detachment rule)
# ============================================================================
# Once per battle round each Boss Snikrot, Mek and Warboss model can issue a
# Taktik to a friendly ORKS unit within 6" (18" for Orks Infantry/Mounted when
# the issuer bears Gob Boomer). The issuer takes a Leadership test — on a
# failure the receiving unit suffers 1 mortal wound (the Taktik still lands).
# A unit can only receive Taktiks once per battle round and never while
# Battle-shocked; effects last until the start of the owner's next Command
# phase. Not modelled (documented): issuing right after arriving from
# Reserves in the Movement phase, and the suspension of an already-issued
# Taktik while the unit is Battle-shocked.

const TAKTIKS: Dictionary = {
	"Get Stuck In": "Re-roll Charge rolls",
	"Get On Wiv It": "+1 Strength on melee weapons",
	"Sneaky Stalkin'": "Stealth + Benefit of Cover (Infantry/Mounted, not Meganobz)",
	"Shoota Drills": "+1 to ranged Hit rolls (Infantry/Mounted)",
}

func _unit_is_taktik_issuer(unit: Dictionary) -> bool:
	return _unit_has_keyword(unit, "MEK") or _unit_has_keyword(unit, "WARBOSS") \
		or _unit_has_keyword(unit, "BOSS SNIKROT")

func get_taktik_issuers(player: int) -> Array:
	"""Boss Snikrot / Mek / Warboss units of a Taktikal Brigade player that
	have not issued Taktiks this battle round."""
	# 10e Taktikal Brigade rule — the 11e rule is Suspiciously Well Organised (WP-O34).
	if GameConstants.edition >= 11:
		return []
	if not player_has_detachment(player, "Taktikal Brigade"):
		return []
	var round_no = GameState.get_battle_round()
	var out: Array = []
	var units = GameState.state.get("units", {})
	for uid in units:
		var unit = units[uid]
		if int(unit.get("owner", 0)) != player:
			continue
		if not _unit_is_taktik_issuer(unit):
			continue
		if int(unit.get("flags", {}).get("taktik_issued_round", 0)) == round_no:
			continue
		var has_alive := false
		for m in unit.get("models", []):
			if m.get("alive", true):
				has_alive = true
				break
		if has_alive:
			out.append(uid)
	return out

func _taktik_range_inches(issuer: Dictionary, target: Dictionary) -> float:
	# Gob Boomer: 18" instead of 6" for Orks Infantry/Mounted targets.
	if _unit_or_attached_has_enhancement(issuer, "Gob Boomer", GameState.state.get("units", {})) \
			and (_unit_has_keyword(target, "INFANTRY") or _unit_has_keyword(target, "MOUNTED")):
		return 18.0
	return 6.0

func can_issue_taktik(issuer_id: String, taktik: String, target_id: String) -> Dictionary:
	"""Full validation for issuing a Taktik. Returns {can: bool, reason}."""
	if GameConstants.edition >= 11:  # 10e Lissen 'Ere — not part of the 11e Taktikal Brigade (WP-O34)
		return {"can": false, "reason": "Lissen 'Ere Taktiks are a 10th-edition Taktikal Brigade rule"}
	var units = GameState.state.get("units", {})
	var issuer = units.get(issuer_id, {})
	var target = units.get(target_id, {})
	if issuer.is_empty() or target.is_empty():
		return {"can": false, "reason": "issuer or target not found"}
	var player = int(issuer.get("owner", 0))
	if not player_has_detachment(player, "Taktikal Brigade"):
		return {"can": false, "reason": "Lissen 'Ere requires the Taktikal Brigade detachment"}
	if not TAKTIKS.has(taktik):
		return {"can": false, "reason": "unknown Taktik '%s'" % taktik}
	if not _unit_is_taktik_issuer(issuer):
		return {"can": false, "reason": "only Boss Snikrot, Mek and Warboss models issue Taktiks"}
	var round_no = GameState.get_battle_round()
	if int(issuer.get("flags", {}).get("taktik_issued_round", 0)) == round_no:
		return {"can": false, "reason": "%s already issued Taktiks this battle round" % issuer_id}
	if int(target.get("owner", 0)) != player:
		return {"can": false, "reason": "Taktiks are issued to friendly units"}
	if not _unit_has_keyword(target, "ORKS"):
		return {"can": false, "reason": "Taktiks are issued to ORKS units"}
	if int(target.get("flags", {}).get("taktik_received_round", 0)) == round_no:
		return {"can": false, "reason": "%s already received Taktiks this battle round" % target_id}
	if target.get("flags", {}).get("battle_shocked", false):
		return {"can": false, "reason": "Taktiks cannot be issued to Battle-shocked units"}
	# Taktik-specific unit scoping (the effects only touch Infantry/Mounted
	# models — refused at unit granularity, documented approximation)
	if taktik in ["Sneaky Stalkin'", "Shoota Drills"] \
			and not (_unit_has_keyword(target, "INFANTRY") or _unit_has_keyword(target, "MOUNTED")):
		return {"can": false, "reason": "%s only affects Infantry/Mounted units" % taktik}
	if taktik == "Sneaky Stalkin'" and _unit_has_keyword(target, "MEGANOBZ"):
		return {"can": false, "reason": "Sneaky Stalkin' excludes Meganobz"}
	# Range (6", 18" via Gob Boomer for Infantry/Mounted)
	var range_in = _taktik_range_inches(issuer, target)
	var in_range := false
	if issuer_id == target_id:
		in_range = true  # an issuer may take its own Taktik
	else:
		var range_px = Measurement.inches_to_px(range_in)
		for m in issuer.get("models", []):
			if not m.get("alive", true) or m.get("position") == null:
				continue
			for tm in target.get("models", []):
				if not tm.get("alive", true) or tm.get("position") == null:
					continue
				if Measurement.model_to_model_distance_px(m, tm) <= range_px:
					in_range = true
					break
			if in_range:
				break
	if not in_range:
		return {"can": false, "reason": "%s is not within %.0f\" of %s" % [target_id, range_in, issuer_id]}
	return {"can": true, "reason": ""}

func get_eligible_taktik_targets(issuer_id: String, taktik: String) -> Array:
	"""Friendly ORKS units this issuer could issue the given Taktik to."""
	var out: Array = []
	var units = GameState.state.get("units", {})
	var issuer = units.get(issuer_id, {})
	for uid in units:
		if int(units[uid].get("owner", -1)) != int(issuer.get("owner", 0)):
			continue
		if can_issue_taktik(issuer_id, taktik, uid).can:
			out.append(uid)
	return out

func issue_taktik(issuer_id: String, taktik: String, target_id: String = "") -> Dictionary:
	"""Issue a Taktik. With no target given, the nearest eligible friendly
	ORKS unit is picked. The issuer's Leadership test failure deals 1 mortal
	wound to the receiving unit but the Taktik still applies."""
	var units = GameState.state.get("units", {})
	if target_id == "":
		var best := ""
		var best_d := INF
		var issuer_u = units.get(issuer_id, {})
		for uid in get_eligible_taktik_targets(issuer_id, taktik):
			if uid == issuer_id and best != "":
				continue
			var d := 0.0 if uid == issuer_id else INF
			for m in issuer_u.get("models", []):
				if not m.get("alive", true) or m.get("position") == null:
					continue
				for tm in units.get(uid, {}).get("models", []):
					if not tm.get("alive", true) or tm.get("position") == null:
						continue
					d = minf(d if d != INF else INF, Measurement.model_to_model_distance_px(m, tm))
			if d < best_d:
				best_d = d
				best = uid
		target_id = best
	if target_id == "":
		return {"success": false, "error": "no eligible Taktik target in range"}
	var check = can_issue_taktik(issuer_id, taktik, target_id)
	if not check.can:
		return {"success": false, "error": check.reason}
	var issuer = units[issuer_id]
	var target = units[target_id]
	var player = int(issuer.get("owner", 0))
	var round_no = GameState.get_battle_round()
	# The issuer's Leadership test — 1 mortal wound to the receiving unit on
	# a failure (the Taktik still lands).
	var CommandPhaseScript = load("res://phases/CommandPhase.gd")
	var ld = CommandPhaseScript._get_effective_leadership(issuer_id)
	var rng = RulesEngine.make_rng()
	var d1 = rng.rng.randi_range(1, 6)
	var d2 = rng.rng.randi_range(1, 6)
	var passed = (d1 + d2) >= ld
	if not passed:
		var mw = RulesEngine.apply_mortal_wounds_to_unit(target_id, 1, GameState.create_snapshot())
		if not mw.get("diffs", []).is_empty():
			GameState.apply_state_changes(mw.diffs)
	# Apply the Taktik until the start of this player's next Command phase.
	if not target.has("flags"):
		target["flags"] = {}
	var tflags = target["flags"]
	match taktik:
		"Get Stuck In":
			tflags[EffectPrimitivesData.FLAG_REROLL_CHARGE] = true
		"Get On Wiv It":
			tflags["effect_taktik_melee_strength"] = 1
		"Sneaky Stalkin'":
			tflags[EffectPrimitivesData.FLAG_STEALTH] = true
			tflags[EffectPrimitivesData.FLAG_COVER] = true
		"Shoota Drills":
			tflags[EffectPrimitivesData.FLAG_PLUS_ONE_HIT_RANGED] = true
	tflags["taktik_active"] = taktik
	tflags["taktik_from_player"] = player
	tflags["taktik_received_round"] = round_no
	if not issuer.has("flags"):
		issuer["flags"] = {}
	issuer["flags"]["taktik_issued_round"] = round_no
	print("FactionAbilityManager: Lissen 'Ere — %s issues '%s' to %s (Ld test %d+%d vs %d: %s)" % [
		issuer_id, taktik, target_id, d1, d2, ld, "passed" if passed else "FAILED — 1 mortal wound"])
	var gel = get_node_or_null("/root/GameEventLog")
	if gel and gel.has_method("add_player_entry"):
		gel.add_player_entry(player, "Lissen 'Ere: %s issues %s to %s%s" % [
			issuer.get("meta", {}).get("name", issuer_id), taktik,
			target.get("meta", {}).get("name", target_id),
			"" if passed else " (Ld test failed — 1 mortal wound)"])
	return {"success": true, "taktik": taktik, "target_unit_id": target_id, "ld_passed": passed, "rolls": [d1, d2]}

func _clear_taktik_effects(player: int) -> void:
	"""Taktiks last until the start of the issuing player's next Command phase."""
	for uid in GameState.state.get("units", {}):
		var flags = GameState.state["units"][uid].get("flags", {})
		if int(flags.get("taktik_from_player", 0)) != player:
			continue
		match str(flags.get("taktik_active", "")):
			"Get Stuck In":
				flags.erase(EffectPrimitivesData.FLAG_REROLL_CHARGE)
			"Get On Wiv It":
				flags.erase("effect_taktik_melee_strength")
			"Sneaky Stalkin'":
				flags.erase(EffectPrimitivesData.FLAG_STEALTH)
				flags.erase(EffectPrimitivesData.FLAG_COVER)
			"Shoota Drills":
				flags.erase(EffectPrimitivesData.FLAG_PLUS_ONE_HIT_RANGED)
		flags.erase("taktik_active")
		flags.erase("taktik_from_player")
		print("FactionAbilityManager: Taktik on %s expired (Player %d's Command phase)" % [uid, player])

# ---- HERE BE LOOT (Orks — Freebooter Krew) (OA-1) ----

func is_loot_objective_available(player: int) -> bool:
	"""Check if loot objective selection is needed (new battle round, Freebooter Krew player)."""
	if not player_has_detachment(player, "Freebooter Krew"):
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

	if not player_has_detachment(player, "Freebooter Krew"):
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

	# OBJ-GAP-2: resolve the objective at this position and use MissionManager's
	# shared predicate (base touching the hosting area of an 11e terrain
	# objective). The marker-radius test below is the headless fallback.
	var mm = Engine.get_main_loop().root.get_node_or_null("/root/MissionManager") if Engine.get_main_loop() != null else null
	if mm != null and mm.has_method("model_in_objective_range"):
		for obj in board.get("board", {}).get("objectives", []):
			var op = obj.get("position", null)
			if op is Dictionary:
				op = Vector2(op.get("x", 0), op.get("y", 0))
			if op is Vector2 and op.distance_to(obj_vec) < 1.0:
				for model in unit.get("models", []):
					if model.get("alive", true) and model.get("position", null) != null \
							and mm.model_in_objective_range(model, obj):
						return true
				return false

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
	if not player_has_detachment(player, "Freebooter Krew"):
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
	combined_unit_id is the bodyguard unit the bearer is attached to (or bearer_id if standalone).
	Matching normalizes typographic apostrophes (Mork’s Kunnin’ vs Mork's Kunnin')
	and accepts both String and {name: ...} enhancement entries."""
	var target_norm = enhancement_name.replace("’", "'")
	var units = GameState.state.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue
		var enhancements = unit.get("meta", {}).get("enhancements", [])
		var has_it = false
		for enh in enhancements:
			var enh_name = ""
			if enh is String:
				enh_name = enh
			elif enh is Dictionary:
				enh_name = str(enh.get("name", ""))
			if enh_name.replace("’", "'") == target_norm:
				has_it = true
				break
		if has_it:
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
	if not player_has_detachment(player, "Freebooter Krew"):
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
	# Issue #329: route through RNGService so static test_mode_seed applies
	var rng = RulesEngine.make_rng()
	var d3_roll = rng.rng.randi_range(1, 3)

	# Apply mortal wounds
	var board = GameState.create_snapshot()
	# rng: Feel No Pain vs these mortal wounds is rolled (WP-C3 Aegis of the Emperor).
	var mw_result = RulesEngine.apply_mortal_wounds(target_unit_id, d3_roll, board, rng)

	# Apply damage diffs
	if mw_result.diffs.size() > 0:
		PhaseManager.apply_state_changes(mw_result.diffs)

	# Remove Battle-shocked status from target
	var target_unit = GameState.state.get("units", {}).get(target_unit_id, {})
	if target_unit.has("flags"):
		target_unit["flags"]["battle_shocked"] = false

	# Also remove Battle-shocked from any attached characters
	# 19.01: the whole Attached unit stops being Battle-shocked — walk the same
	# group MissionManager's OC read uses (RulesEngine linkage, both sides), so
	# a leader linked only by its attached_to back-pointer (or the bodyguard,
	# when the flagged dict picked was the leader's) is cleared too. A fresh
	# array: get_attached_characters returns the live attachment list.
	var attached_chars: Array = GameState.get_attached_characters(target_unit_id).duplicate()
	var dk_head_id = RulesEngine.attached_unit_target_id(target_unit_id, GameState.state)
	for dk_id in RulesEngine.attached_unit_component_ids(dk_head_id, GameState.state):
		if str(dk_id) != target_unit_id and not attached_chars.has(str(dk_id)):
			attached_chars.append(str(dk_id))
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
	# Issue #329: route through RNGService so static test_mode_seed applies
	var rng = RulesEngine.make_rng()
	var d3_roll = rng.rng.randi_range(1, 3)

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

# ---- REDEPLOY ENHANCEMENTS ----
# Razgit's Magik Map (25pts, ORKS model): after deployment, select up to 3
# friendly Orks INFANTRY units and redeploy them; any can be placed into
# Strategic Reserves.
# Castellan's Mark (Codex: Adeptus Custodes 11e, Guardians of the Throne,
# WP-C46): "When both players have deployed their armies, you can redeploy up
# to three friendly ADEPTUS CUSTODES units. When doing so, you can set those
# units up in strategic reserves, regardless of how many units are already in
# strategic reserves." (The 10e Silent Hunters Encircling Hunter is gone.)
# Both share the helpers below (historically named after Razgit) and the same
# per-player 3-slot counter; a player can never own both (different factions).

const REDEPLOY_ENHANCEMENTS = [
	{"name": "Razgit's Magik Map", "keywords": ["ORKS", "INFANTRY"], "exclude_bearer": true},
	{"name": "Castellan's Mark", "keywords": ["ADEPTUS CUSTODES"]},
]

func get_redeploy_enhancement(player: int) -> Dictionary:
	"""Return the redeploy enhancement entry the player owns ({} if none)."""
	# WP-O5 Kaptin's Hat (Codex: Orks, Wreckas): up to three ORKS INFANTRY units.
	var o5_hat: Dictionary = load("res://scripts/codex/orks/OrkEnhancements11e.gd").redeploy_enhancement(player)
	if not o5_hat.is_empty():
		return o5_hat
	# Codex: Space Marines (11e) Hunter's Guile / Chariots of the Storm (SWEnhancements11e.gd, WP-S2).
	if GameConstants.edition >= 11:
		var sw11e_rd: Dictionary = load("res://scripts/codex/space_wolves/SWEnhancements11e.gd").redeploy_enhancement(player)
		if not sw11e_rd.is_empty():
			return sw11e_rd
		# WP-M2b Cyber-familiar (Codex: Space Marines 11e, Tacticus Firestorm Force): up to three ADEPTUS ASTARTES INFANTRY units.
		var sm11e_rd: Dictionary = load("res://scripts/codex/space_marines/SMDetachmentsB.gd").redeploy_enhancement(player)
		if not sm11e_rd.is_empty():
			return sm11e_rd
		# WP-M4c STRATEGIUM COMMAND (Wardens of Ultramar datasheet ability): up to three ADEPTUS ASTARTES units.
		var smc_rd: Dictionary = load("res://scripts/codex/space_marines/SMAbilitiesC.gd").redeploy_entry(player)
		if not smc_rd.is_empty():
			return smc_rd
	for entry in REDEPLOY_ENHANCEMENTS:
		if has_enhancement(player, entry.name):
			return entry
	return {}

func get_redeploy_enhancement_name(player: int) -> String:
	"""Display name of the player's redeploy enhancement ("" if none)."""
	return get_redeploy_enhancement(player).get("name", "")

func has_razgit_magik_map(player: int) -> bool:
	"""Check if a player has a redeploy enhancement (Razgit's Magik Map or
	Encircling Hunter)."""
	return not get_redeploy_enhancement(player).is_empty()

func get_razgit_eligible_units(player: int) -> Array:
	"""Get all units eligible for the player's redeploy enhancement (Orks
	INFANTRY for Razgit's Magik Map, ANATHEMA PSYKANA INFANTRY for Encircling
	Hunter)."""
	var entry = get_redeploy_enhancement(player)
	if entry.is_empty():
		return []

	var bearer_info = _find_enhancement_bearer(player, entry.name)
	if bearer_info.is_empty() and entry.has("bearer_id"):
		bearer_info = {"bearer_id": str(entry.bearer_id)}  # WP-M4c: a datasheet ability (Strategium Command), not an enhancement
	if bearer_info.is_empty():
		return []

	var eligible = []
	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != player:
			continue
		# Skip the bearer's own unit (bearer doesn't redeploy themselves) —
		# Razgit's Magik Map only; Castellan's Mark's "up to three friendly
		# ADEPTUS CUSTODES units" includes the bearer's (WP-C46 ruling).
		if unit_id == bearer_info.bearer_id and entry.get("exclude_bearer", false):
			continue
		# Must be deployed. status may be an int enum (live game) or a String
		# (freshly applied army JSON) — comparing int to String is a runtime
		# error in GDScript 4, so branch on the type.
		if not _status_is_deployed(unit.get("status", 0)):
			continue
		# Must match the enhancement's keyword filter
		var matches_keywords = true
		for kw in entry.keywords:
			if not _unit_has_keyword(unit, kw):
				matches_keywords = false
				break
		if not matches_keywords:
			continue
		# "any_keywords": one of them (Codex: Space Marines (11e) Hunter's Guile —
		# Blood Claws / Thunderwolf Cavalry / Wulfen units, WP-S2).
		if entry.has("any_keywords"):
			var any_kw := false
			for akw in entry.any_keywords:
				if _unit_has_keyword(unit, str(akw)):
					any_kw = true
			if not any_kw:
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
	"""Get how many enhancement redeployments remain (max 3)."""
	return 3 - _razgit_redeploys_used.get(str(player), 0)

func mark_razgit_redeploy_used(player: int) -> void:
	"""Mark one enhancement redeployment as used."""
	var pk = str(player)
	_razgit_redeploys_used[pk] = _razgit_redeploys_used.get(pk, 0) + 1
	print("FactionAbilityManager: %s — player %d used redeploy %d/3" % [
		get_redeploy_enhancement_name(player), player, _razgit_redeploys_used[pk]])

func is_razgit_redeploy_available(player: int) -> bool:
	"""Check if enhancement redeployment slots are still available."""
	return has_razgit_magik_map(player) and get_razgit_redeploys_remaining(player) > 0

# ============================================================================
# GREEN TIDE HELPERS
# ============================================================================

static func unit_counts_as_10(unit: Dictionary) -> bool:
	"""Green Tide: true if the unit has 10+ alive models OR an effect that makes
	it count as such (Raucous Warcaller while leading, BRAGGIN' RIGHTS)."""
	if unit.get("flags", {}).get(EffectPrimitivesData.FLAG_COUNTS_AS_10, false):
		return true
	var alive := 0
	for m in unit.get("models", []):
		if m.get("alive", true):
			alive += 1
	return alive >= 10

static func _unit_or_attached_has_enhancement(unit: Dictionary, enh_name: String, units: Dictionary) -> bool:
	"""True if the unit itself, or any character attached to it, carries the enhancement."""
	var target_norm = enh_name.replace("’", "'")
	var to_check: Array = [unit]
	for char_id in unit.get("attachment_data", {}).get("attached_characters", []):
		var ch = units.get(str(char_id), {})
		if not ch.is_empty():
			to_check.append(ch)
	for u in to_check:
		for enh in u.get("meta", {}).get("enhancements", []):
			var n = ""
			if enh is String:
				n = enh
			elif enh is Dictionary:
				n = str(enh.get("name", ""))
			if n.replace("’", "'") == target_norm:
				return true
	return false


# ============================================================================
# DA BIG HUNT — PREY (detachment rule)
# ============================================================================
# "At the start of your Command phase, select one MONSTER, VEHICLE or
# CHARACTER unit from your opponent's army. Until the start of your next
# Command phase, that enemy unit is your Prey:
#  - Each time a Beast Snagga unit from your army declares a charge that
#    includes your Prey as one of the targets, you can re-roll the Charge roll.
#  - Each time a BEAST SNAGGA model from your army makes an attack that
#    targets your Prey, improve the Armour Penetration characteristic of that
#    attack by 1."
# The marker lives on the ENEMY unit as flags.is_prey_of_<player> so it
# survives save/load and is readable from RulesEngine's static resolvers.
# Selection is automatic (nearest eligible enemy to a friendly BEAST SNAGGA
# unit, keeping the previous Prey while it lives) — override via set_prey().

func get_prey_unit_id(player: int) -> String:
	"""Return the unit id currently marked as this player's Prey, or ""."""
	var flag_key = "is_prey_of_%d" % player
	var units = GameState.state.get("units", {})
	for uid in units:
		if units[uid].get("flags", {}).get(flag_key, false):
			return uid
	return ""

static func unit_is_prey_of(unit: Dictionary, player: int) -> bool:
	return unit.get("flags", {}).get("is_prey_of_%d" % player, false)

func _is_valid_prey_choice(unit: Dictionary, player: int) -> bool:
	"""Eligible Prey: an enemy MONSTER, VEHICLE or CHARACTER unit with at
	least one alive model."""
	if unit.is_empty() or int(unit.get("owner", 0)) == player or int(unit.get("owner", 0)) == 0:
		return false
	if not (RulesEngine.unit_has_keyword(unit, "MONSTER")
			or RulesEngine.unit_has_keyword(unit, "VEHICLE")
			or RulesEngine.unit_has_keyword(unit, "CHARACTER")):
		return false
	for m in unit.get("models", []):
		if m.get("alive", true):
			return true
	return false

func set_prey(player: int, enemy_unit_id: String) -> bool:
	"""Mark an enemy unit as this player's Prey (clearing any previous marker).
	Returns false if the unit is not a legal Prey choice."""
	var units = GameState.state.get("units", {})
	var choice = units.get(enemy_unit_id, {})
	if not _is_valid_prey_choice(choice, player):
		print("FactionAbilityManager: set_prey — %s is not a legal Prey for Player %d (needs enemy MONSTER/VEHICLE/CHARACTER with alive models)" % [enemy_unit_id, player])
		return false
	var flag_key = "is_prey_of_%d" % player
	for uid in units:
		if units[uid].get("flags", {}).has(flag_key):
			units[uid]["flags"].erase(flag_key)
	if not choice.has("flags"):
		choice["flags"] = {}
	choice["flags"][flag_key] = true
	print("FactionAbilityManager: Da Big Hunt — %s (%s) is now Player %d's Prey" % [
		enemy_unit_id, choice.get("meta", {}).get("name", enemy_unit_id), player])
	return true

func _select_prey_for_player(player: int) -> void:
	"""Da Big Hunt: (re-)select this player's Prey at the start of their
	Command phase. Keeps the previous Prey while it is still legal; otherwise
	auto-picks the eligible enemy unit nearest to any friendly BEAST SNAGGA
	unit (documented simplification — set_prey() allows a manual override)."""
	var units = GameState.state.get("units", {})
	var current = get_prey_unit_id(player)
	if current != "" and _is_valid_prey_choice(units.get(current, {}), player):
		# Re-assert (refreshes the marker; also covers loaded saves)
		set_prey(player, current)
		return
	var best_id = ""
	var best_dist = INF
	for uid in units:
		var enemy = units[uid]
		if not _is_valid_prey_choice(enemy, player):
			continue
		var d = _min_distance_to_friendly_beast_snagga(enemy, player)
		if best_id == "" or d < best_dist:
			best_id = uid
			best_dist = d
	if best_id == "":
		print("FactionAbilityManager: Da Big Hunt — no eligible enemy MONSTER/VEHICLE/CHARACTER for Player %d's Prey" % player)
		return
	set_prey(player, best_id)

func _min_distance_to_friendly_beast_snagga(enemy_unit: Dictionary, player: int) -> float:
	"""Smallest model-to-model distance (px) from the enemy unit to any of the
	player's BEAST SNAGGA units. INF when no positioned pair exists."""
	var best = INF
	for uid in GameState.state.get("units", {}):
		var friendly = GameState.state["units"][uid]
		if int(friendly.get("owner", 0)) != player:
			continue
		if not RulesEngine.unit_has_keyword(friendly, "BEAST SNAGGA"):
			continue
		for fm in friendly.get("models", []):
			if not fm.get("alive", true) or fm.get("position") == null:
				continue
			for em in enemy_unit.get("models", []):
				if not em.get("alive", true) or em.get("position") == null:
					continue
				best = minf(best, Measurement.model_to_model_distance_px(fm, em))
	return best

static func unit_has_prey_charge_reroll(unit: Dictionary, target_ids: Array, units: Dictionary) -> bool:
	"""Prey rule, first bullet: a BEAST SNAGGA unit charging its owner's Prey
	can re-roll the Charge roll. Also covers DAT ONE'S EVEN BIGGA! (whose
	re-roll clause has the identical condition)."""
	# 10e Da Big Hunt Prey rule — the 11e rule is Da Hunt is On (WP-O34).
	if GameConstants.edition >= 11:
		return false
	if not RulesEngine.unit_has_keyword(unit, "BEAST SNAGGA"):
		return false
	var owner = int(unit.get("owner", 0))
	if owner <= 0:
		return false
	for tid in target_ids:
		if unit_is_prey_of(units.get(str(tid), {}), owner):
			return true
	return false

static func boarding_ramps_charge_bonus(unit: Dictionary, units: Dictionary) -> int:
	"""Boarding Ramps (Rollin' Deff): +1 to Charge rolls for a unit that
	disembarked this turn from the WAGON bearing the enhancement."""
	if not unit.get("disembarked_this_phase", false):
		return 0
	var from_id = str(unit.get("disembarked_from", ""))
	if from_id == "":
		return 0
	var transport = units.get(from_id, {})
	if transport.is_empty():
		return 0
	return 1 if _unit_or_attached_has_enhancement(transport, "Boarding Ramps", units) else 0

func targetin_gizmos_sustained(actor_unit: Dictionary) -> int:
	"""Targetin' Gizmos (Rollin' Deff): the bearer's unit's ranged weapons
	gain SUSTAINED HITS 1 while a Waaagh! is active. (The always-on IGNORES
	COVER half lives in the UnitAbilityManager entry; the BIG-MEK-embarked
	gating is the 40kdc dataset's own documented approximation.)"""
	if not _unit_or_attached_has_enhancement(actor_unit, "Targetin' Gizmos", GameState.state.get("units", {})):
		return 0
	# WP-O5: in a Codex: Orks Blitz Brigade army the codex Targetin' Gizmos
	# applies instead (OrkEnhancements11e: Big Mek embarked; riled up).
	if GameConstants.edition >= 11 and load("res://scripts/codex/orks/OrkEnhancements11e.gd").owns_name(actor_unit, "Targetin' Gizmos"):
		return 0
	return 1 if is_waaagh_active_for_unit(actor_unit) else 0

static func unit_has_s_gt_t_wound_penalty(unit: Dictionary, _units: Dictionary) -> bool:
	"""The effect_minus_wound_s_gt_t flag (IMPERVIOUS): -1 to incoming Wound
	rolls while the attack's Strength exceeds the unit's Toughness. The S>T
	comparison itself happens at the call site
	(RulesEngine.get_s_gt_t_wound_penalty). (WP-O5: the 10e Da Big Hunt
	Surly as a Squiggoth is gone.)"""
	return bool(unit.get("flags", {}).get("effect_minus_wound_s_gt_t", false))

# (WP-O5: the 10e enhancements Skrag Every Stash! (Da Big Hunt), Supa-glowy
# Fing's Command-phase roll (Dread Mob), Brutal But Kunnin' / Speed Makes
# Right CP rolls (Green Tide / Kult of Speed), Big Gob (Bully Boyz) and
# Mork's Kunnin' / Blitzkaptin redeploys are gone: no Codex: Orks detachment
# has them. Same-named codex enhancements live in OrkEnhancements11e.gd.)

func _nearest_visible_enemy_within(unit: Dictionary, player: int, inches: float) -> String:
	"""Nearest enemy unit with an alive model within `inches` of (and visible
	to) an alive model in `unit`. Returns "" when none qualifies."""
	var range_px = Measurement.inches_to_px(inches)
	var tm = get_node_or_null("/root/TerrainManager")
	var best_id := ""
	var best_d := INF
	for uid in GameState.state.get("units", {}):
		var enemy = GameState.state["units"][uid]
		var enemy_owner = int(enemy.get("owner", 0))
		if enemy_owner == player or enemy_owner == 0:
			continue
		for m in unit.get("models", []):
			if not m.get("alive", true) or m.get("position") == null:
				continue
			for em in enemy.get("models", []):
				if not em.get("alive", true) or em.get("position") == null:
					continue
				var d = Measurement.model_to_model_distance_px(m, em)
				if d > range_px or d >= best_d:
					continue
				if tm != null and tm.has_method("model_visible_11e") and not tm.model_visible_11e(m, em):
					continue
				best_d = d
				best_id = uid
	return best_id

func _grant_bonus_cp(player: int, source: String, roll: int, bonus: int) -> void:
	var pk = str(player)
	var players = GameState.state.get("players", {})
	if players.has(pk):
		players[pk]["cp"] = int(players[pk].get("cp", 0)) + 1
		GameState.record_bonus_cp_gained(player, 1)
		print("FactionAbilityManager: %s — rolled %d+%d, player %d gains 1 CP" % [source, roll, bonus, player])
		var game_event_log = get_node_or_null("/root/GameEventLog")
		if game_event_log:
			game_event_log.add_player_entry(player, "%s: rolled %d — gained 1 CP!" % [source, roll + bonus])

func _unit_within_inches_of_enemy(unit: Dictionary, player: int, inches: float) -> bool:
	var range_px = Measurement.inches_to_px(inches)
	for uid in GameState.state.get("units", {}):
		var enemy = GameState.state["units"][uid]
		if int(enemy.get("owner", 0)) == player:
			continue
		for m in unit.get("models", []):
			if not m.get("alive", true) or m.get("position") == null:
				continue
			for em in enemy.get("models", []):
				if not em.get("alive", true) or em.get("position") == null:
					continue
				if Measurement.model_to_model_distance_px(m, em) <= range_px:
					return true
	return false

# ============================================================================
# FORCED BATTLE-SHOCK TESTS (Big Gob, SQUIG FLINGIN', Supa-glowy Fing)
# ============================================================================

func force_battle_shock_test(unit_id: String, roll_modifier: int = 0, source: String = "") -> Dictionary:
	"""Roll 2D6 (+modifier) against the unit's effective Leadership; the unit
	becomes Battle-shocked on a failure. Out-of-Command-phase tests forced by
	Ork abilities/stratagems."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return {"success": false, "error": "unit not found"}
	var CommandPhaseScript = load("res://phases/CommandPhase.gd")
	var ld = CommandPhaseScript._get_effective_leadership(unit_id)
	# MOB MENTALITY (Codex: Orks 11e): "That unit's battle-shock rolls are
	# automatically successful" for the rest of the phase.
	if unit.get("flags", {}).get("ork11e_mob_mentality", false):
		print("FactionAbilityManager: %s — forced Battle-shock test for %s AUTO-PASSED (MOB MENTALITY)" % [source, unit_id])
		return {"success": true, "passed": true, "auto_passed": true, "total": 0, "leadership": ld, "dice": [], "diffs": []}
	var rng = RulesEngine.make_rng()
	var d1 = rng.rng.randi_range(1, 6)
	var d2 = rng.rng.randi_range(1, 6)
	var total = d1 + d2 + roll_modifier
	var passed = total >= ld
	# WP-M2b Tempered in Battle (Aura) (Codex: Space Marines 11e): a failed leadership roll is re-rolled (free, always taken).
	var sm11e_tb_src: String = str(load("res://scripts/codex/space_marines/SMDetachmentsB.gd").battle_shock_reroll_source(unit_id)) if (not passed and GameConstants.edition >= 11) else ""
	if sm11e_tb_src != "":
		var tb_old: int = total
		d1 = rng.rng.randi_range(1, 6)
		d2 = rng.rng.randi_range(1, 6)
		total = d1 + d2 + roll_modifier
		passed = total >= ld
		print("FactionAbilityManager: %s — %s re-rolls the battle-shock roll %d -> %d vs Ld %d" % [sm11e_tb_src, unit_id, tb_old, total, ld])
	# State diffs of the result (applied here as before; returned so callers
	# that build an action result can record them for replay / network).
	var shock_diffs: Array = []
	if not passed:
		if not unit.has("flags"):
			unit["flags"] = {}
		unit["flags"]["battle_shocked"] = true
		shock_diffs.append({"op": "set", "path": "units.%s.flags.battle_shocked" % unit_id, "value": true})
		# An Attached unit is battle-shocked as one unit (its characters too).
		for char_id in GameState.get_attached_characters(unit_id):
			var char_unit = GameState.state.get("units", {}).get(char_id, {})
			if not char_unit.is_empty():
				if not char_unit.has("flags"):
					char_unit["flags"] = {}
				char_unit["flags"]["battle_shocked"] = true
				shock_diffs.append({"op": "set", "path": "units.%s.flags.battle_shocked" % char_id, "value": true})
	print("FactionAbilityManager: %s — forced Battle-shock test for %s: %d+%d%+d=%d vs Ld %d -> %s" % [
		source if source != "" else "Forced test", unit_id, d1, d2, roll_modifier, total, ld,
		"PASSED" if passed else "FAILED (battle-shocked)"])
	var game_event_log = get_node_or_null("/root/GameEventLog")
	if game_event_log:
		# LIVE-10: the unique display name ("Custodian Guard Epsilon"), not the
		# datasheet name — two units of the same datasheet must be told apart.
		var unit_name = GameState.get_unit_display_name(unit_id)
		if unit_name == "":
			unit_name = unit.get("meta", {}).get("name", unit_id)
		game_event_log.add_player_entry(int(unit.get("owner", 0)),
			"%s: %s takes a Battle-shock test (%d vs Ld %d) — %s%s" % [
				source, unit_name, total, ld, "passed" if passed else "FAILED",
				(" (re-rolled: %s)" % sm11e_tb_src) if sm11e_tb_src != "" else ""])  # WP-M2b Tempered in Battle
	return {"success": true, "passed": passed, "total": total, "leadership": ld, "dice": [d1, d2], "diffs": shock_diffs, "rerolled_by": sm11e_tb_src}

static func _status_is_deployed(status) -> bool:
	"""Unit status can be an int enum (live game) or a String (army JSON that
	has not been through a save round-trip). int != String is a runtime error
	in GDScript 4, so compare per-type."""
	if typeof(status) == TYPE_STRING:
		return status == "DEPLOYED"
	return int(status) == GameStateData.UnitStatus.DEPLOYED

# ============================================================================
# PHASE LIFECYCLE
# ============================================================================

# ============================================================================
# MARTIAL KA'TAH — the 11e codex rule lives in scripts/codex/custodes/
# CustodesKatah.gd (WP-C3); this is only the "has the ability" check the
# detachment code below uses.
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

# ============================================================================
# PHASE LIFECYCLE
# ============================================================================

func on_command_phase_start(player: int) -> void:
	"""Called at the start of each Command Phase. Detects abilities and clears old targets."""
	detect_faction_abilities(player)

	# Detect detachment (P2-27)
	detect_player_detachment(player)

	# Deactivate Waaagh! if it was active (it lasts "until the start of your next Command phase")
	# 11e War Cry: riled up "until the end of the next turn" — either player's (WP-O34).
	if GameConstants.edition >= 11:
		Ork11eArmyRules.expire_war_cry_if_due()
	elif _waaagh_active.get(str(player), false):
		deactivate_waaagh(player)

	# OA-46: Clear Plant the Waaagh! Banner per-unit effects (lasts until start of next battle round)
	_clear_plant_waaagh_banner_effects(player)

	# Clear previous Combat Doctrine effects (they last until next Command phase)
	_clear_doctrine_effects(player)

	# Apply passive detachment abilities (Get Stuck In)
	# (10e rules — at 11e the Codex: Orks detachment rules are read live by
	# OrkDetachments11e, WP-O34.)
	if player_has_detachment(player, "War Horde") and GameConstants.edition < 11:
		_apply_get_stuck_in(player)

	# Green Tide — Mob Mentality: refresh the BOYZ 6+/5+ invulnerable save
	if player_has_detachment(player, "Green Tide") and GameConstants.edition < 11:
		_apply_mob_mentality(player)

	# 11e detachment keyword grants (Dread Mob Gretchin / Taktikal Stormboyz
	# gain BATTLELINE)
	if GameConstants.edition >= 11:
		Ork11eDetachments.apply_keyword_grants(player)  # Kult of Speed / Taktikal Brigade / Runt Swarm BATTLELINE (WP-O34)
	else:
		for det_name in get_player_detachments(player):
			_apply_detachment_keyword_grants(player, str(det_name))

	# Clear loot objective from previous round (Freebooter Krew — OA-1)
	# Loot objective resets each battle round; selection happens via action in CommandPhase
	if player_has_detachment(player, "Freebooter Krew"):
		_clear_loot_objective(player)
		print("FactionAbilityManager: Player %d has Freebooter Krew — awaiting loot objective selection" % player)

	# Da Big Hunt — Prey (detachment rule): (re-)select an enemy MONSTER/
	# VEHICLE/CHARACTER unit as this player's Prey until their next Command
	# phase.
	if player_has_detachment(player, "Da Big Hunt") and GameConstants.edition < 11:  # 10e Prey (WP-O34: 11e is Da Hunt is On)
		_select_prey_for_player(player)

	# Lissen 'Ere — Taktiks (Taktikal Brigade): effects last until the start of
	# this player's next Command phase, so expire them now before new ones are
	# issued this phase.
	_clear_taktik_effects(player)

	# Bionik Workshop — resolve on first Command Phase (start of battle) (OA-2)
	if player_has_detachment(player, "Freebooter Krew") and not _bionik_workshop_resolved:
		if has_enhancement(player, "Bionik Workshop"):
			var bw_result = resolve_bionik_workshop(player)
			if bw_result.success:
				print("FactionAbilityManager: Bionik Workshop resolved for player %d — %s" % [player, bw_result.bonus_description])
		_bionik_workshop_resolved = true


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
		"plant_waaagh_banner_used": _plant_waaagh_banner_used.duplicate(true),
		# Da Boss Is Watchin' (Bully Boyz): second-Waaagh! latch
		"boss_watchin_used": _boss_watchin_used.duplicate(true)
	}

func load_state(data: Dictionary) -> void:
	"""Restore state from save data."""
	_active_effects = data.get("active_effects", {"1": {}, "2": {}})
	_player_abilities = data.get("player_abilities", {"1": [], "2": []})
	_waaagh_used = data.get("waaagh_used", {"1": false, "2": false})
	_waaagh_active = data.get("waaagh_active", {"1": false, "2": false})
	_boss_watchin_used = data.get("boss_watchin_used", {"1": false, "2": false})
	# Detachment ability state (P2-27)
	_player_detachment = data.get("player_detachment", {"1": "", "2": ""})
	_doctrines_used = data.get("doctrines_used", {"1": [], "2": []})
	_active_doctrine = data.get("active_doctrine", {"1": "", "2": ""})
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
