extends SceneTree

# 11e 19.03: an ATTACHED UNIT (a bodyguard plus the CHARACTER units attached to
# it) is a SINGLE unit — it embarks and disembarks as one.
#
# Reported bug (tutorial T3 "Get Movin'", step 3): the unit list showed
# "Boyz + Warboss [Embarked in Battlewagon]", the disembark asked for 10 Boyz
# bases, then reported the disembark complete — with the Warboss still off the
# battlefield. Two independent causes:
#   1. EMBARK never took the leader aboard (Formations/Deployment/Movement all
#      wrote embarked_in for the selected passenger only), so the shipped
#      tutorial fixture has U_WARBOSS_T UNDEPLOYED with embarked_in null.
#   2. DISEMBARK only ever placed the bodyguard's own models.
#
# Usage: godot --headless --path . -s tests/test_attached_leader_transport_11e.gd

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
	create_timer(0.1).timeout.connect(_run_tests)

var _ran := false

func _run_tests() -> void:
	if _ran:
		return
	_ran = true

	print("\n=== 19.03 attached leaders embark/disembark with their bodyguard ===\n")

	var gs = root.get_node_or_null("/root/GameState")
	var tm = root.get_node_or_null("/root/TransportManager")
	var ss = root.get_node_or_null("/root/StateSerializer")
	if gs == null or tm == null or ss == null:
		print("  FAIL: required autoloads not found (GameState/TransportManager/StateSerializer)")
		failed += 1
		_finish()
		return

	_test_group_helpers(gs, tm)
	_test_embark_takes_the_leader(gs, tm)
	_test_disembark_places_the_whole_group(gs, tm)
	_test_legacy_save_repair(ss)
	_test_shipped_tutorial_fixture(ss, gs, tm)

	_finish()

func _finish() -> void:
	print("\n=== %d passed, %d failed ===\n" % [passed, failed])
	quit(1 if failed > 0 else 0)

## Boyz (3 models) + Warboss (1 model) + an empty Battlewagon.
func _seed_state(gs) -> void:
	gs.state = {
		"meta": {"active_player": 1, "battle_round": 1},
		"units": {
			"U_BOYZ": {
				"id": "U_BOYZ", "owner": 1, "status": 2, "embarked_in": null,
				"attached_to": null,
				"attachment_data": {"attached_characters": ["U_BOSS"]},
				"flags": {},
				"meta": {"name": "Boyz", "keywords": ["INFANTRY", "ORKS"], "stats": {"move": 6}},
				"models": [
					{"id": "m1", "alive": true, "base_mm": 32, "position": {"x": 100.0, "y": 100.0}},
					{"id": "m2", "alive": true, "base_mm": 32, "position": {"x": 140.0, "y": 100.0}},
					{"id": "m3", "alive": true, "base_mm": 32, "position": {"x": 180.0, "y": 100.0}},
				],
			},
			"U_BOSS": {
				"id": "U_BOSS", "owner": 1, "status": 2, "embarked_in": null,
				"attached_to": "U_BOYZ",
				"attachment_data": {"attached_characters": []},
				"flags": {},
				"meta": {"name": "Warboss", "keywords": ["CHARACTER", "INFANTRY", "ORKS"], "stats": {"move": 6}},
				"models": [
					{"id": "m1", "alive": true, "base_mm": 40, "position": {"x": 220.0, "y": 100.0}},
				],
			},
			"U_WAGON": {
				"id": "U_WAGON", "owner": 1, "status": 2, "embarked_in": null,
				"attached_to": null,
				"attachment_data": {"attached_characters": []},
				"flags": {},
				"transport_data": {
					"capacity": 22, "capacity_keywords": ["ORKS", "INFANTRY"],
					"capacity_multipliers": {}, "excluded_keywords": [], "firing_deck": 0,
					"embarked_units": [],
				},
				"meta": {"name": "Battlewagon", "keywords": ["VEHICLE", "TRANSPORT", "ORKS"], "stats": {"move": 10}},
				"models": [
					{"id": "m1", "alive": true, "base_mm": 180, "base_type": "rectangular",
					 "base_dimensions": {"length": 100, "width": 180},
					 "position": {"x": 640.0, "y": 320.0}, "rotation": 0.0},
				],
			},
		},
	}

