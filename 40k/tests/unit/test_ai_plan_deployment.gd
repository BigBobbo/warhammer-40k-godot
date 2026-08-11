extends SceneTree

# PM-2a — the AI consumes a plan's deployment: order, per-model placement, the
# seat-2 coordinate mirror, and per-unit fallback to the column formula.
#
# Covers:
#   - plan order overrides `deploy_actions[0]`, for the whole ordered sequence;
#   - placed models land within 0.5" of the authored positions;
#   - a unit the plan does not cover falls back to the formula, and the
#     decision record says so (`source: formula_fallback`);
#   - the SAME plan consumed as player 2 mirrors by [44-x, 60-y] and deploys
#     legally inside the player-2 zone;
#   - PLANS_ENABLED = 0 restores exact pre-plan behaviour;
#   - the plan statics are registered in the suggest_action snapshot contract,
#     so a human-hint preview cannot install a plan on the live AI;
#   - consumption on the REAL mirror_orks_2000_predeploy fixture, whose player-2
#     units carry the `_P2` re-key and whose zone is a triangle.
#
# Run with: godot --headless --path . -s tests/unit/test_ai_plan_deployment.gd

# NOTE: nothing is preloaded. Preloading AIDecisionMaker.gd from a `-s` script
# drags in GameState.gd -> DeploymentZoneData.gd -> the Measurement autoload,
# whose identifier does not resolve at that point in boot; the script then
# fails to compile and every static call on it errors. Autoloads are in the
# tree by the time the deferred _run() executes, so load() there works.
const AIDM_PATH := "res://scripts/AIDecisionMaker.gd"
const PLAN_MANAGER_PATH := "res://scripts/PlanManager.gd"
const PLAN_VALIDATOR_PATH := "res://scripts/PlanValidator.gd"

const RECON_STOMPS := "res://armies/recon_stomps.json"
const FIXTURE_RICH := "res://tests/fixtures/ai_plans/fixture_recon_stomps_rich.json"
const ORK_PREDEPLOY := "res://tests/saves/mirror_orks_2000_predeploy.w40ksave"

const PPI := 40.0     # AIDecisionMaker.PIXELS_PER_INCH
const BOARD_W := 44.0
const BOARD_H := 60.0

# GameStateData.UnitStatus
const STATUS_UNDEPLOYED := 0
const STATUS_DEPLOYED := 2

var AIDM
var PM
var PV

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	create_timer(0.2).timeout.connect(_run)

func _run():
	print("\n=== AI plan deployment (PM-2a) Tests ===\n")
	AIDM = load(AIDM_PATH)
	PM = load(PLAN_MANAGER_PATH)
	PV = load(PLAN_VALIDATOR_PATH)
	if AIDM == null or PM == null or PV == null:
		_assert(false, "scripts load at run time")
	else:
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

# ---------------------------------------------------------------------------
# Builders
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

func _zones_for(zone_id: String) -> Array:
	return PV.zone_json(zone_id).get("zones", [])

func _make_snapshot(zone_id: String, army_path: String, player: int) -> Dictionary:
	"""A deployment-phase snapshot: every unit of `player` undeployed, real
	zone polygons, no terrain."""
	var army := _read_json(army_path)
	var units := {}
	for unit_id in army.get("units", {}).keys():
		var unit: Dictionary = army["units"][unit_id].duplicate(true)
		unit["id"] = unit_id
		unit["owner"] = player
		unit["status"] = STATUS_UNDEPLOYED
		for model in unit.get("models", []):
			model["position"] = null
			model["alive"] = true
		units[unit_id] = unit
	return {
		"meta": {"deployment_type": zone_id, "battle_round": 1, "phase": 3},
		"board": {
			"size": {"width": BOARD_W, "height": BOARD_H},
			"deployment_zones": _zones_for(zone_id),
			"objectives": [],
			"terrain_features": [],
		},
		"factions": {str(player): {"name": "Orks", "detachment": "Speedwaaagh!"}},
		"units": units,
	}

func _deploy_actions(snapshot: Dictionary, player: int) -> Array:
	"""One DEPLOY_UNIT per undeployed unit, in REVERSE key order so that
	`deploy_actions[0]` provably differs from the plan's first ordered unit."""
	var ids: Array = []
	for unit_id in snapshot["units"].keys():
		var unit = snapshot["units"][unit_id]
		if int(unit.get("owner", 0)) == player and int(unit.get("status", 0)) == STATUS_UNDEPLOYED:
			ids.append(str(unit_id))
	ids.sort()
	ids.reverse()
	var actions: Array = []
	for unit_id in ids:
		actions.append({"type": "DEPLOY_UNIT", "unit_id": unit_id})
	return actions

