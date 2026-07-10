# AI Decision-Making Review — July 2026

A critical, phase-by-phase review of how the AI opponent decides what to do,
where it is genuinely strong, where it is weak, what was improved in this
pass, and a roadmap. Companion docs: `AI_SYSTEM_DOCUMENTATION.md` (how each
algorithm works), `AI_TUNING.md` (every editable parameter).

---

## 1. Executive summary

The AI is **not** a simple "measure distances, pick the closest option"
system. It is a layered heuristic engine (~19,500 lines in
`AIDecisionMaker.gd`) with genuine army-level coordination in several places:

- an army-wide **focus-fire plan** in the shooting phase (weapon × target
  marginal-value allocation across every shooter at once),
- a per-turn **multi-phase plan** built at the start of movement (which units
  intend to charge what, which enemy shooters to lock in melee, which
  shooting lanes to preserve) that movement, shooting and charge all consult,
- **charge gang-up** and **fight-phase cumulative-damage** coordination,
- mission awareness (its own primary/secondary cards change objective values),
  army-archetype detection, round-based strategy pivots, VP-tempo desperation,
  and faction personalities.

The weakest coordination link *was* the movement phase itself — the phase the
review was asked to start with. Units move one at a time, and the whole
objective assignment was recomputed from live positions before every single
move, so a unit ordered toward an objective two turns away was invisible to
every later unit ("that objective still needs OC!"), producing pile-ups and
abandoned flanks. Two other defects compounded it (a shared phase-plan cache
between the two players, and log-flooding re-narration). All three are fixed
in this pass — see §4.

On the LLM question: **a per-action LLM backend is the wrong tool; a
turn-level "strategist" LLM is a plausible optional experiment** — see §6.

Manual editing already has deep hooks (91 tunable weights, per-player
profiles, a conditional-rule DSL); what was missing was a shipped, documented
entry point — now `40k/data/ai_config.json` + `docs/AI_TUNING.md`.

---

## 2. Architecture recap (context for the review)

- `AIPlayer.gd` (autoload) — frame-paced controller. One action per
  evaluation tick; failure fallbacks per action type; reactive windows
  (overwatch, rerolls, counter-offensive…); difficulty plumbing; logging.
- `AIDecisionMaker.gd` — pure static decision engine.
  `decide(phase, snapshot, available_actions, player, difficulty)` returns
  one action dict, with `_ai_description`, `_ai_thinking_steps`,
  `_ai_decision_records` attached for the UI/log.
- `AIAbilityAnalyzer.gd` — reads unit abilities into offensive/defensive
  multipliers. `AIDifficultyConfig.gd` — Easy/Normal/Hard/Competitive gates.

An important structural consequence of "one action per call, recompute from a
fresh snapshot": the AI is extremely robust to failures and rule interactions
(the engine is always the source of truth), but any *plan* must be carried in
static caches between calls — and anything not cached is re-derived, which is
where coordination gaps come from.

---

## 3. Phase-by-phase review

### 3.1 Deployment (incl. formations, reserves, transports)

**How it decides.** Leader↔bodyguard attachments are scored on ability
synergy ("while leading" buffs, bodyguard protection). Transport embarkation
scores cargo value vs delivery need. Reserves declarations score units for
deep strike / strategic reserves (mobility, fragility, board pressure). Each
deploying unit is classified into a role (`_classify_deployment_role`) and
placed via terrain-aware scoring — cover for shooters, forward screens,
counter-deployment that reacts to what the enemy has already put down
(`_apply_counter_deployment`, Normal+).

**Strengths.** Role classification + counter-deployment is a solid
foundation; terrain scoring avoids the classic "castle in the open" failure.

**Weaknesses.**
- Deployment is *reactive per unit*; there is no explicit whole-army
  deployment plan ("refuse the left flank", "castle center") that later units
  deliberately complete. Each unit optimizes its own placement given what is
  already down.
- Deployment scoring constants are nearly all hard-coded (not in the
  `get_param` system), so personalities can't reshape deployment yet.

### 3.2 Command phase

