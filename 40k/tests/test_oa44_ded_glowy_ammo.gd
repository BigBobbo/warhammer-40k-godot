extends SceneTree

# Test: OA-44 Ded Glowy Ammo (Aura) for Kaptin Badrukk
# Verifies that:
# 1. get_ded_glowy_ammo_toughness_penalty() returns 0 for non-INFANTRY enemy unit
# 2. get_ded_glowy_ammo_toughness_penalty() returns 0 for INFANTRY unit with no nearby Kaptin
# 3. get_ded_glowy_ammo_toughness_penalty() returns 1 for INFANTRY unit within 6" of Kaptin
# 4. get_ded_glowy_ammo_toughness_penalty() returns 0 for INFANTRY unit beyond 6" of Kaptin
# 5. Penalty does not stack from two Kaptins in range (returns 1 at most)
# 6. Friendly INFANTRY units are not affected (same owner as Kaptin)
# 7. Kaptin attached to a bodyguard unit — range measured from bodyguard
# 8. Non-INFANTRY enemy unit not affected even within range
# Usage: godot --headless --path . -s tests/test_oa44_ded_glowy_ammo.gd
#
# NOTE: Model positions are in pixels. PX_PER_INCH = 40.0
# Models have 32mm bases (radius ~25.2px ≈ 0.63"). Edge-to-edge = center-to-center - ~1.26"
# Use large (20"+) distances for "far" and small (3-5") for "near" to stay clearly in/out of range.

const PX_PER_INCH = 40.0

var _rules_engine = null

func _initialize():
	await create_timer(0.1).timeout
	_rules_engine = root.get_node("RulesEngine")
	if _rules_engine == null:
		print("FAIL: Could not get RulesEngine autoload")
		quit(1)
		return
	_run_tests()

