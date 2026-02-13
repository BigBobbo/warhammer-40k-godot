extends Node
const GameStateData = preload("res://autoloads/GameState.gd")

# RulesEngine - Central authority for game rules validation and resolution
# Handles shooting mechanics, dice rolling, damage application following 10e rules
# This is an autoload singleton, accessed globally as RulesEngine

# Weapon profile structure (will be expanded later)
const WEAPON_PROFILES = {
	"bolt_rifle": {
		"name": "Bolt Rifle",
		"range": 30,
		"attacks": 2,
		"bs": 3,
		"strength": 4,
		"ap": 1,
		"damage": 1,
		"keywords": ["RAPID FIRE 1"]  # Rapid Fire 1 - +1 attack at half range
	},
	"plasma_pistol": {
		"name": "Plasma Pistol", 
		"range": 120,  # Extended range for debugging
		"attacks": 1,
		"bs": 3,
		"strength": 7,
		"ap": 3,
		"damage": 1,
		"keywords": ["PISTOL"]
	},
	"slugga": {
		"name": "Slugga",
		"range": 12,
		"attacks": 1,
		"bs": 5,
		"strength": 4,
		"ap": 0,
		"damage": 1,
		"keywords": ["PISTOL", "ASSAULT"]  # Slugga has both keywords in 10e
	},
	"grot_blasta": {
		"name": "Grot Blasta",
		"range": 12,
		"attacks": 1,
		"bs": 4,
		"strength": 3,
		"ap": 0,
		"damage": 1,
		"keywords": []
	},
	"shoota": {
		"name": "Shoota",
		"range": 18,
		"attacks": 2,
		"bs": 5,
		"strength": 4,
		"ap": 0,
		"damage": 1,
		"keywords": ["ASSAULT"]  # Ork shoota has Assault keyword
	},
	"heavy_bolter": {
		"name": "Heavy Bolter",
		"range": 36,
		"attacks": 3,
		"bs": 3,
		"strength": 5,
		"ap": 1,
		"damage": 2,
		"keywords": ["HEAVY"]  # Heavy keyword - +1 to hit if stationary
	},
	"lascannon": {
		"name": "Lascannon",
		"range": 48,
		"attacks": 1,
		"bs": 3,
		"strength": 12,
		"ap": 3,
		"damage": 6,
		"keywords": ["HEAVY"]  # Heavy keyword - +1 to hit if stationary
	},
	# TEST WEAPON: Lethal Hits keyword for PRP-010 testing
	"lethal_bolter": {
		"name": "Lethal Bolter (Test)",
		"range": 24,
		"attacks": 4,
		"bs": 3,
		"strength": 4,
		"ap": 1,
		"damage": 1,
		"keywords": ["LETHAL HITS"]  # Unmodified 6s to hit auto-wound
	},
	# TEST WEAPON: Sustained Hits keyword for PRP-011 testing
	"sustained_bolter": {
		"name": "Sustained Bolter (Test)",
		"range": 24,
		"attacks": 4,
		"bs": 3,
		"strength": 4,
		"ap": 1,
		"damage": 1,
		"keywords": ["SUSTAINED HITS 1"]  # +1 hit per critical hit
	},
	# TEST WEAPON: Sustained Hits 2 for testing higher values
	"sustained_2_bolter": {
		"name": "Sustained Hits 2 Bolter (Test)",
		"range": 24,
		"attacks": 4,
		"bs": 3,
		"strength": 4,
		"ap": 1,
		"damage": 1,
		"keywords": ["SUSTAINED HITS 2"]  # +2 hits per critical hit
	},
	# TEST WEAPON: Sustained Hits D3 for testing variable values
	"sustained_d3_bolter": {
		"name": "Sustained Hits D3 Bolter (Test)",
		"range": 24,
		"attacks": 3,
		"bs": 3,
		"strength": 4,
		"ap": 1,
		"damage": 1,
		"keywords": ["SUSTAINED HITS D3"]  # Roll D3 per critical hit
	},
	# TEST WEAPON: Both Lethal Hits AND Sustained Hits for interaction testing
	"lethal_sustained_bolter": {
		"name": "Lethal + Sustained Bolter (Test)",
		"range": 24,
		"attacks": 4,
		"bs": 3,
		"strength": 4,
		"ap": 1,
		"damage": 1,
		"keywords": ["LETHAL HITS", "SUSTAINED HITS 1"]  # Crits auto-wound AND generate +1 hit
	},
	# TEST WEAPON: Devastating Wounds for PRP-012 testing
	"devastating_bolter": {
		"name": "Devastating Bolter (Test)",
		"range": 24,
		"attacks": 4,
		"bs": 3,
		"strength": 4,
		"ap": 1,
		"damage": 2,  # Higher damage to see DW effect clearly
		"keywords": ["DEVASTATING WOUNDS"]  # Unmodified 6s to wound bypass saves
	},
	# TEST WEAPON: High damage Devastating Wounds (simulates melta/lascannon)
	"devastating_melta": {
		"name": "Devastating Melta (Test)",
		"range": 12,
		"attacks": 1,
		"bs": 3,
		"strength": 9,
		"ap": 4,
		"damage": 6,  # High damage like melta
		"keywords": ["DEVASTATING WOUNDS"]  # 6 unsaveable damage on crit wound
	},
	# TEST WEAPON: Lethal Hits + Devastating Wounds combo
	"lethal_devastating_bolter": {
		"name": "Lethal + Devastating (Test)",
		"range": 24,
		"attacks": 4,
		"bs": 3,
		"strength": 4,
		"ap": 1,
		"damage": 2,
		"keywords": ["LETHAL HITS", "DEVASTATING WOUNDS"]  # Crits auto-wound, crit wounds bypass saves
	},
	# TEST WEAPON: Blast weapon for PRP-013 testing (frag grenade)
	"frag_grenade": {
		"name": "Frag Grenade",
		"range": 6,
		"attacks": 1,  # Low base attacks to test minimum 3 rule
		"bs": 3,
		"strength": 4,
		"ap": 0,
		"damage": 1,
		"keywords": ["BLAST"]  # +1 attack per 5 models, min 3 vs 6+ models
	},
	# TEST WEAPON: Frag missile for Blast testing (higher damage)
	"frag_missile": {
		"name": "Frag Missile",
		"range": 48,
		"attacks": 2,
		"bs": 3,
		"strength": 4,
		"ap": 0,
		"damage": 1,
		"keywords": ["BLAST", "HEAVY"]  # Blast + Heavy combo
	},
	# TEST WEAPON: Battle cannon for Blast testing (high damage Blast)
	"battle_cannon": {
		"name": "Battle Cannon",
		"range": 48,
		"attacks": 1,
		"bs": 3,
		"strength": 9,
		"ap": 2,
		"damage": 3,
		"keywords": ["BLAST"]  # Large Blast weapon
	},
	# TEST WEAPON: Blast + Devastating Wounds combo (e.g., psychic power)
	"blast_devastating": {
		"name": "Blast + Devastating (Test)",
		"range": 18,
		"attacks": 3,
		"bs": 3,
		"strength": 5,
		"ap": 1,
		"damage": 2,
		"keywords": ["BLAST", "DEVASTATING WOUNDS"]  # Blast + DW combo
	},
	# TORRENT WEAPONS (PRP-014) - Automatically hit without hit roll
	# TEST WEAPON: Basic Flamer for Torrent testing
	"flamer": {
		"name": "Flamer",
		"range": 12,
		"attacks": 6,  # D6 in real 40k but fixed for testing
		"bs": 4,  # Irrelevant - Torrent auto-hits
		"strength": 4,
		"ap": 0,
		"damage": 1,
		"keywords": ["TORRENT", "IGNORES COVER"]  # Standard flamer keywords
	},
	# TEST WEAPON: Heavy Flamer (Torrent + Heavy)
	"heavy_flamer": {
		"name": "Heavy Flamer",
		"range": 12,
		"attacks": 6,  # D6 in real 40k but fixed for testing
		"bs": 4,  # Irrelevant - Torrent auto-hits (Heavy bonus also irrelevant)
		"strength": 5,
		"ap": 1,
		"damage": 1,
		"keywords": ["TORRENT", "HEAVY", "IGNORES COVER"]  # Heavy is irrelevant for Torrent
	},
	# TEST WEAPON: Torrent + Lethal Hits (edge case - Lethal Hits should NOT trigger)
	"torrent_lethal": {
		"name": "Torrent + Lethal (Test)",
		"range": 12,
		"attacks": 6,
		"bs": 4,
		"strength": 4,
		"ap": 0,
		"damage": 1,
		"keywords": ["TORRENT", "LETHAL HITS"]  # Lethal Hits won't trigger (no hit roll)
	},
	# TEST WEAPON: Torrent + Sustained Hits (edge case - Sustained Hits should NOT trigger)
	"torrent_sustained": {
		"name": "Torrent + Sustained (Test)",
		"range": 12,
		"attacks": 6,
		"bs": 4,
		"strength": 4,
		"ap": 0,
		"damage": 1,
		"keywords": ["TORRENT", "SUSTAINED HITS 1"]  # Sustained Hits won't trigger (no hit roll)
	},
	# TEST WEAPON: Torrent + Devastating Wounds (DW CAN trigger on wound roll)
	"torrent_devastating": {
		"name": "Torrent + DW (Test)",
		"range": 12,
		"attacks": 6,
		"bs": 4,
		"strength": 4,
		"ap": 0,
		"damage": 2,
		"keywords": ["TORRENT", "DEVASTATING WOUNDS"]  # DW can trigger on wound rolls
	},
	# TEST WEAPON: Torrent + Blast (rare combo)
	"torrent_blast": {
		"name": "Torrent + Blast (Test)",
		"range": 12,
		"attacks": 3,
		"bs": 4,
		"strength": 5,
		"ap": 1,
		"damage": 1,
		"keywords": ["TORRENT", "BLAST"]  # Blast bonus applies, then all auto-hit
	}
}

# Unit weapon loadouts (MVP - simplified)
const UNIT_WEAPONS = {
	"U_INTERCESSORS_A": {
		"m1": ["bolt_rifle"],
		"m2": ["bolt_rifle"],
		"m3": ["bolt_rifle"],
		"m4": ["bolt_rifle"],
		"m5": ["bolt_rifle", "plasma_pistol"]  # Sergeant
	},
	"U_TACTICAL_A": {
		"m1": ["bolt_rifle"],
		"m2": ["bolt_rifle"],
		"m3": ["bolt_rifle"],
		"m4": ["bolt_rifle"],
		"m5": ["bolt_rifle", "plasma_pistol"]  # Sergeant
	},
	"U_BOYZ_A": {
		"m1": ["slugga", "shoota"],  # Boyz have both slugga and shoota
		"m2": ["slugga", "shoota"],
		"m3": ["slugga", "shoota"],
		"m4": ["slugga", "shoota"],
		"m5": ["slugga", "shoota"],
		"m6": ["slugga", "shoota"],
		"m7": ["slugga", "shoota"],
		"m8": ["slugga", "shoota"],
		"m9": ["slugga", "shoota"],
		"m10": ["slugga", "shoota"]
	},
	"U_GRETCHIN_A": {
		"m1": ["grot_blasta"],
		"m2": ["grot_blasta"],
		"m3": ["grot_blasta"],
		"m4": ["grot_blasta"],
		"m5": ["grot_blasta"]
	}
}

# RNG Service for deterministic dice rolling
class RNGService:
	var rng: RandomNumberGenerator

	func _init(seed_value: int = -1):
		rng = RandomNumberGenerator.new()
		if seed_value >= 0:
			rng.seed = seed_value
		else:
			rng.randomize()

	func roll_d6(count: int) -> Array:
		var rolls = []
		for i in count:
			rolls.append(rng.randi_range(1, 6))
		return rolls

# ==========================================
# SHOOTING MODIFIERS (Phase 1 MVP)
# ==========================================

# Hit modifier flags (can be combined with bitwise OR)
enum HitModifier {
	NONE = 0,
	REROLL_ONES = 1,    # Re-roll 1s to hit
	PLUS_ONE = 2,       # +1 to hit
	MINUS_ONE = 4,      # -1 to hit (cover, moved, etc.)
}

# Apply hit modifiers to a single roll
# Returns the modified roll value and any re-roll that occurred
static func apply_hit_modifiers(roll: int, modifiers: int, rng: RNGService) -> Dictionary:
	var result = {
		"original_roll": roll,
		"modified_roll": roll,
		"rerolled": false,
		"reroll_value": 0,
		"modifier_applied": 0
	}

	# Step 1: Apply re-rolls FIRST (before modifiers per 10e rules)
	if (modifiers & HitModifier.REROLL_ONES) and roll == 1:
		var reroll_result = rng.roll_d6(1)[0]
		result.rerolled = true
		result.reroll_value = reroll_result
		result.modified_roll = reroll_result

	# Step 2: Then apply numeric modifiers (capped at net +1/-1)
	var net_modifier = 0
	if modifiers & HitModifier.PLUS_ONE:
		net_modifier += 1
	if modifiers & HitModifier.MINUS_ONE:
		net_modifier -= 1

	# Cap modifiers at +1/-1 maximum
	net_modifier = clamp(net_modifier, -1, 1)

	result.modifier_applied = net_modifier
	result.modified_roll += net_modifier

	return result

# Main shooting resolution entry point
static func resolve_shoot(action: Dictionary, board: Dictionary, rng_service: RNGService = null) -> Dictionary:
	if not rng_service:
		rng_service = RNGService.new()

	var result = {
		"success": true,
		"phase": "SHOOTING",
		"diffs": [],
		"dice": [],
		"log_text": ""
	}

	var actor_unit_id = action.get("actor_unit_id", "")
	var assignments = action.get("payload", {}).get("assignments", [])

	if assignments.is_empty():
		result.success = false
		result.log_text = "No weapon assignments provided"
		return result

	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})

	if actor_unit.is_empty():
		result.success = false
		result.log_text = "Actor unit not found"
		return result

	# Process each weapon assignment
	for assignment in assignments:
		var assignment_result = _resolve_assignment(assignment, actor_unit_id, board, rng_service)
		result.diffs.append_array(assignment_result.diffs)
		result.dice.append_array(assignment_result.dice)
		if assignment_result.log_text:
			result.log_text += assignment_result.log_text + "\n"

	return result

# Shooting resolution that stops before saves (for interactive save system)
static func resolve_shoot_until_wounds(action: Dictionary, board: Dictionary, rng_service: RNGService = null) -> Dictionary:
	if not rng_service:
		rng_service = RNGService.new()

	var result = {
		"success": true,
		"phase": "SHOOTING",
		"dice": [],
		"log_text": "",
		"save_data_list": []  # Array of save data for each assignment
	}

	var actor_unit_id = action.get("actor_unit_id", "")
	var assignments = action.get("payload", {}).get("assignments", [])

	if assignments.is_empty():
		result.success = false
		result.log_text = "No weapon assignments provided"
		return result

	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})

	if actor_unit.is_empty():
		result.success = false
		result.log_text = "Actor unit not found"
		return result

	# Process each weapon assignment up to wounds
	for assignment in assignments:
		var assignment_result = _resolve_assignment_until_wounds(assignment, actor_unit_id, board, rng_service)

		if assignment_result.has("dice"):
			result.dice.append_array(assignment_result.dice)

		if assignment_result.has("log_text") and assignment_result.log_text:
			result.log_text += assignment_result.log_text + "\n"

		# If wounds were caused, add save data
		if assignment_result.has("save_data") and assignment_result.save_data.get("success", false):
			result.save_data_list.append(assignment_result.save_data)

	return result

