# AI Explainer — Shooting Phase (Focus Fire & Target Selection)

All code references are to `40k/scripts/AIDecisionMaker.gd` unless another file is named. All weight
values below were read directly from the code. The shipped config file `40k/data/ai_config.json`
overrides **nothing** in the shooting phase — its only entry is `PLANS_ENABLED: 1` — so every default
listed here is also the **effective** value (a per-machine `user://ai_config.json` or a player profile
could still override any of them at runtime; layering is resolved in `get_param`, lines 1235–1256).

## Overview

When it is the AI's turn to shoot, it does not pick targets one unit at a time. The first time a
shooter can be selected, it builds a single **army-wide "focus fire plan"**: it lists every ranged
weapon in every one of its units, estimates how much damage each weapon would do to each visible
enemy, and then hands weapons out to targets one at a time, always giving the next weapon to
whichever pairing adds the most value *given what has already been assigned*. "Value" here is
expected damage times a strategic **target value** (how much the AI wants that enemy dead —
points cost, firepower, whether it sits on an objective, whether it is a buffing leader, etc.).
The math is deliberately shaped so that **finishing kills beats spreading chip damage**: crossing a
model's or a unit's wound total earns bonuses, while damage past the point of death is worth only
35% of normal, and once a target already has 115% of its health allocated, further weapons are
pushed elsewhere. Weapons are also matched to sensible jobs — an anti-tank gun pointed at a vehicle
gets a 1.4× bonus, pointed at a horde it gets 0.6× (and up to a further 0.4× for wasting big damage
on 1-wound models). Each unit then fires using its slice of the plan; different weapons in one unit
can be aimed at different targets (split fire), but every model in the unit fires with its squad.
A unit that is "Hidden" in terrain can in principle hold fire to stay untargetable, but the penalty
that drives that behaviour ships at 0.0, so **holding fire is off by default**. On Easy difficulty
all of this is bypassed and the AI shoots at random targets.

## Decision flow

The shooting decider is `_decide_shooting` (line 13035), reached from `decide()` (line 3133).
On Easy difficulty `decide()` diverts to `_decide_random` first (line 3047) — see Difficulty gates.

1. **Housekeeping actions first.** If the engine is mid-sequence, answer it: complete a unit's
   shooting (13044), decline the not-yet-implemented Swift-as-the-Eagle reactive move (13060),
   auto-use Throat Slittas / Sentinel Storm faction abilities (13074, 13083), apply saves (13092),
   continue the weapon sequence (13096), resolve shooting (13100), confirm targets (13111).
2. **Pre-shooting alternatives.** Once per phase, consider the Grenade stratagem (13117; gated on
   `use_stratagems`, i.e. Normal+), then shooting-phase faction stratagems (13133), then whether a
   low-firepower unit should perform a secondary-mission action instead of shooting (13140), burn an
   objective (13154), perform a ritual (13168), or terraform (13182).
3. **Build the focus-fire plan (once per phase).** If `SELECT_SHOOTER` is offered and no plan
   exists, call `_build_focus_fire_plan` over *all* eligible shooter unit ids (13201–13208). The
   plan is a map `unit_id -> [{weapon_id, target_unit_id, model_ids}]` cached in the static
   `_focus_fire_plan` (109) and cleared when the phase ends or a non-shooting phase is entered
   (3050–3056, 13471–13472).
