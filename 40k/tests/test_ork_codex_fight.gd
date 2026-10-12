extends SceneTree

# Codex: Orks (11e) — FIGHT group stratagems (design .llm/ork_codex_11e_design.md
# §3, §3.2, §6). Against the real fixture tests/saves/ork11e_orks_active.w40ksave
# (P1 Orks active vs P2 Custodes), detachment switched per stratagem:
#   A. registry: the 9 FIGHT csv ids are implemented (registry only)
#   B. MOW 'EM DOWN — unit_selected_to_fight; ORKS VEHICLE (not WALKER) that
#      charged; melee [CLEAVE 1] / +1 CLEAVE (A/B attack dice, same seeds); expiry
#   C. UNBRIDLED CARNAGE — BOYZ that charged; melee +1 A (A/B attack dice)
#   D. ARMED TO DA TEEF — unit_selected_to_fight AND unit_selected_to_shoot
#      (your Shooting phase only); MEGANOBZ/NOBZ; re-roll 1s / all if riled up
#   E. enemy_targets_unit_fight hook (real CONFIRM flow + held BATCH) and
#      ORKS IS NEVER BEATEN through the Fight On Death mechanic: D6 per
#      destroyed model, kept models fight, are not allocatable, removed when
#      the unit has fought
#   F. Fight On Death edge cases: selected-to-fight gate, riled up +1,
#      CRAZED RAMPAGE +3 (DEFF DREAD), end-of-phase removal + kill accounting once
#   G. TOO ARROGANT TO DIE / CRAZED RAMPAGE / ORKS IS NEVER BEATEN target gates
#   H. fight_phase_end hook + KEEP IT RUNNIN' (embark follow-up)
#   I. INSTINCTIVE HUNTERS (opponent's Fight phase only, strategic_reserves follow-up)
#   J. AI decider paths
#   K. ScoringPhase: repositioned units survive the end-of-round-3 reserves cull
#
# Usage: godot --headless --path 40k --script tests/test_ork_codex_fight.gd

const FIXTURE := "ork11e_orks_active"
const PHASE_COMMAND := 6
const PHASE_SHOOTING := 8
const PHASE_CHARGE := 9
const PHASE_FIGHT := 10
const PX := 40.0

const CSV_HIT := "hit-em-harder-war-horde"
const CSV_MOW := "mow-em-down-war-horde"
const CSV_UC := "unbridled-carnage-green-tide"
const CSV_ATDT := "armed-to-da-teef-bully-boyz"
const CSV_OINB := "orks-is-never-beaten-war-horde"
const CSV_TATD := "too-arrogant-to-die-bully-boyz"
const CSV_CR := "crazed-rampage-dread-mob"
const CSV_KIR := "keep-it-runnin-blitz-brigade"
const CSV_IH := "instinctive-hunters-da-big-hunt"

var passed := 0
var failed := 0
var SM = null
var GS = null
var PM = null
var RE = null
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
	return _unit(uid).get("flags", {})


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


## Snapshot every model position once, so sections can restore the fixture
## geometry after moving units.
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
		u.erase("embarked_in")
		u["status"] = GS.UnitStatus.DEPLOYED
		if u.has("transport_data"):
			u.transport_data["embarked_units"] = []


func _place(uid: String, points_in: Array) -> void:
	var models: Array = _unit(uid).get("models", [])
	for i in range(models.size()):
		if i < points_in.size():
			var p: Vector2 = points_in[i]
			models[i]["position"] = {"x": p.x * PX, "y": p.y * PX}


func _row(x0: float, y: float, n: int, dx: float) -> Array:
	var out: Array = []
	for i in range(n):
		out.append(Vector2(x0 + i * dx, y))
	return out


func _reset_usage(cp: int = 6) -> void:
	SM._usage_history = {"1": [], "2": []}
	SM.active_effects = []
	GS.state.players["1"]["cp"] = cp
	GS.state.players["2"]["cp"] = cp


func _no_phase_advance(phase) -> void:
	# Keep the Fight phase current when it completes (the test inspects it);
	# record the completion instead.
	_phase_done = false
	if phase.phase_completed.is_connected(PM._on_phase_completed):
		phase.phase_completed.disconnect(PM._on_phase_completed)
	phase.phase_completed.connect(func(): _phase_done = true)


## Fresh Fight phase. `prep` runs between the Command phase and the Fight
## phase entry (flags/positions the FightSequencer must see at phase start).
func _fresh_fight(prep: Callable = Callable()):
	_reset_usage()
	PM.transition_to_phase(PHASE_COMMAND)
	if prep.is_valid():
		prep.call()
	PM.transition_to_phase(PHASE_FIGHT)
	var phase = PM.get_current_phase_instance()
	_no_phase_advance(phase)
	if not phase.stratagem_window_opened.is_connected(_on_window_opened):
		phase.stratagem_window_opened.connect(_on_window_opened)
	for _i in [1, 2]:
		if int(phase.pile_in_step_11e) != int(phase.PileInStep11e.ACTIVE):
			break
		phase.execute_action({"type": "END_PILE_IN", "player": int(phase.piling_in_player_11e)})
	return phase


## Walk the phase to its end (Fight step -> Consolidate step -> end-of-phase
## triggers) until a window pends or the phase completes.
func _drive_to_phase_end(phase) -> void:
	for _i in range(8):
		if phase.has_pending_stratagem_window() or _phase_done:
			return
		var who := int(GS.get_active_player())
		if int(phase.consolidation_step_11e) == int(phase.ConsolidationStep11e.ACTIVE):
			who = int(phase.consolidating_player_11e)
		phase.execute_action({"type": "END_FIGHT", "player": who})


func _melee_board(attacker_flags: Dictionary, attacker_kw: Array, weapon: Dictionary, n_att: int, n_tgt: int) -> Dictionary:
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
			"meta": {"name": "Attackers", "keywords": attacker_kw, "stats": {"toughness": 5, "save": 6, "wounds": 3},
				"abilities": [], "weapons": [weapon]},
			"flags": attacker_flags, "models": atk},
		"U_TGT": {"id": "U_TGT", "owner": 2,
			"meta": {"name": "Targets", "keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 3, "wounds": 3}, "abilities": []},
			"flags": {}, "models": tgt},
	}, "meta": {"phase": 10, "active_player": 1, "battle_round": 2}}


func _melee_result(board: Dictionary, weapon_name: String, seed_val: int) -> Dictionary:
	RE.set_test_seed(seed_val)
	var rng = RE.RNGService.new()
	return RE.resolve_melee_attacks({"type": "FIGHT", "actor_unit_id": "U_ATK",
		"payload": {"assignments": [{"attacker": "U_ATK", "target": "U_TGT", "weapon": weapon_name}]}}, board, rng)


func _hit_block(result: Dictionary) -> Dictionary:
	for d in result.get("dice", []):
		if str(d.get("context", "")) == "hit_roll_melee":
			return d
	return {}


func _cleaver(rules: String) -> Dictionary:
	return {"name": "Test Cleaver", "type": "Melee", "range": "Melee", "attacks": "3", "weapon_skill": "3",
		"strength": "5", "ap": "-1", "damage": "1", "special_rules": rules}


