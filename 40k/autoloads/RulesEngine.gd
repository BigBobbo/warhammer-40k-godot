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
	},
	# MELTA WEAPONS (T1-1) - Bonus damage at half range
	# TEST WEAPON: Meltagun (Melta 2, D6 damage)
	"meltagun": {
		"name": "Meltagun",
		"range": 12,
		"attacks": 1,
		"bs": 3,
		"strength": 9,
		"ap": 4,
		"damage": 1,
		"damage_raw": "D6",
		"keywords": ["MELTA 2"]  # +2 damage at half range (6")
	},
	# TEST WEAPON: Multi-melta (Melta 2, D6 damage, longer range)
	"multi_melta": {
		"name": "Multi-melta",
		"range": 18,
		"attacks": 2,
		"bs": 3,
		"strength": 9,
		"ap": 4,
		"damage": 1,
		"damage_raw": "D6",
		"keywords": ["HEAVY", "MELTA 2"]  # +2 damage at half range (9")
	},
	# TEST WEAPON: Melta with fixed damage for predictable testing
	"test_melta_fixed": {
		"name": "Test Melta Fixed (Test)",
		"range": 24,
		"attacks": 1,
		"bs": 3,
		"strength": 9,
		"ap": 4,
		"damage": 3,
		"keywords": ["MELTA 2"]  # +2 damage at half range (12")
	},
	# TWIN-LINKED WEAPONS (T1-2) — Re-roll all failed wound rolls
	# TEST WEAPON: Twin-linked bolter for testing re-roll wound rolls
	"twin_linked_bolter": {
		"name": "Twin-linked Bolter (Test)",
		"range": 24,
		"attacks": 4,
		"bs": 3,
		"strength": 4,
		"ap": 0,
		"damage": 1,
		"keywords": ["TWIN-LINKED"]  # Re-roll all failed wound rolls
	},
	# TEST WEAPON: Twin-linked + Lethal Hits combo
	"twin_linked_lethal": {
		"name": "Twin-linked Lethal (Test)",
		"range": 24,
		"attacks": 4,
		"bs": 3,
		"strength": 4,
		"ap": 1,
		"damage": 1,
		"keywords": ["TWIN-LINKED", "LETHAL HITS"]  # Re-roll wounds + auto-wound on crit hits
	},
	# TEST WEAPON: Twin-linked + Devastating Wounds combo
	"twin_linked_devastating": {
		"name": "Twin-linked Devastating (Test)",
		"range": 24,
		"attacks": 4,
		"bs": 3,
		"strength": 4,
		"ap": 1,
		"damage": 2,
		"keywords": ["TWIN-LINKED", "DEVASTATING WOUNDS"]  # Re-roll wounds + crit wounds bypass saves
	},
	# INDIRECT FIRE WEAPONS (T2-4) — Can shoot without LoS; -1 to hit, unmodified 1-3 always fail, target gains cover
	# TEST WEAPON: Basic Indirect Fire weapon (e.g., artillery)
	"indirect_mortar": {
		"name": "Indirect Mortar (Test)",
		"range": 48,
		"attacks": 3,
		"bs": 4,
		"strength": 5,
		"ap": 0,
		"damage": 1,
		"keywords": ["INDIRECT FIRE", "BLAST"]  # Indirect Fire + Blast combo (common on artillery)
	},
	# TEST WEAPON: Indirect Fire only (no combos)
	"indirect_basic": {
		"name": "Indirect Basic (Test)",
		"range": 36,
		"attacks": 2,
		"bs": 3,
		"strength": 4,
		"ap": 1,
		"damage": 1,
		"keywords": ["INDIRECT FIRE"]  # Pure Indirect Fire weapon
	},
	# HAZARDOUS WEAPONS (T2-3) — After attacking, roll D6 per Hazardous weapon; on 1, bearer takes 3 MW
	# TEST WEAPON: Basic Hazardous plasma gun
	"hazardous_plasma": {
		"name": "Hazardous Plasma Gun (Test)",
		"range": 24,
		"attacks": 2,
		"bs": 3,
		"strength": 7,
		"ap": 2,
		"damage": 1,
		"keywords": ["HAZARDOUS"]  # On 1: CHARACTER/VEHICLE/MONSTER = 3MW, other = model slain
	},
	# TEST WEAPON: Hazardous + Rapid Fire combo (common on plasma incinerators)
	"hazardous_rapid_fire": {
		"name": "Hazardous Rapid Fire (Test)",
		"range": 24,
		"attacks": 2,
		"bs": 3,
		"strength": 7,
		"ap": 2,
		"damage": 1,
		"keywords": ["HAZARDOUS", "RAPID FIRE 1"]  # Hazardous + Rapid Fire combo
	},
	# LANCE WEAPONS (T4-1) — +1 to wound if bearer's unit made a charge move this turn
	# TEST WEAPON: Basic Lance melee weapon (e.g., Shining Spears laser lance)
	"lance_melee": {
		"name": "Lance Melee (Test)",
		"range": 0,
		"attacks": 3,
		"bs": 4,
		"ws": 3,
		"strength": 6,
		"ap": 2,
		"damage": 2,
		"type": "melee",
		"keywords": ["LANCE"]  # +1 to wound on charge
	},
	# TEST WEAPON: Lance + Lethal Hits combo
	"lance_lethal": {
		"name": "Lance + Lethal (Test)",
		"range": 0,
		"attacks": 4,
		"bs": 4,
		"ws": 3,
		"strength": 5,
		"ap": 1,
		"damage": 1,
		"type": "melee",
		"keywords": ["LANCE", "LETHAL HITS"]  # +1 to wound on charge + auto-wound on crit hits
	},
	# TEST WEAPON: Lance ranged weapon (Lance applies to ranged too per rules)
	"lance_ranged": {
		"name": "Lance Ranged (Test)",
		"range": 24,
		"attacks": 2,
		"bs": 3,
		"strength": 6,
		"ap": 2,
		"damage": 2,
		"type": "ranged",
		"keywords": ["LANCE"]  # +1 to wound on charge (ranged Lance)
	},
	# ONE SHOT WEAPONS (T4-2) — Weapon can only be fired once per battle
	# TEST WEAPON: Basic One Shot missile (e.g., Hunter-killer missile)
	"one_shot_missile": {
		"name": "Hunter-killer Missile (Test)",
		"range": 48,
		"attacks": 1,
		"bs": 3,
		"strength": 14,
		"ap": 3,
		"damage": 6,
		"keywords": ["ONE SHOT"]  # Can only fire once per battle
	},
	# TEST WEAPON: One Shot + Blast combo
	"one_shot_blast": {
		"name": "One Shot Blast (Test)",
		"range": 36,
		"attacks": 3,
		"bs": 3,
		"strength": 8,
		"ap": 2,
		"damage": 2,
		"keywords": ["ONE SHOT", "BLAST"]  # One Shot + Blast combo
	},
	# TEST WEAPON: One Shot with fixed stats for predictable testing
	"one_shot_test": {
		"name": "One Shot Test Weapon",
		"range": 24,
		"attacks": 2,
		"bs": 3,
		"strength": 5,
		"ap": 1,
		"damage": 1,
		"keywords": ["ONE SHOT"]  # Simple One Shot for testing
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
	# Test-only static seed override.
	# When set to a non-negative value, every unseeded make_rng() call
	# derives a deterministic-but-unique seed via hash([test_mode_seed, _test_seed_counter]).
	# Default (-1) preserves existing behavior: unseeded constructors call randomize().
	# Multiplayer is unaffected because it always passes an explicit seed_value.
	# This unblocks deterministic test coverage across phases that don't yet
	# plumb payload.rng_seed through to RNGService construction.
	static var test_mode_seed: int = -1
	static var _test_seed_counter: int = 0
	var rng: RandomNumberGenerator

	func _init(seed_value: int = -1):
		rng = RandomNumberGenerator.new()
		if seed_value >= 0:
			rng.seed = seed_value
		elif test_mode_seed >= 0:
			_test_seed_counter += 1
			rng.seed = hash([test_mode_seed, _test_seed_counter])
		else:
			rng.randomize()

	func roll_d6(count: int) -> Array:
		var rolls = []
		for i in count:
			rolls.append(rng.randi_range(1, 6))
		return rolls

	# Pass-through helpers so callers can use RNGService directly without poking
	# at the inner `rng` field. Used by sites plumbing #329 (TransportManager,
	# MissionManager Supply Drop, FightPhase Mathhammer prediction).
	func randi() -> int:
		return rng.randi()

	func randi_range(from: int, to: int) -> int:
		return rng.randi_range(from, to)

	func randf() -> float:
		return rng.randf()

	func randf_range(from: float, to: float) -> float:
		return rng.randf_range(from, to)


# ── ISS-004: sanctioned RNG factories ────────────────────────────────
# Every dice-rolling code path must obtain its RNGService from one of these
# two factories (enforced by tests/test_iss004_rng_seeding.gd). Bare
# `RNGService.new()` outside this file is a lint failure.

## Factory for ACTION HANDLERS. Honors an explicit payload.rng_seed
## (multiplayer / replay); otherwise generates a seed and RECORDS it back
## into action.payload.rng_seed so the action log can reproduce the rolls.
## Test mode (set_test_seed) takes the legacy deterministic-counter path.
static func rng_for_action(action: Dictionary) -> RNGService:
	var payload = action.get("payload", {})
	var seed_val: int = -1
	if payload is Dictionary:
		seed_val = int(payload.get("rng_seed", -1))
	if seed_val >= 0:
		return RNGService.new(seed_val)
	if RNGService.test_mode_seed >= 0:
		return RNGService.new()
	seed_val = randi() & 0x7FFFFFFF
	if not (action.get("payload") is Dictionary):
		action["payload"] = {}
	action["payload"]["rng_seed"] = seed_val
	return RNGService.new(seed_val)

## Factory for NON-ACTION contexts (managers, UI overlays, phase helpers
## that have no action dict in scope yet). Uses the session-deterministic
## NetworkManager seed when hosting a networked game; preserves the
## test_mode_seed path; otherwise falls back to randomize(). Sites using
## this factory become replay-deterministic once their flows are converted
## to actions (ISS-021).
static func make_rng(_context: String = "") -> RNGService:
	if RNGService.test_mode_seed >= 0:
		return RNGService.new()
	var ml = Engine.get_main_loop()
	if ml != null and ml.root != null:
		var nm = ml.root.get_node_or_null("NetworkManager")
		if nm != null and nm.has_method("get_next_rng_seed"):
			var s: int = nm.get_next_rng_seed()
			if s >= 0:
				return RNGService.new(s)
	return RNGService.new()


# Test/debug helpers exposing RNGService.test_mode_seed via a method, since
# Expression.parse (used by the MCP bridge's execute_script) can't perform
# the static-var assignment directly. Pass -1 to disable test mode and
# resume normal randomization. The counter is reset so each `set_test_seed`
# call starts a fresh deterministic sequence.
static func set_test_seed(seed: int) -> void:
	RNGService.test_mode_seed = seed
	RNGService._test_seed_counter = 0

static func get_test_seed() -> int:
	return RNGService.test_mode_seed

# ==========================================
# SHOOTING MODIFIERS (Phase 1 MVP)
# ==========================================

# Hit modifier flags (can be combined with bitwise OR)
enum HitModifier {
	NONE = 0,
	REROLL_ONES = 1,    # Re-roll 1s to hit
	PLUS_ONE = 2,       # +1 to hit
	MINUS_ONE = 4,      # -1 to hit (cover, moved, etc.)
	REROLL_FAILED = 8,  # Re-roll all failed hit rolls
}

# Apply hit modifiers to a single roll
# Returns the modified roll value and any re-roll that occurred
# hit_threshold: the BS/WS value needed to hit (e.g. 3 for 3+); required for REROLL_FAILED
static func apply_hit_modifiers(roll: int, modifiers: int, rng: RNGService, hit_threshold: int = 0) -> Dictionary:
	var result = {
		"original_roll": roll,
		"modified_roll": roll,
		"rerolled": false,
		"reroll_value": 0,
		"modifier_applied": 0
	}

	# Step 1: Apply re-rolls FIRST (before modifiers per 10e rules)
	# Re-roll ones takes priority check first
	if (modifiers & HitModifier.REROLL_ONES) and roll == 1:
		var reroll_result = rng.roll_d6(1)[0]
		result.rerolled = true
		result.reroll_value = reroll_result
		result.modified_roll = reroll_result
	elif (modifiers & HitModifier.REROLL_FAILED) and hit_threshold > 0 and roll < hit_threshold:
		# Re-roll all failed hit rolls (roll below BS/WS threshold)
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

# Wound modifier flags (can be combined with bitwise OR)
# Per 10e rules: wound roll modifiers are capped at net +1/-1
enum WoundModifier {
	NONE = 0,
	REROLL_ONES = 1,    # Re-roll 1s to wound
	REROLL_FAILED = 2,  # Re-roll all failed wound rolls (Twin-linked)
	PLUS_ONE = 4,       # +1 to wound (e.g., Lance on charge)
	MINUS_ONE = 8,      # -1 to wound
}

# Apply wound modifiers to a single roll
# Returns the modified roll value and any re-roll that occurred
# Per 10e rules: Unmodified 1 always fails, modifiers capped at +1/-1
static func apply_wound_modifiers(roll: int, modifiers: int, wound_threshold: int, rng: RNGService) -> Dictionary:
	var result = {
		"original_roll": roll,
		"modified_roll": roll,
		"rerolled": false,
		"reroll_value": 0,
		"modifier_applied": 0
	}

	# Step 1: Apply re-rolls FIRST (before modifiers per 10e rules)
	# Re-roll ones takes priority check first
	if (modifiers & WoundModifier.REROLL_ONES) and roll == 1:
		var reroll_result = rng.roll_d6(1)[0]
		result.rerolled = true
		result.reroll_value = reroll_result
		result.modified_roll = reroll_result
	elif (modifiers & WoundModifier.REROLL_FAILED) and roll < wound_threshold:
		# Twin-linked: Re-roll all failed wound rolls
		var reroll_result = rng.roll_d6(1)[0]
		result.rerolled = true
		result.reroll_value = reroll_result
		result.modified_roll = reroll_result

	# Step 2: Then apply numeric modifiers (capped at net +1/-1)
	var net_modifier = 0
	if modifiers & WoundModifier.PLUS_ONE:
		net_modifier += 1
	if modifiers & WoundModifier.MINUS_ONE:
		net_modifier -= 1

	# Cap modifiers at +1/-1 maximum per 10e rules
	net_modifier = clamp(net_modifier, -1, 1)

	result.modifier_applied = net_modifier
	result.modified_roll += net_modifier

	return result

# Main shooting resolution entry point
static func resolve_shoot(action: Dictionary, board: Dictionary, rng_service: RNGService = null) -> Dictionary:
	if not rng_service:
		rng_service = make_rng()

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

	# ── ISS-041 (11e 04.03): gather identical attacks. Assignments whose
	# attacks are identical (same skill/S/AP/D + same applicable abilities,
	# same target) are resolved as ONE batch — which also makes their save
	# rolls one batch, applied lowest→highest together (05.04). The engine
	# merges same-weapon batches; cross-weapon dice gathering lands with
	# the ISS-048 shooting-flow rework.
	if GameConstants.edition >= 11 and assignments.size() > 1:
		var gathered = AttackSequence.gather_identical_attacks(assignments, board)
		if gathered.size() < assignments.size():
			var merged: Array = []
			for group in gathered:
				if group.assignment_indices.size() > 1 and group.weapon_ids.size() == 1:
					var combined = assignments[group.assignment_indices[0]].duplicate(true)
					for k in range(1, group.assignment_indices.size()):
						combined["model_ids"] = combined.get("model_ids", []) + assignments[group.assignment_indices[k]].get("model_ids", [])
					merged.append(combined)
					print("RulesEngine: [11e GATHER] %d identical-attack assignments (%s → %s) gathered into one batch" % [group.assignment_indices.size(), group.weapon_ids[0], group.target_unit_id])
				else:
					for ai in group.assignment_indices:
						merged.append(assignments[ai])
			assignments = merged

	# Process each weapon assignment
	for assignment in assignments:
		var assignment_result = _resolve_assignment(assignment, actor_unit_id, board, rng_service)
		result.diffs.append_array(assignment_result.diffs)
		result.dice.append_array(assignment_result.dice)
		if assignment_result.log_text:
			result.log_text += assignment_result.log_text + "\n"

		# HAZARDOUS (T2-3): After weapon resolves, check for Hazardous self-damage
		var weapon_id = assignment.get("weapon_id", "")
		if is_hazardous_weapon(weapon_id, board):
			var models_that_fired = assignment.get("model_ids", []).size()
			var hazardous_result = resolve_hazardous_check(actor_unit_id, weapon_id, models_that_fired, board, rng_service)
			if hazardous_result.hazardous_triggered:
				result.diffs.append_array(hazardous_result.diffs)
			result.dice.append_array(hazardous_result.dice)
			if hazardous_result.log_text:
				result.log_text += hazardous_result.log_text + "\n"

		# ONE SHOT (T4-2): Mark one-shot weapon as fired for each model
		if is_one_shot_weapon(weapon_id, board):
			var model_ids = assignment.get("model_ids", [])
			for model_id in model_ids:
				var one_shot_diffs = mark_one_shot_fired_diffs(actor_unit_id, actor_unit, model_id, weapon_id)
				result.diffs.append_array(one_shot_diffs)
				# Apply diffs to local board so subsequent assignments see updated state
				for d in one_shot_diffs:
					_apply_diff_to_board(board, d)
			print("RulesEngine: [ONE SHOT] Marked weapon '%s' as fired for %d model(s)" % [weapon_id, model_ids.size()])

	return result

# Shooting resolution that stops before saves (for interactive save system)
static func resolve_shoot_until_wounds(action: Dictionary, board: Dictionary, rng_service: RNGService = null) -> Dictionary:
	if not rng_service:
		rng_service = make_rng()

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

	# HAZARDOUS (T2-3): Collect hazardous weapon info for post-save resolution
	var hazardous_weapons = []

	# Process each weapon assignment up to wounds
	for _ai in range(assignments.size()):
		var assignment = assignments[_ai]
		var assignment_result = _resolve_assignment_until_wounds(assignment, actor_unit_id, board, rng_service)

		if assignment_result.has("dice"):
			result.dice.append_array(assignment_result.dice)

		if assignment_result.has("log_text") and assignment_result.log_text:
			result.log_text += assignment_result.log_text + "\n"

		# If wounds were caused, add save data
		if assignment_result.has("save_data") and assignment_result.save_data.get("success", false):
			result.save_data_list.append(assignment_result.save_data)

		# HAZARDOUS (T2-3): Track hazardous weapons for post-save resolution
		var weapon_id = assignment.get("weapon_id", "")
		if is_hazardous_weapon(weapon_id, board):
			hazardous_weapons.append({
				"weapon_id": weapon_id,
				"models_that_fired": assignment.get("model_ids", []).size()
			})

		# ONE SHOT (T4-2): Mark one-shot weapon as fired for each model
		if is_one_shot_weapon(weapon_id, board):
			var model_ids = assignment.get("model_ids", [])
			for model_id in model_ids:
				var one_shot_diffs = mark_one_shot_fired_diffs(actor_unit_id, actor_unit, model_id, weapon_id)
				if not result.has("one_shot_diffs"):
					result["one_shot_diffs"] = []
				result["one_shot_diffs"].append_array(one_shot_diffs)
				# Apply diffs to local board so subsequent assignments see updated state
				for d in one_shot_diffs:
					_apply_diff_to_board(board, d)
			print("RulesEngine: [ONE SHOT] Marked weapon '%s' as fired for %d model(s) (interactive path)" % [weapon_id, model_ids.size()])

	# HAZARDOUS (T2-3): Store hazardous weapon data in result for ShootingPhase to process after saves
	if not hazardous_weapons.is_empty():
		result["hazardous_weapons"] = hazardous_weapons

	return result

# ==========================================
# OVERWATCH SHOOTING (Fire Overwatch Stratagem)
# Only unmodified 6s hit. All other shooting mechanics (wound, save, damage) are normal.
# ==========================================

static func resolve_overwatch_shooting(shooter_unit_id: String, target_unit_id: String, board: Dictionary, rng_service: RNGService = null) -> Dictionary:
	"""Resolve overwatch shooting: all weapons fire at the target, but only unmodified 6s count as hits.
	No hit modifiers are applied. Wound rolls, saves, and damage work normally.
	Returns { success, diffs, dice, log_text, total_hits, total_wounds, total_damage, total_casualties, weapon_results }
	"""
	if not rng_service:
		rng_service = make_rng()

	var result = {
		"success": true,
		"diffs": [],
		"dice": [],
		"log_text": "",
		"total_hits": 0,
		"total_wounds": 0,
		"total_damage": 0,
		"total_casualties": 0,
		"weapon_results": []
	}

	var units = board.get("units", {})
	var shooter_unit = units.get(shooter_unit_id, {})
	var target_unit = units.get(target_unit_id, {})

	if shooter_unit.is_empty():
		result.success = false
		result.log_text = "Shooter unit not found"
		return result

	if target_unit.is_empty():
		result.success = false
		result.log_text = "Target unit not found"
		return result

	var shooter_name = shooter_unit.get("meta", {}).get("name", shooter_unit_id)
	var target_name = target_unit.get("meta", {}).get("name", target_unit_id)

	# Gather all ranged weapons from the shooter unit's alive models
	var weapon_assignments = _build_overwatch_weapon_assignments(shooter_unit, shooter_unit_id, board)

	if weapon_assignments.is_empty():
		result.log_text = "%s has no ranged weapons for overwatch" % shooter_name
		return result

	# Resolve each weapon assignment with overwatch rules
	for wa in weapon_assignments:
		# Skip remaining weapons if target unit is already destroyed
		var ow_target_unit = board.get("units", {}).get(target_unit_id, {})
		var ow_target_alive = false
		for ow_m in ow_target_unit.get("models", []):
			if ow_m.get("alive", true):
				ow_target_alive = true
				break
		if not ow_target_alive:
			print("RulesEngine: OVERWATCH — skipping remaining weapons, target %s destroyed" % target_name)
			break

		var wa_result = _resolve_overwatch_assignment(wa, shooter_unit_id, target_unit_id, board, rng_service)
		result.diffs.append_array(wa_result.get("diffs", []))
		result.dice.append_array(wa_result.get("dice", []))
		result.total_hits += wa_result.get("hits", 0)
		result.total_wounds += wa_result.get("wounds", 0)
		result.total_damage += wa_result.get("damage", 0)
		result.total_casualties += wa_result.get("casualties", 0)
		result.weapon_results.append(wa_result)

		if wa_result.get("log_text", "") != "":
			result.log_text += wa_result.log_text + "\n"

		# Update the board snapshot with applied diffs for subsequent weapons
		# (so model alive/wounds is up to date for wound allocation)
		for diff in wa_result.get("diffs", []):
			_apply_diff_to_board(board, diff)

	if result.total_casualties > 0:
		result.log_text = "OVERWATCH: %s → %s: %d hit(s) (6+ only), %d wound(s), %d slain" % [
			shooter_name, target_name, result.total_hits, result.total_wounds, result.total_casualties
		]
	elif result.total_hits > 0:
		result.log_text = "OVERWATCH: %s → %s: %d hit(s) (6+ only), %d wound(s), all saved" % [
			shooter_name, target_name, result.total_hits, result.total_wounds
		]
	else:
		result.log_text = "OVERWATCH: %s → %s: 0 hits (only unmodified 6s hit)" % [shooter_name, target_name]

	print("RulesEngine: %s" % result.log_text)
	return result

static func _build_overwatch_weapon_assignments(shooter_unit: Dictionary, shooter_unit_id: String, board: Dictionary) -> Array:
	"""Build weapon assignments for overwatch: gather all ranged weapons from alive models.
	Uses _get_model_weapon_ids() for consistent weapon lookup with get_unit_weapons()."""
	var assignments = []
	var models = shooter_unit.get("models", [])

	# Group models by weapon using the shared profile-based lookup
	var weapon_models: Dictionary = {}  # weapon_id -> [model_ids]

	for i in range(models.size()):
		var model = models[i]
		if not model.get("alive", true):
			continue

		var model_id = model.get("id", "m%d" % (i + 1))
		var weapon_ids = _get_model_weapon_ids(shooter_unit, model, "Ranged")

		for weapon_id in weapon_ids:
			if not weapon_models.has(weapon_id):
				weapon_models[weapon_id] = []
			weapon_models[weapon_id].append(model_id)

	# Build assignments
	for weapon_id in weapon_models:
		assignments.append({
			"weapon_id": weapon_id,
			"model_ids": weapon_models[weapon_id],
			"modifiers": {}
		})

	return assignments

static func _resolve_overwatch_assignment(assignment: Dictionary, shooter_unit_id: String, target_unit_id: String, board: Dictionary, rng: RNGService) -> Dictionary:
	"""Resolve a single weapon assignment during overwatch.
	Key difference: only unmodified 6s count as hits. No hit modifiers apply."""
	var result = {
		"diffs": [],
		"dice": [],
		"log_text": "",
		"hits": 0,
		"wounds": 0,
		"damage": 0,
		"casualties": 0
	}

	var weapon_id = assignment.get("weapon_id", "")
	var model_ids = assignment.get("model_ids", [])

	var units = board.get("units", {})
	var shooter_unit = units.get(shooter_unit_id, {})
	var target_unit = units.get(target_unit_id, {})

	if target_unit.is_empty():
		return result

	var weapon_profile = get_weapon_profile(weapon_id, board)
	if weapon_profile.is_empty():
		return result

	var weapon_name = weapon_profile.get("name", weapon_id)

	# --- PHASE 1: Determine attacks ---
	var attacks_raw = weapon_profile.get("attacks_raw", str(weapon_profile.get("attacks", 1)))
	var total_attacks = 0

	# SHOOTY POWER TRIP (OA-37): +1 Attacks to ranged weapons for the phase (D6 roll 5-6)
	var ow_spt_attacks_bonus = 1 if shooter_unit.get("flags", {}).get("effect_shooty_power_trip_attacks", false) else 0

	for model_id in model_ids:
		var attacks_result = roll_variable_characteristic(attacks_raw, rng)
		var model_attacks_ow = attacks_result.value + ow_spt_attacks_bonus
		total_attacks += model_attacks_ow

	if ow_spt_attacks_bonus > 0:
		print("RulesEngine: Shooty Power Trip (Overwatch) — +1 attack per model (%d models)" % model_ids.size())

	if total_attacks <= 0:
		return result

	# --- PHASE 2: Hit rolls (OVERWATCH: only unmodified 6s hit) ---
	var hit_rolls = rng.roll_d6(total_attacks)
	var hits = 0

	for roll in hit_rolls:
		if roll == 6:  # ONLY unmodified 6s — no modifiers applied
			hits += 1

	result.dice.append({
		"context": "overwatch_to_hit",
		"weapon_name": weapon_name,
		"threshold": "6 (Overwatch)",
		"rolls_raw": hit_rolls,
		"total_attacks": total_attacks,
		"successes": hits,
		"overwatch": true
	})

	result.hits = hits

	if hits == 0:
		result.log_text = "%s (Overwatch): %d attacks, 0 hits [%s] vs 6+" % [
			weapon_name, total_attacks,
			", ".join(hit_rolls.map(func(r): return str(r)))]
		return result

	# --- PHASE 3: Wound rolls (normal rules apply) ---
	var strength = weapon_profile.get("strength", 4)
	# PULSA ROKKIT (OA-31): +1 Strength to ranged weapons for the phase
	if shooter_unit.get("flags", {}).get("effect_pulsa_rokkit_active", false):
		var pre_s_pr = strength
		strength += 1
		print("RulesEngine: Pulsa Rokkit (Overwatch) — ranged strength %d → %d (+1)" % [pre_s_pr, strength])
	# SHOOTY POWER TRIP (OA-37): +1 Strength to ranged weapons for the phase (D6 roll 3-4)
	if shooter_unit.get("flags", {}).get("effect_shooty_power_trip_strength", false):
		var pre_s_spt = strength
		strength += 1
		print("RulesEngine: Shooty Power Trip (Overwatch) — ranged strength %d → %d (+1)" % [pre_s_spt, strength])
	var toughness = _get_attached_unit_toughness(target_unit, board)  # P2-90: Use bodyguard T for attached units
	# OA-44: DED GLOWY AMMO — -1T to enemy INFANTRY within 6" of Kaptin Badrukk (overwatch)
	var ded_glowy_penalty_ow = get_ded_glowy_ammo_toughness_penalty(target_unit, board)
	if ded_glowy_penalty_ow > 0:
		toughness = max(1, toughness - ded_glowy_penalty_ow)
		print("RulesEngine: DED GLOWY AMMO (Overwatch) — INFANTRY target T reduced by %d to T%d" % [ded_glowy_penalty_ow, toughness])
	# OA-48: RUNTHERD — Runtherds revert to T4 when all Gretchin are dead
	var runtherd_t_override_ow = get_runtherd_toughness_override(target_unit)
	if runtherd_t_override_ow > 0:
		toughness = runtherd_t_override_ow
		print("RulesEngine: RUNTHERD (Overwatch) — all Gretchin dead, Runtherd T overridden to T%d" % toughness)
	var wound_threshold = _calculate_wound_threshold(strength, toughness)

	var critical_wound_threshold = get_critical_wound_threshold(weapon_id, target_unit, board)

	# ROLLING LOOT-HEAP (OA-6): Grant Anti-Vehicle 4+ from stratagem flag
	if shooter_unit.get("flags", {}).get("effect_rolling_loot_heap", false):
		if unit_has_keyword(target_unit, "VEHICLE"):
			critical_wound_threshold = mini(critical_wound_threshold, 4)
			print("RulesEngine: ROLLING LOOT-HEAP (overwatch) — Anti-Vehicle 4+ active (critical wound threshold %d+)" % critical_wound_threshold)

	# DA BOSS' LADZ (OA-15): -1 to incoming Wound rolls when S > T and Warboss leads target unit (overwatch)
	var ow_da_boss_ladz_mod = get_da_boss_ladz_wound_modifier(target_unit, board, strength, toughness)
	var ow_wound_modifier = 0
	if ow_da_boss_ladz_mod == WoundModifier.MINUS_ONE:
		ow_wound_modifier = -1
		print("RulesEngine: DA BOSS' LADZ (overwatch) — -1 to wound for attacks against %s (S %d > T %d, Warboss leading)" % [target_unit_id, strength, toughness])
	# PYROMANIAKS (OA-14): Check for wound re-rolls with Torrent weapons vs enemies within 6" (Overwatch)
	var ow_pyromaniaks_scope = get_pyromaniaks_reroll_scope(shooter_unit, target_unit, weapon_id, board)
	if ow_pyromaniaks_scope == "failed":
		print("RulesEngine: PYROMANIAKS (Overwatch) — full wound re-roll for %s (Torrent weapon, target within 6\" AND near objective)" % shooter_unit_id)
	elif ow_pyromaniaks_scope == "ones":
		print("RulesEngine: PYROMANIAKS (Overwatch) — re-roll wound rolls of 1 for %s (Torrent weapon, target within 6\")" % shooter_unit_id)

	var wound_rolls = rng.roll_d6(hits)
	var wounds = 0

	for roll in wound_rolls:
		var effective_roll = roll
		# PYROMANIAKS (OA-14): Re-roll wound rolls based on scope
		if ow_pyromaniaks_scope == "ones" and roll == 1:
			effective_roll = rng.roll_d6(1)[0]
			print("RulesEngine: PYROMANIAKS (Overwatch) — re-rolled wound 1 → %d" % effective_roll)
		elif ow_pyromaniaks_scope == "failed" and roll != 1:
			var is_fail = roll < wound_threshold and roll < critical_wound_threshold
			if is_fail:
				effective_roll = rng.roll_d6(1)[0]
				print("RulesEngine: PYROMANIAKS (Overwatch) — re-rolled failed wound %d → %d" % [roll, effective_roll])
		elif ow_pyromaniaks_scope == "failed" and roll == 1:
			effective_roll = rng.roll_d6(1)[0]
			print("RulesEngine: PYROMANIAKS (Overwatch) — re-rolled wound 1 → %d" % effective_roll)

		if effective_roll == 1:
			continue  # Unmodified 1 always fails
		var is_critical_wound = (effective_roll >= critical_wound_threshold)
		if is_critical_wound or effective_roll >= wound_threshold:
			wounds += 1

	result.dice.append({
		"context": "to_wound",
		"weapon_name": weapon_name,
		"threshold": str(wound_threshold) + "+",
		"rolls_raw": wound_rolls,
		"successes": wounds,
		"overwatch": true,
		"wound_modifier": ow_wound_modifier
	})

	result.wounds = wounds

	if wounds == 0:
		result.log_text = "%s (Overwatch): %d hits, no wounds" % [weapon_name, hits]
		return result

	# --- PHASE 4: Saves and damage (normal rules apply) ---
	var ap = weapon_profile.get("ap", 0)
	# PULSA ROKKIT (OA-31): +1 AP to ranged weapons for the phase
	if shooter_unit.get("flags", {}).get("effect_pulsa_rokkit_active", false):
		var pre_ap_pr = ap
		ap = ap + 1
		print("RulesEngine: Pulsa Rokkit (Overwatch) — ranged AP %d → %d (+1)" % [pre_ap_pr, ap])
	# DRIVE-BY DAKKA (OA-13): Improve AP by 1 for ranged attacks vs targets within 9"
	var ow_dbd_bonus = get_drive_by_dakka_ap_bonus(shooter_unit, target_unit)
	if ow_dbd_bonus > 0:
		var pre_ap_dbd = ap
		ap = ap + ow_dbd_bonus
		print("RulesEngine: Drive-by Dakka (Overwatch) — AP %d → %d (improve by %d, target within 9\")" % [pre_ap_dbd, ap, ow_dbd_bonus])
	# WORSEN AP: Ramshackle etc. — reduce AP of incoming attacks (min 0)
	var ow_worsen_ap = EffectPrimitivesData.get_effect_worsen_ap(target_unit)
	if ow_worsen_ap > 0 and ap > 0:
		var pre_ap = ap
		ap = max(0, ap - ow_worsen_ap)
		print("RulesEngine: Worsen AP (Overwatch) — AP %d → %d (worsen by %d)" % [pre_ap, ap, ow_worsen_ap])
	var damage_raw = weapon_profile.get("damage_raw", str(weapon_profile.get("damage", 1)))
	var base_save = target_unit.get("meta", {}).get("stats", {}).get("save", 7)
	var target_flags = target_unit.get("flags", {})

	# Check IGNORES COVER
	var weapon_ignores_cover = false
	var keywords = weapon_profile.get("keywords", [])
	for kw in keywords:
		if "ignores cover" in kw.to_lower():
			weapon_ignores_cover = true
			break
	if not weapon_ignores_cover:
		var special = weapon_profile.get("special_rules", "").to_lower()
		if "ignores cover" in special:
			weapon_ignores_cover = true
	# Issue #374 Panoptispex: unit-level effect_ignores_cover flag also makes
	# the shooter's ranged weapons IGNORE COVER.
	if not weapon_ignores_cover and shooter_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_IGNORES_COVER, false):
		weapon_ignores_cover = true
		print("RulesEngine: Panoptispex (Overwatch) — unit-level effect_ignores_cover applied")

	var allocation_focus_model_id = null
	var models = target_unit.get("models", [])
	var casualties = 0
	var damage_total = 0

	# Find previously wounded model for allocation
	for i in range(models.size()):
		var model = models[i]
		if model.get("alive", true):
			var max_wounds = model.get("wounds", 1)
			var current_wounds = model.get("current_wounds", max_wounds)
			if current_wounds < max_wounds:
				allocation_focus_model_id = model.get("id", "m%d" % i)
				break

	for wound_idx in range(wounds):
		# Select target model
		var target_model = null
		var target_model_index = -1

		if allocation_focus_model_id:
			for i in range(models.size()):
				var model = models[i]
				if model.get("id", "m%d" % i) == allocation_focus_model_id and model.get("alive", true):
					target_model = model
					target_model_index = i
					break

		if not target_model:
			for i in range(models.size()):
				var model = models[i]
				if model.get("alive", true):
					target_model = model
					target_model_index = i
					allocation_focus_model_id = model.get("id", "m%d" % i)
					break

		if not target_model:
			break  # No more alive models

		# Check cover (terrain or effect-granted)
		var effect_cover = EffectPrimitivesData.has_effect_cover(target_unit)
		var has_cover = false
		if not weapon_ignores_cover:
			has_cover = _check_model_has_cover(target_model, shooter_unit_id, board) or effect_cover

		# MA-12: Per-model save from stats_override (overwatch)
		var ow_model_base_save = _get_model_effective_save(target_model, target_unit, base_save)

		# Check invuln (model native, stats_override, or effect-granted)
		# MA-12: Per-model invuln from stats_override (overwatch)
		var model_invuln = _get_model_effective_invuln(target_model, target_unit, target_model.get("invuln", 0))
		var effect_invuln = EffectPrimitivesData.get_effect_invuln(target_unit)
		if effect_invuln > 0:
			if model_invuln == 0 or effect_invuln < model_invuln:
				model_invuln = effect_invuln

		var save_result = _calculate_save_needed(ow_model_base_save, ap, has_cover, model_invuln, target_unit)

		# T4-18: Read save roll modifier from target unit flags (capped at +1/-1 per 10e)
		var ow_save_modifier = target_unit.get("flags", {}).get("save_modifier", 0)
		ow_save_modifier = clamp(ow_save_modifier, -1, 1)

		# Roll save
		var save_roll = rng.roll_d6(1)[0]
		var saved = false
		# 10e rules: Unmodified save roll of 1 always fails
		if save_roll > 1:
			var ow_effective_roll = save_roll + ow_save_modifier
			if save_result.use_invuln:
				saved = ow_effective_roll >= save_result.inv
			else:
				saved = ow_effective_roll >= save_result.armour
		else:
			print("RulesEngine: [overwatch] Save roll natural 1 — auto-fail (unmodified 1 always fails)")

		if not saved:
			# Roll damage
			var dmg_result = roll_variable_characteristic(damage_raw, rng)
			var dmg = dmg_result.value

			# HALF DAMAGE (T4-17): Halve damage if defender has half-damage ability
			if get_unit_half_damage(target_unit):
				var pre_half = dmg
				dmg = apply_half_damage(dmg)
				print("RulesEngine: Half Damage (Overwatch) — damage %d → %d" % [pre_half, dmg])

			# MINUS DAMAGE (P1-18): Subtract damage reduction (e.g. Guardian Eternal -1 Damage), min 1
			var ow_minus_dmg = EffectPrimitivesData.get_effect_minus_damage(target_unit)
			if ow_minus_dmg > 0:
				var pre_minus = dmg
				dmg = max(1, dmg - ow_minus_dmg)
				print("RulesEngine: Minus Damage (Overwatch) — damage %d → %d (-%d)" % [pre_minus, dmg, ow_minus_dmg])

			# Apply damage
			var current_wounds = target_model.get("current_wounds", target_model.get("wounds", 1))
			var new_wounds = max(0, current_wounds - dmg)

			result.diffs.append({
				"op": "set",
				"path": "units.%s.models.%d.current_wounds" % [target_unit_id, target_model_index],
				"value": new_wounds
			})

			damage_total += dmg

			if new_wounds == 0:
				result.diffs.append({
					"op": "set",
					"path": "units.%s.models.%d.alive" % [target_unit_id, target_model_index],
					"value": false
				})
				casualties += 1
				allocation_focus_model_id = null
				# Mark model as dead in local reference for subsequent wounds
				target_model["alive"] = false
				# MA-22: Log model destruction with model type label
				var ow_label = get_model_display_label(target_model, target_unit)
				print("RulesEngine: 💀 %s destroyed (Overwatch)" % ow_label)
			else:
				target_model["current_wounds"] = new_wounds

	result.casualties = casualties
	result.damage = damage_total
	var ow_log_parts = ["%s (Overwatch)" % weapon_name]
	ow_log_parts.append("Hit: %d/%d [%s] vs 6+" % [hits, total_attacks, ", ".join(hit_rolls.map(func(r): return str(r)))])
	ow_log_parts.append("Wound: %d/%d [%s] vs %s+" % [wounds, hits, ", ".join(wound_rolls.map(func(r): return str(r))), str(wound_threshold)])
	if casualties > 0:
		ow_log_parts.append("%d slain" % casualties)
	elif wounds > 0:
		ow_log_parts.append("all saved")
	result.log_text = " - ".join(ow_log_parts)

	return result

static func _apply_diff_to_board(board: Dictionary, diff: Dictionary) -> void:
	"""Apply a single diff to the board snapshot in-place (for sequential weapon resolution)."""
	var path = diff.get("path", "")
	var value = diff.get("value")
	var parts = path.split(".")

	if parts.size() < 2:
		return

	var current = board
	for i in range(parts.size() - 1):
		var key = parts[i]
		# Handle numeric indices (for model arrays)
		if key.is_valid_int():
			var idx = int(key)
			if current is Array and idx < current.size():
				current = current[idx]
			else:
				return
		elif current is Dictionary and current.has(key):
			current = current[key]
		else:
			return

	var last_key = parts[-1]
	if last_key.is_valid_int():
		var idx = int(last_key)
		if current is Array and idx < current.size():
			current[idx] = value
	elif current is Dictionary:
		current[last_key] = value

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

	# SPLIT-FIRE / PER-MODEL LOS+RANGE: Re-validate eligibility at resolve time.
	# Drops models that became ineligible after the player confirmed targets
	# (deaths, reactive movement, LoS changes).
	if not model_ids.is_empty():
		var filt = _filter_eligible_model_ids(model_ids, actor_unit_id, weapon_id, target_unit_id, board)
		if not filt.dropped.is_empty():
			print("RulesEngine: [SPLIT-FIRE] Dropped %d ineligible model(s) at resolve time for %s → %s: %s (reasons=%s)" % [
				filt.dropped.size(), weapon_id, target_unit_id, str(filt.dropped), str(filt.reasons)
			])
		model_ids = filt.kept
		if model_ids.is_empty():
			result.log_text = "No eligible models in range/LoS for %s → %s" % [weapon_id, target_unit_id]
			return result

	# Issue #387 Waaagh! Energy: 'Eadbanger gains +S/+D per 5 models in led unit
	# (and HAZARDOUS at 10+). Mutates profile when applicable.
	weapon_profile = _apply_waaagh_energy_to_profile(weapon_profile, weapon_id, actor_unit_id, board)

	# Calculate total attacks — roll variable attacks per model (D3, D6, etc.)
	var attacks_raw = weapon_profile.get("attacks_raw", str(weapon_profile.get("attacks", 1)))

	var weapon_name = weapon_profile.get("name", weapon_id)

	# GUN-CRAZY SHOW-OFFS (OA-9): Override snazzgun attacks to 4 when targeting closest eligible enemy
	var gun_crazy_attacks = get_gun_crazy_showoffs_attacks(actor_unit, weapon_id, weapon_profile, actor_unit_id, target_unit_id, board)
	if gun_crazy_attacks > 0:
		attacks_raw = str(gun_crazy_attacks)

	var base_attacks = 0
	var attacks_roll_log = []
	# MA-10: Track per-model BS for each attack (supports stats_override.ballistic_skill)
	var bs_per_attack = []
	var has_bs_override = false

	# DECK FRAGGERS (OA-7): Check if ranged weapons gain BLAST vs INFANTRY targets
	var deck_fraggers_blast = false
	if actor_unit.get("flags", {}).get("effect_deck_fraggers", false):
		if unit_has_keyword(target_unit, "INFANTRY"):
			var wp_type = weapon_profile.get("type", "")
			if wp_type.to_lower() == "ranged" or weapon_profile.get("range", 0) > 0:
				if not is_blast_weapon(weapon_id, board):
					deck_fraggers_blast = true
					print("RulesEngine: DECK FRAGGERS — BLAST granted to %s vs INFANTRY target" % weapon_id)

	# SHOOTY POWER TRIP (OA-37): +1 Attacks to ranged weapons for the phase (D6 roll 5-6)
	var spt_attacks_bonus = 1 if actor_unit.get("flags", {}).get("effect_shooty_power_trip_attacks", false) else 0

	for model_id in model_ids:
		var model = _get_model_by_id(actor_unit, model_id)
		var model_bs = _get_model_effective_bs(model, actor_unit, weapon_profile)
		if model_bs != weapon_profile.get("bs", 4):
			has_bs_override = true

		# Roll variable attacks for each model separately (per 10e rules)
		var attacks_result = roll_variable_characteristic(attacks_raw, rng)
		var model_attacks = attacks_result.value

		# SHOOTY POWER TRIP (OA-37): +1 Attacks per model
		model_attacks += spt_attacks_bonus

		# BLAST KEYWORD (PRP-013): Apply minimum attacks per model for Blast weapons vs 6+ model units
		var effective_model_attacks = calculate_blast_minimum(weapon_id, model_attacks, target_unit, board)
		# DECK FRAGGERS (OA-7): Also apply BLAST minimum if stratagem grants BLAST
		if deck_fraggers_blast:
			var df_model_count = count_alive_models(target_unit)
			if df_model_count >= 6 and model_attacks < 3:
				effective_model_attacks = maxi(effective_model_attacks, 3)
		if effective_model_attacks > model_attacks:
			model_attacks = effective_model_attacks

		base_attacks += model_attacks
		# MA-10: Record this model's BS for each of its attacks
		for _j in range(model_attacks):
			bs_per_attack.append(model_bs)
		if attacks_result.rolled:
			attacks_roll_log.append(attacks_result)

	if spt_attacks_bonus > 0:
		print("RulesEngine: Shooty Power Trip — +1 attack per model (%d models, total base attacks = %d)" % [model_ids.size(), base_attacks])

	if has_bs_override:
		print("RulesEngine: [MA-10] Per-model BS override active — models have different BS values")

	if attacks_roll_log.size() > 0:
		print("RulesEngine: Variable attacks rolled (%s) for %d models → %d total base attacks" % [attacks_raw, model_ids.size(), base_attacks])

	# RAPID FIRE KEYWORD: Check if weapon is Rapid Fire and models are in half range
	# MA-10: Track rapid fire attacks with per-model BS
	# MA-14: Only models in this assignment's model_ids count for RF (per-model weapons)
	var rapid_fire_value = get_rapid_fire_value(weapon_id, board)
	var rapid_fire_attacks = 0
	var models_in_half_range = 0
	if rapid_fire_value > 0:
		var weapon_range = weapon_profile.get("range", 24)
		var half_range_inches = weapon_range / 2.0
		for model_id in model_ids:
			var rf_model = _get_model_by_id(actor_unit, model_id)
			if rf_model.is_empty() or not rf_model.get("alive", true):
				continue
			var closest_distance_inches = INF
			for target_model in target_unit.get("models", []):
				if not target_model.get("alive", true):
					continue
				var edge_distance_px = Measurement.model_to_model_distance_px(rf_model, target_model)
				var edge_distance_inches = Measurement.px_to_inches(edge_distance_px)
				closest_distance_inches = min(closest_distance_inches, edge_distance_inches)
			if closest_distance_inches <= half_range_inches:
				models_in_half_range += 1
				var rf_model_bs = _get_model_effective_bs(rf_model, actor_unit, weapon_profile)
				for _j in range(rapid_fire_value):
					bs_per_attack.append(rf_model_bs)
		rapid_fire_attacks = models_in_half_range * rapid_fire_value
		print("RulesEngine: [MA-14] Rapid Fire %d — %d/%d assigned models in half range (+%d attacks)" % [rapid_fire_value, models_in_half_range, model_ids.size(), rapid_fire_attacks])

	# BLAST KEYWORD (PRP-013): Add bonus attacks based on target unit size
	# Per 10e rules, Blast adds to the Attacks characteristic per model
	var blast_bonus_per_model = calculate_blast_bonus(weapon_id, target_unit, board)
	# DECK FRAGGERS (OA-7): Also add BLAST bonus attacks if stratagem grants BLAST
	if deck_fraggers_blast:
		var df_target_count = count_alive_models(target_unit)
		blast_bonus_per_model += int(df_target_count / 5)
	var blast_bonus_attacks = blast_bonus_per_model * model_ids.size()
	var target_model_count = count_alive_models(target_unit)
	# MA-10: Blast bonus attacks use weapon's default BS (not model-specific)
	var default_bs = weapon_profile.get("bs", 4)
	for _j in range(blast_bonus_attacks):
		bs_per_attack.append(default_bs)

	var total_attacks = base_attacks + rapid_fire_attacks + blast_bonus_attacks
	if assignment.has("attacks_override") and assignment.attacks_override != null:
		total_attacks = assignment.attacks_override
		rapid_fire_attacks = 0  # Override disables the rapid fire bonus tracking
		blast_bonus_attacks = 0  # Override disables the blast bonus tracking
		# MA-10: Rebuild bs_per_attack with default BS when attacks are overridden
		bs_per_attack.clear()
		for _j in range(total_attacks):
			bs_per_attack.append(default_bs)

	# MA-29: ABILITY ATTACK BONUS — Check for weapon-targeted +X Attacks from abilities
	var ability_attack_bonus = 0
	if EffectPrimitivesData.has_effect_plus_attacks(actor_unit):
		var bonus_value = EffectPrimitivesData.get_effect_plus_attacks(actor_unit)
		if EffectPrimitivesData.effect_applies_to_weapon(actor_unit, EffectPrimitivesData.FLAG_PLUS_ATTACKS, weapon_name):
			ability_attack_bonus = bonus_value * model_ids.size()  # Per-model bonus
			total_attacks += ability_attack_bonus
			# Add BS entries for the bonus attacks (use per-model BS)
			for ab_model_id in model_ids:
				var bonus_model = _get_model_by_id(actor_unit, ab_model_id)
				var bonus_bs = _get_model_effective_bs(bonus_model, actor_unit, weapon_profile)
				for _j in range(bonus_value):
					bs_per_attack.append(bonus_bs)
			print("RulesEngine: [MA-29] Ability +%d Attacks for '%s' → +%d total (%d models × %d)" % [bonus_value, weapon_name, ability_attack_bonus, model_ids.size(), bonus_value])
		else:
			print("RulesEngine: [MA-29] Ability +%d Attacks exists but does not apply to '%s' (weapon filter active)" % [bonus_value, weapon_name])

	# TORRENT KEYWORD (PRP-014): Check if weapon auto-hits (skip hit roll entirely)
	var is_torrent = is_torrent_weapon(weapon_id, board) or assignment.get("torrent", false)

	# INDIRECT FIRE (T2-4): Check if weapon has Indirect Fire keyword
	var is_indirect_fire = has_indirect_fire(weapon_id, board)

	# CONVERSION X+ (T4-16): Check if weapon has Conversion ability
	# Expands critical hit range when firing at targets 12"+ away
	var critical_hit_threshold = get_critical_hit_threshold(weapon_id, actor_unit, target_unit, model_ids, board)

	# Variables that need to be declared for both paths
	var bs = weapon_profile.get("bs", 4)
	var is_overwatch = assignment.get("overwatch", false)

	# T3-11: FIRE OVERWATCH — only unmodified 6s hit (set BS to 7 so only the
	# auto-hit on natural 6 rule applies; modifiers and rerolls still function
	# normally but cannot lower the threshold below the unmodified-6 check)
	if is_overwatch:
		bs = 7
		# MA-10: Override all per-model BS to 7 for overwatch
		for i in range(bs_per_attack.size()):
			bs_per_attack[i] = 7
		print("RulesEngine: [OVERWATCH] Forcing BS=7 — only unmodified 6s will hit")

	var hits = 0
	var critical_hits = 0  # Unmodified rolls >= critical_hit_threshold (never for Torrent)
	var regular_hits = 0   # Non-critical hits
	var hit_modifiers = HitModifier.NONE
	var heavy_bonus_applied = false
	var bgnt_penalty_applied = false
	var indirect_fire_applied = false
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
		# ADVANCED FIREPOWER (P1-16): Conditional Lethal Hits based on weapon/target type
		if not weapon_has_lethal_hits:
			weapon_has_lethal_hits = check_advanced_firepower_lethal_hits(weapon_id, actor_unit, target_unit, board)
		sustained_data = get_sustained_hits_value(weapon_id, board)

		result.dice.append({
			"context": "auto_hit",  # Special context for Torrent
			"torrent_weapon": true,
			"total_attacks": total_attacks,
			"successes": hits,
			"message": "Torrent: %d automatic hits" % hits,
			# Variable attacks tracking
			"variable_attacks": attacks_roll_log.size() > 0,
			"attacks_notation": attacks_raw if attacks_roll_log.size() > 0 else "",
			"attacks_rolls": attacks_roll_log,
			# Still track these for completeness, but they won't trigger
			"lethal_hits_weapon": weapon_has_lethal_hits,
			"sustained_hits_weapon": sustained_data.value > 0,
			"sustained_hits_note": "N/A - no hit roll for Torrent",
			# BLAST (PRP-013)
			"blast_weapon": is_blast_weapon(weapon_id, board) or deck_fraggers_blast,
			"blast_bonus_attacks": blast_bonus_attacks,
			"target_model_count": target_model_count,
			"base_attacks": base_attacks,
			"rapid_fire_bonus": rapid_fire_attacks,
			"rapid_fire_value": rapid_fire_value,
			"models_in_half_range": models_in_half_range,
			"deck_fraggers_blast": deck_fraggers_blast
		})
	else:
		# Normal hit roll path (non-Torrent weapons)
		# Get hit modifiers
		if assignment.has("modifiers") and assignment.modifiers.has("hit"):
			var hit_mods = assignment.modifiers.hit
			if hit_mods.get("reroll_ones", false):
				hit_modifiers |= HitModifier.REROLL_ONES
			if hit_mods.get("reroll_failed", false):
				hit_modifiers |= HitModifier.REROLL_FAILED
			if hit_mods.get("plus_one", false):
				hit_modifiers |= HitModifier.PLUS_ONE
			if hit_mods.get("minus_one", false):
				hit_modifiers |= HitModifier.MINUS_ONE

		# OATH OF MOMENT (Codex): Re-roll all hit rolls when ADEPTUS ASTARTES attacks oath target
		if FactionAbilityManager.attacker_benefits_from_oath(actor_unit, target_unit):
			hit_modifiers |= HitModifier.REROLL_FAILED
			print("RulesEngine: OATH OF MOMENT — re-roll all failed hits against %s" % target_unit_id)

		# EFFECT FLAGS: Check for ability/stratagem-granted hit modifiers on the attacker
		if EffectPrimitivesData.has_effect_plus_one_hit(actor_unit):
			hit_modifiers |= HitModifier.PLUS_ONE
			print("RulesEngine: Effect +1 to hit applied for %s" % actor_unit_id)
		if EffectPrimitivesData.has_effect_minus_one_hit(actor_unit):
			hit_modifiers |= HitModifier.MINUS_ONE
			print("RulesEngine: Effect -1 to hit applied for %s" % actor_unit_id)
		var reroll_hits_scope = actor_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_REROLL_HITS, "")
		if reroll_hits_scope == "ones":
			hit_modifiers |= HitModifier.REROLL_ONES
			print("RulesEngine: Effect re-roll 1s to hit applied for %s" % actor_unit_id)
		elif reroll_hits_scope == "failed":
			hit_modifiers |= HitModifier.REROLL_FAILED
			print("RulesEngine: Effect re-roll failed hits applied for %s" % actor_unit_id)
		elif reroll_hits_scope == "all":
			hit_modifiers |= HitModifier.REROLL_FAILED
			print("RulesEngine: Effect re-roll all hits applied for %s" % actor_unit_id)

		# DAMAGED PROFILE (P1-14): Check if attacker has Damaged profile active
		if is_damaged_profile_active(actor_unit):
			hit_modifiers |= HitModifier.MINUS_ONE
			print("RulesEngine: Damaged profile -1 to hit applied for %s" % actor_unit_id)

		# HEAVY KEYWORD: Check if weapon is Heavy and unit remained stationary
		# (at edition>=11 [HEAVY] routes through ModifierStack below — 24.16)
		if GameConstants.edition < 11 and is_heavy_weapon(weapon_id, board):
			var remained_stationary = actor_unit.get("flags", {}).get("remained_stationary", false)
			if remained_stationary:
				hit_modifiers |= HitModifier.PLUS_ONE
				heavy_bonus_applied = true

		# BIG GUNS NEVER TIRE: Apply -1 to hit for non-Pistol weapons only when shooter
		# is engaged OR target is engaged with a friendly unit (issue #337). Eligibility
		# is gated by the new two-arg helper rather than the buggy unit-only check.
		# (10e only — 11e replaces BGNT with close-quarters shooting 10.06 +
		# engaged-M/V targeting 17.03, applied via ModifierStack below)
		if GameConstants.edition < 11 and big_guns_never_tire_penalty_applies(actor_unit, target_unit, board):
			# Only apply penalty if this is NOT a Pistol weapon
			if not is_pistol_weapon(weapon_id, board):
				hit_modifiers |= HitModifier.MINUS_ONE
				bgnt_penalty_applied = true
				print("RulesEngine: BGNT -1 to hit applied for %s (weapon %s)" % [actor_unit_id, weapon_id])

		# STEALTH (T2-1): Check if target unit has Stealth (from effect or base ability)
		# Stealth imposes -1 to hit rolls against this unit for ranged attacks
		if GameConstants.edition < 11 and EffectPrimitivesData.has_effect_stealth(target_unit):
			hit_modifiers |= HitModifier.MINUS_ONE
			print("RulesEngine: Stealth (effect-granted) applied -1 to hit against %s" % target_unit_id)
		elif GameConstants.edition < 11 and has_stealth_ability(target_unit):
			hit_modifiers |= HitModifier.MINUS_ONE
			print("RulesEngine: Stealth (ability) applied -1 to hit against %s" % target_unit_id)

		# INDIRECT FIRE (T2-4): Apply -1 to hit modifier for Indirect Fire weapons
		# Issue #371: per 10e RAW, the -1 penalty + Benefit of Cover only apply
		# when the target is NOT visible to any model in the firing unit.
		var indirect_target_visible = is_indirect_fire and _has_los_to_target_unit(actor_unit_id, target_unit_id, board)
		if is_indirect_fire and not indirect_target_visible:
			hit_modifiers |= HitModifier.MINUS_ONE
			indirect_fire_applied = true
			print("RulesEngine: [INDIRECT FIRE] Applied -1 to hit for weapon '%s' (target not visible)" % weapon_profile.get("name", weapon_id))
		elif is_indirect_fire and indirect_target_visible:
			print("RulesEngine: [INDIRECT FIRE] No penalty — target IS visible to firing unit")

		# TANK HUNTERS (OA-11): +1 to Hit when attacking MONSTER or VEHICLE targets
		if has_tank_hunters_vs_target(actor_unit, target_unit):
			hit_modifiers |= HitModifier.PLUS_ONE
			print("RulesEngine: TANK HUNTERS — +1 to hit for %s (target is MONSTER/VEHICLE)" % actor_unit_id)

		# MEKANIAK (OA-34): +1 to Hit for vehicles buffed by Mek at end of Movement phase
		if UnitAbilityManager.has_mekaniak_buff(actor_unit):
			hit_modifiers |= HitModifier.PLUS_ONE
			print("RulesEngine: MEKANIAK — +1 to hit for %s (Mek-buffed vehicle)" % actor_unit_id)

		# WALL OF DAKKA (OA-50): +1 to Hit on ranged attacks vs targets within half weapon range (Bonebreaka)
		var wall_of_dakka_bonus = get_wall_of_dakka_hit_bonus(actor_unit, target_unit, weapon_profile)
		if wall_of_dakka_bonus > 0:
			hit_modifiers |= HitModifier.PLUS_ONE
			print("RulesEngine: WALL OF DAKKA — +1 to hit for %s (target within half range)" % actor_unit_id)

		# BIG AN' SHOOTY (OA-41): +1 to Hit for ranged attacks while Waaagh! active (Morkanaut)
		if UnitAbilityManager.has_big_an_shooty(actor_unit):
			hit_modifiers |= HitModifier.PLUS_ONE
			print("RulesEngine: BIG AN' SHOOTY — +1 to hit (ranged) for %s (Waaagh! active)" % actor_unit_id)

		# DAT'S OUR LOOT! (OA-12): Re-roll Hit rolls of 1 on ranged attacks;
		# full Hit re-roll if target is within range of any objective marker.
		var dats_our_loot_scope = get_dats_our_loot_reroll_scope(actor_unit, target_unit, board)
		if dats_our_loot_scope == "failed":
			hit_modifiers |= HitModifier.REROLL_FAILED
			print("RulesEngine: DAT'S OUR LOOT! — full hit re-roll for %s (target near objective)" % actor_unit_id)
		elif dats_our_loot_scope == "ones":
			hit_modifiers |= HitModifier.REROLL_ONES
			print("RulesEngine: DAT'S OUR LOOT! — re-roll hit rolls of 1 for %s" % actor_unit_id)

		# SPLAT! (OA-38): Re-roll Hit rolls of 1 on ranged attacks when conditions met.
		# Big Gunz: target has 10+ models. Mek Gunz: at Starting Strength vs non-MONSTER/VEHICLE.
		var splat_scope = get_splat_reroll_scope(actor_unit, target_unit)
		if splat_scope == "ones":
			hit_modifiers |= HitModifier.REROLL_ONES
			print("RulesEngine: SPLAT! — re-roll hit rolls of 1 for %s" % actor_unit_id)

		# BLASTAJET ATTACK RUN (OA-40): Re-roll Hit rolls of 1 when targeting non-FLY units.
		var blastajet_scope = get_blastajet_attack_run_reroll_scope(actor_unit, target_unit)
		if blastajet_scope == "ones":
			hit_modifiers |= HitModifier.REROLL_ONES
			print("RulesEngine: BLASTAJET ATTACK RUN — re-roll hit rolls of 1 for %s" % actor_unit_id)

		# XENOS HUNTER: +1 to Hit vs non-IMPERIUM/CHAOS targets (Inquisitor Draxus while leading)
		if has_xenos_hunter_vs_target(actor_unit, target_unit):
			hit_modifiers |= HitModifier.PLUS_ONE
			print("RulesEngine: XENOS HUNTER — +1 to hit for %s (target lacks IMPERIUM/CHAOS)" % actor_unit_id)

		# AGAINST ALL ODDS: +1 to Hit when no friendly units within 6" (Lions of the Emperor)
		if FactionAbilityManager.check_against_all_odds(actor_unit, board):
			hit_modifiers |= HitModifier.PLUS_ONE
			print("RulesEngine: AGAINST ALL ODDS — +1 to hit for %s (no friendlies within 6\")" % actor_unit_id)

		# CAPTAIN-GENERAL: Ignore all numeric hit modifiers (Trajann while leading)
		if has_captain_general(actor_unit):
			hit_modifiers = hit_modifiers & ~(HitModifier.PLUS_ONE | HitModifier.MINUS_ONE)
			print("RulesEngine: CAPTAIN-GENERAL — ignoring all hit roll modifiers for %s" % actor_unit_id)

		# ── ISS-016/053 (11e): hit-side modifier stack — cover/STEALTH worsen
		# BS (13.08/24.33), plunging fire improves it (22.05), [HEAVY] is +1
		# to the hit roll (24.16). The ±1 dice-roll cap lives in ModifierStack.
		if GameConstants.edition >= 11 and not is_overwatch:
			var ms_firing_models: Array = []
			for ms_mid in model_ids:
				var ms_m = _get_model_by_id(actor_unit, ms_mid)
				if not ms_m.is_empty() and ms_m.get("alive", true):
					ms_firing_models.append(ms_m)
			var ms_stack = ModifierStack.collect_hit_context_11e(actor_unit, target_unit, weapon_profile, board, {"attacker_models": ms_firing_models})
			var ms_bs_delta = ms_stack.net("bs")
			var ms_hit_net_pre = ms_stack.net("hit_roll")
			# ISS-047 (24.29): [PSYCHIC] attacks may ignore any or all BS/hit
			# modifiers — the engine ignores exactly the harmful ones.
			if is_psychic_weapon(weapon_id, board):
				if ms_bs_delta > 0:
					print("RulesEngine: [24.29] PSYCHIC — ignoring BS worsening (%+d)" % ms_bs_delta)
					ms_bs_delta = 0
				if ms_hit_net_pre < 0:
					print("RulesEngine: [24.29] PSYCHIC — ignoring hit-roll penalty (%+d)" % ms_hit_net_pre)
					ms_hit_net_pre = 0
			if ms_bs_delta != 0:
				bs += ms_bs_delta
				for ms_i in range(bs_per_attack.size()):
					bs_per_attack[ms_i] += ms_bs_delta
				print("RulesEngine: [11e MODIFIERS] BS %+d (%s)" % [ms_bs_delta, str(ms_stack.sources("bs"))])
			var ms_hit_net = ms_hit_net_pre
			if ms_hit_net > 0:
				hit_modifiers |= HitModifier.PLUS_ONE
				if "heavy" in ms_stack.sources("hit_roll"):
					heavy_bonus_applied = true
				print("RulesEngine: [11e MODIFIERS] +1 to hit (%s)" % str(ms_stack.sources("hit_roll")))
			elif ms_hit_net < 0:
				hit_modifiers |= HitModifier.MINUS_ONE
				print("RulesEngine: [11e MODIFIERS] -1 to hit (%s)" % str(ms_stack.sources("hit_roll")))

		# Roll to hit - CRITICAL HIT TRACKING (PRP-031)
		hit_rolls = rng.roll_d6(total_attacks)

		# ISS-012: per-roll evaluation shared with the melee path
		# (AttackSequence.evaluate_hit_roll). INDIRECT FIRE's unmodified-1-3
		# fail band (#371, unseen targets only) and CONVERSION's crit
		# threshold (T4-16) are parameters.
		var hit_fail_band = 3 if (is_indirect_fire and not indirect_target_visible) else 1
		for i in range(hit_rolls.size()):
			var roll = hit_rolls[i]
			# MA-10: Use per-model BS for this attack's threshold
			var attack_bs = bs_per_attack[i] if i < bs_per_attack.size() else bs
			var hit_eval = AttackSequence.evaluate_hit_roll(roll, attack_bs, hit_modifiers, critical_hit_threshold, rng, hit_fail_band)
			modified_rolls.append(hit_eval.final_roll)
			if hit_eval.rerolled:
				reroll_data.append({
					"original": hit_eval.reroll_from,
					"rerolled_to": hit_eval.reroll_to
				})
			if hit_eval.is_hit:
				hits += 1
				if hit_eval.is_crit:
					critical_hits += 1
				else:
					regular_hits += 1

		# DAKKASTORM (OA-16): Every successful Hit roll scores a Critical Hit (ranged only)
		if has_dakkastorm(actor_unit) and regular_hits > 0:
			print("RulesEngine: DAKKASTORM — converting %d regular hits to critical hits for %s" % [regular_hits, actor_unit_id])
			critical_hits += regular_hits
			regular_hits = 0

		# Check for Lethal Hits keyword
		weapon_has_lethal_hits = has_lethal_hits(weapon_id, board)
		# ADVANCED FIREPOWER (P1-16): Conditional Lethal Hits based on weapon/target type
		if not weapon_has_lethal_hits:
			weapon_has_lethal_hits = check_advanced_firepower_lethal_hits(weapon_id, actor_unit, target_unit, board)
		# OA-10: Ammo Runt / unit effect flags — Lethal Hits from abilities or stratagems (ranged)
		if not weapon_has_lethal_hits and EffectPrimitivesData.has_effect_lethal_hits(actor_unit):
			weapon_has_lethal_hits = true
			print("RulesEngine:   LETHAL HITS granted by unit effect flag (e.g., Ammo Runt)")

		# SUSTAINED HITS (PRP-011): Generate bonus hits on critical hits
		sustained_data = get_sustained_hits_value(weapon_id, board)

		# HERE BE LOOT (OA-1): Freebooter Krew — Sustained Hits 1 near loot objective (ranged)
		if sustained_data.value == 0 and FactionAbilityManager.check_here_be_loot_sustained_hits(actor_unit, target_unit, board):
			sustained_data = {"value": 1, "is_dice": false}
			print("RulesEngine:   SUSTAINED HITS 1 granted by Here Be Loot (Freebooter Krew detachment)")

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
			"indirect_fire_applied": indirect_fire_applied,
			"rapid_fire_bonus": rapid_fire_attacks,
			"rapid_fire_value": rapid_fire_value,
			"models_in_half_range": models_in_half_range,
			"base_attacks": base_attacks,
			"successes": hits,
			# CRITICAL HIT TRACKING (PRP-031)
			"critical_hits": critical_hits,
			"regular_hits": regular_hits,
			"lethal_hits_weapon": weapon_has_lethal_hits,
			# CONVERSION X+ (T4-16)
			"conversion_active": critical_hit_threshold < 6,
			"critical_hit_threshold": critical_hit_threshold,
			# SUSTAINED HITS (PRP-011)
			"sustained_hits_weapon": sustained_data.value > 0,
			"sustained_hits_value": sustained_data.value,
			"sustained_hits_is_dice": sustained_data.is_dice,
			"sustained_bonus_hits": sustained_bonus_hits,
			"sustained_rolls": sustained_result.rolls,
			"total_hits_for_wounds": total_hits_for_wounds,
			# Variable attacks tracking
			"variable_attacks": attacks_roll_log.size() > 0,
			"attacks_notation": attacks_raw if attacks_roll_log.size() > 0 else "",
			"attacks_rolls": attacks_roll_log,
			# BLAST (PRP-013)
			"blast_weapon": is_blast_weapon(weapon_id, board) or deck_fraggers_blast,
			"blast_bonus_attacks": blast_bonus_attacks,
			"target_model_count": target_model_count,
			"deck_fraggers_blast": deck_fraggers_blast,
			# DAKKASTORM (OA-16)
			"dakkastorm_active": has_dakkastorm(actor_unit)
		})

	if hits == 0 and sustained_bonus_hits == 0:
		var miss_weapon_name = weapon_profile.get("name", weapon_id)
		var miss_log = "%s → %s with %s - No hits" % [actor_unit.get("meta", {}).get("name", actor_unit_id), target_unit.get("meta", {}).get("name", target_unit_id), miss_weapon_name]
		if not hit_rolls.is_empty():
			miss_log += " [%s] vs %s+" % [", ".join(hit_rolls.map(func(r): return str(r))), str(bs)]
		result.log_text = miss_log
		return result

	# Roll to wound - LETHAL HITS (PRP-010) + SUSTAINED HITS (PRP-011) + DEVASTATING WOUNDS (PRP-012)
	# TORRENT (PRP-014): Torrent weapons skip hit roll but still roll to wound normally
	var strength = weapon_profile.get("strength", 4)
	# PULSA ROKKIT (OA-31): +1 Strength to ranged weapons for the phase
	if actor_unit.get("flags", {}).get("effect_pulsa_rokkit_active", false):
		var pre_s_pr = strength
		strength += 1
		print("RulesEngine: Pulsa Rokkit — ranged strength %d → %d (+1)" % [pre_s_pr, strength])
	# SHOOTY POWER TRIP (OA-37): +1 Strength to ranged weapons for the phase (D6 roll 3-4)
	if actor_unit.get("flags", {}).get("effect_shooty_power_trip_strength", false):
		var pre_s_spt = strength
		strength += 1
		print("RulesEngine: Shooty Power Trip — ranged strength %d → %d (+1)" % [pre_s_spt, strength])
	var toughness = _get_attached_unit_toughness(target_unit, board)  # P2-90: Use bodyguard T for attached units
	# OA-44: DED GLOWY AMMO — -1T to enemy INFANTRY within 6" of Kaptin Badrukk
	var ded_glowy_penalty = get_ded_glowy_ammo_toughness_penalty(target_unit, board)
	if ded_glowy_penalty > 0:
		toughness = max(1, toughness - ded_glowy_penalty)
		print("RulesEngine: DED GLOWY AMMO — INFANTRY target T reduced by %d to T%d" % [ded_glowy_penalty, toughness])
	# OA-48: RUNTHERD — Runtherds revert to T4 when all Gretchin are dead
	var runtherd_t_override = get_runtherd_toughness_override(target_unit)
	if runtherd_t_override > 0:
		toughness = runtherd_t_override
		print("RulesEngine: RUNTHERD — all Gretchin dead, Runtherd T overridden to T%d" % toughness)
	var wound_threshold = _calculate_wound_threshold(strength, toughness)

	# DEVASTATING WOUNDS (PRP-012): Check if weapon has Devastating Wounds
	var weapon_has_devastating_wounds = has_devastating_wounds(weapon_id, board)
	# Issue #374 Headwoppa's Killchoppa: unit-level effect_devastating_wounds
	# grants DEVASTATING WOUNDS to the bearer's melee weapons. Apply at the
	# unit level here.
	if not weapon_has_devastating_wounds and actor_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_DEVASTATING_WOUNDS, false):
		weapon_has_devastating_wounds = true
		print("RulesEngine: Headwoppa's Killchoppa — unit-level effect_devastating_wounds applied (until-wounds path)")

	# PURITY OF EXECUTION: Ranged attacks vs PSYKER gain [DEVASTATING WOUNDS]
	var purity_of_execution_active = has_purity_of_execution_vs_target(actor_unit, target_unit)
	if purity_of_execution_active:
		weapon_has_devastating_wounds = true
		print("RulesEngine: PURITY OF EXECUTION — Devastating Wounds vs PSYKER target %s" % target_unit_id)

	# ANTI-[KEYWORD] X+: Get critical wound threshold (6 normally, lower if Anti matches target)
	var critical_wound_threshold = get_critical_wound_threshold(weapon_id, target_unit, board)

	# ROLLING LOOT-HEAP (OA-6): Grant Anti-Vehicle 4+ from stratagem flag
	if actor_unit.get("flags", {}).get("effect_rolling_loot_heap", false):
		if unit_has_keyword(target_unit, "VEHICLE"):
			critical_wound_threshold = mini(critical_wound_threshold, 4)
			print("RulesEngine: ROLLING LOOT-HEAP — Anti-Vehicle 4+ active (critical wound threshold %d+)" % critical_wound_threshold)

	var anti_keyword_active = critical_wound_threshold < 6

	# TWIN-LINKED: Check if weapon has Twin-linked (re-roll all failed wound rolls)
	var weapon_has_twin_linked = has_twin_linked(weapon_id, board) or assignment.get("twin_linked", false)

	# WOUND MODIFIERS (T1-3): Build wound modifier flags from assignment and game state
	var wound_modifiers = WoundModifier.NONE
	if assignment.has("modifiers") and assignment.modifiers.has("wound"):
		var wound_mods = assignment.modifiers.wound
		if wound_mods.get("reroll_ones", false):
			wound_modifiers |= WoundModifier.REROLL_ONES
		if wound_mods.get("reroll_failed", false):
			wound_modifiers |= WoundModifier.REROLL_FAILED
		if wound_mods.get("plus_one", false):
			wound_modifiers |= WoundModifier.PLUS_ONE
		if wound_mods.get("minus_one", false):
			wound_modifiers |= WoundModifier.MINUS_ONE
	# Twin-linked handled via WoundModifier system for re-rolls
	if weapon_has_twin_linked:
		wound_modifiers |= WoundModifier.REROLL_FAILED

	# OATH OF MOMENT (Codex): +1 to wound when ADEPTUS ASTARTES attacks oath target
	if FactionAbilityManager.attacker_benefits_from_oath(actor_unit, target_unit):
		wound_modifiers |= WoundModifier.PLUS_ONE
		print("RulesEngine: OATH OF MOMENT — +1 to wound against %s" % target_unit_id)

	# EFFECT FLAGS: Check for ability/stratagem-granted wound modifiers on the attacker
	if EffectPrimitivesData.has_effect_plus_one_wound(actor_unit):
		wound_modifiers |= WoundModifier.PLUS_ONE
		print("RulesEngine: Effect +1 to wound applied for %s" % actor_unit_id)
	if EffectPrimitivesData.has_effect_minus_one_wound(actor_unit):
		wound_modifiers |= WoundModifier.MINUS_ONE
		print("RulesEngine: Effect -1 to wound applied for %s" % actor_unit_id)
	var reroll_wounds_scope = actor_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_REROLL_WOUNDS, "")
	if reroll_wounds_scope == "ones":
		wound_modifiers |= WoundModifier.REROLL_ONES
		print("RulesEngine: Effect re-roll 1s to wound applied for %s" % actor_unit_id)
	elif reroll_wounds_scope == "failed":
		wound_modifiers |= WoundModifier.REROLL_FAILED
		print("RulesEngine: Effect re-roll failed wounds applied for %s" % actor_unit_id)
	elif reroll_wounds_scope == "all":
		wound_modifiers |= WoundModifier.REROLL_FAILED
		print("RulesEngine: Effect re-roll all wounds applied for %s" % actor_unit_id)

	# LANCE (T4-1): +1 to wound if unit charged this turn
	if is_lance_weapon(weapon_id, board):
		var unit_charged = actor_unit.get("flags", {}).get("charged_this_turn", false)
		if unit_charged:
			wound_modifiers |= WoundModifier.PLUS_ONE
			print("RulesEngine: LANCE — +1 to wound (unit charged this turn)")

	# TANK HUNTERS (OA-11): +1 to Wound when attacking MONSTER or VEHICLE targets
	if has_tank_hunters_vs_target(actor_unit, target_unit):
		wound_modifiers |= WoundModifier.PLUS_ONE
		print("RulesEngine: TANK HUNTERS — +1 to wound for %s (target is MONSTER/VEHICLE)" % actor_unit_id)

	# DA BOSS' LADZ (OA-15): -1 to incoming Wound rolls when S > T and Warboss leads target unit
	var da_boss_ladz_mod = get_da_boss_ladz_wound_modifier(target_unit, board, strength, toughness)
	if da_boss_ladz_mod != WoundModifier.NONE:
		wound_modifiers |= da_boss_ladz_mod
		print("RulesEngine: DA BOSS' LADZ — -1 to wound for attacks against %s (S %d > T %d, Warboss leading)" % [target_unit_id, strength, toughness])
	# PYROMANIAKS (OA-14): Re-roll Wound rolls of 1 with Torrent weapons vs enemies within 6"
	# Full Wound re-roll if target is also within range of an objective marker.
	var pyromaniaks_scope = get_pyromaniaks_reroll_scope(actor_unit, target_unit, weapon_id, board)
	if pyromaniaks_scope == "failed":
		wound_modifiers |= WoundModifier.REROLL_FAILED
		print("RulesEngine: PYROMANIAKS — full wound re-roll for %s (Torrent weapon, target within 6\" AND near objective)" % actor_unit_id)
	elif pyromaniaks_scope == "ones":
		wound_modifiers |= WoundModifier.REROLL_ONES
		print("RulesEngine: PYROMANIAKS — re-roll wound rolls of 1 for %s (Torrent weapon, target within 6\")" % actor_unit_id)

	# SLAYERS OF TYRANTS: Re-roll Wound rolls vs CHARACTER/MONSTER/VEHICLE
	if has_slayers_of_tyrants_vs_target(actor_unit, target_unit):
		wound_modifiers |= WoundModifier.REROLL_FAILED
		print("RulesEngine: SLAYERS OF TYRANTS — re-roll wound rolls for %s (target is CHARACTER/MONSTER/VEHICLE)" % actor_unit_id)

	# AGAINST ALL ODDS: +1 to Wound when no friendly units within 6" (Lions of the Emperor)
	if FactionAbilityManager.check_against_all_odds(actor_unit, board):
		wound_modifiers |= WoundModifier.PLUS_ONE
		print("RulesEngine: AGAINST ALL ODDS — +1 to wound for %s (no friendlies within 6\")" % actor_unit_id)

	var wound_modifier_net = 0
	if wound_modifiers & WoundModifier.PLUS_ONE:
		wound_modifier_net += 1
	if wound_modifiers & WoundModifier.MINUS_ONE:
		wound_modifier_net -= 1
	wound_modifier_net = clamp(wound_modifier_net, -1, 1)

	if wound_modifier_net != 0:
		print("RulesEngine: Wound modifier net = %+d (capped at +1/-1)" % wound_modifier_net)

	# LETHAL HITS + SUSTAINED HITS + DEVASTATING WOUNDS + ANTI-KEYWORD + TWIN-LINKED interaction:
	# - Critical hits with Lethal Hits auto-wound (no roll needed) - NOT for Torrent (no crits)
	# - Bonus hits from Sustained Hits always roll to wound (even if weapon has Lethal Hits) - NOT for Torrent (no crits)
	# - Regular (non-critical) hits always roll to wound
	# - Critical wounds (unmodified X+ to wound per Anti threshold, or 6s normally) with Devastating Wounds bypass saves
	# - ANTI-[KEYWORD] X+: Critical wounds on X+ vs matching keyword targets; critical wounds always succeed
	# - Twin-linked: Re-roll all failed wound rolls (via WoundModifier system)
	# - Wound modifiers: +1/-1 cap applied to each roll; unmodified 1 always fails
	var auto_wounds = 0  # From Lethal Hits (never for Torrent)
	var wounds_from_rolls = 0
	var wound_rolls = []
	var critical_wound_count = 0  # Critical wounds: unmodified X+ (Anti) or 6s (default)
	var regular_wound_count = 0   # Non-critical wounds
	var wound_reroll_data = []  # Track twin-linked / modifier re-rolls

	# TORRENT (PRP-014): Since Torrent has no crits, Lethal Hits never triggers
	# All hits must roll to wound normally
	if weapon_has_lethal_hits and not is_torrent and lethal_hits_auto_wound_11e(weapon_id, board, assignment):
		# Critical hits automatically wound - no roll needed
		auto_wounds = critical_hits
		# Per 10e rules, Lethal Hits auto-wounds are NOT critical wounds for Devastating Wounds
		# Critical wounds for DW require unmodified 6 (or Anti threshold) on the WOUND roll

		# Roll wounds for: regular hits + sustained bonus hits
		var hits_to_roll = regular_hits + sustained_bonus_hits
		if hits_to_roll > 0:
			wound_rolls = rng.roll_d6(hits_to_roll)
			for roll in wound_rolls:
				# ISS-012: shared per-roll evaluation (AttackSequence.evaluate_wound_roll)
				var wound_eval = AttackSequence.evaluate_wound_roll(roll, wound_modifiers, wound_threshold, critical_wound_threshold, rng)
				if wound_eval.rerolled:
					wound_reroll_data.append({"original": wound_eval.reroll_from, "rerolled_to": wound_eval.reroll_to})
				if wound_eval.auto_fail:
					continue
				if wound_eval.is_wound:
					wounds_from_rolls += 1
					if weapon_has_devastating_wounds and wound_eval.is_crit:
						critical_wound_count += 1
					else:
						regular_wound_count += 1

		# Lethal Hits auto-wounds go to regular wounds (not critical wounds for DW)
		regular_wound_count += auto_wounds
	else:
		# Normal processing - all hits (including sustained bonus) roll to wound
		wound_rolls = rng.roll_d6(total_hits_for_wounds)
		for roll in wound_rolls:
			# ISS-012: shared per-roll evaluation (AttackSequence.evaluate_wound_roll)
			var wound_eval = AttackSequence.evaluate_wound_roll(roll, wound_modifiers, wound_threshold, critical_wound_threshold, rng)
			if wound_eval.rerolled:
				wound_reroll_data.append({"original": wound_eval.reroll_from, "rerolled_to": wound_eval.reroll_to})
			if wound_eval.auto_fail:
				continue
			if wound_eval.is_wound:
				wounds_from_rolls += 1
				if weapon_has_devastating_wounds and wound_eval.is_crit:
					critical_wound_count += 1
				else:
					regular_wound_count += 1

	var wounds_caused = auto_wounds + wounds_from_rolls

	if anti_keyword_active:
		print("RulesEngine: ANTI-KEYWORD active — critical wound threshold %d+ (normal wound threshold %d+)" % [critical_wound_threshold, wound_threshold])

	if weapon_has_twin_linked and not wound_reroll_data.is_empty():
		print("RulesEngine: TWIN-LINKED — re-rolled %d failed wound rolls" % wound_reroll_data.size())

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
		"regular_wounds": regular_wound_count,
		# ANTI-[KEYWORD] X+ tracking
		"anti_keyword_active": anti_keyword_active,
		"critical_wound_threshold": critical_wound_threshold,
		# TWIN-LINKED tracking
		"twin_linked_weapon": weapon_has_twin_linked,
		"wound_rerolls": wound_reroll_data,
		# WOUND MODIFIER tracking (T1-3)
		"wound_modifier_net": wound_modifier_net,
		"wound_modifiers_applied": wound_modifiers
	})

	if wounds_caused == 0:
		var no_wound_weapon_name = weapon_profile.get("name", weapon_id)
		var no_wound_log = "%s → %s with %s" % [actor_unit.get("meta", {}).get("name", actor_unit_id), target_unit.get("meta", {}).get("name", target_unit_id), no_wound_weapon_name]
		if is_torrent:
			no_wound_log += " - Torrent: %d auto-hits" % hits
		elif not hit_rolls.is_empty():
			no_wound_log += " - Hit: %d/%d [%s] vs %s+" % [hits, total_attacks, ", ".join(hit_rolls.map(func(r): return str(r))), str(bs)]
		else:
			no_wound_log += " - %d hits" % hits
		if sustained_bonus_hits > 0:
			no_wound_log += " (+%d sustained)" % sustained_bonus_hits
		if not wound_rolls.is_empty():
			no_wound_log += " - Wound: 0/%d [%s] vs %s+" % [total_hits_for_wounds, ", ".join(wound_rolls.map(func(r): return str(r))), str(wound_threshold)]
		else:
			no_wound_log += " - no wounds"
		result.log_text = no_wound_log
		return result

	# STOP HERE - Prepare save data instead of auto-resolving
	# DEVASTATING WOUNDS (PRP-012): Pass critical wound info for unsaveable damage
	var devastating_wounds_data = {
		"has_devastating_wounds": weapon_has_devastating_wounds,
		"critical_wounds": critical_wound_count,
		"regular_wounds": regular_wound_count
	}

	# MELTA X (T1-1): Check if weapon is Melta and compute half-range info
	var melta_value = get_melta_value(weapon_id, board)
	var melta_data = {}
	if melta_value > 0:
		# Reuse models_in_half_range if already computed for Rapid Fire, otherwise compute
		var melta_models_in_half_range = models_in_half_range if rapid_fire_value > 0 else count_models_in_half_range(actor_unit, target_unit, weapon_id, model_ids, board)
		melta_data = {
			"melta_value": melta_value,
			"models_in_half_range": melta_models_in_half_range,
			"total_models": model_ids.size()
		}
		print("RulesEngine: MELTA %d — %d/%d models in half range" % [melta_value, melta_models_in_half_range, model_ids.size()])

	# PRECISION (T3-4): Check if weapon has Precision keyword
	# Critical hits (unmodified 6 to hit) from Precision weapons allow wound allocation to CHARACTER models
	var weapon_has_precision = has_precision(weapon_id, board)
	# PURITY OF EXECUTION: Ranged attacks vs PSYKER gain [PRECISION]
	if not weapon_has_precision and purity_of_execution_active:
		weapon_has_precision = true
		print("RulesEngine: PURITY OF EXECUTION — Precision vs PSYKER target %s" % target_unit_id)
	var precision_data = {}
	if weapon_has_precision:
		# Number of precision wounds = min(critical_hits, wounds_caused)
		# These wounds CAN be allocated to CHARACTER models even if bodyguard is alive
		var precision_wounds = mini(critical_hits, wounds_caused)
		precision_data = {
			"has_precision": true,
			"critical_hits": critical_hits,
			"precision_wounds": precision_wounds
		}
		print("RulesEngine: PRECISION — %d critical hits, %d precision wounds (can target CHARACTER)" % [critical_hits, precision_wounds])

	var save_data = prepare_save_resolution(
		wounds_caused,
		target_unit_id,
		actor_unit_id,
		weapon_profile,
		board,
		devastating_wounds_data,
		melta_data,
		precision_data
	)

	result["save_data"] = save_data
	# Build verbose log text with dice roll details
	var int_weapon_name = weapon_profile.get("name", weapon_id)
	var log_parts = []
	log_parts.append("%s → %s with %s" % [
		actor_unit.get("meta", {}).get("name", actor_unit_id),
		target_unit.get("meta", {}).get("name", target_unit_id),
		int_weapon_name
	])

	# Hit roll details
	if is_torrent:
		log_parts.append("Torrent: %d auto-hits" % hits)
	else:
		var hit_detail = "Hit: %d/%d" % [hits, total_attacks]
		if not hit_rolls.is_empty():
			hit_detail += " [%s] vs %s+" % [", ".join(hit_rolls.map(func(r): return str(r))), str(bs)]
		if heavy_bonus_applied:
			hit_detail += " (Heavy +1)"
		if bgnt_penalty_applied:
			hit_detail += " (BGNT -1)"
		if indirect_fire_applied:
			hit_detail += " (Indirect -1)"
		if not reroll_data.is_empty():
			hit_detail += " (%d rerolled)" % reroll_data.size()
		if critical_hits > 0:
			hit_detail += " [%d crit]" % critical_hits
		log_parts.append(hit_detail)

	if sustained_bonus_hits > 0:
		log_parts.append("+%d Sustained Hits" % sustained_bonus_hits)

	# Wound roll details
	var wound_detail = "Wound: %d/%d" % [wounds_caused, total_hits_for_wounds]
	if not wound_rolls.is_empty():
		wound_detail += " [%s] vs %s+" % [", ".join(wound_rolls.map(func(r): return str(r))), str(wound_threshold)]
	if auto_wounds > 0:
		wound_detail += " (%d Lethal auto-wound)" % auto_wounds
	if wound_modifier_net != 0:
		wound_detail += " (%+d modifier)" % wound_modifier_net
	if not wound_reroll_data.is_empty():
		wound_detail += " (%d rerolled)" % wound_reroll_data.size()
	log_parts.append(wound_detail)

	# DEVASTATING WOUNDS: Add critical wound info to log
	if weapon_has_devastating_wounds and critical_wound_count > 0:
		log_parts.append("%d DEVASTATING (unsaveable)" % critical_wound_count)

	# MELTA X (T1-1): Add melta info to log
	if melta_value > 0 and not melta_data.is_empty() and melta_data.models_in_half_range > 0:
		log_parts.append("MELTA +%d damage (half range)" % melta_value)

	# PRECISION (T3-4): Add precision info to log
	if weapon_has_precision and critical_hits > 0:
		log_parts.append("PRECISION: %d wounds can target CHARACTER" % precision_data.precision_wounds)

	log_parts.append("awaiting saves")
	result.log_text = " - ".join(log_parts)

	return result

# Resolve a single weapon assignment (models with weapon -> target)
# SUSTAINED HITS (PRP-011): This function is modified to handle Sustained Hits
# BLAST (PRP-013): This function is modified to handle Blast keyword
# ISS-047 (11e 24.23): [LETHAL HITS] is a CHOICE per attack. Engine
# default: auto-wound, EXCEPT when the weapon also has [DEVASTATING
# WOUNDS] — rolling the wound preserves the critical-wound trigger (the
# 24.23 designer's-note trade-off). assignment.lethal_hits_choice
# ("auto"/"roll") overrides the default. 10e always auto-wounds.
static func lethal_hits_auto_wound_11e(weapon_id: String, board: Dictionary, assignment: Dictionary) -> bool:
	if GameConstants.edition < 11:
		return true
	match str(assignment.get("lethal_hits_choice", "")):
		"auto":
			return true
		"roll":
			print("RulesEngine: [24.23] LETHAL HITS — attacker chose to ROLL critical hits' wounds")
			return false
	if has_devastating_wounds(weapon_id, board):
		print("RulesEngine: [24.23] LETHAL HITS + DEVASTATING WOUNDS — defaulting to ROLL (keeps the crit-wound trigger)")
		return false
	return true


# ── ISS-041 step 2: 11e save/damage resolution via allocation groups ──
# 05.03-05.04: the DEFENDER divides the target into allocation groups,
# saves are batch-rolled, and damage is applied lowest roll → highest
# against the current group. The engine resolves with the defender's
# default legal order (Allocation.default_order); the interactive
# order/PRECISION choice UI is ISS-045. [DEVASTATING WOUNDS] crits become
# per-crit mortal wounds (24.10) applied AFTER the normal damage (06.02).
# NOTE (11e 13.08): cover worsens the attack's BS — it does NOT modify
# saves — so no cover bonus enters this flow (hit-side wiring: ISS-053).
static func _apply_saves_via_allocation_11e(result: Dictionary, target_unit: Dictionary, target_unit_id: String, wounds_to_save: int, dev_wound_crits: int, ap: int, damage_raw: String, rng: RNGService, opts: Dictionary) -> Dictionary:
	var out = {"casualties": 0, "damage_applied": 0, "damage_roll_log": []}
	var groups = Allocation.build_groups(target_unit)
	if groups.is_empty() or (wounds_to_save <= 0 and dev_wound_crits <= 0):
		return out
	# ISS-045: the defender's chosen allocation order (group ids) — must
	# satisfy 05.03's constraints; otherwise the default legal order.
	var order = Allocation.default_order(groups)
	var chosen_order: Array = opts.get("order", [])
	if not chosen_order.is_empty():
		var order_check = Allocation.validate_order(groups, chosen_order)
		if order_check.valid:
			order = chosen_order
		else:
			print("RulesEngine: [11e ALLOCATION] rejected invalid allocation order %s (%s) — using default" % [str(chosen_order), str(order_check.errors)])
	# ISS-047 (24.28): [PRECISION] — the ATTACKER may make a CHARACTER
	# group the CURRENT allocation group until it is destroyed; this
	# explicitly overrides the 05.03 order constraints.
	var precision_gid := str(opts.get("precision_group", ""))
	if precision_gid != "":
		for g in groups:
			if str(g.id) == precision_gid and g.character:
				order.erase(precision_gid)
				order.push_front(precision_gid)
				print("RulesEngine: [24.28] PRECISION — CHARACTER group %s is the current allocation group" % precision_gid)
				break
	var models = target_unit.get("models", [])
	var base_save = target_unit.get("meta", {}).get("stats", {}).get("save", 7)
	var save_modifier = clampi(int(target_unit.get("flags", {}).get("save_modifier", 0)), -1, 1)
	var effect_invuln = EffectPrimitivesData.get_effect_invuln(target_unit)
	var melta_value = int(opts.get("melta_value", 0))
	var melta_box = [int(opts.get("melta_wounds", 0))]
	var has_half_damage = bool(opts.get("half_damage", false))
	var unit_fnp_value = int(opts.get("fnp_value", 0))
	var damage_roll_log: Array = out.damage_roll_log

	print("RulesEngine: [11e ALLOCATION] %d save(s) + %d devastating crit(s) vs %d group(s), order=%s" % [wounds_to_save, dev_wound_crits, groups.size(), str(order)])

	if wounds_to_save > 0:
		var save_rolls = rng.roll_d6(wounds_to_save)
		# Per inflicting attack: roll the D characteristic and apply the
		# defender-side damage modifiers (melta/half/minus/FNP), mirroring
		# the 10e loop so those abilities keep working under the 11e flow.
		var damage_provider = func(_roll: int, model_index: int) -> int:
			var dmg_result = roll_variable_characteristic(damage_raw, rng)
			var dmg = dmg_result.value
			if dmg_result.rolled:
				damage_roll_log.append(dmg_result)
			if melta_value > 0 and melta_box[0] > 0:
				dmg += melta_value
				melta_box[0] -= 1
			if has_half_damage:
				dmg = apply_half_damage(dmg)
			var minus_dmg = EffectPrimitivesData.get_effect_minus_damage(target_unit)
			if minus_dmg > 0:
				dmg = max(1, dmg - minus_dmg)
			var fnp = unit_fnp_value
			if model_index >= 0 and model_index < models.size():
				fnp = get_model_fnp(target_unit, models[model_index])
			if fnp > 0 and dmg > 0:
				var fnp_result = roll_feel_no_pain(dmg, fnp, rng)
				result.dice.append({
					"context": "feel_no_pain",
					"source": "failed_save",
					"rolls": fnp_result.rolls,
					"fnp_value": fnp,
					"wounds_prevented": fnp_result.wounds_prevented,
					"wounds_remaining": fnp_result.wounds_remaining,
					"total_wounds": dmg
				})
				dmg = fnp_result.wounds_remaining
			return dmg
		var alloc = Allocation.apply_save_rolls(target_unit, groups, order, save_rolls, ap, 1, {
			"save_modifier": save_modifier,
			"effect_invuln": effect_invuln,
			"damage_provider": damage_provider,
		})
		var fails := 0
		for ev in alloc.events:
			if ev.get("result", "") != "saved":
				fails += 1
		result.dice.append({
			"context": "save",
			"sv": str(base_save) + "+",
			"ap": ap,
			"cover": "n/a (11e: cover worsens BS, not saves)",
			"save_modifier": save_modifier,
			"rolls_raw": save_rolls,
			"fails": fails,
			"allocation_11e": {"order": order, "events": alloc.events}
		})
		_materialize_allocation_11e(result, target_unit, target_unit_id, alloc.remaining, alloc.models_destroyed)
		out.casualties += alloc.models_destroyed.size()
		out.damage_applied += alloc.damage_total

	# [DEVASTATING WOUNDS] (24.10): each critical wound inflicts D mortal
	# wounds against AT MOST one model, applied after the normal damage
	# (06.02); each crit's excess beyond the selected model is lost.
	if dev_wound_crits > 0:
		var dw_events: Array = []
		for _c in range(dev_wound_crits):
			var dmg_result = roll_variable_characteristic(damage_raw, rng)
			var dmg = dmg_result.value
			if dmg_result.rolled:
				damage_roll_log.append(dmg_result)
			if melta_value > 0 and melta_box[0] > 0:
				dmg += melta_value
				melta_box[0] -= 1
			if has_half_damage:
				dmg = apply_half_damage(dmg)
			var dw_minus_dmg = EffectPrimitivesData.get_effect_minus_damage(target_unit)
			if dw_minus_dmg > 0:
				dmg = max(1, dmg - dw_minus_dmg)
			if unit_fnp_value > 0 and dmg > 0:
				var fnp_result = roll_feel_no_pain(dmg, unit_fnp_value, rng)
				result.dice.append({
					"context": "feel_no_pain",
					"source": "devastating_wounds",
					"rolls": fnp_result.rolls,
					"fnp_value": unit_fnp_value,
					"wounds_prevented": fnp_result.wounds_prevented,
					"wounds_remaining": fnp_result.wounds_remaining,
					"total_wounds": dmg
				})
				dmg = fnp_result.wounds_remaining
			if dmg <= 0:
				continue
			var dw = Allocation.apply_devastating_wounds_11e(target_unit, 1, dmg)
			dw_events.append_array(dw.events)
			_materialize_allocation_11e(result, target_unit, target_unit_id, dw.remaining, dw.models_destroyed)
			out.casualties += dw.models_destroyed.size()
			out.damage_applied += dw.applied
		result.dice.append({
			"context": "devastating_wounds_11e",
			"crits": dev_wound_crits,
			"events": dw_events
		})
		print("RulesEngine: [11e ALLOCATION] devastating wounds — %d crit(s) applied as per-crit mortal wounds" % dev_wound_crits)
	return out


# ── ISS-056: 11e core stratagem dice effects ─────────────────────────
## EXPLOSIVES (15.05): roll 6D6 — each 4+ inflicts 1 mortal wound on the
## target, allocated per 06.02. Mutates the board's target unit and
## returns {dice, diffs, mortal_wounds, casualties}.
static func resolve_explosives_11e(target_unit_id: String, board: Dictionary, rng: RNGService = null) -> Dictionary:
	if rng == null:
		rng = make_rng()
	var rolls = rng.roll_d6(6)
	var mw := 0
	for r in rolls:
		if r >= 4:
			mw += 1
	var result = {"diffs": [], "dice": [{"context": "explosives_11e", "rolls": rolls, "mortal_wounds": mw}],
		"mortal_wounds": mw, "casualties": 0}
	var target = board.get("units", {}).get(target_unit_id, {})
	if mw > 0 and not target.is_empty():
		var out = Allocation.apply_mortal_wounds_11e(target, mw)
		_materialize_allocation_11e(result, target, target_unit_id, out.remaining, out.models_destroyed)
		result.casualties = out.models_destroyed.size()
	print("RulesEngine: [15.05] EXPLOSIVES vs %s — rolls %s -> %d mortal wound(s)" % [target_unit_id, str(rolls), mw])
	return result


## CRUSHING IMPACT (15.06): roll T dice for the selected model — each 1
## inflicts 1 mortal wound on YOUR unit, each 5+ on the enemy unit, both
## capped at 6 mortal wounds per unit.
static func resolve_crushing_impact_11e(unit_id: String, target_unit_id: String, board: Dictionary, rng: RNGService = null) -> Dictionary:
	if rng == null:
		rng = make_rng()
	var unit = board.get("units", {}).get(unit_id, {})
	var target = board.get("units", {}).get(target_unit_id, {})
	var toughness = int(unit.get("meta", {}).get("stats", {}).get("toughness", 6))
	var rolls = rng.roll_d6(toughness)
	var self_mw := 0
	var enemy_mw := 0
	for r in rolls:
		if r == 1:
			self_mw += 1
		elif r >= 5:
			enemy_mw += 1
	self_mw = mini(self_mw, 6)
	enemy_mw = mini(enemy_mw, 6)
	var result = {"diffs": [], "dice": [{"context": "crushing_impact_11e", "rolls": rolls,
		"self_mortals": self_mw, "enemy_mortals": enemy_mw}],
		"self_mortals": self_mw, "enemy_mortals": enemy_mw, "casualties": 0}
	if enemy_mw > 0 and not target.is_empty():
		var out = Allocation.apply_mortal_wounds_11e(target, enemy_mw)
		_materialize_allocation_11e(result, target, target_unit_id, out.remaining, out.models_destroyed)
		result.casualties += out.models_destroyed.size()
	if self_mw > 0 and not unit.is_empty():
		var self_out = Allocation.apply_mortal_wounds_11e(unit, self_mw)
		_materialize_allocation_11e(result, unit, unit_id, self_out.remaining, self_out.models_destroyed)
		result.casualties += self_out.models_destroyed.size()
	print("RulesEngine: [15.06] CRUSHING IMPACT %s vs %s — T%d rolls %s -> %d enemy / %d self mortal wound(s)" % [unit_id, target_unit_id, toughness, str(rolls), enemy_mw, self_mw])
	return result


# The engine's default [PRECISION] pick (24.28): the first CHARACTER
# group in the target. Visible-to-attacker refinement lands with the
# ISS-052 visibility module; the attacker-facing prompt with ISS-063.
static func _precision_group_11e(weapon_has_precision_flag: bool, target_unit: Dictionary) -> String:
	if not weapon_has_precision_flag or GameConstants.edition < 11:
		return ""
	for g in Allocation.build_groups(target_unit):
		if g.character:
			return str(g.id)
	return ""


# Turn an Allocation `remaining` map into diffs AND update the local board
# unit so later assignments in the same action (and the per-crit
# devastating-wound passes) see the post-damage state.
static func _materialize_allocation_11e(result: Dictionary, target_unit: Dictionary, target_unit_id: String, remaining: Dictionary, models_destroyed: Array) -> void:
	var models = target_unit.get("models", [])
	for idx in remaining:
		var i = int(idx)
		if i < 0 or i >= models.size():
			continue
		var model = models[i]
		var w = model.get("wounds", 1)
		var cur = model.get("current_wounds", w)
		var new_wounds = int(remaining[idx])
		if new_wounds == cur:
			continue
		model["current_wounds"] = new_wounds
		result.diffs.append({
			"op": "set",
			"path": "units.%s.models.%d.current_wounds" % [target_unit_id, i],
			"value": new_wounds
		})
	for di_raw in models_destroyed:
		var di = int(di_raw)
		if di < 0 or di >= models.size():
			continue
		if not models[di].get("alive", true):
			continue
		models[di]["alive"] = false
		result.diffs.append({
			"op": "set",
			"path": "units.%s.models.%d.alive" % [target_unit_id, di],
			"value": false
		})
		var label = get_model_display_label(models[di], target_unit)
		print("RulesEngine: 💀 %s destroyed (11e allocation)" % label)


# ── ISS-045: defender-driven allocation batch (11e interactive flow) ──
# Non-mutating compute used by the AllocationGroupOverlay (and any AI
# defender): takes the save_data produced by prepare_save_resolution, the
# defender's chosen group order, and the live board; rolls the save batch
# + per-crit devastating wounds on a SCRATCH copy of the target unit and
# returns {diffs, dice, casualties, damage_applied, saves_passed,
# saves_failed, save_rolls, order_used, groups}. The caller applies the
# diffs (overlay → GameState; phase → snapshot) — both are idempotent
# `set` ops.
static func resolve_allocation_batch_11e(save_data: Dictionary, order: Array, board: Dictionary, rng: RNGService = null) -> Dictionary:
	if rng == null:
		rng = make_rng()
	var target_unit_id = str(save_data.get("target_unit_id", ""))
	var live_unit = board.get("units", {}).get(target_unit_id, {})
	var out = {
		"is_allocation_11e": true, "target_unit_id": target_unit_id,
		"diffs": [], "dice": [], "casualties": 0, "damage_applied": 0,
		"saves_passed": 0, "saves_failed": 0, "save_rolls": [],
		"order_used": [], "groups": [],
	}
	if live_unit.is_empty():
		return out
	# Attached units: characters live in SEPARATE linked units
	# (CharacterAttachmentManager) — fold them into one virtual unit so
	# 05.03 groups them per-CHARACTER and 05.04/06.02 reach them last;
	# diffs are remapped back to the source units afterwards.
	var virtual = _build_attached_allocation_unit_11e(target_unit_id, board)
	var scratch_unit = virtual.unit
	var sources: Array = virtual.sources
	var groups = Allocation.build_groups(scratch_unit)
	out.groups = groups

	var wounds_to_save = int(save_data.get("wounds_to_save", 0))
	var dev_crits = int(save_data.get("devastating_wounds", 0)) if save_data.get("has_devastating_wounds", false) else 0
	var ap = int(save_data.get("ap", 0))
	var damage_raw = str(save_data.get("damage_raw", str(save_data.get("damage", 1))))
	var fnp_value = get_unit_fnp_for_attack(live_unit, save_data.get("is_psychic", false))

	# Melta budget mirrors the auto-resolve path's proportional formula.
	var melta_value = int(save_data.get("melta_bonus", 0))
	var melta_wounds := 0
	if melta_value > 0:
		var in_half = int(save_data.get("melta_models_in_half_range", 0))
		var total_models = maxi(1, int(save_data.get("melta_total_models", 1)))
		if in_half >= total_models:
			melta_wounds = wounds_to_save
		elif in_half > 0:
			melta_wounds = ceili(float(wounds_to_save) * float(in_half) / float(total_models))

	var result = {"diffs": [], "dice": []}
	var applied = _apply_saves_via_allocation_11e(result, scratch_unit, target_unit_id,
		wounds_to_save, dev_crits, ap, damage_raw, rng, {
			"order": order,
			"precision_group": _precision_group_11e(save_data.get("has_precision", false), scratch_unit),
			"melta_value": melta_value,
			"melta_wounds": melta_wounds,
			"half_damage": get_unit_half_damage(live_unit),
			"fnp_value": fnp_value,
		})
	# Remap virtual-unit diff paths back to the source units (attached
	# characters keep their own unit ids).
	for diff in result.diffs:
		var parts = str(diff.get("path", "")).split(".")
		if parts.size() == 5 and parts[0] == "units" and parts[2] == "models":
			var vi = int(parts[3])
			if vi >= 0 and vi < sources.size():
				var src = sources[vi]
				diff["path"] = "units.%s.models.%d.%s" % [src.unit_id, src.model_index, parts[4]]
	out.diffs = result.diffs
	out.dice = result.dice
	out.casualties = applied.casualties
	out.damage_applied = applied.damage_applied
	for d in result.dice:
		if d.get("context", "") == "save":
			out.save_rolls = d.get("rolls_raw", [])
			out.saves_failed = int(d.get("fails", 0))
			out.saves_passed = out.save_rolls.size() - out.saves_failed
			out.order_used = d.get("allocation_11e", {}).get("order", [])
	if out.order_used.is_empty():
		out.order_used = order
	return out


# Fold a bodyguard unit and its attached character units (linked via
# attachment_data.attached_characters) into ONE virtual unit for the 11e
# allocation rules. Returns {unit, sources} where sources[i] maps virtual
# model index i back to {unit_id, model_index}.
static func _build_attached_allocation_unit_11e(target_unit_id: String, board: Dictionary) -> Dictionary:
	var units = board.get("units", {})
	var base_unit = units.get(target_unit_id, {})
	var combined = base_unit.duplicate(true)
	var sources: Array = []
	var base_models = base_unit.get("models", [])
	for i in range(base_models.size()):
		sources.append({"unit_id": target_unit_id, "model_index": i})
	for char_id in base_unit.get("attachment_data", {}).get("attached_characters", []):
		var char_unit = units.get(str(char_id), {})
		if char_unit.is_empty():
			continue
		var char_stats = char_unit.get("meta", {}).get("stats", {})
		var char_models = char_unit.get("models", [])
		for ci in range(char_models.size()):
			var cm = char_models[ci].duplicate(true)
			cm["is_character"] = true
			# Carry the character unit's stat fallbacks onto the model so
			# the combined unit's stats don't mask them (05.03 group keys).
			if not cm.has("wounds") and char_stats.has("wounds"):
				cm["wounds"] = char_stats.wounds
			if not cm.has("save") and char_stats.has("save"):
				cm["save"] = char_stats.save
			if not cm.has("invuln") and char_stats.has("invuln"):
				cm["invuln"] = char_stats.invuln
			combined.models.append(cm)
			sources.append({"unit_id": str(char_id), "model_index": ci})
	return {"unit": combined, "sources": sources}


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

	# SPLIT-FIRE / PER-MODEL LOS+RANGE: Re-validate eligibility at resolve time.
	# (Auto-resolve path — same safety-net as the dice-by-dice resolve path.)
	if not model_ids.is_empty():
		var filt = _filter_eligible_model_ids(model_ids, actor_unit_id, weapon_id, target_unit_id, board)
		if not filt.dropped.is_empty():
			print("RulesEngine: [SPLIT-FIRE][auto-resolve] Dropped %d ineligible model(s) for %s → %s: %s (reasons=%s)" % [
				filt.dropped.size(), weapon_id, target_unit_id, str(filt.dropped), str(filt.reasons)
			])
		model_ids = filt.kept
		if model_ids.is_empty():
			result.log_text = "No eligible models in range/LoS for %s → %s" % [weapon_id, target_unit_id]
			return result

	# Issue #387 Waaagh! Energy: 'Eadbanger gains +S/+D per 5 models in led unit
	# (and HAZARDOUS at 10+). Mutates profile when applicable.
	weapon_profile = _apply_waaagh_energy_to_profile(weapon_profile, weapon_id, actor_unit_id, board)

	# Calculate total attacks — roll variable attacks per model (D3, D6, etc.)
	var attacks_raw = weapon_profile.get("attacks_raw", str(weapon_profile.get("attacks", 1)))

	# GUN-CRAZY SHOW-OFFS (OA-9): Override snazzgun attacks to 4 when targeting closest eligible enemy (auto-resolve)
	var gun_crazy_attacks = get_gun_crazy_showoffs_attacks(actor_unit, weapon_id, weapon_profile, actor_unit_id, target_unit_id, board)
	if gun_crazy_attacks > 0:
		attacks_raw = str(gun_crazy_attacks)

	var base_attacks = 0
	var attacks_roll_log = []
	# MA-10: Track per-model BS for each attack (supports stats_override.ballistic_skill)
	var bs_per_attack = []
	var has_bs_override = false

	# DECK FRAGGERS (OA-7): Check if ranged weapons gain BLAST vs INFANTRY targets (auto-resolve)
	var deck_fraggers_blast = false
	if actor_unit.get("flags", {}).get("effect_deck_fraggers", false):
		if unit_has_keyword(target_unit, "INFANTRY"):
			var wp_type = weapon_profile.get("type", "")
			if wp_type.to_lower() == "ranged" or weapon_profile.get("range", 0) > 0:
				if not is_blast_weapon(weapon_id, board):
					deck_fraggers_blast = true
					print("RulesEngine: DECK FRAGGERS (auto-resolve) — BLAST granted to %s vs INFANTRY target" % weapon_id)

	# SHOOTY POWER TRIP (OA-37): +1 Attacks to ranged weapons for the phase (D6 roll 5-6)
	var ar_spt_attacks_bonus = 1 if actor_unit.get("flags", {}).get("effect_shooty_power_trip_attacks", false) else 0

	for model_id in model_ids:
		var model = _get_model_by_id(actor_unit, model_id)
		var model_bs = _get_model_effective_bs(model, actor_unit, weapon_profile)
		if model_bs != weapon_profile.get("bs", 4):
			has_bs_override = true

		# Roll variable attacks for each model separately (per 10e rules)
		var attacks_result = roll_variable_characteristic(attacks_raw, rng)
		var model_attacks = attacks_result.value

		# SHOOTY POWER TRIP (OA-37): +1 Attacks per model (auto-resolve)
		model_attacks += ar_spt_attacks_bonus

		# BLAST KEYWORD (PRP-013): Apply minimum attacks per model for Blast weapons vs 6+ model units
		var effective_model_attacks = calculate_blast_minimum(weapon_id, model_attacks, target_unit, board)
		# DECK FRAGGERS (OA-7): Also apply BLAST minimum if stratagem grants BLAST (auto-resolve)
		if deck_fraggers_blast:
			var df_model_count = count_alive_models(target_unit)
			if df_model_count >= 6 and model_attacks < 3:
				effective_model_attacks = maxi(effective_model_attacks, 3)
		if effective_model_attacks > model_attacks:
			model_attacks = effective_model_attacks

		base_attacks += model_attacks
		# MA-10: Record this model's BS for each of its attacks
		for _j in range(model_attacks):
			bs_per_attack.append(model_bs)
		if attacks_result.rolled:
			attacks_roll_log.append(attacks_result)

	if ar_spt_attacks_bonus > 0:
		print("RulesEngine: Shooty Power Trip (auto-resolve) — +1 attack per model (%d models, total base attacks = %d)" % [model_ids.size(), base_attacks])

	if has_bs_override:
		print("RulesEngine: [MA-10][auto-resolve] Per-model BS override active — models have different BS values")

	if attacks_roll_log.size() > 0:
		print("RulesEngine: [auto-resolve] Variable attacks rolled (%s) for %d models → %d total base attacks" % [attacks_raw, model_ids.size(), base_attacks])

	# RAPID FIRE KEYWORD: Check if weapon is Rapid Fire and models are in half range
	# MA-10: Track rapid fire attacks with per-model BS
	# MA-14: Only models in this assignment's model_ids count for RF (per-model weapons)
	var rapid_fire_value = get_rapid_fire_value(weapon_id, board)
	var rapid_fire_attacks = 0
	var models_in_half_range = 0
	if rapid_fire_value > 0:
		var weapon_range = weapon_profile.get("range", 24)
		var half_range_inches = weapon_range / 2.0
		for model_id in model_ids:
			var rf_model = _get_model_by_id(actor_unit, model_id)
			if rf_model.is_empty() or not rf_model.get("alive", true):
				continue
			var closest_distance_inches = INF
			for target_model in target_unit.get("models", []):
				if not target_model.get("alive", true):
					continue
				var edge_distance_px = Measurement.model_to_model_distance_px(rf_model, target_model)
				var edge_distance_inches = Measurement.px_to_inches(edge_distance_px)
				closest_distance_inches = min(closest_distance_inches, edge_distance_inches)
			if closest_distance_inches <= half_range_inches:
				models_in_half_range += 1
				var rf_model_bs = _get_model_effective_bs(rf_model, actor_unit, weapon_profile)
				for _j in range(rapid_fire_value):
					bs_per_attack.append(rf_model_bs)
		rapid_fire_attacks = models_in_half_range * rapid_fire_value
		print("RulesEngine: [MA-14][auto-resolve] Rapid Fire %d — %d/%d assigned models in half range (+%d attacks)" % [rapid_fire_value, models_in_half_range, model_ids.size(), rapid_fire_attacks])

	# BLAST KEYWORD (PRP-013): Add bonus attacks based on target unit size
	# Per 10e rules, Blast adds to the Attacks characteristic per model
	var blast_bonus_per_model = calculate_blast_bonus(weapon_id, target_unit, board)
	# DECK FRAGGERS (OA-7): Also add BLAST bonus attacks if stratagem grants BLAST (auto-resolve)
	if deck_fraggers_blast:
		var df_target_count = count_alive_models(target_unit)
		blast_bonus_per_model += int(df_target_count / 5)
	var blast_bonus_attacks = blast_bonus_per_model * model_ids.size()
	var target_model_count = count_alive_models(target_unit)
	# MA-10: Blast bonus attacks use weapon's default BS (not model-specific)
	var default_bs = weapon_profile.get("bs", 4)
	for _j in range(blast_bonus_attacks):
		bs_per_attack.append(default_bs)

	var total_attacks = base_attacks + rapid_fire_attacks + blast_bonus_attacks
	if assignment.has("attacks_override") and assignment.attacks_override != null:
		total_attacks = assignment.attacks_override
		rapid_fire_attacks = 0  # Override disables the rapid fire bonus tracking
		blast_bonus_attacks = 0  # Override disables the blast bonus tracking
		# MA-10: Rebuild bs_per_attack with default BS when attacks are overridden
		bs_per_attack.clear()
		for _j in range(total_attacks):
			bs_per_attack.append(default_bs)

	# MA-29: ABILITY ATTACK BONUS — Check for weapon-targeted +X Attacks from abilities (auto-resolve)
	var ar_weapon_name = weapon_profile.get("name", weapon_id)
	var ar_ability_attack_bonus = 0
	if EffectPrimitivesData.has_effect_plus_attacks(actor_unit):
		var ar_bonus_value = EffectPrimitivesData.get_effect_plus_attacks(actor_unit)
		if EffectPrimitivesData.effect_applies_to_weapon(actor_unit, EffectPrimitivesData.FLAG_PLUS_ATTACKS, ar_weapon_name):
			ar_ability_attack_bonus = ar_bonus_value * model_ids.size()  # Per-model bonus
			total_attacks += ar_ability_attack_bonus
			# Add BS entries for the bonus attacks (use per-model BS)
			for ar_model_id in model_ids:
				var ar_bonus_model = _get_model_by_id(actor_unit, ar_model_id)
				var ar_bonus_bs = _get_model_effective_bs(ar_bonus_model, actor_unit, weapon_profile)
				for _j in range(ar_bonus_value):
					bs_per_attack.append(ar_bonus_bs)
			print("RulesEngine: [MA-29][auto-resolve] Ability +%d Attacks for '%s' → +%d total (%d models × %d)" % [ar_bonus_value, ar_weapon_name, ar_ability_attack_bonus, model_ids.size(), ar_bonus_value])
		else:
			print("RulesEngine: [MA-29][auto-resolve] Ability +%d Attacks exists but does not apply to '%s' (weapon filter active)" % [ar_bonus_value, ar_weapon_name])

	# TORRENT KEYWORD (PRP-014): Check if weapon auto-hits (skip hit roll entirely)
	var is_torrent = is_torrent_weapon(weapon_id, board) or assignment.get("torrent", false)

	# INDIRECT FIRE (T2-4): Check if weapon has Indirect Fire keyword
	var is_indirect_fire = has_indirect_fire(weapon_id, board)

	# CONVERSION X+ (T4-16): Check if weapon has Conversion ability (auto-resolve path)
	var critical_hit_threshold = get_critical_hit_threshold(weapon_id, actor_unit, target_unit, model_ids, board)

	# Variables that need to be declared for both paths
	var bs = weapon_profile.get("bs", 4)
	var is_overwatch = assignment.get("overwatch", false)

	# T3-11: FIRE OVERWATCH — only unmodified 6s hit (set BS to 7 so only the
	# auto-hit on natural 6 rule applies)
	if is_overwatch:
		bs = 7
		# MA-10: Override all per-model BS to 7 for overwatch
		for i in range(bs_per_attack.size()):
			bs_per_attack[i] = 7
		print("RulesEngine: [OVERWATCH][auto-resolve] Forcing BS=7 — only unmodified 6s will hit")

	var hits = 0
	var critical_hits = 0  # Unmodified 6s that hit (never for Torrent)
	var regular_hits = 0   # Non-critical hits
	var hit_modifiers = HitModifier.NONE
	var heavy_bonus_applied = false
	var bgnt_penalty_applied = false
	var indirect_fire_applied = false
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
		# ADVANCED FIREPOWER (P1-16): Conditional Lethal Hits based on weapon/target type
		if not weapon_has_lethal_hits:
			weapon_has_lethal_hits = check_advanced_firepower_lethal_hits(weapon_id, actor_unit, target_unit, board)
		sustained_data = get_sustained_hits_value(weapon_id, board)

		result.dice.append({
			"context": "auto_hit",  # Special context for Torrent
			"torrent_weapon": true,
			"total_attacks": total_attacks,
			"successes": hits,
			"message": "Torrent: %d automatic hits" % hits,
			# Variable attacks tracking
			"variable_attacks": attacks_roll_log.size() > 0,
			"attacks_notation": attacks_raw if attacks_roll_log.size() > 0 else "",
			"attacks_rolls": attacks_roll_log,
			# Still track these for completeness, but they won't trigger
			"lethal_hits_weapon": weapon_has_lethal_hits,
			"sustained_hits_weapon": sustained_data.value > 0,
			"sustained_hits_note": "N/A - no hit roll for Torrent",
			# BLAST (PRP-013)
			"blast_weapon": is_blast_weapon(weapon_id, board) or deck_fraggers_blast,
			"blast_bonus_attacks": blast_bonus_attacks,
			"target_model_count": target_model_count,
			"base_attacks": base_attacks,
			"rapid_fire_bonus": rapid_fire_attacks,
			"rapid_fire_value": rapid_fire_value,
			"models_in_half_range": models_in_half_range,
			"deck_fraggers_blast": deck_fraggers_blast
		})
	else:
		# Normal hit roll path (non-Torrent weapons)
		# Get hit modifiers from assignment (Phase 1 MVP)
		if assignment.has("modifiers") and assignment.modifiers.has("hit"):
			var hit_mods = assignment.modifiers.hit
			if hit_mods.get("reroll_ones", false):
				hit_modifiers |= HitModifier.REROLL_ONES
			if hit_mods.get("reroll_failed", false):
				hit_modifiers |= HitModifier.REROLL_FAILED
			if hit_mods.get("plus_one", false):
				hit_modifiers |= HitModifier.PLUS_ONE
			if hit_mods.get("minus_one", false):
				hit_modifiers |= HitModifier.MINUS_ONE

		# OATH OF MOMENT (Codex): Re-roll all hit rolls when ADEPTUS ASTARTES attacks oath target
		if FactionAbilityManager.attacker_benefits_from_oath(actor_unit, target_unit):
			hit_modifiers |= HitModifier.REROLL_FAILED
			print("RulesEngine: OATH OF MOMENT (auto-resolve) — re-roll all failed hits against %s" % target_unit_id)

		# EFFECT FLAGS: Check for ability/stratagem-granted hit modifiers on the attacker
		if EffectPrimitivesData.has_effect_plus_one_hit(actor_unit):
			hit_modifiers |= HitModifier.PLUS_ONE
			print("RulesEngine: Effect +1 to hit (auto-resolve) applied for %s" % actor_unit_id)
		if EffectPrimitivesData.has_effect_minus_one_hit(actor_unit):
			hit_modifiers |= HitModifier.MINUS_ONE
			print("RulesEngine: Effect -1 to hit (auto-resolve) applied for %s" % actor_unit_id)
		var reroll_hits_scope_ar = actor_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_REROLL_HITS, "")
		if reroll_hits_scope_ar == "ones":
			hit_modifiers |= HitModifier.REROLL_ONES
			print("RulesEngine: Effect re-roll 1s to hit (auto-resolve) applied for %s" % actor_unit_id)
		elif reroll_hits_scope_ar == "failed" or reroll_hits_scope_ar == "all":
			hit_modifiers |= HitModifier.REROLL_FAILED
			print("RulesEngine: Effect re-roll hits (auto-resolve) applied for %s" % actor_unit_id)

		# DAMAGED PROFILE (P1-14): Check if attacker has Damaged profile active
		if is_damaged_profile_active(actor_unit):
			hit_modifiers |= HitModifier.MINUS_ONE
			print("RulesEngine: Damaged profile -1 to hit (auto-resolve) applied for %s" % actor_unit_id)

		# HEAVY KEYWORD: Check if weapon is Heavy and unit remained stationary
		# (at edition>=11 [HEAVY] routes through ModifierStack below — 24.16)
		if GameConstants.edition < 11 and is_heavy_weapon(weapon_id, board):
			var remained_stationary = actor_unit.get("flags", {}).get("remained_stationary", false)
			if remained_stationary:
				hit_modifiers |= HitModifier.PLUS_ONE
				heavy_bonus_applied = true

		# BIG GUNS NEVER TIRE: Apply -1 to hit for non-Pistol weapons only when shooter
		# is engaged OR target is engaged with a friendly unit (issue #337).
		# (10e only — 11e replaces BGNT with close-quarters shooting 10.06 +
		# engaged-M/V targeting 17.03, applied via ModifierStack below)
		if GameConstants.edition < 11 and big_guns_never_tire_penalty_applies(actor_unit, target_unit, board):
			# Only apply penalty if this is NOT a Pistol weapon
			if not is_pistol_weapon(weapon_id, board):
				hit_modifiers |= HitModifier.MINUS_ONE
				bgnt_penalty_applied = true
				print("RulesEngine: BGNT -1 to hit (auto-resolve) applied for %s (weapon %s)" % [actor_unit_id, weapon_id])

		# STEALTH (T2-1): Check if target unit has Stealth (from effect or base ability)
		# Stealth imposes -1 to hit rolls against this unit for ranged attacks
		if GameConstants.edition < 11 and EffectPrimitivesData.has_effect_stealth(target_unit):
			hit_modifiers |= HitModifier.MINUS_ONE
			print("RulesEngine: Stealth (effect-granted) applied -1 to hit against %s" % target_unit_id)
		elif GameConstants.edition < 11 and has_stealth_ability(target_unit):
			hit_modifiers |= HitModifier.MINUS_ONE
			print("RulesEngine: Stealth (ability) applied -1 to hit against %s" % target_unit_id)

		# INDIRECT FIRE (T2-4): Apply -1 to hit modifier for Indirect Fire weapons
		# Issue #371: per 10e RAW, the -1 penalty + Benefit of Cover only apply
		# when the target is NOT visible to any model in the firing unit.
		var indirect_target_visible = is_indirect_fire and _has_los_to_target_unit(actor_unit_id, target_unit_id, board)
		if is_indirect_fire and not indirect_target_visible:
			hit_modifiers |= HitModifier.MINUS_ONE
			indirect_fire_applied = true
			print("RulesEngine: [INDIRECT FIRE] Applied -1 to hit for weapon '%s' (target not visible)" % weapon_profile.get("name", weapon_id))
		elif is_indirect_fire and indirect_target_visible:
			print("RulesEngine: [INDIRECT FIRE] No penalty — target IS visible to firing unit")

		# TANK HUNTERS (OA-11): +1 to Hit when attacking MONSTER or VEHICLE targets (auto-resolve)
		if has_tank_hunters_vs_target(actor_unit, target_unit):
			hit_modifiers |= HitModifier.PLUS_ONE
			print("RulesEngine: TANK HUNTERS (auto-resolve) — +1 to hit for %s (target is MONSTER/VEHICLE)" % actor_unit_id)

		# MEKANIAK (OA-34): +1 to Hit for vehicles buffed by Mek at end of Movement phase (auto-resolve)
		if UnitAbilityManager.has_mekaniak_buff(actor_unit):
			hit_modifiers |= HitModifier.PLUS_ONE
			print("RulesEngine: MEKANIAK (auto-resolve) — +1 to hit for %s (Mek-buffed vehicle)" % actor_unit_id)

		# WALL OF DAKKA (OA-50): +1 to Hit on ranged attacks vs targets within half weapon range (auto-resolve)
		var wall_of_dakka_bonus_ar = get_wall_of_dakka_hit_bonus(actor_unit, target_unit, weapon_profile)
		if wall_of_dakka_bonus_ar > 0:
			hit_modifiers |= HitModifier.PLUS_ONE
			print("RulesEngine: WALL OF DAKKA (auto-resolve) — +1 to hit for %s (target within half range)" % actor_unit_id)

		# BIG AN' SHOOTY (OA-41): +1 to Hit for ranged attacks while Waaagh! active (Morkanaut, auto-resolve)
		if UnitAbilityManager.has_big_an_shooty(actor_unit):
			hit_modifiers |= HitModifier.PLUS_ONE
			print("RulesEngine: BIG AN' SHOOTY (auto-resolve) — +1 to hit (ranged) for %s (Waaagh! active)" % actor_unit_id)

		# DAT'S OUR LOOT! (OA-12): Re-roll Hit rolls of 1 on ranged attacks;
		# full Hit re-roll if target is within range of any objective marker (auto-resolve).
		var dats_our_loot_scope_ar = get_dats_our_loot_reroll_scope(actor_unit, target_unit, board)
		if dats_our_loot_scope_ar == "failed":
			hit_modifiers |= HitModifier.REROLL_FAILED
			print("RulesEngine: DAT'S OUR LOOT! (auto-resolve) — full hit re-roll for %s (target near objective)" % actor_unit_id)
		elif dats_our_loot_scope_ar == "ones":
			hit_modifiers |= HitModifier.REROLL_ONES
			print("RulesEngine: DAT'S OUR LOOT! (auto-resolve) — re-roll hit rolls of 1 for %s" % actor_unit_id)

		# SPLAT! (OA-38): Re-roll Hit rolls of 1 on ranged attacks when conditions met (auto-resolve).
		# Big Gunz: target has 10+ models. Mek Gunz: at Starting Strength vs non-MONSTER/VEHICLE.
		var splat_scope_ar = get_splat_reroll_scope(actor_unit, target_unit)
		if splat_scope_ar == "ones":
			hit_modifiers |= HitModifier.REROLL_ONES
			print("RulesEngine: SPLAT! (auto-resolve) — re-roll hit rolls of 1 for %s" % actor_unit_id)

		# BLASTAJET ATTACK RUN (OA-40): Re-roll Hit rolls of 1 when targeting non-FLY units (auto-resolve).
		var blastajet_scope_ar = get_blastajet_attack_run_reroll_scope(actor_unit, target_unit)
		if blastajet_scope_ar == "ones":
			hit_modifiers |= HitModifier.REROLL_ONES
			print("RulesEngine: BLASTAJET ATTACK RUN (auto-resolve) — re-roll hit rolls of 1 for %s" % actor_unit_id)

		# ── ISS-016/053 (11e): hit-side modifier stack — cover/STEALTH worsen
		# BS (13.08/24.33), plunging fire improves it (22.05), [HEAVY] is +1
		# to the hit roll (24.16). The ±1 dice-roll cap lives in ModifierStack.
		if GameConstants.edition >= 11 and not is_overwatch:
			var ms_firing_models: Array = []
			for ms_mid in model_ids:
				var ms_m = _get_model_by_id(actor_unit, ms_mid)
				if not ms_m.is_empty() and ms_m.get("alive", true):
					ms_firing_models.append(ms_m)
			var ms_stack = ModifierStack.collect_hit_context_11e(actor_unit, target_unit, weapon_profile, board, {"attacker_models": ms_firing_models})
			var ms_bs_delta = ms_stack.net("bs")
			var ms_hit_net_pre = ms_stack.net("hit_roll")
			# ISS-047 (24.29): [PSYCHIC] attacks may ignore any or all BS/hit
			# modifiers — the engine ignores exactly the harmful ones.
			if is_psychic_weapon(weapon_id, board):
				if ms_bs_delta > 0:
					print("RulesEngine: [24.29] PSYCHIC — ignoring BS worsening (%+d)" % ms_bs_delta)
					ms_bs_delta = 0
				if ms_hit_net_pre < 0:
					print("RulesEngine: [24.29] PSYCHIC — ignoring hit-roll penalty (%+d)" % ms_hit_net_pre)
					ms_hit_net_pre = 0
			if ms_bs_delta != 0:
				bs += ms_bs_delta
				for ms_i in range(bs_per_attack.size()):
					bs_per_attack[ms_i] += ms_bs_delta
				print("RulesEngine: [11e MODIFIERS] BS %+d (%s)" % [ms_bs_delta, str(ms_stack.sources("bs"))])
			var ms_hit_net = ms_hit_net_pre
			if ms_hit_net > 0:
				hit_modifiers |= HitModifier.PLUS_ONE
				if "heavy" in ms_stack.sources("hit_roll"):
					heavy_bonus_applied = true
				print("RulesEngine: [11e MODIFIERS] +1 to hit (%s)" % str(ms_stack.sources("hit_roll")))
			elif ms_hit_net < 0:
				hit_modifiers |= HitModifier.MINUS_ONE
				print("RulesEngine: [11e MODIFIERS] -1 to hit (%s)" % str(ms_stack.sources("hit_roll")))

		# Roll to hit with modifiers - CRITICAL HIT TRACKING (PRP-031)
		hit_rolls = rng.roll_d6(total_attacks)

		# ISS-012: per-roll evaluation shared with the melee path
		# (AttackSequence.evaluate_hit_roll). INDIRECT FIRE's unmodified-1-3
		# fail band (#371, unseen targets only) and CONVERSION's crit
		# threshold (T4-16) are parameters.
		var hit_fail_band = 3 if (is_indirect_fire and not indirect_target_visible) else 1
		for i in range(hit_rolls.size()):
			var roll = hit_rolls[i]
			# MA-10: Use per-model BS for this attack's threshold
			var attack_bs = bs_per_attack[i] if i < bs_per_attack.size() else bs
			var hit_eval = AttackSequence.evaluate_hit_roll(roll, attack_bs, hit_modifiers, critical_hit_threshold, rng, hit_fail_band)
			modified_rolls.append(hit_eval.final_roll)
			if hit_eval.rerolled:
				reroll_data.append({
					"original": hit_eval.reroll_from,
					"rerolled_to": hit_eval.reroll_to
				})
			if hit_eval.is_hit:
				hits += 1
				if hit_eval.is_crit:
					critical_hits += 1
				else:
					regular_hits += 1

		# DAKKASTORM (OA-16): Every successful Hit roll scores a Critical Hit (ranged only, auto-resolve)
		if has_dakkastorm(actor_unit) and regular_hits > 0:
			print("RulesEngine: DAKKASTORM (auto-resolve) — converting %d regular hits to critical hits for %s" % [regular_hits, actor_unit_id])
			critical_hits += regular_hits
			regular_hits = 0

		# Check for Lethal Hits keyword
		weapon_has_lethal_hits = has_lethal_hits(weapon_id, board)
		# ADVANCED FIREPOWER (P1-16): Conditional Lethal Hits based on weapon/target type
		if not weapon_has_lethal_hits:
			weapon_has_lethal_hits = check_advanced_firepower_lethal_hits(weapon_id, actor_unit, target_unit, board)
		# OA-10: Ammo Runt / unit effect flags — Lethal Hits from abilities or stratagems (ranged)
		if not weapon_has_lethal_hits and EffectPrimitivesData.has_effect_lethal_hits(actor_unit):
			weapon_has_lethal_hits = true
			print("RulesEngine:   LETHAL HITS granted by unit effect flag (e.g., Ammo Runt)")

		# SUSTAINED HITS (PRP-011): Generate bonus hits on critical hits
		sustained_data = get_sustained_hits_value(weapon_id, board)

		# HERE BE LOOT (OA-1): Freebooter Krew — Sustained Hits 1 near loot objective (ranged)
		if sustained_data.value == 0 and FactionAbilityManager.check_here_be_loot_sustained_hits(actor_unit, target_unit, board):
			sustained_data = {"value": 1, "is_dice": false}
			print("RulesEngine:   SUSTAINED HITS 1 granted by Here Be Loot (Freebooter Krew detachment)")

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
			"indirect_fire_applied": indirect_fire_applied,
			"rapid_fire_bonus": rapid_fire_attacks,
			"rapid_fire_value": rapid_fire_value,
			"models_in_half_range": models_in_half_range,
			"base_attacks": base_attacks,
			"successes": hits,
			# CRITICAL HIT TRACKING (PRP-031)
			"critical_hits": critical_hits,
			"regular_hits": regular_hits,
			"lethal_hits_weapon": weapon_has_lethal_hits,
			# CONVERSION X+ (T4-16)
			"conversion_active": critical_hit_threshold < 6,
			"critical_hit_threshold": critical_hit_threshold,
			# SUSTAINED HITS (PRP-011)
			"sustained_hits_weapon": sustained_data.value > 0,
			"sustained_hits_value": sustained_data.value,
			"sustained_hits_is_dice": sustained_data.is_dice,
			"sustained_bonus_hits": sustained_bonus_hits,
			"sustained_rolls": sustained_result.rolls,
			"total_hits_for_wounds": total_hits_for_wounds,
			# Variable attacks tracking
			"variable_attacks": attacks_roll_log.size() > 0,
			"attacks_notation": attacks_raw if attacks_roll_log.size() > 0 else "",
			"attacks_rolls": attacks_roll_log,
			# BLAST (PRP-013)
			"blast_weapon": is_blast_weapon(weapon_id, board) or deck_fraggers_blast,
			"blast_bonus_attacks": blast_bonus_attacks,
			"target_model_count": target_model_count,
			"deck_fraggers_blast": deck_fraggers_blast,
			# DAKKASTORM (OA-16)
			"dakkastorm_active": has_dakkastorm(actor_unit)
		})

	if hits == 0 and sustained_bonus_hits == 0:
		var ar_miss_weapon_name = weapon_profile.get("name", weapon_id)
		var ar_miss_log = "%s → %s with %s - No hits" % [actor_unit.get("meta", {}).get("name", actor_unit_id), target_unit.get("meta", {}).get("name", target_unit_id), ar_miss_weapon_name]
		if not hit_rolls.is_empty():
			ar_miss_log += " [%s] vs %s+" % [", ".join(hit_rolls.map(func(r): return str(r))), str(bs)]
		result.log_text = ar_miss_log
		return result

	# Roll to wound - LETHAL HITS (PRP-010) + SUSTAINED HITS (PRP-011)
	# TORRENT (PRP-014): Torrent weapons skip hit roll but still roll to wound normally
	var strength = weapon_profile.get("strength", 4)
	# PULSA ROKKIT (OA-31): +1 Strength to ranged weapons for the phase
	if actor_unit.get("flags", {}).get("effect_pulsa_rokkit_active", false):
		var pre_s_pr = strength
		strength += 1
		print("RulesEngine: Pulsa Rokkit (auto-resolve) — ranged strength %d → %d (+1)" % [pre_s_pr, strength])
	# SHOOTY POWER TRIP (OA-37): +1 Strength to ranged weapons for the phase (D6 roll 3-4)
	if actor_unit.get("flags", {}).get("effect_shooty_power_trip_strength", false):
		var pre_s_spt = strength
		strength += 1
		print("RulesEngine: Shooty Power Trip (auto-resolve) — ranged strength %d → %d (+1)" % [pre_s_spt, strength])
	var toughness = _get_attached_unit_toughness(target_unit, board)  # P2-90: Use bodyguard T for attached units
	# OA-44: DED GLOWY AMMO — -1T to enemy INFANTRY within 6" of Kaptin Badrukk (auto-resolve)
	var ded_glowy_penalty_ar = get_ded_glowy_ammo_toughness_penalty(target_unit, board)
	if ded_glowy_penalty_ar > 0:
		toughness = max(1, toughness - ded_glowy_penalty_ar)
		print("RulesEngine: DED GLOWY AMMO (auto-resolve) — INFANTRY target T reduced by %d to T%d" % [ded_glowy_penalty_ar, toughness])
	# OA-48: RUNTHERD — Runtherds revert to T4 when all Gretchin are dead
	var runtherd_t_override_ar = get_runtherd_toughness_override(target_unit)
	if runtherd_t_override_ar > 0:
		toughness = runtherd_t_override_ar
		print("RulesEngine: RUNTHERD (auto-resolve) — all Gretchin dead, Runtherd T overridden to T%d" % toughness)
	var wound_threshold = _calculate_wound_threshold(strength, toughness)

	# DEVASTATING WOUNDS (PRP-012): Check if weapon has Devastating Wounds
	var ar_weapon_has_devastating_wounds = has_devastating_wounds(weapon_id, board)
	# Issue #374 Headwoppa's Killchoppa (auto-resolve path): unit-level
	# effect_devastating_wounds grants DEVASTATING WOUNDS to the bearer's
	# melee weapons.
	if not ar_weapon_has_devastating_wounds and actor_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_DEVASTATING_WOUNDS, false):
		ar_weapon_has_devastating_wounds = true
		print("RulesEngine: Headwoppa's Killchoppa — unit-level effect_devastating_wounds applied (auto-resolve)")

	# ANTI-[KEYWORD] X+: Get critical wound threshold (6 normally, lower if Anti matches target)
	var ar_critical_wound_threshold = get_critical_wound_threshold(weapon_id, target_unit, board)

	# ROLLING LOOT-HEAP (OA-6): Grant Anti-Vehicle 4+ from stratagem flag
	if actor_unit.get("flags", {}).get("effect_rolling_loot_heap", false):
		if unit_has_keyword(target_unit, "VEHICLE"):
			ar_critical_wound_threshold = mini(ar_critical_wound_threshold, 4)
			print("RulesEngine: ROLLING LOOT-HEAP (auto-resolve) — Anti-Vehicle 4+ active (critical wound threshold %d+)" % ar_critical_wound_threshold)

	var ar_anti_keyword_active = ar_critical_wound_threshold < 6

	# TWIN-LINKED: Check if weapon has Twin-linked (re-roll all failed wound rolls)
	var ar_weapon_has_twin_linked = has_twin_linked(weapon_id, board) or assignment.get("twin_linked", false)

	# WOUND MODIFIERS (T1-3): Build wound modifier flags for auto-resolve path
	var ar_wound_modifiers = WoundModifier.NONE
	if assignment.has("modifiers") and assignment.modifiers.has("wound"):
		var wound_mods = assignment.modifiers.wound
		if wound_mods.get("reroll_ones", false):
			ar_wound_modifiers |= WoundModifier.REROLL_ONES
		if wound_mods.get("reroll_failed", false):
			ar_wound_modifiers |= WoundModifier.REROLL_FAILED
		if wound_mods.get("plus_one", false):
			ar_wound_modifiers |= WoundModifier.PLUS_ONE
		if wound_mods.get("minus_one", false):
			ar_wound_modifiers |= WoundModifier.MINUS_ONE
	# Twin-linked handled via WoundModifier system for re-rolls
	if ar_weapon_has_twin_linked:
		ar_wound_modifiers |= WoundModifier.REROLL_FAILED

	# OATH OF MOMENT (Codex): +1 to wound when ADEPTUS ASTARTES attacks oath target
	if FactionAbilityManager.attacker_benefits_from_oath(actor_unit, target_unit):
		ar_wound_modifiers |= WoundModifier.PLUS_ONE
		print("RulesEngine: OATH OF MOMENT (auto-resolve) — +1 to wound against %s" % target_unit_id)

	# EFFECT FLAGS: Check for ability/stratagem-granted wound modifiers on the attacker
	if EffectPrimitivesData.has_effect_plus_one_wound(actor_unit):
		ar_wound_modifiers |= WoundModifier.PLUS_ONE
		print("RulesEngine: Effect +1 to wound (auto-resolve) applied for %s" % actor_unit_id)
	if EffectPrimitivesData.has_effect_minus_one_wound(actor_unit):
		ar_wound_modifiers |= WoundModifier.MINUS_ONE
		print("RulesEngine: Effect -1 to wound (auto-resolve) applied for %s" % actor_unit_id)
	var reroll_wounds_scope_ar = actor_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_REROLL_WOUNDS, "")
	if reroll_wounds_scope_ar == "ones":
		ar_wound_modifiers |= WoundModifier.REROLL_ONES
		print("RulesEngine: Effect re-roll 1s to wound (auto-resolve) applied for %s" % actor_unit_id)
	elif reroll_wounds_scope_ar == "failed" or reroll_wounds_scope_ar == "all":
		ar_wound_modifiers |= WoundModifier.REROLL_FAILED
		print("RulesEngine: Effect re-roll wounds (auto-resolve) applied for %s" % actor_unit_id)

	# LANCE (T4-1): +1 to wound if unit charged this turn
	if is_lance_weapon(weapon_id, board):
		var unit_charged = actor_unit.get("flags", {}).get("charged_this_turn", false)
		if unit_charged:
			ar_wound_modifiers |= WoundModifier.PLUS_ONE
			print("RulesEngine: LANCE (auto-resolve) — +1 to wound (unit charged this turn)")

	# TANK HUNTERS (OA-11): +1 to Wound when attacking MONSTER or VEHICLE targets (auto-resolve)
	if has_tank_hunters_vs_target(actor_unit, target_unit):
		ar_wound_modifiers |= WoundModifier.PLUS_ONE
		print("RulesEngine: TANK HUNTERS (auto-resolve) — +1 to wound for %s (target is MONSTER/VEHICLE)" % actor_unit_id)

	# DA BOSS' LADZ (OA-15): -1 to incoming Wound rolls when S > T and Warboss leads target unit (auto-resolve)
	var ar_da_boss_ladz_mod = get_da_boss_ladz_wound_modifier(target_unit, board, strength, toughness)
	if ar_da_boss_ladz_mod != WoundModifier.NONE:
		ar_wound_modifiers |= ar_da_boss_ladz_mod
		print("RulesEngine: DA BOSS' LADZ (auto-resolve) — -1 to wound for attacks against %s (S %d > T %d, Warboss leading)" % [target_unit_id, strength, toughness])
	# PYROMANIAKS (OA-14): Re-roll Wound rolls of 1 with Torrent weapons vs enemies within 6" (auto-resolve)
	# Full Wound re-roll if target is also within range of an objective marker.
	var ar_pyromaniaks_scope = get_pyromaniaks_reroll_scope(actor_unit, target_unit, weapon_id, board)
	if ar_pyromaniaks_scope == "failed":
		ar_wound_modifiers |= WoundModifier.REROLL_FAILED
		print("RulesEngine: PYROMANIAKS (auto-resolve) — full wound re-roll for %s (Torrent weapon, target within 6\" AND near objective)" % actor_unit_id)
	elif ar_pyromaniaks_scope == "ones":
		ar_wound_modifiers |= WoundModifier.REROLL_ONES
		print("RulesEngine: PYROMANIAKS (auto-resolve) — re-roll wound rolls of 1 for %s (Torrent weapon, target within 6\")" % actor_unit_id)

	var ar_wound_modifier_net = 0
	if ar_wound_modifiers & WoundModifier.PLUS_ONE:
		ar_wound_modifier_net += 1
	if ar_wound_modifiers & WoundModifier.MINUS_ONE:
		ar_wound_modifier_net -= 1
	ar_wound_modifier_net = clamp(ar_wound_modifier_net, -1, 1)

	if ar_wound_modifier_net != 0:
		print("RulesEngine: Wound modifier net (auto-resolve) = %+d (capped at +1/-1)" % ar_wound_modifier_net)

	# LETHAL HITS + SUSTAINED HITS + ANTI-KEYWORD + TWIN-LINKED + WOUND MODIFIERS interaction:
	# - Critical hits with Lethal Hits auto-wound (no roll needed) - NOT for Torrent (no crits)
	# - Bonus hits from Sustained Hits always roll to wound (even if weapon has Lethal Hits) - NOT for Torrent (no crits)
	# - Regular (non-critical) hits always roll to wound
	# - ANTI-[KEYWORD] X+: Critical wounds on X+ vs matching keyword targets; critical wounds always succeed
	# - Twin-linked: Re-roll all failed wound rolls (via WoundModifier system)
	# - Wound modifiers: +1/-1 cap applied to each roll; unmodified 1 always fails
	var auto_wounds = 0  # From Lethal Hits (never for Torrent)
	var wounds_from_rolls = 0
	var wound_rolls = []
	var ar_critical_wound_count = 0  # Critical wounds: unmodified X+ (Anti) or 6s (default)
	var ar_regular_wound_count = 0   # Non-critical wounds
	var ar_wound_reroll_data = []  # Track twin-linked / modifier re-rolls

	# TORRENT (PRP-014): Since Torrent has no crits, Lethal Hits never triggers
	# All hits must roll to wound normally
	if weapon_has_lethal_hits and not is_torrent and lethal_hits_auto_wound_11e(weapon_id, board, assignment):
		# Critical hits automatically wound - no roll needed
		auto_wounds = critical_hits
		# Per 10e rules, Lethal Hits auto-wounds are NOT critical wounds for Devastating Wounds
		# Critical wounds for DW require unmodified 6 (or Anti threshold) on the WOUND roll

		# Roll wounds for: regular hits + sustained bonus hits
		var hits_to_roll = regular_hits + sustained_bonus_hits
		if hits_to_roll > 0:
			wound_rolls = rng.roll_d6(hits_to_roll)
			for roll in wound_rolls:
				# ISS-012: shared per-roll evaluation (AttackSequence.evaluate_wound_roll)
				var wound_eval = AttackSequence.evaluate_wound_roll(roll, ar_wound_modifiers, wound_threshold, ar_critical_wound_threshold, rng)
				if wound_eval.rerolled:
					ar_wound_reroll_data.append({"original": wound_eval.reroll_from, "rerolled_to": wound_eval.reroll_to})
				if wound_eval.auto_fail:
					continue
				if wound_eval.is_wound:
					wounds_from_rolls += 1
					if ar_weapon_has_devastating_wounds and wound_eval.is_crit:
						ar_critical_wound_count += 1
					else:
						ar_regular_wound_count += 1

		# Lethal Hits auto-wounds go to regular wounds (not critical wounds for DW)
		ar_regular_wound_count += auto_wounds
	else:
		# Normal processing - all hits (including sustained bonus) roll to wound
		wound_rolls = rng.roll_d6(total_hits_for_wounds)
		for roll in wound_rolls:
			# ISS-012: shared per-roll evaluation (AttackSequence.evaluate_wound_roll)
			var wound_eval = AttackSequence.evaluate_wound_roll(roll, ar_wound_modifiers, wound_threshold, ar_critical_wound_threshold, rng)
			if wound_eval.rerolled:
				ar_wound_reroll_data.append({"original": wound_eval.reroll_from, "rerolled_to": wound_eval.reroll_to})
			if wound_eval.auto_fail:
				continue
			if wound_eval.is_wound:
				wounds_from_rolls += 1
				if ar_weapon_has_devastating_wounds and wound_eval.is_crit:
					ar_critical_wound_count += 1
				else:
					ar_regular_wound_count += 1

	var wounds_caused = auto_wounds + wounds_from_rolls

	if ar_anti_keyword_active:
		print("RulesEngine: ANTI-KEYWORD active (auto-resolve) — critical wound threshold %d+ (normal wound threshold %d+)" % [ar_critical_wound_threshold, wound_threshold])

	if ar_weapon_has_twin_linked and not ar_wound_reroll_data.is_empty():
		print("RulesEngine: TWIN-LINKED (auto-resolve) — re-rolled %d failed wound rolls" % ar_wound_reroll_data.size())

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
		"devastating_wounds_weapon": ar_weapon_has_devastating_wounds,
		"critical_wounds": ar_critical_wound_count,
		"regular_wounds": ar_regular_wound_count,
		# ANTI-[KEYWORD] X+ tracking
		"anti_keyword_active": ar_anti_keyword_active,
		"critical_wound_threshold": ar_critical_wound_threshold,
		# TWIN-LINKED tracking
		"twin_linked_weapon": ar_weapon_has_twin_linked,
		"wound_rerolls": ar_wound_reroll_data,
		# WOUND MODIFIER tracking (T1-3)
		"wound_modifier_net": ar_wound_modifier_net,
		"wound_modifiers_applied": ar_wound_modifiers
	})

	if wounds_caused == 0:
		var ar_nw_weapon_name = weapon_profile.get("name", weapon_id)
		var ar_nw_log = "%s → %s with %s" % [actor_unit.get("meta", {}).get("name", actor_unit_id), target_unit.get("meta", {}).get("name", target_unit_id), ar_nw_weapon_name]
		if is_torrent:
			ar_nw_log += " - Torrent: %d auto-hits" % hits
		elif not hit_rolls.is_empty():
			ar_nw_log += " - Hit: %d/%d [%s] vs %s+" % [hits, total_attacks, ", ".join(hit_rolls.map(func(r): return str(r))), str(bs)]
		else:
			ar_nw_log += " - %d hits" % hits
		if sustained_bonus_hits > 0:
			ar_nw_log += " (+%d sustained)" % sustained_bonus_hits
		if not wound_rolls.is_empty():
			ar_nw_log += " - Wound: 0/%d [%s] vs %s+" % [total_hits_for_wounds, ", ".join(wound_rolls.map(func(r): return str(r))), str(wound_threshold)]
		else:
			ar_nw_log += " - no wounds"
		result.log_text = ar_nw_log
		return result

	# Process saves and damage
	# T3-17: This section mirrors the interactive path (prepare_save_resolution + apply_save_damage)
	# to ensure both resolution paths produce identical results. Keep in sync with apply_save_damage().
	var ap = weapon_profile.get("ap", 0)
	# PULSA ROKKIT (OA-31): +1 AP to ranged weapons for the phase
	if actor_unit.get("flags", {}).get("effect_pulsa_rokkit_active", false):
		var pre_ap_pr = ap
		ap = ap + 1
		print("RulesEngine: Pulsa Rokkit (auto-resolve) — ranged AP %d → %d (+1)" % [pre_ap_pr, ap])
	# DRIVE-BY DAKKA (OA-13): Improve AP by 1 for ranged attacks vs targets within 9"
	var ar_dbd_bonus = get_drive_by_dakka_ap_bonus(actor_unit, target_unit)
	if ar_dbd_bonus > 0:
		var pre_ap_dbd = ap
		ap = ap + ar_dbd_bonus
		print("RulesEngine: Drive-by Dakka (auto-resolve) — AP %d → %d (improve by %d, target within 9\")" % [pre_ap_dbd, ap, ar_dbd_bonus])
	# WORSEN AP: Ramshackle etc. — reduce AP of incoming attacks (min 0)
	var ar_worsen_ap = EffectPrimitivesData.get_effect_worsen_ap(target_unit)
	if ar_worsen_ap > 0 and ap > 0:
		var pre_ap = ap
		ap = max(0, ap - ar_worsen_ap)
		print("RulesEngine: Worsen AP (auto-resolve) — AP %d → %d (worsen by %d)" % [pre_ap, ap, ar_worsen_ap])
	var damage_raw = weapon_profile.get("damage_raw", str(weapon_profile.get("damage", 1)))
	var casualties = 0
	var damage_applied = 0
	var damage_roll_log = []

	# MELTA X (T1-1): Calculate melta bonus for auto-resolve path
	var ar_melta_value = get_melta_value(weapon_id, board)
	var ar_melta_wounds_remaining = 0
	if ar_melta_value > 0:
		# Reuse models_in_half_range if already computed for Rapid Fire, otherwise compute
		var ar_melta_models_in_half_range = models_in_half_range if rapid_fire_value > 0 else count_models_in_half_range(actor_unit, target_unit, weapon_id, model_ids, board)
		if ar_melta_models_in_half_range > 0:
			if ar_melta_models_in_half_range >= model_ids.size():
				ar_melta_wounds_remaining = wounds_caused
			else:
				ar_melta_wounds_remaining = ceili(float(wounds_caused) * float(ar_melta_models_in_half_range) / float(model_ids.size()))
			print("RulesEngine: MELTA %d (auto-resolve) — %d/%d models in half range, %d/%d wounds get melta bonus" % [ar_melta_value, ar_melta_models_in_half_range, model_ids.size(), ar_melta_wounds_remaining, wounds_caused])

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
	# Issue #374 Panoptispex: unit-level effect_ignores_cover flag also makes
	# the shooter's ranged weapons IGNORE COVER.
	if not auto_weapon_ignores_cover and actor_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_IGNORES_COVER, false):
		auto_weapon_ignores_cover = true
		print("RulesEngine: Panoptispex — unit-level effect_ignores_cover applied (auto-resolve)")

	# Get target unit's save value
	var base_save = target_unit.get("meta", {}).get("stats", {}).get("save", 7)

	# FEEL NO PAIN (T3-17): Check if target unit has FNP — mirrors apply_save_damage()
	# Issue #388: psychic-weapon damage triggers FNP-vs-psychic flag, even when
	# the damage is NOT a mortal wound.
	var ar_is_psychic = is_psychic_weapon(weapon_id, board)
	var ar_fnp_value = get_unit_fnp_for_attack(target_unit, ar_is_psychic)

	# HALF DAMAGE (T4-17): Check if target unit has half-damage defensive ability
	var ar_has_half_damage = get_unit_half_damage(target_unit)
	if ar_has_half_damage:
		print("RulesEngine: Half Damage active on defender (auto-resolve) — all damage characteristics halved (round up)")

	# PRECISION (T3-4): Check if weapon has Precision keyword — mirrors interactive path
	var ar_weapon_has_precision = has_precision(weapon_id, board)
	var ar_precision_wounds = 0
	if ar_weapon_has_precision:
		ar_precision_wounds = mini(critical_hits, wounds_caused)
		if ar_precision_wounds > 0:
			print("RulesEngine: PRECISION (auto-resolve) — %d critical hits, %d precision wounds (can target CHARACTER)" % [critical_hits, ar_precision_wounds])

	# ── ISS-041 (11e): defender allocation groups (05.03-05.04) replace the
	# 10e attacker-driven allocation below. The 10e path is kept intact
	# behind the edition gate (golden corpus pins it byte-for-byte).
	var use_allocation_11e: bool = GameConstants.edition >= 11
	if use_allocation_11e:
		var alloc11 = _apply_saves_via_allocation_11e(result, target_unit, target_unit_id,
			ar_regular_wound_count if ar_weapon_has_devastating_wounds else wounds_caused,
			ar_critical_wound_count if ar_weapon_has_devastating_wounds else 0,
			ap, damage_raw, rng, {
				"melta_value": ar_melta_value,
				"melta_wounds": ar_melta_wounds_remaining,
				"half_damage": ar_has_half_damage,
				"fnp_value": ar_fnp_value,
				"precision_group": _precision_group_11e(ar_weapon_has_precision, target_unit),
			})
		casualties += alloc11.casualties
		damage_applied += alloc11.damage_applied
		damage_roll_log.append_array(alloc11.damage_roll_log)

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

	# DEVASTATING WOUNDS (PRP-012, T3-17): Apply devastating damage first (unsaveable)
	# Critical wounds with Devastating Wounds bypass saves entirely and deal mortal-wound-style
	# damage that spills over between models — mirrors apply_save_damage() behavior.
	var ar_devastating_damage_applied = 0
	if not use_allocation_11e and ar_weapon_has_devastating_wounds and ar_critical_wound_count > 0:
		print("RulesEngine: DEVASTATING WOUNDS (auto-resolve) — %d critical wounds bypass saves, %d regular wounds need saves" % [ar_critical_wound_count, ar_regular_wound_count])

		# Roll variable damage per devastating wound (D3, D6, etc.)
		var dw_total_damage = 0
		for _dw_i in range(ar_critical_wound_count):
			var dmg_result = roll_variable_characteristic(damage_raw, rng)
			var dw_wound_damage = dmg_result.value
			if dmg_result.rolled:
				damage_roll_log.append(dmg_result)
			# MELTA X (T1-1): Add melta bonus to devastating wound damage if applicable
			if ar_melta_value > 0 and ar_melta_wounds_remaining > 0:
				dw_wound_damage += ar_melta_value
				ar_melta_wounds_remaining -= 1
				print("RulesEngine: MELTA +%d (auto-resolve) applied to devastating wound (damage: %d → %d)" % [ar_melta_value, dmg_result.value, dw_wound_damage])
			# HALF DAMAGE (T4-17): Halve devastating wound damage (round up)
			if ar_has_half_damage:
				var pre_half = dw_wound_damage
				dw_wound_damage = apply_half_damage(dw_wound_damage)
				print("RulesEngine: Half Damage (auto-resolve) — devastating wound damage %d → %d" % [pre_half, dw_wound_damage])
			# MINUS DAMAGE (P1-18): Subtract damage reduction (e.g. Guardian Eternal -1 Damage), min 1
			var ar_dw_minus_dmg = EffectPrimitivesData.get_effect_minus_damage(target_unit)
			if ar_dw_minus_dmg > 0:
				var pre_minus = dw_wound_damage
				dw_wound_damage = max(1, dw_wound_damage - ar_dw_minus_dmg)
				print("RulesEngine: Minus Damage (auto-resolve) — devastating wound damage %d → %d (-%d)" % [pre_minus, dw_wound_damage, ar_dw_minus_dmg])
			dw_total_damage += dw_wound_damage

		# FEEL NO PAIN: FNP applies even to devastating wounds
		var actual_dw_damage = dw_total_damage
		if ar_fnp_value > 0:
			var fnp_result = roll_feel_no_pain(dw_total_damage, ar_fnp_value, rng)
			actual_dw_damage = fnp_result.wounds_remaining
			result.dice.append({
				"context": "feel_no_pain",
				"source": "devastating_wounds",
				"rolls": fnp_result.rolls,
				"fnp_value": ar_fnp_value,
				"wounds_prevented": fnp_result.wounds_prevented,
				"wounds_remaining": fnp_result.wounds_remaining,
				"total_wounds": dw_total_damage
			})
			print("RulesEngine: FNP (auto-resolve) reduced devastating damage from %d to %d" % [dw_total_damage, actual_dw_damage])

		if actual_dw_damage > 0:
			# Apply devastating damage with spillover via _apply_damage_to_unit_pool
			var dw_result = _apply_damage_to_unit_pool(target_unit_id, actual_dw_damage, models, board)
			result.diffs.append_array(dw_result.diffs)
			casualties += dw_result.casualties
			damage_applied += dw_result.damage_applied
			ar_devastating_damage_applied = dw_result.damage_applied

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

			# Reset allocation focus after DW damage (models may have died)
			allocation_focus_model_id = null
			for i in range(models.size()):
				var model = models[i]
				if model.get("alive", true):
					var w = model.get("wounds", 1)
					var cw = model.get("current_wounds", w)
					if cw < w:
						allocation_focus_model_id = model.get("id", "m%d" % i)
						break

	# Allocate regular wounds (roll saves) — only ar_regular_wound_count if DW active
	var regular_wounds_to_save = ar_regular_wound_count if ar_weapon_has_devastating_wounds else wounds_caused
	if use_allocation_11e:
		regular_wounds_to_save = 0  # already resolved via 11e allocation groups above
	for wound_idx in range(regular_wounds_to_save):
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
		# Also check stratagem-granted cover (Go to Ground / Smokescreen)
		# INDIRECT FIRE (T2-4): Target gains Benefit of Cover from Indirect Fire ONLY
		# when target is not visible to firing unit (Issue #371 — 10e RAW gate).
		var auto_target_flags = target_unit.get("flags", {})
		var auto_stratagem_cover = auto_target_flags.get("stratagem_cover", false)
		var has_cover = false
		if not auto_weapon_ignores_cover:
			if is_indirect_fire and not _has_los_to_target_unit(actor_unit_id, target_unit_id, board):
				has_cover = true
				print("RulesEngine: [INDIRECT FIRE] Target gains Benefit of Cover (target not visible, auto-resolve)")
			else:
				has_cover = _check_model_has_cover(target_model, actor_unit_id, board) or auto_stratagem_cover

		# MA-12: Per-model save from stats_override (auto-resolve)
		var auto_model_base_save = _get_model_effective_save(target_model, target_unit, base_save)
		if auto_model_base_save != base_save:
			print("RulesEngine: MA-12 per-model save override (auto-resolve) — save %d+ (unit default %d+)" % [auto_model_base_save, base_save])

		# Check effect-granted invulnerable save (Go to Ground / abilities)
		# MA-12: Per-model invuln from stats_override (auto-resolve)
		var auto_model_invuln = _get_model_effective_invuln(target_model, target_unit, target_model.get("invuln", 0))
		var auto_effect_invuln = EffectPrimitivesData.get_effect_invuln(target_unit)
		if auto_effect_invuln > 0:
			if auto_model_invuln == 0 or auto_effect_invuln < auto_model_invuln:
				auto_model_invuln = auto_effect_invuln

		# Calculate save needed
		var save_result = _calculate_save_needed(auto_model_base_save, ap, has_cover, auto_model_invuln, target_unit)

		# T4-18: Read save roll modifier from target unit flags (capped at +1/-1 per 10e)
		var save_modifier = target_unit.get("flags", {}).get("save_modifier", 0)
		save_modifier = clamp(save_modifier, -1, 1)

		# Roll save
		var save_roll = rng.roll_d6(1)[0]
		var saved = false

		# 10e rules: Unmodified save roll of 1 always fails
		if save_roll > 1:
			var effective_save_roll = save_roll + save_modifier
			if save_result.use_invuln:
				saved = effective_save_roll >= save_result.inv
			else:
				saved = effective_save_roll >= save_result.armour
		else:
			print("RulesEngine: [auto-resolve] Save roll natural 1 — auto-fail (unmodified 1 always fails)")

		result.dice.append({
			"context": "save",
			"sv": str(base_save) + "+",
			"ap": ap,
			"cover": "+1 (capped)" if has_cover and not save_result.use_invuln else "none",
			"save_modifier": save_modifier,
			"rolls_raw": [save_roll],
			"fails": 0 if saved else 1
		})

		if not saved:
			# Roll variable damage per failed save (D3, D6, etc.)
			var dmg_result = roll_variable_characteristic(damage_raw, rng)
			var damage = dmg_result.value
			if dmg_result.rolled:
				damage_roll_log.append(dmg_result)

			# MELTA X (T1-1): Add melta bonus to damage if applicable
			if ar_melta_value > 0 and ar_melta_wounds_remaining > 0:
				damage += ar_melta_value
				ar_melta_wounds_remaining -= 1
				print("RulesEngine: MELTA +%d (auto-resolve) applied to damage (total: %d)" % [ar_melta_value, damage])

			# HALF DAMAGE (T4-17): Halve damage if defender has half-damage ability
			if ar_has_half_damage:
				var pre_half = damage
				damage = apply_half_damage(damage)
				print("RulesEngine: Half Damage (auto-resolve) — damage %d → %d" % [pre_half, damage])

			# MINUS DAMAGE (P1-18): Subtract damage reduction (e.g. Guardian Eternal -1 Damage), min 1
			var ar_minus_dmg = EffectPrimitivesData.get_effect_minus_damage(target_unit)
			if ar_minus_dmg > 0:
				var pre_minus = damage
				damage = max(1, damage - ar_minus_dmg)
				print("RulesEngine: Minus Damage (auto-resolve) — damage %d → %d (-%d)" % [pre_minus, damage, ar_minus_dmg])

			# FEEL NO PAIN (T3-17): Roll FNP for each point of damage — mirrors apply_save_damage()
			# MA-28: Use per-model FNP if available, otherwise fall back to unit FNP
			var actual_damage = damage
			var model_fnp_value = get_model_fnp(target_unit, target_model)
			if model_fnp_value > 0:
				var fnp_result = roll_feel_no_pain(damage, model_fnp_value, rng)
				actual_damage = fnp_result.wounds_remaining
				result.dice.append({
					"context": "feel_no_pain",
					"source": "failed_save",
					"rolls": fnp_result.rolls,
					"fnp_value": model_fnp_value,
					"wounds_prevented": fnp_result.wounds_prevented,
					"wounds_remaining": fnp_result.wounds_remaining,
					"total_wounds": damage
				})
				if actual_damage == 0:
					print("RulesEngine: FNP (auto-resolve) prevented all %d damage from failed save!" % damage)
					continue  # FNP saved all wounds from this failed save

			# Apply damage
			var current_wounds = target_model.get("current_wounds", target_model.get("wounds", 1))
			var new_wounds = max(0, current_wounds - actual_damage)

			result.diffs.append({
				"op": "set",
				"path": "units.%s.models.%d.current_wounds" % [target_unit_id, target_model_index],
				"value": new_wounds
			})

			damage_applied += actual_damage

			if new_wounds == 0:
				# Model destroyed
				result.diffs.append({
					"op": "set",
					"path": "units.%s.models.%d.alive" % [target_unit_id, target_model_index],
					"value": false
				})
				casualties += 1
				allocation_focus_model_id = null  # Need new allocation target
				# MA-22: Log model destruction with model type label
				var ar_label = get_model_display_label(target_model, target_unit)
				print("RulesEngine: 💀 %s destroyed (auto-resolve)" % ar_label)

	# Add variable damage dice log if any rolls were made
	if damage_roll_log.size() > 0:
		result.dice.append({
			"context": "variable_damage",
			"notation": damage_raw,
			"rolls": damage_roll_log,
			"total_damage": damage_applied,
			"message": "Variable damage (%s): rolled %s = %d total" % [damage_raw, str(damage_roll_log.map(func(r): return r.value)), damage_applied]
		})
		print("RulesEngine: [auto-resolve] Variable damage rolled (%s): %s → %d total damage applied" % [damage_raw, str(damage_roll_log.map(func(r): return r.value)), damage_applied])

	# Build log text (verbose: includes weapon, dice rolls, modifiers)
	var actor_name = actor_unit.get("meta", {}).get("name", actor_unit_id)
	var target_name = target_unit.get("meta", {}).get("name", target_unit_id)
	var weapon_name = weapon_profile.get("name", weapon_id)

	var log_parts = []
	log_parts.append("%s → %s with %s" % [actor_name, target_name, weapon_name])

	# Hit roll details
	if is_torrent:
		log_parts.append("Torrent: %d auto-hits" % hits)
	else:
		var hit_detail = "Hit: %d/%d" % [hits, total_attacks]
		if not hit_rolls.is_empty():
			hit_detail += " [%s] vs %s+" % [", ".join(hit_rolls.map(func(r): return str(r))), str(bs)]
		if heavy_bonus_applied:
			hit_detail += " (Heavy +1)"
		if bgnt_penalty_applied:
			hit_detail += " (BGNT -1)"
		if indirect_fire_applied:
			hit_detail += " (Indirect -1)"
		if not reroll_data.is_empty():
			hit_detail += " (%d rerolled)" % reroll_data.size()
		if critical_hits > 0:
			hit_detail += " [%d crit]" % critical_hits
		log_parts.append(hit_detail)

	if sustained_bonus_hits > 0:
		log_parts.append("+%d Sustained Hits" % sustained_bonus_hits)

	# Wound roll details
	var wound_detail = "Wound: %d/%d" % [wounds_caused, total_hits_for_wounds]
	if not wound_rolls.is_empty():
		wound_detail += " [%s] vs %s+" % [", ".join(wound_rolls.map(func(r): return str(r))), str(wound_threshold)]
	if auto_wounds > 0:
		wound_detail += " (%d Lethal auto-wound)" % auto_wounds
	if ar_wound_modifier_net != 0:
		wound_detail += " (%+d modifier)" % ar_wound_modifier_net
	if not ar_wound_reroll_data.is_empty():
		wound_detail += " (%d rerolled)" % ar_wound_reroll_data.size()
	log_parts.append(wound_detail)

	# DEVASTATING WOUNDS: Add critical wound info to log
	if ar_weapon_has_devastating_wounds and ar_critical_wound_count > 0:
		log_parts.append("%d DEVASTATING (unsaveable)" % ar_critical_wound_count)

	# MELTA X (T1-1): Add melta info to log
	if ar_melta_value > 0 and ar_melta_wounds_remaining < wounds_caused:
		log_parts.append("MELTA +%d damage" % ar_melta_value)

	# FNP info
	if ar_fnp_value > 0:
		log_parts.append("FNP %d+" % ar_fnp_value)

	if casualties > 0:
		log_parts.append("%d slain" % casualties)
	else:
		log_parts.append("all saved")

	result.log_text = " - ".join(log_parts)

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

	# Issue #383: removed 9e-carryover "battle-shocked cannot shoot" check.
	# Per 10e Wahapedia, battle-shocked effects are: OC=0, Desperate Escape on
	# Fall Back, no stratagem use/target. Cannot-shoot is NOT a battle-shock
	# effect in 10e. Stratagem-block enforcement happens elsewhere.

	# ASSAULT RULES: Units that Advanced can shoot, but ONLY with Assault weapons
	# Check this BEFORE the cannot_shoot flag, since Advanced units CAN shoot (with restrictions)
	var actor_advanced = flags.get("advanced", false)

	# Units that Fell Back cannot shoot (unless special rules like fall_back_and_shoot)
	if flags.get("fell_back", false):
		if not EffectPrimitivesData.has_effect_fall_back_and_shoot(actor_unit):
			errors.append("Unit cannot shoot (fell back)")
			return {"valid": false, "errors": errors}

	# Legacy cannot_shoot flag check - but skip if unit advanced (since advanced units CAN shoot)
	# or has the fall_back_and_shoot effect overriding the post-Fall-Back lockout
	if flags.get("cannot_shoot", false) and not actor_advanced:
		if not (flags.get("fell_back", false) and EffectPrimitivesData.has_effect_fall_back_and_shoot(actor_unit)):
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
				# Issue #370 (BGNT): MONSTER and VEHICLE units can fire any weapon in
				# engagement range per Big Guns Never Tire (BS -1 penalty applies).
				if actor_in_engagement and not is_pistol_weapon(weapon_id, board) and not is_monster_or_vehicle(actor_unit):
					errors.append("Non-Pistol weapon '%s' cannot be fired while in engagement range" % weapon_profile.get("name", weapon_id))

				# ASSAULT RULES: If unit Advanced, only Assault weapons can be used
				# EXCEPTION: Units with advance_and_shoot effect can fire all weapons after Advancing
				if actor_advanced and not is_assault_weapon(weapon_id, board) and not EffectPrimitivesData.has_effect_advance_and_shoot(actor_unit):
					errors.append("Cannot fire non-Assault weapon '%s' after Advancing" % weapon_profile.get("name", weapon_id))

				# MA-26: WEAPON OWNERSHIP VALIDATION — verify each model in the assignment
				# actually has this weapon via their model_profile. Units without model_profiles
				# allow all weapons to all models (backward compatibility).
				var unit_model_profiles = actor_unit.get("meta", {}).get("model_profiles", {})
				if not unit_model_profiles.is_empty():
					var assignment_model_ids = assignment.get("model_ids", [])
					var actor_models = actor_unit.get("models", [])
					var weapon_name = weapon_profile.get("name", weapon_id)
					for check_model_id in assignment_model_ids:
						# Find this model in the unit
						var check_model = {}
						for m in actor_models:
							if m.get("id", "") == check_model_id:
								check_model = m
								break
						if check_model.is_empty():
							continue
						var check_model_type = check_model.get("model_type", "")
						if check_model_type == "" or not unit_model_profiles.has(check_model_type):
							continue  # No profile for this model — allow all weapons (fallback)
						var profile_weapons = unit_model_profiles[check_model_type].get("weapons", [])
						if weapon_name not in profile_weapons:
							var profile_label = unit_model_profiles[check_model_type].get("label", check_model_type)
							errors.append("Model '%s' (%s) does not have weapon '%s' in their profile" % [check_model_id, profile_label, weapon_name])
							print("RulesEngine: MA-26 WEAPON OWNERSHIP — rejected: model '%s' (type '%s') assigned weapon '%s' not in profile weapons %s" % [check_model_id, check_model_type, weapon_name, str(profile_weapons)])

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

			# LONE OPERATIVE (T2-2): Units with Lone Operative can only be targeted from within 12"
			# unless they are part of an Attached unit
			if has_lone_operative(target_unit) and target_unit.get("attached_to", null) == null:
				var attached_chars = target_unit.get("attachment_data", {}).get("attached_characters", [])
				if attached_chars.is_empty():
					var min_dist = _get_min_distance_to_target_rules(actor_unit_id, target_unit_id, board)
					var lo_range = get_lone_operative_range(target_unit)
					if min_dist > lo_range:
						var target_name = target_unit.get("meta", {}).get("name", target_unit_id)
						errors.append("Cannot target '%s' — Lone Operative can only be targeted from within %d\" (closest model is %.1f\" away)" % [target_name, int(lo_range), min_dist])

			# PISTOL RULES: If in engagement, targets must be within engagement range
			# Issue #370 (BGNT): MONSTER and VEHICLE actors firing in ER can target
			# any visible enemy, not just the unit they're locked with.
			if actor_in_engagement and not is_monster_or_vehicle(actor_unit):
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

		# ONE SHOT (T4-2): Check if any model has already fired this one-shot weapon
		if weapon_id != "" and is_one_shot_weapon(weapon_id, board):
			var model_ids = assignment.get("model_ids", [])
			for model_id in model_ids:
				if has_fired_one_shot(actor_unit, model_id, weapon_id):
					var wp = get_weapon_profile(weapon_id, board)
					var wp_name = wp.get("name", weapon_id)
					errors.append("One Shot weapon '%s' has already been fired by model '%s' this battle" % [wp_name, model_id])

	# MA-25: PISTOL MUTUAL EXCLUSIVITY — per-model check (was unit-wide before MA-25)
	# Per 10e rules: "If a model is equipped with one or more Pistols, unless it is a
	# MONSTER or VEHICLE model, it can either shoot with its Pistols or with all of its
	# other ranged weapons."
	# Per-model: Model A (pistol only) can fire pistol while Model B (bolt rifle only)
	# fires bolt rifle. But a single model with both must choose one category.
	if not is_monster_or_vehicle(actor_unit):
		# Build per-model weapon type map: model_id -> { "pistol": bool, "non_pistol": bool }
		var model_weapon_types: Dictionary = {}
		for assignment in assignments:
			var w_id = assignment.get("weapon_id", "")
			if w_id == "":
				continue
			var is_pistol = is_pistol_weapon(w_id, board)
			var m_ids = assignment.get("model_ids", [])
			for m_id in m_ids:
				if not model_weapon_types.has(m_id):
					model_weapon_types[m_id] = {"pistol": false, "non_pistol": false}
				if is_pistol:
					model_weapon_types[m_id]["pistol"] = true
				else:
					model_weapon_types[m_id]["non_pistol"] = true
		# Check each model individually
		for m_id in model_weapon_types:
			var types = model_weapon_types[m_id]
			if types["pistol"] and types["non_pistol"]:
				errors.append("Model '%s' cannot fire both Pistol and non-Pistol weapons — must choose one category (MONSTER/VEHICLE exempt)" % m_id)
				print("RulesEngine: PISTOL MUTUAL EXCLUSIVITY — rejected: model '%s' has both Pistol and non-Pistol weapon assignments" % m_id)

	return {"valid": errors.is_empty(), "errors": errors}

# Helper functions
static func _calculate_wound_threshold(strength: int, toughness: int) -> int:
	# ISS-014: the S-vs-T chart lives once, in AttackSequence.
	return AttackSequence.wound_threshold(strength, toughness)

# P2-90: Resolve correct Toughness for attached units.
# Per 10e rules: "Each time an attack targets an Attached unit, you must use the
# Toughness characteristic of the Bodyguard models in that unit, even if a Leader
# in that unit has a different Toughness characteristic."
# - If target is a CHARACTER attached to a bodyguard (attached_to != null), use bodyguard's T
# - If target is a bodyguard with attached characters, use the bodyguard's own T (already correct)
# - If target is standalone (no attachment), use its own T
static func _get_attached_unit_toughness(target_unit: Dictionary, board: Dictionary) -> int:
	var own_toughness = target_unit.get("meta", {}).get("stats", {}).get("toughness", 4)

	# Check if this unit is a CHARACTER attached to a bodyguard
	var attached_to = target_unit.get("attached_to", null)
	if attached_to != null and attached_to != "":
		var units = board.get("units", {})
		var bodyguard_unit = units.get(attached_to, {})
		if not bodyguard_unit.is_empty():
			var bodyguard_toughness = bodyguard_unit.get("meta", {}).get("stats", {}).get("toughness", 4)
			if bodyguard_toughness != own_toughness:
				print("RulesEngine: P2-90 Attached unit T resolution — using bodyguard T%d instead of character T%d" % [bodyguard_toughness, own_toughness])
			return bodyguard_toughness

	# Bodyguard unit or standalone unit — use own toughness
	return own_toughness

# OA-44: Ded Glowy Ammo (Aura) — Check if target INFANTRY unit suffers -1 Toughness.
# Kaptin Badrukk's aura: enemy INFANTRY within 6" edge-to-edge of Kaptin Badrukk suffer -1T.
# Returns 1 (the toughness penalty to subtract) if the condition is met, 0 otherwise.
# Per 10th Edition: same aura from multiple sources does not stack — returns 1 at most.
static func get_ded_glowy_ammo_toughness_penalty(target_unit: Dictionary, board: Dictionary) -> int:
	# Must have INFANTRY keyword
	if not unit_has_keyword(target_unit, "INFANTRY"):
		return 0

	var target_owner = target_unit.get("owner", 0)
	var units = board.get("units", {})

	for source_unit_id in units:
		var source_unit = units[source_unit_id]

		# Must be an enemy unit (different owner from target)
		if source_unit.get("owner", 0) == target_owner:
			continue

		# Must be alive
		var source_alive = false
		for model in source_unit.get("models", []):
			if model.get("alive", true):
				source_alive = true
				break
		if not source_alive:
			continue

		# Must be on the board (not embarked in transport).
		# T-029a: defensive null-safe check — saved games may store null for unembarked
		# units, and `null != ""` is true, which would silently skip every aura source.
		var src_embk_dga = source_unit.get("embarked_in", "")
		if src_embk_dga != null and src_embk_dga != "":
			continue

		# Check if this unit has 'Ded Glowy Ammo (Aura)' ability directly
		var has_ability = _unit_has_ded_glowy_ammo(source_unit)

		if not has_ability:
			# Also check if any attached characters have the ability
			# (Kaptin Badrukk may be attached to Flash Gitz; range measured from bodyguard unit)
			var attached_chars = source_unit.get("attachment_data", {}).get("attached_characters", [])
			for char_id in attached_chars:
				var char_unit = units.get(char_id, {})
				if char_unit.is_empty():
					continue
				var char_alive = false
				for char_model in char_unit.get("models", []):
					if char_model.get("alive", true):
						char_alive = true
						break
				if not char_alive:
					continue
				if _unit_has_ded_glowy_ammo(char_unit):
					has_ability = true
					break  # source_unit is the bodyguard — range measured from it

		if not has_ability:
			continue

		# Check 6" edge-to-edge distance between source_unit and target_unit
		var min_dist = INF
		for source_model in source_unit.get("models", []):
			if not source_model.get("alive", true):
				continue
			if source_model.get("position", null) == null:
				continue
			for target_model in target_unit.get("models", []):
				if not target_model.get("alive", true):
					continue
				if target_model.get("position", null) == null:
					continue
				var dist = Measurement.model_to_model_distance_inches(source_model, target_model)
				if dist < min_dist:
					min_dist = dist

		if min_dist <= 6.0:
			print("RulesEngine: DED GLOWY AMMO — INFANTRY target within 6\" of source (%s), -1 Toughness applied" % source_unit_id)
			return 1  # Per 10th Ed: same aura from multiple sources does not stack

	return 0

# Helper: check if a unit dict has the 'Ded Glowy Ammo (Aura)' ability.
static func _unit_has_ded_glowy_ammo(unit: Dictionary) -> bool:
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")
		if ability_name == "Ded Glowy Ammo (Aura)":
			return true
	return false

# OA-48: Runtherd — While unit contains Gretchin models, Runtherd models use T2 (same as
# unit base T). If all Gretchin die, Runtherd models revert to their base toughness (T4).
# Returns the effective toughness value if all Gretchin are dead (override needed), or -1
# if no override applies (Gretchin alive = T2 unchanged, or ability not present).
static func get_runtherd_toughness_override(target_unit: Dictionary) -> int:
	# Check if unit has the "Runtherd" datasheet ability
	if not _unit_has_runtherd_ability(target_unit):
		return -1

	var model_profiles = target_unit.get("meta", {}).get("model_profiles", {})
	var has_alive_gretchin = false
	var has_alive_runtherd = false

	for model in target_unit.get("models", []):
		if not model.get("alive", true):
			continue
		var model_type = model.get("model_type", "")
		if model_type == "gretchin":
			has_alive_gretchin = true
		elif model_type == "runtherd":
			has_alive_runtherd = true

	if not has_alive_runtherd:
		return -1  # No Runtherd models alive — ability irrelevant

	if has_alive_gretchin:
		# Runtherd ability active: Runtherd models constrained to T2 (same as unit base T)
		# No toughness override needed — unit toughness already reflects T2
		print("RulesEngine: RUNTHERD — Gretchin alive, Runtherd models constrained to T2")
		return -1

	# All Gretchin dead: Runtherds revert to their base toughness from model_profiles
	var runtherd_t = model_profiles.get("runtherd", {}).get("stats_override", {}).get("toughness", 4)
	print("RulesEngine: RUNTHERD — All Gretchin dead, Runtherd models reverted to T%d" % runtherd_t)
	return runtherd_t

# Helper: check if a unit dict has the 'Runtherd' datasheet ability.
static func _unit_has_runtherd_ability(unit: Dictionary) -> bool:
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")
		if ability_name == "Runtherd":
			return true
	return false

# OA-45: Ghazghkull's Waaagh! Banner (Aura) — Check if attacker gets Lethal Hits on melee.
# Ghazghkull Thraka's aura: friendly ORKS within 12" edge-to-edge get Lethal Hits on melee
# weapons while a Waaagh! is active for their army.
# Returns true if the condition is met, false otherwise.
# Per 10th Edition: same aura from multiple sources does not stack — boolean result.
static func unit_has_waaagh_banner_lethal_hits(attacker_unit: Dictionary, board: Dictionary) -> bool:
	# Must have ORKS keyword
	if not unit_has_keyword(attacker_unit, "ORKS"):
		return false

	# Waaagh! must be active for this unit
	if not FactionAbilityManager.is_waaagh_active_for_unit(attacker_unit):
		return false

	var attacker_owner = attacker_unit.get("owner", 0)
	var units = board.get("units", {})

	for source_unit_id in units:
		var source_unit = units[source_unit_id]

		# Must be a friendly unit (same owner)
		if source_unit.get("owner", 0) != attacker_owner:
			continue

		# Must be alive
		var source_alive = false
		for model in source_unit.get("models", []):
			if model.get("alive", true):
				source_alive = true
				break
		if not source_alive:
			continue

		# Must be on the board (not embarked in transport).
		# T-029a: defensive null-safe check — see note above.
		var src_embk_wb = source_unit.get("embarked_in", "")
		if src_embk_wb != null and src_embk_wb != "":
			continue

		# Must have "Ghazghkull's Waaagh! Banner (Aura)" ability
		if not _unit_has_waaagh_banner(source_unit):
			continue

		# Per 10th Ed rules, a model is always within range of its own aura.
		# If attacker is the same unit as the source (Ghazghkull's own unit), apply.
		var attacker_id = attacker_unit.get("id", "")
		if attacker_id != "" and attacker_id == source_unit.get("id", ""):
			print("RulesEngine: WAAAGH! BANNER — %s is source unit, LETHAL HITS granted (self-aura)" % attacker_id)
			return true

		# Check 12" edge-to-edge distance between source unit and attacker unit
		var min_dist = INF
		for source_model in source_unit.get("models", []):
			if not source_model.get("alive", true):
				continue
			if source_model.get("position", null) == null:
				continue
			for target_model in attacker_unit.get("models", []):
				if not target_model.get("alive", true):
					continue
				if target_model.get("position", null) == null:
					continue
				var dist = Measurement.model_to_model_distance_inches(source_model, target_model)
				if dist < min_dist:
					min_dist = dist

		if min_dist <= 12.0:
			print("RulesEngine: WAAAGH! BANNER — attacker within 12\" of Ghazghkull/Makari (%.1f\"), LETHAL HITS granted" % min_dist)
			return true

	return false

# Helper: check if a unit dict has the "Ghazghkull's Waaagh! Banner (Aura)" ability.
static func _unit_has_waaagh_banner(unit: Dictionary) -> bool:
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")
		if ability_name == "Ghazghkull's Waaagh! Banner (Aura)":
			return true
	return false

static func _calculate_save_needed(base_save: int, ap: int, has_cover: bool, invuln: int, target_unit: Dictionary = {}) -> Dictionary:
	# Calculate armour save with AP and cover.
	#
	# Convention note: weapon profiles in armies/*.json store AP as the
	# negative magnitude string ("-2" for AP-2) and `get_weapon_profile`
	# returns it as the same negative int (-2). Older callers (and the
	# existing s7 unit test) pass AP as a positive magnitude (2). We
	# normalise via abs() so both conventions produce the correct
	# "AP makes saves worse" semantic — base_save + |ap| is the modified
	# armour value before any cover adjustment.
	var ap_magnitude = abs(ap)
	var armour_save = base_save + ap_magnitude  # AP makes saves worse (higher number needed)

	# 10e Benefit of Cover cap: a unit with a Save characteristic of 3+ or better cannot
	# have its Save improved by Cover against an attack with AP 0. The cap matters only
	# when AP is 0 — at AP -1+ the modified (post-AP) save is already 4+ or worse, so
	# cover bringing it back up to base never crosses the 3+ ceiling. (Wahapedia core rules,
	# "Benefit of Cover".) The rule is universal in 10e core; it is NOT keyword-gated to
	# INFANTRY/BEAST/SWARM as the previous implementation incorrectly assumed.
	if has_cover and ap_magnitude == 0 and base_save <= 3:
		# Cover would push save below 3+ — disallow for this attack.
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

static func _has_los_to_target_unit(actor_unit_id: String, target_unit_id: String, board: Dictionary) -> bool:
	"""Issue #371: returns true if any alive model of actor has LoS to any alive
	model of target, ignoring weapon range and ignoring Indirect Fire bypass.
	Used to gate Indirect Fire's -1 BS / Benefit of Cover penalties — per 10e
	those only apply when the target is NOT visible to any model in the firing
	unit."""
	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})
	var target_unit = units.get(target_unit_id, {})
	if actor_unit.is_empty() or target_unit.is_empty():
		return false
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
			if _check_line_of_sight(actor_pos, target_pos, board, actor_model, target_model):
				return true
	return false

static func _check_target_visibility(actor_unit_id: String, target_unit_id: String, weapon_id: String, board: Dictionary) -> Dictionary:
	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})
	var target_unit = units.get(target_unit_id, {})
	var weapon_profile = get_weapon_profile(weapon_id, board)

	if actor_unit.is_empty() or target_unit.is_empty() or weapon_profile.is_empty():
		return {"visible": false, "reason": "Invalid units or weapon"}

	var weapon_range = weapon_profile.get("range", 12)
	var range_px = Measurement.inches_to_px(weapon_range)

	# INDIRECT FIRE (T2-4): Indirect Fire weapons can shoot without Line of Sight
	var is_indirect = has_indirect_fire(weapon_id, board)

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
				# INDIRECT FIRE (T2-4): Skip LoS check for Indirect Fire weapons — range alone suffices
				if is_indirect:
					print("RulesEngine: [INDIRECT FIRE] Weapon '%s' targeting without LoS" % weapon_profile.get("name", weapon_id))
					return {"visible": true, "reason": ""}
				# ISS-052: 11e visibility gates — HIDDEN detection range
				# (13.09) and the obscuring/Solid line semantics
				# (13.10/13.11) — before the base LoS check.
				if GameConstants.edition >= 11:
					var tm_11e = Engine.get_main_loop().root.get_node_or_null("TerrainManager")
					if tm_11e != null:
						if not tm_11e.hidden_model_visible_to(target_model, target_unit, actor_model):
							continue
						if not tm_11e.model_visible_11e(actor_model, target_model):
							continue
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
	# T3-19: Now handles medium terrain using default infantry height
	# TER-2: Ruins-specific visibility rules (conservative: no model info available)
	var terrain_features = board.get("terrain_features", [])

	for terrain_piece in terrain_features:
		var height_cat = terrain_piece.get("height_category", "")

		# Low terrain never blocks LoS
		if height_cat == "low":
			continue

		if height_cat == "tall" or height_cat == "medium":
			var polygon = terrain_piece.get("polygon", PackedVector2Array())
			if _segment_intersects_polygon(from_pos, to_pos, polygon):
				var from_inside = _point_in_polygon(from_pos, polygon)
				var to_inside = _point_in_polygon(to_pos, polygon)

				# TER-2: Ruins visibility rules
				var terrain_type = terrain_piece.get("type", "")
				if terrain_type == "ruins":
					# No model data in legacy path, so no Aircraft/Towering exceptions
					# Can see into ruins (target inside)
					if to_inside:
						continue
					# Can see out if inside (approximation of wholly within)
					if from_inside:
						continue
					# Both outside, line crosses → BLOCKED
					return false

				# Non-ruins: models inside can see out and be seen
				if not from_inside and not to_inside:
					if height_cat == "tall":
						return false
					elif height_cat == "medium":
						# T3-19: Legacy path has no model info, assume infantry height
						# This means medium terrain blocks LoS in the legacy path
						# (conservative: infantry is default and is shorter than medium terrain)
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

	# P1-68: If either endpoint is inside the polygon, the segment interacts with it
	if Geometry2D.is_point_in_polygon(seg_start, polygon_packed):
		return true
	if Geometry2D.is_point_in_polygon(seg_end, polygon_packed):
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

# Terrain types that grant Benefit of Cover per 10e rules (T2-10)
# Ruins, area terrain (woods, craters), and obstacles (barricades) all grant cover
const COVER_TERRAIN_TYPES_WITHIN_AND_BEHIND = ["ruins", "obstacle", "barricade"]
const COVER_TERRAIN_TYPES_WITHIN_ONLY = ["woods", "crater", "area_terrain", "forest"]

# Check if a target position has benefit of cover from a shooter position
static func check_benefit_of_cover(target_pos: Vector2, shooter_pos: Vector2, board: Dictionary) -> bool:
	var terrain_features = board.get("terrain_features", [])

	for terrain_piece in terrain_features:
		var terrain_type = terrain_piece.get("type", "")

		var polygon = terrain_piece.get("polygon", PackedVector2Array())
		if polygon.is_empty():
			continue

		# Ruins, obstacles, barricades: cover when within OR behind (LoS crosses terrain)
		if terrain_type in COVER_TERRAIN_TYPES_WITHIN_AND_BEHIND:
			# Target within terrain gets cover
			if _point_in_polygon(target_pos, polygon):
				return true

			# Target behind terrain (LoS crosses terrain)
			if _segment_intersects_polygon(shooter_pos, target_pos, polygon):
				# Check if shooter is not inside the same terrain piece
				if not _point_in_polygon(shooter_pos, polygon):
					return true

		# Area terrain (woods, craters): cover when target is within the terrain
		elif terrain_type in COVER_TERRAIN_TYPES_WITHIN_ONLY:
			if _point_in_polygon(target_pos, polygon):
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
	# Check if model has benefit of cover from terrain (ruins, woods, craters, obstacles, etc.)
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

		# LONE OPERATIVE (T2-2): Units with Lone Operative can only be targeted from within 12"
		# unless they are part of an Attached unit (attached_to != null is already skipped above,
		# but Lone Operative units that are leading a bodyguard squad won't have attached_to set —
		# they ARE the parent unit. Check if this unit has attached characters, meaning it's a
		# bodyguard unit with a leader attached, which does NOT count as "Lone Operative attached".)
		# The rule applies to the Lone Operative unit itself when it is standalone.
		if has_lone_operative(target_unit) and target_unit.get("attached_to", null) == null:
			# Check if the unit has attached characters (meaning it's leading a bodyguard)
			var attached_chars = target_unit.get("attachment_data", {}).get("attached_characters", [])
			if attached_chars.is_empty():
				# Standalone Lone Operative — check if any actor model is within range.
				var min_dist = _get_min_distance_to_target_rules(actor_unit_id, target_unit_id, board)
				var lo_range = get_lone_operative_range(target_unit)
				if min_dist > lo_range:
					print("RulesEngine: Lone Operative — target '%s' cannot be targeted (closest actor model is %.1f\" away, must be within %d\")" % [target_unit.get("meta", {}).get("name", target_unit_id), min_dist, int(lo_range)])
					continue

		# PSYCHIC VEIL: Unit can only be targeted by ranged attacks within 18"
		if target_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_PSYCHIC_VEIL, false):
			var min_dist = _get_min_distance_to_target_rules(actor_unit_id, target_unit_id, board)
			if min_dist > 18.0:
				print("RulesEngine: Psychic Veil — target '%s' cannot be targeted (closest actor model is %.1f\" away, must be within 18\")" % [target_unit.get("meta", {}).get("name", target_unit_id), min_dist])
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
				"unit_name": target_unit.get("meta", {}).get("display_name", target_unit.get("meta", {}).get("name", target_unit_id)),
				"in_engagement_range": actor_in_engagement,  # Include flag for UI
				"is_bgnt": actor_is_monster_vehicle and actor_in_engagement  # Flag for BGNT status
			}

	return eligible

# Returns a human-readable reason why the given target cannot be shot at by
# the actor unit. Empty string means the target IS eligible.
# Mirrors the eligibility checks in get_eligible_targets so the UI can explain
# why a clicked enemy unit is greyed out (out of range, no LoS, Lone Operative, etc.).
static func get_target_ineligibility_reason(actor_unit_id: String, target_unit_id: String, board: Dictionary) -> String:
	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})
	var target_unit = units.get(target_unit_id, {})

	if actor_unit.is_empty():
		return "No active shooter"
	if target_unit.is_empty():
		return "Invalid target"

	if target_unit.get("owner", 0) == actor_unit.get("owner", 0):
		return "Cannot target a friendly unit"

	if target_unit.get("attached_to", null) != null:
		return "Cannot target an attached character — shoot the bodyguard unit"

	var has_alive = false
	for model in target_unit.get("models", []):
		if model.get("alive", true):
			has_alive = true
			break
	if not has_alive:
		return "Target unit is destroyed"

	var target_name = target_unit.get("meta", {}).get("display_name", target_unit.get("meta", {}).get("name", target_unit_id))
	var actor_owner = actor_unit.get("owner", 0)
	var target_is_monster_vehicle = is_monster_or_vehicle(target_unit)

	# Cannot target enemies within engagement range of friendly units
	# (unless the target is a Monster/Vehicle — Big Guns Never Tire applies to the *shooter*,
	# but the broader rule is that engaged enemies of friends are off-limits to other shooters
	# except when the target is a Monster/Vehicle, since they can also be targeted normally.)
	if not target_is_monster_vehicle:
		if _is_target_in_friendly_engagement(target_unit_id, actor_unit_id, actor_owner, units, board):
			return "%s is in engagement range with a friendly unit" % target_name

	# Lone Operative
	if has_lone_operative(target_unit) and target_unit.get("attached_to", null) == null:
		var attached_chars = target_unit.get("attachment_data", {}).get("attached_characters", [])
		if attached_chars.is_empty():
			var min_dist = _get_min_distance_to_target_rules(actor_unit_id, target_unit_id, board)
			if min_dist > 12.0:
				return "%s has Lone Operative — must be within 12\" (currently %.1f\")" % [target_name, min_dist]

	# Psychic Veil
	if target_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_PSYCHIC_VEIL, false):
		var min_dist = _get_min_distance_to_target_rules(actor_unit_id, target_unit_id, board)
		if min_dist > 18.0:
			return "%s has Psychic Veil — must be within 18\" (currently %.1f\")" % [target_name, min_dist]

	# Per-weapon analysis: figure out if it's a range issue, LoS issue, or engagement issue
	var actor_in_engagement = actor_unit.get("flags", {}).get("in_engagement", false)
	var actor_is_monster_vehicle = is_monster_or_vehicle(actor_unit)
	var target_in_er = false
	if actor_in_engagement:
		target_in_er = _is_target_within_engagement_range(actor_unit_id, target_unit_id, board)

	var unit_weapons = get_unit_weapons(actor_unit_id, board)
	var has_any_weapon = false
	var any_weapon_passed_er_filter = false
	var any_in_range = false
	var any_in_los = false

	for model_id in unit_weapons:
		var actor_model = _get_model_by_id(actor_unit, model_id)
		if actor_model.is_empty() or not actor_model.get("alive", true):
			continue

		for weapon_id in unit_weapons[model_id]:
			has_any_weapon = true
			var is_pistol = is_pistol_weapon(weapon_id, board)

			# Engagement-range weapon eligibility
			if actor_in_engagement:
				if is_pistol:
					if not target_in_er:
						continue
				else:
					if not actor_is_monster_vehicle:
						continue
			any_weapon_passed_er_filter = true

			var weapon_profile = get_weapon_profile(weapon_id, board)
			var weapon_range = weapon_profile.get("range", 12)
			var range_px = Measurement.inches_to_px(weapon_range)
			var is_indirect = has_indirect_fire(weapon_id, board)

			for actor_m in actor_unit.get("models", []):
				if not actor_m.get("alive", true):
					continue
				for target_m in target_unit.get("models", []):
					if not target_m.get("alive", true):
						continue
					var distance = Measurement.model_to_model_distance_px(actor_m, target_m)
					if distance <= range_px:
						any_in_range = true
						if is_indirect:
							any_in_los = true
						else:
							var a_pos = _get_model_position(actor_m)
							var t_pos = _get_model_position(target_m)
							if _check_line_of_sight(a_pos, t_pos, board, actor_m, target_m):
								any_in_los = true

	if not has_any_weapon:
		return "%s has no usable weapons" % actor_unit.get("meta", {}).get("display_name", actor_unit_id)

	if actor_in_engagement and not any_weapon_passed_er_filter:
		if actor_is_monster_vehicle:
			return "No weapons can reach %s while in engagement range" % target_name
		else:
			return "Your unit is in engagement range — only Pistols can shoot, and %s is not in your engagement range" % target_name

	if not any_in_range:
		return "%s is out of range" % target_name
	if not any_in_los:
		return "No line of sight to %s" % target_name

	return ""

# Check if target unit is within engagement range (1", or 2" through barricades) of actor unit
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

			# T3-9: Use barricade-aware engagement range (2" through barricades)
			var effective_er = _get_effective_engagement_range_rules(actor_pos, target_pos, board)
			if Measurement.is_in_engagement_range_shape_aware(actor_model, target_model, effective_er):
				return true

	return false

static func _get_model_by_id(unit: Dictionary, model_id: String) -> Dictionary:
	for model in unit.get("models", []):
		if model.get("id", "") == model_id:
			return model
	return {}

# MA-22: Get display label for a model, including model type if available.
# Returns e.g. "Spanner (m11)" for profiled models, or "m3" for units without profiles.
# Used in death logging and casualty reporting.
static func get_model_display_label(model: Dictionary, unit: Dictionary) -> String:
	var model_id = model.get("id", "")
	var model_type = model.get("model_type", "")
	if model_type == "":
		return model_id
	var model_profiles = unit.get("meta", {}).get("model_profiles", {})
	if model_profiles.has(model_type):
		var label = model_profiles[model_type].get("label", model_type)
		return "%s (%s)" % [label, model_id]
	return model_id

# MA-27: Get effective stats for a model, merging unit base stats with model profile stats_override.
# Returns unit base stats merged with the model's stats_override from its model_profiles entry.
# Returns base unit stats if no model_type or no model_profiles.
# Used by hit resolution (BS/WS), save resolution, wound allocation, and any future per-model stat checks.
static func get_model_effective_stats(unit: Dictionary, model: Dictionary) -> Dictionary:
	var base_stats = unit.get("meta", {}).get("stats", {}).duplicate()
	if model.is_empty():
		return base_stats
	var model_type = model.get("model_type", "")
	if model_type == "":
		return base_stats
	var model_profiles = unit.get("meta", {}).get("model_profiles", {})
	if not model_profiles.has(model_type):
		return base_stats
	var stats_override = model_profiles[model_type].get("stats_override", {})
	if stats_override.is_empty():
		return base_stats
	# Merge: override keys replace base stats
	for key in stats_override:
		base_stats[key] = stats_override[key]
	return base_stats

# MA-10: Get effective BS for a model, checking stats_override.ballistic_skill
# Returns the model's overridden BS if available, otherwise falls back to weapon profile BS.
static func _get_model_effective_bs(model: Dictionary, unit: Dictionary, weapon_profile: Dictionary) -> int:
	var default_bs = weapon_profile.get("bs", 4)
	if model.is_empty():
		return default_bs
	var model_type = model.get("model_type", "")
	if model_type == "":
		return default_bs
	var model_profiles = unit.get("meta", {}).get("model_profiles", {})
	if not model_profiles.has(model_type):
		return default_bs
	var override_bs = model_profiles[model_type].get("stats_override", {}).get("ballistic_skill", -1)
	if override_bs > 0:
		return override_bs
	return default_bs

# MA-11: Get effective WS for a model, checking stats_override.weapon_skill
# Returns the model's overridden WS if available, otherwise falls back to weapon profile WS.
static func _get_model_effective_ws(model: Dictionary, unit: Dictionary, weapon_profile: Dictionary) -> int:
	var default_ws = weapon_profile.get("ws", 4)
	if model.is_empty():
		return default_ws
	var model_type = model.get("model_type", "")
	if model_type == "":
		return default_ws
	var model_profiles = unit.get("meta", {}).get("model_profiles", {})
	if not model_profiles.has(model_type):
		return default_ws
	var override_ws = model_profiles[model_type].get("stats_override", {}).get("weapon_skill", -1)
	if override_ws > 0:
		return override_ws
	return default_ws

# MA-12: Get effective save for a model, checking stats_override.save
# Returns the model's overridden save if available, otherwise falls back to unit base save.
static func _get_model_effective_save(model: Dictionary, unit: Dictionary, default_save: int) -> int:
	if model.is_empty():
		return default_save
	var model_type = model.get("model_type", "")
	if model_type == "":
		return default_save
	var model_profiles = unit.get("meta", {}).get("model_profiles", {})
	if not model_profiles.has(model_type):
		return default_save
	var override_save = model_profiles[model_type].get("stats_override", {}).get("save", -1)
	if override_save > 0:
		return override_save
	return default_save

# MA-12: Get effective invuln for a model, checking stats_override.invuln
# Returns (in priority order): per-model stats_override invuln, model-level invuln,
# or unit meta.stats.invuln. T-014: unit-level meta.stats.invuln is the canonical
# JSON shape — without this fallback, units that only declare invuln at the unit
# level (e.g. Custodian Guard, Blade Champion) would never roll their invuln save.
static func _get_model_effective_invuln(model: Dictionary, unit: Dictionary, default_invuln: int) -> int:
	# Per-model stats_override.invuln wins if set
	if not model.is_empty():
		var model_type = model.get("model_type", "")
		if model_type != "":
			var model_profiles = unit.get("meta", {}).get("model_profiles", {})
			if model_profiles.has(model_type):
				var override_invuln = model_profiles[model_type].get("stats_override", {}).get("invuln", -1)
				if override_invuln > 0:
					return override_invuln
	# Caller-supplied default (typically model.get("invuln", 0))
	if default_invuln > 0:
		return default_invuln
	# T-014 fallback: read unit meta.stats.invuln or invulnerable_save
	var unit_stats = unit.get("meta", {}).get("stats", {})
	var stats_invuln = unit_stats.get("invuln", unit_stats.get("invulnerable_save", 0))
	if typeof(stats_invuln) == TYPE_STRING:
		stats_invuln = int(stats_invuln) if stats_invuln.is_valid_int() else 0
	elif typeof(stats_invuln) == TYPE_FLOAT:
		stats_invuln = int(stats_invuln)
	if stats_invuln > 0:
		return int(stats_invuln)
	return default_invuln

# Shared helper: return weapon IDs for a specific model, respecting model_profiles if present.
# weapon_type_filter: "Ranged" or "Melee" (case-insensitive match against weapon type)
static func _get_model_weapon_ids(unit: Dictionary, model: Dictionary, weapon_type_filter: String) -> Array:
	var weapons_data = unit.get("meta", {}).get("weapons", [])
	var model_profiles = unit.get("meta", {}).get("model_profiles", {})
	var model_type = model.get("model_type", "")

	var use_profile = not model_profiles.is_empty() and model_type != "" and model_profiles.has(model_type)
	var allowed_weapon_names = []
	if use_profile:
		allowed_weapon_names = model_profiles[model_type].get("weapons", [])

	var weapon_ids = []
	for weapon in weapons_data:
		var wtype = weapon.get("type", "")
		if wtype.to_lower() != weapon_type_filter.to_lower():
			continue

		var wname = weapon.get("name", "")
		if use_profile and wname not in allowed_weapon_names:
			continue

		var weapon_id = _generate_weapon_id(wname, wtype)
		if weapon_id not in weapon_ids:
			weapon_ids.append(weapon_id)

	return weapon_ids

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
	var models = unit.get("models", [])
	var result = {}

	# Assign weapons to all alive models using shared helper
	for model in models:
		var model_id = model.get("id", "")
		if model_id != "" and model.get("alive", true):
			result[model_id] = _get_model_weapon_ids(unit, model, "Ranged")

	# Include attached character weapons (combined unit shoots together)
	var attached_chars = unit.get("attachment_data", {}).get("attached_characters", [])
	for char_id in attached_chars:
		var char_unit = units.get(char_id, {})
		if char_unit.is_empty():
			continue

		# Assign character weapons to character's alive models
		var char_models = char_unit.get("models", [])
		for char_model in char_models:
			var char_model_id = char_model.get("id", "")
			if char_model_id != "" and char_model.get("alive", true):
				# Use composite ID so damage routing works correctly
				var composite_id = "%s:%s" % [char_id, char_model_id]
				result[composite_id] = _get_model_weapon_ids(char_unit, char_model, "Ranged")

	return result

# Helper function to generate consistent weapon IDs from names
# Includes weapon_type to avoid collisions between ranged/melee variants with the same name
# (e.g., "Guardian spear" exists as both Ranged and Melee on Custodes units)
static func _generate_weapon_id(weapon_name: String, weapon_type: String = "") -> String:
	# Convert weapon name to consistent ID format
	var weapon_id = weapon_name.to_lower()
	weapon_id = weapon_id.replace(" ", "_")
	weapon_id = weapon_id.replace("-", "_")
	weapon_id = weapon_id.replace("–", "_")  # Handle em dash
	weapon_id = weapon_id.replace("'", "")
	# Append weapon type suffix to prevent collisions between ranged/melee variants
	if weapon_type != "":
		weapon_id += "_" + weapon_type.to_lower()
	return weapon_id

# Get weapon profile
static func get_weapon_profile(weapon_id: String, board: Dictionary = {}) -> Dictionary:
	# First try legacy weapon profiles
	if WEAPON_PROFILES.has(weapon_id):
		var profile = WEAPON_PROFILES.get(weapon_id, {}).duplicate()
		# Ensure legacy profiles have raw strings for variable rolling
		if not profile.has("attacks_raw"):
			profile["attacks_raw"] = str(profile.get("attacks", 1))
		if not profile.has("damage_raw"):
			profile["damage_raw"] = str(profile.get("damage", 1))
		# ISS-003: attach the structured ability list (derived from the
		# legacy keywords/special_rules if no structured data is present)
		if not profile.has("abilities"):
			profile["abilities"] = AbilityRegistry.from_weapon(profile)
		return profile
	
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
			var w_type = weapon.get("type", "")
			# Try type-aware ID first (new format), then name-only (legacy), then exact name match
			var generated_id_typed = _generate_weapon_id(weapon_name, w_type)
			var generated_id_legacy = _generate_weapon_id(weapon_name)

			if generated_id_typed == weapon_id or generated_id_legacy == weapon_id or weapon_name == weapon_id:
				# Convert weapon format to profile format expected by UI
				# Convert string values to appropriate types where needed
				var weapon_range = weapon.get("range", "0")
				var range_value = 0
				if weapon_range == "Melee":
					range_value = 0
				else:
					range_value = int(weapon_range) if (weapon_range != null and weapon_range.is_valid_int()) else 0
				
				# Helper function to safely convert weapon stat strings to integers
				# For variable stats (D3, D6, D6+1), use the average as the integer fallback
				var attacks_str = weapon.get("attacks", "1")
				var attacks_value = 1
				if attacks_str != null and attacks_str.is_valid_int():
					attacks_value = int(attacks_str)
				elif attacks_str != null:
					var parsed = _parse_damage(attacks_str)
					attacks_value = int(ceil(float(parsed.min + parsed.max) / 2.0))  # Use average (rounded up)
				
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
				var damage_value = 1
				if damage_str != null and damage_str.is_valid_int():
					damage_value = int(damage_str)
				elif damage_str != null:
					var parsed = _parse_damage(damage_str)
					damage_value = int(ceil(float(parsed.min + parsed.max) / 2.0))  # Use average (rounded up)
				
				# Parse keywords from special_rules string (e.g., "Pistol, Rapid Fire 1")
				var special_rules = weapon.get("special_rules", "")
				# ISS-003: structured abilities are authoritative. When the
				# weapon carries them, the engine-facing special_rules string
				# is synthesized from the structured data so every downstream
				# matcher consumes what the structured entries describe.
				var abilities = AbilityRegistry.from_weapon(weapon)
				var raw_abilities = weapon.get("abilities", [])
				if raw_abilities is Array and not raw_abilities.is_empty():
					special_rules = AbilityRegistry.to_display_string(abilities)
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
					"keywords": keywords,
					"abilities": abilities
				}
	
	print("WARNING: Weapon profile not found: ", weapon_id)
	return {}

# Issue #387 Waaagh! Energy (Weirdboy 'Eadbanger size scaling).
# Wahapedia (Datasheets_abilities.csv unit 000000004): "While this model is
# leading a unit, add 1 to the Strength and Damage characteristics of this
# model's 'Eadbanger weapon for every 5 models in that unit (rounding down),
# but while that unit contains 10 or more models, that weapon has the
# [HAZARDOUS] ability."
static func get_waaagh_energy_eadbanger_bonus(weirdboy_unit_id: String, board: Dictionary) -> Dictionary:
	var zero = {"strength_bonus": 0, "damage_bonus": 0, "hazardous": false, "led_unit_model_count": 0}
	var units = board.get("units", {})
	var weirdboy = units.get(weirdboy_unit_id, {})
	if weirdboy.is_empty():
		return zero
	var has_ability = false
	for ab in weirdboy.get("abilities", []):
		var ab_name = ""
		if typeof(ab) == TYPE_DICTIONARY:
			ab_name = String(ab.get("name", ""))
		elif typeof(ab) == TYPE_STRING:
			ab_name = String(ab)
		if ab_name == "Waaagh! Energy":
			has_ability = true
			break
	if not has_ability:
		return zero
	var bodyguard_id = weirdboy.get("attached_to", null)
	if bodyguard_id == null or String(bodyguard_id) == "":
		return zero
	var bodyguard = units.get(bodyguard_id, {})
	if bodyguard.is_empty():
		return zero
	var count = 0
	for m in bodyguard.get("models", []):
		if m.get("alive", true):
			count += 1
	var attached = bodyguard.get("attachment_data", {}).get("attached_characters", [])
	for cid in attached:
		var c = units.get(cid, {})
		for cm in c.get("models", []):
			if cm.get("alive", true):
				count += 1
	var bonus = int(count / 5)
	return {
		"strength_bonus": bonus,
		"damage_bonus": bonus,
		"hazardous": count >= 10,
		"led_unit_model_count": count,
	}

# Mutate a weapon profile in-place if Waaagh! Energy applies to this actor +
# weapon. Returns the (possibly modified) profile. Safe to call on any profile.
static func _apply_waaagh_energy_to_profile(profile: Dictionary, weapon_id: String, actor_unit_id: String, board: Dictionary) -> Dictionary:
	var wname = String(profile.get("name", weapon_id)).to_lower()
	if wname.find("eadbanger") == -1:
		return profile
	var bonus = get_waaagh_energy_eadbanger_bonus(actor_unit_id, board)
	if bonus.strength_bonus == 0 and not bonus.hazardous:
		return profile
	var p = profile.duplicate(true)
	if bonus.strength_bonus > 0:
		p["strength"] = int(p.get("strength", 4)) + bonus.strength_bonus
		p["damage"] = int(p.get("damage", 1)) + bonus.damage_bonus
		var damage_raw = String(p.get("damage_raw", str(p.get("damage", 1))))
		if damage_raw.is_valid_int():
			p["damage_raw"] = str(int(damage_raw) + bonus.damage_bonus)
		else:
			# Append +N to variable expressions so D6 -> D6+N etc.
			p["damage_raw"] = damage_raw + "+" + str(bonus.damage_bonus)
		print("RulesEngine: Waaagh! Energy — 'Eadbanger S +%d, D +%d (led unit has %d models)" % [bonus.strength_bonus, bonus.damage_bonus, bonus.led_unit_model_count])
	if bonus.hazardous:
		var keywords = p.get("keywords", []).duplicate()
		var has_haz = false
		for kw in keywords:
			if String(kw).to_upper() == "HAZARDOUS":
				has_haz = true
				break
		if not has_haz:
			keywords.append("HAZARDOUS")
		p["keywords"] = keywords
		var sr = String(p.get("special_rules", ""))
		if sr.to_lower().find("hazardous") == -1:
			p["special_rules"] = sr + (", " if sr != "" else "") + "Hazardous"
		print("RulesEngine: Waaagh! Energy — 'Eadbanger gains HAZARDOUS (led unit has %d models)" % bonus.led_unit_model_count)
	return p

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
# ONE SHOT WEAPON KEYWORD (T4-2)
# ==========================================
# One Shot: Weapons with this ability can only be fired once per entire battle.
# After firing, the weapon is permanently unavailable for the rest of the game.
# Tracked per model — each model gets one use of its one-shot weapon.
# Detection checks both keywords array and special_rules string (case-insensitive).

# Check if a weapon has the One Shot keyword
static func is_one_shot_weapon(weapon_id: String, board: Dictionary = {}) -> bool:
	var profile = get_weapon_profile(weapon_id, board)
	if profile.is_empty():
		return false

	# Check special_rules string for "One Shot" (case-insensitive)
	var special_rules = profile.get("special_rules", "").to_lower()
	if "one shot" in special_rules:
		return true

	# Check keywords array
	var keywords = profile.get("keywords", [])
	for keyword in keywords:
		if keyword.to_upper() == "ONE SHOT":
			return true
	return false

# Check if a specific model has already fired a one-shot weapon this battle
static func has_fired_one_shot(unit: Dictionary, model_id: String, weapon_id: String) -> bool:
	var fired = unit.get("flags", {}).get("one_shot_fired", {})
	var model_fired = fired.get(model_id, [])
	return weapon_id in model_fired

# Generate diffs to mark a one-shot weapon as fired for a specific model
static func mark_one_shot_fired_diffs(unit_id: String, unit: Dictionary, model_id: String, weapon_id: String) -> Array:
	var diffs = []
	var flags = unit.get("flags", {})
	var one_shot_fired = flags.get("one_shot_fired", {})

	if not one_shot_fired.has(model_id):
		# First one-shot weapon fired by this model — create the model entry
		var new_model_entry = [weapon_id]
		var new_one_shot = one_shot_fired.duplicate(true)
		new_one_shot[model_id] = new_model_entry
		diffs.append({
			"op": "set",
			"path": "units.%s.flags.one_shot_fired" % unit_id,
			"value": new_one_shot
		})
	else:
		# Model already has some one-shot weapons fired — append this one
		var existing = one_shot_fired[model_id].duplicate()
		if weapon_id not in existing:
			existing.append(weapon_id)
			var new_one_shot = one_shot_fired.duplicate(true)
			new_one_shot[model_id] = existing
			diffs.append({
				"op": "set",
				"path": "units.%s.flags.one_shot_fired" % unit_id,
				"value": new_one_shot
			})

	return diffs

# Filter out one-shot weapons that have already been fired for a unit
# Returns a new weapons dict with fired one-shot weapons removed per model
static func filter_fired_one_shot_weapons(unit_id: String, unit_weapons_dict: Dictionary, board: Dictionary = {}) -> Dictionary:
	var units = {}
	if not board.is_empty():
		units = board.get("units", {})
	else:
		units = GameState.state.get("units", {})
	var unit = units.get(unit_id, {})
	if unit.is_empty():
		return unit_weapons_dict

	var result = {}
	for model_id in unit_weapons_dict:
		var weapons = unit_weapons_dict[model_id]
		var filtered = []
		for weapon_id in weapons:
			if is_one_shot_weapon(weapon_id, board) and has_fired_one_shot(unit, model_id, weapon_id):
				print("RulesEngine: [ONE SHOT] Filtering out fired weapon '%s' for model '%s'" % [weapon_id, model_id])
				continue
			filtered.append(weapon_id)
		result[model_id] = filtered
	return result

# ==========================================
# LANCE WEAPON KEYWORD (T4-1)
# ==========================================
# Lance: +1 to wound rolls if the bearer's unit made a charge move this turn
# This modifier is subject to the +1/-1 wound modifier cap
# Detection checks both keywords array and special_rules string (case-insensitive)

# Check if a weapon has the Lance keyword
static func is_lance_weapon(weapon_id: String, board: Dictionary = {}) -> bool:
	var profile = get_weapon_profile(weapon_id, board)
	if profile.is_empty():
		return false

	# Check special_rules string for "Lance" (case-insensitive)
	var special_rules = profile.get("special_rules", "").to_lower()
	if "lance" in special_rules:
		return true

	# Check keywords array
	var keywords = profile.get("keywords", [])
	for keyword in keywords:
		if keyword.to_upper() == "LANCE":
			return true
	return false

# ==========================================
# EXTRA ATTACKS (T3-3)
# ==========================================
# Extra Attacks: Weapons with this ability are used IN ADDITION to another weapon,
# not as an alternative. A model makes attacks with this weapon on top of whichever
# other weapon it selects.

# Check if a weapon has the Extra Attacks keyword
static func has_extra_attacks(weapon_id: String, board: Dictionary = {}) -> bool:
	var profile = get_weapon_profile(weapon_id, board)
	if profile.is_empty():
		return false

	# Check special_rules string for "Extra Attacks" (case-insensitive)
	var special_rules = profile.get("special_rules", "").to_lower()
	if "extra attacks" in special_rules:
		return true

	# Check keywords array
	var keywords = profile.get("keywords", [])
	for keyword in keywords:
		if "extra attacks" in keyword.to_lower():
			return true

	return false

# Check if a weapon data dictionary (raw, not profile) has Extra Attacks
static func weapon_data_has_extra_attacks(weapon_data: Dictionary) -> bool:
	var special_rules = weapon_data.get("special_rules", "").to_lower()
	if "extra attacks" in special_rules:
		return true
	var keywords = weapon_data.get("keywords", [])
	for keyword in keywords:
		if "extra attacks" in keyword.to_lower():
			return true
	return false

# ==========================================
# MELTA X (T1-1)
# ==========================================

# Get the Melta value (X) from a weapon's keywords or special_rules
# Returns 0 if not a Melta weapon
# MELTA X: Each attack targeting a unit within half range gets +X Damage
static func get_melta_value(weapon_id: String, board: Dictionary = {}) -> int:
	var profile = get_weapon_profile(weapon_id, board)
	if profile.is_empty():
		return 0

	# Check special_rules string for "Melta X" pattern
	var special_rules = profile.get("special_rules", "").to_lower()
	var regex = RegEx.new()
	regex.compile("melta\\s*(\\d+)")
	var result = regex.search(special_rules)
	if result:
		return result.get_string(1).to_int()

	# Check keywords array for "MELTA X" pattern
	var keywords = profile.get("keywords", [])
	for keyword in keywords:
		var kw_result = regex.search(keyword.to_lower())
		if kw_result:
			return kw_result.get_string(1).to_int()

	return 0

# Check if a weapon has the MELTA keyword (case-insensitive)
static func is_melta_weapon(weapon_id: String, board: Dictionary = {}) -> bool:
	return get_melta_value(weapon_id, board) > 0

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

# Check if Big Guns Never Tire -1 to hit / -1 AP / cover penalty applies to this attack.
# Per WH40K 10e core rules, the BGNT penalty applies only when EITHER:
#   (a) the shooter is in engagement range of one or more enemy units, OR
#   (b) the target is in engagement range of one or more friendly models (other than the shooter).
# It does NOT apply simply because the shooter is a MONSTER/VEHICLE — that was the bug
# in the legacy single-arg `big_guns_never_tire_applies(unit)` helper.
static func big_guns_never_tire_penalty_applies(actor_unit: Dictionary, target_unit: Dictionary, board: Dictionary) -> bool:
	# Penalty only applies to MONSTER or VEHICLE shooters
	if not is_monster_or_vehicle(actor_unit):
		return false

	# Branch (a): shooter is itself in engagement
	if actor_unit.get("flags", {}).get("in_engagement", false):
		print("RulesEngine: BGNT penalty applies — shooter is in engagement (branch a)")
		return true

	# Branch (b): target is in engagement of any friendly unit other than the shooter.
	# Reuse the existing _is_target_in_friendly_engagement helper which already implements
	# "any friendly model within 1\" engagement range of any model of target_unit".
	var units = board.get("units", {})
	if units.is_empty():
		return false
	var actor_owner = actor_unit.get("owner", 0)

	# Resolve target_unit_id by reverse-lookup from the board, since the unit dict
	# itself does not always carry an explicit "id" key.
	var target_unit_id = ""
	for uid in units.keys():
		if units[uid] == target_unit:
			target_unit_id = uid
			break
	if target_unit_id == "":
		# Fall back to direct id lookup if present
		target_unit_id = target_unit.get("id", "")
	if target_unit_id == "":
		return false

	# Resolve actor_unit_id similarly so we can exclude the shooter from "friendly" check
	var actor_unit_id = ""
	for uid in units.keys():
		if units[uid] == actor_unit:
			actor_unit_id = uid
			break
	if actor_unit_id == "":
		actor_unit_id = actor_unit.get("id", "")

	if _is_target_in_friendly_engagement(target_unit_id, actor_unit_id, actor_owner, units, board):
		print("RulesEngine: BGNT penalty applies — target is engaged with a friendly unit (branch b)")
		return true

	return false

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

# ADVANCED FIREPOWER (P1-16): Conditional Lethal Hits for Caladius Grav-tank
# Twin iliastus accelerator cannon → Lethal Hits vs non-MONSTER/non-VEHICLE targets
# Twin arachnus heavy blaze cannon → Lethal Hits vs MONSTER or VEHICLE targets
static func check_advanced_firepower_lethal_hits(weapon_id: String, attacker_unit: Dictionary, target_unit: Dictionary, board: Dictionary = {}) -> bool:
	# Check if the attacker has the "Advanced Firepower" ability
	var abilities = attacker_unit.get("meta", {}).get("abilities", [])
	var has_ability = false
	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")
		if ability_name == "Advanced Firepower":
			has_ability = true
			break

	if not has_ability:
		return false

	# Get weapon name from profile
	var weapon_profile = get_weapon_profile(weapon_id, board)
	if weapon_profile.is_empty():
		return false
	var weapon_name = weapon_profile.get("name", "").to_lower()

	# Get target keywords
	var target_keywords = target_unit.get("meta", {}).get("keywords", [])
	var target_is_monster_or_vehicle = false
	for kw in target_keywords:
		if kw.to_upper() in ["MONSTER", "VEHICLE"]:
			target_is_monster_or_vehicle = true
			break

	# Twin iliastus accelerator cannon: Lethal Hits vs non-MONSTER/non-VEHICLE
	if "iliastus" in weapon_name:
		if not target_is_monster_or_vehicle:
			print("RulesEngine: ADVANCED FIREPOWER — Twin iliastus accelerator cannon gains LETHAL HITS (target is not MONSTER/VEHICLE)")
			return true
		else:
			print("RulesEngine: ADVANCED FIREPOWER — Twin iliastus accelerator cannon does NOT gain LETHAL HITS (target is MONSTER/VEHICLE)")
			return false

	# Twin arachnus heavy blaze cannon: Lethal Hits vs MONSTER/VEHICLE
	if "arachnus" in weapon_name:
		if target_is_monster_or_vehicle:
			print("RulesEngine: ADVANCED FIREPOWER — Twin arachnus heavy blaze cannon gains LETHAL HITS (target is MONSTER/VEHICLE)")
			return true
		else:
			print("RulesEngine: ADVANCED FIREPOWER — Twin arachnus heavy blaze cannon does NOT gain LETHAL HITS (target is not MONSTER/VEHICLE)")
			return false

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
# TWIN-LINKED
# ==========================================

# Check if a weapon has the TWIN-LINKED keyword (case-insensitive)
# Twin-linked: Re-roll all failed wound rolls
static func has_twin_linked(weapon_id: String, board: Dictionary = {}) -> bool:
	var profile = get_weapon_profile(weapon_id, board)
	if profile.is_empty():
		return false

	# Check special_rules string for "Twin-linked" (case-insensitive)
	var special_rules = profile.get("special_rules", "").to_lower()
	if "twin-linked" in special_rules:
		return true

	# Check keywords array
	var keywords = profile.get("keywords", [])
	for keyword in keywords:
		if "twin-linked" in keyword.to_lower():
			return true

	return false

# ==========================================
# PRECISION
# ==========================================

# Check if a weapon has the PRECISION keyword (case-insensitive)
# Precision: Attacks that score a Critical Hit can be allocated to CHARACTER models
# Can come from weapon special_rules OR from a stratagem flag on the attacker unit
static func has_precision(weapon_id: String, board: Dictionary = {}) -> bool:
	var profile = get_weapon_profile(weapon_id, board)
	if profile.is_empty():
		return false

	# Check special_rules string for "Precision" (case-insensitive)
	var special_rules = profile.get("special_rules", "").to_lower()
	if "precision" in special_rules:
		return true

	# Check keywords array
	var keywords = profile.get("keywords", [])
	for keyword in keywords:
		if keyword.to_lower() == "precision":
			return true

	return false

# Check if an attacker unit has PRECISION from an effect (e.g., Epic Challenge stratagem, ability)
static func has_effect_precision_melee(attacker_unit: Dictionary) -> bool:
	return EffectPrimitivesData.has_effect_precision_melee(attacker_unit)

# Legacy alias for backwards compatibility
static func has_stratagem_precision_melee(attacker_unit: Dictionary) -> bool:
	return has_effect_precision_melee(attacker_unit)

# Find CHARACTER model indices in a target unit (for PRECISION allocation)
static func _find_character_model_indices(target_unit: Dictionary) -> Array:
	"""Find indices of CHARACTER models in a unit.
	In 10e, CHARACTER models attached as leaders are tracked as models within the unit."""
	var indices = []
	var keywords = target_unit.get("meta", {}).get("keywords", [])

	# Check if the unit itself has CHARACTER keyword
	var unit_is_character = false
	for kw in keywords:
		if kw.to_upper() == "CHARACTER":
			unit_is_character = true
			break

	if unit_is_character:
		# All alive models in this unit are CHARACTER models
		var models = target_unit.get("models", [])
		for i in range(models.size()):
			if models[i].get("alive", true):
				indices.append(i)
		return indices

	# Check individual models for CHARACTER keyword (for attached leaders)
	var models = target_unit.get("models", [])
	for i in range(models.size()):
		var model = models[i]
		if not model.get("alive", true):
			continue
		var model_keywords = model.get("keywords", [])
		for kw in model_keywords:
			if kw.to_upper() == "CHARACTER":
				indices.append(i)
				break

	return indices

# P3-100: Find attached CHARACTER units for PRECISION allocation in auto-resolve path.
# When a bodyguard unit has attached CHARACTER leaders (via attachment_data), those CHARACTERs
# are separate units. This function returns info about those attached CHARACTER models so
# PRECISION damage can be routed to them during Epic Challenge.
static func _find_attached_character_info(target_unit: Dictionary, board: Dictionary) -> Array:
	"""Find attached CHARACTER models from separate leader units.
	Returns array of { unit_id, model_index, model } for each alive CHARACTER model."""
	var result = []
	var attached_chars = target_unit.get("attachment_data", {}).get("attached_characters", [])
	if attached_chars.is_empty():
		return result

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
			result.append({
				"unit_id": char_id,
				"model_index": j,
				"model": char_model
			})

	return result

# P3-100: Apply PRECISION damage to attached CHARACTER models (in separate leader units).
# Used in auto-resolve path when Epic Challenge grants PRECISION and the target is a
# bodyguard unit with an attached CHARACTER leader.
static func _apply_damage_to_attached_characters(attached_chars: Array, total_damage: int, board: Dictionary) -> Dictionary:
	"""Apply damage to attached CHARACTER models (from separate leader units).
	Similar to _apply_damage_to_character_models but handles cross-unit references."""
	var result = {
		"diffs": [],
		"casualties": 0,
		"damage_applied": 0
	}

	var remaining_damage = total_damage

	while remaining_damage > 0:
		# Find next alive attached CHARACTER model (wounded first, then any alive)
		var target_info = {}

		# Wounded CHARACTER first
		for info in attached_chars:
			var model = info.model
			if model.get("alive", true):
				var current = model.get("current_wounds", model.get("wounds", 1))
				var max_w = model.get("wounds", 1)
				if current < max_w:
					target_info = info
					break

		# Then any alive CHARACTER
		if target_info.is_empty():
			for info in attached_chars:
				if info.model.get("alive", true):
					target_info = info
					break

		if target_info.is_empty():
			break  # No alive attached CHARACTER models left

		var model = target_info.model
		var unit_id = target_info.unit_id
		var model_index = target_info.model_index
		var current_wounds = model.get("current_wounds", model.get("wounds", 1))
		var damage_to_apply = min(remaining_damage, current_wounds)
		var new_wounds = current_wounds - damage_to_apply

		result.diffs.append({
			"op": "set",
			"path": "units.%s.models.%d.current_wounds" % [unit_id, model_index],
			"value": new_wounds
		})

		result.damage_applied += damage_to_apply
		remaining_damage -= damage_to_apply
		model["current_wounds"] = new_wounds

		if new_wounds == 0:
			result.diffs.append({
				"op": "set",
				"path": "units.%s.models.%d.alive" % [unit_id, model_index],
				"value": false
			})
			result.casualties += 1
			model["alive"] = false
			# MA-22: Log attached CHARACTER model destruction with model type label
			var attached_unit = board.get("units", {}).get(unit_id, {})
			var attached_label = get_model_display_label(model, attached_unit)
			print("RulesEngine: 💀 %s destroyed (attached CHARACTER)" % attached_label)

	return result

# ==========================================
# ANTI-[KEYWORD] X+
# ==========================================

# Parse ANTI-[KEYWORD] X+ from a weapon's special_rules or keywords
# Returns Array of Dictionaries: [{"keyword": "INFANTRY", "threshold": 4}, ...]
# Example: "anti-infantry 4+" -> [{"keyword": "INFANTRY", "threshold": 4}]
#          "anti-vehicle 4+, anti-infantry 2+" -> [{"keyword": "VEHICLE", "threshold": 4}, {"keyword": "INFANTRY", "threshold": 2}]
static func get_anti_keyword_data(weapon_id: String, board: Dictionary = {}) -> Array:
	var profile = get_weapon_profile(weapon_id, board)
	if profile.is_empty():
		return []

	var results = []

	# Check special_rules string
	var special_rules = profile.get("special_rules", "").to_lower()
	results.append_array(_parse_anti_keywords_from_string(special_rules))

	# Check keywords array
	var keywords = profile.get("keywords", [])
	for keyword in keywords:
		results.append_array(_parse_anti_keywords_from_string(keyword.to_lower()))

	return results

# Parse "anti-X Y+" patterns from a string
# Matches patterns like "anti-infantry 4+", "anti-vehicle 2+"
static func _parse_anti_keywords_from_string(text: String) -> Array:
	var results = []
	var regex = RegEx.new()
	regex.compile("anti-(\\w+)\\s+(\\d+)\\+?")
	var matches = regex.search_all(text)

	for m in matches:
		var keyword = m.get_string(1).to_upper()
		var threshold = m.get_string(2).to_int()
		results.append({"keyword": keyword, "threshold": threshold})

	return results

# Check if weapon has any Anti-keyword ability
static func has_anti_keyword(weapon_id: String, board: Dictionary = {}) -> bool:
	return get_anti_keyword_data(weapon_id, board).size() > 0

# Check if a unit has a specific keyword (case-insensitive)
static func unit_has_keyword(unit: Dictionary, keyword: String) -> bool:
	var keywords = unit.get("meta", {}).get("keywords", [])
	var kw_upper = keyword.to_upper()
	for kw in keywords:
		if kw.to_upper() == kw_upper:
			return true
	return false

# LONE OPERATIVE (T2-2): Check if a unit has the Lone Operative ability
# Per 10e rules: Unless part of an Attached unit, this unit can only be selected as the target
# of a ranged attack if the attacking model is within 12"
# Abilities can be stored as strings ("Lone Operative") or dicts ({"name": "Lone Operative", ...})
static func has_lone_operative(unit: Dictionary) -> bool:
	# ISS-019/069: unified query. Matches the plain "Lone Operative" ability
	# AND the 11e "Lone Operative X\"" variant (whose full name carries the
	# distance, so the exact-match datasheet query alone would miss it).
	if UnitAbilities.unit_has(unit, "lone operative"):
		return true
	for ab in unit.get("meta", {}).get("abilities", []):
		var nm := ""
		if ab is String:
			nm = ab
		elif ab is Dictionary:
			nm = str(ab.get("name", ""))
		if nm.to_lower().contains("lone operative"):
			return true
	return false


## ISS-069 (11e 24.24): "Lone Operative X\"" gates targeting at X" (visibility
## AND [INDIRECT FIRE]); the default form is 12". Parses the first number in
## any ability whose name contains "lone operative". Edition-agnostic — the
## X" variant simply does not occur in 10e data, where 12" is universal.
static func get_lone_operative_range(unit: Dictionary) -> float:
	for ab in unit.get("meta", {}).get("abilities", []):
		var nm := ""
		if ab is String:
			nm = ab
		elif ab is Dictionary:
			nm = str(ab.get("name", ""))
		if nm.to_lower().contains("lone operative"):
			var digits := ""
			for c in nm:
				if c >= "0" and c <= "9":
					digits += c
				elif digits != "":
					break
			if digits != "":
				return float(digits.to_int())
	return 12.0

# OA-19: "Hold Still and Say 'Aargh!'" — Check if unit has this ability (Painboy)
# On Critical Wound with 'urty syringe vs non-VEHICLE, target suffers D6 mortal wounds
static func _has_hold_still_ability(unit: Dictionary) -> bool:
	# ISS-019: unified query.
	return UnitAbilities.has_datasheet_ability(unit, "Hold Still and Say 'Aargh!'")

# Check if `target_unit_id` is the closest enemy unit to `actor_unit_id`.
# Used by Gun-Crazy Show-offs (Ork) — the snazzgun gets +1 Attack when shooting the closest enemy.
# Standalone CHARACTER targeting protection used to gate this in 9e ("Look Out Sir"), but in 10e
# that rule was removed: standalone-character protection now lives entirely in the Lone Operative ability.
static func is_closest_eligible_target(actor_unit_id: String, target_unit_id: String, board: Dictionary) -> bool:
	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})
	var actor_owner = actor_unit.get("owner", 0)

	var target_dist = _get_min_distance_to_target_rules(actor_unit_id, target_unit_id, board)

	# Check all other enemy units to see if any non-protected one is closer
	for other_unit_id in units:
		if other_unit_id == target_unit_id or other_unit_id == actor_unit_id:
			continue

		var other_unit = units[other_unit_id]

		# Must be enemy
		if other_unit.get("owner", 0) == actor_owner:
			continue

		# Skip attached units (targeted through bodyguard)
		if other_unit.get("attached_to", null) != null:
			continue

		# Skip destroyed units
		var has_alive = false
		for model in other_unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue

		# Check distance — if any other valid enemy is closer, this isn't the closest target.
		var other_dist = _get_min_distance_to_target_rules(actor_unit_id, other_unit_id, board)
		if other_dist < target_dist:
			print("RulesEngine: target '%s' (%.1f\") is NOT closest — '%s' is closer (%.1f\")" % [
				units.get(target_unit_id, {}).get("meta", {}).get("name", target_unit_id),
				target_dist,
				other_unit.get("meta", {}).get("name", other_unit_id),
				other_dist
			])
			return false

	# No non-protected unit is closer — this character IS the closest eligible target
	return true

# GUN-CRAZY SHOW-OFFS (OA-9): Check if a unit has the "Gun-crazy Show-offs" ability
# and the weapon is a snazzgun. If so, and the target is the closest eligible enemy,
# the snazzgun's Attacks characteristic becomes 4 (instead of base 3).
static func get_gun_crazy_showoffs_attacks(actor_unit: Dictionary, weapon_id: String, weapon_profile: Dictionary, actor_unit_id: String, target_unit_id: String, board: Dictionary) -> int:
	# Check if the actor unit has the "Gun-crazy Show-offs" ability
	var abilities = actor_unit.get("meta", {}).get("abilities", [])
	var has_ability = false
	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")
		if ability_name == "Gun-crazy Show-offs":
			has_ability = true
			break

	if not has_ability:
		return -1  # -1 means ability not applicable

	# Check if the weapon is a snazzgun
	var weapon_name = weapon_profile.get("name", weapon_id).to_lower()
	if weapon_name.find("snazzgun") == -1:
		return -1  # Not a snazzgun

	# Check if target is the closest eligible enemy unit
	if is_closest_eligible_target(actor_unit_id, target_unit_id, board):
		print("RulesEngine: GUN-CRAZY SHOW-OFFS — %s targeting closest eligible enemy with snazzgun → Attacks = 4" % actor_unit.get("meta", {}).get("name", actor_unit_id))
		return 4
	else:
		print("RulesEngine: GUN-CRAZY SHOW-OFFS — %s targeting non-closest enemy with snazzgun → Attacks = 3 (base)" % actor_unit.get("meta", {}).get("name", actor_unit_id))
		return -1  # Use base attacks (3)

# TANK HUNTERS (OA-11): Check if a unit has the "Tank Hunters" ability
# and the target is a MONSTER or VEHICLE. If so, returns true indicating
# +1 to Hit and +1 to Wound should be applied for ranged attacks.
static func has_tank_hunters_vs_target(actor_unit: Dictionary, target_unit: Dictionary) -> bool:
	var abilities = actor_unit.get("meta", {}).get("abilities", [])
	var has_ability = false
	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")
		if ability_name == "Tank Hunters":
			has_ability = true
			break

	if not has_ability:
		return false

	# Check if target is MONSTER or VEHICLE
	return is_monster_or_vehicle(target_unit)

# MONSTER HUNTERS (OA-49): Check if a unit has the "Monster Hunters" ability
# and the target is a MONSTER or VEHICLE. If so, returns true indicating
# Hit rolls should be re-rolled for melee attacks.
static func has_monster_hunters_vs_target(actor_unit: Dictionary, target_unit: Dictionary) -> bool:
	var abilities = actor_unit.get("meta", {}).get("abilities", [])
	var has_ability = false
	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")
		if ability_name == "Monster Hunters":
			has_ability = true
			break

	if not has_ability:
		return false

	# Check if target is MONSTER or VEHICLE
	return is_monster_or_vehicle(target_unit)

static func has_slayers_of_tyrants_vs_target(actor_unit: Dictionary, target_unit: Dictionary) -> bool:
	var abilities = actor_unit.get("meta", {}).get("abilities", [])
	var has_ability = false
	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")
		if ability_name == "Slayers of Tyrants":
			has_ability = true
			break
	if not has_ability:
		return false
	return unit_has_keyword(target_unit, "CHARACTER") or unit_has_keyword(target_unit, "MONSTER") or unit_has_keyword(target_unit, "VEHICLE")

static func has_captain_general(actor_unit: Dictionary) -> bool:
	var abilities = actor_unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")
		if ability_name == "Captain-General":
			return true
	return false

static func has_xenos_hunter_vs_target(actor_unit: Dictionary, target_unit: Dictionary) -> bool:
	var abilities = actor_unit.get("meta", {}).get("abilities", [])
	var has_ability = false
	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")
		if ability_name == "Xenos Hunter":
			has_ability = true
			break
	if not has_ability:
		return false
	return not unit_has_keyword(target_unit, "IMPERIUM") and not unit_has_keyword(target_unit, "CHAOS")

static func has_purity_of_execution_vs_target(actor_unit: Dictionary, target_unit: Dictionary) -> bool:
	var abilities = actor_unit.get("meta", {}).get("abilities", [])
	var has_ability = false
	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")
		if ability_name == "Purity of Execution":
			has_ability = true
			break
	if not has_ability:
		return false
	return unit_has_keyword(target_unit, "PSYKER")

# DA BIGGER DEY IZ (OA-49): Mozrog Skragbad — +1 Damage to melee attacks vs MONSTER/VEHICLE,
# +2 Damage vs TITANIC. Returns the damage bonus (0, 1, or 2).
# Since Mozrog is a CHARACTER who fights with his own unit_id, this naturally restricts
# the bonus to his attacks only (not the bodyguard unit's).
static func get_da_bigger_damage_bonus(actor_unit: Dictionary, target_unit: Dictionary) -> int:
	var abilities = actor_unit.get("meta", {}).get("abilities", [])
	var has_ability = false
	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")
		if ability_name == "Da Bigger Dey iz...":
			has_ability = true
			break

	if not has_ability:
		return 0

	# TITANIC gets +2, MONSTER/VEHICLE gets +1
	if unit_has_keyword(target_unit, "TITANIC"):
		return 2
	elif is_monster_or_vehicle(target_unit):
		return 1

	return 0

# BEASTLY RAGE: Beastboss on Squigosaur — after charging, this model's melee weapons
# gain [DEVASTATING WOUNDS] until end of turn. Returns true if the unit has the ability
# AND charged this turn. Since characters fight with their own unit_id, this naturally
# restricts the effect to the Beastboss's attacks only (not the bodyguard unit's).
static func has_beastly_rage_active(actor_unit: Dictionary) -> bool:
	var charged = actor_unit.get("flags", {}).get("charged_this_turn", false)
	if not charged:
		return false
	var abilities = actor_unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")
		if ability_name == "Beastly Rage":
			return true
	return false

# DAT'S OUR LOOT! (OA-12): Check if a unit has the "Dat's Our Loot!" ability.
# Returns true if the unit has the ability (Lootas datasheet ability).
static func has_dats_our_loot(actor_unit: Dictionary) -> bool:
	var abilities = actor_unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")
		if ability_name == "Dat's Our Loot!":
			return true
	return false

# DAT'S OUR LOOT! (OA-12): Check if a target unit is within range of ANY objective marker.
# "Within range" means any alive model in the unit has its base edge within the objective
# control range (3" + 20mm objective marker radius = 3.787").
# This is used to determine whether the full re-roll (vs re-roll 1s) applies.
static func is_unit_near_any_objective(unit: Dictionary, board: Dictionary) -> bool:
	var objectives = board.get("board", {}).get("objectives", [])
	if objectives.is_empty():
		return false

	# Objective control range: 3" + 20mm marker base radius = 3.78740157"
	var control_range_px = 3.78740157 * 40.0  # PX_PER_INCH = 40.0

	for obj in objectives:
		var obj_pos = obj.get("position", null)
		if obj_pos == null:
			continue
		if obj_pos is Dictionary:
			obj_pos = Vector2(obj_pos.get("x", 0), obj_pos.get("y", 0))
		elif not (obj_pos is Vector2):
			continue

		for model in unit.get("models", []):
			if not model.get("alive", true):
				continue
			var model_pos = model.get("position", null)
			if model_pos == null:
				continue
			if model_pos is Dictionary:
				model_pos = Vector2(model_pos.get("x", 0), model_pos.get("y", 0))
			elif not (model_pos is Vector2):
				continue

			# Edge-to-edge: subtract model's base radius from center-to-center distance
			var base_mm = model.get("base_mm", 32)
			var base_radius_px = (base_mm / 25.4) * 40.0 / 2.0
			var center_distance = model_pos.distance_to(obj_pos)
			var edge_distance = max(0.0, center_distance - base_radius_px)

			if edge_distance <= control_range_px:
				return true

	return false

# DAT'S OUR LOOT! (OA-12): Get the re-roll scope for a Lootas unit's ranged attacks.
# Returns "failed" if target is within range of any objective marker (full re-roll),
# "ones" if the unit has the ability but target is not near an objective,
# or "" if the unit doesn't have the ability.
static func get_dats_our_loot_reroll_scope(actor_unit: Dictionary, target_unit: Dictionary, board: Dictionary) -> String:
	if not has_dats_our_loot(actor_unit):
		return ""
	if is_unit_near_any_objective(target_unit, board):
		return "failed"
	return "ones"

# SPLAT! (OA-38): Check if a unit has the "Splat!" ability.
# Returns true if the unit has the ability (Big Gunz / Mek Gunz datasheet ability).
static func has_splat(actor_unit: Dictionary) -> bool:
	var abilities = actor_unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")
		if ability_name == "Splat!":
			return true
	return false

# SPLAT! (OA-38): Check if a unit is at Starting Strength (no models destroyed).
# A unit is at Starting Strength if all its models are alive.
static func is_unit_at_starting_strength(unit: Dictionary) -> bool:
	var models = unit.get("models", [])
	for model in models:
		if not model.get("alive", true):
			return false
	return true

# SPLAT! (OA-38): Get the re-roll scope for a unit's Splat! ability.
# Big Gunz: re-roll Hit rolls of 1 when targeting units with 10+ models.
# Mek Gunz: re-roll Hit rolls of 1 when at Starting Strength and targeting non-MONSTER/VEHICLE.
# Returns "ones" if the condition is met, "" otherwise.
static func get_splat_reroll_scope(actor_unit: Dictionary, target_unit: Dictionary) -> String:
	if not has_splat(actor_unit):
		return ""

	var unit_name = actor_unit.get("meta", {}).get("name", "")

	# Big Gunz variant: re-roll 1s when target has 10+ alive models
	if unit_name == "Big Gunz":
		var target_model_count = count_alive_models(target_unit)
		if target_model_count >= 10:
			print("RulesEngine: SPLAT! (Big Gunz) — target has %d models (>=10), re-roll hit 1s" % target_model_count)
			return "ones"
		else:
			print("RulesEngine: SPLAT! (Big Gunz) — target has %d models (<10), no re-roll" % target_model_count)
			return ""

	# Mek Gunz variant: re-roll 1s when at Starting Strength AND target is not MONSTER/VEHICLE
	if unit_name == "Mek Gunz":
		if not is_unit_at_starting_strength(actor_unit):
			print("RulesEngine: SPLAT! (Mek Gunz) — not at Starting Strength, no re-roll")
			return ""
		if is_monster_or_vehicle(target_unit):
			print("RulesEngine: SPLAT! (Mek Gunz) — target is MONSTER/VEHICLE, no re-roll")
			return ""
		print("RulesEngine: SPLAT! (Mek Gunz) — at Starting Strength vs non-MONSTER/VEHICLE, re-roll hit 1s")
		return "ones"

	# Unknown unit with Splat! — log but don't apply
	print("RulesEngine: SPLAT! — unit '%s' has ability but no matching variant" % unit_name)
	return ""

# BLASTAJET ATTACK RUN (OA-40): Check if a unit has the "Blastajet Attack Run" ability.
# Returns true if the unit has the ability (Wazbom Blastajet datasheet ability).
static func has_blastajet_attack_run(actor_unit: Dictionary) -> bool:
	var abilities = actor_unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")
		if ability_name == "Blastajet Attack Run":
			return true
	return false

# BLASTAJET ATTACK RUN (OA-40): Get the re-roll scope for a unit's Blastajet Attack Run ability.
# Re-roll Hit rolls of 1 when targeting non-FLY units.
# Returns "ones" if the target does not have the FLY keyword, "" otherwise.
static func get_blastajet_attack_run_reroll_scope(actor_unit: Dictionary, target_unit: Dictionary) -> String:
	if not has_blastajet_attack_run(actor_unit):
		return ""

	# Re-roll Hit rolls of 1 when targeting non-FLY units
	if not unit_has_keyword(target_unit, "FLY"):
		print("RulesEngine: BLASTAJET ATTACK RUN — target does not have FLY, re-roll hit 1s")
		return "ones"

	print("RulesEngine: BLASTAJET ATTACK RUN — target has FLY, no re-roll")
	return ""

# DRIVE-BY DAKKA (OA-13): Check if a unit has the "Drive-by Dakka" ability.
# Returns true if the unit has the ability (Warbikers / Wartrakks datasheet ability).
static func has_drive_by_dakka(actor_unit: Dictionary) -> bool:
	var abilities = actor_unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")
		if ability_name == "Drive-by Dakka":
			return true
	return false

# DRIVE-BY DAKKA (OA-13): Check if the closest distance between any alive model in the
# attacker unit and any alive model in the target unit is within the given range (inches).
# Used to determine if Drive-by Dakka AP improvement applies (target within 9").
static func is_target_within_range_inches(actor_unit: Dictionary, target_unit: Dictionary, range_inches: float) -> bool:
	for attacker_model in actor_unit.get("models", []):
		if not attacker_model.get("alive", true):
			continue
		var a_pos = attacker_model.get("position", null)
		if a_pos == null:
			continue
		for target_model in target_unit.get("models", []):
			if not target_model.get("alive", true):
				continue
			var t_pos = target_model.get("position", null)
			if t_pos == null:
				continue
			var distance = Measurement.model_to_model_distance_inches(attacker_model, target_model)
			if distance <= range_inches:
				return true
	return false

# DRIVE-BY DAKKA (OA-13): Get AP improvement for Drive-by Dakka.
# Returns 1 if attacker has Drive-by Dakka and target is within 9", otherwise 0.
static func get_drive_by_dakka_ap_bonus(actor_unit: Dictionary, target_unit: Dictionary) -> int:
	if not has_drive_by_dakka(actor_unit):
		return 0
	if is_target_within_range_inches(actor_unit, target_unit, 9.0):
		return 1
	return 0

# WALL OF DAKKA (OA-50): Check if a unit has the "Wall of Dakka" ability (Bonebreaka).
# +1 to Hit rolls for ranged attacks when target is within half the weapon's range.
static func has_wall_of_dakka(unit: Dictionary) -> bool:
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")
		if ability_name == "Wall of Dakka":
			return true
	return false

# PYROMANIAKS (OA-14): Check if a unit has the "Pyromaniaks" ability.
# Returns true if the unit has the ability (Burna Boyz / Skorchas datasheet ability).
static func has_pyromaniaks(actor_unit: Dictionary) -> bool:
	var abilities = actor_unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")
		if ability_name == "Pyromaniaks":
			return true
	return false

# WALL OF DAKKA (OA-50): Get hit bonus for Wall of Dakka.
# Returns 1 if attacker has Wall of Dakka and target is within half weapon range, otherwise 0.
static func get_wall_of_dakka_hit_bonus(actor_unit: Dictionary, target_unit: Dictionary, weapon_profile: Dictionary) -> int:
	if not has_wall_of_dakka(actor_unit):
		return 0
	var weapon_range = weapon_profile.get("range", 24)
	var half_range_inches = weapon_range / 2.0
	if is_target_within_range_inches(actor_unit, target_unit, half_range_inches):
		return 1
	return 0

# DAKKASTORM (OA-16): Check if a unit has the "Dakkastorm" ability (Dakkajet).
# Every successful Hit roll scores a Critical Hit for ranged attacks.
static func has_dakkastorm(unit: Dictionary) -> bool:
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")
		if ability_name == "Dakkastorm":
			return true
	return false

# DA BOSS' LADZ (OA-15): Check if a unit has the "Da Boss' Ladz" ability.
# Returns true if the unit has the ability (Nobz datasheet ability).
static func has_da_boss_ladz(unit: Dictionary) -> bool:
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")
		if ability_name == "Da Boss' Ladz":
			return true
	return false

# DA BOSS' LADZ (OA-15): Check if a Warboss model is leading the given unit.
# A Warboss is identified by the WARBOSS keyword on an attached CHARACTER unit.
# Returns true if at least one alive Warboss model is attached as leader.
static func is_warboss_leading_unit(unit: Dictionary, board: Dictionary) -> bool:
	var attached_chars = unit.get("attachment_data", {}).get("attached_characters", [])
	if attached_chars.is_empty():
		return false
	var units = board.get("units", {})
	for char_id in attached_chars:
		var char_unit = units.get(char_id, {})
		if char_unit.is_empty():
			continue
		# Check if character has WARBOSS keyword
		if not unit_has_keyword(char_unit, "WARBOSS"):
			continue
		# Check if at least one model in the character unit is alive
		var char_models = char_unit.get("models", [])
		for char_model in char_models:
			if char_model.get("alive", true):
				return true
	return false

# DA BOSS' LADZ (OA-15): Get wound modifier for Da Boss' Ladz.
# Returns WoundModifier.MINUS_ONE if the target unit has "Da Boss' Ladz", a Warboss is
# leading it, and the attack Strength is greater than the unit's Toughness.
# Otherwise returns WoundModifier.NONE.
static func get_da_boss_ladz_wound_modifier(target_unit: Dictionary, board: Dictionary, strength: int, toughness: int) -> int:
	if not has_da_boss_ladz(target_unit):
		return WoundModifier.NONE
	if strength <= toughness:
		return WoundModifier.NONE
	if not is_warboss_leading_unit(target_unit, board):
		return WoundModifier.NONE
	return WoundModifier.MINUS_ONE

# PYROMANIAKS (OA-14): Get the wound re-roll scope for Pyromaniaks.
# Only applies to Torrent weapons (burna, Skorcha, etc.) against targets within 6".
# Returns "failed" if target is within 6" AND within range of any objective marker (full re-roll),
# "ones" if target is within 6" but not near an objective (re-roll 1s only),
# or "" if the unit doesn't have the ability, weapon isn't Torrent, or target is beyond 6".
static func get_pyromaniaks_reroll_scope(actor_unit: Dictionary, target_unit: Dictionary, weapon_id: String, board: Dictionary) -> String:
	if not has_pyromaniaks(actor_unit):
		return ""
	# Only applies to Torrent weapons (burna, Skorcha, etc.)
	if not is_torrent_weapon(weapon_id, board):
		return ""
	# Target must be within 6" of the attacker
	if not is_target_within_range_inches(actor_unit, target_unit, 6.0):
		return ""
	# If target is also within range of any objective marker, allow full re-roll
	if is_unit_near_any_objective(target_unit, board):
		return "failed"
	# Otherwise just re-roll wound rolls of 1
	return "ones"

# STEALTH (T2-1): Check if a unit has the Stealth ability
# Per 10e rules: If all models in a unit have Stealth, ranged attacks targeting it get -1 to hit
# Abilities can be stored as strings ("Stealth") or dicts ({"name": "Stealth", ...})
static func has_stealth_ability(unit: Dictionary) -> bool:
	# ISS-019: unified query — covers datasheet abilities AND the
	# effect_stealth flag (dynamically granted, e.g. Smokescreen-likes).
	return UnitAbilities.unit_has(unit, "stealth")

# DAMAGED PROFILE (P1-14): Check if a unit's Damaged profile is active
# Per 10e rules: When a model with a Damaged profile has wounds remaining at or below
# the threshold, subtract 1 from Hit rolls when that model attacks.
# The ability name format is "Damaged: 1-X Wounds Remaining" where X is the threshold.
# Returns true if the unit has a Damaged ability and its current wounds are within the threshold.
static func is_damaged_profile_active(unit: Dictionary) -> bool:
	var abilities = unit.get("meta", {}).get("abilities", [])
	var threshold = 0
	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")
		if ability_name.begins_with("Damaged:"):
			# Parse threshold from "Damaged: 1-X Wounds Remaining"
			var regex_match = ability_name.split("-")
			if regex_match.size() >= 2:
				# Extract the number after the dash, e.g. "5 Wounds Remaining" -> 5
				var after_dash = regex_match[1].strip_edges()
				threshold = after_dash.to_int()
			break

	if threshold <= 0:
		return false

	# Check current wounds of the model (vehicles are single-model units)
	var models = unit.get("models", [])
	for model in models:
		if model.get("alive", true):
			var current_wounds = model.get("current_wounds", 0)
			if current_wounds > 0 and current_wounds <= threshold:
				return true
	return false

# Get the effective critical wound threshold for a weapon against a target
# Returns 6 normally (only unmodified 6s are critical wounds)
# Returns lower value if weapon has Anti-[Keyword] matching the target
static func get_critical_wound_threshold(weapon_id: String, target_unit: Dictionary, board: Dictionary = {}) -> int:
	var anti_data = get_anti_keyword_data(weapon_id, board)
	if anti_data.is_empty():
		return 6  # Default: only 6s are critical wounds

	# ISS-059 (11e 19.03): ANTI-[KEYWORD] matches against the ATTACHED
	# unit's keyword union (the pg-67 ANTI-PSYKER example) — a leader's
	# keyword exposes the whole unit even when attacks are allocated to
	# bodyguard models.
	var union_keywords: Array = []
	if GameConstants.edition >= 11:
		var cam = Engine.get_main_loop().root.get_node_or_null("CharacterAttachmentManager")
		if cam != null and (target_unit.get("attachment_data", {}).get("attached_characters", []).size() > 0 \
				or target_unit.get("attached_to") != null):
			union_keywords = cam.attached_unit_keywords(str(target_unit.get("id", "")))

	var lowest_threshold = 6
	for anti in anti_data:
		var matches = unit_has_keyword(target_unit, anti.keyword)
		if not matches and not union_keywords.is_empty():
			for kw in union_keywords:
				if str(kw).to_upper() == str(anti.keyword).to_upper():
					matches = true
					break
		if matches:
			lowest_threshold = min(lowest_threshold, anti.threshold)

	return lowest_threshold

# ==========================================
# CONVERSION X+ (T4-16)
# ==========================================

# Get Conversion threshold from a weapon's special_rules or keywords
# Returns 0 if weapon does not have Conversion, or the threshold value (e.g. 4 for "Conversion 4+")
# Conversion X+: When firing at a target 12"+ away, critical hits on X+ instead of only 6
static func get_conversion_threshold(weapon_id: String, board: Dictionary = {}) -> int:
	var profile = get_weapon_profile(weapon_id, board)
	if profile.is_empty():
		return 0

	# Check special_rules string for "Conversion X+" (case-insensitive)
	var special_rules = profile.get("special_rules", "").to_lower()
	var result = _parse_conversion_from_string(special_rules)
	if result > 0:
		return result

	# Check keywords array
	var keywords = profile.get("keywords", [])
	for keyword in keywords:
		result = _parse_conversion_from_string(keyword.to_lower())
		if result > 0:
			return result

	return 0

# Parse "conversion X+" from a string — returns the threshold (e.g. 4) or 0 if not found
static func _parse_conversion_from_string(text: String) -> int:
	var regex = RegEx.new()
	regex.compile("conversion\\s+(\\d+)\\+?")
	var match = regex.search(text)
	if match:
		return match.get_string(1).to_int()
	return 0

# Check if a weapon has the Conversion ability
static func has_conversion(weapon_id: String, board: Dictionary = {}) -> bool:
	return get_conversion_threshold(weapon_id, board) > 0

# Get the critical hit threshold for a weapon, considering Conversion and distance
# Returns 6 normally, or lower if Conversion applies at distance
# Parameters:
#   weapon_id: The weapon to check
#   actor_unit: The attacking unit
#   target_unit: The target unit
#   model_ids: The model IDs of attacking models
#   board: The board state
# For Conversion X+: if ANY attacking model is 12"+ from the closest target model,
# the critical hit threshold is lowered to X for all attacks (conservative approach)
static func get_critical_hit_threshold(weapon_id: String, actor_unit: Dictionary, target_unit: Dictionary, model_ids: Array, board: Dictionary) -> int:
	var conversion_threshold = get_conversion_threshold(weapon_id, board)
	if conversion_threshold <= 0:
		return 6  # Default: only 6s are critical hits

	# Check distance: Conversion only applies at 12"+ from target
	# Use the closest attacking model's distance to the closest target model
	var min_distance_inches = _get_min_distance_to_target(actor_unit, target_unit, model_ids)
	if min_distance_inches >= 12.0:
		print("RulesEngine: CONVERSION %d+ active — closest model is %.1f\" from target (>= 12\")" % [conversion_threshold, min_distance_inches])
		return conversion_threshold
	else:
		print("RulesEngine: CONVERSION %d+ NOT active — closest model is %.1f\" from target (< 12\")" % [conversion_threshold, min_distance_inches])
		return 6  # Too close, normal crit threshold

# Get the minimum distance (in inches) from any attacking model to the closest target model
static func _get_min_distance_to_target(actor_unit: Dictionary, target_unit: Dictionary, model_ids: Array) -> float:
	var min_distance = INF

	for model_id in model_ids:
		var model = _get_model_by_id(actor_unit, model_id)
		if not model or not model.get("alive", true):
			continue

		for target_model in target_unit.get("models", []):
			if not target_model.get("alive", true):
				continue

			var edge_distance_px = Measurement.model_to_model_distance_px(model, target_model)
			var edge_distance_inches = Measurement.px_to_inches(edge_distance_px)
			min_distance = min(min_distance, edge_distance_inches)

	return min_distance

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

	# Per 10e Blast rules: +1 attack for every 5 models in the target unit (rounding down)
	return int(model_count / 5)

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
# T3-9: Now barricade-aware (2" ER through barricades)
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

			# T3-9: Use barricade-aware engagement range (2" through barricades)
			var effective_er = _get_effective_engagement_range_rules(pos1, pos2, board)
			if Measurement.is_in_engagement_range_shape_aware(model1, model2, effective_er):
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
	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})
	var target_unit = units.get(target_unit_id, {})

	# Check if weapon has BLAST natively or via Deck Fraggers (OA-7)
	var has_blast = is_blast_weapon(weapon_id, board)
	if not has_blast:
		# DECK FRAGGERS (OA-7): Ranged weapons gain BLAST when targeting INFANTRY
		if actor_unit.get("flags", {}).get("effect_deck_fraggers", false):
			if unit_has_keyword(target_unit, "INFANTRY"):
				var wp = get_weapon_profile(weapon_id, board)
				var wp_type = wp.get("type", "")
				if wp_type.to_lower() == "ranged" or wp.get("range", 0) > 0:
					has_blast = true
	if not has_blast:
		return {"valid": true, "errors": []}
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

# ==========================================
# HAZARDOUS KEYWORD (T2-3)
# ==========================================

# Check if a weapon has the HAZARDOUS keyword
# Hazardous weapons: After attacking, roll D6; on 1, bearer takes self-damage
# CHARACTER/VEHICLE/MONSTER: 3 mortal wounds per 1
# Other models: 1 model destroyed per 1
static func is_hazardous_weapon(weapon_id: String, board: Dictionary = {}) -> bool:
	var profile = get_weapon_profile(weapon_id, board)
	if profile.is_empty():
		return false

	# Check special_rules string for "Hazardous" (case-insensitive)
	var special_rules = profile.get("special_rules", "").to_lower()
	if "hazardous" in special_rules:
		return true

	# Check keywords array
	var keywords = profile.get("keywords", [])
	for keyword in keywords:
		if keyword.to_upper() == "HAZARDOUS":
			return true

	return false

# Resolve Hazardous self-damage check after a weapon has fired
# Per Balance Dataslate v3.3: Roll D6 per Hazardous weapon fired. On a 1:
#   - Unit suffers 3 mortal wounds allocated to a selected model (no spillover)
#   - Allocation priority: (1) wounded model with Hazardous weapon,
#     (2) non-Character with Hazardous, (3) Character with Hazardous
# Returns { hazardous_triggered, rolls, ones_rolled, diffs, dice, log_text }
static func resolve_hazardous_check(
	actor_unit_id: String,
	weapon_id: String,
	models_that_fired: int,
	board: Dictionary,
	rng: RNGService
) -> Dictionary:
	var result = {
		"hazardous_triggered": false,
		"rolls": [],
		"ones_rolled": 0,
		"diffs": [],
		"dice": [],
		"log_text": ""
	}

	if not is_hazardous_weapon(weapon_id, board):
		return result

	# Roll D6 for each model that fired this Hazardous weapon
	var rolls = rng.roll_d6(models_that_fired)
	result.rolls = rolls

	var ones_rolled = 0
	for roll in rolls:
		if roll == 1:
			ones_rolled += 1
	result.ones_rolled = ones_rolled

	var weapon_profile = get_weapon_profile(weapon_id, board)
	var weapon_name = weapon_profile.get("name", weapon_id)

	print("RulesEngine: [HAZARDOUS] %s — rolled %s, ones: %d" % [weapon_name, str(rolls), ones_rolled])

	# Build dice log entry
	result.dice.append({
		"context": "hazardous_check",
		"weapon_id": weapon_id,
		"weapon_name": weapon_name,
		"rolls": rolls,
		"ones_rolled": ones_rolled,
		"models_checked": models_that_fired,
		"triggered": ones_rolled > 0,
		"message": "Hazardous check for %s: rolled %s — %d ones" % [weapon_name, str(rolls), ones_rolled]
	})

	if ones_rolled == 0:
		result.log_text = "Hazardous check: %s safe (%s)" % [weapon_name, str(rolls)]
		print("RulesEngine: [HAZARDOUS] No ones rolled — safe")
		return result

	result.hazardous_triggered = true

	# Balance Dataslate v3.3: Always 3 mortal wounds per 1 rolled, allocated to selected model
	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})
	var models = actor_unit.get("models", [])
	var total_mw = 3 * ones_rolled

	# Find allocation target using Hazardous-specific priority (Balance Dataslate v3.3):
	#   (1) wounded model with Hazardous weapon
	#   (2) non-Character model with Hazardous weapon
	#   (3) Character model with Hazardous weapon
	var target_model_idx = _find_hazardous_allocation_target(models, weapon_id, board)

	if target_model_idx < 0:
		# Fallback: no valid target found, use standard allocation
		print("RulesEngine: [HAZARDOUS] No valid allocation target — using standard allocation")
		target_model_idx = _find_allocation_target_model(models)

	if target_model_idx >= 0:
		var target_model = models[target_model_idx]
		var model_name = target_model.get("name", target_model.get("id", "model_%d" % target_model_idx))
		print("RulesEngine: [HAZARDOUS] Allocating %d mortal wounds to model '%s' (idx %d)" % [total_mw, model_name, target_model_idx])

		# Apply mortal wounds to this specific model (no spillover per Balance Dataslate v3.3)
		var current_wounds = target_model.get("current_wounds", target_model.get("wounds", 1))

		# Check for Feel No Pain
		# MA-28: Use per-model FNP for the specific model taking hazardous damage
		var fnp_value = get_model_fnp(actor_unit, target_model)
		var actual_mw = total_mw
		var fnp_rolls_arr = []

		if fnp_value > 0:
			var fnp_result = roll_feel_no_pain(total_mw, fnp_value, rng)
			actual_mw = fnp_result.get("wounds_remaining", total_mw)
			fnp_rolls_arr = fnp_result.get("rolls", [])
			print("RulesEngine: [HAZARDOUS] FNP %d+ check — %d MW reduced to %d" % [fnp_value, total_mw, actual_mw])

		var damage_to_apply = min(actual_mw, current_wounds)
		var new_wounds = current_wounds - damage_to_apply
		var casualties = 0

		if damage_to_apply > 0:
			result.diffs.append({
				"op": "set",
				"path": "units.%s.models.%d.current_wounds" % [actor_unit_id, target_model_idx],
				"value": new_wounds
			})
			models[target_model_idx]["current_wounds"] = new_wounds

		if new_wounds <= 0:
			result.diffs.append({
				"op": "set",
				"path": "units.%s.models.%d.alive" % [actor_unit_id, target_model_idx],
				"value": false
			})
			models[target_model_idx]["alive"] = false
			casualties = 1
			# MA-22: Log hazardous model destruction with model type label
			var haz_label = get_model_display_label(target_model, actor_unit)
			print("RulesEngine: 💀 %s destroyed (Hazardous)" % haz_label)

		# MA-22: Use model display label in hazardous log text
		var haz_display = get_model_display_label(target_model, actor_unit)
		result.log_text = "HAZARDOUS! %s: %d ones → %d mortal wounds to %s (%d wounds applied)" % [
			weapon_name, ones_rolled, total_mw, haz_display, damage_to_apply
		]

		result.dice.append({
			"context": "hazardous_damage",
			"damage_type": "mortal_wounds",
			"mortal_wounds": total_mw,
			"wounds_applied": damage_to_apply,
			"casualties": casualties,
			"fnp_rolls": fnp_rolls_arr,
			"target_model_idx": target_model_idx,
			"message": "Hazardous: %d mortal wounds to %s" % [total_mw, actor_unit.get("meta", {}).get("name", actor_unit_id)]
		})
	else:
		# No alive models at all
		result.log_text = "HAZARDOUS! %s: %d ones → no alive models to allocate to" % [weapon_name, ones_rolled]
		print("RulesEngine: [HAZARDOUS] No alive models to allocate mortal wounds to")

	print("RulesEngine: [HAZARDOUS] Result: %s" % result.log_text)
	return result

# Balance Dataslate v3.3 Hazardous allocation priority:
#   (1) wounded model with Hazardous weapon
#   (2) non-Character model with Hazardous weapon
#   (3) Character model with Hazardous weapon
static func _find_hazardous_allocation_target(models: Array, hazardous_weapon_id: String, board: Dictionary) -> int:
	# Build list of alive model indices with whether they have a Hazardous weapon and are CHARACTER
	var candidates = []
	for i in range(models.size()):
		var model = models[i]
		if not model.get("alive", true):
			continue

		var has_hazardous = _model_has_hazardous_weapon(model, board)
		var is_character = _model_is_character(model)
		var current_wounds = model.get("current_wounds", model.get("wounds", 1))
		var max_wounds = model.get("wounds_max", model.get("wounds", 1))
		var is_wounded = current_wounds < max_wounds

		candidates.append({
			"idx": i,
			"has_hazardous": has_hazardous,
			"is_character": is_character,
			"is_wounded": is_wounded
		})

	if candidates.is_empty():
		return -1

	# Priority 1: wounded model with Hazardous weapon
	for c in candidates:
		if c.is_wounded and c.has_hazardous:
			print("RulesEngine: [HAZARDOUS] Allocation priority 1 — wounded model with Hazardous weapon (idx %d)" % c.idx)
			return c.idx

	# Priority 2: non-Character model with Hazardous weapon
	for c in candidates:
		if c.has_hazardous and not c.is_character:
			print("RulesEngine: [HAZARDOUS] Allocation priority 2 — non-Character with Hazardous weapon (idx %d)" % c.idx)
			return c.idx

	# Priority 3: Character model with Hazardous weapon
	for c in candidates:
		if c.has_hazardous and c.is_character:
			print("RulesEngine: [HAZARDOUS] Allocation priority 3 — Character with Hazardous weapon (idx %d)" % c.idx)
			return c.idx

	# Fallback: any alive model (shouldn't happen since at least the firing model has the weapon)
	print("RulesEngine: [HAZARDOUS] Allocation fallback — first alive model (idx %d)" % candidates[0].idx)
	return candidates[0].idx

# Check if a specific model has any Hazardous weapon equipped
static func _model_has_hazardous_weapon(model: Dictionary, board: Dictionary) -> bool:
	var weapons = model.get("weapons", [])
	for weapon in weapons:
		var wid = ""
		if weapon is Dictionary:
			wid = weapon.get("id", weapon.get("weapon_id", ""))
		elif weapon is String:
			wid = weapon
		if wid != "" and is_hazardous_weapon(wid, board):
			return true
	return false

# Check if a model is a CHARACTER (via model-level or keywords)
static func _model_is_character(model: Dictionary) -> bool:
	# Check model-level keywords
	var model_keywords = model.get("keywords", [])
	for kw in model_keywords:
		if kw.to_upper() == "CHARACTER":
			return true
	# Check if model has a "is_character" flag
	if model.get("is_character", false):
		return true
	return false

# ==========================================
# INDIRECT FIRE KEYWORD (T2-4)
# ==========================================

# Check if a weapon has the INDIRECT FIRE keyword
# Indirect Fire weapons: Can shoot without LoS, but:
# - -1 to hit
# - Unmodified hit rolls of 1-3 always fail (instead of just 1)
# - Target always gains Benefit of Cover
static func has_indirect_fire(weapon_id: String, board: Dictionary = {}) -> bool:
	var profile = get_weapon_profile(weapon_id, board)
	if profile.is_empty():
		return false

	# Check special_rules string for "Indirect Fire" (case-insensitive)
	var special_rules = profile.get("special_rules", "").to_lower()
	if "indirect fire" in special_rules:
		return true

	# Check keywords array
	var keywords = profile.get("keywords", [])
	for keyword in keywords:
		if keyword.to_upper() == "INDIRECT FIRE":
			return true

	return false

# Check if a unit has any Rapid Fire weapons
static func unit_has_rapid_fire_weapons(unit_id: String, board: Dictionary = {}) -> bool:
	var unit_weapons = get_unit_weapons(unit_id, board)
	for model_id in unit_weapons:
		for weapon_id in unit_weapons[model_id]:
			if is_rapid_fire_weapon(weapon_id, board):
				return true
	return false

static func _profile_is_psychic(profile: Dictionary) -> bool:
	"""Issue #388: detect PSYCHIC weapon from a profile dict."""
	var special_rules = String(profile.get("special_rules", "")).to_lower()
	if "psychic" in special_rules:
		return true
	var keywords = profile.get("keywords", [])
	for kw in keywords:
		if String(kw).to_upper() == "PSYCHIC":
			return true
	return false

static func is_psychic_weapon(weapon_id: String, board: Dictionary = {}) -> bool:
	"""Issue #388: detect PSYCHIC weapon ability via special_rules / keywords.
	Used to gate get_unit_fnp_for_attack() so FNP-vs-psychic (Daughters of the
	Abyss, Null Aegis) applies to non-mortal psychic damage."""
	var profile = get_weapon_profile(weapon_id, board)
	if profile.is_empty():
		return false
	return _profile_is_psychic(profile)

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

# SPLIT-FIRE / PER-MODEL LOS+RANGE (Issue #split-fire):
# For a given (actor_unit, weapon, target_unit), determine which individual
# alive models carrying that weapon can legally fire it at the target right
# now — i.e. they are within weapon range AND have Line of Sight (or the
# weapon is Indirect Fire). Engagement-range / Pistol restrictions are
# unit-level and are gated upstream by get_eligible_targets; this helper
# trusts that and only checks per-model range + LoS.
#
# Returns a dictionary with the shape:
#   {
#     "eligible": Array[String],   # model_ids that can fire this weapon at the target
#     "reasons":  Dictionary       # { model_id: "out_of_range" | "no_los" | "dead" }
#                                  # (only carriers of this weapon appear in reasons)
#     "distances": Dictionary      # { model_id: edge-to-edge distance in inches to nearest target model }
#   }
#
# Used by:
#  - ShootingController/ShootingPhase to cap the split-fire "how many to this target?" picker
#  - _resolve_assignment_until_wounds to re-validate at resolve time (drops models that
#    became ineligible between assignment and resolve)
static func get_eligible_shooter_models(
	actor_unit_id: String,
	weapon_id: String,
	target_unit_id: String,
	board: Dictionary
) -> Dictionary:
	var result := {"eligible": [], "reasons": {}, "distances": {}}

	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})
	var target_unit = units.get(target_unit_id, {})
	if actor_unit.is_empty() or target_unit.is_empty():
		return result

	var weapon_profile = get_weapon_profile(weapon_id, board)
	if weapon_profile.is_empty():
		return result

	var weapon_range_inches = float(weapon_profile.get("range", 12))
	var is_indirect = has_indirect_fire(weapon_id, board)

	var unit_weapons = get_unit_weapons(actor_unit_id, board)
	var target_models = target_unit.get("models", [])

	# Pre-compute alive target models so we don't repeat the filter per shooter
	var alive_targets: Array = []
	for tm in target_models:
		if tm.get("alive", true):
			alive_targets.append(tm)

	for model_id in unit_weapons:
		# Only consider models that actually carry this weapon
		if not (weapon_id in unit_weapons[model_id]):
			continue

		var actor_model = _get_model_by_id(actor_unit, model_id)
		if actor_model.is_empty():
			continue
		if not actor_model.get("alive", true):
			result.reasons[model_id] = "dead"
			continue

		var actor_pos = _get_model_position(actor_model)
		# EnhancedLineOfSight treats Vector2.ZERO as "invalid position"
		# project-wide. Real game state never places a model at the board
		# origin, but test fixtures sometimes do — when actor_pos is unset,
		# we still do the range check below but skip per-model LoS so we
		# don't false-positive a "no LoS" reason.
		var actor_pos_unset: bool = (actor_pos == Vector2.ZERO)

		# Find nearest alive target model by edge-to-edge distance
		var nearest_inches := INF
		var nearest_target: Dictionary = {}
		for tm in alive_targets:
			var edge_px = Measurement.model_to_model_distance_px(actor_model, tm)
			var edge_inches = Measurement.px_to_inches(edge_px)
			if edge_inches < nearest_inches:
				nearest_inches = edge_inches
				nearest_target = tm

		if nearest_target.is_empty():
			result.reasons[model_id] = "out_of_range"
			continue

		result.distances[model_id] = nearest_inches

		# Range check
		if nearest_inches > weapon_range_inches:
			result.reasons[model_id] = "out_of_range"
			continue

		# LoS check (skipped for Indirect Fire weapons OR when actor position
		# is the engine's invalid-position sentinel)
		if is_indirect or actor_pos_unset:
			result.eligible.append(model_id)
			continue

		# Per-model LoS: this specific actor model must see at least one alive
		# target model (we test against the nearest first since it's likeliest
		# to be visible; if not, sweep the rest).
		var target_pos = _get_model_position(nearest_target)
		var has_los := false
		if target_pos != Vector2.ZERO:
			has_los = _check_line_of_sight(actor_pos, target_pos, board, actor_model, nearest_target)
		if not has_los:
			for tm in alive_targets:
				if tm == nearest_target:
					continue
				var tpos = _get_model_position(tm)
				if tpos == Vector2.ZERO:
					continue
				if _check_line_of_sight(actor_pos, tpos, board, actor_model, tm):
					has_los = true
					break

		if has_los:
			result.eligible.append(model_id)
		else:
			result.reasons[model_id] = "no_los"

	return result

# SPLIT-FIRE / PER-MODEL LOS+RANGE: Resolve-time filter. Returns the subset of
# the requested model_ids that are still eligible to fire weapon_id at
# target_unit_id, plus the list that was dropped (for logging).
static func _filter_eligible_model_ids(
	model_ids: Array,
	actor_unit_id: String,
	weapon_id: String,
	target_unit_id: String,
	board: Dictionary
) -> Dictionary:
	var eligibility = get_eligible_shooter_models(actor_unit_id, weapon_id, target_unit_id, board)

	# DEFENSIVE FALLBACK: If eligibility returned zero candidates AND zero
	# reasons, the unit has no weapon-carrier data the engine can parse
	# (common in headless test fixtures that don't populate unit.meta.weapons).
	# In that case the caller's model_ids are the source of truth — trust them
	# and don't filter, so legacy code paths and fixtures keep working.
	if eligibility.eligible.is_empty() and eligibility.reasons.is_empty():
		return {"kept": model_ids.duplicate(), "dropped": [], "reasons": {}}

	var eligible_set := {}
	for mid in eligibility.eligible:
		eligible_set[mid] = true
	var kept: Array = []
	var dropped: Array = []
	for mid in model_ids:
		if eligible_set.has(mid):
			kept.append(mid)
		else:
			dropped.append(mid)
	return {"kept": kept, "dropped": dropped, "reasons": eligibility.reasons}

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
	# cannot_charge is set by Advance and Fall Back moves, but abilities like
	# Waaagh! (advance_and_charge) or Full Throttle (fall_back_and_charge) can override it.
	if flags.get("cannot_charge", false):
		var can_override = false
		if flags.get("advanced", false) and EffectPrimitivesData.has_effect_advance_and_charge(unit):
			can_override = true
		if flags.get("fell_back", false) and EffectPrimitivesData.has_effect_fall_back_and_charge(unit):
			can_override = true
		if not can_override:
			return false

	if flags.get("advanced", false):
		if not EffectPrimitivesData.has_effect_advance_and_charge(unit):
			return false

	if flags.get("fell_back", false):
		if not EffectPrimitivesData.has_effect_fall_back_and_charge(unit):
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

	# T2-9: Check if charging unit has FLY keyword (needed to charge AIRCRAFT targets)
	var charger_keywords = unit.get("meta", {}).get("keywords", [])
	var charger_has_fly = "FLY" in charger_keywords

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

		# T2-9: Only FLY units can charge AIRCRAFT targets
		var target_keywords = target_unit.get("meta", {}).get("keywords", [])
		if "AIRCRAFT" in target_keywords and not charger_has_fly:
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

	# T2-8: Check if unit has FLY keyword for terrain penalty calculation
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	var unit_keywords = unit.get("meta", {}).get("keywords", [])
	var has_fly = "FLY" in unit_keywords

	# 1. Validate path distances (including terrain penalty - T2-8)
	for model_id in paths:
		var path = paths[model_id]
		if path is Array and path.size() >= 2:
			var path_distance = Measurement.distance_polyline_inches(path)

			# T2-8: Calculate terrain vertical distance penalty
			var terrain_penalty = _calculate_charge_terrain_penalty_rules(path, has_fly, board, unit_keywords)
			var effective_distance = path_distance + terrain_penalty

			if effective_distance > roll:
				if terrain_penalty > 0.0:
					errors.append("Model %s path (%.1f\") + terrain penalty (%.1f\") = %.1f\" exceeds charge distance %d\"" % [
						model_id, path_distance, terrain_penalty, effective_distance, roll])
				else:
					errors.append("Model %s path exceeds charge distance: %.1f\" > %d\"" % [model_id, path_distance, roll])
				auto_fix_suggestions.append("Reduce path length for model %s" % model_id)
	
	# 2. T3-8: Validate each model ends closer to at least one charge target
	var direction_validation = _validate_charge_direction_constraint_rules(unit_id, paths, targets, board)
	if not direction_validation.valid:
		errors.append_array(direction_validation.errors)
		auto_fix_suggestions.append("Move models closer to declared charge targets")

	# 3. Validate engagement range with ALL targets
	var engagement_validation = _validate_engagement_range_constraints_rules(unit_id, paths, targets, board)
	if not engagement_validation.valid:
		errors.append_array(engagement_validation.errors)
		auto_fix_suggestions.append("Adjust final positions to reach all targets")

	# 4. Validate unit coherency
	var coherency_validation = _validate_unit_coherency_for_charge_rules(unit_id, paths, board)
	if not coherency_validation.valid:
		errors.append_array(coherency_validation.errors)
		auto_fix_suggestions.append("Move models closer together to maintain coherency")

	# 5. Validate base-to-base if possible
	var base_to_base_validation = _validate_base_to_base_possible_rules(unit_id, paths, targets, board, roll)
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

				# T3-9: Use barricade-aware engagement range
				var effective_er = _get_effective_engagement_range_rules(model_pos, enemy_pos, board)
				if Measurement.is_in_engagement_range_shape_aware(model, enemy_model, effective_er):
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

# Calculate terrain penalty for a charge path segment.
# Units are always assumed to stay on the ground floor, so there is no
# vertical climbing penalty for terrain height.
# Difficult ground penalties are handled by TerrainManager when available.
static func _calculate_charge_terrain_penalty_rules(path: Array, has_fly: bool, board: Dictionary, unit_keywords: Array = []) -> float:
	var total_penalty: float = 0.0
	var terrain_features = board.get("terrain_features", [])
	if terrain_features.is_empty():
		# Fall back to TerrainManager autoload if terrain not in board dict
		var terrain_manager = Engine.get_singleton("TerrainManager") if Engine.has_singleton("TerrainManager") else null
		if terrain_manager == null:
			# Try node path
			var tree = Engine.get_main_loop()
			if tree and tree.has_method("get_root"):
				var root = tree.get_root()
				if root:
					terrain_manager = root.get_node_or_null("TerrainManager")
		if terrain_manager and terrain_manager.has_method("calculate_charge_terrain_penalty"):
			# Delegate to TerrainManager for each path segment.
			# Pass unit_keywords so INFANTRY can traverse ruins without paying the climb penalty.
			for i in range(1, path.size()):
				var from_pos = _path_point_to_vector2(path[i - 1])
				var to_pos = _path_point_to_vector2(path[i])
				if from_pos != null and to_pos != null:
					total_penalty += terrain_manager.calculate_charge_terrain_penalty(from_pos, to_pos, has_fly, unit_keywords)
			return total_penalty

	# No height/climbing penalty — units always stay on the ground floor.
	# Without TerrainManager, we cannot check difficult_ground traits,
	# so return 0.
	return total_penalty

# Helper to convert a path point (Vector2 or Array) to Vector2
static func _path_point_to_vector2(point) -> Vector2:
	if point is Vector2:
		return point
	elif point is Array and point.size() >= 2:
		return Vector2(point[0], point[1])
	return Vector2.ZERO

## T3-9: Get the effective engagement range between two positions considering barricade terrain.
## Returns 2" if a barricade terrain feature lies between the two positions, 1" otherwise.
## Uses board terrain_features data when available, falls back to TerrainManager autoload.
static func _get_effective_engagement_range_rules(pos1: Vector2, pos2: Vector2, board: Dictionary) -> float:

	var terrain_features = board.get("terrain_features", [])
	if terrain_features.is_empty():
		# Fall back to TerrainManager autoload
		var terrain_manager = _get_terrain_manager_node()
		if terrain_manager and terrain_manager.has_method("get_engagement_range_for_positions"):
			return terrain_manager.get_engagement_range_for_positions(pos1, pos2)
		return GameConstants.engagement_range_inches()

	# Check if any barricade terrain lies between the two positions
	for terrain in terrain_features:
		if terrain.get("type", "") != "barricade":
			continue

		var polygon = terrain.get("polygon", PackedVector2Array())
		if polygon.is_empty():
			continue

		# Check if the line between pos1 and pos2 crosses this barricade
		for i in range(polygon.size()):
			var edge_start = polygon[i]
			var edge_end = polygon[(i + 1) % polygon.size()]
			if Geometry2D.segment_intersects_segment(pos1, pos2, edge_start, edge_end) != null:
				print("[RulesEngine] T3-9: Barricade '%s' between models — engagement range is 2\"" % terrain.get("id", "unknown"))
				return GameConstants.barricade_engagement_range_inches()

	return GameConstants.engagement_range_inches()

## Helper to get TerrainManager node from static context.
static func _get_terrain_manager_node():
	var tree = Engine.get_main_loop()
	if tree and tree.has_method("get_root"):
		var root = tree.get_root()
		if root:
			return root.get_node_or_null("TerrainManager")
	return null

# Validate engagement range constraints for charge
static func _validate_engagement_range_constraints_rules(unit_id: String, per_model_paths: Dictionary, target_ids: Array, board: Dictionary) -> Dictionary:
	var errors = []
	var er_px = Measurement.inches_to_px(GameConstants.engagement_range_inches())
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

					# T3-9: Use barricade-aware engagement range (2" through barricades)
					var effective_er = _get_effective_engagement_range_rules(final_pos, target_pos, board)
					if Measurement.is_in_engagement_range_shape_aware(model_at_final, target_model, effective_er):
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

					# T3-9: Use barricade-aware engagement range for non-target check too
					var effective_er = _get_effective_engagement_range_rules(final_pos, enemy_pos, board)
					if Measurement.is_in_engagement_range_shape_aware(model_at_final, enemy_model, effective_er):
						var enemy_name = enemy_unit.get("meta", {}).get("name", enemy_unit_id)
						errors.append("Cannot end within engagement range of non-target unit: " + enemy_name)
						break

	return {"valid": errors.is_empty(), "errors": errors}

# T3-8: Validate each model ends closer to at least one charge target than it started.
# 10e core rule: Each model making a charge move must end that move closer to
# at least one of the charge target units.
static func _validate_charge_direction_constraint_rules(unit_id: String, per_model_paths: Dictionary, target_ids: Array, board: Dictionary) -> Dictionary:
	var errors = []
	var all_units = board.get("units", {})
	var unit = all_units.get(unit_id, {})
	if unit.is_empty():
		return {"valid": true, "errors": []}

	for model_id in per_model_paths:
		var path = per_model_paths[model_id]
		if not (path is Array and path.size() > 0):
			continue

		var model = _get_model_in_unit_rules(unit, model_id)
		if model.is_empty():
			continue

		var start_pos = _get_model_position_rules(model)
		if start_pos == null or start_pos == Vector2.ZERO:
			continue

		var final_pos = Vector2(path[-1][0], path[-1][1])

		# Check if model ends closer to at least one target model in any target unit
		var ends_closer_to_any_target = false

		for target_id in target_ids:
			var target_unit = all_units.get(target_id, {})
			if target_unit.is_empty():
				continue

			for target_model in target_unit.get("models", []):
				if not target_model.get("alive", true):
					continue

				var target_pos = _get_model_position_rules(target_model)
				if target_pos == null:
					continue

				var start_distance = start_pos.distance_to(target_pos)
				var final_distance = final_pos.distance_to(target_pos)

				if final_distance < start_distance:
					ends_closer_to_any_target = true
					break

			if ends_closer_to_any_target:
				break

		if not ends_closer_to_any_target:
			var err = "Model %s must end its charge move closer to at least one charge target" % model_id
			errors.append(err)
			print("RulesEngine: Direction constraint - %s" % err)

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

	# Check that each model is within 2" horizontally AND 5" vertically of at least one other model
	for i in range(final_models.size()):
		var has_nearby_model = false

		for j in range(final_models.size()):
			if i == j:
				continue

			if Measurement.is_within_coherency(final_models[i], final_models[j]):
				has_nearby_model = true
				break

		if not has_nearby_model:
			errors.append("Unit coherency broken: model %d too far from other models" % i)

	return {"valid": errors.is_empty(), "errors": errors}

# Validate base-to-base if possible for charge
# Per 10e core rules: if a charging model CAN make base-to-base contact
# with an enemy model while satisfying all other constraints, it MUST.
static func _validate_base_to_base_possible_rules(unit_id: String, per_model_paths: Dictionary, target_ids: Array, board: Dictionary, rolled_distance: int = 0) -> Dictionary:
	var errors = []
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	var unit_owner = unit.get("owner", 0)

	const B2B_THRESHOLD_INCHES = 0.1

	if unit.is_empty():
		return {"valid": true, "errors": []}

	# Build final position model dicts for all charging models
	var final_models = {}  # model_id -> model dict at final position
	for model_id in per_model_paths:
		var path = per_model_paths[model_id]
		if path is Array and path.size() > 0:
			var model = _get_model_in_unit_rules(unit, model_id)
			if model.is_empty():
				continue
			var model_at_final = model.duplicate()
			model_at_final["position"] = Vector2(path[-1][0], path[-1][1])
			final_models[model_id] = model_at_final

	if final_models.is_empty():
		return {"valid": true, "errors": []}

	# Collect all alive enemy target models
	var target_models = []
	for target_id in target_ids:
		var target_unit = units.get(target_id, {})
		for target_model in target_unit.get("models", []):
			if target_model.get("alive", true):
				target_models.append({"model": target_model, "unit_id": target_id})

	if target_models.is_empty():
		return {"valid": true, "errors": []}

	# Check if ANY charging model already has B2B with any target model
	for model_id in final_models:
		var final_model = final_models[model_id]
		for target_entry in target_models:
			var distance = Measurement.model_to_model_distance_inches(final_model, target_entry.model)
			if distance <= B2B_THRESHOLD_INCHES:
				return {"valid": true, "errors": []}

	# No model achieved B2B. Check if any COULD have while satisfying all constraints.
	if rolled_distance <= 0:
		return {"valid": true, "errors": []}

	for model_id in final_models:
		var path = per_model_paths[model_id]
		if not (path is Array and path.size() > 0):
			continue

		var start_pos = Vector2(path[0][0], path[0][1])
		var model = _get_model_in_unit_rules(unit, model_id)
		if model.is_empty():
			continue

		var model_at_start = model.duplicate()
		model_at_start["position"] = start_pos

		for target_entry in target_models:
			var target_model = target_entry.model
			var target_pos = _get_model_position_rules(target_model)
			if target_pos == null or target_pos == Vector2.ZERO:
				continue

			# Edge-to-edge distance from start to target = gap the model must close
			var distance_to_b2b = Measurement.model_to_model_distance_inches(model_at_start, target_model)

			if distance_to_b2b > rolled_distance:
				continue

			# Compute B2B position: move model center toward target to close the gap
			var direction = (target_pos - start_pos)
			if direction.length() < 0.001:
				continue
			direction = direction.normalized()
			var move_px = Measurement.inches_to_px(distance_to_b2b)
			var b2b_pos = start_pos + direction * move_px

			var b2b_model = model.duplicate()
			b2b_model["position"] = b2b_pos

			# Constraint 1: Coherency
			var coherency_ok = true
			if final_models.size() > 1:
				var has_nearby = false
				for other_model_id in final_models:
					if other_model_id == model_id:
						continue
					var dist = Measurement.model_to_model_distance_inches(b2b_model, final_models[other_model_id])
					if dist <= 2.0 + Measurement.DISTANCE_TOLERANCE_INCHES:
						has_nearby = true
						break
				coherency_ok = has_nearby

			if not coherency_ok:
				continue

			# Constraint 2: No non-target ER violation
			var non_target_er_ok = true
			for enemy_unit_id in units:
				var enemy_unit = units[enemy_unit_id]
				if enemy_unit.get("owner", 0) == unit_owner:
					continue
				if enemy_unit_id in target_ids:
					continue

				for enemy_model in enemy_unit.get("models", []):
					if not enemy_model.get("alive", true):
						continue
					if Measurement.is_in_engagement_range_shape_aware(b2b_model, enemy_model, GameConstants.engagement_range_inches()):
						non_target_er_ok = false
						break

				if not non_target_er_ok:
					break

			if not non_target_er_ok:
				continue

			# Constraint 3: No model overlap
			var no_overlap = true
			for check_unit_id in units:
				var check_unit = units[check_unit_id]
				for check_model in check_unit.get("models", []):
					if not check_model.get("alive", true):
						continue
					var check_model_id = check_model.get("id", "")
					if check_unit_id == unit_id and check_model_id == model_id:
						continue

					var check_pos_model = check_model
					if check_unit_id == unit_id and final_models.has(check_model_id):
						check_pos_model = final_models[check_model_id]
					if Measurement.models_overlap(b2b_model, check_pos_model):
						no_overlap = false
						break
				if not no_overlap:
					break

			if not no_overlap:
				continue

			# Constraint 4: Unit still has ER with ALL declared targets
			var all_targets_covered = true
			for check_target_id in target_ids:
				var check_target_unit = units.get(check_target_id, {})
				if check_target_unit.is_empty():
					continue

				var target_covered = false
				for other_model_id in final_models:
					var check_charging_model = final_models[other_model_id]
					if other_model_id == model_id:
						check_charging_model = b2b_model

					for check_tm in check_target_unit.get("models", []):
						if not check_tm.get("alive", true):
							continue
						if Measurement.is_in_engagement_range_shape_aware(check_charging_model, check_tm, GameConstants.engagement_range_inches()):
							target_covered = true
							break

					if target_covered:
						break

				if not target_covered:
					all_targets_covered = false
					break

			if not all_targets_covered:
				continue

			# All constraints pass — B2B was achievable but not taken
			errors.append(
				"Base-to-base contact is achievable and must be made when possible (10e core rules)"
			)
			print("RulesEngine: B2B enforcement - %s" % errors[-1])
			return {"valid": false, "errors": errors}

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

# ==========================================
# FIGHT PHASE HELPERS — T4-4: Aircraft restrictions
# ==========================================

# T4-4: Check if a unit is eligible to fight in the fight phase.
# Aircraft can only fight if they have FLY opponents in engagement range.
static func is_eligible_to_fight(unit_id: String, board: Dictionary) -> bool:
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	if unit.is_empty():
		return false

	var unit_owner = unit.get("owner", 0)
	var unit_keywords = unit.get("meta", {}).get("keywords", [])
	var unit_is_aircraft = "AIRCRAFT" in unit_keywords

	# Check if any alive models
	var has_alive = false
	for model in unit.get("models", []):
		if model.get("alive", true):
			has_alive = true
			break
	if not has_alive:
		return false

	# Check engagement range with valid opponents
	for other_id in units:
		var other_unit = units.get(other_id, {})
		if other_unit.get("owner", 0) == unit_owner:
			continue

		var other_keywords = other_unit.get("meta", {}).get("keywords", [])
		# Aircraft can only fight FLY units
		if unit_is_aircraft and "FLY" not in other_keywords:
			continue
		# Non-FLY units ignore Aircraft
		if "AIRCRAFT" in other_keywords and "FLY" not in unit_keywords:
			continue

		# Check if any enemy models are alive
		var enemy_alive = false
		for em in other_unit.get("models", []):
			if em.get("alive", true):
				enemy_alive = true
				break
		if not enemy_alive:
			continue

		# Check engagement range
		if _are_units_in_engagement_range_rules(unit, other_unit, board):
			return true

	return false

# T4-4: Get eligible melee targets for a unit, respecting Aircraft restrictions.
# Aircraft can only target FLY units; non-FLY units cannot target Aircraft.
static func fight_targets_in_engagement(unit_id: String, board: Dictionary) -> Dictionary:
	var eligible = {}
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	if unit.is_empty():
		return eligible

	var unit_owner = unit.get("owner", 0)
	var unit_keywords = unit.get("meta", {}).get("keywords", [])
	var unit_is_aircraft = "AIRCRAFT" in unit_keywords
	var unit_has_fly = "FLY" in unit_keywords

	for target_id in units:
		var target_unit = units.get(target_id, {})
		if target_unit.get("owner", 0) == unit_owner:
			continue

		var target_keywords = target_unit.get("meta", {}).get("keywords", [])

		# T4-4: Aircraft can only fight against units that can Fly
		if unit_is_aircraft and "FLY" not in target_keywords:
			continue
		# T4-4: Non-FLY units cannot target Aircraft
		if "AIRCRAFT" in target_keywords and not unit_has_fly:
			continue

		# Check alive models
		var target_alive = false
		for tm in target_unit.get("models", []):
			if tm.get("alive", true):
				target_alive = true
				break
		if not target_alive:
			continue

		# Check engagement range
		if _are_units_in_engagement_range_rules(unit, target_unit, board):
			eligible[target_id] = {
				"name": target_unit.get("meta", {}).get("name", target_id),
			}

	return eligible

# T4-4: Check if an Aircraft unit can pile in (it cannot).
static func can_unit_pile_in(unit_id: String, board: Dictionary) -> bool:
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	if unit.is_empty():
		return false
	var keywords = unit.get("meta", {}).get("keywords", [])
	return "AIRCRAFT" not in keywords

# T4-4: Check if an Aircraft unit can consolidate (it cannot).
static func can_unit_consolidate(unit_id: String, board: Dictionary) -> bool:
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	if unit.is_empty():
		return false
	var keywords = unit.get("meta", {}).get("keywords", [])
	return "AIRCRAFT" not in keywords

# Helper: Check if two units are within engagement range (1") using model positions
static func _are_units_in_engagement_range_rules(unit1: Dictionary, unit2: Dictionary, board: Dictionary) -> bool:
	var models1 = unit1.get("models", [])
	var models2 = unit2.get("models", [])
	for m1 in models1:
		if not m1.get("alive", true):
			continue
		for m2 in models2:
			if not m2.get("alive", true):
				continue
			if Measurement.is_in_engagement_range_shape_aware(m1, m2):
				return true
	return false

# ===== MELEE COMBAT FUNCTIONS =====

# Per 10e rules: A model can make melee attacks if, after pile-in, it is:
# 1. Within Engagement Range (1") of any enemy model, OR
# 2. In base-to-base contact with a friendly model that is itself in
#    base-to-base contact with an enemy model.
# Returns an array of model indices (int) that are eligible to fight.
const BASE_CONTACT_TOLERANCE_INCHES: float = 0.25  # Generous tolerance for digital positioning

static func get_eligible_melee_model_indices(attacker_unit: Dictionary, board: Dictionary) -> Array:
	var eligible_indices = []
	var attacker_models = attacker_unit.get("models", [])
	var unit_owner = attacker_unit.get("owner", 0)
	var all_units = board.get("units", {})

	# First pass: find which models are within engagement range (1") of any enemy,
	# and separately track which are in base-to-base contact with an enemy.
	var models_in_er = []  # Model indices within 1" of an enemy (eligible via criterion 1)
	var models_in_base_contact_with_enemy = []  # Model indices in base contact with an enemy (for chain eligibility)

	for i in range(attacker_models.size()):
		var model = attacker_models[i]
		if not model.get("alive", true):
			continue

		var model_pos = _get_model_position(model)
		var in_er = false
		var in_base_contact = false
		for other_unit_id in all_units:
			var other_unit = all_units[other_unit_id]
			if str(other_unit.get("owner", 0)) == str(unit_owner):
				continue  # Skip friendly units

			for enemy_model in other_unit.get("models", []):
				if not enemy_model.get("alive", true):
					continue
				var distance = Measurement.model_to_model_distance_inches(model, enemy_model)
				if distance <= BASE_CONTACT_TOLERANCE_INCHES:
					in_base_contact = true
					in_er = true  # Base contact implies ER
					break
				else:
					# T3-9: Use barricade-aware engagement range (2" through barricades)
					var enemy_pos = _get_model_position(enemy_model)
					var effective_er = _get_effective_engagement_range_rules(model_pos, enemy_pos, board)
					if Measurement.is_in_engagement_range_shape_aware(model, enemy_model, effective_er):
						in_er = true
			if in_base_contact:
				break  # Found base contact (best result), stop checking other units
			# Don't break for in_er alone — keep checking other units for base contact

		if in_er:
			models_in_er.append(i)
			eligible_indices.append(i)
		if in_base_contact:
			models_in_base_contact_with_enemy.append(i)

	# Second pass: check models NOT in ER for base-to-base contact with a friendly
	# model that IS in base-to-base contact with an enemy (one level of chain per 10e rules).
	# Note: the chain requires base contact at BOTH links — the friendly model must be in
	# base contact with the enemy, not merely within engagement range.
	for i in range(attacker_models.size()):
		var model = attacker_models[i]
		if not model.get("alive", true):
			continue
		if i in eligible_indices:
			continue  # Already eligible from direct ER check

		for btb_index in models_in_base_contact_with_enemy:
			var btb_model = attacker_models[btb_index]
			var distance = Measurement.model_to_model_distance_inches(model, btb_model)
			if distance <= BASE_CONTACT_TOLERANCE_INCHES:
				eligible_indices.append(i)
				print("RulesEngine: Model %d eligible via base-contact chain (%.2f\" from model %d in base contact with enemy)" % [i, distance, btb_index])
				break

	print("RulesEngine: Per-model eligibility: %d/%d models eligible (ER: %d, base-contact with enemy: %d)" % [
		eligible_indices.size(), attacker_models.size(), models_in_er.size(), models_in_base_contact_with_enemy.size()])

	return eligible_indices

# Main melee combat resolution entry point
static func resolve_melee_attacks(action: Dictionary, board: Dictionary, rng_service: RNGService = null) -> Dictionary:
	if not rng_service:
		rng_service = make_rng()
	
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
		# Issue #391 ORKS IS NEVER BEATEN / DEFIANT TO THE LAST: capture target's
		# alive state BEFORE this assignment so we can identify models that died
		# (and need to swing back before being removed from play).
		var target_unit_id_pre: String = assignment.get("target", "")
		var swing_back_pre_alive: Array = []
		var swing_back_is_defiant: bool = false
		if not target_unit_id_pre.is_empty():
			var pre_target_unit = units.get(target_unit_id_pre, {})
			var pre_flags = pre_target_unit.get("flags", {})
			if pre_flags.get(EffectPrimitivesData.FLAG_SWING_BACK_BEFORE_REMOVE, false) \
					or pre_flags.get(EffectPrimitivesData.FLAG_DEFIANT_TO_THE_LAST, false):
				for m in pre_target_unit.get("models", []):
					swing_back_pre_alive.append(m.get("alive", true))
				swing_back_is_defiant = pre_flags.get(EffectPrimitivesData.FLAG_DEFIANT_TO_THE_LAST, false)

		var assignment_result = _resolve_melee_assignment(assignment, actor_unit_id, board, rng_service)
		result.diffs.append_array(assignment_result.diffs)
		result.dice.append_array(assignment_result.dice)
		if assignment_result.log_text:
			result.log_text += assignment_result.log_text + "\n"

		# Issue #391 ORKS IS NEVER BEATEN / DEFIANT TO THE LAST: now that the
		# original assignment has resolved (and may have killed models), trigger
		# the deferred swing-back attack from the dying-but-not-yet-removed models.
		if not swing_back_pre_alive.is_empty():
			var sb_diffs_dice = _resolve_swing_back_before_remove(target_unit_id_pre, actor_unit_id, swing_back_pre_alive, board, rng_service, swing_back_is_defiant)
			result.diffs.append_array(sb_diffs_dice.get("diffs", []))
			result.dice.append_array(sb_diffs_dice.get("dice", []))
			if sb_diffs_dice.get("log_text", "") != "":
				result.log_text += sb_diffs_dice["log_text"] + "\n"

		# HAZARDOUS (T2-3): After weapon resolves, check for Hazardous self-damage (melee)
		var weapon_id = assignment.get("weapon", "")
		if is_hazardous_weapon(weapon_id, board):
			var models_that_fought = assignment.get("models", []).size()
			var hazardous_result = resolve_hazardous_check(actor_unit_id, weapon_id, models_that_fought, board, rng_service)
			if hazardous_result.hazardous_triggered:
				result.diffs.append_array(hazardous_result.diffs)
			result.dice.append_array(hazardous_result.dice)
			if hazardous_result.log_text:
				result.log_text += hazardous_result.log_text + "\n"

	return result


# Issue #391 ORKS IS NEVER BEATEN: drive a swing-back attack from models that
# died this assignment. The dying models temporarily revive so the eligibility
# / engagement checks in `_resolve_melee_assignment` accept them, then we
# re-apply alive=false. Models that already fought this phase do NOT swing back
# (per Wahapedia: "if that model has not fought this phase").
static func _resolve_swing_back_before_remove(target_unit_id: String, original_attacker_id: String, pre_alive: Array, board: Dictionary, rng: RNGService, is_defiant: bool = false) -> Dictionary:
	var sb_result := {"diffs": [], "dice": [], "log_text": ""}
	var units = board.get("units", {})
	var defender = units.get(target_unit_id, {})
	if defender.is_empty():
		return sb_result
	var attacker = units.get(original_attacker_id, {})
	if attacker.is_empty():
		return sb_result

	# Find models that died this assignment AND haven't fought this phase.
	var dying_models: Array = []
	var defender_models: Array = defender.get("models", [])
	for idx in range(defender_models.size()):
		if idx >= pre_alive.size():
			break
		var was_alive: bool = bool(pre_alive[idx])
		var is_alive_now: bool = bool(defender_models[idx].get("alive", true))
		if was_alive and not is_alive_now:
			var model_flags = defender_models[idx].get("flags", {})
			if model_flags.get("fought_this_phase", false):
				continue
			if is_defiant:
				# DEFIANT TO THE LAST: roll D6, +2 if CHARACTER, need 4+
				var roll = rng.randi_range(1, 6)
				var model_keywords = defender_models[idx].get("keywords", [])
				if model_keywords.is_empty():
					model_keywords = defender.get("meta", {}).get("keywords", [])
				var is_character = false
				for kw in model_keywords:
					if kw.to_upper() == "CHARACTER":
						is_character = true
						break
				var modifier = 2 if is_character else 0
				var total = roll + modifier
				sb_result.dice.append({"type": "defiant_to_the_last", "roll": roll, "modifier": modifier, "total": total, "passed": total >= 4})
				if total >= 4:
					dying_models.append(idx)
					print("RulesEngine: DEFIANT TO THE LAST — model %d rolled %d+%d=%d (4+ needed), PASSES — will swing back" % [idx, roll, modifier, total])
				else:
					print("RulesEngine: DEFIANT TO THE LAST — model %d rolled %d+%d=%d (4+ needed), FAILS — removed normally" % [idx, roll, modifier, total])
			else:
				dying_models.append(idx)

	if dying_models.is_empty():
		return sb_result

	# Find the defender's first melee weapon to swing back with.
	var melee_weapon_name: String = ""
	for w in defender.get("meta", {}).get("weapons", []):
		if str(w.get("type", "")).to_lower() == "melee" or str(w.get("range", "")).to_lower() == "melee":
			melee_weapon_name = w.get("name", "")
			break
	if melee_weapon_name.is_empty():
		var strat_label = "DEFIANT TO THE LAST" if is_defiant else "ORKS IS NEVER BEATEN"
		print("RulesEngine: %s — %s has no melee weapon, cannot swing back" % [strat_label, target_unit_id])
		return sb_result

	var strat_label = "DEFIANT TO THE LAST" if is_defiant else "ORKS IS NEVER BEATEN"
	print("RulesEngine: %s — %s swings back %d dying model(s) at %s with '%s'" % [strat_label, target_unit_id, dying_models.size(), original_attacker_id, melee_weapon_name])

	# Temporarily revive the dying models so the engagement/eligibility checks
	# in _resolve_melee_assignment accept them. Tag them with pending_swing_back
	# for downstream visibility. The original assignment-level alive=false diffs
	# are still in the parent result and will land after our swing-back diffs.
	for idx in dying_models:
		defender_models[idx]["alive"] = true

	var sb_assignment := {
		"attacker": target_unit_id,
		"target": original_attacker_id,
		"weapon": melee_weapon_name,
		"models": dying_models.map(func(i): return str(i))
	}
	var sb_assignment_result = _resolve_melee_assignment(sb_assignment, target_unit_id, board, rng)

	# Restore alive=false on the dying models (they're being removed after swing-back).
	for idx in dying_models:
		defender_models[idx]["alive"] = false
		# Mark that the model fought this phase so it doesn't trigger a second
		# swing-back if a chained mechanic re-checks.
		if not defender_models[idx].has("flags"):
			defender_models[idx]["flags"] = {}
		defender_models[idx]["flags"]["fought_this_phase"] = true

	sb_result.diffs.append_array(sb_assignment_result.diffs)
	sb_result.dice.append_array(sb_assignment_result.dice)
	if sb_assignment_result.log_text:
		sb_result.log_text = sb_assignment_result.log_text
	return sb_result

# P0-58: Resolve melee attacks but stop before saves for interactive wound allocation.
# Returns hit/wound dice blocks and save preparation data for WoundAllocationOverlay.
static func resolve_melee_attacks_interactive(action: Dictionary, board: Dictionary, rng_service: RNGService = null) -> Dictionary:
	"""Resolve melee hit and wound rolls only, returning save data for interactive allocation.
	Used when the defending player is human and should choose wound allocation."""
	if not rng_service:
		rng_service = make_rng()

	var result = {
		"success": true,
		"phase": "FIGHT",
		"diffs": [],
		"dice": [],
		"log_text": "",
		"save_data_list": [],  # Save data per assignment (for WoundAllocationOverlay)
		"has_wounds": false
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

	# Process each attack assignment with stop_before_saves=true
	for assignment in assignments:
		var assignment_result = _resolve_melee_assignment(assignment, actor_unit_id, board, rng_service, true)
		result.dice.append_array(assignment_result.dice)
		if assignment_result.log_text:
			result.log_text += assignment_result.log_text + "\n"

		# If this assignment produced wounds, prepare save data for the overlay
		if assignment_result.get("stop_before_saves", false) and assignment_result.get("wounds_caused", 0) > 0:
			var target_id = assignment_result.get("target_id", "")
			var weapon_prof = assignment_result.get("weapon_profile", {})

			# Build devastating wounds data
			var dw_data = {
				"has_devastating_wounds": assignment_result.get("weapon_has_devastating_wounds", false),
				"critical_wounds": assignment_result.get("critical_wound_count", 0),
				"regular_wounds": assignment_result.get("regular_wound_count", 0)
			}

			# Build precision data
			var prec_data = {
				"has_precision": assignment_result.get("weapon_has_precision", false),
				"precision_wounds": assignment_result.get("critical_hits", 0) if assignment_result.get("weapon_has_precision", false) else 0,
				"critical_hits": assignment_result.get("critical_hits", 0)
			}

			var save_data = prepare_melee_save_resolution(
				assignment_result.get("wounds_caused", 0),
				target_id,
				assignment_result.get("attacker_id", actor_unit_id),
				weapon_prof,
				board,
				dw_data,
				prec_data
			)

			if save_data.get("success", false):
				# OA-19: Attach Hold Still mortal wound data to save_data
				var hs_mw = assignment_result.get("hold_still_mortal_wounds", 0)
				if hs_mw > 0:
					save_data["hold_still_mortal_wounds"] = hs_mw
					print("RulesEngine: P0-58 — Hold Still mortal wounds attached to save data: %d MW" % hs_mw)
				result.save_data_list.append(save_data)
				result.has_wounds = true
				print("RulesEngine: P0-58 — Prepared melee save data: %d wounds for %s from %s" % [
					assignment_result.get("wounds_caused", 0),
					save_data.get("target_unit_name", ""),
					save_data.get("weapon_name", "")
				])

		# HAZARDOUS (T2-3): After weapon resolves, check for Hazardous self-damage (melee)
		var weapon_id = assignment.get("weapon", "")
		if is_hazardous_weapon(weapon_id, board):
			var models_that_fought = assignment.get("models", []).size()
			var hazardous_result = resolve_hazardous_check(actor_unit_id, weapon_id, models_that_fought, board, rng_service)
			if hazardous_result.hazardous_triggered:
				result.diffs.append_array(hazardous_result.diffs)
			result.dice.append_array(hazardous_result.dice)
			if hazardous_result.log_text:
				result.log_text += hazardous_result.log_text + "\n"

	return result

# Resolve a single melee assignment (models with weapon -> target)
# Full pipeline mirroring shooting: hit rolls (with critical tracking, Sustained Hits),
# wound rolls (with Lethal Hits, Devastating Wounds), save rolls (with invulnerable saves),
# FNP, and damage application.
# P0-58: When stop_before_saves=true, stops after wound rolls and returns save prep data
# for interactive wound allocation overlay (defender-controlled wound allocation).
static func _resolve_melee_assignment(assignment: Dictionary, actor_unit_id: String, board: Dictionary, rng: RNGService, stop_before_saves: bool = false) -> Dictionary:
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
	# MA-11: Track per-model WS for each attack (supports stats_override.weapon_skill)
	var ws_per_attack = []
	var has_ws_override = false

	# BALANCE DATASLATE (P2-75): Extra Attacks weapons cannot have their attack count
	# modified by other rules, unless the rule explicitly names the weapon.
	var is_extra_attacks_weapon = has_extra_attacks(weapon_id, board)
	if is_extra_attacks_weapon:
		print("RulesEngine: Weapon '%s' has Extra Attacks — attack count cannot be modified by generic rules (Balance Dataslate)" % weapon_name)

	# WAAAGH! CHECK: Detect if Waaagh! is active for the attacker
	var waaagh_active = FactionAbilityManager.is_waaagh_active_for_unit(attacker_unit)
	# DA BIGGEST AND DA BEST: Check if attacker has this ability (Warboss — +4 attacks while Waaagh!)
	var has_da_biggest = false
	# DEAD BRUTAL: Check if attacker has this ability (Warboss in Mega Armour — damage=3 while Waaagh!)
	var has_dead_brutal = false
	if waaagh_active:
		var attacker_abilities = attacker_unit.get("meta", {}).get("abilities", [])
		for ab in attacker_abilities:
			var ab_name = ""
			if ab is String:
				ab_name = ab
			elif ab is Dictionary:
				ab_name = ab.get("name", "")
			if ab_name == "Da Biggest and da Best":
				has_da_biggest = true
			elif ab_name == "Dead Brutal":
				has_dead_brutal = true

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

		# MA-11: Get this model's effective WS (may differ from weapon profile)
		var model_ws = _get_model_effective_ws(model, attacker_unit, weapon_profile)
		if model_ws != weapon_profile.get("ws", 4):
			has_ws_override = true

		# Roll variable attacks for each model separately (per 10e rules)
		var attacks_result = roll_variable_characteristic(attacks_raw, rng)
		var model_attacks = attacks_result.value

		# MOMENT SHACKLE: Watcher's Axe gets 12 Attacks
		if attacker_unit.get("flags", {}).get("moment_shackle_attacks_12", false):
			if "Watcher" in weapon_name and "Axe" in weapon_name:
				model_attacks = 12
				print("RulesEngine: MOMENT SHACKLE — Watcher's Axe overridden to 12 Attacks")

		# WAAAGH! BONUS: +1 Attack to melee weapons
		# BALANCE DATASLATE (P2-75): Skip for Extra Attacks weapons — Waaagh! doesn't name specific weapons
		if waaagh_active and not is_extra_attacks_weapon:
			model_attacks += 1
		elif waaagh_active and is_extra_attacks_weapon:
			print("RulesEngine: Waaagh! +1 attack BLOCKED for Extra Attacks weapon '%s' (Balance Dataslate)" % weapon_name)

		# DA BIGGEST AND DA BEST: +4 Attacks to this model's melee weapons while Waaagh! active
		# BALANCE DATASLATE (P2-75): Skip for Extra Attacks weapons — ability doesn't name specific weapons
		if has_da_biggest and not is_extra_attacks_weapon:
			model_attacks += 4
			print("RulesEngine: Da Biggest and da Best — +4 attacks for model (Waaagh! active)")
		elif has_da_biggest and is_extra_attacks_weapon:
			print("RulesEngine: Da Biggest and da Best +4 attacks BLOCKED for Extra Attacks weapon '%s' (Balance Dataslate)" % weapon_name)

		total_attacks += model_attacks
		# MA-11: Record this model's WS for each of its attacks
		for _j in range(model_attacks):
			ws_per_attack.append(model_ws)
		if attacks_result.rolled:
			attacks_roll_log.append(attacks_result)

	if has_ws_override:
		print("RulesEngine: [MA-11] Per-model WS override active — models have different WS values")

	# MA-29: ABILITY ATTACK BONUS — Check for weapon-targeted +X Attacks from abilities (melee)
	if model_count > 0 and EffectPrimitivesData.has_effect_plus_attacks(attacker_unit):
		var melee_bonus_value = EffectPrimitivesData.get_effect_plus_attacks(attacker_unit)
		# Issue #393 AVENGE THE FALLEN: if a Below-Half-strength variant flag is
		# set AND the unit is currently Below Half-strength, override the default
		# bonus with the variant value.
		var below_half_bonus = int(attacker_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_PLUS_ATTACKS_BELOW_HALF, 0))
		if below_half_bonus > 0:
			var unit_id_for_below_half = attacker_unit.get("id", actor_unit_id)
			if GameState.is_below_half_strength_combined(unit_id_for_below_half):
				print("RulesEngine: AVENGE THE FALLEN — unit %s Below Half-strength, attacks bonus %d → %d (variant)" % [unit_id_for_below_half, melee_bonus_value, below_half_bonus])
				melee_bonus_value = below_half_bonus
		if EffectPrimitivesData.effect_applies_to_weapon(attacker_unit, EffectPrimitivesData.FLAG_PLUS_ATTACKS, weapon_name):
			if not is_extra_attacks_weapon:  # Balance Dataslate: skip for Extra Attacks weapons
				var melee_ability_bonus = melee_bonus_value * model_count
				total_attacks += melee_ability_bonus
				# Add WS entries for bonus attacks using default WS
				var melee_default_ws = weapon_profile.get("ws", 4)
				for _j in range(melee_ability_bonus):
					ws_per_attack.append(melee_default_ws)
				print("RulesEngine: [MA-29] Ability +%d Attacks for '%s' (melee) → +%d total (%d models × %d)" % [melee_bonus_value, weapon_name, melee_ability_bonus, model_count, melee_bonus_value])

	if model_count < total_alive_models:
		print("RulesEngine: Melee eligibility filter: %d/%d alive models eligible to fight" % [model_count, total_alive_models])

	if total_attacks == 0:
		result.log_text = "No valid attacking models (0/%d in engagement range)" % total_alive_models
		return result

	# ===== PHASE 2: GET COMBAT STATS =====
	# Use WS from weapon profile (10e: WS is on the weapon, not the unit)
	var ws = weapon_profile.get("ws", 4)
	var strength = weapon_profile.get("strength", 4)

	# WAAAGH! BONUS: +1 Strength to melee weapons
	if waaagh_active:
		strength += 1
		print("RulesEngine: Waaagh! active — melee strength %d → %d (+1)" % [strength - 1, strength])

	# BIONIK WORKSHOP (OA-2): +1 Strength to melee weapons
	var bionik_bonus = attacker_unit.get("flags", {}).get("bionik_workshop_bonus", "")
	if bionik_bonus == "strength":
		strength += 1
		print("RulesEngine: Bionik Workshop — melee strength %d → %d (+1)" % [strength - 1, strength])

	# FROM THE HALL OF ARMOURIES (#395 / Shield Host enhancement): +n Strength
	# to melee weapons. Canonical scope is bearer-only, but the flag is applied
	# unit-wide via EffectPrimitives — same approximation as Bionik Workshop.
	# Per-model gating would require threading per-attacker-model state through
	# the resolve loop; tracked as future refactor.
	var plus_s_melee = int(attacker_unit.get("flags", {}).get("effect_plus_strength_melee", 0))
	if plus_s_melee > 0:
		var pre_s_hoa = strength
		strength += plus_s_melee
		print("RulesEngine: Hall of Armouries — melee strength %d → %d (+%d)" % [pre_s_hoa, strength, plus_s_melee])

	var toughness = _get_attached_unit_toughness(target_unit, board)  # P2-90: Use bodyguard T for attached units
	# OA-44: DED GLOWY AMMO — -1T to enemy INFANTRY within 6" of Kaptin Badrukk (melee)
	var ded_glowy_penalty_melee = get_ded_glowy_ammo_toughness_penalty(target_unit, board)
	if ded_glowy_penalty_melee > 0:
		toughness = max(1, toughness - ded_glowy_penalty_melee)
		print("RulesEngine: DED GLOWY AMMO (melee) — INFANTRY target T reduced by %d to T%d" % [ded_glowy_penalty_melee, toughness])
	# OA-48: RUNTHERD — Runtherds revert to T4 when all Gretchin are dead
	var runtherd_t_override_melee = get_runtherd_toughness_override(target_unit)
	if runtherd_t_override_melee > 0:
		toughness = runtherd_t_override_melee
		print("RulesEngine: RUNTHERD (melee) — all Gretchin dead, Runtherd T overridden to T%d" % toughness)
	var ap = weapon_profile.get("ap", 0)
	# MARTIAL MASTERY — IMPROVE AP (P2-27): Shield Host detachment — improve AP by 1 on melee weapons
	# Applied before defender's worsen_ap (attacker improvement first, then defender reduction)
	var melee_attacker_flags = attacker_unit.get("flags", {})
	if melee_attacker_flags.get("martial_mastery_improve_ap", false):
		var pre_ap_mm = ap
		ap = ap + 1
		print("RulesEngine: Martial Mastery (Improve AP) — melee AP %d → %d" % [pre_ap_mm, ap])
	# WORSEN AP: Ramshackle etc. — reduce AP of incoming attacks (min 0)
	var melee_worsen_ap = EffectPrimitivesData.get_effect_worsen_ap(target_unit)
	if melee_worsen_ap > 0 and ap > 0:
		var pre_ap = ap
		ap = max(0, ap - melee_worsen_ap)
		print("RulesEngine: Worsen AP (melee) — AP %d → %d (worsen by %d)" % [pre_ap, ap, melee_worsen_ap])
	var damage = weapon_profile.get("damage", 1)

	# DEAD BRUTAL: While Waaagh! active, 'Uge choppa has Damage 3
	if has_dead_brutal and weapon_name.to_lower().contains("uge choppa"):
		var pre_damage = damage
		damage = 3
		print("RulesEngine: Dead Brutal — 'Uge choppa damage %d → %d (Waaagh! active)" % [pre_damage, damage])

	var base_save = target_unit.get("meta", {}).get("stats", {}).get("save", 7)

	# ===== PHASE 3: DETECT WEAPON ABILITIES =====
	var weapon_has_lethal_hits = has_lethal_hits(weapon_id, board)
	var sustained_data = get_sustained_hits_value(weapon_id, board)
	var weapon_has_devastating_wounds = has_devastating_wounds(weapon_id, board)
	# BEASTLY RAGE: Beastboss on Squigosaur — melee weapons gain DEVASTATING WOUNDS after charging
	if not weapon_has_devastating_wounds and has_beastly_rage_active(attacker_unit):
		weapon_has_devastating_wounds = true
		print("RulesEngine:   DEVASTATING WOUNDS granted by Beastly Rage (charged this turn)")
	var is_torrent = is_torrent_weapon(weapon_id, board) or assignment.get("torrent", false)
	# PRECISION: Check both weapon keyword and stratagem flag on attacker
	var weapon_has_precision = has_precision(weapon_id, board) or has_stratagem_precision_melee(attacker_unit)

	# MARTIAL KA'TAH / EFFECT FLAGS: Check unit-level effect flags for Lethal/Sustained Hits
	# These are set by faction abilities (e.g., Martial Ka'tah) or stratagems via EffectPrimitives
	if not weapon_has_lethal_hits and EffectPrimitivesData.has_effect_lethal_hits(attacker_unit):
		weapon_has_lethal_hits = true
		print("RulesEngine:   LETHAL HITS granted by unit effect flag (e.g., Martial Ka'tah Rendax stance)")
	if sustained_data.value == 0 and EffectPrimitivesData.has_effect_sustained_hits(attacker_unit):
		# Check for Ka'tah-specific sustained hits value, default to 1
		var katah_sh_value = attacker_unit.get("flags", {}).get("katah_sustained_hits_value", 1)
		sustained_data = {"value": katah_sh_value, "is_dice": false}
		print("RulesEngine:   SUSTAINED HITS %d granted by unit effect flag (e.g., Martial Ka'tah Dacatarai stance)" % katah_sh_value)

	# GET STUCK IN (P2-27): War Horde detachment — Sustained Hits 1 on all melee weapons for ORKS
	if sustained_data.value == 0 and FactionAbilityManager.unit_has_get_stuck_in(attacker_unit):
		sustained_data = {"value": 1, "is_dice": false}
		print("RulesEngine:   SUSTAINED HITS 1 granted by Get Stuck In (War Horde detachment)")

	# HERE BE LOOT (OA-1): Freebooter Krew — Sustained Hits 1 near loot objective (melee)
	if sustained_data.value == 0 and FactionAbilityManager.check_here_be_loot_sustained_hits(attacker_unit, target_unit, board):
		sustained_data = {"value": 1, "is_dice": false}
		print("RulesEngine:   SUSTAINED HITS 1 granted by Here Be Loot (Freebooter Krew detachment)")

	# GHAZGHKULL'S WAAAGH! BANNER (OA-45): Lethal Hits on melee attacks for ORKS within 12" of Makari during Waaagh!
	if not weapon_has_lethal_hits and unit_has_waaagh_banner_lethal_hits(attacker_unit, board):
		weapon_has_lethal_hits = true
		print("RulesEngine:   LETHAL HITS granted by Ghazghkull's Waaagh! Banner (ORKS within 12\" of Makari, Waaagh! active)")

	print("RulesEngine: Melee %s (%s) → %s: %d attacks (%d/%d models eligible), WS %d+, S%d, AP%d, D%d" % [
		attacker_name, weapon_name, target_name, total_attacks, model_count, total_alive_models, ws, strength, ap, damage
	])
	if weapon_has_lethal_hits:
		print("RulesEngine:   Weapon has LETHAL HITS")
	if sustained_data.value > 0:
		print("RulesEngine:   Weapon has SUSTAINED HITS %s" % (("D%d" % sustained_data.value) if sustained_data.is_dice else str(sustained_data.value)))
	if weapon_has_devastating_wounds:
		print("RulesEngine:   Weapon has DEVASTATING WOUNDS")
	if weapon_has_precision:
		var precision_source = "weapon" if has_precision(weapon_id, board) else "EPIC CHALLENGE stratagem"
		print("RulesEngine:   Weapon has PRECISION (source: %s)" % precision_source)
	var melee_anti_data = get_anti_keyword_data(weapon_id, board)
	if melee_anti_data.size() > 0:
		for anti in melee_anti_data:
			print("RulesEngine:   Weapon has ANTI-%s %d+" % [anti.keyword, anti.threshold])

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

		# MARTIAL MASTERY — CRIT ON 5+ (P2-27): Shield Host detachment
		var melee_crit_threshold = 6  # Default: only unmodified 6s are critical hits
		if melee_attacker_flags.get("martial_mastery_crit_5", false):
			melee_crit_threshold = 5
			print("RulesEngine: Martial Mastery (Crit on 5+) — melee critical hit threshold lowered to 5+")
		# Also check effect_crit_hit_on flag (from stratagems or other abilities)
		var effect_crit = EffectPrimitivesData.get_effect_crit_hit_on(attacker_unit)
		if effect_crit > 0 and effect_crit < melee_crit_threshold:
			melee_crit_threshold = effect_crit
			print("RulesEngine: Effect crit_hit_on %d+ active — melee critical hit threshold: %d+" % [effect_crit, effect_crit])

		# Build melee hit modifiers using the HitModifier system
		var melee_hit_modifiers = HitModifier.NONE

		# Get hit modifiers from assignment
		if assignment.has("modifiers") and assignment.modifiers.has("hit"):
			var hit_mods = assignment.modifiers.hit
			if hit_mods.get("reroll_ones", false):
				melee_hit_modifiers |= HitModifier.REROLL_ONES
			if hit_mods.get("reroll_failed", false):
				melee_hit_modifiers |= HitModifier.REROLL_FAILED

		# OATH OF MOMENT (Codex): Re-roll all hit rolls when ADEPTUS ASTARTES attacks oath target
		var melee_oath_reroll_hits = FactionAbilityManager.attacker_benefits_from_oath(attacker_unit, target_unit)
		if melee_oath_reroll_hits:
			melee_hit_modifiers |= HitModifier.REROLL_FAILED
			print("RulesEngine: OATH OF MOMENT (melee) — re-roll all failed hits against %s" % target_name)

		# EFFECT FLAGS: Check for ability/stratagem-granted hit modifiers on the attacker (melee)
		if EffectPrimitivesData.has_effect_plus_one_hit(attacker_unit):
			melee_hit_modifiers |= HitModifier.PLUS_ONE
			print("RulesEngine: Effect +1 to hit (melee) applied for %s" % attacker_id)
		if EffectPrimitivesData.has_effect_minus_one_hit(attacker_unit):
			melee_hit_modifiers |= HitModifier.MINUS_ONE
			print("RulesEngine: Effect -1 to hit (melee) applied for %s" % attacker_id)
		var melee_reroll_hits_scope = attacker_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_REROLL_HITS, "")
		if melee_reroll_hits_scope == "ones":
			melee_hit_modifiers |= HitModifier.REROLL_ONES
			print("RulesEngine: Effect re-roll 1s to hit (melee) applied for %s" % attacker_id)
		elif melee_reroll_hits_scope == "failed" or melee_reroll_hits_scope == "all":
			melee_hit_modifiers |= HitModifier.REROLL_FAILED
			print("RulesEngine: Effect re-roll hits (melee) applied for %s" % attacker_id)

		# DAMAGED PROFILE (P1-14): Check if attacker has Damaged profile active
		if is_damaged_profile_active(attacker_unit):
			melee_hit_modifiers |= HitModifier.MINUS_ONE
			print("RulesEngine: Damaged profile -1 to hit (melee) applied for %s" % attacker_id)

		# MEKANIAK (OA-34): +1 to Hit for vehicles buffed by Mek at end of Movement phase (melee)
		if UnitAbilityManager.has_mekaniak_buff(attacker_unit):
			melee_hit_modifiers |= HitModifier.PLUS_ONE
			print("RulesEngine: MEKANIAK (melee) — +1 to hit for %s (Mek-buffed vehicle)" % attacker_id)

		# MONSTER HUNTERS (OA-49): Re-roll Hit rolls when attacking MONSTER or VEHICLE (melee)
		if has_monster_hunters_vs_target(attacker_unit, target_unit):
			melee_hit_modifiers |= HitModifier.REROLL_FAILED
			print("RulesEngine: MONSTER HUNTERS (melee) — re-roll hit rolls for %s (target is MONSTER/VEHICLE)" % attacker_id)

		# BIG AN' STOMPY (OA-41): +1 to Hit for melee attacks while Waaagh! active (Gorkanaut)
		if UnitAbilityManager.has_big_an_stompy(attacker_unit):
			melee_hit_modifiers |= HitModifier.PLUS_ONE
			print("RulesEngine: BIG AN' STOMPY — +1 to hit (melee) for %s (Waaagh! active)" % attacker_id)

		# XENOS HUNTER: +1 to Hit vs non-IMPERIUM/CHAOS targets (melee)
		if has_xenos_hunter_vs_target(attacker_unit, target_unit):
			melee_hit_modifiers |= HitModifier.PLUS_ONE
			print("RulesEngine: XENOS HUNTER (melee) — +1 to hit for %s (target lacks IMPERIUM/CHAOS)" % attacker_id)

		# CAPTAIN-GENERAL: Ignore all numeric hit modifiers (melee)
		if has_captain_general(attacker_unit):
			melee_hit_modifiers = melee_hit_modifiers & ~(HitModifier.PLUS_ONE | HitModifier.MINUS_ONE)
			print("RulesEngine: CAPTAIN-GENERAL (melee) — ignoring all hit roll modifiers for %s" % attacker_id)

		var melee_hit_reroll_data = []
		# ISS-012: per-roll evaluation shared with the ranged paths
		# (AttackSequence.evaluate_hit_roll). melee_crit_threshold covers
		# Martial Mastery (5+); it is always <= 6, so the legacy redundant
		# `unmodified == 6` clause is subsumed by the crit check.
		for i in range(hit_rolls.size()):
			var roll = hit_rolls[i]
			# MA-11: Use per-model WS for this attack's threshold
			var attack_ws = ws_per_attack[i] if i < ws_per_attack.size() else ws
			var hit_eval = AttackSequence.evaluate_hit_roll(roll, attack_ws, melee_hit_modifiers, melee_crit_threshold, rng)
			if hit_eval.rerolled:
				melee_hit_reroll_data.append({
					"original": hit_eval.reroll_from,
					"rerolled_to": hit_eval.reroll_to
				})
			if hit_eval.is_hit:
				hits += 1
				if hit_eval.is_crit:
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
			"total_hits_for_wounds": total_hits_for_wounds,
			# PRECISION tracking
			"precision_weapon": weapon_has_precision
		})

	if hits == 0 and sustained_bonus_hits == 0:
		var melee_miss_log = "Melee: %s (%s) → %s: %d attacks, 0 hits" % [attacker_name, weapon_name, target_name, total_attacks]
		if not hit_rolls.is_empty():
			melee_miss_log += " [%s] vs %s+" % [", ".join(hit_rolls.map(func(r): return str(r))), str(ws)]
		result.log_text = melee_miss_log
		return result

	# ===== PHASE 5: WOUND ROLLS =====
	# With Lethal Hits, Sustained Hits, Devastating Wounds, and Anti-Keyword interactions
	var wound_threshold = _calculate_wound_threshold(strength, toughness)

	# ANTI-[KEYWORD] X+: Get critical wound threshold (6 normally, lower if Anti matches target)
	var melee_critical_wound_threshold = get_critical_wound_threshold(weapon_id, target_unit, board)
	var melee_anti_keyword_active = melee_critical_wound_threshold < 6

	# TWIN-LINKED: Check if weapon has Twin-linked (re-roll all failed wound rolls)
	var melee_weapon_has_twin_linked = has_twin_linked(weapon_id, board) or assignment.get("twin_linked", false)

	# WOUND MODIFIERS (T1-3): Build wound modifier flags for melee path
	var melee_wound_modifiers = WoundModifier.NONE
	if assignment.has("modifiers") and assignment.modifiers.has("wound"):
		var wound_mods = assignment.modifiers.wound
		if wound_mods.get("reroll_ones", false):
			melee_wound_modifiers |= WoundModifier.REROLL_ONES
		if wound_mods.get("reroll_failed", false):
			melee_wound_modifiers |= WoundModifier.REROLL_FAILED
		if wound_mods.get("plus_one", false):
			melee_wound_modifiers |= WoundModifier.PLUS_ONE
		if wound_mods.get("minus_one", false):
			melee_wound_modifiers |= WoundModifier.MINUS_ONE
	# Twin-linked handled via WoundModifier system for re-rolls
	if melee_weapon_has_twin_linked:
		melee_wound_modifiers |= WoundModifier.REROLL_FAILED

	# OATH OF MOMENT (Codex): +1 to wound when ADEPTUS ASTARTES attacks oath target
	if FactionAbilityManager.attacker_benefits_from_oath(attacker_unit, target_unit):
		melee_wound_modifiers |= WoundModifier.PLUS_ONE
		print("RulesEngine: OATH OF MOMENT (melee) — +1 to wound against %s" % target_name)

	# EFFECT FLAGS: Check for ability/stratagem-granted wound modifiers on the attacker (melee)
	if EffectPrimitivesData.has_effect_plus_one_wound(attacker_unit):
		melee_wound_modifiers |= WoundModifier.PLUS_ONE
		print("RulesEngine: Effect +1 to wound (melee) applied for %s" % attacker_id)
	if EffectPrimitivesData.has_effect_minus_one_wound(attacker_unit):
		melee_wound_modifiers |= WoundModifier.MINUS_ONE
		print("RulesEngine: Effect -1 to wound (melee) applied for %s" % attacker_id)
	var melee_reroll_wounds_scope = attacker_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_REROLL_WOUNDS, "")
	if melee_reroll_wounds_scope == "ones":
		melee_wound_modifiers |= WoundModifier.REROLL_ONES
		print("RulesEngine: Effect re-roll 1s to wound (melee) applied for %s" % attacker_id)
	elif melee_reroll_wounds_scope == "failed" or melee_reroll_wounds_scope == "all":
		melee_wound_modifiers |= WoundModifier.REROLL_FAILED
		print("RulesEngine: Effect re-roll wounds (melee) applied for %s" % attacker_id)

	# BASH AND GRAB (OA-3): Freebooter Krew — re-roll Wound rolls vs targets near loot objective
	if attacker_unit.get("flags", {}).get("effect_bash_and_grab", false):
		if FactionAbilityManager.check_bash_and_grab_reroll_wounds(attacker_unit, target_unit, board):
			melee_wound_modifiers |= WoundModifier.REROLL_FAILED
			print("RulesEngine: BASH AND GRAB (melee) — re-roll Wound rolls vs %s (near loot objective)" % target_name)
		else:
			print("RulesEngine: BASH AND GRAB active but target %s not within range of loot objective — no re-roll" % target_name)

	# LANCE (T4-1): +1 to wound if unit charged this turn (melee Lance weapons)
	if is_lance_weapon(weapon_id, board):
		var unit_charged = attacker_unit.get("flags", {}).get("charged_this_turn", false)
		if unit_charged:
			melee_wound_modifiers |= WoundModifier.PLUS_ONE
			print("RulesEngine: LANCE (melee) — +1 to wound (unit charged this turn)")

	# DA BOSS' LADZ (OA-15): -1 to incoming Wound rolls when S > T and Warboss leads target unit (melee)
	var melee_da_boss_ladz_mod = get_da_boss_ladz_wound_modifier(target_unit, board, strength, toughness)
	if melee_da_boss_ladz_mod != WoundModifier.NONE:
		melee_wound_modifiers |= melee_da_boss_ladz_mod
		print("RulesEngine: DA BOSS' LADZ (melee) — -1 to wound for attacks against %s (S %d > T %d, Warboss leading)" % [target_id, strength, toughness])

	# SLAYERS OF TYRANTS: Re-roll Wound rolls vs CHARACTER/MONSTER/VEHICLE (melee)
	if has_slayers_of_tyrants_vs_target(attacker_unit, target_unit):
		melee_wound_modifiers |= WoundModifier.REROLL_FAILED
		print("RulesEngine: SLAYERS OF TYRANTS (melee) — re-roll wound rolls for %s (target is CHARACTER/MONSTER/VEHICLE)" % attacker_id)

	# AGAINST ALL ODDS: +1 to Wound when no friendly units within 6" (melee, Lions of the Emperor)
	if FactionAbilityManager.check_against_all_odds(attacker_unit, board):
		melee_wound_modifiers |= WoundModifier.PLUS_ONE
		print("RulesEngine: AGAINST ALL ODDS (melee) — +1 to wound for %s (no friendlies within 6\")" % attacker_id)

	var melee_wound_modifier_net = 0
	if melee_wound_modifiers & WoundModifier.PLUS_ONE:
		melee_wound_modifier_net += 1
	if melee_wound_modifiers & WoundModifier.MINUS_ONE:
		melee_wound_modifier_net -= 1
	melee_wound_modifier_net = clamp(melee_wound_modifier_net, -1, 1)

	if melee_wound_modifier_net != 0:
		print("RulesEngine: Wound modifier net (melee) = %+d (capped at +1/-1)" % melee_wound_modifier_net)

	var auto_wounds = 0  # From Lethal Hits
	var wounds_from_rolls = 0
	var wound_rolls = []
	var critical_wound_count = 0  # Critical wounds: unmodified X+ (Anti) or 6s (default)
	var regular_wound_count = 0
	var all_critical_wound_count = 0  # OA-19: Track ALL critical wounds (for Hold Still and Say 'Aargh!')
	var melee_wound_reroll_data = []  # Track twin-linked / modifier re-rolls

	if weapon_has_lethal_hits and not is_torrent and lethal_hits_auto_wound_11e(weapon_id, board, assignment):
		# Lethal Hits: Critical hits (unmodified 6s to hit) automatically wound - no wound roll
		auto_wounds = critical_hits
		# Per 10e: Lethal Hits auto-wounds are NOT critical wounds for Devastating Wounds
		# Critical wounds for DW require unmodified 6 (or Anti threshold) on the WOUND roll

		# Roll wounds for: regular hits + sustained bonus hits (sustained bonus hits always roll)
		var hits_to_roll = regular_hits + sustained_bonus_hits
		if hits_to_roll > 0:
			wound_rolls = rng.roll_d6(hits_to_roll)
			for roll in wound_rolls:
				# ISS-012: shared per-roll evaluation (AttackSequence.evaluate_wound_roll)
				var wound_eval = AttackSequence.evaluate_wound_roll(roll, melee_wound_modifiers, wound_threshold, melee_critical_wound_threshold, rng)
				if wound_eval.rerolled:
					melee_wound_reroll_data.append({"original": wound_eval.reroll_from, "rerolled_to": wound_eval.reroll_to})
				if wound_eval.auto_fail:
					continue
				if wound_eval.is_wound:
					wounds_from_rolls += 1
					# OA-19: Track all critical wounds for Hold Still ability
					if wound_eval.is_crit:
						all_critical_wound_count += 1
					if weapon_has_devastating_wounds and wound_eval.is_crit:
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
				# ISS-012: shared per-roll evaluation (AttackSequence.evaluate_wound_roll)
				var wound_eval = AttackSequence.evaluate_wound_roll(roll, melee_wound_modifiers, wound_threshold, melee_critical_wound_threshold, rng)
				if wound_eval.rerolled:
					melee_wound_reroll_data.append({"original": wound_eval.reroll_from, "rerolled_to": wound_eval.reroll_to})
				if wound_eval.auto_fail:
					continue
				if wound_eval.is_wound:
					wounds_from_rolls += 1
					# OA-19: Track all critical wounds for Hold Still ability
					if wound_eval.is_crit:
						all_critical_wound_count += 1
					if weapon_has_devastating_wounds and wound_eval.is_crit:
						critical_wound_count += 1
					else:
						regular_wound_count += 1

	var wounds_caused = auto_wounds + wounds_from_rolls

	if melee_anti_keyword_active:
		print("RulesEngine: ANTI-KEYWORD active (melee) — critical wound threshold %d+ (normal wound threshold %d+)" % [melee_critical_wound_threshold, wound_threshold])

	if melee_weapon_has_twin_linked and not melee_wound_reroll_data.is_empty():
		print("RulesEngine: TWIN-LINKED (melee) — re-rolled %d failed wound rolls" % melee_wound_reroll_data.size())

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
		"regular_wounds": regular_wound_count,
		# ANTI-[KEYWORD] X+ tracking
		"anti_keyword_active": melee_anti_keyword_active,
		"critical_wound_threshold": melee_critical_wound_threshold,
		# TWIN-LINKED tracking
		"twin_linked_weapon": melee_weapon_has_twin_linked,
		"wound_rerolls": melee_wound_reroll_data,
		# WOUND MODIFIER tracking (T1-3)
		"wound_modifier_net": melee_wound_modifier_net,
		"wound_modifiers_applied": melee_wound_modifiers
	})

	if wounds_caused == 0:
		var hit_text = "%d hits" % hits
		if sustained_bonus_hits > 0:
			hit_text += " (+%d sustained)" % sustained_bonus_hits
		result.log_text = "Melee: %s (%s) → %s: %d attacks, %s, 0 wounds" % [attacker_name, weapon_name, target_name, total_attacks, hit_text]
		return result

	# P0-58: When stop_before_saves=true, return wound data for interactive save allocation
	if stop_before_saves:
		result["wounds_caused"] = wounds_caused
		result["critical_wound_count"] = critical_wound_count
		result["regular_wound_count"] = regular_wound_count
		result["weapon_has_devastating_wounds"] = weapon_has_devastating_wounds
		result["weapon_has_precision"] = weapon_has_precision
		result["critical_hits"] = critical_hits
		result["weapon_profile"] = weapon_profile
		result["target_id"] = target_id
		result["attacker_id"] = attacker_id
		result["target_name"] = target_name
		result["attacker_name"] = attacker_name
		result["weapon_name"] = weapon_name
		result["stop_before_saves"] = true
		# OA-19: Compute Hold Still mortal wound count for interactive path
		var hs_mw_count = 0
		if all_critical_wound_count > 0 and _has_hold_still_ability(attacker_unit):
			if weapon_name.to_lower().contains("urty syringe"):
				if not unit_has_keyword(target_unit, "VEHICLE"):
					for _hs_i in range(all_critical_wound_count):
						hs_mw_count += rng.roll_d6(1)[0]
					print("RulesEngine: HOLD STILL AND SAY 'AARGH!' (interactive) — %d critical wound(s), %d mortal wounds pending" % [all_critical_wound_count, hs_mw_count])
				else:
					print("RulesEngine: HOLD STILL AND SAY 'AARGH!' (interactive) — target %s is VEHICLE, excluded" % target_name)
		result["hold_still_mortal_wounds"] = hs_mw_count
		# Build log text for the hit/wound portion
		var hw_parts = []
		hw_parts.append("Melee: %s (%s) → %s" % [attacker_name, weapon_name, target_name])
		if is_torrent:
			hw_parts.append("Torrent: %d auto-hits" % hits)
		else:
			var hw_hit_detail = "Hit: %d/%d" % [hits, total_attacks]
			if critical_hits > 0:
				hw_hit_detail += " [%d crit]" % critical_hits
			hw_parts.append(hw_hit_detail)
		if sustained_bonus_hits > 0:
			hw_parts.append("+%d Sustained Hits" % sustained_bonus_hits)
		var hw_wound_detail = "Wound: %d/%d" % [wounds_caused, total_hits_for_wounds]
		if auto_wounds > 0:
			hw_wound_detail += " (%d Lethal)" % auto_wounds
		hw_parts.append(hw_wound_detail)
		hw_parts.append("Awaiting defender save allocation...")
		result.log_text = " - ".join(hw_parts)
		print("RulesEngine: P0-58 — Melee hits/wounds resolved, %d wounds caused, returning for interactive saves" % wounds_caused)
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

	# T4-18: Read save roll modifier from target unit flags (capped at +1/-1 per 10e)
	var melee_save_modifier = target_unit.get("flags", {}).get("save_modifier", 0)
	melee_save_modifier = clamp(melee_save_modifier, -1, 1)

	if wounds_needing_saves > 0:
		# Calculate save needed using proper invulnerable save logic
		# In melee, no cover applies (cover is for ranged attacks)
		# Get invulnerable save from first alive target model
		var target_models = target_unit.get("models", [])
		var invuln = 0
		# MA-12: Per-model save from stats_override (melee auto-resolve)
		var melee_auto_model_save = base_save
		for model in target_models:
			if model.get("alive", true):
				invuln = _get_model_effective_invuln(model, target_unit, model.get("invuln", 0))
				melee_auto_model_save = _get_model_effective_save(model, target_unit, base_save)
				if melee_auto_model_save != base_save:
					print("RulesEngine: MA-12 per-model save override (melee auto-resolve) — save %d+ (unit default %d+)" % [melee_auto_model_save, base_save])
				break
		# Also check unit-level invuln in meta stats
		if invuln == 0:
			invuln = target_unit.get("meta", {}).get("stats", {}).get("invuln", 0)
		# Check effect-granted invulnerable save (e.g., Waaagh! 5+, Go to Ground, abilities)
		var melee_effect_invuln = EffectPrimitivesData.get_effect_invuln(target_unit)
		if melee_effect_invuln > 0:
			if invuln == 0 or melee_effect_invuln < invuln:
				invuln = melee_effect_invuln
				print("RulesEngine: Effect-granted %d+ invulnerable save applied in melee" % melee_effect_invuln)

		var save_info = _calculate_save_needed(melee_auto_model_save, ap, false, invuln)  # No cover in melee
		save_threshold = save_info.inv if save_info.use_invuln else save_info.armour

		save_rolls = rng.roll_d6(wounds_needing_saves)
		for roll in save_rolls:
			# 10e rules: Unmodified save roll of 1 always fails
			if roll > 1 and (roll + melee_save_modifier) >= save_threshold:
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
		"save_modifier": melee_save_modifier,
		"original_save": base_save,
		"using_invuln": save_threshold != (base_save + ap) and save_threshold < 7,
		# Devastating Wounds tracking
		"devastating_wounds_bypassed": devastating_wound_count,
		"devastating_damage": devastating_damage
	})

	if total_unsaved == 0:
		var saved_log_parts = []
		saved_log_parts.append("Melee: %s (%s) → %s" % [attacker_name, weapon_name, target_name])
		# Hit details
		if is_torrent:
			saved_log_parts.append("Torrent: %d auto-hits" % hits)
		else:
			var saved_hit_detail = "Hit: %d/%d" % [hits, total_attacks]
			if not hit_rolls.is_empty():
				saved_hit_detail += " [%s] vs %s+" % [", ".join(hit_rolls.map(func(r): return str(r))), str(ws)]
			if critical_hits > 0:
				saved_hit_detail += " [%d crit]" % critical_hits
			saved_log_parts.append(saved_hit_detail)
		if sustained_bonus_hits > 0:
			saved_log_parts.append("+%d Sustained" % sustained_bonus_hits)
		# Wound details
		var saved_wound_detail = "Wound: %d/%d" % [wounds_caused, total_hits_for_wounds]
		if not wound_rolls.is_empty():
			saved_wound_detail += " [%s] vs %s+" % [", ".join(wound_rolls.map(func(r): return str(r))), str(wound_threshold)]
		if auto_wounds > 0:
			saved_wound_detail += " (%d Lethal)" % auto_wounds
		saved_log_parts.append(saved_wound_detail)
		saved_log_parts.append("all saved!")
		result.log_text = " - ".join(saved_log_parts)
		return result

	# ===== PHASE 7: DAMAGE APPLICATION =====
	# T2-11: Devastating Wounds mortal wound spillover — separate DW from regular damage
	# Per 10e rules: Devastating Wounds create mortal wounds that spill over between models.
	# Regular failed-save damage does NOT spill over (excess damage lost when model dies).
	var damage_raw = weapon_profile.get("damage_raw", str(weapon_profile.get("damage", 1)))
	# DEAD BRUTAL: Override damage_raw for variable damage rolling
	if has_dead_brutal and weapon_name.to_lower().contains("uge choppa"):
		damage_raw = "3"
	var damage_roll_log = []

	# HALF DAMAGE (T4-17): Check if target unit has half-damage defensive ability
	var melee_has_half_damage = get_unit_half_damage(target_unit)
	if melee_has_half_damage:
		print("RulesEngine: Half Damage active on melee defender — all damage characteristics halved (round up)")

	# DA BIGGER DEY IZ (OA-49): Mozrog Skragbad — conditional damage bonus vs MONSTER/VEHICLE/TITANIC
	var da_bigger_bonus = get_da_bigger_damage_bonus(attacker_unit, target_unit)
	if da_bigger_bonus > 0:
		print("RulesEngine: DA BIGGER DEY IZ — +%d damage for %s (target is %s)" % [da_bigger_bonus, attacker_name, "TITANIC" if da_bigger_bonus == 2 else "MONSTER/VEHICLE"])

	# Roll variable damage per regular failed save
	var melee_minus_dmg = EffectPrimitivesData.get_effect_minus_damage(target_unit)
	# Issue #374 Hall of Armouries: unit-level effect_plus_damage adds to damage
	# rolls for the bearer's melee weapons.
	var melee_plus_dmg = int(attacker_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_PLUS_DAMAGE, 0))
	var regular_wound_damages = []
	for _i in range(failed_saves):
		var dmg_result = roll_variable_characteristic(damage_raw, rng)
		var wound_dmg_value = dmg_result.value
		# DA BIGGER DEY IZ (OA-49): Add conditional damage bonus before defensive modifiers
		if da_bigger_bonus > 0:
			wound_dmg_value += da_bigger_bonus
		# Hall of Armouries: bearer melee +Damage
		if melee_plus_dmg > 0:
			var pre_plus_d = wound_dmg_value
			wound_dmg_value += melee_plus_dmg
			print("RulesEngine: Hall of Armouries (melee) — damage %d → %d (+%d)" % [pre_plus_d, wound_dmg_value, melee_plus_dmg])
		# HALF DAMAGE (T4-17): Halve per-wound damage (round up)
		if melee_has_half_damage:
			wound_dmg_value = apply_half_damage(wound_dmg_value)
		# MINUS DAMAGE (P1-18): Subtract damage reduction (e.g. Guardian Eternal -1 Damage), min 1
		if melee_minus_dmg > 0:
			var pre_minus = wound_dmg_value
			wound_dmg_value = max(1, wound_dmg_value - melee_minus_dmg)
			print("RulesEngine: Minus Damage (melee) — damage %d → %d (-%d)" % [pre_minus, wound_dmg_value, melee_minus_dmg])
		regular_wound_damages.append(wound_dmg_value)
		if dmg_result.rolled:
			damage_roll_log.append(dmg_result)
	var regular_damage = 0
	for d in regular_wound_damages:
		regular_damage += d

	# Roll variable damage per devastating wound (mortal wounds that spill over)
	devastating_damage = 0
	for _i in range(devastating_wound_count):
		var dmg_result = roll_variable_characteristic(damage_raw, rng)
		var dw_dmg_value = dmg_result.value
		# DA BIGGER DEY IZ (OA-49): Add conditional damage bonus before defensive modifiers
		if da_bigger_bonus > 0:
			dw_dmg_value += da_bigger_bonus
		# HALF DAMAGE (T4-17): Halve devastating wound damage (round up)
		if melee_has_half_damage:
			dw_dmg_value = apply_half_damage(dw_dmg_value)
		# MINUS DAMAGE (P1-18): Subtract damage reduction (e.g. Guardian Eternal -1 Damage), min 1
		if melee_minus_dmg > 0:
			var pre_minus = dw_dmg_value
			dw_dmg_value = max(1, dw_dmg_value - melee_minus_dmg)
			print("RulesEngine: Minus Damage (melee) — devastating wound damage %d → %d (-%d)" % [pre_minus, dw_dmg_value, melee_minus_dmg])
		devastating_damage += dw_dmg_value
		if dmg_result.rolled:
			damage_roll_log.append(dmg_result)

	var total_damage = regular_damage + devastating_damage

	# FEEL NO PAIN: Roll FNP separately for devastating wounds and regular damage.
	# T-016: DW deals mortal-wound damage, so the DW FNP roll consults the
	# `effect_fnp_psychic_mortal` flag (Daughters of the Abyss et al.).
	# Issue #388: regular damage from PSYCHIC weapons also triggers FNP-vs-psychic.
	var melee_is_psychic = is_psychic_weapon(weapon_id, board)
	var fnp_value = get_unit_fnp_for_attack(target_unit, melee_is_psychic)
	var dw_fnp_value = get_unit_fnp_for_attack(target_unit, true)
	var actual_dw_damage = devastating_damage
	var actual_regular_damage = regular_damage
	var total_fnp_prevented = 0

	if fnp_value > 0 or dw_fnp_value > 0:
		# T2-11: FNP for devastating wound mortal wounds
		if devastating_damage > 0 and dw_fnp_value > 0:
			var fnp_dw = roll_feel_no_pain(devastating_damage, dw_fnp_value, rng)
			actual_dw_damage = fnp_dw.wounds_remaining
			total_fnp_prevented += fnp_dw.wounds_prevented
			result.dice.append({
				"context": "feel_no_pain",
				"source": "devastating_wounds",
				"threshold": str(dw_fnp_value) + "+",
				"rolls_raw": fnp_dw.rolls,
				"fnp_value": dw_fnp_value,
				"wounds_prevented": fnp_dw.wounds_prevented,
				"wounds_remaining": fnp_dw.wounds_remaining,
				"total_wounds": devastating_damage
			})
			print("RulesEngine: Melee DW FNP %d+ — %d/%d mortal wound damage prevented" % [dw_fnp_value, fnp_dw.wounds_prevented, devastating_damage])

		# FNP for regular failed save damage
		if regular_damage > 0 and fnp_value > 0:
			var fnp_reg = roll_feel_no_pain(regular_damage, fnp_value, rng)
			actual_regular_damage = fnp_reg.wounds_remaining
			total_fnp_prevented += fnp_reg.wounds_prevented
			# Recalculate per-wound damages after FNP (distribute FNP prevention across wounds)
			regular_wound_damages = _distribute_fnp_across_wounds(regular_wound_damages, fnp_reg.wounds_prevented)
			result.dice.append({
				"context": "feel_no_pain",
				"source": "failed_saves",
				"threshold": str(fnp_value) + "+",
				"rolls_raw": fnp_reg.rolls,
				"fnp_value": fnp_value,
				"wounds_prevented": fnp_reg.wounds_prevented,
				"wounds_remaining": fnp_reg.wounds_remaining,
				"total_wounds": regular_damage
			})
			print("RulesEngine: Melee regular FNP %d+ — %d/%d damage prevented" % [fnp_value, fnp_reg.wounds_prevented, regular_damage])

		if total_fnp_prevented > 0:
			print("RulesEngine: Melee FNP total — %d/%d damage prevented" % [total_fnp_prevented, total_damage])

	var actual_damage = actual_dw_damage + actual_regular_damage

	if actual_damage == 0:
		var fnp_all_parts = ["Melee: %s (%s) → %s" % [attacker_name, weapon_name, target_name]]
		if not hit_rolls.is_empty():
			fnp_all_parts.append("Hit: %d/%d [%s] vs %s+" % [hits, total_attacks, ", ".join(hit_rolls.map(func(r): return str(r))), str(ws)])
		else:
			fnp_all_parts.append("Hit: %d/%d" % [hits, total_attacks])
		if not wound_rolls.is_empty():
			fnp_all_parts.append("Wound: %d/%d [%s] vs %s+" % [wounds_caused, total_hits_for_wounds, ", ".join(wound_rolls.map(func(r): return str(r))), str(wound_threshold)])
		else:
			fnp_all_parts.append("Wound: %d" % wounds_caused)
		fnp_all_parts.append("Save: %d failed" % total_unsaved)
		fnp_all_parts.append("FNP %d+ saved all damage!" % fnp_value)
		result.log_text = " - ".join(fnp_all_parts)
		return result

	# Apply damage to target unit
	# T2-11: Devastating wounds (mortal wounds) applied first with spillover,
	# then regular failed-save damage applied per-wound WITHOUT spillover
	var target_models = target_unit.get("models", [])
	var damage_result: Dictionary = {"diffs": [], "casualties": 0, "damage_applied": 0}
	var precision_wounds_allocated = 0

	# PRECISION: Wounds from critical hits can be allocated to CHARACTER models first
	if weapon_has_precision and critical_hits > 0:
		var character_indices = _find_character_model_indices(target_unit)
		# P3-100: Also check for attached CHARACTER leaders (separate units linked via attachment_data)
		var attached_char_info = _find_attached_character_info(target_unit, board)
		var has_any_characters = not character_indices.is_empty() or not attached_char_info.is_empty()

		if has_any_characters:
			# Calculate precision damage share: proportion of actual_damage from critical hit attacks
			# precision_unsaved = min(critical_hits, total_unsaved) — capped by both
			var precision_unsaved = mini(critical_hits, total_unsaved)
			# Proportional split of total damage (damage is already rolled and FNP'd)
			# Ensure at least 1 precision damage when critical hits exist and damage > 0
			var precision_damage = 0
			if total_unsaved > 0 and actual_damage > 0:
				precision_damage = maxi(1, int(round(float(actual_damage) * float(precision_unsaved) / float(total_unsaved))))
			precision_damage = mini(precision_damage, actual_damage)

			# Apply precision damage to CHARACTER models first
			if precision_damage > 0:
				if not character_indices.is_empty():
					# CHARACTER models are within the target unit itself
					var precision_result = _apply_damage_to_character_models(target_id, precision_damage, target_models, character_indices, board)
					result.diffs.append_array(precision_result.diffs)
					precision_wounds_allocated = precision_result.get("damage_applied", 0)
					print("RulesEngine: PRECISION — allocated %d damage to CHARACTER models (%d casualties)" % [precision_wounds_allocated, precision_result.casualties])
					damage_result["casualties"] += precision_result.get("casualties", 0)
					damage_result["damage_applied"] += precision_result.get("damage_applied", 0)
				elif not attached_char_info.is_empty():
					# P3-100: CHARACTER models are in attached leader units — Epic Challenge dueling
					var precision_result = _apply_damage_to_attached_characters(attached_char_info, precision_damage, board)
					result.diffs.append_array(precision_result.diffs)
					precision_wounds_allocated = precision_result.get("damage_applied", 0)
					print("RulesEngine: PRECISION (attached CHARACTER) — allocated %d damage to attached CHARACTER models (%d casualties)" % [precision_wounds_allocated, precision_result.casualties])
					damage_result["casualties"] += precision_result.get("casualties", 0)
					damage_result["damage_applied"] += precision_result.get("damage_applied", 0)

			# Remaining damage split: DW mortal wounds (spillover) + regular (no spillover)
			var remaining_after_precision = actual_damage - precision_damage
			# Proportional split of remaining between DW and regular
			var remaining_dw = 0
			var remaining_regular_wounds = []
			if remaining_after_precision > 0 and actual_damage > 0:
				remaining_dw = mini(actual_dw_damage, remaining_after_precision)
				var remaining_reg = remaining_after_precision - remaining_dw
				# Build per-wound damages for remaining regular wounds
				remaining_regular_wounds = _trim_wound_damages_to_total(regular_wound_damages, remaining_reg)

			# Apply devastating wound mortal wounds with spillover
			if remaining_dw > 0:
				var dw_result = _apply_damage_to_unit_pool(target_id, remaining_dw, target_models, board)
				result.diffs.append_array(dw_result.diffs)
				damage_result["casualties"] += dw_result.get("casualties", 0)
				damage_result["damage_applied"] += dw_result.get("damage_applied", 0)
				print("RulesEngine: T2-11 Melee DW mortal wounds — %d damage with spillover (%d casualties)" % [remaining_dw, dw_result.casualties])

			# Apply regular wounds per-wound without spillover
			if not remaining_regular_wounds.is_empty():
				var reg_result = _apply_damage_per_wound_no_spillover(target_id, remaining_regular_wounds, target_models, board)
				result.diffs.append_array(reg_result.diffs)
				damage_result["casualties"] += reg_result.get("casualties", 0)
				damage_result["damage_applied"] += reg_result.get("damage_applied", 0)
		else:
			# No CHARACTER models in target or attached — apply DW then regular separately
			if actual_dw_damage > 0:
				var dw_result = _apply_damage_to_unit_pool(target_id, actual_dw_damage, target_models, board)
				result.diffs.append_array(dw_result.diffs)
				damage_result["casualties"] += dw_result.get("casualties", 0)
				damage_result["damage_applied"] += dw_result.get("damage_applied", 0)
				print("RulesEngine: T2-11 Melee DW mortal wounds — %d damage with spillover (%d casualties)" % [actual_dw_damage, dw_result.casualties])
			if actual_regular_damage > 0:
				var reg_result = _apply_damage_per_wound_no_spillover(target_id, regular_wound_damages, target_models, board)
				result.diffs.append_array(reg_result.diffs)
				damage_result["casualties"] += reg_result.get("casualties", 0)
				damage_result["damage_applied"] += reg_result.get("damage_applied", 0)
	else:
		# No precision — T2-11: Apply devastating wounds (mortal wounds) with spillover first
		if actual_dw_damage > 0:
			var dw_result = _apply_damage_to_unit_pool(target_id, actual_dw_damage, target_models, board)
			result.diffs.append_array(dw_result.diffs)
			damage_result["casualties"] += dw_result.get("casualties", 0)
			damage_result["damage_applied"] += dw_result.get("damage_applied", 0)
			print("RulesEngine: T2-11 Melee DW mortal wounds — %d damage with spillover (%d casualties)" % [actual_dw_damage, dw_result.casualties])
		# Then apply regular failed-save damage per-wound WITHOUT spillover
		if actual_regular_damage > 0:
			var reg_result = _apply_damage_per_wound_no_spillover(target_id, regular_wound_damages, target_models, board)
			result.diffs.append_array(reg_result.diffs)
			damage_result["casualties"] += reg_result.get("casualties", 0)
			damage_result["damage_applied"] += reg_result.get("damage_applied", 0)

	# ===== OA-19: HOLD STILL AND SAY 'AARGH!' — MORTAL WOUNDS ON CRITICAL WOUND =====
	# After normal damage, apply D6 mortal wounds per critical wound with 'urty syringe
	# Excludes VEHICLE targets. Only triggers for 'urty syringe weapon.
	var hold_still_mortal_wounds = 0
	var hold_still_mw_casualties = 0
	if all_critical_wound_count > 0 and _has_hold_still_ability(attacker_unit):
		if weapon_name.to_lower().contains("urty syringe"):
			if not unit_has_keyword(target_unit, "VEHICLE"):
				for _crit_i in range(all_critical_wound_count):
					hold_still_mortal_wounds += rng.roll_d6(1)[0]
				print("RulesEngine: HOLD STILL AND SAY 'AARGH!' — %d critical wound(s) with '%s', %d mortal wounds vs %s" % [all_critical_wound_count, weapon_name, hold_still_mortal_wounds, target_name])
				if hold_still_mortal_wounds > 0:
					var hs_mw_result = apply_mortal_wounds(target_id, hold_still_mortal_wounds, board, rng)
					result.diffs.append_array(hs_mw_result.get("diffs", []))
					hold_still_mw_casualties = hs_mw_result.get("casualties", 0)
					damage_result["casualties"] += hold_still_mw_casualties
					print("RulesEngine: HOLD STILL — %d mortal wounds applied (%d casualties)" % [hold_still_mortal_wounds, hold_still_mw_casualties])
			else:
				print("RulesEngine: HOLD STILL AND SAY 'AARGH!' — target %s is VEHICLE, mortal wounds excluded" % target_name)

	# ===== BUILD LOG TEXT (verbose with dice rolls) =====
	var log_parts = []
	var eligibility_text = ""
	if model_count < total_alive_models:
		eligibility_text = " (%d/%d models)" % [model_count, total_alive_models]
	log_parts.append("Melee: %s (%s) → %s" % [attacker_name, weapon_name, target_name])

	# Verbose hit details
	if is_torrent:
		log_parts.append("Torrent: %d auto-hits" % hits)
	else:
		var final_hit_detail = "Hit: %d/%d%s" % [hits, total_attacks, eligibility_text]
		if not hit_rolls.is_empty():
			final_hit_detail += " [%s] vs %s+" % [", ".join(hit_rolls.map(func(r): return str(r))), str(ws)]
		if critical_hits > 0:
			final_hit_detail += " [%d crit]" % critical_hits
		log_parts.append(final_hit_detail)

	if sustained_bonus_hits > 0:
		log_parts.append("+%d Sustained Hits" % sustained_bonus_hits)

	# Verbose wound details
	var final_wound_detail = "Wound: %d/%d" % [wounds_caused, total_hits_for_wounds]
	if not wound_rolls.is_empty():
		final_wound_detail += " [%s] vs %s+" % [", ".join(wound_rolls.map(func(r): return str(r))), str(wound_threshold)]
	if auto_wounds > 0:
		final_wound_detail += " (%d Lethal)" % auto_wounds
	if melee_wound_modifier_net != 0:
		final_wound_detail += " (%+d modifier)" % melee_wound_modifier_net
	log_parts.append(final_wound_detail)

	if weapon_has_devastating_wounds and devastating_wound_count > 0:
		log_parts.append("%d DEVASTATING (unsaveable)" % devastating_wound_count)
	if weapon_has_precision and precision_wounds_allocated > 0:
		log_parts.append("PRECISION: %d damage → CHARACTER" % precision_wounds_allocated)

	# DA BIGGER DEY IZ: Log damage bonus in combat summary
	if da_bigger_bonus > 0:
		log_parts.append("DA BIGGER DEY IZ +%d dmg" % da_bigger_bonus)

	# Save result
	log_parts.append("Save: %d/%d failed" % [total_unsaved, wounds_caused])

	log_parts.append("%d slain" % damage_result.casualties)

	if fnp_value > 0:
		var prevented = total_damage - actual_damage
		if prevented > 0:
			log_parts.append("FNP %d+ prevented %d" % [fnp_value, prevented])

	# OA-19: Add Hold Still mortal wound info to log
	if hold_still_mortal_wounds > 0:
		log_parts.append("HOLD STILL: %d MW (%d slain)" % [hold_still_mortal_wounds, hold_still_mw_casualties])

	result.log_text = " - ".join(log_parts)

	return result

# Get fight priority for unit
static func get_fight_priority(unit: Dictionary) -> int:
	var flags = unit.get("flags", {})

	# Determine Fights First status
	# Charged units get Fights First — but Heroic Intervention units do NOT
	var has_fights_first = false
	if flags.get("charged_this_turn", false) and not flags.get("heroic_intervention", false):
		has_fights_first = true

	# Check for Fights First ability
	if not has_fights_first:
		var abilities = unit.get("meta", {}).get("abilities", [])
		for ability in abilities:
			if "fights_first" in str(ability).to_lower():
				has_fights_first = true
				break

	# Determine Fights Last status
	var has_fights_last = unit.get("status_effects", {}).get("fights_last", false)

	# Per 10e Rules Commentary: If a unit has both Fights First and Fights Last,
	# they cancel out and the unit fights in the Remaining Combats step (NORMAL).
	if has_fights_first and has_fights_last:
		return 1  # NORMAL (cancellation)

	if has_fights_first:
		return 0  # FIGHTS_FIRST

	if has_fights_last:
		return 2  # FIGHTS_LAST

	return 1  # NORMAL

# Check if two model dicts are in engagement range (shape-aware)
static func is_in_engagement_range(model1_pos: Vector2, model2_pos: Vector2, base1_mm: float = 25.0, base2_mm: float = 25.0) -> bool:
	# Legacy position-based check - create temporary model dicts for shape-aware calculation
	var model1 = {"position": model1_pos, "base_mm": base1_mm}
	var model2 = {"position": model2_pos, "base_mm": base2_mm}
	return Measurement.is_in_engagement_range_shape_aware(model1, model2)

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
			if Measurement.is_in_engagement_range_shape_aware(model1, model2):
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
	var weapons_data = unit.get("meta", {}).get("weapons", [])
	var model_profiles = unit.get("meta", {}).get("model_profiles", {})

	# Collect all melee weapon names as fallback (for units without model_profiles)
	var all_melee_weapons = []
	for weapon in weapons_data:
		if weapon.get("type", "").to_lower() == "melee":
			var wname = weapon.get("name", "Unknown Weapon")
			if wname not in all_melee_weapons:
				all_melee_weapons.append(wname)

	for model_index in range(models.size()):
		var model = models[model_index]
		if not model.get("alive", true):
			continue

		var model_id = "m" + str(model_index)
		var model_weapons = []

		# Per-model profile branch: if model_profiles exist and model has a model_type,
		# only assign melee weapons listed in that model's profile
		var model_type = model.get("model_type", "")
		if not model_profiles.is_empty() and model_type != "" and model_profiles.has(model_type):
			var profile = model_profiles[model_type]
			var profile_weapon_names = profile.get("weapons", [])
			for weapon in weapons_data:
				if weapon.get("type", "").to_lower() == "melee" and weapon.get("name", "") in profile_weapon_names:
					var wname = weapon.get("name", "Unknown Weapon")
					if wname not in model_weapons:
						model_weapons.append(wname)
		else:
			# Fallback: no model_profiles or no model_type — assign all melee weapons
			model_weapons = all_melee_weapons.duplicate()

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
			# MA-22: Log model destruction with model type label
			var simple_label = get_model_display_label(model, unit)
			print("RulesEngine: 💀 %s destroyed" % simple_label)
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
	devastating_wounds_data: Dictionary = {},
	melta_data: Dictionary = {},
	precision_data: Dictionary = {}
) -> Dictionary:
	"""
	Prepares all data needed for interactive save resolution.
	Returns save requirements without auto-resolving.
	DEVASTATING WOUNDS: Includes devastating_wounds count for unsaveable damage.
	MELTA X (T1-1): Includes melta bonus data for damage increase at half range.
	PRECISION (T3-4): Includes precision data for CHARACTER model targeting.
	"""
	var units = board.get("units", {})
	var target_unit = units.get(target_unit_id, {})

	if target_unit.is_empty():
		return {"success": false, "error": "Target unit not found"}

	var ap = weapon_profile.get("ap", 0)
	# PULSA ROKKIT (OA-31): +1 AP to ranged weapons for the phase
	var shooter_unit = units.get(shooter_unit_id, {})
	if shooter_unit.get("flags", {}).get("effect_pulsa_rokkit_active", false):
		var pre_ap_pr = ap
		ap = ap + 1
		print("RulesEngine: Pulsa Rokkit (interactive) — ranged AP %d → %d (+1)" % [pre_ap_pr, ap])
	# DRIVE-BY DAKKA (OA-13): Improve AP by 1 for ranged attacks vs targets within 9"
	var int_dbd_bonus = get_drive_by_dakka_ap_bonus(shooter_unit, target_unit)
	if int_dbd_bonus > 0:
		var pre_ap_dbd = ap
		ap = ap + int_dbd_bonus
		print("RulesEngine: Drive-by Dakka (interactive) — AP %d → %d (improve by %d, target within 9\")" % [pre_ap_dbd, ap, int_dbd_bonus])
	# WORSEN AP: Ramshackle etc. — reduce AP of incoming attacks (min 0)
	var int_worsen_ap = EffectPrimitivesData.get_effect_worsen_ap(target_unit)
	if int_worsen_ap > 0 and ap > 0:
		var pre_ap = ap
		ap = max(0, ap - int_worsen_ap)
		print("RulesEngine: Worsen AP (interactive) — AP %d → %d (worsen by %d)" % [pre_ap, ap, int_worsen_ap])
	var damage = weapon_profile.get("damage", 1)
	var base_save = target_unit.get("meta", {}).get("stats", {}).get("save", 7)

	var damage_raw = weapon_profile.get("damage_raw", str(damage))

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

	# INDIRECT FIRE (T2-4): Check if weapon has Indirect Fire for automatic cover
	var weapon_is_indirect_fire = false
	if not weapon_ignores_cover:
		var if_keywords = weapon_profile.get("keywords", [])
		for if_kw in if_keywords:
			if if_kw.to_upper() == "INDIRECT FIRE":
				weapon_is_indirect_fire = true
				break
		if not weapon_is_indirect_fire:
			var if_special = weapon_profile.get("special_rules", "").to_lower()
			if "indirect fire" in if_special:
				weapon_is_indirect_fire = true

	# Get model allocation requirements (prioritize wounded models)
	var allocation_info = _get_save_allocation_requirements(target_unit, shooter_unit_id, board)

	# EFFECT-GRANTED MODIFIERS: Check for cover and invuln from stratagems/abilities
	var effect_cover = EffectPrimitivesData.has_effect_cover(target_unit)
	var effect_invuln = EffectPrimitivesData.get_effect_invuln(target_unit)
	var effect_invuln_source = EffectPrimitivesData.get_effect_invuln_source(target_unit)

	if effect_cover:
		print("RulesEngine: Target has effect-granted Benefit of Cover")
	if effect_invuln > 0:
		print("RulesEngine: Target has effect-granted %d+ invulnerable save (source: %s)" % [effect_invuln, effect_invuln_source])

	# Calculate save profile for each model
	var model_save_profiles = []
	for model_info in allocation_info.models:
		var model = model_info.model
		# Cover: from terrain OR from stratagem (unless weapon ignores cover)
		# INDIRECT FIRE (T2-4): Target gains Benefit of Cover from Indirect Fire ONLY
		# when target is not visible to firing unit (Issue #371 — 10e RAW gate).
		var has_cover = false
		if not weapon_ignores_cover:
			if weapon_is_indirect_fire and not _has_los_to_target_unit(shooter_unit_id, target_unit_id, board):
				has_cover = true
				print("RulesEngine: [INDIRECT FIRE] Target gains Benefit of Cover (target not visible)")
			else:
				has_cover = _check_model_has_cover(model, shooter_unit_id, board) or effect_cover

		# MA-12: Per-model save from stats_override (e.g., Mega Armour save 2+ vs regular save 5+)
		var model_base_save = _get_model_effective_save(model, target_unit, base_save)
		if model_base_save != base_save:
			print("RulesEngine: MA-12 per-model save override — model %s save %d+ (unit default %d+)" % [model_info.model_id, model_base_save, base_save])

		# Invulnerable save: use best of model's native invuln, stats_override invuln, and effect-granted invuln
		# MA-12: Check stats_override.invuln for per-model invuln override
		var model_invuln = _get_model_effective_invuln(model, target_unit, model.get("invuln", 0))
		var invuln_source = "Native" if model_invuln > 0 else ""
		if model_invuln != model.get("invuln", 0) and model_invuln > 0:
			invuln_source = "Wargear"
			print("RulesEngine: MA-12 per-model invuln override — model %s invuln %d+ (model default %d+)" % [model_info.model_id, model_invuln, model.get("invuln", 0)])
		if effect_invuln > 0:
			if model_invuln == 0 or effect_invuln < model_invuln:
				model_invuln = effect_invuln
				invuln_source = effect_invuln_source if effect_invuln_source != "" else "Ability"

		var save_result = _calculate_save_needed(model_base_save, ap, has_cover, model_invuln, target_unit)

		model_save_profiles.append({
			"model_id": model_info.model_id,
			"model_index": model_info.model_index,
			"is_wounded": model_info.is_wounded,
			"is_character": model_info.get("is_character", false),  # PRECISION (T3-4): Track character models
			"current_wounds": model.get("current_wounds", model.get("wounds", 1)),
			"max_wounds": model.get("wounds", 1),
			"has_cover": has_cover,
			"save_needed": save_result.inv if save_result.use_invuln else save_result.armour,
			"using_invuln": save_result.use_invuln,
			"invuln_value": save_result.inv,
			"invuln_source": invuln_source,
			"armour_value": save_result.armour,
			"model_type": model.get("model_type", "")  # MA-21: Model type for wound allocation UI display
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

	# MELTA X (T1-1): Extract melta bonus data
	var melta_bonus = melta_data.get("melta_value", 0)
	var melta_models_in_half_range = melta_data.get("models_in_half_range", 0)
	var melta_total_models = melta_data.get("total_models", 0)

	return {
		"success": true,
		"wounds_to_save": wounds_needing_saves,  # Only non-critical wounds need saves
		"total_wounds": wounds_caused,  # Total wounds caused (for logging)
		"target_unit_id": target_unit_id,
		"target_unit_name": target_unit.get("meta", {}).get("display_name", target_unit.get("meta", {}).get("name", target_unit_id)),
		"shooter_unit_id": shooter_unit_id,
		"weapon_name": weapon_profile.get("name", "Unknown Weapon"),
		# Issue #388: stash psychic flag so apply_save_damage can gate FNP-vs-psychic
		"is_psychic": _profile_is_psychic(weapon_profile),
		"ap": ap,
		"damage": damage,
		"damage_raw": damage_raw,  # Raw string for variable damage rolling (D3, D6, etc.)
		"base_save": base_save,
		"model_save_profiles": model_save_profiles,
		"allocation_priority": allocation_info.priority_model_ids,
		# DEVASTATING WOUNDS (PRP-012): Unsaveable damage info
		"has_devastating_wounds": has_devastating_wounds,
		"devastating_wounds": devastating_wound_count,
		"devastating_damage": devastating_damage,  # Fixed estimate; actual DW damage rolled at application time
		# IGNORES COVER: Flag for UI display
		"ignores_cover": weapon_ignores_cover,
		# INDIRECT FIRE (T2-4): Flag for UI display
		"indirect_fire": weapon_is_indirect_fire,
		# MELTA X (T1-1): Bonus damage at half range
		"melta_bonus": melta_bonus,
		"melta_models_in_half_range": melta_models_in_half_range,
		"melta_total_models": melta_total_models,
		# PRECISION (T3-4): Character targeting data
		"has_precision": precision_data.get("has_precision", false),
		"precision_wounds": precision_data.get("precision_wounds", 0),
		"precision_critical_hits": precision_data.get("critical_hits", 0),
		# Character model IDs for precision targeting
		"character_model_ids": allocation_info.character_model_ids,
		"bodyguard_alive": allocation_info.bodyguard_alive
	}

# P0-58: Prepare melee save resolution data for interactive wound allocation overlay.
# Similar to prepare_save_resolution() but for melee context (no cover, no indirect fire, no melta).
static func prepare_melee_save_resolution(
	wounds_caused: int,
	target_unit_id: String,
	attacker_unit_id: String,
	weapon_profile: Dictionary,
	board: Dictionary,
	devastating_wounds_data: Dictionary = {},
	precision_data: Dictionary = {}
) -> Dictionary:
	"""
	Prepares save resolution data for melee wounds so the defending player
	can interactively allocate wounds via WoundAllocationOverlay.
	Returns the same format as prepare_save_resolution().
	"""
	var units = board.get("units", {})
	var target_unit = units.get(target_unit_id, {})

	if target_unit.is_empty():
		return {"success": false, "error": "Target unit not found"}

	var ap = weapon_profile.get("ap", 0)
	# WORSEN AP: Ramshackle etc. — reduce AP of incoming attacks (min 0)
	var worsen_ap = EffectPrimitivesData.get_effect_worsen_ap(target_unit)
	if worsen_ap > 0 and ap > 0:
		var pre_ap = ap
		ap = max(0, ap - worsen_ap)
		print("RulesEngine: Worsen AP (melee interactive) — AP %d → %d (worsen by %d)" % [pre_ap, ap, worsen_ap])

	# MARTIAL MASTERY — IMPROVE AP (P2-27): Shield Host detachment
	var attacker_unit = units.get(attacker_unit_id, {})
	var attacker_flags = attacker_unit.get("flags", {})
	if attacker_flags.get("martial_mastery_improve_ap", false):
		var pre_ap_mm = ap
		ap = ap + 1
		print("RulesEngine: Martial Mastery (Improve AP) — melee interactive AP %d → %d" % [pre_ap_mm, ap])

	var damage = weapon_profile.get("damage", 1)

	# DEAD BRUTAL: Override damage while Waaagh! active
	var waaagh_active = FactionAbilityManager.is_waaagh_active_for_unit(attacker_unit)
	if waaagh_active:
		var attacker_abilities = attacker_unit.get("meta", {}).get("abilities", [])
		for ab in attacker_abilities:
			var ab_name = ""
			if ab is String:
				ab_name = ab
			elif ab is Dictionary:
				ab_name = ab.get("name", "")
			if ab_name == "Dead Brutal" and weapon_profile.get("name", "").to_lower().contains("uge choppa"):
				damage = 3
				print("RulesEngine: Dead Brutal — melee interactive 'Uge choppa damage = 3")

	var base_save = target_unit.get("meta", {}).get("stats", {}).get("save", 7)
	var damage_raw = weapon_profile.get("damage_raw", str(damage))

	# Get model allocation requirements (prioritize wounded models)
	var allocation_info = _get_save_allocation_requirements(target_unit, attacker_unit_id, board)

	# Effect-granted invuln (e.g., Waaagh! 5+)
	var effect_invuln = EffectPrimitivesData.get_effect_invuln(target_unit)
	var effect_invuln_source = EffectPrimitivesData.get_effect_invuln_source(target_unit)
	if effect_invuln > 0:
		print("RulesEngine: Target has effect-granted %d+ invulnerable save (melee interactive, source: %s)" % [effect_invuln, effect_invuln_source])

	# Calculate save profile for each model — NO COVER in melee
	var model_save_profiles = []
	for model_info in allocation_info.models:
		var model = model_info.model
		# MA-12: Per-model save from stats_override
		var model_base_save = _get_model_effective_save(model, target_unit, base_save)
		if model_base_save != base_save:
			print("RulesEngine: MA-12 per-model save override (melee) — model %s save %d+ (unit default %d+)" % [model_info.model_id, model_base_save, base_save])

		# Invulnerable save: use best of model's native invuln, stats_override invuln, and effect-granted invuln
		# MA-12: Check stats_override.invuln for per-model invuln override
		var model_invuln = _get_model_effective_invuln(model, target_unit, model.get("invuln", 0))
		var invuln_source = "Native" if model_invuln > 0 else ""
		if model_invuln != model.get("invuln", 0) and model_invuln > 0:
			invuln_source = "Wargear"
			print("RulesEngine: MA-12 per-model invuln override (melee) — model %s invuln %d+ (model default %d+)" % [model_info.model_id, model_invuln, model.get("invuln", 0)])
		if effect_invuln > 0:
			if model_invuln == 0 or effect_invuln < model_invuln:
				model_invuln = effect_invuln
				invuln_source = effect_invuln_source if effect_invuln_source != "" else "Ability"

		var save_result = _calculate_save_needed(model_base_save, ap, false, model_invuln)  # No cover in melee

		model_save_profiles.append({
			"model_id": model_info.model_id,
			"model_index": model_info.model_index,
			"is_wounded": model_info.is_wounded,
			"is_character": model_info.get("is_character", false),
			"current_wounds": model.get("current_wounds", model.get("wounds", 1)),
			"max_wounds": model.get("wounds", 1),
			"has_cover": false,  # No cover in melee
			"save_needed": save_result.inv if save_result.use_invuln else save_result.armour,
			"using_invuln": save_result.use_invuln,
			"invuln_value": save_result.inv,
			"invuln_source": invuln_source,
			"armour_value": save_result.armour,
			"model_type": model.get("model_type", "")  # MA-21: Model type for wound allocation UI display
		})

	# DEVASTATING WOUNDS data
	var has_devastating_wounds = devastating_wounds_data.get("has_devastating_wounds", false)
	var critical_wounds = devastating_wounds_data.get("critical_wounds", 0)
	var regular_wounds = devastating_wounds_data.get("regular_wounds", wounds_caused)
	var wounds_needing_saves = regular_wounds if has_devastating_wounds else wounds_caused
	var devastating_wound_count = critical_wounds if has_devastating_wounds else 0
	var devastating_damage_val = devastating_wound_count * damage

	# HALF DAMAGE (T4-17)
	var has_half_damage = get_unit_half_damage(target_unit)
	# MINUS DAMAGE (P1-18)
	var minus_dmg = EffectPrimitivesData.get_effect_minus_damage(target_unit)

	# DA BIGGER DEY IZ (OA-49): Mozrog Skragbad — conditional damage bonus vs MONSTER/VEHICLE/TITANIC
	var da_bigger_bonus = get_da_bigger_damage_bonus(attacker_unit, target_unit)
	if da_bigger_bonus > 0:
		print("RulesEngine: DA BIGGER DEY IZ (melee interactive) — +%d damage for %s" % [da_bigger_bonus, attacker_unit.get("meta", {}).get("name", attacker_unit_id)])

	return {
		"success": true,
		"wounds_to_save": wounds_needing_saves,
		"total_wounds": wounds_caused,
		"target_unit_id": target_unit_id,
		"target_unit_name": target_unit.get("meta", {}).get("display_name", target_unit.get("meta", {}).get("name", target_unit_id)),
		"shooter_unit_id": attacker_unit_id,
		"weapon_name": weapon_profile.get("name", "Unknown Weapon"),
		"ap": ap,
		"damage": damage,
		"damage_raw": damage_raw,
		"base_save": base_save,
		"model_save_profiles": model_save_profiles,
		"allocation_priority": allocation_info.priority_model_ids,
		# DEVASTATING WOUNDS
		"has_devastating_wounds": has_devastating_wounds,
		"devastating_wounds": devastating_wound_count,
		"devastating_damage": devastating_damage_val,
		# No cover, no indirect fire, no melta in melee
		"ignores_cover": true,
		"indirect_fire": false,
		"melta_bonus": 0,
		"melta_models_in_half_range": 0,
		"melta_total_models": 0,
		# PRECISION
		"has_precision": precision_data.get("has_precision", false),
		"precision_wounds": precision_data.get("precision_wounds", 0),
		"precision_critical_hits": precision_data.get("critical_hits", 0),
		"character_model_ids": allocation_info.character_model_ids,
		"bodyguard_alive": allocation_info.bodyguard_alive,
		# Melee-specific: damage modifiers for WoundAllocationOverlay
		"has_half_damage": has_half_damage,
		"minus_damage": minus_dmg,
		# DA BIGGER DEY IZ (OA-49): Conditional damage bonus for melee
		"da_bigger_damage_bonus": da_bigger_bonus,
		# Flag to identify this as melee save data
		"is_melee": true
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
	var damage_raw = save_data.get("damage_raw", str(damage_per_wound))
	var units = board.get("units", {})
	var target_unit = units.get(target_unit_id, {})

	if target_unit.is_empty():
		return result

	var models = target_unit.get("models", [])
	var damage_roll_log = []

	# MELTA X (T1-1): Get melta bonus data from save_data
	var melta_bonus = save_data.get("melta_bonus", 0)
	var melta_models_in_half_range = save_data.get("melta_models_in_half_range", 0)
	var melta_total_models = save_data.get("melta_total_models", 0)
	# Calculate how many wounds get melta bonus (proportional to models in half range)
	var total_wounds_for_melta = save_data.get("total_wounds", 0)
	var melta_wounds_remaining = 0  # Counter for wounds that still get melta bonus
	if melta_bonus > 0 and melta_models_in_half_range > 0 and melta_total_models > 0:
		if melta_models_in_half_range >= melta_total_models:
			# All models in half range — all wounds get melta bonus
			melta_wounds_remaining = total_wounds_for_melta
		else:
			# Proportional: ceil(wounds * models_in_half_range / total_models)
			melta_wounds_remaining = ceili(float(total_wounds_for_melta) * float(melta_models_in_half_range) / float(melta_total_models))
		print("RulesEngine: MELTA +%d — %d/%d wounds get melta bonus" % [melta_bonus, melta_wounds_remaining, total_wounds_for_melta])

	# FEEL NO PAIN: Check if target unit has FNP
	# Issue #388: psychic-weapon damage triggers FNP-vs-psychic, even non-mortal.
	# Read the is_psychic flag stashed by prepare_save_resolution.
	var ranged_is_psychic = bool(save_data.get("is_psychic", false))
	var fnp_value = get_unit_fnp_for_attack(target_unit, ranged_is_psychic)

	# HALF DAMAGE (T4-17): Check if target unit has half-damage defensive ability
	var has_half_damage = get_unit_half_damage(target_unit)
	if has_half_damage:
		print("RulesEngine: Half Damage active on defender — all damage characteristics halved (round up)")

	# MINUS DAMAGE (P1-18): Check if target unit has damage reduction (e.g. Guardian Eternal -1 Damage)
	var int_minus_dmg = EffectPrimitivesData.get_effect_minus_damage(target_unit)
	if int_minus_dmg > 0:
		print("RulesEngine: Minus Damage active on defender — all damage reduced by %d (min 1)" % int_minus_dmg)

	# DA BIGGER DEY IZ (OA-49): Conditional damage bonus from melee save data
	var da_bigger_bonus = save_data.get("da_bigger_damage_bonus", 0)
	if da_bigger_bonus > 0:
		print("RulesEngine: DA BIGGER DEY IZ — +%d damage per wound (interactive save)" % da_bigger_bonus)

	# DEVASTATING WOUNDS (PRP-012, T2-11): Apply devastating damage first (unsaveable)
	# T2-11: DW mortal wounds spill over between models via _apply_damage_to_unit_pool
	# Roll variable damage per devastating wound (D3, D6, etc.)
	var devastating_wound_count = save_data.get("devastating_wounds", 0)
	var dw_damage = 0
	if devastating_damage_override >= 0:
		dw_damage = devastating_damage_override
		# HALF DAMAGE (T4-17): Halve overridden devastating damage (round up)
		if has_half_damage and dw_damage > 0:
			var pre_half = dw_damage
			dw_damage = apply_half_damage(dw_damage)
			print("RulesEngine: Half Damage — devastating override damage %d → %d" % [pre_half, dw_damage])
		# MINUS DAMAGE (P1-18): Subtract damage reduction, min 1
		if int_minus_dmg > 0 and dw_damage > 0:
			var pre_minus = dw_damage
			dw_damage = max(1, dw_damage - int_minus_dmg)
			print("RulesEngine: Minus Damage — devastating override damage %d → %d (-%d)" % [pre_minus, dw_damage, int_minus_dmg])
	elif devastating_wound_count > 0 and rng != null:
		for _i in range(devastating_wound_count):
			var dmg_result = roll_variable_characteristic(damage_raw, rng)
			var dw_wound_damage = dmg_result.value
			# MELTA X (T1-1): Add melta bonus to devastating wound damage if applicable
			if melta_bonus > 0 and melta_wounds_remaining > 0:
				dw_wound_damage += melta_bonus
				melta_wounds_remaining -= 1
				print("RulesEngine: MELTA +%d applied to devastating wound (damage: %d → %d)" % [melta_bonus, dmg_result.value, dw_wound_damage])
			# DA BIGGER DEY IZ (OA-49): Add conditional damage bonus before defensive modifiers
			if da_bigger_bonus > 0:
				dw_wound_damage += da_bigger_bonus
			# HALF DAMAGE (T4-17): Halve devastating wound damage (round up)
			if has_half_damage:
				var pre_half = dw_wound_damage
				dw_wound_damage = apply_half_damage(dw_wound_damage)
				print("RulesEngine: Half Damage — devastating wound damage %d → %d" % [pre_half, dw_wound_damage])
			# MINUS DAMAGE (P1-18): Subtract damage reduction, min 1
			if int_minus_dmg > 0:
				var pre_minus = dw_wound_damage
				dw_wound_damage = max(1, dw_wound_damage - int_minus_dmg)
				print("RulesEngine: Minus Damage — devastating wound damage %d → %d (-%d)" % [pre_minus, dw_wound_damage, int_minus_dmg])
			dw_damage += dw_wound_damage
			if dmg_result.rolled:
				damage_roll_log.append({"source": "devastating", "result": dmg_result})
	else:
		dw_damage = save_data.get("devastating_damage", 0)
		# MELTA X (T1-1): Add melta bonus to fixed devastating damage estimate
		if melta_bonus > 0 and devastating_wound_count > 0 and melta_wounds_remaining > 0:
			var melta_dw_wounds = min(devastating_wound_count, melta_wounds_remaining)
			dw_damage += melta_dw_wounds * melta_bonus
			melta_wounds_remaining -= melta_dw_wounds
		# DA BIGGER DEY IZ (OA-49): Add conditional damage bonus to fixed estimate
		if da_bigger_bonus > 0 and devastating_wound_count > 0:
			dw_damage += devastating_wound_count * da_bigger_bonus
		# HALF DAMAGE (T4-17): Halve fixed devastating damage estimate (round up)
		if has_half_damage and dw_damage > 0:
			var pre_half = dw_damage
			dw_damage = apply_half_damage(dw_damage)
			print("RulesEngine: Half Damage — fixed devastating damage %d → %d" % [pre_half, dw_damage])
		# MINUS DAMAGE (P1-18): Subtract damage reduction from fixed estimate, min 1
		if int_minus_dmg > 0 and dw_damage > 0:
			var pre_minus = dw_damage
			dw_damage = max(1, dw_damage - int_minus_dmg)
			print("RulesEngine: Minus Damage — fixed devastating damage %d → %d (-%d)" % [pre_minus, dw_damage, int_minus_dmg])
	if dw_damage > 0:
		print("RulesEngine: Applying %d devastating wounds damage (unsaveable)" % dw_damage)

		# FEEL NO PAIN: FNP applies even to devastating wounds.
		# T-016: DW is mortal-wound damage, so consult the conditional FNP
		# (Daughters of the Abyss FNP 3+ vs Psychic/MW only).
		var actual_dw_damage = dw_damage
		var dw_fnp_value = get_unit_fnp_for_attack(target_unit, true)
		if dw_fnp_value > 0 and rng != null:
			var fnp_result = roll_feel_no_pain(dw_damage, dw_fnp_value, rng)
			actual_dw_damage = fnp_result.wounds_remaining
			result.fnp_rolls.append({
				"context": "feel_no_pain",
				"source": "devastating_wounds",
				"rolls": fnp_result.rolls,
				"fnp_value": dw_fnp_value,
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

		# Roll variable damage per failed save (D3, D6, etc.)
		var wound_damage = damage_per_wound
		if rng != null:
			var dmg_result = roll_variable_characteristic(damage_raw, rng)
			wound_damage = dmg_result.value
			if dmg_result.rolled:
				damage_roll_log.append({"source": "failed_save", "result": dmg_result})

		# MELTA X (T1-1): Add melta bonus to damage if applicable
		if melta_bonus > 0 and melta_wounds_remaining > 0:
			wound_damage += melta_bonus
			melta_wounds_remaining -= 1
			print("RulesEngine: MELTA +%d applied to failed save damage (total: %d)" % [melta_bonus, wound_damage])

		# DA BIGGER DEY IZ (OA-49): Add conditional damage bonus before defensive modifiers
		if da_bigger_bonus > 0:
			wound_damage += da_bigger_bonus

		# HALF DAMAGE (T4-17): Halve per-wound damage (round up)
		if has_half_damage:
			var pre_half = wound_damage
			wound_damage = apply_half_damage(wound_damage)
			print("RulesEngine: Half Damage — failed save damage %d → %d" % [pre_half, wound_damage])

		# MINUS DAMAGE (P1-18): Subtract damage reduction (e.g. Guardian Eternal -1 Damage), min 1
		if int_minus_dmg > 0:
			var pre_minus = wound_damage
			wound_damage = max(1, wound_damage - int_minus_dmg)
			print("RulesEngine: Minus Damage — failed save damage %d → %d (-%d)" % [pre_minus, wound_damage, int_minus_dmg])

		# FEEL NO PAIN: Roll FNP for each point of damage from this failed save
		# MA-28: Use per-model FNP if available, otherwise fall back to unit FNP
		var actual_damage = wound_damage
		var model_fnp_value = get_model_fnp(target_unit, model)
		if model_fnp_value > 0 and rng != null:
			var fnp_result = roll_feel_no_pain(wound_damage, model_fnp_value, rng)
			actual_damage = fnp_result.wounds_remaining
			result.fnp_rolls.append({
				"context": "feel_no_pain",
				"source": "failed_save",
				"rolls": fnp_result.rolls,
				"fnp_value": model_fnp_value,
				"wounds_prevented": fnp_result.wounds_prevented,
				"wounds_remaining": fnp_result.wounds_remaining,
				"total_wounds": wound_damage
			})
			result.fnp_wounds_prevented += fnp_result.wounds_prevented

			if actual_damage == 0:
				print("RulesEngine: FNP prevented all %d damage from failed save!" % wound_damage)
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
			# MA-22: Log model destruction with model type label
			var destroyed_label = get_model_display_label(model, target_unit)
			print("RulesEngine: 💀 %s destroyed" % destroyed_label)

	# Log variable damage rolls if any occurred
	if damage_roll_log.size() > 0:
		result["damage_roll_log"] = damage_roll_log
		print("RulesEngine: Variable damage rolled (%s): %s" % [damage_raw, str(damage_roll_log.map(func(entry): return entry.result.value))])

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
			# MA-22: Log model destruction with model type label
			var pool_unit = board.get("units", {}).get(target_unit_id, {})
			var pool_label = get_model_display_label(model, pool_unit)
			print("RulesEngine: 💀 %s destroyed (devastating wounds)" % pool_label)

	return result

# T2-11: Apply damage per-wound WITHOUT spillover (for regular failed saves in melee)
# Each wound's damage is applied to one model; excess damage beyond that model's HP is LOST.
# This matches 10e rules where normal attack damage does not spill over between models.
static func _apply_damage_per_wound_no_spillover(target_unit_id: String, wound_damages: Array, models: Array, board: Dictionary) -> Dictionary:
	"""Apply per-wound damage without spillover. Each wound targets an allocated model;
	if the model dies, excess damage from that wound is lost (does not carry to next model).
	Next wound targets next alive model."""
	var result_ns = {
		"diffs": [],
		"casualties": 0,
		"damage_applied": 0
	}

	for wound_dmg in wound_damages:
		if wound_dmg <= 0:
			continue

		# Find next model to allocate this wound to (wounded first, then any alive)
		var target_idx = _find_allocation_target_model(models)
		if target_idx < 0:
			break  # No alive models left

		var model = models[target_idx]
		var current_wounds = model.get("current_wounds", model.get("wounds", 1))
		# Damage is CAPPED at model's remaining wounds — NO spillover
		var damage_to_apply = mini(wound_dmg, current_wounds)
		var new_wounds = current_wounds - damage_to_apply

		result_ns.diffs.append({
			"op": "set",
			"path": "units.%s.models.%d.current_wounds" % [target_unit_id, target_idx],
			"value": new_wounds
		})

		result_ns.damage_applied += damage_to_apply
		models[target_idx]["current_wounds"] = new_wounds

		if new_wounds == 0:
			result_ns.diffs.append({
				"op": "set",
				"path": "units.%s.models.%d.alive" % [target_unit_id, target_idx],
				"value": false
			})
			result_ns.casualties += 1
			models[target_idx]["alive"] = false
			# MA-22: Log model destruction with model type label
			var ns_unit = board.get("units", {}).get(target_unit_id, {})
			var ns_label = get_model_display_label(model, ns_unit)
			print("RulesEngine: 💀 %s destroyed (no spillover)" % ns_label)
			# Excess damage from this wound is LOST (no spillover)
			var excess = wound_dmg - damage_to_apply
			if excess > 0:
				print("RulesEngine: T2-11 — %d excess damage lost (no spillover for regular wounds)" % excess)

	return result_ns

# T2-11: Distribute FNP prevention across per-wound damage values
# Reduces wound damages from last to first, removing prevented damage
static func _distribute_fnp_across_wounds(wound_damages: Array, wounds_prevented: int) -> Array:
	"""Reduce per-wound damage values by distributing FNP prevention.
	Removes prevented damage starting from the last wounds (least impactful)."""
	var result_arr = wound_damages.duplicate()
	var remaining_prevention = wounds_prevented

	# Remove prevented damage from end of array (last wounds prevented first)
	var i = result_arr.size() - 1
	while remaining_prevention > 0 and i >= 0:
		if result_arr[i] <= remaining_prevention:
			remaining_prevention -= result_arr[i]
			result_arr[i] = 0
		else:
			result_arr[i] -= remaining_prevention
			remaining_prevention = 0
		i -= 1

	# Filter out zero-damage wounds
	return result_arr.filter(func(d): return d > 0)

# T2-11: Trim wound damage array to match a target total
static func _trim_wound_damages_to_total(wound_damages: Array, target_total: int) -> Array:
	"""Return a subset of wound_damages whose sum equals target_total.
	Takes wounds from the front, trimming the last wound if needed."""
	if target_total <= 0:
		return []
	var result_arr = []
	var running_total = 0
	for d in wound_damages:
		if running_total >= target_total:
			break
		var needed = target_total - running_total
		if d <= needed:
			result_arr.append(d)
			running_total += d
		else:
			result_arr.append(needed)
			running_total = target_total
	return result_arr

# PRECISION: Apply damage specifically to CHARACTER models in the target unit
static func _apply_damage_to_character_models(target_unit_id: String, total_damage: int, models: Array, character_indices: Array, board: Dictionary) -> Dictionary:
	"""Apply damage to CHARACTER models first (for PRECISION ability).
	Only targets models at character_indices. If all CHARACTER models die,
	remaining damage is lost (it was specifically allocated to characters)."""
	var result = {
		"diffs": [],
		"casualties": 0,
		"damage_applied": 0
	}

	var remaining_damage = total_damage

	while remaining_damage > 0:
		# Find next alive CHARACTER model
		var target_index = -1
		# Wounded CHARACTER first
		for idx in character_indices:
			if idx < models.size() and models[idx].get("alive", true):
				var current = models[idx].get("current_wounds", models[idx].get("wounds", 1))
				var max_w = models[idx].get("wounds", 1)
				if current < max_w:
					target_index = idx
					break
		# Then any alive CHARACTER
		if target_index < 0:
			for idx in character_indices:
				if idx < models.size() and models[idx].get("alive", true):
					target_index = idx
					break

		if target_index < 0:
			break  # No alive CHARACTER models left

		var model = models[target_index]
		var current_wounds = model.get("current_wounds", model.get("wounds", 1))
		var damage_to_apply = min(remaining_damage, current_wounds)
		var new_wounds = current_wounds - damage_to_apply

		result.diffs.append({
			"op": "set",
			"path": "units.%s.models.%d.current_wounds" % [target_unit_id, target_index],
			"value": new_wounds
		})

		result.damage_applied += damage_to_apply
		remaining_damage -= damage_to_apply
		models[target_index]["current_wounds"] = new_wounds

		if new_wounds == 0:
			result.diffs.append({
				"op": "set",
				"path": "units.%s.models.%d.alive" % [target_unit_id, target_index],
				"value": false
			})
			result.casualties += 1
			models[target_index]["alive"] = false
			# MA-22: Log CHARACTER model destruction with model type label
			var char_unit = board.get("units", {}).get(target_unit_id, {})
			var char_label = get_model_display_label(model, char_unit)
			print("RulesEngine: 💀 %s destroyed (PRECISION)" % char_label)

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
	"""Returns FNP value (e.g. 5 for 5+), or 0 if unit has no FNP.
	Checks both base stats and effect-granted FNP, using the better (lower) value.
	Note: this returns the UNCONDITIONAL FNP only — for psychic/mortal-only FNP
	(e.g. Daughters of the Abyss) call get_unit_fnp_for_attack(unit, true)."""
	var base_fnp = unit.get("meta", {}).get("stats", {}).get("fnp", 0)
	var effect_fnp = EffectPrimitivesData.get_effect_fnp(unit)

	# Use the better (lower) FNP if both exist, otherwise whichever is non-zero
	if base_fnp > 0 and effect_fnp > 0:
		return min(base_fnp, effect_fnp)
	elif effect_fnp > 0:
		return effect_fnp
	elif base_fnp > 0:
		return base_fnp
	return 0

# T-016: FNP for a specific attack context.
# If the attack is a Psychic Attack OR a Mortal Wound, also consider the
# `effect_fnp_psychic_mortal` flag (set by Daughters of the Abyss et al.) and
# return whichever FNP value is better (lower).
# `is_psychic_or_mortal_wound` should be true for: mortal wounds (incl. those
# spilled from Devastating Wounds) and Psychic Attacks. False otherwise.
static func get_unit_fnp_for_attack(unit: Dictionary, is_psychic_or_mortal_wound: bool) -> int:
	var unconditional = get_unit_fnp(unit)
	if not is_psychic_or_mortal_wound:
		return unconditional
	var conditional = EffectPrimitivesData.get_effect_fnp_psychic_mortal(unit)
	# T-075: Null Aegis (Talons of the Emperor) — Custodes within 6" of friendly
	# ANATHEMA PSYKANA model gain FNP 5+ vs Psychic/MW. Take the better of all.
	var uam = Engine.get_main_loop().root.get_node_or_null("UnitAbilityManager") if Engine.get_main_loop() else null
	var null_aegis = 0
	if uam and uam.has_method("get_null_aegis_fnp"):
		null_aegis = int(uam.get_null_aegis_fnp(unit.get("id", "")))
	var best_conditional = conditional
	if null_aegis > 0 and (best_conditional <= 0 or null_aegis < best_conditional):
		best_conditional = null_aegis
	if best_conditional <= 0:
		return unconditional
	if unconditional <= 0:
		return best_conditional
	return min(unconditional, best_conditional)

# MA-28: Get effective FNP for a specific model, checking stats_override.fnp first.
# Returns the model's overridden FNP if available, otherwise falls back to unit FNP.
# Uses -1 sentinel from .get("fnp", -1) to distinguish "no override" from "explicitly no FNP (0)".
static func get_model_fnp(unit: Dictionary, model: Dictionary) -> int:
	var unit_fnp = get_unit_fnp(unit)
	if model.is_empty():
		return unit_fnp
	var model_type = model.get("model_type", "")
	if model_type == "":
		return unit_fnp
	var model_profiles = unit.get("meta", {}).get("model_profiles", {})
	if not model_profiles.has(model_type):
		return unit_fnp
	var override_fnp = model_profiles[model_type].get("stats_override", {}).get("fnp", -1)
	if override_fnp < 0:
		return unit_fnp  # No override — use unit FNP
	if override_fnp == 0:
		return 0  # Explicitly no FNP for this model type
	# Model has a specific FNP — also check effect FNP and use the better (lower) value
	var effect_fnp = EffectPrimitivesData.get_effect_fnp(unit)
	if effect_fnp > 0:
		return min(override_fnp, effect_fnp)
	return override_fnp

# HALF DAMAGE (T4-17): Check if unit has half-damage defensive ability
static func get_unit_half_damage(unit: Dictionary) -> bool:
	"""Returns true if the unit has the half-damage defensive ability"""
	return unit.get("meta", {}).get("stats", {}).get("half_damage", false)

# HALF DAMAGE (T4-17): Halve incoming damage, rounding up
# Per 10e rules: "Each time an attack is made against this unit, halve the Damage
# characteristic of that attack (rounding up)."
# Applied per-wound AFTER melta bonus, BEFORE Feel No Pain.
static func apply_half_damage(damage: int) -> int:
	"""Halve damage, rounding up. e.g. 5 -> 3, 6 -> 3, 1 -> 1"""
	return ceili(float(damage) / 2.0)

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

# ==========================================
# MORTAL WOUNDS (Stratagem Support)
# ==========================================

static func apply_mortal_wounds(target_unit_id: String, mortal_wounds: int, board: Dictionary, rng: RNGService = null) -> Dictionary:
	"""Apply mortal wounds to a target unit. Mortal wounds bypass saves entirely.
	Each mortal wound deals 1 damage. Feel No Pain can still prevent mortal wound damage.
	Returns { diffs: Array, casualties: int, wounds_applied: int, fnp_rolls: Array }
	"""
	var units = board.get("units", {})
	var target_unit = units.get(target_unit_id, {})
	if target_unit.is_empty():
		return {"diffs": [], "casualties": 0, "wounds_applied": 0, "fnp_rolls": []}

	var models = target_unit.get("models", [])

	# Check for Feel No Pain.
	# T-016: mortal wounds count as "psychic-or-mortal" for the conditional FNP check
	# (e.g. Daughters of the Abyss FNP 3+ vs Psychic/MW only).
	var fnp_value = get_unit_fnp_for_attack(target_unit, true)
	var actual_wounds = mortal_wounds
	var fnp_result = {}

	if fnp_value > 0 and rng != null:
		fnp_result = roll_feel_no_pain(mortal_wounds, fnp_value, rng)
		actual_wounds = fnp_result.get("wounds_remaining", mortal_wounds)
		print("RulesEngine: Mortal wounds FNP check — %d MW, FNP %d+, %d wounds remaining after FNP" % [mortal_wounds, fnp_value, actual_wounds])

	if actual_wounds <= 0:
		return {
			"diffs": [],
			"casualties": 0,
			"wounds_applied": 0,
			"fnp_rolls": fnp_result.get("rolls", [])
		}

	# Apply damage using the standard pool method (wounded models first)
	var damage_result = _apply_damage_to_unit_pool(target_unit_id, actual_wounds, models, board)

	return {
		"diffs": damage_result.get("diffs", []),
		"casualties": damage_result.get("casualties", 0),
		"wounds_applied": actual_wounds,
		"fnp_rolls": fnp_result.get("rolls", [])
	}

# ==========================================
# DEADLY DEMISE (P1-13)
# ==========================================

# Issue #390 CAREEN! API: arm a Deadly-Demise unit to translate to `dest`
# (Vector2 in board pixel coordinates) before its mortal wounds resolve. The
# UI layer should call this after the player picks a destination, between the
# CAREEN! confirmation and the call to resolve_deadly_demise.
static func queue_careen_move(unit_id: String, dest: Vector2, board: Dictionary) -> bool:
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	if unit.is_empty():
		return false
	if not unit.has("flags"):
		unit["flags"] = {}
	unit["flags"][EffectPrimitivesData.FLAG_CAREEN_PENDING_MOVE] = true
	unit["flags"]["careen_destination"] = {"x": dest.x, "y": dest.y}
	print("RulesEngine: CAREEN! armed for %s — destination Δ-anchored at (%.1f, %.1f)" % [unit_id, dest.x, dest.y])
	return true


static func resolve_deadly_demise(destroyed_unit_id: String, dd_value: String, board: Dictionary, rng: RNGService = null) -> Dictionary:
	"""Resolve Deadly Demise when a model with this ability is destroyed.
	Rules: Roll 1D6. On a 6, each unit within 6\" suffers 'dd_value' mortal wounds.
	If dd_value is a random number (D3, D6), roll separately for each unit within 6\".
	Args:
		destroyed_unit_id: The unit that was just destroyed
		dd_value: The mortal wound value string ('D6', 'D3', '1', etc.)
		board: The game state board dictionary
		rng: Optional RNG service for dice rolls
	Returns: { triggered: bool, trigger_roll: int, diffs: Array, per_target: Array, total_mortal_wounds: int, total_casualties: int }
	"""
	if rng == null:
		rng = make_rng()

	var units = board.get("units", {})
	var destroyed_unit = units.get(destroyed_unit_id, {})
	var destroyed_name = destroyed_unit.get("meta", {}).get("name", destroyed_unit_id)

	print("╔═══════════════════════════════════════════════════════════════")
	print("║ P1-13: DEADLY DEMISE — %s (%s) destroyed" % [destroyed_name, destroyed_unit_id])
	print("║ Deadly Demise value: %s" % dd_value)

	# Step 1: Roll 1D6 to see if Deadly Demise triggers (on a 6)
	var trigger_roll = rng.roll_d6(1)[0]
	print("║ Trigger roll: %d (needs 6)" % trigger_roll)

	if trigger_roll != 6:
		print("║ Deadly Demise did NOT trigger (rolled %d, needed 6)" % trigger_roll)
		print("╚═══════════════════════════════════════════════════════════════")
		return {
			"triggered": false,
			"trigger_roll": trigger_roll,
			"diffs": [],
			"per_target": [],
			"total_mortal_wounds": 0,
			"total_casualties": 0
		}

	print("║ DEADLY DEMISE TRIGGERED! Rolling mortal wounds for units within 6\"")

	# Issue #390 CAREEN!: if the player used CAREEN! on this unit before the
	# Deadly Demise mortal-wound roll resolves, slide the unit to the
	# pre-selected destination FIRST. Per Wahapedia, the unit "can move over
	# enemy units (excluding MONSTERS and VEHICLES) as if they were not there"
	# — the player is responsible for selecting a legal destination; we simply
	# translate every model by the same delta so the relative formation is
	# preserved.
	var careen_flags = destroyed_unit.get("flags", {})
	if careen_flags.get(EffectPrimitivesData.FLAG_CAREEN_PENDING_MOVE, false):
		var dest = careen_flags.get("careen_destination", null)
		if dest != null:
			var anchor_model = null
			for m in destroyed_unit.get("models", []):
				if m.has("position"):
					anchor_model = m
					break
			if anchor_model != null:
				var anchor_pos = anchor_model.get("position")
				var ax = anchor_pos.x if not (anchor_pos is Dictionary) else anchor_pos.x
				var ay = anchor_pos.y if not (anchor_pos is Dictionary) else anchor_pos.y
				var dx = dest.x - ax
				var dy = dest.y - ay
				print("║ CAREEN! — translating %s by Δ(%.1f, %.1f) before Deadly Demise resolves" % [destroyed_name, dx, dy])
				for m2 in destroyed_unit.get("models", []):
					if m2.has("position"):
						var p = m2.position
						if p is Dictionary:
							m2.position = {"x": p.x + dx, "y": p.y + dy}
						else:
							m2.position = Vector2(p.x + dx, p.y + dy)
		# Clear the careen flag so the move is single-shot.
		careen_flags.erase(EffectPrimitivesData.FLAG_CAREEN_PENDING_MOVE)
		careen_flags.erase("careen_destination")

	# Step 2: Find all units within 6" of the destroyed model
	var destroyed_owner = destroyed_unit.get("owner", 0)
	var targets_within_6 = _find_units_within_range_of_unit(destroyed_unit_id, 6.0, board)

	var all_diffs: Array = []
	var per_target: Array = []
	var total_mortal_wounds = 0
	var total_casualties = 0

	for target_info in targets_within_6:
		var target_unit_id = target_info.get("unit_id", "")
		var target_name = target_info.get("unit_name", target_unit_id)

		# Step 3: Roll mortal wounds for each target
		var mortal_wounds = _roll_deadly_demise_damage(dd_value, rng)
		print("║ Target: %s — %d mortal wound(s) (from %s)" % [target_name, mortal_wounds, dd_value])

		var target_result = {
			"target_unit_id": target_unit_id,
			"target_name": target_name,
			"mortal_wounds": mortal_wounds,
			"casualties": 0
		}

		# Step 4: Apply mortal wounds
		if mortal_wounds > 0:
			var mw_result = apply_mortal_wounds(target_unit_id, mortal_wounds, board, rng)
			all_diffs.append_array(mw_result.get("diffs", []))
			target_result["casualties"] = mw_result.get("casualties", 0)
			total_casualties += mw_result.get("casualties", 0)

		total_mortal_wounds += mortal_wounds
		per_target.append(target_result)

	print("║ DEADLY DEMISE SUMMARY: %d mortal wound(s) dealt, %d casualt(y/ies) across %d target(s)" % [
		total_mortal_wounds, total_casualties, per_target.size()
	])
	print("╚═══════════════════════════════════════════════════════════════")

	return {
		"triggered": true,
		"trigger_roll": trigger_roll,
		"diffs": all_diffs,
		"per_target": per_target,
		"total_mortal_wounds": total_mortal_wounds,
		"total_casualties": total_casualties
	}

# ==========================================
# TRANSPORT DESTRUCTION (P1-60)
# ==========================================

static func resolve_transport_destruction(transport_unit_id: String, board: Dictionary, rng: RNGService = null) -> Dictionary:
	"""Resolve effects when a transport with embarked units is destroyed.
	Rules (10e): When a TRANSPORT model is destroyed, embarked units must emergency disembark.
	Roll 1D6 per disembarking model:
	  - Roll of 1: That model's unit suffers 1 mortal wound
	  - Roll of 2+: Model disembarks safely
	Models are set up within 3\" of the destroyed transport. If they can't be placed, they are destroyed.
	The disembarking unit is Battle-shocked and counts as having made a Normal move (cannot charge).
	Args:
		transport_unit_id: The transport unit that was just destroyed
		board: The game state board dictionary
		rng: Optional RNG service for dice rolls
	Returns: { embarked_unit_ids: Array, per_unit: Array[{unit_id, unit_name, model_rolls: Array, mortal_wounds: int, models_destroyed: int, diffs: Array}], total_mortal_wounds: int, total_models_destroyed: int, all_diffs: Array }
	"""
	if rng == null:
		rng = make_rng()

	var units = board.get("units", {})
	var transport = units.get(transport_unit_id, {})
	var transport_name = transport.get("meta", {}).get("name", transport_unit_id)

	print("╔═══════════════════════════════════════════════════════════════")
	print("║ P1-60: TRANSPORT DESTRUCTION — %s (%s) destroyed" % [transport_name, transport_unit_id])

	# Get embarked unit IDs from transport_data
	var transport_data = transport.get("transport_data", {})
	var embarked_unit_ids = transport_data.get("embarked_units", []).duplicate()

	if embarked_unit_ids.is_empty():
		print("║ No embarked units — nothing to resolve")
		print("╚═══════════════════════════════════════════════════════════════")
		return {
			"embarked_unit_ids": [],
			"per_unit": [],
			"total_mortal_wounds": 0,
			"total_models_destroyed": 0,
			"all_diffs": []
		}

	print("║ Embarked units: %d" % embarked_unit_ids.size())

	var all_diffs: Array = []
	var per_unit: Array = []
	var total_mortal_wounds: int = 0
	var total_models_destroyed: int = 0

	for embarked_id in embarked_unit_ids:
		var embarked_unit = units.get(embarked_id, {})
		if embarked_unit.is_empty():
			print("║ WARNING: Embarked unit %s not found in board" % embarked_id)
			continue

		var unit_name = embarked_unit.get("meta", {}).get("name", embarked_id)
		var models = embarked_unit.get("models", [])

		print("║ ─────────────────────────────────────────────────────────")
		print("║ Processing embarked unit: %s (%s)" % [unit_name, embarked_id])

		var unit_result = {
			"unit_id": embarked_id,
			"unit_name": unit_name,
			"model_rolls": [],
			"mortal_wounds": 0,
			"models_destroyed": 0,
			"diffs": []
		}

		# Roll D6 per alive model
		var alive_model_count = 0
		for model in models:
			if model.get("alive", true):
				alive_model_count += 1

		if alive_model_count == 0:
			print("║   No alive models in unit — skipping")
			per_unit.append(unit_result)
			continue

		var rolls = rng.roll_d6(alive_model_count)
		unit_result["model_rolls"] = rolls

		# Count mortal wounds (roll of 1 = 1 MW to the unit)
		var unit_mortal_wounds = 0
		for roll in rolls:
			if roll == 1:
				unit_mortal_wounds += 1

		unit_result["mortal_wounds"] = unit_mortal_wounds
		print("║   Rolled %s — %d mortal wound(s) from rolls of 1" % [str(rolls), unit_mortal_wounds])

		# Apply mortal wounds to the unit if any
		if unit_mortal_wounds > 0:
			var mw_result = apply_mortal_wounds(embarked_id, unit_mortal_wounds, board, rng)
			unit_result["diffs"].append_array(mw_result.get("diffs", []))
			unit_result["models_destroyed"] = mw_result.get("casualties", 0)
			total_models_destroyed += mw_result.get("casualties", 0)
			print("║   Applied %d mortal wound(s) — %d model(s) destroyed" % [unit_mortal_wounds, mw_result.get("casualties", 0)])

		total_mortal_wounds += unit_mortal_wounds

		# Clear embarked_in status — unit is now disembarking
		unit_result["diffs"].append({
			"op": "set",
			"path": "units.%s.embarked_in" % embarked_id,
			"value": null
		})

		# Set unit as deployed (in case it was in a different state)
		unit_result["diffs"].append({
			"op": "set",
			"path": "units.%s.status" % embarked_id,
			"value": GameStateData.UnitStatus.DEPLOYED
		})

		# Apply Battle-shocked flag per transport destruction rules
		unit_result["diffs"].append({
			"op": "set",
			"path": "units.%s.flags.battle_shocked" % embarked_id,
			"value": true
		})

		# Mark as having made a Normal move (cannot charge this turn)
		unit_result["diffs"].append({
			"op": "set",
			"path": "units.%s.flags.moved" % embarked_id,
			"value": true
		})
		unit_result["diffs"].append({
			"op": "set",
			"path": "units.%s.flags.cannot_charge" % embarked_id,
			"value": true
		})

		# Mark disembarked_this_phase
		unit_result["diffs"].append({
			"op": "set",
			"path": "units.%s.disembarked_this_phase" % embarked_id,
			"value": true
		})

		# Position surviving models near the destroyed transport
		var transport_models = transport.get("models", [])
		var transport_pos = null
		if not transport_models.is_empty():
			transport_pos = transport_models[0].get("position", null)

		if transport_pos != null:
			var model_index = 0
			for i in range(models.size()):
				if models[i].get("alive", true):
					# Place surviving models in a circle within 3" of transport position
					var angle = (2.0 * PI * model_index) / max(alive_model_count, 1)
					var offset_px = Measurement.inches_to_px(2.0)  # 2" offset (within 3" rule)
					var new_x = transport_pos.get("x", 0) + cos(angle) * offset_px
					var new_y = transport_pos.get("y", 0) + sin(angle) * offset_px
					unit_result["diffs"].append({
						"op": "set",
						"path": "units.%s.models.%d.position" % [embarked_id, i],
						"value": {"x": new_x, "y": new_y}
					})
					model_index += 1
			print("║   Positioned %d surviving model(s) within 3\" of transport" % model_index)

		all_diffs.append_array(unit_result["diffs"])
		per_unit.append(unit_result)

	# Clear the transport's embarked_units list
	all_diffs.append({
		"op": "set",
		"path": "units.%s.transport_data.embarked_units" % transport_unit_id,
		"value": []
	})

	print("║ ─────────────────────────────────────────────────────────")
	print("║ TRANSPORT DESTRUCTION SUMMARY:")
	print("║   Units disembarked: %d" % per_unit.size())
	print("║   Total mortal wounds: %d" % total_mortal_wounds)
	print("║   Total models destroyed: %d" % total_models_destroyed)
	print("╚═══════════════════════════════════════════════════════════════")

	return {
		"embarked_unit_ids": embarked_unit_ids,
		"per_unit": per_unit,
		"total_mortal_wounds": total_mortal_wounds,
		"total_models_destroyed": total_models_destroyed,
		"all_diffs": all_diffs
	}

# ==========================================
# DREAD FOE (P1-17)
# ==========================================

static func resolve_dread_foe(attacker_unit_id: String, target_unit_id: String, charged_this_turn: bool, board: Dictionary, rng: RNGService = null) -> Dictionary:
	"""Resolve Dread Foe ability when the Contemptor-Achillus is selected to fight.
	Rules: Select one enemy unit within Engagement Range. Roll 1D6, adding 2 if
	this model made a Charge move this turn: on 4-5, D3 mortal wounds; on 6+, 3 mortal wounds.
	Args:
		attacker_unit_id: The unit with Dread Foe (Contemptor-Achillus)
		target_unit_id: The selected enemy unit within Engagement Range
		charged_this_turn: Whether the attacker charged this turn (+2 to roll)
		board: The game state board dictionary
		rng: Optional RNG service for dice rolls
	Returns: { roll: int, modified_roll: int, mortal_wounds: int, diffs: Array, casualties: int }
	"""
	if rng == null:
		rng = make_rng()

	var units = board.get("units", {})
	var attacker_unit = units.get(attacker_unit_id, {})
	var attacker_name = attacker_unit.get("meta", {}).get("name", attacker_unit_id)
	var target_unit = units.get(target_unit_id, {})
	var target_name = target_unit.get("meta", {}).get("name", target_unit_id)

	print("╔═══════════════════════════════════════════════════════════════")
	print("║ P1-17: DREAD FOE — %s (%s)" % [attacker_name, attacker_unit_id])
	print("║ Target: %s (%s)" % [target_name, target_unit_id])
	print("║ Charged this turn: %s" % str(charged_this_turn))

	# Step 1: Roll 1D6
	var roll = rng.roll_d6(1)[0]
	var modified_roll = roll + (2 if charged_this_turn else 0)
	print("║ Roll: %d%s = %d" % [roll, " +2 (charged)" if charged_this_turn else "", modified_roll])

	# Step 2: Determine mortal wounds based on modified roll
	var mortal_wounds = 0
	if modified_roll >= 6:
		mortal_wounds = 3
		print("║ Result: 6+ → 3 mortal wounds!")
	elif modified_roll >= 4:
		# D3 mortal wounds (D6 / 2, round up: 1-2=1, 3-4=2, 5-6=3)
		var d3_roll = rng.roll_d6(1)[0]
		mortal_wounds = ceili(float(d3_roll) / 2.0)
		print("║ Result: 4-5 → D3 mortal wounds (rolled %d on D6 = %d)" % [d3_roll, mortal_wounds])
	else:
		print("║ Result: %d — no mortal wounds (needs 4+)" % modified_roll)
		print("╚═══════════════════════════════════════════════════════════════")
		return {
			"roll": roll,
			"modified_roll": modified_roll,
			"mortal_wounds": 0,
			"diffs": [],
			"casualties": 0
		}

	# Step 3: Apply mortal wounds to target
	var mw_result = apply_mortal_wounds(target_unit_id, mortal_wounds, board, rng)

	print("║ DREAD FOE SUMMARY: %d mortal wound(s) dealt to %s, %d casualt(y/ies)" % [
		mortal_wounds, target_name, mw_result.get("casualties", 0)
	])
	print("╚═══════════════════════════════════════════════════════════════")

	return {
		"roll": roll,
		"modified_roll": modified_roll,
		"mortal_wounds": mortal_wounds,
		"diffs": mw_result.get("diffs", []),
		"casualties": mw_result.get("casualties", 0),
		"fnp_rolls": mw_result.get("fnp_rolls", [])
	}

# ==========================================
# PISTON-DRIVEN BRUTALITY (OA-36)
# ==========================================

static func resolve_piston_driven_brutality(attacker_unit_id: String, target_unit_id: String, board: Dictionary, rng: RNGService = null) -> Dictionary:
	"""OA-36: Resolve Piston-driven Brutality ability after a Deff Dread ends a Charge move.
	Rules: Select one enemy unit within Engagement Range. Roll 1D6:
	  on 2-5, D3 mortal wounds; on 6, D3+3 mortal wounds; on 1, nothing.
	Args:
		attacker_unit_id: The unit with Piston-driven Brutality (Deff Dread)
		target_unit_id: The selected enemy unit within Engagement Range
		board: The game state board dictionary
		rng: Optional RNG service for dice rolls
	Returns: { roll: int, mortal_wounds: int, diffs: Array, casualties: int }
	"""
	if rng == null:
		rng = make_rng()

	var units = board.get("units", {})
	var attacker_unit = units.get(attacker_unit_id, {})
	var attacker_name = attacker_unit.get("meta", {}).get("name", attacker_unit_id)
	var target_unit = units.get(target_unit_id, {})
	var target_name = target_unit.get("meta", {}).get("name", target_unit_id)

	print("╔═══════════════════════════════════════════════════════════════")
	print("║ OA-36: PISTON-DRIVEN BRUTALITY — %s (%s)" % [attacker_name, attacker_unit_id])
	print("║ Target: %s (%s)" % [target_name, target_unit_id])

	# Step 1: Roll 1D6
	var roll = rng.roll_d6(1)[0]
	print("║ Roll: %d" % roll)

	# Step 2: Determine mortal wounds based on roll
	var mortal_wounds = 0
	if roll == 6:
		# D3+3 mortal wounds
		var d3_roll = rng.roll_d6(1)[0]
		var d3_value = ceili(float(d3_roll) / 2.0)
		mortal_wounds = d3_value + 3
		print("║ Result: 6 → D3+3 mortal wounds (D3 rolled %d on D6 = %d, +3 = %d)" % [d3_roll, d3_value, mortal_wounds])
	elif roll >= 2:
		# D3 mortal wounds
		var d3_roll = rng.roll_d6(1)[0]
		mortal_wounds = ceili(float(d3_roll) / 2.0)
		print("║ Result: %d → D3 mortal wounds (rolled %d on D6 = %d)" % [roll, d3_roll, mortal_wounds])
	else:
		print("║ Result: 1 — no mortal wounds")
		print("╚═══════════════════════════════════════════════════════════════")
		return {
			"roll": roll,
			"mortal_wounds": 0,
			"diffs": [],
			"casualties": 0
		}

	# Step 3: Apply mortal wounds to target
	var mw_result = apply_mortal_wounds(target_unit_id, mortal_wounds, board, rng)

	print("║ PISTON-DRIVEN BRUTALITY SUMMARY: %d mortal wound(s) dealt to %s, %d casualt(y/ies)" % [
		mortal_wounds, target_name, mw_result.get("casualties", 0)
	])
	print("╚═══════════════════════════════════════════════════════════════")

	return {
		"roll": roll,
		"mortal_wounds": mortal_wounds,
		"diffs": mw_result.get("diffs", []),
		"casualties": mw_result.get("casualties", 0),
		"fnp_rolls": mw_result.get("fnp_rolls", [])
	}

static func _find_units_within_range_of_unit(source_unit_id: String, range_inches: float, board: Dictionary) -> Array:
	"""Find all units (friendly AND enemy) within range_inches of any model in the source unit.
	Deadly Demise affects ALL units within 6\", both friendly and enemy.
	Returns array of { unit_id, unit_name, distance }."""
	var units = board.get("units", {})
	var source_unit = units.get(source_unit_id, {})
	if source_unit.is_empty():
		return []

	var source_models = source_unit.get("models", [])
	var results: Array = []

	for other_id in units:
		if other_id == source_unit_id:
			continue

		var other_unit = units.get(other_id, {})

		# Skip fully destroyed units
		var has_alive = false
		for model in other_unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue

		# Check edge-to-edge distance from destroyed model to nearest alive model
		var min_dist = INF
		for source_model in source_models:
			# Use the destroyed model's position (it was just marked dead but position still exists)
			var source_pos = source_model.get("position", null)
			if source_pos == null:
				continue

			for other_model in other_unit.get("models", []):
				if not other_model.get("alive", true):
					continue
				var dist = Measurement.model_to_model_distance_inches(source_model, other_model)
				min_dist = min(min_dist, dist)

		if min_dist <= range_inches:
			results.append({
				"unit_id": other_id,
				"unit_name": other_unit.get("meta", {}).get("name", other_id),
				"distance": min_dist
			})
			print("║ Unit within 6\": %s (%.1f\")" % [other_unit.get("meta", {}).get("name", other_id), min_dist])

	return results

static func _roll_deadly_demise_damage(dd_value: String, rng: RNGService) -> int:
	"""Roll the mortal wounds for a Deadly Demise trigger.
	dd_value: 'D6', 'D3', '1', etc."""
	var upper = dd_value.to_upper()
	if upper == "D6":
		return rng.roll_d6(1)[0]
	elif upper == "D3":
		# D3 = roll 1D6, divide by 2 rounding up: 1-2=1, 3-4=2, 5-6=3
		var roll = rng.roll_d6(1)[0]
		return ceili(float(roll) / 2.0)
	else:
		# Fixed value (e.g. "1", "2")
		return int(dd_value) if dd_value.is_valid_int() else 1

static func get_grenade_eligible_targets(actor_unit_id: String, board: Dictionary) -> Array:
	"""Get enemy units within 8\" and visible to the grenade-throwing unit.
	Returns array of { unit_id: String, unit_name: String, model_count: int }
	"""
	var eligible = []
	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})

	if actor_unit.is_empty():
		return eligible

	var actor_owner = actor_unit.get("owner", 0)
	var grenade_range_px = Measurement.inches_to_px(8)

	for target_unit_id in units:
		var target_unit = units[target_unit_id]

		# Skip friendly units
		if target_unit.get("owner", 0) == actor_owner:
			continue

		# Skip destroyed units
		var alive_count = 0
		for model in target_unit.get("models", []):
			if model.get("alive", true):
				alive_count += 1
		if alive_count == 0:
			continue

		# Check if any actor model is within 8" and has LoS to any target model
		var in_range_and_visible = false
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

				var distance = actor_pos.distance_to(target_pos)
				if distance <= grenade_range_px:
					in_range_and_visible = true
					break

			if in_range_and_visible:
				break

		if in_range_and_visible:
			eligible.append({
				"unit_id": target_unit_id,
				"unit_name": target_unit.get("meta", {}).get("display_name", target_unit.get("meta", {}).get("name", target_unit_id)),
				"model_count": alive_count
			})

	return eligible

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

# ============================================================================
# SURGE MOVE VALIDATION (P2-71) — 10e Core Rules Update
# ============================================================================
# Surge moves are out-of-phase moves triggered by abilities.
# Restrictions:
#   1. Each unit can only make one surge move per phase
#   2. A unit cannot make a surge move while it is Battle-shocked
#   3. A unit cannot make a surge move while it is within Engagement Range
#
# This static helper can be called from any phase to validate surge eligibility
# without needing a reference to the MovementPhase instance.

static func validate_surge_move_eligibility(unit: Dictionary, unit_id: String, has_surged_this_phase: bool, all_units: Dictionary) -> Dictionary:
	"""Validate whether a unit is eligible to make a surge move.
	Returns {valid: bool, errors: Array}.

	Parameters:
	  unit: The unit dictionary
	  unit_id: The unit's ID
	  has_surged_this_phase: Whether this unit already surged this phase
	  all_units: All units in the game state (for engagement range check)
	"""
	# Restriction 1: Once per phase
	if has_surged_this_phase:
		return {"valid": false, "errors": ["Unit has already made a surge move this phase"]}

	# Restriction 2: Not while Battle-shocked
	var flags = unit.get("flags", {})
	var status_effects = unit.get("status_effects", {})
	if flags.get("battle_shocked", false) or status_effects.get("battle_shocked", false):
		return {"valid": false, "errors": ["Battle-shocked units cannot make surge moves"]}

	# Restriction 3: Not while in Engagement Range
	var owner = unit.get("owner", 0)
	var unit_models = unit.get("models", [])
	for model in unit_models:
		if not model.get("alive", true):
			continue
		var model_pos = model.get("position")
		if model_pos == null:
			continue
		var pos = Vector2.ZERO
		if model_pos is Vector2:
			pos = model_pos
		elif model_pos is Dictionary:
			pos = Vector2(model_pos.get("x", 0), model_pos.get("y", 0))

		# Check against all enemy models
		for enemy_unit_id in all_units:
			var enemy_unit = all_units[enemy_unit_id]
			if enemy_unit.get("owner", 0) == owner:
				continue
			for enemy_model in enemy_unit.get("models", []):
				if not enemy_model.get("alive", true):
					continue
				var enemy_pos = enemy_model.get("position")
				if enemy_pos == null:
					continue
				var epos = Vector2.ZERO
				if enemy_pos is Vector2:
					epos = enemy_pos
				elif enemy_pos is Dictionary:
					epos = Vector2(enemy_pos.get("x", 0), enemy_pos.get("y", 0))

				# Use standard 1" engagement range check
				if Measurement.is_in_engagement_range_shape_aware(model, enemy_model):
					return {"valid": false, "errors": ["Units within Engagement Range cannot make surge moves"]}

	# Unit must have alive models
	var has_alive = false
	for model in unit_models:
		if model.get("alive", true):
			has_alive = true
			break
	if not has_alive:
		return {"valid": false, "errors": ["Unit has no alive models"]}

	return {"valid": true, "errors": []}


# ── ISS-020: public API for phases/controllers ──────────────────────
# Phases and controllers must not reach into RulesEngine's underscore-
# private internals (enforced by tests/test_iss020_public_api.gd). These
# documented wrappers are the supported surface; the privates remain free
# to be refactored.

## True if any model of unit1 is within engagement range of any model of
## unit2, barricade-aware (distinct from the simpler two-arg
## units_in_engagement_range above, which ignores terrain).
static func check_units_in_engagement_range(unit1: Dictionary, unit2: Dictionary, board: Dictionary) -> bool:
	return _check_units_in_engagement_range(unit1, unit2, board)

## Canonical weapon id for a weapon name (+ optional type for the
## type-aware format).
static func generate_weapon_id(weapon_name: String, weapon_type: String = "") -> String:
	return _generate_weapon_id(weapon_name, weapon_type)

## Allocate `total_damage` into the target unit's model pool; returns the
## damage-application result (diffs, casualties).
static func apply_damage_to_unit_pool(target_unit_id: String, total_damage: int, models: Array, board: Dictionary) -> Dictionary:
	return _apply_damage_to_unit_pool(target_unit_id, total_damage, models, board)

## Model dict lookup by id within a unit ({} if absent).
static func get_model_by_id(unit: Dictionary, model_id: String) -> Dictionary:
	return _get_model_by_id(unit, model_id)

## Legacy center-to-center LoS check (debug/visualization only).
static func check_legacy_line_of_sight(from_pos: Vector2, to_pos: Vector2, board: Dictionary) -> bool:
	return _check_legacy_line_of_sight(from_pos, to_pos, board)

## ISS-039: core engagement predicates (11e 03.04 terminology). A unit is
## "engaged" while any of its models is within engagement range of an enemy
## model; "unengaged" otherwise. These are THE eligibility predicates the
## 11e move/shooting/fight type templates gate on (edition-aware via
## GameConstants through the shape-aware check's default ER).
static func is_unit_engaged(unit_id: String, board: Dictionary) -> bool:
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	if unit.is_empty():
		return false
	var owner = int(unit.get("owner", 0))
	for other_id in units:
		if other_id == unit_id:
			continue
		var other = units[other_id]
		if int(other.get("owner", 0)) == owner:
			continue
		if _check_units_in_engagement_range(unit, other, board):
			return true
	return false

static func is_unit_unengaged(unit_id: String, board: Dictionary) -> bool:
	return not is_unit_engaged(unit_id, board)
