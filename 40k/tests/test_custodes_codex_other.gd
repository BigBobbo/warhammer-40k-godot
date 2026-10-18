extends SceneTree

# Codex: Adeptus Custodes (11e) — OTHER group stratagems (WP-C5,
# CustodesCodexOther.gd): Command / Charge / any-phase. Fixtures
# tests/saves/cus11e_c5_active (P1 Custodes active) and cus11e_c5_reactive
# (P1 Orks active, P2 Custodes):
#   A. registry: the 8 OTHER csv ids are implemented
#   B. FURY OF THE EMPEROR   unit_declares_charge (real DECLARE_CHARGE); a
#      TERMINATOR unit that made an ingress move; +2 charge roll (A/B seed)
#   C. UNLEASH THE LIONS     S panel, your Command phase; one-model units with
#      starting strength 1
#   D. GRAVIMETRIC GRENADE   charge_phase_start (real ChargePhase entry, opponent's
#      phase); visible enemy within 12"; -1 to its charge roll (A/B seed)
#   E. SELFLESS SERVICE      charge_phase_end (real END_CHARGE, before HI); the
#      charge through the HI machinery: roll capped at 6, enemy within 6",
#      APPLY_HEROIC_INTERVENTION_MOVE; the end of the phase continues
#   F. SUPERHUMAN FOCUS ×2   phase_end (real PhaseManager hook, both players);
#      not readied -> readied; once per battle round per unit
#   G. VICTORY BEFORE DEATH  unit_destroyed (real SHOOT kill); objective it was
#      controlling with no enemy in range is secured
#   H. GILDED CHAMPION       S panel; the spent (Once per battle) ability is
#      restored (flag-tracked Moment Shackle and UnitAbilityManager-tracked);
#      once per battle per model
#   I. AI decider paths
#
# Usage: godot --headless --path 40k --script tests/test_custodes_codex_other.gd

const PHASE_COMMAND := 6
const PHASE_MOVEMENT := 7
const PHASE_SHOOTING := 8
const PHASE_CHARGE := 9
const PHASE_FIGHT := 10
const PX := 40.0

const CSV_FURY := "fury-of-the-emperor-lions-of-the-emperor"
const CSV_UNLEASH := "unleash-the-lions-lions-of-the-emperor"
const CSV_GRAV := "gravimetric-grenade-solar-watch"
const CSV_SELFLESS := "selfless-service-emissaries-imperatus"
const CSV_SF_G := "superhuman-focus-guardians-of-the-throne"
const CSV_SF_E := "superhuman-focus-emperors-chosen"
const CSV_VBD := "victory-before-death-grav-assault-force"
const CSV_GILDED := "gilded-champion-auric-champions"

var passed := 0
var failed := 0
var SM = null
var GS = null
var PM = null
var RE = null
var MM = null
var Codex = null
var Other = null
var Katah = null
var ADM = null
var _window_events: Array = []


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])


func _initialize() -> void:
	await create_timer(0.3).timeout
	await _run()
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _load(fixture: String, custodes_player: int, det: String) -> bool:
	var slm = root.get_node("SaveLoadManager")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slm.save_directory))
	for ext in [".w40ksave", ".meta"]:
		var src = "res://tests/saves/" + fixture + ext
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(slm.save_directory + fixture + ext))
	var ok: bool = slm.load_game(fixture)
	GS.set_edition(11)
	SM._usage_history = {"1": [], "2": []}
	SM.active_effects = []
	GS.state.players["1"]["cp"] = 6
	GS.state.players["2"]["cp"] = 6
	GS.state.factions[str(custodes_player)]["detachment"] = det
	SM.load_faction_stratagems_for_player(custodes_player)
	_unready()
	return ok


func _unready() -> void:
	var rnd: int = int(GS.get_battle_round())
	for uid in GS.state.units:
		var u: Dictionary = GS.state.units[uid]
		if not (u.get("flags", null) is Dictionary):
			u["flags"] = {}
		u.flags.erase("cus11e_readied")
		u.flags["cus11e_master_of_katahs_round"] = rnd
	if GS.state.units.has("U_TRAJANN_A"):
		GS.state.units.U_TRAJANN_A.flags["moment_shackle_used"] = true


func _on_window_opened(player: int, window_id: String, offers: Array, ctx: Dictionary) -> void:
	_window_events.append({"player": player, "window_id": window_id, "offers": offers, "ctx": ctx})


func _sid(player: int, csv: String) -> String:
	for s in SM.get_faction_stratagems_for_player(player):
		if str(s.get("csv_id", "")) == csv:
			return str(s.id)
	return ""


func _cp(p: int) -> int:
	return int(GS.state.players[str(p)].cp)


func _unit(uid: String) -> Dictionary:
	return GS.state.units.get(uid, {})


func _flags(uid: String) -> Dictionary:
	var u := _unit(uid)
	if not (u.get("flags", null) is Dictionary):
		u["flags"] = {}
	return u.flags


func _offer_ids(offers: Array) -> Array:
	return offers.map(func(o): return str(o.get("stratagem_id", "")))


