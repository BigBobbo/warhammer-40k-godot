extends Node
class_name EffectPrimitivesData

# EffectPrimitives - Data-driven effect system for stratagems and abilities
#
# This library provides a unified way to define, apply, query, and clear
# game effects. Both stratagems and unit abilities produce effects from
# the same set of primitives, allowing them to share the same downstream
# resolution logic in RulesEngine.
#
# Architecture:
# - Effects are defined as dictionaries with a "type" string and optional parameters
# - Persistent effects set flags on units via state diffs; RulesEngine reads these flags
# - Instant effects (mortal wounds, re-rolls, fight order) are executed immediately
#   and don't set persistent flags
# - apply_effects() generates diffs to set flags; clear_effects() removes them
# - Query helpers (has_effect_*, get_effect_value) let RulesEngine check flags generically

# ============================================================================
# EFFECT TYPE CONSTANTS
# ============================================================================
# These match the "type" strings used in stratagem/ability effect definitions.

# Defensive effects (persistent flags on target unit)
const GRANT_INVULN = "grant_invuln"              # value: save threshold (e.g., 6 for 6+)
const GRANT_COVER = "grant_cover"                 # Benefit of Cover
const GRANT_STEALTH = "grant_stealth"             # -1 to hit against this unit (ranged)
const GRANT_FNP = "grant_fnp"                     # value: FNP threshold (e.g., 5 for 5+)

# Offensive weapon keyword grants (persistent flags on attacker unit)
const GRANT_KEYWORD = "grant_keyword"             # keyword: String, scope: "melee"/"ranged"/"all"

# Specific keyword shortcuts (can also use GRANT_KEYWORD with keyword param)
const GRANT_PRECISION = "grant_precision"          # scope: "melee"/"ranged"/"all"
const GRANT_LETHAL_HITS = "grant_lethal_hits"
const GRANT_SUSTAINED_HITS = "grant_sustained_hits"
const GRANT_DEVASTATING_WOUNDS = "grant_devastating_wounds"
const GRANT_IGNORES_COVER = "grant_ignores_cover"
const GRANT_LANCE = "grant_lance"
const GRANT_TWIN_LINKED = "grant_twin_linked"

# Hit/wound stat modifiers (persistent flags)
const PLUS_ONE_HIT = "plus_one_hit"
const MINUS_ONE_HIT = "minus_one_hit"
const PLUS_ONE_WOUND = "plus_one_wound"
const MINUS_ONE_WOUND = "minus_one_wound"
const REROLL_HITS = "reroll_hits"                 # scope: "ones"/"failed"/"all"
const REROLL_WOUNDS = "reroll_wounds"             # scope: "ones"/"failed"/"all"
const REROLL_SAVES = "reroll_saves"               # scope: "ones"/"failed"/"all"

# AP/damage modifiers (persistent flags)
const IMPROVE_AP = "improve_ap"                   # value: amount to improve
const WORSEN_AP = "worsen_ap"                     # value: amount to worsen
const PLUS_DAMAGE = "plus_damage"                 # value: amount to add
const MINUS_DAMAGE = "minus_damage"               # value: amount to subtract (min 1)

# Critical threshold modifiers (persistent flags)
const CRIT_HIT_ON = "crit_hit_on"                 # value: threshold (e.g., 5 for 5+)
const CRIT_WOUND_ON = "crit_wound_on"             # value: threshold

# Movement/eligibility flags (persistent)
const FALL_BACK_AND_SHOOT = "fall_back_and_shoot"
const FALL_BACK_AND_CHARGE = "fall_back_and_charge"
const ADVANCE_AND_CHARGE = "advance_and_charge"
const ADVANCE_AND_SHOOT = "advance_and_shoot"

