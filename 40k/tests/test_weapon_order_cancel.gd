extends SceneTree

# T06 — the weapon-order step is a side-anchored panel with Esc to cancel
# (design guidelines §3). The panel is the shooting resolution dock's ordering
# step (right HUD column); this pins the engine half of its Esc:
#
# 1. CONFIRM_TARGETS with two weapon types waits in "awaiting_weapon_order"
#    and the step can still go back (weapon_order_cancel_block_reason() == "").
# 2. CANCEL_WEAPON_ORDER is accepted there and hands the declaration back:
#    the player's own pending assignments return unchanged (weapon, target,
#    bearers, order), the confirmed list and resolution_state are cleared, the
#    shooter stays selected, nothing is rolled (no state changes, the unit has
#    not shot), and weapon_order_cancelled(shooter) fires once.
# 3. It is rejected outside the step: before any confirm, and a second time.
# 4. Re-confirming works and the "Start Sequence" action (RESOLVE_WEAPON_SEQUENCE,
#    what the dock's Roll to Hit sends) still resolves from it.
# 5. Locked in: once the defender has used a stratagem against the declared
#    targets the step cannot go back — the reason names the opponent, and the
#    action is rejected with it. A die rolled at confirm (Unpredictable Genius)
#    locks it the same way.
# 6. StratagemManager.usage_count reads the per-player history.
#
# Usage: godot --headless --path . -s tests/test_weapon_order_cancel.gd

var passed := 0
var failed := 0
var _cancel_signals: Array = []


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])


func _init() -> void:
	create_timer(0.1).timeout.connect(_run)


func _run() -> void:
	if passed > 0 or failed > 0:
		return
	print("\n=== test_weapon_order_cancel ===")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	var sm = root.get_node_or_null("StratagemManager")
	var rules = root.get_node_or_null("RulesEngine")
	_check("GameState / PhaseManager / StratagemManager / RulesEngine autoloads live",
		gs != null and pm != null and sm != null and rules != null)
	if gs == null or pm == null or sm == null or rules == null:
		_finish()
		return
	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition
	var prev_history = sm._usage_history.duplicate(true)
	GameConstants.edition = 11

	_section_usage_count(sm)
	_section_cancel_round_trip(gs, pm, sm, rules)
	_section_locked_by_stratagem(gs, pm, sm, rules)
	_section_locked_by_roll(gs, pm, sm, rules)

	sm._usage_history = prev_history
	GameConstants.edition = prev_edition
	gs.state = prev_state
	_finish()


# Shooter (two ranged weapons, two models) at (1360,400) and an INFANTRY
# target 15" away at (1360,1000): open ground on the boot layout (the same
# geometry test_core_rules_audit_e28e4f7 uses for a visible target). With
# `smoke` the target carries SMOKE, so the defender is offered the 11e core
# SMOKESCREEN (15.10) when it is targeted — a real reaction to the declaration.
func _board(smoke: bool = false) -> Dictionary:
	var weapons := [
		{"name": "Bolter", "type": "Ranged", "range": "24", "attacks": "2",
			"ballistic_skill": "3", "strength": "4", "ap": "0", "damage": "1", "special_rules": ""},
		{"name": "Plasma gun", "type": "Ranged", "range": "24", "attacks": "1",
			"ballistic_skill": "3", "strength": "7", "ap": "-2", "damage": "2", "special_rules": ""},
	]
	return {
		"U_GUN": {"id": "U_GUN", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Gunners", "keywords": ["INFANTRY"],
				"stats": {"move": 6, "toughness": 4, "save": 3, "wounds": 1}, "weapons": weapons},
			"models": [
				{"id": "m1", "alive": true, "wounds": 1, "current_wounds": 1,
					"base_mm": 32, "base_type": "circular", "position": {"x": 1360, "y": 400}},
				{"id": "m2", "alive": true, "wounds": 1, "current_wounds": 1,
					"base_mm": 32, "base_type": "circular", "position": {"x": 1320, "y": 400}}]},
		"U_FOE": {"id": "U_FOE", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "Foe Squad", "keywords": ["INFANTRY", "SMOKE"] if smoke else ["INFANTRY"],
				"stats": {"move": 6, "toughness": 4, "save": 5, "wounds": 1}},
			"models": [
				{"id": "f0", "alive": true, "wounds": 1, "current_wounds": 1,
					"base_mm": 32, "base_type": "circular", "position": {"x": 1360, "y": 1000}},
				{"id": "f1", "alive": true, "wounds": 1, "current_wounds": 1,
					"base_mm": 32, "base_type": "circular", "position": {"x": 1320, "y": 1000}}]},
	}


