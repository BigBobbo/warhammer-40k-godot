# AI Opponent Audit — Comprehensive Gap Analysis

> **Generated:** 2026-02-19
> **Files audited:** `AIPlayer.gd` (492 lines), `AIDecisionMaker.gd` (2076 lines), `RulesEngine.gd`, all phase files, `StratagemManager.gd`, `FactionAbilityManager.gd`, `UnitAbilityManager.gd`
> **Compared against:** Warhammer 40k 10th Edition Core Rules (wahapedia.ru), Goonhammer competitive tactics, community strategy guides
>
> Items are grouped into priority tiers based on impact to AI competence. Each item includes current behavior, expected behavior per rules/tactics, and suggested implementation approach.

---

## How to Read This Document

- **Severity:** CRITICAL > HIGH > MEDIUM > LOW > QoL/Visual
- CRITICAL = AI cannot play a legal/functional game without this
- HIGH = AI plays significantly worse than a novice human
- MEDIUM = AI plays but misses important tactical opportunities
- LOW = Nice-to-have improvements for more human-like play
- QoL = Quality of life and visual feedback improvements

---

## Architecture Overview

The AI uses a **signal-driven, per-action heuristic system**:
- `AIPlayer.gd` — autoload controller that monitors `PhaseManager.phase_changed` and `phase_action_taken` signals, schedules evaluations with 50ms frame delays
- `AIDecisionMaker.gd` — pure static decision logic, receives `(phase, snapshot, available_actions, player)` and returns an action dictionary
- Actions routed through `NetworkIntegration.route_action()` — identical pipeline to human players and multiplayer

**Key Limitation:** The AI is entirely stateless between decisions. It has no memory of previous turns, no multi-turn planning, and no opponent modeling. Every decision is made from the current game snapshot alone.

---

## TIER 1 — CRITICAL: AI Cannot Function Properly Without These

These gaps cause the AI to be unable to play core parts of the game, resulting in a fundamentally incomplete opponent.

### AI-1. Charge Phase — AI skips all charges (never initiates melee)
- **Current:** `_decide_charge()` always returns `SKIP_CHARGE` for every unit. Comment on line 1598: "not implemented, complex model positioning"
- **Impact:** The AI can never engage in melee combat voluntarily. Melee-focused armies (Orks, World Eaters, Blood Angels, etc.) are completely non-functional. Even shooty armies need charges to contest objectives or finish weakened units. This is the single largest gap in the AI.
- **Expected (10e rules):** Evaluate each chargeable unit. If within 12" of an enemy and the unit has melee weapons, calculate charge probability (2D6 >= distance - 1" engagement range). Declare charges against target(s), roll 2D6, move models into engagement range maintaining coherency and B2B contact.
- **Suggested approach:**
  1. Score charge targets similarly to shooting (expected melee damage, objective importance)
  2. Calculate charge success probability using 2D6 distribution
  3. Only charge when P(success) > threshold (e.g., 50% for important targets, 70% for risky ones)
  4. Reuse `_compute_movement_toward_target()` logic for model positioning after successful roll
  5. Place models in B2B contact with targets, maintaining coherency
- **Competitive relevance:** Every competitive 40k army uses charges. Melee is how you flip objectives, deny enemy scoring, and remove key threats. An AI that never charges is fundamentally broken.

### AI-2. Fight Phase — No pile-in, no consolidation, simplistic attack allocation
- **Current:**
  - Pile-in: always submits empty `movements: {}` (holds position)
  - Consolidation: always submits empty `movements: {}` (holds position)
  - Weapon selection: picks the first melee weapon found, ignoring all others
  - Target selection: picks nearest enemy by centroid distance, not engagement range or damage potential
- **Impact:** AI fighters are stationary punching bags. They don't pull models into combat, don't wrap units to prevent fall-back, don't consolidate onto objectives or into new combats — all fundamental melee tactics.
- **Expected (10e rules):**
  - **Pile-in:** Move each model up to 3" toward the closest enemy model. Models in B2B should not move. This maximizes the number of models that can fight.
  - **Consolidation:** Move each model up to 3" toward the nearest enemy or objective marker. Tactical uses: wrap enemy units (surround to prevent fall-back), tag new enemy units, move onto objectives.
  - **Weapon selection:** Choose the best melee weapon per model. Consider S vs T matchups. Use all available melee weapons, not just the first one.
  - **Target selection:** Choose targets based on expected damage and tactical priority, not just distance.