# ---------------------------------------------------------------------------
func _run() -> void:
	SM = root.get_node("StratagemManager")
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	Fight = load("res://scripts/stratagems/ork_codex/OrkCodexFight.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	GS.set_edition(11)

	print("\n=== test_ork_codex_fight ===\n")
	_check("fixture %s loads" % FIXTURE, _stage_fixture())
	GS.set_edition(11)
	root.get_node("SettingsService").set("auto_allocate_wounds", true)
	_remember_positions()

	_section_registry()
	_section_mow_em_down()
	_section_unbridled_carnage()
	_section_armed_to_da_teef()
	_section_enemy_targets_and_oinb()
	_section_fod_edges()
	_section_fod_target_gates()
	_section_keep_it_runnin()
	_section_instinctive_hunters()
	_section_ai()
	_section_scoring_repositioned()


# ---------------------------------------------------------------------------
func _section_registry() -> void:
	print("\n-- A. registry --")
	var Codex = load("res://scripts/stratagems/ork_codex/OrkCodex11e.gd")
	var impl: Array = Codex.all_implemented_ids()
	for csv in [CSV_HIT, CSV_MOW, CSV_UC, CSV_ATDT, CSV_OINB, CSV_TATD, CSV_CR, CSV_KIR, CSV_IH]:
		_check("%s implemented" % csv, csv in impl and Fight.IMPLEMENTED.get(csv, false))
		_check("%s has an ai kind" % csv, Fight.AI_KIND.has(csv))


# ---------------------------------------------------------------------------
func _section_mow_em_down() -> void:
	print("\n-- B. MOW 'EM DOWN --")
	_set_detachment(1, "War Horde")
	var sid := _sid(1, CSV_MOW)
	_check("MOW 'EM DOWN loaded (War Horde)", sid != "")
	var phase = _fresh_fight()
	var bw := "U_BATTLEWAGON_A"
	var ctx := {"phase": "fight", "unit_id": bw}
	var offers = SM.get_window_offers(1, "unit_selected_to_fight", ctx)
	_check("not offered: Battlewagon has not made a charge move", not sid in _offer_ids(offers), str(_offer_ids(offers)))
	_flags(bw)["charged_this_turn"] = true
	offers = SM.get_window_offers(1, "unit_selected_to_fight", ctx)
	_check("offered: charged ORKS VEHICLE selected to fight", sid in _offer_ids(offers) and _offer_targets(offers, sid) == [bw], str(offers))
	_flags("U_DEFF_DREAD_A")["charged_this_turn"] = true
	_check("not offered: WALKER (Deff Dread) even if charged", not sid in _offer_ids(SM.get_window_offers(1, "unit_selected_to_fight", {"unit_id": "U_DEFF_DREAD_A"})))
	_flags("U_BOYZ_B")["charged_this_turn"] = true
	_check("not offered: non-VEHICLE (Boyz)", not sid in _offer_ids(SM.get_window_offers(1, "unit_selected_to_fight", {"unit_id": "U_BOYZ_B"})))
	_check("not offered: in another window", not sid in _offer_ids(SM.get_window_offers(1, "unit_selected_to_shoot", ctx)))
	_check("not offered to P2", SM.get_window_offers(2, "unit_selected_to_fight", ctx).is_empty())
	var r = SM.can_use_stratagem(1, sid, bw)
	_check("S panel (no window) refused with 'Offered automatically…'", not r.can_use and "Offered automatically" in str(r.reason), str(r))
	r = SM.can_use_stratagem(1, sid, "U_TRUKK_A", {"window_id": "unit_selected_to_fight", "unit_id": bw})
	_check("must target the unit selected to fight", not r.can_use, str(r))

	var cp0 := _cp(1)
	_check("window opens (pauses) for the human", phase.open_stratagem_window(1, "unit_selected_to_fight", {"phase": "fight", "unit_id": bw}, ""))
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_fight", "stratagem_id": sid, "target_unit_id": bw})
	_check("USE succeeds", use.get("success", false), str(use.get("error", "")))
	_check("CP -1", _cp(1) == cp0 - 1, "%d -> %d" % [cp0, _cp(1)])
	_check("flag ork11e_mow_em_down on the Battlewagon", bool(_flags(bw).get("ork11e_mow_em_down", false)))

	# A/B: [CLEAVE 2] -> [CLEAVE 3], no CLEAVE -> [CLEAVE 1]; 10-model target = 2 × X dice.
	var off_b = _melee_board({}, ["ORKS", "VEHICLE"], _cleaver("cleave 2"), 1, 10)
	var on_b = _melee_board({"ork11e_mow_em_down": true}, ["ORKS", "VEHICLE"], _cleaver("cleave 2"), 1, 10)
	var a_off = int(_hit_block(_melee_result(off_b, "Test Cleaver", 7001)).get("total_attacks", -1))
	var a_on = int(_hit_block(_melee_result(on_b, "Test Cleaver", 7001)).get("total_attacks", -1))
	_check("[CLEAVE 2] vs 10 models: 3 A + 4 dice = 7", a_off == 7, str(a_off))
	_check("MOW 'EM DOWN: [CLEAVE 3] vs 10 models: 3 A + 6 dice = 9", a_on == 9, str(a_on))
	var n_off = int(_hit_block(_melee_result(_melee_board({}, ["ORKS", "VEHICLE"], _cleaver(""), 1, 10), "Test Cleaver", 7002)).get("total_attacks", -1))
	var n_on = int(_hit_block(_melee_result(_melee_board({"ork11e_mow_em_down": true}, ["ORKS", "VEHICLE"], _cleaver(""), 1, 10), "Test Cleaver", 7002)).get("total_attacks", -1))
	_check("no [CLEAVE]: 3 attack dice", n_off == 3, str(n_off))
	_check("MOW 'EM DOWN grants [CLEAVE 1]: +2 dice vs 10 models", n_on == 5, str(n_on))
	var small = int(_hit_block(_melee_result(_melee_board({"ork11e_mow_em_down": true}, ["ORKS", "VEHICLE"], _cleaver(""), 1, 4), "Test Cleaver", 7003)).get("total_attacks", -1))
	_check("[CLEAVE 1] vs 4 models: no extra dice", small == 3, str(small))

	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry: ork11e_mow_em_down cleared at end of phase", not _flags(bw).has("ork11e_mow_em_down"))
	_restore_unit_state()


# ---------------------------------------------------------------------------
func _section_unbridled_carnage() -> void:
	print("\n-- C. UNBRIDLED CARNAGE --")
	_set_detachment(1, "Green Tide")
	var sid := _sid(1, CSV_UC)
	_check("UNBRIDLED CARNAGE loaded (Green Tide)", sid != "")
	var phase = _fresh_fight()
	var ctx := {"phase": "fight", "unit_id": "U_BOYZ_B"}
	_check("not offered: Boyz did not charge", not sid in _offer_ids(SM.get_window_offers(1, "unit_selected_to_fight", ctx)))
	_flags("U_BOYZ_B")["charged_this_turn"] = true
	var offers = SM.get_window_offers(1, "unit_selected_to_fight", ctx)
	_check("offered: BOYZ unit that charged", _offer_targets(offers, sid) == ["U_BOYZ_B"], str(offers))
	_flags("U_NOBZ_A")["charged_this_turn"] = true
	_check("not offered: NOBZ (no BOYZ keyword)", not sid in _offer_ids(SM.get_window_offers(1, "unit_selected_to_fight", {"unit_id": "U_NOBZ_A"})))
	_flags("U_BEAST_SNAGGA_BOYZ_A")["charged_this_turn"] = true
	_check("not offered: BEAST SNAGGA BOYZ (keyword is not BOYZ)", not sid in _offer_ids(SM.get_window_offers(1, "unit_selected_to_fight", {"unit_id": "U_BEAST_SNAGGA_BOYZ_A"})))

	var cp0 := _cp(1)
	# Real hook: SELECT_FIGHTER opens the window.
	_window_events.clear()
	var sel = phase.execute_action({"type": "SELECT_FIGHTER", "unit_id": "U_BOYZ_B", "player": 1})
	_check("SELECT_FIGHTER Boyz opens unit_selected_to_fight", sel.get("success", false) and phase.has_pending_stratagem_window()
		and str(phase.get_pending_stratagem_window().get("window_id", "")) == "unit_selected_to_fight", str(sel.get("error", "")))
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_fight", "stratagem_id": sid, "target_unit_id": "U_BOYZ_B"})
	_check("USE succeeds", use.get("success", false), str(use.get("error", "")))
	_check("CP -1", _cp(1) == cp0 - 1)
	_check("+1 A flag on the Boyz", int(_flags("U_BOYZ_B").get("ork11e_plus_attacks_melee", 0)) == 1)
	_check("+1 A flag on the attached Warboss (one unit)", int(_flags("U_WARBOSS_A").get("ork11e_plus_attacks_melee", 0)) == 1)
	_check("activation resumed (attack assignment)", use.get("trigger_attack_assignment", false), str(use.keys()))

	var w := {"name": "Test Choppa", "type": "Melee", "range": "Melee", "attacks": "2", "weapon_skill": "3", "strength": "4", "ap": "0", "damage": "1", "special_rules": ""}
	var a_off = int(_hit_block(_melee_result(_melee_board({}, ["ORKS", "BOYZ"], w, 5, 5), "Test Choppa", 7101)).get("total_attacks", -1))
	var a_on = int(_hit_block(_melee_result(_melee_board({"ork11e_plus_attacks_melee": 1}, ["ORKS", "BOYZ"], w, 5, 5), "Test Choppa", 7101)).get("total_attacks", -1))
	_check("A/B: 5 models x A2 = 10 attacks", a_off == 10, str(a_off))
	_check("A/B: UNBRIDLED CARNAGE 5 models x A3 = 15 attacks", a_on == 15, str(a_on))
	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry: +1 A cleared (Boyz + Warboss)", not _flags("U_BOYZ_B").has("ork11e_plus_attacks_melee") and not _flags("U_WARBOSS_A").has("ork11e_plus_attacks_melee"))
	_restore_unit_state()


# ---------------------------------------------------------------------------
func _section_armed_to_da_teef() -> void:
	print("\n-- D. ARMED TO DA TEEF --")
	_set_detachment(1, "Bully Boyz")
	var sid := _sid(1, CSV_ATDT)
	_check("ARMED TO DA TEEF loaded (Bully Boyz)", sid != "")
	var phase = _fresh_fight()
	var offers = SM.get_window_offers(1, "unit_selected_to_fight", {"unit_id": "U_NOBZ_A"})
	_check("fight window: offered on Nobz", _offer_targets(offers, sid) == ["U_NOBZ_A"], str(offers))
	_check("fight window: offered on Meganobz", _offer_targets(SM.get_window_offers(1, "unit_selected_to_fight", {"unit_id": "U_MEGANOBZ_A"}), sid) == ["U_MEGANOBZ_A"])
	_check("fight window: not offered on Boyz", not sid in _offer_ids(SM.get_window_offers(1, "unit_selected_to_fight", {"unit_id": "U_BOYZ_B"})))
	_check("not offered in enemy_targets_unit_fight", not sid in _offer_ids(SM.get_window_offers(1, "enemy_targets_unit_fight", {"attacker_unit_id": "U_CUSTODIAN_GUARD_B", "target_unit_ids": ["U_NOBZ_A"]})))
	# Opponent's Fight phase: either player's turn — still offered.
	GS.state.meta["active_player"] = 2
	_check("fight window in the opponent's turn: offered", _offer_targets(SM.get_window_offers(1, "unit_selected_to_fight", {"unit_id": "U_NOBZ_A"}), sid) == ["U_NOBZ_A"])
	GS.state.meta["active_player"] = 1

	var cp0 := _cp(1)
	phase.open_stratagem_window(1, "unit_selected_to_fight", {"phase": "fight", "unit_id": "U_NOBZ_A"}, "")
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_fight", "stratagem_id": sid, "target_unit_id": "U_NOBZ_A"})
	_check("USE (fight) succeeds", use.get("success", false), str(use.get("error", "")))
	_check("CP -1", _cp(1) == cp0 - 1)
	_check("not riled up: re-roll hit rolls of 1", str(_flags("U_NOBZ_A").get("effect_reroll_hits", "")) == "ones", str(_flags("U_NOBZ_A")))
	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry: re-roll + marker cleared", not _flags("U_NOBZ_A").has("effect_reroll_hits") and not _flags("U_NOBZ_A").has("ork11e_armed_to_da_teef"))

	# Riled up -> re-roll all hit rolls.
	phase = _fresh_fight()
	_flags("U_MEGANOBZ_A")["waaagh_active"] = true
	phase.open_stratagem_window(1, "unit_selected_to_fight", {"phase": "fight", "unit_id": "U_MEGANOBZ_A"}, "")
	phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_fight", "stratagem_id": sid, "target_unit_id": "U_MEGANOBZ_A"})
	_check("riled up: re-roll ALL hit rolls", str(_flags("U_MEGANOBZ_A").get("effect_reroll_hits", "")) == "all", str(_flags("U_MEGANOBZ_A")))
	SM.on_phase_end(PHASE_FIGHT)

	# A better existing re-roll is never downgraded nor removed by clear().
	phase = _fresh_fight()
	_flags("U_NOBZ_A")["effect_reroll_hits"] = "failed"
	phase.open_stratagem_window(1, "unit_selected_to_fight", {"phase": "fight", "unit_id": "U_NOBZ_A"}, "")
	phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_fight", "stratagem_id": sid, "target_unit_id": "U_NOBZ_A"})
	_check("existing 'failed' re-roll kept (not downgraded to 'ones')", str(_flags("U_NOBZ_A").get("effect_reroll_hits", "")) == "failed")
	SM.on_phase_end(PHASE_FIGHT)
	_check("clear() leaves the other source's re-roll alone", str(_flags("U_NOBZ_A").get("effect_reroll_hits", "")) == "failed")
	_flags("U_NOBZ_A").erase("effect_reroll_hits")

	# A/B (melee): re-roll 1s / all never reduce hits; with failures present they add hits.
	var w := {"name": "Test Klaw", "type": "Melee", "range": "Melee", "attacks": "4", "weapon_skill": "4", "strength": "6", "ap": "-1", "damage": "1", "special_rules": ""}
	var base_h := 0
	var ones_h := 0
	var all_h := 0
	var never_lower := true
	for s in range(20):
		var a = int(_hit_block(_melee_result(_melee_board({}, ["ORKS", "NOBZ"], w, 5, 5), "Test Klaw", 7200 + s)).get("successes", 0))
		var b = int(_hit_block(_melee_result(_melee_board({"effect_reroll_hits": "ones"}, ["ORKS", "NOBZ"], w, 5, 5), "Test Klaw", 7200 + s)).get("successes", 0))
		var c = int(_hit_block(_melee_result(_melee_board({"effect_reroll_hits": "all"}, ["ORKS", "NOBZ"], w, 5, 5), "Test Klaw", 7200 + s)).get("successes", 0))
		base_h += a
		ones_h += b
		all_h += c
		if b < a or c < a:
			never_lower = false
	_check("A/B same seeds: re-rolls never give fewer hits", never_lower)
	_check("A/B: re-roll 1s adds hits (%d -> %d over 20 seeds)" % [base_h, ones_h], ones_h > base_h)
	_check("A/B: re-roll all >= re-roll 1s (%d vs %d)" % [all_h, ones_h], all_h >= ones_h)

	# unit_selected_to_shoot (hook added by the SHOOTING group): handler + offers API.
	_reset_usage()
	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(PHASE_SHOOTING)
	var sctx := {"phase": "shooting", "unit_id": "U_NOBZ_A"}
	offers = SM.get_window_offers(1, "unit_selected_to_shoot", sctx)
	_check("shoot window (your Shooting phase): offered on Nobz", _offer_targets(offers, sid) == ["U_NOBZ_A"], str(offers))
	_check("shoot window: not offered on Boyz", not sid in _offer_ids(SM.get_window_offers(1, "unit_selected_to_shoot", {"unit_id": "U_BOYZ_B"})))
	var rs = SM.can_use_stratagem(1, sid, "U_NOBZ_A", {"window_id": "unit_selected_to_shoot", "unit_id": "U_NOBZ_A"})
	_check("shoot window: can_use ok", rs.can_use, str(rs))
	GS.state.meta["active_player"] = 2
	rs = SM.can_use_stratagem(1, sid, "U_NOBZ_A", {"window_id": "unit_selected_to_shoot", "unit_id": "U_NOBZ_A"})
	_check("opponent's Shooting phase: refused (\"your Shooting phase\")", not rs.can_use and "your own Shooting phase" in str(rs.reason), str(rs))
	GS.state.meta["active_player"] = 1
	cp0 = _cp(1)
	var su = SM.use_stratagem(1, sid, "U_NOBZ_A", {"window_id": "unit_selected_to_shoot", "unit_id": "U_NOBZ_A"})
	_check("shoot window: use succeeds, -1 CP, re-roll 1s for the ranged attacks", su.get("success", false) and _cp(1) == cp0 - 1
		and str(_flags("U_NOBZ_A").get("effect_reroll_hits", "")) == "ones", str(su.get("error", "")))
	SM.on_phase_end(PHASE_SHOOTING)
	_check("shoot window: expires at the end of the Shooting phase", not _flags("U_NOBZ_A").has("effect_reroll_hits"))
	_restore_unit_state()


# ---------------------------------------------------------------------------
func _cg_a_first() -> void:
	_flags("U_CUSTODIAN_GUARD_A")["fights_first"] = true
	_flags("U_CUSTODIAN_GUARD_A")["charged_this_turn"] = true


func _boyz_model_states() -> Dictionary:
	var out := {"alive": 0, "dead": 0, "pending": [], "zero_w_alive": 0}
	var models: Array = _unit("U_BOYZ_B").get("models", [])
	for i in range(models.size()):
		var m = models[i]
		if m.get("alive", true):
			out.alive += 1
			if int(m.get("current_wounds", 1)) <= 0:
				out.zero_w_alive += 1
		else:
			out.dead += 1
	out.pending = _flags("U_BOYZ_B").get("ork11e_fod_pending", [])
	return out


func _section_enemy_targets_and_oinb() -> void:
	print("\n-- E. enemy_targets_unit_fight + ORKS IS NEVER BEATEN (Fight On Death) --")
	_set_detachment(1, "War Horde")
	var sid := _sid(1, CSV_OINB)
	_check("ORKS IS NEVER BEATEN loaded (War Horde)", sid != "")
	var phase = _fresh_fight(Callable(self, "_cg_a_first"))
	var sel = phase.sequencer_11e.peek_selection(GS.state)
	_check("Custodian Guard A (Fights First) — P2 picks first", int(sel.player) == 2 and "U_CUSTODIAN_GUARD_A" in sel.candidates, str(sel))
	var r = phase.execute_action({"type": "SELECT_FIGHTER", "unit_id": "U_CUSTODIAN_GUARD_A", "player": 2})
	_check("P2 selects Custodian Guard A", r.get("success", false) and not phase.has_pending_stratagem_window(), str(r.get("error", "")))
	var batch := {"type": "BATCH_FIGHT_ACTIONS", "player": 2, "sub_actions": [
		{"type": "ASSIGN_ATTACKS", "unit_id": "U_CUSTODIAN_GUARD_A", "target_id": "U_BOYZ_B", "weapon_id": "Guardian spear – Melee", "attacking_models": [], "player": 2},
		{"type": "CONFIRM_AND_RESOLVE_ATTACKS", "player": 2},
		{"type": "ROLL_DICE", "player": 2, "payload": {"fast_roll": true}}]}
	_window_events.clear()
	r = phase.execute_action(batch)
	_check("BATCH succeeds and pauses at CONFIRM", r.get("success", false) and phase.has_pending_stratagem_window(), str(r.get("error", "")))
	var pend: Dictionary = phase.get_pending_stratagem_window()
	_check("window enemy_targets_unit_fight for P1 (owner of the target)", str(pend.get("window_id", "")) == "enemy_targets_unit_fight" and int(pend.get("player", 0)) == 1, str(pend.get("window_id", "")))
	_check("ctx: attacker + targets", str(pend.get("ctx", {}).get("attacker_unit_id", "")) == "U_CUSTODIAN_GUARD_A" and pend.get("ctx", {}).get("target_unit_ids", []) == ["U_BOYZ_B"], str(pend.get("ctx", {})))
	var offers: Array = pend.get("offers", [])
	_check("ORKS IS NEVER BEATEN offered on the Boyz", _offer_targets(offers, sid) == ["U_BOYZ_B"], str(offers))
	_check("no attacks rolled yet (held ROLL_DICE)", phase.confirmed_attacks.size() > 0 and not "U_CUSTODIAN_GUARD_A" in phase.units_that_fought)
	_check("result stamped for the network mirror", r.has("stratagem_window_opened"))
	var blocked = phase.execute_action({"type": "ROLL_DICE", "player": 2, "payload": {"fast_roll": true}})
	_check("attacker cannot roll while the window waits", not blocked.get("success", true))
	var wrong = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 2, "window_id": "enemy_targets_unit_fight", "stratagem_id": sid, "target_unit_id": "U_BOYZ_B"})
	_check("USE by the attacker refused", not wrong.get("success", true))
	_check("not offered for an untargeted unit", not SM.can_use_stratagem(1, sid, "U_NOBZ_A", pend.ctx.merged({"window_id": "enemy_targets_unit_fight"})).can_use)

	var cp0 := _cp(1)
	var before := _boyz_model_states()
	RE.set_test_seed(4242)
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "enemy_targets_unit_fight", "stratagem_id": sid, "target_unit_id": "U_BOYZ_B"})
	_check("USE succeeds", use.get("success", false), str(use.get("error", "")))
	_check("CP -1 (P1)", _cp(1) == cp0 - 1)
	_check("Fight On Death marked on Boyz + attached Warboss", str(_flags("U_BOYZ_B").get("ork11e_fod_mode", "")) == "riled_up" and str(_flags("U_WARBOSS_A").get("ork11e_fod_mode", "")) == "riled_up")
	_check("held ROLL_DICE ran on resume: Custodian Guard A has fought", "U_CUSTODIAN_GUARD_A" in phase.units_that_fought, str(phase.units_that_fought))
	var fod_rolls: Array = phase.dice_log.filter(func(d): return typeof(d) == TYPE_DICTIONARY and str(d.get("context", "")) == "ork11e_fight_on_death")
	var after := _boyz_model_states()
	var destroyed: int = before.alive - after.alive + after.pending.size()
	print("    Boyz before %s after %s, FOD rolls %d" % [str(before), str(after), fod_rolls.size()])
	_check("the attack destroyed Boyz (seeded)", destroyed > 0, str(after))
	_check("one D6 per destroyed Boyz model", fod_rolls.size() == destroyed, "%d rolls vs %d destroyed" % [fod_rolls.size(), destroyed])
	var kept := 0
	for d in fod_rolls:
		if d.get("kept", false):
			kept += 1
		_check("roll %d%+d -> kept=%s matches the 4+ rule" % [int(d.rolls_raw[0]), int(d.modifier), str(d.kept)],
			bool(d.kept) == (int(d.rolls_raw[0]) + int(d.modifier) >= 4))
	_check("kept models are listed as pending", after.pending.size() == kept, "%s vs %d" % [str(after.pending), kept])
	_check("kept models stay on the battlefield (alive, 0 wounds)", after.zero_w_alive == kept)
	_check("game log shows the rolls", ScenarioLogCount("ORKS IS NEVER BEATEN") >= 1)
	if kept == 0:
		print("    (seed produced no kept model — forcing one for the rest of the section)")
		var forced := -1
		var models: Array = _unit("U_BOYZ_B").models
		for i in range(models.size()):
			if not models[i].get("alive", true):
				forced = i
				break
		if forced >= 0:
			models[forced]["alive"] = true
			models[forced]["current_wounds"] = 0
			_flags("U_BOYZ_B")["ork11e_fod_pending"] = [forced]
	var pend_idx: Array = _flags("U_BOYZ_B").get("ork11e_fod_pending", [])

	# Destroyed-but-not-removed: never allocated again.
	var board = GS.state.duplicate(true)
	RE.set_test_seed(99)
	var again = RE.resolve_melee_attacks({"type": "FIGHT", "actor_unit_id": "U_CUSTODIAN_GUARD_A", "payload": {"assignments": [
		{"attacker": "U_CUSTODIAN_GUARD_A", "target": "U_BOYZ_B", "weapon": "Guardian spear – Melee"}]}}, board, RE.RNGService.new())
	var touched_pending := false
	for d in again.get("diffs", []):
		for pi in pend_idx:
			if str(d.get("path", "")).begins_with("units.U_BOYZ_B.models.%d." % int(pi)):
				touched_pending = true
	_check("a later attack never allocates to a kept (destroyed) model", not touched_pending)
	# Interactive defender path (AllocationGroupOverlay -> resolve_allocation_batch_11e).
	var sd := {"target_unit_id": "U_BOYZ_B", "shooter_unit_id": "U_CUSTODIAN_GUARD_A", "wounds_to_save": 12, "ap": -2, "damage_raw": "2", "damage": 2}
	var alloc_batch = RE.resolve_allocation_batch_11e(sd, [], GS.state.duplicate(true), RE.RNGService.new(31))
	var in_groups := false
	for g in alloc_batch.get("groups", []):
		for vi in g.get("model_indices", []):
			var src = alloc_batch.sources[int(vi)]
			if str(src.unit_id) == "U_BOYZ_B" and int(src.model_index) in pend_idx.map(func(v): return int(v)):
				in_groups = true
	var batch_touch := false
	for d in alloc_batch.get("diffs", []):
		for pi in pend_idx:
			if str(d.get("path", "")).begins_with("units.U_BOYZ_B.models.%d." % int(pi)):
				batch_touch = true
	_check("interactive allocation: kept models are in no allocation group", not in_groups)
	_check("interactive allocation: no damage on kept models", not batch_touch)

	# Kept models fight with their unit.
	# (Only those in Engagement Range / base-contact chain can fight — the
	# normal 11e per-model eligibility; a kept model is treated like any other.)
	var eligible = RE.get_eligible_melee_model_indices(_unit("U_BOYZ_B"), GS.state)
	var kept_eligible := 0
	var only_alive := true
	for ei in eligible:
		if int(ei) in pend_idx.map(func(v): return int(v)):
			kept_eligible += 1
		if not _unit("U_BOYZ_B").models[int(ei)].get("alive", true):
			only_alive = false
	_check("kept models in Engagement Range are eligible to fight", kept_eligible > 0 and only_alive, "%s vs eligible %s" % [str(pend_idx), str(eligible)])
	_check("no kill recorded while models are kept", not phase._kill_reported_units.has("U_BOYZ_B"))

	# P1 now picks: the Boyz fight (HIT 'EM HARDER window declined), then the kept models are removed.
	r = phase.execute_action({"type": "SELECT_FIGHTER", "unit_id": "U_BOYZ_B", "player": 1})
	_check("P1 selects the Boyz", r.get("success", false), str(r.get("error", "")))
	if phase.has_pending_stratagem_window():
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 1, "window_id": str(phase.get_pending_stratagem_window().get("window_id", ""))})
	var b2 := {"type": "BATCH_FIGHT_ACTIONS", "player": 1, "sub_actions": [
		{"type": "ASSIGN_ATTACKS", "unit_id": "U_BOYZ_B", "target_id": "U_CUSTODIAN_GUARD_A", "weapon_id": "Choppa", "attacking_models": [], "player": 1},
		{"type": "CONFIRM_AND_RESOLVE_ATTACKS", "player": 1},
		{"type": "ROLL_DICE", "player": 1, "payload": {"fast_roll": true}}]}
	r = phase.execute_action(b2)
	_check("Boyz fight resolves", r.get("success", false) and "U_BOYZ_B" in phase.units_that_fought, str(r.get("error", "")))
	var removed_all := true
	for pi in pend_idx:
		if _unit("U_BOYZ_B").models[int(pi)].get("alive", true):
			removed_all = false
	_check("after the unit has fought, kept models are removed", removed_all and _flags("U_BOYZ_B").get("ork11e_fod_pending", []).is_empty())
	_check("removal logged", ScenarioLogCount("removed from the battlefield (has fought)") >= 1)
	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry: Fight On Death marker cleared", not _flags("U_BOYZ_B").has("ork11e_fod_mode"))
	_restore_unit_state()


