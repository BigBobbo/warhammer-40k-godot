extends SceneTree

# Test: P2-92 — Verify AI player state is preserved across save/load
# Usage: godot --headless --path . -s tests/test_save_load_ai.gd

func _init():
	print("=== P2-92: Test Save/Load AI Players ===")
	var passed = 0
	var failed = 0

	# Test 1: Verify save files contain AI player type info
	print("\n--- Test 1: Save file contains AI player config ---")
	var save_path = "res://saves/move.w40ksave"
	var file = FileAccess.open(save_path, FileAccess.READ)
	if file:
		var json = JSON.new()
		var err = json.parse(file.get_as_text())
		file.close()
		if err == OK:
			var data = json.data
			var config = data.get("meta", {}).get("game_config", {})
			var p1_type = config.get("player1_type", "")
			var p2_type = config.get("player2_type", "")
			var p1_diff = config.get("player1_difficulty", -1)
			var p2_diff = config.get("player2_difficulty", -1)

			if p1_type != "" and p2_type != "":
				print("  PASS: player1_type=%s, player2_type=%s" % [p1_type, p2_type])
				passed += 1
			else:
				print("  FAIL: Missing player type in game_config")
				failed += 1

			if p1_diff >= 0 and p2_diff >= 0:
				print("  PASS: player1_difficulty=%d, player2_difficulty=%d" % [p1_diff, p2_diff])
				passed += 1
			else:
				print("  FAIL: Missing difficulty in game_config")
				failed += 1
		else:
			print("  SKIP: Could not parse save file JSON")
	else:
		print("  SKIP: Save file not found at %s" % save_path)

	# Test 2: Verify AIDecisionMaker.reset_caches() works
	print("\n--- Test 2: AIDecisionMaker.reset_caches() ---")
	var AIDecisionMaker = load("res://scripts/AIDecisionMaker.gd")
	# Set some cache values
	AIDecisionMaker._focus_fire_plan = {"test": true}
	AIDecisionMaker._focus_fire_plan_built = true
	AIDecisionMaker._phase_plan = {"test": true}
	AIDecisionMaker._phase_plan_built = true
	AIDecisionMaker._phase_plan_round = 5
	AIDecisionMaker._fight_order_plan = ["a", "b"]
	AIDecisionMaker._fight_order_plan_built = true
	AIDecisionMaker._bodyguards_with_leaders = ["unit1"]
	AIDecisionMaker._charge_coordination = {"target1": {}}
	AIDecisionMaker._charge_coordination_round = 3

	# Call reset
	AIDecisionMaker.reset_caches()

	# Verify all caches are cleared
	var all_clear = true
	if AIDecisionMaker._focus_fire_plan.size() != 0:
		print("  FAIL: _focus_fire_plan not cleared")
		all_clear = false
	if AIDecisionMaker._focus_fire_plan_built != false:
		print("  FAIL: _focus_fire_plan_built not reset")
		all_clear = false
	if AIDecisionMaker._phase_plan.size() != 0:
		print("  FAIL: _phase_plan not cleared")
		all_clear = false
	if AIDecisionMaker._phase_plan_built != false:
		print("  FAIL: _phase_plan_built not reset")
		all_clear = false
	if AIDecisionMaker._phase_plan_round != -1:
		print("  FAIL: _phase_plan_round not reset")
		all_clear = false
	if AIDecisionMaker._fight_order_plan.size() != 0:
		print("  FAIL: _fight_order_plan not cleared")
		all_clear = false
	if AIDecisionMaker._fight_order_plan_built != false:
		print("  FAIL: _fight_order_plan_built not reset")
		all_clear = false
	if AIDecisionMaker._bodyguards_with_leaders.size() != 0:
		print("  FAIL: _bodyguards_with_leaders not cleared")
		all_clear = false
	if AIDecisionMaker._charge_coordination.size() != 0:
		print("  FAIL: _charge_coordination not cleared")
		all_clear = false
	if AIDecisionMaker._charge_coordination_round != -1:
		print("  FAIL: _charge_coordination_round not reset")
		all_clear = false

	if all_clear:
		print("  PASS: All AIDecisionMaker caches cleared correctly")
		passed += 1
	else:
		failed += 1

	# Test 3: Verify SaveLoadManager metadata includes AI player types
	print("\n--- Test 3: SaveLoadManager metadata includes AI player types ---")
	# Check _create_save_metadata includes player types
	var slm_script = load("res://autoloads/SaveLoadManager.gd")
	var source = FileAccess.open("res://autoloads/SaveLoadManager.gd", FileAccess.READ)
	if source:
		var source_text = source.get_as_text()
		source.close()
		if "player1_type" in source_text and "player2_type" in source_text:
			print("  PASS: SaveLoadManager includes player type fields in metadata")
			passed += 1
		else:
			print("  FAIL: SaveLoadManager missing player type fields in metadata")
			failed += 1
	else:
		print("  SKIP: Could not read SaveLoadManager.gd source")

	# Test 4: Verify Main.gd re-initializes AI on load via _reinitialize_ai_after_load
	print("\n--- Test 4: Main.gd re-initializes AI on load ---")
	var main_source = FileAccess.open("res://scripts/Main.gd", FileAccess.READ)
	if main_source:
		var main_text = main_source.get_as_text()
		main_source.close()

		# SAVE-1: Check that _apply_loaded_state calls _reinitialize_ai_after_load
		var apply_idx = main_text.find("func _apply_loaded_state")
		var apply_end = main_text.find("\nfunc ", apply_idx + 1)
		if apply_end == -1:
			apply_end = main_text.length()
		var apply_body = main_text.substr(apply_idx, apply_end - apply_idx)
		if "_reinitialize_ai_after_load" in apply_body:
			print("  PASS: _apply_loaded_state() calls _reinitialize_ai_after_load()")
			passed += 1
		else:
			print("  FAIL: _apply_loaded_state() does NOT call _reinitialize_ai_after_load()")
			failed += 1

		# SAVE-1: Check that _refresh_after_load calls _reinitialize_ai_after_load
		var refresh_idx = main_text.find("func _refresh_after_load")
		var refresh_end = main_text.find("\nfunc ", refresh_idx + 1)
		if refresh_end == -1:
			refresh_end = main_text.length()
		var refresh_body = main_text.substr(refresh_idx, refresh_end - refresh_idx)
		if "_reinitialize_ai_after_load" in refresh_body:
			print("  PASS: _refresh_after_load() calls _reinitialize_ai_after_load()")
			passed += 1
		else:
			print("  FAIL: _refresh_after_load() does NOT call _reinitialize_ai_after_load()")
			failed += 1

		# SAVE-1: Check that _on_load_requested cancels AI before load
		var load_req_idx = main_text.find("func _on_load_requested")
		var load_req_end = main_text.find("\nfunc ", load_req_idx + 1)
		if load_req_end == -1:
			load_req_end = main_text.length()
		var load_req_body = main_text.substr(load_req_idx, load_req_end - load_req_idx)
		if "cancel_ai_before_load" in load_req_body:
			print("  PASS: _on_load_requested() calls cancel_ai_before_load()")
			passed += 1
		else:
			print("  FAIL: _on_load_requested() does NOT call cancel_ai_before_load()")
			failed += 1

		# SAVE-1: Verify reconfigure_ai_after_load exists in AIPlayer
		var ai_source2 = FileAccess.open("res://autoloads/AIPlayer.gd", FileAccess.READ)
		if ai_source2:
			var ai_text2 = ai_source2.get_as_text()
			ai_source2.close()
			if "func reconfigure_ai_after_load" in ai_text2:
				print("  PASS: AIPlayer has reconfigure_ai_after_load()")
				passed += 1
			else:
				print("  FAIL: AIPlayer missing reconfigure_ai_after_load()")
				failed += 1
			if "func cancel_ai_before_load" in ai_text2:
				print("  PASS: AIPlayer has cancel_ai_before_load()")
				passed += 1
			else:
				print("  FAIL: AIPlayer missing cancel_ai_before_load()")
				failed += 1
		else:
			print("  SKIP: Could not read AIPlayer.gd for SAVE-1 checks")
	else:
		print("  SKIP: Could not read Main.gd source")

	# Test 5: Verify AIPlayer.configure() resets caches
	print("\n--- Test 5: AIPlayer.configure() resets transient state ---")
	var ai_source = FileAccess.open("res://autoloads/AIPlayer.gd", FileAccess.READ)
	if ai_source:
		var ai_text = ai_source.get_as_text()
		ai_source.close()
		var configure_idx = ai_text.find("func configure(")
		var configure_end = ai_text.find("\nfunc ", configure_idx + 1)
		if configure_end == -1:
			configure_end = ai_text.length()
		var configure_body = ai_text.substr(configure_idx, configure_end - configure_idx)

		if "reset_caches" in configure_body:
			print("  PASS: configure() calls AIDecisionMaker.reset_caches()")
			passed += 1
		else:
			print("  FAIL: configure() does NOT call AIDecisionMaker.reset_caches()")
			failed += 1

		if "_failed_deploy_unit_ids.clear()" in configure_body:
			print("  PASS: configure() clears _failed_deploy_unit_ids")
			passed += 1
		else:
			print("  FAIL: configure() does NOT clear _failed_deploy_unit_ids")
			failed += 1
	else:
		print("  SKIP: Could not read AIPlayer.gd source")

	# Summary
	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		print("SOME TESTS FAILED")
	else:
		print("ALL TESTS PASSED")

	quit()
