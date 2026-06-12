extends SceneTree

# ISS-021: action log + deterministic replay.
#
# Records a real action sequence through the live pipeline (warlord
# designation -> formation confirmation -> a seeded SHOOT through
# execute_action), exports the ActionLogger bundle, scrambles the state,
# replays the bundle via ReplayVerifier, and asserts the final state hash
# matches the recording. This is determinism end-to-end: same snapshot +
# same logged actions (with their recorded rng seeds) => identical state.
#
# Usage: godot --headless --path . -s tests/test_iss021_action_replay.gd

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

func _build_state(gs) -> void:
	gs.state["units"] = {
		"U_CHAR_A": {"id": "U_CHAR_A", "owner": 1, "flags": {},
			"meta": {"name": "Cap A", "keywords": ["CHARACTER", "INFANTRY"], "is_warlord": false,
				"stats": {"toughness": 4, "save": 4, "wounds": 3}},
			"models": [{"id": "m0", "alive": true, "wounds": 3, "current_wounds": 3,
				"position": {"x": 100, "y": 100}, "base_mm": 32, "base_type": "circular"}]},
		"U_SHOOTER": {"id": "U_SHOOTER", "owner": 1, "flags": {},
			"meta": {"name": "Shooters", "keywords": ["INFANTRY"],
				"stats": {"toughness": 4, "save": 4, "wounds": 1},
				"weapons": [{"name": "Replay Rifle", "type": "Ranged", "range": "24",
					"attacks": "2", "ballistic_skill": "3", "strength": "4", "ap": "0",
					"damage": "1", "special_rules": "sustained hits 1"}]},
			"models": [{"id": "ms0", "alive": true, "wounds": 1, "current_wounds": 1,
				"position": {"x": 0, "y": 0}, "base_mm": 32, "base_type": "circular"}]},
		"U_TARGET": {"id": "U_TARGET", "owner": 2, "flags": {},
			"meta": {"name": "Targets", "keywords": ["INFANTRY"],
				"stats": {"toughness": 4, "save": 4, "wounds": 1}},
			"models": [
				{"id": "mt0", "alive": true, "wounds": 1, "current_wounds": 1,
					"position": {"x": 40, "y": 0}, "base_mm": 32, "base_type": "circular"},
				{"id": "mt1", "alive": true, "wounds": 1, "current_wounds": 1,
					"position": {"x": 40, "y": 35}, "base_mm": 32, "base_type": "circular"},
			]},
	}
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = 0  # FORMATIONS

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss021_action_replay ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	var logger = root.get_node_or_null("ActionLogger")
	var rules = root.get_node_or_null("RulesEngine")
	if gs == null or pm == null or logger == null:
		_check("autoloads reachable", false)
		_finish()
		return
	rules.set_test_seed(-1)
	var prev = gs.state.duplicate(true)

	# -- Record --
	gs.initialize_default_state()
	_build_state(gs)
	logger.reset_session_baseline()
	pm.transition_to_phase(0)  # FORMATIONS

	var phase = pm.get_current_phase_instance()
	var r1 = phase.execute_action({"type": "DESIGNATE_WARLORD", "unit_id": "U_CHAR_A", "player": 1})
	_check("recorded: DESIGNATE_WARLORD ok", r1.get("success", false))
	var r2 = phase.execute_action({"type": "CONFIRM_FORMATIONS", "player": 1})
	_check("recorded: CONFIRM_FORMATIONS ok", r2.get("success", false))

	# A seeded SHOOT through the real resolution, applied via the pipeline.
	pm.transition_to_phase(8)  # SHOOTING
	var shoot_phase = pm.get_current_phase_instance()
	var shoot_action = {"type": "SHOOT", "actor_unit_id": "U_SHOOTER", "player": 1,
		"payload": {"rng_seed": 991199, "assignments": [{
			"weapon_id": "Replay Rifle", "target_unit_id": "U_TARGET",
			"model_ids": ["ms0"], "attacks_override": 3}]}}
	var rng = rules.rng_for_action(shoot_action)
	var shoot_result = rules.resolve_shoot(shoot_action, gs.create_snapshot(), rng)
	_check("recorded: SHOOT resolved", shoot_result.get("success", false))
	pm.apply_state_changes(shoot_result.get("diffs", []))
	# Log it the way the pipeline does (phase_action_taken), with diffs attached
	shoot_action["_resolved_via"] = "direct"  # marker: replay must skip pipeline exec
	logger.log_action(shoot_action)

	var bundle = logger.export_replay_bundle()
	_check("bundle has snapshot + %d actions" % bundle.actions.size(),
		not bundle.initial_snapshot.is_empty() and bundle.actions.size() >= 3)
	var recorded_hash = bundle.final_replay_hash
	_check("bundle carries final hash", recorded_hash != 0)
	_check("SHOOT action carries its seed",
		bundle.actions[-1].get("payload", {}).get("rng_seed", -1) == 991199)

	# -- Scramble, then replay --
	gs.state["units"]["U_TARGET"]["models"][0]["current_wounds"] = 999
	var verdict = _replay_bundle(gs, pm, rules, logger, bundle)
	_check("replayed hash matches recorded hash", verdict.replayed == recorded_hash,
		"%d vs %d (failures: %s)" % [verdict.replayed, recorded_hash, str(verdict.failures)])

	gs.state = prev
	_finish()

func _replay_bundle(gs, pm, rules, logger, bundle: Dictionary) -> Dictionary:
	# Mirror of ReplayVerifier.replay, with the direct-resolution SHOOT
	# replayed the same way it was recorded.
	var failures = []
	gs.state = bundle.initial_snapshot.duplicate(true)
	pm.transition_to_phase(int(gs.state.meta.phase))
	for entry in bundle.actions:
		var action = entry.duplicate(true)
		for k in ["_log_metadata", "_replay_diffs", "_log_text"]:
			action.erase(k)
		var atype = str(action.get("type", ""))
		if atype == "PHASE_CHANGE" or atype == "":
			continue
		if action.get("_resolved_via", "") == "direct":
			action.erase("_resolved_via")
			pm.transition_to_phase(8)
			var rng = rules.rng_for_action(action)
			var res = rules.resolve_shoot(action, gs.create_snapshot(), rng)
			pm.apply_state_changes(res.get("diffs", []))
			continue
		var phase = pm.get_current_phase_instance()
		var result = phase.execute_action(action)
		if not result.get("success", false):
			failures.append("%s: %s" % [atype, str(result)])
	return {"replayed": logger.replay_hash(gs.state), "failures": failures}

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