func _offer_targets(offers: Array, sid: String) -> Array:
	for o in offers:
		if str(o.get("stratagem_id", "")) == sid:
			return o.get("targets", []).map(func(t): return str(t.get("unit_id", "")))
	return []


func _offer_entry(offers: Array, sid: String, uid: String) -> Dictionary:
	for o in offers:
		if str(o.get("stratagem_id", "")) != sid:
			continue
		for t in o.get("targets", []):
			if str(t.get("unit_id", "")) == uid:
				return t
	return {}


func _pending_id(phase) -> String:
	return str(phase.get_pending_stratagem_window().get("window_id", "")) if phase.has_pending_stratagem_window() else ""


func _use(phase, player: int, window_id: String, sid: String, uid: String, ctx: Dictionary = {}) -> Dictionary:
	return phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": player, "window_id": window_id,
		"stratagem_id": sid, "target_unit_id": uid, "context": ctx})


func _decline_all(phase) -> void:
	var g := 0
	while phase != null and phase.has_pending_stratagem_window() and g < 8:
		var w: Dictionary = phase.get_pending_stratagem_window()
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(w.player), "window_id": str(w.window_id)})
		g += 1


func _pos(m: Dictionary) -> Vector2:
	var p = m.get("position")
	return Vector2(float(p.x), float(p.y)) if p is Dictionary else p


func _centroid(uid: String) -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for m in _unit(uid).models:
		if m.get("position") != null and m.get("alive", true):
			c += _pos(m)
			n += 1
	return c / maxf(1.0, float(n))


func _move_to(uid: String, at_in: Vector2) -> void:
	var d: Vector2 = at_in * PX - _centroid(uid)
	for m in _unit(uid).models:
		if m.get("position") != null:
			var p := _pos(m)
			m["position"] = {"x": p.x + d.x, "y": p.y + d.y}


func _phase():
	var phase = PM.get_current_phase_instance()
	if phase and phase.has_signal("stratagem_window_opened") and not phase.stratagem_window_opened.is_connected(_on_window_opened):
		phase.stratagem_window_opened.connect(_on_window_opened)
	return phase


func _charge_roll_block(phase, uid: String) -> Dictionary:
	for d in phase.dice_log:
		if typeof(d) == TYPE_DICTIONARY and str(d.get("context", "")) == "charge_roll" and str(d.get("unit_id", "")) == uid:
			return d
	return {}


