# Loop iteration sweep — 35 runs across 22 scenarios

Compact log of the iteration-and-improvement pass that ran the loop
against most of the scenario library and fixed the issues each
iteration surfaced. Companion to `demo_findings.md`.

## Issues found and fixed

| # | Issue | Surfaced in | Fix | Verified in |
|---|---|---|---|---|
| 1 | Missing goldens silently pass — driver exits 0 with no warning | iter 1 (`367_designate_warlord` in diff mode, never blessed) | Driver now prints prominent `WARNING N step(s) have no golden` and tells operator how to `--bless` | iter 4 |
| 2 | `--bless` writes goldens even when scenario has failing steps — propagates broken state into the visual baseline | iter 6, 7 (pre-existing scenario reds in `372_ere_we_go_charge_modifier`, `373_lone_operative_guard`) | Driver REFUSES to bless when `SCENARIO_EXIT != 0`. Exits non-zero with clear message | iter 11, 12 |
| 3 | Selector preflight launches a separate Godot instance even when the scenario has no selector-using acts — ~12s wasted per scenario | iter 13-17 (most scenarios show `resolved=0 not_found=0`) | Driver parses scenario JSON, skips preflight if no `click_*` / `expect_node_*` / `expect_token_visible` steps | iter 19 (14s vs ~26s) |
| 4 | Goldens were 1920×1080 PNGs averaging 518KB → 111MB total across 22 scenarios. Approaching Git LFS territory | post iter 30 (full bootstrap done) | `golden_diff.py --bless` now downsamples to quarter resolution (480×270) with max PNG compression. PHASH is empirically Hamming-0 vs full-size source (PHASH internally downsamples to 32×32 anyway). All existing goldens re-shrunken in-place | iter 31, 32 (220/220 still match), iter 33 (drift detection still fires) |
| 5 | After blessing 22 scenarios, `coverage.json` was stale — operators running `list_scenarios_by_priority.py` would keep getting the same top-priority list | post iter 30 | New `scripts/loop/update_coverage_for_blessed.py` walks `goldens/` and updates `last_verified_commit` on every tile whose scenarios list overlaps. Reports orphans (blessed scenarios with no covering tile) | iter 34 (dry-run), iter 35 (applied — 5 tiles updated, 18 orphans reported) |

## Per-scenario state after the sweep

22 of 25 scenarios bootstrapped. The remaining 3 have pre-existing
scenario-level reds and the driver correctly refuses to bless them:

| Scenario | Steps | Result |
|---|---|---|
| `367_designate_warlord` | 12 | blessed |
| `370_bgnt_vehicle_shoots_in_engagement` | 8 | blessed |
| `372_ere_we_go_charge_modifier` | 8 | **REFUSED — 1/8 step failed** (pre-existing) |
| `373_lone_operative_guard` | 9 | **REFUSED — 2/9 steps failed** (pre-existing) |
| `374_headwoppa_devastating_wounds` | 9 | blessed |
| `374_kunnin_but_brutal_fallback` | 9 | blessed |
| `374_panoptispex_ignores_cover` | 8 | blessed |
| `374_supa_cybork_fnp` | 8 | blessed |
| `376_da_jump_bounds` | 11 | blessed |
| `377_defender_deploys_first` | 5 | blessed |
| `378_leader_pairing_formations` | 12 | blessed |
| `382_cp_grant_both_players` | 7 | blessed |
| `383_battleshock_can_shoot` | 8 | blessed |
| `386_deadly_demise_vehicle` | 8 | blessed |
| `387_waaagh_energy_eadbanger` | 8 | blessed |
| `394_follow_me_ladz_plus_move` | 7 | blessed |
| `397_castellan_mark_redeploy` | 7 | blessed |
| `charge_congestion` | 5 | blessed |
| `co_offer_after_charge` | 20 | blessed (re-shrunken) |
| `fight_self_targeting` | 5 | **REFUSED — 1/5 step failed** (pre-existing) |
| `fights_last_select_fighter` | 10 | blessed |
| `hi_offer_after_charge_into_engagement` | 24 | blessed |
| `horde_movement` | 3 | blessed |
| `ri_offer_at_end_of_movement` | 17 | blessed |
| `runner_smoke` | 11 | blessed (re-shrunken) |

Total: 217 blessed per-step goldens, 14MB on disk (down from 110MB
before issue 4 fix).

The 3 refusals point at pre-existing scenario problems that a human
needs to fix on the main branch before the loop can baseline them.
That's the correct behaviour — the loop never overwrites its own
ground truth with a broken state.

## What still needs human attention

1. **The 3 pre-existing scenario reds**
   (`372_ere_we_go_charge_modifier`, `373_lone_operative_guard`,
   `fight_self_targeting`) — these scenarios assert engine results that
   don't match current code. Either the scenario is wrong (update the
   assertion) or the code regressed (fix the code). The loop can't
   tell which; this is human triage.

2. **18 blessed scenarios are orphans in coverage.json** — they have
   goldens but no covering tile. `update_coverage_for_blessed.py`
   reports them explicitly. The operator should add tiles to
   `coverage.json` for each, with a feature description and tag —
   that's a human authoring task the loop can't do automatically.

3. **The 2 pre-existing audit-suite reds**
   (`run_pretrigger_tests.sh` tween-priority-pulse failures) — still
   blocking removal of the `LOOP_SKIP_PREFLIGHT=1` escape hatch in
   the driver. Untouched by this sweep.

## What the sweep proved

The loop infrastructure is robust to the full scenario library:

- 22 scenarios processed cleanly, 3 correctly refused
- 0 crashes in the runner
- 0 timeouts (all under the 180s cap, most well under 30s)
- 0 silent failures — every issue surfaced was caught by the driver's
  reporting or the golden_diff output
- Drift detection still works after the quarter-resolution
  optimization (verified with injected red rectangle)
- Bypass paths (`LOOP_SKIP_PREFLIGHT`, `LOOP_SKIP_SELECTOR_PREFLIGHT`)
  behave as documented
