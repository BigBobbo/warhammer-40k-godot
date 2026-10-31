extends SceneTree

# FIX_CHARGE_REROLL_ODDS (11e rules audit CH-05 + AR-03, rank 11):
# the AI priced every charge as one 2D6 roll (_charge_success_probability),
# but a Blade Champion has Swift Onslaught ("This unit can: Re-roll advance
# rolls. Re-roll charge rolls."): the engine offers that free re-roll before
# Command Re-roll (ChargePhase: EffectPrimitivesData.has_effect_reroll_charge
# -> ability_reroll_opportunity) and AIPlayer takes it whenever the roll is
# short of the NEAREST declared target (_on_ability_reroll_opportunity).
#   one declared target:   P = 1 - (1 - p)^2          (9": 0.278 -> 0.478)
#   a farther target in a multi-target declaration: P = p x (2 - p_near)
#                          (9" with a 7" target declared too: 0.394)
#
# Mismatch case (mirror_custodes_2000_postdeploy units): a Blade Champion 9"
# from its only target records charge_probability 0.278 at FIX = 0 and 0.478
# at FIX = 1. The multi-target EV (11e: targets picked after the roll) uses
# the re-roll-when-short roll distribution: x (2 - p_near).
# Guards: a Custodian Guard (no re-roll source) is unchanged; a Blade
# Champion 2" away (a sure charge) is unchanged; edition 10 (no 11e Swift
# Onslaught in the engine) is unchanged.
#
# Run with: godot --headless --path . -s tests/unit/test_ai_fix_charge_reroll_odds.gd

const AI_PATH := "res://scripts/AIDecisionMaker.gd"
const AIDifficultyConfig = preload("res://scripts/AIDifficultyConfig.gd")
const FIXTURE := "res://tests/saves/mirror_custodes_2000_postdeploy.w40ksave"
const PX := 40.0  # pixels per inch
const BC := "U_BLADE_CHAMPION_A"          # P1, Swift Onslaught
const CG := "U_CUSTODIAN_GUARD_A"         # P1, no charge re-roll
const FAR := "U_PROSECUTORS_A_P2"         # P2 target
const NEAR := "U_CUSTODIAN_GUARD_A_P2"    # P2 target

var _pass_count: int = 0
var _fail_count: int = 0
var _ran := false
var AIDM = null
var _fx_units: Dictionary = {}

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _gs() -> Node:
	return root.get_node("GameState")

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
	print("\n=== FIX_CHARGE_REROLL_ODDS: charge odds include the free Swift Onslaught re-roll ===\n")
	var prev_edition = GameConstants.edition
	var saved_state: Dictionary = _gs().state.duplicate(true)
	GameConstants.edition = 11
	AIDM = load(AI_PATH)
	AIDM._current_difficulty = AIDifficultyConfig.Difficulty.COMPETITIVE
	_fx_units = _load_fixture_units(FIXTURE)
	_assert(_fx_units.has(BC) and _fx_units.has(CG) and _fx_units.has(FAR) and _fx_units.has(NEAR),
		"setup: the mirror_custodes fixture has %s, %s, %s and %s" % [BC, CG, FAR, NEAR])

	test_blade_champion_single_target_param_one()
	test_blade_champion_single_target_param_zero()
	test_farther_target_formula()
	test_multi_target_ev_uses_reroll_distribution()
	test_custodian_guard_unchanged()
	test_sure_charge_unchanged()
	test_edition_10_unchanged()

	AIDM._config_overrides.erase("FIX_CHARGE_REROLL_ODDS")
	AIDM._charge_coordination.clear()
	GameConstants.edition = prev_edition
	_gs().state = saved_state
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

