extends SceneTree

# Test: OA-43 Waaagh! Effigy (Aura) for Stompa
# Verifies that:
# 1. get_battle_shock_bonus() returns 0 for non-ORKS unit
# 2. get_battle_shock_bonus() returns 0 for ORKS unit not near any Stompa
# 3. get_battle_shock_bonus() returns 1 for ORKS unit within 12" of a Stompa
# 4. get_battle_shock_bonus() returns 0 for ORKS unit beyond 12" of a Stompa
# 5. get_battle_shock_bonus() returns 1 (not 2) even with two Stompas in range (no stacking)
# Usage: godot --headless --path . -s tests/test_oa43_waaagh_effigy.gd
#
# NOTE: Model positions are in pixels. PX_PER_INCH = 40.0
# Models have 32mm bases (radius ~25.2px ≈ 0.63"). Edge-to-edge = center-to-center - ~1.26"
# Use large (20"+) distances for "far" and small (4-8") for "near" to avoid base-size edge cases.

const PX_PER_INCH = 40.0

var _ability_mgr = null

func _initialize():
	await create_timer(0.1).timeout
	_ability_mgr = root.get_node("UnitAbilityManager")
	if _ability_mgr == null:
		print("FAIL: Could not get UnitAbilityManager autoload")
		quit(1)
		return
	_run_tests()

func _run_tests():
	print("\n=== Test OA-43: Waaagh! Effigy (Aura) for Stompa ===\n")
	var passed = 0
	var failed = 0

	# --- Test 1: Non-ORKS unit gets no bonus ---
	print("--- Test 1: Non-ORKS unit gets no bonus (not ORKS keyword) ---")
	var custodes_unit = _make_non_orks_unit("custodes_t1", 1)
	var stompa_close = _make_stompa("stompa_close_t1", 1, Vector2(0, 0))
	var result = _test_battle_shock_bonus("custodes_t1", [custodes_unit, stompa_close])
	if result == 0:
		print("  PASS: Non-ORKS unit gets no Battle-shock bonus")
		passed += 1
	else:
		print("  FAIL: Non-ORKS unit should get no bonus, got +%d" % result)
		failed += 1

	# --- Test 2: ORKS unit 40" from Stompa gets no bonus ---
	# 40" center-to-center >> 12" aura range
	print("\n--- Test 2: ORKS unit 40\" from Stompa gets no bonus ---")
	var orks_unit_far = _make_orks_unit("orks_boyz_t2", 1, Vector2(0, 0))
	var stompa_far = _make_stompa("stompa_far_t2", 1, Vector2(40 * PX_PER_INCH, 0))
	result = _test_battle_shock_bonus("orks_boyz_t2", [orks_unit_far, stompa_far])
	if result == 0:
		print("  PASS: ORKS unit 40\" from Stompa gets no bonus")
		passed += 1
	else:
		print("  FAIL: ORKS unit 40\" from Stompa should get no bonus, got +%d" % result)
		failed += 1

	# --- Test 3: ORKS unit ~4" center-to-center from Stompa gets +1 ---
	# 4" center-to-center → edge-to-edge ≈ 2.74" < 12" ✓
	print("\n--- Test 3: ORKS unit ~4\" from Stompa gets +1 ---")
	var orks_unit_near = _make_orks_unit("orks_boyz_t3", 1, Vector2(0, 0))
	var stompa_near = _make_stompa("stompa_near_t3", 1, Vector2(4 * PX_PER_INCH, 0))
	result = _test_battle_shock_bonus("orks_boyz_t3", [orks_unit_near, stompa_near])
	if result == 1:
		print("  PASS: ORKS unit ~4\" from Stompa gets +1 Battle-shock bonus")
		passed += 1
	else:
		print("  FAIL: ORKS unit ~4\" from Stompa should get +1, got +%d" % result)
		failed += 1

	# --- Test 4: ORKS unit ~8" center-to-center from Stompa gets +1 ---
	# 8" center-to-center → edge-to-edge ≈ 6.74" < 12" ✓
	print("\n--- Test 4: ORKS unit ~8\" from Stompa gets +1 ---")
	var orks_unit_mid = _make_orks_unit("orks_boyz_t4", 1, Vector2(0, 0))
	var stompa_mid = _make_stompa("stompa_mid_t4", 1, Vector2(8 * PX_PER_INCH, 0))
	result = _test_battle_shock_bonus("orks_boyz_t4", [orks_unit_mid, stompa_mid])
	if result == 1:
		print("  PASS: ORKS unit ~8\" from Stompa gets +1 Battle-shock bonus")
		passed += 1
	else:
		print("  FAIL: ORKS unit ~8\" from Stompa should get +1, got +%d" % result)
		failed += 1

	# --- Test 5: ORKS unit ~20" from Stompa gets no bonus ---
	# 20" center-to-center → edge-to-edge ≈ 18.74" > 12" ✓
	print("\n--- Test 5: ORKS unit ~20\" from Stompa gets no bonus ---")
	var orks_unit_beyond = _make_orks_unit("orks_boyz_t5", 1, Vector2(0, 0))
	var stompa_beyond = _make_stompa("stompa_beyond_t5", 1, Vector2(20 * PX_PER_INCH, 0))
	result = _test_battle_shock_bonus("orks_boyz_t5", [orks_unit_beyond, stompa_beyond])
	if result == 0:
		print("  PASS: ORKS unit ~20\" from Stompa gets no bonus")
		passed += 1
	else:
		print("  FAIL: ORKS unit ~20\" from Stompa should get no bonus, got +%d" % result)
		failed += 1

	# --- Test 6: Enemy Stompa does not grant bonus ---
	print("\n--- Test 6: Enemy Stompa does not grant bonus ---")
	var friendly_orks = _make_orks_unit("orks_boyz_t6", 1, Vector2(0, 0))
	var enemy_stompa = _make_stompa("stompa_enemy_t6", 2, Vector2(4 * PX_PER_INCH, 0))  # Player 2 = enemy
	result = _test_battle_shock_bonus("orks_boyz_t6", [friendly_orks, enemy_stompa])
	if result == 0:
		print("  PASS: Enemy Stompa does not grant Battle-shock bonus")
		passed += 1
	else:
		print("  FAIL: Enemy Stompa should not grant bonus, got +%d" % result)
		failed += 1

	# --- Test 7: Stompa benefits from its own aura ---
	print("\n--- Test 7: Stompa benefits from its own Waaagh! Effigy aura ---")
	var stompa_self = _make_stompa("stompa_self_t7", 1, Vector2(0, 0))
	result = _test_battle_shock_bonus("stompa_self_t7", [stompa_self])
	if result == 1:
		print("  PASS: Stompa gets +1 from its own Waaagh! Effigy aura")
		passed += 1
	else:
		print("  FAIL: Stompa should get +1 from own aura, got +%d" % result)
		failed += 1

	# --- Test 8: Two Stompas in range - no stacking (returns 1, not 2) ---
	print("\n--- Test 8: Two Stompas in range - bonus does not stack ---")
	var orks_unit_two = _make_orks_unit("orks_boyz_t8", 1, Vector2(0, 0))
	var stompa_a = _make_stompa("stompa_a_t8", 1, Vector2(4 * PX_PER_INCH, 0))
	var stompa_b = _make_stompa("stompa_b_t8", 1, Vector2(8 * PX_PER_INCH, 0))
	result = _test_battle_shock_bonus("orks_boyz_t8", [orks_unit_two, stompa_a, stompa_b])
	if result == 1:
		print("  PASS: Two Stompas in range — bonus is 1 (no stacking per 10th Ed rules)")
		passed += 1
	else:
		print("  FAIL: Two Stompas should give bonus of 1 (not %d) — no stacking" % result)
		failed += 1

	# --- Test 9: ORKS unit near non-Stompa ORKS unit gets no bonus ---
	print("\n--- Test 9: ORKS unit near non-Stompa ORKS unit gets no bonus ---")
	var orks_only = _make_orks_unit("orks_boyz_t9", 1, Vector2(0, 0))
	var other_orks = _make_orks_unit("orks_boyz_t9b", 1, Vector2(4 * PX_PER_INCH, 0))
	result = _test_battle_shock_bonus("orks_boyz_t9", [orks_only, other_orks])
	if result == 0:
		print("  PASS: ORKS unit near non-Stompa ORKS unit gets no bonus")
		passed += 1
	else:
		print("  FAIL: ORKS unit without Stompa nearby should get no bonus, got +%d" % result)
		failed += 1

	print("\n=== Results: %d passed, %d failed ===\n" % [passed, failed])
	if failed == 0:
		print("ALL TESTS PASSED")
		quit(0)
	else:
		print("SOME TESTS FAILED")
		quit(1)

