extends SceneTree

# DEFENDER CONTROL vs an AI ATTACKER (2026-07): the AI's atomic SHOOT must
# pause for a HUMAN defender — first for the reactive-stratagem window
# (smokescreen_11e vs a SMOKE target), then for interactive save batches —
# and resume/finish through USE/DECLINE_REACTIVE_STRATAGEM + APPLY_SAVES.
#
#   A) SHOOT vs human defender with an eligible reactive stratagem pauses
#      with awaiting_reactive_stratagem (no dice rolled yet)
#   B) DECLINE_REACTIVE_STRATAGEM resumes the AI resolution
#   C) the interactive-save queue (_begin_ai_interactive_saves →
#      _process_apply_saves_ai_atomic) hands batches to the defender one at
#      a time and finishes the activation (has_shot) after the last one
#   D) AIPlayer._human_defender_window_pending reports the human defender
#      while the windows are open
#
# Usage: godot --headless --path . -s tests/test_ai_attacker_defender_pause.gd

var passed := 0
var failed := 0
var captured_saves: Array = []

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	create_timer(0.1).timeout.connect(_run_tests)

func _unit(id: String, owner: int, count: int, keywords: Array, weapons: Array, x0: float) -> Dictionary:
	var models = []
	for i in range(count):
		models.append({"id": "m%d" % (i + 1), "alive": true, "wounds": 1,
			"current_wounds": 1, "base_mm": 32, "base_type": "circular",
			"weapons": weapons.duplicate(),
			"position": {"x": x0 + float(i % 5) * 45.0, "y": 400.0 + float(i / 5) * 45.0}})
	return {"id": id, "owner": owner, "flags": {},
		"meta": {"name": id, "keywords": keywords,
			"stats": {"toughness": 4, "save": 5, "wounds": 1, "move": 6}},
		"models": models}

func _setup_state(game_state) -> void:
	game_state.state["units"] = {
		"U_AI_SHOOTER": _unit("U_AI_SHOOTER", 1, 5, ["INFANTRY"], [{"id": "shoota", "weapon_id": "shoota"}], 300.0),
		"U_BOYZ": _unit("U_BOYZ", 2, 10, ["INFANTRY", "SMOKE"], [], 300.0),
	}
	# ~10" apart — inside shoota range (18")
	for m in game_state.state.units["U_BOYZ"].models:
		m.position.y += 400.0
	game_state.state["players"] = {"1": {"cp": 3}, "2": {"cp": 3}}
	game_state.state["meta"]["phase"] = 8
	game_state.state["meta"]["active_player"] = 1

