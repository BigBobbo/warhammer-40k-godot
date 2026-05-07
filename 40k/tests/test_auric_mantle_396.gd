extends SceneTree

# Issue #396: validate that ArmyListManager._apply_enhancement_stat_bonuses
# bumps the bearer model's Wounds by 2 when Auric Mantle is on a unit.
#
# Run via: godot --headless --path 40k --script tests/test_auric_mantle_396.gd

var _alm = null


func _initialize():
	await create_timer(0.1).timeout
	_alm = root.get_node_or_null("ArmyListManager")
	if _alm == null:
		print("FAIL: missing ArmyListManager autoload")
		quit(1)
		return
	_run_tests()


func _run_tests():
	print("\n=== Issue #396: Auric Mantle +2 Wounds at army-build ===\n")
	var passed = 0
	var failed = 0

	# --- Test 1: Shield-Captain with Auric Mantle gets +2 Wounds ---
	print("--- Test 1: Shield-Captain (W6) with Auric Mantle → W8 ---")
	var unit_with_mantle = _make_shield_captain(6, ["Auric Mantle"])
	_alm._apply_enhancement_stat_bonuses("U_SHIELD_CAPTAIN_TEST", unit_with_mantle)
	if unit_with_mantle.meta.stats.wounds == 8:
		print("[PASS] meta.stats.wounds bumped 6 -> 8")
		passed += 1
	else:
		print("[FAIL] expected 8, got %d" % unit_with_mantle.meta.stats.wounds)
		failed += 1
	if unit_with_mantle.models[0].wounds == 8 and unit_with_mantle.models[0].current_wounds == 8:
		print("[PASS] model wounds + current_wounds bumped to 8")
		passed += 1
	else:
		print("[FAIL] model wounds=%d current_wounds=%d" % [unit_with_mantle.models[0].wounds, unit_with_mantle.models[0].current_wounds])
		failed += 1

	# --- Test 2: Shield-Captain without enhancement is unchanged ---
	print("\n--- Test 2: Shield-Captain (W6) with no enhancements → unchanged ---")
	var unit_no_mantle = _make_shield_captain(6, [])
	_alm._apply_enhancement_stat_bonuses("U_SHIELD_CAPTAIN_TEST", unit_no_mantle)
	if unit_no_mantle.meta.stats.wounds == 6 and unit_no_mantle.models[0].wounds == 6:
		print("[PASS] no bump applied without Auric Mantle")
		passed += 1
	else:
		print("[FAIL] meta.stats.wounds=%d model.wounds=%d" % [unit_no_mantle.meta.stats.wounds, unit_no_mantle.models[0].wounds])
		failed += 1

	# --- Test 3: enhancement encoded as Dictionary works ---
	print("\n--- Test 3: enhancement encoded as Dictionary form {name: ...} ---")
	var unit_dict_form = _make_shield_captain(6, [{"name": "Auric Mantle"}])
	_alm._apply_enhancement_stat_bonuses("U_SHIELD_CAPTAIN_TEST", unit_dict_form)
	if unit_dict_form.meta.stats.wounds == 8 and unit_dict_form.models[0].wounds == 8:
		print("[PASS] Dictionary form recognised")
		passed += 1
	else:
		print("[FAIL] Dict form not recognised: stats.wounds=%d" % unit_dict_form.meta.stats.wounds)
		failed += 1

	# --- Test 4: Damaged bearer keeps current_wounds at the lower of (max, old_current+bonus_if_full) ---
	print("\n--- Test 4: Damaged bearer (W6, current 3) — only max wounds bumped, current_wounds preserved ---")
	var damaged_unit = _make_shield_captain(6, ["Auric Mantle"])
	damaged_unit.models[0].current_wounds = 3
	_alm._apply_enhancement_stat_bonuses("U_SHIELD_CAPTAIN_TEST", damaged_unit)
	if damaged_unit.models[0].wounds == 8 and damaged_unit.models[0].current_wounds == 3:
		print("[PASS] damaged bearer: max wounds 6 -> 8, current_wounds preserved at 3")
		passed += 1
	else:
		print("[FAIL] wounds=%d current_wounds=%d" % [damaged_unit.models[0].wounds, damaged_unit.models[0].current_wounds])
		failed += 1

	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		quit(1)
	else:
		quit(0)


func _make_shield_captain(wounds: int, enhancements: Array) -> Dictionary:
	return {
		"id": "U_SHIELD_CAPTAIN_TEST",
		"owner": 1,
		"meta": {
			"name": "Shield-Captain",
			"keywords": ["INFANTRY", "CHARACTER"],
			"stats": {"move": 6, "toughness": 6, "save": 2, "wounds": wounds, "objective_control": 1},
			"enhancements": enhancements,
			"weapons": [],
			"abilities": []
		},
		"models": [
			{"id": "m1", "alive": true, "wounds": wounds, "current_wounds": wounds, "position": {"x": 0, "y": 0}, "base_mm": 40}
		],
		"flags": {}
	}
