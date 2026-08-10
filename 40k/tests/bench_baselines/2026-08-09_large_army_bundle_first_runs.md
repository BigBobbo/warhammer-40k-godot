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

## Addendum 3 — Search and Destroy mirror (the owner's suggested zone type)

`mirror_orks_2000_sd_preformations` seed 7005: **completed**, 5 rounds, 641
actions, 304 s, P1 39 / P2 80 VP. Full loop — live Formations (both Stompas
loaded 22/22), AI deployment of 154 models into the QUARTER-CIRCLE zones
(the polygon projection visibly engaged: dozens of "centre not wholly in
zone polygon — projected to ..." lines), reserves from round 2, zero
permanently-failed deployments, zero script errors. One Warbikers squad
exhausted its deploy retries and went to Strategic Reserves via the new
auto_timeout fallback — the path that used to deadlock END_DEPLOYMENT.
The 41-VP margin is one seed of mirror noise, not a claim about the layout.

## Addendum 4 — the A/A season: the UNUSABLE row is replaced

10 seeds (7001-7010), 61.9 min at 2 lanes, season `bench_data/ork_aa_postfix`:

    completed 10 / stalled 0 / timed out 0
    F (P2−P1) = +9.60   sd 16.11   se 5.09   95% CI [−0.4, +19.6]
    per-game wall: 670-757 s (median 733) under shared load

Seed 7001's season game reproduced this session's standalone run EXACTLY
(733 actions, margin +9) — independent invocations, identical trajectory,
so determinism holds through every new code path. The A/A row is written
into `2026-08-08_2000pt_fixture_AA.md`; the fixture is back in
`gate_candidate.MIRRORS`.

## SUPERSESSION NOTE (added at merge, 2026-08-10)

A parallel session (PR #897) root-caused the same hang from the other end:
`mirror_orks_2000_postdeploy` as originally packed deployed 19 of 34 units
OUT OF COHERENCY (models interleaved across units), and the ISS-042 sweep
was amputating the most-isolated models at every End of Turn. The fixture
was REBUILT with per-unit block packing.

Consequences for the rows above:
- All `mirror_orks_2000_postdeploy` rows in this file (seed 7001 single game
  and the 10-seed A/A) were measured on the PRE-REBUILD fixture. They remain
  valid as robustness evidence for the movement bundle — the AI now survives
  even an illegal board without hanging, deterministically — but they do NOT
  describe the rebuilt fixture. Its A/A is to be re-measured.
- `mirror_orks_2000_postdeploy_spaced` was built with the old
  model-interleaving packer — defective by the same diagnosis — and has
  been DELETED rather than rebuilt. Measured with the merged per-unit
  packer (`--gap` = clearance between unit blocks): 0.6", 0.4", 0.3",
  0.25" and 0.15" all overflow the zone; only 0.1" fits, double the
  canonical 0.05" and not meaningfully "spaced". The 0.5-1" aspiration in
  the earlier progress notes was ill-posed for this army — its unit blocks
  genuinely fill 80-87% of the zone, and density was falsified as the hang
  cause anyway. `--gap` stays in the builder for lighter lists.
- The preformations / Search-and-Destroy fixtures and every row measured on
  them are UNAFFECTED: they ship undeployed, so the packer bug never touched
  them, and in those games the AI deployed coherent formations itself.
- The Custodes paired A/B (E = −1.50 ± 2.14) is likewise unaffected: the
  old packer sorted by base size with unit-id tiebreak, so the near-uniform
  Custodes bases kept each unit's models contiguous (and PR #897 verified
  both Custodes seeds reproduce their historical margins exactly). The
  interleaving bit the Orks because their base sizes alternate wildly.

The two fixes are complementary: the fixture rebuild removes the pathology
from the benchmark; the movement bundle removes the hang from the GAME for
any board state that produces it legally.
