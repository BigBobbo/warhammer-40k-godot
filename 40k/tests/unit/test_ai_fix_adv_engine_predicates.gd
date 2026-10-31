extends SceneTree

# FIX_ADV_ENGINE_PREDICATES (11e rules audit, protocol V2-4: CH-02 + ADV-01 +
# AR-01, with AR-05's RACE-1 part and the army verifier's Wazdakka item).
#
# The objective-race Advance tests decided "may this unit charge / shoot every
# weapon after Advancing" by matching "advance" + "charge" / "shoot" in ability
# TEXT (AIAbilityAnalyzer.unit_has_ability_containing):
#   AI-GAP-4  _should_unit_advance (an objective gap in the (M, M+2"] band):
#             a text match returned true before any shooting check.
#   RACE-1    _should_unit_advance_long_trip (multi-turn trips): a text
#             advance-and-charge skipped the "enemy within M + 12" -> walk"
#             guard, a text advance-and-shoot returned true, and the RI-ASSAULT
#             charge re-check read only the raw effect flag.
# The engine (ChargePhase / ShootingPhase / RulesEngine) asks
# EffectPrimitives.has_effect_advance_and_charge / has_effect_advance_and_shoot
# (rules 09.06 "not eligible to declare a charge ... unless otherwise stated",
# 10.05 "only [ASSAULT] weapons", 11.02). On the bench (tests/saves/*_2000_
# postdeploy, Kult of Speed Orks, 10e ability texts) the text test is wrong
# both ways: every Ork's dormant Waaagh! ("gains the Advance & Charge ability")
# and the Blade Champion's Martial Inspiration read as advance-and-charge, and
# the Kult of Speed SPEED FREEKS (Adrenaline Junkies: [ASSAULT] and a charge
# after an Advance) read as losing their shooting.
#
# (a) mismatch, FIX = 1: a dormant-Waaagh! Stompa with a target in range does
#     not give up its shooting for the 11" gap (AI-GAP-4 false); Deffkoptas and
#     Wazdakka with an enemy 20" away Advance on a long trip (RACE-1 true); a
#     Blade Champion with an enemy 15" away keeps the M + 12" guard (false);
#     a Custodian Guard that disembarked from an Orion (Assault Dropship:
#     engine grant, no effect flag) passes the guard and the RI-ASSAULT
#     re-check (true); the same unit with a text advance-and-charge too (the
#     guard is skipped either way) passes the RI-ASSAULT re-check alone
#     (true); the planner prices the Deffkoptas' 30" trip as a 2-turn Advance.
# (b) FIX = 0: every one of those answers is the old text-test answer.
# (c) guards (same answer at 0 and 1): a riled Gretchin (effect flag set),
#     Warbikers (text and engine agree), a Custodian Guard (no grant: guard
#     and RI-ASSAULT unchanged), a Stompa Advancing to a round-1 no-man's-land
#     objective.
#
# Run with: godot --headless --path . -s tests/unit/test_ai_fix_adv_engine_predicates.gd

const AI_PATH := "res://scripts/AIDecisionMaker.gd"
const GameStateData = preload("res://autoloads/GameState.gd")
const FIX := "FIX_ADV_ENGINE_PREDICATES"
const PX := 40.0  # pixels per inch
const ORIGIN := Vector2(880, 1600)  # our unit's centroid
const MOVABLE := ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]

# Bench ability texts (40kdc 1.0.19 launch data in the bench saves).
const WAAAGH_BENCH := {"name": "Waaagh!", "type": "Faction", "description": "Once per battle, until your next Command phase:\n  -> The unit gains the Advance & Charge ability.\n  -> Add 1 to the unit's Strength characteristic (melee).\n  -> Add 1 to the unit's Attacks characteristic (melee).\n  -> The unit has a 5+ invulnerable save."}
const DEFF_FROM_ABOVE := {"name": "Deff from Above", "type": "Datasheet", "description": "Roll one D6 for each model in this unit: for each 4+, the target suffers 1 mortal wound."}
const DRIVE_BY_DAKKA := {"name": "Drive-by Dakka", "type": "Datasheet", "description": "During the Shooting phase against targets within 9\", subtract 1 from the unit's Armour Penetration characteristic."}
const RUNTHERD := {"name": "Runtherd", "type": "Datasheet", "description": "Modify this model's Toughness characteristic to 2."}
const STOMPIN := {"name": "Stompin' Forward", "type": "Datasheet", "description": "This model can move over terrain features as though they were not there."}
const MARTIAL_INSPIRATION := {"name": "Martial Inspiration", "type": "Datasheet", "description": "Once per battle, the unit gains the Advance & Charge ability."}
const SWIFT_ONSLAUGHT := {"name": "Swift Onslaught", "type": "Datasheet", "description": "After being attached to a unit, you can re-roll the Charge roll."}
const SENTINEL_STORM := {"name": "Sentinel Storm", "type": "Datasheet", "description": "Once per battle, during the Shooting phase, the unit gains the Shoot Again ability."}
const STAND_VIGIL := {"name": "Stand Vigil", "type": "Datasheet", "description": "You can re-roll a Wound roll of 1."}

