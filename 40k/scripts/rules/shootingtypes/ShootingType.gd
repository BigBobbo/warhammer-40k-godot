class_name ShootingType
extends RefCounted

## Base class for the 11e shooting-type template (ISS-048; core rules
## 10.02, 10.04-10.07, 15.09, 17.03).
##
## In 11e a unit selected to shoot first selects ONE shooting type and
## resolves it:
##   ELIGIBLE IF / EFFECT (Making Attacks, 04) / WHILE SHOOTING
##   (weapon + target constraints, hit-roll consequences) / AFTER
##   SHOOTING (not eligible to start an action this phase).
##
## The phase asks the registry (ShootingTypes.gd) which types a unit may
## select, then enforces the WHILE constraints through:
##   eligible() -> weapon_allowed() + target_allowed() per assignment ->
##   hit_consequences() folded into the attack resolution ->
##   after_shooting_effects().
##
## [PISTOL] is identical to [CLOSE-QUARTERS] in 11e (24.27) — the weapon
## checks treat them interchangeably.

var id: String = ""
var display_name: String = ""


static func _rules() -> Node:
	return Engine.get_main_loop().root.get_node("/root/RulesEngine")


## ELIGIBLE IF — returns {eligible: bool, reasons: Array}.
func eligible(_unit_id: String, _board: Dictionary) -> Dictionary:
	return {"eligible": false, "reasons": ["not implemented"]}


## WHILE SHOOTING — may this weapon be selected to make attacks under
## this shooting type? Returns {allowed: bool, reason: String}.
func weapon_allowed(_weapon_profile: Dictionary, _unit: Dictionary, _board: Dictionary) -> Dictionary:
	return {"allowed": true, "reason": ""}


## WHILE SHOOTING — may this enemy unit be targeted with this weapon?
## Baseline (10.02/17.03): engaged enemy units are NOT eligible targets
## unless they are engaged MONSTER/VEHICLE units (17.03) — and [BLAST]
## weapons can never target units engaged with the attacker (24.04).
func target_allowed(unit_id: String, target_id: String, weapon_profile: Dictionary, board: Dictionary) -> Dictionary:
	var rules = _rules()
	var target = board.get("units", {}).get(target_id, {})
	if rules.is_unit_engaged(target_id, board):
		if not _is_monster_or_vehicle(target):
			return {"allowed": false, "reason": "engaged non-MONSTER/VEHICLE units cannot be targeted (17.03)"}
		if _weapon_has(weapon_profile, "blast"):
			return {"allowed": false, "reason": "[BLAST] weapons cannot target engaged units (24.04)"}
	return {"allowed": true, "reason": ""}


## WHILE SHOOTING — hit-roll consequences of this type for one attack:
## {hit_roll_delta: int, fail_band: int, no_hit_rerolls: bool,
##  snap_only_6s: bool, grants_target_cover: bool}.
## fail_band -1 = default (unmodified 1 fails).
func hit_consequences(_weapon_profile: Dictionary, _unit_id: String, _target_id: String, _board: Dictionary) -> Dictionary:
	return {"hit_roll_delta": 0, "fail_band": -1, "no_hit_rerolls": false,
		"snap_only_6s": false, "grants_target_cover": false}


## AFTER SHOOTING — state diffs (10.04-10.07/15.09: the unit is not
## eligible to start an action until the end of the phase).
func after_shooting_effects(unit_id: String) -> Array:
	return [{"op": "set", "path": "units.%s.flags.cannot_start_action" % unit_id, "value": true}]


# ── shared helpers ───────────────────────────────────────────────────

func _unit(unit_id: String, board: Dictionary) -> Dictionary:
	return board.get("units", {}).get(unit_id, {})


func _advanced(unit: Dictionary) -> bool:
	return unit.get("flags", {}).get("advanced", false)


func _engaged(unit_id: String, board: Dictionary) -> bool:
	return _rules().is_unit_engaged(unit_id, board)


static func _is_monster_or_vehicle(unit: Dictionary) -> bool:
	var keywords: Array = unit.get("meta", {}).get("keywords", [])
	return "MONSTER" in keywords or "VEHICLE" in keywords


## Weapon ability check via the structured registry; at 11e [PISTOL]
## counts as [CLOSE-QUARTERS] (24.27).
static func _weapon_has(weapon_profile: Dictionary, ability_id: String) -> bool:
	var abilities: Array = AbilityRegistry.from_weapon(weapon_profile)
	if AbilityRegistry.has_ability(abilities, ability_id):
		return true
	if ability_id == "close_quarters" and AbilityRegistry.has_ability(abilities, "pistol"):
		return true
	return false


## Does the unit have at least one (alive-model) weapon with the ability?
static func _unit_has_weapon_with(unit: Dictionary, ability_id: String) -> bool:
	for weapon in unit.get("meta", {}).get("weapons", []):
		var wtype = str(weapon.get("type", "")).to_lower()
		if wtype == "melee":
			continue
		if _weapon_has(weapon, ability_id):
			return true
	return false