func _run_tests():
	print("\n=== Test OA-44: Ded Glowy Ammo (Aura) for Kaptin Badrukk ===\n")
	var passed = 0
	var failed = 0

	# --- Test 1: Non-INFANTRY enemy unit gets no penalty ---
	print("--- Test 1: Non-INFANTRY enemy (VEHICLE) unit gets no penalty ---")
	var kaptin_t1 = _make_kaptin("kaptin_t1", 1, Vector2(0, 0))
	var vehicle = _make_enemy_unit("vehicle_t1", 2, ["ORKS", "VEHICLE"], Vector2(3 * PX_PER_INCH, 0))
	var board_t1 = _make_board([kaptin_t1, vehicle])
	var penalty = _rules_engine.get_ded_glowy_ammo_toughness_penalty(vehicle.data, board_t1)
	if penalty == 0:
		print("  PASS: VEHICLE enemy gets no toughness penalty")
		passed += 1
	else:
		print("  FAIL: VEHICLE enemy should get no penalty, got -%d" % penalty)
		failed += 1

	# --- Test 2: INFANTRY enemy unit with no Kaptin nearby gets no penalty ---
	print("\n--- Test 2: INFANTRY unit with no Kaptin Badrukk nearby gets no penalty ---")
	var regular_orks = _make_enemy_unit("orks_t2", 1, ["ORKS", "INFANTRY"], Vector2(0, 0))
	var other_orks = _make_enemy_unit("other_orks_t2", 1, ["ORKS", "INFANTRY"], Vector2(3 * PX_PER_INCH, 0))
	var board_t2 = _make_board([regular_orks, other_orks])
	var enemy_infantry = _make_enemy_unit("enemy_inf_t2", 2, ["SPACE MARINES", "INFANTRY"], Vector2(2 * PX_PER_INCH, 0))
	board_t2["units"][enemy_infantry.id] = enemy_infantry.data
	penalty = _rules_engine.get_ded_glowy_ammo_toughness_penalty(enemy_infantry.data, board_t2)
	if penalty == 0:
		print("  PASS: INFANTRY unit with no Kaptin nearby gets no penalty")
		passed += 1
	else:
		print("  FAIL: INFANTRY unit with no Kaptin should get no penalty, got -%d" % penalty)
		failed += 1

	# --- Test 3: INFANTRY enemy within 4" center-to-center of Kaptin gets -1T ---
	# 4" center-to-center with 32mm bases → edge-to-edge ≈ 2.74" < 6" ✓
	print("\n--- Test 3: INFANTRY unit ~4\" from Kaptin gets -1 Toughness penalty ---")
	var kaptin_t3 = _make_kaptin("kaptin_t3", 1, Vector2(0, 0))
	var target_t3 = _make_enemy_unit("target_t3", 2, ["SPACE MARINES", "INFANTRY"], Vector2(4 * PX_PER_INCH, 0))
	var board_t3 = _make_board([kaptin_t3, target_t3])
	penalty = _rules_engine.get_ded_glowy_ammo_toughness_penalty(target_t3.data, board_t3)
	if penalty == 1:
		print("  PASS: INFANTRY unit ~4\" from Kaptin gets -1 Toughness penalty")
		passed += 1
	else:
		print("  FAIL: INFANTRY unit ~4\" from Kaptin should get -1T, got -%d" % penalty)
		failed += 1

	# --- Test 4: INFANTRY enemy ~20" center-to-center from Kaptin gets no penalty ---
	# 20" center-to-center with 32mm bases → edge-to-edge ≈ 18.74" > 6" ✗
	print("\n--- Test 4: INFANTRY unit ~20\" from Kaptin gets no penalty ---")
	var kaptin_t4 = _make_kaptin("kaptin_t4", 1, Vector2(0, 0))
	var target_t4 = _make_enemy_unit("target_t4", 2, ["SPACE MARINES", "INFANTRY"], Vector2(20 * PX_PER_INCH, 0))
	var board_t4 = _make_board([kaptin_t4, target_t4])
	penalty = _rules_engine.get_ded_glowy_ammo_toughness_penalty(target_t4.data, board_t4)
	if penalty == 0:
		print("  PASS: INFANTRY unit ~20\" from Kaptin gets no penalty")
		passed += 1
	else:
		print("  FAIL: INFANTRY unit ~20\" from Kaptin should get no penalty, got -%d" % penalty)
		failed += 1

	# --- Test 5: Two Kaptins in range — no stacking (returns 1 at most) ---
	print("\n--- Test 5: Two Kaptins in range — penalty does not stack (returns 1) ---")
	var kaptin_a_t5 = _make_kaptin("kaptin_a_t5", 1, Vector2(0, 0))
	var kaptin_b_t5 = _make_kaptin("kaptin_b_t5", 1, Vector2(2 * PX_PER_INCH, 0))
	var target_t5 = _make_enemy_unit("target_t5", 2, ["SPACE MARINES", "INFANTRY"], Vector2(4 * PX_PER_INCH, 0))
	var board_t5 = _make_board([kaptin_a_t5, kaptin_b_t5, target_t5])
	penalty = _rules_engine.get_ded_glowy_ammo_toughness_penalty(target_t5.data, board_t5)
	if penalty == 1:
		print("  PASS: Two Kaptins in range — penalty is 1 (no stacking per 10th Ed rules)")
		passed += 1
	else:
		print("  FAIL: Two Kaptins should give penalty of 1 (not %d) — no stacking" % penalty)
		failed += 1

	# --- Test 6: Friendly INFANTRY is not affected (same owner as Kaptin) ---
	print("\n--- Test 6: Friendly INFANTRY (same player as Kaptin) not affected ---")
	var kaptin_t6 = _make_kaptin("kaptin_t6", 1, Vector2(0, 0))
	var friendly_inf = _make_enemy_unit("friendly_inf_t6", 1, ["ORKS", "INFANTRY"], Vector2(3 * PX_PER_INCH, 0))
	var board_t6 = _make_board([kaptin_t6, friendly_inf])
	penalty = _rules_engine.get_ded_glowy_ammo_toughness_penalty(friendly_inf.data, board_t6)
	if penalty == 0:
		print("  PASS: Friendly INFANTRY (same player) is not affected")
		passed += 1
	else:
		print("  FAIL: Friendly INFANTRY should not be affected, got -%d" % penalty)
		failed += 1

	# --- Test 7: Kaptin attached to a bodyguard (Flash Gitz) — range from bodyguard ---
	# Kaptin at (0,0) is attached to Flash Gitz at (0,0). Enemy at 4" gets penalty.
	print("\n--- Test 7: Kaptin attached to bodyguard — range measured from bodyguard unit ---")
	var flash_gitz_t7 = _make_bodyguard_with_kaptin("flash_gitz_t7", "kaptin_t7", 1, Vector2(0, 0))
	var target_t7 = _make_enemy_unit("target_t7", 2, ["SPACE MARINES", "INFANTRY"], Vector2(4 * PX_PER_INCH, 0))
	var board_t7 = _make_board_with_attachment(flash_gitz_t7, "kaptin_t7", target_t7)
	penalty = _rules_engine.get_ded_glowy_ammo_toughness_penalty(target_t7.data, board_t7)
	if penalty == 1:
		print("  PASS: Enemy INFANTRY within 4\" of bodyguard unit (with attached Kaptin) gets -1T")
		passed += 1
	else:
		print("  FAIL: Enemy INFANTRY near bodyguard (attached Kaptin) should get -1T, got -%d" % penalty)
		failed += 1

	# --- Test 8: MONSTER keyword (non-INFANTRY) enemy within range gets no penalty ---
	print("\n--- Test 8: Enemy MONSTER within range gets no penalty ---")
	var kaptin_t8 = _make_kaptin("kaptin_t8", 1, Vector2(0, 0))
	var monster = _make_enemy_unit("monster_t8", 2, ["TYRANIDS", "MONSTER"], Vector2(3 * PX_PER_INCH, 0))
	var board_t8 = _make_board([kaptin_t8, monster])
	penalty = _rules_engine.get_ded_glowy_ammo_toughness_penalty(monster.data, board_t8)
	if penalty == 0:
		print("  PASS: Enemy MONSTER within range gets no penalty (not INFANTRY)")
		passed += 1
	else:
		print("  FAIL: Enemy MONSTER should get no penalty, got -%d" % penalty)
		failed += 1

	print("\n=== Results: %d passed, %d failed ===\n" % [passed, failed])
	if failed == 0:
		print("ALL TESTS PASSED")
		quit(0)
	else:
		print("SOME TESTS FAILED")
		quit(1)

