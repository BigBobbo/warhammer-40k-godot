class_name PileInMove
extends MoveType

## 12.02-12.03 — Pile-in move (ISS-050). A GLOBAL step: both players move
## all eligible units (active player first), at most one pile-in per unit.
## MAXIMUM DISTANCE: 3"
## ELIGIBLE IF (fight phase): engaged, OR made a charge move this turn,
##   OR selected to make an overrun fight this phase (12.06).
## BEFORE: select pile-in targets — engaged: EVERY engaged enemy unit;
##   otherwise one or more enemy units within 5".
## WHILE: models in base-contact with enemy models cannot move; each
##   moved model must end closer to the closest pile-in target (and
##   engaged with it if possible).
## AFTER: the unit must be engaged; every model that started engaged
##   with an enemy unit must still be engaged with that unit.

const TARGET_SELECT_RANGE_INCHES := 5.0

func _init():
	id = "pile_in"
	display_name = "Pile In"


func max_distance_inches(_unit: Dictionary, _context: Dictionary) -> float:
	return 3.0


func eligible(unit_id: String, board: Dictionary) -> Dictionary:
	var unit = board.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return {"eligible": false, "reasons": ["unit not found"]}
	var rules = _rules()
	if rules.is_unit_engaged(unit_id, board):
		return {"eligible": true, "reasons": []}
	if unit.get("flags", {}).get("charged_this_turn", false):
		return {"eligible": true, "reasons": []}
	if unit.get("flags", {}).get("selected_for_overrun_fight", false):
		return {"eligible": true, "reasons": []}
	return {"eligible": false, "reasons": ["not engaged, did not charge, and not making an overrun fight (12.03)"]}


## BEFORE MOVING — pile-in target selection. `context.chosen_targets`
## (Array of enemy unit ids) applies only in the unengaged case; engaged
## units MUST select every engaged enemy unit.
func before_moving(unit_id: String, board: Dictionary, _rng, context: Dictionary) -> Dictionary:
	var rules = _rules()
	var unit = board.get("units", {}).get(unit_id, {})
	var targets: Array = []
	if rules.is_unit_engaged(unit_id, board):
		targets = _engaged_enemy_ids(unit_id, board)
	else:
		var candidates = _enemies_within(unit_id, board, TARGET_SELECT_RANGE_INCHES)
		var chosen: Array = context.get("chosen_targets", [])
		if chosen.is_empty():
			targets = candidates
		else:
			for t in chosen:
				if t in candidates:
					targets.append(t)
		if targets.is_empty():
			return {"error": "no pile-in targets within 5\" (12.03)", "candidates": candidates}
	return {
		"pile_in_targets": targets,
		"started_engaged_with": _engaged_enemy_ids(unit_id, board),
	}


## WHILE MOVING — validate one model's proposed end position.
func model_move_allowed(unit_id: String, model: Dictionary, new_pos: Dictionary, board: Dictionary, context: Dictionary) -> Dictionary:
	if _model_in_base_contact_with_enemy(unit_id, model, board):
		return {"allowed": false, "reason": "models in base-contact with enemy models cannot be moved (12.03)"}
	var before = _distance_to_closest_target(unit_id, model, board, context.get("pile_in_targets", []))
	var moved = model.duplicate(true)
	moved["position"] = new_pos
	var after = _distance_to_closest_target(unit_id, moved, board, context.get("pile_in_targets", []))
	if after >= before:
		return {"allowed": false, "reason": "each moved model must end closer to the closest pile-in target (12.03)"}
	return {"allowed": true, "reason": ""}


func after_moving_conditions(unit_id: String, board: Dictionary, context: Dictionary) -> Dictionary:
	var base = super.after_moving_conditions(unit_id, board, context)
	var violations: Array = base.violations.duplicate()
	var rules = _rules()
	if not rules.is_unit_engaged(unit_id, board):
		violations.append("unit must be engaged after a pile-in move (12.03)")
	var unit = board.get("units", {}).get(unit_id, {})
	for enemy_id in context.get("started_engaged_with", []):
		var enemy = board.get("units", {}).get(enemy_id, {})
		if enemy.is_empty() or not _any_alive(enemy):
			continue
		if not rules.check_units_in_engagement_range(unit, enemy, board):
			violations.append("models that started engaged with %s must still be engaged with it (12.03)" % enemy_id)
	return {"ok": violations.is_empty(), "violations": violations}


# ── helpers ──────────────────────────────────────────────────────────

func _engaged_enemy_ids(unit_id: String, board: Dictionary) -> Array:
	var rules = _rules()
	var unit = board.get("units", {}).get(unit_id, {})
	var owner = int(unit.get("owner", 0))
	var out: Array = []
	for other_id in board.get("units", {}):
		var other = board.units[other_id]
		if int(other.get("owner", 0)) == owner:
			continue
		if not _any_alive(other):
			continue
		if rules.check_units_in_engagement_range(unit, other, board):
			out.append(other_id)
	return out


func _enemies_within(unit_id: String, board: Dictionary, range_inches: float) -> Array:
	var meas = Engine.get_main_loop().root.get_node("/root/Measurement")
	var unit = board.get("units", {}).get(unit_id, {})
	var owner = int(unit.get("owner", 0))
	var out: Array = []
	for other_id in board.get("units", {}):
		var other = board.units[other_id]
		if int(other.get("owner", 0)) == owner or not _any_alive(other):
			continue
		var best := INF
		for m in unit.get("models", []):
			if not m.get("alive", true) or m.get("position") == null:
				continue
			for em in other.get("models", []):
				if not em.get("alive", true) or em.get("position") == null:
					continue
				best = min(best, meas.px_to_inches(meas.model_to_model_distance_px(m, em)))
		if best <= range_inches:
			out.append(other_id)
	return out


func _model_in_base_contact_with_enemy(unit_id: String, model: Dictionary, board: Dictionary) -> bool:
	var meas = Engine.get_main_loop().root.get_node("/root/Measurement")
	var owner = int(board.get("units", {}).get(unit_id, {}).get("owner", 0))
	for other_id in board.get("units", {}):
		var other = board.units[other_id]
		if int(other.get("owner", 0)) == owner or not _any_alive(other):
			continue
		for em in other.get("models", []):
			if not em.get("alive", true) or em.get("position") == null:
				continue
			if meas.model_to_model_distance_px(model, em) <= meas.inches_to_px(0.05):
				return true
	return false


func _distance_to_closest_target(unit_id: String, model: Dictionary, board: Dictionary, target_ids: Array) -> float:
	var meas = Engine.get_main_loop().root.get_node("/root/Measurement")
	var best := INF
	for tid in target_ids:
		var target = board.get("units", {}).get(tid, {})
		for em in target.get("models", []):
			if not em.get("alive", true) or em.get("position") == null:
				continue
			best = min(best, meas.model_to_model_distance_px(model, em))
	return best


func _any_alive(unit: Dictionary) -> bool:
	for m in unit.get("models", []):
		if m.get("alive", true):
			return true
	return false