# Instant effects (no persistent flags — executed immediately by the caller)
const MORTAL_WOUNDS = "mortal_wounds"                     # dice: int, threshold: int
const MORTAL_WOUNDS_TOUGHNESS = "mortal_wounds_toughness_based"  # threshold: int, max: int
const REROLL_LAST_ROLL = "reroll_last_roll"
const FIGHT_NEXT = "fight_next"
const OVERWATCH_SHOOT = "overwatch_shoot"                 # hit_on: int
const COUNTER_CHARGE = "counter_charge"
const AUTO_PASS_SHOCK = "auto_pass_battle_shock"
const ARRIVE_FROM_RESERVES = "arrive_from_reserves"
const DISCARD_SECONDARY = "discard_and_draw_secondary"

# ============================================================================
# FLAG NAME CONSTANTS
# ============================================================================
# Standardized flag names set on units. Used by both apply/clear and RulesEngine queries.
# Naming convention: "effect_<type>" — generic enough for both stratagems and abilities.

const FLAG_INVULN = "effect_invuln"
const FLAG_COVER = "effect_cover"
const FLAG_STEALTH = "effect_stealth"
const FLAG_FNP = "effect_fnp"
const FLAG_PRECISION_MELEE = "effect_precision_melee"
const FLAG_PRECISION_RANGED = "effect_precision_ranged"
const FLAG_LETHAL_HITS = "effect_lethal_hits"
const FLAG_SUSTAINED_HITS = "effect_sustained_hits"
const FLAG_DEVASTATING_WOUNDS = "effect_devastating_wounds"
const FLAG_IGNORES_COVER = "effect_ignores_cover"
const FLAG_LANCE = "effect_lance"
const FLAG_TWIN_LINKED = "effect_twin_linked"
const FLAG_PLUS_ONE_HIT = "effect_plus_one_hit"
const FLAG_MINUS_ONE_HIT = "effect_minus_one_hit"
const FLAG_PLUS_ONE_WOUND = "effect_plus_one_wound"
const FLAG_MINUS_ONE_WOUND = "effect_minus_one_wound"
const FLAG_REROLL_HITS = "effect_reroll_hits"         # value: "ones"/"failed"/"all"
const FLAG_REROLL_WOUNDS = "effect_reroll_wounds"     # value: "ones"/"failed"/"all"
const FLAG_REROLL_SAVES = "effect_reroll_saves"       # value: "ones"/"failed"/"all"
const FLAG_IMPROVE_AP = "effect_improve_ap"
const FLAG_WORSEN_AP = "effect_worsen_ap"
const FLAG_PLUS_DAMAGE = "effect_plus_damage"
const FLAG_MINUS_DAMAGE = "effect_minus_damage"
const FLAG_CRIT_HIT_ON = "effect_crit_hit_on"
const FLAG_CRIT_WOUND_ON = "effect_crit_wound_on"
const FLAG_FALL_BACK_AND_SHOOT = "effect_fall_back_and_shoot"
const FLAG_FALL_BACK_AND_CHARGE = "effect_fall_back_and_charge"
const FLAG_ADVANCE_AND_CHARGE = "effect_advance_and_charge"
const FLAG_ADVANCE_AND_SHOOT = "effect_advance_and_shoot"

# ============================================================================
# EFFECT → FLAG MAPPING
# ============================================================================
# Maps effect type strings to their corresponding unit flag configurations.
# Only persistent effects have flag mappings; instant effects return empty.
#
# Each entry is an Array of flag descriptors:
#   { "flag": String, "value": Variant }         — static value
#   { "flag": String, "value_from": String }      — value read from effect dict key
#   { "flag": String, "value": true }             — boolean flag