4. **Inside `_build_focus_fire_plan`** (13608):
   1. Collect every ranged weapon of every shooter; drop non-pistols for units stuck in engagement
      range (unless MONSTER/VEHICLE) and spent one-shot weapons (13633–13685).
   2. For every enemy compute `kill_threshold` = total remaining wounds of its living models
      (`_calculate_kill_threshold`, 13907–13913) and `target_value` = strategic priority
      (`_calculate_target_value`, 14245 — table below). Two adjustments are applied on top:
      when losing on VP, targets on objectives get the tempo multiplier (13706–13713,
      `_calculate_tempo_modifier` 13990); targets already earmarked for a charge this turn get
      ×0.5 so shooting doesn't steal the charge's kill (13719–13723, `PHASE_PLAN_DONT_SHOOT_CHARGE_TARGET`).
   3. Build the **damage matrix**: for every weapon × enemy pair, expected damage via
      `_estimate_weapon_damage` (13727–13766). A pair scores 0 (and is never assigned) if: pistol
      restriction violated (13744), target is a Lone Operative more than 12" away (13752), or the
      shooter has no line of sight / range to it (13757–13763). Attached characters never appear as
      targets at all — `_get_shootable_enemy_units` (20248) filters them out; they are shot through
      their bodyguard unit.
   4. **Iterative marginal-value allocation** (13795–13847): loop while unassigned weapons remain;
      each iteration computes `_calculate_marginal_value` (14480) for every unassigned weapon ×
      every enemy, assigns the single best pair, adds that weapon's expected damage to the target's
      `allocated_damage`, and repeats. Because `allocated_damage` grows, later weapons naturally
      redirect away from already-doomed targets. If no pair has positive marginal value, allocation
      stops — leftover weapons simply get no assignment.
   5. Group assignments per unit; every weapon assignment carries `model_ids` = **all alive models
      of the unit** (13859–13863, `_get_alive_model_ids` 20179). Split fire is therefore per
      *weapon*, not per model: two weapon types in one squad can hit two targets, but the plan never
      splits copies of the same weapon profile across targets.
5. **Per-unit execution.** Pick the first offered shooter that has a plan entry (13243–13249), or
   any shooter otherwise (13252–13258). Filter its assignments against targets destroyed by earlier
   shooters and re-check line of sight (13333–13347). If all plan targets are gone — or the unit
   was never in the plan — fall back to `_build_unit_assignments_fallback` (14675): a greedy
   per-weapon scorer that sends each weapon at its own best target using `_score_shooting_target`
   (21046). Units with no ranged weapons or no valid target are skipped (13293–13300, 13359–13364).
6. **Hold-fire check (F002, off by default).** Before committing, price what shooting costs in
   surrendered "Hidden" status: `_hidden_forfeit_cost` (23790) returns
   `HIDDEN_FORFEIT_PENALTY × fraction-of-enemy-shooters-the-position-hides-from`
   (`_hidden_immunity_fraction`, 23746). The shot's worth is the summed kill-fraction of its targets
   ×10 (13404–13409). If worth < cost the unit SKIPs to stay Hidden (13439–13449). **Because
   `HIDDEN_FORFEIT_PENALTY` defaults to 0.0 (line 1886, "off; corpus-suggested 3.0"), this branch
   never fires unless a config/profile turns it on.** The mirror-image term — shoot an enemy *now*
   because it will regain Hidden next turn (`_target_regains_hidden_soon`, 23810) — is likewise
   neutral by default (`HIDDEN_WINDOW_BONUS` = 1.0, line 1890).
7. **Fire.** Emit one decision record per weapon listing the top-6 targets it beat
   (`SHOOTING_ALTERNATIVES_K` = 6, line 125; `_emit_shooting_records` 13475), then return a single
   `SHOOT` action with all assignments (13461–13468). When no shooters remain, `END_SHOOTING`
   (13470–13473).

## Scoring tables

### 1. Expected damage per weapon (`_estimate_weapon_damage`, 14556–14673)

Core formula (14654): `attacks × P(hit) × P(wound) × P(unsaved) × damage × carrying-models`, then
×FNP-reduction ×leader-buff ×efficiency.

