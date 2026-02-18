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
	var trial_board = _create_trial_board_state(attackers, defender, rule_toggles, phase)
	
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

			var combat_result: Dictionary
			if phase == "fight" or phase == "melee":
				var melee_action = _build_melee_action(single_weapon_config, defender, rule_toggles, trial_board)
				combat_result = RulesEngine.resolve_melee_attacks(melee_action, trial_board, rng)
			else:
				var shoot_action = _build_shoot_action(single_weapon_config, defender, rule_toggles, trial_board)
				combat_result = RulesEngine.resolve_shoot(shoot_action, trial_board, rng)

			if combat_result.success:
				# Extract combat statistics (pass trial_board for wound delta calculation)
				var damage_dealt = _extract_damage_from_result(combat_result, trial_board)
				trial_result.damage += damage_dealt
				trial_result.models_killed += _count_models_killed_from_diffs(combat_result.diffs)
				trial_result.weapon_breakdown[weapon_id].damage += damage_dealt

				# Extract dice statistics for detailed breakdown
				# Handle both shooting and melee dice context names
				for dice_roll in combat_result.dice:
					match dice_roll.context:
						"to_hit", "hit_roll_melee", "auto_hit_melee", "auto_hit":
							trial_result.hits += dice_roll.get("successes", dice_roll.get("total_attacks", 0))
							var roll_count = dice_roll.get("rolls_raw", []).size()
							if dice_roll.context in ["auto_hit_melee", "auto_hit"]:
								roll_count = dice_roll.get("total_attacks", 0)
							trial_result.attacks_made += roll_count
							trial_result.weapon_breakdown[weapon_id].attacks_made += roll_count
							trial_result.weapon_breakdown[weapon_id].hits += dice_roll.get("successes", dice_roll.get("total_attacks", 0))
						"to_wound", "wound_roll_melee":
							trial_result.wounds += dice_roll.successes
							trial_result.weapon_breakdown[weapon_id].wounds += dice_roll.successes
						"save", "save_roll_melee":
							trial_result.saves_failed += dice_roll.get("fails", 0)
							trial_result.weapon_breakdown[weapon_id].saves_failed += dice_roll.get("fails", 0)

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
			var effective_attacks = base_attacks

			# Rapid Fire X: adds +X attacks per model at half range (not double)
			if rule_toggles.get("rapid_fire", false):
				var rf_value = RulesEngine.get_rapid_fire_value(weapon_id, board)
				var rf_bonus = rf_value * model_ids.size()
				effective_attacks += rf_bonus
				if rf_bonus > 0:
					print("Mathhammer: Rapid Fire %d on %s — +%d attacks (%d models × RF%d), total: %d" % [rf_value, weapon_id, rf_bonus, model_ids.size(), rf_value, effective_attacks])

			# BLAST KEYWORD (T3-22): Auto-calculate Blast bonus from defender model count
			# Per 10e rules: +1 attack per 5 models in target unit; minimum 3 attacks vs 6+ model units
			if RulesEngine.is_blast_weapon(weapon_id, board):
				var target_unit = board.get("units", {}).get(target_unit_id, {})
				if not target_unit.is_empty():
					var blast_bonus = RulesEngine.calculate_blast_bonus(weapon_id, target_unit, board)
					effective_attacks += blast_bonus
					# Enforce minimum 3 attacks against 6+ model units
					var blast_min = RulesEngine.calculate_blast_minimum(weapon_id, effective_attacks, target_unit, board)
					if blast_min > effective_attacks:
						effective_attacks = blast_min
					var model_count = RulesEngine.count_alive_models(target_unit)
					print("Mathhammer: Blast on %s — +%d bonus attacks (%d defender models), effective min: %d, total: %d" % [weapon_id, blast_bonus, model_count, blast_min, effective_attacks])

			assignment["attacks_override"] = effective_attacks

			# Apply Torrent toggle (auto-hit, bypasses hit rolls)
			if rule_toggles.get("torrent", false):
				assignment["torrent"] = true
				print("Mathhammer: Applied Torrent to %s — all attacks auto-hit" % weapon_id)

			# Apply rule toggles that affect wound rolls
			if rule_toggles.get("twin_linked", false):
				assignment["twin_linked"] = true

			# Build modifiers dict for hit and wound re-rolls from rule toggles
			var hit_mods = {}
			var wound_mods = {}

			# Hit re-roll toggles
			if rule_toggles.get("reroll_hits_ones", false):
				hit_mods["reroll_ones"] = true
			if rule_toggles.get("reroll_hits_failed", false):
				hit_mods["reroll_failed"] = true

			# Wound re-roll toggles
			if rule_toggles.get("reroll_wounds_ones", false):
				wound_mods["reroll_ones"] = true
			if rule_toggles.get("reroll_wounds_failed", false):
				wound_mods["reroll_failed"] = true

			if not hit_mods.is_empty() or not wound_mods.is_empty():
				assignment["modifiers"] = {}
				if not hit_mods.is_empty():
					assignment["modifiers"]["hit"] = hit_mods
				if not wound_mods.is_empty():
					assignment["modifiers"]["wound"] = wound_mods

			assignments.append(assignment)
	
	return {
		"type": "SHOOT",
		"actor_unit_id": unit_id,
		"payload": {
			"assignments": assignments
		}
	}

