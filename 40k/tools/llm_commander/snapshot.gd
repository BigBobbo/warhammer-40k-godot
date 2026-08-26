# Commander-view snapshot — sent verbatim over the MCP bridge as one
# execute_script call (multiline: true). The bridge wraps this under
# `func _run(node, tree):`, so no func defs; straight-line code + return.
# Live-verified 2026-08-26 (OC totals agree with MissionManager's own
# control test; engagement via RulesEngine.is_unit_engaged; 0 log errors).
# Conventions: "in_reserve"/"engaged" omitted when false; positions in
# inches (board px / 40) rounded to 0.1; embarked units carry "embarked_in".
var S = GameState.state
var meta = S.get("meta", {})
var players = S.get("players", {})
var phase_i = int(meta.get("phase", 0))
var phase_names = GameState.Phase.keys()
var snap = {
	"round": int(meta.get("battle_round", 1)),
	"phase": str(phase_names[phase_i]) if phase_i >= 0 and phase_i < phase_names.size() else str(phase_i),
	"active_player": int(meta.get("active_player", 1)),
	"vp": {"p1": int(players.get("1", {}).get("vp", 0)), "p2": int(players.get("2", {}).get("vp", 0))},
	"cp": {"p1": int(players.get("1", {}).get("cp", 0)), "p2": int(players.get("2", {}).get("cp", 0))},
	"objectives": [],
	"units": []
}
var UNDEP = GameState.UnitStatus.UNDEPLOYED
var IN_RES = GameState.UnitStatus.IN_RESERVES
var units = S.get("units", {})
for obj in S.get("board", {}).get("objectives", []):
	var oid = str(obj.get("id", ""))
	if oid in MissionManager.removed_objectives or oid in MissionManager.burned_objectives:
		continue
	var opos = obj.get("position", Vector2.ZERO)
	if opos is Dictionary:
		opos = Vector2(float(opos.get("x", 0)), float(opos.get("y", 0)))
	var oc1 = 0
	var oc2 = 0
	for uid in units:
		var u = units[uid]
		var st = int(u.get("status", 0))
		if st == UNDEP or st == IN_RES:
			continue
		if u.get("flags", {}).get("battle_shocked", false):
			continue
		# same OC maths as MissionManager._check_objective_control
		var ocv = int(u.get("flags", {}).get("effect_oc_override", 0))
		if ocv == 0:
			ocv = int(u.get("meta", {}).get("stats", {}).get("objective_control", 0))
		if ocv > 0:
			ocv += int(u.get("flags", {}).get("effect_plus_oc", 0))
		if ocv <= 0:
			continue
		for m in u.get("models", []):
			if not m.get("alive", true) or m.get("position") == null:
				continue
			if MissionManager.model_in_objective_range(m, obj):
				if int(u.get("owner", 0)) == 1:
					oc1 += ocv
				elif int(u.get("owner", 0)) == 2:
					oc2 += ocv
				break
	snap["objectives"].append({
		"id": oid,
		"pos_inches": [snappedf(Measurement.px_to_inches(opos.x), 0.1), snappedf(Measurement.px_to_inches(opos.y), 0.1)],
		"designation": str(obj.get("designation", "")),
		"oc_p1": oc1,
		"oc_p2": oc2,
		"holder": int(MissionManager.objective_control_state.get(oid, 0))
	})
for uid in units:
	var u = units[uid]
	if GameState.is_placeholder_unit(u):
		continue
	var models = u.get("models", [])
	var alive = 0
	var wl = 0
	var cx = 0.0
	var cy = 0.0
	var npos = 0
	for m in models:
		if not m.get("alive", true):
			continue
		alive += 1
		wl += int(m.get("current_wounds", m.get("wounds", 1)))
		var mp = m.get("position")
		if mp != null:
			var v = mp if mp is Vector2 else Vector2(float(mp.get("x", 0)), float(mp.get("y", 0)))
			cx += v.x
			cy += v.y
			npos += 1
	var st = int(u.get("status", 0))
	var embarked = u.get("embarked_in", null) != null
	var in_res = (st == IN_RES) or (st == UNDEP)
	var eng = false
	if alive > 0 and npos > 0 and not in_res and not embarked:
		eng = RulesEngine.is_unit_engaged(uid, S)
	var row = {
		"id": uid,
		"name": GameState.get_unit_display_name(uid),
		"owner": int(u.get("owner", 0)),
		"alive": alive,
		"total": models.size(),
		"wounds_left": wl
	}
	if in_res:
		row["in_reserve"] = true
	if eng:
		row["engaged"] = true
	if npos > 0:
		row["centroid_inches"] = [snappedf(Measurement.px_to_inches(cx / npos), 0.1), snappedf(Measurement.px_to_inches(cy / npos), 0.1)]
	if embarked:
		row["embarked_in"] = str(u.get("embarked_in"))
	snap["units"].append(row)
return snap