| Term | Default value | Plain-English meaning |
|---|---|---|
| P(hit) | (7−BS)/6, clamped to [1/6, 5/6] | Chance to hit; a natural 1 always misses, a 6 always hits (`AttackSequence.gd:112–113`) |
| P(wound) | by S vs T: 2+ if S≥2T, 3+ if S>T, 4+ if S=T, 5+ if S<T, 6+ if S≤T/2 | Standard 40k wound chart (`AttackSequence.gd:97–107`) |
| P(unsaved) | 1 − P(save); save = armour+AP or invuln if better, ceiling 5/6 | Chance the wound gets through (`AttackSequence.gd:124–128`) |
| Cover (11e) | −1 to the attacker's hit roll | Target in cover is harder to hit (14610–14612) |
| Wound-overflow cap | damage capped at target wounds-per-model | A 4-damage hit on a 1-wound model kills 1 model — the AI never counts wasted damage (14644–14646) |
| Carrier count | alive models actually carrying the weapon | Loadout-aware, not whole-unit count (14648–14652) |
| FNP | damage × FNP pass-through multiplier | Feel No Pain shrugs shrink expected damage (14656–14660) |
| CRIT_PROBABILITY | 1/6 | Chance of a critical (6) used by keyword math (line 1781) |
| HALF_RANGE_FALLBACK_PROB | 0.5 | Assumed chance of being in half range when distance unknown (line 1784) |

Weapon keywords are folded in as expectation adjustments (`_apply_weapon_keyword_modifiers`,
20850–20976): TORRENT ⇒ P(hit)=1.0 (20871); BLAST ⇒ +1 attack per 5 enemy models (20875–20879);
RAPID FIRE X ⇒ +X attacks at half range (20882–20893); MELTA X ⇒ +X damage at half range
(20896–20904); ANTI-KEYWORD X+ ⇒ improved effective P(wound) (20907–20922); SUSTAINED HITS X ⇒
attack multiplier `(P(hit)+X/6)/P(hit)` (20925–20940); LETHAL HITS ⇒ crits auto-wound (20943–20955);
DEVASTATING WOUNDS ⇒ critical wounds ignore saves (20958–20968).

### 2. Target value — "how badly do I want this enemy dead" (`_calculate_target_value`, 14245–14478)

Starts at 1.0, then:

| Term | Default value | Plain-English meaning |
|---|---|---|
| MACRO_POINTS_WEIGHT | +0.008 per point | A 200-pt unit adds +1.6 — expensive units are juicier (2041, 14274) |
| TRADE_PPW_WEIGHT | 0.25 × (pts-per-wound/25 − 1) | Units whose wounds are expensive are efficient to remove (1950, 14278–14282) |
| MACRO_RANGED_OUTPUT_WEIGHT | +0.15 per expected ranged damage | Shooty enemies are bigger threats (2042, 14324); output measured vs a T4/3+ reference target (14317–14321) |
| MACRO_MELEE_OUTPUT_WEIGHT | +0.10 per expected melee damage | Choppy enemies threaten too, slightly less (2043, 14359) |
| MACRO_ABILITY_VALUE_WEIGHT | +0.5 × (buff multiplier − 1) | Enemies whose abilities amplify damage rate higher (2044, 14363–14365) |
| MACRO_SURVIVABILITY_DISCOUNT | −0.15 × (defence multiplier − 1) | Very durable targets are slightly less efficient to shoot (2045, 14369–14373) |
| MACRO_LEADER_BUFF_BONUS | ×1.5 | A leader actively buffing a squad is a priority kill (2048, 14381) |
| Standalone character | ×1.3 | Unattached characters still matter (14383) |
| VEHICLE / MONSTER | ×1.2 | Big threats get a nudge (14386–14387) |
| LOW_HEALTH_BONUS | ×1.5 | Unit below half its starting models — finish it (1755, 14390–14392) |
| On objective | ×1.4, plus +0.5 per OC (MACRO_OC_ON_OBJECTIVE_WEIGHT) | Clearing objective holders wins games (14414–14418, 2046); battle-shocked holders get no OC premium (14400–14401) |
| STRATEGY_LATE_OBJ_TARGET_BONUS | ×1.3 in rounds 4–5 | Late game, objective holders matter even more (1975, 14420–14422) |
| Near objective | ×1.15, plus +0.2 per OC (MACRO_OC_NEAR_OBJECTIVE_WEIGHT) | Within double control range (14423–14426, 2047) |
| HIDDEN_WINDOW_BONUS | ×1.0 (**off**; corpus-suggested 1.25) | Would boost enemies about to regain Hidden (1890, 14433–14438) |
| Secondary kill keyword | ×1.4 | Target matches an active kill secondary, e.g. Bring It Down (14443–14449) |
| Marked for Death | ×1.5 | Specifically marked mission target (14452–14456) |
| A Grievous Blow | ×1.4 | Big starting-strength unit for that secondary (14459–14463) |
| Primary kill pressure | ×1.15 | Missions where kills score primary VP (14466–14467) |
| Round-strategy aggression | ×0.8–×1.8 (typ.) | Early-game aggression / behind-on-VP desperation multiplier (14469–14476; tempo math 13990–14022, TEMPO_* 1954–1960) |
| PHASE_PLAN_DONT_SHOOT_CHARGE_TARGET | ×0.5 | Applied in the plan builder: don't shoot up a unit you intend to charge (1941, 13719–13723) |

