extends SceneTree

# Test: MA-32 Integration test with full game flow
# Verifies the complete lifecycle of heterogeneous units (Lootas) through:
#   1. Army loading — model_profiles, model_type on each model
#   2. Deployment simulation — non-sequential model placement, model picker state
#   3. Shooting — separate weapon assignments per model type
#   4. Wound allocation — model type labels in casualty selection
#   5. Casualty removal — spanner tracked as dead correctly
#   6. Save/load round-trip — model_type preserved, weapon assignments correct
#   7. Multiplayer readiness — model types visible in state snapshot
# Usage: godot --headless --path . -s tests/test_integration_model_profiles.gd

func _init():
	print("\n=== MA-32 Integration Test: Full Game Flow with Heterogeneous Units ===\n")
	var passed = 0
	var failed = 0

	# ═══════════════════════════════════════════════════════════════════════
	# PHASE 1: Load Orks army with Lootas (heterogeneous unit)
	# ═══════════════════════════════════════════════════════════════════════

	print("═══ PHASE 1: Army Loading ═══\n")

	# --- Test 1: Load orks.json ---
	print("--- Test 1: Load orks.json successfully ---")
	var army_data = _load_army_json("orks")
	if army_data.is_empty():
		print("  FAIL: Could not load orks.json")
		failed += 1
	else:
		print("  PASS: orks.json loaded")
		passed += 1

	# --- Test 2: Lootas unit exists with model_profiles ---
	print("\n--- Test 2: Lootas unit exists with model_profiles ---")
	var lootas = army_data.get("units", {}).get("U_LOOTAS_A", {})
	var meta = lootas.get("meta", {})
	var mp = meta.get("model_profiles", {})
	var models = lootas.get("models", [])
	if not mp.is_empty() and models.size() == 11:
		print("  PASS: U_LOOTAS_A has model_profiles and 11 models")
		passed += 1
	else:
		print("  FAIL: Missing model_profiles or wrong model count (profiles=%s, models=%d)" % [str(mp.keys()), models.size()])
		failed += 1

	# --- Test 3: Correct model type distribution ---
	print("\n--- Test 3: Model type distribution (8 deffgun, 2 KMB, 1 spanner) ---")
	var type_counts = _count_model_types(models)
	if type_counts.get("loota_deffgun", 0) == 8 and type_counts.get("loota_kmb", 0) == 2 and type_counts.get("spanner", 0) == 1:
		print("  PASS: 8x loota_deffgun, 2x loota_kmb, 1x spanner")
		passed += 1
	else:
		print("  FAIL: Unexpected distribution: %s" % str(type_counts))
		failed += 1

	# --- Test 4: All model_type references are valid profile keys ---
	print("\n--- Test 4: All model_type values reference valid profile keys ---")
	var all_valid = true
	for m in models:
		var mt = m.get("model_type", "")
		if mt == "" or not mp.has(mt):
			print("  FAIL: Model %s has invalid model_type '%s' (valid: %s)" % [m.get("id", "?"), mt, str(mp.keys())])
			all_valid = false
	if all_valid:
		print("  PASS: All 11 models have valid model_type references")
		passed += 1
	else:
		failed += 1

	# ═══════════════════════════════════════════════════════════════════════
	# PHASE 2: Deployment simulation — non-sequential model placement
	# ═══════════════════════════════════════════════════════════════════════

	print("\n═══ PHASE 2: Deployment Simulation ═══\n")

	# --- Test 5: Simulate non-sequential deployment order ---
	print("--- Test 5: Non-sequential deployment — place models in mixed order ---")
	# Simulate placing models in this order: m11(spanner), m5(deffgun), m9(kmb), m1(deffgun), m10(kmb), ...
	var deployment_order = ["m11", "m5", "m9", "m1", "m10", "m2", "m3", "m6", "m7", "m8", "m4"]
	var deployed_unit = lootas.duplicate(true)
	var deployed_models = deployed_unit.get("models", [])
	var placement_positions = {}
	var base_x = 100.0
	var base_y = 200.0
	var placement_ok = true

	for i in range(deployment_order.size()):
		var model_id = deployment_order[i]
		var model = _find_model(deployed_models, model_id)
		if model.is_empty():
			print("  FAIL: Could not find model %s for deployment" % model_id)
			placement_ok = false
			continue
		# Simulate placement at different positions
		var pos = {"x": base_x + (i * 32.0), "y": base_y}
		model["position"] = pos
		model["alive"] = true
		placement_positions[model_id] = pos

	if placement_ok and placement_positions.size() == 11:
		print("  PASS: All 11 models placed in non-sequential order")
		passed += 1
	else:
		print("  FAIL: Only placed %d/11 models" % placement_positions.size())
		failed += 1

	# --- Test 6: Model type picker groups are correct ---
	print("\n--- Test 6: Model type picker would show correct groups ---")
	# Verify the model_profiles can be used to build picker groups
	var picker_groups = {}
	for m in deployed_models:
		var mt = m.get("model_type", "")
		if mt != "":
			if not picker_groups.has(mt):
				picker_groups[mt] = {"label": mp.get(mt, {}).get("label", mt), "count": 0, "model_ids": []}
			picker_groups[mt].count += 1
			picker_groups[mt].model_ids.append(m.get("id", ""))
	var picker_ok = picker_groups.has("loota_deffgun") and picker_groups.has("loota_kmb") and picker_groups.has("spanner")
	if picker_ok and picker_groups["loota_deffgun"].count == 8 and picker_groups["loota_kmb"].count == 2 and picker_groups["spanner"].count == 1:
		print("  PASS: Picker groups: %s (8), %s (2), %s (1)" % [
			picker_groups["loota_deffgun"].label,
			picker_groups["loota_kmb"].label,
			picker_groups["spanner"].label
		])
		passed += 1
	else:
		print("  FAIL: Incorrect picker groups: %s" % str(picker_groups))
		failed += 1

	# --- Test 7: Token visuals distinguish model types ---
	print("\n--- Test 7: Token visual labels per model type ---")
	var label_map = {}
	for m in deployed_models:
		var mt = m.get("model_type", "")
		var label = mp.get(mt, {}).get("label", "")
		if label != "":
			label_map[mt] = label
	if label_map.get("loota_deffgun", "") == "Loota (Deffgun)" and label_map.get("loota_kmb", "") == "Loota (Kustom Mega-blasta)" and label_map.get("spanner", "") == "Spanner":
		print("  PASS: Visual labels correct — Loota (Deffgun), Loota (Kustom Mega-blasta), Spanner")
		passed += 1
	else:
		print("  FAIL: Label map incorrect: %s" % str(label_map))
		failed += 1

	# ═══════════════════════════════════════════════════════════════════════
	# PHASE 3: Shooting — separate weapon assignments per model type
	# ═══════════════════════════════════════════════════════════════════════

	print("\n═══ PHASE 3: Shooting (Weapon Assignment) ═══\n")

	var board = {"units": {"U_LOOTAS_A": deployed_unit}}

	# --- Test 8: Deffgun models fire deffguns only ---
	print("--- Test 8: 8 deffgun models fire deffguns ---")
	var ranged_weapons = _get_unit_ranged_weapons("U_LOOTAS_A", board)
	var deffgun_shooters = 0
	for mid in ["m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8"]:
		if ranged_weapons.has(mid) and "deffgun_ranged" in ranged_weapons[mid]:
			deffgun_shooters += 1
	if deffgun_shooters == 8:
		print("  PASS: 8 deffgun models assigned deffgun_ranged")
		passed += 1
	else:
		print("  FAIL: Expected 8 deffgun shooters, got %d" % deffgun_shooters)
		failed += 1

	# --- Test 9: KMB models fire mega-blastas ---
	print("\n--- Test 9: 3 models fire kustom mega-blastas (2 KMB + 1 spanner) ---")
	var kmb_shooters = 0
	for mid in ["m9", "m10", "m11"]:
		if ranged_weapons.has(mid) and "kustom_mega_blasta_ranged" in ranged_weapons[mid]:
			kmb_shooters += 1
	if kmb_shooters == 3:
		print("  PASS: m9, m10, m11 assigned kustom_mega_blasta_ranged")
		passed += 1
	else:
		print("  FAIL: Expected 3 KMB shooters, got %d" % kmb_shooters)
		failed += 1

	# --- Test 10: Deffgun models cannot fire KMB ---
	print("\n--- Test 10: Deffgun models cannot fire mega-blasta ---")
	var cross_assign_ok = true
	for mid in ["m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8"]:
		if ranged_weapons.has(mid) and "kustom_mega_blasta_ranged" in ranged_weapons[mid]:
			print("  FAIL: %s (deffgun) should NOT have kustom_mega_blasta_ranged" % mid)
			cross_assign_ok = false
	if cross_assign_ok:
		print("  PASS: No deffgun model assigned kustom mega-blasta")
		passed += 1
	else:
		failed += 1

	# --- Test 11: KMB/spanner models cannot fire deffgun ---
	print("\n--- Test 11: KMB/spanner models cannot fire deffgun ---")
	var reverse_cross_ok = true
	for mid in ["m9", "m10", "m11"]:
		if ranged_weapons.has(mid) and "deffgun_ranged" in ranged_weapons[mid]:
			print("  FAIL: %s (KMB/spanner) should NOT have deffgun_ranged" % mid)
			reverse_cross_ok = false
	if reverse_cross_ok:
		print("  PASS: No KMB/spanner model assigned deffgun")
		passed += 1
	else:
		failed += 1

	# --- Test 12: Per-model BS — spanner BS4+ vs others ---
	print("\n--- Test 12: Per-model BS resolution — spanner BS4+, deffgun BS6+, KMB BS5+ ---")
	var deffgun_profile = {"bs": 6, "ws": 4}
	var kmb_profile = {"bs": 5, "ws": 4}
	var bs_ok = true
	for m in deployed_models:
		var mt = m.get("model_type", "")
		if mt == "spanner":
			var bs = _get_model_effective_bs(m, deployed_unit, kmb_profile)
			if bs != 4:
				print("  FAIL: spanner %s should have BS=4, got %d" % [m.get("id", ""), bs])
				bs_ok = false
		elif mt == "loota_deffgun":
			var bs = _get_model_effective_bs(m, deployed_unit, deffgun_profile)
			if bs != 6:
				print("  FAIL: deffgun %s should have BS=6, got %d" % [m.get("id", ""), bs])
				bs_ok = false
		elif mt == "loota_kmb":
			var bs = _get_model_effective_bs(m, deployed_unit, kmb_profile)
			if bs != 5:
				print("  FAIL: loota_kmb %s should have BS=5, got %d" % [m.get("id", ""), bs])
				bs_ok = false
	if bs_ok:
		print("  PASS: Per-model BS correct — spanner=4, deffgun=6, loota_kmb=5 (weapon default)")
		passed += 1
	else:
		failed += 1

	# --- Test 13: Separate shooting assignments produce correct attack counts ---
	print("\n--- Test 13: Attack count per weapon group ---")
	# Deffgun: attacks=2, 8 models = 16 attacks
	# KMB: attacks=3, 3 models = 9 attacks
	var deffgun_attacks = 0
	var kmb_attacks = 0
	var weapons_data = meta.get("weapons", [])
	for w in weapons_data:
		if w.get("name", "") == "Deffgun":
			var atk_str = w.get("attacks", "0")
			deffgun_attacks = int(atk_str) if atk_str.is_valid_int() else 0
		elif w.get("name", "") == "Kustom mega-blasta":
			var atk_str = w.get("attacks", "0")
			kmb_attacks = int(atk_str) if atk_str.is_valid_int() else 0
	var total_deffgun_attacks = deffgun_attacks * 8  # 2 * 8 = 16
	var total_kmb_attacks = kmb_attacks * 3  # 3 * 3 = 9
	if total_deffgun_attacks == 16 and total_kmb_attacks == 9:
		print("  PASS: Deffgun=16 attacks (8x2), KMB=9 attacks (3x3)")
		passed += 1
	else:
		print("  FAIL: Expected 16 deffgun + 9 KMB attacks, got %d + %d" % [total_deffgun_attacks, total_kmb_attacks])
		failed += 1

	# ═══════════════════════════════════════════════════════════════════════
	# PHASE 4: Wound Allocation — model type labels visible
	# ═══════════════════════════════════════════════════════════════════════

	print("\n═══ PHASE 4: Wound Allocation & Casualties ═══\n")

	# --- Test 14: Wound allocation profiles built per-model with model_type ---
	print("--- Test 14: Save profiles built per-model with model_type labels ---")
	var save_profiles = _build_save_profiles(deployed_unit)
	var profiles_ok = true
	if save_profiles.size() != 11:
		print("  FAIL: Expected 11 save profiles, got %d" % save_profiles.size())
		profiles_ok = false
	else:
		# Check each profile has model_type
		for sp in save_profiles:
			if sp.model_type == "":
				print("  FAIL: Save profile for %s missing model_type" % sp.model_id)
				profiles_ok = false
		# Check spanner model (m11) is labeled
		var spanner_found = false
		for sp in save_profiles:
			if sp.model_id == "m11" and sp.model_type == "spanner":
				spanner_found = true
		if not spanner_found:
			print("  FAIL: Spanner model m11 not found in save profiles")
			profiles_ok = false
	if profiles_ok:
		print("  PASS: 11 save profiles with model_type labels (spanner m11 present)")
		passed += 1
	else:
		failed += 1

	# --- Test 15: Wound allocation UI labels per model type ---
	print("\n--- Test 15: Wound allocation UI shows model type labels ---")
	var wound_labels = []
	for sp in save_profiles:
		var label = mp.get(sp.model_type, {}).get("label", "")
		wound_labels.append({
			"model_id": sp.model_id,
			"model_type": sp.model_type,
			"display_label": label if label != "" else sp.model_id,
		})
	var label_types = {}
	for wl in wound_labels:
		label_types[wl.display_label] = label_types.get(wl.display_label, 0) + 1
	if label_types.get("Loota (Deffgun)", 0) == 8 and label_types.get("Loota (Kustom Mega-blasta)", 0) == 2 and label_types.get("Spanner", 0) == 1:
		print("  PASS: UI labels: 8x 'Loota (Deffgun)', 2x 'Loota (Kustom Mega-blasta)', 1x 'Spanner'")
		passed += 1
	else:
		print("  FAIL: Incorrect label distribution: %s" % str(label_types))
		failed += 1

	# ═══════════════════════════════════════════════════════════════════════
	# PHASE 5: Take casualties — remove spanner, verify tracking
	# ═══════════════════════════════════════════════════════════════════════

	print("\n═══ PHASE 5: Casualty Removal ═══\n")

	# --- Test 16: Remove spanner model (m11) as casualty ---
	print("--- Test 16: Remove spanner model (m11) — tracked as dead ---")
	var spanner_model = _find_model(deployed_models, "m11")
	spanner_model["alive"] = false
	spanner_model["current_wounds"] = 0
	var m11 = _find_model(deployed_models, "m11")
	if not m11.get("alive", true) and m11.get("current_wounds", 1) == 0:
		print("  PASS: Spanner model m11 marked as dead (alive=false, wounds=0)")
		passed += 1
	else:
		print("  FAIL: Spanner model not properly marked as dead")
		failed += 1

	# --- Test 17: Dead spanner excluded from weapon assignment ---
	print("\n--- Test 17: Dead spanner excluded from weapon assignment ---")
	var post_casualty_weapons = _get_unit_ranged_weapons("U_LOOTAS_A", board)
	if not post_casualty_weapons.has("m11"):
		print("  PASS: Dead spanner m11 excluded from weapon assignment")
		passed += 1
	else:
		print("  FAIL: Dead spanner m11 still in weapon assignment: %s" % str(post_casualty_weapons["m11"]))
		failed += 1

	# --- Test 18: Alive model counts correct after casualty ---
	print("\n--- Test 18: Alive model counts after spanner death ---")
	var post_type_counts = _count_alive_model_types(deployed_models)
	if post_type_counts.get("loota_deffgun", 0) == 8 and post_type_counts.get("loota_kmb", 0) == 2 and post_type_counts.get("spanner", 0) == 0:
		print("  PASS: 8 deffgun, 2 KMB alive; 0 spanner alive")
		passed += 1
	else:
		print("  FAIL: Post-casualty counts wrong: %s" % str(post_type_counts))
		failed += 1

	# --- Test 19: Remove additional casualties (2 deffgun models) ---
	print("\n--- Test 19: Remove 2 deffgun models (m3, m7) ---")
	_find_model(deployed_models, "m3")["alive"] = false
	_find_model(deployed_models, "m3")["current_wounds"] = 0
	_find_model(deployed_models, "m7")["alive"] = false
	_find_model(deployed_models, "m7")["current_wounds"] = 0
	var post_type_counts2 = _count_alive_model_types(deployed_models)
	if post_type_counts2.get("loota_deffgun", 0) == 6 and post_type_counts2.get("loota_kmb", 0) == 2:
		print("  PASS: After 2 deffgun casualties: 6 deffgun, 2 KMB alive")
		passed += 1
	else:
		print("  FAIL: Counts after deffgun casualties: %s" % str(post_type_counts2))
		failed += 1

	# --- Test 20: Post-casualty weapon assignment reflects reduced models ---
	print("\n--- Test 20: Post-casualty weapon assignment reflects 6 deffgun models ---")
	var post2_weapons = _get_unit_ranged_weapons("U_LOOTAS_A", board)
	var alive_deffgun_shooters = 0
	for mid in post2_weapons:
		if "deffgun_ranged" in post2_weapons[mid]:
			alive_deffgun_shooters += 1
	if alive_deffgun_shooters == 6:
		print("  PASS: 6 alive deffgun models in weapon assignment")
		passed += 1
	else:
		print("  FAIL: Expected 6 deffgun shooters, got %d" % alive_deffgun_shooters)
		failed += 1

	# ═══════════════════════════════════════════════════════════════════════
	# PHASE 6: Save/Load round-trip — model_type preserved
	# ═══════════════════════════════════════════════════════════════════════

	print("\n═══ PHASE 6: Save/Load Round-Trip ═══\n")

	# --- Test 21: Serialize unit state to JSON ---
	print("--- Test 21: Serialize unit state to JSON ---")
	var game_state = {
		"meta": {"battle_round": 2, "active_player": 2, "phase": 3},
		"units": {"U_LOOTAS_A": deployed_unit},
		"_serialization": {"version": "1.1.0", "timestamp": "2026-03-09T12:00:00"}
	}
	var json_string = JSON.stringify(game_state)
	if not json_string.is_empty():
		print("  PASS: Serialized state to JSON (%d bytes)" % json_string.length())
		passed += 1
	else:
		print("  FAIL: Serialization produced empty string")
		failed += 1

	# --- Test 22: Deserialize and verify model_type preserved ---
	print("\n--- Test 22: Deserialize and verify model_type preserved ---")
	var json = JSON.new()
	var parse_err = json.parse(json_string)
	var loaded_state = json.data if parse_err == OK else {}
	var loaded_unit = loaded_state.get("units", {}).get("U_LOOTAS_A", {})
	var loaded_models = loaded_unit.get("models", [])
	var load_ok = true
	if loaded_models.size() != 11:
		print("  FAIL: Loaded models count is %d (expected 11)" % loaded_models.size())
		load_ok = false
	else:
		for m in loaded_models:
			var mt = m.get("model_type", "")
			if mt == "":
				print("  FAIL: Model %s has empty model_type after load" % m.get("id", ""))
				load_ok = false
	if load_ok:
		print("  PASS: All 11 models have model_type after deserialization")
		passed += 1
	else:
		failed += 1

	# --- Test 23: model_type values match original ---
	print("\n--- Test 23: model_type values match original after round-trip ---")
	var types_match = true
	for i in range(min(models.size(), loaded_models.size())):
		var orig_type = models[i].get("model_type", "")
		var loaded_type = loaded_models[i].get("model_type", "")
		if orig_type != loaded_type:
			print("  FAIL: Model %s type mismatch: orig=%s loaded=%s" % [models[i].get("id", ""), orig_type, loaded_type])
			types_match = false
	if types_match:
		print("  PASS: All model_type values match after round-trip")
		passed += 1
	else:
		failed += 1

	# --- Test 24: model_profiles preserved in meta ---
	print("\n--- Test 24: model_profiles preserved in unit meta after round-trip ---")
	var loaded_profiles = loaded_unit.get("meta", {}).get("model_profiles", {})
	if loaded_profiles.has("loota_deffgun") and loaded_profiles.has("loota_kmb") and loaded_profiles.has("spanner"):
		print("  PASS: model_profiles has loota_deffgun, loota_kmb, spanner after round-trip")
		passed += 1
	else:
		print("  FAIL: model_profiles missing keys after round-trip (got: %s)" % str(loaded_profiles.keys()))
		failed += 1

	# --- Test 25: Alive/dead status preserved after round-trip ---
	print("\n--- Test 25: Alive/dead status preserved after round-trip ---")
	var alive_match = true
	for i in range(min(deployed_models.size(), loaded_models.size())):
		var orig_alive = deployed_models[i].get("alive", true)
		var loaded_alive = loaded_models[i].get("alive", true)
		if orig_alive != loaded_alive:
			print("  FAIL: Model %s alive mismatch: orig=%s loaded=%s" % [deployed_models[i].get("id", ""), orig_alive, loaded_alive])
			alive_match = false
	# Specifically check the dead spanner and deffguns
	var loaded_m11 = _find_model(loaded_models, "m11")
	var loaded_m3 = _find_model(loaded_models, "m3")
	var loaded_m7 = _find_model(loaded_models, "m7")
	if loaded_m11.get("alive", true) != false:
		print("  FAIL: Spanner m11 should be dead after load")
		alive_match = false
	if loaded_m3.get("alive", true) != false:
		print("  FAIL: Deffgun m3 should be dead after load")
		alive_match = false
	if loaded_m7.get("alive", true) != false:
		print("  FAIL: Deffgun m7 should be dead after load")
		alive_match = false
	if alive_match:
		print("  PASS: Alive/dead status matches after round-trip (m3,m7,m11 dead)")
		passed += 1
	else:
		failed += 1

	# --- Test 26: Weapon assignments correct after reload ---
	print("\n--- Test 26: Weapon assignments correct after reload ---")
	var loaded_board = {"units": {"U_LOOTAS_A": loaded_unit}}
	var reloaded_weapons = _get_unit_ranged_weapons("U_LOOTAS_A", loaded_board)
	var reload_ok = true
	# Dead models should be excluded
	for dead_mid in ["m3", "m7", "m11"]:
		if reloaded_weapons.has(dead_mid):
			print("  FAIL: Dead model %s should not be in weapon assignment" % dead_mid)
			reload_ok = false
	# Alive deffgun models should still have deffgun
	for mid in ["m1", "m2", "m4", "m5", "m6", "m8"]:
		if not reloaded_weapons.has(mid) or "deffgun_ranged" not in reloaded_weapons[mid]:
			print("  FAIL: Alive deffgun %s missing deffgun_ranged after reload" % mid)
			reload_ok = false
	# Alive KMB models should still have KMB
	for mid in ["m9", "m10"]:
		if not reloaded_weapons.has(mid) or "kustom_mega_blasta_ranged" not in reloaded_weapons[mid]:
			print("  FAIL: Alive KMB %s missing kustom_mega_blasta_ranged after reload" % mid)
			reload_ok = false
	if reload_ok:
		print("  PASS: Weapon assignments correct after reload (dead excluded, alive assigned)")
		passed += 1
	else:
		failed += 1

	# --- Test 27: Profile stats_override preserved after round-trip ---
	print("\n--- Test 27: Profile stats_override preserved after round-trip ---")
	var loaded_spanner_profile = loaded_profiles.get("spanner", {})
	var loaded_spanner_bs = loaded_spanner_profile.get("stats_override", {}).get("ballistic_skill", null)
	if loaded_spanner_bs != null and int(loaded_spanner_bs) == 4:
		print("  PASS: spanner stats_override.ballistic_skill=4 preserved after round-trip")
		passed += 1
	else:
		print("  FAIL: spanner BS override expected 4, got %s" % str(loaded_spanner_bs))
		failed += 1

	# ═══════════════════════════════════════════════════════════════════════
	# PHASE 7: Multiplayer readiness — state snapshot has model types
	# ═══════════════════════════════════════════════════════════════════════

	print("\n═══ PHASE 7: Multiplayer Readiness ═══\n")

	# --- Test 28: State snapshot includes model_type for remote sync ---
	print("--- Test 28: State snapshot has model_type for network sync ---")
	# In multiplayer, the full state is synced via StateSerializer
	# Verify the JSON contains model_type fields that remote clients need
	var snapshot_ok = true
	if "model_type" not in json_string:
		print("  FAIL: Serialized state does not contain 'model_type' strings")
		snapshot_ok = false
	if "model_profiles" not in json_string:
		print("  FAIL: Serialized state does not contain 'model_profiles' data")
		snapshot_ok = false
	if "loota_deffgun" not in json_string:
		print("  FAIL: Serialized state does not contain 'loota_deffgun' profile key")
		snapshot_ok = false
	if "spanner" not in json_string:
		print("  FAIL: Serialized state does not contain 'spanner' profile key")
		snapshot_ok = false
	if snapshot_ok:
		print("  PASS: State snapshot contains model_type, model_profiles, and profile keys for remote sync")
		passed += 1
	else:
		failed += 1

	# --- Test 29: Remote client can reconstruct weapon assignment from snapshot ---
	print("\n--- Test 29: Remote client can reconstruct weapon assignments from snapshot ---")
	# Simulate a remote client receiving the serialized state and building weapons
	var remote_json = JSON.new()
	var remote_err = remote_json.parse(json_string)
	var remote_state = remote_json.data if remote_err == OK else {}
	var remote_unit = remote_state.get("units", {}).get("U_LOOTAS_A", {})
	var remote_board = {"units": {"U_LOOTAS_A": remote_unit}}
	var remote_weapons = _get_unit_ranged_weapons("U_LOOTAS_A", remote_board)
	var remote_ok = true
	# Should match what the host had after casualties
	if remote_weapons.size() != 8:  # 6 deffgun + 2 KMB (3 dead excluded)
		print("  FAIL: Remote weapon assignment has %d models (expected 8 alive)" % remote_weapons.size())
		remote_ok = false
	# Verify weapon type correctness
	for mid in remote_weapons:
		var model = _find_model(remote_unit.get("models", []), mid)
		var mt = model.get("model_type", "")
		if mt == "loota_deffgun" and "deffgun_ranged" not in remote_weapons[mid]:
			print("  FAIL: Remote deffgun %s missing deffgun weapon" % mid)
			remote_ok = false
		if mt == "loota_kmb" and "kustom_mega_blasta_ranged" not in remote_weapons[mid]:
			print("  FAIL: Remote KMB %s missing KMB weapon" % mid)
			remote_ok = false
	if remote_ok:
		print("  PASS: Remote client reconstructs correct weapon assignments from snapshot")
		passed += 1
	else:
		failed += 1

	# ═══════════════════════════════════════════════════════════════════════
	# PHASE 8: Backward Compatibility — units without model_profiles
	# ═══════════════════════════════════════════════════════════════════════

	print("\n═══ PHASE 8: Backward Compatibility ═══\n")

	# --- Test 30: Unit without model_profiles works identically ---
	print("--- Test 30: Unit without model_profiles (U_BOYZ_E) works unchanged ---")
	var boyz = army_data.get("units", {}).get("U_BOYZ_E", {})
	var boyz_meta = boyz.get("meta", {})
	var boyz_profiles = boyz_meta.get("model_profiles", {})
	var boyz_models = boyz.get("models", [])
	if boyz_profiles.is_empty() and boyz_models.size() > 0:
		# All models should get all ranged weapons
		var boyz_board = {"units": {"U_BOYZ_E": boyz}}
		var boyz_weapons = _get_unit_ranged_weapons("U_BOYZ_E", boyz_board)
		var all_same = true
		var first_weapons = boyz_weapons.get("m1", [])
		for mid in boyz_weapons:
			if boyz_weapons[mid].size() != first_weapons.size():
				all_same = false
		if all_same and boyz_weapons.size() == boyz_models.size():
			print("  PASS: %d models each get all %d ranged weapons (no profile restriction)" % [boyz_weapons.size(), first_weapons.size()])
			passed += 1
		else:
			print("  FAIL: Uneven weapon distribution for non-profiled unit")
			failed += 1
	else:
		print("  FAIL: U_BOYZ_E should have no model_profiles (got: %s)" % str(boyz_profiles.keys()))
		failed += 1

	# --- Test 31: Backward-compat unit save/load works ---
	print("\n--- Test 31: Backward-compat unit save/load round-trip ---")
	var compat_state = {
		"meta": {"battle_round": 1},
		"units": {"U_BOYZ_E": boyz},
		"_serialization": {"version": "1.1.0"}
	}
	var compat_json = JSON.stringify(compat_state)
	var compat_parser = JSON.new()
	var compat_err = compat_parser.parse(compat_json)
	var compat_loaded = compat_parser.data if compat_err == OK else {}
	var compat_unit = compat_loaded.get("units", {}).get("U_BOYZ_E", {})
	var compat_models = compat_unit.get("models", [])
	if compat_models.size() == boyz_models.size():
		print("  PASS: Backward-compat unit round-trips correctly (%d models)" % compat_models.size())
		passed += 1
	else:
		print("  FAIL: Model count mismatch after round-trip (%d vs %d)" % [compat_models.size(), boyz_models.size()])
		failed += 1

	# ═══════════════════════════════════════════════════════════════════════
	# PHASE 9: Edge Cases
	# ═══════════════════════════════════════════════════════════════════════

	print("\n═══ PHASE 9: Edge Cases ═══\n")

	# --- Test 32: All models dead — weapon assignment returns empty ---
	print("--- Test 32: All models dead — weapon assignment returns empty ---")
	var dead_unit = deployed_unit.duplicate(true)
	for m in dead_unit.get("models", []):
		m["alive"] = false
		m["current_wounds"] = 0
	var dead_board = {"units": {"U_DEAD": dead_unit}}
	dead_unit["id"] = "U_DEAD"
	dead_board["units"] = {"U_DEAD": dead_unit}
	var dead_weapons = _get_unit_ranged_weapons("U_DEAD", dead_board)
	if dead_weapons.is_empty():
		print("  PASS: All-dead unit has no weapon assignments")
		passed += 1
	else:
		print("  FAIL: Expected empty weapons, got %d entries" % dead_weapons.size())
		failed += 1

	# --- Test 33: melee weapons respect model profiles too ---
	print("\n--- Test 33: Melee weapons respect model profiles ---")
	var melee_weapons = _get_unit_melee_weapons("U_LOOTAS_A", board)
	var melee_ok = true
	# All alive Lootas models have "Close combat weapon" in their profile
	# m3, m7, m11 are dead — they should be excluded
	for mid_key in melee_weapons:
		if "Close combat weapon" not in melee_weapons[mid_key]:
			print("  FAIL: Model %s missing 'Close combat weapon' in melee" % mid_key)
			melee_ok = false
	# Dead models excluded
	var dead_model_indices = []
	for i in range(deployed_models.size()):
		if not deployed_models[i].get("alive", true):
			dead_model_indices.append(i)
	for dead_idx in dead_model_indices:
		var dead_mid = "m" + str(dead_idx)
		if melee_weapons.has(dead_mid):
			print("  FAIL: Dead model index %s should be excluded from melee" % dead_mid)
			melee_ok = false
	if melee_ok:
		print("  PASS: Melee weapons respect profiles — alive models get CCW, dead excluded")
		passed += 1
	else:
		failed += 1

	# --- Test 34: Profile weapon list accuracy check ---
	print("\n--- Test 34: Profile weapon lists reference only existing weapons ---")
	var weapon_names_in_meta = []
	for w in meta.get("weapons", []):
		weapon_names_in_meta.append(w.get("name", ""))
	var ref_ok = true
	for profile_key in mp:
		for wname in mp[profile_key].get("weapons", []):
			if wname not in weapon_names_in_meta:
				print("  FAIL: Profile %s references weapon '%s' not in meta.weapons" % [profile_key, wname])
				ref_ok = false
	if ref_ok:
		print("  PASS: All profile weapon references are valid")
		passed += 1
	else:
		failed += 1

	# --- Summary ---
	print("\n═══════════════════════════════════════════════════════════════")
	print("=== MA-32 Integration Results: %d passed, %d failed ===" % [passed, failed])
	print("═══════════════════════════════════════════════════════════════")
	if failed > 0:
		print("SOME TESTS FAILED")
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)