# Resolve assignment up to wound stage (stops before saves)
# SUSTAINED HITS (PRP-011): This function is modified to handle Sustained Hits
# BLAST (PRP-013): This function is modified to handle Blast keyword
static func _resolve_assignment_until_wounds(assignment: Dictionary, actor_unit_id: String, board: Dictionary, rng: RNGService) -> Dictionary:
	var result = {
		"dice": [],
		"log_text": ""
	}

	var model_ids = assignment.get("model_ids", [])
	var weapon_id = assignment.get("weapon_id", "")
	var target_unit_id = assignment.get("target_unit_id", "")

	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})
	var target_unit = units.get(target_unit_id, {})

	if target_unit.is_empty():
		result.log_text = "Target unit not found"
		return result

	# Get weapon profile
	var weapon_profile = get_weapon_profile(weapon_id, board)
	if weapon_profile.is_empty():
		result.log_text = "Unknown weapon: " + weapon_id
		return result

	# Calculate total attacks
	var attacks_per_model = weapon_profile.get("attacks", 1)

	# BLAST KEYWORD (PRP-013): Apply minimum attacks for Blast weapons vs 6+ model units
	var blast_minimum_applied = false
	var original_attacks_per_model = attacks_per_model
	var effective_attacks_per_model = calculate_blast_minimum(weapon_id, attacks_per_model, target_unit, board)
	if effective_attacks_per_model > attacks_per_model:
		blast_minimum_applied = true
		attacks_per_model = effective_attacks_per_model

	var base_attacks = model_ids.size() * attacks_per_model

	# RAPID FIRE KEYWORD: Check if weapon is Rapid Fire and models are in half range
	var rapid_fire_value = get_rapid_fire_value(weapon_id, board)
	var rapid_fire_attacks = 0
	var models_in_half_range = 0
	if rapid_fire_value > 0:
		models_in_half_range = count_models_in_half_range(actor_unit, target_unit, weapon_id, model_ids, board)
		rapid_fire_attacks = models_in_half_range * rapid_fire_value

	# BLAST KEYWORD (PRP-013): Add bonus attacks based on target unit size
	var blast_bonus_attacks = calculate_blast_bonus(weapon_id, target_unit, board)
	var target_model_count = count_alive_models(target_unit)

	var total_attacks = base_attacks + rapid_fire_attacks + blast_bonus_attacks
	if assignment.has("attacks_override") and assignment.attacks_override != null:
		total_attacks = assignment.attacks_override
		rapid_fire_attacks = 0  # Override disables the rapid fire bonus tracking
		blast_bonus_attacks = 0  # Override disables the blast bonus tracking

	# TORRENT KEYWORD (PRP-014): Check if weapon auto-hits (skip hit roll entirely)
	var is_torrent = is_torrent_weapon(weapon_id, board)

	# Variables that need to be declared for both paths
	var bs = weapon_profile.get("bs", 4)
	var hits = 0
	var critical_hits = 0  # Unmodified 6s that hit (never for Torrent)
	var regular_hits = 0   # Non-critical hits
	var hit_modifiers = HitModifier.NONE
	var heavy_bonus_applied = false
	var bgnt_penalty_applied = false
	var hit_rolls = []
	var modified_rolls = []
	var reroll_data = []
	var weapon_has_lethal_hits = false
	var sustained_data = {"value": 0, "is_dice": false}
	var sustained_result = {"bonus_hits": 0, "rolls": []}
	var sustained_bonus_hits = 0
	var total_hits_for_wounds = 0

	if is_torrent:
		# TORRENT: All attacks automatically hit - no roll needed
		# Since no hit roll is made:
		# - Lethal Hits cannot trigger (no critical hits)
		# - Sustained Hits cannot trigger (no critical hits)
		# - Hit modifiers are irrelevant (Heavy, cover, etc.)
		hits = total_attacks
		regular_hits = total_attacks  # All are "regular" hits - no crits possible
		critical_hits = 0  # Torrent weapons never roll to hit, so no crits
		total_hits_for_wounds = hits

		# Note: We still check if weapon HAS these keywords for UI display
		# but they won't have any effect since there's no hit roll
		weapon_has_lethal_hits = has_lethal_hits(weapon_id, board)
		sustained_data = get_sustained_hits_value(weapon_id, board)

		result.dice.append({
			"context": "auto_hit",  # Special context for Torrent
			"torrent_weapon": true,
			"total_attacks": total_attacks,
			"successes": hits,
			"message": "Torrent: %d automatic hits" % hits,
			# Still track these for completeness, but they won't trigger
			"lethal_hits_weapon": weapon_has_lethal_hits,
			"sustained_hits_weapon": sustained_data.value > 0,
			"sustained_hits_note": "N/A - no hit roll for Torrent",
			# BLAST (PRP-013)
			"blast_weapon": is_blast_weapon(weapon_id, board),
			"blast_bonus_attacks": blast_bonus_attacks,
			"blast_minimum_applied": blast_minimum_applied,
			"blast_original_attacks": original_attacks_per_model,
			"target_model_count": target_model_count,
			"base_attacks": base_attacks,
			"rapid_fire_bonus": rapid_fire_attacks,
			"rapid_fire_value": rapid_fire_value,
			"models_in_half_range": models_in_half_range
		})
	else:
		# Normal hit roll path (non-Torrent weapons)
		# Get hit modifiers
		if assignment.has("modifiers") and assignment.modifiers.has("hit"):
			var hit_mods = assignment.modifiers.hit
			if hit_mods.get("reroll_ones", false):
				hit_modifiers |= HitModifier.REROLL_ONES
			if hit_mods.get("plus_one", false):
				hit_modifiers |= HitModifier.PLUS_ONE
			if hit_mods.get("minus_one", false):
				hit_modifiers |= HitModifier.MINUS_ONE

		# HEAVY KEYWORD: Check if weapon is Heavy and unit remained stationary
		if is_heavy_weapon(weapon_id, board):
			var remained_stationary = actor_unit.get("flags", {}).get("remained_stationary", false)
			if remained_stationary:
				hit_modifiers |= HitModifier.PLUS_ONE
				heavy_bonus_applied = true

		# BIG GUNS NEVER TIRE: Apply -1 to hit for non-Pistol weapons when Monster/Vehicle is in Engagement Range
		if big_guns_never_tire_applies(actor_unit):
			# Only apply penalty if this is NOT a Pistol weapon
			if not is_pistol_weapon(weapon_id, board):
				hit_modifiers |= HitModifier.MINUS_ONE
				bgnt_penalty_applied = true

		# Roll to hit - CRITICAL HIT TRACKING (PRP-031)
		hit_rolls = rng.roll_d6(total_attacks)

		for i in range(hit_rolls.size()):
			var roll = hit_rolls[i]
			var unmodified_roll = roll  # Store BEFORE any modifications
			var modifier_result = apply_hit_modifiers(roll, hit_modifiers, rng)
			var final_roll = modifier_result.modified_roll
			modified_rolls.append(final_roll)

			# Track reroll - if rerolled, the unmodified roll is the NEW roll
			if modifier_result.rerolled:
				reroll_data.append({
					"original": modifier_result.original_roll,
					"rerolled_to": modifier_result.reroll_value
				})
				unmodified_roll = modifier_result.reroll_value  # Use new roll for crit check

			# 10e rules: Unmodified 1 always misses, unmodified 6 always hits
			if unmodified_roll == 1:
				pass  # Auto-miss regardless of modifiers
			elif unmodified_roll == 6 or final_roll >= bs:
				hits += 1
				# Critical hit = unmodified 6 (BEFORE modifiers)
				if unmodified_roll == 6:
					critical_hits += 1
				else:
					regular_hits += 1

		# Check for Lethal Hits keyword
		weapon_has_lethal_hits = has_lethal_hits(weapon_id, board)

		# SUSTAINED HITS (PRP-011): Generate bonus hits on critical hits
		sustained_data = get_sustained_hits_value(weapon_id, board)
		sustained_result = roll_sustained_hits(critical_hits, sustained_data, rng)
		sustained_bonus_hits = sustained_result.bonus_hits

		# Total hits for wound rolls = regular hits + bonus hits from Sustained
		# (Critical hits with Lethal Hits auto-wound, but their Sustained bonus hits still roll)
		total_hits_for_wounds = hits + sustained_bonus_hits

		result.dice.append({
			"context": "to_hit",
			"threshold": str(bs) + "+",
			"rolls_raw": hit_rolls,
			"rolls_modified": modified_rolls,
			"rerolls": reroll_data,
			"modifiers_applied": hit_modifiers,
			"heavy_bonus_applied": heavy_bonus_applied,
			"bgnt_penalty_applied": bgnt_penalty_applied,
			"rapid_fire_bonus": rapid_fire_attacks,
			"rapid_fire_value": rapid_fire_value,
			"models_in_half_range": models_in_half_range,
			"base_attacks": base_attacks,
			"successes": hits,
			# CRITICAL HIT TRACKING (PRP-031)
			"critical_hits": critical_hits,
			"regular_hits": regular_hits,
			"lethal_hits_weapon": weapon_has_lethal_hits,
			# SUSTAINED HITS (PRP-011)
			"sustained_hits_weapon": sustained_data.value > 0,
			"sustained_hits_value": sustained_data.value,
			"sustained_hits_is_dice": sustained_data.is_dice,
			"sustained_bonus_hits": sustained_bonus_hits,
			"sustained_rolls": sustained_result.rolls,
			"total_hits_for_wounds": total_hits_for_wounds,
			# BLAST (PRP-013)
			"blast_weapon": is_blast_weapon(weapon_id, board),
			"blast_bonus_attacks": blast_bonus_attacks,
			"blast_minimum_applied": blast_minimum_applied,
			"blast_original_attacks": original_attacks_per_model,
			"target_model_count": target_model_count
		})

	if hits == 0 and sustained_bonus_hits == 0:
		result.log_text = "%s → %s: No hits" % [actor_unit.get("meta", {}).get("name", actor_unit_id), target_unit.get("meta", {}).get("name", target_unit_id)]
		return result

	# Roll to wound - LETHAL HITS (PRP-010) + SUSTAINED HITS (PRP-011) + DEVASTATING WOUNDS (PRP-012)
	# TORRENT (PRP-014): Torrent weapons skip hit roll but still roll to wound normally
	var strength = weapon_profile.get("strength", 4)
	var toughness = target_unit.get("meta", {}).get("stats", {}).get("toughness", 4)
	var wound_threshold = _calculate_wound_threshold(strength, toughness)

	# DEVASTATING WOUNDS (PRP-012): Check if weapon has Devastating Wounds
	var weapon_has_devastating_wounds = has_devastating_wounds(weapon_id, board)

	# LETHAL HITS + SUSTAINED HITS + DEVASTATING WOUNDS interaction:
	# - Critical hits with Lethal Hits auto-wound (no roll needed) - NOT for Torrent (no crits)
	# - Bonus hits from Sustained Hits always roll to wound (even if weapon has Lethal Hits) - NOT for Torrent (no crits)
	# - Regular (non-critical) hits always roll to wound
	# - Critical wounds (unmodified 6s to wound) with Devastating Wounds bypass saves - CAN happen for Torrent
	var auto_wounds = 0  # From Lethal Hits (never for Torrent)
	var wounds_from_rolls = 0
	var wound_rolls = []
	var critical_wound_count = 0  # DEVASTATING WOUNDS: Unmodified 6s to wound (CAN trigger for Torrent)
	var regular_wound_count = 0   # DEVASTATING WOUNDS: Non-critical wounds

	# TORRENT (PRP-014): Since Torrent has no crits, Lethal Hits never triggers
	# All hits must roll to wound normally
	if weapon_has_lethal_hits and not is_torrent:
		# Critical hits automatically wound - no roll needed
		auto_wounds = critical_hits
		# DEVASTATING WOUNDS: Lethal Hits auto-wounds count as critical wounds IF weapon has DW
		# Note: Lethal Hits auto-wound on hit roll 6s, not wound roll 6s
		# Per 10e rules, these are auto-wounds but NOT critical wounds for Devastating Wounds
		# Critical wounds for DW require unmodified 6 on the WOUND roll

		# Roll wounds for: regular hits + sustained bonus hits
		var hits_to_roll = regular_hits + sustained_bonus_hits
		if hits_to_roll > 0:
			wound_rolls = rng.roll_d6(hits_to_roll)
			for roll in wound_rolls:
				if roll >= wound_threshold:
					wounds_from_rolls += 1
					# DEVASTATING WOUNDS: Track unmodified 6s on wound roll
					if weapon_has_devastating_wounds and roll == 6:
						critical_wound_count += 1
					else:
						regular_wound_count += 1

		# Lethal Hits auto-wounds go to regular wounds (not critical wounds for DW)
		regular_wound_count += auto_wounds
	else:
		# Normal processing - all hits (including sustained bonus) roll to wound
		wound_rolls = rng.roll_d6(total_hits_for_wounds)
		for roll in wound_rolls:
			if roll >= wound_threshold:
				wounds_from_rolls += 1
				# DEVASTATING WOUNDS: Track unmodified 6s on wound roll
				if weapon_has_devastating_wounds and roll == 6:
					critical_wound_count += 1
				else:
					regular_wound_count += 1

	var wounds_caused = auto_wounds + wounds_from_rolls

	result.dice.append({
		"context": "to_wound",
		"threshold": str(wound_threshold) + "+",
		"rolls_raw": wound_rolls,
		"successes": wounds_caused,
		# LETHAL HITS tracking (PRP-010)
		"lethal_hits_auto_wounds": auto_wounds,
		"wounds_from_rolls": wounds_from_rolls,
		"lethal_hits_weapon": weapon_has_lethal_hits,
		# SUSTAINED HITS tracking (PRP-011)
		"sustained_bonus_hits_rolled": sustained_bonus_hits,
		# DEVASTATING WOUNDS tracking (PRP-012)
		"devastating_wounds_weapon": weapon_has_devastating_wounds,
		"critical_wounds": critical_wound_count,
		"regular_wounds": regular_wound_count
	})

	if wounds_caused == 0:
		result.log_text = "%s → %s: %d hits (+%d sustained), no wounds" % [actor_unit.get("meta", {}).get("name", actor_unit_id), target_unit.get("meta", {}).get("name", target_unit_id), hits, sustained_bonus_hits]
		return result

	# STOP HERE - Prepare save data instead of auto-resolving
	# DEVASTATING WOUNDS (PRP-012): Pass critical wound info for unsaveable damage
	var devastating_wounds_data = {
		"has_devastating_wounds": weapon_has_devastating_wounds,
		"critical_wounds": critical_wound_count,
		"regular_wounds": regular_wound_count
	}
	var save_data = prepare_save_resolution(
		wounds_caused,
		target_unit_id,
		actor_unit_id,
		weapon_profile,
		board,
		devastating_wounds_data
	)

	result["save_data"] = save_data
	# SUSTAINED HITS (PRP-011) + DEVASTATING WOUNDS (PRP-012): Include in log text
	var log_parts = []
	log_parts.append("%s → %s: %d hits" % [
		actor_unit.get("meta", {}).get("name", actor_unit_id),
		target_unit.get("meta", {}).get("name", target_unit_id),
		hits
	])
	if sustained_bonus_hits > 0:
		log_parts[0] += " (+%d sustained)" % sustained_bonus_hits
	log_parts[0] += ", %d wounds" % wounds_caused

	# DEVASTATING WOUNDS: Add critical wound info to log
	if weapon_has_devastating_wounds and critical_wound_count > 0:
		log_parts.append("%d DEVASTATING (unsaveable)" % critical_wound_count)

	log_parts.append("awaiting saves")
	result.log_text = " - ".join(log_parts)

	return result

