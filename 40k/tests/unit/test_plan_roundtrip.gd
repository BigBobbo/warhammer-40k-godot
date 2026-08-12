extends SceneTree

# PM-5 — the deployment recorder and its round trip.
#
# The claim this file has to earn: what the Plan Editor records, the AI
# reproduces. So it does not stop at "the serializer emits plausible JSON" —
# it builds a deployment, records it, and then feeds the recording back through
# the PM-2a consumption path for BOTH seats, asserting the models land where
# they were recorded (seat 1 verbatim, seat 2 through the [44-x, 60-y] mirror).
#
# Covers:
#   - order comes from state.phase_log in dispatch order, not dictionary order;
#   - px -> inches conversion, model order preserved;
#   - reserves / embarkations / attachments are lifted out of unit state and are
#     NOT also emitted as placements;
#   - keys are filled from the live identity (army file, zone, layout, detachment);
#   - a terrain_layout_id that does not resolve is dropped rather than emitted
#     (it would make the plan unsaveable);
#   - anchors are derived and are recorded-only;
#   - the recording passes PlanValidator;
#   - ROUND TRIP: consumed by AIDecisionMaker as player 1 and as player 2, every
#     model lands within 0.5" of the recorded position.
#
# Run with: godot --headless --path . -s tests/unit/test_plan_roundtrip.gd

# NOTE (same trap as the other plan tests): nothing is preloaded. Preloading
# AIDecisionMaker.gd from a `-s` script drags in GameState.gd ->
# DeploymentZoneData.gd -> the Measurement autoload, which does not resolve at
# that point in boot. Autoloads are in the tree by the time the deferred _run()
# fires, so load() there works.
const RECORDER_PATH := "res://scripts/PlanRecorder.gd"
const AIDM_PATH := "res://scripts/AIDecisionMaker.gd"
const PLAN_VALIDATOR_PATH := "res://scripts/PlanValidator.gd"
const PLAN_MANAGER_PATH := "res://scripts/PlanManager.gd"

const RECON_STOMPS := "res://armies/recon_stomps.json"

const PPI := 40.0     # PlanRecorder.PIXELS_PER_INCH
const BOARD_W := 44.0
const BOARD_H := 60.0
const TOLERANCE_IN := 0.5

# GameStateData.UnitStatus
const STATUS_UNDEPLOYED := 0
const STATUS_DEPLOYED := 2
const STATUS_IN_RESERVES := 7

var REC
var AIDM
var PV
var PM

var _pass_count: int = 0
var _fail_count: int = 0


func _init():
	create_timer(0.2).timeout.connect(_run)


func _run():
	print("\n=== Plan recorder + round trip (PM-5) Tests ===\n")
	REC = load(RECORDER_PATH)
	AIDM = load(AIDM_PATH)
	PV = load(PLAN_VALIDATOR_PATH)
	PM = load(PLAN_MANAGER_PATH)
	if REC == null or AIDM == null or PV == null or PM == null:
		_assert(false, "scripts load at run time")
	else:
		test_placements_and_units()
		test_order_from_phase_log()
		test_formations_are_lifted_not_placed()
		test_keys_and_layout_guard()
		test_anchors()
		test_partial_unit_is_skipped()
		test_default_name()
		test_painted_earmarks()
		test_recording_validates()
		test_roundtrip_seat_1()
		test_roundtrip_seat_2()

	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)


# ============================================================
# Fixtures
# ============================================================

func _model(x_in: float, y_in: float, id: String) -> Dictionary:
	return {
		"id": id,
		"alive": true,
		"base_mm": 32,
		"base_type": "circular",
		"position": Vector2(x_in * PPI, y_in * PPI),
	}


