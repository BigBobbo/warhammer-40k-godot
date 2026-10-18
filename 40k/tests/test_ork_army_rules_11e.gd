extends SceneTree

# Codex: Orks (11e) army rules — WP-O34 (plan O3). Against the real fixture
# tests/saves/ork11e_o34_active.w40ksave (P1 Orks from the codex-era army file
# + a Weirdboy, War Horde, ACTIVE vs P2 Custodes; generator
# tests/helpers/gen_ork11e_o34_fixtures.gd):
#   A. Waaagh! riled up (11e): 5+ InSv, ranged [ASSAULT], advance-and-charge,
#      no 10e +1 S/A; War Cry records "until the end of the next turn"
#   B. War Cry expiry — called in your own Command phase / in the opponent's
#   C. War Cry in the OPPONENT's Command phase: rule window before the
#      Battle-shock step, USE riles the Orks up, not offered when spent / at
#      10e / to a player without the Waaagh!, the AI declines without stalling
#   D. Waaagh! free advance re-roll: offered in the advance re-roll dialog
#      (no CP), used / declined, not offered in a tutorial, AI policy
#   E. Da Boss: +1CP at the start of the battle round only while the WARLORD
#      has it (alive), once per round, not for the second player's Command
#      phase, not at 10e
#   F. Unstable Energies: psyker / psychic levels, budget refusal with
#      feedback, reset each battle round, 22.03.01 once per phase, the Da Jump
#      path refuses and stops listing USE_DA_JUMP, level override
#
# Usage: godot --headless --path 40k --script tests/test_ork_army_rules_11e.gd

const FIXTURE := "ork11e_o34_active"
const PHASE_COMMAND := 6
const PHASE_MOVEMENT := 7
const PHASE_SHOOTING := 8
const PX := 40.0
const ArmyRules = preload("res://scripts/codex/orks/OrkArmyRules11e.gd")
const Det = preload("res://scripts/codex/orks/OrkDetachments11e.gd")

var passed := 0
var failed := 0
var SM = null
var GS = null
var PM = null
var RE = null
var FAM = null
var _reroll_events: Array = []


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


func _reload() -> void:
	_stage_fixture()
	GS.set_edition(11)
	FAM.load_state({})
	_reroll_events.clear()


func _set_detachment(player: int, det: String) -> void:
	GS.state.factions[str(player)]["detachment"] = det
	SM.load_faction_stratagems_for_player(player)
	FAM.detect_player_detachment(player)


func _cp(p: int) -> int:
	return int(GS.state.players[str(p)].cp)


func _flags(uid: String) -> Dictionary:
	return GS.state.units.get(uid, {}).get("flags", {})


func _set_turn(round_no: int, active: int, phase: int) -> void:
	GS.state.meta["battle_round"] = round_no
	GS.state.meta["active_player"] = active
	GS.state.meta["phase"] = phase


func _on_reroll(_uid: String, _player: int, ctx: Dictionary) -> void:
	_reroll_events.append(ctx)


## A seed whose first D6 (RulesEngine.RNGService) is <= `cap` / == `value`
## (BEGIN_ADVANCE rolls with RNGService.new(payload.rng_seed)).
func _seed_rolling_at_most(cap: int) -> int:
	for s in range(1, 500):
		if int(RE.RNGService.new(s).roll_d6(1)[0]) <= cap:
			return s
	return 1


func _seed_rolling_exactly(value: int) -> int:
	for s in range(1, 500):
		if int(RE.RNGService.new(s).roll_d6(1)[0]) == value:
			return s
	return 1


func _decline_pending(phase) -> void:
	for _i in range(4):
		if phase == null or not phase.has_pending_stratagem_window():
			return
		var w: Dictionary = phase.get_pending_stratagem_window()
		phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": int(w.get("player", 1)), "window_id": str(w.get("window_id", ""))})