const MELEE := {"name": "Choppa", "type": "Melee", "range": "Melee", "attacks": "3", "weapon_skill": "3", "strength": "5", "ap": "-1", "damage": "1", "special_rules": ""}
const SUPA_ROKKITS := {"name": "Supa-rokkits", "type": "Ranged", "range": "100", "attacks": "D6", "ballistic_skill": "5", "strength": "10", "ap": "-2", "damage": "6", "special_rules": "blast"}
const KOPTA_ROKKITS := {"name": "Kopta rokkits", "type": "Ranged", "range": "24", "attacks": "1", "ballistic_skill": "5", "strength": "9", "ap": "-2", "damage": "3", "special_rules": "blast, twin linked"}
const SLUGGA := {"name": "Slugga", "type": "Ranged", "range": "12", "attacks": "1", "ballistic_skill": "5", "strength": "4", "ap": "0", "damage": "1", "special_rules": "pistol"}
const GRABBA_RANGED := {"name": "Grabba dragga – ranged", "type": "Ranged", "range": "12", "attacks": "1", "ballistic_skill": "4", "strength": "8", "ap": "-2", "damage": "D6", "special_rules": "assault, precision"}
const PSYKO_GATLER := {"name": "Psyko‑gatler", "type": "Ranged", "range": "24", "attacks": "6", "ballistic_skill": "4", "strength": "6", "ap": "-1", "damage": "1", "special_rules": "assault, sustained hits 1"}
const GROT_BLASTA := {"name": "Grot blasta", "type": "Ranged", "range": "12", "attacks": "1", "ballistic_skill": "4", "strength": "3", "ap": "0", "damage": "1", "special_rules": "pistol"}
const TWIN_DAKKAGUN := {"name": "Twin dakkagun", "type": "Ranged", "range": "18", "attacks": "3", "ballistic_skill": "5", "strength": "5", "ap": "0", "damage": "1", "special_rules": "assault, rapid fire 2, twin linked"}
const GUARDIAN_SPEAR := {"name": "Guardian spear – Ranged", "type": "Ranged", "range": "24", "attacks": "2", "ballistic_skill": "2", "strength": "4", "ap": "-1", "damage": "2", "special_rules": "assault"}

const ORKS_KOS := {"name": "Orks", "detachment": "Kult of Speed"}
const CUSTODES := {"name": "Adeptus Custodes", "detachment": "Lions of the Emperor"}

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
	print("\n=== FIX_ADV_ENGINE_PREDICATES: objective-race Advance tests read the engine, not ability text ===\n")
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	AIDM = load(AI_PATH)
	# The AI-GAP-4 band stays the plain-D6 (M, M+2"] here (FIX_WAAAGH_ADV_REROLL
	# is tested on its own); RI-ASSAULT is pinned on (shipped default).
	AIDM._config_overrides["FIX_WAAAGH_ADV_REROLL"] = 0.0
	AIDM._config_overrides["FIX_REINFORCE_INSURANCE"] = 1.0
	AIDM._config_overrides["FIX_RI_ASSAULT"] = 1.0
	_saved_state = _gs().state.duplicate(true)

	test_stompa_dormant_waaagh_keeps_its_shooting()
	test_deffkoptas_long_trip_advance()
	test_wazdakka_long_trip_advance()
	test_blade_champion_keeps_the_charge_guard()
	test_ri_assault_recheck_reads_engine_grant()
	test_ri_assault_recheck_alone()
	test_planner_prices_deffkoptas_trip_as_advance()
	test_guard_riled_gretchin_unchanged()
	test_guard_warbikers_unchanged()
	test_guard_custodian_guard_unchanged()
	test_guard_stompa_round1_no_mans_land_unchanged()

	_gs().state = _saved_state.duplicate(true)
	for k in [FIX, "FIX_WAAAGH_ADV_REROLL", "FIX_REINFORCE_INSURANCE", "FIX_RI_ASSAULT"]:
		AIDM._config_overrides.erase(k)
	GameConstants.edition = prev_edition
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)

