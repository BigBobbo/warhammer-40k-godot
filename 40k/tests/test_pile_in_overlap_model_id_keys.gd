extends SceneTree

# Regression: pile-in / consolidate overlap validation with MODEL-ID movement
# keys ("m1", "m2", …) as the FightController actually submits them.
#
# Bug (fixed): _validate_no_overlaps_for_movement resolved the moving model with
# `int(model_id)`. GDScript's int("m2") parses the trailing digits and returns 2,
# but real army data (e.g. Warbikers) numbers models 1-based — m2 lives at array
# index 1, not 2. That off-by-one:
#   • compared the moving model against a *sibling's* — and its own — stale
#     position, so any small pile-in produced a phantom
#     "Model m2 would overlap with <unit>/1" rejection (the screenshot bug), and
#   • skipped the LAST model entirely, because int("m3") == models.size().
#
# The existing suites never caught it: they key movements by numeric index
# ("0"/"1") or use 0-based ids ("m0"), both of which happen to round-trip through
# int() correctly. This test uses 1-based ids and real oval bike geometry.
#
# Usage: godot --headless --path . -s tests/test_pile_in_overlap_model_id_keys.gd

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
	create_timer(0.1).timeout.connect(_run_tests)

func _mk_bike(id: String, x: float, y: float) -> Dictionary:
	# Real Warbiker base: oval, length(x)=42mm, width(y)=75mm, 1-based ids.
	return {"id": id, "alive": true, "wounds": 3, "current_wounds": 3,
		"base_mm": 75, "base_type": "oval", "base_dimensions": {"length": 42, "width": 75},
		"position": {"x": x, "y": y}}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_pile_in_overlap_model_id_keys ===\n")
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		_check("autoloads", false); _finish(); return
	var prev_state = gs.state.duplicate(true)
	var Meas = root.get_node("Measurement")

	# Three bikes in a horizontal row, centres 3.0" apart -> ~1.35" edge gaps.
	# One enemy touches m2 (base contact) so the id-keyed base-contact check has
	# something to resolve against; m1/m3 stay well clear of it.
	var sp = Meas.inches_to_px(3.0)
	var bike_half_y = Meas.mm_to_px(75) / 2.0   # bike long axis (up)
	var enemy_r = Meas.base_radius_px(32)
	gs.state["units"] = {
		"U_TESTBIKES": {"id": "U_TESTBIKES", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Test Bikes", "keywords": ["MOUNTED"]},
			"models": [
				_mk_bike("m1", 500, 500),
				_mk_bike("m2", 500 + sp, 500),
				_mk_bike("m3", 500 + 2 * sp, 500),
			]},
		"U_TESTENEMY": {"id": "U_TESTENEMY", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "Test Enemy", "keywords": ["INFANTRY"]},
			"models": [
				# ~0.1" BELOW m2's oval edge (long axis) -> within the 0.25" b2b
				# tolerance for m2, well clear of m1/m3 to the sides, and out of the
				# way of the pile-in moves below (which all head UP / sideways).
				{"id": "e1", "alive": true, "wounds": 2, "current_wounds": 2,
					"base_mm": 32, "base_type": "circular",
					"position": {"x": 500 + sp, "y": 500 + bike_half_y + enemy_r + Meas.inches_to_px(0.1)}},
			]},
	}
	var fp = load("res://phases/FightPhase.gd").new()
	var models = gs.state["units"]["U_TESTBIKES"]["models"]

	# Document the root cause so a future int() regression is obvious.
	_check("int('m2') == 2 (the trap)", int("m2") == 2)
	_check("_fight_model_index_for_key resolves 'm2' -> index 1",
		fp._fight_model_index_for_key(models, "m2") == 1)
	_check("_fight_model_index_for_key resolves numeric '1' -> index 1",
		fp._fight_model_index_for_key(models, "1") == 1)
	_check("_fight_model_index_for_key returns -1 for unknown key",
		fp._fight_model_index_for_key(models, "zzz") == -1)

	# --- Base-contact detection must resolve model-id keys too (10e path). ---
	# The enemy touches m2, so only "m2" is in base contact.
	_check("base-contact by id key: 'm2' (touching enemy) is in base contact",
		fp._is_model_in_base_contact_with_enemy("U_TESTBIKES", "m2"))
	_check("base-contact by id key: 'm1' (clear) is NOT in base contact",
		not fp._is_model_in_base_contact_with_enemy("U_TESTBIKES", "m1"))
	_check("base-contact by id key: 'm3' (clear) is NOT in base contact",
		not fp._is_model_in_base_contact_with_enemy("U_TESTBIKES", "m3"))

	# --- Case 1: small pile-in that overlaps NOTHING must be accepted. ---
	# m2 moves 0.5" straight up toward an (imaginary) enemy, away from siblings.
	var c1 = fp._validate_no_overlaps_for_movement("U_TESTBIKES",
		{"m2": Vector2(500 + sp, 500 - Meas.inches_to_px(0.5))})
	_check("model-id key: non-overlapping pile-in is VALID (was the false-positive bug)",
		c1.valid, str(c1.errors))

	# Same move by numeric index key must also be valid (no regression).
	var c1b = fp._validate_no_overlaps_for_movement("U_TESTBIKES",
		{"1": Vector2(500 + sp, 500 - Meas.inches_to_px(0.5))})
	_check("numeric key: non-overlapping pile-in is VALID", c1b.valid, str(c1b.errors))

	# --- Case 2: m2 moved INTO m1 must be rejected against the RIGHT model. ---
	var c2 = fp._validate_no_overlaps_for_movement("U_TESTBIKES",
		{"m2": Vector2(560, 500)})  # 60px from m1 -> real overlap
	_check("model-id key: real overlap is REJECTED", not c2.valid, str(c2.errors))
	_check("real overlap names the correct other model (index 0 = m1)",
		str(c2.errors).contains("U_TESTBIKES/0"), str(c2.errors))
	_check("real overlap does NOT name the moving model itself (index 1)",
		not str(c2.errors).contains("U_TESTBIKES/1"), str(c2.errors))

	# --- Case 3: the LAST model must be checked, not silently skipped. ---
	# m3 (int('m3')==3==size) moved into m2's position -> real overlap.
	var c3 = fp._validate_no_overlaps_for_movement("U_TESTBIKES",
		{"m3": Vector2(500 + sp + 60, 500)})  # 60px from m2 -> real overlap
	_check("last model 'm3' is validated (not skipped) and its overlap is REJECTED",
		not c3.valid, str(c3.errors))

	# --- Case 4: two siblings moving together compare against each other's
	# PROPOSED positions (id-keyed), not stale ones. Both drift up 0.5"
	# in parallel -> still no overlap. ---
	var c4 = fp._validate_no_overlaps_for_movement("U_TESTBIKES", {
		"m1": Vector2(500, 500 - Meas.inches_to_px(0.5)),
		"m2": Vector2(500 + sp, 500 - Meas.inches_to_px(0.5)),
		"m3": Vector2(500 + 2 * sp, 500 - Meas.inches_to_px(0.5)),
	})
	_check("parallel multi-model pile-in (id keys) is VALID", c4.valid, str(c4.errors))

	fp.free()
	gs.state = prev_state
	_finish()

func _finish():
	print("\n=== Totals: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