# ============================================================
# Helpers
# ============================================================

func _make_kaptin(unit_id: String, owner: int, position: Vector2) -> Dictionary:
	return {
		"id": unit_id,
		"data": {
			"owner": owner,
			"meta": {
				"name": "Kaptin Badrukk",
				"keywords": ["ORKS", "INFANTRY", "CHARACTER", "FREEBOOTER", "KAPTIN BADRUKK"],
				"abilities": [
					{
						"name": "Ded Glowy Ammo (Aura)",
						"type": "Datasheet",
						"description": "While this model is on the battlefield, subtract 1 from the Toughness characteristic of enemy INFANTRY units that are within 6\" of this model."
					}
				]
			},
			"models": [
				{
					"alive": true,
					"base_mm": 40,
					"position": {"x": position.x, "y": position.y}
				}
			],
			"flags": {}
		}
	}

func _make_enemy_unit(unit_id: String, owner: int, keywords: Array, position: Vector2) -> Dictionary:
	return {
		"id": unit_id,
		"data": {
			"owner": owner,
			"meta": {
				"name": "Unit " + unit_id,
				"keywords": keywords,
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

func _make_board(units: Array) -> Dictionary:
	var units_dict = {}
	for unit in units:
		units_dict[unit.id] = unit.data
	return {"units": units_dict}

func _make_bodyguard_with_kaptin(bodyguard_id: String, kaptin_id: String, owner: int, position: Vector2) -> Dictionary:
	"""Create a Flash Gitz bodyguard unit at position. Kaptin Badrukk is recorded as attached character."""
	return {
		"id": bodyguard_id,
		"data": {
			"owner": owner,
			"meta": {
				"name": "Flash Gitz",
				"keywords": ["ORKS", "INFANTRY", "FLASH GITZ"],
				"abilities": []
			},
			"models": [
				{
					"alive": true,
					"base_mm": 32,
					"position": {"x": position.x, "y": position.y}
				}
			],
			"attachment_data": {
				"attached_characters": [kaptin_id]
			},
			"flags": {}
		}
	}

func _make_board_with_attachment(bodyguard: Dictionary, kaptin_id: String, target: Dictionary) -> Dictionary:
	"""Build board dict with bodyguard unit (containing attached Kaptin) and target."""
	var kaptin_unit = {
		"owner": bodyguard.data.get("owner", 1),
		"meta": {
			"name": "Kaptin Badrukk",
			"keywords": ["ORKS", "INFANTRY", "CHARACTER", "FREEBOOTER", "KAPTIN BADRUKK"],
			"abilities": [
				{
					"name": "Ded Glowy Ammo (Aura)",
					"type": "Datasheet",
					"description": "While this model is on the battlefield, subtract 1 from the Toughness characteristic of enemy INFANTRY units that are within 6\" of this model."
				}
			]
		},
		"models": [
			{
				"alive": true,
				"base_mm": 40,
				"position": bodyguard.data["models"][0]["position"]  # Attached — same position as bodyguard
			}
		],
		"attached_to": bodyguard.id,
		"flags": {}
	}
	return {
		"units": {
			bodyguard.id: bodyguard.data,
			kaptin_id: kaptin_unit,
			target.id: target.data
		}
	}
