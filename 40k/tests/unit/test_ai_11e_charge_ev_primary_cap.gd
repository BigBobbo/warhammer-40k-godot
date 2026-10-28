extends SceneTree

# 11e AI valuation fixes raised by the LLM-critic review (2026-10-28):
#  1. Multi-target charge declarations are scored as an expected value over
#     the 2D6 roll (11.02/11.04: targets are picked AFTER the roll, and the
#     post-roll step keeps whichever declared targets the roll reached) —
#     not as an all-or-nothing bet on the farthest target, and not by adding
#     every target's full value (the charger has one set of attacks).
#  2. Objective VP respects the 15 VP per-turn primary cap, so extra
#     objectives have diminishing returns (Battlefield Dominance: home + 2
#     others = 13 VP; a third non-home adds 2, a fourth adds 0).
# Run with: godot --headless --path . -s tests/unit/test_ai_11e_charge_ev_primary_cap.gd

const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== 11e charge EV + primary cap tests ===\n")
	_test_window_vp()
	_test_objective_marginal_under_cap()
	_test_flat_hold_min_card_unchanged()
	_test_multi_charge_expected_value()
	_test_multi_charge_unreachable_combo()
	_test_shooting_value_per_wound()
	_test_melee_classifier()
	_test_charge_leaves_held_objective()
	_test_extra_target_that_hits_back_adds_nothing()
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

func _near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps

# Battlefield Dominance command rules (PrimaryMissionData11e)
const BD_RULES = [
	{"when": "command", "type": "per_objective", "vp_per": 3, "exclude_home": false, "rounds": [2, 5]},
	{"when": "command", "type": "per_objective", "vp_per": 2, "exclude_home": true, "require_hold_home": true, "rounds": [2, 5]},
]

func _test_window_vp() -> void:
	_assert(_near(AIDecisionMaker._primary_command_window_vp(BD_RULES, 1), 3.0), "BD: home only = 3 VP")
	_assert(_near(AIDecisionMaker._primary_command_window_vp(BD_RULES, 3), 13.0), "BD: home + 2 = 13 VP")
	_assert(_near(AIDecisionMaker._primary_command_window_vp(BD_RULES, 4), 18.0), "BD: home + 3 = 18 VP uncapped")

func _set_primary(rules: Array) -> void:
	AIDecisionMaker._primary_awareness_p1 = {"card_name": "test", "vp_rules": rules}
	AIDecisionMaker._secondary_awareness_p1 = {}

func _nml(held: bool) -> Dictionary:
	return {"is_home": false, "is_enemy_home": false, "is_central": false, "is_held_by_me": held}

func _test_objective_marginal_under_cap() -> void:
	_set_primary(BD_RULES)
	var second = AIDecisionMaker._estimate_objective_vp_value(_nml(false), 1, 2, 2)
	_assert(_near(second.vp, 5.0), "BD: taking a 2nd non-home objective (10 -> 13... from home+1) is worth the full 5 VP (got %s)" % str(second.vp))
	var third = AIDecisionMaker._estimate_objective_vp_value(_nml(false), 1, 3, 2)
	_assert(_near(third.vp, 2.0), "BD: a 3rd non-home objective adds only 2 VP under the 15 cap (got %s)" % str(third.vp))
	var fourth = AIDecisionMaker._estimate_objective_vp_value(_nml(false), 1, 4, 2)
	_assert(_near(fourth.vp, 0.0), "BD: a 4th non-home objective adds 0 VP (got %s)" % str(fourth.vp))
	var cap_note := false
	for s in third.sources:
		if "primary cap" in str(s):
			cap_note = true
	_assert(cap_note, "narration says the primary cap limited the value")
	var keep = AIDecisionMaker._estimate_objective_vp_value(_nml(true), 1, 4, 2)
	_assert(_near(keep.vp, 2.0), "BD: losing one of 4 held (18 -> 13, capped 15 -> 13) costs 2 VP (got %s)" % str(keep.vp))

func _test_flat_hold_min_card_unchanged() -> void:
	# Meatgrinder: flat 4 VP for holding >= 1 non-home objective
	_set_primary([{"when": "command", "type": "hold_min", "min": 1, "exclude_home": true, "vp": 4, "rounds": [2, 5]}])
	var first = AIDecisionMaker._estimate_objective_vp_value(_nml(false), 1, 1, 1)
	var second = AIDecisionMaker._estimate_objective_vp_value(_nml(false), 1, 2, 1)
	_assert(first.vp > second.vp, "Meatgrinder: the first non-home objective is worth more than the second (%s vs %s)" % [str(first.vp), str(second.vp)])

func _target(id: String, dist: float, need: float, value: float) -> Dictionary:
	var p = AIDecisionMaker._charge_success_probability(need)
	return {"target_id": id, "target_name": id, "dist": dist, "need": need, "prob": p,
		"score": value * p, "target_score": value, "melee_dmg": 1.0, "target_hp": 5.0, "action": {}}

