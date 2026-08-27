# AI Explainer: Charge and Fight Phases

All file references are to `40k/scripts/AIDecisionMaker.gd` unless another file is named.
All weight values below are the **effective in-game values**: `40k/data/ai_config.json` overrides code defaults, but its `parameters` block currently contains only `PLANS_ENABLED: 1` (ai_config.json lines 16-18), so **every charge/fight weight runs at its code default**. Each weight is read through `get_param()` (line 1235), whose priority is: per-rule overrides → per-player profile → ai_config.json → code default.

## Overview

When it is time to charge, the AI looks at every unit that is allowed to declare a charge and every enemy it could charge, and gives each charger→target pair a score. The score starts from "how much melee damage would I expect to do to this target", then adds bonuses for things a good player cares about (the target is a character, it is sitting on an objective, it is a dangerous shooter worth locking up, it is nearly dead, friends are already piling onto it) and subtracts for risks (the defender could fire Overwatch, the target is too tough to hurt). That whole score is then multiplied by the real mathematical chance that a 2D6 roll covers the distance, so a juicy target 11" away scores far less than a decent target 4" away. Only the single best-scoring charge is declared per decision; if even the best one falls below a "worth it" threshold — which moves up and down with the battle round, how far behind on points the AI is, its faction's aggression, and the difficulty setting — the AI skips charging with that unit instead. After a failed charge roll, the AI decides whether to spend 1 CP on a Command Re-roll using simple odds-based rules (never chase a needed 11+, always retry a near miss). In the fight phase, the AI first sorts all of its engaged units into an activation order — units that can outright wipe their target or are about to die fight first — then, for each unit, piles in up to 3" toward the nearest enemy, picks the melee target and weapon that maximise a damage-plus-strategy score, and finally consolidates 3" either to wrap/tag more enemies or toward a nearby objective. Both phases keep a shared "ledger" of who is already attacking each target so several units gang up to actually finish kills instead of spreading damage thinly.

## Decision flow

### Charge phase (`_decide_charge`, line 14759)

Executed in strict priority order each time the AI is asked for an action:

1. **Reaction windows first** — Command Re-roll fallback decline (lines 14774-14785; the real decision happens in the signal handler, see step 8), Fire Overwatch as defender (14788-14829), Heroic Intervention as defender (14832-14857), Tank Shock after a charge (14860-14868), applying a Heroic Intervention move (14871-14880).
2. **Finish an in-progress charge** — `COMPLETE_UNIT_CHARGE` (14883-14892).
3. **Apply a successful roll** — `APPLY_CHARGE_MOVE` (14895-14906). At 11th edition the AI first re-picks targets post-roll from the "selectable" list (`_select_post_roll_charge_targets`, 16023-16066): if the declared target survived the roll it is kept; if the roll dropped it, the best-scoring reachable target is chosen instead. The actual model placement (`_compute_charge_move`, 16068) honours the rolled distance, terrain penalties, "each model ends closer", engagement range with every declared target, no contact with non-targets, coherency, and the 11.04 "end within 1 inch if able" rule; if no legal move exists it returns `SKIP_CHARGE`.
4. **Roll the dice** — `CHARGE_ROLL` (14909-14918).
5. **Declare the best charge** — `_evaluate_best_charge` (14921-14924, body at 14945). See scoring below.
6. **Decline** — if no charge beats the threshold, `SKIP_CHARGE` for the unit (14927-14936): logged as "no good target".
7. **End the phase** — `END_CHARGE` (14939).
8. **Command Re-roll on charge rolls** (out-of-band): `ChargePhase` emits `command_reroll_opportunity`; `AIPlayer._on_command_reroll_opportunity` (40k/autoloads/AIPlayer.gd 1488-1558) computes the distance still needed (min distance minus engagement range, 1519) and calls `evaluate_command_reroll_charge` (AIDecisionMaker 23226-23267). Re-roll rules, in order:
   - Charge already made → never (23235).
   - Needed distance > 10" → never, odds too low (23241).
   - Missed by ≤ 2 and need ≤ 9" → always re-roll (23248).
   - Rolled ≤ 4 (a terrible roll) and need ≤ 9" → re-roll (23254).
   - Otherwise, re-roll only if the AI has ≥ 3 CP banked and need ≤ 9" (23260-23263); else keep the CP.