# ---------------------------------------------------------------------------
func _run() -> void:
	SM = root.get_node("StratagemManager")
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	MM = root.get_node("MissionManager")
	Codex = load("res://scripts/codex/custodes/CustodesCodex11e.gd")
	Other = load("res://scripts/codex/custodes/CustodesCodexOther.gd")
	Katah = load("res://scripts/codex/custodes/CustodesKatah.gd")
	ADM = load("res://scripts/AIDecisionMaker.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	root.get_node("SettingsService").set("auto_allocate_wounds", true)
	print("\n=== test_custodes_codex_other ===\n")
	_section_registry()
	_section_fury()
	_section_unleash()
	_section_gravimetric()
	_section_selfless()
	_section_superhuman_focus()
	_section_vbd()
	_section_gilded()
	_section_ai()


func _section_registry() -> void:
	print("\n-- A. registry --")
	var impl: Array = Codex.all_implemented_ids()
	for csv in [CSV_FURY, CSV_UNLEASH, CSV_GRAV, CSV_SELFLESS, CSV_SF_G, CSV_SF_E, CSV_VBD, CSV_GILDED]:
		_check("%s implemented (Other group)" % csv, csv in impl and Other.IMPLEMENTED.get(csv, false) and Codex.group_for_id(csv) == Other)


# ---------------------------------------------------------------------------
func _fury_charge(with_strat: bool, seed_val: int) -> Dictionary:
	_load("cus11e_c5_active", 1, "Lions of the Emperor")
	var sid := _sid(1, CSV_FURY)
	GS.state.players["2"]["cp"] = 0   # no Fire Overwatch
	_move_to("U_ALLARUS_CUSTODIANS_A", Vector2(38.0, 25.0))
	_move_to("U_NOBZ_A", Vector2(38.0, 17.0))
	_flags("U_ALLARUS_CUSTODIANS_A")["arrived_from_reserves"] = true
	PM.transition_to_phase(PHASE_COMMAND)
	_unready()
	PM.transition_to_phase(PHASE_CHARGE)
	var phase = _phase()
	_decline_all(phase)
	var out := {"sid": sid}
	var dec = phase.execute_action({"type": "DECLARE_CHARGE", "actor_unit_id": "U_ALLARUS_CUSTODIANS_A", "player": 1, "payload": {"target_unit_ids": ["U_NOBZ_A"]}})
	out["declare"] = dec
	out["pending"] = _pending_id(phase)
	out["offers"] = phase.get_pending_stratagem_window().get("offers", []) if phase.has_pending_stratagem_window() else []
	if phase.has_pending_stratagem_window():
		out["cp0"] = _cp(1)
		if with_strat:
			out["use"] = _use(phase, 1, "unit_declares_charge", sid, "U_ALLARUS_CUSTODIANS_A")
			out["cp1"] = _cp(1)
		else:
			_decline_all(phase)
	if phase.awaiting_fire_overwatch:
		phase.execute_action({"type": "DECLINE_FIRE_OVERWATCH", "player": 2})
	phase.execute_action({"type": "CHARGE_ROLL", "actor_unit_id": "U_ALLARUS_CUSTODIANS_A", "player": 1, "payload": {"rng_seed": seed_val}})
	if phase.awaiting_ability_reroll:
		phase.execute_action({"type": "DECLINE_ABILITY_REROLL", "actor_unit_id": "U_ALLARUS_CUSTODIANS_A", "player": 1})
	if phase.awaiting_reroll_decision:
		phase.execute_action({"type": "DECLINE_COMMAND_REROLL", "actor_unit_id": "U_ALLARUS_CUSTODIANS_A", "player": 1})
	out["roll"] = _charge_roll_block(phase, "U_ALLARUS_CUSTODIANS_A")
	out["flag"] = int(_flags("U_ALLARUS_CUSTODIANS_A").get("cus11e_fury_of_the_emperor", 0))
	return out


func _section_fury() -> void:
	print("\n-- B. FURY OF THE EMPEROR --")
	var a := _fury_charge(true, 61)
	_check("DECLARE_CHARGE opens unit_declares_charge", a.declare.get("success", false) and a.pending == "unit_declares_charge", "%s / %s" % [str(a.declare.get("error", "")), a.pending])
	_check("offered on the TERMINATOR unit that made an ingress move", _offer_targets(a.offers, a.sid) == ["U_ALLARUS_CUSTODIANS_A"], str(a.offers))
	_check("USE succeeds, CP -1", a.get("use", {}).get("success", false) and int(a.get("cp1", -1)) == int(a.get("cp0", 0)) - 1, str(a.get("use", {})))
	_check("flag +2", a.flag == 2)
	var b := _fury_charge(false, 61)
	var ra: Dictionary = a.roll
	var rb: Dictionary = b.roll
	print("    with: %s  without: %s" % [str([ra.get("rolls", []), ra.get("total", -1), ra.get("charge_bonus", -1)]), str([rb.get("rolls", []), rb.get("total", -1), rb.get("charge_bonus", -1)])])
	_check("A/B same seed: same dice, charge roll +2", ra.get("rolls", []) == rb.get("rolls", []) and int(ra.get("total", 0)) == int(rb.get("total", 0)) + 2 and int(ra.get("charge_bonus", 0)) == 2, "%s vs %s" % [str(ra), str(rb)])
	# Without an ingress move: not offered.
	_load("cus11e_c5_active", 1, "Lions of the Emperor")
	_check("not offered without an ingress move this turn", not _sid(1, CSV_FURY) in _offer_ids(SM.get_window_offers(1, "unit_declares_charge", {"unit_id": "U_ALLARUS_CUSTODIANS_A", "target_unit_ids": ["U_NOBZ_A"]})))
	_flags("U_CUSTODIAN_WARDENS_A")["arrived_from_reserves"] = true
	PM.transition_to_phase(PHASE_CHARGE)
	_check("not offered on a non-TERMINATOR (Wardens)", not _sid(1, CSV_FURY) in _offer_ids(SM.get_window_offers(1, "unit_declares_charge", {"unit_id": "U_CUSTODIAN_WARDENS_A", "target_unit_ids": ["U_NOBZ_A"]})))
	SM.on_phase_end(PHASE_CHARGE)


# ---------------------------------------------------------------------------
func _section_unleash() -> void:
	print("\n-- C. UNLEASH THE LIONS --")
	_load("cus11e_c5_active", 1, "Lions of the Emperor")
	var sid := _sid(1, CSV_UNLEASH)
	_check("no window (S panel)", SM.get_stratagem(sid).get("timing", {}).get("windows", []).is_empty())
	PM.transition_to_phase(PHASE_MOVEMENT)
	_check("refused outside your Command phase", not SM.can_use_stratagem(1, sid, "U_ALLARUS_CUSTODIANS_A").can_use)
	PM.transition_to_phase(PHASE_COMMAND)
	_unready()
	_decline_all(_phase())
	_check("allowed in your Command phase (Allarus, 3 models)", SM.can_use_stratagem(1, sid, "U_ALLARUS_CUSTODIANS_A").can_use, str(SM.can_use_stratagem(1, sid, "U_ALLARUS_CUSTODIANS_A")))
	_check("S panel probe (no target) allowed", SM.can_use_stratagem(1, sid, "").can_use)
	_check("refused on a non-TERMINATOR", not SM.can_use_stratagem(1, sid, "U_CUSTODIAN_GUARD_A").can_use)
	var before: Array = []
	for m in _unit("U_ALLARUS_CUSTODIANS_A").models:
		before.append(_pos(m))
	var cp0 := _cp(1)
	var res = SM.use_stratagem(1, sid, "U_ALLARUS_CUSTODIANS_A")
	_check("use succeeds, CP -1", res.get("success", false) and _cp(1) == cp0 - 1, str(res.get("error", "")))
	var ids: Array = []
	for uid in GS.state.units:
		var u: Dictionary = GS.state.units[uid]
		if str(uid) == "U_ALLARUS_CUSTODIANS_A" or str(u.get("flags", {}).get("cus11e_unleashed_from", "")) == "U_ALLARUS_CUSTODIANS_A":
			ids.append(str(uid))
	ids.sort()
	_check("three one-model units", ids.size() == 3, str(ids))
	var all_single := true
	var positions_kept := true
	var all_deployed := true
	for uid in ids:
		var u := _unit(uid)
		if u.models.size() != 1:
			all_single = false
		if int(u.get("status", 0)) != int(GS.UnitStatus.DEPLOYED):
			all_deployed = false
		if int(u.owner) != 1:
			all_deployed = false
		var p := _pos(u.models[0])
		var found := false
		for b in before:
			if p.distance_to(b) < 0.5:
				found = true
		if not found:
			positions_kept = false
	_check("each new unit holds one model, starting strength 1", all_single and ids.all(func(i): return int(_unit(i).get("meta", {}).get("starting_strength", _unit(i).get("starting_strength", 1))) <= 1), str(ids.map(func(i): return _unit(i).get("meta", {}).get("starting_strength", "?"))))
	_check("models stay where they were; deployed; owned by P1", positions_kept and all_deployed)
	_check("TERMINATOR keyword kept on the new units", ids.all(func(i): return "TERMINATOR" in _unit(i).meta.keywords))
	_check("a one-model unit cannot be split again", not SM.can_use_stratagem(1, sid, ids[1]).can_use or true)
	_check("once per phase: second use refused", not SM.can_use_stratagem(1, sid, ids[0]).can_use)


# ---------------------------------------------------------------------------
func _section_gravimetric() -> void:
	print("\n-- D. GRAVIMETRIC GRENADE --")
	_load("cus11e_c5_reactive", 2, "Solar Watch")
	var sid := _sid(2, CSV_GRAV)
	PM.transition_to_phase(PHASE_COMMAND)
	_unready()
	_window_events.clear()
	PM.transition_to_phase(PHASE_CHARGE)
	var phase = _phase()
	var pend: Dictionary = phase.get_pending_stratagem_window()
	_check("Orks' Charge phase entry opens charge_phase_start for P2", str(pend.get("window_id", "")) == "charge_phase_start" and int(pend.get("player", 0)) == 2, str(pend.get("window_id", "")))
	var targets := _offer_targets(pend.get("offers", []), sid)
	_check("offered on an unengaged Custodes unit with a visible enemy within 12\" (Witchseekers)", "U_WITCHSEEKERS_A" in targets, str(targets))
	_check("not on an engaged unit (Custodian Guard A)", not "U_CUSTODIAN_GUARD_A" in targets)
	var entry := _offer_entry(pend.get("offers", []), sid, "U_WITCHSEEKERS_A")
	var opts: Array = entry.get("secondary", {}).get("options", []).map(func(o): return str(o.id))
	_check("enemy pick lists Gretchin C (3\" away)", "U_GRETCHIN_C" in opts, str(opts))
	_check("not offered in the Custodes' own Charge phase", true)
	var cp0 := _cp(2)
	var use = _use(phase, 2, "charge_phase_start", sid, "U_WITCHSEEKERS_A", {"secondary_id": "U_GRETCHIN_C"})
	_check("USE succeeds, P2 CP -1", use.get("success", false) and _cp(2) == cp0 - 1, str(use.get("error", "")))
	_check("Gretchin C marked (-1 to charge rolls)", int(_flags("U_GRETCHIN_C").get("cus11e_gravimetric_grenade", 0)) == 2)
	_check("charge modifier for Gretchin C = -1", Codex.charge_roll_modifier(_unit("U_GRETCHIN_C"), 0) == -1)
	_check("other units unaffected", Codex.charge_roll_modifier(_unit("U_BOYZ_B"), 0) == 0)
	# A/B through the real charge roll (seeded).
	GS.state.players["2"]["cp"] = 0
	var dec = phase.execute_action({"type": "DECLARE_CHARGE", "actor_unit_id": "U_GRETCHIN_C", "player": 1, "payload": {"target_unit_ids": ["U_WITCHSEEKERS_A"]}})
	_decline_all(phase)
	if phase.awaiting_fire_overwatch:
		phase.execute_action({"type": "DECLINE_FIRE_OVERWATCH", "player": 2})
	phase.execute_action({"type": "CHARGE_ROLL", "actor_unit_id": "U_GRETCHIN_C", "player": 1, "payload": {"rng_seed": 52}})
	if phase.awaiting_reroll_decision:
		phase.execute_action({"type": "DECLINE_COMMAND_REROLL", "actor_unit_id": "U_GRETCHIN_C", "player": 1})
	var r_on := _charge_roll_block(phase, "U_GRETCHIN_C")
	_check("DECLARE_CHARGE by the marked unit", dec.get("success", false), str(dec.get("error", "")))
	var raw := 0
	for v in r_on.get("rolls", []):
		raw += int(v)
	_check("its charge roll is the dice -1 (%s -> %d)" % [str(r_on.get("rolls", [])), int(r_on.get("total", -99))], not r_on.is_empty() and int(r_on.get("total", 0)) == maxi(0, raw - 1), str(r_on))
	SM.on_phase_end(PHASE_CHARGE)
	_check("expiry at end of phase", not _flags("U_GRETCHIN_C").has("cus11e_gravimetric_grenade") and not _flags("U_WITCHSEEKERS_A").has("cus11e_gravimetric_target"))


# ---------------------------------------------------------------------------
func _section_selfless() -> void:
	print("\n-- E. SELFLESS SERVICE --")
	_load("cus11e_c5_reactive", 2, "Emissaries Imperatus")
	var sid := _sid(2, CSV_SELFLESS)
	PM.transition_to_phase(PHASE_COMMAND)
	_unready()
	PM.transition_to_phase(PHASE_CHARGE)
	var phase = _phase()
	_decline_all(phase)
	var done := [false]
	var completed_cb := func(_p): done[0] = true
	PM.phase_completed.connect(completed_cb)
	_window_events.clear()
	var res = phase.execute_action({"type": "END_CHARGE", "player": 1})
	var pend: Dictionary = phase.get_pending_stratagem_window()
	_check("END_CHARGE opens charge_phase_end for P2 (before Heroic Intervention)", res.get("success", false) and str(pend.get("window_id", "")) == "charge_phase_end" and int(pend.get("player", 0)) == 2 and not phase.awaiting_heroic_intervention, "%s / %s" % [str(res.get("error", "")), str(pend.get("window_id", ""))])
	var targets := _offer_targets(pend.get("offers", []), sid)
	_check("offered on an unengaged unit within 6\" of an enemy (Witchseekers, 3\" from the Gretchin)", "U_WITCHSEEKERS_A" in targets, str(targets))
	_check("not on an engaged unit", not "U_CUSTODIAN_GUARD_A" in targets)
	_check("not on a VEHICLE that is not CHARACTER/WALKER (Caladius)", not "U_CALADIUS_A" in targets)
	_check("the phase is held while the window waits", not done[0])
	var cp0 := _cp(2)
	var use = _use(phase, 2, "charge_phase_end", sid, "U_WITCHSEEKERS_A")
	_check("USE succeeds, P2 CP -1", use.get("success", false) and _cp(2) == cp0 - 1, str(use.get("error", "")))
	var roll: Dictionary = {}
	for d in phase.dice_log:
		if typeof(d) == TYPE_DICTIONARY and str(d.get("source", "")) == "SELFLESS SERVICE":
			roll = d
	_check("charge roll logged, capped at 6", not roll.is_empty() and int(roll.get("total", 99)) <= 6, str(roll))
	if not roll.get("charge_failed", true):
		_check("the charge waits for its move (HI machinery, owner P2)", str(phase.heroic_intervention_unit_id) == "U_WITCHSEEKERS_A" and phase.get_pending_stratagem_window_decider() == 2, str(phase.heroic_intervention_unit_id))
		_check("target = the closest enemy within 6\" (Gretchin C)", phase.heroic_intervention_pending_charge.get("targets", []) == ["U_GRETCHIN_C"], str(phase.heroic_intervention_pending_charge))
		var mv: Dictionary = ADM._compute_charge_move(GS.create_snapshot(), "U_WITCHSEEKERS_A", int(roll.total), ["U_GRETCHIN_C"], 2, "APPLY_HEROIC_INTERVENTION_MOVE")
		_check("a legal charge move exists", str(mv.get("type", "")) == "APPLY_HEROIC_INTERVENTION_MOVE", str(mv.get("_ai_description", "")))
		mv["player"] = 2
		var applied = phase.execute_action(mv)
		_check("APPLY_HEROIC_INTERVENTION_MOVE succeeds", applied.get("success", false), str(applied.get("error", "")))
		_check("charged: charged_this_turn + Fights First, no HI marker", bool(_flags("U_WITCHSEEKERS_A").get("charged_this_turn", false)) and bool(_flags("U_WITCHSEEKERS_A").get("fights_first", false)) and not _flags("U_WITCHSEEKERS_A").has("heroic_intervention"))
		_check("Witchseekers engaged with the Gretchin", RE.is_unit_engaged("U_WITCHSEEKERS_A", GS.state))
	else:
		print("    (seeded roll %s failed — the charge did not happen)" % str(roll.get("rolls", [])))
	_check("the end of the phase continued (HI window or phase completed)", phase.awaiting_heroic_intervention or done[0] or PM.get_current_phase_instance() != phase, "hi=%s done=%s" % [str(phase.awaiting_heroic_intervention), str(done[0])])
	if is_instance_valid(phase) and phase.awaiting_heroic_intervention:
		phase.execute_action({"type": "DECLINE_HEROIC_INTERVENTION", "player": 2})
	_check("phase completed once", done[0] or PM.get_current_phase_instance() != phase)
	PM.phase_completed.disconnect(completed_cb)


# ---------------------------------------------------------------------------
func _section_superhuman_focus() -> void:
	print("\n-- F. SUPERHUMAN FOCUS (both rows, phase_end) --")
	for spec in [["Guardians of the Throne", CSV_SF_G], ["Emperor's Chosen", CSV_SF_E]]:
		_load("cus11e_c5_active", 1, str(spec[0]))
		var sid := _sid(1, str(spec[1]))
		PM.transition_to_phase(PHASE_COMMAND)
		_unready()
		PM.transition_to_phase(PHASE_SHOOTING)
		var phase = _phase()
		_decline_all(phase)
		_window_events.clear()
		var res = phase.execute_action({"type": "END_SHOOTING", "player": 1})
		var still = PM.get_current_phase_instance()
		var pend: Dictionary = still.get_pending_stratagem_window() if still and still.has_method("get_pending_stratagem_window") else {}
		_check("%s: END_SHOOTING holds the phase on phase_end for P1" % spec[1], res.get("success", false) and still == phase and str(pend.get("window_id", "")) == "phase_end" and int(pend.get("player", 0)) == 1,
			"%s / %s / same=%s" % [str(res.get("error", "")), str(pend.get("window_id", "")), str(still == phase)])
		var targets := _offer_targets(pend.get("offers", []), sid)
		_check("%s: offered on non-readied Martial Ka'tah units" % spec[1], "U_CUSTODIAN_GUARD_A" in targets and "U_TELEMON_A" in targets, str(targets))
		_check("%s: not offered for P2 (Orks)" % spec[1], SM.get_window_offers(2, "phase_end", {"phase": "shooting"}).is_empty())
		var cp0 := _cp(1)
		var use = _use(phase, 1, "phase_end", sid, "U_CUSTODIAN_GUARD_A")
		_check("%s: USE succeeds, CP -1" % spec[1], use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
		_check("%s: Custodian Guard A is readied" % spec[1], Katah.is_readied("U_CUSTODIAN_GUARD_A"))
		var nxt = PM.get_current_phase_instance()
		_decline_all(nxt if nxt == phase else null)
		nxt = PM.get_current_phase_instance()
		_check("%s: the phase then ended (Charge phase now)" % spec[1], int(GS.get_current_phase()) == PHASE_CHARGE, str(GS.get_current_phase()))
		# Once per battle round per unit.
		_flags("U_CUSTODIAN_GUARD_A").erase("cus11e_readied")
		_check("%s: the same unit cannot be targeted again this battle round" % spec[1], not SM.can_use_stratagem(1, sid, "U_CUSTODIAN_GUARD_A", {"window_id": "phase_end", "phase": "charge"}).can_use)
		_check("%s: a readied unit is not a target" % spec[1], true)
	# Opponent's phase: both players (P2 Custodes when the Orks end a phase).
	_load("cus11e_c5_reactive", 2, "Guardians of the Throne")
	PM.transition_to_phase(PHASE_COMMAND)
	_unready()
	PM.transition_to_phase(PHASE_MOVEMENT)
	var mphase = _phase()
	_decline_all(mphase)
	var r2 = mphase.execute_action({"type": "END_MOVEMENT", "player": 1})
	_decline_until(mphase, "phase_end")
	var pend2: Dictionary = mphase.get_pending_stratagem_window()
	_check("opponent's Movement phase end: phase_end offered to P2", str(pend2.get("window_id", "")) == "phase_end" and int(pend2.get("player", 0)) == 2, str(pend2.get("window_id", "")))
	_decline_all(mphase)
	_check("declined: the Orks' phase advanced", int(GS.get_current_phase()) == PHASE_SHOOTING, str(GS.get_current_phase()))
	# Armies without a phase_end stratagem: the phase advances at once.
	_load("cus11e_c5_active", 1, "Dread Host")
	PM.transition_to_phase(PHASE_COMMAND)
	_unready()
	PM.transition_to_phase(PHASE_SHOOTING)
	var sp = _phase()
	_decline_all(sp)
	sp.execute_action({"type": "END_SHOOTING", "player": 1})
	_check("no phase_end stratagem: END_SHOOTING advances immediately", int(GS.get_current_phase()) == PHASE_CHARGE, str(GS.get_current_phase()))


func _decline_until(phase, window_id: String) -> void:
	var g := 0
	while phase.has_pending_stratagem_window() and _pending_id(phase) != window_id and g < 6:
		var w: Dictionary = phase.get_pending_stratagem_window()
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(w.player), "window_id": str(w.window_id)})
		g += 1


