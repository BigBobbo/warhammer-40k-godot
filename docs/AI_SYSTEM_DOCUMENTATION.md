# AI System Documentation

This document provides a comprehensive breakdown of how the AI works in this Warhammer 40,000 10th Edition game, covering every phase, the decisions it makes, and the algorithms driving those decisions.

---

## Architecture Overview

The AI system is split into three core components:

| File | Role |
|------|------|
| `autoloads/AIPlayer.gd` | **Controller** — Autoload node that monitors game signals, drives the evaluation loop, and submits actions through `NetworkIntegration.route_action()`. Handles timing, reactive stratagems, movement execution, and error recovery. |
| `scripts/AIDecisionMaker.gd` | **Decision Engine** — Pure static logic. Takes a game snapshot + available actions in, returns a single action dictionary out. No scene tree access. All scoring, planning, and tactical evaluation happens here. |
| `scripts/AIAbilityAnalyzer.gd` | **Ability Analyzer** — Static utility that reads unit abilities, leader bonuses, and special rules to compute offensive/defensive multipliers used by the decision engine. |
| `scripts/AIDifficultyConfig.gd` | **Difficulty Configuration** — Defines four difficulty levels (Easy/Normal/Hard/Competitive) and gates which AI features are active at each level. |

### Control Flow

```
Game Signal (phase_changed / phase_action_taken / result_applied)
  -> AIPlayer._request_evaluation()
     -> _process() tick (with configurable delay)
        -> _evaluate_and_act()
           -> PhaseManager.get_available_actions()
           -> AIDecisionMaker.decide(phase, snapshot, available_actions, player, difficulty)
              -> Returns action dictionary
           -> NetworkIntegration.route_action(action)
           -> Handle result (success, failure, multi-step follow-up)
           -> _request_evaluation()  [loop continues]
```

The AI evaluates one action at a time in a frame-paced loop. After each action completes, the game signals trigger a new evaluation. A configurable delay between actions (`AI_ACTION_DELAY` / speed presets) gives the renderer time to draw and makes the AI visible to the player.

---

## Difficulty System

Four difficulty levels control which AI features are enabled:

| Feature | Easy | Normal | Hard | Competitive |
|---------|------|--------|------|-------------|
| Random valid actions | Yes | No | No | No |
| Score noise | 100.0 | 1.5 | 0.5 | 0.0 |
| Focus fire coordination | No | Yes | Yes | Yes |
| Threat range awareness | No | Yes | Yes | Yes |
| Weapon-target efficiency | No | Yes | Yes | Yes |
| Multi-phase planning | No | No | Yes | Yes |
| Stratagems (reactive/proactive) | No | No | Yes | Yes |
| Survival assessment | No | No | Yes | Yes |
| Screening/deep strike denial | No | No | Yes | Yes |
| Counter-deployment | No | Yes | Yes | Yes |
| Trade/tempo analysis | No | No | No | Yes |
| Look-ahead planning | No | No | No | Yes |
| Movement iterations | 1 | 3 | 5 | 8 |
| Charge threshold modifier | 2.0 (rarely) | 1.0 | 0.85 | 0.7 (aggressive) |

**Easy** mode picks random valid actions with high score noise (essentially randomizing tactical choices). Mechanical steps like saves and confirmations are still deterministic.

**Normal** mode uses full scoring but with small noise (1.5) for natural variation.

**Hard** adds stratagems, multi-phase planning, survival assessment, and screening.

**Competitive** removes all noise and adds trade/tempo analysis for optimal play.

---

## Round Strategy System (Late-Game Pivot)

The AI adjusts its priorities based on which battle round it is, reflecting how Warhammer 40k games evolve:

| Round | Strategy Label | Aggression | Objective Priority | Survival | Charge Threshold |
|-------|---------------|------------|-------------------|----------|-----------------|
| 1-2 | AGGRESSIVE | 1.3x | 0.95x | 0.7x | 0.5x (lower = more willing) |
| 3 | BALANCED | 1.0x | 1.0x | 1.0x | 1.0x |
| 4-5 | OBJECTIVE/SURVIVAL | 0.7x | 1.6x | 1.4x | 1.3x (higher = less willing) |

- **Rounds 1-2**: The AI plays aggressively — seeking kills, advancing forward, and accepting risk. Objectives still matter (0.95x, nearly full weight) because Round 2 is the first scoring round.
- **Round 3**: Balanced transition period.
- **Rounds 4-5**: The AI pivots to objective control and survival. It values holding objectives 60% more, avoids risky engagements, and only charges if the target is on an objective.

---

## Phase-by-Phase Decision Breakdown

### 1. Formations Phase (`_decide_formations`)

**Purpose**: Attach leaders to bodyguard units, embark units in transports, and declare reserves.

#### Leader Attachment (`_evaluate_best_leader_attachment`)

The AI scores every possible leader-bodyguard pairing by simulating the attachment and computing:

1. **Offensive ranged multiplier** — How much the leader's "while leading" abilities (e.g., +1 to hit, reroll wounds) improve ranged damage output.
2. **Offensive melee multiplier** — Same for melee.
3. **Defensive multiplier** — FNP, cover, stealth granted by the leader.
4. **Tactical bonuses** — Fall Back and Charge (+0.15), Fall Back and Shoot (+0.10), Advance and Charge (+0.15), Advance and Shoot (+0.10).
5. **Model count scaling** — More models = more benefit from per-model buffs (+5% per extra model).
6. **Points value scaling** — Buffing expensive units is more impactful.

Formula: `score = (avg_offensive + defensive + tactical) * model_scale * points_scale`

The highest-scoring pairing is attached first, then the process repeats.

#### Transport Embarkation (`_evaluate_transport_embarkation`)

After leaders are attached, the AI evaluates which infantry units should embark in available transports. It avoids embarking bodyguard units that already have leaders attached (stored in `_bodyguards_with_leaders`).

#### Reserves Declaration (`_evaluate_reserves_declarations`)

The AI decides which units to place in Strategic Reserves or Deep Strike based on army composition and unit capabilities.

---

### 2. Deployment Phase (`_decide_deployment`)

**Purpose**: Place units on the board within the deployment zone.

The deployment algorithm works in layers:

1. **Role classification** (`_classify_deployment_role`): Each unit is classified as:
   - `fragile_shooter` — Low T, poor save, ranged weapons → seeks cover
   - `durable_shooter` — Tough ranged unit → positions for firing lanes
   - `melee` — Close combat unit → deploys forward
   - `character` — Hides behind LoS blockers

2. **Column-based spreading**: Units are distributed across 3-5 columns within the deployment zone to avoid clumping. Each subsequent unit goes to the next column, wrapping to a new depth row.

3. **Objective proximity blending**: Column position is blended 70/30 with the nearest-to-zone objective position, pulling units toward objectives.

4. **Counter-deployment** (Normal+): The AI analyzes where the opponent has already deployed and adjusts:
   - Melee units shift toward fragile enemy targets
   - Fragile shooters shift away from enemy melee threats
   - Durable shooters position for firing lanes against high-value concentrations

5. **Terrain-aware positioning** (`_find_terrain_aware_position`): Adjusts final position based on terrain:
   - Fragile shooters and characters seek cover/LoS-blocking terrain
   - Durable shooters avoid terrain that blocks their own firing lanes
   - Melee units avoid terrain that would slow charges

6. **Collision resolution**: Positions are adjusted to avoid overlapping with already-deployed models and terrain walls.

---

### 3. Scout Phase (`_decide_scout`)

Units with the Scout ability can make a pre-game move. The AI moves scout units toward the nearest uncontrolled objective or, for melee units, toward the nearest enemy.

---

### 4. Command Phase (`_decide_command`)

