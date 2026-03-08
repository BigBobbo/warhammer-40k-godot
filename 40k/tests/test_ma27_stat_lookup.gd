extends SceneTree

# Test: MA-27 Per-model stat lookup helper
# Verifies RulesEngine.get_model_effective_stats(unit, model) returns correct merged stats
# Usage: godot --headless --path . -s tests/test_ma27_stat_lookup.gd

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
	print("\n=== Test MA-27: Per-Model Stat Lookup Helper ===\n")
	var passed = 0
	var failed = 0

	var unit = _make_lootas_unit()
	var base_stats = unit.get("meta", {}).get("stats", {})
	print("  Unit base stats: %s" % str(base_stats))

	# --- Test 1: Deffgun Loota model returns unit base stats (empty stats_override) ---
	print("\n--- Test 1: Deffgun Loota model → returns unit base stats ---")
	var deffgun_model = unit["models"][0]  # loota_deffgun
	var effective = _re.get_model_effective_stats(unit, deffgun_model)
	print("  Effective stats: %s" % str(effective))
	if _stats_equal(effective, base_stats):
		print("  PASS: Deffgun Loota returns base stats (empty override)")
		passed += 1
	else:
		print("  FAIL: Deffgun Loota stats differ from base. Got %s, expected %s" % [str(effective), str(base_stats)])
		failed += 1

	# --- Test 2: Spanner model returns base stats with BS overridden to 4 ---
	print("\n--- Test 2: Spanner model → returns base stats with ballistic_skill=4 ---")
	var spanner_model = unit["models"][10]  # spanner
	effective = _re.get_model_effective_stats(unit, spanner_model)
	print("  Effective stats: %s" % str(effective))
	var actual_bs = effective.get("ballistic_skill", -1)
	if actual_bs == 4:
		print("  PASS: Spanner BS overridden to 4")
		passed += 1
	else:
		print("  FAIL: Spanner BS expected 4, got %s" % str(actual_bs))
		failed += 1

	# --- Test 3: Spanner retains non-overridden base stats ---
	print("\n--- Test 3: Spanner retains non-overridden base stats ---")
	effective = _re.get_model_effective_stats(unit, spanner_model)
	var ok = true
	for key in base_stats:
		if key == "ballistic_skill":
			continue  # This is overridden
		if effective.get(key) != base_stats.get(key):
			print("  FAIL: Spanner stat '%s' expected %s, got %s" % [key, str(base_stats[key]), str(effective.get(key))])
			ok = false
	if ok:
		print("  PASS: Spanner retains all non-overridden base stats")
		passed += 1
	else:
		failed += 1

	# --- Test 4: Model without model_type returns unit base stats ---
	print("\n--- Test 4: Model without model_type → returns unit base stats ---")
	var no_type_model = {"id": "m_test", "wounds": 1, "alive": true}
	effective = _re.get_model_effective_stats(unit, no_type_model)
	print("  Effective stats: %s" % str(effective))
	if _stats_equal(effective, base_stats):
		print("  PASS: Model without model_type returns base stats")
		passed += 1
	else:
		print("  FAIL: Expected base stats, got %s" % str(effective))
		failed += 1

	# --- Test 5: Unit without model_profiles returns unit base stats ---
	print("\n--- Test 5: Unit without model_profiles → returns unit base stats ---")
	var plain_unit = _make_plain_unit()
	var plain_stats = plain_unit.get("meta", {}).get("stats", {})
	var plain_model = plain_unit["models"][0]
	effective = _re.get_model_effective_stats(plain_unit, plain_model)
	print("  Plain base stats: %s" % str(plain_stats))
	print("  Effective stats: %s" % str(effective))
	if _stats_equal(effective, plain_stats):
		print("  PASS: Unit without model_profiles returns base stats")
		passed += 1
	else:
		print("  FAIL: Expected base stats, got %s" % str(effective))
		failed += 1

	# --- Test 6: Empty model dict returns unit base stats ---
	print("\n--- Test 6: Empty model dict → returns unit base stats ---")
	effective = _re.get_model_effective_stats(unit, {})
	if _stats_equal(effective, base_stats):
		print("  PASS: Empty model returns base stats")
		passed += 1
	else:
		print("  FAIL: Expected base stats for empty model, got %s" % str(effective))
		failed += 1

	# --- Test 7: Does not mutate unit base stats ---
	print("\n--- Test 7: Does not mutate original unit base stats ---")
	var before_stats = unit.get("meta", {}).get("stats", {}).duplicate()
	var _spanner_eff = _re.get_model_effective_stats(unit, spanner_model)
	var after_stats = unit.get("meta", {}).get("stats", {})
	if _stats_equal(before_stats, after_stats):
		print("  PASS: Unit base stats not mutated by get_model_effective_stats")
		passed += 1
	else:
		print("  FAIL: Unit base stats were mutated! Before: %s, After: %s" % [str(before_stats), str(after_stats)])
		failed += 1

	# --- Test 8: Multiple overrides (leadership + attacks, like an Intercessor Sergeant) ---
	print("\n--- Test 8: Multiple stats_override keys merge correctly ---")
	var sgt_unit = _make_multi_override_unit()
	var sgt_model = sgt_unit["models"][0]  # sergeant with leadership=6, attacks=4
	var sgt_base = sgt_unit.get("meta", {}).get("stats", {})
	effective = _re.get_model_effective_stats(sgt_unit, sgt_model)
	print("  Base stats: %s" % str(sgt_base))
	print("  Effective stats: %s" % str(effective))
	if effective.get("leadership") == 6 and effective.get("attacks") == 4:
		print("  PASS: Multiple overrides applied (leadership=6, attacks=4)")
		passed += 1
	else:
		print("  FAIL: Expected leadership=6, attacks=4. Got leadership=%s, attacks=%s" % [str(effective.get("leadership")), str(effective.get("attacks"))])
		failed += 1

	# --- Test 9: Non-overridden stats in multi-override unit ---
	print("\n--- Test 9: Non-overridden stats preserved in multi-override unit ---")
	ok = true
	for key in sgt_base:
		if key in ["leadership", "attacks"]:
			continue  # These are overridden
		if effective.get(key) != sgt_base.get(key):
			print("  FAIL: Stat '%s' expected %s, got %s" % [key, str(sgt_base[key]), str(effective.get(key))])
			ok = false
	if ok:
		print("  PASS: Non-overridden stats preserved")
		passed += 1
	else:
		failed += 1

	# Summary
	print("\n=== MA-27 Results: %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		print("FAIL")
		quit(1)
	else:
		print("ALL PASS")
		quit(0)

# Build a test Lootas unit with model_profiles (matching orks.json structure)
func _make_lootas_unit() -> Dictionary:
	var models = []
	# 8 deffgun models
	for i in range(8):
		models.append({
			"id": "m%d" % (i + 1),
			"wounds": 1,
			"current_wounds": 1,
			"base_mm": 32,
			"alive": true,
			"model_type": "loota_deffgun"
		})
	# 2 kmb models
	for i in range(2):
		models.append({
			"id": "m%d" % (i + 9),
			"wounds": 1,
			"current_wounds": 1,
			"base_mm": 32,
			"alive": true,
			"model_type": "loota_kmb"
		})
	# 1 spanner
	models.append({
		"id": "m11",
		"wounds": 1,
		"current_wounds": 1,
		"base_mm": 32,
		"alive": true,
		"model_type": "spanner"
	})

	return {
		"id": "U_LOOTAS",
		"owner": 2,
		"meta": {
			"name": "Lootas",
			"stats": {
				"move": 6,
				"toughness": 5,
				"save": 5,
				"wounds": 1,
				"leadership": 7,
				"objective_control": 1
			},
			"model_profiles": {
				"loota_deffgun": {
					"label": "Loota (Deffgun)",
					"stats_override": {},
					"weapons": ["Deffgun", "Close combat weapon"],
					"transport_slots": 1
				},
				"loota_kmb": {
					"label": "Loota (Kustom Mega-blasta)",
					"stats_override": {},
					"weapons": ["Kustom mega-blasta", "Close combat weapon"],
					"transport_slots": 1
				},
				"spanner": {
					"label": "Spanner",
					"stats_override": {"ballistic_skill": 4},
					"weapons": ["Kustom mega-blasta", "Close combat weapon"],
					"transport_slots": 1
				}
			}
		},
		"models": models
	}

# Build a plain unit without model_profiles
func _make_plain_unit() -> Dictionary:
	return {
		"id": "U_WARBOSS",
		"owner": 2,
		"meta": {
			"name": "Warboss",
			"stats": {
				"move": 6,
				"toughness": 5,
				"save": 4,
				"wounds": 6,
				"leadership": 6,
				"objective_control": 1
			}
		},
		"models": [
			{"id": "m1", "wounds": 6, "current_wounds": 6, "alive": true}
		]
	}

# Build a unit with multiple overridden stats (like Intercessor Sergeant)
func _make_multi_override_unit() -> Dictionary:
	return {
		"id": "U_INTERCESSORS",
		"owner": 1,
		"meta": {
			"name": "Intercessor Squad",
			"stats": {
				"move": 6,
				"toughness": 4,
				"save": 3,
				"wounds": 2,
				"leadership": 7,
				"attacks": 3,
				"objective_control": 2
			},
			"model_profiles": {
				"intercessor_sergeant": {
					"label": "Intercessor Sergeant",
					"stats_override": {"leadership": 6, "attacks": 4},
					"weapons": ["Bolt rifle", "Bolt pistol", "Power fist"],
					"transport_slots": 1
				},
				"intercessor": {
					"label": "Intercessor",
					"stats_override": {},
					"weapons": ["Bolt rifle", "Bolt pistol", "Close combat weapon"],
					"transport_slots": 1
				}
			}
		},
		"models": [
			{"id": "m1", "wounds": 2, "current_wounds": 2, "alive": true, "model_type": "intercessor_sergeant"},
			{"id": "m2", "wounds": 2, "current_wounds": 2, "alive": true, "model_type": "intercessor"},
			{"id": "m3", "wounds": 2, "current_wounds": 2, "alive": true, "model_type": "intercessor"},
			{"id": "m4", "wounds": 2, "current_wounds": 2, "alive": true, "model_type": "intercessor"},
			{"id": "m5", "wounds": 2, "current_wounds": 2, "alive": true, "model_type": "intercessor"}
		]
	}

func _stats_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a:
		if not b.has(key) or a[key] != b[key]:
			return false
	return true
