# AI Dossier — The Decision Loop & What the Player Can Observe

*Sources: `40k/autoloads/AIPlayer.gd` (the loop), `40k/scripts/AIDecisionMaker.gd` (the brain), `40k/scripts/AIDifficultyConfig.gd` (difficulty knobs), `40k/data/ai_config.json` (tuning overrides). All line numbers verified against the working tree on 2026-08-27.*

## Overview

The AI opponent is not a background process that "plays a turn" in one go — it is a metronome. Every game frame, an autoload called `AIPlayer` checks whether it owes the game a decision; when it does, it waits a short, configurable delay (so a human can watch), asks the static rule-brain `AIDecisionMaker.decide()` for exactly **one** action, submits that action through the same pipeline a human click would use, and then re-arms itself for the next tick. Every decision follows the same universal shape: list the legal candidates, give each one a numeric score built from named weight terms, pick the highest, and record the whole comparison — chosen option, rejected options, scores, and which tuning parameters were touched. That record is what the player sees: the pulsing "AI is thinking..." banner, the "Thinking about Movement Phase..." cards in the game log with rejected options and their scores, and a full JSON decision log exportable with F10. A 2000-point game produces roughly 350–750 of these logged actions (measured medians: 390 for a 9-unit elite army mirror, 684 for a 16-unit horde mirror). Because a submitted action can be rejected by the rules engine, the loop carries an elaborate safety net: per-action-type retry/skip fallbacks, a 2-second watchdog that force-restarts a stalled loop, a "gate stall" monitor that shouts after 20 seconds of waiting on a human and tries to re-open lost dialogs after 45, and a hard cap of 200 consecutive no-progress attempts per phase that triggers a tiered escape (end the phase → decline the blocker → any valid action → force phase advance). Nothing in `40k/data/ai_config.json` currently changes any scoring weight — its only entry, `PLANS_ENABLED: 1`, matches the code default, so every number in this dossier is the live, effective value.

## Decision flow

The loop, in the order the code executes it:

1. **Frame tick / pacing** — `AIPlayer._process()` runs every frame (`AIPlayer.gd:187-209`). If an evaluation is pending, it counts down `_eval_timer` and then calls `_evaluate_and_act()`. The timer is set by `_request_evaluation()` (`AIPlayer.gd:211-215`) to the effective action delay:
   - Human-vs-AI: the AI-speed preset — Fast 0.05 s, Normal 0.2 s (default), Slow 0.5 s, Step-by-step = pause for a Continue press (`AIPlayer.gd:64-78`).
   - AI-vs-AI spectator mode: **0.5 s** base (`SPECTATOR_ACTION_DELAY`, `AIPlayer.gd:87`) divided by a speed multiplier the viewer can cycle (0.25×, 0.5×, 1×, 2×, 4×; default 1× — `AIPlayer.gd:88-89`), floored at 0.05 s so the renderer/MCP bridge stay responsive (`MIN_ACTION_DELAY`, `AIPlayer.gd:65`, applied at `AIPlayer.gd:2826-2832`).

2. **Watchdog** — if the AI *should* be acting but no evaluation is scheduled, `_process` accumulates idle time and after **2.0 s** (`WATCHDOG_TIMEOUT`, `AIPlayer.gd:47`) forces a fresh evaluation (`AIPlayer.gd:191-198`). This is the backstop for any missed signal.

3. **"Thinking" starts** — the first evaluation of a sequence flips `_ai_thinking = true` and emits `ai_turn_started` (`AIPlayer.gd:223-236`), which shows the centered, gold-bordered, pulsing "AI is thinking..." banner with animated dots (`Main.gd:1907-2019`). In Step-by-step mode the banner instead shows a Continue button (`Main.gd:1950-1962`).

