extends SceneTree

# 11e charge targets must be within 12" AND within the charge roll.
#
# Core 11.04 BEFORE MOVING: "Select one or more enemy units that are within
# 12" of your unit and within the maximum distance of your unit" — and the
# maximum distance IS the 2D6 charge roll (11.02 step 2). pg-37 MAKING A CHARGE
# MOVE example B: a unit "more than 7" from the charging unit ... cannot be
# selected as a charge target, even though the charging unit could end its
# charge move within 2" of this unit". FAILED CHARGES sidebar: an unmodified
# roll of 2 "is never sufficient".
#
# Replaces tests/test_charge_roll_reachability_er.gd, whose premise was wrong:
# it asserted that a 9" roll could select a target 9.6" away because the
# charger only had to close to 2" engagement range (the "Deffkopta" report,
# PR #859, ceiling min(12, roll + ER)). Under 11.04 that target is beyond the
# roll, so the charge fails. This suite pins the corrected ceiling
# min(12, roll), its inclusive 0.02" float tolerance, the Attached-unit
# measurement (19.01), Heroic Intervention's "within the maximum distance"
# (15.11), the player-facing text, and the AI's roll-needed math.
#
# Review fixes also pinned here: the post-roll success check
# (_is_charge_roll_sufficient / _per_target_charge_requirements) and every
# pre-roll 12" check (RulesEngine.charge_targets_within_12, DECLARE_CHARGE)
# measure from the whole Attached unit too, so a target declared before the
# roll (the UI path) and reachable only through the leader is not FAILED; the
# MP client's failure text keeps the phase's within/beyond-the-roll split; and
# a target at an exact whole inch (measured a hair over) asks for that roll in
# the UI 'Min roll' and the AI odds, as the phase accepts it.
#
# All 11e flows go through the real ChargePhase.execute_action path
# (DECLARE_CHARGE -> CHARGE_ROLL{rng_seed} -> APPLY_CHARGE_MOVE).
#
# Usage: godot --headless --path . -s tests/test_charge_target_within_roll_11e.gd

var passed := 0
var failed := 0
var _started := false
var _seed_by_total := {}  # 2D6 total -> first RNGService seed producing it

const PX_PER_INCH := 40.0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, ("  --  " + detail) if detail != "" else ""])

func _init():
	create_timer(0.3).timeout.connect(_run_tests)

func _meas() -> Node:
	return root.get_node("Measurement")

func _r32() -> float:
	return _meas().base_radius_px(32)

# Centre gap (px) for two 32mm bases whose edges are `edge_in` inches apart.
func _gap_px(edge_in: float) -> float:
	return edge_in * PX_PER_INCH + 2.0 * _r32()

func _model(id: String, pos: Vector2, wounds: int = 1) -> Dictionary:
	return {"id": id, "alive": true, "current_wounds": wounds, "wounds": wounds,
		"base_mm": 32, "base_type": "circular", "position": {"x": pos.x, "y": pos.y}}

func _unit(id: String, owner: int, positions: Array, keywords: Array = ["INFANTRY"]) -> Dictionary:
	var models: Array = []
	for i in range(positions.size()):
		models.append(_model("m%d" % (i + 1), positions[i]))
	return {"id": id, "squad_id": id, "owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED, "flags": {},
		"attached_to": null, "attachment_data": {"attached_characters": []},
		"meta": {"name": id, "keywords": keywords, "stats": {"move": 6, "toughness": 4, "save": 4, "wounds": 1}},
		"models": models, "embarked_in": null}

func _set_state(units: Dictionary, cp: int = 0) -> void:
	root.get_node("GameState").state = {
		"meta": {"phase": GameStateData.Phase.CHARGE, "active_player": 2, "battle_round": 2, "turn_number": 2, "game_id": "within_roll"},
		"units": units,
		"players": {"1": {"cp": cp, "vp": 0}, "2": {"cp": cp, "vp": 0}},
		"board": {"terrain": []},
		"phase_log": [],
	}
	root.get_node("TerrainManager").terrain_features.clear()

func _new_phase() -> Node:
	var phase = load("res://phases/ChargePhase.gd").new()
	root.add_child(phase)
	phase._on_phase_enter()
	return phase

# Charger (P2, one model at origin) and one target (P1) `edge_in` inches away.
const ORIGIN := Vector2(700.0, 1200.0)
func _pair(edge_in: float) -> Dictionary:
	return {
		"U_CHG": _unit("U_CHG", 2, [ORIGIN]),
		"U_TGT": _unit("U_TGT", 1, [ORIGIN + Vector2(_gap_px(edge_in), 0.0)]),
	}

func _edge(a: String, b: String) -> float:
	var gs = root.get_node("GameState")
	return _meas().model_to_model_distance_inches(gs.state.units[a].models[0], gs.state.units[b].models[0])

func _declare_and_roll(phase: Node, targets: Array, total: int) -> Dictionary:
	var d = phase.execute_action({"type": "DECLARE_CHARGE", "actor_unit_id": "U_CHG", "payload": {"target_unit_ids": targets}})
	if not d.get("success", false):
		return {"declare": d}
	var r = phase.execute_action({"type": "CHARGE_ROLL", "actor_unit_id": "U_CHG", "payload": {"rng_seed": _seed_by_total[total]}})
	return {"declare": d, "roll": r}

