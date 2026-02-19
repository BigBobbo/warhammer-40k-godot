extends Node

# UnitAbilityManager - Applies datasheet/faction ability effects using EffectPrimitives
#
# This manager bridges the gap between ability descriptions stored in unit meta.abilities
# and the EffectPrimitives flag system used by RulesEngine during combat resolution.
#
# Architecture:
# - ABILITY_EFFECTS lookup table maps ability names to EffectPrimitives effect definitions
# - At the start of combat-relevant phases (Shooting, Fight), scans all units and applies
#   effect flags for matched abilities (leader abilities, always-on abilities, etc.)
# - At the end of each phase, clears ability-applied effect flags
# - RulesEngine reads the same effect_* flags regardless of whether they came from
#   a stratagem or an ability
#
# Supported ability categories:
# 1. Leader abilities ("while this model is leading a unit") - apply to the led unit
# 2. Always-on unit abilities (Stealth, Ramshackle, etc.) - apply to the unit itself
# 3. Conditional abilities (Waaagh!-dependent, objective-dependent) - apply when condition met
#
# NOTE: Some abilities are already handled directly in RulesEngine without flags:
# - Stealth: RulesEngine.has_stealth_ability() checks meta.abilities directly
# - Lone Operative: RulesEngine.has_lone_operative() checks meta.abilities directly
# - Deep Strike, Infiltrators, Scouts: handled by deployment phases
# - Transport, Firing Deck: handled by TransportManager
# These are NOT duplicated here to avoid double-application.

# ============================================================================
# ABILITY EFFECTS LOOKUP TABLE
# ============================================================================
# Maps ability names to their EffectPrimitives-based effect definitions.
#
# Each entry:
#   "name": {
#     "condition": String,   # "while_leading", "always", "waaagh_active", "on_objective"
#     "effects": Array,      # Same format as stratagem effects: [{"type": "...", ...}]
#     "target": String,      # "led_unit" (bodyguard unit), "unit" (self), "model" (self only)
#     "attack_type": String, # "melee", "ranged", "all" — which attacks the effect modifies
#     "implemented": bool,   # Whether we can fully resolve this ability
#     "description": String  # Short description for debugging/UI
#   }

