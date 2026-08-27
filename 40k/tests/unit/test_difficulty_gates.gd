extends SceneTree

# Test AI Difficulty Gates
# Verifies that AIDifficultyConfig's gate functions return the documented
# per-tier matrix AND that AIDecisionMaker actually consults the previously
# decorative gates (use_screening, use_trade_analysis, use_focus_fire,
# use_weapon_efficiency, use_survival_assessment). The source-shape pins are
# a regression net against a silent unwire; the behavioral checks prove the
# gate-off paths return neutral values.
# Run with: godot --headless --path . -s tests/unit/test_difficulty_gates.gd

const AIDifficultyConfig = preload("res://scripts/AIDifficultyConfig.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")

const EASY = AIDifficultyConfig.Difficulty.EASY
const NORMAL = AIDifficultyConfig.Difficulty.NORMAL
const HARD = AIDifficultyConfig.Difficulty.HARD
const COMPETITIVE = AIDifficultyConfig.Difficulty.COMPETITIVE

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== AI Difficulty Gate Tests ===\n")
	_run_tests()

	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	if _fail_count > 0:
		print("SOME TESTS FAILED")
	else:
		print("ALL TESTS PASSED")
	quit(1 if _fail_count > 0 else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

func _run_tests():
	test_gate_tier_matrix()
	test_movement_iterations_matrix()
	test_gate_call_sites_present()
	test_trade_efficiency_gated_by_difficulty()
	test_efficiency_multiplier_gated_by_difficulty()

# =========================================================================
# Helper: assert one gate across all four tiers
# =========================================================================

func _assert_gate(gate_name: String, fn: Callable, expected: Array) -> void:
	var tiers = [EASY, NORMAL, HARD, COMPETITIVE]
	var tier_names = ["Easy", "Normal", "Hard", "Competitive"]
	for i in range(tiers.size()):
		var actual = fn.call(tiers[i])
		_assert(actual == expected[i], "%s(%s) == %s" % [gate_name, tier_names[i], str(expected[i])])

# =========================================================================
# Tier matrix — the documented per-difficulty values
# =========================================================================

func test_gate_tier_matrix():
	print("\n--- Gate tier matrix (Easy / Normal / Hard / Competitive) ---")
	_assert_gate("use_random_actions", AIDifficultyConfig.use_random_actions, [true, false, false, false])
	_assert_gate("use_stratagems", AIDifficultyConfig.use_stratagems, [false, true, true, true])
	_assert_gate("use_multi_phase_planning", AIDifficultyConfig.use_multi_phase_planning, [false, false, true, true])
	_assert_gate("use_focus_fire", AIDifficultyConfig.use_focus_fire, [false, true, true, true])
	_assert_gate("use_threat_awareness", AIDifficultyConfig.use_threat_awareness, [false, true, true, true])
	_assert_gate("use_trade_analysis", AIDifficultyConfig.use_trade_analysis, [false, false, false, true])
	_assert_gate("use_look_ahead", AIDifficultyConfig.use_look_ahead, [false, false, false, true])
	_assert_gate("use_weapon_efficiency", AIDifficultyConfig.use_weapon_efficiency, [false, true, true, true])
	_assert_gate("use_survival_assessment", AIDifficultyConfig.use_survival_assessment, [false, true, true, true])
	_assert_gate("use_screening", AIDifficultyConfig.use_screening, [false, false, true, true])
	_assert_gate("use_counter_deployment", AIDifficultyConfig.use_counter_deployment, [false, true, true, true])
	_assert_gate("use_command_reroll", AIDifficultyConfig.use_command_reroll, [false, true, true, true])
	_assert_gate("use_overwatch", AIDifficultyConfig.use_overwatch, [false, true, true, true])
	_assert_gate("use_counter_offensive", AIDifficultyConfig.use_counter_offensive, [false, true, true, true])

func test_movement_iterations_matrix():
	print("\n--- get_movement_iterations matrix ---")
	_assert_gate("get_movement_iterations", AIDifficultyConfig.get_movement_iterations, [1, 3, 5, 8])

# =========================================================================
# Source-shape pins — catch a silent unwire of the newly consulted gates
# =========================================================================

func test_gate_call_sites_present():
	print("\n--- AIDecisionMaker gate call sites (source pins) ---")
	var f = FileAccess.open("res://scripts/AIDecisionMaker.gd", FileAccess.READ)
	_assert(f != null, "AIDecisionMaker.gd source is readable")
	if f == null:
		return
	var src = f.get_as_text()
	var required_calls = [
		"AIDifficultyConfigData.use_screening(_current_difficulty)",
		"AIDifficultyConfigData.use_trade_analysis(_current_difficulty)",
		"AIDifficultyConfigData.use_focus_fire(_current_difficulty)",
		"AIDifficultyConfigData.use_weapon_efficiency(_current_difficulty)",
		"AIDifficultyConfigData.use_survival_assessment(_current_difficulty)",
		# Previously wired gates — pinned so they stay wired too
		"AIDifficultyConfigData.use_random_actions(",
		"AIDifficultyConfigData.use_threat_awareness(",
		"AIDifficultyConfigData.use_stratagems(",
	]
	for call in required_calls:
		_assert(call in src, "AIDecisionMaker.gd contains gate call '%s'" % call)

# =========================================================================
# Behavioral: gate-off paths return neutral values
# =========================================================================

func _mk_unit(points: int, wounds: int, num_models: int, keywords: Array = ["INFANTRY"], toughness: int = 4) -> Dictionary:
	var models = []
	for i in range(num_models):
		models.append({
			"id": "m%d" % i,
			"alive": true,
			"current_wounds": wounds,
			"position": {"x": 100.0 + i * 40.0, "y": 100.0}
		})
	return {
		"meta": {
			"points": points,
			"keywords": keywords,
			"stats": {"wounds": wounds, "toughness": toughness}
		},
		"models": models
	}

func test_trade_efficiency_gated_by_difficulty():
	print("\n--- _get_trade_efficiency respects use_trade_analysis ---")
	var saved_difficulty = AIDecisionMaker._current_difficulty
	# 65pt / 10W attacker (6.5 ppw) vs 200pt / 13W target (15.4 ppw) — a
	# clearly favorable trade, so the Competitive multiplier must exceed 1.0.
	var attacker = _mk_unit(65, 2, 5)
	var target = _mk_unit(200, 13, 1, ["VEHICLE"], 10)

	AIDecisionMaker._current_difficulty = COMPETITIVE
	var eff_competitive = AIDecisionMaker._get_trade_efficiency(attacker, target)
	_assert(eff_competitive > 1.0, "Competitive: favorable trade multiplier > 1.0 (got %.2f)" % eff_competitive)

	for tier_info in [[EASY, "Easy"], [NORMAL, "Normal"], [HARD, "Hard"]]:
		AIDecisionMaker._current_difficulty = tier_info[0]
		var eff = AIDecisionMaker._get_trade_efficiency(attacker, target)
		_assert(eff == 1.0, "%s: trade multiplier is neutral 1.0 (got %.2f)" % [tier_info[1], eff])

	AIDecisionMaker._current_difficulty = saved_difficulty

func test_efficiency_multiplier_gated_by_difficulty():
	print("\n--- _calculate_efficiency_multiplier respects use_weapon_efficiency ---")
	var saved_difficulty = AIDecisionMaker._current_difficulty
	# Anti-tank profile (S9, AP-3, D6 damage) vs a VEHICLE — a perfect match,
	# so the Normal+ multiplier must differ from neutral.
	var weapon = {
		"name": "Test Lascannon",
		"type": "Ranged",
		"strength": "9",
		"ap": "-3",
		"damage": "D6",
		"special_rules": ""
	}
	var vehicle = _mk_unit(200, 13, 1, ["VEHICLE"], 10)

	AIDecisionMaker._current_difficulty = NORMAL
	var mult_normal = AIDecisionMaker._calculate_efficiency_multiplier(weapon, vehicle)
	_assert(mult_normal != 1.0, "Normal: anti-tank vs vehicle multiplier is non-neutral (got %.2f)" % mult_normal)

	AIDecisionMaker._current_difficulty = EASY
	var mult_easy = AIDecisionMaker._calculate_efficiency_multiplier(weapon, vehicle)
	_assert(mult_easy == 1.0, "Easy: multiplier is EFFICIENCY_NEUTRAL 1.0 (got %.2f)" % mult_easy)

	AIDecisionMaker._current_difficulty = saved_difficulty