func ScenarioLogCount(fragment: String) -> int:
	var sr = root.get_node_or_null("ScenarioRunner")
	if sr and sr.has_method("event_log_count_containing"):
		return int(sr.event_log_count_containing(fragment))
	var gel = root.get_node_or_null("GameEventLog")
	var n := 0
	if gel and "entries" in gel:
		for e in gel.entries:
			if fragment in str(e.get("text", "")):
				n += 1
	return n


# ---------------------------------------------------------------------------
func _section_fod_edges() -> void:
	print("\n-- F. Fight On Death edge cases --")
	_set_detachment(1, "Dread Mob")
	var cr := _sid(1, CSV_CR)
	_check("CRAZED RAMPAGE loaded (Dread Mob)", cr != "")
	var phase = _fresh_fight()
	_check("CRAZED RAMPAGE offered on the Deff Dread", _offer_targets(SM.get_window_offers(1, "enemy_targets_unit_fight",
		{"attacker_unit_id": "U_PROSECUTORS_A", "target_unit_ids": ["U_DEFF_DREAD_A"]}), cr) == ["U_DEFF_DREAD_A"])
	phase.open_stratagem_window(1, "enemy_targets_unit_fight", {"phase": "fight", "attacker_unit_id": "U_PROSECUTORS_A", "target_unit_ids": ["U_DEFF_DREAD_A"]}, "")
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "enemy_targets_unit_fight", "stratagem_id": cr, "target_unit_id": "U_DEFF_DREAD_A"})
	_check("CRAZED RAMPAGE used", use.get("success", false), str(use.get("error", "")))
	_check("mode deff_dread", str(_flags("U_DEFF_DREAD_A").get("ork11e_fod_mode", "")) == "deff_dread")
	_check("DEFF DREAD: +3 to the roll", int(Fight.fod_roll_modifier("U_DEFF_DREAD_A").mod) == 3)
	_flags("U_KILLA_KANS_A")["ork11e_fod_mode"] = "deff_dread"
	_check("Killa Kans (WALKER, no DEFF DREAD): +0", int(Fight.fod_roll_modifier("U_KILLA_KANS_A").mod) == 0)
	_flags("U_KILLA_KANS_A").erase("ork11e_fod_mode")
	_flags("U_NOBZ_A")["ork11e_fod_mode"] = "riled_up"
	_check("not riled up: +0", int(Fight.fod_roll_modifier("U_NOBZ_A").mod) == 0)
	_flags("U_NOBZ_A")["waaagh_active"] = true
	_check("riled up (Waaagh!): +1", int(Fight.fod_roll_modifier("U_NOBZ_A").mod) == 1)
	_flags("U_NOBZ_A").erase("waaagh_active")
	_flags("U_NOBZ_A")["ork11e_riled_up"] = true
	_check("riled up (ork11e_riled_up): +1", int(Fight.fod_roll_modifier("U_NOBZ_A").mod) == 1)

	# The Deff Dread is destroyed (e.g. by mortal wounds): D6+3 always passes.
	var diffs: Array = [
		{"op": "set", "path": "units.U_DEFF_DREAD_A.models.0.current_wounds", "value": 0},
		{"op": "set", "path": "units.U_DEFF_DREAD_A.models.0.alive", "value": false}]
	phase._ork11e_fod_intercept(diffs)
	_check("Deff Dread kept (D6+3 >= 4)", diffs[1].value == true and _has_pending_diff(diffs, "U_DEFF_DREAD_A", [0]), str(diffs))
	PM.apply_state_changes(diffs)
	_check("Deff Dread on the battlefield, 0 wounds, pending", _unit("U_DEFF_DREAD_A").models[0].get("alive", false) and int(_unit("U_DEFF_DREAD_A").models[0].current_wounds) == 0)
	var again: Array = [{"op": "set", "path": "units.U_DEFF_DREAD_A.models.0.alive", "value": false}]
	var n_rolls: int = phase.dice_log.size()
	phase._ork11e_fod_intercept(again)
	_check("the same model is never rolled for twice", phase.dice_log.size() == n_rolls and again[0].value == false)
	_check("a rolled diff carries the travelling marker", diffs[1].get("ork11e_fod_rolled", false))
	_flags("U_KILLA_KANS_A")["ork11e_fod_mode"] = "riled_up"
	var marked: Array = [{"op": "set", "path": "units.U_KILLA_KANS_A.models.0.alive", "value": false, "ork11e_fod_rolled": true}]
	phase._ork11e_fod_intercept(marked)
	_check("a diff already rolled on another peer (marker) is not rolled again", phase.dice_log.size() == n_rolls and marked[0].value == false)
	_flags("U_KILLA_KANS_A").erase("ork11e_fod_mode")

	# Selected-to-fight gate: Nobz selected -> a destroyed Nobz is removed, no roll.
	phase._ork11e_selected_to_fight["U_NOBZ_A"] = true
	var nd: Array = [{"op": "set", "path": "units.U_NOBZ_A.models.1.alive", "value": false}]
	n_rolls = phase.dice_log.size()
	phase._ork11e_fod_intercept(nd)
	_check("unit already selected to fight: no roll, model removed", phase.dice_log.size() == n_rolls and nd[0].value == false)
	phase._ork11e_selected_to_fight.erase("U_NOBZ_A")
	_flags("U_NOBZ_A").erase("ork11e_fod_mode")
	_flags("U_NOBZ_A").erase("ork11e_riled_up")

	# End-of-phase removal: the Deff Dread never fought -> removed at the end of
	# the phase, its destruction processed exactly once.
	var mm = root.get_node("MissionManager")
	var kills_before := int(mm._kills_this_round.get("2", 0))
	_drive_to_phase_end(phase)
	if phase.has_pending_stratagem_window():
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(phase.get_pending_stratagem_window_decider()), "window_id": "fight_phase_end"})
		_drive_to_phase_end(phase)
	_check("Deff Dread removed at the end of the phase", not _unit("U_DEFF_DREAD_A").models[0].get("alive", true) and _flags("U_DEFF_DREAD_A").get("ork11e_fod_pending", []).is_empty())
	_check("phase completed", _phase_done)
	_check("kill credited once, to the Deff Dread's opponent (P2)", int(mm._kills_this_round.get("2", 0)) == kills_before + 1, "%d -> %d" % [kills_before, int(mm._kills_this_round.get("2", 0))])
	phase._check_kill_diffs([{"op": "set", "path": "units.U_DEFF_DREAD_A.models.0.alive", "value": false}])
	_check("a repeated kill hook does not count it again", int(mm._kills_this_round.get("2", 0)) == kills_before + 1)
	SM.on_phase_end(PHASE_FIGHT)
	_restore_unit_state()

	# Interactive defender path: the AllocationGroupOverlay rolls the Fight On
	# Death D6s BEFORE applying its batch (bodyguard / destroyed checks see the
	# kept models) and its APPLY_MELEE_SAVES summary carries marked diffs.
	phase = _fresh_fight()
	for uid in ["U_BOYZ_B", "U_WARBOSS_A"]:
		_flags(uid)["ork11e_fod_mode"] = "riled_up"
		_flags(uid)["waaagh_active"] = true
	var Ovl = load("res://scripts/AllocationGroupOverlay.gd")
	var ov = Ovl.new()
	root.add_child(ov)
	var summary := {}
	ov.allocation_complete.connect(func(s): summary.merge(s, true))
	var rolls_before: int = phase.dice_log.size()
	ov.setup({"target_unit_id": "U_BOYZ_B", "target_unit_name": "Boyz", "shooter_unit_id": "U_CUSTODIAN_GUARD_A",
		"weapon_name": "Guardian spear", "wounds_to_save": 14, "total_wounds": 14, "ap": -3, "damage": 2, "damage_raw": "2",
		"base_save": 6, "is_psychic": false, "has_devastating_wounds": false, "devastating_wounds": 0, "melta_bonus": 0}, 1)
	# auto_mode (computer allocates) resolves inside setup(); otherwise drive
	# the confirm the same way.
	if not ov.resolved:
		ov.auto_mode = true
		ov._on_confirm_pressed()
	var ov_rolls: Array = phase.dice_log.slice(rolls_before).filter(func(d): return typeof(d) == TYPE_DICTIONARY and str(d.get("context", "")) == "ork11e_fight_on_death")
	var ov_kept: int = ov_rolls.filter(func(d): return d.get("kept", false)).size()
	var zero_alive := 0
	for m in _unit("U_BOYZ_B").models:
		if m.get("alive", true) and int(m.get("current_wounds", 1)) <= 0:
			zero_alive += 1
	print("    overlay batch: casualties=%d rolls=%d kept=%d" % [int(ov.batch_result.get("casualties", 0)), ov_rolls.size(), ov_kept])
	_check("overlay: one D6 per model its batch destroyed", ov_rolls.size() > 0 and ov_rolls.size() == int(ov.batch_result.get("casualties", 0)), "%d rolls vs %d casualties" % [ov_rolls.size(), int(ov.batch_result.get("casualties", 0))])
	_check("overlay: kept models applied as alive with 0 wounds", zero_alive == ov_kept)
	ov._on_done_pressed()
	var marked_all := true
	var has_pending_diff := false
	for d in summary.get("diffs", []):
		if str(d.get("path", "")).ends_with(".alive") and not d.get("ork11e_fod_rolled", false):
			marked_all = false
		if str(d.get("path", "")) == "units.U_BOYZ_B.flags.ork11e_fod_pending":
			has_pending_diff = true
	_check("overlay summary: every destroyed-model diff marked as rolled", marked_all and not summary.get("diffs", []).is_empty())
	_check("overlay summary: carries the pending list", has_pending_diff == (ov_kept > 0))
	var n_after: int = phase.dice_log.size()
	phase._ork11e_fod_intercept(summary.get("diffs", []))
	_check("APPLY_MELEE_SAVES pass never re-rolls the overlay's models", phase.dice_log.size() == n_after)
	SM.on_phase_end(PHASE_FIGHT)
	_restore_unit_state()

	# Phase left another way (transition): kept models still removed on exit.
	phase = _fresh_fight()
	_flags("U_DEFF_DREAD_A")["ork11e_fod_mode"] = "deff_dread"
	var d2: Array = [{"op": "set", "path": "units.U_DEFF_DREAD_A.models.0.current_wounds", "value": 0},
		{"op": "set", "path": "units.U_DEFF_DREAD_A.models.0.alive", "value": false}]
	phase._ork11e_fod_intercept(d2)
	PM.apply_state_changes(d2)
	PM.transition_to_phase(PHASE_COMMAND)
	_check("phase exit removes kept models", not _unit("U_DEFF_DREAD_A").models[0].get("alive", true))
	_restore_unit_state()


