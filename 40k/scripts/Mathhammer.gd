extends RefCounted
class_name Mathhammer

# Mathhammer - Monte Carlo simulation system for Warhammer 40k combat calculations
# Leverages existing RulesEngine combat resolution for accurate statistical analysis
# Provides expected damage, kill probability, and outcome distribution analysis

# Configuration constants
const DEFAULT_TRIALS = 10000
const MIN_TRIALS = 100
const MAX_TRIALS = 100000

# Statistical result structure
class SimulationResult:
	var trials_run: int = 0
	var total_damage: float = 0.0
	var damage_distribution: Dictionary = {}
	var kill_probability: float = 0.0
	var expected_survivors: float = 0.0
	var damage_efficiency: float = 0.0
	var detailed_trials: Array = []
	var statistical_summary: Dictionary = {}
	
	func get_average_damage() -> float:
		return total_damage / trials_run if trials_run > 0 else 0.0
	
	func get_damage_percentile(percentile: float) -> int:
		if detailed_trials.is_empty():
			return 0
		var sorted_damage = detailed_trials.map(func(trial): return trial.damage)
		sorted_damage.sort()
		var index = int(percentile * sorted_damage.size())
		return sorted_damage[min(index, sorted_damage.size() - 1)]

# Main simulation entry point
static func simulate_combat(config: Dictionary) -> SimulationResult:
	var trials = clamp(config.get("trials", DEFAULT_TRIALS), MIN_TRIALS, MAX_TRIALS)
	var attackers = config.get("attackers", [])
	var defender = config.get("defender", {})
	var rule_toggles = config.get("rule_toggles", {})
	var phase = config.get("phase", "shooting")
	var seed_value = config.get("seed", -1)
	
	if attackers.is_empty() or defender.is_empty():
		push_error("Mathhammer: Missing attackers or defender in simulation config")
		return SimulationResult.new()
	
	var result = SimulationResult.new()
	result.trials_run = trials
	
	# Initialize RNG with seed for reproducible results
	var rng = RulesEngine.RNGService.new(seed_value)
	
	# Run Monte Carlo simulation
	for trial in range(trials):
		var trial_result = _run_single_trial(attackers, defender, phase, rule_toggles, rng)
		result.detailed_trials.append(trial_result)
		result.total_damage += trial_result.damage
		
		# Update damage distribution histogram
		var damage_key = str(trial_result.damage)
		result.damage_distribution[damage_key] = result.damage_distribution.get(damage_key, 0) + 1
		
		# Track kills for probability calculation
		if trial_result.models_killed >= _get_total_models(defender):
			result.kill_probability += 1.0
	
	# Calculate final statistics
	result.kill_probability /= trials
	result.expected_survivors = _calculate_expected_survivors(result, defender)
	result.damage_efficiency = _calculate_damage_efficiency(result, defender)
	result.statistical_summary = _generate_statistical_summary(result)
	
	# Log comprehensive breakdown
	_log_simulation_results(result, attackers, defender, trials)
	
	return result

