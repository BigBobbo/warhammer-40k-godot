extends SceneTree

# Codex: Orks (11e) stratagems of the OTHER group (Command / Charge / any
# phase) + their window hooks (design .llm/ork_codex_11e_design.md §3, §6):
#   A. registry: the five ids implemented
#   B. MOB MENTALITY       battle_shock_step_start (CommandPhase start)
#   C. BREAKIN' HEADS      unit_battle_shocked (BasePhase event windows) + nesting
#   D. IMPENDING KRUNCH    unit_ended_charge_move (ChargePhase APPLY_CHARGE_MOVE)
#   E. FLYIN' HEADBUTT     unit_destroyed, before Deadly Demise (Shooting kill path)
#   F. INFESTED WAR ZONE   enemy_unit_has_attacked + new_reserve_unit follow-up
#   G. unit_declares_charge hook (synthetic window stratagem — STOMPING
#      JUGGERNAUT's handler belongs to the Movement group)
#   H. END_COMMAND auto-resolved battle-shock tests now apply their flags
#   I. 11e desperate escape battle-shock roll (09.07) -> BREAKIN' HEADS in the
#      Movement phase
#   J. enemy_unit_has_attacked in the FIGHT phase (melee kill -> INFESTED WAR
#      ZONE once the enemy fighter's activation is over)
#
# Per stratagem: offered in its window and NOT outside it / to the wrong
# player; keyword & condition gates; CP spent; effect (A/B where a roll is
# modified); expiry; AI decider path.
#
# Fixtures: tests/saves/ork11e_orks_active (P1 Orks active) and
# ork11e_orks_reactive (P1 Custodes active, P2 Orks) — design §6.6.
#
# Usage: godot --headless --path 40k --script tests/test_ork_codex_other.gd

const PHASE_COMMAND := 6
const PHASE_MOVEMENT := 7
const PHASE_SHOOTING := 8
const PHASE_CHARGE := 9
const PHASE_FIGHT := 10
const PX := 40.0

var passed := 0
var failed := 0
var SM = null
var GS = null
var PM = null
var RE = null
var AI = null
var ADM = null
var FAM = null


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
# Helpers
# ---------------------------------------------------------------------------

func _load(fixture: String) -> bool:
	var slm = root.get_node("SaveLoadManager")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slm.save_directory))
	for ext in [".w40ksave", ".meta"]:
		var src = "res://tests/saves/" + fixture + ext
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(slm.save_directory + fixture + ext))
	var ok: bool = slm.load_game(fixture)
	GameConstants.edition = 11
	_ai_off()
	SM._usage_history = {"1": [], "2": []}
	SM.active_effects = []
	GS.state.players["1"]["cp"] = 6
	GS.state.players["2"]["cp"] = 6
	return ok


func _ai_off() -> void:
	AI.enabled = false
	AI.ai_players = {1: false, 2: false}


func _ai_on(player: int) -> void:
	AI.enabled = true
	AI.ai_players = {1: player == 1, 2: player == 2}


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


func _phase():
	return PM.get_current_phase_instance()


func _unit(uid: String) -> Dictionary:
	return GS.state.units.get(uid, {})


func _alive(uid: String) -> int:
	var n := 0
	for m in _unit(uid).get("models", []):
		if m.get("alive", true):
			n += 1
	return n


func _wounds(uid: String) -> int:
	var n := 0
	for m in _unit(uid).get("models", []):
		if m.get("alive", true):
			n += int(m.get("current_wounds", m.get("wounds", 1)))
	return n


func _kill(uid: String, n: int) -> void:
	var killed := 0
	for m in _unit(uid).get("models", []):
		if killed >= n:
			break
		if m.get("alive", true):
			m["alive"] = false
			m["current_wounds"] = 0
			killed += 1


## Clone the last model n times, one row further from the enemy (smaller y in
## the active orientation, larger y in the reactive one).
func _add_models(uid: String, n: int, dy_inches: float = -1.5) -> void:
	var models: Array = _unit(uid).models
	var last: Dictionary = models[models.size() - 1]
	for i in range(n):
		var m: Dictionary = last.duplicate(true)
		m["id"] = "m%d" % (models.size() + 1)
		m["alive"] = true
		m["current_wounds"] = m.get("wounds", 1)
		var p = last.position
		m["position"] = {"x": float(p.x) - (i - n / 2.0) * 1.3 * PX, "y": float(p.y) + dy_inches * PX}
		models.append(m)


func _translate(uid: String, dx_in: float, dy_in: float) -> void:
	for m in _unit(uid).get("models", []):
		var p = m.get("position", null)
		if p == null:
			continue
		m["position"] = {"x": float(p.x) + dx_in * PX, "y": float(p.y) + dy_in * PX}


func _centroid(uid: String) -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for m in _unit(uid).get("models", []):
		if m.get("position", null) == null:
			continue
		c += Vector2(float(m.position.x), float(m.position.y))
		n += 1
	return c / max(1, n)


func _move_near(uid: String, anchor_uid: String, offset_in: Vector2) -> void:
	var target: Vector2 = _centroid(anchor_uid) + offset_in * PX
	var d: Vector2 = (target - _centroid(uid)) / PX
	_translate(uid, d.x, d.y)


## Move a unit so its centroid sits at `at` (inches). Open-field spots used by
## this test (no enemy within engagement range): active orientation
## (40, 44.5) / (40, 52); reactive orientation (41, 24) / (41, 35).
## Codex: Adeptus Custodes (11e, WP-C3): the Custodes Command phase readies
## every Martial Ka'tah unit, so selecting Custodian Guard F to shoot / fight
## would first open a ka'tah window (Salvus / Dacatarai ...) for the human P1.
## The ka'tahs are not under test here (test_custodes_army_rules_11e.gd covers
## them): un-ready the Custodes and spend Master of Ka'tahs for the round.
func _cus11e_unready() -> void:
	var rnd: int = int(GS.get_battle_round())
	for uid in GS.state.units:
		var u: Dictionary = GS.state.units[uid]
		if not (u.get("flags", null) is Dictionary):
			u["flags"] = {}
		u.flags.erase("cus11e_readied")
		u.flags["cus11e_master_of_katahs_round"] = rnd


func _move_to(uid: String, at: Vector2) -> void:
	var d: Vector2 = (at * PX - _centroid(uid)) / PX
	_translate(uid, d.x, d.y)


func _offers_for(offers: Array, sid: String) -> Dictionary:
	for o in offers:
		if str(o.get("stratagem_id", "")) == sid:
			return o
	return {}


func _target_ids(offer: Dictionary) -> Array:
	var out: Array = []
	for t in offer.get("targets", []):
		out.append(str(t.get("unit_id", "")))
	return out


func _secondary_ids(offer: Dictionary, uid: String) -> Array:
	for t in offer.get("targets", []):
		if str(t.get("unit_id", "")) == uid:
			var out: Array = []
			for o in t.get("secondary", {}).get("options", []):
				out.append(str(o.get("id", "")))
			return out
	return []


func _pending_window(phase) -> Dictionary:
	return phase.get_pending_stratagem_window() if phase.has_pending_stratagem_window() else {}


func _ranged_assignments(shooter: String, target: String) -> Array:
	var by_weapon := {}
	var weapons: Dictionary = RE.get_unit_weapons(shooter, GS.state)
	for mid in weapons:
		for wid in weapons[mid]:
			var prof: Dictionary = RE.get_weapon_profile(wid, GS.state)
			if prof.is_empty() or float(prof.get("range", 0)) <= 0.0:
				continue
			if not by_weapon.has(wid):
				by_weapon[wid] = []
			by_weapon[wid].append(mid)
	var out: Array = []
	for wid in by_weapon:
		out.append({"weapon_id": wid, "target_unit_id": target, "model_ids": by_weapon[wid]})
	return out


func _shoot(phase, shooter: String, target: String, seed_val: int) -> Dictionary:
	return phase.execute_action({"type": "SHOOT", "actor_unit_id": shooter, "player": int(_unit(shooter).owner),
		"payload": {"assignments": _ranged_assignments(shooter, target), "rng_seed": seed_val}})


# ---------------------------------------------------------------------------

func _run() -> void:
	SM = root.get_node("StratagemManager")
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	AI = root.get_node("AIPlayer")
	FAM = root.get_node("FactionAbilityManager")
	ADM = load("res://scripts/AIDecisionMaker.gd")
	var ss = root.get_node_or_null("SettingsService")
	if ss:
		ss.auto_allocate_wounds = true
	_ai_off()
	GameConstants.edition = 11
	print("\n=== test_ork_codex_other ===\n")

	_section_registry()
	await _section_mob_mentality()
	await _section_breakin_heads()
	await _section_impending_krunch()
	await _section_flyin_headbutt()
	await _section_infested_war_zone()
	await _section_declares_charge_hook()
	await _section_end_command_auto_resolve()
	await _section_desperate_escape()
	await _section_infested_fight()
	_ai_off()


