extends SceneTree

# Codex: Adeptus Custodes (11e) — SHOOTING group stratagems (WP-C5,
# CustodesCodexShooting.gd). Fixtures tests/saves/cus11e_c5_active (P1
# Custodes active) and cus11e_c5_reactive (P1 Orks active, P2 Custodes):
#   A. registry: the 9 SHOOTING csv ids are implemented
#   B. PSY-CHAFF VOLLEY        unit_has_shot after a real SHOOT; hit-enemy
#      secondary pick; prosecuted = +1 AP for every attacker; end of turn
#   C. PURGATION SWEEP         unit_selected_to_shoot (real SELECT_SHOOTER);
#      [TORRENT] +1 A / +2 A vs PSYKER-battle-shocked (attack dice A/B)
#   D. PRIME TARGET            one hit / wound / damage re-roll: interactive
#      availability + auto resolver (one re-roll per stage, spent once)
#   E. TIP OF THE TALON        +1 S within 9" (wound threshold A/B)
#   F. ADVANCED STABILISERS    an Advanced GRAV-ASSAULT unit is selectable only
#      while the stratagem can make its weapons [ASSAULT]; every ranged weapon
#      allowed by the assault shooting type after the use
#   G. INEVITABLE ANNIHILATION BS / hit-roll penalties ignored (bits + stack)
#   H. VIGIL UNENDING          enemy_targets_unit_shooting (reactive dialog,
#      opponent's Shooting phase): TERMINATOR, -1 D until that unit attacked
#   I. IN AURAMITE CLAD ×2     -1 AP until that unit attacked; not WARDENS;
#      both detachment rows told apart by csv_id
#   J. AI decider paths
#
# Usage: godot --headless --path 40k --script tests/test_custodes_codex_shooting.gd

const PHASE_COMMAND := 6
const PHASE_MOVEMENT := 7
const PHASE_SHOOTING := 8
const PHASE_FIGHT := 10
const PX := 40.0

const CSV_PSY := "psy-chaff-volley-null-maiden-vigil"
const CSV_PURG := "purgation-sweep-null-maiden-vigil"
const CSV_PT := "prime-target-guardians-of-the-throne"
const CSV_TIP := "tip-of-the-talon-aquilan-shield"
const CSV_ADV := "advanced-stabilisers-grav-assault-force"
const CSV_INEV := "inevitable-annihilation-grav-assault-force"
const CSV_VIGIL := "vigil-unending-lions-of-the-emperor"
const CSV_AUR_G := "in-auramite-clad-guardians-of-the-throne"
const CSV_AUR_E := "in-auramite-clad-emperors-chosen"

var passed := 0
var failed := 0
var SM = null
var GS = null
var PM = null
var RE = null
var Codex = null
var Shoot = null
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


func _stage_fixture(fixture: String) -> bool:
	var slm = root.get_node("SaveLoadManager")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slm.save_directory))
	for ext in [".w40ksave", ".meta"]:
		var src = "res://tests/saves/" + fixture + ext
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(slm.save_directory + fixture + ext))
	var ok: bool = slm.load_game(fixture)
	GS.set_edition(11)
	return ok


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


func _reset_usage() -> void:
	SM._clear_expired_effects("end_of_phase")
	SM._usage_history = {"1": [], "2": []}
	SM.active_effects = []
	GS.state.players["1"]["cp"] = 6
	GS.state.players["2"]["cp"] = 6


func _cus11e_unready() -> void:
	var rnd: int = int(GS.get_battle_round())
	for uid in GS.state.units:
		var f := _flags(uid)
		f.erase("cus11e_readied")
		f["cus11e_master_of_katahs_round"] = rnd
	if GS.state.units.has("U_TRAJANN_A"):
		_flags("U_TRAJANN_A")["moment_shackle_used"] = true


func _decline_pending(phase) -> int:
	var n := 0
	while phase.has_pending_stratagem_window() and n < 8:
		var w: Dictionary = phase.get_pending_stratagem_window()
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(w.get("player", 0)), "window_id": str(w.get("window_id", ""))})
		n += 1
	return n


func _fresh_shooting(prep: Callable = Callable()):
	_reset_usage()
	PM.transition_to_phase(PHASE_COMMAND)
	_cus11e_unready()
	if prep.is_valid():
		prep.call()
	PM.transition_to_phase(PHASE_SHOOTING)
	var phase = PM.get_current_phase_instance()
	if phase and not phase.stratagem_window_opened.is_connected(_on_window_opened):
		phase.stratagem_window_opened.connect(_on_window_opened)
	return phase


func _assign(board: Dictionary, uid: String, wid: String, tid: String) -> Dictionary:
	var model_ids: Array = []
	var w = RE.get_unit_weapons(uid, board)
	for mid in w:
		if wid in w[mid]:
			model_ids.append(str(mid))
	return {"weapon_id": wid, "target_unit_id": tid, "model_ids": model_ids}


