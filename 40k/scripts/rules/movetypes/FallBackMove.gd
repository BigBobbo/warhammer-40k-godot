class_name FallBackMove
extends MoveType

## 09.07 FALL-BACK MOVE — eligible if ENGAGED; max distance M; must end
## unengaged; afterwards not eligible to shoot/charge (and 11e: start an
## action) until end of turn.
##
## 11e adds MODES (assessed in order):
##   ▪ ordered_retreat   — selectable if the unit is NOT battle-shocked
##                         (not mandatory: desperate escape may be chosen)
##   ▪ desperate_escape  — otherwise mandatory. BEFORE: one hazard roll per
##                         model (06.03). WHILE: models may move through
##                         enemies. AFTER: if not battle-shocked, make a
##                         battle-shock roll.
## 10e has no modes here (its desperate-escape tests are per-model when
## crossing enemies, handled in the legacy movement path).

func _init():
	id = "fall_back"
	display_name = "Fall Back"

func eligible(unit_id: String, board: Dictionary) -> Dictionary:
	var unit = _unit(board, unit_id)
	if unit.is_empty() or not _on_battlefield(unit):
		return {"eligible": false, "reasons": ["unit not on the battlefield"]}
	if not _rules().is_unit_engaged(unit_id, board):
		return {"eligible": false, "reasons": ["unit is not engaged"]}
	return {"eligible": true, "reasons": []}

func max_distance_inches(unit: Dictionary, _context: Dictionary) -> float:
	return float(unit.get("meta", {}).get("stats", {}).get("move", 0))

func mode_ids() -> Array:
	return ["ordered_retreat", "desperate_escape"] if GameConstants.edition >= 11 else []

func select_mode(unit_id: String, board: Dictionary, _context: Dictionary = {}) -> Dictionary:
	if GameConstants.edition < 11:
		return {"mode": "", "mandatory": false, "available": []}
	var unit = _unit(board, unit_id)
	var shocked: bool = unit.get("flags", {}).get("battle_shocked", false)
	if shocked:
		# 09.07: "Otherwise, you must select this mode."
		return {"mode": "desperate_escape", "mandatory": true, "available": ["desperate_escape"]}
	# Ordered retreat is selectable but NOT mandatory (sidebar): the player
	# may pick desperate escape instead. Default to ordered retreat.
	return {"mode": "ordered_retreat", "mandatory": false, "available": ["ordered_retreat", "desperate_escape"]}

func before_moving(unit_id: String, board: Dictionary, rng, context: Dictionary) -> Dictionary:
	if GameConstants.edition < 11 or context.get("mode", "") != "desperate_escape":
		return {}
	# Desperate Escape BEFORE MOVING: a hazard roll for each model (06.03).
	var unit = _unit(board, unit_id)
	var alive := 0
	for m in unit.get("models", []):
		if m.get("alive", true):
			alive += 1
	var hz = AttackSequence.hazard_rolls(unit, alive, rng)
	return {
		"hazard": hz,
		"mortal_wounds": hz.mortal_wounds,
		"can_move_through_enemies": true,  # WHILE MOVING (desperate escape)
		"dice": [{"context": "desperate_escape_hazard", "rolls": hz.rolls}],
	}

func after_moving_conditions(unit_id: String, board: Dictionary, context: Dictionary) -> Dictionary:
	var base = super.after_moving_conditions(unit_id, board, context)
	if not base.ok:
		return base
	if _rules().is_unit_engaged(unit_id, board):
		return {"ok": false, "violations": ["unit must end a fall-back move unengaged"]}
	return {"ok": true, "violations": []}

func after_moving_effects(unit_id: String, context: Dictionary) -> Array:
	var effects = [
		{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "moved"), "value": true},
		{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "fell_back"), "value": true},
	]
	if GameConstants.edition >= 11:
		effects.append({"op": "set", "path": StateSchema.path_unit_flag(unit_id, "cannot_start_action"), "value": true})
		if context.get("mode", "") == "desperate_escape":
			# 09.07 AFTER MOVING (desperate escape): if not battle-shocked,
			# a battle-shock roll must be made — surfaced as a required
			# follow-up for the phase to resolve via leadership_roll.
			effects.append({"op": "set", "path": StateSchema.path_unit_flag(unit_id, "pending_battleshock_roll"), "value": true})
	return effects
