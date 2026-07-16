extends SceneTree

# DEFENDER CONTROL (2026-07): the defending player rolls their own saves,
# may Command Re-roll one save die, and picks which bases are removed.
# Engine-level coverage:
#   A) resolve_allocation_batch_11e honors forced_save_rolls (exact replay)
#   B) preferred_targets kills the DEFENDER'S chosen models, not lowest-index
#   C) casualty count is invariant to the choice (same rolls, same damage)
#   D) wounded model stays first in line even against a preference
#   E) StratagemManager.execute_command_reroll deducts 1 CP (save re-roll spend)
#   F) wiring pins: phases/controllers/network carry the new defender paths
#
# Usage: godot --headless --path . -s tests/test_defender_control.gd

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	create_timer(0.1).timeout.connect(_run_tests)

func _boyz_board(wounded_index: int = -1) -> Dictionary:
	var models = []
	for i in range(10):
		var w := 1
		var cur := 1
		if i == wounded_index:
			w = 2
			cur = 1
		models.append({"id": "m%d" % (i + 1), "alive": true, "wounds": w,
			"current_wounds": cur, "base_mm": 32, "base_type": "circular",
			"position": {"x": 300.0 + float(i) * 40.0, "y": 400.0}})
	return {
		"units": {
			"U_BOYZ": {"id": "U_BOYZ", "owner": 2, "flags": {},
				"meta": {"name": "Boyz", "keywords": ["INFANTRY"],
					"stats": {"toughness": 5, "save": 5, "wounds": 1}},
				"models": models},
		},
		"meta": {},
		"players": {"1": {"cp": 3}, "2": {"cp": 3}},
	}

func _save_data(wounds: int) -> Dictionary:
	return {
		"target_unit_id": "U_BOYZ", "target_unit_name": "Boyz",
		"shooter_unit_id": "U_SHOOTER", "weapon_name": "Test Cannon",
		"wounds_to_save": wounds, "total_wounds": wounds,
		"ap": -10, "damage": 1, "damage_raw": "1", "base_save": 5,
		"is_psychic": false, "has_devastating_wounds": false, "devastating_wounds": 0,
		"melta_bonus": 0,
	}

func _alive_indices(board: Dictionary) -> Array:
	var out: Array = []
	var models: Array = board.units["U_BOYZ"].models
	for i in range(models.size()):
		if models[i].get("alive", true):
			out.append(i)
	return out

