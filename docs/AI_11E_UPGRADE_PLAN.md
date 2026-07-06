# AI 11th-Edition Upgrade Plan

Status: **in progress** (this document is the working plan; each workstream lists
its acceptance evidence). Authored 2026-07-06 on branch
`claude/game-ai-11th-edition-dyik2h`.

## Why

The engine, data, phases, missions and scoring are fully 11th edition
(`GameConstants.edition == 11`, 40kdc launch dataset). The AI
(`AIPlayer.gd` + `AIDecisionMaker.gd`) was never migrated: it plays *legally*
under 11e but reasons with 10e heuristics, ignores the new mission cards,
ignores most stratagems, and its on-screen reasoning is terse. The three user
asks:

1. Make the AI a challenging 11e opponent (rules-correct, mission-aware).
2. Incorporate stratagems and faction rules useful to the shipped army lists.
3. Make the AI's thought process much more verbose in the left-hand Game Log
   panel — including options it considered and **rejected**, and why.

## Governing principle

**The AI must mirror the engine's implemented 11e behaviour, not the paper
rules.** Where the engine still resolves something 10e-style (e.g. BLAST
bonus attacks), the AI models the engine. Where the engine exposes a decision
window (available action or opportunity signal), the AI must handle it —
never fall through silently. Stratagems the engine treats as display-only
stubs (no `effects_json`, no custom handler — e.g. all Gladius Task Force
detachment stratagems) are **out of scope for AI use**: we do not invent
rules text the dataset deliberately omits.

## Current architecture (verified)

- `AIPlayer.gd` (autoload): drives turns via `_process` watchdog →
  `_execute_next_action` → `AIDecisionMaker.decide(phase, snapshot,
  available_actions, player, difficulty)` → `NetworkIntegration.route_action`.
  Reactive windows arrive as phase signals (`reactive_stratagem_opportunity`,
  `fire_overwatch_opportunity`, `heroic_intervention_opportunity`,
  `counter_offensive_opportunity`, `tank_shock_opportunity`,
  `rapid_ingress_opportunity`, `command_reroll_opportunity`,
  `epic_challenge_opportunity`, …) → `_on_*` handlers →
  `AIDecisionMaker.evaluate_*` → `_submit_reactive_action`.
- Thinking pipeline: `AIDecisionMaker._add_thinking_step()` →
  `result._ai_thinking_steps` → `AIPlayer._log_ai_thinking` →
  `GameEventLog.add_ai_thinking_entry` (renders in the **left GameLogPanel**,
  340 px card log with an AI filter toggle) + `ai_thinking_step` signal
  (renders in the bottom-right `AIActionLogOverlay`).
  **Reactive evaluators bypass `decide()`, so their reasoning never reaches
  the UI today.**
- Difficulty: Easy = random; Normal = default in the menu; stratagems
  currently gated to **Hard+** (`AIDifficultyConfig.use_stratagems`).

## Workstreams

### WS1 — 11e rules-correctness fixes in the AI brain