func _setup(gs, pm, defender_cp: int, smoke: bool = false):
	gs.state["units"] = _board(smoke)
	gs.state["terrain_features"] = []
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = 8
	if not gs.state.has("players"):
		gs.state["players"] = {}
	for p in ["1", "2"]:
		if not gs.state["players"].has(p):
			gs.state["players"][p] = {}
	gs.state["players"]["1"]["cp"] = 0
	gs.state["players"]["2"]["cp"] = defender_cp
	pm.transition_to_phase(8)
	var sp = pm.get_current_phase_instance()
	_cancel_signals.clear()
	if sp != null and sp.has_signal("weapon_order_cancelled"):
		sp.weapon_order_cancelled.connect(func(uid): _cancel_signals.append(uid))
	return sp


# SELECT_SHOOTER + one assignment per weapon (bearer m1 the bolter, m2 the
# plasma gun). Returns the two assignment payloads in declaration order.
func _declare(sp, rules) -> Array:
	var r_sel = sp.execute_action({"type": "SELECT_SHOOTER", "actor_unit_id": "U_GUN", "player": 1,
		"payload": {"shooting_type": "normal"}})
	_check("SELECT_SHOOTER succeeds", r_sel.get("success", false), str(r_sel.get("errors", r_sel.get("error", ""))))
	var bolter := str(rules.generate_weapon_id("Bolter", "Ranged"))
	var plasma := str(rules.generate_weapon_id("Plasma gun", "Ranged"))
	var declared := [
		{"weapon_id": bolter, "target_unit_id": "U_FOE", "model_ids": ["m1"]},
		{"weapon_id": plasma, "target_unit_id": "U_FOE", "model_ids": ["m2"]},
	]
	for a in declared:
		var r_as = sp.execute_action({"type": "ASSIGN_TARGET", "actor_unit_id": "U_GUN", "player": 1,
			"payload": a.duplicate(true)})
		_check("ASSIGN_TARGET %s succeeds" % a.weapon_id, r_as.get("success", false), str(r_as.get("errors", r_as.get("error", ""))))
	return declared


func _same_declaration(got: Array, want: Array) -> bool:
	if got.size() != want.size():
		return false
	for i in range(want.size()):
		var g: Dictionary = got[i]
		var w: Dictionary = want[i]
		if str(g.get("weapon_id", "")) != str(w.weapon_id) or str(g.get("target_unit_id", "")) != str(w.target_unit_id):
			return false
		if Array(g.get("model_ids", [])) != Array(w.model_ids):
			return false
	return true


# Defender reactive window (if any) declined, so the step is reached.
func _decline_reactive(sp) -> void:
	if sp.awaiting_reactive_stratagem:
		var r = sp.execute_action({"type": "DECLINE_REACTIVE_STRATAGEM", "player": 2})
		_check("defender declines the reactive window", r.get("success", false), str(r))


func _section_usage_count(sm) -> void:
	print("\n-- StratagemManager.usage_count --")
	sm._usage_history = {"1": [], "2": [{"stratagem_id": "x"}, {"stratagem_id": "y"}]}
	_check("usage_count reads each player's history (0 / 2)", sm.usage_count(1) == 0 and sm.usage_count(2) == 2,
		"%d / %d" % [sm.usage_count(1), sm.usage_count(2)])
	sm._usage_history = {"1": [], "2": []}