const _EFFECT_FLAG_MAP: Dictionary = {
	GRANT_INVULN: [{"flag": FLAG_INVULN, "value_from": "value"}],
	GRANT_COVER: [{"flag": FLAG_COVER, "value": true}],
	GRANT_STEALTH: [{"flag": FLAG_STEALTH, "value": true}],
	GRANT_FNP: [{"flag": FLAG_FNP, "value_from": "value"}],
	GRANT_PRECISION: "use_scope",  # Special handling: scope determines flag
	GRANT_LETHAL_HITS: [{"flag": FLAG_LETHAL_HITS, "value": true}],
	GRANT_SUSTAINED_HITS: [{"flag": FLAG_SUSTAINED_HITS, "value": true}],
	GRANT_DEVASTATING_WOUNDS: [{"flag": FLAG_DEVASTATING_WOUNDS, "value": true}],
	GRANT_IGNORES_COVER: [{"flag": FLAG_IGNORES_COVER, "value": true}],
	GRANT_LANCE: [{"flag": FLAG_LANCE, "value": true}],
	GRANT_TWIN_LINKED: [{"flag": FLAG_TWIN_LINKED, "value": true}],
	PLUS_ONE_HIT: [{"flag": FLAG_PLUS_ONE_HIT, "value": true}],
	MINUS_ONE_HIT: [{"flag": FLAG_MINUS_ONE_HIT, "value": true}],
	PLUS_ONE_WOUND: [{"flag": FLAG_PLUS_ONE_WOUND, "value": true}],
	MINUS_ONE_WOUND: [{"flag": FLAG_MINUS_ONE_WOUND, "value": true}],
	REROLL_HITS: [{"flag": FLAG_REROLL_HITS, "value_from": "scope"}],
	REROLL_WOUNDS: [{"flag": FLAG_REROLL_WOUNDS, "value_from": "scope"}],
	REROLL_SAVES: [{"flag": FLAG_REROLL_SAVES, "value_from": "scope"}],
	IMPROVE_AP: [{"flag": FLAG_IMPROVE_AP, "value_from": "value"}],
	WORSEN_AP: [{"flag": FLAG_WORSEN_AP, "value_from": "value"}],
	PLUS_DAMAGE: [{"flag": FLAG_PLUS_DAMAGE, "value_from": "value"}],
	MINUS_DAMAGE: [{"flag": FLAG_MINUS_DAMAGE, "value_from": "value"}],
	CRIT_HIT_ON: [{"flag": FLAG_CRIT_HIT_ON, "value_from": "value"}],
	CRIT_WOUND_ON: [{"flag": FLAG_CRIT_WOUND_ON, "value_from": "value"}],
	FALL_BACK_AND_SHOOT: [{"flag": FLAG_FALL_BACK_AND_SHOOT, "value": true}],
	FALL_BACK_AND_CHARGE: [{"flag": FLAG_FALL_BACK_AND_CHARGE, "value": true}],
	ADVANCE_AND_CHARGE: [{"flag": FLAG_ADVANCE_AND_CHARGE, "value": true}],
	ADVANCE_AND_SHOOT: [{"flag": FLAG_ADVANCE_AND_SHOOT, "value": true}],
}

# Set of instant effect types that don't set persistent flags
const _INSTANT_EFFECTS: Array = [
	MORTAL_WOUNDS,
	MORTAL_WOUNDS_TOUGHNESS,
	REROLL_LAST_ROLL,
	FIGHT_NEXT,
	OVERWATCH_SHOOT,
	COUNTER_CHARGE,
	AUTO_PASS_SHOCK,
	ARRIVE_FROM_RESERVES,
	DISCARD_SECONDARY,
]

# ============================================================================
# APPLY EFFECTS
# ============================================================================

static func apply_effects(effects: Array, target_unit_id: String) -> Array:
	"""
	Generate state diffs to apply an array of effects to a unit.
	Only persistent (flag-based) effects produce diffs. Instant effects are skipped
	(they should be handled by the caller's execution logic).
	Returns Array of diff dictionaries for PhaseManager.apply_state_changes().
	"""
	var diffs: Array = []
	for effect in effects:
		var effect_diffs = _apply_single_effect(effect, target_unit_id)
		diffs.append_array(effect_diffs)
	return diffs