func _apply_deploy(snapshot: Dictionary, action: Dictionary) -> void:
	var unit = snapshot["units"][action["unit_id"]]
	unit["status"] = STATUS_DEPLOYED
	var positions: Array = action.get("model_positions", [])
	for i in range(unit.get("models", []).size()):
		if i < positions.size():
			unit["models"][i]["position"] = positions[i]

func _plan_positions_for(plan: Dictionary, unit_id: String) -> Array:
	for placement in plan.get("deployment", {}).get("placements", []):
		if str(placement.get("unit", "")) == unit_id:
			return placement.get("models_inches", [])
	return []

func _zone_polygon_px(zone_id: String, player: int) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for zone in _zones_for(zone_id):
		if int(zone.get("player", 0)) == player:
			for point in zone.get("poly", []):
				poly.append(Vector2(float(point["x"]) * PPI, float(point["y"]) * PPI))
			break
	return poly

func _last_record_context() -> Dictionary:
	var records: Array = AIDM._decision_records
	if records.is_empty():
		return {}
	return records[records.size() - 1].get("context", {})

# ---------------------------------------------------------------------------

func _run_tests() -> void:
	test_plan_order_and_placement()
	test_uncovered_unit_falls_back()
	test_seat_two_mirror()
	test_plans_disabled_restores_formula()
	test_snapshot_contract_protects_live_plans()
	test_real_predeploy_fixture_both_seats()

func test_plan_order_and_placement() -> void:
	var plan := _read_json(FIXTURE_RICH)
	_assert(not plan.is_empty(), "rich fixture plan loads")
	var snapshot := _make_snapshot("hammer_anvil", RECON_STOMPS, 1)
	AIDM.clear_all_plans()
	AIDM.set_player_plan(1, plan)

	var order: Array = plan["deployment"]["order"]
	var followed := 0
	var within_half_inch := 0
	var checked := 0
	for step in range(order.size()):
		var actions := _deploy_actions(snapshot, 1)
		if actions.is_empty():
			break
		var expected := str(order[step])
		if step == 0:
			_assert(str(actions[0]["unit_id"]) != expected,
				"the phase's own first action is NOT the plan's first unit (so order is really being overridden)")
		var decision: Dictionary = AIDM._decide_deployment(snapshot, actions, 1)
		if decision.is_empty():
			break
		if str(decision.get("unit_id", "")) == expected:
			followed += 1
		# Positions must match the authored ones, in the player-1 frame.
		var authored := _plan_positions_for(plan, str(decision.get("unit_id", "")))
		if not authored.is_empty():
			checked += 1
			var worst := 0.0
			var positions: Array = decision.get("model_positions", [])
			for i in range(mini(authored.size(), positions.size())):
				var want := Vector2(float(authored[i][0]), float(authored[i][1]))
				var got: Vector2 = positions[i] / PPI
				worst = maxf(worst, want.distance_to(got))
			if worst <= 0.5:
				within_half_inch += 1
		_apply_deploy(snapshot, decision)

	_assert(followed == order.size(),
		"every one of the %d ordered units deployed in plan order (got %d)" % [order.size(), followed])
	_assert(checked == order.size() and within_half_inch == checked,
		"every planned unit landed within 0.5\" of its authored positions (%d/%d)" % [within_half_inch, checked])

	var ctx := _last_record_context()
	_assert(str(ctx.get("source", "")).begins_with("plan:"),
		"plan-driven deployments record source 'plan:<name>' (got '%s')" % ctx.get("source", ""))
	_assert(not bool(ctx.get("seat_mirrored", true)), "…and seat_mirrored is false at seat 1")

func test_uncovered_unit_falls_back() -> void:
	# U_GRETCHIN_B is embarked in the rich fixture, so it has no placement.
	var plan := _read_json(FIXTURE_RICH)
	var snapshot := _make_snapshot("hammer_anvil", RECON_STOMPS, 1)
	AIDM.clear_all_plans()
	AIDM.set_player_plan(1, plan)

	var actions := [{"type": "DEPLOY_UNIT", "unit_id": "U_GRETCHIN_B"}]
	var decision: Dictionary = AIDM._decide_deployment(snapshot, actions, 1)
	_assert(str(decision.get("unit_id", "")) == "U_GRETCHIN_B", "an uncovered unit is still deployed")
	_assert(str(decision.get("_ai_description", "")).find("from plan") == -1,
		"…via the formula, not the plan (got '%s')" % decision.get("_ai_description", ""))
	var ctx := _last_record_context()
	_assert(str(ctx.get("source", "")) == "formula_fallback",
		"…and the record says source 'formula_fallback' (got '%s')" % ctx.get("source", ""))
	_assert(str(ctx.get("plan", "")) == str(plan.get("name", "")),
		"…naming the plan that was active but did not cover it")
	_assert(decision.get("model_positions", []).size() == snapshot["units"]["U_GRETCHIN_B"]["models"].size(),
		"…with a position for every model")

