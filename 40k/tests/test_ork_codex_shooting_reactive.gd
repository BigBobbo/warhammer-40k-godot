extends SceneTree

# Codex: Orks (11e) — SHOOTING-REACTIVE group (OrkCodexShootingReactive.gd):
# GROT SHIELDS, HULKING BRUTES, SPEEDIEST FREEKS (enemy_targets_unit_shooting,
# folded into the defender's reactive dialog), GRAB IT (unit_has_shot),
# GUN-CRAZY SHOW-OFFS and GOADED INTO ACTION (enemy_has_shot), their engine
# consumers and follow-ups (design .llm/ork_codex_11e_design.md §3, §3.2, §6).
#
#   A. registry: the six ids are implemented, AI kinds
#   B. enemy_targets_unit_shooting offers + gates (keyword, targeted, window,
#      turn), HULKING BRUTES variant (+1 CP), GROT SHIELDS secondary pick
#   C. effects A/B with the same seeds: HULKING BRUTES (-1 to wound, S>T and
#      upgrade), SPEEDIEST FREEKS (unmodified 1-3 fail), GROT SHIELDS
#      (interception -> Gretchin mortal wounds; Gretchin gone -> hits proceed;
#      other attacker unaffected) on the interactive AND auto resolver paths
#   D. the reactive dialog: core + codex stratagem on one targeting (re-opens
#      after a use), "don't offer again this phase", expiry at end of phase
#   E. unit_has_shot / GRAB IT: window after a real SHOOT, human follow-up
#      (stage / clamp / end-condition refusal / auto / confirm), other actions
#      refused meanwhile, charge lock, expiry, AI decider auto-move
#   F. enemy_has_shot / GUN-CRAZY SHOW-OFFS: offered only to a hit
#      FLASH GITZ/TANKBUSTAS unit, auto-resolved shooting at the attacker
#   G. enemy_has_shot / GOADED INTO ACTION: wounded + unengaged BEAST SNAGGA,
#      D6 surge (riled-up re-roll), human auto+confirm, AI auto
#   H. network: ORK11E_REACTIVE_MOVE_* are turn-exempt; the mover is checked
#
# Usage: godot --headless --path 40k --script tests/test_ork_codex_shooting_reactive.gd

const PHASE_COMMAND := 6
const PHASE_SHOOTING := 8
const PHASE_CHARGE := 9
const PX := 40.0

var passed := 0
var failed := 0
var SM = null
var GS = null
var PM = null
var RE = null
var RM = null
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


func _on_window_opened(player: int, window_id: String, offers: Array, ctx: Dictionary) -> void:
	_window_events.append({"player": player, "window_id": window_id, "offers": offers, "ctx": ctx})


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
	GS.state.players["1"]["cp"] = 6
	GS.state.players["2"]["cp"] = 6
	SM._usage_history = {"1": [], "2": []}
	return ok


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


func _shooting_phase():
	PM.transition_to_phase(PHASE_COMMAND)
	_cus11e_unready()
	PM.transition_to_phase(PHASE_SHOOTING)
	var phase = PM.get_current_phase_instance()
	if phase and not phase.stratagem_window_opened.is_connected(_on_window_opened):
		phase.stratagem_window_opened.connect(_on_window_opened)
	return phase


## Codex: Adeptus Custodes (11e, WP-C3): the Custodes Command phase readies
## every Martial Ka'tah unit, so a Custodes unit selected to shoot would first
## open a SALVUS ka'tah window for the human P1. The ka'tahs are not under test
## here (test_custodes_army_rules_11e.gd covers them): un-ready the Custodes
## and spend Master of Ka'tahs for the round.
func _cus11e_unready() -> void:
	var rnd: int = int(GS.get_battle_round())
	for uid in GS.state.units:
		var u: Dictionary = GS.state.units[uid]
		if not (u.get("flags", null) is Dictionary):
			u["flags"] = {}
		u.flags.erase("cus11e_readied")
		u.flags["cus11e_master_of_katahs_round"] = rnd


func _move_unit(uid: String, dx_in: float, dy_in: float) -> void:
	for m in GS.state.units[uid].models:
		var p = m.get("position", null)
		if p is Dictionary:
			m["position"] = {"x": float(p.x) + dx_in * PX, "y": float(p.y) + dy_in * PX}
		elif p is Vector2:
			m["position"] = p + Vector2(dx_in, dy_in) * PX


func _unit_wounds(uid: String) -> int:
	var total := 0
	for m in GS.state.units[uid].models:
		if m.get("alive", true):
			total += int(m.get("current_wounds", m.get("wounds", 1)))
	return total


func _alive(uid: String) -> int:
	var n := 0
	for m in GS.state.units[uid].models:
		if m.get("alive", true):
			n += 1
	return n


## Every ranged weapon of `shooter` at `target` (all alive models).
func _assignments(shooter: String, target: String, board: Dictionary) -> Array:
	var uw: Dictionary = RE.get_unit_weapons(shooter, board)
	var per_weapon := {}
	for mid in uw:
		for wid in uw[mid]:
			if not per_weapon.has(wid):
				per_weapon[wid] = []
			per_weapon[wid].append(mid)
	var out: Array = []
	for wid in per_weapon:
		out.append({"weapon_id": wid, "target_unit_id": target, "model_ids": per_weapon[wid]})
	return out


func _first_block(dice: Array, ctx: String) -> Dictionary:
	for b in dice:
		if str(b.get("context", "")) == ctx:
			return b
	return {}


func _sum_successes(dice: Array, ctx: String) -> int:
	var n := 0
	for b in dice:
		if str(b.get("context", "")) == ctx:
			n += int(b.get("successes", 0))
	return n


func _offer_for(entries: Array, sid: String) -> Dictionary:
	for e in entries:
		if str(e.get("stratagem", {}).get("id", "")) == sid:
			return e
	return {}


