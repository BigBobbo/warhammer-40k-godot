extends SceneTree

# FIX_STAY_ENGAGED (COO-18; absorbs SUR-06 / SUR-18 / DEN-15 / OFF-09):
# _decide_engaged_unit's default branch fell back whenever the unit was not on
# an objective — even locked with a unit it wipes in its own Fight phase, where
# it strikes first (11e 12.04: the active player selects first when no Fights
# First unit is eligible). The survival assessment's "hold" / "fall_back"
# recommendation and SURVIVAL_HOLD_BONUS / SURVIVAL_FALL_BACK_BONUS were never
# read.
#
# Fix: at the default fall-back point, an "engaged_choice" STAY-vs-LEAVE
# ledger in points (points per wound): STAY = the fight (+ wipe bonus), the
# strike-back after our first casualties, close-quarters shooting (10.06),
# a locked shooter / pinned holder (04.02, 09.07, 16.01), the shooting it is
# shielded from while engaged (04.02; 17.03), the "hold" bias; LEAVE = Fall
# Back and Shoot / Charge, an objective the fall back takes (14.02), Desperate
# Escape hazard + battle-shock rolls (09.07; Commentary 09.07.01), the
# "fall_back" bias — priced on the fall-back generator's own destinations.
#
# Cases (a) behaviour, (b) FIX_STAY_ENGAGED = 0 restores the old decision
# byte for byte, (c) guards that must not change: no fall-back path, 10e,
# only REMAIN_STATIONARY offered, on an objective where leaving changes
# control, not engaged by the AI's own measure; plus the ledger invariant
# (every candidate's score is the sum of its terms).
#
# Run with: godot --headless --path . -s tests/unit/test_ai_fix_stay_engaged.gd
# (runs once the scene tree is up: the fix reads RulesEngine, MissionManager
# and the fall-back move type)

const AI_PATH := "res://scripts/AIDecisionMaker.gd"
const GameStateData = preload("res://autoloads/GameState.gd")
const FAR_OBJ := Vector2(1500, 300)
const SPEAR := {"name": "Guardian spear", "type": "Melee", "range": "Melee", "attacks": "5", "weapon_skill": "2",
	"strength": "7", "ap": "-2", "damage": "2", "special_rules": ""}
const CCW_WEAK := {"name": "Close combat weapon", "type": "Melee", "range": "Melee", "attacks": "2", "weapon_skill": "3",
	"strength": "3", "ap": "0", "damage": "1", "special_rules": ""}
const SHANK := {"name": "Shank", "type": "Melee", "range": "Melee", "attacks": "1", "weapon_skill": "5",
	"strength": "2", "ap": "0", "damage": "1", "special_rules": ""}
const CLAW := {"name": "Claw", "type": "Melee", "range": "Melee", "attacks": "6", "weapon_skill": "3",
	"strength": "6", "ap": "-1", "damage": "2", "special_rules": ""}
const AXE := {"name": "Axe", "type": "Melee", "range": "Melee", "attacks": "2", "weapon_skill": "3",
	"strength": "6", "ap": "-1", "damage": "2", "special_rules": ""}
const CLUB := {"name": "Club", "type": "Melee", "range": "Melee", "attacks": "2", "weapon_skill": "3",
	"strength": "4", "ap": "0", "damage": "1", "special_rules": ""}
const BOLTGUN := {"name": "Boltgun", "type": "Ranged", "range": "24", "attacks": "2", "ballistic_skill": "3",
	"strength": "4", "ap": "0", "damage": "1", "special_rules": ""}
const HEAVY_GUN := {"name": "Heavy gun", "type": "Ranged", "range": "36", "attacks": "3", "ballistic_skill": "3",
	"strength": "9", "ap": "-2", "damage": "3", "special_rules": ""}
const PISTOL := {"name": "Bolt pistol", "type": "Ranged", "range": "12", "attacks": "1", "ballistic_skill": "3",
	"strength": "4", "ap": "0", "damage": "1", "special_rules": "pistol"}
const PARAMS := ["FIX_STAY_ENGAGED", "STAY_ENGAGED_STRIKE_FIRST", "STAY_ENGAGED_CQ_WEIGHT", "STAY_ENGAGED_FREE_TARGET_WEIGHT"]
const LASCANNON := {"name": "Lascannon", "type": "Ranged", "range": "48", "attacks": "1", "ballistic_skill": "3",
	"strength": "12", "ap": "-3", "damage": "6", "special_rules": ""}
## The Orks_2000.json Burna profile: D6 attacks, BS "N/A", [TORRENT] (24.37: no hit roll).
const BURNA := {"name": "Burna", "type": "Ranged", "range": "12", "attacks": "D6", "ballistic_skill": "N/A",
	"strength": "4", "ap": "0", "damage": "1", "special_rules": "ignores cover, torrent",
	"abilities": [{"id": "ignores_cover"}, {"id": "torrent"}]}
const MULTI_MELTA := {"name": "Multi-melta", "type": "Ranged", "range": "18", "attacks": "2", "ballistic_skill": "4",
	"strength": "9", "ap": "-4", "damage": "D6", "special_rules": "melta 2"}
const MM_PX := 40.0 / 25.4

var _pass_count: int = 0
var _fail_count: int = 0
var _ran := false
var AIDM = null
var _last_records: Array = []
var _all_records: Array = []

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

func _near(a: float, b: float, tol: float = 0.05) -> bool:
	return absf(a - b) <= tol

func _run_tests():
	if _ran:
		return
	_ran = true
	await process_frame
	print("\n=== FIX_STAY_ENGAGED: stay engaged on purpose (STAY vs LEAVE ledger) ===\n")
	var tm = root.get_node_or_null("TerrainManager")
	var re = root.get_node_or_null("RulesEngine")
	_assert(tm != null and re != null, "TerrainManager / RulesEngine autoloads present")
	if tm == null or re == null:
		print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
		quit(1)
		return
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	var prev_terrain = tm.terrain_features.duplicate(true)
	tm.terrain_features = []
	if re.has_method("clear_los_memo"):
		re.clear_los_memo()
	AIDM = load(AI_PATH)

	test_finish_the_enemy_stays()
	test_param_zero_restores_old_reads()
	test_losing_fight_falls_back()
	test_strike_first_discount()
	test_shield_counts_reaching_shooters()
	test_lock_target_and_holder()
	test_vehicle_close_quarters_shooting()
	test_desperate_escape_prices_hazards()
	test_fall_back_and_x_leave_values()
	test_leave_objective_when_control_changes()
	test_on_objective_control_change_skips()
	test_on_objective_losing_runs()
	test_guard_no_fall_back_path_unchanged()
	test_guard_edition_10_unchanged()
	test_guard_only_remain_stationary_offered()
	test_guard_not_engaged_unchanged()
	# Review fixes
	test_strike_first_friendly_charger_hands_over()
	test_strike_first_contested_combats()
	test_free_target_for_our_guns()
	test_ranged_damage_weapon_keywords()
	test_desperate_escape_rolls_match_engine()
	test_crossing_predicate_shape_aware()
	test_crossing_costs_nothing_until_engine_refuses()
	test_reason_when_staying_is_a_loss()
	test_ledger_sums()

	for p in PARAMS:
		AIDM._config_overrides.erase(p)
	AIDM.reset_caches()
	AIDM.clear_all_plans()
	tm.terrain_features = prev_terrain
	if re.has_method("clear_los_memo"):
		re.clear_los_memo()
	GameConstants.edition = prev_edition
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 or _pass_count == 0 else 0)

# --- fixtures ---------------------------------------------------------------

func _snapshot(battle_round: int = 2, objs: Array = [], first_turn_player: int = 1) -> Dictionary:
	var o: Array = objs if not objs.is_empty() else [{"id": "obj_far", "position": FAR_OBJ, "zone": "no_mans_land"}]
	return {"battle_round": battle_round,
		"meta": {"battle_round": battle_round, "first_turn_player": first_turn_player, "active_player": 1},
		"board": {"objectives": o, "terrain_features": []}, "units": {}}

func _line(x0: float, dx: float, y: float, n: int) -> Array:
	var out: Array = []
	for k in range(n):
		out.append(Vector2(x0 + dx * float(k), y))
	return out

func _add(snap: Dictionary, uid: String, owner: int, positions: Array, weapons: Array, toughness: int,
		save: int, wounds: int, points: int, keywords: Array = ["INFANTRY"], base_mm: int = 40,
		flags: Dictionary = {}, stats_extra: Dictionary = {}) -> Dictionary:
	var models = []
	for i in range(positions.size()):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": base_mm, "base_type": "circular",
			"base_dimensions": {}, "position": positions[i], "wounds": wounds, "current_wounds": wounds})
	var stats := {"move": 6, "toughness": toughness, "save": save, "wounds": wounds,
		"leadership": 6, "objective_control": 2}
	for k in stats_extra:
		stats[k] = stats_extra[k]
	var u = {"id": uid, "owner": owner, "status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"name": uid, "points": points, "stats": stats, "keywords": keywords, "weapons": weapons},
		"models": models, "flags": flags.duplicate()}
	snap.units[uid] = u
	return u

## Custodian Guard (5 x 40 mm, guardian spears, T6 Sv2 4++ W4, 215 pts) in a
## line at y; the 32 mm / 40 mm line 80 px below it is 0.43-0.58" away (engaged).
func _add_cg(snap: Dictionary, uid: String, owner: int, y: float, flags: Dictionary = {}) -> Dictionary:
	return _add(snap, uid, owner, _line(600, 65, y, 5), [SPEAR], 6, 2, 4, 215, ["INFANTRY"], 40, flags, {"invuln": 4})

## Prosecutors (4 x 32 mm, close combat weapons, T3 Sv3 W1, 45 pts).
func _add_pz(snap: Dictionary, uid: String, owner: int, y: float) -> Dictionary:
	return _add(snap, uid, owner, _line(630, 50, y, 4), [CCW_WEAK], 3, 3, 1, 45, ["INFANTRY"], 32)

