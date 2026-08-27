# AI Explainer — Cross-Cutting Behavior Modifiers

**Covers:** round strategy stances, tempo (VP-based aggression), the four difficulty tiers, and enemy threat zones.
**Sources:** `40k/scripts/AIDecisionMaker.gd` (24,318 lines, all static), `40k/scripts/AIDifficultyConfig.gd`, `40k/autoloads/AIPlayer.gd`, `40k/data/ai_config.json`.

> **Are these the real, in-effect numbers?** Yes. The shipped `40k/data/ai_config.json` sets only one parameter, `PLANS_ENABLED: 1` — which is already the code default (`AIDecisionMaker.gd:421` uses default `1.0`). Every weight below is therefore the **effective** value unless a per-machine `user://ai_config.json` or a player profile exists on the player's computer (layering order documented at `AIDecisionMaker.gd:291-298` and `AIDecisionMaker.gd:1235-1256`: rule overrides > player profile > config file > code default).

---

## Overview

The AI does not use one fixed personality — three "dials" continuously reshape every score it computes. First, the **round strategy stance**: in battle rounds 1–2 the AI is deliberately aggressive (kills and forward movement are worth ~30% more, safety worth 30% less), round 3 is neutral, and rounds 4–5 flip to an objective-and-survival mindset (objectives worth 60% more, kills worth 30% less). Second, **tempo**: the AI reads the victory-point scoreboard every decision — when it is losing, it plays up to 50% more aggressively, and from round 4 onward a losing AI enters "desperation mode" (up to 1.8× aggression, and it will accept charges it would normally decline). When winning, it dials back to about 0.8× and plays to protect its lead. Third, **threat zones**: for every enemy unit the AI draws two invisible danger circles — a charge circle (enemy Move + 12" charge + 2" engagement range) and a shooting circle (longest gun range) — and moving into those circles costs points off a movement candidate's score, weighted by how dangerous that enemy is and how deep into the circle the move ends. Finally, the four **difficulty tiers** gate which of these brains are switched on at all: Easy is literally random, Normal has the full tactical core (threat zones, tempo, stratagems), Hard adds multi-phase planning and less random scoring, and Competitive removes score randomness entirely and charges the most willingly. All three modifier systems multiply together with faction and army-archetype modifiers, so an Ork army, losing, in round 4, stacks several aggression boosts at once.

---

## Decision flow

Ordered as the code actually executes when the AI takes a turn (`AIDecisionMaker.decide()`, entered at `AIDecisionMaker.gd:2966` where `_current_difficulty` is stored):

