class_name NormalShooting
extends ShootingType

## 10.04 — ELIGIBLE IF: unengaged and did not advance this turn.

func _init():
	id = "normal"
	display_name = "Normal Shooting"


func eligible(unit_id: String, board: Dictionary) -> Dictionary:
	if GameConstants.edition < 11:
		return {"eligible": false, "reasons": ["11e shooting types"]}
	var reasons: Array = []
	if _engaged(unit_id, board):
		reasons.append("unit is engaged (10.04)")
	if _advanced(_unit(unit_id, board)):
		reasons.append("unit made an advance move this turn (10.04)")
	return {"eligible": reasons.is_empty(), "reasons": reasons}
