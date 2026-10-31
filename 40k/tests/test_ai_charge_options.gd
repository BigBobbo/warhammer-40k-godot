extends SceneTree

# ADV-CHG-1 / MELEE-SEEK-2 / CHG-OPT-1: the AI's Advance-and-charge reasoning.
#
# 1. ADV-CHG-1: "may charge after Advancing" is the engine's predicate (riled
#    up / effect flag), NOT ability text — the Ork Waaagh! rule text mentions
#    "advance" and "charge" whether or not the unit is riled up.
# 2. MELEE-SEEK-2: Ghazghkull (Gork's Klaw S14 D4 next to a BS5+ S6 gun) is a
#    melee seeker; Lootas / Battlewagon (benchmark: must stay on mission) are not.
# 3. charge_odds_this_turn: Move-then-2D6 and Advance-D6-then-2D6 odds from the
#    edge distance.
# 4. CHG-OPT-1: the movement planner offers "Move → charge X" always and
#    "Advance → charge X" only when the unit is riled up; a riled-up
#    Ghazghkull 16" from an enemy takes the Advance-and-charge.
#
# Run via: godot --headless --path 40k --script tests/test_ai_charge_options.gd

const PPI := 40.0
const MOVE_ALL := ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]

var passed := 0
var failed := 0


func _initialize():
	await create_timer(0.2).timeout
	_run_tests()


func _check(name: String, ok: bool, detail: String) -> void:
	if ok:
		passed += 1
		print("[PASS] %s — %s" % [name, detail])
	else:
		failed += 1
		print("[FAIL] %s — %s" % [name, detail])


