class_name MoveType
extends RefCounted

## Base class for the 11e move-type template (ISS-040; core rules 03.01).
##
## Every move in 11e is expressed uniformly:
##   MAXIMUM DISTANCE / ELIGIBLE IF / EFFECT / BEFORE / WHILE / AFTER MOVING
## with mutually exclusive MODES assessed in the order presented (09.07's
## "Selecting Modes" sidebar). If end conditions fail, the models return to
## their starting positions and the unit has NOT been selected to move
## (03.01/03.02).
##
## Phases ask the registry (MoveTypes.gd) which move types a unit is
## eligible for, then drive the selected type through:
##   eligible() -> select_mode() -> before_moving() -> [player moves models,
##   validated against while_moving rules] -> after_moving_conditions() ->
##   after_moving_effects().
##
## Concrete instances so far: RemainStationary, Normal, Advance, FallBack
## (09.04-09.07). Charge/pile-in/consolidation/disembark/ingress/surge land
## with their issues (ISS-049/050/058/060/061) as further instances.

var id: String = ""
var display_name: String = ""


static func _rules() -> Node:
	return Engine.get_main_loop().root.get_node("/root/RulesEngine")


## ELIGIBLE IF — returns {eligible: bool, reasons: Array[String]}.
func eligible(_unit_id: String, _board: Dictionary) -> Dictionary:
	return {"eligible": false, "reasons": ["not implemented"]}


## MAXIMUM DISTANCE in inches for this move, given the BEFORE-step context
## (e.g. advance roll). -1 means "no movement" (remain stationary).
func max_distance_inches(_unit: Dictionary, _context: Dictionary) -> float:
	return 0.0


## The mode ids this move type offers, in assessment order. Empty = no modes.
func mode_ids() -> Array:
	return []


## Select the mode for a unit per the sidebar rules: assess each mode in
## order; mandatory-if-applicable modes are chosen automatically. Returns
## {mode: String, mandatory: bool, available: Array} ("" = no modes).
func select_mode(_unit_id: String, _board: Dictionary, _context: Dictionary = {}) -> Dictionary:
	return {"mode": "", "mandatory": false, "available": []}


## BEFORE MOVING — dice and declarations (advance rolls, hazard rolls).
## Returns a context dict merged into the move context; may carry
## {mortal_wounds, dice: [...]} for the phase to apply/log.
func before_moving(_unit_id: String, _board: Dictionary, _rng, _context: Dictionary) -> Dictionary:
	return {}


## AFTER MOVING conditions — checks that void the move if violated
## (03.01: "If one or more of the above conditions are not met, that unit
## cannot make that move"). Returns {ok: bool, violations: Array}.
func after_moving_conditions(unit_id: String, board: Dictionary, _context: Dictionary) -> Dictionary:
	# Universal end conditions (03.01): unit must be in coherency.
	var unit = board.get("units", {}).get(unit_id, {})
	var coh = AttackSequence.check_unit_coherency(unit)
	if not coh.coherent:
		return {"ok": false, "violations": ["unit not in coherency: %s" % str(coh.offenders)]}
	return {"ok": true, "violations": []}


## AFTER MOVING effects — state diffs (flags) this move imposes, e.g.
## advanced units cannot charge. Edition-aware where the rules differ.
func after_moving_effects(_unit_id: String, _context: Dictionary) -> Array:
	return []


# ── shared eligibility helpers ──────────────────────────────────────

func _on_battlefield(unit: Dictionary) -> bool:
	for m in unit.get("models", []):
		if m.get("alive", true) and m.get("position") != null:
			return true
	return false

func _unit(board: Dictionary, unit_id: String) -> Dictionary:
	return board.get("units", {}).get(unit_id, {})


## ── 03.01 "Its base cannot be moved through enemy models" ─────────
## EA-08 (11e 09.07): shared by the Movement phase's path checks
## (MovementPhase._path_crosses_enemy_bases / _path_crosses_monster_vehicle_bases)
## and the fall-back moves made outside it (Tactical Fluidity, WIND-SWIFT
## EVASION via ReactiveMove11e), so every fall-back judges "moving through"
## the same way.
##
## Base CONTACT is not moving through. A charge's snap leaves bases within
## half a pixel of each other and float32 positions turn exact contact into a
## hair of overlap, so a straight path is swept with a base CONTACT_TOLERANCE_MM
## smaller than the model's (half a millimetre a side, about 0.8 px).
const CONTACT_TOLERANCE_MM := 1

static func _measurement() -> Node:
	var ml = Engine.get_main_loop()
	if ml is SceneTree and ml.root:
		return ml.root.get_node_or_null("Measurement")
	return null

static func _pos_of(m: Dictionary) -> Vector2:
	var p = m.get("position", null)
	if p is Vector2:
		return p
	if p is Dictionary:
		return Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
	return Vector2.INF