# Resolve a single weapon assignment (models with weapon -> target)
# SUSTAINED HITS (PRP-011): This function is modified to handle Sustained Hits
# BLAST (PRP-013): This function is modified to handle Blast keyword
static func _resolve_assignment(assignment: Dictionary, actor_unit_id: String, board: Dictionary, rng: RNGService) -> Dictionary:
	var result = {
		"diffs": [],
		"dice": [],
		"log_text": ""
	}

	var model_ids = assignment.get("model_ids", [])
	var weapon_id = assignment.get("weapon_id", "")
	var target_unit_id = assignment.get("target_unit_id", "")

	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})
	var target_unit = units.get(target_unit_id, {})

	if target_unit.is_empty():
		result.log_text = "Target unit not found"
		return result

	# Get weapon profile
	var weapon_profile = get_weapon_profile(weapon_id, board)
	if weapon_profile.is_empty():
		result.log_text = "Unknown weapon: " + weapon_id
		return result

	# Calculate total attacks
	var attacks_per_model = weapon_profile.get("attacks", 1)

	# BLAST KEYWORD (PRP-013): Apply minimum attacks for Blast weapons vs 6+ model units
	var blast_minimum_applied = false
	var original_attacks_per_model = attacks_per_model
	var effective_attacks_per_model = calculate_blast_minimum(weapon_id, attacks_per_model, target_unit, board)
	if effective_attacks_per_model > attacks_per_model:
		blast_minimum_applied = true
		attacks_per_model = effective_attacks_per_model

	var base_attacks = model_ids.size() * attacks_per_model

	# RAPID FIRE KEYWORD: Check if weapon is Rapid Fire and models are in half range
	var rapid_fire_value = get_rapid_fire_value(weapon_id, board)
	var rapid_fire_attacks = 0
	var models_in_half_range = 0
	if rapid_fire_value > 0:
		models_in_half_range = count_models_in_half_range(actor_unit, target_unit, weapon_id, model_ids, board)
		rapid_fire_attacks = models_in_half_range * rapid_fire_value

	# BLAST KEYWORD (PRP-013): Add bonus attacks based on target unit size
	var blast_bonus_attacks = calculate_blast_bonus(weapon_id, target_unit, board)
	var target_model_count = count_alive_models(target_unit)

	var total_attacks = base_attacks + rapid_fire_attacks + blast_bonus_attacks
	if assignment.has("attacks_override") and assignment.attacks_override != null:
		total_attacks = assignment.attacks_override
		rapid_fire_attacks = 0  # Override disables the rapid fire bonus tracking
		blast_bonus_attacks = 0  # Override disables the blast bonus tracking

	# TORRENT KEYWORD (PRP-014): Check if weapon auto-hits (skip hit roll entirely)
	var is_torrent = is_torrent_weapon(weapon_id, board)

	# Variables that need to be declared for both paths
	var bs = weapon_profile.get("bs", 4)
	var hits = 0
	var critical_hits = 0  # Unmodified 6s that hit (never for Torrent)
	var regular_hits = 0   # Non-critical hits
	var hit_modifiers = HitModifier.NONE
	var heavy_bonus_applied = false
	var bgnt_penalty_applied = false
	var hit_rolls = []
	var modified_rolls = []
	var reroll_data = []
	var weapon_has_lethal_hits = false
	var sustained_data = {"value": 0, "is_dice": false}
	var sustained_result = {"bonus_hits": 0, "rolls": []}
	var sustained_bonus_hits = 0
	var total_hits_for_wounds = 0

	if is_torrent:
		# TORRENT: All attacks automatically hit - no roll needed
		# Since no hit roll is made:
		# - Lethal Hits cannot trigger (no critical hits)
		# - Sustained Hits cannot trigger (no critical hits)
		# - Hit modifiers are irrelevant (Heavy, cover, etc.)
		hits = total_attacks
		regular_hits = total_attacks  # All are "regular" hits - no crits possible
		critical_hits = 0  # Torrent weapons never roll to hit, so no crits
		total_hits_for_wounds = hits

		# Note: We still check if weapon HAS these keywords for UI display
		# but they won't have any effect since there's no hit roll
		weapon_has_lethal_hits = has_lethal_hits(weapon_id, board)
		sustained_data = get_sustained_hits_value(weapon_id, board)

		result.dice.append({
			"context": "auto_hit",  # Special context for Torrent
			"torrent_weapon": true,
			"total_attacks": total_attacks,
			"successes": hits,
			"message": "Torrent: %d automatic hits" % hits,
			# Still track these for completeness, but they won't trigger
			"lethal_hits_weapon": weapon_has_lethal_hits,
			"sustained_hits_weapon": sustained_data.value > 0,
			"sustained_hits_note": "N/A - no hit roll for Torrent",
			# BLAST (PRP-013)
			"blast_weapon": is_blast_weapon(weapon_id, board),
			"blast_bonus_attacks": blast_bonus_attacks,
			"blast_minimum_applied": blast_minimum_applied,
			"blast_original_attacks": original_attacks_per_model,
			"target_model_count": target_model_count,
			"base_attacks": base_attacks,
			"rapid_fire_bonus": rapid_fire_attacks,
			"rapid_fire_value": rapid_fire_value,
			"models_in_half_range": models_in_half_range
		})
	else:
		# Normal hit roll path (non-Torrent weapons)
		# Get hit modifiers from assignment (Phase 1 MVP)
		if assignment.has("modifiers") and assignment.modifiers.has("hit"):
			var hit_mods = assignment.modifiers.hit
			if hit_mods.get("reroll_ones", false):
				hit_modifiers |= HitModifier.REROLL_ONES
			if hit_mods.get("plus_one", false):
				hit_modifiers |= HitModifier.PLUS_ONE
			if hit_mods.get("minus_one", false):
				hit_modifiers |= HitModifier.MINUS_ONE

		# HEAVY KEYWORD: Check if weapon is Heavy and unit remained stationary
		if is_heavy_weapon(weapon_id, board):
			var remained_stationary = actor_unit.get("flags", {}).get("remained_stationary", false)
			if remained_stationary:
				hit_modifiers |= HitModifier.PLUS_ONE
				heavy_bonus_applied = true

		# BIG GUNS NEVER TIRE: Apply -1 to hit for non-Pistol weapons when Monster/Vehicle is in Engagement Range
		if big_guns_never_tire_applies(actor_unit):
			# Only apply penalty if this is NOT a Pistol weapon
			if not is_pistol_weapon(weapon_id, board):
				hit_modifiers |= HitModifier.MINUS_ONE
				bgnt_penalty_applied = true

		# Roll to hit with modifiers - CRITICAL HIT TRACKING (PRP-031)
		hit_rolls = rng.roll_d6(total_attacks)

		for i in range(hit_rolls.size()):
			var roll = hit_rolls[i]
			var unmodified_roll = roll  # Store BEFORE any modifications
			# Apply modifiers to this roll
			var modifier_result = apply_hit_modifiers(roll, hit_modifiers, rng)
			var final_roll = modifier_result.modified_roll
			modified_rolls.append(final_roll)

			# Track re-rolls for dice log
			if modifier_result.rerolled:
				reroll_data.append({
					"original": modifier_result.original_roll,
					"rerolled_to": modifier_result.reroll_value
				})
				unmodified_roll = modifier_result.reroll_value  # Use new roll for crit check

			# 10e rules: Unmodified 1 always misses, unmodified 6 always hits
			if unmodified_roll == 1:
				pass  # Auto-miss regardless of modifiers
			elif unmodified_roll == 6 or final_roll >= bs:
				hits += 1
				# Critical hit = unmodified 6 (BEFORE modifiers)
				if unmodified_roll == 6:
					critical_hits += 1
				else:
					regular_hits += 1

		# Check for Lethal Hits keyword
		weapon_has_lethal_hits = has_lethal_hits(weapon_id, board)

		# SUSTAINED HITS (PRP-011): Generate bonus hits on critical hits
		sustained_data = get_sustained_hits_value(weapon_id, board)
		sustained_result = roll_sustained_hits(critical_hits, sustained_data, rng)
		sustained_bonus_hits = sustained_result.bonus_hits

		# Total hits for wound rolls = regular hits + bonus hits from Sustained
		# (Critical hits with Lethal Hits auto-wound, but their Sustained bonus hits still roll)
		total_hits_for_wounds = hits + sustained_bonus_hits

		result.dice.append({
			"context": "to_hit",
			"threshold": str(bs) + "+",
			"rolls_raw": hit_rolls,
			"rolls_modified": modified_rolls,
			"rerolls": reroll_data,
			"modifiers_applied": hit_modifiers,
			"heavy_bonus_applied": heavy_bonus_applied,
			"bgnt_penalty_applied": bgnt_penalty_applied,
			"rapid_fire_bonus": rapid_fire_attacks,
			"rapid_fire_value": rapid_fire_value,
			"models_in_half_range": models_in_half_range,
			"base_attacks": base_attacks,
			"successes": hits,
			# CRITICAL HIT TRACKING (PRP-031)
			"critical_hits": critical_hits,
			"regular_hits": regular_hits,
			"lethal_hits_weapon": weapon_has_lethal_hits,
			# SUSTAINED HITS (PRP-011)
			"sustained_hits_weapon": sustained_data.value > 0,
			"sustained_hits_value": sustained_data.value,
			"sustained_hits_is_dice": sustained_data.is_dice,
			"sustained_bonus_hits": sustained_bonus_hits,
			"sustained_rolls": sustained_result.rolls,
			"total_hits_for_wounds": total_hits_for_wounds,
			# BLAST (PRP-013)
			"blast_weapon": is_blast_weapon(weapon_id, board),
			"blast_bonus_attacks": blast_bonus_attacks,
			"blast_minimum_applied": blast_minimum_applied,
			"blast_original_attacks": original_attacks_per_model,
			"target_model_count": target_model_count
		})

	if hits == 0 and sustained_bonus_hits == 0:
		result.log_text = "%s → %s: No hits" % [actor_unit.get("meta", {}).get("name", actor_unit_id), target_unit.get("meta", {}).get("name", target_unit_id)]
		return result

	# Roll to wound - LETHAL HITS (PRP-010) + SUSTAINED HITS (PRP-011)
	# TORRENT (PRP-014): Torrent weapons skip hit roll but still roll to wound normally
	var strength = weapon_profile.get("strength", 4)
	var toughness = target_unit.get("meta", {}).get("stats", {}).get("toughness", 4)
	var wound_threshold = _calculate_wound_threshold(strength, toughness)

	# LETHAL HITS + SUSTAINED HITS interaction:
	# - Critical hits with Lethal Hits auto-wound (no roll needed) - NOT for Torrent (no crits)
	# - Bonus hits from Sustained Hits always roll to wound (even if weapon has Lethal Hits) - NOT for Torrent (no crits)
	# - Regular (non-critical) hits always roll to wound
	var auto_wounds = 0  # From Lethal Hits (never for Torrent)
	var wounds_from_rolls = 0
	var wound_rolls = []

	# TORRENT (PRP-014): Since Torrent has no crits, Lethal Hits never triggers
	# All hits must roll to wound normally
	if weapon_has_lethal_hits and not is_torrent:
		# Critical hits automatically wound - no roll needed
		auto_wounds = critical_hits
		# Roll wounds for: regular hits + sustained bonus hits
		var hits_to_roll = regular_hits + sustained_bonus_hits
		if hits_to_roll > 0:
			wound_rolls = rng.roll_d6(hits_to_roll)
			for roll in wound_rolls:
				if roll >= wound_threshold:
					wounds_from_rolls += 1
	else:
		# Normal processing - all hits (including sustained bonus) roll to wound
		wound_rolls = rng.roll_d6(total_hits_for_wounds)
		for roll in wound_rolls:
			if roll >= wound_threshold:
				wounds_from_rolls += 1

	var wounds_caused = auto_wounds + wounds_from_rolls

	result.dice.append({
		"context": "to_wound",
		"threshold": str(wound_threshold) + "+",
		"rolls_raw": wound_rolls,
		"successes": wounds_caused,
		# LETHAL HITS tracking (PRP-010)
		"lethal_hits_auto_wounds": auto_wounds,
		"wounds_from_rolls": wounds_from_rolls,
		"lethal_hits_weapon": weapon_has_lethal_hits,
		# SUSTAINED HITS tracking (PRP-011)
		"sustained_bonus_hits_rolled": sustained_bonus_hits
	})

	if wounds_caused == 0:
		result.log_text = "%s → %s: %d hits (+%d sustained), no wounds" % [actor_unit.get("meta", {}).get("name", actor_unit_id), target_unit.get("meta", {}).get("name", target_unit_id), hits, sustained_bonus_hits]
		return result

	# Process saves and damage
	var ap = weapon_profile.get("ap", 0)
	var damage = weapon_profile.get("damage", 1)
	var casualties = 0
	var damage_applied = 0

	# IGNORES COVER: Check if weapon ignores cover for auto-resolve path
	var auto_weapon_ignores_cover = false
	var auto_keywords = weapon_profile.get("keywords", [])
	for auto_kw in auto_keywords:
		if "ignores cover" in auto_kw.to_lower():
			auto_weapon_ignores_cover = true
			break
	if not auto_weapon_ignores_cover:
		var auto_special = weapon_profile.get("special_rules", "").to_lower()
		if "ignores cover" in auto_special:
			auto_weapon_ignores_cover = true

	# Get target unit's save value
	var base_save = target_unit.get("meta", {}).get("stats", {}).get("save", 7)

	# Find allocation focus model (if any model was previously wounded)
	var allocation_focus_model_id = null
	var models = target_unit.get("models", [])
	for i in range(models.size()):
		var model = models[i]
		if model.get("alive", true):
			var wounds = model.get("wounds", 1)
			var current_wounds = model.get("current_wounds", wounds)
			if current_wounds < wounds:
				allocation_focus_model_id = model.get("id", "m%d" % i)
				break
	
	# Allocate wounds
	for wound_idx in range(wounds_caused):
		# Select target model
		var target_model = null
		var target_model_index = -1
		
		if allocation_focus_model_id:
			# Must allocate to previously wounded model
			for i in range(models.size()):
				var model = models[i]
				if model.get("id", "m%d" % i) == allocation_focus_model_id and model.get("alive", true):
					target_model = model
					target_model_index = i
					break
		
		if not target_model:
			# Find first alive model
			for i in range(models.size()):
				var model = models[i]
				if model.get("alive", true):
					target_model = model
					target_model_index = i
					allocation_focus_model_id = model.get("id", "m%d" % i)
					break
		
		if not target_model:
			break  # No more models to allocate to
		
		# Check for cover (IGNORES COVER skips this)
		var has_cover = false if auto_weapon_ignores_cover else _check_model_has_cover(target_model, actor_unit_id, board)

		# Calculate save needed
		var save_result = _calculate_save_needed(base_save, ap, has_cover, target_model.get("invuln", 0))
		
		# Roll save
		var save_roll = rng.roll_d6(1)[0]
		var saved = false

		# 10e rules: Unmodified save roll of 1 always fails
		if save_roll > 1:
			if save_result.use_invuln:
				saved = save_roll >= save_result.inv
			else:
				saved = save_roll >= save_result.armour
		
		result.dice.append({
			"context": "save",
			"sv": str(base_save) + "+",
			"ap": ap,
			"cover": "+1 (capped)" if has_cover and not save_result.use_invuln else "none",
			"rolls_raw": [save_roll],
			"fails": 0 if saved else 1
		})
		
		if not saved:
			# Apply damage
			var current_wounds = target_model.get("current_wounds", target_model.get("wounds", 1))
			var new_wounds = max(0, current_wounds - damage)
			
			result.diffs.append({
				"op": "set",
				"path": "units.%s.models.%d.current_wounds" % [target_unit_id, target_model_index],
				"value": new_wounds
			})
			
			damage_applied += damage
			
			if new_wounds == 0:
				# Model destroyed
				result.diffs.append({
					"op": "set",
					"path": "units.%s.models.%d.alive" % [target_unit_id, target_model_index],
					"value": false
				})
				casualties += 1
				allocation_focus_model_id = null  # Need new allocation target
	
	# Build log text
	var actor_name = actor_unit.get("meta", {}).get("name", actor_unit_id)
	var target_name = target_unit.get("meta", {}).get("name", target_unit_id)
	
	if casualties > 0:
		result.log_text = "%s → %s: %d hits, %d wounds, %d failed saves → %d slain" % [actor_name, target_name, hits, wounds_caused, wounds_caused - (wounds_caused - casualties), casualties]
	else:
		result.log_text = "%s → %s: %d hits, %d wounds, all saved" % [actor_name, target_name, hits, wounds_caused]
	
	return result

# Validation functions
static func validate_shoot(action: Dictionary, board: Dictionary) -> Dictionary:
	var errors = []

	var actor_unit_id = action.get("actor_unit_id", "")
	if actor_unit_id == "":
		errors.append("Missing actor_unit_id")
		return {"valid": false, "errors": errors}

	var assignments = action.get("payload", {}).get("assignments", [])
	if assignments.is_empty():
		errors.append("No weapon assignments provided")
		return {"valid": false, "errors": errors}

	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})

	if actor_unit.is_empty():
		errors.append("Actor unit not found")
		return {"valid": false, "errors": errors}

	# Check if unit can shoot
	var flags = actor_unit.get("flags", {})

	# BATTLE-SHOCKED: Battle-shocked units cannot shoot (10e rules)
	if flags.get("battle_shocked", false):
		errors.append("Unit cannot shoot (battle-shocked)")
		return {"valid": false, "errors": errors}

	# ASSAULT RULES: Units that Advanced can shoot, but ONLY with Assault weapons
	# Check this BEFORE the cannot_shoot flag, since Advanced units CAN shoot (with restrictions)
	var actor_advanced = flags.get("advanced", false)

	# Units that Fell Back cannot shoot (unless special rules)
	if flags.get("fell_back", false):
		errors.append("Unit cannot shoot (fell back)")
		return {"valid": false, "errors": errors}

	# Legacy cannot_shoot flag check - but skip if unit advanced (since advanced units CAN shoot)
	if flags.get("cannot_shoot", false) and not actor_advanced:
		errors.append("Unit cannot shoot")

	# PISTOL RULES: Check if actor is in engagement range
	var actor_in_engagement = flags.get("in_engagement", false)

	# Validate each assignment
	for assignment in assignments:
		var weapon_id = assignment.get("weapon_id", "")
		var target_unit_id = assignment.get("target_unit_id", "")

		if weapon_id == "":
			errors.append("Assignment missing weapon_id")
		else:
			var weapon_profile = get_weapon_profile(weapon_id, board)
			if weapon_profile.is_empty():
				errors.append("Unknown weapon: " + weapon_id)
			else:
				# PISTOL RULES: If in engagement, only Pistol weapons can be used
				if actor_in_engagement and not is_pistol_weapon(weapon_id, board):
					errors.append("Non-Pistol weapon '%s' cannot be fired while in engagement range" % weapon_profile.get("name", weapon_id))

				# ASSAULT RULES: If unit Advanced, only Assault weapons can be used
				if actor_advanced and not is_assault_weapon(weapon_id, board):
					errors.append("Cannot fire non-Assault weapon '%s' after Advancing" % weapon_profile.get("name", weapon_id))

		if target_unit_id == "":
			errors.append("Assignment missing target_unit_id")
		elif not units.has(target_unit_id):
			errors.append("Target unit not found: " + target_unit_id)
		else:
			var target_unit = units[target_unit_id]
			if target_unit.get("owner", 0) == actor_unit.get("owner", 0):
				errors.append("Cannot target friendly units")

			# 10e TARGETING RESTRICTION: Cannot target enemies in engagement with friendly units
			# Exception: MONSTER and VEHICLE targets can always be targeted (Big Guns Never Tire)
			if not is_monster_or_vehicle(target_unit):
				if _is_target_in_friendly_engagement(target_unit_id, actor_unit_id, actor_unit.get("owner", 0), units, board):
					var target_name = target_unit.get("meta", {}).get("name", target_unit_id)
					errors.append("Cannot target '%s' — it is within engagement range of a friendly unit" % target_name)

			# PISTOL RULES: If in engagement, targets must be within engagement range
			if actor_in_engagement:
				var target_in_er = _is_target_within_engagement_range(actor_unit_id, target_unit_id, board)
				if not target_in_er:
					var target_name = target_unit.get("meta", {}).get("name", target_unit_id)
					errors.append("Pistol weapons can only target enemies in engagement range (target '%s' is not in engagement range)" % target_name)

			# BLAST RULES (PRP-013): Blast weapons cannot target units in engagement with friendlies
			if weapon_id != "":
				var blast_validation = validate_blast_targeting(actor_unit_id, target_unit_id, weapon_id, board)
				if not blast_validation.valid:
					errors.append_array(blast_validation.errors)

			# Check range and visibility
			if weapon_id != "":
				var weapon_profile = get_weapon_profile(weapon_id, board)
				if not weapon_profile.is_empty():
					var visibility_result = _check_target_visibility(actor_unit_id, target_unit_id, weapon_id, board)
					if not visibility_result.visible:
						errors.append(visibility_result.reason)

	return {"valid": errors.is_empty(), "errors": errors}

# Helper functions
static func _calculate_wound_threshold(strength: int, toughness: int) -> int:
	# 10e wound chart
	if strength >= toughness * 2:
		return 2  # 2+
	elif strength > toughness:
		return 3  # 3+
	elif strength == toughness:
		return 4  # 4+
	elif strength * 2 <= toughness:
		return 6  # 6+
	else:
		return 5  # 5+

static func _calculate_save_needed(base_save: int, ap: int, has_cover: bool, invuln: int) -> Dictionary:
	# Calculate armour save with AP and cover
	var armour_save = base_save + ap  # AP makes saves worse (higher number needed)
	
	# Apply cover if applicable
	if has_cover and ap == 0 and base_save <= 3:
		# 3+ or better save doesn't benefit from cover vs AP 0
		has_cover = false
	
	if has_cover:
		armour_save -= 1  # Cover improves save by 1
	
	# Cap save improvement at +1 total
	var improvement = base_save - armour_save
	if improvement > 1:
		armour_save = base_save - 1
	
	# Saves can never be better than 2+
	armour_save = max(2, armour_save)
	
	# Check if invuln is better (invuln ignores AP)
	var use_invuln = false
	if invuln > 0 and invuln < armour_save:
		use_invuln = true
	
	return {
		"armour": armour_save,
		"inv": invuln if invuln > 0 else 99,
		"use_invuln": use_invuln,
		"cap_applied": improvement > 1
	}

static func _check_target_visibility(actor_unit_id: String, target_unit_id: String, weapon_id: String, board: Dictionary) -> Dictionary:
	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})
	var target_unit = units.get(target_unit_id, {})
	var weapon_profile = get_weapon_profile(weapon_id, board)
	
	if actor_unit.is_empty() or target_unit.is_empty() or weapon_profile.is_empty():
		return {"visible": false, "reason": "Invalid units or weapon"}
	
	var weapon_range = weapon_profile.get("range", 12)
	var range_px = Measurement.inches_to_px(weapon_range)
	
	# Check if any model in actor unit can see and is in range of any model in target unit
	var actor_models = actor_unit.get("models", [])
	var target_models = target_unit.get("models", [])
	
	for actor_model in actor_models:
		if not actor_model.get("alive", true):
			continue
		
		var actor_pos = _get_model_position(actor_model)
		if not actor_pos:
			continue
		
		for target_model in target_models:
			if not target_model.get("alive", true):
				continue
			
			var target_pos = _get_model_position(target_model)
			if not target_pos:
				continue
			
			# Check range using shape-aware edge-to-edge distance
			var distance = Measurement.model_to_model_distance_px(actor_model, target_model)
			if distance <= range_px:
				# Check LoS with enhanced base-aware visibility
				if _check_line_of_sight(actor_pos, target_pos, board, actor_model, target_model):
					return {"visible": true, "reason": ""}
	
	return {"visible": false, "reason": "No valid targets in range and LoS"}

static func _check_line_of_sight(from_pos: Vector2, to_pos: Vector2, board: Dictionary, shooter_model: Dictionary = {}, target_model: Dictionary = {}) -> bool:
	# Enhanced mode with model data for base-aware visibility checking
	if not shooter_model.is_empty() and not target_model.is_empty():
		var result = EnhancedLineOfSight.check_enhanced_visibility(shooter_model, target_model, board)
		return result.has_los
	
	# Fallback to legacy point-to-point for backward compatibility
	return _check_legacy_line_of_sight(from_pos, to_pos, board)

static func _check_legacy_line_of_sight(from_pos: Vector2, to_pos: Vector2, board: Dictionary) -> bool:
	# Original simple line of sight checking (preserved for backward compatibility)
	var terrain_features = board.get("terrain_features", [])
	
	for terrain_piece in terrain_features:
		# Only tall terrain (>5") blocks LoS completely
		if terrain_piece.get("height_category", "") == "tall":
			var polygon = terrain_piece.get("polygon", PackedVector2Array())
			if _segment_intersects_polygon(from_pos, to_pos, polygon):
				# Check if both models are outside the terrain
				# (models inside can see out and be seen)
				if not _point_in_polygon(from_pos, polygon) and not _point_in_polygon(to_pos, polygon):
					return false
	
	return true

static func _segment_intersects_polygon(seg_start: Vector2, seg_end: Vector2, poly) -> bool:
	# Use Godot's Geometry2D for proper polygon intersection
	var polygon_packed: PackedVector2Array
	
	if poly is PackedVector2Array:
		polygon_packed = poly
	elif poly is Array:
		# Convert Array to PackedVector2Array
		polygon_packed = PackedVector2Array()
		for vertex in poly:
			if vertex is Dictionary:
				polygon_packed.append(Vector2(vertex.get("x", 0), vertex.get("y", 0)))
			elif vertex is Vector2:
				polygon_packed.append(vertex)
	else:
		return false
	
	if polygon_packed.is_empty():
		return false
	
	# Check if line segment intersects any edge of the polygon
	for i in range(polygon_packed.size()):
		var edge_start = polygon_packed[i]
		var edge_end = polygon_packed[(i + 1) % polygon_packed.size()]
		
		if Geometry2D.segment_intersects_segment(seg_start, seg_end, edge_start, edge_end):
			return true
	
	return false

# Helper function to check if a point is inside a polygon
static func _point_in_polygon(point: Vector2, poly) -> bool:
	var polygon_packed: PackedVector2Array
	
	if poly is PackedVector2Array:
		polygon_packed = poly
	elif poly is Array:
		# Convert Array to PackedVector2Array
		polygon_packed = PackedVector2Array()
		for vertex in poly:
			if vertex is Dictionary:
				polygon_packed.append(Vector2(vertex.get("x", 0), vertex.get("y", 0)))
			elif vertex is Vector2:
				polygon_packed.append(vertex)
	else:
		return false
	
	return Geometry2D.is_point_in_polygon(point, polygon_packed)

