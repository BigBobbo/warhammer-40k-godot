class_name AIAbilityAnalyzer
extends RefCounted

# AIAbilityAnalyzer - Static utility class for AI ability awareness
#
# Provides pure-data analysis of unit abilities, leader bonuses, and special
# rules to help the AI make better tactical decisions. All methods are static
# and work from snapshot data — no scene tree access needed.
#
# Key capabilities:
# 1. Read and parse unit abilities from meta.abilities (String + Dictionary)
# 2. Detect leader bonuses from attached characters (e.g. +1 hit, reroll hits)
# 3. Detect "Fall Back and X" / "Advance and X" abilities for movement decisions
# 4. Detect Feel No Pain, Stealth, Lone Operative for defensive scoring
# 5. Compute offensive/defensive ability multipliers for AI scoring pipeline
#
# This class references UnitAbilityManager.ABILITY_EFFECTS for known ability
# definitions but does NOT depend on the scene tree or autoload instances.

# Preload the ability lookup table from UnitAbilityManager
const UnitAbilityManagerData = preload("res://autoloads/UnitAbilityManager.gd")

# Cache of ability effects table (loaded once from UnitAbilityManager)
static var _ability_effects_cache: Dictionary = {}

# ============================================================================
# ABILITY EFFECTS TABLE ACCESS
# ============================================================================

static func _get_ability_effects() -> Dictionary:
	"""Get the ABILITY_EFFECTS lookup table. Uses cache after first access."""
	if _ability_effects_cache.is_empty():
		# Access the const directly from the script resource
		_ability_effects_cache = UnitAbilityManagerData.ABILITY_EFFECTS
	return _ability_effects_cache

# ============================================================================
# ABILITY PARSING
# ============================================================================

static func get_ability_names(unit: Dictionary) -> Array:
	"""Extract all ability names from a unit's meta.abilities.
	Handles both String and Dictionary formats, skipping 'Core' entries."""
	var names = []
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var name = _extract_ability_name(ability)
		if name != "" and name != "Core":
			names.append(name)
	return names

static func get_ability_descriptions(unit: Dictionary) -> Dictionary:
	"""Get a map of ability_name -> description for all abilities on a unit."""
	var result = {}
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		if ability is Dictionary:
			var name = ability.get("name", "")
			var desc = ability.get("description", "")
			if name != "" and name != "Core":
				result[name] = desc
	return result

static func unit_has_ability(unit: Dictionary, ability_name: String) -> bool:
	"""Check if a unit has a specific ability by name (case-sensitive)."""
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var name = _extract_ability_name(ability)
		if name == ability_name:
			return true
	return false

static func unit_has_ability_containing(unit: Dictionary, text: String) -> bool:
	"""Check if a unit has any ability whose name or description contains text (case-insensitive)."""
	var lower_text = text.to_lower()
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var name = _extract_ability_name(ability).to_lower()
		if name.contains(lower_text):
			return true
		if ability is Dictionary:
			var desc = ability.get("description", "").to_lower()
			if desc.contains(lower_text):
				return true
	return false

static func _extract_ability_name(ability) -> String:
	"""Extract ability name from either String or Dictionary format."""
	if ability is String:
		return ability
	elif ability is Dictionary:
		return ability.get("name", "")
	return ""

# ============================================================================
# LEADER BONUS DETECTION
# ============================================================================