# --- builders -----------------------------------------------------------------

# `n` models in a row centred on `centre` (centroid = centre).
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

func _stompa(flags: Dictionary = {}) -> Dictionary:
	return _unit("U_STOMPA_A", 1, "Stompa", ["ORKS", "STOMPA", "TITANIC", "TOWERING", "TRANSPORT", "VEHICLE", "WALKER"],
		10.0, [SUPA_ROKKITS, MELEE], [WAAAGH_BENCH, STOMPIN], 1, 180.0, flags)

func _deffkoptas() -> Dictionary:
	return _unit("U_DEFFKOPTAS_A", 1, "Deffkoptas", ["DEFFKOPTAS", "FLY", "GRENADES", "ORKS", "SPEED FREEKS", "VEHICLE"],
		12.0, [KOPTA_ROKKITS, SLUGGA, MELEE], [WAAAGH_BENCH, DEFF_FROM_ABOVE], 3, 75.0)

func _wazdakka() -> Dictionary:
	return _unit("U_WAZDAKKA_GUTSMEK_A", 1, "Wazdakka Gutsmek", ["CHARACTER", "EPIC HERO", "MOUNTED", "ORKS", "SMOKE", "SPEED FREEKS", "VEHICLE", "WAZDAKKA GUTSMEK"],
		14.0, [GRABBA_RANGED, PSYKO_GATLER, MELEE], [WAAAGH_BENCH], 1, 120.0)

func _gretchin(flags: Dictionary = {}) -> Dictionary:
	return _unit("U_GRETCHIN_A", 1, "Gretchin", ["GRETCHIN", "GROTS", "INFANTRY", "ORKS"],
		6.0, [GROT_BLASTA, MELEE], [WAAAGH_BENCH, RUNTHERD], 5, 25.0, flags)

func _warbikers() -> Dictionary:
	return _unit("U_WARBIKERS_A", 1, "Warbikers", ["GRENADES", "MOUNTED", "ORKS", "SPEED FREEKS", "WARBIKERS"],
		12.0, [TWIN_DAKKAGUN, MELEE], [WAAAGH_BENCH, DRIVE_BY_DAKKA], 3, 75.0)

func _blade_champion() -> Dictionary:
	return _unit("U_BLADE_CHAMPION_A", 1, "Blade Champion", ["ADEPTUS CUSTODES", "BLADE CHAMPION", "CHARACTER", "IMPERIUM", "INFANTRY"],
		6.0, [MELEE], [MARTIAL_INSPIRATION, SWIFT_ONSLAUGHT], 1, 40.0)

func _custodian_guard() -> Dictionary:
	return _unit("U_CUSTODIAN_GUARD_A", 1, "Custodian Guard", ["ADEPTUS CUSTODES", "BATTLELINE", "CUSTODIAN GUARD", "IMPERIUM", "INFANTRY"],
		6.0, [GUARDIAN_SPEAR, MELEE], [SENTINEL_STORM, STAND_VIGIL], 4, 40.0)

# One enemy model `dist_in` inches straight above our centroid.
func _enemy_at(dist_in: float, owner: int = 2) -> Dictionary:
	return _unit("U_ENEMY", owner, "Enemy Squad", ["INFANTRY"], 6.0, [MELEE], [], 1, 40.0, {},
		ORIGIN + Vector2(0, -dist_in * PX))

# The live board the engine predicates read (detachments, attached groups).
func _live(units: Array, p1_faction: Dictionary) -> Dictionary:
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
	return by_id

# --- calls at FIX = 0 and FIX = 1 ------------------------------------------------

func _gap4(unit: Dictionary, gap_in: float, battle_round: int, obj_eval: Dictionary, enemies: Dictionary) -> bool:
	return AIDM._should_unit_advance(unit, gap_in, float(unit.meta.stats.move),
		AIDM._unit_has_ranged_weapons(unit), AIDM._get_max_weapon_range(unit), enemies,
		AIDM._get_unit_centroid(unit), battle_round, obj_eval)