const ABILITY_EFFECTS: Dictionary = {
	# ======================================================================
	# LEADER ABILITIES — "While this model is leading a unit..."
	# These apply to the bodyguard unit when the CHARACTER is attached.
	# ======================================================================

	# Ork Warboss / Boss Zagstruk / Speedboss — +1 to melee hit rolls
	"Might is Right": {
		"condition": "while_leading",
		"effects": [{"type": "plus_one_hit"}],
		"target": "led_unit",
		"attack_type": "melee",
		"implemented": true,
		"description": "+1 to melee Hit rolls for led unit"
	},

	# Ork Warboss on Warbike — same as Might is Right
	"Speedboss": {
		"condition": "while_leading",
		"effects": [{"type": "plus_one_hit"}],
		"target": "led_unit",
		"attack_type": "melee",
		"implemented": true,
		"description": "+1 to melee Hit rolls for led unit"
	},

	# Ork Boss Zagstruk — same as Might is Right
	"Drill Boss": {
		"condition": "while_leading",
		"effects": [{"type": "plus_one_hit"}],
		"target": "led_unit",
		"attack_type": "melee",
		"implemented": true,
		"description": "+1 to melee Hit rolls for led unit"
	},

	# Ork Ghazghkull Thraka — +1 to melee Hit AND Wound rolls
	"Prophet of Da Great Waaagh!": {
		"condition": "while_leading",
		"effects": [{"type": "plus_one_hit"}, {"type": "plus_one_wound"}],
		"target": "led_unit",
		"attack_type": "melee",
		"implemented": true,
		"description": "+1 to melee Hit and Wound rolls for led unit"
	},

	# Ork Big Mek in Mega Armour — re-roll Hit rolls of 1 (ranged)
	"More Dakka": {
		"condition": "while_leading",
		"effects": [{"type": "reroll_hits", "scope": "ones"}],
		"target": "led_unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "Re-roll ranged Hit rolls of 1 for led unit"
	},

	# Ork Kaptin Badrukk — re-roll Hit rolls (all, ranged)
	"Flashiest Gitz": {
		"condition": "while_leading",
		"effects": [{"type": "reroll_hits", "scope": "all"}],
		"target": "led_unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "Re-roll all ranged Hit rolls for led unit"
	},

	# Ork Boss Snikrot — led unit has Benefit of Cover
	"Red Skull Kommandos": {
		"condition": "while_leading",
		"effects": [{"type": "grant_cover"}],
		"target": "led_unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Led unit has Benefit of Cover"
	},

	# Ork Painboy / Mad Dok Grotsnik — led unit has Feel No Pain 5+
	"Dok's Toolz": {
		"condition": "while_leading",
		"effects": [{"type": "grant_fnp", "value": 5}],
		"target": "led_unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Led unit has Feel No Pain 5+"
	},

	"Mad Dok": {
		"condition": "while_leading",
		"effects": [{"type": "grant_fnp", "value": 5}],
		"target": "led_unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Led unit has Feel No Pain 5+"
	},

	# Ork Mad Dok Grotsnik — eligible to charge after falling back
	"One Scalpel Short of a Medpack": {
		"condition": "while_leading",
		"effects": [{"type": "fall_back_and_charge"}],
		"target": "led_unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Led unit can charge after falling back"
	},

	# Custodes Blade Champion — re-roll Charge rolls
	"Swift Onslaught": {
		"condition": "while_leading",
		"effects": [{"type": "reroll_charge"}],
		"target": "led_unit",
		"attack_type": "all",
		"implemented": false,
		"description": "Re-roll Charge rolls for led unit (reroll_charge not yet a primitive)"
	},

	# ======================================================================
	# ALWAYS-ON UNIT ABILITIES
	# ======================================================================

	# Custodes Custodian Guard — re-roll Wound rolls of 1
	"Stand Vigil": {
		"condition": "always",
		"effects": [{"type": "reroll_wounds", "scope": "ones"}],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Re-roll Wound rolls of 1"
	},

	# Ork Battlewagon — simplified as FNP 6+ (actual: each time loses wounds, D6: 6 = ignore)
	"Ramshackle": {
		"condition": "always",
		"effects": [{"type": "grant_fnp", "value": 6}],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Feel No Pain 6+ (simplified from per-wound-loss D6:6)"
	},

	# Ork Boyz — sticky objectives
	"Get Da Good Bitz": {
		"condition": "on_objective",
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": false,
		"description": "Sticky objectives (not yet a combat effect)"
	},

	# Custodes Witchseekers — FNP 3+ vs Psychic/mortal wounds
	"Daughters of the Abyss": {
		"condition": "always",
		"effects": [{"type": "grant_fnp", "value": 3}],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Feel No Pain 3+ vs Psychic Attacks and mortal wounds (simplified: FNP 3+ always)"
	},

	# Custodes Blade Champion — once per battle advance and charge
	"Martial Inspiration": {
		"condition": "while_leading",
		"effects": [{"type": "advance_and_charge"}],
		"target": "led_unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per battle: charge after advancing"
	},

	# ======================================================================
	# CONDITIONAL ABILITIES (Waaagh!-dependent etc.)
	# These are tracked but not auto-applied; they require game state conditions.
	# ======================================================================

	# Ork Warboss — +4 attacks while Waaagh! active
	"Da Biggest and da Best": {
		"condition": "waaagh_active",
		"effects": [],
		"target": "model",
		"attack_type": "melee",
		"implemented": false,
		"description": "+4 melee Attacks while Waaagh! active (stat modification not yet supported)"
	},

	# Ork Warboss in Mega Armour — weapon damage 3 while Waaagh! active
	"Dead Brutal": {
		"condition": "waaagh_active",
		"effects": [],
		"target": "model",
		"attack_type": "melee",
		"implemented": false,
		"description": "Weapon damage = 3 while Waaagh! active (weapon stat modification not yet supported)"
	},
}

# ============================================================================
# STATE
# ============================================================================

# Active ability effects currently applied to units
# Each entry: { "ability_name": String, "source_unit_id": String (leader),
#               "target_unit_id": String, "effects": Array,
#               "attack_type": String, "condition": String }
var _active_ability_effects: Array = []