func _set_param(param: String, v: float) -> void:
	AIDM._config_overrides[param] = v

func _set_fix(v: float) -> void:
	_set_param("FIX_STAY_ENGAGED", v)

func _reset() -> void:
	AIDM.reset_caches()
	AIDM.clear_all_plans()
	AIDM._config_overrides.erase("STAY_ENGAGED_STRIKE_FIRST")
	AIDM._config_overrides.erase("STAY_ENGAGED_CQ_WEIGHT")
	AIDM._config_overrides.erase("STAY_ENGAGED_FREE_TARGET_WEIGHT")
	AIDM._thinking_steps.clear()

func _engaged(snap: Dictionary, uid: String, move_types: Array = ["BEGIN_FALL_BACK", "REMAIN_STATIONARY"]) -> Dictionary:
	AIDM._decision_records.clear()
	var enemies = AIDM._get_enemy_units(snap, 1)
	var d = AIDM._decide_engaged_unit(snap.units[uid], uid, uid, move_types,
		AIDM._get_objectives(snap), enemies, snap, 1)
	_last_records = AIDM._decision_records.duplicate(true)
	for r in _last_records:
		_all_records.append(r)
	print("  %s: %s / %s" % [uid, str(d.get("type", "")), str(d.get("_ai_description", ""))])
	return d

func _choice() -> Dictionary:
	for i in range(_last_records.size() - 1, -1, -1):
		if str(_last_records[i].get("decision_type", "")) == "engaged_choice":
			return _last_records[i]
	return {}

func _chosen_key(rec: Dictionary) -> String:
	var c: Array = rec.get("candidates", [])
	var ci := int(rec.get("chosen_index", -1))
	return str(c[ci].get("key", "")) if ci >= 0 and ci < c.size() else ""

func _cand(rec: Dictionary, key: String) -> Dictionary:
	for c in rec.get("candidates", []):
		if str(c.get("key", "")) == key:
			return c
	return {}

func _term(rec: Dictionary, side: String, term: String) -> float:
	return float(_cand(rec, side).get("score_breakdown", {}).get(term, 0.0))

func _has_term(rec: Dictionary, side: String, term: String) -> bool:
	return _cand(rec, side).get("score_breakdown", {}).has(term)

func _notes(d: Dictionary) -> String:
	return " | ".join(PackedStringArray(d.get("_ai_move_adjustments", [])))

# --- (a) behaviour ------------------------------------------------------------

func test_finish_the_enemy_stays() -> void:
	print("\n--- (a) Custodian Guard locked with 4 Prosecutors it wipes, off every objective ---")
	_reset()
	_set_fix(1.0)
	var snap = _snapshot()
	_add_cg(snap, "CG", 1, 1200)
	_add_pz(snap, "PZ", 2, 1280)
	var d = _engaged(snap, "CG")
	var rec = _choice()
	_assert(str(d.get("type", "")) == "REMAIN_STATIONARY", "stays: REMAIN_STATIONARY (got %s)" % str(d.get("type", "")))
	_assert(str(d.get("_ai_description", "")).begins_with("CG stays engaged with PZ"),
		"description says it stays engaged with PZ (%s)" % str(d.get("_ai_description", "")))
	_assert(_notes(d).contains("Wipes out PZ"), "move note: wipes out PZ in our own Fight phase (%s)" % _notes(d))
	_assert(_notes(d).contains("12.04"), "move note cites the strike-first rule (12.04)")
	_assert(str(rec.get("decision_type", "")) == "engaged_choice" and _chosen_key(rec) == "stay",
		"engaged_choice record, chosen key 'stay' (got %s / %s)" % [str(rec.get("decision_type", "")), _chosen_key(rec)])
	_assert(_near(_term(rec, "stay", "stay_fight"), 45.0), "stay_fight = 4 W x 11.25 pts/W = 45.0 (got %.3f)" % _term(rec, "stay", "stay_fight"))
	_assert(_near(_term(rec, "stay", "stay_kill"), 11.25), "stay_kill = 25%% of 45 pts = 11.25 (got %.3f)" % _term(rec, "stay", "stay_kill"))
	_assert(_near(_term(rec, "stay", "stay_survival"), 16.125), "stay_survival = 1.5 x 10.75 pts/W = 16.125 (got %.3f)" % _term(rec, "stay", "stay_survival"))
	_assert(not _has_term(rec, "stay", "stay_loss"), "no strike-back: wiped before it strikes (12.04)")
	_assert(_near(float(_cand(rec, "fall_back").get("score", -1.0)), 0.0), "falling back is worth 0 (got %.3f)" % float(_cand(rec, "fall_back").get("score", -1.0)))
	_assert(str(rec.get("context", {}).get("fall_back_mode", "")) == "ordered_retreat", "fall-back mode: ordered retreat (not battle-shocked)")

# --- (b) param 0 ---------------------------------------------------------------

func test_param_zero_restores_old_reads() -> void:
	print("\n--- (b) FIX_STAY_ENGAGED = 0: the old fall back, byte for byte ---")
	_reset()
	_set_fix(0.0)
	var snap = _snapshot()
	_add_cg(snap, "CG", 1, 1200)
	_add_pz(snap, "PZ", 2, 1280)
	var d = _engaged(snap, "CG")
	_assert(str(d.get("type", "")) == "BEGIN_FALL_BACK", "flag 0: falls back (got %s)" % str(d.get("type", "")))
	_assert(str(d.get("_ai_description", "")) == "CG falls back (not on objective)",
		"flag 0: the old description (got %s)" % str(d.get("_ai_description", "")))
	_assert(not d.has("_ai_move_adjustments"), "flag 0: no _ai_move_adjustments key")
	_assert(d.keys() == ["type", "actor_unit_id", "_ai_model_destinations", "_ai_description"],
		"flag 0: the old keys in the old order (got %s)" % str(d.keys()))
	_assert(_choice().is_empty(), "flag 0: no engaged_choice record")
	_reset()
	var dests = AIDM._compute_fall_back_destinations(snap.units.CG, "CG", snap, AIDM._get_enemy_units(snap, 1),
		AIDM._get_objectives(snap), 1)
	_assert(str(d.get("_ai_model_destinations", {})) == str(dests),
		"flag 0: destinations are _compute_fall_back_destinations' own")
	# A losing fight (our Prosecutors locked with Allarus Custodians): with the
	# flag on LEAVE wins, and the fall back uses the very destinations the
	# ledger priced — the same ones the flag-off decision returns.
	_reset()
	var snap2 = _snapshot()
	_add_pz(snap2, "PZ", 1, 1200)
	_add(snap2, "AL", 2, _line(600, 65, 1280, 5), [SPEAR], 7, 2, 4, 275, ["INFANTRY"], 40, {}, {"invuln": 4})
	_set_fix(1.0)
	var d_on = _engaged(snap2, "PZ")
	_set_fix(0.0)
	var d_off = _engaged(snap2, "PZ")
	_assert(str(d_on.get("type", "")) == "BEGIN_FALL_BACK" and str(d_on.get("_ai_model_destinations", {})) == str(d_off.get("_ai_model_destinations", {})),
		"flag on, LEAVE wins: the same destinations as flag 0 (%s)" % str(d_on.get("_ai_description", "")))
	_assert(str(d_off.get("_ai_description", "")) == "PZ falls back (not on objective, survival LETHAL (11.6 dmg vs 4.0 wounds))",
		"flag 0: the old losing-fight description (%s)" % str(d_off.get("_ai_description", "")))
	_set_fix(1.0)

func test_losing_fight_falls_back() -> void:
	print("\n--- (a) our Prosecutors locked with Allarus Custodians that kill them ---")
	_reset()
	_set_fix(1.0)
	var snap = _snapshot()
	_add_pz(snap, "PZ", 1, 1200)
	_add(snap, "AL", 2, _line(600, 65, 1280, 5), [SPEAR], 7, 2, 4, 275, ["INFANTRY"], 40, {}, {"invuln": 4})
	var d = _engaged(snap, "PZ")
	var rec = _choice()
	_assert(str(d.get("type", "")) == "BEGIN_FALL_BACK", "falls back (got %s)" % str(d.get("type", "")))
	_assert(_chosen_key(rec) == "fall_back", "engaged_choice chose 'fall_back' (got %s)" % _chosen_key(rec))
	_assert(_near(_term(rec, "stay", "stay_loss"), -45.0), "stay_loss = -4 W x 11.25 = -45.0 (got %.3f)" % _term(rec, "stay", "stay_loss"))
	_assert(_near(_term(rec, "stay", "stay_fight"), 2.037, 0.01), "stay_fight = 0.148 dmg x 13.75 pts/W = 2.04 (got %.3f)" % _term(rec, "stay", "stay_fight"))
	_assert(_near(_term(rec, "fall_back", "leave_survival"), 22.5), "leave_survival = 2 x 11.25 = 22.5 (got %.3f)" % _term(rec, "fall_back", "leave_survival"))
	_assert(str(d.get("_ai_description", "")).contains("falling back is worth 22.5 pts, staying -43.0"),
		"description gives both values (%s)" % str(d.get("_ai_description", "")))
	_assert(_notes(d).contains("staying would cost 4.0 wounds (45 pts) to AL"), "move note: what staying would cost (%s)" % _notes(d))