func _test_battle_shock_bonus(unit_id: String, units: Array) -> int:
	"""Set up GameState with the given units, call get_battle_shock_bonus, return result."""
	var units_dict = {}
	for unit in units:
		units_dict[unit.id] = unit.data

	# Temporarily override GameState units
	var game_state = root.get_node("GameState")
	var original_units = game_state.state.get("units", {}).duplicate(true)
	game_state.state["units"] = units_dict

	var bonus = _ability_mgr.get_battle_shock_bonus(unit_id)

	# Restore original state
	game_state.state["units"] = original_units
	return bonus

func _make_orks_unit(unit_id: String, owner: int, position: Vector2) -> Dictionary:
	return {
		"id": unit_id,
		"data": {
			"owner": owner,
			"meta": {
				"name": "Ork Boyz",
				"keywords": ["ORKS", "INFANTRY"],
				"abilities": []
			},
			"models": [
				{
					"alive": true,
					"base_mm": 32,
					"position": {"x": position.x, "y": position.y}
				}
			],
			"flags": {}
		}
	}

func _make_non_orks_unit(unit_id: String, owner: int) -> Dictionary:
	return {
		"id": unit_id,
		"data": {
			"owner": owner,
			"meta": {
				"name": "Custodian Guard",
				"keywords": ["ADEPTUS CUSTODES", "INFANTRY"],
				"abilities": []
			},
			"models": [
				{
					"alive": true,
					"base_mm": 32,
					"position": {"x": 0.0, "y": 0.0}
				}
			],
			"flags": {}
		}
	}

func _make_stompa(unit_id: String, owner: int, position: Vector2) -> Dictionary:
	return {
		"id": unit_id,
		"data": {
			"owner": owner,
			"meta": {
				"name": "Stompa",
				"keywords": ["ORKS", "TRANSPORT", "TITANIC", "VEHICLE", "STOMPA"],
				"abilities": [
					{
						"name": "Waaagh! Effigy (Aura)",
						"type": "Datasheet",
						"description": "While a friendly ORKS unit is within 12\" of this model, each time you take a Battle-shock test for that unit, add 1 to that test."
					}
				]
			},
			"models": [
				{
					"alive": true,
					"base_mm": 32,
					"position": {"x": position.x, "y": position.y}
				}
			],
			"flags": {}
		}
	}