# Track which units have had ability flags applied this phase
# { unit_id: [ability_name1, ability_name2, ...] }
var _applied_this_phase: Dictionary = {}

func _ready() -> void:
	var implemented_count = 0
	for ability_name in ABILITY_EFFECTS:
		if ABILITY_EFFECTS[ability_name].get("implemented", false):
			implemented_count += 1
	print("UnitAbilityManager: Ready — %d ability definitions (%d implemented)" % [ABILITY_EFFECTS.size(), implemented_count])

# ============================================================================
# PHASE LIFECYCLE
# ============================================================================

func on_phase_start(phase: int) -> void:
	"""Called at the start of each phase. Applies ability effects for combat phases."""
	# Apply ability effects at start of combat-relevant phases
	if _is_combat_phase(phase):
		_apply_all_ability_effects(phase)
		var phase_name = _phase_to_string(phase)
		print("UnitAbilityManager: Applied ability effects for %s phase (%d active effects)" % [phase_name, _active_ability_effects.size()])

func on_phase_end(phase: int) -> void:
	"""Called at the end of each phase. Clears ability-applied effect flags."""
	if _is_combat_phase(phase) or _applied_this_phase.size() > 0:
		_clear_all_ability_effects()
		var phase_name = _phase_to_string(phase)
		print("UnitAbilityManager: Cleared ability effects at end of %s phase" % phase_name)

func on_movement_phase_start() -> void:
	"""Called at movement phase start. Applies eligibility abilities (fall_back_and_charge, etc.)."""
	_apply_eligibility_effects()
	print("UnitAbilityManager: Applied eligibility effects for Movement phase")

func on_movement_phase_end() -> void:
	"""Called at movement phase end. Clears eligibility flags."""
	_clear_all_ability_effects()

# ============================================================================
# CORE: APPLY ABILITY EFFECTS
# ============================================================================

func _apply_all_ability_effects(phase: int) -> void:
	"""Scan all units and apply relevant ability effects as flags."""
	_active_ability_effects.clear()
	_applied_this_phase.clear()

	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]

		# Skip destroyed units
		if not _has_alive_models(unit):
			continue

		# 1. Check for leader abilities on attached characters
		_apply_leader_abilities(unit_id, unit, phase)

		# 2. Check for always-on unit abilities
		_apply_unit_abilities(unit_id, unit, phase)

func _apply_leader_abilities(bodyguard_unit_id: String, bodyguard_unit: Dictionary, phase: int) -> void:
	"""Check if this unit has attached leaders with combat-affecting abilities."""
	var attachment_data = bodyguard_unit.get("attachment_data", {})
	var attached_characters = attachment_data.get("attached_characters", [])

	if attached_characters.is_empty():
		return

	var units = GameState.state.get("units", {})

	for char_id in attached_characters:
		var char_unit = units.get(char_id, {})
		if char_unit.is_empty():
			continue

		# Character must have alive models
		if not _has_alive_models(char_unit):
			continue

		# Scan the character's abilities
		var abilities = char_unit.get("meta", {}).get("abilities", [])
		for ability in abilities:
			var ability_name = ""
			if ability is String:
				ability_name = ability
			elif ability is Dictionary:
				ability_name = ability.get("name", "")

			if ability_name == "" or ability_name == "Core":
				continue

			# Look up in our effects table
			var effect_def = ABILITY_EFFECTS.get(ability_name, {})
			if effect_def.is_empty():
				continue
			if not effect_def.get("implemented", false):
				continue
			if effect_def.get("condition", "") != "while_leading":
				continue
			if effect_def.get("target", "") != "led_unit":
				continue

			# Check if this ability is relevant to the current phase
			if not _is_relevant_for_phase(effect_def, phase):
				continue

			# Apply the effects to the bodyguard unit
			var effects = effect_def.get("effects", [])
			if effects.is_empty():
				continue

			var diffs = EffectPrimitivesData.apply_effects(effects, bodyguard_unit_id)
			if not diffs.is_empty():
				PhaseManager.apply_state_changes(diffs)

				# Track the active effect
				_active_ability_effects.append({
					"ability_name": ability_name,
					"source_unit_id": char_id,
					"target_unit_id": bodyguard_unit_id,
					"effects": effects,
					"attack_type": effect_def.get("attack_type", "all"),
					"condition": "while_leading"
				})

				# Track for phase cleanup
				if not _applied_this_phase.has(bodyguard_unit_id):
					_applied_this_phase[bodyguard_unit_id] = []
				_applied_this_phase[bodyguard_unit_id].append(ability_name)

				var char_name = char_unit.get("meta", {}).get("name", char_id)
				var bg_name = bodyguard_unit.get("meta", {}).get("name", bodyguard_unit_id)
				var flag_names = EffectPrimitivesData.get_flag_names_for_effects(effects)
				print("UnitAbilityManager: %s (%s) grants '%s' to %s — flags: %s" % [
					char_name, char_id, ability_name, bg_name, str(flag_names)
				])

