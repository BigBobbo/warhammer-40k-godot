extends RefCounted
class_name MathhammerResults

# MathhammerResults - Advanced statistical analysis and results processing
# Provides comprehensive analysis of Mathhammer simulation results
# Includes distribution analysis, confidence intervals, and efficiency metrics

# Statistical constants
const CONFIDENCE_95_PERCENT = 1.96  # Z-score for 95% confidence interval
const CONFIDENCE_99_PERCENT = 2.576  # Z-score for 99% confidence interval

# Analysis result structure
class AnalysisResult:
	var basic_stats: Dictionary = {}
	var distribution: Dictionary = {}
	var confidence_intervals: Dictionary = {}
	var efficiency_metrics: Dictionary = {}
	var recommendations: Array = []

# Perform comprehensive statistical analysis
static func analyze_results(simulation_result: Mathhammer.SimulationResult, config: Dictionary) -> AnalysisResult:
	var analysis = AnalysisResult.new()
	
	if not simulation_result or simulation_result.trials_run == 0:
		return analysis
	
	# Calculate basic statistics
	analysis.basic_stats = _calculate_basic_statistics(simulation_result)
	
	# Analyze damage distribution
	analysis.distribution = _analyze_damage_distribution(simulation_result)
	
	# Calculate confidence intervals
	analysis.confidence_intervals = _calculate_confidence_intervals(simulation_result)
	
	# Calculate efficiency metrics
	analysis.efficiency_metrics = _calculate_efficiency_metrics(simulation_result, config)
	
	# Generate tactical recommendations
	analysis.recommendations = _generate_recommendations(simulation_result, config, analysis)
	
	return analysis

# Calculate basic descriptive statistics
static func _calculate_basic_statistics(result: Mathhammer.SimulationResult) -> Dictionary:
	var stats = {}
	
	if result.detailed_trials.is_empty():
		return stats
	
	# Extract damage values
	var damage_values = []
	var hit_values = []
	var wound_values = []
	
	for trial in result.detailed_trials:
		damage_values.append(trial.damage)
		hit_values.append(trial.hits)
		wound_values.append(trial.wounds)
	
	# Calculate statistics for damage
	stats["damage"] = {
		"mean": _calculate_mean(damage_values),
		"median": _calculate_median(damage_values),
		"mode": _calculate_mode(damage_values),
		"std_dev": _calculate_standard_deviation(damage_values),
		"variance": _calculate_variance(damage_values),
		"skewness": _calculate_skewness(damage_values),
		"kurtosis": _calculate_kurtosis(damage_values)
	}
	
	# Calculate statistics for hits
	stats["hits"] = {
		"mean": _calculate_mean(hit_values),
		"median": _calculate_median(hit_values),
		"std_dev": _calculate_standard_deviation(hit_values)
	}
	
	# Calculate statistics for wounds
	stats["wounds"] = {
		"mean": _calculate_mean(wound_values),
		"median": _calculate_median(wound_values),
		"std_dev": _calculate_standard_deviation(wound_values)
	}
	
	return stats

# Analyze damage distribution patterns
static func _analyze_damage_distribution(result: Mathhammer.SimulationResult) -> Dictionary:
	var distribution = {}
	
	if result.damage_distribution.is_empty():
		return distribution
	
	var total_trials = float(result.trials_run)
	var sorted_damages = result.damage_distribution.keys()
	sorted_damages.sort_custom(func(a, b): return int(a) < int(b))
	
	# Calculate probabilities and cumulative distribution
	var probabilities = {}
	var cumulative = {}
	var running_total = 0.0
	
	for damage_str in sorted_damages:
		var damage = int(damage_str)
		var count = result.damage_distribution[damage_str]
		var probability = count / total_trials
		
		probabilities[damage] = probability
		running_total += probability
		cumulative[damage] = running_total
	
	distribution["probabilities"] = probabilities
	distribution["cumulative"] = cumulative
	distribution["expected_value"] = _calculate_expected_value(probabilities)
	distribution["entropy"] = _calculate_entropy(probabilities)
	
	# Identify significant damage thresholds
	distribution["thresholds"] = _identify_damage_thresholds(cumulative)
	
	return distribution

# Calculate confidence intervals
static func _calculate_confidence_intervals(result: Mathhammer.SimulationResult) -> Dictionary:
	var intervals = {}
	
	if result.detailed_trials.is_empty():
		return intervals
	
	var damage_values = result.detailed_trials.map(func(trial): return trial.damage)
	var mean_damage = _calculate_mean(damage_values)
	var std_dev = _calculate_standard_deviation(damage_values)
	var n = float(result.trials_run)
	
	# Standard error of the mean
	var std_error = std_dev / sqrt(n)
	
	# 95% confidence interval
	var margin_95 = CONFIDENCE_95_PERCENT * std_error
	intervals["95_percent"] = {
		"lower": mean_damage - margin_95,
		"upper": mean_damage + margin_95,
		"margin": margin_95
	}
	
	# 99% confidence interval
	var margin_99 = CONFIDENCE_99_PERCENT * std_error
	intervals["99_percent"] = {
		"lower": mean_damage - margin_99,
		"upper": mean_damage + margin_99,
		"margin": margin_99
	}
	
	# Statistical significance test for non-zero damage
	var t_statistic = mean_damage / std_error if std_error > 0 else 0
	intervals["significance"] = {
		"t_statistic": t_statistic,
		"p_value_estimate": _estimate_p_value(t_statistic),
		"significantly_positive": t_statistic > CONFIDENCE_95_PERCENT
	}
	
	return intervals

