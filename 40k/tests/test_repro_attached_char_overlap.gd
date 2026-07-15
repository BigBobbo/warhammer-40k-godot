extends SceneTree

# Regression: an attached character (e.g. a Blade Champion leading Custodian
# Guard) must NOT end up overlapping a bodyguard model after the unit makes a
# Normal/Advance move (MovementPhase) or a Charge move (ChargePhase).
#
# Root cause (fixed): attached-character models are rigidly translated by the
# bodyguard's first-model delta with NO overlap resolution, so when the player
# re-arranges the bodyguard formation the character could land on top of a
# bodyguard model. The fix nudges the character to the nearest clear position.
#
# Usage: godot --headless --path . -s tests/test_repro_attached_char_overlap.gd

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	create_timer(0.1).timeout.connect(_run)

func _mk(id: String, x: float, y: float) -> Dictionary:
	# 40mm circular base (Custodian Guard / Blade Champion).
	return {"id": id, "alive": true, "wounds": 2, "current_wounds": 2,
		"base_mm": 40, "base_type": "circular", "position": {"x": x, "y": y}}

func _pos(v) -> Vector2:
	if v is Vector2: return v
	return Vector2(v.get("x", 0), v.get("y", 0))

func _overlaps_any_guard(Meas, champ_pos: Vector2, guard_models: Array) -> String:
	var champ = {"base_mm": 40, "base_type": "circular", "position": champ_pos}
	for gm in guard_models:
		var g = {"base_mm": 40, "base_type": "circular", "position": _pos(gm.get("position"))}
		if Meas.models_overlap(champ, g):
			return gm.get("id")
	return ""

func _run():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_repro_attached_char_overlap ===\n")
	var gs = root.get_node_or_null("GameState")
	var Meas = root.get_node_or_null("Measurement")
	if gs == null or Meas == null:
		_check("autoloads present", false); _finish(); return
	var prev_state = gs.state.duplicate(true)

	_test_measurement_helper(Meas)
	_test_movement_advance(gs, Meas)
	_test_charge(gs, Meas)

	gs.state = prev_state
	_finish()

# ── 1. The shared resolver keeps a clear ideal, moves an overlapping one. ──
func _test_measurement_helper(Meas) -> void:
	print("-- Measurement.find_nearest_non_overlapping_position --")
	var mover = {"base_mm": 40, "base_type": "circular"}
	var blocker = {"base_mm": 40, "base_type": "circular", "position": Vector2(500, 500)}

	# Clear ideal -> returned unchanged.
	var clear_ideal = Vector2(900, 900)
	var r_clear = Meas.find_nearest_non_overlapping_position(mover, clear_ideal, [blocker])
	_check("clear ideal returned unchanged", r_clear == clear_ideal, str(r_clear))

	# Ideal on top of a blocker -> nudged clear, and close to ideal.
	var r_nudge = Meas.find_nearest_non_overlapping_position(mover, Vector2(500, 500), [blocker])
	var nudged = {"base_mm": 40, "base_type": "circular", "position": r_nudge}
	_check("overlapping ideal is nudged clear of the blocker",
		not Meas.models_overlap(nudged, blocker), str(r_nudge))
	# 40mm bases: must separate ~63px; nearest clear spot should be well under 90px away.
	_check("nudge stays near the ideal (nearest gap)",
		Vector2(500, 500).distance_to(r_nudge) < 90.0,
		"moved %.1fpx" % Vector2(500, 500).distance_to(r_nudge))

