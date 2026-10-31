extends SceneTree

# FIX_HI_CHARGE_ODDS (11e rules audit CH-03 + HI-01, rank 7):
# evaluate_heroic_intervention valued a counter-charge without the 2D6 charge
# roll the engine makes AFTER the CP is spent (ChargePhase
# _process_use_heroic_intervention: target per mode, use_stratagem, then 2D6;
# INTO THE FRAY capped at 6; a short roll fails and the CP is gone), and chose
# LEAP TO DEFEND whenever any charged enemy was within 12".
# 15.11 HEROIC INTERVENTION: "Resolve a charge with your unit (11.02) ...
# Leap to Defend: ... only select enemy units that made a charge move this
# phase and are within the maximum distance. Into the Fray: ... if the result
# is greater than 6, change it to 6." 11.04: targets within the maximum distance.
#
# Mismatch case (asym_2000_postdeploy units, Custodes defending):
#   one eligible Custodian Guard, the nearest charged enemy 11" away, no enemy
#   within 6", CP 3 — FIX = 0: USE (leap_to_defend); FIX = 1: DECLINE
#   (P(2D6 >= 11) = 8%). Add an enemy 4" away — FIX = 1: USE with mode
#   into_the_fray, and the engine finds that target for the mode
#   (ChargePhase._closest_hi_target_11e) and its roll test agrees with the need.
# Guards: a charged enemy at 7" (58%) is still used as a Leap at both values;
# a charged enemy 4" away is a Leap at both values (same target either mode);
# CP 0 declines at both values.
#
# Run with: godot --headless --path . -s tests/unit/test_ai_fix_hi_charge_odds.gd

const AI_PATH := "res://scripts/AIDecisionMaker.gd"
const AIDifficultyConfig = preload("res://scripts/AIDifficultyConfig.gd")
const FIXTURE := "res://tests/saves/asym_2000_postdeploy.w40ksave"
const PX := 40.0  # pixels per inch
const CG := "U_CUSTODIAN_GUARD_A"   # P1 (defender)
const BIKES := "U_WARBIKERS_A"      # P2, charged this turn
const STORMBOYZ := "U_STORMBOYZ_A"  # P2, did not charge

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
	print("\n=== FIX_HI_CHARGE_ODDS: Heroic Intervention priced with its 2D6 charge roll ===\n")
	var prev_edition = GameConstants.edition
	var saved_state: Dictionary = _gs().state.duplicate(true)
	GameConstants.edition = 11
	AIDM = load(AI_PATH)
	AIDM._current_difficulty = AIDifficultyConfig.Difficulty.COMPETITIVE
	_fx_units = _load_fixture_units(FIXTURE)
	_assert(_fx_units.has(CG) and _fx_units.has(BIKES) and _fx_units.has(STORMBOYZ),
		"setup: the asym fixture has %s, %s and %s" % [CG, BIKES, STORMBOYZ])

	test_far_leap_declined()
	test_fray_chosen_over_far_leap()
	test_param_zero_old_behaviour()
	test_near_leap_kept()
	test_charged_enemy_within_6_stays_leap()
	test_no_cp_declines()

	AIDM._config_overrides.erase("FIX_HI_CHARGE_ODDS")
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

func _fx(uid: String, origin: Vector2, step: float, flags: Dictionary = {}) -> Dictionary:
	var u: Dictionary = _fx_units[uid].duplicate(true)
	u["owner"] = int(u.get("owner", 0))
	u["status"] = int(u.get("status", 2))
	u["flags"] = flags.duplicate()
	var i := 0
	for m in u["models"]:
		m["alive"] = true
		m["position"] = {"x": origin.x + float(i) * step, "y": origin.y}
		i += 1
	return u

func _radius_in(uid: String) -> float:
	return float(_fx_units[uid]["models"][0].get("base_mm", 32)) / 2.0 / 25.4

