extends SceneTree

# FIX_CHARGE_EV — the charge gang-up bonus counts only help that really arrived.
#
# Critic finding s7419_r3_p2_charge_2 (value-checked: not charging is +8.7 VP
# over 12 paired seeds, +7.9 VP over 24 more): Custodian Guard Gamma declared
# a 17% charge at Scout Squad Beta and FAILED the roll. The 45-point, 2-wound
# Prosecutor Squad then charged the same Scouts for 0.4 expected damage, into
# 2.6 dmg of overwatch and a fight back that wipes it — its charge scored
# +1.72 against a 0.37 bar only because ch_gang_up paid the +7 "kill gang-up"
# bonus for Gamma's 20.8 damage, help that was never coming (its own terms
# summed below zero).
#
#   CH-ARRIVED  charges resolve one unit at a time, so an earlier charger has
#               already rolled when the next unit declares: only one that made
#               it (charged this turn, within engagement range of the target)
#               counts as help; with none, there is no gang-up bonus at all.
#   CH-NEEDED   the kill bonus pays for tipping the target over — none when the
#               chargers already in kill it without this unit.
#   FIX_CHARGE_EV = 0 restores the old behaviour (every declared charger counts).
#
# Run with: godot --headless --path 40k -s tests/unit/test_ai_fix_charge_ev.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")
const AIDifficultyConfig = preload("res://scripts/AIDifficultyConfig.gd")

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== FIX_CHARGE_EV: gang-up counts only help that arrived ===\n")
	# Competitive: no score noise (the -s harness would otherwise default the
	# difficulty static, see test_ai_charge_decisions.gd).
	AIDecisionMaker._current_difficulty = AIDifficultyConfig.Difficulty.COMPETITIVE
	AIDecisionMaker._config_overrides["FIX_CHARGE_EV"] = 1.0  # the fix may be off by default; the checks switch it on
	_test_failed_charger_pays_no_gang_up()
	_test_lone_killer_gets_no_gang_up_from_failed_charger()
	_test_arrived_charger_still_pays_kill_bonus()
	_test_arrived_charger_still_pays_pile_bonus()
	_test_no_kill_bonus_when_target_already_doomed()
	_test_param_zero_restores_base()
	_test_weak_unit_skips_after_failed_charge()
	_test_weak_unit_skips_when_target_already_doomed()
	AIDecisionMaker._charge_coordination.clear()
	AIDecisionMaker._config_overrides.erase("FIX_CHARGE_EV")
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

# ---------------------------------------------------------------------------
# Fixtures (40 px per inch, 32 mm bases)
# ---------------------------------------------------------------------------

func _snapshot() -> Dictionary:
	return {
		"battle_round": 3,
		"board": {"objectives": [], "terrain_features": [], "deployment_zones": []},
		"units": {},
	}

func _melee(wname: String, ws: int, s: int, ap: int, d: int, a: int) -> Dictionary:
	return {"name": wname, "type": "Melee", "weapon_skill": str(ws), "strength": str(s),
		"ap": ("-%d" % ap) if ap > 0 else "0", "damage": str(d), "attacks": str(a)}

# `n` models in a row from `pos`, 60 px (1.5") apart.
func _add(snap: Dictionary, uid: String, owner: int, pos: Vector2, n: int, weapons: Array,
		toughness: int = 4, save_val: int = 3, wounds: int = 1) -> Dictionary:
	var models := []
	for i in range(n):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": 32, "base_type": "circular",
			"base_dimensions": {}, "position": Vector2(pos.x + i * 60, pos.y),
			"wounds": wounds, "current_wounds": wounds})
	var u := {"id": uid, "owner": owner, "status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {"name": uid, "keywords": ["INFANTRY"], "weapons": weapons,
			"stats": {"move": 6, "toughness": toughness, "save": save_val, "wounds": wounds,
				"leadership": 6, "objective_control": 1}},
		"models": models, "flags": {}}
	snap.units[uid] = u
	return u