func _load_fixture_units(path: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string(path)
	var raw: PackedByteArray = Marshalls.base64_to_raw(txt.strip_edges())
	var bytes: PackedByteArray = raw.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	var data = JSON.parse_string(bytes.get_string_from_utf8())
	if not (data is Dictionary):
		return {}
	return data.get("units", {})

func _fx(uid: String, origin: Vector2, step: float) -> Dictionary:
	var u: Dictionary = _fx_units[uid].duplicate(true)
	u["owner"] = int(u.get("owner", 0))
	u["status"] = int(u.get("status", 2))
	u["flags"] = {}
	var i := 0
	for m in u["models"]:
		m["alive"] = true
		m["position"] = {"x": origin.x + float(i) * step, "y": origin.y}
		i += 1
	return u

func _radius_in(uid: String) -> float:
	return float(_fx_units[uid]["models"][0].get("base_mm", 32)) / 2.0 / 25.4

# `charger` at (800, 1200); each target {uid: inches} placed below it, edge to
# edge, its models in a row from x = 800 (its first model straight below the
# charger's first model).
func _board(charger: String, targets: Dictionary) -> Dictionary:
	var units := {}
	units[charger] = _fx(charger, Vector2(800, 1200), 70.0)
	for tid in targets:
		var step := 2.0 * _radius_in(tid) * PX + 8.0
		var y := 1200.0 + (float(targets[tid]) + _radius_in(charger) + _radius_in(tid)) * PX
		units[tid] = _fx(tid, Vector2(800.0, y), step)
	var snap := {"battle_round": 3, "meta": {"battle_round": 3, "active_player": 1},
		"board": {"objectives": [], "terrain_features": [], "deployment_zones": []},
		"factions": {"1": {"name": "Adeptus Custodes", "detachment": "Lions of the Emperor"},
			"2": {"name": "Adeptus Custodes", "detachment": "Lions of the Emperor"}},
		"players": {"1": {"cp": 4, "vp": 0}, "2": {"cp": 0, "vp": 0}},
		"units": units}
	# Swift Onslaught (CustodesAbilities.charge_reroll_source) reads the live GameState.
	_gs().state["units"] = units.duplicate(true)
	_gs().state["meta"]["battle_round"] = 3
	_gs().state["meta"]["active_player"] = 1
	_gs().state["factions"] = snap.factions.duplicate(true)
	_gs().state["players"] = snap.players.duplicate(true)
	return snap

# charge_probability the charge decision record holds for charger -> tid.
func _recorded_prob(snap: Dictionary, charger: String, tid: String, fix: float) -> float:
	AIDM._config_overrides["FIX_CHARGE_REROLL_ODDS"] = fix
	AIDM._charge_coordination.clear()
	AIDM._decision_records.clear()
	var actions := [{"type": "DECLARE_CHARGE", "actor_unit_id": charger, "payload": {"target_unit_ids": [tid]}},
		{"type": "SKIP_CHARGE", "actor_unit_id": charger}, {"type": "END_CHARGE"}]
	AIDM._evaluate_best_charge(snap, actions, 1)
	AIDM._charge_coordination.clear()
	for rec in AIDM._decision_records:
		if str(rec.get("decision_type", "")) != "charge":
			continue
		for c in rec.get("candidates", []):
			if str(c.get("target_unit_id", "")) == tid or str(c.get("key", "")) == "%s|%s" % [charger, tid]:
				return float(c.get("score_breakdown", {}).get("charge_probability", NAN))
	return NAN

func _p2d6(n: int) -> float:
	return float(AIDM._charge_success_probability(float(n)))

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_blade_champion_single_target_param_one():
	var snap := _board(BC, {FAR: 9.0})
	var d := float(AIDM._get_closest_model_distance_inches(snap.units[BC], snap.units[FAR]))
	print("  board: Blade Champion -> Prosecutors %.2f\"" % d)
	_assert(EffectPrimitivesData.has_effect_reroll_charge(snap.units[BC]),
		"setup: the engine grants the Blade Champion a free charge re-roll (Swift Onslaught)")
	var p := _recorded_prob(snap, BC, FAR, 1.0)
	var want := 1.0 - pow(1.0 - _p2d6(9), 2.0)
	print("  FIX=1: charge_probability %.4f (want %.4f)" % [p, want])
	_assert(absf(p - want) < 1e-6 and absf(p - 0.478) < 0.001,
		"FIX=1: Blade Champion 9\" from its only target records 0.478 (got %.4f)" % p)

func test_blade_champion_single_target_param_zero():
	var p := _recorded_prob(_board(BC, {FAR: 9.0}), BC, FAR, 0.0)
	_assert(absf(p - _p2d6(9)) < 1e-9 and absf(p - 0.278) < 0.001,
		"FIX=0: the old plain 2D6 0.278 (got %.4f)" % p)

func test_farther_target_formula():
	# The AI re-rolls only when the roll misses the NEAREST declared target:
	# a 9" target declared with a 7" one gets p9 x (2 - p7).
	var has_fn := false
	for m in AIDM.get_script_method_list():
		if str(m.get("name", "")) == "_charge_odds_with_reroll":
			has_fn = true
	var p := NAN
	if has_fn:
		p = float(AIDM._charge_odds_with_reroll(float(AIDM._charge_roll_needed(9.0)), float(AIDM._charge_roll_needed(7.0))))
	_assert(has_fn and absf(p - _p2d6(9) * (2.0 - _p2d6(7))) < 1e-9 and absf(p - 0.394) < 0.001,
		"helper: 9\" target with a 7\" target declared -> 0.278 x (2 - 0.583) = 0.394 (got %.4f)" % p)

func _combo_ev(snap: Dictionary, charger: String, fix: float) -> float:
	# Two targets (7" and 9"), each with value-if-reached 10 (score = 10 x p).
	AIDM._config_overrides["FIX_CHARGE_REROLL_ODDS"] = fix
	var combo := []
	for tid in [NEAR, FAR]:
		var dist := float(AIDM._get_closest_model_distance_inches(snap.units[charger], snap.units[tid]))
		var need := float(AIDM._charge_roll_needed(dist))
		var p := float(AIDM._charge_success_probability(need))
		combo.append({"target_id": tid, "dist": dist, "score": 10.0 * p, "target_score": 10.0, "melee_dmg": 1.0,
			"target_hp": 10.0, "target_name": tid, "action": {}, "need": need, "prob": p})
	var res: Dictionary = AIDM._score_multi_target_combo(charger, snap.units[charger], charger, combo, 1.0,
		{"expected_damage": 0.0, "best_shooter_name": "", "risk_level": "none", "score_penalty": 1.0}, snap, 1)
	return float(res.get("score", -INF))

func test_multi_target_ev_uses_reroll_distribution():
	var snap := _board(BC, {NEAR: 7.0, FAR: 9.0})
	var ev0 := _combo_ev(snap, BC, 0.0)
	var ev1 := _combo_ev(snap, BC, 1.0)
	var factor := 2.0 - _p2d6(7)  # every roll that reaches a target is >= the nearest need
	print("  multi-target EV: FIX=0 %.4f, FIX=1 %.4f (want x%.4f = %.4f)" % [ev0, ev1, factor, ev0 * factor])
	_assert(ev0 > 0.0 and absf(ev1 - ev0 * factor) < 1e-6,
		"FIX=1: the 2-target EV uses the re-roll-when-short distribution, x(2 - p_near) (%.4f -> %.4f)" % [ev0, ev1])

func test_custodian_guard_unchanged():
	var snap := _board(CG, {FAR: 9.0})
	_assert(not EffectPrimitivesData.has_effect_reroll_charge(snap.units[CG]), "setup: a Custodian Guard has no charge re-roll")
	var a := _recorded_prob(snap, CG, FAR, 0.0)
	var b := _recorded_prob(_board(CG, {FAR: 9.0}), CG, FAR, 1.0)
	_assert(a == b and absf(a - 0.278) < 0.001, "guard: Custodian Guard 9\" — 0.278 at both values (%.4f / %.4f)" % [a, b])
	var snap2 := _board(CG, {NEAR: 7.0, FAR: 9.0})
	var e0 := _combo_ev(snap2, CG, 0.0)
	var e1 := _combo_ev(snap2, CG, 1.0)
	_assert(e0 == e1, "guard: Custodian Guard 2-target EV unchanged (%.4f / %.4f)" % [e0, e1])

func test_sure_charge_unchanged():
	var a := _recorded_prob(_board(BC, {FAR: 1.5}), BC, FAR, 0.0)
	var b := _recorded_prob(_board(BC, {FAR: 1.5}), BC, FAR, 1.0)
	_assert(a == 1.0 and b == 1.0, "guard: Blade Champion 1.5\" away — 1.0 at both values (%.4f / %.4f)" % [a, b])

func test_edition_10_unchanged():
	GameConstants.edition = 10
	var a := _recorded_prob(_board(BC, {FAR: 9.0}), BC, FAR, 0.0)
	var b := _recorded_prob(_board(BC, {FAR: 9.0}), BC, FAR, 1.0)
	GameConstants.edition = 11
	_assert(a == b, "guard: edition 10 (no 11e Swift Onslaught re-roll) — the same odds at both values (%.4f / %.4f)" % [a, b])
