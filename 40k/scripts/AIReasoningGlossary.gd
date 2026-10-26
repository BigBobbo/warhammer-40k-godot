extends RefCounted
class_name AIReasoningGlossary

# AIReasoningGlossary — plain-English names for the values AIDecisionMaker puts
# in a decision record's score_breakdown, used by the K suggestion breakdown
# (AISuggestionBreakdownPanel) so a player reads "Weapon fit ×0.24 (poor)"
# instead of `efficiency=0.24`.
#
# Each entry:
#   label   — short name shown to the player
#   help    — one-line tooltip explaining what it measures
#   fmt     — how the value is printed:
#               pts    signed score points (additive ledger term)
#               in     inches                 wounds  wounds
#               pct    0..1 shown as percent  mult    multiplier, with a word
#               turns  battle turns           vp      victory points
#               num    plain number           text    shown as-is
#   good    — which direction favours an option: "high", "low" or "" (neutral /
#             not comparable). Only used for factor-style records; additive
#             terms are compared by their signed contribution.
#   hidden  — true when the value just repeats the option's score (shown
#             elsewhere) or is pure bookkeeping
#
# Keys missing here still render (humanised key name) and are listed under
# "Developer details › Unlabelled values" so gaps are easy to spot and add.

const TERMS := {
	# --- Movement: objective scoring ledger (sums to the score) -------------
	"objective_priority": {"label": "Objective value", "fmt": "pts", "help": "Base value of this objective right now: who controls it, how contested it is, and the VP at stake."},
	"oc_efficiency": {"label": "Enough OC to take it", "fmt": "pts", "help": "Bonus when this unit's Objective Control is enough to win the objective."},
	"distance_penalty": {"label": "Distance cost", "fmt": "pts", "help": "Penalty for each extra turn needed to get there."},
	"reach_horizon": {"label": "Rounds left to score", "fmt": "pts", "help": "Reduced when the unit would arrive too late to score here in the remaining rounds."},
	"stay_on_objective": {"label": "Already holding it", "fmt": "pts", "help": "Bonus for staying on an objective the unit already holds."},
	"horde_presence": {"label": "Big squad", "fmt": "pts", "help": "Large squads are hard to shift off an objective."},
	"reachability": {"label": "Can get there this turn", "fmt": "pts", "help": "Bonus if reachable with a normal move (or an advance); penalty in round 1 if it cannot arrive by round 2."},
	"firing_position": {"label": "Shooting targets kept", "fmt": "pts", "help": "Whether moving here keeps, gains or loses enemies within weapon range."},
	"threat_delta": {"label": "Danger", "fmt": "pts", "help": "Penalty for moving into more enemy shooting / charge threat than the unit faces now."},
	"overwatch_risk": {"label": "Overwatch risk", "fmt": "pts", "help": "Penalty for moving where enemies can fire Overwatch."},
	"hidden_gain": {"label": "Stays Hidden", "fmt": "pts", "help": "Bonus for ending where the unit stays Hidden."},
	"charge_lane": {"label": "On the way to its charge", "fmt": "pts", "help": "Bonus when the objective lies toward the unit's planned charge target (penalty if opposite)."},
	"shooting_lane": {"label": "Shooting lane", "fmt": "pts", "help": "Bonus when the objective keeps the planned shooting target in range."},
	"primary_awareness": {"label": "Primary mission", "fmt": "pts", "help": "Bonus from this round's primary mission (objective pressure, enemy home, centre, must-hold home)."},
	"plan_earmark": {"label": "Game plan", "fmt": "pts", "help": "Bonus or penalty from the AI's plan for this unit this turn."},
	"secondary_spread": {"label": "Secondary: spread out", "fmt": "pts", "help": "Bonus for entering a table quarter your army does not cover yet."},
	"secondary_zone": {"label": "Secondary: objective zone", "fmt": "pts", "help": "Bonus from an active secondary mission that rewards this objective's zone."},
	"secondary_enemy_push": {"label": "Secondary: push into enemy zone", "fmt": "pts", "help": "Bonus from a secondary mission that rewards being in the enemy deployment zone."},
	"secondary_defend_home": {"label": "Secondary: defend home", "fmt": "pts", "help": "Bonus from a secondary mission that rewards holding your home objective."},
	"secondary_no_mans_land": {"label": "Secondary: no man's land", "fmt": "pts", "help": "Bonus from a secondary mission that rewards no man's land objectives."},
	"secondary_center": {"label": "Secondary: board centre", "fmt": "pts", "help": "Bonus from a secondary mission that rewards the centre of the board."},
	"secondary_edge_flank": {"label": "Secondary: table edge", "fmt": "pts", "help": "Bonus from a secondary mission that rewards the enemy's table edges."},
	"secondary_kill_proximity": {"label": "Secondary: near kill targets", "fmt": "pts", "help": "Bonus for ending near enemies a secondary mission wants killed."},
	"screen_base": {"label": "Screening job", "fmt": "pts", "help": "Base value of using this unit as a screen."},
	"screen_distance": {"label": "Screen distance", "fmt": "pts", "help": "Penalty for how far the unit must go to screen."},
	"denial_priority": {"label": "Deny enemy objective", "fmt": "pts", "help": "How badly the AI wants to stop the enemy taking this objective."},
	"block_base": {"label": "Blocking job", "fmt": "pts", "help": "Base value of blocking an enemy charge or move corridor."},
	"block_priority": {"label": "Block priority", "fmt": "pts", "help": "How important blocking this corridor is."},
	"block_distance": {"label": "Block distance", "fmt": "pts", "help": "Penalty for how far the unit must go to block."},
	# Movement descriptors (NOT part of the sum)
	"expected_vp": {"label": "VP at stake", "fmt": "vp", "good": "high", "help": "Victory points this objective is worth to you over the game."},
	"distance_inches": {"label": "Distance", "fmt": "in", "good": "low", "help": "Distance from the unit to the objective."},
	"turns_to_reach": {"label": "Turns to get there", "fmt": "turns", "good": "low", "help": "Battle turns of movement needed to arrive."},
	"assigned_by": {"label": "Assigned by", "fmt": "text", "hidden": true, "help": "Which planning pass assigned the unit."},

	# --- Shooting -----------------------------------------------------------
	"marginal_value": {"label": "Shot value", "fmt": "num", "good": "high", "hidden": true, "help": "The option's score: damage that counts toward kills × target priority × weapon fit, with overkill discounted."},
	"expected_damage": {"label": "Expected damage", "fmt": "wounds", "good": "high", "help": "Average wounds this weapon deals after hit, wound and save rolls."},
	"target_value": {"label": "Target priority", "fmt": "num", "good": "high", "help": "How much the AI wants this unit dead (points, threat, objective presence). Higher = more wanted."},
	"kill_threshold": {"label": "Wounds left in unit", "fmt": "wounds", "good": "low", "help": "Total wounds remaining across the target unit's models."},
	"already_allocated": {"label": "Damage already assigned", "fmt": "wounds", "good": "low", "help": "Expected damage other weapons are already putting into this target."},
	"efficiency": {"label": "Weapon fit", "fmt": "mult", "good": "high", "help": "How well the weapon suits the target (anti-tank vs vehicles, anti-infantry vs hordes, wasted damage). ×1.0 is neutral."},
	"kill_fraction": {"label": "Share of unit killed", "fmt": "pct", "good": "high", "help": "Expected damage as a share of the target's remaining wounds."},
	"target_hp": {"label": "Wounds left", "fmt": "wounds", "good": "low", "help": "Wounds remaining in the target unit."},
	"hidden_forfeit_cost": {"label": "Cost of losing Hidden", "fmt": "num", "good": "low", "help": "What the unit gives up by revealing itself to shoot."},
	"shoot_worth": {"label": "Value of shooting", "fmt": "num", "good": "high", "help": "Expected value of the shots this unit would make."},
	"net": {"label": "Net", "fmt": "num", "good": "high", "hidden": true, "help": "Value of this choice minus the alternative."},

	# --- Charge / fight -----------------------------------------------------
	"charge_probability": {"label": "Chance to make the charge", "fmt": "pct", "good": "high", "help": "Probability the 2D6 charge roll covers the distance."},
	"melee_damage": {"label": "Expected melee damage", "fmt": "wounds", "good": "high", "help": "Average wounds the unit deals in melee against this target."},
	"distance": {"label": "Distance", "fmt": "in", "good": "low", "help": "Distance to the target."},
	"strategic_value": {"label": "Strategic value", "fmt": "num", "good": "high", "help": "Extra value beyond damage (objective holders, characters, threats)."},

	# --- Deployment / formations / reserves / secondaries --------------------
	"plan": {"label": "Follows deployment plan", "fmt": "num", "hidden": true, "help": "Chosen from the AI's pre-built deployment plan."},
	"wounds": {"label": "Wounds", "fmt": "wounds", "good": "high", "help": "Total wounds of the unit."},
	"attached_to_bodyguard": {"label": "Leading a unit", "fmt": "num", "good": "high", "help": "Bonus when the character is attached to a bodyguard unit."},
	"pairing_synergy": {"label": "Leader–unit synergy", "fmt": "num", "good": "high", "help": "How well the leader's abilities suit the unit it joins."},
	"reserve_value": {"label": "Value in reserve", "fmt": "num", "good": "high", "help": "How much the unit gains from arriving later via reserves / deep strike."},
	"board_presence_penalty": {"label": "Board presence lost", "fmt": "num", "good": "low", "help": "Cost of leaving the board thin while the unit is in reserve."},
	"objective_proximity": {"label": "Near objectives", "fmt": "num", "good": "high", "help": "Bonus for deploying close to objectives."},
	"crowding": {"label": "Crowding", "fmt": "num", "good": "high", "help": "Penalty for deploying on top of friendly units."},
	"achievability": {"label": "Chance to achieve", "fmt": "num", "good": "high", "help": "How achievable this secondary mission looks right now."},
	"discard_value": {"label": "Value of discarding", "fmt": "num", "good": "high", "help": "Value of discarding this secondary card."},
	"discard_threshold": {"label": "Discard threshold", "fmt": "num", "help": "Cards scoring below this are discarded."},
}

