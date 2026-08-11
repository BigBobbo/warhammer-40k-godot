extends SceneTree

# PM-3 — the five earmark verbs bias the AI's existing machinery.
#
# Covers, for each verb, the ONE mechanism it is supposed to use:
#   HOLD_OBJECTIVE  additive (unit, objective) term in the assignment score,
#                   with a DIFFERENTIAL assert: the same state with plans
#                   disabled sends that unit somewhere else, so the test cannot
#                   be satisfied by the formula happening to agree;
#   PUSH_CENTER     the same shape, aimed at the central objective;
#   SCREEN          withholds the unit from the objective passes entirely, so it
#                   falls through to the screening pass;
#   HUNT_CHARACTERS an ADDITIVE term in all three per-attacker scorers, on top
#                   of (never replacing) their existing CHARACTER handling;
#   RESERVE_UNTIL   consumed at formations/deployment — see
#                   tests/unit/test_ai_plan_formations.gd.
# Plus: release-on-damage decay, the profile_fragment merge order, and the
# snapshot contract for the new mutable static.
#
# Run with: godot --headless --path . -s tests/unit/test_ai_plan_earmarks.gd

const AIDM_PATH := "res://scripts/AIDecisionMaker.gd"
const RECON_STOMPS := "res://armies/recon_stomps.json"

var AIDM
var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	create_timer(0.2).timeout.connect(_run)