func _has_pending_diff(diffs: Array, uid: String, expect: Array) -> bool:
	for d in diffs:
		if str(d.get("path", "")) == "units.%s.flags.ork11e_fod_pending" % uid:
			return Array(d.value).map(func(v): return int(v)) == expect
	return false


# ---------------------------------------------------------------------------
func _section_fod_target_gates() -> void:
	print("\n-- G. target gates (TOO ARROGANT TO DIE / CRAZED RAMPAGE / ORKS IS NEVER BEATEN) --")
	_set_detachment(1, "Bully Boyz")
	var tatd := _sid(1, CSV_TATD)
	_check("TOO ARROGANT TO DIE loaded (Bully Boyz)", tatd != "")
	_fresh_fight()
	var ctx := {"attacker_unit_id": "U_CUSTODIAN_GUARD_B", "target_unit_ids": ["U_NOBZ_A", "U_BOYZ_B", "U_MEGANOBZ_A"]}
	var offers = SM.get_window_offers(1, "enemy_targets_unit_fight", ctx)
	var t := _offer_targets(offers, tatd)
	_check("TATD: Nobz + Meganobz offered, Boyz not", "U_NOBZ_A" in t and "U_MEGANOBZ_A" in t and not "U_BOYZ_B" in t, str(t))
	_check("TATD: not offered outside enemy_targets_unit_fight", not tatd in _offer_ids(SM.get_window_offers(1, "unit_selected_to_fight", {"unit_id": "U_NOBZ_A"})))
	_check("TATD: not offered to the attacker's player", SM.get_window_offers(2, "enemy_targets_unit_fight", ctx).is_empty())
	_set_detachment(1, "Dread Mob")
	var cr := _sid(1, CSV_CR)
	t = _offer_targets(SM.get_window_offers(1, "enemy_targets_unit_fight", {"attacker_unit_id": "U_PROSECUTORS_A", "target_unit_ids": ["U_DEFF_DREAD_A", "U_KILLA_KANS_A", "U_BATTLEWAGON_A"]}), cr)
	_check("CRAZED RAMPAGE: ORKS WALKERs offered (Deff Dread, Killa Kans), Battlewagon not", "U_DEFF_DREAD_A" in t and "U_KILLA_KANS_A" in t and not "U_BATTLEWAGON_A" in t, str(t))
	var kw: Array = _unit("U_DEFF_DREAD_A").meta.keywords
	kw.append("TITANIC")
	_check("CRAZED RAMPAGE: TITANIC excluded", not "U_DEFF_DREAD_A" in _offer_targets(SM.get_window_offers(1, "enemy_targets_unit_fight", {"attacker_unit_id": "U_PROSECUTORS_A", "target_unit_ids": ["U_DEFF_DREAD_A"]}), cr))
	_set_detachment(1, "War Horde")
	var oinb := _sid(1, CSV_OINB)
	_check("ORKS IS NEVER BEATEN: TITANIC excluded", not "U_DEFF_DREAD_A" in _offer_targets(SM.get_window_offers(1, "enemy_targets_unit_fight", {"attacker_unit_id": "U_PROSECUTORS_A", "target_unit_ids": ["U_DEFF_DREAD_A"]}), oinb))
	kw.erase("TITANIC")
	_check("ORKS IS NEVER BEATEN: any ORKS unit (Deff Dread)", "U_DEFF_DREAD_A" in _offer_targets(SM.get_window_offers(1, "enemy_targets_unit_fight", {"attacker_unit_id": "U_PROSECUTORS_A", "target_unit_ids": ["U_DEFF_DREAD_A"]}), oinb))
	GS.state.players["1"]["cp"] = 0
	_check("no offers with 0 CP", SM.get_window_offers(1, "enemy_targets_unit_fight", ctx).is_empty())
	_restore_unit_state()


