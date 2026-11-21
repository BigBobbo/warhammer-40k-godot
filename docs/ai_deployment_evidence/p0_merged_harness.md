# P0 final — live harness on the merged code after the review fixes

Code: branch claude/hopeful-hypatia-35xlm9 at 842c0b2 (lanes A, B1, B2 merged, plus the W3 review fixes F1-F4). Every P0 kill switch at its default 1. Plans off.

Command (both runs): `python3 40k/tools/deploy_harness.py --launch --fixtures mirror_orks_2000_predeploy asym_2000_predeploy mirror_custodes_2000_predeploy --zones fixture hammer_anvil dawn_of_war search_and_destroy sweeping_engagement tipping_point --seeds 7 11 --plans off`; the second run adds `--attach gate` (each Deffkilla Wartrike leads a 6-bike Warbikers unit, 24 of 36 runs; the Custodes mirror has no such pair). Caches are cleared before every run (cold), so the drop times are cold-cache figures.

Measured on a shared 4-CPU container; wall-clock figures are indicative only. D10 is enforced by per-drop COUNTS in the tests.

## No attachments — `p0_merged_harness.json`

### Per map (p0_merged_harness.json)
| fixture | map | runs | forced reserves | failed submits | fully Hidden (multi-model) | leakers | home held | audit violations |
|---|---|---|---|---|---|---|---|---|
| asym | dawn_of_war | 2 | 0 | 0 | 20/28 | 0 | 4/4 | 0 |
| asym | fixture | 2 | 0 | 0 | 16/28 | 0 | 4/4 | 0 |
| asym | hammer_anvil | 2 | 0 | 0 | 22/28 | 0 | 4/4 | 0 |
| asym | search_and_destroy | 2 | 0 | 0 | 22/28 | 0 | 4/4 | 0 |
| asym | sweeping_engagement | 2 | 0 | 0 | 16/28 | 0 | 0/4 | 0 |
| asym | tipping_point | 2 | 0 | 0 | 22/28 | 0 | 4/4 | 0 |
| mirror_custodes | dawn_of_war | 2 | 0 | 0 | 24/32 | 0 | 4/4 | 0 |
| mirror_custodes | fixture | 2 | 0 | 0 | 18/32 | 0 | 4/4 | 0 |
| mirror_custodes | hammer_anvil | 2 | 0 | 0 | 24/32 | 0 | 4/4 | 0 |
| mirror_custodes | search_and_destroy | 2 | 0 | 0 | 28/32 | 0 | 4/4 | 0 |
| mirror_custodes | sweeping_engagement | 2 | 0 | 0 | 14/32 | 0 | 0/4 | 0 |
| mirror_custodes | tipping_point | 2 | 0 | 0 | 22/32 | 0 | 4/4 | 0 |
| mirror_orks | dawn_of_war | 2 | 0 | 0 | 18/24 | 0 | 4/4 | 0 |
| mirror_orks | fixture | 2 | 0 | 0 | 18/24 | 0 | 4/4 | 0 |
| mirror_orks | hammer_anvil | 2 | 0 | 0 | 18/24 | 0 | 4/4 | 0 |
| mirror_orks | search_and_destroy | 2 | 0 | 0 | 20/24 | 0 | 4/4 | 0 |
| mirror_orks | sweeping_engagement | 2 | 0 | 0 | 16/24 | 0 | 0/4 | 0 |
| mirror_orks | tipping_point | 2 | 0 | 0 | 18/24 | 0 | 4/4 | 0 |
| **total** | | 36 | **0** | **0** | **356/504** | **0** | 60/72 | **0** |

builder: 26 builds, 0 no-legal, 0 gate rejections, 0 grown, worst drop 1152 ms
delta: forced 152 -> 0, failed submits 298 -> 0, fully Hidden multi 53/504 -> 356/504, leakers 263 -> 0

Totals: worst drop (whole decision) 1697 ms, mean 109 ms; worst per-drop work evals 72,475 / fresh 14,141 / growth 144,612.

## Gate attachments — `p0_merged_harness_attached.json`

### Per map (p0_merged_harness_attached.json)
| fixture | map | runs | forced reserves | failed submits | fully Hidden (multi-model) | leakers | home held | audit violations |
|---|---|---|---|---|---|---|---|---|
| asym | dawn_of_war | 2 | 0 | 0 | 20/28 | 0 | 4/4 | 0 |
| asym | fixture | 2 | 0 | 0 | 16/28 | 0 | 4/4 | 0 |
| asym | hammer_anvil | 2 | 0 | 0 | 26/28 | 0 | 4/4 | 0 |
| asym | search_and_destroy | 2 | 0 | 0 | 22/28 | 0 | 4/4 | 0 |
| asym | sweeping_engagement | 2 | 0 | 0 | 16/28 | 0 | 0/4 | 0 |
| asym | tipping_point | 2 | 0 | 0 | 24/28 | 0 | 4/4 | 0 |
| mirror_custodes | dawn_of_war | 2 | 0 | 0 | 24/32 | 0 | 4/4 | 0 |
| mirror_custodes | fixture | 2 | 0 | 0 | 18/32 | 0 | 4/4 | 0 |
| mirror_custodes | hammer_anvil | 2 | 0 | 0 | 24/32 | 0 | 4/4 | 0 |
| mirror_custodes | search_and_destroy | 2 | 0 | 0 | 28/32 | 0 | 4/4 | 0 |
| mirror_custodes | sweeping_engagement | 2 | 0 | 0 | 14/32 | 0 | 0/4 | 0 |
| mirror_custodes | tipping_point | 2 | 0 | 0 | 22/32 | 0 | 4/4 | 0 |
| mirror_orks | dawn_of_war | 2 | 0 | 0 | 20/24 | 0 | 4/4 | 0 |
| mirror_orks | fixture | 2 | 0 | 0 | 16/24 | 0 | 4/4 | 0 |
| mirror_orks | hammer_anvil | 2 | 0 | 0 | 24/24 | 0 | 4/4 | 0 |
| mirror_orks | search_and_destroy | 2 | 0 | 0 | 20/24 | 0 | 4/4 | 0 |
| mirror_orks | sweeping_engagement | 2 | 0 | 0 | 14/24 | 0 | 0/4 | 0 |
| mirror_orks | tipping_point | 2 | 0 | 0 | 20/24 | 0 | 4/4 | 0 |
| **total** | | 36 | **0** | **0** | **368/504** | **0** | 60/72 | **0** |

builder: 12 builds, 0 no-legal, 0 gate rejections, 0 grown, worst drop 1360 ms
delta: forced 152 -> 0, failed submits 298 -> 0, fully Hidden multi 53/504 -> 368/504, leakers 263 -> 0

Totals: worst drop (whole decision) 1371 ms, mean 96 ms; worst per-drop work evals 32,605 / fresh 17,636 / growth 150,278.
