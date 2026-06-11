class_name ConsolidationMove
extends PileInMove

## 12.07-12.08 — Consolidation move (ISS-050). A GLOBAL step after the
## Fight step: both players move all eligible units (active player
## first), at most one consolidation per unit.
## MAXIMUM DISTANCE: 3"
## ELIGIBLE IF (fight phase): the unit was eligible to fight this phase.
## BEFORE — select consolidation mode (mandatory, assessed in order):
##   ▫ ONGOING: engaged — select every engaged enemy unit.
##   ▫ ENGAGING: otherwise, enemy units within 3" — select one or more.
##   ▫ OBJECTIVE: otherwise, objective within 3" — select one.
## WHILE: ongoing — base-contact models locked, moved models end closer
##   to the closest selected enemy; engaging — closer to closest selected
##   enemy; objective — within range of the objective if possible, else
##   closer to it.
## AFTER: ongoing — started-engaged pairs maintained; engaging — engaged
##   with ALL selected units, and engaged enemies that have not fought
##   are selected by the OPPONENT one at a time and fight (12.04);
##   objective — within range of the selected objective.

const ENGAGING_RANGE_INCHES := 3.0
# Objective range: 3" + 20mm marker radius (matches MissionManager).
const OBJECTIVE_RANGE_INCHES := 3.78740157

func _init():
	id = "consolidation"
	display_name = "Consolidate"


func eligible(unit_id: String, board: Dictionary) -> Dictionary:
	if GameConstants.edition < 11:
		return {"eligible": false, "reasons": ["11e fight-phase template"]}
	var unit = board.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return {"eligible": false, "reasons": ["unit not found"]}
	if unit.get("flags", {}).get("was_eligible_to_fight", false):
		return {"eligible": true, "reasons": []}
	return {"eligible": false, "reasons": ["unit was not eligible to fight this phase (12.08)"]}


func mode_ids() -> Array:
	return ["ongoing", "engaging", "objective"]


## 12.08 BEFORE — modes are mandatory-if-applicable, assessed in order.
func select_mode(unit_id: String, board: Dictionary) -> Dictionary:
	var rules = _rules()
	if rules.is_unit_engaged(unit_id, board):
		return {"mode": "ongoing", "mandatory": true, "available": ["ongoing"]}
	if not _enemies_within(unit_id, board, ENGAGING_RANGE_INCHES).is_empty():
		return {"mode": "engaging", "mandatory": true, "available": ["engaging"]}
	if not _objectives_within(unit_id, board, OBJECTIVE_RANGE_INCHES).is_empty():
		return {"mode": "objective", "mandatory": true, "available": ["objective"]}
	return {"mode": "", "mandatory": false, "available": []}


func before_moving(unit_id: String, board: Dictionary, _rng, context: Dictionary) -> Dictionary:
	var mode = str(context.get("mode", select_mode(unit_id, board).mode))
	var out = {"mode": mode, "started_engaged_with": _engaged_enemy_ids(unit_id, board)}
	match mode:
		"ongoing":
			out["targets"] = _engaged_enemy_ids(unit_id, board)
		"engaging":
			var candidates = _enemies_within(unit_id, board, ENGAGING_RANGE_INCHES)
			var chosen: Array = context.get("chosen_targets", [])
			var targets: Array = []
			for t in chosen:
				if t in candidates:
					targets.append(t)
			out["targets"] = targets if not targets.is_empty() else candidates
			out["candidates"] = candidates
		"objective":
			var objs = _objectives_within(unit_id, board, OBJECTIVE_RANGE_INCHES)
			var chosen_obj = str(context.get("chosen_objective", ""))
			out["objective"] = chosen_obj if chosen_obj in objs else (objs[0] if not objs.is_empty() else "")
		_:
			out["error"] = "no consolidation mode applies — the unit cannot move (12.08)"
	return out