func _race1(unit: Dictionary, enemies: Dictionary) -> bool:
	return AIDM._should_unit_advance_long_trip(unit, AIDM._unit_has_ranged_weapons(unit),
		AIDM._get_max_weapon_range(unit), enemies, AIDM._get_unit_centroid(unit))

func _at(value: float, c: Callable):
	AIDM._config_overrides[FIX] = value
	var r = c.call()
	AIDM._config_overrides[FIX] = 1.0
	return r

# --- (a) + (b): the mismatch cases -----------------------------------------------

func test_stompa_dormant_waaagh_keeps_its_shooting():
	print("\n--- AI-GAP-4: dormant-Waaagh! Stompa (M10), objective gap 11\", target 30\" away (in range) ---")
	var stompa := _stompa()
	var enemy := _enemy_at(30.0)
	_live([stompa, enemy], ORKS_KOS)
	var ev := {"id": "obj_nml_1", "zone": "no_mans_land", "state": "enemy_held", "priority": 5.0}
	var old_v = _at(0.0, func(): return _gap4(stompa, 11.0, 2, ev, {"U_ENEMY": enemy}))
	var new_v = _at(1.0, func(): return _gap4(stompa, 11.0, 2, ev, {"U_ENEMY": enemy}))
	_assert(old_v == true, "FIX=0: the Waaagh! text reads as advance-and-charge -> the Stompa Advances (got %s)" % str(old_v))
	_assert(new_v == false, "FIX=1: no engine advance-and-charge/shoot -> the Stompa keeps its shooting (got %s)" % str(new_v))

func test_deffkoptas_long_trip_advance():
	print("\n--- RACE-1: Kult of Speed Deffkoptas (M12), enemy 20\" away (in Kopta rokkit range) ---")
	var dk := _deffkoptas()
	var enemy := _enemy_at(20.0)
	_live([dk, enemy], ORKS_KOS)
	var old_v = _at(0.0, func(): return _race1(dk, {"U_ENEMY": enemy}))
	var new_v = _at(1.0, func(): return _race1(dk, {"U_ENEMY": enemy}))
	_assert(old_v == false, "FIX=0: no 'shoot' text -> the Deffkoptas walk to keep their rokkits (got %s)" % str(old_v))
	_assert(new_v == true, "FIX=1: Adrenaline Junkies gives [ASSAULT] after the Advance -> the Deffkoptas Advance (got %s)" % str(new_v))

func test_wazdakka_long_trip_advance():
	print("\n--- RACE-1 + RI-ASSAULT re-check: Wazdakka (M14, all [ASSAULT]), enemy 20\" away ---")
	var wz := _wazdakka()
	var enemy := _enemy_at(20.0)
	_live([wz, enemy], ORKS_KOS)
	var old_v = _at(0.0, func(): return _race1(wz, {"U_ENEMY": enemy}))
	var new_v = _at(1.0, func(): return _race1(wz, {"U_ENEMY": enemy}))
	_assert(old_v == false, "FIX=0: the RI-ASSAULT re-check reads the raw flag -> Wazdakka walks (enemy inside M+12\") (got %s)" % str(old_v))
	_assert(new_v == true, "FIX=1: the engine lets SPEED FREEKS Advance, shoot and charge -> Wazdakka Advances (got %s)" % str(new_v))

func test_blade_champion_keeps_the_charge_guard():
	print("\n--- RACE-1: Blade Champion (Martial Inspiration text, no ranged weapon), enemy 15\" away ---")
	var bc := _blade_champion()
	var enemy := _enemy_at(15.0)
	_live([bc, enemy], CUSTODES)
	var old_v = _at(0.0, func(): return _race1(bc, {"U_ENEMY": enemy}))
	var new_v = _at(1.0, func(): return _race1(bc, {"U_ENEMY": enemy}))
	_assert(old_v == true, "FIX=0: the text skips the M+12\" charge guard -> the Blade Champion Advances (got %s)" % str(old_v))
	_assert(new_v == false, "FIX=1: no engine advance-and-charge -> the guard keeps the charge, it walks (got %s)" % str(new_v))

