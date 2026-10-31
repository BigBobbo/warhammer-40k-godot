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
	"contest_race": {"label": "Enemy gets there first", "fmt": "pts", "help": "Cut when the enemy can have at least this unit's OC on the objective before it arrives."},
	"distance_penalty": {"label": "Distance cost", "fmt": "pts", "help": "Penalty for each extra turn needed to get there — a share of the objective's value per turn."},
	"reach_horizon": {"label": "Rounds left to score", "fmt": "pts", "help": "Reduced when the unit would arrive too late to score here in the remaining rounds."},
	"stay_on_objective": {"label": "Already holding it", "fmt": "pts", "help": "Bonus for staying on an objective the unit already holds."},
	"horde_presence": {"label": "Big squad", "fmt": "pts", "help": "Large squads are hard to shift off an objective."},
	"reachability": {"label": "Can get there this turn", "fmt": "pts", "help": "Bonus if reachable with a normal move (or an advance); penalty in round 1 if it cannot arrive by round 2."},
	"firing_position": {"label": "Shooting targets kept", "fmt": "pts", "help": "Whether moving here keeps, gains or loses enemies within weapon range."},
	"threat_delta": {"label": "Danger", "fmt": "pts", "help": "Penalty for moving into more enemy shooting / charge threat than the unit faces now."},
	"overwatch_risk": {"label": "Overwatch risk", "fmt": "pts", "help": "Penalty for moving where enemies can fire Overwatch."},
	"hidden_gain": {"label": "Stays Hidden", "fmt": "pts", "help": "Bonus for ending where the unit stays Hidden."},
	"charge_lane": {"label": "On the way to its charge", "fmt": "pts", "help": "Bonus when the objective lies toward the unit's planned charge target (penalty if opposite)."},
	"charge_damage": {"label": "Charge: expected damage", "fmt": "pts", "help": "Expected melee wounds on the target if the charge connects, times the chance it connects (Move/Advance then 2D6)."},
	"charge_lock_shooter": {"label": "Charge: locks a dangerous shooter", "fmt": "pts", "help": "Bonus for tying up an enemy shooter the plan wants locked in combat, times the chance the charge connects."},
	"charge_objective": {"label": "Charge: target holds an objective", "fmt": "pts", "help": "Share of the objective the target stands on, times the chance the charge connects."},
	"shooting_forfeited": {"label": "Advancing gives up shooting", "fmt": "pts", "help": "Penalty: Advancing without advance-and-shoot means this unit cannot shoot this turn."},
	"failed_charge_danger": {"label": "Danger if the charge fails", "fmt": "pts", "help": "Threat at the spot the move ends, times the chance the charge falls short."},
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
	"gap_inches": {"label": "Gap to close", "fmt": "in", "good": "low", "help": "How far the unit's nearest model still has to move to be on the objective (touching its terrain area, or within 3\" of an open-ground marker)."},
	"charge_chance": {"label": "Chance the charge connects", "fmt": "pct", "good": "high", "help": "Chance the move (plus the Advance D6 if advancing) and the 2D6 charge roll together reach the target, from the closest models' edge distance."},
	"adv_chance": {"label": "Advance roll gets there", "fmt": "pct", "good": "high", "help": "Chance an Advance (Move + D6) gets a model onto the objective this turn when a normal Move falls short."},
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
	# Fight ORDER ledger (which unit activates next), from _score_fighter_priority
	"order_damage": {"label": "Damage it would deal", "fmt": "pts", "help": "Expected melee damage against its best engaged target × the order damage weight (1 by default)."},
	"order_can_wipe": {"label": "Can wipe its target first", "fmt": "pts", "help": "Bonus when it can destroy its target outright, removing that unit before it fights back."},
	"order_half_kill": {"label": "Can halve its target", "fmt": "pts", "help": "Bonus when it can take its target below half its remaining wounds (but not wipe it)."},
	"order_character": {"label": "Target is a CHARACTER", "fmt": "pts", "help": "Bonus when its best target is a CHARACTER."},
	"order_dangerous_shooter": {"label": "Target is a dangerous shooter", "fmt": "pts", "help": "Bonus when its best target has dangerous ranged output."},
	"order_target_on_objective": {"label": "Target on an objective", "fmt": "pts", "help": "Bonus when its best target stands on an objective."},
	"order_likely_to_die": {"label": "Likely to die before it fights", "fmt": "pts", "help": "Bonus when the enemies engaged with it can deal 75%+ of its remaining wounds — fight now to get value from it."},
	"order_badly_hurt": {"label": "Will be badly hurt", "fmt": "pts", "help": "Smaller bonus when the enemies engaged with it can deal 50–75% of its remaining wounds."},
	"order_overkill": {"label": "Overkill — let others go first", "fmt": "pts", "help": "Penalty when its damage is over 2.5× its target's remaining wounds."},
	"order_cant_hurt": {"label": "Can barely hurt anything", "fmt": "pts", "help": "Expected damage under 0.1: the priority is a flat 0.5."},
	"order_melee_buffs": {"label": "Melee buffs", "fmt": "pts", "help": "Scaling from abilities that boost its melee attacks (leaders, auras)."},
	"order_round_aggression": {"label": "Round / army aggression", "fmt": "pts", "help": "Scaling by how aggressive the AI plays this battle round with this army."},
	"difficulty_noise": {"label": "Difficulty randomness", "fmt": "pts", "help": "Random noise added at lower difficulties to make the AI less exact."},
	# Charge — 'no charge' option
	"charge_threshold": {"label": "Minimum worth charging", "fmt": "num", "help": "A charge is only declared if its score beats this (1.0, lowered when behind on VP, by faction aggression and by difficulty)."},
	# Stratagem windows / reactive stratagems
	"stratagem_value": {"label": "Stratagem value", "fmt": "pts", "help": "How much this stratagem would achieve on this unit right now, from its codex handler (offensive: extra damage; defensive: damage prevented × the unit's worth)."},
	"paid_cp_penalty": {"label": "Costs CP", "fmt": "pts", "help": "Paid stratagems rank 1 lower than a free ability with a similar effect."},
	"cp_cost": {"label": "CP cost", "fmt": "num", "help": "Command points it costs."},
	"use_threshold": {"label": "Bar to use it", "fmt": "num", "help": "Minimum value to spend the CP: 1.5 × CP cost for defensive, 2 for offensive/utility (offensive also needs 2+ CP so one is kept for reactions), 1 for free abilities."},
	"cp_available": {"label": "CP available", "fmt": "num", "help": "Command points the player has."},
	# Scout objective choice (_find_best_scout_objective)
	"scout_obj_control": {"label": "Who holds it", "fmt": "pts", "help": "+10 nobody controls it, +7 the enemy holds it (get there first), +5 contested, −5 you already hold it."},
	"scout_no_mans_land": {"label": "In no man's land", "fmt": "pts", "help": "Bonus for an objective in no man's land."},
	"scout_home_objective": {"label": "Your home objective", "fmt": "pts", "help": "Penalty: your home objective is already close, so scouting toward it gains little."},
	"scout_enemy_home": {"label": "Enemy home objective", "fmt": "pts", "help": "Penalty: don't rush the enemy's home objective with a scout."},
	"scout_distance": {"label": "Distance", "fmt": "pts", "help": "Penalty per inch to the objective (0.3 per inch by default)."},
	# Reserves arrival order (_score_reserves_deployment)
	"arrive_points": {"label": "Unit's points", "fmt": "pts", "help": "Points ÷ 50: expensive units have more impact, so they come in first."},
	"arrive_deep_strike": {"label": "Deep Strike", "fmt": "pts", "help": "Bonus for Deep Strike units (more flexible placement)."},
	"arrive_melee": {"label": "Has melee weapons", "fmt": "pts", "help": "Bonus: can charge the turn after arriving."},
	"arrive_ranged": {"label": "Has ranged weapons", "fmt": "pts", "help": "Bonus: can shoot right after arriving."},
	"arrive_round_urgency": {"label": "Running out of rounds", "fmt": "pts", "help": "+2 in round 3, +5 from round 4 — units still in reserve at the end of the battle count as destroyed."},
	"arrive_objectives": {"label": "Objectives in play", "fmt": "pts", "help": "+1.5 per contested/enemy-held objective, +0.5 per open one. Note: this counts objectives board-wide, so it is the same for every unit and never changes which unit arrives."},
	# Disembark
	"disembark_value": {"label": "Value of getting out", "fmt": "num", "good": "high", "help": "How much disembarking helps now (objective reach, charge/shoot opportunities, transport danger). Anything above 0 beats staying embarked."},
	# Shooting target priority (_calculate_target_value), multipliers booked as the change they made
	"tv_base": {"label": "Base", "fmt": "pts", "help": "Every target starts at 1."},
	"tv_points": {"label": "Points cost", "fmt": "pts", "help": "Points × 0.01: expensive units are worth more to kill."},
	"tv_points_per_wound": {"label": "Points per wound", "fmt": "pts", "help": "Expensive-per-wound models (vs 25 pts/wound) are better trades."},
	"tv_ranged_threat": {"label": "Its shooting threat", "fmt": "pts", "help": "Expected ranged damage it deals (vs T4 Sv3+) × weight."},
	"tv_melee_threat": {"label": "Its melee threat", "fmt": "pts", "help": "Expected melee damage it deals (vs T4 Sv3+) × weight."},
	"tv_buffs": {"label": "Its buffs", "fmt": "pts", "help": "Bonus when abilities (e.g. an attached leader) boost its attacks."},
	"tv_hard_to_kill": {"label": "Hard to kill", "fmt": "pts", "help": "Penalty when defensive abilities (Feel No Pain, invulnerable saves…) make it harder to kill."},
	"tv_character": {"label": "CHARACTER", "fmt": "pts", "help": "×1.3 for a character, more if it is leading (buffing) a unit."},
	"tv_vehicle_monster": {"label": "VEHICLE / MONSTER", "fmt": "pts", "help": "×1.2."},
	"tv_wounded": {"label": "Below half strength", "fmt": "pts", "help": "Bonus for finishing off a unit that has lost over half its models."},
	"tv_on_objective": {"label": "On an objective", "fmt": "pts", "help": "×1.4 plus its OC, more in round 4+."},
	"tv_near_objective": {"label": "Near an objective", "fmt": "pts", "help": "×1.15 plus a little for its OC."},
	"tv_regains_hidden": {"label": "About to regain Hidden", "fmt": "pts", "help": "Shoot it while it can still be targeted."},
	"tv_secondary_target": {"label": "Secondary mission target", "fmt": "pts", "help": "Bonus when killing it scores one of your secondaries (kill keywords, Marked for Death, big units)."},
	"tv_primary_kills": {"label": "Primary rewards kills", "fmt": "pts", "help": "×1.15 when this round's primary mission scores kills."},
	"tv_round_aggression": {"label": "Round / army aggression", "fmt": "pts", "help": "Scaling by how aggressive the AI plays this round with this army."},
	"tv_behind_on_vp": {"label": "Behind on VP", "fmt": "pts", "help": "When behind, targets on objectives are worth more (clear them to score)."},
	"tv_planned_charge_target": {"label": "Planned charge target", "fmt": "pts", "help": "Reduced: the AI plans to charge it, so it leaves it for melee."},
	# Charge score (_score_charge_target + the chance/multiplier chain)
	"ch_damage": {"label": "Melee damage it would deal", "fmt": "pts", "help": "Expected melee damage × the charge damage weight."},
	"ch_below_half": {"label": "Target below half strength", "fmt": "pts", "help": "Bonus when the target has lost over half its models."},
	"ch_character": {"label": "Target is a CHARACTER", "fmt": "pts", "help": "Bonus for charging a CHARACTER."},
	"ch_cant_hurt": {"label": "Can barely hurt it", "fmt": "pts", "help": "Penalty when expected melee damage is under 1 wound."},
	"ch_tie_up_shooter": {"label": "Ties up a shooter", "fmt": "pts", "help": "Bonus for locking a 24\"+ shooter in combat."},
	"ch_plan_lock_shooter": {"label": "Game plan: lock this shooter", "fmt": "pts", "help": "The AI's turn plan wants this dangerous shooter locked in combat."},
	"ch_low_toughness": {"label": "Low Toughness target", "fmt": "pts", "help": "Bonus when the target's Toughness is 3 or less."},
	"ch_melee_buffs": {"label": "Melee buffs", "fmt": "pts", "help": "Scaling from abilities boosting the charger's melee."},
	"ch_target_defences": {"label": "Target's defensive abilities", "fmt": "pts", "help": "Reduction for the target's Feel No Pain, invulnerable saves, etc."},
	"ch_points_trade": {"label": "Points trade", "fmt": "pts", "help": "Scaling for the points-per-wound trade (Competitive difficulty only)."},
	"ch_gang_up": {"label": "Gang up", "fmt": "pts", "help": "Bonus for concentrating charges: a friendly unit is already fighting it, other units can charge it too, or combined damage can kill it."},
	"ch_can_halve": {"label": "Can take it below half", "fmt": "pts", "help": "Bonus when expected damage is half its remaining wounds or more."},
	"ch_can_wipe": {"label": "Can wipe it out", "fmt": "pts", "help": "Extra bonus when expected damage is enough to destroy it."},
	"ch_deadly_demise": {"label": "Doomed with Deadly Demise", "fmt": "pts", "help": "A doomed vehicle with Deadly Demise wants to explode next to enemies."},
	"ch_chance": {"label": "Charge may fail", "fmt": "pts", "help": "Reduction: the value is multiplied by the chance the 2D6 roll gets there (including terrain). The biggest reduction for long charges."},
	"ch_melee_capable": {"label": "Melee weapons & buffs", "fmt": "pts", "help": "Units without melee weapons keep only 30% of the value; melee buffs from abilities (leaders, auras) raise it."},
	"ch_short_charge": {"label": "Short, reliable charge", "fmt": "pts", "help": "Bonus for charges needing 6\" or less (more for 3\" or less)."},
	"ch_target_on_objective": {"label": "Target on an objective", "fmt": "pts", "help": "Bonus for charging onto an objective (more in round 4+)."},
	"ch_overwatch_risk": {"label": "Overwatch risk", "fmt": "pts", "help": "Reduction for the expected Overwatch damage on the way in."},
	# Reserves value (_score_unit_for_reserves)
	"res_deep_strike_fit": {"label": "Suits Deep Strike", "fmt": "pts", "help": "Melee units gain most, then short-range shooters; long-range shooters gain little."},
	"res_flank_fit": {"label": "Suits Strategic Reserves", "fmt": "pts", "help": "Flank entry: good for melee, fine for short range, poor for units that want to shoot turn 1."},
	"res_speed": {"label": "Fast unit", "fmt": "pts", "help": "Units moving 8\"+ (more for 10\" and 12\") make good use of a board-edge arrival."},
	"res_points": {"label": "Points", "fmt": "pts", "help": "Expensive units gain more from a safe, well-timed arrival (capped)."},
	"res_vehicle_monster": {"label": "VEHICLE / MONSTER", "fmt": "pts", "help": "Penalty: big units generally want table presence (smaller for melee ones)."},
	"res_long_range": {"label": "Long-range platform", "fmt": "pts", "help": "Penalty: heavy ranged units want to shoot from turn 1."},
	"res_cheap_screen": {"label": "Cheap screen", "fmt": "pts", "help": "Penalty: cheap units are better as turn-1 screens."},
	# Deployment spot (_find_terrain_aware_position)
	"deploy_terrain": {"label": "Terrain fit for its role", "fmt": "pts", "help": "How well the terrain suits the unit's role (cover, line of sight, height)."},
	"deploy_objectives": {"label": "Near objectives", "fmt": "pts", "help": "Up to +1 per objective within 10\"."},
	"deploy_depth": {"label": "Front / back preference", "fmt": "pts", "help": "Melee units like the front edge; characters and fragile shooters like the back."},
	"deploy_drift": {"label": "Drift from the column layout", "fmt": "pts", "help": "−1 per 5\" away from its planned column spot (stops the army bunching up)."},
	"deploy_baseline_bar": {"label": "Bar a terrain spot must beat", "fmt": "num", "help": "The column-layout spot is used unless a terrain spot scores 1.0 or more."},
	# Heroic Intervention (evaluate_heroic_intervention)
	"hi_unit_value": {"label": "How strong the unit is", "fmt": "pts", "help": "Half the unit's estimated value: stronger units make better counter-chargers."},
	"hi_character": {"label": "CHARACTER", "fmt": "pts", "help": "+2: characters usually fight well."},
	"hi_monster": {"label": "MONSTER", "fmt": "pts", "help": "+1."},
	"hi_enemy_value": {"label": "Enemy worth intervening against", "fmt": "pts", "help": "×1.3 against a valuable enemy (value 5+), ×0.7 against a cheap one (2 or less), unchanged in between."},
	"hi_charger_value": {"label": "Enemy's value", "fmt": "num", "help": "Estimated value of the enemy this unit would charge (11e: the closest enemy that charged within 12\", else the closest within 6\")."},
	# Fire Overwatch (evaluate_fire_overwatch)
	"ow_shots": {"label": "Ranged shots", "fmt": "num", "help": "Total ranged shots the unit can fire."},
	"ow_expected_hits": {"label": "Expected hits (6s only)", "fmt": "num", "good": "high", "help": "Shots ÷ 6: Overwatch only hits on unmodified 6s."},
	"ow_target_value": {"label": "Target's value", "fmt": "num", "help": "Estimated value of the enemy unit being shot."},
	"ow_hits_bar": {"label": "Hits needed", "fmt": "num", "help": "Overwatch is only fired for 0.5+ expected hits…"},
	"ow_value_bar": {"label": "Target value needed", "fmt": "num", "help": "…on a target worth 2 or more."},
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
	"reason": "Why",
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
			return ("%+.2f" if absf(f) < 1.0 else "%+.1f") % f
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