# The finding's shape: a weak 2-model squad 4.7" from a 6-model, 6 HP target,
# and an elite unit that declared on the target earlier this phase. `guard_in`
# = its charge made it (charged this turn, now in base contact); otherwise it
# failed and is still 9.6" away.
func _finding_snapshot(guard_in: bool) -> Dictionary:
	var snap := _snapshot()
	_add(snap, "scouts", 1, Vector2(800, 1200), 6, [_melee("Combat knife", 3, 3, 0, 1, 1)], 4, 4, 1)
	_add(snap, "pros", 2, Vector2(800, 1438), 2, [_melee("Gun stock", 3, 3, 0, 1, 1)], 4, 3, 1)
	var guard_y := 1130.0 if guard_in else 766.0  # base contact vs 9.6" edge to edge
	var guard := _add(snap, "guard", 2, Vector2(900, guard_y), 3, [_melee("Guardian spear", 2, 7, 2, 2, 5)], 6, 2, 3)
	if guard_in:
		guard.flags["charged_this_turn"] = true
	return snap

# What _evaluate_best_charge records when "guard" declares on "scouts".
func _record_guard_declared(snap: Dictionary) -> void:
	AIDecisionMaker._charge_coordination.clear()
	AIDecisionMaker._charge_coordination["scouts"] = {"charger_ids": ["guard"],
		"total_expected_dmg": AIDecisionMaker._estimate_melee_damage(snap.units.guard, snap.units.scouts)}

func _gang_up(charger: Dictionary, target: Dictionary, snap: Dictionary) -> float:
	var terms := {}
	AIDecisionMaker._score_charge_target(charger, target, snap, 2, terms)
	return float(terms.get("ch_gang_up", 0.0))

func _charge_actions(uid: String, tid: String) -> Array:
	return [{"type": "DECLARE_CHARGE", "actor_unit_id": uid, "payload": {"target_unit_ids": [tid]}},
		{"type": "SKIP_CHARGE", "actor_unit_id": uid}, {"type": "END_CHARGE"}]

# ---------------------------------------------------------------------------
# Scoring: the ch_gang_up term
# ---------------------------------------------------------------------------

func _test_failed_charger_pays_no_gang_up() -> void:
	var snap := _finding_snapshot(false)
	_record_guard_declared(snap)
	var g := _gang_up(snap.units.pros, snap.units.scouts, snap)
	_assert(g == 0.0, "an earlier charge that FAILED its roll pays no gang-up bonus (ch_gang_up %.1f, want 0)" % g)

func _test_lone_killer_gets_no_gang_up_from_failed_charger() -> void:
	# A strong unit that kills the target on its own: the failed earlier
	# declaration must not hand it a "gang-up" kill bonus either (its own kill
	# is already ch_can_wipe).
	var snap := _finding_snapshot(false)
	_record_guard_declared(snap)
	var champ := _add(snap, "champ", 2, Vector2(800, 1438), 3, [_melee("Guardian spear", 2, 7, 2, 2, 5)], 6, 2, 3)
	var d_champ := AIDecisionMaker._estimate_melee_damage(champ, snap.units.scouts)
	_assert(d_champ >= AIDecisionMaker._calculate_kill_threshold(snap.units.scouts),
		"setup: the follow-up kills the target alone (%.2f dmg)" % d_champ)
	var g := _gang_up(champ, snap.units.scouts, snap)
	_assert(g == 0.0, "no gang-up bonus without a helper that arrived, even for a unit that kills alone (ch_gang_up %.1f, want 0)" % g)

func _test_arrived_charger_still_pays_kill_bonus() -> void:
	# The guard made it but deals less than the target's HP; a follow-up whose
	# damage tips it over still gets the kill gang-up bonus (good charges kept).
	var snap := _snapshot()
	_add(snap, "target", 1, Vector2(800, 1200), 4, [_melee("Knife", 4, 3, 0, 1, 1)], 4, 4, 1)
	var guard := _add(snap, "guard", 2, Vector2(800, 1130), 1, [_melee("Guardian spear", 2, 7, 2, 2, 5)], 6, 2, 3)
	guard.flags["charged_this_turn"] = true
	var boyz := _add(snap, "boyz", 2, Vector2(800, 1438), 5, [_melee("Choppa", 3, 4, 1, 1, 2)], 5, 5, 1)
	var d_guard := AIDecisionMaker._estimate_melee_damage(guard, snap.units.target)
	var d_boyz := AIDecisionMaker._estimate_melee_damage(boyz, snap.units.target)
	var hp := AIDecisionMaker._calculate_kill_threshold(snap.units.target)
	_assert(d_guard < hp and d_guard + d_boyz >= hp,
		"setup: the guard alone (%.2f) does not kill the %.0f HP target, guard + boyz (%.2f) does" % [d_guard, hp, d_guard + d_boyz])
	AIDecisionMaker._charge_coordination.clear()
	AIDecisionMaker._charge_coordination["target"] = {"charger_ids": ["guard"], "total_expected_dmg": d_guard}
	var g := _gang_up(boyz, snap.units.target, snap)
	_assert(g == 5.0, "a charger that ARRIVED still pays the kill gang-up bonus when this unit is needed for the kill (ch_gang_up %.1f, want 5)" % g)

