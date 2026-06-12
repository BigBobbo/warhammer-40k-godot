class_name AssaultShooting
extends ShootingType

## 10.05 — ELIGIBLE IF: unengaged, advanced this turn, has [ASSAULT]
## weapons. WHILE: only [ASSAULT] weapons may be selected.

func _init():
	id = "assault"
	display_name = "Assault Shooting"


func eligible(unit_id: String, board: Dictionary) -> Dictionary:
	if GameConstants.edition < 11:
		return {"eligible": false, "reasons": ["11e shooting types"]}
	var unit = _unit(unit_id, board)
	var reasons: Array = []
	if _engaged(unit_id, board):
		reasons.append("unit is engaged (10.05)")
	if not _advanced(unit):
		reasons.append("unit did not make an advance move this turn (10.05)")
	if not _unit_has_weapon_with(unit, "assault"):
		reasons.append("no [ASSAULT] weapons (10.05)")
	if _unit(unit_id, board).get("flags", {}).get("cannot_shoot", false):
		reasons.append("unit cannot shoot (performing an action, 16.01)")
	return {"eligible": reasons.is_empty(), "reasons": reasons}


func weapon_allowed(weapon_profile: Dictionary, _unit: Dictionary, _board: Dictionary) -> Dictionary:
	if not _weapon_has(weapon_profile, "assault"):
		return {"allowed": false, "reason": "only [ASSAULT] weapons after advancing (10.05)"}
	return {"allowed": true, "reason": ""}
