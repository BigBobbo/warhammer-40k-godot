extends SceneTree

# Disembark → move flow (11e 18.04 tactical disembark).
#
# Part A — the mechanic behind the UX fix: when a unit disembarks from a
#   transport that HAS NOT moved, it is selected to make a normal/advance move
#   (movement_active is set, `moved` is not). Pressing Confirm Move (0")
#   immediately flags it `moved` and ends the move — the trap the new
#   PostDisembarkMoveDialog exists to make obvious. (The dialog itself is a UI
#   affordance, covered by tests/scenarios/sp/disembark_move_prompt.json.)
#
# Part B — the DisembarkController positions fix: for a unit with casualties
#   interspersed, _complete_disembark() must emit SLOT-aligned positions (one
#   per model slot) so every ALIVE model receives its placed position. Emitting
#   ALIVE-ordered positions shifted them onto the wrong models and left the tail
#   unplaced, which broke coherency at Confirm Move.
#
# Usage: godot --headless --path . -s tests/test_disembark_move_flow.gd

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
	create_timer(0.1).timeout.connect(_run)

# -- Part A state fixture: 1-model unit embarked in an unmoved transport --
func _setup_state() -> void:
	var gs = root.get_node("GameState")
	gs.state = {
		"meta": {"phase": GameStateData.Phase.MOVEMENT, "active_player": 1, "battle_round": 1, "turn_number": 1},
		"board": {"size": {"width": 1760, "height": 2400}, "deployment_zones": []},
		"units": {
			"U_BOYZ": {
				"id": "U_BOYZ", "owner": 1,
				"status": GameStateData.UnitStatus.DEPLOYED,
				"embarked_in": "U_TRUKK", "flags": {},
				"meta": {"name": "Boyz", "keywords": ["INFANTRY", "ORKS"], "stats": {"move": 6, "wounds": 1}},
				"models": [{"id": "m1", "alive": true, "current_wounds": 1, "wounds": 1,
					"base_mm": 32, "base_type": "circular", "position": null}],
			},
			"U_TRUKK": {
				"id": "U_TRUKK", "owner": 1,
				"status": GameStateData.UnitStatus.DEPLOYED, "flags": {},
				"transport_data": {"capacity": 22, "embarked_units": ["U_BOYZ"]},
				"meta": {"name": "Trukk", "keywords": ["VEHICLE", "TRANSPORT"], "stats": {"move": 12, "wounds": 10}},
				"models": [{"id": "t1", "alive": true, "current_wounds": 10, "wounds": 10,
					"base_mm": 100, "base_type": "circular", "position": {"x": 800, "y": 800}}],
			},
		},
		"players": {"1": {"cp": 3, "vp": 0}, "2": {"cp": 3, "vp": 0}},
	}

func _run():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_disembark_move_flow (edition 11) ===\n")
	GameConstants.edition = 11
	await _test_part_a()
	_test_part_b()
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_part_a() -> void:
	print("-- Part A: tactical disembark offers a move; Confirm Move (0\") ends it --")
	_setup_state()
	var pm = root.get_node("PhaseManager")
	pm.transition_to_phase(GameStateData.Phase.MOVEMENT)
	await process_frame
	await process_frame
	var phase = pm.current_phase_instance

	var r1 = phase.execute_action({"type": "CONFIRM_DISEMBARK", "actor_unit_id": "U_BOYZ",
		"payload": {"positions": [{"x": 800, "y": 680}], "can_setup_tactical": true}})
	_check("CONFIRM_DISEMBARK succeeds", r1.get("success", false), str(r1.get("error", "")))
	await process_frame
	await process_frame

	var boyz = root.get_node("GameState").get_unit("U_BOYZ")
	_check("unit is off the transport", boyz.get("embarked_in", null) == null)
	_check("tactical disembark offers a move (movement_active, not yet moved)",
		boyz.get("flags", {}).get("movement_active", false) and not boyz.get("flags", {}).get("moved", false),
		str(boyz.get("flags", {})))
	_check("the offered move is in active_moves", phase.active_moves.has("U_BOYZ"))

	# Confirm Move with no staged movement — the trap the dialog guards against.
	var r2 = phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_BOYZ", "payload": {}})
	_check("CONFIRM_UNIT_MOVE succeeds", r2.get("success", false), str(r2.get("error", "")))
	await process_frame
	boyz = root.get_node("GameState").get_unit("U_BOYZ")
	_check("after Confirm Move the unit is flagged moved (move consumed)",
		boyz.get("flags", {}).get("moved", false))

func _test_part_b() -> void:
	print("\n-- Part B: DisembarkController emits SLOT-aligned positions (casualties interspersed) --")
	# Unit of 10 slots, 5 alive (m1,m4,m5 style dead interspersed): alive at
	# indices 1,2,5,8,9 — the exact shape that used to misplace models.
	var alive_flags := [false, true, true, false, false, true, false, false, true, true]
	var models := []
	for i in range(alive_flags.size()):
		models.append({"id": "m%d" % (i + 1), "alive": alive_flags[i],
			"base_mm": 32, "base_type": "circular", "position": null})

	var dc = load("res://scripts/DisembarkController.gd").new()
	root.add_child(dc)
	dc.unit_id = "U_CARGO"
	dc.unit_data = {"id": "U_CARGO", "owner": 1, "models": models,
		"meta": {"keywords": ["INFANTRY"]}}
	# ALIVE-ordered placements (index k == k-th alive model), a tight coherent cluster.
	var placements := [Vector2(800, 680), Vector2(830, 680), Vector2(860, 680),
		Vector2(815, 710), Vector2(845, 710)]
	dc.model_positions = placements.duplicate()
	dc.model_rotations = [0.0, 0.0, 0.0, 0.0, 0.0]
	dc.current_model_idx = 5

	var captured := {"positions": null}
	dc.disembark_completed.connect(func(_uid, positions): captured["positions"] = positions)
	dc._complete_disembark()

	var emitted = captured["positions"]
	_check("disembark_completed fired", emitted != null)
	if emitted == null:
		return
	_check("emits one position per MODEL SLOT (not just alive count)",
		emitted.size() == models.size(), "got %d, want %d" % [emitted.size(), models.size()])

	# Each ALIVE slot must carry its k-th placement; dead slots are placeholders.
	var k := 0
	var all_aligned := true
	var detail := ""
	for i in range(models.size()):
		if alive_flags[i]:
			var want: Vector2 = placements[k]
			var got: Vector2 = emitted[i]
			if not got.is_equal_approx(want):
				all_aligned = false
				detail += "slot %d: got %s want %s; " % [i, str(got), str(want)]
			k += 1
	_check("every alive model receives ITS OWN placed position (slot-aligned)", all_aligned, detail)