static func get_leader_bonuses(unit_id: String, unit: Dictionary, all_units: Dictionary) -> Dictionary:
	"""Analyze all leader bonuses affecting a unit from attached characters.

	Returns a dictionary with combined bonus info:
	{
		"has_leader": bool,
		"leader_names": Array[String],
		"hit_bonus_melee": int,      # +N to melee hit rolls
		"hit_bonus_ranged": int,     # +N to ranged hit rolls
		"wound_bonus_melee": int,    # +N to melee wound rolls
		"wound_bonus_ranged": int,   # +N to ranged wound rolls
		"reroll_hits_melee": String, # "none", "ones", "failed", "all"
		"reroll_hits_ranged": String,
		"reroll_wounds_melee": String,
		"reroll_wounds_ranged": String,
		"has_fnp": int,              # FNP value from leader (0 = none)
		"has_cover": bool,           # Leader grants cover
		"fall_back_and_charge": bool,
		"fall_back_and_shoot": bool,
		"advance_and_charge": bool,
		"advance_and_shoot": bool,
		"abilities": Array[Dictionary] # Raw matched abilities with details
	}"""
	var bonuses = _empty_leader_bonuses()

	var attachment_data = unit.get("attachment_data", {})
	var attached_characters = attachment_data.get("attached_characters", [])

	if attached_characters.is_empty():
		return bonuses

	var ability_effects = _get_ability_effects()

	for char_id in attached_characters:
		var char_unit = all_units.get(char_id, {})
		if char_unit.is_empty():
			continue

		# Character must have alive models
		if not _has_alive_models(char_unit):
			continue

		var char_name = char_unit.get("meta", {}).get("name", char_id)
		bonuses["has_leader"] = true
		bonuses["leader_names"].append(char_name)

		var abilities = char_unit.get("meta", {}).get("abilities", [])
		for ability in abilities:
			var ability_name = _extract_ability_name(ability)
			if ability_name == "" or ability_name == "Core":
				continue

			# Check the effects table for known abilities
			var effect_def = ability_effects.get(ability_name, {})
			if effect_def.is_empty():
				# Not in lookup table -- try description-based detection
				if ability is Dictionary:
					_detect_from_description(ability, bonuses)
				continue

			if effect_def.get("condition", "") != "while_leading":
				continue
			if not effect_def.get("implemented", false):
				continue

			var attack_type = effect_def.get("attack_type", "all")
			var effects = effect_def.get("effects", [])

			for effect in effects:
				var etype = effect.get("type", "")
				_apply_bonus_from_effect(etype, effect, attack_type, bonuses)

			bonuses["abilities"].append({
				"name": ability_name,
				"source": char_name,
				"attack_type": attack_type,
				"effects": effects
			})

	return bonuses

static func _empty_leader_bonuses() -> Dictionary:
	return {
		"has_leader": false,
		"leader_names": [],
		"hit_bonus_melee": 0,
		"hit_bonus_ranged": 0,
		"wound_bonus_melee": 0,
		"wound_bonus_ranged": 0,
		"reroll_hits_melee": "none",
		"reroll_hits_ranged": "none",
		"reroll_wounds_melee": "none",
		"reroll_wounds_ranged": "none",
		"has_fnp": 0,
		"has_cover": false,
		"fall_back_and_charge": false,
		"fall_back_and_shoot": false,
		"advance_and_charge": false,
		"advance_and_shoot": false,
		"abilities": []
	}

static func _apply_bonus_from_effect(etype: String, effect: Dictionary, attack_type: String, bonuses: Dictionary) -> void:
	"""Apply a single effect to the bonuses dictionary based on its type."""
	match etype:
		"plus_one_hit":
			if attack_type in ["melee", "all"]:
				bonuses["hit_bonus_melee"] += 1
			if attack_type in ["ranged", "all"]:
				bonuses["hit_bonus_ranged"] += 1
		"plus_one_wound":
			if attack_type in ["melee", "all"]:
				bonuses["wound_bonus_melee"] += 1
			if attack_type in ["ranged", "all"]:
				bonuses["wound_bonus_ranged"] += 1
		"reroll_hits":
			var scope = effect.get("scope", "ones")
			if attack_type in ["melee", "all"]:
				bonuses["reroll_hits_melee"] = _best_reroll(bonuses["reroll_hits_melee"], scope)
			if attack_type in ["ranged", "all"]:
				bonuses["reroll_hits_ranged"] = _best_reroll(bonuses["reroll_hits_ranged"], scope)
		"reroll_wounds":
			var scope = effect.get("scope", "ones")
			if attack_type in ["melee", "all"]:
				bonuses["reroll_wounds_melee"] = _best_reroll(bonuses["reroll_wounds_melee"], scope)
			if attack_type in ["ranged", "all"]:
				bonuses["reroll_wounds_ranged"] = _best_reroll(bonuses["reroll_wounds_ranged"], scope)
		"grant_fnp":
			var value = int(effect.get("value", 0))
			if value > 0:
				if bonuses["has_fnp"] == 0 or value < bonuses["has_fnp"]:
					bonuses["has_fnp"] = value
		"grant_cover":
			bonuses["has_cover"] = true
		"fall_back_and_charge":
			bonuses["fall_back_and_charge"] = true
		"fall_back_and_shoot":
			bonuses["fall_back_and_shoot"] = true
		"advance_and_charge":
			bonuses["advance_and_charge"] = true
		"advance_and_shoot":
			bonuses["advance_and_shoot"] = true

static func _best_reroll(current: String, new_scope: String) -> String:
	"""Return the better (broader) reroll scope."""
	var priority = {"none": 0, "ones": 1, "failed": 2, "all": 3}
	var current_p = priority.get(current, 0)
	var new_p = priority.get(new_scope, 0)
	return new_scope if new_p > current_p else current

