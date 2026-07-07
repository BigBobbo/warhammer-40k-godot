extends SceneTree

# Charge-phase bug-fix regression suite (charge-phase-bugs branch).
# Pins the fixes for:
#   1. False INSUFFICIENT_ROLL: the pre-roll feasibility check penalized the
#      full straight centre-to-centre line — a 6" roll vs a target 2.5" away
#      behind a ruin corner was declared failed. Now the model stops at
#      engagement range and may angle around terrain (ring sampling that
#      mirrors the 2-point paths the drag UI / AI actually submit).
#   2. TerrainManager: a segment wholly inside one footprint (no wall crossed)
#      paid a phantom climb penalty.
#   3. 11e selectable_targets recomputed from the FINAL total (after Command
#      Re-roll / +N bonuses), not the raw first 2D6.
#   4. Double CHARGE_ROLL / re-DECLARE after a roll are rejected.
#   5. USE_FIRE_OVERWATCH accepts actor_unit_id (human dialog format).
#   6. _validate_base_to_base_possible judges friend/foe from the CHARGING
#      unit's owner (Heroic Intervention correctness).
#   7. Unit coherency for charges includes UNMOVED models.
#   8. Non-target ER check skips Reserves units (they read as (0,0)).
#
# Usage: godot --headless --path . -s tests/test_charge_phase_fixes.gd

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
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.2).timeout.connect(_run_tests)

func _make_unit(id: String, owner: int, keywords: Array, positions: Array, base_mm: int = 32) -> Dictionary:
	var models = []
	for i in range(positions.size()):
		var pos = positions[i]
		models.append({
			"id": "m%d" % (i + 1),
			"alive": true,
			"current_wounds": 4,
			"wounds": 4,
			"base_mm": base_mm,
			"base_type": "circular",
			"position": ({"x": pos.x, "y": pos.y} if pos != null else null),
		})
	return {
		"id": id, "squad_id": id, "owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"flags": {},
		"meta": {"name": id, "keywords": keywords, "stats": {"move": 6, "toughness": 4, "save": 4, "wounds": 4}},
		"models": models,
		"embarked_in": null,
	}

func _tall_ruin(id: String, x0: float, y0: float, x1: float, y1: float) -> Dictionary:
	return {
		"id": id, "type": "ruins",
		"polygon": PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]),
		"height_category": "tall",
		"position": Vector2((x0 + x1) / 2.0, (y0 + y1) / 2.0),
		"size": Vector2(x1 - x0, y1 - y0), "rotation": 0.0,
		"can_move_through": {"INFANTRY": true, "VEHICLE": false, "MONSTER": false},
	}

func _setup_state(units: Dictionary, active_player: int = 2) -> void:
	var gs = root.get_node("GameState")
	gs.state = {
		"meta": {"phase": GameStateData.Phase.CHARGE, "active_player": active_player, "battle_round": 1, "turn_number": 1, "game_id": "test"},
		"units": units,
		"players": {"1": {"cp": 0, "vp": 0}, "2": {"cp": 0, "vp": 0}},
		"board": {"terrain": []},
		"phase_log": [],
	}

func _new_phase() -> Node:
	var phase = load("res://phases/ChargePhase.gd").new()
	root.add_child(phase)
	phase._on_phase_enter()
	return phase

