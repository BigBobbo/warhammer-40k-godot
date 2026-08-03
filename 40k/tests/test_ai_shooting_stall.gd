extends SceneTree

# AI SHOOTING STALL (reported 2026-08-03): the AI's shooting phase froze
# mid-activation after the human defender took a while to roll saves. The AI
# "thinking" indicator flashed every watchdog tick forever and the phase never
# advanced.
#
# Three defects combined:
#   A) ShootingPhase.get_available_actions() kept offering RESOLVE_SHOOTING /
#      SELECT_SHOOTER / SKIP_UNIT / END_SHOOTING while an attack was paused on
#      the defender's saves (active_shooter_id + confirmed_assignments are still
#      populated). Taking any of them re-entered the paused activation —
#      RESOLVE_SHOOTING re-rolled the whole attack behind the defender's back.
#   B) _process_apply_saves' single-weapon completion path never cleared
#      pending_save_data, which is the flag AIPlayer._human_defender_window_pending()
#      reads — so the AI kept waiting for saves that were already applied.
#   C) AIPlayer's human-decision gates had no escape hatch: every gate returns
#      before _current_phase_actions is touched, so MAX_ACTIONS_PER_PHASE could
#      never rescue a gate that latched.
#
# Usage: godot --headless --path . -s tests/test_ai_shooting_stall.gd

var passed := 0
var failed := 0
var done := false

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	create_timer(0.2).timeout.connect(_run)

func _board() -> Dictionary:
	var shooters = []
	for i in range(6):
		shooters.append({"id": "ms%d" % i, "position": {"x": 100.0, "y": float(i * 40)},
			"base_mm": 32, "base_type": "circular", "alive": true,
			"wounds": 2, "current_wounds": 2})
	var targets = []
	for i in range(6):
		targets.append({"id": "mt%d" % i, "position": {"x": 200.0, "y": float(i * 40)},
			"base_mm": 40, "base_type": "circular", "alive": true,
			"wounds": 1, "current_wounds": 1, "stats": {"toughness": 3, "save": 5}})
	return {
		"meta": {"active_player": 2, "turn_number": 1, "battle_round": 2, "phase": 8},
		"players": {"1": {"cp": 5}, "2": {"cp": 5}},
		"units": {
			"U_AI_SHOOTER": {"id": "U_AI_SHOOTER", "owner": 2, "status": 3,
				"meta": {"name": "AI Shootas", "keywords": ["INFANTRY"],
					"stats": {"toughness": 5, "save": 5, "wounds": 2}},
				"models": shooters, "flags": {}},
			"U_HUMAN_TARGET": {"id": "U_HUMAN_TARGET", "owner": 1, "status": 3,
				"meta": {"name": "Human Guard", "keywords": ["INFANTRY"],
					"stats": {"toughness": 3, "save": 5, "wounds": 1}},
				"models": targets, "flags": {}},
		}
	}

func _action_types(phase) -> Array:
	var out := []
	for a in phase.get_available_actions():
		var t = str(a.get("type", ""))
		if t != "" and not t in out:
			out.append(t)
	return out