func test_strike_first_discount() -> void:
	print("\n--- (a) Custodian Guard vs a Custodian Guard clone: who strikes first (12.04) ---")
	_reset()
	_set_fix(1.0)
	var snap = _snapshot()
	_add_cg(snap, "CG", 1, 1200)
	_add_cg(snap, "CG2", 2, 1280)
	_engaged(snap, "CG")
	var ctx: Dictionary = _choice().get("context", {})
	# 25 x 5/6 x 4/6 x 1/2 x 2 = 13.89 each way; we strike first and kill 69%.
	_assert(_near(float(ctx.get("out_dmg", 0.0)), 13.89, 0.02), "out = 13.89 (got %s)" % str(ctx.get("out_dmg", "")))
	_assert(_near(float(ctx.get("in_dmg_after_first_strike", 0.0)), 4.24, 0.02),
		"strike-back after our first casualties = 13.89 x (1 - 13.89/20) = 4.24 (got %s)" % str(ctx.get("in_dmg_after_first_strike", "")))
	_assert(_chosen_key(_choice()) == "stay", "strikes first: stays (got %s)" % _chosen_key(_choice()))
	snap.units.CG2.flags["fights_first"] = true
	_engaged(snap, "CG")
	ctx = _choice().get("context", {})
	_assert(_near(float(ctx.get("in_dmg_after_first_strike", 0.0)), 13.89, 0.02),
		"enemy has Fights First: no discount (got %s)" % str(ctx.get("in_dmg_after_first_strike", "")))
	_assert(not bool(ctx.get("we_strike_first", true)), "context: we do not strike first")
	snap.units.CG2.flags.erase("fights_first")
	_set_param("STAY_ENGAGED_STRIKE_FIRST", 0.0)
	_engaged(snap, "CG")
	ctx = _choice().get("context", {})
	_assert(_near(float(ctx.get("in_dmg_after_first_strike", 0.0)), 13.89, 0.02),
		"STAY_ENGAGED_STRIKE_FIRST = 0: the raw estimate (got %s)" % str(ctx.get("in_dmg_after_first_strike", "")))
	AIDM._config_overrides.erase("STAY_ENGAGED_STRIKE_FIRST")

## Our squad (5 x T4 Sv3 W2, 100 pts) near the north edge, locked with a
## durable single model (T10 Sv2 W12, 200 pts); three enemy squads of 10
## boltguns 18-22" south of it (in reach: 24" + 6" move) or 47"+ away at the
## south edge (out of reach).
func _shield_board(shooters_near: bool, vehicle: bool) -> Dictionary:
	var snap = _snapshot()
	_add(snap, "SH", 1, _line(630, 50, 300, 5), [AXE], 4, 3, 2, 100, ["VEHICLE"] if vehicle else ["INFANTRY"], 32)
	_add(snap, "TANKY", 2, [Vector2(730, 380)], [CLAW], 10, 2, 12, 200, ["INFANTRY"], 40)
	for i in range(3):
		var y := (1100.0 + 60.0 * float(i)) if shooters_near else (2250.0 + 60.0 * float(i))
		_add(snap, "S%d" % (i + 1), 2, _line(500, 52, y, 10), [BOLTGUN], 4, 3, 1, 100, ["INFANTRY"], 32)
	return snap

func test_shield_counts_reaching_shooters() -> void:
	print("\n--- (a) shield: an engaged unit cannot be shot (04.02) ---")
	_reset()
	_set_fix(1.0)
	var snap = _shield_board(true, false)
	var d = _engaged(snap, "SH")
	var rec = _choice()
	var ctx: Dictionary = rec.get("context", {})
	var shield := _term(rec, "stay", "stay_shield")
	var saved := 0.0
	for sid in ["S1", "S2", "S3"]:
		saved += AIDM._stay_engaged_ranged_damage(snap.units[sid], snap.units.SH, 0)
	var in_adj := float(ctx.get("in_dmg_after_first_strike", 0.0))
	var p_eng := 1.0 - clampf(float(ctx.get("out_dmg", 0.0)) / 12.0, 0.0, 1.0)
	var expect := 0.5 * (1.0 - in_adj / 10.0) * p_eng * 0.5 * minf(saved, 10.0 - in_adj) * 10.0
	print("  shield %.3f, saved %.3f, expected %.3f" % [shield, saved, expect])
	_assert(shield > 0.0 and _near(shield, expect, 0.05), "stay_shield = the 04.02 formula (got %.3f, expected %.3f)" % [shield, expect])
	_assert(str(d.get("type", "")) == "REMAIN_STATIONARY", "with the shooters in reach: stays (got %s)" % str(d.get("type", "")))
	_assert(_notes(d).contains("Cannot be shot by 3 enemy unit(s)"), "move note counts the 3 shooters (%s)" % _notes(d))
	var far = _shield_board(false, false)
	var d_far = _engaged(far, "SH")
	_assert(not _has_term(_choice(), "stay", "stay_shield"), "shooters 47\"+ away: no stay_shield")
	_assert(str(d_far.get("type", "")) == "BEGIN_FALL_BACK", "shooters out of reach: falls back (got %s)" % str(d_far.get("type", "")))
	var veh = _shield_board(true, true)
	_engaged(veh, "SH")
	var shield_v := _term(_choice(), "stay", "stay_shield")
	var partial := 0.0
	for sid in ["S1", "S2", "S3"]:
		partial += AIDM._stay_engaged_ranged_damage(veh.units[sid], veh.units.SH, 1, false, false, true)
	var ctx_v: Dictionary = _choice().get("context", {})
	var in_v := float(ctx_v.get("in_dmg_after_first_strike", 0.0))
	var p_v := 1.0 - clampf(float(ctx_v.get("out_dmg", 0.0)) / 12.0, 0.0, 1.0)
	var expect_v := 0.25 * (1.0 - in_v / 10.0) * p_v * minf(saved - partial, 10.0 - in_v) * 10.0
	print("  vehicle shield %.3f, expected %.3f" % [shield_v, expect_v])
	_assert(shield_v > 0.0 and shield_v < shield and _near(shield_v, expect_v, 0.05),
		"VEHICLE: only the -1 to hit / no-[BLAST] share is saved (17.03): %.3f < %.3f" % [shield_v, shield])

## Our squad (5 x T4 W2, 100 pts) locked with an enemy gun unit E (3 x W3,
## heavy guns, 150 pts) that nobody kills this turn.
func _lock_board(e_keywords: Array = ["INFANTRY"], e_flags: Dictionary = {}, br: int = 2, ftp: int = 1,
		e_on_objective: bool = false) -> Dictionary:
	var objs: Array = [{"id": "obj_far", "position": FAR_OBJ}]
	if e_on_objective:
		objs.append({"id": "obj_e", "position": Vector2(730, 1400)})
	var snap = _snapshot(br, objs, ftp)
	_add(snap, "LK", 1, _line(600, 65, 1200, 5), [CCW_WEAK], 4, 3, 2, 100, ["INFANTRY"], 40)
	_add(snap, "E", 2, _line(665, 65, 1280, 3), [HEAVY_GUN, SHANK], 5, 3, 3, 150, e_keywords, 40, e_flags)
	return snap

func test_lock_target_and_holder() -> void:
	print("\n--- (a) lock target (phase plan) and pinned objective holder ---")
	_reset()
	_set_fix(1.0)
	var plan := {"lock_targets": ["E"], "charge_intent": {}, "shooting_lanes": {}, "charge_target_ids": []}
	AIDM._phase_plan[1] = plan
	_engaged(_lock_board(), "LK")
	var lock := _term(_choice(), "stay", "stay_lock")
	_assert(lock > 0.0, "E is a lock target: stay_lock > 0 (got %.3f)" % lock)
	AIDM._phase_plan[1] = {"lock_targets": [], "charge_intent": {}, "shooting_lanes": {}, "charge_target_ids": []}
	_engaged(_lock_board(), "LK")
	_assert(not _has_term(_choice(), "stay", "stay_lock"), "no lock targets: no stay_lock")
	AIDM._phase_plan[1] = plan
	_engaged(_lock_board(["VEHICLE"]), "LK")
	var lock_v := _term(_choice(), "stay", "stay_lock")
	_assert(lock > 0.0 and _near(lock_v / lock, 0.25, 0.001), "VEHICLE lock target: x 0.25 (it keeps close-quarters shooting) (ratio %.4f)" % (lock_v / maxf(lock, 0.0001)))
	_engaged(_lock_board(["INFANTRY"], {"effect_fall_back_and_shoot": true}), "LK")
	_assert(not _has_term(_choice(), "stay", "stay_lock"), "lock target with Fall Back and Shoot: denied nothing")
	AIDM._phase_plan[1] = {"lock_targets": [], "charge_intent": {}, "shooting_lanes": {}, "charge_target_ids": []}
	var d_h = _engaged(_lock_board(["INFANTRY"], {}, 2, 1, true), "LK")
	var rec_h = _choice()
	var ctx: Dictionary = rec_h.get("context", {})
	var surv_u := 1.0 - float(ctx.get("in_dmg_after_first_strike", 0.0)) / 10.0
	var surv_e := 1.0 - float(ctx.get("out_dmg", 0.0)) / 9.0
	var hold_expect := 0.15 * 150.0 * surv_u * surv_e
	_assert(_near(_term(rec_h, "stay", "stay_lock"), hold_expect, 0.05),
		"E holds an objective: pinned for 0.15 x 150 pts x survival (got %.3f, expected %.3f)" % [_term(rec_h, "stay", "stay_lock"), hold_expect])
	_assert(_notes(d_h).contains("Pins E"), "move note: pins E (16.01) (%s)" % _notes(d_h))
	AIDM._phase_plan[1] = plan
	_engaged(_lock_board(["INFANTRY"], {}, 5, 2, false), "LK")
	_assert(not _has_term(_choice(), "stay", "stay_lock") and not _has_term(_choice(), "stay", "stay_shield"),
		"round 5, we play second: no enemy turn left, no lock / shield")
	AIDM._phase_plan.erase(1)