# ---------------------------------------------------------------------------
func _run() -> void:
	SM = root.get_node("StratagemManager")
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	RE = root.get_node("RulesEngine")
	FAM = root.get_node("FactionAbilityManager")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	GS.set_edition(11)

	print("\n=== test_ork_army_rules_11e ===\n")
	_check("fixture %s loads" % FIXTURE, _stage_fixture())
	GS.set_edition(11)
	_check("fixture: the Warboss is the WARLORD and carries Da Boss",
		bool(GS.state.units.U_WARBOSS_A.meta.get("is_warlord", false)) and ArmyRules.has_ability(GS.state.units.U_WARBOSS_A, "Da Boss"))
	_check("fixture: the Weirdboy is an ORKS PSYKER with Unstable Energies", ArmyRules.is_budgeted_psyker(GS.state.units.U_WEIRDBOY_A))

	_section_waaagh_riled_up()
	_section_war_cry_expiry()
	_section_war_cry_opponent_phase()
	_section_free_advance_reroll()
	_section_da_boss()
	_section_unstable_energies()


# ---------------------------------------------------------------------------
func _section_waaagh_riled_up() -> void:
	print("\n-- A. Waaagh! riled up (11e) --")
	_reload()
	_set_turn(2, 1, PHASE_COMMAND)
	FAM.detect_faction_abilities(1)
	_check("War Cry is available to the Orks", FAM.is_waaagh_available(1))
	var res: Dictionary = FAM.activate_waaagh(1)
	_check("War Cry (CALL_WAAAGH path) succeeds", res.get("success", false), str(res))
	var f := _flags("U_KOMMANDOS_A")
	_check("riled up: waaagh_active", bool(f.get("waaagh_active", false)))
	_check("riled up: 5+ invulnerable save", int(f.get("effect_invuln", 0)) == 5)
	_check("riled up: advancing does not prevent charging", bool(f.get("effect_advance_and_charge", false)))
	_check("riled up: ranged attacks have [ASSAULT]", bool(f.get("effect_advance_and_shoot", false)))
	_check("no 10e +1 S / +1 A melee bonus at 11e", not FAM.waaagh_melee_bonus_applies(GS.state.units.U_KOMMANDOS_A))
	_check("the Weirdboy (Waaagh! ability) is riled up too", bool(_flags("U_WEIRDBOY_A").get("waaagh_active", false)))
	_check("Custodes are untouched", not bool(_flags("U_CUSTODIAN_GUARD_A").get("waaagh_active", false)))
	_check("expiry recorded: until the end of the next turn (turn #%d)" % (ArmyRules.turn_index() + 1),
		int(GS.state.players["1"].get(ArmyRules.P_WAR_CRY_UNTIL, -1)) == ArmyRules.turn_index() + 1)
	_check("once per battle: not available again", not FAM.is_waaagh_available(1))


func _section_war_cry_expiry() -> void:
	print("\n-- B. War Cry expiry: until the end of the next turn --")
	_reload()
	# Called in the Orks' own Command phase, battle round 2 (turn #2).
	_set_turn(2, 1, PHASE_COMMAND)
	FAM.detect_faction_abilities(1)
	FAM.activate_waaagh(1)
	_check("turn index of R2 P1 is 2", ArmyRules.turn_index() == 2)
	# The opponent's Command phase (turn #3 — "the next turn") — still riled up.
	_set_turn(2, 2, PHASE_COMMAND)
	FAM.on_command_phase_start(2)
	_check("riled up through the opponent's next turn (turn #3)", FAM.is_waaagh_active(1) and bool(_flags("U_BOYZ_B").get("waaagh_active", false)))
	# The Orks' next Command phase (turn #4): the next turn is over.
	_set_turn(3, 1, PHASE_COMMAND)
	FAM.on_command_phase_start(1)
	_check("ends once the next turn is over (start of turn #4)", not FAM.is_waaagh_active(1) and not bool(_flags("U_BOYZ_B").get("waaagh_active", false)))
	_check("invuln / assault cleared with it", not _flags("U_BOYZ_B").has("effect_invuln") and not bool(_flags("U_BOYZ_B").get("effect_advance_and_shoot", false)))

	# Called in the OPPONENT's Command phase (R2 P2, turn #3): riled up for
	# the opponent's turn AND the Orks' next turn (#4); ends before turn #5.
	_reload()
	_set_turn(2, 2, PHASE_COMMAND)
	FAM.detect_faction_abilities(1)
	FAM.activate_waaagh(1)
	_check("expiry recorded: turn #4", int(GS.state.players["1"].get(ArmyRules.P_WAR_CRY_UNTIL, -1)) == 4)
	_set_turn(3, 1, PHASE_COMMAND)
	FAM.on_command_phase_start(1)
	_check("still riled up in the Orks' own next turn (turn #4) — the old 'start of your next Command phase' expiry would have ended it",
		FAM.is_waaagh_active(1) and bool(_flags("U_BOYZ_B").get("waaagh_active", false)))
	_set_turn(3, 2, PHASE_COMMAND)
	FAM.on_command_phase_start(2)
	_check("ends at the start of turn #5", not FAM.is_waaagh_active(1))

	# A save from before WP-O34 (no recorded expiry) keeps the old behaviour.
	_reload()
	_set_turn(2, 1, PHASE_COMMAND)
	FAM.detect_faction_abilities(1)
	FAM.activate_waaagh(1)
	GS.state.players["1"].erase(ArmyRules.P_WAR_CRY_UNTIL)
	_set_turn(2, 2, PHASE_COMMAND)
	FAM.on_command_phase_start(2)
	_check("legacy (no expiry key): not ended by the opponent's Command phase", FAM.is_waaagh_active(1))
	_set_turn(3, 1, PHASE_COMMAND)
	FAM.on_command_phase_start(1)
	_check("legacy (no expiry key): ends at its owner's next Command phase", not FAM.is_waaagh_active(1))