1. **Difficulty check — Easy bails out immediately.** `use_random_actions()` is true only for Easy, and the AI returns a random valid action with no scoring at all (`AIDecisionMaker.gd:3047-3048`, `AIDifficultyConfig.gd:23-24`). Nothing below applies to Easy.
2. **Round stance is computed.** `_get_round_strategy_modifiers(battle_round)` returns 4 multipliers + a label: rounds 1–2 → `AGGRESSIVE`, round 3 → `BALANCED` (all 1.0), rounds 4–5 → `OBJECTIVE/SURVIVAL` (`AIDecisionMaker.gd:14024-14053`). It is then multiplied component-by-component with the army-archetype modifiers via `_apply_army_archetype_to_strategy()` (`AIDecisionMaker.gd:14228-14236`).
3. **Multi-phase planning gate.** Below Hard, the movement→shooting→charge phase plan is suppressed (`AIDecisionMaker.gd:3110-3112`, `AIDifficultyConfig.gd:33-34`).
4. **Movement phase — threat data is built (Normal+).** `_calculate_enemy_threat_data()` runs only if `use_threat_awareness()` (Normal and above) (`AIDecisionMaker.gd:6773-6775`, `AIDifficultyConfig.gd:41-42`). Each enemy gets: charge-threat radius = Move + 12" + 2" engagement range; shooting-threat radius = longest weapon range; and a danger weight 0.3–3.0 (`AIDecisionMaker.gd:23893-23930`).
5. **Objective urgency is tempo-adjusted.** `_calculate_tempo_modifier()` (VP diff + round, `AIDecisionMaker.gd:13990-14022`) multiplies the priority of contestable objectives when behind, and adds a defensive bonus for held objectives when ahead (`AIDecisionMaker.gd:8665-8678`).
6. **Each movement candidate is scored.** Base score = objective priority × stance `objective_priority` (`AIDecisionMaker.gd:8909`). If the destination increases threat exposure by more than 0.5, the increase × stance `survival` is subtracted (`AIDecisionMaker.gd:9007-9017`); overwatch risk is also × `survival` (`AIDecisionMaker.gd:9033`). A melee-only unit ignores 95% of charge-threat penalties (`THREAT_MELEE_UNIT_IGNORE`, `AIDecisionMaker.gd:24020-24021`). If a safe unit's best move would walk it from near-zero charge threat into heavy threat (≥3.0), the AI considers just standing still instead (`AIDecisionMaker.gd:7192-7215`). Final destinations are run through `_find_safer_position()`, which tries sideways dodges and shorter moves scoring `progress×1.5 − threat` (`AIDecisionMaker.gd:24090-24180`, called at 11253-11255).
7. **Difficulty noise is injected at comparison points.** Unit-assignment ordering (`AIDecisionMaker.gd:6985-6986`), charge target scores (15086, 15415) and fight-order scores (17236) each get ± noise via `_apply_difficulty_noise()` (`AIDecisionMaker.gd:2071-2077`): Easy 100.0 (moot — Easy never scores), Normal 1.5, Hard 0.5, Competitive 0.0.
8. **Shooting — tempo boosts objective-clearing.** When behind (tempo > 1.0), any enemy standing on an objective has its target value multiplied by the tempo modifier (`AIDecisionMaker.gd:13697-13713`). In rounds 4–5, targets on objectives get a further ×1.3 (`STRATEGY_LATE_OBJ_TARGET_BONUS`, `AIDecisionMaker.gd:14418-14422`), and all target values are multiplied by stance `aggression` (`AIDecisionMaker.gd:14472-14476`).
9. **Charge — threshold assembly.** The bar a charge score must clear starts at 1.0, then: lowered when behind — `max(1.0 − (tempo−1)×0.4, 0.3)` (`AIDecisionMaker.gd:15124-15130`); × difficulty modifier (Easy 2.0 / Normal 1.0 / Hard 0.85 / Competitive 0.7) (`AIDecisionMaker.gd:15133`, `AIDifficultyConfig.gd:105-116`); × stance `charge_threshold` (0.5 early / 1.0 mid / 1.3 late) (`AIDecisionMaker.gd:15138-15145`); ÷ faction aggression if > 1.0 (`AIDecisionMaker.gd:15159-15164`). If the best charge score is below the final threshold, no charge is declared (`AIDecisionMaker.gd:15167-15169`). Charge target scores themselves are × stance `aggression` (15653) and get ×1.5 in rounds 4–5 when the target sits on an objective (15068, 15401).
10. **Fight phase.** Fighter activation priority is × stance `aggression` (`AIDecisionMaker.gd:17351-17357`) plus difficulty noise (17236).
11. **Reactive windows (AIPlayer).** Overwatch, reactive stratagems, Counter-Offensive and Command Re-roll each check their difficulty gate before the AI will even consider them (`AIPlayer.gd:1045, 1158, 1192, 1388, 1501`).

---

## Scoring tables

### 1. Round strategy stances (`AIDecisionMaker.gd:1966-1975`, applied 14024-14053)

Battle-round mapping (`AIDecisionMaker.gd:14030-14053`): **rounds 1–2 → AGGRESSIVE**, **round 3 → BALANCED (all multipliers 1.0)**, **rounds 4–5 → OBJECTIVE/SURVIVAL**.