# Build melee action for RulesEngine integration
static func _build_melee_action(attacker_config: Dictionary, defender: Dictionary, rule_toggles: Dictionary, board: Dictionary) -> Dictionary:
	var unit_id = attacker_config.get("unit_id", "")
	var target_unit_id = defender.get("unit_id", "")
	var weapons = attacker_config.get("weapons", [])

	var assignments = []

	# Create melee assignments matching FightPhase confirmed_attacks format
	for weapon_config in weapons:
		var weapon_id = weapon_config.get("weapon_id", "")
		var model_ids = weapon_config.get("model_ids", [])
		var base_attacks = weapon_config.get("attacks", 1)

		if weapon_id != "" and not model_ids.is_empty():
			var assignment = {
				"attacker": unit_id,
				"target": target_unit_id,
				"weapon": weapon_id,
				"models": model_ids
			}

			# Apply rule toggles that affect wound rolls
			if rule_toggles.get("twin_linked", false):
				assignment["twin_linked"] = true

			# Build modifiers dict for hit and wound re-rolls from rule toggles
			var hit_mods = {}
			var wound_mods = {}

			# Hit re-roll toggles
			if rule_toggles.get("reroll_hits_ones", false):
				hit_mods["reroll_ones"] = true
			if rule_toggles.get("reroll_hits_failed", false):
				hit_mods["reroll_failed"] = true

			# Wound re-roll toggles
			if rule_toggles.get("reroll_wounds_ones", false):
				wound_mods["reroll_ones"] = true
			if rule_toggles.get("reroll_wounds_failed", false):
				wound_mods["reroll_failed"] = true

			if not hit_mods.is_empty() or not wound_mods.is_empty():
				assignment["modifiers"] = {}
				if not hit_mods.is_empty():
					assignment["modifiers"]["hit"] = hit_mods
				if not wound_mods.is_empty():
					assignment["modifiers"]["wound"] = wound_mods

			assignments.append(assignment)

	return {
		"type": "FIGHT",
		"actor_unit_id": unit_id,
		"payload": {
			"assignments": assignments
		}
	}