## WP-C3: the Custodes' Command phase readies their units (flags.cus11e_readied),
## which opens their 0-CP ka'tah windows (command_phase_main first). Clear it so
## this file sees only the Orks' War Cry window (same helper as test_ork_codex_other.gd).
func _cus11e_unready() -> void:
	var rnd: int = int(GS.get_battle_round())
	for uid in GS.state.units:
		var u: Dictionary = GS.state.units[uid]
		if not (u.get("flags", null) is Dictionary):
			u["flags"] = {}
		u.flags.erase("cus11e_readied")
		u.flags["cus11e_master_of_katahs_round"] = rnd


func _section_war_cry_opponent_phase() -> void:
	print("\n-- C. War Cry in the opponent's Command phase (rule window) --")
	_reload()
	GS.state.meta["active_player"] = 2
	PM.transition_to_phase(PHASE_COMMAND)
	_cus11e_unready()
	var phase = PM.get_current_phase_instance()
	_check("Command phase of Player 2 (Custodes)", int(GS.get_active_player()) == 2 and phase != null)
	var entries: Array = ArmyRules.war_cry_window_entries(2)
	_check("the non-active Orks get a War Cry window entry", entries.size() == 1 and int(entries[0].player) == 1 and str(entries[0].window_id) == ArmyRules.WINDOW_WAR_CRY, str(entries))
	var offers: Array = SM.get_window_offers(1, ArmyRules.WINDOW_WAR_CRY, {"phase": "command"})
	_check("offer: WAR CRY, free rule offer", offers.size() == 1 and str(offers[0].stratagem_id) == ArmyRules.RULE_WAR_CRY and bool(offers[0].get("rule", false)) and int(offers[0].cp_cost) == 0, str(offers))
	_check("the Custodes are offered nothing", SM.get_window_offers(2, ArmyRules.WINDOW_WAR_CRY, {"phase": "command"}).is_empty())
	# The window opens when the Battle-shock step starts (END_COMMAND here).
	var cp1 := _cp(1)
	var res: Dictionary = phase.execute_action({"type": "END_COMMAND", "player": 2})
	_check("END_COMMAND pauses on Player 1's War Cry window", res.get("success", false) and phase.has_pending_stratagem_window()
		and str(phase.get_pending_stratagem_window().get("window_id", "")) == ArmyRules.WINDOW_WAR_CRY, str(phase.get_pending_stratagem_window()))
	var blocked: Dictionary = phase.execute_action({"type": "END_COMMAND", "player": 2})
	_check("other actions wait for the decision", not blocked.get("success", true))
	var use: Dictionary = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": ArmyRules.WINDOW_WAR_CRY,
		"stratagem_id": ArmyRules.RULE_WAR_CRY, "target_unit_id": ""})
	_check("USE War Cry succeeds", use.get("success", false), str(use.get("error", "")))
	_check("the Orks are riled up in the opponent's turn", FAM.is_waaagh_active(1) and int(_flags("U_BOYZ_B").get("effect_invuln", 0)) == 5)
	_check("no CP spent (an army rule, not a stratagem)", _cp(1) == cp1)
	_check("expiry: the end of the Orks' next turn (#%d)" % (ArmyRules.turn_index() + 1), int(GS.state.players["1"].get(ArmyRules.P_WAR_CRY_UNTIL, -1)) == ArmyRules.turn_index() + 1)
	var diff_seen := false
	for d in use.get("changes", []):
		if str(d.get("path", "")) == "units.U_BOYZ_B.flags.waaagh_active":
			diff_seen = true
	_check("the riled-up flags ride the action result (replay / network)", diff_seen)
	_check("War Cry no longer offered (once per battle)", SM.get_window_offers(1, ArmyRules.WINDOW_WAR_CRY, {"phase": "command"}).is_empty())
	_check("the Command phase then completes", not phase.has_pending_stratagem_window())

	# Decline leaves the Waaagh! unused.
	_reload()
	GS.state.meta["active_player"] = 2
	PM.transition_to_phase(PHASE_COMMAND)
	_cus11e_unready()
	phase = PM.get_current_phase_instance()
	phase.execute_action({"type": "END_COMMAND", "player": 2})
	_check("window open again (fresh game)", phase.has_pending_stratagem_window())
	phase.execute_action({"type": "DECLINE_WINDOW_STRATAGEM", "player": 1, "window_id": ArmyRules.WINDOW_WAR_CRY})
	_check("declined: the Waaagh! is still unused", FAM.is_waaagh_available(1) and not FAM.is_waaagh_active(1))

	# AI decider: answered synchronously (declines — the AI calls its own).
	_reload()
	var ai = root.get_node("AIPlayer")
	ai.enabled = true
	ai.ai_players = {1: true, 2: false}
	GS.state.meta["active_player"] = 2
	PM.transition_to_phase(PHASE_COMMAND)
	_cus11e_unready()
	phase = PM.get_current_phase_instance()
	res = phase.execute_action({"type": "END_COMMAND", "player": 2})
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	_check("AI decider: no pending window, no stall", res.get("success", false) and not phase.has_pending_stratagem_window(), str(res.get("error", "")))
	_check("AI declined War Cry in the opponent's phase", not FAM.is_waaagh_active(1))

	# Not at 10e; not for a player without the Waaagh!.
	_reload()
	GS.set_edition(10)
	_check("10e: no War Cry window", ArmyRules.war_cry_window_entries(2).is_empty())
	GS.set_edition(11)
	_check("Custodes (no Waaagh!) get no entry in the Orks' phase", ArmyRules.war_cry_window_entries(1).is_empty())


