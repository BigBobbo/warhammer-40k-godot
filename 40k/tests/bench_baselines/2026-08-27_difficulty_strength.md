# Do the harder AI configurations actually play better? (2026-08-27)

The question had never been measured: the benchmark harness could only run
**same-tier** games (`PlanSimulator` applied one `difficulty` value to both
seats), so "is Hard actually better than Normal?" was unanswerable by
construction. Adding `difficulty1`/`difficulty2` (defaulting to `difficulty`,
so every existing caller is unchanged) made it measurable.

Testbed: custodes_lions mirror, hammer_anvil / take_and_hold_mirror_1 /
take_and_hold, no plans, 6 shared seeds (5001–5006), both seat orders so the
board's ≈ +10 VP P1 seat bias cancels. Zero stalls or timeouts throughout.

## Method check — can this design detect a strength gap at all?

Easy(P1) vs Competitive(P2), seed 5001: **P1 15 – 86 P2**. The same seed at
equal configuration is 37–57. A 71-point swing on one seed confirms both that
per-seat difficulty binds (`AIPlayer.get_difficulty` read back 0 / 3 mid-game)
and that the measurement resolves real differences.

## Normal vs Competitive

| Arm | Margin (P1 − P2) | Games |
|---|---|---|
| Normal (P1) vs Competitive (P2) | −8.3 ± 30.9 | 3–3 |
| Competitive (P1) vs Normal (P2) | +40.2 ± 27.6 | 5–1 |

Per-seed margins — arm A: [−53, −37, +43, +2, +5, −10]; arm B: [+53, +41,
+58, −10, +23, +76].

**Seat-cancelled: Competitive is ≈ +24 VP/game stronger than Normal, winning
8 of 12 games.** This is the largest AI-strength effect measured this week —
larger than the layout-tuned Ork plan's ≈ +21 — and it lands well outside the
board's seat bias.

The result corrects a standing assumption in
`2026-08-27_next_steps.md`: after that session's parameter nulls, the working
hypothesis was that this mirror's flat optima might make the tier ladder
cosmetic. It is not. The features that separate the tiers — zero score noise,
multi-phase (movement → shooting → charge) planning, keener charge thresholds,
trade analysis, deep-strike screening — compound into a decisive advantage
even though single-parameter nudges measured null. **Structure beats
knob-turning**, consistent with everything else measured this week.

## Hard vs Competitive — is Competitive the peak?

| Arm | Margin (P1 − P2) | Games |
|---|---|---|
| Hard (P1) vs Competitive (P2) | TBD | TBD |
| Competitive (P1) vs Hard (P2) | TBD | TBD |

## Consequence for the product

The owner's direction is a single, always-best AI rather than a ladder of
tiers. Given the measurement, the way to deliver that is **not** to remove the
tier gating (that would flatten a ladder which demonstrably works) but to
**default every game to the strongest configuration**. The v1.39.0 gate wiring
that reserved screening for Hard+ and trade analysis for Competitive is
therefore load-bearing, not a regression — provided the default sits at the
top.

Caveat for future benchmarking: every baseline before this date was recorded
at Normal. Comparisons across reports must match difficulty explicitly; the
per-game and per-run summaries now carry `difficulty_p1` / `difficulty_p2` so
this can be checked rather than assumed.

Scope: one army mirror, one board, 6 seeds per arm. The effect is large enough
to survive that sample, but per-army confirmation is worthwhile before treating
+24 VP as a general constant.
