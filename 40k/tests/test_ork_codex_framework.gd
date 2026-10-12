extends SceneTree

# Codex: Orks (11e) stratagem WINDOW framework + HIT 'EM HARDER
# (design .llm/ork_codex_11e_design.md §3, §3.1, §4, §6).
#
# Covers, against the real fixture tests/saves/ork11e_orks_active.w40ksave
# (P1 Orks War Horde active vs P2 Custodes):
#   A. dispatcher registry: 40 csv ids in their groups, implemented = registry only
#   B. window gating in can_use_stratagem (no window / wrong window / right window)
#   C. StratagemManager.get_window_offers (target, CP, other window, other player)
#   D. FightPhase hook unit_selected_to_fight: pause, pending gate, USE path
#      (CP -1, flags on the Attached unit, flow resumes to attack assignment)
#   E. HIT 'EM HARDER effect: melee [LETHAL HITS] A/B with the same seeds
#   F. expiry at end of phase
#   G. DECLINE path + "don't offer again this phase"
#   H. AI decider path (synchronous, never pauses) + AIDecisionMaker heuristics
#   I. network: window actions are turn-exempt; others still turn-gated and
#      refused while a window is pending
#   J. opponent-Shooting fold-in: enemy_targets_unit_shooting window offers
#      ride the legacy reactive list (same StratagemDialog, same button names,
#      variant buttons) and USE_REACTIVE_STRATAGEM threads the window context.
#      No codex stratagem of that window is implemented yet, so a synthetic
#      window stratagem is injected for the defender (test-only).
#
# Usage: godot --headless --path 40k --script tests/test_ork_codex_framework.gd

const FIXTURE := "ork11e_orks_active"
const HIT_CSV := "hit-em-harder-war-horde"
# GameStateData.Phase values (ints: referencing the GameState class here would
# compile it before the autoloads exist — see AIDecisionMaker.gd's note).
const PHASE_COMMAND := 6
const PHASE_FIGHT := 10

var passed := 0
var failed := 0
var SM = null
var GS = null
var PM = null
var RE = null
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


func _stage_fixture() -> bool:
	var slm = root.get_node("SaveLoadManager")
	var dst = slm.save_directory + FIXTURE + ".w40ksave"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slm.save_directory))
	for ext in [".w40ksave", ".meta"]:
		var src = "res://tests/saves/" + FIXTURE + ext
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(slm.save_directory + FIXTURE + ext))
	return slm.load_game(FIXTURE)


func _hit_id() -> String:
	for s in SM.get_faction_stratagems_for_player(1):
		if str(s.get("csv_id", "")) == HIT_CSV:
			return str(s.id)
	return ""


func _cp(p: int) -> int:
	return int(GS.state.players[str(p)].cp)


func _run() -> void:
	SM = root.get_node("StratagemManager")
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	GameConstants.edition = 11

	print("\n=== test_ork_codex_framework ===\n")
	_check("fixture %s loads" % FIXTURE, _stage_fixture())
	GameConstants.edition = 11
	_check("fixture: P1 is Orks / War Horde", str(GS.state.factions["1"].get("detachment", "")) == "War Horde")
	_check("fixture: Warboss attached to Boyz", str(GS.state.units.U_WARBOSS_A.get("attached_to", "")) == "U_BOYZ_B")
	_check("fixture: Boyz engaged with Custodian Guard A", RE.is_unit_engaged("U_BOYZ_B", GS.state))
	GS.state.players["1"]["cp"] = 6
	GS.state.players["2"]["cp"] = 6

	_section_registry()
	var sid := _hit_id()
	_check("HIT 'EM HARDER loaded for P1", sid != "")
	_section_gating(sid)
	_section_offers(sid)
	await _section_phase_flow(sid)
	_section_lethal_ab()
	_section_expiry(sid)
	await _section_decline()
	await _section_ai(sid)
	_section_network()
	await _section_shooting_fold_in()


