extends SceneTree

# 11e 12.05/12.06 + 19.03: an Attached unit's fight type is decided by the
# WHOLE Attached unit's engagement, not the bodyguard's own models.
#
# Regression: FightPhase._proceed_to_fight_moves measured only the activated
# id (the bodyguard). When only the Leader's model was within Engagement
# Range the bodyguard read as "unengaged", so selecting the Attached unit to
# fight granted it an OVERRUN fight's additional pile-in — even though the
# FightSequencer (which folds the components) had already logged
# types: ["normal"]. The player saw a second pile-in on activation.
#
#  - leader-only engaged    -> normal fight, no extra pile-in
#  - bodyguard-only engaged -> normal fight, no extra pile-in
#  - whole unit unengaged (charged, targets gone) -> overrun pile-in still offered
#  - 12.04 "engaged at the start of this step" is the FIGHT step, after the
#    12.02 Pile In step: a charged unit unengaged at phase start that piles
#    into combat fights a normal fight (the sequencer used to snapshot
#    engagement at phase entry, so it got a spurious overrun pile-in)
#
# Usage: godot --headless --path . -s tests/test_attached_overrun_fold_11e.gd

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

func _m(id: String, x: float, y: float, w: int = 2) -> Dictionary:
	return {"id": id, "alive": true, "wounds": w, "current_wounds": w,
		"base_mm": 25, "base_type": "circular", "position": {"x": x, "y": y}}

func _melee(name: String) -> Array:
	return [{"name": name, "type": "Melee", "range": "Melee", "attacks": "2", "weapon_skill": "2",
		"strength": "5", "ap": "0", "damage": "1", "keywords": [], "special_rules": ""}]

# 40px = 1". Enemy model at (600,500). bg_pos / lead_pos place the
# bodyguard's two models and the Leader's model.
func _board(gs, bg_pos: Array, lead_pos: Vector2, charged: bool) -> void:
	gs.state["units"] = {
		"U_G": {"id": "U_G", "owner": 1, "status": 2, "flags": {"charged_this_turn": charged},
			"attachment_data": {"attached_characters": ["U_L"]},
			"meta": {"name": "Guard", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 2},
				"weapons": _melee("Spear")},
			"models": [_m("m1", bg_pos[0].x, bg_pos[0].y), _m("m2", bg_pos[1].x, bg_pos[1].y)]},
		"U_L": {"id": "U_L", "owner": 1, "status": 2, "flags": {"charged_this_turn": charged},
			"attached_to": "U_G",
			"meta": {"name": "Champion", "keywords": ["INFANTRY", "CHARACTER"], "stats": {"move": 6, "wounds": 5},
				"weapons": _melee("Blade")},
			"models": [_m("m1", lead_pos.x, lead_pos.y, 5)]},
		"U_B": {"id": "U_B", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "Boyz", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 1}},
			"models": [_m("e1", 600, 500, 1)]},
	}
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = 10

# Enter the Fight phase, pass both Pile In halves, select U_G to fight.
func _select(gs, pm) -> Dictionary:
	pm.transition_to_phase(10)
	var fp = pm.get_current_phase_instance()
	fp.execute_action({"type": "END_PILE_IN", "player": 1})
	fp.execute_action({"type": "END_PILE_IN", "player": 2})
	var r = fp.execute_action({"type": "SELECT_FIGHTER", "unit_id": "U_G", "player": 1})
	return {"fp": fp, "result": r}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_attached_overrun_fold_11e ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	if gs == null or pm == null:
		_check("autoloads present", false)
		_finish()
		return
	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11

	print("-- only the LEADER's model is engaged --")
	_board(gs, [Vector2(300, 600), Vector2(300, 640)], Vector2(540, 500), false)
	var a = _select(gs, pm)
	_check("selection succeeds", a.result.get("success", false), str(a.result.get("errors", [])))
	_check("no overrun pile-in triggered", not a.result.get("trigger_pile_in", false), str(a.result.keys()))
	_check("overrun unit not set", a.fp.overrun_pile_in_unit_11e == "", a.fp.overrun_pile_in_unit_11e)
	_check("PILE_IN not offered on the activation",
		not a.fp.get_available_actions().any(func(x): return x.get("type") == "PILE_IN"))

	print("\n-- only the BODYGUARD's models are engaged --")
	_board(gs, [Vector2(540, 500), Vector2(540, 540)], Vector2(300, 500), false)
	var b = _select(gs, pm)
	_check("selection succeeds", b.result.get("success", false), str(b.result.get("errors", [])))
	_check("no overrun pile-in triggered", not b.result.get("trigger_pile_in", false))
	_check("overrun unit not set", b.fp.overrun_pile_in_unit_11e == "", b.fp.overrun_pile_in_unit_11e)

	print("\n-- whole Attached unit unengaged (charged) -> genuine overrun --")
	_board(gs, [Vector2(300, 600), Vector2(300, 640)], Vector2(300, 500), true)
	var c = _select(gs, pm)
	_check("selection succeeds", c.result.get("success", false), str(c.result.get("errors", [])))
	_check("overrun pile-in triggered", c.result.get("trigger_pile_in", false), str(c.result.keys()))
	_check("overrun unit is the bodyguard", c.fp.overrun_pile_in_unit_11e == "U_G", c.fp.overrun_pile_in_unit_11e)

	print("\n-- unengaged at phase start, piles in during 12.02 -> normal fight --")
	# Lone charged unit U_S 2.5" from the Boyz (its charge target was moved
	# off); it piles in 2" to 0.5" during the Pile In step.
	gs.state["units"] = {
		"U_S": {"id": "U_S", "owner": 1, "status": 2, "flags": {"charged_this_turn": true},
			"meta": {"name": "Shield-Captain", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 6},
				"weapons": _melee("Spear")},
			"models": [_m("s1", 600, 360, 6)]},
		"U_B": {"id": "U_B", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "Boyz", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 1}},
			"models": [_m("e1", 600, 500, 1)]},
	}
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = 10
	var rules = root.get_node("RulesEngine")
	_check("fixture: U_S unengaged at phase start", not rules.is_unit_engaged("U_S", gs.state))
	pm.transition_to_phase(10)
	var fp_d = pm.get_current_phase_instance()
	var pi = fp_d.execute_action({"type": "PILE_IN", "unit_id": "U_S", "movements": {"0": Vector2(600, 440)}, "player": 1})
	_check("pile-in into engagement succeeds", pi.get("success", false), str(pi.get("errors", pi)))
	_check("U_S engaged after its pile-in", rules.is_unit_engaged("U_S", gs.state))
	fp_d.execute_action({"type": "END_PILE_IN", "player": 1})
	fp_d.execute_action({"type": "END_PILE_IN", "player": 2})
	_check("Fight step snapshot records U_S as engaged at step start",
		fp_d.sequencer_11e.engaged_at_step_start.get("U_S", false), str(fp_d.sequencer_11e.engaged_at_step_start))
	var d = fp_d.execute_action({"type": "SELECT_FIGHTER", "unit_id": "U_S", "player": 1})
	_check("selection succeeds", d.get("success", false), str(d.get("errors", [])))
	_check("no overrun pile-in triggered", not d.get("trigger_pile_in", false), str(d.keys()))
	_check("overrun unit not set", fp_d.overrun_pile_in_unit_11e == "", fp_d.overrun_pile_in_unit_11e)

	GameConstants.edition = prev_edition
	gs.state = prev_state
	_finish()

func _finish():
	print("\n=== %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