# ==========================================
# COVER SYSTEM
# ==========================================

# Check if a target position has benefit of cover from a shooter position
static func check_benefit_of_cover(target_pos: Vector2, shooter_pos: Vector2, board: Dictionary) -> bool:
	var terrain_features = board.get("terrain_features", [])
	
	for terrain_piece in terrain_features:
		if terrain_piece.get("type", "") != "ruins":
			continue
		
		var polygon = terrain_piece.get("polygon", PackedVector2Array())
		if polygon.is_empty():
			continue
		
		# Target within terrain gets cover
		if _point_in_polygon(target_pos, polygon):
			return true
		
		# Target behind terrain (LoS crosses terrain)
		if _segment_intersects_polygon(shooter_pos, target_pos, polygon):
			# Check if shooter is not inside the same terrain piece
			if not _point_in_polygon(shooter_pos, polygon):
				return true
	
	return false

# Check if any models in a unit have cover from the shooting unit
static func check_unit_has_cover(target_unit_id: String, shooter_unit_id: String, board: Dictionary) -> bool:
	var units = board.get("units", {})
	var target_unit = units.get(target_unit_id, {})
	var shooter_unit = units.get(shooter_unit_id, {})
	
	if target_unit.is_empty() or shooter_unit.is_empty():
		return false
	
	# Get average shooter position (simplified)
	var shooter_positions = []
	for model in shooter_unit.get("models", []):
		if model.get("alive", true):
			var pos = _get_model_position(model)
			if pos != Vector2.ZERO:
				shooter_positions.append(pos)
	
	if shooter_positions.is_empty():
		return false
	
	var avg_shooter_pos = Vector2.ZERO
	for pos in shooter_positions:
		avg_shooter_pos += pos
	avg_shooter_pos /= shooter_positions.size()
	
	# Check if majority of target models have cover
	var models_in_cover = 0
	var total_alive_models = 0
	
	for model in target_unit.get("models", []):
		if model.get("alive", true):
			total_alive_models += 1
			var model_pos = _get_model_position(model)
			if model_pos != Vector2.ZERO:
				if check_benefit_of_cover(model_pos, avg_shooter_pos, board):
					models_in_cover += 1
	
	# Unit has cover if majority of models are in cover
	return models_in_cover > (total_alive_models / 2.0)

static func _segment_rect_intersection(seg_start: Vector2, seg_end: Vector2, rect_min: Vector2, rect_max: Vector2) -> bool:
	# Check if segment intersects axis-aligned rectangle
	var t_min = 0.0
	var t_max = 1.0
	var delta = seg_end - seg_start
	
	for axis in [0, 1]:  # x and y axes
		if abs(delta[axis]) < 0.0001:
			# Segment parallel to axis
			if seg_start[axis] < rect_min[axis] or seg_start[axis] > rect_max[axis]:
				return false
		else:
			var t1 = (rect_min[axis] - seg_start[axis]) / delta[axis]
			var t2 = (rect_max[axis] - seg_start[axis]) / delta[axis]
			
			if t1 > t2:
				var temp = t1
				t1 = t2
				t2 = temp
			
			t_min = max(t_min, t1)
			t_max = min(t_max, t2)
			
			if t_min > t_max:
				return false
	
	return true

static func _check_model_has_cover(model: Dictionary, shooting_unit_id: String, board: Dictionary) -> bool:
	# Check if model has benefit of cover from ruins terrain
	var model_pos = _get_model_position(model)
	if not model_pos:
		return false
	
	var units = board.get("units", {})
	var shooting_unit = units.get(shooting_unit_id, {})
	
	if shooting_unit.is_empty():
		return false
	
	# Get average shooter position for cover determination
	var shooter_positions = []
	for shooter in shooting_unit.get("models", []):
		if shooter.get("alive", true):
			var shooter_pos = _get_model_position(shooter)
			if shooter_pos != Vector2.ZERO:
				shooter_positions.append(shooter_pos)
	
	if shooter_positions.is_empty():
		return false
	
	# Use average shooter position for cover check
	var avg_shooter_pos = Vector2.ZERO
	for pos in shooter_positions:
		avg_shooter_pos += pos
	avg_shooter_pos /= shooter_positions.size()
	
	# Check if model has benefit of cover using our new cover system
	return check_benefit_of_cover(model_pos, avg_shooter_pos, board)


static func _polygon_center(poly: Array) -> Vector2:
	if poly.is_empty():
		return Vector2.ZERO
	
	var sum = Vector2.ZERO
	for vertex in poly:
		var x = vertex.get("x", 0) if vertex is Dictionary else vertex.x
		var y = vertex.get("y", 0) if vertex is Dictionary else vertex.y
		sum += Vector2(x, y)
	
	return sum / poly.size()

static func _get_model_position(model: Dictionary) -> Vector2:
	var pos = model.get("position")
	if pos == null:
		return Vector2.ZERO
	if pos is Dictionary:
		return Vector2(pos.get("x", 0), pos.get("y", 0))
	elif pos is Vector2:
		return pos
	return Vector2.ZERO

# Utility functions for getting eligible targets
static func get_eligible_targets(actor_unit_id: String, board: Dictionary) -> Dictionary:
	var eligible = {}
	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})

	if actor_unit.is_empty():
		return eligible

	var actor_owner = actor_unit.get("owner", 0)

	# PISTOL RULES: Check if actor is in engagement range
	var actor_in_engagement = actor_unit.get("flags", {}).get("in_engagement", false)

	# BIG GUNS NEVER TIRE: Check if actor is Monster/Vehicle (can shoot non-Pistol weapons in ER)
	var actor_is_monster_vehicle = is_monster_or_vehicle(actor_unit)

	# Check each potential target unit
	for target_unit_id in units:
		var target_unit = units[target_unit_id]

		# Skip friendly units
		if target_unit.get("owner", 0) == actor_owner:
			continue

		# Skip units that are attached to a bodyguard (they are targeted through their bodyguard)
		if target_unit.get("attached_to", null) != null:
			continue

		# Skip destroyed units
		var has_alive_models = false
		for model in target_unit.get("models", []):
			if model.get("alive", true):
				has_alive_models = true
				break

		if not has_alive_models:
			continue

		# 10e TARGETING RESTRICTION: Cannot target enemy units within engagement range of
		# friendly units, UNLESS the target is a MONSTER or VEHICLE (Big Guns Never Tire).
		# Note: This is a general restriction separate from the Blast-specific one.
		var target_is_monster_vehicle = is_monster_or_vehicle(target_unit)
		if not target_is_monster_vehicle:
			var target_engaged_with_friendly = _is_target_in_friendly_engagement(target_unit_id, actor_unit_id, actor_owner, units, board)
			if target_engaged_with_friendly:
				continue

		# Check if target is within engagement range (needed for Pistol targeting)
		var target_in_er = false
		if actor_in_engagement:
			target_in_er = _is_target_within_engagement_range(actor_unit_id, target_unit_id, board)

		# Check weapons that can target this unit
		var weapons_in_range = []
		var unit_weapons = get_unit_weapons(actor_unit_id, board)

		for model_id in unit_weapons:
			var model = _get_model_by_id(actor_unit, model_id)
			if not model or not model.get("alive", true):
				continue

			for weapon_id in unit_weapons[model_id]:
				if weapon_id in weapons_in_range:
					continue

				var is_pistol = is_pistol_weapon(weapon_id, board)

				# ENGAGEMENT RANGE WEAPON RULES:
				if actor_in_engagement:
					if is_pistol:
						# PISTOL RULES: Pistols can only target enemies in engagement range
						if not target_in_er:
							continue
					else:
						# Non-Pistol weapons require Big Guns Never Tire (Monster/Vehicle)
						if not actor_is_monster_vehicle:
							continue
						# BGNT: Non-Pistol weapons can target any visible enemy (no ER restriction)

				var visibility = _check_target_visibility(actor_unit_id, target_unit_id, weapon_id, board)
				if visibility.visible:
					weapons_in_range.append(weapon_id)

		if not weapons_in_range.is_empty():
			eligible[target_unit_id] = {
				"weapons_in_range": weapons_in_range,
				"unit_name": target_unit.get("meta", {}).get("name", target_unit_id),
				"in_engagement_range": actor_in_engagement,  # Include flag for UI
				"is_bgnt": actor_is_monster_vehicle and actor_in_engagement  # Flag for BGNT status
			}

	return eligible

# Check if target unit is within engagement range (1") of actor unit
static func _is_target_within_engagement_range(actor_unit_id: String, target_unit_id: String, board: Dictionary) -> bool:
	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})
	var target_unit = units.get(target_unit_id, {})

	if actor_unit.is_empty() or target_unit.is_empty():
		return false

	# Check if any actor model is within engagement range of any target model
	for actor_model in actor_unit.get("models", []):
		if not actor_model.get("alive", true):
			continue

		var actor_pos = _get_model_position(actor_model)
		if actor_pos == Vector2.ZERO:
			continue

		for target_model in target_unit.get("models", []):
			if not target_model.get("alive", true):
				continue

			var target_pos = _get_model_position(target_model)
			if target_pos == Vector2.ZERO:
				continue

			# Use shape-aware edge-to-edge engagement range check
			if Measurement.is_in_engagement_range_shape_aware(actor_model, target_model, 1.0):
				return true

	return false

static func _get_model_by_id(unit: Dictionary, model_id: String) -> Dictionary:
	for model in unit.get("models", []):
		if model.get("id", "") == model_id:
			return model
	return {}

# Get weapons for a unit
static func get_unit_weapons(unit_id: String, board: Dictionary = {}) -> Dictionary:
	# First try legacy format for backward compatibility
	if UNIT_WEAPONS.has(unit_id):
		return UNIT_WEAPONS.get(unit_id, {})
	
	# Get unit from provided board or current game state
	var units = {}
	if not board.is_empty():
		units = board.get("units", {})
	else:
		units = GameState.state.get("units", {})
	var unit = units.get(unit_id, {})
	
	if unit.is_empty():
		print("WARNING: Unit not found: ", unit_id)
		return {}
	
	# Convert modern weapons format to model-weapon mapping
	var weapons = unit.get("meta", {}).get("weapons", [])
	var models = unit.get("models", [])
	var result = {}

	# First, collect unique weapon IDs from unit's weapon list
	# This prevents duplicate weapons from causing multiple assignments
	var unique_weapon_ids = []
	for weapon in weapons:
		if weapon.get("type", "") == "Ranged":  # Only include ranged weapons for shooting
			var weapon_id = _generate_weapon_id(weapon.get("name", ""))
			if weapon_id not in unique_weapon_ids:
				unique_weapon_ids.append(weapon_id)

	# Assign unique weapons to all alive models
	for model in models:
		var model_id = model.get("id", "")
		if model_id != "" and model.get("alive", true):
			result[model_id] = unique_weapon_ids.duplicate()

	# Include attached character weapons (combined unit shoots together)
	var attached_chars = unit.get("attachment_data", {}).get("attached_characters", [])
	for char_id in attached_chars:
		var char_unit = units.get(char_id, {})
		if char_unit.is_empty():
			continue

		var char_weapons = char_unit.get("meta", {}).get("weapons", [])
		var char_unique_weapon_ids = []
		for weapon in char_weapons:
			if weapon.get("type", "") == "Ranged":
				var weapon_id = _generate_weapon_id(weapon.get("name", ""))
				if weapon_id not in char_unique_weapon_ids:
					char_unique_weapon_ids.append(weapon_id)

		# Assign character weapons to character's alive models
		var char_models = char_unit.get("models", [])
		for char_model in char_models:
			var char_model_id = char_model.get("id", "")
			if char_model_id != "" and char_model.get("alive", true):
				# Use composite ID so damage routing works correctly
				var composite_id = "%s:%s" % [char_id, char_model_id]
				result[composite_id] = char_unique_weapon_ids.duplicate()

	return result

# Helper function to generate consistent weapon IDs from names
static func _generate_weapon_id(weapon_name: String) -> String:
	# Convert weapon name to consistent ID format
	var weapon_id = weapon_name.to_lower()
	weapon_id = weapon_id.replace(" ", "_")
	weapon_id = weapon_id.replace("-", "_")
	weapon_id = weapon_id.replace("–", "_")  # Handle em dash
	weapon_id = weapon_id.replace("'", "")
	return weapon_id

# Get weapon profile
static func get_weapon_profile(weapon_id: String, board: Dictionary = {}) -> Dictionary:
	# First try legacy weapon profiles
	if WEAPON_PROFILES.has(weapon_id):
		return WEAPON_PROFILES.get(weapon_id, {})
	
	# Search through all units for matching weapon
	var units = {}
	if not board.is_empty():
		units = board.get("units", {})
	else:
		units = GameState.state.get("units", {})
	
	for unit_id in units:
		var unit = units[unit_id]
		var weapons = unit.get("meta", {}).get("weapons", [])
		
		for weapon in weapons:
			var weapon_name = weapon.get("name", "")
			var generated_id = _generate_weapon_id(weapon_name)
			
			
			if generated_id == weapon_id:
				# Convert weapon format to profile format expected by UI
				# Convert string values to appropriate types where needed
				var weapon_range = weapon.get("range", "0")
				var range_value = 0
				if weapon_range == "Melee":
					range_value = 0
				else:
					range_value = int(weapon_range) if (weapon_range != null and weapon_range.is_valid_int()) else 0
				
				# Helper function to safely convert weapon stat strings to integers
				var attacks_str = weapon.get("attacks", "1")
				var attacks_value = int(attacks_str) if (attacks_str != null and attacks_str.is_valid_int()) else 1
				
				var bs_str = weapon.get("ballistic_skill", "4") 
				var bs_value = int(bs_str) if (bs_str != null and bs_str.is_valid_int()) else 4
				
				var ws_str = weapon.get("weapon_skill", "4")
				var ws_value = int(ws_str) if (ws_str != null and ws_str.is_valid_int()) else 4
				
				var strength_str = weapon.get("strength", "3")
				var strength_value = int(strength_str) if (strength_str != null and strength_str.is_valid_int()) else 3
				
				var ap_str = weapon.get("ap", "0")  
				var ap_value = 0
				if ap_str.begins_with("-"):
					var ap_num_str = ap_str.substr(1)  # Remove the "-"
					ap_value = -int(ap_num_str) if (ap_num_str != null and ap_num_str.is_valid_int()) else 0
				else:
					ap_value = int(ap_str) if (ap_str != null and ap_str.is_valid_int()) else 0
				
				var damage_str = weapon.get("damage", "1")
				var damage_value = int(damage_str) if (damage_str != null and damage_str.is_valid_int()) else 1
				# TODO: Handle complex damage like "D6+2" - for now treat as 1
				
				# Parse keywords from special_rules string (e.g., "Pistol, Rapid Fire 1")
				var special_rules = weapon.get("special_rules", "")
				var keywords = weapon.get("keywords", [])

				# If keywords array is empty but special_rules has content, extract keywords
				if keywords.is_empty() and special_rules != "":
					var rules_parts = special_rules.split(",")
					for part in rules_parts:
						var keyword = part.strip_edges().to_upper()
						# Extract keyword name (ignore numbers like "Rapid Fire 1")
						var space_pos = keyword.find(" ")
						if space_pos > 0:
							# Check if this is a keyword with a number (e.g., "RAPID FIRE 1")
							var base_keyword = keyword.substr(0, space_pos)
							if base_keyword in ["PISTOL", "ASSAULT", "HEAVY", "RAPID", "TORRENT", "BLAST"]:
								keywords.append(base_keyword)
							else:
								keywords.append(keyword)
						else:
							keywords.append(keyword)

				return {
					"name": weapon_name,
					"type": weapon.get("type", ""),
					"range": range_value,  # Convert to int for calculations
					"attacks": attacks_value,  # Convert to int for calculations
					"attacks_raw": attacks_str,  # Keep raw string for variable rolling (D3, D6, etc.)
					"bs": bs_value,  # Convert to int for to-hit rolls
					"ballistic_skill": bs_str,  # Keep string for UI display
					"ws": ws_value,  # Convert to int for melee rolls
					"weapon_skill": ws_str,  # Keep string for UI display
					"strength": strength_value,  # Convert to int for calculations
					"ap": ap_value,  # Convert to int for calculations
					"damage": damage_value,  # Convert to int for calculations
					"damage_raw": damage_str,  # Keep raw string for variable rolling (D3, D6, etc.)
					"special_rules": special_rules,
					"keywords": keywords
				}
	
	print("WARNING: Weapon profile not found: ", weapon_id)
	return {}

# Check if a weapon has the PISTOL keyword (case-insensitive)
static func is_pistol_weapon(weapon_id: String, board: Dictionary = {}) -> bool:
	var profile = get_weapon_profile(weapon_id, board)
	if profile.is_empty():
		return false

	var keywords = profile.get("keywords", [])
	for keyword in keywords:
		if keyword.to_upper() == "PISTOL":
			return true
	return false

# Check if a unit has any Pistol weapons
static func unit_has_pistol_weapons(unit_id: String, board: Dictionary = {}) -> bool:
	var unit_weapons = get_unit_weapons(unit_id, board)
	for model_id in unit_weapons:
		for weapon_id in unit_weapons[model_id]:
			if is_pistol_weapon(weapon_id, board):
				return true
	return false

# Get only Pistol weapons for a unit
static func get_unit_pistol_weapons(unit_id: String, board: Dictionary = {}) -> Dictionary:
	var result = {}
	var unit_weapons = get_unit_weapons(unit_id, board)

	for model_id in unit_weapons:
		var pistol_weapons = []
		for weapon_id in unit_weapons[model_id]:
			if is_pistol_weapon(weapon_id, board):
				pistol_weapons.append(weapon_id)
		if not pistol_weapons.is_empty():
			result[model_id] = pistol_weapons

	return result

# Check if a weapon has the ASSAULT keyword (case-insensitive)
static func is_assault_weapon(weapon_id: String, board: Dictionary = {}) -> bool:
	var profile = get_weapon_profile(weapon_id, board)
	if profile.is_empty():
		return false

	var keywords = profile.get("keywords", [])
	for keyword in keywords:
		if keyword.to_upper() == "ASSAULT":
			return true
	return false

# Check if a unit has any Assault weapons
static func unit_has_assault_weapons(unit_id: String, board: Dictionary = {}) -> bool:
	var unit_weapons = get_unit_weapons(unit_id, board)
	for model_id in unit_weapons:
		for weapon_id in unit_weapons[model_id]:
			if is_assault_weapon(weapon_id, board):
				return true
	return false

# Get only Assault weapons for a unit
static func get_unit_assault_weapons(unit_id: String, board: Dictionary = {}) -> Dictionary:
	var result = {}
	var unit_weapons = get_unit_weapons(unit_id, board)

	for model_id in unit_weapons:
		var assault_weapons = []
		for weapon_id in unit_weapons[model_id]:
			if is_assault_weapon(weapon_id, board):
				assault_weapons.append(weapon_id)
		if not assault_weapons.is_empty():
			result[model_id] = assault_weapons

	return result

# Check if a weapon has the HEAVY keyword (case-insensitive)
static func is_heavy_weapon(weapon_id: String, board: Dictionary = {}) -> bool:
	var profile = get_weapon_profile(weapon_id, board)
	if profile.is_empty():
		return false

	var keywords = profile.get("keywords", [])
	for keyword in keywords:
		if keyword.to_upper() == "HEAVY":
			return true
	return false