## Our VEHICLE (1 model, T10 Sv3 W12, heavy gun, 150 pts) locked with chaff
## (10 x T3 Sv7 W1, 50 pts); another enemy unit (5 x T4 Sv3 W2) 18" away.
func _cq_board(keywords: Array, weapons: Array) -> Dictionary:
	var snap = _snapshot()
	_add(snap, "VH", 1, [Vector2(730, 1200)], weapons, 10, 3, 12, 150, keywords, 60)
	var chaff: Array = []
	for k in range(10):
		chaff.append(Vector2(730.0 + 42.0 * (float(k) - 4.5), 1287.0))
	_add(snap, "CHAFF", 2, chaff, [SHANK], 3, 7, 1, 50, ["INFANTRY"], 25)
	_add(snap, "MARINES", 2, _line(626, 52, 400, 5), [BOLTGUN], 4, 3, 2, 100, ["INFANTRY"], 32)
	return snap

func test_vehicle_close_quarters_shooting() -> void:
	print("\n--- (a) close-quarters shooting (10.06) ---")
	_reset()
	_set_fix(1.0)
	var snap = _cq_board(["VEHICLE"], [HEAVY_GUN, CCW_WEAK])
	var d = _engaged(snap, "VH")
	var rec = _choice()
	var cq := _term(rec, "stay", "stay_cq_shoot")
	var out := float(rec.get("context", {}).get("out_dmg", 0.0))
	var a_dmg: float = AIDM._stay_engaged_ranged_damage(snap.units.VH, snap.units.CHAFF, 1, true, false, true)
	var a_take := (minf(out + a_dmg, 10.0) - minf(out, 10.0)) * 5.0
	var gap: float = AIDM._get_closest_model_distance_inches(snap.units.VH, snap.units.MARINES)
	var b_dmg: float = AIDM._stay_engaged_ranged_damage(snap.units.VH, snap.units.MARINES, 1, false, false, false, gap)
	var b_take := minf(b_dmg, 10.0) * 10.0
	print("  cq %.3f, option A %.3f, option B %.3f" % [cq, a_take, b_take])
	_assert(cq > 0.0 and _near(cq, maxf(a_take, b_take), 0.01), "VEHICLE: stay_cq_shoot = max(engaged chaff, the unit 18\" away) (got %.3f)" % cq)
	_assert(str(d.get("type", "")) == "REMAIN_STATIONARY", "VEHICLE keeps shooting: stays (got %s)" % str(d.get("type", "")))
	_assert(_notes(d).contains("close-quarters shooting (10.06)"), "move note: close-quarters shooting (%s)" % _notes(d))
	_engaged(_cq_board(["INFANTRY"], [HEAVY_GUN, CCW_WEAK]), "VH")
	_assert(not _has_term(_choice(), "stay", "stay_cq_shoot"), "not MONSTER/VEHICLE, no [CLOSE-QUARTERS] weapon: no stay_cq_shoot")
	_engaged(_cq_board(["INFANTRY"], [PISTOL, CCW_WEAK]), "VH")
	_assert(not _has_term(_choice(), "stay", "stay_cq_shoot"), "[PISTOL] at the default STAY_ENGAGED_CQ_WEIGHT 0: not counted")
	_set_param("STAY_ENGAGED_CQ_WEIGHT", 1.0)
	_engaged(_cq_board(["INFANTRY"], [PISTOL, CCW_WEAK]), "VH")
	_assert(_term(_choice(), "stay", "stay_cq_shoot") > 0.0, "[PISTOL] with STAY_ENGAGED_CQ_WEIGHT 1: counted (got %.3f)" % _term(_choice(), "stay", "stay_cq_shoot"))
	AIDM._config_overrides.erase("STAY_ENGAGED_CQ_WEIGHT")

## Our grunts (5 x 32 mm W1, 75 pts, Ld 6) in a mildly losing fight with
## brutes (4 x W2, 80 pts) that take 1.1 damage and deal 1.3.
func _de_board(flags: Dictionary) -> Dictionary:
	var snap = _snapshot()
	_add(snap, "GR", 1, _line(630, 50, 1200, 5), [CCW_WEAK], 4, 4, 1, 75, ["INFANTRY"], 32, flags)
	_add(snap, "BR", 2, _line(630, 50, 1280, 4), [CLUB], 4, 4, 2, 80, ["INFANTRY"], 32)
	return snap

func test_desperate_escape_prices_hazards() -> void:
	print("\n--- (a) Desperate Escape: hazard rolls (06.03) and the battle-shock roll (09.07) ---")
	_reset()
	_set_fix(1.0)
	var d0 = _engaged(_de_board({}), "GR")
	_assert(str(d0.get("type", "")) == "BEGIN_FALL_BACK" and not _has_term(_choice(), "fall_back", "leave_hazard"),
		"Ordered Retreat: no hazard, the mildly losing fight falls back (got %s)" % str(d0.get("type", "")))
	var d1 = _engaged(_de_board({"battle_shocked": true}), "GR")
	var rec1 = _choice()
	_assert(_near(_term(rec1, "fall_back", "leave_hazard"), -(5.0 * 2.0 / 6.0) * 15.0),
		"battle-shocked: 5 hazard rolls x 1/3 x 15 pts/W = -25.0 (got %.3f)" % _term(rec1, "fall_back", "leave_hazard"))
	_assert(not _has_term(rec1, "fall_back", "leave_shock"), "battle-shocked: no further battle-shock roll")
	_assert(str(d1.get("type", "")) == "REMAIN_STATIONARY", "the hazard tips the mildly losing fight to staying (got %s)" % str(d1.get("type", "")))
	_assert(str(rec1.get("context", {}).get("fall_back_mode", "")) == "desperate_escape", "mode: desperate escape (mandatory)")
	_engaged(_de_board({"effect_cut_em_down": true}), "GR")
	var rec2 = _choice()
	_assert(str(rec2.get("context", {}).get("forced_by", "")) != "", "forced by an enemy rule (Commentary 09.07.01): %s" % str(rec2.get("context", {}).get("forced_by", "")))
	_assert(_near(_term(rec2, "fall_back", "leave_hazard"), -25.0), "forced: the same hazard (got %.3f)" % _term(rec2, "fall_back", "leave_hazard"))
	_assert(_near(_term(rec2, "fall_back", "leave_shock"), -0.1 * 75.0 * 10.0 / 36.0, 0.01),
		"forced, not battle-shocked: battle-shock roll -0.1 x 75 x P(2D6 < 6) = -2.08 (got %.3f)" % _term(rec2, "fall_back", "leave_shock"))
	_engaged(_de_board({"effect_cut_em_down": true, "effect_cut_em_down_minus1": true}), "GR")
	_assert(_near(_term(_choice(), "fall_back", "leave_hazard"), -(5.0 * 3.0 / 6.0) * 15.0),
		"-1 to the hazard rolls: fails on 1-3 = -37.5 (got %.3f)" % _term(_choice(), "fall_back", "leave_hazard"))

func test_fall_back_and_x_leave_values() -> void:
	print("\n--- (a) Fall Back and Shoot / Fall Back and Charge ---")
	_reset()
	_set_fix(1.0)
	var snap = _snapshot()
	_add(snap, "FX", 1, _line(600, 65, 1200, 5), [SPEAR, BOLTGUN], 6, 2, 4, 215, ["INFANTRY"], 40,
		{"effect_fall_back_and_shoot": true}, {"invuln": 4})
	_add_cg(snap, "EN", 2, 1280)
	_engaged(snap, "FX")
	_assert(_term(_choice(), "fall_back", "leave_fb_shoot") > 0.0,
		"Fall Back and Shoot: the boltguns still have a shot after the fall back (got %.3f)" % _term(_choice(), "fall_back", "leave_fb_shoot"))
	var snap2 = _snapshot()
	var fc = _add(snap2, "FC", 1, _line(600, 65, 1200, 5), [SPEAR], 6, 2, 4, 215, ["INFANTRY"], 40,
		{"effect_fall_back_and_charge": true}, {"invuln": 4})
	_add_cg(snap2, "EN", 2, 1280)
	_engaged(snap2, "FC")
	var rec = _choice()
	var ctx: Dictionary = rec.get("context", {})
	_reset()
	var dests = AIDM._compute_fall_back_destinations(fc, "FC", snap2, AIDM._get_enemy_units(snap2, 1), AIDM._get_objectives(snap2), 1)
	var probe = AIDM._stay_engaged_probe(fc, dests)
	var gap: float = AIDM._get_closest_model_distance_inches(probe, snap2.units.EN)
	var p: float = AIDM._charge_success_probability(AIDM._charge_roll_needed(gap))
	var out := float(ctx.get("out_dmg", 0.0))
	var inn := float(ctx.get("in_dmg", 0.0))
	var net := minf(out, 20.0) * 10.75 + (0.25 * 215.0 if out >= 20.0 else 0.0) - minf(inn * maxf(0.0, 1.0 - out / 20.0), 20.0) * 10.75
	var expect := p * maxf(0.0, net)
	print("  charge gap %.2f\", p %.3f, expected %.3f, got %.3f" % [gap, p, expect, _term(rec, "fall_back", "leave_fb_charge")])
	_assert(p > 0.0 and _near(_term(rec, "fall_back", "leave_fb_charge"), expect, 0.05),
		"Fall Back and Charge: P(2D6 >= the gap the fall back leaves) x the fight as the charger (got %.3f, expected %.3f)" % [
			_term(rec, "fall_back", "leave_fb_charge"), expect])

