class_name AdvanceMove
extends MoveType

## 09.06 ADVANCE MOVE — BEFORE: advance roll (D6); max distance M + roll;
## must end unengaged; AFTER: until end of turn not eligible to declare a
## charge (both editions), to shoot non-ASSAULT weapons (10e wording /
## 11e assault-shooting gate) or — 11e — to start an action.

func _init():
	id = "advance"
	display_name = "Advance"

func eligible(unit_id: String, board: Dictionary) -> Dictionary:
	var unit = _unit(board, unit_id)
	if unit.is_empty() or not _on_battlefield(unit):
		return {"eligible": false, "reasons": ["unit not on the battlefield"]}
	if _rules().is_unit_engaged(unit_id, board):
		return {"eligible": false, "reasons": ["unit is engaged"]}
	return {"eligible": true, "reasons": []}

func before_moving(_unit_id: String, _board: Dictionary, rng, _context: Dictionary) -> Dictionary:
	var roll: int = rng.roll_d6(1)[0]
	return {"advance_roll": roll, "dice": [{"context": "advance_roll", "rolls": [roll]}]}

func max_distance_inches(unit: Dictionary, context: Dictionary) -> float:
	return float(unit.get("meta", {}).get("stats", {}).get("move", 0)) + float(context.get("advance_roll", 0))

func after_moving_conditions(unit_id: String, board: Dictionary, context: Dictionary) -> Dictionary:
	var base = super.after_moving_conditions(unit_id, board, context)
	if not base.ok:
		return base
	if _rules().is_unit_engaged(unit_id, board):
		return {"ok": false, "violations": ["unit must end an advance unengaged"]}
	return {"ok": true, "violations": []}

func after_moving_effects(unit_id: String, _context: Dictionary) -> Array:
	var effects = [
		{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "moved"), "value": true},
		{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "advanced"), "value": true},
	]
	if GameConstants.edition >= 11:
		# 09.06 AFTER MOVING (11e): not eligible to start an action either.
		effects.append({"op": "set", "path": StateSchema.path_unit_flag(unit_id, "cannot_start_action"), "value": true})
	return effects