func _test_multi_charge_expected_value() -> void:
	# A on 5+ (30/36), B on 9+ (10/36), both worth 10 if reached.
	var a = _target("A", 5.0, 5.0, 10.0)
	var b = _target("B", 9.0, 9.0, 10.0)
	var charger = {"models": [{"base_mm": 32, "current_wounds": 2, "position": {"x": 0, "y": 0}}]}
	var res = AIDecisionMaker._score_multi_target_combo("C", charger, "Charger", [a, b], 1.0,
		{"expected_damage": 0.0, "score_penalty": 1.0}, {"units": {}}, 1)
	var share = AIDecisionMaker.MULTI_CHARGE_EXTRA_TARGET_SHARE
	# rolls 5-8: A only (20/36); rolls 9-12: A + share*B (10/36)
	var expected = (20.0 / 36.0) * 10.0 + (10.0 / 36.0) * (10.0 + share * 10.0)
	_assert(_near(res.score, expected, 0.05), "EV over 2D6 = %.2f (got %.2f)" % [expected, res.score])
	_assert(res.score > a.score, "declaring A+B beats declaring A alone (%.2f > %.2f): a low roll still takes A" % [res.score, a.score])
	_assert(res.score < a.score + b.score, "the combo is not the sum of both full values (one set of attacks)")
	_assert(res.action.get("payload", {}).get("target_unit_ids", []) == ["A", "B"], "action lists both targets, nearest first")
	_assert("after the roll" in str(res.description), "description says targets are picked after the roll: %s" % res.description)

func _test_multi_charge_unreachable_combo() -> void:
	# B needs 13+: no roll reaches both, so the combo is not offered
	var a = _target("A", 5.0, 5.0, 10.0)
	var b = _target("B", 13.0, 13.0, 10.0)
	b.prob = 0.0
	var charger = {"models": [{"base_mm": 32, "current_wounds": 2, "position": {"x": 0, "y": 0}}]}
	var res = AIDecisionMaker._score_multi_target_combo("C", charger, "Charger", [a, b], 1.0,
		{"expected_damage": 0.0, "score_penalty": 1.0}, {"units": {}}, 1)
	_assert(res.score == -INF, "a combo no roll can complete is not offered")

# SHOOT-PW: the critic case s7001_r2_p1_shooting_1 — a healthy 14-wound unit
# (value 7.45, 1.78 dmg) vs a wounded 6-wound one (value 2.55, 2.22 dmg).
func _test_shooting_value_per_wound() -> void:
	var tv = {"HEALTHY": 7.45, "WOUNDED": 2.55}
	var th = {"HEALTHY": 14.0, "WOUNDED": 6.0}
	var alloc = {"HEALTHY": 0.0, "WOUNDED": 0.0}
	var wpm = {"HEALTHY": 5.0, "WOUNDED": 3.0}
	var healthy = AIDecisionMaker._calculate_marginal_value(1.78, "HEALTHY", tv, th, alloc, wpm, 1.0, {})
	var wounded = AIDecisionMaker._calculate_marginal_value(2.22, "WOUNDED", tv, th, alloc, wpm, 1.0, {})
	# 2.55 was the wounded unit's value AFTER the planned-charge-target halving
	# (SHOOT-FINISH no longer halves a unit below half its wounds): 5.1 here.
	tv["WOUNDED"] = 5.1
	var wounded_full = AIDecisionMaker._calculate_marginal_value(2.22, "WOUNDED", tv, th, alloc, wpm, 1.0, {})
	_assert(wounded_full > healthy, "per-wound value: the wounded unit (%.2f) beats chip damage on the healthy one (%.2f)" % [wounded_full, healthy])
	_assert(wounded > healthy, "even at the halved value, SHOOT-UNIT puts the likely kill first (%.2f vs %.2f)" % [wounded, healthy])
	var unit_v = AIDecisionMaker.SHOOT_UNIT_REMOVAL_VALUE
	_assert(_near(healthy, 1.78 * 7.45 / 14.0 + 1.78 / 14.0 * unit_v, 0.01), "healthy target value = dmg x (value + unit value) / wounds (got %.3f)" % healthy)
	# critic case s7001_r2_p2_shooting_1 (aifix run): healthy Custodian Guard
	# (value 10.37, 15 W, 0.89 dmg) vs a 4-wound Prosecutor Squad (value 0.83,
	# 1.87 dmg at efficiency 0.7) — the killable squad must win.
	var tv2 = {"CG": 10.37, "PRO": 0.83}
	var th2 = {"CG": 15.0, "PRO": 4.0}
	var al2 = {"CG": 0.0, "PRO": 0.0}
	var wp2 = {"CG": 5.0, "PRO": 1.0}
	var cg = AIDecisionMaker._calculate_marginal_value(0.89, "CG", tv2, th2, al2, wp2, 1.0, {})
	var pro = AIDecisionMaker._calculate_marginal_value(1.87, "PRO", tv2, th2, al2, wp2, 0.7, {})
	_assert(pro > cg, "a likely kill on a cheap squad (%.2f) beats chip damage on an elite unit (%.2f)" % [pro, cg])

