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
  recon_stomps_base_army (+ 25 others that never failed).
- PRE-EXISTING windowed failures (identical pass/fail counts on the 276eb36
  baseline worktree, so not caused by the codex work — do not chase them):
  tut_t1_basics (1 fail, step 92), tut_full_course_chain_pad (7),
  tut_t1_lock_it_in_start_glyph (28), tut_t1_pad_ack_button (31),
  tut_t4_dakka_pad (31), tut_t4_dakka_reassign_pad (2), tut_t5_ere_we_go_pad (22),
  tut_t6_krumpin_pad (6), tut_t6_wrong_fighter_backout (18),
  iss064b_primary_disposition_11e (4), iss064d_triangulate_prompt_11e (1).
- CAUSED BY THE DATA IMPORT, owned by WP-O5: taktikal_enhancements_load (passes
  on 276eb36, 14/19 on the branch) — it tests the 10e Taktikal Brigade
  enhancements (Skwad Leader / Mek Kaptin) that the codex replaced with Kill
  Kommanda / Throat-slittas.
- After WP-C3 + WP-O34 merges (c8fdec5): WP-O34 reported 5250/0 across 140
  files after merging the C3 tip.
- If you branched before a7d77c2, merge the branch tip before your final gate.

## Final validation (integrator, 2026-10-18, tip `6e5530b9` + PLAN-only commits)

- Gate `run_pretrigger_tests.sh`: **8913 passed, 1 failed across 157 tests, exit 0** — the one
  failure is `test_custodes_lions_silent_hunters.gd`, an XFAIL on main's
  `tests/ci/direct_known_failures.txt` (BUG-11, AP sign in legacy fixture weapons).
- main's CI modes (WP-FIX2, on `daf21dcc` = this tree minus FIX1 scenarios / the deployment
  fix): `--all` 12,673 passed, failures only in the 29 known-list files; GUT unit 1563 (48
  allowlisted), integration 49 (9 allowlisted), network 14/0.
- Windowed: WP-FIX1 swept all 221 `cus11e_*` / `ork11e_*` scenarios (221/221); the main-merge
  sweep ran 255 scenarios (all non-known failures since fixed). Integrator reran 28 scenarios
  on the final tip (28/28, 0 script errors) plus the three builder→game e2e scenarios
  (`w3_builder_codex_datasheets` 20/0, `cus11e_enh_builder_cloud_army` 19/0,
  `ork11e_enh_builder_cloud_army` 24/0; browser halves all pass).
- Server: `npm test` 41/41 + parser 99/99; `verify-wahapedia-import` PASS; `npm run codex11e`
  reproducible.
- Pre-existing windowed failures from the original baseline that remain: the tutorial pads
  (lesson fixtures frozen pre-codex), `fullauto_formations_rules`, `terrain_11e_layouts`,
  `pad_reinforcement_no_move_menu` (on main's known list).