# ---------------------------------------------------------------------------
func _section_registry() -> void:
	print("\n-- A. registry --")
	var Codex = load("res://scripts/stratagems/ork_codex/OrkCodex11e.gd")
	var ids: Array = Codex.all_registered_ids()
	_check("40 csv ids registered", ids.size() == 40, str(ids.size()))
	var uniq := {}
	for i in ids:
		uniq[i] = true
	_check("no csv id registered twice", uniq.size() == ids.size())
	var groups := {
		"res://scripts/stratagems/ork_codex/OrkCodexFight.gd": 9,
		"res://scripts/stratagems/ork_codex/OrkCodexShooting.gd": 8,
		"res://scripts/stratagems/ork_codex/OrkCodexShootingReactive.gd": 6,
		"res://scripts/stratagems/ork_codex/OrkCodexMovement.gd": 12,
		"res://scripts/stratagems/ork_codex/OrkCodexOther.gd": 5,
	}
	for path in groups:
		_check("%s owns %d ids" % [path.get_file(), groups[path]], load(path).IDS.size() == groups[path], str(load(path).IDS.size()))
	# Implemented = registry only: every implemented id must be registered, and
	# HIT 'EM HARDER (the framework's worked example) must stay implemented.
	# (Compare against the registry, not a fixed list, so each implementation
	# group can add ids without editing this check.)
	var _impl: Array = Codex.all_implemented_ids()
	var _unregistered_impl: Array = []
	for _iid in _impl:
		if not (_iid in ids):
			_unregistered_impl.append(_iid)
	_check("every implemented id is registered", _unregistered_impl.is_empty(), str(_unregistered_impl))
	_check("HIT 'EM HARDER is implemented", HIT_CSV in _impl, str(_impl))

	# Every Ork CSV row (all detachments) maps to a group.
	var rows: Array = SM._faction_loader.load_faction_stratagems("Orks", "")
	var unregistered: Array = []
	var marker_rows := 0
	for s in rows:
		if Codex.handles(s):
			marker_rows += 1
			if Codex.group_for(s) == null:
				unregistered.append(str(s.get("csv_id", "?")))
	_check("all 40 Ork CSV rows carry the custom:ork11e marker", marker_rows == 40, str(marker_rows))
	_check("every Ork CSV row is registered", unregistered.is_empty(), str(unregistered))

	# Implemented flag on the loaded War Horde set: registry, not names.
	var impl := {}
	for s in SM.get_faction_stratagems_for_player(1):
		impl[str(s.get("csv_id", ""))] = bool(s.get("implemented", false))
	_check("War Horde: HIT 'EM HARDER implemented", impl.get(HIT_CSV, false) == true, str(impl))
	# Every other row's flag must match the registry (groups add ids in parallel).
	var others_off := true
	for k in impl:
		if impl[k] != bool(Codex.group_for_id(k) != null and Codex.group_for_id(k).IMPLEMENTED.get(k, false)):
			others_off = false
	_check("War Horde: the other five rows follow the registry", others_off and impl.size() == 6, str(impl))
	var ontb = SM.find_faction_stratagem_by_name(1, "ORKS IS NEVER BEATEN")
	var r = SM.can_use_stratagem(1, ontb, "U_BOYZ_B", {"window_id": "enemy_targets_unit_fight"})
	_check("unimplemented codex row: 'not yet mechanically implemented'", not r.can_use and "not yet mechanically implemented" in str(r.reason), str(r))


func _section_gating(sid: String) -> void:
	print("\n-- B. window gating --")
	var r = SM.can_use_stratagem(1, sid, "U_BOYZ_B")
	_check("no window_id -> refused with 'Offered automatically when …'",
		not r.can_use and "Offered automatically when one of your units is selected to fight" in str(r.reason), str(r))
	r = SM.can_use_stratagem(1, sid, "U_BOYZ_B", {"window_id": "unit_selected_to_shoot", "unit_id": "U_BOYZ_B"})
	_check("wrong window_id -> refused", not r.can_use and "Offered automatically" in str(r.reason), str(r))
	r = SM.can_use_stratagem(1, sid, "U_BOYZ_B", {"window_id": "unit_selected_to_fight", "unit_id": "U_BOYZ_B"})
	_check("right window outside the Fight phase -> refused by the phase gate", not r.can_use and "fight phase" in str(r.reason).to_lower(), str(r))


