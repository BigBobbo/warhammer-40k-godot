extends SceneTree

# FIX_WAAAGH_ADV_REROLL (11e rules audit, protocol V2-4: AR-06).
#
# Orks Waaagh!: "Friendly ORKS units with this ability can: Re-roll advance
# rolls" — every ORKS unit with the ability, riled up or not. The engine
# offers it as a free re-roll (OrkArmyRules11e.free_advance_reroll_source,
# MovementPhase) and the AI takes it on a 1-3 (ai_take_free_advance_reroll,
# AIPlayer). Ability re-rolls (EffectPrimitives.has_effect_reroll_advance —
# the Blade Champion's Swift Onslaught) are made by the engine on a 1-3. The
# planner priced every Advance as a plain D6: so with the re-roll each of 1-3
# has probability 1/12 and each of 4-6 1/4 (mean 4.25", P(>= 3) = 0.83).
#   RACE-1    _long_trip_advance_saves_turn: 2D6 >= 9 is 0.278 (< 0.3) plain,
#             0.542 re-rolled -> a 33" trip at M12 Advances (2 turns, not 3).
#   pace      long-trip turns to reach and the RI-QUARTER end spot use
#             M + 4.25" instead of M + 3.5".
#   AI-GAP-4  the (M, M+2"] band (plain P(>= 2) = 0.83) becomes (M, M+3"].
#
# (a) mismatch, FIX = 1: the 33" Warbikers trip saves a turn and the planner
#     Advances; a 32" trip is priced at 2 turns (not 3); a gap of M+2.5"
#     reaches the AI-GAP-4 branch (Gretchin, Blade Champion) and the planner
#     Advances the Gretchin there; the RI-QUARTER spot of an Advance ends
#     M+16.25" away and counts the quarter it reaches.
# (b) FIX = 0: every one of those is the old plain-D6 answer.
# (c) guards (same at 0 and 1): a Custodian Guard (no re-roll source); a
#     one-die trip (P(6) 0.17 -> 0.25, still < 0.3); a gap beyond M+3"; with
#     FIX_ADV_ENGINE_PREDICATES on, a Stompa that reaches the widened band
#     with a target in range still keeps its shooting; the plain-D6 odds.
#
# Run with: godot --headless --path . -s tests/unit/test_ai_fix_waaagh_adv_reroll.gd

const AI_PATH := "res://scripts/AIDecisionMaker.gd"
const GameStateData = preload("res://autoloads/GameState.gd")
const FIX := "FIX_WAAAGH_ADV_REROLL"
const PX := 40.0  # pixels per inch
const CR_PX := 151.5  # AIDecisionMaker.OBJECTIVE_CONTROL_RANGE_PX (3.79")
const ORIGIN := Vector2(880, 1600)  # our unit's centroid
const MOVABLE := ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]

# Bench ability texts (40kdc 1.0.19 launch data in the bench saves).
const WAAAGH_BENCH := {"name": "Waaagh!", "type": "Faction", "description": "Once per battle, until your next Command phase:\n  -> The unit gains the Advance & Charge ability.\n  -> Add 1 to the unit's Strength characteristic (melee).\n  -> Add 1 to the unit's Attacks characteristic (melee).\n  -> The unit has a 5+ invulnerable save."}
const DRIVE_BY_DAKKA := {"name": "Drive-by Dakka", "type": "Datasheet", "description": "During the Shooting phase against targets within 9\", subtract 1 from the unit's Armour Penetration characteristic."}
const RUNTHERD := {"name": "Runtherd", "type": "Datasheet", "description": "Modify this model's Toughness characteristic to 2."}
const STOMPIN := {"name": "Stompin' Forward", "type": "Datasheet", "description": "This model can move over terrain features as though they were not there."}
const MARTIAL_INSPIRATION := {"name": "Martial Inspiration", "type": "Datasheet", "description": "Once per battle, the unit gains the Advance & Charge ability."}
const SWIFT_ONSLAUGHT := {"name": "Swift Onslaught", "type": "Datasheet", "description": "After being attached to a unit, you can re-roll the Charge roll."}
const SENTINEL_STORM := {"name": "Sentinel Storm", "type": "Datasheet", "description": "Once per battle, during the Shooting phase, the unit gains the Shoot Again ability."}
const STAND_VIGIL := {"name": "Stand Vigil", "type": "Datasheet", "description": "You can re-roll a Wound roll of 1."}

