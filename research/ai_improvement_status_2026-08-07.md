# AI improvement work: status report

Date: 2026-08-07. Branch: `claude/file-read-prompt-exec-7q5410`.

This document summarises an attempt to build an automated loop that improves
the game's AI from the games it plays, following the plan in
`research/ai_learning_framework_design.md`.

## Summary

The measurement infrastructure was built and verified. Three engine defects
were found and fixed. The search itself ran and **did not produce a change
worth shipping**: the best candidate measured +2.25 VP per game against a
required +4 VP, with a standard error of about 3.2, which is not
distinguishable from zero.

The most consequential finding was structural rather than numerical. The
single most influential tunable parameter in the AI was, until this work, a
hardcoded number that no configuration file could reach.

---

## What worked

### 1. Environment validation (M0)

`tools/ai_lab/fixture_check.py` validates a benchmark fixture before any
games are played on it. It detects the specific corruption that invalidated
every AI baseline before 2026-08-06: an army-list header row imported as a
unit, carrying `points: 2000` and `keywords: ["UNKNOWN"]`, which inflated one
army from 1,840 to 3,840 points and doubled the Strategic Reserves allowance.

The checker fails the corrupt fixture and passes both mirror fixtures. A
Custodes mirror was built so that a two-matchup grid is possible.

### 2. Data persistence (M1)

The AI already produced a full record of every decision — the options it
considered, the score it gave each, the option it chose, and the parameters it
used. All of it was discarded when the process exited, and the game's outcome
was written to a separate file that had no reference to it.

Each benchmark game now writes one `wh40k_ai_game_record` containing the
decisions, the outcome, per-award victory point events, and provenance
(fixture SHA-256, git commit, engine version, seed, and the full profile
inline). Records are written on every exit path, including stalled games,
which the previous export hook never covered.

Measured size: 485 KB raw, 49 KB compressed per game. A season directory is
converted to Parquet and DuckDB by `tools/ai_lab/build_index.py`, which
provides four views, including one joining every decision to the outcome of
the game it belonged to. That join did not previously exist.

### 3. Determinism (M2a)

The AI called the global, unseeded random number generator in 16 places.
Difficulty score noise is applied inside a movement-ordering sort comparator,
so the order in which units acted was itself random. Two games at the same
seed diverged at the fifth movement decision and finished as different games.

All 16 sites now draw from a seeded generator, and `Array.shuffle()` was
replaced with a deterministic Fisher-Yates shuffle for the same reason.

Verified across 10 seeds on both mirror fixtures: 5,109 action lines and 1,332
decision records identical between independent runs.

### 4. The evaluator (M2b)

`tools/ai_lab/run_paired.py` runs seed-paired, side-swapped arms:

    M1: baseline as P1, candidate as P2  →  F + E
    M2: candidate as P1, baseline as P2  →  F − E
    E = (M1 − M2) / 2   isolates the effect
    F = (M1 + M2) / 2   isolates the fixture's structural bias

Stopping is sequential and the rule is fixed before the run and recorded in
the campaign file, so the driver decides when to stop rather than a person
watching the numbers.

Verified by a null test: a candidate identical to the baseline returns
E = 0.00 with a standard error of 0.00, every paired seed producing identical
margins. That zero-variance case doubles as a detector for candidates that
pass validation but change nothing.

### 5. Structural baselines (M0, completed)

A/A runs on both mirrors, 40 games, establishing each fixture's structural
bias:

| fixture | F | se | 95% CI |
|---|---|---|---|
| `mirror_orks_postdeploy` | −7.11 | 2.65 | [−12.3, −1.9] |
| `mirror_custodes_postdeploy` | +2.16 | 3.04 | [−3.8, +8.1] |

The two fixtures do not share a bias and the Custodes one is not
distinguishable from zero. Cross-checked against the previous A/A arm on the
Ork mirror (−3.90, different commit): the difference is 0.58 standard errors,
so the instrument agrees with itself.

The Custodes mirror also resolves a full game in about 48 seconds against
about 487 seconds for the Ork mirror, because it fields 9 elite units a side
rather than a 16-unit horde. Screens and early search rounds are roughly ten
times cheaper there.

### 6. Engine defects found and fixed