func test_ri_assault_recheck_reads_engine_grant():
	print("\n--- RACE-1 RI-ASSAULT re-check: Custodian Guard after an Orion disembark (Assault Dropship), enemy 15\" away ---")
	var cg := _custodian_guard()
	cg["flags"]["cus11e_ab_dropship"] = true  # CustodesAbilities.F_DROPSHIP: may charge after its Advance
	var enemy := _enemy_at(15.0)
	_live([cg, enemy], CUSTODES)
	var old_v = _at(0.0, func(): return _race1(cg, {"U_ENEMY": enemy}))
	var new_v = _at(1.0, func(): return _race1(cg, {"U_ENEMY": enemy}))
	_assert(old_v == false, "FIX=0: no text and no raw flag -> the M+12\" guard makes it walk (got %s)" % str(old_v))
	_assert(new_v == true, "FIX=1: the engine grant keeps the charge and the [ASSAULT] spear keeps shooting -> it Advances (got %s)" % str(new_v))

func test_ri_assault_recheck_alone():
	print("\n--- RACE-1 RI-ASSAULT re-check alone: the same Custodian Guard with a text advance-and-charge too, enemy 15\" away ---")
	# The text (a 10e 'Martial Inspiration') and the engine (Assault Dropship)
	# both say advance-and-charge, so the M+12" guard is skipped at 0 and 1 and
	# neither says advance-and-shoot: only the RI-ASSAULT re-check differs (it
	# read the raw effect flag, which the Dropship grant does not set).
	var cg := _custodian_guard()
	cg["meta"]["abilities"] = [STAND_VIGIL, MARTIAL_INSPIRATION]
	cg["flags"]["cus11e_ab_dropship"] = true
	var enemy := _enemy_at(15.0)
	_live([cg, enemy], CUSTODES)
	var old_v = _at(0.0, func(): return _race1(cg, {"U_ENEMY": enemy}))
	var new_v = _at(1.0, func(): return _race1(cg, {"U_ENEMY": enemy}))
	_assert(old_v == false, "FIX=0: the RI-ASSAULT re-check reads the raw flag -> the M+12\" re-check makes it walk (got %s)" % str(old_v))
	_assert(new_v == true, "FIX=1: the re-check reads the engine grant -> it Advances, the [ASSAULT] spear keeps shooting (got %s)" % str(new_v))

func test_planner_prices_deffkoptas_trip_as_advance():
	print("\n--- planner: Deffkoptas, objective gap 30\" (3 turns walking), enemy 20\" to the side ---")
	var dk := _deffkoptas()
	var enemy := _unit("U_ENEMY", 2, "Enemy Squad", ["INFANTRY"], 6.0, [MELEE], [], 1, 40.0, {},
		ORIGIN + Vector2(20.0 * PX, 0))
	_live([dk, enemy], ORKS_KOS)
	var obj_pos := ORIGIN + Vector2(0, -(30.0 * PX + 151.5))
	var snap := {"battle_round": 2, "meta": {"battle_round": 2, "first_turn_player": 1},
		"board": {"objectives": [{"id": "obj_far", "position": obj_pos, "zone": "no_mans_land"}], "terrain_features": []},
		"units": {"U_DEFFKOPTAS_A": dk, "U_ENEMY": enemy},
		"factions": _gs().state["factions"]}
	var res := {}
	for v in [0.0, 1.0]:
		AIDM._config_overrides[FIX] = v
		AIDM._primary_awareness_p1 = {}
		AIDM._secondary_awareness_p1 = {}
		var evals = AIDM._evaluate_all_objectives(snap, [obj_pos], 1, {"U_ENEMY": enemy}, {"U_DEFFKOPTAS_A": dk}, 2)
		AIDM._assign_units_to_objectives(snap, {"U_DEFFKOPTAS_A": MOVABLE}, evals, [obj_pos],
			{"U_ENEMY": enemy}, {"U_DEFFKOPTAS_A": dk}, 1, 2)
		var cand := {}
		for c in AIDM._last_movement_candidates.get("U_DEFFKOPTAS_A", []):
			if str(c.objective_id) == "obj_far":
				cand = c
		print("  FIX=%d: obj_far candidate %s, %d turn(s)" % [int(v), str(cand.get("action", "?")), int(cand.get("turns_to_reach", 0))])
		res[v] = cand
	AIDM._config_overrides[FIX] = 1.0
	AIDM._primary_awareness_p1 = {}
	_assert(str(res[0.0].get("action", "")) == "move" and int(res[0.0].get("turns_to_reach", 0)) == 3,
		"FIX=0: the planner walks the Deffkoptas, 3 turns (%s, %d)" % [str(res[0.0].get("action", "")), int(res[0.0].get("turns_to_reach", 0))])
	_assert(str(res[1.0].get("action", "")) == "advance" and int(res[1.0].get("turns_to_reach", 0)) == 2,
		"FIX=1: the planner Advances the Deffkoptas, 2 turns (%s, %d)" % [str(res[1.0].get("action", "")), int(res[1.0].get("turns_to_reach", 0))])

