extends SceneTree

# FIX_CO_NEXT_PICK (11e rules audit CO-01, rank 9):
# COUNTEROFFENSIVE (2 CP) is offered to the non-active player after every
# enemy activation (FightPhase._after_enemy_has_fought_window), and
# evaluate_counter_offensive bought it from melee / value / keyword / wounds
# terms alone, as if it were the only way to "fight next".
#
# 15.12 COUNTEROFFENSIVE: "your unit has the Fights First ability and it must
# be the next unit you select to fight (12.04)". 12.04: players alternate. After
# an enemy unit fought, the defender already selects next (FightSequencer
# select_to_fight hands the pick over; next_selection keeps it with the
# defender unless the attacker still has an eligible Fights First unit and the
# defender has none). CO is pure waste — under 12.04 AND under the engine,
# whose CO-02 bug keeps the pick with the CO player — when the attacker has no
# eligible Fights First unit left AND either the CO unit is the defender's
# only eligible unit or the attacker has no eligible unit at all.
#
# Cases (live FightPhase + FightSequencer, P1 active, P2 deciding, CP 4):
#  (a1) the attacker's only charger has fought, the attacker still has a non-
#       Fights-First engaged unit, the defender has ONE eligible unit:
#       FIX=0 USE_COUNTER_OFFENSIVE, FIX=1 DECLINE_COUNTER_OFFENSIVE.
#  (a2) the attacker's only unit has fought, the defender has TWO eligible
#       units: FIX=0 USE, FIX=1 DECLINE.
#  (g1) an attacker Fights First unit (a second charger) is still eligible:
#       USE at both values (CO lets the defender strike before it).
#  (g2) the attacker has a non-Fights-First unit left and the defender has two
#       eligible units (the engine's CO-02 double activation is real value):
#       USE at both values.
#  (g3) no live Fight phase / sequencer: USE at both values (fix inert).
#  (g4) CP 2 (the CO cost) with a low-value candidate: the old "saving CP"
#       decline at FIX=0, a decline at FIX=1 too.
#
# Run with: godot --headless --path . -s tests/unit/test_ai_fix_co_next_pick.gd

const AI_PATH := "res://scripts/AIDecisionMaker.gd"
const PARAM := "FIX_CO_NEXT_PICK"

var _pass_count: int = 0
var _fail_count: int = 0
var _ran := false
var AIDM = null

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.2).timeout.connect(_run_tests)

func _gs() -> Node:
	return root.get_node("GameState")

func _pm() -> Node:
	return root.get_node("PhaseManager")

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

func _run_tests():
	if _ran:
		return
	_ran = true
	await process_frame
	print("\n=== FIX_CO_NEXT_PICK: no Counteroffensive when it cannot change who fights next ===\n")
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	var aip = root.get_node("AIPlayer")
	aip.enabled = false
	AIDM = load(AI_PATH)

	test_no_live_sequencer_is_inert()
	test_only_unit_left_declines()
	test_attacker_has_nothing_left_declines()
	test_attacker_fights_first_unit_left_keeps_co()
	test_engine_double_activation_keeps_co()
	test_cp_tight_low_value_declines_both()

	AIDM._config_overrides.erase(PARAM)
	GameConstants.edition = prev_edition
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)

# --- board helpers -----------------------------------------------------------

const SWORD := {"name": "Power sword", "type": "Melee", "range": "Melee", "attacks": "3", "weapon_skill": "3",
	"strength": "5", "ap": "-2", "damage": "1", "special_rules": ""}

func _model(mid: String, x: float, y: float) -> Dictionary:
	return {"id": mid, "alive": true, "wounds": 3, "current_wounds": 3, "base_mm": 32,
		"base_type": "circular", "base_dimensions": {}, "position": {"x": x, "y": y}}

# Three 32mm models in a row (52 px apart: 1.6 px edge gap) starting at x, y.
func _row(prefix: String, x: float, y: float) -> Array:
	var out: Array = []
	for i in range(3):
		out.append(_model("%s%d" % [prefix, i], x + 52.0 * i, y))
	return out

func _unit(uid: String, owner: int, name: String, models: Array, flags: Dictionary = {}) -> Dictionary:
	return {"id": uid, "owner": owner, "status": 2, "flags": flags.duplicate(),
		"meta": {"name": name, "points": 120, "keywords": ["INFANTRY"],
			"stats": {"move": 6, "toughness": 5, "save": 3, "wounds": 3, "leadership": 6, "objective_control": 2},
			"weapons": [SWORD], "abilities": []},
		"models": models}

const CHARGED := {"charged_this_turn": true, "fights_first": true}

# P2's DEF row at y=1000; P1's CHG directly above (base contact), P1's NFF
# directly below (base contact); P2's DEF2 above CHG (base contact).
func _def() -> Dictionary:
	return _unit("DEF", 2, "Defender Guard", _row("d", 800, 1000))
func _def2() -> Dictionary:
	return _unit("DEF2", 2, "Second Defender", _row("e", 800, 896))
func _chg() -> Dictionary:
	return _unit("CHG", 1, "Charger", _row("c", 800, 948), CHARGED)