**Charge-phase deadlock.** Three of forty benchmark games froze at round 5.
Root cause, from retained logs: a Heroic Intervention move that could not
reach engagement range. The AI submitted a move it had already determined fell
short; validation rejected it; the AI's recovery action also failed because
the unit had already acted; and that sub-state offered no other action. The
200-action escape then routed an action descriptor without a payload, which
can never validate. Fixed at three levels, including a new
`ABORT_HEROIC_INTERVENTION_MOVE` action, which matches 11th edition rule 15.11
(an intervention whose move cannot be made simply fails). Verified on the two
seeds that previously deadlocked, and by a windowed scenario (25 assertions).

**Dead rule context.** `_get_vp_diff` read `meta.player1_vp` and
`meta.player2_vp`, keys written by exactly one test and by nothing in a real
game. Victory point difference was therefore always zero, which silently
disabled five profile rule conditions: two could never fire and two fired
always. It now reads the real value.

**Timeout misreported as stall.** A game that exceeded its wall clock while
still progressing was recorded as stalled. Because stall rate is a guardrail,
this made the guardrail depend on machine load. Timeout is now a separate
status. This was discovered after oversubscribing the machine produced three
false stalls.

### 7. Expressiveness audit

`tools/ai_lab/tunability_audit.py` and `feature_census.py` measure the
boundary of what parameter search can reach:

- The AI's entire reported scoring vocabulary is **12 distinct terms** across
  four instrumented decision types.
- **84% of the scoring arithmetic** used bare numeric literals with no
  `get_param` call, and was therefore unreachable by any profile, rule or
  optimiser at any budget.
- Only 5 of 104 tunable parameters ever appeared in a decision record, so the
  rest could not be credited or blamed by any offline analysis.

The audit also identified the objective-assignment distance penalty — a
hardcoded `2.0`, linear in turns and identical in round 1 and round 5 — as the
mechanism behind a measured behaviour: **49.6% of 2,502 movement decisions
chose a destination both farther away and lower-scoring than an available
alternative**, rising from 40.6% in round 1 to 57.7% in round 5.

Twenty-two coefficients were then promoted to `get_param` at unchanged values.
This is behaviour-preserving; it changes only what a search can reach. The
tunable surface went from 104 to 126 parameters and unreachable arithmetic
from 84% to 78%.

### 8. Sensitivity screen (M3)

336 games, 208 minutes, Custodes mirror, ±30% one at a time.

| parameter | default | max abs E | note |
|---|---|---|---|
| `MOVE_REACHABLE_BONUS` | 3 | 9.25 | reducing it scored −9.25 |
| `WEIGHT_OC_EFFICIENCY` | 2 | 5.88 | both directions positive; noisy |
| `WEIGHT_UNCONTROLLED_OBJ` | 10 | 5.38 | reducing it scored −5.38 |
| `MOVE_TURNS_AWAY_PENALTY` | 2 | 3.62 | increasing it scored +3.63 |
| `MOVE_UNREACHABLE_EARLY_PENALTY` | 2 | 2.75 | |

Five parameters move the margin by at least 2 VP, which under the design
document's own criterion selects cross-entropy search over coordinate descent.

**Three of those five were hardcoded literals that morning**, including the
highest-influence parameter in the entire screen. A search run the previous
day would have spent its whole budget without being able to touch them.

Thirteen of the twenty-one tested changed no decision at all at ±30%,
including every charge, fight and shooting coefficient in the set. This does
not prove they are unread: a parameter can be read and still never change
which option scores highest.

### 9. Regression protection

25 windowed scenarios covering the modified systems, 799 assertions, zero
failures. A per-scenario timeout was added to the batch runner, which
previously had none, making a slow scenario indistinguishable from a hung one.

---

## What did not work

### The search did not find a shippable change

The cross-entropy campaign ran 264 games over three generations on six
parameters.

| generation | best so far | population range |
|---|---|---|
| 1 | +2.13 | −5.94 to +2.12 |
| 2 | +2.13 | −13.00 to −0.25 |
| 3 | +2.25 | −1.00 to +3.00 |

Best candidate: **E = +2.25 VP per game, standard error about 3.2**, giving a
confidence interval of roughly [−4.0, +8.5]. The pre-registered stopping rule
never reached "accept". The required threshold is +4 VP at two standard
errors.

