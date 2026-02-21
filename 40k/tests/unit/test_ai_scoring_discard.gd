extends SceneTree

# Test AI Secondary Mission Discard Logic (T7-47)
# Verifies that the AI correctly evaluates mission achievability and
# discards unachievable secondary missions for +1 CP.
# Run with: godot --headless --script tests/unit/test_ai_scoring_discard.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== AI Secondary Mission Discard Tests (T7-47) ===\n")
	_run_tests()

	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	if _fail_count > 0:
		print("SOME TESTS FAILED")
	else:
		print("ALL TESTS PASSED")
	quit(1 if _fail_count > 0 else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

func _run_tests():
	test_no_discard_actions_ends_turn()
	test_count_alive_units()
	test_assassination_no_characters()
	test_assassination_with_characters()
	test_bring_it_down_no_targets()
	test_bring_it_down_with_targets()
	test_cull_the_horde_no_targets()
	test_behind_enemy_lines_no_units()
	test_behind_enemy_lines_with_units()
	test_engage_on_all_fronts_too_few_units()
	test_defend_stronghold_no_home_objectives()
	test_action_mission_no_units()
	test_marked_for_death_all_dead()
	test_while_active_no_enemies()
	test_while_active_with_enemies()

# =========================================================================
# Helpers
# =========================================================================

func _create_test_snapshot() -> Dictionary:
	return {
		"meta": {"battle_round": 2, "active_player": 2},
		"units": {},
		"board": {
			"objectives": [
				{"id": "obj_1", "zone": "player1"},
				{"id": "obj_2", "zone": "no_mans_land"},
				{"id": "obj_3", "zone": "player2"},
			],
		},
		"players": {
			"1": {"cp": 3, "vp": 0},
			"2": {"cp": 3, "vp": 0},
		},
	}

func _add_unit(snapshot: Dictionary, unit_id: String, owner: int, keywords: Array = [], models_count: int = 5, all_alive: bool = true, starting_strength: int = -1) -> void:
	var models = []
	for i in range(models_count):
		models.append({
			"id": "m%d" % (i + 1),
			"alive": all_alive or i < models_count / 2,
			"position": {"x": 100 + i * 30, "y": 200},
		})
	var ss = starting_strength if starting_strength >= 0 else models_count
	snapshot["units"][unit_id] = {
		"owner": owner,
		"meta": {"name": unit_id, "keywords": keywords, "starting_strength": ss},
		"models": models,
	}

# =========================================================================
# Tests: Basic flow
# =========================================================================

func test_no_discard_actions_ends_turn():
	var snapshot = _create_test_snapshot()
	var actions = [{"type": "END_SCORING"}]
	var result = AIDecisionMaker._decide_scoring(snapshot, actions, 2)
	_assert(result["type"] == "END_SCORING", "No discard actions -> END_SCORING (got: %s)" % result["type"])

# =========================================================================
# Tests: _count_alive_units_for_player
# =========================================================================

func test_count_alive_units():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "unit_a", 1, [], 3, true)
	_add_unit(snapshot, "unit_b", 1, [], 2, true)
	_add_unit(snapshot, "unit_c", 2, [], 4, true)
	var count_p1 = AIDecisionMaker._count_alive_units_for_player(snapshot["units"], 1)
	var count_p2 = AIDecisionMaker._count_alive_units_for_player(snapshot["units"], 2)
	_assert(count_p1 == 2, "Player 1 has 2 alive units (got: %d)" % count_p1)
	_assert(count_p2 == 1, "Player 2 has 1 alive unit (got: %d)" % count_p2)

# =========================================================================
# Tests: Kill-based mission achievability
# =========================================================================

func test_assassination_no_characters():
	var units = {}
	# Only non-character units
	units["enemy_1"] = {
		"owner": 1,
		"meta": {"name": "Boyz", "keywords": ["Infantry"]},
		"models": [{"id": "m1", "alive": true}],
	}
	var score = AIDecisionMaker._assess_assassination(units, 1)
	_assert(score == 0.0, "Assassination impossible with no characters (got: %.1f)" % score)

func test_assassination_with_characters():
	var units = {}
	units["enemy_char"] = {
		"owner": 1,
		"meta": {"name": "Captain", "keywords": ["Infantry", "Character"]},
		"models": [{"id": "m1", "alive": true}],
	}
	var score = AIDecisionMaker._assess_assassination(units, 1)
	_assert(score > 0.0, "Assassination achievable with alive character (got: %.1f)" % score)

func test_bring_it_down_no_targets():
	var units = {}
	units["enemy_1"] = {
		"owner": 1,
		"meta": {"name": "Boyz", "keywords": ["Infantry"]},
		"models": [{"id": "m1", "alive": true}],
	}
	var score = AIDecisionMaker._assess_bring_it_down(units, 1)
	_assert(score == 0.0, "Bring it Down impossible with no vehicles/monsters (got: %.1f)" % score)

