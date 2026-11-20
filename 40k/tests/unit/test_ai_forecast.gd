extends SceneTree

# AIForecast.gd is a GDScript port of the Combat Calc forecast
# (server/public/calc/forecast.mjs). This test proves the port is faithful:
#
#  1. Card parity — every secondary in missions-11e.mjs exists in
#     AIForecast.CARDS with the same timing / kind / target / min round /
#     pair / fixed flag, and vice versa; every id is a real SecondaryMissionData
#     card; every 11e primary card name is one AIForecast scores.
#  2. Statistical parity — 28 scenarios (all 25 primary cards, a mid-game
#     start with hands/used/VP/destroyed units, fixed vs tactical, a contested
#     plan with confidence overrides) generated and run through the JS by
#     tools/ai_lab/forecast_parity.mjs. The GDScript means, sds and win rates
#     must match within sampling error (the RNGs differ, so exact equality is
#     not expected).
#  3. Determinism — the same seed gives identical results.
#
# Regenerate the fixture after changing forecast.mjs:
#   node tools/ai_lab/forecast_parity.mjs
# Run with: godot --headless --path . -s tests/unit/test_ai_forecast.gd

const FC = preload("res://scripts/AIForecast.gd")
const SMD = preload("res://scripts/data/SecondaryMissionData.gd")
const PMD = preload("res://scripts/data/PrimaryMissionData11e.gd")
const FIXTURE := "res://tests/fixtures/forecast_parity.json"
const MISSIONS_JS := "res://../server/public/calc/missions-11e.mjs"
const TRIALS := 4000

var _pass := 0
var _fail := 0
var _ran := false

func _init():
	create_timer(0.1).timeout.connect(_run)

func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("PASS: %s" % msg)
	else:
		_fail += 1
		print("FAIL: %s" % msg)