# Custodian Guard row at y=1200; the charged Warbikers `bikes_in` inches below
# it (edge to edge); the Stormboyz `boyz_in` inches above it (0 = off board).
func _board(cp: int, bikes_in: float, boyz_in: float = 0.0) -> Dictionary:
	var units := {}
	units[CG] = _fx(CG, Vector2(800, 1200), 70.0)
	var by := 1200.0 + (bikes_in + _radius_in(CG) + _radius_in(BIKES)) * PX
	units[BIKES] = _fx(BIKES, Vector2(800, by), 90.0, {"charged_this_turn": true})
	if boyz_in > 0.0:
		var sy := 1200.0 - (boyz_in + _radius_in(CG) + _radius_in(STORMBOYZ)) * PX
		units[STORMBOYZ] = _fx(STORMBOYZ, Vector2(800, sy), 60.0)
	var snap := {"battle_round": 3, "meta": {"battle_round": 3, "active_player": 2},
		"board": {"objectives": [], "terrain_features": [], "deployment_zones": []},
		"factions": {"1": {"name": "Adeptus Custodes", "detachment": "Lions of the Emperor"},
			"2": {"name": "Orks", "detachment": "Kult of Speed"}},
		"players": {"1": {"cp": cp, "vp": 0}, "2": {"cp": 3, "vp": 0}},
		"units": units}
	# StratagemManager's 11e HI eligibility reads the live GameState.
	_gs().state["units"] = units.duplicate(true)
	_gs().state["meta"]["battle_round"] = 3
	_gs().state["meta"]["active_player"] = 2
	_gs().state["factions"] = snap.factions.duplicate(true)
	_gs().state["players"] = snap.players.duplicate(true)
	return snap

func _hi(snap: Dictionary, fix: float) -> Dictionary:
	AIDM._config_overrides["FIX_HI_CHARGE_ODDS"] = fix
	AIDM._decision_records.clear()
	var d: Dictionary = AIDM.evaluate_heroic_intervention(1, "", snap)
	print("  FIX=%d -> %s mode=%s (%s)" % [int(fix), d.get("type", ""), str(d.get("mode", "-")), str(d.get("_ai_description", ""))])
	return d

func _dist(snap: Dictionary, a: String, b: String) -> float:
	return float(AIDM._get_closest_model_distance_inches(snap.units[a], snap.units[b]))

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_far_leap_declined():
	var snap := _board(3, 11.0)
	print("  board: Custodian Guard -> charged Warbikers %.2f\"" % _dist(snap, CG, BIKES))
	var eligible: Array = root.get_node("StratagemManager").get_heroic_intervention_eligible_units_11e(1)
	_assert(eligible.size() == 1 and str(eligible[0].get("unit_id", "")) == CG,
		"setup: the engine offers the Custodian Guard alone (%s)" % str(eligible))
	var d := _hi(snap, 1.0)
	_assert(str(d.get("type", "")) == "DECLINE_HEROIC_INTERVENTION",
		"FIX=1: a Leap to Defend needing 11 on 2D6 (8%%) is declined (got %s %s)" % [d.get("type", ""), str(d.get("mode", ""))])