func _apply_unit_abilities(unit_id: String, unit: Dictionary, phase: int) -> void:
	"""Check if this unit has always-on abilities that affect combat."""
	var abilities = unit.get("meta", {}).get("abilities", [])

	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")

		if ability_name == "" or ability_name == "Core":
			continue

		# Look up in our effects table
		var effect_def = ABILITY_EFFECTS.get(ability_name, {})
		if effect_def.is_empty():
			continue
		if not effect_def.get("implemented", false):
			continue

		# Only handle "always" condition here (leader abilities handled separately)
		var condition = effect_def.get("condition", "")
		if condition != "always":
			continue

		# Target must be "unit" (self)
		if effect_def.get("target", "") != "unit":
			continue

		# Check if relevant for this phase
		if not _is_relevant_for_phase(effect_def, phase):
			continue

		# Don't double-apply if already applied this phase
		if _applied_this_phase.has(unit_id) and ability_name in _applied_this_phase[unit_id]:
			continue

		var effects = effect_def.get("effects", [])
		if effects.is_empty():
			continue

		var diffs = EffectPrimitivesData.apply_effects(effects, unit_id)
		if not diffs.is_empty():
			PhaseManager.apply_state_changes(diffs)

			_active_ability_effects.append({
				"ability_name": ability_name,
				"source_unit_id": unit_id,
				"target_unit_id": unit_id,
				"effects": effects,
				"attack_type": effect_def.get("attack_type", "all"),
				"condition": "always"
			})

			if not _applied_this_phase.has(unit_id):
				_applied_this_phase[unit_id] = []
			_applied_this_phase[unit_id].append(ability_name)

			var unit_name = unit.get("meta", {}).get("name", unit_id)
			var flag_names = EffectPrimitivesData.get_flag_names_for_effects(effects)
			print("UnitAbilityManager: %s (%s) has ability '%s' — flags: %s" % [
				unit_name, unit_id, ability_name, str(flag_names)
			])

func _apply_eligibility_effects() -> void:
	"""Apply eligibility abilities (fall_back_and_charge, advance_and_charge, etc.)
	   at the start of the Movement phase so they're available during movement decisions."""
	_active_ability_effects.clear()
	_applied_this_phase.clear()

	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if not _has_alive_models(unit):
			continue

		# Check leader abilities for eligibility effects
		var attachment_data = unit.get("attachment_data", {})
		var attached_characters = attachment_data.get("attached_characters", [])

		for char_id in attached_characters:
			var char_unit = units.get(char_id, {})
			if char_unit.is_empty() or not _has_alive_models(char_unit):
				continue

			var abilities = char_unit.get("meta", {}).get("abilities", [])
			for ability in abilities:
				var ability_name = _get_ability_name(ability)
				if ability_name == "":
					continue

				var effect_def = ABILITY_EFFECTS.get(ability_name, {})
				if effect_def.is_empty() or not effect_def.get("implemented", false):
					continue
				if effect_def.get("condition", "") != "while_leading":
					continue

				# Only apply eligibility effects (fall_back_and_*, advance_and_*)
				var effects = effect_def.get("effects", [])
				var eligibility_effects = []
				for effect in effects:
					var etype = effect.get("type", "")
					if etype in [
						EffectPrimitivesData.FALL_BACK_AND_SHOOT,
						EffectPrimitivesData.FALL_BACK_AND_CHARGE,
						EffectPrimitivesData.ADVANCE_AND_CHARGE,
						EffectPrimitivesData.ADVANCE_AND_SHOOT
					]:
						eligibility_effects.append(effect)

				if eligibility_effects.is_empty():
					continue

				var diffs = EffectPrimitivesData.apply_effects(eligibility_effects, unit_id)
				if not diffs.is_empty():
					PhaseManager.apply_state_changes(diffs)
					_active_ability_effects.append({
						"ability_name": ability_name,
						"source_unit_id": char_id,
						"target_unit_id": unit_id,
						"effects": eligibility_effects,
						"attack_type": "all",
						"condition": "while_leading"
					})
					if not _applied_this_phase.has(unit_id):
						_applied_this_phase[unit_id] = []
					_applied_this_phase[unit_id].append(ability_name)

					var char_name = char_unit.get("meta", {}).get("name", char_id)
					var bg_name = unit.get("meta", {}).get("name", unit_id)
					print("UnitAbilityManager: %s grants eligibility '%s' to %s" % [char_name, ability_name, bg_name])

