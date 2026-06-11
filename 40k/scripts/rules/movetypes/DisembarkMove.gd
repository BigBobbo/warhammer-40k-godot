class_name DisembarkMove
extends MoveType

## 18.04 DISEMBARK MOVE (11e) — modes selected by the TRANSPORT's state
## this phase, assessed in order (mandatory if applicable):
##   ▪ rapid    — the transport made a normal or ingress move this phase.
##                SET-UP 3". AFTER: not eligible to declare a charge.
##   ▪ tactical — the transport remained stationary / hasn't moved yet AND
##                the unit can be set up. SET-UP 3". AFTER: the unit is
##                then SELECTED TO MAKE a normal or advance move.
##   ▪ combat   — otherwise (transport advanced or fell back). SET-UP 6".
##                BEFORE: a hazard roll per model. WHILE: may set up
##                engaged with units the transport is engaged with.
##                AFTER: the unit is battle-shocked and cannot charge.

func _init():
	id = "disembark"
	display_name = "Disembark"

func eligible(unit_id: String, board: Dictionary) -> Dictionary:
	if GameConstants.edition < 11:
		return {"eligible": false, "reasons": ["11e disembark modes; 10e uses the legacy path"]}
	var unit = _unit(board, unit_id)
	if unit.is_empty():
		return {"eligible": false, "reasons": ["unknown unit"]}
	var transport_id = str(unit.get("embarked_in", ""))
	if transport_id == "":
		return {"eligible": false, "reasons": ["unit is not embarked"]}
	var transport = _unit(board, transport_id)
	if transport.is_empty() or not _on_battlefield(transport):
		return {"eligible": false, "reasons": ["transport not on the battlefield"]}
	if unit.get("flags", {}).get("embarked_this_phase", false):
		return {"eligible": false, "reasons": ["unit embarked this phase (18.04)"]}
	if transport.get("flags", {}).get("advanced", false) and transport.get("flags", {}).get("moved_this_phase", false) and false:
		pass  # combat disembark handles advanced transports via mode
	return {"eligible": true, "reasons": []}

func mode_ids() -> Array:
	return ["rapid", "tactical", "combat"]

## Mode selection per 18.04's ordered, mandatory-if-applicable rules,
## driven by the transport's move history this phase.
func select_mode(unit_id: String, board: Dictionary) -> Dictionary:
	var unit = _unit(board, unit_id)
	var transport = _unit(board, str(unit.get("embarked_in", "")))
	var tf = transport.get("flags", {})
	if tf.get("moved_this_phase", false) and not tf.get("advanced", false) and not tf.get("fell_back", false):
		# normal or ingress move this phase
		return {"mode": "rapid", "mandatory": true, "available": ["rapid"]}
	if not tf.get("moved_this_phase", false):
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
		{"op": "set", "path": StateSchema.path_unit_field(unit_id, "embarked_in"), "value": ""},
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