# Create a mutable board state for trial simulation
static func _create_trial_board_state(attackers: Array, defender: Dictionary, rule_toggles: Dictionary = {}, phase: String = "shooting") -> Dictionary:
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

			# Apply custom defender stat overrides from UI panel
			var overrides = defender.get("overrides", {})
			if not overrides.is_empty():
				fresh_defender = _apply_defender_overrides(fresh_defender, overrides, defender_unit_id)

			for model in fresh_defender.get("models", []):
				model["alive"] = true
				model["current_wounds"] = model.get("wounds", 1)

			# Apply Feel No Pain from rule toggles to defender stats
			# FNP toggles override any existing FNP on the unit (use best value toggled)
			# Custom override FNP takes priority over toggle FNP
			var fnp_value = _get_fnp_from_toggles(rule_toggles)
			var override_fnp = overrides.get("fnp", 0)
			if override_fnp > 0:
				fnp_value = override_fnp  # Custom override wins
			if fnp_value > 0:
				if not fresh_defender.has("meta"):
					fresh_defender["meta"] = {}
				if not fresh_defender["meta"].has("stats"):
					fresh_defender["meta"]["stats"] = {}
				fresh_defender["meta"]["stats"]["fnp"] = fnp_value
				print("Mathhammer: Applied FNP %d+ to defender %s" % [fnp_value, defender_unit_id])

			# Apply invulnerable save from rule toggles to defender models
			# Invuln is set per-model since RulesEngine reads model.get("invuln", 0)
			# Custom override invuln takes priority over toggle invuln
			var invuln_value = _get_invuln_from_toggles(rule_toggles)
			var override_invuln = overrides.get("invuln", 0)
			if override_invuln > 0:
				invuln_value = override_invuln  # Custom override wins
			if invuln_value > 0:
				for model in fresh_defender.get("models", []):
					var existing_invuln = model.get("invuln", 0)
					if existing_invuln == 0 or invuln_value < existing_invuln:
						model["invuln"] = invuln_value
				print("Mathhammer: Applied invulnerable save %d+ to defender %s" % [invuln_value, defender_unit_id])

			trial_board.units[defender_unit_id] = fresh_defender

	# ANTI-[KEYWORD] X+ (T2-13): Inject anti-keyword text into attacker weapon special_rules
	# so RulesEngine's get_anti_keyword_data() / get_critical_wound_threshold() picks it up.
	# Anti-keyword lowers the critical wound threshold (e.g., Anti-Infantry 4+ = crits on wound 4+).
	var anti_keyword_texts = _get_anti_keyword_texts_from_toggles(rule_toggles)
	if not anti_keyword_texts.is_empty():
		for attacker_config in attackers:
			var unit_id = attacker_config.get("unit_id", "")
			if trial_board.units.has(unit_id):
				var unit = trial_board.units[unit_id]
				var weapons = unit.get("meta", {}).get("weapons", [])
				for weapon in weapons:
					var existing_rules = weapon.get("special_rules", "")
					for anti_text in anti_keyword_texts:
						# Only append if not already present in the weapon's special_rules
						if anti_text.to_lower() not in existing_rules.to_lower():
							if existing_rules != "":
								existing_rules += ", "
							existing_rules += anti_text
					weapon["special_rules"] = existing_rules
				print("Mathhammer: Injected anti-keyword rules [%s] into attacker %s weapons" % [", ".join(anti_keyword_texts), unit_id])

	# For melee simulations, ensure all models have positions within engagement range
	# so the eligibility check in resolve_melee_attacks passes
	if phase == "fight" or phase == "melee":
		_place_models_in_engagement_range(trial_board, attackers, defender)
		# Apply charged_this_turn flag if lance toggle is active
		if rule_toggles.get("lance_charged", false):
			for attacker_config in attackers:
				var unit_id = attacker_config.get("unit_id", "")
				if trial_board.units.has(unit_id):
					if not trial_board.units[unit_id].has("flags"):
						trial_board.units[unit_id]["flags"] = {}
					trial_board.units[unit_id]["flags"]["charged_this_turn"] = true

	return trial_board

# Place all attacker and defender models in engagement range for melee simulation
# This ensures the eligibility check in resolve_melee_attacks passes for all alive models
static func _place_models_in_engagement_range(trial_board: Dictionary, attackers: Array, defender: Dictionary) -> void:
	var defender_unit_id = defender.get("unit_id", "")
	var defender_unit = trial_board.units.get(defender_unit_id, {})
	var defender_models = defender_unit.get("models", [])

	# Place defender models at origin
	for i in range(defender_models.size()):
		defender_models[i]["position"] = {"x": float(i) * 0.5, "y": 0.0}

	# Place attacker models adjacent to defender (within engagement range = 1")
	for attacker_config in attackers:
		var unit_id = attacker_config.get("unit_id", "")
		var attacker_unit = trial_board.units.get(unit_id, {})
		var attacker_models = attacker_unit.get("models", [])
		for i in range(attacker_models.size()):
			# Place within 0.5" of corresponding defender model (well within ER)
			attacker_models[i]["position"] = {"x": float(i) * 0.5, "y": 0.5}

# Extract the best (lowest) FNP value from active rule toggles
static func _get_fnp_from_toggles(rule_toggles: Dictionary) -> int:
	var fnp_value = 0
	if rule_toggles.get("feel_no_pain_4", false):
		fnp_value = 4
	elif rule_toggles.get("feel_no_pain_5", false):
		fnp_value = 5
	elif rule_toggles.get("feel_no_pain_6", false):
		fnp_value = 6
	return fnp_value

# Extract the best (lowest) invulnerable save value from active rule toggles
static func _get_invuln_from_toggles(rule_toggles: Dictionary) -> int:
	var invuln_value = 0
	if rule_toggles.get("invuln_2", false):
		invuln_value = 2
	elif rule_toggles.get("invuln_3", false):
		invuln_value = 3
	elif rule_toggles.get("invuln_4", false):
		invuln_value = 4
	elif rule_toggles.get("invuln_5", false):
		invuln_value = 5
	elif rule_toggles.get("invuln_6", false):
		invuln_value = 6
	return invuln_value

# Extract anti-keyword text strings from active rule toggles (T2-13)
# Returns an array of strings like ["Anti-Infantry 4+", "Anti-Vehicle 4+"]
# These get injected into weapon special_rules so RulesEngine picks them up
static func _get_anti_keyword_texts_from_toggles(rule_toggles: Dictionary) -> Array:
	var texts = []
	if rule_toggles.get("anti_infantry_4", false):
		texts.append("Anti-Infantry 4+")
	if rule_toggles.get("anti_vehicle_4", false):
		texts.append("Anti-Vehicle 4+")
	if rule_toggles.get("anti_monster_4", false):
		texts.append("Anti-Monster 4+")
	return texts