# ============================================================================
# CLEAR ABILITY EFFECTS
# ============================================================================

func _clear_all_ability_effects() -> void:
	"""Clear all ability-applied effect flags from units."""
	var units = GameState.state.get("units", {})

	for effect_entry in _active_ability_effects:
		var target_unit_id = effect_entry.get("target_unit_id", "")
		var effects = effect_entry.get("effects", [])
		var unit = units.get(target_unit_id, {})
		if unit.is_empty():
			continue

		var flags = unit.get("flags", {})
		EffectPrimitivesData.clear_effects(effects, target_unit_id, flags)

	_active_ability_effects.clear()
	_applied_this_phase.clear()

# ============================================================================
# QUERY HELPERS
# ============================================================================

func get_active_ability_effects_for_unit(unit_id: String) -> Array:
	"""Get all active ability effects on a unit. Useful for UI display."""
	var results = []
	for effect in _active_ability_effects:
		if effect.get("target_unit_id", "") == unit_id:
			results.append(effect)
	return results

func unit_has_active_ability(unit_id: String, ability_name: String) -> bool:
	"""Check if a unit currently has a specific ability effect active."""
	for effect in _active_ability_effects:
		if effect.get("target_unit_id", "") == unit_id and effect.get("ability_name", "") == ability_name:
			return true
	return false

func get_ability_effect_definition(ability_name: String) -> Dictionary:
	"""Get the effect definition for an ability name. Returns empty dict if not found."""
	return ABILITY_EFFECTS.get(ability_name, {})

func is_ability_implemented(ability_name: String) -> bool:
	"""Check if an ability has a mechanical implementation."""
	var def_data = ABILITY_EFFECTS.get(ability_name, {})
	return def_data.get("implemented", false)

func get_implemented_abilities() -> Array:
	"""Get all ability names that are mechanically implemented."""
	var result = []
	for ability_name in ABILITY_EFFECTS:
		if ABILITY_EFFECTS[ability_name].get("implemented", false):
			result.append(ability_name)
	return result

func get_unit_ability_summary(unit_id: String) -> Array:
	"""Get a summary of all abilities on a unit and their implementation status.
	Returns array of { name, type, implemented, active }."""
	var summary = []
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return summary

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "" or ability_name == "Core":
			continue

		var ability_type = ""
		if ability is Dictionary:
			ability_type = ability.get("type", "")

		var effect_def = ABILITY_EFFECTS.get(ability_name, {})
		summary.append({
			"name": ability_name,
			"type": ability_type,
			"implemented": effect_def.get("implemented", false),
			"active": unit_has_active_ability(unit_id, ability_name),
			"has_definition": not effect_def.is_empty()
		})

	return summary

func get_leader_abilities_for_unit(unit_id: String) -> Array:
	"""Get leader abilities that are currently active on a unit from attached characters.
	Returns array of { ability_name, source_character_id, attack_type, effects }."""
	var results = []
	for effect in _active_ability_effects:
		if effect.get("target_unit_id", "") == unit_id and effect.get("condition", "") == "while_leading":
			results.append({
				"ability_name": effect.get("ability_name", ""),
				"source_character_id": effect.get("source_unit_id", ""),
				"attack_type": effect.get("attack_type", "all"),
				"effects": effect.get("effects", [])
			})
	return results