# ═══════════════════════════════════════════════════════════════════════
# Helper functions
# ═══════════════════════════════════════════════════════════════════════

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

func _find_model(models: Array, model_id: String) -> Dictionary:
	for m in models:
		if m.get("id", "") == model_id:
			return m
	return {}

func _count_model_types(models: Array) -> Dictionary:
	var counts = {}
	for m in models:
		var mt = m.get("model_type", "")
		counts[mt] = counts.get(mt, 0) + 1
	return counts

func _count_alive_model_types(models: Array) -> Dictionary:
	var counts = {}
	for m in models:
		if m.get("alive", true):
			var mt = m.get("model_type", "")
			counts[mt] = counts.get(mt, 0) + 1
	return counts

func _build_save_profiles(unit: Dictionary) -> Array:
	var models_arr = unit.get("models", [])
	var unit_save = unit.get("meta", {}).get("stats", {}).get("save", 7)
	var model_profiles = unit.get("meta", {}).get("model_profiles", {})
	var profiles = []
	for m in models_arr:
		if not m.get("alive", true):
			continue
		var mt = m.get("model_type", "")
		var model_save = unit_save
		if model_profiles.has(mt):
			var so = model_profiles[mt].get("stats_override", {}).get("save", -1)
			if so > 0:
				model_save = int(so)
		profiles.append({
			"model_id": m.get("id", ""),
			"model_type": mt,
			"save": model_save,
			"current_wounds": m.get("current_wounds", 1),
		})
	return profiles

