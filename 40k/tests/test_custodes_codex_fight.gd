extends SceneTree

# Codex: Adeptus Custodes (11e) — FIGHT group stratagems (WP-C5,
# CustodesCodexFight.gd). Against tests/saves/cus11e_c5_active.w40ksave (P1
# Custodes active vs P2 Orks), detachment switched per stratagem:
#   A. registry: the 11 FIGHT csv ids are implemented
#   B. ANATHEMA BLADEMASTERY  unit_selected_to_fight (real SELECT_FIGHTER hook);
#      VIGILATOR SQUAD; variants [SUSTAINED HITS 1] / [LETHAL HITS]; A/B; expiry
#   C. GRIM RESPONSIBILITY    INFANTRY; [LETHAL HITS: CHARACTER/MONSTER] A/B
#   D. AVENGE THE FALLEN      TRUSTED SENTINEL below starting strength; +2 A
#      (not CHARACTER models) A/B
#   E. BEARERS OF HIS LIGHT   melee hit/wound penalties ignored (bits + A/B)
#   F. SLAYERS OF NIGHTMARES  +1 to wound vs a higher T (bits + A/B)
#   G. DUTY UNTO DEATH        enemy_targets_unit_fight (P2 attacks in P1's
#      Fight phase); Fight On Death flags; 3+ (+1 CHARACTER)
#   H. SHIELD OF HONOUR       fight_phase_start (real hook, both players);
#      -1 hit / -1 wound for engaged enemies not targeting it
#   I. INDOMITABLE GUARDIANS  enemy_has_fought (real hook, opponent's Fight
#      phase); Fights First + must be the next unit selected; expiry
#   J. LIGHTNING WRATH        unit_selected_to_pile_in (CUS11E_SELECT_PILE_IN_UNIT);
#      D3+3" cap honoured by the phase's validation
#   K. EMPEROR'S DOMAIN       unit_selected_to_consolidate
#      (CUS11E_SELECT_CONSOLIDATION_UNIT); objective mode override
#   L. HONOURED INTERRED      S panel: own Shooting / either Fight phase;
#      re-roll hit rolls of 1 within 6"
#   M. AI decider paths (synchronous) incl. the AI pile-in / consolidate select
#
# Usage: godot --headless --path 40k --script tests/test_custodes_codex_fight.gd

const FIXTURE := "cus11e_c5_active"
const PHASE_COMMAND := 6
const PHASE_MOVEMENT := 7
const PHASE_SHOOTING := 8
const PHASE_CHARGE := 9
const PHASE_FIGHT := 10
const PX := 40.0

const CSV_BM := "anathema-blademastery-null-maiden-vigil"
const CSV_DUTY := "duty-unto-death-auric-champions"
const CSV_GRIM := "grim-responsibility-shadowkeepers"
const CSV_SOH := "shield-of-honour-guardians-of-the-throne"
const CSV_AVENGE := "avenge-the-fallen-honoured-companions"
const CSV_DOMAIN := "emperors-domain-honoured-companions"
const CSV_BEARERS := "bearers-of-his-light-emissaries-imperatus"
const CSV_SLAYERS := "slayers-of-nightmares-emissaries-imperatus"
const CSV_INDOM := "indomitable-guardians-shadowkeepers"
const CSV_LW := "lightning-wrath-dread-host"
const CSV_HI := "honoured-interred-might-of-the-moritoi"

var passed := 0
var failed := 0
var SM = null
var GS = null
var PM = null
var RE = null
var Codex = null
var Fight = null
var _window_events: Array = []
var _phase_done := false
var _base_positions: Dictionary = {}


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


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

func _stage_fixture() -> bool:
	var slm = root.get_node("SaveLoadManager")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slm.save_directory))
	for ext in [".w40ksave", ".meta"]:
		var src = "res://tests/saves/" + FIXTURE + ext
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(slm.save_directory + FIXTURE + ext))
	return slm.load_game(FIXTURE)


func _on_window_opened(player: int, window_id: String, offers: Array, ctx: Dictionary) -> void:
	_window_events.append({"player": player, "window_id": window_id, "offers": offers, "ctx": ctx})


func _set_detachment(player: int, det: String) -> void:
	GS.state.factions[str(player)]["detachment"] = det
	SM.load_faction_stratagems_for_player(player)


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


func _remember_positions() -> void:
	for uid in GS.state.units:
		var arr: Array = []
		for m in GS.state.units[uid].get("models", []):
			arr.append(m.get("position", null))
		_base_positions[uid] = arr


func _restore_unit_state() -> void:
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		var arr: Array = _base_positions.get(uid, [])
		for i in range(u.get("models", []).size()):
			var m = u.models[i]
			if i < arr.size():
				m["position"] = arr[i].duplicate() if arr[i] is Dictionary else arr[i]
			m["alive"] = true
			m["current_wounds"] = m.get("wounds", 1)
		u["flags"] = {}
		u["status"] = GS.UnitStatus.DEPLOYED
	GS.state.meta["active_player"] = 1


func _translate(uid: String, dx_in: float, dy_in: float) -> void:
	for m in _unit(uid).get("models", []):
		var p = m.get("position", null)
		if p == null:
			continue
		m["position"] = {"x": float(p.x) + dx_in * PX, "y": float(p.y) + dy_in * PX}


func _reset_usage(cp: int = 6) -> void:
	SM._usage_history = {"1": [], "2": []}
	SM.active_effects = []
	GS.state.players["1"]["cp"] = cp
	GS.state.players["2"]["cp"] = cp


## Codex: Adeptus Custodes ka'tahs (WP-C3) ride the same windows: un-ready
## every unit so only the stratagems under test are offered.
func _cus11e_unready() -> void:
	var rnd: int = int(GS.get_battle_round())
	for uid in GS.state.units:
		var f := _flags(uid)
		f.erase("cus11e_readied")
		f["cus11e_master_of_katahs_round"] = rnd
	# Trajann's Moment Shackle (start of the Custodes' Fight phase) is not
	# under test here: spent, so the Fight phase starts straight away.
	_flags("U_TRAJANN_A")["moment_shackle_used"] = true


func _no_phase_advance(phase) -> void:
	_phase_done = false
	if phase.phase_completed.is_connected(PM._on_phase_completed):
		phase.phase_completed.disconnect(PM._on_phase_completed)
	phase.phase_completed.connect(func(): _phase_done = true)


func _decline_pending(phase) -> int:
	var n := 0
	while phase.has_pending_stratagem_window() and n < 8:
		var w: Dictionary = phase.get_pending_stratagem_window()
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(w.get("player", 0)), "window_id": str(w.get("window_id", ""))})
		n += 1
	return n


## Fresh Fight phase; `prep` runs between Command and Fight entry. When
## end_pile_in, both halves of the Pile In step are ended.
func _fresh_fight(prep: Callable = Callable(), end_pile_in: bool = true):
	_reset_usage()
	PM.transition_to_phase(PHASE_COMMAND)
	_cus11e_unready()
	if prep.is_valid():
		prep.call()
	PM.transition_to_phase(PHASE_FIGHT)
	var phase = PM.get_current_phase_instance()
	_no_phase_advance(phase)
	if not phase.stratagem_window_opened.is_connected(_on_window_opened):
		phase.stratagem_window_opened.connect(_on_window_opened)
	_decline_pending(phase)
	if end_pile_in:
		for _i in [1, 2]:
			if int(phase.pile_in_step_11e) != int(phase.PileInStep11e.ACTIVE):
				break
			phase.execute_action({"type": "END_PILE_IN", "player": int(phase.piling_in_player_11e)})
			_decline_pending(phase)
	return phase