| Term | Default value | Plain-English meaning |
|---|---|---|
| `STRATEGY_EARLY_AGGRESSION` | 1.3 | Rounds 1–2: kill-seeking scores (shooting target value, charge value, fight priority) get +30% |
| `STRATEGY_EARLY_OBJECTIVE` | 0.95 | Rounds 1–2: objective scores at 95% — near-full weight, since grabbing objectives early matters for round-2 scoring |
| `STRATEGY_EARLY_SURVIVAL` | 0.7 | Rounds 1–2: threat/overwatch penalties shrink to 70% — the AI accepts more risk |
| `STRATEGY_EARLY_CHARGE` | 0.5 | Rounds 1–2: the charge bar is halved — much more willing to charge |
| `STRATEGY_LATE_AGGRESSION` | 0.7 | Rounds 4–5: kill-seeking scores cut by 30% |
| `STRATEGY_LATE_OBJECTIVE` | 1.6 | Rounds 4–5: objective control worth +60% |
| `STRATEGY_LATE_SURVIVAL` | 1.4 | Rounds 4–5: threat avoidance penalties +40% — keep units alive to hold ground |
| `STRATEGY_LATE_CHARGE` | 1.3 | Rounds 4–5: charge bar +30% — less willing to charge… |
| `STRATEGY_LATE_CHARGE_ON_OBJ_BONUS` | 1.5 | …except charges that clear an objective: +50% to that charge's score in rounds 4–5 (applied 15068, 15401) |
| `STRATEGY_LATE_OBJ_TARGET_BONUS` | 1.3 | Rounds 4–5: shooting targets standing on objectives worth +30% (applied 14422) |

What each multiplier touches: `aggression` → shooting target value (14476), charge target score (15653), fight priority (17357). `objective_priority` → movement objective score (8909). `survival` → threat-delta and overwatch penalties in movement (9014, 9017, 9033). `charge_threshold` → the declare-a-charge bar (15142). Note these are multiplied with **army archetype** modifiers of the same names before use (14228-14236), so a melee-heavy army shifts all of them further.

### 2. Tempo — VP-scoreboard aggression (`AIDecisionMaker.gd:1954-1960`, computed 13990-14022)

| Term | Default value | Plain-English meaning |
|---|---|---|
| `TEMPO_VP_DIFF_WEIGHT` | 0.1 | Each VP of deficit adds +0.10 aggression (each VP of lead subtracts 0.05 — the ahead case is halved at 14012) |
| `TEMPO_BEHIND_AGGRESSION_BOOST` | 1.5 | Cap on the behind boost: aggression never exceeds 1.5× from deficit alone (reached at 5 VP behind) |
| `TEMPO_AHEAD_CONSERVATION` | 0.8 | Floor when ahead: aggression never drops below 0.8× (reached at 4 VP ahead) |
| `TEMPO_DESPERATION_ROUND` | 4 | From battle round 4 onward, being behind at all triggers the desperation formula |
| `TEMPO_DESPERATION_MULTIPLIER` | 1.8 | Cap on desperation aggression: `1 + deficit × 0.1 × (3 / rounds_left)`, clamped to at most 1.8× |
| `TEMPO_MAX_ROUNDS` | 5 | Game length used to compute `rounds_left` in the desperation formula |
| `TEMPO_CHARGE_THRESHOLD_REDUCTION` | 0.4 | When behind, charge bar = `max(1 − (tempo−1)×0.4, 0.3)` — desperation makes marginal charges acceptable (15129) |

Where tempo is applied: objective urgency in movement — offensive states ×tempo; enemy strongholds get `+(tempo−1)×3` softening when behind; held objectives get `+(1−tempo)×2` when ahead (8668-8678). Shooting — targets on objectives ×tempo when behind (13706-13713). Charge — the threshold reduction above (15125-15130).

### 3. Threat zones (`AIDecisionMaker.gd:1834-1841, 1925`, computed 23893-24078)