static func _apply_single_effect(effect: Dictionary, target_unit_id: String) -> Array:
	"""Generate diffs for a single effect definition."""
	var effect_type = effect.get("type", "")

	# Skip instant effects — they don't set flags
	if effect_type in _INSTANT_EFFECTS:
		return []

	# Handle grant_keyword specially (uses keyword + scope to determine flag)
	if effect_type == GRANT_KEYWORD:
		return _apply_grant_keyword(effect, target_unit_id)

	# Handle grant_precision specially (uses scope to determine flag)
	if effect_type == GRANT_PRECISION:
		return _apply_grant_precision(effect, target_unit_id)

	# Look up flag mapping
	var mapping = _EFFECT_FLAG_MAP.get(effect_type)
	if mapping == null:
		print("EffectPrimitives: Unknown effect type '%s' — no flags to set" % effect_type)
		return []
	if mapping is String and mapping == "use_scope":
		# This shouldn't happen since GRANT_PRECISION is handled above
		return []

	# Apply each flag descriptor
	var diffs: Array = []
	for descriptor in mapping:
		var flag_name: String = descriptor.flag
		var value = _resolve_flag_value(descriptor, effect)
		diffs.append({
			"op": "set",
			"path": "units.%s.flags.%s" % [target_unit_id, flag_name],
			"value": value
		})
	return diffs

static func _apply_grant_keyword(effect: Dictionary, target_unit_id: String) -> Array:
	"""Handle grant_keyword effect: determines flag from keyword + scope."""
	var keyword = effect.get("keyword", "").to_upper()
	var scope = effect.get("scope", "all").to_lower()

	var flag_name = _keyword_to_flag(keyword, scope)
	if flag_name == "":
		print("EffectPrimitives: Unknown keyword '%s' for grant_keyword" % keyword)
		return []

	return [{
		"op": "set",
		"path": "units.%s.flags.%s" % [target_unit_id, flag_name],
		"value": true
	}]

static func _apply_grant_precision(effect: Dictionary, target_unit_id: String) -> Array:
	"""Handle grant_precision effect: sets flag based on scope."""
	var scope = effect.get("scope", "all").to_lower()
	var diffs: Array = []

	if scope == "melee" or scope == "all":
		diffs.append({
			"op": "set",
			"path": "units.%s.flags.%s" % [target_unit_id, FLAG_PRECISION_MELEE],
			"value": true
		})
	if scope == "ranged" or scope == "all":
		diffs.append({
			"op": "set",
			"path": "units.%s.flags.%s" % [target_unit_id, FLAG_PRECISION_RANGED],
			"value": true
		})
	return diffs

static func _keyword_to_flag(keyword: String, scope: String) -> String:
	"""Map a weapon keyword + scope to the corresponding unit flag name."""
	match keyword:
		"PRECISION":
			if scope == "melee":
				return FLAG_PRECISION_MELEE
			elif scope == "ranged":
				return FLAG_PRECISION_RANGED
			else:
				return FLAG_PRECISION_MELEE  # Default to melee for "all" — caller handles both
		"LETHAL HITS", "LETHAL_HITS":
			return FLAG_LETHAL_HITS
		"SUSTAINED HITS", "SUSTAINED_HITS":
			return FLAG_SUSTAINED_HITS
		"DEVASTATING WOUNDS", "DEVASTATING_WOUNDS":
			return FLAG_DEVASTATING_WOUNDS
		"IGNORES COVER", "IGNORES_COVER":
			return FLAG_IGNORES_COVER
		"LANCE":
			return FLAG_LANCE
		"TWIN-LINKED", "TWIN_LINKED":
			return FLAG_TWIN_LINKED
	return ""

static func _resolve_flag_value(descriptor: Dictionary, effect: Dictionary):
	"""Resolve the value for a flag descriptor."""
	if descriptor.has("value_from"):
		# Read value from effect dictionary key
		var key = descriptor.value_from
		return effect.get(key, true)
	return descriptor.get("value", true)

# ============================================================================
# CLEAR EFFECTS
# ============================================================================

static func clear_effects(effects: Array, unit_id: String, unit_flags: Dictionary) -> void:
	"""
	Clear flags from a unit's flags dictionary for the given effects.
	Operates directly on the flags dictionary (in-memory cleanup).
	Used when effects expire at end of phase/turn.
	"""
	for effect in effects:
		_clear_single_effect(effect, unit_id, unit_flags)