func _unit(owner_id: int, name: String, positions_in: Array, status: int = STATUS_DEPLOYED) -> Dictionary:
	var models: Array = []
	for i in range(positions_in.size()):
		var p = positions_in[i]
		models.append(_model(float(p[0]), float(p[1]), "m%d" % (i + 1)))
	return {
		"owner": owner_id,
		"status": status,
		"meta": {"name": name, "keywords": ["INFANTRY"]},
		"models": models,
	}


## A hammer_anvil player-1 deployment (zone is y 0..18, x 0..44) with one unit
## on the board, one in reserves, one embarked and one attached character.
func _state() -> Dictionary:
	var gretchin := _unit(1, "Gretchin Alpha", [[8.0, 6.0], [9.5, 6.0], [11.0, 6.0]])
	var stormboyz := _unit(1, "Stormboyz Alpha", [[20.0, 12.0], [21.5, 12.0]])
	var stompa := _unit(1, "Stompa", [[30.0, 9.0]])

	var reserved := _unit(1, "Deffkoptas Alpha", [], STATUS_IN_RESERVES)
	reserved["models"] = [_model(0.0, 0.0, "m1")]
	reserved["models"][0]["position"] = null

	var passenger := _unit(1, "Gretchin Beta", [[30.0, 9.0]])
	passenger["embarked_in"] = "U_STOMPA_A"

	var character := _unit(1, "Deffkilla Wartrike Alpha", [[20.0, 12.0]])
	character["attached_to"] = "U_STORMBOYZ_A"

	# An enemy unit, to prove the recorder only serialises its own seat.
	var enemy := _unit(2, "Custodian Guard", [[20.0, 50.0]])

	return {
		"units": {
			"U_GRETCHIN_A": gretchin,
			"U_STORMBOYZ_A": stormboyz,
			"U_STOMPA_A": stompa,
			"U_DEFFKOPTAS_A": reserved,
			"U_GRETCHIN_B": passenger,
			"U_DEFFKILLA_WARTRIKE_A": character,
			"U_ENEMY_A": enemy,
		},
		"factions": {
			"1": {"name": "Orks", "detachment": "Speedwaaagh!"},
			"2": {"name": "Adeptus Custodes", "detachment": "Shield Host"},
		},
		"board": {
			"terrain_layout": "",
			"objectives": [
				{"id": "obj_home_1", "position": Vector2(22.0 * PPI, 10.0 * PPI)},
				{"id": "obj_center", "position": Vector2(22.0 * PPI, 30.0 * PPI)},
			],
		},
		"meta": {
			"deployment_type": "hammer_anvil",
			"game_config": {
				"player1_army": "recon_stomps",
				"player2_army": "custodes_lions",
				"deployment": "hammer_anvil",
				"terrain": "",
				"mission": "take_and_hold",
				"plan_editor": true,
			},
		},
		# Dispatch order is deliberately NOT the units dictionary order.
		"phase_log": [
			{"type": "DEPLOY_UNIT", "unit_id": "U_STOMPA_A"},
			{"type": "PLACE_IN_RESERVES", "unit_id": "U_DEFFKOPTAS_A"},
			{"type": "COMPOSITE_DEPLOY", "unit_id": "U_STORMBOYZ_A"},
			{"type": "DEPLOY_UNIT", "unit_id": "U_ENEMY_A"},
			{"type": "DEPLOY_UNIT", "unit_id": "U_GRETCHIN_A"},
		],
	}


# ============================================================
# Tests
# ============================================================