**How it decides.** A long prioritized chain: battle-shock management first
(Insane Bravery evaluation vs 2d6 failure odds), then faction
once-per-battle abilities with explicit timing rules (WAAAGH! — round 2+
always, round 1 if any unit is in threat range; Waaagh! banner; doctrine /
Oath of Moment / Martial Ka'tah target selection scored on expected value),
then proactive stratagems. Primary/secondary "awareness" for the round is
built here (what the cards actually pay VP for) and cached per player.

**Strengths.** Once-per-game resources have deliberate, *narrated* timing
heuristics ("use-it-or-lose-it" logic beats hoarding). Mission awareness
built here is what makes movement mission-driven rather than geometric.

**Weaknesses.** The chain is first-match-wins rather than scored against
each other; CP budgeting across the whole turn (e.g. "save 1 CP for
overwatch on their turn") is implicit at best.

### 3.3 Movement phase — the deep dive

**How it actually decides (correcting the "distance to things" model).**
Per `decide()` call:

1. **Multi-phase plan** (once per phase, Hard+): flag melee units whose
   move+12" reach makes a worthwhile charge (`charge_intent`), list dangerous
   enemy shooters worth locking in melee (`lock_targets`), record shooting
   lanes for ranged units.
2. **Threat map** (Normal+): per enemy unit, charge-threat radius
   (M+12"+ER), shooting-threat radius, unit value.
3. **Objective evaluation**: each objective gets a priority from its control
   state (uncontrolled / contested / enemy-weak / enemy-strong / held-safe /
   held-threatened), round urgency (rush R1, contest R2, consolidate R3,
   push R4-5), VP tempo (desperation when behind), denial and retention
   bonuses, and — dominantly — **expected VP at the next scoring point from
   the player's actual mission cards**.
4. **Unit→objective assignment**: all (unit × objective) pairs scored — OC
   efficiency vs need, distance in turns, reachability, keeping/losing/gaining
   firing positions, threat increase, charge-lane alignment, secondary-mission
   positional bonuses (quarters, enemy zone, center, kill proximity). Greedy
   allocation: units already on objectives that still need them hold; then
   best pairs fill remaining OC needs; leftovers become deep-strike screens,
   corridor blockers, or support.
5. **Execution for the chosen unit** (priority: engaged units, then
   disembarked → normal → transports, front-to-back): Advance when assigned
   or when melee-seeking needs the reach (respecting advance-and-charge
   flags), Remain Stationary for Heavy bonus / firing positions / Lone
   Operative safety / threat avoidance, Fall Back with survival assessment,
   otherwise a terrain-aware, collision-resolved move toward the blended
   target (objective ⊕ charge target ⊕ half-range position ⊕ firing
   position), with per-model destinations.

So "distance to units and objectives" is one term among roughly a dozen. The
*real* gaps were about **what other units are doing**, which is exactly what
the user suspected:

**Diagnosed defects (all fixed in this pass, §4):**

1. **No memory of en-route intentions.** The assignment recomputed OC needs
   from live positions before every move. A unit dispatched toward obj_3 but
   still 8" short contributed nothing to obj_3's books, so the next unit was
   *also* sent to obj_3. Manifestation: redundant stacking on the nearest
   "needy" objective, starved far objectives.
2. **Shared phase-plan cache between players.** `_phase_plan_built` was a
   single bool keyed only by round — in AI-vs-AI (or any second AI turn in
   the same battle round) the second player saw "already built" and played
   with **no charge intents, no lock targets, no shooting lanes** every
   round.
3. **Log flooding instead of clarity.** Every decide() call re-recorded and
   re-narrated *every* unit's assignment (N units ⇒ ~N² thinking lines per
   phase), which buried the actual reasoning.

**Remaining weaknesses (roadmap, §7):** movement order is heuristic rather
than dependency-aware (a screening unit may move before the unit it
screens); no explicit "escort/deliver" pairing between transports and
cargo beyond delivery targets; melee-aggression distance limits are
hard-coded rather than parameters.

### 3.4 Shooting phase

**How it decides.** Army-wide **focus-fire plan** built once per phase: kill
thresholds per enemy, macro target values (threat output, points, OC on
objectives, ability value, survivability discount, tempo), a weapon×target
expected-damage matrix (LoS-checked, keyword-aware: Rapid Fire, Melta, Anti-X,
Blast, cover, half-range), then iterative marginal-value assignment with
overkill decay — i.e. weapons are allocated where they add the most *marginal*
value, kills are consolidated, spillover redirected. Grenades and proactive
stratagems evaluated per phase; charge targets are deliberately under-shot
(`PHASE_PLAN_DONT_SHOOT_CHARGE_TARGET`) so the charge still has something to
lock.

**Strengths.** This is the most sophisticated phase — genuine cross-unit
optimization, weapon-role matching, and it narrates chosen vs rejected
targets. **Weaknesses.** The matrix is expensive (rebuilt if the phase plan
is invalidated); no explicit "reserve overwatch shooters" concept; splitting
a unit's weapons across targets is possible but model-level split fire is
coarse.

### 3.5 Charge phase

**How it decides.** For each eligible charger: score each target — expected
melee damage (weapon-by-weapon math incl. WAAAGH! buffs), target value, OC
flips on objectives, lock-the-shooter bonus from the phase plan, overwatch
risk estimate, charge success probability from 2d6 distance (terrain
penalty-adjusted), multi-target combos scored, and **gang-up coordination**
(targets already charged this phase get a pile-on bonus with cumulative
expected damage). Declares, then computes the post-roll charge move with
base-to-base placement, engagement-range legality and collision resolution;
command reroll evaluated on failed rolls.

**Strengths.** Probability-weighted scoring with overwatch risk is the right
frame; gang-up + lock-shooters is real coordination. **Weaknesses.**
Heroic-intervention risk of the *enemy* isn't modeled; charge order (which
charger declares first to open lanes) is not optimized.

### 3.6 Fight phase

**How it decides.** A **fight-order plan** ranks all eligible fighters
(kill-before-being-killed, interrupt value); per fighter, targets are scored
(expected damage vs value, objective context) with **cumulative-damage
coordination** so later fighters finish wounded targets instead of spreading;
pile-in and consolidate have engagement-vs-objective modes (consolidate onto
objectives when the combat is decided).

**Strengths.** Activation-order planning + damage pooling is exactly what a
good player does. **Weaknesses.** No "hold back a fighter to counter-punch
after the enemy interrupts"; consolidate mode choice is heuristic.

### 3.7 Scoring / secondaries

**How it decides.** Per-card achievability assessments (a dedicated
`_assess_*` for each 11e secondary: Behind Enemy Lines, Engage on All
Fronts, Area Denial, Assassination, Bring It Down, Cull the Horde, Storm
Hostile Objective, …) drive both discard/keep decisions and the positional
bonuses fed back into movement. Action-based secondaries (burn, ritual,
terraform) are evaluated as explicit actions with shooting-value tradeoffs.

**Strengths.** Card-aware VP math flowing into movement is rare even in
commercial 40k AI attempts. **Weaknesses.** No multi-turn secondary plan
("keep this card because round 4 me can score it").

### 3.8 Reactive windows (both turns)

Overwatch (expected damage vs 1CP), reactive defensive stratagems
(Go-to-Ground/Smokescreen scored on incoming threat), counter-offensive,
heroic intervention, rapid ingress, command rerolls (charge/advance/
battle-shock with explicit odds math), tank shock, epic challenge, Ka'tah
stances. All difficulty-gated, all narrated via `take_thinking_steps()`.

---

## 4. What was improved in this pass (movement coordination)

Implemented in `AIDecisionMaker.gd` / `AIPlayer.gd` (tags `COORD-1..3`):

1. **Per-player phase plans (COORD-1).** `_phase_plan` / `_phase_plan_built`
   are now keyed by player. The second AI player in a round now builds its
   own charge intents / lock targets / shooting lanes instead of silently
   playing plan-less (accessors `_get_phase_plan`, `_is_charge_target`,
   `_get_charge_intent` resolve per acting player).

2. **Movement intent ledger — "what are my other units doing?" (COORD-2).**
   Every finalized movement decision records an intent
   `{action, objective_id, dest, oc, unit_name}` for that player's phase
   (funnel: `_finalize_movement_decision`). The objective assignment now
   computes **incoming OC** — units that already took their move and are en
   route to an objective (but not yet in control range) count toward its OC
   need, with double-count protection for units already inside control
   range, staleness protection (intents of units that failed to execute are
   cleared by `AIPlayer` via `clear_movement_intent`), and redirect
   narration: *"obj_3 is already covered (Boyz en route) — redirecting to
   obj_4."* Result: later units reinforce genuinely needy objectives instead
   of stacking the same one.

3. **Once-per-phase army battle plan in the game log (COORD-3).** At the
   first movement decision of the phase, the AI logs the whole army's plan —
   one line per unit: role (HOLD / MOVE / ADVANCE / SCREEN), objective,
   distance, and why — plus engaged-unit notes and threat-zone count, as its
   own dedicated log card. Each unit's detailed decision card (chosen option
   + top rejected alternatives with scores, board-linked so hovering draws
   the options) is now emitted **once, at the moment that unit acts**,
   instead of re-narrating every unit's assignment on every action (which
   flooded the log with near-duplicate blocks and drowned the signal).