static func _clear_single_effect(effect: Dictionary, unit_id: String, unit_flags: Dictionary) -> void:
	"""Clear flags for a single effect from the unit's flags dictionary."""
	var effect_type = effect.get("type", "")

	# Instant effects don't have flags to clear
	if effect_type in _INSTANT_EFFECTS:
		return

	# Handle grant_keyword specially
	if effect_type == GRANT_KEYWORD:
		var keyword = effect.get("keyword", "").to_upper()
		var scope = effect.get("scope", "all").to_lower()
		var flag_name = _keyword_to_flag(keyword, scope)
		if flag_name != "" and unit_flags.has(flag_name):
			unit_flags.erase(flag_name)
			print("EffectPrimitives: Cleared %s from %s" % [flag_name, unit_id])
		return

	# Handle grant_precision specially
	if effect_type == GRANT_PRECISION:
		var scope = effect.get("scope", "all").to_lower()
		if scope == "melee" or scope == "all":
			if unit_flags.has(FLAG_PRECISION_MELEE):
				unit_flags.erase(FLAG_PRECISION_MELEE)
				print("EffectPrimitives: Cleared %s from %s" % [FLAG_PRECISION_MELEE, unit_id])
		if scope == "ranged" or scope == "all":
			if unit_flags.has(FLAG_PRECISION_RANGED):
				unit_flags.erase(FLAG_PRECISION_RANGED)
				print("EffectPrimitives: Cleared %s from %s" % [FLAG_PRECISION_RANGED, unit_id])
		return

	# Look up flag mapping
	var mapping = _EFFECT_FLAG_MAP.get(effect_type)
	if mapping == null or (mapping is String and mapping == "use_scope"):
		return

	for descriptor in mapping:
		var flag_name: String = descriptor.flag
		if unit_flags.has(flag_name):
			unit_flags.erase(flag_name)
			print("EffectPrimitives: Cleared %s from %s" % [flag_name, unit_id])

static func get_flag_names_for_effects(effects: Array) -> Array:
	"""
	Get all flag names that would be set by the given effects.
	Useful for bulk cleanup without needing the full effect definitions.
	Returns Array of flag name strings.
	"""
	var flags: Array = []
	for effect in effects:
		var effect_type = effect.get("type", "")
		if effect_type in _INSTANT_EFFECTS:
			continue

		if effect_type == GRANT_KEYWORD:
			var keyword = effect.get("keyword", "").to_upper()
			var scope = effect.get("scope", "all").to_lower()
			var flag_name = _keyword_to_flag(keyword, scope)
			if flag_name != "" and flag_name not in flags:
				flags.append(flag_name)
			continue

		if effect_type == GRANT_PRECISION:
			var scope = effect.get("scope", "all").to_lower()
			if scope == "melee" or scope == "all":
				if FLAG_PRECISION_MELEE not in flags:
					flags.append(FLAG_PRECISION_MELEE)
			if scope == "ranged" or scope == "all":
				if FLAG_PRECISION_RANGED not in flags:
					flags.append(FLAG_PRECISION_RANGED)
			continue

		var mapping = _EFFECT_FLAG_MAP.get(effect_type)
		if mapping == null or (mapping is String and mapping == "use_scope"):
			continue
		for descriptor in mapping:
			if descriptor.flag not in flags:
				flags.append(descriptor.flag)
	return flags

# ============================================================================
# QUERY HELPERS — Used by RulesEngine to check effects on units
# ============================================================================

static func has_effect_invuln(unit: Dictionary) -> bool:
	"""Check if a unit has an effect-granted invulnerable save."""
	return unit.get("flags", {}).get(FLAG_INVULN, 0) > 0

static func get_effect_invuln(unit: Dictionary) -> int:
	"""Get the effect-granted invulnerable save value (0 if none)."""
	return unit.get("flags", {}).get(FLAG_INVULN, 0)

static func has_effect_cover(unit: Dictionary) -> bool:
	"""Check if a unit has effect-granted Benefit of Cover."""
	return unit.get("flags", {}).get(FLAG_COVER, false)

static func has_effect_stealth(unit: Dictionary) -> bool:
	"""Check if a unit has effect-granted Stealth (-1 to hit)."""
	return unit.get("flags", {}).get(FLAG_STEALTH, false)