4. **Gate checks** — `_evaluate_and_act()` (`AIPlayer.gd:1745-1922`) runs a series of "is it actually my move?" gates before doing anything: re-entrancy guard (1751), roll-off suppressed while a human is present (1756), fight-phase selecting-player override (1771-1775), human owns the current fight-phase step (1785-1790), human defender owes saves/reactive decisions (1796-1801), human owes a reactive window like Heroic Intervention/Overwatch (1813-1819), human owes a secondary-mission pick (1856-1860). Every human gate calls `_note_gate_block()` and idles — the AI never decides *for* a human.

5. **Ask the brain** — `_execute_next_action()` (`AIPlayer.gd:1924-2127`) takes a game-state snapshot, gets the legal action list from `PhaseManager.get_available_actions()` (1930), filters out units that have permanently failed deployment/reinforcement/embarkation (1933-1956), logs one "Thinking about <Phase> Phase... (move x5, hold x3, ...)" card per phase per round (1969-1986), and calls `AIDecisionMaker.decide(phase, snapshot, available, player, difficulty)` (1989).

6. **decide() dispatch** — `AIDecisionMaker.decide()` (`AIDecisionMaker.gd:2965-3162`) sets the current player/difficulty, evaluates profile rules if a per-player profile is loaded (2972-3030), clears the per-decision thinking/record buffers (3031-3034), short-circuits to fully random choices on Easy (3047-3048), resets phase-scoped plan caches when the phase/round changes (3050-3108), then dispatches on phase to one of twelve `_decide_*` handlers — formations, deployment, redeployment, scout, roll-off, first-turn roll-off, command, movement, shooting, charge, fight, scoring (3114-3139). Unknown phases fall back to any `END_*` action (3140-3146).

7. **The universal decision shape** — inside every handler: enumerate candidates, score each with named additive terms (`_t_add` / `_t_mul` keep the invariant *sum(terms) == score*, `AIDecisionMaker.gd:1635-1644`), sort, pick `chosen_index`, and emit a **decision record** via `_record_choice`/`_add_decision_record` (`AIDecisionMaker.gd:1602-1683`). Each record carries `decision_type`, `unit_id`, `candidates[]` (each with `description`, `score`, `score_breakdown`), `chosen_index`, `parameters_used` — auto-captured as *exactly* the tunable parameters resolved through `get_param()` during that decision (`AIDecisionMaker.gd:1212-1233`, 1651-1677) — plus `difficulty` and `context` (including `options_considered`). `_narrate_decision_record` (`AIDecisionMaker.gd:1726-1745`) turns the record into log text: "*UnitName [decision_type]: chose X (score 12.3)*", up to three "*✗ rejected: Y (score 8.1)*" lines, and "*… and N other options scored lower*". Records, thinking steps, and a board-highlight context ride back on the decision dict as `_ai_decision_records` / `_ai_thinking_steps` / `_ai_thinking_context` (3148-3155).

8. **Publish the reasoning** — back in AIPlayer (2036-2094): a single thinking step logs as a plain line; multiple steps become a collapsible "Thinking: <description>" block in the game log; a once-per-phase "Movement plan" gets its own card (2041-2054). The routing (`AIPlayer.gd:3359-3399`) sends every line to the GameEventLog panel, the bottom-right overlay stream (`ai_thinking_step` signal), stdout, and the debug log file. Decision-record batches accumulate for the F10 export and auto-refresh `user://ai_decision_log.json` every 50 batches (2062-2084; export format at 3734-3847; F10 keybind at 183-185). A retained-batch cap of 500 (100 on web) drops oldest first (`AIPlayer.gd:3730`).

9. **Submit & verify** — the decision goes through `NetworkIntegration.route_action()` (2127), the exact pipeline a human's click uses, so the rules engine validates it. Success → clear failure counters, handle multi-step follow-ups (movement staging, scout moves, deferred advance rolls, 2382-2420). Failure → a per-action-type recovery (see Safety nets). Each successful phase action fires `phase_action_taken`, which **resets the 200-action safety counter and schedules the next tick** (`AIPlayer.gd:860-873`) — that is the heartbeat that keeps the loop running.

