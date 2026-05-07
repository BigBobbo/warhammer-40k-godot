extends SceneTree

# Issue #391: validate that ORKS IS NEVER BEATEN's effect_swing_back_before_remove
# flag triggers a swing-back attack pass for dying models BEFORE they're removed.
#
# Test 1: Boyz unit with the flag attacked by a one-shot melee attacker; dying
#         Boyz swing back, producing additional hit/wound dice with the Boyz's
#         choppa weapon at the original attacker.
# Test 2: Same setup WITHOUT the flag — no swing-back attack pass.
# Test 3: Models that already fought this phase do NOT swing back.
#
# Run via: godot --headless --path 40k --script tests/test_orks_is_never_beaten_swing_back_391.gd

var _re = null
var _ep = null


func _initialize():
	await create_timer(0.1).timeout
	_re = root.get_node_or_null("RulesEngine")
	_ep = preload("res://autoloads/EffectPrimitives.gd")
	if _re == null:
		print("FAIL: missing RulesEngine autoload")
		quit(1)
		return
	_run_tests()


func _run_tests():
	print("\n=== Issue #391: ORKS IS NEVER BEATEN swing-back deferral ===\n")
	var passed = 0
	var failed = 0

	# --- Test 1: with flag, Boyz die and swing back ---
	print("--- Test 1: Boyz with flag — dying models swing back at attacker ---")
	var board1 = _make_board(true, false)
	var action = {
		"actor_unit_id": "U_KILLER",
		"payload": {
			"assignments": [{
				"attacker": "U_KILLER",
				"target": "U_BOYZ_TEST",
				"weapon": "Killer blade",
				"models": ["0"]
			}]
		}
	}
	var rng = _re.RNGService.new(7)
	var result1 = _re.resolve_melee_attacks(action, board1, rng)
	# Count Boyz alive=false diffs (deaths) AND check for swing-back wound dice
	# attributed to U_BOYZ_TEST attacking U_KILLER.
	var deaths = 0
	for d in result1.get("diffs", []):
		if d.get("path", "").begins_with("units.U_BOYZ_TEST.models.") and d.get("path", "").ends_with(".alive") and d.get("value") == false:
			deaths += 1
	var swing_back_hit_rolls = 0
	var saw_swing_back_log = "ORKS IS NEVER BEATEN" in result1.get("log_text", "")
	for d in result1.get("dice", []):
		if d.get("context", "") == "hit_roll_melee":
			# Both the original attack AND the swing-back will emit hit_roll_melee.
			# Count separately by checking if rolls_raw is non-empty.
			swing_back_hit_rolls += d.get("rolls_raw", []).size()
	if deaths > 0:
		print("[PASS] %d Boyz died" % deaths)
		passed += 1
	else:
		print("[FAIL] no Boyz deaths recorded")
		failed += 1
	# We expect at least 2 hit_roll_melee blocks: 1 from attacker, 1 from swing-back.
	var melee_dice_blocks = 0
	for d in result1.get("dice", []):
		if d.get("context", "") == "hit_roll_melee":
			melee_dice_blocks += 1
	if melee_dice_blocks >= 2:
		print("[PASS] swing-back attack pass produced an extra hit_roll_melee dice block (total: %d)" % melee_dice_blocks)
		passed += 1
	else:
		print("[FAIL] expected >=2 hit_roll_melee dice blocks, got %d" % melee_dice_blocks)
		failed += 1

	# --- Test 2: without flag, no swing-back ---
	print("\n--- Test 2: Boyz WITHOUT flag — no swing-back ---")
	var board2 = _make_board(false, false)
	var rng2 = _re.RNGService.new(7)
	var result2 = _re.resolve_melee_attacks(action, board2, rng2)
	var melee_dice_blocks_2 = 0
	for d in result2.get("dice", []):
		if d.get("context", "") == "hit_roll_melee":
			melee_dice_blocks_2 += 1
	if melee_dice_blocks_2 == 1:
		print("[PASS] without flag: only 1 hit_roll_melee block (no swing-back)")
		passed += 1
	else:
		print("[FAIL] without flag: expected 1, got %d" % melee_dice_blocks_2)
		failed += 1

	# --- Test 3: with flag but Boyz already fought this phase — no swing-back ---
	print("\n--- Test 3: Boyz with flag but already fought_this_phase=true — no swing-back ---")
	var board3 = _make_board(true, true)
	var rng3 = _re.RNGService.new(7)
	var result3 = _re.resolve_melee_attacks(action, board3, rng3)
	var melee_dice_blocks_3 = 0
	for d in result3.get("dice", []):
		if d.get("context", "") == "hit_roll_melee":
			melee_dice_blocks_3 += 1
	if melee_dice_blocks_3 == 1:
		print("[PASS] already-fought: only 1 hit_roll_melee block (no swing-back)")
		passed += 1
	else:
		print("[FAIL] already-fought: expected 1, got %d" % melee_dice_blocks_3)
		failed += 1

	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		quit(1)
	else:
		quit(0)


func _make_board(swing_back_flag: bool, models_fought: bool) -> Dictionary:
	# Killer unit: 1 model with high-S, high-Damage melee weapon designed to one-shot Boyz.
	var killer = {
		"id": "U_KILLER",
		"owner": 1,
		"status": 2,
		"meta": {
			"name": "Killer",
			"keywords": ["INFANTRY"],
			"stats": {"move": 6, "toughness": 5, "save": 3, "wounds": 4, "objective_control": 1},
			"weapons": [{
				"id": "killer_blade",
				"name": "Killer blade",
				"type": "Melee",
				"range": "Melee",
				"attacks": "6",
				"weapon_skill": "2",
				"strength": "10",
				"ap": "-3",
				"damage": "3"
			}],
			"abilities": []
		},
		"models": [{"id": "k1", "wounds": 4, "current_wounds": 4, "alive": true, "position": {"x": 200, "y": 200}, "base_mm": 32}],
		"flags": {}
	}
	# Boyz: 5 models, T5 W1 5+. Flag controls swing-back behaviour.
	var boyz_models = []
	for i in range(5):
		var m = {"id": "b%d" % (i + 1), "wounds": 1, "current_wounds": 1, "alive": true, "position": {"x": 200 + i * 10, "y": 252}, "base_mm": 32, "flags": {}}
		if models_fought:
			m["flags"]["fought_this_phase"] = true
		boyz_models.append(m)
	var boyz_flags = {}
	if swing_back_flag:
		boyz_flags["effect_swing_back_before_remove"] = true
	var boyz = {
		"id": "U_BOYZ_TEST",
		"owner": 2,
		"status": 2,
		"meta": {
			"name": "Boyz",
			"keywords": ["INFANTRY", "ORKS"],
			"stats": {"move": 6, "toughness": 5, "save": 5, "wounds": 1, "objective_control": 2},
			"weapons": [{
				"id": "boyz_choppa",
				"name": "Choppa",
				"type": "Melee",
				"range": "Melee",
				"attacks": "3",
				"weapon_skill": "3",
				"strength": "4",
				"ap": "-1",
				"damage": "1"
			}],
			"abilities": []
		},
		"models": boyz_models,
		"flags": boyz_flags
	}
	return {
		"units": {"U_KILLER": killer, "U_BOYZ_TEST": boyz},
		"meta": {"battle_round": 1, "active_player": 1}
	}
