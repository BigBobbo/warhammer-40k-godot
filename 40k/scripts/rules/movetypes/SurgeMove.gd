class_name SurgeMove
extends MoveType

## 21.02 SURGE MOVE (11e) — a triggered move toward the closest enemy.
## MAXIMUM DISTANCE: stated by the triggering rule (context.max_inches).
## ELIGIBLE IF: the triggering rule fired (context-driven), the unit is
##   not battle-shocked, is unengaged, and has not moved this phase.
## BEFORE: the CLOSEST enemy unit becomes the surge target.
## WHILE: each model must end engaged with the surge target if possible,
##   else as close as possible to it.
## AFTER: the unit cannot be engaged with any non-target enemy and cannot
##   move again this phase.

func _init():
	id = "surge"
	display_name = "Surge"

static func _measurement() -> Node:
	return Engine.get_main_loop().root.get_node("/root/Measurement")

func eligible(unit_id: String, board: Dictionary) -> Dictionary:
	var unit = _unit(board, unit_id)
	if unit.is_empty() or not _on_battlefield(unit):
		return {"eligible": false, "reasons": ["unit not on the battlefield"]}
	if GameConstants.edition < 11:
		return {"eligible": false, "reasons": ["surge moves are an 11e move type"]}
	if unit.get("flags", {}).get("battle_shocked", false):
		return {"eligible": false, "reasons": ["battle-shocked units cannot surge"]}
	if _rules().is_unit_engaged(unit_id, board):
		return {"eligible": false, "reasons": ["unit is engaged"]}
	if unit.get("flags", {}).get("moved_this_phase", false):
		return {"eligible": false, "reasons": ["unit has already moved this phase"]}
	return {"eligible": true, "reasons": []}

func max_distance_inches(_unit: Dictionary, context: Dictionary) -> float:
	return float(context.get("max_inches", 0.0))

## BEFORE MOVING: the surge target is the CLOSEST enemy unit (21.02).
func before_moving(unit_id: String, board: Dictionary, _rng, _context: Dictionary) -> Dictionary:
	var unit = _unit(board, unit_id)
	var owner = int(unit.get("owner", 0))
	var m = _measurement()
	var best_id := ""
	var best_dist := INF
	for other_id in board.get("units", {}):
		var other = board.units[other_id]
		if int(other.get("owner", 0)) == owner:
			continue
		for um in unit.get("models", []):
			if not um.get("alive", true) or um.get("position") == null:
				continue
			for em in other.get("models", []):
				if not em.get("alive", true) or em.get("position") == null:
					continue
				var d = m.model_to_model_distance_px(um, em)
				if d < best_dist:
					best_dist = d
					best_id = other_id
	return {"surge_target": best_id}

func after_moving_conditions(unit_id: String, board: Dictionary, context: Dictionary) -> Dictionary:
	var base = super.after_moving_conditions(unit_id, board, context)
	if not base.ok:
		return base
	# 21.02 AFTER: cannot be engaged with enemies that were not the target.
	var target_id = str(context.get("surge_target", ""))
	var unit = _unit(board, unit_id)
	var owner = int(unit.get("owner", 0))
	for other_id in board.get("units", {}):
		if other_id == unit_id or str(other_id) == target_id:
			continue
		var other = board.units[other_id]
		if int(other.get("owner", 0)) == owner:
			continue
		if _rules().check_units_in_engagement_range(unit, other, board):
			return {"ok": false, "violations": ["surge move ended engaged with a non-target unit (%s)" % other_id]}
	return {"ok": true, "violations": []}

func after_moving_effects(unit_id: String, _context: Dictionary) -> Array:
	return [
		{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "moved_this_phase"), "value": true},
		{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "surged"), "value": true},
	]