const MELEE := {"name": "Choppa", "type": "Melee", "range": "Melee", "attacks": "3", "weapon_skill": "3", "strength": "5", "ap": "-1", "damage": "1", "special_rules": ""}
const SUPA_ROKKITS := {"name": "Supa-rokkits", "type": "Ranged", "range": "100", "attacks": "D6", "ballistic_skill": "5", "strength": "10", "ap": "-2", "damage": "6", "special_rules": "blast"}
const GROT_BLASTA := {"name": "Grot blasta", "type": "Ranged", "range": "12", "attacks": "1", "ballistic_skill": "4", "strength": "3", "ap": "0", "damage": "1", "special_rules": "pistol"}
const TWIN_DAKKAGUN := {"name": "Twin dakkagun", "type": "Ranged", "range": "18", "attacks": "3", "ballistic_skill": "5", "strength": "5", "ap": "0", "damage": "1", "special_rules": "assault, rapid fire 2, twin linked"}
const GUARDIAN_SPEAR := {"name": "Guardian spear – Ranged", "type": "Ranged", "range": "24", "attacks": "2", "ballistic_skill": "2", "strength": "4", "ap": "-1", "damage": "2", "special_rules": "assault"}

const ORKS_KOS := {"name": "Orks", "detachment": "Kult of Speed"}
const CUSTODES := {"name": "Adeptus Custodes", "detachment": "Lions of the Emperor"}
# Reconnaissance Sweep (3 quarters -> 3 VP, 4 -> 6 at the end of our turn).
const RECON := {"card_name": "Reconnaissance Sweep", "active_rules": 2, "quarters": true,
	"objective_pressure": 0.0, "vp_rules": [
		{"when": "eot", "type": "quarters", "min": 3, "vp": 3, "exclusive_group": "quarters_tier"},
		{"when": "eot", "type": "quarters", "min": 4, "vp": 6, "exclusive_group": "quarters_tier"}]}

var _pass_count: int = 0
var _fail_count: int = 0
var _ran := false
var AIDM = null
var _saved_state: Dictionary = {}

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
	print("\n=== FIX_WAAAGH_ADV_REROLL: Advance odds with the free Waaagh! / ability re-roll (1-3) ===\n")
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	AIDM = load(AI_PATH)
	# The text-based advance-and-X tests stay as shipped here
	# (FIX_ADV_ENGINE_PREDICATES is tested on its own, and once below with this
	# fix); RI-QUARTER is pinned on (shipped default).
	AIDM._config_overrides["FIX_ADV_ENGINE_PREDICATES"] = 0.0
	AIDM._config_overrides["FIX_REINFORCE_INSURANCE"] = 1.0
	AIDM._config_overrides["FIX_RI_QUARTER"] = 1.0
	_saved_state = _gs().state.duplicate(true)

	test_race1_two_turn_trip_odds()
	test_planner_advances_the_two_turn_trip()
	test_planner_prices_the_reroll_pace()
	test_ai_gap4_band_reaches_m_plus_3()
	test_planner_band_advances_gretchin()
	test_ri_quarter_spot_at_the_reroll_pace()
	test_guard_custodian_guard_unchanged()
	test_guard_one_die_trip_unchanged()
	test_guard_beyond_the_band_unchanged()
	test_guard_with_engine_predicates_stompa_keeps_shooting()

	_gs().state = _saved_state.duplicate(true)
	for k in [FIX, "FIX_ADV_ENGINE_PREDICATES", "FIX_REINFORCE_INSURANCE", "FIX_RI_QUARTER"]:
		AIDM._config_overrides.erase(k)
	AIDM._primary_awareness_p1 = {}
	AIDM._secondary_awareness_p1 = {}
	GameConstants.edition = prev_edition
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)

# --- builders -----------------------------------------------------------------

