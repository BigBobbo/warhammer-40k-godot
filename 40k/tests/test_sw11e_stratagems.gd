extends SceneTree

# Codex: Space Marines (11e) — SPACE WOLVES detachment stratagems (WP-S3,
# SWCodex11e.gd + SWCodexCombat / SWCodexMovement / SWCodexCommand).
# Fixtures (tests/helpers/gen_sw11e_s3_fixtures.gd):
#   sw11e_s3_active   P1 Space Wolves ACTIVE vs P2 Orks
#   sw11e_s3_reactive P1 Orks ACTIVE vs P2 Space Wolves
# The Space Wolves player gets all three detachments (Saga of the Great Wolf,
# Champions of Fenris, Saga of the Beastslayer) set in-test.
#
#   A. registry / data: 12 csv ids implemented, windows, pinned bit values,
#      non-Space Wolves armies refused
#   B. GRIMNAR'S COMMAND + BIRTH OF A SAGA  command_phase_main (real END_COMMAND
#      hook), variants, doctrine state API, CHARACTER keyword, re-offer, CP,
#      once per phase, expiry at the owner's next Command phase only
#   C. CHAMPION'S GUIDANCE / UNBRIDLED FEROCITY / FANGS OF THE PACK / EYE OF
#      THE PACK  unit_selected_to_fight (+ unit_selected_to_shoot), real
#      SELECT_FIGHTER hook, eligibility, A/B (same seeds), 15.01, expiry
#   D. HEROIC RESOLVE  enemy_targets_unit_fight / _shooting, -1 D A/B, ends when
#      that enemy unit has attacked
#   E. IMPETUOSITY / BATTLE INSTINCTS  enemy_has_shot (real SHOOT hook),
#      targeted (not only hit) units, surge / normal move follow-ups
#   F. FENRISIAN FEROCITY  unit_selected_to_move (real BEGIN_NORMAL_MOVE hook)
#      / unit_declares_charge, MOBILE grant, expiry
#   G. CO-ORDINATED STRIKE  fight_phase_end (opponent's Fight phase), edge 9",
#      strategic reserves follow-up
#   H. WOLF TOTEMS  S panel (any phase, either turn), FNP 5+ vs mortal wounds
#      only, A/B, expiry
#   I. AI deciders never stall (command, fight, enemy_has_shot)
#
# Usage: godot --headless --path 40k --script tests/test_sw11e_stratagems.gd

const ACTIVE := "sw11e_s3_active"
const REACTIVE := "sw11e_s3_reactive"
const PHASE_COMMAND := 6
const PHASE_MOVEMENT := 7
const PHASE_SHOOTING := 8
const PHASE_CHARGE := 9
const PHASE_FIGHT := 10
const PX := 40.0
const DETS := ["Saga of the Great Wolf", "Champions of Fenris", "Saga of the Beastslayer"]

const CSV_BIRTH := "birth-of-a-saga-champions-of-fenris"
const CSV_HEROIC := "heroic-resolve-champions-of-fenris"
const CSV_GUIDANCE := "champions-guidance-champions-of-fenris"
const CSV_UNBRIDLED := "unbridled-ferocity-saga-of-the-beastslayer"
const CSV_STRIKE := "co-ordinated-strike-saga-of-the-beastslayer"
const CSV_IMPET := "impetuosity-saga-of-the-beastslayer"
const CSV_INSTINCTS := "battle-instincts-saga-of-the-great-wolf"
const CSV_GRIMNAR := "grimnars-command-saga-of-the-great-wolf"
const CSV_FEROCITY := "fenrisian-ferocity-saga-of-the-great-wolf"
const CSV_FANGS := "fangs-of-the-pack-saga-of-the-great-wolf"
const CSV_TOTEMS := "wolf-totems-saga-of-the-great-wolf"
const CSV_EYE := "eye-of-the-pack-saga-of-the-great-wolf"

const EXPECTED_WINDOWS := {
	CSV_BIRTH: ["command_phase_main"],
	CSV_HEROIC: ["enemy_targets_unit_shooting", "enemy_targets_unit_fight"],
	CSV_GUIDANCE: ["unit_selected_to_fight"],
	CSV_UNBRIDLED: ["unit_selected_to_fight"],
	CSV_STRIKE: ["fight_phase_end"],
	CSV_IMPET: ["enemy_has_shot"],
	CSV_INSTINCTS: ["enemy_has_shot"],
	CSV_GRIMNAR: ["command_phase_main"],
	CSV_FEROCITY: ["unit_selected_to_move", "unit_declares_charge"],
	CSV_FANGS: ["unit_selected_to_fight"],
	CSV_TOTEMS: [],
	CSV_EYE: ["unit_selected_to_shoot", "unit_selected_to_fight"],
}

var passed := 0
var failed := 0
var SM = null
var GS = null
var PM = null
var RE = null
var Codex = null
var Common = null
var RM = null
var _sw := 1


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

func _stage_fixture(fixture: String) -> bool:
	var slm = root.get_node("SaveLoadManager")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slm.save_directory))
	for ext in [".w40ksave", ".meta"]:
		var src = "res://tests/saves/" + fixture + ext
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(slm.save_directory + fixture + ext))
	var ok = slm.load_game(fixture)
	GameConstants.edition = 11
	_sw = 1 if fixture == ACTIVE else 2
	GS.state.factions[str(_sw)]["detachment"] = DETS[0]
	GS.state.factions[str(_sw)]["detachments"] = DETS.duplicate()
	SM.load_faction_stratagems_for_player(_sw)
	_reset_usage()
	return ok


func _reset_usage(cp: int = 6) -> void:
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


func _phase(phase_id: int):
	_reset_usage()
	PM.transition_to_phase(PHASE_COMMAND)
	if phase_id != PHASE_COMMAND:
		PM.transition_to_phase(phase_id)
	var phase = PM.get_current_phase_instance()
	_no_phase_advance(phase)
	_decline_pending(phase)
	return phase


## Decline every pending window that is not `player`'s (the other seat's
## post-shot windows open first — 01.03.02 active player first).
func _decline_until(phase, player: int) -> void:
	var n := 0
	while phase.has_pending_stratagem_window() and int(phase.get_pending_stratagem_window().get("player", 0)) != player and n < 6:
		var w: Dictionary = phase.get_pending_stratagem_window()
		print("    declining %s for P%d" % [str(w.get("window_id", "")), int(w.get("player", 0))])
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(w.get("player", 0)), "window_id": str(w.get("window_id", ""))})
		n += 1


func _keywords(uid: String) -> Array:
	return _unit(uid).get("meta", {}).get("keywords", []).map(func(k): return str(k).to_upper())


func _translate(uid: String, dx_in: float, dy_in: float) -> void:
	for m in _unit(uid).get("models", []):
		var p = m.get("position", null)
		if p is Dictionary:
			m["position"] = {"x": float(p.x) + dx_in * PX, "y": float(p.y) + dy_in * PX}


func _block(result: Dictionary, ctx_name: String) -> Dictionary:
	for d in result.get("dice", []):
		if str(d.get("context", "")) == ctx_name:
			return d
	return {}


func _sum_successes(dice: Array, ctx: String) -> int:
	var n := 0
	for b in dice:
		if str(b.get("context", "")) == ctx:
			n += int(b.get("successes", 0))
	return n


func _log_count(fragment: String) -> int:
	var gel = root.get_node_or_null("GameEventLog")
	var n := 0
	if gel and "entries" in gel:
		for e in gel.entries:
			if fragment in str(e.get("text", "")):
				n += 1
	return n


func _melee_weapon(ws: String, s: String, d: String, a: String = "4", rules: String = "") -> Dictionary:
	return {"name": "Test Blade", "type": "Melee", "range": "Melee", "attacks": a, "weapon_skill": ws,
		"strength": s, "ap": "0", "damage": d, "special_rules": rules}


