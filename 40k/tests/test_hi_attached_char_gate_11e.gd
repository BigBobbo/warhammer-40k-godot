extends SceneTree

# HEROIC INTERVENTION vs ATTACHED UNITS (11e 15.11 + 19.01).
#
# PLAYER REPORT (2026-08-06): "Blade Champion Beta is attached to a squad that
# has been charged in combat. I've been given the option to heroically
# intervene, but as my Blade Champion is already part of the squad that is
# engaged, I did not think I needed to do that — in fact I did not think that
# would even be possible." The screenshot shows the end-of-charge-phase HI
# window offering "Blade Champion Beta / Leap to Defend / Into the Fray" while
# the Custodian Guard he leads is locked in combat with the Stormboyz that just
# charged them.
#
# TWO bugs, both in the eligibility builders:
#   1. 19.01 — an attached CHARACTER is a component of his bodyguard's Attached
#      unit, not a unit of his own, so he must never get a row. (The
#      Counter-Offensive builder already folds this way; HI never did.)
#   2. The "unengaged" test called RulesEngine.is_unit_engaged, which measures
#      ONE unit dict's own models. The leader's single model trails a couple of
#      inches behind the squad taking the charge, so he read as unengaged while
#      the unit he is part of was fully engaged.
#
# Covered here:
#   - RulesEngine.is_attached_unit_engaged folds the Attached unit (and
#     is_unit_engaged still does not — that is the root cause, spelled out)
#   - get_heroic_intervention_eligible_units_11e (end-of-phase window) and
#     get_heroic_intervention_eligible_units (10e per-charge window) both drop
#     the leader AND his engaged bodyguard, while keeping a genuinely separate
#     unengaged unit — the fold must not swallow unrelated units
#   - an unengaged Attached unit is still offered, as ONE row naming both
#   - ChargePhase._validate_use_heroic_intervention rejects the leader
#     server-side, so a stale dialog / remote client cannot push the move
#
# Usage: godot --headless --path . -s tests/test_hi_attached_char_gate_11e.gd

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
	create_timer(0.1).timeout.connect(_run_tests)

func _model(id: String, x: float, y: float, wounds: int = 1) -> Dictionary:
	return {"id": id, "alive": true, "wounds": wounds, "current_wounds": wounds,
		"base_mm": 32, "base_type": "circular", "position": {"x": x, "y": y}}

# 40px = 1". The reported geometry: Ork Stormboyz (P2) charged this turn and
# ended in Engagement Range of the Custodian Guard (P1); the Blade Champion
# leading that Guard sits 2.5" BEHIND his squad — out of ER himself, but well
# within the 12" LEAP TO DEFEND band. The Telemon is a separate P1 unit 4"
# away from the Stormboyz, unengaged: a legitimate HI candidate that must
# survive the fold.
func _board(gs) -> void:
	gs.state["units"] = {
		"U_STORMBOYZ": {"id": "U_STORMBOYZ", "owner": 2, "status": 2,
			"flags": {"charged_this_turn": true},
			"attached_to": null, "attachment_data": {"attached_characters": []},
			"meta": {"name": "Stormboyz T", "keywords": ["INFANTRY", "FLY"],
				"stats": {"move": 12, "toughness": 5, "save": 6, "wounds": 1}},
			"models": [_model("s0", 500.0, 500.0), _model("s1", 545.0, 500.0)]},
		"U_GUARD": {"id": "U_GUARD", "owner": 1, "status": 2, "flags": {},
			"attached_to": null, "attachment_data": {"attached_characters": []},
			"meta": {"name": "Custodian Guard T", "keywords": ["INFANTRY", "CUSTODIAN GUARD"],
				"stats": {"move": 6, "toughness": 6, "save": 2, "wounds": 3}},
			"models": [_model("g0", 500.0, 545.0, 3), _model("g1", 545.0, 545.0, 3)]},
		"U_CHAMPION": {"id": "U_CHAMPION", "owner": 1, "status": 2, "flags": {},
			"attached_to": null, "attachment_data": {"attached_characters": []},
			"meta": {"name": "Blade Champion T", "keywords": ["CHARACTER", "INFANTRY"],
				"leader_data": {"can_lead": ["CUSTODIAN GUARD"]},
				"stats": {"move": 6, "toughness": 6, "save": 2, "invuln": 4, "wounds": 6}},
			"models": [_model("c0", 500.0, 645.0, 6)]},
		"U_TELEMON": {"id": "U_TELEMON", "owner": 1, "status": 2, "flags": {},
			"attached_to": null, "attachment_data": {"attached_characters": []},
			"meta": {"name": "Telemon T", "keywords": ["VEHICLE", "WALKER"],
				"stats": {"move": 8, "toughness": 11, "save": 2, "wounds": 14}},
			"models": [_model("t0", 500.0, 340.0, 14)]},
	}
	gs.state["meta"]["active_player"] = 2
	gs.state["meta"]["phase"] = 9
	gs.state["players"]["1"]["cp"] = 5
	gs.state["players"]["2"]["cp"] = 5