func _run() -> void:
	SM = root.get_node("StratagemManager")
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	RM = load("res://scripts/rules/ReactiveMove11e.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	var ss = root.get_node_or_null("SettingsService")
	if ss:
		ss.set("auto_allocate_wounds", true)
	GameConstants.edition = 11

	print("\n=== test_ork_codex_shooting_reactive ===\n")
	_section_registry()
	_section_targeting_offers()
	_section_effects_ab()
	_section_reactive_dialog()
	_section_grab_it()
	_section_gun_crazy()
	_section_goaded()
	_section_network()


# ---------------------------------------------------------------------------
func _section_registry() -> void:
	print("\n-- A. registry --")
	var G = load("res://scripts/stratagems/ork_codex/OrkCodexShootingReactive.gd")
	for csv in G.IDS:
		_check("%s implemented" % csv, bool(G.IMPLEMENTED.get(csv, false)))
	var Codex = load("res://scripts/stratagems/ork_codex/OrkCodex11e.gd")
	_check("HULKING BRUTES +1CP variant costs 2", Codex.cp_cost_for({"csv_id": "hulking-brutes-bully-boyz", "cp_cost": 1, "effects": [{"type": "custom:ork11e"}]}, {"variant_id": "all_ranged"}) == 2)
	_check("defensive kinds", G.ai_kind({"csv_id": "grot-shields-runt-swarm"}) == "defensive" and G.ai_kind({"csv_id": "hulking-brutes-bully-boyz"}) == "defensive")


# ---------------------------------------------------------------------------
func _section_targeting_offers() -> void:
	print("\n-- B. enemy_targets_unit_shooting offers + gates --")
	_check("reactive fixture loads", _stage_fixture("ork11e_orks_reactive"))
	_check("P1 Custodes active", int(GS.state.meta.active_player) == 1)
	var phase = _shooting_phase()
	_check("Shooting phase, P1 active", GS.get_current_phase() == PHASE_SHOOTING and phase != null)

	# HULKING BRUTES (Bully Boyz)
	_set_detachment(2, "Bully Boyz")
	var hb := _sid(2, "hulking-brutes-bully-boyz")
	_check("HULKING BRUTES loaded for P2", hb != "")
	var avail: Array = SM.get_reactive_stratagems_for_shooting(2, ["U_NOBZ_A"], {"attacker_unit_id": "U_CUSTODIAN_GUARD_C"})
	var e = _offer_for(avail, hb)
	_check("HB offered when the enemy targets the Nobz", not e.is_empty() and e.eligible_units == ["U_NOBZ_A"], str(avail.map(func(x): return x.stratagem.get("name", "?"))))
	if not e.is_empty():
		var t0 = e.offer.targets[0]
		_check("HB offer carries the +1CP upgrade variant (2 CP)", t0.get("variants", []).size() == 1 and int(t0.variants[0].cp_cost) == 2, str(t0))
	_check("HB offered on MEGANOBZ too", not _offer_for(SM.get_reactive_stratagems_for_shooting(2, ["U_MEGANOBZ_A"], {"attacker_unit_id": "U_CUSTODIAN_GUARD_C"}), hb).is_empty())
	_check("HB not offered on BOYZ (not MEGANOBZ/NOBZ)", _offer_for(SM.get_reactive_stratagems_for_shooting(2, ["U_BOYZ_B"], {"attacker_unit_id": "U_CUSTODIAN_GUARD_C"}), hb).is_empty())
	var r = SM.can_use_stratagem(2, hb, "U_NOBZ_A")
	_check("HB outside its window -> 'Offered automatically when …'", not r.can_use and "Offered automatically" in str(r.reason), str(r))
	r = SM.can_use_stratagem(2, hb, "U_NOBZ_A", {"window_id": "enemy_has_shot", "attacker_unit_id": "U_CUSTODIAN_GUARD_C"})
	_check("HB in the wrong window -> refused", not r.can_use, str(r))
	r = SM.can_use_stratagem(2, hb, "U_MEGANOBZ_A", {"window_id": "enemy_targets_unit_shooting", "target_unit_ids": ["U_NOBZ_A"], "attacker_unit_id": "U_CUSTODIAN_GUARD_C"})
	_check("HB must target the targeted unit", not r.can_use, str(r))
	GS.state.players["2"]["cp"] = 1
	var cheap = _offer_for(SM.get_reactive_stratagems_for_shooting(2, ["U_NOBZ_A"], {"attacker_unit_id": "U_CUSTODIAN_GUARD_C"}), hb)
	_check("1 CP: base offered, unaffordable upgrade dropped", not cheap.is_empty() and cheap.offer.targets[0].get("variants", []).is_empty(), str(cheap.get("offer", {})))
	GS.state.players["2"]["cp"] = 6

	# SPEEDIEST FREEKS (Kult of Speed)
	_set_detachment(2, "Kult of Speed")
	var sf := _sid(2, "speediest-freeks-kult-of-speed")
	_check("SPEEDIEST FREEKS loaded", sf != "")
	_check("SF offered on Warbikers (SPEED FREEKS)", not _offer_for(SM.get_reactive_stratagems_for_shooting(2, ["U_WARBIKERS_A"], {"attacker_unit_id": "U_CUSTODIAN_GUARD_C"}), sf).is_empty())
	_check("SF not offered on Boyz", _offer_for(SM.get_reactive_stratagems_for_shooting(2, ["U_BOYZ_B"], {"attacker_unit_id": "U_CUSTODIAN_GUARD_C"}), sf).is_empty())
	# r5:F2 — the Trukk is a SPEED FREEKS datasheet in the codex (data patch).
	_check("SF offered on the Trukk (SPEED FREEKS per the codex)", not _offer_for(SM.get_reactive_stratagems_for_shooting(2, ["U_TRUKK_A"], {"attacker_unit_id": "U_CUSTODIAN_GUARD_C"}), sf).is_empty())

	# GROT SHIELDS (Runt Swarm)
	_set_detachment(2, "Runt Swarm")
	var gsid := _sid(2, "grot-shields-runt-swarm")
	_check("GROT SHIELDS loaded", gsid != "")
	var g1 = _offer_for(SM.get_reactive_stratagems_for_shooting(2, ["U_FLASH_GITZ_A"], {"attacker_unit_id": "U_CUSTODIAN_GUARD_C"}), gsid)
	_check("GS: Gretchin within 3\" of the targeted Flash Gitz offered", not g1.is_empty() and "U_GRETCHIN_C" in g1.eligible_units, str(g1.get("eligible_units", [])))
	var single_sec := false
	if not g1.is_empty():
		for t in g1.offer.targets:
			if t.has("secondary"):
				single_sec = true
	_check("GS: one shieldable unit -> no secondary pick", not single_sec)
	var g2 = _offer_for(SM.get_reactive_stratagems_for_shooting(2, ["U_FLASH_GITZ_A", "U_TANKBUSTAS_A"], {"attacker_unit_id": "U_CUSTODIAN_GUARD_C"}), gsid)
	var sec_opts: Array = []
	if not g2.is_empty():
		for t in g2.offer.targets:
			if str(t.unit_id) == "U_GRETCHIN_C" and t.has("secondary"):
				sec_opts = t.secondary.options.map(func(o): return str(o.id))
	_check("GS: two targeted Ork units within 3\" -> secondary unit pick", "U_FLASH_GITZ_A" in sec_opts and "U_TANKBUSTAS_A" in sec_opts, str(sec_opts))
	_check("GS: not offered when only GRETCHIN are targeted", _offer_for(SM.get_reactive_stratagems_for_shooting(2, ["U_GRETCHIN_C"], {"attacker_unit_id": "U_CUSTODIAN_GUARD_C"}), gsid).is_empty())
	_check("GS: not offered for a non-INFANTRY Ork unit", _offer_for(SM.get_reactive_stratagems_for_shooting(2, ["U_DEFF_DREAD_A"], {"attacker_unit_id": "U_CUSTODIAN_GUARD_C"}), gsid).is_empty())
	r = SM.can_use_stratagem(2, gsid, "U_GRETCHIN_C", {"window_id": "enemy_targets_unit_shooting", "target_unit_ids": ["U_FLASH_GITZ_A", "U_TANKBUSTAS_A"], "attacker_unit_id": "U_CUSTODIAN_GUARD_C", "secondary_id": "U_TANKBUSTAS_A"})
	_check("GS: with a secondary pick allowed", r.can_use, str(r))
	r = SM.can_use_stratagem(2, gsid, "U_GRETCHIN_C", {"window_id": "enemy_targets_unit_shooting", "target_unit_ids": ["U_FLASH_GITZ_A", "U_TANKBUSTAS_A"], "attacker_unit_id": "U_CUSTODIAN_GUARD_C", "secondary_id": "U_BOYZ_B"})
	_check("GS: a pick that is not a targeted unit within 3\" refused", not r.can_use, str(r))
	var Gr = load("res://scripts/stratagems/ork_codex/OrkCodexShootingReactive.gd")
	var no_pick_diffs: Array = Gr.apply(SM.get_stratagem(gsid), "U_GRETCHIN_C", {"target_unit_ids": ["U_FLASH_GITZ_A", "U_TANKBUSTAS_A"], "attacker_unit_id": "U_CUSTODIAN_GUARD_C"})
	var shielded := ""
	for d in no_pick_diffs:
		if str(d.path).ends_with(".flags.ork11e_grot_shields"):
			shielded = str(d.path).split(".")[1]
	_check("GS: no pick (reactive AI) -> the most valuable candidate is shielded", shielded == "U_TANKBUSTAS_A", shielded)
	# Wrong turn: the same offers in P2's own Shooting phase are refused.
	r = SM.can_use_stratagem(1, gsid, "U_GRETCHIN_C", {"window_id": "enemy_targets_unit_shooting", "target_unit_ids": ["U_FLASH_GITZ_A"], "attacker_unit_id": "U_CUSTODIAN_GUARD_C"})
	_check("GS: not usable by the active player", not r.can_use, str(r))


# ---------------------------------------------------------------------------
func _section_effects_ab() -> void:
	print("\n-- C. effects A/B (same seeds) --")
	_stage_fixture("ork11e_orks_reactive")
	_shooting_phase()
	var board: Dictionary = GS.create_snapshot()
	var shooter := "U_CUSTODIAN_GUARD_C"

	# HULKING BRUTES
	var a_nobz := _assignments(shooter, "U_NOBZ_A", board)
	_check("Custodian Guard C has ranged weapons", not a_nobz.is_empty())
	var base_res = RE.resolve_shoot_until_wounds({"actor_unit_id": shooter, "payload": {"assignments": [a_nobz[0]]}}, board.duplicate(true), RE.RNGService.new(4242))
	var b2: Dictionary = board.duplicate(true)
	b2.units.U_NOBZ_A.flags["ork11e_hulking_brutes"] = "all"
	var hb_res = RE.resolve_shoot_until_wounds({"actor_unit_id": shooter, "payload": {"assignments": [a_nobz[0]]}}, b2, RE.RNGService.new(4242))
	var w0 = _first_block(base_res.dice, "to_wound")
	var w1 = _first_block(hb_res.dice, "to_wound")
	_check("HB 'all': wound modifier -1 (interactive path)", int(w1.get("wound_modifier_net", 0)) == -1 and int(w0.get("wound_modifier_net", 0)) == 0, "%s / %s" % [w0.get("wound_modifier_net", "?"), w1.get("wound_modifier_net", "?")])
	_check("HB 'all': never more wounds than without (same seed)", int(w1.get("successes", 0)) <= int(w0.get("successes", 0)), "%d vs %d" % [int(w1.get("successes", 0)), int(w0.get("successes", 0))])
	var b3: Dictionary = board.duplicate(true)
	b3.units.U_NOBZ_A.flags["ork11e_hulking_brutes"] = "s_gt_t"
	var s_res = RE.resolve_shoot_until_wounds({"actor_unit_id": shooter, "payload": {"assignments": [a_nobz[0]]}}, b3, RE.RNGService.new(4242))
	_check("HB base: S4 vs T5 (S not > T) -> no penalty", int(_first_block(s_res.dice, "to_wound").get("wound_modifier_net", 9)) == 0)
	var b4: Dictionary = board.duplicate(true)
	b4.units.U_NOBZ_A.flags["ork11e_hulking_brutes"] = "s_gt_t"
	b4.units.U_NOBZ_A.meta.stats["toughness"] = 3
	var s2_res = RE.resolve_shoot_until_wounds({"actor_unit_id": shooter, "payload": {"assignments": [a_nobz[0]]}}, b4, RE.RNGService.new(4242))
	_check("HB base: S4 vs T3 (S > T) -> -1 to wound", int(_first_block(s2_res.dice, "to_wound").get("wound_modifier_net", 0)) == -1)
	_check("HB helper", RE.ork11e_ranged_wound_penalty({"flags": {"ork11e_hulking_brutes": "s_gt_t"}}, 6, 5) and not RE.ork11e_ranged_wound_penalty({"flags": {"ork11e_hulking_brutes": "s_gt_t"}}, 5, 5) and RE.ork11e_ranged_wound_penalty({"flags": {"ork11e_hulking_brutes": "all"}}, 2, 5))
	# auto path (resolve_shoot / _resolve_assignment)
	var auto0 = RE.resolve_shoot({"actor_unit_id": shooter, "payload": {"assignments": [a_nobz[0]]}}, board.duplicate(true), RE.RNGService.new(99))
	var b5: Dictionary = board.duplicate(true)
	b5.units.U_NOBZ_A.flags["ork11e_hulking_brutes"] = "all"
	var auto1 = RE.resolve_shoot({"actor_unit_id": shooter, "payload": {"assignments": [a_nobz[0]]}}, b5, RE.RNGService.new(99))
	_check("HB 'all' on the auto path: never more wounds (same seed)", _sum_successes(auto1.dice, "to_wound") <= _sum_successes(auto0.dice, "to_wound"),
		"%d vs %d" % [_sum_successes(auto1.dice, "to_wound"), _sum_successes(auto0.dice, "to_wound")])
	var ledger_names: Array = []
	for b in auto1.dice:
		for l in b.get("modifier_ledger", []):
			ledger_names.append(str(l.get("source", l.get("name", ""))))
	_check("HB named in the auto path's wound ledger", "Hulking Brutes" in str(ledger_names), str(ledger_names))

	# SPEEDIEST FREEKS — test geometry: the Warbikers placed in the open, in
	# range of Custodian Guard C and engaged with nobody.
	var wb_models: Array = board.units.U_WARBIKERS_A.models
	for i in range(wb_models.size()):
		wb_models[i]["position"] = {"x": 42.0 * PX, "y": (34.0 + 3.2 * i) * PX}
	var a_wb := _assignments(shooter, "U_WARBIKERS_A", board)
	var sf0 = RE.resolve_shoot_until_wounds({"actor_unit_id": shooter, "payload": {"assignments": [a_wb[0]]}}, board.duplicate(true), RE.RNGService.new(777))
	var bsf: Dictionary = board.duplicate(true)
	bsf.units.U_WARBIKERS_A.flags["ork11e_speediest_freeks"] = true
	var sf1 = RE.resolve_shoot_until_wounds({"actor_unit_id": shooter, "payload": {"assignments": [a_wb[0]]}}, bsf, RE.RNGService.new(777))
	var h0 = _first_block(sf0.dice, "to_hit")
	var h1 = _first_block(sf1.dice, "to_hit")
	var raw: Array = h1.get("rolls_raw", [])
	var ge4 := 0
	var ge2 := 0
	for v in raw:
		if int(v) >= 4:
			ge4 += 1
		if int(v) >= 2:
			ge2 += 1
	_check("SF: same dice both runs", h0.get("rolls_raw", []) == raw)
	_check("SF: hits = unmodified 4+ only", int(h1.get("successes", -1)) <= ge4, "%d hits, %d rolls >=4, raw %s" % [int(h1.get("successes", -1)), ge4, str(raw)])
	_check("SF: without the flag 2+ hits (BS 2+)", int(h0.get("successes", -1)) == ge2, "%d vs %d" % [int(h0.get("successes", -1)), ge2])
	var staged = RE.resolve_shoot_hits({"actor_unit_id": shooter, "payload": {"assignments": [a_wb[0]]}}, bsf.duplicate(true), RE.RNGService.new(777))
	_check("SF: fail band 3 carried in the staged hit context (Command Re-roll path)", int(staged.get("hit_context", {}).get("hit_fail_band", 0)) == 3, str(staged.get("hit_context", {}).get("hit_fail_band", "?")))
	var sfa = RE.resolve_shoot({"actor_unit_id": shooter, "payload": {"assignments": [a_wb[0]]}}, bsf.duplicate(true), RE.RNGService.new(31))
	var ha = _first_block(sfa.dice, "to_hit")
	var ge4a := 0
	for v in ha.get("rolls_raw", []):
		if int(v) >= 4:
			ge4a += 1
	_check("SF on the auto path: hits = unmodified 4+ only", int(ha.get("successes", -1)) <= ge4a, str(ha.get("rolls_raw", [])))
	_check("SF helper band", RE.ork11e_ranged_hit_fail_band({"flags": {"ork11e_speediest_freeks": true}}, 1) == 3 and RE.ork11e_ranged_hit_fail_band({"flags": {"ork11e_speediest_freeks": true}}, 5) == 5 and RE.ork11e_ranged_hit_fail_band({}, 1) == 1)

	# GROT SHIELDS
	var a_fg := _assignments(shooter, "U_FLASH_GITZ_A", board)
	var gs0 = RE.resolve_shoot_until_wounds({"actor_unit_id": shooter, "payload": {"assignments": [a_fg[0]]}}, board.duplicate(true), RE.RNGService.new(555))
	var bgs: Dictionary = board.duplicate(true)
	bgs.units.U_FLASH_GITZ_A.flags["ork11e_grot_shields"] = {"gretchin_unit_id": "U_GRETCHIN_C", "attacker_unit_ids": [shooter], "player": 2}
	var gret_before := 0
	for m in bgs.units.U_GRETCHIN_C.models:
		if m.get("alive", true):
			gret_before += 1
	var gs1 = RE.resolve_shoot_until_wounds({"actor_unit_id": shooter, "payload": {"assignments": [a_fg[0]]}}, bgs, RE.RNGService.new(555))
	var hits := int(_first_block(gs1.dice, "to_hit").get("successes", 0))
	var gsb = _first_block(gs1.dice, "grot_shields")
	_check("GS: hits scored (precondition)", hits > 0, str(hits))
	_check("GS: every hit intercepted while Gretchin remain", int(gsb.get("intercepted", -1)) == mini(hits, gret_before), "%s / hits %d" % [str(gsb), hits])
	_check("GS: no wound roll left for the shielded unit", int(_first_block(gs1.dice, "to_wound").get("successes", 0)) == 0 and gs1.get("save_data_list", []).is_empty())
	_check("GS: without the flag the hits roll to wound", not _first_block(gs0.dice, "to_wound").get("rolls_raw", []).is_empty())
	var gdiffs: Array = gs1.get("one_shot_diffs", [])
	var gdead := 0
	for d in gdiffs:
		if str(d.path).begins_with("units.U_GRETCHIN_C.") and str(d.path).ends_with(".alive") and d.value == false:
			gdead += 1
	_check("GS: Gretchin mortal-wound diffs ride out (one per intercepted hit, W1 models)", gdead == int(gsb.get("intercepted", -2)), "%d dead, %d diffs" % [gdead, gdiffs.size()])
	# Gretchin with a single model left: one interception, the rest proceed.
	var bone: Dictionary = board.duplicate(true)
	bone.units.U_FLASH_GITZ_A.flags["ork11e_grot_shields"] = {"gretchin_unit_id": "U_GRETCHIN_C", "attacker_unit_ids": [shooter], "player": 2}
	var models: Array = bone.units.U_GRETCHIN_C.models
	for i in range(1, models.size()):
		models[i]["alive"] = false
	var gs2 = RE.resolve_shoot_until_wounds({"actor_unit_id": shooter, "payload": {"assignments": [a_fg[0]]}}, bone, RE.RNGService.new(555))
	var gsb2 = _first_block(gs2.dice, "grot_shields")
	_check("GS: last Gretchin absorbs one hit, the others proceed", int(gsb2.get("intercepted", -1)) == 1 and _first_block(gs2.dice, "to_wound").get("rolls_raw", []).size() >= hits - 1, str(gsb2))
	# Another attacker is not intercepted.
	var bother: Dictionary = board.duplicate(true)
	bother.units.U_FLASH_GITZ_A.flags["ork11e_grot_shields"] = {"gretchin_unit_id": "U_GRETCHIN_C", "attacker_unit_ids": ["U_CUSTODIAN_GUARD_D"], "player": 2}
	var gs3 = RE.resolve_shoot_until_wounds({"actor_unit_id": shooter, "payload": {"assignments": [a_fg[0]]}}, bother, RE.RNGService.new(555))
	_check("GS: only 'that enemy unit's' attacks are intercepted", _first_block(gs3.dice, "grot_shields").is_empty())
	# Auto path
	var bga: Dictionary = board.duplicate(true)
	bga.units.U_FLASH_GITZ_A.flags["ork11e_grot_shields"] = {"gretchin_unit_id": "U_GRETCHIN_C", "attacker_unit_ids": [shooter], "player": 2}
	var gsa = RE.resolve_shoot({"actor_unit_id": shooter, "payload": {"assignments": [a_fg[0]]}}, bga, RE.RNGService.new(555))
	var adead := 0
	var fg_hurt := false
	for d in gsa.diffs:
		if str(d.path).begins_with("units.U_GRETCHIN_C.") and str(d.path).ends_with(".alive") and d.value == false:
			adead += 1
		if str(d.path).begins_with("units.U_FLASH_GITZ_A."):
			fg_hurt = true
	_check("GS on the auto path: Gretchin take the mortal wounds, Flash Gitz untouched", adead > 0 and not fg_hurt, "%d dead, fg_hurt %s" % [adead, fg_hurt])


# ---------------------------------------------------------------------------
func _section_reactive_dialog() -> void:
	print("\n-- D. reactive dialog: several stratagems per targeting, don't offer again, expiry --")
	_stage_fixture("ork11e_orks_reactive")
	_set_detachment(2, "Runt Swarm")
	var phase = _shooting_phase()
	var gsid := _sid(2, "grot-shields-runt-swarm")
	var shooter := "U_CUSTODIAN_GUARD_C"
	phase.active_shooter_id = shooter
	phase.confirmed_assignments = [{"target_unit_id": "U_KOMMANDOS_A", "weapon_id": "x", "model_ids": []},
		{"target_unit_id": "U_FLASH_GITZ_A", "weapon_id": "x", "model_ids": []}]
	var chk = phase._check_reactive_stratagems()
	var names: Array = chk.get("available_stratagems", []).map(func(x): return str(x.stratagem.get("id", "")))
	_check("core SMOKESCREEN and codex GROT SHIELDS both offered", "smokescreen_11e" in names and gsid in names, str(names))
	phase.awaiting_reactive_stratagem = true
	phase.resolution_state = {"phase": "awaiting_reactive_stratagem", "assignments": phase.confirmed_assignments}
	var cp0 := _cp(2)
	var r1 = phase.execute_action({"type": "USE_REACTIVE_STRATAGEM", "player": 2, "stratagem_id": "smokescreen_11e", "target_unit_id": "U_KOMMANDOS_A"})
	_check("SMOKESCREEN used", r1.get("success", false) and _cp(2) == cp0 - 1, str(r1.get("error", "")))
	_check("dialog re-opens: GROT SHIELDS still usable", r1.get("reactive_stratagem_opportunity", false) and phase.awaiting_reactive_stratagem, str(r1.keys()))
	var again_names: Array = r1.get("available_stratagems", []).map(func(x): return str(x.stratagem.get("id", "")))
	_check("re-opened list: SMOKESCREEN gone (once per phase), GROT SHIELDS kept", not "smokescreen_11e" in again_names and gsid in again_names, str(again_names))
	var r2 = phase.execute_action({"type": "USE_REACTIVE_STRATAGEM", "player": 2, "stratagem_id": gsid, "target_unit_id": "U_GRETCHIN_C"})
	_check("GROT SHIELDS used second (CP -1 more)", r2.get("success", false) and _cp(2) == cp0 - 2, str(r2.get("error", "")))
	_check("nothing left: the attack resumes", not phase.awaiting_reactive_stratagem and not r2.get("reactive_stratagem_opportunity", false))
	var flag = GS.state.units.U_FLASH_GITZ_A.flags.get("ork11e_grot_shields", null)
	_check("shield flag on the Flash Gitz names the Gretchin + attacker", typeof(flag) == TYPE_DICTIONARY and flag.gretchin_unit_id == "U_GRETCHIN_C" and shooter in flag.attacker_unit_ids, str(flag))
	_check("Gretchin marked as the shield source", str(GS.state.units.U_GRETCHIN_C.flags.get("ork11e_grot_shields_source", "")) == "U_FLASH_GITZ_A")
	var r3 = SM.can_use_stratagem(2, gsid, "U_GRETCHIN_D", {"window_id": "enemy_targets_unit_shooting", "target_unit_ids": ["U_TANKBUSTAS_A"], "attacker_unit_id": "U_CUSTODIAN_GUARD_D"})
	_check("GROT SHIELDS once per phase", not r3.can_use and "once per phase" in str(r3.reason), str(r3))
	# Expiry at the end of the phase
	SM.on_phase_end(PHASE_SHOOTING)
	_check("GROT SHIELDS flags cleared at the end of the phase", not GS.state.units.U_FLASH_GITZ_A.flags.has("ork11e_grot_shields") and not GS.state.units.U_GRETCHIN_C.flags.has("ork11e_grot_shields_source"))

	# Variant via USE_REACTIVE_STRATAGEM context (HULKING BRUTES +1CP)
	_stage_fixture("ork11e_orks_reactive")
	_set_detachment(2, "Bully Boyz")
	phase = _shooting_phase()
	var hb := _sid(2, "hulking-brutes-bully-boyz")
	phase.active_shooter_id = shooter
	phase.confirmed_assignments = [{"target_unit_id": "U_NOBZ_A", "weapon_id": "x", "model_ids": []}]
	phase.awaiting_reactive_stratagem = true
	cp0 = _cp(2)
	var rv = phase.execute_action({"type": "USE_REACTIVE_STRATAGEM", "player": 2, "stratagem_id": hb, "target_unit_id": "U_NOBZ_A", "context": {"variant_id": "all_ranged"}})
	_check("HB upgrade used through the reactive action: 2 CP", rv.get("success", false) and _cp(2) == cp0 - 2, "%s cp %d->%d" % [str(rv.get("error", "")), cp0, _cp(2)])
	_check("HB upgrade flag = all", str(GS.state.units.U_NOBZ_A.flags.get("ork11e_hulking_brutes", "")) == "all")
	SM.on_phase_end(PHASE_SHOOTING)
	_check("HB flag cleared at the end of the phase", not GS.state.units.U_NOBZ_A.flags.has("ork11e_hulking_brutes"))

	# Don't offer again
	_stage_fixture("ork11e_orks_reactive")
	_set_detachment(2, "Kult of Speed")
	phase = _shooting_phase()
	phase.active_shooter_id = shooter
	phase.confirmed_assignments = [{"target_unit_id": "U_WARBIKERS_A", "weapon_id": "x", "model_ids": []}]
	_check("SPEEDIEST FREEKS offered", phase._check_reactive_stratagems().get("has_opportunities", false))
	phase.awaiting_reactive_stratagem = true
	var dd = phase.execute_action({"type": "DECLINE_REACTIVE_STRATAGEM", "player": 2, "dont_offer_again": true})
	_check("decline with don't-offer-again succeeds", dd.get("success", false), str(dd.get("error", "")))
	_check("defender prompt suppressed for the rest of the phase", not phase._check_reactive_stratagems().get("has_opportunities", true))
	var p2 = _shooting_phase()
	p2.active_shooter_id = shooter
	p2.confirmed_assignments = [{"target_unit_id": "U_WARBIKERS_A", "weapon_id": "x", "model_ids": []}]
	_check("suppression resets with the next phase instance", p2._check_reactive_stratagems().get("has_opportunities", false))


# ---------------------------------------------------------------------------
func _shoot(phase, shooter: String, target: String) -> Dictionary:
	var board: Dictionary = GS.create_snapshot()
	var elig: Dictionary = RE.get_eligible_targets(shooter, board).get(target, {})
	var weapons: Array = elig.get("weapons_in_range", [])
	var assignments: Array = []
	for a in _assignments(shooter, target, board):
		if a.weapon_id in weapons:
			assignments.append(a)
	if assignments.is_empty():
		print("  [diag] %s cannot target %s — eligible: %s; weapons: %s" % [shooter, target,
			str(RE.get_eligible_targets(shooter, board).keys()), str(RE.get_unit_weapons(shooter, board))])
	return phase.execute_action({"type": "SHOOT", "actor_unit_id": shooter, "player": int(GS.state.units[shooter].owner),
		"payload": {"assignments": assignments}})


func _section_grab_it() -> void:
	print("\n-- E. unit_has_shot / GRAB IT --")
	_check("active fixture loads", _stage_fixture("ork11e_orks_active"))
	_set_detachment(1, "Wreckas")
	var gi := _sid(1, "grab-it-wreckas")
	_check("GRAB IT loaded for P1", gi != "")
	var phase = _shooting_phase()
	RE.set_test_seed(2026)
	_check("Tankbustas not within range of an objective before", not RM.group_within_objective_range(GS.state, "U_TANKBUSTAS_A"))
	var G = load("res://scripts/stratagems/ork_codex/OrkCodexShootingReactive.gd")
	_check("an objective is within a 6\" move of the Tankbustas", G.objective_range_gap_inches("U_TANKBUSTAS_A") <= 6.0, str(G.objective_range_gap_inches("U_TANKBUSTAS_A")))
	var r = SM.can_use_stratagem(1, gi, "U_TANKBUSTAS_A", {"window_id": "unit_has_shot", "unit_id": "U_TANKBUSTAS_A"})
	_check("GRAB IT usable in unit_has_shot for the shooter", r.can_use, str(r))
	r = SM.can_use_stratagem(1, gi, "U_BOYZ_B", {"window_id": "unit_has_shot", "unit_id": "U_BOYZ_B"})
	_check("GRAB IT refused for a non-BREAKA BOYZ/FLASH GITZ/TANKBUSTAS unit", not r.can_use, str(r))
	r = SM.can_use_stratagem(1, gi, "U_FLASH_GITZ_A", {"window_id": "unit_has_shot", "unit_id": "U_TANKBUSTAS_A"})
	_check("GRAB IT must target the unit that has shot", not r.can_use, str(r))
	r = SM.can_use_stratagem(1, gi, "U_TANKBUSTAS_A", {"window_id": "unit_selected_to_shoot", "unit_id": "U_TANKBUSTAS_A"})
	_check("GRAB IT not in another window", not r.can_use, str(r))

	_window_events.clear()
	var cp0 := _cp(1)
	var res = _shoot(phase, "U_TANKBUSTAS_A", "U_CUSTODIAN_GUARD_C")
	_check("Tankbustas SHOOT succeeds", res.get("success", false), str(res.get("error", "")))
	_check("unit_has_shot window opened for P1 after the shooting resolved", phase.has_pending_stratagem_window() and str(phase.get_pending_stratagem_window().get("window_id", "")) == "unit_has_shot", str(phase.get_pending_stratagem_window()))
	var offered := false
	for ev in _window_events:
		if ev.window_id == "unit_has_shot" and ev.player == 1:
			for o in ev.offers:
				if str(o.stratagem_id) == gi and str(o.targets[0].unit_id) == "U_TANKBUSTAS_A":
					offered = true
	_check("GRAB IT offered on the Tankbustas", offered, str(_window_events))
	_check("Tankbustas marked as having shot", bool(GS.state.units.U_TANKBUSTAS_A.flags.get("has_shot", false)))
	var blocked = phase.execute_action({"type": "END_SHOOTING", "player": 1})
	_check("other actions refused while the window waits", not blocked.get("success", true))

	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_has_shot", "stratagem_id": gi, "target_unit_id": "U_TANKBUSTAS_A"})
	_check("USE GRAB IT succeeds", use.get("success", false), str(use.get("error", "")))
	_check("CP -1", _cp(1) == cp0 - 1, "%d -> %d" % [cp0, _cp(1)])
	_check("charge lock flag set", bool(GS.state.units.U_TANKBUSTAS_A.flags.get("ork11e_grab_it_no_charge", false)))
	_check("human follow-up pending (reactive move)", not phase._ork11e_followup.is_empty() and phase._ork11e_followup.kind == "normal" and float(phase._ork11e_followup.max_inches) == 6.0)
	_check("AI idles: pending decider = P1", phase.get_pending_stratagem_window_decider() == 1)
	var blocked2 = phase.execute_action({"type": "SELECT_SHOOTER", "actor_unit_id": "U_FLASH_GITZ_A", "player": 1})
	_check("other actions refused during the move", not blocked2.get("success", true) and "finish the normal move" in str(blocked2.get("error", "")), str(blocked2.get("error", "")))
	var origin: Dictionary = phase._ork11e_followup.origin.duplicate()
	# Over-long drag is clamped to 6"
	var st = phase.execute_action({"type": "ORK11E_REACTIVE_MOVE_STAGE", "player": 1, "payload": {"translation": {"x": 0.0, "y": 20.0 * PX}}})
	_check("stage succeeds and is clamped to 6\"", st.get("success", false) and absf(float(st.get("ork11e_reactive_move", {}).get("moved_inches", 0)) - 6.0) < 0.05, str(st.get("ork11e_reactive_move", {}).get("moved_inches", "?")))
	# Away from every objective: refused
	phase.execute_action({"type": "ORK11E_REACTIVE_MOVE_STAGE", "player": 1, "payload": {"translation": {"x": 0.0, "y": 0.5 * PX}}})
	var bad = phase.execute_action({"type": "ORK11E_REACTIVE_MOVE_CONFIRM", "player": 1})
	_check("confirm refused when the move does not end within range of an objective", not bad.get("success", true) and "objective" in str(bad.get("error", "")), str(bad.get("error", "")))
	var wrong_player = phase.execute_action({"type": "ORK11E_REACTIVE_MOVE_AUTO", "player": 2})
	_check("the other player cannot make the move", not wrong_player.get("success", true))
	var auto = phase.execute_action({"type": "ORK11E_REACTIVE_MOVE_AUTO", "player": 1})
	_check("auto-move succeeds", auto.get("success", false), str(auto.get("error", "")))
	_check("auto-move info: legal", bool(auto.get("ork11e_reactive_move", {}).get("valid", false)), str(auto.get("ork11e_reactive_move", {}).get("violations", [])))
	var conf = phase.execute_action({"type": "ORK11E_REACTIVE_MOVE_CONFIRM", "player": 1})
	_check("confirm succeeds", conf.get("success", false), str(conf.get("error", "")))
	_check("follow-up finished", phase._ork11e_followup.is_empty() and not phase._window_followup_pending)
	_check("Tankbustas now within range of an objective", RM.group_within_objective_range(GS.state, "U_TANKBUSTAS_A"))
	var max_moved := 0.0
	for key in origin:
		var parts = str(key).rsplit(":", true, 1)
		var p = GS.state.units[parts[0]].models[int(parts[1])].position
		max_moved = maxf(max_moved, Vector2(float(p.x), float(p.y)).distance_to(origin[key]) / PX)
	_check("no model moved more than 6\"", max_moved <= 6.05 and max_moved > 0.0, str(max_moved))
	_check("Tankbustas unengaged after the move", not RE.is_unit_engaged("U_TANKBUSTAS_A", GS.state))
	_check("no window left pending (P2 Custodes: no enemy_has_shot offers)", not phase.has_pending_stratagem_window())
	_check("charge lock: RulesEngine.eligible_to_charge false", not RE.eligible_to_charge("U_TANKBUSTAS_A", GS.state))
	var cm = MoveTypes.get_type("charge").eligible("U_TANKBUSTAS_A", GS.state)
	_check("charge lock: 11e charge template refuses (GRAB IT)", not cm.eligible and "GRAB IT" in str(cm.reasons), str(cm))
	SM.on_phase_end(PHASE_SHOOTING)
	_check("charge lock survives the end of the Shooting phase", bool(GS.state.units.U_TANKBUSTAS_A.flags.get("ork11e_grab_it_no_charge", false)))
	SM.on_turn_start(2)
	_check("charge lock cleared at the end of the turn", not GS.state.units.U_TANKBUSTAS_A.flags.has("ork11e_grab_it_no_charge"))

	# AI decider: synchronous use + auto-move (Flash Gitz)
	_stage_fixture("ork11e_orks_active")
	_set_detachment(1, "Wreckas")
	gi = _sid(1, "grab-it-wreckas")
	phase = _shooting_phase()
	var ai = root.get_node("AIPlayer")
	ai.enabled = true
	ai.ai_players = {1: true, 2: false}
	cp0 = _cp(1)
	var ares = _shoot(phase, "U_FLASH_GITZ_A", "U_CUSTODIAN_GUARD_C")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_check("AI SHOOT succeeds", ares.get("success", false), str(ares.get("error", "")))
	_check("AI window resolved synchronously (no pause, no follow-up)", not phase.has_pending_stratagem_window() and phase._ork11e_followup.is_empty())
	_check("AI used GRAB IT (CP -1)", _cp(1) == cp0 - 1 and bool(GS.state.units.U_FLASH_GITZ_A.flags.get("ork11e_grab_it_no_charge", false)), "%d -> %d" % [cp0, _cp(1)])
	_check("AI auto-moved the Flash Gitz within range of an objective", RM.group_within_objective_range(GS.state, "U_FLASH_GITZ_A"))
	var has_pos_diff := false
	for d in ares.get("changes", []):
		if str(d.get("path", "")).begins_with("units.U_FLASH_GITZ_A.models.") and str(d.path).ends_with(".position"):
			has_pos_diff = true
	_check("the AI move's position diffs are in the action's changes (replay/network)", has_pos_diff)
	RE.set_test_seed(-1)


# ---------------------------------------------------------------------------
func _section_gun_crazy() -> void:
	print("\n-- F. enemy_has_shot / GUN-CRAZY SHOW-OFFS --")
	_stage_fixture("ork11e_orks_reactive")
	_set_detachment(2, "Wreckas")
	var gc := _sid(2, "gun-crazy-show-offs-wreckas")
	_check("GUN-CRAZY SHOW-OFFS loaded for P2", gc != "")
	var phase = _shooting_phase()
	RE.set_test_seed(7)
	var r = SM.can_use_stratagem(2, gc, "U_TANKBUSTAS_A", {"window_id": "enemy_has_shot", "attacker_unit_id": "U_CUSTODIAN_GUARD_C", "hit_unit_ids": ["U_FLASH_GITZ_A"]})
	_check("refused for a unit that was not hit", not r.can_use, str(r))
	r = SM.can_use_stratagem(2, gc, "U_BOYZ_B", {"window_id": "enemy_has_shot", "attacker_unit_id": "U_CUSTODIAN_GUARD_C", "hit_unit_ids": ["U_BOYZ_B"]})
	_check("refused for a non-FLASH GITZ/TANKBUSTAS unit", not r.can_use, str(r))
	r = SM.can_use_stratagem(2, gc, "U_TANKBUSTAS_A", {"window_id": "enemy_has_shot", "attacker_unit_id": "U_CUSTODIAN_GUARD_C", "hit_unit_ids": ["U_TANKBUSTAS_A"]})
	_check("allowed for a hit Tankbustas unit that can target the attacker", r.can_use, str(r))
	r = SM.can_use_stratagem(1, gc, "U_TANKBUSTAS_A", {"window_id": "enemy_has_shot", "attacker_unit_id": "U_CUSTODIAN_GUARD_C", "hit_unit_ids": ["U_TANKBUSTAS_A"]})
	_check("not for the active player", not r.can_use, str(r))

	_window_events.clear()
	var cp0 := _cp(2)
	var cg_wounds := _unit_wounds("U_CUSTODIAN_GUARD_C")
	var res = _shoot(phase, "U_CUSTODIAN_GUARD_C", "U_TANKBUSTAS_A")
	_check("Custodes SHOOT at the Tankbustas succeeds", res.get("success", false), str(res.get("error", "")))
	var w = phase.get_pending_stratagem_window()
	_check("enemy_has_shot window pending for P2", str(w.get("window_id", "")) == "enemy_has_shot" and int(w.get("player", 0)) == 2, str(w))
	_check("ctx: attacker + Tankbustas hit", str(w.get("ctx", {}).get("attacker_unit_id", "")) == "U_CUSTODIAN_GUARD_C" and "U_TANKBUSTAS_A" in w.get("ctx", {}).get("hit_unit_ids", []), str(w.get("ctx", {})))
	var targets: Array = []
	for o in w.get("offers", []):
		if str(o.stratagem_id) == gc:
			targets = o.targets.map(func(t): return str(t.unit_id))
	_check("GUN-CRAZY offered only on the hit Tankbustas", targets == ["U_TANKBUSTAS_A"], str(targets))
	var dice_before: int = phase.dice_log.size()
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 2, "window_id": "enemy_has_shot", "stratagem_id": gc, "target_unit_id": "U_TANKBUSTAS_A"})
	_check("USE GUN-CRAZY SHOW-OFFS succeeds", use.get("success", false), str(use.get("error", "")))
	_check("CP -1", _cp(2) == cp0 - 1)
	var to_attacker := 0
	for i in range(dice_before, phase.dice_log.size()):
		if str(phase.dice_log[i].get("target_unit_id", "")) == "U_CUSTODIAN_GUARD_C":
			to_attacker += 1
	_check("Tankbustas shot the attacker (dice against Custodian Guard C)", to_attacker > 0, str(to_attacker))
	var other_targets := 0
	for i in range(dice_before, phase.dice_log.size()):
		var tid := str(phase.dice_log[i].get("target_unit_id", ""))
		if tid != "" and tid != "U_CUSTODIAN_GUARD_C":
			other_targets += 1
	_check("…and only that enemy unit", other_targets == 0)
	var dmg_in_changes := false
	for d in use.get("changes", []):
		if str(d.get("path", "")).begins_with("units.U_CUSTODIAN_GUARD_C.models."):
			dmg_in_changes = true
	_check("damage (if any) carried in the action's changes", dmg_in_changes == (_unit_wounds("U_CUSTODIAN_GUARD_C") < cg_wounds), "dmg diff %s, wounds %d -> %d" % [dmg_in_changes, cg_wounds, _unit_wounds("U_CUSTODIAN_GUARD_C")])
	_check("window closed, phase free", not phase.has_pending_stratagem_window() and phase._ork11e_followup.is_empty())
	_check("Tankbustas NOT marked has_shot for their own next phase", not bool(GS.state.units.U_TANKBUSTAS_A.flags.get("has_shot", false)))
	# AI decider (P2 AI): synchronous auto shoot.
	_stage_fixture("ork11e_orks_reactive")
	_set_detachment(2, "Wreckas")
	gc = _sid(2, "gun-crazy-show-offs-wreckas")
	phase = _shooting_phase()
	var ai = root.get_node("AIPlayer")
	ai.enabled = true
	ai.ai_players = {1: false, 2: true}
	cp0 = _cp(2)
	var ares = _shoot(phase, "U_CUSTODIAN_GUARD_C", "U_TANKBUSTAS_A")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_check("AI defender: no pause", ares.get("success", false) and not phase.has_pending_stratagem_window())
	_check("AI defender used GUN-CRAZY SHOW-OFFS", _cp(2) == cp0 - 1, "%d -> %d" % [cp0, _cp(2)])
	RE.set_test_seed(-1)