func _test_group_helpers(gs, tm) -> void:
	print("-- group resolution --")
	_seed_state(gs)

	_check("bodyguard resolves to [bodyguard, leader]",
		tm.get_attached_unit_group("U_BOYZ") == ["U_BOYZ", "U_BOSS"],
		str(tm.get_attached_unit_group("U_BOYZ")))
	_check("leader resolves to the same group, bodyguard first",
		tm.get_attached_unit_group("U_BOSS") == ["U_BOYZ", "U_BOSS"],
		str(tm.get_attached_unit_group("U_BOSS")))
	_check("an unattached unit is its own group",
		tm.get_attached_unit_group("U_WAGON") == ["U_WAGON"],
		str(tm.get_attached_unit_group("U_WAGON")))
	_check("the leader is flagged as an attached passenger",
		tm.is_attached_passenger("U_BOSS") and not tm.is_attached_passenger("U_BOYZ"))
	_check("the leader is not offered as a separate passenger",
		not _embarkable_ids(tm).has("U_BOSS"),
		str(_embarkable_ids(tm)))
	_check("the bodyguard IS offered as a passenger",
		_embarkable_ids(tm).has("U_BOYZ"),
		str(_embarkable_ids(tm)))

func _embarkable_ids(tm) -> Array:
	var ids := []
	for u in tm.get_embarkable_units("U_WAGON", 1):
		ids.append(u.get("id", ""))
	return ids

func _test_embark_takes_the_leader(gs, tm) -> void:
	print("-- embark --")
	_seed_state(gs)

	tm.embark_unit("U_BOYZ", "U_WAGON")

	_check("bodyguard is aboard", gs.state.units.U_BOYZ.get("embarked_in", null) == "U_WAGON")
	_check("attached leader is aboard too (19.03)",
		gs.state.units.U_BOSS.get("embarked_in", null) == "U_WAGON",
		str(gs.state.units.U_BOSS.get("embarked_in", null)))
	_check("leader counts as deployed", int(gs.state.units.U_BOSS.get("status", -1)) == 2)
	_check("leader models are off the battlefield",
		gs.state.units.U_BOSS.models[0].get("position", 1) == null)
	_check("transport lists both passengers",
		gs.state.units.U_WAGON.transport_data.embarked_units == ["U_BOYZ", "U_BOSS"],
		str(gs.state.units.U_WAGON.transport_data.embarked_units))
	_check("capacity check counts the leader's models too (4, not 3)",
		_capacity_used(tm) == 4, str(_capacity_used(tm)))

func _capacity_used(tm) -> int:
	return tm._get_embarked_model_count("U_WAGON")

func _test_disembark_places_the_whole_group(gs, tm) -> void:
	print("-- disembark --")
	_seed_state(gs)
	tm.embark_unit("U_BOYZ", "U_WAGON")

	_check("disembark group spans bodyguard + leader",
		tm.get_disembark_group("U_BOYZ") == ["U_BOYZ", "U_BOSS"],
		str(tm.get_disembark_group("U_BOYZ")))

	var slots := 0
	for gid in tm.get_disembark_group("U_BOYZ"):
		for m in gs.state.units[gid].models:
			if m.get("alive", true):
				slots += 1
	_check("placement covers 4 models, not 3", slots == 4, str(slots))

	# Disembark each member the way MovementPhase._process_confirm_disembark does.
	tm.disembark_unit("U_BOYZ", [Vector2(500, 400), Vector2(540, 400), Vector2(580, 400)])
	tm.disembark_unit("U_BOSS", [Vector2(620, 400)])

	_check("bodyguard left the transport", gs.state.units.U_BOYZ.get("embarked_in", null) == null)
	_check("leader left the transport", gs.state.units.U_BOSS.get("embarked_in", null) == null)
	_check("leader model is on the board at its placed position",
		gs.state.units.U_BOSS.models[0].position != null
			and abs(float(gs.state.units.U_BOSS.models[0].position.x) - 620.0) < 0.01,
		str(gs.state.units.U_BOSS.models[0].position))
	_check("transport is empty",
		gs.state.units.U_WAGON.transport_data.embarked_units.is_empty(),
		str(gs.state.units.U_WAGON.transport_data.embarked_units))

	# Both position-array shapes must land the survivors on the same spots.
	# ALIVE-ORDER (what the placement UI emits — one entry per living model):
	# reading this as model-indexed shifted every survivor onto the wrong base.
	_seed_state(gs)
	gs.state.units.U_BOYZ.models[0]["alive"] = false
	tm.embark_unit("U_BOYZ", "U_WAGON")
	tm.disembark_unit("U_BOYZ", [Vector2(500, 400), Vector2(540, 400)])
	_check("alive-order: first survivor gets the first position",
		gs.state.units.U_BOYZ.models[1].position != null
			and abs(float(gs.state.units.U_BOYZ.models[1].position.x) - 500.0) < 0.01,
		str(gs.state.units.U_BOYZ.models[1].position))
	_check("alive-order: second survivor gets the second position",
		gs.state.units.U_BOYZ.models[2].position != null
			and abs(float(gs.state.units.U_BOYZ.models[2].position.x) - 540.0) < 0.01,
		str(gs.state.units.U_BOYZ.models[2].position))

	# MODEL-INDEXED (what the AI and scripted/network actions emit — full length,
	# dead slots padded). Same survivors, same spots.
	_seed_state(gs)
	gs.state.units.U_BOYZ.models[0]["alive"] = false
	tm.embark_unit("U_BOYZ", "U_WAGON")
	tm.disembark_unit("U_BOYZ", [Vector2(9999, 9999), Vector2(500, 400), Vector2(540, 400)])
	_check("model-indexed: dead slot's padding is ignored",
		gs.state.units.U_BOYZ.models[1].position != null
			and abs(float(gs.state.units.U_BOYZ.models[1].position.x) - 500.0) < 0.01,
		str(gs.state.units.U_BOYZ.models[1].position))
	_check("model-indexed: second survivor gets its own slot's position",
		gs.state.units.U_BOYZ.models[2].position != null
			and abs(float(gs.state.units.U_BOYZ.models[2].position.x) - 540.0) < 0.01,
		str(gs.state.units.U_BOYZ.models[2].position))
	_check("model-indexed: the dead model stays off the board",
		gs.state.units.U_BOYZ.models[0].position == null,
		str(gs.state.units.U_BOYZ.models[0].position))

	# No casualties: the two shapes are identical, so either reading works.
	_seed_state(gs)
	tm.embark_unit("U_BOYZ", "U_WAGON")
	tm.disembark_unit("U_BOYZ", [Vector2(500, 400), Vector2(540, 400), Vector2(580, 400)])
	_check("no casualties: every model gets its own position",
		abs(float(gs.state.units.U_BOYZ.models[0].position.x) - 500.0) < 0.01
			and abs(float(gs.state.units.U_BOYZ.models[2].position.x) - 580.0) < 0.01)