# ---------------------------------------------------------------------------
func _boyz_by_trukk() -> void:
	# Boyz + attached Warboss in two ranks just in front of the Trukk.
	_place("U_BOYZ_B", _row(15.0, 9.8, 5, 1.3) + _row(15.0, 11.1, 5, 1.3))
	_place("U_WARBOSS_A", [Vector2(13.6, 9.9)])


func _section_keep_it_runnin() -> void:
	print("\n-- H. fight_phase_end + KEEP IT RUNNIN' --")
	_set_detachment(1, "Blitz Brigade")
	var sid := _sid(1, CSV_KIR)
	_check("KEEP IT RUNNIN' loaded (Blitz Brigade)", sid != "")
	var phase = _fresh_fight()
	_check("Boyz stamped 'was eligible to fight' at phase start", bool(_flags("U_BOYZ_B").get("was_eligible_to_fight", false)))
	_check("not offered while engaged", not "U_BOYZ_B" in _offer_targets(SM.get_window_offers(1, "fight_phase_end", {"phase": "fight"}), sid))
	_boyz_by_trukk()
	_place("U_KOMMANDOS_A", _row(6.2, 9.4, 5, 1.3) + _row(6.2, 10.7, 5, 1.3))
	var offers = SM.get_window_offers(1, "fight_phase_end", {"phase": "fight"})
	var t := _offer_targets(offers, sid)
	_check("offered: unengaged Boyz wholly within 6\" of the Trukk", "U_BOYZ_B" in t, str(offers))
	_check("attached Warboss is not offered on its own", not "U_WARBOSS_A" in t)
	_check("not offered: Kommandos were never eligible to fight", not "U_KOMMANDOS_A" in t, str(t))
	var entry := _offer_entry(offers, sid, "U_BOYZ_B")
	_check("single transport: no secondary pick, label names it", not entry.has("secondary") and "Trukk" in str(entry.get("label", "")), str(entry))
	_check("not offered in another window", not sid in _offer_ids(SM.get_window_offers(1, "unit_selected_to_fight", {"unit_id": "U_BOYZ_B"})))
	# Out of range
	var saved = _unit("U_BOYZ_B").models[9].position.duplicate()
	_unit("U_BOYZ_B").models[9]["position"] = {"x": 15.0 * PX, "y": 16.5 * PX}
	_check("not offered: one model not wholly within 6\"", not "U_BOYZ_B" in _offer_targets(SM.get_window_offers(1, "fight_phase_end", {"phase": "fight"}), sid))
	_unit("U_BOYZ_B").models[9]["position"] = saved
	# Capacity: Trukk (12) already carrying 10 Gretchin cannot take 11 more models.
	_unit("U_TRUKK_A").transport_data["embarked_units"] = ["U_GRETCHIN_D"]
	_unit("U_GRETCHIN_D")["embarked_in"] = "U_TRUKK_A"
	_check("not offered: transport without the capacity", not "U_BOYZ_B" in _offer_targets(SM.get_window_offers(1, "fight_phase_end", {"phase": "fight"}), sid))
	_unit("U_TRUKK_A").transport_data["embarked_units"] = []
	_unit("U_GRETCHIN_D").erase("embarked_in")
	# Two transports -> secondary pick.
	var bw_saved = _unit("U_BATTLEWAGON_A").models[0].position.duplicate()
	_unit("U_BATTLEWAGON_A").models[0]["position"] = {"x": 17.6 * PX, "y": 15.6 * PX}
	entry = _offer_entry(SM.get_window_offers(1, "fight_phase_end", {"phase": "fight"}), sid, "U_BOYZ_B")
	var opts: Array = entry.get("secondary", {}).get("options", []).map(func(o): return str(o.id))
	_check("two transports in range: secondary pick lists both", "U_TRUKK_A" in opts and "U_BATTLEWAGON_A" in opts, str(entry))
	_unit("U_BATTLEWAGON_A").models[0]["position"] = bw_saved

	# Real end of phase: END_FIGHT -> Consolidate step -> fight_phase_end window.
	var cp0 := _cp(1)
	_window_events.clear()
	_drive_to_phase_end(phase)
	_check("fight_phase_end window pending for the ACTIVE player first", phase.has_pending_stratagem_window()
		and str(phase.get_pending_stratagem_window().get("window_id", "")) == "fight_phase_end" and phase.get_pending_stratagem_window_decider() == 1,
		str(phase.get_pending_stratagem_window()))
	_check("phase not completed while the window waits", not _phase_done)
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "fight_phase_end", "stratagem_id": sid, "target_unit_id": "U_BOYZ_B"})
	_check("USE succeeds", use.get("success", false), str(use.get("error", "")))
	_check("CP -1", _cp(1) == cp0 - 1)
	_check("embark follow-up: Boyz embarked within the Trukk", str(_unit("U_BOYZ_B").get("embarked_in", "")) == "U_TRUKK_A")
	_check("attached Warboss embarked too", str(_unit("U_WARBOSS_A").get("embarked_in", "")) == "U_TRUKK_A")
	_check("Trukk lists both units", "U_BOYZ_B" in _unit("U_TRUKK_A").transport_data.embarked_units and "U_WARBOSS_A" in _unit("U_TRUKK_A").transport_data.embarked_units)
	_check("models left the battlefield (positions cleared)", _unit("U_BOYZ_B").models[0].get("position", 1) == null)
	var has_embark_diff := false
	for d in use.get("changes", []):
		if str(d.get("path", "")) == "units.U_BOYZ_B.embarked_in":
			has_embark_diff = true
	_check("embark diffs in the action result (replay/network)", has_embark_diff)
	_check("phase completed after the window(s)", _phase_done and not phase.has_pending_stratagem_window())
	_restore_unit_state()

	# AI decider (synchronous) at fight_phase_end: declines with no enemy near,
	# uses it when an enemy unit is within 12" of the exposed Boyz.
	var ai = root.get_node("AIPlayer")
	var kir_strat = SM.get_stratagem(sid)
	phase = _fresh_fight()
	_boyz_by_trukk()
	_place("U_GRETCHIN_C", _row(1.5, 1.5, 10, 0.0))
	_check("AI score: no enemy within 12\" -> keep the CP", Fight.ai_score(kir_strat, 1, "U_GRETCHIN_C", "fight_phase_end", {}) < 2.0)
	_place("U_CUSTODIAN_GUARD_C", _row(14.0, 19.0, 5, 1.7))
	_check("AI score: enemy within 12\" -> worth it", Fight.ai_score(kir_strat, 1, "U_BOYZ_B", "fight_phase_end", {}) >= 2.0)
	ai.enabled = true
	ai.ai_players = {1: true, 2: false}
	cp0 = _cp(1)
	_drive_to_phase_end(phase)
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_check("AI decider used KEEP IT RUNNIN' synchronously (enemies within 12\")", str(_unit("U_BOYZ_B").get("embarked_in", "")) == "U_TRUKK_A" and _cp(1) == cp0 - 1, "embarked_in=%s cp %d->%d" % [str(_unit("U_BOYZ_B").get("embarked_in", "")), cp0, _cp(1)])
	_check("…and the phase completed (no stall)", _phase_done)
	_restore_unit_state()