static func has_effect_fnp(unit: Dictionary) -> bool:
	"""Check if a unit has an effect-granted Feel No Pain."""
	return unit.get("flags", {}).get(FLAG_FNP, 0) > 0

static func get_effect_fnp(unit: Dictionary) -> int:
	"""Get the effect-granted FNP value (0 if none)."""
	return unit.get("flags", {}).get(FLAG_FNP, 0)

static func has_effect_precision_melee(unit: Dictionary) -> bool:
	"""Check if a unit has effect-granted PRECISION for melee attacks."""
	return unit.get("flags", {}).get(FLAG_PRECISION_MELEE, false)

static func has_effect_precision_ranged(unit: Dictionary) -> bool:
	"""Check if a unit has effect-granted PRECISION for ranged attacks."""
	return unit.get("flags", {}).get(FLAG_PRECISION_RANGED, false)

static func has_effect_lethal_hits(unit: Dictionary) -> bool:
	"""Check if a unit has effect-granted Lethal Hits."""
	return unit.get("flags", {}).get(FLAG_LETHAL_HITS, false)

static func has_effect_sustained_hits(unit: Dictionary) -> bool:
	"""Check if a unit has effect-granted Sustained Hits."""
	return unit.get("flags", {}).get(FLAG_SUSTAINED_HITS, false)

static func has_effect_devastating_wounds(unit: Dictionary) -> bool:
	"""Check if a unit has effect-granted Devastating Wounds."""
	return unit.get("flags", {}).get(FLAG_DEVASTATING_WOUNDS, false)

static func has_effect_ignores_cover(unit: Dictionary) -> bool:
	"""Check if a unit has effect-granted Ignores Cover."""
	return unit.get("flags", {}).get(FLAG_IGNORES_COVER, false)

static func has_effect_plus_one_hit(unit: Dictionary) -> bool:
	"""Check if a unit has effect-granted +1 to hit."""
	return unit.get("flags", {}).get(FLAG_PLUS_ONE_HIT, false)

static func has_effect_minus_one_hit(unit: Dictionary) -> bool:
	"""Check if a unit has effect-granted -1 to hit."""
	return unit.get("flags", {}).get(FLAG_MINUS_ONE_HIT, false)

static func has_effect_plus_one_wound(unit: Dictionary) -> bool:
	"""Check if a unit has effect-granted +1 to wound."""
	return unit.get("flags", {}).get(FLAG_PLUS_ONE_WOUND, false)

static func has_effect_minus_one_wound(unit: Dictionary) -> bool:
	"""Check if a unit has effect-granted -1 to wound."""
	return unit.get("flags", {}).get(FLAG_MINUS_ONE_WOUND, false)

static func has_effect_worsen_ap(unit: Dictionary) -> bool:
	"""Check if a unit has effect-granted AP worsening."""
	return unit.get("flags", {}).get(FLAG_WORSEN_AP, 0) > 0

static func get_effect_worsen_ap(unit: Dictionary) -> int:
	"""Get the effect-granted AP worsen value (0 if none)."""
	return unit.get("flags", {}).get(FLAG_WORSEN_AP, 0)

static func has_effect_improve_ap(unit: Dictionary) -> bool:
	"""Check if a unit has effect-granted AP improvement."""
	return unit.get("flags", {}).get(FLAG_IMPROVE_AP, 0) > 0

static func get_effect_improve_ap(unit: Dictionary) -> int:
	"""Get the effect-granted AP improve value (0 if none)."""
	return unit.get("flags", {}).get(FLAG_IMPROVE_AP, 0)

static func has_effect_minus_damage(unit: Dictionary) -> bool:
	"""Check if a unit has effect-granted damage reduction."""
	return unit.get("flags", {}).get(FLAG_MINUS_DAMAGE, 0) > 0

static func get_effect_minus_damage(unit: Dictionary) -> int:
	"""Get the effect-granted damage reduction value (0 if none)."""
	return unit.get("flags", {}).get(FLAG_MINUS_DAMAGE, 0)

