extends SceneTree

# ROLLOUT: one-shot forced decisions for counterfactual rollouts
# (tools/ai_lab/rollout.py, AIBenchmarkRunner --bench-override=). An override
# fires once, only for its kind, player, unit and battle round; with no
# overrides armed the AI is unchanged.
# Run with: godot --headless --path . -s tests/unit/test_ai_rollout_override.gd

const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== Rollout overrides (ROLLOUT) ===\n")
	test_matching_and_one_shot()
	test_objective_lookup()
	AIDecisionMaker.set_rollout_overrides([])
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

func test_matching_and_one_shot() -> void:
	AIDecisionMaker.set_rollout_overrides([
		{"kind": "move", "round": 2, "player": 1, "unit": "U_A", "objective": "obj_center", "mode": "advance"},
		{"kind": "charge", "round": 2, "player": 2, "unit": "U_B", "targets": []},
	])
	_assert(AIDecisionMaker._take_rollout_override("move", 1, "U_A", 1).is_empty(), "wrong round: no override")
	_assert(AIDecisionMaker._take_rollout_override("move", 2, "U_A", 2).is_empty(), "wrong player: no override")
	_assert(AIDecisionMaker._take_rollout_override("shoot", 1, "U_A", 2).is_empty(), "wrong kind: no override")
	_assert(AIDecisionMaker._take_rollout_override("move", 1, "U_X", 2).is_empty(), "wrong unit: no override")
	var ov = AIDecisionMaker._take_rollout_override("move", 1, "U_A", 2)
	_assert(str(ov.get("objective", "")) == "obj_center" and str(ov.get("mode", "")) == "advance", "matching override is returned")
	_assert(AIDecisionMaker._take_rollout_override("move", 1, "U_A", 2).is_empty(), "an override fires only once")
	var ch = AIDecisionMaker._take_rollout_override("charge", 2, "U_B", 2)
	_assert(ch.has("targets") and (ch.targets as Array).is_empty(), "charge override with no targets (= skip) is returned")
	AIDecisionMaker.set_rollout_overrides([])
	_assert(AIDecisionMaker._take_rollout_override("move", 1, "U_A", 2).is_empty(), "no overrides armed: the AI is unchanged")

func test_objective_lookup() -> void:
	var snap = {"board": {"objectives": [
		{"id": "obj_center", "position": Vector2(880, 1200)},
		{"id": "obj_home_1", "position": {"x": 700.0, "y": 470.0}}]}}
	_assert(AIDecisionMaker._objective_pos_by_id(snap, "obj_center") == Vector2(880, 1200), "objective position by id (Vector2)")
	_assert(AIDecisionMaker._objective_pos_by_id(snap, "obj_home_1") == Vector2(700, 470), "objective position by id (dict)")
	_assert(AIDecisionMaker._objective_pos_by_id(snap, "obj_x") == Vector2.INF, "unknown objective -> INF")