func _section_offers(sid: String) -> void:
	print("\n-- C. offers --")
	PM.transition_to_phase(PHASE_FIGHT)
	_check("in the Fight phase", GS.get_current_phase() == PHASE_FIGHT)
	var ctx := {"phase": "fight", "unit_id": "U_BOYZ_B"}
	var r = SM.can_use_stratagem(1, sid, "U_BOYZ_B", {"window_id": "unit_selected_to_fight", "unit_id": "U_BOYZ_B"})
	_check("right window in the Fight phase -> allowed", r.can_use, str(r))
	r = SM.can_use_stratagem(1, sid, "U_CUSTODIAN_GUARD_A", {"window_id": "unit_selected_to_fight", "unit_id": "U_CUSTODIAN_GUARD_A"})
	_check("enemy target refused (must be a unit from your army)", not r.can_use, str(r))
	r = SM.can_use_stratagem(1, sid, "U_NOBZ_A", {"window_id": "unit_selected_to_fight", "unit_id": "U_BOYZ_B"})
	_check("target must be the unit selected to fight", not r.can_use, str(r))

	var offers = SM.get_window_offers(1, "unit_selected_to_fight", ctx)
	_check("P1 offered exactly HIT 'EM HARDER", offers.size() == 1 and str(offers[0].stratagem_id) == sid, str(offers))
	if offers.size() == 1:
		_check("offer target = U_BOYZ_B, cost 1", offers[0].targets.size() == 1 and str(offers[0].targets[0].unit_id) == "U_BOYZ_B" and int(offers[0].cp_cost) == 1, str(offers[0]))
	_check("no offers for P1 when an ENEMY unit is selected", SM.get_window_offers(1, "unit_selected_to_fight", {"unit_id": "U_CUSTODIAN_GUARD_A"}).is_empty())
	_check("no offers for P2 (Custodes have no window stratagems)", SM.get_window_offers(2, "unit_selected_to_fight", {"unit_id": "U_CUSTODIAN_GUARD_A"}).is_empty())
	_check("no offers in another window", SM.get_window_offers(1, "unit_selected_to_shoot", ctx).is_empty())
	GS.state.players["1"]["cp"] = 0
	_check("no offers with 0 CP", SM.get_window_offers(1, "unit_selected_to_fight", ctx).is_empty())
	GS.state.players["1"]["cp"] = 6


func _end_pile_in(phase) -> void:
	for p in [1, 2]:
		if int(phase.pile_in_step_11e) != int(phase.PileInStep11e.ACTIVE):
			break
		phase.execute_action({"type": "END_PILE_IN", "player": int(phase.piling_in_player_11e)})


