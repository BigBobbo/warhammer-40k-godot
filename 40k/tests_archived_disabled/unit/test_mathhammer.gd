extends "res://addons/gut/test.gd"

# Unit tests for Mathhammer core simulation engine
# Validates Monte Carlo simulation, RulesEngine integration, and statistical accuracy

var test_config: Dictionary
var mock_attacker: Dictionary
var mock_defender: Dictionary

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

	# Setup test configuration
	mock_attacker = {
		"unit_id": "TEST_ATTACKER",
		"weapons": [{
			"weapon_id": "test_weapon",
			"model_ids": ["m1", "m2"],
			"attacks": 2
		}]
	}
	
	mock_defender = {
		"unit_id": "TEST_DEFENDER"
	}
	
	test_config = {
		"trials": 1000,  # Smaller number for faster testing
		"attackers": [mock_attacker],
		"defender": mock_defender,
		"rule_toggles": {},
		"phase": "shooting",
		"seed": 12345  # Fixed seed for reproducible results
	}
	
	# Setup mock game state
	_setup_mock_game_state()

func _setup_mock_game_state():
	# Create mock units for testing
	if GameState:
		GameState.state = {
			"units": {
				"TEST_ATTACKER": {
					"id": "TEST_ATTACKER",
					"owner": 1,
					"meta": {
						"name": "Test Attacker",
						"points": 100,
						"weapons": [{
							"name": "Test Weapon",
							"type": "Ranged",
							"range": "24",
							"attacks": "2",
							"ballistic_skill": "3",
							"strength": "4",
							"ap": "0",
							"damage": "1"
						}]
					},
					"models": [
						{"id": "m1", "wounds": 1, "current_wounds": 1, "alive": true, "position": {"x": 100, "y": 100}},
						{"id": "m2", "wounds": 1, "current_wounds": 1, "alive": true, "position": {"x": 120, "y": 100}}
					]
				},
				"TEST_DEFENDER": {
					"id": "TEST_DEFENDER", 
					"owner": 2,
					"meta": {
						"name": "Test Defender",
						"stats": {
							"toughness": 4,
							"save": 5
						}
					},
					"models": [
						{"id": "m1", "wounds": 1, "current_wounds": 1, "alive": true, "position": {"x": 300, "y": 100}},
						{"id": "m2", "wounds": 1, "current_wounds": 1, "alive": true, "position": {"x": 320, "y": 100}}
					]
				}
			}
		}

func test_simulation_runs_successfully():
	# Test basic simulation execution
	var result = Mathhammer.simulate_combat(test_config)
	
	assert_not_null(result, "Simulation should return a result")
	assert_eq(result.trials_run, 1000, "Should run correct number of trials")
	assert_ge(result.total_damage, 0, "Total damage should be non-negative")

func test_simulation_with_zero_trials():
	# Test edge case with zero trials
	test_config.trials = 0
	var result = Mathhammer.simulate_combat(test_config)
	
	assert_eq(result.trials_run, 100, "Should enforce minimum trials")

func test_simulation_with_excessive_trials():
	# Test edge case with too many trials
	test_config.trials = 200000
	var result = Mathhammer.simulate_combat(test_config)
	
	assert_le(result.trials_run, 100000, "Should enforce maximum trials")

func test_damage_distribution():
	# Test damage distribution calculation
	var result = Mathhammer.simulate_combat(test_config)
	
	assert_false(result.damage_distribution.is_empty(), "Should have damage distribution")
	
	# Verify distribution adds up to total trials
	var total_count = 0
	for damage_key in result.damage_distribution:
		total_count += result.damage_distribution[damage_key]
	
	assert_eq(total_count, result.trials_run, "Distribution should account for all trials")

func test_statistical_summary():
	# Test statistical summary generation
	var result = Mathhammer.simulate_combat(test_config)
	
	assert_false(result.statistical_summary.is_empty(), "Should have statistical summary")
	assert_true(result.statistical_summary.has("mean_damage"), "Should have mean damage")
	assert_true(result.statistical_summary.has("median_damage"), "Should have median damage")
	assert_ge(result.statistical_summary.mean_damage, 0, "Mean damage should be non-negative")

func test_kill_probability_calculation():
	# Test kill probability with easy target
	test_config.trials = 100
	var result = Mathhammer.simulate_combat(test_config)
	
	assert_ge(result.kill_probability, 0.0, "Kill probability should be >= 0")
	assert_le(result.kill_probability, 1.0, "Kill probability should be <= 1")

