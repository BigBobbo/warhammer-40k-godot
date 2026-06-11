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
func select_mode(_unit_id: String, _board: Dictionary) -> Dictionary:
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