static func _detect_from_description(ability: Dictionary, bonuses: Dictionary) -> void:
	"""Fallback: detect ability effects from description text when not in the lookup table."""
	var desc = ability.get("description", "").to_lower()
	if desc.is_empty():
		return

	# Fall back and charge detection
	if "fall back" in desc and "charge" in desc:
		bonuses["fall_back_and_charge"] = true
	# Fall back and shoot detection
	if "fall back" in desc and "shoot" in desc:
		bonuses["fall_back_and_shoot"] = true
	# Advance and charge detection
	if "advance" in desc and "charge" in desc:
		bonuses["advance_and_charge"] = true
	# Advance and shoot detection (without penalty)
	if "advance" in desc and "shoot" in desc:
		bonuses["advance_and_shoot"] = true

# ============================================================================
# FALL BACK AND X / ADVANCE AND X DETECTION
# ============================================================================

static func can_fall_back_and_charge(unit_id: String, unit: Dictionary, all_units: Dictionary) -> bool:
	"""Check if a unit can charge after falling back (from leader or own abilities)."""
	# Check unit's own abilities
	if _unit_has_fall_back_ability(unit, "charge"):
		return true
	# Check effect flags (set by UnitAbilityManager during movement phase)
	if unit.get("flags", {}).get("effect_fall_back_and_charge", false):
		return true
	# Check leader abilities
	var bonuses = get_leader_bonuses(unit_id, unit, all_units)
	return bonuses["fall_back_and_charge"]

static func can_fall_back_and_shoot(unit_id: String, unit: Dictionary, all_units: Dictionary) -> bool:
	"""Check if a unit can shoot after falling back (from leader or own abilities)."""
	if _unit_has_fall_back_ability(unit, "shoot"):
		return true
	if unit.get("flags", {}).get("effect_fall_back_and_shoot", false):
		return true
	var bonuses = get_leader_bonuses(unit_id, unit, all_units)
	return bonuses["fall_back_and_shoot"]

static func can_advance_and_charge(unit_id: String, unit: Dictionary, all_units: Dictionary) -> bool:
	"""Check if a unit can charge after advancing."""
	if _unit_has_advance_ability(unit, "charge"):
		return true
	if unit.get("flags", {}).get("effect_advance_and_charge", false):
		return true
	var bonuses = get_leader_bonuses(unit_id, unit, all_units)
	return bonuses["advance_and_charge"]

static func can_advance_and_shoot(unit_id: String, unit: Dictionary, all_units: Dictionary) -> bool:
	"""Check if a unit can shoot without penalty after advancing."""
	if _unit_has_advance_ability(unit, "shoot"):
		return true
	if unit.get("flags", {}).get("effect_advance_and_shoot", false):
		return true
	var bonuses = get_leader_bonuses(unit_id, unit, all_units)
	return bonuses["advance_and_shoot"]

static func _unit_has_fall_back_ability(unit: Dictionary, action: String) -> bool:
	"""Check if the unit itself (not leader) has a Fall Back and X ability."""
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var name = _extract_ability_name(ability).to_lower()
		if "fall back" in name and action.to_lower() in name:
			return true
		if ability is Dictionary:
			var desc = ability.get("description", "").to_lower()
			if "fall back" in desc and action.to_lower() in desc:
				# Also check the effects table
				var ability_name = ability.get("name", "")
				var effect_def = _get_ability_effects().get(ability_name, {})
				if not effect_def.is_empty():
					for effect in effect_def.get("effects", []):
						if effect.get("type", "") == ("fall_back_and_%s" % action.to_lower()):
							return true
				# Description-based fallback
				return true
	return false

static func _unit_has_advance_ability(unit: Dictionary, action: String) -> bool:
	"""Check if the unit itself has an Advance and X ability."""
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var name = _extract_ability_name(ability).to_lower()
		if "advance" in name and action.to_lower() in name:
			return true
		if ability is Dictionary:
			var desc = ability.get("description", "").to_lower()
			if "advance" in desc and action.to_lower() in desc:
				var ability_name = ability.get("name", "")
				var effect_def = _get_ability_effects().get(ability_name, {})
				if not effect_def.is_empty():
					for effect in effect_def.get("effects", []):
						if effect.get("type", "") == ("advance_and_%s" % action.to_lower()):
							return true
				return true
	return false

# ============================================================================
# DEFENSIVE ABILITY DETECTION
# ============================================================================