static func has_effect_crit_hit_on(unit: Dictionary) -> bool:
	"""Check if a unit has effect-granted critical hit threshold."""
	return unit.get("flags", {}).get(FLAG_CRIT_HIT_ON, 0) > 0

static func get_effect_crit_hit_on(unit: Dictionary) -> int:
	"""Get the effect-granted critical hit threshold (0 if none, e.g., 5 means 5+)."""
	return unit.get("flags", {}).get(FLAG_CRIT_HIT_ON, 0)

static func has_effect_fall_back_and_shoot(unit: Dictionary) -> bool:
	"""Check if a unit has effect-granted fall back and shoot eligibility."""
	return unit.get("flags", {}).get(FLAG_FALL_BACK_AND_SHOOT, false)

static func has_effect_fall_back_and_charge(unit: Dictionary) -> bool:
	"""Check if a unit has effect-granted fall back and charge eligibility."""
	return unit.get("flags", {}).get(FLAG_FALL_BACK_AND_CHARGE, false)

static func has_effect_advance_and_charge(unit: Dictionary) -> bool:
	"""Check if a unit has effect-granted advance and charge eligibility."""
	return unit.get("flags", {}).get(FLAG_ADVANCE_AND_CHARGE, false)

static func has_effect_advance_and_shoot(unit: Dictionary) -> bool:
	"""Check if a unit has effect-granted advance and shoot eligibility."""
	return unit.get("flags", {}).get(FLAG_ADVANCE_AND_SHOOT, false)

static func has_any_effect_flag(unit: Dictionary) -> bool:
	"""Check if a unit has any effect flags set."""
	var flags = unit.get("flags", {})
	for key in flags:
		if key.begins_with("effect_"):
			return true
	return false

static func clear_all_effect_flags(unit_flags: Dictionary) -> void:
	"""Remove all effect_* flags from a unit's flags dictionary."""
	var to_remove: Array = []
	for key in unit_flags:
		if key.begins_with("effect_"):
			to_remove.append(key)
	for key in to_remove:
		unit_flags.erase(key)

# ============================================================================
# EFFECT CLASSIFICATION
# ============================================================================

static func is_instant_effect(effect_type: String) -> bool:
	"""Check if an effect type is instant (executed immediately, no persistent flags)."""
	return effect_type in _INSTANT_EFFECTS

static func is_persistent_effect(effect_type: String) -> bool:
	"""Check if an effect type sets persistent flags on a unit."""
	return not is_instant_effect(effect_type) and (
		_EFFECT_FLAG_MAP.has(effect_type) or
		effect_type == GRANT_KEYWORD or
		effect_type == GRANT_PRECISION
	)

static func get_all_persistent_flag_names() -> Array:
	"""Get all possible effect flag names. Useful for comprehensive cleanup."""
	return [
		FLAG_INVULN, FLAG_COVER, FLAG_STEALTH, FLAG_FNP,
		FLAG_PRECISION_MELEE, FLAG_PRECISION_RANGED,
		FLAG_LETHAL_HITS, FLAG_SUSTAINED_HITS, FLAG_DEVASTATING_WOUNDS,
		FLAG_IGNORES_COVER, FLAG_LANCE, FLAG_TWIN_LINKED,
		FLAG_PLUS_ONE_HIT, FLAG_MINUS_ONE_HIT,
		FLAG_PLUS_ONE_WOUND, FLAG_MINUS_ONE_WOUND,
		FLAG_REROLL_HITS, FLAG_REROLL_WOUNDS, FLAG_REROLL_SAVES,
		FLAG_IMPROVE_AP, FLAG_WORSEN_AP,
		FLAG_PLUS_DAMAGE, FLAG_MINUS_DAMAGE,
		FLAG_CRIT_HIT_ON, FLAG_CRIT_WOUND_ON,
		FLAG_FALL_BACK_AND_SHOOT, FLAG_FALL_BACK_AND_CHARGE,
		FLAG_ADVANCE_AND_CHARGE, FLAG_ADVANCE_AND_SHOOT,
	]
