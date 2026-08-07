# Scoring-horizon model — measured and REJECTED, 2026-08-07

**Question:** the AI's objective scoring has no concept of the game ending. Does
giving it one make it win more?

**Answer: no. It makes it clearly worse — E = -4.29 VP/game, 95% CI [-7.43, -1.15].**

## The defect being addressed

`_assign_units_to_objectives` computes `turns_to_reach` and uses it only in a
small linear penalty — a couple of points against objective priorities of
20-100. Nothing compares it to the rounds remaining. Primary VP is awarded in
the command phases of rounds 2-5, so an objective a unit cannot stand on before
the last command phase can never be scored by it. Yet in round 5 an objective
eight turns away still outscored one the unit was standing on.

Measured consequences, before any change:

- 57% of movement decisions targeted an objective 24 inches or more away, and
  24% targeted 40+, against unit moves of 5-12 inches in a five-round game
  (803 decisions over 6 games).
- 49.6% of movement decisions chose a destination both farther away AND
  lower-scoring than an available alternative, rising from 40.6% in round 1 to
  57.7% in round 5, across 19 games.

## The change tested

An objective's value scaled with the scoring opportunities remaining after
arrival, collapsing to a floor past the horizon:

    arrival_round   = battle_round + turns_to_reach - 1
    scoring_chances = max(0, 5 - arrival_round)
    score          *= max(scoring_chances / total_chances, MOVE_UNREACHABLE_FLOOR)

## Design

Paired, side-swapped, common random numbers, on `mirror_custodes_postdeploy` at
Hard. `E = (M1 - M2) / 2`. Stopping rule fixed in advance at |E| >= 4 VP and
2 standard errors.

| seed | M1 | M2 | E |
|---|---|---|---|
| 81001 | 9.0 | 11.0 | -1.00 |
| 81002 | -2.0 | 13.0 | -7.50 |
| 81003 | 20.0 | 29.0 | -4.50 |
| 81004 | 2.0 | 9.0 | -3.50 |
| 81005 | -3.0 | -7.0 | +2.00 |
| 81006 | 11.0 | 9.0 | +1.00 |
| 81007 | 19.0 | 24.0 | -2.50 |
| 81008 | -2.0 | 10.0 | -6.00 |
| 81009 | -7.0 | -3.0 | -2.00 |
| 81010 | 5.0 | 20.0 | -7.50 |
| 81011 | 4.0 | 6.0 | -1.00 |
| 81012 | -21.0 | 17.0 | -19.00 |

**E = -4.29 VP/game, se 1.60, 95% CI [-7.43, -1.15]** over 12 pairs / 24 games.

**F = +7.21** (se 2.68), consistent with the A/A arm's +2.16 (se 3.04)
at 1.25 standard errors — so the instrument had not moved.

Sequential looks: -4.12 at 4 pairs, -2.75 at 8, -4.29 at 12, then REJECT. The
sign never changed and the interval never included zero.

## Reading

The defect is real; the remedy was wrong. Marching at a distant objective is not
purely wasted — the unit contests, screens and threatens on the way, and passes
near other objectives. Suppressing that pulls the army into a huddle and cedes
the board.

**Declining to walk somewhere is not the same as choosing something better to do
instead**, and this change only did the former. It removed a behaviour without
supplying a replacement.

Variants worth testing against this baseline: a gentler `MOVE_UNREACHABLE_FLOOR`,
or redirecting the freed movement into an explicit alternative — screening,
board control, threat projection — rather than only lowering a number.

## Note on the harness

This is the first result in the project to clear the pre-registered bar in
either direction, and it took 48 games. It also caught a piece of reasoning that
was confident, evidence-backed and wrong, which is the entire reason for
building the evaluator before the optimiser.
