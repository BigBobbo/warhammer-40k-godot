# How the AI Decides: the MOVEMENT Phase

All file references are to the repo at `/home/user/warhammer-40k-godot`. The main file is
`40k/scripts/AIDecisionMaker.gd` (24,318 lines, all static); entry is via the autoload
`40k/autoloads/AIPlayer.gd`, which calls `AIDecisionMaker.decide(...)`
(AIDecisionMaker.gd:2965) every time the engine asks the AI for its next action.

**Are the defaults overridden?** `40k/data/ai_config.json` was checked: its `parameters`
block contains only `"PLANS_ENABLED": 1`, which is already the code default
(AIDecisionMaker.gd:421 reads `get_param("PLANS_ENABLED", 1.0)`). **So every value in this
dossier is the effective value** — the code-default constants are what actually runs.
(Resolution order for any weight: per-context rule overrides > per-player profile >
`ai_config.json` > code constant — AIDecisionMaker.gd:1235-1256. No profile or rule file
ships enabled by default.)

---

## Overview

Once per movement phase the AI writes an army-wide "battle plan" and then executes it one
unit at a time, so the plan it announces in the game log is the plan it actually follows.
First it prices every objective marker on the board: a marker nobody holds is worth 10
points of priority, a contested one 8, an enemy-held-but-flippable one 7, and on top of
that it adds the *actual victory points* the marker would pay at the next scoring point
(read from the mission cards, at 1.2 priority points per VP) plus urgency, denial and
retention bonuses that shift with the battle round. Next it scores every (unit, objective)
pairing — objective priority, how efficiently the unit's Objective Control stat fills the
need there, a distance penalty of 2 per extra turn of marching, bonuses for staying on a
marker it already holds, keeping enemies in gun range, and penalties for walking into
enemy charge/shooting threat zones — and greedily assigns units in several passes: holders
first, then capturers, then melee units converted to "attack" orders with someone else
back-filled onto their marker, then cheap units sent to screen deep-strikes or block
corridors, and finally leftovers spread out as support. Only then does it pick the actual
spot on the table: a straight line toward the target, bent around terrain, nudged toward
cover, pulled sideways out of threat zones, and finally squeezed through a collision
ladder that tries shorter and shorter moves at more and more angles so every model lands
legally and in formation. Advance is chosen when the extra ~2" is needed and the unit
loses nothing by it; Fall Back decisions for units stuck in combat weigh the objective-control
math against expected melee damage; Remain Stationary wins when the unit already holds its
marker, would lose all its shooting targets, or has Heavy weapons worth the +1 to hit.
Difficulty changes how sharp all this is: Easy plays randomly, Normal adds mild score
noise, Hard adds multi-phase (charge/lock) planning, Competitive removes all noise.

---

## Decision flow (in code order)

### A. `decide()` entry — AIDecisionMaker.gd:2965-3130
1. Sets current difficulty/player, evaluates any profile rules, clears the thinking log.
2. **Easy difficulty short-circuit**: `use_random_actions` → `_decide_random(...)` picks a
   random legal action; none of the logic below runs (AIDecisionMaker.gd:3046-3048,
   AIDifficultyConfig.gd:23-24).
3. Phase-change housekeeping: leaving the movement phase clears the committed battle plan
   (`_turn_movement_plan.clear()`, AIDecisionMaker.gd:3077-3082); a new round clears the
   multi-phase plan, movement intents and the battle plan (AIDecisionMaker.gd:3087-3094).
4. Below Hard difficulty, `_phase_plan_built[player] = true` is pre-set so the
   charge-intent/lock-target plan is never built (AIDecisionMaker.gd:3111-3112).
5. Dispatches to `_decide_movement` for the movement phase (AIDecisionMaker.gd:3115+).

