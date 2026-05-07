extends SceneTree

# Issue #395: validate that RulesEngine._resolve_melee_assignment reads the
# effect_plus_strength_melee flag and bumps the wound threshold accordingly.
#
# Approach (mirrors test_ma11_per_model_ws.gd): synthesize a melee board with
# attacker models within engagement range of target models. Run resolve over
# many trials with the flag = 0 and with the flag = 1. The setup is S5 vs T6
# (wound 5+ → ~33%) without the flag, S6 vs T6 (wound 4+ → ~50%) with it.
# A statistical gap > 0.10 between the two wound rates proves the flag is
# being consumed.
#
# Run via: godot --headless --path 40k --script tests/test_hall_of_armouries_resolve_395.gd

var _re = null


func _initialize():
	await create_timer(0.1).timeout
	_re = root.get_node_or_null("RulesEngine")
	if _re == null:
		print("FAIL: Could not get RulesEngine autoload")
		quit(1)
		return
	_run_tests()


func _run_tests():
	print("\n=== Issue #395: Hall of Armouries melee strength bump ===\n")
	var passed = 0
	var failed = 0

	var num_trials = 200

	# --- Run 1: WITHOUT flag (S5 vs T6, wound 5+, ~33% expected) ---
	print("--- Run 1: effect_plus_strength_melee NOT set (baseline S5 vs T6) ---")
	var baseline_wounds = 0
	var baseline_attacks = 0
	for trial in range(num_trials):
		var rng = _re.RNGService.new(trial)
		var board = _make_board(0)
		var assignment = {
			"attacker": "U_HOA_TEST",
			"target": "U_HOA_VICTIM",
			"weapon": "Hall test blade",
			"models": ["0"]
		}
		var result = _re._resolve_melee_assignment(assignment, "U_HOA_TEST", board, rng)
		for dice_entry in result.get("dice", []):
			if dice_entry.get("context", "") == "wound_roll_melee":
				baseline_wounds += dice_entry.get("successes", 0)
				baseline_attacks += dice_entry.get("rolls_raw", []).size()
	var baseline_rate = float(baseline_wounds) / float(baseline_attacks) if baseline_attacks > 0 else 0.0
	print("  baseline: %d wounds / %d wound-rolls = %.3f (expected ~0.33)" % [baseline_wounds, baseline_attacks, baseline_rate])

	# --- Run 2: WITH flag = 1 (S6 vs T6, wound 4+, ~50% expected) ---
	print("\n--- Run 2: effect_plus_strength_melee = 1 (bumped S6 vs T6) ---")
	var bumped_wounds = 0
	var bumped_attacks = 0
	for trial in range(num_trials):
		var rng = _re.RNGService.new(trial)
		var board = _make_board(1)
		var assignment = {
			"attacker": "U_HOA_TEST",
			"target": "U_HOA_VICTIM",
			"weapon": "Hall test blade",
			"models": ["0"]
		}
		var result = _re._resolve_melee_assignment(assignment, "U_HOA_TEST", board, rng)
		for dice_entry in result.get("dice", []):
			if dice_entry.get("context", "") == "wound_roll_melee":
				bumped_wounds += dice_entry.get("successes", 0)
				bumped_attacks += dice_entry.get("rolls_raw", []).size()
	var bumped_rate = float(bumped_wounds) / float(bumped_attacks) if bumped_attacks > 0 else 0.0
	print("  bumped: %d wounds / %d wound-rolls = %.3f (expected ~0.50)" % [bumped_wounds, bumped_attacks, bumped_rate])

	# --- Assertion 1: baseline within sanity range ---
	if baseline_attacks > 0 and baseline_rate >= 0.18 and baseline_rate <= 0.48:
		print("\n[PASS] baseline rate %.3f within [0.18, 0.48] for S5 vs T6 (wound 5+)" % baseline_rate)
		passed += 1
	else:
		print("\n[FAIL] baseline rate %.3f NOT within [0.18, 0.48]" % baseline_rate)
		failed += 1

	# --- Assertion 2: bumped within sanity range ---
	if bumped_attacks > 0 and bumped_rate >= 0.35 and bumped_rate <= 0.65:
		print("[PASS] bumped rate %.3f within [0.35, 0.65] for S6 vs T6 (wound 4+)" % bumped_rate)
		passed += 1
	else:
		print("[FAIL] bumped rate %.3f NOT within [0.35, 0.65]" % bumped_rate)
		failed += 1

	# --- Assertion 3: bumped is meaningfully higher than baseline (proves consumption) ---
	var rate_delta = bumped_rate - baseline_rate
	if rate_delta >= 0.08:
		print("[PASS] bumped rate exceeds baseline by %.3f (>= 0.08 confirms flag consumed)" % rate_delta)
		passed += 1
	else:
		print("[FAIL] rate delta %.3f insufficient — flag may not be consumed" % rate_delta)
		failed += 1

	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		quit(1)
	else:
		quit(0)


func _make_board(plus_s_melee: int) -> Dictionary:
	# Attacker model at (200,200), target model at (200,252) — same x, 52px apart.
	# 32mm bases (~50px) put edge-to-edge distance ~2px, well within 1" (40px) ER.
	var attacker_models = [
		{"id": "m1", "wounds": 4, "current_wounds": 4, "alive": true, "position": Vector2(200, 200), "base_mm": 32}
	]
	var target_models = [
		{"id": "t1", "wounds": 1, "current_wounds": 1, "alive": true, "position": Vector2(200, 252), "base_mm": 32}
	]
	var attacker_unit := {
		"id": "U_HOA_TEST",
		"owner": 1,
		"meta": {
			"name": "Hall Tester",
			"keywords": ["INFANTRY", "CHARACTER"],
			"stats": {"move": 6, "toughness": 4, "save": 3, "wounds": 4},
			"weapons": [{
				"id": "hoa_blade",
				"name": "Hall test blade",
				"type": "Melee",
				"range": "Melee",
				"attacks": "4",
				"weapon_skill": "3",
				"strength": "5",
				"ap": "0",
				"damage": "1"
			}],
			"abilities": []
		},
		"models": attacker_models,
		"flags": {}
	}
	if plus_s_melee > 0:
		attacker_unit.flags["effect_plus_strength_melee"] = plus_s_melee

	return {
		"units": {
			"U_HOA_TEST": attacker_unit,
			"U_HOA_VICTIM": {
				"id": "U_HOA_VICTIM",
				"owner": 2,
				"meta": {
					"name": "Hall Victim",
					"keywords": ["INFANTRY"],
					"stats": {"move": 6, "toughness": 6, "save": 4, "wounds": 1},
					"weapons": [],
					"abilities": []
				},
				"models": target_models,
				"flags": {}
			}
		},
		"meta": {"battle_round": 1, "active_player": 1}
	}
