extends SceneTree

# Codex: Adeptus Custodes (11e) ARMY RULES — WP-C3 (CustodesKatah.gd).
# Contract: .llm/codex_11e_wahapedia/IMPLEMENTATION.md; rules text:
# .llm/codex_11e_wahapedia/custodes/RULES.md. Against the real fixture
# tests/saves/cus11e_c3_custodes_active.w40ksave (P1 Custodes ACTIVE, Command
# phase of battle round 2, P1 took the first turn; P2 Orks):
#   A. readied step — P1's units with Martial Ka'tah readied at the start of
#      THEIR Command phase, never the opponent's; reserves included
#   B. each ka'tah offered only in its window, only in its phase / turn, only
#      while readied (and the 6" start-of-Fight filter)
#   C. one use un-readies the (Attached) unit; a second ka'tah is refused;
#      the window stays open for what is still offered; stratagem + ka'tah order
#   D. effects A/B with the same seeds: CALISTUS (real Movement-phase moves
#      through a VEHICLE), SALVUS (cover BS worsening, -1 hit, -1 wound),
#      DACATARAI (re-roll 1s vs non-M/V only), KAPTARIS (-1 to hit),
#      RENDAX ([LETHAL HITS] vs M/V only), CONSERVAI (actions)
#   E. expiry — phase-scoped ka'tahs at phase end, Conservai at the next
#      Command phase; readied persists into the opponent's turn
#   F. Master of Ka'tahs — re-readies once per battle round, per unit
#   G. Aegis of the Emperor — FNP 5+ on several mortal-wound paths, never
#      stacked (best FNP wins), not vs normal damage
#   H. Aquila Commander — +1CP at the start of the battle round only when the
#      WARLORD has it; once per round; NOT limited by the 10e bonus-CP cap
#      (11e has none — same ruling as Da Boss)
#   I. Daughters of the Abyss 3+ / Psychic Null aura 5+ — psychic attacks only
#   J. Anathema Psykana — no ANATHEMA PSYKANA WARLORD (validation + Formations)
#   K. AI ka'tah choices — synchronous, never stall a window
#   L. Favoured Ka'tah API stub + old 10e stance system gone
#
# Usage: godot --headless --path 40k --script tests/test_custodes_army_rules_11e.gd

const FIXTURE := "cus11e_c3_custodes_active"
const PHASE_COMMAND := 6
const PHASE_MOVEMENT := 7
const PHASE_SHOOTING := 8
const PHASE_CHARGE := 9
const PHASE_FIGHT := 10
const PX := 40.0

const CG := "U_CUSTODIAN_GUARD_B"
const SC := "U_SHIELD_CAPTAIN_A"
const BC := "U_BLADE_CHAMPION_A"
const CONT := "U_CONTEMPTOR-ACHILLUS_DREADNOUGHT_H"
const WS_C := "U_WITCHSEEKERS_C"
const WS_D := "U_WITCHSEEKERS_D"
const TELEMON := "U_TELEMON_HEAVY_DREADNOUGHT_I"
const CALADIUS := "U_CALADIUS_GRAV-TANK_E"
const JETBIKE := "U_SHIELD_CAPTAIN_JETBIKE_A"
const BOYZ := "U_BOYZ_B"
const DREAD := "U_DEFF_DREAD_A"
const MEGA := "U_MEGANOBZ_A"
const GRETS := "U_GRETCHIN_C"

var passed := 0
var failed := 0
var SM = null
var GS = null
var PM = null
var RE = null
var K = null
var _base: Dictionary = {}
var _phase_done := false


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


func _unit(uid: String) -> Dictionary:
	return GS.state.units.get(uid, {})


func _flags(uid: String) -> Dictionary:
	var u = _unit(uid)
	if not u.has("flags"):
		u["flags"] = {}
	return u.flags


func _cp(p: int) -> int:
	return int(GS.state.players[str(p)].cp)


func _pos(m: Dictionary) -> Vector2:
	var p = m.get("position")
	if p is Dictionary:
		return Vector2(float(p.x), float(p.y))
	return p


func _remember() -> void:
	for uid in GS.state.units:
		var arr: Array = []
		for m in GS.state.units[uid].models:
			arr.append(m.get("position").duplicate() if m.get("position") is Dictionary else m.get("position"))
		_base[uid] = arr


## Positions, wounds, flags back to the fixture; `readied` re-readies P1.
func _restore(readied: bool = true) -> void:
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		var arr: Array = _base.get(uid, [])
		for i in range(u.models.size()):
			if i < arr.size():
				u.models[i]["position"] = arr[i].duplicate() if arr[i] is Dictionary else arr[i]
			u.models[i]["alive"] = true
			u.models[i]["current_wounds"] = u.models[i].get("wounds", 1)
		u["flags"] = {}
		u["status"] = GS.UnitStatus.DEPLOYED
		if readied and int(u.get("owner", 0)) == 1 and K.has_martial_katah(u):
			u.flags[K.FLAG_READIED] = true
	GS.state.meta["active_player"] = 1
	GS.state.meta["battle_round"] = 2


func _no_phase_advance(phase) -> void:
	_phase_done = false
	if phase.phase_completed.is_connected(PM._on_phase_completed):
		phase.phase_completed.disconnect(PM._on_phase_completed)
	phase.phase_completed.connect(func(): _phase_done = true)


## Enter `phase_id` directly (fresh phase instance), keeping the board.
func _enter(phase_id: int):
	PM.transition_to_phase(phase_id)
	var phase = PM.get_current_phase_instance()
	_no_phase_advance(phase)
	return phase


func _offer_ids(offers: Array) -> Array:
	return offers.map(func(o): return str(o.get("stratagem_id", "")))


func _targets(offers: Array, sid: String) -> Array:
	for o in offers:
		if str(o.get("stratagem_id", "")) == sid:
			return o.get("targets", []).map(func(t): return str(t.get("unit_id", "")))
	return []


func _target(offers: Array, sid: String, uid: String) -> Dictionary:
	for o in offers:
		if str(o.get("stratagem_id", "")) != sid:
			continue
		for t in o.get("targets", []):
			if str(t.get("unit_id", "")) == uid:
				return t
	return {}


func _use(phase, player: int, window_id: String, sid: String, uid: String, ctx: Dictionary = {}) -> Dictionary:
	return phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": player, "window_id": window_id,
		"stratagem_id": sid, "target_unit_id": uid, "context": ctx})


func _decline(phase, player: int, window_id: String) -> Dictionary:
	return phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": player, "window_id": window_id})


func _pending_window(phase) -> String:
	return str(phase.get_pending_stratagem_window().get("window_id", "")) if phase.has_pending_stratagem_window() else ""


func _pending_offers(phase) -> Array:
	return phase.get_pending_stratagem_window().get("offers", []) if phase.has_pending_stratagem_window() else []


func _block(res: Dictionary, ctx_name: String) -> Dictionary:
	for d in res.get("dice", []):
		if str(d.get("context", "")) == ctx_name:
			return d
	return {}


func _ledger_has(block: Dictionary, source: String) -> bool:
	for e in block.get("modifier_ledger", []):
		if str(e.get("source", "")).find(source) >= 0:
			return true
	return false


func _ranged_weapon(uid: String) -> String:
	var w = RE.get_unit_weapons(uid, GS.state)
	for mid in w:
		for wid in w[mid]:
			var prof = RE.get_weapon_profile(str(wid), GS.state)
			if str(prof.get("type", "")).to_lower() != "melee" and str(prof.get("range", "melee")).to_lower() != "melee":
				return str(wid)
	return ""


func _assign(board: Dictionary, uid: String, wid: String, tid: String) -> Dictionary:
	var model_ids: Array = []
	var w = RE.get_unit_weapons(uid, board)
	for mid in w:
		if wid in w[mid]:
			model_ids.append(str(mid))
	return {"weapon_id": wid, "target_unit_id": tid, "model_ids": model_ids}


func _shoot(board: Dictionary, uid: String, wid: String, tid: String, seed_val: int) -> Dictionary:
	return RE.resolve_shoot({"type": "SHOOT", "actor_unit_id": uid, "payload": {"assignments": [_assign(board, uid, wid, tid)]}}, board, RE.RNGService.new(seed_val))