func _melee_board(att_flags: Dictionary, att_kw: Array, weapon: Dictionary, n_att: int, tgt_t: int, tgt_flags: Dictionary = {}, tgt_save: int = 7, tgt_wounds: int = 3) -> Dictionary:
	var atk: Array = []
	for i in range(n_att):
		atk.append({"id": "ma%d" % i, "position": {"x": 10.0, "y": 10.0 + i * 30}, "base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 3, "current_wounds": 3})
	var tgt: Array = []
	for i in range(4):
		tgt.append({"id": "mt%d" % i, "position": {"x": 30.0, "y": 10.0 + i * 30}, "base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": tgt_wounds, "current_wounds": tgt_wounds})
	return {"units": {
		"U_ATK": {"id": "U_ATK", "owner": 1,
			"meta": {"name": "Attackers", "keywords": att_kw, "stats": {"toughness": 4, "save": 6, "wounds": 3},
				"abilities": [], "weapons": [weapon]},
			"flags": att_flags, "models": atk},
		"U_TGT": {"id": "U_TGT", "owner": 2,
			"meta": {"name": "Targets", "keywords": ["INFANTRY"], "stats": {"toughness": tgt_t, "save": tgt_save, "wounds": tgt_wounds}, "abilities": []},
			"flags": tgt_flags, "models": tgt},
	}, "meta": {"phase": 10, "active_player": 1, "battle_round": 2}}


func _melee(board: Dictionary, seed_val: int) -> Dictionary:
	RE.set_test_seed(seed_val)
	var rng = RE.RNGService.new()
	return RE.resolve_melee_attacks({"type": "FIGHT", "actor_unit_id": "U_ATK",
		"payload": {"assignments": [{"attacker": "U_ATK", "target": "U_TGT", "weapon": "Test Blade"}]}}, board, rng)


## Wounds the target unit lost in a resolve result (its diffs).
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


## A/B over seeds: [hits_off, hits_on, wounds_off, wounds_on, lost_off, lost_on].
func _ab(board_off: Dictionary, board_on: Dictionary, seeds: Array) -> Array:
	var out := [0, 0, 0, 0, 0, 0]
	for sd in seeds:
		var a = _melee(board_off.duplicate(true), int(sd))
		var b = _melee(board_on.duplicate(true), int(sd))
		out[0] += int(_block(a, "hit_roll_melee").get("successes", 0))
		out[1] += int(_block(b, "hit_roll_melee").get("successes", 0))
		out[2] += int(_block(a, "wound_roll_melee").get("successes", 0))
		out[3] += int(_block(b, "wound_roll_melee").get("successes", 0))
		out[4] += _wounds_lost(a, board_off)
		out[5] += _wounds_lost(b, board_on)
	return out


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


# ---------------------------------------------------------------------------
func _run() -> void:
	SM = root.get_node("StratagemManager")
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	Codex = load("res://scripts/codex/space_wolves/SWCodex11e.gd")
	Common = load("res://scripts/codex/space_wolves/SWCommon.gd")
	RM = load("res://scripts/rules/ReactiveMove11e.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	GS.set_edition(11)
	root.get_node("SettingsService").set("auto_allocate_wounds", true)

	print("\n=== test_sw11e_stratagems ===\n")
	_check("fixture %s loads" % ACTIVE, _stage_fixture(ACTIVE))
	_section_registry()
	_section_command()
	_section_fight_buffs()
	_section_heroic_resolve()
	_section_post_shot_moves()
	_section_fenrisian_ferocity()
	_section_coordinated_strike()
	_section_wolf_totems()
	_section_ai()
	RE.set_test_seed(-1)


# ---------------------------------------------------------------------------
func _section_registry() -> void:
	print("\n-- A. registry / data --")
	var impl: Array = Codex.all_implemented_ids()
	_check("12 csv ids registered and implemented", Codex.all_registered_ids().size() == 12 and impl.size() == 12, str(impl))
	var loaded := 0
	for s in SM.get_faction_stratagems_for_player(1):
		if not Codex.handles(s):
			continue
		loaded += 1
		var csv := str(s.get("csv_id", ""))
		_check("%s: implemented, marker custom:sw11e" % csv, bool(s.get("implemented", false)) and Codex.is_registered(s))
		var w: Array = s.get("timing", {}).get("windows", [])
		_check("%s windows = %s" % [csv, str(EXPECTED_WINDOWS.get(csv, "?"))], w == EXPECTED_WINDOWS.get(csv, ["?"]), str(w))
	_check("all 12 Space Wolves stratagems loaded for P1 (3 detachments)", loaded == 12, str(loaded))
	_check("WoundModifier.REROLL_ONES_TWOS pinned at 16", int(RE.WoundModifier.REROLL_ONES_TWOS) == Codex.WOUND_REROLL_ONES_TWOS)
	_check("HitModifier / WoundModifier REROLL_ONES pinned at 1", int(RE.HitModifier.REROLL_ONES) == Codex.HIT_REROLL_ONES and int(RE.WoundModifier.REROLL_ONES) == Codex.WOUND_REROLL_ONES)
	# REROLL_ONES_TWOS semantics (apply_wound_modifiers): 1 and 2 re-rolled, a 2 that wounds (2+) kept.
	var rng = RE.RNGService.new(5)
	_check("re-roll 1s and 2s: a 1 is re-rolled", bool(RE.apply_wound_modifiers(1, 16, 4, rng).rerolled))
	_check("re-roll 1s and 2s: a 2 is re-rolled vs 4+", bool(RE.apply_wound_modifiers(2, 16, 4, rng).rerolled))
	_check("re-roll 1s and 2s: a 2 that wounds (2+) is kept", not bool(RE.apply_wound_modifiers(2, 16, 2, rng).rerolled))
	_check("re-roll 1s and 2s: a 3 is kept", not bool(RE.apply_wound_modifiers(3, 16, 5, rng).rerolled))
	# Only a Space Wolves army: the Ork player is refused by the dispatcher.
	var strat: Dictionary = SM.get_stratagem(_sid(1, CSV_TOTEMS))
	var v = Codex.validate(strat, 2, "U_BOYZ_B", {})
	_check("a non-Space Wolves army is refused", not v.ok and "Space Wolves" in str(v.reason), str(v))


# ---------------------------------------------------------------------------
func _section_command() -> void:
	print("\n-- B. GRIMNAR'S COMMAND + BIRTH OF A SAGA (command_phase_main) --")
	_stage_fixture(ACTIVE)
	var gc := _sid(1, CSV_GRIMNAR)
	var bs := _sid(1, CSV_BIRTH)
	_check("both loaded", gc != "" and bs != "")
	var phase = _phase(PHASE_COMMAND)
	var offers = SM.get_window_offers(1, "command_phase_main", {"phase": "command"})
	var gc_t := _offer_targets(offers, gc)
	var bs_t := _offer_targets(offers, bs)
	_check("GRIMNAR'S COMMAND offered on Grey Hunters B", "U_GREY_HUNTERS_B" in gc_t, str(gc_t))
	_check("GRIMNAR'S COMMAND not on the Venerable Dreadnought (VEHICLE)", not "U_VENERABLE_DREADNOUGHT_A" in gc_t)
	_check("GRIMNAR'S COMMAND offers the three doctrines, a choice required", _offer_entry(offers, gc, "U_GREY_HUNTERS_B").get("variants", []).size() == 3 and bool(_offer_entry(offers, gc, "U_GREY_HUNTERS_B").get("require_variant", false)))
	_check("BIRTH OF A SAGA offered on Grey Hunters B", "U_GREY_HUNTERS_B" in bs_t, str(bs_t))
	_check("BIRTH OF A SAGA not on Logan Grimnar (already CHARACTER)", not "U_LOGAN_GRIMNAR_A" in bs_t)
	_check("BIRTH OF A SAGA not on the Venerable Dreadnought (VEHICLE)", not "U_VENERABLE_DREADNOUGHT_A" in bs_t)
	_check("not offered to P2 (Orks)", not gc in _offer_ids(SM.get_window_offers(2, "command_phase_main", {"phase": "command"})))
	_check("not offered in another window", not gc in _offer_ids(SM.get_window_offers(1, "unit_selected_to_move", {"unit_id": "U_GREY_HUNTERS_B", "move_type": "normal"})))
	var panel = SM.can_use_stratagem(1, gc)
	_check("S panel: 'Offered automatically when your Command phase is under way'", not panel.can_use and "Command phase" in str(panel.reason), str(panel))
	# Real hook: END_COMMAND starts the Battle-shock step -> command_phase_main for P1.
	var r = phase.execute_action({"type": "END_COMMAND", "player": 1})
	var pend: Dictionary = phase.get_pending_stratagem_window()
	_check("END_COMMAND opens command_phase_main for P1", str(pend.get("window_id", "")) == "command_phase_main" and int(pend.get("player", 0)) == 1, "%s / %s" % [str(r.get("error", "")), str(pend.get("window_id", ""))])
	if not phase.has_pending_stratagem_window():
		phase.open_stratagem_window(1, "command_phase_main", {"phase": "command"}, "")
	var none = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "command_phase_main", "stratagem_id": gc, "target_unit_id": "U_GREY_HUNTERS_B"})
	_check("GRIMNAR'S COMMAND without a doctrine choice refused", not none.get("success", true))
	var cp0 := _cp(1)
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "command_phase_main", "stratagem_id": gc,
		"target_unit_id": "U_GREY_HUNTERS_B", "context": {"variant_id": "assault"}})
	_check("USE GRIMNAR'S COMMAND (Assault Doctrine) succeeds", use.get("success", false), str(use.get("error", "")))
	_check("CP -1", _cp(1) == cp0 - 1, "%d -> %d" % [cp0, _cp(1)])
	var f := _flags("U_GREY_HUNTERS_B")
	_check("per-unit doctrine keys written (SWCommon contract)", str(f.get("sw11e_doctrine", "")) == "assault" and int(f.get("sw11e_doctrine_expires_player", 0)) == 1, str(f))
	_check("SWCommon.doctrine_active: assault yes, devastator no", Common.doctrine_active_id("U_GREY_HUNTERS_B", "assault") and not Common.doctrine_active_id("U_GREY_HUNTERS_B", "devastator"))
	_check("another unit: no doctrine", not Common.doctrine_active_id("U_WOLF_GUARD_TERMINATORS_A", "assault"))
	_check("Game Log names the stratagem and the doctrine", _log_count("Used GRIMNAR'S COMMAND") >= 1 and _log_count("Assault Doctrine") >= 1)
	pend = phase.get_pending_stratagem_window()
	_check("window re-offered after the use", str(pend.get("window_id", "")) == "command_phase_main", str(pend.get("window_id", "")))
	var re_ids := _offer_ids(pend.get("offers", []))
	_check("…BIRTH OF A SAGA still offered, GRIMNAR'S COMMAND not (once per phase)", bs in re_ids and not gc in re_ids, str(re_ids))
	_check("15.01: Grey Hunters B (already targeted this phase) not offered for BIRTH OF A SAGA", not "U_GREY_HUNTERS_B" in _offer_targets(pend.get("offers", []), bs))
	cp0 = _cp(1)
	use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "command_phase_main", "stratagem_id": bs, "target_unit_id": "U_WOLF_GUARD_TERMINATORS_A"})
	_check("USE BIRTH OF A SAGA on the Wolf Guard Terminators succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	_check("the unit has the CHARACTER keyword", "CHARACTER" in _keywords("U_WOLF_GUARD_TERMINATORS_A"))
	_check("marker sw11e_birth_of_a_saga", bool(_flags("U_WOLF_GUARD_TERMINATORS_A").get("sw11e_birth_of_a_saga", false)))
	_decline_pending(phase)
	# CHARACTER now makes the unit a HEROIC RESOLVE / CHAMPION'S GUIDANCE target.
	var hr := _sid(1, CSV_HEROIC)
	var cg := _sid(1, CSV_GUIDANCE)
	var hr_v = Codex.validate(SM.get_stratagem(hr), 1, "U_WOLF_GUARD_TERMINATORS_A", {"window_id": "enemy_targets_unit_fight", "target_unit_ids": ["U_WOLF_GUARD_TERMINATORS_A"]})
	_check("BIRTH OF A SAGA unit is a CHARACTER unit for HEROIC RESOLVE", hr_v.ok, str(hr_v))
	var cg_v = Codex.validate(SM.get_stratagem(cg), 1, "U_WOLF_GUARD_TERMINATORS_A", {"window_id": "unit_selected_to_fight", "unit_id": "U_WOLF_GUARD_TERMINATORS_A"})
	_check("…and for CHAMPION'S GUIDANCE", cg_v.ok, str(cg_v))
	cg_v = Codex.validate(SM.get_stratagem(cg), 1, "U_GREY_HUNTERS_B", {"window_id": "unit_selected_to_fight", "unit_id": "U_GREY_HUNTERS_B"})
	_check("a unit without CHARACTER is refused CHAMPION'S GUIDANCE", not cg_v.ok)
	# Expiry: the opponent's Command phase does not end them; the owner's does.
	SM.on_turn_start(2)
	_check("still active at the start of P2's turn", "CHARACTER" in _keywords("U_WOLF_GUARD_TERMINATORS_A") and Common.doctrine_active_id("U_GREY_HUNTERS_B", "assault"))
	SM.on_turn_start(1)
	_check("expired at the start of P1's next Command phase: CHARACTER removed", not "CHARACTER" in _keywords("U_WOLF_GUARD_TERMINATORS_A") and not _flags("U_WOLF_GUARD_TERMINATORS_A").has("sw11e_birth_of_a_saga"))
	_check("…and the doctrine keys cleared", not _flags("U_GREY_HUNTERS_B").has("sw11e_doctrine") and not _flags("U_GREY_HUNTERS_B").has("sw11e_grimnars_command") and not Common.doctrine_active_id("U_GREY_HUNTERS_B", "assault"))
	# A doctrine written by another rule after Grimnar's Command is not touched by its expiry.
	_reset_usage()
	var ctx := {"window_id": "command_phase_main", "phase": "command", "variant_id": "devastator"}
	var u2 = SM.use_stratagem(1, gc, "U_WOLF_GUARD_TERMINATORS_A", ctx)
	_check("direct use (devastator) succeeds", u2.get("success", false), str(u2.get("error", "")))
	_flags("U_WOLF_GUARD_TERMINATORS_A")["sw11e_doctrine"] = "tactical"
	SM.on_turn_start(1)
	_check("a doctrine another rule wrote later survives the expiry", str(_flags("U_WOLF_GUARD_TERMINATORS_A").get("sw11e_doctrine", "")) == "tactical")
	_flags("U_WOLF_GUARD_TERMINATORS_A").erase("sw11e_doctrine")
	var bad = SM.can_use_stratagem(1, gc, "U_GREY_HUNTERS_B", {"window_id": "command_phase_main", "variant_id": "bogus"})
	_check("an unknown doctrine is refused", not bad.can_use, str(bad))


# ---------------------------------------------------------------------------
func _section_fight_buffs() -> void:
	print("\n-- C. CHAMPION'S GUIDANCE / UNBRIDLED FEROCITY / FANGS OF THE PACK / EYE OF THE PACK --")
	_stage_fixture(ACTIVE)
	var cg := _sid(1, CSV_GUIDANCE)
	var uf := _sid(1, CSV_UNBRIDLED)
	var fp := _sid(1, CSV_FANGS)
	var ep := _sid(1, CSV_EYE)
	var phase = _phase(PHASE_FIGHT)
	var w := "unit_selected_to_fight"
	var logan := _offer_ids(SM.get_window_offers(1, w, {"phase": "fight", "unit_id": "U_LOGAN_GRIMNAR_A"}))
	_check("Logan (CHARACTER INFANTRY): GUIDANCE, FANGS, EYE offered; UNBRIDLED not", cg in logan and fp in logan and ep in logan and not uf in logan, str(logan))
	var bc := _offer_ids(SM.get_window_offers(1, w, {"phase": "fight", "unit_id": "U_BLOOD_CLAWS_A"}))
	_check("Blood Claws: UNBRIDLED, FANGS, EYE offered; GUIDANCE not (no CHARACTER)", uf in bc and fp in bc and ep in bc and not cg in bc, str(bc))
	var twc := _offer_ids(SM.get_window_offers(1, w, {"phase": "fight", "unit_id": "U_THUNDERWOLF_CAVALRY_A"}))
	_check("Thunderwolf Cavalry (MOUNTED): UNBRIDLED, FANGS offered; EYE not (not INFANTRY)", uf in twc and fp in twc and not ep in twc, str(twc))
	var p2_ids := _offer_ids(SM.get_window_offers(2, w, {"phase": "fight", "unit_id": "U_BOYZ_B"}))
	_check("no Space Wolves stratagem offered to P2 (Orks)", not cg in p2_ids and not uf in p2_ids and not fp in p2_ids and not ep in p2_ids, str(p2_ids))
	_check("not offered in fight_phase_start", not cg in _offer_ids(SM.get_window_offers(1, "fight_phase_start", {"phase": "fight"})))
	# Real hook: SELECT_FIGHTER.
	for _i in [1, 2]:
		if int(phase.pile_in_step_11e) != int(phase.PileInStep11e.ACTIVE):
			break
		phase.execute_action({"type": "END_PILE_IN", "player": int(phase.piling_in_player_11e)})
		_decline_pending(phase)
	var sel = phase.sequencer_11e.peek_selection(GS.state)
	print("    selection: %s" % str(sel))
	if int(sel.get("player", 0)) == 1:
		var r = phase.execute_action({"type": "SELECT_FIGHTER", "unit_id": "U_LOGAN_GRIMNAR_A", "player": 1})
		var pend: Dictionary = phase.get_pending_stratagem_window()
		_check("SELECT_FIGHTER Logan opens unit_selected_to_fight for P1", r.get("success", false) and str(pend.get("window_id", "")) == w and int(pend.get("player", 0)) == 1, "%s / %s" % [str(r.get("error", "")), str(pend)])
	else:
		_check("P1 selects first in this fixture (precondition for the SELECT_FIGHTER hook)", false, str(sel))
	if not phase.has_pending_stratagem_window():
		phase.open_stratagem_window(1, w, {"phase": "fight", "unit_id": "U_LOGAN_GRIMNAR_A"}, "")
	var cp0 := _cp(1)
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": w, "stratagem_id": cg, "target_unit_id": "U_LOGAN_GRIMNAR_A"})
	_check("USE CHAMPION'S GUIDANCE succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	_check("flag sw11e_champions_guidance", bool(_flags("U_LOGAN_GRIMNAR_A").get("sw11e_champions_guidance", false)))
	_check("15.01: FANGS OF THE PACK refused on Logan this phase", not SM.can_use_stratagem(1, fp, "U_LOGAN_GRIMNAR_A", {"window_id": w, "unit_id": "U_LOGAN_GRIMNAR_A"}).can_use)
	_check("once per phase: CHAMPION'S GUIDANCE refused on another CHARACTER unit", not SM.can_use_stratagem(1, cg, "U_WOLF_GUARD_BATTLE_LEADER_A", {"window_id": w, "unit_id": "U_WOLF_GUARD_BATTLE_LEADER_A"}).can_use)
	# Engine consumers.
	var logan_u := _unit("U_LOGAN_GRIMNAR_A")
	_check("hit bits: re-roll 1s in melee only", Codex.apply_hit_bits(0, logan_u, {}, true, []) & 1 and Codex.apply_hit_bits(0, logan_u, {}, false, []) == 0)
	_check("wound bits: re-roll 1s in melee only", Codex.apply_wound_bits(0, logan_u, {}, true, []) & 1 and Codex.apply_wound_bits(0, logan_u, {}, false, []) == 0)
	# A/B (same seeds): WS 4+, S4 vs T4.
	var kw := ["ADEPTUS ASTARTES", "INFANTRY", "CHARACTER"]
	var ab = _ab(_melee_board({}, kw, _melee_weapon("4", "4", "1", "6"), 3, 4), _melee_board({"sw11e_champions_guidance": true}, kw, _melee_weapon("4", "4", "1", "6"), 3, 4), range(7100, 7130))
	_check("A/B CHAMPION'S GUIDANCE: more hits (%d -> %d) and more wounds (%d -> %d) over 30 seeds" % [ab[0], ab[1], ab[2], ab[3]], ab[1] > ab[0] and ab[3] > ab[2], str(ab))
	var ledger: Array = []
	Codex.apply_wound_bits(0, logan_u, {}, true, ledger)
	_check("named in the modifier ledger", ledger.any(func(e): return str(e.get("source", "")) == "Champion's Guidance"), str(ledger))
	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry: flag cleared at the end of the phase", not _flags("U_LOGAN_GRIMNAR_A").has("sw11e_champions_guidance"))

	# UNBRIDLED FEROCITY — melee [LANCE] (+1 to wound after a charge move).
	_reset_usage()
	phase.open_stratagem_window(1, w, {"phase": "fight", "unit_id": "U_BLOOD_CLAWS_A"}, "")
	_flags("U_BLOOD_CLAWS_A")["charged_this_turn"] = true
	use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": w, "stratagem_id": uf, "target_unit_id": "U_BLOOD_CLAWS_A"})
	_check("USE UNBRIDLED FEROCITY on the Blood Claws succeeds", use.get("success", false), str(use.get("error", "")))
	_check("melee [LANCE] grant + marker", bool(_flags("U_BLOOD_CLAWS_A").get("effect_grant_lance", false)) and bool(_flags("U_BLOOD_CLAWS_A").get("sw11e_unbridled_ferocity", false)))
	var bkw := ["ADEPTUS ASTARTES", "INFANTRY", "BLOOD CLAWS"]
	ab = _ab(_melee_board({"charged_this_turn": true}, bkw, _melee_weapon("3", "4", "1", "6"), 3, 5), _melee_board({"charged_this_turn": true, "effect_grant_lance": true}, bkw, _melee_weapon("3", "4", "1", "6"), 3, 5), range(7200, 7220))
	_check("A/B [LANCE] after a charge: same hits, more wounds (%d -> %d)" % [ab[2], ab[3]], ab[0] == ab[1] and ab[3] > ab[2], str(ab))
	var nc = _ab(_melee_board({}, bkw, _melee_weapon("3", "4", "1", "6"), 3, 5), _melee_board({"effect_grant_lance": true}, bkw, _melee_weapon("3", "4", "1", "6"), 3, 5), range(7200, 7210))
	_check("A/B [LANCE] without a charge: no change", nc[2] == nc[3], str(nc))
	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry: [LANCE] grant + marker cleared", not _flags("U_BLOOD_CLAWS_A").has("effect_grant_lance") and not _flags("U_BLOOD_CLAWS_A").has("sw11e_unbridled_ferocity"))
	_flags("U_BLOOD_CLAWS_A").erase("charged_this_turn")

	# FANGS OF THE PACK — melee [PRECISION]; an earlier [PRECISION] grant survives the expiry.
	_reset_usage()
	_flags("U_THUNDERWOLF_CAVALRY_A")["effect_precision_melee"] = true
	phase.open_stratagem_window(1, w, {"phase": "fight", "unit_id": "U_THUNDERWOLF_CAVALRY_A"}, "")
	use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": w, "stratagem_id": fp, "target_unit_id": "U_THUNDERWOLF_CAVALRY_A"})
	_check("USE FANGS OF THE PACK on the Thunderwolf Cavalry succeeds", use.get("success", false), str(use.get("error", "")))
	_check("melee [PRECISION] (engine flag)", RE.has_effect_precision_melee(_unit("U_THUNDERWOLF_CAVALRY_A")))
	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry keeps a [PRECISION] the unit already had", bool(_flags("U_THUNDERWOLF_CAVALRY_A").get("effect_precision_melee", false)) and not _flags("U_THUNDERWOLF_CAVALRY_A").has("sw11e_fangs_of_the_pack"))
	_flags("U_THUNDERWOLF_CAVALRY_A").erase("effect_precision_melee")
	_reset_usage()
	phase.open_stratagem_window(1, w, {"phase": "fight", "unit_id": "U_GREY_HUNTERS_A"}, "")
	phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": w, "stratagem_id": fp, "target_unit_id": "U_GREY_HUNTERS_A"})
	_check("FANGS on Grey Hunters A: [PRECISION]", RE.has_effect_precision_melee(_unit("U_GREY_HUNTERS_A")))
	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry removes the [PRECISION] it granted", not _flags("U_GREY_HUNTERS_A").has("effect_precision_melee"))

	# EYE OF THE PACK — melee (fight) and ranged (own Shooting phase).
	_reset_usage()
	phase.open_stratagem_window(1, w, {"phase": "fight", "unit_id": "U_GREY_HUNTERS_A"}, "")
	use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": w, "stratagem_id": ep, "target_unit_id": "U_GREY_HUNTERS_A"})
	_check("USE EYE OF THE PACK (fight) succeeds", use.get("success", false), str(use.get("error", "")))
	_check("wound bits: re-roll 1s and 2s, melee and ranged", Codex.apply_wound_bits(0, _unit("U_GREY_HUNTERS_A"), {}, true, []) & 16 and Codex.apply_wound_bits(0, _unit("U_GREY_HUNTERS_A"), {}, false, []) & 16)
	var ikw := ["ADEPTUS ASTARTES", "INFANTRY"]
	ab = _ab(_melee_board({}, ikw, _melee_weapon("3", "3", "1", "6"), 3, 6), _melee_board({"sw11e_eye_of_the_pack": true}, ikw, _melee_weapon("3", "3", "1", "6"), 3, 6), range(7300, 7330))
	_check("A/B EYE OF THE PACK (melee, wound on 5+): same hits, more wounds (%d -> %d)" % [ab[2], ab[3]], ab[0] == ab[1] and ab[3] > ab[2], str(ab))
	SM.on_phase_end(PHASE_FIGHT)
	_check("expiry: flag cleared", not _flags("U_GREY_HUNTERS_A").has("sw11e_eye_of_the_pack"))
	# Ranged: own Shooting phase only.
	_reset_usage()
	var shoot_ctx := {"phase": "shooting", "unit_id": "U_WULFEN_A"}
	_check("EYE offered when the Wulfen (INFANTRY) are selected to shoot", ep in _offer_ids(SM.get_window_offers(1, "unit_selected_to_shoot", shoot_ctx)))
	GS.state.meta["active_player"] = 2
	_check("…but not in the opponent's Shooting phase", not SM.can_use_stratagem(1, ep, "U_WULFEN_A", {"window_id": "unit_selected_to_shoot", "unit_id": "U_WULFEN_A"}).can_use)
	GS.state.meta["active_player"] = 1
	var board: Dictionary = GS.create_snapshot()
	board.units.U_GRETCHIN_C.meta.stats["toughness"] = 8
	var wid := ""
	for mid in RE.get_unit_weapons("U_WULFEN_A", board):
		for x in RE.get_unit_weapons("U_WULFEN_A", board)[mid]:
			wid = str(x)
	var mids: Array = RE.get_unit_weapons("U_WULFEN_A", board).keys()
	var asg := {"weapon_id": wid, "target_unit_id": "U_GRETCHIN_C", "model_ids": mids}
	var off := 0
	var on := 0
	var on_board: Dictionary = board.duplicate(true)
	on_board.units.U_WULFEN_A.flags["sw11e_eye_of_the_pack"] = true
	for sd in range(7400, 7430):
		off += _sum_successes(RE.resolve_shoot({"actor_unit_id": "U_WULFEN_A", "payload": {"assignments": [asg]}}, board.duplicate(true), RE.RNGService.new(sd)).dice, "to_wound")
		on += _sum_successes(RE.resolve_shoot({"actor_unit_id": "U_WULFEN_A", "payload": {"assignments": [asg]}}, on_board.duplicate(true), RE.RNGService.new(sd)).dice, "to_wound")
	_check("A/B EYE OF THE PACK (ranged auto path, %s vs T8): more wounds (%d -> %d)" % [wid, off, on], on > off, "%d vs %d" % [off, on])
	var iw = RE.resolve_shoot_until_wounds({"actor_unit_id": "U_WULFEN_A", "payload": {"assignments": [asg]}}, on_board.duplicate(true), RE.RNGService.new(7))
	var named := false
	for b in iw.get("dice", []):
		if b.get("modifier_ledger", []).any(func(e): return str(e.get("source", "")) == "Eye of the Pack"):
			named = true
	_check("ranged interactive path names Eye of the Pack in its wound ledger", named)


# ---------------------------------------------------------------------------
func _section_heroic_resolve() -> void:
	print("\n-- D. HEROIC RESOLVE --")
	_stage_fixture(ACTIVE)
	var hr := _sid(1, CSV_HEROIC)
	var phase = _phase(PHASE_FIGHT)
	var w := "enemy_targets_unit_fight"
	var ctx := {"phase": "fight", "attacker_unit_id": "U_WARBOSS_A", "target_unit_ids": ["U_LOGAN_GRIMNAR_A"]}
	_check("offered when the Warboss targets Logan (CHARACTER)", _offer_targets(SM.get_window_offers(1, w, ctx), hr) == ["U_LOGAN_GRIMNAR_A"])
	_check("not for a non-CHARACTER target", not hr in _offer_ids(SM.get_window_offers(1, w, {"phase": "fight", "attacker_unit_id": "U_BOYZ_B", "target_unit_ids": ["U_BLOOD_CLAWS_A"]})))
	_check("not for a unit that was not targeted", not SM.can_use_stratagem(1, hr, "U_WOLF_GUARD_BATTLE_LEADER_A", ctx.merged({"window_id": w})).can_use)
	_check("2 CP", int(SM.get_stratagem(hr).get("cp_cost", 0)) == 2)
	# Own Shooting phase: not "your opponent's".
	var own = SM.can_use_stratagem(1, hr, "U_WOLF_GUARD_BATTLE_LEADER_A", {"window_id": "enemy_targets_unit_shooting", "attacker_unit_id": "U_KOMMANDOS_A", "target_unit_ids": ["U_WOLF_GUARD_BATTLE_LEADER_A"]})
	_check("refused in its own turn's enemy_targets_unit_shooting", not own.can_use, str(own))
	phase.open_stratagem_window(1, w, ctx, "")
	var cp0 := _cp(1)
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": w, "stratagem_id": hr, "target_unit_id": "U_LOGAN_GRIMNAR_A"})
	_check("USE HEROIC RESOLVE succeeds, CP -2", use.get("success", false) and _cp(1) == cp0 - 2, str(use.get("error", "")))
	var f = _flags("U_LOGAN_GRIMNAR_A").get("sw11e_heroic_resolve", null)
	_check("flag records the attacker", typeof(f) == TYPE_DICTIONARY and "U_WARBOSS_A" in f.get("attacker_ids", []), str(f))
	_check("-1 D through EffectPrimitives.get_effect_minus_damage", int(EffectPrimitivesData.get_effect_minus_damage(_unit("U_LOGAN_GRIMNAR_A"))) == 1)
	# A/B: D2 attacks, no save -> half the wounds lost with -1 D (min 1).
	var kw := ["ORKS", "INFANTRY"]
	var ab = _ab(_melee_board({}, kw, _melee_weapon("3", "5", "2", "6"), 2, 4), _melee_board({}, kw, _melee_weapon("3", "5", "2", "6"), 2, 4, {"sw11e_heroic_resolve": {"attacker_ids": ["U_ATK"]}}), range(7500, 7520))
	_check("A/B -1 D: same wounds (%d), fewer wounds lost (%d -> %d)" % [ab[2], ab[4], ab[5]], ab[2] == ab[3] and ab[5] < ab[4] and ab[5] > 0, str(ab))
	var d1 = _ab(_melee_board({}, kw, _melee_weapon("3", "5", "1", "6"), 2, 4), _melee_board({}, kw, _melee_weapon("3", "5", "1", "6"), 2, 4, {"sw11e_heroic_resolve": {"attacker_ids": ["U_ATK"]}}), range(7500, 7510))
	_check("A/B D1 attacks stay 1 (minimum 1)", d1[4] == d1[5], str(d1))
	# Ends when that enemy unit has attacked — not when another unit has.
	Codex.on_unit_has_attacked("U_BOYZ_B")
	_check("another enemy unit attacking does not end it", _flags("U_LOGAN_GRIMNAR_A").has("sw11e_heroic_resolve"))
	Codex.on_unit_has_attacked("U_WARBOSS_A")
	_check("ends once the Warboss has attacked", not _flags("U_LOGAN_GRIMNAR_A").has("sw11e_heroic_resolve") and EffectPrimitivesData.get_effect_minus_damage(_unit("U_LOGAN_GRIMNAR_A")) == 0)
	SM.on_phase_end(PHASE_FIGHT)
	# Opponent's Shooting phase: folded into the defender's reactive dialog.
	_stage_fixture(REACTIVE)
	hr = _sid(2, CSV_HEROIC)
	phase = _phase(PHASE_SHOOTING)
	phase.active_shooter_id = "U_KOMMANDOS_A"
	phase.confirmed_assignments = [{"target_unit_id": "U_WOLF_GUARD_BATTLE_LEADER_A", "weapon_id": "x", "model_ids": []}]
	var chk: Dictionary = phase._check_reactive_stratagems()
	var found := false
	for e in chk.get("available_stratagems", []):
		if str(e.get("stratagem", {}).get("id", "")) == hr:
			found = true
	_check("opponent's Shooting phase: HEROIC RESOLVE in the defender's reactive dialog", chk.get("has_opportunities", false) and found, str(chk.keys()))
	phase.awaiting_reactive_stratagem = true
	cp0 = _cp(2)
	var ru = phase.execute_action({"type": "USE_REACTIVE_STRATAGEM", "player": 2, "stratagem_id": hr, "target_unit_id": "U_WOLF_GUARD_BATTLE_LEADER_A"})
	_check("USE_REACTIVE_STRATAGEM HEROIC RESOLVE succeeds, CP -2", ru.get("success", false) and _cp(2) == cp0 - 2, str(ru.get("error", "")))
	f = _flags("U_WOLF_GUARD_BATTLE_LEADER_A").get("sw11e_heroic_resolve", null)
	_check("flag records the Kommandos", typeof(f) == TYPE_DICTIONARY and "U_KOMMANDOS_A" in f.get("attacker_ids", []), str(f))
	SM.on_phase_end(PHASE_SHOOTING)
	_check("end-of-phase backstop clears it", not _flags("U_WOLF_GUARD_BATTLE_LEADER_A").has("sw11e_heroic_resolve"))


# ---------------------------------------------------------------------------
func _section_post_shot_moves() -> void:
	print("\n-- E. IMPETUOSITY / BATTLE INSTINCTS (enemy_has_shot) --")
	_stage_fixture(REACTIVE)
	var im := _sid(2, CSV_IMPET)
	var bi := _sid(2, CSV_INSTINCTS)
	_check("both loaded for P2", im != "" and bi != "")
	var w := "enemy_has_shot"
	var phase = _phase(PHASE_SHOOTING)
	var base := {"phase": "shooting", "attacker_unit_id": "U_GRETCHIN_C"}
	_check("IMPETUOSITY offered on a TARGETED (not hit) Wulfen unit", _offer_targets(SM.get_window_offers(2, w, base.merged({"targeted_unit_ids": ["U_WULFEN_A"], "hit_unit_ids": []})), im) == ["U_WULFEN_A"])
	_check("…not when the Wulfen were not targeted", not im in _offer_ids(SM.get_window_offers(2, w, base.merged({"targeted_unit_ids": ["U_GREY_HUNTERS_B"], "hit_unit_ids": []}))))
	_check("…not on Grey Hunters (not BLOOD CLAWS/TWC/WULFEN)", not SM.can_use_stratagem(2, im, "U_GREY_HUNTERS_B", {"window_id": w, "targeted_unit_ids": ["U_GREY_HUNTERS_B"]}).can_use)
	_check("…not on an engaged Blood Claws unit", not SM.can_use_stratagem(2, im, "U_BLOOD_CLAWS_A", {"window_id": w, "targeted_unit_ids": ["U_BLOOD_CLAWS_A"]}).can_use)
	_check("BATTLE INSTINCTS offered on targeted Grey Hunters B (INFANTRY)", bi in _offer_ids(SM.get_window_offers(2, w, base.merged({"targeted_unit_ids": ["U_GREY_HUNTERS_B"]}))))
	_check("BATTLE INSTINCTS not on the Venerable Dreadnought", not SM.can_use_stratagem(2, bi, "U_VENERABLE_DREADNOUGHT_A", {"window_id": w, "targeted_unit_ids": ["U_VENERABLE_DREADNOUGHT_A"]}).can_use)
	_check("not in another window", not SM.can_use_stratagem(2, im, "U_WULFEN_A", {"window_id": "enemy_targets_unit_shooting", "target_unit_ids": ["U_WULFEN_A"]}).can_use)
	# Real hook: the Gretchin (P1, active; 3.5" away) shoot the Wulfen.
	RE.set_test_seed(11)
	var cp0 := _cp(2)
	var res = _shoot(phase, "U_GRETCHIN_C", "U_WULFEN_A")
	_check("Gretchin SHOOT at the Wulfen succeeds", res.get("success", false), str(res.get("error", "")))
	_decline_until(phase, 2)
	var pend: Dictionary = phase.get_pending_stratagem_window()
	_check("enemy_has_shot pending for P2", str(pend.get("window_id", "")) == w and int(pend.get("player", 0)) == 2, str(pend.get("window_id", "")))
	_check("ctx carries targeted_unit_ids with the Wulfen", "U_WULFEN_A" in pend.get("ctx", {}).get("targeted_unit_ids", []), str(pend.get("ctx", {})))
	_check("IMPETUOSITY offered on the Wulfen", im in _offer_ids(pend.get("offers", [])), str(_offer_ids(pend.get("offers", []))))
	var gretchin_d0: float = Common.group_distance_inches("U_WULFEN_A", "U_GRETCHIN_C")
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 2, "window_id": w, "stratagem_id": im, "target_unit_id": "U_WULFEN_A"})
	_check("USE IMPETUOSITY succeeds, CP -1", use.get("success", false) and _cp(2) == cp0 - 1, str(use.get("error", "")))
	var fu: Dictionary = phase._ork11e_followup
	_check("surge follow-up pending for P2: D6 = max distance, the Gretchin are the surge target", not fu.is_empty() and fu.kind == "surge" and int(fu.roll) >= 1 and int(fu.roll) <= 6 and float(fu.max_inches) == float(fu.roll) and str(fu.surge_target) == "U_GRETCHIN_C", str(fu))
	var auto = phase.execute_action({"type": "ORK11E_REACTIVE_MOVE_AUTO", "player": 2})
	var conf = phase.execute_action({"type": "ORK11E_REACTIVE_MOVE_CONFIRM", "player": 2})
	_check("auto surge + confirm succeed", auto.get("success", false) and conf.get("success", false), "%s / %s" % [str(auto.get("error", "")), str(conf.get("error", ""))])
	var gretchin_d1: float = Common.group_distance_inches("U_WULFEN_A", "U_GRETCHIN_C")
	_check("the Wulfen ended closer to the Gretchin (%.2f\" -> %.2f\")" % [gretchin_d0, gretchin_d1], gretchin_d1 < gretchin_d0)
	_check("follow-up finished, nothing pending", phase._ork11e_followup.is_empty() and not phase.has_pending_stratagem_window())
	_check("Game Log names IMPETUOSITY", _log_count("IMPETUOSITY") >= 1)
	# BATTLE INSTINCTS: the Flash Gitz shoot Grey Hunters B (about 3" short of obj_nml_2).
	_stage_fixture(REACTIVE)
	phase = _phase(PHASE_SHOOTING)
	RE.set_test_seed(21)
	var in_range0: bool = RM.group_within_objective_range(GS.state, "U_GREY_HUNTERS_B")
	_check("Grey Hunters B not within range of an objective before", not in_range0)
	res = _shoot(phase, "U_FLASH_GITZ_A", "U_GREY_HUNTERS_B")
	_check("Flash Gitz SHOOT at Grey Hunters B succeeds", res.get("success", false), str(res.get("error", "")))
	_decline_until(phase, 2)
	pend = phase.get_pending_stratagem_window()
	_check("BATTLE INSTINCTS offered on Grey Hunters B", bi in _offer_ids(pend.get("offers", [])) and "U_GREY_HUNTERS_B" in _offer_targets(pend.get("offers", []), bi), str(pend.get("offers", [])))
	use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 2, "window_id": w, "stratagem_id": bi, "target_unit_id": "U_GREY_HUNTERS_B"})
	_check("USE BATTLE INSTINCTS succeeds", use.get("success", false), str(use.get("error", "")))
	fu = phase._ork11e_followup
	_check("normal-move follow-up: D3+3 = 4..6\"", not fu.is_empty() and fu.kind == "normal" and float(fu.max_inches) >= 4.0 and float(fu.max_inches) <= 6.0, str(fu))
	auto = phase.execute_action({"type": "ORK11E_REACTIVE_MOVE_AUTO", "player": 2})
	conf = phase.execute_action({"type": "ORK11E_REACTIVE_MOVE_CONFIRM", "player": 2})
	_check("auto move + confirm succeed", auto.get("success", false) and conf.get("success", false), "%s / %s" % [str(auto.get("error", "")), str(conf.get("error", ""))])
	_check("Grey Hunters B now within range of obj_nml_2", RM.group_within_objective_range(GS.state, "U_GREY_HUNTERS_B"))
	_check("Game Log names the D3 roll", _log_count("BATTLE INSTINCTS") >= 1)
	# Own turn: refused.
	_stage_fixture(ACTIVE)
	var own = SM.can_use_stratagem(1, _sid(1, CSV_IMPET), "U_WULFEN_A", {"window_id": w, "targeted_unit_ids": ["U_WULFEN_A"]})
	_check("refused in its own Shooting phase", not own.can_use, str(own))