func _run():
	print("\n=== AI plan earmarks (PM-3) Tests ===\n")
	AIDM = load(AIDM_PATH)
	if AIDM == null:
		_assert(false, "AIDecisionMaker loads at run time")
	else:
		_run_tests()
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	print("ALL TESTS PASSED" if _fail_count == 0 else "SOME TESTS FAILED")
	quit(1 if _fail_count > 0 else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

# ---------------------------------------------------------------------------

func _read_json(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	if err != OK or not (json.data is Dictionary):
		return {}
	return json.data

func _unit(unit_id: String, owner: int, name: String, keywords: Array, models: int,
		pos: Vector2, oc: int = 2, move: int = 6) -> Dictionary:
	var model_list: Array = []
	for i in range(models):
		model_list.append({
			"id": "m%d" % (i + 1), "alive": true, "wounds": 2, "current_wounds": 2,
			"base_mm": 32, "position": {"x": pos.x + i * 40.0, "y": pos.y},
		})
	return {
		"id": unit_id, "owner": owner, "status": 2,
		"meta": {"name": name, "keywords": keywords, "points": 100,
			"stats": {"move": move, "toughness": 4, "save": 4, "wounds": 2,
				"leadership": 7, "objective_control": oc}},
		"models": model_list,
	}

func _snapshot() -> Dictionary:
	# Two friendly units and two objectives, placed so the formula's own
	# preference is unambiguous and DIFFERENT from the plan's.
	var units := {
		# Sits right next to obj_home_1 (the formula's obvious pick for it).
		"U_GRETCHIN_A": _unit("U_GRETCHIN_A", 1, "Gretchin", ["INFANTRY", "ORKS"], 5, Vector2(880.0, 300.0)),
		# Deliberately NOT standing on either objective: the "hold" pass assigns
		# sole holders first and overrides raw scores, so a unit already on an
		# objective cannot be moved by a scoring bonus at all.
		"U_STORMBOYZ_A": _unit("U_STORMBOYZ_A", 1, "Stormboyz", ["INFANTRY", "ORKS"], 5, Vector2(500.0, 760.0)),
		"U_ENEMY_CHAR": _unit("U_ENEMY_CHAR", 2, "Warboss", ["CHARACTER", "INFANTRY", "ORKS"], 1, Vector2(880.0, 1600.0)),
		"U_ENEMY_MOB": _unit("U_ENEMY_MOB", 2, "Boyz", ["INFANTRY", "ORKS"], 10, Vector2(1000.0, 1600.0)),
	}
	return {
		"meta": {"deployment_type": "hammer_anvil", "battle_round": 2, "phase": 7},
		"board": {
			"size": {"width": 44, "height": 60},
			"deployment_zones": [],
			"terrain_features": [],
			"objectives": [
				{"id": "obj_home_1", "position": {"x": 880.0, "y": 240.0}, "designation": "home"},
				{"id": "obj_center", "position": {"x": 880.0, "y": 1200.0}, "designation": "central"},
			],
		},
		"factions": {"1": {"name": "Orks", "detachment": "Speedwaaagh!"}},
		"units": units,
	}

func _plan(earmarks: Array) -> Dictionary:
	return {
		"format": "wh40k_ai_plan", "version": 1, "name": "PM3 Test Plan",
		"description": "", "author": "test",
		"keys": {"army_file": "recon_stomps", "detachment_hint": "Speedwaaagh!",
			"deployment_zone_id": "hammer_anvil", "terrain_layout_id": "", "mission_id": ""},
		"deployment": {"order": [], "placements": [], "reserves": [], "embarkations": [], "attachments": []},
		"earmarks": earmarks,
		"profile_fragment": {"parameters": {}, "rules": []},
	}

func _bonus_for(unit_id: String, objective_id: String, snapshot: Dictionary) -> float:
	return float(AIDM._plan_objective_earmark_bonus(unit_id, objective_id, 1, snapshot).get("bonus", 0.0))

func _label_for(unit_id: String, objective_id: String, snapshot: Dictionary) -> String:
	return str(AIDM._plan_objective_earmark_bonus(unit_id, objective_id, 1, snapshot).get("earmark", ""))

# ---------------------------------------------------------------------------

func _run_tests() -> void:
	test_hold_objective()
	test_assignment_differential()
	test_push_center()
	test_screen()
	test_hunt_characters()
	test_release_on_damage()
	test_profile_fragment_merge_order()
	test_snapshot_contract()

func test_hold_objective() -> void:
	var snapshot := _snapshot()
	AIDM.clear_all_plans()
	AIDM.set_player_plan(1, _plan([
		{"unit": "U_STORMBOYZ_A", "verb": "HOLD_OBJECTIVE", "target": "obj_home_1"}]))

	var bonus := _bonus_for("U_STORMBOYZ_A", "obj_home_1", snapshot)
	_assert(bonus > 0.0, "HOLD_OBJECTIVE adds a positive term for the earmarked objective (%.1f)" % bonus)
	_assert(_label_for("U_STORMBOYZ_A", "obj_home_1", snapshot) == "HOLD_OBJECTIVE:obj_home_1",
		"…labelled 'HOLD_OBJECTIVE:obj_home_1' for the decision record")
	_assert(_bonus_for("U_STORMBOYZ_A", "obj_center", snapshot) == 0.0,
		"…and nothing for any other objective — the bonus is per (unit, objective) pair")
	_assert(_bonus_for("U_GRETCHIN_A", "obj_home_1", snapshot) == 0.0,
		"…and nothing for a unit the plan does not earmark")

	# DIFFERENTIAL: with plans disabled the very same call gives zero, so a
	# passing assertion above cannot be the formula agreeing by coincidence.
	AIDM._config_overrides["PLANS_ENABLED"] = 0
	var disabled := _bonus_for("U_STORMBOYZ_A", "obj_home_1", snapshot)
	AIDM._config_overrides.erase("PLANS_ENABLED")
	_assert(disabled == 0.0, "PLANS_ENABLED=0 removes the bonus entirely (%.1f)" % disabled)
	_assert(bonus != disabled, "…so the earmark, not the formula, is what moved the score")

	# The weight is a real tunable, not a constant.
	AIDM._config_overrides["PLAN_EARMARK_HOLD_BONUS"] = 25.0
	var tuned := _bonus_for("U_STORMBOYZ_A", "obj_home_1", snapshot)
	AIDM._config_overrides.erase("PLAN_EARMARK_HOLD_BONUS")
	_assert(is_equal_approx(tuned, 25.0), "PLAN_EARMARK_HOLD_BONUS is tunable through the normal param path (%.1f)" % tuned)

func _assignment_evals() -> Array:
	# obj_evaluations entries must carry every field the scorer reads with dot
	# notation — `is_home` in particular, whose absence throws inside the
	# candidate loop and silently yields no candidates at all.
	return [
		{"id": "obj_home_1", "position": Vector2(880.0, 240.0), "priority": 10.0, "state": "uncontrolled",
			"oc_needed": 1, "enemy_oc": 0, "friendly_oc": 0, "projected_enemy_oc": 0, "vp_value": 5.0,
			"is_home": true, "is_enemy_home": false, "zone": "player1", "distance": 0.0},
		{"id": "obj_center", "position": Vector2(880.0, 1200.0), "priority": 10.0, "state": "uncontrolled",
			"oc_needed": 1, "enemy_oc": 0, "friendly_oc": 0, "projected_enemy_oc": 0, "vp_value": 5.0,
			"is_home": false, "is_enemy_home": false, "zone": "no_mans_land", "distance": 0.0},
	]

func _assign(snapshot: Dictionary) -> Dictionary:
	var friendly := {}
	for unit_id in snapshot["units"].keys():
		if int(snapshot["units"][unit_id].get("owner", 0)) == 1:
			friendly[unit_id] = snapshot["units"][unit_id]
	var movable := {}
	for unit_id in friendly.keys():
		movable[unit_id] = ["BEGIN_NORMAL_MOVE"]
	return AIDM._assign_units_to_objectives(
		snapshot, movable, _assignment_evals(),
		[Vector2(880.0, 240.0), Vector2(880.0, 1200.0)], {}, friendly, 1, 2, [])

func test_assignment_differential() -> void:
	# The gate's real bar: run the ACTUAL assignment and show the earmarked unit
	# ends up somewhere different from where the formula alone would send it.
	var snapshot := _snapshot()
	snapshot["units"].erase("U_ENEMY_CHAR")
	snapshot["units"].erase("U_ENEMY_MOB")

	# One free chooser only. The assignment is GREEDY over (unit, objective)
	# pairs and each objective's OC need is consumed by the first unit sent
	# there, so a second unit standing next to the earmarked objective would
	# claim it first and the earmark would have nothing left to win.
	var solo := snapshot.duplicate(true)
	solo["units"].erase("U_GRETCHIN_A")

	AIDM.clear_all_plans()
	var base: Dictionary = _assign(solo)
	var base_obj := str(base.get("U_STORMBOYZ_A", {}).get("objective_id", ""))
	_assert(not base_obj.is_empty(), "the plans-off control assigns U_STORMBOYZ_A somewhere (%s)" % base_obj)

	var other := "obj_center" if base_obj == "obj_home_1" else "obj_home_1"
	AIDM.set_player_plan(1, _plan([
		{"unit": "U_STORMBOYZ_A", "verb": "HOLD_OBJECTIVE", "target": other}]))
	AIDM._config_overrides["PLAN_EARMARK_HOLD_BONUS"] = 100.0
	var planned: Dictionary = _assign(solo)
	AIDM._config_overrides.erase("PLAN_EARMARK_HOLD_BONUS")
	var planned_obj := str(planned.get("U_STORMBOYZ_A", {}).get("objective_id", ""))
	_assert(planned_obj == other,
		"the earmark moves U_STORMBOYZ_A from %s to %s" % [base_obj, planned_obj])
	_assert(planned_obj != base_obj,
		"…genuinely a different assignment from the plans-off control, so the test cannot be satisfied by formula behaviour")
	_assert(str(planned.get("U_STORMBOYZ_A", {}).get("score_terms", {}).get("plan_earmark", "")) != "",
		"…and the assignment's score_breakdown names the plan_earmark term that did it")

	# SCREEN keeps the unit out of the objective passes entirely, so the
	# screening pass is the only thing left that can pick it up.
	AIDM.clear_all_plans()
	AIDM.set_player_plan(1, _plan([{"unit": "U_STORMBOYZ_A", "verb": "SCREEN"}]))
	var screened: Dictionary = _assign(snapshot)
	var screen_passes := ["screen_denial", "screen_protect", "corridor_block", "support"]
	var screened_pass := str(screened.get("U_STORMBOYZ_A", {}).get("assign_pass", ""))
	_assert(screened_pass.is_empty() or screen_passes.has(screened_pass),
		"a SCREEN earmark drops the unit out of the objective passes into the screening pass (assign_pass=%s)" % screened_pass)

	AIDM.clear_all_plans()
	var unscreened: Dictionary = _assign(snapshot)
	var unscreened_pass := str(unscreened.get("U_STORMBOYZ_A", {}).get("assign_pass", ""))
	_assert(not unscreened_pass.is_empty() and not screen_passes.has(unscreened_pass),
		"…where without the earmark the same unit does objective work instead (assign_pass=%s)" % unscreened_pass)
	_assert(screened_pass != unscreened_pass,
		"…so SCREEN genuinely changed which pass claimed it")
	_assert(unscreened.has("U_GRETCHIN_A") and screened.has("U_GRETCHIN_A"),
		"…and the unearmarked unit is assigned either way")
	AIDM.clear_all_plans()

func test_push_center() -> void:
	var snapshot := _snapshot()
	AIDM.clear_all_plans()
	AIDM.set_player_plan(1, _plan([{"unit": "U_GRETCHIN_A", "verb": "PUSH_CENTER"}]))

	var centre_ids: Array = AIDM._plan_central_objective_ids(snapshot)
	_assert(centre_ids.has("obj_center"), "the central objective resolves (got %s)" % str(centre_ids))
	_assert(_bonus_for("U_GRETCHIN_A", "obj_center", snapshot) > 0.0, "PUSH_CENTER adds a term toward the centre")
	_assert(_label_for("U_GRETCHIN_A", "obj_center", snapshot) == "PUSH_CENTER:obj_center", "…labelled for the record")
	_assert(_bonus_for("U_GRETCHIN_A", "obj_home_1", snapshot) == 0.0, "…and nothing toward the home objective")

func test_screen() -> void:
	var snapshot := _snapshot()
	AIDM.clear_all_plans()
	AIDM.set_player_plan(1, _plan([{"unit": "U_GRETCHIN_A", "verb": "SCREEN"}]))
	_assert(AIDM._plan_unit_is_screening("U_GRETCHIN_A", 1, snapshot),
		"SCREEN marks the unit as withheld from the objective passes")
	_assert(not AIDM._plan_unit_is_screening("U_STORMBOYZ_A", 1, snapshot),
		"…and only that unit")
	AIDM._config_overrides["PLANS_ENABLED"] = 0
	var disabled: bool = AIDM._plan_unit_is_screening("U_GRETCHIN_A", 1, snapshot)
	AIDM._config_overrides.erase("PLANS_ENABLED")
	_assert(not disabled, "PLANS_ENABLED=0 stops withholding it")

func test_hunt_characters() -> void:
	var snapshot := _snapshot()
	AIDM.clear_all_plans()
	AIDM.set_player_plan(1, _plan([{"unit": "U_STORMBOYZ_A", "verb": "HUNT_CHARACTERS"}]))
	var attacker: Dictionary = snapshot["units"]["U_STORMBOYZ_A"]
	var character: Dictionary = snapshot["units"]["U_ENEMY_CHAR"]
	var mob: Dictionary = snapshot["units"]["U_ENEMY_MOB"]

	var vs_char := float(AIDM._plan_hunt_bonus(attacker, character, snapshot, 1))
	var vs_mob := float(AIDM._plan_hunt_bonus(attacker, mob, snapshot, 1))
	_assert(vs_char > 0.0, "HUNT_CHARACTERS adds a term against a CHARACTER target (%.1f)" % vs_char)
	_assert(vs_mob == 0.0, "…and nothing against a non-CHARACTER target")

	var other: Dictionary = snapshot["units"]["U_GRETCHIN_A"]
	_assert(float(AIDM._plan_hunt_bonus(other, character, snapshot, 1)) == 0.0,
		"…and nothing for a unit without the earmark")

	AIDM._config_overrides["PLANS_ENABLED"] = 0
	var disabled := float(AIDM._plan_hunt_bonus(attacker, character, snapshot, 1))
	AIDM._config_overrides.erase("PLANS_ENABLED")
	_assert(disabled == 0.0, "PLANS_ENABLED=0 removes the hunt term")

func test_release_on_damage() -> void:
	var snapshot := _snapshot()
	AIDM.clear_all_plans()
	AIDM.set_player_plan(1, _plan([
		{"unit": "U_STORMBOYZ_A", "verb": "HOLD_OBJECTIVE", "target": "obj_home_1"}]))
	_assert(_bonus_for("U_STORMBOYZ_A", "obj_home_1", snapshot) > 0.0, "a full-strength unit keeps its earmark")

	# 2 of 5 models alive = 40%, below the 0.5 release threshold.
	for i in range(3):
		snapshot["units"]["U_STORMBOYZ_A"]["models"][i]["alive"] = false
	_assert(_bonus_for("U_STORMBOYZ_A", "obj_home_1", snapshot) == 0.0,
		"a unit at 40%% strength has its earmark released")
	_assert(AIDM._plan_released_earmarks.has("1:U_STORMBOYZ_A"), "…and the release is recorded once")

	# Exactly at the threshold it still holds.
	AIDM.clear_all_plans()
	AIDM.set_player_plan(1, _plan([
		{"unit": "U_GRETCHIN_A", "verb": "HOLD_OBJECTIVE", "target": "obj_home_1"}]))
	var fresh := _snapshot()
	fresh["units"]["U_GRETCHIN_A"]["models"][0]["alive"] = false
	fresh["units"]["U_GRETCHIN_A"]["models"][1]["alive"] = false
	_assert(_bonus_for("U_GRETCHIN_A", "obj_home_1", fresh) > 0.0,
		"a unit at exactly the threshold (3/5) keeps its earmark")

	AIDM._config_overrides["PLAN_EARMARK_RELEASE_AT"] = 0.9
	var strict := _bonus_for("U_GRETCHIN_A", "obj_home_1", fresh)
	AIDM._config_overrides.erase("PLAN_EARMARK_RELEASE_AT")
	_assert(strict == 0.0, "PLAN_EARMARK_RELEASE_AT is tunable — at 0.9 the same 3/5 unit is released")

func test_profile_fragment_merge_order() -> void:
	AIDM.clear_all_plans()
	AIDM.clear_all_profiles()
	var plan := _plan([])
	plan["profile_fragment"] = {"parameters": {"WEIGHT_UNCONTROLLED_OBJ": 99.0}, "rules": []}

	AIDM.set_player_plan(1, plan)
	AIDM._current_player = 1
	_assert(is_equal_approx(AIDM.get_param("WEIGHT_UNCONTROLLED_OBJ", 1.0), 99.0),
		"a plan's profile_fragment reaches get_param through the normal profile layering")

	# An EXPLICIT profile wins: assigning one and then a plan must not silently
	# overwrite the player's own profile with the plan's fragment.
	AIDM.clear_all_plans()
	AIDM.clear_all_profiles()
	AIDM.load_player_profile(1, {"parameters": {"WEIGHT_UNCONTROLLED_OBJ": 5.0}, "rules": []})
	AIDM.set_player_plan(1, plan)
	AIDM._current_player = 1
	_assert(is_equal_approx(AIDM.get_param("WEIGHT_UNCONTROLLED_OBJ", 1.0), 5.0),
		"…but an explicitly assigned profile wins over the plan's fragment")

	AIDM.clear_all_profiles()
	AIDM.clear_all_plans()
	AIDM._current_player = 0

func test_snapshot_contract() -> void:
	# suggest_action() runs a full decide() for the human-hint preview; a release
	# recorded during that preview must not survive onto the live AI.
	var saved: Dictionary = AIDM._snapshot_planning_state()
	_assert(saved.has("plan_released_earmarks"),
		"the planning-state snapshot registers the earmark-release static")
	AIDM._plan_released_earmarks.clear()
	var before: Dictionary = AIDM._snapshot_planning_state()
	AIDM._plan_released_earmarks["1:U_PREVIEW"] = true
	AIDM._restore_planning_state(before)
	_assert(not AIDM._plan_released_earmarks.has("1:U_PREVIEW"),
		"…and restoring drops a release recorded during a preview")
	AIDM._restore_planning_state(saved)
	AIDM.clear_all_plans()