10. **Reactive interruptions** — during the *human's* turn, phase signals (fire overwatch windows, heroic intervention, command re-roll, counter-offensive, tank shock, etc., connected at `AIPlayer.gd:879-1018`) call evaluators directly; the answers are submitted deferred via `_submit_reactive_action` (`AIPlayer.gd:1686-1741`) and are logged into the same action log and thinking-card system (`_flush_reactive_thinking`, 3391-3399).

11. **End of thinking / turn summary** — when a phase change or "no actions" ends the sequence, `_end_ai_thinking()` (`AIPlayer.gd:242-254`) hides the banner, emits `ai_turn_ended` with just that sequence's actions, and stores them in the turn history that feeds the AI Turn Replay panel (793-828, `Main.gd:2025-2028`). Game over → the decision log is auto-exported once (`AIPlayer.gd:1843-1849`).

12. **On-demand hint** — a human can ask "what would the AI do here?": `request_suggestion()` (`AIPlayer.gd:724-789`) runs the identical `decide()` pipeline in preview mode (planning caches snapshotted and restored, `AIDecisionMaker.gd:3178-3182`), executes nothing, and posts a "Suggestion (<Phase>): ..." reasoning card to the game log — never at Easy, which has no reasoning to show (769-770).

## Scoring tables

All values below are the code defaults **and** the effective values: `40k/data/ai_config.json` overrides nothing except `PLANS_ENABLED = 1` (`ai_config.json:16-18`), which equals the code default (`AIDecisionMaker.gd:421` — `get_param("PLANS_ENABLED", 1.0)`), so plans are on and every weight runs at its built-in default. Override layering, when used, is: rule overrides > per-player profile > `user://ai_config.json` > `res://data/ai_config.json` > code constant (`AIDecisionMaker.gd:295-322`, `1235-1275`).

### Pacing — how fast the AI visibly acts

| Term | Default value | Plain-English meaning |
|---|---|---|
| `AI_SPEED_DELAYS[FAST]` | 0.05 s | Fastest preset — one AI action every 50 ms (`AIPlayer.gd:67`) |
| `AI_SPEED_DELAYS[NORMAL]` | 0.2 s | Default vs-human pacing (`AIPlayer.gd:68`) |
| `AI_SPEED_DELAYS[SLOW]` | 0.5 s | Slow preset (`AIPlayer.gd:69`) |
| `AI_SPEED_DELAYS[STEP_BY_STEP]` | 0.0 s (manual) | Pauses before every action; Continue button/Space advances (`AIPlayer.gd:70`, `2789-2801`) |
| `SPECTATOR_ACTION_DELAY` | 0.5 s | Base delay between actions when both players are AI (`AIPlayer.gd:87`) |
| `SPECTATOR_SPEED_PRESETS` | 0.25×–4× (default 1×) | Viewer-cycled divisor of the 0.5 s spectator delay (`AIPlayer.gd:88-89`) |
| `MIN_ACTION_DELAY` | 0.05 s | Absolute floor so the renderer & MCP bridge keep breathing (`AIPlayer.gd:65`) |

### Safety net thresholds

| Term | Default value | Plain-English meaning |
|---|---|---|
| `WATCHDOG_TIMEOUT` | 2.0 s | Idle time before a stalled loop is force-restarted (`AIPlayer.gd:47`) |
| `MAX_ACTIONS_PER_PHASE` | 200 | Consecutive *no-progress* attempts before the tiered escape fires; reset on every successful action (`AIPlayer.gd:37`, `860-873`) |
| `GATE_WARN_SEC` | 20 s | Waiting on one human gate this long → loud warning in the logs (`AIPlayer.gd:59`) |
| `GATE_RECOVER_SEC` | 45 s | Per-attempt interval to re-open a lost decision dialog (`AIPlayer.gd:60`) |
| `GATE_MAX_RECOVERIES` | 5 | Recovery attempts before giving up (still logging loudly) (`AIPlayer.gd:61`) |
| `SELECT_FIGHTER` retry cap | 3 | Consecutive rejected fighter picks before escalating to END_FIGHT (`AIPlayer.gd:42`, `2146-2167`) |