func _section_free_advance_reroll() -> void:
	print("\n-- D. Waaagh!: free advance re-roll --")
	_reload()
	_set_detachment(1, "Kult of Speed")  # no Kommandos movement stratagems in the way
	PM.transition_to_phase(PHASE_MOVEMENT)
	var phase = PM.get_current_phase_instance()
	_decline_pending(phase)  # WP-O6: the codex Da Jump is offered at the start of the Movement phase
	if not phase.command_reroll_opportunity.is_connected(_on_reroll):
		phase.command_reroll_opportunity.connect(_on_reroll)
	_check("source for Kommandos = Waaagh!", ArmyRules.free_advance_reroll_source(GS.state.units.U_KOMMANDOS_A) == "Waaagh!")
	_check("no source for Custodes", ArmyRules.free_advance_reroll_source(GS.state.units.U_CUSTODIAN_GUARD_C) == "")
	var cp1 := _cp(1)
	var low_seed := _seed_rolling_at_most(3)
	_reroll_events.clear()
	var res: Dictionary = phase.execute_action({"type": "BEGIN_ADVANCE", "actor_unit_id": "U_KOMMANDOS_A", "player": 1, "payload": {"rng_seed": low_seed}})
	_decline_pending(phase)
	var rolled := int(phase._reroll_pending_data.get("advance_roll", 0))
	_check("BEGIN_ADVANCE (rolled %d) pauses for the re-roll decision" % rolled, res.get("success", false) and phase._awaiting_reroll_decision, str(res.get("error", "")))
	_check("the pending re-roll is the free Waaagh! one", str(phase._reroll_pending_data.get("free_ability", "")) == "Waaagh!")
	_check("the dialog signal carries free_ability_name = Waaagh!", not _reroll_events.is_empty() and str(_reroll_events[-1].get("free_ability_name", "")) == "Waaagh!", str(_reroll_events))
	var use: Dictionary = phase.execute_action({"type": "USE_COMMAND_REROLL", "actor_unit_id": "U_KOMMANDOS_A", "player": 1, "payload": {"rng_seed": 99}})
	_check("USE (free) re-rolls and resolves the advance", use.get("success", false) and bool(_flags("U_KOMMANDOS_A").get("advanced", false)), str(use.get("error", "")))
	_check("no CP spent", _cp(1) == cp1, "%d -> %d" % [cp1, _cp(1)])
	var expected := int(RE.RNGService.new(99).roll_d6(1)[0])
	_check("the advance uses the re-rolled die (%d, was %d)" % [expected, rolled], int(phase.active_moves.get("U_KOMMANDOS_A", {}).get("advance_roll", -1)) == expected)

	# Decline keeps the roll.
	_reload()
	_set_detachment(1, "Kult of Speed")
	PM.transition_to_phase(PHASE_MOVEMENT)
	phase = PM.get_current_phase_instance()
	_decline_pending(phase)  # WP-O6: the codex Da Jump is offered at the start of the Movement phase
	phase.execute_action({"type": "BEGIN_ADVANCE", "actor_unit_id": "U_STORMBOYZ_A", "player": 1, "payload": {"rng_seed": _seed_rolling_at_most(5)}})
	_decline_pending(phase)
	var kept := int(phase._reroll_pending_data.get("advance_roll", -1))
	_check("Stormboyz: free re-roll offered", phase._awaiting_reroll_decision)
	phase.execute_action({"type": "DECLINE_COMMAND_REROLL", "actor_unit_id": "U_STORMBOYZ_A", "player": 1})
	_check("DECLINE keeps the rolled %d" % kept, int(phase.active_moves.get("U_STORMBOYZ_A", {}).get("advance_roll", -1)) == kept)
	# A 6 is never offered a re-roll.
	_reload()
	_set_detachment(1, "Kult of Speed")
	PM.transition_to_phase(PHASE_MOVEMENT)
	phase = PM.get_current_phase_instance()
	_decline_pending(phase)  # WP-O6: the codex Da Jump is offered at the start of the Movement phase
	phase.execute_action({"type": "BEGIN_ADVANCE", "actor_unit_id": "U_KOMMANDOS_A", "player": 1, "payload": {"rng_seed": _seed_rolling_exactly(6)}})
	_decline_pending(phase)
	# (The paid Command Re-roll is still offered on a 6 — pre-existing engine
	# behaviour; the free Waaagh! re-roll is not.)
	_check("a 6: the free Waaagh! re-roll is not offered", str(phase._reroll_pending_data.get("free_ability", "x")) == "" or not phase._awaiting_reroll_decision,
		"awaiting=%s pending=%s" % [str(phase._awaiting_reroll_decision), str(phase._reroll_pending_data)])

	# Tutorial: not offered (scripted lessons keep the Command Re-roll flow).
	_reload()
	GS.state.meta["tutorial"] = true
	_check("tutorial: no free re-roll source", ArmyRules.free_advance_reroll_source(GS.state.units.U_KOMMANDOS_A) == "")
	GS.state.meta.erase("tutorial")
	GS.set_edition(10)
	_check("10e: no free re-roll source", ArmyRules.free_advance_reroll_source(GS.state.units.U_KOMMANDOS_A) == "")
	GS.set_edition(11)
	_check("AI policy: re-roll a 1-3, keep a 4+", ArmyRules.ai_take_free_advance_reroll(1) and ArmyRules.ai_take_free_advance_reroll(3)
		and not ArmyRules.ai_take_free_advance_reroll(4))


