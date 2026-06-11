class_name NormalMove
extends MoveType

## 09.05 NORMAL MOVE — max distance M; eligible if on the battlefield and
## unengaged; must end unengaged.

func _init():
	id = "normal"
	display_name = "Normal Move"

func eligible(unit_id: String, board: Dictionary) -> Dictionary:
	var unit = _unit(board, unit_id)
	if unit.is_empty() or not _on_battlefield(unit):
		return {"eligible": false, "reasons": ["unit not on the battlefield"]}
	if _rules().is_unit_engaged(unit_id, board):
		return {"eligible": false, "reasons": ["unit is engaged"]}
	return {"eligible": true, "reasons": []}

func max_distance_inches(unit: Dictionary, _context: Dictionary) -> float:
	return float(unit.get("meta", {}).get("stats", {}).get("move", 0))

func after_moving_conditions(unit_id: String, board: Dictionary, context: Dictionary) -> Dictionary:
	var base = super.after_moving_conditions(unit_id, board, context)
	if not base.ok:
		return base
	# 09.05 AFTER MOVING: your unit must be unengaged.
	if _rules().is_unit_engaged(unit_id, board):
		return {"ok": false, "violations": ["unit must end a normal move unengaged"]}
	return {"ok": true, "violations": []}

func after_moving_effects(unit_id: String, _context: Dictionary) -> Array:
	return [{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "moved"), "value": true}]