- **Suggested approach:**
  1. Pile-in: for each model not in B2B, compute direction toward closest enemy model and move up to 3"
  2. Consolidation: score each possible 3" move by: proximity to objective (+), proximity to unengaged enemy (+), wrapping potential (+)
  3. Weapon selection: score each weapon against the target (same expected damage calculation as shooting)
  4. Target: pick the enemy unit where expected damage is highest, or that's on an important objective

### AI-3. No stratagem usage — AI never spends CP
- **Current:** The AI never uses any stratagems. Not Overwatch, not Command Re-roll (except for battle-shock), not Counter-Offensive, not Heroic Intervention, not Smokescreen, not Go to Ground — nothing.
- **Impact:** Stratagems are one of the most impactful aspects of 10th edition. A player who never uses stratagems is playing with a massive handicap. The CP just accumulates unused.
- **Expected (10e rules):** Use core stratagems at appropriate times:
  - **Fire Overwatch** (1 CP): When opponent charges or moves near a key unit. Hit on 6s only, but can deter charges or soften attackers.
  - **Command Re-roll** (1 CP): When an important die roll fails (key save, charge roll, hit roll on high-value weapon). Currently only used for battle-shock.
  - **Counter-Offensive** (2 CP): When enemy fights first and our unit is in danger of being wiped before it can fight back.
  - **Heroic Intervention** (2 CP): When enemy charges near a CHARACTER. Counter-charge to protect key units.
  - **Smokescreen** (1 CP): Protect key units from shooting with -1 to hit.
  - **Go to Ground** (1 CP): Protect INFANTRY on objectives with 6+ invuln + cover.
  - **Insane Bravery** (1 CP): Already handled for battle-shock.
- **Suggested approach:**
  1. Create a stratagem evaluation system that checks available stratagems at each decision point
  2. Score each stratagem by expected value (how much does it change the outcome?)
  3. Weigh against CP cost and remaining CP
  4. Priority order: defensive first (protect units on objectives), then offensive (amplify damage)

---

## TIER 2 — HIGH: AI Plays Significantly Worse Than a Novice Human

These gaps cause the AI to make consistently poor decisions that any beginner player would recognize as mistakes.

### AI-4. Shooting target scoring doesn't check weapon range
- **Current:** `_score_shooting_target()` calculates expected damage but never checks if the target is within the weapon's range. The actual range validation happens in `RulesEngine.validate_shoot()` which then rejects the action, causing the AI to waste its turn on failed shooting attempts (then SKIP_UNIT fallback).
- **Impact:** AI frequently attempts to shoot targets that are out of range, then skips the unit entirely when the action fails. This means units that DO have valid targets in range don't get to shoot.
- **Fix:** Add range check to `_score_shooting_target()`. Compare weapon range (in inches) to distance between shooter centroid and target centroid. Score 0 for out-of-range targets.

### AI-5. No weapon-to-target optimization (all weapons fire at same target)
- **Current:** All ranged weapons on a unit are assigned to a single "best" target. A lascannon (S12 AP-3 D6+1) and a bolt rifle (S4 AP-1 D1) both fire at the same target.
- **Impact:** Massively inefficient. High-AP anti-tank weapons should target vehicles/monsters. High-volume low-AP weapons should target infantry hordes. Splitting fire is a fundamental 40k tactic.
- **Expected:** For each weapon, independently score all eligible targets. Assign each weapon to its best target.
- **Fix:** Change the weapon assignment loop in `_decide_shooting()` to score targets per-weapon instead of per-unit. Each weapon gets its own `best_target_id`.

### AI-6. Shooting target scoring ignores invulnerable saves
- **Current:** `_save_probability()` only considers armor save + AP. No invulnerable save check. Against a 4++ invulnerable save unit, the AI calculates expected damage as if AP fully penetrates, drastically overestimating effectiveness.
- **Impact:** AI wastes high-AP weapons on units with invulnerable saves (e.g., shooting lascannons at Custodes with 4++) when those weapons would be better used against units relying on armor saves.
- **Fix:** Read `target_unit.meta.stats.invuln` (if present). Use `min(modified_armor_save, invuln_save)` for save probability calculation.

