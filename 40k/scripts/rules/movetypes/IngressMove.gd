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
## PackedVector2Array, board_size_inches: Vector2, models: Array}.
## `models` is optional and parallel to `model_positions` — each entry is the
## arriving model's dict (base_mm / base_type / rotation). It makes the
## opponent-deployment-zone test base-aware: 20.04 bars models set up "within"
## (not "wholly within") that zone, so a base straddling the zone boundary is
## illegal even though its centre point sits outside. Without it the check falls
## back to the centre point.
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
	var models: Array = context.get("models", [])

	var pos_index := -1
	for pos in model_positions:
		pos_index += 1
		var self_model: Dictionary = models[pos_index] if pos_index < models.size() and models[pos_index] is Dictionary else {}
		var self_radius_px: float = m.base_radius_px(int(self_model.get("base_mm", 0))) if self_model.has("base_mm") else 0.0

		# 20.04: WHOLLY within 6" of one or more battlefield edges
		# (Deep Strike 24.09 lifts this: anywhere on the battlefield).
		# "Wholly" means the far side of the base has to fit inside the band
		# too — measuring only the centre let a base hang its own radius past
		# the line. Falls back to the centre point when no model data was
		# supplied, which is all the old behaviour ever did.
		if not deep_strike:
			if not _wholly_within_setup_distance(pos, self_model, board_w_px, board_h_px, edge_px):
				errors.append("model at %s is not wholly within 6\" of a battlefield edge" % str(pos))

		# more than 8" horizontally from all enemy units, measured BASE EDGE to
		# BASE EDGE like every other distance in the game. This used to compare
		# centre points, which quietly allowed arrivals up to both base radii
		# closer than the rule permits.
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
				var enemy_radius_px: float = m.base_radius_px(int(em.get("base_mm", 32)))
				if pos.distance_to(epv) - self_radius_px - enemy_radius_px < enemy_px:
					errors.append("model at %s is within 8\" of an enemy model" % str(pos))
					break

		# Before the third battle round: not within the opponent's
		# deployment zone (applies to ingress; Deep Strike 24.09 lifts it
		# explicitly — "even if that is within your opponent's deployment
		# zone" — so it is checked for non-DS ingress only).
		if battle_round < 3 and not deep_strike:
			var zone = context.get("opponent_zone", PackedVector2Array())
			if zone.size() >= 3 and _in_opponent_zone(pos, models, pos_index, zone):
				errors.append("model at %s is inside the opponent's deployment zone before battle round 3" % str(pos))

	return {"valid": errors.is_empty(), "errors": errors}

## True when the model set up at [param pos] fits WHOLLY inside the set-up
## distance of at least one battlefield edge (20.04). Shape-aware when the
## caller supplied the model; centre-point when it did not.
func _wholly_within_setup_distance(pos: Vector2, model: Dictionary, board_w_px: float, board_h_px: float, edge_px: float) -> bool:
	if model.is_empty():
		return min(min(pos.x, board_w_px - pos.x), min(pos.y, board_h_px - pos.y)) <= edge_px
	var bands := [
		PackedVector2Array([Vector2(0, 0), Vector2(board_w_px, 0), Vector2(board_w_px, edge_px), Vector2(0, edge_px)]),
		PackedVector2Array([Vector2(0, board_h_px - edge_px), Vector2(board_w_px, board_h_px - edge_px), Vector2(board_w_px, board_h_px), Vector2(0, board_h_px)]),
		PackedVector2Array([Vector2(0, 0), Vector2(edge_px, 0), Vector2(edge_px, board_h_px), Vector2(0, board_h_px)]),
		PackedVector2Array([Vector2(board_w_px - edge_px, 0), Vector2(board_w_px, 0), Vector2(board_w_px, board_h_px), Vector2(board_w_px - edge_px, board_h_px)]),
	]
	var rot: float = float(model.get("rotation", 0.0))
	for band in bands:
		if _measurement().shape_wholly_in_polygon(pos, model, rot, band):
			return true
	return false

## True when the model set up at [param pos] is "within" [param zone]. Uses the
## real base shape when the caller supplied `models`, so a base overhanging the
## zone boundary counts; falls back to the centre point when it did not.
func _in_opponent_zone(pos: Vector2, models: Array, index: int, zone: PackedVector2Array) -> bool:
	if index >= 0 and index < models.size() and models[index] is Dictionary:
		var probe: Dictionary = (models[index] as Dictionary).duplicate()
		probe["position"] = pos
		return _measurement().model_overlaps_polygon(probe, zone)
	return Geometry2D.is_point_in_polygon(pos, zone)

func after_moving_effects(unit_id: String, _context: Dictionary) -> Array:
	return [
		{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "moved"), "value": true},
		{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "arrived_from_reserves"), "value": true},
		# 20.04 AFTER MOVING: no other move type until the next Charge
		# phase — charging IS allowed.
		{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "no_moves_until_charge_phase"), "value": true},
		{"op": "set", "path": StateSchema.path_unit_field(unit_id, "status"), "value": 2},
	]
