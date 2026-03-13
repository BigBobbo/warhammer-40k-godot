extends SceneTree

# Test: OA-45 Ghazghkull's Waaagh! Banner (Aura) for Ghazghkull Thraka
# Verifies that:
# 1. unit_has_waaagh_banner_lethal_hits() returns false for non-ORKS attacker
# 2. unit_has_waaagh_banner_lethal_hits() returns false when Waaagh! not active
# 3. unit_has_waaagh_banner_lethal_hits() returns true for ORKS unit within 12" during Waaagh!
# 4. unit_has_waaagh_banner_lethal_hits() returns false for ORKS unit beyond 12" during Waaagh!
# 5. Lethal Hits does not stack — returns true at most even with two Banner sources
# 6. Enemy ORKS units do not benefit (different owner from source)
# 7. Ghazghkull's own unit benefits from its own aura (self-aura rule)
# 8. Non-ORKS friendly unit does not benefit even within 12"
# Usage: godot --headless --path . -s tests/test_oa45_waaagh_banner.gd
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
	print("\n=== Test OA-45: Ghazghkull's Waaagh! Banner (Aura) ===\n")
	var passed = 0
	var failed = 0

	# --- Test 1: Non-ORKS attacker gets no Lethal Hits ---
	print("--- Test 1: Non-ORKS attacker (SPACE MARINES) gets no Lethal Hits ---")
	var ghaz_t1 = _make_ghazghkull("ghaz_t1", 1, Vector2(0, 0))
	var space_marine = _make_attacker("sm_t1", 1, ["SPACE MARINES", "INFANTRY"], Vector2(3 * PX_PER_INCH, 0), true)
	var board_t1 = _make_board([ghaz_t1, space_marine])
	var result = _rules_engine.unit_has_waaagh_banner_lethal_hits(space_marine.data, board_t1)
	if not result:
		print("  PASS: Non-ORKS attacker does not get Lethal Hits")
		passed += 1
	else:
		print("  FAIL: Non-ORKS attacker should NOT get Lethal Hits, but got true")
		failed += 1

	# --- Test 2: ORKS attacker with no Waaagh! active gets no Lethal Hits ---
	print("\n--- Test 2: ORKS attacker without Waaagh! active gets no Lethal Hits ---")
	var ghaz_t2 = _make_ghazghkull("ghaz_t2", 1, Vector2(0, 0))
	var boyz_t2 = _make_attacker("boyz_t2", 1, ["ORKS", "INFANTRY"], Vector2(3 * PX_PER_INCH, 0), false)
	var board_t2 = _make_board([ghaz_t2, boyz_t2])
	result = _rules_engine.unit_has_waaagh_banner_lethal_hits(boyz_t2.data, board_t2)
	if not result:
		print("  PASS: ORKS attacker with no Waaagh! does not get Lethal Hits")
		passed += 1
	else:
		print("  FAIL: ORKS attacker without Waaagh! should NOT get Lethal Hits, but got true")
		failed += 1

	# --- Test 3: ORKS attacker within 10" of Ghazghkull during Waaagh! gets Lethal Hits ---
	# 10" center-to-center with 32mm bases → edge-to-edge ≈ 8.74" < 12" ✓
	print("\n--- Test 3: ORKS attacker ~10\" from Ghazghkull during Waaagh! gets Lethal Hits ---")
	var ghaz_t3 = _make_ghazghkull("ghaz_t3", 1, Vector2(0, 0))
	var boyz_t3 = _make_attacker("boyz_t3", 1, ["ORKS", "INFANTRY"], Vector2(10 * PX_PER_INCH, 0), true)
	var board_t3 = _make_board([ghaz_t3, boyz_t3])
	result = _rules_engine.unit_has_waaagh_banner_lethal_hits(boyz_t3.data, board_t3)
	if result:
		print("  PASS: ORKS attacker within 12\" of Ghazghkull during Waaagh! gets Lethal Hits")
		passed += 1
	else:
		print("  FAIL: ORKS attacker within 12\" of Ghazghkull during Waaagh! should get Lethal Hits")
		failed += 1

	# --- Test 4: ORKS attacker beyond 12" of Ghazghkull during Waaagh! gets no Lethal Hits ---
	# 20" center-to-center with 32mm bases → edge-to-edge ≈ 18.74" > 12" ✗
	print("\n--- Test 4: ORKS attacker ~20\" from Ghazghkull during Waaagh! gets no Lethal Hits ---")
	var ghaz_t4 = _make_ghazghkull("ghaz_t4", 1, Vector2(0, 0))
	var boyz_t4 = _make_attacker("boyz_t4", 1, ["ORKS", "INFANTRY"], Vector2(20 * PX_PER_INCH, 0), true)
	var board_t4 = _make_board([ghaz_t4, boyz_t4])
	result = _rules_engine.unit_has_waaagh_banner_lethal_hits(boyz_t4.data, board_t4)
	if not result:
		print("  PASS: ORKS attacker beyond 12\" of Ghazghkull does not get Lethal Hits")
		passed += 1
	else:
		print("  FAIL: ORKS attacker beyond 12\" should NOT get Lethal Hits, but got true")
		failed += 1

	# --- Test 5: Two Banner sources do not stack — result is still true (boolean) ---
	print("\n--- Test 5: Two Ghazghkull sources — result is true at most (no double-stacking) ---")
	var ghaz_t5a = _make_ghazghkull("ghaz_t5a", 1, Vector2(0, 0))
	var ghaz_t5b = _make_ghazghkull("ghaz_t5b", 1, Vector2(2 * PX_PER_INCH, 0))
	var boyz_t5 = _make_attacker("boyz_t5", 1, ["ORKS", "INFANTRY"], Vector2(5 * PX_PER_INCH, 0), true)
	var board_t5 = _make_board([ghaz_t5a, ghaz_t5b, boyz_t5])
	result = _rules_engine.unit_has_waaagh_banner_lethal_hits(boyz_t5.data, board_t5)
	if result:
		print("  PASS: With two Banner sources within range, attacker gets Lethal Hits (boolean — no stack)")
		passed += 1
	else:
		print("  FAIL: With two Banner sources, attacker should still get Lethal Hits")
		failed += 1

	# --- Test 6: Enemy ORKS unit does not benefit (different owner from Ghazghkull) ---
	print("\n--- Test 6: Enemy ORKS unit (player 2) does not benefit from player 1's Ghazghkull ---")
	var ghaz_t6 = _make_ghazghkull("ghaz_t6", 1, Vector2(0, 0))
	var enemy_boyz = _make_attacker("enemy_boyz_t6", 2, ["ORKS", "INFANTRY"], Vector2(3 * PX_PER_INCH, 0), true)
	var board_t6 = _make_board([ghaz_t6, enemy_boyz])
	result = _rules_engine.unit_has_waaagh_banner_lethal_hits(enemy_boyz.data, board_t6)
	if not result:
		print("  PASS: Enemy ORKS unit does not benefit from opponent's Waaagh! Banner")
		passed += 1
	else:
		print("  FAIL: Enemy ORKS unit should NOT benefit from opponent's Waaagh! Banner")
		failed += 1

	# --- Test 7: Ghazghkull's own unit benefits from its own aura (self-aura) ---
	print("\n--- Test 7: Ghazghkull's own unit benefits from its own Waaagh! Banner (self-aura) ---")
	var ghaz_t7 = _make_ghazghkull("ghaz_t7", 1, Vector2(0, 0))
	ghaz_t7.data["flags"]["waaagh_active"] = true
	var board_t7 = _make_board([ghaz_t7])
	result = _rules_engine.unit_has_waaagh_banner_lethal_hits(ghaz_t7.data, board_t7)
	if result:
		print("  PASS: Ghazghkull's unit benefits from its own Waaagh! Banner (self-aura)")
		passed += 1
	else:
		print("  FAIL: Ghazghkull's unit should benefit from its own aura")
		failed += 1

	# --- Test 8: Non-ORKS friendly unit (INFANTRY only) does not benefit within 12" ---
	print("\n--- Test 8: Non-ORKS friendly unit does not get Lethal Hits even within 12\" ---")
	var ghaz_t8 = _make_ghazghkull("ghaz_t8", 1, Vector2(0, 0))
	var guard = _make_attacker("guard_t8", 1, ["ASTRA MILITARUM", "INFANTRY"], Vector2(3 * PX_PER_INCH, 0), true)
	var board_t8 = _make_board([ghaz_t8, guard])
	result = _rules_engine.unit_has_waaagh_banner_lethal_hits(guard.data, board_t8)
	if not result:
		print("  PASS: Non-ORKS friendly unit does not get Lethal Hits from Waaagh! Banner")
		passed += 1
	else:
		print("  FAIL: Non-ORKS friendly unit should NOT get Lethal Hits from Waaagh! Banner")
		failed += 1

	# --- Summary ---
	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed == 0:
		print("ALL TESTS PASSED")
		quit(0)
	else:
		print("SOME TESTS FAILED")
		quit(1)