func _section_da_boss() -> void:
	print("\n-- E. Da Boss --")
	_reload()
	_check("Da Boss warlord found (Warboss)", ArmyRules.da_boss_warlord(1).get("unit_id", "") == "U_WARBOSS_A")
	_check("Custodes have no Da Boss warlord", ArmyRules.da_boss_warlord(2).is_empty())
	# Battle round 3 starts with the first-turn player's (P1) Command phase.
	GS.state.meta["battle_round"] = 3
	GS.state.meta["active_player"] = 1
	var cp1 := _cp(1)
	var cp2 := _cp(2)
	PM.transition_to_phase(PHASE_COMMAND)
	_check("start of battle round 3: Orks +1 core CP +1 Da Boss", _cp(1) == cp1 + 2, "%d -> %d" % [cp1, _cp(1)])
	_check("Custodes: +1 core CP only", _cp(2) == cp2 + 1, "%d -> %d" % [cp2, _cp(2)])
	_check("round marker recorded", int(GS.state.players["1"].get(ArmyRules.P_DA_BOSS_ROUND, 0)) == 3)
	_check("once per battle round (a second call grants nothing)", ArmyRules.on_battle_round_start(3).is_empty())
	var logged := false
	var gel = root.get_node_or_null("GameEventLog")
	if gel and "entries" in gel:
		for e in gel.entries:
			if "Da Boss" in str(e.get("text", e)):
				logged = true
	_check("the Game Log names Da Boss", logged or gel == null)
	# The second player's Command phase is not the start of the battle round.
	var cp_before := _cp(1)
	GS.state.meta["active_player"] = 2
	PM.transition_to_phase(PHASE_COMMAND)
	_check("P2's Command phase (same round): no Da Boss CP", _cp(1) == cp_before + 1, "%d -> %d" % [cp_before, _cp(1)])
	# Warlord without Da Boss -> nothing.
	_reload()
	GS.state.units.U_WARBOSS_A.meta["is_warlord"] = false
	GS.state.units.U_WEIRDBOY_A.meta["is_warlord"] = true
	_check("a Da Boss model that is not the warlord grants nothing", ArmyRules.on_battle_round_start(4).is_empty())
	# Destroyed warlord -> nothing.
	_reload()
	for m in GS.state.units.U_WARBOSS_A.models:
		m["alive"] = false
	_check("a destroyed warlord grants nothing", ArmyRules.on_battle_round_start(4).is_empty())
	_reload()
	GS.set_edition(10)
	_check("10e: no Da Boss CP", ArmyRules.on_battle_round_start(4).is_empty())
	GS.set_edition(11)
	var d := ArmyRules.on_battle_round_start(5)
	_check("warlord alive at 11e: diffs for the CP and the marker", d.size() == 2 and str(d[0].path) == "players.1.cp", str(d))


