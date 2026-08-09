# First full Ork-mirror games after the large-army bundle — 2026-08-09

Code: branch `claude/ai-large-unit-performance-1g0zha` (commits `b7816bd`,
`2f4b2bc`, `9ed9e6e`), shipped defaults (bundle ON). Machine: the 4-core lab
container, runs SHARED with 1-2 concurrent godot instances, so the wall
clocks below are upper bounds, not clean per-game numbers. Single games, not
seasons — the A/A and paired campaigns are the next step, these rows are the
"is it usable at all" gate the fixture failed before.

| fixture | seed | status | rounds | actions | wall s | VP (P1/P2) |
|---|---|---|---|---|---|---|
| `mirror_orks_2000_postdeploy` | 7001 | **completed** | 5 | 733 | 705 | 70 / 79 |
| `mirror_orks_2000_preformations` | 7003 | **completed** | 5 | 586 | 274 | — / winner P2 (+8) |

Reference for the first row: before this bundle the same fixture was
**UNUSABLE** — two probes were still inside battle round 1 after 22 and 14
minutes (`40k/tests/exams/slow/README.md`), because one boxed-in unit walked
a ~78-rung fallback ladder inside a single decision. It now finishes all
five rounds with plausible mirror scores, with every boxed-in unit bounded:

    Warbikers Delta: MOVE_SEARCH_BUDGET exhausted before relaxed 0.70x
    (20032 candidates); holding this round
    Stompa: STUCK_EARLY_EXIT — no model placeable at any strict fraction
    (work=2352); holding this round
    Gretchin Alpha: PARTIAL_MOVE — 10 models move, 1 hold position
    skipping search — marked stuck in round N   (x6, the per-round memo)

The second row is the new full-loop fixture: a LIVE Formations phase
(`--preformations`), then the AI deploys all 154 models itself. In it the AI
embarked Gretchin Alpha+Beta into each Stompa (22/22 capacity), declared 26%
of points into reserves (11e cap: 50%), deployed largest-base-first inside
the real zone polygons, brought reserves on from round 2, and disembarked
the Gretchin in round 3 when space opened. Formations + deployment for both
armies took under 30 seconds of the 274.

Exam suite at this commit: **10/10 PASS in 295 s**, including
`dp01_deployment_is_recorded` (on the new deployment code) and
`sc01_reserves_under_the_cap` (rewritten: live formations fixture, int-enum
status test, phase-ran assertion — the old exam could not fail).

Zero `SCRIPT ERROR` lines in either game log.

## What these rows do NOT claim

- No strength claim: the paired A/B (defaults vs
  `bench_profiles/large_army_moves_off.json`) needs its campaign; a stuck
  unit that holds instead of squeezing through at 0.5x radius is a
  behaviour change and its VP cost is unmeasured until then.
- No variance claim: one seed per fixture. The A/A season (10 seeds) that
  replaces the "UNUSABLE" row in `2026-08-08_2000pt_fixture_AA.md` is still
  to be run, after which the Ork mirror belongs back in
  `gate_candidate.MIRRORS` and `slow/sc02` can be un-parked.
- The postdeploy fixture's 0.07" packing remains a fixture defect to
  rebuild (~0.5-1" gaps); these runs prove robustness under it, not that it
  is a sensible board.

## Addendum — Custodes arm smoke, same seed (5001), sequential runs

| arm | status | rounds | actions | wall s | vp_diff (P2−P1) |
|---|---|---|---|---|---|
| OFF profile (`large_army_moves_off`, both players) | completed | 5 | 561 | 167 | −4 |
| shipped defaults (bundle ON) | completed | 5 | 514 | 141 | +13 |

Both profiles verified loaded ("Loaded profile for P" ×2). One seed — this
row validates the A/B instrument (both arms healthy, comparable shape), not
strength. On this healthy board the ON arm fired ZERO budget/stuck/partial
events: the mechanisms engage only under congestion, by construction. The
paired campaign (`bench_data/campaign_large_army_bundle`, seeds 9100+) is
the strength measurement.

## Addendum 2 — paired A/B, Custodes mirror, 8 pairs (campaign max)

`run_paired.py`, candidate = `large_army_moves_off` (OLD behaviour), baseline
= shipped defaults (bundle ON), seeds 9100+, 16 games, all completed, 0
stalls. Campaign JSON:
`bench_data/campaign_large_army_bundle/campaign_paired_20260809_210034_large_army_moves_off.json`.

    E (old − new) = −1.50 VP/game   se 2.142   95% CI [−5.7, +2.7]   t = −0.7
    F (structural) = −4.50           se 3.718

Read: at this budget the bundle is strength-NEUTRAL on the healthy mirror —
the point estimate slightly favours the new defaults and the CI excludes a
regression larger than ~2.7 VP at 95%. The stopping rule never reached a
verdict (needs |E| ≥ 4 at 2 se, or se ≤ 1.6 for futility), so a bigger
campaign can tighten this; nothing here argues for turning the bundle off.
The trajectory across the run: +3.25 → +0.38 → 0.00 → −1.50 as pairs
accumulated — noise collapsing around zero.