4. **Collateral fixes found while validating:**
   - Reactive-window reasoning blocks (command reroll, overwatch, …) no
     longer swallow the *previous* decision's thinking lines — the step
     buffer is cleared once handed off (`decide()` tail).
   - Profile rules with a `phase` condition fired in the wrong phase (stale
     literal phase map: "MOVEMENT" matched the Scout phase). Now mapped from
     the real enum.
   - `MovementPhase` Bomb Squigs / Scatter eligibility crashed with a script
     error (`GameState.PIXELS_PER_INCH` doesn't exist → `Measurement.PX_PER_INCH`).
   - "AI plays a turn" windowed scenarios were flaky: the secondary-mission
     deck shuffle used an unseeded RNG, so the AI could randomly draw a
     requires-interaction card (A Tempting Target) and pause forever behind
     a human-only dialog. The deck RNG now honours the scenario's
     `rng_seed` (`SecondaryMissionManager.set_test_seed`).
   - **AI-vs-AI fight-phase deadlock** (found by the benchmark): AIPlayer's
     fight-phase acting-player override only ran when the ACTIVE player was
     human, so with two AIs the active AI kept submitting the other player's
     12.07 `END_CONSOLIDATION` ("Not your half") until the phase action cap
     hit and the game froze. The override now applies whenever the selecting
     player is an AI, and `_get_fight_phase_selecting_player` prefers the
     global pile-in/consolidate step's half-owner (the phase's
     `current_selecting_player` goes stale when a 12.08 forced fight
     interrupts the step). Benchmark seed 1001 at Hard: stalled round 4
     before, completes all 5 rounds after.