func test_seat_two_mirror() -> void:
	var plan := _read_json(FIXTURE_RICH)
	var snapshot := _make_snapshot("hammer_anvil", RECON_STOMPS, 2)
	AIDM.clear_all_plans()
	AIDM.set_player_plan(2, plan)

	var poly_p2 := _zone_polygon_px("hammer_anvil", 2)
	_assert(poly_p2.size() >= 3, "hammer_anvil player-2 polygon resolves")

	var first_unit := str(plan["deployment"]["order"][0])
	var actions := _deploy_actions(snapshot, 2)
	var decision: Dictionary = AIDM._decide_deployment(snapshot, actions, 2)
	_assert(str(decision.get("unit_id", "")) == first_unit, "seat 2 follows the same plan order")
	_assert(str(decision.get("_ai_description", "")).find("from plan") != -1,
		"seat 2 deploys FROM THE PLAN rather than degrading to the formula (got '%s')" % decision.get("_ai_description", ""))

	var authored := _plan_positions_for(plan, first_unit)
	var positions: Array = decision.get("model_positions", [])
	var worst := 0.0
	var all_inside := true
	for i in range(mini(authored.size(), positions.size())):
		var want := Vector2(BOARD_W - float(authored[i][0]), BOARD_H - float(authored[i][1]))
		var got: Vector2 = positions[i] / PPI
		worst = maxf(worst, want.distance_to(got))
		if not Geometry2D.is_point_in_polygon(positions[i], poly_p2):
			all_inside = false
	_assert(worst <= 0.5, "seat-2 positions match the [44-x, 60-y] mirror of the authored ones (worst %.3f\")" % worst)
	_assert(all_inside, "every seat-2 model sits inside the player-2 deployment zone")

	var ctx := _last_record_context()
	_assert(bool(ctx.get("seat_mirrored", false)), "the record marks the placement as seat-mirrored")

	# The un-mirrored positions would be illegal at seat 2 — that is the whole
	# reason the transform exists, so prove it rather than asserting it.
	var raw_inside := 0
	for pair in authored:
		if Geometry2D.is_point_in_polygon(Vector2(float(pair[0]) * PPI, float(pair[1]) * PPI), poly_p2):
			raw_inside += 1
	_assert(raw_inside == 0,
		"…and the UNmirrored authored positions land nowhere inside the player-2 zone (%d/%d inside)" % [raw_inside, authored.size()])

func test_plans_disabled_restores_formula() -> void:
	var plan := _read_json(FIXTURE_RICH)
	var snapshot := _make_snapshot("hammer_anvil", RECON_STOMPS, 1)
	AIDM.clear_all_plans()
	AIDM.set_player_plan(1, plan)
	var actions := _deploy_actions(snapshot, 1)

	var with_plan: Dictionary = AIDM._decide_deployment(snapshot, actions, 1)

	AIDM._config_overrides["PLANS_ENABLED"] = 0
	var without_plan: Dictionary = AIDM._decide_deployment(snapshot, actions, 1)
	AIDM._config_overrides.erase("PLANS_ENABLED")

	_assert(str(with_plan.get("unit_id", "")) != str(without_plan.get("unit_id", "")),
		"PLANS_ENABLED=0 deploys the phase's first unit, not the plan's (%s vs %s)" % [
			with_plan.get("unit_id", ""), without_plan.get("unit_id", "")])
	_assert(str(without_plan.get("unit_id", "")) == str(actions[0]["unit_id"]),
		"…which is exactly deploy_actions[0], the pre-plan behaviour")
	var ctx := _last_record_context()
	_assert(str(ctx.get("source", "")) == "formula",
		"…and the record says source 'formula', not 'formula_fallback' (got '%s')" % ctx.get("source", ""))

func test_snapshot_contract_protects_live_plans() -> void:
	# suggest_action() runs a full decide() for the human-hint preview and then
	# restores. A plan auto-matched during that preview must NOT survive onto
	# the live AI — that is what _snapshot_planning_state/_restore_planning_state
	# are for, and every new mutable static has to be registered in both.
	var saved: Dictionary = AIDM._snapshot_planning_state()
	_assert(saved.has("player_plans") and saved.has("plan_auto_match_attempted") and saved.has("plan_logged_once"),
		"the planning-state snapshot registers all three plan statics")

	AIDM.clear_all_plans()
	var before: Dictionary = AIDM._snapshot_planning_state()
	AIDM.set_player_plan(1, _read_json(FIXTURE_RICH))
	_assert(not AIDM.get_player_plan(1).is_empty(), "a plan is installed mid-'preview'")
	AIDM._restore_planning_state(before)
	_assert(AIDM.get_player_plan(1).is_empty(),
		"restoring the planning state removes it again — the preview cannot leak a plan onto the live AI")
	AIDM._restore_planning_state(saved)