func test_bring_it_down_with_targets():
	var units = {}
	units["enemy_tank"] = {
		"owner": 1,
		"meta": {"name": "Leman Russ", "keywords": ["Vehicle"]},
		"models": [{"id": "m1", "alive": true}],
	}
	var score = AIDecisionMaker._assess_bring_it_down(units, 1)
	_assert(score > 0.0, "Bring it Down achievable with alive vehicle (got: %.1f)" % score)

func test_cull_the_horde_no_targets():
	var units = {}
	# Infantry but only 5 starting strength
	units["enemy_1"] = {
		"owner": 1,
		"meta": {"name": "Intercessors", "keywords": ["Infantry"], "starting_strength": 5},
		"models": [{"id": "m1", "alive": true}],
	}
	var score = AIDecisionMaker._assess_cull_the_horde(units, 1)
	_assert(score == 0.0, "Cull the Horde impossible without 13+ strength infantry (got: %.1f)" % score)

# =========================================================================
# Tests: Positional mission achievability
# =========================================================================

func test_behind_enemy_lines_no_units():
	var units = {}
	var score = AIDecisionMaker._assess_behind_enemy_lines(units, 2)
	_assert(score == 0.0, "Behind Enemy Lines impossible with no units (got: %.1f)" % score)

func test_behind_enemy_lines_with_units():
	var units = {}
	units["my_unit_1"] = {
		"owner": 2,
		"meta": {"name": "Marines", "keywords": ["Infantry"]},
		"models": [{"id": "m1", "alive": true}],
	}
	units["my_unit_2"] = {
		"owner": 2,
		"meta": {"name": "Scouts", "keywords": ["Infantry"]},
		"models": [{"id": "m1", "alive": true}],
	}
	var score = AIDecisionMaker._assess_behind_enemy_lines(units, 2)
	_assert(score > 0.0, "Behind Enemy Lines achievable with 2+ units (got: %.1f)" % score)

func test_engage_on_all_fronts_too_few_units():
	var units = {}
	units["my_unit_1"] = {
		"owner": 2,
		"meta": {"name": "Marines", "keywords": []},
		"models": [{"id": "m1", "alive": true}],
	}
	var score = AIDecisionMaker._assess_engage_on_all_fronts(units, 2)
	_assert(score < 0.2, "Engage on All Fronts very unlikely with only 1 unit (got: %.2f)" % score)

# =========================================================================
# Tests: Objective mission achievability
# =========================================================================

func test_defend_stronghold_no_home_objectives():
	var units = {}
	units["my_unit"] = {
		"owner": 2,
		"meta": {"name": "Marines", "keywords": []},
		"models": [{"id": "m1", "alive": true}],
	}
	var snapshot = _create_test_snapshot()
	# Remove player2 objectives
	snapshot["board"]["objectives"] = [
		{"id": "obj_1", "zone": "player1"},
		{"id": "obj_2", "zone": "no_mans_land"},
	]
	var score = AIDecisionMaker._assess_defend_stronghold(units, snapshot, 2)
	_assert(score == 0.0, "Defend Stronghold impossible with no home objectives (got: %.1f)" % score)

# =========================================================================
# Tests: Action mission achievability
# =========================================================================

func test_action_mission_no_units():
	var units = {}
	var score = AIDecisionMaker._assess_action_mission(units, 2)
	_assert(score == 0.0, "Action mission impossible with no units (got: %.1f)" % score)

# =========================================================================
# Tests: Marked for Death
# =========================================================================

func test_marked_for_death_all_dead():
	var units = {}
	units["target_1"] = {
		"owner": 1,
		"meta": {"name": "Target 1", "keywords": []},
		"models": [{"id": "m1", "alive": false}],
	}
	units["target_2"] = {
		"owner": 1,
		"meta": {"name": "Target 2", "keywords": []},
		"models": [{"id": "m1", "alive": false}],
	}
	var mission = {
		"id": "marked_for_death",
		"name": "Marked for Death",
		"mission_data": {
			"alpha_targets": ["target_1"],
			"gamma_target": "target_2",
		},
	}
	var score = AIDecisionMaker._assess_marked_for_death(units, mission)
	_assert(score == 0.0, "Marked for Death impossible when all targets dead (got: %.1f)" % score)

# =========================================================================
# Tests: While-active missions
# =========================================================================

func test_while_active_no_enemies():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "my_unit", 2, [], 5, true)
	# No enemy units
	var mission = {
		"id": "no_prisoners",
		"name": "No Prisoners",
		"scoring": {"when": "while_active"},
	}
	var score = AIDecisionMaker._evaluate_mission_achievability(snapshot, mission, 2, 2)
	_assert(score == 0.0, "While-active impossible with no enemies alive (got: %.1f)" % score)

func test_while_active_with_enemies():
	var snapshot = _create_test_snapshot()
	_add_unit(snapshot, "my_unit", 2, [], 5, true)
	_add_unit(snapshot, "enemy", 1, [], 5, true)
	var mission = {
		"id": "no_prisoners",
		"name": "No Prisoners",
		"scoring": {"when": "while_active"},
	}
	var score = AIDecisionMaker._evaluate_mission_achievability(snapshot, mission, 2, 2)
	_assert(score == 1.0, "While-active always achievable with enemies alive (got: %.1f)" % score)