Verification: windowed scenario `40k/tests/scenarios/sp/ai_coordinated_movement.json`
drives a live AI movement phase and asserts the battle-plan block, per-unit
reasoning and coordination entries appear in the in-game log; the AI-vs-AI
benchmark harness (`bash 40k/tests/run_ai_benchmark.sh`) exists for win-rate
regression on tuning changes.

---

## 5. Where AI thinking appears (verbosity guarantee)

Every decision path accumulates thinking steps that land in:

1. **The in-game game log** (left panel) — `ai_thinking` lines and
   collapsible `ai_thinking_block` cards; block cards with positional
   candidates draw chosen (green) vs rejected (red) options on the board on
   hover. This is the primary surface and now carries: the phase battle
   plan, per-unit chosen/rejected scoring, coordination redirects, VP-stake
   summaries, and every reactive-window rationale.
2. The transient bottom-right **AI action overlay** while the AI plays.
3. **stdout + the debug log file** (`user://logs/debug_*.log`) — every
   thinking line is mirrored via `DebugLogger`, so post-game analysis works
   even without the UI.
4. The **JSON decision export** (`user://ai_decision_log.json`, F10 or auto
   at game end) with full score breakdowns per candidate — consumed by the
   AI Gameplay Visualizer web app.

---

## 6. Should the backend be a cheap LLM?

**Recommendation: not for per-action decisions; optionally yes as a
turn-level strategist — but only as an experiment behind a flag.**

The numbers: the AI takes roughly 50–200 engine actions per turn (every
model stage, save allocation, reroll window…). Even a fast hosted model at
~1–3 s and ~$0.001–0.01 per call would make a turn take minutes and a game
cost dollars, versus milliseconds and free today. Determinism (seeded
replays, the benchmark harness, scenario tests), offline play, and rules
legality all get worse — an LLM can *suggest* an illegal move, so the
engine-side validation and fallback machinery must stay regardless.

Where an LLM **would** add value cheaply:

- **Strategist layer (once per battle round, not per action):** feed it a
  compact game-state summary (VP, cards, objective states, army health) and
  let it choose among *existing* strategy presets / parameter deltas — the
  profile+rules system added for manual tuning is exactly the actuation
  surface it would need (`load_player_profile` / rule overrides). Bounded
  cost (~5 calls/game), zero legality risk (it only nudges weights), and
  fully optional/offline-safe (fall back to current heuristics).
- **Color commentary:** rewriting the (now verbose) thinking log into
  in-character narration. Cosmetic, cacheable, safe.

What an LLM would *not* fix: the geometric sub-problems (charge lanes,
coherency placement, threat maps) where the current specialized code is
already better than a language model would be. If deeper play strength is
the goal, the higher-leverage classical step is bounded look-ahead /
1-ply simulation of the opponent's reply using the existing damage
estimators (already stubbed as `use_look_ahead` at Competitive).

**Bottom line:** keep the heuristic engine as the source of truth. If
desired later, add the round-level LLM strategist as an opt-in experiment —
the plumbing now exists; it degrades gracefully to current behavior.

---

## 7. Roadmap (highest value next)

1. **Movement order by dependency** — move blockers/screens before the units
   they protect; move objective-critical units first, opportunists last.
2. **Escort pairing** — transports + cargo and character+bodyguard treated as
   one planning entity through movement/charge.
3. **Parameterize the remaining hard-coded tactics** (melee-aggression
   distance ladders, horde thresholds, deployment scoring) via `get_param`
   so profiles can reshape them — see `AI_TUNING.md` §"not yet a parameter".
4. **1-ply look-ahead at Competitive** — score the opponent's best reply to
   the top-2 candidate moves using the existing damage estimators.
5. **CP budget planning** — reserve CP for known reactive windows based on
   opponent threats.
6. **Deployment master plan** — pick a whole-army posture first (castle,
   refused flank, spread) and score placements against it.
7. Optional: the round-level LLM strategist experiment (§6).
