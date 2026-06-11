class_name CloseQuartersShooting
extends ShootingType

## 10.06 — ELIGIBLE IF: engaged, did not advance, and has
## [CLOSE-QUARTERS] weapons ([PISTOL] counts, 24.27) or is MONSTER/
## VEHICLE. WHILE: targets the unit is engaged with become legal;
## MONSTER/VEHICLE models take -1 to hit except with CQ weapons vs an
## engaged target, and [BLAST] still cannot target engaged units;
## other models may ONLY use CQ weapons against units engaged with them.
## Replaces the 10e pistol rules and Big Guns Never Tire.

func _init():
	id = "close_quarters"
	display_name = "Close-Quarters Shooting"


func eligible(unit_id: String, board: Dictionary) -> Dictionary:
	if GameConstants.edition < 11:
		return {"eligible": false, "reasons": ["11e shooting types"]}
	var unit = _unit(unit_id, board)
	var reasons: Array = []
	if not _engaged(unit_id, board):
		reasons.append("unit is not engaged (10.06)")
	if _advanced(unit):
		reasons.append("unit made an advance move this turn (10.06)")
	if not (_unit_has_weapon_with(unit, "close_quarters") or _is_monster_or_vehicle(unit)):
		reasons.append("no [CLOSE-QUARTERS] weapons and not MONSTER/VEHICLE (10.06)")
	return {"eligible": reasons.is_empty(), "reasons": reasons}


func weapon_allowed(weapon_profile: Dictionary, unit: Dictionary, _board: Dictionary) -> Dictionary:
	if _is_monster_or_vehicle(unit):
		return {"allowed": true, "reason": ""}
	if not _weapon_has(weapon_profile, "close_quarters"):
		return {"allowed": false, "reason": "non-MONSTER/VEHICLE models may only use [CLOSE-QUARTERS] weapons (10.06)"}
	return {"allowed": true, "reason": ""}


func target_allowed(unit_id: String, target_id: String, weapon_profile: Dictionary, board: Dictionary) -> Dictionary:
	var rules = _rules()
	var unit = _unit(unit_id, board)
	var target = board.get("units", {}).get(target_id, {})
	var engaged_with = rules.check_units_in_engagement_range(unit, target, board)
	if _is_monster_or_vehicle(unit):
		# 10.06: BLAST still cannot target a unit the shooter is engaged with.
		if engaged_with and _weapon_has(weapon_profile, "blast"):
			return {"allowed": false, "reason": "[BLAST] cannot target a unit this unit is engaged with (10.06)"}
		if not engaged_with:
			# Other targets follow the baseline rules (incl. 17.03).
			return super.target_allowed(unit_id, target_id, weapon_profile, board)
		return {"allowed": true, "reason": ""}
	# Non-M/V models: only units engaged with this unit.
	if not engaged_with:
		return {"allowed": false, "reason": "non-MONSTER/VEHICLE models may only target units engaged with this unit (10.06)"}
	if _weapon_has(weapon_profile, "blast"):
		return {"allowed": false, "reason": "[BLAST] cannot target engaged units (24.04)"}
	return {"allowed": true, "reason": ""}


func hit_consequences(weapon_profile: Dictionary, unit_id: String, target_id: String, board: Dictionary) -> Dictionary:
	var out = super.hit_consequences(weapon_profile, unit_id, target_id, board)
	var unit = _unit(unit_id, board)
	if _is_monster_or_vehicle(unit):
		var engaged_with = _rules().check_units_in_engagement_range(unit, board.get("units", {}).get(target_id, {}), board)
		if not (_weapon_has(weapon_profile, "close_quarters") and engaged_with):
			out.hit_roll_delta -= 1  # 10.06 MONSTER/VEHICLE penalty
	return out