Zone geometry (`AIDecisionMaker.gd:23910-23916`): **charge circle** = enemy Move + 12" (max charge) + 2" engagement range (2" is the 11th-edition value, `rules/GameConstants.gd:31-32`); **shooting circle** = enemy's longest weapon range. Each enemy also gets a danger weight `unit_value` of 0.3–3.0 (23932-23990): base 1.0, +0.5 for 10+ models, −0.2 for ≤2 models, +0.5 for T8+/W8+, +0.3 for W4+, +0.3 for CHARACTER/VEHICLE/MONSTER, +0.2/+0.3/+0.5 for increasingly nasty melee weapons.

Penalty at a position = depth-into-circle × danger weight × the penalty constant, summed over all enemies (24011-24060):

| Term | Default value | Plain-English meaning |
|---|---|---|
| `THREAT_CHARGE_PENALTY` | 2.0 | Base cost of standing inside an enemy's charge circle (scaled by depth and enemy danger) |
| `THREAT_CLOSE_MELEE_PENALTY` | 2.0 | Extra stacked cost within 12" of a melee enemy — it can charge without moving first (24033-24038) |
| `THREAT_SHOOTING_PENALTY` | 0.5 | Cost of standing inside an enemy's gun range — deliberately light, often unavoidable |
| `THREAT_MELEE_UNIT_IGNORE` | 0.05 | A melee-only AI unit multiplies charge-zone penalties by 0.05 — it *wants* to be there (24020-24021, 9029) |
| `THREAT_FRAGILE_BONUS` | 1.3 | Total threat ×1.3 for fragile units (Toughness ≤3 or 1 Wound) (24070-24071) |
| `THREAT_CLOSE_MELEE_DISTANCE_INCHES` | 12.0 | The "can charge without moving" danger radius (1841) |
| (hardcoded) character multiplier | 1.5 | Non-vehicle CHARACTERs multiply total threat ×1.5 so they hide behind cover (24006-24007, 24064) |
| `THREAT_SAFE_MARGIN_INCHES` | 2.0 | Defined at 1838 as a safety buffer but **never referenced anywhere else** — currently inert |

Application: movement candidates lose `threat_increase × survival-stance` when a move raises exposure by >0.5 (9007-9017); a safe unit may simply stay put rather than enter a ≥3.0 charge-threat destination, if faction aggression ≤1.2 (7192-7215); destinations are nudged sideways/shorter by `_find_safer_position()` scoring `inches-of-progress ×1.5 − threat` (24090-24180).

### 4. Difficulty tier numbers (`AIDifficultyConfig.gd`)

| Term | Easy | Normal | Hard | Competitive | Meaning |
|---|---|---|---|---|---|
| Score noise (`get_score_noise`, :72-83) | 100.0 | 1.5 | 0.5 | 0.0 | Random ± added to scores; 100 would drown all signal (Easy never scores anyway) |
| Charge threshold ×(`get_charge_threshold_modifier`, :105-116) | 2.0 | 1.0 | 0.85 | 0.7 | Lower = charges more willingly |
| Movement iterations (`get_movement_iterations`, :86-97) | 1 | 3 | 5 | 8 | Defined but **never called** — see Difficulty gates |

---

## Worked example

*(Invented but realistic; every number follows the code paths cited above.)*

**Situation:** Battle round 4. The AI (Space Marines, Normal difficulty, BALANCED archetype, faction aggression 1.0) trails **15 VP to 22** (deficit −7). An Intercessor squad weighs moving onto a contested objective that sits 8" from a 12-strong Ork Boyz mob (Move 6", big choppas, shootas 18").

**Step 1 — Tempo** (13990-14022): behind by 7 → `1.0 + min(7×0.1, 0.5) = 1.5`. Round 4 desperation: `rounds_left = 5−4+1 = 2`; urgency `= 1 + 7×0.1×(3/2) = 2.05`, clamped to `TEMPO_DESPERATION_MULTIPLIER` → **tempo = 1.8**.

**Step 2 — Round stance** (14046-14053): rounds 4–5 → aggression 0.7, objective 1.6, survival 1.4, charge bar 1.3.

**Step 3 — Objective urgency** (8668-8672): the contested objective's base priority, say 6.0, is ×1.8 tempo = **10.8**, then the movement score starts at 10.8 × 1.6 objective stance = **17.3** (8909).

**Step 4 — Threat penalty** (23893-24078): Boyz danger weight = 1.0 +0.5 (10+ models) +0.2 (decent melee) = **1.7**. Charge circle = 6+12+2 = **20"**; destination is 8" away → depth 0.6 → charge penalty 0.6×1.7×2.0 = **2.04**; inside 12" too → close-melee penalty (1−8/12)×1.7×2.0 = **1.13**; shootas (18") → (1−8/18)×1.7×0.5 = **0.47**. Total threat at destination ≈ **3.65** (current position ≈ 0). Movement deduction = 3.65 × 1.4 survival stance = **−5.11** (9014). Net movement score ≈ 17.3 − 5.1 = **12.2** — the objective still wins, but a destination 4" further from the Boyz would have kept ~4 more points, so `_find_safer_position()` may shave the approach sideways.