### AI-7. Shooting target scoring ignores weapon keywords
- **Current:** Expected damage calculation is purely `attacks * hit_prob * wound_prob * unsaved_prob * damage`. No consideration of: Lethal Hits, Sustained Hits, Devastating Wounds, Blast, Rapid Fire at half range, Melta bonus damage, Anti-keyword, Torrent (auto-hit).
- **Impact:** AI doesn't understand weapon synergies. A Blast weapon against a 20-model unit should be prioritized. A Melta weapon at half range should target vehicles. Anti-Infantry weapons should target infantry.
- **Fix:** Enhance `_score_shooting_target()` to:
  - Check Blast keyword: add +1 attack per 5 models in target
  - Check Rapid Fire: add +X attacks if within half range
  - Check Melta: add +X damage if within half range
  - Check Anti-keyword: lower critical wound threshold if target has matching keyword
  - Check Torrent: set hit probability to 1.0

### AI-8. Movement doesn't consider shooting range positioning
- **Current:** Movement AI only moves toward objectives. A unit with 24" range weapons sitting 30" from the nearest enemy will walk toward an objective without considering that moving 6" closer to the enemy would put targets in range.
- **Impact:** Ranged units often end up out of shooting range because they're moving toward objectives rather than positioning for effective fire.
- **Fix:** After computing the objective-based move target, check if the destination puts any enemy units in weapon range. If current position has no targets in range but a slight adjustment would, bias the movement vector toward the nearest viable shooting position.

### AI-9. No reinforcements/reserves deployment
- **Current:** AI never brings units in from Strategic Reserves or Deep Strike. Units placed in reserves during deployment (as a fallback for failed deployment) remain in reserves for the entire game.
- **Impact:** Reserves are a core tactical tool. Deep Strike allows units to arrive 9"+ from enemies in the Movement phase from round 2 onward. The AI effectively plays with fewer units if any are in reserves.
- **Expected (10e rules):** From Battle Round 2+, units in Strategic Reserves can be set up from a board edge. Units in Deep Strike can arrive anywhere 9"+ from enemy models.
- **Fix:** In `_decide_movement()`, check for reserve units. If any exist and it's Round 2+, prioritize bringing them onto the board near objectives or behind enemy lines.

### AI-10. No secondary mission planning
- **Current:** `_decide_scoring()` just returns `END_SCORING`. The AI never evaluates secondary missions, never voluntarily discards missions for CP, never plans movement around secondary objectives.
- **Impact:** Secondary missions can account for up to 40 VP (out of ~90 total). Ignoring them means the AI is playing for only primary VP, putting it at a massive scoring disadvantage.
- **Fix:** In `_decide_command()`, evaluate active secondary missions and plan which ones to pursue. In `_decide_movement()`, factor secondary mission requirements into unit assignments. In `_decide_scoring()`, handle voluntary discards.

### AI-11. Formations phase — no leader attachments or transport decisions
- **Current:** `_decide_formations()` immediately confirms with no leader attachments, transport embarkations, or reserve declarations.
- **Impact:** Leader attachments are fundamental in 10th edition. Attaching a character to a unit grants Look Out Sir protection and often powerful leader abilities (re-rolls, FNP, etc.). Not attaching leaders means they're vulnerable and their abilities are wasted.
- **Fix:** Evaluate available leaders and eligible bodyguard units. Attach leaders to appropriate units based on: ability synergy, unit survivability, positioning needs.

---

## TIER 3 — MEDIUM: AI Misses Important Tactical Opportunities

### AI-12. No threat avoidance in movement
- **Current:** Movement only considers moving toward objectives. If a fragile shooting unit is 8" from a melee-focused enemy, the AI may move it closer to an objective that happens to be near the enemy, getting it charged and destroyed next turn.
- **Impact:** AI units walk into charge range of enemy melee units unnecessarily. A human player would position outside 12" to avoid charges.
- **Fix:** Add a threat penalty to movement destinations. If the destination is within 12" of a dangerous melee enemy (and the unit is a fragile ranged unit), penalize that destination. Consider "safe" positions outside charge range.