# ─── Helpers ─────────────────────────────────────────────────────────────────

func _make_ghazghkull(unit_id: String, owner: int, pos: Vector2) -> Dictionary:
	var data = {
		"id": unit_id,
		"owner": owner,
		"status": "ACTIVE",
		"embarked_in": "",
		"flags": {"waaagh_active": true},
		"meta": {
			"name": "Ghazghkull Thraka",
			"keywords": ["ORKS", "MONSTER", "CHARACTER", "EPIC HERO", "WARBOSS", "GHAZGHKULL THRAKA"],
			"abilities": [
				{"name": "Ghazghkull's Waaagh! Banner (Aura)", "type": "Datasheet",
				 "description": "Friendly ORKS units within 12\" get Lethal Hits on melee during Waaagh!"}
			]
		},
		"models": [
			{"id": "m1", "wounds": 12, "current_wounds": 12, "base_mm": 100,
			 "position": {"x": pos.x, "y": pos.y}, "alive": true, "status_effects": []},
			{"id": "m2", "wounds": 1, "current_wounds": 1, "base_mm": 32,
			 "position": {"x": pos.x + 50, "y": pos.y}, "alive": true, "status_effects": []}
		]
	}
	return {"id": unit_id, "data": data}

func _make_attacker(unit_id: String, owner: int, keywords: Array, pos: Vector2, waaagh_active: bool) -> Dictionary:
	var data = {
		"id": unit_id,
		"owner": owner,
		"status": "ACTIVE",
		"embarked_in": "",
		"flags": {"waaagh_active": waaagh_active},
		"meta": {
			"name": "Test Unit",
			"keywords": keywords,
			"abilities": []
		},
		"models": [
			{"id": "m1", "wounds": 1, "current_wounds": 1, "base_mm": 32,
			 "position": {"x": pos.x, "y": pos.y}, "alive": true, "status_effects": []}
		]
	}
	return {"id": unit_id, "data": data}

func _make_board(units: Array) -> Dictionary:
	var board = {"units": {}}
	for u in units:
		board["units"][u.id] = u.data
	return board
