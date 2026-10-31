extends SceneTree

# FIX-EOG-TIMING (11e rules audit OC-02, protocol V2-4): end-of-battle primary
# awards (when "eog") were priced as if they paid at the next scoring point in
# every battle round.
#
# Root cause — _build_primary_awareness puts every rule whose battle-round
# window holds this round into the round's awareness. An "eog" rule has no
# "rounds" key (PrimaryMissionData11e.gd: Vital Link / Vanguard Operation /
# Inescapable Dominion / Punishment hold_enemy_home, Unstoppable Force
# hold_central, Triangulation hold_min 4), so it defaults to [1, 5] and was
# active in rounds 1-5: enemy_home_bonus / central_bonus / objective_pressure
# and the per-objective VP price (_estimate_objective_vp_value) counted it from
# round 1. The engine pays it once, when the battle ends
# (MissionManager.score_primary_eog_11e; _score_primary_11e skips every rule
# whose "when" differs from the scoring timing). 08.05: a mission aspect is
# resolved only at its own trigger.
#
# With FIX_EOG_TIMING = 1 an "eog" rule is priced only in the last battle round
# (MAX_BATTLE_ROUNDS_AI). Guards: the last round still prices it; a card with
# no "eog" rule is unchanged; the card's other rules keep their price;
# FIX_EOG_TIMING = 0 restores the old awareness exactly.
#
# Run with: godot --headless --path . -s tests/unit/test_ai_fix_eog_timing.gd

const AI_PATH := "res://scripts/AIDecisionMaker.gd"
const PMD = preload("res://scripts/data/PrimaryMissionData11e.gd")
# Source lines of _estimate_objective_vp_value ("ENEMY HOME pays <vp> VP (primary)").
const ENEMY_HOME_SRC := "ENEMY HOME pays"
const CENTRE_SRC := "CENTRE pays"
const HOME_1 := Vector2(700, 470)
const HOME_2 := Vector2(1060, 1930)
const CENTRE := Vector2(880, 1200)

var _pass_count: int = 0
var _fail_count: int = 0
var _ran := false
var AIDM = null
var _mm = null

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

func _run_tests():
	if _ran:
		return
	_ran = true
	await process_frame
	print("\n=== FIX-EOG-TIMING: end-of-battle primary awards are priced only in the last round ===\n")
	_mm = root.get_node_or_null("MissionManager")
	_assert(_mm != null, "MissionManager autoload present")
	if _mm == null:
		print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
		quit(1)
		return
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	var prev_cards: Dictionary = _mm.player_primary_missions.duplicate(true)
	AIDM = load(AI_PATH)

	# P1 Priority Assets vs P2 Purge the Foe: P1 plays Vital Link (eog
	# hold_enemy_home 10 VP), P2 plays Destroyer's Wrath (no eog rule).
	_set_cards("priority_assets", "purge_the_foe")
	test_round2_eog_rule_not_priced()
	test_param_zero_restores_old_price()
	test_last_round_still_prices_eog()
	test_other_rules_of_the_card_unchanged()
	test_card_without_eog_unchanged()
	test_objective_evaluation_drops_enemy_home_vp()
	# P1 Purge the Foe vs P2 Take and Hold: P1 plays Unstoppable Force (eog
	# hold_central 5 VP) — the card the V2-1 gate seeds give P1.
	_set_cards("purge_the_foe", "take_and_hold")
	test_unstoppable_force_centre_round1()

	AIDM._config_overrides.erase("FIX_EOG_TIMING")
	AIDM._primary_awareness_p1 = {}
	AIDM._primary_awareness_p2 = {}
	_mm.player_primary_missions = prev_cards
	GameConstants.edition = prev_edition
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)

# --- fixtures ---------------------------------------------------------------

func _set_cards(p1_disposition: String, p2_disposition: String) -> void:
	_mm.player_primary_missions = {
		"1": PMD.get_card(p1_disposition, p2_disposition),
		"2": PMD.get_card(p2_disposition, p1_disposition),
	}

## Build the player's primary awareness for `battle_round` with the fix at
## `fix`, and install it where the VP estimator reads it.
func _awareness(player: int, battle_round: int, fix: float) -> Dictionary:
	AIDM._config_overrides["FIX_EOG_TIMING"] = fix
	AIDM._secondary_awareness_p1 = {}
	AIDM._secondary_awareness_p2 = {}
	var aw: Dictionary = AIDM._build_primary_awareness(
		{"battle_round": battle_round, "meta": {"battle_round": battle_round}}, player)
	if player == 1:
		AIDM._primary_awareness_p1 = aw
	else:
		AIDM._primary_awareness_p2 = aw
	return aw

func _enemy_home_price(player: int) -> Dictionary:
	# One objective held (home), none held by the enemy.
	return AIDM._estimate_objective_vp_value({"is_home": false, "is_enemy_home": true,
		"is_central": false, "is_held_by_me": false}, player, 1, 0)

func _centre_price(player: int) -> Dictionary:
	return AIDM._estimate_objective_vp_value({"is_home": false, "is_enemy_home": false,
		"is_central": true, "is_held_by_me": false}, player, 1, 0)