# Run a single trial of the combat simulation
static func _run_single_trial(attackers: Array, defender: Dictionary, phase: String, rule_toggles: Dictionary, rng: RulesEngine.RNGService) -> Dictionary:
	var trial_result = {
		"damage": 0,
		"models_killed": 0,
		"overkill": 0,
		"hits": 0,
		"wounds": 0,
		"saves_failed": 0,
		"attacks_made": 0,
		"weapon_breakdown": {}  # Track stats per weapon
	}
	
	# Create a mutable copy of board state for this trial
	var trial_board = _create_trial_board_state(attackers, defender)
	
	# Process each attacking unit sequentially
	for attacker_config in attackers:
		var unit_id = attacker_config.get("unit_id", "")
		if not _has_alive_models(trial_board, unit_id):
			continue
		
		# Get unit name for logging
		var unit_name = ""
		if GameState:
			var unit_data = GameState.get_unit(unit_id)
			unit_name = unit_data.get("meta", {}).get("name", unit_id)
		
		# Process each weapon separately
		for weapon_config in attacker_config.get("weapons", []):
			var weapon_id = weapon_config.get("weapon_id", "")
			var attacks = weapon_config.get("attacks", 0)
			
			if attacks <= 0:
				continue
				
			# Initialize weapon breakdown if not already done
			if not trial_result.weapon_breakdown.has(weapon_id):
				trial_result.weapon_breakdown[weapon_id] = {
					"attacks_made": 0,
					"hits": 0,
					"wounds": 0,
					"saves_failed": 0,
					"damage": 0,
					"weapon_name": weapon_id.replace("_", " ").capitalize()
				}
			
			# Create a single weapon attacker config
			var single_weapon_config = {
				"unit_id": unit_id,
				"weapons": [weapon_config]
			}
			
			var shoot_action = _build_shoot_action(single_weapon_config, defender, rule_toggles, trial_board)
			var combat_result = RulesEngine.resolve_shoot(shoot_action, trial_board, rng)
			
			if combat_result.success:
				# Extract combat statistics
				var damage_dealt = _extract_damage_from_result(combat_result)
				trial_result.damage += damage_dealt
				trial_result.models_killed += _count_models_killed_from_diffs(combat_result.diffs)
				
				# Extract dice statistics for detailed breakdown
				for dice_roll in combat_result.dice:
					match dice_roll.context:
						"to_hit":
							trial_result.hits += dice_roll.successes
							trial_result.attacks_made += dice_roll.rolls_raw.size()
							trial_result.weapon_breakdown[weapon_id].attacks_made += dice_roll.rolls_raw.size()
							trial_result.weapon_breakdown[weapon_id].hits += dice_roll.successes
						"to_wound":
							trial_result.wounds += dice_roll.successes
							trial_result.weapon_breakdown[weapon_id].wounds += dice_roll.successes
						"save":
							trial_result.saves_failed += dice_roll.get("fails", 0)
							trial_result.weapon_breakdown[weapon_id].saves_failed += dice_roll.get("fails", 0)
							trial_result.weapon_breakdown[weapon_id].damage += damage_dealt
				
				# Apply damage to trial board state for sequential attackers
				_apply_diffs_to_board(combat_result.diffs, trial_board)
	
	# Calculate overkill
	var defender_total_wounds = _get_total_wounds(defender)
	trial_result.overkill = max(0, trial_result.damage - defender_total_wounds)
	
	return trial_result

# Build shooting action for RulesEngine integration
static func _build_shoot_action(attacker_config: Dictionary, defender: Dictionary, rule_toggles: Dictionary, board: Dictionary) -> Dictionary:
	var unit_id = attacker_config.get("unit_id", "")
	var target_unit_id = defender.get("unit_id", "")
	var weapons = attacker_config.get("weapons", [])
	
	var assignments = []
	
	# Create weapon assignments for all specified weapons
	for weapon_config in weapons:
		var weapon_id = weapon_config.get("weapon_id", "")
		var model_ids = weapon_config.get("model_ids", [])
		var base_attacks = weapon_config.get("attacks", 1)
		
		if weapon_id != "" and not model_ids.is_empty():
			var assignment = {
				"weapon_id": weapon_id,
				"target_unit_id": target_unit_id,
				"model_ids": model_ids
			}
			
			# Apply rule toggles that affect attack count
			if rule_toggles.get("rapid_fire", false):
				assignment["attacks_override"] = base_attacks * 2
			else:
				assignment["attacks_override"] = base_attacks
			
			assignments.append(assignment)
	
	return {
		"type": "SHOOT",
		"actor_unit_id": unit_id,
		"payload": {
			"assignments": assignments
		}
	}

