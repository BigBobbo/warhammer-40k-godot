extends Node
const GameStateData = preload("res://autoloads/GameState.gd")

# RulesEngine - Central authority for game rules validation and resolution
# Handles shooting mechanics, dice rolling, damage application following 10e rules
# This is an autoload singleton, accessed globally as RulesEngine

# MA-LOADOUT: bump whenever _ensure_loadout_resolved learns to resolve something
# it previously left as the datasheet menu. Units stamped by an older resolver
# (saved games, the tutorial fixtures) carry a lower version and are re-resolved
# on load, so an improvement reaches existing saves instead of only new ones.
#   1 — ranged from wargear (Phase 1) + melee from wargear (Phase 1b)
#   2 — melee/ranged fall back to the datasheet's DEFAULT per-model kit when the
#       roster's wargear says nothing about that weapon type (CASE D)
#   3 — a wargear line naming a multi-profile weapon by its base name
#       ("3x Rokkit Launcha" for "Rokkit Launcha – Blasta / – Busta"), or with
#       another capitalisation ("1x Power snappa"), counts for that weapon
#       (WP-O1b: codex Deffkoptas lost their Rokkit Launcha). A model that an
#       older version already stamped keeps its stamp (it no longer
#       over-reports, so it is not re-resolved).
const LOADOUT_RESOLVER_VERSION := 3

# Weapon profile structure (will be expanded later)
const WEAPON_PROFILES = {
	"bolt_rifle": {
		"name": "Bolt Rifle",
		"range": 24,  # 11e (40kdc bolt-rifle): 24" (was 30" in 10e)
		"attacks": 2,
		"bs": 3,
		"strength": 4,
		"ap": 1,
		"damage": 1,
		"keywords": ["ASSAULT", "HEAVY"]  # 11e: Assault + Heavy (10e Rapid Fire 1 dropped)
	},
	"boltgun": {
		"name": "Boltgun",
		"range": 24,  # 11e (40kdc boltgun, Adeptus Astartes copy)
		"attacks": 2,
		"bs": 3,
		"strength": 4,
		"ap": 0,
		"damage": 1,
		"keywords": []  # 11e boltgun has no weapon keywords
	},
	"plasma_pistol": {
		"name": "Plasma Pistol",
		"range": 120,  # Extended range for debugging (11e real range: 12)
		"attacks": 1,
		"bs": 3,
		"strength": 7,
		"ap": 2,  # 11e Standard profile: S7 AP-2 D1 (Supercharge S8 AP-3 D2 [HAZARDOUS] not modelled — single-profile dict)
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
		"keywords": ["PISTOL"]  # 11e: Pistol only (10e Assault dropped)
	},
	"choppa": {
		"name": "Choppa",
		"range": 0,
		"attacks": 3,
		"bs": 4,
		"ws": 3,
		"strength": 4,
		"ap": 1,
		"damage": 1,
		"type": "melee",
		"keywords": []  # 11e (40kdc choppa, Orks copy): A3 WS3+ S4 AP-1 D1
	},
	"grot_blasta": {
		"name": "Grot Blasta",
		"range": 12,
		"attacks": 1,
		"bs": 4,
		"strength": 3,
		"ap": 0,
		"damage": 1,
		"keywords": ["PISTOL"]  # 11e: gained Pistol
	},
	"shoota": {
		"name": "Shoota",
		"range": 18,
		"attacks": 2,
		"bs": 5,
		"strength": 4,
		"ap": 0,
		"damage": 1,
		"keywords": ["RAPID FIRE 1"]  # 11e: Rapid Fire 1 (10e Assault dropped)
	},
	"heavy_bolter": {
		"name": "Heavy Bolter",
		"range": 36,
		"attacks": 3,
		"bs": 3,
		"strength": 5,
		"ap": 1,
		"damage": 2,
		"keywords": ["ASSAULT", "SUSTAINED HITS 1"]  # 11e Astartes copy: Assault + Sustained Hits 1 (10e Heavy dropped)
	},
	"lascannon": {
		"name": "Lascannon",
		"range": 48,
		"attacks": 1,
		"bs": 3,
		"strength": 12,
		"ap": 3,
		"damage": 4,  # int fallback only (≈avg of D6+1); resolution uses damage_raw
		"damage_raw": "D6+1",  # 11e: D6+1 variable damage (was flat 6)
		"keywords": []  # 11e Astartes copy: no keywords (10e Heavy dropped)
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
		# 11e (40kdc tactical-squad): Tactical Marines carry boltguns, not bolt rifles
		"m1": ["boltgun"],
		"m2": ["boltgun"],
		"m3": ["boltgun"],
		"m4": ["boltgun"],
		"m5": ["boltgun", "plasma_pistol"]  # Sergeant
	},
	"U_BOYZ_A": {
		# 11e: each Boy carries slugga (+choppa) OR shoota (+CCW). This legacy
		# table is ranged-only and keeps the MVP simplification of both guns
		# per model; melee falls back to the default close combat weapon.
		"m1": ["slugga", "shoota"],
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
	REROLL_NON_CRIT = 16,  # Re-roll every hit roll that is not a critical hit (fishing for crits)
}

# Apply hit modifiers to a single roll
# Returns the modified roll value and any re-roll that occurred
# hit_threshold: the BS/WS value needed to hit (e.g. 3 for 3+); required for REROLL_FAILED
static func apply_hit_modifiers(roll: int, modifiers: int, rng: RNGService, hit_threshold: int = 0, fail_band: int = 1, crit_threshold: int = 6) -> Dictionary:
	var result = {
		"original_roll": roll,
		"modified_roll": roll,
		"rerolled": false,
		"reroll_value": 0,
		"modifier_applied": 0
	}

	# Net numeric modifier (capped at +1/-1) — known before the re-roll
	# decision even though it is applied after it.
	var pre_net := 0
	if modifiers & HitModifier.PLUS_ONE:
		pre_net += 1
	if modifiers & HitModifier.MINUS_ONE:
		pre_net -= 1
	pre_net = clampi(pre_net, -1, 1)
	# r5:F6/F9: "re-roll failed hits" re-rolls exactly the dice that would
	# FAIL once modifiers and any unmodified-fail band (INDIRECT FIRE,
	# SPEEDIEST FREEKS) are taken into account — never a die that would hit
	# (an unmodified critical always hits). The old test was raw < BS.
	var would_fail: bool = roll <= fail_band or (roll < crit_threshold and roll + pre_net < hit_threshold)

	# Step 1: Apply re-rolls FIRST (before modifiers per 10e rules)
	# Re-roll ones takes priority check first
	if (modifiers & HitModifier.REROLL_ONES) and roll == 1:
		var reroll_result = rng.roll_d6(1)[0]
		result.rerolled = true
		result.reroll_value = reroll_result
		result.modified_roll = reroll_result
	elif (modifiers & HitModifier.REROLL_FAILED) and hit_threshold > 0 and would_fail:
		# Re-roll all failed hit rolls (roll below BS/WS threshold)
		var reroll_result = rng.roll_d6(1)[0]
		result.rerolled = true
		result.reroll_value = reroll_result
		result.modified_roll = reroll_result
	elif (modifiers & HitModifier.REROLL_NON_CRIT) and roll < crit_threshold:
		# "Re-roll hit rolls" used to fish for critical hits: every roll that is
		# not a critical hit (failed AND successful non-critical) is re-rolled.
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

## effect_reroll_hits scope written by a "re-roll hit rolls" grant whose
## controller chose to fish for critical hits (Codex: Orks (11e) ARMED TO DA
## TEEF while riled up, "re-roll hit rolls" variant): failed hits are always
## re-rolled; successful NON-critical hits are re-rolled too for every weapon
## whose critical hits are worth more than a normal hit ([LETHAL HITS] /
## [SUSTAINED HITS], from the weapon or a granted effect). Weapons without a
## critical-hit payoff keep their successes (re-rolling them can only hurt).
const REROLL_HITS_SCOPE_NON_CRIT := "non_crit"

static func _non_crit_hit_reroll_bits(attacker_unit: Dictionary, weapon_id: String, board: Dictionary, is_melee: bool) -> int:
	var flags: Dictionary = attacker_unit.get("flags", {})
	var payoff := has_lethal_hits(weapon_id, board) or has_sustained_hits(weapon_id, board)
	if not payoff:
		if is_melee:
			payoff = bool(flags.get(EffectPrimitivesData.FLAG_LETHAL_HITS_MELEE, false)) or bool(flags.get(EffectPrimitivesData.FLAG_SUSTAINED_HITS_MELEE, false))
		else:
			payoff = bool(flags.get(EffectPrimitivesData.FLAG_LETHAL_HITS, false)) or bool(flags.get(EffectPrimitivesData.FLAG_SUSTAINED_HITS, false))
	if payoff:
		return HitModifier.REROLL_FAILED | HitModifier.REROLL_NON_CRIT
	return HitModifier.REROLL_FAILED

# Wound modifier flags (can be combined with bitwise OR)
# Per 10e rules: wound roll modifiers are capped at net +1/-1
enum WoundModifier {
	NONE = 0,
	REROLL_ONES = 1,    # Re-roll 1s to wound
	REROLL_FAILED = 2,  # Re-roll all failed wound rolls (Twin-linked)
	PLUS_ONE = 4,       # +1 to wound (e.g., Lance on charge)
	MINUS_ONE = 8,      # -1 to wound
	REROLL_ONES_TWOS = 16,  # Re-roll wound rolls of 1 and 2 (Codex: Space Marines 11e EYE OF THE PACK — SWCodex11e.gd)
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
	elif (modifiers & WoundModifier.REROLL_ONES_TWOS) and roll <= 2 and roll < wound_threshold:
		# Codex: Space Marines (11e) EYE OF THE PACK (SWCodex11e.gd): "can re-roll
		# wound rolls of 1 and 2" — a 2 that already wounds (2+) is kept.
		var reroll_12 = rng.roll_d6(1)[0]
		result.rerolled = true
		result.reroll_value = reroll_12
		result.modified_roll = reroll_12

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
	# 10.02: the selected shooting type rides on every assignment (10.07).
	var assignments = _stamp_shooting_type(action.get("payload", {}).get("assignments", []), action)

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
		if is_hazardous_weapon(weapon_id, board) \
				or board.get("units", {}).get(actor_unit_id, {}).get("flags", {}).get("effect_grant_hazardous", false):
			var models_that_fired = assignment.get("model_ids", []).size()
			var hazardous_result = resolve_hazardous_check(actor_unit_id, weapon_id, models_that_fired, board, rng_service)
			if hazardous_result.hazardous_triggered:
				result.diffs.append_array(hazardous_result.diffs)
			result.dice.append_array(hazardous_result.dice)
			# LV2-G1: the player-facing hazard line (this log_text can reach the
			# Game Log as the action's text) — same wording on every path.
			var haz_line := str(hazardous_result.get("game_log_text", hazardous_result.log_text))
			if haz_line != "":
				result.log_text += haz_line + "\n"

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
	# 10.02: the selected shooting type rides on every assignment (10.07).
	var assignments = _stamp_shooting_type(action.get("payload", {}).get("assignments", []), action)

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

		# GROT SHIELDS (Codex: Orks 11e): the Gretchin unit's mortal-wound diffs
		# travel in the one_shot_diffs channel — the diffs every ShootingPhase
		# resolution path already merges into the action's changes — and are
		# mirrored onto the local board so later weapons see the casualties.
		for gs_d in assignment_result.get("grot_shields_diffs", []):
			if not result.has("one_shot_diffs"):
				result["one_shot_diffs"] = []
			result["one_shot_diffs"].append(gs_d)
			_apply_diff_to_board(board, gs_d)

		# HAZARDOUS (T2-3): Track hazardous weapons for post-save resolution
		var weapon_id = assignment.get("weapon_id", "")
		if is_hazardous_weapon(weapon_id, board) or actor_unit.get("flags", {}).get("effect_grant_hazardous", false):
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
# STAGED SHOOTING (interactive Command Re-roll between hit and wound rolls)
# resolve_shoot_hits() rolls ONLY the hit roll for a single weapon and returns a
# hit_context; the caller may pause (offer Command Re-roll on a hit die via
# reroll_hit_die), then call resolve_shoot_wounds(hit_context) which rolls the
# wound roll and prepares save data. This lets a player re-roll a hit die BEFORE
# the wound roll is made — the whole point of the staged sequence. The composed
# resolve_shoot_until_wounds() above stays behaviour-identical for the fast /
# networked paths (golden tests guard it).
# ==========================================

static func resolve_shoot_hits(action: Dictionary, board: Dictionary, rng_service: RNGService = null) -> Dictionary:
	if not rng_service:
		rng_service = make_rng()
	var result = {"success": true, "phase": "SHOOTING", "dice": [], "log_text": "", "no_hits": true}
	var actor_unit_id = action.get("actor_unit_id", "")
	# 10.02: the selected shooting type rides on every assignment (10.07).
	var assignments = _stamp_shooting_type(action.get("payload", {}).get("assignments", []), action)
	if assignments.is_empty():
		result.success = false
		result.log_text = "No weapon assignments provided"
		return result
	# Staged path resolves ONE weapon at a time.
	var assignment = assignments[0]
	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})
	if actor_unit.is_empty():
		result.success = false
		result.log_text = "Actor unit not found"
		return result

	var hit_res = _resolve_assignment_hits(assignment, actor_unit_id, board, rng_service)
	result.dice = hit_res.get("dice", [])
	result.log_text = hit_res.get("log_text", "")
	result.no_hits = hit_res.get("no_hits", true)
	# Always propagate hit_context (present even on a miss) so the staged path can
	# Command Re-roll a missed die and continue to wounds if it becomes a hit.
	result["hit_context"] = hit_res.get("hit_context", {})

	# The weapon HAS fired once the hit roll is made — mirror the one-shot /
	# hazardous bookkeeping resolve_shoot_until_wounds() performs per assignment.
	var weapon_id = assignment.get("weapon_id", "")
	if is_hazardous_weapon(weapon_id, board) \
			or actor_unit.get("flags", {}).get("effect_grant_hazardous", false):
		result["hazardous_weapons"] = [{
			"weapon_id": weapon_id,
			"models_that_fired": assignment.get("model_ids", []).size()
		}]
	if is_one_shot_weapon(weapon_id, board):
		var one_shot_diffs = []
		for model_id in assignment.get("model_ids", []):
			one_shot_diffs.append_array(mark_one_shot_fired_diffs(actor_unit_id, actor_unit, model_id, weapon_id))
		result["one_shot_diffs"] = one_shot_diffs
	return result

static func resolve_shoot_wounds(hit_context: Dictionary, board: Dictionary, rng_service: RNGService = null) -> Dictionary:
	if not rng_service:
		rng_service = make_rng()
	var w = _resolve_assignment_wounds(hit_context, board, rng_service)
	var result = {
		"success": true,
		"phase": "SHOOTING",
		"dice": w.get("dice", []),
		"log_text": w.get("log_text", ""),
		"no_wounds": w.get("no_wounds", false),
		"save_data_list": []
	}
	if w.has("save_data") and w["save_data"].get("success", false):
		result["save_data_list"] = [w["save_data"]]
	if w.has("wound_context"):
		result["wound_context"] = w["wound_context"]
	# GROT SHIELDS (Codex: Orks 11e): same one_shot_diffs channel as
	# resolve_shoot_until_wounds — ShootingPhase merges it into the changes.
	if w.has("grot_shields_diffs"):
		result["one_shot_diffs"] = w["grot_shields_diffs"]
		for gs_d in w["grot_shields_diffs"]:
			_apply_diff_to_board(board, gs_d)
	return result

# COMMAND RE-ROLL — re-roll a single hit die and recompute totals in place.
# Only the chosen die is re-rolled; the untouched dice keep their result. A die
# re-rolled here is not auto-re-rolled again (re-roll modifiers masked off — a
# dice can only be re-rolled once). Returns an updated to_hit display block.
# Works for BOTH ranged and melee hit contexts (melee stores WS under "bs" and
# sets is_melee, which routes the display block context + skips DAKKASTORM).
## True when the staged die (stage "hits" -> hit_evals, "wounds" ->
## wound_evals) was already re-rolled — callers check this BEFORE spending
## the Command Re-roll CP (r5:F7: "never re-roll a dice more than once").
static func staged_die_already_rerolled(context: Dictionary, stage: String, die_index: int) -> bool:
	var evals: Array = context.get("hit_evals" if stage == "hits" else "wound_evals", [])
	if die_index < 0 or die_index >= evals.size():
		return false
	return bool(evals[die_index].get("rerolled", false))

static func reroll_hit_die(hit_context: Dictionary, die_index: int, rng_service: RNGService = null) -> Dictionary:
	if not rng_service:
		rng_service = make_rng()
	if hit_context.get("is_torrent", false):
		return {"success": false, "error": "Torrent weapons make no hit roll to re-roll"}
	if hit_context.get("no_hit_rerolls", false):
		return {"success": false, "error": "Indirect shooting: hit rolls cannot be re-rolled (10.07)"}
	var evals = hit_context.get("hit_evals", [])
	if die_index < 0 or die_index >= evals.size():
		return {"success": false, "error": "Invalid hit die index %d" % die_index}
	# Core rules: "you can never re-roll a dice more than once" — a die an
	# automatic re-roll (e.g. LONG, UNCONTROLLED BURSTS) or an earlier
	# Command Re-roll already re-rolled cannot be re-rolled again (r5:F7).
	if bool(evals[die_index].get("rerolled", false)):
		return {"success": false, "error": "That hit die has already been re-rolled — a dice can never be re-rolled more than once"}
	var old_crits = int(hit_context.get("critical_hits", 0))
	var bs_per_attack = hit_context.get("bs_per_attack", [])
	var attack_bs = int(bs_per_attack[die_index]) if die_index < bs_per_attack.size() else int(hit_context.get("bs", 4))
	var mods_no_reroll = int(hit_context.get("hit_modifiers", 0)) & ~(HitModifier.REROLL_ONES | HitModifier.REROLL_FAILED | HitModifier.REROLL_NON_CRIT)
	# DRIVE-BY BUSTIN' (Codex: Orks 11e): this die is a Firing Deck attack of a mixed batch
	var ork11e_fd_mask = hit_context.get("ork11e_fd_plus_one", [])
	if die_index < ork11e_fd_mask.size() and ork11e_fd_mask[die_index]:
		mods_no_reroll |= HitModifier.PLUS_ONE
	var new_raw = rng_service.roll_d6(1)[0]
	var ev = AttackSequence.evaluate_hit_roll(new_raw, attack_bs, mods_no_reroll, int(hit_context.get("critical_hit_threshold", 6)), rng_service, int(hit_context.get("hit_fail_band", 1)))
	var old_eval = evals[die_index]
	evals[die_index] = {"raw": new_raw, "final": ev.final_roll, "is_hit": ev.is_hit, "is_crit": ev.is_crit, "rerolled": true, "reroll_from": int(old_eval.get("raw", 0)), "reroll_to": new_raw}
	hit_context["hit_rolls"][die_index] = new_raw
	hit_context["modified_rolls"][die_index] = ev.final_roll

	# Re-tally from the per-die evals, then re-apply DAKKASTORM (all hits -> crits)
	var hits = 0
	var crits = 0
	var regular = 0
	for e in evals:
		if e.get("is_hit", false):
			hits += 1
			if e.get("is_crit", false):
				crits += 1
			else:
				regular += 1
	# DAKKASTORM converts hits to crits for RANGED attacks only — never melee.
	if not hit_context.get("is_melee", false) and has_dakkastorm(hit_context.get("actor_unit", {})) and regular > 0:
		crits += regular
		regular = 0
	hit_context["hits"] = hits
	hit_context["critical_hits"] = crits
	hit_context["regular_hits"] = regular
	# Sustained bonus hits depend on the crit count — only re-roll them if the
	# crit count actually changed, so re-rolling a plain miss->hit doesn't churn
	# an unrelated Sustained bonus.
	if crits != old_crits:
		var sr = roll_sustained_hits(crits, hit_context.get("sustained_data", {"value": 0, "is_dice": false}), rng_service)
		hit_context["sustained_bonus_hits"] = sr.bonus_hits
	hit_context["total_hits_for_wounds"] = hits + int(hit_context.get("sustained_bonus_hits", 0))

	var block = {
		"context": "hit_roll_melee" if hit_context.get("is_melee", false) else "to_hit",
		"threshold": str(hit_context.get("hit_threshold_display", str(hit_context.get("bs", 4)) + "+")),
		"rolls_raw": hit_context["hit_rolls"],
		"rolls_modified": hit_context["modified_rolls"],
		"rerolls": hit_context.get("reroll_data", []),
		"successes": hits,
		"target_unit_id": str(hit_context.get("target_unit_id", "")),  # enemy_has_shot window
		"critical_hits": crits,
		"sustained_bonus_hits": int(hit_context.get("sustained_bonus_hits", 0)),
		"total_hits_for_wounds": hit_context["total_hits_for_wounds"],
		# Carry the provenance through a Command Re-roll — the modifiers that
		# produced this threshold have not changed just because one die did.
		"modifier_ledger": hit_context.get("modifier_ledger", []),
		"command_rerolled_index": die_index
	}
	return {
		"success": true,
		"hit_context": hit_context,
		"dice_block": block,
		"old_value": old_eval.get("raw", 0),
		"new_value": new_raw,
		# Modified (post-BS-modifier) values — what the log / die buttons display.
		"old_display": old_eval.get("final", old_eval.get("raw", 0)),
		"new_display": ev.final_roll
	}

# COMMAND RE-ROLL — re-roll a single wound die, recompute wounds and rebuild the
# save data (wounds_to_save / devastating crits) from the new tally.
static func reroll_wound_die(wound_context: Dictionary, die_index: int, board: Dictionary, rng_service: RNGService = null) -> Dictionary:
	if not rng_service:
		rng_service = make_rng()
	var evals = wound_context.get("wound_evals", [])
	if die_index < 0 or die_index >= evals.size():
		return {"success": false, "error": "Invalid wound die index %d" % die_index}
	if bool(evals[die_index].get("rerolled", false)):
		return {"success": false, "error": "That wound die has already been re-rolled — a dice can never be re-rolled more than once"}
	var mods_no_reroll = int(wound_context.get("wound_modifiers", 0)) & ~(WoundModifier.REROLL_ONES | WoundModifier.REROLL_FAILED | WoundModifier.REROLL_ONES_TWOS)
	var new_raw = rng_service.roll_d6(1)[0]
	var ev = AttackSequence.evaluate_wound_roll(new_raw, mods_no_reroll, int(wound_context.get("wound_threshold", 4)), int(wound_context.get("critical_wound_threshold", 6)), rng_service)
	var old_eval = evals[die_index]
	evals[die_index] = {"raw": new_raw, "is_wound": ev.is_wound, "is_crit": ev.is_crit, "auto_fail": ev.auto_fail, "rerolled": true, "reroll_from": int(old_eval.get("raw", 0)), "reroll_to": new_raw}
	wound_context["wound_rolls"][die_index] = new_raw

	var has_dev = bool(wound_context.get("weapon_has_devastating_wounds", false))
	var wounds_from_rolls = 0
	var crit_wounds = 0
	var regular_wounds = 0
	var all_crit_wounds = 0  # ALL critical wounds regardless of DW (melee Hold Still)
	for e in evals:
		if e.get("auto_fail", false):
			continue
		if e.get("is_wound", false):
			wounds_from_rolls += 1
			if e.get("is_crit", false):
				all_crit_wounds += 1
			if has_dev and e.get("is_crit", false):
				crit_wounds += 1
			else:
				regular_wounds += 1
	var auto_wounds = int(wound_context.get("auto_wounds", 0))
	regular_wounds += auto_wounds  # Lethal Hits auto-wounds count as regular wounds
	var wounds_caused = auto_wounds + wounds_from_rolls

	var dev_data = {
		"has_devastating_wounds": has_dev,
		"critical_wounds": crit_wounds,
		"regular_wounds": regular_wounds
	}
	var precision_data = {}
	if bool(wound_context.get("weapon_has_precision", false)):
		precision_data = {
			"has_precision": true,
			"critical_hits": int(wound_context.get("critical_hits", 0)),
			"precision_wounds": mini(int(wound_context.get("critical_hits", 0)), wounds_caused)
		}
	var save_data = {}
	if wounds_caused > 0:
		# Melee wound contexts rebuild save data via the melee AP-modifier chain
		# (no cover / melta in melee) — same overlay format either way.
		if wound_context.get("is_melee", false):
			save_data = prepare_melee_save_resolution(
				wounds_caused,
				wound_context.get("target_unit_id", ""),
				wound_context.get("actor_unit_id", ""),
				wound_context.get("weapon_profile", {}),
				board,
				dev_data,
				precision_data
			)
		else:
			save_data = prepare_save_resolution(
				wounds_caused,
				wound_context.get("target_unit_id", ""),
				wound_context.get("actor_unit_id", ""),
				wound_context.get("weapon_profile", {}),
				board,
				dev_data,
				wound_context.get("melta_data", {}),
				precision_data
			)
	var block = {
		"context": "wound_roll_melee" if wound_context.get("is_melee", false) else "to_wound",
		"threshold": str(wound_context.get("wound_threshold", 4)) + "+",
		"rolls_raw": wound_context["wound_rolls"],
		"successes": wounds_caused,
		"critical_wounds": crit_wounds,
		"regular_wounds": regular_wounds,
		# Same as the hit path: a re-rolled die does not change WHY the
		# threshold is what it is.
		"modifier_ledger": wound_context.get("modifier_ledger", []),
		"command_rerolled_index": die_index
	}
	return {
		"success": true,
		"wound_context": wound_context,
		"dice_block": block,
		"wounds_caused": wounds_caused,
		"critical_wounds": crit_wounds,
		"regular_wounds": regular_wounds,
		"all_critical_wounds": all_crit_wounds,
		"save_data": save_data,
		"old_value": old_eval.get("raw", 0),
		"new_value": new_raw
	}

# ==========================================
# OVERWATCH SHOOTING (Fire Overwatch Stratagem)
# Only unmodified 6s hit. All other shooting mechanics (wound, save, damage) are normal.
# ==========================================

static func resolve_overwatch_shooting(shooter_unit_id: String, target_unit_id: String, board: Dictionary, rng_service: RNGService = null, hit_on_six: bool = true) -> Dictionary:
	"""Resolve overwatch shooting: all weapons fire at the target, but only unmodified 6s count as hits.
	No hit modifiers are applied. Wound rolls, saves, and damage work normally.
	With hit_on_six=false the weapons hit on their normal (unmodified) BS instead —
	used by CALL DAT DAKKA? (More Dakka!) to shoot back 'as if it were your
	Shooting phase' outside the shooting flow.
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

		var wa_result = _resolve_overwatch_assignment(wa, shooter_unit_id, target_unit_id, board, rng_service, hit_on_six)
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

# ==========================================
# 11e 15.09 SNAP SHOOTING — targets + weapon assignments (FIRE OVERWATCH 15.08)
# ==========================================
# 15.09 WHILE SHOOTING: "You can only target one visible enemy unit within 24"
# of your unit (and only if it is an eligible target)." 15.08 only targets an
# UNENGAGED unit, and 19.01 makes a bodyguard + its attached CHARACTER(s) ONE
# unit — so everything below is measured from every model of the shooter's
# Attached unit (a leader's model counts for the 24" and for visibility, and
# the leader's guns shoot) against every model of the target's Attached unit.

## Copy of `board` whose `component_ids` units read as unengaged:
## flags.in_engagement is a cache refreshed at the start of the Shooting
## phase and is stale in the Movement phase. The snap shooter has been checked
## unengaged LIVE (RulesEngine.is_attached_unit_engaged) before it is offered,
## and a stale `true` would make get_eligible_targets apply the engaged
## [PISTOL] / Big Guns rules to it. Shallow copies — terrain keeps its
## identity, so the LoS memo epoch is unaffected.
static func _snap_board_unengaged(board: Dictionary, component_ids: Array) -> Dictionary:
	var b: Dictionary = board.duplicate(false)
	var units: Dictionary = board.get("units", {}).duplicate(false)
	for cid in component_ids:
		if not units.has(cid):
			continue
		var u: Dictionary = units[cid].duplicate(false)
		var f: Dictionary = u.get("flags", {}).duplicate(false)
		f["in_engagement"] = false
		u["flags"] = f
		units[cid] = u
	b["units"] = units
	return b

## The alive, positioned models of `component_ids` with their centre (px) and
## circumscribed base radius (px, Measurement.base_extent_px) — the input of
## _snap_min_distance_pts. Models without a position (reserves, embarked) are
## left out (_get_min_distance_to_target_rules would read them as (0, 0)).
static func _snap_model_points(component_ids: Array, board: Dictionary) -> Array:
	var pts: Array = []
	var units: Dictionary = board.get("units", {})
	for cid in component_ids:
		for m in units.get(cid, {}).get("models", []):
			if not m.get("alive", true) or m.get("position") == null:
				continue
			var pos = m.get("position")
			var c: Vector2 = pos if pos is Vector2 else Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
			pts.append({"m": m, "c": c, "r": Measurement.base_extent_px(m)})
	return pts

## Closest edge-to-edge distance (inches) between two model sets from
## _snap_model_points, or INF when it is more than `cutoff_inches` (or either
## set is empty). PERF: a pair whose bounding circles are already farther apart
## than the cutoff / the best pair so far skips the shape-aware measurement.
static func _snap_min_distance_pts(a_pts: Array, b_pts: Array, cutoff_inches: float = INF) -> float:
	var best := INF
	for a in a_pts:
		for t in b_pts:
			var lower_in: float = (a.c.distance_to(t.c) - float(a.r) - float(t.r)) / Measurement.PX_PER_INCH
			if lower_in > cutoff_inches or lower_in >= best:
				continue
			best = minf(best, Measurement.model_to_model_distance_inches(a.m, t.m))
	return best if best <= cutoff_inches else INF

## Closest edge-to-edge distance (inches) between any alive, positioned model
## of the shooter's Attached unit and any of the target's Attached unit (INF
## when either side has none on the battlefield).
static func _snap_min_distance_inches(shooter_components: Array, target_components: Array, board: Dictionary) -> float:
	return _snap_min_distance_pts(_snap_model_points(shooter_components, board), _snap_model_points(target_components, board))

## 15.09 "visible": at least one model of the shooter's Attached unit can see
## at least one model of the target's Attached unit (the same 11e visibility
## predicate target eligibility uses — unit_sight_line).
static func _snap_unit_visible(shooter_components: Array, target_components: Array, board: Dictionary) -> bool:
	for sid in shooter_components:
		for tid in target_components:
			if unit_sight_line(sid, tid, board, false).get("has_los", false):
				return true
	return false

## The legal SNAP-shooting targets of `shooter_unit_id`'s (Attached) unit:
## enemy units within 24" of it (measured first — it is the cheapest test, and
## only those units go through the LoS-heavy eligibility scan), that are an
## eligible target (RulesEngine.get_eligible_targets — Lone Operative X",
## Psychic Veil, Hunter profiles, >= 1 weapon in range and visible — asked of
## every component of the Attached unit), UNENGAGED, and visible to the unit.
## 04.02: "Unless otherwise stated, each target must be: ... Unengaged."
## 17.03 lifts that for MONSTER/VEHICLE targets only "In your Shooting phase";
## snap shooting happens in the opponent's Movement phase, so an engaged
## MONSTER/VEHICLE (which get_eligible_targets lets through for the Shooting
## phase) is dropped here — and so is a target whose attached CHARACTER is
## engaged (19.01: one unit). Sneaky Surprise units cannot be targeted by Fire
## Overwatch (datasheet ability). Returns [{unit_id, label, distance_inches}],
## nearest first. `pts_cache` (optional, PERF): unit id -> _snap_model_points
## of its Attached unit, shared by a caller that asks about many shooters on the
## same board (the FIRE OVERWATCH offer) so each enemy unit is measured once.
static func snap_shooting_targets_11e(shooter_unit_id: String, board: Dictionary, pts_cache: Dictionary = {}) -> Array:
	var out: Array = []
	var units: Dictionary = board.get("units", {})
	var shooter: Dictionary = units.get(shooter_unit_id, {})
	if shooter.is_empty():
		return out
	var owner := int(shooter.get("owner", 0))
	var head := attached_unit_target_id(shooter_unit_id, board)
	var components: Array = attached_unit_component_ids(head, board)
	# 15.09 "within 24" of your unit": enemy units (a bodyguard heads its
	# Attached unit — an attached CHARACTER is targeted through it, and
	# embarked units are not on the battlefield).
	var near: Dictionary = {}  # target id -> closest distance (inches)
	var shooter_pts: Array = _snap_model_points(components, board)
	if shooter_pts.is_empty():
		return out
	for tid in units:
		var target_u: Dictionary = units[tid]
		if int(target_u.get("owner", 0)) == owner:
			continue
		if target_u.get("attached_to", null) != null or target_u.get("embarked_in", null) != null:
			continue
		if not pts_cache.has(tid):
			pts_cache[tid] = _snap_model_points(attached_unit_component_ids(tid, board), board)
		var dist := _snap_min_distance_pts(shooter_pts, pts_cache[tid], 24.0)
		if dist <= 24.0:
			near[tid] = dist
	if near.is_empty():
		return out
	# 15.08 TARGET "One friendly unengaged unit": an engaged unit has no snap
	# shot at all. Engagement range is at most 2" horizontally (barricades,
	# T3-9), so only a unit with an enemy model that close needs the (live,
	# whole-Attached-unit) engagement check — not the stale flags.in_engagement.
	var nearest := INF
	for tid in near:
		nearest = minf(nearest, float(near[tid]))
	if nearest <= maxf(GameConstants.engagement_range_inches(), GameConstants.barricade_engagement_range_inches()) + 1.0 \
			and is_attached_unit_engaged(head, board):
		print("RulesEngine: [15.08] SNAP — %s is engaged: no snap shooting" % head)
		return out
	var b := _snap_board_unengaged(board, components)
	var candidate_ids: Dictionary = {}
	for cid in components:
		var et: Dictionary = get_eligible_targets(cid, b, false, near)
		for tid in et:
			candidate_ids[tid] = true
	var ability_mgr = Engine.get_main_loop().root.get_node_or_null("UnitAbilityManager")
	for tid in candidate_ids:
		var target: Dictionary = units.get(tid, {})
		if target.is_empty() or int(target.get("owner", 0)) == owner:
			continue
		if ability_mgr != null and ability_mgr.has_method("has_sneaky_surprise") and ability_mgr.has_sneaky_surprise(tid):
			print("RulesEngine: [15.09] SNAP — %s has Sneaky Surprise (cannot be targeted by Fire Overwatch)" % tid)
			continue
		var cus11e_block := _cus11e_snap_block_reason(target)
		if cus11e_block == "" and GameConstants.edition >= 11:
			cus11e_block = str(load("res://scripts/codex/space_marines/SMDetachmentsA.gd").snap_block_reason(target))  # WP-M2a Seal of Shrouding / Linebreaker Onslaught
		if cus11e_block != "":
			print("RulesEngine: [15.09] SNAP — %s cannot be targeted with snap shooting (%s)" % [tid, cus11e_block])
			continue
		if is_attached_unit_engaged(tid, board):
			print("RulesEngine: [15.09/04.02] SNAP — %s is engaged: not an eligible target outside your Shooting phase (17.03)" % tid)
			continue
		var target_components: Array = attached_unit_component_ids(tid, board)
		if not _snap_unit_visible(components, target_components, board):
			continue
		var meta: Dictionary = target.get("meta", {})
		out.append({"unit_id": tid, "label": str(meta.get("display_name", meta.get("name", tid))), "distance_inches": float(near.get(tid, INF))})
	out.sort_custom(func(a, c): return float(a.distance_inches) < float(c.distance_inches))
	return out

## Codex: Adeptus Custodes (11e) rules that make a unit an illegal SNAP-shooting
## target: GOLDEN LIGHT OF THE MOIRAIDES (stratagem, WP-C5) and COMBAT
## DEPLOYMENT (enhancement, WP-C46) — "enemy units cannot target that unit with
## snap shooting attacks". Both read the whole Attached unit. "" = no block.
## (They used to be checked only on the 10e per-move Fire Overwatch path,
## StratagemManager.get_fire_overwatch_eligible_units.)
static func _cus11e_snap_block_reason(target_unit: Dictionary) -> String:
	if target_unit.is_empty() or GameConstants.edition < 11:
		return ""
	if load("res://scripts/codex/custodes/CustodesCodex11e.gd").blocks_snap_shooting_at(target_unit):
		return "GOLDEN LIGHT OF THE MOIRAIDES"
	if load("res://scripts/codex/custodes/CustodesDetachments.gd").blocks_snap_shooting(target_unit):
		return "Combat Deployment"
	return ""

## Expected damage of one profile against the target (used to pick one
## profile per weapon, 04.01.03, and the [CLOSE-QUARTERS] / other-weapons set
## of a model, 24.07). Same heuristic as ShootingPhase's forced-shoot picker.
static func _snap_profile_value(weapon_id: String, target_unit: Dictionary, board: Dictionary) -> float:
	var prof = get_weapon_profile(weapon_id, board)
	var t := float(str(target_unit.get("meta", {}).get("stats", {}).get("toughness", 4))) if str(target_unit.get("meta", {}).get("stats", {}).get("toughness", 4)).is_valid_float() else 4.0
	var s := float(str(prof.get("strength", 4))) if str(prof.get("strength", 4)).is_valid_float() else 4.0
	var p_wound := 3.0 / 6.0
	if s >= 2.0 * t:
		p_wound = 5.0 / 6.0
	elif s > t:
		p_wound = 4.0 / 6.0
	elif s * 2.0 <= t:
		p_wound = 1.0 / 6.0
	elif s < t:
		p_wound = 2.0 / 6.0
	var ap := absf(float(str(prof.get("ap", 0)))) if str(prof.get("ap", 0)).is_valid_float() else 0.0
	return _snap_avg_value(prof.get("attacks_raw", prof.get("attacks", 1))) * p_wound \
		* _snap_avg_value(prof.get("damage_raw", prof.get("damage", 1))) * (1.0 + 0.15 * ap)

static func _snap_avg_value(v) -> float:
	var s := str(v).to_upper().replace(" ", "")
	if s.is_valid_float():
		return float(s)
	var plus := 0.0
	if "+" in s:
		var p := s.split("+")
		s = p[0]
		plus = float(p[1]) if p.size() > 1 and p[1].is_valid_float() else 0.0
	var d := s.find("D")
	if d < 0:
		return plus
	var n := float(s.substr(0, d)) if d > 0 and s.substr(0, d).is_valid_float() else 1.0
	var sides := float(s.substr(d + 1)) if s.substr(d + 1).is_valid_float() else 6.0
	return n * (sides + 1.0) / 2.0 + plus

static func _snap_weapon_base_name(weapon_id: String, board: Dictionary) -> String:
	var wname := str(get_weapon_profile(weapon_id, board).get("name", weapon_id))
	for sep in [" – ", " — ", " - "]:
		var idx := wname.find(sep)
		if idx > 0:
			return wname.substr(0, idx)
	return wname

## [CLOSE-QUARTERS] weapon (24.07; [PISTOL] is identical, 24.27).
static func _snap_is_close_quarters_weapon(weapon_id: String, board: Dictionary) -> bool:
	if is_pistol_weapon(weapon_id, board):
		return true
	var abilities: Array = AbilityRegistry.from_weapon(get_weapon_profile(weapon_id, board))
	return AbilityRegistry.has_ability(abilities, "close_quarters") or AbilityRegistry.has_ability(abilities, "pistol")

## The weapon assignments a SNAP shot (15.09) at `target_unit_id` makes —
## "Your unit shoots as described in Making Attacks (04)":
##  - 04.01: every ranged weapon of every model of the Attached unit (the
##    leader's composite "<char>:<model>" bearers included), one profile per
##    weapon (04.01.03 — the best one vs this target), and for a model that is
##    not a MONSTER/VEHICLE either its [CLOSE-QUARTERS] weapons or its other
##    ranged weapons (24.07 — whichever set is worth more);
##  - 04.02: per weapon, only the models that can see the target and have it
##    in range fire (get_eligible_shooter_models); Hunter profiles that cannot
##    target it are dropped (04.01.03); a standalone Lone Operative is not
##    visible to models beyond its X" (24.24); spent [ONE SHOT] weapons stay
##    silent (24.26).
## Every assignment carries overwatch:true (BS 7 → only unmodified 6s hit, no
## hit re-rolls at 11e) and shooting_type "snap".
static func build_snap_assignments_11e(shooter_unit_id: String, target_unit_id: String, board: Dictionary) -> Array:
	var head := attached_unit_target_id(shooter_unit_id, board)
	var components: Array = attached_unit_component_ids(head, board)
	var b := _snap_board_unengaged(board, components)
	var units: Dictionary = b.get("units", {})
	var head_unit: Dictionary = units.get(head, {})
	var target: Dictionary = units.get(target_unit_id, {})
	if head_unit.is_empty() or target.is_empty():
		return []
	var lone_op_range := -1.0
	if has_lone_operative(target) and target.get("attached_to", null) == null \
			and target.get("attachment_data", {}).get("attached_characters", []).is_empty():
		lone_op_range = get_lone_operative_range(target)
	var unit_weapons: Dictionary = get_unit_weapons(head, b)
	var eligible_cache: Dictionary = {}  # weapon_id -> eligible bearer ids
	var models_for: Dictionary = {}  # weapon_id -> [bearer ids]
	for bearer_id in unit_weapons:
		var bearer_model: Dictionary = resolve_bearer_model(head_unit, str(bearer_id), b)
		if bearer_model.is_empty() or not bearer_model.get("alive", true) or bearer_model.get("position") == null:
			continue
		if lone_op_range > 0.0:
			var lo_best := INF
			for tm in target.get("models", []):
				if tm.get("alive", true) and tm.get("position") != null:
					lo_best = minf(lo_best, Measurement.model_to_model_distance_inches(bearer_model, tm))
			if lo_best > lone_op_range:
				continue
		var best_cq := {}     # base name -> weapon id
		var best_other := {}  # base name -> weapon id
		for wid in unit_weapons[bearer_id]:
			var prof: Dictionary = get_weapon_profile(wid, b)
			if prof.is_empty() or str(prof.get("type", "")).to_lower() == "melee":
				continue
			if not weapon_profile_can_target(wid, target, b):
				continue
			if is_one_shot_weapon(wid, b) and has_fired_one_shot(head_unit, str(bearer_id), wid):
				continue
			if not eligible_cache.has(wid):
				eligible_cache[wid] = get_eligible_shooter_models(head, wid, target_unit_id, b).get("eligible", [])
			if not (str(bearer_id) in eligible_cache[wid]):
				continue
			var base := _snap_weapon_base_name(wid, b)
			var bucket: Dictionary = best_cq if _snap_is_close_quarters_weapon(wid, b) else best_other
			if not bucket.has(base) or _snap_profile_value(wid, target, b) > _snap_profile_value(bucket[base], target, b):
				bucket[base] = wid
		var bearer_unit: Dictionary = resolve_bearer_unit(head_unit, str(bearer_id), b)
		var chosen: Array = []
		if is_monster_or_vehicle(bearer_unit if not bearer_unit.is_empty() else head_unit):
			chosen = best_cq.values() + best_other.values()
		else:
			var cq_value := 0.0
			for w in best_cq.values():
				cq_value += _snap_profile_value(w, target, b)
			var other_value := 0.0
			for w in best_other.values():
				other_value += _snap_profile_value(w, target, b)
			chosen = best_other.values() if other_value >= cq_value and not best_other.is_empty() else best_cq.values()
		for wid in chosen:
			if not models_for.has(wid):
				models_for[wid] = []
			models_for[wid].append(str(bearer_id))
	var assignments: Array = []
	for wid in models_for:
		assignments.append({"weapon_id": wid, "target_unit_id": target_unit_id, "model_ids": models_for[wid],
			"overwatch": true, "shooting_type": "snap"})
	return assignments

static func _resolve_overwatch_assignment(assignment: Dictionary, shooter_unit_id: String, target_unit_id: String, board: Dictionary, rng: RNGService, hit_on_six: bool = true) -> Dictionary:
	"""Resolve a single weapon assignment during overwatch.
	Key difference: only unmodified 6s count as hits (hit_on_six=false uses the
	weapon's unmodified BS instead — CALL DAT DAKKA?). No hit modifiers apply."""
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

	# WP-O6: Codex: Orks (11e) datasheet abilities (attacks / S / AP; overwatch hits only on 6s)
	var ork6: Dictionary = ork11e_ab_mods(shooter_unit, target_unit, weapon_profile, false, board, model_ids)
	var ow_ab_attacks_bonus := int(ork6.get("attacks", 0))

	for model_id in model_ids:
		var attacks_result = roll_variable_characteristic(attacks_raw, rng)
		var model_attacks_ow = attacks_result.value + ow_ab_attacks_bonus
		total_attacks += model_attacks_ow

	if ow_ab_attacks_bonus > 0:
		print("RulesEngine: [WP-O6] (Overwatch) — +%d attack(s) per model from Codex: Orks (11e) datasheet abilities" % ow_ab_attacks_bonus)

	if total_attacks <= 0:
		return result

	# --- PHASE 2: Hit rolls (OVERWATCH: only unmodified 6s hit; CALL DAT
	# DAKKA? shoots back at the weapon's normal unmodified BS instead) ---
	var hit_rolls = rng.roll_d6(total_attacks)
	var hits = 0
	var ow_threshold = 6
	if not hit_on_six:
		var bs_str = str(weapon_profile.get("ballistic_skill", "6"))
		ow_threshold = int(bs_str) if bs_str.is_valid_int() else 6

	# SPEEDIEST FREEKS (Codex: Orks 11e): unmodified hit rolls of 1-3 fail.
	var ow_fail_band := ork11e_ranged_hit_fail_band(target_unit, 1)
	for roll in hit_rolls:
		if roll >= ow_threshold and roll > ow_fail_band:  # unmodified; 1s always fail
			hits += 1

	result.dice.append({
		"context": "overwatch_to_hit",
		"weapon_name": weapon_name,
		"threshold": ("6 (Overwatch)" if hit_on_six else "%d+ (unmodified BS)" % ow_threshold),
		"rolls_raw": hit_rolls,
		"total_attacks": total_attacks,
		"successes": hits,
		"overwatch": true
	})

	# GROT SHIELDS (Codex: Orks 11e): overwatch hits carry no crit tracking —
	# every intercepted hit is a normal hit.
	var ow_gs = ork11e_grot_shields_intercept(shooter_unit_id, target_unit, 0, hits, 0, {"value": 0, "is_dice": false}, false, board, rng)
	if ow_gs.active and ow_gs.intercepted > 0:
		hits = ow_gs.regular_hits
		result.diffs.append_array(ow_gs.diffs)
		result.dice.append({"context": "grot_shields", "message": ow_gs.log_text,
			"intercepted": ow_gs.intercepted, "gretchin_unit_id": ow_gs.gretchin_unit_id,
			"target_unit_id": target_unit_id})

	result.hits = hits

	if hits == 0:
		result.log_text = "%s (Overwatch): %d attacks, 0 hits [%s] vs 6+" % [
			weapon_name, total_attacks,
			", ".join(hit_rolls.map(func(r): return str(r)))]
		return result

	# --- PHASE 3: Wound rolls (normal rules apply) ---
	var strength = weapon_profile.get("strength", 4)
	# WP-O6: Codex: Orks (11e) datasheet-ability strength modifiers (Overwatch)
	if int(ork6.get("strength", 0)) != 0:
		strength += int(ork6.get("strength", 0))
		print("RulesEngine: [WP-O6] (Overwatch) ranged strength +%d → S%d" % [int(ork6.get("strength", 0)), strength])
	strength += ork11e_det_strength_bonus(shooter_unit, weapon_id, board)  # Codex: Orks (11e) Powers of da Waaagh! [PSYCHIC] +S (WP-O34)
	var toughness = _get_attached_unit_toughness(target_unit, board)  # P2-90: Use bodyguard T for attached units
	# OA-44: DED GLOWY AMMO — -1T to enemy INFANTRY within 6" of Kaptin Badrukk (overwatch)
	var ded_glowy_penalty_ow = get_ded_glowy_ammo_toughness_penalty(target_unit, board)
	if ded_glowy_penalty_ow > 0:
		toughness = max(1, toughness - ded_glowy_penalty_ow)
		print("RulesEngine: DED GLOWY AMMO (Overwatch) — INFANTRY target T reduced by %d to T%d" % [ded_glowy_penalty_ow, toughness])
	var wound_threshold = _calculate_wound_threshold(strength, toughness)

	var critical_wound_threshold = get_critical_wound_threshold(weapon_id, target_unit, board)
	critical_wound_threshold = mini(critical_wound_threshold, int(ork11e_enh().anti_threshold(ork6, target_unit)))  # WP-O5 Supa-glowy Fing [ANTI-INFANTRY 4+] (overwatch)

	# ROLLING LOOT-HEAP (OA-6): Grant Anti-Vehicle 4+ from stratagem flag
	if shooter_unit.get("flags", {}).get("effect_rolling_loot_heap", false):
		if unit_has_keyword(target_unit, "VEHICLE"):
			critical_wound_threshold = mini(critical_wound_threshold, 4)
			print("RulesEngine: ROLLING LOOT-HEAP (overwatch) — Anti-Vehicle 4+ active (critical wound threshold %d+)" % critical_wound_threshold)

	# SPESHUL AMMO (Speedwaaagh!): non-Torrent ranged weapons gain
	# [ANTI-MONSTER 4+] and [ANTI-VEHICLE 4+].
	if shooter_unit.get("flags", {}).get("effect_speshul_ammo", false):
		var ow_sa_torrent = "torrent" in str(get_weapon_profile(weapon_id, board).get("special_rules", "")).to_lower()
		if not ow_sa_torrent and (unit_has_keyword(target_unit, "MONSTER") or unit_has_keyword(target_unit, "VEHICLE")):
			critical_wound_threshold = mini(critical_wound_threshold, 4)
			print("RulesEngine: SPESHUL AMMO (overwatch) — Anti-Monster/Vehicle 4+ active (critical wound threshold %d+)" % critical_wound_threshold)

	# HARDY BIONIKS (WP-O6, Painboss): -1 to wound for S > T attacks that target the unit (overwatch)
	var ow_wound_modifier = 0
	if ork11e_ab_wound_penalty(target_unit, strength, toughness):
		ow_wound_modifier = -1
		print("RulesEngine: HARDY BIONIKS (overwatch) — -1 to wound for attacks against %s (S %d > T %d)" % [target_unit_id, strength, toughness])
	# IMPERVIOUS / effect_minus_wound_s_gt_t: -1 to wound while S > T
	if ow_wound_modifier == 0 and get_s_gt_t_wound_penalty(target_unit, board, strength, toughness) == WoundModifier.MINUS_ONE:
		ow_wound_modifier = -1
		print("RulesEngine: S>T wound penalty (overwatch) — -1 to wound for attacks against %s (S %d > T %d)" % [target_unit_id, strength, toughness])
	# DEFENDER FLAG ('ARD AS NAILS): -1 to wound for attacks targeting the flagged unit
	if EffectPrimitivesData.has_effect_minus_one_wound_defense(target_unit):
		ow_wound_modifier = -1
		print("RulesEngine: Defender effect -1 to wound (overwatch attacks vs %s)" % target_unit_id)
	# HULKING BRUTES (Codex: Orks 11e): -1 to wound for ranged attacks that target the unit.
	if ork11e_ranged_wound_penalty(target_unit, strength, toughness):
		ow_wound_modifier = -1
		print("RulesEngine: HULKING BRUTES (overwatch) — -1 to wound for attacks against %s" % target_unit_id)
	# Codex: Adeptus Custodes (11e) ±1 to wound — Gilded Guardians, Bane of Abominations, ... (WP-C46).
	if GameConstants.edition >= 11:
		var cus11e_ow_net := 0
		for c in cus11e_det().wound_effects(shooter_unit, target_unit, false, strength, toughness, board):
			if str(c.kind) == "plus_one":
				cus11e_ow_net += 1
			elif str(c.kind) == "minus_one":
				cus11e_ow_net -= 1
			print("RulesEngine: [cus11e] %s (overwatch) — %s to wound" % [str(c.source), str(c.kind)])
		ow_wound_modifier = clampi(ow_wound_modifier + cus11e_ow_net, -1, 1)
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
	# WP-O6: Codex: Orks (11e) datasheet-ability AP (Pulsa Rokkit, Finderz Keeperz) (Overwatch)
	if int(ork6.get("ap", 0)) > 0:
		var pre_ap_o6 = ap
		ap = improve_ap(ap, int(ork6.get("ap", 0)))
		print("RulesEngine: [WP-O6] (Overwatch) AP %d → %d" % [pre_ap_o6, ap])
	# IMPROVE AP: effect-granted AP improvement (Umbral Prosecution ranged AP +1 etc.)
	var ow_improve_ap = EffectPrimitivesData.get_effect_improve_ap_scoped(shooter_unit, "ranged")
	if ow_improve_ap > 0:
		var pre_ap_imp = ap
		ap = improve_ap(ap, ow_improve_ap)
		print("RulesEngine: Improve AP (Overwatch) — AP %d → %d (improve by %d)" % [pre_ap_imp, ap, ow_improve_ap])
	# SPESHUL SHELLS (More Dakka!): +1 AP vs targets within 18"
	var ow_ss_bonus = get_speshul_shells_ap_bonus(shooter_unit, target_unit)
	if ow_ss_bonus > 0:
		ap = improve_ap(ap, ow_ss_bonus)
		print("RulesEngine: SPESHUL SHELLS (Overwatch) — AP improved by %d (target within 18\")" % ow_ss_bonus)
	# PREY (Da Big Hunt): +1 AP for BEAST SNAGGA attacks against the attacker's Prey
	var ow_prey_bonus = get_prey_ap_bonus(shooter_unit, target_unit)
	if ow_prey_bonus > 0:
		ap = improve_ap(ap, ow_prey_bonus)
		print("RulesEngine: PREY (Overwatch) — AP improved by %d (target is Prey)" % ow_prey_bonus)	# WORSEN AP: Ramshackle etc. — reduce AP of incoming attacks (min 0)
	# Codex: Adeptus Custodes stratagems (CustodesCodex11e.gd): PSY-CHAFF VOLLEY +1 AP vs a prosecuted unit, IN AURAMITE CLAD -1 AP.
	ap = _cus11e_codex().modify_ap(ap, shooter_unit, target_unit)
	# Codex: Space Marines (11e) stratagems (SMCodex11e.gd): ARMOUR OF CONTEMPT -1 AP to attacks that target the unit.
	ap = _sm11e_codex().modify_ap(ap, shooter_unit, target_unit)
	var ow_worsen_ap = EffectPrimitivesData.get_effect_worsen_ap(target_unit)
	if ow_worsen_ap > 0 and ap != 0:
		var pre_ap = ap
		ap = worsen_ap(ap, ow_worsen_ap)
		print("RulesEngine: Worsen AP (Overwatch) — AP %d → %d (worsen by %d)" % [pre_ap, ap, ow_worsen_ap])
	var damage_raw = weapon_profile.get("damage_raw", str(weapon_profile.get("damage", 1)))
	damage_raw = cus11e_damage_raw_plus(str(damage_raw), int(load("res://scripts/codex/space_marines/SMDetachmentsB.gd").ranged_damage_bonus(shooter_unit, weapon_profile)))  # WP-M2b Master-forged Firearms +1 D (Codex: Space Marines 11e)
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
			# Fresh model: honour the defender's die-first order (AI/auto)
			# instead of always soaking on the lowest-index base.
			var ow_pick = _find_allocation_target_model(models, CasualtyPreference.engine_auto_preference(target_unit, board))
			if ow_pick >= 0:
				target_model = models[ow_pick]
				target_model_index = ow_pick
				allocation_focus_model_id = models[ow_pick].get("id", "m%d" % ow_pick)

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
		effect_invuln = cus11e_invuln(target_unit, false, effect_invuln, board)  # Codex: Adeptus Custodes (11e) Flare Shields / Eagle's Eye (WP-C46)
		if effect_invuln > 0:
			if model_invuln == 0 or effect_invuln < model_invuln:
				model_invuln = effect_invuln

		var save_result = _calculate_save_needed(ow_model_base_save, ap, has_cover, model_invuln, target_unit)

		# T4-18: Read save roll modifier from target unit flags (capped at +1/-1 per 10e)
		var ow_save_modifier = int(target_unit.get("flags", {}).get("save_modifier", 0)) + int(_sm11e_abilities_b().save_roll_bonus(target_unit))  # WP-M4b: Unyielding in the Face of the Foe (+1 to save rolls)
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
			# WP-C7: Codex: Adeptus Custodes (11e) Praesidium Shield — -1 D for the attack allocated to the Shield-Captain.
			var ow_ps: Dictionary = CustodesAbilities11eScript.allocated_damage(dmg, target_unit, target_model, ow_minus_dmg)
			if str(ow_ps.get("note", "")) != "":
				dmg = int(ow_ps.damage)
				result.dice.append({"context": "damage_modifier", "source": "Praesidium Shield", "message": str(ow_ps.note)})
			var ow_ry: Dictionary = _sm11e_abilities_b().allocated_damage(dmg, target_unit, target_model, ow_minus_dmg)  # WP-M4b: Refuse to Yield (-1 D)
			if str(ow_ry.get("note", "")) != "":
				dmg = int(ow_ry.damage)
				result.dice.append({"context": "damage_modifier", "source": "Refuse to Yield", "message": str(ow_ry.note)})

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

# The hit-roll target a player should read: bs_per_attack carries the
# EFFECTIVE per-attack BS after 11e characteristic modifiers (benefit of
# cover 13.08 worsens it, plunging fire 22.05 improves it) — the batch `bs`
# does not, so labelling with str(bs) shows "2+" while the dice were judged
# against 3+. When per-model views disagree the majority target is shown
# with a "mixed" note. The suffix must stay digit-free: consumers parse the
# number back out with String.to_int(), which concatenates EVERY digit in
# the string ("2+/3+" would read back as 23).
static func _hit_threshold_display(base_bs: int, bs_per_attack: Array, cover_worsened_attacks: int = 0, fail_band: int = 1, fail_band_note: String = "indirect") -> String:
	var shown := base_bs
	var mixed := false
	if not bs_per_attack.is_empty():
		var counts := {}
		for v in bs_per_attack:
			counts[int(v)] = int(counts.get(int(v), 0)) + 1
		shown = int(bs_per_attack[0])
		for t in counts:
			if counts[t] > counts.get(shown, 0) or (counts[t] == counts.get(shown, 0) and t > shown):
				shown = t
		mixed = counts.size() > 1
	# An unmodified 1 always fails — a modifier-improved "1+" still reads 2+.
	shown = maxi(shown, 2)
	var notes: Array = []
	# 10.07 indirect shooting: an unmodified 1-5 (or 1-3) fails whatever the
	# BS — show the roll the die actually needed, so a 5 is not drawn as a hit.
	if fail_band > 1 and fail_band + 1 > shown:
		shown = fail_band + 1
		notes.append(fail_band_note)
	if cover_worsened_attacks > 0:
		notes.append("cover")
	if mixed:
		notes.append("mixed")
	var s := "%d+" % shown
	if not notes.is_empty():
		s += " (%s)" % ", ".join(notes)
	return s

# Resolve assignment up to wound stage (stops before saves)
# SUSTAINED HITS (PRP-011): This function is modified to handle Sustained Hits
# BLAST (PRP-013): This function is modified to handle Blast keyword
static func _resolve_assignment_until_wounds(assignment: Dictionary, actor_unit_id: String, board: Dictionary, rng: RNGService) -> Dictionary:
	# Composed from the hit half + wound half so the staged (interactive
	# re-roll) path can pause between them. Behaviour is identical to the
	# original monolith (golden/replay tests guard the RNG order).
	var h = _resolve_assignment_hits(assignment, actor_unit_id, board, rng)
	var result = {"dice": (h.get("dice", []) as Array).duplicate(), "log_text": h.get("log_text", "")}
	if h.get("no_hits", false):
		return result
	var w = _resolve_assignment_wounds(h["hit_context"], board, rng)
	for wb in w.get("dice", []):
		result.dice.append(wb)
	result.log_text = w.get("log_text", result.log_text)
	if w.has("save_data"):
		result["save_data"] = w["save_data"]
	if w.has("grot_shields_diffs"):
		result["grot_shields_diffs"] = w["grot_shields_diffs"]
	return result

static func _resolve_assignment_hits(assignment: Dictionary, actor_unit_id: String, board: Dictionary, rng: RNGService) -> Dictionary:
	var hit_fail_band := 1
	# AIR-3: every early return below (target gone, unknown weapon, SPLIT-FIRE
	# dropped every model) is a "no hits" result. Callers branch on no_hits and
	# otherwise index hit_context — without these defaults
	# _resolve_assignment_until_wounds raised "Invalid access to property or
	# key 'hit_context'" and the assignment was lost mid-resolution.
	var result = {
		"dice": [],
		"log_text": "",
		"no_hits": true,
		"hit_context": {}
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

	# Calculate total attacks — roll variable attacks per model (D3, D6, etc.)
	var attacks_raw = weapon_profile.get("attacks_raw", str(weapon_profile.get("attacks", 1)))

	var weapon_name = weapon_profile.get("name", weapon_id)

	# WP-O6: Codex: Orks (11e) datasheet abilities for this batch (hit context carries it on).
	var ork6: Dictionary = ork11e_ab_mods(actor_unit, target_unit, weapon_profile, false, board, model_ids)

	var base_attacks = 0
	var attacks_roll_log = []
	# MA-10: Track per-model BS for each attack (supports stats_override.ballistic_skill)
	var bs_per_attack = []
	var cover_model_per_attack = []  # audit #7: firing model per attack (13.08 per-model cover)
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
	# SYNCHRONISED INFERNO (Silent Hunters): ranged weapons gain BLAST vs any target
	if not deck_fraggers_blast and EffectPrimitivesData.has_effect_grant_blast(actor_unit):
		var wp_type_gb = weapon_profile.get("type", "")
		if wp_type_gb.to_lower() == "ranged" or weapon_profile.get("range", 0) > 0:
			if not is_blast_weapon(weapon_id, board):
				deck_fraggers_blast = true
				print("RulesEngine: Effect-granted BLAST applied to %s" % weapon_id)

	# DRIVE-BY BUSTIN' (Codex: Orks 11e): per-attack record of whether the
	# attack is made with a weapon selected for the Firing Deck ability.
	var ork11e_fd_attack: Array = []
	for model_id in model_ids:
		# ATTACHED CHARACTERS: model_ids can carry composite "<char_unit>:<model>"
		# bearers. Resolve BOTH the model and the unit its stat overrides live on
		# — reading a character's model_type out of the bodyguard unit's
		# model_profiles silently misses and falls back to the weapon's base BS.
		var model = resolve_bearer_model(actor_unit, model_id, board)
		var model_bs = _get_model_effective_bs(model, resolve_bearer_unit(actor_unit, model_id, board), weapon_profile)
		if model_bs != weapon_profile.get("bs", 4):
			has_bs_override = true

		# Roll variable attacks for each model separately (per 10e rules)
		var attacks_result = roll_variable_characteristic(attacks_raw, rng)
		var model_attacks = attacks_result.value

		# WP-O6 (Blitz Dem Gitz!, ...): +A per attacking model
		model_attacks += int(ork6.get("attacks", 0))

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
		# Audit #7: and its identity, for per-attack 13.08 cover.
		for _j in range(model_attacks):
			bs_per_attack.append(model_bs)
			cover_model_per_attack.append(model)
			ork11e_fd_attack.append(ork11e_is_firing_deck_bearer(model_id))
		if attacks_result.rolled:
			attacks_roll_log.append(attacks_result)

	if int(ork6.get("attacks", 0)) > 0:
		print("RulesEngine: [WP-O6] +%d attack(s) per model from Codex: Orks (11e) datasheet abilities (%d models, total base attacks = %d)" % [int(ork6.get("attacks", 0)), model_ids.size(), base_attacks])

	if has_bs_override:
		print("RulesEngine: [MA-10] Per-model BS override active — models have different BS values")

	if attacks_roll_log.size() > 0:
		print("RulesEngine: Variable attacks rolled (%s) for %d models → %d total base attacks" % [attacks_raw, model_ids.size(), base_attacks])

	# RAPID FIRE KEYWORD: Check if weapon is Rapid Fire and models are in half range
	# MA-10: Track rapid fire attacks with per-model BS
	# MA-14: Only models in this assignment's model_ids count for RF (per-model weapons)
	var rapid_fire_value = get_rapid_fire_value(weapon_id, board)
	# UMBRAL PROSECUTION (Silent Hunters): ranged weapons gain [RAPID FIRE X]
	# for the phase — use the granted value when it beats the native one.
	var granted_rapid_fire = EffectPrimitivesData.get_effect_grant_rapid_fire(actor_unit)
	if granted_rapid_fire > rapid_fire_value:
		rapid_fire_value = granted_rapid_fire
		print("RulesEngine: Effect-granted RAPID FIRE %d applied to %s" % [granted_rapid_fire, weapon_id])
	# DAKKAMEK (Speedwaaagh!): the Mekaniak-selected Vehicle's ranged weapons gain
	# [RAPID FIRE 1] until the start of the bearer's next turn.
	if rapid_fire_value < 1 and str(weapon_profile.get("type", "Ranged")).to_lower() != "melee" \
			and (actor_unit.get("flags", {}).get("dakkamek_rapid_fire", false) or actor_unit.get("flags", {}).get("effect_grant_rapid_fire_1", false)):
		rapid_fire_value = 1
		print("RulesEngine: DAKKAMEK — [RAPID FIRE 1] granted to %s's ranged weapon %s" % [actor_unit_id, weapon_id])
	# BRUTAL BROADSIDE (Rollin' Deff): ranged weapons gain [RAPID FIRE X] with
	# X = the weapon's Attacks characteristic (fixed-value Attacks only —
	# dice-valued Attacks keep their native rapid fire; documented).
	if str(weapon_profile.get("type", "Ranged")).to_lower() != "melee" \
			and actor_unit.get("flags", {}).get("effect_brutal_broadside", false):
		var bb_attacks_raw = str(weapon_profile.get("attacks", "1"))
		if bb_attacks_raw.is_valid_int():
			rapid_fire_value = maxi(rapid_fire_value, int(bb_attacks_raw))
			print("RulesEngine: BRUTAL BROADSIDE — [RAPID FIRE %d] on %s (X = Attacks)" % [rapid_fire_value, weapon_id])
		else:
			print("RulesEngine: BRUTAL BROADSIDE — %s has dice-valued Attacks (%s), rapid fire grant skipped" % [weapon_id, bb_attacks_raw])
	# CLOSE-RANGE DAKKA (Codex: Orks 11e): [RAPID FIRE 1], or +1 to the value of
	# an existing [RAPID FIRE] (applied after every other RAPID FIRE grant).
	# WP-O5 Supa-snazz Dakka: Snazzguns have [RAPID FIRE 1] (not cumulative with their own).
	rapid_fire_value = maxi(rapid_fire_value, int(ork11e_enh().rapid_fire_grant(actor_unit, weapon_profile)))
	var ork11e_crd_bonus = ork11e_rapid_fire_bonus(actor_unit, weapon_profile)
	if ork11e_crd_bonus > 0:
		rapid_fire_value += ork11e_crd_bonus
		print("RulesEngine: CLOSE-RANGE DAKKA — %s now [RAPID FIRE %d]" % [weapon_id, rapid_fire_value])
	var rapid_fire_attacks = 0
	var models_in_half_range = 0
	if rapid_fire_value > 0:
		var weapon_range = weapon_profile.get("range", 24) + ork11e_det_range_bonus(actor_unit, weapon_profile)  # Codex: Orks (11e) Dakka! Dakka! Dakka! +3" Range while riled up (WP-O34)
		var half_range_inches = weapon_range if load("res://scripts/codex/space_marines/SMDetachmentsB.gd").full_range_rapid_fire(actor_unit) else weapon_range / 2.0  # WP-M2b Codex Fire-patterns: [RAPID FIRE] up to maximum range
		for model_id in model_ids:
			# ATTACHED CHARACTERS: a composite "<char_unit>:<model>" bearer is not
			# in actor_unit.models, so _get_model_by_id returned {} and the model
			# was skipped — a character's gun could never count as within half
			# range, silently losing its RAPID FIRE bonus attacks.
			var rf_model = resolve_bearer_model(actor_unit, model_id, board)
			if rf_model.is_empty() or not rf_model.get("alive", true):
				continue
			var closest_distance_inches = INF
			# Half range is measured to the whole TARGET unit — for an
			# Attached unit that includes its leaders (19.03), not only the
			# bodyguard models (r1:WH-3).
			for target_model in attached_unit_models(target_unit_id, board):
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
					ork11e_fd_attack.append(ork11e_is_firing_deck_bearer(model_id))
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
	var ork11e_fd_blast: int = blast_bonus_per_model * model_ids.filter(func(m): return ork11e_is_firing_deck_bearer(m)).size()
	for _j in range(blast_bonus_attacks):
		bs_per_attack.append(default_bs)
		ork11e_fd_attack.append(_j < ork11e_fd_blast)

	var total_attacks = base_attacks + rapid_fire_attacks + blast_bonus_attacks
	if assignment.has("attacks_override") and assignment.attacks_override != null:
		total_attacks = assignment.attacks_override
		rapid_fire_attacks = 0  # Override disables the rapid fire bonus tracking
		blast_bonus_attacks = 0  # Override disables the blast bonus tracking
		# MA-10: Rebuild bs_per_attack with default BS when attacks are overridden
		bs_per_attack.clear()
		ork11e_fd_attack.clear()
		for _j in range(total_attacks):
			bs_per_attack.append(default_bs)
			ork11e_fd_attack.append(not model_ids.is_empty() and model_ids.all(func(m): return ork11e_is_firing_deck_bearer(m)))

	# MA-29: ABILITY ATTACK BONUS — Check for weapon-targeted +X Attacks from abilities
	var ability_attack_bonus = 0
	if EffectPrimitivesData.has_effect_plus_attacks(actor_unit):
		var bonus_value = EffectPrimitivesData.get_effect_plus_attacks(actor_unit)
		if EffectPrimitivesData.effect_applies_to_weapon(actor_unit, EffectPrimitivesData.FLAG_PLUS_ATTACKS, weapon_name):
			ability_attack_bonus = bonus_value * model_ids.size()  # Per-model bonus
			total_attacks += ability_attack_bonus
			# Add BS entries for the bonus attacks (use per-model BS)
			for ab_model_id in model_ids:
				var bonus_model = resolve_bearer_model(actor_unit, ab_model_id, board)
				var bonus_bs = _get_model_effective_bs(bonus_model, resolve_bearer_unit(actor_unit, ab_model_id, board), weapon_profile)
				for _j in range(bonus_value):
					bs_per_attack.append(bonus_bs)
					ork11e_fd_attack.append(ork11e_is_firing_deck_bearer(ab_model_id))
			print("RulesEngine: [MA-29] Ability +%d Attacks for '%s' → +%d total (%d models × %d)" % [bonus_value, weapon_name, ability_attack_bonus, model_ids.size(), bonus_value])
		else:
			print("RulesEngine: [MA-29] Ability +%d Attacks exists but does not apply to '%s' (weapon filter active)" % [bonus_value, weapon_name])
	# Codex: Orks (11e) Try Dat Button! +1 A per model (WP-O34).
	var ork11e_a := ork11e_det_attacks_per_model(actor_unit)
	if ork11e_a > 0:
		for tdb_model_id in model_ids:
			var tdb_model = resolve_bearer_model(actor_unit, tdb_model_id, board)
			var tdb_bs = _get_model_effective_bs(tdb_model, resolve_bearer_unit(actor_unit, tdb_model_id, board), weapon_profile)
			for _j in range(ork11e_a):
				bs_per_attack.append(tdb_bs)
				ork11e_fd_attack.append(ork11e_is_firing_deck_bearer(tdb_model_id))
		total_attacks += ork11e_a * model_ids.size()
		print("RulesEngine: TRY DAT BUTTON! — +%d attack per model on %s (%d models)" % [ork11e_a, weapon_name, model_ids.size()])
	# Codex: Adeptus Custodes (11e) Not a Shell Wasted: the bearer's unit's ranged attacks +1 A (WP-C46).
	var cus11e_nsw := cus11e_ranged_attacks_per_model(actor_unit, board)
	if cus11e_nsw > 0:
		for nsw_model_id in model_ids:
			var nsw_model = resolve_bearer_model(actor_unit, nsw_model_id, board)
			var nsw_bs = _get_model_effective_bs(nsw_model, resolve_bearer_unit(actor_unit, nsw_model_id, board), weapon_profile)
			for _j in range(cus11e_nsw):
				bs_per_attack.append(nsw_bs)
				ork11e_fd_attack.append(ork11e_is_firing_deck_bearer(nsw_model_id))
		total_attacks += cus11e_nsw * model_ids.size()
		print("RulesEngine: NOT A SHELL WASTED — +%d attack per model on %s (%d models)" % [cus11e_nsw, weapon_name, model_ids.size()])

	# TORRENT KEYWORD (PRP-014): Check if weapon auto-hits (skip hit roll entirely)
	var is_torrent = is_torrent_weapon(weapon_id, board) or assignment.get("torrent", false) or bool(ork6.get("torrent", false))  # WP-O5 Temperamental Shokka (1: [TORRENT])

	# Codex: Adeptus Custodes stratagems (CustodesCodex11e.gd): PURGATION SWEEP +1/+2 A on [TORRENT] weapons.
	var cus11e_bonus_a: int = int(_cus11e_codex().bonus_attacks_per_model(actor_unit, target_unit, weapon_profile, is_torrent, false)) * model_ids.size()
	if cus11e_bonus_a > 0 and not (assignment.has("attacks_override") and assignment.attacks_override != null):
		total_attacks += cus11e_bonus_a
		for _j in range(cus11e_bonus_a):
			bs_per_attack.append(weapon_profile.get("bs", 4))
			ork11e_fd_attack.append(false)
		print("RulesEngine: PURGATION SWEEP — +%d attack(s) for [TORRENT] weapon '%s' (%d models)" % [cus11e_bonus_a, weapon_name, model_ids.size()])

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
		critical_hit_threshold = _snap_critical_hit_threshold_11e(critical_hit_threshold)
		# WP-M4a SENTINEL PROTOCOLS (Firestrike Servo-turrets): this unit's snap-shooting attacks hit on unmodified 4+.
		if SMAbilitiesAScript.snap_hit_threshold(actor_unit) > 0:
			bs = SMAbilitiesAScript.snap_hit_threshold(actor_unit)
			for sm_i in range(bs_per_attack.size()):
				bs_per_attack[sm_i] = bs
			print("RulesEngine: [WP-M4a] Sentinel Protocols — snap shooting hits on unmodified %d+" % bs)

	var cover_worsened_attacks = 0  # 13.08 — attacks whose BS the benefit of cover worsened
	var hit_threshold_display = str(bs) + "+"  # rebuilt from the effective per-attack BS before display
	var hits = 0
	var critical_hits = 0  # Unmodified rolls >= critical_hit_threshold (never for Torrent)
	var regular_hits = 0   # Non-critical hits
	# ISS-modifier-provenance: names WHERE each modifier below came from, so the
	# Dice Log and the resolution docks can say "Against All Odds: +1 to hit"
	# instead of an anonymous "+1". Purely additive — never read by the maths.
	var hit_modifiers = HitModifier.NONE
	var hit_mod_ledger: Array = []
	var heavy_bonus_applied = false
	var bgnt_penalty_applied = false
	var indirect_fire_applied = false
	var indirect_consequences: bool = false  # 11e 10.07 — set in the hit branch below
	var hit_rolls = []
	var modified_rolls = []
	var reroll_data = []
	# Per-die classification (raw/final/is_hit/is_crit), captured so a single-die
	# Command Re-roll (staged shooting) can recompute totals without re-rolling
	# the untouched dice. Empty for Torrent (no hit roll).
	var hit_evals = []
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
		weapon_has_lethal_hits = has_lethal_hits(weapon_id, board, target_unit)
		sustained_data = get_sustained_hits_value(weapon_id, board, target_unit)

		result.dice.append({
			"context": "auto_hit",  # Special context for Torrent
			"torrent_weapon": true,
			"total_attacks": total_attacks,
			"successes": hits,
			"target_unit_id": target_unit_id,  # enemy_has_shot window: which units were hit
			"weapon_id": weapon_id,  # WP-M4b Suppression Fire: hits per weapon
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
				ModifierLedger.note(hit_mod_ledger, "Attack assignment", ModifierLedger.KIND_HIT, ModifierLedger.REROLL_ONES)
			if hit_mods.get("reroll_failed", false):
				hit_modifiers |= HitModifier.REROLL_FAILED
				ModifierLedger.note(hit_mod_ledger, "Attack assignment", ModifierLedger.KIND_HIT, ModifierLedger.REROLL_FAILED)
			if hit_mods.get("plus_one", false):
				hit_modifiers |= HitModifier.PLUS_ONE
				ModifierLedger.note(hit_mod_ledger, "Attack assignment", ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE)
			if hit_mods.get("minus_one", false):
				hit_modifiers |= HitModifier.MINUS_ONE
				ModifierLedger.note(hit_mod_ledger, "Attack assignment", ModifierLedger.KIND_HIT, ModifierLedger.MINUS_ONE)

		# EFFECT FLAGS: Check for ability/stratagem-granted hit modifiers on the attacker
		if EffectPrimitivesData.has_effect_plus_one_hit(actor_unit):
			hit_modifiers |= HitModifier.PLUS_ONE
			ModifierLedger.note(hit_mod_ledger, "Ability effect", ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE, "granted by an ability or Stratagem")
			print("RulesEngine: Effect +1 to hit applied for %s" % actor_unit_id)
		if EffectPrimitivesData.has_effect_minus_one_hit(actor_unit):
			hit_modifiers |= HitModifier.MINUS_ONE
			ModifierLedger.note(hit_mod_ledger, "Ability effect", ModifierLedger.KIND_HIT, ModifierLedger.MINUS_ONE, "imposed by an ability or Stratagem")
			print("RulesEngine: Effect -1 to hit applied for %s" % actor_unit_id)
		var reroll_hits_scope = actor_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_REROLL_HITS, "")
		if reroll_hits_scope == "ones":
			hit_modifiers |= HitModifier.REROLL_ONES
			ModifierLedger.note(hit_mod_ledger, "Ability effect", ModifierLedger.KIND_HIT, ModifierLedger.REROLL_ONES, "granted by an ability or Stratagem")
			print("RulesEngine: Effect re-roll 1s to hit applied for %s" % actor_unit_id)
		elif reroll_hits_scope == "failed":
			hit_modifiers |= HitModifier.REROLL_FAILED
			ModifierLedger.note(hit_mod_ledger, "Ability effect", ModifierLedger.KIND_HIT, ModifierLedger.REROLL_FAILED, "granted by an ability or Stratagem")
			print("RulesEngine: Effect re-roll failed hits applied for %s" % actor_unit_id)
		elif reroll_hits_scope == "all":
			hit_modifiers |= HitModifier.REROLL_FAILED
			ModifierLedger.note(hit_mod_ledger, "Ability effect", ModifierLedger.KIND_HIT, ModifierLedger.REROLL_FAILED, "re-roll all hit rolls")
			print("RulesEngine: Effect re-roll all hits applied for %s" % actor_unit_id)
		elif reroll_hits_scope == REROLL_HITS_SCOPE_NON_CRIT:
			hit_modifiers |= _non_crit_hit_reroll_bits(actor_unit, weapon_id, board, false)
			ModifierLedger.note(hit_mod_ledger, "Ability effect", ModifierLedger.KIND_HIT, ModifierLedger.REROLL_FAILED, "re-roll hit rolls (non-critical hits too, for critical-hit weapons)")
			print("RulesEngine: Effect re-roll hit rolls (fishing for crits where they matter) applied for %s / %s" % [actor_unit_id, weapon_id])

		# DAMAGED PROFILE (P1-14): Check if attacker has Damaged profile active
		if is_damaged_profile_active(actor_unit):
			hit_modifiers |= HitModifier.MINUS_ONE
			ModifierLedger.note(hit_mod_ledger, "Damaged profile", ModifierLedger.KIND_HIT, ModifierLedger.MINUS_ONE, "attacker is on its Damaged profile")
			print("RulesEngine: Damaged profile -1 to hit applied for %s" % actor_unit_id)

		# HEAVY KEYWORD: Check if weapon is Heavy and unit remained stationary
		# (at edition>=11 [HEAVY] routes through ModifierStack below — 24.16)
		if GameConstants.edition < 11 and is_heavy_weapon(weapon_id, board):
			var remained_stationary = actor_unit.get("flags", {}).get("remained_stationary", false)
			if remained_stationary:
				hit_modifiers |= HitModifier.PLUS_ONE
				ModifierLedger.note(hit_mod_ledger, "[HEAVY]", ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE, "unit remained stationary")
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
				ModifierLedger.note(hit_mod_ledger, "Big Guns Never Tire", ModifierLedger.KIND_HIT, ModifierLedger.MINUS_ONE, "shooting while engaged")
				bgnt_penalty_applied = true
				print("RulesEngine: BGNT -1 to hit applied for %s (weapon %s)" % [actor_unit_id, weapon_id])

		# STEALTH (T2-1): Check if target unit has Stealth (from effect or base ability)
		# Stealth imposes -1 to hit rolls against this unit for ranged attacks
		if GameConstants.edition < 11 and EffectPrimitivesData.has_effect_stealth(target_unit):
			hit_modifiers |= HitModifier.MINUS_ONE
			ModifierLedger.note(hit_mod_ledger, "Stealth", ModifierLedger.KIND_HIT, ModifierLedger.MINUS_ONE, "target has Stealth (granted)")
			print("RulesEngine: Stealth (effect-granted) applied -1 to hit against %s" % target_unit_id)
		elif GameConstants.edition < 11 and has_stealth_ability(target_unit):
			hit_modifiers |= HitModifier.MINUS_ONE
			ModifierLedger.note(hit_mod_ledger, "Stealth", ModifierLedger.KIND_HIT, ModifierLedger.MINUS_ONE, "target has the Stealth ability")
			print("RulesEngine: Stealth (ability) applied -1 to hit against %s" % target_unit_id)

		# INDIRECT FIRE (T2-4): Apply -1 to hit modifier for Indirect Fire weapons
		# Issue #371: per 10e RAW, the -1 penalty + Benefit of Cover only apply
		# when the target is NOT visible to any model in the firing unit.
		var indirect_target_visible = is_indirect_fire and _has_los_to_target_unit(actor_unit_id, target_unit_id, board)
		# 11e (10.07): the WHILE SHOOTING consequences (cover, no hit re-rolls,
		# the 1-5 / 1-3 fail band) follow the shooting type the player SELECTED
		# for the unit, not whether the target happens to be visible. Callers
		# stamp it on the assignment (_stamp_shooting_type); without it (legacy
		# callers) fall back to "unseen target ⇒ indirect" — the only legal way
		# to shoot an unseen target.
		indirect_consequences = _indirect_consequences_apply(is_indirect_fire, indirect_target_visible, assignment)
		# 11e (10.07): the indirect penalty is a harsh UNMODIFIED fail band (see
		# hit_fail_band below), not a -1 modifier — gate the 10e -1 off at e11.
		if is_indirect_fire and not indirect_target_visible and GameConstants.edition < 11:
			hit_modifiers |= HitModifier.MINUS_ONE
			ModifierLedger.note(hit_mod_ledger, "[INDIRECT FIRE]", ModifierLedger.KIND_HIT, ModifierLedger.MINUS_ONE, "target is not visible")
			indirect_fire_applied = true
			print("RulesEngine: [INDIRECT FIRE] Applied -1 to hit for weapon '%s' (target not visible)" % weapon_profile.get("name", weapon_id))
		elif is_indirect_fire and indirect_target_visible:
			print("RulesEngine: [INDIRECT FIRE] No penalty — target IS visible to firing unit")

		# TANK HUNTERS (OA-11): +1 to Hit when attacking MONSTER or VEHICLE targets
		if has_tank_hunters_vs_target(actor_unit, target_unit):
			hit_modifiers |= HitModifier.PLUS_ONE
			ModifierLedger.note(hit_mod_ledger, "Tank Hunters", ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE, "target is a MONSTER or VEHICLE")
			print("RulesEngine: TANK HUNTERS — +1 to hit for %s (target is MONSTER/VEHICLE)" % actor_unit_id)

		# WALL OF DAKKA (OA-50): +1 to Hit on ranged attacks vs targets within half weapon range (Bonebreaka)
		var wall_of_dakka_bonus = get_wall_of_dakka_hit_bonus(actor_unit, target_unit, weapon_profile)
		if wall_of_dakka_bonus > 0:
			hit_modifiers |= HitModifier.PLUS_ONE
			ModifierLedger.note(hit_mod_ledger, "Wall of Dakka", ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE, "target within half range")
			print("RulesEngine: WALL OF DAKKA — +1 to hit for %s (target within half range)" % actor_unit_id)

		# TARGETIN' SQUIGS / HUGE SHOW-OFFS: effect-granted +1 to hit on ranged attacks
		if actor_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_PLUS_ONE_HIT_RANGED, false):
			hit_modifiers |= HitModifier.PLUS_ONE
			ModifierLedger.note(hit_mod_ledger, "Ability effect", ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE, "+1 to hit on ranged attacks (Targetin' Squigs / Huge Show-offs)")
			print("RulesEngine: +1 to hit (ranged) — effect_plus_one_hit_ranged on %s" % actor_unit_id)
		# ARMOURED DUELLISTS (Blitz Brigade): +1 to hit vs MONSTER/VEHICLE
		if get_armoured_duellists_bonus(actor_unit, target_unit) > 0:
			hit_modifiers |= HitModifier.PLUS_ONE
			ModifierLedger.note(hit_mod_ledger, "Armoured Duellists", ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE, "target is a MONSTER or VEHICLE")
			print("RulesEngine: ARMOURED DUELLISTS — +1 to hit vs %s (MONSTER/VEHICLE)" % target_unit_id)
		# Codex: Orks (11e) detachment rules (WP-O34): +1 to hit (Skyborne Loons / Seekerz), re-roll 1s (Wreckin' and Lootin').
		var ork11e_hp_src := ork11e_det_hit_plus_one(actor_unit, target_unit, false, board)
		if ork11e_hp_src != "":
			hit_modifiers |= HitModifier.PLUS_ONE
			ModifierLedger.note(hit_mod_ledger, ork11e_hp_src, ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE)
		var ork11e_rr_src := ork11e_det_hit_reroll_ones(actor_unit, target_unit, false, board)
		if ork11e_rr_src != "":
			hit_modifiers |= HitModifier.REROLL_ONES
			ModifierLedger.note(hit_mod_ledger, ork11e_rr_src, ModifierLedger.KIND_HIT, ModifierLedger.REROLL_ONES)

		# LONG, UNCONTROLLED BURSTS (Codex: Orks 11e): ranged attacks that target a
		# FLY unit can re-roll the hit roll.
		if ork11e_long_uncontrolled_bursts_reroll(actor_unit, target_unit):
			hit_modifiers |= HitModifier.REROLL_FAILED
			ModifierLedger.note(hit_mod_ledger, "Long, Uncontrolled Bursts", ModifierLedger.KIND_HIT, ModifierLedger.REROLL_FAILED, "target has FLY")
			print("RulesEngine: LONG, UNCONTROLLED BURSTS — re-roll hit rolls vs FLY target %s" % target_unit_id)
		# DRIVE-BY BUSTIN' (Codex: Orks 11e): +1 to hit for weapons selected for the
		# Firing Deck ability — the whole batch when every attack is a Firing Deck
		# one, otherwise per attack in the hit roll loop below.
		if ork11e_drive_by_bustin_active(actor_unit) and not ork11e_fd_attack.is_empty() and not ork11e_fd_attack.has(false):
			hit_modifiers |= HitModifier.PLUS_ONE
			ModifierLedger.note(hit_mod_ledger, "Drive-by Bustin'", ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE, "weapon selected for the Firing Deck ability")
			print("RulesEngine: DRIVE-BY BUSTIN' — +1 to hit for Firing Deck weapon %s" % weapon_id)
		# DAT'S OUR LOOT! (OA-12): Re-roll Hit rolls of 1 on ranged attacks;
		# full Hit re-roll if target is within range of any objective marker.
		var dats_our_loot_scope = get_dats_our_loot_reroll_scope(actor_unit, target_unit, board)
		if dats_our_loot_scope == "failed":
			hit_modifiers |= HitModifier.REROLL_FAILED
			ModifierLedger.note(hit_mod_ledger, "Dat's Our Loot!", ModifierLedger.KIND_HIT, ModifierLedger.REROLL_FAILED, "target within range of an objective marker")
			print("RulesEngine: DAT'S OUR LOOT! — full hit re-roll for %s (target near objective)" % actor_unit_id)
		elif dats_our_loot_scope == "ones":
			hit_modifiers |= HitModifier.REROLL_ONES
			ModifierLedger.note(hit_mod_ledger, "Dat's Our Loot!", ModifierLedger.KIND_HIT, ModifierLedger.REROLL_ONES, "target within range of an objective marker")
			print("RulesEngine: DAT'S OUR LOOT! — re-roll hit rolls of 1 for %s" % actor_unit_id)

		# WP-O6: Codex: Orks (11e) datasheet abilities (Strafing Run, Dodge Dis!, Ammo Runts, ...)
		hit_modifiers = ork11e_ab_hit_bits(hit_modifiers, hit_mod_ledger, ork6)

		# XENOS HUNTER: +1 to Hit vs non-IMPERIUM/CHAOS targets (Inquisitor Draxus while leading)
		if has_xenos_hunter_vs_target(actor_unit, target_unit):
			hit_modifiers |= HitModifier.PLUS_ONE
			ModifierLedger.note(hit_mod_ledger, "Xenos Hunter", ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE, "target lacks IMPERIUM and CHAOS")
			print("RulesEngine: XENOS HUNTER — +1 to hit for %s (target lacks IMPERIUM/CHAOS)" % actor_unit_id)

		# Codex: Adeptus Custodes (11e) detachment rules / enhancements (CustodesDetachments.gd, WP-C46).
		hit_modifiers = cus11e_apply_hit_effects(hit_modifiers, hit_mod_ledger, actor_unit, target_unit, false, board, {"model_ids": model_ids})

		# ── ISS-016/053 (11e): hit-side modifier stack — cover/STEALTH worsen
		# BS (13.08/24.33), plunging fire improves it (22.05), [HEAVY] is +1
		# to the hit roll (24.16). The ±1 dice-roll cap lives in ModifierStack.
		if GameConstants.edition >= 11 and not is_overwatch:
			var ms_firing_models: Array = []
			for ms_mid in model_ids:
				# ATTACHED CHARACTERS: composite bearers resolved through the board.
				# Without this a character-only assignment produced an EMPTY
				# attacker_models list, so cover / STEALTH / plunging fire were
				# evaluated with no firing model to measure from.
				var ms_m = resolve_bearer_model(actor_unit, ms_mid, board)
				if not ms_m.is_empty() and ms_m.get("alive", true):
					ms_firing_models.append(ms_m)
			var ms_stack = ModifierStack.collect_hit_context_11e(actor_unit, target_unit, weapon_profile, board, {"attacker_models": ms_firing_models, "per_attack_cover": true})
			# Codex: Adeptus Custodes SALVUS (CustodesKatah.gd): the harmful BS /
			# hit-roll entries of the stack are ignored.
			var cus11e_salvus_ignored: Array = _cus11e_katah().salvus_filter_stack(actor_unit, ms_stack)
			# Codex: Adeptus Custodes stratagems (CustodesCodex11e.gd): INEVITABLE ANNIHILATION ignores the harmful BS / hit-roll entries.
			cus11e_salvus_ignored.append_array(_cus11e_codex().filter_hit_stack(actor_unit, ms_stack, false))
			# Codex: Space Marines (11e) stratagems (SMCodex11e.gd): MIGHT OF THE MACHINE SPIRIT ignores the harmful BS / hit-roll entries.
			cus11e_salvus_ignored.append_array(_sm11e_codex().filter_hit_stack(actor_unit, ms_stack, false))
			var ms_bs_delta = ms_stack.net("bs")
			var ms_hit_net_pre = ms_stack.net("hit_roll")
			# WP-O6 Walking Bastion ignores BS/hit modifiers like [PSYCHIC] does.
			var ms_is_psychic: bool = is_psychic_weapon(weapon_id, board) or bool(ork6.get("ignore_hit_penalties", false))
			# ISS-047 (24.29): [PSYCHIC] attacks may ignore any or all BS/hit
			# modifiers — the engine ignores exactly the harmful ones.
			if ms_is_psychic:
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
				ModifierLedger.note_stack(hit_mod_ledger, ms_stack.sources("bs"), ModifierLedger.KIND_HIT, ModifierLedger.WORSEN_BS if ms_bs_delta > 0 else ModifierLedger.IMPROVE_BS)
			# Audit #7 (13.08 per attacking model): each attack takes the
			# cover worsening based on ITS OWN firing model's view of the
			# target. Attacks with no recorded firing model (overrides,
			# bonus attacks) fall back to the first firing model's view.
			# (SALVUS / INEVITABLE ANNIHILATION ignore that BS worsening too; WP-O6 Codex: Orks [IGNORES COVER].)
			if not ms_is_psychic and not _cus11e_katah().salvus_active(actor_unit) and not _cus11e_codex().ignores_bs_worsening(actor_unit, false) and not _sm11e_codex().ignores_bs_worsening(actor_unit, false) and not ModifierStack.attack_ignores_cover(actor_unit, weapon_profile, {"ignores_cover": bool(ork6.get("ignores_cover", false))}):
				var pa_terrain = Engine.get_main_loop().root.get_node_or_null("TerrainManager")
				if pa_terrain != null:
					# WP-O6 Madcap Artillery: a wobbled unit's targets have the benefit of cover.
					var pa_strat_cover: bool = target_unit.get("flags", {}).get("stratagem_cover", false) or bool(ork6.get("target_cover", false))
					# 11e 10.07: an [INDIRECT FIRE] attack at an unseen target
					# has the benefit of cover per attack, regardless of terrain
					# — at 11e that worsens the attacker's BS here (13.08), not
					# the save.
					var pa_indirect_cover: bool = indirect_consequences
					var pa_fallback: Dictionary = ms_firing_models[0] if not ms_firing_models.is_empty() else {}
					var pa_cover_cache: Dictionary = {}
					var pa_covered_count := 0
					for ms_i in range(bs_per_attack.size()):
						var pa_model: Dictionary = cover_model_per_attack[ms_i] if ms_i < cover_model_per_attack.size() else pa_fallback
						var pa_key := str(pa_model.get("id", "_"))
						if not pa_cover_cache.has(pa_key):
							pa_cover_cache[pa_key] = pa_strat_cover or pa_indirect_cover or pa_terrain.unit_has_cover_11e(target_unit, pa_model)
						if pa_cover_cache[pa_key]:
							bs_per_attack[ms_i] += 1
							pa_covered_count += 1
					cover_worsened_attacks = pa_covered_count
					if pa_covered_count > 0:
						print("RulesEngine: [13.08 per-model] benefit of cover — %d/%d attack(s) worsened by 1 BS" % [pa_covered_count, bs_per_attack.size()])
			var ms_hit_net = ms_hit_net_pre
			if ms_hit_net > 0:
				hit_modifiers |= HitModifier.PLUS_ONE
				ModifierLedger.note_stack(hit_mod_ledger, ms_stack.sources("hit_roll"), ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE)
				if "heavy" in ms_stack.sources("hit_roll"):
					heavy_bonus_applied = true
				print("RulesEngine: [11e MODIFIERS] +1 to hit (%s)" % str(ms_stack.sources("hit_roll")))
			elif ms_hit_net < 0:
				hit_modifiers |= HitModifier.MINUS_ONE
				ModifierLedger.note_stack(hit_mod_ledger, ms_stack.sources("hit_roll"), ModifierLedger.KIND_HIT, ModifierLedger.MINUS_ONE)
				print("RulesEngine: [11e MODIFIERS] -1 to hit (%s)" % str(ms_stack.sources("hit_roll")))
			if _cus11e_katah().salvus_active(actor_unit):
				ModifierLedger.note(hit_mod_ledger, "Salvus (Ka'tah)", ModifierLedger.KIND_HIT, ModifierLedger.IGNORED,
					"BS worsening (incl. benefit of cover) and hit-roll penalties ignored%s" % ((": " + ", ".join(cus11e_salvus_ignored)) if not cus11e_salvus_ignored.is_empty() else ""))

		# Codex: Adeptus Custodes SALVUS (CustodesKatah.gd): ignore every -1 to
		# hit (the +1s are kept — "can ignore" is the attacker's choice).
		if _cus11e_katah().salvus_active(actor_unit) and (hit_modifiers & HitModifier.MINUS_ONE):
			hit_modifiers = hit_modifiers & ~HitModifier.MINUS_ONE
			ModifierLedger.note(hit_mod_ledger, "Salvus (Ka'tah)", ModifierLedger.KIND_HIT, ModifierLedger.IGNORED, "hit-roll penalties ignored")
			ModifierLedger.mark_ignored(hit_mod_ledger, ModifierLedger.KIND_HIT, [ModifierLedger.MINUS_ONE])
			print("RulesEngine: SALVUS — ignoring hit-roll penalties for %s" % actor_unit_id)
		# Codex: Adeptus Custodes stratagems (CustodesCodex11e.gd): GOLDEN LIGHT (-1), HONOURED INTERRED (re-roll 1s), INEVITABLE ANNIHILATION (ignore -1).
		hit_modifiers = _cus11e_codex().apply_hit_bits(hit_modifiers, actor_unit, target_unit, false, board, hit_mod_ledger)
		# Codex: Space Marines (11e) stratagems (SMCodex11e.gd): HURTLING TARGETS / UMBRAL EVASION (-1), MIGHT OF THE MACHINE SPIRIT (ignore -1).
		hit_modifiers = _sm11e_codex().apply_hit_bits(hit_modifiers, actor_unit, target_unit, false, hit_mod_ledger)

		# Roll to hit - CRITICAL HIT TRACKING (PRP-031)
		hit_rolls = rng.roll_d6(total_attacks)

		# ISS-012: per-roll evaluation shared with the melee path
		# (AttackSequence.evaluate_hit_roll). INDIRECT FIRE's unmodified-1-3
		# fail band (#371, unseen targets only) and CONVERSION's crit
		# threshold (T4-16) are parameters.
		hit_fail_band = 1
		if indirect_consequences:
			# 11e (10.07): unmodified 1-5 fails (need a 6), unless the firing unit
			# remained stationary AND the target is visible to a friendly unit, in
			# which case 1-3 fails (need 4+). 10e: 1-3 fails (4+).
			hit_fail_band = _indirect_hit_fail_band_11e(actor_unit_id, target_unit_id, board) if GameConstants.edition >= 11 else 3
			print("RulesEngine: [10.07] INDIRECT shooting — unmodified 1-%d fails (target visible to shooter: %s, type: %s)" % [hit_fail_band, str(indirect_target_visible), str(assignment.get("shooting_type", "inferred"))])
			# 11e (10.07): "You cannot re-roll hit rolls" for every attack an
			# [INDIRECT FIRE] weapon makes while the unit shoots indirect.
			if GameConstants.edition >= 11 and (hit_modifiers & (HitModifier.REROLL_ONES | HitModifier.REROLL_FAILED | HitModifier.REROLL_NON_CRIT)):
				hit_modifiers &= ~(HitModifier.REROLL_ONES | HitModifier.REROLL_FAILED | HitModifier.REROLL_NON_CRIT)
				print("RulesEngine: [11e 10.07] INDIRECT — hit re-rolls suppressed")
		# 11e 15.09 SNAP SHOOTING (FIRE OVERWATCH 15.08): "You cannot re-roll
		# hit rolls." Re-roll-hits abilities and stratagem
		# flags are all stripped for every snap attack.
		if is_overwatch and GameConstants.edition >= 11 and (hit_modifiers & (HitModifier.REROLL_ONES | HitModifier.REROLL_FAILED | HitModifier.REROLL_NON_CRIT)):
			hit_modifiers &= ~(HitModifier.REROLL_ONES | HitModifier.REROLL_FAILED | HitModifier.REROLL_NON_CRIT)
			print("RulesEngine: [11e 15.09] SNAP — hit re-rolls suppressed")
		# WP-M4a SENTINEL PROTOCOLS: snap-shooting attacks hit on UNMODIFIED 4+ — no hit-roll modifier applies.
		if is_overwatch and SMAbilitiesAScript.snap_hit_threshold(actor_unit) > 0 and (hit_modifiers & (HitModifier.PLUS_ONE | HitModifier.MINUS_ONE)):
			hit_modifiers &= ~(HitModifier.PLUS_ONE | HitModifier.MINUS_ONE)
			print("RulesEngine: [WP-M4a] Sentinel Protocols — unmodified 4+: hit-roll modifiers dropped")
		# DRIVE-BY BUSTIN': a batch mixing Firing Deck and the transport's own
		# weapons gets the +1 only on its Firing Deck attacks.
		var ork11e_fd_mixed: bool = ork11e_drive_by_bustin_active(actor_unit) and ork11e_fd_attack.has(true) and ork11e_fd_attack.has(false)
		if ork11e_fd_mixed:
			ModifierLedger.note(hit_mod_ledger, "Drive-by Bustin'", ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE, "Firing Deck weapons' attacks only")
		# SPEEDIEST FREEKS (Codex: Orks 11e): ranged attacks that target the
		# unit fail on an unmodified hit roll of 1-3.
		hit_fail_band = ork11e_ranged_hit_fail_band(target_unit, hit_fail_band)
		for i in range(hit_rolls.size()):
			var roll = hit_rolls[i]
			# MA-10: Use per-model BS for this attack's threshold
			var attack_bs = bs_per_attack[i] if i < bs_per_attack.size() else bs
			var ork11e_attack_mods: int = hit_modifiers
			if ork11e_fd_mixed and i < ork11e_fd_attack.size() and ork11e_fd_attack[i]:
				ork11e_attack_mods |= HitModifier.PLUS_ONE
			var hit_eval = AttackSequence.evaluate_hit_roll(roll, attack_bs, ork11e_attack_mods, critical_hit_threshold, rng, hit_fail_band)
			modified_rolls.append(hit_eval.final_roll)
			hit_evals.append({"raw": roll, "final": hit_eval.final_roll, "is_hit": hit_eval.is_hit, "is_crit": hit_eval.is_crit, "rerolled": hit_eval.rerolled, "reroll_from": hit_eval.reroll_from, "reroll_to": hit_eval.reroll_to})
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

		# Codex: Adeptus Custodes MAGNA IMPERATOR (Emperor's Chosen, WP-C46): re-roll one hit roll
		# (not for an [INDIRECT FIRE] shot at an unseen target — 10.07 forbids hit re-rolls; not for snap shooting).
		if not indirect_consequences and not is_overwatch:
			var cus11e_mh: Dictionary = cus11e_magna_reroll_hit(actor_unit, hit_evals, modified_rolls, reroll_data, bs_per_attack, bs, hit_modifiers, critical_hit_threshold, rng, hit_fail_band, hit_mod_ledger)
			hits += int(cus11e_mh.hit)
			critical_hits += int(cus11e_mh.crit)
			regular_hits += int(cus11e_mh.hit) - int(cus11e_mh.crit)
			# WP-M2a Codex: Space Marines (11e) Ironstorm Auto-targeters / Martial Paragon: re-roll one hit roll.
			var sm11e_mh: Dictionary = sm11e_reroll_one_hit(actor_unit, false, hit_evals, modified_rolls, reroll_data, bs_per_attack, bs, hit_modifiers, critical_hit_threshold, rng, hit_fail_band, hit_mod_ledger)
			hits += int(sm11e_mh.hit)
			critical_hits += int(sm11e_mh.crit)
			regular_hits += int(sm11e_mh.hit) - int(sm11e_mh.crit)

		# DAKKASTORM (OA-16): Every successful Hit roll scores a Critical Hit (ranged only)
		if has_dakkastorm(actor_unit) and regular_hits > 0:
			print("RulesEngine: DAKKASTORM — converting %d regular hits to critical hits for %s" % [regular_hits, actor_unit_id])
			critical_hits += regular_hits
			regular_hits = 0

		# Check for Lethal Hits keyword
		weapon_has_lethal_hits = has_lethal_hits(weapon_id, board, target_unit)
		# OA-10: Ammo Runt / unit effect flags — Lethal Hits from abilities or stratagems (ranged)
		if not weapon_has_lethal_hits and EffectPrimitivesData.has_effect_lethal_hits(actor_unit):
			weapon_has_lethal_hits = true
			print("RulesEngine:   LETHAL HITS granted by unit effect flag (e.g., Ammo Runt)")
		# BLITZA FIRE (Kult of Speed): ranged-scoped Lethal Hits flag
		if not weapon_has_lethal_hits and actor_unit.get("flags", {}).get("effect_lethal_hits_ranged", false):
			weapon_has_lethal_hits = true
			print("RulesEngine:   LETHAL HITS granted by ranged effect flag (BLITZA FIRE)")
		# TRY DAT BUTTON! (Dread Mob): rolled Button Effect — ranged LETHAL HITS
		if not weapon_has_lethal_hits and actor_unit.get("flags", {}).get("effect_try_dat_lethal_ranged", false):
			weapon_has_lethal_hits = true
			print("RulesEngine:   LETHAL HITS granted by TRY DAT BUTTON! (Dread Mob)")
		# WP-O6: Codex: Orks (11e) datasheet abilities (Pulsa Rokkit, Bust 'Em, ...)
		if not weapon_has_lethal_hits and bool(ork6.get("lethal", false)):
			weapon_has_lethal_hits = true
			print("RulesEngine:   LETHAL HITS granted by a Codex: Orks (11e) datasheet ability")

		# SUSTAINED HITS (PRP-011): Generate bonus hits on critical hits
		sustained_data = get_sustained_hits_value(weapon_id, board, target_unit)

		# HERE BE LOOT (OA-1): Freebooter Krew — Sustained Hits 1 near loot objective (ranged)
		if sustained_data.value == 0 and FactionAbilityManager.check_here_be_loot_sustained_hits(actor_unit, target_unit, board):
			sustained_data = {"value": 1, "is_dice": false}
			print("RulesEngine:   SUSTAINED HITS 1 granted by Here Be Loot (Freebooter Krew detachment)")
		# DAKKASTORM (Kult of Speed): ranged SUSTAINED HITS 1 (2 within 9")
		var kos_ds_val = get_dakkastorm_sustained_value(actor_unit, target_unit)
		if kos_ds_val > int(sustained_data.value):
			sustained_data = {"value": kos_ds_val, "is_dice": false}
			print("RulesEngine:   SUSTAINED HITS %d granted by DAKKASTORM (Kult of Speed)" % kos_ds_val)
		# TARGETIN' GIZMOS (Rollin' Deff): ranged SUSTAINED HITS 1 during a Waaagh!
		var tg_val = FactionAbilityManager.targetin_gizmos_sustained(actor_unit)
		if tg_val > int(sustained_data.value):
			sustained_data = {"value": tg_val, "is_dice": false}
			print("RulesEngine:   SUSTAINED HITS %d granted by TARGETIN' GIZMOS (Waaagh! active)" % tg_val)
		# DAKKA! DAKKA! DAKKA! (More Dakka! detachment): ranged SUSTAINED HITS 1
		# for ORKS INFANTRY/WALKER while the Waaagh! is active
		if int(sustained_data.value) == 0 and FactionAbilityManager.unit_has_more_dakka_waaagh_sustained(actor_unit):
			sustained_data = {"value": 1, "is_dice": false}
			print("RulesEngine:   SUSTAINED HITS 1 granted by DAKKA! DAKKA! DAKKA! (More Dakka! detachment, Waaagh! active)")
		# TRY DAT BUTTON! (Dread Mob): rolled Button Effect — ranged SUSTAINED HITS 1
		if int(sustained_data.value) == 0 and actor_unit.get("flags", {}).get("effect_try_dat_sustained_ranged", false):
			sustained_data = {"value": 1, "is_dice": false}
			print("RulesEngine:   SUSTAINED HITS 1 granted by TRY DAT BUTTON! (Dread Mob)")
		# NEVER ENOUGH DAKKA / DAKKASTORM / VINDICTIVE ARTILLERISTS (Codex: Orks 11e):
		# ranged [SUSTAINED HITS 1] (a weapon's own SUSTAINED HITS X is kept).
		var ork11e_sh_val = ork11e_ranged_sustained_hits(actor_unit)
		if int(sustained_data.value) == 0 and ork11e_sh_val > 0:
			sustained_data = {"value": ork11e_sh_val, "is_dice": false}
			print("RulesEngine:   SUSTAINED HITS %d granted by a Codex: Orks (11e) stratagem" % ork11e_sh_val)
		# WP-O6: More Dakka / Even More Dakka (riled up): ranged [SUSTAINED HITS 1]
		if int(sustained_data.value) == 0 and int(ork6.get("sustained", 0)) > 0:
			sustained_data = {"value": int(ork6.get("sustained", 0)), "is_dice": false}
			print("RulesEngine:   SUSTAINED HITS %d granted by a Codex: Orks (11e) datasheet ability" % int(ork6.get("sustained", 0)))

		# Codex: Space Marines (11e) stratagems (SMCodex11e.gd): HEADHUNTER DOCTRINE / RELENTLESS ASSAULT / STRIKE FROM THE SHADOWS.
		var sm11e_g: Dictionary = _sm11e_codex().attack_grants(actor_unit, target_unit, false)
		if not weapon_has_lethal_hits and str(sm11e_g.lethal) != "":
			weapon_has_lethal_hits = true
			print("RulesEngine:   LETHAL HITS granted by %s" % str(sm11e_g.lethal))
		if int(sustained_data.value) == 0 and int(sm11e_g.sustained) > 0:
			sustained_data = {"value": int(sm11e_g.sustained), "is_dice": false}
			print("RulesEngine:   SUSTAINED HITS %d granted by a Codex: Space Marines stratagem" % int(sm11e_g.sustained))

		sustained_result = roll_sustained_hits(critical_hits, sustained_data, rng)
		sustained_bonus_hits = sustained_result.bonus_hits

		# Total hits for wound rolls = regular hits + bonus hits from Sustained
		# (Critical hits with Lethal Hits auto-wound, but their Sustained bonus hits still roll)
		total_hits_for_wounds = hits + sustained_bonus_hits
		cus11e_det().note_ranged_hits(actor_unit, weapon_id, target_unit_id, hits)  # Codex: Adeptus Custodes (11e) Auriferous Orb — BLINDING LIGHT targets (WP-C46)

		# The displayed target must match what each die was judged against —
		# bs_per_attack carries the effective (cover/plunging-adjusted) BS.
		# The fail band's source: 10.07 indirect shooting, or only SPEEDIEST
		# FREEKS (Codex: Orks 11e) on an ordinary shot — don't call that "indirect".
		hit_threshold_display = _hit_threshold_display(bs, bs_per_attack, cover_worsened_attacks, hit_fail_band,
			"indirect" if indirect_consequences else "fails on 1-%d" % hit_fail_band)
		result.dice.append({
			"context": "to_hit",
			"threshold": hit_threshold_display,
			"rolls_raw": hit_rolls,
			"rolls_modified": modified_rolls,
			"rerolls": reroll_data,
			"modifiers_applied": hit_modifiers,
			"modifier_ledger": hit_mod_ledger,
			"heavy_bonus_applied": heavy_bonus_applied,
			"bgnt_penalty_applied": bgnt_penalty_applied,
			"indirect_fire_applied": indirect_fire_applied,
			"rapid_fire_bonus": rapid_fire_attacks,
			"rapid_fire_value": rapid_fire_value,
			"models_in_half_range": models_in_half_range,
			"base_attacks": base_attacks,
			"successes": hits,
			"target_unit_id": target_unit_id,  # enemy_has_shot window: which units were hit
			"weapon_id": weapon_id,  # WP-M4b Suppression Fire: hits per weapon
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
		# Unmodified rolls up to this value fail regardless of BS (INDIRECT
		# FIRE 10.07, SPEEDIEST FREEKS) — the dice log shows the band (r5:F10).
		# Only written when wider than the core unmodified-1 fail, so every
		# other dice block is unchanged (ISS-012 attack goldens).
		if hit_fail_band > 1:
			result.dice[-1]["hit_fail_band"] = hit_fail_band

	# Build the hit context up-front so it is available even on a full miss —
	# the staged shooting path may Command Re-roll a MISSED die (turning it into
	# a hit), which needs the per-die evals/modifiers preserved here.
	var hit_context = {
		"assignment": assignment,
		"actor_unit_id": actor_unit_id,
		"weapon_id": weapon_id,
		"weapon_profile": weapon_profile,
		"actor_unit": actor_unit,
		"target_unit": target_unit,
		"target_unit_id": target_unit_id,
		"model_ids": model_ids,
		"hits": hits,
		"critical_hits": critical_hits,
		"regular_hits": regular_hits,
		"sustained_bonus_hits": sustained_bonus_hits,
		"total_hits_for_wounds": total_hits_for_wounds,
		"weapon_has_lethal_hits": weapon_has_lethal_hits,
		"is_torrent": is_torrent,
		# 11e 10.07: indirect shooting — "You cannot re-roll hit rolls" (also
		# blocks the staged Command Re-roll of a hit die).
		# 11e 15.09: snap shooting (FIRE OVERWATCH) cannot re-roll hit rolls either.
		"no_hit_rerolls": (indirect_consequences or is_overwatch) and GameConstants.edition >= 11,
		"hit_rolls": hit_rolls,
		"modified_rolls": modified_rolls,
		"hit_evals": hit_evals,
		"reroll_data": reroll_data,
		"bs": bs,
		"bs_per_attack": bs_per_attack,
		"hit_threshold_display": hit_threshold_display,
		"total_attacks": total_attacks,
		"heavy_bonus_applied": heavy_bonus_applied,
		"bgnt_penalty_applied": bgnt_penalty_applied,
		"indirect_fire_applied": indirect_fire_applied,
		"models_in_half_range": models_in_half_range,
		"rapid_fire_value": rapid_fire_value,
		"hit_modifiers": hit_modifiers,
		"modifier_ledger": hit_mod_ledger,
		"critical_hit_threshold": critical_hit_threshold,
		"hit_fail_band": hit_fail_band,
		"sustained_data": sustained_data,
		# DRIVE-BY BUSTIN': per-attack +1 for a batch mixing Firing Deck weapons
		"ork11e_fd_plus_one": ork11e_fd_attack if (ork11e_drive_by_bustin_active(actor_unit) and ork11e_fd_attack.has(true) and ork11e_fd_attack.has(false)) else [],
		# WP-O6: Codex: Orks (11e) datasheet-ability modifiers for the wound/save stages
		"ork11e_ab": ork6,
	}
	result["hit_context"] = hit_context

	if hits == 0 and sustained_bonus_hits == 0:
		var miss_weapon_name = weapon_profile.get("name", weapon_id)
		var miss_log = "%s → %s with %s - No hits" % [actor_unit.get("meta", {}).get("name", actor_unit_id), target_unit.get("meta", {}).get("name", target_unit_id), miss_weapon_name]
		if not hit_rolls.is_empty():
			miss_log += " [%s] vs %s" % [", ".join(hit_rolls.map(func(r): return str(r))), hit_threshold_display]
		result.log_text = miss_log
		result["no_hits"] = true
		return result

	result["no_hits"] = false
	return result

static func _resolve_assignment_wounds(hit_context: Dictionary, board: Dictionary, rng: RNGService) -> Dictionary:
	var result = {"dice": [], "log_text": ""}
	var assignment = hit_context["assignment"]
	var actor_unit_id = hit_context["actor_unit_id"]
	var weapon_id = hit_context["weapon_id"]
	var weapon_profile = hit_context["weapon_profile"]
	var actor_unit = hit_context["actor_unit"]
	var target_unit = hit_context["target_unit"]
	var target_unit_id = hit_context["target_unit_id"]
	var model_ids = hit_context["model_ids"]
	var hits = hit_context["hits"]
	var critical_hits = hit_context["critical_hits"]
	var regular_hits = hit_context["regular_hits"]
	var sustained_bonus_hits = hit_context["sustained_bonus_hits"]
	var total_hits_for_wounds = hit_context["total_hits_for_wounds"]
	var weapon_has_lethal_hits = hit_context["weapon_has_lethal_hits"]
	var is_torrent = hit_context["is_torrent"]
	var hit_rolls = hit_context["hit_rolls"]
	var modified_rolls = hit_context["modified_rolls"]
	var reroll_data = hit_context["reroll_data"]
	var bs = hit_context["bs"]
	var bs_per_attack = hit_context["bs_per_attack"]
	var hit_threshold_display = str(hit_context.get("hit_threshold_display", str(bs) + "+"))
	var total_attacks = hit_context["total_attacks"]
	var heavy_bonus_applied = hit_context["heavy_bonus_applied"]
	var bgnt_penalty_applied = hit_context["bgnt_penalty_applied"]
	var indirect_fire_applied = hit_context["indirect_fire_applied"]
	var models_in_half_range = hit_context["models_in_half_range"]
	var rapid_fire_value = hit_context["rapid_fire_value"]
	var hit_modifiers = hit_context["hit_modifiers"]
	var critical_hit_threshold = hit_context["critical_hit_threshold"]
	var sustained_data = hit_context["sustained_data"]
	# GROT SHIELDS (Codex: Orks 11e): hits on the shielded unit end their attack
	# sequence and become mortal wounds on the Gretchin unit. The diffs ride
	# out in result.grot_shields_diffs (merged into the action's changes).
	var gs_res = ork11e_grot_shields_intercept(actor_unit_id, target_unit, critical_hits, regular_hits, sustained_bonus_hits, sustained_data, is_torrent, board, rng)
	if gs_res.active and gs_res.intercepted > 0:
		critical_hits = gs_res.critical_hits
		regular_hits = gs_res.regular_hits
		sustained_bonus_hits = gs_res.sustained_bonus_hits
		hits = critical_hits + regular_hits
		total_hits_for_wounds = hits + sustained_bonus_hits
		result["grot_shields_diffs"] = gs_res.diffs
		result.dice.append({"context": "grot_shields", "message": gs_res.log_text,
			"intercepted": gs_res.intercepted, "gretchin_unit_id": gs_res.gretchin_unit_id,
			"target_unit_id": target_unit_id})
	# Roll to wound - LETHAL HITS (PRP-010) + SUSTAINED HITS (PRP-011) + DEVASTATING WOUNDS (PRP-012)
	# TORRENT (PRP-014): Torrent weapons skip hit roll but still roll to wound normally
	var strength = weapon_profile.get("strength", 4)
	# WP-O6: Codex: Orks (11e) datasheet-ability modifiers (carried from the hit stage)
	var ork6: Dictionary = hit_context.get("ork11e_ab", {})
	if ork6.is_empty():
		ork6 = ork11e_ab_mods(actor_unit, target_unit, weapon_profile, false, board, model_ids)
	if int(ork6.get("strength", 0)) != 0:
		strength += int(ork6.get("strength", 0))
		print("RulesEngine: [WP-O6] ranged strength +%d from Codex: Orks (11e) datasheet abilities → S%d" % [int(ork6.get("strength", 0)), strength])
	# MOBILE DAKKASTORM (Speedwaaagh!): +2 Strength for a SPEED FREEKS/TRUKK unit's
	# ranged attacks against the marked enemy unit (marker holds the user's player).
	if target_unit.get("flags", {}).get("mobile_dakkastorm_marked", false) \
			and int(actor_unit.get("owner", 0)) != int(target_unit.get("owner", -1)) \
			and (unit_has_keyword(actor_unit, "SPEED FREEKS") or unit_has_keyword(actor_unit, "TRUKK")):
		var pre_s_md = strength
		strength += 2
		print("RulesEngine: MOBILE DAKKASTORM — ranged strength %d → %d (+2 vs marked %s)" % [pre_s_md, strength, target_unit_id])
	# Codex: Adeptus Custodes stratagems (CustodesCodex11e.gd): TIP OF THE TALON +1 S vs a target within 9".
	strength += int(_cus11e_codex().ranged_strength_bonus(actor_unit, target_unit, board))
	# Codex: Space Marines (11e) STRIKE FROM THE SHADOWS (SMCodex11e.gd): +1 S.
	strength += int(_sm11e_codex().attack_grants(actor_unit, target_unit, false).strength)
	strength += ork11e_det_strength_bonus(actor_unit, weapon_id, board)  # Codex: Orks (11e) Try Dat Button! / Powers of da Waaagh! (WP-O34)
	var toughness = _get_attached_unit_toughness(target_unit, board)  # P2-90: Use bodyguard T for attached units
	# OA-44: DED GLOWY AMMO — -1T to enemy INFANTRY within 6" of Kaptin Badrukk
	var ded_glowy_penalty = get_ded_glowy_ammo_toughness_penalty(target_unit, board)
	if ded_glowy_penalty > 0:
		toughness = max(1, toughness - ded_glowy_penalty)
		print("RulesEngine: DED GLOWY AMMO — INFANTRY target T reduced by %d to T%d" % [ded_glowy_penalty, toughness])
	toughness = ork11e_det_toughness(actor_unit, target_unit, toughness)  # Codex: Orks (11e) Unpredictable Genius — Runtified (WP-O34)
	var wound_threshold = _calculate_wound_threshold(strength, toughness)

	# DEVASTATING WOUNDS (PRP-012): Check if weapon has Devastating Wounds
	var weapon_has_devastating_wounds = has_devastating_wounds(weapon_id, board, target_unit)
	# Issue #374 Headwoppa's Killchoppa: unit-level effect_devastating_wounds
	# grants DEVASTATING WOUNDS to the bearer's melee weapons. Apply at the
	# unit level here.
	if not weapon_has_devastating_wounds and actor_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_DEVASTATING_WOUNDS, false):
		weapon_has_devastating_wounds = true
		print("RulesEngine: Headwoppa's Killchoppa — unit-level effect_devastating_wounds applied (until-wounds path)")
	if not weapon_has_devastating_wounds and bool(ork6.get("devastating", false)):  # WP-O5 Supa-glowy Fing
		weapon_has_devastating_wounds = true
		print("RulesEngine: [WP-O5] [DEVASTATING WOUNDS] granted by a Codex: Orks (11e) enhancement")

	# 24.10 (audit #17): [DEVASTATING WOUNDS] is a CHOICE — the attacker may
	# decline the mortal-wound conversion for this batch; critical wounds
	# then resolve through the normal save/damage sequence.
	if GameConstants.edition >= 11 and weapon_has_devastating_wounds \
			and str(assignment.get("devastating_wounds_choice", "")) == "normal":
		weapon_has_devastating_wounds = false
		print("RulesEngine: [24.10] DEVASTATING WOUNDS — attacker declined the mortal-wound conversion")

	# ANTI-[KEYWORD] X+: Get critical wound threshold (6 normally, lower if Anti matches target)
	var critical_wound_threshold = get_critical_wound_threshold(weapon_id, target_unit, board)
	critical_wound_threshold = mini(critical_wound_threshold, int(ork11e_enh().anti_threshold(ork6, target_unit)))  # WP-O5 Supa-glowy Fing [ANTI-INFANTRY 4+]

	# ROLLING LOOT-HEAP (OA-6): Grant Anti-Vehicle 4+ from stratagem flag
	if actor_unit.get("flags", {}).get("effect_rolling_loot_heap", false):
		if unit_has_keyword(target_unit, "VEHICLE"):
			critical_wound_threshold = mini(critical_wound_threshold, 4)
			print("RulesEngine: ROLLING LOOT-HEAP — Anti-Vehicle 4+ active (critical wound threshold %d+)" % critical_wound_threshold)

	# SPESHUL AMMO (Speedwaaagh!): non-Torrent ranged weapons gain
	# [ANTI-MONSTER 4+] and [ANTI-VEHICLE 4+] (critical wound on 4+ vs those).
	if actor_unit.get("flags", {}).get("effect_speshul_ammo", false):
		var sa_is_torrent = "torrent" in str(get_weapon_profile(weapon_id, board).get("special_rules", "")).to_lower()
		if not sa_is_torrent and (unit_has_keyword(target_unit, "MONSTER") or unit_has_keyword(target_unit, "VEHICLE")):
			critical_wound_threshold = mini(critical_wound_threshold, 4)
			print("RulesEngine: SPESHUL AMMO — Anti-Monster/Vehicle 4+ active (critical wound threshold %d+)" % critical_wound_threshold)

	var anti_keyword_active = critical_wound_threshold < 6

	# TWIN-LINKED: Check if weapon has Twin-linked (re-roll all failed wound rolls)
	var weapon_has_twin_linked = has_twin_linked(weapon_id, board, target_unit) or assignment.get("twin_linked", false)

	# WOUND MODIFIERS (T1-3): Build wound modifier flags from assignment and game state
	# ISS-modifier-provenance: names WHERE each modifier below came from, so the
	# Dice Log and the resolution docks can say "Against All Odds: +1 to hit"
	# instead of an anonymous "+1". Purely additive — never read by the maths.
	var wound_modifiers = WoundModifier.NONE
	var wound_mod_ledger: Array = []
	if assignment.has("modifiers") and assignment.modifiers.has("wound"):
		var wound_mods = assignment.modifiers.wound
		if wound_mods.get("reroll_ones", false):
			wound_modifiers |= WoundModifier.REROLL_ONES
			ModifierLedger.note(wound_mod_ledger, "Attack assignment", ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_ONES)
		if wound_mods.get("reroll_failed", false):
			wound_modifiers |= WoundModifier.REROLL_FAILED
			ModifierLedger.note(wound_mod_ledger, "Attack assignment", ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_FAILED)
		if wound_mods.get("plus_one", false):
			wound_modifiers |= WoundModifier.PLUS_ONE
			ModifierLedger.note(wound_mod_ledger, "Attack assignment", ModifierLedger.KIND_WOUND, ModifierLedger.PLUS_ONE)
		if wound_mods.get("minus_one", false):
			wound_modifiers |= WoundModifier.MINUS_ONE
			ModifierLedger.note(wound_mod_ledger, "Attack assignment", ModifierLedger.KIND_WOUND, ModifierLedger.MINUS_ONE)
	# Twin-linked handled via WoundModifier system for re-rolls
	if weapon_has_twin_linked:
		wound_modifiers |= WoundModifier.REROLL_FAILED
		ModifierLedger.note(wound_mod_ledger, "[TWIN-LINKED]", ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_FAILED)

	# EFFECT FLAGS: Check for ability/stratagem-granted wound modifiers on the attacker
	if EffectPrimitivesData.has_effect_plus_one_wound(actor_unit):
		wound_modifiers |= WoundModifier.PLUS_ONE
		ModifierLedger.note(wound_mod_ledger, "Ability effect", ModifierLedger.KIND_WOUND, ModifierLedger.PLUS_ONE, "granted by an ability or Stratagem")
		print("RulesEngine: Effect +1 to wound applied for %s" % actor_unit_id)
	if EffectPrimitivesData.has_effect_minus_one_wound(actor_unit):
		wound_modifiers |= WoundModifier.MINUS_ONE
		ModifierLedger.note(wound_mod_ledger, "Ability effect", ModifierLedger.KIND_WOUND, ModifierLedger.MINUS_ONE, "imposed by an ability or Stratagem")
		print("RulesEngine: Effect -1 to wound applied for %s" % actor_unit_id)
	# DEFENDER FLAG ('ARD AS NAILS): -1 to wound for attacks targeting the flagged unit
	if EffectPrimitivesData.has_effect_minus_one_wound_defense(target_unit):
		wound_modifiers |= WoundModifier.MINUS_ONE
		ModifierLedger.note(wound_mod_ledger, "'Ard as Nails", ModifierLedger.KIND_WOUND, ModifierLedger.MINUS_ONE, "defender's ability")
		print("RulesEngine: Defender effect -1 to wound (attacks vs %s)" % target_unit_id)
	var reroll_wounds_scope = actor_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_REROLL_WOUNDS, "")
	if reroll_wounds_scope == "ones":
		wound_modifiers |= WoundModifier.REROLL_ONES
		ModifierLedger.note(wound_mod_ledger, "Ability effect", ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_ONES, "granted by an ability or Stratagem")
		print("RulesEngine: Effect re-roll 1s to wound applied for %s" % actor_unit_id)
	elif reroll_wounds_scope == "failed":
		wound_modifiers |= WoundModifier.REROLL_FAILED
		ModifierLedger.note(wound_mod_ledger, "Ability effect", ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_FAILED, "granted by an ability or Stratagem")
		print("RulesEngine: Effect re-roll failed wounds applied for %s" % actor_unit_id)
	elif reroll_wounds_scope == "all":
		wound_modifiers |= WoundModifier.REROLL_FAILED
		ModifierLedger.note(wound_mod_ledger, "Ability effect", ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_FAILED, "re-roll all wound rolls")
		print("RulesEngine: Effect re-roll all wounds applied for %s" % actor_unit_id)

	# LANCE (T4-1): +1 to wound if unit charged this turn. Effect-granted Lance
	# (Deathsong Scythes etc.) treats all the unit's weapons as [LANCE].
	if is_lance_weapon(weapon_id, board) or EffectPrimitivesData.has_effect_lance(actor_unit):
		var unit_charged = actor_unit.get("flags", {}).get("charged_this_turn", false)
		if unit_charged:
			wound_modifiers |= WoundModifier.PLUS_ONE
			ModifierLedger.note(wound_mod_ledger, "[LANCE]", ModifierLedger.KIND_WOUND, ModifierLedger.PLUS_ONE, "unit charged this turn")
			print("RulesEngine: LANCE — +1 to wound (unit charged this turn)")

	# TANK HUNTERS (OA-11): +1 to Wound when attacking MONSTER or VEHICLE targets
	if has_tank_hunters_vs_target(actor_unit, target_unit):
		wound_modifiers |= WoundModifier.PLUS_ONE
		ModifierLedger.note(wound_mod_ledger, "Tank Hunters", ModifierLedger.KIND_WOUND, ModifierLedger.PLUS_ONE, "target is a MONSTER or VEHICLE")
		print("RulesEngine: TANK HUNTERS — +1 to wound for %s (target is MONSTER/VEHICLE)" % actor_unit_id)

	# WP-O6: Codex: Orks (11e) datasheet abilities (Go fer da Weak Spot, Beastscent, Warpath, ...)
	wound_modifiers = ork11e_ab_wound_bits(wound_modifiers, wound_mod_ledger, ork6)

	# HARDY BIONIKS (WP-O6, Painboss): -1 to wound for S > T attacks that target the unit
	if ork11e_ab_wound_penalty(target_unit, strength, toughness):
		wound_modifiers |= WoundModifier.MINUS_ONE
		ModifierLedger.note(wound_mod_ledger, ork11e_ab_wound_penalty_name(target_unit, strength, toughness), ModifierLedger.KIND_WOUND, ModifierLedger.MINUS_ONE, "attack's Strength exceeds the target's Toughness")
		print("RulesEngine: HARDY BIONIKS — -1 to wound for attacks against %s (S %d > T %d)" % [target_unit_id, strength, toughness])
	# IMPERVIOUS / effect_minus_wound_s_gt_t: -1 to wound while S > T
	var sgt_mod = get_s_gt_t_wound_penalty(target_unit, board, strength, toughness)
	if sgt_mod != WoundModifier.NONE:
		wound_modifiers |= sgt_mod
		ModifierLedger.note(wound_mod_ledger, "IMPERVIOUS", ModifierLedger.KIND_WOUND, ModifierLedger.MINUS_ONE, "attack's Strength exceeds the target's Toughness")
		print("RulesEngine: S>T wound penalty — -1 to wound for attacks against %s (S %d > T %d)" % [target_unit_id, strength, toughness])
	# HULKING BRUTES (Codex: Orks 11e): -1 to wound for ranged attacks that
	# target the unit (S > T only, or every attack with the +1CP upgrade).
	if ork11e_ranged_wound_penalty(target_unit, strength, toughness):
		wound_modifiers |= WoundModifier.MINUS_ONE
		ModifierLedger.note(wound_mod_ledger, "Hulking Brutes", ModifierLedger.KIND_WOUND, ModifierLedger.MINUS_ONE, "Codex: Orks stratagem on the target")
		print("RulesEngine: HULKING BRUTES — -1 to wound for ranged attacks against %s (S %d, T %d, mode %s)" % [target_unit_id, strength, toughness, str(target_unit.get("flags", {}).get("ork11e_hulking_brutes", ""))])
	# BIGGER SHELLS FOR BIGGER GITZ (Dread Mob): +1 to wound vs MONSTER/VEHICLE
	if get_bigger_shells_wound_bonus(actor_unit, target_unit) > 0:
		wound_modifiers |= WoundModifier.PLUS_ONE
		ModifierLedger.note(wound_mod_ledger, "Bigger Shells for Bigger Gitz", ModifierLedger.KIND_WOUND, ModifierLedger.PLUS_ONE)
		print("RulesEngine: BIGGER SHELLS — +1 to wound vs %s (MONSTER/VEHICLE)" % target_unit_id)
	# ARMOURED DUELLISTS (Blitz Brigade): +1 to wound vs MONSTER/VEHICLE
	if get_armoured_duellists_bonus(actor_unit, target_unit) > 0:
		wound_modifiers |= WoundModifier.PLUS_ONE
		ModifierLedger.note(wound_mod_ledger, "Armoured Duellists", ModifierLedger.KIND_WOUND, ModifierLedger.PLUS_ONE, "target is a MONSTER or VEHICLE")
		print("RulesEngine: ARMOURED DUELLISTS — +1 to wound vs %s (MONSTER/VEHICLE)" % target_unit_id)
	# PYROMANIAKS (OA-14): Re-roll Wound rolls of 1 with Torrent weapons vs enemies within 6"
	# Full Wound re-roll if target is also within range of an objective marker.
	var pyromaniaks_scope = get_pyromaniaks_reroll_scope(actor_unit, target_unit, weapon_id, board)
	if pyromaniaks_scope == "failed":
		wound_modifiers |= WoundModifier.REROLL_FAILED
		ModifierLedger.note(wound_mod_ledger, "Pyromaniaks", ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_FAILED, "target within range of an objective marker")
		print("RulesEngine: PYROMANIAKS — full wound re-roll for %s (Torrent weapon, target within 6\" AND near objective)" % actor_unit_id)
	elif pyromaniaks_scope == "ones":
		wound_modifiers |= WoundModifier.REROLL_ONES
		ModifierLedger.note(wound_mod_ledger, "Pyromaniaks", ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_ONES, "target within range of an objective marker")
		print("RulesEngine: PYROMANIAKS — re-roll wound rolls of 1 for %s (Torrent weapon, target within 6\")" % actor_unit_id)

	# Codex: Adeptus Custodes (11e) detachment rules / enhancements (CustodesDetachments.gd, WP-C46).
	wound_modifiers = cus11e_apply_wound_effects(wound_modifiers, wound_mod_ledger, actor_unit, target_unit, false, strength, toughness, board, {"model_ids": assignment.get("model_ids", [])})
	# Codex: Space Marines (11e) Space Wolves stratagems (SWCodex11e.gd): EYE OF THE PACK re-rolls wound rolls of 1 and 2.
	wound_modifiers = _sw11e_codex().apply_wound_bits(wound_modifiers, actor_unit, target_unit, false, wound_mod_ledger)
	# Codex: Space Marines (11e) stratagems (SMCodex11e.gd): MIGHT OF THE MACHINE SPIRIT ignores wound-roll penalties.
	wound_modifiers = _sm11e_codex().apply_wound_bits(wound_modifiers, actor_unit, target_unit, false, wound_mod_ledger)

	# KUSTOM DAKKA (Codex: Orks 11e): +1 to wound vs a target that is not a MONSTER/VEHICLE unit
	if ork11e_kustom_dakka_wound_bonus(actor_unit, target_unit) > 0:
		wound_modifiers |= WoundModifier.PLUS_ONE
		ModifierLedger.note(wound_mod_ledger, "Kustom Dakka", ModifierLedger.KIND_WOUND, ModifierLedger.PLUS_ONE, "target is not a MONSTER or VEHICLE")
		print("RulesEngine: KUSTOM DAKKA — +1 to wound vs %s" % target_unit_id)
	# Codex: Adeptus Custodes SALVUS (CustodesKatah.gd): wound-roll penalties ignored.
	if _cus11e_katah().salvus_active(actor_unit) and (wound_modifiers & WoundModifier.MINUS_ONE):
		wound_modifiers = wound_modifiers & ~WoundModifier.MINUS_ONE
		ModifierLedger.note(wound_mod_ledger, "Salvus (Ka'tah)", ModifierLedger.KIND_WOUND, ModifierLedger.IGNORED, "wound-roll penalties ignored")
		ModifierLedger.mark_ignored(wound_mod_ledger, ModifierLedger.KIND_WOUND, [ModifierLedger.MINUS_ONE])
		print("RulesEngine: SALVUS — ignoring wound-roll penalties for %s" % actor_unit_id)
	wound_modifiers = sw11e_ignore_wound_penalties(wound_modifiers, wound_mod_ledger, ork6)  # WP-S4 Gift of the Iron Wolf (Space Wolves)
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
	# Per-die classification, captured so a single-die Command Re-roll (staged
	# shooting) can recompute wound totals without re-rolling untouched dice.
	var wound_evals = []

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
				wound_evals.append({"raw": roll, "is_wound": wound_eval.is_wound, "is_crit": wound_eval.is_crit, "auto_fail": wound_eval.auto_fail, "rerolled": wound_eval.rerolled, "reroll_from": wound_eval.reroll_from, "reroll_to": wound_eval.reroll_to})
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
			wound_evals.append({"raw": roll, "is_wound": wound_eval.is_wound, "is_crit": wound_eval.is_crit, "auto_fail": wound_eval.auto_fail, "rerolled": wound_eval.rerolled, "reroll_from": wound_eval.reroll_from, "reroll_to": wound_eval.reroll_to})
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

	# Codex: Adeptus Custodes MAGNA IMPERATOR (Emperor's Chosen, WP-C46): re-roll one wound roll.
	var cus11e_mw: Dictionary = cus11e_magna_reroll_wound(actor_unit, wound_evals, wound_rolls, wound_reroll_data, wound_modifiers, wound_threshold, critical_wound_threshold, rng, wound_mod_ledger)
	if int(cus11e_mw.wound) > 0:
		wounds_from_rolls += 1
		if weapon_has_devastating_wounds and int(cus11e_mw.crit) > 0:
			critical_wound_count += 1
		else:
			regular_wound_count += 1
	# WP-M2a Codex: Space Marines (11e) Ironstorm Auto-targeters / Martial Paragon: re-roll one wound roll.
	var sm11e_mw: Dictionary = sm11e_reroll_one_wound(actor_unit, false, wound_evals, wound_rolls, wound_reroll_data, wound_modifiers, wound_threshold, critical_wound_threshold, rng, wound_mod_ledger)
	if int(sm11e_mw.wound) > 0:
		wounds_from_rolls += 1
		if weapon_has_devastating_wounds and int(sm11e_mw.crit) > 0:
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
		"modifier_ledger": wound_mod_ledger,
		"wound_modifiers_applied": wound_modifiers
	})

	if wounds_caused == 0:
		var no_wound_weapon_name = weapon_profile.get("name", weapon_id)
		var no_wound_log = "%s → %s with %s" % [actor_unit.get("meta", {}).get("name", actor_unit_id), target_unit.get("meta", {}).get("name", target_unit_id), no_wound_weapon_name]
		if is_torrent:
			no_wound_log += " - Torrent: %d auto-hits" % hits
		elif not hit_rolls.is_empty():
			no_wound_log += " - Hit: %d/%d [%s] vs %s" % [hits, total_attacks, ", ".join(hit_rolls.map(func(r): return str(r))), hit_threshold_display]
		else:
			no_wound_log += " - %d hits" % hits
		if sustained_bonus_hits > 0:
			no_wound_log += " (+%d sustained)" % sustained_bonus_hits
		if not wound_rolls.is_empty():
			no_wound_log += " - Wound: 0/%d [%s] vs %s+" % [total_hits_for_wounds, ", ".join(wound_rolls.map(func(r): return str(r))), str(wound_threshold)]
		else:
			no_wound_log += " - no wounds"
		result.log_text = no_wound_log
		result["no_wounds"] = true
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
	var weapon_has_precision = has_precision(weapon_id, board) or bool(ork6.get("precision", false))  # WP-S4 Headhunters (Space Wolves): [PRECISION] vs the quarry
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
	# Everything a single-die Command Re-roll (staged shooting) needs to re-tally
	# wounds and rebuild save_data without re-rolling the untouched dice.
	result["wound_context"] = {
		"weapon_id": weapon_id,
		"weapon_profile": weapon_profile,
		"actor_unit_id": actor_unit_id,
		"target_unit_id": target_unit_id,
		"wound_rolls": wound_rolls,
		"wound_evals": wound_evals,
		"wound_threshold": wound_threshold,
		"wound_modifiers": wound_modifiers,
		"modifier_ledger": wound_mod_ledger,
		"critical_wound_threshold": critical_wound_threshold,
		"weapon_has_devastating_wounds": weapon_has_devastating_wounds,
		"weapon_has_precision": weapon_has_precision,
		"auto_wounds": auto_wounds,
		"critical_hits": critical_hits,
		"melta_data": melta_data,
	}
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
			hit_detail += " [%s] vs %s" % [", ".join(hit_rolls.map(func(r): return str(r))), hit_threshold_display]
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
	if has_devastating_wounds(weapon_id, board, board.get("units", {}).get(str(assignment.get("target_unit_id", "")), {})):
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
	var save_modifier = clampi(int(target_unit.get("flags", {}).get("save_modifier", 0)) + int(_sm11e_abilities_b().save_roll_bonus(target_unit)), -1, 1)  # WP-M4b: Unyielding in the Face of the Foe (+1 to save rolls)
	var effect_invuln = EffectPrimitivesData.get_effect_invuln(target_unit)
	var melta_value = int(opts.get("melta_value", 0))
	var melta_box = [int(opts.get("melta_wounds", 0))]
	var has_half_damage = bool(opts.get("half_damage", false))
	var unit_fnp_value = int(opts.get("fnp_value", 0))
	# WP-C3: the attack's kind for the conditional FNP grants — psychic attacks
	# (Daughters of the Abyss / Psychic Null) and the devastating-wound mortal
	# wounds below (Aegis of the Emperor). Best applicable FNP, never stacked.
	var alloc_is_psychic := bool(opts.get("is_psychic", false))
	var dw_fnp_value := _better_fnp(unit_fnp_value, _conditional_fnp(target_unit, alloc_is_psychic, true))
	# BIGGER SHELLS (Dread Mob, pushed): callers pass the attacking unit so the
	# conditional +1 Damage vs MONSTER/VEHICLE can resolve per target.
	var bs_actor_unit: Dictionary = opts.get("actor_unit", {})
	# WP-O6: flat +D per attack from Codex: Orks (11e) datasheet abilities
	# (High-speed Carnage, Brutal Impact) — melee callers pass it.
	var plus_damage := int(opts.get("plus_damage", 0))
	effect_invuln = ork11e_det_invuln(bs_actor_unit, target_unit, effect_invuln)  # Codex: Orks (11e) Unpredictable Genius — Dat's Weird (WP-O34)
	effect_invuln = cus11e_invuln(target_unit, bool(opts.get("is_melee", false)), effect_invuln)  # Codex: Adeptus Custodes (11e) Flare Shields / Eagle's Eye (WP-C46)
	var damage_roll_log: Array = out.damage_roll_log
	# Defender-side interactive options (AllocationGroupOverlay two-step flow):
	# forced_save_rolls replays an already-rolled batch (e.g. after a save
	# Command Re-roll substituted one die); preferred_targets is the
	# defender's chosen casualty order within groups.
	var forced_save_rolls: Array = opts.get("forced_save_rolls", [])
	var preferred_targets: Array = opts.get("preferred_targets", [])
	out["models_destroyed"] = []

	print("RulesEngine: [11e ALLOCATION] %d save(s) + %d devastating crit(s) vs %d group(s), order=%s" % [wounds_to_save, dev_wound_crits, groups.size(), str(order)])

	if wounds_to_save > 0:
		var save_rolls: Array
		if forced_save_rolls.size() == wounds_to_save:
			save_rolls = forced_save_rolls.duplicate()
			print("RulesEngine: [11e ALLOCATION] using %d forced save roll(s): %s" % [save_rolls.size(), str(save_rolls)])
		else:
			if not forced_save_rolls.is_empty():
				push_warning("RulesEngine: forced_save_rolls size %d != wounds_to_save %d — rolling fresh" % [forced_save_rolls.size(), wounds_to_save])
			save_rolls = rng.roll_d6(wounds_to_save)
		# Per inflicting attack: roll the D characteristic and apply the
		# defender-side damage modifiers (melta/half/minus/FNP), mirroring
		# the 10e loop so those abilities keep working under the 11e flow.
		var damage_provider = func(_roll: int, model_index: int) -> int:
			var dmg_result = roll_variable_characteristic(damage_raw, rng)
			# Codex: Adeptus Custodes stratagems (CustodesCodex11e.gd): PRIME TARGET re-rolls one low damage roll.
			dmg_result = _cus11e_codex().auto_single_reroll_damage(dmg_result, damage_raw, bs_actor_unit, rng)
			dmg_result = SMAbilitiesC11eScript.reroll_damage(dmg_result, damage_raw, bs_actor_unit, rng, bool(opts.get("is_melee", false)))  # WP-M4c: Total Obliteration
			var dmg = dmg_result.value
			if dmg_result.rolled:
				damage_roll_log.append(dmg_result)
			if melta_value > 0 and melta_box[0] > 0:
				dmg += melta_value
				melta_box[0] -= 1
			# BIGGER SHELLS (Dread Mob, pushed): +1 Damage vs MONSTER/VEHICLE
			dmg += get_bigger_shells_damage_bonus(bs_actor_unit, target_unit)
			dmg += plus_damage
			if has_half_damage:
				dmg = apply_half_damage(dmg)
			var minus_dmg = EffectPrimitivesData.get_effect_minus_damage(target_unit)
			if minus_dmg > 0:
				dmg = max(1, dmg - minus_dmg)
			# WP-C7: Codex: Adeptus Custodes (11e) Praesidium Shield — attacks allocated to the Shield-Captain's model have -1 D (min 1).
			if model_index >= 0 and model_index < models.size():
				var ps_res: Dictionary = CustodesAbilities11eScript.allocated_damage(dmg, target_unit, models[model_index], minus_dmg)
				if str(ps_res.get("note", "")) != "":
					dmg = int(ps_res.damage)
					result.dice.append({"context": "damage_modifier", "source": "Praesidium Shield", "message": str(ps_res.note)})
				var ry_res: Dictionary = _sm11e_abilities_b().allocated_damage(dmg, target_unit, models[model_index], minus_dmg)  # WP-M4b: Refuse to Yield (-1 D)
				if str(ry_res.get("note", "")) != "":
					dmg = int(ry_res.damage)
					result.dice.append({"context": "damage_modifier", "source": "Refuse to Yield", "message": str(ry_res.note)})
			var fnp = unit_fnp_value
			if model_index >= 0 and model_index < models.size():
				# Per-model FNP + the conditional grants for this attack (a
				# psychic attack keeps Daughters of the Abyss / Psychic Null).
				fnp = get_model_fnp_vs(target_unit, models[model_index], alloc_is_psychic, false)
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
			"preferred_targets": preferred_targets,
		})
		var fails := 0
		for ev in alloc.events:
			if ev.get("result", "") != "saved":
				fails += 1
		# ARMOUR SAVES IN THE LOGS: carry the threshold the defender was
		# actually rolling against (and whether it was an invulnerable save)
		# plus the standard successes/failed counters, so every downstream
		# renderer — dice log, game-log combat card — can label and colour the
		# save row the same way it does hit and wound rolls. Allocation is
		# per group, so this reports the group that took the first die; for a
		# single-group unit (the common case) it covers the whole batch.
		var save_needed_display := 0
		var save_using_invuln := false
		for ev in alloc.events:
			if ev.has("needed"):
				save_needed_display = int(ev.get("needed", 0))
				save_using_invuln = bool(ev.get("using_invuln", false))
				break
		result.dice.append({
			"context": "save",
			# int(): stats.save can be a float (5.0), and "5.0+" reads badly in
			# the log if anything falls back to this as the displayed threshold.
			"sv": "%d+" % int(base_save),
			"ap": ap,
			"cover": "n/a (11e: cover worsens BS, not saves)",
			"save_modifier": save_modifier,
			"rolls_raw": save_rolls,
			"fails": fails,
			"failed": fails,
			"successes": save_rolls.size() - fails,
			"threshold": ("%d+" % save_needed_display) if save_needed_display > 0 else "",
			"using_invuln": save_using_invuln,
			"allocation_11e": {"order": order, "events": alloc.events}
		})
		_materialize_allocation_11e(result, target_unit, target_unit_id, alloc.remaining, alloc.models_destroyed)
		out.casualties += alloc.models_destroyed.size()
		out.damage_applied += alloc.damage_total
		out.models_destroyed.append_array(alloc.models_destroyed)

	# [DEVASTATING WOUNDS] (24.10): each critical wound inflicts D mortal
	# wounds against AT MOST one model, applied after the normal damage
	# (06.02); each crit's excess beyond the selected model is lost.
	if dev_wound_crits > 0:
		var dw_events: Array = []
		for _c in range(dev_wound_crits):
			var dmg_result = roll_variable_characteristic(damage_raw, rng)
			# Codex: Adeptus Custodes stratagems (CustodesCodex11e.gd): PRIME TARGET re-rolls one low damage roll.
			dmg_result = _cus11e_codex().auto_single_reroll_damage(dmg_result, damage_raw, bs_actor_unit, rng)
			dmg_result = SMAbilitiesC11eScript.reroll_damage(dmg_result, damage_raw, bs_actor_unit, rng, bool(opts.get("is_melee", false)))  # WP-M4c: Total Obliteration
			var dmg = dmg_result.value
			if dmg_result.rolled:
				damage_roll_log.append(dmg_result)
			if melta_value > 0 and melta_box[0] > 0:
				dmg += melta_value
				melta_box[0] -= 1
			# BIGGER SHELLS (Dread Mob, pushed): +1 Damage vs MONSTER/VEHICLE
			dmg += get_bigger_shells_damage_bonus(bs_actor_unit, target_unit)
			dmg += plus_damage
			if has_half_damage:
				dmg = apply_half_damage(dmg)
			var dw_minus_dmg = EffectPrimitivesData.get_effect_minus_damage(target_unit)
			if dw_minus_dmg > 0:
				dmg = max(1, dmg - dw_minus_dmg)
			if dw_fnp_value > 0 and dmg > 0:
				var fnp_result = roll_feel_no_pain(dmg, dw_fnp_value, rng)
				result.dice.append({
					"context": "feel_no_pain",
					"source": "devastating_wounds",
					"rolls": fnp_result.rolls,
					"fnp_value": dw_fnp_value,
					"wounds_prevented": fnp_result.wounds_prevented,
					"wounds_remaining": fnp_result.wounds_remaining,
					"total_wounds": dmg
				})
				dmg = fnp_result.wounds_remaining
			if dmg <= 0:
				continue
			var dw = Allocation.apply_devastating_wounds_11e(target_unit, 1, dmg, preferred_targets)
			dw_events.append_array(dw.events)
			_materialize_allocation_11e(result, target_unit, target_unit_id, dw.remaining, dw.models_destroyed)
			out.casualties += dw.models_destroyed.size()
			out.damage_applied += dw.applied
			out.models_destroyed.append_array(dw.models_destroyed)
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
		# Feel No Pain vs mortal wounds (incl. Aegis of the Emperor, WP-C3).
		var mw_left := mortal_wounds_after_fnp(target, mw, rng, result.dice, false, "explosives_11e")
		var out = Allocation.apply_mortal_wounds_11e(target, mw_left, CasualtyPreference.engine_auto_preference(target, board))
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
		# Feel No Pain vs mortal wounds (incl. Aegis of the Emperor, WP-C3).
		var enemy_left := mortal_wounds_after_fnp(target, enemy_mw, rng, result.dice, false, "crushing_impact_11e")
		var out = Allocation.apply_mortal_wounds_11e(target, enemy_left, CasualtyPreference.engine_auto_preference(target, board))
		_materialize_allocation_11e(result, target, target_unit_id, out.remaining, out.models_destroyed)
		result.casualties += out.models_destroyed.size()
	if self_mw > 0 and not unit.is_empty():
		var self_left := mortal_wounds_after_fnp(unit, self_mw, rng, result.dice, false, "crushing_impact_11e")
		var self_out = Allocation.apply_mortal_wounds_11e(unit, self_left, CasualtyPreference.engine_auto_preference(unit, board))
		_materialize_allocation_11e(result, unit, unit_id, self_out.remaining, self_out.models_destroyed)
		result.casualties += self_out.models_destroyed.size()
	print("RulesEngine: [15.06] CRUSHING IMPACT %s vs %s — T%d rolls %s -> %d enemy / %d self mortal wound(s)" % [unit_id, target_unit_id, toughness, str(rolls), enemy_mw, self_mw])
	return result


## KRUNCHIN' DESCENT (Taktikal Brigade): just after a Stormboyz unit ends a
## Charge move, roll one D6 for each of its models within Engagement Range of
## the selected enemy unit — each 4+ inflicts 1 mortal wound (max 6).
## CRUSHING IMPACT (Bully Boyz) reuses this with threshold 5 (4 while a
## Waaagh! is active); UNSTOPPABLE MOMENTUM (Da Big Hunt) with er_only=false
## (one die per model in the unit) and bonus dice vs the Prey.
static func resolve_krunchin_descent(unit_id: String, target_unit_id: String, board: Dictionary, rng: RNGService = null, threshold: int = 4, er_only: bool = true, bonus_dice: int = 0) -> Dictionary:
	if rng == null:
		rng = make_rng()
	var unit = board.get("units", {}).get(unit_id, {})
	var target = board.get("units", {}).get(target_unit_id, {})
	var dice_count := 0
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		var pos1 = _get_model_position(model)
		if pos1 == Vector2.ZERO:
			continue
		if not er_only:
			dice_count += 1
			continue
		for enemy_model in target.get("models", []):
			if not enemy_model.get("alive", true):
				continue
			var pos2 = _get_model_position(enemy_model)
			if pos2 == Vector2.ZERO:
				continue
			var effective_er = _get_effective_engagement_range_rules(pos1, pos2, board)
			if Measurement.is_in_engagement_range_shape_aware(model, enemy_model, effective_er):
				dice_count += 1
				break
	dice_count += maxi(bonus_dice, 0)
	var rolls = rng.roll_d6(dice_count) if dice_count > 0 else []
	var mw := 0
	for r in rolls:
		if r >= threshold:
			mw += 1
	mw = mini(mw, 6)
	var result = {"diffs": [], "dice": [{"context": "krunchin_descent", "rolls": rolls, "mortal_wounds": mw}],
		"mortal_wounds": mw, "models_in_er": dice_count, "casualties": 0}
	if mw > 0 and not target.is_empty():
		# Feel No Pain vs mortal wounds (incl. Aegis of the Emperor, WP-C3).
		var mw_left := mortal_wounds_after_fnp(target, mw, rng, result.dice, false, "krunchin_descent")
		var out = Allocation.apply_mortal_wounds_11e(target, mw_left, CasualtyPreference.engine_auto_preference(target, board))
		_materialize_allocation_11e(result, target, target_unit_id, out.remaining, out.models_destroyed)
		result.casualties = out.models_destroyed.size()
	print("RulesEngine: KRUNCHIN' DESCENT %s vs %s — %d model(s) in ER, rolls %s -> %d mortal wound(s)" % [unit_id, target_unit_id, dice_count, str(rolls), mw])
	return result


# 24.28 [PRECISION] (audit #13): the ATTACKER may promote ONE allocation
# group containing a CHARACTER model that is VISIBLE to at least one
# attacking model. `chosen_gid` (the attacker's pick, e.g. from the
# AllocationGroupOverlay / action payload) wins when eligible; otherwise
# the first eligible group is auto-picked. Empty actor/board skips the
# visibility gate (legacy callers), "" = no promotion.
static func _precision_group_11e(weapon_has_precision_flag: bool, target_unit: Dictionary, actor_unit: Dictionary = {}, board: Dictionary = {}, chosen_gid: String = "") -> String:
	if not weapon_has_precision_flag or GameConstants.edition < 11:
		return ""
	var eligible: Array = []
	for g in Allocation.build_groups(target_unit):
		if not g.character:
			continue
		if actor_unit.is_empty() or _character_group_visible_to_attackers(g, target_unit, actor_unit, board):
			eligible.append(str(g.id))
	if eligible.is_empty():
		if not actor_unit.is_empty():
			print("RulesEngine: [24.28] PRECISION — no CHARACTER group is visible to the attackers; no promotion")
		return ""
	if chosen_gid != "":
		if chosen_gid in eligible:
			return chosen_gid
		print("RulesEngine: [24.28] requested PRECISION group %s is not an eligible visible CHARACTER group — auto-picking %s" % [chosen_gid, eligible[0]])
	return eligible[0]

# 24.28: at least one alive model of the CHARACTER group is visible to at
# least one alive attacking model — the same per-model gates as the live
# targeting path (13.09 hidden detection, 13.10/13.11 sight lines, base LoS).
static func _character_group_visible_to_attackers(group: Dictionary, target_unit: Dictionary, actor_unit: Dictionary, board: Dictionary) -> bool:
	var t_models = target_unit.get("models", [])
	var tm = Engine.get_main_loop().root.get_node_or_null("TerrainManager")
	for actor_model in actor_unit.get("models", []):
		if not actor_model.get("alive", true):
			continue
		var a_pos = _get_model_position(actor_model)
		if not a_pos:
			continue
		for mi_raw in group.get("model_indices", []):
			var mi = int(mi_raw)
			if mi < 0 or mi >= t_models.size():
				continue
			var t_model = t_models[mi]
			if not t_model.get("alive", true):
				continue
			var t_pos = _get_model_position(t_model)
			if not t_pos:
				continue
			if tm != null:
				# 13.09 hidden gate; 13.10/13.11 sight lines are judged by the
				# base LoS check (EnhancedLineOfSight 11e branch) below.
				if not tm.hidden_model_visible_to(t_model, target_unit, actor_model):
					continue
			if _check_line_of_sight(a_pos, t_pos, board, actor_model, t_model):
				return true
	return false

## UI helper (audit #13): the [PRECISION] character groups the attacker may
## promote for this save batch — group ids + display labels, visibility-gated.
static func precision_eligible_groups_11e(save_data: Dictionary, board: Dictionary) -> Array:
	if GameConstants.edition < 11 or not save_data.get("has_precision", false):
		return []
	var target_unit = board.get("units", {}).get(str(save_data.get("target_unit_id", "")), {})
	var actor_unit = board.get("units", {}).get(str(save_data.get("shooter_unit_id", "")), {})
	if target_unit.is_empty():
		return []
	var combined = _build_attached_allocation_unit_11e(str(save_data.get("target_unit_id", "")), board)
	var scratch = combined.unit
	var out: Array = []
	for g in Allocation.build_groups(scratch):
		if not g.character:
			continue
		if not actor_unit.is_empty() and not _character_group_visible_to_attackers(g, scratch, actor_unit, board):
			continue
		var label = str(g.id)
		var indices = g.get("model_indices", [])
		if not indices.is_empty():
			var m = scratch.get("models", [])[int(indices[0])]
			label = get_model_display_label(m, scratch)
		out.append({"id": str(g.id), "label": label})
	return out


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
# saves_failed, save_rolls, order_used, groups, sources,
# models_destroyed}. `sources[i]` maps virtual model index i back to
# {unit_id, model_index}; `models_destroyed` holds virtual indices. The
# caller applies the diffs (overlay → GameState; phase → snapshot) — both
# are idempotent `set` ops.
#
# `opts` (all optional — the overlay's interactive two-step flow):
#   forced_save_rolls: Array — replay these save dice instead of rolling
#                      (used to re-run the batch after a save Command
#                      Re-roll, or with the defender's casualty picks)
#   preferred_targets: Array — virtual model indices in the defender's
#                      chosen casualty order (see Allocation.apply_save_rolls)
static func resolve_allocation_batch_11e(save_data: Dictionary, order: Array, board: Dictionary, rng: RNGService = null, opts: Dictionary = {}) -> Dictionary:
	if rng == null:
		rng = make_rng()
	var target_unit_id = str(save_data.get("target_unit_id", ""))
	var live_unit = board.get("units", {}).get(target_unit_id, {})
	var out = {
		"is_allocation_11e": true, "target_unit_id": target_unit_id,
		"diffs": [], "dice": [], "casualties": 0, "damage_applied": 0,
		"saves_passed": 0, "saves_failed": 0, "save_rolls": [],
		"order_used": [], "groups": [], "sources": [], "models_destroyed": [],
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
	out.sources = sources

	var wounds_to_save = int(save_data.get("wounds_to_save", 0))
	var dev_crits = int(save_data.get("devastating_wounds", 0)) if save_data.get("has_devastating_wounds", false) else 0
	var ap = int(save_data.get("ap", 0))
	var damage_raw = str(save_data.get("damage_raw", str(save_data.get("damage", 1))))
	var fnp_value = get_unit_fnp_vs(live_unit, bool(save_data.get("is_psychic", false)), false)

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
			"precision_group": _precision_group_11e(save_data.get("has_precision", false), scratch_unit,
				board.get("units", {}).get(str(save_data.get("shooter_unit_id", "")), {}), board,
				str(save_data.get("precision_group_choice", ""))),
			"actor_unit": board.get("units", {}).get(str(save_data.get("shooter_unit_id", "")), {}),
			"is_melee": bool(save_data.get("is_melee", false)),  # Codex: Adeptus Custodes (11e) Flare Shields vs ranged only (WP-C46)
			# WP-O6: melee +D (save_data from prepare_melee_save_resolution)
			"plus_damage": int(save_data.get("da_bigger_damage_bonus", 0)),
			"melta_value": melta_value,
			"melta_wounds": melta_wounds,
			"half_damage": get_unit_half_damage(live_unit),
			"fnp_value": fnp_value,
			"is_psychic": bool(save_data.get("is_psychic", false)),
			"forced_save_rolls": opts.get("forced_save_rolls", []),
			"preferred_targets": opts.get("preferred_targets", []),
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
	out.models_destroyed = applied.get("models_destroyed", [])
	for d in result.dice:
		if d.get("context", "") == "save":
			out.save_rolls = d.get("rolls_raw", [])
			out.saves_failed = int(d.get("fails", 0))
			out.saves_passed = out.save_rolls.size() - out.saves_failed
			out.order_used = d.get("allocation_11e", {}).get("order", [])
	if out.order_used.is_empty():
		out.order_used = order
	return out


# ARMOUR SAVES IN THE GAME LOG: translate an 11e allocation batch's dice into
# the canonical block shapes every log renderer already understands —
# "save_roll" (GameLogPanel's visible Save row + ShootingPhase's save detail
# line) and "feel_no_pain". The 11e batch is resolved wholesale inside
# AllocationGroupOverlay and reported back as one summary, so its raw blocks
# use the engine-internal "save" context with `fails`/`rolls` keys that no
# renderer matches. Without this translation the game log jumped straight from
# the wound roll to "No models destroyed" with nothing showing the saves that
# were the reason nothing died.
# `ctx`: {target_unit_name, weapon_name} — the attribution the 10e path puts on
# its own save blocks. Unknown contexts pass through untouched.
static func normalize_allocation_11e_dice(summary: Dictionary, ctx: Dictionary = {}) -> Array:
	var target_name := str(ctx.get("target_unit_name", ""))
	var weapon_name := str(ctx.get("weapon_name", ""))
	var out: Array = []
	for blk in summary.get("dice", []):
		var context := str(blk.get("context", ""))
		if context == "save":
			var normalized: Dictionary = blk.duplicate(true)
			var rolls: Array = blk.get("rolls_raw", [])
			var failed := int(blk.get("failed", blk.get("fails", 0)))
			normalized["context"] = "save_roll"
			normalized["failed"] = failed
			normalized["successes"] = int(blk.get("successes", rolls.size() - failed))
			# `threshold` is the roll the defender needed; fall back to the raw
			# armour save when the batch predates the enriched block.
			var threshold := str(blk.get("threshold", ""))
			normalized["threshold"] = threshold if threshold != "" else str(blk.get("sv", ""))
			normalized["original_save"] = int(str(blk.get("sv", "7+")).replace("+", ""))
			normalized["using_invuln"] = bool(blk.get("using_invuln", false))
			normalized["weapon_name"] = weapon_name
			normalized["target_unit_name"] = target_name
			out.append(normalized)
		elif context == "feel_no_pain":
			var fnp: Dictionary = blk.duplicate(true)
			# The batch path stores its dice under "rolls"; every renderer
			# reads "rolls_raw".
			if not fnp.has("rolls_raw"):
				fnp["rolls_raw"] = blk.get("rolls", [])
			fnp["threshold"] = "%d+" % int(blk.get("fnp_value", 0))
			fnp["target_unit_name"] = target_name
			out.append(fnp)
		else:
			out.append(blk)
	return out


# ============================================================================
# 19.02/19.03: THE ATTACHED UNIT IS ONE TARGET
# ============================================================================
# While a CHARACTER is attached to a bodyguard unit the two are ONE Attached
# unit for all rules purposes, so the CHARACTER is NEVER selectable as a
# target in its own right — attacks are made against the Attached unit and the
# allocation rules (05.03 grouping / 05.04 CHARACTER groups last) are what
# reach the leader, once every bodyguard model is dead (or via [PRECISION]).
# The ranged path has enforced this for a while (get_eligible_targets skips
# attached_to units, validate_shoot rejects them); these helpers exist so the
# MELEE path can enforce the same rule from one implementation.

# The id of the unit that IS the Attached unit for targeting purposes: the
# bodyguard for an attached character, otherwise unit_id itself.
# BOTH sides of the linkage are checked — the character's `attached_to`
# back-pointer AND every bodyguard's attachment_data.attached_characters
# forward list — because saves and tutorial fixtures exist where only one side
# was written (FightPhase._fight_is_attached_character does the same).
# A bodyguard with no models left is NOT returned: 19.05 makes the Leader its
# own unit again once its Bodyguard unit is destroyed (CharacterAttachmentManager
# .check_bodyguard_destroyed writes that back), and redirecting to a wiped unit
# would make the surviving character untargetable.
static func attached_unit_target_id(unit_id: String, board: Dictionary) -> String:
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	if unit.is_empty():
		return unit_id
	var back_ptr = unit.get("attached_to", null)
	if back_ptr != null and str(back_ptr) != "" and _unit_has_alive_model(units.get(str(back_ptr), {})):
		return str(back_ptr)
	for other_id in units:
		if other_id == unit_id:
			continue
		if unit_id in units[other_id].get("attachment_data", {}).get("attached_characters", []):
			if _unit_has_alive_model(units[other_id]):
				return str(other_id)
	return unit_id

# True when unit_id is a CHARACTER attached to a (still-standing) bodyguard,
# i.e. a component of an Attached unit that cannot be targeted on its own.
static func is_attached_character(unit_id: String, board: Dictionary) -> bool:
	return attached_unit_target_id(unit_id, board) != unit_id

# Every model of the whole Attached unit headed by unit_id: its own models
# plus its attached characters'. Engagement range / visibility for TARGETING
# is measured against all of them — the leader's model is part of the unit, so
# a bodyguard whose only model within Engagement Range is its attached
# CHARACTER is still a legal melee target.
# Mirrors attached_unit_target_id's 19.05 guard: a bodyguard with no models
# left no longer heads an Attached unit (its leaders are units of their own
# again), so its characters are NOT folded in — otherwise the wiped squad
# would keep showing up as a target on the strength of the leader's model,
# alongside the leader's own entry. NOTE this is deliberately NOT the rule
# _build_attached_allocation_unit_11e uses: mid-batch, wounds that finish off
# the last bodyguard model must still spill onto the CHARACTER group.
static func attached_unit_models(unit_id: String, board: Dictionary) -> Array:
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	var out: Array = []
	out.append_array(unit.get("models", []))
	if not _unit_has_alive_model(unit):
		return out
	for char_id in unit.get("attachment_data", {}).get("attached_characters", []):
		var char_unit = units.get(str(char_id), {})
		if char_unit.is_empty():
			continue
		out.append_array(char_unit.get("models", []))
	return out

# The component unit ids of the Attached unit headed by unit_id: the unit
# itself first, then each attached CHARACTER that still exists. 19.03 makes
# these ONE unit — they pile in together, fight in ONE activation and
# consolidate together — but the state model keeps them as separate unit dicts
# so each component keeps its own stats, abilities, weapons and model indices.
# Callers that must act "as one unit" walk this list rather than folding the
# dicts together (see FightPhase's fight-group handling).
# BOTH sides of the linkage are walked, for the same reason attached_unit_target_id
# does: saves and tutorial fixtures exist where only ONE side was written. In
# audit_370_bgnt_shoot, for instance, Boyz Beta's attached_characters names one of
# its two Warbosses and the other is linked only by its own `attached_to` — the
# forward list alone dropped that leader out of his own unit, so anything measured
# across "the whole Attached unit" (engagement, stratagem eligibility, fight
# groups) silently ignored his model.
static func attached_unit_component_ids(unit_id: String, board: Dictionary) -> Array:
	var units = board.get("units", {})
	var out: Array = [unit_id]
	var unit = units.get(unit_id, {})
	if unit.is_empty():
		return out
	for char_id in unit.get("attachment_data", {}).get("attached_characters", []):
		if units.has(str(char_id)) and str(char_id) != unit_id and not out.has(str(char_id)):
			out.append(str(char_id))
	for other_id in units:
		if other_id == unit_id or out.has(str(other_id)):
			continue
		var back_ptr = units[other_id].get("attached_to", null)
		if back_ptr != null and str(back_ptr) == unit_id:
			out.append(str(other_id))
	return out

# Just the attached CHARACTER components of the Attached unit headed by unit_id
# (i.e. attached_unit_component_ids minus the head). Call this instead of reading
# `attachment_data.attached_characters` directly: that forward list alone misses a
# leader who is linked only by his own `attached_to` back-pointer, which real
# saves contain (see attached_unit_component_ids).
static func attached_character_ids(unit_id: String, board: Dictionary) -> Array:
	var out: Array = attached_unit_component_ids(unit_id, board)
	out.erase(unit_id)
	return out

static func _unit_has_alive_model(unit: Dictionary) -> bool:
	for m in unit.get("models", []):
		if m.get("alive", true):
			return true
	return false


# Fold a bodyguard unit and its attached character units (linked via
# attachment_data.attached_characters) into ONE virtual unit for the 11e
# allocation rules. Returns {unit, sources} where sources[i] maps virtual
# model index i back to {unit_id, model_index}.
# An attached CHARACTER passed in as the target is resolved back to its
# bodyguard first (19.02): the caller is asking for "the Attached unit that
# contains this unit", and building the fold from the character alone would
# hand back a lone CHARACTER group and let every wound land on the leader
# while its bodyguard models stood untouched.
static func _build_attached_allocation_unit_11e(target_unit_id: String, board: Dictionary) -> Dictionary:
	var units = board.get("units", {})
	target_unit_id = attached_unit_target_id(target_unit_id, board)
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
			CustodesAbilities11eScript.decorate_alloc_model(cm, char_unit)  # WP-C7: Praesidium Shield bearer tag, Moment Shackle 3+ InSv ("this model")
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

	# Calculate total attacks — roll variable attacks per model (D3, D6, etc.)
	var attacks_raw = weapon_profile.get("attacks_raw", str(weapon_profile.get("attacks", 1)))

	# WP-O6: Codex: Orks (11e) datasheet abilities for this batch (auto-resolve).
	var ork6: Dictionary = ork11e_ab_mods(actor_unit, target_unit, weapon_profile, false, board, model_ids)

	var base_attacks = 0
	var attacks_roll_log = []
	# MA-10: Track per-model BS for each attack (supports stats_override.ballistic_skill)
	var bs_per_attack = []
	var cover_model_per_attack = []  # audit #7: firing model per attack (13.08 per-model cover)
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
	# SYNCHRONISED INFERNO (Silent Hunters): ranged weapons gain BLAST vs any target
	if not deck_fraggers_blast and EffectPrimitivesData.has_effect_grant_blast(actor_unit):
		var wp_type_gb = weapon_profile.get("type", "")
		if wp_type_gb.to_lower() == "ranged" or weapon_profile.get("range", 0) > 0:
			if not is_blast_weapon(weapon_id, board):
				deck_fraggers_blast = true
				print("RulesEngine: Effect-granted BLAST (auto-resolve) applied to %s" % weapon_id)

	# DRIVE-BY BUSTIN' (Codex: Orks 11e): per-attack record of whether the
	# attack is made with a weapon selected for the Firing Deck ability.
	var ork11e_fd_attack: Array = []
	for model_id in model_ids:
		# ATTACHED CHARACTERS: see the same block in _resolve_assignment_hits.
		var model = resolve_bearer_model(actor_unit, model_id, board)
		var model_bs = _get_model_effective_bs(model, resolve_bearer_unit(actor_unit, model_id, board), weapon_profile)
		if model_bs != weapon_profile.get("bs", 4):
			has_bs_override = true

		# Roll variable attacks for each model separately (per 10e rules)
		var attacks_result = roll_variable_characteristic(attacks_raw, rng)
		var model_attacks = attacks_result.value

		# WP-O6 (Blitz Dem Gitz!, ...): +A per attacking model (auto-resolve)
		model_attacks += int(ork6.get("attacks", 0))

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
		# Audit #7: and its identity, for per-attack 13.08 cover.
		for _j in range(model_attacks):
			bs_per_attack.append(model_bs)
			cover_model_per_attack.append(model)
			ork11e_fd_attack.append(ork11e_is_firing_deck_bearer(model_id))
		if attacks_result.rolled:
			attacks_roll_log.append(attacks_result)


	if has_bs_override:
		print("RulesEngine: [MA-10][auto-resolve] Per-model BS override active — models have different BS values")

	if attacks_roll_log.size() > 0:
		print("RulesEngine: [auto-resolve] Variable attacks rolled (%s) for %d models → %d total base attacks" % [attacks_raw, model_ids.size(), base_attacks])

	# RAPID FIRE KEYWORD: Check if weapon is Rapid Fire and models are in half range
	# MA-10: Track rapid fire attacks with per-model BS
	# MA-14: Only models in this assignment's model_ids count for RF (per-model weapons)
	var rapid_fire_value = get_rapid_fire_value(weapon_id, board)
	# UMBRAL PROSECUTION (Silent Hunters): ranged weapons gain [RAPID FIRE X]
	# for the phase — use the granted value when it beats the native one.
	var granted_rapid_fire = EffectPrimitivesData.get_effect_grant_rapid_fire(actor_unit)
	if granted_rapid_fire > rapid_fire_value:
		rapid_fire_value = granted_rapid_fire
		print("RulesEngine: Effect-granted RAPID FIRE %d applied to %s" % [granted_rapid_fire, weapon_id])
	# DAKKAMEK (Speedwaaagh!): the Mekaniak-selected Vehicle's ranged weapons gain
	# [RAPID FIRE 1] until the start of the bearer's next turn.
	if rapid_fire_value < 1 and str(weapon_profile.get("type", "Ranged")).to_lower() != "melee" \
			and (actor_unit.get("flags", {}).get("dakkamek_rapid_fire", false) or actor_unit.get("flags", {}).get("effect_grant_rapid_fire_1", false)):
		rapid_fire_value = 1
		print("RulesEngine: DAKKAMEK — [RAPID FIRE 1] granted to %s's ranged weapon %s" % [actor_unit_id, weapon_id])
	# BRUTAL BROADSIDE (Rollin' Deff): ranged weapons gain [RAPID FIRE X] with
	# X = the weapon's Attacks characteristic (fixed-value Attacks only —
	# dice-valued Attacks keep their native rapid fire; documented).
	if str(weapon_profile.get("type", "Ranged")).to_lower() != "melee" \
			and actor_unit.get("flags", {}).get("effect_brutal_broadside", false):
		var bb_attacks_raw = str(weapon_profile.get("attacks", "1"))
		if bb_attacks_raw.is_valid_int():
			rapid_fire_value = maxi(rapid_fire_value, int(bb_attacks_raw))
			print("RulesEngine: BRUTAL BROADSIDE — [RAPID FIRE %d] on %s (X = Attacks)" % [rapid_fire_value, weapon_id])
		else:
			print("RulesEngine: BRUTAL BROADSIDE — %s has dice-valued Attacks (%s), rapid fire grant skipped" % [weapon_id, bb_attacks_raw])
	# CLOSE-RANGE DAKKA (Codex: Orks 11e): [RAPID FIRE 1], or +1 to the value of
	# an existing [RAPID FIRE] (applied after every other RAPID FIRE grant).
	# WP-O5 Supa-snazz Dakka: Snazzguns have [RAPID FIRE 1] (not cumulative with their own).
	rapid_fire_value = maxi(rapid_fire_value, int(ork11e_enh().rapid_fire_grant(actor_unit, weapon_profile)))
	var ork11e_crd_bonus = ork11e_rapid_fire_bonus(actor_unit, weapon_profile)
	if ork11e_crd_bonus > 0:
		rapid_fire_value += ork11e_crd_bonus
		print("RulesEngine: CLOSE-RANGE DAKKA (auto-resolve) — %s now [RAPID FIRE %d]" % [weapon_id, rapid_fire_value])
	var rapid_fire_attacks = 0
	var models_in_half_range = 0
	if rapid_fire_value > 0:
		var weapon_range = weapon_profile.get("range", 24) + ork11e_det_range_bonus(actor_unit, weapon_profile)  # Codex: Orks (11e) Dakka! Dakka! Dakka! +3" Range while riled up (WP-O34)
		var half_range_inches = weapon_range if load("res://scripts/codex/space_marines/SMDetachmentsB.gd").full_range_rapid_fire(actor_unit) else weapon_range / 2.0  # WP-M2b Codex Fire-patterns: [RAPID FIRE] up to maximum range
		for model_id in model_ids:
			# ATTACHED CHARACTERS: a composite "<char_unit>:<model>" bearer is not
			# in actor_unit.models, so _get_model_by_id returned {} and the model
			# was skipped — a character's gun could never count as within half
			# range, silently losing its RAPID FIRE bonus attacks.
			var rf_model = resolve_bearer_model(actor_unit, model_id, board)
			if rf_model.is_empty() or not rf_model.get("alive", true):
				continue
			var closest_distance_inches = INF
			# Half range is measured to the whole TARGET unit — for an
			# Attached unit that includes its leaders (19.03), not only the
			# bodyguard models (r1:WH-3).
			for target_model in attached_unit_models(target_unit_id, board):
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
					ork11e_fd_attack.append(ork11e_is_firing_deck_bearer(model_id))
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
	var ork11e_fd_blast: int = blast_bonus_per_model * model_ids.filter(func(m): return ork11e_is_firing_deck_bearer(m)).size()
	for _j in range(blast_bonus_attacks):
		bs_per_attack.append(default_bs)
		ork11e_fd_attack.append(_j < ork11e_fd_blast)

	var total_attacks = base_attacks + rapid_fire_attacks + blast_bonus_attacks
	if assignment.has("attacks_override") and assignment.attacks_override != null:
		total_attacks = assignment.attacks_override
		rapid_fire_attacks = 0  # Override disables the rapid fire bonus tracking
		blast_bonus_attacks = 0  # Override disables the blast bonus tracking
		# MA-10: Rebuild bs_per_attack with default BS when attacks are overridden
		bs_per_attack.clear()
		ork11e_fd_attack.clear()
		for _j in range(total_attacks):
			bs_per_attack.append(default_bs)
			ork11e_fd_attack.append(not model_ids.is_empty() and model_ids.all(func(m): return ork11e_is_firing_deck_bearer(m)))

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
				var ar_bonus_model = resolve_bearer_model(actor_unit, ar_model_id, board)
				var ar_bonus_bs = _get_model_effective_bs(ar_bonus_model, resolve_bearer_unit(actor_unit, ar_model_id, board), weapon_profile)
				for _j in range(ar_bonus_value):
					bs_per_attack.append(ar_bonus_bs)
					ork11e_fd_attack.append(ork11e_is_firing_deck_bearer(ar_model_id))
			print("RulesEngine: [MA-29][auto-resolve] Ability +%d Attacks for '%s' → +%d total (%d models × %d)" % [ar_bonus_value, ar_weapon_name, ar_ability_attack_bonus, model_ids.size(), ar_bonus_value])
		else:
			print("RulesEngine: [MA-29][auto-resolve] Ability +%d Attacks exists but does not apply to '%s' (weapon filter active)" % [ar_bonus_value, ar_weapon_name])
	# Codex: Orks (11e) Try Dat Button! +1 A per model (WP-O34).
	var ork11e_a_ar := ork11e_det_attacks_per_model(actor_unit)
	if ork11e_a_ar > 0:
		for ar_model_id in model_ids:
			var ar_tdb_model = resolve_bearer_model(actor_unit, ar_model_id, board)
			var ar_tdb_bs = _get_model_effective_bs(ar_tdb_model, resolve_bearer_unit(actor_unit, ar_model_id, board), weapon_profile)
			for _j in range(ork11e_a_ar):
				bs_per_attack.append(ar_tdb_bs)
				ork11e_fd_attack.append(ork11e_is_firing_deck_bearer(ar_model_id))
		total_attacks += ork11e_a_ar * model_ids.size()
		print("RulesEngine: TRY DAT BUTTON! (auto-resolve) — +%d attack per model on %s (%d models)" % [ork11e_a_ar, ar_weapon_name, model_ids.size()])
	# Codex: Adeptus Custodes (11e) Not a Shell Wasted: the bearer's unit's ranged attacks +1 A (WP-C46).
	var cus11e_nsw_ar := cus11e_ranged_attacks_per_model(actor_unit, board)
	if cus11e_nsw_ar > 0:
		for nsw_model_id in model_ids:
			var nsw_model = resolve_bearer_model(actor_unit, nsw_model_id, board)
			var nsw_bs = _get_model_effective_bs(nsw_model, resolve_bearer_unit(actor_unit, nsw_model_id, board), weapon_profile)
			for _j in range(cus11e_nsw_ar):
				bs_per_attack.append(nsw_bs)
				ork11e_fd_attack.append(ork11e_is_firing_deck_bearer(nsw_model_id))
		total_attacks += cus11e_nsw_ar * model_ids.size()
		print("RulesEngine: NOT A SHELL WASTED (auto-resolve) — +%d attack per model on %s (%d models)" % [cus11e_nsw_ar, ar_weapon_name, model_ids.size()])

	# TORRENT KEYWORD (PRP-014): Check if weapon auto-hits (skip hit roll entirely)
	var is_torrent = is_torrent_weapon(weapon_id, board) or assignment.get("torrent", false) or bool(ork6.get("torrent", false))  # WP-O5 Temperamental Shokka (1: [TORRENT])

	# Codex: Adeptus Custodes stratagems (CustodesCodex11e.gd): PURGATION SWEEP +1/+2 A on [TORRENT] weapons.
	var ar_cus11e_bonus_a: int = int(_cus11e_codex().bonus_attacks_per_model(actor_unit, target_unit, weapon_profile, is_torrent, false)) * model_ids.size()
	if ar_cus11e_bonus_a > 0 and not (assignment.has("attacks_override") and assignment.attacks_override != null):
		total_attacks += ar_cus11e_bonus_a
		for _j in range(ar_cus11e_bonus_a):
			bs_per_attack.append(weapon_profile.get("bs", 4))
			ork11e_fd_attack.append(false)
		print("RulesEngine: PURGATION SWEEP (auto-resolve) — +%d attack(s) for [TORRENT] weapon %s" % [ar_cus11e_bonus_a, weapon_id])

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
		critical_hit_threshold = _snap_critical_hit_threshold_11e(critical_hit_threshold)
		# WP-M4a SENTINEL PROTOCOLS (Firestrike Servo-turrets): this unit's snap-shooting attacks hit on unmodified 4+.
		if SMAbilitiesAScript.snap_hit_threshold(actor_unit) > 0:
			bs = SMAbilitiesAScript.snap_hit_threshold(actor_unit)
			for sm_i in range(bs_per_attack.size()):
				bs_per_attack[sm_i] = bs
			print("RulesEngine: [WP-M4a] Sentinel Protocols — snap shooting hits on unmodified %d+" % bs)

	var cover_worsened_attacks = 0  # 13.08 — attacks whose BS the benefit of cover worsened
	var hit_threshold_display = str(bs) + "+"  # rebuilt from the effective per-attack BS before display
	var hits = 0
	var critical_hits = 0  # Unmodified 6s that hit (never for Torrent)
	var regular_hits = 0   # Non-critical hits
	# ISS-modifier-provenance: names WHERE each modifier below came from, so the
	# Dice Log and the resolution docks can say "Against All Odds: +1 to hit"
	# instead of an anonymous "+1". Purely additive — never read by the maths.
	var hit_modifiers = HitModifier.NONE
	var hit_mod_ledger: Array = []
	var heavy_bonus_applied = false
	var bgnt_penalty_applied = false
	var indirect_fire_applied = false
	var indirect_consequences: bool = false  # 11e 10.07 — set in the hit branch below
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
		weapon_has_lethal_hits = has_lethal_hits(weapon_id, board, target_unit)
		sustained_data = get_sustained_hits_value(weapon_id, board, target_unit)

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
				ModifierLedger.note(hit_mod_ledger, "Attack assignment", ModifierLedger.KIND_HIT, ModifierLedger.REROLL_ONES)
			if hit_mods.get("reroll_failed", false):
				hit_modifiers |= HitModifier.REROLL_FAILED
				ModifierLedger.note(hit_mod_ledger, "Attack assignment", ModifierLedger.KIND_HIT, ModifierLedger.REROLL_FAILED)
			if hit_mods.get("plus_one", false):
				hit_modifiers |= HitModifier.PLUS_ONE
				ModifierLedger.note(hit_mod_ledger, "Attack assignment", ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE)
			if hit_mods.get("minus_one", false):
				hit_modifiers |= HitModifier.MINUS_ONE
				ModifierLedger.note(hit_mod_ledger, "Attack assignment", ModifierLedger.KIND_HIT, ModifierLedger.MINUS_ONE)

		# EFFECT FLAGS: Check for ability/stratagem-granted hit modifiers on the attacker
		if EffectPrimitivesData.has_effect_plus_one_hit(actor_unit):
			hit_modifiers |= HitModifier.PLUS_ONE
			ModifierLedger.note(hit_mod_ledger, "Ability effect", ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE, "granted by an ability or Stratagem")
			print("RulesEngine: Effect +1 to hit (auto-resolve) applied for %s" % actor_unit_id)
		if EffectPrimitivesData.has_effect_minus_one_hit(actor_unit):
			hit_modifiers |= HitModifier.MINUS_ONE
			ModifierLedger.note(hit_mod_ledger, "Ability effect", ModifierLedger.KIND_HIT, ModifierLedger.MINUS_ONE, "imposed by an ability or Stratagem")
			print("RulesEngine: Effect -1 to hit (auto-resolve) applied for %s" % actor_unit_id)
		var reroll_hits_scope_ar = actor_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_REROLL_HITS, "")
		if reroll_hits_scope_ar == "ones":
			hit_modifiers |= HitModifier.REROLL_ONES
			ModifierLedger.note(hit_mod_ledger, "Ability effect", ModifierLedger.KIND_HIT, ModifierLedger.REROLL_ONES, "granted by an ability or Stratagem")
			print("RulesEngine: Effect re-roll 1s to hit (auto-resolve) applied for %s" % actor_unit_id)
		elif reroll_hits_scope_ar == "failed" or reroll_hits_scope_ar == "all":
			hit_modifiers |= HitModifier.REROLL_FAILED
			ModifierLedger.note(hit_mod_ledger, "Ability effect", ModifierLedger.KIND_HIT, ModifierLedger.REROLL_FAILED, "granted by an ability or Stratagem")
			print("RulesEngine: Effect re-roll hits (auto-resolve) applied for %s" % actor_unit_id)
		elif reroll_hits_scope_ar == REROLL_HITS_SCOPE_NON_CRIT:
			hit_modifiers |= _non_crit_hit_reroll_bits(actor_unit, weapon_id, board, false)
			ModifierLedger.note(hit_mod_ledger, "Ability effect", ModifierLedger.KIND_HIT, ModifierLedger.REROLL_FAILED, "re-roll hit rolls (non-critical hits too, for critical-hit weapons)")
			print("RulesEngine: Effect re-roll hit rolls (auto-resolve, fishing for crits where they matter) applied for %s / %s" % [actor_unit_id, weapon_id])

		# DAMAGED PROFILE (P1-14): Check if attacker has Damaged profile active
		if is_damaged_profile_active(actor_unit):
			hit_modifiers |= HitModifier.MINUS_ONE
			ModifierLedger.note(hit_mod_ledger, "Damaged profile", ModifierLedger.KIND_HIT, ModifierLedger.MINUS_ONE, "attacker is on its Damaged profile")
			print("RulesEngine: Damaged profile -1 to hit (auto-resolve) applied for %s" % actor_unit_id)

		# HEAVY KEYWORD: Check if weapon is Heavy and unit remained stationary
		# (at edition>=11 [HEAVY] routes through ModifierStack below — 24.16)
		if GameConstants.edition < 11 and is_heavy_weapon(weapon_id, board):
			var remained_stationary = actor_unit.get("flags", {}).get("remained_stationary", false)
			if remained_stationary:
				hit_modifiers |= HitModifier.PLUS_ONE
				ModifierLedger.note(hit_mod_ledger, "[HEAVY]", ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE, "unit remained stationary")
				heavy_bonus_applied = true

		# BIG GUNS NEVER TIRE: Apply -1 to hit for non-Pistol weapons only when shooter
		# is engaged OR target is engaged with a friendly unit (issue #337).
		# (10e only — 11e replaces BGNT with close-quarters shooting 10.06 +
		# engaged-M/V targeting 17.03, applied via ModifierStack below)
		if GameConstants.edition < 11 and big_guns_never_tire_penalty_applies(actor_unit, target_unit, board):
			# Only apply penalty if this is NOT a Pistol weapon
			if not is_pistol_weapon(weapon_id, board):
				hit_modifiers |= HitModifier.MINUS_ONE
				ModifierLedger.note(hit_mod_ledger, "Big Guns Never Tire", ModifierLedger.KIND_HIT, ModifierLedger.MINUS_ONE, "shooting while engaged")
				bgnt_penalty_applied = true
				print("RulesEngine: BGNT -1 to hit (auto-resolve) applied for %s (weapon %s)" % [actor_unit_id, weapon_id])

		# STEALTH (T2-1): Check if target unit has Stealth (from effect or base ability)
		# Stealth imposes -1 to hit rolls against this unit for ranged attacks
		if GameConstants.edition < 11 and EffectPrimitivesData.has_effect_stealth(target_unit):
			hit_modifiers |= HitModifier.MINUS_ONE
			ModifierLedger.note(hit_mod_ledger, "Stealth", ModifierLedger.KIND_HIT, ModifierLedger.MINUS_ONE, "target has Stealth (granted)")
			print("RulesEngine: Stealth (effect-granted) applied -1 to hit against %s" % target_unit_id)
		elif GameConstants.edition < 11 and has_stealth_ability(target_unit):
			hit_modifiers |= HitModifier.MINUS_ONE
			ModifierLedger.note(hit_mod_ledger, "Stealth", ModifierLedger.KIND_HIT, ModifierLedger.MINUS_ONE, "target has the Stealth ability")
			print("RulesEngine: Stealth (ability) applied -1 to hit against %s" % target_unit_id)

		# INDIRECT FIRE (T2-4): Apply -1 to hit modifier for Indirect Fire weapons
		# Issue #371: per 10e RAW, the -1 penalty + Benefit of Cover only apply
		# when the target is NOT visible to any model in the firing unit.
		var indirect_target_visible = is_indirect_fire and _has_los_to_target_unit(actor_unit_id, target_unit_id, board)
		# 11e (10.07): the WHILE SHOOTING consequences (cover, no hit re-rolls,
		# the 1-5 / 1-3 fail band) follow the shooting type the player SELECTED
		# for the unit, not whether the target happens to be visible. Callers
		# stamp it on the assignment (_stamp_shooting_type); without it (legacy
		# callers) fall back to "unseen target ⇒ indirect" — the only legal way
		# to shoot an unseen target.
		indirect_consequences = _indirect_consequences_apply(is_indirect_fire, indirect_target_visible, assignment)
		# 11e (10.07): the indirect penalty is a harsh UNMODIFIED fail band (see
		# hit_fail_band below), not a -1 modifier — gate the 10e -1 off at e11.
		if is_indirect_fire and not indirect_target_visible and GameConstants.edition < 11:
			hit_modifiers |= HitModifier.MINUS_ONE
			ModifierLedger.note(hit_mod_ledger, "[INDIRECT FIRE]", ModifierLedger.KIND_HIT, ModifierLedger.MINUS_ONE, "target is not visible")
			indirect_fire_applied = true
			print("RulesEngine: [INDIRECT FIRE] Applied -1 to hit for weapon '%s' (target not visible)" % weapon_profile.get("name", weapon_id))
		elif is_indirect_fire and indirect_target_visible:
			print("RulesEngine: [INDIRECT FIRE] No penalty — target IS visible to firing unit")

		# TANK HUNTERS (OA-11): +1 to Hit when attacking MONSTER or VEHICLE targets (auto-resolve)
		if has_tank_hunters_vs_target(actor_unit, target_unit):
			hit_modifiers |= HitModifier.PLUS_ONE
			ModifierLedger.note(hit_mod_ledger, "Tank Hunters", ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE, "target is a MONSTER or VEHICLE")
			print("RulesEngine: TANK HUNTERS (auto-resolve) — +1 to hit for %s (target is MONSTER/VEHICLE)" % actor_unit_id)

		# WALL OF DAKKA (OA-50): +1 to Hit on ranged attacks vs targets within half weapon range (auto-resolve)
		var wall_of_dakka_bonus_ar = get_wall_of_dakka_hit_bonus(actor_unit, target_unit, weapon_profile)
		if wall_of_dakka_bonus_ar > 0:
			hit_modifiers |= HitModifier.PLUS_ONE
			ModifierLedger.note(hit_mod_ledger, "Wall of Dakka", ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE, "target within half range")
			print("RulesEngine: WALL OF DAKKA (auto-resolve) — +1 to hit for %s (target within half range)" % actor_unit_id)

		# TARGETIN' SQUIGS / HUGE SHOW-OFFS: effect-granted +1 to hit on ranged attacks
		if actor_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_PLUS_ONE_HIT_RANGED, false):
			hit_modifiers |= HitModifier.PLUS_ONE
			ModifierLedger.note(hit_mod_ledger, "Ability effect", ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE, "+1 to hit on ranged attacks (Targetin' Squigs / Huge Show-offs)")
			print("RulesEngine: +1 to hit (ranged) — effect_plus_one_hit_ranged on %s" % actor_unit_id)
		# ARMOURED DUELLISTS (Blitz Brigade): +1 to hit vs MONSTER/VEHICLE
		if get_armoured_duellists_bonus(actor_unit, target_unit) > 0:
			hit_modifiers |= HitModifier.PLUS_ONE
			ModifierLedger.note(hit_mod_ledger, "Armoured Duellists", ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE, "target is a MONSTER or VEHICLE")
			print("RulesEngine: ARMOURED DUELLISTS (auto-resolve) — +1 to hit vs %s (MONSTER/VEHICLE)" % target_unit_id)

		# LONG, UNCONTROLLED BURSTS (Codex: Orks 11e): ranged attacks that target a
		# FLY unit can re-roll the hit roll.
		if ork11e_long_uncontrolled_bursts_reroll(actor_unit, target_unit):
			hit_modifiers |= HitModifier.REROLL_FAILED
			ModifierLedger.note(hit_mod_ledger, "Long, Uncontrolled Bursts", ModifierLedger.KIND_HIT, ModifierLedger.REROLL_FAILED, "target has FLY")
			print("RulesEngine: LONG, UNCONTROLLED BURSTS (auto-resolve) — re-roll hit rolls vs FLY target %s" % target_unit_id)
		# DRIVE-BY BUSTIN' (Codex: Orks 11e): +1 to hit for weapons selected for the
		# Firing Deck ability — the whole batch when every attack is a Firing Deck
		# one, otherwise per attack in the hit roll loop below.
		if ork11e_drive_by_bustin_active(actor_unit) and not ork11e_fd_attack.is_empty() and not ork11e_fd_attack.has(false):
			hit_modifiers |= HitModifier.PLUS_ONE
			ModifierLedger.note(hit_mod_ledger, "Drive-by Bustin'", ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE, "weapon selected for the Firing Deck ability")
			print("RulesEngine: DRIVE-BY BUSTIN' (auto-resolve) — +1 to hit for Firing Deck weapon %s" % weapon_id)
		# DAT'S OUR LOOT! (OA-12): Re-roll Hit rolls of 1 on ranged attacks;
		# full Hit re-roll if target is within range of any objective marker (auto-resolve).
		var dats_our_loot_scope_ar = get_dats_our_loot_reroll_scope(actor_unit, target_unit, board)
		if dats_our_loot_scope_ar == "failed":
			hit_modifiers |= HitModifier.REROLL_FAILED
			ModifierLedger.note(hit_mod_ledger, "Dat's Our Loot!", ModifierLedger.KIND_HIT, ModifierLedger.REROLL_FAILED, "target within range of an objective marker")
			print("RulesEngine: DAT'S OUR LOOT! (auto-resolve) — full hit re-roll for %s (target near objective)" % actor_unit_id)
		elif dats_our_loot_scope_ar == "ones":
			hit_modifiers |= HitModifier.REROLL_ONES
			ModifierLedger.note(hit_mod_ledger, "Dat's Our Loot!", ModifierLedger.KIND_HIT, ModifierLedger.REROLL_ONES, "target within range of an objective marker")
			print("RulesEngine: DAT'S OUR LOOT! (auto-resolve) — re-roll hit rolls of 1 for %s" % actor_unit_id)

		# WP-O6: Codex: Orks (11e) datasheet abilities (Strafing Run, Dodge Dis!, Ammo Runts, ...)
		hit_modifiers = ork11e_ab_hit_bits(hit_modifiers, hit_mod_ledger, ork6)

		# Codex: Orks (11e) detachment rules (WP-O34): +1 to hit (Skyborne Loons / Seekerz), re-roll 1s (Wreckin' and Lootin').
		var ork11e_hp_src_ar := ork11e_det_hit_plus_one(actor_unit, target_unit, false, board)
		if ork11e_hp_src_ar != "":
			hit_modifiers |= HitModifier.PLUS_ONE
			ModifierLedger.note(hit_mod_ledger, ork11e_hp_src_ar, ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE)
		var ork11e_rr_src_ar := ork11e_det_hit_reroll_ones(actor_unit, target_unit, false, board)
		if ork11e_rr_src_ar != "":
			hit_modifiers |= HitModifier.REROLL_ONES
			ModifierLedger.note(hit_mod_ledger, ork11e_rr_src_ar, ModifierLedger.KIND_HIT, ModifierLedger.REROLL_ONES)

		# Codex: Adeptus Custodes (11e) detachment rules / enhancements (CustodesDetachments.gd, WP-C46).
		hit_modifiers = cus11e_apply_hit_effects(hit_modifiers, hit_mod_ledger, actor_unit, target_unit, false, board, {"model_ids": model_ids})

		# ── ISS-016/053 (11e): hit-side modifier stack — cover/STEALTH worsen
		# BS (13.08/24.33), plunging fire improves it (22.05), [HEAVY] is +1
		# to the hit roll (24.16). The ±1 dice-roll cap lives in ModifierStack.
		if GameConstants.edition >= 11 and not is_overwatch:
			var ms_firing_models: Array = []
			for ms_mid in model_ids:
				# ATTACHED CHARACTERS: composite bearers resolved through the board.
				# Without this a character-only assignment produced an EMPTY
				# attacker_models list, so cover / STEALTH / plunging fire were
				# evaluated with no firing model to measure from.
				var ms_m = resolve_bearer_model(actor_unit, ms_mid, board)
				if not ms_m.is_empty() and ms_m.get("alive", true):
					ms_firing_models.append(ms_m)
			var ms_stack = ModifierStack.collect_hit_context_11e(actor_unit, target_unit, weapon_profile, board, {"attacker_models": ms_firing_models, "per_attack_cover": true})
			# Codex: Adeptus Custodes SALVUS (CustodesKatah.gd): the harmful BS /
			# hit-roll entries of the stack are ignored.
			var cus11e_salvus_ignored: Array = _cus11e_katah().salvus_filter_stack(actor_unit, ms_stack)
			# Codex: Adeptus Custodes stratagems (CustodesCodex11e.gd): INEVITABLE ANNIHILATION ignores the harmful BS / hit-roll entries.
			cus11e_salvus_ignored.append_array(_cus11e_codex().filter_hit_stack(actor_unit, ms_stack, false))
			# Codex: Space Marines (11e) stratagems (SMCodex11e.gd): MIGHT OF THE MACHINE SPIRIT ignores the harmful BS / hit-roll entries.
			cus11e_salvus_ignored.append_array(_sm11e_codex().filter_hit_stack(actor_unit, ms_stack, false))
			var ms_bs_delta = ms_stack.net("bs")
			var ms_hit_net_pre = ms_stack.net("hit_roll")
			# WP-O6 Walking Bastion ignores BS/hit modifiers like [PSYCHIC] does.
			var ms_is_psychic: bool = is_psychic_weapon(weapon_id, board) or bool(ork6.get("ignore_hit_penalties", false))
			# ISS-047 (24.29): [PSYCHIC] attacks may ignore any or all BS/hit
			# modifiers — the engine ignores exactly the harmful ones.
			if ms_is_psychic:
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
				ModifierLedger.note_stack(hit_mod_ledger, ms_stack.sources("bs"), ModifierLedger.KIND_HIT, ModifierLedger.WORSEN_BS if ms_bs_delta > 0 else ModifierLedger.IMPROVE_BS)
			# Audit #7 (13.08 per attacking model): each attack takes the
			# cover worsening based on ITS OWN firing model's view of the
			# target. Attacks with no recorded firing model (overrides,
			# bonus attacks) fall back to the first firing model's view.
			# (SALVUS / INEVITABLE ANNIHILATION ignore that BS worsening too; WP-O6 Codex: Orks [IGNORES COVER].)
			if not ms_is_psychic and not _cus11e_katah().salvus_active(actor_unit) and not _cus11e_codex().ignores_bs_worsening(actor_unit, false) and not _sm11e_codex().ignores_bs_worsening(actor_unit, false) and not ModifierStack.attack_ignores_cover(actor_unit, weapon_profile, {"ignores_cover": bool(ork6.get("ignores_cover", false))}):
				var pa_terrain = Engine.get_main_loop().root.get_node_or_null("TerrainManager")
				if pa_terrain != null:
					# WP-O6 Madcap Artillery: a wobbled unit's targets have the benefit of cover.
					var pa_strat_cover: bool = target_unit.get("flags", {}).get("stratagem_cover", false) or bool(ork6.get("target_cover", false))
					# 11e 10.07: an [INDIRECT FIRE] attack at an unseen target
					# has the benefit of cover per attack, regardless of terrain
					# — at 11e that worsens the attacker's BS here (13.08), not
					# the save.
					var pa_indirect_cover: bool = indirect_consequences
					var pa_fallback: Dictionary = ms_firing_models[0] if not ms_firing_models.is_empty() else {}
					var pa_cover_cache: Dictionary = {}
					var pa_covered_count := 0
					for ms_i in range(bs_per_attack.size()):
						var pa_model: Dictionary = cover_model_per_attack[ms_i] if ms_i < cover_model_per_attack.size() else pa_fallback
						var pa_key := str(pa_model.get("id", "_"))
						if not pa_cover_cache.has(pa_key):
							pa_cover_cache[pa_key] = pa_strat_cover or pa_indirect_cover or pa_terrain.unit_has_cover_11e(target_unit, pa_model)
						if pa_cover_cache[pa_key]:
							bs_per_attack[ms_i] += 1
							pa_covered_count += 1
					cover_worsened_attacks = pa_covered_count
					if pa_covered_count > 0:
						print("RulesEngine: [13.08 per-model] benefit of cover — %d/%d attack(s) worsened by 1 BS" % [pa_covered_count, bs_per_attack.size()])
			var ms_hit_net = ms_hit_net_pre
			if ms_hit_net > 0:
				hit_modifiers |= HitModifier.PLUS_ONE
				ModifierLedger.note_stack(hit_mod_ledger, ms_stack.sources("hit_roll"), ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE)
				if "heavy" in ms_stack.sources("hit_roll"):
					heavy_bonus_applied = true
				print("RulesEngine: [11e MODIFIERS] +1 to hit (%s)" % str(ms_stack.sources("hit_roll")))
			elif ms_hit_net < 0:
				hit_modifiers |= HitModifier.MINUS_ONE
				ModifierLedger.note_stack(hit_mod_ledger, ms_stack.sources("hit_roll"), ModifierLedger.KIND_HIT, ModifierLedger.MINUS_ONE)
				print("RulesEngine: [11e MODIFIERS] -1 to hit (%s)" % str(ms_stack.sources("hit_roll")))
			if _cus11e_katah().salvus_active(actor_unit):
				ModifierLedger.note(hit_mod_ledger, "Salvus (Ka'tah)", ModifierLedger.KIND_HIT, ModifierLedger.IGNORED,
					"BS worsening (incl. benefit of cover) and hit-roll penalties ignored%s" % ((": " + ", ".join(cus11e_salvus_ignored)) if not cus11e_salvus_ignored.is_empty() else ""))

		# Codex: Adeptus Custodes SALVUS (CustodesKatah.gd): ignore every -1 to
		# hit (the +1s are kept — "can ignore" is the attacker's choice).
		if _cus11e_katah().salvus_active(actor_unit) and (hit_modifiers & HitModifier.MINUS_ONE):
			hit_modifiers = hit_modifiers & ~HitModifier.MINUS_ONE
			ModifierLedger.note(hit_mod_ledger, "Salvus (Ka'tah)", ModifierLedger.KIND_HIT, ModifierLedger.IGNORED, "hit-roll penalties ignored")
			ModifierLedger.mark_ignored(hit_mod_ledger, ModifierLedger.KIND_HIT, [ModifierLedger.MINUS_ONE])
			print("RulesEngine: SALVUS — ignoring hit-roll penalties for %s" % actor_unit_id)
		# Codex: Adeptus Custodes stratagems (CustodesCodex11e.gd): GOLDEN LIGHT (-1), HONOURED INTERRED (re-roll 1s), INEVITABLE ANNIHILATION (ignore -1).
		hit_modifiers = _cus11e_codex().apply_hit_bits(hit_modifiers, actor_unit, target_unit, false, board, hit_mod_ledger)
		# Codex: Space Marines (11e) stratagems (SMCodex11e.gd): HURTLING TARGETS / UMBRAL EVASION (-1), MIGHT OF THE MACHINE SPIRIT (ignore -1).
		hit_modifiers = _sm11e_codex().apply_hit_bits(hit_modifiers, actor_unit, target_unit, false, hit_mod_ledger)

		# Roll to hit with modifiers - CRITICAL HIT TRACKING (PRP-031)
		hit_rolls = rng.roll_d6(total_attacks)

		# ISS-012: per-roll evaluation shared with the melee path
		# (AttackSequence.evaluate_hit_roll). INDIRECT FIRE's unmodified-1-3
		# fail band (#371, unseen targets only) and CONVERSION's crit
		# threshold (T4-16) are parameters.
		var hit_fail_band = 1
		if indirect_consequences:
			# 11e (10.07): unmodified 1-5 fails (need a 6), unless the firing unit
			# remained stationary AND the target is visible to a friendly unit, in
			# which case 1-3 fails (need 4+). 10e: 1-3 fails (4+).
			hit_fail_band = _indirect_hit_fail_band_11e(actor_unit_id, target_unit_id, board) if GameConstants.edition >= 11 else 3
			print("RulesEngine: [10.07] INDIRECT shooting — unmodified 1-%d fails (target visible to shooter: %s, type: %s)" % [hit_fail_band, str(indirect_target_visible), str(assignment.get("shooting_type", "inferred"))])
			# 11e (10.07): "You cannot re-roll hit rolls" for every attack an
			# [INDIRECT FIRE] weapon makes while the unit shoots indirect.
			if GameConstants.edition >= 11 and (hit_modifiers & (HitModifier.REROLL_ONES | HitModifier.REROLL_FAILED | HitModifier.REROLL_NON_CRIT)):
				hit_modifiers &= ~(HitModifier.REROLL_ONES | HitModifier.REROLL_FAILED | HitModifier.REROLL_NON_CRIT)
				print("RulesEngine: [11e 10.07] INDIRECT — hit re-rolls suppressed")
		# 11e 15.09 SNAP SHOOTING (FIRE OVERWATCH 15.08): "You cannot re-roll
		# hit rolls." Re-roll-hits abilities and stratagem
		# flags are all stripped for every snap attack.
		if is_overwatch and GameConstants.edition >= 11 and (hit_modifiers & (HitModifier.REROLL_ONES | HitModifier.REROLL_FAILED | HitModifier.REROLL_NON_CRIT)):
			hit_modifiers &= ~(HitModifier.REROLL_ONES | HitModifier.REROLL_FAILED | HitModifier.REROLL_NON_CRIT)
			print("RulesEngine: [11e 15.09] SNAP — hit re-rolls suppressed")
		# WP-M4a SENTINEL PROTOCOLS: snap-shooting attacks hit on UNMODIFIED 4+ — no hit-roll modifier applies.
		if is_overwatch and SMAbilitiesAScript.snap_hit_threshold(actor_unit) > 0 and (hit_modifiers & (HitModifier.PLUS_ONE | HitModifier.MINUS_ONE)):
			hit_modifiers &= ~(HitModifier.PLUS_ONE | HitModifier.MINUS_ONE)
			print("RulesEngine: [WP-M4a] Sentinel Protocols — unmodified 4+: hit-roll modifiers dropped")
		# DRIVE-BY BUSTIN': a batch mixing Firing Deck and the transport's own
		# weapons gets the +1 only on its Firing Deck attacks.
		var ork11e_fd_mixed: bool = ork11e_drive_by_bustin_active(actor_unit) and ork11e_fd_attack.has(true) and ork11e_fd_attack.has(false)
		if ork11e_fd_mixed:
			ModifierLedger.note(hit_mod_ledger, "Drive-by Bustin'", ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE, "Firing Deck weapons' attacks only")
		# SPEEDIEST FREEKS (Codex: Orks 11e): unmodified hit rolls of 1-3 fail.
		hit_fail_band = ork11e_ranged_hit_fail_band(target_unit, hit_fail_band)
		var cus11e_ar_hit_evals: Array = []  # per-die records for MAGNA IMPERATOR (WP-C46)
		for i in range(hit_rolls.size()):
			var roll = hit_rolls[i]
			# MA-10: Use per-model BS for this attack's threshold
			var attack_bs = bs_per_attack[i] if i < bs_per_attack.size() else bs
			var ork11e_attack_mods: int = hit_modifiers
			if ork11e_fd_mixed and i < ork11e_fd_attack.size() and ork11e_fd_attack[i]:
				ork11e_attack_mods |= HitModifier.PLUS_ONE
			var hit_eval = AttackSequence.evaluate_hit_roll(roll, attack_bs, ork11e_attack_mods, critical_hit_threshold, rng, hit_fail_band)
			# Codex: Adeptus Custodes stratagems (CustodesCodex11e.gd): PRIME TARGET re-rolls one failed hit roll (auto-resolve).
			hit_eval = _cus11e_codex().auto_single_reroll_hit(hit_eval, roll, actor_unit, attack_bs, ork11e_attack_mods, critical_hit_threshold, rng, hit_fail_band, indirect_consequences)
			modified_rolls.append(hit_eval.final_roll)
			cus11e_ar_hit_evals.append({"raw": roll, "final": hit_eval.final_roll, "is_hit": hit_eval.is_hit, "is_crit": hit_eval.is_crit, "rerolled": hit_eval.rerolled, "reroll_from": hit_eval.reroll_from, "reroll_to": hit_eval.reroll_to})
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

		# Codex: Adeptus Custodes MAGNA IMPERATOR (Emperor's Chosen, WP-C46): re-roll one hit roll (auto-resolve).
		if not indirect_consequences and not is_overwatch:
			var cus11e_mh_ar: Dictionary = cus11e_magna_reroll_hit(actor_unit, cus11e_ar_hit_evals, modified_rolls, reroll_data, bs_per_attack, bs, hit_modifiers, critical_hit_threshold, rng, hit_fail_band, hit_mod_ledger)
			hits += int(cus11e_mh_ar.hit)
			critical_hits += int(cus11e_mh_ar.crit)
			regular_hits += int(cus11e_mh_ar.hit) - int(cus11e_mh_ar.crit)
			# WP-M2a Ironstorm Auto-targeters / Martial Paragon: re-roll one hit roll (auto-resolve).
			var sm11e_mh_ar: Dictionary = sm11e_reroll_one_hit(actor_unit, false, cus11e_ar_hit_evals, modified_rolls, reroll_data, bs_per_attack, bs, hit_modifiers, critical_hit_threshold, rng, hit_fail_band, hit_mod_ledger)
			hits += int(sm11e_mh_ar.hit)
			critical_hits += int(sm11e_mh_ar.crit)
			regular_hits += int(sm11e_mh_ar.hit) - int(sm11e_mh_ar.crit)

		# DAKKASTORM (OA-16): Every successful Hit roll scores a Critical Hit (ranged only, auto-resolve)
		if has_dakkastorm(actor_unit) and regular_hits > 0:
			print("RulesEngine: DAKKASTORM (auto-resolve) — converting %d regular hits to critical hits for %s" % [regular_hits, actor_unit_id])
			critical_hits += regular_hits
			regular_hits = 0

		# Check for Lethal Hits keyword
		weapon_has_lethal_hits = has_lethal_hits(weapon_id, board, target_unit)
		# OA-10: Ammo Runt / unit effect flags — Lethal Hits from abilities or stratagems (ranged)
		if not weapon_has_lethal_hits and EffectPrimitivesData.has_effect_lethal_hits(actor_unit):
			weapon_has_lethal_hits = true
			print("RulesEngine:   LETHAL HITS granted by unit effect flag (e.g., Ammo Runt)")
		# BLITZA FIRE (Kult of Speed): ranged-scoped Lethal Hits flag
		if not weapon_has_lethal_hits and actor_unit.get("flags", {}).get("effect_lethal_hits_ranged", false):
			weapon_has_lethal_hits = true
			print("RulesEngine:   LETHAL HITS granted by ranged effect flag (BLITZA FIRE)")
		# TRY DAT BUTTON! (Dread Mob): rolled Button Effect — ranged LETHAL HITS
		if not weapon_has_lethal_hits and actor_unit.get("flags", {}).get("effect_try_dat_lethal_ranged", false):
			weapon_has_lethal_hits = true
			print("RulesEngine:   LETHAL HITS granted by TRY DAT BUTTON! (Dread Mob)")
		# WP-O6: Codex: Orks (11e) datasheet abilities (Pulsa Rokkit, Bust 'Em, ...)
		if not weapon_has_lethal_hits and bool(ork6.get("lethal", false)):
			weapon_has_lethal_hits = true
			print("RulesEngine:   LETHAL HITS granted by a Codex: Orks (11e) datasheet ability")

		# SUSTAINED HITS (PRP-011): Generate bonus hits on critical hits
		sustained_data = get_sustained_hits_value(weapon_id, board, target_unit)

		# HERE BE LOOT (OA-1): Freebooter Krew — Sustained Hits 1 near loot objective (ranged)
		if sustained_data.value == 0 and FactionAbilityManager.check_here_be_loot_sustained_hits(actor_unit, target_unit, board):
			sustained_data = {"value": 1, "is_dice": false}
			print("RulesEngine:   SUSTAINED HITS 1 granted by Here Be Loot (Freebooter Krew detachment)")
		# DAKKASTORM (Kult of Speed): ranged SUSTAINED HITS 1 (2 within 9")
		var kos_ds_val = get_dakkastorm_sustained_value(actor_unit, target_unit)
		if kos_ds_val > int(sustained_data.value):
			sustained_data = {"value": kos_ds_val, "is_dice": false}
			print("RulesEngine:   SUSTAINED HITS %d granted by DAKKASTORM (Kult of Speed)" % kos_ds_val)
		# TARGETIN' GIZMOS (Rollin' Deff): ranged SUSTAINED HITS 1 during a Waaagh!
		var tg_val = FactionAbilityManager.targetin_gizmos_sustained(actor_unit)
		if tg_val > int(sustained_data.value):
			sustained_data = {"value": tg_val, "is_dice": false}
			print("RulesEngine:   SUSTAINED HITS %d granted by TARGETIN' GIZMOS (Waaagh! active)" % tg_val)
		# DAKKA! DAKKA! DAKKA! (More Dakka! detachment): ranged SUSTAINED HITS 1
		# for ORKS INFANTRY/WALKER while the Waaagh! is active
		if int(sustained_data.value) == 0 and FactionAbilityManager.unit_has_more_dakka_waaagh_sustained(actor_unit):
			sustained_data = {"value": 1, "is_dice": false}
			print("RulesEngine:   SUSTAINED HITS 1 granted by DAKKA! DAKKA! DAKKA! (More Dakka! detachment, Waaagh! active)")
		# TRY DAT BUTTON! (Dread Mob): rolled Button Effect — ranged SUSTAINED HITS 1
		if int(sustained_data.value) == 0 and actor_unit.get("flags", {}).get("effect_try_dat_sustained_ranged", false):
			sustained_data = {"value": 1, "is_dice": false}
			print("RulesEngine:   SUSTAINED HITS 1 granted by TRY DAT BUTTON! (Dread Mob)")
		# NEVER ENOUGH DAKKA / DAKKASTORM / VINDICTIVE ARTILLERISTS (Codex: Orks 11e):
		# ranged [SUSTAINED HITS 1] (a weapon's own SUSTAINED HITS X is kept).
		var ork11e_sh_val = ork11e_ranged_sustained_hits(actor_unit)
		if int(sustained_data.value) == 0 and ork11e_sh_val > 0:
			sustained_data = {"value": ork11e_sh_val, "is_dice": false}
			print("RulesEngine:   SUSTAINED HITS %d granted by a Codex: Orks (11e) stratagem" % ork11e_sh_val)
		# WP-O6: More Dakka / Even More Dakka (riled up): ranged [SUSTAINED HITS 1]
		if int(sustained_data.value) == 0 and int(ork6.get("sustained", 0)) > 0:
			sustained_data = {"value": int(ork6.get("sustained", 0)), "is_dice": false}
			print("RulesEngine:   SUSTAINED HITS %d granted by a Codex: Orks (11e) datasheet ability" % int(ork6.get("sustained", 0)))

		# Codex: Space Marines (11e) stratagems (SMCodex11e.gd): HEADHUNTER DOCTRINE / RELENTLESS ASSAULT / STRIKE FROM THE SHADOWS.
		var sm11e_g: Dictionary = _sm11e_codex().attack_grants(actor_unit, target_unit, false)
		if not weapon_has_lethal_hits and str(sm11e_g.lethal) != "":
			weapon_has_lethal_hits = true
			print("RulesEngine:   LETHAL HITS granted by %s" % str(sm11e_g.lethal))
		if int(sustained_data.value) == 0 and int(sm11e_g.sustained) > 0:
			sustained_data = {"value": int(sm11e_g.sustained), "is_dice": false}
			print("RulesEngine:   SUSTAINED HITS %d granted by a Codex: Space Marines stratagem" % int(sm11e_g.sustained))

		sustained_result = roll_sustained_hits(critical_hits, sustained_data, rng)
		sustained_bonus_hits = sustained_result.bonus_hits

		# Total hits for wound rolls = regular hits + bonus hits from Sustained
		# (Critical hits with Lethal Hits auto-wound, but their Sustained bonus hits still roll)
		total_hits_for_wounds = hits + sustained_bonus_hits
		cus11e_det().note_ranged_hits(actor_unit, weapon_id, target_unit_id, hits)  # Codex: Adeptus Custodes (11e) Auriferous Orb — BLINDING LIGHT targets (WP-C46)

		# The displayed target must match what each die was judged against —
		# bs_per_attack carries the effective (cover/plunging-adjusted) BS.
		# The fail band's source: 10.07 indirect shooting, or only SPEEDIEST
		# FREEKS (Codex: Orks 11e) on an ordinary shot — don't call that "indirect".
		hit_threshold_display = _hit_threshold_display(bs, bs_per_attack, cover_worsened_attacks, hit_fail_band,
			"indirect" if indirect_consequences else "fails on 1-%d" % hit_fail_band)
		result.dice.append({
			"context": "to_hit",
			"threshold": hit_threshold_display,
			"rolls_raw": hit_rolls,
			"rolls_modified": modified_rolls,
			"rerolls": reroll_data,
			"modifiers_applied": hit_modifiers,
			"modifier_ledger": hit_mod_ledger,
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
		# Unmodified rolls up to this value fail regardless of BS (INDIRECT
		# FIRE 10.07, SPEEDIEST FREEKS) — the dice log shows the band (r5:F10).
		# Only written when wider than the core unmodified-1 fail, so every
		# other dice block is unchanged (ISS-012 attack goldens).
		if hit_fail_band > 1:
			result.dice[-1]["hit_fail_band"] = hit_fail_band

	if hits == 0 and sustained_bonus_hits == 0:
		var ar_miss_weapon_name = weapon_profile.get("name", weapon_id)
		var ar_miss_log = "%s → %s with %s - No hits" % [actor_unit.get("meta", {}).get("name", actor_unit_id), target_unit.get("meta", {}).get("name", target_unit_id), ar_miss_weapon_name]
		if not hit_rolls.is_empty():
			ar_miss_log += " [%s] vs %s" % [", ".join(hit_rolls.map(func(r): return str(r))), hit_threshold_display]
		result.log_text = ar_miss_log
		return result

	# GROT SHIELDS (Codex: Orks 11e): intercepted hits end their attack sequence;
	# the Gretchin unit's mortal wounds join this assignment's diffs.
	var ar_gs = ork11e_grot_shields_intercept(actor_unit_id, target_unit, critical_hits, regular_hits, sustained_bonus_hits, sustained_data, is_torrent, board, rng)
	if ar_gs.active and ar_gs.intercepted > 0:
		critical_hits = ar_gs.critical_hits
		regular_hits = ar_gs.regular_hits
		sustained_bonus_hits = ar_gs.sustained_bonus_hits
		hits = critical_hits + regular_hits
		total_hits_for_wounds = hits + sustained_bonus_hits
		result.diffs.append_array(ar_gs.diffs)
		for ar_gs_d in ar_gs.diffs:
			_apply_diff_to_board(board, ar_gs_d)
		result.dice.append({"context": "grot_shields", "message": ar_gs.log_text,
			"intercepted": ar_gs.intercepted, "gretchin_unit_id": ar_gs.gretchin_unit_id,
			"target_unit_id": target_unit_id})
		if total_hits_for_wounds <= 0:
			result.log_text = ar_gs.log_text
			return result

	# Roll to wound - LETHAL HITS (PRP-010) + SUSTAINED HITS (PRP-011)
	# TORRENT (PRP-014): Torrent weapons skip hit roll but still roll to wound normally
	var strength = weapon_profile.get("strength", 4)
	# WP-O6: Codex: Orks (11e) datasheet-ability strength modifiers (auto-resolve)
	if int(ork6.get("strength", 0)) != 0:
		strength += int(ork6.get("strength", 0))
		print("RulesEngine: [WP-O6] ranged strength +%d (auto-resolve) → S%d" % [int(ork6.get("strength", 0)), strength])
	# MOBILE DAKKASTORM (Speedwaaagh!): +2 Strength for a SPEED FREEKS/TRUKK unit's
	# ranged attacks against the marked enemy unit (marker holds the user's player).
	if target_unit.get("flags", {}).get("mobile_dakkastorm_marked", false) \
			and int(actor_unit.get("owner", 0)) != int(target_unit.get("owner", -1)) \
			and (unit_has_keyword(actor_unit, "SPEED FREEKS") or unit_has_keyword(actor_unit, "TRUKK")):
		var pre_s_md = strength
		strength += 2
		print("RulesEngine: MOBILE DAKKASTORM (auto-resolve) — ranged strength %d → %d (+2 vs marked %s)" % [pre_s_md, strength, target_unit_id])
	# Codex: Adeptus Custodes stratagems (CustodesCodex11e.gd): TIP OF THE TALON +1 S vs a target within 9".
	strength += int(_cus11e_codex().ranged_strength_bonus(actor_unit, target_unit, board))
	# Codex: Space Marines (11e) STRIKE FROM THE SHADOWS (SMCodex11e.gd): +1 S.
	strength += int(_sm11e_codex().attack_grants(actor_unit, target_unit, false).strength)
	strength += ork11e_det_strength_bonus(actor_unit, weapon_id, board)  # Codex: Orks (11e) Try Dat Button! / Powers of da Waaagh! (WP-O34)
	var toughness = _get_attached_unit_toughness(target_unit, board)  # P2-90: Use bodyguard T for attached units
	# OA-44: DED GLOWY AMMO — -1T to enemy INFANTRY within 6" of Kaptin Badrukk (auto-resolve)
	var ded_glowy_penalty_ar = get_ded_glowy_ammo_toughness_penalty(target_unit, board)
	if ded_glowy_penalty_ar > 0:
		toughness = max(1, toughness - ded_glowy_penalty_ar)
		print("RulesEngine: DED GLOWY AMMO (auto-resolve) — INFANTRY target T reduced by %d to T%d" % [ded_glowy_penalty_ar, toughness])
	toughness = ork11e_det_toughness(actor_unit, target_unit, toughness)  # Codex: Orks (11e) Unpredictable Genius — Runtified (WP-O34)
	var wound_threshold = _calculate_wound_threshold(strength, toughness)

	# DEVASTATING WOUNDS (PRP-012): Check if weapon has Devastating Wounds
	var ar_weapon_has_devastating_wounds = has_devastating_wounds(weapon_id, board, target_unit)
	# Issue #374 Headwoppa's Killchoppa (auto-resolve path): unit-level
	# effect_devastating_wounds grants DEVASTATING WOUNDS to the bearer's
	# melee weapons.
	if not ar_weapon_has_devastating_wounds and actor_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_DEVASTATING_WOUNDS, false):
		ar_weapon_has_devastating_wounds = true
		print("RulesEngine: Headwoppa's Killchoppa — unit-level effect_devastating_wounds applied (auto-resolve)")
	if not ar_weapon_has_devastating_wounds and bool(ork6.get("devastating", false)):  # WP-O5 Supa-glowy Fing
		ar_weapon_has_devastating_wounds = true
		print("RulesEngine: [WP-O5] [DEVASTATING WOUNDS] granted by a Codex: Orks (11e) enhancement (auto-resolve)")
	# 24.10 (audit #17): attacker may decline the mortal-wound conversion.
	if GameConstants.edition >= 11 and ar_weapon_has_devastating_wounds \
			and str(assignment.get("devastating_wounds_choice", "")) == "normal":
		ar_weapon_has_devastating_wounds = false
		print("RulesEngine: [24.10] DEVASTATING WOUNDS — attacker declined the mortal-wound conversion (auto-resolve)")

	# ANTI-[KEYWORD] X+: Get critical wound threshold (6 normally, lower if Anti matches target)
	var ar_critical_wound_threshold = get_critical_wound_threshold(weapon_id, target_unit, board)
	ar_critical_wound_threshold = mini(ar_critical_wound_threshold, int(ork11e_enh().anti_threshold(ork6, target_unit)))  # WP-O5 Supa-glowy Fing [ANTI-INFANTRY 4+]

	# ROLLING LOOT-HEAP (OA-6): Grant Anti-Vehicle 4+ from stratagem flag
	if actor_unit.get("flags", {}).get("effect_rolling_loot_heap", false):
		if unit_has_keyword(target_unit, "VEHICLE"):
			ar_critical_wound_threshold = mini(ar_critical_wound_threshold, 4)
			print("RulesEngine: ROLLING LOOT-HEAP (auto-resolve) — Anti-Vehicle 4+ active (critical wound threshold %d+)" % ar_critical_wound_threshold)

	# SPESHUL AMMO (Speedwaaagh!): non-Torrent ranged weapons gain
	# [ANTI-MONSTER 4+] and [ANTI-VEHICLE 4+].
	if actor_unit.get("flags", {}).get("effect_speshul_ammo", false):
		var ar_sa_torrent = "torrent" in str(get_weapon_profile(weapon_id, board).get("special_rules", "")).to_lower()
		if not ar_sa_torrent and (unit_has_keyword(target_unit, "MONSTER") or unit_has_keyword(target_unit, "VEHICLE")):
			ar_critical_wound_threshold = mini(ar_critical_wound_threshold, 4)
			print("RulesEngine: SPESHUL AMMO (auto-resolve) — Anti-Monster/Vehicle 4+ active (critical wound threshold %d+)" % ar_critical_wound_threshold)

	var ar_anti_keyword_active = ar_critical_wound_threshold < 6

	# TWIN-LINKED: Check if weapon has Twin-linked (re-roll all failed wound rolls)
	var ar_weapon_has_twin_linked = has_twin_linked(weapon_id, board, target_unit) or assignment.get("twin_linked", false)

	# WOUND MODIFIERS (T1-3): Build wound modifier flags for auto-resolve path
	# ISS-modifier-provenance: names WHERE each modifier below came from, so the
	# Dice Log and the resolution docks can say "Against All Odds: +1 to hit"
	# instead of an anonymous "+1". Purely additive — never read by the maths.
	var ar_wound_modifiers = WoundModifier.NONE
	var ar_wound_mod_ledger: Array = []
	if assignment.has("modifiers") and assignment.modifiers.has("wound"):
		var wound_mods = assignment.modifiers.wound
		if wound_mods.get("reroll_ones", false):
			ar_wound_modifiers |= WoundModifier.REROLL_ONES
			ModifierLedger.note(ar_wound_mod_ledger, "Attack assignment", ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_ONES)
		if wound_mods.get("reroll_failed", false):
			ar_wound_modifiers |= WoundModifier.REROLL_FAILED
			ModifierLedger.note(ar_wound_mod_ledger, "Attack assignment", ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_FAILED)
		if wound_mods.get("plus_one", false):
			ar_wound_modifiers |= WoundModifier.PLUS_ONE
			ModifierLedger.note(ar_wound_mod_ledger, "Attack assignment", ModifierLedger.KIND_WOUND, ModifierLedger.PLUS_ONE)
		if wound_mods.get("minus_one", false):
			ar_wound_modifiers |= WoundModifier.MINUS_ONE
			ModifierLedger.note(ar_wound_mod_ledger, "Attack assignment", ModifierLedger.KIND_WOUND, ModifierLedger.MINUS_ONE)
	# Twin-linked handled via WoundModifier system for re-rolls
	if ar_weapon_has_twin_linked:
		ar_wound_modifiers |= WoundModifier.REROLL_FAILED
		ModifierLedger.note(ar_wound_mod_ledger, "[TWIN-LINKED]", ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_FAILED)

	# EFFECT FLAGS: Check for ability/stratagem-granted wound modifiers on the attacker
	if EffectPrimitivesData.has_effect_plus_one_wound(actor_unit):
		ar_wound_modifiers |= WoundModifier.PLUS_ONE
		ModifierLedger.note(ar_wound_mod_ledger, "Ability effect", ModifierLedger.KIND_WOUND, ModifierLedger.PLUS_ONE, "granted by an ability or Stratagem")
		print("RulesEngine: Effect +1 to wound (auto-resolve) applied for %s" % actor_unit_id)
	if EffectPrimitivesData.has_effect_minus_one_wound(actor_unit):
		ar_wound_modifiers |= WoundModifier.MINUS_ONE
		ModifierLedger.note(ar_wound_mod_ledger, "Ability effect", ModifierLedger.KIND_WOUND, ModifierLedger.MINUS_ONE, "imposed by an ability or Stratagem")
		print("RulesEngine: Effect -1 to wound (auto-resolve) applied for %s" % actor_unit_id)
	# DEFENDER FLAG ('ARD AS NAILS): -1 to wound for attacks targeting the flagged unit
	if EffectPrimitivesData.has_effect_minus_one_wound_defense(target_unit):
		ar_wound_modifiers |= WoundModifier.MINUS_ONE
		ModifierLedger.note(ar_wound_mod_ledger, "'Ard as Nails", ModifierLedger.KIND_WOUND, ModifierLedger.MINUS_ONE, "defender's ability")
		print("RulesEngine: Defender effect -1 to wound (auto-resolve, attacks vs %s)" % target_unit_id)
	var reroll_wounds_scope_ar = actor_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_REROLL_WOUNDS, "")
	if reroll_wounds_scope_ar == "ones":
		ar_wound_modifiers |= WoundModifier.REROLL_ONES
		ModifierLedger.note(ar_wound_mod_ledger, "Ability effect", ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_ONES, "granted by an ability or Stratagem")
		print("RulesEngine: Effect re-roll 1s to wound (auto-resolve) applied for %s" % actor_unit_id)
	elif reroll_wounds_scope_ar == "failed" or reroll_wounds_scope_ar == "all":
		ar_wound_modifiers |= WoundModifier.REROLL_FAILED
		ModifierLedger.note(ar_wound_mod_ledger, "Ability effect", ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_FAILED, "granted by an ability or Stratagem")
		print("RulesEngine: Effect re-roll wounds (auto-resolve) applied for %s" % actor_unit_id)

	# LANCE (T4-1): +1 to wound if unit charged this turn. Effect-granted Lance
	# (Deathsong Scythes etc.) treats all the unit's weapons as [LANCE].
	if is_lance_weapon(weapon_id, board) or EffectPrimitivesData.has_effect_lance(actor_unit):
		var unit_charged = actor_unit.get("flags", {}).get("charged_this_turn", false)
		if unit_charged:
			ar_wound_modifiers |= WoundModifier.PLUS_ONE
			ModifierLedger.note(ar_wound_mod_ledger, "[LANCE]", ModifierLedger.KIND_WOUND, ModifierLedger.PLUS_ONE, "unit charged this turn")
			print("RulesEngine: LANCE (auto-resolve) — +1 to wound (unit charged this turn)")

	# TANK HUNTERS (OA-11): +1 to Wound when attacking MONSTER or VEHICLE targets (auto-resolve)
	if has_tank_hunters_vs_target(actor_unit, target_unit):
		ar_wound_modifiers |= WoundModifier.PLUS_ONE
		ModifierLedger.note(ar_wound_mod_ledger, "Tank Hunters", ModifierLedger.KIND_WOUND, ModifierLedger.PLUS_ONE, "target is a MONSTER or VEHICLE")
		print("RulesEngine: TANK HUNTERS (auto-resolve) — +1 to wound for %s (target is MONSTER/VEHICLE)" % actor_unit_id)

	# WP-O6: Codex: Orks (11e) datasheet abilities (Go fer da Weak Spot, Beastscent, Warpath, ...)
	ar_wound_modifiers = ork11e_ab_wound_bits(ar_wound_modifiers, ar_wound_mod_ledger, ork6)

	# HARDY BIONIKS (WP-O6, Painboss): -1 to wound for S > T attacks that target the unit (auto-resolve)
	if ork11e_ab_wound_penalty(target_unit, strength, toughness):
		ar_wound_modifiers |= WoundModifier.MINUS_ONE
		ModifierLedger.note(ar_wound_mod_ledger, ork11e_ab_wound_penalty_name(target_unit, strength, toughness), ModifierLedger.KIND_WOUND, ModifierLedger.MINUS_ONE, "attack's Strength exceeds the target's Toughness")
		print("RulesEngine: HARDY BIONIKS (auto-resolve) — -1 to wound for attacks against %s (S %d > T %d)" % [target_unit_id, strength, toughness])
	# IMPERVIOUS / effect_minus_wound_s_gt_t: -1 to wound while S > T
	var ar_sgt_mod = get_s_gt_t_wound_penalty(target_unit, board, strength, toughness)
	if ar_sgt_mod != WoundModifier.NONE:
		ar_wound_modifiers |= ar_sgt_mod
		ModifierLedger.note(ar_wound_mod_ledger, "IMPERVIOUS", ModifierLedger.KIND_WOUND, ModifierLedger.MINUS_ONE, "attack's Strength exceeds the target's Toughness")
		print("RulesEngine: S>T wound penalty (auto-resolve) — -1 to wound for attacks against %s (S %d > T %d)" % [target_unit_id, strength, toughness])
	# HULKING BRUTES (Codex: Orks 11e): -1 to wound for ranged attacks that target the unit.
	if ork11e_ranged_wound_penalty(target_unit, strength, toughness):
		ar_wound_modifiers |= WoundModifier.MINUS_ONE
		ModifierLedger.note(ar_wound_mod_ledger, "Hulking Brutes", ModifierLedger.KIND_WOUND, ModifierLedger.MINUS_ONE, "Codex: Orks stratagem on the target")
		print("RulesEngine: HULKING BRUTES (auto-resolve) — -1 to wound for ranged attacks against %s (S %d, T %d)" % [target_unit_id, strength, toughness])
	# BIGGER SHELLS FOR BIGGER GITZ (Dread Mob): +1 to wound vs MONSTER/VEHICLE
	if get_bigger_shells_wound_bonus(actor_unit, target_unit) > 0:
		ar_wound_modifiers |= WoundModifier.PLUS_ONE
		ModifierLedger.note(ar_wound_mod_ledger, "Bigger Shells for Bigger Gitz", ModifierLedger.KIND_WOUND, ModifierLedger.PLUS_ONE)
		print("RulesEngine: BIGGER SHELLS (auto-resolve) — +1 to wound vs %s (MONSTER/VEHICLE)" % target_unit_id)
	# ARMOURED DUELLISTS (Blitz Brigade): +1 to wound vs MONSTER/VEHICLE
	if get_armoured_duellists_bonus(actor_unit, target_unit) > 0:
		ar_wound_modifiers |= WoundModifier.PLUS_ONE
		ModifierLedger.note(ar_wound_mod_ledger, "Armoured Duellists", ModifierLedger.KIND_WOUND, ModifierLedger.PLUS_ONE, "target is a MONSTER or VEHICLE")
		print("RulesEngine: ARMOURED DUELLISTS (auto-resolve) — +1 to wound vs %s (MONSTER/VEHICLE)" % target_unit_id)
	# PYROMANIAKS (OA-14): Re-roll Wound rolls of 1 with Torrent weapons vs enemies within 6" (auto-resolve)
	# Full Wound re-roll if target is also within range of an objective marker.
	var ar_pyromaniaks_scope = get_pyromaniaks_reroll_scope(actor_unit, target_unit, weapon_id, board)
	if ar_pyromaniaks_scope == "failed":
		ar_wound_modifiers |= WoundModifier.REROLL_FAILED
		ModifierLedger.note(ar_wound_mod_ledger, "Pyromaniaks", ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_FAILED, "target within range of an objective marker")
		print("RulesEngine: PYROMANIAKS (auto-resolve) — full wound re-roll for %s (Torrent weapon, target within 6\" AND near objective)" % actor_unit_id)
	elif ar_pyromaniaks_scope == "ones":
		ar_wound_modifiers |= WoundModifier.REROLL_ONES
		ModifierLedger.note(ar_wound_mod_ledger, "Pyromaniaks", ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_ONES, "target within range of an objective marker")
		print("RulesEngine: PYROMANIAKS (auto-resolve) — re-roll wound rolls of 1 for %s (Torrent weapon, target within 6\")" % actor_unit_id)

	# Codex: Adeptus Custodes (11e) detachment rules / enhancements (CustodesDetachments.gd, WP-C46).
	ar_wound_modifiers = cus11e_apply_wound_effects(ar_wound_modifiers, ar_wound_mod_ledger, actor_unit, target_unit, false, strength, toughness, board, {"model_ids": model_ids})
	# Codex: Space Marines (11e) Space Wolves stratagems (SWCodex11e.gd): EYE OF THE PACK re-rolls wound rolls of 1 and 2.
	ar_wound_modifiers = _sw11e_codex().apply_wound_bits(ar_wound_modifiers, actor_unit, target_unit, false, ar_wound_mod_ledger)
	# Codex: Space Marines (11e) stratagems (SMCodex11e.gd): MIGHT OF THE MACHINE SPIRIT ignores wound-roll penalties.
	ar_wound_modifiers = _sm11e_codex().apply_wound_bits(ar_wound_modifiers, actor_unit, target_unit, false, ar_wound_mod_ledger)

	# KUSTOM DAKKA (Codex: Orks 11e): +1 to wound vs a target that is not a MONSTER/VEHICLE unit
	if ork11e_kustom_dakka_wound_bonus(actor_unit, target_unit) > 0:
		ar_wound_modifiers |= WoundModifier.PLUS_ONE
		ModifierLedger.note(ar_wound_mod_ledger, "Kustom Dakka", ModifierLedger.KIND_WOUND, ModifierLedger.PLUS_ONE, "target is not a MONSTER or VEHICLE")
		print("RulesEngine: KUSTOM DAKKA (auto-resolve) — +1 to wound vs %s" % target_unit_id)
	# Codex: Adeptus Custodes SALVUS (CustodesKatah.gd): wound-roll penalties ignored.
	if _cus11e_katah().salvus_active(actor_unit) and (ar_wound_modifiers & WoundModifier.MINUS_ONE):
		ar_wound_modifiers = ar_wound_modifiers & ~WoundModifier.MINUS_ONE
		ModifierLedger.note(ar_wound_mod_ledger, "Salvus (Ka'tah)", ModifierLedger.KIND_WOUND, ModifierLedger.IGNORED, "wound-roll penalties ignored")
		ModifierLedger.mark_ignored(ar_wound_mod_ledger, ModifierLedger.KIND_WOUND, [ModifierLedger.MINUS_ONE])
		print("RulesEngine: SALVUS (auto-resolve) — ignoring wound-roll penalties for %s" % actor_unit_id)
	ar_wound_modifiers = sw11e_ignore_wound_penalties(ar_wound_modifiers, ar_wound_mod_ledger, ork6)  # WP-S4 Gift of the Iron Wolf (Space Wolves)
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
	var cus11e_ar_wound_evals: Array = []  # per-die records for MAGNA IMPERATOR (WP-C46)

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
				# Codex: Adeptus Custodes stratagems (CustodesCodex11e.gd): PRIME TARGET re-rolls one failed wound roll (auto-resolve).
				wound_eval = _cus11e_codex().auto_single_reroll_wound(wound_eval, roll, actor_unit, ar_wound_modifiers, wound_threshold, ar_critical_wound_threshold, rng)
				cus11e_ar_wound_evals.append({"raw": roll, "is_wound": wound_eval.is_wound, "is_crit": wound_eval.is_crit, "auto_fail": wound_eval.auto_fail, "rerolled": wound_eval.rerolled, "reroll_from": wound_eval.reroll_from, "reroll_to": wound_eval.reroll_to})
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
			# Codex: Adeptus Custodes stratagems (CustodesCodex11e.gd): PRIME TARGET re-rolls one failed wound roll (auto-resolve).
			wound_eval = _cus11e_codex().auto_single_reroll_wound(wound_eval, roll, actor_unit, ar_wound_modifiers, wound_threshold, ar_critical_wound_threshold, rng)
			cus11e_ar_wound_evals.append({"raw": roll, "is_wound": wound_eval.is_wound, "is_crit": wound_eval.is_crit, "auto_fail": wound_eval.auto_fail, "rerolled": wound_eval.rerolled, "reroll_from": wound_eval.reroll_from, "reroll_to": wound_eval.reroll_to})
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

	# Codex: Adeptus Custodes MAGNA IMPERATOR (Emperor's Chosen, WP-C46): re-roll one wound roll (auto-resolve).
	var cus11e_mw_ar: Dictionary = cus11e_magna_reroll_wound(actor_unit, cus11e_ar_wound_evals, wound_rolls, ar_wound_reroll_data, ar_wound_modifiers, wound_threshold, ar_critical_wound_threshold, rng, ar_wound_mod_ledger)
	if int(cus11e_mw_ar.wound) > 0:
		wounds_from_rolls += 1
		if ar_weapon_has_devastating_wounds and int(cus11e_mw_ar.crit) > 0:
			ar_critical_wound_count += 1
		else:
			ar_regular_wound_count += 1
	# WP-M2a Ironstorm Auto-targeters / Martial Paragon: re-roll one wound roll (auto-resolve).
	var sm11e_mw_ar: Dictionary = sm11e_reroll_one_wound(actor_unit, false, cus11e_ar_wound_evals, wound_rolls, ar_wound_reroll_data, ar_wound_modifiers, wound_threshold, ar_critical_wound_threshold, rng, ar_wound_mod_ledger)
	if int(sm11e_mw_ar.wound) > 0:
		wounds_from_rolls += 1
		if ar_weapon_has_devastating_wounds and int(sm11e_mw_ar.crit) > 0:
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
		"modifier_ledger": ar_wound_mod_ledger,
		"wound_modifiers_applied": ar_wound_modifiers
	})

	if wounds_caused == 0:
		var ar_nw_weapon_name = weapon_profile.get("name", weapon_id)
		var ar_nw_log = "%s → %s with %s" % [actor_unit.get("meta", {}).get("name", actor_unit_id), target_unit.get("meta", {}).get("name", target_unit_id), ar_nw_weapon_name]
		if is_torrent:
			ar_nw_log += " - Torrent: %d auto-hits" % hits
		elif not hit_rolls.is_empty():
			ar_nw_log += " - Hit: %d/%d [%s] vs %s" % [hits, total_attacks, ", ".join(hit_rolls.map(func(r): return str(r))), hit_threshold_display]
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
	# WP-O6: Codex: Orks (11e) datasheet-ability AP (Pulsa Rokkit, Finderz Keeperz) (auto-resolve)
	if int(ork6.get("ap", 0)) > 0:
		var pre_ap_o6 = ap
		ap = improve_ap(ap, int(ork6.get("ap", 0)))
		print("RulesEngine: [WP-O6] (auto-resolve) AP %d → %d" % [pre_ap_o6, ap])
	# IMPROVE AP: effect-granted AP improvement (Umbral Prosecution ranged AP +1 etc.)
	var ar_improve_ap = EffectPrimitivesData.get_effect_improve_ap_scoped(actor_unit, "ranged")
	if ar_improve_ap > 0:
		var pre_ap_imp = ap
		ap = improve_ap(ap, ar_improve_ap)
		print("RulesEngine: Improve AP (auto-resolve) — AP %d → %d (improve by %d)" % [pre_ap_imp, ap, ar_improve_ap])
	# SPESHUL SHELLS (More Dakka!): +1 AP vs targets within 18"
	var ar_ss_bonus = get_speshul_shells_ap_bonus(actor_unit, target_unit)
	if ar_ss_bonus > 0:
		ap = improve_ap(ap, ar_ss_bonus)
		print("RulesEngine: SPESHUL SHELLS (auto-resolve) — AP improved by %d (target within 18\")" % ar_ss_bonus)
	# PREY (Da Big Hunt): +1 AP for BEAST SNAGGA attacks against the attacker's Prey
	var ar_prey_bonus = get_prey_ap_bonus(actor_unit, target_unit)
	if ar_prey_bonus > 0:
		ap = improve_ap(ap, ar_prey_bonus)
		print("RulesEngine: PREY (auto-resolve) — AP improved by %d (target is Prey)" % ar_prey_bonus)
	# TRY DAT BUTTON! (Dread Mob, 5-6): +2 AP (40kdc flatten of the Critical Wound rider)
	if actor_unit.get("flags", {}).get("effect_try_dat_ap2", false):
		ap = improve_ap(ap, 2)
		print("RulesEngine: TRY DAT BUTTON! (auto-resolve) — AP improved by 2")	# WORSEN AP: Ramshackle etc. — reduce AP of incoming attacks (min 0)
	# GLOWIN' DAKKA (Codex: Orks 11e): +1 AP vs a target within 9"
	var ar_glowin_ap = ork11e_glowin_dakka_ap_bonus(actor_unit, target_unit, board)
	if ar_glowin_ap > 0:
		ap = ork11e_improve_ap(ap, ar_glowin_ap)
		print("RulesEngine: GLOWIN' DAKKA (auto-resolve) — AP improved by %d (target within 9\")" % ar_glowin_ap)
	# Codex: Adeptus Custodes stratagems (CustodesCodex11e.gd): PSY-CHAFF VOLLEY +1 AP vs a prosecuted unit, IN AURAMITE CLAD -1 AP.
	ap = _cus11e_codex().modify_ap(ap, actor_unit, target_unit)
	# Codex: Space Marines (11e) stratagems (SMCodex11e.gd): ARMOUR OF CONTEMPT -1 AP to attacks that target the unit.
	ap = _sm11e_codex().modify_ap(ap, actor_unit, target_unit)
	var ar_worsen_ap = EffectPrimitivesData.get_effect_worsen_ap(target_unit)
	if ar_worsen_ap > 0 and ap != 0:
		var pre_ap = ap
		ap = worsen_ap(ap, ar_worsen_ap)
		print("RulesEngine: Worsen AP (auto-resolve) — AP %d → %d (worsen by %d)" % [pre_ap, ap, ar_worsen_ap])
	var damage_raw = weapon_profile.get("damage_raw", str(weapon_profile.get("damage", 1)))
	damage_raw = cus11e_damage_raw_plus(str(damage_raw), int(load("res://scripts/codex/space_marines/SMDetachmentsB.gd").ranged_damage_bonus(actor_unit, weapon_profile)))  # WP-M2b Master-forged Firearms +1 D (Codex: Space Marines 11e)
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
	var ar_fnp_value = get_unit_fnp_vs(target_unit, ar_is_psychic, false)

	# HALF DAMAGE (T4-17): Check if target unit has half-damage defensive ability
	var ar_has_half_damage = get_unit_half_damage(target_unit)
	if ar_has_half_damage:
		print("RulesEngine: Half Damage active on defender (auto-resolve) — all damage characteristics halved (round up)")

	# PRECISION (T3-4): Check if weapon has Precision keyword — mirrors interactive path
	var ar_weapon_has_precision = has_precision(weapon_id, board) or bool(ork6.get("precision", false))  # WP-S4 Headhunters: [PRECISION] vs the quarry
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
				"actor_unit": board.get("units", {}).get(actor_unit_id, {}),
				"melta_value": ar_melta_value,
				"melta_wounds": ar_melta_wounds_remaining,
				"half_damage": ar_has_half_damage,
				"fnp_value": ar_fnp_value,
				"is_psychic": ar_is_psychic,
				"precision_group": _precision_group_11e(ar_weapon_has_precision, target_unit,
					board.get("units", {}).get(actor_unit_id, {}), board,
					str(assignment.get("precision_group_choice", ""))),
				# AI defenders resolved engine-side (no overlay) still pick their
				# casualties smartly; [] for human defenders = engine default.
				"preferred_targets": CasualtyPreference.engine_auto_preference(target_unit, board),
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
			# BIGGER SHELLS (Dread Mob, pushed): +1 Damage vs MONSTER/VEHICLE
			dw_wound_damage += get_bigger_shells_damage_bonus(actor_unit, target_unit)
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
			# Fresh model: honour the defender's die-first order (AI/auto)
			# instead of always soaking on the lowest-index base.
			var reg_pick = _find_allocation_target_model(models, CasualtyPreference.engine_auto_preference(target_unit, board))
			if reg_pick >= 0:
				target_model = models[reg_pick]
				target_model_index = reg_pick
				allocation_focus_model_id = models[reg_pick].get("id", "m%d" % reg_pick)

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
			# 11e (10.07/13.08): indirect's benefit of cover worsens the
			# attacker's BS on the hit side (applied per attack above), NOT
			# the save — the save grant is the 10e mechanic.
			if is_indirect_fire and GameConstants.edition < 11 and not _has_los_to_target_unit(actor_unit_id, target_unit_id, board):
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
		auto_effect_invuln = ork11e_det_invuln(actor_unit, target_unit, auto_effect_invuln)  # Codex: Orks (11e) Unpredictable Genius — Dat's Weird (WP-O34)
		auto_effect_invuln = cus11e_invuln(target_unit, false, auto_effect_invuln)  # Codex: Adeptus Custodes (11e) Flare Shields / Eagle's Eye (WP-C46)
		if auto_effect_invuln > 0:
			if auto_model_invuln == 0 or auto_effect_invuln < auto_model_invuln:
				auto_model_invuln = auto_effect_invuln

		# Calculate save needed
		var save_result = _calculate_save_needed(auto_model_base_save, ap, has_cover, auto_model_invuln, target_unit)

		# T4-18: Read save roll modifier from target unit flags (capped at +1/-1 per 10e)
		var save_modifier = int(target_unit.get("flags", {}).get("save_modifier", 0)) + int(_sm11e_abilities_b().save_roll_bonus(target_unit))  # WP-M4b: Unyielding in the Face of the Foe
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

			# BIGGER SHELLS (Dread Mob, pushed): +1 Damage vs MONSTER/VEHICLE
			damage += get_bigger_shells_damage_bonus(actor_unit, target_unit)

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
			var model_fnp_value = get_model_fnp_vs(target_unit, target_model, ar_is_psychic, false)
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
			hit_detail += " [%s] vs %s" % [", ".join(hit_rolls.map(func(r): return str(r))), hit_threshold_display]
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

	# Units that Fell Back cannot shoot (unless special rules like
	# fall_back_and_shoot or Kult of Speed's Adrenaline Junkies)
	if flags.get("fell_back", false):
		if not EffectPrimitivesData.has_effect_fall_back_and_shoot(actor_unit) \
				and not FactionAbilityManager.unit_has_adrenaline_junkies(actor_unit):
			errors.append("Unit cannot shoot (fell back)")
			return {"valid": false, "errors": errors}

	# Legacy cannot_shoot flag check - but skip if unit advanced (since advanced units CAN shoot)
	# or has the fall_back_and_shoot effect overriding the post-Fall-Back lockout
	if flags.get("cannot_shoot", false) and not actor_advanced:
		if not (flags.get("fell_back", false) and (EffectPrimitivesData.has_effect_fall_back_and_shoot(actor_unit) \
				or FactionAbilityManager.unit_has_adrenaline_junkies(actor_unit))):
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
				# 11e (10.06 / 24.27): [CLOSE-QUARTERS] counts as [PISTOL] here, incl.
				# WP-M3b POINT-BLANK BRUTALITY's granted [CLOSE-QUARTERS] (SMCodexB.gd).
				var vs_cq: bool = GameConstants.edition >= 11 and (_snap_is_close_quarters_weapon(weapon_id, board) \
					or load("res://scripts/codex/space_marines/SMCodexB.gd").weapon_gets_close_quarters(weapon_profile, actor_unit))
				if actor_in_engagement and not is_pistol_weapon(weapon_id, board) and not vs_cq and not is_monster_or_vehicle(actor_unit):
					errors.append("Non-Pistol weapon '%s' cannot be fired while in engagement range" % weapon_profile.get("name", weapon_id))

				# ASSAULT RULES: If unit Advanced, only Assault weapons can be used
				# EXCEPTION: Units with advance_and_shoot effect (or a
				# detachment-granted unit-wide ASSAULT — More Dakka! /
				# Adrenaline Junkies) can fire all weapons after Advancing
				if actor_advanced and not is_assault_weapon(weapon_id, board) \
						and not EffectPrimitivesData.has_effect_advance_and_shoot(actor_unit) \
						and not FactionAbilityManager.unit_has_detachment_assault(actor_unit):
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

			# HUNTER PROFILES (11e 04.01.03): "Hunter profiles can only target
			# units with the specified keywords."
			if weapon_id != "" and not weapon_profile_can_target(weapon_id, target_unit, board):
				var hp_name = get_weapon_profile(weapon_id, board).get("name", weapon_id)
				errors.append("Hunter profile '%s' can only target %s units" % [hp_name, "/".join(hunter_profile_target_keywords(weapon_id, board))])

			# ATTACHED CHARACTER (19.02): while a CHARACTER is attached to a
			# bodyguard the combined Attached unit is ONE unit — the character
			# can never be selected as a separate ranged-attack target.
			# get_eligible_targets already hides these from the UI; this is the
			# authoritative engine gate for callers that bypass it (the AI
			# focus-fire plan used to shoot attached leaders directly and the
			# defender then had no bodyguard models to allocate wounds to).
			if target_unit.get("attached_to", null) != null:
				var attached_name = target_unit.get("meta", {}).get("display_name", target_unit.get("meta", {}).get("name", target_unit_id))
				errors.append("Cannot target '%s' — attached character; shoot the bodyguard unit instead" % attached_name)

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
	# 11e 19.02: attacks vs an attached unit use the HIGHEST Toughness of the
	# bodyguard models (not just the unit's single profile value).
	var own_toughness = _unit_highest_toughness(target_unit)

	# Check if this unit is a CHARACTER attached to a bodyguard
	var attached_to = target_unit.get("attached_to", null)
	if attached_to != null and attached_to != "":
		var units = board.get("units", {})
		var bodyguard_unit = units.get(attached_to, {})
		if not bodyguard_unit.is_empty():
			var bodyguard_toughness = _unit_highest_toughness(bodyguard_unit)
			if bodyguard_toughness != own_toughness:
				print("RulesEngine: P2-90/19.02 Attached unit T resolution — using highest bodyguard T%d instead of character T%d" % [bodyguard_toughness, own_toughness])
			return bodyguard_toughness

	# Bodyguard unit or standalone unit — use own (highest-model) toughness
	return own_toughness

# 11e 19.02 helper: highest Toughness among a unit's (alive) models, falling
# back to per-model meta.stats.toughness, then the unit's profile T.
static func _unit_highest_toughness(unit: Dictionary) -> int:
	var unit_t = int(unit.get("meta", {}).get("stats", {}).get("toughness", 4))
	var best = -1
	for m in unit.get("models", []):
		if not m.get("alive", true):
			continue
		var mt = m.get("meta", {}).get("stats", {}).get("toughness", null)
		if mt == null:
			mt = m.get("toughness", null)
		if mt != null:
			best = max(best, int(mt))
	return best if best > 0 else unit_t

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

	# 11e (13.08): Benefit of Cover worsens the attacking model's BS by 1 — it does
	# NOT modify the save. Cover-improves-save is a 10e-only rule. The 11e resolution
	# paths handle cover hit-side (ModifierStack) and the 11e allocation path never
	# calls this function; the two legacy callers that still reach it (overwatch
	# saves, AI/auto-allocate saves) must therefore ignore cover for saves at e11,
	# otherwise cover is double-counted (BS worsened AND save improved).
	if GameConstants.edition >= 11:
		has_cover = false

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

## 11e 15.09 SNAP SHOOTING: "Each attack only hits on an unmodified hit roll
## of 6 (irrespective of the attacking weapon's BS characteristic or any
## modifiers)". Overwatch forces BS 7, which stops BS/hit modifiers — but a
## rule that LOWERS the critical-hit threshold (Conversion X+, BLITZA FIRE,
## effect_crit_hit_on) would still make a 5 hit through AttackSequence's
## "unmodified >= crit threshold always hits" branch. Clamp it back to 6 at
## edition >= 11 (an unmodified 6 is still a critical hit). 10e unchanged.
static func _snap_critical_hit_threshold_11e(critical_hit_threshold: int) -> int:
	if GameConstants.edition >= 11 and critical_hit_threshold < 6:
		print("RulesEngine: [11e 15.09] SNAP — critical hit threshold %d+ clamped to 6+ (only unmodified 6s hit)" % critical_hit_threshold)
		return 6
	return critical_hit_threshold

## 11e (10.07): do an [INDIRECT FIRE] weapon's indirect-shooting WHILE
## SHOOTING consequences apply to this attack? At 11e they follow the shooting
## type the player SELECTED for the unit (assignment.shooting_type, stamped by
## _stamp_shooting_type): "indirect" ⇒ yes even against a VISIBLE target. An
## UNSEEN target can only be shot by selecting indirect shooting, so it always
## gets them — whatever type was stamped: no UI or AI path picks a shooting
## type yet, so SELECT_SHOOTER defaults the unit to "normal" and a stamped
## "normal" must not switch 10.07 off for a hidden target (merge review
## SHOOT-1). A visible target shot with any other type ⇒ no. 10e keeps the
## visibility rule (#371).
static func _indirect_consequences_apply(is_indirect_fire: bool, target_visible: bool, assignment: Dictionary) -> bool:
	if not is_indirect_fire:
		return false
	if GameConstants.edition >= 11 and str(assignment.get("shooting_type", "")) == "indirect":
		return true
	return not target_visible

## 10.02: the shooting type selected for the unit applies to every attack it
## makes. Copy action.payload.shooting_type onto each assignment (without
## mutating the caller's dicts) so per-attack resolution reads the selected
## type instead of inferring it.
static func _stamp_shooting_type(assignments: Array, action: Dictionary) -> Array:
	var st := str(action.get("payload", {}).get("shooting_type", ""))
	if st == "":
		return assignments
	var out: Array = []
	for a in assignments:
		if a is Dictionary and not a.has("shooting_type"):
			var stamped: Dictionary = a.duplicate()
			stamped["shooting_type"] = st
			out.append(stamped)
		else:
			out.append(a)
	return out

## 11e (10.07): the unmodified hit-roll fail band for INDIRECT shooting at a
## non-visible target. 1-5 fail (need 6); 1-3 fail (need 4+) only if the firing
## unit remained stationary AND the target is visible to one or more friendly
## units (a spotter).
static func _indirect_hit_fail_band_11e(actor_unit_id: String, target_unit_id: String, board: Dictionary) -> int:
	var units = board.get("units", {})
	var actor = units.get(actor_unit_id, {})
	if not actor.get("flags", {}).get("remained_stationary", false):
		return 5
	var owner = int(actor.get("owner", 0))
	for uid in units:
		if int(units[uid].get("owner", -1)) != owner:
			continue
		if _has_los_to_target_unit(uid, target_unit_id, board):
			return 3  # remained stationary + a friendly spotter sees the target
	return 5

static func _has_los_to_target_unit(actor_unit_id: String, target_unit_id: String, board: Dictionary) -> bool:
	"""Issue #371: returns true if any alive model of actor has LoS to any alive
	model of target, ignoring weapon range and ignoring Indirect Fire bypass.
	Used to gate Indirect Fire's -1 BS / Benefit of Cover penalties — per 10e
	those only apply when the target is NOT visible to any model in the firing
	unit."""
	return unit_sight_line(actor_unit_id, target_unit_id, board, false).has_los

## The best sight line between two UNITS, judged with EXACTLY the visibility
## predicate target eligibility uses (11e HIDDEN gate 13.09 + the base-aware
## LoS in _check_line_of_sight), ignoring weapon range and the Indirect Fire
## bypass. This is the single source of truth for "can these two units see each
## other, and along which line?" — the LoS debug overlay used to answer that
## question with its own hand-rolled pair loop (plus an extra, stricter
## TerrainManager.model_visible_11e gate the rules path never applies), so the
## overlay routinely disagreed with the target list in BOTH directions.
##
## Model pairs are tried nearest-first: that is the line a player would draw by
## hand, and it is the pair most likely to be clear, so the scan normally stops
## on the first check.
##
## `max_pairs` caps how many of those nearest pairs are tried (0 = every pair).
## Rules callers leave it unlimited; the debug overlay caps it, because a fully
## blocked 20-model mob vs a 20-model mob is 400 base-sampled visibility checks
## and the overlay sweeps every unit pair on the board. Capping only ever costs
## the overlay line ART (it may draw the nearest pair instead of the one that
## actually sees) — the VERDICT it colours by comes from the eligibility path.
##
## Returns:
##   has_los  : bool     — at least one pair has a clear, 11e-legal sight line
##   from/to  : Vector2  — the pair that PROVED sight; when nothing can see
##                         anything, the closest pair instead
##   block_at : Vector2  — (blocked only, and only when want_block_point) where
##                         the drawn line first hits the terrain that kills it
static func unit_sight_line(actor_unit_id: String, target_unit_id: String, board: Dictionary, want_block_point: bool = true, max_pairs: int = 0) -> Dictionary:
	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})
	var target_unit = units.get(target_unit_id, {})
	var out := {"has_los": false, "from": Vector2.ZERO, "to": Vector2.ZERO}
	if actor_unit.is_empty() or target_unit.is_empty():
		return out

	var pairs: Array = []
	for actor_model in actor_unit.get("models", []):
		if not actor_model.get("alive", true):
			continue
		var actor_pos = _get_model_position(actor_model)
		if not actor_pos:
			continue
		for target_model in target_unit.get("models", []):
			if not target_model.get("alive", true):
				continue
			var target_pos = _get_model_position(target_model)
			if not target_pos:
				continue
			pairs.append([actor_pos.distance_squared_to(target_pos), actor_model, target_model, actor_pos, target_pos])
	if pairs.is_empty():
		return out
	pairs.sort_custom(func(a, b): return a[0] < b[0])

	var tm_hidden = Engine.get_main_loop().root.get_node_or_null("TerrainManager") if GameConstants.edition >= 11 else null
	var budget: int = pairs.size() if max_pairs <= 0 else mini(max_pairs, pairs.size())
	for i in range(budget):
		var p = pairs[i]
		# 13.09: a hidden model is not visible beyond its detection range —
		# "visible to any model in the firing unit" must honour that too.
		if tm_hidden != null and not tm_hidden.hidden_model_visible_to(p[2], target_unit, p[1]):
			continue
		if _check_line_of_sight(p[3], p[4], board, p[1], p[2]):
			return {"has_los": true, "from": p[3], "to": p[4]}

	# Nothing can see anything — hand back the closest pair so the caller can
	# show WHICH line was judged, and where terrain killed it.
	var nearest = pairs[0]
	out["from"] = nearest[3]
	out["to"] = nearest[4]
	if want_block_point:
		var blk = EnhancedLineOfSight.block_point_for_line(nearest[3], nearest[4], board, nearest[1], nearest[2])
		if not blk.is_empty():
			out["block_at"] = blk.point
	return out

## Longest RANGED weapon reach, in inches, anywhere in the unit's loadout —
## including an attached character's guns and firing-deck loans, because
## get_unit_weapons emits those as bearers too. 0.0 when the unit carries no
## ranged weapon at all.
static func max_ranged_weapon_range_inches(actor_unit_id: String, board: Dictionary) -> float:
	var longest := 0.0
	var unit_weapons = get_unit_weapons(actor_unit_id, board)
	for model_id in unit_weapons:
		for weapon_id in unit_weapons[model_id]:
			var profile = get_weapon_profile(weapon_id, board)
			if profile.is_empty():
				continue
			# "Melee" parses to 0.0, so a stray melee profile can never win here.
			longest = maxf(longest, float(profile.get("range", 0)) + (ork11e_det_range_bonus(board.get("units", {}).get(actor_unit_id, {}), profile) if float(profile.get("range", 0)) > 0.0 else 0.0))  # Codex: Orks (11e) Dakka! Dakka! Dakka! +3" Range while riled up (WP-O34)
	return longest

## Cheap "could any of this unit's guns even reach that one?" — pure
## edge-to-edge distance against the longest ranged weapon in the loadout, with
## NO line-of-sight work at all.
##
## The LoS debug overlay uses it to drop out-of-range enemies before paying for
## a visibility sweep, which is what Settings > Visual > "LoS Debug: include
## units out of weapon range" switches off. Deliberately NOT a targeting rule:
## it ignores Pistols-in-engagement, Big Guns Never Tire and everything else, so
## it can only ever be an over-approximation of what get_eligible_targets will
## accept — no unit that IS a legal target can be filtered out by it.
##
## A unit with no ranged weapons has nothing to be out of range OF, so this
## answers true and filters nothing (a melee unit's sight lines stay drawn).
static func unit_within_weapon_reach(actor_unit_id: String, target_unit_id: String, board: Dictionary) -> bool:
	var range_in := max_ranged_weapon_range_inches(actor_unit_id, board)
	if range_in <= 0.0:
		return true
	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})
	var target_unit = units.get(target_unit_id, {})
	if actor_unit.is_empty() or target_unit.is_empty():
		return false
	var range_px := Measurement.inches_to_px(range_in)
	for actor_model in actor_unit.get("models", []):
		if not actor_model.get("alive", true):
			continue
		if not _get_model_position(actor_model):
			continue
		for target_model in target_unit.get("models", []):
			if not target_model.get("alive", true):
				continue
			if not _get_model_position(target_model):
				continue
			if Measurement.model_to_model_distance_px(actor_model, target_model) <= range_px:
				return true
	return false

static func _check_target_visibility(actor_unit_id: String, target_unit_id: String, weapon_id: String, board: Dictionary) -> Dictionary:
	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})
	var target_unit = units.get(target_unit_id, {})
	var weapon_profile = get_weapon_profile(weapon_id, board)

	if actor_unit.is_empty() or target_unit.is_empty() or weapon_profile.is_empty():
		return {"visible": false, "reason": "Invalid units or weapon"}

	var weapon_range = weapon_profile.get("range", 12) + ork11e_det_range_bonus(actor_unit, weapon_profile)  # Codex: Orks (11e) Dakka! Dakka! Dakka! +3" Range while riled up (WP-O34)
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
				# ISS-052: 11e HIDDEN gate (13.09) — a hidden model is only
				# visible to observers within its detection range. The
				# obscuring/Solid line semantics (13.10/13.11) are handled by
				# the base LoS check below (EnhancedLineOfSight runs the 11e
				# per-line rules with full base-to-base sampling at edition 11,
				# including the terrain-area grouping + "within" exclusions).
				if GameConstants.edition >= 11:
					var tm_11e = Engine.get_main_loop().root.get_node_or_null("TerrainManager")
					if tm_11e != null:
						if not tm_11e.hidden_model_visible_to(target_model, target_unit, actor_model):
							continue
				# Check LoS with enhanced base-aware visibility
				if _check_line_of_sight(actor_pos, target_pos, board, actor_model, target_model):
					return {"visible": true, "reason": ""}

	return {"visible": false, "reason": "No valid targets in range and LoS"}

# --- Line-of-sight memoization (PERF-LOS) ---------------------------------
# Base-aware line of sight is a PURE function of shooter/target geometry
# (position, base shape/size, rotation, elevation) and the terrain layout. It
# is also the single dominant cost of the shooting phase: the "which units can
# shoot" filter runs get_eligible_targets for EVERY friendly unit × enemy unit
# × weapon × model-pair, on phase entry AND again after every target click,
# with no caching. On a realistic board that measured 3–32 seconds per sweep —
# the freeze the player sees entering shooting and the multi-second pause on
# each target click.
#
# We memoize the yes/no result keyed by the exact geometry the check depends
# on, scoped to a "terrain epoch": the cache is dropped the instant the terrain
# array's reference changes. Every fresh GameState.create_snapshot() builds a
# NEW terrain array, so a stale board can never yield a wrong hit, and any move
# that changes a model's position changes its key (a miss). The rich-dict
# callers that need sight_line/attempted_lines (LoSDebugVisual, LineOfSightManager)
# call EnhancedLineOfSight.check_enhanced_visibility directly and bypass this.
static var _los_memo: Dictionary = {}
static var _los_memo_terrain = null   # reference-identity guard for the epoch
const _LOS_MEMO_MAX := 200000         # safety cap (realistically ~pairs/board)

# Drop the memo when the board's terrain layout changes identity. Using
# reference identity (is_same) is intentional: snapshots duplicate terrain, so
# a different board object is a different epoch and never shares cached results.
static func _los_memo_check_epoch(board: Dictionary) -> void:
	var terrain = board.get("terrain_features", null)
	if not is_same(terrain, _los_memo_terrain):
		_los_memo.clear()
		_los_memo_terrain = terrain

# Geometry fingerprint. Includes the model id AND position so a moved or swapped
# model is always a cache miss, plus every base attribute that feeds the
# base-aware sampler.
static func _los_memo_key(sm: Dictionary, tm: Dictionary) -> String:
	var sp = _get_model_position(sm)
	var tp = _get_model_position(tm)
	return "%s@%s/%s/%s/%s/%s/%s|%s@%s/%s/%s/%s/%s/%s" % [
		sm.get("id", ""), sp, sm.get("base_mm", 32), sm.get("base_type", ""),
		sm.get("base_dimensions", {}), sm.get("rotation", 0.0), sm.get("elevation_inches", 0.0),
		tm.get("id", ""), tp, tm.get("base_mm", 32), tm.get("base_type", ""),
		tm.get("base_dimensions", {}), tm.get("rotation", 0.0), tm.get("elevation_inches", 0.0),
	]

# PERF-LOS: force-clear the LoS memo (e.g. if terrain is ever edited in place).
static func clear_los_memo() -> void:
	_los_memo.clear()
	_los_memo_terrain = null

static func _check_line_of_sight(from_pos: Vector2, to_pos: Vector2, board: Dictionary, shooter_model: Dictionary = {}, target_model: Dictionary = {}) -> bool:
	# Enhanced mode with model data for base-aware visibility checking
	if not shooter_model.is_empty() and not target_model.is_empty():
		# PERF-LOS: memoized fast path (see _los_memo notes above).
		_los_memo_check_epoch(board)
		var key = _los_memo_key(shooter_model, target_model)
		if _los_memo.has(key):
			return _los_memo[key]
		var result = EnhancedLineOfSight.check_enhanced_visibility(shooter_model, target_model, board)
		var has_los: bool = result.has_los
		if _los_memo.size() < _LOS_MEMO_MAX:
			_los_memo[key] = has_los
		return has_los

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
# first_match_only (PERF-LOS): when true, return as soon as ONE eligible target
# (with one in-range/visible weapon) is found. The "can this unit shoot at all?"
# list filter only needs a yes/no, so it passes true and skips the rest of the
# (expensive, LoS-heavy) enemy scan. The default false path builds the full map
# the target-selection UI needs.
# only_target_ids (PERF, 15.09 snap shooting): when non-empty, only the enemy
# units whose ids are keys of it are considered — a caller that has already
# ruled the rest out on a cheaper test (snap shooting: "within 24"") skips
# their LoS / engagement scans. Every check on a considered unit is unchanged.
static func get_eligible_targets(actor_unit_id: String, board: Dictionary, first_match_only: bool = false, only_target_ids: Dictionary = {}) -> Dictionary:
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

	# PERF-LOS: the actor's weapon layout is identical for every candidate target,
	# so resolve it ONCE here instead of re-parsing it inside the per-target loop.
	var unit_weapons = get_unit_weapons(actor_unit_id, board)

	# Check each potential target unit
	for target_unit_id in units:
		if not only_target_ids.is_empty() and not only_target_ids.has(target_unit_id):
			continue
		var target_unit = units[target_unit_id]

		# Skip friendly units
		if target_unit.get("owner", 0) == actor_owner:
			continue

		# Skip units that are attached to a bodyguard (they are targeted through their bodyguard)
		if target_unit.get("attached_to", null) != null:
			continue

		# Skip embarked units — models inside a TRANSPORT are not on the
		# battlefield and can never be shot at directly (18.01). Do not rely on
		# their positions being null: a unit that embarked mid-game may carry a
		# stale pre-embark position.
		if target_unit.get("embarked_in", null) != null:
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

		# Check weapons that can target this unit (unit_weapons hoisted above the loop)
		var weapons_in_range = []

		# PERF-LOS: a weapon carried by N models was previously visibility-checked
		# once PER carrying model — and _check_target_visibility already scans every
		# alive actor model internally, so those N-1 extra scans were pure waste
		# (each a full actor×target model loop). On a horde unit that is the
		# difference between checking "shoota" once vs 20×. Dedup by weapon: only
		# the first bearer of each weapon triggers the (expensive) visibility scan.
		var checked_weapons := {}
		for model_id in unit_weapons:
			# ATTACHED CHARACTERS: get_unit_weapons emits composite
			# "<char_unit>:<model>" bearers. Dropping them here meant an attached
			# character's guns never contributed to target eligibility — a unit
			# whose ONLY in-range weapon was the character's read as having no
			# eligible targets at all.
			var model = resolve_bearer_model(actor_unit, model_id, board)
			if not model or not model.get("alive", true):
				continue

			for weapon_id in unit_weapons[model_id]:
				if weapon_id in weapons_in_range or checked_weapons.has(weapon_id):
					continue
				checked_weapons[weapon_id] = true

				# HUNTER PROFILES (11e 04.01.03): only units with the
				# specified keywords can be targeted by that profile.
				if not weapon_profile_can_target(weapon_id, target_unit, board):
					continue

				var is_pistol = is_pistol_weapon(weapon_id, board)
				# 11e 10.06 / 24.27: a [CLOSE-QUARTERS] weapon is what [PISTOL] was — an
				# engaged unit fires it at the units it is engaged with (the 11e data
				# prints "close quarters", never PISTOL). WP-M3b: found while validating
				# POINT-BLANK BRUTALITY, whose granted [CLOSE-QUARTERS] (SMCodexB.gd) counts too.
				if not is_pistol and actor_in_engagement and GameConstants.edition >= 11:
					is_pistol = _snap_is_close_quarters_weapon(weapon_id, board) \
						or load("res://scripts/codex/space_marines/SMCodexB.gd").weapon_gets_close_quarters(get_weapon_profile(weapon_id, board), actor_unit)

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
					# PERF-LOS: for the yes/no filter, one visible weapon settles it —
					# stop scanning this unit's remaining weapons.
					if first_match_only:
						break
			if first_match_only and not weapons_in_range.is_empty():
				break

		if not weapons_in_range.is_empty():
			eligible[target_unit_id] = {
				"weapons_in_range": weapons_in_range,
				"unit_name": target_unit.get("meta", {}).get("display_name", target_unit.get("meta", {}).get("name", target_unit_id)),
				"in_engagement_range": actor_in_engagement,  # Include flag for UI
				"is_bgnt": actor_is_monster_vehicle and actor_in_engagement  # Flag for BGNT status
			}
			# PERF-LOS: filter caller only needs to know the unit CAN shoot something.
			if first_match_only:
				return eligible

	return eligible

# Returns a human-readable reason why the given target cannot be shot at by
# the actor unit. Empty string means the target IS eligible.
# Mirrors the eligibility checks in get_eligible_targets so the UI can explain
# why a clicked enemy unit is greyed out (out of range, no LoS, Lone Operative, etc.).
static func get_target_ineligibility_reason(actor_unit_id: String, target_unit_id: String, board: Dictionary) -> String:
	return explain_target_ineligibility(actor_unit_id, target_unit_id, board).reason

# Structured form of the above: the same verdict plus a stable `code` naming
# WHICH gate refused the target. The LoS debug overlay needs the code, not just
# the prose — "no_los"/"hidden" mean there is provably no clear model pair, so
# the overlay can skip hunting for one (that hunt is the expensive half of a
# whole-board sweep). Codes: "" (eligible), no_shooter, invalid_target,
# friendly, attached, embarked, destroyed, friendly_engagement, lone_operative,
# psychic_veil, no_weapons, engagement_range, out_of_range, hidden, no_los.
static func explain_target_ineligibility(actor_unit_id: String, target_unit_id: String, board: Dictionary) -> Dictionary:
	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})
	var target_unit = units.get(target_unit_id, {})

	if actor_unit.is_empty():
		return _ineligible("no_shooter", "No active shooter")
	if target_unit.is_empty():
		return _ineligible("invalid_target", "Invalid target")

	if target_unit.get("owner", 0) == actor_unit.get("owner", 0):
		return _ineligible("friendly", "Cannot target a friendly unit")

	if target_unit.get("attached_to", null) != null:
		return _ineligible("attached", "Cannot target an attached character — shoot the bodyguard unit")

	# 18.01: models inside a TRANSPORT are not on the battlefield. get_eligible_targets
	# skips them; without the same skip here an embarked unit's stale pre-embark
	# position could report in range + LoS and this function would answer "" —
	# i.e. "targetable" — for a unit the target list will never offer.
	if target_unit.get("embarked_in", null) != null:
		return _ineligible("embarked", "%s is embarked in a transport — shoot the transport instead" % target_unit.get("meta", {}).get("display_name", target_unit.get("meta", {}).get("name", target_unit_id)))

	var has_alive = false
	for model in target_unit.get("models", []):
		if model.get("alive", true):
			has_alive = true
			break
	if not has_alive:
		return _ineligible("destroyed", "Target unit is destroyed")

	var target_name = target_unit.get("meta", {}).get("display_name", target_unit.get("meta", {}).get("name", target_unit_id))
	var actor_owner = actor_unit.get("owner", 0)
	var target_is_monster_vehicle = is_monster_or_vehicle(target_unit)

	# Cannot target enemies within engagement range of friendly units
	# (unless the target is a Monster/Vehicle — Big Guns Never Tire applies to the *shooter*,
	# but the broader rule is that engaged enemies of friends are off-limits to other shooters
	# except when the target is a Monster/Vehicle, since they can also be targeted normally.)
	if not target_is_monster_vehicle:
		if _is_target_in_friendly_engagement(target_unit_id, actor_unit_id, actor_owner, units, board):
			return _ineligible("friendly_engagement", "%s is in engagement range with a friendly unit" % target_name)

	# Lone Operative
	if has_lone_operative(target_unit) and target_unit.get("attached_to", null) == null:
		var attached_chars = target_unit.get("attachment_data", {}).get("attached_characters", [])
		if attached_chars.is_empty():
			var min_dist = _get_min_distance_to_target_rules(actor_unit_id, target_unit_id, board)
			# Read the datasheet's range like get_eligible_targets does — hardcoding
			# 12" made this disagree with the target list for any Lone Operative X"
			# that is not the 12" default.
			var lo_range = get_lone_operative_range(target_unit)
			if min_dist > lo_range:
				return _ineligible("lone_operative", "%s has Lone Operative — must be within %d\" (currently %.1f\")" % [target_name, int(lo_range), min_dist])

	# Psychic Veil
	if target_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_PSYCHIC_VEIL, false):
		var min_dist = _get_min_distance_to_target_rules(actor_unit_id, target_unit_id, board)
		if min_dist > 18.0:
			return _ineligible("psychic_veil", "%s has Psychic Veil — must be within 18\" (currently %.1f\")" % [target_name, min_dist])

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
	# 11e HIDDEN (13.09): track pairs that have clear sight lines but are
	# gated by detection range, so the player gets the real reason instead of
	# a generic "no line of sight".
	var any_hidden_blocked = false
	var hidden_min_dist = INF
	var hidden_det_range = GameConstants.hidden_detection_range_inches()
	var tm_hidden = Engine.get_main_loop().root.get_node_or_null("TerrainManager") if GameConstants.edition >= 11 else null

	for model_id in unit_weapons:
		# ATTACHED CHARACTERS: composite bearers resolved through the board, so a
		# character's weapons are considered when explaining WHY a target is
		# ineligible (they were skipped entirely before).
		var actor_model = resolve_bearer_model(actor_unit, model_id, board)
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
			var weapon_range = weapon_profile.get("range", 12) + ork11e_det_range_bonus(actor_unit, weapon_profile)  # Codex: Orks (11e) Dakka! Dakka! Dakka! +3" Range while riled up (WP-O34)
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
								# Sight lines are clear — mirror the 13.09
								# hidden gate applied by _check_target_visibility.
								if tm_hidden != null and not tm_hidden.hidden_model_visible_to(target_m, target_unit, actor_m):
									any_hidden_blocked = true
									var d_in = Measurement.px_to_inches(distance)
									if d_in < hidden_min_dist:
										hidden_min_dist = d_in
										hidden_det_range = tm_hidden.detection_range_inches_for(target_m, target_unit, actor_m)
								else:
									any_in_los = true

	if not has_any_weapon:
		return _ineligible("no_weapons", "%s has no usable weapons" % actor_unit.get("meta", {}).get("display_name", actor_unit_id))

	if actor_in_engagement and not any_weapon_passed_er_filter:
		if actor_is_monster_vehicle:
			return _ineligible("engagement_range", "No weapons can reach %s while in engagement range" % target_name)
		else:
			return _ineligible("engagement_range", "Your unit is in engagement range — only Pistols can shoot, and %s is not in your engagement range" % target_name)

	if not any_in_range:
		return _ineligible("out_of_range", "%s is out of range" % target_name)
	if not any_in_los:
		if any_hidden_blocked:
			return _ineligible("hidden", "%s is Hidden (dense terrain, hasn't shot recently) — visible only within %d\" detection range; your closest model is %.1f\" away" % [target_name, int(round(hidden_det_range)), hidden_min_dist])
		return _ineligible("no_los", "No line of sight to %s — terrain blocks every sight line" % target_name)

	return {"reason": "", "code": ""}

static func _ineligible(code: String, reason: String) -> Dictionary:
	return {"reason": reason, "code": code}


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
	# FIRING DECK (24.14): synthetic bearer ids "<hull_id>@fd<i>" (produced by
	# get_unit_weapons for loaned embarked weapons) resolve to the transport's
	# hull model so BS / position / LoS use the transport. Real model ids never
	# contain "@fd", so this strip is a no-op for every normal lookup.
	var fd_idx = model_id.find("@fd")
	if fd_idx > 0:
		model_id = model_id.substr(0, fd_idx)
	for model in unit.get("models", []):
		if model.get("id", "") == model_id:
			return model
	return {}

## Resolve a BEARER id produced by get_unit_weapons() to its real model dict.
##
## get_unit_weapons emits three id shapes for a single "unit":
##   "m3"                     — a model of the unit itself
##   "U_WARBOSS_T:m1"         — a model of an ATTACHED CHARACTER (composite, so
##                              damage routes back to the character's own unit)
##   "m1@fd2"                 — a firing-deck loan, bound to the transport hull
## _get_model_by_id only understands the first and third: a composite id has no
## match in actor_unit.models, so it returned {}. Every caller that walks
## get_unit_weapons and then looks the bearer up therefore skipped attached
## characters' guns entirely — including per-model range/LoS eligibility, which
## made a Warboss's kombi-weapon unassignable through the click/pad path
## ("can't fire on X (range / line of sight)" with an EMPTY reasons dict, since
## the bearer was dropped before any range test ran). Pass the board so the
## character's own unit can be reached.
static func resolve_bearer_model(actor_unit: Dictionary, bearer_id: String, board: Dictionary) -> Dictionary:
	# "@fd" is stripped by _get_model_by_id itself and never carries a ":".
	var sep := bearer_id.find(":")
	if sep > 0:
		var owner_unit_id := bearer_id.substr(0, sep)
		var inner_model_id := bearer_id.substr(sep + 1)
		var owner_unit: Dictionary = board.get("units", {}).get(owner_unit_id, {})
		if owner_unit.is_empty() and board.is_empty():
			owner_unit = GameState.state.get("units", {}).get(owner_unit_id, {})
		if owner_unit.is_empty():
			return {}
		return _get_model_by_id(owner_unit, inner_model_id)
	return _get_model_by_id(actor_unit, bearer_id)

## The unit dict that OWNS a bearer id — actor_unit for a normal id, the
## attached character's own unit for a composite one. Needed wherever a
## PER-MODEL STAT OVERRIDE is read: model_profiles / stats_override live on the
## owning unit's meta, so looking a character's model_type up in the bodyguard
## unit's profiles silently misses and falls back to the weapon's base stat.
static func resolve_bearer_unit(actor_unit: Dictionary, bearer_id: String, board: Dictionary) -> Dictionary:
	var sep := bearer_id.find(":")
	if sep <= 0:
		return actor_unit
	var owner_unit_id := bearer_id.substr(0, sep)
	var owner_unit: Dictionary = board.get("units", {}).get(owner_unit_id, {})
	if owner_unit.is_empty() and board.is_empty():
		owner_unit = GameState.state.get("units", {}).get(owner_unit_id, {})
	return owner_unit if not owner_unit.is_empty() else actor_unit

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

	# MA-LOADOUT: a resolved per-model loadout (derived from the unit's wargear by
	# _ensure_loadout_resolved) overrides the model_profiles menu — so a model
	# reports the weapon it actually carries rather than every wargear option.
	# Ranged (Phase 1/Task C) and melee (Phase 1b/Task D) are symmetric.
	var tf = weapon_type_filter.to_lower()
	var resolved_ranged = model.get("ranged_loadout", null)
	var resolved_melee = model.get("melee_loadout", null)
	var use_resolved_ranged = tf == "ranged" and resolved_ranged is Array
	var use_resolved_melee = tf == "melee" and resolved_melee is Array

	var weapon_ids = []
	for weapon in weapons_data:
		var wtype = weapon.get("type", "")
		if wtype.to_lower() != tf:
			continue

		var wname = weapon.get("name", "")
		# Enhancement-granted weapons (meta.weapons[].granted_by, e.g. the
		# Custodes Emperor's Light / Auriferous Orb — WP-C46) are carried by the
		# bearer whatever its roster loadout or model_profiles menu says.
		var granted: bool = str(weapon.get("granted_by", "")) != ""
		if granted:
			pass
		elif use_resolved_ranged:
			if wname not in resolved_ranged:
				continue
		elif use_resolved_melee:
			if wname not in resolved_melee:
				continue
		elif use_profile and wname not in allowed_weapon_names:
			continue

		var weapon_id = _generate_weapon_id(wname, wtype)
		if weapon_id not in weapon_ids:
			weapon_ids.append(weapon_id)

	return weapon_ids


# MA-LOADOUT: resolve which weapon(s) each model of a multi-model unit actually
# carries, from the unit's `wargear` counts, stamping them onto the models
# (`ranged_loadout` — and, once Task D lands, `melee_loadout`).
#
# Datasheets store, per model_type, the full MENU of wargear options. When the
# importer already narrowed that to one weapon (e.g. Lootas' loota_deffgun ->
# Deffgun) a model correctly reports one gun. But when it left a menu (Ork Boyz'
# generic "boy" type) — or gave no model_profiles at all — every model reports
# EVERY option, so a 10-model mob reports ~4x its real guns.
#
# Resolution is deliberately conservative: it only ever REDUCES over-counting and
# every assignment is cross-checked against model_profiles, so it never hands a
# model a weapon its type can't take and never changes an already-correct unit.
# Anything it can't pin cleanly is left exactly as-is (the safe fallback) and
# logged. See _resolve_type_loadout for the cases handled (A/B/C/D).
static func _ensure_loadout_resolved(unit: Dictionary) -> void:
	# Version the "already done" stamp instead of a bare bool: saves (and the
	# tutorial fixtures) written by an OLDER resolver carry _loadout_checked =
	# true with only the ranged half resolved, and a bare bool would lock them
	# out of every later improvement forever. Re-running is safe — each type is
	# skipped when it no longer over-reports, so an existing stamp survives.
	if int(unit.get("_loadout_version", 0)) >= LOADOUT_RESOLVER_VERSION:
		return
	unit["_loadout_version"] = LOADOUT_RESOLVER_VERSION
	unit["_loadout_checked"] = true

	# A single-model unit (VEHICLE / MONSTER / character) DOES fire all of the
	# weapons it carries — but `meta.weapons` is the datasheet's option MENU, not
	# its arsenal. A Battlewagon's menu offers a kannon OR a killkannon OR a zzap
	# gun; the roster picked one. Narrow it from the roster's wargear so the
	# Shooting/Fight phases stop offering guns the player never took. The
	# resolver returns the menu untouched whenever it can't read the loadout, and
	# we only stamp when it actually narrowed something — so a unit we cannot
	# resolve keeps the original "fires everything on the datasheet" behaviour.
	if unit.get("models", []).size() < 2:
		_resolve_single_model_loadout(unit)
		return

	_resolve_type_loadout(unit, "Ranged", "ranged_loadout")
	# MA-LOADOUT Phase 1b (Task D): resolve melee the same way, so the Fight phase
	# stops over-counting a model's melee options (a Boy's Choppa AND Close combat
	# weapon, a Nob's several melee profiles). Melee wargear is spottier than
	# ranged, so most units fall back to the menu; those that pin it cleanly
	# (Kommandos -> Choppa, Burna Boyz -> Cuttin' flames + CCW) are resolved.
	_resolve_type_loadout(unit, "Melee", "melee_loadout")


# MA-LOADOUT: single-model narrowing. Shares ONE resolution with the datasheet
# UI (UnitLoadoutResolver) so what a player is shown and what they can fire can
# never disagree. Stamps `ranged_loadout` / `melee_loadout` on the lone model —
# the same keys _get_model_weapon_ids already honours — but ONLY for a type the
# resolver genuinely narrowed. Leaving the other type unstamped preserves the
# old menu behaviour for it exactly.
static func _resolve_single_model_loadout(unit: Dictionary) -> void:
	var models = unit.get("models", [])
	if models.size() != 1:
		return
	var meta = unit.get("meta", {})
	var menu = meta.get("weapons", [])
	if typeof(menu) != TYPE_ARRAY or menu.is_empty():
		return

	var equipped = UnitLoadoutResolver.get_equipped_weapons(unit)
	if equipped.size() >= menu.size():
		return  # nothing was narrowed — leave the unit untouched

	# Bucket both the menu and the equipped set per weapon type, so we can tell
	# WHICH type actually lost options (a Battlewagon narrows its ranged menu
	# 6 -> 3 while its melee list is already exact).
	var uname = str(meta.get("name", ""))
	for pair in [["Ranged", "ranged_loadout"], ["Melee", "melee_loadout"]]:
		var type_filter = str(pair[0]).to_lower()
		var menu_names := []
		for w in menu:
			if typeof(w) == TYPE_DICTIONARY and str(w.get("type", "")).to_lower() == type_filter:
				var n = str(w.get("name", ""))
				if n not in menu_names:
					menu_names.append(n)
		var kept := []
		for w in equipped:
			if typeof(w) == TYPE_DICTIONARY and str(w.get("type", "")).to_lower() == type_filter:
				var n = str(w.get("name", ""))
				if n not in kept:
					kept.append(n)
		if kept.size() >= menu_names.size():
			continue  # this type was not narrowed
		models[0][str(pair[1])] = kept
		print("[MA-LOADOUT] %s (%s): single model narrowed to roster loadout %s (menu had %d)" % [
			uname, str(pair[0]), str(kept), menu_names.size()])


# MA-LOADOUT: cross-check guard — may this model's type actually take
# `weapon_name`? True when the unit has no model_profiles constraint for this
# model (its menu is already limited to meta.weapons), otherwise the name must be
# in the model_type's allowed weapon list. This is the guard against inventing a
# weapon a model_type can't have (the #1 risk when widening coverage).
static func _model_allows_weapon(unit: Dictionary, model: Dictionary, weapon_name: String) -> bool:
	var model_profiles = unit.get("meta", {}).get("model_profiles", {})
	var model_type = model.get("model_type", "")
	if model_profiles.is_empty() or model_type == "" or not model_profiles.has(model_type):
		return true
	return weapon_name in model_profiles[model_type].get("weapons", [])


# MA-LOADOUT (WP-S1): per model index, the weapon slugs its composition role
# can hold — the role's default kit plus every option bundle open to that role
# (role filter "" = any model). {} when the roles can't be worked out.
static func _role_weapon_menus(unit: Dictionary) -> Dictionary:
	var models = unit.get("models", [])
	var ds_key = UnitLoadoutResolver.datasheet_key(unit)
	var positional = _positional_roles(ds_key, models.size())
	if positional.size() != models.size() or not _kits_match_weapons(unit):
		return {}
	var options = UnitLoadoutResolver.get_wargear_options(ds_key)
	var out := {}
	for i in range(models.size()):
		var role = UnitLoadoutResolver.match_model_role(ds_key, [str(positional[i])])
		if role == "":
			return {}
		var menu := {}
		for sl in UnitLoadoutResolver.get_role_default_weapon_slugs(ds_key, role):
			menu[str(sl)] = true
		for opt in options:
			var rf = str(opt.get("role", ""))
			if rf != "" and rf != role:
				continue
			for bundle in opt.get("bundles", []):
				for b in bundle:
					menu[str(b)] = true
		out[i] = menu
	return out

# True when every default-kit weapon id of every role of this datasheet names
# one of the unit's weapons (full or base name). Only then do the WP-S1 rules
# below trust the kit enough to say "this role carries no gun" or "this role
# can't take that gun"; a kit whose ids don't match the weapon names (Ork
# "choppa" vs "Choppas") keeps the older, more cautious behaviour.
static func _kits_match_weapons(unit: Dictionary) -> bool:
	var names := {}
	for w in unit.get("meta", {}).get("weapons", []):
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var n = str(w.get("name", ""))
		names[UnitLoadoutResolver.slugify(n)] = true
		names[UnitLoadoutResolver.slugify(UnitLoadoutResolver.base_weapon_name(n))] = true
	var ds_key = UnitLoadoutResolver.datasheet_key(unit)
	var roles = UnitLoadoutResolver.get_model_roles(ds_key)
	if roles.is_empty():
		return false
	for r in roles:
		var role = UnitLoadoutResolver.slugify(str(r.get("name", "")))
		var kit = UnitLoadoutResolver.get_role_default_weapon_slugs(ds_key, role)
		if kit.is_empty():
			return false
		for sl in kit:
			if not names.has(str(sl)):
				return false
	return true

static func _role_menu_allows(role_menu: Dictionary, mi: int, weapon_name: String) -> bool:
	var menu: Dictionary = role_menu.get(mi, {})
	return menu.has(UnitLoadoutResolver.slugify(weapon_name)) or \
		menu.has(UnitLoadoutResolver.slugify(UnitLoadoutResolver.base_weapon_name(weapon_name)))


# Every profile name of one weapon (a multi-profile weapon is carried whole).
static func _model_allows_weapons(unit: Dictionary, model: Dictionary, weapon_names: Array) -> bool:
	for wn in weapon_names:
		if not _model_allows_weapon(unit, model, str(wn)):
			return false
	return true


# MA-LOADOUT: shared resolver for one weapon type ("Ranged" / "Melee"). Parses
# the unit's `wargear` counts for that type's weapons and, when they unambiguously
# pin the per-model loadout, stamps `loadout_key` on each model. Leaves the unit
# untouched (safe fallback) and logs why otherwise.
#
# Cases handled:
#   A) one gun per model, counts sum to the model count (original Phase 1) — the
#      special (lowest-count) guns go on the first models that may take them.
#   B) uniform multi-gun models: every distinct gun appears exactly once per
#      model (each count == model_count), so each model carries the same set
#      (Deffkopta -> [Kopta rokkits, Slugga]). Guards out oversized/broken
#      wargear (a 2-model unit carrying 10-model counts fails this cleanly).
#   C) incomplete-but-consistent: fewer counts than models but all the SAME gun
#      (a 20-Boy mob recorded with only "10x Slugga") -> that gun on every model.
#   D) wargear silent about this type entirely (the norm for MELEE) -> fall back
#      to the datasheet's default kit per model role, e.g. Boyz -> Boss Nob with
#      a Big choppa, Boyz with Choppas. See _resolve_type_from_datasheet_defaults.
static func _resolve_type_loadout(unit: Dictionary, weapon_type_filter: String, loadout_key: String) -> void:
	var meta = unit.get("meta", {})
	var models = unit.get("models", [])

	# Weapon names of this type the datasheet actually lists.
	var type_names := {}
	# Every slug a wargear line may name one of them by -> the weapon's
	# profile names of this type. A multi-profile weapon is listed per profile
	# ("Rokkit Launcha – Blasta", "Rokkit Launcha – Busta") but a roster names
	# it once ("3x Rokkit Launcha"): that line is one weapon per model, carried
	# with all its profiles of this type (WP-O1b). Full-name slugs also absorb
	# capitalisation ("1x Power snappa" -> "Power Snappa").
	var full_slug := {}   # slug(full name) -> full name
	var base_group := {}  # slug(base name) -> [full names]
	for w in meta.get("weapons", []):
		if str(w.get("type", "")).to_lower() == weapon_type_filter.to_lower():
			var wn := str(w.get("name", ""))
			type_names[wn] = true
			full_slug[UnitLoadoutResolver.slugify(wn)] = wn
			var bs := UnitLoadoutResolver.slugify(UnitLoadoutResolver.base_weapon_name(wn))
			var grp: Array = base_group.get(bs, [])
			if wn not in grp:
				grp.append(wn)
			base_group[bs] = grp
	if type_names.is_empty():
		return

	# Only act when a model currently over-reports this weapon type. Units already
	# resolved per model_type (loota_deffgun, etc.) are left untouched.
	var over_reports := false
	for model in models:
		if _get_model_weapon_ids(unit, model, weapon_type_filter).size() > 1:
			over_reports = true
			break
	if not over_reports:
		return

	# Parse wargear into {name: count} for this type, summing duplicate lines and
	# ignoring entries that aren't this unit's weapons of this type (roles, the
	# other weapon type, and count-less entries we can't size).
	var counts := {}
	var total := 0
	# gun key (as counted) -> the profile names a model carrying it reports
	var gun_names := {}
	for entry in meta.get("wargear", []):
		for part in str(entry).split(","):
			var txt = part.strip_edges()
			var space = txt.find(" ")
			if space <= 0:
				continue
			var head = txt.substr(0, space)
			if not head.ends_with("x"):
				continue
			var num_str = head.substr(0, head.length() - 1)
			if not num_str.is_valid_int():
				continue
			var name = txt.substr(space + 1).strip_edges()
			var key := ""
			if type_names.has(name):
				key = name
				gun_names[key] = [name]
			else:
				var s := UnitLoadoutResolver.slugify(str(name))
				if full_slug.has(s):
					key = str(full_slug[s])
					gun_names[key] = [key]
				elif base_group.has(s):
					var grp: Array = base_group[s]
					key = UnitLoadoutResolver.base_weapon_name(str(grp[0]))
					gun_names[key] = grp.duplicate()
			if key != "":
				var n = int(num_str)
				counts[key] = int(counts.get(key, 0)) + n
				total += n

	var model_count = models.size()
	var uname = str(meta.get("name", ""))
	var tlow = weapon_type_filter.to_lower()
	if counts.is_empty():
		# CASE D — the roster's wargear says NOTHING about this weapon type, which
		# is the norm for melee (a Boyz mob records "9x Slugga, 1x Slugga" and not
		# one word about choppas). Falling through here left every model reporting
		# the whole datasheet MENU, so a Boy claimed a Choppa AND a Close combat
		# weapon and the Boss Nob claimed a Big choppa, a Choppa AND a Power klaw —
		# those are mutually-exclusive wargear OPTIONS, not a shared arsenal.
		# The datasheet states what each role is equipped with by default
		# ("The Boss Nob is equipped with: slugga; big choppa. Every Boy is
		# equipped with: slugga; choppa."), so use that.
		if _resolve_type_from_datasheet_defaults(unit, weapon_type_filter, loadout_key):
			return
		print("[MA-LOADOUT] %s (%s): left unresolved — no parseable %s wargear counts and no usable datasheet default kit" % [uname, weapon_type_filter, tlow])
		return

	var distinct = counts.keys()

	# CASE A — exactly one gun per model. Assign lowest-count (special) weapons to
	# the earliest model that may take them so they're identifiable; the bulk gun
	# fills the rest. Falls back if a gun can't be placed within model_profiles.
	if total == model_count:
		var ordered = distinct.duplicate()
		ordered.sort_custom(func(a, b): return int(counts[a]) < int(counts[b]))
		var assigned := {}   # model index -> gun name
		var used := {}       # model index -> true
		# Which weapons each model's composition ROLE can ever hold (its default
		# kit + the options open to that role) — so a special gun never lands on
		# a model whose role can't take it (a Thunderclap on a Hunting Wolf).
		# {} when the roles can't be told; then only model_profiles decide.
		var role_menu := _role_weapon_menus(unit)
		for name in ordered:
			for _i in range(int(counts[name])):
				var placed := false
				for mi in range(model_count):
					if used.has(mi):
						continue
					if not role_menu.is_empty() and not _role_menu_allows(role_menu, mi, str(name)):
						continue
					if _model_allows_weapons(unit, models[mi], gun_names[name]):
						used[mi] = true
						assigned[mi] = name
						placed = true
						break
				if not placed:
					# The counts are real but the roster's own model_profiles will
					# not take this gun. The datasheet knows the per-role split —
					# try it before giving up (CASE D).
					print("[MA-LOADOUT] %s (%s): could not place '%s' within model_profiles — trying the datasheet kit" % [uname, weapon_type_filter, name])
					if not _resolve_type_from_datasheet_defaults(unit, weapon_type_filter, loadout_key):
						print("[MA-LOADOUT] %s (%s): left unresolved — could not place '%s'" % [uname, weapon_type_filter, name])
					return
		for mi in range(model_count):
			models[mi][loadout_key] = (gun_names[assigned[mi]] as Array).duplicate()
		return

	# CASE B — uniform multi-gun models (each distinct gun appears once per model).
	var uniform := true
	for name in distinct:
		if int(counts[name]) != model_count:
			uniform = false
			break
	if uniform and total == distinct.size() * model_count:
		var gun_set := []
		for name in distinct:
			for pn in gun_names[name]:
				if pn not in gun_set:
					gun_set.append(pn)
		for model in models:
			for name in gun_set:
				if not _model_allows_weapon(unit, model, name):
					print("[MA-LOADOUT] %s (%s): left unresolved — set gun '%s' not allowed for model_type '%s'" % [uname, weapon_type_filter, name, str(model.get("model_type", ""))])
					return
		for model in models:
			model[loadout_key] = gun_set.duplicate()
		return

	# CASE C — incomplete-but-consistent: fewer counts than models, all one gun.
	if distinct.size() == 1 and total < model_count:
		var name = str(distinct[0])
		var all_allowed := true
		for model in models:
			if not _model_allows_weapons(unit, model, gun_names[name]):
				# Handing the gun to EVERY model is wrong here — some role can't
				# take it, which means the roster's short count is a per-role
				# figure ("9x Close combat weapon" for 9 Boyz + a Boss Nob with a
				# big choppa). The datasheet's per-role kit knows the split.
				print("[MA-LOADOUT] %s (%s): consistent gun '%s' not allowed for model_type '%s' — trying the datasheet kit" % [uname, weapon_type_filter, name, str(model.get("model_type", ""))])
				all_allowed = false
				break
		if all_allowed:
			for model in models:
				model[loadout_key] = (gun_names[name] as Array).duplicate()
			return
		if _resolve_type_from_datasheet_defaults(unit, weapon_type_filter, loadout_key):
			return
		print("[MA-LOADOUT] %s (%s): left unresolved — consistent gun '%s' fits no per-role kit" % [uname, weapon_type_filter, name])
		return

	# Counts we cannot read as one-gun-per-model. The datasheet's per-role kit,
	# adjusted by the options the roster took, is the last and best-informed
	# chance to pin this (a roster listing per-role sub-totals lands here).
	if _resolve_type_from_datasheet_defaults(unit, weapon_type_filter, loadout_key):
		return
	print("[MA-LOADOUT] %s (%s): left unresolved — counts inconclusive (total=%d models=%d distinct=%d)" % [uname, weapon_type_filter, total, model_count, distinct.size()])


# MA-LOADOUT CASE D: resolve one weapon type from the datasheet's kit — the
# default "equipped with" line, adjusted by whichever "•" options the roster
# took — when the roster's wargear is silent about that type.
#
# `meta.weapons` is the datasheet's whole option MENU and `model_profiles[t].weapons`
# is the menu that role may pick FROM — neither says what the model ended up
# holding. The 40kdc data does: `unitCompositions` gives each role its
# `default_weapon_ids` (Boss Nob -> big-choppa + slugga, Boy -> slugga + choppa)
# and `wargearOptions` gives the swaps on top. Wargear-derived resolution
# (cases A/B/C) always wins; this only fills the silence.
#
# Safety: every pick is intersected with the datasheet's weapons of this type AND
# with _model_allows_weapon, so the result is always a SUBSET of what the model
# already reported — resolution can only ever reduce, never invent. Any model we
# cannot pin (unknown datasheet, unmatched role, no kit of this type) aborts the
# whole unit and leaves it exactly as it was. Returns true when it stamped.
static func _resolve_type_from_datasheet_defaults(unit: Dictionary, weapon_type_filter: String, loadout_key: String) -> bool:
	var meta = unit.get("meta", {})
	var models = unit.get("models", [])
	var uname = str(meta.get("name", ""))
	var tlow = weapon_type_filter.to_lower()

	# Datasheet weapon names of this type, in datasheet order.
	var type_weapon_names: Array = []
	for w in meta.get("weapons", []):
		if typeof(w) != TYPE_DICTIONARY:
			continue
		if str(w.get("type", "")).to_lower() == tlow:
			var n = str(w.get("name", ""))
			if n != "" and n not in type_weapon_names:
				type_weapon_names.append(n)
	if type_weapon_names.is_empty():
		return false

	# What each model carries, as weapon-id slugs. [] when the roster can't be
	# read confidently — see _datasheet_model_kits.
	var kits = _datasheet_model_kits(unit)
	if kits.is_empty():
		return false

	var picks: Array = []  # parallel to models
	var any_pick := false
	var kits_trusted := _kits_match_weapons(unit)
	for i in range(models.size()):
		var model = models[i]
		var allowed: Array = []
		var kit_has_type := false
		for wname in type_weapon_names:
			# Match the full name AND the base name so a kit slug of
			# "guardian-spear" picks up "Guardian spear – Melee".
			var s_full = UnitLoadoutResolver.slugify(wname)
			var s_base = UnitLoadoutResolver.slugify(UnitLoadoutResolver.base_weapon_name(wname))
			if not (kits[i].has(s_full) or kits[i].has(s_base)):
				continue
			kit_has_type = true
			if _model_allows_weapon(unit, model, wname):
				allowed.append(wname)
		if allowed.is_empty() and (kit_has_type or not kits_trusted):
			print("[MA-LOADOUT] %s (%s): model %d's datasheet kit has no %s weapon — left unresolved" % [
				uname, weapon_type_filter, i, tlow])
			return false
		# A model whose kit simply has no weapon of this type carries none
		# (a Hunting Wolf has no gun; a Wolf Guard Terminator who swapped his
		# storm bolter for a storm shield shoots nothing). WP-S1.
		if not allowed.is_empty():
			any_pick = true
		picks.append(allowed)
	if not any_pick:
		print("[MA-LOADOUT] %s (%s): no model's datasheet kit has a %s weapon — left unresolved" % [uname, weapon_type_filter, tlow])
		return false

	# Only stamp when this actually narrows something. A unit already reporting
	# exactly its default kit gains nothing from the stamp, and skipping it keeps
	# "resolution never changes an already-correct unit" true.
	var narrowed := false
	for i in range(models.size()):
		if picks[i].size() < _get_model_weapon_ids(unit, models[i], weapon_type_filter).size():
			narrowed = true
			break
	if not narrowed:
		return false

	for i in range(models.size()):
		models[i][loadout_key] = picks[i]
	print("[MA-LOADOUT] %s (%s): resolved from datasheet default kit — %s" % [
		uname, weapon_type_filter, str(_summarise_loadout_picks(models, loadout_key))])
	return true


# MA-LOADOUT: what each model of this unit carries, as weapon-id slugs, built
# from the datasheet rather than from the model's option menu. Returns [] — the
# "cannot tell" answer — rather than a guess.
#
# Each model starts on its ROLE's default kit (the datasheet's "equipped with"
# line: Boss Nob = big choppa + slugga, Boy = slugga + choppa). Then the "•"
# options the roster actually took are applied, as whole BUNDLES:
#
#   "Any number of Boyz can each have their slugga AND choppa replaced with
#    1 shoota AND 1 close combat weapon"
#
# so a roster recording "10x Shoota" tells us those ten Boyz hold a CLOSE COMBAT
# WEAPON, not the choppa they started with. That pairing is the whole reason this
# reads wargearOptions instead of just the default kit — the melee half of a swap
# is almost never written into the roster's wargear string.
#
# Bails (returns []) whenever the roster can't be read without guessing:
#   * a role that can't be matched to the datasheet's composition
#   * the roster NAMES an option's weapon but gives no count for it, and the
#     option's own constraint doesn't pin one ("any number of Custodian Guard
#     can replace their guardian spear with a sentinel blade" + a wargear line
#     that just says "Sentinel blade" = an unknown number of blades)
#   * a swap that wants more models than the role has
#   * a weapon the roster names that no model ends up holding — proof we did
#     not understand this roster
static func _datasheet_model_kits(unit: Dictionary) -> Array:
	var meta = unit.get("meta", {})
	var models = unit.get("models", [])
	var uname = str(meta.get("name", ""))
	if models.is_empty() or uname == "":
		return []

	# Slugs that name one of THIS datasheet's weapons (full and base forms), so
	# roster lines naming a role ("9x Boy") or an upgrade ("1x 'Ard Case") are
	# ignored rather than mistaken for wargear.
	var datasheet_slugs := {}
	for w in meta.get("weapons", []):
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var n = str(w.get("name", ""))
		if n == "":
			continue
		datasheet_slugs[UnitLoadoutResolver.slugify(n)] = true
		datasheet_slugs[UnitLoadoutResolver.slugify(UnitLoadoutResolver.base_weapon_name(n))] = true

	# Role per model, then its default kit. Kits are looked up under the
	# unit's datasheet key: its own name, or "<name> [1.0.19]" for a roster
	# built on a pre-codex datasheet (UnitLoadoutResolver.datasheet_key).
	var ds_key = UnitLoadoutResolver.datasheet_key(unit)
	var model_profiles = meta.get("model_profiles", {})
	var positional = _positional_roles(ds_key, models.size())
	var role_of: Array = []
	var kits: Array = []
	for i in range(models.size()):
		var model_type = str(models[i].get("model_type", ""))
		var role_names: Array = []
		if model_type != "":
			role_names.append(model_type)
			if model_profiles.has(model_type):
				var label = str(model_profiles[model_type].get("label", ""))
				if label != "":
					role_names.append(label)
		if i < positional.size():
			role_names.append(str(positional[i]))  # last resort, least specific
		var role = UnitLoadoutResolver.match_model_role(ds_key, role_names)
		if role == "":
			print("[MA-LOADOUT] %s: model %d's role could not be matched to the datasheet composition — left unresolved" % [uname, i])
			return []
		var kit = UnitLoadoutResolver.get_role_default_weapon_slugs(ds_key, role)
		if kit.is_empty():
			print("[MA-LOADOUT] %s: no default kit for role '%s' — left unresolved" % [uname, role])
			return []
		role_of.append(role)
		kits.append(kit.duplicate())

	# Roster wargear as {weapon slug: count}, where -1 means "named without a
	# count" — enough to know a swap happened, not enough to know how often.
	var option_item_slugs := {}
	for opt in UnitLoadoutResolver.get_wargear_options(ds_key):
		for bundle in opt.get("bundles", []):
			for b in bundle:
				option_item_slugs[str(b)] = true
	var wargear_counts := {}
	for entry in meta.get("wargear", []):
		for part in str(entry).split(","):
			var txt = str(part).strip_edges()
			if txt == "":
				continue
			var count := -1
			var space = txt.find(" ")
			if space > 0:
				var head = txt.substr(0, space)
				if head.ends_with("x") and head.substr(0, head.length() - 1).is_valid_int():
					count = int(head.substr(0, head.length() - 1))
					txt = txt.substr(space + 1).strip_edges()
			var paren = txt.find("(")
			if paren > 0:
				txt = txt.substr(0, paren).strip_edges()
			var s = UnitLoadoutResolver.slugify(txt)
			# A non-weapon item an option swaps in (Wolf Guard Terminators:
			# "Storm Bolter replaced with 1 Storm Shield") is evidence of that
			# swap too — "4x Storm Shield" = four storm bolters gone.
			if s == "" or not (datasheet_slugs.has(s) or option_item_slugs.has(s)):
				continue
			if count < 0 or int(wargear_counts.get(s, 0)) < 0:
				wargear_counts[s] = -1  # any count-less mention poisons the tally
			else:
				wargear_counts[s] = int(wargear_counts.get(s, 0)) + count

	# A weapon granted by more than one swap on this datasheet cannot attribute a
	# count to any single one of them: a Boy's shoota swap, his big-shoota swap
	# AND the Boss Nob's kombi swap all hand out a close combat weapon, so a
	# roster line of "9x Close combat weapon" says nothing about which was taken.
	# Only a weapon unique to ONE swap is evidence.
	var options = UnitLoadoutResolver.get_wargear_options(ds_key)
	var grant_counts := {}
	for option in options:
		for bundle in option.get("bundles", []):
			for s in bundle:
				grant_counts[s] = int(grant_counts.get(s, 0)) + 1
	# WP-M4b: Codex: Space Marines (11e) datasheets — the one-of roles (min = max
	# = 1 beside other roles: the Sergeant) for the swap ordering below.
	var sm11e_kits: bool = GameConstants.edition >= 11 and "ADEPTUS ASTARTES" in (meta.get("keywords", []) as Array).map(func(k): return str(k).to_upper())
	var sm11e_single_roles: Array = []
	if sm11e_kits:
		var sm_roles: Array = UnitLoadoutResolver.get_model_roles(ds_key)
		if sm_roles.size() > 1:
			for r in sm_roles:
				if int(r.get("min", 0)) == 1 and int(r.get("max", 0)) == 1:
					sm11e_single_roles.append(UnitLoadoutResolver.slugify(str(r.get("name", ""))))

	# Apply the swaps the roster took. A model can take several options as long
	# as each one still finds the weapons it replaces (a Grey Hunter Pack Leader
	# swaps his chainsword for a power fist AND his bolt pistol for a plasma
	# pistol); two options replacing the same weapon never claim one model.
	var swapped := {}  # model index -> true once any option changed its kit
	for option in options:
		var role_filter = str(option.get("role", ""))
		var replaces: Array = option.get("replaces", [])
		var candidates: Array = []
		for i in range(models.size()):
			if replaces.is_empty():
				if swapped.has(i):
					continue
			else:
				var still_has := true
				for gone in replaces:
					if gone not in kits[i]:
						still_has = false
						break
				if not still_has:
					continue
			if role_filter != "" and str(role_of[i]) != role_filter:
				continue
			candidates.append(i)
		if candidates.is_empty():
			continue
		# WP-M4b (Codex: Space Marines 11e): an "any model" swap goes to the
		# rank-and-file first — the one-of roles (the Sergeant) keep their kit
		# for their own options (Desolation Squad: 4 Superkrak + a Sergeant's
		# Vengor Launcher).
		if sm11e_kits and role_filter == "":
			var bulk: Array = candidates.filter(func(ci): return not str(role_of[ci]) in sm11e_single_roles)
			var singles: Array = candidates.filter(func(ci): return str(role_of[ci]) in sm11e_single_roles)
			candidates = bulk + singles

		for bundle in option.get("bundles", []):
			# A bundle was taken if the roster names a weapon it grants that the
			# candidates did not already have as standard.
			var evidence: Array = []
			for s in bundle:
				if not wargear_counts.has(s):
					continue
				if s in kits[candidates[0]]:
					continue  # already standard for this role — no evidence of a swap
				if int(grant_counts.get(s, 0)) > 1:
					continue  # granted by more than one swap — proves nothing
				evidence.append(s)
			if evidence.is_empty():
				continue

			var n := -1
			for s in evidence:
				var c = int(wargear_counts[s])
				if c < 0:
					print("[MA-LOADOUT] %s: roster names '%s' with no count and the datasheet allows any number — left unresolved" % [uname, s])
					return []
				n = maxi(n, c)
			if n <= 0:
				continue

			var cap = int(option.get("max_count", -1))
			var per_n = int(option.get("per_n_models", -1))
			if per_n > 0:
				cap = int(floor(float(models.size()) / float(per_n)))
			if cap >= 0 and n > cap:
				print("[MA-LOADOUT] %s: roster wants %d of a swap the datasheet caps at %d — left unresolved" % [uname, n, cap])
				return []
			if n > candidates.size():
				print("[MA-LOADOUT] %s: roster wants %d of a swap but only %d model(s) can take it — left unresolved" % [uname, n, candidates.size()])
				return []

			for k in range(n):
				var idx = int(candidates[k])
				var kit: Array = kits[idx]
				for gone in option.get("replaces", []):
					kit.erase(gone)
				for gained in bundle:
					if gained not in kit:
						kit.append(gained)
				kits[idx] = kit
				swapped[idx] = true
			# Consume the models this bundle used so a sibling bundle of the same
			# option (shoota boyz AND rokkit boyz) takes different ones.
			candidates = candidates.slice(n)
			if candidates.is_empty():
				break

	# WP-M4b (Codex: Space Marines 11e): a weapon two swaps can grant (a Scout
	# Sergeant's OR a Scout's Shotgun; the Desolation Sergeant's two Vengor
	# swaps) proves nothing above — give each still-missing one to the first
	# model, option by option, that can still take it (same cap rules).
	if sm11e_kits:
		for s in wargear_counts:
			var want := int(wargear_counts[s])
			if want <= 0 or int(grant_counts.get(s, 0)) <= 1:
				continue
			var have := 0
			for kit in kits:
				if kit.has(s):
					have += 1
			for option in options:
				if have >= want:
					break
				var amb_bundle: Array = []
				for bundle in option.get("bundles", []):
					if s in bundle:
						amb_bundle = bundle
				if amb_bundle.is_empty():
					continue
				var cap2 := int(option.get("max_count", -1))
				var per_n2 := int(option.get("per_n_models", -1))
				if per_n2 > 0:
					cap2 = int(floor(float(models.size()) / float(per_n2)))
				var taken := 0
				for i in range(models.size()):
					if have >= want or (cap2 >= 0 and taken >= cap2):
						break
					var rf := str(option.get("role", ""))
					if rf != "" and str(role_of[i]) != rf:
						continue
					if kits[i].has(s):
						continue
					var ok_r := true
					for gone in option.get("replaces", []):
						if gone not in kits[i]:
							ok_r = false
					if not ok_r or (option.get("replaces", []).is_empty() and swapped.has(i)):
						continue
					var kit2: Array = kits[i]
					for gone in option.get("replaces", []):
						kit2.erase(gone)
					for gained in amb_bundle:
						if gained not in kit2:
							kit2.append(gained)
					kits[i] = kit2
					swapped[i] = true
					have += 1
					taken += 1
			if have > 0:
				print("[MA-LOADOUT] %s: '%s' (granted by several swaps) given to %d model(s) by option order" % [uname, s, have])

	# Final proof of understanding: every weapon the roster names must be on some
	# model. If one is missing we misread the roster — say so instead of shipping
	# a loadout that quietly drops a weapon the player paid for.
	for s in wargear_counts:
		var found := false
		for kit in kits:
			if kit.has(s):
				found = true
				break
		if not found:
			print("[MA-LOADOUT] %s: roster names '%s' but no model ends up with it — left unresolved" % [uname, s])
			return []

	return kits


# MA-LOADOUT: the composition role each model index plays, worked out from the
# datasheet's unit composition alone ("1 Boss Nob" then "9-19 Boy" -> index 0 is
# the Boss Nob, 1..9 are Boyz). For units that carry no model_profiles this is
# the only thing that can tell a Boss Nob from a Boy.
#
# Deliberately narrow — it bails (returns []) unless the split is FORCED:
#   * at most ONE role may be open-ended (max > min); two open-ended roles (a
#     Lootas mob of 1-2 Spanners + 4-8 Lootas) can be filled several ways —
#     EXCEPT when the model count is a whole multiple of the minimum unit size
#     and every role scales by that multiple within its range: 11e codex units
#     come in fixed sizes ("1-2 Nob + 9-18 Boy" is sold as 10 or 20 models), so
#     a 20-model mob is 2 Nobs + 18 Boyz
#   * the fixed roles' counts plus the open-ended role's allowed range must add
#     up to exactly this unit's model count
# Anything else is ambiguous and the caller falls back to the datasheet menu.
# The army builder's other fixed split (gameformat.compositionCounts): every
# role at its minimum, the remainder filling roles from the LAST one up, each
# to its maximum (Wolf Scouts at 12: 1 Pack Leader, 2 Hunting Wolves, 9 Wolf
# Scouts). Only when the last role alone cannot take the remainder — otherwise
# the split is the one-open-ended-role case and stays undecidable here.
static func _positional_roles_fill_from_last(roles: Array, model_count: int) -> Array:
	var counts: Array = []
	var total := 0
	for r in roles:
		counts.append(int(r.get("min", 0)))
		total += int(r.get("min", 0))
	var rest := model_count - total
	var last := roles.size() - 1
	if last < 0 or rest <= 0:
		return []
	var last_room := int(roles[last].get("max", roles[last].get("min", 0))) - int(counts[last])
	if rest <= last_room:
		return []  # the last role could hold it all: not this builder split
	for k in range(last, -1, -1):
		var room := int(roles[k].get("max", roles[k].get("min", 0))) - int(counts[k])
		var add := mini(maxi(room, 0), rest)
		counts[k] = int(counts[k]) + add
		rest -= add
		if rest == 0:
			break
	if rest != 0:
		return []
	var out: Array = []
	for k in range(roles.size()):
		for _j in range(int(counts[k])):
			out.append(str(roles[k].get("name", "")))
	return out

static func _positional_roles(unit_name: String, model_count: int) -> Array:
	var roles = UnitLoadoutResolver.get_model_roles(unit_name)
	if roles.is_empty() or model_count <= 0:
		return []

	var flexible := -1
	var fixed_total := 0
	var counts: Array = []
	var open_ended := 0
	var min_total := 0
	for i in range(roles.size()):
		var mn := int(roles[i].get("min", 0))
		var mx := int(roles[i].get("max", mn))
		min_total += mn
		if mx > mn:
			open_ended += 1
	if open_ended > 1:
		# Codex fixed sizes: every role scales by the same whole multiple.
		if min_total <= 0 or model_count % min_total != 0:
			return _positional_roles_fill_from_last(roles, model_count)
		var mult := model_count / min_total
		var out_scaled: Array = []
		for i in range(roles.size()):
			var mn := int(roles[i].get("min", 0))
			var mx := int(roles[i].get("max", mn))
			if mn * mult > mx:
				return _positional_roles_fill_from_last(roles, model_count)  # cannot scale that far
			for _j in range(mn * mult):
				out_scaled.append(str(roles[i].get("name", "")))
		return out_scaled if out_scaled.size() == model_count else []

	for i in range(roles.size()):
		var mn := int(roles[i].get("min", 0))
		var mx := int(roles[i].get("max", mn))
		counts.append(mn)
		if mx > mn:
			flexible = i
		else:
			fixed_total += mn

	if flexible < 0:
		if fixed_total != model_count:
			return []
	else:
		var remainder := model_count - fixed_total
		var fmin := int(roles[flexible].get("min", 0))
		var fmax := int(roles[flexible].get("max", fmin))
		if remainder < fmin or remainder > fmax:
			return []
		counts[flexible] = remainder

	var out: Array = []
	for i in range(roles.size()):
		for _j in range(int(counts[i])):
			out.append(str(roles[i].get("name", "")))
	if out.size() != model_count:
		return []
	return out


# "9x Choppa, 1x Big choppa" style summary of a just-stamped loadout, for the log.
static func _summarise_loadout_picks(models: Array, loadout_key: String) -> Array:
	var tally := {}
	var order: Array = []
	for m in models:
		var key = ", ".join(PackedStringArray(m.get(loadout_key, [])))
		if not tally.has(key):
			tally[key] = 0
			order.append(key)
		tally[key] += 1
	var out: Array = []
	for key in order:
		out.append("%dx %s" % [int(tally[key]), key])
	return out

# MA-LOADOUT Phase 3 (Task B): the model IDs in this unit that carry a
# NON-majority ranged loadout — i.e. the special/heavy-weapon models that should
# look distinct on the board. Uses each model's ACTUALLY-reported ranged guns
# (the same resolved data get_unit_weapons uses — covers both wargear-resolved
# loadouts and model_type-resolved mobs like Lootas), so an over-reporting
# unresolved unit (every model shows the same menu) yields [] and gets no marker.
# Returns [] when every model carries the same guns (nobody stands out). Single
# source of truth shared by TokenVisual (draws the marker) and the tests.
static func get_special_weapon_model_ids(unit: Dictionary) -> Array:
	var models = unit.get("models", [])
	if models.size() < 2:
		return []
	_ensure_loadout_resolved(unit)
	var sig_of := {}       # model_id -> ranged-loadout signature
	var sig_counts := {}   # signature -> count
	for m in models:
		if not m.get("alive", true):
			continue
		var ids = _get_model_weapon_ids(unit, m, "Ranged")
		var sig = _loadout_signature(ids)
		sig_of[str(m.get("id", ""))] = sig
		sig_counts[sig] = int(sig_counts.get(sig, 0)) + 1
	if sig_counts.size() <= 1:
		return []  # every model reports the same guns -> nobody is "special"
	# Majority signature = the bulk/basic gun the rank-and-file carry.
	var majority_sig := ""
	var majority_n := -1
	for s in sig_counts:
		if int(sig_counts[s]) > majority_n:
			majority_n = int(sig_counts[s])
			majority_sig = s
	var out := []
	for mid in sig_of:
		if sig_of[mid] != majority_sig:
			out.append(mid)
	return out

# Stable order-independent signature for a per-model loadout (the sorted weapon
# names joined), so [A,B] and [B,A] compare equal.
static func _loadout_signature(loadout: Array) -> String:
	var names := []
	for n in loadout:
		names.append(str(n))
	names.sort()
	return "|".join(names)

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

	# MA-LOADOUT: resolve each model's actual ranged gun from wargear (once per
	# unit) so a mob reports the guns it carries, not every wargear option.
	_ensure_loadout_resolved(unit)

	# Convert modern weapons format to model-weapon mapping
	var models = unit.get("models", [])
	var result = {}

	# Assign weapons to all alive models using shared helper
	for model in models:
		var model_id = model.get("id", "")
		if model_id != "" and model.get("alive", true):
			result[model_id] = _get_model_weapon_ids(unit, model, "Ranged")

	# Include attached character weapons (combined unit shoots together)
	# 19.01: both sides of the linkage — a leader linked only by its own
	# `attached_to` (no forward entry) still shoots with its Attached unit.
	var attached_chars = attached_character_ids(unit_id, {"units": units})
	for char_id in attached_chars:
		var char_unit = units.get(char_id, {})
		if char_unit.is_empty():
			continue
		_ensure_loadout_resolved(char_unit)

		# Assign character weapons to character's alive models
		var char_models = char_unit.get("models", [])
		for char_model in char_models:
			var char_model_id = char_model.get("id", "")
			if char_model_id != "" and char_model.get("alive", true):
				# Use composite ID so damage routing works correctly
				var composite_id = "%s:%s" % [char_id, char_model_id]
				result[composite_id] = _get_model_weapon_ids(char_unit, char_model, "Ranged")

	# FIRING DECK (24.14): weapons selected from embarked models are treated as
	# being equipped by the TRANSPORT model for this activation. Each loan becomes
	# a distinct SYNTHETIC BEARER model id "<hull_id>@fd<i>" that carries the
	# loaned weapon's BASE id (not a per-weapon "__fd" alias). Modelling each loan
	# as one more bearer of the SAME base weapon lets identical guns collapse into
	# a single "<weapon> ×N" row and split-fire exactly like a squad's shared
	# weapon — while still contributing N models' worth of attacks (resolution
	# counts one attack-set per bearer). _get_model_by_id maps the synthetic id
	# back to the transport hull model, so BS / position / LoS use the transport
	# (identical to the previous alias, which also bound to the hull).
	var fd_loans = unit.get("flags", {}).get("firing_deck_weapons", [])
	if fd_loans is Array and not fd_loans.is_empty():
		var hull_model_id := ""
		for model in models:
			if model.get("alive", true) and model.get("id", "") != "":
				hull_model_id = model.get("id", "")
				break
		if hull_model_id != "":
			for i in range(fd_loans.size()):
				var loan = fd_loans[i]
				var base_weapon_id = str(loan.get("weapon_id", ""))
				if base_weapon_id == "":
					continue
				var bearer_id = "%s@fd%d" % [hull_model_id, i]
				result[bearer_id] = [base_weapon_id]

	return result

# Helper function to generate consistent weapon IDs from names
# Includes weapon_type to avoid collisions between ranged/melee variants with the same name
# (e.g., "Guardian spear" exists as both Ranged and Melee on Custodes units)
# PERF (2026-08-01): get_weapon_profile() resolves an id by scanning EVERY unit
# on the board × EVERY weapon on it, regenerating BOTH id forms for each one —
# ~200 _generate_weapon_id() calls per lookup on a 26-unit board. The function
# is pure (name + type in, id out), so memoise it. This is the hot inner loop
# of every profile lookup, and profile lookups happen dozens of times per attack
# sequence (and thousands of times per Mathhammer simulation).
static var _weapon_id_cache: Dictionary = {}

static func _generate_weapon_id(weapon_name: String, weapon_type: String = "") -> String:
	# The \u0001 separator can never appear in a datasheet weapon name, so the
	# two halves of the key can never alias each other.
	var cache_key := weapon_name + "\u0001" + weapon_type
	var cached = _weapon_id_cache.get(cache_key)
	if cached != null:
		return cached
	var generated := _generate_weapon_id_uncached(weapon_name, weapon_type)
	_weapon_id_cache[cache_key] = generated
	return generated

static func _generate_weapon_id_uncached(weapon_name: String, weapon_type: String = "") -> String:
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
	# FIRING DECK aliases ("<id>__fd<i>") resolve to the base weapon's profile.
	var fd_idx = weapon_id.find("__fd")
	if fd_idx > 0:
		return get_weapon_profile(weapon_id.substr(0, fd_idx), board)
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

## Hunter profiles (11e 04.01.03): "Hunter profiles can only target units with
## the specified keywords." Returns the keywords (upper case, any-of) a Hunter
## profile requires of its target, or [] when the profile is not a Hunter
## profile. Structured data wins (profile.target_restrictions.required_keywords_any,
## or an abilities entry {"id": "hunter", "keywords"/"keyword": …}); army files
## built by the current converter only carry the legacy "hunter" token in
## special_rules (the keyword parameters are dropped), so a bare Hunter token
## falls back to MONSTER/VEHICLE — the restriction of every Hunter profile in
## the shipped 11e catalogue (data/40kdc/weapons.json: 8/8 profiles).
const HUNTER_FALLBACK_TARGET_KEYWORDS: Array = ["MONSTER", "VEHICLE"]

static func hunter_profile_target_keywords(weapon_id: String, board: Dictionary = {}) -> Array:
	var profile = get_weapon_profile(weapon_id, board)
	if profile.is_empty():
		return []
	var out: Array = []
	var tr = profile.get("target_restrictions", null)
	if tr is Dictionary and tr.get("required_keywords_any", []) is Array:
		for k in tr.get("required_keywords_any", []):
			if not str(k).to_upper() in out:
				out.append(str(k).to_upper())
	var is_hunter := not out.is_empty()
	var abilities = profile.get("abilities", [])
	if abilities is Array:
		for ab in abilities:
			if typeof(ab) == TYPE_DICTIONARY and str(ab.get("id", "")) == "hunter":
				is_hunter = true
				var kws = ab.get("keywords", ab.get("keyword", []))
				if typeof(kws) == TYPE_STRING:
					kws = [kws]
				if kws is Array:
					for k in kws:
						if not str(k).to_upper() in out:
							out.append(str(k).to_upper())
	if not is_hunter:
		for tok in str(profile.get("special_rules", "")).split(","):
			if tok.strip_edges().to_lower() == "hunter":
				is_hunter = true
				break
	if not is_hunter:
		return []
	return out if not out.is_empty() else HUNTER_FALLBACK_TARGET_KEYWORDS.duplicate()

## Can `weapon_id`'s profile target `target_unit`? False only for a Hunter
## profile whose required keywords the target (or a character attached to it)
## lacks (04.01.03).
static func weapon_profile_can_target(weapon_id: String, target_unit: Dictionary, board: Dictionary = {}) -> bool:
	var required := hunter_profile_target_keywords(weapon_id, board)
	if required.is_empty():
		return true
	var kws: Array = []
	for k in target_unit.get("meta", {}).get("keywords", []):
		kws.append(str(k).to_upper())
	var units: Dictionary = board.get("units", {}) if not board.is_empty() else GameState.state.get("units", {})
	for cid in target_unit.get("attachment_data", {}).get("attached_characters", []):
		for k in units.get(str(cid), {}).get("meta", {}).get("keywords", []):
			kws.append(str(k).to_upper())
	for r in required:
		if r in kws:
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
## ISS-070 (11e 24.01): keyword-scoped weapon abilities. A scoped ability
## written "<token>: KEYWORD" (e.g. "lethal hits: vehicle") applies only
## against targets that have KEYWORD. Returns the scope keywords (upper),
## or [] when the ability is unscoped (the case for all current data).
static func get_weapon_ability_scope(weapon_id: String, board: Dictionary, token: String) -> Array:
	var profile = get_weapon_profile(weapon_id, board)
	if profile.is_empty():
		return []
	# Structured ability entries carry an explicit "scope" array.
	for ab in AbilityRegistry.from_weapon(profile):
		if ab is Dictionary:
			var nm = str(ab.get("id", "")).to_lower().replace("_", " ")
			if nm.contains(token.to_lower()):
				var sc = ab.get("scope", [])
				if sc is Array and not sc.is_empty():
					var out: Array = []
					for k in sc:
						out.append(str(k).to_upper())
					return out
	# Flat special_rules form: "<token>: keyword" (comma-delimited list).
	var sr = str(profile.get("special_rules", "")).to_lower()
	for part in sr.split(","):
		var p = str(part).strip_edges()
		if p.begins_with(token.to_lower()) and ":" in p:
			var kw = str(p.split(":")[1]).strip_edges()
			if kw != "":
				return [kw.to_upper()]
	return []


static func _ability_scope_matches(scope: Array, target_unit: Dictionary) -> bool:
	if scope.is_empty():
		return true
	if target_unit.is_empty():
		return true  # legacy caller with no target -> unscoped behaviour
	var tk: Array = []
	for k in target_unit.get("meta", {}).get("keywords", []):
		tk.append(str(k).to_upper())
	for s in scope:
		if s in tk:
			return true
	return false


## True only when a scoped ability does NOT apply to this target (so the
## caller must suppress it). False when unscoped or no target given.
static func _ability_suppressed_by_scope(weapon_id: String, board: Dictionary, token: String, target_unit: Dictionary) -> bool:
	if target_unit.is_empty():
		return false
	var scope = get_weapon_ability_scope(weapon_id, board, token)
	return not scope.is_empty() and not _ability_scope_matches(scope, target_unit)


static func has_lethal_hits(weapon_id: String, board: Dictionary = {}, target_unit: Dictionary = {}) -> bool:
	# ISS-070: 24.01 keyword-scope gate.
	if _ability_suppressed_by_scope(weapon_id, board, "lethal hits", target_unit):
		return false
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
static func get_sustained_hits_value(weapon_id: String, board: Dictionary = {}, target_unit: Dictionary = {}) -> Dictionary:
	# ISS-070: 24.01 keyword-scope gate.
	if _ability_suppressed_by_scope(weapon_id, board, "sustained hits", target_unit):
		return {"value": 0}
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
	# ISS-072 (24.02): duplicated weapon abilities are NOT cumulative — the
	# controlling player selects which instance applies. For [SUSTAINED
	# HITS X] we auto-select the best (highest) of all instances present,
	# rather than the first (and never the sum).
	var regex = RegEx.new()
	regex.compile("sustained hits\\s*(d?)(\\d+)")
	var best := {"value": 0, "is_dice": false}
	for result in regex.search_all(text):
		var is_dice = result.get_string(1) == "d"
		var value = result.get_string(2).to_int()
		# Compare on value; a flat number beats an equal-or-lower dice form
		# only when strictly higher (keep it simple: highest numeric wins).
		if value > best.value:
			best = {"value": value, "is_dice": is_dice}
	return best

# Check if a weapon has Sustained Hits
static func has_sustained_hits(weapon_id: String, board: Dictionary = {}, target_unit: Dictionary = {}) -> bool:
	return get_sustained_hits_value(weapon_id, board, target_unit).value > 0

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
static func has_devastating_wounds(weapon_id: String, board: Dictionary = {}, target_unit: Dictionary = {}) -> bool:
	# ISS-070: 24.01 keyword-scope gate.
	if _ability_suppressed_by_scope(weapon_id, board, "devastating wounds", target_unit):
		return false
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
static func has_twin_linked(weapon_id: String, board: Dictionary = {}, target_unit: Dictionary = {}) -> bool:
	# ISS-070: 24.01 keyword-scope gate.
	if _ability_suppressed_by_scope(weapon_id, board, "twin-linked", target_unit):
		return false
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

	# 11e negated form [ANTI-non-MONSTER/VEHICLE 2+] (Codex: Adeptus Custodes
	# Auriferous Orb, WP-C46): matches a target with NONE of the listed keywords.
	var neg = RegEx.new()
	neg.compile("anti-non-([a-z/ \\-]+?)\\s+(\\d+)\\+?")
	for nm in neg.search_all(text):
		var kws: Array = []
		for k in nm.get_string(1).split("/"):
			if k.strip_edges() != "":
				kws.append(k.strip_edges().to_upper())
		results.append({"keyword": "non-" + "/".join(PackedStringArray(kws)), "negated": kws, "threshold": nm.get_string(2).to_int()})

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
	# WP-O6: Codex: Orks (11e) conditional Lone Operative (Support Shokka, Boss
	# of da Hunt, Beast Snagga Following, Speednob Support, Da Grand Warlord's Ladz).
	if GameConstants.edition >= 11 and OrkAbilities11eScript.conditional_lone_operative(unit):
		return true
	# WP-S4: Space Wolves Iron Priest — Lone Operative while within 3" of a friendly SPACE WOLVES VEHICLE.
	if GameConstants.edition >= 11 and SWAbilities11eScript.conditional_lone_operative(unit):
		return true
	# WP-M4a: Iron Father / Techmarine (3" of an AA VEHICLE), Leader of Astartes (3" of AA INFANTRY).
	if GameConstants.edition >= 11 and SMAbilitiesAScript.conditional_lone_operative(unit):
		return true
	return false


## Audit #8 (11e 21.02): "Surge X\"" datasheet ability — the stated maximum
## distance of the unit's surge move. 0.0 = no rule grants one. Mirrors the
## Lone Operative X" parser; matched on the ability NAME starting with
## "surge" to avoid substring hits.
static func get_surge_move_inches(unit: Dictionary) -> float:
	for ab in unit.get("meta", {}).get("abilities", []):
		var nm := ""
		if ab is String:
			nm = ab
		elif ab is Dictionary:
			nm = str(ab.get("name", ""))
		if nm.to_lower().begins_with("surge"):
			var digits := ""
			for c in nm:
				if c >= "0" and c <= "9":
					digits += c
				elif digits != "":
					break
			if digits != "":
				return float(digits.to_int())
	return 0.0

## 11e core ability "Heal X" (sourced 2026-07-03; see the missions doc
## appendix): parses X from a "Heal X" ability name. 0 = no heal rule.
static func get_heal_amount(unit: Dictionary) -> int:
	for ab in unit.get("meta", {}).get("abilities", []):
		var nm := ""
		if ab is String:
			nm = ab
		elif ab is Dictionary:
			nm = str(ab.get("name", ""))
		if nm.to_lower().begins_with("heal"):
			var digits := ""
			for c in nm:
				if c >= "0" and c <= "9":
					digits += c
				elif digits != "":
					break
			if digits != "":
				return digits.to_int()
	return 0

## 11e Heal X resolution: X times — restore one lost wound to a wounded
## model; if no wounded models exist, return one destroyed model with 1
## wound. A unit at full strength/wounds wastes the remaining heals.
## Mutates the unit dict in place; returns {"healed": n, "revived": n}.
static func apply_heal_11e(unit: Dictionary, amount: int) -> Dictionary:
	var healed := 0
	var revived := 0
	for _i in range(amount):
		var wounded = null
		for model in unit.get("models", []):
			if not model.get("alive", true):
				continue
			if int(model.get("current_wounds", model.get("wounds", 1))) < int(model.get("wounds", 1)):
				wounded = model
				break
		if wounded != null:
			wounded["current_wounds"] = int(wounded.get("current_wounds", 0)) + 1
			healed += 1
			continue
		var dead = null
		for model in unit.get("models", []):
			if not model.get("alive", true):
				dead = model
				break
		if dead != null:
			dead["alive"] = true
			dead["current_wounds"] = 1
			revived += 1
			continue
		break  # everything alive at full wounds — excess heals are wasted
	return {"healed": healed, "revived": revived}

## Core "Feel No Pain X+" datasheet ability (by NAME — "Feel No Pain 5+"):
## X, or 0 when the unit has none. The bare "Feel No Pain" row of
## UnitAbilityManager (10e data) keeps its own grant_fnp path.
static func get_named_fnp(unit: Dictionary) -> int:
	var best := 0
	for ab in unit.get("meta", {}).get("abilities", []):
		var nm := ""
		if ab is String:
			nm = ab
		elif ab is Dictionary:
			nm = str(ab.get("name", ""))
		nm = nm.strip_edges().to_lower()
		if not nm.begins_with("feel no pain "):
			continue
		var digits := nm.substr(13).replace("+", "").strip_edges()
		if digits.is_valid_int() and int(digits) >= 2 and int(digits) <= 6:
			best = int(digits) if best == 0 else mini(best, int(digits))
	return best

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
	# OBJ-GAP-2: with MissionManager up, "within range" is its shared predicate
	# (base touching the hosting area of an 11e terrain objective); the marker
	# radius below is the headless fallback.
	var mm = Engine.get_main_loop().root.get_node_or_null("/root/MissionManager") if Engine.get_main_loop() != null else null

	for obj in objectives:
		if mm != null and mm.has_method("model_in_objective_range") and obj.get("position", null) != null:
			for model in unit.get("models", []):
				if model.get("alive", true) and model.get("position", null) != null \
						and mm.model_in_objective_range(model, obj):
					return true
			continue
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

static func _meta_has_enhancement(unit: Dictionary, enh_name: String) -> bool:
	for enh in unit.get("meta", {}).get("enhancements", []):
		if enh is String and enh == enh_name:
			return true
		if enh is Dictionary and str(enh.get("name", "")) == enh_name:
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


# SPESHUL SHELLS (More Dakka!): +1 AP on the unit's ranged attacks vs targets
# within 18" while the stratagem flag is set. Simplification: applies against
# any target within 18" (the 'closest eligible target' clause is not tracked
# per attack).
static func get_speshul_shells_ap_bonus(actor_unit: Dictionary, target_unit: Dictionary) -> int:
	# More Dakka! variant: +1 AP vs targets within 18"
	if actor_unit.get("flags", {}).get("effect_speshul_shells_md", false) \
			and is_target_within_range_inches(actor_unit, target_unit, 18.0):
		return 1
	# Rollin' Deff variant: +1 AP vs targets within 9"
	if actor_unit.get("flags", {}).get("effect_speshul_shells_rd", false) \
			and is_target_within_range_inches(actor_unit, target_unit, 9.0):
		return 1
	return 0

# DAKKASTORM (Kult of Speed): ranged SUSTAINED HITS 1, upgraded to
# SUSTAINED HITS 2 while targeting a unit within 9". Returns 0 without the flag.
static func get_dakkastorm_sustained_value(actor_unit: Dictionary, target_unit: Dictionary) -> int:
	if not actor_unit.get("flags", {}).get("effect_dakkastorm_kos", false):
		return 0
	return 2 if is_target_within_range_inches(actor_unit, target_unit, 9.0) else 1

# ---------------------------------------------------------------------------
# Codex: Orks (11e) detachment rules (WP-O34) — the logic lives in
# scripts/codex/orks/OrkDetachments11e.gd; the resolver paths only call the
# thin wrappers below (each returns the no-op value below edition 11).
# ---------------------------------------------------------------------------
static var _ork11e_det_script = null
static func ork11e_det():
	if _ork11e_det_script == null:
		_ork11e_det_script = load("res://scripts/codex/orks/OrkDetachments11e.gd")
	return _ork11e_det_script

## WP-O5: Codex: Orks (11e) enhancements (scripts/codex/orks/OrkEnhancements11e.gd).
## Attack modifiers arrive through ork11e_ab_mods (OrkAbilities11e merges
## them); the resolver paths read the keys "devastating", "anti" and
## "torrent" next to the weapon's own keywords.
static var _ork11e_enh_script = null
static func ork11e_enh():
	if _ork11e_enh_script == null:
		_ork11e_enh_script = load("res://scripts/codex/orks/OrkEnhancements11e.gd")
	return _ork11e_enh_script

## +1 to hit source ("" = none): Skyborne Loons, Unpredictable Genius (Seekerz).
static func ork11e_det_hit_plus_one(actor_unit: Dictionary, target_unit: Dictionary, is_melee: bool, board: Dictionary = {}) -> String:
	if GameConstants.edition < 11:
		return ""
	return ork11e_det().hit_plus_one_source(actor_unit, target_unit, is_melee, board)

## Re-roll hit rolls of 1 source ("" = none): Wreckin' and Lootin'.
static func ork11e_det_hit_reroll_ones(actor_unit: Dictionary, target_unit: Dictionary, is_melee: bool, board: Dictionary = {}) -> String:
	if GameConstants.edition < 11:
		return ""
	return ork11e_det().hit_reroll_ones_source(actor_unit, target_unit, is_melee, board)

## Strength bonus for one weapon: Try Dat Button! (+2 S), Powers of da Waaagh!.
static func ork11e_det_strength_bonus(actor_unit: Dictionary, weapon_id: String, board: Dictionary = {}) -> int:
	if GameConstants.edition < 11:
		return 0
	var sb: Dictionary = ork11e_det().strength_bonus(actor_unit, weapon_id, board)
	if int(sb.get("value", 0)) > 0:
		print("RulesEngine: [ork11e] Strength +%d for %s (%s)" % [int(sb.value), weapon_id, ", ".join(PackedStringArray(sb.get("sources", [])))])
	return int(sb.get("value", 0))

## Attacks bonus per model: Try Dat Button! (+1 A).
static func ork11e_det_attacks_per_model(actor_unit: Dictionary) -> int:
	if GameConstants.edition < 11:
		return 0
	return ork11e_det().attacks_bonus_per_model(actor_unit)

## Target toughness for this attacker: Unpredictable Genius (Runtified, -1 T).
static func ork11e_det_toughness(actor_unit: Dictionary, target_unit: Dictionary, toughness: int) -> int:
	if GameConstants.edition < 11:
		return toughness
	return ork11e_det().target_toughness(actor_unit, target_unit, toughness)

## Target invulnerable save for this attacker: Unpredictable Genius (Dat's Weird, 4+).
static func ork11e_det_invuln(actor_unit: Dictionary, target_unit: Dictionary, invuln: int) -> int:
	if GameConstants.edition < 11:
		return invuln
	return ork11e_det().target_invuln(actor_unit, target_unit, invuln)

## Range characteristic bonus (inches): Dakka! Dakka! Dakka! (+3" while riled up);
## Codex: Adeptus Custodes (11e) Aquilan Shield Favoured SALVUS +6" (WP-C46).
static func ork11e_det_range_bonus(actor_unit: Dictionary, weapon_profile: Dictionary = {}) -> float:
	if GameConstants.edition < 11:
		return 0.0
	# + WP-O5 Targetin' Squigs (+3" R, excluding [TORRENT]) — different rules stack.
	return ork11e_det().range_bonus_inches(actor_unit, weapon_profile) + cus11e_det().range_bonus_inches(actor_unit, weapon_profile) \
		+ float(ork11e_enh().range_bonus(actor_unit, weapon_profile)) \
		+ SMAbilitiesAScript.range_bonus_inches(actor_unit, weapon_profile)  # WP-M4a THUNDEROUS FORCE (Librarian in Terminator Armour): +6" R

# ---------------------------------------------------------------------------
# Codex: Adeptus Custodes (11e) detachment rules + enhancements (WP-C46) — the
# logic lives in scripts/codex/custodes/CustodesDetachments.gd (the façade for
# CustodesEnhancements.gd); the resolver paths only call the wrappers below
# (each one is a no-op below edition 11).
# ---------------------------------------------------------------------------
static var _cus11e_det_script = null
static func cus11e_det():
	if _cus11e_det_script == null:
		_cus11e_det_script = load("res://scripts/codex/custodes/CustodesDetachments.gd")
	return _cus11e_det_script

## Fold the codex hit-roll contributions (Moritoi Ancients, Radiant Mantle,
## Blinding Light, Oblivion Knight, Edge of the Blade) into the HitModifier
## bits and the modifier ledger. ctx.model_ids: the batch's firing models.
static func cus11e_apply_hit_effects(bits: int, ledger: Array, attacker: Dictionary, target: Dictionary, is_melee: bool, board: Dictionary, ctx: Dictionary = {}) -> int:
	if GameConstants.edition < 11:
		return bits
	for c in cus11e_det().hit_effects(attacker, target, is_melee, board, ctx):
		match str(c.get("kind", "")):
			"plus_one":
				bits |= HitModifier.PLUS_ONE
				ModifierLedger.note(ledger, str(c.source), ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE, str(c.get("note", "")))
			"minus_one":
				bits |= HitModifier.MINUS_ONE
				ModifierLedger.note(ledger, str(c.source), ModifierLedger.KIND_HIT, ModifierLedger.MINUS_ONE, str(c.get("note", "")))
			"reroll_ones":
				bits |= HitModifier.REROLL_ONES
				ModifierLedger.note(ledger, str(c.source), ModifierLedger.KIND_HIT, ModifierLedger.REROLL_ONES, str(c.get("note", "")))
		print("RulesEngine: [cus11e] %s — %s to hit (%s)" % [str(c.source), str(c.kind), str(attacker.get("id", "?"))])
	return bits

## Wound-roll counterpart (Gilded Guardians, Wardens of the Dark Cells,
## Companion's Watch, Assemblage of Might, Moritoi Ancients, Bane of
## Abominations, Oblivion Knight, Edge of the Blade).
static func cus11e_apply_wound_effects(bits: int, ledger: Array, attacker: Dictionary, target: Dictionary, is_melee: bool, strength: int, toughness: int, board: Dictionary, ctx: Dictionary = {}) -> int:
	if GameConstants.edition < 11:
		return bits
	for c in cus11e_det().wound_effects(attacker, target, is_melee, strength, toughness, board, ctx):
		match str(c.get("kind", "")):
			"plus_one":
				bits |= WoundModifier.PLUS_ONE
				ModifierLedger.note(ledger, str(c.source), ModifierLedger.KIND_WOUND, ModifierLedger.PLUS_ONE, str(c.get("note", "")))
			"minus_one":
				bits |= WoundModifier.MINUS_ONE
				ModifierLedger.note(ledger, str(c.source), ModifierLedger.KIND_WOUND, ModifierLedger.MINUS_ONE, str(c.get("note", "")))
			"reroll_ones":
				bits |= WoundModifier.REROLL_ONES
				ModifierLedger.note(ledger, str(c.source), ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_ONES, str(c.get("note", "")))
		print("RulesEngine: [cus11e] %s — %s to wound (%s)" % [str(c.source), str(c.kind), str(attacker.get("id", "?"))])
	return bits

## MAGNA IMPERATOR (Emperor's Chosen): re-roll ONE failed hit roll of this
## unit's attacks (once per selection to attack — CustodesDetachments). Re-rolls
## the first failed die that was not re-rolled already; mutates hit_evals /
## modified_rolls / reroll_data and returns {hit: 0|1, crit: 0|1} for the tallies.
static func cus11e_magna_reroll_hit(actor_unit: Dictionary, hit_evals: Array, modified_rolls: Array, reroll_data: Array, bs_per_attack: Array, bs: int, mods: int, crit_threshold: int, rng: RNGService, fail_band: int, ledger: Array, ranged: bool = true) -> Dictionary:
	var out := {"hit": 0, "crit": 0}
	if GameConstants.edition < 11:
		return out
	var rr_src := ""
	if cus11e_det().magna_imperator_available(actor_unit, "hit"):
		rr_src = "Magna Imperator"
	elif ranged and SMAbilitiesAScript.machine_spirit_available(actor_unit, "hit"):  # WP-M4a POWER OF THE MACHINE SPIRIT (Land Raider): re-roll one hit roll
		rr_src = "Power of the Machine Spirit"
	if rr_src == "":
		return out
	var i: int = cus11e_det().magna_pick_index(hit_evals, "is_hit")
	if i < 0:
		return out
	if rr_src == "Magna Imperator":
		cus11e_det().magna_imperator_consume(actor_unit, "hit")
	else:
		SMAbilitiesAScript.machine_spirit_consume(actor_unit, "hit")
	var new_raw: int = rng.roll_d6(1)[0]
	var attack_bs: int = int(bs_per_attack[i]) if i < bs_per_attack.size() else bs
	var no_rr: int = mods & ~(HitModifier.REROLL_ONES | HitModifier.REROLL_FAILED | HitModifier.REROLL_NON_CRIT)
	var ev = AttackSequence.evaluate_hit_roll(new_raw, attack_bs, no_rr, crit_threshold, rng, fail_band)
	var old_raw = hit_evals[i].get("raw", 0)
	hit_evals[i] = {"raw": old_raw, "final": ev.final_roll, "is_hit": ev.is_hit, "is_crit": ev.is_crit, "rerolled": true, "reroll_from": old_raw, "reroll_to": new_raw}
	if i < modified_rolls.size():
		modified_rolls[i] = ev.final_roll
	reroll_data.append({"original": old_raw, "rerolled_to": new_raw})
	ModifierLedger.note(ledger, rr_src, ModifierLedger.KIND_HIT, ModifierLedger.REROLL_FAILED, "one hit roll re-rolled (%d -> %d)" % [int(old_raw), new_raw])
	print("RulesEngine: [cus11e] %s — %s re-rolls one hit roll: %d -> %d (%s)" % [rr_src.to_upper(), str(actor_unit.get("id", "?")), int(old_raw), new_raw, "hit" if ev.is_hit else "miss"])
	if ev.is_hit:
		out.hit = 1
		if ev.is_crit:
			out.crit = 1
	return out

## MAGNA IMPERATOR: re-roll ONE failed wound roll. wound_evals entries are
## {raw, is_wound, is_crit, auto_fail, rerolled}; returns {wound, crit} (0|1).
static func cus11e_magna_reroll_wound(actor_unit: Dictionary, wound_evals: Array, wound_rolls: Array, reroll_data: Array, mods: int, wound_threshold: int, crit_threshold: int, rng: RNGService, ledger: Array, ranged: bool = true) -> Dictionary:
	var out := {"wound": 0, "crit": 0, "index": -1}
	if GameConstants.edition < 11:
		return out
	var rr_src := ""
	if cus11e_det().magna_imperator_available(actor_unit, "wound"):
		rr_src = "Magna Imperator"
	elif ranged and SMAbilitiesAScript.machine_spirit_available(actor_unit, "wound"):  # WP-M4a POWER OF THE MACHINE SPIRIT: re-roll one wound roll
		rr_src = "Power of the Machine Spirit"
	if rr_src == "":
		return out
	var i: int = cus11e_det().magna_pick_index(wound_evals, "is_wound")
	if i < 0:
		return out
	if rr_src == "Magna Imperator":
		cus11e_det().magna_imperator_consume(actor_unit, "wound")
	else:
		SMAbilitiesAScript.machine_spirit_consume(actor_unit, "wound")
	var new_raw: int = rng.roll_d6(1)[0]
	var no_rr: int = mods & ~(WoundModifier.REROLL_ONES | WoundModifier.REROLL_FAILED | WoundModifier.REROLL_ONES_TWOS)
	var ev = AttackSequence.evaluate_wound_roll(new_raw, no_rr, wound_threshold, crit_threshold, rng)
	var old_raw = wound_evals[i].get("raw", 0)
	wound_evals[i] = {"raw": old_raw, "is_wound": ev.is_wound, "is_crit": ev.is_crit, "auto_fail": ev.auto_fail, "rerolled": true, "reroll_from": old_raw, "reroll_to": new_raw}
	reroll_data.append({"original": old_raw, "rerolled_to": new_raw})
	ModifierLedger.note(ledger, rr_src, ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_FAILED, "one wound roll re-rolled (%d -> %d)" % [int(old_raw), new_raw])
	print("RulesEngine: [cus11e] %s — %s re-rolls one wound roll: %d -> %d (%s)" % [rr_src.to_upper(), str(actor_unit.get("id", "?")), int(old_raw), new_raw, "wound" if ev.is_wound else "fail"])
	out.index = i
	if ev.is_wound and not ev.auto_fail:
		out.wound = 1
		if ev.is_crit:
			out.crit = 1
	return out

## WP-M2a Codex: Space Marines (11e) IRONSTORM AUTO-TARGETERS (AA VEHICLE, not
## WALKER, ranged) / MARTIAL PARAGON (the bearer's unit): "re-roll one hit
## roll" — the Magna Imperator single-die re-roll, sourced from
## SMDetachmentsA.reroll_one_source (once per unit per phase per roll type).
static func sm11e_reroll_one_hit(actor_unit: Dictionary, is_melee: bool, hit_evals: Array, modified_rolls: Array, reroll_data: Array, bs_per_attack: Array, bs: int, mods: int, crit_threshold: int, rng: RNGService, fail_band: int, ledger: Array) -> Dictionary:
	var out := {"hit": 0, "crit": 0}
	if GameConstants.edition < 11:
		return out
	var smd = load("res://scripts/codex/space_marines/SMDetachmentsA.gd")
	var src: String = str(smd.reroll_one_source(actor_unit, "hit", is_melee))
	if src == "":
		return out
	var i: int = cus11e_det().magna_pick_index(hit_evals, "is_hit")
	if i < 0:
		return out
	smd.reroll_one_consume(actor_unit, "hit", src)
	var new_raw: int = rng.roll_d6(1)[0]
	var attack_bs: int = int(bs_per_attack[i]) if i < bs_per_attack.size() else bs
	var no_rr: int = mods & ~(HitModifier.REROLL_ONES | HitModifier.REROLL_FAILED | HitModifier.REROLL_NON_CRIT)
	var ev = AttackSequence.evaluate_hit_roll(new_raw, attack_bs, no_rr, crit_threshold, rng, fail_band)
	var old_raw = hit_evals[i].get("raw", 0)
	hit_evals[i] = {"raw": old_raw, "final": ev.final_roll, "is_hit": ev.is_hit, "is_crit": ev.is_crit, "rerolled": true}
	if i < modified_rolls.size():
		modified_rolls[i] = ev.final_roll
	reroll_data.append({"original": old_raw, "rerolled_to": new_raw})
	ModifierLedger.note(ledger, src, ModifierLedger.KIND_HIT, ModifierLedger.REROLL_FAILED, "one hit roll re-rolled (%d -> %d)" % [int(old_raw), new_raw])
	print("RulesEngine: [sm11e] %s — %s re-rolls one hit roll: %d -> %d (%s)" % [src, str(actor_unit.get("id", "?")), int(old_raw), new_raw, "hit" if ev.is_hit else "miss"])
	if ev.is_hit:
		out.hit = 1
		if ev.is_crit:
			out.crit = 1
	return out

## WP-M2a IRONSTORM AUTO-TARGETERS / MARTIAL PARAGON: "re-roll one wound roll".
static func sm11e_reroll_one_wound(actor_unit: Dictionary, is_melee: bool, wound_evals: Array, wound_rolls: Array, reroll_data: Array, mods: int, wound_threshold: int, crit_threshold: int, rng: RNGService, ledger: Array) -> Dictionary:
	var out := {"wound": 0, "crit": 0, "index": -1}
	if GameConstants.edition < 11:
		return out
	var smd = load("res://scripts/codex/space_marines/SMDetachmentsA.gd")
	var src: String = str(smd.reroll_one_source(actor_unit, "wound", is_melee))
	if src == "":
		return out
	var i: int = cus11e_det().magna_pick_index(wound_evals, "is_wound")
	if i < 0:
		return out
	smd.reroll_one_consume(actor_unit, "wound", src)
	var new_raw: int = rng.roll_d6(1)[0]
	var no_rr: int = mods & ~(WoundModifier.REROLL_ONES | WoundModifier.REROLL_FAILED | WoundModifier.REROLL_ONES_TWOS)
	var ev = AttackSequence.evaluate_wound_roll(new_raw, no_rr, wound_threshold, crit_threshold, rng)
	var old_raw = wound_evals[i].get("raw", 0)
	wound_evals[i] = {"raw": old_raw, "is_wound": ev.is_wound, "is_crit": ev.is_crit, "auto_fail": ev.auto_fail, "rerolled": true}
	reroll_data.append({"original": old_raw, "rerolled_to": new_raw})
	ModifierLedger.note(ledger, src, ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_FAILED, "one wound roll re-rolled (%d -> %d)" % [int(old_raw), new_raw])
	print("RulesEngine: [sm11e] %s — %s re-rolls one wound roll: %d -> %d (%s)" % [src, str(actor_unit.get("id", "?")), int(old_raw), new_raw, "wound" if ev.is_wound else "fail"])
	out.index = i
	if ev.is_wound and not ev.auto_fail:
		out.wound = 1
		if ev.is_crit:
			out.crit = 1
	return out

## Melee weapon-ability grants (Martial Mastery, Flawless Bladework, From the
## Hall of Armouries, Auric Exemplar): {sustained, lethal, devastating: source,
## cleave: int, cleave_source}.
static func cus11e_melee_grants(attacker: Dictionary, target: Dictionary, board: Dictionary = {}) -> Dictionary:
	if GameConstants.edition < 11:
		return {"sustained": "", "lethal": "", "devastating": "", "cleave": 0, "cleave_source": ""}
	return cus11e_det().melee_weapon_grants(attacker, target, board)

## Memento Moritoi: the bearer's melee attacks +1 A, S and D ({a, s, d, source}).
static func cus11e_melee_profile_bonus(attacker: Dictionary) -> Dictionary:
	var none := {"a": 0, "s": 0, "d": 0, "source": ""}
	if GameConstants.edition < 11:
		return none
	var e = cus11e_det().enh()
	return e.melee_profile_bonus(attacker) if e else none

## A Damage characteristic string with +n ("2" -> "3", "D6" -> "D6+1",
## "D3+3" -> "D3+4"). n <= 0 returns the string unchanged.
static func cus11e_damage_raw_plus(raw: String, n: int) -> String:
	if n <= 0:
		return raw
	var s := raw.strip_edges()
	if s.is_valid_int():
		return str(int(s) + n)
	var plus := s.rfind("+")
	if plus > 0 and s.substr(plus + 1).is_valid_int():
		return "%s+%d" % [s.substr(0, plus), int(s.substr(plus + 1)) + n]
	return "%s+%d" % [s, n]

## Not a Shell Wasted: +N Attacks per firing model for ranged weapons.
static func cus11e_ranged_attacks_per_model(actor_unit: Dictionary, board: Dictionary = {}) -> int:
	if GameConstants.edition < 11:
		return 0
	var e = cus11e_det().enh()
	return int(e.ranged_attacks_bonus(actor_unit, board)) if e else 0

## The better of `current` and the codex invulnerable saves (Flare Shields 4+
## vs ranged, Eagle's Eye 3+). 0 = none.
static func cus11e_invuln(target_unit: Dictionary, is_melee: bool, current: int, board: Dictionary = {}) -> int:
	if GameConstants.edition < 11:
		return current
	return cus11e_det().better_invuln(current, target_unit, is_melee, board)

# ---------------------------------------------------------------------------
# Codex: Orks (11e) — "when a unit is selected to shoot" stratagems
# (scripts/stratagems/ork_codex/OrkCodexShooting.gd). The handler writes these
# flags on the shooter and every component of its Attached unit until the end
# of the phase; each helper below is read from EVERY ranged resolver path
# (interactive _resolve_assignment_hits / _resolve_assignment_wounds /
# prepare_save_resolution, auto _resolve_assignment, the single-die Command
# Re-roll) and from the ShootingController forecast. Per-target conditions are
# evaluated against the target of each attack. VINDICTIVE ARTILLERISTS'
# [LETHAL HITS] / [HAZARDOUS] reuse the ranged-only effect_lethal_hits_ranged /
# effect_grant_hazardous flags, whose consumers match the rule exactly.
# ---------------------------------------------------------------------------
# ── WP-O6: Codex: Orks (11e) DATASHEET abilities (scripts/codex/orks/OrkAbilities11e.gd).
# One aggregator call per attack batch (attack_mods) is folded into every
# resolver path by the adapters below; target-only defences (invulnerable
# save, -1 D, -1 AP) live in the EffectPrimitives getters.
const OrkAbilities11eScript = preload("res://scripts/codex/orks/OrkAbilities11e.gd")
# WP-C7: Codex: Adeptus Custodes (11e) DATASHEET abilities (scripts/codex/custodes/CustodesAbilities.gd).
const CustodesAbilities11eScript = preload("res://scripts/codex/custodes/CustodesAbilities.gd")
# WP-S4: Codex: Space Marines (11e) Space Wolves DATASHEET abilities (scripts/codex/space_wolves/SWAbilities11e.gd).
const SWAbilities11eScript = preload("res://scripts/codex/space_wolves/SWAbilities11e.gd")
# WP-M4c: Codex: Space Marines (11e) generic DATASHEET abilities, M4c datasheets (scripts/codex/space_marines/SMAbilitiesC.gd).
const SMAbilitiesC11eScript = preload("res://scripts/codex/space_marines/SMAbilitiesC.gd")
# WP-M4a: Codex: Space Marines (11e) generic DATASHEET abilities, M4a list (scripts/codex/space_marines/SMAbilitiesA.gd).
const SMAbilitiesAScript = preload("res://scripts/codex/space_marines/SMAbilitiesA.gd")

static func ork11e_ab_mods(actor_unit: Dictionary, target_unit: Dictionary, weapon_profile: Dictionary, is_melee: bool, board: Dictionary, bearer_ids: Array = []) -> Dictionary:
	if GameConstants.edition < 11:
		return OrkAbilities11eScript._empty_mods()
	var ab_mods: Dictionary = OrkAbilities11eScript.attack_mods(actor_unit, target_unit, weapon_profile, is_melee, board, bearer_ids)
	CustodesAbilities11eScript.merge_attack_mods(ab_mods, actor_unit, target_unit, weapon_profile, is_melee, board, bearer_ids)  # WP-C7: Codex: Adeptus Custodes (11e) datasheet abilities ride the same aggregator
	# WP-S2: Codex: Space Marines (11e) Space Wolves detachment rules + enhancements (Legendary Slayers,
	# Hunter's Eye, Ferocious Strike, A Giant Amongst Giants) ride the same aggregator.
	load("res://scripts/codex/space_wolves/SWDetachments11e.gd").merge_attack_mods(ab_mods, actor_unit, target_unit, weapon_profile, is_melee, board, bearer_ids)
	SWAbilities11eScript.merge_attack_mods(ab_mods, actor_unit, target_unit, weapon_profile, is_melee, board, bearer_ids)  # WP-S4: Space Wolves (11e) datasheet abilities ride the same aggregator
	load("res://scripts/codex/space_marines/SMDetachmentsA.gd").merge_attack_mods(ab_mods, actor_unit, target_unit, weapon_profile, is_melee, board, bearer_ids)  # WP-M2a: Codex: Space Marines (11e) detachments A (Laurels, Gunnery Honours, Combined Deployment, Venator, Vanguard Ambushers, Ancient Exhortation)
	load("res://scripts/codex/space_marines/SMDetachmentsB.gd").merge_attack_mods(ab_mods, actor_unit, target_unit, weapon_profile, is_melee, board, bearer_ids)  # WP-M2b: Codex: Space Marines (11e) generic detachments B (Enduring Vengeance, Walking Fortress, enhancements)
	_sm11e_abilities_b().merge_attack_mods(ab_mods, actor_unit, target_unit, weapon_profile, is_melee, board, bearer_ids)  # WP-M4b: Codex: Space Marines (11e) M4b datasheet abilities ride the same aggregator
	SMAbilitiesC11eScript.merge_attack_mods(ab_mods, actor_unit, target_unit, weapon_profile, is_melee, board, bearer_ids)  # WP-M4c: Space Marines (11e) M4c datasheet abilities ride the same aggregator
	load("res://scripts/codex/space_marines/SMCodexB.gd").merge_attack_mods(ab_mods, actor_unit, target_unit, weapon_profile, is_melee, board, bearer_ids)  # Codex: Space Marines (11e) WP-M3b (SMCodexB.gd): detachment stratagem attack modifiers
	SMAbilitiesAScript.merge_attack_mods(ab_mods, actor_unit, target_unit, weapon_profile, is_melee, board, bearer_ids)  # WP-M4a: Codex: Space Marines (11e) generic datasheet abilities (M4a list)
	return ab_mods

## WP-M4b: Codex: Space Marines (11e) M4b datasheet abilities (scripts/codex/space_marines/SMAbilitiesB.gd), loaded lazily.
static func _sm11e_abilities_b():
	return load("res://scripts/codex/space_marines/SMAbilitiesB.gd")

## Fold the datasheet-ability hit modifiers into HitModifier bits (+ ledger).
static func ork11e_ab_hit_bits(bits: int, ledger: Array, ab: Dictionary) -> int:
	for s in ab.get("sources", []):
		if str(s.get("kind", "")) == "hit":
			ModifierLedger.note(ledger, str(s.get("name", "")), ModifierLedger.KIND_HIT, str(s.get("effect", "")), str(s.get("note", "")))
	if ab.get("hit_plus", false):
		bits |= HitModifier.PLUS_ONE
	if ab.get("hit_minus", false):
		bits |= HitModifier.MINUS_ONE
	match str(ab.get("hit_reroll", "")):
		"ones":
			bits |= HitModifier.REROLL_ONES
		"failed":
			bits |= HitModifier.REROLL_FAILED
	if ab.get("ignore_hit_penalties", false) and (bits & HitModifier.MINUS_ONE):
		bits &= ~HitModifier.MINUS_ONE
		ModifierLedger.mark_ignored(ledger, ModifierLedger.KIND_HIT, [ModifierLedger.MINUS_ONE])
	if not ab.get("sources", []).is_empty():
		print("RulesEngine: [WP-O6] Ork datasheet hit modifiers: %s" % str(ab.get("sources", []).map(func(x): return "%s %s" % [x.name, x.effect])))
	return bits

## Fold the datasheet-ability wound modifiers into WoundModifier bits (+ ledger).
static func ork11e_ab_wound_bits(bits: int, ledger: Array, ab: Dictionary) -> int:
	for s in ab.get("sources", []):
		if str(s.get("kind", "")) == "wound":
			ModifierLedger.note(ledger, str(s.get("name", "")), ModifierLedger.KIND_WOUND, str(s.get("effect", "")), str(s.get("note", "")))
	if ab.get("wound_plus", false):
		bits |= WoundModifier.PLUS_ONE
	match str(ab.get("wound_reroll", "")):
		"ones":
			bits |= WoundModifier.REROLL_ONES
		"ones_twos":  # WP-M2a Venator Omni-auspex (assault doctrine): re-roll wound rolls of 1-2
			bits |= WoundModifier.REROLL_ONES_TWOS
		"failed":
			bits |= WoundModifier.REROLL_FAILED
	return bits

## WP-S4: Codex: Space Marines (11e) Gift of the Iron Wolf — "that VEHICLE
## model's attacks can ignore modifiers to ... wound rolls": every -1 to wound
## is ignored (the +1s are kept — the attacker's choice).
static func sw11e_ignore_wound_penalties(bits: int, ledger: Array, ab: Dictionary) -> int:
	if not bool(ab.get("ignore_wound_penalties", false)) or not (bits & WoundModifier.MINUS_ONE):
		return bits
	ModifierLedger.note(ledger, "Gift of the Iron Wolf", ModifierLedger.KIND_WOUND, ModifierLedger.IGNORED, "wound-roll penalties ignored")
	ModifierLedger.mark_ignored(ledger, ModifierLedger.KIND_WOUND, [ModifierLedger.MINUS_ONE])
	print("RulesEngine: [WP-S4] Gift of the Iron Wolf — ignoring wound-roll penalties")
	return bits & ~WoundModifier.MINUS_ONE

## Hardy Bioniks (Painboss): S > T attacks that target the unit have -1 to wound.
static func ork11e_ab_wound_penalty(target_unit: Dictionary, strength: int, toughness: int) -> bool:
	return GameConstants.edition >= 11 and (OrkAbilities11eScript.incoming_wound_penalty(target_unit, strength, toughness) \
		or CustodesAbilities11eScript.incoming_wound_penalty(target_unit, strength, toughness)  # WP-C7: Unyielding Ancient / Praesidium Shield (Sentinel Guard)
		or SWAbilities11eScript.incoming_wound_penalty(target_unit, strength, toughness)  # WP-S4: Legendary Tenacity / Rugged Resilience (Space Wolves)
		or load("res://scripts/codex/space_marines/SMDetachmentsB.gd").incoming_wound_penalty(target_unit, strength, toughness)  # WP-M2b: Indefatigable Fortitude / Indomitable Defence (Codex: Space Marines 11e)
		or _sm11e_abilities_b().incoming_wound_penalty(target_unit, strength, toughness)  # WP-M4b: Never Shall the Standard Fall
		or SMAbilitiesC11eScript.incoming_wound_penalty(target_unit, strength, toughness)  # WP-M4c: Duty Eternal (Redemptor Dreadnought)
		or SMAbilitiesAScript.incoming_wound_penalty(target_unit, strength, toughness))  # WP-M4a: Rites of Tempering (Iron Father Feirros)

## The ledger name of the S > T -1 to wound above (Hardy Bioniks, or the
## Custodes Unyielding Ancient / Praesidium Shield — WP-C7).
static func ork11e_ab_wound_penalty_name(target_unit: Dictionary, strength: int, toughness: int) -> String:
	var cus_src: String = CustodesAbilities11eScript.incoming_wound_penalty_source(target_unit, strength, toughness)
	if cus_src == "":
		cus_src = SWAbilities11eScript.incoming_wound_penalty_source(target_unit, strength, toughness)  # WP-S4: Legendary Tenacity / Rugged Resilience
	if cus_src == "":
		cus_src = load("res://scripts/codex/space_marines/SMDetachmentsB.gd").incoming_wound_penalty_source(target_unit, strength, toughness)  # WP-M2b: Indefatigable Fortitude / Indomitable Defence
	if cus_src == "":
		cus_src = _sm11e_abilities_b().incoming_wound_penalty_source(target_unit, strength, toughness)  # WP-M4b: Never Shall the Standard Fall
	if cus_src == "":
		cus_src = SMAbilitiesC11eScript.incoming_wound_penalty_source(target_unit, strength, toughness)  # WP-M4c: Duty Eternal
	if cus_src == "":
		cus_src = SMAbilitiesAScript.incoming_wound_penalty_source(target_unit, strength, toughness)  # WP-M4a: Rites of Tempering
	return cus_src if cus_src != "" else "Hardy Bioniks"

const ORK11E_FLAG_CLOSE_RANGE_DAKKA := "ork11e_close_range_dakka"
const ORK11E_FLAG_VINDICTIVE_ARTILLERISTS := "ork11e_vindictive_artillerists"  # = chosen variant id
const ORK11E_FLAG_DRIVE_BY_BUSTIN := "ork11e_drive_by_bustin"
const ORK11E_FLAG_KUSTOM_DAKKA := "ork11e_kustom_dakka"
const ORK11E_FLAG_GLOWIN_DAKKA := "ork11e_glowin_dakka"
const ORK11E_FLAG_NEVER_ENOUGH_DAKKA := "ork11e_never_enough_dakka"
const ORK11E_FLAG_LONG_UNCONTROLLED_BURSTS := "ork11e_long_uncontrolled_bursts"
const ORK11E_FLAG_DAKKASTORM := "ork11e_dakkastorm"

# CLOSE-RANGE DAKKA: ranged attacks have [RAPID FIRE 1], or +1 to the value of
# an existing [RAPID FIRE] — either way the attack's RAPID FIRE value rises by
# 1 (0 -> 1). Applied after every other RAPID FIRE grant ("already has").
static func ork11e_rapid_fire_bonus(actor_unit: Dictionary, weapon_profile: Dictionary) -> int:
	if not actor_unit.get("flags", {}).get(ORK11E_FLAG_CLOSE_RANGE_DAKKA, false):
		return 0
	if str(weapon_profile.get("type", "Ranged")).to_lower() == "melee":
		return 0
	return 1

# NEVER ENOUGH DAKKA / DAKKASTORM / VINDICTIVE ARTILLERISTS (Sustained Hits or
# the overcharged variant): ranged [SUSTAINED HITS 1]. Callers apply it only
# when the weapon has no SUSTAINED HITS of its own — duplicates are not
# cumulative and the controlling player picks the better instance (core rules,
# weapon abilities), and SUSTAINED HITS 1 is never better than an existing X.
static func ork11e_ranged_sustained_hits(actor_unit: Dictionary) -> int:
	var flags = actor_unit.get("flags", {})
	if flags.get(ORK11E_FLAG_NEVER_ENOUGH_DAKKA, false) or flags.get(ORK11E_FLAG_DAKKASTORM, false):
		return 1
	if str(flags.get(ORK11E_FLAG_VINDICTIVE_ARTILLERISTS, "")) in ["sustained_hits", "overcharge"]:
		return 1
	return 0

# DRIVE-BY BUSTIN': +1 to hit rolls for ranged attacks made with weapons
# selected for the Firing Deck ability. Firing Deck loans are bearer ids
# "<hull>@fd<i>" (get_unit_weapons), so the bonus is decided per bearer.
static func ork11e_drive_by_bustin_active(actor_unit: Dictionary) -> bool:
	return bool(actor_unit.get("flags", {}).get(ORK11E_FLAG_DRIVE_BY_BUSTIN, false))

static func ork11e_is_firing_deck_bearer(bearer_id) -> bool:
	return str(bearer_id).find("@fd") != -1

# KUSTOM DAKKA: +1 to wound for ranged attacks that target a unit that is not
# a MONSTER or VEHICLE unit.
static func ork11e_kustom_dakka_wound_bonus(actor_unit: Dictionary, target_unit: Dictionary) -> int:
	if not actor_unit.get("flags", {}).get(ORK11E_FLAG_KUSTOM_DAKKA, false):
		return 0
	if target_unit.is_empty() or unit_has_keyword(target_unit, "MONSTER") or unit_has_keyword(target_unit, "VEHICLE"):
		return 0
	return 1

# GLOWIN' DAKKA: +1 AP for ranged attacks that target a unit within 9" of the
# attacking unit (closest models, edge to edge; both Attached units whole).
static func ork11e_glowin_dakka_ap_bonus(actor_unit: Dictionary, target_unit: Dictionary, board: Dictionary = {}) -> int:
	if not actor_unit.get("flags", {}).get(ORK11E_FLAG_GLOWIN_DAKKA, false):
		return 0
	if target_unit.is_empty():
		return 0
	var a_models: Array = actor_unit.get("models", [])
	var t_models: Array = target_unit.get("models", [])
	if not board.is_empty():
		if str(actor_unit.get("id", "")) != "":
			a_models = attached_unit_models(str(actor_unit.get("id", "")), board)
		if str(target_unit.get("id", "")) != "":
			t_models = attached_unit_models(str(target_unit.get("id", "")), board)
	for am in a_models:
		if not am.get("alive", true) or am.get("position", null) == null:
			continue
		for tm in t_models:
			if not tm.get("alive", true) or tm.get("position", null) == null:
				continue
			if Measurement.model_to_model_distance_inches(am, tm) <= 9.0:
				return 1
	return 0

# Improve an AP value by `by` (02.02.06: "improving an AP of 0 by 1 would
# result in an AP of -1"). Army weapon profiles carry AP as the signed value
# (-1 for AP-1, see get_weapon_profile) and the 11e save step reads it signed
# (Allocation.apply_save_rolls: armour needed = Sv - ap), so improving makes
# the value more negative — AP 0 becomes -1. Only a value already stored as a
# positive magnitude (the legacy WEAPON_PROFILES table) grows upwards instead.
static func ork11e_improve_ap(ap: int, by: int) -> int:
	return improve_ap(ap, by)

## AP SIGN CONVENTION (r4:WS-6). Army weapon profiles store AP signed (-2 for
## AP-2; get_weapon_profile / _parse_ap_value), and the 11e save step reads it
## signed (Allocation.apply_save_rolls: armour needed = Sv - ap); the legacy
## _calculate_save_needed takes |ap|. Only the legacy WEAPON_PROFILES table
## still stores a positive magnitude (2 for AP-2). EVERY AP modifier must go
## through these two helpers so "+1 AP" always makes the save WORSE:
##   improve_ap — signed / zero: ap - by (AP 0 -> -1, 02.02.06); legacy
##                positive magnitude: ap + by. Never pushes a signed value
##                positive, so the sign test stays unambiguous.
##   worsen_ap  — reduce the AP toward 0 (never past it): signed min(0, ap + by);
##                legacy positive magnitude max(0, ap - by).
static func improve_ap(ap: int, by: int) -> int:
	if by <= 0:
		return ap
	return ap + by if ap > 0 else ap - by

static func worsen_ap(ap: int, by: int) -> int:
	if by <= 0 or ap == 0:
		return ap
	return maxi(0, ap - by) if ap > 0 else mini(0, ap + by)

# LONG, UNCONTROLLED BURSTS: ranged attacks that target a FLY unit can re-roll
# the hit roll (the engine re-rolls failed hits — the "all" convention).
static func ork11e_long_uncontrolled_bursts_reroll(actor_unit: Dictionary, target_unit: Dictionary) -> bool:
	if not actor_unit.get("flags", {}).get(ORK11E_FLAG_LONG_UNCONTROLLED_BURSTS, false):
		return false
	return not target_unit.is_empty() and unit_has_keyword(target_unit, "FLY")

# BIGGER SHELLS FOR BIGGER GITZ (Dread Mob): +1 to Wound vs MONSTER/VEHICLE;
# when pushed, +1 Damage against those targets as well.
static func get_bigger_shells_wound_bonus(actor_unit: Dictionary, target_unit: Dictionary) -> int:
	if not actor_unit.get("flags", {}).get("effect_bigger_shells", false):
		return 0
	if unit_has_keyword(target_unit, "MONSTER") or unit_has_keyword(target_unit, "VEHICLE"):
		return 1
	return 0

static func get_bigger_shells_damage_bonus(actor_unit: Dictionary, target_unit: Dictionary) -> int:
	if not actor_unit.get("flags", {}).get("effect_bigger_shells_push", false):
		return 0
	if unit_has_keyword(target_unit, "MONSTER") or unit_has_keyword(target_unit, "VEHICLE"):
		return 1
	return 0

# Generic mortal-wound application to a unit by id (Supa-glowy Fing,
# CONNIVING RUNTS, ...). Allocates via the 11e mortal-wound path and returns
# {diffs, mortal_wounds, casualties}.
static func apply_mortal_wounds_to_unit(target_unit_id: String, mw: int, board: Dictionary, rng: RNGService = null) -> Dictionary:
	var result = {"diffs": [], "mortal_wounds": mw, "casualties": 0, "dice": []}
	var target = board.get("units", {}).get(target_unit_id, {})
	if mw <= 0 or target.is_empty():
		return result
	# Feel No Pain vs mortal wounds (incl. Aegis of the Emperor, WP-C3).
	var mw_left := mortal_wounds_after_fnp(target, mw, rng, result.dice)
	var out = Allocation.apply_mortal_wounds_11e(target, mw_left, CasualtyPreference.engine_auto_preference(target, board))
	_materialize_allocation_11e(result, target, target_unit_id, out.remaining, out.models_destroyed)
	result.casualties = out.models_destroyed.size()
	return result

# ARMOURED DUELLISTS (Blitz Brigade): +1 to Hit and +1 to Wound while
# targeting a MONSTER or VEHICLE unit.
static func get_armoured_duellists_bonus(actor_unit: Dictionary, target_unit: Dictionary) -> int:
	if not actor_unit.get("flags", {}).get("effect_armoured_duellists", false):
		return 0
	if unit_has_keyword(target_unit, "MONSTER") or unit_has_keyword(target_unit, "VEHICLE"):
		return 1
	return 0

# CONNIVING RUNTS (Dread Mob): roll one D6 — on a 4+, the enemy unit that just
# moved suffers D3+1 mortal wounds (the Gretchin unit's Normal move is set up
# by MovementPhase afterwards).
static func resolve_conniving_runts(target_unit_id: String, board: Dictionary, rng: RNGService = null) -> Dictionary:
	if rng == null:
		rng = make_rng()
	var roll = rng.roll_d6(1)[0]
	var result = {"diffs": [], "roll": roll, "mortal_wounds": 0, "casualties": 0}
	if roll >= 4:
		var mw = rng.rng.randi_range(1, 3) + 1
		var applied = apply_mortal_wounds_to_unit(target_unit_id, mw, board, rng)
		result.diffs = applied.diffs
		result.mortal_wounds = mw
		result.casualties = applied.casualties
	print("RulesEngine: CONNIVING RUNTS vs %s — rolled %d -> %d mortal wound(s)" % [target_unit_id, roll, int(result.mortal_wounds)])
	return result

# PREY (Da Big Hunt detachment rule): each time a BEAST SNAGGA model makes an
# attack (ranged or melee) that targets its owner's Prey, improve the AP of
# that attack by 1. The Prey marker lives on the target unit's flags
# (is_prey_of_<player>, set by FactionAbilityManager at Command phase start).
static func get_prey_ap_bonus(actor_unit: Dictionary, target_unit: Dictionary) -> int:
	# Codex: Orks (11e) — Da Hunt is On / Try Dat Button! +1 AP (WP-O34), every resolver path.
	if GameConstants.edition >= 11:
		return ork11e_det().attack_ap_bonus(actor_unit, target_unit)
	var prey_owner = int(actor_unit.get("owner", 0))
	if prey_owner <= 0:
		return 0
	if not target_unit.get("flags", {}).get("is_prey_of_%d" % prey_owner, false):
		return 0
	if not unit_has_keyword(actor_unit, "BEAST SNAGGA"):
		return 0
	return 1

# The effect_minus_wound_s_gt_t defender flag (IMPERVIOUS): -1 to incoming
# Wound rolls when the attack's Strength is greater than the target unit's
# Toughness. (WP-O5: the 10e Da Big Hunt Surly as a Squiggoth no longer feeds
# it — the codex enhancement is Brute Bosses' set-back-up rule.)
static func get_s_gt_t_wound_penalty(target_unit: Dictionary, board: Dictionary, strength: int, toughness: int) -> int:
	if strength <= toughness:
		return WoundModifier.NONE
	if not FactionAbilityManager.unit_has_s_gt_t_wound_penalty(target_unit, board.get("units", {})):
		return WoundModifier.NONE
	return WoundModifier.MINUS_ONE

# ── Codex: Orks (11e) defensive stratagems used in the opponent's Shooting
# phase (OrkCodexShootingReactive.gd). The handlers write ork11e_* flags on
# every component of the targeted (Attached) unit; these helpers are called
# from EVERY ranged resolver path (interactive hit/wound stages, the auto
# _resolve_assignment path, overwatch) — never from melee.

# HULKING BRUTES: flags.ork11e_hulking_brutes = "s_gt_t" (ranged attacks with
# S greater than the unit's T have -1 to wound) or "all" (+1CP upgrade: every
# ranged attack that targets the unit has -1 to wound).
static func ork11e_ranged_wound_penalty(target_unit: Dictionary, strength: int, toughness: int) -> bool:
	var mode := str(target_unit.get("flags", {}).get("ork11e_hulking_brutes", ""))
	if mode == "all":
		return true
	if mode == "s_gt_t" and strength > toughness:
		return true
	return false

# SPEEDIEST FREEKS: flags.ork11e_speediest_freeks — ranged attacks that target
# the unit fail on an unmodified hit roll of 1-3 (the same unmodified fail-band
# mechanism INDIRECT FIRE uses; the larger band wins).
static func ork11e_ranged_hit_fail_band(target_unit: Dictionary, band: int) -> int:
	if target_unit.get("flags", {}).get("ork11e_speediest_freeks", false):
		return maxi(band, 3)
	return band

# GROT SHIELDS: flags.ork11e_grot_shields = {gretchin_unit_id, attacker_unit_ids}
# on the shielded ORKS INFANTRY unit. Each time a hit roll of one of those
# enemy units' ranged attacks that target the shielded unit results in a hit,
# while a model of the Gretchin unit is on the battlefield, that attack's
# sequence ends (no wound roll, no [LETHAL HITS] auto-wound, no [SUSTAINED
# HITS] extra hits of that attack) and the Gretchin unit suffers 1 mortal
# wound. Torrent attacks make no hit roll, so they are never intercepted.
# Ruling: the Ork player sequences the simultaneous triggers, so critical hits
# are intercepted before normal hits. Called at the start of the wound stage,
# so a hit die changed by a Command Re-roll is judged on its final result.
# Returns the adjusted hit counts plus the Gretchin's mortal-wound diffs (the
# caller merges them into the action's changes — nothing is applied here).
static func ork11e_grot_shields_intercept(actor_unit_id: String, target_unit: Dictionary, critical_hits: int, regular_hits: int, sustained_bonus_hits: int, sustained_data: Dictionary, is_torrent: bool, board: Dictionary, rng) -> Dictionary:
	var out := {"active": false, "intercepted": 0, "crit_intercepted": 0,
		"critical_hits": critical_hits, "regular_hits": regular_hits,
		"sustained_bonus_hits": sustained_bonus_hits, "diffs": [], "casualties": 0,
		"gretchin_unit_id": "", "log_text": ""}
	var gs_flag = target_unit.get("flags", {}).get("ork11e_grot_shields", null)
	if typeof(gs_flag) != TYPE_DICTIONARY or is_torrent:
		return out
	if not actor_unit_id in gs_flag.get("attacker_unit_ids", []):
		return out
	var gid := str(gs_flag.get("gretchin_unit_id", ""))
	var units: Dictionary = board.get("units", {})
	if gid == "" or not units.has(gid):
		return out
	out.gretchin_unit_id = gid
	out.active = true
	# Private copy of the Gretchin unit: the mortal wounds are simulated one
	# at a time so "a model of your GRETCHIN unit is on the battlefield" is
	# re-checked before every interception.
	var sim_units: Dictionary = units.duplicate(false)
	sim_units[gid] = units[gid].duplicate(true)
	var sim_board: Dictionary = board.duplicate(false)
	sim_board["units"] = sim_units
	var crit_left := critical_hits
	var reg_left := regular_hits
	while crit_left + reg_left > 0:
		if count_alive_models(sim_units[gid]) <= 0:
			break
		if crit_left > 0:
			crit_left -= 1
			out.crit_intercepted += 1
		else:
			reg_left -= 1
		out.intercepted += 1
		var mw = apply_mortal_wounds(gid, 1, sim_board, rng)
		for d in mw.get("diffs", []):
			out.diffs.append(d)
			_apply_diff_to_board(sim_board, d)
		out.casualties += int(mw.get("casualties", 0))
	out.critical_hits = crit_left
	out.regular_hits = reg_left
	# The intercepted critical hits' [SUSTAINED HITS] extra hits belong to the
	# attacks whose sequence ended.
	if out.crit_intercepted > 0 and sustained_bonus_hits > 0 and critical_hits > 0:
		if not bool(sustained_data.get("is_dice", false)):
			out.sustained_bonus_hits = maxi(0, sustained_bonus_hits - out.crit_intercepted * int(sustained_data.get("value", 0)))
		else:
			out.sustained_bonus_hits = int(floor(float(sustained_bonus_hits) * float(crit_left) / float(critical_hits)))
	var g_name = units[gid].get("meta", {}).get("display_name", units[gid].get("meta", {}).get("name", gid))
	if out.intercepted > 0:
		out.log_text = "GROT SHIELDS: %d hit(s) intercepted by %s — %d mortal wound(s), %d model(s) slain" % [
			out.intercepted, g_name, out.intercepted, out.casualties]
	else:
		out.log_text = "GROT SHIELDS: %s has no model left on the battlefield — hits proceed" % g_name
	print("RulesEngine: %s (attacker %s; %d crit / %d normal hit(s) left)" % [out.log_text, actor_unit_id, crit_left, reg_left])
	return out

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
	return UnitAbilities.unit_has(unit, "stealth") \
		or (GameConstants.edition >= 11 and ork11e_enh().grants_stealth(unit)) \
		or SMAbilitiesC11eScript.grants_stealth(unit)  # WP-O5 Kill Kommanda (while attached); WP-M4c Trifold Path of Shadow

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
		if anti.has("negated"):
			# [ANTI-non-X/Y]: the target (Attached unit union included) has none of them.
			var has_any := false
			for nk in anti.negated:
				if unit_has_keyword(target_unit, str(nk)):
					has_any = true
				for kw in union_keywords:
					if str(kw).to_upper() == str(nk):
						has_any = true
			if not has_any:
				lowest_threshold = min(lowest_threshold, anti.threshold)
			continue
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
	var threshold := 6  # Default: only 6s are critical hits
	var conversion_threshold = get_conversion_threshold(weapon_id, board)
	if conversion_threshold > 0:
		# Check distance: Conversion only applies at 12"+ from target
		# Use the closest attacking model's distance to the closest target model
		var min_distance_inches = _get_min_distance_to_target(actor_unit, target_unit, model_ids, board)
		if min_distance_inches >= 12.0:
			print("RulesEngine: CONVERSION %d+ active — closest model is %.1f\" from target (>= 12\")" % [conversion_threshold, min_distance_inches])
			threshold = conversion_threshold
		else:
			print("RulesEngine: CONVERSION %d+ NOT active — closest model is %.1f\" from target (< 12\")" % [conversion_threshold, min_distance_inches])
	# BLITZA FIRE (Kult of Speed): ranged crits on 5+ vs targets within 9"
	if threshold > 5 and actor_unit.get("flags", {}).get("effect_blitza_fire", false) \
			and is_target_within_range_inches(actor_unit, target_unit, 9.0):
		threshold = 5
		print("RulesEngine: BLITZA FIRE — ranged critical hits on 5+ (target within 9\")")
	return threshold

# Get the minimum distance (in inches) from any attacking model to the closest target model
static func _get_min_distance_to_target(actor_unit: Dictionary, target_unit: Dictionary, model_ids: Array, board: Dictionary = {}) -> float:
	var min_distance = INF

	for model_id in model_ids:
		# ATTACHED CHARACTERS: composite bearers resolved through the board. When
		# EVERY bearer was a character's model this returned INF, and the caller
		# (CONVERSION X+, "12\" or more from the target") read INF >= 12.0 as
		# true — handing out a critical-hit bonus regardless of real distance.
		var model = resolve_bearer_model(actor_unit, model_id, board)
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
## Alive models of the whole Attached unit (bodyguard + attached CHARACTERs —
## 19.01: one unit) that `unit_id` belongs to; a plain unit counts itself.
static func attached_unit_alive_model_count(unit_id: String, board: Dictionary) -> int:
	var head := str(attached_unit_target_id(unit_id, board))
	var units: Dictionary = board.get("units", {})
	var n := 0
	for gid in attached_unit_component_ids(head, board):
		n += count_alive_models(units.get(str(gid), {}))
	return n

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

# 11e [CLEAVE X] (24.06): parse the X value from a melee weapon (0 if absent).
static func get_cleave_value(weapon_id: String, board: Dictionary = {}) -> int:
	var profile = get_weapon_profile(weapon_id, board)
	if profile.is_empty():
		return 0
	var sources = [str(profile.get("special_rules", ""))]
	for kw in profile.get("keywords", []):
		sources.append(str(kw))
	var rx = RegEx.new()
	rx.compile("(?i)cleave\\s+(\\d+)")
	for s in sources:
		var m = rx.search(s)
		if m:
			return int(m.get_string(1))
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
	if not has_blast and EffectPrimitivesData.has_effect_grant_blast(actor_unit):
		# SYNCHRONISED INFERNO (Silent Hunters): ranged weapons gain BLAST vs any target
		var wp_gb = get_weapon_profile(weapon_id, board)
		if str(wp_gb.get("type", "")).to_lower() == "ranged" or wp_gb.get("range", 0) > 0:
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

# True when the unit's flags grant [HAZARDOUS] to this weapon: the ranged-only
# effect_grant_hazardous to a ranged weapon, effect_grant_hazardous_melee to a
# melee weapon.
static func _weapon_hazardous_by_grant(actor_unit_id: String, weapon_id: String, board: Dictionary) -> bool:
	var flags = board.get("units", {}).get(actor_unit_id, {}).get("flags", {})
	var is_melee := str(get_weapon_profile(weapon_id, board).get("type", "Ranged")).to_lower() == "melee"
	if is_melee:
		return bool(flags.get("effect_grant_hazardous_melee", false))
	return bool(flags.get(EffectPrimitivesData.FLAG_GRANT_HAZARDOUS, false))

## Public: is `weapon_id` [HAZARDOUS] when `actor_unit_id` fires it — natively
## or by a granted [HAZARDOUS] (e.g. VINDICTIVE ARTILLERISTS' overcharged
## option). The shooting forecast reads this (r3:F8).
static func weapon_is_hazardous_for(actor_unit_id: String, weapon_id: String, board: Dictionary) -> bool:
	return is_hazardous_weapon(weapon_id, board) or _weapon_hazardous_by_grant(actor_unit_id, weapon_id, board)

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

	# A weapon can also be [HAZARDOUS] by a granted ability (unit flag
	# effect_grant_hazardous for ranged weapons, effect_grant_hazardous_melee
	# for melee — e.g. VINDICTIVE ARTILLERISTS). The callers already count such
	# weapons; without this the check silently rolled nothing for them.
	if not is_hazardous_weapon(weapon_id, board) and not _weapon_hazardous_by_grant(actor_unit_id, weapon_id, board):
		return result

	# Roll D6 for each model that fired this Hazardous weapon
	var rolls = rng.roll_d6(models_that_fired)
	result.rolls = rolls

	# 11e 06.03/24.15: a hazard roll of 1-2 fails. 10e/Balance-Dataslate: only a 1.
	var hazard_fail_threshold: int = 2 if GameConstants.edition >= 11 else 1
	# WP-M4b RITES OF THERMAL APPEASEMENT (Hellblaster Squad): +1 to hazard rolls for its plasma weapons.
	var haz_mod: int = int(_sm11e_abilities_b().hazard_roll_modifier(board.get("units", {}).get(actor_unit_id, {}), str(get_weapon_profile(weapon_id, board).get("name", ""))))
	if haz_mod != 0:
		print("RulesEngine: [HAZARDOUS] Rites of Thermal Appeasement — %+d to hazard rolls" % haz_mod)
	var ones_rolled = 0
	for roll in rolls:
		if roll + haz_mod <= hazard_fail_threshold:
			ones_rolled += 1
	result.ones_rolled = ones_rolled

	var weapon_profile = get_weapon_profile(weapon_id, board)
	var weapon_name = weapon_profile.get("name", weapon_id)
	# LV2-G1: name the unit and the fail band in the dice blocks, so the Game Log
	# / Dice History can say WHO rolled and what failed ("1-2" at 11e).
	var haz_unit: Dictionary = board.get("units", {}).get(actor_unit_id, {})
	var haz_unit_name := str(haz_unit.get("meta", {}).get("display_name", haz_unit.get("meta", {}).get("name", actor_unit_id)))
	var fail_band := "1" if hazard_fail_threshold <= 1 else "1-%d" % hazard_fail_threshold
	# 10e wording ("N ones") is kept; at 11e a 2 fails too, so "ones" was wrong.
	var fail_count_text := ("%d ones" % ones_rolled) if hazard_fail_threshold <= 1 else ("%d failed (%s)" % [ones_rolled, fail_band])

	print("RulesEngine: [HAZARDOUS] %s — rolled %s, failed (%s): %d" % [weapon_name, str(rolls), fail_band, ones_rolled])

	# Build dice log entry
	result.dice.append({
		"context": "hazardous_check",
		"weapon_id": weapon_id,
		"weapon_name": weapon_name,
		"unit_id": actor_unit_id,
		"unit_name": haz_unit_name,
		"owner": int(haz_unit.get("owner", 0)),
		"rolls": rolls,
		"ones_rolled": ones_rolled,
		"fail_threshold": hazard_fail_threshold,
		"models_checked": models_that_fired,
		"triggered": ones_rolled > 0,
		"message": "Hazardous check for %s: rolled %s — %s" % [weapon_name, str(rolls), fail_count_text]
	})

	if ones_rolled == 0:
		result.log_text = "Hazardous check: %s safe (%s)" % [weapon_name, str(rolls)]
		result["game_log_text"] = hazard_game_log_line(result.dice)
		print("RulesEngine: [HAZARDOUS] No failed hazard roll — safe")
		return result

	result.hazardous_triggered = true

	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})
	var models = actor_unit.get("models", [])
	# 11e 06.03: 1 mortal wound per failed hazard roll (3 if every model in the
	# unit is MONSTER/VEHICLE). 10e/Balance-Dataslate: always 3 per 1 rolled.
	var mw_per_fail: int = 3
	if GameConstants.edition >= 11:
		mw_per_fail = 3 if is_monster_or_vehicle(actor_unit) else 1
	var total_mw = mw_per_fail * ones_rolled

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
		# Mortal wounds: + the mortal-wound-only FNP (Aegis of the Emperor, WP-C3).
		var fnp_value = get_model_fnp_vs(actor_unit, target_model, false, true)
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
		result.log_text = "HAZARDOUS! %s: %s → %d mortal wounds to %s (%d wounds applied)" % [
			weapon_name, fail_count_text, total_mw, haz_display, damage_to_apply
		]

		result.dice.append({
			"context": "hazardous_damage",
			"damage_type": "mortal_wounds",
			"unit_id": actor_unit_id,
			"unit_name": haz_unit_name,
			"weapon_name": weapon_name,
			"model_label": haz_display,
			"mortal_wounds": total_mw,
			"wounds_applied": damage_to_apply,
			"casualties": casualties,
			"fnp_rolls": fnp_rolls_arr,
			"target_model_idx": target_model_idx,
			"message": "Hazardous: %d mortal wounds to %s" % [total_mw, actor_unit.get("meta", {}).get("name", actor_unit_id)]
		})
	else:
		# No alive models at all
		result.log_text = "HAZARDOUS! %s: %s → no alive models to allocate to" % [weapon_name, fail_count_text]
		print("RulesEngine: [HAZARDOUS] No alive models to allocate mortal wounds to")

	result["game_log_text"] = hazard_game_log_line(result.dice)
	print("RulesEngine: [HAZARDOUS] Result: %s" % result.log_text)
	return result

## LV2-G1: the player-facing Game Log line for ONE hazard check — its
## hazardous_check block, optionally followed by its hazardous_damage block
## (the dice resolve_hazardous_check returns), e.g.
##   "Hazardous: Mek Gunz (Smasha Gun) rolled 2 — failed (1-2): 3 mortal wounds"
##   "Hazardous: Mek Gunz (Kustom Mega-kannon) rolled 5 — passed (fails on 1-2)"
## Every caller that logs a hazard roll (shooting, overwatch, melee) uses it,
## so native and granted [HAZARDOUS] read the same.
static func hazard_game_log_line(haz_dice: Array) -> String:
	var check: Dictionary = {}
	var damage: Dictionary = {}
	for d in haz_dice:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var ctx := str(d.get("context", ""))
		if ctx == "hazardous_check" and check.is_empty():
			check = d
		elif ctx == "hazardous_damage" and not check.is_empty() and damage.is_empty():
			damage = d
	if check.is_empty():
		return ""
	var thr := int(check.get("fail_threshold", 1))
	var band := "1" if thr <= 1 else "1-%d" % thr
	var rolls: Array = check.get("rolls", [])
	var rolled := ", ".join(PackedStringArray(rolls.map(func(r): return str(r))))
	var unit_name := str(check.get("unit_name", ""))
	var weapon := str(check.get("weapon_name", check.get("weapon_id", "")))
	var who := ("%s (%s)" % [unit_name, weapon]) if unit_name != "" else weapon
	var failed := int(check.get("ones_rolled", 0))
	if failed <= 0:
		return "Hazardous: %s rolled %s — passed (fails on %s)" % [who, rolled, band]
	var line := "Hazardous: %s rolled %s — %s (%s)" % [who, rolled, "failed" if failed == 1 else "%d failed" % failed, band]
	if damage.is_empty():
		return line + ": no model left to take the mortal wounds"
	var mw := int(damage.get("mortal_wounds", 0))
	var applied := int(damage.get("wounds_applied", mw))
	line += ": %d mortal wound%s" % [mw, "" if mw == 1 else "s"]
	if applied != mw:
		line += " (%d wound%s lost)" % [applied, "" if applied == 1 else "s"]
	if int(damage.get("casualties", 0)) > 0:
		line += " — %s destroyed" % str(damage.get("model_label", "1 model"))
	return line

# Balance Dataslate v3.3 Hazardous allocation priority:
#   (1) wounded model with Hazardous weapon
#   (2) non-Character model with Hazardous weapon
#   (3) Character model with Hazardous weapon
static func _find_hazardous_allocation_target(models: Array, hazardous_weapon_id: String, board: Dictionary) -> int:
	# Build list of alive model indices with whether they have a Hazardous weapon and are CHARACTER
	var candidates = []
	for i in range(models.size()):
		var model = models[i]
		# Destroyed-but-not-removed models (05.04.05) take no further damage.
		if not model_can_be_allocated(model):
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
	board: Dictionary,
	for_rapid_fire: bool = false
) -> int:
	var weapon_profile = get_weapon_profile(weapon_id, board)
	var weapon_range = weapon_profile.get("range", 24) + ork11e_det_range_bonus(actor_unit, weapon_profile)  # Codex: Orks (11e) Dakka! Dakka! Dakka! +3" Range while riled up (WP-O34)
	var half_range_inches = weapon_range if (for_rapid_fire and load("res://scripts/codex/space_marines/SMDetachmentsB.gd").full_range_rapid_fire(actor_unit)) else weapon_range / 2.0  # WP-M2b Codex Fire-patterns (RAPID FIRE only, never MELTA)

	var models_in_half_range = 0

	for model_id in model_ids:
		# ATTACHED CHARACTERS: composite bearers live in another unit dict.
		# Skipping them lost MELTA's half-range damage bonus for a character's gun.
		var model = resolve_bearer_model(actor_unit, model_id, board)
		if not model or not model.get("alive", true):
			continue

		# Check distance to closest target model (edge-to-edge) — every model
		# of the target unit, including an Attached unit's leaders (19.03).
		var closest_distance_inches = INF
		var hr_target_id := str(target_unit.get("id", ""))
		var hr_target_models: Array = attached_unit_models(hr_target_id, board) \
			if hr_target_id != "" and board.get("units", {}).has(hr_target_id) else target_unit.get("models", [])
		for target_model in hr_target_models:
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

	var weapon_range_inches = float(weapon_profile.get("range", 12)) + ork11e_det_range_bonus(actor_unit, weapon_profile)  # Codex: Orks (11e) Dakka! Dakka! Dakka! +3" Range while riled up (WP-O34)
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

		# Composite "<char_unit_id>:<model_id>" bearers (attached characters) live
		# in a DIFFERENT unit dict — resolve through the board, not actor_unit.
		var actor_model = resolve_bearer_model(actor_unit, model_id, board)
		if actor_model.is_empty():
			# Still silent (no reason recorded): _filter_eligible_model_ids keys
			# its "unparseable weapon-carrier data, trust the caller" fallback on
			# eligible AND reasons both being empty, and headless fixtures without
			# meta.weapons depend on that fallback to fire at all.
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
	
	# GRAB IT (Codex: Orks 11e): hard charge lock until the end of the turn.
	if flags.get("ork11e_grab_it_no_charge", false):
		return false
	# WP-C7: Codex: Adeptus Custodes (11e) MOBILE HUNTER — the same hard lock (CustodesAbilities.gd).
	if CustodesAbilities11eScript.blocks_charge(unit):
		return false
	# WP-M4c PURGATION RUN (Land Speeder): not eligible to declare a charge until the end of the turn.
	if SMAbilitiesC11eScript.blocks_charge(unit):
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
				# 11e: from the whole Attached unit (19.01) — see charge_unit_models
				"distance": _charge_min_distance_to_target_rules(unit_id, target_id, board)
			}
	
	return eligible

# Why `target_unit_id` is NOT in charge_targets_within_12(unit_id)'s result — a
# player-facing sentence for the click-to-target path, which lets the player
# click any enemy on the board (not just the ones listed in ELIGIBLE TARGETS).
# Deliberately mirrors charge_targets_within_12's filters in the same order, so
# the explanation can never disagree with the list it explains. Returns "" when
# the target IS chargeable.
static func charge_target_ineligibility_reason(unit_id: String, target_unit_id: String, board: Dictionary) -> String:
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	var target_unit = units.get(target_unit_id, {})

	if unit.is_empty():
		return "No charging unit selected"
	if target_unit.is_empty():
		return "Invalid charge target"

	var target_name = target_unit.get("meta", {}).get("display_name", target_unit.get("meta", {}).get("name", target_unit_id))

	if target_unit.get("owner", 0) == unit.get("owner", 0):
		return "Cannot charge a friendly unit"

	var has_alive_models = false
	for model in target_unit.get("models", []):
		if model.get("alive", true):
			has_alive_models = true
			break
	if not has_alive_models:
		return "%s is destroyed" % target_name

	var charger_has_fly = "FLY" in unit.get("meta", {}).get("keywords", [])
	if "AIRCRAFT" in target_unit.get("meta", {}).get("keywords", []) and not charger_has_fly:
		return "%s is an AIRCRAFT — only units with FLY can charge it" % target_name

	if not _is_target_within_charge_range_rules(unit_id, target_unit_id, board):
		var dist = _charge_min_distance_to_target_rules(unit_id, target_unit_id, board)
		if dist == INF:
			return "%s is not on the battlefield" % target_name
		return "%s is %.1f\" away — charge targets must be within 12\"" % [target_name, dist]

	return ""

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
	var base_to_base_validation = validate_base_to_base_possible_rules(unit_id, paths, targets, board, roll)
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

# The models a charge measures "your unit" from. 11e: every model of the
# Attached unit headed by unit_id (its own models plus its attached
# CHARACTER(s)') — 19.01 "An attached unit is a single unit for all rules
# purposes", so 11.04 BEFORE MOVING's "within 12" of your unit and within the
# maximum distance of your unit" and AFTER MOVING's "Your unit must be engaged
# with all of the charge targets" are satisfied by the leader's models too (the
# charge move already carries them as <char_unit>:<model> paths). Same model set
# as ChargeMove11e._unit_group_models. 10e: the unit's own models (unchanged).
static func charge_unit_models(unit_id: String, board: Dictionary) -> Array:
	var units = board.get("units", {})
	if GameConstants.edition < 11:
		return units.get(unit_id, {}).get("models", [])
	var out: Array = []
	for gid in attached_unit_component_ids(unit_id, board):
		out.append_array(units.get(str(gid), {}).get("models", []))
	return out

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

	# 11e: from every model of the Attached unit (19.01) — see charge_unit_models
	for model in charge_unit_models(unit_id, board):
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

# Charge-only minimum edge-to-edge distance (inches) from the charging unit
# to target_id, measured from charge_unit_models — every model of the Attached
# unit at 11e (19.01), the unit's own models at 10e. The ELIGIBLE TARGETS row
# distance and the ineligibility message use it, so they agree with
# _is_target_within_charge_range_rules. Deliberately NOT folded into
# _get_min_distance_to_target_rules, which shooting (Lone Operative, Psychic
# Veil, closest target) also reads.
static func _charge_min_distance_to_target_rules(unit_id: String, target_id: String, board: Dictionary) -> float:
	var target = board.get("units", {}).get(target_id, {})
	var min_distance = INF
	for model in charge_unit_models(unit_id, board):
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
			min_distance = min(min_distance, Measurement.model_to_model_distance_inches(model, target_model))
	return min_distance

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
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})

	# Build model dicts with final positions for shape-aware distance
	var final_models = []
	var moved_ids := {}
	for model_id in per_model_paths:
		var path = per_model_paths[model_id]
		if path is Array and path.size() > 0:
			moved_ids[model_id] = true
			var model = _get_model_in_unit_rules(unit, model_id)
			var model_at_final = model.duplicate()
			model_at_final["position"] = Vector2(path[-1][0], path[-1][1])
			final_models.append(model_at_final)

	# Coherency is a whole-unit condition: include the UNMOVED alive models at their
	# current positions so a single dragged model cannot legally break away from the
	# rest of its unit (mirrors ChargePhase._validate_unit_coherency_for_charge).
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		if model.get("position") == null:
			continue
		var mid = model.get("id", "")
		if moved_ids.has(mid):
			continue
		final_models.append(model)

	if final_models.size() < 2:
		return {"valid": true, "errors": []}  # Single model or no movement

	# Delegate to the edition-aware single source of truth (11e 03.03: within 2" of a
	# mate AND within 9" of every other model in the unit).
	var result = AttackSequence.check_unit_coherency({"models": final_models})
	if result.get("coherent", true):
		return {"valid": true, "errors": []}

	var offenders = result.get("offenders", [])
	return {"valid": false, "errors": ["Unit coherency broken: %d model(s) out of coherency — every model must be within 2\" of a mate AND within 9\" of every other model in the unit" % offenders.size()]}

# Charge close-distance enforcement (11e Charge Move 11.04, "WHILE MOVING").
# Per-model rule: every charging model that CAN end its move within 1" of a
# charge target — while still satisfying coherency, overlap, non-target ER and
# all-target coverage — MUST do so. Base-to-base contact (0") over-satisfies the
# 1" band and is what the UI snap assist places models at. Function name kept for
# call-site stability; it now enforces "within 1 inch", not literal base contact.
static func validate_base_to_base_possible_rules(unit_id: String, per_model_paths: Dictionary, target_ids: Array, board: Dictionary, rolled_distance: int = 0) -> Dictionary:
	var errors = []
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	var unit_owner = unit.get("owner", 0)

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

	# 11.04 WHILE MOVING (11e): each model that CAN end ENGAGED (within Engagement
	# Range) with one or more charge targets MUST do so — a PER-MODEL obligation.
	# The old 10e reading was wrongly satisfied by a SINGLE model reaching base
	# contact; here every model is judged. Base-to-base (0") over-satisfies the band.
	if rolled_distance <= 0:
		return {"valid": true, "errors": []}

	# Distance band a model must close into if it can. 11e: a charge ends with the
	# unit ENGAGED — Engagement Range is 2" horizontally (03.04). 10e used 1". This
	# reads from GameConstants so the edition switch applies; a hardcoded 1" here
	# was a 10e engagement-range leak that over-constrained 11e charges (a model
	# legitimately ending engaged at ~1.1"-2.0" was wrongly told to close to 1").
	var close_inches: float = GameConstants.engagement_range_inches()
	var band_tol: float = 0.05  # fp / snap-noise slack on the band

	for model_id in final_models:
		# A model already within 1" of any target satisfies its own obligation.
		var already_close := false
		for target_entry in target_models:
			if Measurement.model_to_model_distance_inches(final_models[model_id], target_entry.model) <= close_inches + band_tol:
				already_close = true
				break
		if already_close:
			continue

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

			# Inches the model must travel to close into the 1" band (edge-to-edge).
			var distance_to_close = Measurement.model_to_model_distance_inches(model_at_start, target_model) - close_inches
			if distance_to_close > rolled_distance:
				continue  # cannot reach within 1" of this target with the roll
			distance_to_close = max(0.0, distance_to_close)

			# Candidate within-1" endpoint: move centre toward target to close the gap.
			var direction = (target_pos - start_pos)
			if direction.length() < 0.001:
				continue
			direction = direction.normalized()
			var move_px = Measurement.inches_to_px(distance_to_close)
			var b2b_pos = start_pos + direction * move_px

			var b2b_model = model.duplicate()
			b2b_model["position"] = b2b_pos

			# Constraint 0a: the candidate path must also afford any terrain
			# vertical penalty — the distance validator charges it, so an
			# endpoint only reachable by ignoring the climb cannot be demanded.
			var unit_kw = unit.get("meta", {}).get("keywords", [])
			var tm_penalty := 0.0
			var tmgr_b2b = Engine.get_main_loop().root.get_node_or_null("TerrainManager") if Engine.get_main_loop() is SceneTree else null
			if tmgr_b2b and tmgr_b2b.has_method("calculate_charge_terrain_penalty"):
				tm_penalty = tmgr_b2b.calculate_charge_terrain_penalty(start_pos, b2b_pos, "FLY" in unit_kw, unit_kw)
			if distance_to_close + tm_penalty > rolled_distance:
				continue

			# Constraint 0b: an endpoint overlapping a wall is never legal
			# (_validate_no_wall_overlaps rejects it), so it cannot be used to
			# demand the close-distance obligation either.
			if Measurement.model_overlaps_any_wall(b2b_model):
				continue

			# Straight-line-to-centre is approximate for non-circular bases; only
			# flag when the candidate really does land within the 1" band. The
			# acceptance tolerance MUST match the already-close band (band_tol)
			# above: with a looser slack (this used 0.25) an oval-target
			# candidate could land at e.g. 1.15" — accepted here, yet a model
			# placed exactly there would still not count as "close", so the
			# obligation demanded an endpoint that could not satisfy it and
			# every legal move was rejected.
			if Measurement.model_to_model_distance_inches(b2b_model, target_model) > close_inches + band_tol:
				continue

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

			# A legal within-1" endpoint existed but was not taken.
			errors.append(
				"Model %s could end within 1\" of a charge target and must do so (11.04)" % model_id
			)
			print("RulesEngine: charge close-distance enforcement - %s" % errors[-1])
			break  # this model is flagged; evaluate the next model

	return {"valid": errors.is_empty(), "errors": errors}

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

	# Generic NdN six-sided dice (e.g. "3D6" for Supa-burny Fuel's killa jet burna).
	# Generalizes the 2D6 case above; excludes bare "D6" (begins with a digit).
	if upper.ends_with("D6") and not upper.begins_with("D"):
		var n_part = upper.substr(0, upper.length() - 2)
		if n_part.is_valid_int() and int(n_part) > 0:
			var n = int(n_part)
			var ndn_rolls = rng.roll_d6(n)
			var ndn_total = 0
			for r in ndn_rolls:
				ndn_total += r
			return {"value": ndn_total, "rolled": true, "notation": upper, "roll": ndn_total}

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

		# 19.02: an attached CHARACTER is part of ONE Attached unit and is
		# never a target on its own — its bodyguard is the entry that stands
		# for the whole Attached unit (and is reached below with the leader's
		# models folded in, so leader-only engagement still offers it).
		if is_attached_character(target_id, board):
			continue

		var target_keywords = target_unit.get("meta", {}).get("keywords", [])

		# T4-4: Aircraft can only fight against units that can Fly
		if unit_is_aircraft and "FLY" not in target_keywords:
			continue
		# T4-4: Non-FLY units cannot target Aircraft
		if "AIRCRAFT" in target_keywords and not unit_has_fly:
			continue

		# Alive-model and engagement checks run over the WHOLE Attached unit
		# (bodyguard + attached characters), not just the bodyguard's own
		# models — 19.03, the leader's model belongs to this unit.
		var target_group = {"models": attached_unit_models(target_id, board)}

		var target_alive = false
		for tm in target_group.models:
			if tm.get("alive", true):
				target_alive = true
				break
		if not target_alive:
			continue

		# Check engagement range
		if _are_units_in_engagement_range_rules(unit, target_group, board):
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
const BASE_CONTACT_TOLERANCE_INCHES: float = 0.1  # Tolerance for digital positioning (was 0.25 — too generous, see #base-contact-buffer-sizing)

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
					# BULLDOZER BRUTALITY (Green Tide): models within 3" of an
					# enemy model are eligible to fight this phase.
					if attacker_unit.get("flags", {}).get("effect_fight_range_3", false):
						effective_er = maxf(effective_er, 3.0)
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
		var swing_back_mode: String = "always"
		if not target_unit_id_pre.is_empty():
			var pre_target_unit = units.get(target_unit_id_pre, {})
			var pre_flags = pre_target_unit.get("flags", {})
			if pre_flags.get(EffectPrimitivesData.FLAG_SWING_BACK_BEFORE_REMOVE, false) \
					or pre_flags.get(EffectPrimitivesData.FLAG_DEFIANT_TO_THE_LAST, false) \
					or pre_flags.get("effect_too_arrogant_to_die", false):
				for m in pre_target_unit.get("models", []):
					swing_back_pre_alive.append(m.get("alive", true))
				if pre_flags.get(EffectPrimitivesData.FLAG_DEFIANT_TO_THE_LAST, false):
					swing_back_mode = "defiant"
				elif pre_flags.get("effect_too_arrogant_to_die", false):
					swing_back_mode = "too_arrogant"

		var assignment_result = _resolve_melee_assignment(assignment, actor_unit_id, board, rng_service)
		result.diffs.append_array(assignment_result.diffs)
		result.dice.append_array(assignment_result.dice)
		if assignment_result.log_text:
			result.log_text += assignment_result.log_text + "\n"

		# Issue #391 ORKS IS NEVER BEATEN / DEFIANT TO THE LAST: now that the
		# original assignment has resolved (and may have killed models), trigger
		# the deferred swing-back attack from the dying-but-not-yet-removed models.
		if not swing_back_pre_alive.is_empty():
			var sb_diffs_dice = _resolve_swing_back_before_remove(target_unit_id_pre, actor_unit_id, swing_back_pre_alive, board, rng_service, swing_back_mode)
			result.diffs.append_array(sb_diffs_dice.get("diffs", []))
			result.dice.append_array(sb_diffs_dice.get("dice", []))
			if sb_diffs_dice.get("log_text", "") != "":
				result.log_text += sb_diffs_dice["log_text"] + "\n"

		# HAZARDOUS (T2-3): After weapon resolves, check for Hazardous self-damage (melee)
		# KLANKIN' KLAWS (Dread Mob, pushed) grants melee HAZARDOUS via the
		# melee-scoped effect flag.
		var weapon_id = assignment.get("weapon", "")
		if is_hazardous_weapon(weapon_id, board) \
				or board.get("units", {}).get(actor_unit_id, {}).get("flags", {}).get("effect_grant_hazardous_melee", false):
			var models_that_fought = assignment.get("models", []).size()
			var hazardous_result = resolve_hazardous_check(actor_unit_id, weapon_id, models_that_fought, board, rng_service)
			if hazardous_result.hazardous_triggered:
				result.diffs.append_array(hazardous_result.diffs)
			result.dice.append_array(hazardous_result.dice)
			# LV2-G1: the player-facing hazard line (this log_text can reach the
			# Game Log as the action's text) — same wording on every path.
			var haz_line := str(hazardous_result.get("game_log_text", hazardous_result.log_text))
			if haz_line != "":
				result.log_text += haz_line + "\n"

	return result


# Issue #391 ORKS IS NEVER BEATEN: drive a swing-back attack from models that
# died this assignment. The dying models temporarily revive so the eligibility
# / engagement checks in `_resolve_melee_assignment` accept them, then we
# re-apply alive=false. Models that already fought this phase do NOT swing back
# (per Wahapedia: "if that model has not fought this phase").
static func _resolve_swing_back_before_remove(target_unit_id: String, original_attacker_id: String, pre_alive: Array, board: Dictionary, rng: RNGService, swing_back_mode = "always") -> Dictionary:
	# swing_back_mode: "always" (ORKS IS NEVER BEATEN), "defiant" (DEFIANT TO
	# THE LAST: D6 +2 CHARACTER, 4+) or "too_arrogant" (TOO ARROGANT TO DIE,
	# Bully Boyz: D6 +2 while a Waaagh! is active for the unit, 5+). Legacy
	# bool callers map true -> "defiant".
	if swing_back_mode is bool:
		swing_back_mode = "defiant" if swing_back_mode else "always"
	var is_defiant: bool = swing_back_mode == "defiant"
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
			elif swing_back_mode == "too_arrogant":
				# TOO ARROGANT TO DIE (Bully Boyz): roll D6, +2 while a
				# Waaagh! is active for the unit, need 5+.
				var ta_roll = rng.randi_range(1, 6)
				var ta_mod = 2 if FactionAbilityManager.is_waaagh_active_for_unit(defender) else 0
				var ta_total = ta_roll + ta_mod
				sb_result.dice.append({"type": "too_arrogant_to_die", "roll": ta_roll, "modifier": ta_mod, "total": ta_total, "passed": ta_total >= 5})
				if ta_total >= 5:
					dying_models.append(idx)
					print("RulesEngine: TOO ARROGANT TO DIE — model %d rolled %d+%d=%d (5+ needed), PASSES — will swing back" % [idx, ta_roll, ta_mod, ta_total])
				else:
					print("RulesEngine: TOO ARROGANT TO DIE — model %d rolled %d+%d=%d (5+ needed), FAILS — removed normally" % [idx, ta_roll, ta_mod, ta_total])
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
				result.save_data_list.append(save_data)
				result.has_wounds = true
				print("RulesEngine: P0-58 — Prepared melee save data: %d wounds for %s from %s" % [
					assignment_result.get("wounds_caused", 0),
					save_data.get("target_unit_name", ""),
					save_data.get("weapon_name", "")
				])

		# HAZARDOUS (T2-3): After weapon resolves, check for Hazardous self-damage (melee)
		# KLANKIN' KLAWS (Dread Mob, pushed) grants melee HAZARDOUS via the
		# melee-scoped effect flag.
		var weapon_id = assignment.get("weapon", "")
		if is_hazardous_weapon(weapon_id, board) \
				or board.get("units", {}).get(actor_unit_id, {}).get("flags", {}).get("effect_grant_hazardous_melee", false):
			var models_that_fought = assignment.get("models", []).size()
			var hazardous_result = resolve_hazardous_check(actor_unit_id, weapon_id, models_that_fought, board, rng_service)
			if hazardous_result.hazardous_triggered:
				result.diffs.append_array(hazardous_result.diffs)
			result.dice.append_array(hazardous_result.dice)
			# LV2-G1: the player-facing hazard line (this log_text can reach the
			# Game Log as the action's text) — same wording on every path.
			var haz_line := str(hazardous_result.get("game_log_text", hazardous_result.log_text))
			if haz_line != "":
				result.log_text += haz_line + "\n"

	return result

# ==========================================
# STAGED FIGHT (interactive Command Re-roll between hit and wound rolls)
# resolve_melee_hits() rolls ONLY the hit roll for a single melee assignment and
# returns a hit_context; the caller may pause (offer Command Re-roll on a hit die
# via reroll_hit_die), then call resolve_melee_wounds(hit_context) which rolls the
# wound roll and prepares save data. resolve_melee_saves_auto() runs the saving
# throw + damage tail for the auto-allocate path. Mirrors the staged shooting API
# (resolve_shoot_hits / resolve_shoot_wounds); the composed
# _resolve_melee_assignment stays behaviour-identical for the fast paths.
# ==========================================

static func resolve_melee_hits(action: Dictionary, board: Dictionary, rng_service: RNGService = null) -> Dictionary:
	if not rng_service:
		rng_service = make_rng()
	var result = {"success": true, "phase": "FIGHT", "dice": [], "log_text": "", "no_hits": true, "early_exit": false}
	var actor_unit_id = action.get("actor_unit_id", "")
	var assignments = action.get("payload", {}).get("assignments", [])
	if assignments.is_empty():
		result.success = false
		result.log_text = "No attack assignments provided"
		return result
	# Staged path resolves ONE assignment at a time.
	var assignment = assignments[0]
	var h = _resolve_melee_assignment_hits(assignment, actor_unit_id, board, rng_service)
	result.dice = h.get("dice", [])
	result.log_text = h.get("log_text", "")
	result.no_hits = h.get("no_hits", false)
	result.early_exit = h.get("early_exit", false)
	# Always propagate hit_context (present even on a miss) so the staged path can
	# Command Re-roll a missed die and continue to wounds if it becomes a hit.
	result["hit_context"] = h.get("hit_context", {})
	return result

# _interactive_saves: kept for API compatibility (it gated the pre-codex Hold
# Still and Say 'Aargh!' mortal wounds, which the Codex: Orks (11e) removed).
static func resolve_melee_wounds(hit_context: Dictionary, board: Dictionary, rng_service: RNGService = null, _interactive_saves: bool = true) -> Dictionary:
	if not rng_service:
		rng_service = make_rng()
	var w = _resolve_melee_assignment_wounds(hit_context, board, rng_service)
	var result = {
		"success": true,
		"phase": "FIGHT",
		"dice": w.get("dice", []),
		"log_text": w.get("log_text", ""),
		"no_wounds": w.get("no_wounds", false),
		"wounds_caused": w.get("wounds_caused", 0),
		"all_critical_wound_count": w.get("all_critical_wound_count", 0),
		"wound_context": w.get("wound_context", {}),
		"wound_result": w,
		"save_data_list": [],
	}
	if w.get("no_wounds", false):
		return result
	# Package interactive-save data exactly like resolve_melee_attacks_interactive
	# (dev wounds / precision), so the same overlay flow works.
	var packaged = {"log_text": ""}
	_build_melee_stop_before_saves(packaged, hit_context, w, rng_service)
	result["log_text"] = packaged.get("log_text", result["log_text"])
	var dw_data = {
		"has_devastating_wounds": hit_context.get("weapon_has_devastating_wounds", false),
		"critical_wounds": w.get("critical_wound_count", 0),
		"regular_wounds": w.get("regular_wound_count", 0)
	}
	var prec_data = {
		"has_precision": hit_context.get("weapon_has_precision", false),
		"precision_wounds": hit_context.get("critical_hits", 0) if hit_context.get("weapon_has_precision", false) else 0,
		"critical_hits": hit_context.get("critical_hits", 0)
	}
	var save_data = prepare_melee_save_resolution(
		w.get("wounds_caused", 0),
		hit_context.get("target_id", ""),
		hit_context.get("attacker_id", ""),
		hit_context.get("weapon_profile", {}),
		board,
		dw_data,
		prec_data
	)
	if save_data.get("success", false):
		result["save_data_list"] = [save_data]
	return result

# Staged fight auto-allocate tail: run the PHASE 6-7 saving throws + damage for
# one assignment whose hits/wounds were rolled via the staged calls above.
static func resolve_melee_saves_auto(hit_context: Dictionary, wound_result: Dictionary, board: Dictionary, rng_service: RNGService = null) -> Dictionary:
	if not rng_service:
		rng_service = make_rng()
	var s = _resolve_melee_assignment_saves(hit_context, wound_result, board, rng_service)
	return {
		"success": true,
		"phase": "FIGHT",
		"diffs": s.get("diffs", []),
		"dice": s.get("dice", []),
		"log_text": s.get("log_text", "")
	}

# Resolve a single melee assignment (models with weapon -> target)
# Full pipeline mirroring shooting: hit rolls (with critical tracking, Sustained Hits),
# wound rolls (with Lethal Hits, Devastating Wounds), save rolls (with invulnerable saves),
# FNP, and damage application.
# P0-58: When stop_before_saves=true, stops after wound rolls and returns save prep data
# for interactive wound allocation overlay (defender-controlled wound allocation).
#
# STAGED FIGHT: composed from the hits / wounds / saves thirds below so the staged
# fight path (resolve_melee_hits / resolve_melee_wounds / resolve_melee_saves_auto)
# can pause between the hit roll and the wound roll for Command Re-roll — exactly
# mirroring the ranged _resolve_assignment_until_wounds split. Behaviour and RNG
# order are identical to the original monolith.
static func _resolve_melee_assignment(assignment: Dictionary, actor_unit_id: String, board: Dictionary, rng: RNGService, stop_before_saves: bool = false) -> Dictionary:
	var h = _resolve_melee_assignment_hits(assignment, actor_unit_id, board, rng)
	var result = {
		"diffs": [],
		"dice": (h.get("dice", []) as Array).duplicate(),
		"log_text": h.get("log_text", "")
	}
	if h.get("early_exit", false) or h.get("no_hits", false):
		return result

	var hit_context = h.get("hit_context", {})
	var w = _resolve_melee_assignment_wounds(hit_context, board, rng)
	for wdb in w.get("dice", []):
		result.dice.append(wdb)
	if w.get("no_wounds", false):
		result.log_text = w.get("log_text", "")
		return result

	# P0-58: When stop_before_saves=true, return wound data for interactive save allocation
	if stop_before_saves:
		_build_melee_stop_before_saves(result, hit_context, w, rng)
		return result

	var s = _resolve_melee_assignment_saves(hit_context, w, board, rng)
	result.diffs.append_array(s.get("diffs", []))
	for sdb in s.get("dice", []):
		result.dice.append(sdb)
	result.log_text = s.get("log_text", "")
	return result

# P0-58 packaging shared by the interactive monolith path and the staged fight
# path: stamps the hit/wound tallies onto `result` and builds the awaiting-saves
# log line.
static func _build_melee_stop_before_saves(result: Dictionary, hit_context: Dictionary, w: Dictionary, _rng: RNGService) -> void:
	var is_torrent = hit_context.get("is_torrent", false)
	var hits = int(hit_context.get("hits", 0))
	var critical_hits = int(hit_context.get("critical_hits", 0))
	var sustained_bonus_hits = int(hit_context.get("sustained_bonus_hits", 0))
	var total_attacks = int(hit_context.get("total_attacks", 0))
	var total_hits_for_wounds = int(hit_context.get("total_hits_for_wounds", 0))
	var wounds_caused = int(w.get("wounds_caused", 0))
	var auto_wounds = int(w.get("auto_wounds", 0))
	result["wounds_caused"] = wounds_caused
	result["critical_wound_count"] = w.get("critical_wound_count", 0)
	result["regular_wound_count"] = w.get("regular_wound_count", 0)
	result["weapon_has_devastating_wounds"] = hit_context.get("weapon_has_devastating_wounds", false)
	result["weapon_has_precision"] = hit_context.get("weapon_has_precision", false)
	result["critical_hits"] = critical_hits
	result["weapon_profile"] = hit_context.get("weapon_profile", {})
	result["target_id"] = hit_context.get("target_id", "")
	result["attacker_id"] = hit_context.get("attacker_id", "")
	result["target_name"] = hit_context.get("target_name", "")
	result["attacker_name"] = hit_context.get("attacker_name", "")
	result["weapon_name"] = hit_context.get("weapon_name", "")
	result["stop_before_saves"] = true
	# Build log text for the hit/wound portion
	var hw_parts = []
	hw_parts.append("Melee: %s (%s) → %s" % [result["attacker_name"], result["weapon_name"], result["target_name"]])
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

# MA-LOADOUT (melee): which models actually swing `weapon_id` this activation.
#
# A model must be (a) eligible to fight, (b) inside any explicit model selection
# the caller made, and (c) EQUIPPED WITH THE WEAPON. (c) is new. The Fight phase
# used to skip it entirely, so every eligible model swung whatever weapon was
# picked for the unit: a 10-strong Boyz mob all swinging the Boss Nob's Power
# klaw, 30 attacks at S9 AP-2 D2 where the datasheet gives one model three.
# (Reported via the T6 tutorial, where that wiped the Custodian Guard the mob was
# supposed to leave standing 38% of the time.)
#
# `_get_model_weapon_ids` is the same per-model lookup the Shooting phase has
# always used: a resolved `melee_loadout` when the roster pinned one, else the
# datasheet's model_profiles menu, else — for a unit whose data cannot tell its
# models apart — the whole unit menu, which returns every model and leaves
# behaviour exactly as it was. So this only narrows where the data is actually
# there to narrow with.
#
# Same conservative posture on the way out: if NOTHING matches (a weapon no
# profile lists, e.g. an unequipped datasheet option), keep the old selection
# rather than silently deleting the unit's attacks.
static func _melee_weapon_swingers(unit: Dictionary, weapon_id: String, eligible_indices: Array, attacking_models: Array, unit_name: String = "", weapon_name: String = "") -> Array:
	# Resolve the per-model loadout first. _get_model_weapon_ids below answers
	# with the datasheet's option MENU until it does — every Boy "carrying" a
	# choppa AND a close combat weapon — so without this the narrowing keys off
	# what a model COULD take rather than what the roster bought it. Idempotent
	# and version-stamped, so this is a no-op after the first call per unit.
	_ensure_loadout_resolved(unit)

	var selected: Array = []
	for idx in eligible_indices:
		if attacking_models.is_empty() or str(idx) in attacking_models:
			selected.append(idx)

	var models = unit.get("models", [])
	var carriers: Array = []
	for idx in selected:
		if idx < 0 or idx >= models.size():
			continue
		if weapon_id in _get_model_weapon_ids(unit, models[idx], "Melee"):
			carriers.append(idx)

	if carriers.is_empty():
		if not selected.is_empty():
			print("RulesEngine: MA-LOADOUT melee — no model of %s is equipped with '%s'; keeping all %d eligible attacker(s) (loadout data cannot resolve it)" % [
				unit_name if unit_name != "" else unit.get("meta", {}).get("name", "unit"),
				weapon_name if weapon_name != "" else weapon_id,
				selected.size()])
		return selected

	if carriers.size() < selected.size():
		print("RulesEngine: MA-LOADOUT melee — %d of %d eligible %s model(s) carry '%s'; only they swing it" % [
			carriers.size(), selected.size(),
			unit_name if unit_name != "" else unit.get("meta", {}).get("name", "unit"),
			weapon_name if weapon_name != "" else weapon_id])
	return carriers


## Does ANY alive model of this unit hold this melee weapon?
##
## The companion to get_melee_weapon_swingers, which deliberately falls back to
## "every eligible model" when it cannot attribute a weapon — that keeps a unit
## swinging rather than silently zeroing its attacks, but it also means an empty
## carrier list never tells the UI that a weapon simply is not owned.
##
## This answers that question honestly at both ends. Before a unit's loadout
## resolves, models report the datasheet's option MENU, so this returns true and
## nothing is hidden. Once it resolves, a weapon the roster never bought is on no
## model and this returns false — which is what lets the attack panel stop
## offering an Ork mob the Power klaw it does not have.
static func unit_has_melee_weapon(unit: Dictionary, weapon_id: String) -> bool:
	_ensure_loadout_resolved(unit)
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		if weapon_id in _get_model_weapon_ids(unit, model, "Melee"):
			return true
	return false


## Public wrapper for the melee carrier lookup (ISS-020 lint: no leading
## underscore in cross-script calls). The attack dialog uses it to list the
## weapons a unit can really swing, and how many models swing each.
static func get_melee_weapon_swingers(unit: Dictionary, weapon_id: String, eligible_indices: Array, attacking_models: Array = []) -> Array:
	return _melee_weapon_swingers(unit, weapon_id, eligible_indices, attacking_models)


# Melee hits third: PHASES 1-4 of the original monolith (attack counting, combat
# stats, weapon abilities, hit rolls). Returns {dice, log_text, early_exit,
# no_hits, hit_context}. The hit_context carries per-die evals (reroll_hit_die
# support) and every stat the wounds/saves thirds need. WS is ALSO stored under
# the ranged "bs"/"bs_per_attack" keys so reroll_hit_die works unchanged.
static func _resolve_melee_assignment_hits(assignment: Dictionary, actor_unit_id: String, board: Dictionary, rng: RNGService) -> Dictionary:
	var result = {
		"diffs": [],
		"dice": [],
		"log_text": "",
		"early_exit": false,
		"no_hits": false
	}

	var attacker_id = assignment.get("attacker", "")
	var target_id = assignment.get("target", "")
	var weapon_id = assignment.get("weapon", "")
	var attacking_models = assignment.get("models", [])

	if weapon_id.is_empty():
		result.log_text = "No weapon specified for melee attack"
		result.early_exit = true
		return result

	# Get weapon profile (melee weapons use same format as ranged)
	var weapon_profile = get_weapon_profile(weapon_id, board)
	if weapon_profile.is_empty():
		result.log_text = "Weapon profile not found: " + weapon_id
		result.early_exit = true
		return result

	var units = board.get("units", {})
	var attacker_unit = units.get(attacker_id, {})
	var target_unit = units.get(target_id, {})

	if attacker_unit.is_empty() or target_unit.is_empty():
		result.log_text = "Attacker or target unit not found"
		result.early_exit = true
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
	# Audit #14 (11e): the 10e Balance-Dataslate restriction is GONE — at
	# edition >= 11 [EXTRA ATTACKS] weapons take attack modifiers normally,
	# so the suppression flag only arms at 10e.
	var is_extra_attacks_weapon = has_extra_attacks(weapon_id, board) and GameConstants.edition < 11
	if is_extra_attacks_weapon:
		print("RulesEngine: Weapon '%s' has Extra Attacks — attack count cannot be modified by generic rules (Balance Dataslate, 10e)" % weapon_name)

	# WAAAGH! CHECK: Detect if Waaagh! is active for the attacker
	var waaagh_active = FactionAbilityManager.is_waaagh_active_for_unit(attacker_unit)
	# The +1 A / +1 S melee bonus is the 10e Waaagh! only — at 11e a riled-up
	# unit gets 5+ InSv / [ASSAULT] / advance-and-charge, no melee bonus.
	var waaagh_melee_bonus = FactionAbilityManager.waaagh_melee_bonus_applies(attacker_unit)
	# WP-O6: Codex: Orks (11e) datasheet abilities for this melee batch
	# (Might Is Right, Rokkit Charge, High-speed Carnage, Super Runts, ...).
	var ork6: Dictionary = ork11e_ab_mods(attacker_unit, target_unit, weapon_profile, true, board)
	var ork6_a := int(ork6.get("attacks", 0))
	var ork6_ws := int(ork6.get("ws", 0))

	# Compute per-model fight eligibility based on engagement range
	var eligible_model_indices = get_eligible_melee_model_indices(attacker_unit, board)
	# MA-LOADOUT (melee): and of those, the ones that actually CARRY this weapon
	# (it resolves the per-model loadout on the way in).
	var swinging_model_indices = _melee_weapon_swingers(
		attacker_unit, weapon_id, eligible_model_indices, attacking_models, attacker_name, weapon_name)
	var total_alive_models = 0

	for model_index in range(attacker_models.size()):
		var model = attacker_models[model_index]
		if not model.get("alive", true):
			continue

		total_alive_models += 1

		# Eligible to fight (in ER or base-contact chain), inside any explicit
		# model selection, and equipped with the weapon — see _melee_weapon_swingers.
		if not model_index in swinging_model_indices:
			continue

		model_count += 1

		# MA-11: Get this model's effective WS (may differ from weapon profile)
		var model_ws = _get_model_effective_ws(model, attacker_unit, weapon_profile)
		# WP-O6 (Super Runts): "+1 WS" improves the characteristic (5+ -> 4+), never past 2+
		if ork6_ws > 0:
			model_ws = maxi(2, int(model_ws) - ork6_ws)
		if model_ws != weapon_profile.get("ws", 4):
			has_ws_override = true

		# Roll variable attacks for each model separately (per 10e rules)
		var attacks_result = roll_variable_characteristic(attacks_raw, rng)
		var model_attacks = attacks_result.value

		# WAAAGH! BONUS: +1 Attack to melee weapons
		# BALANCE DATASLATE (P2-75): Skip for Extra Attacks weapons — Waaagh! doesn't name specific weapons
		if waaagh_melee_bonus and not is_extra_attacks_weapon:
			model_attacks += 1
		elif waaagh_melee_bonus and is_extra_attacks_weapon:
			print("RulesEngine: Waaagh! +1 attack BLOCKED for Extra Attacks weapon '%s' (Balance Dataslate)" % weapon_name)

		# WP-O6: +A per attacking model from Codex: Orks (11e) datasheet abilities
		if ork6_a > 0 and not is_extra_attacks_weapon:
			model_attacks += ork6_a
			print("RulesEngine: [WP-O6] +%d A for model (Codex: Orks 11e datasheet abilities)" % ork6_a)

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

	# UNBRIDLED CARNAGE (Codex: Orks 11e, Green Tide): "Your unit's melee
	# attacks have +1 A" — +N to the A characteristic of every melee weapon of
	# each swinging model (OrkCodexFight writes ork11e_plus_attacks_melee).
	var ork11e_melee_a_bonus := int(attacker_unit.get("flags", {}).get("ork11e_plus_attacks_melee", 0))
	if model_count > 0 and ork11e_melee_a_bonus > 0 and not is_extra_attacks_weapon:
		var uc_total = ork11e_melee_a_bonus * model_count
		total_attacks += uc_total
		var uc_ws = weapon_profile.get("ws", 4)
		for _j in range(uc_total):
			ws_per_attack.append(uc_ws)
		print("RulesEngine: UNBRIDLED CARNAGE — +%d A for '%s' (melee) → +%d total (%d models)" % [ork11e_melee_a_bonus, weapon_name, uc_total, model_count])
	# Codex: Adeptus Custodes stratagems (CustodesCodex11e.gd): AVENGE THE FALLEN +2 A (not for CHARACTER models).
	var cus11e_melee_a := int(_cus11e_codex().bonus_attacks_per_model(attacker_unit, target_unit, weapon_profile, false, true)) if model_count > 0 and not is_extra_attacks_weapon else 0
	if cus11e_melee_a > 0:
		var atf_total = cus11e_melee_a * model_count
		total_attacks += atf_total
		for _j in range(atf_total):
			ws_per_attack.append(weapon_profile.get("ws", 4))
		print("RulesEngine: AVENGE THE FALLEN — +%d A for '%s' (melee) → +%d total (%d models)" % [cus11e_melee_a, weapon_name, atf_total, model_count])
	# Codex: Orks (11e) Try Dat Button! +1 A (WP-O34) — same Extra Attacks exclusion as above.
	var ork11e_tdb_a := ork11e_det_attacks_per_model(attacker_unit)
	if model_count > 0 and ork11e_tdb_a > 0 and not is_extra_attacks_weapon:
		var tdb_total = ork11e_tdb_a * model_count
		total_attacks += tdb_total
		for _j in range(tdb_total):
			ws_per_attack.append(weapon_profile.get("ws", 4))
		print("RulesEngine: TRY DAT BUTTON! — +%d A for '%s' (melee) → +%d total (%d models)" % [ork11e_tdb_a, weapon_name, tdb_total, model_count])

	# DEATHSONG SCYTHES (Silent Hunters): +X melee Attacks, but only while the
	# attack targets a PSYKER unit.
	if model_count > 0 and not is_extra_attacks_weapon:
		var vs_psyker_bonus = EffectPrimitivesData.get_effect_plus_attacks_vs_psyker(attacker_unit)
		if vs_psyker_bonus > 0 and unit_has_keyword(target_unit, "PSYKER"):
			var vs_psyker_total = vs_psyker_bonus * model_count
			total_attacks += vs_psyker_total
			var vsp_ws = weapon_profile.get("ws", 4)
			for _j in range(vs_psyker_total):
				ws_per_attack.append(vsp_ws)
			print("RulesEngine: Effect +%d Attacks vs PSYKER for '%s' (melee) → +%d total" % [vs_psyker_bonus, weapon_name, vs_psyker_total])

	# Codex: Adeptus Custodes (11e) MEMENTO MORITOI (WP-C46): the bearer's melee attacks +1 A (and +1 S / +1 D below).
	var cus11e_mpb: Dictionary = cus11e_melee_profile_bonus(attacker_unit)
	if model_count > 0 and int(cus11e_mpb.a) > 0:
		var mm_total = int(cus11e_mpb.a) * model_count
		total_attacks += mm_total
		for _j in range(mm_total):
			ws_per_attack.append(weapon_profile.get("ws", 4))
		print("RulesEngine: %s — +%d A for '%s' (melee) → +%d total" % [str(cus11e_mpb.source), int(cus11e_mpb.a), weapon_name, mm_total])
	# Codex: Adeptus Custodes (11e) melee weapon grants: Martial Mastery / Flawless Bladework /
	# From the Hall of Armouries / Auric Exemplar (CustodesDetachments.gd, WP-C46).
	var cus11e_mg: Dictionary = cus11e_melee_grants(attacker_unit, target_unit, board)

	# 11e [CLEAVE X] (24.06): if this weapon makes all its attacks against a
	# single target unit, add X dice for every 5 models in the target (melee
	# blast). Melee attack-splitting isn't modelled, so a melee weapon always
	# has a single target here.
	if GameConstants.edition >= 11:
		var cleave_x = get_cleave_value(weapon_id, board)
		# DEVASTATING DRIFT (Rollin' Deff): melee weapons gain [CLEAVE 1]
		if attacker_unit.get("flags", {}).get("effect_grant_cleave_1", false):
			cleave_x = maxi(cleave_x, 1)
			print("RulesEngine: DEVASTATING DRIFT — melee weapon %s gains CLEAVE 1" % weapon_id)
		# MOW 'EM DOWN (Codex: Orks 11e, War Horde): melee attacks have
		# [CLEAVE 1], or +1 to the value of a [CLEAVE] they already have.
		if attacker_unit.get("flags", {}).get("ork11e_mow_em_down", false):
			var mow_before = cleave_x
			cleave_x = cleave_x + 1 if cleave_x > 0 else 1
			print("RulesEngine: MOW 'EM DOWN — melee weapon %s [CLEAVE %d] -> [CLEAVE %d]" % [weapon_id, mow_before, cleave_x])
		# Codex: Adeptus Custodes (11e) AURIC EXEMPLAR: the bearer's melee attacks have [CLEAVE 1] (WP-C46).
		if int(cus11e_mg.cleave) > cleave_x:
			cleave_x = int(cus11e_mg.cleave)
			print("RulesEngine: %s — melee weapon %s gains [CLEAVE %d]" % [str(cus11e_mg.cleave_source), weapon_id, cleave_x])
		# WP-M4c INTO THE FRAY (Captain on Bike): charged this turn -> this unit's melee attacks have [CLEAVE 1].
		if cleave_x < SMAbilitiesC11eScript.melee_cleave(attacker_unit):
			cleave_x = SMAbilitiesC11eScript.melee_cleave(attacker_unit)
			print("RulesEngine: Into the Fray — melee weapon %s gains [CLEAVE %d]" % [weapon_id, cleave_x])
		if cleave_x > 0:
			# 19.01: an Attached unit is ONE unit — its leaders' models count
			# toward "every 5 models in the target" as well as the bodyguard's.
			var cleave_models = attached_unit_alive_model_count(target_id, board)
			var cleave_extra = AbilityRegistry.cleave_bonus_dice(cleave_x, cleave_models, true)
			if cleave_extra > 0:
				total_attacks += cleave_extra
				var cleave_ws = weapon_profile.get("ws", 4)
				for _j in range(cleave_extra):
					ws_per_attack.append(cleave_ws)
				print("RulesEngine: [CLEAVE %d] +%d dice vs %d-model target (melee)" % [cleave_x, cleave_extra, cleave_models])

	if model_count < total_alive_models:
		print("RulesEngine: Melee eligibility filter: %d/%d alive models eligible to fight" % [model_count, total_alive_models])

	if total_attacks == 0:
		result.log_text = "No valid attacking models (0/%d in engagement range)" % total_alive_models
		result.early_exit = true
		return result

	# ===== PHASE 2: GET COMBAT STATS =====
	# Use WS from weapon profile (10e: WS is on the weapon, not the unit)
	var ws = weapon_profile.get("ws", 4)
	var strength = weapon_profile.get("strength", 4)

	# Codex: Adeptus Custodes (11e) MEMENTO MORITOI: +1 S on the bearer's melee attacks (WP-C46).
	if int(cus11e_mpb.s) > 0:
		strength += int(cus11e_mpb.s)
		print("RulesEngine: %s — melee strength %d → %d" % [str(cus11e_mpb.source), strength - int(cus11e_mpb.s), strength])

	# WAAAGH! BONUS: +1 Strength to melee weapons (10e only — see waaagh_melee_bonus_applies)
	if waaagh_melee_bonus:
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
	# Codex: Space Marines (11e) STRIKE FROM THE SHADOWS (SMCodex11e.gd): +1 S.
	var sm11e_ms := int(_sm11e_codex().attack_grants(attacker_unit, target_unit, true).strength)
	if sm11e_ms > 0:
		strength += sm11e_ms
		print("RulesEngine: Strike from the Shadows — melee strength +%d (now %d)" % [sm11e_ms, strength])

	# (WP-O5: the 10e Green Tide Ferocious Show Off +S is gone — the codex
	# Ferocious Show-off is +1/+2 A, OrkEnhancements11e.merge_attack_mods.)

	# KLANKIN' KLAWS (Dread Mob): +2 S on melee weapons for the phase
	var kk_strength_bonus = int(attacker_unit.get("flags", {}).get("effect_klankin_klaws", 0))
	if kk_strength_bonus > 0:
		strength += kk_strength_bonus
		print("RulesEngine: KLANKIN' KLAWS — melee strength +%d (now %d)" % [kk_strength_bonus, strength])

	# GET ON WIV IT Taktik (Taktikal Brigade — Lissen 'Ere): +1 S on melee
	# weapons until the start of the issuer's next Command phase
	var taktik_s_bonus = int(attacker_unit.get("flags", {}).get("effect_taktik_melee_strength", 0))
	if taktik_s_bonus > 0:
		strength += taktik_s_bonus
		print("RulesEngine: GET ON WIV IT Taktik — melee strength +%d (now %d)" % [taktik_s_bonus, strength])
	strength += ork11e_det_strength_bonus(attacker_unit, weapon_id, board)  # Codex: Orks (11e) Try Dat Button! / Powers of da Waaagh! (WP-O34)

	# WP-O6: Codex: Orks (11e) datasheet-ability Strength (Might Is Right, High-speed Carnage, ...)
	if int(ork6.get("strength", 0)) != 0:
		strength += int(ork6.get("strength", 0))
		print("RulesEngine: [WP-O6] melee strength +%d → S%d" % [int(ork6.get("strength", 0)), strength])

	var toughness = _get_attached_unit_toughness(target_unit, board)  # P2-90: Use bodyguard T for attached units
	# OA-44: DED GLOWY AMMO — -1T to enemy INFANTRY within 6" of Kaptin Badrukk (melee)
	var ded_glowy_penalty_melee = get_ded_glowy_ammo_toughness_penalty(target_unit, board)
	if ded_glowy_penalty_melee > 0:
		toughness = max(1, toughness - ded_glowy_penalty_melee)
		print("RulesEngine: DED GLOWY AMMO (melee) — INFANTRY target T reduced by %d to T%d" % [ded_glowy_penalty_melee, toughness])
	var ap = weapon_profile.get("ap", 0)
	# (The 10e Shield Host Martial Mastery "improve AP" option is gone — the
	# codex Martial Mastery is a [SUSTAINED HITS 1] / [LETHAL HITS] choice, WP-C46.)
	# IMPROVE AP: effect-granted AP improvement (melee scope)
	var melee_improve_ap = EffectPrimitivesData.get_effect_improve_ap_scoped(attacker_unit, "melee")
	if melee_improve_ap > 0:
		var pre_ap_imp = ap
		ap = improve_ap(ap, melee_improve_ap)
		print("RulesEngine: Improve AP (melee) — AP %d → %d (improve by %d)" % [pre_ap_imp, ap, melee_improve_ap])
	# PREY (Da Big Hunt): +1 AP for BEAST SNAGGA attacks against the attacker's Prey
	var melee_prey_bonus = get_prey_ap_bonus(attacker_unit, target_unit)
	if melee_prey_bonus > 0:
		ap = improve_ap(ap, melee_prey_bonus)
		print("RulesEngine: PREY (melee) — AP improved by %d (target is Prey)" % melee_prey_bonus)
	# TRY DAT BUTTON! (Dread Mob, 5-6): +2 AP (40kdc flatten of the Critical Wound rider)
	if attacker_unit.get("flags", {}).get("effect_try_dat_ap2", false):
		ap = improve_ap(ap, 2)
		print("RulesEngine: TRY DAT BUTTON! (melee) — AP improved by 2")
	# WP-O6: Codex: Orks (11e) datasheet-ability AP (melee)
	if int(ork6.get("ap", 0)) > 0:
		var pre_ap_o6 = ap
		ap = improve_ap(ap, int(ork6.get("ap", 0)))
		print("RulesEngine: [WP-O6] (melee) AP %d → %d" % [pre_ap_o6, ap])
	# Codex: Adeptus Custodes stratagems (CustodesCodex11e.gd): PSY-CHAFF VOLLEY +1 AP vs a prosecuted unit, IN AURAMITE CLAD -1 AP.
	ap = _cus11e_codex().modify_ap(ap, attacker_unit, target_unit)
	# Codex: Space Marines (11e) stratagems (SMCodex11e.gd): ARMOUR OF CONTEMPT -1 AP to attacks that target the unit.
	ap = _sm11e_codex().modify_ap(ap, attacker_unit, target_unit)
	# WORSEN AP: Ramshackle etc. — reduce AP of incoming attacks (min 0)
	var melee_worsen_ap = EffectPrimitivesData.get_effect_worsen_ap(target_unit)
	if melee_worsen_ap > 0 and ap != 0:
		var pre_ap = ap
		ap = worsen_ap(ap, melee_worsen_ap)
		print("RulesEngine: Worsen AP (melee) — AP %d → %d (worsen by %d)" % [pre_ap, ap, melee_worsen_ap])
	var damage = weapon_profile.get("damage", 1)

	# Codex: Adeptus Custodes (11e) MEMENTO MORITOI: +1 D on the bearer's melee attacks (WP-C46).
	if int(cus11e_mpb.d) > 0:
		damage += int(cus11e_mpb.d)
		print("RulesEngine: %s — melee damage %d → %d" % [str(cus11e_mpb.source), damage - int(cus11e_mpb.d), damage])

	# WP-O6: Codex: Orks (11e) datasheet-ability Damage (High-speed Carnage, Brutal Impact)
	var ork6_d := int(ork6.get("damage", 0))
	if ork6_d > 0:
		print("RulesEngine: [WP-O6] (melee) +%d Damage per attack from Codex: Orks (11e) datasheet abilities" % ork6_d)

	var base_save = target_unit.get("meta", {}).get("stats", {}).get("save", 7)

	# ===== PHASE 3: DETECT WEAPON ABILITIES =====
	var weapon_has_lethal_hits = has_lethal_hits(weapon_id, board, target_unit)
	var sustained_data = get_sustained_hits_value(weapon_id, board, target_unit)
	var weapon_has_devastating_wounds = has_devastating_wounds(weapon_id, board, target_unit)
	# BEASTLY RAGE: Beastboss on Squigosaur — melee weapons gain DEVASTATING WOUNDS after charging
	if not weapon_has_devastating_wounds and has_beastly_rage_active(attacker_unit):
		weapon_has_devastating_wounds = true
		print("RulesEngine:   DEVASTATING WOUNDS granted by Beastly Rage (charged this turn)")
	# WP-S4 Headhunters (Space Wolves): melee attacks vs the quarry have [DEVASTATING WOUNDS].
	if not weapon_has_devastating_wounds and bool(ork6.get("devastating", false)):
		weapon_has_devastating_wounds = true
		print("RulesEngine:   DEVASTATING WOUNDS granted by a codex (11e) datasheet ability (melee)")
	# 24.10 (audit #17): attacker may decline the mortal-wound conversion.
	if GameConstants.edition >= 11 and weapon_has_devastating_wounds \
			and str(assignment.get("devastating_wounds_choice", "")) == "normal":
		weapon_has_devastating_wounds = false
		print("RulesEngine: [24.10] DEVASTATING WOUNDS — attacker declined the mortal-wound conversion (melee)")
	var is_torrent = is_torrent_weapon(weapon_id, board) or assignment.get("torrent", false) or bool(ork6.get("torrent", false))  # WP-O5 Temperamental Shokka (1: [TORRENT])
	# PRECISION: Check both weapon keyword and stratagem flag on attacker
	var weapon_has_precision = has_precision(weapon_id, board) or has_stratagem_precision_melee(attacker_unit) or bool(ork6.get("precision", false))  # WP-S4 Headhunters: [PRECISION] vs the quarry

	# EFFECT FLAGS: unit-level Lethal / Sustained Hits grants set by abilities or
	# stratagems via EffectPrimitives.
	if not weapon_has_lethal_hits and EffectPrimitivesData.has_effect_lethal_hits(attacker_unit):
		weapon_has_lethal_hits = true
		print("RulesEngine:   LETHAL HITS granted by unit effect flag")
	if sustained_data.value == 0 and EffectPrimitivesData.has_effect_sustained_hits(attacker_unit):
		sustained_data = {"value": 1, "is_dice": false}
		print("RulesEngine:   SUSTAINED HITS 1 granted by unit effect flag")
	# Codex: Adeptus Custodes RENDAX ka'tah (CustodesKatah.gd): melee attacks have
	# [LETHAL HITS: MONSTER/VEHICLE] — only vs a MONSTER or VEHICLE target.
	if not weapon_has_lethal_hits and _cus11e_katah().rendax_lethal_hits(attacker_unit, target_unit):
		weapon_has_lethal_hits = true
		print("RulesEngine:   LETHAL HITS (MONSTER/VEHICLE) granted by the RENDAX ka'tah vs %s" % target_name)
	# Codex: Adeptus Custodes (11e) Martial Mastery [SUSTAINED HITS 1] / [LETHAL HITS], Flawless
	# Bladework [SUSTAINED HITS 1], From the Hall of Armouries [DEVASTATING WOUNDS] (WP-C46).
	if not weapon_has_lethal_hits and str(cus11e_mg.lethal) != "":
		weapon_has_lethal_hits = true
		print("RulesEngine:   LETHAL HITS granted by %s" % str(cus11e_mg.lethal))
	if sustained_data.value == 0 and str(cus11e_mg.sustained) != "":
		sustained_data = {"value": 1, "is_dice": false}
		print("RulesEngine:   SUSTAINED HITS 1 granted by %s" % str(cus11e_mg.sustained))
	if not weapon_has_devastating_wounds and str(cus11e_mg.devastating) != "" \
			and str(assignment.get("devastating_wounds_choice", "")) != "normal":
		weapon_has_devastating_wounds = true
		print("RulesEngine:   DEVASTATING WOUNDS granted by %s" % str(cus11e_mg.devastating))
	# Codex: Adeptus Custodes stratagems (CustodesCodex11e.gd): GRIM RESPONSIBILITY [LETHAL HITS: CHARACTER/MONSTER].
	if not weapon_has_lethal_hits and _cus11e_codex().melee_lethal_hits(attacker_unit, target_unit):
		weapon_has_lethal_hits = true
		print("RulesEngine:   LETHAL HITS (CHARACTER/MONSTER) granted by GRIM RESPONSIBILITY vs %s" % target_name)

	# Codex: Space Marines (11e) stratagems (SMCodex11e.gd): RELENTLESS ASSAULT / STRIKE FROM THE SHADOWS.
	var sm11e_mg: Dictionary = _sm11e_codex().attack_grants(attacker_unit, target_unit, true)
	if not weapon_has_lethal_hits and str(sm11e_mg.lethal) != "":
		weapon_has_lethal_hits = true
		print("RulesEngine:   LETHAL HITS granted by %s" % str(sm11e_mg.lethal))
	if sustained_data.value == 0 and int(sm11e_mg.sustained) > 0:
		sustained_data = {"value": int(sm11e_mg.sustained), "is_dice": false}
		print("RulesEngine:   SUSTAINED HITS %d granted by a Codex: Space Marines stratagem" % int(sm11e_mg.sustained))

	# FIGHT PROPPA (Taktikal Brigade, 10e) and HIT 'EM HARDER (Codex: Orks 11e,
	# OrkCodexFight.gd): melee-scoped grants — [SUSTAINED HITS 1] or
	# [LETHAL HITS] for this unit's melee weapons this phase. These flags are
	# read ONLY here, never in shooting resolution.
	if not weapon_has_lethal_hits and attacker_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_LETHAL_HITS_MELEE, false):
		weapon_has_lethal_hits = true
		print("RulesEngine:   LETHAL HITS granted by melee effect flag (melee-scoped stratagem: HIT 'EM HARDER / Fight Proppa)")
	if sustained_data.value == 0 and attacker_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_SUSTAINED_HITS_MELEE, false):
		sustained_data = {"value": 1, "is_dice": false}
		print("RulesEngine:   SUSTAINED HITS 1 granted by melee effect flag (Fight Proppa)")

	# TRY DAT BUTTON! (Dread Mob): rolled Button Effect — melee scope
	if not weapon_has_lethal_hits and attacker_unit.get("flags", {}).get("effect_try_dat_lethal_melee", false):
		weapon_has_lethal_hits = true
		print("RulesEngine:   LETHAL HITS granted by TRY DAT BUTTON! (Dread Mob)")
	if sustained_data.value == 0 and attacker_unit.get("flags", {}).get("effect_try_dat_sustained_melee", false):
		sustained_data = {"value": 1, "is_dice": false}
		print("RulesEngine:   SUSTAINED HITS 1 granted by TRY DAT BUTTON! (Dread Mob)")

	# GET STUCK IN (P2-27): War Horde detachment — Sustained Hits 1 on all melee weapons for ORKS
	if GameConstants.edition < 11 and sustained_data.value == 0 and FactionAbilityManager.unit_has_get_stuck_in(attacker_unit):
		sustained_data = {"value": 1, "is_dice": false}
		print("RulesEngine:   SUSTAINED HITS 1 granted by Get Stuck In (War Horde detachment)")
	# Codex: Orks (11e) (WP-O34): Get Stuck In / Displays of Savagery / Mob-handed Brutality melee [SUSTAINED HITS 1].
	if GameConstants.edition >= 11 and sustained_data.value == 0:
		var ork11e_sh: Dictionary = ork11e_det().melee_sustained_hits(attacker_unit, board)
		if int(ork11e_sh.get("value", 0)) > 0:
			sustained_data = {"value": int(ork11e_sh.value), "is_dice": false}
			print("RulesEngine:   SUSTAINED HITS %d granted by %s" % [int(ork11e_sh.value), str(ork11e_sh.source)])
	# Codex: Orks (11e) Mob-handed Brutality (WP-O34): charged ORKS INFANTRY melee [LETHAL HITS] vs non-MONSTER/VEHICLE.
	if GameConstants.edition >= 11 and not weapon_has_lethal_hits:
		var ork11e_lh_src: String = ork11e_det().melee_lethal_hits_source(attacker_unit, target_unit, board)
		if ork11e_lh_src != "":
			weapon_has_lethal_hits = true
			print("RulesEngine:   LETHAL HITS granted by %s" % ork11e_lh_src)

	# HERE BE LOOT (OA-1): Freebooter Krew — Sustained Hits 1 near loot objective (melee)
	if sustained_data.value == 0 and FactionAbilityManager.check_here_be_loot_sustained_hits(attacker_unit, target_unit, board):
		sustained_data = {"value": 1, "is_dice": false}
		print("RulesEngine:   SUSTAINED HITS 1 granted by Here Be Loot (Freebooter Krew detachment)")

	# GHAZGHKULL'S WAAAGH! BANNER (OA-45): Lethal Hits on melee attacks for ORKS within 12" of Makari during Waaagh!
	if not weapon_has_lethal_hits and unit_has_waaagh_banner_lethal_hits(attacker_unit, board):
		weapon_has_lethal_hits = true
		print("RulesEngine:   LETHAL HITS granted by Ghazghkull's Waaagh! Banner (ORKS within 12\" of Makari, Waaagh! active)")
	# WP-O6: Tide of Muscle / Warpath (Kill Rig) / Bust 'Em: [LETHAL HITS]
	if not weapon_has_lethal_hits and bool(ork6.get("lethal", false)):
		weapon_has_lethal_hits = true
		print("RulesEngine:   LETHAL HITS granted by a Codex: Orks (11e) datasheet ability (melee)")
	# WP-C7: Codex: Adeptus Custodes (11e) Quicksilver Execution / Impenetrable Defence: melee [SUSTAINED HITS 1] (the ranged paths read the same key).
	if int(sustained_data.value) == 0 and int(ork6.get("sustained", 0)) > 0:
		sustained_data = {"value": int(ork6.get("sustained", 0)), "is_dice": false}
		print("RulesEngine:   SUSTAINED HITS %d granted by a codex (11e) datasheet ability (melee)" % int(ork6.get("sustained", 0)))

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
	# STAGED FIGHT: per-die records for Command Re-roll (mirrors the ranged path).
	# Declarations hoisted out of the non-torrent branch so the hit_context can be
	# built unconditionally; behaviour is unchanged (torrent makes no hit roll).
	var hit_evals = []
	var modified_rolls = []
	var melee_hit_reroll_data = []
	var melee_crit_threshold = 6  # Default: only unmodified 6s are critical hits
	# ISS-modifier-provenance: names WHERE each modifier below came from, so the
	# Dice Log and the resolution docks can say "Against All Odds: +1 to hit"
	# instead of an anonymous "+1". Purely additive — never read by the maths.
	var melee_hit_modifiers = HitModifier.NONE
	var melee_hit_mod_ledger: Array = []

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

		# Effect-granted critical hit threshold (stratagems or other abilities)
		var effect_crit = EffectPrimitivesData.get_effect_crit_hit_on(attacker_unit)
		if effect_crit > 0 and effect_crit < melee_crit_threshold:
			melee_crit_threshold = effect_crit
			print("RulesEngine: Effect crit_hit_on %d+ active — melee critical hit threshold: %d+" % [effect_crit, effect_crit])
		# DRAG IT DOWN (Da Big Hunt): melee crits on 5+ when the target is the
		# attacker's Prey (per-target live check on the Prey marker flag).
		if attacker_unit.get("flags", {}).get("effect_drag_it_down", false) and melee_crit_threshold > 5:
			var did_owner = int(attacker_unit.get("owner", 0))
			if did_owner > 0 and target_unit.get("flags", {}).get("is_prey_of_%d" % did_owner, false):
				melee_crit_threshold = 5
				print("RulesEngine: DRAG IT DOWN — melee critical hits on 5+ (target is Prey)")

		# Build melee hit modifiers using the HitModifier system
		# Get hit modifiers from assignment
		if assignment.has("modifiers") and assignment.modifiers.has("hit"):
			var hit_mods = assignment.modifiers.hit
			if hit_mods.get("reroll_ones", false):
				melee_hit_modifiers |= HitModifier.REROLL_ONES
				ModifierLedger.note(melee_hit_mod_ledger, "Attack assignment", ModifierLedger.KIND_HIT, ModifierLedger.REROLL_ONES)
			if hit_mods.get("reroll_failed", false):
				melee_hit_modifiers |= HitModifier.REROLL_FAILED
				ModifierLedger.note(melee_hit_mod_ledger, "Attack assignment", ModifierLedger.KIND_HIT, ModifierLedger.REROLL_FAILED)

		# EFFECT FLAGS: Check for ability/stratagem-granted hit modifiers on the attacker (melee)
		if EffectPrimitivesData.has_effect_plus_one_hit(attacker_unit):
			melee_hit_modifiers |= HitModifier.PLUS_ONE
			ModifierLedger.note(melee_hit_mod_ledger, "Ability effect", ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE, "granted by an ability or Stratagem")
			print("RulesEngine: Effect +1 to hit (melee) applied for %s" % attacker_id)
		if EffectPrimitivesData.has_effect_minus_one_hit(attacker_unit):
			melee_hit_modifiers |= HitModifier.MINUS_ONE
			ModifierLedger.note(melee_hit_mod_ledger, "Ability effect", ModifierLedger.KIND_HIT, ModifierLedger.MINUS_ONE, "imposed by an ability or Stratagem")
			print("RulesEngine: Effect -1 to hit (melee) applied for %s" % attacker_id)
		# DEFENDER FLAG (UNWAVERING SENTINELS): -1 to hit for melee attacks targeting the flagged unit
		if EffectPrimitivesData.has_effect_minus_one_hit_defense_melee(target_unit):
			melee_hit_modifiers |= HitModifier.MINUS_ONE
			ModifierLedger.note(melee_hit_mod_ledger, "Unwavering Sentinels", ModifierLedger.KIND_HIT, ModifierLedger.MINUS_ONE, "defender's ability")
			print("RulesEngine: Defender effect -1 to hit (melee attacks vs %s)" % target_unit.get("meta", {}).get("name", "?"))
		var melee_reroll_hits_scope = attacker_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_REROLL_HITS, "")
		if melee_reroll_hits_scope == "ones":
			melee_hit_modifiers |= HitModifier.REROLL_ONES
			ModifierLedger.note(melee_hit_mod_ledger, "Ability effect", ModifierLedger.KIND_HIT, ModifierLedger.REROLL_ONES, "granted by an ability or Stratagem")
			print("RulesEngine: Effect re-roll 1s to hit (melee) applied for %s" % attacker_id)
		elif melee_reroll_hits_scope == "failed" or melee_reroll_hits_scope == "all":
			melee_hit_modifiers |= HitModifier.REROLL_FAILED
			ModifierLedger.note(melee_hit_mod_ledger, "Ability effect", ModifierLedger.KIND_HIT, ModifierLedger.REROLL_FAILED, "granted by an ability or Stratagem")
			print("RulesEngine: Effect re-roll hits (melee) applied for %s" % attacker_id)
		elif melee_reroll_hits_scope == REROLL_HITS_SCOPE_NON_CRIT:
			melee_hit_modifiers |= _non_crit_hit_reroll_bits(attacker_unit, weapon_id, board, true)
			ModifierLedger.note(melee_hit_mod_ledger, "Ability effect", ModifierLedger.KIND_HIT, ModifierLedger.REROLL_FAILED, "re-roll hit rolls (non-critical hits too, for critical-hit weapons)")
			print("RulesEngine: Effect re-roll hit rolls (melee, fishing for crits where they matter) applied for %s / %s" % [attacker_id, weapon_id])

		# DAMAGED PROFILE (P1-14): Check if attacker has Damaged profile active
		if is_damaged_profile_active(attacker_unit):
			melee_hit_modifiers |= HitModifier.MINUS_ONE
			ModifierLedger.note(melee_hit_mod_ledger, "Damaged profile", ModifierLedger.KIND_HIT, ModifierLedger.MINUS_ONE, "attacker is on its Damaged profile")
			print("RulesEngine: Damaged profile -1 to hit (melee) applied for %s" % attacker_id)

		# WP-O6: Codex: Orks (11e) datasheet abilities (Krumpin' Time, Sumfin' to Prove,
		# Prophet of da Great Waaagh!, Big an' Stompy, Paired Krumpas, ...)
		melee_hit_modifiers = ork11e_ab_hit_bits(melee_hit_modifiers, melee_hit_mod_ledger, ork6)

		# XENOS HUNTER: +1 to Hit vs non-IMPERIUM/CHAOS targets (melee)
		if has_xenos_hunter_vs_target(attacker_unit, target_unit):
			melee_hit_modifiers |= HitModifier.PLUS_ONE
			ModifierLedger.note(melee_hit_mod_ledger, "Xenos Hunter", ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE, "target lacks IMPERIUM and CHAOS")
			print("RulesEngine: XENOS HUNTER (melee) — +1 to hit for %s (target lacks IMPERIUM/CHAOS)" % attacker_id)

		# Codex: Adeptus Custodes (11e) detachment rules / enhancements (CustodesDetachments.gd, WP-C46).
		melee_hit_modifiers = cus11e_apply_hit_effects(melee_hit_modifiers, melee_hit_mod_ledger, attacker_unit, target_unit, true, board)

		# Codex: Adeptus Custodes DACATARAI (attacker) / KAPTARIS (target) ka'tahs
		# (CustodesKatah.gd): re-roll hit rolls of 1 vs a non-MONSTER/VEHICLE
		# target; -1 to hit for melee attacks that target the unit.
		var cus11e_melee: Dictionary = _cus11e_katah().melee_hit_effects(attacker_unit, target_unit)
		if bool(cus11e_melee.get("reroll_ones", false)):
			melee_hit_modifiers |= HitModifier.REROLL_ONES
			ModifierLedger.note(melee_hit_mod_ledger, "Dacatarai (Ka'tah)", ModifierLedger.KIND_HIT, ModifierLedger.REROLL_ONES, "target is not a MONSTER or VEHICLE")
			print("RulesEngine: DACATARAI — %s re-rolls melee hit rolls of 1 vs %s" % [attacker_id, target_name])
		if bool(cus11e_melee.get("minus_one", false)):
			melee_hit_modifiers |= HitModifier.MINUS_ONE
			ModifierLedger.note(melee_hit_mod_ledger, "Kaptaris (Ka'tah)", ModifierLedger.KIND_HIT, ModifierLedger.MINUS_ONE, "defender's ka'tah")
			print("RulesEngine: KAPTARIS — melee attacks that target %s have -1 to hit" % target_name)
		# Codex: Adeptus Custodes stratagems (CustodesCodex11e.gd): SHIELD OF HONOUR / GOLDEN LIGHT (-1), HONOURED INTERRED (re-roll 1s), BEARERS OF HIS LIGHT (ignore -1).
		melee_hit_modifiers = _cus11e_codex().apply_hit_bits(melee_hit_modifiers, attacker_unit, target_unit, true, board, melee_hit_mod_ledger)
		# Codex: Space Marines (11e) Space Wolves stratagems (SWCodex11e.gd): CHAMPION'S GUIDANCE re-rolls melee hit rolls of 1.
		melee_hit_modifiers = _sw11e_codex().apply_hit_bits(melee_hit_modifiers, attacker_unit, target_unit, true, melee_hit_mod_ledger)
		# Codex: Space Marines (11e) stratagems (SMCodex11e.gd): MIGHT OF THE MACHINE SPIRIT ignores hit-roll penalties.
		melee_hit_modifiers = _sm11e_codex().apply_hit_bits(melee_hit_modifiers, attacker_unit, target_unit, true, melee_hit_mod_ledger)

		# A10 (24.29): [PSYCHIC] melee weapons ignore modifiers to the hit roll —
		# strip the harmful -1 (the shooting paths do the same). 11e only.
		if GameConstants.edition >= 11 and (is_psychic_weapon(weapon_id, board) or bool(ork6.get("psychic", false))):
			melee_hit_modifiers = melee_hit_modifiers & ~HitModifier.MINUS_ONE
			ModifierLedger.note(melee_hit_mod_ledger, "[PSYCHIC]", ModifierLedger.KIND_HIT, ModifierLedger.IGNORED, "psychic weapons ignore hit-roll penalties")
			ModifierLedger.mark_ignored(melee_hit_mod_ledger, ModifierLedger.KIND_HIT, [ModifierLedger.MINUS_ONE])
			print("RulesEngine: [PSYCHIC] (melee) — ignoring hit-roll penalties for %s" % weapon_name)

		# ISS-012: per-roll evaluation shared with the ranged paths
		# (AttackSequence.evaluate_hit_roll). melee_crit_threshold covers
		# Martial Mastery (5+); it is always <= 6, so the legacy redundant
		# `unmodified == 6` clause is subsumed by the crit check.
		for i in range(hit_rolls.size()):
			var roll = hit_rolls[i]
			# MA-11: Use per-model WS for this attack's threshold
			var attack_ws = ws_per_attack[i] if i < ws_per_attack.size() else ws
			var hit_eval = AttackSequence.evaluate_hit_roll(roll, attack_ws, melee_hit_modifiers, melee_crit_threshold, rng)
			modified_rolls.append(hit_eval.final_roll)
			hit_evals.append({"raw": roll, "final": hit_eval.final_roll, "is_hit": hit_eval.is_hit, "is_crit": hit_eval.is_crit, "rerolled": hit_eval.rerolled, "reroll_from": hit_eval.reroll_from, "reroll_to": hit_eval.reroll_to})
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

		# Codex: Adeptus Custodes MAGNA IMPERATOR (Emperor's Chosen, WP-C46): re-roll one hit roll (melee).
		var cus11e_mh_m: Dictionary = cus11e_magna_reroll_hit(attacker_unit, hit_evals, modified_rolls, melee_hit_reroll_data, ws_per_attack, ws, melee_hit_modifiers, melee_crit_threshold, rng, 1, melee_hit_mod_ledger, false)
		hits += int(cus11e_mh_m.hit)
		critical_hits += int(cus11e_mh_m.crit)
		regular_hits += int(cus11e_mh_m.hit) - int(cus11e_mh_m.crit)
		# WP-M2a Martial Paragon: re-roll one hit roll (melee).
		var sm11e_mh_m: Dictionary = sm11e_reroll_one_hit(attacker_unit, true, hit_evals, modified_rolls, melee_hit_reroll_data, ws_per_attack, ws, melee_hit_modifiers, melee_crit_threshold, rng, 1, melee_hit_mod_ledger)
		hits += int(sm11e_mh_m.hit)
		critical_hits += int(sm11e_mh_m.crit)
		regular_hits += int(sm11e_mh_m.hit) - int(sm11e_mh_m.crit)

		# SUSTAINED HITS: Generate bonus hits on critical hits
		if sustained_data.value > 0 and critical_hits > 0:
			sustained_result = roll_sustained_hits(critical_hits, sustained_data, rng)
			sustained_bonus_hits = sustained_result.bonus_hits

		# Total hits for wound rolls = regular hits + critical hits + bonus from Sustained
		# (If Lethal Hits: critical hits auto-wound, but sustained bonus hits still roll)
		total_hits_for_wounds = hits + sustained_bonus_hits

		# NOTE: the block shape is pinned by tests/fixtures/attack_goldens.json —
		# per-die modified rolls / reroll data live in hit_context (and flow to the
		# staged dialog via fight_stage_paused), not here.
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
			"precision_weapon": weapon_has_precision,
			# Named provenance for every hit modifier applied above.
			"modifier_ledger": melee_hit_mod_ledger
		})

	# Build the hit context up-front so it is available even on a full miss —
	# the staged fight path may Command Re-roll a MISSED die (turning it into a
	# hit), which needs the per-die evals/modifiers preserved here. WS values are
	# duplicated under the ranged "bs"/"bs_per_attack" keys for reroll_hit_die.
	var hit_context = {
		"is_melee": true,
		"assignment": assignment,
		"actor_unit_id": actor_unit_id,
		"attacker_id": attacker_id,
		"target_id": target_id,
		"target_unit_id": target_id,
		"weapon_id": weapon_id,
		"weapon_profile": weapon_profile,
		"weapon_name": weapon_name,
		"attacker_name": attacker_name,
		"target_name": target_name,
		"actor_unit": attacker_unit,
		"target_unit": target_unit,
		# Combat stats (post-modifier) needed by the wounds / saves thirds
		"ws": ws,
		"strength": strength,
		"toughness": toughness,
		"ap": ap,
		"damage": damage,
		"base_save": base_save,
		# WP-O6: Codex: Orks (11e) datasheet-ability modifiers (wound bits, +D)
		"ork11e_ab": ork6,
		"model_count": model_count,
		"total_alive_models": total_alive_models,
		# Weapon abilities
		"weapon_has_lethal_hits": weapon_has_lethal_hits,
		"weapon_has_devastating_wounds": weapon_has_devastating_wounds,
		"weapon_has_precision": weapon_has_precision,
		"sustained_data": sustained_data,
		"is_torrent": is_torrent,
		# Hit tallies + per-die records
		"hits": hits,
		"critical_hits": critical_hits,
		"regular_hits": regular_hits,
		"sustained_bonus_hits": sustained_bonus_hits,
		"total_hits_for_wounds": total_hits_for_wounds,
		"total_attacks": total_attacks,
		"hit_rolls": hit_rolls,
		"modified_rolls": modified_rolls,
		"hit_evals": hit_evals,
		"reroll_data": melee_hit_reroll_data,
		# reroll_hit_die compatibility (ranged field names)
		"bs": ws,
		"bs_per_attack": ws_per_attack,
		"hit_modifiers": melee_hit_modifiers,
		"modifier_ledger": melee_hit_mod_ledger,
		"critical_hit_threshold": melee_crit_threshold,
		"hit_fail_band": 1,
	}
	result["hit_context"] = hit_context

	if hits == 0 and sustained_bonus_hits == 0:
		var melee_miss_log = "Melee: %s (%s) → %s: %d attacks, 0 hits" % [attacker_name, weapon_name, target_name, total_attacks]
		if not hit_rolls.is_empty():
			melee_miss_log += " [%s] vs %s+" % [", ".join(hit_rolls.map(func(r): return str(r))), str(ws)]
		result.log_text = melee_miss_log
		result.no_hits = true
		return result

	return result

# Melee wounds third: PHASE 5 of the original monolith (wound rolls with Lethal
# Hits / Devastating Wounds / Anti-Keyword / Twin-linked). Takes the hit_context
# from _resolve_melee_assignment_hits; returns {dice, log_text, no_wounds,
# wounds_caused, critical_wound_count, regular_wound_count,
# all_critical_wound_count, auto_wounds, wound_rolls, wound_threshold,
# melee_wound_modifier_net, wound_context}. wound_context carries per-die evals
# so reroll_wound_die works for melee.
static func _resolve_melee_assignment_wounds(hit_context: Dictionary, board: Dictionary, rng: RNGService) -> Dictionary:
	var result = {
		"dice": [],
		"log_text": "",
		"no_wounds": false
	}
	var assignment = hit_context["assignment"]
	var attacker_id = hit_context["attacker_id"]
	var target_id = hit_context["target_id"]
	var weapon_id = hit_context["weapon_id"]
	var weapon_name = hit_context["weapon_name"]
	var attacker_name = hit_context["attacker_name"]
	var target_name = hit_context["target_name"]
	var units = board.get("units", {})
	var attacker_unit = units.get(attacker_id, {})
	var target_unit = units.get(target_id, {})
	var strength = hit_context["strength"]
	var toughness = hit_context["toughness"]
	var weapon_has_lethal_hits = hit_context["weapon_has_lethal_hits"]
	var weapon_has_devastating_wounds = hit_context["weapon_has_devastating_wounds"]
	var is_torrent = hit_context["is_torrent"]
	var hits = int(hit_context["hits"])
	var critical_hits = int(hit_context["critical_hits"])
	var regular_hits = int(hit_context["regular_hits"])
	var sustained_bonus_hits = int(hit_context["sustained_bonus_hits"])
	var total_hits_for_wounds = int(hit_context["total_hits_for_wounds"])
	var total_attacks = int(hit_context["total_attacks"])

	# ===== PHASE 5: WOUND ROLLS =====
	# With Lethal Hits, Sustained Hits, Devastating Wounds, and Anti-Keyword interactions
	var wound_threshold = _calculate_wound_threshold(strength, toughness)

	# ANTI-[KEYWORD] X+: Get critical wound threshold (6 normally, lower if Anti matches target)
	var melee_critical_wound_threshold = get_critical_wound_threshold(weapon_id, target_unit, board)
	var melee_anti_keyword_active = melee_critical_wound_threshold < 6

	# TWIN-LINKED: Check if weapon has Twin-linked (re-roll all failed wound rolls)
	var melee_weapon_has_twin_linked = has_twin_linked(weapon_id, board, target_unit) or assignment.get("twin_linked", false)

	# WOUND MODIFIERS (T1-3): Build wound modifier flags for melee path
	# ISS-modifier-provenance: names WHERE each modifier below came from, so the
	# Dice Log and the resolution docks can say "Against All Odds: +1 to hit"
	# instead of an anonymous "+1". Purely additive — never read by the maths.
	var melee_wound_modifiers = WoundModifier.NONE
	var melee_wound_mod_ledger: Array = []
	if assignment.has("modifiers") and assignment.modifiers.has("wound"):
		var wound_mods = assignment.modifiers.wound
		if wound_mods.get("reroll_ones", false):
			melee_wound_modifiers |= WoundModifier.REROLL_ONES
			ModifierLedger.note(melee_wound_mod_ledger, "Attack assignment", ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_ONES)
		if wound_mods.get("reroll_failed", false):
			melee_wound_modifiers |= WoundModifier.REROLL_FAILED
			ModifierLedger.note(melee_wound_mod_ledger, "Attack assignment", ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_FAILED)
		if wound_mods.get("plus_one", false):
			melee_wound_modifiers |= WoundModifier.PLUS_ONE
			ModifierLedger.note(melee_wound_mod_ledger, "Attack assignment", ModifierLedger.KIND_WOUND, ModifierLedger.PLUS_ONE)
		if wound_mods.get("minus_one", false):
			melee_wound_modifiers |= WoundModifier.MINUS_ONE
			ModifierLedger.note(melee_wound_mod_ledger, "Attack assignment", ModifierLedger.KIND_WOUND, ModifierLedger.MINUS_ONE)
	# Twin-linked handled via WoundModifier system for re-rolls
	if melee_weapon_has_twin_linked:
		melee_wound_modifiers |= WoundModifier.REROLL_FAILED
		ModifierLedger.note(melee_wound_mod_ledger, "[TWIN-LINKED]", ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_FAILED)

	# EFFECT FLAGS: Check for ability/stratagem-granted wound modifiers on the attacker (melee)
	if EffectPrimitivesData.has_effect_plus_one_wound(attacker_unit):
		melee_wound_modifiers |= WoundModifier.PLUS_ONE
		ModifierLedger.note(melee_wound_mod_ledger, "Ability effect", ModifierLedger.KIND_WOUND, ModifierLedger.PLUS_ONE, "granted by an ability or Stratagem")
		print("RulesEngine: Effect +1 to wound (melee) applied for %s" % attacker_id)
	if EffectPrimitivesData.has_effect_minus_one_wound(attacker_unit):
		melee_wound_modifiers |= WoundModifier.MINUS_ONE
		ModifierLedger.note(melee_wound_mod_ledger, "Ability effect", ModifierLedger.KIND_WOUND, ModifierLedger.MINUS_ONE, "imposed by an ability or Stratagem")
		print("RulesEngine: Effect -1 to wound (melee) applied for %s" % attacker_id)
	# DEFENDER FLAG ('ARD AS NAILS): -1 to wound for attacks targeting the flagged unit
	if EffectPrimitivesData.has_effect_minus_one_wound_defense(target_unit):
		melee_wound_modifiers |= WoundModifier.MINUS_ONE
		ModifierLedger.note(melee_wound_mod_ledger, "'Ard as Nails", ModifierLedger.KIND_WOUND, ModifierLedger.MINUS_ONE, "defender's ability")
		print("RulesEngine: Defender effect -1 to wound (melee attacks vs %s)" % target_name)
	var melee_reroll_wounds_scope = attacker_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_REROLL_WOUNDS, "")
	if melee_reroll_wounds_scope == "ones":
		melee_wound_modifiers |= WoundModifier.REROLL_ONES
		ModifierLedger.note(melee_wound_mod_ledger, "Ability effect", ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_ONES, "granted by an ability or Stratagem")
		print("RulesEngine: Effect re-roll 1s to wound (melee) applied for %s" % attacker_id)
	elif melee_reroll_wounds_scope == "failed" or melee_reroll_wounds_scope == "all":
		melee_wound_modifiers |= WoundModifier.REROLL_FAILED
		ModifierLedger.note(melee_wound_mod_ledger, "Ability effect", ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_FAILED, "granted by an ability or Stratagem")
		print("RulesEngine: Effect re-roll wounds (melee) applied for %s" % attacker_id)

	# BASH AND GRAB (OA-3): Freebooter Krew — re-roll Wound rolls vs targets near loot objective
	if attacker_unit.get("flags", {}).get("effect_bash_and_grab", false):
		if FactionAbilityManager.check_bash_and_grab_reroll_wounds(attacker_unit, target_unit, board):
			melee_wound_modifiers |= WoundModifier.REROLL_FAILED
			ModifierLedger.note(melee_wound_mod_ledger, "Bash and Grab", ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_FAILED, "Freebooter Krew — target holds an objective")
			print("RulesEngine: BASH AND GRAB (melee) — re-roll Wound rolls vs %s (near loot objective)" % target_name)
		else:
			print("RulesEngine: BASH AND GRAB active but target %s not within range of loot objective — no re-roll" % target_name)

	# ORKS IS STILL ORKS (More Dakka!): re-roll wound rolls of 1; full re-roll
	# when the target is within range of an objective marker.
	if attacker_unit.get("flags", {}).get("effect_orks_is_still_orks", false):
		if is_unit_near_any_objective(target_unit, board):
			melee_wound_modifiers |= WoundModifier.REROLL_FAILED
			ModifierLedger.note(melee_wound_mod_ledger, "Orks is Still Orks", ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_FAILED, "target within range of an objective marker")
			print("RulesEngine: ORKS IS STILL ORKS (melee) — full wound re-roll vs %s (near objective)" % target_name)
		else:
			melee_wound_modifiers |= WoundModifier.REROLL_ONES
			ModifierLedger.note(melee_wound_mod_ledger, "Orks is Still Orks", ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_ONES, "target within range of an objective marker")
			print("RulesEngine: ORKS IS STILL ORKS (melee) — re-roll wound 1s vs %s" % target_name)

	# LANCE (T4-1): +1 to wound if unit charged this turn (melee Lance weapons).
	# Effect-granted Lance treats all the unit's weapons as [LANCE] — set either
	# via EffectPrimitives GRANT_LANCE (effect_lance: Deathsong Scythes,
	# Servo-driven Charge, Plunging Talons) or directly as effect_grant_lance
	# (DED KILLY CONSTRUCTION, Speedwaaagh!).
	if is_lance_weapon(weapon_id, board) or EffectPrimitivesData.has_effect_lance(attacker_unit) \
			or attacker_unit.get("flags", {}).get("effect_grant_lance", false) \
			or (GameConstants.edition >= 11 and load("res://scripts/codex/space_wolves/SWDetachments11e.gd").melee_lance_source(attacker_unit) != ""):  # Codex: Space Marines (11e) Skjald's Foretelling melee [LANCE] (WP-S2)
		var unit_charged = attacker_unit.get("flags", {}).get("charged_this_turn", false)
		if unit_charged:
			melee_wound_modifiers |= WoundModifier.PLUS_ONE
			ModifierLedger.note(melee_wound_mod_ledger, "[LANCE]", ModifierLedger.KIND_WOUND, ModifierLedger.PLUS_ONE, "unit charged this turn")
			print("RulesEngine: LANCE (melee) — +1 to wound (unit charged this turn)")

	# FULL THROTTLE! (Kult of Speed): +1 to melee wound rolls until end of turn
	if attacker_unit.get("flags", {}).get("effect_full_throttle", false):
		melee_wound_modifiers |= WoundModifier.PLUS_ONE
		ModifierLedger.note(melee_wound_mod_ledger, "Full Throttle!", ModifierLedger.KIND_WOUND, ModifierLedger.PLUS_ONE)
		print("RulesEngine: FULL THROTTLE! (melee) — +1 to wound for %s" % attacker_id)

	# WP-O6: Codex: Orks (11e) datasheet abilities (Warpath, Da Bigger Dey Iz, Prophet aura, ...)
	melee_wound_modifiers = ork11e_ab_wound_bits(melee_wound_modifiers, melee_wound_mod_ledger, hit_context.get("ork11e_ab", {}))

	# HARDY BIONIKS (WP-O6, Painboss): -1 to wound for S > T attacks that target the unit (melee)
	if ork11e_ab_wound_penalty(target_unit, strength, toughness):
		melee_wound_modifiers |= WoundModifier.MINUS_ONE
		ModifierLedger.note(melee_wound_mod_ledger, ork11e_ab_wound_penalty_name(target_unit, strength, toughness), ModifierLedger.KIND_WOUND, ModifierLedger.MINUS_ONE, "attack's Strength exceeds the target's Toughness")
		print("RulesEngine: HARDY BIONIKS (melee) — -1 to wound for attacks against %s (S %d > T %d)" % [target_id, strength, toughness])
	# IMPERVIOUS / effect_minus_wound_s_gt_t: -1 to wound while S > T
	var melee_sgt_mod = get_s_gt_t_wound_penalty(target_unit, board, strength, toughness)
	if melee_sgt_mod != WoundModifier.NONE:
		melee_wound_modifiers |= melee_sgt_mod
		ModifierLedger.note(melee_wound_mod_ledger, "IMPERVIOUS", ModifierLedger.KIND_WOUND, ModifierLedger.MINUS_ONE, "attack's Strength exceeds the target's Toughness")
		print("RulesEngine: S>T wound penalty (melee) — -1 to wound for attacks against %s (S %d > T %d)" % [target_id, strength, toughness])


	# Codex: Adeptus Custodes (11e) detachment rules / enhancements (CustodesDetachments.gd, WP-C46).
	melee_wound_modifiers = cus11e_apply_wound_effects(melee_wound_modifiers, melee_wound_mod_ledger, attacker_unit, target_unit, true, strength, toughness, board)

	# Codex: Adeptus Custodes stratagems (CustodesCodex11e.gd): SLAYERS OF NIGHTMARES (+1), SHIELD OF HONOUR (-1), BEARERS OF HIS LIGHT (ignore -1).
	melee_wound_modifiers = _cus11e_codex().apply_wound_bits(melee_wound_modifiers, attacker_unit, target_unit, true, strength, toughness, melee_wound_mod_ledger)
	# Codex: Space Marines (11e) Space Wolves stratagems (SWCodex11e.gd): CHAMPION'S GUIDANCE (1s) / EYE OF THE PACK (1s and 2s) wound re-rolls.
	melee_wound_modifiers = _sw11e_codex().apply_wound_bits(melee_wound_modifiers, attacker_unit, target_unit, true, melee_wound_mod_ledger)
	# Codex: Space Marines (11e) stratagems (SMCodex11e.gd): MIGHT OF THE MACHINE SPIRIT ignores wound-roll penalties.
	melee_wound_modifiers = _sm11e_codex().apply_wound_bits(melee_wound_modifiers, attacker_unit, target_unit, true, melee_wound_mod_ledger)

	melee_wound_modifiers = sw11e_ignore_wound_penalties(melee_wound_modifiers, melee_wound_mod_ledger, hit_context.get("ork11e_ab", {}))  # WP-S4 Gift of the Iron Wolf (Space Wolves)
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
	var wound_evals = []  # STAGED FIGHT: per-die records for reroll_wound_die

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
				wound_evals.append({"raw": roll, "is_wound": wound_eval.is_wound, "is_crit": wound_eval.is_crit, "auto_fail": wound_eval.auto_fail, "rerolled": wound_eval.rerolled, "reroll_from": wound_eval.reroll_from, "reroll_to": wound_eval.reroll_to})
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
				wound_evals.append({"raw": roll, "is_wound": wound_eval.is_wound, "is_crit": wound_eval.is_crit, "auto_fail": wound_eval.auto_fail, "rerolled": wound_eval.rerolled, "reroll_from": wound_eval.reroll_from, "reroll_to": wound_eval.reroll_to})
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

	# Codex: Adeptus Custodes MAGNA IMPERATOR (Emperor's Chosen, WP-C46): re-roll one wound roll (melee).
	var cus11e_mw_m: Dictionary = cus11e_magna_reroll_wound(attacker_unit, wound_evals, wound_rolls, melee_wound_reroll_data, melee_wound_modifiers, wound_threshold, melee_critical_wound_threshold, rng, melee_wound_mod_ledger, false)
	if int(cus11e_mw_m.wound) > 0:
		wounds_from_rolls += 1
		if int(cus11e_mw_m.crit) > 0:
			all_critical_wound_count += 1
		if weapon_has_devastating_wounds and int(cus11e_mw_m.crit) > 0:
			critical_wound_count += 1
		else:
			regular_wound_count += 1
	# WP-M2a Martial Paragon: re-roll one wound roll (melee).
	var sm11e_mw_m: Dictionary = sm11e_reroll_one_wound(attacker_unit, true, wound_evals, wound_rolls, melee_wound_reroll_data, melee_wound_modifiers, wound_threshold, melee_critical_wound_threshold, rng, melee_wound_mod_ledger)
	if int(sm11e_mw_m.wound) > 0:
		wounds_from_rolls += 1
		if int(sm11e_mw_m.crit) > 0:
			all_critical_wound_count += 1
		if weapon_has_devastating_wounds and int(sm11e_mw_m.crit) > 0:
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
		"modifier_ledger": melee_wound_mod_ledger,
		"wound_modifiers_applied": melee_wound_modifiers
	})

	# Package the wound stage for the composer / staged fight path. wound_context
	# mirrors the ranged wound_context field names so reroll_wound_die works.
	result["wounds_caused"] = wounds_caused
	result["critical_wound_count"] = critical_wound_count
	result["regular_wound_count"] = regular_wound_count
	result["all_critical_wound_count"] = all_critical_wound_count
	result["auto_wounds"] = auto_wounds
	result["wound_rolls"] = wound_rolls
	result["wound_threshold"] = wound_threshold
	result["melee_wound_modifier_net"] = melee_wound_modifier_net
	result["wound_context"] = {
		"is_melee": true,
		"wound_evals": wound_evals,
		"wound_rolls": wound_rolls,
		"wound_modifiers": melee_wound_modifiers,
		"modifier_ledger": melee_wound_mod_ledger,
		"wound_threshold": wound_threshold,
		"critical_wound_threshold": melee_critical_wound_threshold,
		"weapon_has_devastating_wounds": weapon_has_devastating_wounds,
		"weapon_has_precision": hit_context.get("weapon_has_precision", false),
		"auto_wounds": auto_wounds,
		"critical_hits": critical_hits,
		"target_unit_id": target_id,
		"actor_unit_id": attacker_id,
		"weapon_profile": hit_context.get("weapon_profile", {}),
		"melta_data": {},
	}

	if wounds_caused == 0:
		var hit_text = "%d hits" % hits
		if sustained_bonus_hits > 0:
			hit_text += " (+%d sustained)" % sustained_bonus_hits
		result.log_text = "Melee: %s (%s) → %s: %d attacks, %s, 0 wounds" % [attacker_name, weapon_name, target_name, total_attacks, hit_text]
		result.no_wounds = true
		return result

	return result

# Melee saves third: PHASES 6-7 of the original monolith (saving throws, FNP,
# damage application, Hold Still mortal wounds). Takes the hit_context and the
# wounds-third result; returns {diffs, dice, log_text}. Only the auto-resolve
# path reaches this — the interactive path stops before saves.
static func _resolve_melee_assignment_saves(hit_context: Dictionary, w: Dictionary, board: Dictionary, rng: RNGService) -> Dictionary:
	var result = {
		"diffs": [],
		"dice": [],
		"log_text": ""
	}
	var assignment = hit_context["assignment"]
	var actor_unit_id = hit_context["actor_unit_id"]
	var attacker_id = hit_context["attacker_id"]
	var target_id = hit_context["target_id"]
	var weapon_id = hit_context["weapon_id"]
	var weapon_name = hit_context["weapon_name"]
	var weapon_profile = hit_context["weapon_profile"]
	var attacker_name = hit_context["attacker_name"]
	var target_name = hit_context["target_name"]
	var units = board.get("units", {})
	var attacker_unit = units.get(attacker_id, {})
	var target_unit = units.get(target_id, {})
	var ws = hit_context["ws"]
	var ap = hit_context["ap"]
	var damage = hit_context["damage"]
	var base_save = hit_context["base_save"]
	# WP-O6: Codex: Orks (11e) datasheet-ability +D (High-speed Carnage, Brutal Impact)
	var ork6_plus_d := int(hit_context.get("ork11e_ab", {}).get("damage", 0))
	var model_count = int(hit_context["model_count"])
	var total_alive_models = int(hit_context["total_alive_models"])
	var weapon_has_devastating_wounds = hit_context["weapon_has_devastating_wounds"]
	var weapon_has_precision = hit_context["weapon_has_precision"]
	var is_torrent = hit_context["is_torrent"]
	var hits = int(hit_context["hits"])
	var critical_hits = int(hit_context["critical_hits"])
	var sustained_bonus_hits = int(hit_context["sustained_bonus_hits"])
	var total_attacks = int(hit_context["total_attacks"])
	var total_hits_for_wounds = int(hit_context["total_hits_for_wounds"])
	var hit_rolls = hit_context["hit_rolls"]
	var wounds_caused = int(w["wounds_caused"])
	var critical_wound_count = int(w["critical_wound_count"])
	var regular_wound_count = int(w["regular_wound_count"])
	var all_critical_wound_count = int(w["all_critical_wound_count"])
	var auto_wounds = int(w["auto_wounds"])
	var wound_rolls = w["wound_rolls"]
	var wound_threshold = w["wound_threshold"]
	var melee_wound_modifier_net = int(w["melee_wound_modifier_net"])

	# ===== PHASE 6: SAVE ROLLS =====
	# A1 (11e): melee saves/damage via the SAME defender allocation-group path as
	# ranged (05.03-05.04), giving allocation groups, the [DEVASTATING WOUNDS]
	# one-model-per-crit cap (24.10), and 06.02 mortal-wound priority. The 10e
	# melee save/damage below is skipped at edition >= 11. (Interactive defender
	# allocation rides FightController's AllocationGroupOverlay.)
	if GameConstants.edition >= 11:
		var m_damage_raw = weapon_profile.get("damage_raw", str(weapon_profile.get("damage", 1)))
		# Codex: Adeptus Custodes (11e) MEMENTO MORITOI: +1 D on the bearer's melee attacks (WP-C46).
		m_damage_raw = cus11e_damage_raw_plus(str(m_damage_raw), int(cus11e_melee_profile_bonus(board.get("units", {}).get(attacker_id, {})).d))
		var m_alloc = _apply_saves_via_allocation_11e(result, target_unit, target_id,
			regular_wound_count if weapon_has_devastating_wounds else wounds_caused,
			critical_wound_count if weapon_has_devastating_wounds else 0,
			ap, m_damage_raw, rng, {
				"actor_unit": board.get("units", {}).get(actor_unit_id, {}),
				"is_melee": true,  # Codex: Adeptus Custodes (11e) — Flare Shields is vs ranged only (WP-C46)
				"plus_damage": ork6_plus_d,
				"half_damage": get_unit_half_damage(target_unit),
				"fnp_value": get_unit_fnp_vs(target_unit, is_psychic_weapon(weapon_id, board), false),
				"is_psychic": is_psychic_weapon(weapon_id, board),
				"precision_group": _precision_group_11e(weapon_has_precision, target_unit,
					board.get("units", {}).get(actor_unit_id, {}), board,
					str(assignment.get("precision_group_choice", ""))),
				# AI defenders resolved engine-side (no overlay) still pick their
				# casualties smartly; [] for human defenders = engine default.
				"preferred_targets": CasualtyPreference.engine_auto_preference(target_unit, board),
			})
		var m_log := []
		m_log.append("Melee: %s (%s) → %s" % [attacker_name, weapon_name, target_name])
		m_log.append("Hit: %d/%d" % [hits, total_attacks])
		m_log.append("Wound: %d/%d" % [wounds_caused, total_hits_for_wounds])
		if weapon_has_devastating_wounds and critical_wound_count > 0:
			m_log.append("%d DEVASTATING" % critical_wound_count)
		m_log.append("%d slain" % m_alloc.casualties)
		result.log_text = " - ".join(m_log)
		return result

	# Devastating Wounds: Critical wounds (unmodified 6s to wound) bypass saves entirely
	var wounds_needing_saves = regular_wound_count if weapon_has_devastating_wounds else wounds_caused
	var devastating_wound_count = critical_wound_count if weapon_has_devastating_wounds else 0
	var devastating_damage = devastating_wound_count * damage

	var failed_saves = 0
	var successful_saves = 0
	var save_rolls = []
	var save_threshold = 7  # Default: impossible to save

	# T4-18: Read save roll modifier from target unit flags (capped at +1/-1 per 10e)
	var melee_save_modifier = int(target_unit.get("flags", {}).get("save_modifier", 0)) + int(_sm11e_abilities_b().save_roll_bonus(target_unit))  # WP-M4b: Unyielding in the Face of the Foe
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
	var damage_roll_log = []

	# HALF DAMAGE (T4-17): Check if target unit has half-damage defensive ability
	var melee_has_half_damage = get_unit_half_damage(target_unit)
	if melee_has_half_damage:
		print("RulesEngine: Half Damage active on melee defender — all damage characteristics halved (round up)")

	# WP-O6: flat +D from Codex: Orks (11e) datasheet abilities (replaces the
	# pre-codex Da Bigger Dey iz... +D, which the codex changed to a wound re-roll)
	var da_bigger_bonus = ork6_plus_d
	if da_bigger_bonus > 0:
		print("RulesEngine: [WP-O6] +%d damage per attack for %s (Codex: Orks 11e datasheet abilities)" % [da_bigger_bonus, attacker_name])

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
	var fnp_value = get_unit_fnp_vs(target_unit, melee_is_psychic, false)
	var dw_fnp_value = get_unit_fnp_vs(target_unit, melee_is_psychic, true)
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
		log_parts.append("+%d dmg (datasheet ability)" % da_bigger_bonus)

	# Save result
	log_parts.append("Save: %d/%d failed" % [total_unsaved, wounds_caused])

	log_parts.append("%d slain" % damage_result.casualties)

	if fnp_value > 0:
		var prevented = total_damage - actual_damage
		if prevented > 0:
			log_parts.append("FNP %d+ prevented %d" % [fnp_value, prevented])

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

	# MA-LOADOUT Phase 1b (Task D): resolve per-model melee loadouts (once) so a
	# model reports the melee weapon(s) it actually fights with rather than every
	# datasheet option. Idempotent — a no-op once the unit is resolved.
	_ensure_loadout_resolved(unit)

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

		# Prefer the resolved per-model melee loadout when present (the weapons the
		# model actually fights with); else fall back to the profile menu, else all.
		var resolved_melee = model.get("melee_loadout", null)
		var model_type = model.get("model_type", "")
		if resolved_melee is Array:
			for weapon in weapons_data:
				if weapon.get("type", "").to_lower() == "melee" and weapon.get("name", "") in resolved_melee:
					var wname = weapon.get("name", "Unknown Weapon")
					if wname not in model_weapons:
						model_weapons.append(wname)
		elif not model_profiles.is_empty() and model_type != "" and model_profiles.has(model_type):
			# Per-model profile branch: only melee weapons listed in this model's profile
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
		# Enhancement-granted melee weapons (granted_by, e.g. Codex: Adeptus
		# Custodes Emperor's Light — WP-C46) are always carried by the bearer.
		for weapon in weapons_data:
			if weapon.get("type", "").to_lower() == "melee" and str(weapon.get("granted_by", "")) != "":
				var gname = weapon.get("name", "Unknown Weapon")
				if gname not in model_weapons:
					model_weapons.append(gname)

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
	var shooter_unit = units.get(shooter_unit_id, {})
	# WP-O6: Codex: Orks (11e) datasheet-ability AP (Pulsa Rokkit, Finderz Keeperz) — unit-level sources
	var int_ork6: Dictionary = ork11e_ab_mods(shooter_unit, target_unit, weapon_profile, false, board)
	if int(int_ork6.get("ap", 0)) > 0:
		var pre_ap_o6 = ap
		ap = improve_ap(ap, int(int_ork6.get("ap", 0)))
		print("RulesEngine: [WP-O6] (interactive) AP %d → %d" % [pre_ap_o6, ap])
	# IMPROVE AP: effect-granted AP improvement (Umbral Prosecution ranged AP +1 etc.)
	var int_improve_ap = EffectPrimitivesData.get_effect_improve_ap_scoped(shooter_unit, "ranged")
	if int_improve_ap > 0:
		var pre_ap_imp = ap
		ap = improve_ap(ap, int_improve_ap)
		print("RulesEngine: Improve AP (interactive) — AP %d → %d (improve by %d)" % [pre_ap_imp, ap, int_improve_ap])
	# SPESHUL SHELLS (More Dakka!): +1 AP vs targets within 18"
	var int_ss_bonus = get_speshul_shells_ap_bonus(shooter_unit, target_unit)
	if int_ss_bonus > 0:
		ap = improve_ap(ap, int_ss_bonus)
		print("RulesEngine: SPESHUL SHELLS (interactive) — AP improved by %d (target within 18\")" % int_ss_bonus)
	# PREY (Da Big Hunt): +1 AP for BEAST SNAGGA attacks against the attacker's Prey
	var int_prey_bonus = get_prey_ap_bonus(shooter_unit, target_unit)
	if int_prey_bonus > 0:
		ap = improve_ap(ap, int_prey_bonus)
		print("RulesEngine: PREY (interactive) — AP improved by %d (target is Prey)" % int_prey_bonus)
	# TRY DAT BUTTON! (Dread Mob, 5-6): +2 AP (40kdc flatten of the Critical Wound rider)
	if shooter_unit.get("flags", {}).get("effect_try_dat_ap2", false):
		ap = improve_ap(ap, 2)
		print("RulesEngine: TRY DAT BUTTON! (interactive) — AP improved by 2")	# WORSEN AP: Ramshackle etc. — reduce AP of incoming attacks (min 0)
	# GLOWIN' DAKKA (Codex: Orks 11e): +1 AP vs a target within 9"
	var int_glowin_ap = ork11e_glowin_dakka_ap_bonus(shooter_unit, target_unit, board)
	if int_glowin_ap > 0:
		ap = ork11e_improve_ap(ap, int_glowin_ap)
		print("RulesEngine: GLOWIN' DAKKA (interactive) — AP improved by %d (target within 9\")" % int_glowin_ap)
	# Codex: Adeptus Custodes stratagems (CustodesCodex11e.gd): PSY-CHAFF VOLLEY +1 AP vs a prosecuted unit, IN AURAMITE CLAD -1 AP.
	ap = _cus11e_codex().modify_ap(ap, shooter_unit, target_unit)
	# Codex: Space Marines (11e) stratagems (SMCodex11e.gd): ARMOUR OF CONTEMPT -1 AP to attacks that target the unit.
	ap = _sm11e_codex().modify_ap(ap, shooter_unit, target_unit)
	var int_worsen_ap = EffectPrimitivesData.get_effect_worsen_ap(target_unit)
	if int_worsen_ap > 0 and ap != 0:
		var pre_ap = ap
		ap = worsen_ap(ap, int_worsen_ap)
		print("RulesEngine: Worsen AP (interactive) — AP %d → %d (worsen by %d)" % [pre_ap, ap, int_worsen_ap])
	var damage = weapon_profile.get("damage", 1)
	var base_save = target_unit.get("meta", {}).get("stats", {}).get("save", 7)

	var damage_raw = weapon_profile.get("damage_raw", str(damage))
	damage_raw = cus11e_damage_raw_plus(str(damage_raw), int(load("res://scripts/codex/space_marines/SMDetachmentsB.gd").ranged_damage_bonus(shooter_unit, weapon_profile)))  # WP-M2b Master-forged Firearms +1 D (Codex: Space Marines 11e)

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
	# Codex: Orks (11e) Unpredictable Genius — Dat's Weird (WP-O34): 4+ InSv against this shooter.
	var ork11e_inv = ork11e_det_invuln(board.get("units", {}).get(shooter_unit_id, {}), target_unit, effect_invuln)
	if ork11e_inv != effect_invuln:
		effect_invuln = ork11e_inv
		effect_invuln_source = "Unpredictable Genius — Dat's Weird"
	# Codex: Adeptus Custodes (11e) Flare Shields 4+ vs ranged / Eagle's Eye 3+ (WP-C46).
	var cus11e_inv := cus11e_invuln(target_unit, false, effect_invuln, board)
	if cus11e_inv != effect_invuln:
		effect_invuln = cus11e_inv
		effect_invuln_source = "Codex: Adeptus Custodes"

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
			# 11e (10.07/13.08): indirect cover is applied on the HIT side
			# (BS worsening in the resolve loop) — the save grant is 10e.
			if weapon_is_indirect_fire and GameConstants.edition < 11 and not _has_los_to_target_unit(shooter_unit_id, target_unit_id, board):
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
	# (local named mi_worsen_ap so it does not shadow the static worsen_ap())
	var mi_worsen_ap = EffectPrimitivesData.get_effect_worsen_ap(target_unit)
	if mi_worsen_ap > 0 and ap != 0:
		var pre_ap = ap
		ap = worsen_ap(ap, mi_worsen_ap)
		print("RulesEngine: Worsen AP (melee interactive) — AP %d → %d (worsen by %d)" % [pre_ap, ap, mi_worsen_ap])

	var attacker_unit = units.get(attacker_unit_id, {})
	# PREY (Da Big Hunt): +1 AP for BEAST SNAGGA attacks against the attacker's Prey
	var mi_prey_bonus = get_prey_ap_bonus(attacker_unit, target_unit)
	if mi_prey_bonus > 0:
		ap = improve_ap(ap, mi_prey_bonus)
		print("RulesEngine: PREY (melee interactive) — AP improved by %d (target is Prey)" % mi_prey_bonus)
	# TRY DAT BUTTON! (Dread Mob, 5-6): +2 AP (40kdc flatten of the Critical Wound rider)
	if attacker_unit.get("flags", {}).get("effect_try_dat_ap2", false):
		ap = improve_ap(ap, 2)
		print("RulesEngine: TRY DAT BUTTON! (melee interactive) — AP improved by 2")

	# IMPROVE AP: effect-granted AP improvement (melee scope)
	var mi_improve_ap = EffectPrimitivesData.get_effect_improve_ap_scoped(attacker_unit, "melee")
	if mi_improve_ap > 0:
		var pre_ap_imp = ap
		ap = improve_ap(ap, mi_improve_ap)
		print("RulesEngine: Improve AP (melee interactive) — AP %d → %d (improve by %d)" % [pre_ap_imp, ap, mi_improve_ap])

	# WP-O6: Codex: Orks (11e) datasheet-ability AP (melee interactive)
	var mi_ork6_ap := int(ork11e_ab_mods(attacker_unit, target_unit, weapon_profile, true, board).get("ap", 0))
	if mi_ork6_ap > 0:
		ap = improve_ap(ap, mi_ork6_ap)
		print("RulesEngine: [WP-O6] (melee interactive) AP improved by %d → %d" % [mi_ork6_ap, ap])
	# Codex: Adeptus Custodes stratagems (CustodesCodex11e.gd): PSY-CHAFF VOLLEY +1 AP vs a prosecuted unit, IN AURAMITE CLAD -1 AP.
	ap = _cus11e_codex().modify_ap(ap, attacker_unit, target_unit)
	# Codex: Space Marines (11e) stratagems (SMCodex11e.gd): ARMOUR OF CONTEMPT -1 AP to attacks that target the unit.
	ap = _sm11e_codex().modify_ap(ap, attacker_unit, target_unit)

	var damage = weapon_profile.get("damage", 1)

	# Codex: Adeptus Custodes (11e) MEMENTO MORITOI: +1 D on the bearer's melee attacks (WP-C46).
	var cus11e_mi_d := int(cus11e_melee_profile_bonus(attacker_unit).d)
	if cus11e_mi_d > 0:
		damage += cus11e_mi_d

	var base_save = target_unit.get("meta", {}).get("stats", {}).get("save", 7)
	var damage_raw = weapon_profile.get("damage_raw", str(damage))
	damage_raw = cus11e_damage_raw_plus(str(damage_raw), cus11e_mi_d)  # Codex: Adeptus Custodes (11e) Memento Moritoi +1 D (WP-C46)

	# Get model allocation requirements (prioritize wounded models)
	var allocation_info = _get_save_allocation_requirements(target_unit, attacker_unit_id, board)

	# Effect-granted invuln (e.g., Waaagh! 5+)
	var effect_invuln = EffectPrimitivesData.get_effect_invuln(target_unit)
	var effect_invuln_source = EffectPrimitivesData.get_effect_invuln_source(target_unit)
	# Codex: Adeptus Custodes (11e) Eagle's Eye 3+ (WP-C46).
	var cus11e_minv := cus11e_invuln(target_unit, true, effect_invuln, board)
	if cus11e_minv != effect_invuln:
		effect_invuln = cus11e_minv
		effect_invuln_source = "Codex: Adeptus Custodes"
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

	# WP-O6: flat +D from Codex: Orks (11e) datasheet abilities (High-speed Carnage, Brutal Impact)
	var mi_ork6: Dictionary = ork11e_ab_mods(attacker_unit, target_unit, weapon_profile, true, board)
	var da_bigger_bonus = int(mi_ork6.get("damage", 0))
	if da_bigger_bonus > 0:
		print("RulesEngine: [WP-O6] (melee interactive) +%d damage per attack for %s" % [da_bigger_bonus, attacker_unit.get("meta", {}).get("name", attacker_unit_id)])

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
	var fnp_value = get_unit_fnp_vs(target_unit, ranged_is_psychic, false)

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
		var dw_fnp_value = get_unit_fnp_vs(target_unit, ranged_is_psychic, true)
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
		var model_fnp_value = get_model_fnp_vs(target_unit, model, ranged_is_psychic, false)
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
static func _apply_damage_to_unit_pool(target_unit_id: String, total_damage: int, models: Array, board: Dictionary, preferred: Array = []) -> Dictionary:
	"""Apply damage to unit, distributing across models following 10e rules"""
	var result = {
		"diffs": [],
		"casualties": 0,
		"damage_applied": 0
	}

	var remaining_damage = total_damage

	# Apply damage following allocation rules: wounded models first, then any model
	while remaining_damage > 0:
		# Find next model to apply damage to (wounded first, then preferred/any alive)
		var target_model_index = _find_allocation_target_model(models, preferred)
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

# 05.04.05 Fight On Death (Codex: Orks 11e ORKS IS NEVER BEATEN / TOO
# ARROGANT TO DIE / CRAZED RAMPAGE): a model that was destroyed but is "not
# removed from the battlefield" until its unit has fought stays alive=true with
# 0 wounds left (FightPhase._ork11e_fod_intercept). It is still destroyed, so
# no further attack or mortal wound can be allocated to it.
static func model_can_be_allocated(model: Dictionary) -> bool:
	if not model.get("alive", true):
		return false
	return int(model.get("current_wounds", model.get("wounds", 1))) > 0

# DEVASTATING WOUNDS (PRP-012): Find model to allocate damage to (wounded first)
static func _find_allocation_target_model(models: Array, preferred: Array = []) -> int:
	"""Find next model to allocate damage to: wounded models first, then any alive.
	`preferred` (optional) is a die-first order of model indices from
	CasualtyPreference — it only picks WHICH un-wounded model soaks next
	(the 05.04 wounded-first rule always wins). Destroyed-but-not-removed
	models (0 wounds, see model_can_be_allocated) are never picked."""
	# First, look for wounded alive models
	for i in range(models.size()):
		var model = models[i]
		if model_can_be_allocated(model):
			var current = model.get("current_wounds", model.get("wounds", 1))
			var max_wounds = model.get("wounds", 1)
			if current < max_wounds:
				return i  # Return first wounded model

	# No wounded models — honour the defender's die-first preference
	for p in preferred:
		var pi = int(p)
		if pi >= 0 and pi < models.size() and model_can_be_allocated(models[pi]):
			return pi

	# No preference (or preference exhausted), return first alive model
	for i in range(models.size()):
		if model_can_be_allocated(models[i]):
			return i

	return -1  # No alive models

# FEEL NO PAIN: Get FNP value for a unit (0 = no FNP)
static func get_unit_fnp(unit: Dictionary) -> int:
	"""Returns FNP value (e.g. 5 for 5+), or 0 if unit has no FNP.
	Checks both base stats and effect-granted FNP, using the better (lower) value.
	Note: this returns the UNCONDITIONAL FNP only — for psychic/mortal-only FNP
	(e.g. Daughters of the Abyss) call get_unit_fnp_for_attack(unit, true)."""
	var base_fnp = unit.get("meta", {}).get("stats", {}).get("fnp", 0)
	# WP-S4 (found verifying the Space Wolves core abilities): the core
	# "Feel No Pain X+" datasheet ability — the 11e army data carries it only
	# as an ability NAME (Ulrik, Bjorn, Murderfang, Trajann, Beastboss ...),
	# never as stats.fnp, so it was never applied. Parsed like Lone Operative X".
	var named_fnp := get_named_fnp(unit)
	if named_fnp > 0 and (int(base_fnp) <= 0 or named_fnp < int(base_fnp)):
		base_fnp = named_fnp
	var effect_fnp = EffectPrimitivesData.get_effect_fnp(unit)
	# Codex: Adeptus Custodes (11e) Genalchemic Warding / Augury Uplink: the bearer has FNP 5+ (WP-C46).
	if GameConstants.edition >= 11:
		effect_fnp = _better_fnp(effect_fnp, int(cus11e_det().unit_fnp(unit)))
		effect_fnp = _better_fnp(effect_fnp, int(SMAbilitiesC11eScript.unit_fnp(unit)))  # WP-M4c: Seeker of the Unfound / Veteran Bodyguard (FNP 4+)

	# Use the better (lower) FNP if both exist, otherwise whichever is non-zero
	if base_fnp > 0 and effect_fnp > 0:
		return min(base_fnp, effect_fnp)
	elif effect_fnp > 0:
		return effect_fnp
	elif base_fnp > 0:
		return base_fnp
	return 0

# T-016 (compatibility wrapper): FNP for a psychic attack and/or mortal wound
# when the caller cannot tell the two apart. New code calls get_unit_fnp_vs
# with explicit flags (WP-C3: Aegis of the Emperor is vs mortal wounds only,
# Daughters of the Abyss / Psychic Null vs psychic attacks only).
static func get_unit_fnp_for_attack(unit: Dictionary, is_psychic_or_mortal_wound: bool) -> int:
	return get_unit_fnp_vs(unit, is_psychic_or_mortal_wound, is_psychic_or_mortal_wound)

## The best Feel No Pain that applies to one wound loss — never cumulative:
## the unconditional FNP (stats / effect) and every conditional grant for the
## attack's kind. is_psychic: a psychic attack (24.29); is_mortal: a mortal
## wound (06.02 — devastating wounds, hazards, Deadly Demise, stratagems …).
static func get_unit_fnp_vs(unit: Dictionary, is_psychic: bool, is_mortal: bool) -> int:
	return _better_fnp(get_unit_fnp(unit), _conditional_fnp(unit, is_psychic, is_mortal))

## Per-model variant (MA-28 stats_override.fnp) of get_unit_fnp_vs.
static func get_model_fnp_vs(unit: Dictionary, model: Dictionary, is_psychic: bool, is_mortal: bool) -> int:
	return _better_fnp(get_model_fnp(unit, model), _conditional_fnp(unit, is_psychic, is_mortal))

## Only the conditional FNP grants (0 = none): the T-016 psychic-or-mortal
## flag, plus the Codex: Adeptus Custodes army rules (CustodesKatah.fnp_vs:
## Aegis of the Emperor vs mortal wounds, Daughters of the Abyss / Psychic
## Null vs psychic attacks). (The 10e Talons of the Emperor Null Aegis aura is
## gone with that detachment — WP-C46.)
static func _conditional_fnp(unit: Dictionary, is_psychic: bool, is_mortal: bool) -> int:
	if not is_psychic and not is_mortal:
		return 0
	var best := int(EffectPrimitivesData.get_effect_fnp_psychic_mortal(unit))
	# Codex: Adeptus Custodes army rules (CustodesKatah.gd)
	best = _better_fnp(best, int(_cus11e_katah().fnp_vs(unit, is_psychic, is_mortal)))
	# Codex: Space Marines (11e) Space Wolves WOLF TOTEMS (SWCodex11e.gd): Feel No Pain 5+ against mortal wounds.
	if is_mortal:
		best = _better_fnp(best, int(_sw11e_codex().fnp_vs_mortal(unit)))
		# Codex: Space Marines (11e) LAYERED CERAMITE (SMCodex11e.gd): Feel No Pain 5+ against mortal wounds.
		best = _better_fnp(best, int(_sm11e_codex().fnp_vs_mortal(unit)))
	best = _better_fnp(best, int(_sm11e_abilities_b().conditional_fnp(unit, is_psychic, is_mortal)))  # WP-M4b: Hood of Hellfire / Psychic Hood (FNP 4+)
	# WP-M4a: Psychic Hood (FNP 4+ vs psychic attacks) / Zealous Fortitude (FNP 4+ vs mortal wounds).
	best = _better_fnp(best, int(SMAbilitiesAScript.fnp_vs(unit, is_psychic, is_mortal)))
	return best

static func _better_fnp(a: int, b: int) -> int:
	if a <= 0:
		return b
	if b <= 0:
		return a
	return mini(a, b)

## Codex: Adeptus Custodes army rules module (loaded lazily — no preload
## cascade into the autoload's compile).
static func _cus11e_katah():
	return load("res://scripts/codex/custodes/CustodesKatah.gd")

## Codex: Adeptus Custodes stratagems (WP-C5) — the effect consumers the
## one-line hooks in this file call (loaded lazily, like _cus11e_katah).
static func _cus11e_codex():
	return load("res://scripts/codex/custodes/CustodesCodex11e.gd")

## Codex: Space Marines (11e) Space Wolves stratagems (WP-S3) — the effect
## consumers of the one-line "SWCodex11e.gd" hooks in this file (loaded lazily).
static func _sw11e_codex():
	return load("res://scripts/codex/space_wolves/SWCodex11e.gd")

## Codex: Space Marines (11e) generic detachment stratagems (WP-M3a) — the effect
## consumers of the one-line "SMCodex11e.gd" hooks in this file (loaded lazily).
static func _sm11e_codex():
	return load("res://scripts/codex/space_marines/SMCodex11e.gd")

## Mortal wounds that survive Feel No Pain, for the mortal-wound paths that
## allocate through Allocation.apply_mortal_wounds_11e (explosives, crushing
## impact, hazards, emergency disembarks, …): rolls the best FNP vs a mortal
## wound (get_unit_fnp_vs) once per wound. Appends a feel_no_pain dice block
## to `dice` when FNP is rolled. Returns the wounds left to allocate.
static func mortal_wounds_after_fnp(unit: Dictionary, mortal_wounds: int, rng: RNGService, dice: Array = [], is_psychic: bool = false, source: String = "mortal_wounds") -> int:
	if mortal_wounds <= 0 or unit.is_empty():
		return mortal_wounds
	var fnp := get_unit_fnp_vs(unit, is_psychic, true)
	if fnp <= 0:
		return mortal_wounds
	if rng == null:
		rng = make_rng()
	var fr = roll_feel_no_pain(mortal_wounds, fnp, rng)
	dice.append({"context": "feel_no_pain", "source": source, "rolls": fr.rolls, "fnp_value": fnp,
		"wounds_prevented": fr.wounds_prevented, "wounds_remaining": fr.wounds_remaining, "total_wounds": mortal_wounds})
	print("RulesEngine: %s vs %s — Feel No Pain %d+ prevented %d of %d mortal wound(s)" % [source, str(unit.get("id", "?")), fnp, int(fr.wounds_prevented), mortal_wounds])
	return int(fr.wounds_remaining)

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
	var fnp_value = get_unit_fnp_vs(target_unit, false, true)
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

	# Apply damage using the standard pool method (wounded models first);
	# when the computer allocates for this defender, its die-first order
	# decides which fresh model soaks next instead of lowest-index.
	var mw_preferred = CasualtyPreference.engine_auto_preference(target_unit, board)
	var damage_result = _apply_damage_to_unit_pool(target_unit_id, actual_wounds, models, board, mw_preferred)

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
			# Feel No Pain dice vs these mortal wounds (e.g. Aegis of the Emperor).
			target_result["fnp_rolls"] = mw_result.get("fnp_rolls", [])
			target_result["wounds_applied"] = int(mw_result.get("wounds_applied", 0))
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

static func unit_has_enhancement(unit: Dictionary, enhancement_name: String) -> bool:
	"""True if the unit's meta.enhancements list carries the named enhancement
	(entries may be plain strings or {name: ...} dictionaries)."""
	for enh in unit.get("meta", {}).get("enhancements", []):
		var enh_name = enh if enh is String else (enh.get("name", "") if enh is Dictionary else "")
		if enh_name == enhancement_name:
			return true
	return false

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
	var to_place: Array = []  # [{unit_id, unit_name, model_indices, result_index}] — placed after all hazard rolls

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

		# A7: emergency disembark hazard rolls. 11e (18.05/06.03): a roll of 1-2
		# fails → 1 mortal wound (3 if every model in the unit is MONSTER/VEHICLE).
		# 10e: only a roll of 1 → 1 MW.
		var haz_fail_threshold: int = 2 if GameConstants.edition >= 11 else 1
		var haz_mw_per_fail: int = 1
		if GameConstants.edition >= 11 and is_monster_or_vehicle(embarked_unit):
			haz_mw_per_fail = 3
		var unit_mortal_wounds = 0
		for roll in rolls:
			if roll <= haz_fail_threshold:
				unit_mortal_wounds += haz_mw_per_fail

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

		# 18.05 WHILE MOVING: models are set up after the hazard rolls — note
		# which models those mortal wounds destroyed (the diffs are not applied
		# to `board` here) so only survivors are placed.
		var hazard_dead: Dictionary = {}
		for d in unit_result["diffs"]:
			var dp = str(d.get("path", "")).split(".")
			if dp.size() == 5 and dp[0] == "units" and dp[1] == embarked_id and dp[2] == "models" \
					and dp[4] == "alive" and d.get("value") == false:
				hazard_dead[int(dp[3])] = true
		var survivors: Array = []
		for i in range(models.size()):
			if models[i].get("alive", true) and not hazard_dead.has(i):
				survivors.append(i)
		to_place.append({"unit_id": embarked_id, "unit_name": unit_name, "model_indices": survivors,
			"result_index": per_unit.size()})

		all_diffs.append_array(unit_result["diffs"])
		per_unit.append(unit_result)

	# 18.05 WHILE MOVING: set up every surviving model wholly within 6" of
	# the destroyed TRANSPORT and as close as possible to it, as a legal set
	# up (03.02: on the battlefield, not overlapping models or terrain it
	# cannot stand in, unengaged, in coherency). "Each model that cannot be set
	# up in this way is destroyed."
	var placement = _emergency_disembark_placements(transport, to_place, board)
	for entry in to_place:
		var uid: String = entry.unit_id
		var ur: Dictionary = per_unit[int(entry.result_index)]
		var placed: Dictionary = placement.placed.get(uid, {})
		var unplaced: Array = placement.destroyed.get(uid, [])
		for mi in placed:
			var pos: Vector2 = placed[mi]
			ur["diffs"].append({"op": "set", "path": "units.%s.models.%d.position" % [uid, int(mi)],
				"value": {"x": pos.x, "y": pos.y}})
			all_diffs.append(ur["diffs"][-1])
		for mi in unplaced:
			for d in [{"op": "set", "path": "units.%s.models.%d.current_wounds" % [uid, int(mi)], "value": 0},
					{"op": "set", "path": "units.%s.models.%d.alive" % [uid, int(mi)], "value": false}]:
				ur["diffs"].append(d)
				all_diffs.append(d)
		ur["models_placed"] = placed.size()
		ur["models_unplaceable"] = unplaced.size()
		ur["models_destroyed"] = int(ur.get("models_destroyed", 0)) + unplaced.size()
		total_models_destroyed += unplaced.size()
		print("║   %s: %d model(s) set up within 6\" (nearest first), %d could not be set up legally and are destroyed (18.05)" % [
			entry.unit_name, placed.size(), unplaced.size()])

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

# 18.05 emergency disembark placement. Pure (does not mutate `board`).
# `to_place`: [{unit_id, model_indices}] in the order to set up. Returns
# {placed: {unit_id: {model_index: Vector2}}, destroyed: {unit_id: [model_index]},
#  rejected: {reason: count}} where `rejected` tallies why candidate spots
# were illegal (for the log / tests).
#
# Search: candidate centres on a 0.5" grid around the transport, filtered per
# base size by the static set-up rules — wholly within 6" of the transport
# hull, not overlapping the transport or any other model, on the battlefield,
# not overlapping walls / dense terrain the unit cannot stand in, and outside
# engagement range of every enemy model (03.02 "unengaged") — then sorted
# nearest-first (edge-to-edge distance to the transport; ties broken by y, x
# so the result is deterministic). Each model takes the nearest remaining
# candidate that does not overlap a model already placed by this disembark and
# keeps its unit in coherency (03.03); a model with no such spot is destroyed.
const EMERGENCY_DISEMBARK_GRID_INCHES := 0.5

static func _emergency_disembark_placements(transport: Dictionary, to_place: Array, board: Dictionary) -> Dictionary:
	var out = {"placed": {}, "destroyed": {}, "rejected": {}}
	var units: Dictionary = board.get("units", {})
	var transport_model: Dictionary = {}
	for tm in transport.get("models", []):
		if tm.get("position", null) != null:
			transport_model = tm.duplicate()
			break
	if transport_model.is_empty():
		# No footprint to measure from — nothing can be set up within 6".
		for entry in to_place:
			out.destroyed[entry.unit_id] = entry.model_indices.duplicate()
		return out
	transport_model["alive"] = true  # its footprint still blocks set up
	var t_pos: Vector2 = _get_model_position(transport_model)
	var t_extent: float = Measurement.base_extent_px(transport_model)
	var setup_px: float = Measurement.inches_to_px(6.0)
	var er_px: float = Measurement.inches_to_px(GameConstants.engagement_range_inches())
	var owner := int(transport.get("owner", 0))

	# Units whose models are being set up must not block themselves (embarked
	# models can carry stale positions).
	var placing_ids: Dictionary = {}
	for entry in to_place:
		placing_ids[entry.unit_id] = true
	# Other on-table models near the transport (cheap centre-distance prefilter).
	var reach: float = t_extent + setup_px + er_px + Measurement.inches_to_px(4.0)
	var blockers: Array = []  # [{model, enemy: bool, extent}]
	for uid in units:
		if placing_ids.has(uid) or uid == str(transport.get("id", "")):
			continue
		var u = units[uid]
		if u.get("embarked_in", null) != null:
			continue
		# Off-table units (undeployed / in strategic reserves) can carry stale
		# positions — they occupy no ground.
		if int(u.get("status", GameStateData.UnitStatus.DEPLOYED)) in [GameStateData.UnitStatus.UNDEPLOYED,
				GameStateData.UnitStatus.DEPLOYING, GameStateData.UnitStatus.IN_RESERVES]:
			continue
		for m in u.get("models", []):
			if not m.get("alive", true) or m.get("position", null) == null:
				continue
			var mp: Vector2 = _get_model_position(m)
			if mp.distance_to(t_pos) > reach:
				continue
			blockers.append({"model": m, "enemy": int(u.get("owner", 0)) != owner, "extent": Measurement.base_extent_px(m)})

	var grid_px: float = Measurement.inches_to_px(EMERGENCY_DISEMBARK_GRID_INCHES)
	var span: float = t_extent + setup_px
	var steps: int = int(ceil(span / grid_px))
	var candidates_by_sig: Dictionary = {}
	var placed_models: Array = []  # [{model, group}] models set up by this disembark
	var group_members: Dictionary = {}  # coherency group -> [model dicts]

	for entry in to_place:
		var uid: String = entry.unit_id
		var unit: Dictionary = units.get(uid, {})
		var keywords: Array = unit.get("meta", {}).get("keywords", [])
		var group_id: String = attached_unit_target_id(uid, board)
		out.placed[uid] = {}
		out.destroyed[uid] = []
		for mi in entry.model_indices:
			var model: Dictionary = unit.get("models", [])[int(mi)]
			var sig := "%s|%s|%s|%s|%s" % [str(model.get("base_type", "circular")), str(model.get("base_mm", 32)),
				str(model.get("base_dimensions", {})), str(model.get("rotation", 0.0)), ",".join(PackedStringArray(keywords))]
			if not candidates_by_sig.has(sig):
				candidates_by_sig[sig] = _emergency_disembark_candidates(model, keywords, transport_model, t_pos,
					setup_px, steps, grid_px, blockers, out.rejected)
			var chosen = null
			for cand in candidates_by_sig[sig]:
				var test_model: Dictionary = model.duplicate()
				test_model["position"] = cand.pos
				test_model["alive"] = true
				var clash := false
				for pm in placed_models:
					if Measurement.models_overlap(test_model, pm):
						clash = true
						break
				if clash:
					out.rejected["overlaps a disembarking model"] = int(out.rejected.get("overlaps a disembarking model", 0)) + 1
					continue
				var members: Array = group_members.get(group_id, [])
				if not members.is_empty():
					var near_one := false
					var within_nine := true
					for other in members:
						var d_in: float = Measurement.model_to_model_distance_inches(test_model, other)
						if d_in <= 2.0 + 0.01:
							near_one = true
						if d_in > 9.0 + 0.01:
							within_nine = false
					if not near_one or not within_nine:
						out.rejected["breaks coherency"] = int(out.rejected.get("breaks coherency", 0)) + 1
						continue
				chosen = test_model
				break
			if chosen == null:
				out.destroyed[uid].append(int(mi))
				continue
			out.placed[uid][int(mi)] = _get_model_position(chosen)
			placed_models.append(chosen)
			if not group_members.has(group_id):
				group_members[group_id] = []
			group_members[group_id].append(chosen)
	return out

# Statically legal set-up spots for one base size, nearest-first (see above).
static func _emergency_disembark_candidates(model: Dictionary, keywords: Array, transport_model: Dictionary, t_pos: Vector2, setup_px: float, steps: int, grid_px: float, blockers: Array, rejected: Dictionary) -> Array:
	var cands: Array = []
	var extent: float = Measurement.base_extent_px(model)
	var er_px: float = Measurement.inches_to_px(GameConstants.engagement_range_inches())
	for gy in range(-steps, steps + 1):
		for gx in range(-steps, steps + 1):
			var pos := t_pos + Vector2(gx * grid_px, gy * grid_px)
			var test_model: Dictionary = model.duplicate()
			test_model["position"] = pos
			test_model["alive"] = true
			# Wholly within 6" of the TRANSPORT: the farthest point of this
			# base is within 6" of the transport hull.
			if Measurement.model_edge_to_point_distance_px(transport_model, pos) + extent > setup_px + 0.5:
				rejected["not wholly within 6\""] = int(rejected.get("not wholly within 6\"", 0)) + 1
				continue
			if Measurement.models_overlap(test_model, transport_model):
				rejected["overlaps the transport"] = int(rejected.get("overlaps the transport", 0)) + 1
				continue
			if Measurement.model_outside_board(pos, test_model):
				rejected["off the battlefield"] = int(rejected.get("off the battlefield", 0)) + 1
				continue
			if Measurement.model_overlaps_any_wall(test_model, keywords):
				rejected["terrain"] = int(rejected.get("terrain", 0)) + 1
				continue
			var illegal := ""
			for b in blockers:
				var bp: Vector2 = _get_model_position(b.model)
				var centre: float = bp.distance_to(pos)
				if centre > extent + float(b.extent) + er_px + 1.0:
					continue
				if Measurement.models_overlap(test_model, b.model):
					illegal = "overlaps a model"
					break
				if b.enemy and Measurement.is_in_engagement_range_shape_aware(test_model, b.model):
					illegal = "within engagement range of an enemy"
					break
			if illegal != "":
				rejected[illegal] = int(rejected.get(illegal, 0)) + 1
				continue
			cands.append({"pos": pos, "dist": Measurement.model_to_model_distance_px(test_model, transport_model)})
	cands.sort_custom(func(a, b):
		if not is_equal_approx(a.dist, b.dist):
			return a.dist < b.dist
		if not is_equal_approx(a.pos.y, b.pos.y):
			return a.pos.y < b.pos.y
		return a.pos.x < b.pos.x)
	return cands

# ==========================================
# DREAD FOE (P1-17)
# ==========================================


# ==========================================
# PISTON-DRIVEN BRUTALITY (OA-36)
# ==========================================


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

		# Skip attached characters — the Attached unit is one unit (19.02);
		# GRENADE must target the bodyguard unit, same as any ranged attack.
		if target_unit.get("attached_to", null) != null:
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

## Expected value of a characteristic string: "1", "3", "D6", "2D3", "D6+1".
## Used wherever a weapon has to be RANKED without rolling — the attack-dialog's
## forecast rows and FightPhase's "which weapon does this model swing when
## nobody chose for it" both read it, so their answers agree.
static func average_dice_notation(s: String) -> float:
	s = s.strip_edges().to_upper().replace(" ", "")
	if s.is_empty():
		return 1.0
	if s.is_valid_int():
		return float(int(s))
	var plus_idx = s.find("+")
	var bonus: float = 0.0
	if plus_idx >= 0:
		var after = s.substr(plus_idx + 1)
		if after.is_valid_int():
			bonus = float(int(after))
		s = s.substr(0, plus_idx)
	var d_idx = s.find("D")
	if d_idx < 0:
		return 1.0 + bonus
	var n_str = s.substr(0, d_idx)
	var x_str = s.substr(d_idx + 1)
	var n: int = int(n_str) if n_str.is_valid_int() else 1
	var x: int = int(x_str) if x_str.is_valid_int() else 6
	# Average of one die of size x is (x+1)/2.
	return float(n) * (float(x) + 1.0) / 2.0 + bonus

## MA-LOADOUT: force per-model loadout resolution (ranged + melee) on a unit so
## UI/read paths can then read model.ranged_loadout / model.melee_loadout.
## Idempotent — a no-op once the unit has been resolved.
static func ensure_loadout_resolved(unit: Dictionary) -> void:
	_ensure_loadout_resolved(unit)

## Allocate `total_damage` into the target unit's model pool; returns the
## damage-application result (diffs, casualties).
static func apply_damage_to_unit_pool(target_unit_id: String, total_damage: int, models: Array, board: Dictionary) -> Dictionary:
	return _apply_damage_to_unit_pool(target_unit_id, total_damage, models, board)

## 19.03 + 05.03: the Attached unit headed by target_unit_id folded into one
## virtual unit for allocation ({unit, sources}) — what
## resolve_allocation_batch_11e allocates against (attached CHARACTERs become
## per-model CHARACTER groups reached last).
static func build_attached_allocation_unit_11e(target_unit_id: String, board: Dictionary) -> Dictionary:
	return _build_attached_allocation_unit_11e(target_unit_id, board)

## Model dict lookup by id within a unit ({} if absent).
static func get_model_by_id(unit: Dictionary, model_id: String) -> Dictionary:
	return _get_model_by_id(unit, model_id)

## SPLIT-FIRE / PER-MODEL LOS+RANGE: the subset of `model_ids` still eligible
## to fire weapon_id at target_unit_id ({kept, dropped, reasons}) — the same
## resolve-time filter the engine applies, so UI previews (the blocked-bearers
## panel) agree with which models will actually shoot.
static func filter_eligible_model_ids(model_ids: Array, actor_unit_id: String, weapon_id: String, target_unit_id: String, board: Dictionary) -> Dictionary:
	return _filter_eligible_model_ids(model_ids, actor_unit_id, weapon_id, target_unit_id, board)

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

## Same predicate, asked of the whole ATTACHED unit (19.01: bodyguard +
## attached CHARACTER(s) are one unit for all rules purposes). is_unit_engaged
## measures a single unit dict's own models, so a leader standing a couple of
## inches behind his squad reads as "unengaged" while the squad he is part of is
## locked in combat — which is how a Blade Champion leading a charged Custodian
## Guard was offered Heroic Intervention into a fight he was already in.
## Any component being engaged engages the whole Attached unit; an attached
## CHARACTER passed in resolves to its bodyguard first (19.02).
static func is_attached_unit_engaged(unit_id: String, board: Dictionary) -> bool:
	var head_id := attached_unit_target_id(unit_id, board)
	for component_id in attached_unit_component_ids(head_id, board):
		if is_unit_engaged(component_id, board):
			return true
	return false