## Synthetic melee board (attacker vs target), like test_ork_codex_fight.gd.
func _melee_board(atk_flags: Dictionary, tgt_flags: Dictionary, tgt_kw: Array, rules: String, n_att: int = 5) -> Dictionary:
	var atk: Array = []
	for i in range(n_att):
		atk.append({"id": "ma%d" % i, "position": {"x": 10.0, "y": 10.0 + i * 30}, "base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 3, "current_wounds": 3})
	var tgt: Array = []
	for i in range(5):
		tgt.append({"id": "mt%d" % i, "position": {"x": 30.0, "y": 10.0 + i * 30}, "base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 30, "current_wounds": 30})
	var weapon := {"name": "Test Spear", "type": "Melee", "range": "Melee", "attacks": "6", "weapon_skill": "3",
		"strength": "6", "ap": "-1", "damage": "1", "special_rules": rules}
	return {"units": {
		"U_ATK": {"id": "U_ATK", "owner": 1,
			"meta": {"name": "Custodians", "keywords": ["ADEPTUS CUSTODES", "INFANTRY"], "stats": {"toughness": 6, "save": 2, "wounds": 3},
				"abilities": [], "weapons": [weapon]},
			"flags": atk_flags, "models": atk},
		"U_TGT": {"id": "U_TGT", "owner": 2,
			"meta": {"name": "Targets", "keywords": tgt_kw, "stats": {"toughness": 5, "save": 6, "wounds": 30}, "abilities": []},
			"flags": tgt_flags, "models": tgt},
	}, "meta": {"phase": 10, "active_player": 1, "battle_round": 2}}


func _melee(board: Dictionary, seed_val: int) -> Dictionary:
	RE.set_test_seed(seed_val)
	return RE.resolve_melee_attacks({"type": "FIGHT", "actor_unit_id": "U_ATK",
		"payload": {"assignments": [{"attacker": "U_ATK", "target": "U_TGT", "weapon": "Test Spear"}]}}, board, RE.RNGService.new(seed_val))


# ---------------------------------------------------------------------------
func _run() -> void:
	SM = root.get_node("StratagemManager")
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	K = load("res://scripts/codex/custodes/CustodesKatah.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	GS.set_edition(11)

	print("\n=== test_custodes_army_rules_11e ===\n")
	_check("fixture %s loads" % FIXTURE, _stage_fixture())
	GS.set_edition(11)
	root.get_node("SettingsService").set("auto_allocate_wounds", true)
	# The fixture sits in P1's Command phase of battle round 2 (P1 first):
	# entering it runs the start of the battle round and P1's readied step,
	# exactly what the game does when it loads the save.
	_enter(PHASE_COMMAND)
	_remember()

	_section_readied_step()
	_section_aquila_commander()
	_section_offers()
	_section_one_use_and_window()
	_section_calistus_move()
	_section_salvus()
	_section_melee_katahs()
	_section_conservai()
	_section_expiry()
	_section_master_of_katahs()
	_section_aegis()
	_section_daughters()
	_section_anathema_psykana()
	_section_ai()
	_section_api_and_cleanup()


# ---------------------------------------------------------------------------
func _section_readied_step() -> void:
	print("\n-- A. readied step --")
	var p1_katah := 0
	var p1_readied := 0
	for uid in GS.state.units:
		var u = GS.state.units[uid]
		if int(u.owner) == 1 and K.has_martial_katah(u):
			p1_katah += 1
			if bool(u.flags.get(K.FLAG_READIED, false)):
				p1_readied += 1
		if int(u.owner) == 2:
			_check("opponent's %s is NOT readied by P1's Command phase" % uid, not bool(u.get("flags", {}).get(K.FLAG_READIED, false)))
	_check("every P1 unit with Martial Ka'tah is readied at the start of P1's Command phase (%d/%d)" % [p1_readied, p1_katah], p1_katah == 9 and p1_readied == p1_katah)
	_check("readied marker = K.is_readied for the Custodian Guard", K.is_readied(CG))
	# Re-run the step for P2 (their Command phase): Orks have no Martial Ka'tah.
	_flags(CG)[K.FLAG_READIED] = false
	K.on_command_phase_start(2)
	_check("P2's readied step does not ready P1's units", not bool(_flags(CG).get(K.FLAG_READIED, false)))
	var any_ork := false
	for uid in GS.state.units:
		if int(GS.state.units[uid].owner) == 2 and bool(GS.state.units[uid].get("flags", {}).get(K.FLAG_READIED, false)):
			any_ork = true
	_check("no Ork unit is ever readied", not any_ork)
	# Ruling: units in reserves are readied too.
	_unit(JETBIKE)["status"] = GS.UnitStatus.IN_RESERVES
	_flags(JETBIKE)[K.FLAG_READIED] = false
	K.on_command_phase_start(1)
	_check("a unit in Strategic Reserves is readied as well (ruling)", bool(_flags(JETBIKE).get(K.FLAG_READIED, false)))
	_check("P1's readied step readies the Custodian Guard again", bool(_flags(CG).get(K.FLAG_READIED, false)))
	_unit(JETBIKE)["status"] = GS.UnitStatus.DEPLOYED


# ---------------------------------------------------------------------------
func _section_aquila_commander() -> void:
	print("\n-- H. Aquila Commander --")
	# Fixture load = start of battle round 2 (P1 first): 6 + 1 (Command phase) + 1 (Aquila).
	_check("P1 (WARLORD Shield-Captain, Aquila Commander) has 8 CP after the round-2 start", _cp(1) == 8, str(_cp(1)))
	_check("P2 (WARLORD Warboss, no Aquila Commander) has 7 CP", _cp(2) == 7, str(_cp(2)))
	_check("the CP is not counted against the 10e bonus-CP cap", GS.get_bonus_cp_gained_this_round(1) == 0 and GS.get_bonus_cp_gained_this_round(2) == 0)
	_check("warlord carries the per-round markers", int(_flags(SC).get(K.FLAG_AQUILA_ROUND, -1)) == 2 and int(_flags(SC).get(K.FLAG_AQUILA_CP_ROUND, -1)) == 2)
	K.on_battle_round_start(2)
	_check("once per battle round: re-resolving round 2 adds nothing", _cp(1) == 8, str(_cp(1)))
	# Round 3 through the real Command phase (P1 first again).
	GS.state.meta["battle_round"] = 3
	GS.state.players["1"]["cp"] = 2
	GS.state.players["2"]["cp"] = 2
	var phase = _enter(PHASE_COMMAND)
	_check("round 3 Command phase: P1 +1 (phase) +1 (Aquila) = 4", _cp(1) == 4, str(_cp(1)))
	_check("round 3: P2 +1 only", _cp(2) == 3, str(_cp(2)))
	# No 11e cap: a player who already gained bonus CP this round still gains it.
	GS.state.meta["battle_round"] = 4
	GS.reset_bonus_cp_tracking()
	GS.record_bonus_cp_gained(1, 1)
	var before := _cp(1)
	K.on_battle_round_start(4)
	_check("other bonus CP this round: Aquila Commander still gains its 1CP (no 11e cap)", _cp(1) == before + 1, "%d -> %d" % [before, _cp(1)])
	# Only when the WARLORD has it.
	GS.state.meta["battle_round"] = 5
	GS.reset_bonus_cp_tracking()
	GS.state.units[SC].meta["is_warlord"] = false
	GS.state.units[BC].meta["is_warlord"] = true
	before = _cp(1)
	K.on_battle_round_start(5)
	_check("Blade Champion WARLORD (no Aquila Commander): no CP", _cp(1) == before)
	GS.state.units[SC].meta["is_warlord"] = true
	GS.state.units[BC].meta["is_warlord"] = false
	# A destroyed WARLORD gains nothing.
	GS.state.meta["battle_round"] = 6
	GS.reset_bonus_cp_tracking()
	for m in GS.state.units[SC].models:
		m["alive"] = false
	before = _cp(1)
	K.on_battle_round_start(6)
	_check("destroyed WARLORD: no CP (ruling)", _cp(1) == before)
	if phase:
		pass
	_restore()
	GS.reset_bonus_cp_tracking()
	GS.state.players["1"]["cp"] = 6
	GS.state.players["2"]["cp"] = 6


# ---------------------------------------------------------------------------
func _section_offers() -> void:
	print("\n-- B. offers: right window, right phase / turn, readied only --")
	var ids := {}
	for kid in K.KATAH_ORDER:
		ids[kid] = K.offer_id(kid)
	# Command phase
	var phase = _enter(PHASE_COMMAND)
	_restore()
	var cpm = K.window_offers(1, "command_phase_main", {"phase": "command"})
	_check("command_phase_main: only CONSERVAI is offered", _offer_ids(cpm) == [ids.conservai], str(_offer_ids(cpm)))
	var cons_t := _targets(cpm, ids.conservai)
	_check("CONSERVAI targets every readied P1 unit on the battlefield (9)", cons_t.size() == 9, str(cons_t))
	_check("P2 gets no ka'tah in command_phase_main", K.window_offers(2, "command_phase_main", {}).is_empty())
	_check("not in unit_selected_to_move during the Command phase", K.window_offers(1, "unit_selected_to_move", {"unit_id": WS_C, "move_type": "normal"}).is_empty())
	# The phase opens command_phase_main before the battle-shock step window.
	var r = phase.execute_action({"type": "BEGIN_BATTLE_SHOCK_STEP", "player": 1})
	_check("BEGIN_BATTLE_SHOCK_STEP opens command_phase_main (P1 human)", r.get("success", false) and _pending_window(phase) == "command_phase_main", _pending_window(phase))
	_check("the pending window carries the CONSERVAI card", ids.conservai in _offer_ids(_pending_offers(phase)))
	_decline(phase, 1, "command_phase_main")
	# WP-O34: the Orks (P2) are then offered WAR CRY ("at the start of the Command
	# phase" — either player's; after the active player's window). Not under test here.
	if phase.has_pending_stratagem_window() and _pending_window(phase) == "ork11e_war_cry":
		_decline(phase, 2, "ork11e_war_cry")
	_check("declined: no window left (no battle_shock_step_start offers)", not phase.has_pending_stratagem_window())

	# Movement phase
	phase = _enter(PHASE_MOVEMENT)
	_restore()
	var mv = K.window_offers(1, "unit_selected_to_move", {"unit_id": WS_C, "move_type": "normal"})
	_check("unit_selected_to_move (normal): CALISTUS for the selected unit", _offer_ids(mv) == [ids.calistus] and _targets(mv, ids.calistus) == [WS_C], str(mv))
	for mt in ["advance", "fall_back"]:
		_check("CALISTUS also offered for a %s move" % mt, ids.calistus in _offer_ids(K.window_offers(1, "unit_selected_to_move", {"unit_id": WS_C, "move_type": mt})))
	_check("not for other move types (remain stationary)", K.window_offers(1, "unit_selected_to_move", {"unit_id": WS_C, "move_type": "remain_stationary"}).is_empty())
	_check("not for an Ork unit", K.window_offers(2, "unit_selected_to_move", {"unit_id": BOYZ, "move_type": "normal"}).is_empty())
	_check("not in unit_selected_to_shoot during the Movement phase", K.window_offers(1, "unit_selected_to_shoot", {"unit_id": WS_C}).is_empty())
	GS.state.meta["active_player"] = 2
	_check("CALISTUS is 'your Movement phase' only (opponent's turn: none)", K.window_offers(1, "unit_selected_to_move", {"unit_id": WS_C, "move_type": "normal"}).is_empty())
	GS.state.meta["active_player"] = 1
	_flags(WS_C)[K.FLAG_READIED] = false
	_check("not readied (and no Master of Ka'tahs): not offered", K.window_offers(1, "unit_selected_to_move", {"unit_id": WS_C, "move_type": "normal"}).is_empty())
	_flags(WS_C)[K.FLAG_READIED] = true

	# Shooting phase
	phase = _enter(PHASE_SHOOTING)
	_restore()
	var sh = K.window_offers(1, "unit_selected_to_shoot", {"unit_id": CALADIUS})
	_check("unit_selected_to_shoot: SALVUS for the selected unit", _offer_ids(sh) == [ids.salvus] and _targets(sh, ids.salvus) == [CALADIUS], str(sh))
	GS.state.meta["active_player"] = 2
	_check("SALVUS is 'your Shooting phase' only", K.window_offers(1, "unit_selected_to_shoot", {"unit_id": CALADIUS}).is_empty())
	GS.state.meta["active_player"] = 1

	# Fight phase
	phase = _enter(PHASE_FIGHT)
	_restore()
	var fs = K.window_offers(1, "fight_phase_start", {"phase": "fight"})
	_check("fight_phase_start: DACATARAI and KAPTARIS", _offer_ids(fs) == [ids.dacatarai, ids.kaptaris], str(_offer_ids(fs)))
	var fs_t := _targets(fs, ids.dacatarai)
	for want in [CG, SC, BC, CONT, WS_D]:
		_check("fight_phase_start offers %s (within 6\" of an enemy)" % want, want in fs_t, str(fs_t))
	for not_want in [CALADIUS, JETBIKE, TELEMON, WS_C]:
		_check("fight_phase_start does not offer %s (> 6\" from every enemy)" % not_want, not not_want in fs_t)
	GS.state.meta["active_player"] = 2
	_check("Dacatarai / Kaptaris also in the OPPONENT's Fight phase", _targets(K.window_offers(1, "fight_phase_start", {}), ids.kaptaris).size() == fs_t.size())
	GS.state.meta["active_player"] = 1
	var rf = K.window_offers(1, "unit_selected_to_fight", {"unit_id": BC})
	_check("unit_selected_to_fight: RENDAX for the fighter", _offer_ids(rf) == [ids.rendax] and _targets(rf, ids.rendax) == [BC], str(rf))
	GS.state.meta["active_player"] = 2
	_check("RENDAX in the opponent's Fight phase too", ids.rendax in _offer_ids(K.window_offers(1, "unit_selected_to_fight", {"unit_id": BC})))
	GS.state.meta["active_player"] = 1
	_check("no ka'tah in fight_phase_end", K.window_offers(1, "fight_phase_end", {}).is_empty())
	_check("cards are free: cp_cost 0, kind katah", int(fs[0].get("cp_cost", -1)) == 0 and str(fs[0].get("kind", "")) == "katah")


# ---------------------------------------------------------------------------
func _section_one_use_and_window() -> void:
	print("\n-- C. one use un-readies; a second is refused; the window stays open --")
	_restore()
	var phase = _enter(PHASE_FIGHT)
	_restore()
	phase = _enter(PHASE_FIGHT)
	_check("Fight phase entry pauses on P1's fight_phase_start (human)", _pending_window(phase) == "fight_phase_start" and int(phase.get_pending_stratagem_window_decider()) == 1, _pending_window(phase))
	_check("the Pile In step has not begun while the window waits", int(phase.pile_in_step_11e) != int(phase.PileInStep11e.ACTIVE))
	var blocked = phase.execute_action({"type": "END_PILE_IN", "player": 1})
	_check("other actions are refused while it waits", not blocked.get("success", true))
	var dac: String = K.offer_id("dacatarai")
	var kap: String = K.offer_id("kaptaris")
	var cp_before := _cp(1)
	var r = _use(phase, 1, "fight_phase_start", dac, CG)
	_check("USE Dacatarai on the Custodian Guard succeeds", r.get("success", false), str(r.get("error", "")))
	_check("the unit is no longer readied", not K.is_readied(CG))
	_check("Dacatarai flag set", bool(_flags(CG).get(K.flag_for("dacatarai"), false)))
	_check("CP unchanged (ka'tah costs no CP)", _cp(1) == cp_before, "%d -> %d" % [cp_before, _cp(1)])
	_check("the window re-opens for the rest (still fight_phase_start, P1)", _pending_window(phase) == "fight_phase_start" and int(phase.get_pending_stratagem_window_decider()) == 1)
	var rest := _pending_offers(phase)
	_check("the used unit is no longer offered; the others still are", not CG in _targets(rest, dac) and not CG in _targets(rest, kap) and SC in _targets(rest, kap), str(_targets(rest, kap)))
	var again = _use(phase, 1, "fight_phase_start", kap, CG)
	_check("a second ka'tah for the same unit is refused", not again.get("success", true))
	_check("refused use leaves the window open", _pending_window(phase) == "fight_phase_start")
	var direct = K.use_katah(1, kap, CG, {"window_id": "fight_phase_start", "phase": "fight"})
	_check("CustodesKatah.use_katah refuses it too", not direct.get("success", true) and str(direct.get("error", "")).find("not readied") >= 0, str(direct))
	r = _use(phase, 1, "fight_phase_start", kap, CONT)
	_check("Kaptaris on the Contemptor in the same window", r.get("success", false) and bool(_flags(CONT).get(K.flag_for("kaptaris"), false)))
	_decline(phase, 1, "fight_phase_start")
	_check("P1 declines the rest: P2's window has no offers -> the Pile In step begins", not phase.has_pending_stratagem_window() and int(phase.pile_in_step_11e) == int(phase.PileInStep11e.ACTIVE))
	var gel_hits := 0
	for e in root.get_node("GameEventLog").get_all_entries():
		if str(e.get("text", "")).find("Martial Ka'tah: Custodian Guard Sodality uses DACATARAI") >= 0:
			gel_hits += 1
	_check("Game Log names the unit and the ka'tah", gel_hits >= 1)
	# Stratagem + ka'tah ordering: after a STRATAGEM use the window re-opens
	# with the ka'tah cards only, and only when one is still usable there.
	var q0: int = phase._window_queue.size()
	phase._queue_katah_reopen(1, "fight_phase_start", {"phase": "fight"}, true)
	_check("after a stratagem: ka'tah-only re-open queued while a readied unit is in range", phase._window_queue.size() == q0 + 1 and bool(phase._window_queue[0].get("katah_only", false)))
	phase._window_queue.clear()
	for uid in GS.state.units:
		_flags(uid)[K.FLAG_READIED] = false
		_flags(uid)[K.FLAG_MASTER_ROUND] = 2  # Master of Ka'tahs spent too
	phase._queue_katah_reopen(1, "fight_phase_start", {"phase": "fight"}, true)
	_check("…and nothing is queued once no ka'tah is usable", phase._window_queue.is_empty())
	_check("katah_only offers contain no stratagem", phase._window_offers_for(1, "fight_phase_start", {"phase": "fight"}, true).filter(func(o): return not K.is_katah_offer(o)).is_empty())


# ---------------------------------------------------------------------------
func _section_calistus_move() -> void:
	print("\n-- D1. CALISTUS through the real Movement phase (A/B) --")
	_restore()
	var phase = _enter(PHASE_MOVEMENT)
	_restore()
	var cal: String = K.offer_id("calistus")
	var r = phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": WS_C, "player": 1})
	_check("BEGIN_NORMAL_MOVE pauses on unit_selected_to_move with CALISTUS", r.get("success", false) and _pending_window(phase) == "unit_selected_to_move" and cal in _offer_ids(_pending_offers(phase)), _pending_window(phase))
	_decline(phase, 1, "unit_selected_to_move")
	_check("B: declined -> the move begins, the unit stays readied", phase.active_moves.has(WS_C) and K.is_readied(WS_C))
	var m1 = GS.state.units[WS_C].models[0]
	var dest := _pos(m1) + Vector2(0, -5.75 * PX)
	var b = phase.execute_action({"type": "STAGE_MODEL_MOVE", "actor_unit_id": WS_C, "payload": {"model_id": str(m1.id), "dest": [dest.x, dest.y]}})
	_check("B: a normal move straight through the Telemon (VEHICLE) is refused", not b.get("success", true), str(b.get("error", b.get("errors", ""))))
	# A: a fresh Movement phase, Calistus used.
	_restore()
	phase = _enter(PHASE_MOVEMENT)
	_restore()
	r = phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": WS_C, "player": 1})
	r = _use(phase, 1, "unit_selected_to_move", cal, WS_C)
	_check("A: USE Calistus -> the move begins", r.get("success", false) and phase.active_moves.has(WS_C) and not phase.has_pending_stratagem_window(), str(r.get("error", "")))
	_check("A: Witchseekers no longer readied, Calistus active", not K.is_readied(WS_C) and bool(_flags(WS_C).get(K.flag_for("calistus"), false)))
	m1 = GS.state.units[WS_C].models[0]
	dest = _pos(m1) + Vector2(0, -5.75 * PX)
	var a = phase.execute_action({"type": "STAGE_MODEL_MOVE", "actor_unit_id": WS_C, "payload": {"model_id": str(m1.id), "dest": [dest.x, dest.y]}})
	_check("A: the same move through the VEHICLE is accepted", a.get("success", false), str(a.get("error", a.get("errors", ""))))
	_check("A: path check helper agrees (no crossing for a Calistus move)", not phase._path_crosses_monster_vehicle_bases(_pos(GS.state.units[WS_C].models[1]), _pos(GS.state.units[WS_C].models[1]) + Vector2(0, -5.75 * PX), WS_C, GS.state.units[WS_C].models[1]))
	# The ka'tah lasts for the phase: ends with it.
	PM.transition_to_phase(PHASE_SHOOTING)
	_check("expiry: Calistus cleared when the Movement phase ends", not _flags(WS_C).has(K.flag_for("calistus")))


# ---------------------------------------------------------------------------
func _section_salvus() -> void:
	print("\n-- D2. SALVUS (A/B, same seeds, both ranged resolvers) --")
	_restore()
	var phase = _enter(PHASE_SHOOTING)
	_restore()
	var wid := _ranged_weapon(CALADIUS)
	_check("Caladius has a ranged weapon (%s)" % wid, wid != "")
	# Penalties: target in cover (BS worsened by 1 per attack, 13.08) and
	# "-1 to wound" (HULKING BRUTES on the Gretchin).
	var off: Dictionary = GS.state.duplicate(true)
	off.units[GRETS].flags["stratagem_cover"] = true
	off.units[GRETS].flags["ork11e_hulking_brutes"] = "all"
	var on: Dictionary = off.duplicate(true)
	on.units[CALADIUS].flags[K.flag_for("salvus")] = true
	var hits_off := 0
	var hits_on := 0
	var wounds_off := 0
	var wounds_on := 0
	var never_less := true
	var ledger_ok := false
	var t_off := ""
	var t_on := ""
	for s in range(20):
		var x0 = _shoot(off.duplicate(true), CALADIUS, wid, GRETS, 500 + s)
		var x1 = _shoot(on.duplicate(true), CALADIUS, wid, GRETS, 500 + s)
		var h0 = _block(x0, "to_hit")
		var h1 = _block(x1, "to_hit")
		hits_off += int(h0.get("successes", 0))
		hits_on += int(h1.get("successes", 0))
		if int(h1.get("successes", 0)) < int(h0.get("successes", 0)):
			never_less = false
		var w0 = _block(x0, "to_wound")
		var w1 = _block(x1, "to_wound")
		wounds_off += int(w0.get("successes", 0))
		wounds_on += int(w1.get("successes", 0))
		if _ledger_has(h1, "Salvus"):
			ledger_ok = true
		if s == 0:
			t_off = str(h0.get("threshold", ""))
			t_on = str(h1.get("threshold", ""))
	_check("SALVUS: never fewer hits, and more overall (cover ignored): %d -> %d" % [hits_off, hits_on], never_less and hits_on > hits_off)
	_check("SALVUS: more wounds (-1 to wound ignored): %d -> %d" % [wounds_off, wounds_on], wounds_on > wounds_off)
	_check("SALVUS: the hit block's ledger names Salvus", ledger_ok)
	_check("SALVUS: hit threshold display differs (%s vs %s)" % [t_off, t_on], t_off != t_on)
	# Interactive resolver (resolve_shoot_until_wounds) honours it too.
	var i0 = RE.resolve_shoot_until_wounds({"type": "SHOOT", "actor_unit_id": CALADIUS, "payload": {"assignments": [_assign(off, CALADIUS, wid, GRETS)]}}, off.duplicate(true), RE.RNGService.new(77))
	var i1 = RE.resolve_shoot_until_wounds({"type": "SHOOT", "actor_unit_id": CALADIUS, "payload": {"assignments": [_assign(on, CALADIUS, wid, GRETS)]}}, on.duplicate(true), RE.RNGService.new(77))
	_check("SALVUS interactive: hits >= without", int(_block(i1, "to_hit").get("successes", 0)) >= int(_block(i0, "to_hit").get("successes", 0)) and _ledger_has(_block(i1, "to_hit"), "Salvus"))
	# +1 modifiers are kept: a +1 to hit flag still applies under Salvus.
	var plus: Dictionary = on.duplicate(true)
	plus.units[GRETS].flags.erase("stratagem_cover")
	plus.units[CALADIUS].flags["effect_plus_one_hit_ranged"] = true
	var p1 = _shoot(plus.duplicate(true), CALADIUS, wid, GRETS, 9)
	_check("SALVUS keeps the +1s (\"can ignore\" — only the harmful ones)", _ledger_has(_block(p1, "to_hit"), "Ability effect") and _ledger_has(_block(p1, "to_hit"), "Salvus"), str(_block(p1, "to_hit").get("modifier_ledger", [])))


# ---------------------------------------------------------------------------
func _section_melee_katahs() -> void:
	print("\n-- D3. DACATARAI / KAPTARIS / RENDAX (A/B, same seeds) --")
	var dflag := {K.flag_for("dacatarai"): true}
	var rerolls_inf := 0
	var rerolls_mv := 0
	var hits_off := 0
	var hits_on := 0
	for s in range(20):
		var off = _melee(_melee_board({}, {}, ["INFANTRY"], ""), 100 + s)
		var on = _melee(_melee_board(dflag.duplicate(), {}, ["INFANTRY"], ""), 100 + s)
		var mv = _melee(_melee_board(dflag.duplicate(), {}, ["VEHICLE"], ""), 100 + s)
		hits_off += int(_block(off, "hit_roll_melee").get("successes", 0))
		hits_on += int(_block(on, "hit_roll_melee").get("successes", 0))
		if _ledger_has(_block(on, "hit_roll_melee"), "Dacatarai"):
			rerolls_inf += 1
		if _ledger_has(_block(mv, "hit_roll_melee"), "Dacatarai"):
			rerolls_mv += 1
	_check("DACATARAI: re-roll hit rolls of 1 vs infantry (ledger every time)", rerolls_inf == 20)
	_check("DACATARAI: more hits overall vs infantry: %d -> %d" % [hits_off, hits_on], hits_on > hits_off)
	_check("DACATARAI: no re-roll vs a VEHICLE", rerolls_mv == 0)

	var kflag := {K.flag_for("kaptaris"): true}
	var k_off := 0
	var k_on := 0
	var k_ledger := true
	for s in range(20):
		var off = _melee(_melee_board({}, {}, ["INFANTRY"], ""), 200 + s)
		var on = _melee(_melee_board({}, kflag.duplicate(), ["INFANTRY"], ""), 200 + s)
		k_off += int(_block(off, "hit_roll_melee").get("successes", 0))
		k_on += int(_block(on, "hit_roll_melee").get("successes", 0))
		if not _ledger_has(_block(on, "hit_roll_melee"), "Kaptaris"):
			k_ledger = false
	_check("KAPTARIS: melee attacks that target the unit have -1 to hit: %d -> %d" % [k_off, k_on], k_on < k_off and k_ledger)

	var rflag := {K.flag_for("rendax"): true}
	var r_mv = _melee(_melee_board(rflag.duplicate(), {}, ["VEHICLE"], ""), 7)
	var r_inf = _melee(_melee_board(rflag.duplicate(), {}, ["INFANTRY"], ""), 7)
	var r_off = _melee(_melee_board({}, {}, ["MONSTER"], ""), 7)
	_check("RENDAX: [LETHAL HITS] vs a VEHICLE", bool(_block(r_mv, "hit_roll_melee").get("lethal_hits_weapon", false)))
	_check("RENDAX: [LETHAL HITS] vs a MONSTER", bool(_block(_melee(_melee_board(rflag.duplicate(), {}, ["MONSTER"], ""), 7), "hit_roll_melee").get("lethal_hits_weapon", false)))
	_check("RENDAX: no [LETHAL HITS] vs infantry (keyword-qualified)", not bool(_block(r_inf, "hit_roll_melee").get("lethal_hits_weapon", true)))
	_check("without RENDAX: no [LETHAL HITS] vs a MONSTER", not bool(_block(r_off, "hit_roll_melee").get("lethal_hits_weapon", true)))


# ---------------------------------------------------------------------------
func _section_conservai() -> void:
	print("\n-- D4. CONSERVAI (actions) --")
	_restore()
	var AM = load("res://scripts/rules/ActionsManager.gd")
	var board: Dictionary = GS.state
	var e0 = AM.can_start_action(CG, board)
	_check("engaged Custodian Guard cannot start an action", not e0.eligible)
	_flags(CG)["battle_shocked"] = true
	_flags(CG)[K.flag_for("conservai")] = true
	var e1 = AM.can_start_action(CG, board)
	_check("CONSERVAI: engaged + battle-shocked -> eligible to start an action", e1.eligible, str(e1.reasons))
	var st = AM.start_action(CG, "hold_position", board, 1, 2)
	var sets_cannot_shoot := false
	for c in st.get("changes", []):
		if str(c.get("path", "")).ends_with("cannot_shoot"):
			sets_cannot_shoot = true
	_check("CONSERVAI: starting an action does not make the unit ineligible to shoot", st.get("success", false) and not sets_cannot_shoot, str(st))
	_flags(WS_D)["battle_shocked"] = true
	_check("without CONSERVAI a battle-shocked unit still cannot", not AM.can_start_action(WS_D, board).eligible)
	var plain = AM.start_action(WS_C, "hold_position", board, 1, 2)
	_check("control: without CONSERVAI starting an action sets cannot_shoot", plain.get("success", false) and str(plain.get("changes", [])).find("cannot_shoot") >= 0, str(plain))
	# ShootingPhase START_ACTION keeps a Conservai unit shootable.
	_restore()
	var phase = _enter(PHASE_SHOOTING)
	_restore()
	_flags(WS_D)[K.flag_for("conservai")] = true
	var ok = phase.execute_action({"type": "START_ACTION", "actor_unit_id": WS_D, "player": 1, "payload": {"action_id": "hold_position"}})
	_check("START_ACTION under CONSERVAI succeeds", ok.get("success", false), str(ok.get("error", "")))
	_check("…and the unit has not 'shot' — it may still shoot this phase", not bool(_flags(WS_D).get("has_shot", false)) and not WS_D in phase.units_that_shot)
	_check("…but it is performing the action", str(_flags(WS_D).get("performing_action", "")) == "hold_position")


# ---------------------------------------------------------------------------
func _section_expiry() -> void:
	print("\n-- E. expiry --")
	_restore()
	var phase = _enter(PHASE_COMMAND)
	_restore()
	var r = K.use_katah(1, K.offer_id("conservai"), CG, {"window_id": "command_phase_main", "phase": "command"})
	_check("CONSERVAI used on the Custodian Guard (Command phase)", r.get("success", false), str(r.get("error", "")))
	PM.transition_to_phase(PHASE_MOVEMENT)
	PM.transition_to_phase(PHASE_SHOOTING)
	_check("CONSERVAI lasts until the end of the TURN (still on in the Shooting phase)", bool(_flags(CG).get(K.flag_for("conservai"), false)))
	_check("the Shield-Captain is still readied (unused)", K.is_readied(SC))
	# Opponent's turn: readied units keep their state; Conservai is gone.
	GS.state.meta["active_player"] = 2
	PM.transition_to_phase(PHASE_COMMAND)
	_check("P2's Command phase ends P1's Conservai (end of turn)", not _flags(CG).has(K.flag_for("conservai")))
	_check("P1 units still readied in the opponent's turn", K.is_readied(SC) and not K.is_readied(CG))
	phase = _enter(PHASE_FIGHT)
	var fs = K.window_offers(1, "fight_phase_start", {})
	_check("…and can use a ka'tah then (Kaptaris for the Shield-Captain in P2's Fight phase)", SC in _targets(fs, K.offer_id("kaptaris")))
	r = K.use_katah(1, K.offer_id("kaptaris"), SC, {"window_id": "fight_phase_start", "phase": "fight"})
	_check("Kaptaris used in the opponent's Fight phase", r.get("success", false), str(r.get("error", "")))
	PM.transition_to_phase(PHASE_SCORING_OR_NEXT())
	_check("phase-scoped ka'tah (Kaptaris) cleared at the end of the Fight phase", not _flags(SC).has(K.flag_for("kaptaris")))
	GS.state.meta["active_player"] = 1
	K.on_command_phase_start(1)
	_check("next own Command phase: readied again", K.is_readied(SC) and K.is_readied(CG))
	if phase:
		pass
	_restore()


func PHASE_SCORING_OR_NEXT() -> int:
	return 11  # SCORING


# ---------------------------------------------------------------------------
func _section_master_of_katahs() -> void:
	print("\n-- F. Master of Ka'tahs --")
	_restore()
	var phase = _enter(PHASE_FIGHT)
	_restore()
	phase = _enter(PHASE_FIGHT)
	var dac: String = K.offer_id("dacatarai")
	var kap: String = K.offer_id("kaptaris")
	var r = _use(phase, 1, "fight_phase_start", dac, SC)
	_check("Shield-Captain uses Dacatarai (readied)", r.get("success", false) and not K.is_readied(SC), str(r.get("error", "")))
	var t := _target(_pending_offers(phase), kap, SC)
	_check("not readied, Master of Ka'tahs unused: Kaptaris offered as the master variant only", not t.is_empty() and bool(t.get("require_variant", false)) and str(t.get("variants", [{}])[0].get("id", "")) == K.MASTER_VARIANT, str(t))
	_flags(CG)[K.FLAG_READIED] = false
	_check("a Custodian Guard (no Master) that is not readied is not offered", not CG in _targets(K.window_offers(1, "fight_phase_start", {}), kap))
	_flags(CG)[K.FLAG_READIED] = true
	var plain = _use(phase, 1, "fight_phase_start", kap, SC)
	_check("plain use without the variant is refused", not plain.get("success", true))
	r = _use(phase, 1, "fight_phase_start", kap, SC, {"variant_id": K.MASTER_VARIANT})
	_check("Master of Ka'tahs: readied again and Kaptaris used at once", r.get("success", false) and bool(_flags(SC).get(K.flag_for("kaptaris"), false)) and not K.is_readied(SC), str(r.get("error", "")))
	_check("master marker = battle round 2", int(_flags(SC).get(K.FLAG_MASTER_ROUND, -1)) == 2)
	_check("once per battle round: no further master variant", not K.master_available(SC) and _target(_pending_offers(phase), dac, SC).is_empty())
	_decline(phase, 1, "fight_phase_start")
	# Same battle round, opponent's turn: still used.
	GS.state.meta["active_player"] = 2
	_check("still used in the opponent's turn of the same battle round", not K.master_available(SC))
	# Next battle round: available again (unit not readied).
	GS.state.meta["battle_round"] = 3
	_check("next battle round: available again", K.master_available(SC))
	_flags(SC)[K.FLAG_READIED] = true
	_check("a READIED unit does not need it (not offered)", not K.master_available(SC))
	GS.state.meta["active_player"] = 1
	GS.state.meta["battle_round"] = 2
	_check("Master of Ka'tahs only on the Shield-Captain datasheets", K.master_component(CG) == "" and K.master_component(SC) == SC and K.master_component(JETBIKE) == JETBIKE)
	# Attached unit: flags on every component, the leader's Master serves the unit.
	_restore()
	GS.state.units[SC]["attached_to"] = CG
	GS.state.units[CG]["attachment_data"] = {"attached_characters": [SC]}
	_check("Attached unit: readied if any component is", K.is_readied(CG) and K.is_readied(SC))
	var group_offer = K.window_offers(1, "unit_selected_to_fight", {"unit_id": CG})
	_check("Attached unit: one card target labelled 'Guard + Captain'", _targets(group_offer, K.offer_id("rendax")) == [CG] and str(_target(group_offer, K.offer_id("rendax"), CG).get("label", "")).find("+") > 0, str(group_offer))
	r = K.use_katah(1, K.offer_id("rendax"), CG, {"window_id": "unit_selected_to_fight", "phase": "fight", "unit_id": CG})
	_check("Attached unit: Rendax written on BOTH components, both un-readied", r.get("success", false) and bool(_flags(CG).get(K.flag_for("rendax"), false)) and bool(_flags(SC).get(K.flag_for("rendax"), false)) and not K.is_readied(CG) and not K.is_readied(SC))
	_check("Attached unit: the leader's Master of Ka'tahs is the unit's", K.master_component(CG) == SC and K.master_available(CG))
	GS.state.units[SC].erase("attached_to")
	GS.state.units[CG]["attachment_data"] = {"attached_characters": []}
	PM.transition_to_phase(11)
	_restore()


# ---------------------------------------------------------------------------
func _section_aegis() -> void:
	print("\n-- G. Aegis of the Emperor (FNP 5+ vs mortal wounds) --")
	_restore()
	var cg = _unit(CG)
	_check("Custodian Guard: FNP 5+ vs a mortal wound", RE.get_unit_fnp_vs(cg, false, true) == 5)
	_check("…none vs normal damage", RE.get_unit_fnp_vs(cg, false, false) == 0)
	_check("…none vs a (non-mortal) psychic attack", RE.get_unit_fnp_vs(cg, true, false) == 0)
	_check("Witchseekers (no Aegis): no FNP vs mortal wounds", RE.get_unit_fnp_vs(_unit(WS_C), false, true) == 0)
	# Best applicable, never stacked.
	var with4: Dictionary = cg.duplicate(true)
	with4.meta.stats["fnp"] = 4
	_check("with FNP 4+ as well: the best (4+) applies vs mortal wounds", RE.get_unit_fnp_vs(with4, false, true) == 4)
	var with6: Dictionary = cg.duplicate(true)
	with6.meta.stats["fnp"] = 6
	_check("with FNP 6+ as well: Aegis 5+ is the best", RE.get_unit_fnp_vs(with6, false, true) == 5 and RE.get_unit_fnp_vs(with6, false, false) == 6)
	# Path 1: stratagem / ability mortal wounds (RulesEngine.apply_mortal_wounds)
	var b1: Dictionary = GS.state.duplicate(true)
	var mw1 = RE.apply_mortal_wounds(CG, 12, b1, RE.RNGService.new(3))
	_check("apply_mortal_wounds: FNP rolled for all 12 MW", mw1.get("fnp_rolls", []).size() == 12 and int(mw1.get("wounds_applied", 12)) < 12, str(mw1.get("fnp_rolls", [])))
	# Path 2: apply_mortal_wounds_to_unit (11e allocation helper)
	var mw2 = RE.apply_mortal_wounds_to_unit(CG, 12, GS.state.duplicate(true), RE.RNGService.new(3))
	_check("apply_mortal_wounds_to_unit: feel_no_pain dice block", not mw2.get("dice", []).is_empty() and int(mw2.dice[0].get("fnp_value", 0)) == 5)
	# Path 3: EXPLOSIVES (11e core stratagem dice effect)
	var ex_ok := false
	for s in range(20):
		var ex = RE.resolve_explosives_11e(CG, GS.state.duplicate(true), RE.RNGService.new(11 + s))
		if int(ex.get("mortal_wounds", 0)) > 0:
			var ex_fnp = _block(ex, "feel_no_pain")
			ex_ok = int(ex_fnp.get("fnp_value", 0)) == 5 and ex_fnp.get("rolls", []).size() == int(ex.mortal_wounds)
			break
	_check("EXPLOSIVES: FNP 5+ rolled for each of its mortal wounds", ex_ok)
	# Path 4: Deadly Demise of an adjacent vehicle
	var dd_seen := false
	for s in range(40):
		var b4: Dictionary = GS.state.duplicate(true)
		var dd = RE.resolve_deadly_demise(DREAD, "6", b4, RE.RNGService.new(900 + s))
		if not dd.get("triggered", false):
			continue
		for pt in dd.get("per_target", []):
			if str(pt.get("target_unit_id", "")) == BC and not pt.get("fnp_rolls", []).is_empty():
				dd_seen = true
		if dd_seen:
			break
	_check("Deadly Demise mortal wounds roll the Blade Champion's Aegis FNP", dd_seen)
	# Path 5: [HAZARDOUS] (granted to the Caladius' guns)
	var hz_seen := false
	var wid := _ranged_weapon(CALADIUS)
	for s in range(40):
		var b5: Dictionary = GS.state.duplicate(true)
		b5.units[CALADIUS].flags["effect_grant_hazardous"] = true
		var hz = RE.resolve_hazardous_check(CALADIUS, wid, 3, b5, RE.RNGService.new(40 + s))
		var dmg = _block(hz, "hazardous_damage")
		if not dmg.is_empty() and not dmg.get("fnp_rolls", []).is_empty():
			hz_seen = true
			break
	_check("[HAZARDOUS] mortal wounds roll Aegis FNP 5+", hz_seen)
	# Path 6: [DEVASTATING WOUNDS] (11e allocation path) on the Custodians.
	var dw_board := _melee_board({}, {}, ["INFANTRY"], "Devastating Wounds")
	dw_board.units.U_TGT.meta["abilities"] = [{"name": "Aegis of the Emperor", "type": "Faction"}]
	dw_board.units.U_TGT.meta["keywords"] = ["ADEPTUS CUSTODES", "INFANTRY"]
	dw_board.units.U_TGT.meta.stats["save"] = 2
	var dw_fnp := false
	var dw_normal_fnp := false
	for s in range(20):
		var dr = _melee(dw_board.duplicate(true), 60 + s)
		for d in dr.get("dice", []):
			if str(d.get("context", "")) == "feel_no_pain":
				if str(d.get("source", "")) == "devastating_wounds" and int(d.get("fnp_value", 0)) == 5:
					dw_fnp = true
				elif str(d.get("source", "")) != "devastating_wounds":
					dw_normal_fnp = true
	_check("[DEVASTATING WOUNDS] mortal wounds: Aegis FNP 5+ rolled", dw_fnp)
	_check("…but no Aegis FNP vs the normal (failed save) damage", not dw_normal_fnp)
	# Path 7: crushing impact (11e core stratagem) — both sides' mortal wounds.
	var ci_ok := false
	for s in range(40):
		var ci = RE.resolve_crushing_impact_11e(TELEMON, BOYZ, GS.state.duplicate(true), RE.RNGService.new(5 + s))
		if int(ci.get("self_mortals", 0)) > 0:
			for d in ci.get("dice", []):
				if str(d.get("context", "")) == "feel_no_pain" and int(d.get("fnp_value", 0)) == 5:
					ci_ok = true
			break
	_check("CRUSHING IMPACT self mortal wounds on the Telemon roll Aegis FNP 5+", ci_ok)


# ---------------------------------------------------------------------------
func _section_daughters() -> void:
	print("\n-- I. Daughters of the Abyss / Psychic Null --")
	_restore()
	var ws = _unit(WS_C)
	_check("Witchseekers: FNP 3+ vs psychic attacks", RE.get_unit_fnp_vs(ws, true, false) == 3)
	_check("…not vs normal damage", RE.get_unit_fnp_vs(ws, false, false) == 0)
	_check("…not vs (non-psychic) mortal wounds", RE.get_unit_fnp_vs(ws, false, true) == 0)
	# Psychic Null (Aura): Telemon is 0.26" from Witchseekers C.
	_check("Psychic Null: Telemon (ADEPTUS CUSTODES, within 6\") FNP 5+ vs psychic", RE.get_unit_fnp_vs(_unit(TELEMON), true, false) == 5 and K.psychic_null_source(_unit(TELEMON)) != "")
	_check("…not vs normal damage", RE.get_unit_fnp_vs(_unit(TELEMON), false, false) == 0)
	_check("…psychic mortal wound: best of Aegis 5+ / Psychic Null 5+ = 5", RE.get_unit_fnp_vs(_unit(TELEMON), true, true) == 5)
	_check("Caladius (> 6\" from both Witchseekers): no Psychic Null", RE.get_unit_fnp_vs(_unit(CALADIUS), true, false) == 0)
	_check("an Ork unit near the Witchseekers gets nothing", RE.get_unit_fnp_vs(_unit(GRETS), true, false) == 0)
	# A psychic attack through the resolver: FNP 3+ vs the Witchseekers.
	var board: Dictionary = GS.state.duplicate(true)
	var shooter: Dictionary = board.units[GRETS]
	var psy := {"name": "Test Psy Bolt", "type": "Ranged", "range": "24", "attacks": "6", "ballistic_skill": "2",
		"strength": "8", "ap": "-3", "damage": "1", "special_rules": "Psychic"}
	shooter.meta["weapons"] = [psy]
	var plain := psy.duplicate()
	plain["name"] = "Test Plain Bolt"
	plain["special_rules"] = ""
	var b_plain: Dictionary = board.duplicate(true)
	b_plain.units[GRETS].meta["weapons"] = [plain]
	var psy_fnp := false
	var plain_fnp := false
	for s in range(15):
		var w_psy := ""
		var w_plain := ""
		var wm = RE.get_unit_weapons(GRETS, board)
		for mid in wm:
			for wid in wm[mid]:
				if str(wid).find("psy") >= 0:
					w_psy = str(wid)
		var wm2 = RE.get_unit_weapons(GRETS, b_plain)
		for mid in wm2:
			for wid in wm2[mid]:
				if str(wid).find("plain") >= 0:
					w_plain = str(wid)
		if w_psy == "" or w_plain == "":
			break
		var rp = RE.resolve_shoot({"type": "SHOOT", "actor_unit_id": GRETS, "payload": {"assignments": [_assign(board, GRETS, w_psy, WS_D)]}}, board.duplicate(true), RE.RNGService.new(700 + s))
		var rq = RE.resolve_shoot({"type": "SHOOT", "actor_unit_id": GRETS, "payload": {"assignments": [_assign(b_plain, GRETS, w_plain, WS_D)]}}, b_plain.duplicate(true), RE.RNGService.new(700 + s))
		if int(_block(rp, "feel_no_pain").get("fnp_value", 0)) == 3:
			psy_fnp = true
		if not _block(rq, "feel_no_pain").is_empty():
			plain_fnp = true
	_check("a [PSYCHIC] attack on Witchseekers rolls FNP 3+", psy_fnp)
	_check("the same attack without [PSYCHIC] rolls no FNP", not plain_fnp)
	_check("UnitAbilityManager row no longer grants the 10e psychic+mortal flag", root.get_node("UnitAbilityManager").ABILITY_EFFECTS["Daughters of the Abyss"].effects.is_empty())


# ---------------------------------------------------------------------------
func _section_anathema_psykana() -> void:
	print("\n-- J. Anathema Psykana: no ANATHEMA PSYKANA WARLORD --")
	var alm = root.get_node("ArmyListManager")
	var army := {"faction": {"name": "Adeptus Custodes", "points": 2000, "detachment": "Guardians of the Throne"},
		"units": {"U_KC": {"meta": {"name": "Knight-Centura", "is_warlord": true, "keywords": ["ADEPTUS CUSTODES", "ANATHEMA PSYKANA", "CHARACTER", "INFANTRY"]}}}}
	var v = alm.validate_army_construction_11e(army)
	_check("army validation warns about an ANATHEMA PSYKANA WARLORD", str(v.warnings).find("ANATHEMA PSYKANA model cannot be your WARLORD") >= 0, str(v.warnings))
	army.units.U_KC.meta.keywords = ["ADEPTUS CUSTODES", "CHARACTER", "INFANTRY"]
	v = alm.validate_army_construction_11e(army)
	_check("a non-Anathema warlord: no such warning", str(v.warnings).find("ANATHEMA PSYKANA") < 0)
	# WP-C46 filled the hook in (CustodesDetachments.allows_anathema_psykana_warlord).
	_check("hook: Null Maiden Vigil allows an ANATHEMA PSYKANA WARLORD (WP-C46), other detachments do not",
		K.anathema_psykana_warlord_allowed("Null Maiden Vigil") and not K.anathema_psykana_warlord_allowed("Guardians of the Throne"))
	# FormationsPhase refuses the designation and never auto-picks one.
	GS.state.units["U_TEST_KC"] = {"id": "U_TEST_KC", "owner": 1, "status": GS.UnitStatus.DEPLOYED, "flags": {},
		"meta": {"name": "Knight-Centura", "keywords": ["ADEPTUS CUSTODES", "ANATHEMA PSYKANA", "CHARACTER", "INFANTRY"], "abilities": [], "stats": {}},
		"models": [{"id": "m1", "alive": true, "wounds": 4, "current_wounds": 4, "base_mm": 40, "position": {"x": 400.0, "y": 2200.0}}]}
	var fp = load("res://phases/FormationsPhase.gd").new()
	var was_confirmed = GS.state.meta.get("formations_p1_confirmed", false)
	GS.state.meta["formations_p1_confirmed"] = false
	var res = fp._validate_designate_warlord({"unit_id": "U_TEST_KC", "player": 1})
	_check("Formations: DESIGNATE_WARLORD of an ANATHEMA PSYKANA model is refused", not res.valid and str(res.errors).find("ANATHEMA PSYKANA") >= 0, str(res))
	res = fp._validate_designate_warlord({"unit_id": SC, "player": 1})
	_check("Formations: the Shield-Captain may be designated", res.valid, str(res))
	_check("Formations: never offered as a DESIGNATE_WARLORD action", not "U_TEST_KC" in fp._cus11e_warlord_eligible(["U_TEST_KC", SC], 1))
	GS.state.units[SC].meta["is_warlord"] = false
	GS.state.units["U_TEST_KC"].meta["is_warlord"] = true
	var wv = fp._validate_warlord_designation(1)
	_check("Formations: an ANATHEMA PSYKANA warlord fails the confirmation check", not wv.valid, str(wv))
	GS.state.units["U_TEST_KC"].meta["is_warlord"] = false
	GS.state.units[SC].meta["is_warlord"] = true
	GS.state.meta["formations_p1_confirmed"] = was_confirmed
	fp.free()
	GS.state.units.erase("U_TEST_KC")


# ---------------------------------------------------------------------------
func _section_ai() -> void:
	print("\n-- K. AI picks without stalling --")
	_restore()
	var ai = root.get_node("AIPlayer")
	ai.enabled = true
	ai.ai_players = {1: true, 2: false}
	var phase = _enter(PHASE_FIGHT)
	_restore()
	phase = _enter(PHASE_FIGHT)
	_check("AI P1: fight_phase_start resolved synchronously (no pending window)", not phase.has_pending_stratagem_window(), _pending_window(phase))
	_check("…the Pile In step began", int(phase.pile_in_step_11e) == int(phase.PileInStep11e.ACTIVE))
	_check("AI: Dacatarai on the Custodian Guard (engaged with Boyz, own turn)", bool(_flags(CG).get(K.flag_for("dacatarai"), false)))
	_check("AI: Dacatarai on the Contemptor (engaged with Meganobz)", bool(_flags(CONT).get(K.flag_for("dacatarai"), false)))
	_check("AI: Blade Champion (engaged with a VEHICLE) is kept readied for Rendax", K.is_readied(BC))
	_check("AI: unengaged Witchseekers D not spent", K.is_readied(WS_D))
	var ADM = load("res://scripts/AIDecisionMaker.gd")
	var rf = K.window_offers(1, "unit_selected_to_fight", {"unit_id": BC})
	var d = ADM.decide_window_stratagem(1, "unit_selected_to_fight", rf, {"unit_id": BC})
	_check("AI: Rendax when selected to fight vs the Deff Dread", d.get("use", false) and str(d.stratagem_id) == K.offer_id("rendax"), str(d))
	var mv = K.window_offers(1, "unit_selected_to_move", {"unit_id": WS_C, "move_type": "normal"})
	_check("AI: no Calistus for a plain normal move", mv.is_empty() or not ADM.decide_window_stratagem(1, "unit_selected_to_move", mv, {"unit_id": WS_C, "move_type": "normal"}).get("use", false))
	var cons = K.ai_pick(1, "command_phase_main", [{"stratagem_id": K.offer_id("conservai"), "kind": "katah", "katah_id": "conservai", "targets": [{"unit_id": CG}]}], {})
	_check("AI: never Conservai (it does not start actions)", not cons.get("use", true))
	var fb = K.ai_pick(1, "unit_selected_to_move", [{"stratagem_id": K.offer_id("calistus"), "kind": "katah", "katah_id": "calistus", "targets": [{"unit_id": CG}]}], {"unit_id": CG, "move_type": "fall_back"})
	_check("AI: Calistus for a fall-back move", fb.get("use", false))
	# Opponent's turn: the AI's readied Custodes defend with Kaptaris.
	_restore()
	GS.state.meta["active_player"] = 2
	phase = _enter(PHASE_FIGHT)
	_check("AI P1 in P2's Fight phase: windows resolved, no stall", not phase.has_pending_stratagem_window() or int(phase.get_pending_stratagem_window_decider()) == 2)
	_check("AI: Kaptaris on the engaged Custodian Guard in the opponent's turn", bool(_flags(CG).get(K.flag_for("kaptaris"), false)))
	GS.state.meta["active_player"] = 1
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	PM.transition_to_phase(11)
	_restore()


# ---------------------------------------------------------------------------
func _section_api_and_cleanup() -> void:
	print("\n-- L. Favoured Ka'tah API + 10e stance system removed --")
	# WP-C46 (CustodesDetachments.gd) defines the Favoured Ka'tah; the fixture's
	# detachment is not a Unique: Shield Host one, so nothing is favoured here.
	_check("favoured_katah(player): \"\" for a detachment without a Favoured Ka'tah", K.favoured_katah(1) == "" and K.favoured_katah(2) == "")
	_check("favoured_katah_extra_effect: [] when the ka'tah is not favoured", K.favoured_katah_extra_effect(1, "calistus", WS_C, {}).is_empty())
	_check("favoured_katah_secondary: {} when the ka'tah is not favoured", K.favoured_katah_secondary(1, "kaptaris", CG, {}).is_empty())
	_check("ready_diffs (SUPERHUMAN FOCUS API) readies the unit", str(K.ready_diffs(CG)).find(K.FLAG_READIED) >= 0)
	_check("KatahStanceDialog is gone", not ResourceLoader.exists("res://dialogs/KatahStanceDialog.gd"))
	var fam = root.get_node("FactionAbilityManager")
	_check("FactionAbilityManager: apply/clear/get_katah_stance removed", not fam.has_method("apply_katah_stance") and not fam.has_method("clear_katah_stance") and not fam.has_method("get_katah_stance"))
	var fight_src := FileAccess.get_file_as_string("res://phases/FightPhase.gd")
	_check("FightPhase: no SELECT_KATAH_STANCE / katah_stance_required", fight_src.find("SELECT_KATAH_STANCE") < 0 and fight_src.find("katah_stance_required") < 0)
	_check("UnitAbilityManager: no 10e Master of the Stances", not root.get_node("UnitAbilityManager").ABILITY_EFFECTS.has("Master of the Stances"))
	_check("StratagemManager names the new windows", SM.window_when_text("fight_phase_start") != "fight phase start" and SM.window_when_text("command_phase_main") != "command phase main")