# Create a mutable board state for trial simulation
static func _create_trial_board_state(attackers: Array, defender: Dictionary) -> Dictionary:
	var trial_board = {
		"units": {}
	}
	
	# Add attacker units
	for attacker_config in attackers:
		var unit_id = attacker_config.get("unit_id", "")
		if unit_id != "" and GameState:
			var unit_data = GameState.get_unit(unit_id)
			if not unit_data.is_empty():
				trial_board.units[unit_id] = unit_data.duplicate(true)
	
	# Add defender unit with full health
	var defender_unit_id = defender.get("unit_id", "")
	if defender_unit_id != "" and GameState:
		var defender_data = GameState.get_unit(defender_unit_id)
		if not defender_data.is_empty():
			# Reset defender to full health for clean trial
			var fresh_defender = defender_data.duplicate(true)
			for model in fresh_defender.get("models", []):
				model["alive"] = true
				model["current_wounds"] = model.get("wounds", 1)
			trial_board.units[defender_unit_id] = fresh_defender
	
	return trial_board

# Extract total damage dealt from combat result
static func _extract_damage_from_result(combat_result: Dictionary) -> int:
	var damage = 0
	for diff in combat_result.get("diffs", []):
		if diff.get("op", "") == "set" and diff.get("path", "").ends_with(".current_wounds"):
			# Calculate damage as difference from max wounds (simplified approach)
			var new_wounds = diff.get("value", 0)
			if new_wounds == 0:
				damage += 1  # Model killed, count as 1+ damage
	return damage

# Count models killed from diff operations
static func _count_models_killed_from_diffs(diffs: Array) -> int:
	var killed = 0
	for diff in diffs:
		if diff.get("op", "") == "set" and diff.get("path", "").ends_with(".alive") and diff.get("value", true) == false:
			killed += 1
	return killed

# Apply combat result diffs to trial board state
static func _apply_diffs_to_board(diffs: Array, board: Dictionary) -> void:
	for diff in diffs:
		var path = diff.get("path", "")
		var value = diff.get("value")
		var op = diff.get("op", "")
		
		if op == "set" and path != "":
			_apply_path_value(board, path, value)

# Apply a single path-value change to nested dictionary
static func _apply_path_value(dict: Dictionary, path: String, value) -> void:
	var path_parts = path.split(".")
	var current = dict
	
	# Navigate to parent of target
	for i in range(path_parts.size() - 1):
		var key = path_parts[i]
		if key != null and key.is_valid_int():
			key = int(key)
		
		if current is Array and key is int:
			if key < current.size():
				current = current[key]
			else:
				return  # Invalid path
		elif current is Dictionary:
			if current.has(key):
				current = current[key]
			else:
				return  # Invalid path
		else:
			return  # Invalid path structure
	
	# Set the final value
	var final_key = path_parts[-1]
	if final_key != null and final_key.is_valid_int():
		final_key = int(final_key)
	
	if current is Array and final_key is int and final_key < current.size():
		current[final_key] = value
	elif current is Dictionary:
		current[final_key] = value

# Utility functions for analysis
static func _get_total_models(unit_config: Dictionary) -> int:
	if GameState:
		var unit_data = GameState.get_unit(unit_config.get("unit_id", ""))
		return unit_data.get("models", []).size()
	return 0

static func _get_total_wounds(unit_config: Dictionary) -> int:
	if GameState:
		var unit_data = GameState.get_unit(unit_config.get("unit_id", ""))
		var total = 0
		for model in unit_data.get("models", []):
			total += model.get("wounds", 1)
		return total
	return 0

static func _has_alive_models(board: Dictionary, unit_id: String) -> bool:
	var unit = board.get("units", {}).get(unit_id, {})
	for model in unit.get("models", []):
		if model.get("alive", true):
			return true
	return false

static func _calculate_expected_survivors(result: SimulationResult, defender: Dictionary) -> float:
	var total_models = _get_total_models(defender)
	var avg_killed = 0.0
	
	for trial in result.detailed_trials:
		avg_killed += trial.models_killed
	
	avg_killed /= result.trials_run
	return max(0.0, total_models - avg_killed)

