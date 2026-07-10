# First-turn-swap experiment — 2026-07-10

**Question:** how much of the Custodes (P1) sweep in the 2026-07-10 baseline is
first-turn advantage vs AI skill / matchup?

**Method:** `audit_baseline_postdeploy_p2first` — byte-identical board to the
baseline fixture except P2 (Orks) takes the first turn. Same seeds 2001–2010,
both difficulties, same code as the baseline's post-fix state. 20/20 games
completed, zero stalls.

**Measurement caveat:** seeds fix the dice stream and secondary-deck order,
but the AI's frame-paced action loop interleaves with wall-clock timing, so
full game trajectories are not seed-reproducible under different CPU load.
Compare aggregates, not per-seed pairs.

## Results (avg VP diff, P2 − P1)

| Lane | Baseline (P1 first) | Swapped (P2 first) | First-turn effect |
|---|---|---|---|
| Normal | −28.2 ¹ | **−19.0** | ≈ +9 VP |
| Hard | −28.3 ¹ | **−9.4** | ≈ +19 VP |

¹ 10-seed averages including the post-fix re-runs of the previously stalled
seeds (2007, 2010, 2003).

Swapped-lane outcomes: Normal 10× P1 wins (closest −5); Hard 8× P1 wins,
**1 draw (seed 2003, 39–39), 1 P2 win (seed 2005, 42–29)** — the first
non-P1 results in 40 games of benchmarking.

Per-game (swapped fixture):

| seed | Normal (P1/P2) | diff | Hard (P1/P2) | diff |
|---|---|---|---|---|
| 2001 | 38/10 | −28 | 26/10 | −16 |
| 2002 | 41/18 | −23 | 40/26 | −14 |
| 2003 | 43/34 | −9 | 39/39 | **0** |
| 2004 | 54/24 | −30 | 36/26 | −10 |
| 2005 | 42/26 | −16 | 29/42 | **+13** |
| 2006 | 38/24 | −14 | 38/24 | −14 |
| 2007 | 52/35 | −17 | 45/39 | −6 |
| 2008 | 55/24 | −31 | 45/24 | −21 |
| 2009 | 34/29 | −5 | 49/37 | −12 |
| 2010 | 51/34 | −17 | 38/24 | −14 |

## Interpretation

1. **First-turn advantage is real and large at Hard (~19 VP)** — going first
   lets the Orks reach midboard objectives before the Custodes shooting
   phase, and at Hard the multi-phase planning capitalizes on it. It explains
   roughly two-thirds of the Hard gap.
2. **It does not explain the whole gap**: Orks going first at Hard still lose
   by ~9 on average, and at Normal by ~19. The residual matches the
   post-mortem finding (see companion report `2026-07-10_ork_loss_postmortem`
   section in the A/B report): the Ork army survives but chases instead of
   scoring — primary VP ≈ 6 per game vs P1's 21–36.
3. Both sides' absolute VP drop when P2 goes first (P1 loses a scoring turn
   tempo too) — margins, not totals, are the comparable quantity.