# ---------------------------------------------------------------------------
func _section_goaded() -> void:
	print("\n-- G. enemy_has_shot / GOADED INTO ACTION --")
	_stage_fixture("ork11e_orks_reactive")
	_set_detachment(2, "Da Big Hunt")
	var ga := _sid(2, "goaded-into-action-da-big-hunt")
	_check("GOADED INTO ACTION loaded for P2", ga != "")
	# Free the Beast Snagga Boyz from the Allarus (test geometry): Boyz back 3".
	_move_unit("U_BEAST_SNAGGA_BOYZ_A", 0.0, 3.0)
	var phase = _shooting_phase()
	_check("Beast Snagga Boyz unengaged now", not RE.is_unit_engaged("U_BEAST_SNAGGA_BOYZ_A", GS.state))
	var r = SM.can_use_stratagem(2, ga, "U_BEAST_SNAGGA_BOYZ_A", {"window_id": "enemy_has_shot", "attacker_unit_id": "U_ALLARUS_CUSTODIANS_A", "wounded_unit_ids": []})
	_check("refused when the unit lost no wound", not r.can_use, str(r))
	r = SM.can_use_stratagem(2, ga, "U_BOYZ_B", {"window_id": "enemy_has_shot", "attacker_unit_id": "U_ALLARUS_CUSTODIANS_A", "wounded_unit_ids": ["U_BOYZ_B"]})
	_check("refused for a non-BEAST SNAGGA unit", not r.can_use, str(r))
	# Seed 3: the Allarus volley costs the Boyz 6 wounds and leaves the Nob and
	# 3 Boyz in coherency. (Since #916, computer-rolled saves go through the 11e
	# grouped allocation; with the casualty preference's group order the
	# survivors stay coherent here — the precondition below pins that, since a
	# unit out of coherency cannot make the surge.)
	RE.set_test_seed(3)
	var w_before := _unit_wounds("U_BEAST_SNAGGA_BOYZ_A")
	_window_events.clear()
	var res = _shoot(phase, "U_ALLARUS_CUSTODIANS_A", "U_BEAST_SNAGGA_BOYZ_A")
	_check("Allarus SHOOT at the Beast Snagga Boyz succeeds", res.get("success", false), str(res.get("error", "")))
	var lost := _unit_wounds("U_BEAST_SNAGGA_BOYZ_A") < w_before
	_check("Beast Snagga Boyz lost a wound (seeded precondition)", lost, "%d -> %d" % [w_before, _unit_wounds("U_BEAST_SNAGGA_BOYZ_A")])
	_check("…and the survivors are still in coherency (seeded precondition)", AttackSequence.check_unit_coherency(GS.state.units.U_BEAST_SNAGGA_BOYZ_A).coherent)
	var w = phase.get_pending_stratagem_window()
	_check("enemy_has_shot pending for P2 with the wounded unit in ctx", str(w.get("window_id", "")) == "enemy_has_shot" and "U_BEAST_SNAGGA_BOYZ_A" in w.get("ctx", {}).get("wounded_unit_ids", []), str(w.get("ctx", {})))
	GS.state.units.U_BEAST_SNAGGA_BOYZ_A.flags["ork11e_riled_up"] = true
	var cp0 := _cp(2)
	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 2, "window_id": "enemy_has_shot", "stratagem_id": ga, "target_unit_id": "U_BEAST_SNAGGA_BOYZ_A"})
	_check("USE GOADED succeeds", use.get("success", false), str(use.get("error", "")))
	_check("CP -1", _cp(2) == cp0 - 1)
	var fu: Dictionary = phase._ork11e_followup
	_check("surge follow-up pending for P2 (human)", not fu.is_empty() and fu.kind == "surge" and int(fu.player) == 2, str(fu.keys()))
	_check("D6 rolled (1-6) = max distance", int(fu.get("roll", 0)) >= 1 and int(fu.get("roll", 0)) <= 6 and float(fu.max_inches) == float(fu.roll))
	_check("surge target = the closest enemy unit", str(fu.get("surge_target", "")) != "")
	var info = phase.ork11e_reactive_move_info()
	_check("riled up: the D6 can be re-rolled once", bool(info.get("reroll_available", false)))
	var rr = phase.execute_action({"type": "ORK11E_REACTIVE_MOVE_REROLL", "player": 2})
	_check("re-roll succeeds", rr.get("success", false), str(rr.get("error", "")))
	var rr2 = phase.execute_action({"type": "ORK11E_REACTIVE_MOVE_REROLL", "player": 2})
	_check("…only once", not rr2.get("success", true))
	var origin: Dictionary = fu.origin.duplicate()
	var target := str(fu.surge_target)
	var d_before := INF
	for key in origin:
		var parts = str(key).rsplit(":", true, 1)
		d_before = minf(d_before, RM.model_to_unit_inches(GS.state.units[parts[0]].models[int(parts[1])], target, GS.state))
	var coh0 = AttackSequence.check_unit_coherency(GS.state.units.U_BEAST_SNAGGA_BOYZ_A)
	print("  [diag] BSB alive %d, coherent %s offenders %s, roll %d, target %s, origin %s" % [_alive("U_BEAST_SNAGGA_BOYZ_A"), str(coh0.coherent), str(coh0.offenders), int(fu.roll), target, str(origin)])
	var nothing = phase.execute_action({"type": "ORK11E_REACTIVE_MOVE_CONFIRM", "player": 2})
	_check("confirming without moving is refused (must end as close as possible)", not nothing.get("success", true) or float(fu.max_inches) < 0.5, str(nothing.get("error", "")))
	var auto = phase.execute_action({"type": "ORK11E_REACTIVE_MOVE_AUTO", "player": 2})
	_check("auto surge placement succeeds", auto.get("success", false), str(auto.get("error", "")))
	var conf = phase.execute_action({"type": "ORK11E_REACTIVE_MOVE_CONFIRM", "player": 2})
	_check("confirm succeeds", conf.get("success", false), str(conf.get("error", "")))
	var d_after := INF
	var max_moved := 0.0
	for key in origin:
		var parts = str(key).rsplit(":", true, 1)
		var m = GS.state.units[parts[0]].models[int(parts[1])]
		d_after = minf(d_after, RM.model_to_unit_inches(m, target, GS.state))
		max_moved = maxf(max_moved, Vector2(float(m.position.x), float(m.position.y)).distance_to(origin[key]) / PX)
	_check("the unit ended closer to the surge target", d_after < d_before, "%.2f -> %.2f" % [d_before, d_after])
	_check("no model moved more than the D6", max_moved <= float(fu.max_inches) + 0.05, "%.2f vs %.0f" % [max_moved, float(fu.max_inches)])
	_check("follow-up finished", phase._ork11e_followup.is_empty() and not phase.has_pending_stratagem_window())
	# AI decider
	_stage_fixture("ork11e_orks_reactive")
	_set_detachment(2, "Da Big Hunt")
	_move_unit("U_BEAST_SNAGGA_BOYZ_A", 0.0, 3.0)
	phase = _shooting_phase()
	RE.set_test_seed(3)
	var ai = root.get_node("AIPlayer")
	ai.enabled = true
	ai.ai_players = {1: false, 2: true}
	cp0 = _cp(2)
	var bsb_origin: Dictionary = RM.current_positions("U_BEAST_SNAGGA_BOYZ_A", GS.state)
	var ares = _shoot(phase, "U_ALLARUS_CUSTODIANS_A", "U_BEAST_SNAGGA_BOYZ_A")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_check("AI defender: no pause", ares.get("success", false) and not phase.has_pending_stratagem_window() and phase._ork11e_followup.is_empty())
	var moved := false
	var now: Dictionary = RM.current_positions("U_BEAST_SNAGGA_BOYZ_A", GS.state)
	for key in bsb_origin:
		if now.has(key) and now[key].distance_to(bsb_origin[key]) > 1.0:
			moved = true
	_check("AI used GOADED and surged", _cp(2) == cp0 - 1 and moved, "cp %d -> %d moved %s" % [cp0, _cp(2), moved])
	RE.set_test_seed(-1)


