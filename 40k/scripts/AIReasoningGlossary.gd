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
#   sum     — true for a value that is added into the score even though it
#             is printed with a unit (Warlord: wounds + bodyguard bonus)
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
	"target_value": {"label": "Target priority", "fmt": "num", "good": "high", "help": "How much the AI wants this unit dead: its points, damage output, objective presence and OC, buffs it gives, CHARACTER/VEHICLE/MONSTER, and how wounded it is. Raised when the AI is behind on VP and the target holds an objective; cut when the AI plans to charge it instead."},
	"kill_threshold": {"label": "Wounds left in unit", "fmt": "wounds", "good": "low", "help": "Total wounds remaining across the target unit's models."},
	"already_allocated": {"label": "Damage already assigned", "fmt": "wounds", "good": "low", "help": "Expected damage other weapons are already putting into this target."},
	"efficiency": {"label": "Weapon fit", "fmt": "mult", "good": "high", "help": "How well the weapon suits the target (anti-tank vs vehicles, anti-infantry vs hordes, wasted damage). ×1.0 is neutral."},
	"kill_fraction": {"label": "Share of unit killed", "fmt": "pct", "good": "high", "help": "Expected damage as a share of the target's remaining wounds."},
	"target_hp": {"label": "Wounds left", "fmt": "wounds", "good": "low", "help": "Wounds remaining in the target unit."},
	"hidden_forfeit_cost": {"label": "Cost of losing Hidden", "fmt": "num", "good": "low", "help": "Shooting removes Hidden for this turn and the next. Cost = the Hidden penalty setting × the share of enemies the unit is currently hidden from (0 if it already shot or is not Hidden)."},
	"shoot_worth": {"label": "Value of shooting", "fmt": "num", "good": "high", "help": "10 per target fully destroyed: for each target, the share of its remaining wounds the shots should remove (capped at 1), summed and × 10."},
	"net": {"label": "Advantage over the other option", "fmt": "num", "good": "high", "help": "This option's value minus the other option's (hold fire: cost of losing Hidden − value of shooting; shoot: the reverse)."},

	# --- Charge / fight -----------------------------------------------------
	"charge_probability": {"label": "Chance to make the charge", "fmt": "pct", "good": "high", "help": "Probability the 2D6 charge roll reaches the target, including extra distance for climbing terrain."},
	"melee_damage": {"label": "Expected melee damage", "fmt": "wounds", "good": "high", "help": "Average wounds the unit deals in melee against this target (best weapon, after hit/wound/save rolls)."},
	"charge_target_value": {"label": "Value if the charge lands", "fmt": "num", "good": "high", "help": "Expected melee damage × damage weight, plus bonuses (target below half strength, CHARACTER, long-range shooter to tie up, the AI's plan) minus a penalty if it cannot hurt the target. The final score is this × chance to make the charge × short-charge, on-objective and Overwatch-risk multipliers."},
	"distance": {"label": "Distance", "fmt": "in", "good": "low", "help": "Distance to the target."},
	# Fight score ledger (sum == score), from _score_fight_target
	"fight_damage": {"label": "Damage it deals", "fmt": "pts", "help": "Expected melee damage × the damage weight (2 by default) — the main factor."},
	"fight_target_below_half": {"label": "Target already below half", "fmt": "pts", "help": "Bonus when fewer than half the target's models are left (easier to finish, denies points)."},
	"fight_character": {"label": "Target is a CHARACTER", "fmt": "pts", "help": "Bonus for attacking a CHARACTER."},
	"plan_hunt": {"label": "Game plan: hunt characters", "fmt": "pts", "help": "Extra bonus when the AI's plan earmarks this unit to hunt CHARACTERs."},
	"fight_cant_hurt": {"label": "Can barely hurt it", "fmt": "pts", "help": "Penalty when expected damage is under 1 wound."},
	"fight_can_wipe": {"label": "Can wipe it out", "fmt": "pts", "help": "Bonus when expected damage is at least the target's remaining wounds."},
	"fight_can_halve": {"label": "Can take it below half", "fmt": "pts", "help": "Bonus when expected damage is at least half the target's remaining wounds (but not enough to wipe it)."},
	"fight_overkill": {"label": "Overkill", "fmt": "pts", "help": "Penalty when expected damage is more than 3× the target's remaining wounds."},
	"fight_lock_shooter": {"label": "Ties up a shooter", "fmt": "pts", "help": "Bonus for keeping a long-range (24\"+) or dangerous shooting unit locked in combat."},
	"fight_target_on_objective": {"label": "Target on an objective", "fmt": "pts", "help": "Bonus when the target stands on an objective."},
	"fight_low_toughness": {"label": "Low Toughness target", "fmt": "pts", "help": "Bonus when the target's Toughness is 3 or less."},
	"fight_target_defences": {"label": "Target's defensive abilities", "fmt": "pts", "help": "Reduction because the target has defensive abilities (Feel No Pain, -1 to wound, etc.): the score so far is divided by their strength."},
	"fight_points_trade": {"label": "Points trade", "fmt": "pts", "help": "Scaling for the points trade: up when the target's points-per-wound is higher than the attacker's, down when lower (Competitive difficulty only)."},
	"fight_finish_off": {"label": "Finishes what others started", "fmt": "pts", "help": "Bonus when units that already fought this phase damaged the target and this unit can finish or nearly finish it (bigger for 10+ model hordes)."},
	"fight_already_overkilled": {"label": "Already dead to earlier attacks", "fmt": "pts", "help": "Penalty when earlier fighters this phase already dealt enough damage to kill it."},
	"fight_gang_up": {"label": "Starts a gang-up", "fmt": "pts", "help": "Horde units only: bonus when other friendly units are also engaged with this target, so attacks concentrate on it."},
	"fight_floor_zero": {"label": "Raised to 0", "fmt": "pts", "help": "Fight scores never go below 0; this cancels the negative remainder."},
	"strategic_value": {"label": "Non-damage bonuses and penalties (older records)", "fmt": "num", "good": "high", "help": "The fight score minus expected damage × damage weight: bonuses for CHARACTERs, a unit below half strength, being able to wipe it or halve it, a target on an objective, low Toughness, locking long-range or dangerous shooters, and finishing what another unit started; penalties for overkill or not being able to hurt it. Also absorbs scaling for the target's defensive abilities and the points trade."},

	# --- Deployment / formations / reserves / secondaries --------------------
	"plan": {"label": "Follows deployment plan", "fmt": "num", "hidden": true, "help": "Chosen from the AI's pre-built deployment plan."},
	"wounds": {"label": "Wounds", "fmt": "wounds", "sum": true, "good": "high", "help": "The character's Wounds characteristic: tougher characters make safer Warlords."},
	"attached_to_bodyguard": {"label": "Protected by a bodyguard", "fmt": "pts", "help": "Bonus when the character is leading a unit, so the bodyguard protects the Warlord."},
	"pairing_synergy": {"label": "Leader–unit synergy", "fmt": "num", "good": "high", "help": "How much the leader improves this unit: its ranged, melee and defensive buff multipliers, weighted by the unit's model count and points, plus tactical rules (fall back and still charge/shoot, advance and charge)."},
	"reserve_value": {"label": "Value in reserve", "fmt": "pts", "help": "How much the unit gains from arriving later: Deep Strike melee units most, then flexible short-range shooters and Strategic Reserves melee (flank entry). Long-range shooters, vehicles/monsters and leaders score low."},
	"board_presence_penalty": {"label": "Board presence lost", "fmt": "pts", "help": "Penalty when reserving leaves fewer units on the table than objectives + 2 (1.5 per unit short), plus 1 per 100 pts of Strategic Reserves above 25% of the army."},
	"points": {"label": "Points", "fmt": "num", "help": "Points value leaving the table (unit plus attached leaders)."},
	"objective_proximity": {"label": "Near objectives", "fmt": "pts", "help": "24 minus the distance in inches to the nearest objective (0 when 24\" or more away)."},
	"crowding": {"label": "Crowding", "fmt": "pts", "help": "Penalty for standing near friendly units already deployed: 6 minus the gap in inches, for each one closer than 6\"."},
	"achievability": {"label": "How achievable (0–1)", "fmt": "num", "good": "low", "help": "The AI's estimate from the board: 0 = impossible, under 0.2 = extremely unlikely, 0.2–0.5 = difficult, 0.5+ = reasonably achievable. Less achievable cards are better to discard."},
	"discard_value": {"label": "Value of discarding", "fmt": "num", "hidden": true, "help": "Minus the achievability: the option's score."},
	"discard_threshold": {"label": "Discard below", "fmt": "num", "help": "A card is only discarded if its achievability is below this: 0.2, or 0.1 in round 4+ when the deck is empty."},
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


static func is_addend(key: String) -> bool:
	"""Part of an additive ledger: printed as score points, or flagged `sum`.
	Unlabelled keys count too — new _t_add terms are the common case."""
	var e: Dictionary = TERMS.get(key, {})
	return str(e.get("fmt", "pts")) == "pts" or bool(e.get("sum", false))


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
