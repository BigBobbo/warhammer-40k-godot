extends SceneTree

# T-026 (data-layer wedge): GameState.split_unit_at_deployment splits a
# 10-model UNDEPLOYED unit with Combat Squads or Patrol Squad ability into
# two 5-model siblings. The full audit task ALSO needs DeploymentController
# UI integration (offer "Split now?" prompt during deployment) — that part is
# surfaced as BLOCKED in the audit report; this wedge gives the rules-side
# helper that the UI can call.
#
# Usage: godot --headless --path . -s tests/test_t026_combat_squads_split.gd

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

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_t026_combat_squads_split ===\n")
	_test_split_happy_path()
	_test_split_rejects_no_ability()
	_test_split_rejects_wrong_size()
	_test_split_rejects_already_deployed()
	_finish()

func _make_tactical_squad_state(num_models: int = 10, has_ability: bool = true,
		status: int = 0) -> Dictionary:
	var abilities = []
	if has_ability:
		abilities.append({"name": "Combat Squads", "type": "Datasheet"})
	abilities.append({"name": "Bolt Discipline", "type": "Datasheet"})
	var models = []
	for i in range(num_models):
		models.append({"id": "m%d" % (i + 1), "alive": true, "current_wounds": 1, "wounds": 1,
			"base_mm": 32, "position": null})
	return {
		"meta": {"phase": GameStateData.Phase.DEPLOYMENT, "active_player": 1},
		"players": {"1": {"cp": 3}, "2": {"cp": 3}},
		"units": {
			"U_TAC": {
				"id": "U_TAC",
				"squad_id": "U_TAC",
				"owner": 1,
				"status": status,
				"flags": {},
				"meta": {
					"name": "Tactical Squad",
					"keywords": ["IMPERIUM", "INFANTRY", "TACTICAL SQUAD"],
					"stats": {"move": 6, "toughness": 4, "save": 3, "wounds": 1},
					"abilities": abilities,
					"weapons": [{"name": "Bolter", "type": "Ranged", "range": "24",
						"attacks": "2", "ballistic_skill": "3", "strength": "4", "ap": "0",
						"damage": "1"}],
				},
				"models": models,
			},
		},
	}

func _test_split_happy_path() -> void:
	print("\n-- T-026/A: split a 10-model Tactical Squad with Combat Squads ability --")
	var gs = root.get_node("GameState")
	gs.state = _make_tactical_squad_state()
	var sibling_id = gs.split_unit_at_deployment("U_TAC")
	_check("split returned a sibling id", sibling_id != "",
		"got %s" % sibling_id)
	_check("sibling exists in state.units", sibling_id in gs.state["units"])
	# Source kept m1..m5
	var src = gs.state["units"]["U_TAC"]
	_check("source has 5 models after split",
		src["models"].size() == 5,
		"got %d" % src["models"].size())
	# Sibling has m1..m5 (renumbered)
	var sib = gs.state["units"][sibling_id]
	_check("sibling has 5 models",
		sib["models"].size() == 5,
		"got %d" % sib["models"].size())
	_check("sibling models renumbered to m1..m5",
		sib["models"][0]["id"] == "m1" and sib["models"][4]["id"] == "m5")
	# Cross-link metadata
	_check("source split_from_combat_squads=true",
		src.get("split_from_combat_squads", false) == true)
	_check("sibling split_sibling_of references source",
		sib.get("split_sibling_of", "") == "U_TAC")
	_check("source display_name has 'Combat Squad A'",
		"Combat Squad A" in src.get("meta", {}).get("display_name", ""))
	_check("sibling display_name has 'Combat Squad B'",
		"Combat Squad B" in sib.get("meta", {}).get("display_name", ""))

func _test_split_rejects_no_ability() -> void:
	print("\n-- T-026/B: rejects unit lacking Combat Squads / Patrol Squad ability --")
	var gs = root.get_node("GameState")
	gs.state = _make_tactical_squad_state(10, false, 0)
	var sibling_id = gs.split_unit_at_deployment("U_TAC")
	_check("split returns '' when ability missing",
		sibling_id == "")

func _test_split_rejects_wrong_size() -> void:
	print("\n-- T-026/C: rejects unit not exactly 10 models --")
	var gs = root.get_node("GameState")
	gs.state = _make_tactical_squad_state(8, true, 0)
	var sibling_id = gs.split_unit_at_deployment("U_TAC")
	_check("split returns '' for 8-model unit",
		sibling_id == "")

func _test_split_rejects_already_deployed() -> void:
	print("\n-- T-026/D: rejects unit not in UNDEPLOYED status --")
	var gs = root.get_node("GameState")
	# UNDEPLOYED is enum 0; 2 = MOVED is "already on board"
	gs.state = _make_tactical_squad_state(10, true, 2)
	var sibling_id = gs.split_unit_at_deployment("U_TAC")
	_check("split returns '' when already deployed",
		sibling_id == "")

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
