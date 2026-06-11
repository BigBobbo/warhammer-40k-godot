extends SceneTree

# ISS-057: the 11e ACTIONS system (16.00-16.01), driven through the
# rulebook's example action (Deploy Device, pg 58):
#   STARTS: your Shooting phase · UNITS: one INFANTRY unit within a terrain
#   area outside your deployment zone · USE LIMIT: once per turn ·
#   COMPLETES: end of the turn · EFFECT: set up a marker.
#
# Covers: every 16.01 eligibility gate, the shoot/charge locks on start,
# movement cancelling the action (pile-in/consolidation exempt), use
# limits, completion at the trigger, and battle-shock blocking completion.
#
# Usage: godot --headless --path . -s tests/test_iss057_actions_11e.gd

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

func _board() -> Dictionary:
	return {"units": {
		"U_INF": {"id": "U_INF", "owner": 1, "flags": {},
			"meta": {"keywords": ["INFANTRY"], "stats": {"objective_control": 2}},
			"models": [{"id": "m0", "alive": true, "base_mm": 32, "base_type": "circular",
				"position": {"x": 500, "y": 500}}]},
		"U_TITAN": {"id": "U_TITAN", "owner": 1, "flags": {},
			"meta": {"keywords": ["TITANIC", "VEHICLE"], "stats": {"objective_control": 8}},
			"models": [{"id": "t0", "alive": true, "base_mm": 160, "base_type": "circular",
				"position": {"x": 1000, "y": 1000}}]},
		"U_FOE": {"id": "U_FOE", "owner": 2, "flags": {},
			"meta": {"keywords": ["INFANTRY"], "stats": {"objective_control": 1}},
			"models": [{"id": "e0", "alive": true, "base_mm": 32, "base_type": "circular",
				"position": {"x": 2000, "y": 2000}}]},
	}, "meta": {}}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss057_actions_11e ===\n")
	ActionsManager.clear_registry()
	ActionsManager.register_action({
		"id": "deploy_device", "name": "Deploy Device",
		"starts": "shooting", "units": {"keywords": ["INFANTRY"]},
		"use_limit": "once_per_turn", "completes": "end_of_turn",
		"effect": "set_up_marker",
	})

	print("-- 16.01 eligibility gates --")
	GameConstants.edition = 10
	_check("actions are 11e-only", not ActionsManager.can_start_action("U_INF", _board()).eligible)
	GameConstants.edition = 11
	_check("eligible infantry can start", ActionsManager.can_start_action("U_INF", _board()).eligible)
	var b = _board()
	b.units["U_INF"].flags["battle_shocked"] = true
	_check("battle-shocked cannot start", not ActionsManager.can_start_action("U_INF", b).eligible)
	b = _board()
	b.units["U_INF"].meta.stats.objective_control = 0
	_check("OC 0 cannot start", not ActionsManager.can_start_action("U_INF", b).eligible)
	b = _board()
	b.units["U_INF"].flags["advanced"] = true
	_check("advanced this turn cannot start", not ActionsManager.can_start_action("U_INF", b).eligible)
	b = _board()
	b.units["U_FOE"].models[0].position = {"x": 530, "y": 500}  # engaged
	_check("engaged cannot start", not ActionsManager.can_start_action("U_INF", b).eligible)
	b.units["U_FOE"].models[0].position = {"x": 1030, "y": 1000}  # engage the titan
	_check("TITANIC can start while engaged", ActionsManager.can_start_action("U_TITAN", b).eligible)
	b = _board()
	b.units["U_INF"].meta.keywords = ["AIRCRAFT"]
	b.units["U_INF"].meta.stats.objective_control = 2
	_check("AIRCRAFT cannot start", not ActionsManager.can_start_action("U_INF", b).eligible)

	print("\n-- starting: locks + unit filter + use limit --")
	b = _board()
	var r = ActionsManager.start_action("U_INF", "deploy_device", b, 1, 2)
	_check("start succeeds with diffs", r.success and r.changes.size() >= 3, str(r))
	var locked_shoot := false
	var locked_charge := false
	for c in r.changes:
		if "cannot_shoot" in str(c.path): locked_shoot = true
		if "cannot_charge" in str(c.path): locked_charge = true
	_check("starting locks shooting and charging until end of turn", locked_shoot and locked_charge)
	var rt = ActionsManager.start_action("U_TITAN", "deploy_device", b, 1, 2)
	_check("unit keyword filter enforced (TITANIC lacks INFANTRY)", not rt.success, str(rt))
	var r2 = ActionsManager.start_action("U_INF", "deploy_device", b, 1, 2)
	_check("once-per-turn use limit enforced", not r2.success, str(r2))
	r2 = ActionsManager.start_action("U_INF", "deploy_device", b, 1, 3)
	_check("a new turn resets the limit", r2.success)
	# TITANIC shooting exemption
	ActionsManager.register_action({"id": "titan_task", "name": "T", "starts": "shooting",
		"units": {"keywords": ["TITANIC"]}, "use_limit": "", "completes": "end_of_turn", "effect": "x"})
	var rtitan = ActionsManager.start_action("U_TITAN", "titan_task", _board(), 1, 2)
	var titan_shoot_locked := false
	for c in rtitan.changes:
		if "cannot_shoot" in str(c.path): titan_shoot_locked = true
	_check("TITANIC units may still shoot while performing an action", rtitan.success and not titan_shoot_locked)

	print("\n-- movement cancels (except pile-in/consolidation) --")
	var performing = {"flags": {"performing_action": "deploy_device"}}
	_check("a normal move cancels the action",
		not ActionsManager.on_unit_moved("U_INF", performing, "normal").is_empty())
	_check("pile-in does NOT cancel",
		ActionsManager.on_unit_moved("U_INF", performing, "pile_in").is_empty())
	_check("consolidation does NOT cancel",
		ActionsManager.on_unit_moved("U_INF", performing, "consolidation").is_empty())

	print("\n-- completion at the trigger --")
	b = _board()
	b.units["U_INF"].flags["performing_action"] = "deploy_device"
	var done = ActionsManager.complete_actions("end_of_turn", b)
	_check("action completes at end of turn with its effect",
		done.completed.size() == 1 and done.completed[0].effect == "set_up_marker", str(done))
	b.units["U_INF"].flags["performing_action"] = "deploy_device"
	b.units["U_INF"].flags["battle_shocked"] = true
	done = ActionsManager.complete_actions("end_of_turn", b)
	_check("battle-shock prevents completion (01.07)",
		done.completed.is_empty() and not done.changes.is_empty(), str(done))

	print("\n-- step 2: lock consumers + end-of-turn hook --")
	# cannot_shoot blocks every selectable shooting type (16.01).
	var lb = _board()
	lb.units["U_INF"].meta["weapons"] = [{"name": "Rifle", "type": "Ranged", "range": "24",
		"attacks": "2", "ballistic_skill": "3", "strength": "4", "ap": "0", "damage": "1",
		"special_rules": ""}]
	lb.units["U_INF"].flags["cannot_shoot"] = true
	_check("cannot_shoot lock: no shooting type selectable",
		ShootingTypes.available_for("U_INF", lb).is_empty(), str(ShootingTypes.available_for("U_INF", lb)))
	lb.units["U_INF"].flags.erase("cannot_shoot")
	_check("lock cleared: normal shooting selectable again",
		ShootingTypes.available_for("U_INF", lb) == ["normal"])
	# cannot_charge blocks the 11e charge template.
	var cb = _board()
	cb.units["U_FOE"].models[0].position = {"x": 700, "y": 500}  # within 12"
	cb.units["U_INF"].flags["cannot_charge"] = true
	_check("cannot_charge lock: charge template refuses",
		not MoveTypes.get_type("charge").eligible("U_INF", cb).eligible)
	cb.units["U_INF"].flags.erase("cannot_charge")
	_check("lock cleared: charge eligible again",
		MoveTypes.get_type("charge").eligible("U_INF", cb).eligible)
	# PhaseManager's end-of-turn hook completes actions against live state.
	var pm = root.get_node_or_null("PhaseManager")
	var gs = root.get_node_or_null("GameState")
	_check("PhaseManager + GameState present", pm != null and gs != null)
	gs.state.units["U_HOOK_TEST"] = {"id": "U_HOOK_TEST", "owner": 1,
		"flags": {"performing_action": "deploy_device"},
		"meta": {"keywords": ["INFANTRY"], "stats": {}},
		"models": [{"id": "m0", "alive": true, "base_mm": 32, "base_type": "circular",
			"position": {"x": 600, "y": 600}}]}
	pm._complete_actions_11e(1)
	var hf = gs.state.units["U_HOOK_TEST"].flags
	_check("turn_ending hook completed the action through the diff pipeline",
		hf.get("performing_action", "x") == "" and hf.get("action_completed", "") == "deploy_device",
		str(hf))
	gs.state.units.erase("U_HOOK_TEST")

	GameConstants.edition = 10
	ActionsManager.clear_registry()
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