# Calculate efficiency and effectiveness metrics
static func _calculate_efficiency_metrics(result: Mathhammer.SimulationResult, config: Dictionary) -> Dictionary:
	var metrics = {}
	
	if result.trials_run == 0:
		return metrics
	
	# Basic efficiency metrics
	metrics["damage_efficiency"] = result.damage_efficiency
	metrics["kill_probability"] = result.kill_probability
	metrics["expected_survivors"] = result.expected_survivors
	
	# Advanced efficiency calculations
	var avg_damage = result.get_average_damage()
	
	# Calculate points efficiency (damage per point spent)
	var attacker_cost = _calculate_attacker_cost(config.get("attackers", []))
	if attacker_cost > 0:
		metrics["damage_per_point"] = avg_damage / attacker_cost
		metrics["kills_per_point"] = (1.0 - result.kill_probability) / attacker_cost if result.kill_probability < 1.0 else 1.0 / attacker_cost
	
	# Calculate risk metrics
	metrics["consistency"] = _calculate_consistency_score(result)
	metrics["reliability"] = _calculate_reliability_score(result)
	
	# Time-to-kill analysis
	metrics["expected_turns_to_kill"] = _calculate_turns_to_kill(result, config)
	
	# Overkill analysis
	var overkill_values = result.detailed_trials.map(func(trial): return trial.overkill)
	metrics["average_overkill"] = _calculate_mean(overkill_values)
	metrics["overkill_percentage"] = metrics.average_overkill / avg_damage if avg_damage > 0 else 0
	
	return metrics

# Generate tactical recommendations based on analysis
static func _generate_recommendations(result: Mathhammer.SimulationResult, config: Dictionary, analysis: AnalysisResult) -> Array:
	var recommendations = []
	
	# Efficiency recommendations
	var efficiency = analysis.efficiency_metrics.get("damage_efficiency", 0)
	if efficiency < 0.7:
		recommendations.append({
			"type": "efficiency",
			"priority": "high", 
			"message": "Low damage efficiency (%.1f%%). Consider targeting different units or using different weapons." % (efficiency * 100)
		})
	
	# Consistency recommendations
	var consistency = analysis.efficiency_metrics.get("consistency", 0)
	if consistency < 0.5:
		recommendations.append({
			"type": "consistency",
			"priority": "medium",
			"message": "Inconsistent damage output. Consider weapons with more reliable damage."
		})
	
	# Kill probability recommendations
	var kill_prob = result.kill_probability
	if kill_prob < 0.3:
		recommendations.append({
			"type": "lethality",
			"priority": "high",
			"message": "Low kill probability (%.1f%%). Consider focusing fire or adding more attackers." % (kill_prob * 100)
		})
	elif kill_prob > 0.9:
		recommendations.append({
			"type": "optimization",
			"priority": "low",
			"message": "Very high kill probability (%.1f%%). You might be overkilling this target." % (kill_prob * 100)
		})
	
	# Overkill recommendations
	var overkill_percent = analysis.efficiency_metrics.get("overkill_percentage", 0)
	if overkill_percent > 0.3:
		recommendations.append({
			"type": "overkill",
			"priority": "medium",
			"message": "High overkill (%.1f%%). Consider splitting attacks or targeting different units." % (overkill_percent * 100)
		})
	
	# Statistical significance recommendations
	var significance = analysis.confidence_intervals.get("significance", {})
	if not significance.get("significantly_positive", false):
		recommendations.append({
			"type": "statistical",
			"priority": "high",
			"message": "Damage output not statistically significant. This matchup may not be effective."
		})
	
	return recommendations

# Statistical calculation functions
static func _calculate_mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	return values.reduce(func(sum, val): return sum + val, 0.0) / values.size()

static func _calculate_median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	
	var sorted_values = values.duplicate()
	sorted_values.sort()
	var n = sorted_values.size()
	
	if n % 2 == 0:
		return (sorted_values[n/2 - 1] + sorted_values[n/2]) / 2.0
	else:
		return sorted_values[n/2]

static func _calculate_mode(values: Array) -> float:
	if values.is_empty():
		return 0.0
	
	var frequency = {}
	for value in values:
		frequency[value] = frequency.get(value, 0) + 1
	
	var max_freq = 0
	var mode_value = 0
	
	for value in frequency:
		if frequency[value] > max_freq:
			max_freq = frequency[value]
			mode_value = value
	
	return mode_value

