extends SceneTree

# 06_SYNTHESIS launch-blocker #12 / issue #377: Per Chapter Approved 2025-26,
# the defender deploys first.
#
# `RollOffPhase` writes meta.attacker and meta.defender after the pre-
# deployment roll-off. `TurnManager._handle_deployment_phase_start` now
# reads meta.defender and seeds the deployment alternation with the
# defender (falling back to 1 if the field is missing or invalid).
#
# Pre-issue #377 the alternation always seated P1 first regardless of
# who won the roll-off. This pin asserts the defender-aware path is
# wired in both the writer and the reader and drives a live state
# transition to confirm.
#
# Usage: godot --headless --path . -s tests/test_t012_defender_deploys_first_pin.gd

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

func _read(path: String) -> String:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t = f.get_as_text()
	f.close()
	return t

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_t012_defender_deploys_first_pin ===\n")
	_test_roll_off_phase_writes_meta()
	_test_turn_manager_reads_defender()
	_test_live_handle_deployment_p2_defender()
	_test_live_handle_deployment_p1_defender()
	_finish()

func _test_roll_off_phase_writes_meta() -> void:
	print("\n-- A: RollOffPhase writes meta.attacker and meta.defender --")
	var src = _read("res://phases/RollOffPhase.gd")
	_check("RollOffPhase.gd readable", not src.is_empty())
	_check("writes meta.attacker",
		"\"path\": \"meta.attacker\"" in src or "meta.attacker" in src)
	_check("writes meta.defender",
		"\"path\": \"meta.defender\"" in src or "meta.defender" in src)
	_check("uses 3 - first_turn_player to compute defender",
		"3 - _first_turn_player" in src or "3 - first_turn_player" in src,
		"defender = the OTHER player from whoever won the roll-off")

func _test_turn_manager_reads_defender() -> void:
	print("\n-- B: TurnManager reads meta.defender at deployment start --")
	var src = _read("res://autoloads/TurnManager.gd")
	_check("TurnManager.gd readable", not src.is_empty())
	_check("_handle_deployment_phase_start reads meta.defender",
		"meta\", {}).get(\"defender\"" in src or "meta\").get(\"defender\"" in src,
		"hard-coded P1 first would not read meta.defender at all")
	_check("attacker derived as 3 - defender",
		"3 - defender" in src,
		"attacker should fall through if defender has no undeployed units")
	_check("_set_active_player(defender) called when defender has undeployed units",
		"_set_active_player(defender)" in src)

func _test_live_handle_deployment_p2_defender() -> void:
	print("\n-- C: live drive — meta.defender=2 → P2 seated first --")
	var tm = root.get_node_or_null("TurnManager")
	var gs = root.get_node_or_null("GameState")
	if tm == null or gs == null:
		_check("TurnManager + GameState reachable", false)
		return
	_check("TurnManager + GameState reachable", true)
	# Stash, then inject a controllable state where P2 is the defender
	var prev = gs.state.duplicate(true)
	gs.state["meta"] = gs.state.get("meta", {})
	gs.state["meta"]["defender"] = 2
	gs.state["meta"]["attacker"] = 1
	gs.state["meta"]["active_player"] = 1  # baseline; expect this to flip to 2
	# Inject undeployed units for both players so the alternation has work to do
	gs.state["units"] = {
		"U_P1_UNIT": {"id": "U_P1_UNIT", "owner": 1, "status": GameStateData.UnitStatus.UNDEPLOYED, "models": [{"id": "m1", "alive": true, "position": null}]},
		"U_P2_UNIT": {"id": "U_P2_UNIT", "owner": 2, "status": GameStateData.UnitStatus.UNDEPLOYED, "models": [{"id": "m1", "alive": true, "position": null}]},
	}
	tm._handle_deployment_phase_start()
	_check("active_player is 2 (defender)",
		gs.get_active_player() == 2,
		"got %d" % gs.get_active_player())
	gs.state = prev

func _test_live_handle_deployment_p1_defender() -> void:
	print("\n-- D: live drive — meta.defender=1 → P1 seated first --")
	var tm = root.get_node("TurnManager")
	var gs = root.get_node("GameState")
	var prev = gs.state.duplicate(true)
	gs.state["meta"] = gs.state.get("meta", {})
	gs.state["meta"]["defender"] = 1
	gs.state["meta"]["attacker"] = 2
	gs.state["meta"]["active_player"] = 2
	gs.state["units"] = {
		"U_P1_UNIT": {"id": "U_P1_UNIT", "owner": 1, "status": GameStateData.UnitStatus.UNDEPLOYED, "models": [{"id": "m1", "alive": true, "position": null}]},
		"U_P2_UNIT": {"id": "U_P2_UNIT", "owner": 2, "status": GameStateData.UnitStatus.UNDEPLOYED, "models": [{"id": "m1", "alive": true, "position": null}]},
	}
	tm._handle_deployment_phase_start()
	_check("active_player is 1 (defender)",
		gs.get_active_player() == 1,
		"got %d" % gs.get_active_player())
	gs.state = prev

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
