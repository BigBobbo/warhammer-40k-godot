# AI Player Audit — Gaps, Missing Tactics & Improvement Opportunities

> **Generated:** 2026-02-19
> **Files audited:** `AIPlayer.gd`, `AIDecisionMaker.gd` (2,076 lines), `RulesEngine.gd`, all phase scripts, `STRATAGEMS_AND_ABILITIES_PLAN.md`, `MASTER_AUDIT.md`
> **Compared against:** Warhammer 40k 10th Edition Core Rules (wahapedia), competitive tactics guides (Goonhammer, Grimhammer Tactics), community AI/strategy discussions

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [What the AI Currently Does Well](#what-the-ai-currently-does-well)
3. [Critical Gaps — Rules Compliance](#critical-gaps--rules-compliance)
4. [Strategic & Tactical Gaps](#strategic--tactical-gaps)
5. [Phase-by-Phase AI Logic Gaps](#phase-by-phase-ai-logic-gaps)
6. [Missing Weapon Keywords Affecting AI](#missing-weapon-keywords-affecting-ai)
7. [Quality of Life Improvements](#quality-of-life-improvements)
8. [Visual Improvements](#visual-improvements)
9. [Prioritized TODO List](#prioritized-todo-list)

---

## Executive Summary

The AI player system (`AIPlayer.gd` + `AIDecisionMaker.gd`) provides a functional single-player experience covering all game phases. It uses heuristic decision trees with objective-control-aware movement, basic shooting target prioritization, and signal-driven non-blocking action submission. However, it has **major gaps** in charge/fight phases (charges are skipped entirely, pile-in/consolidation always hold position), **no stratagem usage**, **no ability awareness**, and **lacks competitive tactics** like screening, deep strike denial, threat assessment, or resource-efficient weapon allocation. The AI currently plays at a beginner level — it moves toward objectives and shoots at the nearest viable target but makes no attempt at multi-phase planning or positional strategy.

---

## What the AI Currently Does Well

| Area | Implementation | Quality |
|------|---------------|---------|
| **Deployment** | Column-based spread with objective proximity weighting, collision resolution via spiral search | Good |
| **Movement — Objective Control** | Global objective evaluation with OC-aware scoring, greedy unit-to-objective assignment, hold/move/advance decisions | Strong |
| **Movement — Engaged Units** | Smart fall-back decisions based on OC war at current objective | Good |
| **Movement — Advance Decisions** | Cross-phase consideration (checks if advancing loses shooting targets) | Good |
| **Movement — Terrain Awareness** | Path blocking detection, alternate angle pathfinding, cover-seeking behavior | Good |
| **Movement — Collision Avoidance** | Model overlap detection, perpendicular offset resolution, movement cap enforcement | Good |
| **Shooting — Target Selection** | Expected damage calculation using hit/wound/save probability chain | Basic |
| **Shooting — One Shot Tracking** | Correctly skips already-fired ONE SHOT weapons | Good |
| **Command Phase** | Battle-shock tests, command re-roll usage | Functional |
| **Signal Architecture** | Frame-paced evaluation, re-entrancy guards, safety action limits, failed action recovery | Strong |

---

## Critical Gaps — Rules Compliance

These are rules the AI **should** follow but currently does not, leading to incorrect or suboptimal play.

### AI-GAP-1: Charges Are Completely Skipped [CRITICAL]

**Current:** `_decide_charge()` always returns `SKIP_CHARGE` for every unit with the comment "not implemented."
**Impact:** The AI never charges, which means melee-focused armies (Orks, World Eaters, Custodes melee builds) are completely neutered. The AI also never gains the "charged this turn" bonus for Lance weapons, never triggers Fights First from charging, and never locks enemy units in engagement range.
**Rules reference:** Core Rules — Charge Phase: units within 12" of an enemy may declare a charge, roll 2D6", and must end within engagement range of at least one declared target.
**Fix:** Implement charge declaration logic with:
  - Charge distance feasibility check (unit centroid to nearest enemy model <= 12")
  - Expected value assessment (average charge roll = 7", success probability calculation)
  - Model positioning after successful charge (move models into engagement range)
  - Multi-target charge declarations when beneficial
  - Integration with overwatch risk assessment

### AI-GAP-2: Pile-In and Consolidation Always Hold Position [CRITICAL]

**Current:** `_decide_fight()` sends empty `movements: {}` for both PILE_IN and CONSOLIDATE actions. Models never move during the fight phase.
**Impact:** Models that aren't already in base-to-base contact after a charge will fight with reduced or zero eligible models. Consolidation should be used to move onto objectives, tag new enemy units, or consolidate into beneficial positions.
**Rules reference:** Core Rules — Fight Phase: Pile in = move up to 3" closer to nearest enemy. Consolidate = move up to 3" closer to nearest enemy.
**Fix:** Implement pile-in logic that moves each model 3" toward the nearest enemy model, and consolidation that prioritizes:
  - Moving onto objectives
  - Engaging new enemy units (tag for next fight phase)
  - Maintaining unit coherency

### AI-GAP-3: No Stratagem Usage [HIGH]

**Current:** The AI never uses any stratagems. No CP is ever spent.
**Impact:** The AI misses all 11 core stratagems available to every army, including critical defensive plays (Go to Ground, Smokescreen), offensive buffs (Grenade, Epic Challenge), and reactive plays (Fire Overwatch, Counter-Offensive, Heroic Intervention). This is a massive tactical disadvantage.
**Rules reference:** Core Rules — Stratagems: players may use one stratagem per phase (with restrictions).
**Fix (staged):**
  1. **Phase 1:** Implement core offensive stratagems — Grenade (in shooting), Epic Challenge (in fight)
  2. **Phase 2:** Implement core defensive stratagems — Go to Ground, Smokescreen (opponent's shooting), Fire Overwatch (opponent's movement/charge)
  3. **Phase 3:** Implement reactive stratagems — Counter-Offensive (fight), Heroic Intervention (opponent's charge), Rapid Ingress (opponent's movement)
  4. **Phase 4:** Implement Command Re-roll with intelligent trigger (re-roll failed charges, critical saves, close battle-shock tests)
  5. **Phase 5:** Implement faction-specific stratagems via data-driven effect system

### AI-GAP-4: No Unit Ability Awareness [HIGH]

**Current:** The AI does not read or act on any unit abilities. The `UnitAbilityManager` applies effects at runtime, but the AI decision-making ignores ability synergies.
**Impact:** The AI doesn't:
  - Prioritize keeping Leaders attached to their bodyguard units
  - Use units with "Fall Back and Charge" abilities to fall back and re-charge
  - Position aura-granting units to maximize buff coverage
  - Protect Lone Operative units by keeping them >12" from enemies
  - Leverage Deadly Demise by charging doomed vehicles into enemy clusters
**Fix:** Add ability-aware decision hooks:
  - Query `UnitAbilityManager` for active effects when scoring movement/shooting decisions
  - Factor in leader attachment bonuses when evaluating unit value
  - Check for "Fall Back and X" abilities before deciding to fall back

### AI-GAP-5: No Invulnerable Save Consideration in Target Scoring [MEDIUM]

**Current:** `_score_shooting_target()` only uses the basic save characteristic. Invulnerable saves are ignored.
**Impact:** The AI may waste high-AP weapons on targets with invulnerable saves (e.g., shooting AP-4 lascannons at a unit with a 4++ invuln, where the AP is mostly wasted).
**Fix:** Check for invulnerable save in target unit stats and use `min(modified_save, invuln)` when calculating save probability.

### AI-GAP-6: Fight Phase — Only One Melee Weapon Used [MEDIUM]

**Current:** `_assign_fight_attacks()` picks the first melee weapon found and assigns all attacks with it.
**Impact:** Units with multiple melee profiles (e.g., a power fist AND a chainsword) can't use Extra Attacks weapons alongside their primary weapon. The AI also doesn't choose the optimal weapon for each target.
**Fix:** Evaluate all melee weapon options per target, account for Extra Attacks weapons, and pick the combination that maximizes expected damage.

### AI-GAP-7: Formations Phase — No Leader Attachment or Transport Embarkation [LOW]

**Current:** `_decide_formations()` immediately confirms formations without evaluating leader attachments, transport embarkation, or reserves declarations.
**Impact:** Leaders are never attached to bodyguard units (missing their "while leading" abilities), and transports are never used for deployment efficiency.
**Fix:** Evaluate leader-bodyguard pairings based on ability synergies, and assign small/fast units to transports when beneficial.

---

## Strategic & Tactical Gaps

These are competitive strategy concepts the AI lacks entirely.

### AI-TACTIC-1: No Target Priority Framework [HIGH]

**Current:** Shooting targets are scored purely on expected damage output per weapon. There is no macro-level threat assessment or kill priority.
**Impact:** The AI doesn't focus fire to remove key threats, doesn't prioritize finishing off wounded units, and doesn't consider the trade value of killing a unit.
**Competitive reference:** "Shoot what you can kill and use the weapons designed to kill the right targets." — Goonhammer Start Competing
**Fix:** Implement a two-level target priority system:
  - **Macro priority** (start of turn): rank enemy units by threat level (damage output, objective presence, ability value)
  - **Micro priority** (per weapon): allocate weapons to maximize total expected value, not just per-weapon damage

### AI-TACTIC-2: No Focus Fire / Overkill Awareness [HIGH]

**Current:** Each weapon independently picks its best target. Multiple weapons may spread fire across many targets instead of concentrating on one.
**Impact:** The AI rarely kills entire units, which means it doesn't prevent them from acting next turn.
**Competitive reference:** "A dead unit can't shoot, fight, or hold objectives. A wounded unit still can."
**Fix:** Implement a focus-fire system:
  - Calculate total expected damage across ALL weapons against each target
  - Identify kill thresholds (how much damage needed to destroy the unit)
  - Allocate weapons to meet kill thresholds, then redirect excess to secondary targets

### AI-TACTIC-3: No Screening or Deep Strike Denial [HIGH]

**Current:** The AI only considers objectives when positioning units. No consideration of blocking enemy deep strike, screening characters, or zone control.
**Impact:** The AI's backfield is completely exposed to deep strike attacks. Enemy reserves can land on home objectives freely.
**Competitive reference:** "You can prevent enemy Deep Strike threats by spacing out units 18 inches apart, creating a bubble which prevents enemy units from arriving." — Grimhammer Tactics
**Fix:** Implement screening logic:
  - Identify enemy units in reserves
  - Calculate deep strike denial zones (9" bubble around friendly models)
  - Assign expendable/cheap units to screen backfield objectives

### AI-TACTIC-4: No Threat Range Awareness [HIGH]

**Current:** The AI doesn't pre-measure enemy threat ranges before moving.
**Impact:** Units may move into charge range of enemy melee threats, or into rapid fire range when they could have stayed at long range.
**Competitive reference:** "Pre-measure enemy threat ranges, potential firing lanes, and charges before moving." — Goonhammer fundamentals
**Fix:** Before each movement decision:
  - Calculate all enemy threat ranges (movement + charge range for melee, weapon ranges for shooting)
  - Score positions based on safety vs. offensive value

### AI-TACTIC-5: No Multi-Phase Planning [MEDIUM]

**Current:** Each phase is decided independently. Movement doesn't consider shooting lanes. Shooting doesn't consider upcoming charge opportunities.
**Impact:** The AI may move a unit out of shooting range, or shoot at a target it was planning to charge (wasting the charge bonus).
**Fix:** Implement cross-phase planning:
  - Movement phase: consider shooting ranges, charge angles, fight positioning
  - Shooting phase: don't shoot at targets you want to charge (unless necessary)
  - Charge phase: prefer charges that lock dangerous enemy shooting units in combat

### AI-TACTIC-6: No Trade/Tempo Awareness [MEDIUM]

**Current:** The AI doesn't track the points value or strategic value of units being traded.
**Impact:** It may trade a 200-point unit to kill a 50-point unit, or vice versa.
**Competitive reference:** "Controlling tempo determines who sets the terms for the engagement." — Grimhammer Tactics
**Fix:** Track points value, VP score, and turn count. Adjust aggression based on score differential.

### AI-TACTIC-7: No Secondary Mission Awareness [MEDIUM]

**Current:** `_decide_scoring()` immediately ends the scoring phase with no consideration of secondary mission conditions.
**Impact:** The AI doesn't position units to score secondary missions and never discards unfavorable secondaries.
**Fix:** Query active secondary missions and factor their conditions into movement and target selection.

### AI-TACTIC-8: No Weapon-Target Efficiency Matching [MEDIUM]

**Current:** All weapons are independently assigned to their highest-damage target regardless of weapon suitability.
**Impact:** Anti-tank weapons may be wasted on infantry blobs. Anti-infantry weapons may be pointed at vehicles.
**Competitive reference:** "Anti-tank weapons at vehicles and monsters, anti-infantry at infantry and swarms. Don't waste multi-damage shots on single-wound models." — Goonhammer
**Fix:** Compare weapon damage vs. target wounds per model. Penalize multi-damage weapons targeting single-wound models.

### AI-TACTIC-9: No Move Blocking [LOW]

**Current:** The AI doesn't position units to block enemy movement corridors.
**Fix:** Identify key movement corridors and position expendable units to block them.

### AI-TACTIC-10: No Late-Game Pivot [LOW]

**Current:** The AI uses the same strategy throughout the game. Has basic round-awareness but no strategic shift.
**Competitive reference:** "Turn 4 is usually the magic turn where you need to start considering objectives along with simply killing things."
**Fix:** Implement turn-based strategy modifier:
  - Rounds 1-2: aggressive positioning
  - Round 3: balance attacking and defending
  - Rounds 4-5: prioritize objective control and survival

---

## Phase-by-Phase AI Logic Gaps

### Formations Phase

| ID | Gap | Priority |
|----|-----|----------|
| FORM-1 | No leader attachment evaluation (leaders never joined to bodyguard units) | HIGH |
| FORM-2 | No transport embarkation (transports never used) | MEDIUM |
| FORM-3 | No reserves declaration (all units deployed on table) | MEDIUM |

### Deployment Phase

| ID | Gap | Priority |
|----|-----|----------|
| DEPLOY-1 | No terrain-aware deployment (units placed without regard to cover or LoS blocking) | HIGH |
| DEPLOY-2 | No counter-deployment (doesn't react to where opponent deploys) | MEDIUM |
| DEPLOY-3 | Deployment spread is fixed column pattern regardless of army composition | MEDIUM |
| DEPLOY-4 | No character hiding behind LoS-blocking terrain | MEDIUM |
| DEPLOY-5 | No forward deployment for aggressive units (melee units near front edge) | LOW |

### Scout Phase

| ID | Gap | Priority |
|----|-----|----------|
| SCOUT-1 | All scout moves are skipped entirely | HIGH |
| SCOUT-2 | Should move scouts toward nearest uncontrolled objective | HIGH |

### Command Phase

| ID | Gap | Priority |
|----|-----|----------|
| CMD-1 | Command Re-roll always used regardless of probability improvement | LOW |
| CMD-2 | No Insane Bravery usage evaluation (should use on critical units) | LOW |
| CMD-3 | No faction ability activation (Oath of Moment target selection, Waaagh declaration) | MEDIUM |

### Movement Phase

| ID | Gap | Priority |
|----|-----|----------|
| MOV-1 | No shooting range consideration when positioning (may move out of weapon range) | HIGH |
| MOV-2 | No enemy threat range avoidance (may walk into charge range) | HIGH |
| MOV-3 | No Heavy weapon bonus consideration (should remain stationary when Heavy bonus is valuable) | MEDIUM |
| MOV-4 | No screening/deep strike denial positioning | HIGH |
| MOV-5 | No multi-turn pathing (single-turn greedy only) | LOW |
| MOV-6 | Fall-back path destinations are not computed (fall back doesn't move models) | HIGH |
| MOV-7 | No transport disembark decisions | MEDIUM |

### Shooting Phase

| ID | Gap | Priority |
|----|-----|----------|
| SHOOT-1 | No focus fire coordination across units | HIGH |
| SHOOT-2 | No weapon-target efficiency matching | HIGH |
| SHOOT-3 | Invulnerable saves not factored into target scoring | MEDIUM |
| SHOOT-4 | No range-band optimization (Rapid Fire bonus at half range, Melta bonus) | MEDIUM |
| SHOOT-5 | No cover/benefit-of-cover consideration in target scoring | MEDIUM |
| SHOOT-6 | Battle-shocked units still selected as shooters (should be auto-skipped) | LOW |
| SHOOT-7 | No Pistol usage evaluation (should fire Pistols when in engagement range) | MEDIUM |

### Charge Phase

| ID | Gap | Priority |
|----|-----|----------|
| CHARGE-1 | All charges skipped — charge logic not implemented | CRITICAL |
| CHARGE-2 | No charge probability assessment (average roll 7", probability curves) | HIGH |
| CHARGE-3 | No charge move model positioning | HIGH |
| CHARGE-4 | No multi-target charge declarations | MEDIUM |
| CHARGE-5 | No risk assessment (overwatch damage vs. charge benefit) | MEDIUM |

### Fight Phase

| ID | Gap | Priority |
|----|-----|----------|
| FIGHT-1 | Pile-in movement always empty (models don't move toward enemies) | CRITICAL |
| FIGHT-2 | Consolidation movement always empty (models don't consolidate) | CRITICAL |
| FIGHT-3 | Only first melee weapon used, no multi-weapon optimization | MEDIUM |
| FIGHT-4 | Target selection is nearest-distance only, not damage-optimal | MEDIUM |
| FIGHT-5 | No Counter-Offensive stratagem usage when beneficial | MEDIUM |
| FIGHT-6 | No fight order optimization (which unit to activate first) | LOW |

### Scoring Phase

| ID | Gap | Priority |
|----|-----|----------|
| SCORE-1 | Scoring phase immediately ended, no secondary mission evaluation | MEDIUM |
| SCORE-2 | No discard decision for unachievable secondary missions | LOW |

---

## Missing Weapon Keywords Affecting AI

The following weapon keywords are not yet fully integrated, which limits AI combat effectiveness:

| Keyword | Effect | AI Impact | Engine Status |
|---------|--------|-----------|---------------|
| **Conversion X+** | Crit hits on X+ at 12"+ range | AI doesn't position at optimal range | Implemented in Mathhammer only |
| **Extra Attacks** | Bonus attacks added automatically | AI only uses one melee weapon | Partially implemented |
| **One Shot** | Can only fire once per battle | AI correctly skips fired One Shot weapons | Implemented |
| **Precision** | Can target Characters in attached units | AI can't snipe Characters | Implemented |
| **Lance** | +1 to wound on charge turn | AI never charges so never triggers | Implemented |

Note: Melta, Twin-linked, Hazardous, Indirect Fire, Stealth, and Lone Operative are already implemented per MASTER_AUDIT.md.

---

## Quality of Life Improvements

### QoL-1: AI Turn Summary Panel [HIGH]

**Current:** AI actions are logged to console only. The human player has no in-game summary of what the AI did.
**Existing infrastructure:** `AIPlayer` emits `ai_action_taken` and `ai_turn_ended` signals with action descriptions, and maintains `_action_log`. These signals are not consumed by any UI.
**Fix:** Create a turn summary panel that displays after each AI turn with units moved, shooting results, charge results, and fight results.

### QoL-2: AI Thinking Indicator [HIGH]

**Current:** When the AI is processing its turn, there's no visual feedback. The game appears frozen for 50ms between actions.
**Fix:** Display an "AI is thinking..." indicator with a spinner or pulsing animation during AI evaluation.

### QoL-3: AI Speed Controls [MEDIUM]

**Current:** `AI_ACTION_DELAY` is hardcoded to 50ms. Players can't slow down or speed up the AI.
**Fix:** Add a speed slider in game settings:
  - Fast (0ms delay) — for testing
  - Normal (200ms delay) — see each action briefly
  - Slow (500ms delay) — follow along in detail
  - Step-by-step (pause after each action, click to continue)

### QoL-4: AI Decision Explanations [MEDIUM]

**Current:** `_ai_description` strings are terse (e.g., "Boyz moves toward obj_2").
**Fix:** Enhance descriptions with reasoning:
  - "Boyz moves toward Objective 2 (uncontrolled, 8.5in away, OC 2 needed)"
  - "Lascannon shoots at Battlewagon (expected 4.2 damage, 67% kill probability)"
  - "Warboss charges Intercessors (7in needed, 58% success rate)"

### QoL-5: AI Difficulty Levels [MEDIUM]

**Current:** Single difficulty level with basic heuristics.
**Fix:** Implement 3 difficulty levels:
  - **Easy:** Random valid actions with slight objective awareness
  - **Normal:** Current heuristic system with improvements from this audit
  - **Hard:** Full tactical system with focus fire, screening, multi-phase planning, stratagem usage

### QoL-6: AI vs AI Spectator Mode Improvements [LOW]

**Current:** AI vs AI is supported but the game flies by with no ability to follow along.
**Fix:** In AI vs AI mode, auto-slow the action delay and show turn summaries for both players.

### QoL-7: Undo / Replay AI Turn [LOW]

**Current:** No way to review what the AI did after the turn passes.
**Fix:** Store the full action log per turn and provide a replay panel accessible from the game menu.

---

## Visual Improvements

### VIS-1: AI Movement Path Visualization [HIGH]

**Current:** AI units teleport to their destinations. No movement path is shown.
**Fix:** Draw a brief movement trail (dotted line or arrow) from each model's origin to destination during AI movement. Fade after 1-2 seconds.

### VIS-2: AI Target Lines for Shooting [MEDIUM]

**Current:** Shooting results appear but there's no visual connection between shooter and target during AI shooting.
**Fix:** Draw a brief targeting line (red) from shooting unit to target when the AI fires. Show hit/wound results as floating text near the target.

### VIS-3: AI Charge Arrows [MEDIUM]

**Current:** N/A (charges not implemented), but when implemented:
**Fix:** Draw charge declaration arrows (orange/yellow) from charger to target, show charge roll result prominently.

### VIS-4: Objective Control Indicators During AI Turn [MEDIUM]

**Current:** Objective control state is shown but doesn't highlight changes during AI movement.
**Fix:** Flash objective markers when control state changes during the AI turn.

### VIS-5: AI Unit Highlighting [LOW]

**Current:** No visual distinction for which unit the AI is currently acting with.
**Fix:** Add a glow or highlight ring around the active AI unit during its actions. Different colors for different action types (blue = move, red = shoot, orange = charge).

### VIS-6: Damage Numbers / Kill Feed [LOW]

**Current:** Shooting/fight results are shown in dialog overlays but not as floating combat text.
**Fix:** Show floating damage numbers above targets when the AI deals damage, and a kill notification when a unit is destroyed.

### VIS-7: AI Action Log Overlay [LOW]

**Current:** Actions logged to console only.
**Fix:** Small scrolling text overlay in corner showing real-time AI actions as they happen.

---

## Prioritized TODO List

### P0 — Critical (AI plays incorrectly without these)

- [ ] **Implement AI charge declarations** — evaluate charge feasibility (distance, probability), declare charges against optimal targets, compute model positions post-charge (AI-GAP-1, CHARGE-1 through CHARGE-3)
- [ ] **Implement pile-in movement** — move models up to 3" toward nearest enemy during fight phase (AI-GAP-2, FIGHT-1)
- [ ] **Implement consolidation movement** — move models up to 3" toward nearest enemy or objective after fighting (AI-GAP-2, FIGHT-2)
- [ ] **Implement fall-back model positioning** — compute valid fall-back destinations away from enemy engagement range (MOV-6)

### P1 — High (AI plays very poorly without these)

- [ ] **Implement focus fire system** — coordinate weapon assignments across all shooting units to concentrate on kill thresholds (AI-TACTIC-2, SHOOT-1)
- [ ] **Implement weapon-target efficiency matching** — match anti-tank to vehicles, anti-infantry to hordes, avoid wasting multi-damage on single-wound models (AI-TACTIC-8, SHOOT-2)
- [ ] **Implement basic stratagem usage** — start with Grenade, Fire Overwatch, Go to Ground, Command Re-roll (AI-GAP-3)
- [ ] **Implement scout move execution** — move scout units toward nearest uncontrolled objective (SCOUT-1, SCOUT-2)
- [ ] **Add enemy threat range awareness** — calculate charge threat zones and shooting ranges, avoid moving into danger (AI-TACTIC-4, MOV-2)
- [ ] **Add shooting range consideration to movement** — don't move units out of their weapon range (MOV-1)
- [ ] **Implement screening/deep strike denial** — position cheap units to deny enemy deep strike zones (AI-TACTIC-3, MOV-4)
- [ ] **Implement leader attachment in formations** — evaluate and attach leaders to bodyguard units (FORM-1)
- [ ] **Add terrain-aware deployment** — place units behind LoS-blocking terrain for cover (DEPLOY-1)
- [ ] **Add invulnerable save to target scoring** — use min(modified_save, invuln) in shooting target evaluation (AI-GAP-5, SHOOT-3)
- [ ] **Add AI turn summary panel** — consume existing AIPlayer signals to show what happened (QoL-1)
- [ ] **Add AI thinking indicator** — show visual feedback during AI processing (QoL-2)
- [ ] **Add AI movement path visualization** — draw movement trails during AI unit movement (VIS-1)

### P2 — Medium (AI competence and feel improvements)

- [ ] **Implement target priority framework** — macro-level threat ranking + micro-level weapon allocation (AI-TACTIC-1)
- [ ] **Implement multi-phase planning** — movement considers shooting lanes, shooting considers upcoming charges (AI-TACTIC-5)
- [ ] **Implement trade/tempo awareness** — track points values, adjust aggression based on VP score (AI-TACTIC-6)
- [ ] **Implement secondary mission awareness** — factor secondary conditions into positioning and targeting (AI-TACTIC-7)
- [ ] **Implement Heavy weapon stationary bonus** — prefer remaining stationary when Heavy bonus is significant (MOV-3)
- [ ] **Implement multi-weapon melee optimization** — use Extra Attacks weapons, pick best weapon per target (AI-GAP-6, FIGHT-3)
- [ ] **Implement fight target optimization** — score melee targets by expected damage, not just distance (FIGHT-4)
- [ ] **Add range-band optimization** — prefer Rapid Fire half-range, Melta half-range positioning (SHOOT-4)
- [ ] **Add cover consideration in target scoring** — penalize targets with Benefit of Cover (SHOOT-5)
- [ ] **Implement Counter-Offensive stratagem** — use 2CP when AI's high-value melee unit is at risk (FIGHT-5)
- [ ] **Implement transport usage** — embark in formations, disembark during movement (FORM-2, MOV-7)
- [ ] **Implement reserves declarations** — put appropriate units in strategic reserves or deep strike (FORM-3)
- [ ] **Add AI speed controls** — configurable action delay (QoL-3)
- [ ] **Add AI decision explanations** — enhanced _ai_description with reasoning (QoL-4)
- [ ] **Add AI shooting target lines** — visual targeting feedback (VIS-2)
- [ ] **Add objective control flash on change** — highlight when AI flips objectives (VIS-4)

### P3 — Low (Polish and competitive-level play)

- [ ] **Implement AI difficulty levels** — Easy/Normal/Hard with different heuristic depths (QoL-5)
- [ ] **Implement move blocking** — position units to block enemy movement corridors (AI-TACTIC-9)
- [ ] **Implement late-game strategy pivot** — shift priorities based on turn and VP score (AI-TACTIC-10)
- [ ] **Implement counter-deployment** — react to opponent's deployment choices (DEPLOY-2)
- [ ] **Implement faction ability activation** — Oath of Moment target, Waaagh declaration (CMD-3)
- [ ] **Implement fight order optimization** — choose which unit fights first for best outcomes (FIGHT-6)
- [ ] **Implement secondary mission discard logic** — discard unachievable secondaries for CP (SCORE-2)
- [ ] **Add Pistol usage in engagement range** — fire Pistols when in melee (SHOOT-7)
- [ ] **Implement charge multi-target declarations** — declare charges against multiple nearby enemies (CHARGE-4)
- [ ] **Implement overwatch risk assessment** — weigh charge benefit vs. overwatch damage (CHARGE-5)
- [ ] **Add AI unit highlighting during actions** — glow effect on active unit (VIS-5)
- [ ] **Add floating damage numbers** — combat text for damage and kills (VIS-6)
- [ ] **Add AI action log overlay** — scrolling real-time action feed (VIS-7)
- [ ] **Add AI vs AI spectator improvements** — auto-slow and dual summaries (QoL-6)
- [ ] **Add AI turn replay** — review previous AI turn actions (QoL-7)
- [ ] **Implement charge arrow visualization** — show charge declarations visually (VIS-3)

---

## Summary Statistics

| Category | Total Items | Critical | High | Medium | Low |
|----------|-------------|----------|------|--------|-----|
| Rules Compliance Gaps | 7 | 2 | 3 | 1 | 1 |
| Strategic/Tactical Gaps | 10 | 0 | 4 | 4 | 2 |
| Phase-Specific Gaps | 29 | 3 | 10 | 11 | 5 |
| QoL Improvements | 7 | 0 | 2 | 3 | 2 |
| Visual Improvements | 7 | 0 | 1 | 3 | 3 |
| **TOTAL** | **60** | **5** | **20** | **22** | **13** |