func _ids(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		out.append(str(r.get("unit_id", "")))
	return out

func _name_for(rows: Array, unit_id: String) -> String:
	for r in rows:
		if str(r.get("unit_id", "")) == unit_id:
			return str(r.get("unit_name", ""))
	return ""

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_hi_attached_char_gate_11e ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	var rules = root.get_node_or_null("RulesEngine")
	var cam = root.get_node_or_null("CharacterAttachmentManager")
	var sm = root.get_node_or_null("StratagemManager")
	if gs == null or pm == null or rules == null or cam == null or sm == null:
		_check("autoloads present", false)
		_finish()
		return
	_check("autoloads present", true)

	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	_board(gs)
	cam.attach_character("U_CHAMPION", "U_GUARD")
	_check("fixture: champion attached to the Custodian Guard",
		gs.state.units["U_CHAMPION"].get("attached_to") == "U_GUARD"
		and "U_CHAMPION" in gs.state.units["U_GUARD"].get("attachment_data", {}).get("attached_characters", []),
		str(gs.state.units["U_CHAMPION"].get("attached_to")))

	var board = gs.create_snapshot()

	print("\n-- root cause: the leader's own model is NOT in ER, his unit is --")
	_check("fixture: the Guard really is engaged by the charging Stormboyz",
		rules.is_unit_engaged("U_GUARD", board))
	_check("fixture: the champion's OWN model is out of ER (the trap)",
		not rules.is_unit_engaged("U_CHAMPION", board))
	_check("is_attached_unit_engaged(champion) folds in his squad -> engaged",
		rules.is_attached_unit_engaged("U_CHAMPION", board))
	_check("is_attached_unit_engaged(bodyguard) -> engaged",
		rules.is_attached_unit_engaged("U_GUARD", board))
	_check("is_attached_unit_engaged(unengaged Telemon) -> false",
		not rules.is_attached_unit_engaged("U_TELEMON", board))

	print("\n-- 11e 15.11 end-of-phase window --")
	var rows_11e = sm.get_heroic_intervention_eligible_units_11e(1)
	var ids_11e = _ids(rows_11e)
	_check("NO row for the attached Blade Champion (19.01)",
		not ids_11e.has("U_CHAMPION"), str(ids_11e))
	_check("NO row for his engaged Custodian Guard either (15.11 unengaged)",
		not ids_11e.has("U_GUARD"), str(ids_11e))
	_check("the separate unengaged Telemon IS still offered",
		ids_11e.has("U_TELEMON"), str(ids_11e))
	_check("exactly one row survives", ids_11e.size() == 1, str(ids_11e))

	print("\n-- 10e per-charge window (same builder bug) --")
	var rows_10e = sm.get_heroic_intervention_eligible_units(1, "U_STORMBOYZ", board)
	var ids_10e = _ids(rows_10e)
	_check("no attached-champion row", not ids_10e.has("U_CHAMPION"), str(ids_10e))
	_check("no engaged-Guard row", not ids_10e.has("U_GUARD"), str(ids_10e))

	print("\n-- ChargePhase server-side gate --")
	pm.transition_to_phase(9)
	var cp = pm.get_current_phase_instance()
	cp.awaiting_heroic_intervention = true
	cp.heroic_intervention_player = 1
	var v_champ = cp._validate_use_heroic_intervention({"unit_id": "U_CHAMPION", "player": 1})
	_check("USE_HEROIC_INTERVENTION on the attached champion is rejected",
		not v_champ.valid, str(v_champ))
	var names_rule = false
	for e in v_champ.get("errors", []):
		if "Attached CHARACTER" in str(e):
			names_rule = true
	_check("rejection names the attached-character rule", names_rule, str(v_champ.get("errors")))
	var v_guard = cp._validate_use_heroic_intervention({"unit_id": "U_GUARD", "player": 1})
	_check("USE_HEROIC_INTERVENTION on the engaged Guard is rejected too",
		not v_guard.valid, str(v_guard))
	var v_telemon = cp._validate_use_heroic_intervention({"unit_id": "U_TELEMON", "player": 1})
	_check("the unengaged Telemon is still allowed through", v_telemon.valid, str(v_telemon))

	print("\n-- positive control: an UNENGAGED Attached unit is still offered --")
	# Pull the Stormboyz back to 4" from the Guard: nobody is engaged any more,
	# but the charged enemy is inside both the 6" FRAY and 12" LEAP bands. The
	# Attached unit must reappear as ONE row headed by the bodyguard.
	gs.state.units["U_STORMBOYZ"].models[0].position = {"x": 500.0, "y": 385.0}
	gs.state.units["U_STORMBOYZ"].models[1].position = {"x": 545.0, "y": 385.0}
	var free_board = gs.create_snapshot()
	_check("fixture: nobody is engaged now",
		not rules.is_attached_unit_engaged("U_GUARD", free_board))
	var rows_free = sm.get_heroic_intervention_eligible_units_11e(1)
	var ids_free = _ids(rows_free)
	_check("the Attached unit is offered, headed by the bodyguard",
		ids_free.has("U_GUARD"), str(ids_free))
	_check("still no row of the attached champion's own",
		not ids_free.has("U_CHAMPION"), str(ids_free))
	_check("the single row names the whole Attached unit",
		_name_for(rows_free, "U_GUARD") == "Custodian Guard T + Blade Champion T",
		_name_for(rows_free, "U_GUARD"))
	_check("USE on the now-unengaged Attached unit validates",
		cp._validate_use_heroic_intervention({"unit_id": "U_GUARD", "player": 1}).valid,
		str(cp._validate_use_heroic_intervention({"unit_id": "U_GUARD", "player": 1})))

	print("\n-- 19.05: a wiped bodyguard hands the leader back his own unit --")
	for m in gs.state.units["U_GUARD"].models:
		m["alive"] = false
	var wiped_rows = _ids(sm.get_heroic_intervention_eligible_units_11e(1))
	_check("the ex-leader is offered in his own right", wiped_rows.has("U_CHAMPION"), str(wiped_rows))
	_check("the wiped bodyguard is not offered on his model's strength",
		not wiped_rows.has("U_GUARD"), str(wiped_rows))

	cp.awaiting_heroic_intervention = false
	cp.heroic_intervention_player = 0
	for uid in ["U_STORMBOYZ", "U_GUARD", "U_CHAMPION", "U_TELEMON"]:
		gs.state.units.erase(uid)
	gs.state = prev_state
	GameConstants.edition = prev_edition
	_finish()

func _finish():
	print("\n=== RESULTS: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