func _run():
	if _ran:
		return
	_ran = true
	await process_frame
	print("\n=== AIForecast: port parity with forecast.mjs ===\n")
	test_card_parity()
	test_primary_names()
	test_statistical_parity()
	test_determinism()
	test_secondary_values()
	print("\n=== Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func test_card_parity() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join("../server/public/calc/missions-11e.mjs").simplify_path()
	var f := FileAccess.open(path, FileAccess.READ)
	_check(f != null, "missions-11e.mjs readable at %s" % path)
	if f == null:
		return
	var src := f.get_as_text()
	var start := src.find("export const SECONDARIES")
	var end := src.find("];", start)
	var block := src.substr(start, end - start)
	var re := RegEx.new()
	re.compile("\\{ id: '([a-z-]+)'[^\\n]*")
	var js_ids := {}
	for m in re.search_all(block):
		var line: String = m.get_string(0)
		var id: String = m.get_string(1).replace("-", "_")
		var spec := {}
		for key in ["timing", "kind", "target", "pair"]:
			var r2 := RegEx.new()
			r2.compile(key + ": '([a-zA-Z0-9-]+)'")
			var mm := r2.search(line)
			if mm:
				spec[key] = mm.get_string(1).replace("-", "_")
		var r3 := RegEx.new()
		r3.compile("minRound: (\\d+)")
		var m3 := r3.search(line)
		if m3:
			spec["min_round"] = int(m3.get_string(1))
		spec["fixed"] = line.contains("fixed: true")
		js_ids[id] = spec
	_check(js_ids.size() == 18, "missions-11e.mjs lists the 18-card 11e deck (got %d)" % js_ids.size())
	for id in js_ids:
		var gd: Dictionary = FC.CARDS.get(id, {})
		_check(not gd.is_empty(), "card %s present in AIForecast.CARDS" % id)
		if gd.is_empty():
			continue
		var js: Dictionary = js_ids[id]
		var same: bool = gd.timing == js.timing and gd.kind == js.kind \
			and str(gd.get("target", "")) == str(js.get("target", "")) \
			and str(gd.get("pair", "")) == str(js.get("pair", "")) \
			and int(gd.get("min_round", 0)) == int(js.get("min_round", 0)) \
			and bool(gd.get("fixed", false)) == bool(js.fixed)
		_check(same, "card %s spec matches JS (gd=%s js=%s)" % [id, str(gd), str(js)])
		_check(not SMD.get_mission_by_id(id).is_empty(), "card %s is a real SecondaryMissionData id" % id)
	for id in FC.CARDS:
		_check(js_ids.has(id), "AIForecast card %s exists in missions-11e.mjs" % id)
	var deck: Array = SMD.get_mission_ids_for_deck_11e()
	deck.sort()
	_check(deck == FC.card_ids(), "AIForecast cards == the game's 11e deck (%s)" % str(deck))

func test_primary_names() -> void:
	# Every 11e primary card must reach a real scoring branch in _primary():
	# an unknown name falls through to {EOT: 0, C: 0} and would score nothing.
	var probe_h := {"total": 3, "home": 1, "opp_home": 1, "exp": 1, "opp_exp": 0, "central": 1,
		"non_home": 2, "nml": 2, "opp_territory": 1, "ids": []}
	var opp_h := {"total": 1, "home": 1, "opp_home": 0, "exp": 0, "opp_exp": 0, "central": 0,
		"non_home": 0, "nml": 0, "opp_territory": 0, "ids": []}
	var names := {}
	for card in PMD.get_all_cards():
		names[str(card.get("name", ""))] = true
	_check(names.size() == 25, "PrimaryMissionData11e has 25 cards (got %d)" % names.size())
	for n in names:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var total := 0
		for r in range(1, 6):
			var v: Dictionary = FC._primary(n, {"r": r, "h": probe_h, "h_opp": opp_h,
				"kills": [{"characters": 0, "w10": 0, "ss13": false, "on_obj": true}],
				"lost_prev": 0, "newly": 1, "p_act": 1.0, "ms": {}, "rng": rng, "enemy_alive": 6, "rate": {}})
			total += int(v.EOT) + int(v.C)
		_check(total > 0, "primary '%s' scores through AIForecast (%d VP over 5 probe rounds)" % [n, total])

func _load_fixture() -> Dictionary:
	var f := FileAccess.open(FIXTURE, FileAccess.READ)
	if f == null:
		return {}
	return JSON.parse_string(f.get_as_text())

static func _int_keys(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[int(k)] = d[k]
	return out

static func _to_game_P(s: Dictionary, armies: Dictionary, trials: int) -> Dictionary:
	var objs: Array = []
	for o in s.objectives:
		objs.append({"id": str(o.id), "cls": str(o.cls), "side": int(o.side)})
	var plan := {}
	for r in s.plan:
		var cells := {}
		for k in s.plan[r]:
			cells[str(k)] = int(s.plan[r][k])
		plan[int(r)] = cells
	var players := {}
	for k in s.players:
		var p: Dictionary = (s.players[k] as Dictionary).duplicate(true)
		p["army"] = FC.army_profile(armies[k].units)
		players[int(k)] = p
	var P := {"objectives": objs, "plan": plan, "players": players, "trials": trials,
		"seed": int(s.get("seed", 1)), "first": int(s.get("first", 0)),
		"start_round": int(s.get("start_round", 1)), "start_turn": int(s.get("start_turn", 0)),
		"start_after_draw": bool(s.get("start_after_draw", false))}
	if s.has("confidence"):
		P["confidence"] = s.confidence
	return P

func test_statistical_parity() -> void:
	var fx := _load_fixture()
	_check(not fx.is_empty(), "parity fixture loads (%s)" % FIXTURE)
	if fx.is_empty():
		return
	var t0 := Time.get_ticks_msec()
	var worst_mean := 0.0
	var worst_win := 0.0
	for s in fx.scenarios:
		var P := _to_game_P(s, fx.armies, TRIALS)
		var r: Dictionary = FC.forecast(P)
		var js: Dictionary = s.js
		# sampling error: GD at TRIALS + JS at 20000 trials, 4.5 combined SE
		var se1: float = 4.5 * float(js.sd1) * sqrt(1.0 / TRIALS + 1.0 / float(fx.trials_js))
		var se2: float = 4.5 * float(js.sd2) * sqrt(1.0 / TRIALS + 1.0 / float(fx.trials_js))
		var pw: float = float(js.p_win1)
		var se_w: float = 4.5 * sqrt(maxf(pw * (1.0 - pw), 0.01) * (1.0 / TRIALS + 1.0 / float(fx.trials_js)))
		var d1: float = absf(float(r.mean[1]) - float(js.mean1))
		var d2: float = absf(float(r.mean[2]) - float(js.mean2))
		var dw: float = absf(float(r.p_win[1]) - pw)
		var dsd: float = absf(float(r.sd[1]) - float(js.sd1))
		worst_mean = maxf(worst_mean, maxf(d1, d2))
		worst_win = maxf(worst_win, dw)
		_check(d1 <= se1 and d2 <= se2 and dw <= se_w and dsd <= maxf(1.0, 0.12 * float(js.sd1)),
			"%s: GD %.2f/%.2f win %.3f sd %.1f vs JS %.2f/%.2f win %.3f sd %.1f (tol %.2f/%.2f/%.3f)" % [
				s.name, r.mean[1], r.mean[2], r.p_win[1], r.sd[1], js.mean1, js.mean2, pw, js.sd1, se1, se2, se_w])
	var ms := Time.get_ticks_msec() - t0
	print("INFO: %d scenarios x %d trials in %d ms (%.2f ms per simulated game); worst mean gap %.2f VP, worst win gap %.3f" % [
		fx.scenarios.size(), TRIALS, ms, float(ms) / (fx.scenarios.size() * TRIALS), worst_mean, worst_win])

func test_determinism() -> void:
	var fx := _load_fixture()
	if fx.is_empty():
		return
	var P := _to_game_P(fx.scenarios[25], fx.armies, 300)
	var a: Dictionary = FC.forecast(P)
	var b: Dictionary = FC.forecast(P)
	_check(a.mean[1] == b.mean[1] and a.mean[2] == b.mean[2] and a.p_win[1] == b.p_win[1],
		"same seed -> identical forecast (%.3f/%.3f)" % [a.mean[1], a.mean[2]])
	P["seed"] = 99
	var c: Dictionary = FC.forecast(P)
	_check(c.mean[1] != a.mean[1], "different seed -> different sample")

func _sv_P(hand: Array, round_: int, turn: int, enemy_units: Array, plan_cells: Dictionary, kill_rate: float = 1.3) -> Dictionary:
	var objs := [{"id": "home1", "cls": "home", "side": 1}, {"id": "home2", "cls": "home", "side": 2},
		{"id": "exp1", "cls": "exp", "side": 1}, {"id": "exp2", "cls": "exp", "side": 2},
		{"id": "centre", "cls": "central", "side": 0}]
	var plan := {}
	for r in range(1, 6):
		plan[r] = plan_cells
	var deck: Array = []
	for id in FC.card_ids():
		if not hand.has(id):
			deck.append(id)
	var mine := FC.army_profile([{"name": "a1", "models": 10}, {"name": "a2", "models": 5}])
	return {"objectives": objs, "plan": plan, "first": 1, "start_round": round_, "start_turn": turn,
		"start_after_draw": true, "trials": 1500, "seed": 5,
		"players": {
			1: {"mission": "Battlefield Dominance", "mode": "tactical", "army": mine, "kill_rate": kill_rate,
				"start": {"hand": hand, "used": [], "deck": deck}},
			2: {"mission": "Meatgrinder", "mode": "tactical", "army": FC.army_profile(enemy_units),
				"start": {"hand": [], "used": []}}}}

func test_secondary_values() -> void:
	var no_chars := [{"name": "b1", "models": 10}, {"name": "b2", "models": 3}]
	var with_chars := [{"name": "b1", "models": 10}, {"name": "b2", "models": 1, "characters": 1}]
	var hold_nml := {"home1": 1, "home2": 2, "exp1": 1, "exp2": 1, "centre": 1}
	var hold_none := {"home1": 1, "home2": 2, "exp1": 2, "exp2": 2, "centre": 2}
	# A kill card with no targets left is worth nothing
	var v1: Dictionary = FC.secondary_values(_sv_P(["assassination"], 2, 0, no_chars, hold_nml), 1)
	_check(float(v1.keep.assassination) < 0.05, "Assassination with no enemy CHARACTER left keeps ~0 VP (%.2f)" % v1.keep.assassination)
	var v2: Dictionary = FC.secondary_values(_sv_P(["assassination"], 2, 0, with_chars, hold_nml), 1)
	_check(float(v2.keep.assassination) > 1.0, "Assassination with a live CHARACTER keeps real VP (%.2f)" % v2.keep.assassination)
	# Secure No Man's Land pays 5 when the plan holds both NML objectives
	var v3: Dictionary = FC.secondary_values(_sv_P(["secure_no_mans_land"], 2, 0, no_chars, hold_nml), 1)
	var v4: Dictionary = FC.secondary_values(_sv_P(["secure_no_mans_land"], 2, 0, no_chars, hold_none), 1)
	_check(float(v3.keep.secure_no_mans_land) > 3.5, "Secure NML with NML held keeps ~5 VP (%.2f)" % v3.keep.secure_no_mans_land)
	_check(float(v4.keep.secure_no_mans_land) < float(v3.keep.secure_no_mans_land) - 1.5,
		"Secure NML is worth less when NML is the enemy's (%.2f < %.2f)" % [v4.keep.secure_no_mans_land, v3.keep.secure_no_mans_land])
	# A fresh draw is worth more with the whole game ahead than on the last turn
	var early: Dictionary = FC.secondary_values(_sv_P([], 2, 0, with_chars, hold_nml), 1)
	var late: Dictionary = FC.secondary_values(_sv_P([], 5, 0, with_chars, hold_nml), 1)
	_check(float(early.draw_now) > float(late.draw_now) and float(early.draw_now) > 2.0,
		"a draw now is worth more in R2 (%.2f) than R5 (%.2f)" % [early.draw_now, late.draw_now])
	# Fixed missions never redraw
	var P5 := _sv_P(["assassination", "bring_it_down"], 2, 0, with_chars, hold_nml)
	P5.players[1]["mode"] = "fixed"
	P5.players[1]["fixed"] = ["assassination", "bring_it_down"]
	_check(float(FC.secondary_values(P5, 1).draw_now) == 0.0, "fixed mode: no redraw value")
