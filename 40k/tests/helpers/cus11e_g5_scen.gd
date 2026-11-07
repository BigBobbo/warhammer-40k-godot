extends RefCounted
## Helpers for the WP-G5 windowed scenarios (tests/scenarios/sp/cus11e_g5_*.json):
## player-controlled NO ESCAPE / SELFLESS SERVICE / RAPID REACTIONS
## (scripts/codex/custodes/CustodesReactive.gd). Setup privileges and reads only
## — every decision in the scenarios is a real click.

const PX := 40.0


static func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


static func phase():
	return _root().get_node("PhaseManager").get_current_phase_instance()


## Setup privilege: seed the engine RNG so the next 2D6 the reactive charge
## rolls (CustodesCommon.roll_dice) sums to >= want (and <= max_sum).
static func seed_roll(want: int, max_sum: int = 12) -> int:
	var re = _root().get_node("RulesEngine")
	var common = load("res://scripts/codex/custodes/CustodesCommon.gd")
	for s in range(1, 400):
		re.set_test_seed(s)
		var r: Array = common.roll_dice(2, 6)
		var t := int(r[0]) + int(r[1])
		if t >= want and t <= max_sum:
			re.set_test_seed(s)
			print("[cus11e g5 scen] seeded the charge roll: seed %d -> %s" % [s, str(r)])
			return t
	return 0


## The pending WP-G5 flow ({} when none).
static func g5() -> Dictionary:
	var ph = phase()
	if ph == null:
		return {}
	var g = ph.get("_cus11e_g5")
	return g if typeof(g) == TYPE_DICTIONARY else {}


static func stage() -> String:
	return str(g5().get("stage", ""))


## Board px of a unit's model (index i) — drag_board start points.
static func model_px(uid: String, i: int = 0) -> Array:
	var m = _root().get_node("GameState").state.units[uid].models[i]
	var p = m.position
	return [float(p.x), float(p.y)]


static func dialog_text() -> String:
	var d = _root().get_node_or_null("Cus11eReactiveDialog")
	if d == null:
		return ""
	var out: Array = []
	for n in ["Content/Header", "Content/RollResult", "Content/Body", "Content/Result"]:
		var l = d.get_node_or_null(n)
		if l != null:
			out.append(str(l.text))
	return " | ".join(out)
