class_name DisembarkMove
extends MoveType

## 18.04 DISEMBARK MOVE (11e) — ELIGIBLE IF: embarked, did not embark
## this phase, and the TRANSPORT has NOT made an advance or fall-back
## move this phase (those bar disembarking entirely). Modes are then
## assessed in order (mandatory if applicable):
##   ▪ rapid    — the transport made a normal or ingress move this phase.
##                SET-UP 3". AFTER: not eligible to declare a charge.
##   ▪ tactical — otherwise (stationary / not yet moved) AND the unit CAN
##                be set up within 3". AFTER: the unit is then SELECTED
##                TO MAKE a normal or advance move.
##   ▪ combat   — otherwise (e.g. no room for a tactical set-up, or the
##                transport is engaged). SET-UP 6". BEFORE: a hazard roll
##                per model. WHILE: may set up engaged with units the
##                transport is engaged with. AFTER: battle-shocked and
##                cannot charge.

func _init():
	id = "disembark"
	display_name = "Disembark"

func eligible(unit_id: String, board: Dictionary) -> Dictionary:
	if GameConstants.edition < 11:
		return {"eligible": false, "reasons": ["11e disembark modes; 10e uses the legacy path"]}
	var unit = _unit(board, unit_id)
	if unit.is_empty():
		return {"eligible": false, "reasons": ["unknown unit"]}
	# null is the codebase-wide "not embarked" sentinel; str(null) would give
	# "<null>", so guard before stringifying.
	var embarked_raw = unit.get("embarked_in", null)
	var transport_id = str(embarked_raw) if embarked_raw != null else ""
	if transport_id == "":
		return {"eligible": false, "reasons": ["unit is not embarked"]}
	var transport = _unit(board, transport_id)
	if transport.is_empty() or not _on_battlefield(transport):
		return {"eligible": false, "reasons": ["transport not on the battlefield"]}
	if unit.get("flags", {}).get("embarked_this_phase", false):
		return {"eligible": false, "reasons": ["unit embarked this phase (18.04)"]}
	# 18.04 RAW: an advanced or fallen-back transport bars disembarking.
	if transport.get("flags", {}).get("advanced", false):
		return {"eligible": false, "reasons": ["transport made an advance move this phase (18.04)"]}
	if transport.get("flags", {}).get("fell_back", false):
		return {"eligible": false, "reasons": ["transport made a fall-back move this phase (18.04)"]}
	return {"eligible": true, "reasons": []}

func mode_ids() -> Array:
	return ["rapid", "tactical", "combat"]

## Mode selection per 18.04's ordered, mandatory-if-applicable rules,
## driven by the transport's move history this phase.
func select_mode(unit_id: String, board: Dictionary, context: Dictionary = {}) -> Dictionary:
	var unit = _unit(board, unit_id)
	var embarked_raw = unit.get("embarked_in", null)
	var transport = _unit(board, str(embarked_raw) if embarked_raw != null else "")
	var tf = transport.get("flags", {})
	if tf.get("moved_this_phase", false):
		# normal or ingress move this phase (advance/fall-back are barred
		# by eligibility before mode selection is reached)
		return {"mode": "rapid", "mandatory": true, "available": ["rapid"]}
	# Tactical requires that the unit CAN be set up within 3" (18.04);
	# the caller passes can_setup_tactical=false when the geometry check
	# fails — combat disembark (6", hazard) is the fallback.
	if context.get("can_setup_tactical", true):
		return {"mode": "tactical", "mandatory": true, "available": ["tactical"]}
	return {"mode": "combat", "mandatory": true, "available": ["combat"]}

## SET-UP DISTANCE per mode (18.04).
func setup_distance_inches(context: Dictionary) -> float:
	return 6.0 if context.get("mode", "") == "combat" else 3.0

func before_moving(unit_id: String, board: Dictionary, rng, context: Dictionary) -> Dictionary:
	if context.get("mode", "") != "combat":
		return {}
	# Combat disembark BEFORE MOVING: a hazard roll per model (06.03).
	var unit = _unit(board, unit_id)
	var alive := 0
	for m in unit.get("models", []):
		if m.get("alive", true):
			alive += 1
	var hz = AttackSequence.hazard_rolls(unit, alive, rng)
	return {"hazard": hz, "mortal_wounds": hz.mortal_wounds,
		"can_setup_engaged_with_transport_foes": true,
		"dice": [{"context": "combat_disembark_hazard", "rolls": hz.rolls}]}

func after_moving_effects(unit_id: String, context: Dictionary) -> Array:
	var fx = [
		{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "disembarked_this_turn"), "value": true},
		# null, not "": the codebase-wide "not embarked" check is
		# `embarked_in != null` (token rendering, unit lists, can_disembark).
		# This diff is applied AFTER TransportManager.disembark_unit() already
		# set null — writing "" here turned the unit into an invisible
		# "still embarked" ghost (models hidden, listed as Cannot Disembark).
		{"op": "set", "path": StateSchema.path_unit_field(unit_id, "embarked_in"), "value": null},
	]
	match str(context.get("mode", "")):
		"rapid":
			fx.append({"op": "set", "path": StateSchema.path_unit_flag(unit_id, "cannot_charge"), "value": true})
		"tactical":
			# 18.04: the unit is then selected to make a normal or advance
			# move — surfaced for the movement flow to honour.
			fx.append({"op": "set", "path": StateSchema.path_unit_flag(unit_id, "pending_post_disembark_move"), "value": true})
		"combat":
			fx.append({"op": "set", "path": StateSchema.path_unit_flag(unit_id, "battle_shocked"), "value": true})
			fx.append({"op": "set", "path": StateSchema.path_unit_flag(unit_id, "cannot_charge"), "value": true})
	return fx