func test_leave_objective_when_control_changes() -> void:
	print("\n--- (a) the fall back takes an objective (14.02) ---")
	_reset()
	_set_fix(1.0)
	var objs := [{"id": "obj_land", "position": Vector2(730, 920)}]
	var snap = _snapshot(2, objs)
	_add(snap, "OB", 1, _line(600, 65, 1200, 5), [CCW_WEAK], 4, 3, 2, 100, ["INFANTRY"], 40)
	_add(snap, "EB", 2, _line(665, 65, 1280, 3), [CLUB], 4, 3, 2, 60, ["INFANTRY"], 40)
	var d = _engaged(snap, "OB")
	_assert(_near(_term(_choice(), "fall_back", "leave_objective"), 25.0),
		"uncontrolled objective in the fall-back landing: leave_objective 25 (got %.3f)" % _term(_choice(), "fall_back", "leave_objective"))
	_assert(_notes(d).contains("obj_land") or str(d.get("type", "")) == "REMAIN_STATIONARY", "the note names the objective when it falls back (%s)" % _notes(d))
	var snap2 = _snapshot(2, objs)
	_add(snap2, "OB", 1, _line(600, 65, 1200, 5), [CCW_WEAK], 4, 3, 2, 100, ["INFANTRY"], 40)
	_add(snap2, "EB", 2, _line(665, 65, 1280, 3), [CLUB], 4, 3, 2, 60, ["INFANTRY"], 40)
	_add(snap2, "HOLD", 1, _line(600, 65, 860, 5), [CCW_WEAK], 4, 3, 2, 100, ["INFANTRY"], 40, {}, {"objective_control": 3})
	_engaged(snap2, "OB")
	_assert(not _has_term(_choice(), "fall_back", "leave_objective"), "already ours with more OC: no leave_objective")

func test_on_objective_control_change_skips() -> void:
	print("\n--- (c) guard: sole holder with Fall Back and Charge — leaving changes control ---")
	for v in [0.0, 1.0]:
		_reset()
		_set_fix(v)
		var snap = _snapshot(2, [{"id": "obj_o", "position": Vector2(700, 1200)}])
		_add(snap, "OURS", 1, [Vector2(675, 1200), Vector2(725, 1200)], [CCW_WEAK], 4, 3, 2, 50, ["INFANTRY"], 32,
			{"effect_fall_back_and_charge": true})
		_add(snap, "ENE", 2, [Vector2(700, 1280)], [CLUB], 4, 3, 2, 30, ["INFANTRY"], 32)
		var d = _engaged(snap, "OURS")
		_assert(_choice().is_empty(), "flag=%.0f: no engaged_choice record" % v)
		_assert(str(d.get("type", "")) == "BEGIN_FALL_BACK" and str(d.get("_ai_description", "")) == "OURS falls back (losing OC war, can charge back (Fall Back and Charge))",
			"flag=%.0f: the old Fall Back and Charge decision (%s)" % [v, str(d.get("_ai_description", ""))])
	_set_fix(1.0)

func test_on_objective_losing_runs() -> void:
	print("\n--- (a) on an objective, losing the OC war, leaving changes nothing: priced ---")
	_reset()
	_set_fix(1.0)
	var snap = _snapshot(2, [{"id": "obj_o", "position": Vector2(700, 1200)}])
	_add(snap, "OURS", 1, [Vector2(675, 1200), Vector2(725, 1200)], [CCW_WEAK], 4, 3, 2, 50, ["INFANTRY"], 32)
	_add(snap, "PAL", 1, [Vector2(700, 1130)], [CCW_WEAK], 4, 3, 2, 30, ["INFANTRY"], 32)
	_add(snap, "ENE", 2, _line(596, 52, 1280, 5), [CLUB], 4, 3, 2, 80, ["INFANTRY"], 32)
	_engaged(snap, "OURS")
	_assert(not _choice().is_empty(), "OC 6 vs 10 either way: an engaged_choice record is emitted (%s)" % _chosen_key(_choice()))

# --- (c) guards ------------------------------------------------------------------

func test_guard_no_fall_back_path_unchanged() -> void:
	print("\n--- (c) guard: no fall-back path (M1\" cannot leave engagement range) ---")
	for v in [0.0, 1.0]:
		_reset()
		_set_fix(v)
		var snap = _snapshot()
		_add(snap, "CG", 1, _line(600, 65, 1200, 5), [SPEAR], 6, 2, 4, 215, ["INFANTRY"], 40, {}, {"invuln": 4, "move": 1})
		_add_pz(snap, "PZ", 2, 1280)
		var d = _engaged(snap, "CG")
		_assert(str(d.get("_ai_description", "")) == "CG remains stationary (no valid fall-back path)",
			"flag=%.0f: remains stationary, no valid fall-back path (%s)" % [v, str(d.get("_ai_description", ""))])
		_assert(_choice().is_empty(), "flag=%.0f: no engaged_choice record" % v)
	_set_fix(1.0)

func test_guard_edition_10_unchanged() -> void:
	print("\n--- (c) guard: 10th edition — the flag does nothing ---")
	GameConstants.edition = 10
	var got: Array = []
	for v in [0.0, 1.0]:
		_reset()
		_set_fix(v)
		var snap = _snapshot()
		_add_cg(snap, "CG", 1, 1200)
		_add_pz(snap, "PZ", 2, 1280)
		var d = _engaged(snap, "CG")
		got.append(str(d))
		_assert(_choice().is_empty(), "10e, flag=%.0f: no engaged_choice record" % v)
	GameConstants.edition = 11
	_assert(got[0] == got[1] and got[0].contains("BEGIN_FALL_BACK"), "10e: the same fall back with the flag on and off")
	_set_fix(1.0)

func test_guard_only_remain_stationary_offered() -> void:
	print("\n--- (c) guard: only REMAIN_STATIONARY offered ---")
	_reset()
	_set_fix(1.0)
	var snap = _snapshot()
	_add_cg(snap, "CG", 1, 1200)
	_add_pz(snap, "PZ", 2, 1280)
	var d = _engaged(snap, "CG", ["REMAIN_STATIONARY"])
	_assert(str(d.get("_ai_description", "")) == "CG remains stationary (engaged, no fall back option)",
		"the old stationary decision (%s)" % str(d.get("_ai_description", "")))
	_assert(_choice().is_empty(), "no engaged_choice record")

func test_guard_not_engaged_unchanged() -> void:
	print("\n--- (c) guard: offered a fall back but no enemy within engagement range by the AI's measure ---")
	for v in [0.0, 1.0]:
		_reset()
		_set_fix(v)
		var snap = _snapshot()
		_add_cg(snap, "CG", 1, 1200)
		_add_pz(snap, "PZ", 2, 1400)  # 4.4" away
		var d = _engaged(snap, "CG")
		_assert(_choice().is_empty() and str(d.get("_ai_description", "")) == "CG falls back (not on objective)",
			"flag=%.0f: the old fall back, no record (%s)" % [v, str(d.get("_ai_description", ""))])
	_set_fix(1.0)

# --- review fixes ----------------------------------------------------------------

func _cg_at(snap: Dictionary, uid: String, owner: int, x0: float, y: float, flags: Dictionary = {}) -> Dictionary:
	return _add(snap, uid, owner, _line(x0, 65, y, 5), [SPEAR], 6, 2, 4, 215, ["INFANTRY"], 40, flags, {"invuln": 4})