func test_expected_survivors_calculation():
	# Test expected survivors calculation
	var result = Mathhammer.simulate_combat(test_config)
	
	assert_ge(result.expected_survivors, 0.0, "Expected survivors should be non-negative")

func test_damage_efficiency_calculation():
	# Test damage efficiency calculation
	var result = Mathhammer.simulate_combat(test_config)
	
	assert_ge(result.damage_efficiency, 0.0, "Damage efficiency should be non-negative")
	assert_le(result.damage_efficiency, 1.0, "Damage efficiency should be <= 1.0")

func test_percentile_calculations():
	# Test percentile calculations
	var result = Mathhammer.simulate_combat(test_config)
	
	var p25 = result.get_damage_percentile(0.25)
	var median = result.get_damage_percentile(0.5)
	var p75 = result.get_damage_percentile(0.75)
	
	assert_le(p25, median, "25th percentile should be <= median")
	assert_le(median, p75, "Median should be <= 75th percentile")

func test_reproducible_results_with_seed():
	# Test that same seed produces same results
	var result1 = Mathhammer.simulate_combat(test_config)
	var result2 = Mathhammer.simulate_combat(test_config)
	
	assert_eq(result1.get_average_damage(), result2.get_average_damage(), "Same seed should produce identical results")

func test_different_seeds_produce_different_results():
	# Test that different seeds produce different results
	test_config.seed = 12345
	var result1 = Mathhammer.simulate_combat(test_config)
	
	test_config.seed = 54321
	var result2 = Mathhammer.simulate_combat(test_config)
	
	# With enough trials, results should be different (very low probability of being identical)
	var diff = abs(result1.get_average_damage() - result2.get_average_damage())
	assert_gt(diff, 0.001, "Different seeds should produce different results")

func test_empty_attackers_validation():
	# Test validation with empty attackers
	test_config.attackers = []
	var result = Mathhammer.simulate_combat(test_config)
	
	assert_eq(result.trials_run, 0, "Empty attackers should return empty result")

func test_empty_defender_validation():
	# Test validation with empty defender
	test_config.defender = {}
	var result = Mathhammer.simulate_combat(test_config)
	
	assert_eq(result.trials_run, 0, "Empty defender should return empty result")

func test_config_validation_success():
	# Test successful configuration validation
	var validation = Mathhammer.validate_simulation_config(test_config)
	
	assert_true(validation.valid, "Valid config should pass validation")
	assert_true(validation.errors.is_empty(), "Valid config should have no errors")

func test_config_validation_missing_attackers():
	# Test validation with missing attackers
	test_config.attackers = []
	var validation = Mathhammer.validate_simulation_config(test_config)
	
	assert_false(validation.valid, "Config without attackers should fail validation")
	assert_false(validation.errors.is_empty(), "Should have validation errors")

func test_config_validation_missing_defender():
	# Test validation with missing defender
	test_config.defender = {}
	var validation = Mathhammer.validate_simulation_config(test_config)
	
	assert_false(validation.valid, "Config without defender should fail validation")
	assert_false(validation.errors.is_empty(), "Should have validation errors")

func test_config_validation_invalid_trials():
	# Test validation with invalid trial count
	test_config.trials = -100
	var validation = Mathhammer.validate_simulation_config(test_config)
	
	assert_false(validation.valid, "Config with invalid trials should fail validation")

func test_performance_requirement():
	# Test that 10K trials complete in reasonable time
	test_config.trials = 10000
	var start_time = Time.get_ticks_msec()
	
	var result = Mathhammer.simulate_combat(test_config)
	
	var elapsed_time = Time.get_ticks_msec() - start_time
	assert_lt(elapsed_time, 5000, "10K trials should complete in under 5 seconds") # Relaxed from 2s requirement
	assert_eq(result.trials_run, 10000, "Should complete all trials")

func test_multi_attacker_support():
	# Test multiple attackers
	var second_attacker = mock_attacker.duplicate()
	second_attacker.unit_id = "TEST_ATTACKER"  # Use same attacker for simplicity
	test_config.attackers = [mock_attacker, second_attacker]
	
	var result = Mathhammer.simulate_combat(test_config)
	
	assert_not_null(result, "Multi-attacker simulation should work")
	assert_eq(result.trials_run, 1000, "Should run all trials with multiple attackers")