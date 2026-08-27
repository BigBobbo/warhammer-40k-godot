# How the AI Sets Up: Formations & Deployment

*A plain-English dossier on the game's AI, extracted directly from the code. Every claim cites `file:line`. All weight values below were verified against the shipped `40k/data/ai_config.json`, which currently overrides **nothing** except `PLANS_ENABLED = 1` (`40k/data/ai_config.json:15-17`) — so every number in this document is the **effective** in-game value (the code default).*

This document covers the **plain, no-plan AI** — the formula the AI falls back to whenever no authored "AI Plan" covers the decision. When a plan matches, it takes over unit-by-unit and the formula only handles what the plan misses (`AIDecisionMaker.gd:4016-4021`, `4723-4751`).

---

## Overview

Before the first dice are rolled, the AI makes two big sets of choices. In the **Formations phase** it decides which hero characters join which squads (leader attachments), which squads ride inside transports, which units wait off-table in reserves, and who the Warlord is. In the **Deployment phase** it decides where each unit physically stands on the table.

For leader attachments, the AI "test-fits" every allowed hero-plus-squad pairing and estimates how much the hero's *while leading* abilities (re-rolls, +1 to hit, Feel No Pain, etc.) would boost that squad's shooting, fighting, and survivability — bigger and more expensive squads get more credit because buffs multiply across more models. For reserves, it prefers holding back melee units with Deep Strike (they arrive anywhere and threaten a charge), keeps long-range shooters on the table for Turn 1 firepower, and refuses to strip the board so bare that it cannot cover the objectives. Hard caps of 50% of the army's points and half the army's unit count are enforced, with an extra soft penalty once Strategic Reserves exceed 25% of points.