func _unit(uid: String, owner: int, name: String, keywords: Array, move: float, weapons: Array,
		abilities: Array, n: int = 1, base_mm: float = 32.0, flags: Dictionary = {},
		centre: Vector2 = ORIGIN) -> Dictionary:
	var models = []
	for i in range(n):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": base_mm,
			"base_type": "circular", "base_dimensions": {}, "wounds": 3, "current_wounds": 3,
			"position": {"x": centre.x + (i - (n - 1) / 2.0) * (base_mm / 25.4 * PX + 4.0), "y": centre.y}})
	return {"id": uid, "owner": owner, "status": GameStateData.UnitStatus.DEPLOYED,
		"flags": flags.duplicate(), "attachment_data": {"attached_characters": []},
		"meta": {"name": name, "display_name": name, "keywords": keywords, "points": 100,
			"stats": {"move": move, "toughness": 6, "save": 4, "wounds": 3, "leadership": 7, "objective_control": 2},
			"weapons": weapons, "abilities": abilities},
		"models": models}

func _warbikers(n: int = 3, centre: Vector2 = ORIGIN) -> Dictionary:
	return _unit("U_WARBIKERS_A", 1, "Warbikers", ["GRENADES", "MOUNTED", "ORKS", "SPEED FREEKS", "WARBIKERS"],
		12.0, [TWIN_DAKKAGUN, MELEE], [WAAAGH_BENCH, DRIVE_BY_DAKKA], n, 75.0, {}, centre)

func _gretchin() -> Dictionary:
	return _unit("U_GRETCHIN_A", 1, "Gretchin", ["GRETCHIN", "GROTS", "INFANTRY", "ORKS"],
		6.0, [GROT_BLASTA, MELEE], [WAAAGH_BENCH, RUNTHERD], 5, 25.0)

func _stompa() -> Dictionary:
	return _unit("U_STOMPA_A", 1, "Stompa", ["ORKS", "STOMPA", "TITANIC", "TOWERING", "TRANSPORT", "VEHICLE", "WALKER"],
		10.0, [SUPA_ROKKITS, MELEE], [WAAAGH_BENCH, STOMPIN], 1, 180.0)

func _blade_champion() -> Dictionary:
	return _unit("U_BLADE_CHAMPION_A", 1, "Blade Champion", ["ADEPTUS CUSTODES", "BLADE CHAMPION", "CHARACTER", "IMPERIUM", "INFANTRY"],
		6.0, [MELEE], [MARTIAL_INSPIRATION, SWIFT_ONSLAUGHT], 1, 40.0)

func _custodian_guard() -> Dictionary:
	return _unit("U_CUSTODIAN_GUARD_A", 1, "Custodian Guard", ["ADEPTUS CUSTODES", "BATTLELINE", "CUSTODIAN GUARD", "IMPERIUM", "INFANTRY"],
		6.0, [GUARDIAN_SPEAR, MELEE], [SENTINEL_STORM, STAND_VIGIL], 4, 40.0)

func _enemy(pos: Vector2) -> Dictionary:
	return _unit("U_ENEMY", 2, "Enemy Squad", ["INFANTRY"], 6.0, [MELEE], [], 1, 40.0, {}, pos)

# The live board the engine helpers read (detachments, abilities by unit id).
func _live(units: Array, p1_faction: Dictionary) -> void:
	_gs().state = _saved_state.duplicate(true)
	var by_id := {}
	for u in units:
		by_id[str(u.id)] = u
	_gs().state["units"] = by_id
	if not _gs().state.has("meta"):
		_gs().state["meta"] = {}
	_gs().state["meta"]["battle_round"] = 2
	_gs().state["meta"]["active_player"] = 1
	_gs().state["factions"] = {"1": p1_faction.duplicate(), "2": CUSTODES.duplicate() if p1_faction.name == "Orks" else ORKS_KOS.duplicate()}
	_gs().state["players"] = {"1": {}, "2": {}}

func _has_fn(fn: String) -> bool:
	for m in AIDM.get_script_method_list():
		if str(m.get("name", "")) == fn:
			return true
	return false

func _at(value: float, c: Callable):
	AIDM._config_overrides[FIX] = value
	var r = c.call()
	AIDM._config_overrides[FIX] = 1.0
	return r

func _gap4(unit: Dictionary, gap_in: float, battle_round: int, obj_eval: Dictionary, enemies: Dictionary) -> bool:
	return AIDM._should_unit_advance(unit, gap_in, float(unit.meta.stats.move),
		AIDM._unit_has_ranged_weapons(unit), AIDM._get_max_weapon_range(unit), enemies,
		AIDM._get_unit_centroid(unit), battle_round, obj_eval)

