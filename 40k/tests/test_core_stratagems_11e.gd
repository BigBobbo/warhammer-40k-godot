extends SceneTree

# 11e core stratagem set (15.02-15.12) — live-path regression. The A4 alias
# resolves the retired 10e ids to the *_11e definitions; this test pins the
# parts that were found inert or leaking:
#   1. SMOKESCREEN (15.10): the effect must set flags.stratagem_cover — the
#      flag the 11e hit-side cover check actually reads (setting only
#      effect_cover burned CP for zero benefit) — and expire at end of phase.
#   2. COUNTEROFFENSIVE (15.12): grants flags.fights_first and MUST clear it
#      on expiry (it used to leak for the rest of the battle).
#   3. EPIC CHALLENGE (15.03): effect_precision_melee set + cleared.
#   4. RAPID INGRESS (15.07): blocked in battle round 1, available later.
#   5. HEROIC INTERVENTION (15.11): the window moves to the END of the
#      opponent's Charge phase, with modes — INTO THE FRAY caps the charge
#      roll at 6 and targets within 6"; declining completes the phase.
#
# Usage: godot --headless --path . -s tests/test_core_stratagems_11e.gd

var passed := 0
var failed := 0
var _phase_completed := 0

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
	# U_HI (P1): unengaged, 4" (edge) from U_EN — eligible for both HI modes.
	# U_EN (P2): charged this turn (leap-to-defend target).
	# U_SMOKE (P1): SMOKE keyword for Smokescreen.
	# U_CO (P1): engaged Counteroffensive candidate; U_EC (P1): CHARACTER.
	gs.state["units"] = {
		"U_HI": {"id": "U_HI", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Defenders", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 1}},
			"models": [
				{"id": "m0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 25, "base_type": "circular", "position": {"x": 500, "y": 500}},
			]},
		"U_EN": {"id": "U_EN", "owner": 2, "status": 2, "flags": {"charged_this_turn": true},
			"meta": {"name": "Chargers", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 1}},
			"models": [
				{"id": "e0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 25, "base_type": "circular", "position": {"x": 700, "y": 500}},
			]},
		"U_SMOKE": {"id": "U_SMOKE", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Smokers", "keywords": ["INFANTRY", "SMOKE"], "stats": {"move": 6, "wounds": 1}},
			"models": [
				{"id": "s0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 25, "base_type": "circular", "position": {"x": 200, "y": 200}},
			]},
		"U_CO": {"id": "U_CO", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Brawlers", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 1}},
			"models": [
				{"id": "c0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 25, "base_type": "circular", "position": {"x": 300, "y": 800}},
			]},
		"U_EC": {"id": "U_EC", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Captain", "keywords": ["INFANTRY", "CHARACTER"], "stats": {"move": 6, "wounds": 4}},
			"models": [
				{"id": "h0", "alive": true, "wounds": 4, "current_wounds": 4, "base_mm": 40, "base_type": "circular", "position": {"x": 900, "y": 200}},
			]},
	}
	gs.state["meta"]["active_player"] = 2
	gs.state["players"] = {"1": {"cp": 10}, "2": {"cp": 10}}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_core_stratagems_11e ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	var sm = root.get_node_or_null("StratagemManager")
	if gs == null or pm == null or sm == null:
		_check("autoloads", false); _finish(); return
	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition

	GameConstants.edition = 11
	_board()

	print("-- A4 alias: the retired 10e ids resolve to the 11e core set --")
	gs.state["meta"]["phase"] = 9  # timing checks validate against the live phase
	var hi_cu = sm.can_use_stratagem(1, "heroic_intervention")
	_check("heroic_intervention resolves and is usable at e11 (charge phase)", hi_cu.can_use, str(hi_cu))
	_check("smokescreen resolves to smokescreen_11e", sm._resolve_core_id("smokescreen") == "smokescreen_11e")

	print("\n-- SMOKESCREEN (15.10): the effect flag the 11e cover check reads --")
	gs.state["meta"]["phase"] = 8  # shooting
	var r_ss = sm.use_stratagem(1, "smokescreen", "U_SMOKE")
	_check("smokescreen use succeeds", r_ss.get("success", false), str(r_ss))
	var smoke_flags = gs.state["units"]["U_SMOKE"].get("flags", {})
	_check("stratagem_cover set (the flag the 11e hit-side cover check reads)",
		smoke_flags.get("stratagem_cover", false))
	_check("effect_cover set (10e save-side readers + AI heuristics)",
		smoke_flags.get("effect_cover", false))
	# End-of-phase expiry must CLEAR the 11e-set flags (they used to leak).
	sm.on_phase_end(8)
	_check("expiry clears stratagem_cover", not gs.state["units"]["U_SMOKE"].get("flags", {}).get("stratagem_cover", false))
	_check("expiry clears effect_cover", not gs.state["units"]["U_SMOKE"].get("flags", {}).get("effect_cover", false))

	print("\n-- COUNTEROFFENSIVE (15.12) + EPIC CHALLENGE (15.03): flags + expiry --")
	gs.state["meta"]["phase"] = 10  # fight
	var r_co = sm.use_stratagem(1, "counter_offensive", "U_CO")
	_check("counteroffensive use succeeds", r_co.get("success", false), str(r_co))
	_check("fights_first granted", gs.state["units"]["U_CO"].get("flags", {}).get("fights_first", false))
	var r_ec = sm.use_stratagem(1, "epic_challenge", "U_EC")
	_check("epic challenge use succeeds", r_ec.get("success", false), str(r_ec))
	_check("effect_precision_melee granted", gs.state["units"]["U_EC"].get("flags", {}).get("effect_precision_melee", false))
	sm.on_phase_end(10)
	_check("expiry clears fights_first (no all-battle leak)",
		not gs.state["units"]["U_CO"].get("flags", {}).get("fights_first", false))
	_check("expiry clears effect_precision_melee",
		not gs.state["units"]["U_EC"].get("flags", {}).get("effect_precision_melee", false))

	print("\n-- RAPID INGRESS (15.07): not during the first battle round --")
	gs.state["meta"]["phase"] = 8  # 11e RI window: opponent's shooting phase
	gs.state["meta"]["battle_round"] = 1
	var ri1 = sm.can_use_stratagem(1, "rapid_ingress")
	_check("rapid ingress blocked in battle round 1", not ri1.can_use, str(ri1))
	gs.state["meta"]["battle_round"] = 2
	var ri2 = sm.can_use_stratagem(1, "rapid_ingress")
	_check("rapid ingress available from battle round 2", ri2.can_use, str(ri2))
	gs.state["meta"]["battle_round"] = 1

	print("\n-- HEROIC INTERVENTION (15.11): end-of-charge-phase window + modes --")
	pm.transition_to_phase(9)  # CHARGE (active player 2; defender = 1)
	var cp = pm.get_current_phase_instance()
	cp.phase_completed.connect(func(): _phase_completed += 1)
	var r_end = cp.execute_action({"type": "END_CHARGE", "player": 2})
	_check("END_CHARGE opens the HI window instead of completing the phase",
		r_end.get("success", false) and r_end.get("trigger_heroic_intervention", false), str(r_end))
	_check("phase did NOT complete yet", _phase_completed == 0)
	_check("defender (P1) is offered", cp.heroic_intervention_player == 1)
	var elig_names = []
	for e in r_end.get("heroic_intervention_eligible_units", []):
		elig_names.append(e.get("unit_id", ""))
	_check("unengaged defenders within 12\" are eligible (U_HI)", "U_HI" in elig_names, str(elig_names))

	var cp1_before = gs.state["players"]["1"]["cp"]
	# seed 2 rolls [5,4] = 9 — proves the INTO THE FRAY cap (9 -> 6)
	var r_use = cp.execute_action({"type": "USE_HEROIC_INTERVENTION", "unit_id": "U_HI", "player": 1,
		"mode": "into_the_fray", "payload": {"rng_seed": 2}})
	_check("USE (into_the_fray) succeeds", r_use.get("success", false), str(r_use))
	_check("HI costs 1 CP at 11e", gs.state["players"]["1"]["cp"] == cp1_before - 1,
		"cp %d -> %d" % [cp1_before, gs.state["players"]["1"]["cp"]])
	_check("HI charge pending (roll sufficient with seed 2)", not cp.heroic_intervention_pending_charge.is_empty(),
		str(cp.heroic_intervention_pending_charge))
	var dist = int(cp.heroic_intervention_pending_charge.get("distance", 0))
	_check("INTO THE FRAY charge roll capped at 6 (rolled 9)", dist == 6,
		"distance=%d rolls=%s" % [dist, str(cp.heroic_intervention_pending_charge.get("dice_rolls", []))])
	_check("target is the closest enemy within 6\" (U_EN)",
		cp.heroic_intervention_pending_charge.get("targets", []) == ["U_EN"],
		str(cp.heroic_intervention_pending_charge.get("targets", [])))
	_check("mode recorded", str(cp.heroic_intervention_pending_charge.get("mode", "")) == "into_the_fray")
	# Apply a legal HI charge move: ~4" toward U_EN ending in base-to-base
	# contact (the validator requires b2b when achievable) — the END_CHARGE
	# that opened the window owes the phase completion once the move resolves.
	var r_move = cp.execute_action({"type": "APPLY_HEROIC_INTERVENTION_MOVE", "actor_unit_id": "U_HI",
		"payload": {"per_model_paths": {"m0": [[500, 500], [660, 500]]}}})
	_check("HI charge move applies", r_move.get("success", false), str(r_move))
	_check("HI unit is charged_this_turn but NOT fights_first",
		gs.state["units"]["U_HI"].get("flags", {}).get("charged_this_turn", false)
		and not gs.state["units"]["U_HI"].get("flags", {}).get("fights_first", false),
		str(gs.state["units"]["U_HI"].get("flags", {})))
	_check("phase completes after the HI window resolves", _phase_completed == 1)

	print("\n-- 10e sensitivity: no end-of-phase HI window --")
	GameConstants.edition = 10
	gs.state = prev_state.duplicate(true)
	_board()
	pm.transition_to_phase(9)
	var cp10 = pm.get_current_phase_instance()
	var completed10 = []
	cp10.phase_completed.connect(func(): completed10.append(true))
	var r10 = cp10.execute_action({"type": "END_CHARGE", "player": 2})
	_check("e10: END_CHARGE completes the phase immediately",
		r10.get("success", false) and completed10.size() == 1, str(r10))

	gs.state = prev_state
	GameConstants.edition = prev_edition
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