func _ff2() -> Dictionary:
	# A second charger engaged with DEF from the right (Fights First).
	return _unit("FF2", 1, "Second Charger", [_model("f0", 956, 1000), _model("f1", 1008, 1000), _model("f2", 1060, 1000)], CHARGED)
func _nff() -> Dictionary:
	return _unit("NFF", 1, "Engaged Boyz", _row("n", 800, 1052))

# Enter a fresh Fight phase on `units` (P1 active), close the 12.02 Pile In
# step, and let the attacker's charger CHG fight (select_to_fight hands the
# pick to P2 and marks it fought), as the engine does before the CO window.
func _enter_fight_after_charger(units: Dictionary, cp: int) -> Node:
	var gs = _gs()
	var pm = _pm()
	gs.state["units"] = units
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["battle_round"] = 2
	gs.state["meta"]["phase"] = 10
	pm.transition_to_phase(10)
	var fp = pm.get_current_phase_instance()
	if fp.phase_completed.is_connected(pm._on_phase_completed):
		fp.phase_completed.disconnect(pm._on_phase_completed)
	for _i in range(2):
		if int(fp.pile_in_step_11e) != int(fp.PileInStep11e.ACTIVE):
			break
		fp.execute_action({"type": "END_PILE_IN", "player": int(fp.piling_in_player_11e)})
	fp.sequencer_11e.select_to_fight("CHG", gs.state)
	gs.state["players"]["1"]["cp"] = 4
	gs.state["players"]["2"]["cp"] = cp
	return fp

func _co_candidates(fp, player: int) -> Array:
	var out: Array = []
	for uid in fp.sequencer_11e.eligible_units(_gs().state, player, false):
		out.append({"unit_id": uid, "unit_name": _gs().state.units[uid].meta.name})
	return out

func _decide(eligible: Array, fix: float) -> Dictionary:
	AIDM._config_overrides[PARAM] = fix
	print("  --- %s = %.0f ---" % [PARAM, fix])
	var snapshot: Dictionary = _gs().create_snapshot(false)
	var d: Dictionary = AIDM.evaluate_counter_offensive(2, eligible, snapshot)
	print("  -> %s %s | %s" % [str(d.get("type", "")), str(d.get("unit_id", "")), str(d.get("_ai_description", ""))])
	return d

# --- cases -------------------------------------------------------------------

func test_no_live_sequencer_is_inert():
	print("\n-- (g3) no live Fight phase: the fix has nothing to read --")
	var gs = _gs()
	var pm = _pm()
	gs.state["units"] = {"CHG": _chg(), "DEF": _def()}
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["battle_round"] = 2
	gs.state["players"]["2"]["cp"] = 4
	var phase = pm.get_current_phase_instance()
	var has_seq: bool = phase != null and "sequencer_11e" in phase and phase.sequencer_11e != null
	_assert(not has_seq, "set-up: no live fight sequencer before the Fight phase is entered")
	var eligible = [{"unit_id": "DEF", "unit_name": "Defender Guard"}]
	var d0 = _decide(eligible, 0.0)
	var d1 = _decide(eligible, 1.0)
	_assert(str(d0.get("type", "")) == "USE_COUNTER_OFFENSIVE" and str(d0.get("unit_id", "")) == "DEF",
		"no sequencer, FIX=0: USE_COUNTER_OFFENSIVE on DEF (got %s)" % str(d0.get("type", "")))
	_assert(JSON.stringify(d0) == JSON.stringify(d1),
		"no sequencer: FIX=1 returns exactly the FIX=0 decision (%s vs %s)" % [str(d1.get("type", "")), str(d0.get("type", ""))])

func test_only_unit_left_declines():
	print("\n-- (a1) the attacker's only Fights First unit has fought; DEF is P2's only eligible unit --")
	var fp = _enter_fight_after_charger({"CHG": _chg(), "NFF": _nff(), "DEF": _def()}, 4)
	var seq = fp.sequencer_11e
	_assert(seq.selectable_units(_gs().state, 1, true).is_empty(), "set-up: P1 has no eligible Fights First unit left")
	_assert(seq.selectable_units(_gs().state, 1, false) == ["NFF"], "set-up: P1 still has NFF to fight (%s)" % str(seq.selectable_units(_gs().state, 1, false)))
	var peek: Dictionary = seq.peek_selection(_gs().state)
	_assert(int(peek.get("player", 0)) == 2 and peek.get("candidates", []) == ["DEF"],
		"set-up (12.04): without CO, P2 already selects DEF next (%s)" % str(peek))
	var eligible = _co_candidates(fp, 2)
	var d0 = _decide(eligible, 0.0)
	_assert(str(d0.get("type", "")) == "USE_COUNTER_OFFENSIVE" and str(d0.get("unit_id", "")) == "DEF" and int(d0.get("cp_cost", 0)) == 2,
		"FIX=0 (old): USE_COUNTER_OFFENSIVE on DEF for 2 CP (got %s %s)" % [str(d0.get("type", "")), str(d0.get("unit_id", ""))])
	var d1 = _decide(eligible, 1.0)
	_assert(str(d1.get("type", "")) == "DECLINE_COUNTER_OFFENSIVE" and int(d1.get("player", 0)) == 2,
		"FIX=1: DECLINE_COUNTER_OFFENSIVE — DEF fights next anyway (got %s)" % str(d1.get("type", "")))

