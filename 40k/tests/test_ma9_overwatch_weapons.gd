extends SceneTree

# Test: MA-9 Overwatch weapon assembly unified with per-model path
# Verifies that:
# 1. _get_model_weapon_ids() returns correct ranged weapons per model type
# 2. _build_overwatch_weapon_assignments() produces consistent results with get_unit_weapons()
# 3. Lootas: 8 deffgun models + 3 mega-blasta models (2 kmb + 1 spanner)
# 4. Units without model_profiles still work correctly
# Usage: godot --headless --path . -s tests/test_ma9_overwatch_weapons.gd

var _re = null

func _initialize():
	await create_timer(0.1).timeout
	_re = root.get_node("RulesEngine")
	if _re == null:
		print("FAIL: Could not get RulesEngine autoload")
		quit(1)
		return
	_run_tests()

func _run_tests():
	print("\n=== Test MA-9: Overwatch weapon assembly unified with per-model path ===\n")
	var passed = 0
	var failed = 0

	# --- Test 1: _get_model_weapon_ids for Lootas deffgun model ---
	print("--- Test 1: _get_model_weapon_ids — deffgun model gets Deffgun ---")
	var lootas_board = _make_lootas_board()
	var lootas_unit = lootas_board["units"]["U_LOOTAS"]
	var deffgun_model = lootas_unit["models"][0]  # loota_deffgun
	var deffgun_ids = _re._get_model_weapon_ids(lootas_unit, deffgun_model, "Ranged")
	if deffgun_ids.size() == 1 and "deffgun_ranged" in deffgun_ids:
		print("  PASS: deffgun model gets [deffgun_ranged]")
		passed += 1
	else:
		print("  FAIL: Expected [deffgun_ranged], got %s" % str(deffgun_ids))
		failed += 1

	# --- Test 2: _get_model_weapon_ids for Lootas kmb model ---
	print("\n--- Test 2: _get_model_weapon_ids — kmb model gets Kustom mega-blasta ---")
	var kmb_model = lootas_unit["models"][8]  # loota_kmb
	var kmb_ids = _re._get_model_weapon_ids(lootas_unit, kmb_model, "Ranged")
	if kmb_ids.size() == 1 and "kustom_mega_blasta_ranged" in kmb_ids:
		print("  PASS: kmb model gets [kustom_mega_blasta_ranged]")
		passed += 1
	else:
		print("  FAIL: Expected [kustom_mega_blasta_ranged], got %s" % str(kmb_ids))
		failed += 1

	# --- Test 3: _get_model_weapon_ids for spanner model ---
	print("\n--- Test 3: _get_model_weapon_ids — spanner model gets Kustom mega-blasta ---")
	var spanner_model = lootas_unit["models"][10]  # spanner
	var spanner_ids = _re._get_model_weapon_ids(lootas_unit, spanner_model, "Ranged")
	if spanner_ids.size() == 1 and "kustom_mega_blasta_ranged" in spanner_ids:
		print("  PASS: spanner model gets [kustom_mega_blasta_ranged]")
		passed += 1
	else:
		print("  FAIL: Expected [kustom_mega_blasta_ranged], got %s" % str(spanner_ids))
		failed += 1

	# --- Test 4: _get_model_weapon_ids melee filter ---
	print("\n--- Test 4: _get_model_weapon_ids — melee filter returns Close combat weapon ---")
	var melee_ids = _re._get_model_weapon_ids(lootas_unit, deffgun_model, "Melee")
	if melee_ids.size() == 1 and "close_combat_weapon_melee" in melee_ids:
		print("  PASS: melee filter returns [close_combat_weapon_melee]")
		passed += 1
	else:
		print("  FAIL: Expected [close_combat_weapon_melee], got %s" % str(melee_ids))
		failed += 1

	# --- Test 5: Overwatch assignments — 8 deffgun + 3 mega-blasta ---
	print("\n--- Test 5: Overwatch assignments — 8 deffgun models + 3 mega-blasta models ---")
	var ow = _re._build_overwatch_weapon_assignments(lootas_unit, "U_LOOTAS", lootas_board)
	var deffgun_count = 0
	var kmb_count = 0
	for a in ow:
		if a["weapon_id"] == "deffgun_ranged":
			deffgun_count = a["model_ids"].size()
		elif a["weapon_id"] == "kustom_mega_blasta_ranged":
			kmb_count = a["model_ids"].size()
	if deffgun_count == 8 and kmb_count == 3:
		print("  PASS: 8 models fire deffguns, 3 models (2 kmb + 1 spanner) fire mega-blastas")
		passed += 1
	else:
		print("  FAIL: Expected 8 deffgun + 3 kmb, got %d deffgun + %d kmb" % [deffgun_count, kmb_count])
		failed += 1

	# --- Test 6: Overwatch consistent with get_unit_weapons ---
	print("\n--- Test 6: Overwatch assignments match get_unit_weapons ---")
	var unit_weapons = _re.get_unit_weapons("U_LOOTAS", lootas_board)
	# Group unit_weapons by weapon_id -> count
	var uw_counts = {}
	for mid in unit_weapons:
		for wid in unit_weapons[mid]:
			uw_counts[wid] = uw_counts.get(wid, 0) + 1
	var ow_counts = {}
	for a in ow:
		ow_counts[a["weapon_id"]] = a["model_ids"].size()
	if ow_counts == uw_counts:
		print("  PASS: Overwatch and get_unit_weapons produce identical weapon-to-model counts")
		passed += 1
	else:
		print("  FAIL: Overwatch: %s, get_unit_weapons: %s" % [str(ow_counts), str(uw_counts)])
		failed += 1

	# --- Test 7: Dead model excluded from overwatch ---
	print("\n--- Test 7: Dead model excluded from overwatch ---")
	var dead_board = _make_lootas_board()
	dead_board["units"]["U_LOOTAS"]["models"][0]["alive"] = false  # kill one deffgun model
	var ow_dead = _re._build_overwatch_weapon_assignments(dead_board["units"]["U_LOOTAS"], "U_LOOTAS", dead_board)
	var deffgun_alive = 0
	for a in ow_dead:
		if a["weapon_id"] == "deffgun_ranged":
			deffgun_alive = a["model_ids"].size()
	if deffgun_alive == 7:
		print("  PASS: Dead model excluded, 7 deffgun models remain")
		passed += 1
	else:
		print("  FAIL: Expected 7 deffgun models, got %d" % deffgun_alive)
		failed += 1

	# --- Test 8: Unit without model_profiles — all models get all ranged weapons ---
	print("\n--- Test 8: Non-profiled unit overwatch consistency ---")
	var basic_board = _make_basic_board()
	var basic_unit = basic_board["units"]["U_BASIC"]
	var ow_basic = _re._build_overwatch_weapon_assignments(basic_unit, "U_BASIC", basic_board)
	var uw_basic = _re.get_unit_weapons("U_BASIC", basic_board)
	var ow_basic_counts = {}
	for a in ow_basic:
		ow_basic_counts[a["weapon_id"]] = a["model_ids"].size()
	var uw_basic_counts = {}
	for mid in uw_basic:
		for wid in uw_basic[mid]:
			uw_basic_counts[wid] = uw_basic_counts.get(wid, 0) + 1
	if ow_basic_counts == uw_basic_counts:
		print("  PASS: Non-profiled unit overwatch matches get_unit_weapons")
		passed += 1
	else:
		print("  FAIL: Overwatch: %s, get_unit_weapons: %s" % [str(ow_basic_counts), str(uw_basic_counts)])
		failed += 1

	# --- Test 9: Live army data — Lootas from orks.json ---
	print("\n--- Test 9: Live army data — Lootas overwatch from orks.json ---")
	var ork_data = _load_army_json("orks")
	if ork_data.is_empty():
		print("  FAIL: Could not load orks.json")
		failed += 1
	else:
		var live_board = {"units": ork_data.get("units", {})}
		var live_lootas = live_board["units"].get("U_LOOTAS_A", {})
		var live_ow = _re._build_overwatch_weapon_assignments(live_lootas, "U_LOOTAS_A", live_board)
		var live_deffgun = 0
		var live_kmb = 0
		for a in live_ow:
			if a["weapon_id"] == "deffgun_ranged":
				live_deffgun = a["model_ids"].size()
			elif a["weapon_id"] == "kustom_mega_blasta_ranged":
				live_kmb = a["model_ids"].size()
		if live_deffgun == 8 and live_kmb == 3:
			print("  PASS: Live orks.json Lootas: 8 deffgun + 3 mega-blasta")
			passed += 1
		else:
			print("  FAIL: Expected 8+3, got %d+%d" % [live_deffgun, live_kmb])
			failed += 1

	# --- Summary ---
	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)