func model_move_allowed(unit_id: String, model: Dictionary, new_pos: Dictionary, board: Dictionary, context: Dictionary) -> Dictionary:
	var mode = str(context.get("mode", ""))
	if mode == "ongoing" and _model_in_base_contact_with_enemy(unit_id, model, board):
		return {"allowed": false, "reason": "models in base-contact with enemy models cannot be moved (12.08)"}
	if mode == "ongoing" or mode == "engaging":
		var before = _distance_to_closest_target(unit_id, model, board, context.get("targets", []))
		var moved = model.duplicate(true)
		moved["position"] = new_pos
		var after = _distance_to_closest_target(unit_id, moved, board, context.get("targets", []))
		if after >= before:
			return {"allowed": false, "reason": "each moved model must end closer to the closest selected enemy unit (12.08)"}
		return {"allowed": true, "reason": ""}
	if mode == "objective":
		var obj = _objective_by_id(board, str(context.get("objective", "")))
		if obj.is_empty():
			return {"allowed": false, "reason": "no objective selected"}
		var meas = Engine.get_main_loop().root.get_node("/root/Measurement")
		var before_d = _model_to_objective_px(model, obj)
		var moved = model.duplicate(true)
		moved["position"] = new_pos
		var after_d = _model_to_objective_px(moved, obj)
		if after_d <= meas.inches_to_px(OBJECTIVE_RANGE_INCHES):
			return {"allowed": true, "reason": ""}
		if after_d < before_d:
			return {"allowed": true, "reason": "closer (not yet in range)"}
		return {"allowed": false, "reason": "must end within range of the objective if possible, or closer to it (12.08)"}
	return {"allowed": false, "reason": "no consolidation mode"}


func after_moving_conditions(unit_id: String, board: Dictionary, context: Dictionary) -> Dictionary:
	var coh = AttackSequence.check_unit_coherency(board.get("units", {}).get(unit_id, {}))
	var violations: Array = []
	if not coh.coherent:
		violations.append("unit not in coherency: %s" % str(coh.offenders))
	var rules = _rules()
	var unit = board.get("units", {}).get(unit_id, {})
	match str(context.get("mode", "")):
		"ongoing":
			for enemy_id in context.get("started_engaged_with", []):
				var enemy = board.get("units", {}).get(enemy_id, {})
				if enemy.is_empty() or not _any_alive(enemy):
					continue
				if not rules.check_units_in_engagement_range(unit, enemy, board):
					violations.append("models that started engaged with %s must still be engaged with it (12.08)" % enemy_id)
		"engaging":
			for t in context.get("targets", []):
				var enemy = board.get("units", {}).get(t, {})
				if not rules.check_units_in_engagement_range(unit, enemy, board):
					violations.append("unit must be engaged with all selected units (12.08): not engaged with %s" % t)
		"objective":
			var obj = _objective_by_id(board, str(context.get("objective", "")))
			var meas = Engine.get_main_loop().root.get_node("/root/Measurement")
			var in_range := false
			for m in unit.get("models", []):
				if m.get("alive", true) and m.get("position") != null \
						and _model_to_objective_px(m, obj) <= meas.inches_to_px(OBJECTIVE_RANGE_INCHES):
					in_range = true
					break
			if not in_range:
				violations.append("unit must be within range of the selected objective (12.08)")
	return {"ok": violations.is_empty(), "violations": violations}


## 12.08 AFTER (engaging): enemy units now engaged with this unit that
## have NOT fought become eligible and are selected to fight by the
## opponent, one at a time. Returns those enemy unit ids.
func forced_fights_after_engaging(unit_id: String, board: Dictionary, fought: Dictionary) -> Array:
	var out: Array = []
	for enemy_id in _engaged_enemy_ids(unit_id, board):
		if not fought.get(enemy_id, false):
			out.append(enemy_id)
	return out


# ── helpers ──────────────────────────────────────────────────────────

func _objectives_within(unit_id: String, board: Dictionary, range_inches: float) -> Array:
	var meas = Engine.get_main_loop().root.get_node("/root/Measurement")
	var unit = board.get("units", {}).get(unit_id, {})
	var out: Array = []
	for obj in board.get("board", {}).get("objectives", []):
		var best := INF
		for m in unit.get("models", []):
			if not m.get("alive", true) or m.get("position") == null:
				continue
			best = min(best, _model_to_objective_px(m, obj))
		if best <= meas.inches_to_px(range_inches):
			out.append(str(obj.get("id", "")))
	return out


func _objective_by_id(board: Dictionary, obj_id: String) -> Dictionary:
	for obj in board.get("board", {}).get("objectives", []):
		if str(obj.get("id", "")) == obj_id:
			return obj
	return {}


func _model_to_objective_px(model: Dictionary, obj: Dictionary) -> float:
	var meas = Engine.get_main_loop().root.get_node("/root/Measurement")
	var pos = obj.get("position")
	if pos is Dictionary:
		pos = Vector2(pos.get("x", 0), pos.get("y", 0))
	return meas.model_edge_to_point_distance_px(model, pos)