func _apply_diffs(board: Dictionary, diffs: Array) -> void:
	for diff in diffs:
		var parts = str(diff.path).split(".")
		if parts.size() == 5 and parts[0] == "units":
			board.units[parts[1]].models[int(parts[3])][parts[4]] = diff.value

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_defender_control ===\n")
	var rules = root.get_node_or_null("RulesEngine")
	_check("RulesEngine autoload present", rules != null)
	GameConstants.edition = 11

	print("-- A) forced_save_rolls: exact dice replay --")
	var board = _boyz_board()
	var forced = [1, 1, 1]  # AP-10 vs Sv5+: every die fails no matter its value
	var batch = rules.resolve_allocation_batch_11e(_save_data(3), [], board,
		rules.RNGService.new(7), {"forced_save_rolls": forced})
	_check("save_rolls == forced rolls", str(batch.save_rolls) == str(forced), str(batch.save_rolls))
	_check("all 3 fail at AP-10", int(batch.saves_failed) == 3)
	_check("3 casualties", int(batch.casualties) == 3)
	_check("default victims are the lowest indices [0,1,2]",
		str(batch.models_destroyed) == str([0, 1, 2]), str(batch.models_destroyed))

	print("\n-- B) preferred_targets: the defender's chosen bases die --")
	var board_b = _boyz_board()
	var batch_b = rules.resolve_allocation_batch_11e(_save_data(3), [], board_b,
		rules.RNGService.new(7), {"forced_save_rolls": forced, "preferred_targets": [5, 6, 7]})
	_check("chosen victims [5,6,7] died", str(batch_b.models_destroyed) == str([5, 6, 7]), str(batch_b.models_destroyed))
	_apply_diffs(board_b, batch_b.diffs)
	var alive_b = _alive_indices(board_b)
	_check("models 0-2 (engine defaults) survived", 0 in alive_b and 1 in alive_b and 2 in alive_b, str(alive_b))

	print("\n-- C) casualty count invariant to the pick --")
	_check("same casualties with and without preference",
		int(batch.casualties) == int(batch_b.casualties),
		"%d vs %d" % [batch.casualties, batch_b.casualties])
	_check("same save fails with and without preference",
		int(batch.saves_failed) == int(batch_b.saves_failed))

	print("\n-- D) 05.04: a pre-wounded model cannot be spared by the pick --")
	var board_d = _boyz_board(4)  # model index 4 is wounded (W2, 1 remaining)
	var batch_d = rules.resolve_allocation_batch_11e(_save_data(3), [], board_d,
		rules.RNGService.new(7), {"forced_save_rolls": forced, "preferred_targets": [8, 9]})
	_check("wounded model 4 is the first casualty even against the preference",
		4 in batch_d.models_destroyed, str(batch_d.models_destroyed))
	_check("remaining picks honor the preference [8,9]",
		8 in batch_d.models_destroyed and 9 in batch_d.models_destroyed, str(batch_d.models_destroyed))

	print("\n-- E) save Command Re-roll spends 1 CP via StratagemManager --")
	var game_state = root.get_node_or_null("GameState")
	var stratagem_mgr = root.get_node_or_null("StratagemManager")
	_check("GameState + StratagemManager present", game_state != null and stratagem_mgr != null)
	if game_state != null and stratagem_mgr != null:
		game_state.state["players"] = {"1": {"cp": 3}, "2": {"cp": 3}}
		game_state.state["units"] = _boyz_board().units
		if stratagem_mgr.has_method("reset_for_new_battle"):
			stratagem_mgr.reset_for_new_battle()
		var avail = stratagem_mgr.is_command_reroll_available(2)
		_check("command re-roll available for defender with 3 CP", avail.get("available", false), str(avail))
		var cr = stratagem_mgr.execute_command_reroll(2, "U_BOYZ", {
			"roll_type": "save_roll", "original_rolls": [2], "unit_name": "Boyz"})
		_check("execute_command_reroll succeeded", cr.get("success", false), str(cr))
		var cp_after = int(game_state.state.players["2"].cp)
		_check("defender CP 3 -> 2", cp_after == 2, "cp=%d" % cp_after)

	print("\n-- F) wiring pins (regression net, not validation) --")
	var sp_src = FileAccess.get_file_as_string("res://phases/ShootingPhase.gd")
	_check("ShootingPhase: AI atomic pauses for human saves",
		"_should_pause_for_human_saves" in sp_src and "_begin_ai_interactive_saves" in sp_src)
	_check("ShootingPhase: APPLY_SAVES handles the AI atomic queue",
		"_process_apply_saves_ai_atomic" in sp_src)
	_check("ShootingPhase: reactive window pauses the AI atomic SHOOT",
		"ai_atomic" in sp_src and "_resolve_ai_shoot" in sp_src)
	_check("ShootingPhase: defender save command re-roll deduction wired",
		"_apply_defender_save_command_reroll" in sp_src)
	var fp_src = FileAccess.get_file_as_string("res://phases/FightPhase.gd")
	_check("FightPhase: 11e allocation summaries accepted in APPLY_MELEE_SAVES",
		"is_allocation_11e" in fp_src)
	_check("FightPhase: networked defender always interactive",
		"NetworkManager.is_networked():\n\t\t_auto_alloc_11e = false" in fp_src)
	var nm_src = FileAccess.get_file_as_string("res://autoloads/NetworkManager.gd")
	_check("NetworkManager: reactive stratagem actions network-exempt",
		"\"USE_REACTIVE_STRATAGEM\"" in nm_src and "\"DECLINE_REACTIVE_STRATAGEM\"" in nm_src)
	_check("NetworkManager: reactive opportunity re-emitted to defender client",
		"reactive_stratagem_opportunity" in nm_src)
	var sc_src = FileAccess.get_file_as_string("res://scripts/ShootingController.gd")
	_check("ShootingController: attacker WAITS instead of auto-declining",
		"waiting for remote defender" in sc_src)
	var ai_src = FileAccess.get_file_as_string("res://autoloads/AIPlayer.gd")
	_check("AIPlayer: idles on human defender windows",
		"_human_defender_window_pending" in ai_src)
	var sd_src = FileAccess.get_file_as_string("res://dialogs/StratagemDialog.gd")
	_check("StratagemDialog: 5s auto-decline countdown removed",
		"AUTO_DECLINE_SECONDS" not in sd_src)
	var ss_src = FileAccess.get_file_as_string("res://autoloads/SettingsService.gd")
	_check("SettingsService: auto_allocate_wounds defaults OFF",
		"var auto_allocate_wounds: bool = false" in ss_src)
	var fc_src = FileAccess.get_file_as_string("res://scripts/FightController.gd")
	_check("FightController: 11e melee saves use AllocationGroupOverlay",
		"AllocationGroupOverlay.new()" in fc_src)

	GameConstants.edition = 10
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
