# Grid pHash size evaluation — 3×3 vs 4×4

Empirical comparison of grid granularity for the diff prefilter,
filed as the reviewer-checkbox follow-up from PR #403.

## Methodology

Same scenario (`367_designate_warlord`), same regressions tested
in PR #403's empirical table, plus a sweep against 6 other
scenarios to detect false-positive rate.

## Sensitivity (regression detection)

| Regression | 3×3 | 4×4 |
|---|---|---|
| Clean (no regression) | drift 0, hd=0 | drift 0, hd=0 |
| Button text `"Confirm F" → "C"` | drift 0, hd=4 (**miss**) | drift 12, hd=8 (catch) |
| Parchment color swap (parchment → green) | drift 12, hd=8 (catch) | drift 12, hd=10 (catch) |

4×4 catches the button-text regression that 3×3 misses (4×4 tiles
are smaller, so the button area dominates one tile's hash).

## Specificity (false-positive sweep)

| Scenario | 3×3 | 4×4 |
|---|---|---|
| `runner_smoke` | drift 0, hd=0 | drift 0, hd=0 |
| `376_da_jump_bounds` | drift 0, hd=0 | drift 0, hd=0 |
| `378_leader_pairing_formations` | drift 0, hd=0 | drift 0, hd=0 |
| `382_cp_grant_both_players` | drift 0 | **drift 7/7, hd=14 (false positive)** |
| `383_battleshock_can_shoot` | drift 0, hd=2 | drift 0, hd=2 |
| `387_waaagh_energy_eadbanger` | drift 0, hd=2 | drift 0, hd=2 |
| `charge_congestion` | drift 0 | **drift 2/5, hd=20 (false positive)** |

4×4 introduces 2 new false positives.

## Decision

**3×3 stays as default.** The button-text-class regression sits at
the noise floor where small text changes live; the per-step
threshold override mechanism (`_thresholds.json:per_step`) is the
right escape hatch for scenarios that need to catch text-level
regressions.

Trading 1-2 false positives per ~25 scenarios for tighter
sensitivity is the wrong direction. A loop that fails on real PRs
because the unchanged battlefield happened to land differently
across tile boundaries erodes trust — the prefilter is supposed to
filter signal from noise, not produce noise of its own.

The per-step override remains the right tool for scenarios
specifically testing text content or fine UI detail. The default
should optimise for false-positive avoidance, which 3×3 does.

## What 3×3 cannot catch

Documented limitations of the 3×3 grid at 480×270 golden resolution:
- Single-word text changes in already-text-dense regions
- 1-2px border color changes (sub-pixel at 480×270)
- Equal-luminance color swaps (pHash blindness)

These are filed as separate follow-ups:
- Higher-resolution goldens (stop downsampling) — the obvious fix
  for the latter two
- Per-step threshold tuning for text-sensitive scenarios — already
  supported

The grid size itself is the wrong knob for these problems.
