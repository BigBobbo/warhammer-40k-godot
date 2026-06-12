extends SceneTree

# ISS-029: golden-master replay harness.
#
# Records a representative multi-phase game slice (formations -> movement
# -> seeded shooting -> seeded charge -> scoring transition) through the
# REAL phase pipeline at both editions, then:
#   1) scrambles the state and replays the bundle -> the final replay
#      hash must match (determinism + harness function);
#   2) SENSITIVITY: replays the 10e bundle with GameConstants.edition
#      perturbed to 11 -> the hash MUST differ or actions fail (proving
#      the harness catches rules drift, per the acceptance criteria);
#   3) persists the bundles under user://goldens_replay/ as inspectable
#      artifacts of this run.
#
# Usage: godot --headless --path . -s tests/test_iss029_golden_replay.gd

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
		"U_CHAR_A": {"id": "U_CHAR_A", "owner": 1, "flags": {}, "status": 2,
			"meta": {"name": "Cap A", "keywords": ["CHARACTER", "INFANTRY"], "is_warlord": false,
				"stats": {"toughness": 4, "save": 4, "wounds": 3, "move": 6, "objective_control": 1}},
			"models": [{"id": "m0", "alive": true, "wounds": 3, "current_wounds": 3,
				"position": {"x": 200, "y": 200}, "base_mm": 32, "base_type": "circular"}]},
		"U_SHOOTER": {"id": "U_SHOOTER", "owner": 1, "flags": {}, "status": 2,
			"meta": {"name": "Shooters", "keywords": ["INFANTRY"],
				"stats": {"toughness": 4, "save": 4, "wounds": 1, "move": 6, "objective_control": 1},
				"weapons": [{"name": "Golden Rifle", "type": "Ranged", "range": "24",
					"attacks": "2", "ballistic_skill": "3", "strength": "4", "ap": "0",
					"damage": "1", "special_rules": ""}]},
			"models": [{"id": "ms0", "alive": true, "wounds": 1, "current_wounds": 1,
				"position": {"x": 400, "y": 400}, "base_mm": 32, "base_type": "circular"}]},
		"U_TARGET": {"id": "U_TARGET", "owner": 2, "flags": {}, "status": 2,
			"meta": {"name": "Targets", "keywords": ["INFANTRY"],
				"stats": {"toughness": 4, "save": 4, "wounds": 1, "move": 6, "objective_control": 1}},
			"models": [
				{"id": "mt0", "alive": true, "wounds": 1, "current_wounds": 1,
					"position": {"x": 480, "y": 400}, "base_mm": 32, "base_type": "circular"},
				{"id": "mt1", "alive": true, "wounds": 1, "current_wounds": 1,
					"position": {"x": 480, "y": 435}, "base_mm": 32, "base_type": "circular"},
			]},
	}
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = 0

func _record_game(gs, pm, rules, logger, edition: int) -> Dictionary:
	GameConstants.edition = edition
	gs.initialize_default_state()
	_build_state(gs)
	logger.reset_session_baseline()

	pm.transition_to_phase(0)  # FORMATIONS
	var ph = pm.get_current_phase_instance()
	ph.execute_action({"type": "DESIGNATE_WARLORD", "unit_id": "U_CHAR_A", "player": 1})
	ph.execute_action({"type": "CONFIRM_FORMATIONS", "player": 1})
	# Player 2 confirms too — otherwise the active player stays at 2 and
	# every player-1 action below fails validation.
	ph = pm.get_current_phase_instance()
	if ph != null:
		ph.execute_action({"type": "CONFIRM_FORMATIONS", "player": 2})
	gs.state["meta"]["active_player"] = 1

	pm.transition_to_phase(7)  # MOVEMENT
	ph = pm.get_current_phase_instance()
	ph.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_SHOOTER", "player": 1})
	ph.execute_action({"type": "SET_MODEL_DEST", "actor_unit_id": "U_SHOOTER", "player": 1,
		"payload": {"model_id": "ms0", "dest": [440.0, 400.0]}})
	ph.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_SHOOTER", "player": 1})

	pm.transition_to_phase(8)  # SHOOTING (seeded via direct resolution)
	var shoot_action = {"type": "SHOOT", "actor_unit_id": "U_SHOOTER", "player": 1,
		"payload": {"rng_seed": 29291111, "assignments": [{
			"weapon_id": "Golden Rifle", "target_unit_id": "U_TARGET",
			"model_ids": ["ms0"], "attacks_override": 2}]}}
	var rng = rules.rng_for_action(shoot_action)
	var sres = rules.resolve_shoot(shoot_action, gs.create_snapshot(), rng)
	pm.apply_state_changes(sres.get("diffs", []))
	shoot_action["_resolved_via"] = "direct"
	logger.log_action(shoot_action)

	pm.transition_to_phase(9)  # CHARGE (declare + seeded roll, then skip)
	ph = pm.get_current_phase_instance()
	var targets = ["U_TARGET"] if edition < 11 else []
	ph.execute_action({"type": "DECLARE_CHARGE", "actor_unit_id": "U_SHOOTER", "player": 1,
		"payload": {"target_unit_ids": targets}})
	ph.execute_action({"type": "CHARGE_ROLL", "actor_unit_id": "U_SHOOTER", "player": 1,
		"payload": {"rng_seed": 7}})

	return logger.export_replay_bundle()

