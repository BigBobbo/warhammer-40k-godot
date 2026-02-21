class_name AIDifficultyConfig
extends RefCounted

# AIDifficultyConfig - Centralized configuration for AI difficulty levels
# T7-40: Implements Easy, Normal, Hard, and Competitive difficulty modes.
#
# Easy:        Random valid actions — no scoring or optimization
# Normal:      Current tactical behavior (existing decision logic)
# Hard:        Enhanced tactics — always considers stratagems, tighter focus fire
# Competitive: Full look-ahead planning — optimal stratagem timing, trade analysis

enum Difficulty {
	EASY = 0,
	NORMAL = 1,
	HARD = 2,
	COMPETITIVE = 3
}

# --- Per-difficulty configuration ---
# Each difficulty level has a set of modifiers that affect AI behavior.

# Whether the AI uses random valid actions instead of scoring
static func use_random_actions(difficulty: int) -> bool:
	return difficulty == Difficulty.EASY

# Whether the AI considers stratagems (reactive and proactive)
static func use_stratagems(difficulty: int) -> bool:
	return difficulty >= Difficulty.HARD

# Whether the AI uses multi-phase planning (movement→shooting→charge coordination)
static func use_multi_phase_planning(difficulty: int) -> bool:
	return difficulty >= Difficulty.HARD

# Whether the AI uses focus fire coordination across units
static func use_focus_fire(difficulty: int) -> bool:
	return difficulty >= Difficulty.NORMAL

# Whether the AI uses threat range awareness for positioning
static func use_threat_awareness(difficulty: int) -> bool:
	return difficulty >= Difficulty.NORMAL

# Whether the AI uses trade/tempo analysis for target priority
static func use_trade_analysis(difficulty: int) -> bool:
	return difficulty >= Difficulty.COMPETITIVE

# Whether the AI uses look-ahead planning (predicting opponent responses)
static func use_look_ahead(difficulty: int) -> bool:
	return difficulty == Difficulty.COMPETITIVE

# Whether the AI uses weapon-target efficiency matching
static func use_weapon_efficiency(difficulty: int) -> bool:
	return difficulty >= Difficulty.NORMAL

# Whether the AI uses survival assessment for fall-back decisions
static func use_survival_assessment(difficulty: int) -> bool:
	return difficulty >= Difficulty.HARD

# Whether the AI uses screening/deep strike denial positioning
static func use_screening(difficulty: int) -> bool:
	return difficulty >= Difficulty.HARD

# T7-44: Whether the AI reacts to opponent deployment (counter-deployment)
static func use_counter_deployment(difficulty: int) -> bool:
	return difficulty >= Difficulty.NORMAL

# Score noise factor — adds randomness to scoring to make AI less predictable
# Easy: high noise (essentially random), Normal: moderate, Hard: low, Competitive: none
static func get_score_noise(difficulty: int) -> float:
	match difficulty:
		Difficulty.EASY:
			return 100.0  # Overwhelms actual scores, making choices random
		Difficulty.NORMAL:
			return 1.5    # Small noise for natural variation
		Difficulty.HARD:
			return 0.5    # Minimal noise
		Difficulty.COMPETITIVE:
			return 0.0    # No noise — pure optimization
		_:
			return 1.5

# Movement optimization iterations — higher = better positioning
static func get_movement_iterations(difficulty: int) -> int:
	match difficulty:
		Difficulty.EASY:
			return 1    # Single random position
		Difficulty.NORMAL:
			return 3    # A few candidates
		Difficulty.HARD:
			return 5    # More thorough search
		Difficulty.COMPETITIVE:
			return 8    # Exhaustive positioning
		_:
			return 3

# Whether AI uses Command Re-roll optimally
static func use_command_reroll(difficulty: int) -> bool:
	return difficulty >= Difficulty.NORMAL

# Charge threshold modifier — lower = more willing to charge
# Easy AI almost never charges (risky), Competitive AI charges more aggressively
static func get_charge_threshold_modifier(difficulty: int) -> float:
	match difficulty:
		Difficulty.EASY:
			return 2.0   # Much higher threshold — rarely charges
		Difficulty.NORMAL:
			return 1.0   # Standard threshold
		Difficulty.HARD:
			return 0.85  # Slightly lower — more aggressive charging
		Difficulty.COMPETITIVE:
			return 0.7   # Aggressive — charges when expected value is positive
		_:
			return 1.0

# Overwatch evaluation — whether AI will use fire overwatch
static func use_overwatch(difficulty: int) -> bool:
	return difficulty >= Difficulty.NORMAL

# Counter-offensive evaluation — whether AI uses counter-offensive stratagem
static func use_counter_offensive(difficulty: int) -> bool:
	return difficulty >= Difficulty.HARD

# --- Display helpers ---

static func difficulty_name(difficulty: int) -> String:
	match difficulty:
		Difficulty.EASY:
			return "Easy"
		Difficulty.NORMAL:
			return "Normal"
		Difficulty.HARD:
			return "Hard"
		Difficulty.COMPETITIVE:
			return "Competitive"
		_:
			return "Normal"

static func difficulty_description(difficulty: int) -> String:
	match difficulty:
		Difficulty.EASY:
			return "Random valid actions — good for learning the game"
		Difficulty.NORMAL:
			return "Tactical decisions with standard optimization"
		Difficulty.HARD:
			return "Enhanced tactics with stratagems and coordinated planning"
		Difficulty.COMPETITIVE:
			return "Optimal play with look-ahead planning and trade analysis"
		_:
			return ""

static func from_string(name: String) -> int:
	match name.to_lower():
		"easy":
			return Difficulty.EASY
		"normal":
			return Difficulty.NORMAL
		"hard":
			return Difficulty.HARD
		"competitive":
			return Difficulty.COMPETITIVE
		_:
			return Difficulty.NORMAL