## A copy of `model` whose base is CONTACT_TOLERANCE_MM smaller (round and
## oval / rectangular dimensions alike) — the swept base of a path check.
static func contact_tolerant_mover(model: Dictionary) -> Dictionary:
	var m: Dictionary = model.duplicate(true)
	m["base_mm"] = maxi(1, int(round(float(m.get("base_mm", 32)))) - CONTACT_TOLERANCE_MM)
	var dims = m.get("base_dimensions", {})
	if dims is Dictionary and not dims.is_empty():
		var nd: Dictionary = dims.duplicate()
		for k in ["length", "width"]:
			if nd.has(k):
				nd[k] = maxf(1.0, float(nd[k]) - float(CONTACT_TOLERANCE_MM))
		m["base_dimensions"] = nd
	return m

## Shape-aware base overlap (Measurement.models_overlap); bounding circles
## when the autoload is not there (bare --script unit tests).
static func _bases_overlap(a: Dictionary, b: Dictionary) -> bool:
	var meas = _measurement()
	if meas != null:
		return bool(meas.models_overlap(a, b))
	var pa := _pos_of(a)
	var pb := _pos_of(b)
	if pa == Vector2.INF or pb == Vector2.INF:
		return false
	var ra := _bounding_radius_px(a)
	var rb := _bounding_radius_px(b)
	return pa.distance_to(pb) < ra + rb

static func _bounding_radius_px(m: Dictionary) -> float:
	var mm := float(m.get("base_mm", 32))
	var dims = m.get("base_dimensions", {})
	if dims is Dictionary and not dims.is_empty() and str(m.get("base_type", "circular")) != "circular":
		mm = maxf(float(dims.get("length", mm)), float(dims.get("width", mm)))
	return mm / 25.4 * 40.0 / 2.0

## Does `mover` (already contact-tolerant), moved in a straight line from
## `from` to `to`, move THROUGH `other` (standing at other_pos)? Samples about
## every 10 px (t > 0). A base the mover already overlaps at `from` (a deep
## overlap a set-up left behind) only counts when the path takes the mover's
## centre closer to it; otherwise any overlap on the way counts.
static func sweep_moves_through(mover: Dictionary, from: Vector2, to: Vector2, other: Dictionary, other_pos: Vector2) -> bool:
	var probe: Dictionary = mover.duplicate()
	probe["position"] = from
	var start_overlap: bool = _bases_overlap(probe, other)
	var start_d := from.distance_to(other_pos)
	var n: int = maxi(2, int(from.distance_to(to) / 10.0))
	for i in range(1, n + 1):
		var p: Vector2 = from.lerp(to, float(i) / float(n))
		probe["position"] = p
		if _bases_overlap(probe, other):
			if not start_overlap or p.distance_to(other_pos) < start_d - 0.5:
				return true
	return false

## 11e 23.02 MOVEMENT: "Each time a unit makes any type of move, its models can
## be moved through AIRCRAFT models" — an AIRCRAFT unit's models never block a
## move's path (friendly or enemy; a move still cannot END on one).
static func unit_is_aircraft(u: Dictionary) -> bool:
	for kw in u.get("meta", {}).get("keywords", []):
		if str(kw).to_upper() == "AIRCRAFT":
			return true
	return false

## Would `model` (of a unit owned by `owner`), moved straight from `from` to
## `to`, move through an alive, on-table model of another player? skip_unit_ids
## (a set: unit_id -> true) is never a blocker, nor is an AIRCRAFT model
## (23.02). 03.01 / 09.07 (Ordered Retreat).
static func path_crosses_enemy_models(board: Dictionary, owner: int, model: Dictionary, from: Vector2, to: Vector2, skip_unit_ids: Dictionary = {}) -> bool:
	if from.distance_to(to) < 0.01:
		return false
	var mover := contact_tolerant_mover(model)
	var mover_r := _bounding_radius_px(mover)
	var seg := to - from
	var seg_len2 := seg.length_squared()
	var units: Dictionary = board.get("units", {})
	for uid in units:
		if skip_unit_ids.has(str(uid)):
			continue
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) == owner or u.get("embarked_in", null) != null:
			continue
		if unit_is_aircraft(u):
			continue  # 23.02: models can be moved through AIRCRAFT models
		for om in u.get("models", []):
			if not om.get("alive", true):
				continue
			var op := _pos_of(om)
			if op == Vector2.INF:
				continue
			# Cheap reject: the enemy base is farther from the path than the
			# two bounding radii (+1 px) — no overlap anywhere along it.
			var t := clampf((op - from).dot(seg) / seg_len2, 0.0, 1.0) if seg_len2 > 0.0 else 0.0
			if (from + seg * t).distance_to(op) > mover_r + _bounding_radius_px(om) + 1.0:
				continue
			if sweep_moves_through(mover, from, to, om, op):
				return true
	return false


## 21.03 / 24.17 (11e): when a FLYING unit "takes to the skies" its move
## maximum is reduced by 2" (0" with HOVER) and it may move through all
## models and terrain ignoring vertical distance. Returns the distance
## modifier in inches for a declared take-to-the-skies move.
static func take_to_skies_modifier(unit: Dictionary) -> float:
	if GameConstants.edition < 11:
		return 0.0
	var keywords: Array = unit.get("meta", {}).get("keywords", [])
	if not "FLY" in keywords:
		return 0.0
	if "HOVER" in keywords:
		return 0.0
	return -2.0
