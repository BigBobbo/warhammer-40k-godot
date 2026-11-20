extends SceneTree

# Re-price cached rollout cases under different AIPositionSim options.
#
# tests/forecast_prefilter.gd --cache=DIR writes, per measured case, the sim
# world, the rebuilt plan's intents, the base and alternative intents and the
# forecast input. This replays them with each variant in --variants (a JSON
# list of {name, opts}) and writes one JSON line per case:
#   {job, player, sides, v: {name: {pred, trace}}}
# pred = forecast margin (alternative minus base) at the rollout horizon
# (--trials > 0); trace = the plan's line turn by turn, for the ground-truth
# comparison (--trace=1). Driven by tools/ai_lab/possim_sweep.py.
#
# Usage: godot --headless --path . -s tests/possim_replay.gd -- --cache=DIR --jobs=<json list of job ids>
#          --variants=<file.json> --out=<out.jsonl> [--trials=600] [--trace=1]

const PS = preload("res://scripts/AIPositionSim.gd")
const FC = preload("res://scripts/AIForecast.gd")

func _init():
	var cache := _arg("cache")
	var trials := int(_arg("trials", "600"))
	var want_trace := _arg("trace", "1") == "1"
	var variants: Array = JSON.parse_string(FileAccess.open(_arg("variants"), FileAccess.READ).get_as_text())
	var jobs: Array = JSON.parse_string(FileAccess.open(_arg("jobs"), FileAccess.READ).get_as_text())
	var out := FileAccess.open(_arg("out"), FileAccess.WRITE)
	for job in jobs:
		var f := FileAccess.open(cache.path_join(str(job) + ".var"), FileAccess.READ)
		if f == null:
			continue
		var c: Dictionary = str_to_var(f.get_as_text())
		var world: Dictionary = c.world
		var player: int = int(c.player)
		var opp := 2 if player == 1 else 1
		var sides := {}
		for uid in world.units:
			sides[uid] = int(world.units[uid].side)
		var row := {"job": str(job), "player": player, "sides": sides, "v": {}}
		for variant in variants:
			var opts: Dictionary = (variant.opts as Dictionary).duplicate()
			if not opts.has("end_round"):
				opts["end_round"] = mini(int(world.round) + 1, FC.ROUNDS)
			var res := {}
			if trials > 0:
				var m := {}
				for arm in ["base", "alt"]:
					var sim: Dictionary = PS.run(world, c[arm], opts)
					var P: Dictionary = (c.P as Dictionary).duplicate()
					P["turn_plan"] = sim.turns
					P["end_round"] = int(opts.end_round)
					P["crn"] = true
					P["trials"] = trials
					var r: Dictionary = FC.forecast(P)
					m[arm] = float(r.mean[player]) - float(r.mean[opp])
				res["pred"] = m.alt - m.base
				if _arg("arms", "0") == "1":
					# against the rebuilt plan's own choice (what today's AI plays)
					var sim_p: Dictionary = PS.run(world, c.plan, opts)
					var Pp: Dictionary = (c.P as Dictionary).duplicate()
					Pp["turn_plan"] = sim_p.turns
					Pp["end_round"] = int(opts.end_round)
					Pp["crn"] = true
					Pp["trials"] = trials
					var rp: Dictionary = FC.forecast(Pp)
					res["pred_vs_plan"] = m.alt - (float(rp.mean[player]) - float(rp.mean[opp]))
			if want_trace:
				var to: Dictionary = opts.duplicate()
				to["trace"] = true
				var tr: Dictionary = PS.run(world, c.plan, to)
				var rows: Array = []
				for t in tr.turns:
					rows.append({"side": t.side, "own_end": t.own_end, "units": t.units})
				res["trace"] = rows
				if _arg("arms", "0") == "1":
					for arm in ["base", "alt"]:
						var ar: Dictionary = PS.run(world, c[arm], to)
						var arows: Array = []
						for t in ar.turns:
							arows.append({"side": t.side, "own_end": t.own_end, "unit": t.units.get(c.unit, []), "lam": t.get("lam", {})})
						res["trace_" + arm] = arows
					res["intent_base"] = str(c.base.get(c.unit, {}))
					res["intent_alt"] = str(c.alt.get(c.unit, {}))
			row.v[str(variant.name)] = res
		# --truth=DIR: score the REAL ownership and kills of the game that was
		# actually played from this position (possim_truth.py) — isolates the
		# forecast's "ownership -> VP" step from the sim's "positions -> ownership"
		var truth_dir := _arg("truth", "")
		if truth_dir != "" and trials > 0:
			var tf := FileAccess.open(truth_dir.path_join(str(job) + ".json"), FileAccess.READ)
			if tf != null:
				var tr: Dictionary = JSON.parse_string(tf.get_as_text())
				var shape: Dictionary = PS.run(world, c.plan, {"end_round": mini(int(world.round) + 1, FC.ROUNDS), "damage": false, "policy": false})
				var ends: Array = []
				var stop_rows: Array = []
				for t in tr.get("trace", []):
					if int(t.get("player", 0)) != 0:
						ends.append(t)
					else:
						stop_rows.append(t)
				if ends.size() < shape.turns.size() and not stop_rows.is_empty():
					ends.append(stop_rows[0])
				if str(tr.get("status", "")) == "completed" and ends.size() >= shape.turns.size():
					var tp: Array = []
					var prev_units: Dictionary = {}
					for k in range(shape.turns.size()):
						var own := {}
						for oid in ends[k].control:
							var ow := int(ends[k].control[oid])
							own[oid] = [1.0 if ow == 1 else 0.0, 1.0 if ow == 2 else 0.0]
						var lam := {1: 0.0, 2: 0.0}
						for uid in ends[k].units:
							var tu: Dictionary = ends[k].units[uid]
							var was: float = float(prev_units.get(uid, {}).get("share", 1.0))
							if float(tu.share) <= 0.0 and was > 0.0:
								lam[2 if int(tu.side) == 1 else 1] += 1.0
						prev_units = ends[k].units
						tp.append({"own_start": shape.turns[k].own_start if k == 0 else tp[k - 1].own_end, "own_end": own, "lam": lam})
					var P: Dictionary = (c.P as Dictionary).duplicate()
					P["turn_plan"] = tp
					P["end_round"] = mini(int(world.round) + 1, FC.ROUNDS)
					var rng := RandomNumberGenerator.new()
					var sums := {"prim1": 0.0, "prim2": 0.0, "sec1": 0.0, "sec2": 0.0}
					for i in range(trials):
						rng.seed = 991 + 7919 * i
						var g: Dictionary = FC._simulate_game(P, rng)
						sums.prim1 += float(g[1].prim_total)
						sums.prim2 += float(g[2].prim_total)
						sums.sec1 += float(g[1].sec_total)
						sums.sec2 += float(g[2].sec_total)
					for key in sums:
						sums[key] = sums[key] / float(trials)
					row["truth_fc"] = sums
					row["truth_vp"] = tr.get("vp", {})
					row["truth_vp_start"] = tr.get("vp_start", {})
					row["missions"] = [str(P.players[1].get("mission", "")), str(P.players[2].get("mission", ""))]
		out.store_line(JSON.stringify(row))
	out.close()
	quit(0)

func _arg(name: String, d: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return d