# Plan `unit` toward one objective `gap_in` inches (past control range) away
# in `dir`; returns the candidate for it at FIX = value.
func _plan_candidate(value: float, unit: Dictionary, gap_in: float, dir: Vector2, others: Array,
		enemies: Dictionary, primary: Dictionary = {}) -> Dictionary:
	AIDM._config_overrides[FIX] = value
	AIDM._primary_awareness_p1 = primary
	AIDM._secondary_awareness_p1 = {}
	var centroid: Vector2 = AIDM._get_unit_centroid(unit)
	var obj_pos: Vector2 = centroid + dir.normalized() * (gap_in * PX + CR_PX)
	var units := {str(unit.id): unit}
	var friendlies := {str(unit.id): unit}
	for o in others:
		units[str(o.id)] = o
		friendlies[str(o.id)] = o
	for e in enemies:
		units[e] = enemies[e]
	var snap := {"battle_round": 2, "meta": {"battle_round": 2, "first_turn_player": 1},
		"board": {"objectives": [{"id": "obj_far", "position": obj_pos, "zone": "no_mans_land"}], "terrain_features": []},
		"units": units, "factions": _gs().state["factions"]}
	var evals = AIDM._evaluate_all_objectives(snap, [obj_pos], 1, enemies, friendlies, 2)
	AIDM._assign_units_to_objectives(snap, {str(unit.id): MOVABLE}, evals, [obj_pos], enemies, friendlies, 1, 2)
	var cand := {}
	for c in AIDM._last_movement_candidates.get(str(unit.id), []):
		if str(c.objective_id) == "obj_far":
			cand = c
	print("  FIX=%d: %s -> obj_far: %s, %d turn(s), terms %s" % [int(value), str(unit.id),
		str(cand.get("action", "?")), int(cand.get("turns_to_reach", 0)), str(cand.get("score_terms", {}))])
	AIDM._config_overrides[FIX] = 1.0
	AIDM._primary_awareness_p1 = {}
	return cand

# --- (a) + (b): the mismatch cases -----------------------------------------------

func test_race1_two_turn_trip_odds():
	print("\n--- RACE-1 odds: Warbikers (M12, Waaagh!) on a 33\" trip (need 9 on two Advance rolls) ---")
	var wb := _warbikers()
	_live([wb], ORKS_KOS)
	var plain_p: float = AIDM._prob_sum_d6_at_least(2, 9.0)
	_assert(absf(plain_p - 10.0 / 36.0) < 1e-6, "plain 2D6 >= 9 = 0.278 (got %.4f)" % plain_p)
	if not _has_fn("_adv_face_probs"):
		_assert(false, "FIX=1: helper _adv_face_probs (re-rolled Advance odds) exists")
		_assert(false, "FIX=1: the 33\" trip saves a turn with the re-roll (P 0.542)")
		return
	var faces0: Array = _at(0.0, func(): return AIDM._adv_face_probs(wb))
	var faces1: Array = _at(1.0, func(): return AIDM._adv_face_probs(wb))
	_assert(faces0.is_empty(), "FIX=0: a plain D6 (no face odds) (got %s)" % str(faces0))
	_assert(faces1.size() == 6 and absf(float(faces1[0]) - 1.0 / 12.0) < 1e-9 and absf(float(faces1[5]) - 0.25) < 1e-9,
		"FIX=1: Waaagh! re-roll odds 1-3: 1/12, 4-6: 1/4 (got %s)" % str(faces1))
	var p1: float = AIDM._prob_sum_d6_at_least(2, 9.0, faces1)
	_assert(absf(p1 - 0.5416667) < 1e-4, "re-rolled 2D6 >= 9 = 0.542 (got %.4f)" % p1)
	var s0: bool = AIDM._long_trip_advance_saves_turn(33.0, 12.0, faces0)
	var s1: bool = AIDM._long_trip_advance_saves_turn(33.0, 12.0, faces1)
	_assert(s0 == false, "FIX=0: the 33\" trip does not save a turn (P 0.278 < 0.3) (got %s)" % str(s0))
	_assert(s1 == true, "FIX=1: the 33\" trip saves a turn (P 0.542 >= 0.3) (got %s)" % str(s1))

