extends SceneTree

# Issue #376: validate Da Jump placement guards (board-bounds, edge-to-edge,
# strict-9 inch). Run: godot --headless --script tests/test_da_jump_placement_376.gd

func _initialize():
	print("=== Issue #376: Da Jump placement validation ===")
	var fails = 0
	fails += _test_strict_9()
	fails += _test_off_board()
	fails += _test_safe_placement_passes()
	fails += _test_edge_to_edge()
	if fails == 0:
		print("\n[OK] all #376 validations passed")
		quit(0)
	else:
		print("\n[FAIL] %d validation(s) failed" % fails)
		quit(1)

func _build_state(weirdboy_owner: int = 2, enemy_pos: Dictionary = {"x": 1600, "y": 100}) -> Dictionary:
	# Synthetic snapshot with one Weirdboy + one enemy infantry model. Enemy
	# placed at (1600, 100), so 9.0" away horizontally is y = 460 (9*40 = 360px).
	var weirdboy_model_id = "wb1"
	return {
		"meta": {"active_player": weirdboy_owner, "battle_round": 2, "turn_number": 2},
		"board": {"size": {"width": 44, "height": 60}},
		"units": {
			"U_WEIRDBOY_J": {
				"owner": weirdboy_owner,
				"meta": {"name": "Weirdboy"},
				"models": [{"id": weirdboy_model_id, "alive": true, "base_mm": 32, "position": null}],
				"flags": {"awaiting_da_jump_placement": true}
			},
			"U_ENEMY": {
				"owner": (1 if weirdboy_owner == 2 else 2),
				"meta": {"name": "Enemy Boyz"},
				"models": [{"id": "e1", "alive": true, "base_mm": 32, "position": enemy_pos}]
			}
		}
	}

func _make_phase(state: Dictionary) -> Object:
	var script: GDScript = load("res://phases/MovementPhase.gd")
	var phase = Node.new()
	phase.set_script(script)
	phase.game_state_snapshot = state
	phase.phase_type = 4  # MOVEMENT enum value (placeholder; not consulted by _process_place_da_jump)
	return phase

func _test_strict_9() -> int:
	print("\n-- strict >9 (exactly 9.0\" rejected) --")
	var fails = 0
	# Enemy at (1600, 100). 9.0" horizontally at same y would be (1600-360, 100)=(1240,100).
	# But Da Jump uses center-distance pre-fix, edge-to-edge post-fix. With both bases
	# 32mm, 9.0" edge-to-edge means center distance > 9.0 + 2*0.63" = 10.26". Use a
	# placement at center distance exactly 9.0" from enemy and confirm it's rejected.
	var state = _build_state()
	var phase = _make_phase(state)
	# Center-distance 9.0" => 360 px. Enemy at (1600, 100), candidate at (1600, 460).
	var action = {
		"actor_unit_id": "U_WEIRDBOY_J",
		"player": 2,
		"payload": {"model_positions": [{"model_id": "wb1", "x": 1600, "y": 460}]}
	}
	var result = phase.call("_process_place_da_jump", action)
	# Edge-to-edge at 9.0 - 0.63 - 0.63 = 7.74" — must be rejected (<=9 fails)
	if result.get("success", false):
		print("[FAIL] center-9.0\" placement was accepted (edge-to-edge <9): %s" % str(result))
		fails += 1
	else:
		print("[OK]   exactly 9.0\" center distance rejected: %s" % str(result.get("message", "")))
	phase.queue_free()
	return fails

func _test_off_board() -> int:
	print("\n-- off-board placement rejected --")
	var fails = 0
	var state = _build_state()
	var phase = _make_phase(state)
	# (-500, -500) is clearly off-board (board is 0..44" * 0..60")
	var action = {
		"actor_unit_id": "U_WEIRDBOY_J",
		"player": 2,
		"payload": {"model_positions": [{"model_id": "wb1", "x": -500, "y": -500}]}
	}
	var result = phase.call("_process_place_da_jump", action)
	if result.get("success", false):
		print("[FAIL] off-board placement was accepted: %s" % str(result))
		fails += 1
	else:
		print("[OK]   off-board (-500,-500) rejected: %s" % str(result.get("message", "")))
	phase.queue_free()
	return fails

func _test_safe_placement_passes() -> int:
	print("\n-- safe placement (well outside 9\") accepted --")
	var fails = 0
	# Enemy at (1600, 100). Place at (200, 200) — far from enemy AND on-board.
	# Board is 44x60 inches = 1760x2400 px (40 px/in). (200, 200) is at (5", 5") — on board.
	var state = _build_state()
	var phase = _make_phase(state)
	var action = {
		"actor_unit_id": "U_WEIRDBOY_J",
		"player": 2,
		"payload": {"model_positions": [{"model_id": "wb1", "x": 200, "y": 200}]}
	}
	var result = phase.call("_process_place_da_jump", action)
	if not result.get("success", false):
		print("[FAIL] safe placement (200, 200) was rejected: %s" % str(result))
		fails += 1
	else:
		print("[OK]   safe placement at (200, 200) accepted")
	phase.queue_free()
	return fails

func _test_edge_to_edge() -> int:
	print("\n-- edge-to-edge >9\" boundary (just inside vs just outside) --")
	var fails = 0
	# 32mm base radius = 16mm = 0.63 inches. Edge-to-edge >9" means center distance
	# > 9.0 + 0.63 + 0.63 = 10.26 inches = 410.4 px.
	# Test 1: center distance 411 px — edge-to-edge ~9.025" -> SHOULD PASS
	# Test 2: center distance 408 px — edge-to-edge ~8.95" -> SHOULD REJECT
	var state1 = _build_state()
	var phase1 = _make_phase(state1)
	var act1 = {
		"actor_unit_id": "U_WEIRDBOY_J",
		"player": 2,
		"payload": {"model_positions": [{"model_id": "wb1", "x": 1600, "y": 511}]}  # 411 px from (1600,100)
	}
	var r1 = phase1.call("_process_place_da_jump", act1)
	if not r1.get("success", false):
		print("[FAIL] edge-9.025\" placement was rejected: %s" % str(r1))
		fails += 1
	else:
		print("[OK]   edge-to-edge 9.025\" accepted")
	phase1.queue_free()

	var state2 = _build_state()
	var phase2 = _make_phase(state2)
	var act2 = {
		"actor_unit_id": "U_WEIRDBOY_J",
		"player": 2,
		"payload": {"model_positions": [{"model_id": "wb1", "x": 1600, "y": 508}]}  # 408 px
	}
	var r2 = phase2.call("_process_place_da_jump", act2)
	if r2.get("success", false):
		print("[FAIL] edge-8.95\" placement was accepted: %s" % str(r2))
		fails += 1
	else:
		print("[OK]   edge-to-edge 8.95\" rejected: %s" % str(r2.get("message", "")))
	phase2.queue_free()

	return fails