func _army_unit(path: String, uid: String) -> Dictionary:
	var f = FileAccess.open(path, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d.get("units", {}).get(uid, {}).duplicate(true)


func _place(unit: Dictionary, owner: int, pos: Vector2, base_mm: int = 32) -> Dictionary:
	unit["owner"] = owner
	unit["status"] = 2
	unit["flags"] = {}
	var models = unit.get("models", [])
	if models.is_empty():
		models = [{"id": "m1", "alive": true}]
	for i in range(models.size()):
		models[i]["alive"] = true
		models[i]["position"] = {"x": pos.x + i * 45.0, "y": pos.y}
		models[i]["base_mm"] = base_mm
	unit["models"] = models
	return unit


func _guard(pos: Vector2) -> Dictionary:
	var models = []
	for i in range(3):
		models.append({"id": "m%d" % (i + 1), "alive": true, "wounds": 3, "current_wounds": 3,
			"position": {"x": pos.x + i * 45.0, "y": pos.y}, "base_mm": 40})
	return {"owner": 1, "status": 2, "flags": {}, "models": models,
		"meta": {"name": "Sentinel Guard", "points": 150, "keywords": ["INFANTRY"],
			"weapons": [], "abilities": [],
			"stats": {"move": 6, "objective_control": 2, "toughness": 6, "save": 2, "wounds": 3, "invuln": 4}}}


func _assign(snapshot: Dictionary, movable_ids: Array) -> Dictionary:
	AIDecisionMaker.reset_caches()
	AIDecisionMaker._current_player = 2
	var objectives = AIDecisionMaker._get_objectives(snapshot)
	var enemies = AIDecisionMaker._get_enemy_units(snapshot, 2)
	var friendly = AIDecisionMaker._get_units_for_player(snapshot, 2)
	var evals = AIDecisionMaker._evaluate_all_objectives(snapshot, objectives, 2, enemies, friendly, 1)
	var movable = {}
	for uid in movable_ids:
		movable[uid] = MOVE_ALL
	return AIDecisionMaker._assign_units_to_objectives(
		snapshot, movable, evals, objectives, enemies, friendly, 2, 1, [])


func _charge_cand(uid: String, mode: String) -> Dictionary:
	for c in AIDecisionMaker._last_movement_candidates.get(uid, []):
		if str(c.get("action", "")) == mode:
			return c
	return {}


func _run_tests():
	print("\n=== Advance-and-charge reasoning ===\n")
	var gs = root.get_node("GameState")
	var saved_objs = gs.state.get("board", {}).get("objectives", []).duplicate(true)
	var saved_edition = GameConstants.edition
	GameConstants.edition = 11
	gs.state["board"]["objectives"] = []

	# --- 1: ADV-CHG-1 ---
	var ghaz = _place(_army_unit("res://armies/orks.json", "U_GHAZGHKULL_THRAKA_A"), 2, Vector2(900.0, 600.0), 32)
	var text_says: bool = AIAbilityAnalyzer.unit_has_ability_containing(ghaz, "advance") \
		and AIAbilityAnalyzer.unit_has_ability_containing(ghaz, "charge")
	_check("not riled up: may NOT charge after Advancing", not AIDecisionMaker._can_advance_and_charge(ghaz),
		"engine predicate false (old text heuristic said %s)" % text_says)
	var riled = ghaz.duplicate(true)
	riled.flags["effect_advance_and_charge"] = true
	_check("riled up: may charge after Advancing", AIDecisionMaker._can_advance_and_charge(riled), "flag set")
	_check("ShouldAdvance no longer claims a free Advance-and-charge",
		AIDecisionMaker._should_unit_advance_long_trip(ghaz, true, 36.0,
			{"E": _guard(Vector2(900.0, 1100.0))}, AIDecisionMaker._get_unit_centroid(ghaz)) == false,
		"enemy 12.5\" away, unit not riled -> no long-trip Advance")

	# --- 2: MELEE-SEEK-2 ---
	var prof = AIDecisionMaker._unit_reference_output(ghaz)
	_check("Ghazghkull is a melee seeker", AIDecisionMaker._is_melee_seeker(ghaz),
		"melee %.2f vs ranged %.2f per model (ref T5 Sv3+)" % [prof.melee, prof.ranged])
	for uid in ["U_LOOTAS_A", "U_BATTLEWAGON_G"]:
		var u = _place(_army_unit("res://armies/orks.json", uid), 2, Vector2(300.0, 300.0))
		var p = AIDecisionMaker._unit_reference_output(u)
		_check("%s stays a shooter" % uid, not AIDecisionMaker._is_melee_seeker(u),
			"melee %.2f vs ranged %.2f" % [p.melee, p.ranged])
	# Report-only: every army unit whose classification the ratio flips.
	var flipped := []
	var dir = DirAccess.open("res://armies")
	for fn in dir.get_files():
		if not fn.ends_with(".json"):
			continue
		var f = FileAccess.open("res://armies/" + fn, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		if typeof(d) != TYPE_DICTIONARY:
			continue
		for uid in d.get("units", {}):
			var u = _place(d.units[uid].duplicate(true), 2, Vector2(300.0, 300.0))
			if not AIDecisionMaker._unit_has_ranged_weapons(u) or not AIDecisionMaker._is_melee_focused_unit(u):
				continue
			var p = AIDecisionMaker._unit_reference_output(u)
			if p.ranged > 0.0 and p.melee < 9999.0:
				# melee-focused only via MELEE-SEEK-2 when the old weak-gun test failed
				var strong := false
				for w in u.meta.get("weapons", []):
					if str(w.get("type", "")).to_lower() == "ranged" and not "pistol" in str(w.get("special_rules", "")).to_lower() \
							and ((int(w.get("strength", 0)) >= 5 and int(w.get("attacks", 0)) >= 2) or int(w.get("attacks", 0)) >= 4):
						strong = true
				if strong:
					flipped.append("%s/%s (%.1f vs %.1f)" % [fn.get_basename(), u.meta.get("name", uid), p.melee, p.ranged])
	print("  MELEE-SEEK-2 newly seeking: %s" % ", ".join(flipped))

	# --- 3: odds. Edge 16" (32mm bases both sides => centre gap 16" + radii). ---
	var r32 := 16.0 / 25.4 * PPI
	var r40 := 20.0 / 25.4 * PPI
	var gy := 600.0 + r32 + 16.0 * PPI + r40
	var guard = _guard(Vector2(900.0, gy))
	var odds = AIDecisionMaker.charge_odds_this_turn(ghaz, guard)
	_check("edge distance measured base to base", absf(float(odds.edge_in) - 16.0) < 0.1, "edge %.2f\"" % float(odds.edge_in))
	# Move 8 leaves 8": 2D6 >= 8 = 15/36. Advance D6 then 2D6 is far likelier.
	_check("Move-then-charge odds = P(2D6 >= 8)", absf(float(odds.p_move) - 15.0 / 36.0) < 0.01, "%.3f" % float(odds.p_move))
	_check("Advance-then-charge odds are higher", float(odds.p_advance) > 0.7 and float(odds.p_advance) > float(odds.p_move),
		"%.3f" % float(odds.p_advance))

	# --- 4: CHG-OPT-1 in the planner. One far objective so the charge competes. ---
	var objs := [{"id": "obj_home", "position": {"x": 300.0, "y": 200.0}, "zone": "player2"}]
	var s_plain = {"meta": {"battle_round": 1}, "battle_round": 1,
		"board": {"terrain_features": [], "objectives": objs},
		"units": {"U_GHAZ": ghaz.duplicate(true), "U_GUARD": guard.duplicate(true)}}
	var a_plain = _assign(s_plain, ["U_GHAZ"])
	var mv = _charge_cand("U_GHAZ", "charge_move")
	_check("not riled: Move → charge is offered, Advance → charge is not",
		not mv.is_empty() and _charge_cand("U_GHAZ", "charge_advance").is_empty(),
		"move option %.1f (%s); assignment %s" % [float(mv.get("score", 0.0)), mv.get("reason", ""),
			a_plain.get("U_GHAZ", {}).get("action", "")])

	var s_riled = s_plain.duplicate(true)
	s_riled.units["U_GHAZ"] = riled.duplicate(true)
	var a_riled = _assign(s_riled, ["U_GHAZ"])
	var adv = _charge_cand("U_GHAZ", "charge_advance")
	var ra = a_riled.get("U_GHAZ", {})
	_check("riled: Advance → charge is offered with the higher odds",
		not adv.is_empty() and float(adv.get("charge_chance", 0.0)) > float(_charge_cand("U_GHAZ", "charge_move").get("charge_chance", 1.0)),
		"advance option %.1f (%s)" % [float(adv.get("score", 0.0)), adv.get("reason", "")])
	_check("riled Ghazghkull plans Advance-and-charge",
		ra.get("action", "") == "attack" and ra.get("assign_pass", "") == "charge" and bool(ra.get("attack_advance", false))
			and ra.get("attack_target_id", "") == "U_GUARD",
		"%s/%s advance=%s target=%s — %s" % [ra.get("action", ""), ra.get("assign_pass", ""),
			str(ra.get("attack_advance", "")), ra.get("attack_target_id", ""), ra.get("reason", "")])

	gs.state["board"]["objectives"] = saved_objs
	GameConstants.edition = saved_edition
	AIDecisionMaker.reset_caches()
	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