# ============================================================================
# STATIC QUERY — Check abilities on units without needing phase flags
# ============================================================================
# These methods check meta.abilities directly for cases where RulesEngine needs
# to know about abilities outside of the flag system.

static func unit_has_leader_ability(bodyguard_unit: Dictionary, ability_name: String, all_units: Dictionary) -> bool:
	"""Check if a bodyguard unit has a leader granting a specific ability.
	Works without requiring phase flag application."""
	var attachment_data = bodyguard_unit.get("attachment_data", {})
	var attached_characters = attachment_data.get("attached_characters", [])

	for char_id in attached_characters:
		var char_unit = all_units.get(char_id, {})
		if char_unit.is_empty():
			continue

		# Character must be alive
		var has_alive = false
		for model in char_unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue

		var abilities = char_unit.get("meta", {}).get("abilities", [])
		for ability in abilities:
			var name = ""
			if ability is String:
				name = ability
			elif ability is Dictionary:
				name = ability.get("name", "")
			if name == ability_name:
				return true

	return false

static func get_ability_attack_type(ability_name: String) -> String:
	"""Get the attack_type restriction for an ability (melee/ranged/all)."""
	var def_data = ABILITY_EFFECTS.get(ability_name, {})
	return def_data.get("attack_type", "all")

# ============================================================================
# HELPERS
# ============================================================================

func _has_alive_models(unit: Dictionary) -> bool:
	"""Check if a unit has at least one alive model."""
	for model in unit.get("models", []):
		if model.get("alive", true):
			return true
	return false

func _get_ability_name(ability) -> String:
	"""Extract ability name from either String or Dictionary format."""
	if ability is String:
		return ability
	elif ability is Dictionary:
		return ability.get("name", "")
	return ""

func _is_combat_phase(phase: int) -> bool:
	"""Check if a phase involves combat resolution (where ability flags matter)."""
	const GameStateData = preload("res://autoloads/GameState.gd")
	return phase in [
		GameStateData.Phase.SHOOTING,
		GameStateData.Phase.FIGHT,
		GameStateData.Phase.CHARGE  # For Tank Shock, Overwatch interactions
	]

func _is_relevant_for_phase(effect_def: Dictionary, phase: int) -> bool:
	"""Check if an ability's effects are relevant for the current phase."""
	var attack_type = effect_def.get("attack_type", "all")
	const GameStateData = preload("res://autoloads/GameState.gd")

	# "all" is always relevant
	if attack_type == "all":
		return true

	# "melee" only relevant in Fight phase
	if attack_type == "melee" and phase == GameStateData.Phase.FIGHT:
		return true

	# "ranged" only relevant in Shooting phase (and Charge for overwatch)
	if attack_type == "ranged" and phase in [GameStateData.Phase.SHOOTING, GameStateData.Phase.CHARGE]:
		return true

	return false

func _phase_to_string(phase: int) -> String:
	const GameStateData = preload("res://autoloads/GameState.gd")
	match phase:
		GameStateData.Phase.DEPLOYMENT: return "deployment"
		GameStateData.Phase.COMMAND: return "command"
		GameStateData.Phase.MOVEMENT: return "movement"
		GameStateData.Phase.SHOOTING: return "shooting"
		GameStateData.Phase.CHARGE: return "charge"
		GameStateData.Phase.FIGHT: return "fight"
		GameStateData.Phase.SCORING: return "scoring"
		_: return "unknown"

# ============================================================================
# SAVE/LOAD SUPPORT
# ============================================================================

func get_state_for_save() -> Dictionary:
	"""Return state data for save games."""
	return {
		"active_ability_effects": _active_ability_effects.duplicate(true),
		"applied_this_phase": _applied_this_phase.duplicate(true)
	}

func load_state(data: Dictionary) -> void:
	"""Restore state from save data."""
	_active_ability_effects = data.get("active_ability_effects", [])
	_applied_this_phase = data.get("applied_this_phase", {})
	print("UnitAbilityManager: State loaded — %d active effects" % _active_ability_effects.size())

func reset_for_new_game() -> void:
	"""Reset all tracking for a new game."""
	_active_ability_effects.clear()
	_applied_this_phase.clear()
	print("UnitAbilityManager: Reset for new game")
