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

# ============================================================================
# CONSTANTS
# ============================================================================

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
		# Advance and charge eligibility
		unit["flags"]["effect_advance_and_charge"] = true

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
			# Only clear invuln if it was the Waaagh! 5+ (don't clobber other sources)
			if flags.get("effect_invuln", 0) == 5:
				flags.erase("effect_invuln")
			var unit_name = unit.get("meta", {}).get("name", unit_id)
			print("FactionAbilityManager: Waaagh! effects cleared from %s (%s)" % [unit_name, unit_id])

func _unit_has_waaagh_ability(unit: Dictionary) -> bool:
	"""Check if a unit has the Waaagh! faction ability."""
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")
		if ability_name == "Waaagh!":
			return true
	return false

static func is_waaagh_active_for_unit(unit: Dictionary) -> bool:
	"""Static query: Check if a unit currently has Waaagh! active (for RulesEngine)."""
	return unit.get("flags", {}).get("waaagh_active", false)

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
	stance: 'dacatarai' or 'rendax'"""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return {"success": false, "error": "Unit not found: %s" % unit_id}

	if stance != "dacatarai" and stance != "rendax":
		return {"success": false, "error": "Invalid stance: %s (must be 'dacatarai' or 'rendax')" % stance}

	# Clear any previous stance flags
	clear_katah_stance(unit_id)

	# Set the appropriate effect flag
	if not unit.has("flags"):
		unit["flags"] = {}

	if stance == "dacatarai":
		# Sustained Hits 1 on melee attacks
		unit["flags"]["effect_sustained_hits"] = true
		unit["flags"]["katah_stance"] = "dacatarai"
		unit["flags"]["katah_sustained_hits_value"] = 1
	elif stance == "rendax":
		# Lethal Hits on melee attacks
		unit["flags"]["effect_lethal_hits"] = true
		unit["flags"]["katah_stance"] = "rendax"

	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var stance_display = FACTION_ABILITIES["Martial Ka'tah"]["stances"][stance]["display"]
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

	# Deactivate Waaagh! if it was active (it lasts "until the start of your next Command phase")
	if _waaagh_active.get(str(player), false):
		deactivate_waaagh(player)

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
		"waaagh_active": _waaagh_active.duplicate(true)
	}

func load_state(data: Dictionary) -> void:
	"""Restore state from save data."""
	_active_effects = data.get("active_effects", {"1": {}, "2": {}})
	_player_abilities = data.get("player_abilities", {"1": [], "2": []})
	_waaagh_used = data.get("waaagh_used", {"1": false, "2": false})
	_waaagh_active = data.get("waaagh_active", {"1": false, "2": false})
	print("FactionAbilityManager: State loaded — effects: %s, waaagh_active: %s" % [str(_active_effects), str(_waaagh_active)])