static func get_unit_fnp(unit: Dictionary) -> int:
	"""Get a unit's Feel No Pain value (0 = none). Checks stats, flags, and leader bonuses."""
	# Check base stats
	var base_fnp = int(unit.get("meta", {}).get("stats", {}).get("fnp", 0))
	# Check effect flags (stratagem/ability granted)
	var flags = unit.get("flags", {})
	var effect_fnp = int(flags.get("effect_fnp", 0))
	# Use best (lowest non-zero)
	var best = 0
	if base_fnp > 0 and effect_fnp > 0:
		best = mini(base_fnp, effect_fnp)
	elif base_fnp > 0:
		best = base_fnp
	elif effect_fnp > 0:
		best = effect_fnp
	return best

static func get_fnp_damage_multiplier(fnp_value: int) -> float:
	"""Convert a FNP value to a damage reduction multiplier.
	FNP 5+ means each wound has 2/6 chance of being ignored -> 4/6 damage gets through.
	Returns 1.0 if no FNP."""
	if fnp_value <= 0 or fnp_value > 6:
		return 1.0
	# Probability of NOT passing FNP = (fnp_value - 1) / 6
	return float(fnp_value - 1) / 6.0

static func has_stealth(unit: Dictionary) -> bool:
	"""Check if a unit has the Stealth ability (imposes -1 to hit for ranged attacks)."""
	# Check effect flags first
	if unit.get("flags", {}).get("effect_stealth", false):
		return true
	# Check abilities
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var name = _extract_ability_name(ability).to_lower()
		if name == "stealth":
			return true
	return false

static func has_lone_operative(unit: Dictionary) -> bool:
	"""Check if a unit has the Lone Operative ability (can only be targeted within 12\")."""
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var name = _extract_ability_name(ability).to_lower()
		if name == "lone operative":
			return true
	return false

static func is_lone_operative_protected(unit: Dictionary) -> bool:
	"""Check if a Lone Operative unit is actually protected (not attached to a bodyguard)."""
	if not has_lone_operative(unit):
		return false
	# Lone Operative protection is lost when the character joins a unit
	var attached_to = unit.get("attached_to", null)
	if attached_to != null:
		return false
	var attached_chars = unit.get("attachment_data", {}).get("attached_characters", [])
	if not attached_chars.is_empty():
		return false
	return true

# ============================================================================
# OFFENSIVE ABILITY MULTIPLIERS FOR AI SCORING
# ============================================================================

static func get_offensive_multiplier_ranged(unit_id: String, unit: Dictionary, all_units: Dictionary) -> float:
	"""Calculate a multiplier representing offensive ability bonuses for ranged attacks.
	Used by the AI to adjust expected damage when scoring shooting targets.

	The multiplier accounts for:
	- Leader-granted +1 hit (improves hit probability)
	- Leader-granted reroll hits (improves hit probability)
	- Leader-granted +1 wound (improves wound probability)
	- Leader-granted reroll wounds (improves wound probability)

	Returns a float >= 1.0 (bonuses only improve, never penalize)."""
	var bonuses = get_leader_bonuses(unit_id, unit, all_units)

	var multiplier = 1.0

	# +1 to hit improves hit probability significantly
	# Average improvement: from BS4+ (50%) to BS3+ (67%) = +33% relative
	if bonuses["hit_bonus_ranged"] > 0:
		multiplier *= 1.0 + (0.25 * bonuses["hit_bonus_ranged"])

	# Reroll hits (ranged)
	match bonuses["reroll_hits_ranged"]:
		"ones":
			multiplier *= 1.10  # ~10% improvement (reroll 1/6 of rolls)
		"failed":
			multiplier *= 1.30  # ~30% improvement for typical BS4+
		"all":
			multiplier *= 1.35  # ~35% improvement

	# +1 to wound
	if bonuses["wound_bonus_ranged"] > 0:
		multiplier *= 1.0 + (0.20 * bonuses["wound_bonus_ranged"])

	# Reroll wounds (ranged)
	match bonuses["reroll_wounds_ranged"]:
		"ones":
			multiplier *= 1.08
		"failed":
			multiplier *= 1.25
		"all":
			multiplier *= 1.30

	return multiplier

static func get_offensive_multiplier_melee(unit_id: String, unit: Dictionary, all_units: Dictionary) -> float:
	"""Calculate a multiplier representing offensive ability bonuses for melee attacks.
	Same as ranged but uses melee-specific leader bonuses."""
	var bonuses = get_leader_bonuses(unit_id, unit, all_units)

	var multiplier = 1.0

	# +1 to hit (melee)
	if bonuses["hit_bonus_melee"] > 0:
		multiplier *= 1.0 + (0.25 * bonuses["hit_bonus_melee"])

	# Reroll hits (melee)
	match bonuses["reroll_hits_melee"]:
		"ones":
			multiplier *= 1.10
		"failed":
			multiplier *= 1.30
		"all":
			multiplier *= 1.35

	# +1 to wound (melee)
	if bonuses["wound_bonus_melee"] > 0:
		multiplier *= 1.0 + (0.20 * bonuses["wound_bonus_melee"])

	# Reroll wounds (melee)
	match bonuses["reroll_wounds_melee"]:
		"ones":
			multiplier *= 1.08
		"failed":
			multiplier *= 1.25
		"all":
			multiplier *= 1.30

	return multiplier

