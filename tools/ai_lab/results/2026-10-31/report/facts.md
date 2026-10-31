# Fact sheet for the next report version (rounds 3-5, protocol v2 tracks)

Compiled 2026-10-31 (after 12:46 UTC) by the report-update workflow's facts agent. Repo HEAD = origin tip = `544c693` (checked with `git ls-remote`).
Read-only: no tracked file changed, nothing committed, nothing published.

**Citation key.** `S:<n>` = `.ai_lab_work/STATUS.md` line n. `P2:<n>` = `tools/ai_lab/protocol_v2.md` line n. `VH:<n>` = `40k/data/version_history.json` line n.
`RA:<n>` = `tools/ai_lab/rules_audit_11e.md` line n. `TT:<n>` = `tools/ai_lab/tuning_track_proposal.md` line n. `FX:<n>` = `tools/ai_lab/fixture_proposal.md` line n.
`DR4[...]` = `.ai_lab_work/decide_r4.json` key. `CH2:<n>` / `FH2:<n>` = `.ai_lab_work/confirmed_h2.txt` / `faded_h2.txt` line n. `C1:<n>` / `F1:<n>` = `.ai_lab_work/confirmed.txt` / `faded.txt` line n.
`RC/<file>` = `.ai_lab_work/recheck/<file>` (raw ROLLOUT_RESULT lines). `WF12` = `/root/.claude/projects/-home-user-warhammer-40k-godot/72451711-ff9e-5f4b-a27c-d739a3534701/workflows/wf_194da67a-997.json` (audit-fix workflow output; not in the repo).
`commit <sha>` = that commit's message or `--stat`. **(derived)** = arithmetic or a count done by this agent on the named files; the method is given.

---

## 0. Scope check: what the live report covers (read before writing)

- The live artifact (slug ff26c2b6-1afb-4ca6-85e2-4e3bb25ce495, version `1793360876-4088`, 483 lines; title "AI Critic Loop"; read mode "owner" = private) has the page heading **"AI Critic Loop: rounds 1 and 2"**. It is dated 30 October 2026. Its summary says "The AI plays as version 1.56.6". [read_artifact and get_artifact, this session; S:383 gives the version and 483 lines]
- The link in S:40 (`https://claude.ai/artifact/YWRAdHeM7gBJTKAZJDnYZJ`) resolves to the same slug and version. [get_artifact, this session]
- So the report has **no round 3, no round 4, no 1.56.7 and no 1.56.8**. The task text assumed "up to about round 3/4". This sheet therefore also gives round 3 (section 1a) and the full 1.56.x list (section 1f).
- The old scratchpad log was lost in a container restart at 23:58 on 2026-10-30; STATUS.md was rebuilt then. Round-4 facts before 23:58 come from commits and `tools/ai_lab/r4_designs/`. [S:1, S:44]

---

## 1. Rounds 3-4, the V10/V11/V12 benches, and the 1.56.7 and 1.56.8 ships

### 1a. Round 3 (not in the report)
- Candidate V9 = `5e70bc2`: FIX_KEEPER_RELEASE on. Finding s7437 r1 (sole home keeper): alternative +7.31 VP [4.98, 9.63] over 36 seeds. [commit 5e70bc2]
- Bench V9 vs V7D, 11e rules, 124 pairs (cus 42, asy 42, ork 40): **every pair identical (M1 == M2), pooled E = 0.0**. The rule (pooled E > 0, no fixture CI wholly below 0) was not met. FIX_KEEPER_RELEASE switched off in `14eb69f`. [commit 14eb69f; S:12]

### 1b. Round 4 pipeline (2026-10-30 and 2026-10-31)
- Dates (corrected in the check step): sweep cases committed 2026-10-30 16:07-16:33; last round-4 sweep value check saved 01:23 on 31 Oct [S:102]; group test decided 00:56 [S:91]; V12 decision 03:57 [S:281]; 1.56.8 shipped 04:14:43 [commit e12e6e8].
- 24 critic sweeps r4c00-r4c23, seeds 7451-7474, on V9 (`5e70bc2`; cases record game_version 1.56.6). [results_r4/*.txt; tools/ai_lab/r4_designs/fix_args_r4.json "base_sha"]
- **(derived)** 185 rollout jobs at 12 seeds: 20 with 95% CI wholly above 0 ("clear"), 12 wholly below 0 ("harmful"), 40 with all 12 seeds identical (no signal). Method: count ROLLOUT_RESULT lines in results_r4/*.txt; clear = ci[0] > 0; harmful = ci[1] < 0; no signal = identical == n.
- 24-seed re-check batches pr5-pr9 (commits fee0bf5, 50a3c62, 688f0fa, 8f95280, e7266c9). Their raw result files are not in `.ai_lab_work/recheck/` (the work folder was rebuilt after the restart); the 36-seed values in the table below come from fix_args_r4.json.
- 7 clusters -> 7 judge panels (3 designs, 2 reviews each, 1 judge; keeper_reach had 4 reviews). [fix_args_r4.json clusters; r4_designs/*/panel.json]

| Cluster | Key finding(s), 36 seeds | Winner | Commit | Outcome |
|---|---|---|---|---|
| reinforce_insurance | s7437 r2 +4.36 [0.61, 8.12]; s7418 r1 +2.67 [0.36, 4.97] | root | 1ef7d8a | in V10 -> shipped 1.56.7 |
| lone_flip | s7454 r3 +21.50 [16.93, 26.07]; s7455 r2 +5.92 [1.30, 10.53] | root | 2042dbc | in V10 -> shipped 1.56.7 |
| keeper_reach | s7453 r1 +6.17 [3.42, 8.91]; s7454 r1 +4.83 [3.08, 6.59]; s7437 r1 +7.31 [4.98, 9.63] (raw 7.305 in r4_designs/measured_positions.json; fix_args_r4 prints +7.30; commit 5e70bc2 prints +7.31) | game | 00cc467 | parked (acts only inside the keeper release, which is off) |
| charge_low_odds | s7469 r2 +4.33 [1.37, 7.30]; s7467 r2 +2.64 [0.40, 4.88]; s7457 r2 +3.81 [0.20, 7.41] | none | f9dbb8e | nothing merged |
| screen_vs_objective | s7467 r1 +3.64 [1.82, 5.46] | narrow | 4bf2281 | parked (bench has no reserves) -> reserve track (section 7) |
| waaagh_advance_charge | s7468 r3 +6.14 [3.08, 9.19]; s7473 r3 +10.03 [6.82, 13.23] | game | 76db1ca | in V11/V12 -> shipped 1.56.8 |
| r1_home_capture | s7468 r1 +6.86 [4.45, 9.27]; s7451 r1 +5.86 [3.09, 8.63]; s7412 r1 +2.86 [1.27, 4.45]; s7411 r1 +2.50 [0.71, 4.29] | game (split switches) | 08ca3e8 | in V11/V12; FIX_R1_SUPPORT_ADVANCE off in 1.56.8 |