# ═══════════════════════════════════════════════════════════════════════
# Weapon assignment helpers (mirror RulesEngine logic)
# ═══════════════════════════════════════════════════════════════════════

func _gen_weapon_id(weapon_name: String, weapon_type: String = "") -> String:
	var wid = weapon_name.to_lower()
	wid = wid.replace(" ", "_")
	wid = wid.replace("-", "_")
	wid = wid.replace("–", "_")
	wid = wid.replace("'", "")
	if weapon_type != "":
		wid += "_" + weapon_type.to_lower()
	return wid

func _get_model_weapon_ids(unit: Dictionary, model: Dictionary, type_filter: String) -> Array:
	var weapons_data = unit.get("meta", {}).get("weapons", [])
	var model_profiles = unit.get("meta", {}).get("model_profiles", {})
	var model_type = model.get("model_type", "")
	var use_profile = not model_profiles.is_empty() and model_type != "" and model_profiles.has(model_type)
	var allowed_weapon_names = []
	if use_profile:
		allowed_weapon_names = model_profiles[model_type].get("weapons", [])
	var weapon_ids = []
	for weapon in weapons_data:
		var wtype = weapon.get("type", "")
		if wtype.to_lower() != type_filter.to_lower():
			continue
		var wname = weapon.get("name", "")
		if use_profile and wname not in allowed_weapon_names:
			continue
		var weapon_id = _gen_weapon_id(wname, wtype)
		if weapon_id not in weapon_ids:
			weapon_ids.append(weapon_id)
	return weapon_ids

