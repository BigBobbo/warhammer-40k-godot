# Pinned goldens for the visual-regression loop.
# Each PNG is the blessed reference frame for one (scenario, step) pair.
# Filenames mirror the runner output: <scenario_id>_step_NN_<act>.png.
# Comparison is PHASH (perceptual hash) with per-scenario thresholds in
# _thresholds.json. See scripts/loop/golden_diff.py.
#
# Adding/updating a golden:
#   bash scripts/loop/run_one_scenario_loop.sh --bless <scenario.json>
#
# Removing a golden:
#   rm 40k/tests/scenarios/goldens/<scenario_id>_step_*.png
#   then re-run the loop; missing-golden status writes a "would-bless"
#   note and exits green.
