extends SceneTree

# 19.03 ATTACHED UNITS in the global Pile In (12.02) and Consolidate (12.07)
# steps — regression for "Blade Champions attached to Custodian Guard are
# listed/treated as separate pile-in units".
#
# While a CHARACTER is attached to a bodyguard they are ONE Attached unit:
#   1. The step's eligible list offers the BODYGUARD only (named
#      "Guard + Champion"); the attached character is never its own entry.
#   2. A bodyguard whose ONLY engaged model is the attached character's is
#      still eligible (engagement is the Attached unit's).
#   3. One PILE_IN action moves bodyguard models (plain keys) AND the
#      character's models ("char_unit:index" keys); both positions land.
#   4. The character's own step move is spent with the bodyguard's; a direct
#      PILE_IN / CONSOLIDATE for the character is rejected (19.03).
#   5. The Consolidate step mirrors all of the above.
#   6. The AI's PILE_IN payload includes the attached character's movements.
#
# Usage: godot --headless --path . -s tests/test_pile_in_attached_characters_11e.gd

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

func _board() -> void:
	var gs = root.get_node("GameState")
	# 40px = 1"; 25mm base radius ~19.7px, so centres must be >= ~39.4px apart.
	# Pair 1 — U_G "Custodian Guard" (P1, engaged with U_B) + attached U_L
	#   "Blade Champion" (unengaged, 2.05" from the enemy — it needs the
	#   combined pile-in to get in).
	# Pair 2 — U_G2 "Custodian Wardens" (P1, its OWN model unengaged) +
	#   attached U_L2 "Blade Champion Beta" (ENGAGED with U_B2): the Attached
	#   unit is engaged only through the character's model.
	# U_C — P1 bystander (never eligible).
	gs.state["units"] = {
		"U_G": {"id": "U_G", "owner": 1, "status": 2, "flags": {},
			"attachment_data": {"attached_characters": ["U_L"]},
			"meta": {"name": "Custodian Guard", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 2}},
			"models": [
				{"id": "m1", "alive": true, "wounds": 2, "current_wounds": 2, "base_mm": 25, "base_type": "circular", "position": {"x": 540, "y": 500}},
				{"id": "m2", "alive": true, "wounds": 2, "current_wounds": 2, "base_mm": 25, "base_type": "circular", "position": {"x": 540, "y": 540}},
			]},
		"U_L": {"id": "U_L", "owner": 1, "status": 2, "flags": {}, "attached_to": "U_G",
			"meta": {"name": "Blade Champion", "keywords": ["INFANTRY", "CHARACTER"], "stats": {"move": 6, "wounds": 5}},
			"models": [
				{"id": "m1", "alive": true, "wounds": 5, "current_wounds": 5, "base_mm": 25, "base_type": "circular", "position": {"x": 480, "y": 500}},
			]},
		"U_B": {"id": "U_B", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "Lootas", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 1}},
			"models": [
				{"id": "e1", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 25, "base_type": "circular", "position": {"x": 600, "y": 500}},
			]},
		"U_G2": {"id": "U_G2", "owner": 1, "status": 2, "flags": {},
			"attachment_data": {"attached_characters": ["U_L2"]},
			"meta": {"name": "Custodian Wardens", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 3}},
			"models": [
				{"id": "m1", "alive": true, "wounds": 3, "current_wounds": 3, "base_mm": 25, "base_type": "circular", "position": {"x": 1200, "y": 800}},
			]},
		"U_L2": {"id": "U_L2", "owner": 1, "status": 2, "flags": {}, "attached_to": "U_G2",
			"meta": {"name": "Blade Champion Beta", "keywords": ["INFANTRY", "CHARACTER"], "stats": {"move": 6, "wounds": 5}},
			"models": [
				{"id": "m1", "alive": true, "wounds": 5, "current_wounds": 5, "base_mm": 25, "base_type": "circular", "position": {"x": 1252, "y": 800}},
			]},
		"U_B2": {"id": "U_B2", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "Burna Boyz", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 1}},
			"models": [
				{"id": "e1", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 25, "base_type": "circular", "position": {"x": 1312, "y": 800}},
			]},
		"U_C": {"id": "U_C", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Bystanders", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 1}},
			"models": [
				{"id": "m1", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 25, "base_type": "circular", "position": {"x": 200, "y": 200}},
			]},
	}
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = 10

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_pile_in_attached_characters_11e ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	if gs == null or pm == null:
		_check("autoloads", false); _finish(); return
	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition

	GameConstants.edition = 11
	_board()
	pm.transition_to_phase(10)  # FIGHT
	var fp = pm.get_current_phase_instance()

	print("-- 12.02 step data: ONE entry per Attached unit --")
	_check("Pile In step ACTIVE on phase entry", fp.pile_in_step_11e == fp.PileInStep11e.ACTIVE)
	var pending = fp.get_pending_pile_in_step_data()
	var pend_units = pending.get("eligible_units", {})
	_check("bodyguard U_G listed", pend_units.has("U_G"), str(pend_units.keys()))
	_check("attached Blade Champion U_L is NOT its own entry", not pend_units.has("U_L"), str(pend_units.keys()))
	_check("attached Blade Champion U_L2 is NOT its own entry", not pend_units.has("U_L2"), str(pend_units.keys()))
	_check("U_G2 eligible although only its CHARACTER's model is engaged (19.03)",
		pend_units.has("U_G2"), str(pend_units.keys()))
	_check("bystander U_C not listed", not pend_units.has("U_C"), str(pend_units.keys()))
	_check("entry named as the Attached unit",
		pend_units.get("U_G", {}).get("name", "") == "Custodian Guard + Blade Champion",
		str(pend_units.get("U_G", {})))
	_check("U_G2 shows engaged via its character's model",
		pend_units.get("U_G2", {}).get("engaged", false), str(pend_units.get("U_G2", {})))
	_check("entry carries the attached character ids",
		pend_units.get("U_G", {}).get("attached_characters", []) == ["U_L"], str(pend_units.get("U_G", {})))

	print("\n-- direct PILE_IN for an attached character is rejected (19.03) --")
	var v_char = fp._validate_pile_in({"unit_id": "U_L2", "movements": {}})
	_check("attached character cannot pile in on its own",
		not v_char.valid and str(v_char.errors).contains("19.03"), str(v_char))

	print("\n-- one PILE_IN moves bodyguard AND attached character models --")
	# U_G m1 (540,500) -> (545,500): 0.125" toward e1 at (600,500).
	# U_L m1 (480,500) -> (505,500) via the "U_L:0" key: 0.625" toward e1,
	# ends 40px (base-to-base) behind U_G m1's NEW spot — no overlap.
	var r_g = fp.execute_action({"type": "PILE_IN", "unit_id": "U_G",
		"movements": {"0": Vector2(545, 500), "U_L:0": Vector2(505, 500)}, "player": 1})
	_check("combined pile-in succeeds", r_g.get("success", false), str(r_g))
	_check("bodyguard model moved", gs.state["units"]["U_G"]["models"][0]["position"]["x"] == 545.0,
		str(gs.state["units"]["U_G"]["models"][0]["position"]))
	_check("attached character's model moved in the same action",
		gs.state["units"]["U_L"]["models"][0]["position"]["x"] == 505.0,
		str(gs.state["units"]["U_L"]["models"][0]["position"]))
	_check("character's one step move spent with the bodyguard's",
		fp.units_that_piled_in.get("U_L", false), str(fp.units_that_piled_in))
	var v_again = fp._validate_pile_in({"unit_id": "U_G", "movements": {}})
	_check("second pile-in for the Attached unit rejected (12.02)",
		not v_again.valid, str(v_again))

	print("\n-- movement keys must address the Attached unit only --")
	var v_foreign = fp._validate_pile_in({"unit_id": "U_G2", "movements": {"U_C:0": Vector2(1210, 800)}})
	_check("key addressing a non-attached unit rejected",
		not v_foreign.valid and str(v_foreign.errors).contains("attached"), str(v_foreign))

	print("\n-- AI pile-in payload includes the attached character's models --")
	var ai = load("res://scripts/AIDecisionMaker.gd")
	var snapshot = gs.state.duplicate(true)
	var ai_action = ai._compute_pile_in_action(snapshot, "U_G2", 1)
	var ai_has_char_key := false
	for key in ai_action.get("movements", {}):
		if str(key).begins_with("U_L2:"):
			ai_has_char_key = true
			break
	_check("AI moves U_G2's bodyguard model toward the fight",
		not ai_action.get("movements", {}).is_empty(), str(ai_action))
	_check("AI payload carries U_L2 movements under 'U_L2:<idx>' keys",
		ai_has_char_key, str(ai_action.get("movements", {})))

	print("\n-- Consolidate step mirrors the fold --")
	var r_pi2 = fp.execute_action({"type": "PILE_IN", "unit_id": "U_G2", "movements": {}, "player": 1})
	_check("U_G2 declines to move (still spends its step move)", r_pi2.get("success", false), str(r_pi2))
	fp.execute_action({"type": "END_PILE_IN", "player": 1})
	fp.execute_action({"type": "END_PILE_IN", "player": 2})
	_check("Pile In step DONE", fp.pile_in_step_11e == fp.PileInStep11e.DONE)
	for uid in ["U_G", "U_L", "U_B", "U_G2", "U_L2", "U_B2"]:
		fp.sequencer_11e.mark_fought(uid)
	var r_end = fp.execute_action({"type": "END_FIGHT", "player": 1})
	_check("END_FIGHT enters the Consolidate step", fp.consolidation_step_11e == fp.ConsolidationStep11e.ACTIVE, str(r_end))
	var cons_data = r_end.get("consolidation_selection_data", {})
	var cons_units = cons_data.get("eligible_units", {})
	_check("consolidate list offers bodyguards, not attached characters",
		cons_units.has("U_G") and not cons_units.has("U_L") and not cons_units.has("U_L2"),
		str(cons_units.keys()))
	_check("U_G2 consolidate-eligible via its character's engagement stamp (19.03)",
		cons_units.has("U_G2"), str(cons_units.keys()))
	_check("consolidate entry named as the Attached unit",
		cons_units.get("U_G", {}).get("name", "") == "Custodian Guard + Blade Champion", str(cons_units.get("U_G", {})))
	_check("U_G2's 12.08 mode assessed on the folded unit (ongoing — its character is engaged)",
		cons_units.get("U_G2", {}).get("mode", "") == "ongoing", str(cons_units.get("U_G2", {})))

	var v_char_cons = fp._validate_consolidate({"unit_id": "U_L2", "movements": {}})
	_check("attached character cannot consolidate on its own (19.03)",
		not v_char_cons.valid and str(v_char_cons.errors).contains("19.03"), str(v_char_cons))

	# U_G2 m1 (1200,800) -> (1210,805): closer to U_B2's e1 at (1312,800);
	# U_L2 m1 (1252,800) -> (1262,800) via "U_L2:0": closer, stays engaged.
	var r_cons = fp.execute_action({"type": "CONSOLIDATE", "unit_id": "U_G2",
		"movements": {"0": Vector2(1210, 805), "U_L2:0": Vector2(1262, 800)}, "player": 1})
	_check("combined consolidation succeeds", r_cons.get("success", false), str(r_cons))
	_check("bodyguard model consolidated", gs.state["units"]["U_G2"]["models"][0]["position"]["x"] == 1210.0,
		str(gs.state["units"]["U_G2"]["models"][0]["position"]))
	_check("attached character's model consolidated in the same action",
		gs.state["units"]["U_L2"]["models"][0]["position"]["x"] == 1262.0,
		str(gs.state["units"]["U_L2"]["models"][0]["position"]))
	_check("character's one consolidation spent with the bodyguard's",
		fp.units_that_consolidated_11e.has("U_L2"), str(fp.units_that_consolidated_11e))

	gs.state = prev_state
	GameConstants.edition = prev_edition
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