# ---------------------------------------------------------------------------
func _section_registry() -> void:
	print("\n-- A. registry --")
	var G = load("res://scripts/stratagems/ork_codex/OrkCodexOther.gd")
	var Codex = load("res://scripts/stratagems/ork_codex/OrkCodex11e.gd")
	for csv in ["mob-mentality-green-tide", "breakin-heads-war-horde", "impending-krunch-blitz-brigade", "flyin-headbutt-flyboyz", "infested-war-zone-runt-swarm"]:
		_check("%s implemented (registry)" % csv, csv in Codex.all_implemented_ids())
		_check("%s owned by OrkCodexOther" % csv, csv in G.IDS)
	_check("OrkCodexOther owns exactly 5 ids", G.IDS.size() == 5)


# ---------------------------------------------------------------------------
# B. MOB MENTALITY
# ---------------------------------------------------------------------------
func _section_mob_mentality() -> void:
	print("\n-- B. MOB MENTALITY (battle_shock_step_start) --")
	_check("fixture ork11e_orks_active loads", _load("ork11e_orks_active"))
	_set_detachment(1, "Green Tide")
	var sid := _sid(1, "mob-mentality-green-tide")
	_check("MOB MENTALITY loaded for P1 (Green Tide)", sid != "")
	var Codex = load("res://scripts/stratagems/ork_codex/OrkCodex11e.gd")

	# Beast Snagga Boyz below half-strength => must test. Boyz B (+Warboss) = 11 models.
	_kill("U_BEAST_SNAGGA_BOYZ_A", 6)
	var G = load("res://scripts/stratagems/ork_codex/OrkCodexOther.gd")
	var d_bsb: float = G._group_distance("U_BOYZ_B", "U_BEAST_SNAGGA_BOYZ_A")
	_check("setup: Beast Snagga Boyz within 12\" of Boyz B (%.1f\")" % d_bsb, d_bsb <= 12.0)
	PM.transition_to_phase(PHASE_COMMAND)
	var phase = _phase()
	_check("11-model attached Boyz: no window (needs 13+ models)", not phase.has_pending_stratagem_window(), str(_pending_window(phase).get("window_id", "")))
	var r = SM.can_use_stratagem(1, sid, "U_BOYZ_B", {"window_id": "battle_shock_step_start", "units_needing_test": ["U_BEAST_SNAGGA_BOYZ_A"]})
	_check("validate: 11 models refused with the 13+ reason", not r.can_use and "13+" in str(r.reason), str(r))

	# 12 Boyz + the attached Warboss = 13 models (19.03 — one unit).
	_add_models("U_BOYZ_B", 2)
	# A unit that must test but is out of range: Tankbustas moved far away.
	_kill("U_TANKBUSTAS_A", 4)
	_translate("U_TANKBUSTAS_A", 26.0, -8.0)
	var d_tb: float = G._group_distance("U_BOYZ_B", "U_TANKBUSTAS_A")
	_check("setup: Tankbustas beyond 12\" (%.1f\")" % d_tb, d_tb > 12.0)
	# Already battle-shocked units must test too — and recover if they pass.
	GS.state.units.U_BEAST_SNAGGA_BOYZ_A.flags["battle_shocked"] = true
	var cp0 := _cp(1)
	PM.transition_to_phase(PHASE_COMMAND)
	phase = _phase()
	var cp_start := _cp(1)
	_check("Command phase start: +1 CP (%d -> %d)" % [cp0, cp_start], cp_start == cp0 + 1)
	# LIVE-3 / MM-1: the window does NOT open at phase entry (on top of the
	# Command step's exclusive prompts) — it opens when the Battle-shock step
	# starts (the roll call sends BEGIN_BATTLE_SHOCK_STEP).
	_check("phase entry: battle_shock_step_start not opened yet (Command-step prompts first)", not phase.has_pending_stratagem_window() and not phase.battle_shock_step_window_opened(), str(_pending_window(phase).get("window_id", "")))
	var begin = phase.execute_action({"type": "BEGIN_BATTLE_SHOCK_STEP", "player": 1})
	_check("BEGIN_BATTLE_SHOCK_STEP succeeds", begin.get("success", false), str(begin.get("error", "")))
	var w := _pending_window(phase)
	_check("battle_shock_step_start window pending for P1", str(w.get("window_id", "")) == "battle_shock_step_start" and int(w.get("player", 0)) == 1, str(w.get("window_id", "")))
	_check("BEGIN result stamped with the opened window (network mirror)", begin.has("stratagem_window_opened"))
	var offer := _offers_for(w.get("offers", []), sid)
	_check("MOB MENTALITY offered on Boyz B", _target_ids(offer) == ["U_BOYZ_B"], str(_target_ids(offer)))
	var opts := _secondary_ids(offer, "U_BOYZ_B")
	_check("secondary lists the Beast Snagga Boyz (must test, within 12\", visible)", "U_BEAST_SNAGGA_BOYZ_A" in opts, str(opts))
	_check("secondary excludes the out-of-range Tankbustas", not "U_TANKBUSTAS_A" in opts, str(opts))
	_check("secondary excludes units that need no test", not "U_NOBZ_A" in opts and not "U_KOMMANDOS_A" in opts, str(opts))
	_check("no window offers for P2 (Custodes)", SM.get_window_offers(2, "battle_shock_step_start", {"units_needing_test": ["U_CUSTODIAN_GUARD_A"]}).is_empty())
	_check("MOB MENTALITY not offered in another window", _offers_for(SM.get_window_offers(1, "unit_battle_shocked", {"unit_id": "U_BOYZ_B"}), sid).is_empty())
	r = SM.can_use_stratagem(1, sid, "U_BOYZ_B")
	_check("outside its window: 'Offered automatically when …battle-shock step…'", not r.can_use and "battle-shock step" in str(r.reason), str(r))
	var blocked = phase.execute_action({"type": "BATTLE_SHOCK_TEST", "unit_id": "U_BEAST_SNAGGA_BOYZ_A", "player": 1})
	_check("battle-shock tests wait for the decision", not blocked.get("success", true) and blocked.get("stratagem_window_pending", false), str(blocked.get("error", "")))
	var no_sec = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "battle_shock_step_start", "stratagem_id": sid, "target_unit_id": "U_BOYZ_B", "context": {}})
	_check("USE without a selected unit refused", not no_sec.get("success", true), str(no_sec.get("error", "")))
	var bad_sec = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "battle_shock_step_start", "stratagem_id": sid, "target_unit_id": "U_BOYZ_B", "context": {"secondary_id": "U_TANKBUSTAS_A"}})
	_check("USE selecting an out-of-range unit refused", not bad_sec.get("success", true) and phase.has_pending_stratagem_window(), str(bad_sec.get("error", "")))
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "battle_shock_step_start", "stratagem_id": sid, "target_unit_id": "U_BOYZ_B", "context": {"secondary_id": "U_BEAST_SNAGGA_BOYZ_A"}})
	_check("USE (select Beast Snagga Boyz) succeeds", use.get("success", false), str(use.get("error", "")))
	_check("window closed", not phase.has_pending_stratagem_window())
	_check("CP -1", _cp(1) == cp_start - 1, "%d -> %d" % [cp_start, _cp(1)])
	_check("auto-pass flag on the selected unit", bool(_unit("U_BEAST_SNAGGA_BOYZ_A").flags.get("ork11e_mob_mentality", false)))
	_check("no auto-pass flag on the 13+ unit itself", not _unit("U_BOYZ_B").flags.get("ork11e_mob_mentality", false))

	# Effect A/B: both units at an impossible Ld 13 — the selected one passes
	# with no dice, the other fails.
	GS.state.units.U_BEAST_SNAGGA_BOYZ_A.meta.stats["leadership"] = 13
	GS.state.units.U_TANKBUSTAS_A.meta.stats["leadership"] = 13
	var t1 = phase.execute_action({"type": "BATTLE_SHOCK_TEST", "unit_id": "U_BEAST_SNAGGA_BOYZ_A", "player": 1})
	_check("selected unit: test automatically successful (no dice)", t1.get("success", false) and t1.get("auto_passed", false) and t1.get("test_passed", false) and int(t1.get("die1", -1)) == 0, str(t1))
	_check("result names MOB MENTALITY", str(t1.get("auto_pass_source", "")) == "MOB MENTALITY")
	_check("battle-shocked unit recovered (11e 08.03)", not _unit("U_BEAST_SNAGGA_BOYZ_A").flags.get("battle_shocked", true))
	var t2 = phase.execute_action({"type": "BATTLE_SHOCK_TEST", "unit_id": "U_TANKBUSTAS_A", "player": 1, "dice_roll": [6, 6]})
	_check("unselected unit at Ld 13 fails (12 < 13)", t2.get("success", false) and not t2.get("test_passed", true), str(t2.get("message", "")))
	_check("unselected unit battle-shocked", bool(_unit("U_TANKBUSTAS_A").flags.get("battle_shocked", false)))
	# Forced (out-of-sequence) battle-shock rolls in the phase honour it too.
	var forced = FAM.force_battle_shock_test("U_BEAST_SNAGGA_BOYZ_A", -5, "test")
	_check("forced battle-shock roll auto-passes while the flag is set", forced.get("passed", false) and forced.get("auto_passed", false), str(forced))

	# Expiry: end of the phase.
	var eff_ok := false
	for e in SM.active_effects:
		if str(e.get("stratagem_id", "")) == sid:
			eff_ok = str(e.get("expires", "")) == "end_of_phase"
	_check("active effect expires end_of_phase", eff_ok)
	PM.transition_to_phase(PHASE_MOVEMENT)
	_check("flag cleared when the Command phase ends", not _unit("U_BEAST_SNAGGA_BOYZ_A").flags.has("ork11e_mob_mentality"))
	_check("selection record cleared", not _unit("U_BOYZ_B").flags.has("ork11e_mob_mentality_selected"))

	# No unit needs a test => no window at all.
	GS.state.units.U_BEAST_SNAGGA_BOYZ_A.flags["battle_shocked"] = false
	for m in _unit("U_BEAST_SNAGGA_BOYZ_A").models:
		m["alive"] = true
		m["current_wounds"] = m.get("wounds", 1)
	GS.state.units.U_TANKBUSTAS_A.flags["battle_shocked"] = false
	for m in _unit("U_TANKBUSTAS_A").models:
		m["alive"] = true
		m["current_wounds"] = m.get("wounds", 1)
	PM.transition_to_phase(PHASE_COMMAND)
	_phase().execute_action({"type": "BEGIN_BATTLE_SHOCK_STEP", "player": 1})
	_check("no unit must test: no battle_shock_step_start window", not _phase().has_pending_stratagem_window())

	# AI decider: answered synchronously at the start of the step.
	_kill("U_BEAST_SNAGGA_BOYZ_A", 6)
	GS.state.units.U_BEAST_SNAGGA_BOYZ_A.meta.stats["leadership"] = 7
	SM._usage_history = {"1": [], "2": []}
	PM.transition_to_phase(PHASE_COMMAND)
	phase = _phase()
	_check("AI turn: no window at phase entry either", not phase.has_pending_stratagem_window())
	var cp_ai := _cp(1)
	_ai_on(1)
	# The AI's own first battle-shock action starts the step: the window is
	# answered synchronously, then the test itself runs in the same action.
	var ai_test = phase.execute_action({"type": "BATTLE_SHOCK_TEST", "unit_id": "U_BEAST_SNAGGA_BOYZ_A", "player": 1})
	_ai_off()
	_check("AI decider: no pending window", not phase.has_pending_stratagem_window())
	_check("AI used MOB MENTALITY (CP -1, flag on the Beast Snagga Boyz)", _cp(1) == cp_ai - 1 and bool(_unit("U_BEAST_SNAGGA_BOYZ_A").flags.get("ork11e_mob_mentality", false)), "cp %d -> %d" % [cp_ai, _cp(1)])
	_check("AI: the test that started the step ran after the decision (auto-passed)", ai_test.get("success", false) and ai_test.get("auto_passed", false), str(ai_test))
	_check("AI: the window diffs ride in that action's result", ai_test.get("changes", []).size() > 0)
	PM.transition_to_phase(PHASE_MOVEMENT)

	# Human: a direct BATTLE_SHOCK_TEST / END_COMMAND before the roll call also
	# starts the step — the window opens first and the action resumes after.
	SM._usage_history = {"1": [], "2": []}
	GS.state.units.U_BEAST_SNAGGA_BOYZ_A.meta.stats["leadership"] = 13
	PM.transition_to_phase(PHASE_COMMAND)
	phase = _phase()
	var deferred_test = phase.execute_action({"type": "BATTLE_SHOCK_TEST", "unit_id": "U_BEAST_SNAGGA_BOYZ_A", "player": 1, "dice_roll": [1, 1]})
	_check("direct BATTLE_SHOCK_TEST opens the battle_shock_step_start window first", deferred_test.get("success", false) and str(_pending_window(phase).get("window_id", "")) == "battle_shock_step_start", str(deferred_test))
	_check("the test has not been rolled yet", not "U_BEAST_SNAGGA_BOYZ_A" in phase._units_tested)
	var dec_t = phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 1, "window_id": "battle_shock_step_start"})
	_check("decline -> the deferred test runs (failed at Ld 13)", dec_t.get("success", false) and "U_BEAST_SNAGGA_BOYZ_A" in phase._units_tested and bool(_unit("U_BEAST_SNAGGA_BOYZ_A").flags.get("battle_shocked", false)), str(dec_t))
	_check("BEGIN after the step started is a no-op", phase.execute_action({"type": "BEGIN_BATTLE_SHOCK_STEP", "player": 1}).get("success", false) and not phase.has_pending_stratagem_window())
	PM.transition_to_phase(PHASE_MOVEMENT)
	GS.state.units.U_BEAST_SNAGGA_BOYZ_A.flags["battle_shocked"] = false
	SM._usage_history = {"1": [], "2": []}
	PM.transition_to_phase(PHASE_COMMAND)
	phase = _phase()
	var deferred_end = phase.execute_action({"type": "END_COMMAND", "player": 1})
	_check("END_COMMAND before the roll call opens the window and keeps the phase", deferred_end.get("success", false) and GS.get_current_phase() == PHASE_COMMAND and str(_pending_window(phase).get("window_id", "")) == "battle_shock_step_start", str(deferred_end.get("message", "")))
	var cp_end := _cp(1)
	var use_end = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "battle_shock_step_start", "stratagem_id": sid, "target_unit_id": "U_BOYZ_B", "context": {"secondary_id": "U_BEAST_SNAGGA_BOYZ_A"}})
	_check("USE -> END_COMMAND resumes: the selected unit auto-passed and the phase ended", use_end.get("success", false) and _cp(1) == cp_end - 1 and GS.get_current_phase() == PHASE_MOVEMENT and not bool(_unit("U_BEAST_SNAGGA_BOYZ_A").flags.get("battle_shocked", false)), "phase=%d %s" % [GS.get_current_phase(), str(use_end.get("error", ""))])
	GS.state.units.U_BEAST_SNAGGA_BOYZ_A.meta.stats["leadership"] = 7

	# Opponent's turn: the Orks are not the active player — never offered.
	_check("fixture ork11e_orks_reactive loads", _load("ork11e_orks_reactive"))
	_set_detachment(2, "Green Tide")
	var sid2 := _sid(2, "mob-mentality-green-tide")
	_add_models("U_BOYZ_B", 2, 1.5)
	_kill("U_BEAST_SNAGGA_BOYZ_A", 6)
	r = SM.can_use_stratagem(2, sid2, "U_BOYZ_B", {"window_id": "battle_shock_step_start", "units_needing_test": ["U_BEAST_SNAGGA_BOYZ_A"]})
	_check("opponent's Command phase: refused (your turn only)", not r.can_use and "your turn" in str(r.reason), str(r))
	_check("opponent's Command phase: no offers for the Orks", SM.get_window_offers(2, "battle_shock_step_start", {"units_needing_test": ["U_BEAST_SNAGGA_BOYZ_A"]}).is_empty())