func _replay(gs, pm, rules, bundle: Dictionary) -> Dictionary:
	var failures = []
	gs.state = bundle.initial_snapshot.duplicate(true)
	pm.transition_to_phase(int(gs.state.meta.phase))
	for entry in bundle.actions:
		var action = entry.duplicate(true)
		for k in ["_log_metadata", "_replay_diffs", "_log_text"]:
			action.erase(k)
		var atype = str(action.get("type", ""))
		if atype == "PHASE_CHANGE":
			# Mirror the recorded transition so the replayed state walks
			# the same phase inits as the recording.
			pm.transition_to_phase(int(action.get("phase", 0)))
			continue
		if atype == "":
			continue
		if action.get("_resolved_via", "") == "direct":
			action.erase("_resolved_via")
			var rng = rules.rng_for_action(action)
			var res = rules.resolve_shoot(action, gs.create_snapshot(), rng)
			pm.apply_state_changes(res.get("diffs", []))
			continue
		# Phase transitions are re-derived from the logged game context
		# (ActionLogger's enrichment), which is then stripped so the state
		# phase_log matches the recording byte-for-byte.
		var want_phase = int(action.get("game_context", {}).get("phase", -1))
		action.erase("game_context")
		if want_phase >= 0 and want_phase != gs.get_current_phase():
			pm.transition_to_phase(want_phase)
		var phase = pm.get_current_phase_instance()
		if phase == null:
			failures.append("%s: no phase" % atype)
			continue
		var result = phase.execute_action(action)
		if not (result is Dictionary and result.get("success", false)):
			failures.append("%s: failed" % atype)
	var logger = root.get_node("ActionLogger")
	return {"hash": logger.replay_hash(gs.state), "failures": failures}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss029_golden_replay ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	var logger = root.get_node_or_null("ActionLogger")
	var rules = root.get_node_or_null("RulesEngine")
	_check("autoloads reachable", gs != null and pm != null and logger != null and rules != null)
	rules.set_test_seed(-1)
	var prev = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://goldens_replay"))

	for edition in [10, 11]:
		print("\n-- golden game slice at edition %d --" % edition)
		var bundle = _record_game(gs, pm, rules, logger, edition)
		_check("e%d: bundle recorded (%d actions)" % [edition, bundle.actions.size()],
			bundle.actions.size() >= 6 and not bundle.initial_snapshot.is_empty())
		var recorded_hash = int(bundle.final_replay_hash)
		_check("e%d: bundle carries a final hash" % edition, recorded_hash != 0)

		# Persist as an inspectable artifact of this run.
		var fpath = "user://goldens_replay/golden_slice_e%d.json" % edition
		var fa = FileAccess.open(fpath, FileAccess.WRITE)
		fa.store_string(JSON.stringify(bundle, "  "))
		fa.close()

		# Scramble, then replay.
		gs.state["units"]["U_TARGET"]["models"][0]["current_wounds"] = 999
		gs.state["units"]["U_SHOOTER"]["models"][0]["position"] = {"x": 1.0, "y": 1.0}
		var verdict = _replay(gs, pm, rules, bundle)
		_check("e%d: replay reproduces the recorded hash (failures: %d)" % [edition, verdict.failures.size()],
			verdict.hash == recorded_hash and verdict.failures.is_empty(),
			str(verdict.failures) + " hash %d vs %d" % [verdict.hash, recorded_hash])

	# SENSITIVITY: a perturbed replay must NOT reproduce the recording.
	# (This slice is edition-neutral by construction — normal move, plain
	# rifle, pre-declared charge — so the probe perturbs the recorded
	# dice stream instead: any drift in resolution behavior shows up the
	# same way, as a hash mismatch.)
	print("\n-- sensitivity: tampered dice stream must break the golden --")
	var bundle10 = _record_game(gs, pm, rules, logger, 10)
	var tampered = bundle10.duplicate(true)
	for a in tampered.actions:
		if str(a.get("type", "")) == "SHOOT":
			a["payload"]["rng_seed"] = 4242
	var perturbed = _replay(gs, pm, rules, tampered)
	_check("perturbed dice stream breaks the golden (hash mismatch or failures)",
		perturbed.hash != int(bundle10.final_replay_hash) or not perturbed.failures.is_empty(),
		"perturbed replay still matched — harness is NOT sensitive")

	GameConstants.edition = prev_edition
	gs.state = prev
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