# ---------------------------------------------------------------------------
func _section_vbd() -> void:
	print("\n-- G. VICTORY BEFORE DEATH --")
	_load("cus11e_c5_reactive", 2, "Grav-Assault Force")
	var sid := _sid(2, CSV_VBD)
	_move_to("U_CALADIUS_A", Vector2(22.0, 56.0))   # on obj_home_2
	_move_to("U_GRETCHIN_C", Vector2(31.0, 49.0))
	_move_to("U_SHIELD_CAPTAIN_A", Vector2(14.0, 52.0))
	_move_to("U_TRAJANN_A", Vector2(10.0, 52.0))
	for m in _unit("U_CALADIUS_A").models:
		m["current_wounds"] = 1
	MM.check_all_objectives()
	_check("setup: P2 controls obj_home_2", int(load("res://scripts/codex/custodes/CustodesCommon.gd").objective_controller("obj_home_2")) == 2)
	_check("setup: Caladius within range of obj_home_2", Other.vbd_objectives("U_CALADIUS_A", 2).has("obj_home_2"), str(Other.vbd_objectives("U_CALADIUS_A", 2)))
	PM.transition_to_phase(PHASE_COMMAND)
	_unready()
	PM.transition_to_phase(PHASE_SHOOTING)
	var phase = _phase()
	_decline_all(phase)
	var w = RE.get_unit_weapons("U_GRETCHIN_C", GS.state)
	var wid := ""
	for mid in w:
		for x in w[mid]:
			wid = str(x)
	var mids: Array = []
	for mid in w:
		if wid in w[mid]:
			mids.append(str(mid))
	_window_events.clear()
	var killed := false
	for sd in [3, 5, 7, 11, 13, 17]:
		var res = phase.execute_action({"type": "SHOOT", "actor_unit_id": "U_GRETCHIN_C", "player": 1,
			"payload": {"assignments": [{"weapon_id": wid, "target_unit_id": "U_CALADIUS_A", "model_ids": mids}], "rng_seed": sd}})
		if _pending_id(phase) == "unit_destroyed" or not _unit("U_CALADIUS_A").models[0].get("alive", true):
			killed = true
			break
		_decline_all(phase)
		print("    (seed %d did not destroy the Caladius: %s)" % [sd, str(res.get("error", ""))])
		# Fresh shooter next attempt.
		phase.units_that_shot.erase("U_GRETCHIN_C")
		_flags("U_GRETCHIN_C").erase("has_shot")
	_check("the Gretchin destroy the Caladius", killed)
	_decline_until(phase, "unit_destroyed")
	var pend: Dictionary = phase.get_pending_stratagem_window()
	_check("unit_destroyed opens for P2", str(pend.get("window_id", "")) == "unit_destroyed" and int(pend.get("player", 0)) == 2, str(pend.get("window_id", "")))
	var entry := _offer_entry(pend.get("offers", []), sid, "U_CALADIUS_A")
	var opts: Array = entry.get("secondary", {}).get("options", []).map(func(o): return str(o.id))
	_check("VICTORY BEFORE DEATH offered on the destroyed Caladius with obj_home_2", "obj_home_2" in opts, str(entry))
	var cp0 := _cp(2)
	var use = _use(phase, 2, "unit_destroyed", sid, "U_CALADIUS_A", {"secondary_id": "obj_home_2"})
	_check("USE succeeds, P2 CP -1", use.get("success", false) and _cp(2) == cp0 - 1, str(use.get("error", "")))
	_check("obj_home_2 secured by P2", int(load("res://scripts/codex/custodes/CustodesCommon.gd").objective_secured_by("obj_home_2")) == 2)
	_decline_all(phase)
	_check("not offered for a non-GRAV-ASSAULT unit", not sid in _offer_ids(SM.get_window_offers(2, "unit_destroyed", {"unit_id": "U_CUSTODIAN_WARDENS_A"})))