func _test_arrived_charger_still_pays_pile_bonus() -> void:
	var snap := _snapshot()
	_add(snap, "target", 1, Vector2(800, 1200), 10, [], 4, 3, 2)  # 20 HP: no kill in reach
	var guard := _add(snap, "guard", 2, Vector2(800, 1130), 1, [_melee("Guardian spear", 2, 7, 2, 2, 5)], 6, 2, 3)
	guard.flags["charged_this_turn"] = true
	var boyz := _add(snap, "boyz", 2, Vector2(800, 1438), 5, [_melee("Choppa", 3, 4, 1, 1, 2)], 5, 5, 1)
	AIDecisionMaker._charge_coordination.clear()
	AIDecisionMaker._charge_coordination["target"] = {"charger_ids": ["guard"],
		"total_expected_dmg": AIDecisionMaker._estimate_melee_damage(guard, snap.units.target)}
	var g := _gang_up(boyz, snap.units.target, snap)
	_assert(g == 2.0, "piling onto a target an arrived charger is fighting keeps the pile-on bonus (ch_gang_up %.1f, want 2)" % g)

func _test_no_kill_bonus_when_target_already_doomed() -> void:
	var snap := _finding_snapshot(true)
	_record_guard_declared(snap)
	var d_guard := float(AIDecisionMaker._charge_coordination.scouts.total_expected_dmg)
	var hp := AIDecisionMaker._calculate_kill_threshold(snap.units.scouts)
	_assert(d_guard >= hp, "setup: the arrived guard alone kills the target (%.2f dmg vs %.0f HP)" % [d_guard, hp])
	var g := _gang_up(snap.units.pros, snap.units.scouts, snap)
	_assert(g == 0.0, "no kill gang-up bonus when the chargers already in kill the target without this unit (ch_gang_up %.1f, want 0)" % g)

func _test_param_zero_restores_base() -> void:
	var snap := _finding_snapshot(false)
	_record_guard_declared(snap)
	AIDecisionMaker._config_overrides["FIX_CHARGE_EV"] = 0.0
	var g := _gang_up(snap.units.pros, snap.units.scouts, snap)
	AIDecisionMaker._config_overrides["FIX_CHARGE_EV"] = 1.0  # the fix may be off by default; the checks switch it on
	_assert(g == 5.0, "FIX_CHARGE_EV = 0: the failed charger counts again — old kill gang-up bonus (ch_gang_up %.1f, want 5)" % g)

# ---------------------------------------------------------------------------
# Decision: the weak squad no longer charges on phantom help
# ---------------------------------------------------------------------------

func _test_weak_unit_skips_after_failed_charge() -> void:
	var snap := _finding_snapshot(false)
	_record_guard_declared(snap)
	var d = AIDecisionMaker._decide_charge(snap, _charge_actions("pros", "scouts"), 2)
	_assert(d.get("type", "") == "SKIP_CHARGE",
		"a 0.2-dmg squad does not charge a target whose earlier charger failed its roll (got %s: %s)" % [d.get("type", ""), d.get("_ai_description", "")])

func _test_weak_unit_skips_when_target_already_doomed() -> void:
	var snap := _finding_snapshot(true)
	_record_guard_declared(snap)
	var d = AIDecisionMaker._decide_charge(snap, _charge_actions("pros", "scouts"), 2)
	_assert(d.get("type", "") == "SKIP_CHARGE",
		"a 0.2-dmg squad does not pile onto a target the arrived charger kills alone (got %s: %s)" % [d.get("type", ""), d.get("_ai_description", "")])
