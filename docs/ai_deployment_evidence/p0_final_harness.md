# P0 final — live harness, 36 runs (P0.1 + P0.3 + P0.4)

`python3 40k/tools/deploy_harness.py --launch --port 9181 --fixtures mirror_orks_2000_predeploy asym_2000_predeploy mirror_custodes_2000_predeploy --zones fixture hammer_anvil dawn_of_war search_and_destroy sweeping_engagement tipping_point --seeds 7 11 --plans off` on branch claude/hopeful-hypatia-35xlm9 (every P0 kill switch at its default 1). Raw output: `p0_final_harness.json`.

- **rejected** = refused deployment actions of any type, counted at the source by AIPlayer (`DeploymentEval.count_rejected_deploy_actions` over `AIPlayer.get_deploy_rejections()`: first tries, retries, the reserves fallback). New in P0.4.
- **failed** = the legacy game-log count of first-try refusals (comparable with the baseline's 298).
- Both columns sum both seats; Hidden / leakers / home likewise.

| fixture | map | seed | forced | rejected | failed | audit | fully Hidden multi | leakers | home held | worst drop |
|---|---|---|---|---|---|---|---|---|---|---|
| asym | dawn_of_war | 7 | 0 | 0 | 0 | 0 | 10 / 14 | 0 | 2 / 2 | 519 ms |
| asym | dawn_of_war | 11 | 0 | 0 | 0 | 0 | 10 / 14 | 0 | 2 / 2 | 484 ms |
| asym | fixture | 7 | 0 | 0 | 0 | 0 | 8 / 14 | 0 | 2 / 2 | 135 ms |
| asym | fixture | 11 | 0 | 0 | 0 | 0 | 8 / 14 | 0 | 2 / 2 | 131 ms |
| asym | hammer_anvil | 7 | 0 | 0 | 0 | 0 | 11 / 14 | 0 | 2 / 2 | 120 ms |
| asym | hammer_anvil | 11 | 0 | 0 | 0 | 0 | 11 / 14 | 0 | 2 / 2 | 168 ms |
| asym | search_and_destroy | 7 | 0 | 0 | 0 | 0 | 12 / 14 | 0 | 2 / 2 | 837 ms |
| asym | search_and_destroy | 11 | 0 | 0 | 0 | 0 | 12 / 14 | 0 | 2 / 2 | 831 ms |
| asym | sweeping_engagement | 7 | 0 | 0 | 0 | 0 | 8 / 14 | 0 | 0 / 2 | 631 ms |
| asym | sweeping_engagement | 11 | 0 | 0 | 0 | 0 | 8 / 14 | 0 | 0 / 2 | 418 ms |
| asym | tipping_point | 7 | 0 | 0 | 0 | 0 | 11 / 14 | 0 | 2 / 2 | 398 ms |
| asym | tipping_point | 11 | 0 | 0 | 0 | 0 | 11 / 14 | 0 | 2 / 2 | 391 ms |
| mirror_custodes | dawn_of_war | 7 | 0 | 0 | 0 | 0 | 12 / 16 | 0 | 2 / 2 | 35 ms |
| mirror_custodes | dawn_of_war | 11 | 0 | 0 | 0 | 0 | 12 / 16 | 0 | 2 / 2 | 43 ms |
| mirror_custodes | fixture | 7 | 0 | 0 | 0 | 0 | 9 / 16 | 0 | 2 / 2 | 52 ms |
| mirror_custodes | fixture | 11 | 0 | 0 | 0 | 0 | 9 / 16 | 0 | 2 / 2 | 43 ms |
| mirror_custodes | hammer_anvil | 7 | 0 | 0 | 0 | 0 | 12 / 16 | 0 | 2 / 2 | 50 ms |
| mirror_custodes | hammer_anvil | 11 | 0 | 0 | 0 | 0 | 12 / 16 | 0 | 2 / 2 | 38 ms |
| mirror_custodes | search_and_destroy | 7 | 0 | 0 | 0 | 0 | 12 / 16 | 0 | 2 / 2 | 49 ms |
| mirror_custodes | search_and_destroy | 11 | 0 | 0 | 0 | 0 | 12 / 16 | 0 | 2 / 2 | 48 ms |
| mirror_custodes | sweeping_engagement | 7 | 0 | 0 | 0 | 0 | 7 / 16 | 0 | 0 / 2 | 38 ms |
| mirror_custodes | sweeping_engagement | 11 | 0 | 0 | 0 | 0 | 7 / 16 | 0 | 0 / 2 | 40 ms |
| mirror_custodes | tipping_point | 7 | 0 | 0 | 0 | 0 | 11 / 16 | 0 | 2 / 2 | 34 ms |
| mirror_custodes | tipping_point | 11 | 0 | 0 | 0 | 0 | 11 / 16 | 0 | 2 / 2 | 36 ms |
| mirror_orks | dawn_of_war | 7 | 0 | 0 | 0 | 0 | 9 / 12 | 0 | 2 / 2 | 565 ms |
| mirror_orks | dawn_of_war | 11 | 0 | 0 | 0 | 0 | 9 / 12 | 0 | 2 / 2 | 566 ms |
| mirror_orks | fixture | 7 | 0 | 0 | 0 | 0 | 9 / 12 | 0 | 2 / 2 | 553 ms |
| mirror_orks | fixture | 11 | 0 | 0 | 0 | 0 | 9 / 12 | 0 | 2 / 2 | 536 ms |
| mirror_orks | hammer_anvil | 7 | 0 | 0 | 0 | 0 | 7 / 12 | 0 | 2 / 2 | 235 ms |
| mirror_orks | hammer_anvil | 11 | 0 | 0 | 0 | 0 | 7 / 12 | 0 | 2 / 2 | 225 ms |
| mirror_orks | search_and_destroy | 7 | 0 | 0 | 0 | 0 | 9 / 12 | 0 | 2 / 2 | 814 ms |
| mirror_orks | search_and_destroy | 11 | 0 | 0 | 0 | 0 | 9 / 12 | 0 | 2 / 2 | 875 ms |
| mirror_orks | sweeping_engagement | 7 | 0 | 0 | 0 | 0 | 8 / 12 | 0 | 0 / 2 | 527 ms |
| mirror_orks | sweeping_engagement | 11 | 0 | 0 | 0 | 0 | 8 / 12 | 0 | 0 / 2 | 482 ms |
| mirror_orks | tipping_point | 7 | 0 | 0 | 0 | 0 | 9 / 12 | 0 | 2 / 2 | 312 ms |
| mirror_orks | tipping_point | 11 | 0 | 0 | 0 | 0 | 9 / 12 | 0 | 2 / 2 | 343 ms |
| **total** | | 36 runs | **0** | **0** | 0 | 0 | **348 / 504** | **0** | 60 / 72 | 875 ms |

Also: builder 'no legal set-up' 0, builder gate rejections 0, 1008 drops, mean 80 ms per drop (whole decision, every build included).

Determinism cross-check: in 36 of 36 runs, the per-seat deployment metrics and the audit are identical to the committed P0.3 run (`p0_3_terrain_harness.json`, same configs, measured before P0.4). P0.4 changed no AI decision, only measurement. No differences.

Baseline for comparison (`p0_baseline_harness.md`, pre-P0, same 36 configs): 152 forced reserves, 298 refused placements (legacy count), 53/504 fully Hidden multi-model units, 263 leakers, 55/72 home objectives held.

After the 36 runs, MCP `verify_delivery` on the live harness game (port 9181) returned verdict PASS: `log.no_errors` (0 ERROR lines), and on the last board 0 refused deployment actions, 0 forced reserves, 0 legality-audit violations, 0 undeployed units.