func _section_phase_flow(sid: String) -> void:
	print("\n-- D. FightPhase hook unit_selected_to_fight --")
	var phase = PM.get_current_phase_instance()
	_check("FightPhase instance", phase != null and phase.has_method("open_stratagem_window"))
	phase.stratagem_window_opened.connect(_on_window_opened)
	_end_pile_in(phase)
	_check("pile-in step finished", int(phase.pile_in_step_11e) == int(phase.PileInStep11e.DONE))
	var sel = phase.sequencer_11e.peek_selection(GS.state)
	_check("Orks (active, no Fights First) select first", int(sel.player) == 1 and "U_BOYZ_B" in sel.candidates, str(sel))

	_window_events.clear()
	var cp_before := _cp(1)
	var res = phase.execute_action({"type": "SELECT_FIGHTER", "unit_id": "U_BOYZ_B", "player": 1})
	_check("SELECT_FIGHTER succeeds", res.get("success", false), str(res.get("error", "")))
	_check("window is pending for P1", phase.has_pending_stratagem_window() and phase.get_pending_stratagem_window_decider() == 1)
	_check("stratagem_window_opened emitted once with HIT 'EM HARDER",
		_window_events.size() == 1 and _window_events[0].window_id == "unit_selected_to_fight" and _window_events[0].offers.size() == 1,
		str(_window_events))
	_check("result carries stratagem_window_opened (network mirror)", res.has("stratagem_window_opened"))
	_check("no attack assignment yet (flow paused)", not res.get("trigger_attack_assignment", false))

	var blocked = phase.execute_action({"type": "END_FIGHT", "player": 1})
	_check("other actions refused while the window waits", not blocked.get("success", true) and "Waiting for Player 1" in str(blocked.get("error", "")), str(blocked))
	var wrong_player = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 2, "window_id": "unit_selected_to_fight", "stratagem_id": sid, "target_unit_id": "U_BOYZ_B"})
	_check("USE by the wrong player refused", not wrong_player.get("success", true), str(wrong_player))
	var wrong_target = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_fight", "stratagem_id": sid, "target_unit_id": "U_NOBZ_A"})
	_check("USE on a target not offered refused", not wrong_target.get("success", true), str(wrong_target))
	var wrong_window = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_shoot", "stratagem_id": sid, "target_unit_id": "U_BOYZ_B"})
	_check("USE naming another window refused", not wrong_window.get("success", true), str(wrong_window))
	_check("window still pending after refused answers", phase.has_pending_stratagem_window())

	var use = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_fight", "stratagem_id": sid, "target_unit_id": "U_BOYZ_B"})
	_check("USE_WINDOW_STRATAGEM succeeds", use.get("success", false), str(use.get("error", "")))
	_check("window closed", not phase.has_pending_stratagem_window())
	_check("CP 6 -> 5", _cp(1) == cp_before - 1, "%d -> %d" % [cp_before, _cp(1)])
	_check("Boyz melee [LETHAL HITS] flag set", bool(GS.state.units.U_BOYZ_B.flags.get("effect_lethal_hits_melee", false)))
	_check("attached Warboss gets the flag too (19.03)", bool(GS.state.units.U_WARBOSS_A.flags.get("effect_lethal_hits_melee", false)))
	_check("enemy unit untouched", not GS.state.units.U_CUSTODIAN_GUARD_A.flags.has("effect_lethal_hits_melee"))
	_check("flow resumed: attack assignment requested for U_BOYZ_B", use.get("trigger_attack_assignment", false) and phase.active_fighter_id == "U_BOYZ_B", str(use.keys()))
	_check("result names the stratagem used", str(use.get("stratagem_used", {}).get("stratagem_id", "")) == sid)
	var changes = use.get("changes", [])
	var has_cp_diff := false
	for d in changes:
		if str(d.get("path", "")) == "players.1.cp":
			has_cp_diff = true
	_check("result changes include the CP diff (replay/network)", has_cp_diff)
	var again = SM.can_use_stratagem(1, sid, "U_BOYZ_B", {"window_id": "unit_selected_to_fight", "unit_id": "U_BOYZ_B"})
	_check("once per phase: second use refused", not again.can_use, str(again))
	var log_hit := false
	for e in GS.state.get("phase_log", []):
		if str(e.get("type", "")) == "STRATAGEM_USED" and str(e.get("stratagem_id", "")) == sid:
			log_hit = true
	_check("STRATAGEM_USED in the phase log", log_hit)