func _has_src(sources: Array, prefix: String) -> bool:
	for src in sources:
		if str(src).begins_with(prefix):
			return true
	return false

func _has_eog_rule(aw: Dictionary) -> bool:
	for r in aw.get("vp_rules", []):
		if str(r.get("when", "")) == "eog":
			return true
	return false

func _snapshot(battle_round: int) -> Dictionary:
	var objs = [
		{"id": "obj_home_1", "position": HOME_1, "zone": "player1"},
		{"id": "obj_home_2", "position": HOME_2, "zone": "player2"},
		{"id": "obj_center", "position": CENTRE, "zone": "no_mans_land"},
	]
	var snap = {"battle_round": battle_round, "meta": {"battle_round": battle_round},
		"board": {"objectives": objs, "terrain_features": []}, "units": {}}
	# P1 holds its home; P2 holds its home; the centre is empty.
	_add_unit(snap, "P1_HOLDER", 1, HOME_1)
	_add_unit(snap, "P2_HOLDER", 2, HOME_2)
	return snap

func _add_unit(snap: Dictionary, uid: String, owner: int, pos: Vector2) -> void:
	var models = []
	for i in range(3):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": 32, "base_type": "circular",
			"base_dimensions": {}, "position": pos + Vector2(float(i - 1) * 40.0, 0.0),
			"wounds": 2, "current_wounds": 2})
	snap.units[uid] = {"id": uid, "owner": owner, "status": 2,
		"meta": {"name": uid, "points": 100, "stats": {"move": 6, "toughness": 4, "save": 3,
			"wounds": 2, "leadership": 6, "objective_control": 2}, "keywords": ["INFANTRY"], "weapons": []},
		"models": models, "flags": {}}

func _eval_of(evals: Array, oid: String) -> Dictionary:
	for ev in evals:
		if str(ev.get("id", "")) == oid:
			return ev
	return {}

func _evals(battle_round: int, fix: float) -> Array:
	_awareness(1, battle_round, fix)
	var snap = _snapshot(battle_round)
	var friendly = AIDM._get_units_for_player(snap, 1)
	var enemies = AIDM._get_enemy_units(snap, 1)
	return AIDM._evaluate_all_objectives(snap, AIDM._get_objectives(snap), 1, enemies, friendly, battle_round)

# --- tests --------------------------------------------------------------------

func test_round2_eog_rule_not_priced() -> void:
	print("\n--- Vital Link, round 2, FIX_EOG_TIMING = 1 ---")
	var aw = _awareness(1, 2, 1.0)
	var price = _enemy_home_price(1)
	print("  enemy_home_bonus=%s vp=%s sources=%s" % [aw.get("enemy_home_bonus"), price.vp, str(price.sources)])
	_assert(float(aw.get("enemy_home_bonus", -1.0)) == 0.0,
		"round 2: the eog hold_enemy_home rule adds no enemy-home bonus (got %s, old 15)" % str(aw.get("enemy_home_bonus")))
	_assert(not _has_eog_rule(aw), "round 2: no eog rule in the round's priced rules (vp_rules)")
	_assert(not _has_src(price.sources, ENEMY_HOME_SRC),
		"round 2: the enemy home is not priced with the 10 VP end-of-battle award (sources %s)" % str(price.sources))
	_assert(is_equal_approx(float(price.vp), 4.0),
		"round 2: the enemy home is worth only the hold-1 command VP, 4 (got %s, old 14)" % str(price.vp))

func test_param_zero_restores_old_price() -> void:
	print("\n--- Vital Link, round 2, FIX_EOG_TIMING = 0 (old behaviour) ---")
	var aw = _awareness(1, 2, 0.0)
	var price = _enemy_home_price(1)
	print("  enemy_home_bonus=%s vp=%s sources=%s" % [aw.get("enemy_home_bonus"), price.vp, str(price.sources)])
	_assert(float(aw.get("enemy_home_bonus", -1.0)) == 15.0,
		"off: enemy_home_bonus is 15 (max(4, 1.5 x 10)) as before (got %s)" % str(aw.get("enemy_home_bonus")))
	_assert(_has_src(price.sources, ENEMY_HOME_SRC), "off: the enemy home lists '%s 10 VP' (%s)" % [ENEMY_HOME_SRC, str(price.sources)])
	_assert(is_equal_approx(float(price.vp), 14.0), "off: the enemy home is priced 14 VP (4 + 10) as before (got %s)" % str(price.vp))
	_assert(not aw.has("eog_withheld"), "off: the awareness carries no new key")