[values: fix_args_r4.json clusters[].findings[].measured; winners: r4_designs/*/panel.json verdict.winner; parked notes: commit messages 00cc467, 4bf2281]

### 1c. Bench arms, all vs V7D (= shipped 1.56.6 AI, `f38e43a`), 11e rules, same 124 seed pairs
Seeds: cus 95000/95020/95040 x14, asy 99000/99020/99040 x14, ork 94000..94080 step 20 x8. [S:25]
E per pair = (M1 - M2)/2; pooled = equal weight per fixture. v1 ship rule: pooled E > 0 and no fixture 95% CI wholly below 0. [decide_r4.py lines 1-3]

| Arm | Code | cus (n42) | asy (n42) | ork (n40) | Pooled E [95% CI] | Rule | Source |
|---|---|---|---|---|---|---|---|
| V10 = LONE_FLIP + REINFORCE_INSURANCE | 12e0753 | +2.92 [-1.18, 7.02] | -0.80 [-2.59, 0.99] | +0.29 [-2.72, 3.30] | **+0.80 [-1.00, 2.60]** | met -> **shipped 1.56.7** | S:13-14; commit 1322dc2 |
| V10 vs V0 (sanity) | 12e0753 | – | – | – | +0.54 [-1.43, 2.51] | – | S:15; commit 1322dc2 |
| LF-only (V10, FIX_REINFORCE_INSURANCE=0) | profile | +1.05 [-0.34, 2.44] | +0.05 [-0.66, 0.75] | +1.27 [-0.39, 2.94] | +0.79 [0.03, 1.55] | met | DR4["LFvsV7D"]; S:92 |
| RI-only (V10, FIX_LONE_FLIP=0) | profile | +1.32 [-3.10, 5.74] | -1.06 [-2.92, 0.80] | -0.89 [-3.42, 1.64] | -0.21 [-2.02, 1.60] | fails | DR4["RIvsV7D"]; S:82, S:93 |
| V11 (pre-fixup ddaa5f8) | V10 + v11 patch | -1.21 [-4.93, 2.50] | -0.85 [-3.13, 1.44] | +2.74 [-0.47, 5.94] | +0.23 [-1.58, 2.03] | met (barely) | DR4["V11vsV7D"]; S:81-82 |
| V12 C_full (R1_SUPPORT_ADVANCE on) | V10 + V11b parts | -0.98 [-4.63, 2.68] | -1.64 [-4.48, 1.19] | +2.46 [-1.28, 6.20] | -0.05 [-2.03, 1.93] | fails | DR4["V12FvsV7D"]; S:282 |
| **V12 C_waaagh (R1_SUPPORT_ADVANCE off)** | same, R1SA=0 | +1.49 [-2.01, 4.98] | +1.65 [-0.67, 3.98] | +0.38 [-2.48, 3.23] | **+1.17 [-0.52, 2.86]** | met -> **shipped 1.56.8** | DR4["V12WvsV7D"]; S:283; commit e12e6e8 |

- V10: "The fixes changed 217 of 248 bench games"; 22 shards. [commit 1322dc2]
- Identical pairs (M1 == M2): LF cus 19, asy 34, ork 29; RI 1 / 6 / 19; V11 3 / 2 / 3; V12F 1 / 1 / 4; V12W 0 / 2 / 7. [DR4[...]."identical_pairs"]
- Fix tag lines / games with a fire, V12W: WAAAGH_ADVANCE_CHARGE cus 88/60, asy 82/46, ork 46/28; LONE_FLIP 169/53, 52/25, 50/28; REINFORCE_INSURANCE 371/84, 344/44, 220/57; R1_SUPPORT_ADVANCE 0 (off). [DR4["V12WvsV7D"][fx]."fires"; S:273]
- Group-test rule (pre-registered 23:12, before arm data): keep the variant among {V10, LF-only, RI-only} with the highest pooled E that meets the rule. Result: **V10 stays** (+0.80 vs LF +0.79); switch_lf_only.sh not run. [S:16-18, S:91-94]
- LF-only has the same mean as V10 with much less spread; RI alone adds nothing. Interaction E(V10) - E(LF) - E(RI) = 0.80 - 0.79 + 0.21 = +0.22. [S:94-95]
- V12 rule (pre-registered 00:52, before LF's last shard and any combination data): ship the V12 arm with the highest pooled E only if it meets the rule AND beats V10's +0.80 on the same seeds; else keep V10. [S:84-89, S:96-97]
- Decision 03:57: **ship V12 C_waaagh** (+1.17 > +0.80). [S:281-285]
- Honest note on record: the pooled CI includes 0 (z ~ 1.36). Under protocol v2 (V2-2) it would not cross the look-1 boundary (3.710). It shipped because the V12 decision was pre-registered under v1 and running work finished under its own rules. [S:286-287]
- Lineage: V11 = V10 + `v11_from_v10.patch` (V9R keeper-off + waaagh final + r1_home_capture final; local ddaa5f8); V11b = V11 + review fixup (local 1e438b9); V12 patch pushed in `d14614d`; "9 extra suites pass on V12". [S:8-9, S:105]

### 1d. The 1.56.8 ship (2026-10-31)
- Commit `e12e6e8` (04:14:43 UTC), pushed 04:17. Shipped AI = V12 C_waaagh: FIX_WAAAGH_ADVANCE_CHARGE = 1.0, FIX_R1_SUPPORT_ADVANCE = 0.0 (code kept). Cherry-picked from ship-prep `54732ab` (review: ready). [S:294-295; commit e12e6e8; `git show e12e6e8:40k/scripts/AIDecisionMaker.gd` line 1726 `FIX_WAAAGH_ADVANCE_CHARGE: float = 1.0`, line 1662 `FIX_R1_SUPPORT_ADVANCE: float = 0.0`]
- Motivating finding: s7468 r3 P2 Stormboyz Advanced "to attack" and so could not charge; the critic's alternative (a Normal move to obj_nml_1) measured +6.14 VP [3.08, 9.19] over 36 seeds. The shipped fix keeps the attack but makes it a Normal move, so the charge stays legal (final.json: "partly" matches the alternative's intent). [fix_args_r4.json line 816; r4_designs/waaagh_advance_charge/final.json decision_checks[0]]
- **What changed for players** (VH:5-11): summary "The AI no longer Advances toward a unit it means to charge when the Advance would cost it the charge." Changes: (1) Orks (and any unit without an advance-and-charge effect) make a Normal move toward a unit they mean to charge and keep the charge; (2) while a Waaagh! (or another advance-and-charge effect) is active, those units still Advance, because then the Advance does not stop the charge.
- Tests: test_ai_fix_waaagh_advance_charge 10/0, test_ai_fix_r1_home_capture 29/0, and 14 other AI suites pass. [commit e12e6e8]
- Windowed scenario `40k/tests/scenarios/sp/ai_waaagh_advance_charge_s7468.json` (save `40k/tests/saves/critic_waaagh_s7468_r3.w40ksave`): **27/27 steps pass**, edition 11, re-run in the main checkout at 04:15. [result file `/root/.local/share/godot/app_userdata/40k/test_results/scenarios/ai_waaagh_advance_charge_s7468.json`: passed 27, failed 0, total_steps 27; S:294]
- **Screenshots** (this container; userdata dir `~/.local/share/godot/app_userdata/40k/`):
  - BEFORE (fix off): `/root/.local/share/godot/app_userdata/40k/test_results/scenarios/ai_waaagh_advance_charge_s7468_00_fix_off_before.png` — K card "THE AI WOULD: Stormboyz **advances** to attack Prosecutor Squad (12.0" away — closing to charge range (0.0" after move))"; scenario step 11 asserts BEGIN_ADVANCE.
  - AFTER (fix on): `.../ai_waaagh_advance_charge_s7468_01_fix_on_after.png` — K card "Stormboyz **moves** to attack Prosecutor Squad (12.0" away ...)"; step 21 asserts BEGIN_NORMAL_MOVE.
  - Both: top bar "ROUND 3/5 P2", "Movement Phase P2 Orks (Defender)", score "38 vs 18"; the Game Log panel on the left of the AFTER shot lists both suggestions (advances, then moves). [viewed both PNGs; result JSON steps 11, 21; S:295-296]
- V2-6 baseline for round 5 = V12W (1.56.8). Round-5 panel winners had to be rebased onto it. [S:294, S:296]
- Flags from the ship review (pre-existing, not caused by 1.56.8): (1) tests/test_ai_objective_assignment_fixes.gd fails 6/1 on V10 too and is not in tests/ci/direct_known_failures.txt; (2) IngressMove sets flags.no_moves_until_charge_phase and nothing clears it, so MovementController hides Move/Advance for units that arrived from reserves in every later turn (human-UI bug; MovementPhase does not enforce it; AI unaffected). [S:297-299]

### 1e. The 1.56.7 ship (2026-10-30)
- Commit `1322dc2` (23:41:48 UTC) adds the version entry; the AI code (FIX_LONE_FLIP = 1, FIX_REINFORCE_INSURANCE = 1 with RI_RACE / RI_ASSAULT / RI_QUARTER) has been on the branch since `12e0753`. [commit 1322dc2]
- Windowed scenarios: ai_reinforce_insurance_s7437 25/0, ai_lone_flip_s7454 25/0, version_display_at_bottom 12/0. [commit 1322dc2; result JSONs in test_results/scenarios/ also show 25/25, 25/25, 12/12]
- Screenshot files (later re-run, 2026-10-31 03:47): `.../test_results/scenarios/ai_reinforce_insurance_s7437_00_fix_off_before.png`, `..._01_fix_on_after.png`, `ai_lone_flip_s7454_00_fix_off_before.png`, `..._01_fix_on_after.png`. [ls of the userdata dir]
- Scenario content: s7437 fix off = Custodian Guard Beta reinforces obj_center (already held, OC 6); fix on = Beta advances toward obj_nml_2 (RI-QUARTER +9.0), centre reinforcement carries the RI-RACE penalty (enemy ~42 OC vs our 17). s7454 fix off = Gamma sent alone to flip obj_nml_1 (enemy OC 14); fix on = Gamma to obj_home_2, Alpha flips obj_center, Beta holds it. [commit 57b5acc]

### 1f. All 1.56.x version entries (newest first)

| Version | Date | Commit that added it | Summary (VH) | VH lines |
|---|---|---|---|---|
| 1.56.8 | 2026-10-31 | e12e6e8 | The AI no longer Advances toward a unit it means to charge when the Advance would cost it the charge. (2 changes) | 4-12 |
| 1.56.7 | 2026-10-30 | 1322dc2 | The AI shares its units between objectives better: fewer wasted reinforcements, and no lone units sent to flip strongly held objectives. (4 changes: reach measured from each unit's nearest model; Reconnaissance Sweep quarter VP counted; all-[ASSAULT] units Advance on long trips; a unit staying on an enemy-controlled objective no longer makes it read as taken) | 13-23 |
| 1.56.6 | 2026-10-30 | f38e43a | The AI reads objective control on terrain correctly and stops wasting moves on objectives it already holds. (2) | 24-32 |
| 1.56.5 | 2026-10-29 | 86ff136 | The AI playing second claims its own side's objectives in round 1 again. (1) | 33-40 |
| 1.56.4 | 2026-10-29 | 40833cc | Faster objective control checks (about 1/5 of the time). (1) | 41-48 |
| 1.56.3 | 2026-10-29 | 8f4664f | The AI contests the centre again instead of leaving it to the enemy. (2) | 49-57 |
| 1.56.2 | 2026-10-29 | c1ba348 | The AI Advances toward far objectives again when the dice can get it there a turn sooner (about 1 in 3 or better). (1) | 58-65 |
| 1.56.1 | 2026-10-28 | 26f0a42 | More AI fixes: the cheapest unit keeps home, charges count real help and the cost of being hit back. (6) | 66-78 |
| 1.56.0 | 2026-10-28 | 554b40a | The AI keeps its army together, finishes wounded units and stops several wasted moves. (10) | 79-95 |

[commit column: `git log -S'"version": "<v>"' -- 40k/data/version_history.json`]

---

## 2. Protocol v2

- File `tools/ai_lab/protocol_v2.md`, "Written 2026-10-31 ~02:58 UTC, BEFORE any v2 data was collected. Committed to git so the commit time fixes the order." [P2:3-4]
- **Pre-registration commit `27fac2c`, 2026-10-31 02:59:43 UTC**, docs only (95 lines). "The V12 bench and the 4 round-5 judge panels finish under the v1 rules." [commit 27fac2c]
- Transition: finish under v1 (a) the V12 confirmation bench and its 00:52 rule, (b) the 4 round-5 judge panels, (c) sweeps r5c06/07/08/10 (12-seed value check). Everything else follows v2. [P2:6-12]
- Clarification 03:05 (before any reach data): the reach run uses 2 pairs per fixture, because with the same AI in both seats the two games of a pair are identical; this gives the 6 different games V2-1 intends. [S:228-229]

**Why adopted — no file states the motive in words.** The facts on record before 02:59 that each rule answers (writer: present as context, not as a quoted reason):
- Benches that cannot see a fix: round 3's V9 bench had all 124 pairs identical, pooled E 0.0 [commit 14eb69f]; round 4 parked screen_vs_objective because "The bench gives identical pairs, so it cannot meet pooled bench E > 0" [r4_designs/screen_vs_objective/panel.json verdict.required_changes[0]]. Lesson text given to v2 finalizers: "round 2's fixes passed every gate and still lost 6.26 VP per game over full games ... A fix that never fires in the benchmark fixtures cannot show a gain" [creator_dirs/resfinal_screen_vs_objective/final_screen_vs_objective.txt, LESSONS line].
- Under-powered benches: "The 124-pair benches had pooled SE 0.39-0.92 VP" [P2:47]. Of the arms complete before 02:59 (V10, LF-only, RI-only, V11), only LF-only had a pooled 95% CI above 0 (table 1c).
- One-round rollouts: the pr10 24-seed re-check faded 2 of 11 findings [S:126]; the round-2 lesson in the current report: the rollout check sees only the next battle round.
- A rules mismatch on record before 02:59: the round-4 charge_low_odds panel (commit f9dbb8e, 2026-10-30 20:55) found that the AI applies a 10e charge-time overwatch cost (T7-51) that the 11e engine does not apply [commit f9dbb8e message; S:39]. CORRECTED: the charge study (separator workflow) reported its other mechanisms (FURY never priced, no post-roll decline, HI cost) only at 03:19-03:2x, after protocol v2 [commit 7736b71, 03:19:00; S:244-253]; do not list it as pre-02:59 context.
- No units in reserve at the start of the bench fixtures (84/84 deployed), on record before 02:59 [S:109 (02:13); commit 4bf2281 (2026-10-30 21:01)]. CORRECTED: "no attached leaders" was first recorded by the charge study at 03:19-03:2x, after protocol v2 [commit 7736b71; S:254].
- Small shipped gains per round so far: round 2 none, round 3 0.0, round 4 +0.80 with CI including 0 (sections 1a, 1c; report for round 2).

**The 6 rules, one line each:**
- **V2-1 Bench-reach gate.** Before design or bench, a cluster's decision type and each fix's own log tag must reach >= 1.0 line per game over 6 gate games (1 pair per fixture, seeds 91000/91100/91200); below -> PARK (code kept, FIX_ param 0). [P2:14-28]
- **V2-2 Sequential bench.** Each new arm plays the shipped AI at looks of 124 / 248 / 372 pairs; ship only if z >= 3.710 / 2.512 / 1.993 (Lan-DeMets O'Brien-Fleming, one-sided alpha 0.025) and no fixture 95% CI wholly below 0; non-binding futility stop if pooled E <= 0 at look 1 or 2. Power: true gain of 1.0 / 2.0 / 2.8 / 3.24 final SEs -> 16% / 49% / 78% / 88%; ~80% power for true gains of about 0.7-1.5 VP. [P2:30-51]
- **V2-3 Longer value check.** Before a finding enters a panel, re-check it at horizon 2 (two battle rounds; to game end if the decision is in round 4 or 5) with 24 seeds, seed base 5300; CONFIRMED-H2 only if the 95% CI lower bound > 0, else FADED and dropped. [P2:53-62]
- **V2-4 11e rules audit.** List every rule assumption in AIDecisionMaker.gd, compare it with the engine and the 11e core rules, verify each mismatch adversarially, rank it; clear AI-side fixes go behind FIX_<NAME> (0 = old behaviour) with a failing-first test, all in one bundle arm; engine-vs-rules defects are listed, not fixed. [P2:64-74]
- **V2-5 Broader bench.** Reserve fixtures become an extra gate for reserve-dependent fixes once a review says "usable", fixture_check passes and smoke games show no errors; one more faction fixture is proposed only (not run). [P2:76-83]
- **V2-6 Stop rule.** Round-5 gain = pooled E of the round-5 bundle that ships under V2-2 (0 if none); if <= +0.5 VP, no new critic sweeps or rounds; instead propose (not run) a parameter-tuning track with cost and time. [P2:85-90]
- Standing rules unchanged: no PRs; push only to claude/awesome-clarke-31p54m; never claim a result not run; never remove debug logs; wait on conditions; archive each sibling session after reading. [P2:92-95]
- Decision tool: `.ai_lab_work/decide_v2.py` (looks by seed range, z vs 3.710/2.512/1.993, fixture safety, futility), written 03:26 and smoke-tested on V12F data (tooling test only). [S:259; decide_v2.py lines 1-7]

---

## 3. Round 5 (sweep cases committed 2026-10-30 23:49 to 2026-10-31 00:16; round closed 2026-10-31 08:57)

### 3a. Sweeps
- 16 sweeps r5c00-r5c15 on `1322dc2` (= 1.56.7 / V10 AI), seeds 7475-7490; results in `.ai_lab_work/results_r5/`. [S:30]
- Matchups: r5c00-r5c05 Custodes mirror (s7475-7480); r5c06-r5c11 Orks mirror (s7481-7486); r5c12-r5c13 Custodes vs Orks (s7487-7488); r5c14-r5c15 Orks vs Custodes (s7489-7490). [S:50, 56, 58, 65, 67, 71 (cus); S:336, 319, 363, 121, 344, 110 (ork); S:99, 103, 117, 101 (mixed)]
- Sweep armies: the current `40k/armies/Orks_2000.json` (War Horde) and the current `custodes_lions`, not the bench lists. [S:360-361]
- **(derived)** 109 rollout jobs at 12 seeds: **7 clear**, **8 harmful**, 18 with all 12 seeds identical, the rest neutral. Method as in 1b, on results_r5/*.txt.
  - Clear: s7475 r3 +11.83 [2.26, 21.40]; s7477 r1 +8.42 [1.40, 15.43] (drift); s7480 r1 +3.92 [1.25, 6.59]; s7480 r2 +7.67 [0.80, 14.53]; s7482 r1 +4.58 [1.41, 7.76]; s7484 r1 +5.33 [1.96, 8.71]; s7487 r2 +5.33 [0.96, 9.70].
  - Harmful (the AI was right): s7478 r2 -8.17; s7479 r1 -3.92; s7481 r1 -9.33 and -18.50 (Lootas advances); s7483 r1 -3.92 (corridor screen); s7485 r1 -2.92 (backfield screen); s7489 r1 -5.50 (Mek reinforcement); s7490 r1 -3.83 (Lootas keep-hold).
- Round 5 closed at 08:54-08:57 when the last sweep (r5c08: 9 jobs, no clear finding) reported. [S:363]
- Measured-position library after round 5: 554 positions = 44 clear, 42 harmful, 468 neutral. **(derived)** count of `class` in tools/ai_lab/r5_designs/measured_positions.json at `84d65b2`. (507 positions at the first panel inputs, commit fa935da.)

### 3b. Clusters (inputs pushed `fa935da` 02:13 and `110a854` 02:50; base `12e0753`)
| Cluster | Findings (24-seed h1 unless noted) | Guardrails | Decision-type reach, per game (V10 both seats, 6 games) |
|---|---|---|---|
| marginal_oc | s7463 r1 +4.50 [1.34, 7.66]; s7475 r3 +8.00 [3.15, 12.85]; s7478 r3 +5.58 [1.41, 9.76] | 7 | 72.5 (cus 49, asy 69, ork 99.5) |
| charge_target | s7480 r3 +5.75 [1.46, 10.04] | 4 | 12.33 (cus 16, asy 18, ork 3) |
| ranged_hold_vs_centre | s7462 r1 +5.62 [3.42, 7.83]; s7463 r1 +4.79 [2.50, 7.09] | 6 | 8.83 (cus 2, asy 4.5, ork 20); "holds for Heavy weapon bonus" = **0** |
| attack_move | s7475 r2 +4.00 [1.04, 6.96]; s7455 r2 +5.92 [1.30, 10.53] (36); s7421 r2 +9.81 [6.57, 13.04] (36) | 5 | 44.17 (cus 33, asy 53.5, ork 46) |

[findings/guardrails: tools/ai_lab/r5_designs/fix_args_r5.json clusters; reach: `.ai_lab_work/r5_panel/reach_v10.txt` lines 2-5 (reach session 04:13, S:288-293). s7462 r1: fix_args_r5 prints +5.62 and confirmed.txt +5.63; the raw value is 5.625 (RC/pr10_2.txt).]
- All 4 clusters pass the V2-1 cluster gate (>= 1.0/game) at the decision-type level. The binding gate is the fix gate (the winner's own tag). [S:291-293]
- Screen cluster PARKED (screens need enemy reserves; bench fixtures have 0 units in reserve, verified 84/84 deployed). Corridor-block screens do not need reserves, but the block finding was single. [S:109, S:111]
- Charge low-odds study (separator workflow): **"no separator"** between over-charges and right charges over 77 positions; the s7470_1 harmful twin did not replicate on 12 fresh seeds (-0.83 [-3.81, 2.14]); its mechanisms went to the V2-4 audit. [tools/ai_lab/r5_designs/charge_separator_brief.md line 3; commit 7736b71; S:244-251]

### 3c. The 4 judge panels (each: 3 designs, 2 reviews per design (game lens + code lens), 1 judge; v1 rules)
Designer one-pair bench fires: marginal_oc narrow 0 / root 0.5 / game 0; charge_target narrow 45.5 / root 104 / game 245 (score-change lines, not decisions); attack_move narrow 0 / root 0 / game 1; ranged_hold game 0 / narrow 0 / root 19. All 12 designs: 0 harmful moves, tests ok. [.ai_lab_work/r5_panel/design_msgs/*.txt]

| Panel | Commit | Reviews (verdicts) | Winner; judge totals | Required changes | Outcome |
|---|---|---|---|---|---|
| marginal_oc | 16b02ca | 5 drop, 1 revise | **none**; totals game 3, narrow 2.5, root 2.3 | 6 (only if revived) | Nothing merges. All (a) holder-release gates count an attached leader (Blade Champion C on Guard Beta) as staying; s7475's flip is also a replay artifact (COORD-4 plans once per phase); bench reach ~0. [S:312-318] |
| attack_move | 18512c2 | narrow revise/drop; root revise/revise; game drop/revise | narrow (conditional); totals narrow 4, game 3.7, root 3 | 7 | Judge expected PARK (~0.3 fires/game; 0 in 6 Custodes bench games). **Dropped at h2** (05:39): s7455 r2 +4.54 [-5.18, 14.26] not confirmed, and s7475 r2 had faded (-3.00 [-9.10, 3.10]); no finalizer. [S:320-325, S:340-341] |
| charge_target | 856d61b (panel), be845fa (final) | all 6 revise | narrow; totals narrow 29, root 25, game 24 | 6 in panel.json (STATUS counts 5; the 6th is the real-save guard tests) | Finalized on 1.56.8; **V2-1 fix gate FAIL 0.33 changed declarations/game** (cus 0.5, asy 0.5, ork 0.0) -> **PARKED**. [S:326-330, S:352] |
| ranged_hold_vs_centre | 36b8626 | narrow ok/revise; root drop/revise; game revise/ok | game; totals game 4.14, narrow 3.43, root 2.71 | 8 (+4 optional grafts) | **PARKED, no finalizer**: corridor branch dropped at h2 (s7463 r1 mov2_3 -1.63 [-4.35, 1.10]); Heavy branch kept (s7462 r1 +6.25 [3.48, 9.02]) but has **0 bench reach** (no [HEAVY] weapon in any bench list). [S:355-357, S:360] |

[reviews/winners/totals/required-change counts: tools/ai_lab/r5_designs/*/panel.json (reviews[].verdict, verdict.winner, verdict.scores[].total, len(verdict.required_changes)). Totals are on each judge's own scale, so do not compare them across panels: charge_target's totals equal the sum of five 0-10 scores (checked: narrow 6+5+4+7+7 = 29); attack_move and ranged_hold state "total = (evidence + generality + 2 x full_game_safety + 2 x bench_reach + code_quality) / 7" in verdict.reasons; marginal_oc states no formula.]