# Context keys worth showing to a player (everything else is developer-only).
const CONTEXT_LABELS := {
	"round": "Battle round",
	"weapon_id": "Weapon",
	"assign_action": "Planned action",
	"source": "Picked by",
	"targets_considered": "Targets considered",
}

const MULT_WORDS := [[0.5, "very poor"], [0.8, "poor"], [1.2, "neutral"], [1.4, "good"], [INF, "great"]]


static func has_term(key: String) -> bool:
	return TERMS.has(key)


static func info(key: String) -> Dictionary:
	return TERMS.get(key, {})


static func label(key: String) -> String:
	var e: Dictionary = TERMS.get(key, {})
	if e.has("label"):
		return str(e.label)
	return key.replace("_", " ").capitalize()


static func help(key: String) -> String:
	return str(TERMS.get(key, {}).get("help", "No description yet (internal value '%s')." % key))


static func is_hidden(key: String) -> bool:
	return bool(TERMS.get(key, {}).get("hidden", false))


static func good_direction(key: String) -> String:
	return str(TERMS.get(key, {}).get("good", ""))


static func format_value(key: String, v) -> String:
	var fmt := str(TERMS.get(key, {}).get("fmt", "num"))
	if not (v is float or v is int):
		return str(v)
	var f := float(v)
	match fmt:
		"pts":
			return "%+.1f" % f
		"in":
			return "%.1f\"" % f
		"wounds":
			return ("%.1f" if absf(f) < 10.0 else "%.0f") % f
		"pct":
			return "%d%%" % roundi(f * 100.0)
		"mult":
			return "×%.2f (%s)" % [f, mult_word(f)]
		"turns":
			return "%d" % roundi(f)
		"vp":
			return "%.1f VP" % f
	return ("%.2f" if absf(f) < 10.0 else "%.1f") % f


static func mult_word(f: float) -> String:
	for pair in MULT_WORDS:
		if f < float(pair[0]):
			return str(pair[1])
	return "great"
