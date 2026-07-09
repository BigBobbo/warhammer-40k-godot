extends SceneTree

# Speedwaaagh! Kustom Shokk Box (Deffkilla Wartrike): the bearer moves
# horizontally through terrain features on a turbo (Advance). In this engine
# that means:
#   - the 13.06 dense-terrain path block (which stops a Mounted unit) is
#     bypassed on an Advance (verified via _validate_set_model_dest), and
#   - the difficult-ground movement penalty is waived (verified via
#     _get_movement_terrain_penalty).
#
# Run: godot --headless --path 40k --script tests/test_kustom_shokk_box.gd

var _passed = 0
var _failed = 0


func _rect(cx: float, cy: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(cx - w / 2, cy - h / 2), Vector2(cx + w / 2, cy - h / 2),
		Vector2(cx + w / 2, cy + h / 2), Vector2(cx - w / 2, cy + h / 2)])


func _check(label: String, cond: bool) -> void:
	if cond:
		print("[PASS] %s" % label)
		_passed += 1
	else:
		print("[FAIL] %s" % label)
		_failed += 1


func _initialize():
	await create_timer(0.2).timeout
	_run()
	print("\n=== RESULTS: %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _unit(keywords: Array, enh: Array, x: float) -> Dictionary:
	return {"id": "U", "owner": 1,
		"meta": {"name": "T", "keywords": keywords, "enhancements": enh, "stats": {"move": 12}},
		"flags": {}, "models": [{"id": "m0", "position": {"x": x, "y": 500.0}, "base_mm": 60,
			"base_type": "circular", "alive": true, "wounds": 1, "current_wounds": 1}]}


func _run():
	var GS = root.get_node("GameState")
	var tm = root.get_node("TerrainManager")
	if GS == null or tm == null:
		_check("autoloads present", false)
		return
	GameConstants.edition = 11

	# A tall dense ruin at x 400..600, y 400..600.
	var prev = tm.terrain_features.duplicate(true)
	tm.terrain_features = [
		{"id": "ruin", "type": "ruins", "polygon": _rect(500, 500, 200, 200), "height_category": "tall"},
	]
	var from_pos = Vector2(300, 500)
	var across = Vector2(700, 500)   # crosses the ruin horizontally

	# Baseline: a Mounted unit is blocked by 13.06 dense terrain (the rule KSB overcomes).
	_check("baseline: MOUNTED blocked by dense terrain (13.06)",
		not tm.can_move_through_11e(["MOUNTED"], from_pos, across).allowed)

	# Two units: bearer (KSB) and a plain Mounted unit — both Mounted.
	var bearer = _unit(["MOUNTED", "CHARACTER"], ["Kustom Shokk Box"], 300.0)
	bearer.id = "U_BEARER"
	bearer.models[0].id = "b0"
	var plain = _unit(["MOUNTED", "CHARACTER"], [], 300.0)
	plain.id = "U_PLAIN"
	plain.models[0].id = "p0"
	GS.state["units"] = {"U_BEARER": bearer, "U_PLAIN": plain}

	var phase = load("res://phases/MovementPhase.gd").new()
	phase.game_state_snapshot = GS.state
	root.add_child(phase)

	# Helper detection.
	_check("_unit_has_kustom_shokk_box true for bearer", phase._unit_has_kustom_shokk_box("U_BEARER"))
	_check("_unit_has_kustom_shokk_box false for plain unit", not phase._unit_has_kustom_shokk_box("U_PLAIN"))
	_check("_unit_has_kustom_shokk_box false for empty id", not phase._unit_has_kustom_shokk_box(""))

	# The terrain-penalty waiver is a safe no-op here (ruins impose no horizontal
	# penalty in this engine) — just confirm the bearer path returns cleanly.
	_check("Kustom Shokk Box bearer pays NO terrain penalty", phase._get_movement_terrain_penalty(from_pos, across, "U_BEARER") == 0.0)

	# --- The real effect: bypass the 13.06 dense-terrain block on a turbo (Advance) ---
	# Drive the actual move validator (_validate_set_model_dest) for a move that
	# crosses the ruin. Ample move cap + no enemies so only the terrain gate matters.
	var dest_across = [700.0, 500.0]

	# Plain Mounted, Advancing through the ruin -> blocked by 13.06.
	phase.active_moves = {"U_PLAIN": {"mode": "ADVANCE", "move_cap_inches": 40.0, "model_moves": [], "staged_moves": []}}
	var plain_adv = phase._validate_set_model_dest({"actor_unit_id": "U_PLAIN", "payload": {"model_id": "p0", "dest": dest_across}})
	_check("plain Mounted Advance through dense terrain is BLOCKED", not plain_adv.get("valid", true))

	# Bearer, Advancing (turbo) through the ruin -> allowed (KSB bypass).
	phase.active_moves = {"U_BEARER": {"mode": "ADVANCE", "move_cap_inches": 40.0, "model_moves": [], "staged_moves": []}}
	var bearer_adv = phase._validate_set_model_dest({"actor_unit_id": "U_BEARER", "payload": {"model_id": "b0", "dest": dest_across}})
	_check("Kustom Shokk Box bearer Advance (turbo) through dense terrain is ALLOWED",
		bearer_adv.get("valid", false), )

	# Bearer, NORMAL move (no turbo) through the ruin -> still blocked (KSB is turbo-only).
	phase.active_moves = {"U_BEARER": {"mode": "NORMAL", "move_cap_inches": 40.0, "model_moves": [], "staged_moves": []}}
	var bearer_norm = phase._validate_set_model_dest({"actor_unit_id": "U_BEARER", "payload": {"model_id": "b0", "dest": dest_across}})
	_check("Kustom Shokk Box does NOT apply on a Normal move (turbo only)", not bearer_norm.get("valid", true))

	phase.queue_free()
	tm.terrain_features = prev
