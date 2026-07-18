extends SceneTree

# Test AI Against All Odds (Lions of the Emperor) isolation awareness
# Verifies the AAO helper module in AIDecisionMaker: detachment/unit gating,
# the exact +1 Hit / +1 Wound damage multiplier, the friendly-gap measurement
# (incl. attached-leader groups and off-board units), the charge landing-spot
# isolation check, melee EV integration, reinforcement candidate spacing, and
# the From Golden Light end-of-turn redeploy evaluation.
# Run with: godot --headless --script tests/unit/test_ai_against_all_odds.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

const PPI := 40.0  # pixels per inch, mirrors AIDecisionMaker.PIXELS_PER_INCH

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== AI Against All Odds (Lions) Tests ===\n")
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

func _assert_approx(actual: float, expected: float, tolerance: float, message: String) -> void:
	if abs(actual - expected) <= tolerance:
		_pass_count += 1
		print("PASS: %s (got %.3f)" % [message, actual])
	else:
		_fail_count += 1
		print("FAIL: %s (got %.3f, expected %.3f)" % [message, actual, expected])

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_custodes_unit(id: String, owner: int, x_in: float, y_in: float, model_count: int = 3) -> Dictionary:
	var models = []
	for i in range(model_count):
		models.append({
			"id": "m%d" % (i + 1),
			"alive": true,
			"wounds": 3,
			"current_wounds": 3,
			"base_mm": 40,
			"position": {"x": (x_in + float(i) * 1.5) * PPI, "y": y_in * PPI}
		})
	return {
		"id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"models": models,
		"meta": {
			"name": id,
			"keywords": ["ADEPTUS CUSTODES", "IMPERIUM", "INFANTRY"],
			"stats": {"move": 6, "toughness": 6, "save": 2, "wounds": 3, "objective_control": 2},
			"weapons": [{
				"name": "Guardian spear",
				"type": "melee",
				"attacks": "5", "weapon_skill": "2", "strength": "7", "ap": "-2", "damage": "2"
			}],
			"points": 150
		},
		"flags": {},
		"attachment_data": {"attached_characters": []}
	}

func _make_snapshot(units: Dictionary, detachment: String = "Lions of the Emperor") -> Dictionary:
	return {
		"meta": {"battle_round": 2},
		"factions": {"2": {"name": "Adeptus Custodes", "detachment": detachment}},
		"units": units,
		"board": {"objectives": [], "terrain_features": []},
		"players": {"2": {"cp": 2}}
	}

# ---------------------------------------------------------------------------

func _run_tests():
	test_detachment_gate()
	test_unit_eligibility()
	test_attack_multiplier_math()
	test_friendly_gap_measurement()
	test_gap_ignores_attached_leader_group()
	test_gap_ignores_offboard_units()
	test_isolated_now_engine_check()
	test_melee_damage_aao_override()
	test_charge_landing_isolation()
	test_reinforcement_candidates_prefer_spacing()
	test_end_turn_redeploy_holds_objective()
	test_end_turn_redeploy_escapes_when_mauled()
	test_movement_intent_overrides()

func test_detachment_gate():
	var u = _make_custodes_unit("U_A", 2, 10, 10)
	var snap = _make_snapshot({"U_A": u})
	_assert(AIDecisionMaker._aao_detachment_active(snap, 2), "Lions of the Emperor detachment activates AAO")
	var snap_sh = _make_snapshot({"U_A": u}, "Shield Host")
	_assert(not AIDecisionMaker._aao_detachment_active(snap_sh, 2), "Shield Host does not activate AAO")
	# NBSP-in-name roster variant (issue #366) still matches
	var snap_nbsp = _make_snapshot({"U_A": u}, "Lions of the Emperor")
	_assert(AIDecisionMaker._aao_detachment_active(snap_nbsp, 2), "NBSP detachment name still activates AAO")

func test_unit_eligibility():
	var custodes = _make_custodes_unit("U_A", 2, 10, 10)
	_assert(AIDecisionMaker._aao_unit_eligible(custodes), "Non-VEHICLE Custodes unit is AAO-eligible")
	var vehicle = _make_custodes_unit("U_V", 2, 10, 10)
	vehicle.meta.keywords = ["ADEPTUS CUSTODES", "VEHICLE"]
	_assert(not AIDecisionMaker._aao_unit_eligible(vehicle), "Custodes VEHICLE is not AAO-eligible")
	var ork = _make_custodes_unit("U_O", 2, 10, 10)
	ork.meta.keywords = ["ORKS", "INFANTRY"]
	_assert(not AIDecisionMaker._aao_unit_eligible(ork), "Non-Custodes unit is not AAO-eligible")