# ---------------------------------------------------------------------------
func _section_fenrisian_ferocity() -> void:
	print("\n-- F. FENRISIAN FEROCITY --")
	_stage_fixture(ACTIVE)
	var ff := _sid(1, CSV_FEROCITY)
	var phase = _phase(PHASE_MOVEMENT)
	var w := "unit_selected_to_move"
	_check("offered on Thunderwolf Cavalry B (MOUNTED) selected to move", ff in _offer_ids(SM.get_window_offers(1, w, {"phase": "movement", "unit_id": "U_THUNDERWOLF_CAVALRY_B", "move_type": "normal"})))
	_check("offered on the Venerable Dreadnought (WALKER)", ff in _offer_ids(SM.get_window_offers(1, w, {"phase": "movement", "unit_id": "U_VENERABLE_DREADNOUGHT_A", "move_type": "advance"})))
	_check("not on Grey Hunters B (INFANTRY)", not ff in _offer_ids(SM.get_window_offers(1, w, {"phase": "movement", "unit_id": "U_GREY_HUNTERS_B", "move_type": "normal"})))
	_check("offered when the cavalry declares a charge", ff in _offer_ids(SM.get_window_offers(1, "unit_declares_charge", {"phase": "charge", "unit_id": "U_THUNDERWOLF_CAVALRY_B", "target_unit_ids": ["U_GRETCHIN_C"]})))
	var r = phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_THUNDERWOLF_CAVALRY_B", "player": 1})
	var pend: Dictionary = phase.get_pending_stratagem_window()
	_check("BEGIN_NORMAL_MOVE opens unit_selected_to_move with FENRISIAN FEROCITY", str(pend.get("window_id", "")) == w and ff in _offer_ids(pend.get("offers", [])), "%s / %s" % [str(r.get("error", "")), str(pend.get("window_id", ""))])
	if not phase.has_pending_stratagem_window():
		phase.open_stratagem_window(1, w, {"phase": "movement", "unit_id": "U_THUNDERWOLF_CAVALRY_B", "move_type": "normal"}, "")
	var cp0 := _cp(1)
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": w, "stratagem_id": ff, "target_unit_id": "U_THUNDERWOLF_CAVALRY_B"})
	_check("USE FENRISIAN FEROCITY succeeds, CP -1", use.get("success", false) and _cp(1) == cp0 - 1, str(use.get("error", "")))
	_check("the engine's MOBILE grant is on", bool(_flags("U_THUNDERWOLF_CAVALRY_B").get("ork11e_mobile", false)))
	_check("MovementPhase terrain keywords include MOBILE", "MOBILE" in phase._terrain_rule_keywords("U_THUNDERWOLF_CAVALRY_B", {}))
	var tm = root.get_node("TerrainManager")
	_check("13.06: MOBILE passes dense terrain", tm._passes_dense_11e(["MOUNTED", "MOBILE"]) and not tm._passes_dense_11e(["MOUNTED"]))
	_check("once per phase", not SM.can_use_stratagem(1, ff, "U_VENERABLE_DREADNOUGHT_A", {"window_id": w, "unit_id": "U_VENERABLE_DREADNOUGHT_A", "move_type": "normal"}).can_use)
	GS.state.meta["active_player"] = 2
	_check("not in the opponent's turn", not SM.can_use_stratagem(1, ff, "U_VENERABLE_DREADNOUGHT_A", {"window_id": w, "unit_id": "U_VENERABLE_DREADNOUGHT_A", "move_type": "normal"}).can_use)
	GS.state.meta["active_player"] = 1
	_decline_pending(phase)
	SM.on_phase_end(PHASE_MOVEMENT)
	_check("expiry: MOBILE grant + marker cleared at the end of the phase", not _flags("U_THUNDERWOLF_CAVALRY_B").has("ork11e_mobile") and not _flags("U_THUNDERWOLF_CAVALRY_B").has("sw11e_fenrisian_ferocity"))