func _run():
	if done:
		return
	done = true
	print("\n=== test_ai_shooting_stall ===\n")

	GameConstants.edition = 11
	var gs = root.get_node_or_null("GameState")
	var ai = root.get_node_or_null("AIPlayer")
	var re = root.get_node_or_null("RulesEngine")
	_check("GameState / AIPlayer / RulesEngine autoloads present",
		gs != null and ai != null and re != null)
	if gs == null or ai == null or re == null:
		_finish(); return

	gs.state = _board()
	ai.configure({1: "HUMAN", 2: "AI"})
	_check("player 2 is the AI, player 1 is the human defender",
		ai.is_ai_player(2) and not ai.is_ai_player(1))

	var phase = load("res://phases/ShootingPhase.gd").new()
	get_root().add_child(phase)
	phase.enter_phase(gs.state)
	var pm = root.get_node_or_null("PhaseManager")
	if pm:
		pm.current_phase_instance = phase

	var saves_seen := []
	phase.saves_required.connect(func(sdl): saves_seen.append(sdl))

	print("-- the AI's atomic SHOOT pauses for the human defender --")
	# 40 attacks at BS3+ into T3 Sv5+ makes "at least one wound" effectively
	# certain; the seed retry keeps the test deterministic anyway (a zero-wound
	# roll would skip the pause entirely and prove nothing).
	var shoot_result := {}
	for seed_try in [1234, 77, 909, 31337]:
		shoot_result = phase.execute_action({
			"type": "SHOOT", "actor_unit_id": "U_AI_SHOOTER", "player": 2,
			"payload": {"rng_seed": seed_try, "assignments": [{
				"weapon_id": "bolt_rifle", "target_unit_id": "U_HUMAN_TARGET",
				"model_ids": ["ms0", "ms1", "ms2", "ms3", "ms4", "ms5"],
				"attacks_override": 40}]}})
		if not saves_seen.is_empty():
			break
		# No wounds this seed — reset the activation and try the next one.
		gs.state = _board()
		phase.enter_phase(gs.state)
	_check("SHOOT succeeded", shoot_result.get("success", false), str(shoot_result.get("error", "")))
	_check("SHOOT paused for the defender (saves_required emitted)", saves_seen.size() >= 1)
	_check("a save batch is pending", phase.pending_save_data.size() == 1)
	if saves_seen.is_empty():
		_check("reached a wounds result within 4 seeds", false)
		_finish(); return

	print("\n-- A) DEFENDER CONTROL LOCK: nothing may re-enter the paused attack --")
	var during := _action_types(phase)
	_check("only APPLY_SAVES is offered while saves are pending",
		during == ["APPLY_SAVES"], str(during))
	for blocked in ["RESOLVE_SHOOTING", "SELECT_SHOOTER", "SKIP_UNIT", "CONFIRM_TARGETS", "SHOOT"]:
		var v = phase.validate_action({"type": blocked, "actor_unit_id": "U_AI_SHOOTER", "player": 2})
		_check("%s is rejected while saves are pending" % blocked,
			not v.get("valid", true), str(v.get("errors", [])))
	# The escape hatch stays open for the player.
	_check("END_SHOOTING is NOT save-locked (player's manual escape hatch)",
		not "END_SHOOTING" in phase._SAVE_LOCKED_ACTIONS)
	_check("AI._human_defender_window_pending() reports the human defender",
		ai._human_defender_window_pending() == 1)

	print("\n-- B) after APPLY_SAVES the pending batch is gone and the AI is free --")
	var sd = saves_seen[0][0]
	var batch = re.resolve_allocation_batch_11e(sd, [], gs.state, re.RNGService.new(99), {})
	var summary = {
		"is_allocation_11e": true,
		"target_unit_id": sd.get("target_unit_id", ""),
		"saves_passed": batch.get("saves_passed", 0),
		"saves_failed": batch.get("saves_failed", 0),
		"casualties": batch.get("casualties", 0),
		"diffs": batch.get("diffs", []),
		"order_used": batch.get("order_used", []),
		"dice": [],
	}
	var apply_result = phase.execute_action({"type": "APPLY_SAVES", "player": 1,
		"payload": {"save_results_list": [summary]}})
	_check("APPLY_SAVES succeeded", apply_result.get("success", false), str(apply_result.get("error", "")))
	_check("pending_save_data drained", phase.pending_save_data.is_empty(),
		"size=%d" % phase.pending_save_data.size())
	_check("AI is no longer gated on the defender", ai._human_defender_window_pending() == 0)
	var after := _action_types(phase)
	_check("the AI has real actions again", after.size() > 0 and after != ["APPLY_SAVES"], str(after))

	print("\n-- C) AIPlayer stall breaker is wired --")
	_check("gate tracking helpers exist",
		ai.has_method("_note_gate_block") and ai.has_method("_attempt_gate_recovery")
		and ai.has_method("_clear_gate_block"))
	_check("recovery skips while the defender's dialog is genuinely on screen",
		ai.has_method("_defender_dialog_on_screen"))
	var secondary = root.get_node_or_null("SecondaryMissionManager")
	_check("SecondaryMissionManager can re-emit a dropped interaction window",
		secondary != null and secondary.has_method("reemit_pending_interactions"))
	# One held gate warns and then escalates instead of freezing silently.
	ai._gate_reason = ""
	ai._note_gate_block("defender_window", "unit test")
	_check("first block records the gate", ai._gate_reason == "defender_window")
	ai._gate_since_msec = Time.get_ticks_msec() - int(ai.GATE_WARN_SEC * 1000.0) - 1000
	ai._note_gate_block("defender_window", "unit test")
	_check("held past GATE_WARN_SEC escalates to the warn state", ai._gate_recoveries >= 1)
	ai._clear_gate_block()
	_check("_clear_gate_block resets the tracker",
		ai._gate_reason == "" and ai._gate_recoveries == 0)

	print("\n-- D) source pins for the two one-shot-signal recoveries --")
	var sc_src = FileAccess.get_file_as_string("res://scripts/ShootingController.gd")
	_check("ShootingController releases the save guard on a deduped emission",
		"processing_saves_signal = false\n\t\t\treturn" in sc_src
		or "DUPLICATE DETECTED" in sc_src and "processing_saves_signal = false" in sc_src)
	_check("ShootingController self-heals a stale save guard with no overlay",
		"STALE SAVE GUARD" in sc_src)
	var sp_src = FileAccess.get_file_as_string("res://phases/ShootingPhase.gd")
	_check("ShootingPhase has the DEFENDER CONTROL LOCK",
		"DEFENDER CONTROL LOCK" in sp_src and "_SAVE_LOCKED_ACTIONS" in sp_src)

	_finish()

func _finish():
	print("\n=== %d passed, %d failed ===\n" % [passed, failed])
	quit(1 if failed > 0 else 0)