func test_attacker_has_nothing_left_declines():
	print("\n-- (a2) the attacker's only unit has fought; P2 has two eligible units --")
	var fp = _enter_fight_after_charger({"CHG": _chg(), "DEF": _def(), "DEF2": _def2()}, 4)
	var seq = fp.sequencer_11e
	_assert(seq.selectable_units(_gs().state, 1, false).is_empty(), "set-up: P1 has no eligible unit left")
	var mine: Array = seq.eligible_units(_gs().state, 2, false)
	mine.sort()
	_assert(mine == ["DEF", "DEF2"], "set-up: P2 has DEF and DEF2 eligible (%s)" % str(mine))
	var eligible = _co_candidates(fp, 2)
	var d0 = _decide(eligible, 0.0)
	_assert(str(d0.get("type", "")) == "USE_COUNTER_OFFENSIVE",
		"FIX=0 (old): USE_COUNTER_OFFENSIVE (got %s %s)" % [str(d0.get("type", "")), str(d0.get("unit_id", ""))])
	var d1 = _decide(eligible, 1.0)
	_assert(str(d1.get("type", "")) == "DECLINE_COUNTER_OFFENSIVE",
		"FIX=1: DECLINE_COUNTER_OFFENSIVE — nothing of P1's is left to fight (got %s)" % str(d1.get("type", "")))

func test_attacker_fights_first_unit_left_keeps_co():
	print("\n-- (g1) a second P1 charger (Fights First) is still eligible --")
	var fp = _enter_fight_after_charger({"CHG": _chg(), "FF2": _ff2(), "DEF": _def()}, 4)
	var seq = fp.sequencer_11e
	_assert(seq.selectable_units(_gs().state, 1, true) == ["FF2"], "set-up: P1 still has FF2 (Fights First) eligible (%s)" % str(seq.selectable_units(_gs().state, 1, true)))
	var peek: Dictionary = seq.peek_selection(_gs().state)
	_assert(int(peek.get("player", 0)) == 1, "set-up (12.04): without CO, P1 selects FF2 before DEF (%s)" % str(peek))
	var eligible = _co_candidates(fp, 2)
	var d0 = _decide(eligible, 0.0)
	var d1 = _decide(eligible, 1.0)
	_assert(str(d0.get("type", "")) == "USE_COUNTER_OFFENSIVE", "attacker FF unit left, FIX=0: USE (got %s)" % str(d0.get("type", "")))
	_assert(JSON.stringify(d0) == JSON.stringify(d1), "attacker FF unit left, FIX=1: the same USE decision (got %s)" % str(d1.get("type", "")))

func test_engine_double_activation_keeps_co():
	print("\n-- (g2) P1 has a non-Fights-First unit left, P2 has two eligible units --")
	var fp = _enter_fight_after_charger({"CHG": _chg(), "NFF": _nff(), "DEF": _def(), "DEF2": _def2()}, 4)
	var seq = fp.sequencer_11e
	_assert(seq.selectable_units(_gs().state, 1, true).is_empty() and seq.selectable_units(_gs().state, 1, false) == ["NFF"],
		"set-up: P1 has only NFF (not Fights First) left")
	var eligible = _co_candidates(fp, 2)
	_assert(eligible.size() == 2, "set-up: P2 has two Counteroffensive candidates (%d)" % eligible.size())
	var d0 = _decide(eligible, 0.0)
	var d1 = _decide(eligible, 1.0)
	_assert(str(d0.get("type", "")) == "USE_COUNTER_OFFENSIVE", "double activation possible, FIX=0: USE (got %s)" % str(d0.get("type", "")))
	_assert(JSON.stringify(d0) == JSON.stringify(d1), "double activation possible, FIX=1: the same USE decision (got %s)" % str(d1.get("type", "")))

func test_cp_tight_low_value_declines_both():
	print("\n-- (g4) CP 2 (exactly the cost), low-value candidate: declined at both values --")
	var units = {"CHG": _chg(), "NFF": _nff(), "DEF": _def()}
	# One unwounded model: score 2.0 + 1.5*0.4 + 1.5 (two enemy units close)
	# = 4.1, below the 5.0 a last-CP Counteroffensive needs ("saving CP").
	units["DEF"]["models"] = [_model("d0", 800, 1000)]
	var fp = _enter_fight_after_charger(units, 2)
	var eligible = _co_candidates(fp, 2)
	var d0 = _decide(eligible, 0.0)
	var d1 = _decide(eligible, 1.0)
	_assert(str(d0.get("type", "")) == "DECLINE_COUNTER_OFFENSIVE", "low value, FIX=0: DECLINE (got %s)" % str(d0.get("type", "")))
	_assert(str(d1.get("type", "")) == "DECLINE_COUNTER_OFFENSIVE", "low value, FIX=1: DECLINE (got %s)" % str(d1.get("type", "")))