# --- (c) guards: same answer at 0 and 1 ---------------------------------------------

func test_guard_riled_gretchin_unchanged():
	print("\n--- guard: riled-up Gretchin (effect_advance_and_charge set), target 10\" away ---")
	var grots := _gretchin({"waaagh_active": true, "effect_advance_and_charge": true})
	var enemy := _enemy_at(10.0)
	_live([grots, enemy], ORKS_KOS)
	var ev := {"id": "obj_nml_1", "zone": "no_mans_land", "state": "enemy_held", "priority": 5.0}
	var g0 = _at(0.0, func(): return _gap4(grots, 7.0, 2, ev, {"U_ENEMY": enemy}))
	var g1 = _at(1.0, func(): return _gap4(grots, 7.0, 2, ev, {"U_ENEMY": enemy}))
	_assert(g0 == true and g1 == true, "AI-GAP-4: a riled unit Advances and keeps its charge at 0 and 1 (%s, %s)" % [str(g0), str(g1)])
	var r0 = _at(0.0, func(): return _race1(grots, {"U_ENEMY": enemy}))
	var r1 = _at(1.0, func(): return _race1(grots, {"U_ENEMY": enemy}))
	_assert(r0 == false and r1 == false, "RACE-1: a target in pistol range still makes it walk at 0 and 1 (%s, %s)" % [str(r0), str(r1)])

func test_guard_warbikers_unchanged():
	print("\n--- guard: Kult of Speed Warbikers (text and engine both say advance-and-shoot), enemy 15\" away ---")
	var wb := _warbikers()
	var enemy := _enemy_at(15.0)
	_live([wb, enemy], ORKS_KOS)
	var r0 = _at(0.0, func(): return _race1(wb, {"U_ENEMY": enemy}))
	var r1 = _at(1.0, func(): return _race1(wb, {"U_ENEMY": enemy}))
	_assert(r0 == true and r1 == true, "RACE-1: Warbikers Advance at 0 and 1 (%s, %s)" % [str(r0), str(r1)])

func test_guard_custodian_guard_unchanged():
	print("\n--- guard: Custodian Guard (no grant, no matching text; [ASSAULT] spear) ---")
	var cg := _custodian_guard()
	var near := _enemy_at(15.0)
	_live([cg, near], CUSTODES)
	var n0 = _at(0.0, func(): return _race1(cg, {"U_ENEMY": near}))
	var n1 = _at(1.0, func(): return _race1(cg, {"U_ENEMY": near}))
	_assert(n0 == false and n1 == false, "RACE-1: enemy 15\" away (inside M+12\") -> walks at 0 and 1 (%s, %s)" % [str(n0), str(n1)])
	var far := _enemy_at(21.0)
	_live([cg, far], CUSTODES)
	var f0 = _at(0.0, func(): return _race1(cg, {"U_ENEMY": far}))
	var f1 = _at(1.0, func(): return _race1(cg, {"U_ENEMY": far}))
	_assert(f0 == true and f1 == true, "RACE-1 RI-ASSAULT: enemy 21\" away (in spear range, outside M+12\") -> Advances at 0 and 1 (%s, %s)" % [str(f0), str(f1)])

func test_guard_stompa_round1_no_mans_land_unchanged():
	print("\n--- guard: dormant-Waaagh! Stompa, round 1, no-man's-land objective, target in range ---")
	var stompa := _stompa()
	var enemy := _enemy_at(30.0)
	_live([stompa, enemy], ORKS_KOS)
	var ev := {"id": "obj_nml_1", "zone": "no_mans_land", "state": "uncontrolled", "priority": 5.0}
	var g0 = _at(0.0, func(): return _gap4(stompa, 11.0, 1, ev, {"U_ENEMY": enemy}))
	var g1 = _at(1.0, func(): return _gap4(stompa, 11.0, 1, ev, {"U_ENEMY": enemy}))
	_assert(g0 == true and g1 == true, "AI-GAP-4: the round-1 no-man's-land rule still Advances at 0 and 1 (%s, %s)" % [str(g0), str(g1)])