| # | Fix | Where |
|---|-----|-------|
| 1.1 | Engagement range is 2" at 11e. Charge "needed distance" math hardcodes `- 1.0`. Use `GameConstants.engagement_range_inches()`. | `AIPlayer.gd:1057,1115`, `AIDecisionMaker.gd:10674` |
| 1.2 | Deep-strike arrival is >8" at 11e (was 9"). Screening/denial constants assume 9"/18". Derive from edition. | `AIDecisionMaker.gd:451-452` (`DEEP_STRIKE_DENIAL_RANGE_PX`, `SCREEN_SPACING_PX`) + reinforcement placement margins |
| 1.3 | Benefit of cover at 11e = **−1 to the attacker's hit roll**, not +1 save. AI target scoring applies the 10e save bonus. Branch on edition. | `_score_shooting_target` (`AIDecisionMaker.gd:15762-15768`) |
| 1.4 | Fire Overwatch at 11e = SNAP shooting (unmodified 6s, one visible target within 24", no re-rolls). Align AI's overwatch EV + charge-time overwatch-risk estimate with the engine's snap implementation (incl. how TORRENT resolves). | `evaluate_fire_overwatch`, `_estimate_unit_overwatch_damage`, `_estimate_overwatch_risk` |
| 1.5 | Smokescreen id mismatch: the 11e window offers `smokescreen_11e`, the scorer matches only `"smokescreen"` → AI never smokescreens. Also stop scoring `go_to_ground` at 11e (retired). | `evaluate_reactive_stratagem`, `_score_defensive_stratagem_target` (`AIDecisionMaker.gd:16399-16424`) |
| 1.6 | Crushing Impact (11e Tank Shock successor) also allows **MONSTER**; expected value = T×⅓ MW to enemy (cap 6) minus T×⅙ MW to self. | `evaluate_tank_shock` (`AIDecisionMaker.gd:16524+`) |
| 1.7 | 11e charge flow: targets are selected **after** the 2D6 roll; unreachable pre-declared targets are dropped and `selectable_targets` may contain more. On `APPLY_CHARGE_MOVE`, re-pick the best target set from what the roll actually reaches. | `_decide_charge` step 2, `_compute_charge_move` |
| 1.8 | Fights-First awareness: chargers fight first at 11e; `counteroffensive_11e` grants FF. Fight-order planner should treat FF pools correctly (engine already restricts `SELECT_FIGHTER`; AI ordering must not assume it can save chargers for later). | `_build_fight_order_plan`, `_score_fighter_priority` |
| 1.9 | Fall Back modes (Ordered Retreat vs Desperate Escape): if the engine surfaces a mode choice to the mover, choose deliberately (Desperate Escape only when escaping is worth expected hazard casualties) and narrate. | `_decide_engaged_unit`, movement decider |

### WS2 — Mission play (the biggest challenge lever)

**2a. Seven new 11e secondary cards** (currently no-ops in
`_build_secondary_awareness` / `_evaluate_mission_achievability`), encoded
from their real definitions in `SecondaryMissionData.gd:489-645`:

- `a_grievous_blow` — kill-priority bias toward enemy units with Starting
  Strength ≥ 13 (like the old cull_the_horde arm).
- `forward_position` — 5 VP holding enemy home / expansion objective →
  strong movement bias to enemy home + NML objectives.
- `burden_of_trust` — 2 VP per guarded objective at end of *opponent's* turn
  → bias toward holding multiple objectives with units staying on them.
- `centre_ground` — 3/5 VP tiers around board centre (±3"/6" enemy
  exclusion) → centre push + clear enemies near centre.
- `beacon` — 3/5 VP for a unit outside own DZ / own territory at end of
  opponent's turn → push one durable unit forward.
- `outflank` — 3/5 VP for units within 6" of board edges outside own
  territory (5 VP needs opposite edges) → send cheap fast units wide.
- `plunder` — Shooting-phase action in a terrain area outside own territory
  → route an action-capable unit to qualifying terrain (reuses the existing
  `PERFORM_SECONDARY_ACTION` machinery).

Also: achievability scores for all seven (drives keep/discard/New-Orders
logic), and prune the dead 10e arms (`area_denial`,
`storm_hostile_objective`, `extend_battle_lines`, `cull_the_horde`,
`marked_for_death`) from the 11e path. Update
`docs/AI_SYSTEM_DOCUMENTATION.md`.

**2b. Primary-mission / Force-Disposition awareness (NEW).** The AI never
reads its primary card. Add `_build_primary_awareness(snapshot, player)`:

- Source: `MissionManager.player_primary_missions[player]` (card rules per
  `PrimaryMissionData11e` schema).
- Handle the generic rule types that dominate the 25 cards: `hold_min` (22),
  `per_objective` (11), `hold_more` (6), `hold_enemy_home` (6),
  `hold_central` (5), `destroyed_min`/`destroyed_per_unit` (6), `quarters`
  (2), `killed_more_than_opponent_last_turn` (2), `hold_new` (2),
  `hold_central_plus_nml`, `per_new_objective`. Marker/action mechanics
  auto-resolve in the engine already; unknown types → neutral + a thinking
  note.
- Feed biases into `_evaluate_all_objectives` (per-objective bonus when the
  card pays for it: enemy home, centre, "new" objectives), round urgency
  (rules with `rounds` windows), and aggression (kill-based cards).
- Narrate: "Primary (Take and Hold vs Purge): hold 2+ objectives scores 5 VP
  at my Command phase — currently holding 1 — weighting obj_center +4".

### WS3 — Stratagem breadth (core set + implemented faction sets)

**3a. Generic `USE_STRATAGEM` handling.** Phases already surface/accept
`USE_STRATAGEM` actions (CommandPhase even lists INSANE BRAVERY and GRAB AND
BASH), but no decider handles them → AI never uses any. Add a shared
evaluator that scores `USE_STRATAGEM` actions from `available_actions` and,
for proactive windows the phases don't enumerate, queries
`StratagemManager.get_proactive_stratagems_for_phase()` and dispatches
`USE_STRATAGEM` directly (phases process it; `can_use_stratagem` gates
validity).

**3b. Complete the 11e core set (10 stratagems).** Currently evaluated: fire
overwatch, smokescreen (broken id), counter-offensive, heroic intervention,
rapid ingress, command re-roll, grenade→explosives, tank-shock→crushing
impact. Add/fix:

- `insane_bravery` (once per battle): before taking a `BATTLE_SHOCK_TEST`,
  if the unit is critical (objective OC / points / late-round scoring
  pressure) and failure probability is high, use it. Window already surfaced.
- `epic_challenge`: replace the always-decline handler with an evaluation
  (our CHARACTER's melee with [PRECISION] can realistically kill an attached
  enemy CHARACTER).
- `heroic_intervention` 11e modes (`leap_to_defend` vs `into_the_fray`).
- CP costs read from `StratagemManager.stratagems` definitions instead of
  hardcoded literals.
- Simple CP budgeting: hold 1 CP entering the opponent's turn when reactive
  value is likely, unless spending now wins materially more — and narrate the
  tradeoff either way.

**3c. Implemented faction/detachment stratagems.** The shipped armies:

- **Orks — War Horde** (all six have real `effects_json` since #505):
  UNBRIDLED CARNAGE (crit 5+ melee — use on the biggest melee activation),
  'ARD AS NAILS (−1 wound-roll defence, reactive when a valuable ORKS unit is
  targeted), MOB RULE (unshock an INFANTRY unit near a 10+ MOB), 'ERE WE GO
  (+2 advance/charge before moving a key charger), CAREEN! + ORKS IS NEVER
  BEATEN (reactive windows where the engine offers them).
- **Adeptus Custodes — Shield Host** (all six real): AVENGE THE FALLEN
  (+1/+2 melee attacks when below strength), UNWAVERING SENTINELS (−1 hit
  melee defence on an objective), ARCHEOTECH MUNITIONS (lethal/sustained on a
  shooting unit), MULTIPOTENTIALITY (fall back + still shoot/charge),
  VIGILANCE ETERNAL (sticky objective before moving off), ARCANE GENETIC
  ALCHEMY (4+ FNP vs mortals — reactive window where offered).
- **Custodes — Lions of the Emperor** custom-implemented set (DEFIANT TO THE
  LAST, SWIFT AS THE EAGLE, UNLEASH THE LIONS) scored where their windows
  fire.
- **Space Marines — Gladius**: all stubs → AI notes "no implemented
  detachment stratagems" in thinking and uses core set only.

Reactive faction stratagems ('ARD AS NAILS, UNWAVERING SENTINELS, ORKS IS
NEVER BEATEN) already flow through `_get_faction_reactive_stratagems` into
the same `reactive_stratagem_opportunity` window the AI handles — extend the
scorer beyond the two hardcoded core ids to score by `effects_json`.

### WS4 — Faction ability decisions the AI currently ignores

CommandPhase surfaces these and `_decide_command` falls through to
`END_COMMAND` past all of them: `PLANT_WAAAGH_BANNER`, `USE_DA_KAPTIN`,
`USE_GROT_ORDERLY`, `USE_FIX_DAT_ARMOUR_UP`, `USE_PSYCHIC_VEIL`,
`USE_UNLEASH_THE_LIONS`. Add heuristics + narration for each (free/once-per
abilities default to "use when any meaningful benefit"). Audit other phases
for similarly ignored ability actions (Ka'tah stance selection in Fight
phase, etc.) and handle them. Keep existing Waaagh!/Oath/Doctrines/Martial
Mastery logic but narrate holds ("Holding Waaagh!: only 2/8 units within
22"").

### WS5 — Verbose thinking (the UI ask)

**Mechanism:**

- Reactive-path capture: evaluators append to the same `_thinking_steps`;
  new `AIDecisionMaker.take_thinking_steps()` lets every `AIPlayer`
  reactive handler flush reasoning to the log — so *declines* get explained
  ("Declined Fire Overwatch: snap shooting EV 0.4 wounds < 1.2 threshold").
- Auto-narration from decision records: `_add_decision_record` already
  captures scored candidate lists everywhere; generate thinking text from it
  centrally — chosen candidate + top rejected candidates with score deltas
  and reason fragments ("chose Boyz→obj_center 14.2; rejected obj_east 9.1 —
  enemy OC 8 vs our 4; rejected hold 6.0 — no targets in range").
- Fill narration gaps per phase: movement destination reasoning, shooting
  target choices incl. rejected targets, charge candidates with success
  probability + overwatch risk, fight target/order reasoning, command-phase
  ability/stratagem use-or-hold, scoring discard reasoning, stratagem CP
  tradeoffs.

**UI (left GameLogPanel):**

- Batch one decision's thinking into a single **collapsible card** (header =
  the decision headline, body = detail lines, reusing the combat-card
  collapse pattern) so verbosity doesn't flood the log; auto-expanded while
  the AI acts is not needed — details are one click away, and the headline
  carries the conclusion.
- New `GameEventLog.add_ai_thinking_block(player, header, lines)` + entry
  type; `AIPlayer` groups steps per decision. The bottom-right overlay keeps
  the existing line-based stream (short strings).
- Raise `MAX_CARDS` 200 → 300 and keep the AI filter toggle working.

### WS6 — Difficulty rebalance (challenging by default)

Default menu difficulty is **Normal**. Move core-stratagem consideration
(`use_stratagems`, `use_counter_offensive`, `use_survival_assessment`) down
to **Normal+**; keep multi-phase planning + screening at Hard+, trade/tempo
+ look-ahead at Competitive. Easy stays fully random. Update the difficulty
description strings so the menu reflects reality.

### WS7 — Validation (project gate)

- Headless: extend `tests/unit/test_ai_stratagem_evaluation.gd` +
  new tests for the new evaluators (insane-bravery EV, crushing-impact EV,
  epic-challenge, faction-stratagem scoring, secondary/primary awareness
  builders, 11e cover/ER math).
- Windowed scenario(s) under `tests/scenarios/sp/`: drive an AI turn
  end-to-end; assert the left GameLogPanel contains AI thinking cards
  including at least one *rejection/hold* line; assert an AI `USE_STRATAGEM`
  fires in a set-up state; screenshot the left panel showing the verbose
  thinking; `verify_delivery` PASS with no ERROR log lines.
- Prepend `40k/data/version_history.json` entry (minor bump — player-facing).

## Sequencing

1. WS5 mechanism first (thinking capture + auto-narration + UI card) — all
   later work narrates through it.
2. WS1 correctness fixes (small, isolated, testable).
3. WS3b core-set completion + id/CP fixes.
4. WS2 secondaries then primaries.
5. WS3a/3c faction stratagems + WS4 abilities.
6. WS6 difficulty defaults.
7. WS7 validation is continuous; final windowed scenario + screenshot gate
   before the last commit.

## Out of scope (recorded, not silently dropped)

- Inventing effects for stub stratagems (Gladius detachment, other factions'
  display-only rows) — engine/data work, not AI.
- Engine timing moves (e.g. Rapid Ingress window is emitted at end of
  opponent movement rather than 11e's start-of-shooting) — AI answers the
  windows the engine provides.
- Damaged/degrading vehicle profiles (dataset gap), per-unit BS variants of
  shared weapons (dataset gap).
- The seven-card windowed AI-vs-AI full-game benchmark (nice-to-have; the
  scenario gate above is the acceptance bar).