**Step 5 — Charge decision next phase** (15124-15167): threshold = 1.0 → tempo lowers it: `max(1 − (1.8−1)×0.4, 0.3) = 0.68` → ×1.0 Normal difficulty → ×1.3 late-round stance = **0.884**. The best charge (into the Boyz on the objective) scores, say, base 0.9 ×1.5 `STRATEGY_LATE_CHARGE_ON_OBJ_BONUS` ×0.7 late aggression ≈ **0.95** ± 1.5 Normal noise → usually clears 0.884: the desperate, losing AI declares a charge it would have declined at 22–15 up (threshold then: 1.0×1.0×1.3 = 1.3).

---

## Difficulty gates

Feature matrix — **"wired" means the gate function is actually called in game code**; several gates exist in `AIDifficultyConfig.gd` but are never consulted, so the feature runs at every scoring difficulty (verified by repo-wide grep — the only call sites are listed in Evidence).

| Feature | Easy | Normal | Hard | Competitive | Gate wired? (call site) |
|---|---|---|---|---|---|
| Random actions instead of scoring (:23) | **yes** | no | no | no | yes — AIDecisionMaker.gd:3047 |
| Stratagems, incl. reactive & Rapid Ingress (:29) | no | yes | yes | yes | yes — 5925, 13119, 21936; AIPlayer.gd:1045, 1192 |
| Focus fire coordination (:37) | – | yes | yes | yes | **no — never called**; runs whenever scoring runs |
| Threat-range awareness (:41) | – | yes | yes | yes | yes — AIDecisionMaker.gd:6774 |
| Multi-phase planning (move→shoot→charge) (:33) | no | no | yes | yes | yes — AIDecisionMaker.gd:3111 |
| Screening / deep-strike denial (:63) | – | **yes*** | yes | yes | **no — never called**; PASS 3 screening (9487-9610) runs for any scoring AI when the enemy has reserves |
| Trade look-ahead / trade analysis (:45) | – | **yes*** | yes | yes | **no — never called**; `_get_trade_efficiency` (13978-13988) applied unconditionally in charge (15520) and fight (17132) scoring |
| Opponent-response look-ahead (:49) | – | – | – | intended | **no — never called**; no code path consumes this flag |
| Weapon-target efficiency (:53) | – | yes | yes | yes | **no — never called** |
| Survival / fall-back assessment (:59) | – | yes | yes | yes | **no — never called** |
| Counter-deployment (:67) | no | yes | yes | yes | yes — AIDecisionMaker.gd:4848 |
| Score noise (:72) | 100.0 | 1.5 | 0.5 | 0.0 | yes — via `_apply_difficulty_noise` at 6985-6986, 15086, 15415, 17236 |
| Movement iterations (:86) | 1 | 3 | 5 | 8 | **no — never called** |
| Command Re-roll (:100) | no | yes | yes | yes | yes — AIPlayer.gd:1501 |
| Charge threshold modifier (:105) | 2.0 | 1.0 | 0.85 | 0.7 | yes — AIDecisionMaker.gd:15133 (via 2079-2081) |
| Fire Overwatch (:119) | no | yes | yes | yes | yes — AIPlayer.gd:1158 |
| Counter-Offensive stratagem (:123) | no | yes | yes | yes | yes — AIPlayer.gd:1388 |