**Purpose**: Handle start-of-turn mechanics.

Decisions made (in priority order):

1. **Battle-shock tests** — Automatic, always taken when available.
2. **WAAAGH! activation** (Orks) — Smart timing based on unit proximity:
   - Round 1: Activate if any unit can reach enemies (alpha strike)
   - Round 2+: Always activate (use-it-or-lose-it, maximizes turns of benefit)
3. **Oath of Moment** (Space Marines) — Selects the highest-value enemy target using macro-level target priority (points cost, damage output, objective presence).
4. **Combat Doctrines** (Space Marines) — Assault early (advance+charge), Tactical mid-game, Devastator late.
5. **Martial Mastery** (Custodes) — Defaults to crit-on-5 for more damage, switches to improve AP vs high-save targets.
6. **Secondary mission awareness** (`_build_secondary_awareness`) — Analyzes active secondary missions (Behind Enemy Lines, Engage on All Fronts, etc.) and builds positional bonuses that influence movement decisions this turn.
7. **New Orders evaluation** — Swaps unachievable secondary missions for new ones (costs 1 CP). Uses mission achievability scoring with round-dependent thresholds.

---

### 5. Movement Phase (`_decide_movement`)

The most complex phase. Uses a three-phase internal pipeline:

#### Phase 1: Global Objective Evaluation (`_evaluate_all_objectives`)

Every objective on the board is scored based on:
- **Control status**: Uncontrolled (10.0), contested (8.0), enemy-weak (7.0), home undefended (9.0), already held (-3.0)
- **Scoring urgency**: Higher in rounds where objectives score VP
- **Round strategy**: Multiplied by objective_priority modifier (0.95x early, 1.6x late)

#### Phase 2: Unit-to-Objective Assignment (`_assign_units_to_objectives`)