### 3. Weapon↔target efficiency matching (`_calculate_efficiency_multiplier`, 21346–21398)

Weapons are classified (`_classify_weapon_role`, 21241) as **anti-tank** (points for
S ≥ 7 `ANTI_TANK_STRENGTH_THRESHOLD` 1759, AP ≥ 2 `ANTI_TANK_AP_THRESHOLD` 1760, avg damage ≥ 3
`ANTI_TANK_DAMAGE_THRESHOLD` 1761), **anti-infantry** (S ≤ 5 `ANTI_INFANTRY_STRENGTH_CAP` 1763,
damage ≤ 1 `ANTI_INFANTRY_DAMAGE_THRESHOLD` 1762, AP ≤ 1, high attacks, blast/torrent), or
general-purpose. Targets are classified (`_classify_target_type`, 21309) as vehicle/monster, elite
(2+ wounds per model), or horde.

| Term | Default value | Plain-English meaning |
|---|---|---|
| EFFICIENCY_PERFECT_MATCH | ×1.4 | Anti-tank → vehicle/monster; anti-infantry → horde (1766, 21361/21369) |
| EFFICIENCY_GOOD_MATCH | ×1.15 | Either role → elite targets (1767, 21363/21371) |
| EFFICIENCY_NEUTRAL | ×1.0 | General-purpose weapons, any target (1768, 21375) |
| EFFICIENCY_POOR_MATCH | ×0.6 | Anti-tank → horde; anti-infantry → vehicle (1769, 21365/21373) |
| EFFICIENCY_TERRIBLE_MATCH | 0.35 — **declared but never used** | The match table stops at 0.6 (1770; no call site) |
| DAMAGE_WASTE_PENALTY_HEAVY | ×0.4 | D3+ average damage fired at 1-wound models (1773, 21386–21387) |
| DAMAGE_WASTE_PENALTY_MODERATE | ×0.7 | 2-damage weapons at 1-wound models (1774, 21388–21389) |
| ANTI_KEYWORD_BONUS | ×1.5 | Weapon's ANTI-X rule matches a target keyword (1777, 21395–21396) |

Note: efficiency is applied **twice** on the focus-fire path — once inside the damage estimate
(`_estimate_weapon_damage` returns `raw_damage × efficiency`, 14671–14673) and again inside
`_calculate_marginal_value` (`marginal *= efficiency`, 14544, fed from the efficiency cache built at
13788–13793). A 1.4 perfect match therefore effectively weighs ~1.96× in allocation; a 0.6 poor
match ~0.36×. The fallback scorer applies it once (21229–21230).

### 4. Marginal value — the allocator's yardstick (`_calculate_marginal_value`, 14480–14554)

For a candidate weapon→target pairing, with `threshold` = target's total remaining wounds,
`current_alloc` = damage already promised to it, `wpm` = wounds per model:

| Term | Default value | Plain-English meaning |
|---|---|---|
| useful damage | damage up to `threshold − current_alloc` | Damage that still contributes to killing the unit; valued at `useful × target_value` (14505–14521) |
| OVERKILL_TOLERANCE | 1.15 | Once 115% of the target's wounds are allocated, *all* further damage counts as waste (1753, 14509) |
| MICRO_OVERKILL_DECAY | 0.35 | Damage beyond the kill threshold is still worth 35% — finishing blows aren't free (2051, 14541) |
| MICRO_MODEL_KILL_VALUE | 0.6 | Each whole model this weapon's damage tips over adds `models × wpm × target_value × 0.6` (2052, 14528–14534) |
| MICRO_MARGINAL_KILL_BONUS | ×2.5 | If the assignment pushes the running total past 60% of the unit's wipe threshold, the whole marginal value is multiplied by 2.5 — kills snowball (2050, 14537–14538) |
| efficiency | ×(table 3 value) | Anti-tank/anti-infantry matching (14544) |
| LOW_HEALTH_BONUS | ×1.5 | Target already below half its starting model count (1755, 14547–14552) |
| already_allocated | running sum per target | Updated after every assignment (13846), which is what makes weapon N+1 avoid piling onto a dead target |
| kill_fraction | expected damage ÷ kill threshold | Recorded per candidate in the decision log (13583) |
| KILL_BONUS_MULTIPLIER | 2.0 — **declared but not used in any score** | Only echoed into decision-record metadata (1754, 13484); an in-code audit note (1212–1219) calls it out as a knob no `get_param` asks for |

### 5. Fallback per-unit scorer extras (`_score_shooting_target`, 21046–21232)

Used when a unit missed the plan or its plan targets died. Same damage math, plus:

| Term | Default value | Plain-English meaning |
|---|---|---|
| Range band | ×1.10 / ×1.0 / ×0.85 | Within half range / mid / beyond 75% of max range (21139–21151) |
| Secondary mission favours | ×1.20 vehicles (Bring It Down), ×1.25 characters (Assassination), ×1.15 6+-model units (Cull the Horde), ×1.10 infantry (No Prisoners), ×1.05 all (Overwhelming Force) | Aim where the missions pay (21164–21184) |
| Stealth | ×0.85 | Approximates the −1 to hit (21193–21195) |
| Defensive stratagem buff | ×0.80 | Smokescreen / Go to Ground targets deprioritised (21197–21211) |
| Below half strength | ×1.5 | Finish wounded units (21213–21217) |
| CHARACTER | ×1.2 | Characters slightly favoured (21219–21222) |

### 6. Hold fire / Hidden economics (F002/F003)

