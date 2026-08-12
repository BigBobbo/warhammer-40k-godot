extends SceneTree

# PM-11 coherence check: does PLANS_ENABLED = 0 really mean "the AI behaves
# exactly as it did before the plan feature existed"?
#
# The claim the whole feature rests on is that every plan consumer sits behind
# one gate, so turning it off is a complete revert. That is easy to assert and
# easy to get wrong — a consumer that reads the plan BEFORE checking the gate,
# or a side effect in set_player_plan() itself, would leak.
#
# This checks it the only way that means anything: run the AI's decision path
# with a plan LOADED but the gate OFF, and compare against the same path with
# no plan loaded at all. Same seed, same state, same everything. Any difference
# is a leak.
#
# Run: godot --headless --path 40k -s tests/spikes/pm11_plans_off_is_inert.gd

const FIXTURE := "mirror_orks_2000_predeploy"
const PLAN := "res://data/ai_plans/orks_recon_stomps_crucible.json"

var _passed := 0
var _failed := 0


func _init():
	create_timer(0.4).timeout.connect(_run)


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("PASS: %s%s" % [label, "" if detail == "" else "  (%s)" % detail])
	else:
		_failed += 1
		print("FAIL: %s%s" % [label, "" if detail == "" else "  (%s)" % detail])


func _run() -> void:
	print("\n=== PM-11: PLANS_ENABLED=0 is inert ===\n")
	var AIDM = load("res://scripts/AIDecisionMaker.gd")
	var PV = load("res://scripts/PlanValidator.gd")
	var plan = PV.load_plan_file(PLAN)
	_check("the shipped plan loads", not plan.is_empty())

	var save_mgr = root.get_node_or_null("SaveLoadManager")
	if save_mgr == null or not save_mgr.load_game(FIXTURE):
		_check("fixture loads", false, FIXTURE)
		_finish()
		return
	await create_timer(0.5).timeout
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	pm.transition_to_phase(1)
	await create_timer(0.5).timeout

	# --- A0: what a player gets having chosen NOTHING ----------------------
	# Worth measuring on its own. Shipping plans means the AI AUTO-MATCHES one
	# whenever the army, zone and layout line up, so a player who has never
	# opened the Plan Editor now gets plan-driven deployment on recon_stomps.
	AIDM.clear_all_profiles()
	seed(4242)
	var snapshot_auto = gs.create_snapshot()
	var actions_auto := _deployment_actions(gs)
	var choice_auto = AIDM.decide(1, snapshot_auto, actions_auto, 1, 1)

	# --- A: no plan at all, auto-match suppressed --------------------------
	AIDM.clear_all_profiles()
	AIDM.suppress_player_plan(1)
	seed(4242)
	var snapshot_a = gs.create_snapshot()
	var actions_a := _deployment_actions(gs)
	var choice_a = AIDM.decide(1, snapshot_a, actions_a, 1, 1)

	# --- B: plan LOADED, gate OFF -----------------------------------------
	AIDM.clear_all_profiles()
	AIDM.set_player_plan(1, plan)
	AIDM.load_player_profile(1, {"parameters": {"PLANS_ENABLED": 0.0}, "rules": []})
	_check("the plan really is loaded for the seat",
		not AIDM.get_player_plan(1).is_empty(),
		str(AIDM.get_player_plan(1).get("name", "?")))
	seed(4242)
	var snapshot_b = gs.create_snapshot()
	var actions_b := _deployment_actions(gs)
	var choice_b = AIDM.decide(1, snapshot_b, actions_b, 1, 1)

	# --- C: plan loaded, gate ON (must DIFFER, or the test proves nothing) --
	AIDM.clear_all_profiles()
	AIDM.set_player_plan(1, plan)
	AIDM.load_player_profile(1, {"parameters": {"PLANS_ENABLED": 1.0}, "rules": []})
	seed(4242)
	var snapshot_c = gs.create_snapshot()
	var actions_c := _deployment_actions(gs)
	var choice_c = AIDM.decide(1, snapshot_c, actions_c, 1, 1)

	var auto_desc := _describe(choice_auto)
	var a_desc := _describe(choice_a)
	var b_desc := _describe(choice_b)
	var c_desc := _describe(choice_c)
	print("\n  chose nothing    : %s" % auto_desc)
	print("  no plan at all   : %s" % a_desc)
	print("  plan + gate OFF  : %s" % b_desc)
	print("  plan + gate ON   : %s" % c_desc)
	print("")

	_check("gate OFF is byte-identical to having no plan at all", a_desc == b_desc,
		"%s vs %s" % [a_desc.substr(0, 60), b_desc.substr(0, 60)])
	# The negative control: if ON and OFF agreed too, the comparison above would
	# be vacuous — it would pass for a feature that does nothing at all.
	_check("gate ON genuinely changes the decision (negative control)",
		a_desc != c_desc, "%s vs %s" % [a_desc.substr(0, 40), c_desc.substr(0, 40)])
	_check("only the gated path used the plan",
		not b_desc.contains("plan") and c_desc.contains("plan"))
	# Shipping content changed the default. This is a real player-facing effect
	# and it is asserted rather than left as a surprise: with plans on the search
	# path, choosing nothing gets you the shipped plan.
	_check("choosing nothing now auto-matches the shipped plan",
		auto_desc.contains("plan") and auto_desc == c_desc,
		auto_desc.substr(0, 70))

	AIDM.clear_all_profiles()
	_finish()


func _deployment_actions(gs) -> Array:
	var pm = root.get_node_or_null("PhaseManager")
	var phase = pm.get_current_phase_instance()
	if phase == null:
		return []
	gs.set_active_player(1)
	return phase.get_available_actions()


func _describe(action) -> String:
	if action == null or not (action is Dictionary) or action.is_empty():
		return "<none>"
	var out := "%s %s" % [str(action.get("type", "?")), str(action.get("unit_id", "?"))]
	var positions = action.get("model_positions", [])
	if positions is Array and not positions.is_empty():
		var p = positions[0]
		if p is Vector2:
			out += " first(%.2f,%.2f) n=%d" % [p.x, p.y, positions.size()]
	out += " | %s" % str(action.get("_ai_description", ""))
	return out


func _finish() -> void:
	print("\n=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
