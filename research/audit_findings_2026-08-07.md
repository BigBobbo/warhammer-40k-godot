# Expressiveness audit — first run, 2026-08-07

> **Status update, same day.** F-01 and F-02 are partially ACTED ON: 22 of the
> named coefficients were promoted to `get_param` with identical values, so the
> objective-assignment reachability penalty, charge-target and fight-target
> scoring are now inside the search space (104 → 126 parameters; unreachable
> scoring arithmetic 84% → 78%). Promotion is behaviour-preserving by
> construction — it changes *what a search can reach*, not what the AI does.
> Whether moving them helps is a question for the evaluator, not this audit.
> F-04…F-07 (the instrumentation gaps) are still open.

Run against 19 A/A games on `mirror_orks_postdeploy` at `ef5b389`
(2,502 movement decisions, 4 instrumented decision types).

The audit asks **"is this expressible?"**, never "was this good?". The second
question needs ~36 games per call and is the project's bottleneck; the first is
a coverage question about the search space, costs zero games, and is checkable
against `feature_census.py` and `params_manifest.py`.

Findings are typed into buckets. **Bucket 3 is the one nothing else in the
pipeline produces** — parameter search cannot find it by construction, because
it is search *within* the space.

| Bucket | Meaning | Route |
|---|---|---|
| 1 | tunable now — term exists, weighted wrong | parameter queue (M3/M4) |
| 2 | rule-expressible — needs conditional behaviour | DSL queue |
| 3 | **not expressible** — needs new code | feature backlog, human-reviewed |
| 0 | instrumentation gap — the audit is blind here | fix first, cheap |

Every finding states what was **verified mechanically** and what is
**hypothesis**. No finding here claims a VP improvement; nothing does until it
clears the paired evaluator.

---

## F-01 — The objective-assignment distance penalty is a hardcoded literal

**Bucket 3.** `AIDecisionMaker.gd:7519-7521`:

```gdscript
var turns_to_reach = max(1.0, ceil(dist_inches / move_inches)) if move_inches > 0 else 99.0
...
# Distance penalty: further away = less useful
if turns_to_reach > 1:
    score -= (turns_to_reach - 1) * 2.0
```

The AI **does** compute how many turns away an objective is. It then applies a
penalty whose coefficient is a bare `2.0` with no `get_param`, linear in turns,
and identical in round 5 and round 1.

**Verified:**
- The literal exists as quoted; no `get_param` on that line.
- `params_manifest.py` contains **zero** parameters governing objective
  reachability. The seven distance/range parameters concern shooting half-range,
  overwatch, deep-strike denial and a melee advance threshold — none of them this.
- Behaviour, across 19 games / 2,502 movement decisions: **49.6%** choose a
  destination both *farther away* and *lower-scoring* than an available
  alternative. Median chosen distance 35.9"; median distance of the better
  alternative 12.5". 1,090 of 1,241 chose a destination >24" away.
- The rate climbs monotonically with the round: 40.6% (r1) → 57.7% (r5).
- Of movement phases with ≥3 such picks, **46%** converge ≥60% of them on a
  *single* objective, mean distance ~47" — e.g. r3 P2 sent 7 of 10 units toward
  `obj_home_1` at a mean 49.7".

**Not verified — deliberately:**
- That this is *wrong*. Spreading units and making multi-turn pushes at an
  enemy home objective are both legitimate. 54% of those phases spread across
  objectives, which is coordination working as designed.
- That changing it improves VP. That requires the paired evaluator, not this audit.

**Why it is bucket 3:** even if tuning were the right fix, no profile can reach
a bare literal. This mechanism drives roughly half of all movement decisions and
is **completely invisible to M4's search.** A campaign could run its full
1,500–3,500 games and never touch it.

**Cheapest next step:** promote the coefficient to `get_param`, and make it a
function of rounds remaining rather than a constant — an objective eight turns
away in round 5 is worth zero, not "minus 14". One line for the promotion;
the round-awareness is a small change to the same expression.

---

## F-02 — 84% of the scoring arithmetic is unreachable by any profile

**Bucket 3, structural.** `tunability_audit.py` at `ef5b389`:

```
score arithmetic with a get_param coefficient  (TUNABLE) ... 46
score arithmetic with a bare numeric coefficient (NOT)  ... 243
==> 84% unreachable by ANY profile, rule, or optimiser, at any games budget
```

