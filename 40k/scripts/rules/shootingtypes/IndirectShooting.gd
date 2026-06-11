class_name IndirectShooting
extends ShootingType

## 10.07 — ELIGIBLE IF: unengaged, did not advance, has [INDIRECT FIRE]
## weapons. WHILE: [INDIRECT FIRE] weapons may target non-visible units;
## per attack the target has the benefit of cover, hit rolls cannot be
## re-rolled, and unmodified 1-5 fails (1-3 if the unit remained
## stationary AND the target is visible to a friendly spotter unit).

func _init():
	id = "indirect"
	display_name = "Indirect Shooting"


func eligible(unit_id: String, board: Dictionary) -> Dictionary:
	if GameConstants.edition < 11:
		return {"eligible": false, "reasons": ["11e shooting types"]}
	var unit = _unit(unit_id, board)
	var reasons: Array = []
	if _engaged(unit_id, board):
		reasons.append("unit is engaged (10.07)")
	if _advanced(unit):
		reasons.append("unit made an advance move this turn (10.07)")
	if not _unit_has_weapon_with(unit, "indirect_fire"):
		reasons.append("no [INDIRECT FIRE] weapons (10.07)")
	return {"eligible": reasons.is_empty(), "reasons": reasons}


func hit_consequences(weapon_profile: Dictionary, unit_id: String, target_id: String, board: Dictionary) -> Dictionary:
	var out = super.hit_consequences(weapon_profile, unit_id, target_id, board)
	if not _weapon_has(weapon_profile, "indirect_fire"):
		return out
	out.grants_target_cover = true
	out.no_hit_rerolls = true
	out.fail_band = 5
	var unit = _unit(unit_id, board)
	if unit.get("flags", {}).get("remained_stationary", false) \
			and has_spotter(unit_id, target_id, board):
		out.fail_band = 3
	return out


## A friendly unit (other than the shooter) to which the target is
## visible (10.07's spotter condition).
func has_spotter(unit_id: String, target_id: String, board: Dictionary) -> bool:
	var rules = _rules()
	var owner = int(_unit(unit_id, board).get("owner", 0))
	for other_id in board.get("units", {}):
		if other_id == unit_id:
			continue
		var other = board.units[other_id]
		if int(other.get("owner", 0)) != owner:
			continue
		var any_alive := false
		for m in other.get("models", []):
			if m.get("alive", true):
				any_alive = true
				break
		if not any_alive:
			continue
		if rules._has_los_to_target_unit(other_id, target_id, board):
			return true
	return false