# ---------------------------------------------------------------------------
func _p2_active() -> void:
	GS.state.meta["active_player"] = 2


func _section_instinctive_hunters() -> void:
	print("\n-- I. INSTINCTIVE HUNTERS --")
	_set_detachment(1, "Da Big Hunt")
	var sid := _sid(1, CSV_IH)
	_check("INSTINCTIVE HUNTERS loaded (Da Big Hunt)", sid != "")
	# Own turn: never offered.
	var phase = _fresh_fight()
	_place("U_BEAST_SNAGGA_BOYZ_A", _row(1.0, 22.0, 5, 1.3) + _row(1.0, 23.3, 5, 1.3))
	_check("own Fight phase: not offered (opponent's turn only)", not sid in _offer_ids(SM.get_window_offers(1, "fight_phase_end", {"phase": "fight"})))
	_restore_unit_state()
	# Opponent's (Custodes') Fight phase.
	phase = _fresh_fight(Callable(self, "_p2_active"))
	_check("P2 is the active player", GS.get_active_player() == 2)
	_check("engaged Beast Snagga not offered", not "U_BEAST_SNAGGA_BOYZ_A" in _offer_targets(SM.get_window_offers(1, "fight_phase_end", {"phase": "fight"}), sid))
	_place("U_BEAST_SNAGGA_BOYZ_A", _row(16.0, 22.0, 5, 1.3) + _row(16.0, 23.3, 5, 1.3))
	_check("unengaged but not within 6\" of an edge: not offered", not "U_BEAST_SNAGGA_BOYZ_A" in _offer_targets(SM.get_window_offers(1, "fight_phase_end", {"phase": "fight"}), sid))
	_place("U_BEAST_SNAGGA_BOYZ_A", _row(1.0, 22.0, 5, 1.3) + _row(1.0, 23.3, 5, 1.3))
	_check("unengaged within 6\" of a battlefield edge: offered", _offer_targets(SM.get_window_offers(1, "fight_phase_end", {"phase": "fight"}), sid) == ["U_BEAST_SNAGGA_BOYZ_A"])
	_check("not offered to a non-BEAST SNAGGA unit near the edge", not "U_FLASH_GITZ_A" in _offer_targets(SM.get_window_offers(1, "fight_phase_end", {"phase": "fight"}), sid))
	var cp0 := _cp(1)
	_window_events.clear()
	_drive_to_phase_end(phase)
	_check("fight_phase_end: Custodes (active, no offers) first, then the Ork window", phase.has_pending_stratagem_window()
		and phase.get_pending_stratagem_window_decider() == 1, str(phase.get_pending_stratagem_window()))
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "fight_phase_end", "stratagem_id": sid, "target_unit_id": "U_BEAST_SNAGGA_BOYZ_A"})
	_check("USE succeeds", use.get("success", false), str(use.get("error", "")))
	_check("CP -1 (non-active player)", _cp(1) == cp0 - 1)
	var u = _unit("U_BEAST_SNAGGA_BOYZ_A")
	_check("strategic_reserves follow-up: unit IN_RESERVES / strategic_reserves", int(u.get("status", -1)) == int(GS.UnitStatus.IN_RESERVES) and str(u.get("reserve_type", "")) == "strategic_reserves", str(u.get("status")))
	_check("repositioned flag (20.04 exemption)", bool(u.flags.get("repositioned_to_reserves", false)))
	_check("phase completed", _phase_done)
	_restore_unit_state()
	GS.state.meta["active_player"] = 1