static func _calculate_variance(values: Array) -> float:
	if values.size() < 2:
		return 0.0
	
	var mean = _calculate_mean(values)
	var sum_squared_diff = 0.0
	
	for value in values:
		var diff = value - mean
		sum_squared_diff += diff * diff
	
	return sum_squared_diff / (values.size() - 1)

static func _calculate_standard_deviation(values: Array) -> float:
	return sqrt(_calculate_variance(values))

static func _calculate_skewness(values: Array) -> float:
	if values.size() < 3:
		return 0.0
	
	var mean = _calculate_mean(values)
	var std_dev = _calculate_standard_deviation(values)
	
	if std_dev == 0:
		return 0.0
	
	var sum_cubed = 0.0
	for value in values:
		var standardized = (value - mean) / std_dev
		sum_cubed += pow(standardized, 3)
	
	return sum_cubed / values.size()

static func _calculate_kurtosis(values: Array) -> float:
	if values.size() < 4:
		return 0.0
	
	var mean = _calculate_mean(values)
	var std_dev = _calculate_standard_deviation(values)
	
	if std_dev == 0:
		return 0.0
	
	var sum_fourth = 0.0
	for value in values:
		var standardized = (value - mean) / std_dev
		sum_fourth += pow(standardized, 4)
	
	return (sum_fourth / values.size()) - 3.0  # Excess kurtosis

static func _calculate_expected_value(probabilities: Dictionary) -> float:
	var expected = 0.0
	for damage in probabilities:
		expected += damage * probabilities[damage]
	return expected

static func _calculate_entropy(probabilities: Dictionary) -> float:
	var entropy = 0.0
	for prob in probabilities.values():
		if prob > 0:
			entropy -= prob * log(prob) / log(2)
	return entropy

static func _identify_damage_thresholds(cumulative: Dictionary) -> Dictionary:
	var thresholds = {}
	
	# Find damage values at key percentiles
	var target_percentiles = [0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 0.99]
	
	for percentile in target_percentiles:
		for damage in cumulative:
			if cumulative[damage] >= percentile:
				thresholds[percentile] = damage
				break
	
	return thresholds

static func _calculate_attacker_cost(attackers: Array) -> int:
	var total_cost = 0
	
	for attacker_config in attackers:
		var unit_id = attacker_config.get("unit_id", "")
		if GameState:
			var unit = GameState.get_unit(unit_id)
			total_cost += unit.get("meta", {}).get("points", 0)
	
	return total_cost

static func _calculate_consistency_score(result: Mathhammer.SimulationResult) -> float:
	# Consistency = 1 - (standard deviation / mean)
	# Higher values indicate more consistent results
	
	if result.detailed_trials.is_empty():
		return 0.0
	
	var damage_values = result.detailed_trials.map(func(trial): return trial.damage)
	var mean_damage = _calculate_mean(damage_values)
	var std_dev = _calculate_standard_deviation(damage_values)
	
	if mean_damage == 0:
		return 1.0 if std_dev == 0 else 0.0
	
	var coefficient_of_variation = std_dev / mean_damage
	return max(0.0, 1.0 - coefficient_of_variation)

static func _calculate_reliability_score(result: Mathhammer.SimulationResult) -> float:
	# Reliability = probability of achieving at least mean damage
	if result.detailed_trials.is_empty():
		return 0.0
	
	var damage_values = result.detailed_trials.map(func(trial): return trial.damage)
	var mean_damage = _calculate_mean(damage_values)
	
	var count_above_mean = 0
	for damage in damage_values:
		if damage >= mean_damage:
			count_above_mean += 1
	
	return float(count_above_mean) / result.trials_run

static func _calculate_turns_to_kill(result: Mathhammer.SimulationResult, config: Dictionary) -> float:
	# Estimate turns needed to kill target based on average damage
	var avg_damage = result.get_average_damage()
	
	if avg_damage <= 0:
		return float("inf")
	
	# Get defender total wounds
	var defender_config = config.get("defender", {})
	var defender_wounds = _get_defender_total_wounds(defender_config)
	
	return ceil(defender_wounds / avg_damage) if defender_wounds > 0 else 1.0

static func _get_defender_total_wounds(defender_config: Dictionary) -> int:
	var unit_id = defender_config.get("unit_id", "")
	if unit_id == "" or not GameState:
		return 1
	
	var unit = GameState.get_unit(unit_id)
	var total_wounds = 0
	
	for model in unit.get("models", []):
		total_wounds += model.get("wounds", 1)
	
	return total_wounds

static func _estimate_p_value(t_statistic: float) -> float:
	# Rough p-value estimation for t-statistic
	# This is a simplified approximation
	var abs_t = abs(t_statistic)
	
	if abs_t > 4.0:
		return 0.0001
	elif abs_t > 3.0:
		return 0.01
	elif abs_t > 2.0:
		return 0.05
	elif abs_t > 1.0:
		return 0.2
	else:
		return 0.5