func _get_unit_ranged_weapons(unit_id: String, board: Dictionary) -> Dictionary:
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	if unit.is_empty():
		return {}
	var result = {}
	for model in unit.get("models", []):
		var model_id = model.get("id", "")
		if model_id != "" and model.get("alive", true):
			result[model_id] = _get_model_weapon_ids(unit, model, "Ranged")
	return result

func _get_unit_melee_weapons(unit_id: String, board: Dictionary) -> Dictionary:
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	if unit.is_empty():
		return {}
	var weapons_data = unit.get("meta", {}).get("weapons", [])
	var model_profiles = unit.get("meta", {}).get("model_profiles", {})
	var all_melee = []
	for w in weapons_data:
		if w.get("type", "").to_lower() == "melee":
			var wn = w.get("name", "Unknown Weapon")
			if wn not in all_melee:
				all_melee.append(wn)
	var result = {}
	var models_arr = unit.get("models", [])
	for i in range(models_arr.size()):
		var model = models_arr[i]
		if not model.get("alive", true):
			continue
		var model_id = "m" + str(i)
		var model_type = model.get("model_type", "")
		if not model_profiles.is_empty() and model_type != "" and model_profiles.has(model_type):
			var prof_weapons = model_profiles[model_type].get("weapons", [])
			var model_melee = []
			for w in weapons_data:
				if w.get("type", "").to_lower() == "melee" and w.get("name", "") in prof_weapons:
					var wn = w.get("name", "Unknown Weapon")
					if wn not in model_melee:
						model_melee.append(wn)
			if not model_melee.is_empty():
				result[model_id] = model_melee
		else:
			if not all_melee.is_empty():
				result[model_id] = all_melee.duplicate()
	return result

# ═══════════════════════════════════════════════════════════════════════
# Combat resolution helpers (mirror RulesEngine logic)
# ═══════════════════════════════════════════════════════════════════════

func _get_model_effective_bs(model: Dictionary, unit: Dictionary, weapon_profile: Dictionary) -> int:
	var default_bs = weapon_profile.get("bs", 4)
	if model.is_empty():
		return default_bs
	var model_type = model.get("model_type", "")
	if model_type == "":
		return default_bs
	var model_profiles = unit.get("meta", {}).get("model_profiles", {})
	if not model_profiles.has(model_type):
		return default_bs
	var override_bs = model_profiles[model_type].get("stats_override", {}).get("ballistic_skill", -1)
	if override_bs > 0:
		return int(override_bs)
	return default_bs