# ---------------------------------------------------------------------------
func _section_coordinated_strike() -> void:
	print("\n-- G. CO-ORDINATED STRIKE (fight_phase_end) --")
	_stage_fixture(REACTIVE)
	var cs := _sid(2, CSV_STRIKE)
	var phase = _phase(PHASE_FIGHT)
	var w := "fight_phase_end"
	var t := _offer_targets(SM.get_window_offers(2, w, {"phase": "fight"}), cs)
	_check("offered on Thunderwolf Cavalry B (unengaged, within 9\" of an edge)", "U_THUNDERWOLF_CAVALRY_B" in t, str(t))
	_check("offered on the Wulfen (unengaged, within 9\" of the left edge)", "U_WULFEN_A" in t, str(t))
	_check("not on the engaged Blood Claws / Thunderwolf Cavalry A", not "U_BLOOD_CLAWS_A" in t and not "U_THUNDERWOLF_CAVALRY_A" in t)
	_check("not on Grey Hunters B (keyword)", not "U_GREY_HUNTERS_B" in t)
	_translate("U_THUNDERWOLF_CAVALRY_B", 14.0, -14.0)
	_check("not once the cavalry is more than 9\" from every edge", not "U_THUNDERWOLF_CAVALRY_B" in _offer_targets(SM.get_window_offers(2, w, {"phase": "fight"}), cs), str(Common.group_edge_distance_inches("U_THUNDERWOLF_CAVALRY_B")))
	_translate("U_THUNDERWOLF_CAVALRY_B", -14.0, 14.0)
	phase.open_stratagem_window(2, w, {"phase": "fight"}, "")
	var cp0 := _cp(2)
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 2, "window_id": w, "stratagem_id": cs, "target_unit_id": "U_THUNDERWOLF_CAVALRY_B"})
	_check("USE CO-ORDINATED STRIKE succeeds, CP -1", use.get("success", false) and _cp(2) == cp0 - 1, str(use.get("error", "")))
	var u := _unit("U_THUNDERWOLF_CAVALRY_B")
	var off_board := true
	for m in u.models:
		if m.get("position", null) != null:
			off_board = false
	_check("placed in strategic reserves (status, reserve type, off the board)", int(u.status) == int(GS.UnitStatus.IN_RESERVES) and str(u.get("reserve_type", "")) == "strategic_reserves" and off_board, str(u.get("status")))
	_check("Game Log: CO-ORDINATED STRIKE", _log_count("CO-ORDINATED STRIKE") >= 1)
	# Its own turn: refused ("End of your opponent's Fight phase").
	_stage_fixture(ACTIVE)
	var own = SM.can_use_stratagem(1, _sid(1, CSV_STRIKE), "U_THUNDERWOLF_CAVALRY_B", {"window_id": w})
	_check("refused at the end of its own Fight phase", not own.can_use, str(own))