func _make_lootas_board() -> Dictionary:
	var models = []
	for i in range(8):
		models.append({"id": "m%d" % (i + 1), "wounds": 1, "current_wounds": 1, "alive": true, "model_type": "loota_deffgun"})
	for i in range(2):
		models.append({"id": "m%d" % (i + 9), "wounds": 1, "current_wounds": 1, "alive": true, "model_type": "loota_kmb"})
	models.append({"id": "m11", "wounds": 1, "current_wounds": 1, "alive": true, "model_type": "spanner"})

	return {"units": {"U_LOOTAS": {
		"id": "U_LOOTAS",
		"meta": {
			"name": "Lootas",
			"weapons": [
				{"name": "Deffgun", "type": "Ranged", "range": "48", "attacks": "2", "strength": "8", "ap": "-1", "damage": "2", "ballistic_skill": "6", "special_rules": "heavy, rapid fire 1"},
				{"name": "Kustom mega-blasta", "type": "Ranged", "range": "24", "attacks": "3", "strength": "9", "ap": "-2", "damage": "D6", "ballistic_skill": "5", "special_rules": "hazardous"},
				{"name": "Close combat weapon", "type": "Melee", "range": "Melee", "attacks": "2", "strength": "4", "ap": "0", "damage": "1", "weapon_skill": "3"}
			],
			"model_profiles": {
				"loota_deffgun": {"label": "Loota (Deffgun)", "stats_override": {}, "weapons": ["Deffgun", "Close combat weapon"], "transport_slots": 1},
				"loota_kmb": {"label": "Loota (KMB)", "stats_override": {}, "weapons": ["Kustom mega-blasta", "Close combat weapon"], "transport_slots": 1},
				"spanner": {"label": "Spanner", "stats_override": {"ballistic_skill": 4}, "weapons": ["Kustom mega-blasta", "Close combat weapon"], "transport_slots": 1}
			},
			"stats": {"move": 6, "toughness": 5, "save": 5, "wounds": 1}
		},
		"models": models
	}}}

