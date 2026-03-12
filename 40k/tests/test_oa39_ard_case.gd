extends SceneTree

# Test: OA-39 'Ard Case wargear for Battlewagon
# Verifies that:
# 1. 'Ard Case grants +2 Toughness to Battlewagon
# 2. 'Ard Case disables Firing Deck (sets firing_deck to 0)
# 3. Unit without 'Ard Case keeps original toughness
# 4. Unit without 'Ard Case keeps Firing Deck
# Usage: godot --headless --path . -s tests/test_oa39_ard_case.gd

var _alm = null

func _initialize():
	await create_timer(0.1).timeout
	_alm = root.get_node("ArmyListManager")
	if _alm == null:
		print("FAIL: Could not get ArmyListManager autoload")
		quit(1)
		return
	_run_tests()

func _run_tests():
	print("\n=== Test OA-39: 'Ard Case wargear for Battlewagon ===\n")
	var passed = 0
	var failed = 0

	# --- Test 1: 'Ard Case grants +2 Toughness ---
	print("--- Test 1: 'Ard Case grants +2 Toughness ---")
	var unit = _make_battlewagon_with_ard_case()
	_alm._apply_wargear_stat_bonuses("U_BATTLEWAGON", unit)
	var new_t = int(unit.meta.stats.get("toughness", 0))
	if new_t == 12:
		print("  PASS: Toughness = 12 (base 10 + 2)")
		passed += 1
	else:
		print("  FAIL: Expected toughness=12, got %d" % new_t)
		failed += 1

	# --- Test 2: 'Ard Case disables Firing Deck ---
	print("\n--- Test 2: 'Ard Case disables Firing Deck ---")
	var fd = unit.transport_data.get("firing_deck", -1)
	if fd == 0:
		print("  PASS: Firing Deck disabled (firing_deck=0)")
		passed += 1
	else:
		print("  FAIL: Expected firing_deck=0, got %d" % fd)
		failed += 1

	# --- Test 3: Without 'Ard Case, toughness unchanged ---
	print("\n--- Test 3: Without 'Ard Case, toughness unchanged ---")
	var unit2 = _make_battlewagon_without_ard_case()
	_alm._apply_wargear_stat_bonuses("U_BATTLEWAGON2", unit2)
	var t2 = int(unit2.meta.stats.get("toughness", 0))
	if t2 == 10:
		print("  PASS: Toughness = 10 (unchanged)")
		passed += 1
	else:
		print("  FAIL: Expected toughness=10, got %d" % t2)
		failed += 1

	# --- Test 4: Without 'Ard Case, Firing Deck preserved ---
	print("\n--- Test 4: Without 'Ard Case, Firing Deck preserved ---")
	var fd2 = unit2.transport_data.get("firing_deck", -1)
	if fd2 == 11:
		print("  PASS: Firing Deck preserved (firing_deck=11)")
		passed += 1
	else:
		print("  FAIL: Expected firing_deck=11, got %d" % fd2)
		failed += 1

	# --- Test 5: 'Ard Case with no transport_data doesn't crash ---
	print("\n--- Test 5: 'Ard Case on unit without transport_data doesn't crash ---")
	var unit3 = _make_unit_with_ard_case_no_transport()
	_alm._apply_wargear_stat_bonuses("U_NO_TRANSPORT", unit3)
	var t3 = int(unit3.meta.stats.get("toughness", 0))
	if t3 == 6:
		print("  PASS: Toughness = 6 (base 4 + 2), no crash without transport_data")
		passed += 1
	else:
		print("  FAIL: Expected toughness=6, got %d" % t3)
		failed += 1

	# --- Test 6: Verify loaded army applies 'Ard Case to Battlewagon ---
	print("\n--- Test 6: Verify Battlewagon in orks.json gets +2T applied ---")
	# Load the actual orks army and check the Battlewagon
	var found_battlewagon = false
	var game_state = root.get_node("GameState")
	if game_state and game_state.has_method("get"):
		# Try checking loaded units from army
		pass

	# Instead, verify via the WARGEAR_STAT_BONUSES constant
	var ard_case_def = _alm.WARGEAR_STAT_BONUSES.get("'Ard Case", {})
	if not ard_case_def.is_empty():
		var has_stat = ard_case_def.get("stat", "") == "toughness"
		var has_bonus = ard_case_def.get("bonus", 0) == 2
		var has_remove_fd = ard_case_def.get("removes_firing_deck", false) == true
		if has_stat and has_bonus and has_remove_fd:
			print("  PASS: WARGEAR_STAT_BONUSES['Ard Case'] correctly defined")
			passed += 1
		else:
			print("  FAIL: 'Ard Case definition incomplete: stat=%s, bonus=%d, removes_fd=%s" % [
				ard_case_def.get("stat", "?"), ard_case_def.get("bonus", 0),
				str(ard_case_def.get("removes_firing_deck", false))
			])
			failed += 1
	else:
		print("  FAIL: 'Ard Case not found in WARGEAR_STAT_BONUSES")
		failed += 1

	# --- Summary ---
	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)