static func _calculate_damage_efficiency(result: SimulationResult, defender: Dictionary) -> float:
	var total_wounds = _get_total_wounds(defender)
	if total_wounds == 0:
		return 0.0
	
	var avg_damage = result.get_average_damage()
	var useful_damage = min(avg_damage, total_wounds)
	return (useful_damage / avg_damage) if avg_damage > 0 else 0.0

static func _generate_statistical_summary(result: SimulationResult) -> Dictionary:
	return {
		"mean_damage": result.get_average_damage(),
		"median_damage": result.get_damage_percentile(0.5),
		"percentile_25": result.get_damage_percentile(0.25),
		"percentile_75": result.get_damage_percentile(0.75),
		"percentile_95": result.get_damage_percentile(0.95),
		"max_damage": result.get_damage_percentile(1.0),
		"min_damage": result.get_damage_percentile(0.0)
	}

static func _log_simulation_results(result: SimulationResult, attackers: Array, defender: Dictionary, trials: int) -> void:
	print("\n=========================================")
	print("=== MATHHAMMER SIMULATION RESULTS ===")
	print("=========================================")
	print("Trials run: %d" % trials)
	print("Number of attacking units: %d" % attackers.size())
	
	# Aggregate weapon stats across all trials
	var weapon_totals = {}
	var total_attacks_across_trials = 0
	var total_hits_across_trials = 0
	var total_wounds_across_trials = 0
	var total_unsaved_across_trials = 0
	
	for trial in result.detailed_trials:
		for weapon_id in trial.get("weapon_breakdown", {}):
			if not weapon_totals.has(weapon_id):
				weapon_totals[weapon_id] = {
					"attacks_made": 0,
					"hits": 0,
					"wounds": 0,
					"saves_failed": 0,
					"damage": 0,
					"weapon_name": trial.weapon_breakdown[weapon_id].weapon_name
				}
			weapon_totals[weapon_id].attacks_made += trial.weapon_breakdown[weapon_id].attacks_made
			weapon_totals[weapon_id].hits += trial.weapon_breakdown[weapon_id].hits
			weapon_totals[weapon_id].wounds += trial.weapon_breakdown[weapon_id].wounds
			weapon_totals[weapon_id].saves_failed += trial.weapon_breakdown[weapon_id].saves_failed
			weapon_totals[weapon_id].damage += trial.weapon_breakdown[weapon_id].damage
			
			total_attacks_across_trials += trial.weapon_breakdown[weapon_id].attacks_made
			total_hits_across_trials += trial.weapon_breakdown[weapon_id].hits
			total_wounds_across_trials += trial.weapon_breakdown[weapon_id].wounds
			total_unsaved_across_trials += trial.weapon_breakdown[weapon_id].saves_failed
	
	# Log per-weapon breakdown
	print("\n--- WEAPON BREAKDOWN ---")
	var weapon_count = 0
	for weapon_id in weapon_totals:
		weapon_count += 1
		var stats = weapon_totals[weapon_id]
		var hit_rate = (float(stats.hits) / float(stats.attacks_made) * 100.0) if stats.attacks_made > 0 else 0.0
		var wound_rate = (float(stats.wounds) / float(stats.hits) * 100.0) if stats.hits > 0 else 0.0
		var unsaved_rate = (float(stats.saves_failed) / float(stats.wounds) * 100.0) if stats.wounds > 0 else 0.0
		
		print("\n[Weapon %d] %s:" % [weapon_count, stats.weapon_name])
		print("  Total Attacks: %d" % stats.attacks_made)
		print("  Avg Attacks/Trial: %.1f" % (float(stats.attacks_made) / float(trials)))
		print("  Hits: %d (%.1f%%)" % [stats.hits, hit_rate])
		print("  Wounds: %d (%.1f%% of hits)" % [stats.wounds, wound_rate])
		print("  Unsaved: %d (%.1f%% of wounds)" % [stats.saves_failed, unsaved_rate])
		print("  Total Damage: %d" % stats.damage)
		print("  Avg Damage/Trial: %.2f" % (float(stats.damage) / float(trials)))
	
	# Log aggregated totals
	if weapon_totals.size() > 1:
		print("\n--- AGGREGATED TOTALS ---")
		print("Total Attacks Made: %d" % total_attacks_across_trials)
		print("Total Hits: %d" % total_hits_across_trials)
		print("Total Wounds: %d" % total_wounds_across_trials)
		print("Total Unsaved: %d" % total_unsaved_across_trials)
		var overall_hit_rate = (float(total_hits_across_trials) / float(total_attacks_across_trials) * 100.0) if total_attacks_across_trials > 0 else 0.0
		var overall_wound_rate = (float(total_wounds_across_trials) / float(total_hits_across_trials) * 100.0) if total_hits_across_trials > 0 else 0.0
		var overall_unsaved_rate = (float(total_unsaved_across_trials) / float(total_wounds_across_trials) * 100.0) if total_wounds_across_trials > 0 else 0.0
		print("Overall Hit Rate: %.1f%%" % overall_hit_rate)
		print("Overall Wound Rate: %.1f%%" % overall_wound_rate) 
		print("Overall Unsaved Rate: %.1f%%" % overall_unsaved_rate)
	
	# Log overall statistics
	print("\n--- DAMAGE STATISTICS ---")
	print("Average Damage: %.2f" % result.get_average_damage())
	print("Median Damage: %d" % result.get_damage_percentile(0.5))
	print("25th Percentile: %d" % result.get_damage_percentile(0.25))
	print("75th Percentile: %d" % result.get_damage_percentile(0.75))
	print("95th Percentile: %d" % result.get_damage_percentile(0.95))
	print("Max Damage: %d" % result.get_damage_percentile(1.0))
	print("Min Damage: %d" % result.get_damage_percentile(0.0))
	
	# Get defender info
	var defender_name = ""
	var defender_wounds = 0
	var defender_models = 0
	if GameState:
		var defender_unit_id = defender.get("unit_id", "")
		var defender_data = GameState.get_unit(defender_unit_id)
		defender_name = defender_data.get("meta", {}).get("name", defender_unit_id)
		defender_wounds = _get_total_wounds(defender)
		defender_models = _get_total_models(defender)
	
	print("\n--- TARGET INFO ---")
	print("Defender: %s" % defender_name)
	print("Total Models: %d" % defender_models)
	print("Total Wounds: %d" % defender_wounds)
	print("Kill Probability: %.1f%%" % (result.kill_probability * 100))
	print("Expected Survivors: %.2f models" % result.expected_survivors)
	print("=========================================\n")