func test_attack_multiplier_math():
	# WS2+ (hit capped at 2+) S7 vs T6: wound 3+ -> 2+ = x1.25 total
	_assert_approx(AIDecisionMaker._aao_attack_multiplier(2, 7, 6), 1.25, 0.001,
		"WS2+ S7 vs T6 multiplier is 1.25 (hit capped, wound 3+->2+)")
	# WS3+ S5 vs T5: hit 3+->2+ = 1.25, wound 4+->3+ = 1.333 => 1.6667
	_assert_approx(AIDecisionMaker._aao_attack_multiplier(3, 5, 5), 5.0 / 3.0, 0.001,
		"WS3+ S5 vs T5 multiplier is 1.667")
	# S12 vs T6 already wounds on 2+: only hit improves (4+ -> 3+)
	_assert_approx(AIDecisionMaker._aao_attack_multiplier(4, 12, 6), (4.0 / 6.0) / (3.0 / 6.0), 0.001,
		"WS4+ S12 vs T6 multiplier improves hit only")

func test_friendly_gap_measurement():
	var a = _make_custodes_unit("U_A", 2, 10, 10, 1)
	var b = _make_custodes_unit("U_B", 2, 20, 10, 1)  # 10" centre-to-centre
	var snap = _make_snapshot({"U_A": a, "U_B": b})
	var gap = AIDecisionMaker._aao_min_friendly_gap_inches(a, snap, 2)
	# 40mm bases: edge-to-edge = 10" - 2 * (20mm in inches ~0.787") ~ 8.43"
	_assert(gap > 8.0 and gap < 9.0, "Gap between units 10\" apart is ~8.4\" edge-to-edge (got %.2f)" % gap)
	# Moving A 6" toward B closes the gap under the 6" rule distance
	var gap_after = AIDecisionMaker._aao_min_friendly_gap_inches(a, snap, 2, Vector2(6.0 * PPI, 0))
	_assert(gap_after < 6.0, "Gap after moving 6\" toward friend drops below 6\" (got %.2f)" % gap_after)

func test_gap_ignores_attached_leader_group():
	var guard = _make_custodes_unit("U_GUARD", 2, 10, 10, 3)
	guard.attachment_data.attached_characters = ["U_CHAMP"]
	var champ = _make_custodes_unit("U_CHAMP", 2, 10.5, 10, 1)
	champ["attached_to"] = "U_GUARD"
	var snap = _make_snapshot({"U_GUARD": guard, "U_CHAMP": champ})
	var gap = AIDecisionMaker._aao_min_friendly_gap_inches(guard, snap, 2)
	_assert(gap == INF, "Attached leader does not break the bodyguard's bubble (gap INF)")
	var gap_champ = AIDecisionMaker._aao_min_friendly_gap_inches(champ, snap, 2)
	_assert(gap_champ == INF, "Bodyguard does not break its attached leader's bubble (gap INF)")

func test_gap_ignores_offboard_units():
	var a = _make_custodes_unit("U_A", 2, 10, 10, 1)
	var b = _make_custodes_unit("U_B", 2, 12, 10, 1)  # 2" away but in reserves
	b.status = GameStateData.UnitStatus.IN_RESERVES
	var c = _make_custodes_unit("U_C", 2, 13, 10, 1)  # 3" away but embarked
	c["embarked_in"] = "U_TRANSPORT"
	var snap = _make_snapshot({"U_A": a, "U_B": b, "U_C": c})
	var gap = AIDecisionMaker._aao_min_friendly_gap_inches(a, snap, 2)
	_assert(gap == INF, "Reserves/embarked units never break the bubble (gap INF)")

func test_isolated_now_engine_check():
	var a = _make_custodes_unit("U_A", 2, 10, 10, 1)
	var b = _make_custodes_unit("U_B", 2, 30, 10, 1)  # 20" away
	var snap = _make_snapshot({"U_A": a, "U_B": b})
	AIDecisionMaker._aao_now_cache.clear()
	_assert(AIDecisionMaker._aao_isolated_now(a, snap), "Isolated Lions unit gets the buff (engine check)")
	var b_close = _make_custodes_unit("U_B", 2, 14, 10, 1)  # 4" away
	var snap_close = _make_snapshot({"U_A": a, "U_B": b_close})
	AIDecisionMaker._aao_now_cache.clear()
	_assert(not AIDecisionMaker._aao_isolated_now(a, snap_close), "Friendly within 6\" removes the buff")
	AIDecisionMaker._aao_now_cache.clear()
	var snap_sh = _make_snapshot({"U_A": a, "U_B": b}, "Shield Host")
	_assert(not AIDecisionMaker._aao_isolated_now(a, snap_sh), "Non-Lions detachment never gets the buff")
	AIDecisionMaker._aao_now_cache.clear()

