# Gate baseline

- Commit 276eb36 (before the codex import): `bash 40k/tests/run_pretrigger_tests.sh`
  → **4648 passed, 0 failed across 136 tests** (run 2026-10-17 in a clean worktree).
- So there are NO pre-existing failures: every failure on the branch is
  caused by the codex work and must be fixed or retired (RETIRED_TESTS.md).
- Integrator status on claude/gracious-shannon-u3z0mf after the data import
  (e704330 + follow-up fixes): see the "Branch gate" section below once filled in.

## Branch gate
- ad244cd (data import + triage): 4765 passed, 13 failed across 137 files —
  all 13 in tests/test_melee_datasheet_kits.gd (pre-codex Boyz kit), fixed in
  a5bed45 (wargear rebuild for re-kitted datasheets + test ported to the codex
  kit, 23/23). Expected state at a7d77c2: 0 failures.
- Windowed scenarios touched by the data change (booting from army files)
  re-run green: custodes_lions_vs_recon, custodes_custodian_guard_deep_strike,
  pm10_shipped_plan_from_menu, pm_f4_coherency_note_in_browser,
  recon_stomps_base_army (+ 25 others that never failed). Tutorial scenarios:
  tutorial armies stay pre-codex (see PLAN follow-ups); rerun pending.
- If you branched before a7d77c2, merge the branch tip before your final gate.