# ---------------------------------------------------------------------------
func _section_network() -> void:
	print("\n-- H. network --")
	var NM = root.get_node("NetworkManager")
	_stage_fixture("ork11e_orks_reactive")
	var phase = _shooting_phase()
	phase._ork11e_followup = {"player": 2, "kind": "surge", "unit_id": "U_BEAST_SNAGGA_BOYZ_A", "source": "TEST",
		"origin": {}, "max_inches": 3.0, "end_condition": "", "surge_target": "", "roll": 3, "reroll_allowed": false, "rerolled": false, "reference": {}}
	var prev_map = NM.peer_to_player_map.duplicate()
	NM.peer_to_player_map = {1: 1, 7: 2}
	var v = NM.validate_action({"type": "ORK11E_REACTIVE_MOVE_SKIP", "player": 2}, 7)
	_check("network: the non-active mover's action is turn-exempt", v.get("valid", false), str(v))
	v = NM.validate_action({"type": "ORK11E_REACTIVE_MOVE_SKIP", "player": 1}, 1)
	_check("network: the other player's move action refused by the phase", not v.get("valid", true), str(v))
	v = NM.validate_action({"type": "END_SHOOTING", "player": 1}, 1)
	_check("network: other actions refused during the move", not v.get("valid", true), str(v))
	NM.peer_to_player_map = prev_map
	phase._ork11e_followup = {}