\* The class comments (`AIDifficultyConfig.gd:7-10`) describe screening as Hard+ and trade analysis as Competitive-only, but since their gates are never consulted, **the effective behavior today is: Easy = pure random; Normal/Hard/Competitive all get screening and trade math**; the real tier differences are noise level, charge threshold, multi-phase planning, and Easy's randomness. Difficulty is set per player (default Normal) at `AIPlayer.gd:293-294`, read back at `AIPlayer.gd:597-599`, stored into the decision maker at `AIDecisionMaker.gd:2966` (static default Normal at 2390).

---

## Evidence

All paths absolute; `ADM` = `/home/user/warhammer-40k-godot/40k/scripts/AIDecisionMaker.gd`, `ADC` = `/home/user/warhammer-40k-godot/40k/scripts/AIDifficultyConfig.gd`, `AIP` = `/home/user/warhammer-40k-godot/40k/autoloads/AIPlayer.gd`.

- Config layering & effective values: ADM:229-231, 291-298, 1235-1256, 1258-1273; `/home/user/warhammer-40k-godot/40k/data/ai_config.json` (only `PLANS_ENABLED: 1`; default already 1.0 at ADM:419-421).
- Round stance constants: ADM:1966-1975. Round→stance mapping + labels: ADM:14024-14053. Archetype combination: ADM:14228-14236. Application: objective score ADM:8909; threat/overwatch × survival ADM:9014, 9017, 9033; shooting target value × aggression ADM:14472-14476; late obj-target bonus ADM:14418-14422; charge threshold × stance ADM:15138-15145; charge-on-objective late bonus ADM:15063-15068, 15396-15401; charge score × aggression ADM:15648-15653; fight priority × aggression ADM:17351-17357.
- Tempo constants: ADM:1954-1960. Formula: ADM:13990-14022 (behind 14007-14009, ahead 14010-14012, desperation 14014-14018). Application: objective urgency ADM:8665-8678; shooting targets on objectives ADM:13696-13713; charge threshold reduction ADM:15124-15130.
- Threat constants: ADM:1834-1841, 1925 (`THREAT_SAFE_MARGIN_INCHES` at 1838 is defined but unused). Threat data build + gate: ADM:6773-6775, 23893-23930. Danger weight: ADM:23932-23990. Position evaluation: ADM:23992-24078 (character ×1.5 at 24006-24007/24064; fragile ×1.3 at 24070-24071). Stay-put check: ADM:7192-7215. Safer-position search: ADM:24090-24180 (invoked ~11253-11255). Engagement range 2" (11e): `/home/user/warhammer-40k-godot/40k/scripts/rules/GameConstants.gd:31-32`.
- Difficulty tiers: ADC:12-17 (enum), 23-124 (gates and numbers), 141-152 (descriptions). Easy random path: ADM:3046-3048, 3272+. Noise helper: ADM:2071-2077; applied ADM:6985-6986, 15086, 15415, 17236. Charge modifier helper: ADM:2079-2081, applied 15133. Multi-phase gate: ADM:3110-3112. Threat gate: ADM:6774. Counter-deployment: ADM:4848. Stratagem gates: ADM:5925, 13119, 21936; AIP:1045, 1158, 1192, 1388, 1501. Difficulty plumbing: AIP:256-294, 597-599, 666-677; ADM:2390, 2966.
- Unwired gates (defined ADC, zero call sites repo-wide): `use_focus_fire` (:37), `use_trade_analysis` (:45), `use_look_ahead` (:49), `use_weapon_efficiency` (:53), `use_survival_assessment` (:59), `use_screening` (:63), `get_movement_iterations` (:86). Screening runs ungated at ADM:9487-9610; trade efficiency ungated at ADM:13978-13988, 15520-15524, 17132.
