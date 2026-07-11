class_name EmergencyDisembarkMove
extends MoveType

## 18.05 EMERGENCY DISEMBARK MOVE (11e) — when the TRANSPORT is destroyed.
## SET-UP 6", as close as possible to the transport; each model that
## cannot be set up is destroyed. BEFORE: a hazard roll per model.
## AFTER: the unit is battle-shocked and cannot charge this turn.

func _init():
	id = "emergency_disembark"
	display_name = "Emergency Disembark"

func eligible(unit_id: String, board: Dictionary) -> Dictionary:
	if GameConstants.edition < 11:
		return {"eligible": false, "reasons": ["11e move type"]}
	var unit = _unit(board, unit_id)
	var embarked_raw = unit.get("embarked_in", null)
	if embarked_raw == null or str(embarked_raw) == "":
		return {"eligible": false, "reasons": ["unit is not embarked"]}
	# Caller asserts the transport was just destroyed (the destruction
	# handler drives this move; there is no standing board state for it).
	return {"eligible": true, "reasons": []}

func setup_distance_inches(_context: Dictionary) -> float:
	return 6.0

func before_moving(unit_id: String, board: Dictionary, rng, _context: Dictionary) -> Dictionary:
	var unit = _unit(board, unit_id)
	var alive := 0
	for m in unit.get("models", []):
		if m.get("alive", true):
			alive += 1
	var hz = AttackSequence.hazard_rolls(unit, alive, rng)
	return {"hazard": hz, "mortal_wounds": hz.mortal_wounds,
		"dice": [{"context": "emergency_disembark_hazard", "rolls": hz.rolls}]}

func after_moving_effects(unit_id: String, _context: Dictionary) -> Array:
	return [
		{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "disembarked_this_turn"), "value": true},
		# null, not "": `embarked_in != null` is the codebase-wide embark check
		# (see DisembarkMove.after_moving_effects for the failure mode).
		{"op": "set", "path": StateSchema.path_unit_field(unit_id, "embarked_in"), "value": null},
		{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "battle_shocked"), "value": true},
		{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "cannot_charge"), "value": true},
	]