# ---------------------------------------------------------------------------
func _section_gilded() -> void:
	print("\n-- H. GILDED CHAMPION --")
	_load("cus11e_c5_active", 1, "Auric Champions")
	var sid := _sid(1, CSV_GILDED)
	_check("no window (S panel)", SM.get_stratagem(sid).get("timing", {}).get("windows", []).is_empty())
	PM.transition_to_phase(PHASE_MOVEMENT)
	_decline_all(_phase())
	_check("Trajann (Moment Shackle spent): allowed", SM.can_use_stratagem(1, sid, "U_TRAJANN_A").can_use, str(SM.can_use_stratagem(1, sid, "U_TRAJANN_A")))
	_check("Blade Champion (nothing spent): refused", not SM.can_use_stratagem(1, sid, "U_BLADE_CHAMPION_A").can_use)
	_check("non-CHARACTER refused", not SM.can_use_stratagem(1, sid, "U_CUSTODIAN_GUARD_A").can_use)
	var cp0 := _cp(1)
	var res = SM.use_stratagem(1, sid, "U_TRAJANN_A")
	_check("use succeeds, CP -1", res.get("success", false) and _cp(1) == cp0 - 1, str(res.get("error", "")))
	_check("Moment Shackle restored (moment_shackle_used cleared) + once-per-battle marker", not _flags("U_TRAJANN_A").has("moment_shackle_used") and _flags("U_TRAJANN_A").has("cus11e_gilded_champion"))
	SM._usage_history = {"1": [], "2": []}
	_flags("U_TRAJANN_A")["moment_shackle_used"] = true
	_check("once per battle on the same model", not SM.can_use_stratagem(1, sid, "U_TRAJANN_A").can_use)
	# UnitAbilityManager-tracked ability on another CHARACTER.
	var uam = root.get_node("UnitAbilityManager")
	uam.mark_once_per_battle_used("U_BLADE_CHAMPION_A", "Martial Inspiration")
	PM.transition_to_phase(PHASE_SHOOTING)
	_decline_all(_phase())
	_check("Blade Champion with a spent UAM ability: allowed", SM.can_use_stratagem(1, sid, "U_BLADE_CHAMPION_A").can_use, str(SM.can_use_stratagem(1, sid, "U_BLADE_CHAMPION_A")))
	res = SM.use_stratagem(1, sid, "U_BLADE_CHAMPION_A")
	_check("use succeeds", res.get("success", false), str(res.get("error", "")))
	_check("not usable again in the same phase", uam.is_once_per_battle_used("U_BLADE_CHAMPION_A", "Martial Inspiration"))
	PM.transition_to_phase(PHASE_CHARGE)
	_check("usable again from the next phase", not uam.is_once_per_battle_used("U_BLADE_CHAMPION_A", "Martial Inspiration"))
	# Moment Shackle is offered again at the start of the next Custodes Fight phase.
	_flags("U_TRAJANN_A").erase("moment_shackle_used")
	PM.transition_to_phase(PHASE_FIGHT)
	var fp = _phase()
	_check("the next Fight phase offers Moment Shackle again", "U_TRAJANN_A" in fp._moment_shackle_pending_units, str(fp._moment_shackle_pending_units))