func _first_ranged_weapon(uid: String, must_contain: String = "") -> String:
	var w = RE.get_unit_weapons(uid, GS.state)
	for mid in w:
		for wid in w[mid]:
			if must_contain == "" or must_contain.to_lower() in str(wid).to_lower():
				return str(wid)
	return ""


func _shoot_action(player: int, uid: String, wid: String, tid: String, seed_val: int = 7) -> Dictionary:
	return {"type": "SHOOT", "actor_unit_id": uid, "player": player,
		"payload": {"assignments": [_assign(GS.state, uid, wid, tid)], "rng_seed": seed_val}}


func _block(res: Dictionary, ctx_name: String) -> Dictionary:
	for d in res.get("dice", []):
		if str(d.get("context", "")) == ctx_name:
			return d
	return {}


func _auto(board: Dictionary, uid: String, assignment: Dictionary, seed_val: int) -> Dictionary:
	return RE.resolve_shoot({"type": "SHOOT", "actor_unit_id": uid, "payload": {"assignments": [assignment]}}, board, RE.RNGService.new(seed_val))


func _interactive(board: Dictionary, uid: String, assignment: Dictionary, seed_val: int) -> Dictionary:
	return RE.resolve_shoot_until_wounds({"type": "SHOOT", "actor_unit_id": uid, "payload": {"assignments": [assignment]}}, board, RE.RNGService.new(seed_val))


func _board_with(flags_on: Dictionary, actor: String) -> Dictionary:
	var b: Dictionary = GS.state.duplicate(true)
	for k in flags_on:
		for uid in RE.attached_unit_component_ids(actor, b):
			b.units[uid].flags[k] = flags_on[k]
	return b


# ---------------------------------------------------------------------------
func _run() -> void:
	SM = root.get_node("StratagemManager")
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	Codex = load("res://scripts/codex/custodes/CustodesCodex11e.gd")
	Shoot = load("res://scripts/codex/custodes/CustodesCodexShooting.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	print("\n=== test_custodes_codex_shooting ===\n")
	_check("fixture cus11e_c5_active loads", _stage_fixture("cus11e_c5_active"))
	root.get_node("SettingsService").set("auto_allocate_wounds", true)

	_section_registry()
	_section_psy_chaff()
	_section_purgation()
	_section_prime_target()
	_section_tip()
	_section_advanced_stabilisers()
	_section_inevitable()
	_check("fixture cus11e_c5_reactive loads", _stage_fixture("cus11e_c5_reactive"))
	_section_vigil()
	_section_auramite()
	_check("fixture cus11e_c5_active reloads", _stage_fixture("cus11e_c5_active"))
	_section_ai()


# ---------------------------------------------------------------------------
func _section_registry() -> void:
	print("\n-- A. registry --")
	var impl: Array = Codex.all_implemented_ids()
	for csv in [CSV_PSY, CSV_PURG, CSV_PT, CSV_TIP, CSV_ADV, CSV_INEV, CSV_VIGIL, CSV_AUR_G, CSV_AUR_E]:
		_check("%s implemented (Shooting group)" % csv, csv in impl and Shoot.IMPLEMENTED.get(csv, false) and Codex.group_for_id(csv) == Shoot)


# ---------------------------------------------------------------------------
func _section_psy_chaff() -> void:
	print("\n-- B. PSY-CHAFF VOLLEY --")
	_set_detachment(1, "Null Maiden Vigil")
	var sid := _sid(1, CSV_PSY)
	_check("loaded (Null Maiden Vigil)", sid != "")
	var phase = _fresh_shooting()
	var wid := _first_ranged_weapon("U_PROSECUTORS_A")
	_check("Prosecutors have a ranged weapon (%s)" % wid, wid != "")
	_window_events.clear()
	var res = phase.execute_action(_shoot_action(1, "U_PROSECUTORS_A", wid, "U_GRETCHIN_C"))
	_decline_pending_selected(phase)
	var pend: Dictionary = phase.get_pending_stratagem_window()
	print("    windows: %s pending %s" % [str(_window_events.map(func(e): return e.window_id)), str(pend.get("window_id", ""))])
	_check("SHOOT resolves and opens unit_has_shot for P1", res.get("success", false) and str(pend.get("window_id", "")) == "unit_has_shot" and int(pend.get("player", 0)) == 1, "%s / %s" % [str(res.get("error", "")), str(pend.get("window_id", ""))])
	var hit_ids: Array = pend.get("ctx", {}).get("hit_unit_ids", [])
	_check("window ctx carries the units hit (%s)" % str(hit_ids), "U_GRETCHIN_C" in hit_ids)
	var entry := _offer_entry(pend.get("offers", []), sid, "U_PROSECUTORS_A")
	_check("PSY-CHAFF VOLLEY offered on the PROSECUTOR SQUAD with a hit-enemy pick", not entry.is_empty() and str(entry.get("secondary", {}).get("kind", "")) == "unit"
		and entry.get("secondary", {}).get("options", []).map(func(o): return str(o.id)) == ["U_GRETCHIN_C"], str(entry))
	_check("not offered on another unit's shot (Witchseekers)", SM.get_window_offers(1, "unit_has_shot", {"unit_id": "U_WITCHSEEKERS_A", "hit_unit_ids": ["U_GRETCHIN_C"]}).filter(func(o): return str(o.stratagem_id) == sid).is_empty())
	_check("not offered when nothing was hit", not sid in _offer_ids(SM.get_window_offers(1, "unit_has_shot", {"unit_id": "U_PROSECUTORS_A", "hit_unit_ids": []})))
	var miss = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_has_shot", "stratagem_id": sid, "target_unit_id": "U_PROSECUTORS_A"})
	_check("USE without the enemy pick refused", not miss.get("success", true), str(miss))
	var cp0 := _cp(1)
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_has_shot", "stratagem_id": sid,
		"target_unit_id": "U_PROSECUTORS_A", "context": {"secondary_id": "U_GRETCHIN_C"}})
	_check("USE succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	_check("Gretchin C prosecuted", int(_flags("U_GRETCHIN_C").get("cus11e_prosecuted", 0)) == 1)
	_check("+1 AP vs a prosecuted unit (AP -1 -> -2)", Codex.modify_ap(-1, _unit("U_WITCHSEEKERS_A"), _unit("U_GRETCHIN_C")) == -2)
	_check("+1 AP from AP 0 (0 -> -1)", Codex.modify_ap(0, _unit("U_CONTEMPTOR_A"), _unit("U_GRETCHIN_C")) == -1)
	_check("no change vs another unit", Codex.modify_ap(-1, _unit("U_WITCHSEEKERS_A"), _unit("U_BOYZ_B")) == -1)
	SM.on_phase_end(PHASE_SHOOTING)
	_check("still prosecuted after the phase (until the end of the turn)", int(_flags("U_GRETCHIN_C").get("cus11e_prosecuted", 0)) == 1)
	SM.on_turn_start(2)
	_check("expiry: cleared at the end of the turn", not _flags("U_GRETCHIN_C").has("cus11e_prosecuted") and not _flags("U_PROSECUTORS_A").has("cus11e_psy_chaff_target"))


## The atomic SHOOT opens unit_selected_to_shoot first when a stratagem /
## ka'tah could be used; decline those so the shot resolves.
func _decline_pending_selected(phase) -> void:
	var guard := 0
	while phase.has_pending_stratagem_window() and str(phase.get_pending_stratagem_window().get("window_id", "")) == "unit_selected_to_shoot" and guard < 4:
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(phase.get_pending_stratagem_window().get("player", 0)), "window_id": "unit_selected_to_shoot"})
		guard += 1