# ---------------------------------------------------------------------------
# C. BREAKIN' HEADS
# ---------------------------------------------------------------------------
func _section_breakin_heads() -> void:
	print("\n-- C. BREAKIN' HEADS (unit_battle_shocked) --")
	_check("fixture ork11e_orks_active loads", _load("ork11e_orks_active"))
	var sid := _sid(1, "breakin-heads-war-horde")
	_check("BREAKIN' HEADS loaded for P1 (War Horde)", sid != "")
	# Boyz B (+ attached Warboss) and the unattached Nobz below half, at Ld 13.
	_kill("U_BOYZ_B", 6)
	_kill("U_NOBZ_A", 3)
	for uid in ["U_BOYZ_B", "U_WARBOSS_A", "U_NOBZ_A"]:
		GS.state.units[uid].meta.stats["leadership"] = 13
	PM.transition_to_phase(PHASE_COMMAND)
	var phase = _phase()
	_check("no battle_shock_step_start window for War Horde", not phase.has_pending_stratagem_window())
	var r = SM.can_use_stratagem(1, sid, "U_BOYZ_B", {"window_id": "unit_battle_shocked", "unit_id": "U_BOYZ_B"})
	_check("not battle-shocked yet: refused", not r.can_use and "not battle-shocked" in str(r.reason), str(r))

	# Unattached unit fails: no window.
	var nobz = phase.execute_action({"type": "BATTLE_SHOCK_TEST", "unit_id": "U_NOBZ_A", "player": 1, "dice_roll": [1, 1]})
	_check("Nobz fail their test", nobz.get("success", false) and bool(_unit("U_NOBZ_A").flags.get("battle_shocked", false)))
	_check("unattached Nobz: no BREAKIN' HEADS window", not phase.has_pending_stratagem_window())
	r = SM.can_use_stratagem(1, sid, "U_NOBZ_A", {"window_id": "unit_battle_shocked", "unit_id": "U_NOBZ_A"})
	_check("validate: only an attached unit", not r.can_use and "attached" in str(r.reason), str(r))

	var cp0 := _cp(1)
	var res = phase.execute_action({"type": "BATTLE_SHOCK_TEST", "unit_id": "U_BOYZ_B", "player": 1, "dice_roll": [1, 1]})
	_check("Boyz fail their test", res.get("success", false) and not res.get("test_passed", true))
	_check("Boyz + attached Warboss battle-shocked", bool(_unit("U_BOYZ_B").flags.get("battle_shocked", false)) and bool(_unit("U_WARBOSS_A").flags.get("battle_shocked", false)))
	var w := _pending_window(phase)
	_check("unit_battle_shocked window pending for P1 (the owner)", str(w.get("window_id", "")) == "unit_battle_shocked" and int(w.get("player", 0)) == 1, str(w.get("window_id", "")))
	_check("window ctx names the Attached unit (Boyz B)", str(w.get("ctx", {}).get("unit_id", "")) == "U_BOYZ_B")
	var offer := _offers_for(w.get("offers", []), sid)
	_check("BREAKIN' HEADS offered on the battle-shocked unit", _target_ids(offer) == ["U_BOYZ_B"], str(_target_ids(offer)))
	_check("action result stamped for the network mirror", res.has("stratagem_window_opened"))
	var blocked = phase.execute_action({"type": "END_COMMAND", "player": 1})
	_check("phase waits for the decision", not blocked.get("success", true))
	_check("no offers for P2 in this window", SM.get_window_offers(2, "unit_battle_shocked", {"unit_id": "U_BOYZ_B"}).is_empty())

	# Nested event: another attached ORKS INFANTRY unit becomes battle-shocked
	# while the window is pending — queued, opened when this one closes.
	GS.state.units.U_RUNTHERD_A["attached_to"] = "U_GRETCHIN_C"
	GS.state.units.U_GRETCHIN_C["attachment_data"] = {"attached_characters": ["U_RUNTHERD_A"]}
	GS.state.units.U_GRETCHIN_C.flags["battle_shocked"] = true
	GS.state.units.U_RUNTHERD_A.flags["battle_shocked"] = true
	phase._window_events_flush({})
	_check("nested event queued behind the pending window", phase._ev_deferred.size() == 1 and str(phase.get_pending_stratagem_window().get("ctx", {}).get("unit_id", "")) == "U_BOYZ_B", str(phase._ev_deferred))
	var dec = phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_battle_shocked"})
	_check("DECLINE succeeds, no CP spent", dec.get("success", false) and _cp(1) == cp0)
	_check("Boyz still battle-shocked after decline", bool(_unit("U_BOYZ_B").flags.get("battle_shocked", false)))
	w = _pending_window(phase)
	_check("the queued window opens next (Gretchin C)", str(w.get("window_id", "")) == "unit_battle_shocked" and str(w.get("ctx", {}).get("unit_id", "")) == "U_GRETCHIN_C", str(w.get("ctx", {})))
	_check("its result is stamped (network)", dec.has("stratagem_window_opened"))

	var alive_before := _alive("U_GRETCHIN_C")
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_battle_shocked", "stratagem_id": sid, "target_unit_id": "U_GRETCHIN_C"})
	_check("USE on Gretchin C (+Runtherd) succeeds", use.get("success", false), str(use.get("error", "")))
	_check("CP -1", _cp(1) == cp0 - 1)
	var rec: Dictionary = _unit("U_GRETCHIN_C").flags.get("ork11e_breakin_heads", {})
	var d3 := int(rec.get("d3", 0))
	_check("D3 rolled (1-3)", d3 >= 1 and d3 <= 3, str(rec))
	_check("D3 mortal wounds: %d Gretchin (W1) destroyed" % d3, alive_before - _alive("U_GRETCHIN_C") == d3, "%d -> %d" % [alive_before, _alive("U_GRETCHIN_C")])
	_check("no longer battle-shocked (unit + attached character)", not _unit("U_GRETCHIN_C").flags.get("battle_shocked", true) and not _unit("U_RUNTHERD_A").flags.get("battle_shocked", true))
	r = SM.can_use_stratagem(1, sid, "U_BOYZ_B", {"window_id": "unit_battle_shocked", "unit_id": "U_BOYZ_B"})
	_check("once per phase", not r.can_use, str(r))
	PM.transition_to_phase(PHASE_MOVEMENT)
	_check("record cleared at end of phase", not _unit("U_GRETCHIN_C").flags.has("ork11e_breakin_heads"))

	# AI decider: answered synchronously right after the failed test.
	_check("fixture reloaded", _load("ork11e_orks_active"))
	_kill("U_BOYZ_B", 6)
	for uid in ["U_BOYZ_B", "U_WARBOSS_A"]:
		GS.state.units[uid].meta.stats["leadership"] = 13
	PM.transition_to_phase(PHASE_COMMAND)
	phase = _phase()
	var cp_ai := _cp(1)
	var alive_ai := _alive("U_BOYZ_B")
	_ai_on(1)
	var ai_res = phase.execute_action({"type": "BATTLE_SHOCK_TEST", "unit_id": "U_BOYZ_B", "player": 1, "dice_roll": [1, 1]})
	_ai_off()
	_check("AI: no pending window", not phase.has_pending_stratagem_window())
	_check("AI used BREAKIN' HEADS (CP -1, not battle-shocked)", _cp(1) == cp_ai - 1 and not _unit("U_BOYZ_B").flags.get("battle_shocked", true), "cp %d -> %d" % [cp_ai, _cp(1)])
	_check("AI: D3 Boyz lost", alive_ai - _alive("U_BOYZ_B") == int(_unit("U_BOYZ_B").flags.get("ork11e_breakin_heads", {}).get("d3", -1)))
	var has_cp_diff := false
	for d in ai_res.get("changes", []):
		if str(d.get("path", "")) == "players.1.cp":
			has_cp_diff = true
	_check("AI use diffs ride in the action result (replay/network)", has_cp_diff)