# Check if a unit has any Heavy weapons
static func unit_has_heavy_weapons(unit_id: String, board: Dictionary = {}) -> bool:
	var unit_weapons = get_unit_weapons(unit_id, board)
	for model_id in unit_weapons:
		for weapon_id in unit_weapons[model_id]:
			if is_heavy_weapon(weapon_id, board):
				return true
	return false

# Get only Heavy weapons for a unit
static func get_unit_heavy_weapons(unit_id: String, board: Dictionary = {}) -> Dictionary:
	var result = {}
	var unit_weapons = get_unit_weapons(unit_id, board)

	for model_id in unit_weapons:
		var heavy_weapons = []
		for weapon_id in unit_weapons[model_id]:
			if is_heavy_weapon(weapon_id, board):
				heavy_weapons.append(weapon_id)
		if not heavy_weapons.is_empty():
			result[model_id] = heavy_weapons

	return result

# ==========================================
# BIG GUNS NEVER TIRE (PRP-005)
# ==========================================

# Check if a unit has the MONSTER or VEHICLE keyword (case-insensitive)
static func is_monster_or_vehicle(unit: Dictionary) -> bool:
	var keywords = unit.get("meta", {}).get("keywords", [])
	for keyword in keywords:
		var kw_upper = keyword.to_upper()
		if kw_upper == "MONSTER" or kw_upper == "VEHICLE":
			return true
	return false

# Check if Big Guns Never Tire applies to a unit
# BGNT applies when a Monster/Vehicle unit is in Engagement Range
# Check if BGNT rule applies to a unit (is it a MONSTER or VEHICLE)
# This checks unit type eligibility, not engagement state
static func big_guns_never_tire_applies(unit: Dictionary) -> bool:
	return is_monster_or_vehicle(unit)

# Check if BGNT is currently active for a unit (in engagement AND is MONSTER/VEHICLE)
static func big_guns_never_tire_active(unit: Dictionary) -> bool:
	var in_engagement = unit.get("flags", {}).get("in_engagement", false)
	if not in_engagement:
		return false
	return is_monster_or_vehicle(unit)

# Check if a unit has any non-Pistol weapons (for BGNT shooting)
static func unit_has_non_pistol_weapons(unit_id: String, board: Dictionary = {}) -> bool:
	var unit_weapons = get_unit_weapons(unit_id, board)
	for model_id in unit_weapons:
		for weapon_id in unit_weapons[model_id]:
			if not is_pistol_weapon(weapon_id, board):
				return true
	return false

# ==========================================
# RAPID FIRE KEYWORD HELPERS
# ==========================================

# Get the Rapid Fire value (X) from a weapon's keywords or special_rules
# Returns 0 if not a Rapid Fire weapon
static func get_rapid_fire_value(weapon_id: String, board: Dictionary = {}) -> int:
	var profile = get_weapon_profile(weapon_id, board)
	if profile.is_empty():
		return 0

	# Check special_rules string for "Rapid Fire X" pattern
	var special_rules = profile.get("special_rules", "").to_lower()
	var regex = RegEx.new()
	regex.compile("rapid\\s*fire\\s*(\\d+)")
	var result = regex.search(special_rules)
	if result:
		return result.get_string(1).to_int()

	# Check keywords array for "RAPID FIRE X" pattern
	var keywords = profile.get("keywords", [])
	for keyword in keywords:
		var kw_result = regex.search(keyword.to_lower())
		if kw_result:
			return kw_result.get_string(1).to_int()

	return 0

# Check if a weapon has the RAPID FIRE keyword (case-insensitive)
static func is_rapid_fire_weapon(weapon_id: String, board: Dictionary = {}) -> bool:
	return get_rapid_fire_value(weapon_id, board) > 0

# ==========================================
# LETHAL HITS (PRP-010)
# ==========================================

# Check if a weapon has the LETHAL HITS keyword (case-insensitive)
# Lethal Hits: Critical hits (unmodified 6s to hit) automatically wound without wound roll
static func has_lethal_hits(weapon_id: String, board: Dictionary = {}) -> bool:
	var profile = get_weapon_profile(weapon_id, board)
	if profile.is_empty():
		return false

	# Check special_rules string for "Lethal Hits" (case-insensitive)
	var special_rules = profile.get("special_rules", "").to_lower()
	if "lethal hits" in special_rules:
		return true

	# Check keywords array
	var keywords = profile.get("keywords", [])
	for keyword in keywords:
		if keyword.to_lower() == "lethal hits":
			return true

	return false

# ==========================================
# SUSTAINED HITS (PRP-011)
# ==========================================

# Get Sustained Hits value from a weapon's keywords or special_rules
# Returns Dictionary with:
#   - value: The number of bonus hits per critical (0 if not Sustained Hits)
#   - is_dice: Whether the value is a dice roll (D3, D6)
# Examples: "Sustained Hits 1" -> {value: 1, is_dice: false}
#           "Sustained Hits D3" -> {value: 3, is_dice: true}
static func get_sustained_hits_value(weapon_id: String, board: Dictionary = {}) -> Dictionary:
	var profile = get_weapon_profile(weapon_id, board)
	if profile.is_empty():
		return {"value": 0, "is_dice": false}

	# Check special_rules string for "Sustained Hits X" or "Sustained Hits DX"
	var special_rules = profile.get("special_rules", "").to_lower()
	var sustained_result = _parse_sustained_hits_from_string(special_rules)
	if sustained_result.value > 0:
		return sustained_result

	# Check keywords array
	var keywords = profile.get("keywords", [])
	for keyword in keywords:
		sustained_result = _parse_sustained_hits_from_string(keyword.to_lower())
		if sustained_result.value > 0:
			return sustained_result

	return {"value": 0, "is_dice": false}

# Parse "sustained hits X" or "sustained hits dX" from a string
static func _parse_sustained_hits_from_string(text: String) -> Dictionary:
	# Look for "sustained hits" followed by a value
	var regex = RegEx.new()
	regex.compile("sustained hits\\s*(d?)(\\d+)")
	var result = regex.search(text)

	if result:
		var is_dice = result.get_string(1) == "d"
		var value = result.get_string(2).to_int()
		return {"value": value, "is_dice": is_dice}

	return {"value": 0, "is_dice": false}

# Check if a weapon has Sustained Hits
static func has_sustained_hits(weapon_id: String, board: Dictionary = {}) -> bool:
	return get_sustained_hits_value(weapon_id, board).value > 0

# Roll for sustained hits based on the weapon's sustained hits value
# Returns the total bonus hits generated for a given number of critical hits
static func roll_sustained_hits(critical_hits: int, sustained_data: Dictionary, rng: RNGService) -> Dictionary:
	if critical_hits <= 0 or sustained_data.value <= 0:
		return {"bonus_hits": 0, "rolls": []}

	var total_bonus = 0
	var rolls = []

	for _i in range(critical_hits):
		var bonus = sustained_data.value
		if sustained_data.is_dice:
			# Roll for variable sustained hits (D3 or D6)
			var roll = rng.roll_d6(1)[0]
			if sustained_data.value == 3:  # D3
				bonus = ((roll - 1) / 2) + 1  # Convert 1-6 to 1-3: 1-2->1, 3-4->2, 5-6->3
			else:  # D6 or other
				bonus = roll
			rolls.append({"dice": "D%d" % sustained_data.value, "roll": roll, "result": bonus})
		else:
			rolls.append({"fixed": bonus})
		total_bonus += bonus

	return {"bonus_hits": total_bonus, "rolls": rolls}

# Get display string for Sustained Hits (for UI)
static func get_sustained_hits_display(weapon_id: String, board: Dictionary = {}) -> String:
	var sustained = get_sustained_hits_value(weapon_id, board)
	if sustained.value <= 0:
		return ""
	if sustained.is_dice:
		return "SH D%d" % sustained.value
	return "SH %d" % sustained.value

# ==========================================
# DEVASTATING WOUNDS (PRP-012)
# ==========================================

# Check if weapon has Devastating Wounds ability
# Critical wounds (unmodified 6s to wound) bypass saves entirely
static func has_devastating_wounds(weapon_id: String, board: Dictionary = {}) -> bool:
	var profile = get_weapon_profile(weapon_id, board)
	if profile.is_empty():
		return false

	# Check special_rules string for "Devastating Wounds" (case-insensitive)
	var special_rules = profile.get("special_rules", "").to_lower()
	if "devastating wounds" in special_rules:
		return true

	# Check keywords array
	var keywords = profile.get("keywords", [])
	for keyword in keywords:
		if "devastating wounds" in keyword.to_lower():
			return true

	return false

# ==========================================
# BLAST KEYWORD (PRP-013)
# ==========================================

# Check if a weapon has the BLAST keyword
# Blast weapons gain bonus attacks based on target unit size
static func is_blast_weapon(weapon_id: String, board: Dictionary = {}) -> bool:
	var profile = get_weapon_profile(weapon_id, board)
	if profile.is_empty():
		return false

	# Check special_rules string for "Blast" (case-insensitive)
	var special_rules = profile.get("special_rules", "").to_lower()
	if "blast" in special_rules:
		return true

	# Check keywords array
	var keywords = profile.get("keywords", [])
	for keyword in keywords:
		if keyword.to_upper() == "BLAST":
			return true

	return false

# Count alive models in a target unit
static func count_alive_models(target_unit: Dictionary) -> int:
	var model_count = 0
	for model in target_unit.get("models", []):
		if model.get("alive", true):
			model_count += 1
	return model_count

# Calculate Blast bonus attacks
# Per 10e rules: +1 attack per 5 models in target unit (rounded down)
static func calculate_blast_bonus(weapon_id: String, target_unit: Dictionary, board: Dictionary = {}) -> int:
	if not is_blast_weapon(weapon_id, board):
		return 0

	var model_count = count_alive_models(target_unit)

	# Per 10e Blast rules:
	# - 5 or fewer models: no bonus
	# - 6-10 models: +1 attack
	# - 11+ models: +2 attacks (D3 simplified to flat 2 for predictability)
	if model_count >= 11:
		return 2
	elif model_count >= 6:
		return 1
	else:
		return 0

# Calculate minimum attacks for Blast
# Per 10e rules: Blast weapons make minimum 3 attacks vs units with 6+ models
static func calculate_blast_minimum(weapon_id: String, base_attacks: int, target_unit: Dictionary, board: Dictionary = {}) -> int:
	if not is_blast_weapon(weapon_id, board):
		return base_attacks

	var model_count = count_alive_models(target_unit)

	# Minimum 3 attacks against 6+ model units
	if model_count >= 6 and base_attacks < 3:
		return 3

	return base_attacks

# Check if a unit is in engagement range with any model of another unit
# Used for Blast targeting restriction
static func _check_units_in_engagement_range(unit1: Dictionary, unit2: Dictionary, board: Dictionary) -> bool:
	for model1 in unit1.get("models", []):
		if not model1.get("alive", true):
			continue

		var pos1 = _get_model_position(model1)
		if pos1 == Vector2.ZERO:
			continue

		for model2 in unit2.get("models", []):
			if not model2.get("alive", true):
				continue

			var pos2 = _get_model_position(model2)
			if pos2 == Vector2.ZERO:
				continue

			# Use shape-aware edge-to-edge engagement range check
			if Measurement.is_in_engagement_range_shape_aware(model1, model2, 1.0):
				return true

	return false

# Check if target enemy unit is within engagement range of any friendly unit (other than the actor).
# Per 10e rules: Units cannot shoot at enemies engaged with friendly units (except MONSTER/VEHICLE targets).
static func _is_target_in_friendly_engagement(target_unit_id: String, actor_unit_id: String, actor_owner: int, units: Dictionary, board: Dictionary) -> bool:
	var target_unit = units.get(target_unit_id, {})
	if target_unit.is_empty():
		return false

	for unit_id in units:
		var unit = units[unit_id]
		# Must be a friendly unit (same owner as actor)
		if unit.get("owner", 0) != actor_owner:
			continue
		# Skip the actor unit itself
		if unit_id == actor_unit_id:
			continue
		# Skip destroyed units
		var has_alive = false
		for model in unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue
		# Check if this friendly unit is in engagement range with the target
		if _check_units_in_engagement_range(unit, target_unit, board):
			return true

	return false

# Validate Blast targeting restriction
# Per 10e rules: Blast weapons cannot target units in Engagement Range of friendly units
static func validate_blast_targeting(actor_unit_id: String, target_unit_id: String, weapon_id: String, board: Dictionary) -> Dictionary:
	if not is_blast_weapon(weapon_id, board):
		return {"valid": true, "errors": []}

	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})
	var target_unit = units.get(target_unit_id, {})
	var actor_owner = actor_unit.get("owner", 0)

	if actor_unit.is_empty() or target_unit.is_empty():
		return {"valid": true, "errors": []}  # Let other validation handle missing units

	# Check if target is in engagement range of any friendly unit
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) != actor_owner:
			continue  # Skip enemy units

		if unit_id == actor_unit_id:
			continue  # Skip self

		# Check if this friendly unit is in engagement with target
		if _check_units_in_engagement_range(unit, target_unit, board):
			return {
				"valid": false,
				"errors": ["Cannot fire Blast weapon at unit in Engagement Range of friendly units"]
			}

	return {"valid": true, "errors": []}

# Get display string for Blast info (for UI)
static func get_blast_display(weapon_id: String, target_unit: Dictionary, board: Dictionary = {}) -> String:
	if not is_blast_weapon(weapon_id, board):
		return ""

	var model_count = count_alive_models(target_unit)
	var bonus = calculate_blast_bonus(weapon_id, target_unit, board)

	if bonus > 0:
		return "+%d (Blast: %d models)" % [bonus, model_count]
	elif model_count >= 6:
		return "min 3 (Blast: %d models)" % model_count
	else:
		return "(Blast: %d models)" % model_count

# ==========================================
# IGNORES COVER KEYWORD
# ==========================================

# Check if a weapon has the IGNORES COVER keyword
# Weapons with this keyword prevent the target from gaining the Benefit of Cover
static func has_ignores_cover(weapon_id: String, board: Dictionary = {}) -> bool:
	var profile = get_weapon_profile(weapon_id, board)
	if profile.is_empty():
		return false

	# Check special_rules string
	var special_rules = profile.get("special_rules", "").to_lower()
	if "ignores cover" in special_rules:
		return true

	# Check keywords array
	var keywords = profile.get("keywords", [])
	for keyword in keywords:
		if "ignores cover" in keyword.to_lower():
			return true

	return false

# ==========================================
# TORRENT KEYWORD (PRP-014)
# ==========================================

# Check if a weapon has the TORRENT keyword
# Torrent weapons automatically hit - no hit roll is made
# This means Lethal Hits/Sustained Hits cannot trigger (no hit roll = no crits)
static func is_torrent_weapon(weapon_id: String, board: Dictionary = {}) -> bool:
	var profile = get_weapon_profile(weapon_id, board)
	if profile.is_empty():
		return false

	# Check special_rules string for "Torrent" (case-insensitive)
	var special_rules = profile.get("special_rules", "").to_lower()
	if "torrent" in special_rules:
		return true

	# Check keywords array
	var keywords = profile.get("keywords", [])
	for keyword in keywords:
		if keyword.to_upper() == "TORRENT":
			return true

	return false

# Check if a unit has any Torrent weapons
static func unit_has_torrent_weapons(unit_id: String, board: Dictionary = {}) -> bool:
	var unit_weapons = get_unit_weapons(unit_id, board)
	for model_id in unit_weapons:
		for weapon_id in unit_weapons[model_id]:
			if is_torrent_weapon(weapon_id, board):
				return true
	return false

# Get only Torrent weapons for a unit
static func get_unit_torrent_weapons(unit_id: String, board: Dictionary = {}) -> Dictionary:
	var result = {}
	var unit_weapons = get_unit_weapons(unit_id, board)

	for model_id in unit_weapons:
		var torrent_weapons = []
		for weapon_id in unit_weapons[model_id]:
			if is_torrent_weapon(weapon_id, board):
				torrent_weapons.append(weapon_id)
		if not torrent_weapons.is_empty():
			result[model_id] = torrent_weapons

	return result

# Check if a unit has any Rapid Fire weapons
static func unit_has_rapid_fire_weapons(unit_id: String, board: Dictionary = {}) -> bool:
	var unit_weapons = get_unit_weapons(unit_id, board)
	for model_id in unit_weapons:
		for weapon_id in unit_weapons[model_id]:
			if is_rapid_fire_weapon(weapon_id, board):
				return true
	return false

# Get only Rapid Fire weapons for a unit
static func get_unit_rapid_fire_weapons(unit_id: String, board: Dictionary = {}) -> Dictionary:
	var result = {}
	var unit_weapons = get_unit_weapons(unit_id, board)

	for model_id in unit_weapons:
		var rapid_fire_weapons = []
		for weapon_id in unit_weapons[model_id]:
			if is_rapid_fire_weapon(weapon_id, board):
				rapid_fire_weapons.append(weapon_id)
		if not rapid_fire_weapons.is_empty():
			result[model_id] = rapid_fire_weapons

	return result

# Count how many models in the shooter unit are within half range of the target unit
# Uses edge-to-edge distance per 10th Edition rules
static func count_models_in_half_range(
	actor_unit: Dictionary,
	target_unit: Dictionary,
	weapon_id: String,
	model_ids: Array,
	board: Dictionary
) -> int:
	var weapon_profile = get_weapon_profile(weapon_id, board)
	var weapon_range = weapon_profile.get("range", 24)
	var half_range_inches = weapon_range / 2.0

	var models_in_half_range = 0

	for model_id in model_ids:
		var model = _get_model_by_id(actor_unit, model_id)
		if not model or not model.get("alive", true):
			continue

		# Check distance to closest target model (edge-to-edge)
		var closest_distance_inches = INF
		for target_model in target_unit.get("models", []):
			if not target_model.get("alive", true):
				continue

			# Use shape-aware distance measurement
			var edge_distance_px = Measurement.model_to_model_distance_px(model, target_model)
			var edge_distance_inches = Measurement.px_to_inches(edge_distance_px)
			closest_distance_inches = min(closest_distance_inches, edge_distance_inches)

		if closest_distance_inches <= half_range_inches:
			models_in_half_range += 1

	return models_in_half_range

# Validation function to check if unit has weapons
static func unit_has_weapons(unit_id: String) -> bool:
	var unit_weapons = get_unit_weapons(unit_id)
	
	for model_id in unit_weapons:
		if not unit_weapons[model_id].is_empty():
			return true
	
	return false

# Debug function to list all weapons for a unit
static func debug_unit_weapons(unit_id: String) -> void:
	print("=== DEBUGGING WEAPONS FOR UNIT: ", unit_id, " ===")
	
	var unit_weapons = get_unit_weapons(unit_id)
	if unit_weapons.is_empty():
		print("NO WEAPONS FOUND")
		return
	
	for model_id in unit_weapons:
		print("Model ", model_id, ":")
		for weapon_id in unit_weapons[model_id]:
			var profile = get_weapon_profile(weapon_id)
			print("  - ", weapon_id, " (", profile.get("name", "Unknown"), ")")
	
	print("=== END WEAPON DEBUG ===")

# ==========================================
# CHARGE PHASE HELPERS
# ==========================================