# ── 2. MovementPhase advance: champion riding a re-arranged bodyguard. ──
func _test_movement_advance(gs, Meas) -> void:
	print("-- MovementPhase._move_attached_characters --")
	var champ_start := Vector2(500, 640)
	var m1_from := Vector2(500, 570)
	var m1_dest := Vector2(500, 300)
	var delta := m1_dest - m1_from            # (0,-270)
	var champ_ideal := champ_start + delta    # (500,370) -> lands on m2

	gs.state["units"] = {
		"U_GUARD": {"id": "U_GUARD", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Custodian Guard Zeta", "keywords": ["INFANTRY"]},
			"attachment_data": {"attached_characters": ["U_CHAMP"]},
			"models": [
				_mk("m1", m1_dest.x, m1_dest.y),   # 500,300 (final)
				_mk("m2", 500, 370),               # champion's rigid ideal
				_mk("m3", 500, 440),
				_mk("m4", 500, 510),
				_mk("m5", 500, 580),
			]},
		"U_CHAMP": {"id": "U_CHAMP", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Blade Champion Gamma", "keywords": ["INFANTRY", "CHARACTER"]},
			"attachment_data": {"attached_to": "U_GUARD"},
			"models": [_mk("m1", champ_start.x, champ_start.y)]},
	}

	var mp = load("res://phases/MovementPhase.gd").new()
	get_root().add_child(mp)
	mp.active_moves = {"U_GUARD": {"mode": "ADVANCE", "staged_moves": [],
		"model_moves": [{"model_id": "m1", "model_source_unit_id": "U_GUARD",
			"from": {"x": m1_from.x, "y": m1_from.y},
			"dest": {"x": m1_dest.x, "y": m1_dest.y}, "rotation": 0.0}]}}

	var changes = mp._move_attached_characters("U_GUARD", ["U_CHAMP"], {})
	var champ_final = null
	for ch in changes:
		if ch.get("op") == "set" and str(ch.get("path", "")).begins_with("units.U_CHAMP.models.0.position"):
			champ_final = _pos(ch.get("value"))
	_check("advance: champion move produced", champ_final != null)
	if champ_final != null:
		var hit = _overlaps_any_guard(Meas, champ_final, gs.state["units"]["U_GUARD"]["models"])
		_check("advance: champion does NOT overlap any bodyguard model",
			hit == "", "champion %s overlaps guard %s (ideal was %s)" % [str(champ_final), hit, str(champ_ideal)])
		_check("advance: champion still moved with the unit (near its rigid ideal)",
			champ_final.distance_to(champ_ideal) < 120.0,
			"moved %.1fpx from ideal" % champ_final.distance_to(champ_ideal))
	mp.free()

# ── 3. ChargePhase charge: champion riding a re-arranged bodyguard. ──
func _test_charge(gs, Meas) -> void:
	print("-- ChargePhase._charge_attached_character_changes --")
	var champ_start := Vector2(500, 640)

	# Bodyguard starts spread on a horizontal row; charges into a tight column.
	gs.state["units"] = {
		"U_GUARD2": {"id": "U_GUARD2", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Custodian Guard Zeta", "keywords": ["INFANTRY"]},
			"attachment_data": {"attached_characters": ["U_CHAMP2"]},
			"models": [
				_mk("m1", 500, 570),
				_mk("m2", 600, 570),
				_mk("m3", 700, 570),
				_mk("m4", 800, 570),
				_mk("m5", 900, 570),
			]},
		"U_CHAMP2": {"id": "U_CHAMP2", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Blade Champion Gamma", "keywords": ["INFANTRY", "CHARACTER"]},
			"attachment_data": {"attached_to": "U_GUARD2"},
			"models": [_mk("m1", champ_start.x, champ_start.y)]},
	}
	# Charge paths: m1 delta (0,-270); m2 ends exactly on champion's rigid ideal.
	var per_model_paths = {
		"m1": [[500, 570], [500, 300]],
		"m2": [[600, 570], [500, 370]],   # champion ideal = (500,370)
		"m3": [[700, 570], [500, 440]],
		"m4": [[800, 570], [500, 510]],
		"m5": [[900, 570], [500, 580]],
	}
	var champ_ideal := champ_start + Vector2(0, -270)  # (500,370)

	var cp = load("res://phases/ChargePhase.gd").new()
	get_root().add_child(cp)

	var changes = cp._charge_attached_character_changes("U_GUARD2", per_model_paths, true)
	var champ_final = null
	for ch in changes:
		if ch.get("op") == "set" and str(ch.get("path", "")).begins_with("units.U_CHAMP2.models.0.position"):
			champ_final = _pos(ch.get("value"))
	_check("charge: champion move produced", champ_final != null)
	if champ_final != null:
		# Guard FINAL positions for the overlap check.
		var guard_finals := []
		for mid in ["m1", "m2", "m3", "m4", "m5"]:
			var p = per_model_paths[mid]
			guard_finals.append({"id": mid, "position": {"x": p[-1][0], "y": p[-1][1]}})
		var hit = _overlaps_any_guard(Meas, champ_final, guard_finals)
		_check("charge: champion does NOT overlap any bodyguard model",
			hit == "", "champion %s overlaps guard %s (ideal was %s)" % [str(champ_final), hit, str(champ_ideal)])
		_check("charge: champion still moved with the unit (near its rigid ideal)",
			champ_final.distance_to(champ_ideal) < 120.0,
			"moved %.1fpx from ideal" % champ_final.distance_to(champ_ideal))
	cp.free()

func _finish():
	print("\n=== Totals: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