# ---------------------------------------------------------------------------
func _section_wolf_totems() -> void:
	print("\n-- H. WOLF TOTEMS (S panel) --")
	_stage_fixture(REACTIVE)
	var wt := _sid(2, CSV_TOTEMS)
	var phase = _phase(PHASE_SHOOTING)
	var panel = SM.can_use_stratagem(2, wt)
	_check("S panel: usable in the opponent's Shooting phase", panel.can_use, str(panel))
	_check("target: Wulfen (INFANTRY) yes", SM.can_use_stratagem(2, wt, "U_WULFEN_A").can_use)
	_check("target: Thunderwolf Cavalry (MOUNTED) yes", SM.can_use_stratagem(2, wt, "U_THUNDERWOLF_CAVALRY_B").can_use)
	_check("target: Venerable Dreadnought (VEHICLE) no", not SM.can_use_stratagem(2, wt, "U_VENERABLE_DREADNOUGHT_A").can_use)
	_check("target: an Ork unit no", not SM.can_use_stratagem(2, wt, "U_BOYZ_B").can_use)
	var cp0 := _cp(2)
	var use = SM.use_stratagem(2, wt, "U_WULFEN_A")
	_check("use succeeds, CP -1", use.get("success", false) and _cp(2) == cp0 - 1, str(use.get("error", "")))
	var wu := _unit("U_WULFEN_A")
	_check("FNP 5+ against mortal wounds", RE.get_unit_fnp_vs(wu, false, true) == 5)
	_check("…not against ordinary damage", RE.get_unit_fnp_vs(wu, false, false) == 0)
	var lost_off := 0
	var lost_on := 0
	var board: Dictionary = GS.create_snapshot()
	var off_board: Dictionary = board.duplicate(true)
	off_board.units.U_WULFEN_A.flags.erase("sw11e_wolf_totems")
	for sd in range(7600, 7620):
		lost_off += int(RE.apply_mortal_wounds("U_WULFEN_A", 4, off_board.duplicate(true), RE.RNGService.new(sd)).get("wounds_applied", 0))
		lost_on += int(RE.apply_mortal_wounds("U_WULFEN_A", 4, board.duplicate(true), RE.RNGService.new(sd)).get("wounds_applied", 0))
	_check("A/B 4 mortal wounds x 20 seeds: fewer wounds applied (%d -> %d)" % [lost_off, lost_on], lost_on < lost_off, "%d vs %d" % [lost_off, lost_on])
	_check("once per phase", not SM.can_use_stratagem(2, wt, "U_THUNDERWOLF_CAVALRY_B").can_use)
	SM.on_phase_end(PHASE_SHOOTING)
	_check("expiry at the end of the phase", not _flags("U_WULFEN_A").has("sw11e_wolf_totems") and RE.get_unit_fnp_vs(_unit("U_WULFEN_A"), false, true) == 0)
	_reset_usage()
	PM.transition_to_phase(PHASE_FIGHT)
	_check("usable in the Fight phase too (any phase)", SM.can_use_stratagem(2, wt, "U_WULFEN_A").can_use)
	# AI (WP-S5): it lasts one phase, so the AI never spends it where no mortal
	# wounds come (it used to fire it in its own Command phase).
	var Combat = load("res://scripts/codex/space_wolves/SWCodexCombat.gd")
	var hz_uid := ""
	for uid in GS.state.units:
		var uu: Dictionary = GS.state.units[uid]
		if int(uu.get("owner", 0)) == 2 and Combat.Common.group_points(uid) >= 80:
			for w in uu.get("meta", {}).get("weapons", []):
				if "hazardous" in str(w.get("special_rules", "")).to_lower() and str(w.get("type", "")).to_lower() != "melee":
					hz_uid = uid
		if hz_uid != "":
			break
	if hz_uid != "":
		GS.state.meta.phase = PHASE_COMMAND
		_check("AI: WOLF TOTEMS scores 0 in the Command phase (%s, [HAZARDOUS] gun)" % hz_uid, Combat._totems_score(hz_uid) == 0.0)
		GS.state.meta.phase = PHASE_SHOOTING
		_check("AI: …and > 0 in the Shooting phase", Combat._totems_score(hz_uid) > 0.0)