# Check if unit is eligible to charge
static func eligible_to_charge(unit_id: String, board: Dictionary) -> bool:
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	
	if unit.is_empty():
		return false
	
	var status = unit.get("status", 0)
	var flags = unit.get("flags", {})
	
	# Check if unit is deployed
	if not (status == GameStateData.UnitStatus.DEPLOYED or 
			status == GameStateData.UnitStatus.MOVED or 
			status == GameStateData.UnitStatus.SHOT):
		return false
	
	# Check restriction flags
	if flags.get("cannot_charge", false):
		return false
	
	if flags.get("advanced", false):
		return false
	
	if flags.get("fell_back", false):
		return false
	
	if flags.get("charged_this_turn", false):
		return false
	
	# Check if unit has AIRCRAFT keyword (cannot charge)
	var keywords = unit.get("meta", {}).get("keywords", [])
	if "AIRCRAFT" in keywords:
		return false
	
	# Check if already in engagement range (cannot declare charges)
	if _is_unit_in_engagement_range_charge(unit, board):
		return false
	
	# Check if unit has any alive models
	var has_alive = false
	for model in unit.get("models", []):
		if model.get("alive", true):
			has_alive = true
			break
	
	return has_alive

# Get eligible charge targets within 12" for a unit
static func charge_targets_within_12(unit_id: String, board: Dictionary) -> Dictionary:
	var eligible = {}
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	
	if unit.is_empty():
		return eligible
	
	var unit_owner = unit.get("owner", 0)
	
	# Check each potential target unit
	for target_id in units:
		var target_unit = units[target_id]
		
		# Skip friendly units
		if target_unit.get("owner", 0) == unit_owner:
			continue
		
		# Skip destroyed units
		var has_alive_models = false
		for model in target_unit.get("models", []):
			if model.get("alive", true):
				has_alive_models = true
				break
		
		if not has_alive_models:
			continue
		
		# Check if within 12" charge range
		if _is_target_within_charge_range_rules(unit_id, target_id, board):
			eligible[target_id] = {
				"name": target_unit.get("meta", {}).get("name", target_id),
				"distance": _get_min_distance_to_target_rules(unit_id, target_id, board)
			}
	
	return eligible

# Master validation function for charge paths
static func validate_charge_paths(unit_id: String, targets: Array, roll: int, paths: Dictionary, board: Dictionary) -> Dictionary:
	var errors = []
	var auto_fix_suggestions = []
	
	# 1. Validate path distances
	for model_id in paths:
		var path = paths[model_id]
		if path is Array and path.size() >= 2:
			var path_distance = Measurement.distance_polyline_inches(path)
			if path_distance > roll:
				errors.append("Model %s path exceeds charge distance: %.1f\" > %d\"" % [model_id, path_distance, roll])
				auto_fix_suggestions.append("Reduce path length for model %s" % model_id)
	
	# 2. Validate engagement range with ALL targets
	var engagement_validation = _validate_engagement_range_constraints_rules(unit_id, paths, targets, board)
	if not engagement_validation.valid:
		errors.append_array(engagement_validation.errors)
		auto_fix_suggestions.append("Adjust final positions to reach all targets")
	
	# 3. Validate unit coherency
	var coherency_validation = _validate_unit_coherency_for_charge_rules(unit_id, paths, board)
	if not coherency_validation.valid:
		errors.append_array(coherency_validation.errors)
		auto_fix_suggestions.append("Move models closer together to maintain coherency")
	
	# 4. Validate base-to-base if possible
	var base_to_base_validation = _validate_base_to_base_possible_rules(unit_id, paths, targets, board)
	if not base_to_base_validation.valid:
		errors.append_array(base_to_base_validation.errors)
		auto_fix_suggestions.append("Move models to achieve base-to-base contact when possible")
	
	return {
		"valid": errors.is_empty(),
		"reasons": errors,
		"auto_fix_suggestions": auto_fix_suggestions
	}

# Helper function to check if unit is in engagement range
static func _is_unit_in_engagement_range_charge(unit: Dictionary, board: Dictionary) -> bool:
	var models = unit.get("models", [])
	var unit_owner = unit.get("owner", 0)
	var all_units = board.get("units", {})

	for model in models:
		if not model.get("alive", true):
			continue

		var model_pos = _get_model_position_rules(model)
		if model_pos == null:
			continue

		# Check against all enemy models using shape-aware distance
		for enemy_unit_id in all_units:
			var enemy_unit = all_units[enemy_unit_id]
			if enemy_unit.get("owner", 0) == unit_owner:
				continue  # Skip friendly units

			for enemy_model in enemy_unit.get("models", []):
				if not enemy_model.get("alive", true):
					continue

				var enemy_pos = _get_model_position_rules(enemy_model)
				if enemy_pos == null:
					continue

				if Measurement.is_in_engagement_range_shape_aware(model, enemy_model, 1.0):
					return true

	return false

# Check if target is within 12" charge range
static func _is_target_within_charge_range_rules(unit_id: String, target_id: String, board: Dictionary) -> bool:
	const CHARGE_RANGE_INCHES = 12.0
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	var target = units.get(target_id, {})

	if unit.is_empty() or target.is_empty():
		return false

	# Find closest edge-to-edge distance between any models using shape-aware calculations
	var min_distance = INF

	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue

		var model_pos = _get_model_position_rules(model)
		if model_pos == null:
			continue

		for target_model in target.get("models", []):
			if not target_model.get("alive", true):
				continue

			var target_pos = _get_model_position_rules(target_model)
			if target_pos == null:
				continue

			var distance_inches = Measurement.model_to_model_distance_inches(model, target_model)
			min_distance = min(min_distance, distance_inches)

	return min_distance <= CHARGE_RANGE_INCHES

# Get minimum distance to target
static func _get_min_distance_to_target_rules(unit_id: String, target_id: String, board: Dictionary) -> float:
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	var target = units.get(target_id, {})
	var min_distance = INF

	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue

		var model_pos = _get_model_position_rules(model)
		if model_pos == null:
			continue

		for target_model in target.get("models", []):
			if not target_model.get("alive", true):
				continue

			var target_pos = _get_model_position_rules(target_model)
			if target_pos == null:
				continue

			# Use shape-aware edge-to-edge distance for non-circular bases
			var distance = Measurement.model_to_model_distance_inches(model, target_model)
			min_distance = min(min_distance, distance)

	return min_distance

# Helper to get model position for charge calculations
static func _get_model_position_rules(model: Dictionary) -> Vector2:
	var pos = model.get("position")
	if pos == null:
		return Vector2.ZERO
	if pos is Dictionary:
		return Vector2(pos.get("x", 0), pos.get("y", 0))
	elif pos is Vector2:
		return pos
	return Vector2.ZERO

# Validate engagement range constraints for charge
static func _validate_engagement_range_constraints_rules(unit_id: String, per_model_paths: Dictionary, target_ids: Array, board: Dictionary) -> Dictionary:
	const ENGAGEMENT_RANGE_INCHES = 1.0
	var errors = []
	var er_px = Measurement.inches_to_px(ENGAGEMENT_RANGE_INCHES)
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	var unit_owner = unit.get("owner", 0)
	
	# Check that unit ends within ER of ALL targets
	for target_id in target_ids:
		var target_unit = units.get(target_id, {})
		if target_unit.is_empty():
			continue
		
		var unit_in_er_of_target = false
		
		for model_id in per_model_paths:
			var path = per_model_paths[model_id]
			if path is Array and path.size() > 0:
				var final_pos = Vector2(path[-1][0], path[-1][1])
				var model = _get_model_in_unit_rules(unit, model_id)
				var model_at_final = model.duplicate()
				model_at_final["position"] = final_pos

				# Check if this model is in ER of any target model using shape-aware distance
				for target_model in target_unit.get("models", []):
					if not target_model.get("alive", true):
						continue

					var target_pos = _get_model_position_rules(target_model)
					if target_pos == null:
						continue

					if Measurement.is_in_engagement_range_shape_aware(model_at_final, target_model, 1.0):
						unit_in_er_of_target = true
						break

				if unit_in_er_of_target:
					break

		if not unit_in_er_of_target:
			var target_name = target_unit.get("meta", {}).get("name", target_id)
			errors.append("Must end within engagement range of all targets: " + target_name)

	# Check that unit does NOT end in ER of non-target enemies
	for enemy_unit_id in units:
		var enemy_unit = units[enemy_unit_id]
		if enemy_unit.get("owner", 0) == unit_owner:
			continue  # Skip friendly

		if enemy_unit_id in target_ids:
			continue  # Skip declared targets

		# Check if any charging model ends in ER of this non-target
		for model_id in per_model_paths:
			var path = per_model_paths[model_id]
			if path is Array and path.size() > 0:
				var final_pos = Vector2(path[-1][0], path[-1][1])
				var model = _get_model_in_unit_rules(unit, model_id)
				var model_at_final = model.duplicate()
				model_at_final["position"] = final_pos

				for enemy_model in enemy_unit.get("models", []):
					if not enemy_model.get("alive", true):
						continue

					var enemy_pos = _get_model_position_rules(enemy_model)
					if enemy_pos == null:
						continue

					if Measurement.is_in_engagement_range_shape_aware(model_at_final, enemy_model, 1.0):
						var enemy_name = enemy_unit.get("meta", {}).get("name", enemy_unit_id)
						errors.append("Cannot end within engagement range of non-target unit: " + enemy_name)
						break

	return {"valid": errors.is_empty(), "errors": errors}

# Validate unit coherency for charge
static func _validate_unit_coherency_for_charge_rules(unit_id: String, per_model_paths: Dictionary, board: Dictionary) -> Dictionary:
	var errors = []
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})

	# Build model dicts with final positions for shape-aware distance
	var final_models = []
	for model_id in per_model_paths:
		var path = per_model_paths[model_id]
		if path is Array and path.size() > 0:
			var model = _get_model_in_unit_rules(unit, model_id)
			var model_at_final = model.duplicate()
			model_at_final["position"] = Vector2(path[-1][0], path[-1][1])
			final_models.append(model_at_final)

	if final_models.size() < 2:
		return {"valid": true, "errors": []}  # Single model or no movement

	# Check that each model is within 2" of at least one other model (edge-to-edge)
	for i in range(final_models.size()):
		var has_nearby_model = false

		for j in range(final_models.size()):
			if i == j:
				continue

			var distance = Measurement.model_to_model_distance_inches(final_models[i], final_models[j])

			if distance <= 2.0:
				has_nearby_model = true
				break

		if not has_nearby_model:
			errors.append("Unit coherency broken: model %d too far from other models" % i)

	return {"valid": errors.is_empty(), "errors": errors}

# Validate base-to-base if possible for charge (simplified for MVP)
static func _validate_base_to_base_possible_rules(unit_id: String, per_model_paths: Dictionary, target_ids: Array, board: Dictionary) -> Dictionary:
	# For MVP, we'll implement a simplified check
	# In full implementation, this would check if base-to-base contact is achievable
	# and required when all other constraints are satisfied
	return {"valid": true, "errors": []}

# Helper to get model in unit for charge calculations
static func _get_model_in_unit_rules(unit: Dictionary, model_id: String) -> Dictionary:
	var models = unit.get("models", [])
	for model in models:
		if model.get("id", "") == model_id:
			return model
	return {}

# ==========================================
# ARMY LIST WEAPON PARSING
# ==========================================

# Parse weapon stats from army list data
static func parse_weapon_stats(weapon_data: Dictionary) -> Dictionary:
	var stats = {}
	
	# Handle dice notation (e.g., "D6", "2D6")
	if weapon_data.has("attacks"):
		var attacks = weapon_data.get("attacks", "1")
		if attacks is String:
			stats["attacks"] = _parse_dice_notation(attacks)
		else:
			stats["attacks"] = {"min": attacks, "max": attacks, "dice": ""}
	else:
		stats["attacks"] = {"min": 1, "max": 1, "dice": ""}
	
	# Parse other weapon stats
	stats["range"] = _parse_range(weapon_data.get("range", "Melee"))
	stats["weapon_skill"] = weapon_data.get("weapon_skill", null)
	stats["ballistic_skill"] = weapon_data.get("ballistic_skill", null)
	stats["strength"] = _parse_stat_value(weapon_data.get("strength", "4"))
	stats["ap"] = _parse_ap_value(weapon_data.get("ap", "0"))
	stats["damage"] = _parse_damage(weapon_data.get("damage", "1"))
	stats["special_rules"] = weapon_data.get("special_rules", "")
	stats["type"] = weapon_data.get("type", "Ranged")
	
	return stats

static func _parse_dice_notation(notation: String) -> Dictionary:
	if notation == "D3":
		return {"min": 1, "max": 3, "dice": "D3"}
	elif notation == "D6":
		return {"min": 1, "max": 6, "dice": "D6"}
	elif notation.begins_with("D6+"):
		var bonus = notation.split("+")[1].to_int()
		return {"min": 1 + bonus, "max": 6 + bonus, "dice": notation}
	elif notation.begins_with("2D6"):
		return {"min": 2, "max": 12, "dice": "2D6"}
	elif notation.to_int() > 0:
		var value = notation.to_int()
		return {"min": value, "max": value, "dice": ""}
	else:
		# Handle unknown dice notation as 1
		print("Unknown dice notation: ", notation, ", defaulting to 1")
		return {"min": 1, "max": 1, "dice": ""}

static func _parse_range(range_str: String) -> int:
	if range_str == "Melee":
		return 0
	else:
		var value = range_str.to_int()
		return value if value > 0 else 24  # Default to 24" if parsing fails

static func _parse_stat_value(stat_str: String) -> int:
	var value = stat_str.to_int()
	return value if value > 0 else 4  # Default to 4 if parsing fails

static func _parse_ap_value(ap_str: String) -> int:
	if ap_str.begins_with("-"):
		return ap_str.to_int()
	elif ap_str == "0":
		return 0
	else:
		var value = ap_str.to_int()
		return -value if value > 0 else 0

static func _parse_damage(damage_str: String) -> Dictionary:
	if damage_str == "D3":
		return {"min": 1, "max": 3, "dice": "D3"}
	elif damage_str == "D6":
		return {"min": 1, "max": 6, "dice": "D6"}
	elif damage_str.begins_with("D6+"):
		var bonus = damage_str.split("+")[1].to_int()
		return {"min": 1 + bonus, "max": 6 + bonus, "dice": damage_str}
	elif damage_str.begins_with("D3+"):
		var bonus = damage_str.split("+")[1].to_int()
		return {"min": 1 + bonus, "max": 3 + bonus, "dice": damage_str}
	else:
		var value = damage_str.to_int()
		if value > 0:
			return {"min": value, "max": value, "dice": ""}
		else:
			# Handle unknown damage notation as 1
			print("Unknown damage notation: ", damage_str, ", defaulting to 1")
			return {"min": 1, "max": 1, "dice": ""}

# Roll a variable characteristic string (e.g. "D3", "D6", "D6+1", "D3+3", "2D6", "3")
# Returns the rolled integer value.
static func roll_variable_characteristic(value_str: String, rng: RNGService) -> Dictionary:
	if value_str == null or value_str.is_empty():
		return {"value": 1, "rolled": false, "notation": "", "roll": 0}

	# If it's a plain integer, return it directly
	if value_str.is_valid_int():
		return {"value": int(value_str), "rolled": false, "notation": "", "roll": 0}

	var upper = value_str.to_upper().strip_edges()

	# D3
	if upper == "D3":
		var roll = rng.roll_d6(1)[0]
		var result_val = ((roll - 1) / 2) + 1  # 1-2→1, 3-4→2, 5-6→3
		return {"value": result_val, "rolled": true, "notation": "D3", "roll": roll}

	# D6
	if upper == "D6":
		var roll = rng.roll_d6(1)[0]
		return {"value": roll, "rolled": true, "notation": "D6", "roll": roll}

	# 2D6
	if upper == "2D6":
		var rolls = rng.roll_d6(2)
		var total = rolls[0] + rolls[1]
		return {"value": total, "rolled": true, "notation": "2D6", "roll": total}

	# D6+N or D3+N
	if "+" in upper:
		var parts = upper.split("+")
		var dice_part = parts[0].strip_edges()
		var bonus = int(parts[1].strip_edges()) if parts.size() > 1 and parts[1].strip_edges().is_valid_int() else 0

		if dice_part == "D6":
			var roll = rng.roll_d6(1)[0]
			return {"value": roll + bonus, "rolled": true, "notation": upper, "roll": roll}
		elif dice_part == "D3":
			var roll = rng.roll_d6(1)[0]
			var result_val = ((roll - 1) / 2) + 1 + bonus
			return {"value": result_val, "rolled": true, "notation": upper, "roll": roll}

	# Fallback: try to parse as int, default to 1
	var fallback = value_str.to_int()
	if fallback > 0:
		return {"value": fallback, "rolled": false, "notation": "", "roll": 0}

	print("RulesEngine: Unknown variable characteristic: '%s', defaulting to 1" % value_str)
	return {"value": 1, "rolled": false, "notation": value_str, "roll": 0}

# Get parsed weapon stats for a unit
static func get_unit_parsed_weapons(unit_id: String) -> Array:
	if not GameState:
		return []
		
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return []
	
	var parsed_weapons = []
	var weapons = unit.get("meta", {}).get("weapons", [])
	
	for weapon in weapons:
		var parsed = parse_weapon_stats(weapon)
		parsed["name"] = weapon.get("name", "Unknown Weapon")
		parsed_weapons.append(parsed)
	
	return parsed_weapons

# Validate weapon special rules
static func validate_weapon_special_rules(special_rules: String) -> Dictionary:
	var result = {"valid": true, "errors": []}
	
	if special_rules.is_empty():
		return result
	
	# Split by comma to handle multiple rules
	var rules_list = special_rules.split(",")
	
	for rule in rules_list:
		var rule_name = rule.strip_edges().to_lower()
		
		# Check against known special rules (expand this list as needed)
		var known_rules = [
			"assault", "heavy", "rapid fire", "pistol", "torrent", "blast",
			"precision", "sustained hits", "devastating wounds", "lethal hits",
			"twin-linked", "ignores cover", "lance", "anti-infantry",
			"anti-vehicle", "anti-monster", "feel no pain"
		]
		
		var rule_recognized = false
		for known_rule in known_rules:
			if rule_name.contains(known_rule):
				rule_recognized = true
				break
		
		if not rule_recognized:
			print("Warning: Unknown weapon special rule: ", rule_name)
			# Don't mark as invalid, just warn
	
	return result

# ===== MELEE COMBAT FUNCTIONS =====

# Per 10e rules: A model can make melee attacks if, after pile-in, it is:
# 1. Within Engagement Range (1") of any enemy model, OR
# 2. In base-to-base contact with a friendly model that is itself within
#    Engagement Range of any enemy model.
# Returns an array of model indices (int) that are eligible to fight.
const BASE_CONTACT_TOLERANCE_INCHES: float = 0.25  # Generous tolerance for digital positioning