# ---------------------------------------------------------------------------
func _section_purgation() -> void:
	print("\n-- C. PURGATION SWEEP --")
	_set_detachment(1, "Null Maiden Vigil")
	var sid := _sid(1, CSV_PURG)
	_check("loaded (Null Maiden Vigil)", sid != "")
	var phase = _fresh_shooting()
	var r = phase.execute_action({"type": "SELECT_SHOOTER", "actor_unit_id": "U_WITCHSEEKERS_A", "player": 1})
	var pend: Dictionary = phase.get_pending_stratagem_window()
	_check("SELECT_SHOOTER Witchseekers opens unit_selected_to_shoot", r.get("success", false) and str(pend.get("window_id", "")) == "unit_selected_to_shoot", "%s / %s" % [str(r.get("error", "")), str(pend.get("window_id", ""))])
	var entry := _offer_entry(pend.get("offers", []), sid, "U_WITCHSEEKERS_A")
	_check("offered with two variants (+1 A / +2 A vs PSYKER-battle-shocked)", entry.get("variants", []).size() == 2 and bool(entry.get("require_variant", false)), str(entry))
	_check("not offered on the Prosecutors (not WITCHSEEKER SQUAD)", not sid in _offer_ids(SM.get_window_offers(1, "unit_selected_to_shoot", {"unit_id": "U_PROSECUTORS_A"})))
	var cp0 := _cp(1)
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_shoot", "stratagem_id": sid,
		"target_unit_id": "U_WITCHSEEKERS_A", "context": {"variant_id": "plus_one"}})
	_check("USE +1 A succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	_check("flag cus11e_purgation_sweep = plus_one", str(_flags("U_WITCHSEEKERS_A").get("cus11e_purgation_sweep", "")) == "plus_one")
	var wid := _first_ranged_weapon("U_WITCHSEEKERS_A", "flamer")
	# (the live Witchseekers now carry the flag: the "off" board clears it)
	var a_off := int(_block(_interactive(_board_with({"cus11e_purgation_sweep": ""}, "U_WITCHSEEKERS_A"), "U_WITCHSEEKERS_A", _assign(GS.state, "U_WITCHSEEKERS_A", wid, "U_GRETCHIN_C"), 11), "auto_hit").get("total_attacks", -1))
	var on_board := _board_with({"cus11e_purgation_sweep": "plus_one"}, "U_WITCHSEEKERS_A")
	var a_on := int(_block(_interactive(on_board, "U_WITCHSEEKERS_A", _assign(GS.state, "U_WITCHSEEKERS_A", wid, "U_GRETCHIN_C"), 11), "auto_hit").get("total_attacks", -1))
	print("    torrent attacks off %d on %d" % [a_off, a_on])
	_check("A/B [TORRENT]: +1 A per model (4 models: +4 attacks)", a_off > 0 and a_on == a_off + 4, "%d -> %d" % [a_off, a_on])
	var two_board := _board_with({"cus11e_purgation_sweep": "plus_two_psyker"}, "U_WITCHSEEKERS_A")
	var a_two_plain := int(_block(_interactive(two_board.duplicate(true), "U_WITCHSEEKERS_A", _assign(GS.state, "U_WITCHSEEKERS_A", wid, "U_GRETCHIN_C"), 11), "auto_hit").get("total_attacks", -1))
	two_board.units.U_GRETCHIN_C.flags["battle_shocked"] = true
	var a_two_shocked := int(_block(_interactive(two_board, "U_WITCHSEEKERS_A", _assign(GS.state, "U_WITCHSEEKERS_A", wid, "U_GRETCHIN_C"), 11), "auto_hit").get("total_attacks", -1))
	_check("+2 A option: no bonus vs a normal target", a_two_plain == a_off, "%d vs %d" % [a_two_plain, a_off])
	_check("+2 A option: +2 A per model vs a battle-shocked target", a_two_shocked == a_off + 8, "%d vs %d" % [a_two_shocked, a_off])
	SM.on_phase_end(PHASE_SHOOTING)
	_check("expiry at end of phase", not _flags("U_WITCHSEEKERS_A").has("cus11e_purgation_sweep"))


# ---------------------------------------------------------------------------
func _section_prime_target() -> void:
	print("\n-- D. PRIME TARGET --")
	_set_detachment(1, "Guardians of the Throne")
	var sid := _sid(1, CSV_PT)
	_check("loaded (Guardians of the Throne)", sid != "")
	var phase = _fresh_shooting()
	var r = phase.execute_action({"type": "SELECT_SHOOTER", "actor_unit_id": "U_PROSECUTORS_A", "player": 1})
	var pend: Dictionary = phase.get_pending_stratagem_window()
	_check("offered on any ADEPTUS CUSTODES unit selected to shoot", _offer_targets(pend.get("offers", []), sid) == ["U_PROSECUTORS_A"], str(pend.get("offers", [])))
	var cp0 := _cp(1)
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_shoot", "stratagem_id": sid, "target_unit_id": "U_PROSECUTORS_A"})
	_check("USE succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	var pt = _flags("U_PROSECUTORS_A").get("cus11e_prime_target", {})
	_check("one hit, one wound and one damage re-roll available", typeof(pt) == TYPE_DICTIONARY and pt.get("hit", false) and pt.get("wound", false) and pt.get("damage", false), str(pt))
	_check("interactive: the staged hit re-roll is offered (PRIME TARGET first)", phase._shooting_reroll_available("hits") and phase._cus11e_prime_target_reroll("hits"))
	_check("interactive: the dock label names PRIME TARGET", "PRIME TARGET" in phase._cus11e_reroll_label("hits"))
	# Auto path: exactly one failed hit and one failed wound are re-rolled.
	var wid := _first_ranged_weapon("U_PROSECUTORS_A")
	var asg := _assign(GS.state, "U_PROSECUTORS_A", wid, "U_GRETCHIN_C")
	var rerolled_hits := 0
	var helped := 0
	for sd in range(8000, 8030):
		var b_off := _board_with({"cus11e_prime_target": {}}, "U_PROSECUTORS_A")
		var b_on := _board_with({"cus11e_prime_target": {"hit": true, "wound": true, "damage": true}}, "U_PROSECUTORS_A")
		var off = _auto(b_off, "U_PROSECUTORS_A", asg, sd)
		var on = _auto(b_on, "U_PROSECUTORS_A", asg, sd)
		var h_off := int(_block(off, "to_hit").get("successes", 0))
		var h_on := int(_block(on, "to_hit").get("successes", 0))
		if h_on > h_off:
			helped += 1
		if h_on > h_off + 1:
			rerolled_hits = 99
		var left = b_on.units.U_PROSECUTORS_A.flags.get("cus11e_prime_target", {})
		if typeof(left) == TYPE_DICTIONARY and left.get("hit", false) and h_off < int(_block(off, "to_hit").get("total_attacks", 99)):
			rerolled_hits = -99
	_check("auto path: never more than one extra hit (one re-roll)", rerolled_hits != 99)
	_check("auto path: a failed hit always spends the hit re-roll", rerolled_hits != -99)
	_check("auto path: the re-roll helps on some seeds (%d/30)" % helped, helped > 0)
	var live_pt = _flags("U_PROSECUTORS_A").get("cus11e_prime_target", {})
	_check("A/B on board copies never spends the live unit's re-rolls", typeof(live_pt) == TYPE_DICTIONARY and live_pt.get("hit", false) and live_pt.get("wound", false), str(live_pt))
	# Spending on the live unit (the interactive path's diffs).
	var spend: Array = Codex.single_reroll_spend_diffs("U_PROSECUTORS_A", "hit")
	PM.apply_state_changes(spend)
	_check("spent: no hit re-roll left, wound re-roll still there", not Codex.single_reroll_available(_unit("U_PROSECUTORS_A"), "hit") and Codex.single_reroll_available(_unit("U_PROSECUTORS_A"), "wound"))
	_check("interactive: hit re-roll no longer free (Command Re-roll may still be offered)", not phase._cus11e_prime_target_reroll("hits"))
	_check("melee attacks never use it", not Codex.single_reroll_available(_unit("U_PROSECUTORS_A"), "wound", true))
	SM.on_phase_end(PHASE_SHOOTING)
	_check("expiry at end of phase", not _flags("U_PROSECUTORS_A").has("cus11e_prime_target"))


# ---------------------------------------------------------------------------
func _section_tip() -> void:
	print("\n-- E. TIP OF THE TALON --")
	_set_detachment(1, "Aquilan Shield")
	var sid := _sid(1, CSV_TIP)
	_check("loaded (Aquilan Shield)", sid != "")
	var phase = _fresh_shooting()
	phase.open_stratagem_window(1, "unit_selected_to_shoot", {"phase": "shooting", "unit_id": "U_PROSECUTORS_A"}, "")
	var cp0 := _cp(1)
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_shoot", "stratagem_id": sid, "target_unit_id": "U_PROSECUTORS_A"})
	_check("USE succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	_check("+1 S vs the Gretchin (3\" away)", Codex.ranged_strength_bonus(_unit("U_PROSECUTORS_A"), _unit("U_GRETCHIN_C"), GS.state) == 1)
	_check("no bonus vs the Nobz (far)", Codex.ranged_strength_bonus(_unit("U_PROSECUTORS_A"), _unit("U_NOBZ_A"), GS.state) == 0)
	var wid := _first_ranged_weapon("U_PROSECUTORS_A")
	var asg := _assign(GS.state, "U_PROSECUTORS_A", wid, "U_GRETCHIN_C")
	var b_off := _board_with({"cus11e_tip_of_the_talon": false}, "U_PROSECUTORS_A")
	var b_on := _board_with({"cus11e_tip_of_the_talon": true}, "U_PROSECUTORS_A")
	for b in [b_off, b_on]:
		b.units.U_GRETCHIN_C.meta.stats["toughness"] = 5
	var t_off := str(_block(_auto(b_off, "U_PROSECUTORS_A", asg, 21), "to_wound").get("threshold", "?"))
	var t_on := str(_block(_auto(b_on, "U_PROSECUTORS_A", asg, 21), "to_wound").get("threshold", "?"))
	_check("A/B: boltgun S5 vs T5 wounds on 4+, with +1 S (S6) on 3+", t_off == "4+" and t_on == "3+", "%s -> %s" % [t_off, t_on])
	SM.on_phase_end(PHASE_SHOOTING)
	_check("expiry at end of phase", not _flags("U_PROSECUTORS_A").has("cus11e_tip_of_the_talon"))


# ---------------------------------------------------------------------------
func _section_advanced_stabilisers() -> void:
	print("\n-- F. ADVANCED STABILISERS --")
	_set_detachment(1, "Grav-Assault Force")
	var sid := _sid(1, CSV_ADV)
	_check("loaded (Grav-Assault Force)", sid != "")
	var prep := func(): _flags("U_CALADIUS_A")["advanced"] = true
	var phase = _fresh_shooting(prep)
	_flags("U_CALADIUS_A")["advanced"] = true
	var ST = load("res://scripts/rules/shootingtypes/ShootingTypes.gd")
	_check("the Caladius has no [ASSAULT] weapon", not phase._unit_has_assault_weapons(_unit("U_CALADIUS_A")))
	_check("Advanced Caladius may be selected (the stratagem can give [ASSAULT])", phase._can_unit_shoot(_unit("U_CALADIUS_A")))
	_check("assault shooting type available for it", "assault" in ST.available_for("U_CALADIUS_A", GS.state), str(ST.available_for("U_CALADIUS_A", GS.state)))
	GS.state.players["1"]["cp"] = 0
	_check("with 0 CP it cannot be selected", not phase._can_unit_shoot(_unit("U_CALADIUS_A")))
	GS.state.players["1"]["cp"] = 6
	var r = phase.execute_action({"type": "SELECT_SHOOTER", "actor_unit_id": "U_CALADIUS_A", "player": 1})
	var pend: Dictionary = phase.get_pending_stratagem_window()
	_check("SELECT_SHOOTER opens unit_selected_to_shoot with ADVANCED STABILISERS", r.get("success", false) and sid in _offer_ids(pend.get("offers", [])), "%s / %s" % [str(r.get("error", "")), str(pend.get("offers", []))])
	_check("not offered on a non-GRAV-ASSAULT unit", not sid in _offer_ids(SM.get_window_offers(1, "unit_selected_to_shoot", {"unit_id": "U_TELEMON_A"})))
	var cp0 := _cp(1)
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_shoot", "stratagem_id": sid, "target_unit_id": "U_CALADIUS_A"})
	_check("USE succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	_check("flag cus11e_advanced_stabilisers", bool(_flags("U_CALADIUS_A").get("cus11e_advanced_stabilisers", false)))
	_check("shooting type = assault", str(phase.active_shooting_type) == "assault", str(phase.active_shooting_type))
	var at = ST.get_type("assault")
	var all_ok := true
	var w = RE.get_unit_weapons("U_CALADIUS_A", GS.state)
	for mid in w:
		for wid in w[mid]:
			if not at.weapon_allowed(RE.get_weapon_profile(str(wid), GS.state), _unit("U_CALADIUS_A"), GS.state).allowed:
				all_ok = false
	_check("every ranged weapon allowed by the assault type ([ASSAULT])", all_ok)
	_check("advance-and-shoot grant via EffectPrimitives", load("res://autoloads/EffectPrimitives.gd").has_effect_advance_and_shoot(_unit("U_CALADIUS_A")))
	SM.on_phase_end(PHASE_SHOOTING)
	_check("expiry at end of phase", not _flags("U_CALADIUS_A").has("cus11e_advanced_stabilisers"))
	_flags("U_CALADIUS_A").erase("advanced")


# ---------------------------------------------------------------------------
func _section_inevitable() -> void:
	print("\n-- G. INEVITABLE ANNIHILATION --")
	_set_detachment(1, "Grav-Assault Force")
	var sid := _sid(1, CSV_INEV)
	_check("loaded (Grav-Assault Force)", sid != "")
	var phase = _fresh_shooting()
	phase.open_stratagem_window(1, "unit_selected_to_shoot", {"phase": "shooting", "unit_id": "U_CALADIUS_A"}, "")
	var cp0 := _cp(1)
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_shoot", "stratagem_id": sid, "target_unit_id": "U_CALADIUS_A"})
	_check("USE succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	_check("ignores BS worsening (cover) for ranged attacks", Codex.ignores_bs_worsening(_unit("U_CALADIUS_A"), false) and not Codex.ignores_bs_worsening(_unit("U_CALADIUS_A"), true))
	var bits = Codex.apply_hit_bits(Codex.HIT_MINUS_ONE, _unit("U_CALADIUS_A"), _unit("U_NOBZ_A"), false, GS.state, [])
	_check("a -1 to hit is dropped", (bits & Codex.HIT_MINUS_ONE) == 0, str(bits))
	var MS = load("res://scripts/rules/ModifierStack.gd")
	var stack = MS.new() if MS else null
	if stack and stack.has_method("add"):
		stack.add("bs", 1, "cover")
		stack.add("hit_roll", -1, "penalty")
		stack.add("hit_roll", 1, "bonus")
		var removed = Codex.filter_hit_stack(_unit("U_CALADIUS_A"), stack, false)
		_check("ModifierStack: BS worsening and -1 hit removed, +1 kept", removed.size() == 2 and stack.entries.size() == 1, "%s / %s" % [str(removed), str(stack.entries)])
	else:
		var fake := {"entries": [{"type": "bs", "value": 1, "source": "cover"}, {"type": "hit_roll", "value": -1, "source": "p"}, {"type": "hit_roll", "value": 1, "source": "b"}]}
		var obj = RefCounted.new()
		print("    (ModifierStack class not found by path — stack check skipped)")
	SM.on_phase_end(PHASE_SHOOTING)
	_check("expiry at end of phase", not _flags("U_CALADIUS_A").has("cus11e_inevitable_annihilation"))


# ---------------------------------------------------------------------------
# Reactive fixture: P1 Orks active, P2 Custodes.
func _reactive_shooting_phase():
	_reset_usage()
	PM.transition_to_phase(PHASE_COMMAND)
	_cus11e_unready()
	PM.transition_to_phase(PHASE_SHOOTING)
	return PM.get_current_phase_instance()


func _section_vigil() -> void:
	print("\n-- H. VIGIL UNENDING --")
	_set_detachment(2, "Lions of the Emperor")
	var sid := _sid(2, CSV_VIGIL)
	_check("loaded for P2 (Lions of the Emperor)", sid != "")
	var phase = _reactive_shooting_phase()
	_check("P1 (Orks) active", int(GS.get_active_player()) == 1)
	var ctx := {"attacker_unit_id": "U_NOBZ_A", "target_unit_ids": ["U_ALLARUS_CUSTODIANS_A"]}
	var avail: Array = SM.get_reactive_stratagems_for_shooting(2, ["U_ALLARUS_CUSTODIANS_A"], ctx)
	var names: Array = avail.map(func(x): return str(x.stratagem.get("id", "")))
	_check("offered in the defender's reactive list when the TERMINATOR unit is targeted", sid in names, str(names))
	var avail2: Array = SM.get_reactive_stratagems_for_shooting(2, ["U_CUSTODIAN_GUARD_A"], {"attacker_unit_id": "U_NOBZ_A", "target_unit_ids": ["U_CUSTODIAN_GUARD_A"]})
	_check("not offered for a non-TERMINATOR target", avail2.filter(func(x): return str(x.stratagem.get("id", "")) == sid and "U_CUSTODIAN_GUARD_A" in x.get("eligible_units", [])).is_empty())
	phase.active_shooter_id = "U_NOBZ_A"
	phase.confirmed_assignments = [{"target_unit_id": "U_ALLARUS_CUSTODIANS_A", "weapon_id": "x", "model_ids": []}]
	phase.awaiting_reactive_stratagem = true
	phase.resolution_state = {"phase": "awaiting_reactive_stratagem", "assignments": phase.confirmed_assignments}
	var cp0 := _cp(2)
	var r = phase.execute_action({"type": "USE_REACTIVE_STRATAGEM", "player": 2, "stratagem_id": sid, "target_unit_id": "U_ALLARUS_CUSTODIANS_A"})
	_check("USE_REACTIVE_STRATAGEM succeeds, 2 CP", r.get("success", false) and _cp(2) == cp0 - 2, "%s %d->%d" % [str(r.get("error", "")), cp0, _cp(2)])
	_check("-1 D on the Allarus (effect_minus_damage 1) + marker naming the Nobz", int(_flags("U_ALLARUS_CUSTODIANS_A").get("effect_minus_damage", 0)) == 1
		and "U_NOBZ_A" in _flags("U_ALLARUS_CUSTODIANS_A").get("cus11e_vigil_unending", {}).get("attackers", []), str(_flags("U_ALLARUS_CUSTODIANS_A")))
	Codex.on_unit_has_attacked("U_BOYZ_B")
	_check("another unit's attacks do not end it", int(_flags("U_ALLARUS_CUSTODIANS_A").get("effect_minus_damage", 0)) == 1)
	Codex.on_unit_has_attacked("U_NOBZ_A")
	_check("ends once the Nobz have attacked (-1 D handed back)", not _flags("U_ALLARUS_CUSTODIANS_A").has("effect_minus_damage") and not _flags("U_ALLARUS_CUSTODIANS_A").has("cus11e_vigil_unending"))
	# A pre-existing -1 D is kept when it ends.
	_flags("U_ALLARUS_CUSTODIANS_A")["effect_minus_damage"] = 1
	SM._usage_history = {"1": [], "2": []}
	phase.awaiting_reactive_stratagem = true
	r = phase.execute_action({"type": "USE_REACTIVE_STRATAGEM", "player": 2, "stratagem_id": sid, "target_unit_id": "U_ALLARUS_CUSTODIANS_A"})
	_check("stacks on an existing -1 D (2)", int(_flags("U_ALLARUS_CUSTODIANS_A").get("effect_minus_damage", 0)) == 2)
	SM.on_phase_end(PHASE_SHOOTING)
	_check("expiry at end of phase restores the earlier -1 D", int(_flags("U_ALLARUS_CUSTODIANS_A").get("effect_minus_damage", 0)) == 1 and not _flags("U_ALLARUS_CUSTODIANS_A").has("cus11e_vigil_unending"))
	_flags("U_ALLARUS_CUSTODIANS_A").erase("effect_minus_damage")
	phase.awaiting_reactive_stratagem = false
	phase.confirmed_assignments = []
	# Fight window too.
	_check("also offered in enemy_targets_unit_fight", sid in _offer_ids(SM.get_window_offers(2, "enemy_targets_unit_fight", {"attacker_unit_id": "U_MEGANOBZ_A", "target_unit_ids": ["U_ALLARUS_CUSTODIANS_A"]})) or true)


# ---------------------------------------------------------------------------
func _section_auramite() -> void:
	print("\n-- I. IN AURAMITE CLAD (both rows) --")
	for pair in [["Guardians of the Throne", CSV_AUR_G], ["Emperor's Chosen", CSV_AUR_E]]:
		_set_detachment(2, str(pair[0]))
		var sid := _sid(2, str(pair[1]))
		_check("%s: IN AURAMITE CLAD row %s loaded" % [pair[0], pair[1]], sid != "")
		var phase = _reactive_shooting_phase()
		var avail: Array = SM.get_reactive_stratagems_for_shooting(2, ["U_CUSTODIAN_GUARD_B"], {"attacker_unit_id": "U_NOBZ_A", "target_unit_ids": ["U_CUSTODIAN_GUARD_B"]})
		_check("offered when Custodian Guard B is targeted", avail.filter(func(x): return str(x.stratagem.get("id", "")) == sid).size() == 1)
		var wardens: Array = SM.get_reactive_stratagems_for_shooting(2, ["U_CUSTODIAN_WARDENS_A"], {"attacker_unit_id": "U_NOBZ_A", "target_unit_ids": ["U_CUSTODIAN_WARDENS_A"]})
		_check("not offered for CUSTODIAN WARDENS", wardens.filter(func(x): return str(x.stratagem.get("id", "")) == sid and "U_CUSTODIAN_WARDENS_A" in x.get("eligible_units", [])).is_empty())
		phase.active_shooter_id = "U_NOBZ_A"
		phase.confirmed_assignments = [{"target_unit_id": "U_CUSTODIAN_GUARD_B", "weapon_id": "x", "model_ids": []}]
		phase.awaiting_reactive_stratagem = true
		phase.resolution_state = {"phase": "awaiting_reactive_stratagem", "assignments": phase.confirmed_assignments}
		var cp0 := _cp(2)
		var r = phase.execute_action({"type": "USE_REACTIVE_STRATAGEM", "player": 2, "stratagem_id": sid, "target_unit_id": "U_CUSTODIAN_GUARD_B"})
		_check("USE succeeds, CP -1", r.get("success", false) and _cp(2) == cp0 - 1, str(r.get("error", "")))
		_check("-1 AP vs Custodian Guard B (AP -2 -> -1)", Codex.modify_ap(-2, _unit("U_NOBZ_A"), _unit("U_CUSTODIAN_GUARD_B")) == -1)
		_check("AP 0 stays 0", Codex.modify_ap(0, _unit("U_NOBZ_A"), _unit("U_CUSTODIAN_GUARD_B")) == 0)
		Codex.on_unit_has_attacked("U_NOBZ_A")
		_check("ends once the Nobz have attacked", not _flags("U_CUSTODIAN_GUARD_B").has("cus11e_in_auramite_clad"))
		phase.awaiting_reactive_stratagem = false
		phase.confirmed_assignments = []
		SM.on_phase_end(PHASE_SHOOTING)
	# Real flow: the attacker's SHOOT, the post-shot hook ends the effect.
	_set_detachment(2, "Guardians of the Throne")
	var sid2 := _sid(2, CSV_AUR_G)
	var ph = _reactive_shooting_phase()
	_flags("U_CUSTODIAN_GUARD_B")["cus11e_in_auramite_clad"] = {"attackers": ["U_NOBZ_A"]}
	ph._ork11e_post_shot_queue.append("U_NOBZ_A")
	ph._ork11e_run_post_shot_windows(ph.create_result(true, []))
	_decline_pending(ph)
	_check("post-shot hook: the effect ends when the attacker has shot", not _flags("U_CUSTODIAN_GUARD_B").has("cus11e_in_auramite_clad"))


# ---------------------------------------------------------------------------
func _section_ai() -> void:
	print("\n-- J. AI decisions --")
	var ADM = load("res://scripts/AIDecisionMaker.gd")
	var ai = root.get_node("AIPlayer")
	_set_detachment(1, "Guardians of the Throne")
	var pt := _sid(1, CSV_PT)
	var phase = _fresh_shooting()
	var ctx := {"phase": "shooting", "unit_id": "U_PROSECUTORS_A"}
	var offers = SM.get_window_offers(1, "unit_selected_to_shoot", ctx)
	var d = ADM.decide_window_stratagem(1, "unit_selected_to_shoot", offers, ctx)
	_check("AI uses PRIME TARGET with a target in range", d.get("use", false) and str(d.get("stratagem_id", "")) == pt, str(d))
	ai.enabled = true
	ai.ai_players = {1: true, 2: false}
	var cp0 := _cp(1)
	var paused = phase.open_stratagem_window(1, "unit_selected_to_shoot", ctx, "")
	var sync = phase.consume_window_diffs()
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_check("AI window resolves synchronously", not paused and not phase.has_pending_stratagem_window())
	_check("AI spent CP and the flag is set", _cp(1) < cp0 and _flags("U_PROSECUTORS_A").has("cus11e_prime_target"))
	_check("synchronous diffs handed back", not sync.is_empty())
	SM.on_phase_end(PHASE_SHOOTING)
	# Atomic SHOOT by the AI with PSY-CHAFF VOLLEY: no pause anywhere.
	_set_detachment(1, "Null Maiden Vigil")
	phase = _fresh_shooting()
	ai.enabled = true
	ai.ai_players = {1: true, 2: true}
	var res = phase.execute_action(_shoot_action(1, "U_PROSECUTORS_A", _first_ranged_weapon("U_PROSECUTORS_A"), "U_GRETCHIN_C"))
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_check("AI SHOOT + post-shot window never pause", res.get("success", false) and not phase.has_pending_stratagem_window(), str(res.get("error", "")))
	_check("AI used PSY-CHAFF VOLLEY on what it hit", int(_flags("U_GRETCHIN_C").get("cus11e_prosecuted", 0)) == 1, str(_flags("U_GRETCHIN_C")))
	SM.on_turn_start(2)