Two considerations argue the true effect is smaller than +2.25:

1. It is the maximum over roughly 24 noisy evaluations, so it is biased upward
   by selection.
2. The resulting parameter changes are small (−24% to +5%), which is the
   pattern of a search moving within noise rather than following a gradient.

Generation 2 turning entirely negative and generation 3 returning to
generation 1's level is consistent with the same reading.

### Common random numbers helped less than expected

Seeding the AI makes an *identical* candidate reproduce exactly, which is what
makes the no-op detector free. But any candidate that changes one decision
reshuffles every subsequent dice draw, so the paired spread stays wide.
Observed standard errors were 1.3 to 5 VP at four to five pairs.

### A bug in the measurement tooling

`run_paired.margins_by_seed` keyed only on arm and seed. Multiple campaigns
share a season directory and all label their arms M1 and M2, so evaluation *N*
pooled the games of evaluations 1 to *N*−1 into its own estimate. The first
result was correct and every subsequent one was contaminated, with no visible
symptom.

This was found by inspecting the running screen's own season directory. The
first screen run was discarded and repeated. Fixed on two independent axes
(filtering by candidate, and one directory per evaluation) with a regression
test.

---

## What is still running

The two-mirror gate on the best candidate: 8 paired seeds per mirror, both
mirrors, with a concurrent A/A arm as a harness check. An earlier attempt was
lost when the container suspended; it has been restarted.

The informative question is not whether it passes — at +2.25 ± 3.2 it cannot
clear +4 at two standard errors — but whether the effect transfers to the Ork
mirror at all. A fixture-local effect and a real one are indistinguishable on
a single fixture.

---

## What remains to be done

1. **Widen the instrumentation** (audit findings F-03 to F-07). Shooting
   records the assigned plan rather than the alternatives considered, and its
   `chosen_index` is hardcoded to 0. Movement's recorded score is a copy of
   one term rather than a decomposition, so the mechanism behind roughly
   two-thirds of decisions is absent from the data. Until this is fixed,
   offline analysis of those decisions is not possible.

2. **Promote more coefficients.** 78% of scoring arithmetic is still
   unreachable, concentrated in reserves scoring (18 literals), embarkation
   (14), disembarkation (14) and fight target selection (12). Given that three
   of the five parameters that mattered came from the first promotion pass,
   this is the highest-value remaining lever.

3. **Run the search at its intended budget.** The design document specifies
   1,500 to 3,500 games per matchup for the M4 stage. This campaign used 264,
   about a tenth, on one fixture.

4. **Screen the Ork mirror.** Every charge and fight coefficient registered as
   inert on the 9-unit Custodes mirror. The 16-unit Ork horde is where melee
   decisions are frequent, and they may matter there.

5. **Rule search and LLM-proposed rules** (design document stage M5). Not
   started.

---

## What was skipped, and why

- **The windowed scenario suite in the gate.** Gate 3 records as NOT RUN,
  which blocks shipping by design. It was skipped for this candidate because
  the candidate is a data profile that scenarios do not load, and the code at
  this commit already passed 25 scenarios and 799 assertions. It would not be
  defensible to skip for a code change.

- **The full 478-scenario suite.** 25 scenarios covering the modified systems
  were run instead. The full suite takes several hours at roughly 2 to 3
  minutes per scenario.

- **Counterfactual replay** (design document RQ3). Determinism now makes it
  feasible at one rollout per branch, but it was not built.

- **Shipping a tuned profile.** No candidate met the acceptance criteria, so
  there is nothing to ship. The only player-facing change in this work is the
  charge-phase deadlock fix, released as version 1.28.7.

---

## Assessment

The design document's falsifiable success metric is: within one 30-day season
and 12,000 games, the automated cycle produces a change beating the default by
at least +4 VP per game across both mirrors at two standard errors.

That metric is **not yet answered**. This work used roughly 1,500 games in one
day and a search budget about a tenth of the specified size. The correct
conclusion is that this campaign, at this budget, found nothing shippable —
not that weight tuning is falsified.

The stronger signal points elsewhere. The screen's most influential parameter
was unreachable by any search until it was promoted, and 78% of the scoring
arithmetic remains in that state. On the current evidence, making more of the
AI reachable is likely to be worth more than searching harder over the part
that already is.