static func get_eligible_melee_model_indices(attacker_unit: Dictionary, board: Dictionary) -> Array:
	var eligible_indices = []
	var attacker_models = attacker_unit.get("models", [])
	var unit_owner = attacker_unit.get("owner", 0)
	var all_units = board.get("units", {})

	# First pass: find which models are within engagement range (1") of any enemy
	var models_in_er = []  # Array of model indices directly in engagement range

	for i in range(attacker_models.size()):
		var model = attacker_models[i]
		if not model.get("alive", true):
			continue

		var in_er = false
		for other_unit_id in all_units:
			var other_unit = all_units[other_unit_id]
			if str(other_unit.get("owner", 0)) == str(unit_owner):
				continue  # Skip friendly units

			for enemy_model in other_unit.get("models", []):
				if not enemy_model.get("alive", true):
					continue
				if Measurement.is_in_engagement_range_shape_aware(model, enemy_model, 1.0):
					in_er = true
					break
			if in_er:
				break

		if in_er:
			models_in_er.append(i)
			eligible_indices.append(i)

	# Second pass: check models NOT in ER for base-to-base contact with a friendly
	# model that IS in ER (one level of chain per 10e rules)
	for i in range(attacker_models.size()):
		var model = attacker_models[i]
		if not model.get("alive", true):
			continue
		if i in eligible_indices:
			continue  # Already eligible from direct ER check

		for er_index in models_in_er:
			var er_model = attacker_models[er_index]
			var distance = Measurement.model_to_model_distance_inches(model, er_model)
			if distance <= BASE_CONTACT_TOLERANCE_INCHES:
				eligible_indices.append(i)
				print("RulesEngine: Model %d eligible via base-contact chain (%.2f\" from model %d in ER)" % [i, distance, er_index])
				break

	return eligible_indices

# Main melee combat resolution entry point
static func resolve_melee_attacks(action: Dictionary, board: Dictionary, rng_service: RNGService = null) -> Dictionary:
	if not rng_service:
		rng_service = RNGService.new()
	
	var result = {
		"success": true,
		"phase": "FIGHT",
		"diffs": [],
		"dice": [],
		"log_text": ""
	}
	
	var actor_unit_id = action.get("actor_unit_id", "")
	var assignments = action.get("payload", {}).get("assignments", [])
	
	if assignments.is_empty():
		result.success = false
		result.log_text = "No attack assignments provided"
		return result
	
	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})
	
	if actor_unit.is_empty():
		result.success = false
		result.log_text = "Actor unit not found"
		return result
	
	# Process each attack assignment
	for assignment in assignments:
		var assignment_result = _resolve_melee_assignment(assignment, actor_unit_id, board, rng_service)
		result.diffs.append_array(assignment_result.diffs)
		result.dice.append_array(assignment_result.dice)
		if assignment_result.log_text:
			result.log_text += assignment_result.log_text + "\n"
	
	return result

# Resolve a single melee assignment (models with weapon -> target)
# Full pipeline mirroring shooting: hit rolls (with critical tracking, Sustained Hits),
# wound rolls (with Lethal Hits, Devastating Wounds), save rolls (with invulnerable saves),
# FNP, and damage application.
static func _resolve_melee_assignment(assignment: Dictionary, actor_unit_id: String, board: Dictionary, rng: RNGService) -> Dictionary:
	var result = {
		"diffs": [],
		"dice": [],
		"log_text": ""
	}

	var attacker_id = assignment.get("attacker", "")
	var target_id = assignment.get("target", "")
	var weapon_id = assignment.get("weapon", "")
	var attacking_models = assignment.get("models", [])

	if weapon_id.is_empty():
		result.log_text = "No weapon specified for melee attack"
		return result

	# Get weapon profile (melee weapons use same format as ranged)
	var weapon_profile = get_weapon_profile(weapon_id, board)
	if weapon_profile.is_empty():
		result.log_text = "Weapon profile not found: " + weapon_id
		return result

	var units = board.get("units", {})
	var attacker_unit = units.get(attacker_id, {})
	var target_unit = units.get(target_id, {})

	if attacker_unit.is_empty() or target_unit.is_empty():
		result.log_text = "Attacker or target unit not found"
		return result

	var attacker_name = attacker_unit.get("meta", {}).get("name", attacker_id)
	var target_name = target_unit.get("meta", {}).get("name", target_id)
	var weapon_name = weapon_profile.get("name", weapon_id)

	# ===== PHASE 1: CALCULATE TOTAL ATTACKS =====
	# Per 10e rules: Only models within Engagement Range (1") of an enemy, or in
	# base-to-base contact with a friendly model that is in ER, can make attacks.
	var attacks_raw = weapon_profile.get("attacks_raw", str(weapon_profile.get("attacks", 1)))
	var total_attacks = 0
	var attacker_models = attacker_unit.get("models", [])
	var model_count = 0
	var attacks_roll_log = []

	# Compute per-model fight eligibility based on engagement range
	var eligible_model_indices = get_eligible_melee_model_indices(attacker_unit, board)
	var total_alive_models = 0

	for model_index in range(attacker_models.size()):
		var model = attacker_models[model_index]
		if not model.get("alive", true):
			continue

		total_alive_models += 1

		# If specific models assigned, check if this model is included
		if not attacking_models.is_empty() and not str(model_index) in attacking_models:
			continue

		# Per-model fight eligibility: must be in ER or base-contact chain
		if not model_index in eligible_model_indices:
			continue

		model_count += 1
		# Roll variable attacks for each model separately (per 10e rules)
		var attacks_result = roll_variable_characteristic(attacks_raw, rng)
		total_attacks += attacks_result.value
		if attacks_result.rolled:
			attacks_roll_log.append(attacks_result)

	if model_count < total_alive_models:
		print("RulesEngine: Melee eligibility filter: %d/%d alive models eligible to fight" % [model_count, total_alive_models])

	if total_attacks == 0:
		result.log_text = "No valid attacking models (0/%d in engagement range)" % total_alive_models
		return result

	# ===== PHASE 2: GET COMBAT STATS =====
	# Use WS from weapon profile (10e: WS is on the weapon, not the unit)
	var ws = weapon_profile.get("ws", 4)
	var strength = weapon_profile.get("strength", 4)
	var toughness = target_unit.get("meta", {}).get("stats", {}).get("toughness", 4)
	var ap = weapon_profile.get("ap", 0)
	var damage = weapon_profile.get("damage", 1)
	var base_save = target_unit.get("meta", {}).get("stats", {}).get("save", 7)

	# ===== PHASE 3: DETECT WEAPON ABILITIES =====
	var weapon_has_lethal_hits = has_lethal_hits(weapon_id, board)
	var sustained_data = get_sustained_hits_value(weapon_id, board)
	var weapon_has_devastating_wounds = has_devastating_wounds(weapon_id, board)
	var is_torrent = is_torrent_weapon(weapon_id, board)

	print("RulesEngine: Melee %s (%s) → %s: %d attacks (%d/%d models eligible), WS %d+, S%d, AP%d, D%d" % [
		attacker_name, weapon_name, target_name, total_attacks, model_count, total_alive_models, ws, strength, ap, damage
	])
	if weapon_has_lethal_hits:
		print("RulesEngine:   Weapon has LETHAL HITS")
	if sustained_data.value > 0:
		print("RulesEngine:   Weapon has SUSTAINED HITS %s" % (("D%d" % sustained_data.value) if sustained_data.is_dice else str(sustained_data.value)))
	if weapon_has_devastating_wounds:
		print("RulesEngine:   Weapon has DEVASTATING WOUNDS")

	# ===== PHASE 4: HIT ROLLS =====
	var hits = 0
	var critical_hits = 0
	var regular_hits = 0
	var sustained_bonus_hits = 0
	var sustained_result = {"bonus_hits": 0, "rolls": []}
	var total_hits_for_wounds = 0
	var hit_rolls = []

	if is_torrent:
		# TORRENT: All attacks automatically hit - no roll needed
		hits = total_attacks
		regular_hits = total_attacks
		critical_hits = 0  # No crits possible without rolling
		total_hits_for_wounds = hits

		result.dice.append({
			"context": "auto_hit_melee",
			"torrent_weapon": true,
			"total_attacks": total_attacks,
			"successes": hits,
			"message": "Torrent: %d automatic hits" % hits,
			"weapon": weapon_id
		})
	else:
		# Normal hit roll using Weapon Skill
		hit_rolls = rng.roll_d6(total_attacks)

		for i in range(hit_rolls.size()):
			var roll = hit_rolls[i]
			var unmodified_roll = roll

			# 10e rules: Unmodified 1 always misses, unmodified 6 always hits
			if unmodified_roll == 1:
				pass  # Auto-miss
			elif unmodified_roll == 6 or roll >= ws:
				hits += 1
				# Critical hit = unmodified 6 (BEFORE modifiers)
				if unmodified_roll == 6:
					critical_hits += 1
				else:
					regular_hits += 1

		# SUSTAINED HITS: Generate bonus hits on critical hits
		if sustained_data.value > 0 and critical_hits > 0:
			sustained_result = roll_sustained_hits(critical_hits, sustained_data, rng)
			sustained_bonus_hits = sustained_result.bonus_hits

		# Total hits for wound rolls = regular hits + critical hits + bonus from Sustained
		# (If Lethal Hits: critical hits auto-wound, but sustained bonus hits still roll)
		total_hits_for_wounds = hits + sustained_bonus_hits

		result.dice.append({
			"context": "hit_roll_melee",
			"threshold": str(ws) + "+",
			"rolls_raw": hit_rolls,
			"successes": hits,
			"weapon": weapon_id,
			"total_attacks": total_attacks,
			# Critical hit tracking
			"critical_hits": critical_hits,
			"regular_hits": regular_hits,
			"lethal_hits_weapon": weapon_has_lethal_hits,
			# Sustained Hits tracking
			"sustained_hits_weapon": sustained_data.value > 0,
			"sustained_hits_value": sustained_data.value,
			"sustained_hits_is_dice": sustained_data.is_dice,
			"sustained_bonus_hits": sustained_bonus_hits,
			"sustained_rolls": sustained_result.rolls,
			"total_hits_for_wounds": total_hits_for_wounds
		})

	if hits == 0 and sustained_bonus_hits == 0:
		result.log_text = "Melee: %s (%s) → %s: %d attacks, 0 hits" % [attacker_name, weapon_name, target_name, total_attacks]
		return result

	# ===== PHASE 5: WOUND ROLLS =====
	# With Lethal Hits, Sustained Hits, and Devastating Wounds interactions
	var wound_threshold = _calculate_wound_threshold(strength, toughness)

	var auto_wounds = 0  # From Lethal Hits
	var wounds_from_rolls = 0
	var wound_rolls = []
	var critical_wound_count = 0  # Unmodified 6s to wound (for Devastating Wounds)
	var regular_wound_count = 0

	if weapon_has_lethal_hits and not is_torrent:
		# Lethal Hits: Critical hits (unmodified 6s to hit) automatically wound - no wound roll
		auto_wounds = critical_hits
		# Per 10e: Lethal Hits auto-wounds are NOT critical wounds for Devastating Wounds
		# Critical wounds for DW require unmodified 6 on the WOUND roll

		# Roll wounds for: regular hits + sustained bonus hits (sustained bonus hits always roll)
		var hits_to_roll = regular_hits + sustained_bonus_hits
		if hits_to_roll > 0:
			wound_rolls = rng.roll_d6(hits_to_roll)
			for roll in wound_rolls:
				if roll >= wound_threshold:
					wounds_from_rolls += 1
					if weapon_has_devastating_wounds and roll == 6:
						critical_wound_count += 1
					else:
						regular_wound_count += 1

		# Lethal Hits auto-wounds go to regular wounds (not critical for DW)
		regular_wound_count += auto_wounds
	else:
		# Normal processing - all hits (including sustained bonus) roll to wound
		if total_hits_for_wounds > 0:
			wound_rolls = rng.roll_d6(total_hits_for_wounds)
			for roll in wound_rolls:
				if roll >= wound_threshold:
					wounds_from_rolls += 1
					if weapon_has_devastating_wounds and roll == 6:
						critical_wound_count += 1
					else:
						regular_wound_count += 1

	var wounds_caused = auto_wounds + wounds_from_rolls

	result.dice.append({
		"context": "wound_roll_melee",
		"threshold": str(wound_threshold) + "+",
		"rolls_raw": wound_rolls,
		"successes": wounds_caused,
		"strength": strength,
		"toughness": toughness,
		# Lethal Hits tracking
		"lethal_hits_auto_wounds": auto_wounds,
		"wounds_from_rolls": wounds_from_rolls,
		"lethal_hits_weapon": weapon_has_lethal_hits,
		# Sustained Hits tracking
		"sustained_bonus_hits_rolled": sustained_bonus_hits,
		# Devastating Wounds tracking
		"devastating_wounds_weapon": weapon_has_devastating_wounds,
		"critical_wounds": critical_wound_count,
		"regular_wounds": regular_wound_count
	})

	if wounds_caused == 0:
		var hit_text = "%d hits" % hits
		if sustained_bonus_hits > 0:
			hit_text += " (+%d sustained)" % sustained_bonus_hits
		result.log_text = "Melee: %s (%s) → %s: %d attacks, %s, 0 wounds" % [attacker_name, weapon_name, target_name, total_attacks, hit_text]
		return result

	# ===== PHASE 6: SAVE ROLLS =====
	# With invulnerable saves and Devastating Wounds (bypass saves)

	# Devastating Wounds: Critical wounds (unmodified 6s to wound) bypass saves entirely
	var wounds_needing_saves = regular_wound_count if weapon_has_devastating_wounds else wounds_caused
	var devastating_wound_count = critical_wound_count if weapon_has_devastating_wounds else 0
	var devastating_damage = devastating_wound_count * damage

	var failed_saves = 0
	var successful_saves = 0
	var save_rolls = []
	var save_threshold = 7  # Default: impossible to save

	if wounds_needing_saves > 0:
		# Calculate save needed using proper invulnerable save logic
		# In melee, no cover applies (cover is for ranged attacks)
		# Get invulnerable save from first alive target model
		var target_models = target_unit.get("models", [])
		var invuln = 0
		for model in target_models:
			if model.get("alive", true):
				invuln = model.get("invuln", 0)
				break
		# Also check unit-level invuln in meta stats
		if invuln == 0:
			invuln = target_unit.get("meta", {}).get("stats", {}).get("invuln", 0)

		var save_info = _calculate_save_needed(base_save, ap, false, invuln)  # No cover in melee
		save_threshold = save_info.inv if save_info.use_invuln else save_info.armour

		save_rolls = rng.roll_d6(wounds_needing_saves)
		for roll in save_rolls:
			# 10e rules: Unmodified save roll of 1 always fails
			if roll > 1 and roll >= save_threshold:
				successful_saves += 1

		failed_saves = wounds_needing_saves - successful_saves

	# Total unsaved wounds = failed regular saves + devastating wounds (bypass saves)
	var total_unsaved = failed_saves + devastating_wound_count

	result.dice.append({
		"context": "save_roll_melee",
		"threshold": str(save_threshold) + "+",
		"rolls_raw": save_rolls,
		"successes": successful_saves,
		"failed": failed_saves,
		"ap": ap,
		"original_save": base_save,
		"using_invuln": save_threshold != (base_save + ap) and save_threshold < 7,
		# Devastating Wounds tracking
		"devastating_wounds_bypassed": devastating_wound_count,
		"devastating_damage": devastating_damage
	})

	if total_unsaved == 0:
		var hit_text = "%d hits" % hits
		if sustained_bonus_hits > 0:
			hit_text += " (+%d sustained)" % sustained_bonus_hits
		result.log_text = "Melee: %s (%s) → %s: %d attacks, %s, %d wounds, all saved!" % [attacker_name, weapon_name, target_name, total_attacks, hit_text, wounds_caused]
		return result

	# ===== PHASE 7: DAMAGE APPLICATION =====
	# Roll variable damage per unsaved wound (D3, D6, etc.)
	var damage_raw = weapon_profile.get("damage_raw", str(weapon_profile.get("damage", 1)))
	var regular_damage = 0
	var damage_roll_log = []
	for _i in range(failed_saves):
		var dmg_result = roll_variable_characteristic(damage_raw, rng)
		regular_damage += dmg_result.value
		if dmg_result.rolled:
			damage_roll_log.append(dmg_result)

	# Devastating wounds also use per-wound variable damage
	devastating_damage = 0
	for _i in range(devastating_wound_count):
		var dmg_result = roll_variable_characteristic(damage_raw, rng)
		devastating_damage += dmg_result.value
		if dmg_result.rolled:
			damage_roll_log.append(dmg_result)

	var total_damage = regular_damage + devastating_damage

	# FEEL NO PAIN: Roll FNP for total damage before applying
	var fnp_value = get_unit_fnp(target_unit)
	var actual_damage = total_damage

	if fnp_value > 0:
		var fnp_result = roll_feel_no_pain(total_damage, fnp_value, rng)
		actual_damage = fnp_result.wounds_remaining
		result.dice.append({
			"context": "feel_no_pain",
			"threshold": str(fnp_value) + "+",
			"rolls_raw": fnp_result.rolls,
			"fnp_value": fnp_value,
			"wounds_prevented": fnp_result.wounds_prevented,
			"wounds_remaining": fnp_result.wounds_remaining,
			"total_wounds": total_damage
		})
		print("RulesEngine: Melee FNP %d+ — %d/%d damage prevented" % [fnp_value, fnp_result.wounds_prevented, total_damage])

	if actual_damage == 0:
		result.log_text = "Melee: %s (%s) → %s: %d attacks, %d hits, %d wounds, %d failed saves, FNP saved all damage!" % [attacker_name, weapon_name, target_name, total_attacks, hits, wounds_caused, total_unsaved]
		return result

	# Apply damage to target unit
	var target_models = target_unit.get("models", [])
	var damage_result = _apply_damage_to_unit_pool(target_id, actual_damage, target_models, board)
	result.diffs.append_array(damage_result.diffs)

	# ===== BUILD LOG TEXT =====
	var log_parts = []
	var hit_text = "%d hits" % hits
	if sustained_bonus_hits > 0:
		hit_text += " (+%d sustained)" % sustained_bonus_hits
	var eligibility_text = ""
	if model_count < total_alive_models:
		eligibility_text = " (%d/%d models)" % [model_count, total_alive_models]
	log_parts.append("Melee: %s (%s) → %s: %d attacks%s, %s, %d wounds" % [attacker_name, weapon_name, target_name, total_attacks, eligibility_text, hit_text, wounds_caused])

	if weapon_has_lethal_hits and auto_wounds > 0:
		log_parts.append("%d lethal" % auto_wounds)
	if weapon_has_devastating_wounds and devastating_wound_count > 0:
		log_parts.append("%d DEVASTATING (unsaveable)" % devastating_wound_count)

	log_parts.append("%d casualties" % damage_result.casualties)

	if fnp_value > 0:
		var prevented = total_damage - actual_damage
		log_parts.append("FNP prevented %d" % prevented)

	result.log_text = ", ".join(log_parts)

	return result

# Get fight priority for unit
static func get_fight_priority(unit: Dictionary) -> int:
	# Check if unit charged this turn
	if unit.get("flags", {}).get("charged_this_turn", false):
		return 0  # FIGHTS_FIRST
	
	# Check for Fights First ability
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		if "fights_first" in str(ability).to_lower():
			return 0  # FIGHTS_FIRST
	
	# Check for Fights Last debuff
	var status_effects = unit.get("status_effects", {})
	if status_effects.get("fights_last", false):
		return 2  # FIGHTS_LAST
	
	return 1  # NORMAL