func _section_unstable_energies() -> void:
	print("\n-- F. Unstable Energies --")
	_reload()
	var wb: Dictionary = GS.state.units.U_WEIRDBOY_A
	_check("Weirdboy psyker level 1 (Waaagh! Energy)", ArmyRules.psyker_level(wb) == 1)
	_check("psychic levels: Da Jump 1, Warpath 1, Roar of Mork 1", ArmyRules.psychic_level("Da Jump") == 1 and ArmyRules.psychic_level("Warpath") == 1 and ArmyRules.psychic_level("Roar of Mork") == 1)
	_check("level from a printed name", ArmyRules.psychic_level("Da Jump (psychic level 2, once per army, per battle round)") == 2)
	_check("psyker level from a printed name", ArmyRules._level_from_text("Waaagh! Energy (psyker level 3)", "psyker") == 3)
	_check("a non-psyker is not budgeted", not ArmyRules.is_budgeted_psyker(GS.state.units.U_BOYZ_B) and ArmyRules.can_use_psychic("U_BOYZ_B", "Warpath").get("ok", false))
	_set_turn(2, 1, PHASE_MOVEMENT)
	_check("fresh round: Warpath allowed", ArmyRules.can_use_psychic("U_WEIRDBOY_A", "Warpath").get("ok", false))
	GS.apply_state_changes(ArmyRules.record_psychic_use("U_WEIRDBOY_A", "Roar of Mork"))
	_check("1 of 1 spent", ArmyRules.psychic_levels_used(GS.state.units.U_WEIRDBOY_A) == 1)
	var chk: Dictionary = ArmyRules.can_use_psychic("U_WEIRDBOY_A", "Warpath")
	_check("over budget: Warpath refused", not chk.get("ok", true) and str(chk.get("code", "")) == "budget" and "Unstable Energies" in str(chk.get("reason", "")), str(chk))
	_check("same ability again this phase: 22.03.01", str(ArmyRules.can_use_psychic("U_WEIRDBOY_A", "Roar of Mork").get("code", "")) == "same_phase")
	_set_turn(2, 1, PHASE_SHOOTING)
	_check("later phase, same round: still over budget", not ArmyRules.can_use_psychic("U_WEIRDBOY_A", "Warpath").get("ok", true))
	_set_turn(3, 1, PHASE_MOVEMENT)
	_check("next battle round: budget reset", ArmyRules.can_use_psychic("U_WEIRDBOY_A", "Warpath").get("ok", false) and ArmyRules.psychic_levels_used(GS.state.units.U_WEIRDBOY_A) == 0)
	# Level override (WP-O5 Warphead hook): psyker level 2 = two level-1 uses.
	GS.state.units.U_WEIRDBOY_A.flags[ArmyRules.F_PSYKER_LEVEL_OVERRIDE] = 2
	GS.apply_state_changes(ArmyRules.record_psychic_use("U_WEIRDBOY_A", "Roar of Mork"))
	_check("psyker level 2: a second level-1 ability still fits", ArmyRules.can_use_psychic("U_WEIRDBOY_A", "Warpath").get("ok", false))
	GS.apply_state_changes(ArmyRules.record_psychic_use("U_WEIRDBOY_A", "Warpath"))
	_check("psyker level 2: a third does not", not ArmyRules.can_use_psychic("U_WEIRDBOY_A", "Da Jump").get("ok", true))
	GS.state.units.U_WEIRDBOY_A.flags.erase(ArmyRules.F_PSYKER_LEVEL_OVERRIDE)

	# The Da Jump path. WP-O6: the 10e USE_DA_JUMP teleport is gone — the codex
	# Da Jump is a Codex: Orks (11e) datasheet ability offered in the
	# movement_phase_start window (OrkAbilities11e), budgeted through this
	# rule's can_use_psychic / record_psychic_use.
	_reload()
	_set_detachment(1, "Kult of Speed")
	PM.transition_to_phase(PHASE_MOVEMENT)
	var phase = PM.get_current_phase_instance()
	var dj_ctx := {"phase": "movement", "window_id": "movement_phase_start"}
	var dj_offered := func() -> bool:
		for o in SM.get_all_window_offers(1, "movement_phase_start", dj_ctx):
			if str(o.get("stratagem_id", "")) == "ork11e_ab_da_jump":
				for t in o.get("targets", []):
					if str(t.get("unit_id", "")) == "U_WEIRDBOY_A":
						return true
		return false
	_check("Da Jump offered at the start of the Movement phase while the budget is free", dj_offered.call())
	GS.apply_state_changes(ArmyRules.record_psychic_use("U_WEIRDBOY_A", "Warpath"))
	_check("Da Jump not offered once the psyker level is spent", not dj_offered.call())
	var res: Dictionary = SM.use_stratagem(1, "ork11e_ab_da_jump", "U_WEIRDBOY_A", dj_ctx)
	_check("using Da Jump anyway is refused", not res.get("success", true), str(res))
	# Fresh budget: Da Jump records its level.
	_reload()
	_set_detachment(1, "Kult of Speed")
	PM.transition_to_phase(PHASE_MOVEMENT)
	phase = PM.get_current_phase_instance()
	_check("the movement_phase_start window is pending (Da Jump on offer)", phase.has_pending_stratagem_window()
		and str(phase.get_pending_stratagem_window().get("window_id", "")) == "movement_phase_start")
	res = phase.execute_action({"type": "USE_WINDOW_STRATAGEM", "player": 1, "window_id": "movement_phase_start",
		"stratagem_id": "ork11e_ab_da_jump", "target_unit_id": "U_WEIRDBOY_A", "context": {}})
	_check("Da Jump with a free budget succeeds", res.get("success", false), str(res.get("error", "")))
	_check("Da Jump spent the psyker level", ArmyRules.psychic_levels_used(GS.state.units.U_WEIRDBOY_A) == 1)
	_decline_pending(phase)
	GS.set_edition(10)
	_check("10e: no budget applies", ArmyRules.can_use_psychic("U_WEIRDBOY_A", "Warpath").get("ok", false))
	GS.set_edition(11)