For deployment position, each unit is first classified into a role (melee, fragile shooter, durable shooter, character, anti-tank, general). A baseline spot is computed from a column grid across the deployment zone blended toward the nearest objective; that spot is then nudged in reaction to what the opponent has already deployed (counter-deployment), and finally the AI shops for nearby terrain — characters hide behind line-of-sight blockers, fragile shooters seek cover, melee units want forward LoS blockers to advance behind. When reserves arrive mid-game, the AI grades every legal landing spot mainly by objective proximity (base value 10 for spots within 6" of a marker) and a "sweet spot" distance from enemies.

Deployment and Formations behave **the same at every difficulty level** — even "Easy" (which is otherwise random) reuses the full setup logic — with one exception: Easy skips counter-deployment.

---

## Decision flow

### A. Formations phase — order of operations (`AIDecisionMaker.gd:3984-4060`)

The AI is called repeatedly; each call returns exactly one declaration, in this strict priority order:

1. **Plan check** — if an authored AI Plan matches this army, it dictates attachments/embarkations/reserves and everything below is skipped for what the plan covers (`4016-4021`).
2. **Leader attachments** — while any hero-to-squad attachment is still possible, score *every* available pairing and declare the single best one (`4024-4027`, scorer at `4110-4211`). The comment at `3985-3988` states the intent: attach **all** leaders eventually (the Bodyguard rule always protects them), but do the best-synergy pairings first so the best hero gets the best squad.
3. **Transport embarkation** — pick the transport load-out with the best total score, greedily filling capacity with the highest-scoring cargo (`4031-4034`, `4217-4358`). Units that already have a leader attached, or that have the Bodyguard ability, are never embarked (`4241-4258`).
4. **Reserves declarations** — one unit per call, best-scoring first, until nothing scores ≥ 2.0 or a cap is hit (`4042-4045`, `4429-4576`).
5. **Warlord designation** — required before confirming. Picks the character with the most wounds, +10 if already attached to a bodyguard squad (`4048-4051`, `4062-4108`).
6. **Confirm formations** — when nothing above fires (`4054-4059`).

#### A1. Leader-attachment synergy scoring (`4148-4211`)

For each candidate pairing the AI *simulates* the attachment (`4164-4166`) and asks the ability analyzer three questions about the combined unit:

- **Ranged offence multiplier** — starts at 1.0; ×1.25 per +1-to-hit; ×1.10 / ×1.30 / ×1.35 for re-roll-1s / re-roll-failed / re-roll-all hits; ×1.20 per +1-to-wound; ×1.08 / ×1.25 / ×1.30 for wound re-rolls (`AIAbilityAnalyzer.gd:437-460`).
- **Melee offence multiplier** — same scheme for melee buffs (`AIAbilityAnalyzer.gd:472-495`).
- **Defence multiplier** — Feel No Pain X+ becomes an effective-hit-points multiplier `1/(1-(7-X)/6)` (so FNP 5+ ≈ ×1.5); Stealth ×1.15; leader-granted cover ×1.15 (`AIAbilityAnalyzer.gd:513-532`).

Then:

```
synergy    = (ranged_mult + melee_mult + defence_mult) / 3 + tactical_bonus     (4193)
model_scale  = 1 + (alive_models − 1) × 0.05        # +5% per extra model      (4197)
points_scale = 1 + (squad_points − 50) / 400                                    (4201)
score = synergy × model_scale × points_scale                                    (4203)
```

Tactical bonuses (`4176-4183`): fall-back-and-charge +0.15, fall-back-and-shoot +0.10, advance-and-charge +0.15, advance-and-shoot +0.10.

#### A2. Reserves declarations and the 50% caps (`4429-4576`)

- **Hard caps**: reserves may hold at most **50% of total army points** (`max_reserves_points = int(total_army_points * 0.50)`, `4456`) and at most **half the army's unit count** (integer division, `4457`). A candidate that would bust the points cap is skipped outright (`4512-4513`); once the unit cap is reached the AI stops declaring (`4472-4474`).
  - *Note:* the function's own docstring cites the tabletop rule "Strategic Reserves limited to 25% of points" (`4436-4437`), but the code enforces only the 50% total caps — the 25% line is handled as a *soft penalty* instead (next bullet).
- **Board-presence guard (COORD-6)** (`4489-4529`): the AI refuses to strip its own board control. It wants at least `objectives_on_board + 2` units starting on the table (`4498`); each unit short of that costs the candidate **−1.5** (`4520`). For Strategic Reserves only, every point committed beyond a "comfort line" of **25% of army points** costs **−0.01 per point** (`4499`, `4521-4524`).
- **Deep Strike preferred**: when a unit could use either reserve type, the deep-strike option is always kept (`4476-4486`).
- **Declaration threshold**: the best candidate must score **≥ 2.0** or everything deploys on the table (`4556-4564`).
- Per-unit desirability comes from `_score_unit_for_reserves` (`4579-4703`) — see the scoring tables. Hard exclusions: leader-capable characters (should attach instead), Fortifications, and already-embarked units all score 0 (`4598-4614`).

### B. Deployment phase — placing each unit (`AIDecisionMaker.gd:4709-4954`)

Deployment alternates with the opponent (the phase engine handles turn switching, `DeploymentPhase.gd:1396-1404`). Each AI turn:

1. **Which unit next?** The AI takes the *first* `DEPLOY_UNIT` action offered (`4735`), and the phase lists undeployed units in army-list order (`DeploymentPhase.gd:1377-1388`, `1584-1599`) — so with no plan, **deployment order is simply army-list order**. Embarked and attached units deploy with their carrier/bodyguard and never appear in the list (`DeploymentPhase.gd:1589-1594`).
2. **Role classification** (`4754`, classifier `4958-5018`): `character` (any CHARACTER keyword) → `melee` (no ranged weapons, or melee-dominated output) → `anti_tank` (any ranged weapon with Strength ≥ 9 or AP ≥ 3, `4985-4997`) → `fragile_shooter` (T≤4 with Sv 4+/worse and W≤2, or T≤3 W≤2, `5004-5011`) → `durable_shooter` → `general`.
3. **Baseline spot — column grid blended toward objectives** (`4792-4845`):
   - The zone is split into `min(5, max(3, army_size))` columns (`4821`); the Nth deployed unit goes in column `N mod columns`, and starts a new row `min(200px, zone_height/3)` deeper every full pass (`4823-4830`).
   - Depth: 80 px (2") in from the zone's front edge, plus the row offset (`4833-4840`).
   - The final baseline X is **70% column position + 30% nearest-objective position** (the objective point clamped into the zone, `4799-4809`, `4843-4845`).
4. **Counter-deployment nudges** (Normal difficulty and up, `4847-4851`; logic `5026-5165`). Reacting to enemy units *already on the table*:
   - **Melee** units shift 35% of the X-gap toward the juiciest enemy cluster (fragile shooters first, else high-value ≥100 pt units, else everyone) and push 40 px (1") toward the front edge (`5066-5090`).
   - **Fragile shooters** shift 30% of the X-gap *away* from enemy melee concentrations and tuck 30 px toward the back edge; with no enemy melee on the table they instead drift 20% toward the enemy mass (`5092-5116`).
   - **Durable shooters** shift 25% toward the enemy centre of mass, plus another 15% toward high-value targets (`5118-5134`).
   - **Characters** shift 25% away from enemy shooter concentrations and 25 px toward the back (`5136-5157`).
   - **General** units drift 15% toward the enemy centre (`5159-5163`).
5. **Terrain shopping** (`4853-4858`; scorer `5199-5256`; search `5261-5393`). For every terrain piece in or within 3" of the zone, the AI generates candidate spots behind it (away from the enemy), inside it for area terrain, and on its flanks (`5313-5335`). Each candidate scores `terrain_role_score + objective_bonus + depth_bonus − drift_penalty`:
   - objective bonus: up to +1.0 per objective within 10" (linear falloff, `5355-5360`);
   - depth bonus: melee up to +1.5 for being near the front, characters/fragile shooters up to +1.0 for being near the back (`5362-5371`);
   - drift penalty: −1.0 per 200 px (5") away from the baseline, and any candidate more than 40% of the zone's width from baseline is rejected outright (`5347-5353`).
   - The winning terrain spot is only used if it scores **≥ 1.0**; otherwise the counter-deployed baseline stands (`5385-5388`).
6. **Physical placement**: models are laid out in a grid up to 5 wide, spaced one base-diameter + 10 px apart (`20321-20347`), collisions with already-placed models are resolved (`4918-4920`), and wall overlaps trigger a search for a wall-free centre (`4922-4942`). A faction special case: Lions "Against All Odds" armies spread 6"+ apart to keep their buff live (`4860-4862`).
7. For the record/telemetry, the chosen spot is compared against a ring of five alternates 6" away, scored on objective proximity (up to 24) and a crowding penalty for stacking within 6" of a deployed friend (`4864-4900`).

### C. Reinforcement arrival — reserves coming back on (`AIDecisionMaker.gd:7429-7618`)

From Round 2, when reserves may arrive:

1. **Who lands first**: every reserve unit gets an urgency score (`7620-7660`, table below); highest first (`7470-7471`).
2. **Where to land — candidate generation** (`7662-7794`):
   - *Strategic Reserves*: sample points 3" in from all four board edges, every 4" (`7695-7757`).
   - *Deep Strike*: rings around every objective at 10", 12" and 15" out, every 30°, plus a full-board 4" grid (`7759-7794`). A unit sitting in Strategic Reserves that also has Deep Strike tries Deep Strike placement first (`7480-7496`).
   - Candidates must be > the ingress stand-off from all enemy models (read live from `GameConstants.reinforcement_min_enemy_distance_inches()` — 8" under 11e rules, `7968-7981`), outside 12" of enemy Omni-scrambler models (`8007-8015`), within 6" of a board edge for Strategic Reserves (`7983-7991`), and — Round 2 only — outside the opponent's deployment zone (`7993-8005`).
3. **Spot scoring** (`7826-7884`): objective proximity dominates (see table); distance-to-enemy adds a bonus in the 9-15" band; "Against All Odds" armies add ±4/−3 for landing clear of / inside friendly bubbles.
4. The best-scoring centroid gets a model formation generated around it, re-validated for the distance rule, coherency, and true base overlap; failures fall through to the next candidate, next placement type, then the next unit (`7509-7595`).

---

## Scoring tables

All values verified as the effective in-game defaults (nothing in `ai_config.json` overrides them). Every one is tunable by name via `ai_config.json` / player profiles (`AIDecisionMaker.gd:1235-1256`).

### Leader attachment (fixed coefficients, not tunable)

| Term | Value | Plain-English meaning | Source |
|---|---|---|---|
| +1 to hit (per point) | ×1.25 | Hero makes the squad hit noticeably more often | `AIAbilityAnalyzer.gd:437-438` |
| Re-roll 1s / failed / all hits | ×1.10 / ×1.30 / ×1.35 | Better hit re-rolls are worth more | `AIAbilityAnalyzer.gd:441-447` |
| +1 to wound (per point) | ×1.20 | Squad wounds more reliably | `AIAbilityAnalyzer.gd:450-451` |
| Re-roll 1s / failed / all wounds | ×1.08 / ×1.25 / ×1.30 | Wound re-roll ladder | `AIAbilityAnalyzer.gd:454-460` |
| Feel No Pain X+ | ×1/(1−(7−X)/6) | e.g. FNP 5+ ≈ 1.5× effective toughness | `AIAbilityAnalyzer.gd:520-524` |
| Stealth / leader-granted cover | ×1.15 each | Harder to shoot | `AIAbilityAnalyzer.gd:527-532` |
| Fall back & charge / & shoot | +0.15 / +0.10 | Tactical freedom bonuses | `AIDecisionMaker.gd:4176-4179` |
| Advance & charge / & shoot | +0.15 / +0.10 | | `AIDecisionMaker.gd:4180-4183` |
| Per extra model in squad | ×(1 + 0.05·(N−1)) | Buffs are worth more on big squads | `AIDecisionMaker.gd:4197` |
| Squad points scale | ×(1 + (pts−50)/400) | Buffing expensive squads matters more | `AIDecisionMaker.gd:4201` |
| Warlord: attached to a squad | +10.0 (`WARLORD_ATTACHED_BONUS`) | Warlord pick strongly prefers a protected hero; base score = wounds | `AIDecisionMaker.gd:1355, 4083-4091` |

### Transport embarkation — cargo desirability (`AIDecisionMaker.gd:4360-4423`, consts `1380-1393`)

| Term | Default | Plain-English meaning |
|---|---|---|
| `EMBARK_LOW_TOUGHNESS` | 0.3 | Toughness 4 or less — fragile, wants a metal box |
| `EMBARK_POOR_SAVE` | 0.2 | Save 5+ or worse |
| `EMBARK_SINGLE_WOUND` | 0.2 | 1-wound models are very fragile |
| `EMBARK_SMALL_UNIT` / `EMBARK_MEDIUM_UNIT` | 0.3 / 0.15 | ≤5 models / ≤10 models (capacity-efficient) |
| `EMBARK_SHORT_RANGE` / `EMBARK_MID_RANGE` | 0.3 / 0.15 | Guns reach ≤12" / ≤24" — needs delivery |
| `EMBARK_MELEE` | 0.25 | Has melee weapons — transport delivers the charge |
| `EMBARK_VERY_SLOW` / `EMBARK_SLOW` | 0.2 / 0.1 | Move ≤5" / ≤6" |
| `EMBARK_EXPENSIVE` / `EMBARK_COSTLY` | 0.15 / 0.1 | ≥150 pts / ≥100 pts — worth protecting |
| `EMBARK_INFANTRY` | 0.1 | INFANTRY keyword |
| `EMBARK_OC_PER_POINT` | 0.1 × OC | High objective-control units benefit from fast delivery (only if OC ≥ 2) |

### Reserves declaration — unit desirability (`AIDecisionMaker.gd:4579-4703`, consts `1394-1413`)

| Term | Default | Plain-English meaning |
|---|---|---|
| `RESERVES_DS_PURE_MELEE` | 8.0 | Deep Strike, melee-only unit — the ideal reserve |
| `RESERVES_DS_MIXED_MELEE` | 6.0 | Deep Strike, mixed melee/ranged |
| `RESERVES_DS_SHORT_RANGE` | 5.0 | Deep Strike shooter, guns ≤18" (flamers/meltas) |
| `RESERVES_DS_MID_RANGE` | 3.5 | Deep Strike shooter, guns ≤24" |
| `RESERVES_DS_LONG_RANGE` | 1.5 | Deep Strike long-range shooter — marginal benefit |
| DS points bonus | +pts/100, capped at 3.0 | Expensive units are worth careful placement (`RESERVES_DS_POINTS_DIVISOR`/`_CAP`) |
| `RESERVES_SR_PURE_MELEE` | 4.0 | Strategic Reserves, melee-only — flank entry |
| `RESERVES_SR_MIXED_MELEE` | 2.5 | Strategic Reserves, mixed unit |
| `RESERVES_SR_SHORT_RANGE` | 2.0 | SR shooter with guns ≤18" |
| `RESERVES_SR_RANGED` | 0.5 | Any other SR ranged unit — wants Turn 1 shooting instead |
| `RESERVES_SR_MOVE_12` / `_10` / `_8` | 2.0 / 1.5 / 0.5 | Fast units exploit edge entry (Move ≥12"/≥10"/≥8") |
| SR melee points bonus | +pts/200, capped at 1.5 | (`RESERVES_SR_POINTS_DIVISOR`/`_CAP`) |
| `RESERVES_VEHICLE_RANGED_PENALTY` | ×0.4 | Vehicles/Monsters with guns want to be on the table |
| `RESERVES_VEHICLE_MELEE_PENALTY` | ×0.7 | Even melee Vehicles/Monsters are discounted |
| `RESERVES_LONG_RANGE_PENALTY` | ×0.3 | Ranged-only unit with ≥36" guns — stay and shoot |
| `RESERVES_CHEAP_SCREEN_PENALTY` | ×0.5 | ≤100 pts (`SCREEN_CHEAP_UNIT_POINTS`, `1923`) without Deep Strike — better used as a screen |
| Board-presence penalty | −1.5 per unit below (objectives+2) on board | COORD-6 guard (`4498, 4520`) |
| SR overcommit penalty | −0.01 per point past 25% of army points | Soft "comfort line" (`4499, 4521-4524`) |
| Declaration threshold | 2.0 | Best candidate below this → deploy everything (`4559`) |
| Hard caps | 50% points, ⌊units/2⌋ | `4456-4457` |

### Deployment terrain scores by role (`AIDecisionMaker.gd:5211-5250`, consts `1308-1318`)

"LoS blocker" = tall terrain, or medium ruins (`5206`). "Cover" = ruins/obstacle/barricade/woods/crater/forest (`5209`).

| Role | LoS blocker | Cover | Extra |
|---|---|---|---|
| Character | +5.0 (`DEPLOY_TERRAIN_CHAR_LOS_BLOCK`) | +2.0 (`DEPLOY_TERRAIN_CHAR_COVER`) | hides behind tall terrain |
| Fragile shooter | +3.5 | +3.0 | *note: the code feeds the `…FRAGILE_COVER` (3.5) param to the LoS-blocker case and `…FRAGILE_LOS_BLOCK` (3.0) to the cover case — the two names are swapped in use (`5222-5225`); the executed values are as listed here* |
| Durable shooter | +1.0 (`…DURABLE_LOS_BLOCK`) | +2.5 (`…DURABLE_COVER`) | cover matters more than hiding |
| Melee | +4.0 (`…MELEE_LOS_BLOCK`) | +1.5 (`…MELEE_COVER`) | plus up to +2.0 the closer the terrain is to the zone's front edge (`DEPLOY_TERRAIN_FORWARD_WEIGHT`, `5240-5244`) |
| General | +1.5 (`…SCREEN_LOS_BLOCK`) | +2.0 (`…SCREEN_COVER`) | |
| Any | 0 | 0 | impassable terrain is worthless (`5253-5254`) |
| Candidate modifiers | — | — | +≤1.0 per objective within 10" (`5355-5360`); depth bonus ≤1.5 melee-front / ≤1.0 fragile-back (`5362-5371`); −1 per 5" drift from baseline; >40%-zone-width drift rejected (`5347-5353`); winner needs ≥1.0 (`5386`) |

### Reinforcement arrival — landing-spot value (`AIDecisionMaker.gd:7826-7884`, consts `1333-1338`)

| Term | Default | Plain-English meaning |
|---|---|---|
| `REINFORCE_OBJ_NEAR_BASE` | 10.0 − distance(in) | Spot within 6" of an objective: 10 minus the distance (so 4"-out ≈ 6.0) |
| `REINFORCE_OBJ_FAR_BASE` | max(0, 8.0 − 0.3·distance) | Further out: diminishing value, zero beyond ~27" |
| `REINFORCE_CHARGE_RANGE` | +3.0 | 10-15" from the nearest enemy — can shoot, hard to be charged |
| `REINFORCE_NEAR_CHARGE_RANGE` | +2.0 | 9-10" from enemies — just outside charge range |
| `REINFORCE_AAO_CLEAR` / `REINFORCE_AAO_BROKEN` | +4.0 / −3.0 | Lions "Against All Odds" only: lands with the 6" solo-bubble intact / broken |

### Reinforcement arrival — which unit lands first (`AIDecisionMaker.gd:7620-7660`, consts `1339-1346`)

| Term | Default | Plain-English meaning |
|---|---|---|
| Points priority | pts / 50 (`RESERVE_DEPLOY_POINTS_DIVISOR`) | Expensive units come in sooner |
| `RESERVE_DEPLOY_DEEP_STRIKE` | +2.0 | Deep Strikers are more flexible — use them |
| `RESERVE_DEPLOY_MELEE` | +1.5 | Melee unit — arrive, then charge next turn |
| `RESERVE_DEPLOY_SHORT_RANGE` | +1.0 | Added for **any** ranged weapons (despite the name) — can shoot on arrival (`7641-7642`) |
| `RESERVE_DEPLOY_ROUND_5` / `_ROUND_4` | +5.0 / +2.0 | Round ≥4 / ≥3 urgency — undeployed reserves are destroyed at game end |
| `RESERVE_DEPLOY_CONTESTED_OBJ` | +1.5 per contested/enemy-held objective | The board needs help |
| `RESERVE_DEPLOY_OPEN_OBJ` | +0.5 per uncontested objective | Free real estate |

---

## Worked example

*Invented but realistic: the AI (Player 2, bottom zone) is deploying its 4th unit — 10 Fire Warrior-style infantry (T3, Sv 4+, W1, guns 30", 100 pts) in a 10-unit army on a 44"×60" board (40 px = 1", `AIDecisionMaker.gd:24,38-39`). No plan is active.*

**1. Role.** Ranged weapons, T3/W1 → `fragile_shooter` (`5004-5011`).

**2. Baseline (column grid).** Bottom zone bounds y = 1930…2390 px (`20316-20319`). 10 units → `min(5, max(3,10)) = 5` columns (`4821`); 3 units already down → column index 3, row 0 (`4823-4824`). Column centre x = 40 + 336×3.5 = **1216**. Front-edge depth: 1930 + 80 = **2010** (`4839-4840`). Nearest objective (clamped into the zone) sits at x = 880, so baseline x = 0.7×1216 + 0.3×880 = **1115** (`4844`). Baseline = **(1115, 2010)**.

**3. Counter-deployment (Normal+).** The opponent has a melee blob deployed at x ≈ 600. Fragile shooter shifts *away*: x += (1115−600)×0.3 ≈ +155 → x = **1270**, and tucks 30 px back → y = **2040** (`5101-5108`).

**4. Terrain shopping.** A medium ruin (blocks LoS + grants cover, `5206-5209`) sits at (1300, 2100), 200×160 px. Candidate "behind it" (away from the enemy, i.e. below): offset = max(200,160)/2 + 60 = 160 px → candidate **(1300, 2260)** (`5313-5332`). Score:
- terrain: LoS-block 3.5 + cover 3.0 = **+6.5** (`5222-5225`)
- objectives: nearest is ~28" away → **+0** (`5355-5360`)
- depth: back edge is y = 2390; 130 px from it over a 460 px-deep zone → 1.0×(1−130/460) ≈ **+0.72** (`5368-5371`)
- drift: 222 px from the counter-deployed baseline → −222/200 ≈ **−1.11** (`5348-5349`)
- **Total ≈ 6.11** — comfortably above the 1.0 bar (`5386`), so the unit deploys tucked behind the ruin at (1300, 2260) instead of in the open at (1270, 2040).

**5. Physical layout.** 10 models in a 5×2 grid, each base-diameter + 10 px apart, clamped to the zone, collision-resolved against everything already placed, and checked against walls (`20321-20347`, `4916-4942`).

---

## Difficulty gates

Difficulty barely touches setup — by design:

| Behaviour | Easy | Normal | Hard | Competitive | Source |
|---|---|---|---|---|---|
| Formations logic (attachments, embarkation, reserves, warlord) | full logic | full | full | full | Easy explicitly routes FORMATIONS to the normal decider (`AIDecisionMaker.gd:3320-3322`) |
| Deployment positioning | full logic | full | full | full | Easy routes DEPLOYMENT to the normal decider "random positions would be chaotic" (`3324-3326`) |
| **Counter-deployment** (react to enemy placements) | **off** | on | on | on | `use_counter_deployment: difficulty >= NORMAL` (`AIDifficultyConfig.gd:67-68`), checked at `AIDecisionMaker.gd:4848` |
| Everything else random | yes | no | no | no | `use_random_actions` (`AIDifficultyConfig.gd:23-24`), gate at `AIDecisionMaker.gd:3047-3048` |

So the only setup difference an Easy player sees is that the AI ignores where they deployed. Score noise (`AIDifficultyConfig.gd:72-83`) is **not** applied to any formations/deployment score. Screening and multi-phase planning gates (Hard+) affect later phases, not setup.

---

## Evidence

Key file:line references (all paths under `/home/user/warhammer-40k-godot/`):

- **Config layering & effective values**: `40k/data/ai_config.json:15-17` (only `PLANS_ENABLED:1` — no weight overrides, so code defaults are effective); `40k/scripts/AIDecisionMaker.gd:291-322` (load order res:// then user://), `1235-1256` (`get_param` priority: rule overrides > player profile > config > const default).
- **Formations dispatcher & order**: `AIDecisionMaker.gd:3984-4060`; plan hand-off `4016-4021`.
- **Leader attachment**: `4110-4146` (pick best pairing), `4148-4211` (scoring formula), `4144-4145` (bodyguard bookkeeping); multipliers `40k/scripts/AIAbilityAnalyzer.gd:420-534`.
- **Warlord**: `4062-4108`; `WARLORD_ATTACHED_BONUS` at `1355`.
- **Embarkation**: `4217-4358` (greedy fill), `4360-4423` (cargo scores), consts `1380-1393`.
- **Reserves declaration**: `4429-4576` (caps `4456-4457`, unit-cap stop `4472-4474`, DS preference `4476-4486`, presence guard `4489-4529`, threshold `4556-4564`); unit scoring `4579-4703`, consts `1394-1413`, `SCREEN_CHEAP_UNIT_POINTS` `1923`.
- **Deployment**: `4709-4954` (unit pick `4734-4740`, role log `4754-4768`, column/objective baseline `4792-4845`, counter-deploy gate `4847-4851`, terrain `4853-4858`, alternates record `4864-4908`, formation/collision/wall handling `4910-4942`); role classifier `4958-5018`; counter-deployment `5026-5165`; enemy analysis `5170-5194`; terrain role scores `5199-5256`, consts `1308-1318`; terrain search `5261-5393`; zone bounds `20283-20319`; model grid `20321-20347`.
- **Deployment order source**: `40k/phases/DeploymentPhase.gd:1377-1409` (action list), `1584-1599` (undeployed = army-list order; embarked/attached excluded).
- **Reinforcement arrival**: `AIDecisionMaker.gd:7429-7618` (arrival loop), `7620-7660` (urgency), `7662-7794` (candidate generation), `7796-7824` & `7958-8017` (validity: ingress stand-off from `GameConstants` `7968-7981`, SR 6"-edge `7983-7991`, Round-2 enemy-DZ ban `7993-8005`, Omni-scrambler 12" `8007-8015`), `7826-7884` (spot scoring incl. `REINFORCE_OBJ_NEAR_BASE` at `7857`), consts `1333-1346`.
- **Difficulty**: `40k/scripts/AIDifficultyConfig.gd:23-24, 67-68, 72-83`; Easy-mode routing `AIDecisionMaker.gd:3047-3048, 3320-3326`; per-player difficulty default Normal `40k/autoloads/AIPlayer.gd:294, 599`.

**Honesty flags** (things the code does that a reader might not expect):
1. The fragile-shooter terrain weights are *name-swapped* in use — `DEPLOY_TERRAIN_FRAGILE_COVER` (3.5) is applied to LoS blockers and `…FRAGILE_LOS_BLOCK` (3.0) to cover (`5222-5225`). Anyone tuning those two knobs should know they are crossed.
2. The rules' 25% Strategic Reserves points cap is a *soft penalty* (comfort line), not a hard cap — only the 50%-points / half-units caps are enforced (`4436-4437` vs `4456-4457`, `4499`).
3. `RESERVE_DEPLOY_SHORT_RANGE` (+1.0) fires for **any** ranged weapon, not just short-ranged ones, despite its name (`7641-7642`).
4. Reinforcement *candidate pre-filtering* uses a hardcoded 9"+buffer radius (`7670-7672`) while final validation reads the 11e 8" ingress distance from `GameConstants` (`7968-7981`) — candidates are slightly more conservative than the rules require.
5. This dossier is a static code read; behaviours were not re-driven live in-game for this document.