func test_last_round_still_prices_eog() -> void:
	print("\n--- Vital Link, round 5 (the battle ends this round), FIX_EOG_TIMING = 1 ---")
	var aw = _awareness(1, 5, 1.0)
	var price = _enemy_home_price(1)
	print("  enemy_home_bonus=%s vp=%s sources=%s" % [aw.get("enemy_home_bonus"), price.vp, str(price.sources)])
	_assert(float(aw.get("enemy_home_bonus", -1.0)) == 15.0,
		"round 5: enemy_home_bonus is 15 (got %s)" % str(aw.get("enemy_home_bonus")))
	_assert(_has_src(price.sources, ENEMY_HOME_SRC) and is_equal_approx(float(price.vp), 14.0),
		"round 5: the enemy home is priced with the 10 VP award (vp %s, sources %s)" % [str(price.vp), str(price.sources)])
	var aw0 = _awareness(1, 5, 0.0)
	_assert(int(aw.get("active_rules", -1)) == int(aw0.get("active_rules", -2))
			and float(aw.get("objective_pressure", -1.0)) == float(aw0.get("objective_pressure", -2.0)),
		"round 5: the same awareness on and off (active_rules %s / %s)" % [str(aw.get("active_rules")), str(aw0.get("active_rules"))])

func test_other_rules_of_the_card_unchanged() -> void:
	print("\n--- Vital Link, round 2: the card's command / end-of-turn rules ---")
	var on = _awareness(1, 2, 1.0)
	var off = _awareness(1, 2, 0.0)
	print("  on: central=%s pressure=%s rules=%s | off: central=%s pressure=%s rules=%s" % [
		on.get("central_bonus"), on.get("objective_pressure"), on.get("active_rules"),
		off.get("central_bonus"), off.get("objective_pressure"), off.get("active_rules")])
	_assert(float(on.get("central_bonus", -1.0)) == 4.0 and float(off.get("central_bonus", -1.0)) == 4.0,
		"the command hold_central (4 VP) rule still gives central_bonus 4 on and off")
	_assert(float(on.get("objective_pressure", -1.0)) == float(off.get("objective_pressure", -2.0)),
		"objective_pressure from the hold-1 and marker rules is the same on and off (%s)" % str(on.get("objective_pressure")))
	_assert(int(on.get("active_rules", -1)) == int(off.get("active_rules", -1)) - 1,
		"only the one eog rule is left out (%s vs %s)" % [str(on.get("active_rules")), str(off.get("active_rules"))])

func test_card_without_eog_unchanged() -> void:
	print("\n--- Destroyer's Wrath (P2, no eog rule), round 2 ---")
	var on = _awareness(2, 2, 1.0)
	var off = _awareness(2, 2, 0.0)
	_assert(str(on) == str(off), "a card with no eog rule builds the identical awareness on and off")
	_assert(not on.has("eog_withheld"), "and nothing is recorded as held back")

func test_objective_evaluation_drops_enemy_home_vp() -> void:
	print("\n--- _evaluate_all_objectives, Vital Link, round 2 ---")
	var on = _eval_of(_evals(2, 1.0), "obj_home_2")
	var off = _eval_of(_evals(2, 0.0), "obj_home_2")
	print("  obj_home_2 on: vp=%s prio=%.2f | off: vp=%s prio=%.2f" % [on.get("vp_value"), float(on.get("priority", 0.0)),
		off.get("vp_value"), float(off.get("priority", 0.0))])
	_assert(is_equal_approx(float(on.get("vp_value", -1.0)), 4.0) and is_equal_approx(float(off.get("vp_value", -1.0)), 14.0),
		"the enemy home objective is valued 4 VP on (14 off)")
	_assert(is_equal_approx(float(off.get("priority", 0.0)) - float(on.get("priority", 0.0)), 10.0 * AIDM.WEIGHT_VP_PER_POINT),
		"its priority drops by exactly the 10 VP x WEIGHT_VP_PER_POINT the award added")
	var c_on = _eval_of(_evals(2, 1.0), "obj_center")
	var c_off = _eval_of(_evals(2, 0.0), "obj_center")
	_assert(is_equal_approx(float(c_on.get("priority", 0.0)), float(c_off.get("priority", 1.0))),
		"guard: the centre objective (no eog rule on it) keeps its priority (%.2f / %.2f)" % [float(c_on.get("priority", 0.0)), float(c_off.get("priority", 0.0))])

func test_unstoppable_force_centre_round1() -> void:
	print("\n--- Unstoppable Force (eog hold_central 5), round 1 ---")
	var on = _awareness(1, 1, 1.0)
	var c_on = _centre_price(1)
	var off = _awareness(1, 1, 0.0)
	var c_off = _centre_price(1)
	print("  on: central_bonus=%s centre vp=%s | off: central_bonus=%s centre vp=%s" % [
		on.get("central_bonus"), c_on.vp, off.get("central_bonus"), c_off.vp])
	_assert(float(on.get("central_bonus", -1.0)) == 0.0 and not _has_src(c_on.sources, CENTRE_SRC),
		"on: the centre gets no end-of-battle bonus or VP in round 1 (bonus %s, sources %s)" % [str(on.get("central_bonus")), str(c_on.sources)])
	_assert(float(off.get("central_bonus", -1.0)) == 5.0 and _has_src(c_off.sources, CENTRE_SRC),
		"off: central_bonus 5 and '%s 5 VP' as before (%s)" % [CENTRE_SRC, str(c_off.sources)])