func _test_legacy_save_repair(ss) -> void:
	print("-- legacy save repair --")
	# A save written before the embark paths expanded: bodyguard aboard, leader
	# stranded UNDEPLOYED outside.
	var data := {
		"units": {
			"U_BOYZ": {"id": "U_BOYZ", "owner": 1, "status": 2, "embarked_in": "U_WAGON",
				"attachment_data": {"attached_characters": ["U_BOSS"]},
				"meta": {"name": "Boyz"}, "models": [{"id": "m1", "alive": true, "base_mm": 32, "position": null}]},
			"U_BOSS": {"id": "U_BOSS", "owner": 1, "status": 0, "embarked_in": null,
				"attached_to": "U_BOYZ", "meta": {"name": "Warboss"},
				"models": [{"id": "m1", "alive": true, "base_mm": 40, "position": {"x": 10.0, "y": 10.0}}]},
			"U_WAGON": {"id": "U_WAGON", "owner": 1, "status": 2,
				"transport_data": {"capacity": 22, "embarked_units": ["U_BOYZ"]},
				"meta": {"name": "Battlewagon"},
				"models": [{"id": "m1", "alive": true, "base_mm": 180, "position": {"x": 640.0, "y": 320.0}}]},
		},
	}
	var result = ss._validate_unit_data(data)

	_check("repair validation still passes", result.get("valid", false))
	_check("stranded leader is embarked with its bodyguard",
		data.units.U_BOSS.get("embarked_in", null) == "U_WAGON",
		str(data.units.U_BOSS.get("embarked_in", null)))
	_check("repaired leader counts as deployed", int(data.units.U_BOSS.get("status", -1)) == 2)
	_check("repaired leader's model is off the battlefield",
		data.units.U_BOSS.models[0].get("position", 1) == null)
	_check("transport now lists the leader",
		"U_BOSS" in data.units.U_WAGON.transport_data.embarked_units,
		str(data.units.U_WAGON.transport_data.embarked_units))
	_check("the repair is reported", result.get("repairs", []).size() > 0)

func _test_shipped_tutorial_fixture(ss, gs, tm) -> void:
	print("-- shipped tutorial_postdeploy fixture (T3 'Get Movin') --")
	var path := "res://data/tutorials/fixtures/tutorial_postdeploy.w40ksave"
	if not FileAccess.file_exists(path):
		print("  SKIP: fixture not present in this build")
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var state = ss.deserialize_game_state(f.get_as_text())
	f.close()

	_check("fixture deserialized", not state.is_empty())
	if state.is_empty():
		return

	var wb = state.get("units", {}).get("U_WARBOSS_T", {})
	_check("tutorial Warboss boards the Battlewagon with the Boyz",
		wb.get("embarked_in", null) == "U_BATTLEWAGON_T",
		str(wb.get("embarked_in", null)))

	gs.state = state
	_check("tutorial disembark group is Boyz + Warboss",
		tm.get_disembark_group("U_BOYZ_T") == ["U_BOYZ_T", "U_WARBOSS_T"],
		str(tm.get_disembark_group("U_BOYZ_T")))

	var slots := 0
	for gid in tm.get_disembark_group("U_BOYZ_T"):
		for m in state.units[gid].models:
			if m.get("alive", true):
				slots += 1
	_check("tutorial disembark asks for 11 models (10 Boyz + Warboss)", slots == 11, str(slots))