func test_placements_and_units() -> void:
	print("\n-- placements: own seat only, px -> inches, model order --")
	var plan: Dictionary = REC.build_plan(_state(), {"name": "T"})
	var placements: Array = plan["deployment"]["placements"]

	var by_unit := {}
	for p in placements:
		by_unit[str(p.get("unit", ""))] = p

	_assert(placements.size() == 3,
		"three units are placed (got %d: %s)" % [placements.size(), str(by_unit.keys())])
	_assert(not by_unit.has("U_ENEMY_A"), "the opposing seat is not recorded")

	var gret = by_unit.get("U_GRETCHIN_A", {})
	var models: Array = gret.get("models_inches", [])
	_assert(models.size() == 3, "Gretchin records all 3 models (got %d)" % models.size())
	if models.size() == 3:
		_assert(_close(models[0][0], 8.0) and _close(models[0][1], 6.0),
			"model 0 converts 320px -> 8.0in (got %s)" % str(models[0]))
		_assert(_close(models[1][0], 9.5), "model order is preserved (got %s)" % str(models[1]))
		_assert(_close(models[2][0], 11.0), "model 2 is last (got %s)" % str(models[2]))
	_assert(str(gret.get("unit_name", "")) == "Gretchin Alpha",
		"unit_name is carried for the degradation path (got '%s')" % str(gret.get("unit_name", "")))


func test_order_from_phase_log() -> void:
	print("\n-- order: dispatch order from phase_log, own seat, placed units only --")
	var plan: Dictionary = REC.build_plan(_state(), {"name": "T"})
	var order: Array = plan["deployment"]["order"]

	_assert(order.size() == 3, "order lists the 3 placed units (got %s)" % str(order))
	_assert(order == ["U_STOMPA_A", "U_STORMBOYZ_A", "U_GRETCHIN_A"],
		"order follows the phase_log, not the units dictionary (got %s)" % str(order))
	_assert(not ("U_DEFFKOPTAS_A" in order),
		"a reserved unit is not in the deployment order")
	_assert(not ("U_ENEMY_A" in order),
		"the opposing seat's action does not leak into order")

	# Every placement must be in order, or the validator warns about an orphan.
	var placed := []
	for p in plan["deployment"]["placements"]:
		placed.append(str(p["unit"]))
	var all_covered := true
	for pid in placed:
		if not (pid in order):
			all_covered = false
	_assert(all_covered, "every placement appears in order (%s vs %s)" % [str(placed), str(order)])

	# A unit placed with no log entry (e.g. deployed before a reload) is still
	# ordered — appended after the logged ones.
	var state := _state()
	state["phase_log"] = [{"type": "DEPLOY_UNIT", "unit_id": "U_GRETCHIN_A"}]
	var plan2: Dictionary = REC.build_plan(state, {"name": "T"})
	var order2: Array = plan2["deployment"]["order"]
	_assert(order2.size() == 3 and str(order2[0]) == "U_GRETCHIN_A",
		"unlogged placements are appended after the logged ones (got %s)" % str(order2))


func test_formations_are_lifted_not_placed() -> void:
	print("\n-- reserves / embarkations / attachments are lifted out of unit state --")
	var plan: Dictionary = REC.build_plan(_state(), {"name": "T"})
	var dep: Dictionary = plan["deployment"]

	_assert(dep["reserves"].size() == 1 and str(dep["reserves"][0]["unit"]) == "U_DEFFKOPTAS_A",
		"the IN_RESERVES unit is recorded as a reserve (got %s)" % str(dep["reserves"]))
	_assert(int(dep["reserves"][0]["arrival_round"]) == 2,
		"arrival_round defaults to the earliest legal round (got %s)" % str(dep["reserves"][0]))

	_assert(dep["embarkations"].size() == 1
			and str(dep["embarkations"][0]["unit"]) == "U_GRETCHIN_B"
			and str(dep["embarkations"][0]["transport"]) == "U_STOMPA_A",
		"the embarked unit is recorded with its transport (got %s)" % str(dep["embarkations"]))

	_assert(dep["attachments"].size() == 1
			and str(dep["attachments"][0]["character"]) == "U_DEFFKILLA_WARTRIKE_A"
			and str(dep["attachments"][0]["bodyguard"]) == "U_STORMBOYZ_A",
		"the attached character is recorded with its bodyguard (got %s)" % str(dep["attachments"]))

	# The three of them must NOT also appear as placements — the validator
	# rejects a unit that is both placed and reserved, and a passenger or an
	# attached character has no board position of its own.
	var placed_ids := []
	for p in dep["placements"]:
		placed_ids.append(str(p["unit"]))
	_assert(not ("U_DEFFKOPTAS_A" in placed_ids), "a reserved unit is not also placed")
	_assert(not ("U_GRETCHIN_B" in placed_ids), "a passenger is not also placed")
	_assert(not ("U_DEFFKILLA_WARTRIKE_A" in placed_ids), "an attached character is not also placed")

	var custom: Dictionary = REC.build_plan(_state(), {"name": "T", "arrival_round": 3})
	_assert(int(custom["deployment"]["reserves"][0]["arrival_round"]) == 3,
		"arrival_round is overridable from info")