func _synthetic_fight(flags: Dictionary, seed_val: int) -> Dictionary:
	var atk = []
	for i in range(10):
		atk.append({"id": "ma%d" % i, "position": {"x": 10.0, "y": 10.0 + i * 30},
			"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 1, "current_wounds": 1})
	var tgt = []
	for i in range(10):
		tgt.append({"id": "mt%d" % i, "position": {"x": 30.0, "y": 10.0 + i * 30},
			"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 3, "current_wounds": 3,
			"stats": {"toughness": 10, "save": 3}})
	var board = {"units": {
		"U_ATK": {"id": "U_ATK", "owner": 1,
			"meta": {"keywords": ["INFANTRY", "ORKS"], "stats": {"toughness": 5, "save": 6, "wounds": 1}, "abilities": []},
			"flags": flags, "models": atk},
		"U_TGT": {"id": "U_TGT", "owner": 2,
			"meta": {"keywords": ["INFANTRY"], "stats": {"toughness": 10, "save": 3, "wounds": 3}, "abilities": []},
			"flags": {}, "models": tgt}
	}, "meta": {"phase": 10, "active_player": 1, "battle_round": 1}}
	RE.set_test_seed(seed_val)
	var rng = RE.RNGService.new()
	var action := {"type": "FIGHT", "actor_unit_id": "U_ATK",
		"payload": {"assignments": [{"attacker": "U_ATK", "target": "U_TGT", "weapon": "choppa"}]}}
	return RE.resolve_melee_attacks(action, board, rng)


func _wounds(result: Dictionary) -> int:
	var total := 0
	for d in result.get("dice", []):
		var c = str(d.get("context", "")).to_lower()
		if "wound" in c and d.has("successes"):
			total += int(d.get("successes", 0))
	return total


func _section_lethal_ab() -> void:
	print("\n-- E. HIT 'EM HARDER effect (melee [LETHAL HITS]) --")
	var off := 0
	var on := 0
	var never_lower := true
	for s in range(20):
		var a = _wounds(_synthetic_fight({}, 1000 + s))
		var b = _wounds(_synthetic_fight({"effect_lethal_hits_melee": true}, 1000 + s))
		off += a
		on += b
		if b < a:
			never_lower = false
	_check("A/B same seeds: with the flag never fewer wounds", never_lower)
	_check("A/B same seeds: lethal hits add wounds vs T10 (%d -> %d over 20 seeds)" % [off, on], on > off)
	# The flag is melee-scoped: the ranged LETHAL HITS readers ignore it.
	var EP = load("res://autoloads/EffectPrimitives.gd")
	_check("ranged resolvers do not read the melee flag", not EP.has_effect_lethal_hits({"flags": {"effect_lethal_hits_melee": true}}))


func _section_expiry(sid: String) -> void:
	print("\n-- F. expiry --")
	var eff_found := false
	for e in SM.active_effects:
		if str(e.get("stratagem_id", "")) == sid and str(e.get("target_unit_id", "")) == "U_BOYZ_B":
			eff_found = true
			_check("active effect expires at end_of_phase", str(e.get("expires", "")) == "end_of_phase", str(e))
	_check("active effect recorded", eff_found)
	SM.on_phase_end(PHASE_FIGHT)
	_check("Boyz flag cleared at end of phase", not GS.state.units.U_BOYZ_B.flags.has("effect_lethal_hits_melee"))
	_check("Warboss flag cleared at end of phase", not GS.state.units.U_WARBOSS_A.flags.has("effect_lethal_hits_melee"))
	_check("marker flag cleared", not GS.state.units.U_BOYZ_B.flags.has("ork11e_hit_em_harder"))


func _fresh_fight_phase():
	SM._usage_history = {"1": [], "2": []}
	SM.active_effects = []
	GS.state.players["1"]["cp"] = 6
	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(PHASE_FIGHT)
	var phase = PM.get_current_phase_instance()
	_end_pile_in(phase)
	return phase


func _section_decline() -> void:
	print("\n-- G. decline + don't offer again --")
	var phase = _fresh_fight_phase()
	var cp_before := _cp(1)
	var res = phase.execute_action({"type": "SELECT_FIGHTER", "unit_id": "U_NOBZ_A", "player": 1})
	_check("SELECT_FIGHTER (Nobz) opens the window", res.get("success", false) and phase.has_pending_stratagem_window(), str(res.get("error", "")))
	var dec = phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_fight"})
	_check("DECLINE succeeds", dec.get("success", false), str(dec.get("error", "")))
	_check("no CP spent on decline", _cp(1) == cp_before)
	_check("no flag on decline", not GS.state.units.U_NOBZ_A.flags.has("effect_lethal_hits_melee"))
	_check("flow resumed after decline (attack assignment)", dec.get("trigger_attack_assignment", false) and phase.active_fighter_id == "U_NOBZ_A", str(dec.keys()))

	# A manual window (same hook semantics) for another unit: plain decline
	# keeps offering, "don't offer again" suppresses for the rest of the phase.
	var ctx := {"phase": "fight", "unit_id": "U_MEGANOBZ_A"}
	_check("offers exist for Meganobz", not SM.get_window_offers(1, "unit_selected_to_fight", ctx).is_empty())
	_check("manual window opens (pauses)", phase.open_stratagem_window(1, "unit_selected_to_fight", ctx, ""))
	var dec2 = phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_fight", "dont_offer_again": true})
	_check("DECLINE with dont_offer_again succeeds", dec2.get("success", false), str(dec2.get("error", "")))
	_check("suppressed: the window does not open again this phase", not phase.open_stratagem_window(1, "unit_selected_to_fight", ctx, "") and not phase.has_pending_stratagem_window())
	var phase2 = _fresh_fight_phase()
	_check("a new phase offers again", phase2.open_stratagem_window(1, "unit_selected_to_fight", ctx, ""))
	phase2.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_fight"})
	_check("window closed after decline", not phase2.has_pending_stratagem_window())


func _section_ai(sid: String) -> void:
	print("\n-- H. AI decider --")
	var ADM = load("res://scripts/AIDecisionMaker.gd")
	var phase = _fresh_fight_phase()
	var offers = SM.get_window_offers(1, "unit_selected_to_fight", {"unit_id": "U_MEGANOBZ_A"})
	var d = ADM.decide_window_stratagem(1, "unit_selected_to_fight", offers, {"unit_id": "U_MEGANOBZ_A"})
	_check("AI uses HIT 'EM HARDER on an engaged melee unit with 6 CP", d.get("use", false) and str(d.get("stratagem_id", "")) == sid and str(d.get("target_unit_id", "")) == "U_MEGANOBZ_A", str(d))
	GS.state.players["1"]["cp"] = 1
	offers = SM.get_window_offers(1, "unit_selected_to_fight", {"unit_id": "U_MEGANOBZ_A"})
	d = ADM.decide_window_stratagem(1, "unit_selected_to_fight", offers, {"unit_id": "U_MEGANOBZ_A"})
	_check("AI keeps its last CP (offensive needs >= 2 CP)", not d.get("use", true), str(d))
	GS.state.players["1"]["cp"] = 6
	# An unengaged unit with no target: score 0 -> decline.
	offers = SM.get_window_offers(1, "unit_selected_to_fight", {"unit_id": "U_KOMMANDOS_A"})
	d = ADM.decide_window_stratagem(1, "unit_selected_to_fight", offers, {"unit_id": "U_KOMMANDOS_A"})
	_check("AI declines on an unengaged unit", not d.get("use", true), str(d))

	# Synchronous path through the phase: an AI decider never pauses.
	var ai = root.get_node("AIPlayer")
	var prev_enabled = ai.enabled
	var prev_players = ai.ai_players.duplicate()
	ai.enabled = true
	ai.ai_players = {1: true, 2: false}
	var cp_before := _cp(1)
	var paused = phase.open_stratagem_window(1, "unit_selected_to_fight", {"phase": "fight", "unit_id": "U_MEGANOBZ_A"}, "")
	var sync_diffs = phase.consume_window_diffs()
	ai.enabled = prev_enabled
	ai.ai_players = prev_players
	_check("AI window resolves synchronously (no pause)", not paused and not phase.has_pending_stratagem_window())
	_check("AI spent 1 CP", _cp(1) == cp_before - 1, "%d -> %d" % [cp_before, _cp(1)])
	_check("AI's choice applied the flag", bool(GS.state.units.U_MEGANOBZ_A.flags.get("effect_lethal_hits_melee", false)))
	_check("synchronous diffs handed to the caller", not sync_diffs.is_empty())
	SM.on_phase_end(PHASE_FIGHT)


func _section_network() -> void:
	print("\n-- I. network validation --")
	var NM = root.get_node("NetworkManager")
	var phase = _fresh_fight_phase()
	# Window pending for P1 (active); P2's peer sends actions.
	phase.open_stratagem_window(1, "unit_selected_to_fight", {"phase": "fight", "unit_id": "U_BOYZ_B"}, "")
	var prev_map = NM.peer_to_player_map.duplicate()
	NM.peer_to_player_map = {1: 1, 7: 2}
	var v = NM.validate_action({"type": "END_FIGHT", "player": 1}, 1)
	_check("network: other actions refused while a window is pending", not v.get("valid", true) and "Waiting for Player 1" in str(v.get("reason", "")), str(v))
	v = NM.validate_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_fight"}, 1)
	_check("network: decider's DECLINE validates", v.get("valid", false), str(v))
	v = NM.validate_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 2, "window_id": "unit_selected_to_fight"}, 7)
	_check("network: the non-decider's answer is refused by the phase", not v.get("valid", true), str(v))
	phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_fight"})
	# Opponent-turn decider: P2's window while P1 is active — turn-exempt.
	GS.state.players["2"]["cp"] = 6
	phase._window_pending = {"player": 2, "window_id": "unit_selected_to_fight", "offers": [], "ctx": {}}
	v = NM.validate_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 2, "window_id": "unit_selected_to_fight"}, 7)
	_check("network: non-active decider is turn-exempt", v.get("valid", false), str(v))
	v = NM.validate_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 1, "window_id": "unit_selected_to_fight"}, 7)
	_check("network: authority still enforced (claimed player != peer)", not v.get("valid", true), str(v))
	phase._window_pending = {}
	NM.peer_to_player_map = prev_map
	# Client mirror re-emits the signal.
	_window_events.clear()
	phase.stratagem_window_opened.connect(_on_window_opened)
	phase.mirror_stratagem_window({"player": 2, "window_id": "unit_selected_to_fight", "offers": [{"stratagem_id": "x"}], "ctx": {"unit_id": "U_BOYZ_B"}})
	_check("client mirror: pending + signal re-emitted", phase.has_pending_stratagem_window() and _window_events.size() == 1)
	phase.clear_mirrored_stratagem_window()
	_check("client mirror cleared", not phase.has_pending_stratagem_window())


