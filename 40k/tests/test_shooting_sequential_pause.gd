extends SceneTree

# Anchor for the sequential-resolution tail refactor (_resolve_next_weapon).
# Drives ShootingPhase._resolve_next_weapon() directly for:
#   - a wounds case  -> result carries save_data_list, resolution_state.awaiting_saves
#   - a no-wounds/miss case -> result carries sequential_pause, completed_weapons grows
# These structural invariants must hold identically before and after extracting
# the shared tail helper. RNG is not seeded here; we assert on shape, not values.
#
# Usage: godot --headless --path . -s tests/test_shooting_sequential_pause.gd

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
	root.connect("ready", Callable(self, "_run"))
	create_timer(0.1).timeout.connect(_run)

func _board(target_toughness: int, target_save: int, attacks: int) -> Dictionary:
	var sm = []
	for i in range(3):
		sm.append({"id": "ms%d" % i, "position": {"x": 0, "y": float(i*35)}, "base_mm": 32,
			"base_type": "circular", "alive": true, "wounds": 2, "current_wounds": 2})
	var tm = []
	for i in range(8):
		tm.append({"id": "mt%d" % i, "position": {"x": 40, "y": float(i*35)}, "base_mm": 32,
			"base_type": "circular", "alive": true, "wounds": 1, "current_wounds": 1,
			"stats": {"toughness": target_toughness, "save": target_save}})
	return {
		"meta": {"active_player": 1, "turn_number": 1},
		"players": {"1": {"cp": 5}, "2": {"cp": 5}},
		"units": {
			"U_S": {"id": "U_S", "owner": 1, "meta": {"name": "Shooters", "keywords": ["INFANTRY"],
				"stats": {"toughness": 4, "save": 3}}, "models": sm, "flags": {}},
			"U_T": {"id": "U_T", "owner": 2, "meta": {"name": "Targets", "keywords": ["INFANTRY"],
				"stats": {"toughness": target_toughness, "save": target_save}}, "models": tm, "flags": {}}
		}
	}

func _assign(attacks: int) -> Dictionary:
	return {"weapon_id": "bolt_rifle", "target_unit_id": "U_T",
		"model_ids": ["ms0", "ms1", "ms2"], "attacks_override": attacks}

func _new_phase(board: Dictionary, order: Array):
	var ShootingPhaseScript = load("res://phases/ShootingPhase.gd")
	var phase = ShootingPhaseScript.new()
	# game_state_snapshot is a read-only property backed by GameState.state, so we
	# must load the board into the GameState autoload for get_unit() to see it.
	root.get_node("GameState").state = board
	# Add to the tree so the phase's get_node_or_null("/root/StratagemManager") etc. resolve.
	get_root().add_child(phase)
	phase.active_shooter_id = "U_S"
	phase.confirmed_assignments = order.duplicate(true)
	phase.resolution_state = {
		"mode": "sequential",
		"weapon_order": order.duplicate(true),
		"current_index": 0,
		"completed_weapons": [],
		"awaiting_saves": false
	}
	return phase

func _has_ctx(dice: Array, ctx: String) -> bool:
	for d in dice:
		if d.get("context", "") == ctx:
			return true
	return false

