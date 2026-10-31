extends SceneTree

# FIX_CHARGE_OW_11E (11e rules audit CH-01 + OW-01, rank 2):
# every charge score was multiplied by the T7-51 Fire Overwatch penalty
# (_estimate_overwatch_risk: the best enemy gun within 24", defender CP >= 1).
# 11e 15.08 FIRE OVERWATCH — WHEN: "End of your opponent's Movement phase.
# TARGET: One friendly unengaged unit (excluding TITANIC units)." The engine
# opens no overwatch window when a charge is declared (ChargePhase: "[11e
# 15.08] no Fire Overwatch against charging ..."), and the dominant source of
# the penalty on the bench, the Ork Stompa, is TITANIC and can never overwatch.
#
# Mismatch case (asym_2000_postdeploy units): Custodian Guard 8" from Gretchin,
# the Stompa within 24", P2 CP 2.
#   FIX = 0: the charge record has a negative 'ch_overwatch_risk' term
#            (records store multipliers as additive deltas).
#   FIX = 1: no 'ch_overwatch_risk' term, and the target score equals the
#            score with P2 CP 0 (no overwatch possible either way).
# Guards: edition 10 keeps the penalty at both values; P2 CP 0 and a board
# with no dangerous gun in 24" score the same at both values.
#
# Run with: godot --headless --path . -s tests/unit/test_ai_fix_charge_ow_11e.gd

const AI_PATH := "res://scripts/AIDecisionMaker.gd"
const AIDifficultyConfig = preload("res://scripts/AIDifficultyConfig.gd")
const FIXTURE := "res://tests/saves/asym_2000_postdeploy.w40ksave"
const PX := 40.0  # pixels per inch
const CG := "U_CUSTODIAN_GUARD_A"
const GRETCHIN := "U_GRETCHIN_A"
const STOMPA := "U_STOMPA_A"

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
	print("\n=== FIX_CHARGE_OW_11E: no charge-time Fire Overwatch penalty at 11e ===\n")
	var prev_edition = GameConstants.edition
	var saved_state: Dictionary = _gs().state.duplicate(true)
	GameConstants.edition = 11
	AIDM = load(AI_PATH)
	AIDM._current_difficulty = AIDifficultyConfig.Difficulty.COMPETITIVE  # no score noise
	_fx_units = _load_fixture_units(FIXTURE)
	_assert(_fx_units.has(CG) and _fx_units.has(GRETCHIN) and _fx_units.has(STOMPA),
		"setup: the asym fixture has %s, %s and %s" % [CG, GRETCHIN, STOMPA])

	test_mismatch_param_one_drops_the_penalty()
	test_param_zero_keeps_the_old_penalty()
	test_edition_10_unchanged()
	test_no_cp_unchanged()
	test_no_gun_in_range_unchanged()

	AIDM._config_overrides.erase("FIX_CHARGE_OW_11E")
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

# A fixture unit, its models laid out in rows of 5 from `origin` (spacing
# `step` px), facing +y.
func _fx(uid: String, origin: Vector2, step: float) -> Dictionary:
	var u: Dictionary = _fx_units[uid].duplicate(true)
	u["owner"] = int(u.get("owner", 0))
	u["status"] = int(u.get("status", 2))
	u["flags"] = {}
	var i := 0
	for m in u["models"]:
		m["alive"] = true
		m["position"] = {"x": origin.x + float(i % 5) * step, "y": origin.y + float(i / 5) * step}
		i += 1
	return u

func _radius_in(u: Dictionary) -> float:
	return float(u["models"][0].get("base_mm", 32)) / 2.0 / 25.4

# Custodian Guard (P1) with the Gretchin `gretchin_in` inches ahead (edge to
# edge) and the Stompa `stompa_in` inches behind it (edge to edge).
func _board(p2_cp: int, gretchin_in: float = 8.0, stompa_in: float = 12.0) -> Dictionary:
	var cg := _fx(CG, Vector2(800, 1200), 70.0)
	var gr_probe := _fx(GRETCHIN, Vector2.ZERO, 50.0)
	var st_probe := _fx(STOMPA, Vector2.ZERO, 0.0)
	var gr_y := 1200.0 + (gretchin_in + _radius_in(cg) + _radius_in(gr_probe)) * PX
	var gr := _fx(GRETCHIN, Vector2(800, gr_y), 50.0)
	var st_y := 1200.0 - (stompa_in + _radius_in(cg) + _radius_in(st_probe)) * PX
	var st := _fx(STOMPA, Vector2(880, st_y), 0.0)
	var units := {CG: cg, GRETCHIN: gr, STOMPA: st}
	var snap := {"battle_round": 3, "meta": {"battle_round": 3, "active_player": 1},
		"board": {"objectives": [], "terrain_features": [], "deployment_zones": []},
		"factions": {"1": {"name": "Adeptus Custodes", "detachment": "Lions of the Emperor"},
			"2": {"name": "Orks", "detachment": "Kult of Speed"}},
		"players": {"1": {"cp": 4, "vp": 0, "primary_vp": 0, "secondary_vp": 0},
			"2": {"cp": p2_cp, "vp": 0, "primary_vp": 0, "secondary_vp": 0}},
		"units": units}
	# Engine helpers the scoring calls read the live GameState.
	_gs().state["units"] = units.duplicate(true)
	_gs().state["meta"]["battle_round"] = 3
	_gs().state["meta"]["active_player"] = 1
	_gs().state["factions"] = snap.factions.duplicate(true)
	_gs().state["players"] = snap.players.duplicate(true)
	return snap

func _charge_actions() -> Array:
	return [{"type": "DECLARE_CHARGE", "actor_unit_id": CG, "payload": {"target_unit_ids": [GRETCHIN]}},
		{"type": "SKIP_CHARGE", "actor_unit_id": CG}, {"type": "END_CHARGE"}]