func _section_shooting_fold_in() -> void:
	print("\n-- J. opponent-Shooting fold-in --")
	SM._usage_history = {"1": [], "2": []}
	GS.state.players["2"]["cp"] = 6
	PM.transition_to_phase(PHASE_COMMAND)
	PM.transition_to_phase(8)  # SHOOTING, P1 (Orks) active
	var phase = PM.get_current_phase_instance()
	var sid := "faction_test_window_enemy_targets"
	SM.stratagems[sid] = {
		"id": sid, "csv_id": "test-window-enemy-targets", "name": "TEST WINDOW REACTIVE",
		"type": "Test Stratagem", "cp_cost": 1, "implemented": true,
		"timing": {"turn": "opponent", "phase": "shooting", "trigger": "enemy_targets_unit_shooting",
			"windows": ["enemy_targets_unit_shooting"]},
		"target": {"type": "unit", "owner": "friendly", "conditions": []},
		"effects": [], "restrictions": {"once_per": "phase"},
		"effect_text": "Test-only window stratagem.", "description": "Test-only window stratagem."}
	SM._player_faction_stratagems["2"].append(sid)
	var avail: Array = SM.get_reactive_stratagems_for_shooting(2, ["U_CUSTODIAN_GUARD_C"], {"attacker_unit_id": "U_FLASH_GITZ_A"})
	var entry = {}
	for e in avail:
		if str(e.stratagem.get("id", "")) == sid:
			entry = e
	_check("fold-in: window offer listed in the reactive list", not entry.is_empty(), str(avail.map(func(e): return e.stratagem.get("name", "?"))))
	_check("fold-in: entry carries window_id + offer", str(entry.get("window_id", "")) == "enemy_targets_unit_shooting" and entry.has("offer"))
	_check("fold-in: eligible unit = the targeted defender unit", entry.get("eligible_units", []) == ["U_CUSTODIAN_GUARD_C"], str(entry.get("eligible_units", [])))
	_check("fold-in: a non-targeted unit is not offered", SM.get_reactive_stratagems_for_shooting(2, ["U_CUSTODIAN_GUARD_D"], {}).filter(func(e): return str(e.stratagem.get("id", "")) == sid and "U_CUSTODIAN_GUARD_C" in e.eligible_units).is_empty())
	var r = SM.can_use_stratagem(2, sid, "U_CUSTODIAN_GUARD_C")
	_check("fold-in: without the window context the use is refused", not r.can_use and "Offered automatically" in str(r.reason), str(r))

	phase.active_shooter_id = "U_FLASH_GITZ_A"
	phase.confirmed_assignments = [{"target_unit_id": "U_CUSTODIAN_GUARD_C", "weapon_id": "x"}]
	phase.awaiting_reactive_stratagem = true
	var action := {"type": "USE_REACTIVE_STRATAGEM", "stratagem_id": sid, "target_unit_id": "U_CUSTODIAN_GUARD_C", "context": {"variant_id": ""}}
	var wctx: Dictionary = phase._reactive_window_context(action)
	_check("fold-in: USE_REACTIVE_STRATAGEM context has the window keys",
		str(wctx.get("window_id", "")) == "enemy_targets_unit_shooting" and str(wctx.get("attacker_unit_id", "")) == "U_FLASH_GITZ_A" and wctx.get("target_unit_ids", []) == ["U_CUSTODIAN_GUARD_C"], str(wctx))
	var v = phase._validate_use_reactive_stratagem(action)
	_check("fold-in: ShootingPhase validates the window stratagem", v.get("valid", false), str(v))
	var core_ctx = phase._reactive_window_context({"type": "USE_REACTIVE_STRATAGEM", "stratagem_id": "smokescreen_11e", "target_unit_id": "U_CUSTODIAN_GUARD_C"})
	_check("fold-in: core reactive stratagems keep an empty context", core_ctx.is_empty(), str(core_ctx))
	var cp_before := _cp(2)
	var used = SM.use_stratagem(2, sid, "U_CUSTODIAN_GUARD_C", wctx)
	_check("fold-in: use with the window context succeeds (-1 CP)", used.get("success", false) and _cp(2) == cp_before - 1, str(used.get("error", "")))
	phase.awaiting_reactive_stratagem = false
	phase.confirmed_assignments = []

	# Same dialog, same button names — variant buttons for window offers.
	var Dlg = load("res://dialogs/StratagemDialog.gd")
	var dlg = Dlg.new()
	root.add_child(dlg)
	var offer := {"stratagem_id": sid, "name": "TEST WINDOW REACTIVE", "cp_cost": 1, "effect_text": "x", "type": "Test",
		"targets": [{"unit_id": "U_CUSTODIAN_GUARD_C", "label": "Guard", "variants": [{"id": "upgrade", "label": "Upgraded", "cp_cost": 2}]}]}
	var smoke = SM.stratagems.get("smokescreen_11e", {"id": "smokescreen_11e", "name": "SMOKESCREEN", "cp_cost": 1})
	dlg.setup(2, [{"stratagem": smoke, "eligible_units": ["U_CUSTODIAN_GUARD_C"]},
		{"stratagem": SM.stratagems[sid], "eligible_units": ["U_CUSTODIAN_GUARD_C"], "window_id": "enemy_targets_unit_shooting", "offer": offer}],
		["U_CUSTODIAN_GUARD_C"])
	var base := "Content/StratScroll/StratList/"
	_check("dialog: core card keeps its node path", dlg.get_node_or_null(base + "Card_smokescreen_11e/Buttons/Use_smokescreen_11e_U_CUSTODIAN_GUARD_C") != null)
	_check("dialog: window card Use_<sid>_<uid>", dlg.get_node_or_null(base + "Card_%s/Buttons/Use_%s_U_CUSTODIAN_GUARD_C" % [sid, sid]) != null)
	var vbtn = dlg.get_node_or_null(base + "Card_%s/Buttons/Use_%s_U_CUSTODIAN_GUARD_C_upgrade" % [sid, sid])
	_check("dialog: variant button Use_<sid>_<uid>_<variant>", vbtn != null)
	var got := []
	dlg.stratagem_selected_with_context.connect(func(a, b, c): got.append([a, b, c]))
	if vbtn:
		vbtn.emit_signal("pressed")
	_check("dialog: variant press emits the variant context", got.size() == 1 and str(got[0][2].get("variant_id", "")) == "upgrade", str(got))

	# Window mode builds the same names + decline buttons.
	var wdlg = Dlg.new()
	root.add_child(wdlg)
	wdlg.setup_window(1, "unit_selected_to_fight", [offer], {"unit_id": "U_BOYZ_B"})
	_check("window dialog: header names the unit", str(wdlg.get_node("Content/Header").text) == "Boyz has been selected to fight", str(wdlg.get_node("Content/Header").text))
	_check("window dialog: Decline + Don't-offer-again buttons", wdlg.get_node_or_null("Content/DeclineButton") != null and wdlg.get_node_or_null("Content/DontOfferAgainButton") != null)
	var wgot := []
	wdlg.window_declined.connect(func(d): wgot.append(d))
	wdlg.get_node("Content/DontOfferAgainButton").emit_signal("pressed")
	_check("window dialog: don't-offer-again emits window_declined(true)", wgot == [true], str(wgot))

	# Escape / the window ✕ = Decline (same convention as Overwatch / HI), and
	# only once — a closed-but-pending window would strand the phase.
	var cdlg = Dlg.new()
	root.add_child(cdlg)
	cdlg.setup_window(1, "unit_selected_to_fight", [offer], {"unit_id": "U_BOYZ_B"})
	var cgot := []
	cdlg.window_declined.connect(func(d): cgot.append(d))
	cdlg.emit_signal("canceled")
	cdlg.emit_signal("close_requested")
	_check("window dialog: Escape/close declines exactly once (not 'don't offer again')", cgot == [false], str(cgot))

	SM._player_faction_stratagems["2"].erase(sid)
	SM.stratagems.erase(sid)
