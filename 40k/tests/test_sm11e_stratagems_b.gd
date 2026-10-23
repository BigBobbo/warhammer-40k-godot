extends SceneTree

# Codex: Space Marines (11e) — the 24 stratagems of the eight WP-M2b generic
# detachments (WP-M3b, SMCodexB.gd + SMCodexBCombat / SMCodexBAction), driven
# through StratagemManager -> the custom:sm11e dispatcher (SMCodex11e.gd; the
# WP-M3b stub until M3a's dispatcher lands — same API).
# Fixtures (tests/helpers/gen_sm11e_m3b_fixtures.gd):
#   sm11e_m3b_active   P1 Space Marines ACTIVE vs P2 Orks
#   sm11e_m3b_reactive P1 Orks ACTIVE vs P2 Space Marines
# The Space Marines player gets all eight detachments, set in-test.
#
#   A. registry / data: 24 ids (facade == groups), implemented, windows,
#      dispatcher routing, non-SM army refused, a Space Wolves army taking the
#      detachments gets the SM rows (loader fallback)
#   B. FOR THE EMPEROR!  command_phase_main (real END_COMMAND hook) + the new
#      command_phase_opponent window, +1 OC (MissionManager.model_oc), re-offer,
#      expiry (turn stamp)
#   C. Fight buffs  GENE-WROUGHT MIGHT / ANNIHILATING FORCE / MERCY IS WEAKNESS
#      / RELENTLESS ASSAULT  unit_selected_to_fight (real SELECT_FIGHTER hook),
#      variants, A/B (same seeds), 15.01, expiry
#   D. Shooting buffs  MERCILESS VETERANS / STORM OF FIRE / ANNIHILATING FORCE /
#      MERCY / RELENTLESS / POINT-BLANK BRUTALITY  unit_selected_to_shoot
#      (real SELECT_SHOOTER hook), doctrine +1 AP, close-quarters grant, A/B
#   E. Defensive  TACTICAL DREADNOUGHT FORTITUDE / ARMOUR OF CONTEMPT x3 /
#      DUTY IN DEATH  enemy_targets_unit_fight / _shooting, -1 D / -1 AP A/B,
#      ends when that enemy unit has attacked, Fight On Death 4+ (+1 assault)
#   F. Post-shot  PURGATION PUSH / SUPPRESSION VOLLEYS / DOMINATION FIRE
#      (unit_has_shot, real SHOOT hook) + HAIL OF VENGEANCE (enemy_has_shot,
#      destroyed_unit_ids), suppressed -1 to hit until the start of your next turn
#   G. Movement  STAND UNYIELDING (movement_phase_end), UPSTOPPABLE ADVANCE
#      (unit_selected_to_move / unit_declares_charge), MASTERFUL TACTICS
#      (enemy_ended_move, D6 / 6" with the tactical doctrine)
#   H. ARMOURED IMPACT (unit_ended_charge_move), ADAMANTINE TERROR
#      (fight_phase_start), GUNSHIP EXTRACTION (fight_phase_end, opponent's)
#   I. AI deciders never stall (command, fight, post-shot, enemy_has_shot)
#
# Usage: godot --headless --path 40k --script tests/test_sm11e_stratagems_b.gd

const ACTIVE := "sm11e_m3b_active"
const REACTIVE := "sm11e_m3b_reactive"
const PHASE_COMMAND := 6
const PHASE_MOVEMENT := 7
const PHASE_SHOOTING := 8
const PHASE_CHARGE := 9
const PHASE_FIGHT := 10
const PX := 40.0
const DETS := ["Terminator Storm Force", "Assault Brethren", "Gravis Linebreaker Force", "Devastator Brethren",
	"Gravis Siege Force", "Tactical Brethren", "Ironclad Champions", "Tacticus Firestorm Force"]

const CSV_TDF := "tactical-dreadnought-fortitude-terminator-storm-force"
const CSV_MERCILESS := "merciless-veterans-terminator-storm-force"
const CSV_GUNSHIP := "gunship-extraction-terminator-storm-force"
const CSV_AOC_AB := "armour-of-contempt-assault-brethren"
const CSV_DUTY := "duty-in-death-assault-brethren"
const CSV_GENE := "gene-wrought-might-assault-brethren"
const CSV_IMPACT := "armoured-impact-gravis-linebreaker-force"
const CSV_ANNIH_GLF := "annihilating-force-gravis-linebreaker-force"
const CSV_PUSH := "purgation-push-gravis-linebreaker-force"
const CSV_AOC_DB := "armour-of-contempt-devastator-brethren"
const CSV_HAIL := "hail-of-vengeance-devastator-brethren"
const CSV_STORM := "storm-of-fire-devastator-brethren"
const CSV_SUPPRESSION := "suppression-volleys-gravis-siege-force"
const CSV_STAND := "stand-unyielding-gravis-siege-force"
const CSV_ANNIH_GSF := "annihilating-force-gravis-siege-force"
const CSV_AOC_TB := "armour-of-contempt-tactical-brethren"
const CSV_DOMINATION := "domination-fire-tactical-brethren"
const CSV_MASTERFUL := "masterful-tactics-tactical-brethren"
const CSV_ADAMANTINE := "adamantine-terror-ironclad-champions"
const CSV_UPSTOPPABLE := "upstoppable-advance-ironclad-champions"
const CSV_MERCY := "mercy-is-weakness-ironclad-champions"
const CSV_POINT_BLANK := "point-blank-brutality-tacticus-firestorm-force"
const CSV_EMPEROR := "for-the-emperor-tacticus-firestorm-force"
const CSV_RELENTLESS := "relentless-assault-tacticus-firestorm-force"

const TARGETS2 := ["enemy_targets_unit_shooting", "enemy_targets_unit_fight"]
const SHOOT_FIGHT := ["unit_selected_to_shoot", "unit_selected_to_fight"]
const EXPECTED_WINDOWS := {
	CSV_TDF: TARGETS2, CSV_MERCILESS: ["unit_selected_to_shoot"], CSV_GUNSHIP: ["fight_phase_end"],
	CSV_AOC_AB: TARGETS2, CSV_DUTY: ["enemy_targets_unit_fight"], CSV_GENE: ["unit_selected_to_fight"],
	CSV_IMPACT: ["unit_ended_charge_move"], CSV_ANNIH_GLF: SHOOT_FIGHT, CSV_PUSH: ["unit_has_shot"],
	CSV_AOC_DB: TARGETS2, CSV_HAIL: ["enemy_has_shot"], CSV_STORM: ["unit_selected_to_shoot"],
	CSV_SUPPRESSION: ["unit_has_shot"], CSV_STAND: ["movement_phase_end"], CSV_ANNIH_GSF: SHOOT_FIGHT,
	CSV_AOC_TB: TARGETS2, CSV_DOMINATION: ["unit_has_shot"], CSV_MASTERFUL: ["enemy_ended_move"],
	CSV_ADAMANTINE: ["fight_phase_start"], CSV_UPSTOPPABLE: ["unit_selected_to_move", "unit_declares_charge"],
	CSV_MERCY: SHOOT_FIGHT, CSV_POINT_BLANK: ["unit_selected_to_shoot"],
	CSV_EMPEROR: ["command_phase_main", "command_phase_opponent"], CSV_RELENTLESS: SHOOT_FIGHT,
}
const EXPECTED_CP := {CSV_TDF: 2, CSV_HAIL: 2}

var passed := 0
var failed := 0
var SM = null
var GS = null
var PM = null
var RE = null
var MM = null
var B = null
var Dispatcher = null
var Common = null
var RM = null
var _sm := 1


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

func _stage_fixture(fixture: String, faction_name: String = "") -> bool:
	var slm = root.get_node("SaveLoadManager")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slm.save_directory))
	for ext in [".w40ksave", ".meta"]:
		var src = "res://tests/saves/" + fixture + ext
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(slm.save_directory + fixture + ext))
	var ok = slm.load_game(fixture)
	GameConstants.edition = 11
	_sm = 1 if fixture == ACTIVE else 2
	if faction_name != "":
		GS.state.factions[str(_sm)]["name"] = faction_name
	GS.state.factions[str(_sm)]["detachment"] = DETS[0]
	GS.state.factions[str(_sm)]["detachments"] = DETS.duplicate()
	SM.load_faction_stratagems_for_player(_sm)
	_reset_usage()
	return ok


func _reset_usage(cp: int = 8) -> void:
	SM._usage_history = {"1": [], "2": []}
	SM.active_effects = []
	GS.state.players["1"]["cp"] = cp
	GS.state.players["2"]["cp"] = cp


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


func _offers(player: int, window_id: String, ctx: Dictionary) -> Array:
	return SM.get_window_offers(player, window_id, ctx)


func _no_phase_advance(phase) -> void:
	if phase.phase_completed.is_connected(PM._on_phase_completed):
		phase.phase_completed.disconnect(PM._on_phase_completed)


func _decline_pending(phase) -> int:
	var n := 0
	while phase.has_pending_stratagem_window() and n < 8:
		var w: Dictionary = phase.get_pending_stratagem_window()
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(w.get("player", 0)), "window_id": str(w.get("window_id", ""))})
		n += 1
	return n


func _decline_until(phase, player: int, window_id: String = "") -> void:
	var n := 0
	while phase.has_pending_stratagem_window() and n < 8:
		var w: Dictionary = phase.get_pending_stratagem_window()
		if int(w.get("player", 0)) == player and (window_id == "" or str(w.get("window_id", "")) == window_id):
			return
		print("    declining %s for P%d" % [str(w.get("window_id", "")), int(w.get("player", 0))])
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(w.get("player", 0)), "window_id": str(w.get("window_id", ""))})
		n += 1


func _phase(phase_id: int):
	_reset_usage()
	PM.transition_to_phase(PHASE_COMMAND)
	if phase_id != PHASE_COMMAND:
		PM.transition_to_phase(phase_id)
	var phase = PM.get_current_phase_instance()
	_no_phase_advance(phase)
	_decline_pending(phase)
	return phase


func _translate(uid: String, dx_in: float, dy_in: float) -> void:
	for m in _unit(uid).get("models", []):
		var p = m.get("position", null)
		if p is Dictionary:
			m["position"] = {"x": float(p.x) + dx_in * PX, "y": float(p.y) + dy_in * PX}
		elif p is Vector2:
			m["position"] = {"x": p.x + dx_in * PX, "y": p.y + dy_in * PX}


func _log_count(fragment: String) -> int:
	var gel = root.get_node_or_null("GameEventLog")
	var n := 0
	if gel and "entries" in gel:
		for e in gel.entries:
			if fragment in str(e.get("text", "")):
				n += 1
	return n


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