# ---------------------------------------------------------------------------
# D. IMPENDING KRUNCH
# ---------------------------------------------------------------------------
func _charge_to_engagement(phase, charger: String, target: String, seed_val: int) -> Dictionary:
	var dec = phase.execute_action({"type": "DECLARE_CHARGE", "actor_unit_id": charger, "player": 1, "payload": {"target_unit_ids": [target]}})
	if not dec.get("success", false):
		return {"error": "DECLARE_CHARGE: %s" % str(dec.get("error", dec.get("errors", "")))}
	if phase.has_pending_stratagem_window():
		return {"error": "unexpected window after DECLARE_CHARGE"}
	if phase.awaiting_fire_overwatch:
		phase.execute_action({"type": "DECLINE_FIRE_OVERWATCH", "player": 2})
	var roll = phase.execute_action({"type": "CHARGE_ROLL", "actor_unit_id": charger, "player": 1, "payload": {"rng_seed": seed_val}})
	if not roll.get("success", false):
		return {"error": "CHARGE_ROLL: %s" % str(roll.get("error", ""))}
	if phase.awaiting_ability_reroll:
		phase.execute_action({"type": "DECLINE_ABILITY_REROLL", "actor_unit_id": charger, "player": 1})
	if phase.awaiting_reroll_decision:
		phase.execute_action({"type": "DECLINE_COMMAND_REROLL", "actor_unit_id": charger, "player": 1})
	if not phase.pending_charges.has(charger):
		return {"error": "charge failed after the roll"}
	var dist := int(phase.pending_charges[charger].get("distance", 0))
	var mv: Dictionary = ADM._compute_charge_move(GS.create_snapshot(), charger, dist, [target], 1)
	if str(mv.get("type", "")) != "APPLY_CHARGE_MOVE":
		return {"error": "no legal charge move (%s)" % str(mv.get("_ai_description", ""))}
	mv["player"] = 1
	var applied = phase.execute_action(mv)
	applied["_distance"] = dist
	return applied


