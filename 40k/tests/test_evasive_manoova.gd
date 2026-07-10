extends SceneTree

# Speedwaaagh! EVASIVE MANOOVA: remove the target Speed Freeks/Trukk unit from
# the battlefield and place it into Strategic Reserves (it can arrive again on a
# later turn via the normal reserves flow). Mirrors the aircraft return-to-
# reserves pattern (GameState.return_aircraft_to_reserves).
#
# Run: godot --headless --path 40k --script tests/test_evasive_manoova.gd

var _passed = 0
var _failed = 0


func _initialize():
	await create_timer(0.2).timeout
	_run()
	print("\n=== RESULTS: %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _check(label: String, cond: bool) -> void:
	if cond:
		print("[PASS] %s" % label)
		_passed += 1
	else:
		print("[FAIL] %s" % label)
		_failed += 1


func _run():
	var SM = root.get_node("StratagemManager")
	var GS = root.get_node("GameState")
	if SM == null or GS == null:
		_check("autoloads present", false)
		return

	# A Speed Freeks unit deployed on the board.
	GS.state["units"] = {
		"U_BUGGY": {"id": "U_BUGGY", "owner": 1, "status": GS.UnitStatus.DEPLOYED,
			"meta": {"name": "Rukkatrukk Squigbuggy", "keywords": ["SPEED FREEKS", "VEHICLE"]},
			"flags": {}, "models": [{"id": "m0", "position": {"x": 100.0, "y": 100.0},
				"alive": true, "wounds": 6, "current_wounds": 6}]},
	}
	_check("precondition: unit starts DEPLOYED, not in reserves",
		GS.state["units"]["U_BUGGY"]["status"] == GS.UnitStatus.DEPLOYED and GS.get_reserves_for_player(1).is_empty())

	var strat = {"name": "EVASIVE MANOOVA", "effects": [{"type": "custom:evasive_manoova"}]}
	var diffs = SM._apply_stratagem_effects("test_em", "U_BUGGY", strat, {})
	_check("apply produced diffs", not diffs.is_empty())
	GS.apply_state_changes(diffs)

	var u = GS.state["units"]["U_BUGGY"]
	_check("unit status is now IN_RESERVES", u["status"] == GS.UnitStatus.IN_RESERVES)
	_check("reserve_type is strategic_reserves", str(u.get("reserve_type", "")) == "strategic_reserves")
	_check("unit is listed in player 1's Strategic Reserves", "U_BUGGY" in GS.get_reserves_for_player(1))

	# End-of-phase clear must NOT pull it back onto the board.
	SM.stratagems["test_em"] = strat
	SM._clear_stratagem_flags("U_BUGGY", "test_em")
	_check("unit stays in reserves after end-of-phase clear",
		GS.state["units"]["U_BUGGY"]["status"] == GS.UnitStatus.IN_RESERVES)