### AI-13. Scout moves skipped entirely
- **Current:** `_decide_scout()` skips all scout moves.
- **Impact:** Scout moves (typically 6") are free pre-game movement. They can put units on objectives turn 1, set up screens, or establish forward positions. Skipping them wastes a significant advantage.
- **Fix:** For each scout-eligible unit, evaluate whether moving toward the nearest objective puts it in control range or closer to a key position. Move scouts toward objectives, maintaining >9" from enemies (as per rules).

### AI-14. No Overwatch reactions
- **Current:** AI never uses Fire Overwatch when the opponent charges or moves near its units.
- **Impact:** Overwatch (hitting on 6s) is a deterrent and occasional damage source. Against large charge targets, Overwatch can remove models and potentially deny the charge.
- **Fix:** When the AI receives a `FIRE_OVERWATCH_OPPORTUNITY` signal (or equivalent action), evaluate: does the unit have ranged weapons? Is the charger a valuable target? Is 1 CP worth the expected damage? If yes, use Overwatch.

### AI-15. Command Re-roll always used for battle-shock, never for other rolls
- **Current:** AI always accepts Command Re-roll for battle-shock tests. Never considers using it for: failed charge rolls, important save rolls, key hit/wound rolls.
- **Impact:** Command Re-roll on a critical charge roll or save could be game-changing. Spending it on a battle-shock test for a non-essential unit is often wasteful.
- **Fix:** Implement a Command Re-roll evaluation that considers: unit importance, impact of the re-roll, CP remaining. Decline re-roll for low-importance battle-shock tests and save the CP.

### AI-16. No multi-turn planning
- **Current:** AI makes each decision independently based on current snapshot. No awareness of future turns, opponent's likely responses, or long-term strategy.
- **Impact:** AI can't set up plays like: "move here this turn so I can charge next turn" or "hold this unit back to screen a later deep strike." It can't predict enemy movements or plan counter-strategies.
- **Suggested approach (incremental):**
  1. **1-turn lookahead for movement:** Before committing to a move, simulate: "If I move here, can the enemy charge me? Can I shoot effectively next turn?"
  2. **Battle round awareness:** Early game (rounds 1-2) emphasize positioning. Late game (rounds 4-5) emphasize VP maximization.
  3. This is already partially implemented (round 1 urgency scoring) but could be expanded.

### AI-17. No Faction Ability usage (Oath of Moment target selection)
- **Current:** The AI doesn't select Oath of Moment targets despite the system being fully implemented. FactionAbilityManager auto-selects the first enemy unit if the player (AI) doesn't choose.
- **Impact:** Oath of Moment grants re-roll 1s to hit AND wound against the selected target for ALL Adeptus Astartes units. Selecting the right target (the one you plan to focus fire on) multiplies your army's damage output significantly.
- **Fix:** In `_decide_command()`, if playing as Space Marines/ADEPTUS ASTARTES, evaluate enemy units and select the Oath target based on: which enemy will most of your army shoot at, which target benefits most from re-rolls (T4+ vs S4 weapons), which target is the biggest threat.

### AI-18. No transport usage (embark/disembark)
- **Current:** AI never embarks units into transports or disembarks them. Transports are treated as standalone units.
- **Impact:** Transports provide protection and mobility. A squad of Marines in a Rhino can advance safely, then disembark next turn to capture an objective. Without transport usage, the AI wastes a key tactical tool.
- **Fix:** Evaluate transport capacity and matching unit types. Embark fragile units that need to cross the board. Disembark when within range of objectives or shooting targets.

### AI-19. No focus fire / overkill awareness
- **Current:** Each weapon independently targets its "best" target. The AI doesn't coordinate fire across units to ensure kills, nor does it avoid overkill on nearly-dead units.
- **Impact:** AI may spread damage across 5 enemy units, killing none, instead of focusing on 2 units and killing both. In competitive play, "a dead model doesn't shoot back" — partial damage is often wasted.
- **Fix:** Track cumulative expected damage on each target across all shooting units. Once expected damage exceeds target's remaining wounds, stop assigning more weapons to that target. Prioritize confirmed kills over damage spread.

### AI-20. Engaged unit decisions ignore unit strength and matchup
- **Current:** Engaged units decide to hold or fall back based only on: are they on an objective? Do they have OC advantage? But never consider: how much damage will they take in the fight phase? Can they survive another round of combat? Is this unit better off shooting next turn?
- **Impact:** A 5-model Intercessor squad locked in combat with 20 Ork Boyz will hold the objective (correct) but won't fall back even when the Boyz will wipe them next fight phase (incorrect — better to fall back, shoot the Boyz, then reclaim the objective).
- **Fix:** Add a survival assessment: estimate expected damage this fight phase. If the unit will likely be destroyed, consider falling back regardless of OC.

---

## TIER 4 — LOW: Nice-to-Have for More Human-Like Play

### AI-21. No difficulty levels
- **Current:** Single difficulty — same heuristics for all games.
- **Suggested levels:**
  - **Easy:** Random movement, always shoots nearest target, never uses stratagems, sometimes makes suboptimal moves intentionally
  - **Normal:** Current implementation with fixes from Tier 1-2
  - **Hard:** Full stratagem usage, weapon-target optimization, multi-turn awareness, threat avoidance
  - **Competitive:** Look-ahead planning, army-specific strategies, optimal stratagem timing

### AI-22. No army-specific strategies
- **Current:** AI uses identical heuristics regardless of army composition. An all-melee Ork army plays identically to a shooty Tau gunline.
- **Fix:** Detect army archetype based on weapon/keyword distribution:
  - **Melee-focused** (>60% melee weapons): aggressive advance, early charges, wrap & trap tactics
  - **Shooting-focused** (>60% ranged, long range): castle deployment, maintain range, fall back over charge
  - **Balanced:** current objective-driven approach works well
  - **Elite** (few high-wound models): protect key models, focus fire, avoid bad trades

### AI-23. No unit trading evaluation
- **Current:** AI doesn't consider the "trade" — sacrificing a cheap unit to remove an expensive one. E.g., charging 65-point Gretchin into 200-point Eradicators to tie them up.
- **Fix:** Add points-per-wound calculation. A cheap unit (low points) engaging or trading with an expensive unit (high points) is a positive trade.

### AI-24. No screening behavior
- **Current:** `_compute_screen_position()` function exists in AIDecisionMaker but is never called from any decision path.
- **Impact:** Screening (placing cheap units between enemy and valuable units) is a core competitive tactic. It prevents deep strike charges, blocks enemy movement lanes, and protects key assets.
- **Fix:** Wire up screening logic in pass 3 of unit assignment. Unassigned cheap units with low OC should screen valuable units or deep strike landing zones.

### AI-25. Deployment doesn't consider army matchup
- **Current:** Deployment spreads units evenly across the zone in columns, biased toward objectives. No consideration of the opponent's army composition.
- **Fix:** If opponent has melee-heavy army, deploy further back. If opponent has shooting-heavy army, deploy with terrain cover. Deploy melee units forward, ranged units behind.

### AI-26. No Rapid Ingress stratagem usage
- **Current:** AI never uses Rapid Ingress (1 CP, arrive from reserves at end of opponent's movement phase).
- **Impact:** Rapid Ingress allows reactive deployment — arriving after seeing where the opponent moved. Very strong for objective play.
- **Fix:** When opponent's movement phase ends, evaluate if any reserve units would benefit from arriving now vs. waiting.

### AI-27. No counter-play to opponent's stratagems
- **Current:** AI doesn't react to opponent's stratagem usage. If opponent uses Smokescreen (-1 to hit), AI doesn't redirect shooting to non-smoked targets.
- **Fix:** Check for active stratagem effects on targets before shooting. Penalize targets with defensive buffs (Smokescreen, Go to Ground) in target scoring.

### AI-28. Fight phase weapon selection uses only one weapon
- **Current:** `_assign_fight_attacks()` selects a single melee weapon (the first one found) and assigns all attacks with it. Many units have multiple melee weapon profiles with different characteristics.
- **Impact:** A unit with both a power fist (S8 AP-2 D2) and a chainsword (S4 AP0 D1) should use the fist against tough targets and the sword against light infantry. Using only one weapon leaves damage on the table.
- **Fix:** For each melee weapon, score it against the target. Assign attacks per-model with the best weapon for the specific target.

---

## TIER 5 — Quality of Life & Visual Improvements

### AI-QoL-1. No AI thinking indicator
- **Current:** When it's the AI's turn, there's no visual indication that the AI is processing. The 50ms action delay looks like the game is frozen.
- **Fix:** Show a "AI is thinking..." banner or spinner during AI turns. Animate unit tokens when the AI selects them for actions.

### AI-QoL-2. No AI action preview
- **Current:** AI actions happen instantly. The human player sees units teleport to new positions and dice results appear without context.
- **Fix:** Add brief visual previews: show movement arrows before confirming movement, highlight targeted units before shooting, show charge lines before charge rolls. Use the existing `GhostVisual.gd` for movement previews.

### AI-QoL-3. AI turn summary missing
- **Current:** `ai_turn_ended` signal exists but isn't connected to any UI. The action log accumulates but is never displayed.
- **Fix:** After each AI turn, show a summary panel listing: units moved and where, units that shot and what they targeted, charges attempted, fight results, VP scored. Use the existing `GameEventLog` system.

### AI-QoL-4. AI decision logging is console-only
- **Current:** AI decisions are logged via `print()` to console/debug log. In-game, the player sees no explanation for AI behavior.
- **Fix:** Route key AI decisions through `GameEventLog.add_ai_entry()` (function already exists). Show entries like: "AI: Intercessors hold Objective A (OC 2 vs enemy OC 1)", "AI: Hellblaster Squad shoots at Carnifex (expected 4.2 damage)".

### AI-QoL-5. AI action pacing is too fast
- **Current:** 50ms between actions. An entire AI shooting phase with 8 units resolves in <1 second. The human player can't follow what happened.
- **Fix:** Add configurable action delay (200ms-1000ms). Add brief pauses between phases. Allow "instant AI" toggle for players who want speed.

### AI-QoL-6. No AI vs AI spectator mode polish
- **Current:** AI vs AI works technically but has no spectator-friendly features.
- **Fix:** Add camera auto-focus on active unit. Show health bars during combat resolution. Add play/pause controls. Show running score overlay.

### AI-QoL-7. No post-game AI performance summary
- **Current:** Game ends with no analysis of how the AI performed.
- **Fix:** After game, show: total VP scored by AI, units lost vs units killed, objectives held per turn, CP spent, key moments (biggest damage dealt, most impactful charge, etc.).

---

## Implementation Priority Roadmap

### Phase 1: Make AI Functional (Tier 1 — CRITICAL)
1. **AI-1: Charge phase** — This is the #1 priority. Without charges, the AI is fundamentally broken.
2. **AI-2: Fight phase improvements** — Pile-in and consolidation make melee units actually effective.
3. **AI-3: Core stratagem usage** — At minimum: Command Re-roll, Overwatch, Smokescreen.

### Phase 2: Make AI Competent (Tier 2 — HIGH)
4. **AI-4: Range checking** — Prevents wasted turns on out-of-range shots.
5. **AI-5: Weapon-to-target optimization** — Split fire is fundamental.
6. **AI-6 + AI-7: Better target scoring** — Invulns, keywords, weapon abilities.
7. **AI-9: Reserves deployment** — Units in reserves need to arrive.
8. **AI-11: Formation decisions** — Leader attachments.
9. **AI-8: Shooting range positioning** — Move into range before shooting.

### Phase 3: Make AI Tactical (Tier 3 — MEDIUM)
10. **AI-12: Threat avoidance** — Don't walk into charge range.
11. **AI-13: Scout moves** — Free pre-game movement.
12. **AI-14: Overwatch reactions** — Deterrent against charges.
13. **AI-19: Focus fire** — Coordinate damage for kills.
14. **AI-17: Oath of Moment** — Faction ability usage.
15. **AI-10: Secondary missions** — Plan for secondary VP.

### Phase 4: Polish (Tier 4-5)
16. AI-21 through AI-28: Difficulty levels, army-specific strategies, screening.
17. AI-QoL-1 through AI-QoL-7: Visual feedback, pacing, summaries.

---

## References

- **Core Rules:** https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- **Competitive Tactics:** https://www.goonhammer.com/start-competing-your-guide-to-getting-better-at-warhammer-40000/
- **AI Source Files:** `40k/autoloads/AIPlayer.gd`, `40k/scripts/AIDecisionMaker.gd`
- **Existing Audits:** MASTER_AUDIT.md (rules compliance), TESTING_AUDIT_SUMMARY.md