func _sd(wounds: int) -> Dictionary:
	return {
		"target_unit_id": "U_BOYZ", "target_unit_name": "Boyz",
		"shooter_unit_id": "U_AI_SHOOTER", "weapon_name": "Test Shoota",
		"wounds_to_save": wounds, "total_wounds": wounds,
		"ap": -10, "damage": 1, "damage_raw": "1", "base_save": 5,
		"is_psychic": false, "has_devastating_wounds": false, "devastating_wounds": 0,
		"melta_bonus": 0,
	}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_ai_attacker_defender_pause ===\n")
	var rules = root.get_node_or_null("RulesEngine")
	var game_state = root.get_node_or_null("GameState")
	var ai = root.get_node_or_null("AIPlayer")
	var sm = root.get_node_or_null("StratagemManager")
	_check("autoloads present", rules != null and game_state != null and ai != null and sm != null)
	GameConstants.edition = 11
	_setup_state(game_state)
	if sm.has_method("reset_for_new_battle"):
		sm.reset_for_new_battle()
	ai.configure({1: "AI", 2: "HUMAN"}, {1: 0, 2: 0})
	_check("AI owns player 1, human owns player 2",
		ai.is_ai_player(1) and not ai.is_ai_player(2))

	var phase = load("res://phases/ShootingPhase.gd").new()
	root.add_child(phase)
	phase.game_state_snapshot = game_state.create_snapshot()
	phase.saves_required.connect(func(list): captured_saves.append(list))

	print("-- A) AI SHOOT pauses for the human defender's reactive window --")
	var shoot_action = {
		"type": "SHOOT",
		"actor_unit_id": "U_AI_SHOOTER",
		"payload": {
			"assignments": [{"weapon_id": "shoota", "target_unit_id": "U_BOYZ",
				"model_ids": ["m1", "m2", "m3", "m4", "m5"]}],
			"rng_seed": 1234
		}
	}
	var result = phase._process_shoot(shoot_action)
	_check("SHOOT returned success", result.get("success", false), str(result.get("error", "")))
	_check("paused with reactive_stratagem_opportunity",
		result.get("reactive_stratagem_opportunity", false), str(result.keys()))
	_check("phase awaiting_reactive_stratagem", phase.awaiting_reactive_stratagem)
	_check("defending player is the human (2)", int(result.get("defending_player", 0)) == 2)
	_check("smokescreen offered", str(result.get("available_stratagems", [])).contains("SMOKESCREEN"),
		str(result.get("available_stratagems", [])))
	_check("unit has NOT shot yet",
		not game_state.state.units["U_AI_SHOOTER"].flags.get("has_shot", false))

	print("\n-- D1) AIPlayer idles on the human reactive window --")
	# Point the AI's phase lookup at our live instance.
	var pm = root.get_node_or_null("PhaseManager")
	var saved_instance = null
	if pm != null:
		saved_instance = pm.current_phase_instance
		pm.current_phase_instance = phase
	_check("_human_defender_window_pending -> human player 2",
		ai._human_defender_window_pending() == 2)

	print("\n-- B) DECLINE resumes the AI resolution --")
	var decline_result = phase._process_decline_reactive_stratagem({"type": "DECLINE_REACTIVE_STRATAGEM"})
	_check("decline result success", decline_result.get("success", false), str(decline_result.get("error", "")))
	_check("reactive window closed", not phase.awaiting_reactive_stratagem)
	var paused_for_saves = not phase.pending_save_data.is_empty()
	var has_shot_flag := false
	for change in decline_result.get("changes", []):
		if str(change.get("path", "")).ends_with("flags.has_shot") and change.get("value") == true:
			has_shot_flag = true
	_check("resumed: either awaiting defender saves or activation finished",
		paused_for_saves or has_shot_flag,
		"pending=%d has_shot=%s" % [phase.pending_save_data.size(), str(has_shot_flag)])
	if paused_for_saves:
		_check("saves_required emitted for the defender", captured_saves.size() >= 1)
		_check("ai_atomic save mode active", phase.resolution_state.get("mode", "") == "ai_atomic")
		_check("D2) AIPlayer idles on the human save window",
			ai._human_defender_window_pending() == 2)
		# Defender resolves every pending batch through the real engine path.
		var guard := 0
		while not phase.pending_save_data.is_empty() and guard < 10:
			guard += 1
			var sd = phase.pending_save_data[0]
			var summary = rules.resolve_allocation_batch_11e(sd, [], game_state.state, rules.RNGService.new(guard))
			var apply_result = phase._process_apply_saves({
				"type": "APPLY_SAVES",
				"payload": {"save_results_list": [summary]}
			})
			_check("APPLY_SAVES batch %d success" % guard, apply_result.get("success", false),
				str(apply_result.get("error", "")))
			if phase.pending_save_data.is_empty():
				for change in apply_result.get("changes", []):
					if str(change.get("path", "")).ends_with("flags.has_shot") and change.get("value") == true:
						has_shot_flag = true
		_check("all save batches consumed", phase.pending_save_data.is_empty())
		_check("activation finished with has_shot", has_shot_flag)
	_check("active shooter cleared after completion", phase.active_shooter_id == "")
	_check("no defender window pending after completion", ai._human_defender_window_pending() == 0)

	print("\n-- C) surgical: the save queue hands batches one at a time --")
	captured_saves.clear()
	var phase2 = load("res://phases/ShootingPhase.gd").new()
	root.add_child(phase2)
	_setup_state(game_state)
	phase2.game_state_snapshot = game_state.create_snapshot()
	phase2.saves_required.connect(func(list): captured_saves.append(list))
	phase2.active_shooter_id = "U_AI_SHOOTER"
	phase2.confirmed_assignments = [{"weapon_id": "shoota", "target_unit_id": "U_BOYZ", "model_ids": ["m1"]}]
	var fake_result = {"save_data_list": [_sd(2), _sd(3)], "hazardous_weapons": [], "one_shot_diffs": []}
	var pause1 = phase2._begin_ai_interactive_saves("U_AI_SHOOTER", -1, fake_result, [])
	_check("queue holds both batches", phase2.pending_save_data.size() == 2)
	_check("only the FIRST batch emitted to the defender",
		captured_saves.size() == 1 and captured_saves[0].size() == 1
		and int(captured_saves[0][0].get("wounds_to_save", 0)) == 2, str(captured_saves))
	_check("pause result carries only the first batch",
		pause1.get("save_data_list", []).size() == 1)
	var s1 = rules.resolve_allocation_batch_11e(phase2.pending_save_data[0], [], game_state.state, rules.RNGService.new(3))
	var r1 = phase2._process_apply_saves({"type": "APPLY_SAVES", "payload": {"save_results_list": [s1]}})
	_check("first APPLY_SAVES succeeds and stays paused",
		r1.get("success", false) and phase2.pending_save_data.size() == 1)
	# The next batch emission is deferred one frame (overlay teardown safety).
	await process_frame
	await process_frame
	_check("second batch emitted after a frame",
		captured_saves.size() == 2 and int(captured_saves[1][0].get("wounds_to_save", 0)) == 3,
		str(captured_saves.size()))
	var s2 = rules.resolve_allocation_batch_11e(phase2.pending_save_data[0], [], game_state.state, rules.RNGService.new(4))
	var r2 = phase2._process_apply_saves({"type": "APPLY_SAVES", "payload": {"save_results_list": [s2]}})
	var has_shot2 := false
	for change in r2.get("changes", []):
		if str(change.get("path", "")).ends_with("flags.has_shot") and change.get("value") == true:
			has_shot2 = true
	_check("final APPLY_SAVES finishes the activation (has_shot diff)", has_shot2)
	_check("queue empty + shooter cleared", phase2.pending_save_data.is_empty() and phase2.active_shooter_id == "")

	if pm != null:
		pm.current_phase_instance = saved_instance
	GameConstants.edition = 10
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