# Apply custom defender stat overrides to the defender unit
# Modifies toughness, save, wounds, model count based on user input
static func _apply_defender_overrides(defender: Dictionary, overrides: Dictionary, defender_id: String) -> Dictionary:
	print("Mathhammer: Applying defender overrides for %s: %s" % [defender_id, str(overrides)])

	# Ensure meta.stats exists
	if not defender.has("meta"):
		defender["meta"] = {}
	if not defender["meta"].has("stats"):
		defender["meta"]["stats"] = {}

	# Override Toughness
	if overrides.has("toughness") and overrides.toughness > 0:
		defender["meta"]["stats"]["toughness"] = overrides.toughness
		print("Mathhammer: Override toughness = %d for %s" % [overrides.toughness, defender_id])

	# Override Armor Save
	if overrides.has("save") and overrides.save > 0:
		defender["meta"]["stats"]["save"] = overrides.save
		print("Mathhammer: Override save = %d+ for %s" % [overrides.save, defender_id])

	# Override Wounds per model
	if overrides.has("wounds") and overrides.wounds > 0:
		for model in defender.get("models", []):
			model["wounds"] = overrides.wounds
			model["current_wounds"] = overrides.wounds
		print("Mathhammer: Override wounds = %d per model for %s" % [overrides.wounds, defender_id])

	# Override Model Count — add or remove models to match desired count
	if overrides.has("model_count") and overrides.model_count > 0:
		var models = defender.get("models", [])
		var target_count = overrides.model_count
		var current_count = models.size()

		if target_count > current_count and current_count > 0:
			# Add models by duplicating the first model template
			var template = models[0].duplicate(true)
			for i in range(target_count - current_count):
				var new_model = template.duplicate(true)
				new_model["id"] = "m%d" % (current_count + i)
				models.append(new_model)
			print("Mathhammer: Added %d models (now %d) for %s" % [target_count - current_count, models.size(), defender_id])
		elif target_count < current_count:
			# Remove excess models from the end
			models.resize(target_count)
			print("Mathhammer: Removed %d models (now %d) for %s" % [current_count - target_count, models.size(), defender_id])

	return defender

# Extract total damage dealt from combat result by computing wound deltas
# Requires trial_board (pre-diff state) so we can compare old wounds vs new wounds
# Tracks per-path wound values so multiple diffs on the same model (e.g. devastating wounds
# then failed save damage) don't double-count against the trial_board's original wounds.
static func _extract_damage_from_result(combat_result: Dictionary, trial_board: Dictionary) -> int:
	var damage = 0
	var last_wounds_by_path: Dictionary = {}  # path -> last known wounds value
	for diff in combat_result.get("diffs", []):
		if diff.get("op", "") == "set" and diff.get("path", "").ends_with(".current_wounds"):
			var path = diff.get("path", "")
			var new_wounds = diff.get("value", 0)
			# Use last diff value for this path if available, otherwise read from trial board
			var old_wounds: int
			if last_wounds_by_path.has(path):
				old_wounds = last_wounds_by_path[path]
			else:
				old_wounds = _get_wounds_from_board_by_path(trial_board, path)
			damage += max(0, old_wounds - new_wounds)
			last_wounds_by_path[path] = new_wounds
	return damage

# Look up a model's current_wounds from the trial board using a diff path
# Path format: "units.<unit_id>.models.<index>.current_wounds"
static func _get_wounds_from_board_by_path(board: Dictionary, path: String) -> int:
	var parts = path.split(".")
	# Expected: ["units", "<unit_id>", "models", "<index>", "current_wounds"]
	if parts.size() < 5:
		return 0
	var unit_id = parts[1]
	var model_index_str = parts[3]
	if not model_index_str.is_valid_int():
		return 0
	var model_index = int(model_index_str)
	var unit = board.get("units", {}).get(unit_id, {})
	var models = unit.get("models", [])
	if model_index < models.size():
		return models[model_index].get("current_wounds", 0)
	return 0

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
	var overrides = unit_config.get("overrides", {})
	if overrides.has("model_count") and overrides.model_count > 0:
		return overrides.model_count
	if GameState:
		var unit_data = GameState.get_unit(unit_config.get("unit_id", ""))
		return unit_data.get("models", []).size()
	return 0

static func _get_total_wounds(unit_config: Dictionary) -> int:
	var overrides = unit_config.get("overrides", {})
	if not overrides.is_empty():
		var model_count = _get_total_models(unit_config)
		var wounds_per_model = overrides.get("wounds", 0)
		if wounds_per_model > 0:
			return model_count * wounds_per_model
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