**charge_target final (be845fa; `tools/ai_lab/r5_designs/charge_target/final.json`):**
- Base 1.56.8 = e12e6e8; param FIX_CHARGE_TARGET. All judge required changes applied (depletion gate <= 0.5 x starting wounds + 2x ratio; CHARACTER / kill-card exemption; Attached-unit folding; CT-COMBO only when the charger cannot engage both; decision-level log; real-save guard tests).
- Decision check: s7480 r3 P2 changes from "Allarus charge Allarus + Allarus #2 (targets after the roll)" to "charge Blade Champion Alpha" = the measured alternative (+5.75 [1.46, 10.04] n24). 8 guardrails unchanged, incl. s7431 r3 (keeps Blade Champion Alpha).
- Tests: test_ai_fix_charge_target 30 passed / 0 failed; on the SHIP copy 24 passed / 6 failed (fails first).
- Fix gate (1 pair per fixture, seeds 91001/91101/91201): changed declarations cus 0.5, asy 0.5, ork 0.0, **pooled 0.33/game < 1.0 -> pass false**. Evaluation-level [CHARGE_TARGET_EVAL] lines cus 8.0, asy 4.5, ork 0 (pooled 4.17) for information. Gate margins: cus E -1.0, asy 0.0, ork 0.0 (noise).
- Risk seen: one changed declaration (cus M1) was followed by a failed charge move (CT-COMBO risk).
- Verdict not_ready -> PARKED; code kept as the committed final.patch, not applied to AIDecisionMaker.gd. [final.json fix_gate, tests, verdict; S:352]