func test_keys_and_layout_guard() -> void:
	print("\n-- keys: identity from live state, unresolvable layout dropped --")
	var plan: Dictionary = REC.build_plan(_state(), {"name": "T"})
	var keys: Dictionary = plan["keys"]

	_assert(str(keys["army_file"]) == "recon_stomps",
		"army_file from game_config (got '%s')" % str(keys["army_file"]))
	_assert(str(keys["deployment_zone_id"]) == "hammer_anvil",
		"deployment_zone_id from meta.deployment_type (got '%s')" % str(keys["deployment_zone_id"]))
	_assert(str(keys["detachment_hint"]) == "Speedwaaagh!",
		"detachment_hint from state.factions (got '%s')" % str(keys["detachment_hint"]))
	_assert(str(keys["mission_id"]) == "take_and_hold",
		"mission_id from game_config (got '%s')" % str(keys["mission_id"]))
	_assert(str(plan["format"]) == "wh40k_ai_plan" and int(plan["version"]) == 1,
		"envelope is the v1 format tag")
	_assert(plan["earmarks"] is Array and plan["earmarks"].is_empty(),
		"earmarks are left empty for PM-6")

	# A layout id the validator cannot resolve would make the plan unsaveable.
	var bogus := _state()
	bogus["board"]["terrain_layout"] = "no_such_layout_at_all"
	var plan2: Dictionary = REC.build_plan(bogus, {"name": "T"})
	_assert(str(plan2["keys"]["terrain_layout_id"]) == "",
		"an unresolvable terrain_layout_id is dropped, not emitted (got '%s')"
			% str(plan2["keys"]["terrain_layout_id"]))

	# A real one is kept.
	var layouts := DirAccess.get_files_at("res://terrain_layouts")
	if layouts.size() > 0:
		var real_id := str(layouts[0]).get_basename()
		var good := _state()
		good["board"]["terrain_layout"] = real_id
		var plan3: Dictionary = REC.build_plan(good, {"name": "T"})
		_assert(str(plan3["keys"]["terrain_layout_id"]) == real_id,
			"a resolvable terrain_layout_id is kept (got '%s')" % str(plan3["keys"]["terrain_layout_id"]))
	else:
		_assert(false, "res://terrain_layouts has files to test against")


func test_anchors() -> void:
	print("\n-- anchors: nearest objective, depth from the zone edge, nearest piece --")
	var terrain := [
		{"id": "area-large-2", "position": Vector2(9.0 * PPI, 7.0 * PPI)},
		{"id": "ruin-far", "position": Vector2(40.0 * PPI, 55.0 * PPI)},
	]
	var plan: Dictionary = REC.build_plan(_state(), {"name": "T"}, terrain)
	var gret := {}
	for p in plan["deployment"]["placements"]:
		if str(p["unit"]) == "U_GRETCHIN_A":
			gret = p
	var anchors: Dictionary = gret.get("anchors", {})

	_assert(str(anchors.get("nearest_objective", "")) == "obj_home_1",
		"nearest objective to (9.5, 6.0) is the home one (got '%s')" % str(anchors.get("nearest_objective", "")))
	_assert(str(anchors.get("nearest_terrain_piece", "")) == "area-large-2",
		"nearest terrain piece is the adjacent one (got '%s')" % str(anchors.get("nearest_terrain_piece", "")))
	# hammer_anvil player-1 zone is y 0..18: a centroid at y=6 is 6" from the
	# back edge and 12" from the front, so the nearest edge is 6".
	var depth := float(anchors.get("depth_from_zone_edge_in", -1.0))
	_assert(abs(depth - 6.0) < 0.2,
		"depth from the nearest zone edge is ~6in (got %.2f)" % depth)

	var no_terrain: Dictionary = REC.build_plan(_state(), {"name": "T"})
	var g2 := {}
	for p in no_terrain["deployment"]["placements"]:
		if str(p["unit"]) == "U_GRETCHIN_A":
			g2 = p
	_assert(not g2.get("anchors", {}).has("nearest_terrain_piece"),
		"with no terrain supplied the piece anchor is omitted, not guessed")


