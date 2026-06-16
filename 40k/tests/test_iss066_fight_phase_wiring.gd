extends SceneTree

# ISS-066 (11e 12.02-12.08): the PileInMove / ConsolidationMove templates
# must be AUTHORITATIVE in the live FightPhase at edition 11. Previously
# the phase ran legacy 10e pile-in/consolidate logic with no edition
# branch. This drives the REAL FightPhase._validate_pile_in /
# _validate_consolidate at edition 11 and asserts the template rules
# apply (eligibility, closer-to-pile-in-target, mode selection, AFTER
# conditions), with a 10e sensitivity check.
#
# Usage: godot --headless --path . -s tests/test_iss066_fight_phase_wiring.gd

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
	# Single-model units (no intra-unit base overlap); base_mm 25.
	gs.state["units"] = {
		"U_A": {"id": "U_A", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Fighters", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 1}},
			"models": [
				{"id": "m0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 25, "base_type": "circular", "position": {"x": 500, "y": 500}},
			]},
		"U_B": {"id": "U_B", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "Enemy", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 1}},
			"models": [
				{"id": "e0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 25, "base_type": "circular", "position": {"x": 560, "y": 500}},
			]},
		"U_C": {"id": "U_C", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Bystanders", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 1}},
			"models": [
				{"id": "c0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 25, "base_type": "circular", "position": {"x": 200, "y": 200}},
			]},
	}
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = 10

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss066_fight_phase_wiring ===\n")
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

	print("-- pile-in: template eligibility is authoritative --")
	fp.active_fighter_id = "U_C"
	var v_inel = fp._validate_pile_in({"unit_id": "U_C", "movements": {}})
	_check("ineligible unit (not engaged/charged/overrun) is rejected by the template",
		not v_inel.valid and str(v_inel.errors).contains("not engaged"), str(v_inel))

	fp.active_fighter_id = "U_A"
	print("\n-- pile-in: closer-to-pile-in-target (12.03) --")
	var v_toward = fp._validate_pile_in({"unit_id": "U_A", "movements": {"0": Vector2(518, 500)}})
	_check("valid pile-in toward the engaged target passes", v_toward.valid, str(v_toward))
	var v_away = fp._validate_pile_in({"unit_id": "U_A", "movements": {"0": Vector2(480, 500)}})
	_check("pile-in moving AWAY from the target is rejected (12.03)",
		not v_away.valid and str(v_away.errors).contains("closer"), str(v_away))

	print("\n-- consolidation: mode selection + per-mode movement (12.08) --")
	var consol = MoveTypes.get_type("consolidation")
	_check("engaged unit -> consolidation mode 'ongoing'",
		consol.select_mode("U_A", gs.state).mode == "ongoing")
	fp.active_fighter_id = "U_A"
	fp.pending_attacks.clear()
	var c_toward = fp._validate_consolidate({"unit_id": "U_A", "movements": {"0": Vector2(518, 500)}})
	_check("valid ongoing consolidation toward the engaged enemy passes", c_toward.valid, str(c_toward))
	var c_away = fp._validate_consolidate({"unit_id": "U_A", "movements": {"0": Vector2(480, 500)}})
	_check("ongoing consolidation moving away is rejected (12.08)",
		not c_away.valid and str(c_away.errors).contains("closer"), str(c_away))
	var c_empty = fp._validate_consolidate({"unit_id": "U_A", "movements": {}})
	_check("empty consolidation (per-model optional) is allowed", c_empty.valid, str(c_empty))

	print("\n-- 10e sensitivity: the legacy path is used (no template eligibility veto) --")
	GameConstants.edition = 10
	gs.state = prev_state.duplicate(true)
	_board()
	pm.transition_to_phase(10)
	var fp10 = pm.get_current_phase_instance()
	fp10.active_fighter_id = "U_C"
	var v10 = fp10._validate_pile_in({"unit_id": "U_C", "movements": {}})
	# At 10e the template eligibility veto does NOT apply: an empty-movement
	# pile-in for the active fighter is accepted by the legacy path. This
	# proves edition 11 took a different (template) route above.
	_check("e10: legacy path accepts the empty pile-in (no template eligibility veto)",
		v10.valid, str(v10))

	gs.state = prev_state
	GameConstants.edition = prev_edition
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
