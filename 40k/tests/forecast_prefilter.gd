extends SceneTree

# Forecast pre-filter for counterfactual rollouts (tools/ai_lab/rollout.py).
#
# A rollout spends 12-36 games to measure what ONE decision is worth. For a
# movement case whose alternative sends one unit to a different objective,
# the game forecast (AIForecast.gd, the same projection FORECAST-PLAN uses)
# can price it in a fraction of a second: rebuild the AI's movement plan in
# the saved position, project each objective's ownership for the plan and for
# the plan with that one unit redirected, and forecast both. The difference in
# final margin is the predicted effect.
#
# tools/ai_lab/forecast_prefilter.py drives this over
# r4_designs/measured_positions.json and compares the prediction with each
# case's MEASURED rollout effect E — the test of whether the forecast is a
# usable screen (and the offline check on FORECAST-PLAN).
#
# Usage:
#   godot --headless --path . -s tests/forecast_prefilter.gd -- --jobs=<jobs.json> --out=<out.jsonl> [--trials=600]
# jobs.json: [{job, case (repo-relative case json), unit, objective, mode}]

const FC = preload("res://scripts/AIForecast.gd")

var _ran := false

func _init():
	create_timer(0.2).timeout.connect(_run)

func _arg(name: String, d: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return d

func _run():
	if _ran:
		return
	_ran = true
	await process_frame
	var jobs_path := _arg("jobs")
	var out_path := _arg("out")
	var trials := int(_arg("trials", "600"))
	var repo := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var jf := FileAccess.open(jobs_path, FileAccess.READ)
	if jf == null:
		print("PREFILTER cannot read jobs %s" % jobs_path)
		quit(2)
		return
	var jobs: Array = JSON.parse_string(jf.get_as_text())
	var out := FileAccess.open(out_path, FileAccess.WRITE)
	var AIDM = load("res://scripts/AIDecisionMaker.gd")
	var slm = root.get_node("SaveLoadManager")
	var ai = root.get_node("AIPlayer")
	var gs = root.get_node("GameState")
	var done := 0
	for job in jobs:
		var row := {"job": job.job}
		var case_path: String = repo.path_join(str(job.case))
		var cf := FileAccess.open(case_path, FileAccess.READ)
		if cf == null:
			row["error"] = "no case"
			out.store_line(JSON.stringify(row))
			continue
		var case: Dictionary = JSON.parse_string(cf.get_as_text())
		var save_path: String = case_path.get_base_dir().path_join(str(case.save_file))
		AIDM.reset_caches()
		AIDM._config_overrides = {"FORECAST_PLAN": 0.0}
		if not slm.load_game_from_file_path(save_path):
			row["error"] = "load failed"
			out.store_line(JSON.stringify(row))
			continue
		await process_frame
		ai.configure({1: "HUMAN", 2: "HUMAN"})
		var pm = root.get_node("PhaseManager")
		pm.transition_to_phase(int(gs.state.get("meta", {}).get("phase", 7)))
		for _f in range(3):
			await process_frame
		var player := int(case.get("player", 0))
		var phase_inst = pm.get_current_phase_instance()
		var actions: Array = phase_inst.get_available_actions() if phase_inst != null else []
		var snap0: Dictionary = gs.create_snapshot(false)
		AIDM._current_player = player
		var decision: Dictionary = AIDM.decide(int(snap0.get("meta", {}).get("phase", 7)), snap0, actions, player)
		var plan: Dictionary = AIDM._turn_movement_plan.get(player, {})
		var assignments: Dictionary = plan.get("assignments", {})
		var evals: Array = AIDM._last_plan_evaluations
		if assignments.is_empty() or evals.is_empty():
			row["error"] = "no movement plan (%s)" % str(decision.get("type", ""))
			out.store_line(JSON.stringify(row))
			continue
		var uid := str(job.unit)
		var oid := str(job.objective)
		var alt: Dictionary = {}
		for c in AIDM._last_movement_candidates.get(uid, []):
			if str(c.get("objective_id", "")) == oid:
				if alt.is_empty() or (str(job.get("mode", "")) == "advance") == (str(c.get("action", "")) == "advance"):
					alt = c
		if alt.is_empty():
			row["error"] = "no candidate %s -> %s" % [uid, oid]
			out.store_line(JSON.stringify(row))
			continue
		var snap: Dictionary = gs.create_snapshot(false)
		var battle_round := int(snap.get("meta", {}).get("battle_round", 1))
		var P: Dictionary = AIDM._forecast_base_P(snap, trials)
		if P.is_empty():
			row["error"] = "battle over"
			out.store_line(JSON.stringify(row))
			continue
		AIDM._config_overrides = {"FORECAST_SURVIVAL": float(_arg("survival", "1"))}
		var bp: Dictionary = AIDM._forecast_plan_projection(evals, assignments, player)
		var base_m: float = AIDM._forecast_margin_of(AIDM._forecast_with_plan(P, bp.cells, bp.conf, battle_round), player)
		var alt_assign: Dictionary = assignments.duplicate()
		var na: Dictionary = alt.duplicate()
		if bool(na.get("already_on_obj", false)):
			na["action"] = "hold"
		alt_assign[uid] = na
		var ap: Dictionary = AIDM._forecast_plan_projection(evals, alt_assign, player)
		var alt_m: float = AIDM._forecast_margin_of(AIDM._forecast_with_plan(P, ap.cells, ap.conf, battle_round), player)
		var a_now: Dictionary = assignments.get(uid, {})
		row["player"] = player
		row["round"] = battle_round
		row["ai_objective"] = str(a_now.get("objective_id", ""))
		row["ai_action"] = str(a_now.get("action", ""))
		row["alt_objective"] = oid
		row["same_objective"] = str(a_now.get("objective_id", "")) == oid
		row["base_margin"] = base_m
		row["alt_margin"] = alt_m
		row["pred"] = alt_m - base_m
		row["cells_changed"] = str(bp.cells) != str(ap.cells)
		row["score_gap"] = float(a_now.get("score", 0.0)) - float(alt.get("score", 0.0))
		# --- position look-ahead (AIPositionSim): the base is the choice the
		# rollout actually measured (the case's logged decision), not whatever
		# this rebuilt plan happens to pick for the unit
		var world: Dictionary = AIDM._possim_world(snap)
		if world.units.has(uid):
			var intents: Dictionary = AIDM._possim_intents(snap, assignments)
			var sig: Dictionary = case.get("signature", {})
			var chosen := str(case.get("chosen_option", ""))
			var base_it := {"mode": "stay", "goal_obj": ""}
			var sig_adv: bool = str(sig.get("type", "")) == "BEGIN_ADVANCE"
			var words := chosen.split(" ")
			if str(sig.get("type", "")) == "REMAIN_STATIONARY" or chosen.begins_with("Hold"):
				pass
			elif (chosen.begins_with("Move ") or chosen.begins_with("Advance ")) and words.size() > 1 and AIDM._objective_pos_by_id(snap, words[1]) != Vector2.INF:
				base_it = {"mode": "advance" if sig_adv else "move", "goal": AIDM._objective_pos_by_id(snap, words[1]) / 40.0, "goal_obj": words[1]}
			elif str(sig.get("choice", "")).begins_with("pos:"):
				var xy := str(sig.choice).substr(4).split(",")
				base_it = {"mode": "advance" if sig_adv else "move", "goal": Vector2(float(xy[0]), float(xy[1])) / 40.0, "goal_obj": ""}
			var alt_mode := str(job.get("mode", "move"))
			var alt_it := {"mode": "stay", "goal_obj": ""}
			if alt_mode != "hold":
				alt_it = {"mode": "advance" if alt_mode == "advance" else "move", "goal": AIDM._objective_pos_by_id(snap, oid) / 40.0, "goal_obj": oid}
			var bi: Dictionary = intents.duplicate()
			bi[uid] = base_it
			var ai2: Dictionary = intents.duplicate()
			ai2[uid] = alt_it
			P["trials"] = trials
			for variant in [["a0", {"damage": false, "policy": false}], ["a1", {"damage": false, "policy": true}],
					["b0", {"damage": true, "policy": false}], ["b1", {"damage": true, "policy": true}]]:
				var mb: Dictionary = AIDM._possim_margin(snap, world, bi, player, P, variant[1])
				var ma: Dictionary = AIDM._possim_margin(snap, world, ai2, player, P, variant[1])
				row["ps_" + variant[0]] = float(ma.margin) - float(mb.margin)
				if variant[0] == "b1":
					row["x_base"] = float(mb.sim.units[uid].x)
					row["x_alt"] = float(ma.sim.units[uid].x)
			row["base_intent"] = "%s %s" % [base_it.mode, base_it.goal_obj]
			row["alt_intent"] = "%s %s" % [alt_it.mode, alt_it.goal_obj]
			row["rebuilt_matches_logged"] = str(a_now.get("objective_id", "")) == str(base_it.goal_obj)
		out.store_line(JSON.stringify(row))
		done += 1
		print("PREFILTER %s pred %+.2f (%s -> %s, cells changed %s) possim a0 %+.2f a1 %+.2f b0 %+.2f b1 %+.2f" % [job.job, alt_m - base_m, row.ai_objective, oid, str(row.cells_changed),
			float(row.get("ps_a0", 0.0)), float(row.get("ps_a1", 0.0)), float(row.get("ps_b0", 0.0)), float(row.get("ps_b1", 0.0))])
	out.close()
	print("PREFILTER done %d/%d" % [done, jobs.size()])
	quit(0)