### Per-difficulty scoring knobs (from `AIDifficultyConfig.gd`)

| Term | Easy | Normal | Hard | Competitive | Meaning |
|---|---|---|---|---|---|
| `get_score_noise` | 100.0 | 1.5 | 0.5 | 0.0 | Random ± added to scores; formula `score + (randf()−0.5)×noise×2` = ±noise (`AIDifficultyConfig.gd:72-83`, applied `AIDecisionMaker.gd:2071-2077`) |
| `get_movement_iterations` | 1 | 3 | 5 | 8 | Candidate positions tried when optimizing a move (`AIDifficultyConfig.gd:86-97`) |
| `get_charge_threshold_modifier` | 2.0 | 1.0 | 0.85 | 0.7 | Multiplier on the score a charge must beat — lower = charges more (`AIDifficultyConfig.gd:105-116`) |

Noise is injected at the ranking comparisons: movement activation order (`AIDecisionMaker.gd:6985-6986`), charge-target scores (15086, 15415), and fight-order scores (17236). All AI-layer randomness flows through one RNG that can be seeded for reproducible benchmark games and is `randomize()`d in normal play (`AIDecisionMaker.gd:1549-1575`).

### Record/log retention (what survives to be observed)

| Term | Default value | Meaning |
|---|---|---|
| `_max_action_log_entries` | 2000 (300 web) | Whole-game action log cap, oldest dropped (`AIPlayer.gd:26`) |
| `_max_turn_history_entries` | 200 (30 web) | Turn-replay panel history cap (`AIPlayer.gd:27`) |
| `_max_decision_record_batches` | 500 (100 web) | Full scoring-breakdown batches kept for export (`AIPlayer.gd:3730`) |
| auto-export interval | every 50 batches | `user://ai_decision_log.json` refreshed mid-game (`AIPlayer.gd:2083-2084`) |

### Sample of the movement objective weights that flow into the loop's most common decision

(One line per unit per Movement phase — the single biggest source of scored decisions. Full weight catalog belongs to the movement dossier; these are cited here because they appear in the worked example.)

| Term | Default (= effective) value | Meaning |
|---|---|---|
| `WEIGHT_UNCONTROLLED_OBJ` | 10.0 | Pull toward an objective nobody holds (`AIDecisionMaker.gd:1813`) |
| `WEIGHT_CONTESTED_OBJ` | 8.0 | Pull toward an objective both sides touch (1814) |
| `WEIGHT_ENEMY_WEAK_OBJ` | 7.0 | Pull toward an enemy-held objective we can flip (1815) |
| `WEIGHT_HOME_UNDEFENDED` | 9.0 | Pull back to an abandoned home objective (1816) |
| `WEIGHT_ENEMY_STRONG_OBJ` | −5.0 | Push away from an objective the enemy holds in force (1817) |
| `WEIGHT_ALREADY_HELD_OBJ` | −3.0 | Mild push off objectives we already hold (1818) |
| `WEIGHT_VP_PER_POINT` | 1.2 | Per expected VP the objective yields at the next scoring point (1812) |

## Worked example

*Invented but realistic — the numbers use the real default weights above and the real Normal-difficulty noise band.*

Round 2, Normal difficulty, the AI's Movement phase. Boyz (20 models, OC 40) must pick a destination. The brain enumerates three objective candidates and scores each with named terms:

| Candidate | Term contributions (score_breakdown) | Raw score | ±1.5 noise | Final |
|---|---|---|---|---|
| **Objective C (uncontrolled, mid-board)** | uncontrolled +10.0, expected 5 VP × 1.2 = +6.0 | 16.0 | +0.7 | **16.7** ← chosen |
| Objective B (contested) | contested +8.0, expected 3 VP × 1.2 = +3.6 | 11.6 | −0.4 | 11.2 |
| Objective A (own, already held) | already-held −3.0, expected 4 VP × 1.2 = +4.8 | 1.8 | +1.1 | 2.9 |

The handler picks `chosen_index = 0`, computes per-model destinations toward Objective C, and returns `{type: "BEGIN_NORMAL_MOVE", actor_unit_id: "boyz_1", _ai_model_destinations: {...}, _ai_description: "Boyz move toward Objective C", _ai_thinking_steps: [...], _ai_decision_records: [...]}`. The attached record stores all three candidates with their `score_breakdown` dicts, `parameters_used: {"WEIGHT_UNCONTROLLED_OBJ": 10.0, "WEIGHT_VP_PER_POINT": 1.2, ...}` (exactly the knobs `get_param` resolved), and `context.options_considered: 3`.

What the player sees in the game log:

> **Thinking: Boyz move toward Objective C**
> Boyz [movement_destination]: chose Objective C (score 16.7)
>   ✗ rejected: Objective B — contested (score 11.2)
>   ✗ rejected: Objective A — already held (score 2.9)

AIPlayer submits `BEGIN_NORMAL_MOVE` through `route_action`; on success it stages each model's destination and confirms the move (`AIPlayer.gd:2409-2416`, `2424-2532` — the staging sub-actions are *not* separate log entries). Had staging failed, it would retry at 75 % / 50 % / 25 % of the move distance and finally fall back to `REMAIN_STATIONARY` (`AIPlayer.gd:2459-2532`). One log entry, one visible token move, ~0.2 s later the loop ticks again.

## Rough decisions-per-game census

"Actions" here = entries in `AIPlayer._action_log` — one per decision submitted by the main loop (`AIPlayer.gd:2088-2093`) or a reactive window (`AIPlayer.gd:1699-1704`); this is exactly the `actions_taken` figure the benchmark harness reports (`AIBenchmarkRunner.gd:521`).

**Measured totals** (AI-vs-AI benchmark games, 5 rounds, both players combined):
- 9-unit-per-side elite mirror (Custodes): **median 390 actions** per game; 16-unit-per-side horde mirror (Orks): **median 684** (`40k/tests/bench_baselines/2026-08-07_mirror_AA_both.md:66-69` — "roughly half the decisions" for the elite army).
- Individual games observed from ~205 up to **826** actions (a full 2000-pt game that included the deployment phase logged 826 actions with 103 deployments — `2026-08-08_deployment_phase_coverage.md:81`; stalled games froze at 444–733 — `2026-08-07_mirror_AA_both.md:52-54`).

