extends SceneTree

# ISS-065 (11e 08.03 + Starting Strength pg 86): a unit takes a
# battle-shock test if it is currently battle-shocked OR "at, or below,
# half-strength". The "AT exactly half-strength" trigger was previously
# omitted. Verifies the rule math (incl. the rule that an odd starting
# strength can NEVER be at half-strength) and that the real CommandPhase
# queues an at-half unit at edition 11 but not at edition 10.
#
# Usage: godot --headless --path . -s tests/test_iss065_at_half_battleshock.gd

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

func _multi(total: int, alive: int) -> Dictionary:
	var models := []
	for i in range(total):
		models.append({"id": "m%d" % i, "alive": i < alive, "wounds": 1,
			"current_wounds": (1 if i < alive else 0), "base_mm": 32, "base_type": "circular"})
	return {"models": models}

func _single(maxw: int, cur: int) -> Dictionary:
	return {"models": [{"id": "m0", "alive": cur > 0, "wounds": maxw, "current_wounds": cur,
		"base_mm": 32, "base_type": "circular"}]}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss065_at_half_battleshock ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	if gs == null or pm == null:
		_check("autoloads", false); _finish(); return
	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition

	print("-- is_at_half_strength: multi-model (even start) --")
	_check("10/10 (full): not at half", not gs.is_at_half_strength(_multi(10, 10)))
	_check("6/10: not at half (it is below)", not gs.is_at_half_strength(_multi(10, 6)))
	_check("5/10: AT half", gs.is_at_half_strength(_multi(10, 5)))
	_check("4/10: not at half (it is below)", not gs.is_at_half_strength(_multi(10, 4)))
	_check("0/10 (destroyed): not at half", not gs.is_at_half_strength(_multi(10, 0)))

	print("\n-- odd starting strength can NEVER be at half (rulebook caveat) --")
	_check("5/9: NOT at half (9 is odd)", not gs.is_at_half_strength(_multi(9, 5)))
	_check("4/9: NOT at half (odd) and IS below half", not gs.is_at_half_strength(_multi(9, 4)) and gs.is_below_half_strength(_multi(9, 4)))

	print("\n-- single-model (wounds) --")
	_check("W2 @ 1: AT half", gs.is_at_half_strength(_single(2, 1)))
	_check("W4 @ 2: AT half", gs.is_at_half_strength(_single(4, 2)))
	_check("W3 @ 1: NOT at half (odd W) but IS below half",
		not gs.is_at_half_strength(_single(3, 1)) and gs.is_below_half_strength(_single(3, 1)))
	_check("W4 @ 3: not at half (above)", not gs.is_at_half_strength(_single(4, 3)))

	print("\n-- combined (pg-86 Captain + 5 Intercessors, starting 6) --")
	# Build a bodyguard of 5 Intercessors + an attached Captain (1).
	gs.state["units"] = {
		"U_BG": {"id": "U_BG", "owner": 1, "status": 2, "flags": {},
			"attachment_data": {"attached_characters": ["U_CAP"]},
			"meta": {"name": "Intercessors", "keywords": ["INFANTRY"], "stats": {"wounds": 2}},
			"models": _multi(5, 5).models},
		"U_CAP": {"id": "U_CAP", "owner": 1, "status": 2, "flags": {}, "attached_to": "U_BG",
			"meta": {"name": "Captain", "keywords": ["CHARACTER", "INFANTRY"], "stats": {"wounds": 4}},
			"models": _single(4, 4).models},
	}
	# Full (6/6): not at half.
	_check("combined 6/6: not at half", not gs.is_at_half_strength_combined("U_BG"))
	# 3 Intercessors destroyed -> 2 Int + 1 Cap = 3/6 alive -> AT half.
	for i in range(3):
		gs.state["units"]["U_BG"]["models"][i]["alive"] = false
	_check("combined: 3 Intercessors destroyed -> AT half (3/6)", gs.is_at_half_strength_combined("U_BG"))
	_check("combined at-3/6: NOT below half", not gs.is_below_half_strength_combined("U_BG"))
	# 4 destroyed -> 1 Int + 1 Cap = 2/6 -> below half (not at).
	gs.state["units"]["U_BG"]["models"][3]["alive"] = false
	_check("combined: 4 Intercessors destroyed -> below half, not at (2/6)",
		gs.is_below_half_strength_combined("U_BG") and not gs.is_at_half_strength_combined("U_BG"))

	print("\n-- real CommandPhase queues an AT-half unit at edition 11 only --")
	gs.state = prev_state.duplicate(true)
	gs.state["units"] = {
		"U_HALF": {"id": "U_HALF", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "HalfMob", "keywords": ["INFANTRY"], "stats": {}}, "models": _multi(10, 5).models},
		"U_BELOW": {"id": "U_BELOW", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "BelowMob", "keywords": ["INFANTRY"], "stats": {}}, "models": _multi(10, 4).models},
		"U_FULL": {"id": "U_FULL", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "FullMob", "keywords": ["INFANTRY"], "stats": {}}, "models": _multi(10, 10).models},
		"U_ODD": {"id": "U_ODD", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "OddMob", "keywords": ["INFANTRY"], "stats": {}}, "models": _multi(9, 5).models},
	}
	gs.state["meta"]["active_player"] = 1
	pm.transition_to_phase(6)  # COMMAND
	var cp = pm.get_current_phase_instance()

	GameConstants.edition = 11
	cp._identify_units_needing_tests()
	var need11 = cp._units_needing_test.duplicate()
	_check("e11: AT-half unit queued", "U_HALF" in need11, str(need11))
	_check("e11: below-half unit queued", "U_BELOW" in need11)
	_check("e11: full unit NOT queued", not ("U_FULL" in need11))
	_check("e11: odd-9-at-5 unit NOT queued (cannot be at half, not below)", not ("U_ODD" in need11))

	GameConstants.edition = 10
	cp._identify_units_needing_tests()
	var need10 = cp._units_needing_test.duplicate()
	_check("e10: AT-half unit NOT queued (10e below-half only)", not ("U_HALF" in need10), str(need10))
	_check("e10: below-half unit still queued", "U_BELOW" in need10)

	gs.state = prev_state
	GameConstants.edition = prev_edition
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