**ranged_hold_vs_centre Heavy branch (verified on decoded bench saves):** 0 occurrences of "heavy" in mirror_custodes (22 units / 52 weapons), asym (28 / 85), mirror_orks (34 / 118). [S:357]

### 3d. Round-5 result and the stop rule
- **Round-5 shipped gain = 0**: marginal_oc none; attack_move dropped at h2; charge_target parked (gate 0.33); ranged_hold parked (corridor branch dropped at h2, Heavy branch 0 bench reach); r5c08 no clear finding. [S:364]
- **V2-6 stop rule triggered at 08:57**: no new critic sweeps or rounds; tuning proposal prepared instead (section 8). [S:364]
- Uncovered CONFIRMED-H2 findings left for any later round (cluster reach first): s7421 r2 centre denial +14.83; s7459 r1 Lootas advance-flip of the enemy home +4.58; s7480 r1 sole holder home -> centre +5.71. [S:342-343] NOTE (check step): for s7459 r1 the +4.58 is the value of the alternative (Lootas Alpha holds obj_home_1), not of the AI's advance-flip [CH2:2]. S:342-343 calls these findings "uncovered" (no design covers them); s7421 r2 was an attack_move finding and s7480 r1 an extra marginal_oc finding.

---

## 4. Horizon re-checks

### 4a. pr10: 24-seed, horizon-1 re-check (launched 00:30, complete 02:48): 9 confirmed, 2 faded [S:72, S:126]
| Job | 12 seeds | 24 seeds | Result |
|---|---|---|---|
| r5c02 s7477 r1 P1 mov2_0 (Prosecutors -> Advance obj_nml_1) | +8.42 [1.40, 15.43] | +6.38 [1.78, 10.97] (drift) | confirmed |
| r5c03 s7478 r3 P2 mov1_5 (CG Beta) | +7.58 [-0.60, 15.77] | +5.58 [1.41, 9.76] | confirmed |
| r5c05 s7480 r3 P2 charge_1_6 (Allarus targets) | +6.17 [-0.33, 12.66] | +5.75 [1.46, 10.04] | confirmed |
| r4c12 s7463 r1 P2 mov1_2 (Kommandos) | +10.92 [6.73, 15.11] | +4.50 [1.34, 7.66] (drift) | confirmed |
| r5c00 s7475 r3 P1 mov2_5 (CG Beta holds centre) | +11.83 [2.26, 21.40] | +8.00 [3.15, 12.85] | confirmed |
| r4c12 s7463 r1 P2 mov2_3 (Lootas corridor block) | +4.17 [0.73, 7.60] | +4.79 [2.50, 7.09] | confirmed |
| r5c00 s7475 r2 P1 mov2_2 (CG Alpha toward charge target) | +5.33 [-1.10, 11.77] | +4.00 [1.04, 6.96] | confirmed |
| r4c11 s7462 r1 P2 mov1_0 (Lootas Heavy hold) | +7.00 [3.91, 10.09] | +5.63 [3.42, 7.83] | confirmed |
| r5c05 s7480 r1 P1 mov1_0 (CG Gamma sole holder) | +3.92 [1.25, 6.59] | +2.38 [0.10, 4.65] | confirmed (weak) |
| r4c11 s7462 r1 P1 shooting_2_5 (Lootas target) | +2.33 [0.28, 4.39] | +0.04 [-1.46, 1.54] | faded |
| r5c05 s7480 r2 P1 mov2_3 (CG Beta advance flip) | +7.67 [0.80, 14.53] | +0.96 [-3.42, 5.34] | faded |
[C1:1-9; F1:1-2; RC/pr10_0..5.txt]

### 4b. V2-3 horizon-2 re-checks: 24 seeds each, --horizon 2, --seed-base 5300; all 23 jobs status ok, 24/24 applied
Batch pr12h2 (commit `e4f759d`, 20 jobs = 7 v2 findings + 13 panel findings as information only; 10 shards) and batch pr13h2 (commit `84d65b2`, 3 jobs). [S:231, S:237, S:365; .ai_lab_work/r5_panel/pr12h2_purpose.json, pr13h2_purpose.json]

| # | Job (sweep, seed, round, player, decision) | Purpose | Earlier value (seeds) | h2 E [95% CI] | Drift at h2 | Outcome | Source |
|---|---|---|---|---|---|---|---|
| 1 | r4c08 s7459 r1 P1 mov2_2 Lootas advance-flip enemy home | v2 | +4.83 [1.93, 7.74] (12) | **+4.58 [0.37, 8.80]** | no | CONFIRMED-H2 | RC/pr12h2_0; CH2:2 |
| 2 | r5c05 s7480 r1 P1 mov1_0 CG Gamma sole holder | info marginal_oc extra | +2.38 [0.10, 4.65] (24) | **+5.71 [0.08, 11.33]** | no | CONFIRMED-H2 | RC/pr12h2_0; CH2:3 |
| 3 | r4c08 s7459 r2 P2 charge_1_6 Beast Snagga 28% charge | v2 | +6.67 [-0.69, 14.03] (12) | **+5.21 [0.30, 10.12]** (2/24 identical) | no | CONFIRMED-H2 | RC/pr12h2_1; CH2:4 |
| 4 | r5c05 s7480 r3 P2 charge_1_6 Allarus targets after roll | info charge_target | +5.75 [1.46, 10.04] (24) | **+11.54 [5.53, 17.55]** | no | CONFIRMED-H2 | RC/pr12h2_1; CH2:5 |
| 5 | r5c12 s7487 r2 P2 charge_1_3 Kommandos 28% charge | v2 | +5.33 [0.96, 9.70] (12) | -0.08 [-6.80, 6.63] | no | FADED | RC/pr12h2_2; FH2:6 |
| 6 | r4c10 s7461 r3 P2 charge_1_6 Battlewagon 2 targets | info charge_target extra | +3.75 [-1.77, 9.27] (12) | +0.08 [-3.55, 3.72] (2/24 identical) | no | not confirmed | RC/pr12h2_2; FH2:7 |
| 7 | r4c14 s7465 r1 P2 mov1_2 Gretchin backfield screen | v2 (screen) | +5.50 [1.56, 9.44] (12) | **+11.79 [6.87, 16.72]** | no | CONFIRMED-H2 (reserve track) | RC/pr12h2_3; CH2:6 |
| 8 | r4c11 s7462 r1 P2 mov1_0 Lootas Heavy hold (ranged_hold F1) | info ranged_hold | +5.63 [3.42, 7.83] (24) | **+6.25 [3.48, 9.02]** | no | CONFIRMED-H2 | RC/pr12h2_3; CH2:7 |
| 9 | r4c14 s7465 r2 P1 charge_1_4 Stormboyz 2-target charge | v2 + info charge_target | +6.75 [1.62, 11.88] (12) | -1.13 [-8.35, 6.10] | no | FADED | RC/pr12h2_4; FH2:10 |
| 10 | r4c12 s7463 r1 P2 mov2_3 Lootas corridor block (F2) | info ranged_hold | +4.79 [2.50, 7.09] (24) | -1.63 [-4.35, 1.10] | no | FADED -> corridor branch dropped | RC/pr12h2_4; FH2:11 |
| 11 | r5c09 s7484 r1 P1 mov1_0 Burna Boyz backfield screen | v2 (screen) | +5.33 [1.96, 8.71] (12) | **+8.00 [3.78, 12.22]** | no | CONFIRMED-H2 (reserve track) | RC/pr12h2_5; CH2:8 |
| 12 | r4c09 s7460 r1 P1 mov2_0 Lootas Heavy hold (F3) | info ranged_hold | +2.58 [0.19, 4.98] (12, drift) | +6.00 [1.60, 10.40] | **yes** | not confirmed (drift) | RC/pr12h2_5; FH2:12 |
| 13 | r5c02 s7477 r1 P1 mov2_0 Prosecutors (parked screen) | v2 | +6.38 [1.78, 10.97] (24, drift) | +3.46 [-3.33, 10.24] | **yes** | FADED | RC/pr12h2_6; FH2:1 |
| 14 | r5c00 s7475 r2 P1 mov2_2 CG Alpha toward charge target | info attack_move | +4.00 [1.04, 6.96] (24) | -3.00 [-9.10, 3.10] | no | FADED (sign flips) | RC/pr12h2_6; FH2:2 |
| 15 | r4c12 s7463 r1 P2 mov1_2 Kommandos reinforce | info marginal_oc | +4.50 [1.34, 7.66] (24, drift) | +4.88 [-0.07, 9.82] | **yes** (raw file) | not confirmed (borderline) | RC/pr12h2_7; FH2:8 |
| 16 | r4c04 s7455 r2 P1 mov2_4 CG Beta toward charge target | info attack_move | +5.92 [1.30, 10.53] (36) | +4.54 [-5.18, 14.26] | no | FADED -> attack_move dropped | RC/pr12h2_7; FH2:9 |
| 17 | r5c00 s7475 r3 P1 mov2_5 CG Beta holds centre | info marginal_oc | +8.00 [3.15, 12.85] (24) | +6.67 [-0.34, 13.67] (2/24 identical) | no | not confirmed (borderline) | RC/pr12h2_8; FH2:5 |
| 18 | sweep2 s7421 r2 P1 mov2_1 CG Gamma centre denial | info attack_move | +9.81 [6.57, 13.04] (36) | **+14.83 [7.13, 22.53]** | no | CONFIRMED-H2 | RC/pr12h2_8; CH2:1 |
| 19 | r5c03 s7478 r3 P2 mov1_5 CG Beta | info marginal_oc | +5.58 [1.41, 9.76] (24) | +4.54 [-4.49, 13.57] | no | not confirmed | RC/pr12h2_9; FH2:3 |
| 20 | r4c03 s7454 r3 P2 mov1_3 CG Gamma | info attack_move extra | +21.50 (36, on V9) | -3.42 [-9.62, 2.78] | **yes** | not confirmed (drift: V10 already sends Gamma elsewhere) | RC/pr12h2_9; FH2:4 |
| 21 | r5c07 s7482 r1 P1 mov2_0 Beast Snagga backfield screen | v2 batch 2 | +4.58 [1.41, 7.76] (12) | +2.08 [-2.03, 6.19] | no | FADED | RC/pr13h2_0; FH2:15 |
| 22 | r5c06 s7481 r1 P1 mov2_1 Beast Snagga backfield screen | v2 batch 2 | +4.42 [-0.34, 9.17] (12) | +0.96 [-7.39, 9.31] | no | FADED | RC/pr13h2_1; FH2:14 |
| 23 | r5c07 s7482 r3 P2 charge_1_6 Lootas 42% charge | v2 batch 2 | +1.75 [-0.66, 4.16] (12) | +0.75 [-2.06, 3.56] (6/24 identical) | no | FADED | RC/pr13h2_2; FH2:13 |

