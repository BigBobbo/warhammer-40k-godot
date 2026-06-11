class_name IngressMove
extends MoveType

## 20.04 INGRESS MOVE (11e) — how strategic reserves arrive.
## SET-UP DISTANCE: 6" — the unit is SET UP (03.02), not moved along a path.
## ELIGIBLE IF: the unit is in strategic reserves (not embarked in a
##   reserved TRANSPORT).
## WHILE MOVING: set up wholly within 6" of one or more battlefield edges
##   and more than 8" horizontally from all enemy units; before the third
##   battle round, not within the opponent's deployment zone.
## AFTER MOVING: not eligible to make any other move until the start of
##   the next Charge phase (so an ingressed unit CAN charge).
##
## Deep Strike (24.09) relaxes the placement to anywhere >8" from enemies
## via the `deep_strike` flag in context.

func _init():
	id = "ingress"
	display_name = "Ingress"

static func _measurement() -> Node:
	return Engine.get_main_loop().root.get_node("/root/Measurement")

func eligible(unit_id: String, board: Dictionary) -> Dictionary:
	var unit = _unit(board, unit_id)
	if unit.is_empty():
		return {"eligible": false, "reasons": ["unknown unit"]}
	if GameConstants.edition < 11:
		return {"eligible": false, "reasons": ["ingress moves are an 11e move type"]}
	if not unit.get("flags", {}).get("in_reserves", false) and int(unit.get("status", -1)) != 7:
		# status 7 = UnitStatus.IN_RESERVES
		return {"eligible": false, "reasons": ["unit is not in strategic reserves"]}
	return {"eligible": true, "reasons": []}

## Validate a proposed set-up: positions are px Vector2s (one per model).
## context: {battle_round: int, deep_strike: bool, opponent_zone:
## PackedVector2Array, board_size_inches: Vector2}.
func validate_setup(_unit_id: String, board: Dictionary, model_positions: Array, context: Dictionary) -> Dictionary:
	var errors: Array = []
	var m = _measurement()
	var battle_round = int(context.get("battle_round", 1))
	var deep_strike: bool = context.get("deep_strike", false)
	var board_size = context.get("board_size_inches", Vector2(44, 60))
	var board_w_px = board_size.x * 40.0
	var board_h_px = board_size.y * 40.0
	var edge_px = m.inches_to_px(6.0)
	var enemy_px = m.inches_to_px(8.0)

	for pos in model_positions:
		# 20.04: wholly within 6" of one or more battlefield edges
		# (Deep Strike 24.09 lifts this: anywhere on the battlefield).
		if not deep_strike:
			var d_edge = min(min(pos.x, board_w_px - pos.x), min(pos.y, board_h_px - pos.y))
			if d_edge > edge_px:
				errors.append("model at %s is more than 6\" from every battlefield edge" % str(pos))

		# more than 8" horizontally from all enemy units
		var owner = int(_unit(board, _unit_id).get("owner", 0))
		for other_id in board.get("units", {}):
			var other = board.units[other_id]
			if int(other.get("owner", 0)) == owner:
				continue
			for em in other.get("models", []):
				if not em.get("alive", true) or em.get("position") == null:
					continue
				var ep = em.position
				var epv = Vector2(float(ep.x) if ep is Dictionary else ep.x, float(ep.y) if ep is Dictionary else ep.y)
				if pos.distance_to(epv) <= enemy_px:
					errors.append("model at %s is within 8\" of an enemy model" % str(pos))
					break

		# Before the third battle round: not within the opponent's
		# deployment zone (applies to ingress; Deep Strike's anywhere-rule
		# still respects this restriction for non-DS ingress only).
		if battle_round < 3 and not deep_strike:
			var zone = context.get("opponent_zone", PackedVector2Array())
			if zone.size() >= 3 and Geometry2D.is_point_in_polygon(pos, zone):
				errors.append("model at %s is inside the opponent's deployment zone before battle round 3" % str(pos))

	return {"valid": errors.is_empty(), "errors": errors}

func after_moving_effects(unit_id: String, _context: Dictionary) -> Array:
	return [
		{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "moved"), "value": true},
		{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "arrived_from_reserves"), "value": true},
		# 20.04 AFTER MOVING: no other move type until the next Charge
		# phase — charging IS allowed.
		{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "no_moves_until_charge_phase"), "value": true},
		{"op": "set", "path": StateSchema.path_unit_field(unit_id, "status"), "value": 2},
	]