func _section_impending_krunch() -> void:
	print("\n-- D. IMPENDING KRUNCH (unit_ended_charge_move) --")
	_check("fixture ork11e_orks_active loads", _load("ork11e_orks_active"))
	_set_detachment(1, "Blitz Brigade")
	var sid := _sid(1, "impending-krunch-blitz-brigade")
	_check("IMPENDING KRUNCH loaded for P1 (Blitz Brigade)", sid != "")
	GS.state.players["2"]["cp"] = 0   # no Fire Overwatch for the Custodes
	# Custodian Guard E alone in the open, the Battlewagon ~4" in front of it.
	_move_to("U_CUSTODIAN_GUARD_E", Vector2(40, 52))
	_move_to("U_BATTLEWAGON_A", Vector2(40, 44.5))
	_check("setup: Battlewagon unengaged", not RE.is_unit_engaged("U_BATTLEWAGON_A", GS.state))
	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(PHASE_CHARGE)
	var phase = _phase()
	_check("in the Charge phase, P1 active", GS.get_current_phase() == PHASE_CHARGE and GS.get_active_player() == 1)
	var cp0 := _cp(1)
	var applied := {}
	for s in [11, 21, 31, 41, 51]:
		applied = _charge_to_engagement(phase, "U_BATTLEWAGON_A", "U_CUSTODIAN_GUARD_E", s)
		if applied.get("success", false):
			break
		print("    (charge attempt with seed %d: %s)" % [s, str(applied.get("error", ""))])
		PM.transition_to_phase(PHASE_CHARGE)
		phase = _phase()
	_check("Battlewagon charge move applied (roll %d)" % int(applied.get("_distance", 0)), applied.get("success", false), str(applied.get("error", "")))
	_check("Battlewagon engaged with Custodian Guard E", RE.check_units_in_engagement_range(_unit("U_BATTLEWAGON_A"), _unit("U_CUSTODIAN_GUARD_E"), GS.state))
	var w := _pending_window(phase)
	_check("unit_ended_charge_move window pending for P1", str(w.get("window_id", "")) == "unit_ended_charge_move" and int(w.get("player", 0)) == 1, str(w.get("window_id", "")))
	var offer := _offers_for(w.get("offers", []), sid)
	_check("IMPENDING KRUNCH offered on the Battlewagon", _target_ids(offer) == ["U_BATTLEWAGON_A"], str(_target_ids(offer)))
	_check("the charge move rode in the paused result", applied.get("changes", []).size() > 0)
	_check("not offered for a non-WAGON charger", _offers_for(SM.get_window_offers(1, "unit_ended_charge_move", {"unit_id": "U_NOBZ_A"}), sid).is_empty())
	_check("not offered in another window", _offers_for(SM.get_window_offers(1, "unit_declares_charge", {"unit_id": "U_BATTLEWAGON_A"}), sid).is_empty())
	_check("no offers for P2", SM.get_window_offers(2, "unit_ended_charge_move", {"unit_id": "U_BATTLEWAGON_A"}).is_empty())
	var shocked_before := {}
	for uid in GS.state.units:
		shocked_before[uid] = bool(GS.state.units[uid].get("flags", {}).get("battle_shocked", false))
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_ended_charge_move", "stratagem_id": sid, "target_unit_id": "U_BATTLEWAGON_A"})
	_check("USE succeeds", use.get("success", false), str(use.get("error", "")))
	_check("CP -1", _cp(1) == cp0 - 1, "%d -> %d" % [cp0, _cp(1)])
	var results: Array = _unit("U_BATTLEWAGON_A").flags.get("ork11e_impending_krunch", [])
	var rolled_ids: Array = []
	var consistent := true
	var minus_one := true
	for rr in results:
		rolled_ids.append(str(rr.get("unit_id", "")))
		var dice: Array = rr.get("dice", [])
		if dice.size() == 2 and int(rr.total) != int(dice[0]) + int(dice[1]) - 1:
			minus_one = false
		var now_shocked := bool(_unit(str(rr.unit_id)).flags.get("battle_shocked", false))
		if not shocked_before.get(str(rr.unit_id), false) and now_shocked == bool(rr.get("passed", true)):
			consistent = false
	_check("Custodian Guard E made a battle-shock roll", "U_CUSTODIAN_GUARD_E" in rolled_ids, str(results))
	_check("every roll is 2D6 - 1", minus_one, str(results))
	_check("failed rolls => battle-shocked, passed => not", consistent, str(results))
	var engaged_now: Array = load("res://scripts/stratagems/ork_codex/OrkCodexOther.gd")._engaged_enemy_units("U_BATTLEWAGON_A")
	var all_rolled := true
	for e in engaged_now:
		if not e in rolled_ids:
			all_rolled = false
	_check("each engaged enemy unit rolled (%s)" % str(engaged_now), all_rolled and rolled_ids.size() == engaged_now.size())
	_check("window closed, charge flow resumed (no error)", not phase.has_pending_stratagem_window() and not use.has("resume_error"))

	# A/B of the modifier with the same seed (engine roll helper).
	RE.set_test_seed(777)
	var a = FAM.force_battle_shock_test("U_CUSTODIAN_GUARD_D", 0, "A")
	RE.set_test_seed(777)
	var b = FAM.force_battle_shock_test("U_CUSTODIAN_GUARD_D", -1, "B")
	RE.set_test_seed(-1)
	_check("A/B same seed: -1 lowers the total by exactly 1 (%d -> %d)" % [int(a.total), int(b.total)], a.dice == b.dice and int(b.total) == int(a.total) - 1)
	GS.state.units.U_CUSTODIAN_GUARD_D.flags["battle_shocked"] = false

	PM.transition_to_phase(PHASE_FIGHT)
	_check("record cleared at end of phase", not _unit("U_BATTLEWAGON_A").flags.has("ork11e_impending_krunch"))

	# AI decider.
	_check("fixture reloaded", _load("ork11e_orks_active"))
	_set_detachment(1, "Blitz Brigade")
	GS.state.players["2"]["cp"] = 0
	_move_to("U_CUSTODIAN_GUARD_E", Vector2(40, 52))
	_move_to("U_BATTLEWAGON_A", Vector2(40, 44.5))
	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(PHASE_CHARGE)
	phase = _phase()
	var cp_ai := _cp(1)
	_ai_on(1)
	var ai_applied := {}
	for s in [11, 21, 31, 41, 51]:
		ai_applied = _charge_to_engagement(phase, "U_BATTLEWAGON_A", "U_CUSTODIAN_GUARD_E", s)
		if ai_applied.get("success", false):
			break
		PM.transition_to_phase(PHASE_CHARGE)
		phase = _phase()
	_ai_off()
	_check("AI: charge applied, no pending window", ai_applied.get("success", false) and not phase.has_pending_stratagem_window(), str(ai_applied.get("error", "")))
	_check("AI used IMPENDING KRUNCH (CP -1, rolls recorded)", _cp(1) == cp_ai - 1 and not _unit("U_BATTLEWAGON_A").flags.get("ork11e_impending_krunch", []).is_empty(), "cp %d -> %d" % [cp_ai, _cp(1)])


# ---------------------------------------------------------------------------
# E. FLYIN' HEADBUTT
# ---------------------------------------------------------------------------
func _setup_flyboyz_shooting() -> String:
	_load("ork11e_orks_reactive")
	_set_detachment(2, "Flyboyz")
	# The Dakkajet and Custodian Guard F in the open, 10" apart; the jet down
	# to 1 wound (setup privilege: T2 / no save so one shot kills it).
	_move_to("U_DAKKAJET_A", Vector2(41, 35))
	_move_to("U_CUSTODIAN_GUARD_F", Vector2(41, 24))
	var jet: Dictionary = _unit("U_DAKKAJET_A")
	jet.models[0]["current_wounds"] = 1
	jet.meta.stats["toughness"] = 2
	jet.meta.stats["save"] = 7
	PM.transition_to_phase(PHASE_COMMAND)
	_cus11e_unready()
	PM.transition_to_phase(PHASE_SHOOTING)
	return _sid(2, "flyin-headbutt-flyboyz")