func _use(phase, player: int, window_id: String, sid: String, target: String, ctx: Dictionary = {}) -> Dictionary:
	var a := {"type": "USE_WINDOW_STRATAGEM", "player": player, "window_id": window_id, "stratagem_id": sid, "target_unit_id": target}
	if not ctx.is_empty():
		a["context"] = ctx
	return phase.execute_action(a)


## Synthetic attack board for A/B: attackers U_ATK (owner 1) vs U_TGT (owner 2).
func _board(att_flags: Dictionary, weapon: Dictionary, n_att: int, tgt_kw: Array = ["INFANTRY"], tgt_flags: Dictionary = {},
		tgt_save: int = 7, tgt_t: int = 4, tgt_wounds: int = 3) -> Dictionary:
	var atk: Array = []
	for i in range(n_att):
		atk.append({"id": "ma%d" % i, "position": {"x": 10.0, "y": 10.0 + i * 30}, "base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 3, "current_wounds": 3})
	var tgt: Array = []
	for i in range(6):
		tgt.append({"id": "mt%d" % i, "position": {"x": 45.0, "y": 10.0 + i * 30}, "base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": tgt_wounds, "current_wounds": tgt_wounds})
	return {"units": {
		"U_ATK": {"id": "U_ATK", "owner": 1, "status": 2,
			"meta": {"name": "Attackers", "keywords": ["ADEPTUS ASTARTES", "INFANTRY"], "stats": {"toughness": 4, "save": 6, "wounds": 3},
				"abilities": [], "weapons": [weapon]},
			"flags": att_flags, "models": atk},
		"U_TGT": {"id": "U_TGT", "owner": 2, "status": 2,
			"meta": {"name": "Targets", "keywords": tgt_kw, "stats": {"toughness": tgt_t, "save": tgt_save, "wounds": tgt_wounds}, "abilities": []},
			"flags": tgt_flags, "models": tgt},
	}, "meta": {"phase": 10, "active_player": 1, "battle_round": 2}}


func _melee_weapon(ws: String, s: String, d: String, a: String = "4", ap: String = "0", rules: String = "") -> Dictionary:
	return {"name": "Test Blade", "type": "Melee", "range": "Melee", "attacks": a, "weapon_skill": ws,
		"strength": s, "ap": ap, "damage": d, "special_rules": rules}


func _melee(board: Dictionary, seed_val: int) -> Dictionary:
	RE.set_test_seed(seed_val)
	var rng = RE.RNGService.new()
	return RE.resolve_melee_attacks({"type": "FIGHT", "actor_unit_id": "U_ATK",
		"payload": {"assignments": [{"attacker": "U_ATK", "target": "U_TGT", "weapon": "Test Blade"}]}}, board, rng)


func _wounds_lost(result: Dictionary, board: Dictionary) -> int:
	var final := {}
	for d in result.get("diffs", []):
		var path := str(d.get("path", ""))
		if path.begins_with("units.U_TGT.models.") and path.ends_with(".current_wounds"):
			final[path] = int(d.get("value", 0))
	var lost := 0
	for path in final:
		var idx := int(path.split(".")[3])
		lost += int(board.units.U_TGT.models[idx].get("wounds", 1)) - int(final[path])
	return lost


## Melee A/B over seeds: wounds the target lost [off, on].
func _ab_melee(board_off: Dictionary, board_on: Dictionary, seeds: Array) -> Array:
	var out := [0, 0]
	for sd in seeds:
		out[0] += _wounds_lost(_melee(board_off.duplicate(true), int(sd)), board_off)
		out[1] += _wounds_lost(_melee(board_on.duplicate(true), int(sd)), board_on)
	return out


## Atomic SHOOT with every ranged weapon of `shooter` that can target `target`
## (the AI / auto-shoot payload); the defender's reactive dialog is declined.
func _shoot(phase, shooter: String, target: String) -> Dictionary:
	var board: Dictionary = GS.create_snapshot()
	var elig: Dictionary = RE.get_eligible_targets(shooter, board).get(target, {})
	var weapons: Array = elig.get("weapons_in_range", [])
	var per_weapon := {}
	var uw: Dictionary = RE.get_unit_weapons(shooter, board)
	for mid in uw:
		for wid in uw[mid]:
			if wid in weapons:
				if not per_weapon.has(wid):
					per_weapon[wid] = []
				per_weapon[wid].append(mid)
	var assignments: Array = []
	for wid in per_weapon:
		assignments.append({"weapon_id": wid, "target_unit_id": target, "model_ids": per_weapon[wid]})
	if assignments.is_empty():
		print("  [diag] %s cannot target %s — eligible: %s" % [shooter, target, str(RE.get_eligible_targets(shooter, board).keys())])
	var r: Dictionary = phase.execute_action({"type": "SHOOT", "actor_unit_id": shooter, "player": int(GS.state.units[shooter].owner),
		"payload": {"assignments": assignments}})
	if phase.awaiting_reactive_stratagem:
		var defender := 2 if int(GS.state.units[shooter].owner) == 1 else 1
		r = phase.execute_action({"type": "DECLINE_REACTIVE_STRATAGEM", "player": defender})
	return r


func _mods(actor: Dictionary, target: Dictionary, melee: bool, weapon: Dictionary = {}) -> Dictionary:
	return RE.ork11e_ab_mods(actor, target, weapon, melee, GS.state)


# ---------------------------------------------------------------------------
func _run() -> void:
	SM = root.get_node("StratagemManager")
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	MM = root.get_node("MissionManager")
	B = load("res://scripts/codex/space_marines/SMCodexB.gd")
	Dispatcher = load("res://scripts/codex/space_marines/SMCodex11e.gd")
	Common = load("res://scripts/codex/space_wolves/SWCommon.gd")
	RM = load("res://scripts/rules/ReactiveMove11e.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	GS.set_edition(11)
	root.get_node("SettingsService").set("auto_allocate_wounds", true)

	print("\n=== test_sm11e_stratagems_b ===\n")
	_check("fixture %s loads" % ACTIVE, _stage_fixture(ACTIVE))
	_section_registry()
	_section_command()
	_section_fight_buffs()
	_section_shooting_buffs()
	_section_defensive()
	_section_post_shot()
	_section_movement()
	_section_charge_fight_misc()
	_section_ai()
	RE.set_test_seed(-1)


# ---------------------------------------------------------------------------
func _section_registry() -> void:
	print("\n-- A. registry / data --")
	var C = load("res://scripts/codex/space_marines/SMCodexBCombat.gd")
	var Ac = load("res://scripts/codex/space_marines/SMCodexBAction.gd")
	var union: Array = C.IDS + Ac.IDS
	union.sort()
	var facade: Array = B.handled_ids()
	facade.sort()
	_check("SMCodexB.IDS (24) == SMCodexBCombat.IDS + SMCodexBAction.IDS", facade.size() == 24 and facade == union, str(facade.size()))
	var all_impl := true
	for k in B.IDS:
		all_impl = all_impl and bool(B.IMPLEMENTED.get(k, false))
	_check("every id IMPLEMENTED", all_impl and B.IMPLEMENTED.size() == 24)
	_check("the dispatcher (SMCodex11e) loads SMCodexB and registers 24 ids", Dispatcher.all_implemented_ids().size() == 24, str(Dispatcher.all_implemented_ids().size()))
	var loaded := 0
	for s in SM.get_faction_stratagems_for_player(1):
		var csv := str(s.get("csv_id", ""))
		if not csv in B.IDS:
			continue
		loaded += 1
		_check("%s: implemented, routed to the custom:sm11e dispatcher" % csv, bool(s.get("implemented", false)) and SM.codex_for(s) == Dispatcher)
		var w: Array = s.get("timing", {}).get("windows", [])
		_check("%s windows = %s" % [csv, str(EXPECTED_WINDOWS.get(csv, "?"))], w == EXPECTED_WINDOWS.get(csv, ["?"]), str(w))
		_check("%s costs %d CP" % [csv, int(EXPECTED_CP.get(csv, 1))], int(s.get("cp_cost", -1)) == int(EXPECTED_CP.get(csv, 1)), str(s.get("cp_cost", -1)))
	_check("all 24 loaded for P1 (8 detachments)", loaded == 24, str(loaded))
	var strat: Dictionary = SM.get_stratagem(_sid(1, CSV_ADAMANTINE))
	var v = Dispatcher.validate(strat, 2, "U_MEGANOBZ_A", {"window_id": "fight_phase_start"})
	_check("a non-Space Marines army (Orks) is refused", not v.ok and "Space Marines" in str(v.reason), str(v))
	_check("the facade itself refuses a non-SM army", not B.validate(strat, 2, "U_MEGANOBZ_A", {}).ok)
	# A Space Wolves army taking these detachments gets the SM rows (loader fallback).
	_stage_fixture(ACTIVE, "Space Wolves")
	var sw_loaded := 0
	for s in SM.get_faction_stratagems_for_player(1):
		if str(s.get("csv_id", "")) in B.IDS and bool(s.get("implemented", false)):
			sw_loaded += 1
	_check("a Space Wolves army with the 8 detachments gets all 24 SM rows", sw_loaded == 24, str(sw_loaded))
	_phase(PHASE_FIGHT)
	var sw_offers := _offers(1, "fight_phase_start", {"phase": "fight"})
	_check("…and they are offered (ADAMANTINE TERROR on the Redemptor)", "U_REDEMPTOR_DREADNOUGHT_A" in _offer_targets(sw_offers, _sid(1, CSV_ADAMANTINE)), str(_offer_ids(sw_offers)))
	_stage_fixture(ACTIVE)


# ---------------------------------------------------------------------------
func _section_command() -> void:
	print("\n-- B. FOR THE EMPEROR! (command_phase_main / command_phase_opponent) --")
	_stage_fixture(ACTIVE)
	var fe := _sid(1, CSV_EMPEROR)
	var phase = _phase(PHASE_COMMAND)
	var offers := _offers(1, "command_phase_main", {"phase": "command"})
	var t := _offer_targets(offers, fe)
	_check("offered on the Assault Intercessors (TACTICUS, within range of obj_home_2)", "U_ASSAULT_INTERCESSOR_SQUAD_A" in t, str(t))
	_check("not on the Eradicators (GRAVIS, not TACTICUS)", not "U_ERADICATOR_SQUAD_WITH_MELTA_RIFLES_A" in t)
	_check("not on the Hellblasters (TACTICUS, no objective in range)", not "U_HELLBLASTER_SQUAD_A" in t)
	_check("not offered in another window", not fe in _offer_ids(_offers(1, "battle_shock_step_start", {"phase": "command"})))
	var oc_model: Dictionary = _unit("U_ASSAULT_INTERCESSOR_SQUAD_A").models[0]
	var oc0 := int(MM.model_oc(_unit("U_ASSAULT_INTERCESSOR_SQUAD_A"), oc_model))
	var r = phase.execute_action({"type": "END_COMMAND", "player": 1})
	var pend: Dictionary = phase.get_pending_stratagem_window()
	_check("END_COMMAND opens command_phase_main for P1", str(pend.get("window_id", "")) == "command_phase_main" and int(pend.get("player", 0)) == 1, "%s / %s" % [str(r.get("error", "")), str(pend.get("window_id", ""))])
	if not phase.has_pending_stratagem_window():
		phase.open_stratagem_window(1, "command_phase_main", {"phase": "command"}, "")
	var cp0 := _cp(1)
	var use := _use(phase, 1, "command_phase_main", fe, "U_ASSAULT_INTERCESSOR_SQUAD_A")
	_check("USE FOR THE EMPEROR! succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	var oc1 := int(MM.model_oc(_unit("U_ASSAULT_INTERCESSOR_SQUAD_A"), oc_model))
	_check("+1 OC per model (%d -> %d)" % [oc0, oc1], oc1 == oc0 + 1)
	_check("after the use the Command-phase windows continue (FOR THE EMPEROR! no longer offered)", not fe in _offer_ids(phase.get_pending_stratagem_window().get("offers", [])) and _offers(1, "command_phase_main", {"phase": "command"}).is_empty())
	_check("once per phase: refused again", not SM.can_use_stratagem(1, fe, "U_ASSAULT_INTERCESSOR_SQUAD_A", {"window_id": "command_phase_main"}).can_use)
	_decline_pending(phase)
	_check("Game Log names it", _log_count("FOR THE EMPEROR!") >= 1)
	# Expiry: the turn stamp — the bonus ends with the turn even if the flag lingers.
	GS.state.meta["active_player"] = 2
	_check("the +1 OC ends with the turn (turn stamp)", int(MM.model_oc(_unit("U_ASSAULT_INTERCESSOR_SQUAD_A"), oc_model)) == oc0)
	GS.state.meta["active_player"] = 1
	SM.on_turn_start(2)
	_check("the end-of-turn expiry clears the flag", not _flags("U_ASSAULT_INTERCESSOR_SQUAD_A").has("sm11e_for_the_emperor"))
	# The opponent's Command phase: the reactive fixture (Orks active).
	_stage_fixture(REACTIVE)
	fe = _sid(2, CSV_EMPEROR)
	phase = _phase(PHASE_COMMAND)
	_check("command_phase_main is NOT offered to the non-active SM player", not fe in _offer_ids(_offers(2, "command_phase_main", {"phase": "command"})))
	var opp_t := _offer_targets(_offers(2, "command_phase_opponent", {"phase": "command"}), fe)
	_check("command_phase_opponent offers it to the SM player in the Ork Command phase", "U_ASSAULT_INTERCESSOR_SQUAD_A" in opp_t, str(opp_t))
	_check("…but never to the active player", not SM.can_use_stratagem(1, fe, "U_ASSAULT_INTERCESSOR_SQUAD_A", {"window_id": "command_phase_opponent"}).can_use)
	r = phase.execute_action({"type": "END_COMMAND", "player": 1})
	_decline_until(phase, 2, "command_phase_opponent")
	pend = phase.get_pending_stratagem_window()
	_check("END_COMMAND (Orks) opens command_phase_opponent for P2", str(pend.get("window_id", "")) == "command_phase_opponent" and int(pend.get("player", 0)) == 2, str(pend.get("window_id", "")))
	if str(pend.get("window_id", "")) == "command_phase_opponent":
		cp0 = _cp(2)
		use = _use(phase, 2, "command_phase_opponent", fe, "U_ASSAULT_INTERCESSOR_SQUAD_A")
		_check("USE in the opponent's Command phase succeeds, CP -1", use.get("success", false) and _cp(2) == cp0 - 1, str(use.get("error", "")))
		_check("+1 OC during the opponent's turn", int(MM.model_oc(_unit("U_ASSAULT_INTERCESSOR_SQUAD_A"), _unit("U_ASSAULT_INTERCESSOR_SQUAD_A").models[0])) == oc0 + 1)
	_decline_pending(phase)


# ---------------------------------------------------------------------------
func _section_fight_buffs() -> void:
	print("\n-- C. GENE-WROUGHT MIGHT / ANNIHILATING FORCE / MERCY IS WEAKNESS / RELENTLESS ASSAULT (unit_selected_to_fight) --")
	_stage_fixture(ACTIVE)
	var gw := _sid(1, CSV_GENE)
	var af := _sid(1, CSV_ANNIH_GLF)
	var af2 := _sid(1, CSV_ANNIH_GSF)
	var mw := _sid(1, CSV_MERCY)
	var ra := _sid(1, CSV_RELENTLESS)
	var phase = _phase(PHASE_FIGHT)
	var w := "unit_selected_to_fight"
	var hi := _offer_ids(_offers(1, w, {"phase": "fight", "unit_id": "U_HEAVY_INTERCESSOR_SQUAD_A"}))
	_check("Heavy Intercessors (GRAVIS TACTICUS?): GENE-WROUGHT + both ANNIHILATING FORCE offered; MERCY not", gw in hi and af in hi and af2 in hi and not mw in hi, str(hi))
	var rd := _offer_ids(_offers(1, w, {"phase": "fight", "unit_id": "U_REDEMPTOR_DREADNOUGHT_A"}))
	_check("Redemptor (DREADNOUGHT): MERCY + GENE-WROUGHT offered; ANNIHILATING / RELENTLESS not", mw in rd and gw in rd and not af in rd and not ra in rd, str(rd))
	var it := _offer_ids(_offers(1, w, {"phase": "fight", "unit_id": "U_INTERCESSOR_SQUAD_A"}))
	_check("Intercessors (TACTICUS): RELENTLESS offered", ra in it, str(it))
	_check("nothing offered to P2 (Orks)", not gw in _offer_ids(_offers(2, w, {"phase": "fight", "unit_id": "U_NOBZ_A"})))
	_check("not in unit_selected_to_move", not gw in _offer_ids(_offers(1, "unit_selected_to_move", {"unit_id": "U_HEAVY_INTERCESSOR_SQUAD_A", "move_type": "normal"})))
	var mercy_e := _offer_entry(_offers(1, w, {"phase": "fight", "unit_id": "U_REDEMPTOR_DREADNOUGHT_A"}), mw, "U_REDEMPTOR_DREADNOUGHT_A")
	_check("MERCY IS WEAKNESS: a choice of [LETHAL HITS] / [SUSTAINED HITS 1] is required", bool(mercy_e.get("require_variant", false)) and mercy_e.get("variants", []).size() == 2, str(mercy_e))
	# Real hook: SELECT_FIGHTER.
	for _i in [1, 2]:
		if int(phase.pile_in_step_11e) != int(phase.PileInStep11e.ACTIVE):
			break
		phase.execute_action({"type": "END_PILE_IN", "player": int(phase.piling_in_player_11e)})
		_decline_pending(phase)
	var sel = phase.sequencer_11e.peek_selection(GS.state)
	if int(sel.get("player", 0)) == 1:
		var r = phase.execute_action({"type": "SELECT_FIGHTER", "unit_id": "U_HEAVY_INTERCESSOR_SQUAD_A", "player": 1})
		var pend: Dictionary = phase.get_pending_stratagem_window()
		_check("SELECT_FIGHTER Heavy Intercessors opens unit_selected_to_fight for P1", r.get("success", false) and str(pend.get("window_id", "")) == w and int(pend.get("player", 0)) == 1, "%s / %s" % [str(r.get("error", "")), str(pend.get("window_id", ""))])
	else:
		_check("P1 selects first (precondition for the SELECT_FIGHTER hook)", false, str(sel))
	if not phase.has_pending_stratagem_window():
		phase.open_stratagem_window(1, w, {"phase": "fight", "unit_id": "U_HEAVY_INTERCESSOR_SQUAD_A"}, "")
	var cp0 := _cp(1)
	GS.state.factions["1"]["sw11e_doctrine"] = "assault"
	var use := _use(phase, 1, w, gw, "U_HEAVY_INTERCESSOR_SQUAD_A")
	_check("USE GENE-WROUGHT MIGHT succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	var f := _flags("U_HEAVY_INTERCESSOR_SQUAD_A")
	_check("melee [LANCE] grant + marker", bool(f.get("effect_grant_lance", false)) and bool(f.get("sm11e_gene_wrought", false)), str(f))
	var hu := _unit("U_HEAVY_INTERCESSOR_SQUAD_A")
	_check("assault doctrine: +1 AP on melee only", int(_mods(hu, _unit("U_NOBZ_A"), true).get("ap", 0)) == 1 and int(_mods(hu, _unit("U_NOBZ_A"), false).get("ap", 0)) == 0)
	GS.state.factions["1"]["sw11e_doctrine"] = ""
	_check("no assault doctrine: no +1 AP", int(_mods(hu, _unit("U_NOBZ_A"), true).get("ap", 0)) == 0)
	_check("15.01: ANNIHILATING FORCE refused on the same unit this phase", not SM.can_use_stratagem(1, af, "U_HEAVY_INTERCESSOR_SQUAD_A", {"window_id": w, "unit_id": "U_HEAVY_INTERCESSOR_SQUAD_A"}).can_use)
	_check("once per phase: GENE-WROUGHT refused on another unit", not SM.can_use_stratagem(1, gw, "U_TERMINATOR_SQUAD_A", {"window_id": w, "unit_id": "U_TERMINATOR_SQUAD_A"}).can_use)
	SM.on_phase_end(PHASE_FIGHT)
	f = _flags("U_HEAVY_INTERCESSOR_SQUAD_A")
	_check("expiry: [LANCE] grant and marker cleared at the end of the phase", not f.has("effect_grant_lance") and not f.has("sm11e_gene_wrought"), str(f))
	# A/B GENE-WROUGHT +1 AP: 4+ save target, AP 0 blade.
	var wpn := _melee_weapon("3", "5", "1", "6")
	var ab := _ab_melee(_board({}, wpn, 3, ["INFANTRY"], {}, 4), _board({"sm11e_gene_wrought": true, "effect_grant_lance": true}, wpn, 3, ["INFANTRY"], {}, 4), range(9100, 9130))
	print("    A/B GENE-WROUGHT (no doctrine in the synthetic board: [LANCE] only, no charge): %s" % str(ab))
	_check("A/B GENE-WROUGHT without a charge / doctrine changes nothing (same seeds)", ab[0] == ab[1], str(ab))
	ab = _ab_melee(_board({"charged_this_turn": true}, wpn, 3, ["INFANTRY"], {}, 4, 6), _board({"charged_this_turn": true, "sm11e_gene_wrought": true, "effect_grant_lance": true}, wpn, 3, ["INFANTRY"], {}, 4, 6), range(9130, 9160))
	_check("A/B GENE-WROUGHT after a charge move: [LANCE] +1 to wound -> more wounds (%d -> %d)" % [ab[0], ab[1]], ab[1] > ab[0], str(ab))
	# ANNIHILATING FORCE melee A/B: lethal hits on a T10 target.
	_reset_usage()
	var r2 = SM.use_stratagem(1, af, "U_HEAVY_INTERCESSOR_SQUAD_A", {"window_id": w, "unit_id": "U_HEAVY_INTERCESSOR_SQUAD_A"})
	_check("ANNIHILATING FORCE (GLF) direct use succeeds", r2.get("success", false), str(r2.get("error", "")))
	_check("…[LETHAL HITS] melee and ranged", bool(_mods(hu, _unit("U_NOBZ_A"), true).get("lethal", false)) and bool(_mods(hu, _unit("U_NOBZ_A"), false).get("lethal", false)))
	var w4 := _melee_weapon("3", "4", "1", "6")
	ab = _ab_melee(_board({}, w4, 3, ["VEHICLE"], {}, 7, 10), _board({"sm11e_annihilating": true}, w4, 3, ["VEHICLE"], {}, 7, 10), range(9200, 9230))
	_check("A/B ANNIHILATING FORCE: more wounds on T10 (%d -> %d)" % [ab[0], ab[1]], ab[1] > ab[0], str(ab))
	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry: sm11e_annihilating cleared", not _flags("U_HEAVY_INTERCESSOR_SQUAD_A").has("sm11e_annihilating"))
	# MERCY IS WEAKNESS variants.
	_reset_usage()
	var bad = SM.can_use_stratagem(1, mw, "U_REDEMPTOR_DREADNOUGHT_A", {"window_id": w, "unit_id": "U_REDEMPTOR_DREADNOUGHT_A", "variant_id": "bogus"})
	_check("MERCY: an unknown choice is refused", not bad.can_use)
	r2 = SM.use_stratagem(1, mw, "U_REDEMPTOR_DREADNOUGHT_A", {"window_id": w, "unit_id": "U_REDEMPTOR_DREADNOUGHT_A", "variant_id": "sustained"})
	_check("MERCY (sustained) succeeds", r2.get("success", false), str(r2.get("error", "")))
	var rdu := _unit("U_REDEMPTOR_DREADNOUGHT_A")
	_check("…[SUSTAINED HITS 1], not lethal", int(_mods(rdu, _unit("U_MEGANOBZ_A"), true).get("sustained", 0)) == 1 and not bool(_mods(rdu, _unit("U_MEGANOBZ_A"), true).get("lethal", false)))
	ab = _ab_melee(_board({}, w4, 3), _board({"sm11e_mercy": "sustained"}, w4, 3), range(9300, 9330))
	_check("A/B MERCY sustained: more wounds (%d -> %d)" % [ab[0], ab[1]], ab[1] > ab[0], str(ab))
	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry: sm11e_mercy cleared", not _flags("U_REDEMPTOR_DREADNOUGHT_A").has("sm11e_mercy"))
	# RELENTLESS ASSAULT conditional keywords.
	_reset_usage()
	r2 = SM.use_stratagem(1, ra, "U_INTERCESSOR_SQUAD_A", {"window_id": w, "unit_id": "U_INTERCESSOR_SQUAD_A", "variant_id": "sustained"})
	_check("RELENTLESS (sustained: non-MONSTER/VEHICLE) succeeds", r2.get("success", false), str(r2.get("error", "")))
	var iu := _unit("U_INTERCESSOR_SQUAD_A")
	_check("…[SUSTAINED HITS 1] vs Gretchin (INFANTRY)", int(_mods(iu, _unit("U_GRETCHIN_C"), true).get("sustained", 0)) == 1)
	_check("…none vs the Redemptor-like VEHICLE (Meganobz are not; use a VEHICLE dict)", int(_mods(iu, {"id": "X", "meta": {"keywords": ["VEHICLE"]}}, true).get("sustained", 0)) == 0)
	_flags("U_INTERCESSOR_SQUAD_A")["sm11e_relentless"] = "lethal"
	_check("lethal variant: [LETHAL HITS] vs a VEHICLE only", bool(_mods(iu, {"id": "X", "meta": {"keywords": ["VEHICLE"]}}, true).get("lethal", false)) and not bool(_mods(iu, _unit("U_GRETCHIN_C"), true).get("lethal", false)))
	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry: sm11e_relentless cleared", not _flags("U_INTERCESSOR_SQUAD_A").has("sm11e_relentless"))


# ---------------------------------------------------------------------------
func _section_shooting_buffs() -> void:
	print("\n-- D. MERCILESS VETERANS / STORM OF FIRE / ANNIHILATING / MERCY / RELENTLESS / POINT-BLANK BRUTALITY (unit_selected_to_shoot) --")
	_stage_fixture(ACTIVE)
	var mv := _sid(1, CSV_MERCILESS)
	var sf := _sid(1, CSV_STORM)
	var pb := _sid(1, CSV_POINT_BLANK)
	var af := _sid(1, CSV_ANNIH_GSF)
	var phase = _phase(PHASE_SHOOTING)
	var w := "unit_selected_to_shoot"
	var ts := _offer_ids(_offers(1, w, {"phase": "shooting", "unit_id": "U_TERMINATOR_SQUAD_A"}))
	_check("Terminator Squad: MERCILESS VETERANS + STORM OF FIRE offered", mv in ts and sf in ts, str(ts))
	var hb := _offer_ids(_offers(1, w, {"phase": "shooting", "unit_id": "U_HELLBLASTER_SQUAD_A"}))
	_check("Hellblasters: MERCILESS not (not TERMINATOR); POINT-BLANK not (unengaged)", not mv in hb and not pb in hb and sf in hb, str(hb))
	var it := _offer_ids(_offers(1, w, {"phase": "shooting", "unit_id": "U_INTERCESSOR_SQUAD_A"}))
	_check("Intercessors (engaged TACTICUS): POINT-BLANK BRUTALITY offered", pb in it, str(it))
	var ag := _offer_ids(_offers(1, w, {"phase": "shooting", "unit_id": "U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A"}))
	_check("Eradicators HB (GRAVIS): ANNIHILATING FORCE offered", af in ag, str(ag))
	# Opponent's Shooting phase: never.
	_stage_fixture(REACTIVE)
	_check("not in the opponent's Shooting phase", not SM.can_use_stratagem(2, _sid(2, CSV_MERCILESS), "U_TERMINATOR_SQUAD_A", {"window_id": w, "unit_id": "U_TERMINATOR_SQUAD_A"}).can_use)
	_stage_fixture(ACTIVE)
	mv = _sid(1, CSV_MERCILESS)
	sf = _sid(1, CSV_STORM)
	pb = _sid(1, CSV_POINT_BLANK)
	phase = _phase(PHASE_SHOOTING)
	# Real hook: SELECT_SHOOTER.
	var r = phase.execute_action({"type": "SELECT_SHOOTER", "actor_unit_id": "U_HELLBLASTER_SQUAD_A", "player": 1})
	var pend: Dictionary = phase.get_pending_stratagem_window()
	_check("SELECT_SHOOTER Hellblasters opens unit_selected_to_shoot for P1", str(pend.get("window_id", "")) == w and int(pend.get("player", 0)) == 1, "%s / %s" % [str(r.get("error", r.get("errors", ""))), str(pend.get("window_id", ""))])
	if not phase.has_pending_stratagem_window():
		phase.open_stratagem_window(1, w, {"phase": "shooting", "unit_id": "U_HELLBLASTER_SQUAD_A"}, "")
	GS.state.factions["1"]["sw11e_doctrine"] = "devastator"
	var cp0 := _cp(1)
	var use := _use(phase, 1, w, sf, "U_HELLBLASTER_SQUAD_A")
	_check("USE STORM OF FIRE succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	var hbu := _unit("U_HELLBLASTER_SQUAD_A")
	var m := _mods(hbu, _unit("U_FLASH_GITZ_A"), false)
	_check("ranged [IGNORES COVER] + devastator doctrine +1 AP", bool(m.get("ignores_cover", false)) and int(m.get("ap", 0)) == 1, str(m))
	_check("melee: neither", not bool(_mods(hbu, _unit("U_FLASH_GITZ_A"), true).get("ignores_cover", false)) and int(_mods(hbu, _unit("U_FLASH_GITZ_A"), true).get("ap", 0)) == 0)
	GS.state.factions["1"]["sw11e_doctrine"] = ""
	_check("no devastator doctrine: [IGNORES COVER] only", int(_mods(hbu, _unit("U_FLASH_GITZ_A"), false).get("ap", 0)) == 0)
	_decline_pending(phase)
	PM.transition_to_phase(PHASE_CHARGE)
	_check("expiry: sm11e_storm_of_fire survives the Shooting phase's effect_* wipe until the expiry, then clears", not _flags("U_HELLBLASTER_SQUAD_A").has("sm11e_storm_of_fire"))
	# MERCILESS VETERANS.
	_stage_fixture(ACTIVE)
	mv = _sid(1, CSV_MERCILESS)
	pb = _sid(1, CSV_POINT_BLANK)
	phase = _phase(PHASE_SHOOTING)
	var r2 = SM.use_stratagem(1, mv, "U_TERMINATOR_SQUAD_A", {"window_id": w, "unit_id": "U_TERMINATOR_SQUAD_A"})
	_check("MERCILESS VETERANS succeeds", r2.get("success", false), str(r2.get("error", "")))
	var tsu := _unit("U_TERMINATOR_SQUAD_A")
	m = _mods(tsu, _unit("U_BOYZ_B"), false)
	_check("ranged [LETHAL HITS] + [SUSTAINED HITS 1]", bool(m.get("lethal", false)) and int(m.get("sustained", 0)) == 1, str(m))
	_check("not melee", not bool(_mods(tsu, _unit("U_BOYZ_B"), true).get("lethal", false)))
	# POINT-BLANK BRUTALITY: [CLOSE-QUARTERS] grant on the engaged Intercessors.
	var CQ = load("res://scripts/rules/shootingtypes/CloseQuartersShooting.gd").new()
	var bolt_rifle: Dictionary = {}
	var blast_w: Dictionary = {}
	for wp in _unit("U_INTERCESSOR_SQUAD_A").meta.weapons:
		if str(wp.get("name", "")).begins_with("Bolt Rifle") and bolt_rifle.is_empty():
			bolt_rifle = wp
		if "blast" in str(wp.get("special_rules", "")).to_lower() and blast_w.is_empty():
			blast_w = wp
	var iu := _unit("U_INTERCESSOR_SQUAD_A")
	_check("before: the bolt rifle is not allowed in close-quarters shooting", not CQ.weapon_allowed(bolt_rifle, iu, GS.state).allowed)
	r2 = SM.use_stratagem(1, pb, "U_INTERCESSOR_SQUAD_A", {"window_id": w, "unit_id": "U_INTERCESSOR_SQUAD_A"})
	_check("POINT-BLANK BRUTALITY succeeds", r2.get("success", false), str(r2.get("error", "")))
	_check("after: the bolt rifle has [CLOSE-QUARTERS] (allowed)", CQ.weapon_allowed(bolt_rifle, iu, GS.state).allowed)
	if not blast_w.is_empty():
		_check("a [BLAST] weapon is excluded", not CQ.weapon_allowed(blast_w, iu, GS.state).allowed, str(blast_w.get("name", "")))
	_check("close-quarters shooting eligible", bool(CQ.eligible("U_INTERCESSOR_SQUAD_A", GS.state).get("eligible", false)))
	m = _mods(iu, _unit("U_GRETCHIN_C"), false, bolt_rifle)
	_check("non-[BLAST] ranged attacks: [IGNORES COVER]", bool(m.get("ignores_cover", false)), str(m))
	if not blast_w.is_empty():
		_check("[BLAST] attacks: no ignores cover", not bool(_mods(iu, _unit("U_GRETCHIN_C"), false, blast_w).get("ignores_cover", false)))
	SM.on_phase_end(PHASE_SHOOTING)
	_check("expiry: sm11e_point_blank cleared", not _flags("U_INTERCESSOR_SQUAD_A").has("sm11e_point_blank") and not CQ.weapon_allowed(bolt_rifle, iu, GS.state).allowed)
	var not_engaged = SM.can_use_stratagem(1, pb, "U_HELLBLASTER_SQUAD_A", {"window_id": w, "unit_id": "U_HELLBLASTER_SQUAD_A"})
	_check("POINT-BLANK refused on an unengaged TACTICUS unit", not not_engaged.can_use, str(not_engaged))
	# Ranged A/B MERCILESS: lethal + sustained.
	var gun := {"name": "Test Gun", "type": "Ranged", "range": "24", "attacks": "4", "ballistic_skill": "3", "strength": "4", "ap": "0", "damage": "1", "special_rules": ""}
	var off := 0
	var on := 0
	for sd in range(9400, 9425):
		for pair in [[{}, false], [{"sm11e_merciless": true}, true]]:
			var bd := _board(pair[0], gun, 3, ["VEHICLE"], {}, 7, 8)
			bd.meta.phase = PHASE_SHOOTING
			RE.set_test_seed(sd)
			var res = RE.resolve_shoot({"type": "SHOOT", "actor_unit_id": "U_ATK", "payload": {"assignments": [{"weapon_id": "Test Gun", "target_unit_id": "U_TGT", "model_ids": ["ma0", "ma1", "ma2"]}]}}, bd, RE.RNGService.new())
			if pair[1]:
				on += _wounds_lost(res, bd)
			else:
				off += _wounds_lost(res, bd)
	_check("A/B MERCILESS VETERANS ranged: more wounds on T8 (%d -> %d)" % [off, on], on > off)


# ---------------------------------------------------------------------------
func _section_defensive() -> void:
	print("\n-- E. TACTICAL DREADNOUGHT FORTITUDE / ARMOUR OF CONTEMPT / DUTY IN DEATH --")
	_stage_fixture(REACTIVE)
	var tdf := _sid(2, CSV_TDF)
	var aoc := _sid(2, CSV_AOC_AB)
	var aoc_db := _sid(2, CSV_AOC_DB)
	var aoc_tb := _sid(2, CSV_AOC_TB)
	var dd := _sid(2, CSV_DUTY)
	var phase = _phase(PHASE_FIGHT)
	var wf := "enemy_targets_unit_fight"
	var ctx := {"phase": "fight", "attacker_unit_id": "U_BOYZ_B", "target_unit_ids": ["U_TERMINATOR_SQUAD_A"]}
	var o := _offers(2, wf, ctx)
	_check("Boyz target the Terminator Squad: TDF, the three ARMOUR OF CONTEMPT, DUTY IN DEATH offered", tdf in _offer_ids(o) and aoc in _offer_ids(o) and aoc_db in _offer_ids(o) and aoc_tb in _offer_ids(o) and dd in _offer_ids(o), str(_offer_ids(o)))
	var o2 := _offers(2, wf, {"phase": "fight", "attacker_unit_id": "U_NOBZ_A", "target_unit_ids": ["U_HEAVY_INTERCESSOR_SQUAD_A"]})
	_check("Heavy Intercessors targeted: ARMOUR OF CONTEMPT yes, TDF no (not TERMINATOR)", aoc in _offer_ids(o2) and not tdf in _offer_ids(o2), str(_offer_ids(o2)))
	_check("only the targeted unit is offered", _offer_targets(o, aoc) == ["U_TERMINATOR_SQUAD_A"], str(_offer_targets(o, aoc)))
	var cp0 := _cp(2)
	var r = SM.use_stratagem(2, tdf, "U_TERMINATOR_SQUAD_A", ctx.merged({"window_id": wf}))
	_check("USE TACTICAL DREADNOUGHT FORTITUDE succeeds, CP -2", r.get("success", false) and _cp(2) == cp0 - 2, str(r.get("error", "")))
	_check("-1 D on attacks that target the unit", int(EffectPrimitivesData.get_effect_minus_damage(_unit("U_TERMINATOR_SQUAD_A"))) == 1)
	_check("15.01: a second stratagem on the same unit this phase is refused (ARMOUR OF CONTEMPT)", not SM.can_use_stratagem(2, aoc, "U_TERMINATOR_SQUAD_A", ctx.merged({"window_id": wf})).can_use)
	_reset_usage()
	cp0 = _cp(2)
	r = SM.use_stratagem(2, aoc, "U_TERMINATOR_SQUAD_A", ctx.merged({"window_id": wf}))
	_check("USE ARMOUR OF CONTEMPT (Assault Brethren) succeeds, CP -1 (next phase / usage reset)", r.get("success", false) and _cp(2) == cp0 - 1, str(r.get("error", "")))
	_check("-1 AP on attacks that target the unit", int(EffectPrimitivesData.get_effect_worsen_ap(_unit("U_TERMINATOR_SQUAD_A"))) == 1)
	_check("another unit unaffected", int(EffectPrimitivesData.get_effect_minus_damage(_unit("U_HEAVY_INTERCESSOR_SQUAD_A"))) == 0 and int(EffectPrimitivesData.get_effect_worsen_ap(_unit("U_HEAVY_INTERCESSOR_SQUAD_A"))) == 0)
	# Another enemy unit attacking does not end them; the Boyz having attacked does.
	B.on_unit_has_attacked("U_NOBZ_A")
	_check("another attacker finishing does not end them", _flags("U_TERMINATOR_SQUAD_A").has("sm11e_tdf_fortitude") and _flags("U_TERMINATOR_SQUAD_A").has("sm11e_aoc"))
	B.on_unit_has_attacked("U_BOYZ_B")
	_check("both end once the Boyz have attacked", not _flags("U_TERMINATOR_SQUAD_A").has("sm11e_tdf_fortitude") and not _flags("U_TERMINATOR_SQUAD_A").has("sm11e_aoc"))
	# A/B: -1 D and -1 AP (melee, same seeds).
	var wpn := _melee_weapon("3", "5", "2", "6", "-2")
	var ab := _ab_melee(_board({}, wpn, 3, ["INFANTRY"], {}, 3, 4, 3), _board({}, wpn, 3, ["INFANTRY"], {"sm11e_tdf_fortitude": {"attacker_ids": ["U_ATK"]}}, 3, 4, 3), range(9500, 9530))
	_check("A/B TDF: fewer wounds lost (%d -> %d)" % [ab[0], ab[1]], ab[1] < ab[0], str(ab))
	ab = _ab_melee(_board({}, wpn, 3, ["INFANTRY"], {}, 3, 4, 3), _board({}, wpn, 3, ["INFANTRY"], {"sm11e_aoc": {"attacker_ids": ["U_ATK"]}}, 3, 4, 3), range(9600, 9630))
	_check("A/B ARMOUR OF CONTEMPT: fewer wounds lost (%d -> %d)" % [ab[0], ab[1]], ab[1] < ab[0], str(ab))
	# Shooting window: only in the opponent's Shooting phase.
	_reset_usage()
	var ws := "enemy_targets_unit_shooting"
	var sctx := {"phase": "shooting", "attacker_unit_id": "U_FLASH_GITZ_A", "target_unit_ids": ["U_TERMINATOR_SQUAD_A"], "window_id": ws}
	_check("ARMOUR OF CONTEMPT usable in the opponent's Shooting phase", SM.can_use_stratagem(2, aoc_db, "U_TERMINATOR_SQUAD_A", sctx).can_use, str(SM.can_use_stratagem(2, aoc_db, "U_TERMINATOR_SQUAD_A", sctx)))
	_check("DUTY IN DEATH never in the Shooting phase", not SM.can_use_stratagem(2, dd, "U_TERMINATOR_SQUAD_A", sctx).can_use)
	_stage_fixture(ACTIVE)
	_phase(PHASE_SHOOTING)
	_check("TDF refused in your own Shooting phase", not SM.can_use_stratagem(1, _sid(1, CSV_TDF), "U_TERMINATOR_SQUAD_A", {"window_id": ws, "target_unit_ids": ["U_TERMINATOR_SQUAD_A"], "attacker_unit_id": "U_FLASH_GITZ_A"}).can_use)
	_phase(PHASE_FIGHT)
	_check("ARMOUR OF CONTEMPT allowed in YOUR Fight phase", SM.can_use_stratagem(1, _sid(1, CSV_AOC_TB), "U_TERMINATOR_SQUAD_A", {"window_id": wf, "target_unit_ids": ["U_TERMINATOR_SQUAD_A"], "attacker_unit_id": "U_BOYZ_B"}).can_use)
	# DUTY IN DEATH: Fight On Death through FightPhase's intercept.
	_stage_fixture(REACTIVE)
	dd = _sid(2, CSV_DUTY)
	phase = _phase(PHASE_FIGHT)
	r = SM.use_stratagem(2, dd, "U_TERMINATOR_SQUAD_A", ctx.merged({"window_id": wf}))
	_check("USE DUTY IN DEATH succeeds", r.get("success", false), str(r.get("error", "")))
	_check("Fight On Death mode written", str(_flags("U_TERMINATOR_SQUAD_A").get("ork11e_fod_mode", "")) == "sm11e_duty_in_death")
	_check("4+, no modifier without the assault doctrine", B.fod_roll("U_TERMINATOR_SQUAD_A", 0) == {"mod": 0, "note": "", "pass": 4})
	GS.state.factions["2"]["sw11e_doctrine"] = "assault"
	_check("+1 with the assault doctrine", int(B.fod_roll("U_TERMINATOR_SQUAD_A", 0).get("mod", 0)) == 1)
	var kept := 0
	var rolled := 0
	for sd in range(9700, 9712):
		RE.set_test_seed(sd)
		phase._ork11e_fod_rolled = {}
		_flags("U_TERMINATOR_SQUAD_A").erase("ork11e_fod_pending")
		var ch: Array = [{"op": "set", "path": "units.U_TERMINATOR_SQUAD_A.models.1.alive", "value": false}]
		phase._ork11e_fod_intercept(ch)
		rolled += 1
		if bool(ch[0].get("value", false)):
			kept += 1
	print("    DUTY IN DEATH: %d of %d destroyed models kept (4+, +1 assault)" % [kept, rolled])
	_check("the intercept rolls and keeps some models (3+ effective with +1)", kept > 0 and kept < rolled + 1)
	GS.state.factions["2"]["sw11e_doctrine"] = ""
	phase._ork11e_selected_to_fight["U_TERMINATOR_SQUAD_A"] = true
	var sel_v = Dispatcher.validate(SM.get_stratagem(dd), 2, "U_TERMINATOR_SQUAD_A", ctx.merged({"window_id": wf}))
	_check("DUTY IN DEATH refused on a unit already selected to fight", not sel_v.ok and "selected to fight" in str(sel_v.reason), str(sel_v))
	phase._ork11e_selected_to_fight.erase("U_TERMINATOR_SQUAD_A")
	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry: the Fight On Death mode is cleared", not _flags("U_TERMINATOR_SQUAD_A").has("ork11e_fod_mode"))


# ---------------------------------------------------------------------------
func _section_post_shot() -> void:
	print("\n-- F. PURGATION PUSH / SUPPRESSION VOLLEYS / DOMINATION FIRE (unit_has_shot) / HAIL OF VENGEANCE (enemy_has_shot) --")
	_stage_fixture(ACTIVE)
	var pp := _sid(1, CSV_PUSH)
	var sv := _sid(1, CSV_SUPPRESSION)
	var df := _sid(1, CSV_DOMINATION)
	var w := "unit_has_shot"
	var phase = _phase(PHASE_SHOOTING)
	var base := {"phase": "shooting", "unit_id": "U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A", "hit_unit_ids": ["U_FLASH_GITZ_A"]}
	var o := _offers(1, w, base)
	_check("Eradicators HB (GRAVIS, unengaged, a few inches short of obj_nml_2): PURGATION PUSH, SUPPRESSION VOLLEYS, DOMINATION FIRE offered", pp in _offer_ids(o) and sv in _offer_ids(o) and df in _offer_ids(o), str(_offer_ids(o)))
	var sv_e := _offer_entry(o, sv, "U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A")
	_check("SUPPRESSION VOLLEYS: a secondary pick among the units hit", sv_e.get("secondary", {}).get("options", []).map(func(x): return str(x.id)) == ["U_FLASH_GITZ_A"], str(sv_e))
	_check("nothing hit: SUPPRESSION / DOMINATION not offered", not sv in _offer_ids(_offers(1, w, base.merged({"hit_unit_ids": []}, true))))
	_check("Hellblasters (not GRAVIS): PURGATION PUSH / SUPPRESSION not; DOMINATION yes", not pp in _offer_ids(_offers(1, w, {"unit_id": "U_HELLBLASTER_SQUAD_A", "hit_unit_ids": ["U_FLASH_GITZ_A"]})) and df in _offer_ids(_offers(1, w, {"unit_id": "U_HELLBLASTER_SQUAD_A", "hit_unit_ids": ["U_FLASH_GITZ_A"]})))
	_check("PURGATION PUSH not on an engaged GRAVIS unit", not SM.can_use_stratagem(1, pp, "U_HEAVY_INTERCESSOR_SQUAD_A", {"window_id": w, "unit_id": "U_HEAVY_INTERCESSOR_SQUAD_A", "hit_unit_ids": ["U_NOBZ_A"]}).can_use)
	# Real hook: the Eradicators HB (flamestorm gauntlets, 12") shoot the Kommandos,
	# moved (setup) to ~8" in front of them -> unit_has_shot for P1.
	_translate("U_FLASH_GITZ_A", 0, 16)
	RE.set_test_seed(31)
	var res = _shoot(phase, "U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A", "U_FLASH_GITZ_A")
	_check("Eradicators HB SHOOT at the Flash Gitz succeeds", res.get("success", false), str(res.get("error", res.get("errors", ""))))
	_decline_until(phase, 1, w)
	var pend: Dictionary = phase.get_pending_stratagem_window()
	_check("unit_has_shot pending for P1 with the Flash Gitz hit", str(pend.get("window_id", "")) == w and "U_FLASH_GITZ_A" in pend.get("ctx", {}).get("hit_unit_ids", []), str(pend.get("ctx", {})))
	var cp0 := _cp(1)
	var in0: bool = RM.group_within_objective_range(GS.state, "U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A")
	_check("Eradicators HB not within range of an objective before", not in0)
	var use := _use(phase, 1, w, pp, "U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A")
	_check("USE PURGATION PUSH succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	var fu: Dictionary = phase._ork11e_followup
	_check("normal-move follow-up: up to 5\", must end within range of an objective", not fu.is_empty() and fu.kind == "normal" and float(fu.max_inches) == 5.0 and str(fu.end_condition) == "within_objective_range", str(fu))
	var auto = phase.execute_action({"type": "ORK11E_REACTIVE_MOVE_AUTO", "player": 1})
	var conf = phase.execute_action({"type": "ORK11E_REACTIVE_MOVE_CONFIRM", "player": 1})
	_check("auto move + confirm succeed", auto.get("success", false) and conf.get("success", false), "%s / %s" % [str(auto.get("error", "")), str(conf.get("error", ""))])
	_check("the Eradicators HB end within range of obj_nml_2", RM.group_within_objective_range(GS.state, "U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A"))
	_check("not eligible to declare a charge this turn (cannot_charge)", bool(_flags("U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A").get("cannot_charge", false)))
	_check("not eligible to embark this turn", B.embark_blocked(_unit("U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A")))
	GS.state.meta["active_player"] = 2
	_check("the embark block ends with the turn", not B.embark_blocked(_unit("U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A")))
	GS.state.meta["active_player"] = 1
	# SUPPRESSION VOLLEYS: -1 battle-shock roll on the unit hit.
	_reset_usage()
	r_sv(sv)
	# DOMINATION FIRE: suppressed until the start of your next turn.
	_reset_usage()
	var dctx := {"window_id": w, "unit_id": "U_HELLBLASTER_SQUAD_A", "hit_unit_ids": ["U_FLASH_GITZ_A", "U_KOMMANDOS_A"], "secondary_id": "U_KOMMANDOS_A"}
	var bad = SM.can_use_stratagem(1, df, "U_HELLBLASTER_SQUAD_A", dctx.merged({"secondary_id": "U_BOYZ_B"}, true))
	_check("DOMINATION FIRE: an enemy unit not hit is refused", not bad.can_use, str(bad))
	var r = SM.use_stratagem(1, df, "U_HELLBLASTER_SQUAD_A", dctx)
	_check("USE DOMINATION FIRE on the Kommandos succeeds", r.get("success", false), str(r.get("error", "")))
	var ku := _unit("U_KOMMANDOS_A")
	_check("the Kommandos' attacks have -1 to hit (aggregator hit_minus)", bool(_mods(ku, _unit("U_HELLBLASTER_SQUAD_A"), false).get("hit_minus", false)) and bool(_mods(ku, _unit("U_HELLBLASTER_SQUAD_A"), true).get("hit_minus", false)))
	_check("the Flash Gitz (not picked) are not suppressed", not bool(_mods(_unit("U_FLASH_GITZ_A"), _unit("U_HELLBLASTER_SQUAD_A"), false).get("hit_minus", false)))
	SM.on_phase_end(PHASE_SHOOTING)
	_check("the end of the Shooting phase does not end the suppression", B.GroupAction.suppressed_active(ku))
	GS.state.meta["active_player"] = 2
	_check("still suppressed in the opponent's turn (same round)", B.GroupAction.suppressed_active(ku))
	GS.state.meta["battle_round"] = int(GS.state.meta.battle_round) + 1
	GS.state.meta["active_player"] = 1
	_check("ends at the start of P1's next turn", not B.GroupAction.suppressed_active(ku))
	GS.state.meta["battle_round"] = int(GS.state.meta.battle_round) - 1
	# HAIL OF VENGEANCE (reactive): the Flash Gitz shoot the Hellblasters.
	_stage_fixture(REACTIVE)
	var hv := _sid(2, CSV_HAIL)
	phase = _phase(PHASE_SHOOTING)
	var hctx := {"phase": "shooting", "attacker_unit_id": "U_FLASH_GITZ_A", "hit_unit_ids": ["U_HELLBLASTER_SQUAD_A"], "destroyed_unit_ids": ["U_HELLBLASTER_SQUAD_A"]}
	_check("HAIL OF VENGEANCE offered on the Hellblasters that lost a model", "U_HELLBLASTER_SQUAD_A" in _offer_targets(_offers(2, "enemy_has_shot", hctx), hv))
	_check("…not when no model was destroyed", not hv in _offer_ids(_offers(2, "enemy_has_shot", hctx.merged({"destroyed_unit_ids": []}, true))))
	_check("…not on an engaged unit (normal shooting)", not SM.can_use_stratagem(2, hv, "U_TERMINATOR_SQUAD_A", {"window_id": "enemy_has_shot", "attacker_unit_id": "U_BOYZ_B", "destroyed_unit_ids": ["U_TERMINATOR_SQUAD_A"]}).can_use)
	# Real hook: make the Hellblasters fragile so a model dies.
	# Setup: one fragile Hellblaster (1 wound left), the others sturdy, so the
	# volley destroys a model but not the unit.
	var hms: Array = _unit("U_HELLBLASTER_SQUAD_A").models
	for i in range(hms.size()):
		hms[i]["current_wounds"] = 1 if i == 0 else 12
		if i > 0:
			hms[i]["wounds"] = 12
	_translate("U_FLASH_GITZ_A", 0, 3)
	var killed := false
	for sd in [41, 42, 43, 44, 45, 46]:
		var alive0 := _alive("U_HELLBLASTER_SQUAD_A")
		RE.set_test_seed(sd)
		res = _shoot(phase, "U_FLASH_GITZ_A", "U_HELLBLASTER_SQUAD_A")
		_decline_until(phase, 2, "enemy_has_shot")
		if _alive("U_HELLBLASTER_SQUAD_A") < alive0 and _alive("U_HELLBLASTER_SQUAD_A") > 0:
			killed = true
			break
		_decline_pending(phase)
		phase.units_that_shot.erase("U_FLASH_GITZ_A")
	_check("the Flash Gitz destroyed a Hellblaster (setup)", killed)
	pend = phase.get_pending_stratagem_window()
	_check("enemy_has_shot pending for P2 with destroyed_unit_ids = the Hellblasters", str(pend.get("window_id", "")) == "enemy_has_shot" and "U_HELLBLASTER_SQUAD_A" in pend.get("ctx", {}).get("destroyed_unit_ids", []), str(pend.get("ctx", {})))
	_check("HAIL OF VENGEANCE offered there", hv in _offer_ids(pend.get("offers", [])), str(_offer_ids(pend.get("offers", []))))
	cp0 = _cp(2)
	var fg_w0 := _wounds("U_FLASH_GITZ_A")
	use = _use(phase, 2, "enemy_has_shot", hv, "U_HELLBLASTER_SQUAD_A")
	_check("USE HAIL OF VENGEANCE succeeds, CP -2", use.get("success", false) and _cp(2) == cp0 - 2, str(use.get("error", "")))
	_check("the Hellblasters shot back at the Flash Gitz (wounds %d -> %d)" % [fg_w0, _wounds("U_FLASH_GITZ_A")], _wounds("U_FLASH_GITZ_A") < fg_w0 or _log_count("HAIL OF VENGEANCE: ") >= 1)
	_check("Game Log names HAIL OF VENGEANCE", _log_count("HAIL OF VENGEANCE") >= 1)
	_decline_pending(phase)


func r_sv(sv: String) -> void:
	var w := "unit_has_shot"
	var fam = root.get_node("FactionAbilityManager")
	var gitz := _unit("U_FLASH_GITZ_A")
	_flags("U_FLASH_GITZ_A").erase("battle_shocked")
	var cp0 := _cp(1)
	RE.set_test_seed(77)
	var r = SM.use_stratagem(1, sv, "U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A", {"window_id": w, "unit_id": "U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A", "hit_unit_ids": ["U_FLASH_GITZ_A"], "secondary_id": "U_FLASH_GITZ_A"})
	_check("USE SUPPRESSION VOLLEYS succeeds, CP -1", r.get("success", false) and _cp(1) == cp0 - 1, str(r.get("error", "")))
	_check("Game Log: a battle-shock roll at -1", _log_count("SUPPRESSION VOLLEYS: ") >= 1 and _log_count("battle-shock roll") >= 1)
	# -1 applied: over seeds the failure rate is higher than an unmodified test.
	var fails_mod := 0
	var fails_plain := 0
	for sd in range(500, 560):
		RE.set_test_seed(sd)
		gitz.flags.erase("battle_shocked")
		if not bool(fam.force_battle_shock_test("U_FLASH_GITZ_A", -1, "t").get("passed", true)):
			fails_mod += 1
		RE.set_test_seed(sd)
		gitz.flags.erase("battle_shocked")
		if not bool(fam.force_battle_shock_test("U_FLASH_GITZ_A", 0, "t").get("passed", true)):
			fails_plain += 1
	gitz.flags.erase("battle_shocked")
	_check("the -1 makes battle-shock more likely (%d vs %d fails / 60)" % [fails_mod, fails_plain], fails_mod >= fails_plain)


# ---------------------------------------------------------------------------
func _section_movement() -> void:
	print("\n-- G. STAND UNYIELDING / UPSTOPPABLE ADVANCE / MASTERFUL TACTICS --")
	_stage_fixture(ACTIVE)
	var su := _sid(1, CSV_STAND)
	var ua := _sid(1, CSV_UPSTOPPABLE)
	var phase = _phase(PHASE_MOVEMENT)
	if MM.has_method("check_all_objectives"):
		MM.check_all_objectives()
	print("    objective control: %s" % str(MM.objective_control_state))
	var o := _offers(1, "movement_phase_end", {"phase": "movement"})
	var t := _offer_targets(o, su)
	_check("STAND UNYIELDING offered on the Eradicators (GRAVIS, on obj_home_2)", "U_ERADICATOR_SQUAD_WITH_MELTA_RIFLES_A" in t, str(t))
	_check("…not on the Assault Intercessors (not GRAVIS)", not "U_ASSAULT_INTERCESSOR_SQUAD_A" in t)
	var e := _offer_entry(o, su, "U_ERADICATOR_SQUAD_WITH_MELTA_RIFLES_A")
	var opts: Array = e.get("secondary", {}).get("options", []).map(func(x): return str(x.id))
	_check("secondary objective pick = obj_home_2", opts == ["obj_home_2"], str(opts))
	var cp0 := _cp(1)
	var r = SM.use_stratagem(1, su, "U_ERADICATOR_SQUAD_WITH_MELTA_RIFLES_A", {"window_id": "movement_phase_end", "secondary_id": "obj_home_2"})
	_check("USE STAND UNYIELDING succeeds, CP -1", r.get("success", false) and _cp(1) == cp0 - 1, str(r.get("error", "")))
	_check("obj_home_2 is secured by P1", Common.objective_secured_by("obj_home_2") == 1)
	_stage_fixture(REACTIVE)
	_check("STAND UNYIELDING refused in the opponent's Movement phase", not SM.can_use_stratagem(2, _sid(2, CSV_STAND), "U_ERADICATOR_SQUAD_WITH_MELTA_RIFLES_A", {"window_id": "movement_phase_end", "secondary_id": "obj_home_2"}).can_use)
	_stage_fixture(ACTIVE)
	ua = _sid(1, CSV_UPSTOPPABLE)
	phase = _phase(PHASE_MOVEMENT)
	# UPSTOPPABLE ADVANCE — real BEGIN_NORMAL_MOVE hook.
	_reset_usage()
	var r2 = phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_BALLISTUS_DREADNOUGHT_A", "player": 1})
	var pend: Dictionary = phase.get_pending_stratagem_window()
	_check("BEGIN_NORMAL_MOVE Ballistus opens unit_selected_to_move with UPSTOPPABLE ADVANCE", str(pend.get("window_id", "")) == "unit_selected_to_move" and ua in _offer_ids(pend.get("offers", [])), "%s / %s" % [str(r2.get("error", r2.get("errors", ""))), str(pend.get("window_id", ""))])
	if not phase.has_pending_stratagem_window():
		phase.open_stratagem_window(1, "unit_selected_to_move", {"phase": "movement", "unit_id": "U_BALLISTUS_DREADNOUGHT_A", "move_type": "normal"}, "")
	cp0 = _cp(1)
	var use := _use(phase, 1, "unit_selected_to_move", ua, "U_BALLISTUS_DREADNOUGHT_A")
	_check("USE UPSTOPPABLE ADVANCE succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	_check("MOBILE grant ork11e_mobile", bool(_flags("U_BALLISTUS_DREADNOUGHT_A").get("ork11e_mobile", false)))
	_check("not on a non-DREADNOUGHT unit", not SM.can_use_stratagem(1, ua, "U_HELLBLASTER_SQUAD_A", {"window_id": "unit_selected_to_move", "unit_id": "U_HELLBLASTER_SQUAD_A"}).can_use)
	SM.on_phase_end(PHASE_MOVEMENT)
	_check("expiry: MOBILE removed at the end of the phase", not _flags("U_BALLISTUS_DREADNOUGHT_A").has("ork11e_mobile"))
	_phase(PHASE_CHARGE)
	_check("unit_declares_charge: offered on a DREADNOUGHT", ua in _offer_ids(_offers(1, "unit_declares_charge", {"phase": "charge", "unit_id": "U_BALLISTUS_DREADNOUGHT_A", "target_unit_ids": ["U_KOMMANDOS_A"]})))
	# MASTERFUL TACTICS (reactive): the Kommandos end a move within 8" of the Hellblasters.
	_stage_fixture(REACTIVE)
	var mt := _sid(2, CSV_MASTERFUL)
	phase = _phase(PHASE_MOVEMENT)
	_translate("U_KOMMANDOS_A", 12, 14)  # front ~ y 36: within 8" of the Hellblasters (front y 42)
	var d_k: float = Common.group_distance_inches("U_HELLBLASTER_SQUAD_A", "U_KOMMANDOS_A")
	print("    Kommandos - Hellblasters: %.2f\"" % d_k)
	var mctx := {"phase": "movement", "enemy_unit_id": "U_KOMMANDOS_A", "move_type": "normal"}
	var mo := _offers(2, "enemy_ended_move", mctx)
	_check("MASTERFUL TACTICS offered on the Hellblasters (within 8\")", "U_HELLBLASTER_SQUAD_A" in _offer_targets(mo, mt), "%.2f / %s" % [d_k, str(_offer_targets(mo, mt))])
	_check("…not on the engaged Terminator Squad", not "U_TERMINATOR_SQUAD_A" in _offer_targets(mo, mt))
	_check("…not on the Redemptor (not INFANTRY/MOUNTED)", not "U_REDEMPTOR_DREADNOUGHT_A" in _offer_targets(mo, mt))
	_check("…not on a unit more than 8\" away (Eradicators)", not "U_ERADICATOR_SQUAD_WITH_MELTA_RIFLES_A" in _offer_targets(mo, mt))
	if not phase.has_pending_stratagem_window():
		phase.open_stratagem_window(2, "enemy_ended_move", mctx, "")
	GS.state.factions["2"]["sw11e_doctrine"] = "tactical"
	cp0 = _cp(2)
	use = _use(phase, 2, "enemy_ended_move", mt, "U_HELLBLASTER_SQUAD_A")
	_check("USE MASTERFUL TACTICS succeeds, CP -1", use.get("success", false) and _cp(2) == cp0 - 1, str(use.get("error", "")))
	var rm: Dictionary = phase._ork11e_reactive_move
	_check("tactical doctrine: a normal move of up to 6\" (no roll)", not rm.is_empty() and float(rm.get("max_inches", 0)) == 6.0, str(rm))
	GS.state.factions["2"]["sw11e_doctrine"] = ""
	_check("Game Log names MASTERFUL TACTICS", _log_count("MASTERFUL TACTICS") >= 1)


# ---------------------------------------------------------------------------
func _section_charge_fight_misc() -> void:
	print("\n-- H. ARMOURED IMPACT / ADAMANTINE TERROR / GUNSHIP EXTRACTION --")
	_stage_fixture(ACTIVE)
	var ai_ := _sid(1, CSV_IMPACT)
	var at := _sid(1, CSV_ADAMANTINE)
	var phase = _phase(PHASE_CHARGE)
	var o := _offers(1, "unit_ended_charge_move", {"phase": "charge", "unit_id": "U_HEAVY_INTERCESSOR_SQUAD_A"})
	_check("ARMOURED IMPACT offered on the Heavy Intercessors (GRAVIS, engaged with the Nobz)", "U_HEAVY_INTERCESSOR_SQUAD_A" in _offer_targets(o, ai_), str(_offer_ids(o)))
	var e := _offer_entry(o, ai_, "U_HEAVY_INTERCESSOR_SQUAD_A")
	_check("secondary pick: the Nobz", e.get("secondary", {}).get("options", []).map(func(x): return str(x.id)) == ["U_NOBZ_A"], str(e))
	_check("not on the Terminator Squad (not GRAVIS)", not ai_ in _offer_ids(_offers(1, "unit_ended_charge_move", {"phase": "charge", "unit_id": "U_TERMINATOR_SQUAD_A"})))
	var n0 := _wounds("U_NOBZ_A")
	var cp0 := _cp(1)
	RE.set_test_seed(55)
	var r = SM.use_stratagem(1, ai_, "U_HEAVY_INTERCESSOR_SQUAD_A", {"window_id": "unit_ended_charge_move", "unit_id": "U_HEAVY_INTERCESSOR_SQUAD_A", "secondary_id": "U_NOBZ_A"})
	_check("USE ARMOURED IMPACT succeeds, CP -1", r.get("success", false) and _cp(1) == cp0 - 1, str(r.get("error", "")))
	print("    Nobz wounds %d -> %d" % [n0, _wounds("U_NOBZ_A")])
	_check("mortal wounds dealt to the Nobz (one D6 per engaged model, 3+)", _wounds("U_NOBZ_A") < n0 and _log_count("ARMOURED IMPACT") >= 1)
	# ADAMANTINE TERROR — fight_phase_start (either player's).
	phase = _phase(PHASE_FIGHT)
	o = _offers(1, "fight_phase_start", {"phase": "fight"})
	_check("ADAMANTINE TERROR offered on the Redemptor (engaged with the Meganobz)", "U_REDEMPTOR_DREADNOUGHT_A" in _offer_targets(o, at), str(_offer_targets(o, at)))
	_check("…not on the unengaged Ballistus", not "U_BALLISTUS_DREADNOUGHT_A" in _offer_targets(o, at))
	_flags("U_MEGANOBZ_A").erase("battle_shocked")
	r = SM.use_stratagem(1, at, "U_REDEMPTOR_DREADNOUGHT_A", {"window_id": "fight_phase_start"})
	_check("USE ADAMANTINE TERROR succeeds", r.get("success", false), str(r.get("error", "")))
	_check("the Meganobz made a battle-shock roll at -1 (Game Log)", _log_count("ADAMANTINE TERROR: ") >= 1)
	_stage_fixture(REACTIVE)
	_phase(PHASE_FIGHT)
	_check("ADAMANTINE TERROR also in the opponent's Fight phase", "U_REDEMPTOR_DREADNOUGHT_A" in _offer_targets(_offers(2, "fight_phase_start", {"phase": "fight"}), _sid(2, CSV_ADAMANTINE)))
	# GUNSHIP EXTRACTION — end of the opponent's Fight phase.
	var ge := _sid(2, CSV_GUNSHIP)
	phase = _phase(PHASE_FIGHT)
	o = _offers(2, "fight_phase_end", {"phase": "fight"})
	var gt := _offer_targets(o, ge)
	_check("GUNSHIP EXTRACTION offered on the unengaged Terminator Assault Squad", "U_TERMINATOR_ASSAULT_SQUAD_A" in gt, str(gt))
	_check("…not on the engaged Terminator Squad", not "U_TERMINATOR_SQUAD_A" in gt)
	_check("…not on the Hellblasters (not TERMINATOR)", not "U_HELLBLASTER_SQUAD_A" in gt)
	if not phase.has_pending_stratagem_window():
		phase.open_stratagem_window(2, "fight_phase_end", {"phase": "fight"}, "")
	cp0 = _cp(2)
	var use := _use(phase, 2, "fight_phase_end", ge, "U_TERMINATOR_ASSAULT_SQUAD_A")
	_check("USE GUNSHIP EXTRACTION succeeds, CP -1", use.get("success", false) and _cp(2) == cp0 - 1, str(use.get("error", "")))
	_check("the unit is in strategic reserves", str(_unit("U_TERMINATOR_ASSAULT_SQUAD_A").get("reserve_type", "")) == "strategic_reserves" and _unit("U_TERMINATOR_ASSAULT_SQUAD_A").models[0].get("position", null) == null, str(_unit("U_TERMINATOR_ASSAULT_SQUAD_A").get("status", "")))
	_stage_fixture(ACTIVE)
	_phase(PHASE_FIGHT)
	_check("GUNSHIP EXTRACTION refused at the end of your own Fight phase", not SM.can_use_stratagem(1, _sid(1, CSV_GUNSHIP), "U_TERMINATOR_ASSAULT_SQUAD_A", {"window_id": "fight_phase_end"}).can_use)


# ---------------------------------------------------------------------------
func _section_ai() -> void:
	print("\n-- I. AI deciders --")
	var ai = root.get_node("AIPlayer")
	var AIDM = load("res://scripts/AIDecisionMaker.gd")
	_stage_fixture(ACTIVE)
	var phase = _phase(PHASE_COMMAND)
	ai.enabled = true
	ai.ai_players = {1: true, 2: false}
	var cp0 := _cp(1)
	var paused: bool = phase.open_stratagem_window(1, "command_phase_main", {"phase": "command"}, "")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_check("AI command_phase_main: no pause, nothing pending", not paused and not phase.has_pending_stratagem_window())
	_check("AI CP never negative", _cp(1) >= 0 and _cp(1) <= cp0)
	_phase(PHASE_FIGHT)
	var offers := _offers(1, "unit_selected_to_fight", {"phase": "fight", "unit_id": "U_REDEMPTOR_DREADNOUGHT_A"})
	var d: Dictionary = AIDM.decide_window_stratagem(1, "unit_selected_to_fight", offers, {"phase": "fight", "unit_id": "U_REDEMPTOR_DREADNOUGHT_A"})
	_check("AI unit_selected_to_fight (Redemptor engaged): uses a buff on it", bool(d.get("use", false)) and str(d.get("target_unit_id", "")) == "U_REDEMPTOR_DREADNOUGHT_A", str(d))
	if str(d.get("stratagem_id", "")) == _sid(1, CSV_MERCY):
		_check("…with a MERCY variant picked", str(d.get("context", {}).get("variant_id", "")) in ["lethal", "sustained"], str(d))
	var fs := _offers(1, "fight_phase_start", {"phase": "fight"})
	d = AIDM.decide_window_stratagem(1, "fight_phase_start", fs, {"phase": "fight"})
	_check("AI fight_phase_start decision well-formed (ADAMANTINE TERROR candidate)", d.has("use"), str(d))
	# Post-shot: AI P1 shooter answers its unit_has_shot window synchronously.
	_stage_fixture(ACTIVE)
	phase = _phase(PHASE_SHOOTING)
	_translate("U_FLASH_GITZ_A", 0, 16)
	ai.enabled = true
	ai.ai_players = {1: true, 2: false}
	RE.set_test_seed(61)
	var res = _shoot(phase, "U_ERADICATOR_SQUAD_WITH_HEAVY_BOLTERS_A", "U_FLASH_GITZ_A")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_decline_until(phase, 99)
	_check("AI shooter: SHOOT resolves, its own windows never pause", res.get("success", false) and phase._ork11e_followup.is_empty(), str(phase.get_pending_stratagem_window().get("window_id", "")))
	# enemy_has_shot: AI defender with HAIL OF VENGEANCE.
	_stage_fixture(REACTIVE)
	phase = _phase(PHASE_SHOOTING)
	var hctx := {"phase": "shooting", "attacker_unit_id": "U_FLASH_GITZ_A", "hit_unit_ids": ["U_HELLBLASTER_SQUAD_A"], "destroyed_unit_ids": ["U_HELLBLASTER_SQUAD_A"]}
	_translate("U_FLASH_GITZ_A", 0, 3)
	var ho := _offers(2, "enemy_has_shot", hctx)
	d = AIDM.decide_window_stratagem(2, "enemy_has_shot", ho, hctx)
	_check("AI HAIL OF VENGEANCE: shoots back when it can (Hellblasters vs Flash Gitz)", bool(d.get("use", false)) and str(d.get("stratagem_id", "")) == _sid(2, CSV_HAIL), str(d))
	# Defensive: AI ARMOUR OF CONTEMPT vs AP Nobz.
	var dctx := {"phase": "fight", "attacker_unit_id": "U_NOBZ_A", "target_unit_ids": ["U_HEAVY_INTERCESSOR_SQUAD_A"]}
	d = AIDM.decide_window_stratagem(2, "enemy_targets_unit_fight", _offers(2, "enemy_targets_unit_fight", dctx), dctx)
	_check("AI enemy_targets_unit_fight decision well-formed", d.has("use"), str(d))
	# Opponent Command phase window: AI P2 answers synchronously.
	phase = _phase(PHASE_COMMAND)
	ai.enabled = true
	ai.ai_players = {1: false, 2: true}
	paused = phase.open_stratagem_window(2, "command_phase_opponent", {"phase": "command"}, "")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_check("AI command_phase_opponent: no pause", not paused and not phase.has_pending_stratagem_window())