# Check if two model dicts are in engagement range (shape-aware)
static func is_in_engagement_range(model1_pos: Vector2, model2_pos: Vector2, base1_mm: float = 25.0, base2_mm: float = 25.0) -> bool:
	# Legacy position-based check - create temporary model dicts for shape-aware calculation
	var model1 = {"position": model1_pos, "base_mm": base1_mm}
	var model2 = {"position": model2_pos, "base_mm": base2_mm}
	return Measurement.is_in_engagement_range_shape_aware(model1, model2, 1.0)

# Check if any models from two units are in engagement range
static func units_in_engagement_range(unit1: Dictionary, unit2: Dictionary) -> bool:
	var models1 = unit1.get("models", [])
	var models2 = unit2.get("models", [])

	for model1 in models1:
		if not model1.get("alive", true):
			continue

		for model2 in models2:
			if not model2.get("alive", true):
				continue

			# Use shape-aware engagement range check
			if Measurement.is_in_engagement_range_shape_aware(model1, model2, 1.0):
				return true

	return false

# Get melee weapons for a unit
static func get_unit_melee_weapons(unit_id: String, board: Dictionary = {}) -> Dictionary:
	var unit_weapons = {}
	
	# Use provided board or get from GameState
	var units = {}
	if not board.is_empty():
		units = board.get("units", {})
	else:
		units = GameState.state.get("units", {})
	
	var unit = units.get(unit_id, {})
	if unit.is_empty():
		return unit_weapons
	
	var models = unit.get("models", [])
	
	for model_index in range(models.size()):
		var model = models[model_index]
		if not model.get("alive", true):
			continue
		
		var model_id = "m" + str(model_index)
		var model_weapons = []
		
		# Get weapons from model or unit meta
		var weapons_data = unit.get("meta", {}).get("weapons", [])
		
		for weapon in weapons_data:
			# Check if this is a melee weapon
			if weapon.get("type", "").to_lower() == "melee":
				model_weapons.append(weapon.get("name", "Unknown Weapon"))
		
		if not model_weapons.is_empty():
			unit_weapons[model_id] = model_weapons
	
	return unit_weapons

# Helper function to apply damage to a unit (reused from shooting)
static func _apply_damage_to_unit(unit_id: String, failed_saves: int, damage_per_wound: int, board: Dictionary, rng: RNGService) -> Dictionary:
	var result = {"diffs": [], "casualties": 0}
	
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	if unit.is_empty():
		return result
	
	var models = unit.get("models", [])
	var wounds_to_allocate = failed_saves
	
	# Simple damage allocation - apply to first alive model
	for model_index in range(models.size()):
		if wounds_to_allocate <= 0:
			break
			
		var model = models[model_index]
		if not model.get("alive", true):
			continue
		
		var current_wounds = model.get("current_wounds", model.get("wounds", 1))
		var max_wounds = model.get("wounds", 1)
		
		# Apply damage
		var wounds_dealt = min(wounds_to_allocate, damage_per_wound)
		var new_wounds = current_wounds - wounds_dealt
		
		if new_wounds <= 0:
			# Model dies
			result.diffs.append({
				"op": "set",
				"path": "units.%s.models.%d.alive" % [unit_id, model_index],
				"value": false
			})
			result.diffs.append({
				"op": "set", 
				"path": "units.%s.models.%d.current_wounds" % [unit_id, model_index],
				"value": 0
			})
			result.casualties += 1
			wounds_to_allocate -= 1
		else:
			# Model survives with reduced wounds
			result.diffs.append({
				"op": "set",
				"path": "units.%s.models.%d.current_wounds" % [unit_id, model_index],
				"value": new_wounds
			})
			wounds_to_allocate -= 1

	return result

# ==========================================
# INTERACTIVE SAVE RESOLUTION (Phase 1 MVP)
# ==========================================

# Prepare save resolution data for interactive defender input
# Called after wound rolls to transfer control to defender
# DEVASTATING WOUNDS (PRP-012): Now includes devastating wounds data for unsaveable damage
static func prepare_save_resolution(
	wounds_caused: int,
	target_unit_id: String,
	shooter_unit_id: String,
	weapon_profile: Dictionary,
	board: Dictionary,
	devastating_wounds_data: Dictionary = {}
) -> Dictionary:
	"""
	Prepares all data needed for interactive save resolution.
	Returns save requirements without auto-resolving.
	DEVASTATING WOUNDS: Includes devastating_wounds count for unsaveable damage.
	"""
	var units = board.get("units", {})
	var target_unit = units.get(target_unit_id, {})

	if target_unit.is_empty():
		return {"success": false, "error": "Target unit not found"}

	var ap = weapon_profile.get("ap", 0)
	var damage = weapon_profile.get("damage", 1)
	var base_save = target_unit.get("meta", {}).get("stats", {}).get("save", 7)

	# IGNORES COVER: Check if weapon ignores cover
	var weapon_ignores_cover = has_ignores_cover(weapon_profile.get("name", ""), board)
	# Also check by weapon_id in case name lookup fails — rebuild weapon_id from name
	if not weapon_ignores_cover:
		var keywords = weapon_profile.get("keywords", [])
		for keyword in keywords:
			if "ignores cover" in keyword.to_lower():
				weapon_ignores_cover = true
				break
		if not weapon_ignores_cover:
			var special_rules = weapon_profile.get("special_rules", "").to_lower()
			if "ignores cover" in special_rules:
				weapon_ignores_cover = true

	# Get model allocation requirements (prioritize wounded models)
	var allocation_info = _get_save_allocation_requirements(target_unit, shooter_unit_id, board)

	# Calculate save profile for each model
	var model_save_profiles = []
	for model_info in allocation_info.models:
		var model = model_info.model
		var has_cover = false if weapon_ignores_cover else _check_model_has_cover(model, shooter_unit_id, board)
		var save_result = _calculate_save_needed(base_save, ap, has_cover, model.get("invuln", 0))

		model_save_profiles.append({
			"model_id": model_info.model_id,
			"model_index": model_info.model_index,
			"is_wounded": model_info.is_wounded,
			"current_wounds": model.get("current_wounds", model.get("wounds", 1)),
			"max_wounds": model.get("wounds", 1),
			"has_cover": has_cover,
			"save_needed": save_result.inv if save_result.use_invuln else save_result.armour,
			"using_invuln": save_result.use_invuln,
			"invuln_value": save_result.inv if save_result.use_invuln else 0,
			"armour_value": save_result.armour
		})

	# DEVASTATING WOUNDS (PRP-012): Extract critical wound info
	var has_devastating_wounds = devastating_wounds_data.get("has_devastating_wounds", false)
	var critical_wounds = devastating_wounds_data.get("critical_wounds", 0)
	var regular_wounds = devastating_wounds_data.get("regular_wounds", wounds_caused)

	# If weapon has DW, only regular wounds need saves
	# Critical wounds (unmodified 6s to wound) bypass saves entirely
	var wounds_needing_saves = regular_wounds if has_devastating_wounds else wounds_caused
	var devastating_wound_count = critical_wounds if has_devastating_wounds else 0
	var devastating_damage = devastating_wound_count * damage  # Each DW wound deals weapon damage

	return {
		"success": true,
		"wounds_to_save": wounds_needing_saves,  # Only non-critical wounds need saves
		"total_wounds": wounds_caused,  # Total wounds caused (for logging)
		"target_unit_id": target_unit_id,
		"target_unit_name": target_unit.get("meta", {}).get("name", target_unit_id),
		"shooter_unit_id": shooter_unit_id,
		"weapon_name": weapon_profile.get("name", "Unknown Weapon"),
		"ap": ap,
		"damage": damage,
		"base_save": base_save,
		"model_save_profiles": model_save_profiles,
		"allocation_priority": allocation_info.priority_model_ids,
		# DEVASTATING WOUNDS (PRP-012): Unsaveable damage info
		"has_devastating_wounds": has_devastating_wounds,
		"devastating_wounds": devastating_wound_count,
		"devastating_damage": devastating_damage,
		# IGNORES COVER: Flag for UI display
		"ignores_cover": weapon_ignores_cover
	}

# Get save allocation requirements (which models can/must receive wounds)
static func _get_save_allocation_requirements(target_unit: Dictionary, shooter_unit_id: String, board: Dictionary) -> Dictionary:
	var models = target_unit.get("models", [])
	var model_list = []
	var priority_model_ids = []  # Models that must be allocated to first (wounded models)
	var character_model_ids = []  # Composite IDs for attached character models
	var bodyguard_alive = false  # Whether any non-character bodyguard models are alive

	for i in range(models.size()):
		var model = models[i]
		if not model.get("alive", true):
			continue

		var model_id = model.get("id", "m%d" % i)
		var current_wounds = model.get("current_wounds", model.get("wounds", 1))
		var max_wounds = model.get("wounds", 1)
		var is_wounded = current_wounds < max_wounds

		model_list.append({
			"model_id": model_id,
			"model_index": i,
			"model": model,
			"is_wounded": is_wounded,
			"is_character": false
		})

		bodyguard_alive = true

		if is_wounded:
			priority_model_ids.append(model_id)

	# Include attached character models
	var target_unit_id = target_unit.get("id", "")
	var attached_chars = target_unit.get("attachment_data", {}).get("attached_characters", [])
	var units = board.get("units", {})

	for char_id in attached_chars:
		var char_unit = units.get(char_id, {})
		if char_unit.is_empty():
			continue

		var char_models = char_unit.get("models", [])
		for j in range(char_models.size()):
			var char_model = char_models[j]
			if not char_model.get("alive", true):
				continue

			var composite_id = "%s:%s" % [char_id, char_model.get("id", "m%d" % j)]
			var current_wounds = char_model.get("current_wounds", char_model.get("wounds", 1))
			var max_wounds = char_model.get("wounds", 1)
			var is_wounded = current_wounds < max_wounds

			model_list.append({
				"model_id": composite_id,
				"model_index": j,
				"model": char_model,
				"is_wounded": is_wounded,
				"is_character": true,
				"source_unit_id": char_id
			})

			character_model_ids.append(composite_id)

			if is_wounded:
				priority_model_ids.append(composite_id)

	return {
		"models": model_list,
		"priority_model_ids": priority_model_ids,
		"character_model_ids": character_model_ids,
		"bodyguard_alive": bodyguard_alive
	}

# Auto-allocate wounds following 10e rules (wounded models first)
# Apply damage from failed saves
# DEVASTATING WOUNDS (PRP-012): Now also applies devastating damage (no saves allowed)
static func apply_save_damage(
	save_results: Array,
	save_data: Dictionary,
	board: Dictionary,
	devastating_damage_override: int = -1,
	rng: RNGService = null
) -> Dictionary:
	"""
	Applies damage to models that failed their saves.
	DEVASTATING WOUNDS: Also applies devastating damage if present in save_data or override.
	FEEL NO PAIN: Rolls FNP for each wound about to be lost, reducing actual damage.
	Returns diffs and casualty count.
	"""
	var result = {
		"diffs": [],
		"casualties": 0,
		"damage_applied": 0,
		"devastating_damage_applied": 0,
		"fnp_rolls": [],
		"fnp_wounds_prevented": 0
	}

	var target_unit_id = save_data.target_unit_id
	var damage_per_wound = save_data.damage
	var units = board.get("units", {})
	var target_unit = units.get(target_unit_id, {})

	if target_unit.is_empty():
		return result

	var models = target_unit.get("models", [])

	# FEEL NO PAIN: Check if target unit has FNP
	var fnp_value = get_unit_fnp(target_unit)

	# DEVASTATING WOUNDS (PRP-012): Apply devastating damage first (unsaveable)
	var dw_damage = devastating_damage_override if devastating_damage_override >= 0 else save_data.get("devastating_damage", 0)
	if dw_damage > 0:
		print("RulesEngine: Applying %d devastating wounds damage (unsaveable)" % dw_damage)

		# FEEL NO PAIN: FNP applies even to devastating wounds
		var actual_dw_damage = dw_damage
		if fnp_value > 0 and rng != null:
			var fnp_result = roll_feel_no_pain(dw_damage, fnp_value, rng)
			actual_dw_damage = fnp_result.wounds_remaining
			result.fnp_rolls.append({
				"context": "feel_no_pain",
				"source": "devastating_wounds",
				"rolls": fnp_result.rolls,
				"fnp_value": fnp_value,
				"wounds_prevented": fnp_result.wounds_prevented,
				"wounds_remaining": fnp_result.wounds_remaining,
				"total_wounds": dw_damage
			})
			result.fnp_wounds_prevented += fnp_result.wounds_prevented
			print("RulesEngine: FNP reduced devastating damage from %d to %d" % [dw_damage, actual_dw_damage])

		if actual_dw_damage > 0:
			var dw_result = _apply_damage_to_unit_pool(target_unit_id, actual_dw_damage, models, board)
			result.diffs.append_array(dw_result.diffs)
			result.casualties += dw_result.casualties
			result.damage_applied += dw_result.damage_applied
			result.devastating_damage_applied = dw_result.damage_applied

			# Update models array for subsequent damage (in case models were killed by DW)
			for diff in dw_result.diffs:
				if diff.op == "set" and ".current_wounds" in diff.path:
					var path_parts = diff.path.split(".")
					if path_parts.size() >= 4:
						var model_idx = int(path_parts[3])
						if model_idx >= 0 and model_idx < models.size():
							models[model_idx]["current_wounds"] = diff.value
				elif diff.op == "set" and ".alive" in diff.path:
					var path_parts = diff.path.split(".")
					if path_parts.size() >= 4:
						var model_idx = int(path_parts[3])
						if model_idx >= 0 and model_idx < models.size():
							models[model_idx]["alive"] = diff.value

	# Apply damage from failed saves
	for save_result in save_results:
		if save_result.saved:
			continue  # No damage if save succeeded

		var model_index = save_result.model_index
		if model_index < 0 or model_index >= models.size():
			continue

		var model = models[model_index]
		if not model.get("alive", true):
			# Model already dead from devastating wounds - find next alive model
			model_index = _find_next_alive_model_index(models, model_index)
			if model_index < 0:
				continue  # No alive models left
			model = models[model_index]

		# FEEL NO PAIN: Roll FNP for each point of damage from this failed save
		var actual_damage = damage_per_wound
		if fnp_value > 0 and rng != null:
			var fnp_result = roll_feel_no_pain(damage_per_wound, fnp_value, rng)
			actual_damage = fnp_result.wounds_remaining
			result.fnp_rolls.append({
				"context": "feel_no_pain",
				"source": "failed_save",
				"rolls": fnp_result.rolls,
				"fnp_value": fnp_value,
				"wounds_prevented": fnp_result.wounds_prevented,
				"wounds_remaining": fnp_result.wounds_remaining,
				"total_wounds": damage_per_wound
			})
			result.fnp_wounds_prevented += fnp_result.wounds_prevented

			if actual_damage == 0:
				print("RulesEngine: FNP prevented all %d damage from failed save!" % damage_per_wound)
				continue  # FNP saved all wounds from this failed save

		var current_wounds = model.get("current_wounds", model.get("wounds", 1))
		var new_wounds = max(0, current_wounds - actual_damage)

		result.diffs.append({
			"op": "set",
			"path": "units.%s.models.%d.current_wounds" % [target_unit_id, model_index],
			"value": new_wounds
		})

		result.damage_applied += actual_damage

		# Update local model tracking
		models[model_index]["current_wounds"] = new_wounds

		if new_wounds == 0:
			# Model destroyed
			result.diffs.append({
				"op": "set",
				"path": "units.%s.models.%d.alive" % [target_unit_id, model_index],
				"value": false
			})
			result.casualties += 1
			models[model_index]["alive"] = false

	return result

# DEVASTATING WOUNDS (PRP-012): Helper to apply damage to unit's wound pool
# Distributes damage across models following 10e allocation rules
static func _apply_damage_to_unit_pool(target_unit_id: String, total_damage: int, models: Array, board: Dictionary) -> Dictionary:
	"""Apply damage to unit, distributing across models following 10e rules"""
	var result = {
		"diffs": [],
		"casualties": 0,
		"damage_applied": 0
	}

	var remaining_damage = total_damage

	# Apply damage following allocation rules: wounded models first, then any model
	while remaining_damage > 0:
		# Find next model to apply damage to (wounded first, then any alive)
		var target_model_index = _find_allocation_target_model(models)
		if target_model_index < 0:
			break  # No alive models

		var model = models[target_model_index]
		var current_wounds = model.get("current_wounds", model.get("wounds", 1))
		var damage_to_apply = min(remaining_damage, current_wounds)
		var new_wounds = current_wounds - damage_to_apply

		result.diffs.append({
			"op": "set",
			"path": "units.%s.models.%d.current_wounds" % [target_unit_id, target_model_index],
			"value": new_wounds
		})

		result.damage_applied += damage_to_apply
		remaining_damage -= damage_to_apply
		models[target_model_index]["current_wounds"] = new_wounds

		if new_wounds == 0:
			result.diffs.append({
				"op": "set",
				"path": "units.%s.models.%d.alive" % [target_unit_id, target_model_index],
				"value": false
			})
			result.casualties += 1
			models[target_model_index]["alive"] = false

	return result

# DEVASTATING WOUNDS (PRP-012): Find model to allocate damage to (wounded first)
static func _find_allocation_target_model(models: Array) -> int:
	"""Find next model to allocate damage to: wounded models first, then any alive"""
	# First, look for wounded alive models
	for i in range(models.size()):
		var model = models[i]
		if model.get("alive", true):
			var current = model.get("current_wounds", model.get("wounds", 1))
			var max_wounds = model.get("wounds", 1)
			if current < max_wounds:
				return i  # Return first wounded model

	# No wounded models, return first alive model
	for i in range(models.size()):
		if models[i].get("alive", true):
			return i

	return -1  # No alive models

# FEEL NO PAIN: Get FNP value for a unit (0 = no FNP)
static func get_unit_fnp(unit: Dictionary) -> int:
	"""Returns FNP value (e.g. 5 for 5+), or 0 if unit has no FNP"""
	var fnp = unit.get("meta", {}).get("stats", {}).get("fnp", 0)
	if fnp > 0:
		return fnp
	return 0

# FEEL NO PAIN: Roll FNP dice for wounds about to be lost
static func roll_feel_no_pain(wounds_to_lose: int, fnp_value: int, rng: RNGService) -> Dictionary:
	"""Roll FNP dice. Each wound that would be lost gets a D6 roll; >= fnp_value prevents it."""
	var rolls = rng.roll_d6(wounds_to_lose)
	var wounds_prevented = 0
	for roll in rolls:
		if roll >= fnp_value:
			wounds_prevented += 1
	var wounds_remaining = wounds_to_lose - wounds_prevented
	print("RulesEngine: Feel No Pain %d+ — rolled %s, prevented %d/%d wounds" % [fnp_value, str(rolls), wounds_prevented, wounds_to_lose])
	return {
		"rolls": rolls,
		"fnp_value": fnp_value,
		"wounds_prevented": wounds_prevented,
		"wounds_remaining": wounds_remaining
	}

# DEVASTATING WOUNDS (PRP-012): Find next alive model starting from given index
static func _find_next_alive_model_index(models: Array, start_index: int) -> int:
	"""Find next alive model starting from given index"""
	for i in range(start_index, models.size()):
		if models[i].get("alive", true):
			return i
	# Wrap around
	for i in range(0, start_index):
		if models[i].get("alive", true):
			return i
	return -1
