class_name UnitAbilities
extends RefCounted

## Unified unit-ability queries (ISS-019).
##
## RulesEngine previously string-searched `meta.abilities` inline in ~30
## places, each blind to dynamically GRANTED abilities (EffectPrimitives
## flags set by stratagems/auras). This is the single query surface:
## datasheet abilities AND effect-granted ones answer through one call.
##
## `effect_flag` maps an ability name to the EffectPrimitives flag that
## grants it dynamically (extend the table as abilities gain dynamic
## sources).

const _EFFECT_FLAGS := {
	"stealth": "effect_stealth",
	"lone operative": "effect_lone_operative",
}


## True if the unit has the named ability — from its datasheet
## (`meta.abilities`, String or {name: ...} entries, case-insensitive) or
## granted dynamically via the corresponding effect flag.
static func unit_has(unit: Dictionary, ability_name: String) -> bool:
	var wanted := ability_name.to_lower()
	if has_datasheet_ability(unit, wanted):
		return true
	var flag = _EFFECT_FLAGS.get(wanted, "")
	if flag != "" and unit.get("flags", {}).get(flag, false):
		return true
	return false


## Datasheet-only check (no dynamic grants).
static func has_datasheet_ability(unit: Dictionary, ability_name: String) -> bool:
	var wanted := ability_name.to_lower()
	for ability in unit.get("meta", {}).get("abilities", []):
		var n := ""
		if ability is String:
			n = ability
		elif ability is Dictionary:
			n = str(ability.get("name", ""))
		if n.to_lower() == wanted:
			return true
	return false