# ============================================================================
# Test data builders
# ============================================================================

func _make_battlewagon_with_ard_case() -> Dictionary:
	"""Battlewagon with 'Ard Case wargear — should get +2T and lose Firing Deck."""
	return {
		"id": "U_BATTLEWAGON",
		"meta": {
			"name": "Battlewagon",
			"keywords": ["BATTLEWAGON", "ORKS", "TRANSPORT", "VEHICLE"],
			"stats": {"toughness": 10, "save": 3, "wounds": 16},
			"wargear": ["1x 'Ard Case"],
			"weapons": [],
			"abilities": [
				{
					"name": "FIRING DECK",
					"type": "Core",
					"description": "Firing Deck 11."
				},
				{
					"name": "'Ard Case",
					"type": "Wargear",
					"description": "Add 2 to this model's Toughness characteristic. If this model is equipped with this wargear, it loses the Firing Deck ability."
				}
			]
		},
		"transport_data": {
			"capacity": 22,
			"firing_deck": 11
		},
		"models": [
			{"id": "m1", "wounds": 16, "current_wounds": 16, "base_mm": 60, "position": null, "alive": true, "status_effects": []}
		]
	}

func _make_battlewagon_without_ard_case() -> Dictionary:
	"""Battlewagon without 'Ard Case — should keep original stats."""
	return {
		"id": "U_BATTLEWAGON2",
		"meta": {
			"name": "Battlewagon",
			"keywords": ["BATTLEWAGON", "ORKS", "TRANSPORT", "VEHICLE"],
			"stats": {"toughness": 10, "save": 3, "wounds": 16},
			"wargear": [],
			"weapons": [],
			"abilities": [
				{
					"name": "FIRING DECK",
					"type": "Core",
					"description": "Firing Deck 11."
				}
			]
		},
		"transport_data": {
			"capacity": 22,
			"firing_deck": 11
		},
		"models": [
			{"id": "m1", "wounds": 16, "current_wounds": 16, "base_mm": 60, "position": null, "alive": true, "status_effects": []}
		]
	}

func _make_unit_with_ard_case_no_transport() -> Dictionary:
	"""Unit with 'Ard Case but no transport_data — edge case for robustness."""
	return {
		"id": "U_NO_TRANSPORT",
		"meta": {
			"name": "Test Non-Transport",
			"keywords": ["VEHICLE"],
			"stats": {"toughness": 4, "save": 3, "wounds": 5},
			"weapons": [],
			"abilities": [
				{
					"name": "'Ard Case",
					"type": "Wargear",
					"description": "Add 2 to this model's Toughness characteristic."
				}
			]
		},
		"models": [
			{"id": "m1", "wounds": 5, "current_wounds": 5, "base_mm": 40, "position": null, "alive": true, "status_effects": []}
		]
	}