# ---------------------------------------------------------------------------
func _section_ai() -> void:
	print("\n-- I. AI deciders --")
	var ai = root.get_node("AIPlayer")
	var AIDM = load("res://scripts/AIDecisionMaker.gd")
	# Command window: AI P1 answers synchronously (and is offered the window again after a use).
	_stage_fixture(ACTIVE)
	var phase = _phase(PHASE_COMMAND)
	ai.enabled = true
	ai.ai_players = {1: true, 2: false}
	var cp0 := _cp(1)
	var paused: bool = phase.open_stratagem_window(1, "command_phase_main", {"phase": "command"}, "")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_check("AI command_phase_main: no pause, nothing pending", not paused and not phase.has_pending_stratagem_window())
	var gc_used := false
	for uid in GS.state.units:
		if str(GS.state.units[uid].get("flags", {}).get("sw11e_grimnars_command", "")) != "":
			gc_used = true
	print("    AI command: CP %d -> %d, grimnar used %s" % [cp0, _cp(1), gc_used])
	_check("AI spent CP only on what it used (CP never negative)", _cp(1) >= 0 and _cp(1) <= cp0)
	# Fight window decisions are sane.
	_phase(PHASE_FIGHT)
	var cg := _sid(1, CSV_GUIDANCE)
	var offers = SM.get_window_offers(1, "unit_selected_to_fight", {"phase": "fight", "unit_id": "U_LOGAN_GRIMNAR_A"})
	var d: Dictionary = AIDM.decide_window_stratagem(1, "unit_selected_to_fight", offers, {"phase": "fight", "unit_id": "U_LOGAN_GRIMNAR_A"})
	_check("AI unit_selected_to_fight (Logan engaged, 6 CP): uses a buff", bool(d.get("use", false)) and str(d.get("target_unit_id", "")) == "U_LOGAN_GRIMNAR_A", str(d))
	var hr_offers = SM.get_window_offers(1, "enemy_targets_unit_fight", {"phase": "fight", "attacker_unit_id": "U_WARBOSS_A", "target_unit_ids": ["U_LOGAN_GRIMNAR_A"]})
	d = AIDM.decide_window_stratagem(1, "enemy_targets_unit_fight", hr_offers, {"phase": "fight", "attacker_unit_id": "U_WARBOSS_A", "target_unit_ids": ["U_LOGAN_GRIMNAR_A"]})
	print("    AI HEROIC RESOLVE decision vs Warboss: %s" % str(d))
	_check("AI HEROIC RESOLVE decision is well-formed", d.has("use"))
	# enemy_has_shot: AI P2 surges the Wulfen (IMPETUOSITY) synchronously.
	_stage_fixture(REACTIVE)
	phase = _phase(PHASE_SHOOTING)
	RE.set_test_seed(11)
	ai.enabled = true
	ai.ai_players = {1: false, 2: true}
	cp0 = _cp(2)
	var origin: Dictionary = RM.current_positions("U_WULFEN_A", GS.state)
	var res = _shoot(phase, "U_GRETCHIN_C", "U_WULFEN_A")
	_decline_until(phase, 2)
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_check("AI defender: SHOOT resolves with no pause", res.get("success", false) and not phase.has_pending_stratagem_window() and phase._ork11e_followup.is_empty())
	var moved := false
	var now: Dictionary = RM.current_positions("U_WULFEN_A", GS.state)
	for key in origin:
		if now.has(key) and now[key].distance_to(origin[key]) > 1.0:
			moved = true
	_check("AI used IMPETUOSITY and surged the Wulfen", _cp(2) == cp0 - 1 and moved, "cp %d -> %d moved %s" % [cp0, _cp(2), moved])
	# AI pre-emptive WOLF TOTEMS scoring (own turn, panel): 0 without a mortal-wound threat.
	var wt: Dictionary = SM.get_stratagem(_sid(2, CSV_TOTEMS))
	_check("AI WOLF TOTEMS score 0 on a unit with no mortal-wound threat (Wulfen)", Codex.ai_score(wt, 2, "U_WULFEN_A", "", {}) == 0.0)
	_check("AI WOLF TOTEMS scores a unit with a [HAZARDOUS] weapon (Grey Hunters B)", Codex.ai_score(wt, 2, "U_GREY_HUNTERS_B", "", {}) >= 2.0)