func test_planner_advances_the_two_turn_trip():
	print("\n--- planner: Warbikers, objective gap 33\" ---")
	var wb := _warbikers()
	var enemy := _enemy(Vector2(1600, 300))
	_live([wb, enemy], ORKS_KOS)
	var c0 := _plan_candidate(0.0, wb, 33.0, Vector2(0, -1), [], {"U_ENEMY": enemy})
	var c1 := _plan_candidate(1.0, wb, 33.0, Vector2(0, -1), [], {"U_ENEMY": enemy})
	_assert(str(c0.get("action", "")) == "move" and int(c0.get("turns_to_reach", 0)) == 3,
		"FIX=0: walks the 33\" trip, 3 turns (%s, %d)" % [str(c0.get("action", "")), int(c0.get("turns_to_reach", 0))])
	_assert(str(c1.get("action", "")) == "advance",
		"FIX=1: Advances the 33\" trip (54%% to arrive a turn sooner) (%s, %d)" % [str(c1.get("action", "")), int(c1.get("turns_to_reach", 0))])

func test_planner_prices_the_reroll_pace():
	print("\n--- planner: Warbikers, objective gap 32\" (Advance either way; pace M+3.5 vs M+4.25) ---")
	var wb := _warbikers()
	var enemy := _enemy(Vector2(1600, 300))
	_live([wb, enemy], ORKS_KOS)
	var c0 := _plan_candidate(0.0, wb, 32.0, Vector2(0, -1), [], {"U_ENEMY": enemy})
	var c1 := _plan_candidate(1.0, wb, 32.0, Vector2(0, -1), [], {"U_ENEMY": enemy})
	_assert(str(c0.get("action", "")) == "advance" and int(c0.get("turns_to_reach", 0)) == 3,
		"FIX=0: 32\" / 15.5\" per turn = 3 turns (%s, %d)" % [str(c0.get("action", "")), int(c0.get("turns_to_reach", 0))])
	_assert(str(c1.get("action", "")) == "advance" and int(c1.get("turns_to_reach", 0)) == 2,
		"FIX=1: 32\" / 16.25\" per turn = 2 turns (%s, %d)" % [str(c1.get("action", "")), int(c1.get("turns_to_reach", 0))])

# MERGE (main ADV-ODDS-1): the AI-GAP-4 "M+2\" band" (M+3\" with the re-roll)
# was replaced by main's per-roll Advance odds (_advance_reach_chance). The
# fix now reads that chance off the re-rolled D6 (1-3: 1/12, 4-6: 1/4), so a
# gap M+2.5\" (needs a 3+) is 4/6 = 0.667 plain and 0.833 re-rolled, and the
# likely-roll bar (ADVANCE_MIN_REACH_CHANCE 0.5) moves from M+4\" to M+5\".
func _chance_at(value: float, unit: Dictionary, gap_in: float) -> float:
	AIDM._config_overrides[FIX] = value
	var faces: Array = AIDM._adv_face_probs(unit)
	var c: float = AIDM._advance_reach_chance(unit, gap_in, float(unit.meta.stats.move), faces)
	AIDM._config_overrides[FIX] = 1.0
	return c

func test_ai_gap4_band_reaches_m_plus_3():
	print("\n--- ADV-ODDS-1 chance: objective gap M+2.5\" / M+4.5\" (Gretchin M6; Blade Champion M6) ---")
	var grots := _gretchin()
	_live([grots], ORKS_KOS)
	var g0 := _chance_at(0.0, grots, 8.5)
	var g1 := _chance_at(1.0, grots, 8.5)
	_assert(absf(g0 - 4.0 / 6.0) < 1e-4, "FIX=0: Gretchin 8.5\" needs a 3+ on a plain D6 -> 0.667 (got %.4f)" % g0)
	_assert(absf(g1 - 10.0 / 12.0) < 1e-4, "FIX=1: Gretchin 8.5\" with the Waaagh! re-roll -> 0.833 (got %.4f)" % g1)
	var ev := {"id": "obj_nml_1", "zone": "no_mans_land", "state": "uncontrolled", "priority": 5.0}
	var gl0 = _at(0.0, func(): return _gap4(grots, 10.5, 2, ev, {}))
	var gl1 = _at(1.0, func(): return _gap4(grots, 10.5, 2, ev, {}))
	_assert(gl0 == true and gl1 == true, "Gretchin 10.5\": an Advance-and-charge (text) unit takes any chance at 0 and 1 (%s, %s)" % [str(gl0), str(gl1)])
	var bc := _blade_champion()
	_live([bc], CUSTODES)
	var b0 := _chance_at(0.0, bc, 10.5)
	var b1 := _chance_at(1.0, bc, 10.5)
	_assert(absf(b0 - 2.0 / 6.0) < 1e-4, "FIX=0: Blade Champion 10.5\" needs a 5+ -> 0.333, below the 0.5 bar (got %.4f)" % b0)
	_assert(absf(b1 - 0.5) < 1e-4, "FIX=1: Blade Champion (Swift Onslaught re-roll) 10.5\" -> 0.5, a likely roll (got %.4f)" % b1)