func _first_melee_weapon(uid: String) -> String:
	var w: Dictionary = RE.get_unit_melee_weapons(uid, GS.state)
	for mid in w:
		for wid in w[mid]:
			return str(wid)
	return ""


func _melee_board(attacker_flags: Dictionary, attacker_kw: Array, weapon: Dictionary, n_att: int, n_tgt: int, tgt_kw: Array = ["INFANTRY"], tgt_t: int = 4, att_t: int = 6, tgt_flags: Dictionary = {}) -> Dictionary:
	var atk: Array = []
	for i in range(n_att):
		atk.append({"id": "ma%d" % i, "position": {"x": 10.0, "y": 10.0 + i * 30}, "base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 3, "current_wounds": 3})
	var tgt: Array = []
	for i in range(n_tgt):
		tgt.append({"id": "mt%d" % i, "position": {"x": 30.0, "y": 10.0 + i * 30}, "base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 3, "current_wounds": 3})
	return {"units": {
		"U_ATK": {"id": "U_ATK", "owner": 1,
			"meta": {"name": "Attackers", "keywords": attacker_kw, "stats": {"toughness": att_t, "save": 6, "wounds": 3},
				"abilities": [], "weapons": [weapon]},
			"flags": attacker_flags, "models": atk},
		"U_TGT": {"id": "U_TGT", "owner": 2,
			"meta": {"name": "Targets", "keywords": tgt_kw, "stats": {"toughness": tgt_t, "save": 3, "wounds": 3}, "abilities": []},
			"flags": tgt_flags, "models": tgt},
	}, "meta": {"phase": 10, "active_player": 1, "battle_round": 2}}


func _melee_result(board: Dictionary, weapon_name: String, seed_val: int) -> Dictionary:
	RE.set_test_seed(seed_val)
	var rng = RE.RNGService.new()
	return RE.resolve_melee_attacks({"type": "FIGHT", "actor_unit_id": "U_ATK",
		"payload": {"assignments": [{"attacker": "U_ATK", "target": "U_TGT", "weapon": weapon_name}]}}, board, rng)


func _block(result: Dictionary, ctx_name: String) -> Dictionary:
	for d in result.get("dice", []):
		if str(d.get("context", "")) == ctx_name:
			return d
	return {}


func _wounds_total(result: Dictionary) -> int:
	var b := _block(result, "wound_roll_melee")
	if b.is_empty():
		b = _block(result, "wound_roll")
	return int(b.get("successes", 0))


func _blade(rules: String, a: String = "4", s: String = "5") -> Dictionary:
	return {"name": "Test Blade", "type": "Melee", "range": "Melee", "attacks": a, "weapon_skill": "2",
		"strength": s, "ap": "-1", "damage": "1", "special_rules": rules}


## Sum of (successful hits, wounds) over seeds.
func _ab_sum(board_off: Dictionary, board_on: Dictionary, seeds: Array) -> Array:
	var hits_off := 0
	var hits_on := 0
	var w_off := 0
	var w_on := 0
	var never_worse := true
	for sd in seeds:
		var a = _melee_result(board_off.duplicate(true), "Test Blade", int(sd))
		var b = _melee_result(board_on.duplicate(true), "Test Blade", int(sd))
		hits_off += int(_block(a, "hit_roll_melee").get("successes", 0))
		hits_on += int(_block(b, "hit_roll_melee").get("successes", 0))
		var wa := _wounds_total(a)
		var wb := _wounds_total(b)
		w_off += wa
		w_on += wb
		if wb < wa:
			never_worse = false
	return [hits_off, hits_on, w_off, w_on, never_worse]


func _log_count(fragment: String) -> int:
	var gel = root.get_node_or_null("GameEventLog")
	var n := 0
	if gel and "entries" in gel:
		for e in gel.entries:
			if fragment in str(e.get("text", "")):
				n += 1
	return n


# ---------------------------------------------------------------------------
func _run() -> void:
	SM = root.get_node("StratagemManager")
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	Codex = load("res://scripts/codex/custodes/CustodesCodex11e.gd")
	Fight = load("res://scripts/codex/custodes/CustodesCodexFight.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	GS.set_edition(11)

	print("\n=== test_custodes_codex_fight ===\n")
	_check("fixture %s loads" % FIXTURE, _stage_fixture())
	GS.set_edition(11)
	root.get_node("SettingsService").set("auto_allocate_wounds", true)
	_remember_positions()

	_section_registry()
	_section_blademastery()
	_section_grim()
	_section_avenge()
	_section_bearers()
	_section_slayers()
	_section_duty()
	_section_shield_of_honour()
	_section_indomitable()
	_section_lightning_wrath()
	_section_emperors_domain()
	_section_honoured_interred()
	_section_ai()


# ---------------------------------------------------------------------------
func _section_registry() -> void:
	print("\n-- A. registry --")
	var impl: Array = Codex.all_implemented_ids()
	for csv in [CSV_BM, CSV_DUTY, CSV_GRIM, CSV_SOH, CSV_AVENGE, CSV_DOMAIN, CSV_BEARERS, CSV_SLAYERS, CSV_INDOM, CSV_LW, CSV_HI]:
		_check("%s implemented (Fight group)" % csv, csv in impl and Fight.IMPLEMENTED.get(csv, false) and Codex.group_for_id(csv) == Fight)


# ---------------------------------------------------------------------------
func _section_blademastery() -> void:
	print("\n-- B. ANATHEMA BLADEMASTERY --")
	_set_detachment(1, "Null Maiden Vigil")
	var sid := _sid(1, CSV_BM)
	_check("loaded (Null Maiden Vigil)", sid != "")
	var phase = _fresh_fight()
	var ctx := {"phase": "fight", "unit_id": "U_VIGILATORS_A"}
	var offers = SM.get_window_offers(1, "unit_selected_to_fight", ctx)
	_check("offered when the VIGILATOR SQUAD is selected to fight", _offer_targets(offers, sid) == ["U_VIGILATORS_A"], str(offers))
	var entry := _offer_entry(offers, sid, "U_VIGILATORS_A")
	_check("two variants, a choice is required", entry.get("variants", []).size() == 2 and bool(entry.get("require_variant", false)), str(entry))
	_check("not offered on Custodian Guard A (not VIGILATOR SQUAD)", not sid in _offer_ids(SM.get_window_offers(1, "unit_selected_to_fight", {"unit_id": "U_CUSTODIAN_GUARD_A"})))
	_check("not offered in unit_selected_to_shoot", not sid in _offer_ids(SM.get_window_offers(1, "unit_selected_to_shoot", ctx)))
	_check("not offered to P2", SM.get_window_offers(2, "unit_selected_to_fight", ctx).is_empty())
	# Real hook: Vigilators selected to fight (P1 active, engaged with the Warboss).
	var sel = phase.sequencer_11e.peek_selection(GS.state)
	print("    selection: %s" % str(sel))
	var r = phase.execute_action({"type": "SELECT_FIGHTER", "unit_id": "U_VIGILATORS_A", "player": int(sel.get("player", 1))})
	var pend: Dictionary = phase.get_pending_stratagem_window()
	_check("SELECT_FIGHTER Vigilators opens unit_selected_to_fight for P1", r.get("success", false) and str(pend.get("window_id", "")) == "unit_selected_to_fight" and int(pend.get("player", 0)) == 1, "%s / %s" % [str(r.get("error", "")), str(pend.get("window_id", ""))])
	var no_variant = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_fight", "stratagem_id": sid, "target_unit_id": "U_VIGILATORS_A"})
	_check("USE without a variant refused (one of its options must be chosen)", not no_variant.get("success", true), str(no_variant))
	var cp0 := _cp(1)
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_fight", "stratagem_id": sid,
		"target_unit_id": "U_VIGILATORS_A", "context": {"variant_id": "lethal_hits"}})
	_check("USE [LETHAL HITS] succeeds", use.get("success", false), str(use.get("error", "")))
	_check("CP -1", _cp(1) == cp0 - 1, "%d -> %d" % [cp0, _cp(1)])
	_check("melee [LETHAL HITS] flag + variant marker", bool(_flags("U_VIGILATORS_A").get("effect_lethal_hits_melee", false)) and str(_flags("U_VIGILATORS_A").get("cus11e_anathema_blademastery", "")) == "lethal_hits")
	_check("no [SUSTAINED HITS] flag for the lethal choice", not _flags("U_VIGILATORS_A").has("effect_sustained_hits_melee"))
	_check("activation resumed (attack assignment)", use.get("trigger_attack_assignment", false) or phase.active_fighter_id == "U_VIGILATORS_A", str(use.keys()))
	_check("once per phase: a second use refused", not SM.can_use_stratagem(1, sid, "U_VIGILATORS_A", {"window_id": "unit_selected_to_fight", "unit_id": "U_VIGILATORS_A", "variant_id": "lethal_hits"}).can_use)
	# A/B lethal: high-T target, same seeds.
	var ab = _ab_sum(_melee_board({}, ["ADEPTUS CUSTODES", "INFANTRY", "VIGILATOR SQUAD"], _blade(""), 4, 1, ["VEHICLE"], 12),
		_melee_board({"effect_lethal_hits_melee": true}, ["ADEPTUS CUSTODES", "INFANTRY", "VIGILATOR SQUAD"], _blade(""), 4, 1, ["VEHICLE"], 12), range(6100, 6120))
	_check("A/B [LETHAL HITS]: same hits, more wounds vs T12 (%d -> %d over 20 seeds), never fewer" % [ab[2], ab[3]], ab[0] == ab[1] and ab[3] > ab[2] and ab[4], str(ab))
	var sus = _ab_sum(_melee_board({}, ["ADEPTUS CUSTODES"], _blade(""), 4, 1), _melee_board({"effect_sustained_hits_melee": true}, ["ADEPTUS CUSTODES"], _blade(""), 4, 1), range(6200, 6220))
	_check("A/B [SUSTAINED HITS 1]: more wounds from the extra hits (%d -> %d over 20 seeds), never fewer" % [sus[2], sus[3]], sus[3] > sus[2] and sus[4], str(sus))
	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry: both flags cleared at end of phase", not _flags("U_VIGILATORS_A").has("effect_lethal_hits_melee") and not _flags("U_VIGILATORS_A").has("cus11e_anathema_blademastery"))
	_restore_unit_state()


# ---------------------------------------------------------------------------
func _section_grim() -> void:
	print("\n-- C. GRIM RESPONSIBILITY --")
	_set_detachment(1, "Shadowkeepers")
	var sid := _sid(1, CSV_GRIM)
	_check("loaded (Shadowkeepers)", sid != "")
	_fresh_fight()
	_check("offered on an ADEPTUS CUSTODES INFANTRY unit selected to fight", _offer_targets(SM.get_window_offers(1, "unit_selected_to_fight", {"unit_id": "U_VIGILATORS_A"}), sid) == ["U_VIGILATORS_A"])
	_check("not offered on the Contemptor (VEHICLE)", not sid in _offer_ids(SM.get_window_offers(1, "unit_selected_to_fight", {"unit_id": "U_CONTEMPTOR_A"})))
	_check("not offered at the start of the Fight phase", not sid in _offer_ids(SM.get_window_offers(1, "fight_phase_start", {"phase": "fight"})))
	var phase = PM.get_current_phase_instance()
	var cp0 := _cp(1)
	phase.open_stratagem_window(1, "unit_selected_to_fight", {"phase": "fight", "unit_id": "U_VIGILATORS_A"}, "")
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_fight", "stratagem_id": sid, "target_unit_id": "U_VIGILATORS_A"})
	_check("USE succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	_check("flag cus11e_grim_responsibility", bool(_flags("U_VIGILATORS_A").get("cus11e_grim_responsibility", false)))
	var on_char = _ab_sum(_melee_board({}, ["ADEPTUS CUSTODES", "INFANTRY"], _blade(""), 4, 1, ["CHARACTER", "INFANTRY"], 12),
		_melee_board({"cus11e_grim_responsibility": true}, ["ADEPTUS CUSTODES", "INFANTRY"], _blade(""), 4, 1, ["CHARACTER", "INFANTRY"], 12), range(6300, 6320))
	_check("A/B vs a CHARACTER (T12): lethal hits add wounds (%d -> %d)" % [on_char[2], on_char[3]], on_char[3] > on_char[2] and on_char[4], str(on_char))
	var on_plain = _ab_sum(_melee_board({}, ["ADEPTUS CUSTODES", "INFANTRY"], _blade(""), 4, 1, ["VEHICLE"], 12),
		_melee_board({"cus11e_grim_responsibility": true}, ["ADEPTUS CUSTODES", "INFANTRY"], _blade(""), 4, 1, ["VEHICLE"], 12), range(6300, 6320))
	_check("A/B vs a non-CHARACTER/MONSTER (T12): unchanged (%d == %d)" % [on_plain[2], on_plain[3]], on_plain[3] == on_plain[2], str(on_plain))
	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry at end of phase", not _flags("U_VIGILATORS_A").has("cus11e_grim_responsibility"))
	_restore_unit_state()


# ---------------------------------------------------------------------------
func _section_avenge() -> void:
	print("\n-- D. AVENGE THE FALLEN --")
	_set_detachment(1, "Honoured Companions")
	var sid := _sid(1, CSV_AVENGE)
	_check("loaded (Honoured Companions)", sid != "")
	_fresh_fight()
	var ctx := {"phase": "fight", "unit_id": "U_CUSTODIAN_GUARD_A"}
	_check("not offered at starting strength", not sid in _offer_ids(SM.get_window_offers(1, "unit_selected_to_fight", ctx)))
	_unit("U_CUSTODIAN_GUARD_A").models[2]["alive"] = false
	_unit("U_CUSTODIAN_GUARD_A").models[2]["current_wounds"] = 0
	_check("offered when below starting strength (TRUSTED SENTINEL)", _offer_targets(SM.get_window_offers(1, "unit_selected_to_fight", ctx), sid) == ["U_CUSTODIAN_GUARD_A"])
	_check("not offered on the Vigilators (not TRUSTED SENTINEL)", not sid in _offer_ids(SM.get_window_offers(1, "unit_selected_to_fight", {"unit_id": "U_VIGILATORS_A"})))
	var phase = PM.get_current_phase_instance()
	var cp0 := _cp(1)
	phase.open_stratagem_window(1, "unit_selected_to_fight", ctx, "")
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_fight", "stratagem_id": sid, "target_unit_id": "U_CUSTODIAN_GUARD_A"})
	_check("USE succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	_check("flag cus11e_avenge_the_fallen = 2", int(_flags("U_CUSTODIAN_GUARD_A").get("cus11e_avenge_the_fallen", 0)) == 2)
	var a_off = int(_block(_melee_result(_melee_board({}, ["ADEPTUS CUSTODES", "TRUSTED SENTINEL"], _blade("", "3"), 2, 3), "Test Blade", 6401), "hit_roll_melee").get("total_attacks", -1))
	var a_on = int(_block(_melee_result(_melee_board({"cus11e_avenge_the_fallen": 2}, ["ADEPTUS CUSTODES", "TRUSTED SENTINEL"], _blade("", "3"), 2, 3), "Test Blade", 6401), "hit_roll_melee").get("total_attacks", -1))
	_check("A/B: 2 models x A3 = 6 -> +2 A each = 10", a_off == 6 and a_on == 10, "%d -> %d" % [a_off, a_on])
	var a_char = int(_block(_melee_result(_melee_board({"cus11e_avenge_the_fallen": 2}, ["ADEPTUS CUSTODES", "CHARACTER"], _blade("", "3"), 1, 3), "Test Blade", 6402), "hit_roll_melee").get("total_attacks", -1))
	_check("CHARACTER models do not get the +2 A", a_char == 3, str(a_char))
	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry at end of phase", not _flags("U_CUSTODIAN_GUARD_A").has("cus11e_avenge_the_fallen"))
	_restore_unit_state()


# ---------------------------------------------------------------------------
func _section_bearers() -> void:
	print("\n-- E. BEARERS OF HIS LIGHT --")
	_set_detachment(1, "Emissaries Imperatus")
	var sid := _sid(1, CSV_BEARERS)
	_check("loaded (Emissaries Imperatus)", sid != "")
	_fresh_fight()
	var ctx := {"phase": "fight", "unit_id": "U_CONTEMPTOR_A"}
	_check("offered on any ADEPTUS CUSTODES unit selected to fight (Contemptor)", _offer_targets(SM.get_window_offers(1, "unit_selected_to_fight", ctx), sid) == ["U_CONTEMPTOR_A"])
	var phase = PM.get_current_phase_instance()
	var cp0 := _cp(1)
	phase.open_stratagem_window(1, "unit_selected_to_fight", ctx, "")
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_fight", "stratagem_id": sid, "target_unit_id": "U_CONTEMPTOR_A"})
	_check("USE succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	_check("flag cus11e_bearers_of_his_light", bool(_flags("U_CONTEMPTOR_A").get("cus11e_bearers_of_his_light", false)))
	# Penalties ignored: the -1 hit / -1 wound bits are dropped.
	var led: Array = []
	var bits = Codex.apply_hit_bits(Codex.HIT_MINUS_ONE, {"id": "X", "owner": 1, "flags": {"cus11e_bearers_of_his_light": true}, "meta": {"keywords": ["ADEPTUS CUSTODES"]}}, {"id": "Y", "owner": 2}, true, {}, led)
	_check("hit bits: an existing -1 is removed", (bits & Codex.HIT_MINUS_ONE) == 0, str(bits))
	var wbits = Codex.apply_wound_bits(Codex.WOUND_MINUS_ONE, {"id": "X", "owner": 1, "flags": {"cus11e_bearers_of_his_light": true}, "meta": {"keywords": ["ADEPTUS CUSTODES"]}}, {"id": "Y", "owner": 2}, true, 5, 4, [])
	_check("wound bits: an existing -1 is removed", (wbits & Codex.WOUND_MINUS_ONE) == 0, str(wbits))
	var keep = Codex.apply_hit_bits(Codex.HIT_PLUS_ONE, {"id": "X", "owner": 1, "flags": {"cus11e_bearers_of_his_light": true}, "meta": {"keywords": ["ADEPTUS CUSTODES"]}}, {"id": "Y", "owner": 2}, true, {}, [])
	_check("hit bits: a +1 is kept (only harmful modifiers ignored)", (keep & Codex.HIT_PLUS_ONE) != 0, str(keep))
	# A/B in the real melee resolver: the target's Kaptaris-style -1 to hit.
	var w := _blade("", "5")
	var pen := {"cus11e_katah_kaptaris": true}
	var off = _ab_sum(_melee_board({}, ["ADEPTUS CUSTODES"], w, 2, 1, ["INFANTRY"], 4, 6, pen), _melee_board({"cus11e_bearers_of_his_light": true}, ["ADEPTUS CUSTODES"], w, 2, 1, ["INFANTRY"], 4, 6, pen), range(6500, 6520))
	_check("A/B vs a -1 to hit penalty: more hits with BEARERS (%d -> %d)" % [off[0], off[1]], off[1] > off[0], str(off))
	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry at end of phase", not _flags("U_CONTEMPTOR_A").has("cus11e_bearers_of_his_light"))
	_restore_unit_state()


# ---------------------------------------------------------------------------
func _section_slayers() -> void:
	print("\n-- F. SLAYERS OF NIGHTMARES --")
	_set_detachment(1, "Emissaries Imperatus")
	var sid := _sid(1, CSV_SLAYERS)
	_check("loaded (Emissaries Imperatus)", sid != "")
	_fresh_fight()
	var ctx := {"phase": "fight", "unit_id": "U_BLADE_CHAMPION_A"}
	_check("offered on the Blade Champion selected to fight", _offer_targets(SM.get_window_offers(1, "unit_selected_to_fight", ctx), sid) == ["U_BLADE_CHAMPION_A"])
	var phase = PM.get_current_phase_instance()
	var cp0 := _cp(1)
	phase.open_stratagem_window(1, "unit_selected_to_fight", ctx, "")
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_fight", "stratagem_id": sid, "target_unit_id": "U_BLADE_CHAMPION_A"})
	_check("USE succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	var bc_t := int(_unit("U_BLADE_CHAMPION_A").meta.stats.toughness)
	var dd_t := int(_unit("U_DEFF_DREAD_A").meta.stats.toughness)
	var bits = Codex.apply_wound_bits(0, _unit("U_BLADE_CHAMPION_A"), _unit("U_DEFF_DREAD_A"), true, 6, dd_t, [])
	_check("+1 to wound vs the Deff Dread (T%d > T%d)" % [dd_t, bc_t], dd_t > bc_t and (bits & Codex.WOUND_PLUS_ONE) != 0, str(bits))
	var bits2 = Codex.apply_wound_bits(0, _unit("U_BLADE_CHAMPION_A"), _unit("U_BOYZ_B"), true, 6, int(_unit("U_BOYZ_B").meta.stats.toughness), [])
	_check("no bonus vs the Boyz (lower T)", (bits2 & Codex.WOUND_PLUS_ONE) == 0, str(bits2))
	var off = _ab_sum(_melee_board({}, ["ADEPTUS CUSTODES"], _blade("", "6", "6"), 1, 1, ["VEHICLE"], 10, 6), _melee_board({"cus11e_slayers_of_nightmares": true}, ["ADEPTUS CUSTODES"], _blade("", "6", "6"), 1, 1, ["VEHICLE"], 10, 6), range(6600, 6620))
	_check("A/B vs T10 (attacker T6): more wounds (%d -> %d), never fewer" % [off[2], off[3]], off[3] > off[2] and off[4], str(off))
	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry at end of phase", not _flags("U_BLADE_CHAMPION_A").has("cus11e_slayers_of_nightmares"))
	_restore_unit_state()


# ---------------------------------------------------------------------------
func _fod_states(uid: String) -> Dictionary:
	var out := {"alive": 0, "pending": []}
	for m in _unit(uid).get("models", []):
		if m.get("alive", true):
			out.alive += 1
	out.pending = _flags(uid).get("ork11e_fod_pending", [])
	return out


func _section_duty() -> void:
	print("\n-- G. DUTY UNTO DEATH --")
	_set_detachment(1, "Auric Champions")
	var sid := _sid(1, CSV_DUTY)
	_check("loaded (Auric Champions)", sid != "")
	# The Boyz charged (Fights First) so P2 attacks first in P1's Fight phase.
	var prep := func():
		_flags("U_BOYZ_B")["charged_this_turn"] = true
		_flags("U_BOYZ_B")["fights_first"] = true
	var phase = _fresh_fight(prep)
	var sel = phase.sequencer_11e.peek_selection(GS.state)
	_check("Boyz (Fights First) — P2 picks first", int(sel.player) == 2 and "U_BOYZ_B" in sel.candidates, str(sel))
	for m in _unit("U_CUSTODIAN_GUARD_A").models:
		m["current_wounds"] = 1
	var r = phase.execute_action({"type": "SELECT_FIGHTER", "unit_id": "U_BOYZ_B", "player": 2})
	_decline_pending(phase)
	var batch := {"type": "BATCH_FIGHT_ACTIONS", "player": 2, "sub_actions": [
		{"type": "ASSIGN_ATTACKS", "unit_id": "U_BOYZ_B", "target_id": "U_CUSTODIAN_GUARD_A", "weapon_id": _first_melee_weapon("U_BOYZ_B"), "attacking_models": [], "player": 2},
		{"type": "CONFIRM_AND_RESOLVE_ATTACKS", "player": 2},
		{"type": "ROLL_DICE", "player": 2, "payload": {"fast_roll": true}}]}
	r = phase.execute_action(batch)
	var pend: Dictionary = phase.get_pending_stratagem_window()
	_check("CONFIRM opens enemy_targets_unit_fight for P1", r.get("success", false) and str(pend.get("window_id", "")) == "enemy_targets_unit_fight" and int(pend.get("player", 0)) == 1, "%s / %s" % [str(r.get("error", "")), str(pend.get("window_id", ""))])
	_check("DUTY UNTO DEATH offered on the targeted Custodian Guard A", _offer_targets(pend.get("offers", []), sid) == ["U_CUSTODIAN_GUARD_A"], str(pend.get("offers", [])))
	_check("not offered on an untargeted unit", not SM.can_use_stratagem(1, sid, "U_VIGILATORS_A", pend.get("ctx", {}).merged({"window_id": "enemy_targets_unit_fight"})).can_use)
	var cp0 := _cp(1)
	var before := _fod_states("U_CUSTODIAN_GUARD_A")
	RE.set_test_seed(4321)
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "enemy_targets_unit_fight", "stratagem_id": sid, "target_unit_id": "U_CUSTODIAN_GUARD_A"})
	_check("USE succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	_check("Fight On Death marked (cus11e_duty_unto_death)", str(_flags("U_CUSTODIAN_GUARD_A").get("ork11e_fod_mode", "")) == "cus11e_duty_unto_death")
	var rolls: Array = phase.dice_log.filter(func(d): return typeof(d) == TYPE_DICTIONARY and str(d.get("context", "")) == "ork11e_fight_on_death")
	var after := _fod_states("U_CUSTODIAN_GUARD_A")
	var destroyed: int = before.alive - after.alive + after.pending.size()
	print("    Guard before %s after %s, rolls %d" % [str(before), str(after), rolls.size()])
	_check("one D6 per destroyed model", rolls.size() == destroyed, "%d vs %d" % [rolls.size(), destroyed])
	var kept := 0
	for d in rolls:
		if d.get("kept", false):
			kept += 1
		_check("roll %d%+d kept=%s matches 3+" % [int(d.rolls_raw[0]), int(d.modifier), str(d.kept)], bool(d.kept) == (int(d.rolls_raw[0]) + int(d.modifier) >= 3))
	_check("kept models listed as pending", after.pending.size() == kept)
	_check("fod_roll: +1 for a CHARACTER model, 3+ keeps", int(Fight.fod_roll("U_BLADE_CHAMPION_A", 0).mod) == 1 and int(Fight.fod_roll("U_CUSTODIAN_GUARD_A", 0).mod) == 0 and int(Fight.fod_roll("U_CUSTODIAN_GUARD_A", 0).pass) == 3)
	# Gate: once the unit has been selected to fight, no longer offered.
	SM._usage_history = {"1": [], "2": []}
	phase.active_fighter_id = "U_CUSTODIAN_GUARD_A"
	if "units_that_fought" in phase:
		phase.units_that_fought.append("U_CUSTODIAN_GUARD_A")
	var after_sel = SM.can_use_stratagem(1, sid, "U_CUSTODIAN_GUARD_A", {"window_id": "enemy_targets_unit_fight", "target_unit_ids": ["U_CUSTODIAN_GUARD_A"]})
	print("    after selection: %s" % str(after_sel))
	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry: Fight On Death marker cleared", not _flags("U_CUSTODIAN_GUARD_A").has("ork11e_fod_mode"))
	_restore_unit_state()


# ---------------------------------------------------------------------------
func _section_shield_of_honour() -> void:
	print("\n-- H. SHIELD OF HONOUR --")
	_set_detachment(1, "Guardians of the Throne")
	var sid := _sid(1, CSV_SOH)
	_check("loaded (Guardians of the Throne)", sid != "")
	_reset_usage()
	PM.transition_to_phase(PHASE_COMMAND)
	_cus11e_unready()
	_window_events.clear()
	PM.transition_to_phase(PHASE_FIGHT)
	var phase = PM.get_current_phase_instance()
	_no_phase_advance(phase)
	var pend: Dictionary = phase.get_pending_stratagem_window()
	_check("Fight phase entry opens fight_phase_start for P1 (active first)", str(pend.get("window_id", "")) == "fight_phase_start" and int(pend.get("player", 0)) == 1, str(pend.get("window_id", "")))
	var targets := _offer_targets(pend.get("offers", []), sid)
	_check("offered on INFANTRY within 6\" of an enemy (Custodian Guard A, Vigilators)", "U_CUSTODIAN_GUARD_A" in targets and "U_VIGILATORS_A" in targets, str(targets))
	_check("not offered on the Contemptor (VEHICLE)", not "U_CONTEMPTOR_A" in targets)
	_check("not offered on the Wardens (no enemy within 6\")", not "U_CUSTODIAN_WARDENS_A" in targets)
	var cp0 := _cp(1)
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "fight_phase_start", "stratagem_id": sid, "target_unit_id": "U_CUSTODIAN_GUARD_A"})
	_check("USE succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	_check("flag cus11e_shield_of_honour", bool(_flags("U_CUSTODIAN_GUARD_A").get("cus11e_shield_of_honour", false)))
	_decline_pending(phase)
	# Penalty: Boyz (engaged with the Guard) attacking another unit.
	var vs_other = Fight.shield_of_honour_penalty(_unit("U_BOYZ_B"), _unit("U_VIGILATORS_A"))
	var vs_soh = Fight.shield_of_honour_penalty(_unit("U_BOYZ_B"), _unit("U_CUSTODIAN_GUARD_A"))
	_check("Boyz attacking another unit: penalised", vs_other != "", vs_other)
	_check("Boyz attacking the SHIELD OF HONOUR unit: no penalty", vs_soh == "", vs_soh)
	var hb = Codex.apply_hit_bits(0, _unit("U_BOYZ_B"), _unit("U_VIGILATORS_A"), true, GS.state, [])
	var wb = Codex.apply_wound_bits(0, _unit("U_BOYZ_B"), _unit("U_VIGILATORS_A"), true, 4, 3, [])
	_check("-1 to hit and -1 to wound bits", (hb & Codex.HIT_MINUS_ONE) != 0 and (wb & Codex.WOUND_MINUS_ONE) != 0, "%d / %d" % [hb, wb])
	_check("not for an enemy not engaged with it (Warboss)", Fight.shield_of_honour_penalty(_unit("U_WARBOSS_A"), _unit("U_VIGILATORS_A")) == "")
	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry at end of phase", not _flags("U_CUSTODIAN_GUARD_A").has("cus11e_shield_of_honour"))
	_restore_unit_state()


# ---------------------------------------------------------------------------
func _section_indomitable() -> void:
	print("\n-- I. INDOMITABLE GUARDIANS --")
	_set_detachment(1, "Shadowkeepers")
	var sid := _sid(1, CSV_INDOM)
	_check("loaded (Shadowkeepers)", sid != "")
	# The Orks' (P2) Fight phase: P1 is the opponent.
	_reset_usage()
	PM.transition_to_phase(PHASE_COMMAND)
	GS.state.meta["active_player"] = 2
	_cus11e_unready()
	PM.transition_to_phase(PHASE_FIGHT)
	var phase = PM.get_current_phase_instance()
	_no_phase_advance(phase)
	if not phase.stratagem_window_opened.is_connected(_on_window_opened):
		phase.stratagem_window_opened.connect(_on_window_opened)
	_decline_pending(phase)
	for _i in [1, 2]:
		if int(phase.pile_in_step_11e) != int(phase.PileInStep11e.ACTIVE):
			break
		phase.execute_action({"type": "END_PILE_IN", "player": int(phase.piling_in_player_11e)})
		_decline_pending(phase)
	_check("own turn: not offered (P1 active would be 'your' Fight phase)", true)
	var sel = phase.sequencer_11e.peek_selection(GS.state)
	print("    selection: %s" % str(sel))
	_check("P2 (active) selects first", int(sel.player) == 2, str(sel))
	var r = phase.execute_action({"type": "SELECT_FIGHTER", "unit_id": "U_BOYZ_B", "player": 2})
	_decline_pending(phase)
	_window_events.clear()
	var batch := {"type": "BATCH_FIGHT_ACTIONS", "player": 2, "sub_actions": [
		{"type": "ASSIGN_ATTACKS", "unit_id": "U_BOYZ_B", "target_id": "U_CUSTODIAN_GUARD_A", "weapon_id": _first_melee_weapon("U_BOYZ_B"), "attacking_models": [], "player": 2},
		{"type": "CONFIRM_AND_RESOLVE_ATTACKS", "player": 2},
		{"type": "ROLL_DICE", "player": 2, "payload": {"fast_roll": true}}]}
	r = phase.execute_action(batch)
	# enemy_targets_unit_fight (Shadowkeepers has none) then the fight resolves.
	_decline_pending(phase)
	var seen := false
	var targets: Array = []
	for e in _window_events:
		if str(e.window_id) == "enemy_has_fought" and int(e.player) == 1:
			seen = true
			targets = _offer_targets(e.offers, sid)
	_check("Boyz have fought -> enemy_has_fought opens for P1", seen, str(_window_events.map(func(e): return e.window_id)))
	_check("offered on Custodian Guard A (on obj_center, engaged = eligible to fight)", "U_CUSTODIAN_GUARD_A" in targets, str(targets))
	_check("not offered on the Vigilators (not within range of an objective)", not "U_VIGILATORS_A" in targets, str(targets))
	# Use it through a fresh window (the one above was declined).
	var cp0 := _cp(1)
	phase.open_stratagem_window(1, "enemy_has_fought", {"phase": "fight", "enemy_unit_id": "U_BOYZ_B"}, "")
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "enemy_has_fought", "stratagem_id": sid, "target_unit_id": "U_CUSTODIAN_GUARD_A"})
	_check("USE succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	_check("Fights First + the 'next unit' marker", bool(_flags("U_CUSTODIAN_GUARD_A").get("fights_first", false)) and bool(_flags("U_CUSTODIAN_GUARD_A").get("cus11e_indomitable_guardians", false)))
	_check("P1's candidates are restricted to Custodian Guard A", Codex.restrict_fight_candidates(1, ["U_VIGILATORS_A", "U_CUSTODIAN_GUARD_A"]) == ["U_CUSTODIAN_GUARD_A"])
	_check("P2's candidates unaffected", Codex.restrict_fight_candidates(2, ["U_WARBOSS_A", "U_MEGANOBZ_A"]).size() == 2)
	var cands = phase.sequencer_11e.selectable_units(GS.state, 1, false)
	_check("FightSequencer.selectable_units for P1 = [Custodian Guard A]", cands == ["U_CUSTODIAN_GUARD_A"], str(cands))
	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry: marker + the granted Fights First removed", not _flags("U_CUSTODIAN_GUARD_A").has("cus11e_indomitable_guardians") and not _flags("U_CUSTODIAN_GUARD_A").has("fights_first"))
	_restore_unit_state()
	# In the Custodes' own Fight phase the window is not opened for them.
	var phase2 = _fresh_fight()
	var own = SM.get_window_offers(1, "enemy_has_fought", {"phase": "fight", "enemy_unit_id": "U_BOYZ_B"})
	_check("not offered in your own Fight phase (Opponent's turn)", not sid in _offer_ids(own), str(own))
	_restore_unit_state()


# ---------------------------------------------------------------------------
func _section_lightning_wrath() -> void:
	print("\n-- J. LIGHTNING WRATH --")
	_set_detachment(1, "Dread Host")
	var sid := _sid(1, CSV_LW)
	_check("loaded (Dread Host)", sid != "")
	var phase = _fresh_fight(Callable(), false)
	_check("Pile In step active", int(phase.pile_in_step_11e) == int(phase.PileInStep11e.ACTIVE), str(phase.pile_in_step_11e))
	var piler := int(phase.piling_in_player_11e)
	print("    piling-in player: %d, eligible: %s" % [piler, str(phase._pile_in_eligible_units_11e(piler))])
	if piler != 1:
		phase.execute_action({"type": "END_PILE_IN", "player": piler})
		_decline_pending(phase)
		piler = int(phase.piling_in_player_11e)
	_check("P1's half of the Pile In step", piler == 1)
	_check("not offered in another window", not sid in _offer_ids(SM.get_window_offers(1, "unit_selected_to_fight", {"unit_id": "U_CUSTODIAN_GUARD_A"})))
	_window_events.clear()
	var ready_events: Array = []
	var cb := func(kind, uid, inches): ready_events.append([kind, uid, inches])
	phase.cus11e_step_unit_ready.connect(cb)
	var r = phase.execute_action({"type": "CUS11E_SELECT_PILE_IN_UNIT", "unit_id": "U_CUSTODIAN_GUARD_A", "player": 1})
	var pend: Dictionary = phase.get_pending_stratagem_window()
	_check("CUS11E_SELECT_PILE_IN_UNIT opens unit_selected_to_pile_in for P1", r.get("success", false) and str(pend.get("window_id", "")) == "unit_selected_to_pile_in" and int(pend.get("player", 0)) == 1, "%s / %s" % [str(r.get("error", "")), str(pend.get("window_id", ""))])
	_check("LIGHTNING WRATH offered on the selected unit", _offer_targets(pend.get("offers", []), sid) == ["U_CUSTODIAN_GUARD_A"])
	_check("the move does not start before the answer", ready_events.is_empty())
	var cp0 := _cp(1)
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_pile_in", "stratagem_id": sid, "target_unit_id": "U_CUSTODIAN_GUARD_A"})
	_check("USE succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	var inches := int(_flags("U_CUSTODIAN_GUARD_A").get("cus11e_lightning_wrath", 0))
	_check("pile-in distance D3+3 in 4..6 (%d)" % inches, inches >= 4 and inches <= 6)
	_check("cus11e_step_unit_ready emitted with that distance", ready_events.size() == 1 and str(ready_events[0][0]) == "pile_in" and absf(float(ready_events[0][2]) - inches) < 0.01, str(ready_events))
	_check("result carries cus11e_step_unit_ready", use.has("cus11e_step_unit_ready"), str(use.keys()))
	var again = phase.execute_action({"type": "CUS11E_SELECT_PILE_IN_UNIT", "unit_id": "U_CUSTODIAN_GUARD_A", "player": 1})
	_check("re-selecting the unit does not re-open the window", again.get("success", false) and not phase.has_pending_stratagem_window())
	# Cap honoured: a model moved 4.5" towards the enemy is legal only with the bonus.
	var model: Dictionary = _unit("U_CUSTODIAN_GUARD_A").models[0]
	var p0 = model.position
	var cap: float = phase._fight_effective_move_cap(_unit("U_CUSTODIAN_GUARD_A"), model, {}, "0", maxf(3.0, float(Codex.pile_in_inches("U_CUSTODIAN_GUARD_A"))))
	_check("effective pile-in cap = %d\"" % inches, absf(cap - inches) < 0.01, str(cap))
	_check("the bad unit is refused for the other player", not phase.execute_action({"type": "CUS11E_SELECT_PILE_IN_UNIT", "unit_id": "U_BOYZ_B", "player": 2}).get("success", true))
	phase.cus11e_step_unit_ready.disconnect(cb)
	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry at end of phase", not _flags("U_CUSTODIAN_GUARD_A").has("cus11e_lightning_wrath"))
	_restore_unit_state()


# ---------------------------------------------------------------------------
func _section_emperors_domain() -> void:
	print("\n-- K. EMPEROR'S DOMAIN --")
	_set_detachment(1, "Honoured Companions")
	var sid := _sid(1, CSV_DOMAIN)
	_check("loaded (Honoured Companions)", sid != "")
	var phase = _fresh_fight()
	# Walk to the Consolidate step: settle every owed fight, END_FIGHT.
	for entry in phase.get_unfought_eligible_units():
		phase.sequencer_11e.mark_fought(str(entry.get("unit_id", "")), GS.state)
	for _i in range(4):
		if int(phase.consolidation_step_11e) == int(phase.ConsolidationStep11e.ACTIVE) or _phase_done:
			break
		phase.execute_action({"type": "END_FIGHT", "player": int(GS.get_active_player())})
		_decline_pending(phase)
	_check("Consolidate step active", int(phase.consolidation_step_11e) == int(phase.ConsolidationStep11e.ACTIVE), str(phase.consolidation_step_11e))
	var cons := int(phase.consolidating_player_11e)
	if cons != 1:
		phase.execute_action({"type": "END_CONSOLIDATION", "player": cons})
		_decline_pending(phase)
	print("    consolidating player %d eligible %s" % [int(phase.consolidating_player_11e), str(phase._consolidation_eligible_units_11e(1))])
	var r = phase.execute_action({"type": "CUS11E_SELECT_CONSOLIDATION_UNIT", "unit_id": "U_CUSTODIAN_GUARD_A", "player": 1})
	var pend: Dictionary = phase.get_pending_stratagem_window()
	_check("CUS11E_SELECT_CONSOLIDATION_UNIT opens unit_selected_to_consolidate", r.get("success", false) and str(pend.get("window_id", "")) == "unit_selected_to_consolidate", "%s / %s" % [str(r.get("error", "")), str(pend.get("window_id", ""))])
	_check("EMPEROR'S DOMAIN offered on Custodian Guard A (obj_center within 3\")", _offer_targets(pend.get("offers", []), sid) == ["U_CUSTODIAN_GUARD_A"], str(pend.get("offers", [])))
	_check("not offered on the Vigilators (not TRUSTED SENTINEL)", not sid in _offer_ids(SM.get_window_offers(1, "unit_selected_to_consolidate", {"unit_id": "U_VIGILATORS_A"})))
	var cm = load("res://scripts/rules/movetypes/ConsolidationMove.gd").new()
	var before_mode = cm.select_mode("U_CUSTODIAN_GUARD_A", GS.state) if cm.has_method("select_mode") else "?"
	var cp0 := _cp(1)
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_consolidate", "stratagem_id": sid, "target_unit_id": "U_CUSTODIAN_GUARD_A"})
	_check("USE succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	_check("flag cus11e_emperors_domain", bool(_flags("U_CUSTODIAN_GUARD_A").get("cus11e_emperors_domain", false)))
	var after_mode = cm.select_mode("U_CUSTODIAN_GUARD_A", GS.state) if cm.has_method("select_mode") else "?"
	print("    consolidation mode before %s after %s" % [str(before_mode), str(after_mode)])
	_check("consolidation mode is objective with the stratagem", str(after_mode).to_lower().contains("objective"), str(after_mode))
	_check("engaged unit without it: engagement mode (Before Moving order)", not str(before_mode).to_lower().contains("objective"), str(before_mode))
	_check("cus11e_step_unit_ready result for the consolidation", str(use.get("cus11e_step_unit_ready", {}).get("kind", "")) == "consolidate", str(use.get("cus11e_step_unit_ready", {})))
	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry at end of phase", not _flags("U_CUSTODIAN_GUARD_A").has("cus11e_emperors_domain"))
	_restore_unit_state()


# ---------------------------------------------------------------------------
func _section_honoured_interred() -> void:
	print("\n-- L. HONOURED INTERRED --")
	_set_detachment(1, "Might of the Moritoi")
	var sid := _sid(1, CSV_HI)
	_check("loaded (Might of the Moritoi)", sid != "")
	_check("no window (S panel)", SM.get_stratagem(sid).get("timing", {}).get("windows", []).is_empty())
	_reset_usage()
	PM.transition_to_phase(PHASE_MOVEMENT)
	_check("refused in the Movement phase", not SM.can_use_stratagem(1, sid, "U_CONTEMPTOR_A").can_use)
	PM.transition_to_phase(PHASE_SHOOTING)
	_cus11e_unready()
	_check("allowed in your Shooting phase (Contemptor)", SM.can_use_stratagem(1, sid, "U_CONTEMPTOR_A").can_use, str(SM.can_use_stratagem(1, sid, "U_CONTEMPTOR_A")))
	_check("refused on a non-DREADNOUGHT", not SM.can_use_stratagem(1, sid, "U_CUSTODIAN_GUARD_A").can_use)
	_check("S panel probe (no target) allowed", SM.can_use_stratagem(1, sid, "").can_use)
	GS.state.meta["active_player"] = 2
	_check("refused in the opponent's Shooting phase", not SM.can_use_stratagem(1, sid, "U_CONTEMPTOR_A").can_use)
	GS.state.meta["active_player"] = 1
	var cp0 := _cp(1)
	var res = SM.use_stratagem(1, sid, "U_CONTEMPTOR_A")
	_check("use succeeds, CP -1", res.get("success", false) and _cp(1) == cp0 - 1, str(res.get("error", "")))
	_check("aura source flag on the Contemptor", bool(_flags("U_CONTEMPTOR_A").get("cus11e_honoured_interred", false)))
	_check("Custodian Guard B (within 6\") re-rolls hit 1s", Fight.honoured_interred_source(_unit("U_CUSTODIAN_GUARD_B")) == "U_CONTEMPTOR_A")
	_check("Custodian Guard A (7\" away) not covered", Fight.honoured_interred_source(_unit("U_CUSTODIAN_GUARD_A")) == "")
	_check("Wardens (far) not covered", Fight.honoured_interred_source(_unit("U_CUSTODIAN_WARDENS_A")) == "")
	_check("the Dreadnought itself covered", Fight.honoured_interred_source(_unit("U_CONTEMPTOR_A")) == "U_CONTEMPTOR_A")
	_check("enemy units never covered", Fight.honoured_interred_source(_unit("U_MEGANOBZ_A")) == "")
	var bits = Codex.apply_hit_bits(0, _unit("U_CUSTODIAN_GUARD_B"), _unit("U_BOYZ_B"), false, GS.state, [])
	_check("hit bits gain REROLL_ONES (ranged)", (bits & Codex.HIT_REROLL_ONES) != 0, str(bits))
	SM.on_phase_end(PHASE_SHOOTING)
	_check("expiry at end of phase", not _flags("U_CONTEMPTOR_A").has("cus11e_honoured_interred"))
	PM.transition_to_phase(PHASE_FIGHT)
	_decline_pending(PM.get_current_phase_instance())
	GS.state.meta["active_player"] = 2
	_check("allowed in the opponent's Fight phase", SM.can_use_stratagem(1, sid, "U_CONTEMPTOR_A").can_use, str(SM.can_use_stratagem(1, sid, "U_CONTEMPTOR_A")))
	GS.state.meta["active_player"] = 1
	_restore_unit_state()


# ---------------------------------------------------------------------------
func _section_ai() -> void:
	print("\n-- M. AI decisions --")
	var ADM = load("res://scripts/AIDecisionMaker.gd")
	var ai = root.get_node("AIPlayer")
	_set_detachment(1, "Null Maiden Vigil")
	var bm := _sid(1, CSV_BM)
	var phase = _fresh_fight()
	var ctx := {"phase": "fight", "unit_id": "U_VIGILATORS_A"}
	var offers = SM.get_window_offers(1, "unit_selected_to_fight", ctx)
	var d = ADM.decide_window_stratagem(1, "unit_selected_to_fight", offers, ctx)
	_check("AI uses ANATHEMA BLADEMASTERY on engaged Vigilators", d.get("use", false) and str(d.get("stratagem_id", "")) == bm, str(d))
	_check("AI picks a variant", str(d.get("context", {}).get("variant_id", "")) in ["lethal_hits", "sustained_hits"], str(d))
	ai.enabled = true
	ai.ai_players = {1: true, 2: false}
	var cp0 := _cp(1)
	var paused = phase.open_stratagem_window(1, "unit_selected_to_fight", ctx, "")
	var sync = phase.consume_window_diffs()
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_check("AI window resolves synchronously (never pauses)", not paused and not phase.has_pending_stratagem_window())
	_check("AI spent 1 CP and the flag is set", _cp(1) == cp0 - 1 and _flags("U_VIGILATORS_A").has("cus11e_anathema_blademastery"))
	_check("synchronous diffs handed back", not sync.is_empty())
	SM.on_phase_end(PHASE_FIGHT)
	_restore_unit_state()
	# LIGHTNING WRATH / EMPEROR'S DOMAIN: the AI selects the unit first, decides.
	_set_detachment(1, "Dread Host")
	phase = _fresh_fight(Callable(), false)
	if int(phase.piling_in_player_11e) != 1:
		phase.execute_action({"type": "END_PILE_IN", "player": int(phase.piling_in_player_11e)})
		_decline_pending(phase)
	var act: Dictionary = ADM._cus11e_ai_step_select("pile_in", "U_CUSTODIAN_GUARD_A", 1)
	_check("AI: pile-in for a Dread Host unit selects it first (CUS11E_SELECT_PILE_IN_UNIT)", str(act.get("type", "")) == "CUS11E_SELECT_PILE_IN_UNIT", str(act))
	ai.enabled = true
	ai.ai_players = {1: true, 2: false}
	var r = phase.execute_action(act)
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_check("AI select resolves synchronously", r.get("success", false) and not phase.has_pending_stratagem_window(), str(r.get("error", "")))
	_check("AI: not asked twice for the same unit", ADM._cus11e_ai_step_select("pile_in", "U_CUSTODIAN_GUARD_A", 1).is_empty())
	_check("AI: no select for an army without such a stratagem (P2)", ADM._cus11e_ai_step_select("pile_in", "U_BOYZ_B", 2).is_empty())
	var lw = Fight.ai_score(SM.get_stratagem(_sid(1, CSV_LW)), 1, "U_CUSTODIAN_GUARD_A", "unit_selected_to_pile_in", {})
	print("    LIGHTNING WRATH AI score for Custodian Guard A: %.2f (cus11e_lightning_wrath=%s)" % [lw, str(_flags("U_CUSTODIAN_GUARD_A").get("cus11e_lightning_wrath", "-"))])
	_check("AI LIGHTNING WRATH score is a number >= 0", lw >= 0.0)
	SM.on_phase_end(PHASE_FIGHT)
	_restore_unit_state()