func _run_tests():
	if _started:
		return
	_started = true
	print("\n=== test_charge_target_within_roll_11e ===")
	var prev_edition = GameConstants.edition
	# Written AFTER the first timer (SettingsService overwrites _init writes).
	GameConstants.edition = 11
	_check("harness runs this suite at edition 11", GameConstants.edition == 11, str(GameConstants.edition))

	var rules = root.get_node("RulesEngine")
	for s in range(0, 200):
		var d = rules.RNGService.new(s).roll_d6(2)
		var t: int = d[0] + d[1]
		if not _seed_by_total.has(t):
			_seed_by_total[t] = s
	_check("found an rng seed for every 2D6 total 2..12", _seed_by_total.size() == 11, str(_seed_by_total))

	_test_ceiling_pins()
	_test_boundary_7_roll()
	_test_7_0_charge_engages()
	_test_predeclared_beyond_roll_dropped()
	_test_failed_charges_roll_of_2()
	_test_deffkopta_case_now_fails()
	_test_attached_leader_in_front()
	_test_attached_leader_declared_before_roll()
	_test_attached_leader_12in_checks()
	_test_client_failure_text_split()
	_test_min_roll_float_boundary()
	_test_heroic_intervention_within_roll()
	_test_ai_roll_needed()
	await _test_ai_command_reroll_uses_edge_distance()
	_test_10e_unchanged()

	GameConstants.edition = prev_edition
	print("\n=== %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)

# ── ceiling + tolerance pins ───────────────────────────────────────────

func _test_ceiling_pins() -> void:
	print("\n-- ceiling = min(12, roll); inclusive 'within' with a 0.02\" tolerance --")
	_check("selectable_distance_ceiling(7) == 7 (ER does not extend it)", ChargeMove11e.selectable_distance_ceiling(7.0) == 7.0,
		str(ChargeMove11e.selectable_distance_ceiling(7.0)))
	_check("selectable_distance_ceiling(2) == 2", ChargeMove11e.selectable_distance_ceiling(2.0) == 2.0)
	_check("selectable_distance_ceiling(12) == 12", ChargeMove11e.selectable_distance_ceiling(12.0) == 12.0)
	_check("selectable_distance_ceiling(14) == 12 (12\" cap, e.g. a +2 bonus on a 12)", ChargeMove11e.selectable_distance_ceiling(14.0) == 12.0)
	_check("tolerance is 0.02\" — the same as ChargePhase.MOVEMENT_CAP_EPSILON",
		is_equal_approx(ChargeMove11e.WITHIN_TOLERANCE_INCHES, 0.02)
		and is_equal_approx(ChargeMove11e.WITHIN_TOLERANCE_INCHES, ChargePhase.MOVEMENT_CAP_EPSILON))

# ── real ChargePhase flow at the 7" boundary ──────────────────────────

func _test_boundary_7_roll() -> void:
	print("\n-- roll 7 (real DECLARE_CHARGE{[]} -> CHARGE_ROLL): targets at 6.9 / 7.0 / 7.01 selectable; 7.03 / 7.1 / 8.9 not --")
	for e in [6.9, 7.0, 7.01, 7.03, 7.1, 8.9]:
		_set_state(_pair(e))
		var measured := _edge("U_CHG", "U_TGT")
		_check("fixture: edge %.2f\" measured %.4f\"" % [e, measured], absf(measured - e) < 0.005)
		var phase = _new_phase()
		var res := _declare_and_roll(phase, [], 7)
		var roll: Dictionary = res.get("roll", {})
		_check("%.2f\": declare + roll accepted" % e, res.declare.get("success", false) and roll.get("success", false),
			str(res))
		var dice = roll.get("dice", [{}])[0]
		_check("%.2f\": the seeded charge roll is 7" % e, int(dice.get("total", -1)) == 7, str(dice))
		var pend: Dictionary = phase.get_pending_charges().get("U_CHG", {})
		if e <= 7.01:
			_check("%.2f\": WITHIN the roll -> charge continues (charge_failed=false)" % e, roll.get("charge_failed", true) == false,
				str(roll.get("charge_failed", "missing")))
			_check("%.2f\": selectable == [U_TGT]" % e, pend.get("selectable_targets", []) == ["U_TGT"], str(pend.get("selectable_targets", "-")))
			_check("%.2f\": CHARGE_ROLL result carries selectable_targets (MP mirror)" % e,
				roll.get("selectable_targets", []) == ["U_TGT"], str(roll.get("selectable_targets", "missing")))
		else:
			_check("%.2f\": BEYOND the roll -> charge FAILS at the roll" % e, roll.get("charge_failed", false) == true,
				str(roll.get("charge_failed", "missing")))
			_check("%.2f\": no pending charge left (the unit does not move)" % e, not phase.has_pending_charge("U_CHG"))
			var attempts: Array = phase.get_failed_charge_attempts()
			_check("%.2f\": INSUFFICIENT_ROLL failure recorded" % e,
				attempts.size() == 1 and attempts[0].get("primary_category", "") == "INSUFFICIENT_ROLL", str(attempts))
			var det := str(attempts[0].get("errors", [""])[0]) if attempts.size() > 0 else ""
			_check("%.2f\": undeclared failure reports the nearest enemy's distance (not inf)" % e,
				("%.1f\"" % e) in det and not "inf" in det, det)
		phase.queue_free()

func _test_7_0_charge_engages() -> void:
	print("\n-- roll 7 vs a target exactly 7.0\" away: the charge is makeable and engages --")
	_set_state(_pair(7.0))
	var phase = _new_phase()
	var res := _declare_and_roll(phase, [], 7)
	_check("7.0\": roll leaves a pending charge", phase.has_pending_charge("U_CHG"), str(res.get("roll", {})))
	var end := ORIGIN + Vector2(6.95 * PX_PER_INCH, 0.0)
	var mv = phase.execute_action({"type": "APPLY_CHARGE_MOVE", "actor_unit_id": "U_CHG",
		"payload": {"target_unit_ids": ["U_TGT"],
			"per_model_paths": {"m1": [[ORIGIN.x, ORIGIN.y], [end.x, end.y]]}, "per_model_rotations": {}}})
	_check("7.0\": APPLY_CHARGE_MOVE of 6.95\" succeeds", mv.get("success", false), str(mv.get("errors", mv.get("error", ""))))
	var gs = root.get_node("GameState")
	var gap := _edge("U_CHG", "U_TGT")
	_check("7.0\": charger ends 0.05\" from the target (engaged)", absf(gap - 0.05) < 0.01, "gap=%.4f" % gap)
	_check("7.0\": charged_this_turn set", gs.state.units.U_CHG.flags.get("charged_this_turn", false) == true)
	phase.queue_free()

func _test_predeclared_beyond_roll_dropped() -> void:
	print("\n-- a pre-declared target 7.1\" away on a 7 is dropped; the failure names the roll --")
	_set_state(_pair(7.1))
	var phase = _new_phase()
	var res := _declare_and_roll(phase, ["U_TGT"], 7)
	var roll: Dictionary = res.get("roll", {})
	_check("declared [U_TGT] at 7.1\": charge fails", roll.get("charge_failed", false) == true, str(roll))
	var attempts: Array = phase.get_failed_charge_attempts()
	var detail := str(attempts[0].get("errors", [""])[0]) if attempts.size() > 0 else ""
	_check("failure detail names the roll and the distance", "Rolled 7\"" in detail and "7.1\"" in detail, detail)
	_check("failure detail teaches the 11.04 rule (target within the charge roll)",
		"within the charge roll" in detail and "11.04" in detail, detail)
	_check("failure detail no longer talks about closing to engagement range",
		not "close to within" in detail, detail)
	var tip: String = phase.get_failure_category_tooltip("INSUFFICIENT_ROLL")
	_check("INSUFFICIENT_ROLL tooltip at 11e explains 'within 12\" AND within the charge roll'",
		"within 12\" AND within the charge roll" in tip and "never succeeds" in tip, tip)
	phase.queue_free()

func _test_failed_charges_roll_of_2() -> void:
	print("\n-- FAILED CHARGES sidebar: a roll of 2 never succeeds (target 2.5\" away) --")
	_set_state(_pair(2.5))
	var phase = _new_phase()
	var res := _declare_and_roll(phase, [], 2)
	var roll: Dictionary = res.get("roll", {})
	_check("roll is 2", int(roll.get("dice", [{}])[0].get("total", -1)) == 2, str(roll))
	_check("roll 2 vs 2.5\": charge FAILS (old roll + ER ceiling let it through)", roll.get("charge_failed", false) == true, str(roll))
	_check("roll 2: unit does not move (no pending charge)", not phase.has_pending_charge("U_CHG"))
	phase.queue_free()

func _test_deffkopta_case_now_fails() -> void:
	print("\n-- the old 'Deffkopta' case: 9\" roll vs 9.6\" FAILS now; vs 9.0\" succeeds --")
	_set_state(_pair(9.6))
	var phase = _new_phase()
	var roll: Dictionary = _declare_and_roll(phase, ["U_TGT"], 9).get("roll", {})
	_check("9 vs 9.6\": FAILS (the target is beyond the roll, 11.04 example B)", roll.get("charge_failed", false) == true, str(roll))
	phase.queue_free()
	_set_state(_pair(9.0))
	phase = _new_phase()
	roll = _declare_and_roll(phase, ["U_TGT"], 9).get("roll", {})
	_check("9 vs 9.0\": succeeds", roll.get("charge_failed", true) == false, str(roll))
	_check("9 vs 9.0\": target kept", phase.get_pending_charges().get("U_CHG", {}).get("targets", []) == ["U_TGT"])
	phase.queue_free()

# ── 19.01: the Attached unit is one unit — the leader's models count ────

func _test_attached_leader_in_front() -> void:
	print("\n-- attached CHARACTER in front of his bodyguard: within-12\" and within-roll measure from him too (19.01) --")
	# Leader 6.5" from the target, bodyguard model 1.5" behind him (edges),
	# i.e. 9.26" from the target — beyond even the old roll + ER (9") ceiling.
	var tgt := Vector2(1500.0, 1200.0)
	var ldr_pos := tgt - Vector2(_gap_px(6.5), 0.0)
	var bg_pos := ldr_pos - Vector2(_gap_px(1.5), 0.0)
	var units := {
		"U_CHG": _unit("U_CHG", 2, [bg_pos]),
		"U_LDR": _unit("U_LDR", 2, [ldr_pos], ["INFANTRY", "CHARACTER"]),
		"U_TGT": _unit("U_TGT", 1, [tgt]),
	}
	units.U_CHG.attachment_data = {"attached_characters": ["U_LDR"]}
	units.U_LDR.attached_to = "U_CHG"
	_set_state(units)
	_check("fixture: leader 6.5\" from the target", absf(_edge("U_LDR", "U_TGT") - 6.5) < 0.005, str(_edge("U_LDR", "U_TGT")))
	_check("fixture: bodyguard 9.26\" from the target", absf(_edge("U_CHG", "U_TGT") - 9.26) < 0.01, str(_edge("U_CHG", "U_TGT")))
	var chg: MoveType = MoveTypes.get_type("charge")
	var board = root.get_node("GameState").state
	_check("template _targets_within(7) sees the target through the leader",
		chg._targets_within("U_CHG", board, ChargeMove11e.selectable_distance_ceiling(7.0)) == ["U_TGT"])
	var phase = _new_phase()
	var roll: Dictionary = _declare_and_roll(phase, [], 7).get("roll", {})
	_check("roll 7: charge continues (target within 7\" of the leader)", roll.get("charge_failed", true) == false, str(roll))
	_check("roll 7: selectable == [U_TGT]", phase.get_pending_charges().get("U_CHG", {}).get("selectable_targets", []) == ["U_TGT"])
	_check("roll 7: min_distance is measured from the leader (6.5\")",
		absf(float(roll.get("dice", [{}])[0].get("min_distance", 0.0)) - 6.5) < 0.01, str(roll.get("dice", [{}])[0].get("min_distance")))
	# Leader moves 6.45" into engagement, bodyguard follows 6.45" (stays in coherency).
	var l_end := ldr_pos + Vector2(6.45 * PX_PER_INCH, 0.0)
	var b_end := bg_pos + Vector2(6.45 * PX_PER_INCH, 0.0)
	var mv = phase.execute_action({"type": "APPLY_CHARGE_MOVE", "actor_unit_id": "U_CHG",
		"payload": {"target_unit_ids": ["U_TGT"], "per_model_rotations": {},
			"per_model_paths": {
				"m1": [[bg_pos.x, bg_pos.y], [b_end.x, b_end.y]],
				"U_LDR:m1": [[ldr_pos.x, ldr_pos.y], [l_end.x, l_end.y]]}}})
	_check("the led charge APPLY_CHARGE_MOVE succeeds", mv.get("success", false), str(mv.get("errors", mv.get("error", ""))))
	_check("leader ends engaged (0.05\")", absf(_edge("U_LDR", "U_TGT") - 0.05) < 0.01, str(_edge("U_LDR", "U_TGT")))
	phase.queue_free()

	print("   eligibility: bodyguard 12.5\" away, leader 10\" away -> eligible to declare (11.02)")
	var far_tgt := Vector2(1500.0, 600.0)
	var l2 := far_tgt - Vector2(_gap_px(10.0), 0.0)
	var b2 := l2 - Vector2(_gap_px(1.24), 0.0)
	var units2 := {
		"U_CHG": _unit("U_CHG", 2, [b2]),
		"U_LDR": _unit("U_LDR", 2, [l2], ["INFANTRY", "CHARACTER"]),
		"U_TGT": _unit("U_TGT", 1, [far_tgt]),
	}
	units2.U_CHG.attachment_data = {"attached_characters": ["U_LDR"]}
	units2.U_LDR.attached_to = "U_CHG"
	_set_state(units2)
	_check("fixture: bodyguard beyond 12\"", _edge("U_CHG", "U_TGT") > 12.0, str(_edge("U_CHG", "U_TGT")))
	_check("eligible(): within 12\" of an enemy through the attached leader",
		chg.eligible("U_CHG", root.get_node("GameState").state).eligible,
		str(chg.eligible("U_CHG", root.get_node("GameState").state)))

# ── review fix: the leader also counts AFTER the roll and for the 12" checks ──

# Leader 6.5" from the target, bodyguard 9.26" (same geometry as
# _test_attached_leader_in_front).
func _leader_front_units() -> Dictionary:
	var tgt := Vector2(1500.0, 1200.0)
	var ldr_pos := tgt - Vector2(_gap_px(6.5), 0.0)
	var bg_pos := ldr_pos - Vector2(_gap_px(1.5), 0.0)
	var units := {
		"U_CHG": _unit("U_CHG", 2, [bg_pos]),
		"U_LDR": _unit("U_LDR", 2, [ldr_pos], ["INFANTRY", "CHARACTER"]),
		"U_TGT": _unit("U_TGT", 1, [tgt]),
	}
	units.U_CHG.attachment_data = {"attached_characters": ["U_LDR"]}
	units.U_LDR.attached_to = "U_CHG"
	return units

func _pos(unit_id: String) -> Vector2:
	var p = root.get_node("GameState").state.units[unit_id].models[0].position
	return Vector2(p.x, p.y)

func _test_attached_leader_declared_before_roll() -> void:
	print("\n-- attached leader in front, target DECLARED before the roll (the UI path): the post-roll check counts the leader (11.04 / 19.01) --")
	# The UI always declares targets before the roll (ChargeController's Declare
	# button needs a selected target), so _is_charge_roll_sufficient and
	# _per_target_charge_requirements run. They used to loop the bodyguard's
	# models only: the target was selectable through the leader and kept, then
	# the charge FAILED with a false "terrain" explanation.
	_set_state(_leader_front_units())
	var phase = _new_phase()
	var res := _declare_and_roll(phase, ["U_TGT"], 7)
	var roll: Dictionary = res.get("roll", {})
	_check("declare [U_TGT] (bodyguard 9.26\", leader 6.5\") accepted", res.declare.get("success", false), str(res.declare))
	_check("roll 7: charge does NOT fail (the leader can end engaged)", roll.get("charge_failed", true) == false, str(roll))
	_check("roll 7: pending charge kept, target kept",
		phase.has_pending_charge("U_CHG") and phase.get_pending_charges().get("U_CHG", {}).get("targets", []) == ["U_TGT"],
		str(phase.get_pending_charges().get("U_CHG", {})))
	_check("roll 7: no failure recorded (no false 'terrain' explanation)", phase.get_failed_charge_attempts().is_empty(),
		str(phase.get_failed_charge_attempts()))
	_check("roll 7: _is_charge_roll_sufficient sees the leader", phase._is_charge_roll_sufficient("U_CHG", 7))
	var per: Dictionary = phase._per_target_charge_requirements("U_CHG", ["U_TGT"], 7.0).get("U_TGT", {})
	_check("per-target: reachable, cost measured from the leader (6.5 - 2\" ER = 4.5\")",
		per.get("reachable", false) and absf(float(per.get("cost", INF)) - 4.5) < 0.01, str(per))
	var l0 := _pos("U_LDR")
	var b0 := _pos("U_CHG")
	var l_end := l0 + Vector2(6.45 * PX_PER_INCH, 0.0)
	var b_end := b0 + Vector2(6.45 * PX_PER_INCH, 0.0)
	var mv = phase.execute_action({"type": "APPLY_CHARGE_MOVE", "actor_unit_id": "U_CHG",
		"payload": {"target_unit_ids": ["U_TGT"], "per_model_rotations": {},
			"per_model_paths": {
				"m1": [[b0.x, b0.y], [b_end.x, b_end.y]],
				"U_LDR:m1": [[l0.x, l0.y], [l_end.x, l_end.y]]}}})
	_check("declared led charge: APPLY_CHARGE_MOVE succeeds", mv.get("success", false), str(mv.get("errors", mv.get("error", ""))))
	_check("declared led charge: leader ends engaged (0.05\")", absf(_edge("U_LDR", "U_TGT") - 0.05) < 0.01, str(_edge("U_LDR", "U_TGT")))
	phase.queue_free()

	# Same board, roll 6: the leader is 6.5" away, beyond the roll -> FAILS with
	# the 'beyond the roll' wording (not the terrain one).
	_set_state(_leader_front_units())
	phase = _new_phase()
	roll = _declare_and_roll(phase, ["U_TGT"], 6).get("roll", {})
	_check("roll 6 vs the leader's 6.5\": FAILS", roll.get("charge_failed", false) == true, str(roll))
	var attempts: Array = phase.get_failed_charge_attempts()
	var det := str(attempts[0].get("errors", [""])[0]) if attempts.size() > 0 else ""
	_check("roll 6: failure says the nearest target (6.5\", from the leader) is beyond the roll",
		"Rolled 6\" but the nearest charge target is 6.5\" away" in det and not "terrain" in det, det)
	phase.queue_free()

func _test_attached_leader_12in_checks() -> void:
	print("\n-- attached leader 10\" away, bodyguard 12.5\": every pre-roll 12\" check counts the leader (11.04 / 19.01) --")
	var far_tgt := Vector2(1500.0, 600.0)
	var l2 := far_tgt - Vector2(_gap_px(10.0), 0.0)
	var b2 := l2 - Vector2(_gap_px(1.24), 0.0)
	var mk := func():
		var u := {
			"U_CHG": _unit("U_CHG", 2, [b2]),
			"U_LDR": _unit("U_LDR", 2, [l2], ["INFANTRY", "CHARACTER"]),
			"U_TGT": _unit("U_TGT", 1, [far_tgt]),
		}
		u.U_CHG.attachment_data = {"attached_characters": ["U_LDR"]}
		u.U_LDR.attached_to = "U_CHG"
		return u
	_set_state(mk.call())
	_check("fixture: bodyguard beyond 12\", leader 10\"", _edge("U_CHG", "U_TGT") > 12.0 and absf(_edge("U_LDR", "U_TGT") - 10.0) < 0.005,
		"bg=%.3f ldr=%.3f" % [_edge("U_CHG", "U_TGT"), _edge("U_LDR", "U_TGT")])
	var rules = root.get_node("RulesEngine")
	var board = root.get_node("GameState").state
	var ui_list: Dictionary = rules.charge_targets_within_12("U_CHG", board)
	_check("RulesEngine.charge_targets_within_12 (the UI target list + unit filter) lists the target", ui_list.keys() == ["U_TGT"], str(ui_list))
	_check("its distance is measured from the leader (10.0\")", absf(float(ui_list.get("U_TGT", {}).get("distance", 0.0)) - 10.0) < 0.01, str(ui_list))
	_check("charge_target_ineligibility_reason agrees (\"\")", rules.charge_target_ineligibility_reason("U_CHG", "U_TGT", board) == "",
		rules.charge_target_ineligibility_reason("U_CHG", "U_TGT", board))
	_check("RulesEngine.charge_unit_models: bodyguard + leader models", rules.charge_unit_models("U_CHG", board).size() == 2)
	_check("the shared _get_min_distance_to_target_rules (shooting: Lone Operative, Psychic Veil) is NOT changed — bodyguard only",
		rules._get_min_distance_to_target_rules("U_CHG", "U_TGT", board) > 12.0, str(rules._get_min_distance_to_target_rules("U_CHG", "U_TGT", board)))
	var phase = _new_phase()
	var el: Dictionary = phase._get_eligible_targets_for_unit("U_CHG")
	_check("phase _get_eligible_targets_for_unit lists the target at 10.0\"",
		el.has("U_TGT") and absf(float(el.U_TGT.get("distance", 0.0)) - 10.0) < 0.01, str(el))
	var d = phase.execute_action({"type": "DECLARE_CHARGE", "actor_unit_id": "U_CHG", "payload": {"target_unit_ids": ["U_TGT"]}})
	_check("DECLARE_CHARGE [U_TGT] accepted (was 'Target beyond 12\" charge range')", d.get("success", false), str(d.get("errors", d.get("error", ""))))
	phase.queue_free()

	print("   10e unchanged: the bodyguard's own models only")
	GameConstants.edition = 10
	_set_state(mk.call())
	board = root.get_node("GameState").state
	_check("10e: charge_unit_models is the unit's own models", rules.charge_unit_models("U_CHG", board).size() == 1)
	_check("10e: charge_targets_within_12 still measures the bodyguard (target 12.5\" away not listed)",
		rules.charge_targets_within_12("U_CHG", board).is_empty(), str(rules.charge_targets_within_12("U_CHG", board)))
	GameConstants.edition = 11

func _test_client_failure_text_split() -> void:
	print("\n-- ChargeController._on_dice_rolled (the MP client's primary handler): 11e failure text mirrors the phase's split --")
	# load() at run time (not the class_name): this script compiles before the
	# autoloads exist, so the global class reference is not usable here.
	var cc = load("res://scripts/ChargeController.gd").new()
	cc.charge_info_label = Label.new()
	cc.dice_log_display = RichTextLabel.new()
	var base := {"context": "charge_roll", "unit_id": "U_CHG", "unit_name": "Charger", "rolls": [3, 4], "total": 7,
		"targets": ["U_TGT"], "charge_failed": true}
	# 6.5" on a 7: within the roll -> the "no model can reach engagement range" wording
	for md in [6.4999969, 7.01]:
		var dd: Dictionary = base.duplicate()
		dd["min_distance"] = md
		cc.dice_log_display.clear()
		cc._on_dice_rolled(dd)
		var info: String = cc.charge_info_label.text
		var log_txt: String = cc.dice_log_display.get_parsed_text()
		_check("min %.2f\" on a 7: info label says within the roll but no model can reach ER" % md,
			"within the roll, but no model can reach" in info and not "must be within" in info, info)
		_check("min %.2f\" on a 7: dice log says the same (no 'must be within the charge roll')" % md,
			"no model can reach" in log_txt and not "must be within the charge roll" in log_txt, log_txt)
	var dd2: Dictionary = base.duplicate()
	dd2["min_distance"] = 7.1
	cc.dice_log_display.clear()
	cc._on_dice_rolled(dd2)
	_check("min 7.1\" on a 7: info label keeps the 'must be within the roll' wording",
		"a charge target must be within the roll" in cc.charge_info_label.text, cc.charge_info_label.text)
	_check("min 7.1\" on a 7: dice log keeps the 11.04 'within the charge roll' wording",
		"must be within the charge roll (11.04)" in cc.dice_log_display.get_parsed_text(), cc.dice_log_display.get_parsed_text())
	cc.charge_info_label.free()
	cc.dice_log_display.free()
	cc.free()

func _test_min_roll_float_boundary() -> void:
	print("\n-- a target at an exact whole inch measures a hair over it: the UI 'Min roll', the AI odds and the phase agree --")
	# Two 32mm bases 7.0" apart along a 0.3 rad diagonal measure 7.0000015":
	# the phase accepts it on a 7 (<= roll + 0.02"), a bare ceil asked for 8.
	var gap := _gap_px(7.0)
	var tgt := ORIGIN + Vector2(cos(0.3), sin(0.3)) * gap
	var units := {"U_CHG": _unit("U_CHG", 2, [ORIGIN]), "U_TGT": _unit("U_TGT", 1, [tgt])}
	_set_state(units)
	var d := _edge("U_CHG", "U_TGT")
	_check("fixture: measured edge distance is a hair over 7.0\" (float drift)", d > 7.0 and d < 7.001, "%.7f" % d)
	var phase = _new_phase()
	var roll: Dictionary = _declare_and_roll(phase, ["U_TGT"], 7).get("roll", {})
	_check("phase: a 7 is accepted against it", roll.get("charge_failed", true) == false, str(roll))
	phase.queue_free()
	# The real controller -> preview path (ChargeController builds the
	# trajectories, ChargeTrajectoryPreview draws 'Min roll: N'). The
	# controller stays out of the tree (its _ready builds the HUD), so its
	# terrain-penalty lookup logs "Can't use get_node() with absolute paths"
	# and treats the board as open ground — the boards here have no terrain.
	var cc = load("res://scripts/ChargeController.gd").new()
	var preview = load("res://scripts/ChargeTrajectoryPreview.gd").new()
	cc.charge_trajectory_preview = preview
	cc.active_unit_id = "U_CHG"
	cc.selected_targets = ["U_TGT"]
	cc._update_charge_trajectory_preview(root.get_node("GameState").get_unit("U_CHG"), ORIGIN)
	_check("preview: min charge needed is the raw distance at 11e", absf(preview._min_charge_needed - d) < 0.001, str(preview._min_charge_needed))
	_check("preview: 'Min roll' asks for 7 (was ceil(7.0000015) = 8)", preview.min_roll_needed() == 7, str(preview.min_roll_needed()))
	_check("AI: odds for it are P(2D6 >= 7) = 21/36 (was 15/36)",
		is_equal_approx(AIDecisionMaker._charge_success_probability(AIDecisionMaker._charge_roll_needed(d)), 21.0 / 36.0),
		str(AIDecisionMaker._charge_success_probability(AIDecisionMaker._charge_roll_needed(d))))
	# Just beyond the tolerance (7.03") still needs an 8 everywhere.
	preview.update_trajectories([{"from": ORIGIN, "to": tgt, "distance_inches": 7.03}], 7.03, ORIGIN)
	_check("preview: 7.03\" still asks for 8", preview.min_roll_needed() == 8, str(preview.min_roll_needed()))
	_check("AI: 7.03\" odds are P(2D6 >= 8) = 15/36",
		is_equal_approx(AIDecisionMaker._charge_success_probability(AIDecisionMaker._charge_roll_needed(7.03)), 15.0 / 36.0))
	# Attached leader in front: the preview measures from him too (19.01).
	_set_state(_leader_front_units())
	cc.active_unit_id = "U_CHG"
	cc.selected_targets = ["U_TGT"]
	cc._update_charge_trajectory_preview(root.get_node("GameState").get_unit("U_CHG"), _pos("U_CHG"))
	_check("preview (leader in front): min charge needed is the leader's 6.5\", not the bodyguard's 9.26\"",
		absf(preview._min_charge_needed - 6.5) < 0.01, str(preview._min_charge_needed))
	_check("preview (leader in front): 'Min roll: 7'", preview.min_roll_needed() == 7, str(preview.min_roll_needed()))
	# 10e unchanged (bare ceil).
	GameConstants.edition = 10
	preview.update_trajectories([{"from": ORIGIN, "to": tgt, "distance_inches": d}], d, ORIGIN)
	_check("10e unchanged: preview min roll is the bare ceil", preview.min_roll_needed() == ceili(d), str(preview.min_roll_needed()))
	GameConstants.edition = 11
	preview.free()
	cc.free()

# ── 15.11 Heroic Intervention: targets must be within the maximum distance ──

func _hi_phase(units: Dictionary) -> Node:
	_set_state(units, 3)
	root.get_node("GameState").state.meta.active_player = 2
	# Each case is a fresh phase: clear the once-per-phase stratagem record.
	root.get_node("StratagemManager")._usage_history = {"1": [], "2": []}
	var phase = _new_phase()
	phase.awaiting_heroic_intervention = true
	phase.heroic_intervention_player = 1
	return phase

func _use_hi(phase: Node, unit_id: String, mode: String, total: int) -> Dictionary:
	return phase._process_use_heroic_intervention({"type": "USE_HEROIC_INTERVENTION", "unit_id": unit_id, "player": 1,
		"mode": mode, "payload": {"rng_seed": _seed_by_total[total]}})

func _test_heroic_intervention_within_roll() -> void:
	print("\n-- 15.11: Heroic Intervention targets must be within the maximum distance (the roll) --")
	# P1 defender U_HI, P2 enemy U_EN (charged this turn) 2.5" away.
	var hi_pos := Vector2(700.0, 600.0)
	var en_pos := hi_pos + Vector2(_gap_px(2.5), 0.0)
	var mk := func():
		var u := {"U_HI": _unit("U_HI", 1, [hi_pos]), "U_EN": _unit("U_EN", 2, [en_pos])}
		u.U_EN.flags["charged_this_turn"] = true
		return u
	var phase = _hi_phase(mk.call())
	var r: Dictionary = _use_hi(phase, "U_HI", "into_the_fray", 2)
	_check("Into the Fray, roll 2 vs 2.5\": FAILS (old cost check 0.5\" <= 2 let it through)",
		r.get("heroic_intervention_failed", false) == true, str(r))
	phase.queue_free()
	phase = _hi_phase(mk.call())
	r = _use_hi(phase, "U_HI", "into_the_fray", 3)
	_check("Into the Fray, roll 3 vs 2.5\": succeeds", r.get("heroic_intervention_roll_success", false) == true, str(r))
	phase.queue_free()

	# Leap to Defend from an Attached unit: leader 4.5" from the charger,
	# bodyguard 6.1" — the whole HI group counts (19.01).
	var en2 := Vector2(1400.0, 600.0)
	var ldr := en2 - Vector2(_gap_px(4.5), 0.0)
	var bg := ldr - Vector2(_gap_px(0.34), 0.0)
	var mk2 := func():
		var u := {
			"U_HI": _unit("U_HI", 1, [bg]),
			"U_HI_LDR": _unit("U_HI_LDR", 1, [ldr], ["INFANTRY", "CHARACTER"]),
			"U_EN": _unit("U_EN", 2, [en2]),
		}
		u.U_HI.attachment_data = {"attached_characters": ["U_HI_LDR"]}
		u.U_HI_LDR.attached_to = "U_HI"
		u.U_EN.flags["charged_this_turn"] = true
		return u
	phase = _hi_phase(mk2.call())
	r = _use_hi(phase, "U_HI", "leap_to_defend", 5)
	_check("Leap to Defend, roll 5: target 4.5\" from the attached leader is within the roll -> succeeds",
		r.get("heroic_intervention_roll_success", false) == true, str(r))
	phase.queue_free()
	phase = _hi_phase(mk2.call())
	r = _use_hi(phase, "U_HI", "leap_to_defend", 4)
	_check("Leap to Defend, roll 4 vs 4.5\": FAILS (old cost check 2.5\" <= 4 let it through)",
		r.get("heroic_intervention_failed", false) == true, str(r))
	phase.queue_free()

# ── AI parity ───────────────────────────────────────────────────────────

func _test_ai_roll_needed() -> void:
	print("\n-- AI: _charge_roll_needed (11e: max(edge, move); 10e: edge - ER + terrain) --")
	GameConstants.edition = 11
	# Values are the roll needed less the phase's 0.02" "within" tolerance
	# (ChargeMove11e.WITHIN_TOLERANCE_INCHES) — see _test_min_roll_float_boundary.
	_check("11e: 7.5\" target needs 7.5 (less the 0.02\" tolerance)", is_equal_approx(AIDecisionMaker._charge_roll_needed(7.5), 7.48),
		str(AIDecisionMaker._charge_roll_needed(7.5)))
	_check("11e: 3.0\" target behind 2.5\" of terrain needs 3.5 (move cost binds; less the tolerance)",
		is_equal_approx(AIDecisionMaker._charge_roll_needed(3.0, 2.5), 3.48), str(AIDecisionMaker._charge_roll_needed(3.0, 2.5)))
	_check("11e: odds for a 7.5\" target are P(2D6 >= 8) = 15/36",
		is_equal_approx(AIDecisionMaker._charge_success_probability(AIDecisionMaker._charge_roll_needed(7.5)), 15.0 / 36.0))
	GameConstants.edition = 10
	_check("10e unchanged: 7.5\" target needs 6.5 (7.5 - 1\" ER)", is_equal_approx(AIDecisionMaker._charge_roll_needed(7.5), 6.5),
		str(AIDecisionMaker._charge_roll_needed(7.5)))
	_check("10e unchanged: terrain adds on top (3.0, 2.5) -> 4.5", is_equal_approx(AIDecisionMaker._charge_roll_needed(3.0, 2.5), 4.5))
	GameConstants.edition = 11

func _test_ai_command_reroll_uses_edge_distance() -> void:
	print("\n-- AI Command Re-roll at 11e: a 7 vs a 7.5\" target is re-rolled (needs 8, not 6) --")
	_set_state(_pair(7.5), 3)
	var pm = root.get_node("PhaseManager")
	var ai = root.get_node("AIPlayer")
	pm.transition_to_phase(GameStateData.Phase.CHARGE)
	var phase = pm.get_current_phase_instance()
	var captured := {}
	phase.command_reroll_opportunity.connect(func(_uid, _p, ctx): captured.merge(ctx, true))
	var d = phase.execute_action({"type": "DECLARE_CHARGE", "actor_unit_id": "U_CHG", "payload": {"target_unit_ids": ["U_TGT"]}})
	var r = phase.execute_action({"type": "CHARGE_ROLL", "actor_unit_id": "U_CHG", "payload": {"rng_seed": _seed_by_total[7]}})
	_check("Command Re-roll window opened for the 7", r.get("awaiting_reroll", false) == true and not captured.is_empty(),
		"declare=%s roll=%s" % [str(d.get("success")), str(r)])
	if captured.is_empty():
		return
	_check("re-roll context text states the 11.04 rule", "within the charge roll" in str(captured.get("context_text", "")),
		str(captured.get("context_text", "")))
	var prev_enabled = ai.enabled
	var prev_players = ai.ai_players.duplicate()
	var log_size: int = ai._action_log.size()
	ai.ai_players = {2: true}
	ai.enabled = true
	ai._on_command_reroll_opportunity("U_CHG", 2, captured)
	await process_frame
	await process_frame
	ai.enabled = prev_enabled
	ai.ai_players = prev_players
	var decided := ""
	if ai._action_log.size() > log_size:
		decided = str(ai._action_log[-1].get("action_type", ""))
	_check("AI uses the Command Re-roll (the 7 cannot select a 7.5\" target)", decided == "USE_COMMAND_REROLL", "decided=%s" % decided)

# ── 10e sensitivity: the edition-10 path is unchanged ────────────────────

func _test_10e_unchanged() -> void:
	print("\n-- 10e unchanged: declared 7.5\" target on a 7 succeeds (cost 6.5\"); 8.9\" fails (7.9\") --")
	GameConstants.edition = 10
	_set_state(_pair(7.5))
	var phase = _new_phase()
	var roll: Dictionary = _declare_and_roll(phase, ["U_TGT"], 7).get("roll", {})
	_check("10e: 7 vs 7.5\" succeeds", roll.get("charge_failed", true) == false, str(roll))
	_check("10e: CHARGE_ROLL result has no 11e selectable list", not roll.has("selectable_targets"), str(roll))
	phase.queue_free()
	_set_state(_pair(8.9))
	phase = _new_phase()
	roll = _declare_and_roll(phase, ["U_TGT"], 7).get("roll", {})
	_check("10e: 7 vs 8.9\" fails", roll.get("charge_failed", false) == true, str(roll))
	var attempts: Array = phase.get_failed_charge_attempts()
	var detail := str(attempts[0].get("errors", [""])[0]) if attempts.size() > 0 else ""
	_check("10e: failure text keeps the engagement-range wording", "engagement range" in detail, detail)
	phase.queue_free()
	GameConstants.edition = 11
