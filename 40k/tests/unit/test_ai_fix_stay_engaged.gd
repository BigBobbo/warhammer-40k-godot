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
const PARAMS := ["FIX_STAY_ENGAGED", "STAY_ENGAGED_STRIKE_FIRST", "STAY_ENGAGED_CQ_WEIGHT"]

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