Each movable unit is assigned to the best objective (or a screening/blocking position) by computing:
- **Distance** to each objective
- **OC efficiency** — Units with high Objective Control value are preferred for contested objectives
- **Threat zones** (Normal+) — Penalty for assignments that move through enemy charge/shooting threat ranges
- **Secondary mission bonuses** — Positional bonuses from secondary awareness (e.g., +7.0 for Behind Enemy Lines zones)
- **Screening assignments** (Hard+) — Cheap units may be assigned to screen against deep strike denial (9" denial zones)
- **Corridor blocking** (Hard+) — Expendable units block enemy movement corridors toward objectives

#### Phase 3: Execute Best Assignment

Units are processed in priority order: engaged units first, then by assignment score.

**For engaged units** (`_decide_engaged_unit`):

The AI performs a **survival assessment** (`_assess_engaged_unit_survival`) that estimates incoming fight-phase damage. Then it decides:
- **Hold** if winning the OC war on an objective (especially rounds 4-5)
- **Fall back** if losing OC, survival is lethal (>75% wounds expected), or the unit has Fall Back and Charge/Shoot abilities
- **Stay** even if doomed, if it's the only unit holding an objective

**For normal movement**:

Each unit's movement is computed via `_compute_movement_toward_target`:

1. **Multi-phase plan integration** (Hard+): If the unit has charge intent, it's directed toward the charge target instead of the nearest objective.
2. **Melee aggression**: Melee-focused units (and units from aggressive factions like Orks) actively seek enemies. Distance limits prevent abandoning objectives:
   - Round 1: Up to 18" for aggressive factions, 14" for others
   - Round 2: 14" / 12"
   - Round 3+: 12" / 10"
   - Horde units (10+ models): Tighter limits, as their OC is more valuable on objectives
3. **Heavy weapon stationary hold**: Units with Heavy weapons that have targets in range prefer remaining stationary for the +1 to hit bonus.
4. **Rapid Fire / Melta half-range positioning**: If moving closer to half range yields significant extra damage, the AI blends movement toward the half-range position.
5. **Firing position preservation**: Movement destinations are scored for whether they maintain, gain, or lose weapon range on enemies.
6. **Advance decision**: The AI advances (adds D6" to movement) when:
   - The unit has Advance and Charge/Shoot abilities
   - The objective is beyond normal move range
   - A melee unit needs extra distance to reach charge range

**Threat range awareness** (Normal+):

Before moving, the AI calculates enemy threat zones:
- **Charge threat** = enemy M + 12" charge + 1" engagement range
- **Shooting threat** = max weapon range

Units receive penalties for moving into threat zones, with fragile/high-value units getting an extra 1.3x multiplier. Melee-focused units mostly ignore charge threat zones (0.05 penalty instead of 2.0).

---

### 6. Shooting Phase (`_decide_shooting`)

#### Focus Fire Plan (`_build_focus_fire_plan`)

At the start of the shooting phase, the AI builds a **coordinated shooting plan** using a two-level priority framework:

**Macro level** (`_calculate_target_value`): Each enemy is scored by strategic priority:
- **Points cost** — 0.008 per point (a 200pt unit = +1.6)
- **Ranged damage output** — Expected hits × wounds × unsaved against T4/Sv3+ baseline
- **Melee damage output** — Same calculation for melee weapons
- **Ability value** — Offensive multiplier from leader buffs
- **Defensive discount** — Harder-to-kill units are less efficient targets
- **Character/Leader bonus** — 1.5x for leaders actively buffing bodyguards
- **Vehicle/Monster bonus** — 1.2x
- **Below half health bonus** — 1.5x (finish off wounded units)
- **Objective presence** — 1.4x on objective, further boosted in late game
- **Points-per-wound efficiency** — Units with high pts/wound are efficient to remove

**Micro level** (iterative allocation): Weapons are assigned to targets by highest marginal expected value:
1. Build a damage matrix (every weapon vs every enemy)
2. Calculate kill thresholds (total remaining wounds per enemy)
3. Iteratively assign each weapon to the target where it provides the most value, considering:
   - **Kill bonus** (2.0x) for assignments that push total damage past the kill threshold
   - **Overkill decay** (0.35x) for damage beyond what kills the target
   - **Low health bonus** (1.5x) for targets below half health
   - **Weapon-target efficiency matching** — Anti-tank weapons vs vehicles (1.4x perfect match), anti-infantry vs hordes (1.4x), mismatched weapons penalized (0.35x-0.6x)
   - **Weapon keyword scoring** — Sustained Hits, Lethal Hits, Devastating Wounds, Torrent, Blast, Anti-X, Twin-linked, Melta, Rapid Fire all have probability-based bonus multipliers
   - **Charge target suppression** (Hard+) — Targets planned for charging get only 0.5x shooting priority (save them for melee)
   - **Line of Sight filtering** — Assignments are dropped if the shooter can't see the target

**Grenade Stratagem** (Hard+): Before regular shooting, the AI evaluates whether to spend 1 CP on the Grenade stratagem for units near enemies.

**Secondary Actions**: Low-firepower units in scoring positions perform secondary mission actions (Establish Locus, Cleanse, Deploy Teleport Homer) instead of shooting.

---

### 7. Charge Phase (`_decide_charge`)

#### Charge Evaluation (`_evaluate_best_charge`)

Each possible charger-target pair is scored:

1. **Charge probability** (`_charge_success_probability`): Based on 2D6 probability to meet or exceed the charge distance minus 1" engagement range. Terrain penalties are added for charging through tall terrain. Charges with <3% probability are skipped.

2. **Target scoring** (`_score_charge_target`):
   - Expected melee damage (×2.0 weight)
   - Below half strength bonus (+3.0)
   - CHARACTER target bonus (+2.0)
   - Poor melee damage penalty (-3.0 if <1 damage)
   - Long-range shooter lock bonus (+2.0 for tying up 24"+ range shooters)
   - Phase plan lock shooter bonus (+3.0 for units identified as dangerous shooters)
   - Low toughness bonus (+1.0)
   - Leader melee ability multiplier
   - Target defensive ability divisor
   - Trade efficiency factor (prefer killing expensive targets with cheap units)
   - Charge coordination gang-up bonus (+5.0-7.0 when combined chargers can kill the target)
   - Charge coordination seed bonus (+3.0-9.0 for first charger when other friendly units are also in charge range)
   - Kill proximity bonus (+3.0 if >50% of wounds, +5.0 if likely kill)
   - Deadly Demise leverage (doomed vehicles get bonus for getting into explosion range)

3. **Final score** = target_score × charge_probability × melee_bonus × short_charge_bonus × objective_bonus × overwatch_risk_penalty × strategy_modifier × difficulty_noise

4. **Multi-target charges** (T7-50): The AI evaluates multi-target declarations when additional targets are along the charge path at marginal extra distance.

5. **Overwatch risk assessment** (`_estimate_overwatch_risk`): Estimates expected overwatch damage from the defending player's best shooter. Risk levels: `negligible`, `low`, `moderate`, `high`. Score penalty ranges from 1.0 (no risk) down to 0.4 (high risk).

#### Reactive Decisions in Charge Phase

- **Fire Overwatch**: AI evaluates whether to fire overwatch against charging enemies based on expected damage vs 1 CP cost.
- **Heroic Intervention**: AI evaluates counter-charging based on melee damage potential.
- **Tank Shock**: AI uses Tank Shock after successful vehicle charges.
- **Command Re-roll**: AI rerolls failed charge rolls when the charge is important (high target value, short distance needed).

---

### 8. Fight Phase (`_decide_fight`)

#### Fight Order Optimization (`_build_fight_order_plan`)

At the start of the fight phase, the AI builds a priority-sorted activation order:
- Units that can likely kill their target activate first (secure the kill before the enemy fights back)
- Units on objectives that need to survive activate later (in case counter-offensive is used)

#### Attack Assignment (`_assign_fight_attacks`)

For each fighting unit:

1. **Weapon selection** (T7-28): Every melee weapon profile is evaluated against every engaged enemy:
   - Primary weapons (normal melee weapons)
   - Extra Attacks weapons (auto-injected additional attack weapons)
   - Default close combat weapon (S=user, AP0, D1, A1, WS4+)
   - WAAAGH! buffs are factored in (+1S, +1A when active)

2. **Target scoring** (`_score_fight_target`):
   - Expected melee damage (×2.0)
   - Below half strength bonus
   - CHARACTER/VEHICLE/MONSTER bonuses
   - Kill probability bonus (+5.0 for likely kills)
   - Objective presence bonus
   - Fight coordination bonus (targets that accumulated damage from prior fighters are prioritized to finish off)

3. **Pile-in Movement** (`_compute_pile_in_action`): Models move up to 3" toward the nearest enemy model to maximize engagement.

4. **Consolidation** (`_compute_consolidate_action`): After fighting, models move 3" toward:
   - The nearest objective (priority)
   - The nearest enemy (secondary)
   - Or away from threats if the unit is badly damaged

---

### 9. Scoring Phase (`_decide_scoring`)

**Purpose**: Evaluate active secondary missions and decide whether to discard unachievable ones for +1 CP.

Each active secondary mission is scored for **achievability** (0.0 to 1.0):

| Score | Meaning |
|-------|---------|
| 0.0 | Completely impossible |
| 0.0-0.2 | Extremely unlikely — discard |
| 0.2-0.5 | Difficult but possible |
| 0.5+ | Reasonably achievable — keep |

**Mission-specific assessors** evaluate:
- **Positional missions** (Behind Enemy Lines, Engage on All Fronts, Area Denial): Count friendly units in required board zones
- **Objective missions** (Storm Hostile, Defend Stronghold): Check objective control status
- **Kill missions** (Assassination, Bring it Down): Check if valid targets exist
- **While-active missions** (No Prisoners): Check if any enemies have been destroyed; penalize if no kills by round 3
- **Action missions** (Establish Locus, Cleanse): Check if units are available to perform actions

Late-game (round 4+ with empty deck): Only truly impossible missions (score <0.1) are discarded.

---

## Cross-Phase Coordination Systems

### Multi-Phase Planning (Hard+)

Built once at the start of the movement phase, the multi-phase plan coordinates across movement → shooting → charge:

1. **Charge intent**: Identifies melee units that can plausibly charge this turn (M + 12" reach). Scores each potential charge target.
2. **Lock targets**: Identifies dangerous enemy shooters (ranged output >= 5.0 expected damage) that should be locked in combat.
3. **Shooting lanes**: Maps which ranged units can hit which enemies from their current position.

**How it's consumed**:
- **Movement**: Units with charge intent are directed toward their charge targets instead of objectives. Ranged units maintain shooting lanes.
- **Shooting**: Targets planned for charging receive only 0.5x shooting priority (soften but don't waste firepower).
- **Charge**: Lock targets get +3.0 priority bonus, with extra bonus proportional to ranged output.

### Focus Fire Coordination (Normal+)

The focus fire system ensures multiple shooters concentrate on the same target to secure kills rather than spreading damage across many targets:

- **Overkill tolerance** of 1.15 (15%) — allows slight overkill to ensure kills
- **Kill bonus multiplier** of 2.0 — strongly rewards assignments that cross the kill threshold
- Once a target is assigned enough damage to kill it, subsequent weapons are redirected to the next-highest-value target

### Charge Coordination

Tracks which enemies have been declared as charge targets earlier in the phase. Subsequent chargers get gang-up bonuses:
- **Kill gang-up** (+5.0-7.0): Combined damage from all chargers exceeds the target's HP
- **Pile-on bonus** (+2.0-3.0 per existing charger): Even without a certain kill, concentrating force is valuable
- **Seed bonus** (+3.0-9.0): First charger gets a bonus if other friendly units are also in charge range of the same target

### Fight Coordination

Tracks cumulative melee damage dealt to each enemy during the fight phase. Subsequent fighters prioritize targets that are close to dying from accumulated damage.

---

## Faction-Specific Behavior

The AI adjusts its play style based on the army faction:

| Faction | Aggression Modifier | Effect |
|---------|-------------------|--------|
| Default | 1.0 | Standard behavior |
| Adeptus Custodes | 1.5 | More willing to charge, melee-oriented movement |
| Orks | 1.8 | Very aggressive, advance frequently, charge readily, horde gang-up bonuses |
| World Eaters | 2.0 | Maximum aggression, always seeks melee |
| Khorne Daemons | 1.8 | Melee-focused, aggressive positioning |

For aggressive factions (>= 1.5):
- Melee-capable units actively seek enemies (not just melee-focused units)
- Charge thresholds are lowered
- Horde charge coordination bonuses are amplified
- Units are more willing to advance
- Melee aggression distance limits are extended

---

## Reactive Stratagem System

The AI responds to opponent actions via signal-based reactive stratagem handling:

| Stratagem | When | Decision Logic |
|-----------|------|---------------|
| **Fire Overwatch** | Enemy moves/charges near friendly unit | Evaluate expected damage vs 1 CP cost. Use if expected damage justifies the CP. |
| **Go to Ground** | Friendly unit targeted by shooting | Evaluate threat level — use for high-value units under heavy fire. |
| **Smokescreen** | Friendly unit targeted by shooting | Use for vehicles/monsters under concentrated fire. |
| **Counter-Offensive** | After enemy unit fights in fight phase | Evaluate if the AI unit can kill or severely damage the attacker before it fights again. |
| **Heroic Intervention** | Enemy charges near friendly CHARACTER | Counter-charge if melee damage potential is good. |
| **Tank Shock** | AI vehicle completes a charge | Always use (free mortal wound chance). |
| **Rapid Ingress** | End of opponent's movement phase | Evaluate bringing reserves onto the board at a favorable position. |
| **Command Re-roll** | After any dice roll | Evaluate based on roll type: reroll failed charges if important, failed battle-shock tests on key units, low advance rolls when distance matters. |
| **Distraction Grot** | Ork unit targeted | Always activate (free 5+ invulnerable save). |
| **Bomb Squigs** | Ork unit completes a normal move | Always activate (free D3 mortal wounds). |

---

## Ability Awareness System (`AIAbilityAnalyzer`)

The analyzer provides the decision engine with comprehensive unit ability profiles:

### Offensive Multipliers
- **+1 to hit**: +25% per bonus (improves from BS4+ to BS3+)
- **Reroll hits (ones)**: +10%
- **Reroll hits (failed)**: +30%
- **Reroll hits (all)**: +35%
- **+1 to wound**: +20% per bonus
- **Reroll wounds**: Same scale as hits

### Defensive Multipliers
- **Feel No Pain**: 1/(1-save_chance), e.g., FNP 5+ = 1.5x effective HP
- **Stealth**: +15% (imposes -1 to ranged hit rolls)
- **Cover from leader**: +15%

### Special Abilities Detected
- Fall Back and Charge/Shoot
- Advance and Charge/Shoot
- Lone Operative (targeting restriction at 12"+)
- Deadly Demise (mortal wounds on destruction)
- "Doomed" status (below 25% total wounds)

---

## Secondary Mission Awareness (Hard+)

At the start of each turn, the AI analyzes active secondary missions and builds positional bonuses:

| Mission Type | AI Adjustment |
|-------------|---------------|
| Behind Enemy Lines | +7.0 bonus for moving into enemy deployment zone |
| Engage on All Fronts | +6.0 bonus for spreading to uncovered table quarters |
| Area Denial | +3.5 bonus for center-of-board positioning |
| Assassination | +2.0 bonus for positioning near enemy CHARACTERs |
| Bring it Down | +2.0 bonus for positioning near enemy VEHICLEs |
| Objective missions | +3.5 bonus for objectives in relevant zones |
| Action missions | Low-firepower units perform actions instead of shooting |

---

## Trade and Tempo Analysis (Competitive only)

### Trade Efficiency
Points-per-wound ratio comparison between attacker and target. The AI prefers engagements where it's "trading up" (cheap units killing expensive targets per wound):
- **Favorable trade**: Up to 1.3x bonus
- **Unfavorable trade**: Down to 0.7x penalty

### Tempo (VP-Based Aggression)
The AI adjusts aggression based on the VP differential:
- **Losing**: Up to 1.5x aggression boost, lower charge thresholds
- **Winning**: 0.8x conservation factor, higher charge thresholds
- **Desperate** (round 4+, losing by 10+ VP): 1.8x aggression multiplier, charge threshold reduced by 0.4

---

## Error Recovery

The AI has extensive error handling for failed actions:

| Failed Action | Recovery |
|--------------|----------|
| DEPLOY_UNIT | Retry with adjusted positions up to 3 times, then mark unit as failed |
| Movement | Fall back to REMAIN_STATIONARY |
| SHOOT | Skip the unit |
| DECLARE_CHARGE / APPLY_CHARGE_MOVE | Skip the charge |
| PILE_IN | Retry with empty movements, then force CONSOLIDATE |
| CONSOLIDATE | Retry with empty movements, then re-evaluate |
| ASSIGN_ATTACKS | Force CONSOLIDATE |
| SELECT_FIGHTER | Send END_FIGHT |
| Reinforcement placement | Retry with new positions, then mark as failed |
| Transport embarkation | Skip the transport |
| Heroic Intervention | Decline instead |

A safety counter (`MAX_ACTIONS_PER_PHASE = 200`) prevents infinite loops. Failed unit IDs are tracked in skip lists that reset on phase change.