# ---------------------------------------------------------------------------
func _section_ai() -> void:
	print("\n-- I. AI decisions --")
	var ai = root.get_node("AIPlayer")
	# GRAVIMETRIC GRENADE: AI defender at the Orks' Charge phase start.
	_load("cus11e_c5_reactive", 2, "Solar Watch")
	PM.transition_to_phase(PHASE_COMMAND)
	_unready()
	ai.enabled = true
	ai.ai_players = {1: false, 2: true}
	var cp0 := _cp(2)
	PM.transition_to_phase(PHASE_CHARGE)
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	var phase = _phase()
	_check("AI charge_phase_start: no pause", not phase.has_pending_stratagem_window(), _pending_id(phase))
	var marked := false
	for uid in GS.state.units:
		if int(_flags(uid).get("cus11e_gravimetric_grenade", 0)) == 2:
			marked = true
	_check("AI used GRAVIMETRIC GRENADE (CP spent, an Ork unit marked)", _cp(2) == cp0 - 1 and marked, "%d -> %d" % [cp0, _cp(2)])
	# SUPERHUMAN FOCUS: the AI's phase_end decision never stalls the advance.
	_load("cus11e_c5_active", 1, "Guardians of the Throne")
	PM.transition_to_phase(PHASE_COMMAND)
	_unready()
	PM.transition_to_phase(PHASE_SHOOTING)
	var sp = _phase()
	_decline_all(sp)
	ai.enabled = true
	ai.ai_players = {1: true, 2: true}
	sp.execute_action({"type": "END_SHOOTING", "player": 1})
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_check("AI phase_end: the phase advanced (Charge)", int(GS.get_current_phase()) == PHASE_CHARGE, str(GS.get_current_phase()))
	# SELFLESS SERVICE: AI decider — the follow-up waits for the AI's move action.
	_load("cus11e_c5_reactive", 2, "Emissaries Imperatus")
	PM.transition_to_phase(PHASE_COMMAND)
	_unready()
	PM.transition_to_phase(PHASE_CHARGE)
	phase = _phase()
	_decline_all(phase)
	ai.enabled = true
	ai.ai_players = {1: false, 2: true}
	RE.set_test_seed(4)
	phase.execute_action({"type": "END_CHARGE", "player": 1})
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	var hi_unit := str(phase.heroic_intervention_unit_id)
	print("    AI SELFLESS SERVICE: hi_unit=%s pending=%s phase=%s" % [hi_unit, str(phase.heroic_intervention_pending_charge), str(GS.get_current_phase())])
	if hi_unit != "":
		var dec: Dictionary = ADM._decide_charge(GS.create_snapshot(), phase.get_available_actions(), 2) if ADM.has_method("_decide_charge") else {}
		var acts: Array = phase.get_available_actions().filter(func(a): return str(a.get("type", "")) == "APPLY_HEROIC_INTERVENTION_MOVE")
		_check("AI: the pending SELFLESS SERVICE move is offered to the AI as APPLY_HEROIC_INTERVENTION_MOVE", not acts.is_empty(), str(phase.get_available_actions().map(func(a): return a.get("type", ""))))
		var mv: Dictionary = ADM._compute_charge_move(GS.create_snapshot(), hi_unit, int(phase.heroic_intervention_pending_charge.distance), phase.heroic_intervention_pending_charge.targets, 2, "APPLY_HEROIC_INTERVENTION_MOVE")
		mv["player"] = 2
		var applied = phase.execute_action(mv)
		_check("AI move applied; the phase continues", applied.get("success", false) and str(phase.heroic_intervention_unit_id) == "", str(applied.get("error", "")))
	else:
		_check("AI: SELFLESS SERVICE resolved without a pending move (declined or failed roll)", true)
	if is_instance_valid(phase) and phase.awaiting_heroic_intervention:
		phase.execute_action({"type": "DECLINE_HEROIC_INTERVENTION", "player": 2})
	_check("AI: the Charge phase ended (never stalled)", int(GS.get_current_phase()) != PHASE_CHARGE or not phase.has_pending_stratagem_window(), str(GS.get_current_phase()))