func test_planner_band_advances_gretchin():
	print("\n--- planner: Gretchin, objective gap 8.5\", an enemy 10\" away: the candidate's Advance odds ---")
	var grots := _gretchin()
	var enemy := _enemy(ORIGIN + Vector2(10.0 * PX, 0))
	_live([grots, enemy], ORKS_KOS)
	var c0 := _plan_candidate(0.0, grots, 8.5, Vector2(0, -1), [], {"U_ENEMY": enemy})
	var c1 := _plan_candidate(1.0, grots, 8.5, Vector2(0, -1), [], {"U_ENEMY": enemy})
	_assert(absf(float(c0.get("adv_chance", -1.0)) - 4.0 / 6.0) < 1e-4,
		"FIX=0: the plan prices the Advance at the plain D6's 0.667 (%s, %.3f)" % [str(c0.get("action", "")), float(c0.get("adv_chance", -1.0))])
	_assert(absf(float(c1.get("adv_chance", -1.0)) - 10.0 / 12.0) < 1e-4 and str(c1.get("action", "")) == "advance",
		"FIX=1: Advances, priced at the re-rolled 0.833 (%s, %.3f)" % [str(c1.get("action", "")), float(c1.get("adv_chance", -1.0))])

func test_ri_quarter_spot_at_the_reroll_pace():
	print("\n--- RI-QUARTER: Warbikers Advance east; M+15.5\" ends in a covered quarter, M+16.25\" in the 4th ---")
	# Single-model Warbikers at x = 880 - 620 - 15: M+3.5" (620 px) ends at
	# x = 865 (bottom-left, covered), M+4.25" (650 px) at x = 895 (bottom-right).
	var wb := _warbikers(1, Vector2(245, 1900))
	var tl := _unit("U_TL", 1, "Top Left", ["INFANTRY"], 6.0, [MELEE], [], 1, 32.0, {}, Vector2(200, 300))
	var tr := _unit("U_TR", 1, "Top Right", ["INFANTRY"], 6.0, [MELEE], [], 1, 32.0, {}, Vector2(1500, 300))
	var bl := _unit("U_BL", 1, "Bottom Left", ["INFANTRY"], 6.0, [MELEE], [], 1, 32.0, {}, Vector2(200, 2250))
	var enemy := _enemy(Vector2(1600, 600))
	_live([wb, tl, tr, bl, enemy], ORKS_KOS)
	var c0 := _plan_candidate(0.0, wb, 30.0, Vector2(1, 0), [tl, tr, bl], {"U_ENEMY": enemy}, RECON)
	var c1 := _plan_candidate(1.0, wb, 30.0, Vector2(1, 0), [tl, tr, bl], {"U_ENEMY": enemy}, RECON)
	var q0 := float(c0.get("score_terms", {}).get("quarter_vp", 0.0))
	var q1 := float(c1.get("score_terms", {}).get("quarter_vp", 0.0))
	_assert(str(c0.get("action", "")) == "advance" and str(c1.get("action", "")) == "advance",
		"the trip is an Advance at 0 and 1 (%s, %s)" % [str(c0.get("action", "")), str(c1.get("action", ""))])
	_assert(q0 == 0.0, "FIX=0: M+3.5\" ends in the covered bottom-left quarter -> no quarter_vp (%.2f)" % q0)
	_assert(absf(q1 - 9.0) < 0.01, "FIX=1: M+4.25\" ends in the 4th quarter -> quarter_vp 9.0 (%.2f)" % q1)

# --- (c) guards: same answer at 0 and 1 ---------------------------------------------