func _section_flyin_headbutt() -> void:
	print("\n-- E. FLYIN' HEADBUTT (unit_destroyed, before Deadly Demise) --")
	var sid := _setup_flyboyz_shooting()
	_check("FLYIN' HEADBUTT loaded for P2 (Flyboyz)", sid != "")
	var phase = _phase()
	_check("Custodes (P1) Shooting phase", GS.get_current_phase() == PHASE_SHOOTING and GS.get_active_player() == 1)
	_check("setup: Custodian Guard F unengaged", not RE.is_unit_engaged("U_CUSTODIAN_GUARD_F", GS.state))
	var cp0 := _cp(2)
	var res := {}
	for s in [5, 6, 7, 8, 9]:
		res = _shoot(phase, "U_CUSTODIAN_GUARD_F", "U_DAKKAJET_A", s)
		if _alive("U_DAKKAJET_A") == 0:
			break
	_check("Custodian Guard F's SHOOT destroys the Dakkajet", res.get("success", false) and _alive("U_DAKKAJET_A") == 0, str(res.get("error", "")))
	var w := _pending_window(phase)
	_check("unit_destroyed window pending for P2 (the owner, non-active)", str(w.get("window_id", "")) == "unit_destroyed" and int(w.get("player", 0)) == 2, str(w.get("window_id", "")))
	var offer := _offers_for(w.get("offers", []), sid)
	_check("FLYIN' HEADBUTT offered on the destroyed Dakkajet", _target_ids(offer) == ["U_DAKKAJET_A"], str(_target_ids(offer)))
	var opts := _secondary_ids(offer, "U_DAKKAJET_A")
	_check("enemy units within 12\" offered (Custodian Guard F)", "U_CUSTODIAN_GUARD_F" in opts, str(opts))
	_check("enemy units beyond 12\" not offered", not "U_CUSTODIAN_GUARD_A" in opts, str(opts))
	_check("Deadly Demise held until the window closes", phase._ev_dd_held.has("U_DAKKAJET_A"))
	_check("no offers for P1 in this window", SM.get_window_offers(1, "unit_destroyed", {"unit_id": "U_DAKKAJET_A"}).is_empty())
	var r = SM.can_use_stratagem(2, sid, "U_GRETCHIN_C", {"window_id": "unit_destroyed", "unit_id": "U_GRETCHIN_C"})
	_check("validate: ORKS AIRCRAFT only", not r.can_use and "AIRCRAFT" in str(r.reason), str(r))
	var wounds_before := _wounds("U_CUSTODIAN_GUARD_F")
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 2, "window_id": "unit_destroyed", "stratagem_id": sid, "target_unit_id": "U_DAKKAJET_A", "context": {"secondary_id": "U_CUSTODIAN_GUARD_F"}})
	_check("USE (select Custodian Guard F) succeeds", use.get("success", false), str(use.get("error", "")))
	_check("CP -1 (P2)", _cp(2) == cp0 - 1)
	var rec: Dictionary = _unit("U_DAKKAJET_A").flags.get("ork11e_flyin_headbutt", {})
	var rolls: Array = rec.get("rolls", [])
	var fours := 0
	for x in rolls:
		if int(x) >= 4:
			fours += 1
	_check("eight D6 rolled", rolls.size() == 8, str(rec))
	_check("one mortal wound per 4+ (%d)" % fours, int(rec.get("mortal_wounds", -1)) == fours)
	_check("Custodian Guard F lost %d wound(s)" % fours, wounds_before - _wounds("U_CUSTODIAN_GUARD_F") == fours, "%d -> %d" % [wounds_before, _wounds("U_CUSTODIAN_GUARD_F")])
	_check("the Dakkajet no longer has Deadly Demise", not root.get_node("UnitAbilityManager").has_deadly_demise("U_DAKKAJET_A"))
	_check("held Deadly Demise released and skipped", not phase._ev_dd_held.has("U_DAKKAJET_A") and "U_DAKKAJET_A" in phase._ev_dd_released)
	PM.transition_to_phase(PHASE_CHARGE)
	_check("flags cleared at end of phase", not _unit("U_DAKKAJET_A").flags.has("ork11e_no_deadly_demise"))

	# DECLINE: Deadly Demise is rolled once the window closes.
	sid = _setup_flyboyz_shooting()
	phase = _phase()
	for s in [5, 6, 7, 8, 9]:
		_shoot(phase, "U_CUSTODIAN_GUARD_F", "U_DAKKAJET_A", s)
		if _alive("U_DAKKAJET_A") == 0:
			break
	_check("decline run: window pending, Deadly Demise held", phase.has_pending_stratagem_window() and phase._ev_dd_held.has("U_DAKKAJET_A"))
	var dec = phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 2, "window_id": "unit_destroyed"})
	_check("DECLINE succeeds", dec.get("success", false))
	_check("Deadly Demise resolved after the decline (ability intact)", "U_DAKKAJET_A" in phase._ev_dd_released and root.get_node("UnitAbilityManager").has_deadly_demise("U_DAKKAJET_A"))

	# AI decider (P2 AI): synchronous, Deadly Demise skipped.
	sid = _setup_flyboyz_shooting()
	phase = _phase()
	var cp_ai := _cp(2)
	_ai_on(2)
	for s in [5, 6, 7, 8, 9]:
		_shoot(phase, "U_CUSTODIAN_GUARD_F", "U_DAKKAJET_A", s)
		if _alive("U_DAKKAJET_A") == 0:
			break
	_ai_off()
	_check("AI: no pending window", not phase.has_pending_stratagem_window())
	_check("AI used FLYIN' HEADBUTT (CP -1, no Deadly Demise)", _cp(2) == cp_ai - 1 and bool(_unit("U_DAKKAJET_A").flags.get("ork11e_no_deadly_demise", false)), "cp %d -> %d" % [cp_ai, _cp(2)])
	_check("AI: Deadly Demise never held", not phase._ev_dd_held.has("U_DAKKAJET_A"))


# ---------------------------------------------------------------------------
# F. INFESTED WAR ZONE
# ---------------------------------------------------------------------------
func _setup_runt_swarm_shooting(alive_left: int = 1) -> String:
	_load("ork11e_orks_reactive")
	_set_detachment(2, "Runt Swarm")
	_move_to("U_GRETCHIN_C", Vector2(40, 35))
	_move_to("U_CUSTODIAN_GUARD_F", Vector2(41, 24))
	_kill("U_GRETCHIN_C", 10 - alive_left)
	PM.transition_to_phase(PHASE_COMMAND)
	_cus11e_unready()
	PM.transition_to_phase(PHASE_SHOOTING)
	return _sid(2, "infested-war-zone-runt-swarm")