static func get_defensive_multiplier(unit_id: String, unit: Dictionary, all_units: Dictionary) -> float:
	"""Calculate a multiplier representing how much harder a unit is to kill due to abilities.
	Used to estimate effective durability when the AI evaluates whether to charge/engage a target.

	Returns a float >= 1.0 (higher = harder to kill).

	Accounts for:
	- Feel No Pain (reduces damage taken)
	- Stealth (-1 to ranged hit rolls)
	- Leader-granted cover (improves save by 1)
	- Leader-granted FNP"""
	var multiplier = 1.0

	# FNP from any source (stats, flags, or leaders)
	var fnp = get_unit_fnp(unit)
	# Also check leader-granted FNP
	var bonuses = get_leader_bonuses(unit_id, unit, all_units)
	var leader_fnp = bonuses["has_fnp"]
	if leader_fnp > 0 and (fnp == 0 or leader_fnp < fnp):
		fnp = leader_fnp

	if fnp > 0:
		# FNP X+ means each wound has (7 - X)/6 chance of being ignored
		var fnp_save_chance = float(7 - fnp) / 6.0
		# Effective HP multiplier: 1 / (1 - fnp_save_chance)
		multiplier *= 1.0 / (1.0 - fnp_save_chance)

	# Stealth: -1 to hit ranged attacks -> roughly 15-20% fewer hits
	if has_stealth(unit):
		multiplier *= 1.15

	# Leader-granted cover: improves save by 1 -> roughly 15% more saves
	if bonuses["has_cover"]:
		multiplier *= 1.15

	return multiplier

# ============================================================================
# COMPREHENSIVE UNIT ABILITY PROFILE FOR AI DECISIONS
# ============================================================================

static func get_unit_ability_profile(unit_id: String, unit: Dictionary, all_units: Dictionary) -> Dictionary:
	"""Build a comprehensive ability profile for a unit for AI decision-making.

	Returns a dictionary summarizing everything the AI needs to know:
	{
		"abilities": Array[String],          # All ability names on this unit
		"leader_bonuses": Dictionary,        # Full leader bonus info
		"can_fall_back_and_charge": bool,
		"can_fall_back_and_shoot": bool,
		"can_advance_and_charge": bool,
		"can_advance_and_shoot": bool,
		"has_fnp": int,                      # Best FNP value (0 = none)
		"has_stealth": bool,
		"has_lone_operative": bool,
		"lone_operative_protected": bool,
		"offensive_mult_ranged": float,
		"offensive_mult_melee": float,
		"defensive_mult": float
	}"""
	var bonuses = get_leader_bonuses(unit_id, unit, all_units)
	var profile = {
		"abilities": get_ability_names(unit),
		"leader_bonuses": bonuses,
		"can_fall_back_and_charge": can_fall_back_and_charge(unit_id, unit, all_units),
		"can_fall_back_and_shoot": can_fall_back_and_shoot(unit_id, unit, all_units),
		"can_advance_and_charge": can_advance_and_charge(unit_id, unit, all_units),
		"can_advance_and_shoot": can_advance_and_shoot(unit_id, unit, all_units),
		"has_fnp": get_unit_fnp(unit),
		"has_stealth": has_stealth(unit),
		"has_lone_operative": has_lone_operative(unit),
		"lone_operative_protected": is_lone_operative_protected(unit),
		"offensive_mult_ranged": get_offensive_multiplier_ranged(unit_id, unit, all_units),
		"offensive_mult_melee": get_offensive_multiplier_melee(unit_id, unit, all_units),
		"defensive_mult": get_defensive_multiplier(unit_id, unit, all_units),
	}

	# Merge leader FNP if better than unit FNP
	if bonuses["has_fnp"] > 0 and (profile["has_fnp"] == 0 or bonuses["has_fnp"] < profile["has_fnp"]):
		profile["has_fnp"] = bonuses["has_fnp"]

	return profile

# ============================================================================
# HELPERS
# ============================================================================

static func _has_alive_models(unit: Dictionary) -> bool:
	"""Check if a unit has at least one alive model."""
	for model in unit.get("models", []):
		if model.get("alive", true):
			return true
	return false
