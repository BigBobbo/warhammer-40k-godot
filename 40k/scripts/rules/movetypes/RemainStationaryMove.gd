class_name RemainStationaryMove
extends MoveType

## 09.04 REMAIN STATIONARY — eligible for any unit; no models move; does
## not trigger start/end-of-move rules.

func _init():
	id = "remain_stationary"
	display_name = "Remain Stationary"

func eligible(unit_id: String, board: Dictionary) -> Dictionary:
	if _unit(board, unit_id).is_empty():
		return {"eligible": false, "reasons": ["unknown unit"]}
	return {"eligible": true, "reasons": []}

func max_distance_inches(_unit: Dictionary, _context: Dictionary) -> float:
	return 0.0

func after_moving_conditions(_unit_id: String, _board: Dictionary, _context: Dictionary) -> Dictionary:
	# 09.04: no models are moved, so no end-of-move conditions apply.
	return {"ok": true, "violations": []}

func after_moving_effects(unit_id: String, _context: Dictionary) -> Array:
	return [{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "remained_stationary"), "value": true}]