func test_real_predeploy_fixture_both_seats() -> void:
	# The fabricated snapshots above are only worth anything if the same code
	# works on a real game state: a crucible_of_battle TRIANGLE zone (which the
	# rectangular collision repair alone cannot honour) and a mirror match whose
	# player-2 units carry the `_P2` re-key.
	var main_loop = Engine.get_main_loop()
	var serializer = (main_loop as SceneTree).root.get_node_or_null("StateSerializer") if main_loop is SceneTree else null
	if serializer == null:
		_assert(false, "StateSerializer autoload is reachable")
		return
	var file = FileAccess.open(ORK_PREDEPLOY, FileAccess.READ)
	if file == null:
		_assert(false, "predeploy fixture is readable")
		return
	var text := file.get_as_text()
	file.close()
	var state: Dictionary = serializer.deserialize_game_state(text)
	_assert(not state.is_empty(), "mirror_orks_2000_predeploy deserializes")
	_assert(str(state.get("meta", {}).get("deployment_type", "")) == "crucible_of_battle",
		"…on the crucible_of_battle triangle")

	# Author a plan for that real identity. Positions sit well inside the
	# player-1 triangle ((0,0)-(44,30)-(44,0)).
	var plan := {
		"format": "wh40k_ai_plan", "version": 1,
		"name": "PM2a Real Fixture", "description": "", "author": "test",
		"keys": {"army_file": "recon_stomps", "detachment_hint": "Speedwaaagh!",
			"deployment_zone_id": "crucible_of_battle",
			"terrain_layout_id": "take_and_hold_mirror_1", "mission_id": ""},
		"deployment": {
			"order": ["U_GRETCHIN_A"],
			"placements": [{
				"unit": "U_GRETCHIN_A", "unit_name": "Gretchin", "role_fallback": "screen",
				"models_inches": [],
			}],
			"reserves": [], "embarkations": [], "attachments": [],
		},
		"earmarks": [], "profile_fragment": {"parameters": {}, "rules": []},
	}
	var gretchin_models: int = state["units"]["U_GRETCHIN_A"]["models"].size()
	var authored: Array = []
	for i in range(gretchin_models):
		authored.append([28.0 + 1.4 * (i % 6), 4.0 + 1.6 * float(i / 6)])
	plan["deployment"]["placements"][0]["models_inches"] = authored
	_assert(PV.validate_plan(plan).get("valid", false),
		"the fixture-keyed plan validates (%s)" % "; ".join(PV.validate_plan(plan).get("errors", [])))

	for player in [1, 2]:
		var snapshot: Dictionary = state.duplicate(true)
		# Put every unit back to undeployed so this is a deployment decision.
		for unit_id in snapshot["units"].keys():
			snapshot["units"][unit_id]["status"] = STATUS_UNDEPLOYED
			for model in snapshot["units"][unit_id].get("models", []):
				model["position"] = null
		var live_id: String = PM.resolve_unit_id("U_GRETCHIN_A", player, snapshot["units"])
		_assert(not live_id.is_empty(), "seat %d resolves U_GRETCHIN_A to '%s'" % [player, live_id])
		if player == 2:
			_assert(live_id == "U_GRETCHIN_A_P2", "…through the mirror re-key at seat 2")

		AIDM.clear_all_plans()
		AIDM.set_player_plan(player, plan)
		var decision: Dictionary = AIDM._decide_deployment(
			snapshot, [{"type": "DEPLOY_UNIT", "unit_id": live_id}], player)
		_assert(str(decision.get("_ai_description", "")).find("from plan") != -1,
			"seat %d deploys %s from the plan on the real fixture (got '%s')" % [
				player, live_id, decision.get("_ai_description", "")])

		var poly := _zone_polygon_px("crucible_of_battle", player)
		var outside := 0
		for pos in decision.get("model_positions", []):
			if not Geometry2D.is_point_in_polygon(pos, poly):
				outside += 1
		_assert(outside == 0,
			"…and all %d models sit inside the seat-%d triangle (%d outside)" % [
				decision.get("model_positions", []).size(), player, outside])

	AIDM.clear_all_plans()
