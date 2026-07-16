extends SceneTree

# DEFENDER CONTROL — melee (2026-07): FightPhase._process_apply_melee_saves
# accepts the 11e AllocationGroupOverlay summary (is_allocation_11e diffs),
# deducts a defender save Command Re-roll, and finishes the activation.
#
# Usage: godot --headless --path . -s tests/test_melee_defender_allocation_11e.gd

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

func _unit(id: String, owner: int, count: int, x0: float) -> Dictionary:
	var models = []
	for i in range(count):
		models.append({"id": "m%d" % (i + 1), "alive": true, "wounds": 1,
			"current_wounds": 1, "base_mm": 32, "base_type": "circular",
			"position": {"x": x0 + float(i) * 45.0, "y": 400.0}})
	return {"id": id, "owner": owner, "flags": {},
		"meta": {"name": id, "keywords": ["INFANTRY"],
			"stats": {"toughness": 4, "save": 5, "wounds": 1, "move": 6}},
		"models": models}

func _sd(wounds: int) -> Dictionary:
	return {
		"target_unit_id": "U_BOYZ", "target_unit_name": "Boyz",
		"shooter_unit_id": "U_KOMMANDOS", "weapon_name": "Choppa",
		"wounds_to_save": wounds, "total_wounds": wounds,
		"ap": -10, "damage": 1, "damage_raw": "1", "base_save": 5,
		"is_psychic": false, "has_devastating_wounds": false, "devastating_wounds": 0,
		"melta_bonus": 0,
	}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_melee_defender_allocation_11e ===\n")
	var rules = root.get_node_or_null("RulesEngine")
	var game_state = root.get_node_or_null("GameState")
	var sm = root.get_node_or_null("StratagemManager")
	_check("autoloads present", rules != null and game_state != null and sm != null)
	GameConstants.edition = 11
	game_state.state["units"] = {
		"U_KOMMANDOS": _unit("U_KOMMANDOS", 1, 5, 300.0),
		"U_BOYZ": _unit("U_BOYZ", 2, 10, 900.0),
	}
	game_state.state["players"] = {"1": {"cp": 3}, "2": {"cp": 3}}
	game_state.state["meta"]["phase"] = 10
	game_state.state["meta"]["active_player"] = 1
	if sm.has_method("reset_for_new_battle"):
		sm.reset_for_new_battle()

	var phase = load("res://phases/FightPhase.gd").new()
	root.add_child(phase)
	phase.game_state_snapshot = game_state.create_snapshot()
	phase.active_fighter_id = "U_KOMMANDOS"
	phase.confirmed_attacks = [{"target": "U_BOYZ", "weapon_id": "choppa", "model_ids": ["m1"]}]
	phase.awaiting_melee_saves = true
	phase.pending_melee_save_data = [_sd(2)]
	phase.pending_melee_hit_wound_result = {}

	# Defender-resolved batch: 2 wounds at AP-10 vs Sv5+ — both fail, the
	# defender picked models 7 and 8 as casualties + used a save re-roll.
	var summary = rules.resolve_allocation_batch_11e(_sd(2), [], game_state.state,
		rules.RNGService.new(11), {"forced_save_rolls": [3, 4], "preferred_targets": [7, 8]})
	_check("batch: both saves failed", int(summary.saves_failed) == 2, str(summary))
	_check("batch: chosen models 7,8 destroyed", str(summary.models_destroyed) == str([7, 8]), str(summary.models_destroyed))
	summary["command_reroll"] = {"used": true, "player": 2, "die_index": 0, "original": 2, "new": 3}

	var result = phase._process_apply_melee_saves({
		"type": "APPLY_MELEE_SAVES",
		"payload": {"save_results_list": [summary]}
	})
	_check("APPLY_MELEE_SAVES success", result.get("success", false), str(result.get("error", "")))
	_check("awaiting_melee_saves cleared", not phase.awaiting_melee_saves)
	var alive := 0
	for m in game_state.state.units["U_BOYZ"].models:
		if m.get("alive", true):
			alive += 1
	_check("defender-chosen casualties applied (8 alive)", alive == 8, "alive=%d" % alive)
	_check("model 7 dead / model 0 alive (defender's pick honored)",
		not game_state.state.units["U_BOYZ"].models[7].get("alive", true)
		and game_state.state.units["U_BOYZ"].models[0].get("alive", true))
	var cp_after = int(game_state.state.players["2"].cp)
	_check("save Command Re-roll deducted (CP 3 -> 2)", cp_after == 2, "cp=%d" % cp_after)
	var has_fought := false
	for change in result.get("changes", []):
		if str(change.get("path", "")).ends_with("flags.has_fought") and change.get("value") == true:
			has_fought = true
	_check("activation finished (has_fought diff)", has_fought)

	GameConstants.edition = 10
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
