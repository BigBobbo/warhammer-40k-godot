class_name AIDecisionMaker
extends RefCounted

# AIDecisionMaker - Pure decision logic for the AI player
# No scene tree access, no signals. Takes data in, returns action dictionaries out.
# All methods are static for use without instantiation.

# --- Constants ---
const AIAbilityAnalyzerData = preload("res://scripts/AIAbilityAnalyzer.gd")
const AIDifficultyConfigData = preload("res://scripts/AIDifficultyConfig.gd")
const PIXELS_PER_INCH: float = 40.0
const ENGAGEMENT_RANGE_PX: float = 40.0  # 1 inch
const CHARGE_RANGE_PX: float = 480.0     # 12 inches
const COHERENCY_RANGE_PX: float = 80.0   # 2 inches
const BOARD_WIDTH_PX: float = 1760.0     # 44 inches
const BOARD_HEIGHT_PX: float = 2400.0    # 60 inches
const OBJECTIVE_RANGE_PX: float = 120.0  # 3 inches - objective control range in 10e
const OBJECTIVE_CONTROL_RANGE_PX: float = 151.5  # 3.79" (3" + 20mm marker radius) in pixels
const BASE_MARGIN_PX: float = 30.0       # Safety margin from board edges

# Late-bound reference to RulesEngine autoload (avoids compile-time dependency)
static func _rules_engine():
	var main = Engine.get_main_loop()
	if main is SceneTree and main.root:
		return main.root.get_node_or_null("RulesEngine")
	return null

# Focus fire plan cache — built once per shooting phase, consumed per-unit
# Stores {unit_id: [{weapon_id, target_unit_id}]} mapping
static var _focus_fire_plan: Dictionary = {}
static var _focus_fire_plan_built: bool = false

# Grenade stratagem evaluation — checked once per shooting phase
static var _grenade_evaluated: bool = false

# T7-23: Multi-phase planning cache — built at start of movement phase,
# consumed during shooting and charge phases.
# Coordinates movement→shooting→charge so phases don't work at cross purposes.
# _phase_plan stores:
#   charge_intent: {unit_id: {target_id, score, distance}} — units likely to charge
#   shooting_lanes: {unit_id: [{target_id, range_inches}]} — shooting targets from post-move positions
#   lock_targets: [target_id, ...] — dangerous enemy shooters to lock in combat
static var _phase_plan: Dictionary = {}
static var _phase_plan_built: bool = false
static var _phase_plan_round: int = -1  # Track which round the plan was built for

# Focus fire tuning constants
const OVERKILL_TOLERANCE: float = 1.3  # Allow up to 30% overkill before redirecting
const KILL_BONUS_MULTIPLIER: float = 2.0  # Bonus multiplier for targets we can actually kill
const LOW_HEALTH_BONUS: float = 1.5  # Bonus for targets below half health

# Weapon-target efficiency matching constants
# Weapon role classification thresholds
const ANTI_TANK_STRENGTH_THRESHOLD: int = 7     # S7+ suggests anti-tank
const ANTI_TANK_AP_THRESHOLD: int = 2            # AP-2+ suggests anti-tank
const ANTI_TANK_DAMAGE_THRESHOLD: float = 3.0    # D3+ suggests anti-tank
const ANTI_INFANTRY_DAMAGE_THRESHOLD: float = 1.0 # D1 is anti-infantry
const ANTI_INFANTRY_STRENGTH_CAP: int = 5        # S5 or below is anti-infantry oriented

# Efficiency multipliers for weapon-target matching
const EFFICIENCY_PERFECT_MATCH: float = 1.4      # Anti-tank vs vehicle, anti-infantry vs horde
const EFFICIENCY_GOOD_MATCH: float = 1.15        # Decent but not ideal pairing
const EFFICIENCY_NEUTRAL: float = 1.0            # No bonus or penalty
const EFFICIENCY_POOR_MATCH: float = 0.6         # Anti-infantry vs vehicle, etc.
const EFFICIENCY_TERRIBLE_MATCH: float = 0.35    # Total waste (e.g. lascannon vs grots)

# Damage waste penalty: multi-damage on single-wound models
const DAMAGE_WASTE_PENALTY_HEAVY: float = 0.4    # D3+ weapon vs 1W models
const DAMAGE_WASTE_PENALTY_MODERATE: float = 0.7  # D2 weapon vs 1W models

# Anti-keyword special rule bonus
const ANTI_KEYWORD_BONUS: float = 1.5            # Weapon has anti-X matching target type

# Weapon keyword scoring constants (SHOOT-5)
# Critical hit probability on a d6 (unmodified 6)
const CRIT_PROBABILITY: float = 1.0 / 6.0
# Rapid Fire / Melta: probability of being within half range when we know target is in range.
# Conservative estimate — assume 50% chance we're at half range unless we can measure.
const HALF_RANGE_FALLBACK_PROB: float = 0.5

# T7-30: AI range-band optimization constants
# Movement positioning for Rapid Fire/Melta half-range bonuses
const HALF_RANGE_MOVE_BLEND: float = 0.4           # How much to blend movement toward half-range position (0-1)
const HALF_RANGE_MIN_BENEFIT: float = 2.0           # Minimum extra attacks/damage across the unit to trigger repositioning
const HALF_RANGE_APPROACH_MARGIN_INCHES: float = 1.0 # Move slightly inside half range for safety margin

# Movement AI tuning weights
const WEIGHT_UNCONTROLLED_OBJ: float = 10.0
const WEIGHT_CONTESTED_OBJ: float = 8.0
const WEIGHT_ENEMY_WEAK_OBJ: float = 7.0
const WEIGHT_HOME_UNDEFENDED: float = 9.0
const WEIGHT_ENEMY_STRONG_OBJ: float = -5.0
const WEIGHT_ALREADY_HELD_OBJ: float = -8.0
const WEIGHT_SCORING_URGENCY: float = 3.0
const WEIGHT_OC_EFFICIENCY: float = 2.0

# Threat range awareness constants (AI-TACTIC-4, MOV-2)
# Charge threat = enemy M + 12" charge + 1" engagement range
# Shooting threat = max weapon range of the enemy unit
# Penalty weights for moving into threat zones
const THREAT_CHARGE_PENALTY: float = 3.0    # Penalty for moving into charge threat range
const THREAT_SHOOTING_PENALTY: float = 1.0  # Lighter penalty for moving into shooting range (often unavoidable)
const THREAT_FRAGILE_BONUS: float = 1.5     # Extra penalty multiplier for fragile/high-value units in danger
const THREAT_MELEE_UNIT_IGNORE: float = 0.3 # Melee-focused units care less about being in charge range
const THREAT_SAFE_MARGIN_INCHES: float = 2.0 # Extra buffer beyond raw threat range for safety
# Close melee proximity: 12" is the raw charge distance — being this close means
# the enemy can charge without needing to move first, making it critically dangerous
const THREAT_CLOSE_MELEE_DISTANCE_INCHES: float = 12.0

# Screening / Deep Strike denial constants (AI-TACTIC-3, MOV-4)
const DEEP_STRIKE_DENIAL_RANGE_PX: float = 360.0  # 9 inches — deep strike must land >9" from enemies
const SCREEN_SPACING_PX: float = 720.0             # 18 inches — spacing between screeners for full denial coverage
const SCREEN_CHEAP_UNIT_POINTS: int = 100           # Units at or below this point cost are screening candidates
const SCREEN_SCORE_BASE: float = 8.0                # Base score for a screening assignment (comparable to objective priority)
const THREAT_CLOSE_MELEE_PENALTY: float = 2.0   # Extra penalty on top of normal charge threat for being within 12"

# T7-42: Corridor blocking constants (AI-TACTIC-9)
# Position expendable units to block enemy movement corridors toward objectives
const CORRIDOR_BLOCK_THREAT_RANGE_INCHES: float = 30.0  # Enemy must be within 30" of objective to warrant blocking
const CORRIDOR_BLOCK_POSITION_RATIO: float = 0.55        # Place blocker 55% of the way from objective toward enemy
const CORRIDOR_BLOCK_SCORE_BASE: float = 7.0             # Base priority for blocking assignments (below screening 8.0)
const CORRIDOR_BLOCK_MIN_GAP_PX: float = 200.0           # 5" — minimum spacing between blocking positions
const CORRIDOR_BLOCK_MAX_POSITIONS: int = 4               # Cap on blocking positions to avoid over-committing

# T7-23: Multi-phase planning constants
# Movement phase adjustments based on planned future actions
const PHASE_PLAN_CHARGE_LANE_BONUS: float = 3.0     # Bonus for moving toward charge-worthy targets
const PHASE_PLAN_SHOOTING_LANE_BONUS: float = 2.0   # Bonus for maintaining shooting lanes
const PHASE_PLAN_CHARGE_INTENT_THRESHOLD: float = 3.0  # Min charge score to flag intent
const PHASE_PLAN_LOCK_SHOOTER_BONUS: float = 3.0    # Bonus for charging dangerous shooters
const PHASE_PLAN_DONT_SHOOT_CHARGE_TARGET: float = 0.1  # Multiplier for shooting at charge targets (near-zero)
const PHASE_PLAN_RANGED_STRENGTH_DANGEROUS: float = 5.0  # Ranged output threshold for "dangerous shooter"
# Urgency scoring extension (expanding round-1 urgency)
const URGENCY_ROUND_2_CONTEST: float = 2.0      # Round 2: contest uncontrolled objectives
const URGENCY_ROUND_3_HOLD: float = 1.5         # Round 3: consolidate hold on objectives
const URGENCY_LATE_GAME_PUSH: float = 2.5       # Round 4-5: aggressive push for VP

# T7-24: Trade and tempo awareness constants
# Trade efficiency: points-per-wound used to evaluate whether engagements are favorable
const TRADE_PPW_WEIGHT: float = 0.25               # How much points-per-wound efficiency affects target value
const TRADE_FAVORABLE_BONUS: float = 1.3            # Max bonus when trading up (cheap unit kills expensive per wound)
const TRADE_UNFAVORABLE_PENALTY: float = 0.7        # Min penalty when trading down (expensive unit kills cheap per wound)
# Tempo: VP differential and round-based aggression adjustments
const TEMPO_VP_DIFF_WEIGHT: float = 0.1             # Per-VP aggression adjustment
const TEMPO_BEHIND_AGGRESSION_BOOST: float = 1.5    # Max aggression boost when losing
const TEMPO_AHEAD_CONSERVATION: float = 0.8         # Conservation factor when winning
const TEMPO_DESPERATION_ROUND: int = 4              # Round at which being behind triggers desperation
const TEMPO_DESPERATION_MULTIPLIER: float = 1.8     # Aggression multiplier in desperation mode
const TEMPO_MAX_ROUNDS: int = 5                     # Standard 40k game length (5 battle rounds)
const TEMPO_CHARGE_THRESHOLD_REDUCTION: float = 0.4 # How much to lower charge threshold when desperate

# T7-43: Late-game strategy pivot constants
# Rounds 1-2: Aggressive — favor kills and aggressive positioning
# Round 3: Balanced — standard weights (all 1.0)
# Rounds 4-5: Objective/survival — prioritize objective control and survival over kills
const STRATEGY_EARLY_AGGRESSION: float = 1.3        # Rounds 1-2: boost kill-seeking scoring by 30%
const STRATEGY_EARLY_OBJECTIVE: float = 0.85         # Rounds 1-2: slightly reduce objective weight (aggression first)
const STRATEGY_EARLY_SURVIVAL: float = 0.8           # Rounds 1-2: accept more risk (reduce threat penalty)
const STRATEGY_EARLY_CHARGE: float = 0.8             # Rounds 1-2: lower charge threshold (more willing to charge)
const STRATEGY_LATE_AGGRESSION: float = 0.7          # Rounds 4-5: reduce kill-seeking scoring by 30%
const STRATEGY_LATE_OBJECTIVE: float = 1.4           # Rounds 4-5: boost objective control priority by 40%
const STRATEGY_LATE_SURVIVAL: float = 1.4            # Rounds 4-5: increase survival/threat avoidance by 40%
const STRATEGY_LATE_CHARGE: float = 1.3              # Rounds 4-5: higher charge threshold (less willing to charge)
const STRATEGY_LATE_CHARGE_ON_OBJ_BONUS: float = 1.5 # Rounds 4-5: extra bonus for charging onto objectives
const STRATEGY_LATE_OBJ_TARGET_BONUS: float = 1.3    # Rounds 4-5: extra bonus for shooting units on objectives

# T7-27: Engaged unit survival assessment constants
# Used to estimate fight-phase damage and inform hold/fall-back decisions
const SURVIVAL_LETHAL_THRESHOLD: float = 0.75      # If expected damage >= 75% of remaining wounds, unit is likely destroyed
const SURVIVAL_SEVERE_THRESHOLD: float = 0.5       # If expected damage >= 50% of remaining wounds, unit is badly hurt
const SURVIVAL_FALL_BACK_BONUS: float = 2.0        # Score bonus toward falling back when survival is threatened
const SURVIVAL_HOLD_BONUS: float = 1.5             # Score bonus toward holding when unit can survive the fight phase

# T7-22: AI target priority framework constants
# Macro-level target value weights
const MACRO_POINTS_WEIGHT: float = 0.008         # Per-point value contribution (200pt unit = +1.6)
const MACRO_RANGED_OUTPUT_WEIGHT: float = 0.15   # Per-expected-damage for ranged output
const MACRO_MELEE_OUTPUT_WEIGHT: float = 0.10    # Per-expected-damage for melee output
const MACRO_ABILITY_VALUE_WEIGHT: float = 0.5    # Bonus per ability multiplier above 1.0
const MACRO_SURVIVABILITY_DISCOUNT: float = 0.15 # Discount per defensive multiplier above 1.0 (harder to kill = less efficient to shoot)
const MACRO_OC_ON_OBJECTIVE_WEIGHT: float = 0.5  # Per-OC when unit is on an objective
const MACRO_OC_NEAR_OBJECTIVE_WEIGHT: float = 0.2 # Per-OC when unit is near an objective
const MACRO_LEADER_BUFF_BONUS: float = 1.5       # Multiplier for leaders providing buffs to attached units
# Micro-level weapon allocation constants
const MICRO_MARGINAL_KILL_BONUS: float = 2.5     # Bonus multiplier when assignment pushes total past kill threshold
const MICRO_OVERKILL_DECAY: float = 0.3          # Value multiplier for damage beyond kill threshold
const MICRO_MODEL_KILL_VALUE: float = 0.4        # Fractional value per model killed (vs full wipe value of 1.0)

# =============================================================================
# T7-40: DIFFICULTY-AWARE SCORING UTILITIES
# =============================================================================

static func _apply_difficulty_noise(score: float) -> float:
	"""Add random noise to a score based on current difficulty level.
	Higher noise makes the AI less optimal (more humanlike / random)."""
	var noise = AIDifficultyConfigData.get_score_noise(_current_difficulty)
	if noise <= 0.0:
		return score
	return score + (randf() - 0.5) * noise * 2.0

static func _get_difficulty_charge_threshold_modifier() -> float:
	"""Get charge threshold modifier for current difficulty."""
	return AIDifficultyConfigData.get_charge_threshold_modifier(_current_difficulty)

# =============================================================================
# MAIN ENTRY POINT
# =============================================================================

# T7-40: Current difficulty level for the active AI player
# Set by AIPlayer before each decide() call, used by sub-methods
static var _current_difficulty: int = AIDifficultyConfigData.Difficulty.NORMAL

static func decide(phase: int, snapshot: Dictionary, available_actions: Array, player: int, difficulty: int = AIDifficultyConfigData.Difficulty.NORMAL) -> Dictionary:
	_current_difficulty = difficulty
	var diff_name = AIDifficultyConfigData.difficulty_name(difficulty)
	# T7-43: Log round strategy mode
	var current_round = snapshot.get("meta", {}).get("battle_round", snapshot.get("battle_round", 1))
	var strategy = _get_round_strategy_modifiers(current_round)
	print("AIDecisionMaker: Deciding for phase %d, player %d, %d available actions (difficulty: %s, round=%d, strategy=%s)" % [
		phase, player, available_actions.size(), diff_name, current_round, strategy.label])
	for a in available_actions:
		print("  Available: %s" % a.get("type", "?"))

	# T7-40: Easy difficulty — pick random valid actions instead of scoring
	if AIDifficultyConfigData.use_random_actions(difficulty):
		return _decide_random(phase, snapshot, available_actions, player)

	# Reset focus fire plan cache and grenade flag when not in shooting phase
	if phase != GameStateData.Phase.SHOOTING:
		if _focus_fire_plan_built:
			_focus_fire_plan_built = false
			_focus_fire_plan.clear()
		_grenade_evaluated = false

	# T7-23: Reset multi-phase plan when a new round starts or when we enter
	# a phase earlier than movement (i.e., command phase or earlier)
	var current_round = snapshot.get("battle_round", 1)
	if _phase_plan_round != current_round:
		_phase_plan.clear()
		_phase_plan_built = false
		_phase_plan_round = current_round

	# T7-40: Normal and below skip multi-phase planning
	if not AIDifficultyConfigData.use_multi_phase_planning(difficulty):
		_phase_plan_built = true  # Prevent building phase plans

	match phase:
		GameStateData.Phase.FORMATIONS:
			return _decide_formations(snapshot, available_actions, player)
		GameStateData.Phase.DEPLOYMENT:
			return _decide_deployment(snapshot, available_actions, player)
		GameStateData.Phase.SCOUT:
			return _decide_scout(snapshot, available_actions, player)
		GameStateData.Phase.COMMAND:
			return _decide_command(snapshot, available_actions, player)
		GameStateData.Phase.MOVEMENT:
			return _decide_movement(snapshot, available_actions, player)
		GameStateData.Phase.SHOOTING:
			return _decide_shooting(snapshot, available_actions, player)
		GameStateData.Phase.CHARGE:
			return _decide_charge(snapshot, available_actions, player)
		GameStateData.Phase.FIGHT:
			return _decide_fight(snapshot, available_actions, player)
		GameStateData.Phase.SCORING:
			return _decide_scoring(snapshot, available_actions, player)
		_:
			# Unknown phase - try to find an END action
			for action in available_actions:
				var t = action.get("type", "")
				if t.begins_with("END_"):
					return {"type": t, "_ai_description": "End phase (fallback)"}
			return {}

# =============================================================================
# T7-40: EASY DIFFICULTY — RANDOM VALID ACTIONS
# =============================================================================

static func _decide_random(phase: int, snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	"""Easy difficulty: pick random valid actions. Still handles required
	sequencing (CONFIRM, APPLY_SAVES, etc.) but makes random tactical choices."""
	if available_actions.is_empty():
		return {}

	# Build action type map
	var action_types = {}
	for a in available_actions:
		var t = a.get("type", "")
		if not action_types.has(t):
			action_types[t] = []
		action_types[t].append(a)

	# --- Required sequencing: always handle these deterministically ---
	# These are mechanical steps that must be completed regardless of difficulty

	# Saves, dice rolls, confirmations
	if action_types.has("APPLY_SAVES"):
		return {"type": "APPLY_SAVES", "payload": {"save_results_list": []}, "_ai_description": "Applying saves (Easy)"}
	if action_types.has("ROLL_DICE"):
		return {"type": "ROLL_DICE", "_ai_description": "Roll dice (Easy)"}
	if action_types.has("CONFIRM_AND_RESOLVE_ATTACKS"):
		return {"type": "CONFIRM_AND_RESOLVE_ATTACKS", "_ai_description": "Confirm attacks (Easy)"}
	if action_types.has("CONTINUE_SEQUENCE"):
		return {"type": "CONTINUE_SEQUENCE", "_ai_description": "Continue sequence (Easy)"}
	if action_types.has("RESOLVE_SHOOTING"):
		return {"type": "RESOLVE_SHOOTING", "_ai_description": "Resolve shooting (Easy)"}
	if action_types.has("CONFIRM_TARGETS"):
		return {"type": "CONFIRM_TARGETS", "_ai_description": "Confirm targets (Easy)"}
	if action_types.has("COMPLETE_SHOOTING_FOR_UNIT"):
		var a = action_types["COMPLETE_SHOOTING_FOR_UNIT"][0]
		return {"type": "COMPLETE_SHOOTING_FOR_UNIT", "actor_unit_id": a.get("actor_unit_id", ""), "_ai_description": "Complete shooting (Easy)"}
	if action_types.has("CONFIRM_UNIT_MOVE"):
		var a = action_types["CONFIRM_UNIT_MOVE"][0]
		return {"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": a.get("actor_unit_id", a.get("unit_id", "")), "_ai_description": "Confirm move (Easy)"}

	# Scoring phase — always process scoring deterministically
	if phase == GameStateData.Phase.SCORING:
		return _decide_scoring(snapshot, available_actions, player)

	# Formations phase — leader attachment still uses normal logic (not tactical)
	if phase == GameStateData.Phase.FORMATIONS:
		return _decide_formations(snapshot, available_actions, player)

	# Deployment — use normal deployment logic (random positions would be chaotic)
	if phase == GameStateData.Phase.DEPLOYMENT:
		return _decide_deployment(snapshot, available_actions, player)

	# Scout moves — use normal logic
	if phase == GameStateData.Phase.SCOUT:
		return _decide_scout(snapshot, available_actions, player)

	# Command phase — use normal logic (just CP/Battle-shock, not tactical)
	if phase == GameStateData.Phase.COMMAND:
		return _decide_command(snapshot, available_actions, player)

	# --- Tactical decisions: randomize these ---

	# Always decline stratagems and reactive abilities on Easy
	for decline_type in ["DECLINE_COMMAND_REROLL", "DECLINE_FIRE_OVERWATCH",
			"DECLINE_REACTIVE_STRATAGEM", "DECLINE_COUNTER_OFFENSIVE",
			"DECLINE_HEROIC_INTERVENTION", "DECLINE_TANK_SHOCK"]:
		if action_types.has(decline_type):
			var a = action_types[decline_type][0]
			var result = {"type": decline_type, "_ai_description": "Decline (Easy)"}
			if a.has("actor_unit_id"):
				result["actor_unit_id"] = a.actor_unit_id
			return result

	# For USE_ reactive actions, also decline (prefer the decline variant)
	for use_type in ["USE_COMMAND_REROLL", "USE_FIRE_OVERWATCH", "USE_REACTIVE_STRATAGEM",
			"USE_COUNTER_OFFENSIVE", "USE_HEROIC_INTERVENTION", "USE_TANK_SHOCK",
			"USE_GRENADE_STRATAGEM"]:
		var decline_variant = use_type.replace("USE_", "DECLINE_")
		if action_types.has(use_type) and action_types.has(decline_variant):
			var a = action_types[decline_variant][0]
			var result = {"type": decline_variant, "_ai_description": "Decline (Easy)"}
			if a.has("actor_unit_id"):
				result["actor_unit_id"] = a.actor_unit_id
			return result

	# Movement: randomly choose between moving and staying
	if phase == GameStateData.Phase.MOVEMENT:
		return _decide_random_movement(snapshot, available_actions, player, action_types)

	# Shooting: pick a random shooter and random target
	if phase == GameStateData.Phase.SHOOTING:
		return _decide_random_shooting(snapshot, available_actions, player, action_types)

	# Charge: randomly decide whether to charge
	if phase == GameStateData.Phase.CHARGE:
		return _decide_random_charge(snapshot, available_actions, player, action_types)

	# Fight: use normal fight logic (sequencing is complex)
	if phase == GameStateData.Phase.FIGHT:
		return _decide_fight(snapshot, available_actions, player)

	# Fallback: pick END action or random action
	for action in available_actions:
		var t = action.get("type", "")
		if t.begins_with("END_"):
			return {"type": t, "_ai_description": "End phase (Easy)"}

	# Last resort: pick a random action
	var random_action = available_actions[randi() % available_actions.size()]
	var result = random_action.duplicate()
	result["_ai_description"] = "Random action: %s (Easy)" % result.get("type", "?")
	return result

static func _decide_random_movement(snapshot: Dictionary, available_actions: Array, player: int, action_types: Dictionary) -> Dictionary:
	"""Easy mode movement: randomly stay or move with minimal optimization."""
	# Handle reinforcements normally (placing is needed)
	if action_types.has("PLACE_REINFORCEMENT"):
		var reinforcement_decision = _decide_reserves_arrival(snapshot, action_types["PLACE_REINFORCEMENT"], player)
		if not reinforcement_decision.is_empty():
			return reinforcement_decision

	# Collect movable units
	var movable_units = {}
	for a in available_actions:
		var t = a.get("type", "")
		if t in ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "BEGIN_FALL_BACK", "REMAIN_STATIONARY"]:
			var uid = a.get("actor_unit_id", a.get("unit_id", ""))
			if uid != "":
				if not movable_units.has(uid):
					movable_units[uid] = []
				movable_units[uid].append(t)

	if movable_units.is_empty():
		return {"type": "END_MOVEMENT", "_ai_description": "End Movement Phase (Easy)"}

	# Pick a random unit
	var unit_ids = movable_units.keys()
	var uid = unit_ids[randi() % unit_ids.size()]
	var move_types = movable_units[uid]
	var unit = snapshot.get("units", {}).get(uid, {})
	var unit_name = unit.get("meta", {}).get("name", uid)

	# 50% chance to remain stationary, 50% chance to move
	if "REMAIN_STATIONARY" in move_types and randf() < 0.5:
		return {
			"type": "REMAIN_STATIONARY",
			"actor_unit_id": uid,
			"_ai_description": "%s remains stationary (Easy)" % unit_name
		}

	# Move normally with a random destination offset
	if "BEGIN_NORMAL_MOVE" in move_types:
		var models = unit.get("models", [])
		var move_inches = float(unit.get("meta", {}).get("stats", {}).get("move", 6))
		var move_px = move_inches * PIXELS_PER_INCH
		var destinations = {}
		for model in models:
			var mid = model.get("id", "")
			var pos = model.get("position", {})
			var cx = float(pos.get("x", 0))
			var cy = float(pos.get("y", 0))
			# Random direction, random distance up to max move
			var angle = randf() * TAU
			var dist = randf() * move_px
			var dest_x = clamp(cx + cos(angle) * dist, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
			var dest_y = clamp(cy + sin(angle) * dist, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)
			destinations[mid] = [dest_x, dest_y]

		return {
			"type": "BEGIN_NORMAL_MOVE",
			"actor_unit_id": uid,
			"_ai_model_destinations": destinations,
			"_ai_description": "%s moves randomly (Easy)" % unit_name
		}

	# Fallback: remain stationary
	if "REMAIN_STATIONARY" in move_types:
		return {
			"type": "REMAIN_STATIONARY",
			"actor_unit_id": uid,
			"_ai_description": "%s remains stationary (Easy fallback)" % unit_name
		}

	return {"type": "END_MOVEMENT", "_ai_description": "End Movement Phase (Easy)"}

static func _decide_random_shooting(snapshot: Dictionary, available_actions: Array, player: int, action_types: Dictionary) -> Dictionary:
	"""Easy mode shooting: pick a random shooter and random target."""
	# If SHOOT actions available, pick randomly
	if action_types.has("SHOOT"):
		var shoot_actions = action_types["SHOOT"]
		var chosen = shoot_actions[randi() % shoot_actions.size()]
		var result = chosen.duplicate()
		var unit_name = snapshot.get("units", {}).get(result.get("actor_unit_id", ""), {}).get("meta", {}).get("name", "?")
		result["_ai_description"] = "%s shoots randomly (Easy)" % unit_name
		return result

	# If SELECT_SHOOTER available, pick randomly
	if action_types.has("SELECT_SHOOTER"):
		var shooters = action_types["SELECT_SHOOTER"]
		var chosen = shooters[randi() % shooters.size()]
		var result = chosen.duplicate()
		result["_ai_description"] = "Select random shooter (Easy)"
		return result

	# End shooting
	if action_types.has("END_SHOOTING"):
		return {"type": "END_SHOOTING", "_ai_description": "End Shooting Phase (Easy)"}

	# Skip unit if available
	if action_types.has("SKIP_UNIT"):
		var a = action_types["SKIP_UNIT"][randi() % action_types["SKIP_UNIT"].size()]
		return {"type": "SKIP_UNIT", "actor_unit_id": a.get("actor_unit_id", ""), "_ai_description": "Skip unit (Easy)"}

	return {"type": "END_SHOOTING", "_ai_description": "End Shooting Phase (Easy fallback)"}

static func _decide_random_charge(snapshot: Dictionary, available_actions: Array, player: int, action_types: Dictionary) -> Dictionary:
	"""Easy mode charge: rarely charges (20% chance), mostly skips."""
	if action_types.has("DECLARE_CHARGE"):
		# 20% chance to charge
		if randf() < 0.2:
			var charges = action_types["DECLARE_CHARGE"]
			var chosen = charges[randi() % charges.size()]
			var result = chosen.duplicate()
			var unit_name = snapshot.get("units", {}).get(result.get("actor_unit_id", ""), {}).get("meta", {}).get("name", "?")
			result["_ai_description"] = "%s charges randomly (Easy)" % unit_name
			return result

	# Skip charging or end phase
	if action_types.has("SKIP_UNIT_CHARGE"):
		var skips = action_types["SKIP_UNIT_CHARGE"]
		var chosen = skips[randi() % skips.size()]
		return {"type": "SKIP_UNIT_CHARGE", "actor_unit_id": chosen.get("actor_unit_id", ""), "_ai_description": "Skip charge (Easy)"}

	if action_types.has("END_CHARGE"):
		return {"type": "END_CHARGE", "_ai_description": "End Charge Phase (Easy)"}

	# Fallback to normal charge logic for complex sequencing
	return _decide_charge(snapshot, available_actions, player)

# =============================================================================
# T7-23: MULTI-PHASE PLANNING
# =============================================================================
# Built once at the start of movement phase. Identifies:
#   1. charge_intent: units that are likely to charge (melee units near enemies)
#   2. lock_targets: dangerous enemy shooters that should be locked in combat
#   3. shooting_lanes: what each unit can shoot from its current/planned position
# This information is consumed by:
#   - Movement: position melee units for charge angles, ranged units for shooting lanes
#   - Shooting: avoid wasting firepower on targets planned for charge
#   - Charge: prefer locking dangerous shooters in combat

static func _build_phase_plan(snapshot: Dictionary, player: int) -> Dictionary:
	"""Build a coordinated cross-phase plan for the current turn.
	Called once at the start of the movement phase."""
	var plan = {
		"charge_intent": {},   # unit_id -> {target_id, target_name, score, distance_inches}
		"lock_targets": [],    # [target_id, ...] — enemy shooters to lock in combat
		"shooting_lanes": {},  # unit_id -> [{target_id, range_inches}]
		"charge_target_ids": [],  # convenience: all target_ids from charge_intent
	}

	var enemies = _get_enemy_units(snapshot, player)
	var friendly_units = _get_units_for_player(snapshot, player)

	if enemies.is_empty() or friendly_units.is_empty():
		return plan

	# --- Step 1: Identify dangerous enemy shooters (candidates for lock_targets) ---
	var dangerous_shooters = []
	for enemy_id in enemies:
		var enemy = enemies[enemy_id]
		var ranged_strength = _estimate_unit_ranged_strength(enemy)
		if ranged_strength >= PHASE_PLAN_RANGED_STRENGTH_DANGEROUS:
			dangerous_shooters.append({
				"unit_id": enemy_id,
				"ranged_strength": ranged_strength,
				"name": enemy.get("meta", {}).get("name", enemy_id)
			})

	# Sort by ranged strength descending (most dangerous first)
	dangerous_shooters.sort_custom(func(a, b): return a.ranged_strength > b.ranged_strength)

	for ds in dangerous_shooters:
		plan.lock_targets.append(ds.unit_id)

	if not dangerous_shooters.is_empty():
		print("AIDecisionMaker: [PHASE-PLAN] Identified %d dangerous enemy shooters:" % dangerous_shooters.size())
		for ds in dangerous_shooters:
			print("  %s (ranged output: %.1f)" % [ds.name, ds.ranged_strength])

	# --- Step 2: Identify charge intents (melee units that can plausibly charge) ---
	for unit_id in friendly_units:
		var unit = friendly_units[unit_id]
		var has_melee = _unit_has_melee_weapons(unit)
		if not has_melee:
			continue

		var centroid = _get_unit_centroid(unit)
		if centroid == Vector2.INF:
			continue

		# Check if unit is engaged (already in combat, won't charge)
		var state = unit.get("state", {})
		if state.get("is_engaged", false):
			continue

		var unit_name = unit.get("meta", {}).get("name", unit_id)
		var move_inches = float(unit.get("meta", {}).get("stats", {}).get("move", 6))

		# After movement + charge, total reach is: M + 12" charge range
		var total_reach_px = (move_inches + 12.0) * PIXELS_PER_INCH

		var best_charge_target = ""
		var best_charge_score = 0.0
		var best_charge_dist = INF
		var best_charge_name = ""

		for enemy_id in enemies:
			var enemy = enemies[enemy_id]
			var enemy_centroid = _get_unit_centroid(enemy)
			if enemy_centroid == Vector2.INF:
				continue

			var dist_px = centroid.distance_to(enemy_centroid)
			var dist_inches = dist_px / PIXELS_PER_INCH

			# Can this unit plausibly reach the enemy after moving + charging?
			# Use total reach + engagement range for generous estimate
			if dist_px > total_reach_px + ENGAGEMENT_RANGE_PX:
				continue

			# Score the charge: melee damage * target value
			var melee_dmg = _estimate_melee_damage(unit, enemy)
			var score = melee_dmg * 2.0

			# Bonus for locking dangerous shooters
			if enemy_id in plan.lock_targets:
				score += PHASE_PLAN_LOCK_SHOOTER_BONUS
				# Extra bonus proportional to how dangerous the shooter is
				var shooter_strength = _estimate_unit_ranged_strength(enemy)
				score += shooter_strength * 0.3

			# Bonus for targets on objectives
			var objectives = _get_objectives(snapshot)
			for obj_pos in objectives:
				if enemy_centroid.distance_to(obj_pos) <= OBJECTIVE_CONTROL_RANGE_PX:
					score *= 1.3
					break

			# Penalty for very long charges (unlikely to succeed)
			# After movement, the charge distance will be reduced by M
			var post_move_charge_dist = max(0.0, dist_inches - move_inches)
			if post_move_charge_dist > 9.0:
				score *= 0.5  # Long charge, less reliable
			elif post_move_charge_dist <= 6.0:
				score *= 1.2  # Reliable charge

			if score > best_charge_score:
				best_charge_score = score
				best_charge_target = enemy_id
				best_charge_dist = dist_inches
				best_charge_name = enemy.get("meta", {}).get("name", enemy_id)

		if best_charge_score >= PHASE_PLAN_CHARGE_INTENT_THRESHOLD and best_charge_target != "":
			plan.charge_intent[unit_id] = {
				"target_id": best_charge_target,
				"target_name": best_charge_name,
				"score": best_charge_score,
				"distance_inches": best_charge_dist
			}
			if best_charge_target not in plan.charge_target_ids:
				plan.charge_target_ids.append(best_charge_target)
			print("AIDecisionMaker: [PHASE-PLAN] %s intends to charge %s (score: %.1f, dist: %.1f\")" % [
				unit_name, best_charge_name, best_charge_score, best_charge_dist])

	# --- Step 3: Build shooting lanes for ranged units ---
	for unit_id in friendly_units:
		var unit = friendly_units[unit_id]
		if not _unit_has_ranged_weapons(unit):
			continue

		# Skip units that intend to charge (they'll be in melee)
		if plan.charge_intent.has(unit_id):
			continue

		var centroid = _get_unit_centroid(unit)
		if centroid == Vector2.INF:
			continue

		var max_range = _get_max_weapon_range(unit)
		if max_range <= 0.0:
			continue

		var lanes = []
		for enemy_id in enemies:
			var enemy = enemies[enemy_id]
			var enemy_centroid = _get_unit_centroid(enemy)
			if enemy_centroid == Vector2.INF:
				continue

			var dist_inches = centroid.distance_to(enemy_centroid) / PIXELS_PER_INCH
			if dist_inches <= max_range:
				lanes.append({
					"target_id": enemy_id,
					"range_inches": dist_inches
				})

		if not lanes.is_empty():
			plan.shooting_lanes[unit_id] = lanes

	print("AIDecisionMaker: [PHASE-PLAN] Summary: %d charge intents, %d lock targets, %d units with shooting lanes" % [
		plan.charge_intent.size(), plan.lock_targets.size(), plan.shooting_lanes.size()])

	return plan

static func _get_phase_plan() -> Dictionary:
	"""Get the current phase plan, or empty dict if not built yet."""
	return _phase_plan

static func _is_charge_target(target_id: String) -> bool:
	"""Check if a target is planned for charging (don't waste shooting on it)."""
	if not _phase_plan_built:
		return false
	return target_id in _phase_plan.get("charge_target_ids", [])

static func _get_charge_intent(unit_id: String) -> Dictionary:
	"""Get the charge intent for a specific unit, or empty dict."""
	if not _phase_plan_built:
		return {}
	return _phase_plan.get("charge_intent", {}).get(unit_id, {})

# =============================================================================
# FORMATIONS PHASE
# =============================================================================

static func _decide_formations(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	# AI strategy: Evaluate leader-bodyguard pairings based on ability synergies
	# ("while leading" bonuses like re-rolls, FNP, +1 to hit) and attach optimally.
	# Leaders always benefit from the Bodyguard rule (can't be targeted while bodyguard lives),
	# so attach all leaders, but prioritize pairings with the best synergy.

	var attachment_actions = []
	var transport_actions = []
	var reserves_actions = []
	var undeclare_reserves_actions = []
	var has_confirm = false

	for action in available_actions:
		match action.get("type", ""):
			"DECLARE_LEADER_ATTACHMENT":
				attachment_actions.append(action)
			"DECLARE_TRANSPORT_EMBARKATION":
				transport_actions.append(action)
			"DECLARE_RESERVES":
				reserves_actions.append(action)
			"UNDECLARE_RESERVES":
				undeclare_reserves_actions.append(action)
			"CONFIRM_FORMATIONS":
				has_confirm = true

	# If there are attachment options, evaluate and pick the best one
	if not attachment_actions.is_empty():
		var best = _evaluate_best_leader_attachment(snapshot, attachment_actions, player)
		if not best.is_empty():
			return best

	# T7-33 / FORM-2: After leader attachments, evaluate transport embarkation.
	# Embark small/fast infantry units in transports for deployment efficiency.
	if not transport_actions.is_empty():
		var embark_decision = _evaluate_transport_embarkation(snapshot, transport_actions, player)
		if not embark_decision.is_empty():
			return embark_decision

	# T7-34 / FORM-3: After transport embarkations, evaluate reserves declarations.
	# Put appropriate units in Strategic Reserves or Deep Strike based on army composition.
	if not reserves_actions.is_empty():
		var reserves_decision = _evaluate_reserves_declarations(snapshot, reserves_actions, undeclare_reserves_actions, player)
		if not reserves_decision.is_empty():
			return reserves_decision

	# No more attachments, embarkations, or reserves to declare — confirm formations
	if has_confirm:
		return {
			"type": "CONFIRM_FORMATIONS",
			"player": player,
			"_ai_description": "AI confirms battle formations (all declarations done)"
		}
	return {}

static func _evaluate_best_leader_attachment(snapshot: Dictionary, attachment_actions: Array, player: int) -> Dictionary:
	"""Score all available leader-bodyguard pairings and return the best one.
	Uses AIAbilityAnalyzer to compute offensive/defensive multipliers from
	the leader's 'while leading' abilities applied to each potential bodyguard."""
	var all_units = snapshot.get("units", {})
	var best_score = -1.0
	var best_action = {}

	for action in attachment_actions:
		var char_id = action.get("character_id", "")
		var bg_id = action.get("bodyguard_id", "")
		var score = _score_leader_bodyguard_pairing(char_id, bg_id, all_units)

		if score > best_score:
			best_score = score
			best_action = action

	if best_action.is_empty():
		return {}

	var char_name = all_units.get(best_action.get("character_id", ""), {}).get("meta", {}).get("name", "unknown")
	var bg_name = all_units.get(best_action.get("bodyguard_id", ""), {}).get("meta", {}).get("name", "unknown")
	best_action["_ai_description"] = "AI attaches %s to %s (synergy: %.2f)" % [char_name, bg_name, best_score]
	print("AIDecisionMaker: Leader attachment - %s -> %s (score=%.2f)" % [char_name, bg_name, best_score])
	return best_action

static func _score_leader_bodyguard_pairing(char_id: String, bg_id: String, all_units: Dictionary) -> float:
	"""Score a potential leader-bodyguard pairing by simulating the attachment
	and computing ability multipliers. Higher score = better synergy.

	Scoring factors:
	- Offensive ranged multiplier (from +hit, reroll hits/wounds for ranged)
	- Offensive melee multiplier (from +hit, reroll hits/wounds for melee)
	- Defensive multiplier (from FNP, cover, etc.)
	- Bodyguard model count (more models = more benefit from offensive buffs)
	- Bodyguard point value (higher value unit = more worth protecting/buffing)
	- Tactical bonuses (fall back and charge/shoot, advance and charge)"""
	var bg_unit = all_units.get(bg_id, {})
	var char_unit = all_units.get(char_id, {})
	if bg_unit.is_empty() or char_unit.is_empty():
		return 0.0

	# Simulate the attachment: create a copy of the bodyguard with this character attached
	var simulated_bg = bg_unit.duplicate()
	simulated_bg["attachment_data"] = {"attached_characters": [char_id]}

	# Compute multipliers with simulated attachment
	var off_ranged = AIAbilityAnalyzerData.get_offensive_multiplier_ranged(bg_id, simulated_bg, all_units)
	var off_melee = AIAbilityAnalyzerData.get_offensive_multiplier_melee(bg_id, simulated_bg, all_units)
	var def_mult = AIAbilityAnalyzerData.get_defensive_multiplier(bg_id, simulated_bg, all_units)

	# Check tactical bonuses from leader
	var bonuses = AIAbilityAnalyzerData.get_leader_bonuses(bg_id, simulated_bg, all_units)
	var tactical_bonus = 0.0
	if bonuses.get("fall_back_and_charge", false):
		tactical_bonus += 0.15
	if bonuses.get("fall_back_and_shoot", false):
		tactical_bonus += 0.10
	if bonuses.get("advance_and_charge", false):
		tactical_bonus += 0.15
	if bonuses.get("advance_and_shoot", false):
		tactical_bonus += 0.10

	# Count alive models in the bodyguard (more models = more benefit from buffs)
	var model_count = 0
	for model in bg_unit.get("models", []):
		if model.get("alive", true):
			model_count += 1

	# Base synergy: average of offensive and defensive improvements
	# Each multiplier is >= 1.0; combined synergy captures total buff value
	var synergy = (off_ranged + off_melee + def_mult) / 3.0 + tactical_bonus

	# Scale by model count: more models benefit more from per-model buffs
	# (e.g., +1 to hit applies to every model's attacks)
	var model_scale = 1.0 + (model_count - 1) * 0.05  # 5% bonus per extra model

	# Scale by point value: buffing expensive units is more impactful
	var points = bg_unit.get("meta", {}).get("points", 100)
	var points_scale = 1.0 + (points - 50.0) / 400.0  # Normalized around typical costs

	var score = synergy * model_scale * points_scale

	print("AIDecisionMaker: Score %s -> %s: off_r=%.2f off_m=%.2f def=%.2f tac=%.2f models=%d pts=%d => %.2f" % [
		char_unit.get("meta", {}).get("name", char_id),
		bg_unit.get("meta", {}).get("name", bg_id),
		off_ranged, off_melee, def_mult, tactical_bonus, model_count, points, score
	])

	return score

# =============================================================================
# TRANSPORT EMBARKATION — FORMATIONS PHASE (T7-33 / FORM-2)
# =============================================================================

static func _evaluate_transport_embarkation(snapshot: Dictionary, transport_actions: Array, player: int) -> Dictionary:
	"""Evaluate which units should embark in available transports during formations.
	Prioritizes embarking small/fast INFANTRY units for deployment efficiency.
	Only embarks one transport per call (called repeatedly until no more are beneficial)."""
	var all_units = snapshot.get("units", {})

	# Build list of candidate units that could embark (not characters, not transports themselves)
	var candidate_units = []
	for unit_id in all_units:
		var unit = all_units[unit_id]
		if unit.get("owner", 0) != player:
			continue
		# Skip transports themselves
		if unit.has("transport_data"):
			continue
		# Skip units already embarked
		if unit.get("embarked_in", null) != null:
			continue
		# Skip characters with leader data (they should attach to bodyguards)
		var keywords = unit.get("meta", {}).get("keywords", [])
		if "CHARACTER" in keywords:
			var leader_data = unit.get("meta", {}).get("leader_data", {})
			if not leader_data.get("can_lead", []).is_empty():
				continue
		candidate_units.append(unit_id)

	if candidate_units.is_empty():
		return {}

	var best_score = 0.0
	var best_action = {}

	for action in transport_actions:
		var transport_id = action.get("transport_id", "")
		var transport = all_units.get(transport_id, {})
		if transport.is_empty() or not transport.has("transport_data"):
			continue

		var capacity = transport.get("transport_data", {}).get("capacity", 0)
		var capacity_keywords = transport.get("transport_data", {}).get("capacity_keywords", [])
		var already_embarked = transport.get("transport_data", {}).get("embarked_units", [])

		# Count already-embarked models
		var embarked_model_count = 0
		for emb_id in already_embarked:
			var emb_unit = all_units.get(emb_id, {})
			for model in emb_unit.get("models", []):
				if model.get("alive", true):
					embarked_model_count += 1

		var remaining_capacity = capacity - embarked_model_count
		if remaining_capacity <= 0:
			continue

		# Score each candidate unit for this transport
		var scored_candidates = []
		for unit_id in candidate_units:
			var unit = all_units.get(unit_id, {})
			var unit_keywords = unit.get("meta", {}).get("keywords", [])

			# Check keyword compatibility
			if capacity_keywords.size() > 0:
				var has_keyword = false
				for kw in capacity_keywords:
					if kw in unit_keywords:
						has_keyword = true
						break
				if not has_keyword:
					continue

			# Count alive models
			var model_count = 0
			for model in unit.get("models", []):
				if model.get("alive", true):
					model_count += 1
			if model_count == 0 or model_count > remaining_capacity:
				continue

			# Score this unit for transport embarkation
			var score = _score_unit_for_embarkation(unit, unit_id, model_count, transport, all_units)
			if score > 0.0:
				scored_candidates.append({"unit_id": unit_id, "score": score, "model_count": model_count})

		if scored_candidates.is_empty():
			continue

		# Sort by score descending
		scored_candidates.sort_custom(func(a, b): return a.score > b.score)

		# Greedily select units that fit in remaining capacity
		var selected_unit_ids = []
		var used_capacity = 0
		for candidate in scored_candidates:
			if used_capacity + candidate.model_count <= remaining_capacity:
				selected_unit_ids.append(candidate.unit_id)
				used_capacity += candidate.model_count

		if selected_unit_ids.is_empty():
			continue

		# Total score for this transport loading
		var total_score = 0.0
		for candidate in scored_candidates:
			if candidate.unit_id in selected_unit_ids:
				total_score += candidate.score

		if total_score > best_score:
			best_score = total_score
			var transport_name = transport.get("meta", {}).get("name", transport_id)
			var unit_names = []
			for uid in selected_unit_ids:
				unit_names.append(all_units.get(uid, {}).get("meta", {}).get("name", uid))
			best_action = {
				"type": "DECLARE_TRANSPORT_EMBARKATION",
				"transport_id": transport_id,
				"unit_ids": selected_unit_ids,
				"player": player,
				"_ai_description": "AI embarks %s in %s (score: %.2f, %d/%d capacity)" % [
					", ".join(unit_names), transport_name, total_score, used_capacity, capacity]
			}

	if not best_action.is_empty():
		print("AIDecisionMaker: [FORM-2] %s" % best_action.get("_ai_description", ""))
	return best_action

static func _score_unit_for_embarkation(unit: Dictionary, unit_id: String, model_count: int,
										transport: Dictionary, all_units: Dictionary) -> float:
	"""Score how much a unit benefits from being embarked in a transport.
	Higher scores = unit benefits more from transport protection and deployment."""
	var score = 0.0
	var keywords = unit.get("meta", {}).get("keywords", [])
	var stats = unit.get("meta", {}).get("stats", {})
	var toughness = int(stats.get("toughness", 4))
	var save = int(stats.get("save", 4))
	var wounds = int(stats.get("wounds", 1))
	var move = int(stats.get("move", 6))
	var points = unit.get("meta", {}).get("points", 100)

	# Fragile units benefit most from transport protection
	# Low toughness (T3-4) and poor saves (5+, 6+) want to be in transports
	if toughness <= 4:
		score += 0.3
	if save >= 5:
		score += 0.2
	if wounds == 1:
		score += 0.2  # Single-wound models are very fragile

	# Small units are more efficient to transport (fewer models = more capacity-efficient)
	if model_count <= 5:
		score += 0.3
	elif model_count <= 10:
		score += 0.15

	# Units with good ranged weapons benefit from being delivered safely to shooting range
	if _unit_has_ranged_weapons(unit):
		var max_range = _get_max_weapon_range(unit)
		if max_range <= 12.0:
			score += 0.3  # Short-range weapons need transport delivery
		elif max_range <= 24.0:
			score += 0.15

	# Melee units benefit greatly from transport delivery to charge range
	if _unit_has_melee_weapons(unit):
		score += 0.25

	# Slow units (M5" or less) benefit more from transport speed
	if move <= 5:
		score += 0.2
	elif move <= 6:
		score += 0.1

	# Higher point units are more worth protecting
	if points >= 150:
		score += 0.15
	elif points >= 100:
		score += 0.1

	# INFANTRY keyword is the most common transport-compatible type
	if "INFANTRY" in keywords:
		score += 0.1

	# Objective control value — units with good OC benefit from fast objective delivery
	var oc = int(stats.get("oc", 1))
	if oc >= 2:
		score += 0.1 * oc

	print("AIDecisionMaker: [FORM-2] Score %s for transport: %.2f (T%d, Sv%d+, W%d, M%d\", %d models, %dpts)" % [
		unit.get("meta", {}).get("name", unit_id), score, toughness, save, wounds, move, model_count, points])
	return score

# =============================================================================
# RESERVES DECLARATIONS — FORMATIONS PHASE (T7-34 / FORM-3)
# =============================================================================

static func _evaluate_reserves_declarations(snapshot: Dictionary, reserves_actions: Array,
		undeclare_reserves_actions: Array, player: int) -> Dictionary:
	"""Evaluate which units should be placed in reserves during formations.

	Per 10th Edition rules:
	- Deep Strike: Units with the Deep Strike ability can be set up in reserves,
	  arriving anywhere on the battlefield >9" from enemies (from Round 2+).
	- Strategic Reserves: Any unit can go into reserves (within 6" of board edge,
	  >9" from enemies). Limited to 25% of total army points.
	- Total reserves cannot exceed 50% of units or 50% of points.
	- Fortifications cannot be placed in reserves.

	Strategy: Put melee-oriented and short-range Deep Strike units in reserves
	for flexible positioning. Use Strategic Reserves for fast melee units that
	benefit from flank entry. Keep ranged firepower on the table for Turn 1 shooting.
	Returns one DECLARE_RESERVES action per call (called repeatedly until no more are beneficial)."""
	var all_units = snapshot.get("units", {})

	# --- Calculate army-wide budget ---
	var total_army_points = 0
	var total_army_units = 0
	for unit_id in all_units:
		var unit = all_units[unit_id]
		if unit.get("owner", 0) == player:
			total_army_points += unit.get("meta", {}).get("points", 0)
			total_army_units += 1

	var max_reserves_points = int(total_army_points * 0.25)
	var max_reserves_units = int(total_army_units / 2)  # Can't put more than half the army in reserves

	# Calculate current reserves commitment from UNDECLARE_RESERVES actions
	# (these represent units already declared in reserves)
	var current_reserves_points = 0
	var current_reserves_count = undeclare_reserves_actions.size()
	for action in undeclare_reserves_actions:
		var uid = action.get("unit_id", "")
		var u = all_units.get(uid, {})
		current_reserves_points += u.get("meta", {}).get("points", 0)

	print("AIDecisionMaker: [FORM-3] Reserves budget: %d/%d pts used, %d/%d units used (army: %d pts, %d units)" % [
		current_reserves_points, max_reserves_points, current_reserves_count, max_reserves_units,
		total_army_points, total_army_units])

	if current_reserves_count >= max_reserves_units:
		print("AIDecisionMaker: [FORM-3] At unit limit for reserves — skipping")
		return {}

	# --- Group actions by unit_id, preferring deep_strike over strategic_reserves ---
	# A unit with Deep Strike ability will have both options; always prefer deep_strike.
	var unit_best_action: Dictionary = {}  # unit_id -> best DECLARE_RESERVES action
	for action in reserves_actions:
		var unit_id = action.get("unit_id", "")
		var reserve_type = action.get("reserve_type", "strategic_reserves")
		if not unit_best_action.has(unit_id):
			unit_best_action[unit_id] = action
		elif reserve_type == "deep_strike":
			# Deep strike is always preferred over strategic reserves (more flexible)
			unit_best_action[unit_id] = action

	# --- Score each candidate unit ---
	var scored_candidates = []
	for unit_id in unit_best_action:
		var action = unit_best_action[unit_id]
		var unit = all_units.get(unit_id, {})
		if unit.is_empty():
			continue

		var reserve_type = action.get("reserve_type", "strategic_reserves")
		var unit_points = unit.get("meta", {}).get("points", 0)

		# Check if adding this unit would exceed the points cap
		if current_reserves_points + unit_points > max_reserves_points:
			continue

		var score = _score_unit_for_reserves(unit, unit_id, reserve_type, snapshot, player)
		if score > 0.0:
			scored_candidates.append({
				"action": action,
				"score": score,
				"unit_id": unit_id,
				"reserve_type": reserve_type,
				"points": unit_points
			})

	if scored_candidates.is_empty():
		print("AIDecisionMaker: [FORM-3] No suitable reserves candidates found")
		return {}

	# Sort by score descending — pick the single best candidate
	scored_candidates.sort_custom(func(a, b): return a.score > b.score)

	# Only declare if the best candidate has a meaningful score
	# (threshold ensures we don't put marginal units in reserves)
	var best = scored_candidates[0]
	if best.score < 2.0:
		print("AIDecisionMaker: [FORM-3] Best candidate score %.1f below threshold — deploying all on table" % best.score)
		return {}

	var action = best.action
	var unit_name = all_units.get(best.unit_id, {}).get("meta", {}).get("name", "unknown")
	var type_label = "Deep Strike" if best.reserve_type == "deep_strike" else "Strategic Reserves"
	action["_ai_description"] = "AI declares %s in %s (score: %.1f, %dpts)" % [
		unit_name, type_label, best.score, best.points]
	print("AIDecisionMaker: [FORM-3] %s" % action.get("_ai_description", ""))
	return action


static func _score_unit_for_reserves(unit: Dictionary, unit_id: String, reserve_type: String,
		snapshot: Dictionary, player: int) -> float:
	"""Score how much a unit benefits from being placed in reserves.
	Higher score = better reserves candidate. Returns 0.0 for units that should not be reserved.

	Scoring philosophy:
	- Deep Strike melee units benefit most (arrive anywhere, charge next turn)
	- Deep Strike short-range shooters benefit from flexible positioning
	- Strategic reserves melee units benefit from flank entry
	- Long-range ranged units should stay on table for Turn 1 shooting
	- Characters with leader data should attach, not reserve
	- Vehicles/Monsters generally prefer table presence"""
	var score = 0.0
	var keywords = unit.get("meta", {}).get("keywords", [])
	var points = unit.get("meta", {}).get("points", 0)
	var has_ranged = _unit_has_ranged_weapons(unit)
	var has_melee = _unit_has_melee_weapons(unit)
	var max_range = _get_max_weapon_range(unit)

	# --- Exclusions: units that should never be reserved ---

	# Characters with leader ability should attach to bodyguards, not go into reserves
	if "CHARACTER" in keywords:
		var leader_data = unit.get("meta", {}).get("leader_data", {})
		if not leader_data.get("can_lead", []).is_empty():
			print("AIDecisionMaker: [FORM-3] Skip %s — CHARACTER with leader data (should attach)" %
				unit.get("meta", {}).get("name", unit_id))
			return 0.0

	# Fortifications cannot be placed in reserves (rules requirement)
	if "FORTIFICATION" in keywords:
		return 0.0

	# Units already embarked in transports shouldn't go into reserves
	if unit.get("embarked_in", null) != null:
		return 0.0

	# Check for Deep Strike ability on the unit
	var has_deep_strike = false
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		if ability is Dictionary and ability.get("name", "") == "Deep Strike":
			has_deep_strike = true
			break
		elif ability is String and ability == "Deep Strike":
			has_deep_strike = true
			break

	# --- Scoring by reserve type ---

	if reserve_type == "deep_strike" and has_deep_strike:
		# Deep Strike allows deployment anywhere >9" from enemies — extremely flexible.
		# Melee units benefit most: arrive close, charge next turn.
		if has_melee and not has_ranged:
			score += 8.0  # Pure melee — Deep Strike is their ideal delivery method
		elif has_melee:
			score += 6.0  # Mixed melee/ranged still benefits significantly
		elif has_ranged and max_range <= 18:
			score += 5.0  # Very short-range shooters (flamers, meltas) need positioning
		elif has_ranged and max_range <= 24:
			score += 3.5  # Short-range shooters benefit from flexible arrival
		else:
			score += 1.5  # Long-range shooters have marginal benefit from Deep Strike

		# Bonus for high-value units (worth positioning carefully)
		score += clamp(points / 100.0, 0.0, 3.0)

	elif reserve_type == "strategic_reserves":
		# Strategic reserves arrive within 6" of a board edge — less flexible but still useful.
		# Primarily benefits fast melee units that can exploit flank entry.
		if has_melee and not has_ranged:
			score += 4.0  # Pure melee benefits from flank delivery
		elif has_melee:
			score += 2.5  # Mixed units get moderate benefit
		elif has_ranged and max_range <= 18:
			score += 2.0  # Short-range shooters can use edge entry
		else:
			score += 0.5  # Ranged units generally want Turn 1 shooting

		# Fast units capitalize better on board edge entry (more distance after arriving)
		var movement = 0
		for model in unit.get("models", []):
			var m_stat = model.get("stats", {}).get("M", "6")
			if m_stat is String:
				m_stat = m_stat.replace("\"", "").strip_edges()
				if m_stat.is_valid_int():
					movement = max(movement, int(m_stat))
				elif m_stat.is_valid_float():
					movement = max(movement, int(float(m_stat)))
			elif m_stat is int or m_stat is float:
				movement = max(movement, int(m_stat))
		if movement >= 12:
			score += 2.0  # Very fast units (bikes, cavalry) are great from reserves
		elif movement >= 10:
			score += 1.5
		elif movement >= 8:
			score += 0.5

		# Bonus for melee-oriented high-value units
		if has_melee:
			score += clamp(points / 200.0, 0.0, 1.5)

	# --- Universal modifiers ---

	# Vehicles and Monsters generally prefer deploying on the table
	# (they have range and durability, and losing a turn of shooting is costly)
	if "VEHICLE" in keywords or "MONSTER" in keywords:
		if not has_melee or has_ranged:
			score *= 0.4  # Significant penalty unless they're melee-focused
		else:
			score *= 0.7  # Melee vehicles/monsters still get some penalty

	# Purely long-range ranged units should stay on the table for Turn 1 shooting
	if has_ranged and not has_melee and max_range >= 36:
		score *= 0.3  # Heavy ranged platforms (Devastators, Leman Russ) want to shoot immediately

	# Cheap screening units are sometimes better deployed as screens
	if points <= SCREEN_CHEAP_UNIT_POINTS and not has_deep_strike:
		score *= 0.5  # Cheap units are better as Turn 1 screens than reserves

	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var type_label = "DS" if reserve_type == "deep_strike" else "SR"
	print("AIDecisionMaker: [FORM-3] Score %s (%s): %.1f (melee=%s, ranged=%s, range=%.0f\", pts=%d)" % [
		unit_name, type_label, score, has_melee, has_ranged, max_range, points])
	return score

# =============================================================================
# DEPLOYMENT PHASE
# =============================================================================

static func _decide_deployment(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	# Filter to DEPLOY_UNIT actions
	var deploy_actions = available_actions.filter(func(a): return a.get("type") == "DEPLOY_UNIT")

	if deploy_actions.is_empty():
		# Check for END_DEPLOYMENT
		for action in available_actions:
			if action.get("type") == "END_DEPLOYMENT":
				return {"type": "END_DEPLOYMENT", "_ai_description": "End Deployment"}
		return {}  # Nothing to do (opponent deploying)

	# Pick first undeployed unit
	var action_template = deploy_actions[0]
	var unit_id = action_template.get("unit_id", "")
	var unit = snapshot.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return {}

	# Calculate deployment zone bounds
	var zone_bounds = _get_deployment_zone_bounds(snapshot, player)

	# T7-18: Classify unit role for terrain-aware deployment
	var unit_role = _classify_deployment_role(unit)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	print("AIDecisionMaker: Deploying %s (role=%s)" % [unit_name, unit_role])

	# Find best position near an objective
	var objectives = _get_objectives(snapshot)
	var zone_center = Vector2(
		(zone_bounds.min_x + zone_bounds.max_x) / 2.0,
		(zone_bounds.min_y + zone_bounds.max_y) / 2.0
	)

	var objective_pos = zone_center
	var best_dist = INF
	for obj_pos in objectives:
		var clamped = Vector2(
			clamp(obj_pos.x, zone_bounds.min_x, zone_bounds.max_x),
			clamp(obj_pos.y, zone_bounds.min_y, zone_bounds.max_y)
		)
		var dist = clamped.distance_to(obj_pos)
		if dist < best_dist:
			best_dist = dist
			objective_pos = clamped

	# Spread units across the zone using column-based distribution
	var my_units = _get_units_for_player(snapshot, player)
	var deployed_count = 0
	for uid in my_units:
		var u = my_units[uid]
		if u.get("status", 0) != GameStateData.UnitStatus.UNDEPLOYED:
			deployed_count += 1

	var zone_width = zone_bounds.max_x - zone_bounds.min_x
	var zone_height = zone_bounds.max_y - zone_bounds.min_y
	var num_columns = maxi(3, mini(5, my_units.size()))
	var col_width = zone_width / num_columns
	var col_index = deployed_count % num_columns
	var depth_row = deployed_count / num_columns  # Which row front-to-back

	# Column center X position
	var col_center_x = zone_bounds.min_x + col_width * (col_index + 0.5)
	# Depth Y: stagger front to back within zone
	var depth_step = mini(200, int(zone_height / 3.0))
	var depth_offset = depth_row * depth_step

	# Player 1 deploys top (low Y), Player 2 deploys bottom (high Y)
	var is_top_zone = zone_bounds.min_y < BOARD_HEIGHT_PX / 2.0
	var deploy_y: float
	if is_top_zone:
		# Top zone - front edge is max_y (closer to center)
		deploy_y = zone_bounds.max_y - 80.0 - depth_offset
	else:
		# Bottom zone - front edge is min_y (closer to center)
		deploy_y = zone_bounds.min_y + 80.0 + depth_offset

	# Blend column position with objective-proximity position (baseline position)
	var baseline_pos = Vector2.ZERO
	baseline_pos.x = col_center_x * 0.7 + objective_pos.x * 0.3
	baseline_pos.y = clamp(deploy_y, zone_bounds.min_y + 60, zone_bounds.max_y - 60)

	# T7-18: Terrain-aware position adjustment
	var terrain_features = snapshot.get("board", {}).get("terrain_features", [])
	var best_pos = _find_terrain_aware_position(
		baseline_pos, unit_role, terrain_features, zone_bounds,
		is_top_zone, objectives, snapshot, player
	)

	# Generate formation positions
	var models = unit.get("models", [])
	var first_model = models[0] if models.size() > 0 else {}
	var base_mm = first_model.get("base_mm", 32)
	var base_type = first_model.get("base_type", "circular")
	var base_dimensions = first_model.get("base_dimensions", {})
	var positions = _generate_formation_positions(best_pos, models.size(), base_mm, zone_bounds)

	# Resolve collisions with already-deployed models
	var deployed_models = _get_all_deployed_model_positions(snapshot)
	positions = _resolve_formation_collisions(positions, base_mm, deployed_models, zone_bounds, base_type, base_dimensions)

	var rotations = []
	for i in range(models.size()):
		rotations.append(0.0)

	return {
		"type": "DEPLOY_UNIT",
		"unit_id": unit_id,
		"model_positions": positions,
		"model_rotations": rotations,
		"_ai_description": "Deployed %s (%s, col %d, row %d)" % [unit_name, unit_role, col_index + 1, depth_row + 1]
	}

# T7-18: Unit role classification for terrain-aware deployment
# Returns one of: "fragile_shooter", "durable_shooter", "melee", "character", "general"
static func _classify_deployment_role(unit: Dictionary) -> String:
	var meta = unit.get("meta", {})
	var keywords = meta.get("keywords", [])
	var stats = meta.get("stats", {})
	var upper_keywords = []
	for kw in keywords:
		upper_keywords.append(str(kw).to_upper())

	# Characters should hide behind LoS blockers
	if "CHARACTER" in upper_keywords:
		return "character"

	var has_ranged = _unit_has_ranged_weapons(unit)
	var has_melee = _unit_has_melee_weapons(unit)

	# Pure melee units deploy forward
	if has_melee and not has_ranged:
		return "melee"

	# Evaluate fragility: low toughness + low save + low wounds = fragile
	var toughness = int(stats.get("toughness", 4))
	var save = int(stats.get("save", 4))
	var wounds = int(stats.get("wounds", 1))

	# Fragile shooting units: T3-4 with 4+/5+/6+ save and low wounds
	if has_ranged:
		var is_fragile = (toughness <= 4 and save >= 4 and wounds <= 2)
		# Also treat low-toughness multi-wound units as fragile (e.g. T3 W2)
		if toughness <= 3 and wounds <= 2:
			is_fragile = true
		if is_fragile:
			return "fragile_shooter"
		return "durable_shooter"

	# Melee-leaning units with both weapons: deploy aggressively
	if has_melee:
		return "melee"

	return "general"

# T7-18: Score a terrain piece's value for a specific deployment role
# Returns 0.0 if terrain is irrelevant, positive values for beneficial terrain
static func _score_terrain_for_role(terrain: Dictionary, role: String, pos_near_terrain: Vector2,
		zone_bounds: Dictionary, is_top_zone: bool) -> float:
	var terrain_type = terrain.get("type", "")
	var height_cat = terrain.get("height_category", "")
	var score = 0.0

	# LoS-blocking terrain (tall/medium ruins, tall woods)
	var blocks_los = (height_cat == "tall") or (height_cat == "medium" and terrain_type == "ruins")

	# Cover-granting terrain
	var grants_cover = terrain_type in ["ruins", "obstacle", "barricade", "woods", "crater", "forest"]

	match role:
		"character":
			# Characters strongly prefer LoS blockers — hide behind tall terrain
			if blocks_los:
				score += 5.0
			if grants_cover:
				score += 2.0
		"fragile_shooter":
			# Fragile shooters want cover and ideally LoS blockers nearby
			# They want to be *next to* LoS blockers (not behind them from their own targets)
			# but behind them from the enemy's perspective
			if blocks_los:
				score += 3.5
			if grants_cover:
				score += 3.0
		"durable_shooter":
			# Durable shooters benefit from cover but don't need to hide as much
			if grants_cover:
				score += 2.5
			if blocks_los:
				score += 1.0
		"melee":
			# Melee units want LoS blockers to advance behind (block enemy shooting)
			# They prefer terrain near the front edge of the deployment zone
			if blocks_los:
				score += 4.0
			if grants_cover:
				score += 1.5
			# Bonus for terrain closer to the front edge (closer to the enemy)
			var front_y = zone_bounds.max_y if is_top_zone else zone_bounds.min_y
			var dist_from_front = abs(pos_near_terrain.y - front_y)
			var zone_height = abs(zone_bounds.max_y - zone_bounds.min_y)
			if zone_height > 0:
				score += 2.0 * (1.0 - clamp(dist_from_front / zone_height, 0.0, 1.0))
		"general":
			# General units get moderate benefit from any terrain
			if grants_cover:
				score += 2.0
			if blocks_los:
				score += 1.5

	# Impassable terrain has no deployment value
	if terrain_type == "impassable":
		return 0.0

	return score

# T7-18: Find the best terrain-aware position for a unit given its role
# Evaluates terrain features near the deployment zone and adjusts the baseline
# position toward beneficial terrain
static func _find_terrain_aware_position(
	baseline_pos: Vector2, role: String, terrain_features: Array,
	zone_bounds: Dictionary, is_top_zone: bool, objectives: Array,
	snapshot: Dictionary, player: int
) -> Vector2:
	if terrain_features.is_empty():
		print("AIDecisionMaker: No terrain features, using baseline position")
		return baseline_pos

	# Determine the front edge of the deployment zone (facing the enemy)
	var front_y = zone_bounds.max_y if is_top_zone else zone_bounds.min_y
	var back_y = zone_bounds.min_y if is_top_zone else zone_bounds.max_y

	# Collect candidate positions near terrain features within/near the deployment zone
	var candidates = []
	var zone_margin = 120.0  # 3" tolerance for terrain just outside the zone

	for terrain in terrain_features:
		var terrain_pos = Vector2.ZERO
		var raw_pos = terrain.get("position", null)
		if raw_pos is Vector2:
			terrain_pos = raw_pos
		elif raw_pos is Dictionary:
			terrain_pos = Vector2(float(raw_pos.get("x", 0)), float(raw_pos.get("y", 0)))
		else:
			# Fallback: compute centroid from polygon
			var polygon = terrain.get("polygon", PackedVector2Array())
			if polygon.size() >= 3:
				var centroid = Vector2.ZERO
				for pt in polygon:
					centroid += pt
				terrain_pos = centroid / polygon.size()
			else:
				continue

		# Check if terrain is within or near the deployment zone
		var in_zone_x = terrain_pos.x >= zone_bounds.min_x - zone_margin and terrain_pos.x <= zone_bounds.max_x + zone_margin
		var in_zone_y = terrain_pos.y >= zone_bounds.min_y - zone_margin and terrain_pos.y <= zone_bounds.max_y + zone_margin
		if not in_zone_x or not in_zone_y:
			continue

		# Calculate candidate positions around this terrain piece
		# Place the unit adjacent to terrain, not inside it (except for area terrain like woods)
		var terrain_size = Vector2.ZERO
		var raw_size = terrain.get("size", null)
		if raw_size is Vector2:
			terrain_size = raw_size
		elif raw_size is Dictionary:
			terrain_size = Vector2(float(raw_size.get("x", 100)), float(raw_size.get("y", 100)))
		else:
			terrain_size = Vector2(100, 100)

		var terrain_type = terrain.get("type", "")
		var is_area_terrain = terrain_type in ["woods", "crater", "forest"]
		var offset_dist = max(terrain_size.x, terrain_size.y) / 2.0 + 60.0  # Adjacent offset

		# Generate candidate positions around the terrain
		var candidate_offsets = []
		if is_area_terrain:
			# Area terrain: deploy within it for cover
			candidate_offsets.append(Vector2.ZERO)
		# For all terrain: positions on the side facing away from the enemy
		if is_top_zone:
			# Enemy is below — "behind" terrain means above it (lower Y)
			candidate_offsets.append(Vector2(0, -offset_dist))  # Behind (away from enemy)
			candidate_offsets.append(Vector2(-offset_dist * 0.7, -offset_dist * 0.7))
			candidate_offsets.append(Vector2(offset_dist * 0.7, -offset_dist * 0.7))
		else:
			# Enemy is above — "behind" terrain means below it (higher Y)
			candidate_offsets.append(Vector2(0, offset_dist))  # Behind (away from enemy)
			candidate_offsets.append(Vector2(-offset_dist * 0.7, offset_dist * 0.7))
			candidate_offsets.append(Vector2(offset_dist * 0.7, offset_dist * 0.7))
		# Also try flanking positions
		candidate_offsets.append(Vector2(-offset_dist, 0))
		candidate_offsets.append(Vector2(offset_dist, 0))

		for offset in candidate_offsets:
			var candidate_pos = terrain_pos + offset
			# Clamp to deployment zone
			candidate_pos.x = clamp(candidate_pos.x, zone_bounds.min_x + 60, zone_bounds.max_x - 60)
			candidate_pos.y = clamp(candidate_pos.y, zone_bounds.min_y + 60, zone_bounds.max_y - 60)

			var terrain_score = _score_terrain_for_role(terrain, role, candidate_pos, zone_bounds, is_top_zone)
			if terrain_score <= 0.0:
				continue

			# Penalize distance from baseline position (don't drift too far from column layout)
			var drift_dist = candidate_pos.distance_to(baseline_pos)
			var drift_penalty = drift_dist / 400.0  # Lose ~1 point per 400px drift

			# Bonus for proximity to objectives
			var obj_bonus = 0.0
			for obj_pos in objectives:
				var obj_dist = candidate_pos.distance_to(obj_pos)
				if obj_dist < 400.0:  # 10 inches
					obj_bonus += 1.0 * (1.0 - obj_dist / 400.0)

			# Role-specific depth preference
			var depth_bonus = 0.0
			if role == "melee":
				# Melee units prefer being near the front edge
				var dist_from_front = abs(candidate_pos.y - front_y)
				depth_bonus = 1.5 * (1.0 - clamp(dist_from_front / (abs(front_y - back_y) + 1.0), 0.0, 1.0))
			elif role == "character" or role == "fragile_shooter":
				# Fragile units prefer being near the back edge
				var dist_from_back = abs(candidate_pos.y - back_y)
				depth_bonus = 1.0 * (1.0 - clamp(dist_from_back / (abs(front_y - back_y) + 1.0), 0.0, 1.0))

			var total_score = terrain_score + obj_bonus + depth_bonus - drift_penalty
			candidates.append({"pos": candidate_pos, "score": total_score, "terrain_type": terrain.get("type", ""), "height": terrain.get("height_category", "")})

	# If no good terrain candidates, fall back to baseline
	if candidates.is_empty():
		print("AIDecisionMaker: No terrain candidates for %s role, using baseline" % role)
		return baseline_pos

	# Sort by score descending and pick the best
	candidates.sort_custom(func(a, b): return a.score > b.score)
	var best = candidates[0]

	# Only use terrain position if it's meaningfully better than baseline
	if best.score < 1.0:
		print("AIDecisionMaker: Best terrain score %.2f too low for %s, using baseline" % [best.score, role])
		return baseline_pos

	print("AIDecisionMaker: T7-18 terrain-aware deploy: %s -> %s terrain (%s), score=%.2f, pos=(%.0f,%.0f)" % [
		role, best.terrain_type, best.height, best.score, best.pos.x, best.pos.y
	])
	return best.pos

# =============================================================================
# SCOUT PHASE
# =============================================================================

static func _decide_scout(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	# AI strategy: Move scout units toward the nearest uncontrolled objective,
	# maintaining >9" from all enemy models. If no valid move exists, skip.

	# Step 1: If CONFIRM_SCOUT_MOVE is available, confirm it
	# (safety fallback — normally AIPlayer handles confirm after staging)
	for action in available_actions:
		if action.get("type") == "CONFIRM_SCOUT_MOVE":
			var uid = action.get("unit_id", "")
			return {
				"type": "CONFIRM_SCOUT_MOVE",
				"unit_id": uid,
				"_ai_description": "Confirm Scout move for %s" % uid
			}

	# Step 2: Find a BEGIN_SCOUT_MOVE action and compute destinations
	for action in available_actions:
		if action.get("type") == "BEGIN_SCOUT_MOVE":
			var unit_id = action.get("unit_id", "")
			var unit = snapshot.get("units", {}).get(unit_id, {})
			if unit.is_empty():
				continue

			var unit_name = unit.get("meta", {}).get("name", unit_id)
			var scout_distance = _get_scout_distance_from_unit(unit)
			if scout_distance <= 0.0:
				scout_distance = 6.0  # Default scout distance

			# Find the best objective to move toward
			var objectives = _get_objectives(snapshot)
			var enemies = _get_enemy_units(snapshot, player)
			var friendly_units = _get_units_for_player(snapshot, player)
			var target_pos = _find_best_scout_objective(unit, objectives, enemies, friendly_units, player, snapshot)

			if target_pos == Vector2.INF:
				print("AIDecisionMaker: No valid scout objective found for %s, skipping" % unit_name)
				return {
					"type": "SKIP_SCOUT_MOVE",
					"unit_id": unit_id,
					"_ai_description": "Skip Scout move for %s (no reachable objective)" % unit_name
				}

			# Compute model destinations toward the target
			var model_destinations = _compute_scout_movement(
				unit, unit_id, target_pos, scout_distance, snapshot, enemies
			)

			if model_destinations.is_empty():
				print("AIDecisionMaker: Could not compute valid scout destinations for %s, skipping" % unit_name)
				return {
					"type": "SKIP_SCOUT_MOVE",
					"unit_id": unit_id,
					"_ai_description": "Skip Scout move for %s (no valid path)" % unit_name
				}

			var centroid = _get_unit_centroid(unit)
			var dist_to_obj = centroid.distance_to(target_pos) / PIXELS_PER_INCH if centroid != Vector2.INF else 0.0

			print("AIDecisionMaker: %s scouting toward objective (%.1f\" away, Scout %d\")" % [
				unit_name, dist_to_obj, int(scout_distance)])

			return {
				"type": "BEGIN_SCOUT_MOVE",
				"unit_id": unit_id,
				"_ai_scout_destinations": model_destinations,
				"_ai_description": "%s scouts toward nearest objective (%.1f\" away)" % [unit_name, dist_to_obj]
			}

	# Step 3: If only SKIP actions remain (no BEGIN), skip remaining units
	for action in available_actions:
		if action.get("type") == "SKIP_SCOUT_MOVE":
			var uid = action.get("unit_id", "")
			return {
				"type": "SKIP_SCOUT_MOVE",
				"unit_id": uid,
				"_ai_description": "Skip Scout move for %s" % uid
			}

	# Step 4: If all scouts handled, end phase
	for action in available_actions:
		if action.get("type") == "END_SCOUT_PHASE":
			return {"type": "END_SCOUT_PHASE", "_ai_description": "End Scout Phase"}

	return {}

# =============================================================================
# SCOUT PHASE HELPERS
# =============================================================================

static func _get_scout_distance_from_unit(unit: Dictionary) -> float:
	"""Extract scout move distance in inches from unit abilities."""
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var aname = ""
		var avalue = 0
		if ability is String:
			aname = ability
		elif ability is Dictionary:
			aname = ability.get("name", "")
			avalue = ability.get("value", 0)
		if aname.to_lower().begins_with("scout"):
			if avalue > 0:
				return float(avalue)
			# Try to parse distance from name, e.g. "Scout 6\"" or "Scout 6"
			var regex = RegEx.new()
			regex.compile("(?i)scout\\s+(\\d+)")
			var result = regex.search(aname)
			if result:
				return float(result.get_string(1))
			return 6.0
	return 0.0

static func _find_best_scout_objective(
	unit: Dictionary, objectives: Array, enemies: Dictionary,
	friendly_units: Dictionary, player: int, snapshot: Dictionary
) -> Vector2:
	"""Find the best objective for a scout unit to move toward.
	Prioritizes: uncontrolled > contested > enemy-weak objectives, with distance as tiebreaker.
	Avoids objectives that are already well-held by friendlies."""
	var centroid = _get_unit_centroid(unit)
	if centroid == Vector2.INF or objectives.is_empty():
		return Vector2.INF

	var obj_data = snapshot.get("board", {}).get("objectives", [])

	var best_pos = Vector2.INF
	var best_score = -INF

	for i in range(objectives.size()):
		var obj_pos = objectives[i]

		# Classify the objective
		var friendly_oc = _get_oc_at_position(obj_pos, friendly_units, player, true)
		var enemy_oc = _get_oc_at_position(obj_pos, enemies, player, false)
		var dist = centroid.distance_to(obj_pos)
		var dist_inches = dist / PIXELS_PER_INCH

		# Determine zone
		var obj_zone = "no_mans_land"
		if i < obj_data.size():
			obj_zone = obj_data[i].get("zone", "no_mans_land")

		var is_home = (player == 1 and obj_zone == "player1") or (player == 2 and obj_zone == "player2")
		var is_enemy_home = (player == 1 and obj_zone == "player2") or (player == 2 and obj_zone == "player1")

		# Score this objective for scouting
		var score = 0.0

		# Uncontrolled objectives are highest priority for scouts
		if friendly_oc == 0 and enemy_oc == 0:
			score += 10.0
		# Objectives not yet secured by friendlies
		elif friendly_oc == 0 and enemy_oc > 0:
			score += 7.0  # Enemy holds it, scout can get there first
		elif friendly_oc > 0 and friendly_oc <= enemy_oc:
			score += 5.0  # Contested, reinforce
		elif friendly_oc > enemy_oc and friendly_oc > 0:
			score -= 5.0  # Already held, lower priority

		# Prefer no-man's-land objectives (center of the board)
		if obj_zone == "no_mans_land":
			score += 3.0
		# Home objectives are less valuable to scout toward (already nearby)
		if is_home:
			score -= 4.0
		# Don't rush enemy home objectives with scouts
		if is_enemy_home:
			score -= 2.0

		# Closer objectives score better (within scout range is ideal)
		score -= dist_inches * 0.3

		if score > best_score:
			best_score = score
			best_pos = obj_pos

	return best_pos

static func _compute_scout_movement(
	unit: Dictionary, unit_id: String, target_pos: Vector2,
	scout_distance_inches: float, snapshot: Dictionary, enemies: Dictionary
) -> Dictionary:
	"""Compute model destinations for a scout move toward target_pos.
	Respects: scout distance limit, >9\" from all enemy models, board bounds, model overlap."""
	if target_pos == Vector2.INF:
		return {}

	var alive_models = _get_alive_models_with_positions(unit)
	if alive_models.is_empty():
		return {}

	var centroid = _get_unit_centroid(unit)
	if centroid == Vector2.INF:
		return {}

	# Calculate movement vector toward target
	var direction = (target_pos - centroid).normalized()
	var move_px = scout_distance_inches * PIXELS_PER_INCH
	var dist_to_target = centroid.distance_to(target_pos)
	var actual_move_px = min(move_px, dist_to_target)
	var move_vector = direction * actual_move_px

	# Get deployed models for overlap checking
	var deployed_models = _get_deployed_models_excluding_unit(snapshot, unit_id)
	var first_model = alive_models[0] if alive_models.size() > 0 else {}
	var base_mm = first_model.get("base_mm", 32)
	var base_type = first_model.get("base_type", "circular")
	var base_dimensions = first_model.get("base_dimensions", {})

	# Build original positions map
	var original_positions = {}
	for model in alive_models:
		var mid = model.get("id", "")
		if mid != "":
			original_positions[mid] = _get_model_position(model)

	# Try the full move first, then progressively shorter moves
	var fractions_to_try = [1.0, 0.75, 0.5, 0.25]
	for fraction in fractions_to_try:
		var try_vector = move_vector * fraction
		var destinations = _try_scout_move_with_checks(
			alive_models, try_vector, enemies, unit, deployed_models,
			base_mm, base_type, base_dimensions, original_positions, move_px
		)
		if not destinations.is_empty():
			if fraction < 1.0:
				print("AIDecisionMaker: Scout using %.0f%% move to satisfy constraints" % (fraction * 100))
			return destinations

	# All fractions failed
	return {}

static func _try_scout_move_with_checks(
	alive_models: Array, move_vector: Vector2, enemies: Dictionary,
	unit: Dictionary, deployed_models: Array, base_mm: int,
	base_type: String, base_dimensions: Dictionary,
	original_positions: Dictionary = {}, move_cap_px: float = 0.0
) -> Dictionary:
	"""Try moving all models by move_vector, checking the >9\" enemy distance rule
	and model overlap. Returns model_id -> [x, y] destinations, or empty dict if invalid."""
	const SCOUT_ENEMY_DIST_INCHES: float = 9.0
	var destinations = {}
	var placed_models: Array = []

	var own_models = unit.get("models", [])
	var own_base_mm = own_models[0].get("base_mm", 32) if own_models.size() > 0 else 32
	var own_radius_inches = (own_base_mm / 2.0) / 25.4

	for model in alive_models:
		var model_id = model.get("id", "")
		if model_id == "":
			continue
		var model_pos = _get_model_position(model)
		if model_pos == Vector2.INF:
			continue
		var dest = model_pos + move_vector

		# Clamp to board bounds with margin
		dest.x = clamp(dest.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
		dest.y = clamp(dest.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)

		# Check movement distance does not exceed scout distance
		if move_cap_px > 0.0:
			var orig_pos = original_positions.get(model_id, model_pos)
			if orig_pos.distance_to(dest) > move_cap_px + 1.0:  # Small tolerance
				return {}

		# Check >9" from all enemy models (edge-to-edge)
		if _is_position_too_close_to_enemies_scout(dest, enemies, own_radius_inches, SCOUT_ENEMY_DIST_INCHES):
			return {}

		# Check overlap with deployed models and already-placed models
		var all_obstacles = deployed_models + placed_models
		if _position_collides_with_deployed(dest, base_mm, all_obstacles, 4.0, base_type, base_dimensions):
			# Try small perpendicular offsets to avoid the collision
			var orig_pos = original_positions.get(model_id, model_pos)
			var resolved_dest = _resolve_scout_collision(
				dest, move_vector, base_mm, base_type, base_dimensions,
				all_obstacles, enemies, own_radius_inches, SCOUT_ENEMY_DIST_INCHES,
				orig_pos, move_cap_px
			)
			if resolved_dest == Vector2.INF:
				return {}
			dest = resolved_dest

		destinations[model_id] = [dest.x, dest.y]
		placed_models.append({
			"position": dest,
			"base_mm": base_mm,
			"base_type": base_type,
			"base_dimensions": base_dimensions
		})

	return destinations

static func _is_position_too_close_to_enemies_scout(
	pos: Vector2, enemies: Dictionary,
	own_radius_inches: float, min_distance_inches: float
) -> bool:
	"""Check if a position is within min_distance_inches (edge-to-edge) of any enemy model.
	Used for scout moves where the minimum distance is 9\"."""
	for enemy_id in enemies:
		var enemy = enemies[enemy_id]
		for model in enemy.get("models", []):
			if not model.get("alive", true):
				continue
			var enemy_pos = _get_model_position(model)
			if enemy_pos == Vector2.INF:
				continue
			var enemy_base_mm = model.get("base_mm", 32)
			var enemy_radius_inches = (enemy_base_mm / 2.0) / 25.4
			var dist_px = pos.distance_to(enemy_pos)
			var dist_inches = dist_px / PIXELS_PER_INCH
			var edge_dist = dist_inches - own_radius_inches - enemy_radius_inches
			if edge_dist < min_distance_inches:
				return true
	return false

static func _resolve_scout_collision(
	dest: Vector2, move_vector: Vector2, base_mm: int,
	base_type: String, base_dimensions: Dictionary,
	obstacles: Array, enemies: Dictionary,
	own_radius_inches: float, min_enemy_dist_inches: float,
	original_pos: Vector2 = Vector2.INF, move_cap_px: float = 0.0
) -> Vector2:
	"""Try perpendicular offsets to avoid collision while satisfying scout >9\" rule."""
	var perp = Vector2(-move_vector.y, move_vector.x).normalized()
	var base_radius = _model_bounding_radius_px(base_mm, base_type, base_dimensions)
	var offsets = [1.0, -1.0, 2.0, -2.0, 3.0, -3.0]

	for multiplier in offsets:
		var offset = perp * base_radius * multiplier
		var candidate = dest + offset

		# Check board bounds
		if candidate.x < BASE_MARGIN_PX or candidate.x > BOARD_WIDTH_PX - BASE_MARGIN_PX:
			continue
		if candidate.y < BASE_MARGIN_PX or candidate.y > BOARD_HEIGHT_PX - BASE_MARGIN_PX:
			continue

		# Check movement cap
		if original_pos != Vector2.INF and move_cap_px > 0.0:
			if original_pos.distance_to(candidate) > move_cap_px + 1.0:
				continue

		# Check model overlap
		if _position_collides_with_deployed(candidate, base_mm, obstacles, 4.0, base_type, base_dimensions):
			continue

		# Check >9" from enemies
		if _is_position_too_close_to_enemies_scout(candidate, enemies, own_radius_inches, min_enemy_dist_inches):
			continue

		return candidate

	return Vector2.INF

# =============================================================================
# COMMAND PHASE
# =============================================================================

static func _decide_command(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	# Handle pending Command Re-roll decisions first
	# Note: The AIPlayer signal handler (_on_command_reroll_opportunity) handles this
	# with full roll context. This is a fallback in case available_actions still shows
	# the reroll options (e.g., if the signal handler hasn't fired yet).
	for action in available_actions:
		if action.get("type") == "USE_COMMAND_REROLL" or action.get("type") == "DECLINE_COMMAND_REROLL":
			# Fallback: decline the reroll (signal handler with context should have acted)
			var uid = action.get("actor_unit_id", action.get("unit_id", ""))
			return {
				"type": "DECLINE_COMMAND_REROLL",
				"actor_unit_id": uid,
				"_ai_description": "Decline Command Re-roll (command phase fallback)"
			}

	# Take any pending battle-shock tests
	for action in available_actions:
		if action.get("type") == "BATTLE_SHOCK_TEST":
			return {
				"type": "BATTLE_SHOCK_TEST",
				"unit_id": action.get("unit_id", ""),
				"_ai_description": "Battle-shock test"
			}

	# All tests done, end command phase
	return {"type": "END_COMMAND", "_ai_description": "End Command Phase"}

# =============================================================================
# MOVEMENT PHASE
# =============================================================================

static func _decide_movement(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	var action_types = {}
	for a in available_actions:
		var t = a.get("type", "")
		if not action_types.has(t):
			action_types[t] = []
		action_types[t].append(a)

	# Step 0: Handle pending Command Re-roll decisions first (advance rolls)
	# The AIPlayer signal handler handles this with full context. This is a fallback.
	if action_types.has("USE_COMMAND_REROLL") or action_types.has("DECLINE_COMMAND_REROLL"):
		var uid = ""
		if action_types.has("USE_COMMAND_REROLL"):
			uid = action_types["USE_COMMAND_REROLL"][0].get("actor_unit_id", "")
		elif action_types.has("DECLINE_COMMAND_REROLL"):
			uid = action_types["DECLINE_COMMAND_REROLL"][0].get("actor_unit_id", "")
		return {
			"type": "DECLINE_COMMAND_REROLL",
			"actor_unit_id": uid,
			"_ai_description": "Decline Command Re-roll (movement phase fallback)"
		}

	# Step 1: If CONFIRM_UNIT_MOVE is available, confirm it
	# (safety fallback — normally AIPlayer handles confirm after staging)
	if action_types.has("CONFIRM_UNIT_MOVE"):
		var a = action_types["CONFIRM_UNIT_MOVE"][0]
		var uid = a.get("actor_unit_id", a.get("unit_id", ""))
		return {
			"type": "CONFIRM_UNIT_MOVE",
			"actor_unit_id": uid,
			"_ai_description": "Confirmed move"
		}

	# Step 1.5: Deploy reserves (reinforcements) before normal movement (MOV-8 / T7-16)
	# From Battle Round 2+, units in reserves can arrive on the battlefield.
	# Deploy them before moving other units so they participate in the turn.
	if action_types.has("PLACE_REINFORCEMENT"):
		var reinforcement_decision = _decide_reserves_arrival(snapshot, action_types["PLACE_REINFORCEMENT"], player)
		if not reinforcement_decision.is_empty():
			return reinforcement_decision

	# Step 1.75: Disembark units from transports before normal movement (T7-33 / MOV-7)
	# Check if any embarked units should disembark. Disembark before moving transports
	# so disembarked units can still move (if transport hasn't moved yet).
	var disembark_decision = _decide_transport_disembark(snapshot, player)
	if not disembark_decision.is_empty():
		return disembark_decision

	# Step 2: Check if any unit can begin moving
	var begin_types = ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "BEGIN_FALL_BACK", "REMAIN_STATIONARY"]
	var can_begin = false
	for bt in begin_types:
		if action_types.has(bt):
			can_begin = true
			break

	if can_begin:
		return _select_movement_action(snapshot, available_actions, player)

	# Step 3: End movement phase
	return {"type": "END_MOVEMENT", "_ai_description": "End Movement Phase"}

static func _select_movement_action(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	# Collect units that can begin moving
	var movable_units = {}  # unit_id -> list of available move types
	for a in available_actions:
		var t = a.get("type", "")
		if t in ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "BEGIN_FALL_BACK", "REMAIN_STATIONARY"]:
			var uid = a.get("actor_unit_id", a.get("unit_id", ""))
			if uid != "":
				if not movable_units.has(uid):
					movable_units[uid] = []
				movable_units[uid].append(t)

	if movable_units.is_empty():
		return {"type": "END_MOVEMENT", "_ai_description": "End Movement Phase"}

	var objectives = _get_objectives(snapshot)
	var enemies = _get_enemy_units(snapshot, player)
	var friendly_units = _get_units_for_player(snapshot, player)
	var battle_round = snapshot.get("battle_round", 1)

	# =========================================================================
	# T7-23: BUILD MULTI-PHASE PLAN (once per movement phase)
	# =========================================================================
	if not _phase_plan_built:
		_phase_plan = _build_phase_plan(snapshot, player)
		_phase_plan_built = true
		_phase_plan_round = battle_round

	# =========================================================================
	# THREAT DATA: Calculate enemy threat zones once for all units (AI-TACTIC-4)
	# T7-40: Only Normal+ difficulty uses threat awareness for positioning
	# =========================================================================
	var threat_data = []
	if AIDifficultyConfigData.use_threat_awareness(_current_difficulty):
		threat_data = _calculate_enemy_threat_data(enemies)
	if not threat_data.is_empty():
		print("AIDecisionMaker: Calculated threat data for %d enemy units" % threat_data.size())
		for td in threat_data:
			print("  Enemy %s: charge_threat=%.1f\", shoot_threat=%.1f\", value=%.1f" % [
				td.unit_id, td.charge_threat_px / PIXELS_PER_INCH,
				td.shoot_threat_px / PIXELS_PER_INCH, td.unit_value])

	# =========================================================================
	# PHASE 1: GLOBAL OBJECTIVE EVALUATION
	# =========================================================================
	var obj_evaluations = _evaluate_all_objectives(snapshot, objectives, player, enemies, friendly_units, battle_round)

	# =========================================================================
	# PHASE 2: UNIT-TO-OBJECTIVE ASSIGNMENT (with threat awareness)
	# =========================================================================
	var assignments = _assign_units_to_objectives(
		snapshot, movable_units, obj_evaluations, objectives, enemies, friendly_units, player, battle_round, threat_data
	)

	# =========================================================================
	# PHASE 3: EXECUTE BEST ASSIGNMENT
	# =========================================================================
	# Process units: engaged units first (must decide immediately), then by assignment priority
	var engaged_units = []
	var assigned_units = []

	for unit_id in movable_units:
		var move_types = movable_units[unit_id]
		var is_engaged = "BEGIN_FALL_BACK" in move_types and not "BEGIN_NORMAL_MOVE" in move_types
		if is_engaged:
			engaged_units.append(unit_id)
		else:
			assigned_units.append(unit_id)

	# --- Handle engaged units first ---
	for unit_id in engaged_units:
		var unit = snapshot.get("units", {}).get(unit_id, {})
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		var move_types = movable_units[unit_id]
		var decision = _decide_engaged_unit(unit, unit_id, unit_name, move_types, objectives, enemies, snapshot, player)
		if not decision.is_empty():
			return decision

	# --- Sort assigned units by priority (highest assignment score first) ---
	# T7-40: Apply difficulty noise to assignment scores for ordering
	assigned_units.sort_custom(func(a, b):
		var score_a = _apply_difficulty_noise(assignments.get(a, {}).get("score", 0.0))
		var score_b = _apply_difficulty_noise(assignments.get(b, {}).get("score", 0.0))
		return score_a > score_b
	)

	for unit_id in assigned_units:
		var unit = snapshot.get("units", {}).get(unit_id, {})
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		var move_types = movable_units[unit_id]
		var assignment = assignments.get(unit_id, {})
		var assigned_obj_pos = assignment.get("objective_pos", Vector2.INF)
		var assigned_obj_id = assignment.get("objective_id", "")
		var assignment_action = assignment.get("action", "move")  # "hold", "move", "advance", "screen"

		# --- OC-AWARE HOLD DECISION ---
		if assignment_action == "hold":
			if "REMAIN_STATIONARY" in move_types:
				var dist_inches = assignment.get("distance", 0.0) / PIXELS_PER_INCH
				var reason = assignment.get("reason", "holding objective")
				print("AIDecisionMaker: %s holds %s (%s, %.1f\" away)" % [unit_name, assigned_obj_id, reason, dist_inches])
				return {
					"type": "REMAIN_STATIONARY",
					"actor_unit_id": unit_id,
					"_ai_description": "%s holds %s (%s)" % [unit_name, assigned_obj_id, reason]
				}

		# --- ADVANCE DECISION ---
		if assignment_action == "advance" and "BEGIN_ADVANCE" in move_types:
			var move_inches = float(unit.get("meta", {}).get("stats", {}).get("move", 6))
			var advance_move = move_inches + 2.0  # Average advance roll
			var target_pos = assigned_obj_pos if assigned_obj_pos != Vector2.INF else _nearest_objective_pos(_get_unit_centroid(unit), objectives)
			var model_destinations = _compute_movement_toward_target(
				unit, unit_id, target_pos, advance_move, snapshot, enemies,
				0.0, threat_data, objectives
			)
			if not model_destinations.is_empty():
				var reason = assignment.get("reason", "needs extra distance")
				print("AIDecisionMaker: %s advances toward %s (%s)" % [unit_name, assigned_obj_id, reason])
				return {
					"type": "BEGIN_ADVANCE",
					"actor_unit_id": unit_id,
					"_ai_model_destinations": model_destinations,
					"_ai_description": "%s advances toward %s (%s)" % [unit_name, assigned_obj_id, reason]
				}

		# --- SCREEN MOVE toward denial/screening position (AI-TACTIC-3, MOV-4) ---
		if assignment_action == "screen" and "BEGIN_NORMAL_MOVE" in move_types:
			var move_inches = float(unit.get("meta", {}).get("stats", {}).get("move", 6))
			var screen_centroid = _get_unit_centroid(unit)
			var screen_target = assigned_obj_pos
			if screen_target != Vector2.INF and screen_centroid != Vector2.INF:
				# If already within 1" of screen position, remain stationary
				if screen_centroid.distance_to(screen_target) <= ENGAGEMENT_RANGE_PX:
					if "REMAIN_STATIONARY" in move_types:
						var reason = assignment.get("reason", "screening position reached")
						print("AIDecisionMaker: [SCREEN] %s at screening position (%.1f\" away)" % [unit_name, screen_centroid.distance_to(screen_target) / PIXELS_PER_INCH])
						return {
							"type": "REMAIN_STATIONARY",
							"actor_unit_id": unit_id,
							"_ai_description": "%s holds screening position (%s)" % [unit_name, reason]
						}
				var model_destinations = _compute_movement_toward_target(
					unit, unit_id, screen_target, move_inches, snapshot, enemies,
					0.0, [], objectives  # No threat avoidance for screeners — they're expendable
				)
				if not model_destinations.is_empty():
					var reason = assignment.get("reason", "screening")
					var dist_inches = screen_centroid.distance_to(screen_target) / PIXELS_PER_INCH
					print("AIDecisionMaker: [SCREEN] %s moving to screen position (%s, %.1f\" away)" % [unit_name, reason, dist_inches])
					return {
						"type": "BEGIN_NORMAL_MOVE",
						"actor_unit_id": unit_id,
						"_ai_model_destinations": model_destinations,
						"_ai_description": "%s screens at (%.0f,%.0f) — %s" % [unit_name, screen_target.x, screen_target.y, reason]
					}
			# Fall through to normal move if screen position is unreachable

		# --- NORMAL MOVE toward assigned objective ---
		if "BEGIN_NORMAL_MOVE" in move_types:
			var move_inches = float(unit.get("meta", {}).get("stats", {}).get("move", 6))
			var centroid = _get_unit_centroid(unit)
			if centroid == Vector2.INF:
				continue
			var target_pos = assigned_obj_pos if assigned_obj_pos != Vector2.INF else _nearest_objective_pos(centroid, objectives)

			# If we're already within control range and assigned to hold, remain stationary
			if target_pos != Vector2.INF and centroid.distance_to(target_pos) <= OBJECTIVE_CONTROL_RANGE_PX:
				if "REMAIN_STATIONARY" in move_types:
					var dist_inches = centroid.distance_to(target_pos) / PIXELS_PER_INCH
					print("AIDecisionMaker: %s within control range of %s (%.1f\"), holding" % [unit_name, assigned_obj_id, dist_inches])
					return {
						"type": "REMAIN_STATIONARY",
						"actor_unit_id": unit_id,
						"_ai_description": "%s holds %s (%.1f\" away)" % [unit_name, assigned_obj_id, dist_inches]
					}

			# --- AI-TACTIC-4: Threat-aware hold check ---
			# Ranged units currently safe from charge threat should avoid moving
			# into charge range if the objective is far away and they have targets to shoot
			if not threat_data.is_empty() and "REMAIN_STATIONARY" in move_types:
				var has_ranged_for_threat = _unit_has_ranged_weapons(unit)
				var is_melee_unit = _unit_has_melee_weapons(unit) and not has_ranged_for_threat
				if has_ranged_for_threat and not is_melee_unit:
					var current_threat_eval = _evaluate_position_threat(centroid, threat_data, unit)
					# Estimate where we'd end up
					var move_dir = (target_pos - centroid).normalized() if centroid.distance_to(target_pos) > 1.0 else Vector2.ZERO
					var est_dest = centroid + move_dir * min(move_inches * PIXELS_PER_INCH, centroid.distance_to(target_pos))
					var dest_threat_eval = _evaluate_position_threat(est_dest, threat_data, unit)
					# If we're currently safe from charges but would move into charge range,
					# and we have shooting targets, consider staying put
					if current_threat_eval.charge_threat < 0.5 and dest_threat_eval.charge_threat >= 2.0:
						var max_wr = _get_max_weapon_range(unit)
						var has_shoot_targets = false
						for eid in enemies:
							var ec = _get_unit_centroid(enemies[eid])
							if ec != Vector2.INF and centroid.distance_to(ec) <= max_wr * PIXELS_PER_INCH:
								has_shoot_targets = true
								break
						if has_shoot_targets:
							print("AIDecisionMaker: %s avoiding charge danger — staying to shoot (charge threat would increase from %.1f to %.1f)" % [
								unit_name, current_threat_eval.charge_threat, dest_threat_eval.charge_threat])
							return {
								"type": "REMAIN_STATIONARY",
								"actor_unit_id": unit_id,
								"_ai_description": "%s holds position (avoiding charge threat, has shooting targets)" % unit_name
							}

			# --- MOV-1: Shooting range consideration ---
			# If the unit has ranged weapons and enemies in range, check if moving
			# would take it out of weapon range. Prefer holding for shooting if objective
			# is far away and we'd lose all targets.
			var has_ranged_weapons = _unit_has_ranged_weapons(unit)
			var max_weapon_range_inches = _get_max_weapon_range(unit) if has_ranged_weapons else 0.0
			if has_ranged_weapons and "REMAIN_STATIONARY" in move_types:
				if _should_hold_for_shooting(unit, centroid, target_pos, max_weapon_range_inches, enemies, move_inches, assignment):
					var enemies_in_range = _get_enemies_in_weapon_range(centroid, max_weapon_range_inches, enemies)
					return {
						"type": "REMAIN_STATIONARY",
						"actor_unit_id": unit_id,
						"_ai_description": "%s holds position for shooting (%d targets in %.0f\" range, obj %s too far)" % [
							unit_name, enemies_in_range.size(), max_weapon_range_inches, assigned_obj_id]
					}

			# --- T7-23: Charge-intent-aware movement target ---
			# If this unit intends to charge, blend the movement target toward
			# the charge target to set up a good charge angle
			var move_target = target_pos
			var charge_intent = _get_charge_intent(unit_id)
			if not charge_intent.is_empty():
				var charge_target_id = charge_intent.get("target_id", "")
				if charge_target_id != "" and enemies.has(charge_target_id):
					var charge_target = enemies[charge_target_id]
					var charge_centroid = _get_unit_centroid(charge_target)
					if charge_centroid != Vector2.INF:
						# Move toward charge target, but try to stay near objectives
						var dist_to_charge = centroid.distance_to(charge_centroid) / PIXELS_PER_INCH
						if dist_to_charge <= move_inches + 12.0:  # Within move + charge range
							# Blend: 70% toward charge target, 30% toward objective
							if target_pos != Vector2.INF:
								move_target = charge_centroid * 0.7 + target_pos * 0.3
							else:
								move_target = charge_centroid
							print("AIDecisionMaker: [PHASE-PLAN] %s blending movement toward charge target %s" % [
								unit_name, charge_intent.get("target_name", charge_target_id)])

			# --- T7-30: Half-range optimization for Rapid Fire/Melta ---
			# If this unit has weapons that benefit from half range and isn't planning
			# to charge, adjust movement to close to half range of the best target.
			if charge_intent.is_empty():
				var half_range_data = _get_unit_half_range_data(unit)
				if half_range_data.has_bonus and half_range_data.total_benefit >= HALF_RANGE_MIN_BENEFIT:
					var half_range_pos = _find_best_half_range_position(centroid, enemies, half_range_data, snapshot, unit)
					if half_range_pos != Vector2.INF:
						if move_target != Vector2.INF:
							move_target = half_range_pos * HALF_RANGE_MOVE_BLEND + move_target * (1.0 - HALF_RANGE_MOVE_BLEND)
						else:
							move_target = half_range_pos
						var hr_dist = centroid.distance_to(half_range_pos) / PIXELS_PER_INCH
						var weapon_names = []
						for w_data in half_range_data.weapons:
							var label = w_data.name
							if w_data.rapid_fire > 0:
								label += " (RF%d)" % w_data.rapid_fire
							if w_data.melta > 0:
								label += " (Melta%d)" % w_data.melta
							weapon_names.append(label)
						print("AIDecisionMaker: [T7-30] %s blending movement toward half range (%.1f\" away) for %s" % [
							unit_name, hr_dist, ", ".join(weapon_names)])

			var model_destinations = _compute_movement_toward_target(
				unit, unit_id, move_target, move_inches, snapshot, enemies,
				max_weapon_range_inches, threat_data, objectives
			)

			if not model_destinations.is_empty():
				var obj_dist_inches = centroid.distance_to(target_pos) / PIXELS_PER_INCH if target_pos != Vector2.INF else 0.0
				var reason = assignment.get("reason", "moving to objective")
				if not charge_intent.is_empty():
					reason = "moving toward charge target %s" % charge_intent.get("target_name", "")
				print("AIDecisionMaker: %s moving toward %s (%s, M: %.0f\")" % [unit_name, assigned_obj_id, reason, move_inches])
				return {
					"type": "BEGIN_NORMAL_MOVE",
					"actor_unit_id": unit_id,
					"_ai_model_destinations": model_destinations,
					"_ai_description": "%s moves toward %s (%s, obj: %.1f\" away)" % [unit_name, assigned_obj_id, reason, obj_dist_inches]
				}
			else:
				print("AIDecisionMaker: %s cannot find valid move toward %s" % [unit_name, assigned_obj_id])

		# --- Fallback: remain stationary ---
		if "REMAIN_STATIONARY" in move_types:
			var reason = assignment.get("reason", "no valid move found")
			return {
				"type": "REMAIN_STATIONARY",
				"actor_unit_id": unit_id,
				"_ai_description": "%s remains stationary (%s)" % [unit_name, reason]
			}

	return {"type": "END_MOVEMENT", "_ai_description": "End Movement Phase"}

# =============================================================================
# RESERVES ARRIVAL (T7-16 / MOV-8)
# =============================================================================

static func _decide_reserves_arrival(snapshot: Dictionary, reinforcement_actions: Array, player: int) -> Dictionary:
	"""Decide which reserve unit to deploy and where to place it.
	Called during the movement phase from Round 2+ when PLACE_REINFORCEMENT actions are available."""
	var battle_round = snapshot.get("battle_round", 1)
	var objectives = _get_objectives(snapshot)
	var enemies = _get_enemy_units(snapshot, player)

	print("AIDecisionMaker: [RESERVES] Evaluating %d units in reserves for deployment (Round %d)" % [reinforcement_actions.size(), battle_round])

	# Build enemy model positions for distance checks
	var enemy_model_positions = _get_enemy_model_positions_from_snapshot(snapshot, player)

	# Score each reserve unit for deployment priority
	var scored_units = []
	for action in reinforcement_actions:
		var unit_id = action.get("unit_id", "")
		var unit = snapshot.get("units", {}).get(unit_id, {})
		if unit.is_empty():
			continue

		var unit_name = unit.get("meta", {}).get("name", unit_id)
		var reserve_type = unit.get("reserve_type", "strategic_reserves")
		var points = int(unit.get("meta", {}).get("points", 0))

		# Calculate deployment priority score
		var score = _score_reserves_deployment(unit, unit_id, reserve_type, objectives, enemies, snapshot, player, battle_round)

		print("AIDecisionMaker: [RESERVES]   %s (%s, %dpts) — deployment score: %.1f" % [unit_name, reserve_type, points, score])

		scored_units.append({
			"unit_id": unit_id,
			"unit": unit,
			"reserve_type": reserve_type,
			"score": score,
			"name": unit_name
		})

	# Sort by score (highest first)
	scored_units.sort_custom(func(a, b): return a.score > b.score)

	# Try to deploy the highest-priority unit
	for candidate in scored_units:
		var unit_id = candidate.unit_id
		var unit = candidate.unit
		var reserve_type = candidate.reserve_type
		var unit_name = candidate.name

		# Compute valid placement positions
		var positions = _compute_reinforcement_positions(
			unit, unit_id, reserve_type, snapshot, player, objectives, enemies, enemy_model_positions, battle_round
		)

		if positions.is_empty():
			print("AIDecisionMaker: [RESERVES]   %s — no valid placement found, skipping" % unit_name)
			continue

		# Generate model formation around the chosen centroid
		var models = unit.get("models", [])
		var alive_count = 0
		for m in models:
			if m.get("alive", true):
				alive_count += 1

		var first_model = models[0] if models.size() > 0 else {}
		var base_mm = first_model.get("base_mm", 32)
		var base_type = first_model.get("base_type", "circular")
		var base_dimensions = first_model.get("base_dimensions", {})

		# Use a generous zone bounds for formation generation (the whole board minus margins)
		var placement_bounds = _get_reinforcement_zone_bounds(reserve_type, player, snapshot, battle_round)
		var model_positions = _generate_formation_positions(positions[0], alive_count, base_mm, placement_bounds)

		# Resolve collisions with existing models
		var deployed_models = _get_all_deployed_model_positions(snapshot)
		model_positions = _resolve_formation_collisions(model_positions, base_mm, deployed_models, placement_bounds, base_type, base_dimensions)

		# Validate all positions satisfy the 9" enemy distance rule
		var all_valid = true
		for pos in model_positions:
			if not _is_valid_reinforcement_position(pos, base_mm, enemy_model_positions, reserve_type, placement_bounds, snapshot, player, battle_round):
				all_valid = false
				break

		if not all_valid:
			# Try alternate positions from our candidate list
			var found_valid = false
			for pi in range(1, positions.size()):
				model_positions = _generate_formation_positions(positions[pi], alive_count, base_mm, placement_bounds)
				model_positions = _resolve_formation_collisions(model_positions, base_mm, deployed_models, placement_bounds, base_type, base_dimensions)
				var valid = true
				for pos in model_positions:
					if not _is_valid_reinforcement_position(pos, base_mm, enemy_model_positions, reserve_type, placement_bounds, snapshot, player, battle_round):
						valid = false
						break
				if valid:
					found_valid = true
					break
			if not found_valid:
				print("AIDecisionMaker: [RESERVES]   %s — no valid formation placement, skipping" % unit_name)
				continue

		# Build the full model_positions array (including dead models as null)
		var full_positions = []
		var alive_idx = 0
		for i in range(models.size()):
			if models[i].get("alive", true) and alive_idx < model_positions.size():
				full_positions.append(model_positions[alive_idx])
				alive_idx += 1
			else:
				full_positions.append(null)

		var rotations = []
		for i in range(models.size()):
			rotations.append(0.0)

		var type_label = "Deep Strike" if reserve_type == "deep_strike" else "Strategic Reserves"
		print("AIDecisionMaker: [RESERVES] Deploying %s via %s at (%.0f, %.0f)" % [
			unit_name, type_label, positions[0].x, positions[0].y])

		return {
			"type": "PLACE_REINFORCEMENT",
			"unit_id": unit_id,
			"model_positions": full_positions,
			"model_rotations": rotations,
			"_ai_description": "%s arrives from %s" % [unit_name, type_label]
		}

	print("AIDecisionMaker: [RESERVES] No reserve units could be deployed this turn")
	return {}

static func _score_reserves_deployment(unit: Dictionary, unit_id: String, reserve_type: String,
		objectives: Array, enemies: Dictionary, snapshot: Dictionary, player: int, battle_round: int) -> float:
	"""Score how urgently a reserve unit should be deployed.
	Higher score = deploy sooner."""
	var score = 0.0
	var points = int(unit.get("meta", {}).get("points", 0))
	var has_ranged = _unit_has_ranged_weapons(unit)
	var has_melee = _unit_has_melee_weapons(unit)

	# Base priority: more expensive units are more impactful
	score += points / 50.0

	# Deep strike units get a slight priority (they can be placed more flexibly)
	if reserve_type == "deep_strike":
		score += 2.0

	# Melee units benefit from arriving to charge next turn
	if has_melee:
		score += 1.5

	# Ranged units benefit from shooting immediately after arrival
	if has_ranged:
		score += 1.0

	# Round urgency: later rounds increase urgency (must deploy by Round 5 or lose the unit)
	if battle_round >= 4:
		score += 5.0  # Critical — last chance on Round 5
	elif battle_round >= 3:
		score += 2.0

	# Check if there are contested objectives that need reinforcement
	var friendly_units = _get_units_for_player(snapshot, player)
	var obj_evaluations = _evaluate_all_objectives(snapshot, objectives, player, enemies, friendly_units, battle_round)
	for eval in obj_evaluations:
		var obj_state = eval.get("state", "")
		if obj_state in ["contested", "enemy_held"]:
			score += 1.5  # Contested objectives benefit from reinforcement
		elif obj_state == "uncontested":
			score += 0.5

	return score

static func _compute_reinforcement_positions(unit: Dictionary, unit_id: String, reserve_type: String,
		snapshot: Dictionary, player: int, objectives: Array, enemies: Dictionary,
		enemy_model_positions: Array, battle_round: int) -> Array:
	"""Compute candidate centroid positions for placing a reserve unit.
	Returns an array of Vector2 positions sorted by tactical value (best first)."""
	var candidates = []
	var first_model = unit.get("models", [{}])[0]
	var base_mm = first_model.get("base_mm", 32)
	# Conservative radius check: 9" + own base radius (in pixels)
	var base_radius_px = (base_mm / 2.0) * (PIXELS_PER_INCH / 25.4)
	var min_enemy_dist_px = 9.0 * PIXELS_PER_INCH + base_radius_px + 25.0  # 25px (~0.6") extra buffer for enemy bases

	if reserve_type == "strategic_reserves":
		candidates = _generate_strategic_reserves_candidates(snapshot, player, objectives, enemies, enemy_model_positions, min_enemy_dist_px, battle_round)
	else:
		# Deep strike: can be placed anywhere on the board >9" from enemies
		candidates = _generate_deep_strike_candidates(snapshot, player, objectives, enemies, enemy_model_positions, min_enemy_dist_px)

	return candidates

static func _generate_strategic_reserves_candidates(snapshot: Dictionary, player: int,
		objectives: Array, enemies: Dictionary, enemy_model_positions: Array,
		min_enemy_dist_px: float, battle_round: int) -> Array:
	"""Generate candidate positions for strategic reserves (within 6\" of board edge)."""
	var candidates = []
	var edge_margin_px = 3.0 * PIXELS_PER_INCH  # Place 3" from edge (safely within the 6" limit)
	var step_px = 4.0 * PIXELS_PER_INCH  # Sample every 4 inches along the edge

	# Get opponent's deployment zone for Turn 2 restriction
	var opponent_zone_poly = []
	if battle_round == 2:
		var opponent = 3 - player
		var zones = snapshot.get("board", {}).get("deployment_zones", [])
		for zone in zones:
			if zone.get("player", 0) == opponent:
				var poly = zone.get("poly", zone.get("vertices", []))
				for v in poly:
					if v is Dictionary and v.has("x") and v.has("y"):
						# Convert from inches to pixels for point-in-polygon check
						opponent_zone_poly.append(Vector2(float(v.x) * PIXELS_PER_INCH, float(v.y) * PIXELS_PER_INCH))

	# Sample along all 4 board edges
	# Left edge (x = edge_margin)
	var x = edge_margin_px
	var y = edge_margin_px
	while y < BOARD_HEIGHT_PX - edge_margin_px:
		var pos = Vector2(x, y)
		if _is_candidate_position_valid(pos, enemy_model_positions, min_enemy_dist_px, opponent_zone_poly):
			candidates.append(pos)
		y += step_px

	# Right edge (x = BOARD_WIDTH - edge_margin)
	x = BOARD_WIDTH_PX - edge_margin_px
	y = edge_margin_px
	while y < BOARD_HEIGHT_PX - edge_margin_px:
		var pos = Vector2(x, y)
		if _is_candidate_position_valid(pos, enemy_model_positions, min_enemy_dist_px, opponent_zone_poly):
			candidates.append(pos)
		y += step_px

	# Top edge (y = edge_margin)
	y = edge_margin_px
	x = edge_margin_px
	while x < BOARD_WIDTH_PX - edge_margin_px:
		var pos = Vector2(x, y)
		if _is_candidate_position_valid(pos, enemy_model_positions, min_enemy_dist_px, opponent_zone_poly):
			candidates.append(pos)
		x += step_px

	# Bottom edge (y = BOARD_HEIGHT - edge_margin)
	y = BOARD_HEIGHT_PX - edge_margin_px
	x = edge_margin_px
	while x < BOARD_WIDTH_PX - edge_margin_px:
		var pos = Vector2(x, y)
		if _is_candidate_position_valid(pos, enemy_model_positions, min_enemy_dist_px, opponent_zone_poly):
			candidates.append(pos)
		x += step_px

	# Score candidates by objective proximity and tactical value
	candidates = _score_and_sort_reinforcement_candidates(candidates, objectives, enemies)

	print("AIDecisionMaker: [RESERVES] Found %d valid strategic reserves positions" % candidates.size())
	return candidates

static func _generate_deep_strike_candidates(snapshot: Dictionary, player: int,
		objectives: Array, enemies: Dictionary, enemy_model_positions: Array,
		min_enemy_dist_px: float) -> Array:
	"""Generate candidate positions for deep strike (anywhere on the board >9\" from enemies)."""
	var candidates = []
	var step_px = 4.0 * PIXELS_PER_INCH  # Sample every 4 inches

	# First: generate candidates near objectives (preferred)
	for obj_pos in objectives:
		# Ring of positions around objectives at various distances
		for dist_inches in [10.0, 12.0, 15.0]:
			var dist_px = dist_inches * PIXELS_PER_INCH
			for angle_deg in range(0, 360, 30):
				var angle_rad = deg_to_rad(float(angle_deg))
				var pos = obj_pos + Vector2(cos(angle_rad), sin(angle_rad)) * dist_px
				pos.x = clamp(pos.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
				pos.y = clamp(pos.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)
				if _is_candidate_position_valid(pos, enemy_model_positions, min_enemy_dist_px, []):
					candidates.append(pos)

	# Second: grid sampling across the board for additional coverage
	var x = BASE_MARGIN_PX + step_px
	while x < BOARD_WIDTH_PX - BASE_MARGIN_PX:
		var y = BASE_MARGIN_PX + step_px
		while y < BOARD_HEIGHT_PX - BASE_MARGIN_PX:
			var pos = Vector2(x, y)
			if _is_candidate_position_valid(pos, enemy_model_positions, min_enemy_dist_px, []):
				candidates.append(pos)
			y += step_px
		x += step_px

	# Score and sort candidates
	candidates = _score_and_sort_reinforcement_candidates(candidates, objectives, enemies)

	print("AIDecisionMaker: [RESERVES] Found %d valid deep strike positions" % candidates.size())
	return candidates

static func _is_candidate_position_valid(pos: Vector2, enemy_model_positions: Array,
		min_enemy_dist_px: float, opponent_zone_poly: Array) -> bool:
	"""Check if a candidate centroid position is valid for reinforcement placement."""
	# Must be on the board
	if pos.x < BASE_MARGIN_PX or pos.x > BOARD_WIDTH_PX - BASE_MARGIN_PX:
		return false
	if pos.y < BASE_MARGIN_PX or pos.y > BOARD_HEIGHT_PX - BASE_MARGIN_PX:
		return false

	# Must be >9" from all enemy models (using conservative buffer)
	for enemy in enemy_model_positions:
		if pos.distance_to(enemy.position) < min_enemy_dist_px:
			return false

	# Turn 2 strategic reserves: cannot be in opponent's deployment zone
	if not opponent_zone_poly.is_empty():
		var packed = PackedVector2Array(opponent_zone_poly)
		if Geometry2D.is_point_in_polygon(pos, packed):
			return false

	return true

static func _score_and_sort_reinforcement_candidates(candidates: Array, objectives: Array, enemies: Dictionary) -> Array:
	"""Score reinforcement candidate positions by tactical value and sort (best first)."""
	var scored = []
	for pos in candidates:
		var score = 0.0

		# Closer to objectives = better (but not TOO close — we want control range)
		var min_obj_dist = INF
		for obj_pos in objectives:
			var dist = pos.distance_to(obj_pos)
			if dist < min_obj_dist:
				min_obj_dist = dist
		if min_obj_dist < INF:
			# Best score at ~3-6" from objective (control range)
			var dist_inches = min_obj_dist / PIXELS_PER_INCH
			if dist_inches <= 6.0:
				score += 10.0 - dist_inches  # Close to objective is great
			else:
				score += max(0.0, 8.0 - dist_inches * 0.3)  # Diminishing returns further out

		# Near enemy units = good for melee threats, but also risky
		var min_enemy_dist = INF
		for eid in enemies:
			var ec = _get_unit_centroid(enemies[eid])
			if ec != Vector2.INF:
				var dist = pos.distance_to(ec)
				if dist < min_enemy_dist:
					min_enemy_dist = dist
		if min_enemy_dist < INF:
			var enemy_inches = min_enemy_dist / PIXELS_PER_INCH
			# Sweet spot: 10-15" from enemies (can shoot, hard to charge immediately)
			if enemy_inches >= 10.0 and enemy_inches <= 15.0:
				score += 3.0
			elif enemy_inches >= 9.0 and enemy_inches < 10.0:
				score += 2.0  # Just out of charge range, decent

		scored.append({"pos": pos, "score": score})

	scored.sort_custom(func(a, b): return a.score > b.score)

	var result = []
	for s in scored:
		result.append(s.pos)
	return result

static func _get_enemy_model_positions_from_snapshot(snapshot: Dictionary, player: int) -> Array:
	"""Get all enemy model positions from snapshot for distance checks.
	Returns array of {position: Vector2, base_mm: int}."""
	var positions = []
	for unit_id in snapshot.get("units", {}):
		var unit = snapshot.units[unit_id]
		if unit.get("owner", 0) == player:
			continue
		var status = unit.get("status", 0)
		if status != GameStateData.UnitStatus.DEPLOYED and status != GameStateData.UnitStatus.MOVED:
			continue
		for model in unit.get("models", []):
			if not model.get("alive", true):
				continue
			var pos_data = model.get("position", null)
			if pos_data == null:
				continue
			var pos: Vector2
			if pos_data is Vector2:
				pos = pos_data
			else:
				pos = Vector2(float(pos_data.get("x", 0)), float(pos_data.get("y", 0)))
			positions.append({
				"position": pos,
				"base_mm": model.get("base_mm", 32)
			})
	return positions

static func _is_valid_reinforcement_position(pos: Vector2, base_mm: int,
		enemy_model_positions: Array, reserve_type: String,
		placement_bounds: Dictionary, snapshot: Dictionary, player: int, battle_round: int) -> bool:
	"""Validate a single model position for reinforcement placement."""
	# Must be on the board
	if pos.x < BASE_MARGIN_PX or pos.x > BOARD_WIDTH_PX - BASE_MARGIN_PX:
		return false
	if pos.y < BASE_MARGIN_PX or pos.y > BOARD_HEIGHT_PX - BASE_MARGIN_PX:
		return false

	# Must be >9" from all enemy models (edge-to-edge)
	var model_radius_inches = (base_mm / 2.0) / 25.4
	for enemy in enemy_model_positions:
		var enemy_radius_inches = (enemy.base_mm / 2.0) / 25.4
		var dist_px = pos.distance_to(enemy.position)
		var dist_inches = dist_px / PIXELS_PER_INCH
		var edge_dist = dist_inches - model_radius_inches - enemy_radius_inches
		if edge_dist < 9.0:
			return false

	# Strategic reserves: must be within 6" of a board edge
	if reserve_type == "strategic_reserves":
		var pos_inches_x = pos.x / PIXELS_PER_INCH
		var pos_inches_y = pos.y / PIXELS_PER_INCH
		var board_w = BOARD_WIDTH_PX / PIXELS_PER_INCH
		var board_h = BOARD_HEIGHT_PX / PIXELS_PER_INCH
		var dist_to_edge = min(pos_inches_x, board_w - pos_inches_x, pos_inches_y, board_h - pos_inches_y)
		if dist_to_edge > 6.0:
			return false

		# Turn 2: cannot be in opponent's deployment zone
		if battle_round == 2:
			var opponent = 3 - player
			var zones = snapshot.get("board", {}).get("deployment_zones", [])
			for zone in zones:
				if zone.get("player", 0) == opponent:
					var poly = zone.get("poly", zone.get("vertices", []))
					var packed = PackedVector2Array()
					for v in poly:
						if v is Dictionary and v.has("x") and v.has("y"):
							packed.append(Vector2(float(v.x) * PIXELS_PER_INCH, float(v.y) * PIXELS_PER_INCH))
					if not packed.is_empty() and Geometry2D.is_point_in_polygon(pos, packed):
						return false

	return true

static func _get_reinforcement_zone_bounds(reserve_type: String, player: int,
		snapshot: Dictionary, battle_round: int) -> Dictionary:
	"""Get zone bounds for formation generation during reinforcement placement."""
	if reserve_type == "strategic_reserves":
		# Strategic reserves must be within 6" of a board edge, so use the full board
		# but the formation generator will place models close together near the centroid
		return {
			"min_x": BASE_MARGIN_PX,
			"max_x": BOARD_WIDTH_PX - BASE_MARGIN_PX,
			"min_y": BASE_MARGIN_PX,
			"max_y": BOARD_HEIGHT_PX - BASE_MARGIN_PX
		}
	else:
		# Deep strike: anywhere on the board
		return {
			"min_x": BASE_MARGIN_PX,
			"max_x": BOARD_WIDTH_PX - BASE_MARGIN_PX,
			"min_y": BASE_MARGIN_PX,
			"max_y": BOARD_HEIGHT_PX - BASE_MARGIN_PX
		}

# =============================================================================
# TRANSPORT DISEMBARK — MOVEMENT PHASE (T7-33 / MOV-7)
# =============================================================================

static func _decide_transport_disembark(snapshot: Dictionary, player: int) -> Dictionary:
	"""Check if any embarked units should disembark at the start of movement.
	Disembark before transports move so disembarked units can still act.
	Returns a CONFIRM_DISEMBARK action if a unit should disembark, or empty dict."""
	var all_units = snapshot.get("units", {})
	var objectives = _get_objectives(snapshot)
	var enemies = _get_enemy_units(snapshot, player)
	var battle_round = snapshot.get("battle_round", 1)

	# Find all embarked units belonging to the player
	var embarked_units = []
	for unit_id in all_units:
		var unit = all_units[unit_id]
		if unit.get("owner", 0) != player:
			continue
		if unit.get("embarked_in", null) == null:
			continue
		# Skip units that already disembarked this phase
		if unit.get("disembarked_this_phase", false):
			continue
		embarked_units.append(unit_id)

	if embarked_units.is_empty():
		return {}

	print("AIDecisionMaker: [MOV-7] Evaluating disembark for %d embarked units" % embarked_units.size())

	var best_score = 0.0
	var best_action = {}

	for unit_id in embarked_units:
		var unit = all_units.get(unit_id, {})
		var transport_id = unit.get("embarked_in", "")
		var transport = all_units.get(transport_id, {})
		if transport.is_empty():
			continue

		# Check if transport has Advanced or Fell Back (can't disembark)
		var transport_flags = transport.get("flags", {})
		if transport_flags.get("advanced", false) or transport_flags.get("fell_back", false):
			continue

		var unit_name = unit.get("meta", {}).get("name", unit_id)
		var transport_name = transport.get("meta", {}).get("name", transport_id)

		# Score whether disembarking is beneficial
		var score = _score_disembark_benefit(unit, unit_id, transport, transport_id,
											objectives, enemies, all_units, battle_round, player)

		print("AIDecisionMaker: [MOV-7] %s in %s: disembark score = %.2f" % [unit_name, transport_name, score])

		if score > best_score:
			# Compute valid disembark positions within 3" of transport
			var positions = _compute_disembark_positions(unit, transport, all_units, player, snapshot)
			if not positions.is_empty():
				best_score = score
				best_action = {
					"type": "CONFIRM_DISEMBARK",
					"actor_unit_id": unit_id,
					"payload": {"positions": positions},
					"_ai_description": "AI disembarks %s from %s (score: %.2f)" % [unit_name, transport_name, score]
				}

	if not best_action.is_empty():
		print("AIDecisionMaker: [MOV-7] %s" % best_action.get("_ai_description", ""))
	return best_action

static func _score_disembark_benefit(unit: Dictionary, unit_id: String, transport: Dictionary,
									transport_id: String, objectives: Array, enemies: Dictionary,
									all_units: Dictionary, battle_round: int, player: int) -> float:
	"""Score how beneficial it is to disembark a unit right now.
	Higher score = more beneficial to disembark. Score < 0.5 means stay embarked."""
	var score = 0.0
	var transport_pos = _get_unit_centroid(transport)
	if transport_pos == Vector2.INF:
		return 0.0

	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var stats = unit.get("meta", {}).get("stats", {})
	var oc = int(stats.get("oc", 1))

	# Factor 1: Proximity to objectives — disembark when near an objective to claim it
	var nearest_obj_dist = INF
	for obj_pos in objectives:
		var dist = transport_pos.distance_to(obj_pos) / PIXELS_PER_INCH
		if dist < nearest_obj_dist:
			nearest_obj_dist = dist

	if nearest_obj_dist <= 3.0:
		# Transport is on an objective — disembark to claim it with OC
		score += 0.8 + (oc * 0.1)
		print("AIDecisionMaker: [MOV-7]   %s: objective within %.1f\" — high disembark priority (OC%d)" % [unit_name, nearest_obj_dist, oc])
	elif nearest_obj_dist <= 6.0:
		score += 0.4
		print("AIDecisionMaker: [MOV-7]   %s: objective within %.1f\" — moderate disembark priority" % [unit_name, nearest_obj_dist])
	elif nearest_obj_dist <= 12.0:
		score += 0.15

	# Factor 2: Shooting opportunity — disembark if enemies are in weapon range
	if _unit_has_ranged_weapons(unit):
		var max_range = _get_max_weapon_range(unit)
		var enemies_in_range = 0
		for enemy_id in enemies:
			var enemy = enemies[enemy_id]
			var enemy_pos = _get_unit_centroid(enemy)
			if enemy_pos == Vector2.INF:
				continue
			var dist_inches = transport_pos.distance_to(enemy_pos) / PIXELS_PER_INCH
			if dist_inches <= max_range + 3.0:  # +3" for disembark spread
				enemies_in_range += 1

		if enemies_in_range > 0:
			score += 0.3 + (enemies_in_range * 0.1)
			print("AIDecisionMaker: [MOV-7]   %s: %d enemies in shooting range (%.0f\")" % [unit_name, enemies_in_range, max_range])

	# Factor 3: Charge opportunity — disembark melee units near enemies
	if _unit_has_melee_weapons(unit):
		var transport_moved = transport.get("flags", {}).get("moved", false)
		if not transport_moved:
			# If transport hasn't moved, disembarked unit can move AND charge
			for enemy_id in enemies:
				var enemy = enemies[enemy_id]
				var enemy_pos = _get_unit_centroid(enemy)
				if enemy_pos == Vector2.INF:
					continue
				var dist_inches = transport_pos.distance_to(enemy_pos) / PIXELS_PER_INCH
				var move_inches = float(stats.get("move", 6))
				if dist_inches <= move_inches + 12.0 + 3.0:  # Move + charge range + disembark
					score += 0.4
					print("AIDecisionMaker: [MOV-7]   %s: enemy in charge range after disembark (%.1f\")" % [unit_name, dist_inches])
					break

	# Factor 4: Battle round — later rounds favor disembarking more
	# Round 1: prefer staying embarked for protection
	# Round 2+: objectives matter, start disembarking
	if battle_round == 1:
		score -= 0.3  # Penalty for early disembark (protection is valuable Turn 1)
	elif battle_round >= 3:
		score += 0.2  # Bonus for late game (objectives are critical)

	# Factor 5: Transport safety — if transport is in danger, disembark to avoid losing contents
	for enemy_id in enemies:
		var enemy = enemies[enemy_id]
		var enemy_pos = _get_unit_centroid(enemy)
		if enemy_pos == Vector2.INF:
			continue
		var dist_inches = transport_pos.distance_to(enemy_pos) / PIXELS_PER_INCH
		if dist_inches <= 12.0:
			# Enemy close enough to threaten the transport
			var enemy_weapons = enemy.get("meta", {}).get("weapons", [])
			for w in enemy_weapons:
				if w.get("type", "").to_lower() == "ranged":
					var strength = int(w.get("strength", 4))
					if strength >= 7:  # Anti-tank capable
						score += 0.25
						print("AIDecisionMaker: [MOV-7]   %s: transport threatened by S%d weapon (%.1f\" away)" % [unit_name, strength, dist_inches])
						break

	return score

static func _compute_disembark_positions(unit: Dictionary, transport: Dictionary,
										all_units: Dictionary, player: int, snapshot: Dictionary) -> Array:
	"""Compute valid positions for disembarking models within 3\" of transport.
	Returns array of positions indexed to match unit.models (dead models get placeholder).
	Returns empty array if placement fails."""
	var transport_pos = _get_unit_centroid(transport)
	if transport_pos == Vector2.INF:
		return []

	var transport_model = transport.get("models", [{}])[0] if transport.get("models", []).size() > 0 else {}
	var transport_base_mm = transport_model.get("base_mm", 100)  # Transports typically have large bases
	var transport_radius_px = (transport_base_mm / 2.0) * (PIXELS_PER_INCH / 25.4)

	# Disembark range: within 3" of transport edge
	var disembark_range_px = 3.0 * PIXELS_PER_INCH  # 3 inches

	# Count alive models
	var all_models = unit.get("models", [])
	var alive_count = 0
	var unit_base_mm = 25  # Default
	for model in all_models:
		if model.get("alive", true):
			alive_count += 1
			unit_base_mm = model.get("base_mm", 25)

	if alive_count == 0:
		return []

	var unit_radius_px = (unit_base_mm / 2.0) * (PIXELS_PER_INCH / 25.4)

	# Max distance from transport center: transport edge + 3" + model edge
	# Use a conservative margin so shape-aware validation still passes
	var max_center_dist_px = transport_radius_px + disembark_range_px + unit_radius_px - 8.0

	# Build list of occupied positions (to avoid overlaps)
	var occupied_positions = []
	for uid in all_units:
		var u = all_units[uid]
		if u.get("embarked_in", null) != null:
			continue  # Skip embarked units
		for model in u.get("models", []):
			if not model.get("alive", true):
				continue
			var pos = _get_model_position(model)
			if pos != Vector2.INF:
				occupied_positions.append({
					"position": pos,
					"base_mm": model.get("base_mm", 32)
				})

	# Get enemy model positions for engagement range check
	var enemy_positions = []
	for uid in all_units:
		var u = all_units[uid]
		if u.get("owner", 0) == player:
			continue
		for model in u.get("models", []):
			if not model.get("alive", true):
				continue
			var pos = _get_model_position(model)
			if pos != Vector2.INF:
				enemy_positions.append({
					"position": pos,
					"base_mm": model.get("base_mm", 32)
				})

	# Determine preferred direction (toward nearest objective)
	var preferred_dir = Vector2.DOWN  # Default
	var objectives = _get_objectives(snapshot)
	if not objectives.is_empty():
		var nearest_obj_dist = INF
		for obj_pos in objectives:
			var dist = transport_pos.distance_to(obj_pos)
			if dist < nearest_obj_dist:
				nearest_obj_dist = dist
				if dist > 1.0:
					preferred_dir = (obj_pos - transport_pos).normalized()

	# Start placement offset from transport center in preferred direction
	var base_offset_dist = transport_radius_px + unit_radius_px + 8.0  # Just outside transport base
	var base_pos = transport_pos + preferred_dir * base_offset_dist
	var spacing = unit_radius_px * 2.0 + 6.0  # Base diameter + small gap

	var cols = mini(5, alive_count)

	# Create a perpendicular direction for the grid layout
	var perp_dir = Vector2(-preferred_dir.y, preferred_dir.x)

	# Build positions for alive models first, then map to model array indices
	var alive_positions = []
	var alive_idx = 0
	for model in all_models:
		if not model.get("alive", true):
			continue

		var row = alive_idx / cols
		var col = alive_idx % cols

		# Calculate grid position
		var col_offset = (col - (cols - 1) / 2.0) * spacing
		var row_offset = row * spacing
		var candidate = base_pos + perp_dir * col_offset + preferred_dir * row_offset

		# Validate: within disembark range (center-to-center)
		var center_dist = candidate.distance_to(transport_pos)
		if center_dist > max_center_dist_px:
			var dir_to_transport = (transport_pos - candidate).normalized()
			candidate = candidate + dir_to_transport * (center_dist - max_center_dist_px + 4.0)

		# Validate: not in engagement range of enemies (1" edge-to-edge)
		var in_engagement = _is_pos_in_engagement(candidate, unit_radius_px, enemy_positions)

		if in_engagement:
			candidate = _find_non_engaged_position(transport_pos, base_offset_dist,
				preferred_dir, perp_dir, col, cols, spacing, max_center_dist_px,
				unit_radius_px, enemy_positions)
			if candidate == Vector2.INF:
				return []

		# Validate: not overlapping other models
		var overlaps = _pos_overlaps_any(candidate, unit_radius_px, occupied_positions, alive_positions)
		if overlaps:
			candidate = _find_non_overlapping_position(candidate, transport_pos, max_center_dist_px,
				unit_radius_px, spacing, occupied_positions, alive_positions, enemy_positions)
			if candidate == Vector2.INF:
				return []

		# Clamp to board bounds
		candidate.x = clamp(candidate.x, unit_radius_px + 2.0, BOARD_WIDTH_PX - unit_radius_px - 2.0)
		candidate.y = clamp(candidate.y, unit_radius_px + 2.0, BOARD_HEIGHT_PX - unit_radius_px - 2.0)

		alive_positions.append(candidate)
		occupied_positions.append({"position": candidate, "base_mm": unit_base_mm})
		alive_idx += 1

	if alive_positions.size() != alive_count:
		return []

	# Map alive positions back to the full model array (dead models get placeholder)
	var positions = []
	var alive_pos_idx = 0
	for model in all_models:
		if model.get("alive", true):
			positions.append(alive_positions[alive_pos_idx])
			alive_pos_idx += 1
		else:
			# Dead models get the transport position as placeholder (skipped by validation)
			positions.append(transport_pos)

	print("AIDecisionMaker: [MOV-7] Computed %d disembark positions (%d alive) for %s" % [
		positions.size(), alive_count, unit.get("meta", {}).get("name", "")])
	return positions

static func _is_pos_in_engagement(pos: Vector2, unit_radius_px: float, enemy_positions: Array) -> bool:
	"""Check if a position is within engagement range (1\") of any enemy model."""
	for enemy_data in enemy_positions:
		var enemy_pos = enemy_data.position
		var enemy_radius_px = (enemy_data.base_mm / 2.0) * (PIXELS_PER_INCH / 25.4)
		var edge_dist_px = pos.distance_to(enemy_pos) - unit_radius_px - enemy_radius_px
		if edge_dist_px < ENGAGEMENT_RANGE_PX:
			return true
	return false

static func _find_non_engaged_position(transport_pos: Vector2, base_offset_dist: float,
	preferred_dir: Vector2, perp_dir: Vector2, col: int, cols: int, spacing: float,
	max_center_dist_px: float, unit_radius_px: float, enemy_positions: Array) -> Vector2:
	"""Try alternate angles around transport to find a position not in engagement range."""
	for angle_offset in [0.5, -0.5, 1.0, -1.0, 1.5, -1.5, PI]:
		var alt_dir = preferred_dir.rotated(angle_offset)
		var alt_pos = transport_pos + alt_dir * base_offset_dist + perp_dir.rotated(angle_offset) * (col - (cols - 1) / 2.0) * spacing
		if alt_pos.distance_to(transport_pos) > max_center_dist_px:
			continue
		if not _is_pos_in_engagement(alt_pos, unit_radius_px, enemy_positions):
			return alt_pos
	return Vector2.INF

static func _pos_overlaps_any(pos: Vector2, unit_radius_px: float,
	occupied_positions: Array, placed_positions: Array) -> bool:
	"""Check if a position overlaps any occupied or already-placed model."""
	for occ in occupied_positions:
		var occ_radius_px = (occ.base_mm / 2.0) * (PIXELS_PER_INCH / 25.4)
		if pos.distance_to(occ.position) < unit_radius_px + occ_radius_px + 2.0:
			return true
	for placed_pos in placed_positions:
		if pos.distance_to(placed_pos) < unit_radius_px * 2.0 + 2.0:
			return true
	return false

static func _find_non_overlapping_position(candidate: Vector2, transport_pos: Vector2,
	max_center_dist_px: float, unit_radius_px: float, spacing: float,
	occupied_positions: Array, placed_positions: Array, enemy_positions: Array) -> Vector2:
	"""Spiral search around candidate for a valid non-overlapping, non-engaged position."""
	for ring in range(1, 5):
		for angle_step in range(8):
			var angle = angle_step * PI / 4.0
			var offset = Vector2(cos(angle), sin(angle)) * ring * spacing * 0.5
			var alt_pos = candidate + offset
			if alt_pos.distance_to(transport_pos) > max_center_dist_px:
				continue
			if alt_pos.x < unit_radius_px or alt_pos.x > BOARD_WIDTH_PX - unit_radius_px:
				continue
			if alt_pos.y < unit_radius_px or alt_pos.y > BOARD_HEIGHT_PX - unit_radius_px:
				continue
			if _pos_overlaps_any(alt_pos, unit_radius_px, occupied_positions, placed_positions):
				continue
			if _is_pos_in_engagement(alt_pos, unit_radius_px, enemy_positions):
				continue
			return alt_pos
	return Vector2.INF

# =============================================================================
# OBJECTIVE EVALUATION (Task 1 + Task 5)
# =============================================================================

static func _evaluate_all_objectives(
	snapshot: Dictionary, objectives: Array, player: int,
	enemies: Dictionary, friendly_units: Dictionary, battle_round: int
) -> Array:
	# Returns array of objective evaluations with priority scores
	var evaluations = []
	var obj_data = snapshot.get("board", {}).get("objectives", [])

	for i in range(objectives.size()):
		var obj_pos = objectives[i]
		var obj_id = ""
		var obj_zone = "no_mans_land"
		if i < obj_data.size():
			obj_id = obj_data[i].get("id", "obj_%d" % i)
			obj_zone = obj_data[i].get("zone", "no_mans_land")

		# Calculate OC totals within control range
		var friendly_oc = _get_oc_at_position(obj_pos, friendly_units, player, true)
		var enemy_oc = _get_oc_at_position(obj_pos, enemies, player, false)

		# Count friendly/enemy units nearby (within 12")
		var friendly_nearby = _count_units_near_position(obj_pos, friendly_units, CHARGE_RANGE_PX)
		var enemy_nearby = _count_units_near_position(obj_pos, enemies, CHARGE_RANGE_PX)

		# Classify the objective state
		var state = "uncontrolled"
		if friendly_oc > 0 and friendly_oc > enemy_oc:
			if enemy_nearby > 0:
				state = "held_threatened"
			else:
				state = "held_safe"
		elif enemy_oc > 0 and enemy_oc > friendly_oc:
			if enemy_oc <= 4:  # Reasonable to contest
				state = "enemy_weak"
			else:
				state = "enemy_strong"
		elif friendly_oc > 0 and enemy_oc > 0:
			state = "contested"
		else:
			state = "uncontrolled"

		# Is this our home objective?
		var is_home = (player == 1 and obj_zone == "player1") or (player == 2 and obj_zone == "player2")
		var is_enemy_home = (player == 1 and obj_zone == "player2") or (player == 2 and obj_zone == "player1")

		# Calculate priority score
		var priority = 0.0
		match state:
			"uncontrolled":
				priority += WEIGHT_UNCONTROLLED_OBJ
			"contested":
				priority += WEIGHT_CONTESTED_OBJ
			"enemy_weak":
				priority += WEIGHT_ENEMY_WEAK_OBJ
			"enemy_strong":
				priority += WEIGHT_ENEMY_STRONG_OBJ
			"held_safe":
				priority += WEIGHT_ALREADY_HELD_OBJ
			"held_threatened":
				priority += WEIGHT_CONTESTED_OBJ * 0.8  # Still important to reinforce

		# Home objective bonus - defend it if undefended
		if is_home and friendly_oc == 0:
			priority += WEIGHT_HOME_UNDEFENDED

		# T7-23: Expanded round-based urgency scoring (was only round 1 + round 4+)
		# Round 1: Rush to objectives — scoring starts in round 2
		if battle_round == 1:
			priority += WEIGHT_SCORING_URGENCY
			# Extra urgency for uncontrolled no-man's-land objectives
			if state == "uncontrolled" and not is_home and not is_enemy_home:
				priority += 1.0
		# Round 2: Contest uncontrolled objectives — this is the first scoring round
		elif battle_round == 2:
			if state in ["uncontrolled", "enemy_weak"]:
				priority += URGENCY_ROUND_2_CONTEST
			elif state == "contested":
				priority += URGENCY_ROUND_2_CONTEST * 0.8
		# Round 3: Consolidate — hold what we have, reinforce contested
		elif battle_round == 3:
			if state == "held_threatened":
				priority += URGENCY_ROUND_3_HOLD
			elif state == "contested":
				priority += URGENCY_ROUND_3_HOLD * 1.2
			elif state == "enemy_weak":
				priority += URGENCY_ROUND_3_HOLD
		# Round 4-5: Aggressive push — every VP matters, flip what we can
		elif battle_round >= 4:
			if state in ["contested", "enemy_weak"]:
				priority += URGENCY_LATE_GAME_PUSH
			elif state == "uncontrolled":
				priority += URGENCY_LATE_GAME_PUSH * 0.8
			# In round 5, even try to contest enemy strongholds
			if battle_round >= 5 and state == "enemy_strong":
				priority += URGENCY_LATE_GAME_PUSH * 0.4

		# T7-24: Tempo-based aggression adjustment
		# When behind on VP, increase urgency to contest/capture objectives
		# When ahead, reduce urgency for risky pushes (protect the lead)
		var tempo_mod = _calculate_tempo_modifier(snapshot, player)
		if tempo_mod != 1.0:
			# Apply tempo to offensive objective scoring (contesting, capturing)
			if state in ["uncontrolled", "contested", "enemy_weak"]:
				priority *= tempo_mod
			# When behind, reduce the penalty for contesting enemy strongholds
			elif state == "enemy_strong" and tempo_mod > 1.0:
				priority += (tempo_mod - 1.0) * 3.0  # Soften the negative scoring
			# When ahead, increase value of defending held objectives
			elif state in ["held_safe", "held_threatened"] and tempo_mod < 1.0:
				priority += (1.0 - tempo_mod) * 2.0  # Bonus for defensive play

		# Don't over-prioritize enemy home objectives (far away, hard to hold)
		if is_enemy_home and state == "enemy_strong":
			priority -= 3.0

		print("AIDecisionMaker: Objective %s: state=%s, friendly_oc=%d, enemy_oc=%d, priority=%.1f (tempo=%.2f)" % [obj_id, state, friendly_oc, enemy_oc, priority, tempo_mod])

		evaluations.append({
			"index": i,
			"id": obj_id,
			"position": obj_pos,
			"zone": obj_zone,
			"state": state,
			"friendly_oc": friendly_oc,
			"enemy_oc": enemy_oc,
			"friendly_nearby": friendly_nearby,
			"enemy_nearby": enemy_nearby,
			"is_home": is_home,
			"is_enemy_home": is_enemy_home,
			"priority": priority,
			"oc_needed": max(0, enemy_oc - friendly_oc + 1)  # OC we need to add to flip control
		})

	return evaluations

# =============================================================================
# UNIT-TO-OBJECTIVE ASSIGNMENT (Task 1 + Task 2 + Task 3 + Task 6)
# =============================================================================

static func _assign_units_to_objectives(
	snapshot: Dictionary, movable_units: Dictionary, obj_evaluations: Array,
	objectives: Array, enemies: Dictionary, friendly_units: Dictionary,
	player: int, battle_round: int, threat_data: Array = []
) -> Dictionary:
	# Returns: {unit_id: {objective_id, objective_pos, action, score, reason, distance}}
	# Uses a greedy assignment algorithm: score all (unit, objective) pairs, assign best first

	var assignments = {}  # unit_id -> assignment dict
	var obj_oc_remaining = {}  # objective_id -> how much more OC is still needed there

	# Initialize OC needs per objective
	for eval in obj_evaluations:
		var obj_id = eval.id
		if eval.state in ["held_safe"]:
			obj_oc_remaining[obj_id] = 0  # Already fully held
		elif eval.state == "held_threatened":
			obj_oc_remaining[obj_id] = max(1, eval.enemy_oc)  # Might need reinforcement
		else:
			# Need enough OC to control: enemy_oc + 1 (minus what we already have)
			obj_oc_remaining[obj_id] = max(1, eval.oc_needed)

	# Build all (unit, objective) candidate pairs with scores
	var candidates = []
	for unit_id in movable_units:
		var unit = snapshot.get("units", {}).get(unit_id, {})
		var centroid = _get_unit_centroid(unit)
		if centroid == Vector2.INF:
			continue
		var move_types = movable_units[unit_id]
		var is_engaged = "BEGIN_FALL_BACK" in move_types and not "BEGIN_NORMAL_MOVE" in move_types
		if is_engaged:
			continue  # Engaged units handled separately

		var unit_oc = int(unit.get("meta", {}).get("stats", {}).get("objective_control", 1))
		var move_inches = float(unit.get("meta", {}).get("stats", {}).get("move", 6))
		var unit_keywords = unit.get("meta", {}).get("keywords", [])
		var has_ranged = _unit_has_ranged_weapons(unit)
		var max_weapon_range = _get_max_weapon_range(unit)

		# T7-43: Get round strategy modifiers for movement scoring
		var move_strategy = _get_round_strategy_modifiers(battle_round)

		for eval in obj_evaluations:
			var obj_pos = eval.position
			var obj_id = eval.id
			var dist_px = centroid.distance_to(obj_pos)
			var dist_inches = dist_px / PIXELS_PER_INCH
			var turns_to_reach = max(1.0, ceil(dist_inches / move_inches)) if move_inches > 0 else 99.0
			var already_on_obj = dist_px <= OBJECTIVE_CONTROL_RANGE_PX

			# Base score from objective priority
			# T7-43: Scale objective priority by round strategy modifier
			var score = eval.priority * move_strategy.objective_priority

			# OC efficiency: high-OC units are more valuable at contested objectives
			if eval.oc_needed > 0:
				score += min(float(unit_oc) / max(1.0, float(eval.oc_needed)), 1.5) * WEIGHT_OC_EFFICIENCY

			# Distance penalty: further away = less useful
			if turns_to_reach > 1:
				score -= (turns_to_reach - 1) * 2.0

			# Already on the objective: big bonus for holding
			if already_on_obj:
				score += 5.0

			# Can reach this turn: bonus
			if dist_inches <= move_inches:
				score += 3.0
			elif dist_inches <= move_inches + 2.0:  # Reachable with advance
				score += 1.5

			# Scoring round awareness: if this is round 1 and we can't reach by round 2, lower priority
			if battle_round == 1 and turns_to_reach > 1:
				score -= 2.0

			# Unit suitability: units with shooting should consider range to enemies
			if has_ranged and eval.enemy_nearby > 0:
				score += 1.0  # Shooting units valuable where enemies are

			# --- THREAT AWARENESS (AI-TACTIC-4, MOV-2) ---
			# Penalize assignments that route units into enemy threat zones
			# T7-43: Scale threat penalties by survival modifier (early=less cautious, late=more cautious)
			if not threat_data.is_empty() and not already_on_obj:
				# Estimate where the unit would end up after moving toward this objective
				var move_direction = (obj_pos - centroid).normalized() if dist_px > 1.0 else Vector2.ZERO
				var move_px_cap = move_inches * PIXELS_PER_INCH
				var estimated_dest = centroid + move_direction * min(move_px_cap, dist_px)

				var dest_threat = _evaluate_position_threat(estimated_dest, threat_data, unit)
				var current_threat = _evaluate_position_threat(centroid, threat_data, unit)

				# Penalize moving INTO more danger than we're currently in
				var threat_increase = dest_threat.total_threat - current_threat.total_threat
				if threat_increase > 0.5:
					score -= threat_increase * move_strategy.survival
					# Extra charge threat penalty: being chargeable is worse than being shot at
					if dest_threat.charge_threat > current_threat.charge_threat + 0.5:
						score -= (dest_threat.charge_threat - current_threat.charge_threat) * 0.5 * move_strategy.survival

			# --- T7-23: MULTI-PHASE PLANNING INFLUENCE ---
			# Units with charge intent should be biased toward charge angle
			var charge_intent = _get_charge_intent(unit_id)
			if not charge_intent.is_empty():
				var charge_target_id = charge_intent.get("target_id", "")
				if charge_target_id != "" and enemies.has(charge_target_id):
					var charge_target = enemies[charge_target_id]
					var charge_target_centroid = _get_unit_centroid(charge_target)
					if charge_target_centroid != Vector2.INF:
						# Check if this objective is on the way to the charge target
						var dir_to_obj = (obj_pos - centroid).normalized() if dist_px > 1.0 else Vector2.ZERO
						var dir_to_charge = (charge_target_centroid - centroid).normalized()
						var alignment = dir_to_obj.dot(dir_to_charge)
						if alignment > 0.5:
							# Objective is in the same general direction as charge target
							score += PHASE_PLAN_CHARGE_LANE_BONUS * alignment
						elif alignment < -0.3:
							# Objective is in the opposite direction — penalize
							score -= PHASE_PLAN_CHARGE_LANE_BONUS * 0.5

			# Ranged units: bonus for objectives that maintain shooting lanes
			if has_ranged and not charge_intent.is_empty() == false:
				var lanes = _phase_plan.get("shooting_lanes", {}).get(unit_id, [])
				if not lanes.is_empty():
					# Check if moving to this objective maintains shooting lanes
					for lane in lanes:
						var lane_target_id = lane.get("target_id", "")
						if enemies.has(lane_target_id):
							var lane_target = enemies[lane_target_id]
							var lane_centroid = _get_unit_centroid(lane_target)
							if lane_centroid != Vector2.INF:
								var dist_to_lane_target = obj_pos.distance_to(lane_centroid) / PIXELS_PER_INCH
								if dist_to_lane_target <= max_weapon_range:
									score += PHASE_PLAN_SHOOTING_LANE_BONUS * 0.5

			# Determine recommended action
			var action = "move"
			var reason = "moving to objective"

			if already_on_obj:
				action = "hold"
				reason = "on objective, OC needed"
			elif dist_inches > move_inches and dist_inches <= move_inches + 2.0:
				# Advance consideration (Task 3)
				var should_advance = _should_unit_advance(
					unit, dist_inches, move_inches, has_ranged, max_weapon_range,
					enemies, centroid, battle_round, eval
				)
				if should_advance:
					action = "advance"
					reason = "advancing for extra range"

			candidates.append({
				"unit_id": unit_id,
				"objective_id": obj_id,
				"objective_pos": obj_pos,
				"score": score,
				"action": action,
				"reason": reason,
				"distance": dist_px,
				"unit_oc": unit_oc,
				"already_on_obj": already_on_obj,
				"turns_to_reach": turns_to_reach
			})

	# Sort by score (highest first)
	candidates.sort_custom(func(a, b): return a.score > b.score)

	# Greedy assignment: assign the best (unit, objective) pair, then reduce OC need
	var assigned_unit_ids = {}  # Track which units are already assigned

	# PASS 1: Assign units already on objectives first (hold decisions)
	# Count how many movable units are on each objective
	var units_on_obj = {}  # obj_id -> count of movable units on it
	for cand in candidates:
		if cand.already_on_obj:
			units_on_obj[cand.objective_id] = units_on_obj.get(cand.objective_id, 0) + 1

	for cand in candidates:
		var uid = cand.unit_id
		var oid = cand.objective_id
		if assigned_unit_ids.has(uid):
			continue
		if not cand.already_on_obj:
			continue

		var remaining = obj_oc_remaining.get(oid, 0)
		var eval_for_obj = _get_obj_eval_by_id(obj_evaluations, oid)
		var obj_state = eval_for_obj.get("state", "")

		# Determine if this unit should hold here
		var should_hold = false
		if remaining > 0:
			should_hold = true  # OC still needed at this objective
		elif obj_state == "held_threatened":
			should_hold = true  # Threatened, keep defender
		elif units_on_obj.get(oid, 0) <= 1:
			# Only one unit on this objective — always hold to maintain control
			# Don't abandon a controlled objective
			should_hold = true
		# If multiple units on same held_safe objective, let extras move elsewhere

		if should_hold:
			assignments[uid] = cand
			assignments[uid]["action"] = "hold"
			assignments[uid]["reason"] = "holding objective (OC: %d)" % cand.unit_oc
			assigned_unit_ids[uid] = true
			obj_oc_remaining[oid] = max(0, remaining - cand.unit_oc)
			# Decrease count so second unit on same obj can be freed
			units_on_obj[oid] = units_on_obj.get(oid, 1) - 1
			print("AIDecisionMaker: Assigned %s to HOLD %s (OC: %d, remaining need: %d)" % [uid, oid, cand.unit_oc, obj_oc_remaining[oid]])
		else:
			# Objective already fully held by another unit — this unit should move elsewhere
			# Will be assigned in pass 2
			pass

	# PASS 2: Assign remaining units to objectives that still need OC
	for cand in candidates:
		var uid = cand.unit_id
		var oid = cand.objective_id
		if assigned_unit_ids.has(uid):
			continue

		var remaining = obj_oc_remaining.get(oid, 0)
		if remaining <= 0:
			# Check if any other objective still needs units
			var any_need = false
			for other_oid in obj_oc_remaining:
				if obj_oc_remaining[other_oid] > 0:
					any_need = true
					break
			if not any_need:
				# All objectives satisfied — assign to screen or best available
				pass  # Fall through to pass 3

			continue  # Skip objectives that don't need more OC

		assignments[uid] = cand
		assigned_unit_ids[uid] = true
		obj_oc_remaining[oid] = max(0, remaining - cand.unit_oc)
		print("AIDecisionMaker: Assigned %s to %s %s (score: %.1f, reason: %s)" % [uid, cand.action.to_upper(), oid, cand.score, cand.reason])

	# PASS 3: Assign remaining units — screening / deep strike denial / support
	# (AI-TACTIC-3, MOV-4) Check for enemy reserves to determine screening urgency
	var enemy_reserves = _get_enemy_reserves(snapshot, player)
	var has_enemy_reserves = enemy_reserves.size() > 0
	if has_enemy_reserves:
		print("AIDecisionMaker: [SCREEN] Detected %d enemy units in reserves:" % enemy_reserves.size())
		for er in enemy_reserves:
			print("  %s (%s, %dpts)" % [er.name, er.reserve_type, er.points])

	# Track screener positions for spacing (18" apart for denial coverage)
	var screener_positions = []
	# Include positions of already-assigned units that are effectively screening
	for uid in assigned_unit_ids:
		var aunit = snapshot.get("units", {}).get(uid, {})
		var ac = _get_unit_centroid(aunit)
		if ac != Vector2.INF:
			screener_positions.append(ac)

	# Calculate denial positions if enemy has reserves
	var denial_positions = []
	if has_enemy_reserves:
		denial_positions = _calculate_denial_positions(
			snapshot, objectives, obj_evaluations, friendly_units, player, screener_positions
		)
		if not denial_positions.is_empty():
			print("AIDecisionMaker: [SCREEN] Calculated %d denial positions:" % denial_positions.size())
			for dp in denial_positions:
				print("  pos=(%.0f,%.0f) priority=%.1f reason=%s" % [dp.position.x, dp.position.y, dp.priority, dp.reason])

	# T7-42: Calculate corridor blocking positions to impede enemy approach to objectives
	var corridor_blocking_positions = _calculate_corridor_blocking_positions(
		snapshot, objectives, obj_evaluations, enemies, friendly_units, player, screener_positions
	)
	if not corridor_blocking_positions.is_empty():
		print("AIDecisionMaker: [BLOCK] Calculated %d corridor blocking positions:" % corridor_blocking_positions.size())
		for bp in corridor_blocking_positions:
			print("  pos=(%.0f,%.0f) priority=%.1f reason=%s" % [bp.position.x, bp.position.y, bp.priority, bp.reason])

	# Collect unassigned units and sort by screening suitability
	var unassigned_units = []
	for unit_id in movable_units:
		if assigned_unit_ids.has(unit_id):
			continue
		var move_types = movable_units[unit_id]
		var is_engaged = "BEGIN_FALL_BACK" in move_types and not "BEGIN_NORMAL_MOVE" in move_types
		if is_engaged:
			continue
		var unit = snapshot.get("units", {}).get(unit_id, {})
		var centroid = _get_unit_centroid(unit)
		if centroid == Vector2.INF:
			continue
		unassigned_units.append({"unit_id": unit_id, "unit": unit, "centroid": centroid})

	# Sort: screening candidates first (cheap units), then by distance to backfield
	unassigned_units.sort_custom(func(a, b):
		var a_screen = _is_screening_candidate(a.unit)
		var b_screen = _is_screening_candidate(b.unit)
		if a_screen != b_screen:
			return a_screen  # Screening candidates come first
		return false  # Maintain original order otherwise
	)

	var denial_idx = 0  # Track which denial position to assign next
	var block_idx = 0   # T7-42: Track which corridor blocking position to assign next
	for entry in unassigned_units:
		var unit_id = entry.unit_id
		var unit = entry.unit
		var centroid = entry.centroid
		var is_screen_candidate = _is_screening_candidate(unit)

		# --- SCREENING ASSIGNMENT ---
		# If enemy has reserves and this unit is a screening candidate, assign to denial
		if has_enemy_reserves and is_screen_candidate and denial_idx < denial_positions.size():
			var denial = denial_positions[denial_idx]
			var denial_pos = denial.position
			var dist_to_denial = centroid.distance_to(denial_pos)
			var move_inches = float(unit.get("meta", {}).get("stats", {}).get("move", 6))

			# Check spacing: don't cluster screeners, keep ~18" apart
			var too_close_to_screener = false
			for sp in screener_positions:
				if denial_pos.distance_to(sp) < SCREEN_SPACING_PX * 0.5:
					too_close_to_screener = true
					break

			if not too_close_to_screener:
				var score = SCREEN_SCORE_BASE + denial.priority
				# Closer units score higher for screening
				score -= (dist_to_denial / PIXELS_PER_INCH) * 0.3
				assignments[unit_id] = {
					"objective_id": "screen_denial",
					"objective_pos": denial_pos,
					"action": "screen",
					"score": score,
					"reason": denial.reason,
					"distance": dist_to_denial
				}
				assigned_unit_ids[unit_id] = true
				screener_positions.append(denial_pos)
				denial_idx += 1
				var unit_name = unit.get("meta", {}).get("name", unit_id)
				print("AIDecisionMaker: [SCREEN] Assigned %s to SCREEN at (%.0f,%.0f) — %s" % [
					unit_name, denial_pos.x, denial_pos.y, denial.reason])
				continue

		# --- SCREENING FALLBACK: Use _compute_screen_position for non-denial screening ---
		# Even without enemy reserves, cheap unassigned units can screen valuable friendlies
		if is_screen_candidate and not enemies.is_empty():
			var screen_pos = _compute_screen_position(unit, unit_id, friendly_units, enemies, snapshot)
			if screen_pos != Vector2.INF:
				# Check spacing
				var too_close = false
				for sp in screener_positions:
					if screen_pos.distance_to(sp) < SCREEN_SPACING_PX * 0.5:
						too_close = true
						break
				if not too_close:
					var dist_to_screen = centroid.distance_to(screen_pos)
					assignments[unit_id] = {
						"objective_id": "screen_protect",
						"objective_pos": screen_pos,
						"action": "screen",
						"score": SCREEN_SCORE_BASE,
						"reason": "screening valuable friendlies from enemy threats",
						"distance": dist_to_screen
					}
					assigned_unit_ids[unit_id] = true
					screener_positions.append(screen_pos)
					var unit_name = unit.get("meta", {}).get("name", unit_id)
					print("AIDecisionMaker: [SCREEN] Assigned %s to SCREEN-PROTECT at (%.0f,%.0f)" % [
						unit_name, screen_pos.x, screen_pos.y])
					continue

		# --- T7-42: CORRIDOR BLOCKING — block enemy movement corridors to objectives ---
		# Expendable units physically block the path between enemies and key objectives,
		# forcing the opponent to waste movement going around or charge the blocker.
		if is_screen_candidate and not corridor_blocking_positions.is_empty() and block_idx < corridor_blocking_positions.size():
			var block = corridor_blocking_positions[block_idx]
			var block_pos = block.position
			var dist_to_block = centroid.distance_to(block_pos)

			# Check spacing: don't cluster blockers
			var too_close_to_blocker = false
			for sp in screener_positions:
				if block_pos.distance_to(sp) < CORRIDOR_BLOCK_MIN_GAP_PX:
					too_close_to_blocker = true
					break

			if not too_close_to_blocker:
				var score = CORRIDOR_BLOCK_SCORE_BASE + block.priority
				# Closer units score higher for blocking
				score -= (dist_to_block / PIXELS_PER_INCH) * 0.3
				assignments[unit_id] = {
					"objective_id": "corridor_block",
					"objective_pos": block_pos,
					"action": "screen",
					"score": score,
					"reason": block.reason,
					"distance": dist_to_block
				}
				assigned_unit_ids[unit_id] = true
				screener_positions.append(block_pos)
				block_idx += 1
				var unit_name = unit.get("meta", {}).get("name", unit_id)
				print("AIDecisionMaker: [BLOCK] Assigned %s to BLOCK at (%.0f,%.0f) — %s" % [
					unit_name, block_pos.x, block_pos.y, block.reason])
				continue

		# --- FALLBACK: Assign to best remaining objective (original behavior) ---
		var best_obj = _find_best_remaining_objective(centroid, obj_evaluations, enemies, unit, snapshot, player)
		if not best_obj.is_empty():
			assignments[unit_id] = best_obj
			assigned_unit_ids[unit_id] = true
			print("AIDecisionMaker: Assigned %s to %s %s (support/screen)" % [unit_id, best_obj.action.to_upper(), best_obj.objective_id])
		else:
			# Truly nothing useful — remain stationary
			assignments[unit_id] = {
				"objective_id": "none",
				"objective_pos": Vector2.INF,
				"action": "hold",
				"score": -100.0,
				"reason": "no useful objective",
				"distance": 0.0
			}

	return assignments

# =============================================================================
# ENGAGED UNIT DECISION (Task 4: Smart Fall Back)
# =============================================================================

static func _decide_engaged_unit(
	unit: Dictionary, unit_id: String, unit_name: String,
	move_types: Array, objectives: Array, enemies: Dictionary,
	snapshot: Dictionary, player: int
) -> Dictionary:
	var centroid = _get_unit_centroid(unit)
	if centroid == Vector2.INF:
		if "REMAIN_STATIONARY" in move_types:
			return {"type": "REMAIN_STATIONARY", "actor_unit_id": unit_id, "_ai_description": "%s remains stationary (no position)" % unit_name}
		return {}

	# --- T7-27: Assess survival before making hold/fall-back decision ---
	var survival = _assess_engaged_unit_survival(unit, unit_id, unit_name, enemies)

	# Check if this unit is on an objective
	var on_objective = false
	var obj_id_held = ""
	for obj_pos in objectives:
		if centroid.distance_to(obj_pos) <= OBJECTIVE_CONTROL_RANGE_PX:
			on_objective = true
			# Find the objective ID
			var obj_data = snapshot.get("board", {}).get("objectives", [])
			for od in obj_data:
				var op = od.get("position", null)
				if op != null:
					var opv = op if op is Vector2 else Vector2(float(op.get("x", 0)), float(op.get("y", 0)))
					if opv.distance_to(obj_pos) < 10.0:
						obj_id_held = od.get("id", "")
			break

	var unit_oc = int(unit.get("meta", {}).get("stats", {}).get("objective_control", 1))
	var friendly_units = _get_units_for_player(snapshot, player)

	# --- Pre-check Fall Back and X abilities (AI-GAP-4) ---
	var all_units = snapshot.get("units", {})
	var fb_and_charge = AIAbilityAnalyzerData.can_fall_back_and_charge(unit_id, unit, all_units)
	var fb_and_shoot = AIAbilityAnalyzerData.can_fall_back_and_shoot(unit_id, unit, all_units)

	# T7-43: Get round strategy for engaged unit decisions
	var engaged_battle_round = snapshot.get("meta", {}).get("battle_round", snapshot.get("battle_round", 1))
	var engaged_strategy = _get_round_strategy_modifiers(engaged_battle_round)

	if on_objective:
		# Check if our OC at this objective would be reduced by falling back
		var friendly_oc_here = _get_oc_at_position(
			centroid, friendly_units, player, true
		)
		var enemy_oc_here = _get_oc_at_position(
			centroid, enemies, player, false
		)

		# T7-43: In rounds 4-5, units on objectives are biased toward holding
		# even if survival is at risk — objective control is paramount
		if engaged_battle_round >= 4 and friendly_oc_here >= enemy_oc_here and "REMAIN_STATIONARY" in move_types:
			if not fb_and_charge:
				print("AIDecisionMaker: [STRATEGY] Round %d — %s holds %s (late-game objective priority, OC %d vs %d)" % [
					engaged_battle_round, unit_name, obj_id_held, friendly_oc_here, enemy_oc_here])
				return {
					"type": "REMAIN_STATIONARY",
					"actor_unit_id": unit_id,
					"_ai_description": "%s holds %s (late-game priority, OC %d vs %d)" % [unit_name, obj_id_held, friendly_oc_here, enemy_oc_here]
				}

		# If we're winning the OC war or tied, stay and hold
		# Exception: if the unit has Fall Back and Charge, falling back may be
		# tactically better (can charge back in, potentially killing the enemy)
		# T7-27: Also override to fall back if survival is lethal and other friendly
		# units can still hold the objective without us
		if friendly_oc_here >= enemy_oc_here and "REMAIN_STATIONARY" in move_types:
			if fb_and_charge:
				print("AIDecisionMaker: %s engaged on %s, winning OC (%d vs %d) but has Fall Back and Charge — may fall back to re-engage" % [unit_name, obj_id_held, friendly_oc_here, enemy_oc_here])
			elif survival.is_lethal and "BEGIN_FALL_BACK" in move_types:
				# T7-27: Unit will likely be destroyed — fall back to preserve it,
				# but only if other friendlies can still hold the objective
				var oc_without_us = friendly_oc_here - unit_oc
				if oc_without_us >= enemy_oc_here:
					print("AIDecisionMaker: T7-27 %s engaged on %s, winning OC (%d vs %d) but survival is LETHAL (%.1f dmg vs %.1f wounds) — falling back (others can hold)" % [
						unit_name, obj_id_held, friendly_oc_here, enemy_oc_here, survival.expected_damage, survival.remaining_wounds])
					# Fall through to fall-back logic below
				else:
					print("AIDecisionMaker: T7-27 %s engaged on %s, survival is LETHAL but must hold (no other holders, OC %d vs %d)" % [
						unit_name, obj_id_held, friendly_oc_here, enemy_oc_here])
					return {
						"type": "REMAIN_STATIONARY",
						"actor_unit_id": unit_id,
						"_ai_description": "%s holds %s despite lethal threat (OC %d vs %d, expected dmg %.1f/%.1f wounds)" % [unit_name, obj_id_held, friendly_oc_here, enemy_oc_here, survival.expected_damage, survival.remaining_wounds]
					}
			else:
				print("AIDecisionMaker: %s engaged on %s but winning OC war (%d vs %d), holding" % [unit_name, obj_id_held, friendly_oc_here, enemy_oc_here])
				return {
					"type": "REMAIN_STATIONARY",
					"actor_unit_id": unit_id,
					"_ai_description": "%s holds %s while engaged (OC %d vs %d)" % [unit_name, obj_id_held, friendly_oc_here, enemy_oc_here]
				}

		# If we're losing OC but falling back would lose the objective entirely
		var oc_without_us = friendly_oc_here - unit_oc
		if oc_without_us <= 0 and "REMAIN_STATIONARY" in move_types:
			if fb_and_charge:
				# With Fall Back and Charge we can charge back onto the objective
				print("AIDecisionMaker: %s engaged on %s, only holder but has Fall Back and Charge — will fall back to re-engage" % [unit_name, obj_id_held])
			else:
				# T7-27: Even as sole holder, warn if survival is lethal (unit may die anyway)
				if survival.is_lethal:
					print("AIDecisionMaker: T7-27 %s engaged on %s, only holder (OC %d) but survival is LETHAL (%.1f dmg vs %.1f wounds) — staying anyway to deny objective" % [
						unit_name, obj_id_held, unit_oc, survival.expected_damage, survival.remaining_wounds])
				else:
					print("AIDecisionMaker: %s engaged on %s, only holder (OC %d), staying" % [unit_name, obj_id_held, unit_oc])
				return {
					"type": "REMAIN_STATIONARY",
					"actor_unit_id": unit_id,
					"_ai_description": "%s stays on %s (only holder, OC: %d)" % [unit_name, obj_id_held, unit_oc]
				}

	# --- Ability-aware fall back decision (AI-GAP-4) ---
	var has_fb_ability = fb_and_charge or fb_and_shoot

	if has_fb_ability:
		var ability_text = []
		if fb_and_charge:
			ability_text.append("charge")
		if fb_and_shoot:
			ability_text.append("shoot")
		var ability_summary = " + ".join(ability_text)
		print("AIDecisionMaker: %s has Fall Back and %s — fall back is more attractive" % [unit_name, ability_summary])

	# Not on objective or better to fall back — fall back
	if "BEGIN_FALL_BACK" in move_types:
		var base_reason = "not on objective" if not on_objective else "losing OC war"

		# T7-27: Enrich reason with survival assessment
		if survival.is_lethal:
			base_reason = "%s, survival LETHAL (%.1f dmg vs %.1f wounds)" % [base_reason, survival.expected_damage, survival.remaining_wounds]
		elif survival.is_severe:
			base_reason = "%s, survival SEVERE (%.1f dmg vs %.1f wounds)" % [base_reason, survival.expected_damage, survival.remaining_wounds]

		# If the unit has Fall Back and X, enrich the reason
		var reason = base_reason
		if fb_and_charge:
			reason = "%s, can charge back (Fall Back and Charge)" % base_reason
		elif fb_and_shoot:
			reason = "%s, can still shoot (Fall Back and Shoot)" % base_reason

		# Compute fall-back destinations for all models (MOV-6)
		var fall_back_destinations = _compute_fall_back_destinations(
			unit, unit_id, snapshot, enemies, objectives, player
		)
		if not fall_back_destinations.is_empty():
			print("AIDecisionMaker: %s falling back with %d model destinations (%s)" % [unit_name, fall_back_destinations.size(), reason])
			return {
				"type": "BEGIN_FALL_BACK",
				"actor_unit_id": unit_id,
				"_ai_model_destinations": fall_back_destinations,
				"_ai_description": "%s falls back (%s)" % [unit_name, reason]
			}
		else:
			# Could not compute valid fall-back positions — remain stationary
			print("AIDecisionMaker: %s cannot find valid fall-back positions, remaining stationary" % unit_name)
			if "REMAIN_STATIONARY" in move_types:
				return {
					"type": "REMAIN_STATIONARY",
					"actor_unit_id": unit_id,
					"_ai_description": "%s remains stationary (no valid fall-back path)" % unit_name
				}

	if "REMAIN_STATIONARY" in move_types:
		return {
			"type": "REMAIN_STATIONARY",
			"actor_unit_id": unit_id,
			"_ai_description": "%s remains stationary (engaged, no fall back option)" % unit_name
		}

	return {}

# =============================================================================
# FALL-BACK MODEL POSITIONING (MOV-6)
# =============================================================================

static func _compute_fall_back_destinations(
	unit: Dictionary, unit_id: String, snapshot: Dictionary,
	enemies: Dictionary, objectives: Array, player: int
) -> Dictionary:
	"""Compute valid fall-back destinations for all models in an engaged unit.
	Each model must end:
	  1. Outside engagement range of ALL enemy models
	  2. Within its movement cap (M inches)
	  3. Not overlapping other models (friendly or enemy)
	  4. Within board bounds
	The AI picks a retreat direction: toward the nearest friendly objective or,
	failing that, directly away from the centroid of engaging enemies."""

	var alive_models = _get_alive_models_with_positions(unit)
	if alive_models.is_empty():
		return {}

	var move_inches = float(unit.get("meta", {}).get("stats", {}).get("move", 6))
	var move_px = move_inches * PIXELS_PER_INCH
	var centroid = _get_unit_centroid(unit)
	if centroid == Vector2.INF:
		return {}

	# Identify engaging enemy models and their centroid
	var engaging_enemy_centroid = _get_engaging_enemy_centroid(unit, unit_id, enemies)

	# Pick a retreat target: nearest uncontested friendly objective, or away from enemies
	var retreat_target = _pick_fall_back_target(centroid, engaging_enemy_centroid, objectives, enemies, player, snapshot)

	# Calculate retreat direction
	var retreat_direction: Vector2
	if retreat_target != Vector2.INF:
		retreat_direction = (retreat_target - centroid).normalized()
	else:
		# Fall back directly away from enemies
		if engaging_enemy_centroid != Vector2.INF:
			retreat_direction = (centroid - engaging_enemy_centroid).normalized()
		else:
			# Fallback: move toward own deployment zone (toward board edge)
			retreat_direction = Vector2(0, -1) if player == 1 else Vector2(0, 1)

	# Safety: if retreat direction is zero (target at our position), fall back
	# to moving directly away from enemies
	if retreat_direction.length_squared() < 0.01:
		if engaging_enemy_centroid != Vector2.INF:
			retreat_direction = (centroid - engaging_enemy_centroid).normalized()
		else:
			retreat_direction = Vector2(0, -1) if player == 1 else Vector2(0, 1)
		print("AIDecisionMaker: Retreat target at unit position, using away-from-enemy direction (%.2f, %.2f)" % [retreat_direction.x, retreat_direction.y])

	# Get deployed model positions for collision checking (excluding this unit)
	var deployed_models = _get_deployed_models_excluding_unit(snapshot, unit_id)
	var first_model = alive_models[0] if alive_models.size() > 0 else {}
	var base_mm = first_model.get("base_mm", 32)
	var base_type = first_model.get("base_type", "circular")
	var base_dimensions = first_model.get("base_dimensions", {})

	# Build original positions map
	var original_positions = {}
	for model in alive_models:
		var mid = model.get("id", "")
		if mid != "":
			original_positions[mid] = _get_model_position(model)

	# Get terrain features for blocking checks
	var terrain_features = snapshot.get("board", {}).get("terrain_features", [])
	var unit_keywords = unit.get("meta", {}).get("keywords", [])

	# Try the primary retreat direction first, then try alternate angles
	var directions_to_try = _build_fall_back_directions(retreat_direction)

	for direction in directions_to_try:
		# Try full move, then progressively shorter
		var fractions = [1.0, 0.75, 0.5, 0.25]
		for fraction in fractions:
			var move_vector = direction * move_px * fraction
			var destinations = _try_fall_back_positions(
				alive_models, move_vector, enemies, unit,
				deployed_models, base_mm, base_type, base_dimensions,
				original_positions, move_px, terrain_features, unit_keywords
			)
			if not destinations.is_empty():
				if fraction < 1.0:
					print("AIDecisionMaker: Fall-back using %.0f%% move in direction (%.1f, %.1f)" % [fraction * 100, direction.x, direction.y])
				return destinations

	# All directions failed
	print("AIDecisionMaker: Could not find valid fall-back destinations for %s" % unit_id)
	return {}

static func _get_engaging_enemy_centroid(unit: Dictionary, unit_id: String, enemies: Dictionary) -> Vector2:
	"""Find the centroid of all enemy models currently within engagement range of this unit."""
	var engaging_positions = []
	var alive_models = _get_alive_models_with_positions(unit)
	var own_models_data = unit.get("models", [])
	var own_base_mm = own_models_data[0].get("base_mm", 32) if own_models_data.size() > 0 else 32
	var own_radius_px = (own_base_mm / 2.0) * (PIXELS_PER_INCH / 25.4)

	for enemy_id in enemies:
		var enemy = enemies[enemy_id]
		for enemy_model in enemy.get("models", []):
			if not enemy_model.get("alive", true):
				continue
			var enemy_pos = _get_model_position(enemy_model)
			if enemy_pos == Vector2.INF:
				continue
			var enemy_base_mm = enemy_model.get("base_mm", 32)
			var enemy_radius_px = (enemy_base_mm / 2.0) * (PIXELS_PER_INCH / 25.4)
			var er_threshold = own_radius_px + enemy_radius_px + ENGAGEMENT_RANGE_PX

			# Check if this enemy model is within ER of any of our models
			for own_model in alive_models:
				var own_pos = _get_model_position(own_model)
				if own_pos == Vector2.INF:
					continue
				if own_pos.distance_to(enemy_pos) < er_threshold:
					engaging_positions.append(enemy_pos)
					break  # Only count this enemy model once

	if engaging_positions.is_empty():
		return Vector2.INF

	var sum_val = Vector2.ZERO
	for pos in engaging_positions:
		sum_val += pos
	return sum_val / engaging_positions.size()

# =============================================================================
# T7-27: ENGAGED UNIT SURVIVAL ASSESSMENT
# =============================================================================

static func _get_engaging_enemy_units(unit: Dictionary, unit_id: String, enemies: Dictionary) -> Array:
	"""Return an array of {enemy_id, enemy_unit} for all enemy units with at least one model
	within engagement range of this unit. Used for survival assessment."""
	var engaging = []
	var alive_models = _get_alive_models_with_positions(unit)
	var own_models_data = unit.get("models", [])
	var own_base_mm = own_models_data[0].get("base_mm", 32) if own_models_data.size() > 0 else 32
	var own_radius_px = (own_base_mm / 2.0) * (PIXELS_PER_INCH / 25.4)

	for enemy_id in enemies:
		var enemy = enemies[enemy_id]
		var is_engaging = false
		for enemy_model in enemy.get("models", []):
			if is_engaging:
				break
			if not enemy_model.get("alive", true):
				continue
			var enemy_pos = _get_model_position(enemy_model)
			if enemy_pos == Vector2.INF:
				continue
			var enemy_base_mm = enemy_model.get("base_mm", 32)
			var enemy_radius_px = (enemy_base_mm / 2.0) * (PIXELS_PER_INCH / 25.4)
			var er_threshold = own_radius_px + enemy_radius_px + ENGAGEMENT_RANGE_PX
			for own_model in alive_models:
				var own_pos = _get_model_position(own_model)
				if own_pos == Vector2.INF:
					continue
				if own_pos.distance_to(enemy_pos) < er_threshold:
					is_engaging = true
					break
		if is_engaging:
			engaging.append({"enemy_id": enemy_id, "enemy_unit": enemy})
	return engaging

static func _estimate_incoming_melee_damage(unit: Dictionary, enemies: Dictionary, unit_id: String) -> float:
	"""T7-27: Estimate total expected melee damage from all engaging enemy units
	in the upcoming fight phase. Uses _estimate_melee_damage in reverse —
	each engaging enemy attacks our unit."""
	var engaging = _get_engaging_enemy_units(unit, unit_id, enemies)
	var total_damage = 0.0
	for entry in engaging:
		var enemy = entry.enemy_unit
		var dmg = _estimate_melee_damage(enemy, unit)
		total_damage += dmg
	return total_damage

static func _estimate_unit_remaining_wounds(unit: Dictionary) -> float:
	"""T7-27: Calculate total remaining wounds across all alive models in a unit.
	Uses current_wounds when available (partially damaged models), otherwise
	falls back to the per-model wounds stat."""
	var total = 0.0
	var wounds_per_model = int(unit.get("meta", {}).get("stats", {}).get("wounds", 1))
	for model in unit.get("models", []):
		if model.get("alive", true):
			total += float(model.get("current_wounds", model.get("wounds", wounds_per_model)))
	return total

static func _assess_engaged_unit_survival(
	unit: Dictionary, unit_id: String, unit_name: String, enemies: Dictionary
) -> Dictionary:
	"""T7-27: Assess whether an engaged unit is likely to survive the fight phase.
	Returns a dictionary with:
	  - expected_damage: total expected melee damage from engaging enemies
	  - remaining_wounds: unit's total remaining wounds
	  - damage_ratio: expected_damage / remaining_wounds (0.0 to INF)
	  - is_lethal: true if damage_ratio >= SURVIVAL_LETHAL_THRESHOLD
	  - is_severe: true if damage_ratio >= SURVIVAL_SEVERE_THRESHOLD
	  - engaging_enemy_ids: list of engaging enemy unit IDs
	  - recommendation: "fall_back" or "hold" or "neutral"
	"""
	var remaining_wounds = _estimate_unit_remaining_wounds(unit)
	if remaining_wounds <= 0.0:
		return {
			"expected_damage": 0.0,
			"remaining_wounds": 0.0,
			"damage_ratio": 0.0,
			"is_lethal": false,
			"is_severe": false,
			"engaging_enemy_ids": [],
			"recommendation": "neutral"
		}

	var expected_damage = _estimate_incoming_melee_damage(unit, enemies, unit_id)
	var damage_ratio = expected_damage / remaining_wounds
	var is_lethal = damage_ratio >= SURVIVAL_LETHAL_THRESHOLD
	var is_severe = damage_ratio >= SURVIVAL_SEVERE_THRESHOLD

	var engaging = _get_engaging_enemy_units(unit, unit_id, enemies)
	var engaging_ids = []
	for entry in engaging:
		engaging_ids.append(entry.enemy_id)

	var recommendation = "neutral"
	if is_lethal:
		recommendation = "fall_back"
	elif is_severe:
		recommendation = "fall_back"
	elif damage_ratio < 0.25:
		recommendation = "hold"

	print("AIDecisionMaker: T7-27 Survival assessment for %s: expected_damage=%.1f, remaining_wounds=%.1f, ratio=%.2f, recommendation=%s (engaging: %s)" % [
		unit_name, expected_damage, remaining_wounds, damage_ratio, recommendation, str(engaging_ids)])

	return {
		"expected_damage": expected_damage,
		"remaining_wounds": remaining_wounds,
		"damage_ratio": damage_ratio,
		"is_lethal": is_lethal,
		"is_severe": is_severe,
		"engaging_enemy_ids": engaging_ids,
		"recommendation": recommendation
	}

static func _pick_fall_back_target(
	centroid: Vector2, enemy_centroid: Vector2,
	objectives: Array, enemies: Dictionary, player: int,
	snapshot: Dictionary
) -> Vector2:
	"""Pick the best retreat target for a falling-back unit.
	Priority: nearest friendly-controlled or uncontrolled objective that is
	away from the engaging enemy. If none found, returns Vector2.INF (caller
	will default to moving directly away from enemies)."""
	var friendly_units = _get_units_for_player(snapshot, player)
	var best_target = Vector2.INF
	var best_score = -INF

	# Compute "away from enemy" direction for directional scoring
	var away_from_enemy = Vector2.ZERO
	if enemy_centroid != Vector2.INF:
		away_from_enemy = (centroid - enemy_centroid).normalized()

	for obj_pos in objectives:
		# Skip objectives at or very near our current position — can't retreat
		# TO where we already are (would produce a zero retreat direction)
		var dist_to_obj = centroid.distance_to(obj_pos)
		if dist_to_obj < ENGAGEMENT_RANGE_PX:
			continue

		# Skip objectives that are closer to the engaging enemy than to us
		if enemy_centroid != Vector2.INF:
			var enemy_dist_to_obj = enemy_centroid.distance_to(obj_pos)
			var our_dist_to_obj = dist_to_obj
			# Only consider objectives that are roughly "behind" us relative to the enemy
			if enemy_dist_to_obj < our_dist_to_obj * 0.7:
				continue

		# Prefer closer objectives
		var score = -dist_to_obj

		# Directional bonus: strongly prefer objectives in the "away from enemy" direction
		if away_from_enemy != Vector2.ZERO and dist_to_obj > 0.01:
			var dir_to_obj = (obj_pos - centroid).normalized()
			var alignment = away_from_enemy.dot(dir_to_obj)  # -1 to +1
			# Bonus of up to +300 for objectives directly away from enemy
			# Penalty of up to -300 for objectives directly toward the enemy
			score += alignment * 300.0

		# Prefer objectives we already control
		var friendly_oc = _get_oc_at_position(obj_pos, friendly_units, player, true)
		var enemy_oc = _get_oc_at_position(obj_pos, enemies, player, false)
		if friendly_oc > enemy_oc:
			score += 200.0  # Strongly prefer friendly-controlled objectives
		elif friendly_oc == 0 and enemy_oc == 0:
			score += 100.0  # Uncontrolled objectives are next best

		if score > best_score:
			best_score = score
			best_target = obj_pos

	return best_target

static func _build_fall_back_directions(primary_direction: Vector2) -> Array:
	"""Build an array of retreat directions to try, starting with the primary
	and branching out to alternates at +/-30, +/-60, +/-90, +/-120, +/-150, and 180 degrees."""
	var directions = [primary_direction]
	var angles = [
		deg_to_rad(30), deg_to_rad(-30),
		deg_to_rad(60), deg_to_rad(-60),
		deg_to_rad(90), deg_to_rad(-90),
		deg_to_rad(120), deg_to_rad(-120),
		deg_to_rad(150), deg_to_rad(-150),
		deg_to_rad(180)
	]
	for angle in angles:
		directions.append(primary_direction.rotated(angle))
	return directions

static func _try_fall_back_positions(
	alive_models: Array, move_vector: Vector2, enemies: Dictionary,
	unit: Dictionary, deployed_models: Array, base_mm: int,
	base_type: String, base_dimensions: Dictionary,
	original_positions: Dictionary, move_cap_px: float,
	terrain_features: Array, unit_keywords: Array
) -> Dictionary:
	"""Try moving all models by move_vector for a fall-back. Unlike normal movement,
	fall-back REQUIRES that every model ends OUTSIDE engagement range of all enemies.
	Returns model_id -> [x, y] destinations, or empty dict if any model cannot be placed."""
	var destinations = {}
	var placed_models: Array = []

	for model in alive_models:
		var model_id = model.get("id", "")
		if model_id == "":
			continue
		var model_pos = _get_model_position(model)
		if model_pos == Vector2.INF:
			continue
		var dest = model_pos + move_vector

		# Clamp to board bounds with margin
		dest.x = clamp(dest.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
		dest.y = clamp(dest.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)

		# Check movement cap
		var orig_pos = original_positions.get(model_id, model_pos)
		if orig_pos.distance_to(dest) > move_cap_px + 1.0:  # +1 tolerance
			return {}

		# CRITICAL: Fall-back models MUST end outside engagement range
		if _is_position_near_enemy(dest, enemies, unit):
			# Try small offsets perpendicular to the move direction to escape ER
			var resolved = _resolve_fall_back_position(
				dest, move_vector, base_mm, base_type, base_dimensions,
				deployed_models + placed_models, enemies, unit,
				orig_pos, move_cap_px
			)
			if resolved == Vector2.INF:
				return {}  # Cannot escape ER with this direction
			dest = resolved

		# Check terrain blocking
		if _path_blocked_by_terrain(model_pos, dest, unit_keywords, terrain_features):
			return {}

		# Check overlap with deployed models and already-placed models
		var all_obstacles = deployed_models + placed_models
		if _position_collides_with_deployed(dest, base_mm, all_obstacles, 4.0, base_type, base_dimensions):
			var resolved = _resolve_fall_back_position(
				dest, move_vector, base_mm, base_type, base_dimensions,
				all_obstacles, enemies, unit, orig_pos, move_cap_px
			)
			if resolved == Vector2.INF:
				return {}
			dest = resolved

		destinations[model_id] = [dest.x, dest.y]
		placed_models.append({
			"position": dest,
			"base_mm": base_mm,
			"base_type": base_type,
			"base_dimensions": base_dimensions
		})

	return destinations

static func _resolve_fall_back_position(
	dest: Vector2, move_vector: Vector2, base_mm: int,
	base_type: String, base_dimensions: Dictionary,
	obstacles: Array, enemies: Dictionary, unit: Dictionary,
	original_pos: Vector2, move_cap_px: float
) -> Vector2:
	"""Try perpendicular and diagonal offsets to find a valid fall-back position
	that is outside engagement range and doesn't collide with other models."""
	var perp = Vector2(-move_vector.y, move_vector.x).normalized()
	if perp == Vector2.ZERO:
		# move_vector is zero, try cardinal directions
		perp = Vector2(1, 0)
	var base_radius = _model_bounding_radius_px(base_mm, base_type, base_dimensions)
	# Try wider range of offsets for fall-back (more aggressive positioning)
	var offsets = [1.0, -1.0, 2.0, -2.0, 3.0, -3.0, 4.0, -4.0]

	for multiplier in offsets:
		var offset = perp * base_radius * multiplier
		var candidate = dest + offset

		# Check board bounds
		if candidate.x < BASE_MARGIN_PX or candidate.x > BOARD_WIDTH_PX - BASE_MARGIN_PX:
			continue
		if candidate.y < BASE_MARGIN_PX or candidate.y > BOARD_HEIGHT_PX - BASE_MARGIN_PX:
			continue

		# Check movement cap
		if original_pos != Vector2.INF and move_cap_px > 0.0:
			if original_pos.distance_to(candidate) > move_cap_px + 1.0:
				continue

		# Must be outside engagement range
		if _is_position_near_enemy(candidate, enemies, unit):
			continue

		# Must not collide with other models
		if _position_collides_with_deployed(candidate, base_mm, obstacles, 4.0, base_type, base_dimensions):
			continue

		return candidate

	return Vector2.INF  # No valid position found

# =============================================================================
# ADVANCE DECISION LOGIC (Task 3 + Task 6)
# =============================================================================

static func _should_unit_advance(
	unit: Dictionary, dist_inches: float, move_inches: float,
	has_ranged: bool, max_weapon_range: float, enemies: Dictionary,
	centroid: Vector2, battle_round: int, obj_eval: Dictionary
) -> bool:
	# Can't reach with normal move but can with advance?
	var can_reach_normal = dist_inches <= move_inches
	var can_reach_advance = dist_inches <= move_inches + 2.0  # Average advance

	if can_reach_normal:
		return false  # Normal move is enough

	if not can_reach_advance:
		return false  # Can't reach even with advance

	# --- AI-GAP-4: Check for Advance and X abilities ---
	# If the unit can advance and still shoot/charge, advancing has no downside
	var unit_id = unit.get("id", "")
	# Note: we check flags directly since leader bonuses should already be applied
	# by UnitAbilityManager during the movement phase
	var adv_and_shoot = unit.get("flags", {}).get("effect_advance_and_shoot", false)
	var adv_and_charge = unit.get("flags", {}).get("effect_advance_and_charge", false)

	# Also check via description-based detection for broader coverage
	if not adv_and_shoot:
		adv_and_shoot = AIAbilityAnalyzerData.unit_has_ability_containing(unit, "advance") and AIAbilityAnalyzerData.unit_has_ability_containing(unit, "shoot")
	if not adv_and_charge:
		adv_and_charge = AIAbilityAnalyzerData.unit_has_ability_containing(unit, "advance") and AIAbilityAnalyzerData.unit_has_ability_containing(unit, "charge")

	if adv_and_shoot:
		print("AIDecisionMaker: %s has Advance and Shoot — advancing has no shooting penalty" % unit.get("meta", {}).get("name", unit_id))
		return true  # No downside to advancing

	if adv_and_charge:
		print("AIDecisionMaker: %s has Advance and Charge — advancing allows charge" % unit.get("meta", {}).get("name", unit_id))
		return true  # Can still charge after advancing

	# Units without ranged weapons should always advance
	if not has_ranged:
		return true

	# Battle-shocked units can't shoot anyway — advance
	if unit.get("flags", {}).get("battle_shocked", false):
		return true

	# Round 1: aggressive positioning is critical for Round 2 scoring
	if battle_round == 1:
		# Advance to reach no-man's-land objectives
		if obj_eval.get("zone", "") == "no_mans_land":
			return true

	# High-priority uncontrolled objective: advancing to grab it is worth losing shooting
	if obj_eval.get("state", "") == "uncontrolled" and obj_eval.get("priority", 0) >= 8.0:
		return true

	# Cross-phase consideration (Task 6): check if we have viable shooting targets nearby
	var has_targets_in_range = false
	for enemy_id in enemies:
		var enemy = enemies[enemy_id]
		var enemy_centroid = _get_unit_centroid(enemy)
		if enemy_centroid == Vector2.INF:
			continue
		if centroid.distance_to(enemy_centroid) <= max_weapon_range * PIXELS_PER_INCH:
			has_targets_in_range = true
			break

	# If no targets in range anyway, advancing costs nothing
	if not has_targets_in_range:
		return true

	# Otherwise, prefer shooting over advancing
	return false

# =============================================================================
# MOVEMENT HELPERS (Enhanced)
# =============================================================================

static func _get_oc_at_position(pos: Vector2, units: Dictionary, player: int, is_friendly: bool) -> int:
	# Sum up OC values of all units within control range of a position
	var total_oc = 0
	for uid in units:
		var unit = units[uid]
		# Skip battle-shocked units (they have 0 effective OC)
		if unit.get("flags", {}).get("battle_shocked", false):
			continue
		var status = unit.get("status", 0)
		if status == GameStateData.UnitStatus.UNDEPLOYED or status == GameStateData.UnitStatus.IN_RESERVES:
			continue
		var oc_val = int(unit.get("meta", {}).get("stats", {}).get("objective_control", 0))
		if oc_val <= 0:
			continue
		# Check if any alive model is within control range
		for model in unit.get("models", []):
			if not model.get("alive", true):
				continue
			var mpos = _get_model_position(model)
			if mpos == Vector2.INF:
				continue
			if mpos.distance_to(pos) <= OBJECTIVE_CONTROL_RANGE_PX:
				total_oc += oc_val
				break  # Count unit once
	return total_oc

static func _count_units_near_position(pos: Vector2, units: Dictionary, range_px: float) -> int:
	var count = 0
	for uid in units:
		var unit = units[uid]
		var status = unit.get("status", 0)
		if status == GameStateData.UnitStatus.UNDEPLOYED or status == GameStateData.UnitStatus.IN_RESERVES:
			continue
		var centroid = _get_unit_centroid(unit)
		if centroid == Vector2.INF:
			continue
		if centroid.distance_to(pos) <= range_px:
			count += 1
	return count

static func _unit_has_ranged_weapons(unit: Dictionary) -> bool:
	var weapons = unit.get("meta", {}).get("weapons", [])
	for w in weapons:
		if w.get("type", "").to_lower() == "ranged":
			return true
	return false

static func _get_max_weapon_range(unit: Dictionary) -> float:
	var max_range = 0.0
	var weapons = unit.get("meta", {}).get("weapons", [])
	for w in weapons:
		if w.get("type", "").to_lower() == "ranged":
			var range_str = w.get("range", "0")
			if range_str.is_valid_float():
				max_range = max(max_range, float(range_str))
			elif range_str.is_valid_int():
				max_range = max(max_range, float(int(range_str)))
	return max_range

static func _get_weapon_range_inches(weapon: Dictionary) -> float:
	"""Parse a weapon's range field and return the range in inches. Returns 0.0 for melee or invalid."""
	var range_str = str(weapon.get("range", "0"))
	if range_str.to_lower() == "melee":
		return 0.0
	# Handle strings like "24", "36", "12" etc.
	# Also strip trailing quote mark if present (e.g. '24"')
	range_str = range_str.replace("\"", "").strip_edges()
	if range_str.is_valid_float():
		return float(range_str)
	elif range_str.is_valid_int():
		return float(int(range_str))
	return 0.0

# =============================================================================
# T7-30: HALF-RANGE WEAPON ANALYSIS (SHOOT-6)
# =============================================================================

static func _get_unit_half_range_data(unit: Dictionary) -> Dictionary:
	"""T7-30: Analyze a unit's weapons for half-range bonuses (Rapid Fire, Melta).
	Returns {has_bonus, best_half_range_inches, total_benefit, weapons: [{name, rapid_fire, melta, half_range_inches, full_range_inches}]}
	total_benefit = sum of (rapid_fire_val + melta_val) across all qualifying weapons, scaled by model count."""
	var weapons = unit.get("meta", {}).get("weapons", [])
	var result = {"has_bonus": false, "best_half_range_inches": 0.0, "total_benefit": 0.0, "weapons": []}
	var model_count = _get_alive_models(unit).size()
	if model_count < 1:
		model_count = 1

	for w in weapons:
		if w.get("type", "").to_lower() != "ranged":
			continue
		var special_rules = w.get("special_rules", "").to_lower()
		var weapon_range = _get_weapon_range_inches(w)
		if weapon_range <= 0.0:
			continue
		var half_range = weapon_range / 2.0
		var rf_val = _parse_rapid_fire_value(special_rules)
		var melta_val = _parse_melta_value(special_rules)
		if rf_val > 0 or melta_val > 0:
			result.has_bonus = true
			result.best_half_range_inches = max(result.best_half_range_inches, half_range)
			result.total_benefit += float(rf_val + melta_val) * model_count
			result.weapons.append({
				"name": w.get("name", ""),
				"rapid_fire": rf_val,
				"melta": melta_val,
				"half_range_inches": half_range,
				"full_range_inches": weapon_range
			})
	return result

static func _find_best_half_range_position(
	centroid: Vector2, enemies: Dictionary, half_range_data: Dictionary, snapshot: Dictionary = {}, shooter_unit: Dictionary = {}
) -> Vector2:
	"""T7-30: Find the best position that puts the unit within half range of a high-value enemy.
	Only considers enemies currently in full range but beyond half range.
	Returns Vector2.INF if no beneficial repositioning exists."""
	if not half_range_data.has_bonus:
		return Vector2.INF

	var best_target = Vector2.INF
	var best_score = 0.0

	for enemy_id in enemies:
		var enemy = enemies[enemy_id]
		var enemy_centroid = _get_unit_centroid(enemy)
		if enemy_centroid == Vector2.INF:
			continue
		var dist_px = centroid.distance_to(enemy_centroid)
		var dist_inches = dist_px / PIXELS_PER_INCH

		# Calculate benefit for each weapon against this enemy
		var benefit = 0.0
		var applicable_half_range_px = 0.0
		for w_data in half_range_data.weapons:
			# Enemy must be within full range but beyond half range
			if dist_inches <= w_data.full_range_inches and dist_inches > w_data.half_range_inches:
				benefit += float(w_data.rapid_fire + w_data.melta)
				applicable_half_range_px = max(applicable_half_range_px, w_data.half_range_inches * PIXELS_PER_INCH)

		if benefit <= 0.0 or applicable_half_range_px <= 0.0:
			continue

		# Weight by enemy value if we can estimate it
		var enemy_value = 1.0
		if not snapshot.is_empty():
			var alive_models = _get_alive_models(enemy).size()
			var total_models = enemy.get("models", []).size()
			# Prefer closing on damaged units (easier to finish off)
			if total_models > 0 and alive_models * 2 < total_models:
				enemy_value = 1.5

		var score = benefit * enemy_value

		if score > best_score:
			best_score = score
			# Compute a position at half range of this enemy (with safety margin)
			var dir = (enemy_centroid - centroid).normalized()
			var margin_px = HALF_RANGE_APPROACH_MARGIN_INCHES * PIXELS_PER_INCH
			var desired_dist_px = applicable_half_range_px - margin_px
			var move_distance_px = max(0.0, dist_px - desired_dist_px)
			best_target = centroid + dir * move_distance_px

	return best_target if best_score >= HALF_RANGE_MIN_BENEFIT else Vector2.INF

# =============================================================================
# SHOOTING RANGE CONSIDERATION FOR MOVEMENT (MOV-1)
# =============================================================================

static func _get_enemies_in_weapon_range(centroid: Vector2, max_weapon_range: float, enemies: Dictionary) -> Array:
	"""Return array of {enemy_id, enemy_centroid, distance_inches} for enemies within weapon range."""
	var in_range = []
	if max_weapon_range <= 0.0:
		return in_range
	var range_px = max_weapon_range * PIXELS_PER_INCH
	for enemy_id in enemies:
		var enemy = enemies[enemy_id]
		var enemy_centroid = _get_unit_centroid(enemy)
		if enemy_centroid == Vector2.INF:
			continue
		var dist = centroid.distance_to(enemy_centroid)
		if dist <= range_px:
			in_range.append({
				"enemy_id": enemy_id,
				"enemy_centroid": enemy_centroid,
				"distance_inches": dist / PIXELS_PER_INCH
			})
	return in_range

static func _clamp_move_for_weapon_range(
	centroid: Vector2, move_vector: Vector2, max_weapon_range: float,
	enemies: Dictionary, unit_name: String
) -> Vector2:
	"""
	Clamp a movement vector so the unit stays within weapon range of the nearest
	enemy it can currently shoot. Returns the (possibly shortened) move vector.
	If no clamping is needed, returns the original vector.
	"""
	if max_weapon_range <= 0.0:
		return move_vector  # No ranged weapons, no constraint

	var range_px = max_weapon_range * PIXELS_PER_INCH
	var proposed_pos = centroid + move_vector

	# Find all enemies currently in range
	var enemies_in_range = _get_enemies_in_weapon_range(centroid, max_weapon_range, enemies)
	if enemies_in_range.is_empty():
		return move_vector  # No enemies in range currently, move freely

	# Check if the proposed destination keeps at least one current target in range
	var keeps_any_target = false
	for entry in enemies_in_range:
		if proposed_pos.distance_to(entry.enemy_centroid) <= range_px:
			keeps_any_target = true
			break

	if keeps_any_target:
		return move_vector  # Movement is fine, at least one target stays in range

	# The move would lose all current targets. Clamp the movement.
	# Find the nearest enemy that is currently in range
	var nearest_enemy_pos = Vector2.INF
	var nearest_dist = INF
	for entry in enemies_in_range:
		var d = centroid.distance_to(entry.enemy_centroid)
		if d < nearest_dist:
			nearest_dist = d
			nearest_enemy_pos = entry.enemy_centroid

	if nearest_enemy_pos == Vector2.INF:
		return move_vector  # Shouldn't happen, but safety fallback

	# Binary search for the maximum fraction of the move that keeps us in range
	var low = 0.0
	var high = 1.0
	var best_fraction = 0.0

	for _i in range(8):  # 8 iterations gives ~0.4% precision
		var mid = (low + high) / 2.0
		var test_pos = centroid + move_vector * mid
		if test_pos.distance_to(nearest_enemy_pos) <= range_px:
			best_fraction = mid
			low = mid
		else:
			high = mid

	if best_fraction <= 0.05:
		# Can barely move at all without losing range — stay put
		print("AIDecisionMaker: %s would lose all shooting targets — clamping to zero movement" % unit_name)
		return Vector2.ZERO

	var clamped = move_vector * best_fraction
	print("AIDecisionMaker: %s movement clamped to %.0f%% to stay within %.0f\" weapon range of nearest enemy" % [
		unit_name, best_fraction * 100.0, max_weapon_range])
	return clamped

static func _should_hold_for_shooting(
	unit: Dictionary, centroid: Vector2, target_pos: Vector2,
	max_weapon_range: float, enemies: Dictionary, move_inches: float,
	assignment: Dictionary
) -> bool:
	"""
	Determine if a ranged unit should remain stationary to maintain shooting
	rather than moving toward a distant objective. Returns true if the unit
	should hold for shooting.
	"""
	if max_weapon_range <= 0.0:
		return false  # No ranged weapons

	# Check if there are enemies currently in weapon range
	var enemies_in_range = _get_enemies_in_weapon_range(centroid, max_weapon_range, enemies)
	if enemies_in_range.is_empty():
		return false  # No targets to shoot, move freely

	# If the objective is close enough to reach this turn, move toward it
	# (being on the objective is usually more important than one turn of shooting)
	var dist_to_obj = centroid.distance_to(target_pos) if target_pos != Vector2.INF else INF
	var dist_to_obj_inches = dist_to_obj / PIXELS_PER_INCH
	if dist_to_obj_inches <= move_inches:
		return false  # Can reach objective this turn, do it

	# If the objective is high-priority (contested, uncontrolled, or needs OC),
	# and we can reach it in 2 turns, don't hold just for shooting
	var obj_priority = assignment.get("score", 0.0)
	var turns_to_reach = max(1.0, ceil(dist_to_obj_inches / move_inches)) if move_inches > 0 else 99.0
	if obj_priority >= 10.0 and turns_to_reach <= 2:
		return false  # High priority objective close enough, keep moving

	# Check if moving toward the objective would take us out of range of all targets
	var direction = (target_pos - centroid).normalized() if target_pos != Vector2.INF else Vector2.ZERO
	var move_vector = direction * move_inches * PIXELS_PER_INCH
	var proposed_pos = centroid + move_vector
	var range_px = max_weapon_range * PIXELS_PER_INCH

	var keeps_any_target = false
	for entry in enemies_in_range:
		if proposed_pos.distance_to(entry.enemy_centroid) <= range_px:
			keeps_any_target = true
			break

	if keeps_any_target:
		return false  # Moving keeps targets in range, go ahead

	# T7-30: Before deciding to hold, check if the unit has Rapid Fire/Melta weapons
	# that would benefit from moving forward to half range. If so, don't hold — let
	# the movement logic push toward half range for the damage bonus.
	var half_range_data = _get_unit_half_range_data(unit)
	if half_range_data.has_bonus and half_range_data.total_benefit >= HALF_RANGE_MIN_BENEFIT:
		# Check if any enemy in range is beyond half range (would benefit from closing)
		var would_benefit_from_closing = false
		for entry in enemies_in_range:
			for w_data in half_range_data.weapons:
				if entry.distance_inches > w_data.half_range_inches and entry.distance_inches <= w_data.full_range_inches:
					would_benefit_from_closing = true
					break
			if would_benefit_from_closing:
				break
		if would_benefit_from_closing:
			var unit_name = unit.get("meta", {}).get("name", "unit")
			print("AIDecisionMaker: [T7-30] %s has Rapid Fire/Melta weapons (benefit=%.1f) — not holding, advancing toward half range" % [
				unit_name, half_range_data.total_benefit])
			return false  # Don't hold — let movement code push toward half range

	# Moving would lose all targets and objective isn't reachable this turn
	# Prefer staying and shooting
	print("AIDecisionMaker: %s has %d enemies in weapon range (max %.0f\") — holding for shooting rather than moving to distant objective (%.1f\" away, %d turns)" % [
		unit.get("meta", {}).get("name", "unit"), enemies_in_range.size(), max_weapon_range,
		dist_to_obj_inches, int(turns_to_reach)])
	return true

static func _nearest_objective_pos(pos: Vector2, objectives: Array) -> Vector2:
	var best = Vector2.INF
	var best_dist = INF
	for obj_pos in objectives:
		var d = pos.distance_to(obj_pos)
		if d < best_dist:
			best_dist = d
			best = obj_pos
	return best

static func _get_obj_eval_by_id(evaluations: Array, obj_id: String) -> Dictionary:
	for eval in evaluations:
		if eval.id == obj_id:
			return eval
	return {}

static func _find_best_remaining_objective(
	centroid: Vector2, obj_evaluations: Array, enemies: Dictionary,
	unit: Dictionary, snapshot: Dictionary, player: int
) -> Dictionary:
	# For unassigned units: find the best objective to support or screen near
	var best_score = -INF
	var best = {}
	var move_inches = float(unit.get("meta", {}).get("stats", {}).get("move", 6))
	var unit_oc = int(unit.get("meta", {}).get("stats", {}).get("objective_control", 1))
	var has_ranged = _unit_has_ranged_weapons(unit)

	for eval in obj_evaluations:
		var dist = centroid.distance_to(eval.position)
		var dist_inches = dist / PIXELS_PER_INCH

		# Score based on: priority + proximity + can we help?
		var score = eval.priority
		score -= dist_inches * 0.5  # Closer is better

		# Contested/threatened objectives benefit most from reinforcement
		if eval.state in ["contested", "held_threatened", "enemy_weak"]:
			score += 3.0

		# Screening position: place between enemy and valuable friendly-held objectives
		if eval.state == "held_safe" and eval.enemy_nearby > 0:
			score += 2.0  # Screen for held objectives

		# Shooting support: ranged units should move toward enemy-adjacent objectives
		if has_ranged and eval.enemy_nearby > 0:
			score += 1.5

		if score > best_score:
			best_score = score
			var action = "move"
			var reason = "supporting nearby objective"
			if dist <= OBJECTIVE_CONTROL_RANGE_PX:
				action = "hold"
				reason = "already at objective"
			best = {
				"objective_id": eval.id,
				"objective_pos": eval.position,
				"action": action,
				"score": score,
				"reason": reason,
				"distance": dist,
				"unit_oc": unit_oc
			}

	return best

static func _compute_movement_toward_target(
	unit: Dictionary, unit_id: String, target_pos: Vector2,
	move_inches: float, snapshot: Dictionary, enemies: Dictionary,
	max_weapon_range: float = 0.0, threat_data: Array = [], objectives: Array = []
) -> Dictionary:
	# Generalized version of _compute_movement_toward_objective that takes a specific target position
	if target_pos == Vector2.INF:
		return {}

	var alive_models = _get_alive_models_with_positions(unit)
	if alive_models.is_empty():
		return {}

	var centroid = _get_unit_centroid(unit)
	if centroid == Vector2.INF:
		return {}

	# Calculate movement vector toward target
	var direction = (target_pos - centroid).normalized()
	var move_px = move_inches * PIXELS_PER_INCH
	var dist_to_target = centroid.distance_to(target_pos)
	var actual_move_px = min(move_px, dist_to_target)
	var move_vector = direction * actual_move_px

	# Get terrain features for blocking checks
	var terrain_features = snapshot.get("board", {}).get("terrain_features", [])
	var unit_keywords = unit.get("meta", {}).get("keywords", [])

	# Check if the direct path is blocked by terrain (Task 8: terrain-aware pathing)
	var final_move_vector = _find_unblocked_move_enhanced(
		centroid, move_vector, actual_move_px, unit_keywords, terrain_features, enemies, unit
	)

	if final_move_vector == Vector2.ZERO:
		print("AIDecisionMaker: All movement paths blocked by terrain")
		return {}

	# --- MOV-1: Clamp movement to maintain weapon range on current targets ---
	if max_weapon_range > 0.0:
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		final_move_vector = _clamp_move_for_weapon_range(
			centroid, final_move_vector, max_weapon_range, enemies, unit_name
		)
		if final_move_vector == Vector2.ZERO:
			# Movement was clamped to zero — no valid move that keeps targets in range
			return {}

	# --- AI-TACTIC-4: Threat-aware position adjustment ---
	# If the destination would place us in a significantly more dangerous position,
	# try to find a safer alternative that still makes progress
	if not threat_data.is_empty():
		var desired_dest = centroid + final_move_vector
		var safer_dest = _find_safer_position(centroid, desired_dest, move_px, threat_data, unit, objectives)
		if safer_dest != desired_dest:
			final_move_vector = safer_dest - centroid

	# Get all deployed model positions (excluding this unit's own models) for overlap checking
	var deployed_models = _get_deployed_models_excluding_unit(snapshot, unit_id)
	var first_model = alive_models[0] if alive_models.size() > 0 else {}
	var base_mm = first_model.get("base_mm", 32)
	var base_type = first_model.get("base_type", "circular")
	var base_dimensions = first_model.get("base_dimensions", {})

	# Build original positions map for movement cap checking during collision resolution
	var original_positions = {}
	for model in alive_models:
		var mid = model.get("id", "")
		if mid != "":
			original_positions[mid] = _get_model_position(model)

	# Try the full move first, then progressively shorter moves
	var fractions_to_try = [1.0, 0.75, 0.5, 0.25]
	for fraction in fractions_to_try:
		var try_vector = final_move_vector * fraction
		var destinations = _try_move_with_collision_check(
			alive_models, try_vector, enemies, unit, deployed_models,
			base_mm, base_type, base_dimensions, original_positions, move_px
		)
		if not destinations.is_empty():
			if fraction < 1.0:
				print("AIDecisionMaker: Using %.0f%% move to avoid model overlap" % (fraction * 100))
			return destinations

	# All fractions failed
	return {}

static func _find_unblocked_move_enhanced(
	centroid: Vector2, move_vector: Vector2, move_distance_px: float,
	unit_keywords: Array, terrain_features: Array,
	enemies: Dictionary, unit: Dictionary
) -> Vector2:
	# Enhanced version with terrain-aware pathing (Task 8)
	# Try the direct path first
	if not _path_blocked_by_terrain(centroid, centroid + move_vector, unit_keywords, terrain_features):
		# Task 8: Check if a path through cover would be better
		var cover_path = _find_cover_path(centroid, move_vector, move_distance_px, unit_keywords, terrain_features, enemies)
		if cover_path != Vector2.ZERO:
			return cover_path
		return move_vector

	print("AIDecisionMaker: Direct path blocked, trying alternate directions")

	# Try angled alternatives: +/-30, +/-60, +/-90
	var base_direction = move_vector.normalized()
	var angles_to_try = [
		deg_to_rad(30), deg_to_rad(-30),
		deg_to_rad(60), deg_to_rad(-60),
		deg_to_rad(90), deg_to_rad(-90)
	]

	for angle in angles_to_try:
		var rotated_dir = base_direction.rotated(angle)
		var alt_vector = rotated_dir * move_distance_px
		if not _path_blocked_by_terrain(centroid, centroid + alt_vector, unit_keywords, terrain_features):
			print("AIDecisionMaker: Found unblocked path at %.0f degrees" % rad_to_deg(angle))
			return alt_vector

	# Try moving at half distance in the original direction
	var half_vector = move_vector * 0.5
	if not _path_blocked_by_terrain(centroid, centroid + half_vector, unit_keywords, terrain_features):
		print("AIDecisionMaker: Moving at half distance to avoid terrain")
		return half_vector

	# All paths blocked
	return Vector2.ZERO

# =============================================================================
# TERRAIN-AWARE PATHING (Task 8)
# =============================================================================

static func _find_cover_path(
	centroid: Vector2, move_vector: Vector2, move_distance_px: float,
	unit_keywords: Array, terrain_features: Array, enemies: Dictionary
) -> Vector2:
	# Check if there's a safer path that ends in/near cover from enemy LoS
	# Only redirect if enemies are nearby and cover is available along the route
	var dest = centroid + move_vector

	# Find nearby enemy positions
	var enemy_positions = []
	for eid in enemies:
		var enemy = enemies[eid]
		var ecentroid = _get_unit_centroid(enemy)
		if ecentroid != Vector2.INF:
			enemy_positions.append(ecentroid)

	if enemy_positions.is_empty():
		return Vector2.ZERO  # No enemies to hide from, use direct path

	# Check if the direct destination has terrain cover from enemies
	var direct_has_cover = _position_has_cover(dest, enemy_positions, terrain_features)
	if direct_has_cover:
		return Vector2.ZERO  # Direct path already ends in cover

	# Try slight adjustments (+/-15, +/-30 degrees) to find a covered endpoint
	var base_dir = move_vector.normalized()
	var small_angles = [deg_to_rad(15), deg_to_rad(-15), deg_to_rad(30), deg_to_rad(-30)]

	for angle in small_angles:
		var alt_dir = base_dir.rotated(angle)
		var alt_vector = alt_dir * move_distance_px
		var alt_dest = centroid + alt_vector
		if not _path_blocked_by_terrain(centroid, alt_dest, unit_keywords, terrain_features):
			if _position_has_cover(alt_dest, enemy_positions, terrain_features):
				print("AIDecisionMaker: Found cover path at %.0f degrees offset" % rad_to_deg(angle))
				return alt_vector

	return Vector2.ZERO  # No better cover path found

static func _position_has_cover(pos: Vector2, enemy_positions: Array, terrain_features: Array) -> bool:
	# Check if a position has terrain between it and enemy positions (providing cover/LoS blocking)
	for enemy_pos in enemy_positions:
		for terrain in terrain_features:
			var polygon = terrain.get("polygon", [])
			var packed = PackedVector2Array()
			if polygon is PackedVector2Array:
				packed = polygon
			elif polygon is Array and polygon.size() >= 3:
				for p in polygon:
					if p is Vector2:
						packed.append(p)
					elif p is Dictionary:
						packed.append(Vector2(float(p.get("x", 0)), float(p.get("y", 0))))

			if packed.size() >= 3:
				# Check if terrain blocks LoS from enemy to this position
				if _line_intersects_polygon(enemy_pos, pos, packed):
					return true  # At least one enemy has LoS blocked by terrain
	return false

# =============================================================================
# SCREENING/DEFENSIVE POSITIONING (Task 7 + T7-15)
# =============================================================================

## Get enemy units currently in reserves (deep strike / strategic reserves)
static func _get_enemy_reserves(snapshot: Dictionary, player: int) -> Array:
	var reserves = []
	for unit_id in snapshot.get("units", {}):
		var unit = snapshot.units[unit_id]
		if unit.get("owner", 0) == player:
			continue  # Skip friendly units
		var status = unit.get("status", 0)
		if status == GameStateData.UnitStatus.IN_RESERVES:
			var has_alive = false
			for model in unit.get("models", []):
				if model.get("alive", true):
					has_alive = true
					break
			if has_alive:
				var reserve_type = unit.get("reserve_type", "strategic_reserves")
				var points = int(unit.get("meta", {}).get("points", 0))
				var unit_name = unit.get("meta", {}).get("name", unit_id)
				reserves.append({
					"unit_id": unit_id,
					"unit": unit,
					"reserve_type": reserve_type,
					"points": points,
					"name": unit_name
				})
	return reserves

## Determine if a unit is a good screening candidate (cheap, expendable)
static func _is_screening_candidate(unit: Dictionary) -> bool:
	var points = int(unit.get("meta", {}).get("points", 0))
	var unit_oc = int(unit.get("meta", {}).get("stats", {}).get("objective_control", 1))
	# Cheap units with low OC are ideal screeners — they're expendable
	# Also include zero-point units (chaff)
	if points <= SCREEN_CHEAP_UNIT_POINTS and unit_oc <= 2:
		return true
	# Units with no ranged weapons are also good screeners (they want to be forward)
	if points <= SCREEN_CHEAP_UNIT_POINTS * 1.5 and not _unit_has_ranged_weapons(unit):
		return true
	return false

## Calculate deep strike denial positions to protect key areas.
## Returns an array of {position: Vector2, priority: float, reason: String}
static func _calculate_denial_positions(
	snapshot: Dictionary, objectives: Array, obj_evaluations: Array,
	friendly_units: Dictionary, player: int, existing_screeners: Array
) -> Array:
	var denial_positions = []

	# Identify home objectives that need protection from deep strike
	for eval in obj_evaluations:
		if not eval.get("is_home", false):
			continue
		var obj_pos = eval.position
		var obj_state = eval.get("state", "")

		# Home objectives are high-priority denial targets
		var priority = 6.0
		if obj_state == "held_safe":
			priority = 8.0  # Protect what we already hold
		elif obj_state == "uncontrolled":
			priority = 5.0  # Still want to deny enemy access

		# Calculate denial position: offset from objective toward board center
		# to create a denial bubble that covers the objective
		var board_center = Vector2(BOARD_WIDTH_PX / 2.0, BOARD_HEIGHT_PX / 2.0)
		var toward_center = (board_center - obj_pos).normalized()
		# Place screener between the objective and the center, at ~9" offset
		# This creates a denial zone that covers the objective area
		var denial_pos = obj_pos + toward_center * DEEP_STRIKE_DENIAL_RANGE_PX * 0.75

		# Clamp to board
		denial_pos.x = clamp(denial_pos.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
		denial_pos.y = clamp(denial_pos.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)

		# Check if an existing screener already covers this area
		var already_covered = false
		for screener_pos in existing_screeners:
			if screener_pos.distance_to(denial_pos) < DEEP_STRIKE_DENIAL_RANGE_PX:
				already_covered = true
				break

		if not already_covered:
			denial_positions.append({
				"position": denial_pos,
				"priority": priority,
				"reason": "deny deep strike near home objective %s" % eval.id
			})

	# Also identify open backfield gaps — areas far from any friendly unit
	# that an enemy could deep strike into
	var deployment_zone = _get_deployment_zone_bounds(snapshot, player)
	if not deployment_zone.is_empty():
		# Sample points across the deployment zone to find uncovered gaps
		var zone_min_x = deployment_zone.get("min_x", 0.0)
		var zone_max_x = deployment_zone.get("max_x", BOARD_WIDTH_PX)
		var zone_min_y = deployment_zone.get("min_y", 0.0)
		var zone_max_y = deployment_zone.get("max_y", BOARD_HEIGHT_PX)
		var step = SCREEN_SPACING_PX  # Check every 18"

		var sample_x = zone_min_x + step * 0.5
		while sample_x < zone_max_x:
			var sample_y = zone_min_y + step * 0.5
			while sample_y < zone_max_y:
				var sample_pos = Vector2(sample_x, sample_y)

				# Check if any friendly unit is within 9" of this sample point
				var nearest_friendly_dist = INF
				for fid in friendly_units:
					var funit = friendly_units[fid]
					var fc = _get_unit_centroid(funit)
					if fc == Vector2.INF:
						continue
					var d = sample_pos.distance_to(fc)
					if d < nearest_friendly_dist:
						nearest_friendly_dist = d

				# Also check existing screener positions
				for screener_pos in existing_screeners:
					var d = sample_pos.distance_to(screener_pos)
					if d < nearest_friendly_dist:
						nearest_friendly_dist = d

				# If no friendly unit within denial range, this is a gap
				if nearest_friendly_dist > DEEP_STRIKE_DENIAL_RANGE_PX:
					denial_positions.append({
						"position": sample_pos,
						"priority": 3.0,  # Lower priority than objective denial
						"reason": "backfield gap (nearest friendly: %.0f\")" % (nearest_friendly_dist / PIXELS_PER_INCH)
					})

				sample_y += step
			sample_x += step

	# Sort by priority (highest first)
	denial_positions.sort_custom(func(a, b): return a.priority > b.priority)
	return denial_positions

static func _compute_screen_position(
	unit: Dictionary, unit_id: String, friendly_units: Dictionary,
	enemies: Dictionary, snapshot: Dictionary
) -> Vector2:
	# Find a good screening position between enemies and valuable friendly units
	var centroid = _get_unit_centroid(unit)
	if centroid == Vector2.INF:
		return Vector2.INF

	# Find the nearest enemy threat
	var nearest_enemy_pos = Vector2.INF
	var nearest_enemy_dist = INF
	for eid in enemies:
		var enemy = enemies[eid]
		var ecentroid = _get_unit_centroid(enemy)
		if ecentroid == Vector2.INF:
			continue
		var d = centroid.distance_to(ecentroid)
		if d < nearest_enemy_dist:
			nearest_enemy_dist = d
			nearest_enemy_pos = ecentroid

	if nearest_enemy_pos == Vector2.INF:
		return Vector2.INF

	# Find the nearest valuable friendly unit to protect
	var protect_pos = Vector2.INF
	var protect_dist = INF
	for fid in friendly_units:
		if fid == unit_id:
			continue
		var funit = friendly_units[fid]
		var fcentroid = _get_unit_centroid(funit)
		if fcentroid == Vector2.INF:
			continue
		# Prioritize protecting units near objectives or with high value
		var d = centroid.distance_to(fcentroid)
		if d < protect_dist:
			protect_dist = d
			protect_pos = fcentroid

	if protect_pos == Vector2.INF:
		return Vector2.INF

	# Screen position: halfway between the friendly unit and the enemy, leaning toward enemy
	var screen_pos = protect_pos + (nearest_enemy_pos - protect_pos) * 0.6
	return screen_pos

## T7-42: Calculate corridor blocking positions to impede enemy movement toward objectives.
## Identifies key corridors between enemy units and high-value objectives, then computes
## positions where expendable units should stand to physically block the approach path.
## Returns an array of {position: Vector2, priority: float, reason: String}
static func _calculate_corridor_blocking_positions(
	snapshot: Dictionary, objectives: Array, obj_evaluations: Array,
	enemies: Dictionary, friendly_units: Dictionary, player: int,
	existing_blockers: Array
) -> Array:
	var blocking_positions = []
	var threat_range_px = CORRIDOR_BLOCK_THREAT_RANGE_INCHES * PIXELS_PER_INCH

	for eval in obj_evaluations:
		# Only block corridors to objectives we hold or want to contest
		if eval.state == "enemy_strong":
			continue  # Don't waste blockers on objectives we can't realistically hold

		var obj_pos = eval.position
		var obj_id = eval.id

		# Base priority depends on how important this objective is to us
		var base_priority = 0.0
		match eval.state:
			"held_safe":
				base_priority = 5.0
			"held_threatened":
				base_priority = 6.0  # Highest — already under pressure
			"contested":
				base_priority = 4.0
			"uncontrolled":
				base_priority = 3.0
			"enemy_weak":
				base_priority = 2.0
		# Home objectives get extra blocking priority
		if eval.is_home:
			base_priority += 2.0

		# For each enemy that threatens this objective
		for enemy_id in enemies:
			var enemy = enemies[enemy_id]
			var enemy_centroid = _get_unit_centroid(enemy)
			if enemy_centroid == Vector2.INF:
				continue

			var dist_to_obj = enemy_centroid.distance_to(obj_pos)
			if dist_to_obj > threat_range_px:
				continue  # Enemy too far to be a realistic threat
			if dist_to_obj < ENGAGEMENT_RANGE_PX * 3:
				continue  # Enemy already at the objective — blocking won't help

			# Calculate blocking position along the corridor
			# Place the blocker between the enemy and the objective, biased toward the enemy
			var corridor_dir = (obj_pos - enemy_centroid).normalized()
			var block_pos = enemy_centroid + corridor_dir * dist_to_obj * CORRIDOR_BLOCK_POSITION_RATIO

			# Clamp to board
			block_pos.x = clamp(block_pos.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
			block_pos.y = clamp(block_pos.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)

			# Check if a friendly unit or existing blocker already covers this corridor
			var already_covered = false
			for blocker_pos in existing_blockers:
				if blocker_pos.distance_to(block_pos) < CORRIDOR_BLOCK_MIN_GAP_PX:
					already_covered = true
					break
			if not already_covered:
				for fid in friendly_units:
					var funit = friendly_units[fid]
					var fc = _get_unit_centroid(funit)
					if fc == Vector2.INF:
						continue
					if fc.distance_to(block_pos) < CORRIDOR_BLOCK_MIN_GAP_PX:
						already_covered = true
						break

			if already_covered:
				continue

			# Priority: closer enemy = more urgent, higher objective value = more important
			var proximity_bonus = (threat_range_px - dist_to_obj) / threat_range_px * 3.0
			var enemy_value = _estimate_enemy_threat_level(enemy)
			var priority = base_priority + proximity_bonus + enemy_value

			var enemy_name = enemy.get("meta", {}).get("name", enemy_id)
			blocking_positions.append({
				"position": block_pos,
				"priority": priority,
				"reason": "block %s approaching %s (%.0f\" away)" % [enemy_name, obj_id, dist_to_obj / PIXELS_PER_INCH]
			})

	# Sort by priority (highest first) and cap the number of positions
	blocking_positions.sort_custom(func(a, b): return a.priority > b.priority)
	if blocking_positions.size() > CORRIDOR_BLOCK_MAX_POSITIONS:
		blocking_positions.resize(CORRIDOR_BLOCK_MAX_POSITIONS)
	return blocking_positions

# --- Movement helpers ---

static func _nearest_objective_distance(pos: Vector2, objectives: Array) -> float:
	var best = INF
	for obj_pos in objectives:
		var d = pos.distance_to(obj_pos)
		if d < best:
			best = d
	return best

# _compute_movement_toward_objective: REMOVED - replaced by _compute_movement_toward_target
# _find_unblocked_move: REMOVED - replaced by _find_unblocked_move_enhanced

static func _path_blocked_by_terrain(
	from: Vector2, to: Vector2, unit_keywords: Array, terrain_features: Array
) -> bool:
	for terrain in terrain_features:
		# Check if the unit can move through this terrain type
		var can_move_through = terrain.get("can_move_through", {})
		var unit_can_pass = false
		for keyword in unit_keywords:
			if can_move_through.get(keyword, false):
				unit_can_pass = true
				break
		# FLY units can always pass over terrain
		if "FLY" in unit_keywords:
			unit_can_pass = true

		if unit_can_pass:
			continue

		# Check if the line intersects this terrain polygon
		var polygon = terrain.get("polygon", [])
		if polygon is PackedVector2Array:
			if _line_intersects_polygon(from, to, polygon):
				return true
		elif polygon is Array and polygon.size() >= 3:
			# Convert Array to points for checking
			var packed = PackedVector2Array()
			for p in polygon:
				if p is Vector2:
					packed.append(p)
				elif p is Dictionary:
					packed.append(Vector2(float(p.get("x", 0)), float(p.get("y", 0))))
			if _line_intersects_polygon(from, to, packed):
				return true

	return false

static func _line_intersects_polygon(from: Vector2, to: Vector2, polygon: PackedVector2Array) -> bool:
	if polygon.size() < 3:
		return false

	# Check if line segment intersects any edge of the polygon
	for i in range(polygon.size()):
		var edge_start = polygon[i]
		var edge_end = polygon[(i + 1) % polygon.size()]
		if Geometry2D.segment_intersects_segment(from, to, edge_start, edge_end):
			return true

	# Also check if starting point is inside the polygon (already in terrain)
	if Geometry2D.is_point_in_polygon(to, polygon):
		return true

	return false

static func _is_position_near_enemy(pos: Vector2, enemies: Dictionary, own_unit: Dictionary) -> bool:
	# Check if position is within engagement range (1") of any enemy model
	var own_models = own_unit.get("models", [])
	var own_base_mm = own_models[0].get("base_mm", 32) if own_models.size() > 0 else 32
	var own_radius_px = (own_base_mm / 2.0) * (PIXELS_PER_INCH / 25.4)

	for enemy_id in enemies:
		var enemy = enemies[enemy_id]
		for model in enemy.get("models", []):
			if not model.get("alive", true):
				continue
			var enemy_pos = _get_model_position(model)
			if enemy_pos == Vector2.INF:
				continue
			var dist = pos.distance_to(enemy_pos)
			# Use engagement range + base radii for proper edge-to-edge check
			var enemy_base_mm = model.get("base_mm", 32)
			var enemy_radius_px = (enemy_base_mm / 2.0) * (PIXELS_PER_INCH / 25.4)
			var min_dist = own_radius_px + enemy_radius_px + ENGAGEMENT_RANGE_PX
			if dist < min_dist:
				return true
	return false

# _try_shorter_move: REMOVED - functionality integrated into _try_move_with_collision_check

static func _try_move_with_collision_check(
	alive_models: Array, move_vector: Vector2, enemies: Dictionary,
	unit: Dictionary, deployed_models: Array, base_mm: int,
	base_type: String, base_dimensions: Dictionary,
	original_positions: Dictionary = {}, move_cap_px: float = 0.0
) -> Dictionary:
	# Try moving all models by move_vector, checking both enemy ER and model overlap
	var destinations = {}
	# Track models we've placed in this move for intra-unit collision
	var placed_models: Array = []

	for model in alive_models:
		var model_id = model.get("id", "")
		if model_id == "":
			continue
		var model_pos = _get_model_position(model)
		if model_pos == Vector2.INF:
			continue
		var dest = model_pos + move_vector

		# Clamp to board bounds with margin
		dest.x = clamp(dest.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
		dest.y = clamp(dest.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)

		# Check enemy engagement range
		if _is_position_near_enemy(dest, enemies, unit):
			return {}

		# Check overlap with deployed models and already-placed models in this move
		var all_obstacles = deployed_models + placed_models
		if _position_collides_with_deployed(dest, base_mm, all_obstacles, 4.0, base_type, base_dimensions):
			# Try small perpendicular offsets to avoid the collision
			var orig_pos = original_positions.get(model_id, model_pos)
			var resolved_dest = _resolve_movement_collision(
				dest, move_vector, base_mm, base_type, base_dimensions,
				all_obstacles, enemies, unit, orig_pos, move_cap_px
			)
			if resolved_dest == Vector2.INF:
				return {}  # Could not resolve collision
			dest = resolved_dest

		destinations[model_id] = [dest.x, dest.y]
		placed_models.append({
			"position": dest,
			"base_mm": base_mm,
			"base_type": base_type,
			"base_dimensions": base_dimensions
		})

	return destinations

static func _resolve_movement_collision(
	dest: Vector2, move_vector: Vector2, base_mm: int,
	base_type: String, base_dimensions: Dictionary,
	obstacles: Array, enemies: Dictionary, unit: Dictionary,
	original_pos: Vector2 = Vector2.INF, move_cap_px: float = 0.0
) -> Vector2:
	# Try perpendicular offsets to avoid collision while staying close to intended destination
	var perp = Vector2(-move_vector.y, move_vector.x).normalized()
	var base_radius = _model_bounding_radius_px(base_mm, base_type, base_dimensions)
	var offsets = [1.0, -1.0, 2.0, -2.0, 3.0, -3.0]

	for multiplier in offsets:
		var offset = perp * base_radius * multiplier
		var candidate = dest + offset

		# Check board bounds
		if candidate.x < BASE_MARGIN_PX or candidate.x > BOARD_WIDTH_PX - BASE_MARGIN_PX:
			continue
		if candidate.y < BASE_MARGIN_PX or candidate.y > BOARD_HEIGHT_PX - BASE_MARGIN_PX:
			continue

		# Check movement cap: offset must not push model beyond its movement distance
		if original_pos != Vector2.INF and move_cap_px > 0.0:
			var offset_dist = original_pos.distance_to(candidate)
			if offset_dist > move_cap_px:
				continue

		if not _position_collides_with_deployed(candidate, base_mm, obstacles, 4.0, base_type, base_dimensions):
			if not _is_position_near_enemy(candidate, enemies, unit):
				return candidate

	return Vector2.INF  # No valid offset found

static func _get_deployed_models_excluding_unit(snapshot: Dictionary, exclude_unit_id: String) -> Array:
	# Returns model positions for all on-board units except the specified one
	# Includes DEPLOYED, MOVED, SHOT, CHARGED statuses (any unit physically on the board)
	var deployed = []
	for uid in snapshot.get("units", {}):
		if uid == exclude_unit_id:
			continue
		var u = snapshot.units[uid]
		var status = u.get("status", 0)
		if status == GameStateData.UnitStatus.UNDEPLOYED or status == GameStateData.UnitStatus.IN_RESERVES:
			continue
		for model in u.get("models", []):
			if not model.get("alive", true):
				continue
			var pos_data = model.get("position", null)
			if pos_data == null:
				continue
			var pos: Vector2
			if pos_data is Vector2:
				pos = pos_data
			else:
				pos = Vector2(float(pos_data.get("x", 0)), float(pos_data.get("y", 0)))
			deployed.append({
				"position": pos,
				"base_mm": model.get("base_mm", 32),
				"base_type": model.get("base_type", "circular"),
				"base_dimensions": model.get("base_dimensions", {}),
				"rotation": model.get("rotation", 0.0)
			})
	return deployed

static func _get_deployed_models_split(snapshot: Dictionary, exclude_unit_id: String, unit_owner: int) -> Dictionary:
	"""Returns deployed models split by allegiance for pile-in/consolidation collision detection.
	Returns {"friendly": Array, "enemy": Array} where each entry has position, base_mm, etc."""
	var friendly = []
	var enemy = []
	for uid in snapshot.get("units", {}):
		if uid == exclude_unit_id:
			continue
		var u = snapshot.units[uid]
		var status = u.get("status", 0)
		if status == GameStateData.UnitStatus.UNDEPLOYED or status == GameStateData.UnitStatus.IN_RESERVES:
			continue
		var is_friendly = int(u.get("owner", 0)) == unit_owner
		for model in u.get("models", []):
			if not model.get("alive", true):
				continue
			var pos_data = model.get("position", null)
			if pos_data == null:
				continue
			var pos: Vector2
			if pos_data is Vector2:
				pos = pos_data
			else:
				pos = Vector2(float(pos_data.get("x", 0)), float(pos_data.get("y", 0)))
			var entry = {
				"position": pos,
				"base_mm": model.get("base_mm", 32),
				"base_type": model.get("base_type", "circular"),
				"base_dimensions": model.get("base_dimensions", {}),
				"rotation": model.get("rotation", 0.0)
			}
			if is_friendly:
				friendly.append(entry)
			else:
				enemy.append(entry)
	return {"friendly": friendly, "enemy": enemy}

# =============================================================================
# SHOOTING PHASE
# =============================================================================

static func _decide_shooting(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	var action_types = {}
	for a in available_actions:
		var t = a.get("type", "")
		if not action_types.has(t):
			action_types[t] = []
		action_types[t].append(a)

	# Step 0: Complete shooting for unit if needed (safety net)
	if action_types.has("COMPLETE_SHOOTING_FOR_UNIT"):
		var a = action_types["COMPLETE_SHOOTING_FOR_UNIT"][0]
		return {
			"type": "COMPLETE_SHOOTING_FOR_UNIT",
			"actor_unit_id": a.get("actor_unit_id", ""),
			"_ai_description": "Complete shooting for unit"
		}

	# Step 1: Handle saves if needed
	if action_types.has("APPLY_SAVES"):
		return {"type": "APPLY_SAVES", "payload": {"save_results_list": []}, "_ai_description": "Applying saves"}

	# Step 2: Continue weapon sequence if needed
	if action_types.has("CONTINUE_SEQUENCE"):
		return {"type": "CONTINUE_SEQUENCE", "_ai_description": "Continue weapon sequence"}

	# Step 3: Resolve shooting if ready
	if action_types.has("RESOLVE_SHOOTING"):
		return {"type": "RESOLVE_SHOOTING", "_ai_description": "Resolve shooting"}

	# Step 4: Confirm targets if pending
	if action_types.has("CONFIRM_TARGETS"):
		return {"type": "CONFIRM_TARGETS", "_ai_description": "Confirm targets"}

	# Step 4.5: Consider GRENADE stratagem before regular shooting
	# T7-40: Only Hard+ difficulty uses stratagems proactively
	# Evaluate once per shooting phase — if worthwhile, use it before regular shooting
	if action_types.has("SELECT_SHOOTER") and not _grenade_evaluated:
		_grenade_evaluated = true
		if AIDifficultyConfigData.use_stratagems(_current_difficulty):
			var grenade_eval = evaluate_grenade_usage(snapshot, player)
			if grenade_eval.get("should_use", false):
				print("AIDecisionMaker: Using GRENADE stratagem — %s" % grenade_eval.get("description", ""))
				return {
					"type": "USE_GRENADE_STRATAGEM",
					"grenade_unit_id": grenade_eval.grenade_unit_id,
					"target_unit_id": grenade_eval.target_unit_id,
					"player": player,
					"_ai_description": grenade_eval.description
				}

	# Step 5: Use the SHOOT action for a full shooting sequence
	# This is the cleanest path - select + assign + confirm in one action
	if action_types.has("SELECT_SHOOTER"):
		# Build focus fire plan if not already built for this shooting phase.
		# The plan coordinates weapon assignments across ALL shooting units to
		# concentrate fire on kill thresholds rather than spreading damage.
		if not _focus_fire_plan_built:
			var shooter_unit_ids = []
			for sa in action_types["SELECT_SHOOTER"]:
				var sid = sa.get("actor_unit_id", sa.get("unit_id", ""))
				if sid != "":
					shooter_unit_ids.append(sid)
			_focus_fire_plan = _build_focus_fire_plan(snapshot, shooter_unit_ids, player)
			_focus_fire_plan_built = true
			print("AIDecisionMaker: Built focus fire plan for %d units, %d target assignments" % [
				shooter_unit_ids.size(), _focus_fire_plan.size()])
			for ff_uid in _focus_fire_plan:
				var ff_unit = snapshot.get("units", {}).get(ff_uid, {})
				var ff_name = ff_unit.get("meta", {}).get("name", ff_uid)
				var ff_assignments = _focus_fire_plan[ff_uid]
				var ff_targets = {}
				for ff_a in ff_assignments:
					var ff_tid = ff_a.get("target_unit_id", "")
					if not ff_targets.has(ff_tid):
						ff_targets[ff_tid] = 0
					ff_targets[ff_tid] += 1
				for ff_tid in ff_targets:
					var ff_target = snapshot.get("units", {}).get(ff_tid, {})
					var ff_tname = ff_target.get("meta", {}).get("name", ff_tid)
					print("  Focus fire: %s -> %s (%d weapon(s))" % [ff_name, ff_tname, ff_targets[ff_tid]])

		# Pick the first available shooter that has a plan
		var selected_unit_id = ""
		for sa in action_types["SELECT_SHOOTER"]:
			var sid = sa.get("actor_unit_id", sa.get("unit_id", ""))
			if sid != "" and _focus_fire_plan.has(sid):
				selected_unit_id = sid
				break

		# If no unit has a plan, try first available shooter with fallback scoring
		if selected_unit_id == "":
			for sa in action_types["SELECT_SHOOTER"]:
				var sid = sa.get("actor_unit_id", sa.get("unit_id", ""))
				if sid != "":
					selected_unit_id = sid
					break

		if selected_unit_id == "":
			_focus_fire_plan_built = false
			_focus_fire_plan.clear()
			return {"type": "END_SHOOTING", "_ai_description": "End Shooting Phase"}

		var unit = snapshot.get("units", {}).get(selected_unit_id, {})
		var unit_name = unit.get("meta", {}).get("name", selected_unit_id)

		# Get weapons for this unit
		var weapons = unit.get("meta", {}).get("weapons", [])
		var ranged_weapons = []
		for w in weapons:
			if w.get("type", "").to_lower() == "ranged":
				ranged_weapons.append(w)

		if ranged_weapons.is_empty():
			# Remove from plan and skip
			_focus_fire_plan.erase(selected_unit_id)
			return {
				"type": "SKIP_UNIT",
				"actor_unit_id": selected_unit_id,
				"_ai_description": "Skipped %s — no ranged weapons" % unit_name
			}

		var enemies = _get_enemy_units(snapshot, player)
		if enemies.is_empty():
			_focus_fire_plan_built = false
			_focus_fire_plan.clear()
			return {"type": "END_SHOOTING", "_ai_description": "End Shooting Phase (no targets)"}

		# Use focus fire plan assignments if available for this unit
		var assignments = []
		if _focus_fire_plan.has(selected_unit_id):
			assignments = _focus_fire_plan[selected_unit_id]
			_focus_fire_plan.erase(selected_unit_id)
			# Filter out assignments targeting units that may have been destroyed by earlier shooters
			var valid_assignments = []
			for a in assignments:
				var tid = a.get("target_unit_id", "")
				if enemies.has(tid):
					valid_assignments.append(a)
				else:
					print("AIDecisionMaker: Dropping assignment for destroyed target %s" % tid)
			assignments = valid_assignments
			# If all plan targets were destroyed, fall back to greedy scoring
			if assignments.is_empty() and not enemies.is_empty():
				assignments = _build_unit_assignments_fallback(unit, ranged_weapons, enemies, snapshot)
				print("AIDecisionMaker: Plan targets destroyed, using fallback for %s (%d assignments)" % [unit_name, assignments.size()])
			else:
				print("AIDecisionMaker: Using focus fire plan for %s (%d assignments)" % [unit_name, assignments.size()])
		else:
			# Fallback: per-weapon greedy scoring (same as old behavior)
			assignments = _build_unit_assignments_fallback(unit, ranged_weapons, enemies, snapshot)
			print("AIDecisionMaker: Using fallback scoring for %s (%d assignments)" % [unit_name, assignments.size()])

		if assignments.is_empty():
			return {
				"type": "SKIP_UNIT",
				"actor_unit_id": selected_unit_id,
				"_ai_description": "Skipped %s — no valid targets in range" % unit_name
			}

		# Build target summary with expected damage reasoning (T7-37)
		var target_damage = {}  # tid -> total expected damage
		var target_hp = {}  # tid -> kill threshold (total HP)
		var target_name_map = {}  # tid -> display name
		for assignment in assignments:
			var tid = assignment.get("target_unit_id", "")
			var target = snapshot.get("units", {}).get(tid, {})
			var tname = target.get("meta", {}).get("name", tid)
			target_name_map[tid] = tname
			if not target_damage.has(tid):
				target_damage[tid] = 0.0
				target_hp[tid] = _calculate_kill_threshold(target)
			var wid = assignment.get("weapon_id", "")
			for w in ranged_weapons:
				if _generate_weapon_id(w.get("name", ""), w.get("type", "")) == wid:
					target_damage[tid] += _estimate_weapon_damage(w, target, snapshot, unit)
					break

		var desc_parts = []
		for tid in target_damage:
			var tname = target_name_map.get(tid, tid)
			var dmg = target_damage[tid]
			var hp = target_hp[tid]
			var kill_pct = (dmg / hp * 100.0) if hp > 0 else 0.0
			desc_parts.append("%s — expected %.1f dmg vs %.0f HP (%.0f%% kill)" % [tname, dmg, hp, min(kill_pct, 100.0)])

		var target_summary = "; ".join(desc_parts) if not desc_parts.is_empty() else "targets"
		return {
			"type": "SHOOT",
			"actor_unit_id": selected_unit_id,
			"payload": {
				"assignments": assignments
			},
			"_ai_description": "%s shoots at %s" % [unit_name, target_summary]
		}

	# No shooters left, end phase — reset plan cache
	_focus_fire_plan_built = false
	_focus_fire_plan.clear()
	return {"type": "END_SHOOTING", "_ai_description": "End Shooting Phase"}

# =============================================================================
# FOCUS FIRE PLAN BUILDER
# =============================================================================

static func _build_focus_fire_plan(snapshot: Dictionary, shooter_unit_ids: Array, player: int) -> Dictionary:
	"""
	T7-22: Build a coordinated shooting plan using two-level priority framework.
	Returns {unit_id: [{weapon_id, target_unit_id, model_ids}]} mapping.

	Two-level priority:
	  Macro: Rank enemies by _calculate_target_value (threat level, damage output,
	         objective presence, ability value, points cost).
	  Micro: Iterative marginal value allocation maximizes total expected value
	         across all weapon-target assignments, not just per-weapon damage.

	Algorithm:
	1. Calculate kill threshold (total remaining wounds) for each enemy
	2. Compute macro-level target values for all enemies
	3. Build damage matrix (weapon × target expected damage)
	4. Iteratively assign weapons to targets by highest marginal expected value,
	   considering kill thresholds, opportunity cost, and overkill penalties
	"""
	var enemies = _get_enemy_units(snapshot, player)
	if enemies.is_empty():
		return {}

	# --- Step 1: Build weapon inventory across all shooters ---
	# Each entry: {unit_id, weapon, weapon_id, unit}
	var all_weapons = []
	for unit_id in shooter_unit_ids:
		var unit = snapshot.get("units", {}).get(unit_id, {})
		if unit.is_empty():
			continue
		var weapons = unit.get("meta", {}).get("weapons", [])
		for w in weapons:
			if w.get("type", "").to_lower() != "ranged":
				continue
			var weapon_name = w.get("name", "")
			var weapon_id = _generate_weapon_id(weapon_name, w.get("type", ""))

			# ONE SHOT: Skip one-shot weapons that have been fully fired
			var _re1 = _rules_engine()
			if _re1 and _re1.is_one_shot_weapon(weapon_id, snapshot):
				var all_fired = true
				var models = unit.get("models", [])
				for model in models:
					if model.get("alive", true):
						var model_id = model.get("id", "")
						if not _re1.has_fired_one_shot(unit, model_id, weapon_id):
							all_fired = false
							break
				if all_fired:
					continue

			all_weapons.append({
				"unit_id": unit_id,
				"weapon": w,
				"weapon_id": weapon_id,
				"unit": unit
			})

	if all_weapons.is_empty():
		return {}

	# --- Step 2: Calculate kill thresholds and expected damage matrix ---
	# kill_threshold[enemy_id] = total remaining wounds across all alive models
	var kill_thresholds = {}
	# target_value[enemy_id] = priority score for killing this target
	var target_values = {}

	# T7-24: Calculate tempo modifier once for all targets
	var shooting_tempo = _calculate_tempo_modifier(snapshot, player)

	for enemy_id in enemies:
		var enemy = enemies[enemy_id]
		kill_thresholds[enemy_id] = _calculate_kill_threshold(enemy)
		var base_value = _calculate_target_value(enemy, snapshot, player)

		# T7-24: When behind on VP, boost target values for units on objectives
		# (need to clear objectives to score). When ahead, focus on efficient kills.
		if shooting_tempo > 1.0:
			var enemy_centroid = _get_unit_centroid(enemy)
			if enemy_centroid != Vector2.INF:
				var obj_positions = _get_objectives(snapshot)
				for obj_pos in obj_positions:
					if enemy_centroid.distance_to(obj_pos) <= OBJECTIVE_CONTROL_RANGE_PX:
						base_value *= shooting_tempo
						break

		# T7-23: Suppress target value for enemies planned for charge.
		# Don't waste shooting on targets we intend to charge into melee with —
		# the charge will handle them, and shooting could kill models that
		# would have been better engaged in combat.
		if _is_charge_target(enemy_id):
			var enemy_name = enemy.get("meta", {}).get("name", enemy_id)
			print("AIDecisionMaker: [PHASE-PLAN] Suppressing shooting priority for %s (planned charge target, %.2f -> %.2f)" % [
				enemy_name, base_value, base_value * PHASE_PLAN_DONT_SHOOT_CHARGE_TARGET])
			base_value *= PHASE_PLAN_DONT_SHOOT_CHARGE_TARGET

		target_values[enemy_id] = base_value

	# damage_matrix[weapon_index][enemy_id] = expected damage
	var damage_matrix = []
	for wi in range(all_weapons.size()):
		var weapon_entry = all_weapons[wi]
		var weapon = weapon_entry["weapon"]
		var shooter_unit = weapon_entry["unit"]
		var dmg_row = {}
		for enemy_id in enemies:
			var enemy = enemies[enemy_id]
			var dmg = _estimate_weapon_damage(weapon, enemy, snapshot, shooter_unit)
			dmg_row[enemy_id] = dmg
		damage_matrix.append(dmg_row)

	# --- Step 3: Marginal value weapon allocation (T7-22 enhanced) ---
	# Instead of greedy per-target allocation, use iterative marginal value
	# optimization that considers opportunity cost across all targets.
	# Each iteration picks the weapon-target pair with highest marginal value.

	# Track how much expected damage is already allocated to each target
	var allocated_damage = {}
	for enemy_id in enemies:
		allocated_damage[enemy_id] = 0.0

	# Track which weapon has been assigned: weapon_assignments[wi] = target_id or ""
	var weapon_target = []
	for wi in range(all_weapons.size()):
		weapon_target.append("")

	# T7-6: Calculate model-level kill thresholds (wounds to kill N models)
	var model_wounds_map = {}  # enemy_id -> wounds per model
	for enemy_id in enemies:
		model_wounds_map[enemy_id] = float(_get_target_wounds_per_model(enemies[enemy_id]))

	# T7-22: Build efficiency cache for all weapon-target pairs
	var efficiency_cache = {}  # "wi:enemy_id" -> float
	for wi in range(all_weapons.size()):
		for enemy_id in enemies:
			var cache_key = "%d:%s" % [wi, enemy_id]
			efficiency_cache[cache_key] = _calculate_efficiency_multiplier(all_weapons[wi]["weapon"], enemies[enemy_id])

	# T7-22: Iterative marginal value allocation.
	# Each iteration: for every unassigned weapon, compute marginal value for
	# every target, pick the highest, assign it, and update allocated damage.
	# This naturally handles opportunity cost — a weapon goes where it adds
	# the most value considering what's already been allocated.
	var unassigned_count = all_weapons.size()
	var max_iterations = all_weapons.size()  # Safety bound
	var iteration = 0

	while unassigned_count > 0 and iteration < max_iterations:
		iteration += 1
		var best_wi = -1
		var best_enemy_id = ""
		var best_marginal_value = 0.0

		for wi in range(all_weapons.size()):
			if weapon_target[wi] != "":
				continue  # Already assigned

			for enemy_id in enemies:
				var dmg = damage_matrix[wi].get(enemy_id, 0.0)
				if dmg <= 0.0:
					continue  # Can't hit this target

				var marginal_value = _calculate_marginal_value(
					dmg, enemy_id, target_values, kill_thresholds,
					allocated_damage, model_wounds_map,
					efficiency_cache.get("%d:%s" % [wi, enemy_id], 1.0),
					enemies
				)

				if marginal_value > best_marginal_value:
					best_marginal_value = marginal_value
					best_wi = wi
					best_enemy_id = enemy_id

		if best_wi < 0 or best_enemy_id == "":
			break  # No profitable assignments remaining

		# Assign this weapon to the best target
		weapon_target[best_wi] = best_enemy_id
		allocated_damage[best_enemy_id] += damage_matrix[best_wi].get(best_enemy_id, 0.0)
		unassigned_count -= 1

	# --- Step 4: Build per-unit assignment dictionaries ---
	var plan = {}
	for wi in range(all_weapons.size()):
		var target_id = weapon_target[wi]
		if target_id == "":
			continue
		var weapon_entry = all_weapons[wi]
		var uid = weapon_entry["unit_id"]
		if not plan.has(uid):
			plan[uid] = []
		plan[uid].append({
			"weapon_id": weapon_entry["weapon_id"],
			"target_unit_id": target_id,
			"model_ids": _get_alive_model_ids(weapon_entry["unit"])
		})

	# T7-22: Log macro-level target priority ranking
	var ranked_targets = enemies.keys()
	ranked_targets.sort_custom(func(a, b): return target_values.get(a, 0) > target_values.get(b, 0))
	print("AIDecisionMaker: T7-22 Macro target priority ranking:")
	for enemy_id in ranked_targets:
		var enemy = enemies[enemy_id]
		var ename = enemy.get("meta", {}).get("name", enemy_id)
		var tval = target_values.get(enemy_id, 0.0)
		var threshold = kill_thresholds.get(enemy_id, 0)
		var target_type_name = _target_type_name(_classify_target_type(enemy))
		var pts = int(enemy.get("meta", {}).get("points", 0))
		print("  #%d %s [%s, %dpts]: priority=%.2f, HP=%.0f" % [
			ranked_targets.find(enemy_id) + 1, ename, target_type_name, pts, tval, threshold])

	# Log focus fire summary with efficiency info
	for enemy_id in allocated_damage:
		var alloc = allocated_damage[enemy_id]
		if alloc > 0:
			var threshold = kill_thresholds.get(enemy_id, 0)
			var enemy = enemies[enemy_id]
			var ename = enemy.get("meta", {}).get("name", enemy_id)
			var kill_pct = (alloc / threshold * 100.0) if threshold > 0 else 0.0
			var target_type_name = _target_type_name(_classify_target_type(enemy))
			print("AIDecisionMaker: Focus fire -> %s [%s]: %.1f eff-adjusted dmg vs %.1f HP (%.0f%% kill, marginal alloc)" % [
				ename, target_type_name, alloc, threshold, kill_pct])

	# Log weapon role assignments for debugging
	for wi in range(all_weapons.size()):
		var target_id = weapon_target[wi]
		if target_id == "":
			continue
		var weapon_entry = all_weapons[wi]
		var w = weapon_entry["weapon"]
		var wname = w.get("name", "?")
		var role_name = _weapon_role_name(_classify_weapon_role(w))
		var target = enemies.get(target_id, {})
		var tname = target.get("meta", {}).get("name", target_id)
		var eff = _calculate_efficiency_multiplier(w, target)
		print("AIDecisionMaker:   %s [%s] -> %s (efficiency: %.2f)" % [wname, role_name, tname, eff])

	return plan

static func _calculate_kill_threshold(unit: Dictionary) -> float:
	"""Calculate total remaining wounds across all alive models in a unit."""
	var total = 0.0
	for model in unit.get("models", []):
		if model.get("alive", true):
			total += float(model.get("current_wounds", model.get("wounds", 1)))
	return total

# =============================================================================
# T7-24: TRADE AND TEMPO AWARENESS
# =============================================================================

static func _get_points_per_wound(unit: Dictionary) -> float:
	"""T7-24: Calculate points per wound for a unit. Higher = more expensive per wound.
	Used for trade efficiency calculations — trading a cheap unit for an expensive one is favorable."""
	var meta = unit.get("meta", {})
	var points = int(meta.get("points", 0))
	if points <= 0:
		return 0.0
	var stats = meta.get("stats", {})
	var wounds_per_model = int(stats.get("wounds", 1))
	var alive_models = _get_alive_models(unit).size()
	var total_wounds = wounds_per_model * max(alive_models, 1)
	if total_wounds <= 0:
		return 0.0
	return float(points) / float(total_wounds)

static func _get_trade_efficiency(attacker: Dictionary, target: Dictionary) -> float:
	"""T7-24: Calculate trade efficiency. Returns >1.0 for favorable trades, <1.0 for unfavorable.
	A favorable trade is when we spend fewer points-per-wound to remove more expensive-per-wound models.
	Example: 65pt Intercessors (6.5 ppw) shooting at 200pt Leman Russ (15.4 ppw) = favorable trade."""
	var attacker_ppw = _get_points_per_wound(attacker)
	var target_ppw = _get_points_per_wound(target)
	if attacker_ppw <= 0.0 or target_ppw <= 0.0:
		return 1.0  # No points data available, neutral trade
	# Ratio: target PPW / attacker PPW. >1.0 means target is more expensive per wound
	var ratio = target_ppw / attacker_ppw
	return clampf(ratio, TRADE_UNFAVORABLE_PENALTY, TRADE_FAVORABLE_BONUS)

static func _calculate_tempo_modifier(snapshot: Dictionary, player: int) -> float:
	"""T7-24: Calculate aggression modifier based on VP differential and game round.
	Returns >1.0 when behind (play more aggressively), <1.0 when ahead (play conservatively).
	Late-game desperation: being behind in rounds 4-5 sharply increases aggression.
	This reflects the real-game insight that trailing players must take risks to catch up,
	while leading players should protect their lead by making efficient trades."""
	var players = snapshot.get("players", {})
	var player_key = str(player)
	var opponent_key = "2" if player == 1 else "1"
	var my_vp = int(players.get(player_key, {}).get("vp", 0))
	var opp_vp = int(players.get(opponent_key, {}).get("vp", 0))
	var vp_diff = my_vp - opp_vp  # Positive = winning, negative = losing

	var battle_round = snapshot.get("meta", {}).get("battle_round", 1)

	# Base aggression: adjust based on VP differential
	var modifier = 1.0
	if vp_diff < 0:
		# Behind: increase aggression proportional to deficit
		modifier += minf(absf(vp_diff) * TEMPO_VP_DIFF_WEIGHT, TEMPO_BEHIND_AGGRESSION_BOOST - 1.0)
	elif vp_diff > 0:
		# Ahead: play more conservatively (smaller adjustment to avoid passivity)
		modifier -= minf(float(vp_diff) * TEMPO_VP_DIFF_WEIGHT * 0.5, 1.0 - TEMPO_AHEAD_CONSERVATION)

	# Late-game desperation: being behind in rounds 4-5 increases aggression sharply
	if battle_round >= TEMPO_DESPERATION_ROUND and vp_diff < 0:
		var rounds_left = TEMPO_MAX_ROUNDS - battle_round + 1
		var urgency = 1.0 + (absf(vp_diff) * TEMPO_VP_DIFF_WEIGHT * (3.0 / maxf(float(rounds_left), 1.0)))
		modifier = maxf(modifier, minf(urgency, TEMPO_DESPERATION_MULTIPLIER))

	print("AIDecisionMaker: [TEMPO] VP: %d vs %d (diff=%+d), round=%d, modifier=%.2f" % [
		my_vp, opp_vp, vp_diff, battle_round, modifier])
	return modifier

static func _get_round_strategy_modifiers(battle_round: int) -> Dictionary:
	"""T7-43: Get round-based strategy modifiers for late-game pivot.
	Rounds 1-2: Aggressive positioning — favor kills and forward movement.
	Round 3: Balanced — standard weights across all factors.
	Rounds 4-5: Objective/survival — prioritize objective control and survival over kills.
	Returns a dictionary with multipliers for different strategic priorities."""
	if battle_round <= 2:
		return {
			"aggression": STRATEGY_EARLY_AGGRESSION,
			"objective_priority": STRATEGY_EARLY_OBJECTIVE,
			"survival": STRATEGY_EARLY_SURVIVAL,
			"charge_threshold": STRATEGY_EARLY_CHARGE,
			"label": "AGGRESSIVE",
		}
	elif battle_round == 3:
		return {
			"aggression": 1.0,
			"objective_priority": 1.0,
			"survival": 1.0,
			"charge_threshold": 1.0,
			"label": "BALANCED",
		}
	else:  # Rounds 4-5
		return {
			"aggression": STRATEGY_LATE_AGGRESSION,
			"objective_priority": STRATEGY_LATE_OBJECTIVE,
			"survival": STRATEGY_LATE_SURVIVAL,
			"charge_threshold": STRATEGY_LATE_CHARGE,
			"label": "OBJECTIVE/SURVIVAL",
		}

static func _calculate_target_value(target_unit: Dictionary, snapshot: Dictionary, player: int) -> float:
	"""
	T7-22: Macro-level target priority assessment.
	Calculate a strategic priority value for killing this target.
	Higher value = more important to remove from the game.

	Factors:
	- Points cost (expensive units are higher value targets)
	- Expected damage output (ranged + melee with hit/wound probability)
	- Objective presence and Objective Control value
	- Ability value (leader buffs, offensive/defensive multipliers)
	- Keywords (CHARACTER, VEHICLE, MONSTER)
	- Health status (finish off wounded units)
	"""
	var value = 1.0

	var meta = target_unit.get("meta", {})
	var stats = meta.get("stats", {})
	var keywords = meta.get("keywords", [])
	var unit_id = target_unit.get("id", "")
	var all_units = snapshot.get("units", {})

	# --- Points cost: expensive units are strategically more valuable to remove ---
	var points = int(meta.get("points", 0))
	if points > 0:
		value += float(points) * MACRO_POINTS_WEIGHT

	# --- T7-24: Points-per-wound efficiency bonus ---
	# Units with high points-per-wound are more efficient to remove (each wound is expensive)
	var target_ppw = _get_points_per_wound(target_unit)
	if target_ppw > 0.0:
		# Normalize against a reference PPW (~25 pts/wound is average for infantry)
		var ppw_ratio = target_ppw / 25.0
		value += (ppw_ratio - 1.0) * TRADE_PPW_WEIGHT

	# --- Expected damage output: compute actual expected damage, not just raw attacks*damage ---
	# Use a "typical" target (T4, Sv3+) as baseline to estimate how threatening this unit is
	var weapons = meta.get("weapons", [])
	var alive_count = _get_alive_models(target_unit).size()
	var model_multiplier = maxf(float(alive_count), 1.0)

	# Ranged damage output (probability-weighted)
	var ranged_output = 0.0
	for w in weapons:
		if w.get("type", "").to_lower() != "ranged":
			continue
		var attacks_str = w.get("attacks", "1")
		var attacks = float(attacks_str) if attacks_str.is_valid_float() else _parse_average_damage(attacks_str)
		var bs_str = w.get("ballistic_skill", "4")
		var bs = int(bs_str) if bs_str.is_valid_int() else 4
		var s_str = w.get("strength", "4")
		var s = int(s_str) if s_str.is_valid_int() else 4
		var ap_str = w.get("ap", "0")
		var w_ap = 0
		if ap_str.begins_with("-"):
			var ap_num = ap_str.substr(1)
			w_ap = int(ap_num) if ap_num.is_valid_int() else 0
		else:
			w_ap = int(ap_str) if ap_str.is_valid_int() else 0
		var dmg = _parse_average_damage(w.get("damage", "1"))
		# Expected damage vs T4 Sv3+ baseline
		var p_hit = _hit_probability(bs)
		var p_wound = _wound_probability(s, 4)
		var p_unsaved = 1.0 - _save_probability(3, w_ap)
		ranged_output += attacks * p_hit * p_wound * p_unsaved * dmg
	# Scale by model count (each model fires)
	ranged_output *= model_multiplier
	value += ranged_output * MACRO_RANGED_OUTPUT_WEIGHT

	# Melee damage output (probability-weighted)
	var melee_output = 0.0
	for w in weapons:
		if w.get("type", "").to_lower() != "melee":
			continue
		var attacks_str = w.get("attacks", "1")
		var attacks = float(attacks_str) if attacks_str.is_valid_float() else _parse_average_damage(attacks_str)
		var ws_str = w.get("weapon_skill", w.get("ballistic_skill", "4"))
		var ws = int(ws_str) if ws_str.is_valid_int() else 4
		var s_str = w.get("strength", "4")
		var s = int(s_str) if s_str.is_valid_int() else 4
		var ap_str = w.get("ap", "0")
		var w_ap = 0
		if ap_str.begins_with("-"):
			var ap_num = ap_str.substr(1)
			w_ap = int(ap_num) if ap_num.is_valid_int() else 0
		else:
			w_ap = int(ap_str) if ap_str.is_valid_int() else 0
		var dmg = _parse_average_damage(w.get("damage", "1"))
		# Expected damage vs T4 Sv3+ baseline
		var p_hit = _hit_probability(ws)
		var p_wound = _wound_probability(s, 4)
		var p_unsaved = 1.0 - _save_probability(3, w_ap)
		melee_output += attacks * p_hit * p_wound * p_unsaved * dmg
	melee_output *= model_multiplier
	value += melee_output * MACRO_MELEE_OUTPUT_WEIGHT

	# --- Ability value: leaders providing buffs are high-priority targets ---
	# Offensive multiplier indicates how much this unit's abilities boost its damage
	var offensive_mult = AIAbilityAnalyzerData.get_offensive_multiplier_ranged(unit_id, target_unit, all_units)
	if offensive_mult > 1.0:
		value += (offensive_mult - 1.0) * MACRO_ABILITY_VALUE_WEIGHT

	# Defensive multiplier: units with strong defensive abilities (FNP, Stealth)
	# are harder to kill but also more dangerous if left alive
	var defensive_mult = AIAbilityAnalyzerData.get_defensive_multiplier(unit_id, target_unit, all_units)
	if defensive_mult > 1.0:
		# Slight discount — harder to kill means less efficient to shoot,
		# but still valuable to remove. Net effect is mild.
		value -= (defensive_mult - 1.0) * MACRO_SURVIVABILITY_DISCOUNT

	# --- Character bonus: leaders providing buffs are strategically critical ---
	if "CHARACTER" in keywords:
		# Check if this character is attached (providing buffs to a bodyguard)
		var attached_to = target_unit.get("attached_to", null)
		var attached_chars = target_unit.get("attachment_data", {}).get("attached_characters", [])
		if attached_to != null or not attached_chars.is_empty():
			value *= MACRO_LEADER_BUFF_BONUS  # Leader actively buffing = very high priority
		else:
			value *= 1.3  # Standalone character still valuable

	# --- Vehicle/Monster bonus (high-threat, high-wound targets) ---
	if "VEHICLE" in keywords or "MONSTER" in keywords:
		value *= 1.2

	# --- Below half health bonus (finish off wounded units — easy VP) ---
	var total_count = target_unit.get("models", []).size()
	if total_count > 0 and alive_count * 2 < total_count:
		value *= LOW_HEALTH_BONUS

	# --- Objective presence: units on/near objectives are strategically critical ---
	var unit_centroid = _get_unit_centroid(target_unit)
	var oc = int(stats.get("oc", 0))
	if unit_centroid != Vector2.INF:
		var objectives = _get_objectives(snapshot)
		var on_objective = false
		var near_objective = false
		for obj_pos in objectives:
			var dist = unit_centroid.distance_to(obj_pos)
			if dist < OBJECTIVE_CONTROL_RANGE_PX:
				on_objective = true
				break
			elif dist < OBJECTIVE_CONTROL_RANGE_PX * 2:
				near_objective = true

		if on_objective:
			value *= 1.4
			# OC value matters much more when actually on an objective
			if oc >= 1:
				value += float(oc) * MACRO_OC_ON_OBJECTIVE_WEIGHT
			# T7-43: In late game, further boost priority of shooting units on objectives
			var target_battle_round = snapshot.get("meta", {}).get("battle_round", snapshot.get("battle_round", 1))
			if target_battle_round >= 4:
				value *= STRATEGY_LATE_OBJ_TARGET_BONUS
		elif near_objective:
			value *= 1.15
			if oc >= 1:
				value += float(oc) * MACRO_OC_NEAR_OBJECTIVE_WEIGHT

	# T7-43: Apply round strategy aggression modifier to overall target value
	# Early game: boost kill-seeking (aggression > 1.0), Late game: reduce (aggression < 1.0)
	var tv_battle_round = snapshot.get("meta", {}).get("battle_round", snapshot.get("battle_round", 1))
	var tv_strategy = _get_round_strategy_modifiers(tv_battle_round)
	value *= tv_strategy.aggression

	return value

static func _calculate_marginal_value(
	weapon_damage: float, enemy_id: String,
	target_values: Dictionary, kill_thresholds: Dictionary,
	allocated_damage: Dictionary, model_wounds_map: Dictionary,
	efficiency: float, enemies: Dictionary
) -> float:
	"""
	T7-22: Micro-level marginal value calculation for weapon-target assignment.
	Returns the marginal expected value of assigning this weapon to this target,
	considering current allocations, kill thresholds, and opportunity cost.

	The value function has three regions:
	1. Below kill threshold: damage contributes to potential kills -> full value
	2. At kill threshold boundary: damage enables a kill -> bonus value
	3. Above kill threshold: overkill -> heavily discounted value
	"""
	var target_value = target_values.get(enemy_id, 1.0)
	var threshold = kill_thresholds.get(enemy_id, 1.0)
	var current_alloc = allocated_damage.get(enemy_id, 0.0)
	var wpm = model_wounds_map.get(enemy_id, 1.0)

	if threshold <= 0.0:
		return 0.0

	# Calculate how much of this weapon's damage is "useful" (contributes to kills)
	var useful_damage = 0.0
	var overkill_damage = 0.0
	var new_total = current_alloc + weapon_damage

	if current_alloc >= threshold * OVERKILL_TOLERANCE:
		# Already massively overkilling — all damage is waste
		overkill_damage = weapon_damage
	elif new_total <= threshold:
		# All damage contributes toward the kill threshold
		useful_damage = weapon_damage
	else:
		# Partially useful, partially overkill
		useful_damage = maxf(threshold - current_alloc, 0.0)
		overkill_damage = weapon_damage - useful_damage

	# Base marginal value: useful damage × target value
	var marginal = useful_damage * target_value

	# T7-22: Kill threshold crossing bonus.
	# If this weapon pushes us past a meaningful kill boundary, add a bonus.
	# Killing models is much more valuable than spreading chip damage.
	if wpm > 0.0:
		# Count model kills before and after this assignment
		var models_killed_before = floorf(current_alloc / wpm)
		var models_killed_after = floorf(minf(new_total, threshold) / wpm)
		var new_model_kills = models_killed_after - models_killed_before

		if new_model_kills >= 1.0:
			# Each new model killed adds fractional value
			marginal += new_model_kills * wpm * target_value * MICRO_MODEL_KILL_VALUE

		# Full wipe bonus: if we cross the total kill threshold
		if current_alloc < threshold and new_total >= threshold * 0.7:
			marginal *= MICRO_MARGINAL_KILL_BONUS

	# Overkill: heavily discount damage beyond the threshold
	marginal += overkill_damage * target_value * MICRO_OVERKILL_DECAY

	# Factor in weapon-target efficiency (anti-tank vs vehicle = bonus)
	marginal *= efficiency

	# Below-half-health bonus: wounded units are easier to finish
	var enemy = enemies.get(enemy_id, {})
	if not enemy.is_empty():
		var alive_count = _get_alive_models(enemy).size()
		var total_count = enemy.get("models", []).size()
		if total_count > 0 and alive_count * 2 < total_count:
			marginal *= LOW_HEALTH_BONUS

	return marginal

static func _estimate_weapon_damage(weapon: Dictionary, target_unit: Dictionary, snapshot: Dictionary, shooter_unit: Dictionary) -> float:
	"""
	Estimate expected damage of a weapon against a target.
	Similar to _score_shooting_target but returns raw expected damage without bonuses,
	and checks range. Includes weapon keyword modifiers (SHOOT-5).
	"""
	# Range check
	var weapon_range_inches = _get_weapon_range_inches(weapon)
	var dist_inches: float = -1.0  # -1 means unknown distance
	if weapon_range_inches > 0.0 and not shooter_unit.is_empty():
		dist_inches = _get_closest_model_distance_inches(shooter_unit, target_unit)
		if dist_inches > weapon_range_inches:
			return 0.0

	var attacks_str = weapon.get("attacks", "1")
	var attacks = float(attacks_str) if attacks_str.is_valid_float() else 1.0

	var bs_str = weapon.get("ballistic_skill", "4")
	var bs = int(bs_str) if bs_str.is_valid_int() else 4

	var strength_str = weapon.get("strength", "4")
	var strength = int(strength_str) if strength_str.is_valid_int() else 4

	var ap_str = weapon.get("ap", "0")
	var ap = 0
	if ap_str.begins_with("-"):
		var ap_num = ap_str.substr(1)
		ap = int(ap_num) if ap_num.is_valid_int() else 0
	else:
		ap = int(ap_str) if ap_str.is_valid_int() else 0

	var damage_str = weapon.get("damage", "1")
	var damage = float(damage_str) if damage_str.is_valid_float() else 1.0

	var toughness = target_unit.get("meta", {}).get("stats", {}).get("toughness", 4)
	var target_save = target_unit.get("meta", {}).get("stats", {}).get("save", 4)
	var target_invuln = _get_target_invulnerable_save(target_unit)

	# --- T7-31: Apply Benefit of Cover (+1 to armour save) ---
	var effective_save = target_save
	if _target_has_benefit_of_cover(target_unit, shooter_unit, snapshot) and not _weapon_ignores_cover(weapon, shooter_unit):
		effective_save = max(2, target_save - 1)

	var p_hit = _hit_probability(bs)
	var p_wound = _wound_probability(strength, toughness)
	var p_unsaved = 1.0 - _save_probability(effective_save, ap, target_invuln)

	# --- Apply weapon keyword modifiers (SHOOT-5) ---
	var kw_mods = _apply_weapon_keyword_modifiers(
		weapon, target_unit,
		attacks, p_hit, p_wound, p_unsaved, damage,
		strength, toughness, effective_save, ap, target_invuln,
		dist_inches, weapon_range_inches
	)
	attacks = kw_mods["attacks"]
	p_hit = kw_mods["p_hit"]
	p_wound = kw_mods["p_wound"]
	p_unsaved = kw_mods["p_unsaved"]
	damage = kw_mods["damage"]

	# --- T7-6: Wound overflow cap ---
	# In 40k, damage that exceeds a model's remaining wounds is lost. Cap damage
	# at wounds-per-model to avoid overestimating kill potential (e.g. D6+1 damage
	# weapon only deals 1 effective damage per unsaved wound vs 1W models).
	var wounds_per_model = _get_target_wounds_per_model(target_unit)
	if wounds_per_model > 0:
		damage = min(damage, float(wounds_per_model))

	# Scale by number of alive models that carry this weapon
	var model_count = _get_alive_models(shooter_unit).size()
	if model_count < 1:
		model_count = 1

	var raw_damage = attacks * p_hit * p_wound * p_unsaved * damage * model_count

	# --- AI-GAP-4: Factor in target FNP for more accurate damage estimates ---
	var target_fnp = AIAbilityAnalyzerData.get_unit_fnp(target_unit)
	if target_fnp > 0:
		var fnp_multiplier = AIAbilityAnalyzerData.get_fnp_damage_multiplier(target_fnp)
		raw_damage *= fnp_multiplier

	# --- AI-GAP-4: Factor in shooter's leader ability bonuses ---
	if not shooter_unit.is_empty():
		var shooter_id = shooter_unit.get("id", "")
		if shooter_id != "":
			var all_units_for_bonus = snapshot.get("units", {})
			var offensive_mult = AIAbilityAnalyzerData.get_offensive_multiplier_ranged(shooter_id, shooter_unit, all_units_for_bonus)
			if offensive_mult > 1.0:
				raw_damage *= offensive_mult

	# Apply weapon-target efficiency multiplier to guide weapon allocation
	var efficiency = _calculate_efficiency_multiplier(weapon, target_unit)
	return raw_damage * efficiency

static func _build_unit_assignments_fallback(unit: Dictionary, ranged_weapons: Array, enemies: Dictionary, snapshot: Dictionary) -> Array:
	"""
	Fallback per-weapon greedy scoring (original behavior).
	Used when a unit is not in the focus fire plan.
	"""
	var assignments = []
	for weapon in ranged_weapons:
		var weapon_name = weapon.get("name", "")
		var weapon_id = _generate_weapon_id(weapon_name, weapon.get("type", ""))

		# ONE SHOT: Skip one-shot weapons that have been fired
		var _re2 = _rules_engine()
		if _re2 and _re2.is_one_shot_weapon(weapon_id, snapshot):
			var all_fired = true
			var models = unit.get("models", [])
			for model in models:
				if model.get("alive", true):
					var model_id = model.get("id", "")
					if not _re2.has_fired_one_shot(unit, model_id, weapon_id):
						all_fired = false
						break
			if all_fired:
				continue

		# Score each enemy target (includes weapon range check)
		var best_target_id = ""
		var best_score = -1.0
		for enemy_id in enemies:
			var enemy = enemies[enemy_id]
			var score = _score_shooting_target(weapon, enemy, snapshot, unit)
			if score > best_score:
				best_score = score
				best_target_id = enemy_id

		if best_target_id != "" and best_score > 0:
			assignments.append({
				"weapon_id": weapon_id,
				"target_unit_id": best_target_id,
				"model_ids": _get_alive_model_ids(unit)
			})
			# T7-7: Log weapon-target efficiency for fallback assignments
			var role_name = _weapon_role_name(_classify_weapon_role(weapon))
			var target = enemies.get(best_target_id, {})
			var tname = target.get("meta", {}).get("name", best_target_id)
			var target_type_name = _target_type_name(_classify_target_type(target))
			var eff = _calculate_efficiency_multiplier(weapon, target)
			print("AIDecisionMaker: Fallback assign %s [%s] -> %s [%s] (efficiency: %.2f, score: %.2f)" % [
				weapon_name, role_name, tname, target_type_name, eff, best_score])

	return assignments

# =============================================================================
# CHARGE PHASE
# =============================================================================

static func _decide_charge(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	var action_types = {}
	for a in available_actions:
		var t = a.get("type", "")
		if not action_types.has(t):
			action_types[t] = []
		action_types[t].append(a)

	# --- Step 0: Handle reaction decisions first ---

	# Command Re-roll: Evaluate whether to reroll failed charge rolls
	# Note: ChargePhase puts USE/DECLINE in available actions. However, we lack the
	# roll context (rolled distance, required distance) here. The AIPlayer signal
	# handler (_on_command_reroll_opportunity) handles this with full context.
	# As a fallback if the signal didn't fire, decline here.
	if action_types.has("USE_COMMAND_REROLL") or action_types.has("DECLINE_COMMAND_REROLL"):
		# Default fallback: decline (signal handler should have already acted)
		var unit_id = ""
		if action_types.has("USE_COMMAND_REROLL"):
			unit_id = action_types["USE_COMMAND_REROLL"][0].get("actor_unit_id", "")
		elif action_types.has("DECLINE_COMMAND_REROLL"):
			unit_id = action_types["DECLINE_COMMAND_REROLL"][0].get("actor_unit_id", "")
		return {
			"type": "DECLINE_COMMAND_REROLL",
			"actor_unit_id": unit_id,
			"_ai_description": "Decline Command Re-roll (charge fallback)"
		}

	# Fire Overwatch: Evaluate whether to fire overwatch during opponent's charge
	if action_types.has("USE_FIRE_OVERWATCH") or action_types.has("DECLINE_FIRE_OVERWATCH"):
		var ow_actions = action_types.get("USE_FIRE_OVERWATCH", [])
		if not ow_actions.is_empty():
			# Build eligible units list from available actions
			var eligible_units = []
			var enemy_unit_id = ""
			var ow_player = player
			for ow_a in ow_actions:
				eligible_units.append({
					"unit_id": ow_a.get("actor_unit_id", ""),
					"unit_name": ow_a.get("description", "")
				})
				if enemy_unit_id == "":
					enemy_unit_id = ow_a.get("enemy_unit_id", "")
				if ow_a.has("player"):
					ow_player = ow_a.player

			var ow_decision = evaluate_fire_overwatch(ow_player, eligible_units, enemy_unit_id, snapshot)
			if ow_decision.get("type", "") == "USE_FIRE_OVERWATCH":
				ow_decision["player"] = ow_player
				return ow_decision

		# Decline overwatch
		var decline_player = player
		if action_types.has("DECLINE_FIRE_OVERWATCH"):
			decline_player = action_types["DECLINE_FIRE_OVERWATCH"][0].get("player", player)
		return {
			"type": "DECLINE_FIRE_OVERWATCH",
			"player": decline_player,
			"_ai_description": "Decline Fire Overwatch"
		}

	# Heroic Intervention: evaluate whether to counter-charge
	if action_types.has("USE_HEROIC_INTERVENTION") or action_types.has("DECLINE_HEROIC_INTERVENTION"):
		var hi_player = player
		var charging_unit_id = ""
		if action_types.has("USE_HEROIC_INTERVENTION"):
			hi_player = action_types["USE_HEROIC_INTERVENTION"][0].get("player", player)
			charging_unit_id = action_types["USE_HEROIC_INTERVENTION"][0].get("charging_unit_id", "")
		elif action_types.has("DECLINE_HEROIC_INTERVENTION"):
			hi_player = action_types["DECLINE_HEROIC_INTERVENTION"][0].get("player", player)

		var hi_decision = evaluate_heroic_intervention(hi_player, charging_unit_id, snapshot)
		if hi_decision.get("type", "") == "USE_HEROIC_INTERVENTION":
			hi_decision["player"] = hi_player
			return hi_decision
		return {
			"type": "DECLINE_HEROIC_INTERVENTION",
			"player": hi_player,
			"_ai_description": "AI declines Heroic Intervention"
		}

	# Tank Shock: evaluate whether to use it after a successful charge
	if action_types.has("USE_TANK_SHOCK") or action_types.has("DECLINE_TANK_SHOCK"):
		var ts_vehicle_id = ""
		if action_types.has("USE_TANK_SHOCK"):
			ts_vehicle_id = action_types["USE_TANK_SHOCK"][0].get("actor_unit_id", "")
		elif action_types.has("DECLINE_TANK_SHOCK"):
			ts_vehicle_id = action_types["DECLINE_TANK_SHOCK"][0].get("actor_unit_id", "")

		var ts_decision = evaluate_tank_shock(player, ts_vehicle_id, snapshot)
		return ts_decision

	# --- Step 1: Complete any pending charge ---
	if action_types.has("COMPLETE_UNIT_CHARGE"):
		var a = action_types["COMPLETE_UNIT_CHARGE"][0]
		var uid = a.get("actor_unit_id", "")
		var unit = snapshot.get("units", {}).get(uid, {})
		var unit_name = unit.get("meta", {}).get("name", uid)
		return {
			"type": "COMPLETE_UNIT_CHARGE",
			"actor_unit_id": uid,
			"_ai_description": "Complete charge for %s" % unit_name
		}

	# --- Step 2: Apply charge movement if a roll was successful ---
	if action_types.has("APPLY_CHARGE_MOVE"):
		var a = action_types["APPLY_CHARGE_MOVE"][0]
		var uid = a.get("actor_unit_id", "")
		var rolled_distance = a.get("rolled_distance", 0)
		var target_ids = a.get("target_ids", [])
		return _compute_charge_move(snapshot, uid, rolled_distance, target_ids, player)

	# --- Step 3: If charge roll is needed, roll ---
	if action_types.has("CHARGE_ROLL"):
		var a = action_types["CHARGE_ROLL"][0]
		var uid = a.get("actor_unit_id", "")
		var unit = snapshot.get("units", {}).get(uid, {})
		var unit_name = unit.get("meta", {}).get("name", uid)
		return {
			"type": "CHARGE_ROLL",
			"actor_unit_id": uid,
			"_ai_description": "Charge roll for %s" % unit_name
		}

	# --- Step 4: Evaluate and declare charges ---
	if action_types.has("DECLARE_CHARGE"):
		var best_charge = _evaluate_best_charge(snapshot, available_actions, player)
		if not best_charge.is_empty():
			return best_charge

	# No good charge found (or no targets) — skip remaining chargeable units one at a time
	if action_types.has("SKIP_CHARGE"):
		var a = action_types["SKIP_CHARGE"][0]
		var uid = a.get("actor_unit_id", "")
		var unit = snapshot.get("units", {}).get(uid, {})
		var unit_name = unit.get("meta", {}).get("name", uid)
		return {
			"type": "SKIP_CHARGE",
			"actor_unit_id": uid,
			"_ai_description": "Skipped charge for %s (no good target)" % unit_name
		}

	# --- Step 5: End charge phase ---
	return {"type": "END_CHARGE", "_ai_description": "End Charge Phase"}

# =============================================================================
# CHARGE EVALUATION
# =============================================================================

static func _evaluate_best_charge(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	"""Evaluate all possible charge declarations and return the best one, or {} if none worth taking."""
	var enemies = _get_enemy_units(snapshot, player)

	# Collect unique charger unit IDs from DECLARE_CHARGE actions
	var charger_targets = {}  # unit_id -> [{target_id, distance_inches, action}]
	for a in available_actions:
		if a.get("type") != "DECLARE_CHARGE":
			continue
		var uid = a.get("actor_unit_id", "")
		var target_ids = a.get("payload", {}).get("target_unit_ids", [])
		if uid == "" or target_ids.is_empty():
			continue

		if not charger_targets.has(uid):
			charger_targets[uid] = []

		var target_id = target_ids[0]
		var unit = snapshot.get("units", {}).get(uid, {})
		var target_unit = snapshot.get("units", {}).get(target_id, {})
		if unit.is_empty() or target_unit.is_empty():
			continue

		# Calculate closest model distance to target
		var min_dist = _get_closest_model_distance_inches(unit, target_unit)

		charger_targets[uid].append({
			"target_id": target_id,
			"distance_inches": min_dist,
			"action": a,
		})

	if charger_targets.is_empty():
		return {}

	# Score each (charger, target) pair
	var best_score = -INF
	var best_action = {}
	var best_description = ""

	for uid in charger_targets:
		var unit = snapshot.get("units", {}).get(uid, {})
		var unit_name = unit.get("meta", {}).get("name", uid)
		var unit_keywords = unit.get("meta", {}).get("keywords", [])
		var has_melee = _unit_has_melee_weapons(unit)

		# Units without melee weapons should generally not charge (except for objective play)
		var melee_bonus = 1.0 if has_melee else 0.3

		# --- AI-GAP-4: Check if charger has melee ability bonuses ---
		var all_units_charge = snapshot.get("units", {})
		var charger_melee_mult = AIAbilityAnalyzerData.get_offensive_multiplier_melee(uid, unit, all_units_charge)
		if charger_melee_mult > 1.0:
			melee_bonus *= charger_melee_mult
			print("AIDecisionMaker: %s has melee leader bonuses (mult=%.2f)" % [unit_name, charger_melee_mult])

		for target_info in charger_targets[uid]:
			var target_id = target_info.target_id
			var dist = target_info.distance_inches
			var target_unit = enemies.get(target_id, {})
			if target_unit.is_empty():
				continue
			var target_name = target_unit.get("meta", {}).get("name", target_id)

			# Calculate charge probability (2D6 must meet or exceed distance - ER)
			var charge_distance_needed = max(0.0, dist - 1.0)  # minus 1" engagement range
			var charge_prob = _charge_success_probability(charge_distance_needed)

			# Skip charges with very low probability
			if charge_prob < 0.08:  # Less than ~8% chance (need 11+ on 2d6)
				print("AIDecisionMaker: Skipping charge %s -> %s (prob=%.1f%%, need=%.1f\")" % [
					unit_name, target_name, charge_prob * 100.0, charge_distance_needed])
				continue

			# Score the charge target
			var target_score = _score_charge_target(unit, target_unit, snapshot, player)

			# T7-37: Compute expected melee damage for description
			var melee_dmg = _estimate_melee_damage(unit, target_unit)
			var target_hp = _calculate_kill_threshold(target_unit)

			# Apply charge probability as a multiplier
			var score = target_score * charge_prob * melee_bonus

			# Bonus for short charges (high reliability)
			if charge_distance_needed <= 6.0:
				score *= 1.2
			if charge_distance_needed <= 3.0:
				score *= 1.3

			# Bonus for charging onto objectives
			# T7-43: In late game, extra bonus for charging onto objectives (objective control > kills)
			var target_centroid = _get_unit_centroid(target_unit)
			var objectives = _get_objectives(snapshot)
			var charge_battle_round = snapshot.get("meta", {}).get("battle_round", snapshot.get("battle_round", 1))
			for obj_pos in objectives:
				if target_centroid != Vector2.INF and target_centroid.distance_to(obj_pos) <= OBJECTIVE_CONTROL_RANGE_PX:
					score *= 1.5  # Target is on an objective
					if charge_battle_round >= 4:
						score *= STRATEGY_LATE_CHARGE_ON_OBJ_BONUS
					break

			# T7-40: Apply difficulty noise to charge scoring
			score = _apply_difficulty_noise(score)
			print("AIDecisionMaker: Charge eval %s -> %s: dist=%.1f\", prob=%.0f%%, target_score=%.1f, final=%.1f" % [
				unit_name, target_name, dist, charge_prob * 100.0, target_score, score])

			if score > best_score:
				best_score = score
				best_action = target_info.action
				var kill_pct = (melee_dmg / target_hp * 100.0) if target_hp > 0 else 0.0
				best_description = "%s declares charge against %s (%.0f%% chance, %.1f\" away, expected %.1f melee dmg vs %.0f HP)" % [
					unit_name, target_name, charge_prob * 100.0, dist, melee_dmg, target_hp]

	# T7-24: Lower charge threshold when behind on VP (desperation charges)
	var charge_tempo = _calculate_tempo_modifier(snapshot, player)
	var charge_threshold = 1.0
	if charge_tempo > 1.0:
		# When behind: reduce threshold to accept more marginal charges
		charge_threshold = maxf(1.0 - (charge_tempo - 1.0) * TEMPO_CHARGE_THRESHOLD_REDUCTION, 0.3)
		print("AIDecisionMaker: [TEMPO] Charge threshold lowered to %.2f (tempo=%.2f)" % [charge_threshold, charge_tempo])

	# T7-40: Apply difficulty modifier to charge threshold
	charge_threshold *= _get_difficulty_charge_threshold_modifier()

	# T7-43: Apply round strategy modifier to charge threshold
	# Early game: lower threshold (more willing), Late game: higher (less willing unless on objective)
	var ct_battle_round = snapshot.get("meta", {}).get("battle_round", snapshot.get("battle_round", 1))
	var ct_strategy = _get_round_strategy_modifiers(ct_battle_round)
	charge_threshold *= ct_strategy.charge_threshold
	if ct_strategy.charge_threshold != 1.0:
		print("AIDecisionMaker: [STRATEGY] Round %d charge threshold adjusted by %.2f (strategy=%s)" % [
			ct_battle_round, ct_strategy.charge_threshold, ct_strategy.label])

	# Minimum threshold to declare a charge
	if best_score < charge_threshold:
		print("AIDecisionMaker: No charge worth declaring (best score: %.1f, threshold: %.1f)" % [best_score, charge_threshold])
		return {}

	print("AIDecisionMaker: Best charge: %s (score=%.1f)" % [best_description, best_score])
	var result = best_action.duplicate()
	result["_ai_description"] = best_description
	return result

static func _charge_success_probability(distance_needed: float) -> float:
	"""Calculate the probability that 2D6 >= distance_needed.
	Returns value between 0.0 and 1.0."""
	# 2D6 ranges from 2 to 12
	# We need the roll to be >= ceil(distance_needed)
	var needed = ceili(distance_needed)

	if needed <= 2:
		return 1.0  # Always succeeds (2D6 minimum is 2)
	if needed > 12:
		return 0.0  # Impossible

	# Count outcomes where sum >= needed out of 36 total outcomes
	var success_count = 0
	for d1 in range(1, 7):
		for d2 in range(1, 7):
			if d1 + d2 >= needed:
				success_count += 1

	return float(success_count) / 36.0

static func _score_charge_target(charger: Dictionary, target: Dictionary, snapshot: Dictionary, player: int) -> float:
	"""Score a potential charge target based on expected melee damage, target value, and tactical factors."""
	var score = 0.0

	# --- Expected melee damage ---
	var melee_damage = _estimate_melee_damage(charger, target)
	score += melee_damage * 2.0  # Weight melee damage highly

	# --- Target value factors ---
	var target_keywords = target.get("meta", {}).get("keywords", [])
	var target_wounds = int(target.get("meta", {}).get("stats", {}).get("wounds", 1))
	var alive_models = _get_alive_models(target).size()
	var total_models = target.get("models", []).size()

	# Bonus for targets below half strength (easier to finish off)
	if total_models > 0 and alive_models * 2 < total_models:
		score += 3.0

	# Bonus for CHARACTER targets
	if "CHARACTER" in target_keywords:
		score += 2.0

	# Penalty for very tough targets we can't damage effectively
	if melee_damage < 1.0:
		score -= 3.0

	# Bonus for engaging dangerous ranged units (stops them from shooting)
	var target_has_ranged = _unit_has_ranged_weapons(target)
	if target_has_ranged:
		var max_range = _get_max_weapon_range(target)
		if max_range >= 24.0:
			score += 2.0  # Good to tie up long-range shooters

	# T7-23: Enhanced bonus for locking dangerous shooters in combat
	# Units identified by the phase plan as dangerous shooters get extra charge priority
	var target_id_for_lock = target.get("id", "")
	if target_id_for_lock != "" and _phase_plan_built:
		var lock_targets = _phase_plan.get("lock_targets", [])
		if target_id_for_lock in lock_targets:
			var ranged_strength = _estimate_unit_ranged_strength(target)
			var lock_bonus = PHASE_PLAN_LOCK_SHOOTER_BONUS
			# Scale bonus by how dangerous the shooter is
			if ranged_strength >= PHASE_PLAN_RANGED_STRENGTH_DANGEROUS * 2.0:
				lock_bonus *= 1.5  # Very dangerous — high priority to lock
			score += lock_bonus
			print("AIDecisionMaker: [PHASE-PLAN] Charge bonus for locking shooter %s (+%.1f, ranged output: %.1f)" % [
				target.get("meta", {}).get("name", target_id_for_lock), lock_bonus, ranged_strength])

	# Bonus for targeting units with low toughness (likely kill)
	var target_toughness = int(target.get("meta", {}).get("stats", {}).get("toughness", 4))
	if target_toughness <= 3:
		score += 1.0

	# --- AI-GAP-4: Factor in charger's melee leader bonuses ---
	var charger_id = charger.get("id", "")
	if charger_id != "":
		var all_units = snapshot.get("units", {})
		var melee_mult = AIAbilityAnalyzerData.get_offensive_multiplier_melee(charger_id, charger, all_units)
		if melee_mult > 1.0:
			score *= melee_mult

	# --- AI-GAP-4: Factor in target's defensive abilities ---
	var target_id_for_def = target.get("id", "")
	if target_id_for_def != "":
		var all_units_def = snapshot.get("units", {})
		var def_mult = AIAbilityAnalyzerData.get_defensive_multiplier(target_id_for_def, target, all_units_def)
		if def_mult > 1.0:
			# Higher defensive multiplier = harder to kill = lower score
			score /= def_mult

	# --- T7-24: Trade efficiency — prefer charging targets where the trade is favorable ---
	var charge_trade_eff = _get_trade_efficiency(charger, target)
	if charge_trade_eff != 1.0:
		score *= charge_trade_eff
		print("AIDecisionMaker: [TRADE] Charge trade efficiency: %.2f (charger ppw=%.1f, target ppw=%.1f)" % [
			charge_trade_eff, _get_points_per_wound(charger), _get_points_per_wound(target)])

	# T7-43: Apply round strategy aggression modifier to charge target scoring
	# Early game: boost charge damage value (aggression > 1.0), Late game: reduce (aggression < 1.0)
	var sct_round = snapshot.get("meta", {}).get("battle_round", snapshot.get("battle_round", 1))
	var sct_strategy = _get_round_strategy_modifiers(sct_round)
	score *= sct_strategy.aggression

	return max(0.0, score)

static func _estimate_melee_damage(attacker: Dictionary, defender: Dictionary) -> float:
	"""Estimate expected damage from a melee attack using the attacker's best melee weapon."""
	var weapons = attacker.get("meta", {}).get("weapons", [])
	var best_damage = 0.0
	var alive_attackers = _get_alive_models(attacker).size()

	var target_toughness = int(defender.get("meta", {}).get("stats", {}).get("toughness", 4))
	var target_save = int(defender.get("meta", {}).get("stats", {}).get("save", 4))
	var target_invuln = _get_target_invulnerable_save(defender)

	for w in weapons:
		if w.get("type", "").to_lower() != "melee":
			continue

		var attacks_str = w.get("attacks", "1")
		var attacks = float(attacks_str) if attacks_str.is_valid_float() else 1.0

		var ws_str = w.get("weapon_skill", w.get("ballistic_skill", "4"))
		var ws = int(ws_str) if ws_str.is_valid_int() else 4

		var strength_str = w.get("strength", "4")
		var strength = int(strength_str) if strength_str.is_valid_int() else 4

		var ap_str = w.get("ap", "0")
		var ap = 0
		if ap_str.begins_with("-"):
			var ap_num = ap_str.substr(1)
			ap = int(ap_num) if ap_num.is_valid_int() else 0
		else:
			ap = int(ap_str) if ap_str.is_valid_int() else 0

		var damage_str = w.get("damage", "1")
		var damage = float(damage_str) if damage_str.is_valid_float() else 1.0

		var p_hit = _hit_probability(ws)
		var p_wound = _wound_probability(strength, target_toughness)
		var p_unsaved = 1.0 - _save_probability(target_save, ap, target_invuln)

		# Total expected damage for entire unit with this weapon
		var weapon_damage = attacks * alive_attackers * p_hit * p_wound * p_unsaved * damage
		best_damage = max(best_damage, weapon_damage)

	# Fallback: close combat weapon (S=user, AP0, D1, 1 attack)
	if best_damage == 0.0 and alive_attackers > 0:
		var charger_strength = int(attacker.get("meta", {}).get("stats", {}).get("toughness", 4))
		var p_hit = _hit_probability(4)  # WS4+ default
		var p_wound = _wound_probability(charger_strength, target_toughness)
		var p_unsaved = 1.0 - _save_probability(target_save, 0, target_invuln)
		best_damage = alive_attackers * p_hit * p_wound * p_unsaved * 1.0

	# --- AI-GAP-4: Factor in target FNP for more accurate melee damage estimates ---
	var target_fnp = AIAbilityAnalyzerData.get_unit_fnp(defender)
	if target_fnp > 0:
		var fnp_multiplier = AIAbilityAnalyzerData.get_fnp_damage_multiplier(target_fnp)
		best_damage *= fnp_multiplier

	return best_damage

static func _unit_has_melee_weapons(unit: Dictionary) -> bool:
	"""Check if a unit has any melee weapons (besides default close combat weapon)."""
	var weapons = unit.get("meta", {}).get("weapons", [])
	for w in weapons:
		if w.get("type", "").to_lower() == "melee":
			return true
	return false

static func _get_closest_model_distance_inches(unit_a: Dictionary, unit_b: Dictionary) -> float:
	"""Get the minimum edge-to-edge distance in inches between any two models of two units.
	Uses pixel-based position calculation since Measurement autoload may not be available statically."""
	var min_dist_px = INF
	for model_a in unit_a.get("models", []):
		if not model_a.get("alive", true):
			continue
		var pos_a = _get_model_position(model_a)
		if pos_a == Vector2.INF:
			continue
		var base_a_mm = model_a.get("base_mm", 32)
		var base_a_radius_px = _model_bounding_radius_px(base_a_mm, model_a.get("base_type", "circular"), model_a.get("base_dimensions", {}))

		for model_b in unit_b.get("models", []):
			if not model_b.get("alive", true):
				continue
			var pos_b = _get_model_position(model_b)
			if pos_b == Vector2.INF:
				continue
			var base_b_mm = model_b.get("base_mm", 32)
			var base_b_radius_px = _model_bounding_radius_px(base_b_mm, model_b.get("base_type", "circular"), model_b.get("base_dimensions", {}))

			# Edge-to-edge distance in pixels
			var center_dist = pos_a.distance_to(pos_b)
			var edge_dist_px = center_dist - base_a_radius_px - base_b_radius_px
			min_dist_px = min(min_dist_px, edge_dist_px)

	if min_dist_px == INF:
		return INF
	return max(0.0, min_dist_px) / PIXELS_PER_INCH

# =============================================================================
# CHARGE MOVEMENT COMPUTATION
# =============================================================================

static func _compute_charge_move(snapshot: Dictionary, unit_id: String, rolled_distance: int, target_ids: Array, player: int) -> Dictionary:
	"""Compute model positions for a charge move. Each model must:
	1. Move at most rolled_distance inches
	2. End closer to at least one charge target than it started
	3. At least one model must end within engagement range (1") of each declared target
	4. No model may end within engagement range of a non-target enemy
	5. Unit coherency must be maintained
	6. No model overlaps
	Returns an APPLY_CHARGE_MOVE action dict with per_model_paths, or a SKIP_CHARGE fallback."""

	var unit = snapshot.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return {"type": "SKIP_CHARGE", "actor_unit_id": unit_id, "_ai_description": "Skip charge (unit not found)"}

	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var alive_models = _get_alive_models_with_positions(unit)
	if alive_models.is_empty():
		return {"type": "SKIP_CHARGE", "actor_unit_id": unit_id, "_ai_description": "Skip charge for %s (no alive models)" % unit_name}

	# Gather target model positions (closest model per target)
	var target_positions = []  # Array of Vector2 (closest target model to charger centroid)
	var charger_centroid = _get_unit_centroid(unit)
	for target_id in target_ids:
		var target_unit = snapshot.get("units", {}).get(target_id, {})
		if target_unit.is_empty():
			continue
		var closest_pos = Vector2.INF
		var closest_dist = INF
		for tm in target_unit.get("models", []):
			if not tm.get("alive", true):
				continue
			var tp = _get_model_position(tm)
			if tp == Vector2.INF:
				continue
			var d = charger_centroid.distance_to(tp)
			if d < closest_dist:
				closest_dist = d
				closest_pos = tp
		if closest_pos != Vector2.INF:
			target_positions.append(closest_pos)

	if target_positions.is_empty():
		return {"type": "SKIP_CHARGE", "actor_unit_id": unit_id, "_ai_description": "Skip charge for %s (no target positions)" % unit_name}

	# Primary target: the first (typically only) target
	var primary_target_pos = target_positions[0]

	# Get all non-target enemy model positions to avoid ending in their engagement range
	var non_target_enemies = []  # Array of {position: Vector2, base_radius_px: float}
	for uid in snapshot.get("units", {}):
		var u = snapshot.units[uid]
		if u.get("owner", 0) == player:
			continue  # Skip friendly
		if uid in target_ids:
			continue  # Skip declared targets
		var u_status = u.get("status", 0)
		if u_status == GameStateData.UnitStatus.UNDEPLOYED or u_status == GameStateData.UnitStatus.IN_RESERVES:
			continue
		for m in u.get("models", []):
			if not m.get("alive", true):
				continue
			var mp = _get_model_position(m)
			if mp == Vector2.INF:
				continue
			var br = _model_bounding_radius_px(m.get("base_mm", 32), m.get("base_type", "circular"), m.get("base_dimensions", {}))
			non_target_enemies.append({"position": mp, "base_radius_px": br})

	# Get deployed models for collision checking (excluding this unit)
	var deployed_models = _get_deployed_models_excluding_unit(snapshot, unit_id)

	# Get target model info for engagement range checking
	var target_model_info = []  # Array of {position, base_radius_px} for all target models
	for target_id in target_ids:
		var target_unit = snapshot.get("units", {}).get(target_id, {})
		for tm in target_unit.get("models", []):
			if not tm.get("alive", true):
				continue
			var tp = _get_model_position(tm)
			if tp == Vector2.INF:
				continue
			var br = _model_bounding_radius_px(tm.get("base_mm", 32), tm.get("base_type", "circular"), tm.get("base_dimensions", {}))
			target_model_info.append({"position": tp, "base_radius_px": br, "target_id": target_id})

	var move_budget_px = rolled_distance * PIXELS_PER_INCH
	var first_model = alive_models[0]
	var base_mm = first_model.get("base_mm", 32)
	var base_type = first_model.get("base_type", "circular")
	var base_dimensions = first_model.get("base_dimensions", {})
	var my_base_radius_px = _model_bounding_radius_px(base_mm, base_type, base_dimensions)

	# --- Compute destinations for each model ---
	# Strategy: move each model toward the primary target, stopping at engagement range
	# The lead model should get into base-to-base or just within engagement range
	# Remaining models maintain coherency and follow

	var per_model_paths = {}
	var placed_positions = []  # Track placed positions for intra-unit overlap avoidance

	# Sort models by distance to primary target (closest first)
	var model_distances = []
	for model in alive_models:
		var mid = model.get("id", "")
		var mpos = _get_model_position(model)
		var dist = mpos.distance_to(primary_target_pos)
		model_distances.append({"model": model, "id": mid, "pos": mpos, "dist": dist})
	model_distances.sort_custom(func(a, b): return a.dist < b.dist)

	var engagement_range_px = ENGAGEMENT_RANGE_PX  # 1" = 40px
	var any_model_in_er = {}  # target_id -> bool (track if we've gotten a model in ER per target)
	for tid in target_ids:
		any_model_in_er[tid] = false

	for md in model_distances:
		var model = md.model
		var mid = md.id
		var start_pos = md.pos
		var start_dist_to_target = md.dist

		# Direction toward primary target
		var direction = (primary_target_pos - start_pos).normalized()
		if direction == Vector2.ZERO:
			direction = Vector2.RIGHT

		# Calculate ideal destination: close to target within engagement range
		# Edge-to-edge engagement range: center distance = ER + my_radius + target_radius
		var closest_target_model = _find_closest_target_model_info(start_pos, target_model_info)
		var target_base_radius = closest_target_model.base_radius_px if not closest_target_model.is_empty() else 20.0
		var ideal_center_dist = engagement_range_px + my_base_radius_px + target_base_radius - 2.0  # Slight buffer inside ER
		var target_for_model = closest_target_model.position if not closest_target_model.is_empty() else primary_target_pos

		var dir_to_target = (target_for_model - start_pos).normalized()
		if dir_to_target == Vector2.ZERO:
			dir_to_target = Vector2.RIGHT

		var target_center_dist = start_pos.distance_to(target_for_model)
		var desired_move_dist = target_center_dist - ideal_center_dist
		# Clamp to move budget
		var actual_move_dist = clamp(desired_move_dist, 0.0, move_budget_px)

		var candidate_pos = start_pos + dir_to_target * actual_move_dist

		# Clamp to board bounds
		candidate_pos.x = clamp(candidate_pos.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
		candidate_pos.y = clamp(candidate_pos.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)

		# Check constraints and adjust
		candidate_pos = _adjust_charge_position(
			candidate_pos, start_pos, move_budget_px, my_base_radius_px,
			target_model_info, non_target_enemies, deployed_models,
			placed_positions, base_mm, base_type, base_dimensions
		)

		# Verify the model ends closer to at least one target than it started
		var ends_closer = false
		for tp_info in target_model_info:
			var original_dist = start_pos.distance_to(tp_info.position)
			var new_dist = candidate_pos.distance_to(tp_info.position)
			if new_dist < original_dist:
				ends_closer = true
				break

		if not ends_closer and start_pos.distance_to(candidate_pos) > 1.0:
			# Fallback: don't move this model (stay in place is valid if it was already close)
			candidate_pos = start_pos

		# Track which targets have a model in engagement range
		for tp_info in target_model_info:
			var edge_dist_px = candidate_pos.distance_to(tp_info.position) - my_base_radius_px - tp_info.base_radius_px
			if edge_dist_px <= engagement_range_px:
				any_model_in_er[tp_info.target_id] = true

		# Record the path (start -> end)
		per_model_paths[mid] = [
			[start_pos.x, start_pos.y],
			[candidate_pos.x, candidate_pos.y]
		]

		placed_positions.append({
			"position": candidate_pos,
			"base_mm": base_mm,
			"base_type": base_type,
			"base_dimensions": base_dimensions
		})

	# Verify we achieved engagement range with all targets
	var all_targets_reached = true
	for tid in target_ids:
		if not any_model_in_er.get(tid, false):
			all_targets_reached = false
			print("AIDecisionMaker: Charge move for %s failed to reach target %s engagement range" % [unit_name, tid])
			break

	if not all_targets_reached:
		# Cannot construct a valid charge move — this shouldn't happen if the roll was sufficient
		# but may occur due to geometry constraints. The phase will handle the failure.
		print("AIDecisionMaker: Submitting charge move anyway — phase will validate and handle failure")

	var target_names = []
	for tid in target_ids:
		var t = snapshot.get("units", {}).get(tid, {})
		target_names.append(t.get("meta", {}).get("name", tid))

	return {
		"type": "APPLY_CHARGE_MOVE",
		"actor_unit_id": unit_id,
		"payload": {
			"per_model_paths": per_model_paths,
			"per_model_rotations": {},
		},
		"_ai_description": "%s charges into %s (rolled %d\")" % [unit_name, ", ".join(target_names), rolled_distance]
	}

static func _find_closest_target_model_info(pos: Vector2, target_model_info: Array) -> Dictionary:
	"""Find the closest target model info dict to a given position."""
	var closest = {}
	var closest_dist = INF
	for info in target_model_info:
		var d = pos.distance_to(info.position)
		if d < closest_dist:
			closest_dist = d
			closest = info
	return closest

static func _adjust_charge_position(
	candidate: Vector2, start_pos: Vector2, move_budget_px: float,
	my_base_radius_px: float, target_model_info: Array,
	non_target_enemies: Array, deployed_models: Array,
	placed_positions: Array, base_mm: int, base_type: String,
	base_dimensions: Dictionary
) -> Vector2:
	"""Adjust a candidate charge position to satisfy constraints:
	- Must not exceed move budget from start
	- Must not overlap with deployed models or already-placed models
	- Must not end in engagement range of non-target enemies
	Returns the adjusted position."""

	var pos = candidate

	# 1. Ensure within move budget
	var move_dist = start_pos.distance_to(pos)
	if move_dist > move_budget_px:
		var dir = (pos - start_pos).normalized()
		pos = start_pos + dir * move_budget_px

	# 2. Check for non-target enemy engagement range violation
	var er_px = ENGAGEMENT_RANGE_PX
	for nte in non_target_enemies:
		var edge_dist = pos.distance_to(nte.position) - my_base_radius_px - nte.base_radius_px
		if edge_dist <= er_px:
			# Push away from non-target enemy
			var push_dir = (pos - nte.position).normalized()
			if push_dir == Vector2.ZERO:
				push_dir = Vector2.RIGHT
			var needed_dist = my_base_radius_px + nte.base_radius_px + er_px + 5.0  # 5px safety margin
			pos = nte.position + push_dir * needed_dist

			# Re-check move budget after push
			move_dist = start_pos.distance_to(pos)
			if move_dist > move_budget_px:
				var dir = (pos - start_pos).normalized()
				pos = start_pos + dir * move_budget_px

	# 3. Check for overlap with deployed models
	var all_obstacles = deployed_models + placed_positions
	if _position_collides_with_deployed(pos, base_mm, all_obstacles, 4.0, base_type, base_dimensions):
		# Spiral search for nearest free position
		var step = my_base_radius_px * 2.0 + 8.0
		for ring in range(1, 6):
			var ring_radius = step * ring * 0.5
			var points_in_ring = maxi(8, ring * 6)
			for p_idx in range(points_in_ring):
				var angle = (2.0 * PI * p_idx) / points_in_ring
				var test_pos = Vector2(
					pos.x + cos(angle) * ring_radius,
					pos.y + sin(angle) * ring_radius
				)
				# Check move budget
				if start_pos.distance_to(test_pos) > move_budget_px:
					continue
				# Check board bounds
				test_pos.x = clamp(test_pos.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
				test_pos.y = clamp(test_pos.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)
				# Check no collision
				if not _position_collides_with_deployed(test_pos, base_mm, all_obstacles, 4.0, base_type, base_dimensions):
					# Check no non-target ER violation
					var nte_ok = true
					for nte in non_target_enemies:
						var edge_dist = test_pos.distance_to(nte.position) - my_base_radius_px - nte.base_radius_px
						if edge_dist <= er_px:
							nte_ok = false
							break
					if nte_ok:
						return test_pos

	return pos

# =============================================================================
# FIGHT PHASE
# =============================================================================

static func _decide_fight(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	var action_types = {}
	for a in available_actions:
		var t = a.get("type", "")
		if not action_types.has(t):
			action_types[t] = []
		action_types[t].append(a)

	# Step 1: If we can roll dice (confirmed attacks ready), roll them
	if action_types.has("ROLL_DICE"):
		return {"type": "ROLL_DICE", "_ai_description": "Roll fight dice"}

	# Step 2: If we can confirm attacks, confirm them
	if action_types.has("CONFIRM_AND_RESOLVE_ATTACKS"):
		return {"type": "CONFIRM_AND_RESOLVE_ATTACKS", "_ai_description": "Confirm fight attacks"}

	# Step 3: If pile-in or assign attacks available, handle them
	if action_types.has("ASSIGN_ATTACKS_UI") or action_types.has("PILE_IN"):
		# We need to assign attacks for the active fighter
		# First pile in — compute movements toward nearest enemy (up to 3")
		if action_types.has("PILE_IN"):
			var a = action_types["PILE_IN"][0]
			var uid = a.get("unit_id", "")
			return _compute_pile_in_action(snapshot, uid, player)

		# Then assign attacks
		if action_types.has("ASSIGN_ATTACKS_UI"):
			var a = action_types["ASSIGN_ATTACKS_UI"][0]
			var uid = a.get("unit_id", "")
			return _assign_fight_attacks(snapshot, uid, player)

	# Step 4: If we need to select a fighter, select one
	if action_types.has("SELECT_FIGHTER"):
		var a = action_types["SELECT_FIGHTER"][0]
		var uid = a.get("unit_id", "")
		var unit = snapshot.get("units", {}).get(uid, {})
		var unit_name = unit.get("meta", {}).get("name", uid)
		# T7-37: Include expected melee damage in fighter selection description
		var fighter_enemies = _get_enemy_units(snapshot, player)
		var nearest_enemy_name = ""
		var fighter_melee_dmg = 0.0
		var fighter_target_hp = 0.0
		var nearest_dist = INF
		for eid in fighter_enemies:
			var enemy = fighter_enemies[eid]
			var d = _get_closest_model_distance_inches(unit, enemy) if not unit.is_empty() else INF
			if d < nearest_dist:
				nearest_dist = d
				nearest_enemy_name = enemy.get("meta", {}).get("name", eid)
				fighter_melee_dmg = _estimate_melee_damage(unit, enemy)
				fighter_target_hp = _calculate_kill_threshold(enemy)
		var fighter_desc = "Select %s to fight" % unit_name
		if nearest_enemy_name != "" and fighter_melee_dmg > 0:
			fighter_desc = "%s fights — expected %.1f melee dmg vs %s (%.0f HP)" % [unit_name, fighter_melee_dmg, nearest_enemy_name, fighter_target_hp]
		return {
			"type": "SELECT_FIGHTER",
			"unit_id": uid,
			"_ai_description": fighter_desc
		}

	# Step 5: Consolidate if available
	if action_types.has("CONSOLIDATE"):
		var a = action_types["CONSOLIDATE"][0]
		var uid = a.get("unit_id", "")
		return _compute_consolidate_action(snapshot, uid, player)

	# Step 6: End fight phase
	if action_types.has("END_FIGHT"):
		return {"type": "END_FIGHT", "_ai_description": "End Fight Phase"}

	return {}

static func _assign_fight_attacks(snapshot: Dictionary, unit_id: String, player: int) -> Dictionary:
	var unit = snapshot.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return {}

	# T7-28: Evaluate ALL melee weapon profiles per target to pick damage-maximizing combination
	# Separate weapons into primary (normal) and Extra Attacks categories
	var weapons = unit.get("meta", {}).get("weapons", [])
	var primary_weapons = []  # Non-Extra Attacks melee weapons
	var extra_attack_weapons = []  # Extra Attacks melee weapons (auto-injected by FightPhase)

	for w in weapons:
		if w.get("type", "").to_lower() == "melee":
			if _weapon_has_extra_attacks(w):
				extra_attack_weapons.append(w)
			else:
				primary_weapons.append(w)

	var alive_attackers = _get_alive_models(unit).size()
	if alive_attackers == 0:
		return {}

	# Find eligible enemy targets
	var all_enemies = _get_enemy_units(snapshot, player)
	if all_enemies.is_empty():
		return {}

	# T7-29: Filter to enemies within engagement range first (fight phase rules)
	var engaged_entries = _get_engaging_enemy_units(unit, unit_id, all_enemies)
	var enemies = {}
	for entry in engaged_entries:
		enemies[entry.enemy_id] = entry.enemy_unit

	# If no enemies in engagement range, fall back to all enemies (edge case: pile-in may not have completed)
	if enemies.is_empty():
		print("AIDecisionMaker: T7-29 no engaged enemies found for %s, falling back to all enemies" % unit_id)
		enemies = all_enemies

	var unit_name = unit.get("meta", {}).get("name", unit_id)

	# T7-29: Score each target by combined damage output + strategic value
	# For each target, find the best weapon and compute a composite score
	var best_weapon_id = "close_combat_weapon"
	var best_target_id = ""
	var best_composite_score = -1.0
	var best_weapon_name = "Close combat weapon"
	var best_raw_damage = 0.0

	# Unit strength for default close combat weapon fallback
	var unit_strength = int(unit.get("meta", {}).get("stats", {}).get("strength", 4))
	var objectives = _get_objectives(snapshot)

	for enemy_id in enemies:
		var enemy = enemies[enemy_id]
		var target_toughness = int(enemy.get("meta", {}).get("stats", {}).get("toughness", 4))
		var target_save = int(enemy.get("meta", {}).get("stats", {}).get("save", 4))
		var target_invuln = _get_target_invulnerable_save(enemy)

		# Calculate Extra Attacks weapon damage for this target (constant across primary weapon choices)
		var ea_damage = 0.0
		for ea_w in extra_attack_weapons:
			ea_damage += _evaluate_melee_weapon_damage(ea_w, alive_attackers, target_toughness, target_save, target_invuln)

		# Find the best primary weapon for this target (highest raw damage)
		var target_best_damage = ea_damage
		var target_best_weapon_id = "close_combat_weapon"
		var target_best_weapon_name = "Close combat weapon"

		for w in primary_weapons:
			var primary_damage = _evaluate_melee_weapon_damage(w, alive_attackers, target_toughness, target_save, target_invuln)
			var total = primary_damage + ea_damage
			if total > target_best_damage:
				target_best_damage = total
				target_best_weapon_name = w.get("name", "Unknown")
				target_best_weapon_id = _generate_weapon_id(target_best_weapon_name, w.get("type", "Melee"))

		# Also evaluate default close combat weapon (S=user, AP0, D1, A1, WS4+)
		var ccw_p_hit = _hit_probability(4)
		var ccw_p_wound = _wound_probability(unit_strength, target_toughness)
		var ccw_p_unsaved = 1.0 - _save_probability(target_save, 0, target_invuln)
		var ccw_damage = 1.0 * alive_attackers * ccw_p_hit * ccw_p_wound * ccw_p_unsaved * 1.0
		var ccw_total = ccw_damage + ea_damage
		if ccw_total > target_best_damage:
			target_best_damage = ccw_total
			target_best_weapon_id = "close_combat_weapon"
			target_best_weapon_name = "Close combat weapon"

		# T7-29: Compute strategic value score for this target
		var strategic_score = _score_fight_target(unit, enemy, target_best_damage, snapshot, player, objectives)

		var target_name = enemy.get("meta", {}).get("name", enemy_id)
		print("AIDecisionMaker: T7-29 fight target eval %s vs %s: damage=%.2f, strategic=%.2f, weapon='%s'" % [
			unit_name, target_name, target_best_damage, strategic_score, target_best_weapon_name])

		if strategic_score > best_composite_score:
			best_composite_score = strategic_score
			best_weapon_id = target_best_weapon_id
			best_weapon_name = target_best_weapon_name
			best_target_id = enemy_id
			best_raw_damage = target_best_damage

	# Fallback to closest enemy if no scoring worked
	if best_target_id == "":
		var unit_centroid = _get_unit_centroid(unit)
		var best_dist = INF
		for enemy_id in enemies:
			var enemy = enemies[enemy_id]
			var enemy_centroid = _get_unit_centroid(enemy)
			if enemy_centroid == Vector2.INF:
				continue
			var dist = unit_centroid.distance_to(enemy_centroid)
			if dist < best_dist:
				best_dist = dist
				best_target_id = enemy_id

	if best_target_id == "":
		return {}

	var target_unit = snapshot.get("units", {}).get(best_target_id, {})
	var target_name = target_unit.get("meta", {}).get("name", best_target_id)
	var ea_count = extra_attack_weapons.size()
	print("AIDecisionMaker: T7-29 fight target optimized — %s selects '%s' vs %s (damage: %.2f, score: %.2f, primaries: %d, EA: %d)" % [
		unit_name, best_weapon_name, target_name, best_raw_damage, best_composite_score, primary_weapons.size(), ea_count])

	return {
		"type": "ASSIGN_ATTACKS",
		"unit_id": unit_id,
		"target_id": best_target_id,
		"weapon_id": best_weapon_id,
		"_ai_description": "%s fights %s with %s — expected %.1f melee dmg vs %.0f HP" % [unit_name, target_name, best_weapon_name, best_raw_damage, _calculate_kill_threshold(target_unit)]
	}

# T7-29: Score a fight target by combining expected damage with strategic value factors
# Similar to _score_charge_target but tailored for the fight phase where units are already engaged
static func _score_fight_target(attacker: Dictionary, target: Dictionary, expected_damage: float, snapshot: Dictionary, player: int, objectives: Array) -> float:
	"""Score a melee target in the fight phase by combining expected damage output with
	strategic value. Higher score = better target to attack."""
	var score = 0.0

	# --- Expected melee damage (primary factor) ---
	score += expected_damage * 2.0

	# --- Target value factors ---
	var target_keywords = target.get("meta", {}).get("keywords", [])
	var target_wounds = int(target.get("meta", {}).get("stats", {}).get("wounds", 1))
	var alive_models = _get_alive_models(target).size()
	var total_models = target.get("models", []).size()

	# Bonus for targets below half strength (easier to wipe out — denies VP, removes threat)
	if total_models > 0 and alive_models * 2 < total_models:
		score += 3.0

	# Bonus for CHARACTER targets (high-value eliminations)
	if "CHARACTER" in target_keywords:
		score += 2.0

	# Penalty for targets we can't meaningfully damage
	if expected_damage < 1.0:
		score -= 3.0

	# --- Kill potential bonus: can we actually wipe the target? ---
	var target_remaining_wounds = float(alive_models * target_wounds)
	if expected_damage >= target_remaining_wounds and target_remaining_wounds > 0:
		# We can likely wipe this unit — big bonus for removing it from the game
		score += 4.0
	elif target_remaining_wounds > 0 and expected_damage >= target_remaining_wounds * 0.5:
		# We can take them below half strength
		score += 2.0

	# --- Overkill penalty: don't waste massive damage on a nearly-dead 1-model unit ---
	if target_remaining_wounds > 0 and expected_damage > target_remaining_wounds * 2.0:
		# More than 2x the wounds remaining — we're overkilling
		score -= 1.5

	# --- Lock dangerous shooters bonus: keep ranged threats tied up in combat ---
	var target_has_ranged = _unit_has_ranged_weapons(target)
	if target_has_ranged:
		var max_range = _get_max_weapon_range(target)
		if max_range >= 24.0:
			score += 2.0  # Lock long-range shooters
		var ranged_output = _estimate_unit_ranged_strength(target)
		if ranged_output >= PHASE_PLAN_RANGED_STRENGTH_DANGEROUS:
			score += 1.5  # Extra bonus for truly dangerous shooters

	# --- Target on objective bonus ---
	var target_centroid = _get_unit_centroid(target)
	if target_centroid != Vector2.INF:
		for obj_pos in objectives:
			if target_centroid.distance_to(obj_pos) <= OBJECTIVE_CONTROL_RANGE_PX:
				score += 2.0  # Killing/weakening units on objectives is valuable
				break

	# --- Low toughness bonus (likely to wound effectively) ---
	var target_toughness = int(target.get("meta", {}).get("stats", {}).get("toughness", 4))
	if target_toughness <= 3:
		score += 1.0

	# --- AI-GAP-4: Factor in target's defensive abilities ---
	var target_id = target.get("id", "")
	if target_id != "":
		var all_units = snapshot.get("units", {})
		var def_mult = AIAbilityAnalyzerData.get_defensive_multiplier(target_id, target, all_units)
		if def_mult > 1.0:
			score /= def_mult

	# --- Trade efficiency: prefer favorable point trades ---
	var trade_eff = _get_trade_efficiency(attacker, target)
	if trade_eff != 1.0:
		score *= trade_eff

	return max(0.0, score)

# T7-28: Helper — check if weapon data has the Extra Attacks keyword
static func _weapon_has_extra_attacks(weapon_data: Dictionary) -> bool:
	var special_rules = weapon_data.get("special_rules", "").to_lower()
	if "extra attacks" in special_rules:
		return true
	var keywords = weapon_data.get("keywords", [])
	for keyword in keywords:
		if "extra attacks" in keyword.to_lower():
			return true
	return false

# T7-28: Helper — calculate expected damage for a single melee weapon against a target
static func _evaluate_melee_weapon_damage(weapon: Dictionary, alive_attackers: int, target_toughness: int, target_save: int, target_invuln: int) -> float:
	var attacks_str = str(weapon.get("attacks", "1"))
	var attacks = float(attacks_str) if attacks_str.is_valid_float() else 1.0

	var ws_str = str(weapon.get("weapon_skill", weapon.get("ballistic_skill", "4")))
	var ws = int(ws_str) if ws_str.is_valid_int() else 4

	var strength_str = str(weapon.get("strength", "4"))
	var strength = int(strength_str) if strength_str.is_valid_int() else 4

	var ap_str = str(weapon.get("ap", "0"))
	var ap = 0
	if ap_str.begins_with("-"):
		var ap_num = ap_str.substr(1)
		ap = int(ap_num) if ap_num.is_valid_int() else 0
	else:
		ap = int(ap_str) if ap_str.is_valid_int() else 0

	var damage_str = str(weapon.get("damage", "1"))
	var damage = float(damage_str) if damage_str.is_valid_float() else 1.0

	var p_hit = _hit_probability(ws)
	var p_wound = _wound_probability(strength, target_toughness)
	var p_unsaved = 1.0 - _save_probability(target_save, ap, target_invuln)

	return attacks * alive_attackers * p_hit * p_wound * p_unsaved * damage

# =============================================================================
# PILE-IN MOVEMENT COMPUTATION
# =============================================================================

static func _pile_in_position_collides(pos: Vector2, base_mm: int,
		friendly_obstacles: Array, enemy_obstacles: Array, placed_positions: Array,
		base_type: String = "circular", base_dimensions: Dictionary = {}) -> bool:
	"""Check collision during pile-in/consolidation movement.
	Uses 2px gap for friendly models (prevent stacking), -1px gap for enemy models
	(allow base-to-base contact but prevent true physical overlap)."""
	if _position_collides_with_deployed(pos, base_mm, friendly_obstacles + placed_positions, 2.0, base_type, base_dimensions):
		return true
	if _position_collides_with_deployed(pos, base_mm, enemy_obstacles, -1.0, base_type, base_dimensions):
		return true
	return false

static func _compute_pile_in_action(snapshot: Dictionary, unit_id: String, player: int) -> Dictionary:
	"""Compute pile-in movements for a unit. Each model moves up to 3" toward the
	closest enemy model (edge-to-edge). Models already in base contact stay put.
	Returns a PILE_IN action dict with the movements dictionary."""
	var unit = snapshot.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return {
			"type": "PILE_IN",
			"unit_id": unit_id,
			"actor_unit_id": unit_id,
			"movements": {},
			"_ai_description": "Pile in (unit not found)"
		}

	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var movements = _compute_pile_in_movements(snapshot, unit_id, unit, player)

	var description = ""
	if movements.is_empty():
		description = "%s pile in (all models holding position)" % unit_name
	else:
		description = "%s piles in toward enemy (%d models moved)" % [unit_name, movements.size()]

	print("AIDecisionMaker: %s" % description)

	return {
		"type": "PILE_IN",
		"unit_id": unit_id,
		"actor_unit_id": unit_id,
		"movements": movements,
		"_ai_description": description
	}

static func _compute_pile_in_movements(snapshot: Dictionary, unit_id: String, unit: Dictionary, player: int) -> Dictionary:
	"""Compute per-model pile-in destinations. Returns {model_id_string: Vector2} for models
	that should move. Models that stay put are omitted.

	Pile-in rules (10th edition):
	- Each model may move up to 3"
	- Each model must end closer to the closest enemy model than it started
	- Models already in base-to-base contact with an enemy cannot move
	- After pile-in, unit must still be in engagement range of at least one enemy
	- Unit coherency must be maintained
	- If a model CAN reach base-to-base contact within 3", it SHOULD"""

	var movements = {}
	var alive_models = _get_alive_models_with_positions(unit)
	if alive_models.is_empty():
		return movements

	var unit_owner = int(unit.get("owner", player))

	# Gather all enemy model info for distance calculations
	var unit_keywords = unit.get("meta", {}).get("keywords", [])
	var has_fly = "FLY" in unit_keywords
	var enemy_models_info = []  # Array of {position: Vector2, base_radius_px: float, base_mm: int}
	for other_unit_id in snapshot.get("units", {}):
		var other_unit = snapshot.units[other_unit_id]
		if int(other_unit.get("owner", 0)) == unit_owner:
			continue  # Skip friendly
		# Skip undeployed / in reserves
		var other_status = other_unit.get("status", 0)
		if other_status == GameStateData.UnitStatus.UNDEPLOYED or other_status == GameStateData.UnitStatus.IN_RESERVES:
			continue
		# Skip AIRCRAFT unless our unit has FLY (T4-4 rule)
		var other_keywords = other_unit.get("meta", {}).get("keywords", [])
		if "AIRCRAFT" in other_keywords and not has_fly:
			continue
		for em in other_unit.get("models", []):
			if not em.get("alive", true):
				continue
			var ep = _get_model_position(em)
			if ep == Vector2.INF:
				continue
			var ebr = _model_bounding_radius_px(em.get("base_mm", 32), em.get("base_type", "circular"), em.get("base_dimensions", {}))
			enemy_models_info.append({
				"position": ep,
				"base_radius_px": ebr,
				"base_mm": em.get("base_mm", 32),
			})

	if enemy_models_info.is_empty():
		print("AIDecisionMaker: Pile-in for %s — no enemy models found" % unit_id)
		return movements

	# Get deployed models split by allegiance for collision checking
	# Friendly models use 2px gap (prevent stacking), enemy models use -1px gap
	# (allow base-to-base contact during pile-in)
	var obstacle_split = _get_deployed_models_split(snapshot, unit_id, unit_owner)
	var friendly_obstacles = obstacle_split.friendly
	var enemy_obstacles = obstacle_split.enemy

	var pile_in_range_px = 3.0 * PIXELS_PER_INCH  # 3" in pixels
	var base_contact_threshold_px = 0.25 * PIXELS_PER_INCH  # Match FightPhase tolerance (0.25")

	# Track placed positions to avoid intra-unit collisions
	var placed_positions = []

	# Sort models by distance to nearest enemy (furthest first so they trail behind)
	var model_entries = []
	for model in alive_models:
		var mid = model.get("id", "")
		var mpos = _get_model_position(model)
		if mpos == Vector2.INF:
			continue
		var mbr = _model_bounding_radius_px(model.get("base_mm", 32), model.get("base_type", "circular"), model.get("base_dimensions", {}))

		# Find closest enemy model (edge-to-edge)
		var closest_enemy_dist_px = INF
		var closest_enemy_pos = Vector2.INF
		var closest_enemy_radius = 0.0
		for ei in enemy_models_info:
			var edge_dist = mpos.distance_to(ei.position) - mbr - ei.base_radius_px
			if edge_dist < closest_enemy_dist_px:
				closest_enemy_dist_px = edge_dist
				closest_enemy_pos = ei.position
				closest_enemy_radius = ei.base_radius_px

		model_entries.append({
			"model": model,
			"id": mid,
			"pos": mpos,
			"base_radius_px": mbr,
			"closest_enemy_dist_px": closest_enemy_dist_px,
			"closest_enemy_pos": closest_enemy_pos,
			"closest_enemy_radius": closest_enemy_radius,
		})

	# Sort: models closest to enemies first (they get priority placement)
	model_entries.sort_custom(func(a, b): return a.closest_enemy_dist_px < b.closest_enemy_dist_px)

	for entry in model_entries:
		var mid = entry.id
		var start_pos = entry.pos
		var my_radius = entry.base_radius_px
		var closest_enemy_pos = entry.closest_enemy_pos
		var closest_enemy_radius = entry.closest_enemy_radius
		var closest_enemy_dist_px = entry.closest_enemy_dist_px
		var model = entry.model
		var base_mm = model.get("base_mm", 32)
		var base_type = model.get("base_type", "circular")
		var base_dimensions = model.get("base_dimensions", {})

		if closest_enemy_pos == Vector2.INF:
			# No enemy found for this model - skip
			placed_positions.append({
				"position": start_pos,
				"base_mm": base_mm,
				"base_type": base_type,
				"base_dimensions": base_dimensions,
			})
			continue

		# Check if model is already in base contact with nearest enemy
		if closest_enemy_dist_px <= base_contact_threshold_px:
			# Model is in base contact — do not move (T4-5)
			print("AIDecisionMaker: Pile-in model %s already in base contact (dist=%.1fpx), holding" % [mid, closest_enemy_dist_px])
			placed_positions.append({
				"position": start_pos,
				"base_mm": base_mm,
				"base_type": base_type,
				"base_dimensions": base_dimensions,
			})
			continue

		# Calculate direction toward closest enemy
		var direction = (closest_enemy_pos - start_pos).normalized()
		if direction == Vector2.ZERO:
			direction = Vector2.RIGHT

		# Calculate ideal destination: base-to-base contact with closest enemy
		# Center-to-center distance for base contact = my_radius + enemy_radius
		var b2b_center_dist = my_radius + closest_enemy_radius
		var current_center_dist = start_pos.distance_to(closest_enemy_pos)
		var desired_move_dist_px = current_center_dist - b2b_center_dist

		# Clamp to 3" pile-in limit
		var actual_move_dist_px = clampf(desired_move_dist_px, 0.0, pile_in_range_px)

		# If the model barely needs to move (sub-pixel), skip it
		if actual_move_dist_px < 1.0:
			placed_positions.append({
				"position": start_pos,
				"base_mm": base_mm,
				"base_type": base_type,
				"base_dimensions": base_dimensions,
			})
			continue

		var candidate_pos = start_pos + direction * actual_move_dist_px

		# Clamp to board bounds
		candidate_pos.x = clampf(candidate_pos.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
		candidate_pos.y = clampf(candidate_pos.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)

		# Check collision with deployed models + already placed models from this unit
		# Friendly obstacles use 2px gap, enemy obstacles use -1px gap (allow B2B contact)
		if _pile_in_position_collides(candidate_pos, base_mm, friendly_obstacles, enemy_obstacles, placed_positions, base_type, base_dimensions):
			# Try to find a nearby collision-free position still closer to the enemy
			var found_alt = false
			var step = my_radius * 2.0 + 4.0
			for ring in range(1, 5):
				var ring_radius = step * ring * 0.4
				var points_in_ring = maxi(8, ring * 6)
				for p_idx in range(points_in_ring):
					var angle = (2.0 * PI * p_idx) / points_in_ring
					var test_pos = Vector2(
						candidate_pos.x + cos(angle) * ring_radius,
						candidate_pos.y + sin(angle) * ring_radius
					)
					# Check move budget
					if start_pos.distance_to(test_pos) > pile_in_range_px:
						continue
					# Must be closer to enemy than start
					if test_pos.distance_to(closest_enemy_pos) >= start_pos.distance_to(closest_enemy_pos):
						continue
					# Clamp to board
					test_pos.x = clampf(test_pos.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
					test_pos.y = clampf(test_pos.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)
					# Check collision (friendly gap=2px, enemy gap=-1px)
					if not _pile_in_position_collides(test_pos, base_mm, friendly_obstacles, enemy_obstacles, placed_positions, base_type, base_dimensions):
						candidate_pos = test_pos
						found_alt = true
						break
				if found_alt:
					break

			if not found_alt:
				# Cannot find collision-free position — hold position
				print("AIDecisionMaker: Pile-in model %s collision — holding position" % mid)
				placed_positions.append({
					"position": start_pos,
					"base_mm": base_mm,
					"base_type": base_type,
					"base_dimensions": base_dimensions,
				})
				continue

		# Verify the model ends closer to the closest enemy than it started
		var new_dist_to_enemy = candidate_pos.distance_to(closest_enemy_pos)
		var old_dist_to_enemy = start_pos.distance_to(closest_enemy_pos)
		if new_dist_to_enemy >= old_dist_to_enemy:
			# Movement doesn't bring us closer — skip (validation would reject)
			print("AIDecisionMaker: Pile-in model %s would not end closer to enemy, skipping" % mid)
			placed_positions.append({
				"position": start_pos,
				"base_mm": base_mm,
				"base_type": base_type,
				"base_dimensions": base_dimensions,
			})
			continue

		# Record the movement
		# FightPhase expects model_id as string index into the models array
		# We need to find the index of this model in the unit's models array
		var model_index = _find_model_index_in_unit(unit, mid)
		if model_index == -1:
			print("AIDecisionMaker: Pile-in model %s index not found, skipping" % mid)
			placed_positions.append({
				"position": start_pos,
				"base_mm": base_mm,
				"base_type": base_type,
				"base_dimensions": base_dimensions,
			})
			continue

		var move_inches = start_pos.distance_to(candidate_pos) / PIXELS_PER_INCH
		print("AIDecisionMaker: Pile-in model %s (idx %d) moves %.1f\" toward enemy" % [mid, model_index, move_inches])

		movements[str(model_index)] = candidate_pos
		placed_positions.append({
			"position": candidate_pos,
			"base_mm": base_mm,
			"base_type": base_type,
			"base_dimensions": base_dimensions,
		})

	return movements

static func _find_model_index_in_unit(unit: Dictionary, model_id: String) -> int:
	"""Find the index of a model in a unit's models array by its id field."""
	var models = unit.get("models", [])
	for i in range(models.size()):
		if models[i].get("id", "") == model_id:
			return i
	# Fallback: try matching as string index
	if model_id.is_valid_int():
		var idx = int(model_id)
		if idx >= 0 and idx < models.size():
			return idx
	return -1

# =============================================================================
# CONSOLIDATION MOVEMENT COMPUTATION
# =============================================================================

static func _compute_consolidate_action(snapshot: Dictionary, unit_id: String, player: int) -> Dictionary:
	"""Compute consolidation movements for a unit after fighting.
	Consolidation has two modes:
	- ENGAGEMENT: If any enemy is within 4" (3" move + 1" engagement range),
	  move each model up to 3" toward closest enemy (same rules as pile-in).
	- OBJECTIVE: If no enemy reachable, move each model up to 3" toward
	  the closest objective marker.
	Returns a CONSOLIDATE action dict with the movements dictionary."""
	var unit = snapshot.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return {
			"type": "CONSOLIDATE",
			"unit_id": unit_id,
			"movements": {},
			"_ai_description": "Consolidate (unit not found)"
		}

	var unit_name = unit.get("meta", {}).get("name", unit_id)

	# T4-4: Aircraft cannot Consolidate
	var unit_keywords = unit.get("meta", {}).get("keywords", [])
	if "AIRCRAFT" in unit_keywords:
		print("AIDecisionMaker: %s is AIRCRAFT — skipping consolidation" % unit_name)
		return {
			"type": "CONSOLIDATE",
			"unit_id": unit_id,
			"movements": {},
			"_ai_description": "%s skips consolidation (AIRCRAFT)" % unit_name
		}

	# Determine consolidation mode: engagement or objective
	var mode = _determine_ai_consolidate_mode(snapshot, unit, player)
	var movements = {}

	if mode == "ENGAGEMENT":
		# Enhanced consolidation: prioritise wrapping enemies and tagging new units
		movements = _compute_consolidate_movements_engagement(snapshot, unit_id, unit, player)
	elif mode == "OBJECTIVE":
		movements = _compute_consolidate_movements_objective(snapshot, unit_id, unit, player)

	var description = ""
	if movements.is_empty():
		description = "%s consolidates (all models holding position)" % unit_name
	else:
		var mode_label = "toward enemy" if mode == "ENGAGEMENT" else "toward objective"
		description = "%s consolidates %s (%d models moved)" % [unit_name, mode_label, movements.size()]

	print("AIDecisionMaker: %s" % description)

	return {
		"type": "CONSOLIDATE",
		"unit_id": unit_id,
		"movements": movements,
		"_ai_description": description
	}

static func _determine_ai_consolidate_mode(snapshot: Dictionary, unit: Dictionary, player: int) -> String:
	"""Determine whether the AI should consolidate toward enemies (ENGAGEMENT) or
	toward the nearest objective (OBJECTIVE).
	- ENGAGEMENT: at least one alive enemy model is within 4" (3" move + 1" ER)
	  of at least one alive friendly model in this unit.
	- OBJECTIVE: no enemy is reachable but an objective exists.
	- NONE: neither target is available.
	T7-43: In rounds 4-5, prefer OBJECTIVE over ENGAGEMENT when enemies are only
	marginally reachable (3-4") and an uncontrolled/contested objective is nearby."""
	var unit_owner = int(unit.get("owner", player))
	var unit_keywords = unit.get("meta", {}).get("keywords", [])
	var has_fly = "FLY" in unit_keywords

	var engagement_check_range_px = 4.0 * PIXELS_PER_INCH  # 3" move + 1" ER
	# T7-43: Tighter range for "firmly engaged" — enemy within 2" means we should stay
	var firm_engagement_range_px = 2.0 * PIXELS_PER_INCH

	var alive_models = _get_alive_models_with_positions(unit)
	if alive_models.is_empty():
		return "NONE"

	# Check if any enemy model is within 4" of any of our models (edge-to-edge)
	var enemy_reachable = false
	var enemy_firmly_engaged = false
	for model in alive_models:
		var mpos = _get_model_position(model)
		if mpos == Vector2.INF:
			continue
		var mbr = _model_bounding_radius_px(model.get("base_mm", 32), model.get("base_type", "circular"), model.get("base_dimensions", {}))

		for other_unit_id in snapshot.get("units", {}):
			var other_unit = snapshot.units[other_unit_id]
			if int(other_unit.get("owner", 0)) == unit_owner:
				continue  # Skip friendly
			var other_status = other_unit.get("status", 0)
			if other_status == GameStateData.UnitStatus.UNDEPLOYED or other_status == GameStateData.UnitStatus.IN_RESERVES:
				continue
			var other_keywords = other_unit.get("meta", {}).get("keywords", [])
			if "AIRCRAFT" in other_keywords and not has_fly:
				continue
			for em in other_unit.get("models", []):
				if not em.get("alive", true):
					continue
				var ep = _get_model_position(em)
				if ep == Vector2.INF:
					continue
				var ebr = _model_bounding_radius_px(em.get("base_mm", 32), em.get("base_type", "circular"), em.get("base_dimensions", {}))
				var edge_dist_px = mpos.distance_to(ep) - mbr - ebr
				if edge_dist_px <= engagement_check_range_px:
					enemy_reachable = true
				if edge_dist_px <= firm_engagement_range_px:
					enemy_firmly_engaged = true

	if enemy_reachable:
		# T7-43: In rounds 4-5, if enemies are only marginally reachable (not firmly engaged),
		# prefer consolidating toward objectives instead. Objective control > kills in late game.
		var consol_battle_round = snapshot.get("meta", {}).get("battle_round", snapshot.get("battle_round", 1))
		if consol_battle_round >= 4 and not enemy_firmly_engaged:
			var objectives = _get_objectives(snapshot)
			if not objectives.is_empty():
				# Check if any objective is nearby and uncontrolled/contested
				var unit_centroid = _get_unit_centroid(unit)
				if unit_centroid != Vector2.INF:
					for obj_pos in objectives:
						var obj_dist = unit_centroid.distance_to(obj_pos)
						if obj_dist <= 6.0 * PIXELS_PER_INCH:  # Objective within 6" — worth consolidating toward
							print("AIDecisionMaker: [STRATEGY] Round %d — consolidating toward objective instead of marginally reachable enemy" % consol_battle_round)
							return "OBJECTIVE"
		return "ENGAGEMENT"

	# No enemy reachable — check for objectives
	var objectives = _get_objectives(snapshot)
	if not objectives.is_empty():
		return "OBJECTIVE"

	return "NONE"

static func _compute_consolidate_movements_engagement(snapshot: Dictionary, unit_id: String, unit: Dictionary, player: int) -> Dictionary:
	"""Compute per-model consolidation destinations in engagement mode.
	Enhanced over basic pile-in with priorities:
	1. Tag new enemy units — move into ER with enemy units not currently engaged
	2. Wrap enemies — distribute models around the enemy to block fall-back
	3. Move toward closest enemy — fallback (same as pile-in)
	Maintains coherency and respects 3" movement limit.
	Returns {model_index_string: Vector2} for models that should move."""

	var movements = {}
	var alive_models = _get_alive_models_with_positions(unit)
	if alive_models.is_empty():
		return movements

	var unit_owner = int(unit.get("owner", player))
	var unit_keywords = unit.get("meta", {}).get("keywords", [])
	var has_fly = "FLY" in unit_keywords

	# Gather enemy model info grouped by unit
	var enemy_units_info = {}  # {unit_id: [{position, base_radius_px, base_mm, model_idx}]}
	var all_enemy_models_info = []  # flat list for closest-enemy lookups
	for other_unit_id in snapshot.get("units", {}):
		var other_unit = snapshot.units[other_unit_id]
		if int(other_unit.get("owner", 0)) == unit_owner:
			continue
		var other_status = other_unit.get("status", 0)
		if other_status == GameStateData.UnitStatus.UNDEPLOYED or other_status == GameStateData.UnitStatus.IN_RESERVES:
			continue
		var other_keywords = other_unit.get("meta", {}).get("keywords", [])
		if "AIRCRAFT" in other_keywords and not has_fly:
			continue
		var unit_models = []
		for em in other_unit.get("models", []):
			if not em.get("alive", true):
				continue
			var ep = _get_model_position(em)
			if ep == Vector2.INF:
				continue
			var ebr = _model_bounding_radius_px(em.get("base_mm", 32), em.get("base_type", "circular"), em.get("base_dimensions", {}))
			var info = {
				"position": ep,
				"base_radius_px": ebr,
				"base_mm": em.get("base_mm", 32),
				"enemy_unit_id": other_unit_id,
			}
			unit_models.append(info)
			all_enemy_models_info.append(info)
		if not unit_models.is_empty():
			enemy_units_info[other_unit_id] = unit_models

	if all_enemy_models_info.is_empty():
		print("AIDecisionMaker: Consolidate (engagement) for %s — no enemy models found" % unit_id)
		return movements

	# Get deployed models split for collision detection
	var obstacle_split = _get_deployed_models_split(snapshot, unit_id, unit_owner)
	var friendly_obstacles = obstacle_split.friendly
	var enemy_obstacles = obstacle_split.enemy

	var consolidate_range_px = 3.0 * PIXELS_PER_INCH
	var base_contact_threshold_px = 0.25 * PIXELS_PER_INCH

	# Track placed positions
	var placed_positions = []

	# Determine which enemy units we are ALREADY engaged with (any model in ER)
	var engaged_enemy_unit_ids = {}
	for model in alive_models:
		var mpos = _get_model_position(model)
		if mpos == Vector2.INF:
			continue
		var mbr = _model_bounding_radius_px(model.get("base_mm", 32), model.get("base_type", "circular"), model.get("base_dimensions", {}))
		for ei in all_enemy_models_info:
			var edge_dist = mpos.distance_to(ei.position) - mbr - ei.base_radius_px
			if edge_dist <= ENGAGEMENT_RANGE_PX:
				engaged_enemy_unit_ids[ei.enemy_unit_id] = true

	# Find taggable enemy units (within 4" range but NOT currently engaged)
	var taggable_enemy_units = {}  # {unit_id: [model_info]}
	for euid in enemy_units_info:
		if engaged_enemy_unit_ids.has(euid):
			continue
		# Check if any of our models can reach any model in this enemy unit (within 4")
		for model in alive_models:
			var mpos = _get_model_position(model)
			if mpos == Vector2.INF:
				continue
			var mbr = _model_bounding_radius_px(model.get("base_mm", 32), model.get("base_type", "circular"), model.get("base_dimensions", {}))
			for ei in enemy_units_info[euid]:
				var edge_dist = mpos.distance_to(ei.position) - mbr - ei.base_radius_px
				if edge_dist <= consolidate_range_px + ENGAGEMENT_RANGE_PX:
					taggable_enemy_units[euid] = enemy_units_info[euid]
					break
			if taggable_enemy_units.has(euid):
				break

	if not taggable_enemy_units.is_empty():
		print("AIDecisionMaker: Consolidate %s found %d taggable enemy unit(s)" % [unit_id, taggable_enemy_units.size()])

	# Build model entries with per-model info
	var model_entries = []
	for model in alive_models:
		var mid = model.get("id", "")
		var mpos = _get_model_position(model)
		if mpos == Vector2.INF:
			continue
		var mbr = _model_bounding_radius_px(model.get("base_mm", 32), model.get("base_type", "circular"), model.get("base_dimensions", {}))

		# Find closest enemy model
		var closest_enemy_dist_px = INF
		var closest_enemy_pos = Vector2.INF
		var closest_enemy_radius = 0.0
		var closest_enemy_unit_id = ""
		for ei in all_enemy_models_info:
			var edge_dist = mpos.distance_to(ei.position) - mbr - ei.base_radius_px
			if edge_dist < closest_enemy_dist_px:
				closest_enemy_dist_px = edge_dist
				closest_enemy_pos = ei.position
				closest_enemy_radius = ei.base_radius_px
				closest_enemy_unit_id = ei.enemy_unit_id

		# Check if this model can tag a new enemy unit (closest enemy is from unengaged unit)
		var can_tag_new = closest_enemy_unit_id != "" and taggable_enemy_units.has(closest_enemy_unit_id)

		# Also check if any taggable enemy model is within reach even if not closest
		var tag_target_pos = Vector2.INF
		var tag_target_radius = 0.0
		var tag_target_dist = INF
		if not taggable_enemy_units.is_empty() and not can_tag_new:
			for euid in taggable_enemy_units:
				for ei in taggable_enemy_units[euid]:
					var edge_dist = mpos.distance_to(ei.position) - mbr - ei.base_radius_px
					if edge_dist <= consolidate_range_px + ENGAGEMENT_RANGE_PX and edge_dist < tag_target_dist:
						tag_target_dist = edge_dist
						tag_target_pos = ei.position
						tag_target_radius = ei.base_radius_px

		model_entries.append({
			"model": model,
			"id": mid,
			"pos": mpos,
			"base_radius_px": mbr,
			"closest_enemy_dist_px": closest_enemy_dist_px,
			"closest_enemy_pos": closest_enemy_pos,
			"closest_enemy_radius": closest_enemy_radius,
			"closest_enemy_unit_id": closest_enemy_unit_id,
			"can_tag_new": can_tag_new,
			"tag_target_pos": tag_target_pos,
			"tag_target_radius": tag_target_radius,
		})

	# Sort: models closest to enemies first (they get priority for base contact),
	# but tag-capable models get higher priority
	model_entries.sort_custom(func(a, b):
		# Tag-capable models go first
		if a.can_tag_new and not b.can_tag_new:
			return true
		if b.can_tag_new and not a.can_tag_new:
			return false
		# Then by distance to closest enemy (closest first)
		return a.closest_enemy_dist_px < b.closest_enemy_dist_px
	)

	# Track which angular positions around each enemy have been claimed (for wrapping)
	var claimed_angles = {}  # {enemy_pos_key: [angle1, angle2, ...]}

	for entry in model_entries:
		var mid = entry.id
		var start_pos = entry.pos
		var my_radius = entry.base_radius_px
		var closest_enemy_pos = entry.closest_enemy_pos
		var closest_enemy_radius = entry.closest_enemy_radius
		var closest_enemy_dist_px = entry.closest_enemy_dist_px
		var model = entry.model
		var base_mm = model.get("base_mm", 32)
		var base_type = model.get("base_type", "circular")
		var base_dimensions = model.get("base_dimensions", {})

		if closest_enemy_pos == Vector2.INF:
			placed_positions.append({"position": start_pos, "base_mm": base_mm, "base_type": base_type, "base_dimensions": base_dimensions})
			continue

		# Check if model is already in base contact — hold position
		if closest_enemy_dist_px <= base_contact_threshold_px:
			print("AIDecisionMaker: Consolidate model %s already in base contact (dist=%.1fpx), holding" % [mid, closest_enemy_dist_px])
			# Record this angle as claimed for wrapping
			var angle_to_model = (start_pos - closest_enemy_pos).angle()
			var ekey = "%d_%d" % [int(closest_enemy_pos.x), int(closest_enemy_pos.y)]
			if not claimed_angles.has(ekey):
				claimed_angles[ekey] = []
			claimed_angles[ekey].append(angle_to_model)
			placed_positions.append({"position": start_pos, "base_mm": base_mm, "base_type": base_type, "base_dimensions": base_dimensions})
			continue

		# Determine target position based on priority
		var target_enemy_pos = closest_enemy_pos
		var target_enemy_radius = closest_enemy_radius
		var is_tagging = false

		# Priority 1: If this model can tag a new enemy unit (closest enemy is unengaged)
		if entry.can_tag_new:
			is_tagging = true
			print("AIDecisionMaker: Consolidate model %s targeting new enemy unit for tagging" % mid)
		elif entry.tag_target_pos != Vector2.INF:
			# Model has a reachable taggable enemy that's not its closest.
			# We still MUST move closer to the closest enemy (rules requirement),
			# but we can try a direction that angles toward the taggable target
			# while still ending closer to the closest enemy.
			pass

		# Priority 2: Wrapping — calculate a wrap position around the target enemy
		var b2b_center_dist = my_radius + target_enemy_radius
		var current_center_dist = start_pos.distance_to(target_enemy_pos)
		var can_reach_b2b = (current_center_dist - b2b_center_dist) <= consolidate_range_px

		var candidate_pos = Vector2.INF

		if can_reach_b2b:
			# Calculate wrap position: try to place on the FAR side of the enemy
			# (opposite from our approach direction — blocks enemy fall-back)
			var approach_dir = (target_enemy_pos - start_pos).normalized()
			var ekey = "%d_%d" % [int(target_enemy_pos.x), int(target_enemy_pos.y)]
			if not claimed_angles.has(ekey):
				claimed_angles[ekey] = []

			# Try angles starting from far side (180° from approach), then sweeping
			var base_angle = approach_dir.angle()
			var wrap_angles = []
			# Far side (ideal wrap position)
			wrap_angles.append(base_angle + PI)
			# Flanking positions
			wrap_angles.append(base_angle + PI * 0.75)
			wrap_angles.append(base_angle - PI * 0.75)
			wrap_angles.append(base_angle + PI * 0.5)
			wrap_angles.append(base_angle - PI * 0.5)
			wrap_angles.append(base_angle + PI * 0.25)
			wrap_angles.append(base_angle - PI * 0.25)
			# Direct approach (same as pile-in — least priority)
			wrap_angles.append(base_angle)

			for try_angle in wrap_angles:
				# Check if this angle is too close to an already-claimed angle
				var angle_taken = false
				var min_angular_gap = (my_radius + 4.0) / b2b_center_dist  # minimum gap in radians
				for claimed in claimed_angles[ekey]:
					var diff = abs(_angle_difference(try_angle, claimed))
					if diff < min_angular_gap:
						angle_taken = true
						break
				if angle_taken:
					continue

				var wrap_pos = target_enemy_pos + Vector2(cos(try_angle), sin(try_angle)) * b2b_center_dist

				# Check movement budget
				if start_pos.distance_to(wrap_pos) > consolidate_range_px:
					continue

				# Must end closer to closest enemy than we started
				if wrap_pos.distance_to(closest_enemy_pos) >= start_pos.distance_to(closest_enemy_pos):
					continue

				# Clamp to board
				wrap_pos.x = clampf(wrap_pos.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
				wrap_pos.y = clampf(wrap_pos.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)

				# Check collision
				if not _pile_in_position_collides(wrap_pos, base_mm, friendly_obstacles, enemy_obstacles, placed_positions, base_type, base_dimensions):
					candidate_pos = wrap_pos
					claimed_angles[ekey].append(try_angle)
					if try_angle != base_angle:
						print("AIDecisionMaker: Consolidate model %s wrapping to far-side angle %.0f°" % [mid, rad_to_deg(try_angle)])
					break

		# Priority 3: Fallback — straight-line movement toward closest enemy (same as pile-in)
		if candidate_pos == Vector2.INF:
			var direction = (target_enemy_pos - start_pos).normalized()
			if direction == Vector2.ZERO:
				direction = Vector2.RIGHT

			var desired_move_dist_px = current_center_dist - b2b_center_dist
			var actual_move_dist_px = clampf(desired_move_dist_px, 0.0, consolidate_range_px)

			if actual_move_dist_px < 1.0:
				placed_positions.append({"position": start_pos, "base_mm": base_mm, "base_type": base_type, "base_dimensions": base_dimensions})
				continue

			candidate_pos = start_pos + direction * actual_move_dist_px
			candidate_pos.x = clampf(candidate_pos.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
			candidate_pos.y = clampf(candidate_pos.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)

			# Check collision with spiral search fallback
			if _pile_in_position_collides(candidate_pos, base_mm, friendly_obstacles, enemy_obstacles, placed_positions, base_type, base_dimensions):
				var found_alt = false
				var step = my_radius * 2.0 + 4.0
				for ring in range(1, 5):
					var ring_radius = step * ring * 0.4
					var points_in_ring = maxi(8, ring * 6)
					for p_idx in range(points_in_ring):
						var angle = (2.0 * PI * p_idx) / points_in_ring
						var test_pos = Vector2(
							candidate_pos.x + cos(angle) * ring_radius,
							candidate_pos.y + sin(angle) * ring_radius
						)
						if start_pos.distance_to(test_pos) > consolidate_range_px:
							continue
						if test_pos.distance_to(closest_enemy_pos) >= start_pos.distance_to(closest_enemy_pos):
							continue
						test_pos.x = clampf(test_pos.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
						test_pos.y = clampf(test_pos.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)
						if not _pile_in_position_collides(test_pos, base_mm, friendly_obstacles, enemy_obstacles, placed_positions, base_type, base_dimensions):
							candidate_pos = test_pos
							found_alt = true
							break
					if found_alt:
						break

				if not found_alt:
					print("AIDecisionMaker: Consolidate model %s collision — holding position" % mid)
					placed_positions.append({"position": start_pos, "base_mm": base_mm, "base_type": base_type, "base_dimensions": base_dimensions})
					continue

		# Final check: must end closer to closest enemy
		if candidate_pos.distance_to(closest_enemy_pos) >= start_pos.distance_to(closest_enemy_pos):
			print("AIDecisionMaker: Consolidate model %s would not end closer to enemy, skipping" % mid)
			placed_positions.append({"position": start_pos, "base_mm": base_mm, "base_type": base_type, "base_dimensions": base_dimensions})
			continue

		# Record the movement
		var model_index = _find_model_index_in_unit(unit, mid)
		if model_index == -1:
			print("AIDecisionMaker: Consolidate model %s index not found, skipping" % mid)
			placed_positions.append({"position": start_pos, "base_mm": base_mm, "base_type": base_type, "base_dimensions": base_dimensions})
			continue

		var move_inches = start_pos.distance_to(candidate_pos) / PIXELS_PER_INCH
		var tag_label = " (tagging new unit)" if is_tagging else ""
		print("AIDecisionMaker: Consolidate model %s (idx %d) moves %.1f\"%s toward enemy" % [mid, model_index, move_inches, tag_label])

		movements[str(model_index)] = candidate_pos
		placed_positions.append({"position": candidate_pos, "base_mm": base_mm, "base_type": base_type, "base_dimensions": base_dimensions})

	return movements

static func _angle_difference(a: float, b: float) -> float:
	"""Return the signed angular difference between two angles, normalized to [-PI, PI]."""
	var diff = fmod(a - b + PI, 2.0 * PI) - PI
	if diff < -PI:
		diff += 2.0 * PI
	return diff

static func _compute_consolidate_movements_objective(snapshot: Dictionary, unit_id: String, unit: Dictionary, player: int) -> Dictionary:
	"""Compute per-model consolidation destinations when moving toward the closest
	objective (fallback mode when no enemy is within engagement reach).
	Returns {model_id_string: Vector2} for models that should move."""
	var movements = {}
	var alive_models = _get_alive_models_with_positions(unit)
	if alive_models.is_empty():
		return movements

	var objectives = _get_objectives(snapshot)
	if objectives.is_empty():
		print("AIDecisionMaker: Consolidate (objective) for %s — no objectives found" % unit_id)
		return movements

	# Get deployed models for collision checking (excluding this unit)
	var deployed_models = _get_deployed_models_excluding_unit(snapshot, unit_id)

	var consolidate_range_px = 3.0 * PIXELS_PER_INCH  # 3" in pixels

	# Track placed positions to avoid intra-unit collisions
	var placed_positions = []

	# Find the closest objective to the unit centroid to use as a consistent target
	var centroid = _get_unit_centroid(unit)
	var target_obj_pos = _nearest_objective_pos(centroid, objectives)
	if target_obj_pos == Vector2.INF:
		return movements

	# Sort models by distance to target objective (furthest first — they benefit most from movement)
	var model_entries = []
	for model in alive_models:
		var mid = model.get("id", "")
		var mpos = _get_model_position(model)
		if mpos == Vector2.INF:
			continue
		var dist_to_obj = mpos.distance_to(target_obj_pos)
		model_entries.append({
			"model": model,
			"id": mid,
			"pos": mpos,
			"dist_to_obj": dist_to_obj,
		})

	# Sort: models closest to objective first (they get priority placement near objective)
	model_entries.sort_custom(func(a, b): return a.dist_to_obj < b.dist_to_obj)

	for entry in model_entries:
		var mid = entry.id
		var start_pos = entry.pos
		var model = entry.model
		var base_mm = model.get("base_mm", 32)
		var base_type = model.get("base_type", "circular")
		var base_dimensions = model.get("base_dimensions", {})
		var my_radius = _model_bounding_radius_px(base_mm, base_type, base_dimensions)

		# Calculate direction toward the target objective
		var direction = (target_obj_pos - start_pos).normalized()
		if direction == Vector2.ZERO:
			# Already exactly on the objective — hold position
			placed_positions.append({
				"position": start_pos,
				"base_mm": base_mm,
				"base_type": base_type,
				"base_dimensions": base_dimensions,
			})
			continue

		# Calculate how far we want to move (up to 3", toward objective)
		var dist_to_target = start_pos.distance_to(target_obj_pos)
		var desired_move_px = minf(dist_to_target, consolidate_range_px)

		# If the model barely needs to move (sub-pixel), skip it
		if desired_move_px < 1.0:
			placed_positions.append({
				"position": start_pos,
				"base_mm": base_mm,
				"base_type": base_type,
				"base_dimensions": base_dimensions,
			})
			continue

		var candidate_pos = start_pos + direction * desired_move_px

		# Clamp to board bounds
		candidate_pos.x = clampf(candidate_pos.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
		candidate_pos.y = clampf(candidate_pos.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)

		# Check collision with deployed models + already placed models from this unit
		var all_obstacles = deployed_models + placed_positions
		if _position_collides_with_deployed(candidate_pos, base_mm, all_obstacles, 2.0, base_type, base_dimensions):
			# Try to find a nearby collision-free position still closer to objective
			var found_alt = false
			var step = my_radius * 2.0 + 4.0
			for ring in range(1, 5):
				var ring_radius = step * ring * 0.4
				var points_in_ring = maxi(8, ring * 6)
				for p_idx in range(points_in_ring):
					var angle = (2.0 * PI * p_idx) / points_in_ring
					var test_pos = Vector2(
						candidate_pos.x + cos(angle) * ring_radius,
						candidate_pos.y + sin(angle) * ring_radius
					)
					# Check move budget
					if start_pos.distance_to(test_pos) > consolidate_range_px:
						continue
					# Must be closer to objective than start
					if test_pos.distance_to(target_obj_pos) >= start_pos.distance_to(target_obj_pos):
						continue
					# Clamp to board
					test_pos.x = clampf(test_pos.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
					test_pos.y = clampf(test_pos.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)
					# Check collision
					if not _position_collides_with_deployed(test_pos, base_mm, all_obstacles, 2.0, base_type, base_dimensions):
						candidate_pos = test_pos
						found_alt = true
						break
				if found_alt:
					break

			if not found_alt:
				# Cannot find collision-free position — hold position
				print("AIDecisionMaker: Consolidate model %s collision — holding position" % mid)
				placed_positions.append({
					"position": start_pos,
					"base_mm": base_mm,
					"base_type": base_type,
					"base_dimensions": base_dimensions,
				})
				continue

		# Verify the model ends closer to the objective than it started
		var new_dist_to_obj = candidate_pos.distance_to(target_obj_pos)
		var old_dist_to_obj = start_pos.distance_to(target_obj_pos)
		if new_dist_to_obj >= old_dist_to_obj:
			# Movement doesn't bring us closer — skip
			print("AIDecisionMaker: Consolidate model %s would not end closer to objective, skipping" % mid)
			placed_positions.append({
				"position": start_pos,
				"base_mm": base_mm,
				"base_type": base_type,
				"base_dimensions": base_dimensions,
			})
			continue

		# Record the movement
		var model_index = _find_model_index_in_unit(unit, mid)
		if model_index == -1:
			print("AIDecisionMaker: Consolidate model %s index not found, skipping" % mid)
			placed_positions.append({
				"position": start_pos,
				"base_mm": base_mm,
				"base_type": base_type,
				"base_dimensions": base_dimensions,
			})
			continue

		var move_inches = start_pos.distance_to(candidate_pos) / PIXELS_PER_INCH
		print("AIDecisionMaker: Consolidate model %s (idx %d) moves %.1f\" toward objective" % [mid, model_index, move_inches])

		movements[str(model_index)] = candidate_pos
		placed_positions.append({
			"position": candidate_pos,
			"base_mm": base_mm,
			"base_type": base_type,
			"base_dimensions": base_dimensions,
		})

	return movements

# =============================================================================
# SCORING PHASE
# =============================================================================

static func _decide_scoring(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	return {"type": "END_SCORING", "_ai_description": "End Turn"}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

static func _get_model_position(model: Dictionary) -> Vector2:
	var pos = model.get("position", null)
	if pos == null:
		return Vector2.INF
	if pos is Vector2:
		return pos
	return Vector2(float(pos.get("x", 0)), float(pos.get("y", 0)))

static func _get_alive_models(unit: Dictionary) -> Array:
	var alive = []
	for model in unit.get("models", []):
		if model.get("alive", true):
			alive.append(model)
	return alive

static func _get_alive_models_with_positions(unit: Dictionary) -> Array:
	var alive = []
	for model in unit.get("models", []):
		if model.get("alive", true) and model.get("position", null) != null:
			alive.append(model)
	return alive

static func _get_alive_model_ids(unit: Dictionary) -> Array:
	"""Return an array of model IDs for all alive models in the unit."""
	var ids = []
	for model in unit.get("models", []):
		if model.get("alive", true):
			ids.append(model.get("id", ""))
	return ids

static func _get_unit_centroid(unit: Dictionary) -> Vector2:
	var alive = _get_alive_models_with_positions(unit)
	if alive.is_empty():
		return Vector2.INF
	var sum_val = Vector2.ZERO
	for model in alive:
		sum_val += _get_model_position(model)
	return sum_val / alive.size()

static func _get_objectives(snapshot: Dictionary) -> Array:
	var objectives = []
	for obj in snapshot.get("board", {}).get("objectives", []):
		var pos = obj.get("position", null)
		if pos:
			if pos is Vector2:
				objectives.append(pos)
			else:
				objectives.append(Vector2(float(pos.get("x", 0)), float(pos.get("y", 0))))
	return objectives

static func _get_units_for_player(snapshot: Dictionary, player: int) -> Dictionary:
	var result = {}
	for unit_id in snapshot.get("units", {}):
		var unit = snapshot.units[unit_id]
		if unit.get("owner", 0) == player:
			result[unit_id] = unit
	return result

static func _get_enemy_units(snapshot: Dictionary, player: int) -> Dictionary:
	var result = {}
	for unit_id in snapshot.get("units", {}):
		var unit = snapshot.units[unit_id]
		if unit.get("owner", 0) != player:
			var status = unit.get("status", 0)
			if status == GameStateData.UnitStatus.UNDEPLOYED or status == GameStateData.UnitStatus.IN_RESERVES:
				continue
			var has_alive = false
			for model in unit.get("models", []):
				if model.get("alive", true):
					has_alive = true
					break
			if has_alive:
				result[unit_id] = unit
	return result

static func _get_deployment_zone_bounds(snapshot: Dictionary, player: int) -> Dictionary:
	var zones = snapshot.get("board", {}).get("deployment_zones", [])
	for zone in zones:
		if zone.get("player", 0) == player:
			var vertices = zone.get("vertices", [])
			if not vertices.is_empty():
				var min_x = INF
				var max_x = -INF
				var min_y = INF
				var max_y = -INF
				for v in vertices:
					var vx: float
					var vy: float
					if v is Vector2:
						vx = v.x
						vy = v.y
					else:
						vx = float(v.get("x", 0))
						vy = float(v.get("y", 0))
					min_x = min(min_x, vx)
					max_x = max(max_x, vx)
					min_y = min(min_y, vy)
					max_y = max(max_y, vy)
				return {"min_x": min_x, "max_x": max_x, "min_y": min_y, "max_y": max_y}

	# Fallback: standard Hammer and Anvil zones
	if player == 1:
		return {"min_x": 40.0, "max_x": 1720.0, "min_y": 10.0, "max_y": 470.0}
	else:
		return {"min_x": 40.0, "max_x": 1720.0, "min_y": 1930.0, "max_y": 2390.0}

static func _generate_formation_positions(centroid: Vector2, num_models: int,
										base_mm: int, zone_bounds: Dictionary) -> Array:
	var positions = []
	var base_radius_px = (base_mm / 2.0) * (PIXELS_PER_INCH / 25.4)
	var spacing = base_radius_px * 2.0 + 10.0  # Base diameter + small gap

	var cols = mini(5, num_models)
	var rows = ceili(float(num_models) / cols)

	var start_x = centroid.x - (cols - 1) * spacing / 2.0
	var start_y = centroid.y - (rows - 1) * spacing / 2.0

	for i in range(num_models):
		var row = i / cols
		var col = i % cols
		var pos = Vector2(start_x + col * spacing, start_y + row * spacing)

		# Clamp to zone bounds with margin
		var margin = base_radius_px + 5.0
		pos.x = clamp(pos.x, zone_bounds.get("min_x", margin) + margin,
					zone_bounds.get("max_x", BOARD_WIDTH_PX - margin) - margin)
		pos.y = clamp(pos.y, zone_bounds.get("min_y", margin) + margin,
					zone_bounds.get("max_y", BOARD_HEIGHT_PX - margin) - margin)

		positions.append(pos)

	return positions

# --- Collision detection utilities for deployment ---

static func _get_all_deployed_model_positions(snapshot: Dictionary) -> Array:
	"""Returns array of {position: Vector2, base_mm: int, base_type: String, base_dimensions: Dictionary}
	for every deployed model on the board."""
	var deployed = []
	for unit_id in snapshot.get("units", {}):
		var unit = snapshot.units[unit_id]
		if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
			continue
		for model in unit.get("models", []):
			if not model.get("alive", true):
				continue
			var pos_data = model.get("position", null)
			if pos_data == null:
				continue
			var pos: Vector2
			if pos_data is Vector2:
				pos = pos_data
			else:
				pos = Vector2(float(pos_data.get("x", 0)), float(pos_data.get("y", 0)))
			deployed.append({
				"position": pos,
				"base_mm": model.get("base_mm", 32),
				"base_type": model.get("base_type", "circular"),
				"base_dimensions": model.get("base_dimensions", {}),
				"rotation": model.get("rotation", 0.0)
			})
	return deployed

static func _model_bounding_radius_px(base_mm: int, base_type: String = "circular", base_dimensions: Dictionary = {}) -> float:
	"""Returns conservative bounding circle radius in pixels for any base type."""
	var mm_to_px = PIXELS_PER_INCH / 25.4
	match base_type:
		"circular":
			return (base_mm / 2.0) * mm_to_px
		"rectangular", "oval":
			var length_mm = base_dimensions.get("length", base_mm)
			var width_mm = base_dimensions.get("width", base_mm * 0.6)
			# Bounding circle = half the diagonal
			var diag_mm = sqrt(length_mm * length_mm + width_mm * width_mm)
			return (diag_mm / 2.0) * mm_to_px
		_:
			return (base_mm / 2.0) * mm_to_px

static func _position_collides_with_deployed(pos: Vector2, base_mm: int, deployed_models: Array, min_gap_px: float = 4.0, base_type: String = "circular", base_dimensions: Dictionary = {}) -> bool:
	"""Check if a position would collide with any deployed model using bounding-circle approximation."""
	var my_radius = _model_bounding_radius_px(base_mm, base_type, base_dimensions)
	for dm in deployed_models:
		var other_radius = _model_bounding_radius_px(
			dm.get("base_mm", 32),
			dm.get("base_type", "circular"),
			dm.get("base_dimensions", {})
		)
		var min_dist = my_radius + other_radius + min_gap_px
		if pos.distance_to(dm.position) < min_dist:
			return true
	return false

static func _resolve_formation_collisions(positions: Array, base_mm: int, deployed_models: Array, zone_bounds: Dictionary, base_type: String = "circular", base_dimensions: Dictionary = {}) -> Array:
	"""For each position that collides, spiral-search for the nearest free spot.
	Also prevents intra-formation overlap."""
	var resolved = []
	# Track positions we've already placed in this formation
	var formation_placed: Array = []  # Array of {position, base_mm, base_type, base_dimensions}
	var mm_to_px = PIXELS_PER_INCH / 25.4
	var my_radius = _model_bounding_radius_px(base_mm, base_type, base_dimensions)
	var margin = my_radius + 5.0
	var step = my_radius * 2.0 + 8.0  # Spiral step size

	for pos in positions:
		# Combine deployed models + already-placed formation models for collision
		var all_obstacles = deployed_models + formation_placed

		if not _position_collides_with_deployed(pos, base_mm, all_obstacles, 4.0, base_type, base_dimensions):
			# No collision, use as-is
			resolved.append(pos)
			formation_placed.append({
				"position": pos,
				"base_mm": base_mm,
				"base_type": base_type,
				"base_dimensions": base_dimensions
			})
			continue

		# Spiral search for a free spot
		var found = false
		for ring in range(1, 8):  # Up to 7 rings outward
			var ring_radius = step * ring
			var points_in_ring = maxi(8, ring * 8)
			for p_idx in range(points_in_ring):
				var angle = (2.0 * PI * p_idx) / points_in_ring
				var candidate = Vector2(
					pos.x + cos(angle) * ring_radius,
					pos.y + sin(angle) * ring_radius
				)
				# Clamp to zone bounds
				candidate.x = clamp(candidate.x, zone_bounds.get("min_x", margin) + margin, zone_bounds.get("max_x", BOARD_WIDTH_PX - margin) - margin)
				candidate.y = clamp(candidate.y, zone_bounds.get("min_y", margin) + margin, zone_bounds.get("max_y", BOARD_HEIGHT_PX - margin) - margin)

				if not _position_collides_with_deployed(candidate, base_mm, all_obstacles, 4.0, base_type, base_dimensions):
					resolved.append(candidate)
					formation_placed.append({
						"position": candidate,
						"base_mm": base_mm,
						"base_type": base_type,
						"base_dimensions": base_dimensions
					})
					found = true
					break
			if found:
				break

		if not found:
			# Last resort: use original position (will likely fail validation, but retry logic will handle it)
			print("AIDecisionMaker: WARNING - Could not find collision-free position for model, using original")
			resolved.append(pos)
			formation_placed.append({
				"position": pos,
				"base_mm": base_mm,
				"base_type": base_type,
				"base_dimensions": base_dimensions
			})

	return resolved

static func _generate_weapon_id(weapon_name: String, weapon_type: String = "") -> String:
	var weapon_id = weapon_name.to_lower()
	weapon_id = weapon_id.replace(" ", "_")
	weapon_id = weapon_id.replace("-", "_")
	weapon_id = weapon_id.replace("–", "_")
	weapon_id = weapon_id.replace("'", "")
	# Append weapon type suffix to prevent collisions between ranged/melee variants
	if weapon_type != "":
		weapon_id += "_" + weapon_type.to_lower()
	return weapon_id

# =============================================================================
# SCORING FUNCTIONS
# =============================================================================

static func _wound_probability(strength: int, toughness: int) -> float:
	if strength >= toughness * 2:
		return 5.0 / 6.0  # 2+
	elif strength > toughness:
		return 4.0 / 6.0  # 3+
	elif strength == toughness:
		return 3.0 / 6.0  # 4+
	elif strength * 2 <= toughness:
		return 1.0 / 6.0  # 6+
	else:
		return 2.0 / 6.0  # 5+

static func _hit_probability(skill: int) -> float:
	if skill <= 1:
		return 1.0
	if skill >= 7:
		return 0.0
	return (7.0 - skill) / 6.0

static func _save_probability(save_val: int, ap: int, invuln: int = 0) -> float:
	var modified_save = save_val + abs(ap)
	# If the target has an invulnerable save, use whichever is better (lower)
	# Invulnerable saves ignore AP, so they are compared against the AP-modified armour save
	if invuln > 0 and invuln < modified_save:
		modified_save = invuln
	if modified_save >= 7:
		return 0.0
	if modified_save <= 1:
		return 1.0
	return (7.0 - modified_save) / 6.0

static func _get_target_invulnerable_save(target_unit: Dictionary) -> int:
	"""Get the best (lowest) invulnerable save for a target unit.
	Checks model-level invuln, unit-level meta.stats.invuln, and effect-granted invuln."""
	var best_invuln: int = 0

	# Check first alive model for native invulnerable save
	var models = target_unit.get("models", [])
	for model in models:
		if model.get("alive", true):
			var model_invuln = model.get("invuln", 0)
			if typeof(model_invuln) == TYPE_STRING:
				model_invuln = int(model_invuln) if model_invuln.is_valid_int() else 0
			if model_invuln > 0:
				best_invuln = model_invuln
			break

	# Check unit-level invuln in meta stats (fallback if models don't have it)
	if best_invuln == 0:
		var stats_invuln = target_unit.get("meta", {}).get("stats", {}).get("invuln", 0)
		if typeof(stats_invuln) == TYPE_STRING:
			stats_invuln = int(stats_invuln) if stats_invuln.is_valid_int() else 0
		if stats_invuln > 0:
			best_invuln = stats_invuln

	# Check effect-granted invulnerable save (e.g. Go to Ground stratagem)
	var effect_invuln = EffectPrimitivesData.get_effect_invuln(target_unit)
	if effect_invuln > 0:
		if best_invuln == 0 or effect_invuln < best_invuln:
			best_invuln = effect_invuln

	return best_invuln

# =============================================================================
# COVER CONSIDERATION IN TARGET SCORING (T7-31 / SHOOT-7)
# =============================================================================
# Benefit of Cover gives +1 to armour saving throws (but not invulnerable saves).
# This makes covered targets harder to damage. Weapons with "Ignores Cover"
# negate this bonus entirely.

# Terrain types that grant Benefit of Cover (mirrors RulesEngine constants)
const COVER_TERRAIN_WITHIN_AND_BEHIND = ["ruins", "obstacle", "barricade"]
const COVER_TERRAIN_WITHIN_ONLY = ["woods", "crater", "area_terrain", "forest"]

static func _target_has_benefit_of_cover(target_unit: Dictionary, shooter_unit: Dictionary, snapshot: Dictionary) -> bool:
	"""Check if target unit has Benefit of Cover from the shooter's perspective.
	Checks both terrain-based cover and effect-granted cover (e.g. Go to Ground)."""
	# Effect-granted cover (stratagems like Go to Ground, Smokescreen)
	if EffectPrimitivesData.has_effect_cover(target_unit):
		return true

	# Flag-based cover (may be set by game logic)
	if target_unit.get("flags", {}).get("in_cover", false):
		return true

	# Terrain-based cover: need positions and board data
	if shooter_unit.is_empty():
		return false

	var board = snapshot.get("board", {})
	var terrain_features = board.get("terrain_features", [])
	if terrain_features.is_empty():
		return false

	var shooter_centroid = _get_unit_centroid(shooter_unit)
	if shooter_centroid == Vector2.INF:
		return false

	# Check if majority of alive target models have cover (same as RulesEngine logic)
	var models_in_cover = 0
	var total_alive = 0

	for model in target_unit.get("models", []):
		if not model.get("alive", true):
			continue
		total_alive += 1
		var model_pos = _get_model_position(model)
		if model_pos == Vector2.ZERO:
			continue

		if _check_position_has_terrain_cover(model_pos, shooter_centroid, terrain_features):
			models_in_cover += 1

	if total_alive == 0:
		return false

	# Unit has cover if majority of models are in cover
	return models_in_cover > (total_alive / 2.0)

static func _check_position_has_terrain_cover(target_pos: Vector2, shooter_pos: Vector2, terrain_features: Array) -> bool:
	"""Check if a target position has Benefit of Cover from terrain relative to shooter."""
	for terrain_piece in terrain_features:
		var terrain_type = terrain_piece.get("type", "")
		var polygon = terrain_piece.get("polygon", PackedVector2Array())
		if polygon is Array:
			var packed = PackedVector2Array()
			for p in polygon:
				if p is Vector2:
					packed.append(p)
				elif p is Dictionary:
					packed.append(Vector2(float(p.get("x", 0)), float(p.get("y", 0))))
			polygon = packed
		if polygon.size() < 3:
			continue

		# Ruins, obstacles, barricades: cover when target is within OR behind (LoS crosses terrain)
		if terrain_type in COVER_TERRAIN_WITHIN_AND_BEHIND:
			if Geometry2D.is_point_in_polygon(target_pos, polygon):
				return true
			# Target behind terrain (LoS from shooter crosses terrain, shooter not inside)
			if _line_intersects_polygon(shooter_pos, target_pos, polygon):
				if not Geometry2D.is_point_in_polygon(shooter_pos, polygon):
					return true

		# Area terrain (woods, craters): cover only when target is within
		elif terrain_type in COVER_TERRAIN_WITHIN_ONLY:
			if Geometry2D.is_point_in_polygon(target_pos, polygon):
				return true

	return false

static func _weapon_ignores_cover(weapon: Dictionary, shooter_unit: Dictionary = {}) -> bool:
	"""Check if a weapon ignores Benefit of Cover via special rules or effect flags."""
	var special_rules = weapon.get("special_rules", "").to_lower()
	if "ignores cover" in special_rules:
		return true
	# Check effect-granted Ignores Cover on the shooter unit
	if not shooter_unit.is_empty() and EffectPrimitivesData.has_effect_ignores_cover(shooter_unit):
		return true
	return false

# =============================================================================
# WEAPON KEYWORD AWARENESS (SHOOT-5)
# =============================================================================
# Adjusts expected damage calculation to account for weapon special rules:
# Blast, Rapid Fire, Melta, Anti-keyword, Torrent, Sustained Hits,
# Lethal Hits, and Devastating Wounds.
# Returns a Dictionary with adjusted values:
#   {attacks, p_hit, p_wound, p_unsaved, damage}

static func _apply_weapon_keyword_modifiers(
	weapon: Dictionary, target_unit: Dictionary,
	base_attacks: float, base_p_hit: float, base_p_wound: float,
	base_p_unsaved: float, base_damage: float,
	strength: int, toughness: int,
	target_save: int, ap: int, target_invuln: int,
	dist_inches: float, weapon_range_inches: float
) -> Dictionary:
	"""
	Apply weapon keyword modifiers to the base expected-damage components.
	All adjustments are applied as mathematical expectation modifiers
	so the AI can compare weapons fairly.
	"""
	var attacks = base_attacks
	var p_hit = base_p_hit
	var p_wound = base_p_wound
	var p_unsaved = base_p_unsaved
	var damage = base_damage
	var special_rules = weapon.get("special_rules", "").to_lower()

	# --- TORRENT: auto-hit, p_hit = 1.0 ---
	if "torrent" in special_rules:
		p_hit = 1.0

	# --- BLAST: +1 attack per 5 models in target unit (10th ed) ---
	if "blast" in special_rules:
		var alive_models = _get_alive_models(target_unit).size()
		var blast_bonus = int(alive_models / 5)
		if blast_bonus > 0:
			attacks += float(blast_bonus)

	# --- RAPID FIRE X: bonus attacks at half range ---
	var rapid_fire_val = _parse_rapid_fire_value(special_rules)
	if rapid_fire_val > 0:
		var at_half_range = _is_within_half_range(dist_inches, weapon_range_inches)
		if at_half_range == 1:
			# Definitely within half range
			attacks += float(rapid_fire_val)
		elif at_half_range == -1:
			# Definitely not within half range — no bonus
			pass
		else:
			# Unknown distance — use expected value (probability-weighted)
			attacks += float(rapid_fire_val) * HALF_RANGE_FALLBACK_PROB

	# --- MELTA X: bonus damage at half range ---
	var melta_val = _parse_melta_value(special_rules)
	if melta_val > 0:
		var at_half_range = _is_within_half_range(dist_inches, weapon_range_inches)
		if at_half_range == 1:
			damage += float(melta_val)
		elif at_half_range == -1:
			pass
		else:
			damage += float(melta_val) * HALF_RANGE_FALLBACK_PROB

	# --- ANTI-KEYWORD X+: improved wound probability vs matching targets ---
	var anti_data = _parse_anti_keyword_data(special_rules)
	var target_keywords = target_unit.get("meta", {}).get("keywords", [])
	for entry in anti_data:
		var anti_kw = entry["keyword"]  # e.g. "INFANTRY"
		var threshold = entry["threshold"]  # e.g. 4
		for tkw in target_keywords:
			if tkw.to_upper() == anti_kw:
				# Anti-keyword: critical wounds on threshold+ instead of just 6+
				# The wound probability becomes: normal wounds on non-crit + auto-wound on anti-crit
				# p_wound_anti = (1 - p_crit_anti) * base_p_wound + p_crit_anti * 1.0
				# where p_crit_anti = (7 - threshold) / 6
				var p_crit_anti = (7.0 - threshold) / 6.0
				var new_p_wound = (1.0 - p_crit_anti) * p_wound + p_crit_anti
				if new_p_wound > p_wound:
					p_wound = new_p_wound
				break  # Only apply the best matching anti-keyword

	# --- SUSTAINED HITS X: extra hits on critical hit rolls (6s) ---
	var sustained_val = _parse_sustained_hits_value(special_rules)
	if sustained_val > 0.0:
		# On a critical hit (1/6 chance per hit roll), gain sustained_val extra hits.
		# Expected extra hits per attack = CRIT_PROBABILITY * sustained_val
		# These extra hits still need to wound and get past saves.
		# Effective attack multiplier: attacks * (1 + CRIT_PROBABILITY * sustained_val * p_hit_share)
		# But since these are additional hits (not attacks), and p_hit is already factored:
		# Total effective hits = attacks * p_hit + attacks * CRIT_PROBABILITY * sustained_val
		# (critical hits are a subset of p_hit, but they generate EXTRA hits)
		# Simplification: multiply attacks by (1 + CRIT_PROBABILITY * sustained_val / p_hit) if p_hit > 0
		# More precisely: effective_hits = attacks * p_hit * (1 + CRIT_PROBABILITY / p_hit * sustained_val)
		#               = attacks * (p_hit + CRIT_PROBABILITY * sustained_val)
		# We model this as an attack multiplier so it flows through the rest of the pipeline.
		if p_hit > 0:
			var hit_multiplier = (p_hit + CRIT_PROBABILITY * sustained_val) / p_hit
			attacks *= hit_multiplier

	# --- LETHAL HITS: critical hits (6s) auto-wound ---
	if "lethal hits" in special_rules:
		# On a 6 to hit, the attack auto-wounds (skips wound roll).
		# Expected contribution from lethal hits per attack:
		#   CRIT_PROBABILITY * p_unsaved * damage (they auto-wound, so p_wound=1 for these)
		# Non-lethal hits contribute:
		#   (p_hit - CRIT_PROBABILITY) * p_wound * p_unsaved * damage
		# Total expected damage per attack:
		#   CRIT_PROBABILITY * 1.0 * p_unsaved * damage + (p_hit - CRIT_PROBABILITY) * p_wound * p_unsaved * damage
		# = p_unsaved * damage * (CRIT_PROBABILITY + (p_hit - CRIT_PROBABILITY) * p_wound)
		# We model this by adjusting p_wound to an effective value:
		if p_hit > 0:
			var effective_p_wound = (CRIT_PROBABILITY + (p_hit - CRIT_PROBABILITY) * p_wound) / p_hit
			p_wound = effective_p_wound

	# --- DEVASTATING WOUNDS: critical wounds (6s) bypass saves ---
	if "devastating wounds" in special_rules:
		# On an unmodified 6 to wound, the attack bypasses saves entirely (mortal wound).
		# Expected contribution from devastating wounds per wound:
		#   CRIT_PROBABILITY * 1.0 * damage (p_unsaved = 1.0 for these)
		# Non-devastating wounds contribute:
		#   (p_wound - CRIT_PROBABILITY) * p_unsaved * damage
		# Total = damage * (CRIT_PROBABILITY + (p_wound - CRIT_PROBABILITY) * p_unsaved)
		# Model by adjusting p_unsaved to an effective value:
		if p_wound > 0:
			var effective_p_unsaved = (CRIT_PROBABILITY + (p_wound - CRIT_PROBABILITY) * p_unsaved) / p_wound
			p_unsaved = effective_p_unsaved

	return {
		"attacks": attacks,
		"p_hit": p_hit,
		"p_wound": p_wound,
		"p_unsaved": p_unsaved,
		"damage": damage
	}

static func _is_within_half_range(dist_inches: float, weapon_range_inches: float) -> int:
	"""
	Determine if a target is within half range of a weapon.
	Returns: 1 = definitely within half range, -1 = definitely not, 0 = unknown.
	"""
	if dist_inches <= 0.0 or weapon_range_inches <= 0.0:
		return 0  # Can't determine — use fallback
	var half_range = weapon_range_inches / 2.0
	if dist_inches <= half_range:
		return 1
	else:
		return -1

static func _parse_rapid_fire_value(special_rules_lower: String) -> int:
	"""Parse 'rapid fire X' from lowercased special_rules string. Returns 0 if not found."""
	var regex = RegEx.new()
	regex.compile("rapid\\s*fire\\s*(\\d+)")
	var result = regex.search(special_rules_lower)
	if result:
		return result.get_string(1).to_int()
	return 0

static func _parse_melta_value(special_rules_lower: String) -> int:
	"""Parse 'melta X' from lowercased special_rules string. Returns 0 if not found."""
	var regex = RegEx.new()
	regex.compile("melta\\s*(\\d+)")
	var result = regex.search(special_rules_lower)
	if result:
		return result.get_string(1).to_int()
	return 0

static func _parse_anti_keyword_data(special_rules_lower: String) -> Array:
	"""Parse 'anti-X Y+' patterns from lowercased special_rules string.
	Returns Array of {keyword: String (UPPERCASE), threshold: int}."""
	var results = []
	var regex = RegEx.new()
	regex.compile("anti-(\\w+)\\s+(\\d+)\\+?")
	var matches = regex.search_all(special_rules_lower)
	for m in matches:
		results.append({
			"keyword": m.get_string(1).to_upper(),
			"threshold": m.get_string(2).to_int()
		})
	return results

static func _parse_sustained_hits_value(special_rules_lower: String) -> float:
	"""Parse 'sustained hits X' or 'sustained hits dX' from lowercased special_rules string.
	Returns the expected number of bonus hits per critical (0 if not found).
	For 'sustained hits D3', returns average of D3 = 2.0.
	For 'sustained hits D6', returns average of D6 = 3.5."""
	var regex = RegEx.new()
	regex.compile("sustained\\s*hits\\s*(d?)(\\d+)")
	var result = regex.search(special_rules_lower)
	if result:
		var is_dice = result.get_string(1) == "d"
		var val = result.get_string(2).to_int()
		if is_dice:
			# Average of dX = (X+1)/2
			if val == 3:
				return 2.0
			elif val == 6:
				return 3.5
			else:
				return (float(val) + 1.0) / 2.0
		else:
			return float(val)
	return 0.0

static func _score_shooting_target(weapon: Dictionary, target_unit: Dictionary, snapshot: Dictionary, shooter_unit: Dictionary = {}) -> float:
	# --- Range check: score 0 for out-of-range targets ---
	var weapon_range_inches = _get_weapon_range_inches(weapon)
	var dist_inches: float = -1.0  # -1 means unknown distance
	if weapon_range_inches > 0.0 and not shooter_unit.is_empty():
		dist_inches = _get_closest_model_distance_inches(shooter_unit, target_unit)
		if dist_inches > weapon_range_inches:
			return 0.0

	var attacks_str = weapon.get("attacks", "1")
	var attacks = float(attacks_str) if attacks_str.is_valid_float() else 1.0

	var bs_str = weapon.get("ballistic_skill", "4")
	var bs = int(bs_str) if bs_str.is_valid_int() else 4

	var strength_str = weapon.get("strength", "4")
	var strength = int(strength_str) if strength_str.is_valid_int() else 4

	var ap_str = weapon.get("ap", "0")
	var ap = 0
	if ap_str.begins_with("-"):
		var ap_num = ap_str.substr(1)
		ap = int(ap_num) if ap_num.is_valid_int() else 0
	else:
		ap = int(ap_str) if ap_str.is_valid_int() else 0

	var damage_str = weapon.get("damage", "1")
	var damage = float(damage_str) if damage_str.is_valid_float() else 1.0

	var toughness = target_unit.get("meta", {}).get("stats", {}).get("toughness", 4)
	var target_save = target_unit.get("meta", {}).get("stats", {}).get("save", 4)
	var target_invuln = _get_target_invulnerable_save(target_unit)

	# --- T7-31: Apply Benefit of Cover (+1 to armour save) ---
	var effective_save = target_save
	if _target_has_benefit_of_cover(target_unit, shooter_unit, snapshot) and not _weapon_ignores_cover(weapon, shooter_unit):
		effective_save = max(2, target_save - 1)  # Cover improves armour save by 1 (min 2+)
		print("AIDecisionMaker: Target has cover, effective save %d+ -> %d+" % [target_save, effective_save])

	var p_hit = _hit_probability(bs)
	var p_wound = _wound_probability(strength, toughness)
	var p_unsaved = 1.0 - _save_probability(effective_save, ap, target_invuln)

	# --- Apply weapon keyword modifiers (SHOOT-5) ---
	var kw_mods = _apply_weapon_keyword_modifiers(
		weapon, target_unit,
		attacks, p_hit, p_wound, p_unsaved, damage,
		strength, toughness, target_save, ap, target_invuln,
		dist_inches, weapon_range_inches
	)
	attacks = kw_mods["attacks"]
	p_hit = kw_mods["p_hit"]
	p_wound = kw_mods["p_wound"]
	p_unsaved = kw_mods["p_unsaved"]
	damage = kw_mods["damage"]

	# --- T7-6: Wound overflow cap ---
	# Damage exceeding model wounds is lost in 40k. Cap for accurate scoring.
	var wounds_per_model = _get_target_wounds_per_model(target_unit)
	if wounds_per_model > 0:
		damage = min(damage, float(wounds_per_model))

	var expected_damage = attacks * p_hit * p_wound * p_unsaved * damage

	# --- AI-GAP-4: Factor in target FNP for more accurate scoring ---
	var target_fnp = AIAbilityAnalyzerData.get_unit_fnp(target_unit)
	if target_fnp > 0:
		var fnp_multiplier = AIAbilityAnalyzerData.get_fnp_damage_multiplier(target_fnp)
		expected_damage *= fnp_multiplier

	# --- AI-GAP-4: Factor in target Stealth for ranged hit penalty ---
	if AIAbilityAnalyzerData.has_stealth(target_unit):
		# Stealth imposes -1 to hit for ranged attacks; approximate as ~15% reduction
		expected_damage *= 0.85

	# Bonus: target below half strength (finish it off)
	var alive_count = _get_alive_models(target_unit).size()
	var total_count = target_unit.get("models", []).size()
	if total_count > 0 and alive_count * 2 < total_count:
		expected_damage *= 1.5

	# Bonus: target has CHARACTER keyword
	var keywords = target_unit.get("meta", {}).get("keywords", [])
	if "CHARACTER" in keywords:
		expected_damage *= 1.2

	# Apply weapon-target efficiency multiplier
	var efficiency = _calculate_efficiency_multiplier(weapon, target_unit)
	expected_damage *= efficiency

	return expected_damage

# =============================================================================
# WEAPON-TARGET EFFICIENCY MATCHING
# =============================================================================

enum WeaponRole { ANTI_TANK, ANTI_INFANTRY, GENERAL_PURPOSE }
enum TargetType { VEHICLE_MONSTER, ELITE, HORDE }

static func _classify_weapon_role(weapon: Dictionary) -> int:
	"""
	Classify a weapon as anti-tank, anti-infantry, or general purpose based on
	its strength, AP, damage, and special rules.
	"""
	var strength_str = weapon.get("strength", "4")
	var strength = int(strength_str) if strength_str.is_valid_int() else 4

	var ap_str = weapon.get("ap", "0")
	var ap = 0
	if ap_str.begins_with("-"):
		var ap_num = ap_str.substr(1)
		ap = int(ap_num) if ap_num.is_valid_int() else 0
	else:
		ap = int(ap_str) if ap_str.is_valid_int() else 0

	var damage_str = weapon.get("damage", "1")
	# Handle variable damage like "D6", "D3+1", "D6+1"
	var damage = _parse_average_damage(damage_str)

	var special_rules = weapon.get("special_rules", "").to_lower()

	# Check for anti-keyword special rules first — they are the strongest indicator
	if _has_anti_vehicle_rule(special_rules):
		return WeaponRole.ANTI_TANK
	if _has_anti_infantry_rule(special_rules):
		return WeaponRole.ANTI_INFANTRY

	# Score weapon characteristics for anti-tank role
	var anti_tank_score = 0
	if strength >= ANTI_TANK_STRENGTH_THRESHOLD:
		anti_tank_score += 2
	if ap >= ANTI_TANK_AP_THRESHOLD:
		anti_tank_score += 1
	if damage >= ANTI_TANK_DAMAGE_THRESHOLD:
		anti_tank_score += 2

	# Score weapon characteristics for anti-infantry role
	var anti_infantry_score = 0
	if strength <= ANTI_INFANTRY_STRENGTH_CAP:
		anti_infantry_score += 1
	if damage <= ANTI_INFANTRY_DAMAGE_THRESHOLD:
		anti_infantry_score += 2
	if ap <= 1:
		anti_infantry_score += 1

	# Check attacks count: high attacks with low damage is anti-infantry
	var attacks_str = weapon.get("attacks", "1")
	var attacks = float(attacks_str) if attacks_str.is_valid_float() else 1.0
	if attacks >= 4 and damage <= 1.5:
		anti_infantry_score += 1

	# Blast weapons lean anti-infantry (more attacks vs larger units)
	if "blast" in special_rules:
		anti_infantry_score += 1

	# Torrent weapons are inherently anti-infantry (auto-hit, usually S4-5 D1)
	if "torrent" in special_rules:
		anti_infantry_score += 1

	# Classify based on scores
	if anti_tank_score >= 3:
		return WeaponRole.ANTI_TANK
	if anti_infantry_score >= 3:
		return WeaponRole.ANTI_INFANTRY

	return WeaponRole.GENERAL_PURPOSE

static func _classify_target_type(target_unit: Dictionary) -> int:
	"""
	Classify a target unit as vehicle/monster, elite, or horde based on
	keywords, wounds per model, and model count.
	"""
	var keywords = target_unit.get("meta", {}).get("keywords", [])
	var stats = target_unit.get("meta", {}).get("stats", {})
	var wounds_per_model = int(stats.get("wounds", 1))
	var toughness = int(stats.get("toughness", 4))
	var alive_models = _get_alive_models(target_unit)
	var model_count = alive_models.size()

	# VEHICLE or MONSTER keyword is the strongest indicator
	for kw in keywords:
		var kw_upper = kw.to_upper()
		if kw_upper == "VEHICLE" or kw_upper == "MONSTER":
			return TargetType.VEHICLE_MONSTER

	# High toughness + high wounds without explicit keyword (e.g. some big characters)
	if toughness >= 8 and wounds_per_model >= 8:
		return TargetType.VEHICLE_MONSTER

	# Horde: many models with low wounds
	if model_count >= 5 and wounds_per_model <= 1:
		return TargetType.HORDE

	# Large infantry squads with 2W are still horde-like
	if model_count >= 8 and wounds_per_model <= 2:
		return TargetType.HORDE

	# Elite: fewer, tougher models (multi-wound infantry, small squads)
	if wounds_per_model >= 2:
		return TargetType.ELITE

	# Default: small infantry squads — treat as horde-adjacent
	return TargetType.HORDE

static func _calculate_efficiency_multiplier(weapon: Dictionary, target_unit: Dictionary) -> float:
	"""
	Calculate an efficiency multiplier for matching a weapon to a target.
	Considers weapon role vs target type, damage waste on low-wound models,
	and anti-keyword special rules.
	"""
	var weapon_role = _classify_weapon_role(weapon)
	var target_type = _classify_target_type(target_unit)
	var multiplier = EFFICIENCY_NEUTRAL

	# --- Role-based matching ---
	match weapon_role:
		WeaponRole.ANTI_TANK:
			match target_type:
				TargetType.VEHICLE_MONSTER:
					multiplier = EFFICIENCY_PERFECT_MATCH
				TargetType.ELITE:
					multiplier = EFFICIENCY_GOOD_MATCH
				TargetType.HORDE:
					multiplier = EFFICIENCY_POOR_MATCH
		WeaponRole.ANTI_INFANTRY:
			match target_type:
				TargetType.HORDE:
					multiplier = EFFICIENCY_PERFECT_MATCH
				TargetType.ELITE:
					multiplier = EFFICIENCY_GOOD_MATCH
				TargetType.VEHICLE_MONSTER:
					multiplier = EFFICIENCY_POOR_MATCH
		WeaponRole.GENERAL_PURPOSE:
			multiplier = EFFICIENCY_NEUTRAL

	# --- T7-7: Damage waste penalty for multi-damage weapons on single-wound models ---
	# When a weapon's average damage exceeds 1 against single-wound targets, the
	# excess damage is wasted (each unsaved wound can only remove 1 model).
	# Wound overflow capping in _estimate_weapon_damage() handles damage ACCURACY;
	# this penalty captures the OPPORTUNITY COST — the weapon could be more effective
	# against a higher-wound target. Uses DAMAGE_WASTE_PENALTY constants.
	var avg_damage = _parse_average_damage(weapon.get("damage", "1"))
	var wpm = float(_get_target_wounds_per_model(target_unit))
	if wpm <= 1.0 and avg_damage > 1.0:
		if avg_damage >= ANTI_TANK_DAMAGE_THRESHOLD:  # D3+ avg damage (heavy waste)
			multiplier *= DAMAGE_WASTE_PENALTY_HEAVY
		else:  # D2 (moderate waste)
			multiplier *= DAMAGE_WASTE_PENALTY_MODERATE

	# --- Anti-keyword bonus ---
	var special_rules = weapon.get("special_rules", "").to_lower()
	var keywords = target_unit.get("meta", {}).get("keywords", [])

	if _weapon_anti_keyword_matches_target(special_rules, keywords):
		multiplier *= ANTI_KEYWORD_BONUS

	return multiplier

static func _get_target_wounds_per_model(target_unit: Dictionary) -> int:
	"""Get the wounds characteristic of models in the target unit."""
	var stats = target_unit.get("meta", {}).get("stats", {})
	return int(stats.get("wounds", 1))

static func _parse_average_damage(damage_str: String) -> float:
	"""
	Parse a damage string and return the average expected damage.
	Handles: "1", "2", "D3", "D6", "D3+1", "D6+1", "2D6", etc.
	"""
	if damage_str.is_valid_float():
		return float(damage_str)
	if damage_str.is_valid_int():
		return float(damage_str)

	var lower = damage_str.to_lower().strip_edges()

	# Handle "D3+N" or "D6+N" patterns
	var plus_parts = lower.split("+")
	var base_damage = 0.0
	var bonus = 0.0

	if plus_parts.size() >= 2:
		var bonus_str = plus_parts[1].strip_edges()
		bonus = float(bonus_str) if bonus_str.is_valid_float() else 0.0

	var base_str = plus_parts[0].strip_edges()

	# Handle "2D6", "2D3" etc.
	var multiplier_val = 1.0
	if base_str.find("d") > 0:
		var d_parts = base_str.split("d")
		if d_parts.size() == 2:
			var mult_str = d_parts[0].strip_edges()
			multiplier_val = float(mult_str) if mult_str.is_valid_float() else 1.0
			var die_str = d_parts[1].strip_edges()
			if die_str == "3":
				base_damage = 2.0  # Average of D3 = 2
			elif die_str == "6":
				base_damage = 3.5  # Average of D6 = 3.5
			else:
				base_damage = (float(die_str) + 1.0) / 2.0 if die_str.is_valid_float() else 1.0
	elif base_str == "d3":
		base_damage = 2.0
	elif base_str == "d6":
		base_damage = 3.5
	else:
		base_damage = float(base_str) if base_str.is_valid_float() else 1.0

	return base_damage * multiplier_val + bonus

static func _has_anti_vehicle_rule(special_rules: String) -> bool:
	"""Check if weapon special rules contain anti-vehicle or anti-monster."""
	return "anti-vehicle" in special_rules or "anti-monster" in special_rules

static func _has_anti_infantry_rule(special_rules: String) -> bool:
	"""Check if weapon special rules contain anti-infantry."""
	return "anti-infantry" in special_rules

static func _weapon_anti_keyword_matches_target(special_rules: String, target_keywords: Array) -> bool:
	"""
	Check if a weapon's anti-X keyword matches a target's keywords.
	e.g. anti-infantry 4+ matches INFANTRY targets, anti-vehicle 4+ matches VEHICLE targets.
	"""
	for kw in target_keywords:
		var kw_lower = kw.to_lower()
		# Check for "anti-<keyword>" in special rules
		var anti_pattern = "anti-" + kw_lower
		if anti_pattern in special_rules:
			return true
	return false

static func _weapon_role_name(role: int) -> String:
	"""Return a human-readable name for a weapon role."""
	match role:
		WeaponRole.ANTI_TANK:
			return "Anti-Tank"
		WeaponRole.ANTI_INFANTRY:
			return "Anti-Infantry"
		WeaponRole.GENERAL_PURPOSE:
			return "General"
		_:
			return "Unknown"

static func _target_type_name(target_type: int) -> String:
	"""Return a human-readable name for a target type."""
	match target_type:
		TargetType.VEHICLE_MONSTER:
			return "Vehicle/Monster"
		TargetType.ELITE:
			return "Elite"
		TargetType.HORDE:
			return "Horde"
		_:
			return "Unknown"

# =============================================================================
# STRATAGEM EVALUATION — AI heuristics for when to use stratagems
# =============================================================================

# --- GRENADE STRATAGEM ---

static func evaluate_grenade_usage(snapshot: Dictionary, player: int) -> Dictionary:
	"""
	Evaluate whether the AI should use the GRENADE stratagem this shooting phase.
	Returns { should_use: bool, grenade_unit_id: String, target_unit_id: String,
	          description: String } or { should_use: false }.

	Heuristic: Use Grenade when we have a GRENADES unit whose ranged weapons are
	weak (few shots, low damage) or that has no ranged weapons, AND there is an
	enemy within 8" that would take meaningful damage from 6D6 at 4+ (avg 3 MW).
	Prefer targets with many wounded low-wound models (mortal wounds bypass saves).
	"""
	var grenade_main_loop = Engine.get_main_loop()
	var strat_manager_node = null
	if grenade_main_loop and grenade_main_loop is SceneTree and grenade_main_loop.root:
		strat_manager_node = grenade_main_loop.root.get_node_or_null("/root/StratagemManager")
	if not strat_manager_node:
		return {"should_use": false}

	var eligible_units = strat_manager_node.get_grenade_eligible_units(player)
	if eligible_units.is_empty():
		return {"should_use": false}

	var best_score: float = 0.0
	var best_grenade_unit_id: String = ""
	var best_target_unit_id: String = ""
	var best_grenade_unit_name: String = ""
	var best_target_unit_name: String = ""

	for entry in eligible_units:
		var grenade_unit_id: String = entry.unit_id
		var grenade_unit = snapshot.get("units", {}).get(grenade_unit_id, {})
		if grenade_unit.is_empty():
			continue

		# Check if this unit has strong ranged weapons — if so, shooting normally is better
		var ranged_weapon_strength = _estimate_unit_ranged_strength(grenade_unit)

		# Get eligible grenade targets (within 8")
		var _re3 = _rules_engine()
		if not _re3:
			continue
		var targets = _re3.get_grenade_eligible_targets(grenade_unit_id, snapshot)
		if targets.is_empty():
			continue

		for target_info in targets:
			var target_unit_id: String = target_info.unit_id
			var target_unit = snapshot.get("units", {}).get(target_unit_id, {})
			if target_unit.is_empty():
				continue

			# Score the grenade target: mortal wounds bypass saves, so low-wound models
			# and wounded models are ideal. Average 3 MW from 6D6 at 4+.
			var target_score = _score_grenade_target(target_unit)

			# Reduce score if the unit has strong ranged weapons (shooting normally is better)
			# Grenade expected value: ~3 mortal wounds (no saves)
			# If ranged weapons do more expected damage, prefer shooting
			if ranged_weapon_strength > 4.0:
				target_score *= 0.3  # Strong ranged unit — prefer shooting
			elif ranged_weapon_strength > 2.0:
				target_score *= 0.7  # Moderate ranged unit — slight preference for shooting

			if target_score > best_score:
				best_score = target_score
				best_grenade_unit_id = grenade_unit_id
				best_target_unit_id = target_unit_id
				best_grenade_unit_name = entry.get("unit_name", grenade_unit_id)
				best_target_unit_name = target_info.get("unit_name", target_unit_id)

	# Use grenade if the score is above a meaningful threshold
	# 3 MW is expected value; score of 2.0+ means decent value
	if best_score >= 2.0 and best_grenade_unit_id != "" and best_target_unit_id != "":
		return {
			"should_use": true,
			"grenade_unit_id": best_grenade_unit_id,
			"target_unit_id": best_target_unit_id,
			"description": "%s throws GRENADE at %s" % [best_grenade_unit_name, best_target_unit_name]
		}

	return {"should_use": false}

static func _estimate_unit_ranged_strength(unit: Dictionary) -> float:
	"""
	Estimate the ranged weapon strength of a unit based on expected wounds output.
	Returns a rough score: 0 = no ranged weapons, higher = more damage output.
	"""
	var total_expected = 0.0
	var weapons = unit.get("meta", {}).get("weapons", [])
	var alive_models = _get_alive_models(unit)
	var model_count = alive_models.size()
	if model_count == 0:
		return 0.0

	for w in weapons:
		if w.get("type", "").to_lower() != "ranged":
			continue
		var attacks_str = w.get("attacks", "1")
		var attacks = float(attacks_str) if attacks_str.is_valid_float() else 1.0
		var damage_str = w.get("damage", "1")
		var avg_damage = _parse_average_damage(damage_str)
		var bs_str = w.get("bs", "4+")
		var bs = int(bs_str.replace("+", "")) if "+" in bs_str else 4
		var hit_prob = max(0.0, (7.0 - bs) / 6.0)
		# Rough wound probability (assume average target T4, moderate save)
		var wound_prob = 0.5
		var save_prob = 0.5  # Assume 50% saves get through
		total_expected += attacks * hit_prob * wound_prob * save_prob * avg_damage * model_count

	return total_expected

static func _score_grenade_target(target_unit: Dictionary) -> float:
	"""
	Score a target for GRENADE usage. Mortal wounds bypass saves, so the key
	factors are: remaining wounds (can we kill models?), model count (more models =
	more value from removing them), and unit value (characters/elites are higher value).
	"""
	var alive = _get_alive_models(target_unit)
	var alive_count = alive.size()
	if alive_count == 0:
		return 0.0

	var wounds_per_model = _get_target_wounds_per_model(target_unit)
	var avg_mortal_wounds = 3.0  # Expected from 6D6 at 4+

	# Base score: how many models can we expect to kill?
	if wounds_per_model <= 0:
		wounds_per_model = 1
	var expected_kills = avg_mortal_wounds / float(wounds_per_model)

	# Wounded models are more vulnerable — check if any models are below full wounds
	var total_remaining_wounds = 0.0
	for model in alive:
		var max_wounds = wounds_per_model
		var current_wounds = model.get("wounds", max_wounds)
		total_remaining_wounds += current_wounds

	# Score based on proportion of total wounds we'd remove
	var wound_proportion = avg_mortal_wounds / max(total_remaining_wounds, 1.0)
	var base_score = wound_proportion * 5.0  # Scale: 5.0 if we'd remove all wounds

	# Bonus for being able to finish off models (mortal wounds on 1W models = guaranteed kills)
	if wounds_per_model == 1:
		base_score += 1.0  # 3 expected kills on 1W models

	# Bonus for small elite units (killing 1-2 of 3 models is more impactful)
	if alive_count <= 3 and wounds_per_model >= 3:
		base_score += 1.0

	# Bonus for characters/high-value units
	var keywords = target_unit.get("meta", {}).get("keywords", [])
	for kw in keywords:
		if kw.to_upper() == "CHARACTER":
			base_score += 1.5
			break

	return base_score

# --- GO TO GROUND / SMOKESCREEN (Reactive — during opponent's shooting) ---

static func evaluate_reactive_stratagem(defending_player: int, available_stratagems: Array, target_unit_ids: Array, snapshot: Dictionary) -> Dictionary:
	"""
	Evaluate whether the AI should use a reactive stratagem (Go to Ground or Smokescreen)
	when being shot at. Returns the action dictionary to submit, or empty dict to decline.

	Heuristic:
	- Use Go to Ground on valuable INFANTRY targets without existing invuln saves
	- Use Smokescreen on SMOKE units being targeted (always beneficial: cover + stealth)
	- Prefer Smokescreen over Go to Ground (stealth is -1 to hit, stronger)
	- Skip if the unit is cheap/expendable (not worth 1 CP)
	"""
	var best_stratagem_id: String = ""
	var best_target_unit_id: String = ""
	var best_score: float = 0.0

	for strat_entry in available_stratagems:
		var strat = strat_entry.get("stratagem", {})
		var eligible_units = strat_entry.get("eligible_units", [])
		var strat_id = strat.get("id", "")

		for unit_id in eligible_units:
			var unit = snapshot.get("units", {}).get(unit_id, {})
			if unit.is_empty():
				continue

			var score = _score_defensive_stratagem_target(unit, strat_id)
			if score > best_score:
				best_score = score
				best_stratagem_id = strat_id
				best_target_unit_id = unit_id

	# Use the stratagem if the score is meaningful (unit is worth protecting)
	if best_score >= 1.5 and best_stratagem_id != "" and best_target_unit_id != "":
		var strat_name = ""
		for strat_entry in available_stratagems:
			if strat_entry.get("stratagem", {}).get("id", "") == best_stratagem_id:
				strat_name = strat_entry.stratagem.get("name", best_stratagem_id)
				break
		var strat_target_unit = snapshot.get("units", {}).get(best_target_unit_id, {})
		var unit_name = strat_target_unit.get("meta", {}).get("name", best_target_unit_id)
		var unit_pts = int(strat_target_unit.get("meta", {}).get("points", 0))
		var strat_reason = "%s on %s (%dpts, protection score: %.1f)" % [strat_name, unit_name, unit_pts, best_score]
		return {
			"type": "USE_REACTIVE_STRATAGEM",
			"stratagem_id": best_stratagem_id,
			"target_unit_id": best_target_unit_id,
			"player": defending_player,
			"_ai_description": "AI uses %s" % strat_reason
		}

	return {
		"type": "DECLINE_REACTIVE_STRATAGEM",
		"player": defending_player,
		"_ai_description": "AI declines reactive stratagems"
	}

static func _score_defensive_stratagem_target(unit: Dictionary, stratagem_id: String) -> float:
	"""
	Score how much a unit benefits from a defensive stratagem.
	Higher score = more worth spending 1 CP on.
	"""
	var alive = _get_alive_models(unit)
	var alive_count = alive.size()
	if alive_count == 0:
		return 0.0

	var keywords = unit.get("meta", {}).get("keywords", [])
	var stats = unit.get("meta", {}).get("stats", {})
	var wounds_per_model = int(stats.get("wounds", 1))
	var save = int(stats.get("save", 4))
	var base_score = 0.0

	# Check existing invulnerable save
	var existing_invuln = 0
	for model in alive:
		var model_invuln = model.get("invuln", 0)
		if typeof(model_invuln) == TYPE_STRING:
			model_invuln = int(model_invuln) if model_invuln.is_valid_int() else 0
		if model_invuln > 0:
			existing_invuln = model_invuln
		break
	if existing_invuln == 0:
		existing_invuln = int(stats.get("invuln", 0))

	match stratagem_id:
		"go_to_ground":
			# Go to Ground grants 6+ invuln + cover
			# More valuable when: no existing invuln, poor save, many models, high value
			if existing_invuln > 0 and existing_invuln <= 5:
				# Already has a decent invuln — 6+ invuln won't help much
				base_score += 0.5
			else:
				# No invuln or 6+ — this helps
				base_score += 1.5

			# Cover improves save by 1 (if not already in cover)
			if not unit.get("flags", {}).get("in_cover", false):
				if save >= 5:  # Poor save benefits more from cover
					base_score += 1.0
				else:
					base_score += 0.5

		"smokescreen":
			# Smokescreen grants cover + stealth (-1 to hit)
			# Stealth is always strong — it reduces incoming damage by ~17-33%
			base_score += 2.0

			# Cover on top of stealth is extra value
			if not unit.get("flags", {}).get("in_cover", false):
				base_score += 0.5

	# Scale by unit value
	# Multi-wound models are more valuable per CP
	base_score *= (1.0 + 0.1 * float(wounds_per_model * alive_count))

	# Bonus for CHARACTER units (high value)
	for kw in keywords:
		var kw_upper = kw.to_upper()
		if kw_upper == "CHARACTER":
			base_score += 1.0
		if kw_upper == "LEADER":
			base_score += 0.5

	# Penalty for single-model units with many wounds already lost
	if alive_count == 1 and wounds_per_model > 1:
		var current_wounds = alive[0].get("wounds", wounds_per_model)
		if current_wounds <= 1:
			base_score *= 0.3  # Nearly dead — not worth saving

	return base_score

# --- FIRE OVERWATCH (Reactive — during opponent's movement/charge) ---

static func evaluate_fire_overwatch(defending_player: int, eligible_units: Array, enemy_unit_id: String, snapshot: Dictionary) -> Dictionary:
	"""
	Evaluate whether the AI should use Fire Overwatch against a moving/charging enemy.
	Returns the action dictionary to submit, or empty dict to decline.

	Heuristic: Fire Overwatch hits only on unmodified 6s (16.7% hit rate).
	Use when:
	- The unit has many high-volume ranged weapons (more dice = more 6s)
	- The enemy is a high-value target (character, expensive unit)
	- The CP cost is affordable (1 CP, once per turn)
	Avoid when:
	- The unit only has 1-2 shots (very unlikely to do anything)
	- CP reserves are low (< 3 CP, save for other stratagems)
	"""
	var player_cp = _get_player_cp_from_snapshot(snapshot, defending_player)

	# Don't use overwatch if CP is low — save for more reliable stratagems
	if player_cp < 2:
		return _decline_fire_overwatch(defending_player)

	var enemy_unit = snapshot.get("units", {}).get(enemy_unit_id, {})
	if enemy_unit.is_empty():
		return _decline_fire_overwatch(defending_player)

	# Evaluate enemy threat level
	var enemy_value = _estimate_unit_value(enemy_unit)

	var best_unit_id: String = ""
	var best_unit_name: String = ""
	var best_expected_hits: float = 0.0

	for entry in eligible_units:
		var unit_id: String = ""
		var unit_name: String = ""
		if entry is Dictionary:
			unit_id = entry.get("unit_id", "")
			unit_name = entry.get("unit_name", unit_id)
		elif entry is String:
			unit_id = entry
			unit_name = entry

		var unit = snapshot.get("units", {}).get(unit_id, {})
		if unit.is_empty():
			continue

		# Count total ranged shots (overwatch hits on 6s only)
		var total_shots = _count_unit_ranged_shots(unit)
		var expected_hits = total_shots / 6.0  # 1/6 chance per shot

		if expected_hits > best_expected_hits:
			best_expected_hits = expected_hits
			best_unit_id = unit_id
			best_unit_name = unit_name

	# Use overwatch if we expect at least ~1 hit and enemy is valuable
	# Threshold: at least 0.5 expected hits (3+ total shots) AND enemy worth shooting at
	if best_expected_hits >= 0.5 and enemy_value >= 2.0 and best_unit_id != "":
		var enemy_name = enemy_unit.get("meta", {}).get("name", enemy_unit_id)
		return {
			"type": "USE_FIRE_OVERWATCH",
			"unit_id": best_unit_id,
			"player": defending_player,
			"_ai_description": "AI fires overwatch with %s at %s (%.1f expected hits)" % [best_unit_name, enemy_name, best_expected_hits]
		}

	return _decline_fire_overwatch(defending_player)

static func _decline_fire_overwatch(player: int) -> Dictionary:
	return {
		"type": "DECLINE_FIRE_OVERWATCH",
		"player": player,
		"_ai_description": "AI declines Fire Overwatch"
	}

# --- TANK SHOCK (Proactive — after own charge move with VEHICLE) ---

static func evaluate_tank_shock(player: int, vehicle_unit_id: String, snapshot: Dictionary) -> Dictionary:
	"""
	Evaluate whether the AI should use Tank Shock after a successful charge with a VEHICLE.
	Returns USE_TANK_SHOCK or DECLINE_TANK_SHOCK action dictionary.

	Heuristic: Tank Shock rolls D6 equal to Toughness (max 6), each 5+ = 1 mortal wound.
	Use when:
	- Vehicle has high toughness (T6+ → 6 dice, ~2 expected MW)
	- Enemy target has low-wound models (MW kills them outright)
	- CP is affordable (1 CP)
	Skip when:
	- Vehicle has low toughness (T4 or less → only 4 dice, ~1.3 MW)
	- CP reserves are very low (1 CP remaining)
	"""
	var player_cp = _get_player_cp_from_snapshot(snapshot, player)

	# Need at least 1 CP to use, but save 1 for other stratagems if possible
	if player_cp < 1:
		return {
			"type": "DECLINE_TANK_SHOCK",
			"_ai_description": "AI declines Tank Shock (no CP)"
		}

	var vehicle_unit = snapshot.get("units", {}).get(vehicle_unit_id, {})
	if vehicle_unit.is_empty():
		return {
			"type": "DECLINE_TANK_SHOCK",
			"_ai_description": "AI declines Tank Shock (no vehicle data)"
		}

	var vehicle_name = vehicle_unit.get("meta", {}).get("name", vehicle_unit_id)
	var toughness = int(vehicle_unit.get("meta", {}).get("toughness", vehicle_unit.get("meta", {}).get("stats", {}).get("toughness", 4)))
	var dice_count = mini(toughness, 6)

	# Expected mortal wounds: dice_count * (2/6) = dice_count / 3
	var expected_mw = float(dice_count) / 3.0

	# Find the best target among enemies in engagement range
	# We use StratagemManager.get_tank_shock_eligible_targets if available,
	# otherwise estimate from snapshot
	var ts_main_loop = Engine.get_main_loop()
	var strat_manager_node = null
	if ts_main_loop and ts_main_loop is SceneTree and ts_main_loop.root:
		strat_manager_node = ts_main_loop.root.get_node_or_null("/root/StratagemManager")
	var eligible_targets = []
	if strat_manager_node:
		eligible_targets = strat_manager_node.get_tank_shock_eligible_targets(vehicle_unit_id, snapshot)

	if eligible_targets.is_empty():
		return {
			"type": "DECLINE_TANK_SHOCK",
			"_ai_description": "AI declines Tank Shock (no eligible targets)"
		}

	var best_target_id = ""
	var best_target_name = ""
	var best_target_score = 0.0

	for target_entry in eligible_targets:
		var target_unit_id = target_entry.get("unit_id", "")
		var target_unit = snapshot.get("units", {}).get(target_unit_id, {})
		if target_unit.is_empty():
			continue

		var target_name = target_entry.get("unit_name", target_unit_id)
		var wounds_per_model = _get_target_wounds_per_model(target_unit)
		var alive_models = _get_alive_models(target_unit)
		var alive_count = alive_models.size()

		# Score: higher when MW will kill models outright
		var score = expected_mw

		# Bonus if wounds_per_model is low (MW kills models outright)
		if wounds_per_model <= 2:
			score *= 1.5  # MW efficiently kills low-wound models
		elif wounds_per_model <= 3:
			score *= 1.2

		# Bonus for small remaining unit (finishing blow)
		if alive_count <= 3:
			score *= 1.3

		# Bonus for high-value targets
		var target_value = _estimate_unit_value(target_unit)
		if target_value >= 5.0:
			score *= 1.2

		if score > best_target_score:
			best_target_score = score
			best_target_id = target_unit_id
			best_target_name = target_name

	# Use if expected value is meaningful (>= 1.0 expected mortal wounds in effect)
	# and we have enough CP (or the score is high enough to justify spending last CP)
	if best_target_score >= 1.0 and best_target_id != "":
		# If this is our last CP, only use if really good value
		if player_cp <= 1 and best_target_score < 2.0:
			return {
				"type": "DECLINE_TANK_SHOCK",
				"_ai_description": "AI declines Tank Shock (saving last CP)"
			}

		print("AIDecisionMaker: Tank Shock — %s (T%d, %dD6) targeting %s (score: %.1f)" % [
			vehicle_name, toughness, dice_count, best_target_name, best_target_score])
		return {
			"type": "USE_TANK_SHOCK",
			"actor_unit_id": vehicle_unit_id,
			"payload": {
				"target_unit_id": best_target_id
			},
			"_ai_description": "AI uses Tank Shock with %s on %s (T%d, %.1f expected MW)" % [
				vehicle_name, best_target_name, toughness, expected_mw]
		}

	return {
		"type": "DECLINE_TANK_SHOCK",
		"_ai_description": "AI declines Tank Shock (low value)"
	}

# --- COUNTER-OFFENSIVE (Reactive — after enemy unit fights in Fight Phase) ---

static func evaluate_counter_offensive(player: int, eligible_units: Array, snapshot: Dictionary) -> Dictionary:
	"""
	Evaluate whether the AI should use Counter-Offensive (2CP) after an enemy unit fights.
	Returns USE_COUNTER_OFFENSIVE or DECLINE_COUNTER_OFFENSIVE action dictionary.

	Heuristic: Counter-Offensive lets the AI fight next with a chosen unit.
	Use when:
	- A high-value melee unit is at risk (could be killed before it gets to fight)
	- The unit has strong melee weapons and meaningful damage to deal
	- CP is affordable (2 CP — same cost as Heroic Intervention)
	Skip when:
	- No strong melee units eligible
	- CP reserves are low (< 3 CP) and the unit isn't critical
	- Eligible units are cheap/expendable (not worth 2 CP)
	"""
	var player_cp = _get_player_cp_from_snapshot(snapshot, player)

	# Counter-Offensive costs 2 CP
	if player_cp < 2:
		return {
			"type": "DECLINE_COUNTER_OFFENSIVE",
			"player": player,
			"_ai_description": "AI declines Counter-Offensive (insufficient CP: %d)" % player_cp
		}

	if eligible_units.is_empty():
		return {
			"type": "DECLINE_COUNTER_OFFENSIVE",
			"player": player,
			"_ai_description": "AI declines Counter-Offensive (no eligible units)"
		}

	var best_unit_id = ""
	var best_unit_name = ""
	var best_score = 0.0

	for entry in eligible_units:
		var unit_id = entry.get("unit_id", "")
		var unit_name = entry.get("unit_name", unit_id)
		var unit = snapshot.get("units", {}).get(unit_id, {})
		if unit.is_empty():
			continue

		var score = 0.0
		var keywords = unit.get("meta", {}).get("keywords", [])
		var has_melee = _unit_has_melee_weapons(unit)

		# Must have melee weapons to benefit from fighting next
		if not has_melee:
			# Unit only has close combat weapon — low value
			score += 0.5
		else:
			score += 2.0

		# Score based on unit value (high-value units are worth protecting)
		var unit_value = _estimate_unit_value(unit)
		score += unit_value * 0.4

		# Bonus for CHARACTER units (critical to protect)
		for kw in keywords:
			var kw_upper = kw.to_upper()
			if kw_upper == "CHARACTER":
				score += 2.5
			elif kw_upper == "MONSTER":
				score += 1.5
			elif kw_upper == "VEHICLE":
				score += 1.0

		# Check if the unit is at risk — wounded units benefit more from striking first
		var alive = _get_alive_models(unit)
		var alive_count = alive.size()
		var stats = unit.get("meta", {}).get("stats", {})
		var wounds_per_model = int(stats.get("wounds", 1))

		if alive_count == 1 and wounds_per_model > 1:
			# Single multi-wound model — check remaining wounds
			var current_wounds = alive[0].get("wounds", wounds_per_model)
			if current_wounds <= wounds_per_model / 2:
				# Badly wounded — high urgency to strike before being killed
				score += 2.0
			elif current_wounds < wounds_per_model:
				score += 1.0

		# Bonus if the unit has many models (more attacks = more value from fighting)
		if alive_count >= 5:
			score += 1.0
		elif alive_count >= 3:
			score += 0.5

		# Check how many enemies are in engagement range (more enemies = more risk)
		var enemy_count_in_range = 0
		var all_units = snapshot.get("units", {})
		for other_id in all_units:
			var other = all_units[other_id]
			if int(other.get("owner", 0)) == player:
				continue
			# Simple proximity check using model positions
			if _are_units_close(unit, other, 1.5):  # ~1" engagement range in inches
				enemy_count_in_range += 1

		if enemy_count_in_range >= 2:
			score += 1.5  # Surrounded — high risk, fight before more enemies pile on

		if score > best_score:
			best_score = score
			best_unit_id = unit_id
			best_unit_name = unit_name

	# Use Counter-Offensive if score justifies the 2 CP cost
	# Threshold of 3.0 (same as Heroic Intervention — both cost 2 CP)
	if best_score >= 3.0 and best_unit_id != "":
		# If CP is tight (exactly 2), only use for very valuable units
		if player_cp <= 2 and best_score < 5.0:
			print("AIDecisionMaker: Counter-Offensive — declining for %s (score: %.1f, saving CP)" % [best_unit_name, best_score])
			return {
				"type": "DECLINE_COUNTER_OFFENSIVE",
				"player": player,
				"_ai_description": "AI declines Counter-Offensive (saving CP, score: %.1f)" % best_score
			}

		print("AIDecisionMaker: Counter-Offensive — %s fights next! (score: %.1f)" % [best_unit_name, best_score])
		return {
			"type": "USE_COUNTER_OFFENSIVE",
			"unit_id": best_unit_id,
			"player": player,
			"_ai_description": "AI uses Counter-Offensive with %s (score: %.1f)" % [best_unit_name, best_score]
		}

	print("AIDecisionMaker: Counter-Offensive — declining (best score: %.1f below threshold)" % best_score)
	return {
		"type": "DECLINE_COUNTER_OFFENSIVE",
		"player": player,
		"_ai_description": "AI declines Counter-Offensive (low value, score: %.1f)" % best_score
	}

static func _are_units_close(unit_a: Dictionary, unit_b: Dictionary, max_inches: float) -> bool:
	"""Check if any model from unit_a is roughly within max_inches of any model from unit_b.
	Uses pixel distance with PIXELS_PER_INCH conversion for a quick proximity check."""
	var max_dist_px = max_inches * PIXELS_PER_INCH
	for model_a in unit_a.get("models", []):
		if not model_a.get("alive", true):
			continue
		var pos_a = _get_model_position(model_a)
		if pos_a == Vector2.INF:
			continue
		for model_b in unit_b.get("models", []):
			if not model_b.get("alive", true):
				continue
			var pos_b = _get_model_position(model_b)
			if pos_b == Vector2.INF:
				continue
			if pos_a.distance_to(pos_b) <= max_dist_px:
				return true
	return false

# --- HEROIC INTERVENTION (Reactive — after opponent's charge) ---

static func evaluate_heroic_intervention(defending_player: int, charging_unit_id: String, snapshot: Dictionary) -> Dictionary:
	"""
	Evaluate whether the AI should use Heroic Intervention to counter-charge.
	Returns USE_HEROIC_INTERVENTION or DECLINE_HEROIC_INTERVENTION action dictionary.

	Heuristic: Heroic Intervention costs 2 CP and requires a charge roll.
	Use when:
	- We have a melee-capable unit nearby (within 6\" of the charging enemy)
	- The counter-charging unit is a strong melee fighter (CHARACTER with good melee)
	- CP is affordable (2 CP, save some for other uses)
	Skip when:
	- No strong melee units available
	- CP reserves are low (< 3 CP)
	- Counter-charger would be outmatched
	"""
	var player_cp = _get_player_cp_from_snapshot(snapshot, defending_player)

	# Heroic Intervention costs 2 CP — need at least 2, prefer 3+
	if player_cp < 2:
		return {
			"type": "DECLINE_HEROIC_INTERVENTION",
			"player": defending_player,
			"_ai_description": "AI declines Heroic Intervention (insufficient CP)"
		}

	# Get eligible units from StratagemManager
	var main_loop = Engine.get_main_loop()
	var strat_manager_node = null
	if main_loop and main_loop is SceneTree and main_loop.root:
		strat_manager_node = main_loop.root.get_node_or_null("/root/StratagemManager")
	if not strat_manager_node:
		return {
			"type": "DECLINE_HEROIC_INTERVENTION",
			"player": defending_player,
			"_ai_description": "AI declines Heroic Intervention"
		}

	var eligible_units = strat_manager_node.get_heroic_intervention_eligible_units(
		defending_player, charging_unit_id, snapshot
	)

	if eligible_units.is_empty():
		return {
			"type": "DECLINE_HEROIC_INTERVENTION",
			"player": defending_player,
			"_ai_description": "AI declines Heroic Intervention (no eligible units)"
		}

	var charging_unit = snapshot.get("units", {}).get(charging_unit_id, {})
	var charging_value = _estimate_unit_value(charging_unit)

	var best_unit_id = ""
	var best_unit_name = ""
	var best_score = 0.0

	for entry in eligible_units:
		var unit_id = entry.get("unit_id", "")
		var unit_name = entry.get("unit_name", unit_id)
		var unit = snapshot.get("units", {}).get(unit_id, {})
		if unit.is_empty():
			continue

		# Score the counter-charge candidate
		var score = 0.0
		var keywords = unit.get("meta", {}).get("keywords", [])
		var has_melee = _unit_has_melee_weapons(unit)

		# Must have melee weapons to be useful
		if not has_melee:
			continue

		# Base score from unit value (stronger units are better counter-chargers)
		var unit_value = _estimate_unit_value(unit)
		score += unit_value * 0.5

		# Bonus for CHARACTER units (they usually have strong melee)
		for kw in keywords:
			var kw_upper = kw.to_upper()
			if kw_upper == "CHARACTER":
				score += 2.0
			elif kw_upper == "MONSTER":
				score += 1.0

		# Scale by enemy value (worth counter-charging valuable enemies)
		if charging_value >= 5.0:
			score *= 1.3
		elif charging_value <= 2.0:
			score *= 0.5  # Not worth 2 CP against cheap units

		if score > best_score:
			best_score = score
			best_unit_id = unit_id
			best_unit_name = unit_name

	# Use if score is high enough to justify 2 CP
	# Threshold higher than other stratagems because of cost and charge roll uncertainty
	if best_score >= 3.0 and best_unit_id != "":
		# If CP is tight (exactly 2), only use against very valuable targets
		if player_cp <= 2 and best_score < 5.0:
			return {
				"type": "DECLINE_HEROIC_INTERVENTION",
				"player": defending_player,
				"_ai_description": "AI declines Heroic Intervention (saving CP)"
			}

		print("AIDecisionMaker: Heroic Intervention — %s counter-charges (score: %.1f)" % [best_unit_name, best_score])
		return {
			"type": "USE_HEROIC_INTERVENTION",
			"player": defending_player,
			"payload": {
				"unit_id": best_unit_id
			},
			"_ai_description": "AI uses Heroic Intervention with %s (score: %.1f)" % [best_unit_name, best_score]
		}

	return {
		"type": "DECLINE_HEROIC_INTERVENTION",
		"player": defending_player,
		"_ai_description": "AI declines Heroic Intervention (low value)"
	}

static func _count_unit_ranged_shots(unit: Dictionary) -> float:
	"""Count total expected ranged attacks for a unit (all alive models * all ranged weapons)."""
	var total = 0.0
	var weapons = unit.get("meta", {}).get("weapons", [])
	var alive = _get_alive_models(unit)
	var model_count = alive.size()

	for w in weapons:
		if w.get("type", "").to_lower() != "ranged":
			continue
		var attacks_str = w.get("attacks", "1")
		var attacks = 0.0
		if attacks_str.is_valid_float():
			attacks = float(attacks_str)
		elif attacks_str.is_valid_int():
			attacks = float(attacks_str)
		elif "d" in attacks_str.to_lower():
			# Variable attacks: use average
			attacks = _parse_average_damage(attacks_str)
		else:
			attacks = 1.0
		total += attacks * model_count

	return total

static func _estimate_unit_value(unit: Dictionary) -> float:
	"""
	Estimate the tactical value of a unit for stratagem decisions.
	Returns a rough score: higher = more valuable.
	"""
	var keywords = unit.get("meta", {}).get("keywords", [])
	var stats = unit.get("meta", {}).get("stats", {})
	var wounds_per_model = int(stats.get("wounds", 1))
	var alive = _get_alive_models(unit)
	var alive_count = alive.size()
	var value = float(alive_count) * float(wounds_per_model) * 0.5

	for kw in keywords:
		var kw_upper = kw.to_upper()
		if kw_upper == "CHARACTER":
			value += 3.0
		elif kw_upper == "VEHICLE":
			value += 2.0
		elif kw_upper == "MONSTER":
			value += 2.0

	return value

# --- COMMAND RE-ROLL (Reactive — after any dice roll) ---

static func evaluate_command_reroll_charge(player: int, rolled_distance: int, required_distance: int, snapshot: Dictionary) -> bool:
	"""
	Evaluate whether the AI should re-roll a charge roll.
	Returns true if the re-roll is worthwhile.

	Heuristic: Re-roll if the charge FAILED and:
	- The gap between rolled and required is small (reroll has reasonable chance)
	- The charging unit is important (character, elite unit)
	"""
	if rolled_distance >= required_distance:
		return false  # Charge already succeeded — no need to reroll

	var gap = required_distance - rolled_distance
	# Probability of rolling required on 2D6:
	# 2D6 average = 7, so if we need 7+ the chance is ~58.3%
	# Need 8+ = ~41.7%, 9+ = ~27.8%, 10+ = ~16.7%, 11+ = ~8.3%, 12 = ~2.8%
	# Don't reroll if we need 11+ (too unlikely)
	if required_distance > 10:
		return false

	# If the roll was close to required (within 2), always reroll
	if gap <= 2 and required_distance <= 9:
		return true

	# If the roll was terrible (e.g. rolled 3 on 2D6, needed 7), reroll
	if rolled_distance <= 4 and required_distance <= 9:
		return true

	# For moderate gaps, check CP affordability
	var player_cp = _get_player_cp_from_snapshot(snapshot, player)
	if player_cp >= 3 and required_distance <= 9:
		return true  # We can afford it, take the shot

	return false

static func evaluate_command_reroll_battleshock(player: int, roll: int, leadership: int, snapshot: Dictionary) -> bool:
	"""
	Evaluate whether the AI should re-roll a failed battle-shock test.
	Returns true if the re-roll is worthwhile.

	Heuristic: Re-roll if:
	- The unit needs the test to pass (e.g. holding an objective)
	- The gap between roll and leadership is small
	"""
	if roll <= leadership:
		return false  # Already passed

	var gap = roll - leadership
	# Re-rolling 2D6: if we need to roll <= leadership, higher leadership = more likely
	# Leadership 6: need 6 or less = 41.7% on 2D6
	# Leadership 7: need 7 or less = 58.3%
	# Leadership 8: need 8 or less = 72.2%

	# Always reroll if leadership is 7+ (good chance of passing)
	if leadership >= 7:
		return true

	# Reroll if the gap is small (within 2)
	if gap <= 2:
		return true

	# If leadership is very low (5 or less), don't waste CP
	if leadership <= 5:
		return false

	return true

static func evaluate_command_reroll_advance(player: int, advance_roll: int, snapshot: Dictionary) -> bool:
	"""
	Evaluate whether the AI should re-roll an advance roll.
	Returns true if the re-roll is worthwhile.

	Heuristic: Re-roll if the roll is very low (1 or 2) since advancing
	is usually done when the extra distance matters.
	"""
	# Only reroll very low advance rolls — a 1 is the worst possible
	if advance_roll <= 1:
		return true
	if advance_roll <= 2:
		# Check if CP is plentiful
		var player_cp = _get_player_cp_from_snapshot(snapshot, player)
		if player_cp >= 3:
			return true

	return false

# --- HELPER: Get player CP from snapshot ---

static func _get_player_cp_from_snapshot(snapshot: Dictionary, player: int) -> int:
	"""Get a player's CP from the game state snapshot."""
	var players = snapshot.get("players", {})
	var player_data = players.get(str(player), players.get(player, {}))
	return int(player_data.get("cp", 0))

# =============================================================================
# ENEMY THREAT RANGE AWARENESS (AI-TACTIC-4, MOV-2)
# =============================================================================
# Calculates charge threat zones and shooting ranges for enemy units,
# allowing the AI to avoid moving into danger when not tactically necessary.

static func _calculate_enemy_threat_data(enemies: Dictionary) -> Array:
	"""Build an array of threat data for each enemy unit.
	Each entry: {unit_id, centroid, charge_threat_px, shoot_threat_px, has_melee, has_ranged, unit_value}
	charge_threat_px = (enemy M + 12" charge + 1" ER) in pixels
	shoot_threat_px = max ranged weapon range in pixels"""
	var threat_data = []
	for enemy_id in enemies:
		var enemy = enemies[enemy_id]
		var ecentroid = _get_unit_centroid(enemy)
		if ecentroid == Vector2.INF:
			continue
		var enemy_stats = enemy.get("meta", {}).get("stats", {})
		var enemy_move = float(enemy_stats.get("move", 6))
		var has_melee = _unit_has_melee_weapons(enemy)
		var has_ranged = _unit_has_ranged_weapons(enemy)
		var max_shoot_range = _get_max_weapon_range(enemy)  # in inches

		# Charge threat range = Movement + 12" max charge + 1" engagement range
		# This represents the maximum distance this unit could reach with a move + charge
		var charge_threat_inches = enemy_move + 12.0 + 1.0
		var charge_threat_px = charge_threat_inches * PIXELS_PER_INCH

		# Shooting threat range = max weapon range
		var shoot_threat_px = max_shoot_range * PIXELS_PER_INCH

		# Estimate unit value/lethality for weighting the threat
		var unit_value = _estimate_enemy_threat_level(enemy)

		threat_data.append({
			"unit_id": enemy_id,
			"centroid": ecentroid,
			"charge_threat_px": charge_threat_px,
			"shoot_threat_px": shoot_threat_px,
			"has_melee": has_melee,
			"has_ranged": has_ranged,
			"unit_value": unit_value
		})
	return threat_data

static func _estimate_enemy_threat_level(enemy: Dictionary) -> float:
	"""Estimate how dangerous an enemy unit is (0.0 to 3.0 scale).
	Used to weight threat zones — more dangerous enemies create scarier zones."""
	var value = 1.0
	var keywords = enemy.get("meta", {}).get("keywords", [])
	var stats = enemy.get("meta", {}).get("stats", {})

	# More alive models = more dangerous
	var alive_count = 0
	for model in enemy.get("models", []):
		if model.get("alive", true):
			alive_count += 1
	if alive_count >= 10:
		value += 0.5
	elif alive_count <= 2:
		value -= 0.2

	# High toughness / wounds suggests elite unit
	var toughness = int(stats.get("toughness", 4))
	var wounds = int(stats.get("wounds", 1))
	if toughness >= 8 or wounds >= 8:
		value += 0.5  # Heavy hitters (vehicles, monsters)
	if wounds >= 4:
		value += 0.3

	# Characters and leader-attached units are more threatening
	if "CHARACTER" in keywords or "VEHICLE" in keywords or "MONSTER" in keywords:
		value += 0.3

	# T7-13: Factor in melee weapon quality for melee-capable enemies
	# Units with powerful melee weapons (high strength, AP, damage, many attacks) are scarier
	var weapons = enemy.get("meta", {}).get("weapons", [])
	var best_melee_score = 0.0
	for w in weapons:
		if w.get("type", "").to_lower() != "melee":
			continue
		var w_attacks_str = w.get("attacks", "1")
		var w_attacks = float(w_attacks_str) if w_attacks_str.is_valid_float() else 1.0
		var w_strength_str = w.get("strength", "4")
		var w_strength = int(w_strength_str) if w_strength_str.is_valid_int() else 4
		var w_ap_str = w.get("ap", "0")
		var w_ap = abs(int(w_ap_str.replace("-", ""))) if w_ap_str.replace("-", "").is_valid_int() else 0
		var w_damage_str = w.get("damage", "1")
		var w_damage = float(w_damage_str) if w_damage_str.is_valid_float() else 1.0
		# Simple melee quality score: attacks * strength-factor * ap-factor * damage
		var s_factor = 1.0 + (w_strength - 4) * 0.1  # S4=1.0, S8=1.4, S12=1.8
		var ap_factor = 1.0 + w_ap * 0.15             # AP0=1.0, AP-2=1.3, AP-4=1.6
		var melee_score = w_attacks * s_factor * ap_factor * w_damage
		best_melee_score = max(best_melee_score, melee_score)

	# Scale: 0 damage = no bonus, typical melee (~4 score) = +0.2, powerful melee (~10+ score) = +0.5
	if best_melee_score >= 10.0:
		value += 0.5
	elif best_melee_score >= 6.0:
		value += 0.3
	elif best_melee_score >= 3.0:
		value += 0.2

	return clampf(value, 0.3, 3.0)

static func _evaluate_position_threat(
	pos: Vector2, threat_data: Array, own_unit: Dictionary
) -> Dictionary:
	"""Evaluate the threat level at a specific position from all enemy units.
	Returns {charge_threat: float, shoot_threat: float, total_threat: float, threats: Array}
	Higher values = more dangerous position."""
	var charge_threat = 0.0
	var shoot_threat = 0.0
	var threats = []  # Details of which enemies threaten this position
	var is_melee_focused = _unit_has_melee_weapons(own_unit) and not _unit_has_ranged_weapons(own_unit)

	var close_melee_range_px = THREAT_CLOSE_MELEE_DISTANCE_INCHES * PIXELS_PER_INCH

	for td in threat_data:
		var dist = pos.distance_to(td.centroid)

		# Check charge threat zone (enemy could move + charge to reach here)
		if td.has_melee and dist < td.charge_threat_px:
			# How deep into the charge threat zone are we? (0.0 = edge, 1.0 = right on top)
			var depth = 1.0 - (dist / td.charge_threat_px)
			var charge_penalty = depth * td.unit_value * THREAT_CHARGE_PENALTY
			# Melee units care less about being charged (they want to fight)
			if is_melee_focused:
				charge_penalty *= THREAT_MELEE_UNIT_IGNORE
			charge_threat += charge_penalty
			threats.append({
				"enemy_id": td.unit_id,
				"type": "charge",
				"distance_inches": dist / PIXELS_PER_INCH,
				"threat_range_inches": td.charge_threat_px / PIXELS_PER_INCH,
				"penalty": charge_penalty
			})

			# T7-13: Extra close melee proximity penalty — within 12" the enemy can
			# charge without needing to move first, which is critically dangerous
			if dist < close_melee_range_px:
				var close_depth = 1.0 - (dist / close_melee_range_px)  # 0=edge of 12", 1=on top
				var close_penalty = close_depth * td.unit_value * THREAT_CLOSE_MELEE_PENALTY
				if is_melee_focused:
					close_penalty *= THREAT_MELEE_UNIT_IGNORE
				charge_threat += close_penalty
				threats.append({
					"enemy_id": td.unit_id,
					"type": "close_melee",
					"distance_inches": dist / PIXELS_PER_INCH,
					"threat_range_inches": THREAT_CLOSE_MELEE_DISTANCE_INCHES,
					"penalty": close_penalty
				})

		# Check shooting threat zone
		if td.has_ranged and td.shoot_threat_px > 0 and dist < td.shoot_threat_px:
			var depth = 1.0 - (dist / td.shoot_threat_px)
			var shoot_penalty = depth * td.unit_value * THREAT_SHOOTING_PENALTY
			shoot_threat += shoot_penalty
			threats.append({
				"enemy_id": td.unit_id,
				"type": "shooting",
				"distance_inches": dist / PIXELS_PER_INCH,
				"threat_range_inches": td.shoot_threat_px / PIXELS_PER_INCH,
				"penalty": shoot_penalty
			})

	var total_threat = charge_threat + shoot_threat

	# Fragile units (low toughness, few wounds) get extra penalty in danger
	var own_stats = own_unit.get("meta", {}).get("stats", {})
	var own_toughness = int(own_stats.get("toughness", 4))
	var own_wounds = int(own_stats.get("wounds", 1))
	if own_toughness <= 3 or own_wounds <= 1:
		total_threat *= THREAT_FRAGILE_BONUS

	return {
		"charge_threat": charge_threat,
		"shoot_threat": shoot_threat,
		"total_threat": total_threat,
		"threats": threats
	}

static func _is_position_in_charge_threat(pos: Vector2, threat_data: Array) -> bool:
	"""Quick check: is this position within any enemy's charge threat range?"""
	for td in threat_data:
		if not td.has_melee:
			continue
		var dist = pos.distance_to(td.centroid)
		if dist < td.charge_threat_px:
			return true
	return false

static func _find_safer_position(
	current_pos: Vector2, desired_pos: Vector2, move_px: float,
	threat_data: Array, own_unit: Dictionary, objectives: Array
) -> Vector2:
	"""Given a desired movement destination, try to find a nearby position that
	reduces threat exposure while still making progress toward the objective.
	Returns the adjusted position, or desired_pos if no safer alternative exists."""
	var desired_threat = _evaluate_position_threat(desired_pos, threat_data, own_unit)
	var current_threat = _evaluate_position_threat(current_pos, threat_data, own_unit)

	# If the desired position is not significantly more dangerous, keep it
	if desired_threat.total_threat <= 0.5 or desired_threat.total_threat <= current_threat.total_threat:
		return desired_pos

	# Only try to find safer positions if the threat increase is meaningful
	if desired_threat.total_threat - current_threat.total_threat < 1.0:
		return desired_pos

	# Try positions along the same general direction but offset to reduce threat
	var move_dir = (desired_pos - current_pos)
	var move_dist = move_dir.length()
	if move_dist < 1.0:
		return desired_pos
	move_dir = move_dir.normalized()

	var best_pos = desired_pos
	var best_score = -INF

	# Score = progress toward target - threat penalty
	# We want to still move forward but choose a less threatened position
	var perp = Vector2(-move_dir.y, move_dir.x)

	# Try: original, slightly left/right, shorter move, shorter + offset
	var candidates = [desired_pos]

	# Lateral offsets (dodge sideways)
	for offset_mult in [1.0, -1.0, 2.0, -2.0]:
		var offset = perp * (PIXELS_PER_INCH * 2.0) * offset_mult
		var candidate = desired_pos + offset
		candidate.x = clamp(candidate.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
		candidate.y = clamp(candidate.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)
		if current_pos.distance_to(candidate) <= move_px:
			candidates.append(candidate)

	# Shorter moves (stop just outside charge threat)
	for fraction in [0.75, 0.5]:
		var shorter = current_pos + move_dir * move_dist * fraction
		shorter.x = clamp(shorter.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
		shorter.y = clamp(shorter.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)
		candidates.append(shorter)
		# Also try shorter + lateral offset
		for offset_mult in [1.0, -1.0]:
			var offset = perp * (PIXELS_PER_INCH * 2.0) * offset_mult
			var combo = shorter + offset
			combo.x = clamp(combo.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
			combo.y = clamp(combo.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)
			if current_pos.distance_to(combo) <= move_px:
				candidates.append(combo)

	# Find nearest objective for progress scoring
	var target_obj = _nearest_objective_pos(desired_pos, objectives)

	for candidate in candidates:
		var cand_threat = _evaluate_position_threat(candidate, threat_data, own_unit)
		# Progress = how much closer to the target objective compared to current position
		var progress = 0.0
		if target_obj != Vector2.INF:
			var current_dist_to_obj = current_pos.distance_to(target_obj)
			var cand_dist_to_obj = candidate.distance_to(target_obj)
			progress = (current_dist_to_obj - cand_dist_to_obj) / PIXELS_PER_INCH  # Inches gained toward objective
		# Score: progress matters, but reducing threat also matters
		var score = progress * 1.5 - cand_threat.total_threat
		if score > best_score:
			best_score = score
			best_pos = candidate

	if best_pos != desired_pos:
		print("AIDecisionMaker: Threat-adjusted position from (%.0f, %.0f) to (%.0f, %.0f) — threat %.1f -> %.1f" % [
			desired_pos.x, desired_pos.y, best_pos.x, best_pos.y,
			desired_threat.total_threat,
			_evaluate_position_threat(best_pos, threat_data, own_unit).total_threat
		])

	return best_pos
