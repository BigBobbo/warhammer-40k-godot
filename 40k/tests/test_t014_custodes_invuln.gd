extends SceneTree

# T-014: Custodian Guard + Blade Champion must roll a 4+ invuln when faced with
# AP-3 or worse weapons. The audit found `meta.stats.invuln` was missing from
# the unit JSON AND that the save calculation only read model-level invuln, so
# even adding it to the JSON would not fire. Both fixes are required:
# - JSON: add `invuln: 4` to meta.stats for both units
# - Code: _get_model_effective_invuln falls back to unit.meta.stats.invuln
#
# Without this fix, both units would resolve saves at 6+ (armour 3+ minus AP-3)
# and take wounds they should have shrugged.
#
# Usage: godot --headless --path . -s tests/test_t014_custodes_invuln.gd

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
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_t014_custodes_invuln ===\n")
	_test_unit_meta_stats_invuln_fallback()
	_test_save_resolution_with_unit_invuln_4()
	_test_json_units_have_invuln()
	_finish()

func _test_unit_meta_stats_invuln_fallback() -> void:
	print("\n-- T-014a: _get_model_effective_invuln falls back to meta.stats.invuln --")
	var rules = root.get_node("RulesEngine")
	var unit = {
		"id": "U_TEST",
		"meta": {
			"stats": {
				"toughness": 6,
				"save": 2,
				"wounds": 3,
				"invuln": 4,
			},
		},
		"models": [
			{"id": "m1", "alive": true, "current_wounds": 3, "wounds": 3},
		],
	}
	var resolved = rules._get_model_effective_invuln(unit.models[0], unit, 0)
	_check("Unit meta.stats.invuln=4 returned when model has none", resolved == 4,
		"got %d" % resolved)

	# Model-level invuln should still take precedence (preserves prior behaviour).
	var override_model = {"id": "m1", "alive": true, "current_wounds": 3, "wounds": 3, "invuln": 5}
	var resolved2 = rules._get_model_effective_invuln(override_model, unit, override_model.get("invuln", 0))
	_check("Model-level invuln still wins over unit fallback", resolved2 == 5,
		"got %d" % resolved2)

	# No invuln anywhere → 0
	var bare_unit = {
		"meta": {"stats": {"toughness": 4, "save": 3, "wounds": 1}},
		"models": [{"id": "m1", "alive": true, "current_wounds": 1, "wounds": 1}],
	}
	var resolved3 = rules._get_model_effective_invuln(bare_unit.models[0], bare_unit, 0)
	_check("No invuln anywhere → 0", resolved3 == 0, "got %d" % resolved3)

func _test_save_resolution_with_unit_invuln_4() -> void:
	print("\n-- T-014b: _calculate_save_needed resolves invuln-4 vs AP-3 --")
	var rules = root.get_node("RulesEngine")
	var unit = {
		"id": "U_TEST",
		"meta": {"stats": {"toughness": 6, "save": 2, "wounds": 3, "invuln": 4}},
		"models": [{"id": "m1", "alive": true, "current_wounds": 3, "wounds": 3}],
	}
	var model = unit.models[0]
	var model_invuln = rules._get_model_effective_invuln(model, unit, model.get("invuln", 0))
	# AP-3 vs save 2+ = 5+ armour. Invuln 4+ is better, so use_invuln must be true.
	var save_result = rules._calculate_save_needed(2, 3, false, model_invuln, unit)
	_check("AP-3: use_invuln is true", save_result.use_invuln == true,
		"use_invuln=%s armour=%s inv=%s" % [save_result.use_invuln, save_result.armour, save_result.inv])
	_check("AP-3: invuln value resolved to 4", int(save_result.inv) == 4,
		"inv=%s" % save_result.inv)

	# AP-1 vs save 2+ = 3+ armour. Armour beats invuln, use_invuln must be false.
	var save_result2 = rules._calculate_save_needed(2, 1, false, model_invuln, unit)
	_check("AP-1: use_invuln is false (armour 3+ beats invuln 4+)", save_result2.use_invuln == false,
		"use_invuln=%s armour=%s inv=%s" % [save_result2.use_invuln, save_result2.armour, save_result2.inv])

func _test_json_units_have_invuln() -> void:
	print("\n-- T-014c: armies/adeptus_custodes.json has invuln=4 on both units --")
	var f := FileAccess.open("res://armies/adeptus_custodes.json", FileAccess.READ)
	_check("armies JSON readable", f != null)
	if f == null:
		return
	var json = JSON.parse_string(f.get_as_text())
	f.close()
	var bc_stats = json.get("units", {}).get("U_BLADE_CHAMPION_A", {}).get("meta", {}).get("stats", {})
	_check("U_BLADE_CHAMPION_A.meta.stats.invuln == 4", int(bc_stats.get("invuln", 0)) == 4,
		"got %s" % str(bc_stats.get("invuln")))
	var cg_stats = json.get("units", {}).get("U_CUSTODIAN_GUARD_B", {}).get("meta", {}).get("stats", {})
	_check("U_CUSTODIAN_GUARD_B.meta.stats.invuln == 4", int(cg_stats.get("invuln", 0)) == 4,
		"got %s" % str(cg_stats.get("invuln")))

	# Test fixture army too
	var f2 := FileAccess.open("res://armies/A_C_test.json", FileAccess.READ)
	_check("A_C_test.json readable", f2 != null)
	if f2 == null:
		return
	var json2 = JSON.parse_string(f2.get_as_text())
	f2.close()
	var bc_test_stats = json2.get("units", {}).get("U_BLADE_CHAMPION_A", {}).get("meta", {}).get("stats", {})
	_check("A_C_test.json U_BLADE_CHAMPION_A.meta.stats.invuln == 4",
		int(bc_test_stats.get("invuln", 0)) == 4,
		"got %s" % str(bc_test_stats.get("invuln")))

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