# Validation function for simulation configuration
static func validate_simulation_config(config: Dictionary) -> Dictionary:
	var errors = []
	
	var attackers = config.get("attackers", [])
	var defender = config.get("defender", {})
	
	if attackers.is_empty():
		errors.append("No attackers specified")
	
	if defender.is_empty():
		errors.append("No defender specified")
	
	# Validate attacker configurations
	for i in range(attackers.size()):
		var attacker = attackers[i]
		var unit_id = attacker.get("unit_id", "")
		
		if unit_id == "":
			errors.append("Attacker %d missing unit_id" % i)
		elif GameState and GameState.get_unit(unit_id).is_empty():
			errors.append("Attacker %d unit not found: %s" % [i, unit_id])
		
		var weapons = attacker.get("weapons", [])
		if weapons.is_empty():
			errors.append("Attacker %d has no weapons specified" % i)
	
	# Validate defender configuration
	var defender_unit_id = defender.get("unit_id", "")
	if defender_unit_id == "":
		errors.append("Defender missing unit_id")
	elif GameState and GameState.get_unit(defender_unit_id).is_empty():
		errors.append("Defender unit not found: %s" % defender_unit_id)
	
	# Validate trial count
	var trials = config.get("trials", DEFAULT_TRIALS)
	if trials < MIN_TRIALS or trials > MAX_TRIALS:
		errors.append("Trial count must be between %d and %d" % [MIN_TRIALS, MAX_TRIALS])
	
	return {
		"valid": errors.is_empty(),
		"errors": errors
	}