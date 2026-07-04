extends SceneTree

# Web-sourced 11e GDM mechanics (docs/rules/11th_edition_missions_gdm2026.md
# appendix, retrieved 2026-07-03):
#  - Heal X core ability: heal wounded model, else revive one at 1 wound.
#  - A Grievous Blow: Starting Strength 13+ criterion.
#  - Outflank: 3 VP one board edge / 5 VP two (min_edges).
#  - Beacon: friendly unit alive wholly outside own deployment zone.
#  - Forward Position: enemy home OR both Expansion objectives.
#  - Fixed secondaries: 20 VP cap per fixed card.
#  - 11e army construction validator (warlord faction, enhancement caps).
#
# Usage: godot --headless --path . -s tests/test_gdm_sourced_11e.gd

var passed := 0
var failed := 0
var gs = null
var re = null
var meas = null

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _mk_unit(owner: int, models: Array, abilities: Array = []) -> Dictionary:
	return {"id": "U_T", "owner": owner,
		"meta": {"name": "T", "keywords": ["INFANTRY"], "abilities": abilities, "stats": {}},
		"models": models}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_gdm_sourced_11e ===\n")
	gs = root.get_node_or_null("GameState")
	var sec = root.get_node_or_null("SecondaryMissionManager")
	var alm = root.get_node_or_null("ArmyListManager")
	re = root.get_node_or_null("RulesEngine")
	meas = root.get_node_or_null("Measurement")
	_check("autoloads present", gs != null and sec != null and alm != null and re != null and meas != null)

	print("-- Heal X --")
	var hu = _mk_unit(1, [
		{"id": "a", "alive": true, "wounds": 3, "current_wounds": 1},
		{"id": "b", "alive": false, "wounds": 3, "current_wounds": 0},
	], ["Heal 3"])
	_check("Heal 3 parsed from abilities", re.get_heal_amount(hu) == 3)
	var res = re.apply_heal_11e(hu, re.get_heal_amount(hu))
	_check("wounded model healed before revival", int(hu["models"][0]["current_wounds"]) == 3,
		str(hu["models"][0]))
	_check("third heal revives the dead model at 1 wound",
		res["healed"] == 2 and res["revived"] == 1 and hu["models"][1]["alive"] == true
		and int(hu["models"][1]["current_wounds"]) == 1, str(res))
	var hu2 = _mk_unit(1, [{"id": "a", "alive": true, "wounds": 2, "current_wounds": 2}], ["Heal 2"])
	var res2 = re.apply_heal_11e(hu2, 2)
	_check("full-strength unit wastes excess heals", res2["healed"] == 0 and res2["revived"] == 0, str(res2))
	_check("no Heal ability parses as 0", re.get_heal_amount(_mk_unit(1, [])) == 0)

	print("\n-- A Grievous Blow: Starting Strength 13+ --")
	GameConstants.edition = 11
	sec._units_destroyed_this_turn = [
		{"unit_id": "U_X", "owner": 2, "points": 60, "max_model_wounds": 1, "starting_strength": 20},
	]
	_check("SS 20 unit qualifies at min_models 13",
		sec._check_high_value_unit_destroyed(1, {"min_models": 13}))
	sec._units_destroyed_this_turn = [
		{"unit_id": "U_Y", "owner": 2, "points": 300, "max_model_wounds": 20, "starting_strength": 5},
	]
	_check("SS 5 unit does NOT qualify (points/wounds no longer implied)",
		not sec._check_high_value_unit_destroyed(1, {"min_models": 13}))
	sec._units_destroyed_this_turn.clear()

	print("\n-- Outflank: distinct board edges --")
	var w = meas.inches_to_px(float(gs.state.board.size.width))
	gs.state["units"]["U_EDGE_L"] = _mk_unit(1, [{"id": "m", "alive": true, "wounds": 1, "current_wounds": 1,
		"base_mm": 32, "base_type": "circular", "position": {"x": 40.0, "y": 1200.0}}])
	gs.state["units"]["U_EDGE_R"] = _mk_unit(1, [{"id": "m", "alive": true, "wounds": 1, "current_wounds": 1,
		"base_mm": 32, "base_type": "circular", "position": {"x": w - 40.0, "y": 1200.0}}])
	_check("two units on opposite edges satisfy min_edges 2",
		sec._check_units_near_board_edges(1, {"min_edges": 2, "edge_inches": 6.0}))
	gs.state.units.erase("U_EDGE_R")
	_check("one edge does not satisfy min_edges 2",
		not sec._check_units_near_board_edges(1, {"min_edges": 2, "edge_inches": 6.0}))
	_check("one edge satisfies min_edges 1",
		sec._check_units_near_board_edges(1, {"min_edges": 1, "edge_inches": 6.0}))
	gs.state.units.erase("U_EDGE_L")

	print("\n-- Beacon: unit wholly outside own deployment zone --")
	var center_px = Vector2(meas.inches_to_px(22), meas.inches_to_px(30))
	gs.state["units"]["U_OUT"] = _mk_unit(1, [{"id": "m", "alive": true, "wounds": 1, "current_wounds": 1,
		"base_mm": 32, "base_type": "circular", "position": {"x": center_px.x, "y": center_px.y}}])
	_check("unit at board centre is outside its own DZ",
		sec._check_unit_outside_own_dz(1, {}), "centre should be NML")
	gs.state.units.erase("U_OUT")
	_check("no qualifying unit -> false", not sec._check_unit_outside_own_dz(1, {}))

	print("\n-- Forward Position: both Expansion objectives --")
	var mm = root.get_node("MissionManager")
	var expansions = mm.get_objective_ids_by_designation("expansion")
	_check("two expansion objectives designated", expansions.size() == 2, str(expansions))
	for obj_id in mm.objective_control_state:
		mm.objective_control_state[obj_id] = 0
	for obj_id in expansions:
		mm.objective_control_state[obj_id] = 1
	_check("both expansions controlled satisfies Forward Position",
		sec._check_enemy_home_objective(1))
	mm.objective_control_state[expansions[0]] = 2
	# Official 11e launch card: controlling ONE expansion objective is enough
	# (controls-objective, objective_role: expansion, count_min: 1).
	_check("one expansion still satisfies Forward Position (official count_min 1)",
		sec._check_enemy_home_objective(1))
	mm.objective_control_state[expansions[1]] = 2
	_check("no expansions and no enemy home fails Forward Position",
		not sec._check_enemy_home_objective(1))

	print("\n-- Fixed secondaries: 20 VP per-card cap --")
	sec.initialize_for_game()
	sec.setup_fixed_missions(1, ["assassination", "a_grievous_blow"])
	var st = sec._player_state["1"]
	var a1 = sec._award_secondary_vp(1, 15, "assassination")
	st["secondary_vp_this_turn"] = 0
	var a2 = sec._award_secondary_vp(1, 15, "assassination")
	_check("second 15 VP award clipped to the card's 20 total",
		a1 == 15 and a2 == 5, "%d then %d" % [a1, a2])
	st["secondary_vp_this_turn"] = 0
	var a3 = sec._award_secondary_vp(1, 5, "a_grievous_blow")
	_check("other fixed card unaffected by the first card's cap", a3 == 5, str(a3))

	print("\n-- 11e army construction validator --")
	var army = alm.load_army_list("orks", 1)
	var v = alm.validate_army_construction_11e(army)
	_check("orks army passes 11e construction validation", v["valid"] and v["warnings"].is_empty(),
		str(v))
	var bad = army.duplicate(true)
	for uid in bad["units"]:
		if bad["units"][uid]["meta"].get("is_warlord", false):
			bad["units"][uid]["meta"]["keywords"] = ["CHARACTER", "TYRANIDS"]
	var v2 = alm.validate_army_construction_11e(bad)
	var has_warlord_warning = false
	for wmsg in v2["warnings"]:
		if "Faction keyword" in wmsg:
			has_warlord_warning = true
	_check("warlord without the army Faction keyword is flagged", has_warlord_warning, str(v2))

	GameConstants.edition = 10
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