func _make_basic_board() -> Dictionary:
	return {"units": {"U_BASIC": {
		"id": "U_BASIC",
		"meta": {
			"name": "Basic Squad",
			"weapons": [
				{"name": "Shoota", "type": "Ranged", "range": "18", "attacks": "2", "strength": "4", "ap": "0", "damage": "1", "ballistic_skill": "5"},
				{"name": "Close combat weapon", "type": "Melee", "range": "Melee", "attacks": "2", "strength": "4", "ap": "0", "damage": "1", "weapon_skill": "3"}
			],
			"stats": {"move": 6, "toughness": 5, "save": 5, "wounds": 1}
		},
		"models": [
			{"id": "m1", "wounds": 1, "current_wounds": 1, "alive": true},
			{"id": "m2", "wounds": 1, "current_wounds": 1, "alive": true},
			{"id": "m3", "wounds": 1, "current_wounds": 1, "alive": true}
		]
	}}}

func _load_army_json(army_name: String) -> Dictionary:
	var file_path = "res://armies/%s.json" % army_name
	if not FileAccess.file_exists(file_path):
		print("  ERROR: File not found: %s" % file_path)
		return {}
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		print("  ERROR: Could not open file: %s" % file_path)
		return {}
	var json_string = file.get_as_text()
	file.close()
	var json = JSON.new()
	var err = json.parse(json_string)
	if err != OK:
		print("  ERROR: JSON parse error: %s" % json.get_error_message())
		return {}
	return json.data