func test_partial_unit_is_skipped() -> void:
	print("\n-- a half-placed unit is skipped rather than half-recorded --")
	var state := _state()
	state["units"]["U_GRETCHIN_A"]["models"][1]["position"] = null
	var plan: Dictionary = REC.build_plan(state, {"name": "T"})
	var ids := []
	for p in plan["deployment"]["placements"]:
		ids.append(str(p["unit"]))
	_assert(not ("U_GRETCHIN_A" in ids),
		"a unit with an unplaced model is not recorded (got %s)" % str(ids))
	_assert(not ("U_GRETCHIN_A" in plan["deployment"]["order"]),
		"and it is not in order either")


func test_default_name() -> void:
	print("\n-- default plan name --")
	var name: String = REC.default_plan_name(_state(), 1)
	_assert(name == "recon_stomps — hammer_anvil",
		"default name is '<army_file> — <zone_id>' (got '%s')" % name)
	var plan: Dictionary = REC.build_plan(_state(), {})
	_assert(str(plan["name"]) == name,
		"an unnamed recording falls back to the default name (got '%s')" % str(plan["name"]))


func test_painted_earmarks() -> void:
	print("\n-- PM-6 earmarks: passed through, filtered, RESERVE_UNTIL reconciled --")
	var state := _state()
	state["meta"]["plan_earmarks"] = [
		{"unit": "U_GRETCHIN_A", "verb": "HOLD_OBJECTIVE", "target": "obj_home_1"},
		{"unit": "U_STORMBOYZ_A", "verb": "SCREEN"},
		# Painted onto a unit that is standing on the board: the plan must record
		# it as a reserve instead, or the validator rejects the contradiction.
		{"unit": "U_STOMPA_A", "verb": "RESERVE_UNTIL", "round": 3},
		# Stale / other seat — must be dropped.
		{"unit": "U_ENEMY_A", "verb": "PUSH_CENTER"},
		{"unit": "U_NO_SUCH_UNIT", "verb": "PUSH_CENTER"},
	]
	var plan: Dictionary = REC.build_plan(state, {"name": "Painted"})
	var earmarks: Array = plan["earmarks"]

	var by_unit := {}
	for e in earmarks:
		by_unit[str(e.get("unit", ""))] = e

	_assert(earmarks.size() == 3,
		"only this seat's live units keep their earmark (got %s)" % str(by_unit.keys()))
	_assert(not by_unit.has("U_ENEMY_A"), "the opposing seat's earmark is dropped")
	_assert(not by_unit.has("U_NO_SUCH_UNIT"), "an earmark for a missing unit is dropped")
	_assert(str(by_unit.get("U_GRETCHIN_A", {}).get("target", "")) == "obj_home_1",
		"HOLD_OBJECTIVE keeps its bound target")

	var reserved_ids := []
	for r in plan["deployment"]["reserves"]:
		reserved_ids.append(str(r["unit"]))
	_assert("U_STOMPA_A" in reserved_ids,
		"a painted RESERVE_UNTIL moves the unit into deployment.reserves (got %s)" % str(reserved_ids))
	for r in plan["deployment"]["reserves"]:
		if str(r["unit"]) == "U_STOMPA_A":
			_assert(int(r["arrival_round"]) == 3,
				"and carries the painted round, not the default (got %s)" % str(r))

	var placed_ids := []
	for p in plan["deployment"]["placements"]:
		placed_ids.append(str(p["unit"]))
	_assert(not ("U_STOMPA_A" in placed_ids),
		"and it is no longer a placement (got %s)" % str(placed_ids))
	_assert(not ("U_STOMPA_A" in plan["deployment"]["order"]),
		"nor in the deployment order")

	# The validator cross-checks RESERVE_UNTIL against deployment.reserves, so
	# this is the assertion that proves the reconciliation is actually needed.
	var result: Dictionary = PV.validate_plan(plan)
	_assert(bool(result.get("valid", false)),
		"a painted plan validates (errors: %s)" % str(result.get("errors", [])))

	# No painting at all -> an explicitly empty list, not a missing key.
	var unpainted: Dictionary = REC.build_plan(_state(), {"name": "Unpainted"})
	_assert(unpainted["earmarks"] is Array and unpainted["earmarks"].is_empty(),
		"an unpainted recording carries an explicit empty earmarks list")