func _weapon(type: String, s: int, a: String, ap: String, d: String, rules: String = "") -> Dictionary:
	return {"type": type, "strength": str(s), "attacks": a, "ap": ap, "damage": d, "special_rules": rules}

func _test_melee_classifier() -> void:
	var prosecutors = {"meta": {"weapons": [_weapon("Ranged", 4, "1", "0", "1", "rapid fire 1"), _weapon("Melee", 3, "2", "0", "1")]}}
	var boyz = {"meta": {"weapons": [_weapon("Ranged", 4, "1", "0", "1", "pistol"), _weapon("Melee", 4, "3", "-1", "1")]}}
	var guard = {"meta": {"weapons": [_weapon("Ranged", 5, "2", "-1", "2", "assault, rapid fire 2"), _weapon("Melee", 8, "6", "-2", "2")]}}
	var champion = {"meta": {"weapons": [_weapon("Melee", 10, "5", "-3", "3")]}}
	_assert(not AIDecisionMaker._is_melee_focused_unit(prosecutors), "Prosecutors (boltgun + S3 close combat weapon) are not melee-focused")
	_assert(AIDecisionMaker._is_melee_focused_unit(boyz), "Ork Boyz (pistols + choppas) stay melee-focused")
	_assert(not AIDecisionMaker._is_melee_focused_unit(guard), "Custodian Guard (strong ranged spear) are not melee-focused")
	_assert(AIDecisionMaker._is_melee_focused_unit(champion), "a unit with only a strong melee weapon is melee-focused")

func _model(id: String, x: float, y: float, oc: int) -> Dictionary:
	return {"id": id, "alive": true, "current_wounds": 2, "wounds": 2, "base_mm": 32,
		"position": {"x": x, "y": y}, "oc": oc}

func _unit(owner: int, models: Array, oc: int) -> Dictionary:
	return {"owner": owner, "status": 2, "models": models,
		"meta": {"name": "u", "stats": {"objective_control": oc}, "keywords": ["INFANTRY"], "weapons": []}}

func _test_charge_leaves_held_objective() -> void:
	var obj = {"id": "obj_a", "position": {"x": 400.0, "y": 400.0}}
	var charger = _unit(1, [_model("c1", 400, 400, 2), _model("c2", 410, 400, 2)], 2)
	var target = _unit(2, [_model("t1", 400, 700, 1)], 1)
	var enemy_near = _unit(2, [_model("e1", 420, 410, 1)], 1)
	var snap = {"board": {"objectives": [obj]}, "units": {"C": charger, "T": target, "E": enemy_near}}
	var leave = AIDecisionMaker._charge_leaves_held_objective("C", charger, target, snap, 1)
	_assert(not leave.is_empty(), "sole holder (OC %s vs enemy %s) leaving the objective is flagged" % [str(leave.get("friendly", "?")), str(leave.get("enemy", "?"))])
	var friend = _unit(1, [_model("f1", 390, 410, 2), _model("f2", 395, 390, 2)], 2)
	snap.units["F"] = friend
	var leave2 = AIDecisionMaker._charge_leaves_held_objective("C", charger, target, snap, 1)
	_assert(leave2.is_empty(), "no cost when other friendly units still hold the objective")

func _test_extra_target_that_hits_back_adds_nothing() -> void:
	# B is a melee monster (S10 A10 AP-3 D3): as an extra target it would maul
	# the charger, so the declaration is worth exactly declaring A alone.
	var a = _target("A", 5.0, 5.0, 10.0)
	var b = _target("B", 9.0, 9.0, 10.0)
	var charger = _unit(1, [_model("c1", 0, 0, 2), _model("c2", 30, 0, 2)], 2)
	charger.meta.stats["toughness"] = 4
	charger.meta.stats["save"] = 4
	var brute = _unit(2, [_model("b1", 0, 300, 1)], 1)
	brute.meta.weapons = [_weapon("Melee", 10, "10", "-3", "3")]
	var res = AIDecisionMaker._score_multi_target_combo("C", charger, "Charger", [a, b], 1.0,
		{"expected_damage": 0.0, "score_penalty": 1.0}, {"units": {"B": brute}}, 1)
	var single_ev = (30.0 / 36.0) * 10.0
	_assert(_near(res.score, single_ev, 0.05), "a hard-hitting extra target adds 0: EV %.2f == A alone %.2f" % [res.score, single_ev])