func test_fray_chosen_over_far_leap():
	var snap := _board(3, 11.0, 4.0)
	var d_fray := _dist(snap, CG, STORMBOYZ)
	print("  board: charged Warbikers %.2f\", Stormboyz %.2f\"" % [_dist(snap, CG, BIKES), d_fray])
	var d := _hi(snap, 1.0)
	_assert(str(d.get("type", "")) == "USE_HEROIC_INTERVENTION" and str(d.get("unit_id", "")) == CG
		and str(d.get("mode", "")) == "into_the_fray",
		"FIX=1: an enemy 4\" away -> USE with mode into_the_fray (got %s mode=%s)" % [d.get("type", ""), str(d.get("mode", ""))])
	# The engine: _process_use_heroic_intervention picks the mode's target with
	# _closest_hi_target_11e (a USE whose mode has no target fails), and the
	# roll test accepts the roll the AI priced (need 4) and not one less.
	var cp_node = load("res://phases/ChargePhase.gd").new()
	root.add_child(cp_node)
	var picked: String = cp_node._closest_hi_target_11e(CG, 1, 6.0, false)
	var need := ceili(float(AIDM._charge_roll_needed(d_fray)))
	var ok_need: bool = cp_node._is_heroic_intervention_roll_sufficient(CG, need, [picked])
	var ok_less: bool = cp_node._is_heroic_intervention_roll_sufficient(CG, need - 1, [picked])
	root.remove_child(cp_node)
	cp_node.free()
	_assert(picked == STORMBOYZ, "engine: into_the_fray resolves to the Stormboyz target (got '%s')" % picked)
	_assert(need == 4 and ok_need and not ok_less,
		"engine: the HI roll test accepts %d and rejects %d for the 4\" target (%s / %s)" % [need, need - 1, str(ok_need), str(ok_less)])

func test_param_zero_old_behaviour():
	var d := _hi(_board(3, 11.0), 0.0)
	_assert(str(d.get("type", "")) == "USE_HEROIC_INTERVENTION" and str(d.get("mode", "")) == "leap_to_defend",
		"FIX=0: the old USE with leap_to_defend at 11\" (got %s mode=%s)" % [d.get("type", ""), str(d.get("mode", ""))])
	d = _hi(_board(3, 11.0, 4.0), 0.0)
	_assert(str(d.get("type", "")) == "USE_HEROIC_INTERVENTION" and str(d.get("mode", "")) == "leap_to_defend",
		"FIX=0: the old leap_to_defend even with an enemy 4\" away (got %s mode=%s)" % [d.get("type", ""), str(d.get("mode", ""))])

func test_near_leap_kept():
	# A charged enemy 7" away (P(2D6 >= 7) = 58%), nothing within 6": still
	# worth the CP — USE with Leap to Defend at both values.
	var a := _hi(_board(3, 7.0), 0.0)
	var b := _hi(_board(3, 7.0), 1.0)
	_assert(str(a.get("type", "")) == "USE_HEROIC_INTERVENTION" and str(b.get("type", "")) == "USE_HEROIC_INTERVENTION"
		and str(a.get("mode", "")) == "leap_to_defend" and str(b.get("mode", "")) == "leap_to_defend"
		and str(a.get("unit_id", "")) == str(b.get("unit_id", "")),
		"guard: a 7\" Leap (58%%) is used at both values (FIX=0 %s/%s, FIX=1 %s/%s)" % [
			a.get("type", ""), str(a.get("mode", "")), b.get("type", ""), str(b.get("mode", ""))])

func test_charged_enemy_within_6_stays_leap():
	# The charger itself 4" away: both modes target it with the same odds —
	# the old Leap to Defend is kept.
	var a := _hi(_board(3, 4.0), 0.0)
	var b := _hi(_board(3, 4.0), 1.0)
	_assert(str(a.get("type", "")) == "USE_HEROIC_INTERVENTION" and str(b.get("type", "")) == "USE_HEROIC_INTERVENTION"
		and str(a.get("mode", "")) == "leap_to_defend" and str(b.get("mode", "")) == "leap_to_defend",
		"guard: a charged enemy 4\" away stays a Leap at both values (FIX=0 %s, FIX=1 %s)" % [str(a.get("mode", "")), str(b.get("mode", ""))])

func test_no_cp_declines():
	var a := _hi(_board(0, 4.0), 0.0)
	var b := _hi(_board(0, 4.0), 1.0)
	_assert(str(a.get("type", "")) == "DECLINE_HEROIC_INTERVENTION" and str(b.get("type", "")) == "DECLINE_HEROIC_INTERVENTION",
		"guard: CP 0 declines at both values (%s / %s)" % [a.get("type", ""), b.get("type", "")])