func test_recording_validates() -> void:
	print("\n-- the recording passes PlanValidator --")
	var plan: Dictionary = REC.build_plan(_state(), {"name": "PM-5 recording"})
	var result: Dictionary = PV.validate_plan(plan)
	_assert(bool(result.get("valid", false)),
		"a recorded plan is valid (errors: %s)" % str(result.get("errors", [])))
	_assert(result.get("warnings", []).is_empty(),
		"and warning-free (warnings: %s)" % str(result.get("warnings", [])))


# ============================================================
# The round trip
# ============================================================

func _consume_and_measure(plan: Dictionary, player: int) -> Dictionary:
	"""Feed `plan` to the PM-2a consumption path for `player` and return
	{unit_id: max deviation in inches} for every placement it produced."""
	AIDM.clear_all_plans()
	AIDM.set_player_plan(player, plan)

	var snapshot := _consumer_snapshot(plan, player)
	var deviations := {}

	# Deploy every unit the plan places, one action at a time, feeding each
	# result back into the snapshot so later units see the earlier ones (the
	# consumer checks overlap against already-deployed models).
	for placement in plan["deployment"]["placements"]:
		var plan_unit := str(placement["unit"])
		var live_id := _live_id(plan_unit, player, snapshot)
		if live_id == "":
			deviations[plan_unit] = INF
			continue
		var actions := [{"type": "DEPLOY_UNIT", "unit_id": live_id}]
		var action: Dictionary = AIDM._decide_deployment(snapshot, actions, player)
		if action.is_empty() or str(action.get("type", "")) != "DEPLOY_UNIT":
			deviations[plan_unit] = INF
			continue
		var positions = action.get("model_positions", [])
		var worst := 0.0
		var expected: Array = placement["models_inches"]
		for i in range(expected.size()):
			if i >= positions.size():
				worst = INF
				break
			var got: Vector2 = positions[i] if positions[i] is Vector2 else Vector2(
				float(positions[i].get("x", 0)), float(positions[i].get("y", 0)))
			var want := Vector2(float(expected[i][0]), float(expected[i][1]))
			if player != 1:
				want = Vector2(BOARD_W - want.x, BOARD_H - want.y)
			var d := (got / PPI).distance_to(want)
			if d > worst:
				worst = d
		deviations[plan_unit] = worst
		# Commit into the snapshot so the next unit sees it on the board.
		var models: Array = snapshot["units"][live_id]["models"]
		for i in range(models.size()):
			if i < positions.size():
				models[i]["position"] = positions[i]
		snapshot["units"][live_id]["status"] = STATUS_DEPLOYED

	AIDM.clear_all_plans()
	return deviations