# ---------------------------------------------------------------------------
func _section_ai() -> void:
	print("\n-- J. AI decisions --")
	var ADM = load("res://scripts/AIDecisionMaker.gd")
	_set_detachment(1, "War Horde")
	var oinb := _sid(1, CSV_OINB)
	var mow := _sid(1, CSV_MOW)
	_fresh_fight()
	var ctx := {"phase": "fight", "attacker_unit_id": "U_CUSTODIAN_GUARD_A", "target_unit_ids": ["U_BOYZ_B"]}
	var offers = SM.get_window_offers(1, "enemy_targets_unit_fight", ctx)
	var d = ADM.decide_window_stratagem(1, "enemy_targets_unit_fight", offers, ctx)
	_check("AI uses ORKS IS NEVER BEATEN when Custodians charge into Boyz", d.get("use", false) and str(d.get("stratagem_id", "")) == oinb, str(d))
	_flags("U_BOYZ_B")["has_fought"] = true
	offers = SM.get_window_offers(1, "enemy_targets_unit_fight", ctx)
	d = ADM.decide_window_stratagem(1, "enemy_targets_unit_fight", offers, ctx)
	_check("AI declines when the unit has already fought (no swing back left)", not d.get("use", true), str(d))
	_flags("U_BOYZ_B").erase("has_fought")
	# MOW 'EM DOWN: engaged charged Battlewagon vs a 5-model unit.
	_place("U_CUSTODIAN_GUARD_C", _row(6.3, 9.6, 5, 1.6))
	_flags("U_BATTLEWAGON_A")["charged_this_turn"] = true
	var mctx := {"phase": "fight", "unit_id": "U_BATTLEWAGON_A"}
	offers = SM.get_window_offers(1, "unit_selected_to_fight", mctx)
	_check("MOW 'EM DOWN offered for the AI too", mow in _offer_ids(offers))
	var ms = Fight.ai_score(SM.get_stratagem(mow), 1, "U_BATTLEWAGON_A", "unit_selected_to_fight", mctx)
	_check("MOW 'EM DOWN AI score > 0 when engaged with a 5+ model unit (%.2f)" % ms, ms > 0.0)
	# Synchronous AI window in the real hook: never pauses.
	var ai = root.get_node("AIPlayer")
	ai.enabled = true
	ai.ai_players = {1: true, 2: false}
	var phase = PM.get_current_phase_instance()
	var cp0 := _cp(1)
	var paused = phase.open_stratagem_window(1, "enemy_targets_unit_fight", ctx, "")
	var sync = phase.consume_window_diffs()
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_check("AI enemy_targets_unit_fight window resolves synchronously", not paused and not phase.has_pending_stratagem_window())
	_check("AI spent 1 CP and marked the Boyz", _cp(1) == cp0 - 1 and str(_flags("U_BOYZ_B").get("ork11e_fod_mode", "")) == "riled_up")
	_check("synchronous diffs handed back", not sync.is_empty())
	SM.on_phase_end(PHASE_FIGHT)
	_restore_unit_state()


# ---------------------------------------------------------------------------
func _section_scoring_repositioned() -> void:
	print("\n-- K. repositioned units survive the round-3 reserves cull --")
	var SP = load("res://phases/ScoringPhase.gd")
	var sp = SP.new()
	root.add_child(sp)
	GS.state.units["U_BEAST_SNAGGA_BOYZ_A"]["status"] = GS.UnitStatus.IN_RESERVES
	GS.state.units["U_BEAST_SNAGGA_BOYZ_A"]["flags"]["repositioned_to_reserves"] = true
	GS.state.units["U_KOMMANDOS_A"]["status"] = GS.UnitStatus.IN_RESERVES
	var changes: Array = sp._destroy_remaining_reserves()
	var hits_bs := false
	var hits_k := false
	for c in changes:
		if str(c.get("path", "")).begins_with("units.U_BEAST_SNAGGA_BOYZ_A."):
			hits_bs = true
		if str(c.get("path", "")).begins_with("units.U_KOMMANDOS_A."):
			hits_k = true
	_check("repositioned Beast Snagga not destroyed", not hits_bs)
	_check("ordinary reserves unit still destroyed", hits_k)
	sp.queue_free()
	_restore_unit_state()