# _evaluate_best_charge on the board; returns the Gretchin candidate of the
# charge decision record: {score, terms (score_breakdown), declared}.
func _eval(snap: Dictionary, fix: float) -> Dictionary:
	AIDM._config_overrides["FIX_CHARGE_OW_11E"] = fix
	AIDM._charge_coordination.clear()
	AIDM._decision_records.clear()
	var res: Dictionary = AIDM._evaluate_best_charge(snap, _charge_actions(), 1)
	var out := {"score": NAN, "terms": {}, "declared": not res.is_empty()}
	for rec in AIDM._decision_records:
		if str(rec.get("decision_type", "")) != "charge":
			continue
		for c in rec.get("candidates", []):
			if str(c.get("target_unit_id", "")) == GRETCHIN or str(c.get("key", "")) == "%s|%s" % [CG, GRETCHIN]:
				out.score = float(c.get("score", NAN))
				out.terms = c.get("score_breakdown", {})
	AIDM._charge_coordination.clear()
	return out

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_mismatch_param_one_drops_the_penalty():
	var snap := _board(2)
	var d := float(AIDM._get_closest_model_distance_inches(snap.units[CG], snap.units[GRETCHIN]))
	var ds := float(AIDM._get_closest_model_distance_inches(snap.units[CG], snap.units[STOMPA]))
	print("  board: Custodian Guard -> Gretchin %.2f\", -> Stompa %.2f\"" % [d, ds])
	_assert(absf(d - 8.0) < 0.05 and ds <= 24.0, "setup: Gretchin 8\" away, Stompa within 24\" (%.2f\", %.2f\")" % [d, ds])
	var risk: Dictionary = AIDM._estimate_overwatch_risk(snap.units[CG], snap, 1)
	print("  old T7-51 estimate: %.2f dmg from %s, penalty x%.2f" % [float(risk.expected_damage), str(risk.best_shooter_name), float(risk.score_penalty)])
	_assert(float(risk.score_penalty) < 1.0, "setup: the T7-51 estimate penalises this charge (x%.2f)" % float(risk.score_penalty))
	var with_cp := _eval(snap, 1.0)
	var no_cp := _eval(_board(0), 0.0)
	print("  FIX=1, P2 CP 2: score %.4f terms %s" % [float(with_cp.score), str(with_cp.terms)])
	print("  FIX=0, P2 CP 0: score %.4f" % float(no_cp.score))
	_assert(not is_nan(float(with_cp.score)), "FIX=1: the charge record has the Gretchin candidate")
	_assert(not (with_cp.terms as Dictionary).has("ch_overwatch_risk"),
		"FIX=1 (11e): no 'ch_overwatch_risk' term in the charge record (terms %s)" % str((with_cp.terms as Dictionary).keys()))
	_assert(is_equal_approx(float(with_cp.score), float(no_cp.score)),
		"FIX=1 (11e): the score with P2 CP 2 equals the score with P2 CP 0 (%.4f vs %.4f)" % [float(with_cp.score), float(no_cp.score)])

func test_param_zero_keeps_the_old_penalty():
	var old := _eval(_board(2), 0.0)
	var no_cp := _eval(_board(0), 0.0)
	var ow := float((old.terms as Dictionary).get("ch_overwatch_risk", 0.0))
	print("  FIX=0, P2 CP 2: score %.4f, ch_overwatch_risk %.4f" % [float(old.score), ow])
	_assert((old.terms as Dictionary).has("ch_overwatch_risk") and ow < 0.0,
		"FIX=0: the old negative 'ch_overwatch_risk' term is back (%.4f)" % ow)
	_assert(float(old.score) < float(no_cp.score),
		"FIX=0: the old penalty lowers the score (%.4f < %.4f)" % [float(old.score), float(no_cp.score)])

func test_edition_10_unchanged():
	GameConstants.edition = 10
	var a := _eval(_board(2), 0.0)
	var b := _eval(_board(2), 1.0)
	GameConstants.edition = 11
	print("  edition 10: FIX=0 %.4f %s / FIX=1 %.4f %s" % [float(a.score), str(a.terms.get("ch_overwatch_risk", "-")),
		float(b.score), str(b.terms.get("ch_overwatch_risk", "-"))])
	_assert(float(a.score) == float(b.score) and (a.terms as Dictionary).has("ch_overwatch_risk")
		and (b.terms as Dictionary).has("ch_overwatch_risk"),
		"guard: edition 10 keeps the overwatch penalty at both values (%.4f vs %.4f)" % [float(a.score), float(b.score)])

func test_no_cp_unchanged():
	var a := _eval(_board(0), 0.0)
	var b := _eval(_board(0), 1.0)
	_assert(float(a.score) == float(b.score) and a.declared == b.declared,
		"guard: P2 CP 0 — the same score and decision at both values (%.4f vs %.4f)" % [float(a.score), float(b.score)])

func test_no_gun_in_range_unchanged():
	# The Stompa 40" behind: only the Gretchin (12" guns) are in 24" — a
	# negligible estimate, penalty x1.0 at both values.
	var snap := _board(2, 8.0, 40.0)
	var risk: Dictionary = AIDM._estimate_overwatch_risk(snap.units[CG], snap, 1)
	var a := _eval(snap, 0.0)
	var b := _eval(_board(2, 8.0, 40.0), 1.0)
	_assert(float(risk.score_penalty) == 1.0 and float(a.score) == float(b.score) and a.declared == b.declared,
		"guard: no dangerous gun within 24\" (penalty x%.2f) — the same score at both values (%.4f vs %.4f)" % [
			float(risk.score_penalty), float(a.score), float(b.score)])