**What those actions are** (composition derived from the per-phase handlers' emitted action types; approximate shares for a ~17-unit-per-side 2000-pt game):

| Phase | Logged actions per player-turn | What they are (action types from the handlers) |
|---|---|---|
| Formations + Deployment (once per game) | ~15–50 per player | One `DEPLOY_UNIT` per unit, `PLACE_IN_RESERVES`, leader attachments, transport embarks (`_decide_formations` 3984, `_decide_deployment` 4709) |
| Command | ~2–8 | Battle-shock tests, doctrine/oath/Waaagh! picks, secondary discard/replace, `END_COMMAND` (`_decide_command` 5908) |
| Movement | ~1 per unit + extras | One `BEGIN_NORMAL_MOVE`/`BEGIN_ADVANCE`/`BEGIN_FALL_BACK`/`REMAIN_STATIONARY` per unit, disembarks, reinforcement placements, `END_MOVEMENT` (`_decide_movement` 6524; per-model staging is not logged separately) |
| Shooting | ~1 per shooting unit | `SHOOT` or `SKIP_UNIT` per unit, occasional `USE_GRENADE_STRATAGEM`, `END_SHOOTING` (`_decide_shooting` 13035) |
| Charge | 1 per non-charger, 3+ per charger | `SKIP_CHARGE`, or `DECLARE_CHARGE` → `CHARGE_ROLL` → charge move/`COMPLETE_UNIT_CHARGE` (`_decide_charge` 14759) |
| Fight | 3–5 per engaged unit | `SELECT_FIGHTER`, `PILE_IN`, `ASSIGN_ATTACKS`, `APPLY_MELEE_SAVES`, `CONSOLIDATE`, plus `END_PILE_IN`/`END_CONSOLIDATION`/`END_FIGHT` steps (`_decide_fight` 16595) — the densest phase per unit involved |
| Scoring | ~1–3 | Score primary/secondary, `END_SCORING` (`_decide_scoring` 18525) |
| Reactive (any time) | dozens per game | Overwatch, command re-roll, heroic intervention, reactive stratagem USE/DECLINE answers (`AIPlayer.gd:1032-1560`) |

Ten player-turns of ~30–60 actions each, plus deployment and reactives, is what lands games in the ~350–750 band; horde armies with heavy melee (many fight-phase activations at 3–5 actions each) sit at the top of it.

## Difficulty gates

From `AIDifficultyConfig.gd` (all static; Easy=0, Normal=1, Hard=2, Competitive=3):

| Capability | Easy | Normal | Hard | Competitive | Source |
|---|---|---|---|---|---|
| Random valid actions instead of scoring | ✅ | — | — | — | `:23-24` |
| Stratagems (reactive + proactive) | — | ✅ | ✅ | ✅ | `:29-30` |
| Focus-fire coordination | — | ✅ | ✅ | ✅ | `:37-38` |
| Threat-range awareness | — | ✅ | ✅ | ✅ | `:41-42` |
| Weapon-target efficiency matching | — | ✅ | ✅ | ✅ | `:53-54` |
| Survival assessment / fall-backs | — | ✅ | ✅ | ✅ | `:59-60` |
| Counter-deployment | — | ✅ | ✅ | ✅ | `:67-68` |
| Command Re-roll used optimally | — | ✅ | ✅ | ✅ | `:100-101` |
| Fire Overwatch / Counter-offensive | — | ✅ | ✅ | ✅ | `:119-124` |
| Multi-phase planning (move→shoot→charge) | — | — | ✅ | ✅ | `:33-34` (enforced at `AIDecisionMaker.gd:3110-3112`) |
| Screening / deep-strike denial | — | — | ✅ | ✅ | `:63-64` |
| Trade/tempo analysis | — | — | — | ✅ | `:45-46` |
| Look-ahead planning | — | — | — | ✅ | `:49-50` |

Loop-relevant Easy behavior: `_decide_random` (`AIDecisionMaker.gd:3272-3400`) still handles all mechanical sequencing deterministically (saves, dice, confirms), still uses *normal* logic for deployment, formations, scout, roll-offs, command, scoring, and fight sequencing, always **declines** every stratagem/reactive window (3350-3372), and randomizes only movement/shooting/charge picks. Easy's noise value of 100 (drowning any real score) is the belt-and-braces on top of that. The on-demand hint feature silently upgrades Easy to Normal so there is reasoning to show (`AIPlayer.gd:769-770`). Difficulty is per-player, default Normal (`AIPlayer.gd:293-294`, `597-599`).

## Evidence

**Loop & pacing** — `40k/autoloads/AIPlayer.gd:187-209` (_process, watchdog); `:211-236` (_request_evaluation, thinking start); `:64-89` (speed presets, spectator 0.5 s, multipliers, 0.05 s floor); `:2826-2832` (effective delay); `:2763-2825` (speed/spectator controls).
**Turn sequencing & gates** — `AIPlayer.gd:1745-1922` (_evaluate_and_act with all gates); `:359-490` (who-acts resolution incl. fight-phase halves); `:508-565` (reactive/defender windows); `:830-873` (phase-changed / action-taken → counter reset + next tick).
**Decision execution & retry** — `AIPlayer.gd:1924-2127` (_execute_next_action: filter, decide, log, submit); `:2129-2381` (per-action-type failure fallbacks: SELECT_FIGHTER retry×3→END_FIGHT 2146-2167, charge→SKIP/ABORT 2176-2197, pile-in empty-retry→SKIP 2200-2242, consolidate 2245-2266, fight→SKIP_UNIT 2271-2293, shoot→SKIP_UNIT 2296-2319, move→REMAIN_STATIONARY 2331-2347, HI→DECLINE 2361-2368, default re-evaluate 2380-2381); `:2424-2532` (movement staging + 75/50/25 % recompute + Desperate Escape + stationary fallback).
**Safety nets** — `AIPlayer.gd:36-61` (caps & gate constants); `:1865-1915` (200-action tiered escape: END_* → DECLINE/SKIP → ABORT → any valid → force phase advance); `:1991-2022` (empty-decision decline guard); `:2905-2996` (gate stall watch, dialog re-emission recovery); `:3469-3733` (deployment/reinforcement retry ladders).
**Universal decision shape** — `40k/scripts/AIDecisionMaker.gd:2965-3162` (decide dispatch); `:1602-1683` (_record_choice/_add_decision_record: candidates, chosen_index, score_breakdown, auto parameters_used); `:1212-1233` (+`:1227-1233`) (param-read capture); `:1635-1644` (_t_add/_t_mul additive ledger); `:1726-1745` (chosen + "✗ rejected" narration); `:1688-1721` (board-highlight context); `:2058-2069` (thinking steps); `:2071-2077` (noise formula); `:1549-1575` (single seedable AI RNG).
**Config & tuning** — `AIDecisionMaker.gd:295-322` (config layering), `:1235-1275` (get_param priority); `40k/data/ai_config.json:16-18` (only PLANS_ENABLED=1; default already 1.0 at `AIDecisionMaker.gd:419-421` → no effective change); movement weights `AIDecisionMaker.gd:1812-1818`.
**Difficulty** — `40k/scripts/AIDifficultyConfig.gd:23-124` (gates), `:72-83` (noise), `:86-97` (iterations), `:105-116` (charge threshold); Easy path `AIDecisionMaker.gd:3047-3048`, `3272-3400`; Normal-skip of multi-phase planning `:3110-3112`.
**Player-visible surfaces** — `40k/scripts/Main.gd:1907-2019` (thinking banner + Continue button + pulse/dots); `AIPlayer.gd:1968-1986` ("Thinking about X Phase..." once per phase/round); `:2036-2059` (collapsible thinking blocks; Movement-plan card); `:3353-3399` (routing to GameEventLog, overlay, stdout, debug file); `:2087-2094` (action log + ai_action_taken); `:724-789` (hint/suggestion preview); `:793-828` (turn history / replay panel), `Main.gd:2025-2028`; `:3283-3345` (post-game performance summary); F10 export `AIPlayer.gd:180-185`, `3734-3847`; auto-export every 50 batches `:2083-2084`, caps `:26-27`, `:3730`.
**Census evidence** — `40k/autoloads/AIBenchmarkRunner.gd:521` (actions = _action_log.size()); `40k/tests/bench_baselines/2026-08-07_mirror_AA_both.md:52-54, 66-69` (medians 390/684; stalls at 444–733); `2026-08-08_deployment_phase_coverage.md:81` (826 actions incl. deployment); per-phase action types from `AIDecisionMaker.gd` handler bodies at `:3984, 4709, 5908, 6524, 13035, 14759, 16595, 18525`.
