extends SceneTree

# Issue #390: validate that CAREEN! translates the destroyed Deadly Demise
# unit to a player-chosen destination BEFORE the mortal-wound roll resolves,
# so MW are dealt at the new position.
#
# Run via: godot --headless --path 40k --script tests/test_careen_resolve_390.gd

var _re = null


func _initialize():
	await create_timer(0.1).timeout
	_re = root.get_node_or_null("RulesEngine")
	if _re == null:
		print("FAIL: missing RulesEngine autoload")
		quit(1)
		return
	_run_tests()


func _run_tests():
	print("\n=== Issue #390: CAREEN! resolution-side move + deadly-demise resolve ===\n")
	var passed = 0
	var failed = 0

	# Force the D6 trigger to roll 6 reliably via dense RNG seed sweep.
	var trigger_seed_for_6 = _find_seed_that_rolls_6()
	if trigger_seed_for_6 == -1:
		print("[FAIL] could not find an RNG seed where roll_d6 returns 6 in [0,500]")
		failed += 1
		quit(1)
		return
	print("Using RNG seed %d (rolls 6 on first roll_d6)" % trigger_seed_for_6)

	# --- Test 1: WITHOUT CAREEN — target unit outside 6" of original position, gets 0 MW ---
	print("\n--- Test 1: no CAREEN! — target at 10\" range, no MW dealt ---")
	var board1 = _make_board()
	var rng1 = _re.RNGService.new(trigger_seed_for_6)
	var result1 = _re.resolve_deadly_demise("U_BATTLEWAGON_TEST", "D6", board1, rng1)
	if not result1.triggered:
		print("[FAIL] expected trigger=true with seed %d, got %s" % [trigger_seed_for_6, str(result1)])
		failed += 1
	elif result1.per_target.size() == 0:
		print("[PASS] without CAREEN!: 0 targets in 6\" of (200, 200) — confirmed no MW dealt")
		passed += 1
	else:
		print("[FAIL] expected 0 targets, got %d: %s" % [result1.per_target.size(), str(result1.per_target)])
		failed += 1

	# --- Test 2: WITH CAREEN — translate to (200, 500), target at (200, 600) now within 2.5" ---
	print("\n--- Test 2: CAREEN! to (200, 500) — target now within 6\", MW dealt ---")
	var board2 = _make_board()
	var armed = _re.queue_careen_move("U_BATTLEWAGON_TEST", Vector2(200, 500), board2)
	if not armed:
		print("[FAIL] queue_careen_move returned false")
		failed += 1
	else:
		print("[PASS] queue_careen_move armed flag")
		passed += 1
	# Confirm flag set
	var flags_after_arm = board2.units.U_BATTLEWAGON_TEST.flags
	if flags_after_arm.get("effect_careen_pending_move", false) and flags_after_arm.has("careen_destination"):
		print("[PASS] flags effect_careen_pending_move=true and careen_destination set")
		passed += 1
	else:
		print("[FAIL] flags incorrect: %s" % str(flags_after_arm))
		failed += 1

	var rng2 = _re.RNGService.new(trigger_seed_for_6)
	var result2 = _re.resolve_deadly_demise("U_BATTLEWAGON_TEST", "D6", board2, rng2)
	if not result2.triggered:
		print("[FAIL] expected trigger=true with seed %d in CAREEN run" % trigger_seed_for_6)
		failed += 1
	# After CAREEN, the Battlewagon model should be at (200, 500), and target at (200, 600) is 100px = 2.5" away.
	var bw_pos = board2.units.U_BATTLEWAGON_TEST.models[0].position
	var bw_x = bw_pos.x if bw_pos is Dictionary else bw_pos.x
	var bw_y = bw_pos.y if bw_pos is Dictionary else bw_pos.y
	if int(bw_x) == 200 and int(bw_y) == 500:
		print("[PASS] Battlewagon translated to (200, 500) before MW resolve")
		passed += 1
	else:
		print("[FAIL] Battlewagon at (%d, %d), expected (200, 500)" % [int(bw_x), int(bw_y)])
		failed += 1
	# Flag should be cleared after consumption.
	if not flags_after_arm.get("effect_careen_pending_move", false):
		print("[PASS] flag effect_careen_pending_move cleared after move")
		passed += 1
	else:
		print("[FAIL] flag not cleared")
		failed += 1
	# Target should now be within range and receive MW.
	if result2.per_target.size() >= 1 and result2.total_mortal_wounds > 0:
		print("[PASS] target unit took %d MW after careen move (%d target(s) in range)" % [result2.total_mortal_wounds, result2.per_target.size()])
		passed += 1
	else:
		print("[FAIL] expected target hit; got total_mortal_wounds=%d, per_target=%s" % [result2.total_mortal_wounds, str(result2.per_target)])
		failed += 1

	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		quit(1)
	else:
		quit(0)


func _find_seed_that_rolls_6() -> int:
	for s in range(500):
		var r = _re.RNGService.new(s)
		if r.roll_d6(1)[0] == 6:
			return s
	return -1


func _make_board() -> Dictionary:
	# Battlewagon at (200, 200) — single model unit (vehicle).
	var bw = {
		"id": "U_BATTLEWAGON_TEST",
		"owner": 2,
		"status": 2,
		"meta": {
			"name": "Battlewagon",
			"keywords": ["VEHICLE", "ORKS"],
			"stats": {"move": 9, "toughness": 11, "save": 3, "wounds": 16, "objective_control": 3},
			"weapons": [],
			"abilities": [{"name": "Deadly Demise D6", "type": "Special", "description": "Roll one D6 ..."}]
		},
		"models": [{"id": "bw1", "wounds": 16, "current_wounds": 0, "alive": false, "position": {"x": 200, "y": 200}, "base_mm": 100}],
		"flags": {}
	}
	# Target unit at (200, 600) — 400 px = 10" from original Battlewagon position.
	var target = {
		"id": "U_TARGET_PLAYER1",
		"owner": 1,
		"status": 2,
		"meta": {
			"name": "Target Squad",
			"keywords": ["INFANTRY"],
			"stats": {"move": 6, "toughness": 4, "save": 4, "wounds": 1, "objective_control": 1},
			"weapons": [],
			"abilities": []
		},
		"models": [{"id": "t1", "wounds": 1, "current_wounds": 1, "alive": true, "position": {"x": 200, "y": 600}, "base_mm": 32}],
		"flags": {}
	}
	return {
		"units": {"U_BATTLEWAGON_TEST": bw, "U_TARGET_PLAYER1": target},
		"meta": {"battle_round": 1, "active_player": 1}
	}