Concentrated in exactly the subsystems that decide the game:

| function | hardcoded coefficients |
|---|---|
| `_score_unit_for_reserves` | 18 |
| `_assign_units_to_objectives` | 18 |
| `_score_unit_for_embarkation` | 14 |
| `_score_disembark_benefit` | 14 |
| `_score_fight_target` | 12 |

This is the strongest available answer to "are we maximising locally?" — **yes,
and the local region is 16% of the coefficients.** It also reprices the roadmap:
promoting literals costs one line each and immediately enlarges the space the
optimiser searches, which is far cheaper than discovering after a 3,500-game
campaign that it was confined to a sixth of the machine.

The count **undercounts**: it only sees compound assignments onto score-like
identifiers, so magic numbers in helpers, thresholds and comparisons are invisible.

---

## F-03 — Shooting target selection may score on expected damage alone

**Bucket 0 first, then 3.** The recorded shooting score equals `expected_damage`
in 100% of candidates, and the census shows three shooting terms
(`expected_damage`, `kill_chance`, `target_hp`) — the latter two annotation.
Nothing about objective control, threat-to-us, or what the target does next.

**But this cannot be concluded from the record**, and saying so would be exactly
the failure mode this audit is designed to avoid: `_calculate_target_value`
(`:12457`) genuinely does weigh points cost, points-per-wound efficiency and
ranged/melee output. The *record* does not show whether that richer valuation
reached this decision.

**Resolve the instrumentation gap before ruling on this finding.**

---

## F-04..F-07 — Instrumentation gaps that blind the audit

**Bucket 0. These are cheap and they gate everything above.**

- **F-04 — shooting records the plan, not the alternatives.** `chosen_index` is
  hardcoded `0` (`:11808`) and the candidate list is the *assigned* targets, not
  the options weighed. So shooting "regret" is meaningless, and any
  alternatives-based analysis of shooting is invalid. The "hold fire to stay
  Hidden" branch also returns *before* its record is emitted (`:11783`), so the
  most interesting shooting decision class is entirely absent.
- **F-05 — no score decomposition.** Movement `score` == `objective_priority` in
  99% of candidates. The assignment rationale is recorded for 22 of 1,660
  movement candidates (`assigned_by`). So the mechanism behind ~half of all
  movement decisions is not in the data at all.
- **F-06 — `parameters_used` is not a guide to what is tunable.** The shooting
  record advertises `KILL_BONUS_MULTIPLIER`, which is a bare `const` with no
  `get_param` call. A search process reading records to pick targets would aim
  at a parameter no profile can move.
- **F-07 — `unit_oc` is context labelled as a criterion.** It is constant across
  every candidate of a movement decision, so it cannot have discriminated
  between them.

---

## What this run did not produce

No bucket-1 or bucket-2 findings strong enough to queue. The five attributable
parameters (`WEIGHT_CONTESTED_OBJ`, `WEIGHT_UNCONTROLLED_OBJ`,
`WEIGHT_VP_PER_POINT`, `OVERKILL_TOLERANCE`,
`TEMPO_CHARGE_THRESHOLD_REDUCTION`) are candidates for the M3 sensitivity
screen, but ranking them is that screen's job, not this audit's.

One candidate worth noting for the DSL queue: `STRATEGY_LATE_OBJECTIVE` *is*
`get_param`-reachable and `round_gte` *is* a valid rule condition, so
"prioritise objectives differently late" is rule-expressible today. It would
only be a partial fix for F-01, because the distance penalty it interacts with
still is not reachable.

---

## Correction to the earlier framing

I previously argued that an LLM's unique contribution is naming the *complement*
of a set — the considerations absent from the vocabulary — because no statistic
can do that.

That is still true for missing **concepts**, but F-01 and F-02 show a large and
more urgent class of "not expressible" is detectable **mechanically**, by grep,
with no model involved. `tunability_audit.py` finds it for free.

So the honest ordering is: run the cheap mechanical detectors first and exhaust
them, and reserve model-driven auditing for what genuinely survives — a
consideration the AI has no term for anywhere. Spending a model on rediscovering
hardcoded coefficients would be precisely the theatre the design document warns
about.