## 12.04: Resolve Remaining Combats starts with the player who did NOT make the
## last Fights First pick. Our second Guard squad B (unengaged) plans to charge
## enemy Guard Y; a successful charge gives it Fights First (11.04), so we make
## the only Fights First pick and the ENEMY starts Resolve Remaining Combats —
## its Guard clone CG2 can strike our stayer first. No strike-first discount.
func test_strike_first_friendly_charger_hands_over() -> void:
	print("\n--- (a) 12.04: a friendly charger hands the first Remaining Combats pick to the enemy ---")
	_reset()
	_set_fix(1.0)
	var snap = _snapshot()
	_add_cg(snap, "CG", 1, 1200)
	_add_cg(snap, "CG2", 2, 1280)
	_cg_at(snap, "B", 1, 200, 300)
	_cg_at(snap, "Y", 2, 200, 660)
	AIDM._phase_plan[1] = {"charge_intent": {"B": {"target_id": "Y", "target_name": "Y", "score": 20.0, "distance_inches": 9.0}},
		"lock_targets": [], "shooting_lanes": {}, "charge_target_ids": ["Y"]}
	var d = _engaged(snap, "CG")
	var ctx: Dictionary = _choice().get("context", {})
	_assert(_near(float(ctx.get("p_strike_first", -1.0)), 0.0, 0.001),
		"B's planned charge (7.4\" edge gap, M6: certain) would give us the only Fights First pick: p(strike first) 0 (got %s)" % str(ctx.get("p_strike_first", "")))
	_assert(_near(float(ctx.get("in_dmg_after_first_strike", 0.0)), 13.89, 0.02),
		"no strike-first discount: the clone's full 13.89 strike-back (got %s)" % str(ctx.get("in_dmg_after_first_strike", "")))
	_assert(not bool(ctx.get("we_strike_first", true)), "context: we do not strike first")
	_assert(str(d.get("type", "")) == "BEGIN_FALL_BACK",
		"without the discount the Guard-vs-clone fight is not worth staying for: falls back (%s)" % str(d.get("_ai_description", "")))
	var fst: Dictionary = AIDM._stay_engaged_first_strike("CG", ["CG"], "CG2", snap, 1)
	var note: String = AIDM._stay_engaged_first_strike_note(fst, "CG2", 13.89, 13.89)
	_assert(note.begins_with("Strikes second") and note.contains("planned charge") and note.contains("12.04"),
		"the K note says it strikes second because of the planned charge (%s)" % note)
	# The engine agrees once B's charge has gone in (ChargePhase sets both flags).
	var k := 0
	for m in snap.units.B.models:
		m.position = Vector2(200.0 + 65.0 * float(k), 580.0)
		k += 1
	snap.units.B.flags["charged_this_turn"] = true
	snap.units.B.flags["fights_first"] = true
	AIDM._phase_plan.erase(1)
	var fs = load("res://scripts/rules/FightSequencer.gd").new()
	fs.begin(snap, 1)
	var s1: Dictionary = fs.next_selection(snap)
	fs.select_to_fight(str(s1.candidates[0]), snap)
	var s2: Dictionary = fs.next_selection(snap)
	print("  engine: pick 1 P%d %s %s, pick 2 P%d %s %s" % [int(s1.player), str(s1.step), str(s1.candidates), int(s2.player), str(s2.step), str(s2.candidates)])
	_assert(int(s1.player) == 1 and str(s1.step) == "fights_first" and int(s2.player) == 2 and str(s2.step) == "remaining" and (s2.candidates as Array).has("CG2"),
		"engine (FightSequencer): B's Fights First pick, then the ENEMY starts Resolve Remaining Combats and may pick CG2")
	_engaged(snap, "CG")
	var ctx2: Dictionary = _choice().get("context", {})
	_assert(_near(float(ctx2.get("p_strike_first", -1.0)), 0.0, 0.001) and int(ctx2.get("fights_first_ours", 0)) == 1 and int(ctx2.get("fights_first_theirs", -1)) == 0,
		"after the charge the ledger agrees: our 1 Fights First unit vs their 0 (p %s, ours %s, theirs %s)" % [
			str(ctx2.get("p_strike_first", "")), str(ctx2.get("fights_first_ours", "")), str(ctx2.get("fights_first_theirs", ""))])
	# An enemy Fights First unit engaged elsewhere balances it: one each, so we
	# start Resolve Remaining Combats again. F's combat is not contested there —
	# its enemy FF fights in the Fights First step.
	_cg_at(snap, "F", 1, 1300, 2000)
	_cg_at(snap, "FF", 2, 1300, 2080, {"fights_first": true})
	_engaged(snap, "CG")
	var ctx3: Dictionary = _choice().get("context", {})
	_assert(int(ctx3.get("fights_first_theirs", 0)) == 1 and int(ctx3.get("contested_combats", 0)) == 1 and _near(float(ctx3.get("p_strike_first", -1.0)), 1.0, 0.001),
		"one Fights First unit each: we start Resolve Remaining Combats again: p 1 (got %s, theirs %s, combats %s)" % [
			str(ctx3.get("p_strike_first", "")), str(ctx3.get("fights_first_theirs", "")), str(ctx3.get("contested_combats", ""))])
	var fs3 = load("res://scripts/rules/FightSequencer.gd").new()
	fs3.begin(snap, 1)
	var seq: Array = []
	for i in range(3):
		var sx: Dictionary = fs3.next_selection(snap)
		seq.append("P%d %s" % [int(sx.player), str(sx.step)])
		fs3.select_to_fight("B" if i == 0 else ("FF" if i == 1 else "CG"), snap)
	_assert(seq == ["P1 fights_first", "P2 fights_first", "P1 remaining"],
		"engine: B, then FF in the Fights First step, then WE start Resolve Remaining Combats (%s)" % str(seq))
	# Control: no charger at all — we start Resolve Remaining Combats, the full discount.
	_reset()
	var snap0 = _snapshot()
	_add_cg(snap0, "CG", 1, 1200)
	_add_cg(snap0, "CG2", 2, 1280)
	var fs0 = load("res://scripts/rules/FightSequencer.gd").new()
	fs0.begin(snap0, 1)
	var s0: Dictionary = fs0.next_selection(snap0)
	_engaged(snap0, "CG")
	var ctx0: Dictionary = _choice().get("context", {})
	_assert(int(s0.player) == 1 and str(s0.step) == "remaining" and _near(float(ctx0.get("p_strike_first", 0.0)), 1.0, 0.001)
		and _near(float(ctx0.get("in_dmg_after_first_strike", 0.0)), 4.24, 0.02),
		"control, no charger: the engine and the ledger both have us start Resolve Remaining Combats (p %s, back %s)" % [
			str(ctx0.get("p_strike_first", "")), str(ctx0.get("in_dmg_after_first_strike", ""))])
	# A planned charge that cannot make it (28" away) changes nothing.
	_cg_at(snap0, "B", 1, 1300, 300)
	_cg_at(snap0, "Y", 2, 1300, 1500)
	AIDM._phase_plan[1] = {"charge_intent": {"B": {"target_id": "Y", "target_name": "Y", "score": 20.0, "distance_inches": 30.0}},
		"lock_targets": [], "shooting_lanes": {}, "charge_target_ids": ["Y"]}
	_engaged(snap0, "CG")
	_assert(_near(float(_choice().get("context", {}).get("p_strike_first", 0.0)), 1.0, 0.001),
		"a planned charge with no chance (28\" gap) does not hand the pick over (p %s)" % str(_choice().get("context", {}).get("p_strike_first", "")))
	AIDM._phase_plan.erase(1)

## 12.04 alternation: with two of our units in separate combats and nobody
## with Fights First, we pick first — the stayer — then the enemy picks the
## OTHER combat's unit and strikes first there. Each stayer gets the discount
## for ceil(S/2) of S combats.
func test_strike_first_contested_combats() -> void:
	print("\n--- (a) 12.04: separate combats share the first picks ---")
	_reset()
	_set_fix(1.0)
	var snap = _snapshot()
	_add_cg(snap, "CG", 1, 1200)
	_add_cg(snap, "CG2", 2, 1280)
	_add_cg(snap, "CG3", 1, 2000)
	_add_cg(snap, "CG4", 2, 2080)
	_engaged(snap, "CG")
	var ctx: Dictionary = _choice().get("context", {})
	var expect := 13.89 * (1.0 - (13.89 / 20.0) * 0.5)
	_assert(int(ctx.get("contested_combats", 0)) == 2 and _near(float(ctx.get("p_strike_first", 0.0)), 0.5, 0.001),
		"two combats, we start: strikes first in 1 of 2 (p %s, combats %s)" % [str(ctx.get("p_strike_first", "")), str(ctx.get("contested_combats", ""))])
	_assert(_near(float(ctx.get("in_dmg_after_first_strike", 0.0)), expect, 0.03),
		"strike-back = 13.89 x (1 - 0.69 x 0.5) = %.2f (got %s)" % [expect, str(ctx.get("in_dmg_after_first_strike", ""))])
	var fs = load("res://scripts/rules/FightSequencer.gd").new()
	fs.begin(snap, 1)
	var s1: Dictionary = fs.next_selection(snap)
	fs.select_to_fight("CG", snap)
	var s2: Dictionary = fs.next_selection(snap)
	_assert(int(s1.player) == 1 and str(s1.step) == "remaining" and int(s2.player) == 2 and (s2.candidates as Array).has("CG4"),
		"engine: we pick one combat, then the enemy picks and may strike first in the other (P%d %s)" % [int(s2.player), str(s2.candidates)])
	_add_cg(snap, "CG5", 1, 300)
	_add_cg(snap, "CG6", 2, 380)
	_engaged(snap, "CG")
	_assert(_near(float(_choice().get("context", {}).get("p_strike_first", 0.0)), 2.0 / 3.0, 0.001),
		"three combats: ceil(3/2) / 3 = 0.667 (got %s)" % str(_choice().get("context", {}).get("p_strike_first", "")))

## 04.02: while LK stays, the enemy it is engaged with cannot be shot by the
## rest of our army; falling back makes it a target for our lascannons, which
## have nothing else to shoot.
func test_free_target_for_our_guns() -> void:
	print("\n--- (a) 04.02: falling back frees the engaged enemy for our other guns ---")
	_reset()
	_set_fix(1.0)
	var plan := {"lock_targets": ["E"], "charge_intent": {}, "shooting_lanes": {}, "charge_target_ids": []}
	AIDM._phase_plan[1] = plan
	var snap = _lock_board()
	_add(snap, "GUNS", 1, _line(600, 65, 480, 5), [LASCANNON], 4, 3, 2, 200, ["INFANTRY"], 40)
	var d = _engaged(snap, "LK")
	var rec = _choice()
	var gap: float = AIDM._get_closest_model_distance_inches(snap.units.GUNS, snap.units.E)
	var dmg: float = AIDM._stay_engaged_ranged_damage(snap.units.GUNS, snap.units.E, 0, false, false, false, gap)
	var expect := minf(dmg, 9.0) * 150.0 / 9.0
	print("  free target %.3f, expected %.3f (lascannons %.2f of E's 9 wounds)" % [_term(rec, "fall_back", "leave_free_target"), expect, dmg])
	_assert(dmg > 0.0 and _near(_term(rec, "fall_back", "leave_free_target"), expect, 0.05),
		"leave_free_target = min(lascannon damage, 9 W) x 16.7 pts/W = %.1f (got %.3f)" % [expect, _term(rec, "fall_back", "leave_free_target")])
	_assert(str(d.get("type", "")) == "BEGIN_FALL_BACK", "freeing E for the lascannons beats staying locked: falls back (%s)" % str(d.get("_ai_description", "")))
	_assert(_notes(d).contains("Frees E for our guns") and _notes(d).contains("04.02"), "move note: frees E for our guns (%s)" % _notes(d))
	var re = root.get_node("RulesEngine")
	var stay_t: Dictionary = re.get_eligible_targets("GUNS", snap)
	var fb_board: Dictionary = snap.duplicate(true)
	var dests: Dictionary = d.get("_ai_model_destinations", {})
	for m in fb_board.units.LK.models:
		var dd = dests.get(m.id, null)
		if dd is Array:
			m.position = Vector2(float(dd[0]), float(dd[1]))
	var fb_t: Dictionary = re.get_eligible_targets("GUNS", fb_board)
	_assert(stay_t.is_empty() and fb_t.has("E"),
		"engine (04.02): GUNS can target nothing while LK stays, E once LK stands at the fall-back destinations (%s -> %s)" % [str(stay_t.keys()), str(fb_t.keys())])
	_set_param("STAY_ENGAGED_FREE_TARGET_WEIGHT", 0.0)
	var d0 = _engaged(snap, "LK")
	_assert(not _has_term(_choice(), "fall_back", "leave_free_target") and str(d0.get("type", "")) == "REMAIN_STATIONARY",
		"STAY_ENGAGED_FREE_TARGET_WEIGHT 0: no term, and it stays (%s)" % str(d0.get("type", "")))
	AIDM._config_overrides.erase("STAY_ENGAGED_FREE_TARGET_WEIGHT")
	var veh = _lock_board(["VEHICLE"])
	_add(veh, "GUNS", 1, _line(600, 65, 480, 5), [LASCANNON], 4, 3, 2, 200, ["INFANTRY"], 40)
	_engaged(veh, "LK")
	_assert(not _has_term(_choice(), "fall_back", "leave_free_target"), "a VEHICLE can be shot while engaged (17.03): nothing to free")
	var held = _lock_board()
	_add(held, "GUNS", 1, _line(600, 65, 480, 5), [LASCANNON], 4, 3, 2, 200, ["INFANTRY"], 40)
	_add(held, "LK2", 1, _line(665, 65, 1360, 3), [CCW_WEAK], 4, 3, 2, 60, ["INFANTRY"], 40)
	_engaged(held, "LK")
	_assert(not _has_term(_choice(), "fall_back", "leave_free_target"), "another of our units keeps E engaged: still no target")
	var alt = _lock_board()
	_add(alt, "GUNS", 1, _line(600, 65, 480, 5), [LASCANNON], 4, 3, 2, 200, ["INFANTRY"], 40)
	_add(alt, "ALT", 2, _line(1300, 65, 600, 3), [SHANK], 5, 3, 3, 150, ["INFANTRY"], 40)
	_engaged(alt, "LK")
	_assert(not _has_term(_choice(), "fall_back", "leave_free_target"), "an equal target already in the lascannons' reach: freeing E gains nothing")
	var weak = _lock_board()
	_add(weak, "GUNS", 1, _line(600, 65, 480, 5), [BOLTGUN], 4, 3, 2, 100, ["INFANTRY"], 40)
	var dw = _engaged(weak, "LK")
	var fw := _term(_choice(), "fall_back", "leave_free_target")
	_assert(fw > 0.0 and str(dw.get("type", "")) == "REMAIN_STATIONARY" and _notes(dw).contains("Falling back is worth only")
		and not _notes(dw).contains("gains nothing"),
		"boltguns: a small gain (%.1f), it still stays and the note says what leaving was worth, not 'gains nothing' (%s)" % [fw, _notes(dw)])
	AIDM._phase_plan.erase(1)