func _live_id(plan_unit: String, player: int, snapshot: Dictionary) -> String:
	var suffixed := "%s_P%d" % [plan_unit, player]
	if snapshot["units"].has(suffixed):
		return suffixed
	if snapshot["units"].has(plan_unit):
		return plan_unit
	return ""


func _consumer_snapshot(plan: Dictionary, player: int) -> Dictionary:
	"""A fresh, fully UNDEPLOYED board for `player`, holding exactly the units
	the plan places, with the plan's zone and objectives. This is the state the
	AI would face at the start of its deployment."""
	var units := {}
	for placement in plan["deployment"]["placements"]:
		var models := []
		for i in range(placement["models_inches"].size()):
			models.append({
				"id": "m%d" % (i + 1),
				"alive": true,
				"base_mm": 32,
				"base_type": "circular",
				"position": null,
			})
		units[str(placement["unit"])] = {
			"owner": player,
			"status": STATUS_UNDEPLOYED,
			"meta": {"name": str(placement.get("unit_name", placement["unit"])), "keywords": ["INFANTRY"]},
			"models": models,
		}
	return {
		"units": units,
		"board": {
			"objectives": [
				{"id": "obj_home_1", "position": Vector2(22.0 * PPI, 10.0 * PPI)},
				{"id": "obj_center", "position": Vector2(22.0 * PPI, 30.0 * PPI)},
			],
			"terrain_layout": "",
		},
		"meta": {
			"deployment_type": str(plan["keys"]["deployment_zone_id"]),
			"active_player": player,
			"battle_round": 1,
			"game_config": {
				"player%d_army" % player: str(plan["keys"]["army_file"]),
				"deployment": str(plan["keys"]["deployment_zone_id"]),
				"terrain": str(plan["keys"]["terrain_layout_id"]),
			},
		},
		"factions": {str(player): {"name": "Orks", "detachment": str(plan["keys"]["detachment_hint"])}},
	}


func test_roundtrip_seat_1() -> void:
	print("\n-- ROUND TRIP: seat 1 reproduces the recorded deployment verbatim --")
	var plan: Dictionary = REC.build_plan(_state(), {"name": "PM-5 roundtrip"})
	var deviations := _consume_and_measure(plan, 1)

	_assert(deviations.size() == plan["deployment"]["placements"].size(),
		"every placement was consumed (%d of %d)" % [deviations.size(), plan["deployment"]["placements"].size()])
	for unit_id in deviations:
		var d: float = deviations[unit_id]
		_assert(d <= TOLERANCE_IN,
			"seat 1: %s lands within %.1fin of the recording (worst %.3fin)" % [unit_id, TOLERANCE_IN, d])


func test_roundtrip_seat_2() -> void:
	print("\n-- ROUND TRIP: seat 2 reproduces it through the [44-x, 60-y] mirror --")
	var plan: Dictionary = REC.build_plan(_state(), {"name": "PM-5 roundtrip"})
	var deviations := _consume_and_measure(plan, 2)

	_assert(deviations.size() == plan["deployment"]["placements"].size(),
		"every placement was consumed (%d of %d)" % [deviations.size(), plan["deployment"]["placements"].size()])
	for unit_id in deviations:
		var d: float = deviations[unit_id]
		_assert(d <= TOLERANCE_IN,
			"seat 2: %s lands within %.1fin of the mirrored recording (worst %.3fin)" % [unit_id, TOLERANCE_IN, d])


# ============================================================
# Harness
# ============================================================

func _close(a: float, b: float, eps: float = 0.001) -> bool:
	return abs(a - b) < eps


func _assert(condition: bool, label: String) -> void:
	if condition:
		_pass_count += 1
		print("  PASS: %s" % label)
	else:
		_fail_count += 1
		print("  FAIL: %s" % label)