func _section_infested_war_zone() -> void:
	print("\n-- F. INFESTED WAR ZONE (enemy_unit_has_attacked + new_reserve_unit) --")
	var sid := _setup_runt_swarm_shooting()
	_check("INFESTED WAR ZONE loaded for P2 (Runt Swarm)", sid != "")
	var phase = _phase()
	var cp0 := _cp(2)
	var units_before: int = GS.state.units.size()
	var res := {}
	for s in [5, 6, 7, 8, 9]:
		res = _shoot(phase, "U_CUSTODIAN_GUARD_F", "U_GRETCHIN_C", s)
		if _alive("U_GRETCHIN_C") == 0:
			break
	_check("Custodian Guard F's SHOOT destroys Gretchin C", res.get("success", false) and _alive("U_GRETCHIN_C") == 0, str(res.get("error", "")))
	var w := _pending_window(phase)
	_check("enemy_unit_has_attacked window pending for P2", str(w.get("window_id", "")) == "enemy_unit_has_attacked" and int(w.get("player", 0)) == 2, str(w.get("window_id", "")))
	_check("ctx: attacker + destroyed units", str(w.get("ctx", {}).get("attacker_unit_id", "")) == "U_CUSTODIAN_GUARD_F" and w.get("ctx", {}).get("destroyed_unit_ids", []) == ["U_GRETCHIN_C"], str(w.get("ctx", {})))
	var offer := _offers_for(w.get("offers", []), sid)
	_check("INFESTED WAR ZONE offered on the destroyed Gretchin unit (2 CP)", _target_ids(offer) == ["U_GRETCHIN_C"] and int(offer.get("cp_cost", 0)) == 2, str(offer.get("targets", [])))
	_check("no offers for P1", SM.get_window_offers(1, "enemy_unit_has_attacked", {"attacker_unit_id": "U_CUSTODIAN_GUARD_F", "destroyed_unit_ids": ["U_GRETCHIN_C"]}).is_empty())
	var r = SM.can_use_stratagem(2, sid, "U_KOMMANDOS_A", {"window_id": "enemy_unit_has_attacked", "destroyed_unit_ids": ["U_KOMMANDOS_A"]})
	_check("validate: GRETCHIN only", not r.can_use and "GRETCHIN" in str(r.reason), str(r))
	r = SM.can_use_stratagem(2, sid, "U_GRETCHIN_D", {"window_id": "enemy_unit_has_attacked", "destroyed_unit_ids": ["U_GRETCHIN_C"]})
	_check("validate: a Gretchin unit that was not destroyed is refused", not r.can_use, str(r))
	GS.state.players["2"]["cp"] = 1
	_check("1 CP: not offered (2 CP)", SM.get_window_offers(2, "enemy_unit_has_attacked", w.get("ctx", {})).is_empty())
	GS.state.players["2"]["cp"] = cp0
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 2, "window_id": "enemy_unit_has_attacked", "stratagem_id": sid, "target_unit_id": "U_GRETCHIN_C"})
	_check("USE succeeds", use.get("success", false), str(use.get("error", "")))
	_check("CP -2", _cp(2) == cp0 - 2, "%d -> %d" % [cp0, _cp(2)])
	var new_id := "U_GRETCHIN_C_R2"
	var nu: Dictionary = _unit(new_id)
	_check("a NEW unit %s was added" % new_id, not nu.is_empty() and GS.state.units.size() == units_before + 1)
	_check("new unit: P2, in Strategic Reserves", int(nu.get("owner", 0)) == 2 and int(nu.get("status", -1)) == 7 and str(nu.get("reserve_type", "")) == "strategic_reserves", "%s/%s" % [nu.get("status"), nu.get("reserve_type")])
	_check("new unit: starting strength (10 models, all alive, full wounds)", nu.get("models", []).size() == 10 and _alive(new_id) == 10 and _wounds(new_id) == 10)
	var no_pos := true
	for m in nu.get("models", []):
		if m.get("position", null) != null:
			no_pos = false
	_check("new unit: not on the battlefield (no positions)", no_pos)
	_check("new unit: identical datasheet (name, keywords, weapons)", str(nu.meta.name) == str(_unit("U_GRETCHIN_C").meta.name) and nu.meta.keywords == _unit("U_GRETCHIN_C").meta.keywords and nu.meta.weapons.size() == _unit("U_GRETCHIN_C").meta.weapons.size())
	_check("new unit: fresh flags, no attachment", nu.get("flags", {}).is_empty() and nu.get("attached_to", null) == null)
	_check("new unit listed in P2's reserves (normal arrival flow)", new_id in GS.get_reserves_for_player(2))
	_check("the destroyed unit stays destroyed", _alive("U_GRETCHIN_C") == 0)
	var replay_has_unit := false
	for d in use.get("changes", []):
		if str(d.get("path", "")) == "units.%s" % new_id:
			replay_has_unit = true
	_check("the new unit diff rides in the action result (replay/network)", replay_has_unit)

	# AI decider.
	sid = _setup_runt_swarm_shooting()
	phase = _phase()
	var cp_ai := _cp(2)
	_ai_on(2)
	for s in [5, 6, 7, 8, 9]:
		_shoot(phase, "U_CUSTODIAN_GUARD_F", "U_GRETCHIN_C", s)
		if _alive("U_GRETCHIN_C") == 0:
			break
	_ai_off()
	_check("AI: no pending window", not phase.has_pending_stratagem_window())
	_check("AI used INFESTED WAR ZONE (CP -2, new unit in reserves)", _cp(2) == cp_ai - 2 and not _unit("U_GRETCHIN_C_R2").is_empty(), "cp %d -> %d" % [cp_ai, _cp(2)])

	# Not an enemy attack: the Orks' own action destroying their Gretchin opens
	# no enemy_unit_has_attacked window.
	_load("ork11e_orks_reactive")
	_set_detachment(2, "Runt Swarm")
	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(PHASE_SHOOTING)
	phase = _phase()
	_kill("U_GRETCHIN_C", 10)
	phase._window_events_flush({})
	_check("Gretchin destroyed outside an enemy attack: no INFESTED WAR ZONE window", not phase.has_pending_stratagem_window())


# ---------------------------------------------------------------------------
# G. unit_declares_charge hook
# ---------------------------------------------------------------------------
func _section_declares_charge_hook() -> void:
	print("\n-- G. unit_declares_charge hook (synthetic window stratagem) --")
	_load("ork11e_orks_active")
	GS.state.players["2"]["cp"] = 0
	var sid := "faction_test_window_declares_charge"
	SM.stratagems[sid] = {
		"id": sid, "csv_id": "test-window-declares-charge", "name": "TEST DECLARES CHARGE",
		"type": "Test Stratagem", "cp_cost": 1, "implemented": true,
		"timing": {"turn": "your", "phase": "charge", "trigger": "unit_declares_charge", "windows": ["unit_declares_charge"]},
		"target": {"type": "unit", "owner": "friendly", "conditions": []},
		"effects": [], "restrictions": {"once_per": "phase"},
		"effect_text": "Test-only window stratagem.", "description": "Test-only window stratagem."}
	SM._player_faction_stratagems["1"].append(sid)
	_move_to("U_CUSTODIAN_GUARD_E", Vector2(40, 52))
	_move_to("U_KOMMANDOS_A", Vector2(40, 45))
	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(PHASE_CHARGE)
	var phase = _phase()
	var cp0 := _cp(1)
	var dec = phase.execute_action({"type": "DECLARE_CHARGE", "actor_unit_id": "U_KOMMANDOS_A", "player": 1, "payload": {"target_unit_ids": ["U_CUSTODIAN_GUARD_E"]}})
	_check("DECLARE_CHARGE succeeds", dec.get("success", false), str(dec.get("error", "")))
	var w := _pending_window(phase)
	_check("unit_declares_charge window pending for P1, before the roll", str(w.get("window_id", "")) == "unit_declares_charge" and str(w.get("ctx", {}).get("unit_id", "")) == "U_KOMMANDOS_A" and w.get("ctx", {}).get("target_unit_ids", []) == ["U_CUSTODIAN_GUARD_E"], str(w.get("ctx", {})))
	var roll = phase.execute_action({"type": "CHARGE_ROLL", "actor_unit_id": "U_KOMMANDOS_A", "player": 1})
	_check("charge roll waits for the decision", not roll.get("success", true))
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_declares_charge", "stratagem_id": sid, "target_unit_id": "U_KOMMANDOS_A"})
	_check("USE succeeds and resumes the declaration flow", use.get("success", false) and not use.has("resume_error"), str(use.get("error", "")))
	_check("CP -1", _cp(1) == cp0 - 1)
	roll = phase.execute_action({"type": "CHARGE_ROLL", "actor_unit_id": "U_KOMMANDOS_A", "player": 1, "payload": {"rng_seed": 3}})
	_check("charge roll proceeds after the window", roll.get("success", false), str(roll.get("error", "")))
	SM._player_faction_stratagems["1"].erase(sid)
	SM.stratagems.erase(sid)


# ---------------------------------------------------------------------------
# H. END_COMMAND auto-resolve
# ---------------------------------------------------------------------------
func _section_end_command_auto_resolve() -> void:
	print("\n-- H. END_COMMAND auto-resolved tests apply their flags --")
	_load("ork11e_orks_active")
	_kill("U_NOBZ_A", 3)
	_kill("U_BOYZ_B", 6)
	for uid in ["U_NOBZ_A", "U_BOYZ_B", "U_WARBOSS_A"]:
		GS.state.units[uid].meta.stats["leadership"] = 13
	PM.transition_to_phase(PHASE_COMMAND)
	var phase = _phase()
	var res = phase.execute_action({"type": "END_COMMAND", "player": 1})
	_check("END_COMMAND succeeds (CP available: no stranded Command Re-roll)", res.get("success", false))
	_check("auto-resolved failure: Nobz battle-shocked", bool(_unit("U_NOBZ_A").flags.get("battle_shocked", false)))
	_check("auto-resolved failure: Boyz + Warboss battle-shocked", bool(_unit("U_BOYZ_B").flags.get("battle_shocked", false)) and bool(_unit("U_WARBOSS_A").flags.get("battle_shocked", false)))
	# WH-6: the window opens "when it becomes battle-shocked" — in the Command
	# phase; END_COMMAND finishes ending the phase once it closes.
	_check("the Command phase waits (same instance)", GS.get_current_phase() == PHASE_COMMAND and _phase() == phase)
	var w := _pending_window(phase)
	_check("the Boyz' unit_battle_shocked window opens in the Command phase", str(w.get("window_id", "")) == "unit_battle_shocked" and str(w.get("ctx", {}).get("unit_id", "")) == "U_BOYZ_B", str(w.get("window_id", "")))
	_check("END_COMMAND result stamped with the opened window", res.has("stratagem_window_opened"))
	var dec = phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_battle_shocked"})
	_check("decline -> the Command phase ends (Movement)", dec.get("success", false) and GS.get_current_phase() == PHASE_MOVEMENT and _phase() != phase, str(dec.get("error", "")))
	_check("no window handed to the Movement phase", not _phase().has_pending_stratagem_window())