func test_guard_custodian_guard_unchanged():
	print("\n--- guard: Custodian Guard (no Advance re-roll) ---")
	var cg := _custodian_guard()
	var enemy := _enemy(Vector2(1600, 300))
	_live([cg, enemy], CUSTODES)
	if _has_fn("_adv_face_probs"):
		var f1: Array = _at(1.0, func(): return AIDM._adv_face_probs(cg))
		_assert(f1.is_empty(), "FIX=1: no re-roll source -> plain D6 (got %s)" % str(f1))
	var ev := {"id": "obj_nml_1", "zone": "no_mans_land", "state": "enemy_held", "priority": 5.0}
	var g0 = _at(0.0, func(): return _gap4(cg, 8.5, 2, ev, {}))
	var g1 = _at(1.0, func(): return _gap4(cg, 8.5, 2, ev, {}))
	_assert(g0 == g1 and is_equal_approx(_chance_at(0.0, cg, 8.5), _chance_at(1.0, cg, 8.5)),
		"ADV-ODDS-1: 8.5\" -> the same Advance decision and odds at 0 and 1 (%s, %s)" % [str(g0), str(g1)])
	var c0 := _plan_candidate(0.0, cg, 15.0, Vector2(0, -1), [], {"U_ENEMY": enemy})
	var c1 := _plan_candidate(1.0, cg, 15.0, Vector2(0, -1), [], {"U_ENEMY": enemy})
	_assert(str(c0.get("action", "")) == str(c1.get("action", "")) and int(c0.get("turns_to_reach", 0)) == int(c1.get("turns_to_reach", 0)),
		"planner: the 15\" trip is the same at 0 and 1 (%s %d, %s %d)" % [str(c0.get("action", "")), int(c0.get("turns_to_reach", 0)),
			str(c1.get("action", "")), int(c1.get("turns_to_reach", 0))])

func test_guard_one_die_trip_unchanged():
	print("\n--- guard: Warbikers 17.5\" trip (one Advance roll must be 6: 0.17 plain, 0.25 re-rolled, both < 0.3) ---")
	var wb := _warbikers()
	_live([wb], ORKS_KOS)
	var faces1: Array = []
	if _has_fn("_adv_face_probs"):
		faces1 = _at(1.0, func(): return AIDM._adv_face_probs(wb))
	var s0: bool = AIDM._long_trip_advance_saves_turn(17.5, 12.0)
	var s1: bool = AIDM._long_trip_advance_saves_turn(17.5, 12.0, faces1) if not faces1.is_empty() else s0
	_assert(s0 == false and s1 == false, "RACE-1: a one-roll 6 does not save the turn at 0 or 1 (%s, %s)" % [str(s0), str(s1)])

func test_guard_beyond_the_band_unchanged():
	print("\n--- guard: Gretchin gap 12.5\" (beyond M+6\": no roll gets there) ---")
	var grots := _gretchin()
	_live([grots], ORKS_KOS)
	var ev := {"id": "obj_nml_1", "zone": "no_mans_land", "state": "enemy_held", "priority": 5.0}
	var g0 = _at(0.0, func(): return _gap4(grots, 12.5, 2, ev, {}))
	var g1 = _at(1.0, func(): return _gap4(grots, 12.5, 2, ev, {}))
	_assert(g0 == false and g1 == false, "ADV-ODDS-1: 12.5\" is out of reach at 0 and 1 (%s, %s)" % [str(g0), str(g1)])

func test_guard_with_engine_predicates_stompa_keeps_shooting():
	print("\n--- guard (with FIX_ADV_ENGINE_PREDICATES = 1): Stompa gap 12.5\" (M10), target 30\" away ---")
	AIDM._config_overrides["FIX_ADV_ENGINE_PREDICATES"] = 1.0
	var stompa := _stompa()
	var enemy := _enemy(ORIGIN + Vector2(0, -30.0 * PX))
	_live([stompa, enemy], ORKS_KOS)
	var ev := {"id": "obj_nml_1", "zone": "no_mans_land", "state": "enemy_held", "priority": 5.0}
	var g0 = _at(0.0, func(): return _gap4(stompa, 12.5, 2, ev, {"U_ENEMY": enemy}))
	var g1 = _at(1.0, func(): return _gap4(stompa, 12.5, 2, ev, {"U_ENEMY": enemy}))
	_assert(g0 == false and g1 == false, "AI-GAP-4: the widened band reaches the shooting check, which keeps the Stompa walking (%s, %s)" % [str(g0), str(g1)])
	AIDM._config_overrides["FIX_ADV_ENGINE_PREDICATES"] = 0.0