### B. `_decide_movement()` — AIDecisionMaker.gd:6524-6697 (steps run in this order; the first that applies returns)
1. **Step 0** — pending Command Re-roll window (advance rolls): fallback is to decline
   (AIDecisionMaker.gd:6534-6544; the real evaluation happens in AIPlayer's signal handler).
2. **Step 0.5/0.6** — free heal windows (Sawbonez, Grot Oiler, Mekaniak): always used, on
   the most-wounded offered model (AIDecisionMaker.gd:6551-6602).
3. **Step 0.7** — free mortal-wound windows (Deff From Above, Quicksilver Execution):
   always used, on the best grenade-style target (AIDecisionMaker.gd:6607-6632).
4. **Step 0.8** — Kunnin' Infiltrator redeploy is declined (no click pathway)
   (AIDecisionMaker.gd:6637-6644).
5. **Step 1** — a staged move waiting for confirmation is confirmed
   (AIDecisionMaker.gd:6648-6655).
6. **Step 1.5** — reserves arrive before anything else moves (`_decide_reserves_arrival`,
   AIDecisionMaker.gd:6660-6663, function at 7429).
7. **Step 1.75** — transports are checked for disembarks before moving
   (`_decide_transport_disembark`, AIDecisionMaker.gd:6668-6670, function at 8044).
8. **Step 2** — if any unit can still begin a move → `_select_movement_action`
   (AIDecisionMaker.gd:6680-6694). The chosen decision gets its battle-plan assignment
   attached and is finalized (intent recorded, decision card emitted) via
   `_finalize_movement_decision` (AIDecisionMaker.gd:3784).
9. **Step 3** — otherwise `END_MOVEMENT` (AIDecisionMaker.gd:6697).

### C. `_select_movement_action()` — AIDecisionMaker.gd:6699-7423
1. Collect movable units and their legal move types (6700-6712).
2. **Build the multi-phase plan once per phase** (Hard+ only): which units intend to
   charge, which enemy shooters to lock in melee, shooting lanes (6722-6735, plan builder
   at 3573).
3. Build secondary-mission and primary-mission awareness if the command phase didn't
   (6741-6760).
4. Try proactive movement-phase faction stratagems ('Ere We Go, Vigilance Eternal,
   Multipotentiality) (6765-6767).
5. **Threat data** (Normal+ only): per enemy unit, a charge-threat radius (Move + 12"
   charge + engagement range) and shooting radius (max weapon range), weighted by a
   0.3-3.0 danger rating (6773-6781, builder at 23893).
6. **THE COMMITTED PLAN (`_turn_movement_plan`)** (6791-6855):
   - The stored plan is **reused** if it is from this battle round and every currently
     movable, non-engaged unit still has an *unconsumed* entry in it.
   - **Replan for cause** only: (a) a unit not in the plan became movable (e.g. a fresh
     disembark) — "X became movable after the plan was made"; (b) a unit whose entry was
     already consumed is movable again (failed move re-offered / reload) — "X is movable
     again after already acting" (6801-6811). The replan is narrated
     (`Re-planning movement: …`, 6851-6853) and a `replans` counter is kept (6848).
   - When (re)planning: **Phase 1** `_evaluate_all_objectives` (8510), **Phase 2**
     `_assign_units_to_objectives` (8775). The plan stores round, assignments, a
     consumed-set, and an "announce" block (round strategy label, army archetype label,
     VP-stakes line, charge intents, lock targets) (6825-6850).
7. Log the plan once: header "Movement plan (Round N…)", VP stakes, charge/lock lines,
   then up to 12 per-unit order lines sorted by score (6873-6949).
8. **Engaged units first** (can only Fall Back or stand): `_decide_engaged_unit` (6952-6958,
   function at 9750 — see section G).
9. **Ordering of everyone else** (6964-6988): disembarked units first (tier 0), loaded
   transport VEHICLEs last (tier 2), then front-to-back (closest to the enemy side moves
   first when >2" apart in Y), ties broken by assignment score **with difficulty noise
   applied** (`_apply_difficulty_noise`, 2071-2077: ±1.5 Normal, ±0.5 Hard, 0 Competitive,
   ±100 Easy — though Easy never reaches here).
10. **Per-unit execution** (6990-7421), branching on the assignment's action:
    - `hold` → REMAIN_STATIONARY (with an optional Lions-of-the-Emperor spacing shuffle)
      (7007-7023).
    - `advance` → destination computed with Move + 2" (average advance roll)
      (7027-7045).
    - `attack` (melee seeker) → move or advance straight at the target with **threat
      avoidance disabled** ("melee units WANT to be close") (7052-7096).
    - `screen` → move to the screen/denial/block position; hold if already within 1"
      (7099-7127).
    - `move` → the normal path (7131-7410), which before moving runs a stack of
      "actually, stay put / adjust the target" checks in order:
      a. Already within control range (3.79") of the assigned marker → hold, unless a
         melee seeker has an enemy within the round-scaled leave-limit (R1: 8" horde /
         Move+14" others; R2: 6" horde / Move+12"; R3+: 12") (7140-7185).
      b. Threat-aware hold for **pure ranged** units (skipped for faction aggression
         > 1.2): currently safe (charge threat < 0.5) but destination charge threat
         ≥ 3.0, and it has shooting targets → stay (7192-7220).
      c. Hold-for-shooting: moving would lose ALL current targets and the objective isn't
         reachable this turn (and its score < 10 or > 2 turns away) → stay
         (`_should_hold_for_shooting`, 7239-7247, function at 10886).
      d. Heavy-weapon hold: expected extra hits from +1-to-hit ≥ 0.15 and no
         high-priority objective (≥ 10 score) calls → stay (7252-7260, consts 1803-1804).
      e. Lone Operative: retreat to keep > 12" from enemies, or hold if already safe
         (7266-7294).
      f. Doomed Deadly-Demise vehicle: drive at the nearest enemy cluster (7300-7319).
      g. Target blending: 70/30 toward a planned charge target (7324-7341); toward
         Rapid-Fire/Melta half-range at 40% blend if the benefit ≥ 2 expected extra
         damage (7346-7365); toward a firing position at 35% blend if the direct path
         loses all targets (7372-7386); Lions 6"-spacing adjustments (7388-7392).
      h. `_compute_movement_toward_target` produces the per-model destinations
         (7394-7410 — see section F). If nothing legal → REMAIN_STATIONARY (7414-7421).

### D. Objective evaluation — `_evaluate_all_objectives`, AIDecisionMaker.gd:8510-8769
For each marker: sum friendly/enemy OC within control range (3.79" = 3" + 20mm marker
radius, const at line 41), count units within 12", and compute **projected enemy OC** —
enemy units whose Move + 2" slack could put them in control range next turn (8564-8585).
Classify the marker (8587-8602):
- `held_safe` (we control, no enemy within 12"), `held_threatened` (we control, enemy
  near), `enemy_weak` (they control with OC ≤ 4), `enemy_strong` (OC > 4), `contested`
  (both present, tied), `uncontrolled`.
Then build the priority score (table 1 below), narrate the top-3 "VP stakes" line
(8757-8765) and return per-marker evaluations including `oc_needed = enemy_oc −
friendly_oc + 1` (8748).

### E. Unit assignment — `_assign_units_to_objectives`, AIDecisionMaker.gd:8775-9744
1. **OC needs ledger**: per marker, base need (0 if held_safe; max(1, enemy_oc) if
   held_threatened; else max(1, oc_needed)) plus projected-pressure extra, capped at
   PROJECTED_NEED_CAP = 4 (8791-8810).
2. **Incoming OC (COORD-2)**: OC of friendly units that already moved toward a marker
   this phase reduces its need, so later units don't stack onto it (8819-8854); a unit
   whose best marker was blocked this way gets a narrated **redirect note** ("obj_2 is
   already covered (X en route) — redirecting to obj_4") (9357, 9410-9411, 9735-9742).
3. Score every (unit, objective) pair (8866-9274) — table 3 below. Every additive term is
   booked by name so `sum(terms) == score` (8914).
4. **Pass 1 — holds** (9282-9352): units already on a marker hold it if OC is still
   needed, it's threatened, or they are the sole holder. Exception "AGGRO-FREE": a home
   marker, ≥ 10-model melee-role unit, aggression > 1.0, round ≤ 2 → freed to advance
   (9320-9321).
5. **Pass 2 — captures** (9402-9422): greedy best-score-first over markers with remaining
   need, consuming OC; reasons narrated as capture / flip / reinforce (9374-9400).
6. **Pass 2.5 — melee-seeker conversion (COORD-4)** (9432-9469): each assigned
   hold/move/advance runs `_melee_chase_gate` (2185 — table 7). If the gate fires, the
   assignment becomes `action: "attack"` on the nearest enemy, its consumed OC is
   **re-opened**, and the objective is kept as a fallback in case the target dies.
7. **Backfill** (9473-9485): re-opened needs get the next best unassigned unit, reason
   suffixed "— backfilling for a unit that went hunting".
8. **Pass 3 — screens / blocks / support** (9487-9720): unassigned units, cheap
   non-CHARACTER units first (`_is_screening_candidate`, 11648):
   - Deep-strike **denial** positions if the enemy has reserves (score = SCREEN_SCORE_BASE
     8.0 + position priority − 0.3/inch of distance; screeners spaced so denial bubbles
     touch) (9576-9626).
   - **Screen-protect** in front of valuable friendlies (flat 8.0) (9630-9658).
   - **Corridor blocks** between enemies and key markers (7.0 + priority − 0.3/inch,
     max 4 blockers, 5" apart) (9663-9698).
   - **Support fallback** `_find_best_remaining_objective` (11078): marker priority
     − 0.5/inch distance, +3.0 if contested/threatened/enemy_weak, +2.0 to screen a safe
     hold with enemies near, +1.5 for ranged near enemies, and **−3.5 per unit already
     committed there** (SUPPORT_STACK_PENALTY) so spares fan out (11093-11135).
   - Truly nothing useful → hold in place with score −100 (9711-9720).

### F. Picking the actual spot — `_compute_movement_toward_target`, AIDecisionMaker.gd:11139-11486
1. Straight-line vector toward the target, capped at the Move stat (11160-11164).
2. **Terrain**: if the direct path is blocked, try 20 angles (±15°…±165°) × 4 distance
   fractions and keep the unblocked option with most forward progress
   (`_find_unblocked_move_enhanced`, 11488-11550). If the path is clear but the endpoint
   is exposed, a ±15°/±30° tweak that ends **in cover** (terrain between endpoint and an
   enemy) is preferred (`_find_cover_path`, 11556-11593).
3. **Climb cost**: non-FLY units pay the terrain penalty out of their move; alternate
   angles are searched for a better net-progress path, and at least 2" of effective move
   is always kept so units stuck in ruins can escape (11179-11238).
4. **Weapon-range clamp**: the move is shortened so current shooting targets stay in
   range when `max_weapon_range` was passed (11241-11248).
5. **Threat dodge** (`_find_safer_position`, 24090-24180): if the destination raises
   total threat by ≥ 1.0, candidates are tried — ±2"/±4" lateral offsets, 75%/50%
   shorter moves, combinations — scored as `progress-toward-objective × 1.5 −
   candidate threat` (+ Hidden bonus when enabled) (24162-24168).
6. **Collision/coherency ladder**: per-model placement at fractions 1.0/0.75/0.5/0.25/
   0.15/0.1, then a formation-preserving move at the same fractions, then ±45°/±90°
   angles, then three progressively relaxed collision radii (0.85×, 0.70×, 0.50×) at more
   angles (11288-11486). Each successful rung returns real per-model destinations that
   the engine validates again. Coherency is handled inside
   `_try_move_with_collision_check` / `_try_formation_move`. Two off-by-default speed
   knobs: MOVE_RIGID_BLOCK_FIRST = 0 (translate the whole squad as one block first) and
   MOVE_LADDER_FAIL_BUDGET = 0 (give up after N failed rungs) (11305, 11293; rationale
   comments at 1460-1515).

### G. Engaged units (Fall Back vs stand) — `_decide_engaged_unit`, AIDecisionMaker.gd:9750-9935
Decided **outside** the battle plan, first in the act order:
1. Survival assessment: expected fight-phase damage ≥ 75% of remaining wounds =
   "lethal", ≥ 50% = "severe" (consts 2034-2035).
2. On an objective (9795-9865): round 4-5 and winning/tied the OC war → hold regardless
   of survival (unless it has Fall Back and Charge). Winning/tied OC → hold, *except*
   lethal survival AND the others present can still out-OC the enemy without this unit →
   fall back. Sole holder → stay even at lethal risk ("deny the objective").
3. Otherwise fall back if allowed (9880-9917): retreat direction = toward the nearest
   safe friendly objective, else directly away from the engaging enemies' centroid;
   per-model placement tries the primary direction then alternates, at 100/75/50/25% of
   Move (`_compute_fall_back_destinations`, 9941-10029). Fall Back and Charge / and Shoot
   abilities make falling back more attractive and are narrated. 11th-edition
   battle-shocked units get the mandatory Desperate Escape narration (~1/3 of models at
   risk) (9905-9911). No valid path → remain stationary.

### H. Advance decisions (three places)
1. **Assignment-time** `_should_unit_advance` (10374-10445): only when the marker is
   between Move and Move+2" away. Advance if the unit has Advance-and-Shoot or
   Advance-and-Charge; always for melee-only units; in R1 for no-man's-land markers; for
   uncontrolled markers with priority ≥ 8; or when it has no shooting targets in range
   anyway. Otherwise shooting wins and it does a normal move.
2. **Melee chase gate** (2277-2287): advance when Advance-and-Charge is available, or
   when a normal move would NOT reach charge range (12").
3. Reserves/disembark paths never advance. The advance distance used for planning is
   always Move + 2" — the average 1d6 is approximated as 2 (7029, 8967, 10381).

---

## Scoring tables (all values are the effective defaults — ai_config.json overrides nothing)

### 1. Objective priority (`_evaluate_all_objectives`)

| Term | Default | Plain-English meaning | Line |
|---|---|---|---|
| WEIGHT_UNCONTROLLED_OBJ | **10.0** | Base value of a marker nobody controls | 1813, 8612 |
| WEIGHT_CONTESTED_OBJ | **8.0** | Base value of a marker both sides stand on | 1814, 8614 |
| held_threatened base | **6.4** | 0.8 × contested weight — reinforce a hold under threat | 8622 |
| WEIGHT_ENEMY_WEAK_OBJ | **7.0** | Enemy holds it with OC ≤ 4 — worth flipping | 1815, 8616 |
| WEIGHT_ENEMY_STRONG_OBJ | **−5.0** | Enemy holds it with OC > 4 — usually not worth it | 1817, 8618 |
| WEIGHT_ALREADY_HELD_OBJ | **−3.0** | Safely held — most units should go elsewhere | 1818, 8620 |
| WEIGHT_HOME_UNDEFENDED | **+9.0** | Own home marker with zero friendly OC on it | 1816, 8626 |
| WEIGHT_SCORING_URGENCY (R1) | **+3.0** | Round-1 rush — scoring starts round 2 | 1819, 8631 |
| R1 NML extra | **+1.0** | Uncontrolled no-man's-land marker in round 1 | 8634 |
| URGENCY_ROUND_2_CONTEST | **+2.0** | R2: uncontrolled/enemy_weak (contested ×0.8 = +1.6; held ×0.6 = +1.2) | 1944, 8637-8643 |
| R2 NML extra | **+1.5** | Any non-home marker in the first scoring round | 8646 |
| URGENCY_ROUND_3_HOLD | **+1.5** | R3: threatened/enemy_weak (+1.8 for contested, ×1.2) | 1945, 8649-8654 |
| URGENCY_LATE_GAME_PUSH | **+2.5** | R4-5: contested/enemy_weak (+2.0 uncontrolled ×0.8; +1.0 enemy_strong in R5 ×0.4) | 1946, 8657-8663 |
| Tempo multiplier | **×0.8 … ×1.8** | Behind on VP → offensive states scaled up; ahead → down (table 6) | 8668-8678 |
| Enemy-home discount | **−3.0** | Enemy_strong home markers are far and hard to keep | 8682 |
| Denial bonus (enemy_weak, R3+) | **+2.0 / +2.5 / +3.0** (R3/R4/R5) | Contesting denies the enemy VP (code: 1.5 + (round−2)×0.5; the inline comment understates by one step) | 8690 |
| Denial bonus (enemy_strong non-home, R3+) | **+1.0 / +1.5 / +2.0** | Same idea, weaker (0.5 + (round−2)×0.5) | 8692 |
| Retention (held_safe) | **+1.5 R1; +3.0/+4.0/+5.0/+6.0 R2-R5** | Don't abandon what's already scoring (code: 2.0 + (round−1)×1.0; comment understates by one step) | 8702-8706 |
| Threatened retention (R2+) | **+2.25 / +3.0 / +3.75 / +4.5** (R2-R5) | Defend a hold under attack (1.5 + (round−1)×0.75; comment likewise off by one) | 8712 |
| WEIGHT_VP_PER_POINT | **1.2 per VP** | Real mission-card VP the marker pays next scoring point, converted to priority | 1812, 8728 |

### 2. VP pricing of one marker (`_estimate_objective_vp_value`, 18788-18877)
Reads the player's actual primary/secondary cards. Marginal logic: for a "hold N" rule
the marker that *reaches* N pays full VP, one that merely builds toward it pays 50%, pure
insurance pays 20%, and a held marker that keeps the threshold alive pays full (18820-18839).
"Hold more than the opponent": full VP only when this marker swings or preserves the
majority, else 30% (18840-18845). Enemy-home / centre / newly-taken rules pay their full
VP when the marker matches. Secondary hints add their VP for matching zones (18862-18875).

### 3. Per-(unit, objective) candidate score (`_assign_units_to_objectives`, 8899-9258)

| Term (booked name) | Default | Plain-English meaning | Line |
|---|---|---|---|
| objective_priority | table 1 × strategy | Marker priority × round-strategy × army-archetype `objective_priority` multiplier | 8909 |
| oc_efficiency | **up to +3.0** | min(unit OC ÷ OC needed, 1.5) × WEIGHT_OC_EFFICIENCY 2.0 — high-OC units to contested markers | 1820, 8918 |
| distance_penalty | **−2.0 / extra turn** | MOVE_TURNS_AWAY_PENALTY per movement turn beyond the first | 1524, 8922 |
| reach_horizon | **OFF** (MOVE_REACH_HORIZON 0.0) | Would scale value by remaining scoring chances; measured at −4.29 VP/game and shipped off | 1495, 8929-8935 |
| stay_on_objective | **+5.0 R1 / +6.0 R2-3 / +7.0 R4-5** | MOVE_STAY_BONUS_EARLY/SCORING/LATE for a unit already on the marker; divided by faction aggression on home markers early for aggressive armies | 1525-1527, 8940-8952 |
| horde_presence | **+2.0 (≥10 models) / +1.0 (≥5)** | Big squads are hard to shift off a marker | 1528-1529, 8959-8962 |
| reachability | **+3.0** arrives this turn / **+1.5** with an advance / **−2.0** R1 and > 1 turn away | MOVE_REACHABLE_BONUS / MOVE_ADVANCE_REACHABLE_BONUS / MOVE_UNREACHABLE_EARLY_PENALTY | 1530-1532, 8965-8972 |
| firing_position | **+3.0 × kept-ratio / −2.5 / +1.5 / +1.0** | Keeps current targets in range / loses ALL / gains new ones / enemies near marker | 1794-1796, 8986-9002 |
| threat_delta | **−(increase × survival-mult)**, extra −0.5× for charge-threat increase | Only the *increase* in threat vs standing still is charged (threat model in table 5) | 9007-9017 |
| overwatch_risk | **OFF** (OVERWATCH_EXPOSURE_PENALTY 0.0) | Would tax newly entering 24" overwatch bands by shot volume ÷ 20; halved R4-5; ×0.05 for pure melee | 1910-1912, 9025-9033, 23858-23885 |
| hidden_gain | **OFF** (WEIGHT_HIDDEN_GAINED 0.0) | Would reward ending in dense terrain (11e Hidden rule); corpus-suggested 4.0, measured inconclusive | 1881, 9041-9043, 23776-23785 |
| aao_isolation | **+2.5 / −2.5** | Lions of the Emperor only: keep/break the 6" no-friendlies bubble (WEIGHT_AAO_ISOLATION / AAO_CLUMP_PENALTY; radius 6", buffer 1") | 2446-2451, 9049-9054 |
| charge_lane | **+3.0 × alignment / −1.5** | PHASE_PLAN_CHARGE_LANE_BONUS — marker in the same direction as this unit's planned charge target (dot > 0.5), penalty if opposite (dot < −0.3). Hard+ only | 1937, 9059-9074 |
| shooting_lane | **+1.0 per lane** | 0.5 × PHASE_PLAN_SHOOTING_LANE_BONUS 2.0 when the marker keeps a planned shooting lane in range. Hard+ only | 1938, 9078-9089 |
| primary_awareness | **up to +3.0 pressure; + enemy-home/centre bonuses; +3.0 hold-home; +4.2 quarters** | The primary card's own geometry (0.5 × pressure capped at 6; SECONDARY_SPREAD_BONUS 6.0 × 0.7 for uncovered quarters) | 9094-9111 |
| secondary_zone | card-derived | Zone bonuses computed from active secondary cards | 2009, 9118-9121 |
| secondary_enemy_push | **×1.5 … ×0.3 of push value; +0.5× on enemy home** | Behind Enemy Lines: scales up as the destination nears the enemy zone (≤ 8" full ×1.5, fading to 24") | 2014, 9126-9146 |
| secondary_defend_home / no_mans_land / center | card-derived | Defend Stronghold / NML priority / Area Denial (center bonus max at centre, fades by 12") | 9149-9167 |
| secondary_spread | **+6.0** | Engage on All Fronts: destination in an uncovered table quarter (SECONDARY_SPREAD_BONUS) | 2012, 9170-9175 |
| secondary_edge_flank | card-derived | Outflank: within 6" of a side edge beyond own half | 9179-9185 |
| secondary_kill_proximity | **+2.0** keyword match; **up to +2.0** No Prisoners (fades to 18"); **up to +2.5** Overwhelming Force (fades to 14") | Position near secondary kill targets | 2011, 9188-9234 |
| plan_earmark | **+8.0 HOLD_OBJECTIVE / +6.0 PUSH_CENTER** | AI-Plan earmark bonus (PLANS_ENABLED = 1); earmark released when the unit drops below 50% models (PLAN_EARMARK_RELEASE_AT 0.5) | 945-948, 1026-1042, 9255-9258 |

### 4. Assignment/coordination constants

| Term | Default | Meaning | Line |
|---|---|---|---|
| OBJECTIVE_CONTROL_RANGE_PX | **151.5 px = 3.79"** | "On the marker" = within 3" + 20mm marker radius | 41 |
| PROJECTED_NEED_CAP | **4** | Max extra OC committed because of projected enemy pressure | 1824, 8791 |
| SUPPORT_STACK_PENALTY | **3.5 per committed unit** | Diminishing returns for leftover units picking the same marker | 1828, 11116 |
| SCREEN_SCORE_BASE | **8.0** | Base priority of a screening job (comparable to a marker) | 1924, 9592 |
| SCREEN_CHEAP_UNIT_POINTS | **100 pts** | At/below this cost a unit is an eligible screener (never CHARACTERs) | 1923, 11648-11656 |
| CORRIDOR_BLOCK_SCORE_BASE | **7.0** | Base priority of a corridor-block job (just below screening) | 1931, 9678 |
| CORRIDOR_BLOCK_THREAT_RANGE_INCHES | **30"** | Enemy must be this close to a marker to warrant blocking | 1929 |
| CORRIDOR_BLOCK_POSITION_RATIO | **0.55** | Blocker stands 55% of the way from marker toward the enemy | 1930 |
| CORRIDOR_BLOCK_MIN_GAP_PX / MAX_POSITIONS | **200 px (5") / 4** | Blocker spacing / cap | 1932-1933 |
| screen/block distance term | **−0.3 per inch** | Closer units get the screening job | 9595, 9681 |

### 5. Threat model (`_calculate_enemy_threat_data` 23893, `_evaluate_position_threat` 23992)

| Term | Default | Meaning | Line |
|---|---|---|---|
| Charge-threat radius | enemy Move + **12"** + engagement range | How far the enemy reaches with move + charge | 23912 |
| Shooting-threat radius | enemy max weapon range | — | 23916 |
| Enemy danger rating | **0.3-3.0** (base 1.0; +0.5 ≥10 models; +0.5 T8+/W8+; +0.3 W4+; +0.3 CHARACTER/VEHICLE/MONSTER; up to +0.5 melee quality) | Scales every penalty from that enemy | 23932-23990 |
| THREAT_CHARGE_PENALTY | **2.0** | Per unit-value × depth-into-zone, for standing inside a charge zone | 1834, 24018 |
| THREAT_CLOSE_MELEE_PENALTY | **2.0** extra within **12"** | Inside raw charge distance — no enemy move needed | 1925, 1841, 24033-24038 |
| THREAT_SHOOTING_PENALTY | **0.5** | Much lighter — being shot at is often unavoidable | 1835, 24050 |
| THREAT_MELEE_UNIT_IGNORE | **×0.05** | Pure-melee units nearly ignore charge threat (they want the fight) | 1837, 24021 |
| Character multiplier | **×1.5** | Non-vehicle CHARACTERs value safety more (pushes them behind cover) | 24007, 24064 |
| THREAT_FRAGILE_BONUS | **×1.3** | Extra for T≤3 or 1-wound units | 1836, 24070-24071 |
| Safer-position trade-off | progress × **1.5** − threat | How the dodge search values progress vs safety | 24162 |

### 6. Strategy multipliers (round × archetype × tempo — multiplied together, 14228-14237)

| Modifier set | aggression | objective | survival | charge threshold | Line |
|---|---|---|---|---|---|
| Rounds 1-2 (AGGRESSIVE) | 1.3 | 0.95 | 0.7 | 0.5 | 1966-1969, 14030-14037 |
| Round 3 (BALANCED) | 1.0 | 1.0 | 1.0 | 1.0 | 14038-14045 |
| Rounds 4-5 (OBJECTIVE/SURVIVAL) | 0.7 | 1.6 | 1.4 | 1.3 | 1970-1973, 14046-14053 |
| MELEE archetype (≥60% melee output) | 1.25 | 0.9 | 0.8 | 0.75 | 1984, 1990-1993 |
| SHOOTING archetype (≥65% ranged) | 0.8 | 1.1 | 1.3 | 1.3 | 1985, 1996-1999 |
| ELITE archetype (avg ≥4W or ≥40 pts/model) | 0.9 | 1.15 | 1.25 | 1.0 | 1986-1987, 2002-2005 |
| Tempo (behind on VP) | ×(1 + 0.1/VP, cap 1.5); desperation from R4: up to ×1.8 | applied to offensive marker states | — | — | 1954-1958, 13990-14022 |
| Tempo (ahead) | down to ×0.8 (half rate) | +up to 2.0 on held markers | — | — | 1956, 14012, 8677-8678 |
| Faction aggression | Default **1.0**, Orks **1.2**, Custodes **1.5**, Khorne **1.8**, World Eaters **2.0** | Shapes stay bonuses, hold-leave limits, R1 setup pushes — not *who* seeks melee | — | — | 2019-2023, 2087-2100 |

### 7. Melee chase gate (`_melee_chase_gate`, 2185-2300) — who abandons a marker to fight
Only **melee-focused** units (no strong ranged guns — 2129-2156, 2175-2176). Gates in order:
- Hold-assigned leave-limits: R1 horde(≥10) 12", others 18" (aggression ≥ 1.5) / 14";
  R2 horde 10", others 14"/12"; R3+ 12"/10" (2208-2227).
- Chase cap: never chase beyond max(**20"** MELEE_AGGRESSION_ADVANCE_THRESHOLD_INCHES,
  own Move + 14") (2029, 2245-2251).
- Hordes off-objective, R1-2, enemy beyond 12": only aggression ≥ 1.5 armies press on (2252-2259).
- On a **contested** own marker from R2 → never leave (2260-2263). On a marker R3+ with
  the enemy > 14" away → stay (2264-2267).
- Hold-assigned with enemy beyond 12" + Move → stay, except an R1 setup push for
  aggression ≥ 1.5 within a further 6" (2268-2275).
- Advance when Advance-and-Charge is available or a normal move can't reach charge range
  (2277-2287). Related execution bonuses: MELEE_AGGRESSION_ENEMY_SEEK_BONUS 8.0 and
  MELEE_AGGRESSION_CHARGE_RANGE_BONUS 12.0 (2027-2028); minimum push 60% of Move
  (MELEE_AGGRESSION_MIN_MOVE_RATIO, 2030).

### 8. Stay-put micro-decisions

| Check | Threshold defaults | Line |
|---|---|---|
| Hold for shooting | would lose ALL targets AND marker not reachable this turn AND (marker score < 10 or > 2 turns away); overridden if Rapid-Fire/Melta closing benefit ≥ 2.0 | 10886-10963 |
| Heavy weapon hold | expected extra hits ≥ **0.15** (HEAVY_STATIONARY_MIN_BENEFIT); overridden by marker score ≥ **10.0** | 1803-1804, 7252-7260 |
| Threat-aware hold (pure ranged) | safe now (charge threat < **0.5**) but destination ≥ **3.0**, has targets; skipped when faction aggression > 1.2 | 7192-7220 |
| Lone Operative | keep > **12"** from enemies | 7266-7294 |
| Half-range reposition | benefit ≥ **2.0** (HALF_RANGE_MIN_BENEFIT), blend **0.4** (HALF_RANGE_MOVE_BLEND), stop **1"** inside (HALF_RANGE_APPROACH_MARGIN_INCHES) | 1788-1790, 7346-7365 |
| Firing-position blend | **0.35** (FIRING_POSITION_BLEND) | 1797, 7384 |
| Charge-target blend | **70% target / 30% marker** when within Move + 12" | 7334-7339 |

### 9. Engaged-unit / fall-back constants

| Term | Default | Meaning | Line |
|---|---|---|---|
| SURVIVAL_LETHAL_THRESHOLD | **0.75** | Expected melee damage ≥ 75% of remaining wounds → "likely destroyed" | 2034 |
| SURVIVAL_SEVERE_THRESHOLD | **0.5** | ≥ 50% → "badly hurt" | 2035 |
| SURVIVAL_FALL_BACK_BONUS / HOLD_BONUS | **2.0 / 1.5** | Score nudges toward falling back / holding | 2036-2037 |
| Fall-back fractions | 100/75/50/25% of Move | Placement retry ladder | 10014 |
| R4-5 objective hold | unconditional when OC war is won/tied | 9806-9814 |

### 10. Reserves & disembark (steps 1.5/1.75 — the phase's preamble)
Reserves arrival order (RESERVE_DEPLOY_*): points ÷ **50** base, +2.0 deep strike, +1.5
melee, +1.0 short-ranged, +1.5 contested marker nearby, +0.5 open marker, +2.0 R4,
+5.0 R5 (1339-1346). Landing-spot scoring: near-objective base **10.0** / far **8.0**,
charge-range bonus **3.0** / near-range **2.0**, Lions spacing +4.0/−3.0 (1333-1338).
Disembark score (`_score_disembark_benefit`, 8115-8241): transport on a marker **+0.8**
(+0.1/OC), within 6" **+0.4**, 12" **+0.15**; shooting **+0.3** +0.1/target; charge
chance **+0.4**; R1 **−0.2**, R2 **+0.3**, R3+ **+0.8**; anti-tank threat to transport
**+0.25**; elite cargo **+0.3** (≥200 pts) / **+0.15** (≥100); aggressive faction
**+0.2**; no Firing Deck **+0.4**; transport stuck **+0.3** (consts 1364-1379). Note:
the docstring says "score < 0.5 means stay embarked" (8119) but the caller actually
disembarks the best unit whenever its score is **> 0.0** and legal positions exist
(8071, 8099-8109) — there is no 0.5 gate in the code.

---

## Worked example (invented but realistic numbers)

Round 2. The AI plays Orks (faction aggression 1.2, army archetype MELEE). A 10-model
Boyz unit (Move 6", OC 2) sits 8" from `obj_3`, an **uncontrolled** marker in
no-man's-land. VP is tied (tempo ×1.0). The primary card pays 5 VP for holding it next
command phase. One enemy 5-man squad with melee weapons (danger rating ≈ 1.0) is 20"
beyond the marker.

**Marker priority** (`_evaluate_all_objectives`):
- uncontrolled: **+10.0**
- Round 2 contest urgency: **+2.0**; NML extra: **+1.5**
- VP pricing: 5 VP × 1.2 = **+6.0**
- Priority = **19.5**

**Boyz → obj_3 candidate score** (`_assign_units_to_objectives`):
- objective_priority: 19.5 × (round 0.95 × MELEE archetype 0.9 = 0.855) = **+16.7**
- oc_efficiency: oc_needed = 1, so min(2/1, 1.5) × 2.0 = **+3.0**
- distance_penalty: 8" ÷ 6" Move → 2 turns → −(2−1) × 2.0 = **−2.0**
- reachability: 8" ≤ 6+2 → advance-reachable **+1.5**
- threat_delta: destination is ~1" deeper into the enemy's 20"-radius charge zone;
  increase ≈ 1.4, × survival (0.7 × 0.8 = 0.56) ≈ **−0.8**
- **Total ≈ 18.4**, action = **advance** (`_should_unit_advance`: melee-only unit → yes).

That beats the same unit's candidate for the safely-held home marker (priority −3.0
already-held +3.0 retention +2.0 VP-share ≈ 4.4 × 0.855 + stay bonuses ≈ 12-13), so the
greedy pass 2 assigns Boyz to **ADVANCE obj_3 — "capturing it (uncontrolled)"**. The
melee chase gate then checks the nearest enemy: 28" away > chase cap max(20", 6+14=20")
→ no attack conversion; the assignment stands. At execution, the destination is the point
8" along the straight line to the marker (Move 6 + 2 advance), terrain-checked, threat-
dodged, and placed model-by-model at the first collision-free rung of the ladder. Next
turn, standing on the marker, the same unit's candidate would instead earn
stay_on_objective +6.0 and horde_presence +2.0 — which is exactly why it stays.

---

## Difficulty gates

| Capability | Easy | Normal | Hard | Competitive | Source |
|---|---|---|---|---|---|
| Any scoring at all (vs random legal action) | random | ✓ | ✓ | ✓ | AIDifficultyConfig.gd:23-24; AIDecisionMaker.gd:3046-3048 |
| Score noise (± on unit act-order) | ±100 (moot) | **±1.5** | **±0.5** | **0** | AIDifficultyConfig.gd:72-83; AIDecisionMaker.gd:2071-2077, 6985-6987 |
| Threat-zone awareness (tables 3/5) | — | ✓ | ✓ | ✓ | AIDifficultyConfig.gd:41-42; AIDecisionMaker.gd:6774 |
| Multi-phase plan (charge_lane / shooting_lane / lock targets) | — | — | ✓ | ✓ | AIDifficultyConfig.gd:33-34; AIDecisionMaker.gd:3111-3112 |
| Charge-threshold modifier (affects later phases) | 2.0 | 1.0 | 0.85 | 0.7 | AIDifficultyConfig.gd:105-116 |
| Screening (`use_screening` says Hard+) | — in the flag, but **the flag is never called**: the screening/blocking passes run at every non-Easy difficulty | | | | AIDifficultyConfig.gd:63-64; no caller in AIDecisionMaker.gd (verified by search) |

Movement-relevant note: `use_survival_assessment` (Normal+) and `get_movement_iterations`
(1/3/5/8) also exist in the config (AIDifficultyConfig.gd:59-60, 86-97); the iterations
value is not consulted by the movement-phase destination ladder shown above.

---

## Evidence (file:line index)

All in `40k/scripts/AIDecisionMaker.gd` unless stated.

- Entry & difficulty: 2965 (decide), 3046-3048 (Easy random), 3111-3112 (phase-plan gate),
  2071-2077 (noise); `40k/autoloads/AIPlayer.gd:769` (random gate on reactive path);
  `40k/scripts/AIDifficultyConfig.gd:23-116` (all gates/values).
- Config/overrides: `40k/data/ai_config.json` (PLANS_ENABLED only); 295-322 (loader),
  1235-1275 (get_param resolution), 421 (PLANS_ENABLED default 1.0).
- `_decide_movement` steps: 6524-6697. Reserves: 7429+; consts 1339-1346, 1333-1338.
  Disembark: 8044-8241; consts 1364-1379; missing 0.5 gate: 8071 + 8099 vs docstring 8119.
- Committed plan / replan-for-cause: 168-169 (store), 6791-6855 (reuse/replan), 3784-3826
  (consume + intents), 3077-3094 (clearing), 6873-6949 (announce).
- Objective evaluation: 8510-8769; state classification 8587-8602; projected OC 8564-8585;
  priority terms 8609-8728; comment-vs-code drift in retention/denial: 8690, 8692, 8705,
  8712. VP pricing: 18788-18877; WEIGHT_VP_PER_POINT 1812.
- Assignment: 8775-9744; needs ledger 8791-8810; incoming OC 8819-8854; candidate scoring
  8899-9274; hold pass 9282-9352 (AGGRO-FREE 9320); capture pass 9374-9422; melee
  conversion 9432-9469 (+ gate 2185-2300); backfill 9473-9485; screening/denial 9576-9626;
  screen-protect 9630-9658; corridor block 9663-9698 (consts 1929-1933); support fallback
  9700-9720 + 11078-11137; redirect notes 9735-9742.
- Movement weights: 1524-1533, 1794-1804, 1812-1828, 1834-1841, 1921-1946, 2009-2014,
  2019-2030, 2034-2037, 2446-2451, 945-948; off-by-default: 1460-1515 (rigid block,
  reach horizon, ladder budget), 1881-1895 (Hidden), 1910-1912 (overwatch).
- Execution branches: hold 7007-7023; advance 7027-7045; attack 7052-7096; screen
  7099-7127; normal move 7131-7410; stay-put checks 7140-7294; blends 7324-7392.
- Destination engine: 11139-11486 (ladder), 11488-11550 (terrain angles), 11556-11614
  (cover path), 24090-24180 (safer position), 23893-24088 (threat data/eval),
  23858-23885 (overwatch), 23776-23785 (hidden).
- Engaged / fall back: 9750-9935 (decision), 9941-10029 (destinations), 2034-2037
  (survival consts).
- Advance: 10374-10445; +2" average 7029/8967/10381.
- Strategy modifiers: 13990-14022 (tempo), 14024-14053 (round), 14059-14237 (archetype),
  1966-2005 (consts); faction aggression 2019-2023, 2087-2100.
- Melee-seeker classification: 2129-2156, 2175-2176; hold-leave limits at execution
  7147-7169.