func _run():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_shooting_sequential_pause ===\n")
	if root.get_node_or_null("RulesEngine") == null:
		_check("RulesEngine autoload reachable", false)
		_finish(); return

	# --- Wounds case: T1 Sv6 vs 30 attacks -> guaranteed wounds -> saves pause ---
	var wounds_ok := false
	for attempt in range(3):
		var board = _board(1, 6, 40)
		var order = [_assign(40), _assign(40)]  # two weapons
		var phase = _new_phase(board, order)
		var res = phase._resolve_next_weapon()
		var sdl = res.get("save_data_list", [])
		if not sdl.is_empty():
			wounds_ok = true
			_check("wounds: result.success", res.get("success", false))
			_check("wounds: save_data_list present", not sdl.is_empty())
			_check("wounds: awaiting_saves set", phase.resolution_state.get("awaiting_saves", false))
			_check("wounds: dice has to_hit", _has_ctx(res.get("dice", []), "to_hit"))
			_check("wounds: dice has to_wound", _has_ctx(res.get("dice", []), "to_wound"))
			_check("wounds: sequence_context stamped on save_data",
				sdl[0].has("sequence_context") and sdl[0]["sequence_context"].get("total_weapons", 0) == 2)
			phase.queue_free()
			break
		phase.queue_free()
	_check("wounds: reached a wounds result within 3 attempts", wounds_ok)

	# --- No-wounds case: T12 Sv2 vs 1 attack -> likely miss/no-wound -> sequential_pause ---
	var miss_ok := false
	for attempt in range(6):
		var board2 = _board(12, 2, 1)
		var order2 = [_assign(1), _assign(1)]
		var phase2 = _new_phase(board2, order2)
		var res2 = phase2._resolve_next_weapon()
		if res2.get("sequential_pause", false):
			miss_ok = true
			_check("no-wounds: result.success", res2.get("success", false))
			_check("no-wounds: sequential_pause=true", res2.get("sequential_pause", false))
			_check("no-wounds: completed_weapons grew", phase2.resolution_state.get("completed_weapons", []).size() >= 1)
			_check("no-wounds: current_index advanced", int(phase2.resolution_state.get("current_index", 0)) == 1)
			_check("no-wounds: remaining_weapons present", res2.has("remaining_weapons"))
			phase2.queue_free()
			break
		phase2.queue_free()
	_check("no-wounds: reached a sequential_pause within 6 attempts", miss_ok)

	# --- Staged progression: hits pause -> wounds pause -> saves ---
	var staged_ok := false
	for attempt in range(4):
		var board = _board(1, 6, 40)
		var order = [_assign(40)]  # single weapon so the tail leads to saves
		var phase = _new_phase(board, order)
		phase.resolution_state["mode"] = "sequential_staged"
		var r1 = phase._resolve_next_weapon()  # -> _staged_roll_hits
		if r1.get("staged_pause", "") != "hits":
			phase.queue_free(); continue
		_check("staged: first result is a hits pause", r1.get("staged_pause", "") == "hits")
		_check("staged: stage == hits_pending", phase.resolution_state.get("stage", "") == "hits_pending")
		_check("staged: to_hit emitted, no to_wound yet", _has_ctx(r1.get("dice", []), "to_hit") and not _has_ctx(r1.get("dice", []), "to_wound"))
		_check("staged: progress message names the weapon",
			str(r1.get("weapon_name", "")).length() > 0)
		var r2 = phase.process_action({"type": "CONTINUE_TO_WOUNDS"})
		# T1/Sv6 vs 40 attacks -> almost certainly wounds -> wounds pause
		if r2.get("staged_pause", "") == "wounds":
			staged_ok = true
			_check("staged: second result is a wounds pause", r2.get("staged_pause", "") == "wounds")
			_check("staged: stage == wounds_pending", phase.resolution_state.get("stage", "") == "wounds_pending")
			_check("staged: to_wound now present", _has_ctx(phase.resolution_state.get("staged_dice", []), "to_wound"))
			var r3 = phase.process_action({"type": "CONTINUE_TO_SAVES"})
			_check("staged: continue-to-saves yields save_data_list", not (r3.get("save_data_list", []) as Array).is_empty())
			_check("staged: awaiting_saves set after saves stage", phase.resolution_state.get("awaiting_saves", false))
			phase.queue_free()
			break
		phase.queue_free()
	_check("staged: reached hits->wounds->saves progression", staged_ok)

	# --- Staged Command Re-roll at the hit stage: spends CP, updates the roll ---
	var rr_board = _board(1, 6, 20)
	var rr_phase = _new_phase(rr_board, [_assign(20)])
	rr_phase.resolution_state["mode"] = "sequential_staged"
	var rr1 = rr_phase._resolve_next_weapon()
	var cp_before = root.get_node("StratagemManager").get_player_cp(1)
	if rr1.get("staged_pause", "") == "hits" and cp_before > 0:
		var rr_res = rr_phase.process_action({"type": "USE_SHOOTING_REROLL", "payload": {"stage": "hits", "die_index": 0}})
		_check("reroll: USE_SHOOTING_REROLL succeeded", rr_res.get("success", false), str(rr_res.get("error", "")))
		if rr_res.get("success", false):
			_check("reroll: CP was spent (1 CP)", root.get_node("StratagemManager").get_player_cp(1) == cp_before - 1,
				"before=%d after=%d" % [cp_before, root.get_node("StratagemManager").get_player_cp(1)])
			_check("reroll: a second re-roll is now unavailable (once per phase)",
				not rr_phase._shooting_reroll_available())
			var rr_res2 = rr_phase.process_action({"type": "USE_SHOOTING_REROLL", "payload": {"stage": "hits", "die_index": 1}})
			_check("reroll: second re-roll rejected (once per phase)", not rr_res2.get("success", true))
	else:
		print("    (reroll test skipped — no hits pause or no CP)")
	rr_phase.queue_free()

	# --- Staged guards: wrong-stage actions are rejected ---
	var gboard = _board(1, 6, 40)
	var gphase = _new_phase(gboard, [_assign(40)])
	gphase.resolution_state["mode"] = "sequential_staged"
	gphase._resolve_next_weapon()  # now at hits_pending
	var bad = gphase.process_action({"type": "CONTINUE_TO_SAVES"})  # illegal before wounds
	_check("staged: CONTINUE_TO_SAVES rejected at hits stage", not bad.get("success", true))
	gphase.queue_free()

	# --- Split-fire regression: APPLY_SAVES in sequential_staged mode must CONTINUE
	# the sequence (advance current_index, offer remaining weapons), not fall into
	# the single-weapon completion branch and drop the second assignment.
	# ("Shooting at two targets only rolls the first one" bug.)
	var sf_ok := false
	for attempt in range(4):
		var sf_board = _board(1, 6, 40)
		var sf_order = [_assign(40), _assign(40)]  # two staged weapons
		var sf_phase = _new_phase(sf_board, sf_order)
		sf_phase.resolution_state["mode"] = "sequential_staged"
		var s1 = sf_phase._resolve_next_weapon()
		if s1.get("staged_pause", "") != "hits":
			sf_phase.queue_free(); continue
		var s2 = sf_phase.process_action({"type": "CONTINUE_TO_WOUNDS"})
		if s2.get("staged_pause", "") != "wounds":
			sf_phase.queue_free(); continue
		var s3 = sf_phase.process_action({"type": "CONTINUE_TO_SAVES"})
		if (s3.get("save_data_list", []) as Array).is_empty():
			sf_phase.queue_free(); continue
		sf_ok = true
		# Defender resolves the batch (11e allocation summary shape, no casualties)
		var apply_res = sf_phase.process_action({"type": "APPLY_SAVES", "payload": {"save_results_list": [{
			"is_allocation_11e": true, "diffs": [], "casualties": 0,
			"saves_passed": 1, "saves_failed": 0, "order_used": []}]}})
		_check("split-fire: APPLY_SAVES succeeded", apply_res.get("success", false))
		_check("split-fire: result pauses for next weapon (sequential_pause)",
			apply_res.get("sequential_pause", false))
		_check("split-fire: current_index advanced to 1",
			int(sf_phase.resolution_state.get("current_index", -1)) == 1)
		_check("split-fire: remaining_weapons carries the 2nd assignment",
			(apply_res.get("remaining_weapons", []) as Array).size() == 1)
		_check("split-fire: mode still sequential_staged",
			sf_phase.resolution_state.get("mode", "") == "sequential_staged")
		# CONTINUE_SEQUENCE must be accepted in staged mode (validator regression)
		var cont = sf_phase.process_action({"type": "CONTINUE_SEQUENCE"})
		_check("split-fire: CONTINUE_SEQUENCE accepted in staged mode",
			cont.get("success", false), str(cont.get("errors", [])))
		_check("split-fire: weapon 2 begins at a hits pause",
			cont.get("staged_pause", "") == "hits")
		sf_phase.queue_free()
		break
	_check("split-fire: reached the APPLY_SAVES continuation within 4 attempts", sf_ok)

	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit()