func _tm() -> Node:
	return root.get_node("TerrainManager")

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_charge_phase_fixes ===")
	var prev_edition = GameConstants.edition

	_test_feasibility_around_ruin_corner()
	_test_feasibility_stops_at_er()
	_test_feasibility_genuinely_blocked()
	_test_wholly_inside_no_penalty()
	_test_11e_selectable_recomputed_after_reroll()
	_test_roll_and_declare_guards()
	_test_fire_overwatch_actor_unit_id()
	_test_b2b_owner_perspective()
	_test_coherency_includes_unmoved()
	_test_reserves_not_at_origin()

	GameConstants.edition = prev_edition
	print("\n=== %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)

# -- 1a. The reported bug: roll 6, target ~2.5" away, tall ruin corner clips the line --
func _test_feasibility_around_ruin_corner() -> void:
	print("\n-- feasibility: path around a ruin corner (reported bug) --")
	GameConstants.edition = 11
	# Rect-based charger like the live repro (Battlewagon geometry): edge gap 2.49"
	var charger = _make_unit("U_CHG", 2, ["VEHICLE"], [Vector2(700, 2150)])
	charger.models[0]["base_type"] = "rectangular"
	charger.models[0]["base_mm"] = 180
	charger.models[0]["base_dimensions"] = {"length": 180, "width": 110}
	charger.models[0]["rotation"] = 0.0
	var target = _make_unit("U_TGT", 1, ["INFANTRY"], [Vector2(973, 2150)], 40)
	_setup_state({"U_CHG": charger, "U_TGT": target})
	_tm().terrain_features.clear()
	_tm().terrain_features.append(_tall_ruin("corner_ruin", 900, 2060, 940, 2155))

	var phase = _new_phase()
	phase.pending_charges["U_CHG"] = {"targets": ["U_TGT"], "declared_targets": ["U_TGT"]}
	var straight_penalty = _tm().calculate_charge_terrain_penalty(Vector2(700, 2150), Vector2(973, 2150), false, ["VEHICLE"])
	_check("straight line pays the climb penalty (12\")", straight_penalty >= 12.0, "penalty=%.1f" % straight_penalty)
	_check("roll of 6 IS sufficient (stops at ER / angles around)", phase._is_charge_roll_sufficient("U_CHG", 6))
	_check("roll of 2 IS sufficient (only ~0.5\" needed)", phase._is_charge_roll_sufficient("U_CHG", 2))

	# FLY charger (the user's Vertus Praetors case) — same geometry
	var gs = root.get_node("GameState")
	gs.state.units["U_CHG"].meta.keywords = ["MOUNTED", "FLY"]
	_check("FLY charger: roll of 6 sufficient", phase._is_charge_roll_sufficient("U_CHG", 6))
	phase.queue_free()
	_tm().terrain_features.clear()

# -- 1b. Penalty only accrues on the travelled portion of the line --
func _test_feasibility_stops_at_er() -> void:
	print("\n-- feasibility: model stops at engagement range before the terrain --")
	GameConstants.edition = 11
	# 32mm charger 5.6" (edge) from target; ruin sits BEHIND the stop point.
	var charger = _make_unit("U_CHG", 2, ["VEHICLE"], [Vector2(700, 2150)])
	var target = _make_unit("U_TGT", 1, ["INFANTRY"], [Vector2(973, 2150)])
	_setup_state({"U_CHG": charger, "U_TGT": target})
	_tm().terrain_features.clear()
	# Ruin hugging the target: straight full line crosses it, travelled part does not
	_tm().terrain_features.append(_tall_ruin("behind_stop", 930, 2060, 960, 2250))

	var phase = _new_phase()
	phase.pending_charges["U_CHG"] = {"targets": ["U_TGT"], "declared_targets": ["U_TGT"]}
	var full_line_penalty = _tm().calculate_charge_terrain_penalty(Vector2(700, 2150), Vector2(973, 2150), false, ["VEHICLE"])
	_check("full line would pay a penalty", full_line_penalty > 0.0, "penalty=%.1f" % full_line_penalty)
	_check("roll of 6 sufficient (stop point is before the ruin)", phase._is_charge_roll_sufficient("U_CHG", 6))
	phase.queue_free()
	_tm().terrain_features.clear()

# -- 1c. A genuinely blocked charge still fails; INFANTRY passes freely --
func _test_feasibility_genuinely_blocked() -> void:
	print("\n-- feasibility: genuinely blocked stays infeasible --")
	GameConstants.edition = 11
	var charger = _make_unit("U_CHG", 2, ["VEHICLE"], [Vector2(700, 2150)])
	var target = _make_unit("U_TGT", 1, ["INFANTRY"], [Vector2(973, 2150)])
	_setup_state({"U_CHG": charger, "U_TGT": target})
	_tm().terrain_features.clear()
	# A 20"-long tall wall between them: every reachable final position's
	# straight drag line crosses it -> 12" climb applies on every candidate.
	_tm().terrain_features.append(_tall_ruin("long_wall", 800, 1750, 840, 2550))

	var phase = _new_phase()
	phase.pending_charges["U_CHG"] = {"targets": ["U_TGT"], "declared_targets": ["U_TGT"]}
	_check("VEHICLE roll 6 infeasible over 6\"-tall wall", not phase._is_charge_roll_sufficient("U_CHG", 6))
	_check("VEHICLE roll 12 still infeasible (needed + 12\" climb > 12)", not phase._is_charge_roll_sufficient("U_CHG", 12))
	var gs = root.get_node("GameState")
	gs.state.units["U_CHG"].meta.keywords = ["INFANTRY"]
	_check("INFANTRY same geometry: roll 6 sufficient (walks through)", phase._is_charge_roll_sufficient("U_CHG", 6))
	# Too-far case, no terrain involved at all
	_tm().terrain_features.clear()
	gs.state.units["U_TGT"].models[0].position = {"x": 700.0 + 8.0 * 40.0 + 50.4, "y": 2150.0}
	_check("8\" away with roll 2: infeasible", not phase._is_charge_roll_sufficient("U_CHG", 2))
	phase.queue_free()

# -- 2. Wholly-inside segment pays no climb --
func _test_wholly_inside_no_penalty() -> void:
	print("\n-- TerrainManager: segment wholly inside one footprint --")
	_tm().terrain_features.clear()
	_tm().terrain_features.append(_tall_ruin("big_ruin", 400, 400, 1200, 1200))
	var pen_vehicle = _tm().calculate_charge_terrain_penalty(Vector2(500, 800), Vector2(1100, 800), false, ["VEHICLE"])
	var pen_fly = _tm().calculate_charge_terrain_penalty(Vector2(500, 800), Vector2(1100, 800), true, ["FLY"])
	_check("ground-floor move inside a ruin: no climb (non-FLY)", pen_vehicle == 0.0, "penalty=%.2f" % pen_vehicle)
	_check("ground-floor move inside a ruin: no climb (FLY)", pen_fly == 0.0, "penalty=%.2f" % pen_fly)
	var pen_crossing = _tm().calculate_charge_terrain_penalty(Vector2(300, 800), Vector2(1100, 800), false, ["VEHICLE"])
	_check("crossing INTO the ruin still pays the climb", pen_crossing > 0.0, "penalty=%.2f" % pen_crossing)
	# difficult_ground trait must keep applying — including wholly inside
	_tm().terrain_features[0]["traits"] = ["difficult_ground"]
	var pen_dg_inside = _tm().calculate_charge_terrain_penalty(Vector2(500, 800), Vector2(1100, 800), false, ["VEHICLE"])
	_check("difficult ground still applies wholly inside", pen_dg_inside == 2.0, "penalty=%.2f" % pen_dg_inside)
	# On LOW terrain (no climb component) the trait is the whole penalty:
	# non-FLY pays exactly 2", FLY ignores it entirely.
	_tm().terrain_features[0]["height_category"] = "low"
	var pen_dg_low = _tm().calculate_charge_terrain_penalty(Vector2(300, 800), Vector2(1100, 800), false, ["VEHICLE"])
	_check("difficult ground costs 2\" crossing low terrain", pen_dg_low == 2.0, "penalty=%.2f" % pen_dg_low)
	var pen_dg_fly = _tm().calculate_charge_terrain_penalty(Vector2(300, 800), Vector2(1100, 800), true, ["FLY"])
	_check("FLY ignores difficult ground", pen_dg_fly == 0.0, "penalty=%.2f" % pen_dg_fly)
	_tm().terrain_features.clear()

# -- 3. 11e selectable recomputed after Command Re-roll --
func _test_11e_selectable_recomputed_after_reroll() -> void:
	print("\n-- 11e: selectable targets recomputed from the re-rolled total --")
	GameConstants.edition = 11
	# Target 7" (edge) away: raw roll of 2 reaches nothing; re-roll of 9 does.
	var charger = _make_unit("U_CHG", 2, ["INFANTRY"], [Vector2(400, 400)])
	var target = _make_unit("U_TGT", 1, ["INFANTRY"], [Vector2(400 + 7.0 * 40.0 + 50.4, 400)])
	_setup_state({"U_CHG": charger, "U_TGT": target})
	root.get_node("GameState").state.players["2"]["cp"] = 1
	_tm().terrain_features.clear()

	var phase = _new_phase()
	var r1 = phase.execute_action({"type": "DECLARE_CHARGE", "actor_unit_id": "U_CHG", "payload": {"target_unit_ids": []}})
	_check("11e declare with no targets ok", r1.get("success", false), str(r1.get("errors", [])))
	# seed 3 -> [1,1] = 2 (verified against RNGService)
	var r2 = phase.execute_action({"type": "CHARGE_ROLL", "actor_unit_id": "U_CHG", "payload": {"rng_seed": 3}})
	_check("roll of 2 pauses for Command Re-roll", phase.awaiting_reroll_decision, str(r2))
	# seed 2 -> [5,4] = 9
	var r3 = phase.execute_action({"type": "USE_COMMAND_REROLL", "actor_unit_id": "U_CHG", "payload": {"rng_seed": 2}})
	_check("re-roll action succeeded", r3.get("success", false), str(r3.get("errors", [])))
	var pend = phase.get_pending_charges().get("U_CHG", {})
	_check("re-rolled total is 9", int(pend.get("distance", 0)) == 9, "distance=%s" % str(pend.get("distance")))
	_check("selectable recomputed from re-rolled total", "U_TGT" in pend.get("selectable_targets", []),
		"selectable=%s" % str(pend.get("selectable_targets", [])))
	_check("charge did NOT fail after re-roll", phase.get_failed_charge_attempts().is_empty(),
		str(phase.get_failed_charge_attempts()))
	phase.queue_free()

# -- 4. Double-roll / re-declare guards --
func _test_roll_and_declare_guards() -> void:
	print("\n-- guards: one 2D6 per declared charge --")
	GameConstants.edition = 11
	var charger = _make_unit("U_CHG", 2, ["INFANTRY"], [Vector2(400, 400)])
	var target = _make_unit("U_TGT", 1, ["INFANTRY"], [Vector2(400 + 5.0 * 40.0 + 50.4, 400)])
	_setup_state({"U_CHG": charger, "U_TGT": target})
	_tm().terrain_features.clear()

	var phase = _new_phase()
	phase.execute_action({"type": "DECLARE_CHARGE", "actor_unit_id": "U_CHG", "payload": {"target_unit_ids": ["U_TGT"]}})
	var roll1 = phase.execute_action({"type": "CHARGE_ROLL", "actor_unit_id": "U_CHG", "payload": {"rng_seed": 2}})
	_check("first roll ok", roll1.get("success", false))
	var roll2 = phase.execute_action({"type": "CHARGE_ROLL", "actor_unit_id": "U_CHG", "payload": {"rng_seed": 23}})
	_check("second CHARGE_ROLL rejected", not roll2.get("success", true), str(roll2.get("errors", [])))
	var redeclare = phase.execute_action({"type": "DECLARE_CHARGE", "actor_unit_id": "U_CHG", "payload": {"target_unit_ids": ["U_TGT"]}})
	_check("re-DECLARE after roll rejected", not redeclare.get("success", true), str(redeclare.get("errors", [])))
	phase.queue_free()

# -- 5. Fire Overwatch accepts actor_unit_id --
func _test_fire_overwatch_actor_unit_id() -> void:
	print("\n-- Fire Overwatch: actor_unit_id accepted (human dialog format) --")
	GameConstants.edition = 10  # 11e moved Fire Overwatch to end of Movement phase
	var charger = _make_unit("U_CHG", 2, ["INFANTRY"], [Vector2(400, 400)])
	var ow_unit = _make_unit("U_OW", 1, ["INFANTRY"], [Vector2(800, 400)])
	_setup_state({"U_CHG": charger, "U_OW": ow_unit})
	root.get_node("GameState").state.players["1"]["cp"] = 1

	var phase = _new_phase()
	phase.awaiting_fire_overwatch = true
	phase.fire_overwatch_player = 1
	phase.fire_overwatch_enemy_unit_id = "U_CHG"
	phase.fire_overwatch_eligible_units = ["U_OW"]
	var v_actor = phase._validate_use_fire_overwatch({"type": "USE_FIRE_OVERWATCH", "actor_unit_id": "U_OW", "player": 1})
	_check("actor_unit_id accepted", v_actor.get("valid", false), str(v_actor.get("errors", [])))
	var v_unit = phase._validate_use_fire_overwatch({"type": "USE_FIRE_OVERWATCH", "unit_id": "U_OW", "player": 1})
	_check("unit_id (AI format) still accepted", v_unit.get("valid", false), str(v_unit.get("errors", [])))
	var v_none = phase._validate_use_fire_overwatch({"type": "USE_FIRE_OVERWATCH", "player": 1})
	_check("missing unit still rejected", not v_none.get("valid", true))
	phase.queue_free()
	GameConstants.edition = 11

# -- 6. B2B constraint judged from the charging unit's owner --
func _test_b2b_owner_perspective() -> void:
	print("\n-- base-to-base: friend/foe from the charging unit's owner (HI) --")
	GameConstants.edition = 10  # 1" ER keeps the geometry tight
	# Heroic Intervention shape: ACTIVE player is 1, the DEFENDER (owner 2) charges.
	# U_BLOCK (owner 1, NOT a target) sits right behind the b2b spot, so making
	# base contact would enter its ER — b2b is not cleanly achievable, and the
	# 1.9"-short final position must therefore be accepted.
	var hi_charger = _make_unit("U_DEF", 2, ["INFANTRY"], [Vector2(400, 400)])
	var atk_target = _make_unit("U_ATK", 1, ["INFANTRY"], [Vector2(400 + 3.0 * 40.0 + 50.4, 400)])
	var atk_blocker = _make_unit("U_BLOCK", 1, ["INFANTRY"], [Vector2(400 + 3.0 * 40.0 + 50.4 + 60.0, 400)])
	_setup_state({"U_DEF": hi_charger, "U_ATK": atk_target, "U_BLOCK": atk_blocker}, 1)

	var phase = _new_phase()
	# Final position 0.9" short of contact: within 1" ER of target, outside ER of blocker.
	var final_x = 400.0 + (3.0 - 0.9) * 40.0
	var paths = {"m1": [[400.0, 400.0], [final_x, 400.0]]}
	var result = phase._validate_base_to_base_possible("U_DEF", paths, ["U_ATK"], 12)
	_check("no false FAIL_BASE_CONTACT for defender charge", result.get("valid", false), str(result.get("errors", [])))
	phase.queue_free()
	GameConstants.edition = 11

# -- 7. Coherency includes unmoved models --
func _test_coherency_includes_unmoved() -> void:
	print("\n-- coherency: whole unit, not just the moved subset --")
	GameConstants.edition = 11
	var unit = _make_unit("U_CHG", 2, ["INFANTRY"], [Vector2(400, 400), Vector2(440, 400)])
	var target = _make_unit("U_TGT", 1, ["INFANTRY"], [Vector2(800, 400)])
	_setup_state({"U_CHG": unit, "U_TGT": target})

	var phase = _new_phase()
	# Move ONLY m1 6" away from unmoved m2 -> unit broken
	var broken = phase._validate_unit_coherency_for_charge("U_CHG", {"m1": [[400.0, 400.0], [400.0 + 240.0, 400.0]]})
	_check("dragging one model away breaks coherency", not broken.get("valid", true))
	# Move m1 to 1.5" from unmoved m2 -> fine
	var ok = phase._validate_unit_coherency_for_charge("U_CHG", {"m1": [[400.0, 400.0], [440.0 + 60.0, 400.0]]})
	_check("moved model within 2\" of unmoved mate is coherent", ok.get("valid", false), str(ok.get("errors", [])))
	phase.queue_free()

# -- 8. Reserves units are not phantom (0,0) non-targets --
func _test_reserves_not_at_origin() -> void:
	print("\n-- non-target ER: Reserves units are skipped --")
	GameConstants.edition = 11
	var charger = _make_unit("U_CHG", 2, ["INFANTRY"], [Vector2(120, 120)])
	var target = _make_unit("U_TGT", 1, ["INFANTRY"], [Vector2(120 + 3.0 * 40.0 + 50.4, 120)])
	var reserves = _make_unit("U_RSV", 1, ["INFANTRY"], [null])
	reserves["status"] = GameStateData.UnitStatus.IN_RESERVES
	_setup_state({"U_CHG": charger, "U_TGT": target, "U_RSV": reserves})

	var phase = _new_phase()
	# Charge to base contact near the board origin — pre-fix the Reserves unit
	# "at (0,0)" produced a false non-target-ER rejection.
	var final_x = 120.0 + 3.0 * 40.0
	var result = phase._validate_engagement_range_constraints("U_CHG", {"m1": [[120.0, 120.0], [final_x, 120.0]]}, ["U_TGT"])
	_check("no phantom ER violation from a Reserves unit", result.get("valid", false), str(result.get("errors", [])))
	phase.queue_free()