## The ranged estimate uses the shared weapon-keyword rules: [TORRENT] has no
## hit roll (24.37), so no -1 to hit either; [MELTA] counts within half range.
func test_ranged_damage_weapon_keywords() -> void:
	print("\n--- (a) ranged estimate: [TORRENT] auto-hits, [MELTA] at half range ---")
	var snap = _snapshot()
	var sh = _add(snap, "BURNAS", 2, [Vector2(700, 1200)], [BURNA], 5, 4, 1, 50, ["INFANTRY"], 32)
	var tgt = _add(snap, "GROTS", 1, [Vector2(700, 1260)], [SHANK], 3, 7, 1, 40, ["INFANTRY"], 25)
	var d0: float = AIDM._stay_engaged_ranged_damage(sh, tgt, 0)
	var d1: float = AIDM._stay_engaged_ranged_damage(sh, tgt, 1, true, false, true)
	_assert(_near(d0, 3.5 * 4.0 / 6.0, 0.005) and _near(d1, d0, 0.0001),
		"[TORRENT] Burna (BS N/A) vs T3 Sv7: 3.5 x 4/6 = 2.33 with or without the -1 to hit (got %.3f / %.3f)" % [d0, d1])
	var veh = _add(snap, "VEH", 1, [Vector2(700, 1500)], [], 9, 3, 10, 150, ["VEHICLE"], 60)
	var full: float = AIDM._stay_engaged_ranged_damage(sh, veh, 0)
	var partial: float = AIDM._stay_engaged_ranged_damage(sh, veh, 1, false, false, true)
	_assert(full > 0.0 and _near(full, partial, 0.0001),
		"stay_shield for an engaged VEHICLE: the -1 to hit (17.03) saves nothing against [TORRENT] (full %.3f, partial %.3f)" % [full, partial])
	var mm = _add(snap, "MM", 1, [Vector2(300, 300)], [MULTI_MELTA], 10, 3, 12, 150, ["VEHICLE"], 60)
	var tank = _add(snap, "TANK", 2, [Vector2(300, 400)], [], 10, 3, 12, 150, ["VEHICLE"], 60)
	var near_d: float = AIDM._stay_engaged_ranged_damage(mm, tank, 0, false, false, false, 0.5)
	var far_d: float = AIDM._stay_engaged_ranged_damage(mm, tank, 0, false, false, false, 15.0)
	_assert(far_d > 0.0 and _near(near_d / far_d, 5.5 / 3.5, 0.001),
		"[MELTA 2]: D6+2 within half range (an engaged target always is) vs D6 at 15\" (ratio %.4f, expected %.4f)" % [near_d / maxf(far_d, 0.0001), 5.5 / 3.5])

## 09.07 / 19.01: the ledger prices as many hazard rolls as the engine makes
## for an Attached unit's Desperate Escape — the bodyguard's today, the whole
## Attached unit once the engine rolls for it (EA-36).
func test_desperate_escape_rolls_match_engine() -> void:
	print("\n--- (a) Desperate Escape: the ledger counts the engine's hazard rolls (09.07; 19.01) ---")
	_reset()
	_set_fix(1.0)
	var snap = _snapshot()
	var gr = _add(snap, "GR", 1, _line(630, 50, 1200, 5), [CCW_WEAK], 4, 4, 1, 75, ["INFANTRY"], 32, {"battle_shocked": true})
	var cap = _add(snap, "CAP", 1, [Vector2(730, 1140)], [CCW_WEAK], 4, 3, 4, 60, ["INFANTRY", "CHARACTER"], 40, {"battle_shocked": true})
	gr["attachment_data"] = {"attached_characters": ["CAP"]}
	cap["attached_to"] = "GR"
	_add(snap, "BR", 2, _line(630, 50, 1280, 4), [CLUB], 4, 4, 2, 80, ["INFANTRY"], 32)
	var enemies = AIDM._get_enemy_units(snap, 1)
	var dests: Dictionary = AIDM._compute_fall_back_destinations(gr, "GR", snap, enemies, AIDM._get_objectives(snap), 1)
	var m: Dictionary = AIDM._stay_engaged_fall_back_mode(gr, "GR", snap, dests, enemies, ["GR", "CAP"])
	var fbm = load("res://scripts/rules/movetypes/MoveTypes.gd").get_type("fall_back")
	var eng: Dictionary = fbm.before_moving("GR", snap, load("res://autoloads/RulesEngine.gd").RNGService.new(7), {"mode": "desperate_escape"})
	var eng_rolls: int = (eng.get("hazard", {}).get("rolls", []) as Array).size()
	var whole: bool = fbm.has_method("attached_unit_hazard_view")
	print("  ledger %d hazard roll(s), engine %d (the engine rolls for the whole Attached unit: %s)" % [int(m.rolls), eng_rolls, str(whole)])
	_assert(bool(m.de) and eng_rolls > 0 and int(m.rolls) == eng_rolls,
		"the ledger prices exactly the engine's hazard rolls (%d vs %d)" % [int(m.rolls), eng_rolls])
	_assert(int(m.rolls) == (6 if whole else 5) and bool(m.whole_unit) == whole,
		"5 bodyguard rolls today; 6 with the leader once the engine rolls for the whole Attached unit (EA-36 in the build: %s)" % str(whole))

## Our 32 mm model 1.5 px from an enemy base (a 32 mm round, or the LONG side of
## a 75 x 42 mm oval), the enemy due south.
func _cross_board(enemy_oval: bool, our_kw: Array = ["INFANTRY"]) -> Dictionary:
	var snap = _snapshot()
	_add(snap, "OURS", 1, [Vector2(700, 1200)], [CCW_WEAK], 4, 4, 1, 15, our_kw, 32)
	var half_mm := 21.0 if enemy_oval else 16.0
	var e = _add(snap, "EN", 2, [Vector2(700, 1200.0 + (16.0 + half_mm) * MM_PX + 1.5)], [CLUB], 5, 4, 3, 30,
		["MOUNTED"] if enemy_oval else ["INFANTRY"], 75 if enemy_oval else 32)
	if enemy_oval:
		e.models[0]["base_type"] = "oval"
		e.models[0]["base_dimensions"] = {"length": 75.0, "width": 42.0}
		e.models[0]["rotation"] = 0.0
	return snap