func test_melee_damage_aao_override():
	var a = _make_custodes_unit("U_A", 2, 10, 10, 3)
	var enemy = _make_custodes_unit("U_E", 1, 20, 10, 5)
	enemy.meta.keywords = ["ORKS", "INFANTRY"]
	enemy.meta.stats.toughness = 5
	var dmg_plain = AIDecisionMaker._estimate_melee_damage(a, enemy, {}, 0)
	var dmg_buffed = AIDecisionMaker._estimate_melee_damage(a, enemy, {}, 1)
	_assert(dmg_buffed > dmg_plain * 1.15,
		"AAO override raises melee EV (%.2f -> %.2f)" % [dmg_plain, dmg_buffed])

func test_charge_landing_isolation():
	var charger = _make_custodes_unit("U_A", 2, 10, 10, 3)
	var target = _make_custodes_unit("U_E", 1, 10, 20, 5)
	target.meta.keywords = ["ORKS", "INFANTRY"]
	# Friendly standing right next to the target's position
	var buddy = _make_custodes_unit("U_B", 2, 10, 22, 3)
	var snap_crowded = _make_snapshot({"U_A": charger, "U_E": target, "U_B": buddy})
	_assert(not AIDecisionMaker._aao_charge_keeps_isolation(charger, target, snap_crowded, 2),
		"Charge into a combat a friendly already crowds loses AAO")
	# Same charge with the friendly far away keeps the buff
	var buddy_far = _make_custodes_unit("U_B", 2, 40, 40, 3)
	var snap_open = _make_snapshot({"U_A": charger, "U_E": target, "U_B": buddy_far})
	_assert(AIDecisionMaker._aao_charge_keeps_isolation(charger, target, snap_open, 2),
		"Solo charge keeps AAO at the landing spot")

func test_reinforcement_candidates_prefer_spacing():
	var near_friend = Vector2(10.0 * PPI, 10.0 * PPI)
	var far_spot = Vector2(30.0 * PPI, 30.0 * PPI)
	var close_spot = Vector2(12.0 * PPI, 10.0 * PPI)  # 2" from the friendly
	var sorted = AIDecisionMaker._score_and_sort_reinforcement_candidates(
		[close_spot, far_spot], [], {}, [near_friend])
	_assert(sorted[0] == far_spot,
		"Reinforcement scoring prefers the drop spot 6\"+ clear of friendlies")

func test_end_turn_redeploy_holds_objective():
	var a = _make_custodes_unit("U_A", 2, 10, 10, 3)
	var snap = _make_snapshot({"U_A": a})
	snap.board.objectives = [{"id": "obj_1", "position": {"x": 10.5 * PPI, "y": 10.0 * PPI}}]
	var verdict = AIDecisionMaker._evaluate_end_turn_redeploy(snap, a, "U_A", 2)
	_assert(not verdict.use, "From Golden Light declined while holding an objective")

func test_end_turn_redeploy_escapes_when_mauled():
	var a = _make_custodes_unit("U_A", 2, 10, 10, 3)
	# Down to 1 of 3 models, last model on 1 wound
	a.models[0].alive = false
	a.models[1].alive = false
	a.models[2].current_wounds = 1
	var enemy = _make_custodes_unit("U_E", 1, 18, 10, 5)
	enemy.meta.keywords = ["ORKS", "INFANTRY"]
	var snap = _make_snapshot({"U_A": a, "U_E": enemy})
	snap.board.objectives = [{"id": "obj_1", "position": {"x": 40.0 * PPI, "y": 50.0 * PPI}}]
	var verdict = AIDecisionMaker._evaluate_end_turn_redeploy(snap, a, "U_A", 2)
	_assert(verdict.use, "From Golden Light used to escape when mauled with enemies close")

func test_movement_intent_overrides():
	# A friendly currently 20" away whose planned move ends 4" away must break
	# the projected bubble when measured through intent overrides.
	var a = _make_custodes_unit("U_A", 2, 10, 10, 1)
	var b = _make_custodes_unit("U_B", 2, 30, 10, 1)
	var snap = _make_snapshot({"U_A": a, "U_B": b})
	var overrides = {"U_B": Vector2(14.0 * PPI, 10.0 * PPI)}
	var gap = AIDecisionMaker._aao_min_friendly_gap_inches(a, snap, 2, Vector2.ZERO, overrides)
	_assert(gap < 6.0, "Intent override measures the friend at its planned destination (got %.2f)" % gap)
	var gap_live = AIDecisionMaker._aao_min_friendly_gap_inches(a, snap, 2)
	_assert(gap_live > 6.0, "Without overrides the friend measures at its live position (got %.2f)" % gap_live)