# ---------------------------------------------------------------------------
# I. Desperate escape battle-shock roll (09.07) -> unit_battle_shocked
# ---------------------------------------------------------------------------
func _section_desperate_escape() -> void:
	print("\n-- I. desperate escape battle-shock roll -> BREAKIN' HEADS (Movement) --")
	_load("ork11e_orks_active")
	GS.state.players["2"]["cp"] = 0   # no Fire Overwatch
	for uid in ["U_BOYZ_B", "U_WARBOSS_A"]:
		GS.state.units[uid].meta.stats["leadership"] = 13
	var sid := _sid(1, "breakin-heads-war-horde")
	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(PHASE_MOVEMENT)
	var phase = _phase()
	var begin = phase.execute_action({"type": "BEGIN_FALL_BACK", "actor_unit_id": "U_BOYZ_B", "player": 1, "payload": {"fall_back_mode": "desperate_escape"}})
	_check("BEGIN_FALL_BACK (desperate escape) succeeds", begin.get("success", false), str(begin.get("error", "")))
	_check("not battle-shocked before the move ends", not _unit("U_BOYZ_B").flags.get("battle_shocked", false))
	var conf = phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_BOYZ_B", "player": 1})
	_check("CONFIRM_UNIT_MOVE succeeds", conf.get("success", false), str(conf.get("error", "")))
	_check("desperate escape battle-shock roll failed at Ld 13: Boyz + Warboss battle-shocked",
		bool(_unit("U_BOYZ_B").flags.get("battle_shocked", false)) and bool(_unit("U_WARBOSS_A").flags.get("battle_shocked", false)))
	_check("pending_battleshock_roll resolved", not _unit("U_BOYZ_B").flags.get("pending_battleshock_roll", true))
	var w := _pending_window(phase)
	_check("BREAKIN' HEADS window in the Movement phase", str(w.get("window_id", "")) == "unit_battle_shocked" and not _offers_for(w.get("offers", []), sid).is_empty(), str(w.get("window_id", "")))
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_battle_shocked", "stratagem_id": sid, "target_unit_id": "U_BOYZ_B"})
	_check("USE in the Movement phase succeeds", use.get("success", false) and not _unit("U_BOYZ_B").flags.get("battle_shocked", true), str(use.get("error", "")))

	# A unit that is already battle-shocked makes no roll (and opens nothing).
	_load("ork11e_orks_active")
	GS.state.players["2"]["cp"] = 0
	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(PHASE_MOVEMENT)
	phase = _phase()
	GS.state.units.U_NOBZ_A.flags["battle_shocked"] = true
	phase.execute_action({"type": "BEGIN_FALL_BACK", "actor_unit_id": "U_NOBZ_A", "player": 1, "payload": {"fall_back_mode": "desperate_escape"}})
	phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_NOBZ_A", "player": 1})
	_check("already battle-shocked: no roll, no window", not phase.has_pending_stratagem_window())


# ---------------------------------------------------------------------------
# J. enemy_unit_has_attacked after a MELEE activation
# ---------------------------------------------------------------------------
func _melee_weapon(uid: String) -> String:
	var weapons: Dictionary = RE.get_unit_melee_weapons(uid, GS.state)
	for mid in weapons:
		for wid in weapons[mid]:
			return str(wid)
	return ""


func _section_infested_fight() -> void:
	print("\n-- J. enemy_unit_has_attacked after a melee activation (Fight phase) --")
	_load("ork11e_orks_reactive")
	_set_detachment(2, "Runt Swarm")
	GS.state.players["2"]["cp"] = 4
	var sid := _sid(2, "infested-war-zone-runt-swarm")
	_move_to("U_GRETCHIN_C", Vector2(40, 35))
	_kill("U_GRETCHIN_C", 9)
	# Custodian Guard F in base contact with the last Grot (model m10).
	var grot: Dictionary = _unit("U_GRETCHIN_C").models[9]
	var cg_m1: Dictionary = _unit("U_CUSTODIAN_GUARD_F").models[0]
	var dx: float = float(grot.position.x) - float(cg_m1.position.x)
	var dy: float = (float(grot.position.y) - 0.8 * PX - 0.5 * PX) - float(cg_m1.position.y)
	_translate("U_CUSTODIAN_GUARD_F", dx / PX, dy / PX)
	_check("setup: Custodian Guard F engaged with Gretchin C", RE.check_units_in_engagement_range(_unit("U_CUSTODIAN_GUARD_F"), _unit("U_GRETCHIN_C"), GS.state))
	PM.transition_to_phase(PHASE_COMMAND)
	_cus11e_unready()
	PM.transition_to_phase(PHASE_FIGHT)
	var phase = _phase()
	for p in [1, 2]:
		if int(phase.pile_in_step_11e) != int(phase.PileInStep11e.ACTIVE):
			break
		phase.execute_action({"type": "END_PILE_IN", "player": int(phase.piling_in_player_11e)})
	var sel = phase.execute_action({"type": "SELECT_FIGHTER", "unit_id": "U_CUSTODIAN_GUARD_F", "player": 1})
	_check("Custodes select Custodian Guard F to fight", sel.get("success", false) and phase.active_fighter_id == "U_CUSTODIAN_GUARD_F", str(sel.get("error", "")))
	var wid := _melee_weapon("U_CUSTODIAN_GUARD_F")
	var asg = phase.execute_action({"type": "ASSIGN_ATTACKS", "unit_id": "U_CUSTODIAN_GUARD_F", "target_id": "U_GRETCHIN_C", "weapon_id": wid, "attacking_models": [], "player": 1})
	_check("melee attacks assigned (%s)" % wid, asg.get("success", false) and wid != "", str(asg.get("error", asg.get("errors", ""))))
	var conf = phase.execute_action({"type": "CONFIRM_AND_RESOLVE_ATTACKS", "player": 1})
	_check("attacks confirmed", conf.get("success", false), str(conf.get("error", "")))
	var roll = phase.execute_action({"type": "ROLL_DICE", "player": 1, "payload": {"fast_roll": true, "rng_seed": 7}})
	_check("melee resolved", roll.get("success", false), str(roll.get("error", "")))
	_check("Gretchin C destroyed in melee", _alive("U_GRETCHIN_C") == 0)
	var w := _pending_window(phase)
	var guard := 0
	# The window opens once the fighter's activation is over (consolidation).
	while w.is_empty() and phase.active_fighter_id == "U_CUSTODIAN_GUARD_F" and guard < 4:
		guard += 1
		var acts: Array = phase.get_available_actions()
		var done := false
		for a in acts:
			var t := str(a.get("type", ""))
			if t in ["CONSOLIDATE", "SKIP_CONSOLIDATE", "END_CONSOLIDATE", "CONFIRM_CONSOLIDATE", "SKIP_CONSOLIDATION"]:
				var act: Dictionary = a.duplicate(true)
				act["player"] = 1
				if t == "CONSOLIDATE" and not act.has("payload"):
					act["payload"] = {"movements": {}}
				phase.execute_action(act)
				done = true
				break
		if not done:
			print("    (no consolidation action among %s)" % str(acts.map(func(x): return x.get("type", ""))))
			break
		w = _pending_window(phase)
	_check("enemy_unit_has_attacked window for P2 after the melee activation", str(w.get("window_id", "")) == "enemy_unit_has_attacked" and int(w.get("player", 0)) == 2, "window=%s active_fighter=%s" % [str(w.get("window_id", "")), phase.active_fighter_id])
	_check("ctx: Custodian Guard F destroyed Gretchin C", str(w.get("ctx", {}).get("attacker_unit_id", "")) == "U_CUSTODIAN_GUARD_F" and w.get("ctx", {}).get("destroyed_unit_ids", []) == ["U_GRETCHIN_C"], str(w.get("ctx", {})))
	_check("INFESTED WAR ZONE offered", not _offers_for(w.get("offers", []), sid).is_empty())
	if phase.has_pending_stratagem_window():
		var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 2, "window_id": "enemy_unit_has_attacked", "stratagem_id": sid, "target_unit_id": "U_GRETCHIN_C"})
		_check("USE in the Fight phase: new Gretchin unit in reserves", use.get("success", false) and int(_unit("U_GRETCHIN_C_R2").get("status", -1)) == 7, str(use.get("error", "")))