## 03.01: the crossing test sweeps the real bases (EA-08's sweep): base
## contact is not moving through, FLY may take to the skies, and a carried
## CHARACTER's path counts.
func test_crossing_predicate_shape_aware() -> void:
	print("\n--- (a) 03.01: the crossing test sweeps the real bases ---")
	var meas = root.get_node("Measurement")
	var mt = load("res://scripts/rules/movetypes/MoveType.gd")
	for oval in [false, true]:
		var snap = _cross_board(oval)
		var ours: Dictionary = snap.units.OURS
		var en: Dictionary = snap.units.EN
		var enemies = AIDM._get_enemy_units(snap, 1)
		var gap_px: float = float(meas.model_to_model_distance_inches(ours.models[0], en.models[0])) * 40.0
		var away := {"m1": [700.0, 960.0]}
		var crossed: bool = AIDM._stay_engaged_path_crosses(ours, "OURS", ["OURS"], away, enemies, snap)
		var label := "oval long side" if oval else "32 mm round"
		_assert(gap_px >= 0.0 and gap_px < 3.0 and not crossed,
			"%s in contact (gap %.1f px): backing straight away does not cross it" % [label, gap_px])
		var through := {"m1": [700.0, 1200.0 + 2.0 * (16.0 + (21.0 if oval else 16.0)) * MM_PX + 80.0]}
		var crossed2: bool = AIDM._stay_engaged_path_crosses(ours, "OURS", ["OURS"], through, enemies, snap)
		_assert(crossed2, "%s: a path straight through it crosses it" % label)
		if mt.has_method("path_crosses_enemy_models"):
			var e_away: bool = mt.path_crosses_enemy_models(snap, 1, ours.models[0], Vector2(700, 1200), Vector2(700, 960), {})
			var e_through: bool = mt.path_crosses_enemy_models(snap, 1, ours.models[0], Vector2(700, 1200),
				Vector2(float(through.m1[0]), float(through.m1[1])), {})
			_assert(e_away == crossed and e_through == crossed2, "%s: the engine's own sweep agrees (EA-08)" % label)
	var sv = _snapshot()
	var vh = _add(sv, "VH", 1, [Vector2(730, 1200)], [CLAW], 9, 3, 12, 180, ["VEHICLE"], 120)
	vh.models[0]["base_type"] = "oval"
	vh.models[0]["base_dimensions"] = {"length": 120.0, "width": 92.0}
	vh.models[0]["rotation"] = 0.0
	_add(sv, "EN", 2, [Vector2(730, 1200.0 + (46.0 + 16.0) * MM_PX + 0.5)], [CLUB], 4, 3, 2, 120, ["INFANTRY"], 32)
	_assert(not AIDM._stay_engaged_path_crosses(vh, "VH", ["VH"], {"m1": [730.0, 880.0]}, AIDM._get_enemy_units(sv, 1), sv),
		"our 120 x 92 oval VEHICLE in long-side contact, backing 8\" straight away: no crossing")
	var sf = _cross_board(false, ["INFANTRY", "FLY"])
	_assert(not AIDM._stay_engaged_path_crosses(sf.units.OURS, "OURS", ["OURS"], {"m1": [700.0, 1200.0 + 64.0 * MM_PX + 80.0]},
		AIDM._get_enemy_units(sf, 1), sf), "FLY: a path through enemy models is no crossing (it may take to the skies, 21.03)")
	var sc = _snapshot()
	var bg = _add(sc, "BG", 1, [Vector2(400, 1200)], [CCW_WEAK], 4, 4, 1, 15, ["INFANTRY"], 32)
	var ch = _add(sc, "CH", 1, [Vector2(700, 1200)], [CCW_WEAK], 4, 3, 4, 60, ["INFANTRY", "CHARACTER"], 40)
	bg["attachment_data"] = {"attached_characters": ["CH"]}
	ch["attached_to"] = "BG"
	_add(sc, "EN", 2, [Vector2(700, 1120)], [CLUB], 4, 3, 2, 30, ["INFANTRY"], 32)
	var en_c = AIDM._get_enemy_units(sc, 1)
	_assert(AIDM._stay_engaged_path_crosses(bg, "BG", ["BG", "CH"], {"m1": [400.0, 960.0]}, en_c, sc)
		and not AIDM._stay_engaged_path_crosses(bg, "BG", ["BG"], {"m1": [400.0, 960.0]}, en_c, sc),
		"the attached CHARACTER rides the bodyguard's delta: its path through an enemy model counts")

## 09.07 today: AIPlayer's BEGIN_FALL_BACK is an Ordered Retreat, and the
## engine lets an Ordered Retreat move through enemy models until EA-08 lands —
## so a crossing costs nothing and the record says Ordered Retreat. Once the
## engine refuses it, the same path is priced as a Desperate Escape.
func test_crossing_costs_nothing_until_engine_refuses() -> void:
	print("\n--- (a) 09.07: a way out through enemy models is a Desperate Escape only where the engine forbids an Ordered Retreat through them ---")
	_reset()
	_set_fix(1.0)
	var snap = _cross_board(false)
	var enemies = AIDM._get_enemy_units(snap, 1)
	var through := {"m1": [700.0, 1200.0 + 64.0 * MM_PX + 80.0]}
	var m: Dictionary = AIDM._stay_engaged_fall_back_mode(snap.units.OURS, "OURS", snap, through, enemies, ["OURS"])
	var rule: bool = load("res://scripts/rules/movetypes/MoveTypes.gd").get_type("fall_back").has_method("path_crosses_enemy_models")
	print("  engine refuses an Ordered Retreat through enemy models: %s; mode %s, de %s, rolls %d" % [str(rule), str(m.mode), str(m.de), int(m.rolls)])
	_assert(bool(m.crossing_rule) == rule and bool(m.de) == rule and bool(m.crosses) == rule
		and str(m.mode) == ("desperate_escape" if rule else "ordered_retreat") and int(m.rolls) == (1 if rule else 0),
		"a path through an enemy model: a Desperate Escape exactly when the engine refuses the Ordered Retreat (EA-08 in the build: %s)" % str(rule))
	# The reviewer's flip: the same mildly losing fight, the enemy on 32 mm
	# rounds or in contact with the long side of 75 x 42 mm ovals — the base
	# shape must not change the decision.
	var got: Array = []
	for oval in [false, true]:
		_reset()
		_set_fix(1.0)
		var s = _snapshot()
		_add(s, "GR", 1, _line(600, 65, 1200, 5), [CCW_WEAK], 4, 4, 1, 75, ["INFANTRY"], 32)
		var half := (21.0 if oval else 16.0) * MM_PX
		var xs := [600.0, 730.0, 860.0, 990.0]
		var br = _add(s, "BR", 2, [], [CLUB], 4, 4, 2, 80, ["MOUNTED"] if oval else ["INFANTRY"], 75 if oval else 32)
		var bm: Array = []
		for k in range(4):
			var mdl := {"id": "m%d" % (k + 1), "alive": true, "position": Vector2(xs[k] if oval else 600.0 + 65.0 * float(k), 1200.0 + 16.0 * MM_PX + half + 1.5),
				"wounds": 2, "current_wounds": 2, "rotation": 0.0, "base_mm": 75 if oval else 32,
				"base_type": "oval" if oval else "circular", "base_dimensions": {"length": 75.0, "width": 42.0} if oval else {}}
			bm.append(mdl)
		br["models"] = bm
		var d = _engaged(s, "GR")
		var rec = _choice()
		got.append(str(d.get("type", "")))
		_assert(not _has_term(rec, "fall_back", "leave_hazard") and str(_cand(rec, "fall_back").get("description", "")) == "Fall back (Ordered Retreat)",
			"%s: no phantom Desperate Escape — no hazard term, the record says Ordered Retreat (%s)" % ["75 x 42 ovals" if oval else "32 mm rounds", str(_cand(rec, "fall_back").get("description", ""))])
	_assert(got[0] == got[1] and got[0] == "BEGIN_FALL_BACK", "the base shape does not flip the decision: %s / %s" % [str(got[0]), str(got[1])])

## The action line's reason: "out-fights them" only for a fight it wins;
## staying because falling back costs more says so.
func test_reason_when_staying_is_a_loss() -> void:
	print("\n--- (a) the action line names why it stays ---")
	_reset()
	_set_fix(1.0)
	var d = _engaged(_de_board({"battle_shocked": true}), "GR")
	var desc := str(d.get("_ai_description", ""))
	_assert(str(d.get("type", "")) == "REMAIN_STATIONARY" and desc.contains("falling back would cost more: its Desperate Escape makes 5 hazard roll(s)")
		and not desc.contains("out-fights"), "battle-shocked, a mildly losing fight: it stays because leaving costs more (%s)" % desc)
	var d2 = _engaged(_de_board({"effect_cut_em_down": true}), "GR")
	var desc2 := str(d2.get("_ai_description", ""))
	_assert(desc2.contains("5 hazard roll(s) and a battle-shock roll") and not desc2.contains("out-fights"),
		"forced Desperate Escape: names the hazard and battle-shock rolls (%s)" % desc2)
	var snap = _snapshot()
	_add_cg(snap, "CG", 1, 1200)
	_add_pz(snap, "PZ", 2, 1280)
	_assert(str(_engaged(snap, "CG").get("_ai_description", "")).contains("wipes them out in our Fight phase"), "a fight it wins still says so")
	_reset()
	_set_fix(1.0)
	var s4 = _snapshot()
	_add(s4, "PZ", 1, _line(630, 50, 1200, 4), [CCW_WEAK], 3, 3, 1, 45, ["INFANTRY"], 32, {"effect_cut_em_down": true})
	_add(s4, "AL", 2, _line(600, 65, 1280, 5), [SPEAR], 7, 2, 4, 275, ["INFANTRY"], 40, {}, {"invuln": 4})
	AIDM._thinking_steps.clear()
	var d4 = _engaged(s4, "PZ")
	var steps: Array = []
	for st in AIDM._thinking_steps:
		steps.append(str(st))
	var steps_s := " | ".join(PackedStringArray(steps))
	_assert(str(d4.get("type", "")) == "BEGIN_FALL_BACK" and steps_s.contains("PZ falls back via Desperate Escape (forced: CUT 'EM DOWN)")
		and not steps_s.contains("PZ falls back via Ordered Retreat"),
		"a forced Desperate Escape that falls back: the step names it, not Ordered Retreat (%s)" % steps_s)

func test_ledger_sums() -> void:
	print("\n--- ledger: every engaged_choice candidate's score is the sum of its terms ---")
	var n := 0
	var bad := 0
	for r in _all_records:
		if str(r.get("decision_type", "")) != "engaged_choice":
			continue
		for c in r.get("candidates", []):
			n += 1
			var total := 0.0
			for k in c.get("score_breakdown", {}):
				total += float(c.score_breakdown[k])
			if absf(total - float(c.get("score", 0.0))) >= 0.01:
				bad += 1
				print("  mismatch: %s %s score %.3f terms %.3f" % [str(r.get("unit_id", "")), str(c.get("key", "")), float(c.get("score", 0.0)), total])
	_assert(n >= 10 and bad == 0, "%d candidates checked, %d mismatches" % [n, bad])