Notes:
- FH2:8 does not mention drift for row 15; the raw file RC/pr12h2_7.txt has `"drift":true` (the pr10 run also had drift, C1:4).
- "Earlier value" sources: 24-seed values = pr10 (C1/F1, RC/pr10_*); 36-seed values = fix_args_r5.json / fix_args_r4.json; 12-seed values = the sweep files results_r4/*.txt and results_r5/*.txt (rows 3, 7, 12 are not in CH2/FH2).
- Raw h2 E values to 3 decimals: 4.583, 5.708, 5.208, 11.542, -0.083, 0.083, 11.792, 6.25, -1.125, -1.625, 8.0, 6.0, 3.458, -3.0, 4.875, 4.542, 6.667, 14.833, 4.542, -3.417, 2.083, 0.958, 0.75 (rows 1-23). [RC files]

**Tallies (derived from CH2 = 8 lines, FH2 = 15 lines, and the purpose files):**
- **8 of 23 CONFIRMED-H2**; 15 not (4 of them with drift: rows 12, 13, 15, 20). Of the 15, FH2 labels 6 NOT CONFIRMED-H2 (rows 6, 12, 15, 17, 19, 20) and 9 FADED-H2 (rows 5, 9, 10, 13, 14, 16, 21, 22, 23).
- **Sign changes (h2 E has the opposite sign to the earlier E): 5 of 23** — rows 5 (s7487 r2 +5.33 -> -0.08), 9 (s7465 r2 +6.75 -> -1.13), 10 (s7463 r1 corridor block +4.79 -> -1.63), 14 (s7475 r2 +4.00 -> -3.00), 20 (s7454 r3 +21.50 -> -3.42, drift). Of the 9 pr10-confirmed findings, 2 changed sign (rows 10 and 14).
- Batch pr12h2: 8/20 confirmed (v2 findings 4/7; information-only findings 4/13). Batch pr13h2: 0/3. [S:377]
- Of the 9 findings confirmed by the pr10 horizon-1 re-check (4a), 3 were confirmed at h2 (rows 2, 4, 8).
- By class: screens 2/5 confirmed (s7465, s7484; S:377); charges 2/6; marginal_oc 1/4 (0 of the panel's own 3); attack_move 1/4; ranged_hold 1/3; Lootas advance-flip 1/1.

---

## 5. V2-4 11th-edition rules audit (commit `585cbbc`, 2026-10-31 06:18)

- Workflow `wf_040c9458-7a8`: 6 topic auditors -> 6 adversarial verifiers -> 1 ranker (13 agents); read-only, **no games**. Rules text: wahapedia 11e core rules snapshot `.ai_lab_work/rules11e/core_rules_11e.txt` (267 KB). [RA:3; S:233, S:346; rules_audit_11e.json "method", "rules_source"]
- **75 items** from 6 topics (charges 13, movement/keywords 11, army rules 10, reserves 13, objectives 13, stratagems 15). **71 confirmed, 4 refuted** (CH-08, ADV-02, movement CH-01, OC-11), 0 uncertain. **51 ranked** entries (46 AI_vs_ENGINE, 5 AI_vs_RULES). **13 CLEAR fixes.** **22 engine-vs-rules defects** listed separately, not fixed. [RA:7, RA:9; rules_audit_11e.json: len(ranked) 51, len(engine_vs_rules) 22, len(refuted) 4]
- Line numbers refer to HEAD 856d61b; AIDecisionMaker.gd unchanged since e12e6e8, 27577 lines. [RA:15]
- Clear-fix criteria: AI_vs_ENGINE, high confidence, runs on the 3 standard fixtures, small change behind a new FIX_ param, failing-first test given. [RA:9]

**The 13 clear fixes (rank order; one line each) [RA:9, RA:19-34, RA:75-216]:**
1. **FIX_OBJ_AREA_REACH (OC-01)** — reach and contest arithmetic measure unit centroid to the objective marker (3.79"), but every bench objective is a terrain area that one model controls by any base overlap. Largest systematic mismatch; estimate +0.5 to +2 VP/game (not measured). [RA:75-84]
2. **FIX_CHARGE_OW_11E (CH-01+OW-01)** — every charge score is multiplied by a 10e charge-time Fire Overwatch penalty (T7-51) that the 11e engine never resolves; the main source (the Stompa) is TITANIC and could never overwatch. Raises charge willingness; VP sign open. [RA:86-95]
3. **FIX_OBJ_AREA_ON_OBJ (OC-03)** — target valuation reads "on objective" as centroid within 3.79" of the marker; 63% of real holders on bench terrain objectives are misread. Estimate +0.3 to +1 VP/game (not measured). [RA:97-106]
4. **FIX_OBJ_AREA_HOLD (OC-04)** — hold / charge-off / fall-back / chase gates use centroid-to-marker and OC sums without the hosting area. Estimate +0.2 to +1 VP/game (not measured). [RA:108-117]
5. **FIX_EOG_TIMING (OC-02)** — end-of-battle primary awards are priced as if they paid at the next scoring point in every round; affects about 48% of bench games. Estimate ~0.3-0.7 VP pooled (not measured). [RA:119-128]
6. **FIX_MOVE_TERRAIN_11E (TER-01)** — Normal/Advance moves of non-INFANTRY units are priced with the charge terrain cost and blocked by every terrain piece; the engine charges 2" difficult ground plus ascent and blocks only dense features over 2". Ork seats only. Estimate: small to moderate, negative for Ork seats (not measured) [RA:137]. [RA:130-139]
7. **FIX_HI_CHARGE_ODDS (CH-03+HI-01)** — Heroic Intervention is valued without the 2D6 charge roll; in full standard games 9 of 16 HIs failed. Estimate +0.2 to +0.6 VP (not measured). [RA:141-150]
8. **FIX_SECURED_AWARE (OC-05)** — secured objectives (14.03) are ignored. Sign uncertain. [RA:152-161]
9. **FIX_CO_NEXT_PICK (CO-01)** — Counteroffensive (2 CP) is bought to "fight next" even when alternation already gives that pick, or nothing is left to fight; 5 of 13 uses were pure waste. Estimate +0.1 to +0.5 VP (not measured) [RA:170]. [RA:163-172]
10. **FIX_PILEIN_TARGETS_11E (CH-09)** — pile-in and consolidation geometry use the 10e "closest enemy model of any unit"; the engine measures to pile-in targets only and rejects the move (5 PILE_IN and 6 CONSOLIDATE rejections in one measured game). Estimate: small (not measured) [RA:181]. [RA:174-183]
11. **FIX_CHARGE_REROLL_ODDS (CH-05+AR-03)** — Blade Champion charge odds ignore the free Swift Onslaught re-roll (need 9: 0.28 -> 0.48). Sign uncertain. [RA:185-194]
12. **FIX_ADV_ENGINE_PREDICATES (CH-02+ADV-01+AR-01)** — objective-race Advance tests read advance-and-charge / advance-and-shoot from ability text, not the engine predicates; wrong both ways on the Kult of Speed bench. Estimate: small positive expected (not measured) [RA:203]. [RA:196-205]
13. **FIX_WAAAGH_ADV_REROLL (AR-06; ranked 14th)** — Ork (and Blade Champion) Advance odds assume a plain D6; the engine gives a free re-roll the AI takes on 1-3 (P(D6 >= 3) 0.67 -> 0.83). Likely < 0.3 VP/game (not measured). [RA:207-216]
(Rank 13 is RS-01, From Golden Light timing: not a clear fix. [RA:33])

**Harness and bench facts from the audit (not fixed; flagged to the user) [RA:13; S:348]:**
- (a) **FGL seat attribution:** END_TURN_REDEPLOY (From Golden Light) for P2's unit is decided by P1's AI (AIPlayer.gd:2252; records log player 1 in 224/224). **Rapid Ingress:** evaluate_rapid_ingress never sets _current_player, so profile arms read the opponent's params. Any FGL fix is sign-inverted in an A/B arm until the decision goes to the owner's seat.
- (b) Bench rosters are 40kdc 1.0.19 Kult of Speed Orks and older Custodes datasheets with unattached Blade Champions; War Horde / Lootas / [HEAVY] / close-quarters items have 0 bench reach.
- (c) **The standard Custodes bench is not reserve-free after round 1:** FGL and On Gilded Wings put Allarus into reserves (~4 placements/game in the Custodes mirror). This changes the "bench cannot see reserves" premise behind V2-5.
- (d) **Bench Custodes faction aggression resolves to 1.0** (FACTION_AGGRESSION_CUSTODES 1.5 never used; SEED-REAL never runs on any seat).
- (e) **AI defenders never get the reactive shooting-stratagem window** (ShootingPhase.gd:2932-2933 opens it only for a HUMAN defender; 5-21 offers/game unanswered), so defensive-stratagem fixes cannot be measured. [also RA:227]
- (f) Suggested follow-ups: Custodian Guard abilities the AI ignores (Praesidium Shield ~22 fires/game; Stand Vigil ~36/game); engine-side AI policies the bench cannot A/B (Salvus 18", FURY constant score).

**The 22 engine-vs-rules items (report only) [RA:220-241]:** CH-13/HI-04/HI-03 (HI: no Fights First, target before the roll, Into the Fray 1 CP not 2); CO-02; HI-02 root (WALKER test); CR-01 engine part (Command Re-roll on battle-shock); GR-01; CI-01 (10e Tank Shock); SM-01 (Smokescreen timing); reactive window (AI defenders); TER-02; CQ-01; FLY (no take-to-the-skies); RS-02 (reserve arrivals locked for the whole round; Custodes mirror 121/224 games); RS-04 (FGL on bench Allarus, 1" test); destroyed reserve units stay IN_RESERVES + Rapid Ingress CP spent before validation; RS-11; RS-13; OC-08; OC-12; Burden of Trust range; consolidation all-candidates; IB-01 engine part; AR-02 (stale bench data).

**Refuted (4) [RA:243-248]:** CH-08 (+2" ER term is not an over-estimate); ADV-02 (already fixed in 1.56.8); movement CH-01 (gang-up seed never runs on the bench); OC-11 (round-1 positions do score; a tuning question).

---

## 6. The audit bundle (V2-4 fixes)

**Implementation.** Workflow `wf_194da67a-997` (launched 06:5x; resumed after a 09:0x container restart): 5 groups in worktrees (G_OBJ 3, G_MISC 3, G_CHG 3, G_FIGHT 2, G_ADV 2) -> adversarial review per group (re-runs fail-first) -> repair -> merge into `.ai_lab_work/audit_fix/bundle.patch` (11:33; AIDecisionMaker.gd + 13 tests) + flip.sh -> V2-1 fix gate. Only AIDecisionMaker.gd may change (the bench swaps only that file). 12 agents; status completed. [S:349, S:366, S:379; WF12 agentCount, status]
- Every new param at 0.0 = shipped 1.56.8 behaviour. [commit ca913e2]

**Reviews: 12 approve + 1 repaired.** [WF12 result.groups[].rev.fixes[].verdict]
- Approve: all 3 G_OBJ, all 3 G_CHG, both G_FIGHT, both G_ADV, FIX_EOG_TIMING and FIX_SECURED_AWARE; fail-first confirmed. [S:376]
- **FIX_MOVE_TERRAIN_11E: needs_changes** — a cross-seat leak: AIPlayer.gd:1699 (recompute after an Advance roll) and :2788 (staging retry) call AIDecisionMaker._compute_movement_toward_target directly for both seats, so a profile arm's fix acted on the base seat's units. [WF12 G_MISC rev]
- **Repair (option b):** new gate `_move_terrain_fix_on(unit)` = param on AND unit owner == _current_player; all 10 checks go through it; 2 new seat tests (fail-first: 21 passed / 2 failed on the pre-repair AI). Probe of 361 decisions: the pre-repair AI changed 175 of 361 decisions with the fix only in the opponent's profile; the repaired AI changed 0. Leak-game replay (Orks mirror seed 91201): repaired = 161 tags, all in P2's phases; pre-repair = 220 tags, 38 in P1's movement. Harness-side fix (route both calls through `_dm(player)`) still open: it needs a change to the shared AIPlayer.gd. [WF12 G_MISC repair.applied/tests/notes]

**Tests (bundle state, all 13 new consts 0.0): 23/23 test files pass.** [WF12 result.merged.tests; S:380]
- 13 new files: obj_area_reach 27/0, obj_area_on_obj 17/0, obj_area_hold 30/0, eog_timing 22/0, move_terrain_11e 23/0, secured_aware 16/0, charge_ow_11e 11/0, hi_charge_odds 11/0, charge_reroll_odds 11/0, co_next_pick 22/0, pilein_targets_11e 29/0, adv_engine_predicates 20/0, waaagh_adv_reroll 25/0.
- 10 existing fix tests: charge_ev 11/0, far_trip 11/0, held_dup 14/0, keeper_release 52/0, lone_flip 16/0, lone_trip 8/0, overcommit 8/0, r1_home_capture 29/0, reinforce_insurance 24/0, waaagh_advance_charge 10/0.
- **Caveat:** with all 13 fixes ON, 17 of 23 files pass; 6 have failing checks (far_trip 4, held_dup 1, lone_flip 1, keeper_release 1, r1_home_capture 8, waaagh_adv_reroll 2), because each test switches only its own fix. They must be updated before any ship. Not checked for the 11-fix AUD state. [WF12 result.merged.notes; S:380]

**Param-0 identity check:** SHIP vs a copy of 585cbbc, and SHIP vs the bundle at 0.0, asym seed 91101, both seat orders: same outcome, same **695-action** trajectory and same **330 decision records** (scores to 6 decimals). [WF12 result.merged.notes; commit ca913e2; S:380]

**V2-1 fix gate** (fixes ON in the candidate seat vs SHIP e12e6e8; 1 pair per fixture, seeds 91001/91101/91201; 6 games, all completed to round 5, 0 SCRIPT ERROR; game times cus 200/186 s, asy 375/323 s, ork 899/862 s). Counting rule pre-registered at 06:5x before gate data: a [FIX_<NAME>] line prints once per evaluation where the fix changes a value the old code used; pass = >= 1.0 line per game (evaluation level; looser than the decision-level count used for charge_target). [S:354; P2:105-106; WF12 result.merged.gate, notes]

| Fix | Lines/game (merge agent, primary count) | Cross-check count (where different) | STATUS.md count (S:379) | cus / asy / ork per game | Verdict |
|---|---|---|---|---|---|
| FIX_OBJ_AREA_REACH | 221.333 | – | 221 | 206 / 205 / 253 | PASS |
| FIX_OBJ_AREA_ON_OBJ | 114.167 | 121.3 | 121 | 149 / 96.5 / 97 | PASS |
| FIX_MOVE_TERRAIN_11E | 90.333 | – | 90 | 0 / 78 / 193 | PASS |
| FIX_ADV_ENGINE_PREDICATES | 33.667 | 34.8 | 35 | 15.5 / 27 / 58.5 | PASS |
| FIX_CHARGE_OW_11E | 34.5 | 41.2 | 41 | 9 / 62.5 / 32 | PASS |
| FIX_OBJ_AREA_HOLD | 32.833 | 48.2 | 48 | 42.5 / 35.5 / 20.5 | PASS |
| FIX_WAAAGH_ADV_REROLL | 18.333 | – | 18 | 3 / 18 / 34 | PASS |
| FIX_CHARGE_REROLL_ODDS | 17.667 | 18.3 | 18 | 52.5 / 0.5 / 0 | PASS |
| FIX_HI_CHARGE_ODDS | 11.5 | 11.7 | 11.7 | 14.5 / 12.5 / 7.5 | PASS |
| FIX_EOG_TIMING | 4 | 4.83 | 4.8 | 4 / 4 / 4 | PASS |
| FIX_PILEIN_TARGETS_11E | 1.167 | – | 1.17 | 0.5 / 3 / 0 | PASS (narrow; 7 lines in 6 games) |
| FIX_CO_NEXT_PICK | 0.833 | – | 0.83 | 1 / 0.5 / 1 | **PARK** (5 lines in 6 games) |
| FIX_SECURED_AWARE | 0 | – | 0 | 0 / 0 / 0 | **PARK** |

[WF12 result.merged.gate.per_tag_lines_per_game, per_tag_by_fixture, totals_6_games; notes (cross-check values); S:379 (the orchestrating session's own count, duplicates collapsed). Totals over the 6 games: REACH 1328, ON_OBJ 685, MOVE_TERRAIN 542, CHARGE_OW 207, ADV_PRED 202, HOLD 197, WAAAGH_ADV_REROLL 110, CHARGE_REROLL 106, HI 69, EOG 24, PILEIN 7, CO 5, SECURED 0.]
- **11 PASS, 2 PARKED.** Every gate line with a player id came from the candidate seat. [WF12 notes; S:380; commit ca913e2]
- 1-pair margins (noise, information only): cus E -11.0 (M1 -30, M2 -8), asy -3.5 (-41, -34), ork +12.0 (+7, -17); pooled -0.833. [WF12 result.merged.gate.E_per_pair; S:379]

**Commits and the bench arm.**
- **`ca913e2`** (12:27:25): 13 fixes behind FIX_ params, all OFF; 16 files, 5197 insertions, 43 deletions (AIDecisionMaker.gd 1418 changed lines; 13 new test files; tools/ai_lab/audit_fixes/flip.sh and flip_all_original.sh). [commit ca913e2]
- `tools/ai_lab/audit_fixes/flip.sh` (no args) turns ON the 11 gate-passing fixes; `--all` = all 13; never commit its result. [flip.sh header]
- **`544c693`** (12:27:56): arm **AUD** pre-registered in protocol_v2.md "Arm registrations", before its first game. Candidate = ca913e2 + flip.sh; base SHIP = e12e6e8 (1.56.8); V2-2 looks 124/248/372 on the registered seeds; --rules11e; difficulty 3; --max-seconds 1800 (2400 Orks mirror); decision by decide_v2.py with pattern 'aud_%s_SHIP_'; ship only on efficacy; no switch-off arms unless efficacy is crossed; no extra fixture gate (a later current-list fixture would be information only). If AUD ships: the 11 consts -> 1.0, a version_history entry, a windowed scenario + live screenshot, and the failing unit-test checks updated. [P2:97-116; commit 544c693]
- **V2-2 look 1 launched: 11 shards** (aud_cus_SHIP_0-2 seeds 95001-95054, 14 pairs each; aud_asy_SHIP_0-2 99001-99054; aud_ork_SHIP_0-4 94001-94088, 8 pairs each); sessions created 12:4x, FAILED none. [S:381-382; sessions.txt lines 101-111; creator_dirs/aud1/*.txt]
- Status at 12:46: shards running; no aud_* result in bench_results/ yet. A look took 91-112 min and 11.8-12.6 container-h in earlier rounds. [live session check; `ls .ai_lab_work/bench_results`; TT:150]

---

## 7. Reserve fixtures (V2-5) and the screen track

**Reserve fixtures — commit `72a14a5` (2026-10-31 04:22):** smoke "usable" + review "usable". [S:300; commit 72a14a5]
- Builder `40k/tests/make_2000pt_fixture.gd` gets two opt-in flags: `--reserves=ai` (runs the real FormationsPhase with the AI for both seats and puts the AI's own reserve picks into reserve) and `--base=<fixture>`. Without the flags the builder is unchanged (decoded saves and .meta identical on 4 configs). [commit 72a14a5; S:301]
- `mirror_custodes_2000_reserves_postdeploy`: Allarus A, Custodian Guard D + Blade Champion A (Warlord, attached), Custodian Guard A; all Deep Strike; 825/2000 pts, 4/11 units per side. `mirror_orks_2000_reserves_postdeploy`: Stormboyz C, D (Strategic Reserves), Deffkoptas A, B (Deep Strike); 410/1975 pts, 4/17 units. `asym_2000_reserves_postdeploy`: Custodes set (P1) + Ork set (P2). [tools/ai_lab/README.md lines 134-146]
- fixture_check passes only without --strict. Smoke: **7 full games, 0 SCRIPT ERRORs**; all Custodes reserves arrive in round 2; [SCREEN] deep-strike logic fires 3-6 times/game (vs 0-1 on the standard fixtures). [commit 72a14a5; S:303]
- Role: an EXTRA gate for reserve-dependent fixes; the 3 standard fixtures stay the ship gate. Prefer the Custodes and asym reserve fixtures (Deffkopta confound). [S:304; README lines 152-160]
- **Defects found (report; not fixed):** (1) ENGINE: destroyed reserve units keep IN_RESERVES (ScoringPhase P1-37) -> ghost arrivals in round 4, and Rapid Ingress on a destroyed unit costs CP; (2) a Rapid Ingress whose placement fails still costs 1 CP (no refund); (3) AI: Deep Strike / Rapid Ingress placements for oval-base Deffkoptas are rejected for walls (`_is_valid_reinforcement_position` has no per-model wall/oval check) -> those units are destroyed at the end of round 3; (4) AI: the movement-order comparator is not a strict weak ordering ("bad comparison function"); (5) bench logs carry MCP-bridge noise (run_lanes does not set GODOT_MCP_DISABLED=1); (6) bench fixtures' datasheets drifted from the current army lists (pre-existing). [S:305-309]
- Correction from the audit: the standard Custodes mirror is not reserve-free after round 1 (~4 placements/game). [RA:13 (c)]

**screen_vs_objective reserve-track finalizer — DONE at 13:56 (commit 233bdd2): PARKED. See section 11. The lines below are the 12:46 state.**
- Launched 09:1x (session created 09:05 UTC): round-4 winner "narrow" (parked) applied on 1.56.8 with judge required changes 1-5. [S:367; creator_dirs/resfinal_screen_vs_objective/final_screen_vs_objective.txt]
- Evidence given to it: s7465 Gretchin screen h2 +11.79 [6.87, 16.72] (CONFIRMED-H2); s7484 Burna h1 +5.33 (later h2 +8.00 [3.78, 12.22] CONFIRMED); s7482 h1 +4.58 and s7481 h1 +4.42 (both later FADED at h2). Guardrails (the screen was right): s7485 -2.92, s7483 corridor -3.92, s7408 -5.83. [S:367; S:377]
- Gate: V2-1 on the 3 RESERVE fixtures, 1 pair each, seeds 91000/91100/91200; pass = pooled >= 1.0 [SCREEN_VS_OBJECTIVE] decision lines per game; standard fixtures run for information. Then, per V2-5, a ship needs the V2-2 sequential test on the reserve fixtures AND no fixture 95% CI wholly below 0 on the 3 standard fixtures at 124 pairs. [S:367; P2:77-81]
- keeper_reach not run: it acts only inside _keeper_release_check, which is inert with FIX_KEEPER_RELEASE = 0 in 1.56.8. [S:367]
- Live status (get_session, 12:46 UTC): "finalizing narrow fix; 36/45 replays done, reserve gate next"; the remote branch tip is still 544c693 (no final.json pushed yet). [live session check; git ls-remote]

---

## 8. V2-6 parameter-tuning proposal (commit `5b00fe0`, 09:30; not run)

- Workflow `wf_a2eb71ab-c3d`: 8 agents, read-only, 0 games; revised after two reviews. [S:370; TT:1, TT:6]
- Trigger: round 5 closed at 08:57 with shipped gain 0 VP <= +0.5 VP. [TT:5]
- **Recommendation: HOLD.** No tuning before the V2-2 decision on the V2-4 bundle; afterwards at most ONE one-generation probe, once; do not run the drafted multi-stage track. [TT:11; S:370]
- **Probe design:** 8 candidates x 8 dims (sd 0.3 x default, clipped to default x (1 +/- 0.5)); race 6 pairs each (48 pairs); top 4 get 12 more pairs (48 pairs); pick = best pooled E over 18 pairs ("rule B"); then Stage C = V2-2 confirmation. 273 params screened offline to 30; 86 cannot act on these fixtures. [TT:91, TT:95-119]
- **Probe cost (estimates):** 8.0 engineering h (<= 14 h if T8 is built in full); 53-81 sibling sessions; 22.5-49.1 container-h (expected 31-36); $26-60 sibling LLM tokens + parent orchestration >= $13-20 (STATUS: ~$39-80); 3.4-6.6 h wall on 14 containers (expected 4.4-5.1 h). [TT:25; S:370; table TT:135-147]
- **Odds (simulated, rule B, sigma 10.26 VP per pair, 100,000 reps):** P(ship & true gain > 0) = 0.035 / **0.10** / **0.31** / 0.39 at tau 0.25 / 0.5 / 1.0 / 1.2 VP (mu 0); <= 0.015 in a near-null pool (tau <= 0.1), where most ships would be false. V2-2 alone needs a true gain of **1.08 VP for a 50% chance** (1.53 VP for 80%). The 5 measured code arms (pooled E -0.21 to +1.17) allow tau up to ~1.2 VP. [TT:12-23, TT:166-170, TT:206; S:370]
- **Drafted multi-stage CEM track:** 251-279 sessions, 86-110 container-h, 10.3-13.5 h; 3.6x the probe's container-h at 1 look (2.3x at 3 looks); adds only +0.004 / +0.015 / +0.086 to P(ship & gain > 0) at tau 0.25 / 0.5 / 1.0 -> do not run. [TT:26]
- **Tool defects found (offline):** cem_driver rates only the FIRST candidate per generation (shared season; later candidates n = 0) [TT:27, TT:54]; tuning tools never pass --rules11e (legacy Take and Hold + 10e deck) [TT:55] and default to difficulty 2 while the bench uses 3 [TT:56]; --max-seconds 400 (20.5% of 224 cus games ran longer) [TT:57]; ai_versions tag/season collision silently reports the first candidate's margins (fake-godot test: candidate B played 0 games and reported A's E 0.0; true +6.0) [TT:45]; Rapid Ingress / Epic Challenge never set _current_player [TT:66]; FGL decided by the unit's opponent (11.9 decisions per cus game) [TT:67]; AIPlayer.gd:1699 and :2788 call HEAD's AIDecisionMaker directly [TT:47]; determinism_check keys records by seed only [TT:77]. Hardening the loop tools: 7.75 h; other fixes 9.0 h. [TT:60, TT:78]
- Further reasons to hold: a ship would tune 3 bench matchups with 0 attached leaders, 0 [HEAVY], 86 of 273 params inert, and Kult of Speed Orks instead of the sweeps' Orks_2000. [TT:24]
- Earlier draft (not committed): `.ai_lab_work/tuning_track_draft.md`; found run_paired.py has no --rules11e and CEM/screen default to difficulty 2. [S:350]

---

## 9. V2-5 fixture proposal (commit `3ff20e3`, 12:04; rev. 2; not built, no games)

- Workflow `wf_15c5f8f0-6ed`: 6 agents, read-only, 0 games; rev. 2 after an adversarial review (needs_changes: 1 blocker, 5 majors, 8 minors). [S:378; FX:3]
- **Stale-bench finding (measured):** the 3 standard bench fixtures (and the 3 reserve fixtures) use **40kdc-data 1.0.19** rosters: custodes_lions at 4dea059 (2026-10-17) or earlier, 11 units / 42 models / 2000 pts; recon_stomps (Kult of Speed) old revision 17 / 77 / 1975. Sweeps and the shipped game use 40kdc-data 1.4.5 + the 11e codex import: custodes_lions 9 / 22 / 1850 with 3 attachments; Orks_2000 (War Horde) 20 / 106 / 1975 with 5 attachments; 29 official layouts vs the bench's single take_and_hold_mirror_1. [FX:62-71; S:378]
- Same-name units differ: Allarus 5 models M5 T7 W4 OC3 on the bench vs 3 models M7 T8 W6 OC2 in the sweeps; Gretchin 11 models OC2 vs 10 OC1; Stormboyz 5 vs 10 models; Mek Leader vs Support. [FX:73-77]
- **At current profiles the standard bench reaches 0/44 clear and 0/42 harmful measured positions.** [FX:16, FX:88]
- **The current `recon_stomps.json` sums to 17 / 75 / 2280 pts (over 2000).** [FX:66; re-checked by this agent: summing `40k/armies/recon_stomps.json` units gives 17 units, 75 models, 2280 pts; Orks_2000.json 20/106/1975; custodes_lions.json 9/22/1850]
- **Recommendation:** build `asym_custodes_warhorde_2000_postdeploy` first: current custodes_lions as P1 (9/22/1850) vs current Orks_2000 as P2 (20/106/1975). Not the Orks_2000 mirror, not the Space Wolves mirror (the V2-5 draft). [FX:8-11, FX:157-159]
- **Role:** a separate extra gate, never a pooled stratum; (a) generality / no-harm check for the V2-4 bundle only if the §4.2 text is committed before that arm's first game (AUD's first game has already started, so it is information-only for AUD, P2:112-113); (b) required cross-faction no-harm check for every fix that acts on Orks_2000 units. Pooling waits for a v3 with a rebuild of the stale standard fixtures. [FX:12-14, FX:163-170]
- Why option 2: datasheet reach 39/44 clear and 38/42 harmful (Orks mirror 16/44 and 25/42; SW mirror 5/44 and 4/42); contains the matchup where Lootas-to-centre alternatives measured harmful (8 positions, 3 harmful, mean -1.82 VP); most critic jobs (177 vs 153 Custodes mirror, 118 Orks mirror). [FX:17-23]
- **Cost (estimates):** engineering <= ~5.5 h; validation 1.0-1.6 container-h for 24 games; each 40-pair look 3.3-5.3 container-h (+26-45% on a standard 124-pair look of 11.8-12.6). 2.5-4 container-min per game vs 5-8 for an Orks mirror. [FX:24, FX:46-49]
- No fixture can un-park ranged_hold's Heavy branch (ceiling 0.5 changed decisions/game on option 2, 0 on the Orks mirror); that needs a V2-1 amendment. No confirmed finding is actionable on any option. [FX:25-45]
- Top risks: 1850 vs 1975 pts; the Orks always move second; an Orks-only fix acts in 1 game of 2 per pair; no attachments and no reserves; 420 Ork pts are Legends; 40 pairs detect only large harm (E below about -3.2 VP). [FX:50-56]
- Status: **awaiting the user's decision** (V2-5 says propose, do not run). [S:378]

---

## 10. Lessons (each with its evidence)

1. **Sweep rosters differ from bench rosters.** Sweeps use current Orks_2000 (War Horde) and current custodes_lions; the bench uses Kult of Speed Orks and older Custodes data. Confirmed findings often have ~0 bench reach; at current profiles the bench reaches 0/44 clear and 0/42 harmful positions. [S:360-361; FX:16, FX:62-71]
2. **Most horizon-1 findings are not confirmed at horizon 2.** 15 of 23 h2 findings were not confirmed (6 NOT CONFIRMED-H2, 9 FADED-H2); of the 9 findings confirmed at h1 (24 seeds), only 3 were confirmed at h2. CORRECTED: 5 of 23 changed sign; of the 9 pr10-confirmed findings, 2 changed sign (s7475 r2: +4.00 -> -3.00; s7463 r1 corridor block: +4.79 -> -1.63). [section 4b]
3. **The reach gate parks most critic-loop fixes.** Round 5: 0 of 4 clusters reached a bench (charge_target 0.33 changed declarations/game; ranged_hold Heavy branch 0 by construction; marginal_oc and attack_move designs 0-1 fires/game). The audit fixes mostly passed (11/13) because their gate counts evaluation-level lines, pre-registered as a looser rule. [section 3c; S:354; section 6]
4. **The bench cannot see attached leaders, [HEAVY] weapons or (mostly) reserves.** 0 leader attachments, 0 "heavy" strings, 84/84 units deployed at the start; yet From Golden Light AND On Gilded Wings put Allarus into reserves (~4 placements/game in the Custodes mirror) [RA:13 (c)]. [S:109, S:254, S:357; RA:13]
5. **Profile arms can leak across seats.** FGL is decided by the opponent; Rapid Ingress / Epic Challenge never set _current_player; AIPlayer.gd:1699/:2788 call the class directly (the MOVE_TERRAIN fix changed 175 of 361 opponent decisions before its repair). Extracted-copy bases avoid most of this. [RA:13; WF12 G_MISC repair; TT:46-47]
6. **v1 shipped on small, uncertain gains.** 1.56.7 at +0.80 [-1.00, 2.60]; 1.56.8 at +1.17 [-0.52, 2.86], z ~ 1.36; V2-2 now needs z >= 3.710 at look 1. [section 1c; S:286; P2:41]
7. **Switch-off arms isolate parts:** RI alone gave nothing (-0.21); with LF on it added +0.22. [S:93-95]
8. **No simple rule separates over-charges from right charges** (77 positions; the sign follows which mission pays). [charge_separator_brief.md line 3]
9. **Tool hygiene matters:** tag/season collision, first-candidate-only CEM, legacy rules at difficulty 2. [TT:27, TT:45, TT:55-56]
10. **Container restarts cost work:** a restart BEFORE 23:58 on 30 Oct lost the scratchpad log and a workflow (23:58 is when STATUS.md was rebuilt; no file records the restart time) [S:1, S:31]; the 09:0x restart (between 09:00 and 09:09) stopped two workflows (resumed from cache) [S:366].

---

## PENDING (render as "Result pending"; keys for the page: `aud_look1`, `screen_reserve`)

1. **`aud_look1` — AUD V2-2 look 1** (11 shards, 124 pairs, running since 12:4x). Decision by decide_v2.py: ship only if z >= 3.710 and no fixture 95% CI wholly below 0; non-binding futility stop if pooled E <= 0; otherwise continue to look 2 (248 pairs). Per-tag fire counts reported for information. [P2:41-45, P2:97-116; S:381-382] FILLED in the check step: see section 11 (formal decision CONTINUE at 14:29).
2. **`screen_reserve` — screen_vs_objective reserve-track finalizer:** final code, decision/guardrail checks (36/45 replays done at 12:46), V2-1 gate on the 3 reserve fixtures (pass >= 1.0 decision lines/game), then (if it passes) a V2-2 bench on the reserve fixtures + the standard-fixture no-harm check. [S:367; P2:77-81] FILLED in the check step: see section 11 (PARKED at 13:56, gate 0.17).
3. **User decision: the V2-6 tuning probe** (recommendation HOLD; at most one probe after the AUD decision). [TT:11]
4. **User decision: build the new fixture** `asym_custodes_warhorde_2000_postdeploy` (and commit the §4.2 pre-registration text before any game on it). [FX:8, FX:172-207; S:378]
5. If AUD ships: update the failing unit-test checks (6 files with all 13 on; not yet checked with the 11 AUD fixes on), add a version_history entry, a windowed scenario and a live screenshot. [P2:114-116; S:380]
6. Open harness/engine items (not in any track): route AIPlayer.gd:1699/:2788 through `_dm(player)`; route FGL to the owner's seat (T7); the 22 engine-vs-rules defects; the IngressMove UI flag bug; test_ai_objective_assignment_fixes 6/1 not in the known-failure list; the K card font draws '~' like a minus; `recon_stomps.json` over 2000 pts; a V2-1 amendment for once-per-game fixes. [WF12 G_MISC repair.notes; TT:67; RA:220-241; S:38, S:297-299; FX:66, FX:33]
7. The report itself: the next page is drafted, not published; publish after `aud_look1` and `screen_reserve` are filled. [S:383]

---

## 11. Update after 12:46 (added by the check-and-fix step on 2026-10-31; repo HEAD 233bdd2)

Citation key as above. `SF` = `tools/ai_lab/r4_designs/screen_vs_objective/final.json` (commit 233bdd2). `AIDM@e12e6e8:<n>` = `git show e12e6e8:40k/scripts/AIDecisionMaker.gd` line n. `DV1` = `.ai_lab_work/decide_v2_AUD_look1.json`.

**AUD look 1 (formal decision 14:29 = CONTINUE).**
- Shards saved: cus#1 13:04, cus#2 13:05, cus#0 13:07, asy#1 13:34, ork#1 13:47, ork#4 13:49, asy#0 13:50, ork#2 13:54, ork#0 13:54, asy#2 14:06, then ork#3 (archived) [S:384-395; archived.txt last lines].
- Decision [S:397; DV1]: 123/124 pairs (seed 94061 M2 timed out at the 2400 s cap; pair dropped as incomplete; "the decision does not depend on it"). cus n42 E -2.607 se 1.683 [-5.91, 0.69]; asy n42 E +1.452 se 1.729 [-1.94, 4.84]; ork n39 E +8.731 se 2.12 [4.58, 12.89]; pooled E +2.525, se 1.071, z 2.359 < 3.71 -> no efficacy; pooled E > 0 -> no futility; fixture_safe true; decision "continue". DV1 has "complete": false (123 < 124 pairs).
- Interim values at 13:23 and 14:24 (S:387, S:396; decide_v2_AUD.json) are NOT used on the page.
- Look 2: launched early at 14:24 as an operational step, not a decision; if look 1 had been futility/efficacy, the look-2 games would be discarded [S:396]. 11 look-2 sessions created at 14:3x, FAILED none [S:398].
- Diagnostic, information only, post hoc [S:399]: candidate advantage per pair, primary / secondary: cus -1.50 / -1.11; asy +0.17 / +1.29; ork +5.83 / +3.21. Fix lines per game: cus OBJ_AREA_REACH 233, ON_OBJ 205, HOLD 104, CHARGE_REROLL_ODDS 69, CHARGE_OW_11E 37, MOVE_TERRAIN 0; ork MOVE_TERRAIN_11E 307, OBJ_AREA_REACH 241, ADV_ENGINE_PREDICATES 54, WAAAGH_ADV_REROLL 34. Switch-off arms only after efficacy [P2 Arm registrations].

**screen_vs_objective reserve track (commit 233bdd2, 2026-10-31 13:56:08) = PARKED** [S:394; SF]:
- Base 1.56.8 = e12e6e8; judge changes 1-5 applied (required_changes[1..5].applied = true; [0] PARK is a shipping rule). Code kept as final.patch, not applied to AIDecisionMaker.gd.
- Tests: test_ai_fix_screen_vs_objective SHIP copy 7 passed / 2 failed; final 9 passed / 0 failed [SF tests.detail].
- Decision checks: 1 of 5 findings flips (s7467 r1 P2: Gretchin screens -> Gretchin advances toward obj_nml_2 = the measured alternative, +3.639 [1.82, 5.46] n36). s7465, s7484, s7482, s7481: no fire; their alternatives target obj_center while it is enemy-held, contested next move or a lost race, which the judge's RC3 excludes [SF decision_checks, risks[1]].
- 45 positions replayed with the final code: fires at 2 (s7467; s7436 r1 P1, unmeasured); no fire at any harmful position [SF extra_checks[2]].
- V2-1 gate on the 3 reserve fixtures: cus 0.0, asy 0.5, ork 0.0, pooled 0.17 lines/game < 1.0 -> pass false; standard fixtures 0.0 (information); 0 SCRIPT ERROR lines in all 12 gate game logs [SF fix_gate].
- Verdict not_ready: keep FIX_SCREEN_VS_OBJECTIVE = 0 (parked); "V2-5 reserve track: nothing ships" [SF verdict; S:394].

**Other facts used by the corrected page (verified in the check step):**
- FIX_R1_HOME_CAPTURE = 0.0 in 1.56.8, "PARKED (0): it fires 0 times in the three bench fixtures (every home is held at deployment)"; its evidence is s7468 r1 (+6.86 [4.45, 9.27], 36 rollouts) [AIDM@e12e6e8:1630-1646]. Also 0.0 in the V11, V11b and V12 patches [tools/ai_lab/r4_designs/v11/*.patch, v12/v12_from_v10.patch]. Commit d14614d: "R1-HOME-CAPTURE parked".
- FIX_R1_SUPPORT_ADVANCE evidence: s7451 r1 P2, a support squad walked a 3-turn trip to a contested centre; Advancing measured +5.86 VP [3.09, 8.63] over 36 rollouts [AIDM@e12e6e8:1647-1662; r1_home_capture/final.json decision_checks[1]: "Gamma moves (Normal) toward obj_center (reinforcing)" -> "Gamma ADVANCES toward obj_center" via [R1_SUPPORT_ADVANCE]; fix_args_r4.json clusters[6].findings[1]: "Custodian Guard Sodality Gamma moves toward obj_center"].
- 6 FIX_ params at 0 in 1.56.8: FAR_TRIP, OVERCOMMIT, KEEPER_RELEASE, R1_HOME_CAPTURE, R1_SUPPORT_ADVANCE, CHARGE_EV [`git show e12e6e8:...AIDecisionMaker.gd | grep "^const FIX_"`]. FIX_KEEPER_REACH, FIX_SCREEN_VS_OBJECTIVE and FIX_CHARGE_TARGET are not in AIDecisionMaker.gd at e12e6e8 or HEAD (patch files only).
- RI-RACE: a one-move reinforcement of a held_threatened objective keeps MOVE_RACE_LOSS_FACTOR of its objective value when the enemy OC that can stand in range after its next move is at least RI_RACE_LOST_RATIO x our OC there with this unit [AIDM@e12e6e8:1675-1695]; RI_RACE_LOST_RATIO = 1.5 [AIDM@e12e6e8:1708]; MOVE_RACE_LOSS_FACTOR = 0.5 [AIDM@e12e6e8:1957].
- FIX_OVERCOMMIT: the top-up takes its best other objective that still needs OC "and that it reaches no later" [AIDM@e12e6e8:1560-1573].
- s7437 r2 P2 Stormboyz 8% charge (the third open round-2 claim): 36 seeds E +1.5 [-0.67, 3.67], neutral [r4_designs/measured_positions.json]; fix_args_r4.json charge_low_odds hint: "round 3's low-odds charge finding faded with more seeds".
- s7437 r1 keeper finding raw E 7.305 [4.98, 9.63] n36 [r4_designs/measured_positions.json].
- Round-4 and round-5 counts re-derived from results_r4/*.txt and results_r5/*.txt: 185 / 20 clear / 12 harmful / 40 no signal; 109 / 7 / 8 / 18.
- Per-pair SD of the later benches: 9.6-11.3 VP (4 large code arms), sigma 10.26 used in the simulation [TT:160].
- Reserve fixtures: the Ork set (Stormboyz C, D; Deffkoptas A, B) is in both the Orks mirror and the asymmetric (P2) reserve fixture; Deffkopta Deep Strike placements are often rejected (walls) [tools/ai_lab/README.md lines 134-160].
- First round-1 bundle: 900 s per game; the round-1 re-test 2400 s [previous page version current.html, Limits].
- Engine-defect descriptions on the page come from RA:220-241.
- K-card texts verified on the embedded screenshots: before "Stormboyz advances to attack Prosecutor Squad (12.0" away — closing to charge range (0.0" after move))"; after "Stormboyz moves to attack Prosecutor Squad (12.0" away — closing to charge range (0.0" after move))".
- The 37 critic claims in the round-1 and round-2 tables are verbatim critic text: each matches a "Problem:" line in 40k/tools/llm_critic/runs/*/REPORT.md or a rollout-case "note" in 40k/tests/rollout_cases/r2c*/ (37 of 37 found).
- The 18 "AI did" quotes of 110 or 140 characters are cut by the tool; the page marks them with "…".
