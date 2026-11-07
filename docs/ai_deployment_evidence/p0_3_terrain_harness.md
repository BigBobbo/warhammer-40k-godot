# P0.3 (11e terrain scorer + zone frame) — live harness, 36 runs

`python3 40k/tools/deploy_harness.py --launch --port 9180 --fixtures mirror_orks_2000_predeploy asym_2000_predeploy mirror_custodes_2000_predeploy --zones fixture hammer_anvil dawn_of_war search_and_destroy sweeping_engagement tipping_point --seeds 7 11 --plans off` (branch claude/hopeful-hypatia-35xlm9, FIX_DEPLOY_FRAME = FIX_DEPLOY_TERRAIN_11E = 1). Raw output: `p0_3_terrain_harness.json`. Columns: baseline = `p0_baseline_harness.json` (pre-P0), P0.1 = FormationBuilder only, P0.3 = this branch.

| fixture | map | forced reserves (base / P0.1 / P0.3) | fully Hidden multi-model (base / P0.1 / P0.3) | leakers (base / P0.1 / P0.3) | home held (base / P0.1 / P0.3) |
|---|---|---|---|---|---|
| asym | dawn_of_war | 7 / 0 / 0 | 0 / 2 / 20 of 28 | 15 / 8 / 0 | 2 / 2 / 4 of 4 |
| asym | fixture | 9 / 0 / 0 | 2 / 6 / 16 of 28 | 13 / 12 / 0 | 4 / 4 / 4 of 4 |
| asym | hammer_anvil | 7 / 0 / 0 | 8 / 8 / 22 of 28 | 7 / 16 / 0 | 4 / 4 / 4 of 4 |
| asym | search_and_destroy | 10 / 0 / 0 | 0 / 8 / 24 of 28 | 25 / 16 / 0 | 4 / 4 / 4 of 4 |
| asym | sweeping_engagement | 11 / 0 / 0 | 0 / 4 / 16 of 28 | 15 / 14 / 0 | 0 / 0 / 0 of 4 |
| asym | tipping_point | 8 / 0 / 0 | 2 / 2 / 22 of 28 | 15 / 16 / 0 | 4 / 4 / 4 of 4 |
| mirror_custodes | dawn_of_war | 0 / 0 / 0 | 1 / 0 / 24 of 32 | 11 / 14 / 0 | 1 / 0 / 4 of 4 |
| mirror_custodes | fixture | 0 / 0 / 0 | 3 / 8 / 18 of 32 | 9 / 16 / 0 | 4 / 4 / 4 of 4 |
| mirror_custodes | hammer_anvil | 0 / 0 / 0 | 12 / 14 / 24 of 32 | 12 / 12 / 0 | 4 / 4 / 4 of 4 |
| mirror_custodes | search_and_destroy | 0 / 0 / 0 | 5 / 8 / 24 of 32 | 18 / 18 / 0 | 4 / 4 / 4 of 4 |
| mirror_custodes | sweeping_engagement | 0 / 0 / 0 | 2 / 2 / 14 of 32 | 20 / 12 / 0 | 0 / 0 / 0 of 4 |
| mirror_custodes | tipping_point | 0 / 0 / 0 | 4 / 2 / 22 of 32 | 18 / 22 / 0 | 4 / 4 / 4 of 4 |
| mirror_orks | dawn_of_war | 14 / 0 / 0 | 2 / 0 / 18 of 24 | 14 / 10 / 0 | 4 / 4 / 4 of 4 |
| mirror_orks | fixture | 15 / 0 / 0 | 1 / 4 / 18 of 24 | 14 / 12 / 0 | 4 / 4 / 4 of 4 |
| mirror_orks | hammer_anvil | 17 / 0 / 0 | 4 / 4 / 14 of 24 | 12 / 20 / 0 | 4 / 4 / 4 of 4 |
| mirror_orks | search_and_destroy | 18 / 0 / 0 | 4 / 2 / 18 of 24 | 16 / 14 / 0 | 4 / 4 / 4 of 4 |
| mirror_orks | sweeping_engagement | 18 / 0 / 0 | 0 / 4 / 16 of 24 | 16 / 12 / 0 | 0 / 0 / 0 of 4 |
| mirror_orks | tipping_point | 18 / 0 / 0 | 3 / 4 / 18 of 24 | 13 / 18 / 0 | 4 / 4 / 4 of 4 |
| **total** | | **152 / 0 / 0** | **53 / 82 / 348 of 504** | **263 / 262 / 0** | 55 / 54 / 60 of 72 |

P0.3 also: failed submits 0, legality-audit violations 0, builder no-legal 0, gate rejections 0; 1008 drops, worst drop (whole decision, every build included) 870 ms, mean 77 ms.

Home objective on Sweeping Engagement is 0/12 in every column: the layout used for it (`disruption_vs_disruption_3`) labels `obj_home_1` (8.5", 10.75") as player1, but that point is in player 2's zone on this map (x 0-14"), so no deployment can hold it — a data / seat-labelling issue, not an AI one.

Screenshots: `p0_3_ingame_asym_crucible_11e_board.jpg` (asym fixture after AI-vs-AI deployment: Custodes and Ork infantry inside the dense ruins, vehicles and bikes behind ruins), `p0_3_kcard_inside_dense_ruins.jpg` (K card: "Inside dense ruins — all 5 models Hidden", Whole unit Hidden +2.0).