func _section_cancel_round_trip(gs, pm, sm, rules) -> void:
	print("\n-- CONFIRM -> weapon-order step -> CANCEL_WEAPON_ORDER -> re-confirm -> Start Sequence --")
	sm._usage_history = {"1": [], "2": []}
	var sp = _setup(gs, pm, 0)
	_check("ShootingPhase instance", sp != null and sp.has_method("weapon_order_cancel_block_reason"))
	if sp == null:
		return
	var early = sp.validate_action({"type": "CANCEL_WEAPON_ORDER", "player": 1})
	_check("no shooter yet: CANCEL_WEAPON_ORDER rejected", not early.get("valid", true), str(early))
	var declared := _declare(sp, rules)
	var before_confirm = sp.execute_action({"type": "CANCEL_WEAPON_ORDER", "player": 1})
	_check("targets not confirmed yet: CANCEL_WEAPON_ORDER rejected", not before_confirm.get("success", true)
		and "no weapon order" in str(before_confirm.get("error", "")).to_lower(), str(before_confirm))

	var r_cf = sp.execute_action({"type": "CONFIRM_TARGETS", "actor_unit_id": "U_GUN", "player": 1})
	_check("CONFIRM_TARGETS succeeds", r_cf.get("success", false), str(r_cf.get("errors", r_cf.get("error", ""))))
	_decline_reactive(sp)
	_check("two weapon types: the phase waits in the weapon-order step",
		str(sp.resolution_state.get("phase", "")) == "awaiting_weapon_order", str(sp.resolution_state))
	_check("confirmed list holds both weapons, pending is empty",
		sp.confirmed_assignments.size() == 2 and sp.pending_assignments.is_empty(),
		"%d confirmed / %d pending" % [sp.confirmed_assignments.size(), sp.pending_assignments.size()])
	_check("the step can still go back (no block reason)", sp.weapon_order_cancel_block_reason() == "",
		sp.weapon_order_cancel_block_reason())

	var shot_before: Array = sp.units_that_shot.duplicate()
	var units_before = gs.state["units"].duplicate(true)
	var r_cancel = sp.execute_action({"type": "CANCEL_WEAPON_ORDER", "actor_unit_id": "U_GUN", "player": 1})
	_check("CANCEL_WEAPON_ORDER succeeds in the step", r_cancel.get("success", false), str(r_cancel.get("errors", r_cancel.get("error", ""))))
	_check("result flags weapon_order_cancelled", r_cancel.get("weapon_order_cancelled", false), str(r_cancel.keys()))
	_check("no game-state changes (nothing rolled)", (r_cancel.get("changes", []) as Array).is_empty(), str(r_cancel.get("changes", [])))
	_check("the declaration comes back unchanged (weapon, target, bearers, order)",
		_same_declaration(sp.pending_assignments, declared), str(sp.pending_assignments))
	_check("confirmed list and resolution_state cleared",
		sp.confirmed_assignments.is_empty() and sp.resolution_state.is_empty(),
		"%d confirmed, state=%s" % [sp.confirmed_assignments.size(), str(sp.resolution_state)])
	_check("the shooter stays selected", sp.active_shooter_id == "U_GUN", sp.active_shooter_id)
	_check("the unit has not shot", sp.units_that_shot == shot_before and not "U_GUN" in sp.units_that_shot, str(sp.units_that_shot))
	_check("units untouched (no wounds, no flags from a roll)", gs.state["units"] == units_before)
	_check("weapon_order_cancelled fired once with the shooter", _cancel_signals == ["U_GUN"], str(_cancel_signals))

	var again = sp.execute_action({"type": "CANCEL_WEAPON_ORDER", "actor_unit_id": "U_GUN", "player": 1})
	_check("a second CANCEL_WEAPON_ORDER is rejected (no step open)", not again.get("success", true), str(again))

	var r_cf2 = sp.execute_action({"type": "CONFIRM_TARGETS", "actor_unit_id": "U_GUN", "player": 1})
	_check("re-confirming the handed-back declaration succeeds", r_cf2.get("success", false), str(r_cf2.get("errors", r_cf2.get("error", ""))))
	_decline_reactive(sp)
	_check("... and opens the weapon-order step again",
		str(sp.resolution_state.get("phase", "")) == "awaiting_weapon_order" and sp.confirmed_assignments.size() == 2,
		str(sp.resolution_state))
	var r_seq = sp.execute_action({"type": "RESOLVE_WEAPON_SEQUENCE", "actor_unit_id": "U_GUN", "player": 1,
		"payload": {"weapon_order": sp.confirmed_assignments.duplicate(true), "fast_roll": false}})
	_check("Start Sequence (RESOLVE_WEAPON_SEQUENCE) still resolves after a cancel", r_seq.get("success", false),
		str(r_seq.get("errors", r_seq.get("error", ""))))
	_check("... into the staged sequence (the step is over)",
		str(sp.resolution_state.get("phase", "")) != "awaiting_weapon_order" and str(sp.resolution_state.get("mode", "")) == "sequential_staged",
		str(sp.resolution_state.get("mode", "?")))
	var late = sp.validate_action({"type": "CANCEL_WEAPON_ORDER", "player": 1})
	_check("once dice are rolling CANCEL_WEAPON_ORDER is rejected", not late.get("valid", true), str(late))