**How `_evaluate_best_charge` scores a candidate (14945-15238):**

1. Collect every `DECLARE_CHARGE` offer, keyed by charger, with the closest-model edge-to-edge distance to each target (14951-14975).
2. Per charger: `melee_bonus` = 1.0 if the unit has real melee weapons, 0.3 if not (14992), times any melee-leader ability multiplier (14996-14999). Estimate Overwatch risk once per charger (15002, method at 15659 — see table).
3. Per target: effective charge distance = closest-model distance − engagement range (2" at 11e) + terrain climb penalty (15026-15028); convert to a true 2D6 probability (`_charge_success_probability`, 15240-15259). **Candidates under 3% success (needing 12) are discarded outright** (15035-15038).
4. Score = `_score_charge_target` (15436, see table) × charge probability × melee_bonus (15051), then reliability multipliers for short charges (15054-15057), on-objective multipliers (15064-15069), Overwatch penalty multiplier (15072-15073), a Deadly-Demise-on-a-doomed-vehicle bonus (15078-15083: ×1.5 for D3, ×2.0 for D6), and per-difficulty random noise (15086).
5. **Multi-charge** (`_evaluate_multi_target_charge`, 15263): every pair and triple among the 5 closest viable targets is also scored (15277-15299). A combo is feasible only if the targets are physically close enough for one unit to touch all of them (15318-15341). The combo uses the **farthest** target's distance for the single shared probability (15343-15350), is discarded under 8% success (15353), sums the raw target scores, and applies: +15% per extra target (15381), ×1.1 if the targets are within 2" of each other (15386-15389), combo short-charge and objective multipliers (see table). If a combo outscores the best single charge, the multi-target declaration wins (15119-15122).
6. **The charge threshold** (declared only if best score ≥ threshold, 15167-15170). It starts at 1.0 and is adjusted in this order:
   - *Tempo (behind on VP)*: threshold = max(1.0 − (tempo − 1.0) × 0.4, 0.3) when the tempo modifier > 1 (15125-15130). Tempo itself (`_calculate_tempo_modifier`, 13990-14022) rises 0.1 per VP behind (capped at 1.5, or up to 1.8 in rounds 4-5 desperation).
   - *Difficulty* multiplier (15133): Easy ×2.0, Normal ×1.0, Hard ×0.85, Competitive ×0.7 (AIDifficultyConfig.gd 105-116).
   - *Round strategy × army archetype* (15138-15142): rounds 1-2 ×0.5, round 3 ×1.0, rounds 4-5 ×1.3 (14030-14053), further multiplied by archetype: MELEE army ×0.75, SHOOTING ×1.3, ELITE ×1.0 (1993, 1999, 2005).
   - *Faction aggression* divides the threshold when > 1.0 (15159-15164): Orks 1.2, Custodes 1.5, World Eaters 2.0, Khorne 1.8, default 1.0 (2019-2023).
7. **Coordination ledger**: every declared charge is recorded per target — charger list plus summed expected damage (15224-15236) — in `_charge_coordination`, which is cleared when the battle round changes or the phase is left (3066-3074). Later chargers read it (see scoring table) so the AI piles multiple units onto one target when that finishes a kill.

### Fight phase (`_decide_fight`, line 16595)

1. **Moment Shackle** (Trajann special) answered first (16608-16638).
2. Mechanical steps in order: `ROLL_DICE` (16654), `CONFIRM_AND_RESOLVE_ATTACKS` (16658).
3. **Pile in, then assign attacks** (16662-16690). A unit that failed to assign attacks twice is skipped to break loops (16679-16687).
4. **Select which unit fights next** (16700-16786): the first time each fight phase, `_build_fight_order_plan` (17200) scores every engaged friendly unit with `_score_fighter_priority` (17259, see table), adds difficulty noise, and sorts descending. When the engine offers a choice of fighters, the AI picks the highest-planned unit among those actually offered (16733-16741). Fight-phase faction stratagems (crit-5+ / extra-attacks types) are fired on the chosen unit before it is selected (16769-16780).
5. **Consolidate** (16790-16793), then end-of-step actions `END_CONSOLIDATION` / `END_PILE_IN` (16797-16814), Sweeping Advance / Acrobatic Escape specials (16817-16829), `END_FIGHT` (16832).

**Pile-in placement** (`_compute_pile_in_movements`, 17526-17773): each model may move up to 3" (17587). Models already in base contact hold (17649-17658). Models are processed closest-to-enemy first (17624); each moves straight at the closest enemy model, aiming for base-to-base contact (17665-17673); on collision it searches rings of nearby spots that still fit the 3" budget and still end closer to the enemy (17693-17721), otherwise it holds. Every move is re-checked to end closer than it started (17734-17746). Attached characters' models are folded into the same move (17508).

**Target choice within engagement** (`_assign_fight_attacks`, 16837): only enemies actually in engagement range are considered (16877), and an engaged attached CHARACTER is remapped to its bodyguard unit per rule 19.02 (16877-16881) so the AI never wastes an activation on an illegal leader pick. For each engaged enemy the AI computes the best primary melee weapon (plus all Extra Attacks weapons, plus the default close-combat-weapon fallback) by raw expected damage (16933-16971), then ranks targets by `_score_fight_target` (17057, see table) and attacks the top scorer with that weapon (17047-17053).

**Fight damage ledger** (`_fight_coordination`): after picking a target the AI records attacker id and expected damage per target (17038-17045); the dictionary resets when the battle round changes (17039-17041). Later fighters consult it in `_score_fight_target` (17140-17156): +5.0 (+7.0 for a 10+ model horde) when their damage finishes what earlier fighters started, +2.5 (+3.5 horde) when it covers half the remainder, and −1.0 when the target is already over-killed. A first attacker also gets a proactive gang-up seed of 4.0 + 2.0 × min(other engaged friendlies, 3) when it is a horde unit sharing the combat (17158-17192).

**Consolidate placement** (`_compute_consolidate_action`, 17792): the mode is a hard rules gate (`_determine_ai_consolidate_mode`, 17852-17957) — ENGAGEMENT if any enemy model is within 3" edge-to-edge (mandatory), otherwise OBJECTIVE only if an objective is within 3" (measured with the 20mm marker radius, 3.787"), otherwise hold still (the normal case after wiping the enemy). ENGAGEMENT mode (17959-18302) works in three priorities per model: (1) *tag* enemy units not yet engaged that are reachable within 3"+ER (18036-18053, tag-capable models move first, 18112-18120); (2) *wrap* — if base contact is reachable, try angles on the FAR side of the enemy first (180°, then ±135°, ±90°, ±45°, then straight on) to block its retreat, skipping angles already claimed by other models (18169-18232); (3) fall back to a straight pile-in-style move (18234-18280). OBJECTIVE mode moves each model up to 3" toward the closest objective (18311+).

## Scoring tables

### Charge target score — `_score_charge_target` (line 15436), additive then multiplied

| Term | Default value | Plain-English meaning |
|---|---|---|
| `CHARGE_MELEE_DAMAGE_WEIGHT` (1418, 15448) | 2.0 | Each point of expected melee damage adds 2 to the score — the backbone of the score |
| `CHARGE_BELOW_HALF_BONUS` (1419, 15461) | +3.0 | Target unit is already below half its models — finish it |
| `CHARGE_CHARACTER_BONUS` (1420, 15465) | +2.0 | Target is a CHARACTER |
| `CHARGE_CANT_HURT_PENALTY` (1421, 15473) | −1.0 | We expect under 1 damage — still mildly useful (ties them up), so only a small penalty |
| `CHARGE_TIE_UP_SHOOTER_BONUS` (1422, 15480) | +2.0 | Target has ranged weapons of 24"+ — charging stops it shooting |
| `PHASE_PLAN_LOCK_SHOOTER_BONUS` (1940, 15489) | +3.0 (×1.5 if very dangerous) | Target was pre-flagged this turn as a dangerous shooter to lock in combat |
| `CHARGE_LOW_TOUGHNESS_BONUS` (1304, 15500) | +1.0 | Target is Toughness 3 or less — easy to wound |
| Melee leader multiplier (15506-15508) | ×(ability-derived) | Charger has a leader buffing its melee |
| Defensive multiplier divisor (15514-15517) | ÷(ability-derived) | Target has defensive abilities — harder to kill, lower score |
| Trade efficiency (15520-15522; consts 1951-1952) | ×0.7 to ×1.3 | Points-per-wound ratio: trading up multiplies, trading down penalises |
| `CHARGE_GANG_UP_BONUS` (1301, 15550) | +3.0 | A friendly unit is already fighting this target |
| Coordination seed (15589) | +3.0 + 2.0×min(others,3) | First charge on a target while other friendlies are in charge range — only for factions with aggression ≥ 1.5 |
| Gang-up kill bonus (15610-15615) | +5.0 (+7.0 if aggression ≥ 1.5) | Combined damage of all declared chargers now kills the target |
| Gang-up pile bonus (15611, 15621) | +2.0 (+3.0) per prior charger | Piling on even without a certain kill |
| `CHARGE_HALF_KILL_BONUS` (1302, 15630) | +3.0 | Our damage covers 50%+ of the target's REMAINING wounds |
| `CHARGE_LIKELY_KILL_BONUS` (1303, 15632) | +5.0 | Our damage alone likely kills the target outright |
| Deadly Demise doomed bonus (15640-15643) | ×1.5 (D3) / ×2.0 (D6) | Doomed exploding vehicle should die in their lines |
| Round/archetype aggression (15649-15653) | ×1.3 rounds 1-2 / ×1.0 R3 / ×0.7 R4-5, × archetype 0.8-1.25 | Early game favours kills, late game favours objectives |
| `AAO_CLUMP_PENALTY` (2451, 15533) | −2.5 | Lions' "Against All Odds" armies only: charging into an occupied combat loses the solo buff |

Result is clamped at ≥ 0 (15655).

### Turning that into the declared charge — `_evaluate_best_charge` (14945)

| Term | Default value | Plain-English meaning |
|---|---|---|
| Melee bonus (14992) | ×1.0 melee / ×0.3 no melee | Units without melee weapons almost never charge |
| Charge probability (15032, 15051) | exact 2D6 odds | Need ≤2: 100%; 3: 97%; 4: 92%; 5: 83%; 6: 72%; 7: 58%; 8: 42%; 9: 28%; 10: 17%; 11: 8%; 12: 3% (15240-15259) |
| Minimum viable probability (15035) | 3% (8% for multi-charge, 15353) | Anything needing more than 12" is dropped |
| `CHARGE_SHORT_6IN_MULT` (1306, 15055) | ×1.2 | Needs 6" or less — reliable |
| `CHARGE_SHORT_3IN_MULT` (1305, 15057) | ×1.3 | Needs 3" or less — near-automatic (stacks: ×1.56 total) |
| `CHARGE_TARGET_ON_OBJ_MULT` (1307, 15066) | ×1.5 | Target stands on an objective |
| `STRATEGY_LATE_CHARGE_ON_OBJ_BONUS` (1974, 15068) | ×1.5 | Rounds 4-5: extra multiplier for on-objective targets |
| Overwatch penalty (15072, computed 15721-15749) | ×1.0 → ×0.2 | See Overwatch table |
| Multi-charge extra-target bonus (15381) | ×(1 + 0.15/extra target) | Locking more units is worth a modest premium |
| `CHARGE_COMBO_SHORT_6IN_MULT` / `_3IN_MULT` (1298-1299, 15373-15376) | ×1.2 / ×1.3 | Same reliability bonuses, judged on the farthest combo target |
| `CHARGE_COMBO_TIGHT_CLUSTER_MULT` (1300, 15389) | ×1.1 | Farthest combo target within 2" of the closest |
| `CHARGE_COMBO_OBJ_MULT` (1297, 15399) | ×1.3 | Any combo target on an objective |
| Charge threshold base (15126) | 1.0 | Best score must beat this to declare at all |
| `TEMPO_CHARGE_THRESHOLD_REDUCTION` (1960, 15129) | 0.4 per point of tempo, floor 0.3 | Behind on VP → accept more marginal charges |
| Difficulty threshold modifier (15133; AIDifficultyConfig.gd 105-116) | Easy 2.0 / Normal 1.0 / Hard 0.85 / Competitive 0.7 | Harder AI charges more willingly |
| `STRATEGY_EARLY_CHARGE` / `STRATEGY_LATE_CHARGE` (1969/1973, 15142) | ×0.5 R1-2 / ×1.3 R4-5 | Early rounds eager, late rounds picky |
| Archetype charge threshold (1993/1999/2005) | MELEE ×0.75 / SHOOTING ×1.3 / ELITE ×1.0 | Army style shifts willingness |
| Faction aggression divisor (15162; 2019-2023) | Orks 1.2, Custodes 1.5, World Eaters 2.0, Khorne 1.8, default 1.0 | Aggressive factions need less convincing |

### Overwatch risk on the charger — `_estimate_overwatch_risk` (15659)

| Condition | Value | Meaning |
|---|---|---|
| Defender has 0 CP (15667-15668) | penalty ×1.0 | Overwatch costs 1 CP — no CP, no risk |
| Expected OW damage < 0.5 (15726-15728) | ×1.0 | Negligible; overwatch hits only on 6s (1/6, 15804) |
| 0.5-2.0 damage (15729-15732) | ×1.0 → ×0.7 | "Moderate": penalty scales linearly |
| 2.0-4.0 damage (15733-15736) | ×0.7 → ×0.4 | "High" |
| > 4.0 damage (15737-15740) | ×max(0.2, 0.4 − 0.05/pt) | "Extreme" |
| Charger is a CHARACTER and damage ≥ 1 (15744-15745) | extra ×0.8 | Protect heroes |
| Damage ≥ half the charger's total wounds (15748-15749) | extra ×0.5 | Could gut the unit before it swings |

Only the single best enemy shooter within 24" counts, because Overwatch is once per turn (15722).

### Fight target score — `_score_fight_target` (17057)

| Term | Default value | Plain-English meaning |
|---|---|---|
| `FIGHT_MELEE_DAMAGE_WEIGHT` (1423, 17063) | 2.0 | Expected damage ×2 is the base score |
| `FIGHT_CAN_HALVE_BONUS` (1428, 17073) | +3.0 | Target already below half its models |
| `FIGHT_CHARACTER_BONUS` (1425, 17077) | +2.0 | Target is a CHARACTER |
| `FIGHT_CANT_HURT_PENALTY` (1426, 17083) | −3.0 | Under 1 expected damage — bigger penalty than at charge time (already locked in) |
| `FIGHT_CAN_WIPE_BONUS` (1427, 17090) | +6.0 | Our damage ≥ target's remaining wounds — likely full wipe |
| `FIGHT_BELOW_HALF_BONUS` (1424, 17093) | +3.0 | Our damage ≥ 50% of remaining wounds |
| `FIGHT_OVERKILL_PENALTY` (1429, 17098) | −1.0 | Damage > 3× remaining wounds — waste |
| `FIGHT_LOCK_LONG_RANGE` (1321, 17105) | +2.0 | Target has 24"+ guns |
| `FIGHT_LOCK_DANGEROUS_SHOOTER` (1320, 17108) | +1.5 | Its ranged output ≥ 5.0 (threshold at 1942) |
| `FIGHT_TARGET_ON_OBJ` (1332, 17115) | +2.0 | Target on an objective |
| `FIGHT_LOW_TOUGHNESS` (1322, 17121) | +1.0 | Toughness ≤ 3 |
| Defensive multiplier divisor (17127-17129) | ÷(ability-derived) | Harder-to-kill targets score lower |
| Trade efficiency (17132-17134) | ×0.7-×1.3 | Prefer favourable point trades |
| Ledger finish bonus (17146, 17149) | +5.0 (+7.0 horde) | Our damage finishes what earlier fighters started |
| Ledger significant bonus (17147, 17153) | +2.5 (+3.5 horde) | Covers half the remainder |
| `FIGHT_ALREADY_OVERKILLED` (1319, 17156) | −1.0 | Prior fighters already covered its wounds |
| Gang-up seed (17188) | +4.0 + 2.0×min(others,3) | Horde first-attacker with friends in the same combat |

### Fight activation order — `_score_fighter_priority` (17259)

| Term | Default value | Plain-English meaning |
|---|---|---|
| `FIGHT_ORDER_CAN_WIPE` (1324, 17298) | +6.0 | Can wipe its best target — go first, deny retaliation |
| `FIGHT_ORDER_HALF_KILL` (1328, 17301) | +3.0 | Can take it below half |
| `FIGHT_ORDER_DAMAGE_WEIGHT` (1326, 17305) | ×1.0 per damage | Raw expected damage added directly |
| `FIGHT_ORDER_CHARACTER` (1325, 17312) | +2.0 | Best target is a CHARACTER |
| `FIGHT_ORDER_DANGEROUS_SHOOTER` (1327, 17318) | +2.0 | Best target is a dangerous shooter (output ≥ 5.0) |
| `FIGHT_ORDER_TARGET_ON_OBJ` (1331, 17325) | +1.5 | Best target on an objective |
| `FIGHT_ORDER_LIKELY_TO_DIE` (1329, 17336) + `SURVIVAL_LETHAL_THRESHOLD` (2034) | +3.0 when incoming ≥ 75% of our wounds | Doomed unit swings before it dies |
| `FIGHT_ORDER_BADLY_HURT` (1323, 17339) + `SURVIVAL_SEVERE_THRESHOLD` (2035) | +1.5 when incoming ≥ 50% | Badly threatened unit goes early |
| `FIGHT_ORDER_MASSIVE_OVERKILL` (1330, 17343) | −1.5 when damage > 2.5× target wounds | Let cheaper units mop up chaff |
| Melee-leader multiplier (17347-17349) | ×(ability-derived) | Buffed units prioritised |
| Round/archetype aggression (17353-17357) | ×0.8-×1.3 | Same early/late scaling as charges |
| Not engaging anyone / can't hurt anyone (17272-17293) | 0.0 / 0.5 flat | Goes last |

## Worked example (invented but realistic numbers)

Round 1. An Ork Boyz mob (has melee weapons, faction aggression 1.2) can charge Intercessors whose closest model is **5.2" away** edge-to-edge. Normal difficulty. The Intercessors are NOT on an objective; they carry 24"-range bolt rifles; the defender has 1 CP and their best shooter's expected Overwatch damage against the Boyz is 1.2.

**Target score** (`_score_charge_target`): expected melee damage 6.0 → 6.0 × 2.0 = **12.0**; +2.0 tie-up-a-24"-shooter = **14.0**; T4 so no low-toughness bonus; damage is under half the squad's 10 remaining wounds so no kill bonuses; trade efficiency ≈ 1.0. Round 1-2 aggression ×1.3 → **18.2**.

**Charge math**: effective distance = 5.2" − 2" ER + 0 terrain = **3.2"**, so the 2D6 roll must be ≥ 4 → probability **33/36 = 91.7%** (15240). Score = 18.2 × 0.917 × 1.0 melee bonus = **16.7**. Needs ≤ 6" → ×1.2 = **20.0** (not ≤ 3", so no ×1.3). Overwatch: 1.2 expected damage is "moderate" → penalty = 1.0 − (1.2 − 0.5) × 0.2 = **×0.86** → **17.2**. Normal-difficulty noise adds ±1.5 → say **17.6**.

**Threshold**: 1.0 base; not behind on VP so no tempo cut; Normal difficulty ×1.0; rounds 1-2 ×0.5 → 0.5; assume BALANCED archetype ×1.0; Ork aggression divides by 1.2 → **0.417**.

17.6 ≥ 0.417, so the AI declares: *"Boyz declares charge against Intercessors (92% chance, 5.2" away, expected 6.0 melee dmg vs 10 HP, overwatch risk: 1.2 dmg)"* and records the charge in the coordination ledger — a second Boyz mob evaluating the same Intercessors would now add +3.0 per prior charger, or +7.0 if the combined damage tips past 10 wounds. If the subsequent 2D6 roll came up 3 (needed 4): missed by 1 with need ≤ 9, so the AI spends 1 CP on a Command Re-roll (rule at 23248).

## Difficulty gates

| Feature | Easy | Normal | Hard | Competitive | Source |
|---|---|---|---|---|---|
| Charge logic | Random: 20% chance to declare a random charge, else skip (`_decide_random_charge`, 3537-3559) | Full scoring | Full scoring | Full scoring | AIDifficultyConfig.gd 23-24; dispatch 3046-3048, 3382-3384 |
| Fight logic | **Uses the normal fight logic even on Easy** (sequencing too complex to randomise) | Full | Full | Full | 3386-3388 |
| Charge threshold modifier | ×2.0 (moot — Easy uses the random path) | ×1.0 | ×0.85 | ×0.7 | AIDifficultyConfig.gd 105-116 |
| Score noise (added to charge scores and fight order) | ±100 (random) | ±1.5 | ±0.5 | 0 | AIDifficultyConfig.gd 72-83; applied 15086, 15415, 17236 |
| Command Re-roll | Never (auto-decline) | Evaluated | Evaluated | Evaluated | AIDifficultyConfig.gd 100-101; AIPlayer.gd 1500-1509 |
| Multi-phase planning (charge-intent / lock-shooter flags feeding the +3.0 lock bonus) | Off | Off | On | On | AIDifficultyConfig.gd 33-34 |
| Trade analysis / look-ahead flags | Off | Off | Off | On | AIDifficultyConfig.gd 45-50 |

## Evidence

- `40k/data/ai_config.json` 16-18 — only `PLANS_ENABLED` overridden; all weights below are effective defaults. Layering documented at AIDecisionMaker.gd 289-298 (res://data then user:// then profiles), `get_param` priority 1235-1256.
- Charge phase flow: `_decide_charge` 14759-14939; reaction windows 14774-14868; post-roll retarget 16023-16066; charge move solver `_compute_charge_move` 16068-16134 (constraints in docstring 16069-16083).
- Charge evaluation: `_evaluate_best_charge` 14945-15238; melee bonus 14992; overwatch risk call 15002; distance/terrain/ER 15026-15028; 3% floor 15035; probability × bonus stack 15051-15073; Deadly Demise 15078-15083; noise 15086; threshold assembly 15124-15170; decline log 15167-15170; coordination record 15224-15236; ledger reset 3066-3074.
- 2D6 probability: `_charge_success_probability` 15240-15259.
- Multi-charge: `_evaluate_multi_target_charge` 15263-15301; feasibility 15318-15341; farthest-target probability 15343-15350; 8% floor 15353; +15%/target 15381; cluster 15386-15389; combo constants 1297-1300.
- Charge target scoring: `_score_charge_target` 15436-15655; constants 1301-1307, 1418-1422, 1940, 2451; gang-up ledger read 15595-15623; seed 15556-15593; trade efficiency 13978-13988 with clamps 1951-1952.
- Overwatch risk: `_estimate_overwatch_risk` 15659-15756; damage-per-6s model 15758-15811.
- Melee damage estimator: `_estimate_melee_damage` 15813-15958 (keyword modifiers 15902-15911, wound-overflow cap 15926-15928, WAAAGH! buffs 15833-15885, FNP 15952-15956).
- Command Re-roll: `evaluate_command_reroll_charge` 23226-23267; AIPlayer handler 40k/autoloads/AIPlayer.gd 1488-1558; difficulty gate AIPlayer.gd 1500-1509; in-phase decline fallback 14774-14785.
- Fight phase flow: `_decide_fight` 16595-16835; retry-break 16679-16687; fighter selection 16700-16786.
- Fight attacks: `_assign_fight_attacks` 16837-17053; engagement filter + 19.02 leader→bodyguard remap 16877-16881; weapon comparison 16933-16971; ledger write 17038-17045.
- Fight target scoring: `_score_fight_target` 17057-17194; constants 1319-1322, 1332, 1423-1429; ledger read 17140-17156; gang seed 17158-17192.
- Fight order: `_build_fight_order_plan` 17200-17256; `_score_fighter_priority` 17259-17359; constants 1323-1331, 2034-2035.
- Pile-in: `_compute_pile_in_action` 17491-17524; `_compute_pile_in_movements` 17526-17773; 3" budget 17587; base-contact hold 17649-17658; collision ring search 17693-17721.
- Consolidate: `_compute_consolidate_action` 17792-17850; mode gates `_determine_ai_consolidate_mode` 17852-17957; engagement mode with tagging 18036-18053 and far-side wrapping 18169-18232; objective mode 18311+.
- Tempo/strategy/faction: `_calculate_tempo_modifier` 13990-14022 (constants 1954-1960); `_get_round_strategy_modifiers` 14024-14053 (constants 1966-1975); archetype 14059-14157 with modifier constants 1984-2005; faction aggression 2087-2100 (constants 2019-2023).
- Difficulty: `40k/scripts/AIDifficultyConfig.gd` — random actions 23-24, score noise 72-83, command reroll gate 100-101, charge threshold modifier 105-116, planning gates 33-50; Easy charge path AIDecisionMaker.gd 3537-3559, dispatch 3046-3048 and 3382-3388.