| Term | Default value | Plain-English meaning |
|---|---|---|
| HIDDEN_FORFEIT_PENALTY | 0.0 (**off**; comment: "corpus-suggested 3.0") | Price of surrendering Hidden for two turns by shooting (1886, 23790–23805). At 0.0 the AI never holds fire |
| shot worth scale | kill-fraction × 10 | A guaranteed full kill is worth 10, comparable to SCREEN_SCORE_BASE = 8.0 (13404–13409, 1924) |
| immunity fraction | 0..1 | Fraction of enemy shooters outside detection range (default 15") of the hidden unit (23746–23771) |
| HIDDEN_WINDOW_BONUS | 1.0 (**off**; comment: "corpus-suggested 1.25") | Would prioritise enemies about to regain Hidden (1890, 14433–14438, 23810–23826) |

## Worked example

Invented but realistic. The AI (Space Marines) has two shooters: a **Devastator with one lascannon**
(BS 3+, S12, AP−3, D6+1 damage ⇒ avg 4.5) and a **10-man Tactical squad with bolters** (BS 3+, S4,
AP0, D1), both ~18" from two enemies: a **Rhino** (VEHICLE, T9, Sv3+, 10 wounds, one model) and
**10 Ork Boyz** (T5, Sv5+, 1 wound each). Minor terms (tempo, secondaries, leader buffs) ignored;
say target_value works out to **2.2 for the Rhino** (points + vehicle ×1.2) and **1.9 for the Boyz**
(model-count firepower + objective presence).

**Damage matrix** (`_estimate_weapon_damage`):
- Lascannon → Rhino: 1 atk × 4/6 hit × 4/6 wound (S12>T9) × 5/6 unsaved (3+ save at AP−3 ⇒ 6+) ×
  4.5 dmg = **1.67**, × efficiency 1.4 (anti-tank vs vehicle) = **2.33**.
- Lascannon → Boyz: 1 × 4/6 × 5/6 (S12≥2×T5 ⇒ 2+) × 1.0 (5+ save at AP−3 is impossible) × 1
  (damage capped at 1 wound/model) = 0.56, × efficiency 0.6 × 0.4 damage-waste = 0.24 ⇒ **0.13**.
- Bolters → Boyz: 10 models × 1 atk × 4/6 × 2/6 (S4<T5) × 4/6 (5+ save) × 1 = 1.48, × 1.4
  (anti-infantry vs horde) = **2.07**.
- Bolters → Rhino: 10 × 4/6 × 1/6 (S4, T9 ⇒ 6+) × 2/6 (3+ save) × 1 = 0.37, × 0.6 = **0.22**.

**Allocation** (`_calculate_marginal_value`; note efficiency multiplies in a second time here):
- Bolters→Boyz: useful 2.07 × 1.9 = 3.93; damage crosses 2 whole 1-wound models ⇒
  +2 × 1 × 1.9 × 0.6 = +2.28 ⇒ 6.21; not past 60% of the 10-wound wipe threshold, no ×2.5;
  × efficiency 1.4 ⇒ **8.7**.
- Lascannon→Rhino: useful 2.33 × 2.2 = 5.13; no whole-model crossing (0→2.33 of 10 wounds);
  × efficiency 1.4 ⇒ **7.2**.
- Lascannon→Boyz: 0.13 × 1.9 × 0.24 ≈ **0.06**. Bolters→Rhino: 0.22 × 2.2 × 0.6 ≈ **0.29**.

Iteration 1 assigns **bolters → Boyz** (8.7, the board-wide best) and books 2.07 damage against the
Boyz. Iteration 2 re-scores the lascannon: Rhino 7.2 still crushes Boyz 0.06 (which would now also
be shaved by the 2.07 already allocated), so **lascannon → Rhino**. The final plan sends each unit
at a different target — coordinated split fire — and had a *second* lascannon existed, iteration 3
would have added it to the Rhino (7.2 again, since only 2.33 of 10 wounds is booked) rather than
spraying the Boyz. Only once the Rhino's allocation reached 10 × 1.15 = 11.5 would OVERKILL_TOLERANCE
zero its useful damage and push further guns elsewhere.

## Difficulty gates

From `40k/scripts/AIDifficultyConfig.gd` (values are code, not config):

| Gate | Easy | Normal | Hard | Competitive | Effect on shooting |
|---|---|---|---|---|---|
| `use_random_actions` (23–24) | yes | no | no | no | Easy skips all scoring: `decide()` line 3047 routes to `_decide_random`, which picks a random shooter and fires everything at one random target via the greedy fallback (3492–3524) |
| `use_stratagems` (29–30) | no | yes | yes | yes | Gates the Grenade stratagem check at 13117–13119 and faction stratagems |
| `use_multi_phase_planning` (33–34) | no | no | yes | yes | Hard+ builds movement→shooting→charge plans; this is what feeds `_is_charge_target` so the ×0.5 don't-shoot-my-charge-target suppression (13719) only has data on Hard+ |
| `use_focus_fire` (37–38) | no | yes | yes | yes | **Declared but never called** — no call site exists, so the focus-fire plan actually runs at every non-Easy difficulty regardless |
| `use_weapon_efficiency` (53–54) | no | yes | yes | yes | Also declared with no call site; efficiency matching always runs on the scoring paths |
| `get_score_noise` (72–83) | 100.0 | 1.5 | 0.5 | 0.0 | Random noise added to scores elsewhere in the file (2074); the shooting allocator itself does not add noise to marginal values |

Net effect: **Easy = random shooting; everything else uses the full focus-fire machinery**, with
Hard/Competitive differing mainly through multi-phase planning (charge-target suppression) and
stratagem/other-phase behaviour rather than different shooting weights.

## Evidence

Main file `40k/scripts/AIDecisionMaker.gd`:
- 109–110, 240: focus-fire plan static caches; 3050–3056 cache reset outside shooting
- 2965, 3047–3048, 3133: `decide()` entry, Easy random diversion, shooting dispatch
- 3485–3524: Easy-mode random shooting
- 13035–13473: `_decide_shooting` — housekeeping (13044–13112), grenade/stratagem/mission actions
  (13117–13193), plan build + unit selection (13197–13263), pistol filter (13275–13291),
  shootable enemies (13304), plan consumption + LoS/destroyed filtering (13328–13357),
  hold-fire F002 (13394–13449), SHOOT emission (13461–13468), END_SHOOTING (13470–13473)
- 13475–13530: `_emit_shooting_records`; 13541–13602: alternatives capture (SHOOTING_ALTERNATIVES_K = 6 at 125)
- 13608–13905: `_build_focus_fire_plan` — weapon inventory (13633–13688), kill thresholds/target
  values + tempo + charge suppression (13690–13725), damage matrix with pistol/Lone-Op/LoS zeroing
  (13727–13766), marginal allocation loop (13795–13847), per-unit plan + model_ids (13849–13863)
- 13907–13913: `_calculate_kill_threshold`; 13990–14022: `_calculate_tempo_modifier`
- 14245–14478: `_calculate_target_value` (points 14274, PPW 14278–14282, ranged/melee output
  14290–14359, abilities 14363–14373, character 14376–14383, vehicle 14386–14387, low health
  14390–14392, objectives 14394–14426, hidden window 14433–14438, secondaries 14440–14467,
  aggression 14469–14476)
- 14480–14554: `_calculate_marginal_value` (overkill 14509/14541, model kills 14526–14534, wipe
  bonus 14537–14538, efficiency 14544, low health 14547–14552)
- 14556–14673: `_estimate_weapon_damage` (cover 14605–14614, probabilities 14621–14625, keywords
  14628–14638, overflow cap 14640–14646, carriers 14648–14652, FNP 14656–14660, efficiency 14671–14673)
- 14675–14753: `_build_unit_assignments_fallback`; 21046–21232: `_score_shooting_target`
- 20850–20976: `_apply_weapon_keyword_modifiers`; 20978–20989 half-range helper
- 21241–21344: weapon-role / target-type classifiers; 21346–21398: `_calculate_efficiency_multiplier`
- 21400–21403: `_get_target_wounds_per_model`; 21405+: `_parse_average_damage` (D3 = 2, D6 = 3.5)
- 20179–20185: `_get_alive_model_ids`; 20248–20255: `_get_shootable_enemy_units` (attached-leader filter, comment 20239–20247)
- 23728–23805: Hidden helpers (`_unit_is_currently_hidden`, `_hidden_immunity_fraction`,
  `_hidden_forfeit_cost`); 23810–23826: `_target_regains_hidden_soon`
- Constants: 41 (OBJECTIVE_CONTROL_RANGE_PX), 125, 1753–1755, 1759–1784, 1886, 1890, 1924, 1941,
  1950, 1954–1960, 1975, 2041–2052
- Parameter layering: 1235–1275 (`get_param`/`get_param_int`), 291–298 (`load_config_overrides`
  reads `res://data/ai_config.json` then `user://ai_config.json`)

Other files:
- `40k/scripts/AIDifficultyConfig.gd`: 23–24, 29–30, 33–38, 53–54, 72–83, 141–151
- `40k/scripts/rules/AttackSequence.gd`: 97–107 (wound chart), 112–113 (hit), 117–118 (wound), 124–128 (save)
- `40k/autoloads/AIPlayer.gd`: 175 (`load_config_overrides` call), 769 (Easy random gate)
- `40k/data/ai_config.json`: `parameters` contains only `PLANS_ENABLED: 1` — no shooting weight overrides, so all defaults above are effective