func _section_locked_by_stratagem(gs, pm, sm, rules) -> void:
	print("\n-- a stratagem used against the declared targets locks them in --")
	sm._usage_history = {"1": [], "2": []}
	var sp = _setup(gs, pm, 3, true)
	if sp == null:
		return
	_declare(sp, rules)
	var cp_before := int(gs.state["players"]["2"]["cp"])
	var r_cf = sp.execute_action({"type": "CONFIRM_TARGETS", "actor_unit_id": "U_GUN", "player": 1})
	_check("CONFIRM_TARGETS succeeds (defender has CP)", r_cf.get("success", false), str(r_cf.get("errors", r_cf.get("error", ""))))
	_check("targeting the SMOKE unit pauses on the defender's reactive window", sp.awaiting_reactive_stratagem,
		str(r_cf.keys()))
	# The real path: the defender uses the offered reactive stratagem.
	var offer: Dictionary = {}
	for entry in r_cf.get("available_stratagems", []):
		var units: Array = entry.get("eligible_units", [])
		if not units.is_empty():
			offer = {"stratagem_id": str(entry.get("stratagem", {}).get("id", "")), "target_unit_id": str(units[0])}
			break
	print("  (reactive offers: %s)" % str(r_cf.get("available_stratagems", []).map(func(e): return str(e.get("stratagem", {}).get("name", "?")))))
	_check("a reactive stratagem is offered to the defender", not offer.is_empty(), str(r_cf.get("available_stratagems", [])))
	if offer.is_empty():
		return
	var r_use = sp.execute_action({"type": "USE_REACTIVE_STRATAGEM", "player": 2,
		"stratagem_id": offer.stratagem_id, "target_unit_id": offer.target_unit_id})
	_check("the defender uses %s on %s (CP spent)" % [offer.stratagem_id, offer.target_unit_id],
		r_use.get("success", false) and int(gs.state["players"]["2"]["cp"]) < cp_before,
		"%s cp %d -> %d" % [str(r_use.get("errors", r_use.get("error", ""))), cp_before, int(gs.state["players"]["2"]["cp"])])
	if sp.awaiting_reactive_stratagem:
		_decline_reactive(sp)
	_check("the phase waits in the weapon-order step",
		str(sp.resolution_state.get("phase", "")) == "awaiting_weapon_order", str(sp.resolution_state))
	var reason: String = sp.weapon_order_cancel_block_reason()
	_check("the step is locked in, naming the opponent's stratagem", "opponent" in reason and "stratagem" in reason, reason)
	var r_cancel = sp.execute_action({"type": "CANCEL_WEAPON_ORDER", "actor_unit_id": "U_GUN", "player": 1})
	_check("CANCEL_WEAPON_ORDER is rejected with that reason",
		not r_cancel.get("success", true) and reason in str(r_cancel.get("error", "")), str(r_cancel))
	_check("the confirmed targets stand", sp.confirmed_assignments.size() == 2 and sp.pending_assignments.is_empty(),
		"%d confirmed / %d pending" % [sp.confirmed_assignments.size(), sp.pending_assignments.size()])


func _section_locked_by_roll(gs, pm, sm, rules) -> void:
	print("\n-- a die rolled at confirm (Unpredictable Genius) locks the targets in --")
	sm._usage_history = {"1": [], "2": []}
	var sp = _setup(gs, pm, 0)
	if sp == null:
		return
	_declare(sp, rules)
	sp.execute_action({"type": "CONFIRM_TARGETS", "actor_unit_id": "U_GUN", "player": 1})
	_decline_reactive(sp)
	_check("step open and cancellable before the roll", sp.weapon_order_cancel_block_reason() == "",
		sp.weapon_order_cancel_block_reason())
	# The CONFIRM_TARGETS hook sets this when OrkDetachments11e.ug_on_targets_confirmed
	# reports applied (a D6 rolled against the declared target).
	sp._wo_lock_reason = "Unpredictable Genius has already been rolled against these targets"
	var r_cancel = sp.execute_action({"type": "CANCEL_WEAPON_ORDER", "actor_unit_id": "U_GUN", "player": 1})
	_check("CANCEL_WEAPON_ORDER is rejected once a die was rolled for the targets",
		not r_cancel.get("success", true) and "Unpredictable Genius" in str(r_cancel.get("error", "")), str(r_cancel))
	# A fresh confirm (new declaration) clears the previous lock.
	sp.resolution_state = {}
	sp.confirmed_assignments = []
	_declare(sp, rules)
	sp.execute_action({"type": "CONFIRM_TARGETS", "actor_unit_id": "U_GUN", "player": 1})
	_decline_reactive(sp)
	_check("a new declaration starts unlocked", sp.weapon_order_cancel_block_reason() == "", sp.weapon_order_cancel_block_reason())


func _finish() -> void:
	print("")
	print("Result: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
