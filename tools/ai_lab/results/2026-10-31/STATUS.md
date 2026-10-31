# AI lab status (rebuilt 2026-10-30 23:58 UTC after a container restart; the old scratchpad log is gone)

Work folder: /home/user/warhammer-40k-godot/.ai_lab_work (git-excluded via .git/info/exclude).
Branch: claude/awesome-clarke-31p54m. Push only there. No PRs. Never remove debug logs.

## Versions
V0 0633cc1 | V6 a1273d1 | V7D f38e43a (= shipped 1.56.6 AI) | V9 5e70bc2 | V10 12e0753 (AI) | V10S 1322dc2 (V10 shipped as 1.56.7)
V11 = V10 AI + tools/ai_lab/r4_designs/v11/v11_from_v10.patch (local ddaa5f8: V9R keeper-off + waaagh final + r1_home_capture final)
V11b = V10 AI + tools/ai_lab/r4_designs/v11/v11b_from_v10.patch (local 1e438b9 = V11 + review fixup of R1-SUPPORT-ADVANCE)

## Decisions so far
- Round 3: keeper fix not shipped (V9 = V7D in 124 pairs) -> FIX_KEEPER_RELEASE 0 (14eb69f).
- Round 4: V10 (LONE_FLIP + REINFORCE_INSURANCE) vs V7D, 124 pairs: cus +2.92 [-1.18, 7.02] n42; asy -0.80 [-2.59, 0.99] n42;
  ork +0.29 [-2.72, 3.30] n40; pooled +0.80 [-1.00, 2.60] -> RULE MET -> SHIPPED as 1.56.7 (57b5acc scenarios, 1322dc2 version
  entry). vs V0: pooled +0.54 [-1.43, 2.51].
- PRE-REGISTERED (23:12, before any arm data): (1) V10 by the round rule [done: shipped]. (2) Among {V10, LF-only, RI-only}, the
  branch keeps the one with the HIGHEST pooled E vs V7D that meets the rule on its complete bench (3 fixtures, same seeds).
  (3) V11 decided alone by the same rule. (4) V10 variant + V11 both pass -> combination needs a confirmation bench first.
  (5) Anything not shipped keeps its code, switched off. Added: V11's bench runs PRE-fixup code (ddaa5f8); any V11 ship needs a
  V11b confirmation bench first.

## Running (sibling sessions; list in sessions.txt)
- r4lf_<fx>_V7D (LF-only = V10 + profile FIX_REINFORCE_INSURANCE=0), r4ri_<fx>_V7D (RI-only = V10 + FIX_LONE_FLIP=0),
  r4v11_<fx>_V7D (V11 pre-fixup): cus complete for all three (restored in bench_results/), asy x3 + ork x5 each still running.
  Seeds = V10's: cus 95000/95020/95040 x14, asy 99000/99020/99040 x14, ork 94000..94080 step 20 x8.
  Interim: V11 cus -1.21 [-4.93, 2.50]; LF cus +1.05 [-0.34, 2.44]; RI cus +1.32 [-3.10, 5.74].
- Round-4 sweeps still running: r4c08, r4c10, r4c11, r4c14 (results -> results_r4/; clear findings -> pr10 queue).
  pr10 queue so far (from r4c12): r4c12/20261030_160506_r4c12_00__s7463_r1_p2_movement_1_2 (Kommandos reinforce obj_nml_2, +10.92,
  drift) and r4c12/..._s7463_r1_p2_movement_2_3 (Lootas screen, +4.17).
- Round 5: 16 sweeps r5c00-r5c15 on 1322dc2 (seeds 7475-7490), results -> results_r5/.
- LOST in the restart: charge-separator workflow (wu3tphk9e) -> relaunch with outputs in charge_r5/.

## How to process a sibling message
  cd .ai_lab_work && python3 save_shard.py <<'EOF' ... EOF ; echo "<label> <id> $(date -u +%H:%M)" >> archived.txt ; ./decide_all.sh
  then archive the session (mcp archive_session).

## Open follow-ups
- UI (pre-existing): the K card font draws '~' like a minus ('worth ~11 VP' reads as 'worth -11 VP').
- Candidate rules fix: phantom 11e charge-time overwatch cost (T7-51) - evidence says the AI over-charges, so bench alone if tried.
- Final ASD-STE100 report update (artifact https://claude.ai/artifact/YWRAdHeM7gBJTKAZJDnYZJ; old source file was in the lost
  scratchpad: re-read the artifact before republishing).

## Log
- 23:58 rebuilt work folder; restored 9 cus shards (LF/RI/V11) from the conversation; sessions.txt rebuilt from list_sessions.
- 00:00 charge-separator workflow RELAUNCHED (w2qwqyerf, wf_ab35adca-413), outputs in charge_r5/.
- 23:59 r4ri_asy_V7D#1 saved (archived).
- 23:59 CHECK-IN 8 done: all running sessions WORKING (r4c08 7/9, r4c10 5/9, r4c11 8/9, r4c14 6/10 rollouts; arms self-recovering from container kills). V11 vs V0 held (V11 cus -1.21; only worth it if V11 vs V7D passes). Check-in 9 at 01:00 (trig_01GomBXQTNjPdkaacYt3MbXd).
- 00:02 r4lf_ork_V7D#3 saved (archived).
- 00:05 r4v11_asy_V7D#1 saved (archived).
- 00:07 r5c03 (cus mirror s7478) saved (archived): no clear; HARMFUL s7478 r2 P1 Prosecutor flip-advance alt (-8.17: AI right); promising s7478 r3 P2 Beta advance capture +7.58 [-0.6,15.8] -> pr11 queue. pr10 queue rebuilt (2 r4c12 jobs).
- 00:07 r4lf_ork_V7D#2 saved (archived).
- 00:08 r4v11_ork_V7D#0 saved (archived).
- 00:11 r4v11_asy_V7D#2 saved (archived).
- 00:12 r4c11 (ork mirror s7462) saved (archived): CLEAR s7462 r1 P2 Lootas Alpha heavy-hold -> alt +7.00 [3.91,10.09]; CLEAR s7462 r1 P1 Lootas shooting target +2.33 [0.28,4.39]; near-harmful s7462 r1 P2 Lootas Beta advance race alt -3.83 [-7.69,0.03] (AI right). Both clear -> pr10 queue (4 jobs now).
- 00:12 r4ri_ork_V7D#0 saved (archived); r4c11 a_did text correction applied.
- 00:14 r5c02 (cus mirror s7477) saved (archived): CLEAR s7477 r1 P1 movement_2_0 +8.42 [1.40,15.43] (drift, a_did empty) -> pr11 queue.
- 00:14 r5c02 correction applied (last line identical 0 -> 5).
- 00:15 r5c01 (cus mirror s7476) saved (archived): no clear, no harmful (all 7 neutral).
- 00:15 r4v11_asy_V7D#0 saved (archived): V11 asy complete.
- 00:17 r4ri_asy_V7D#0 saved (archived).
- 00:17 r4lf_asy_V7D#1 saved (archived).
- 00:19 r4ri_ork_V7D#4 saved (archived).
- 00:19 RI-only now -0.38 pooled (fails). Prepared switch_lf_only.sh (FIX_REINFORCE_INSURANCE 0.0 + RI scenario pins fix on + version 1.56.8 + tests + 3 scenarios); run only if LF-only's complete bench beats +0.80 and meets the rule.
- 00:20 r4ri_ork_V7D#1 saved (archived).
- 00:20 r5c04 (cus mirror s7479) saved (archived): no clear; HARMFUL s7479 r1 P1 Gamma advance capture centre alt (-3.92 [-7.32,-0.51]: AI right).
- 00:22 r4lf_asy_V7D#2 saved (archived).
- 00:25 r5c00 (cus mirror s7475) saved (archived): CLEAR s7475 r3 P1 Beta holds centre under threat -> alt +11.83 [2.26,21.40]; promising s7475 r2 P1 Alpha +5.33 -> pr11 queue (4 jobs).
- 00:26 r4lf_ork_V7D#1 + #4 saved (archived). LF missing: asy_0, ork_0.
- 00:26 r4v11_ork_V7D#1 saved (archived).
- 00:29 r4ri_ork_V7D#3 saved (archived).
- 00:29 r5c05 (cus mirror s7480) saved (archived): CLEAR r1 P1 Gamma sole-holder hold +3.92 [1.25,6.59]; CLEAR r2 P1 Beta advance flip +7.67 [0.80,14.53]; promising r3 P2 Allarus 2-target charge +6.17 -> pr11 queue (7 jobs).
- 00:30 pr10 batch pushed (06663b2): 11 jobs (4 r4 + 7 r5). Creating 6 re-check sessions (shards 0..5/6, 24 seeds, base 5100, shipped AI). save_shard: RECHECK -> recheck/.
- 00:31 r4ri_asy_V7D#2 + r4v11_ork_V7D#2 saved (archived).
- 00:32 pr10 re-check: 6 sessions created (pr10_0..5).
- 00:33 r4ri_ork_V7D#2 saved (archived): RI-only bench COMPLETE.
- 00:34 r4lf_asy_V7D#0 saved (archived). LF missing: ork_0 only.
- 00:40 r4v11_ork_V7D#4 saved; r4c10 (ork s7461) saved: no clear; near-harmful r1 P2 Lootas Alpha capture advance (-6.42 [-13.19,0.35]: AI right). Both archived.
- 00:42 pr10_5 saved (archived): s7477 r1 P1 Prosecutors advance obj_nml_1 CONFIRMED (+6.38 [1.78,10.97] n24).
- 00:48 pr10_4 saved (archived): s7478 r3 P2 CG Beta -> obj_center move CONFIRMED (+5.58 [1.41,9.76] n24); s7480 r3 P2 Allarus charge BC only CONFIRMED (+5.75 [1.46,10.04] n24).
- 00:49 r4v11_ork_V7D#3 saved (archived): V11 bench COMPLETE.
### 00:52 — V11 bench COMPLETE (pre-fixup ddaa5f8): cus -1.21 [-4.93, 2.50] n42; asy -0.85 [-3.13, 1.44] n42; ork +2.74 [-0.47, 5.94] n40;
    pooled +0.23 [-1.58, 2.03] -> meets the rule (barely). RI-only COMPLETE: pooled -0.21 [-2.02, 1.60] -> fails. LF-only: 1 shard left
    (ork_0), now +0.98 [0.15, 1.82] vs V10 +0.80.
- PRE-REGISTERED 00:52 (before LF's last shard and before any combination data): V12 confirmation bench = the kept V10 variant (V10 or
  LF-only, by rule (2)) + V11b parts, merged as code with every switch kept. Two arms on the same 124 seeds vs V7D:
  C_full (FIX_WAAAGH_ADVANCE_CHARGE 1, FIX_R1_SUPPORT_ADVANCE 1) and C_waaagh (FIX_R1_SUPPORT_ADVANCE 0; reason: V11's gain is in the
  Orks mirror, the Custodes fixtures are negative, R1SA had the review's major defect and unmeasured shapes).
  Ship the arm with the highest pooled E vs V7D only if it meets the rule AND its pooled E is higher than the kept V10 variant's own
  pooled E on the same seeds; otherwise keep the V10 variant alone and leave the V11 parts switched off (code kept).
- 00:51 V12 MERGE workflow launched (wyz0egt3w, wf_4d82ceaf-240): V10 tip + V11b parts (diff bc57258..1e438b9) in wt_v12; outputs v12_from_v10.patch + v12_merge_report.json.
### 00:56 — ROUND-4 GROUP TEST DECIDED (pre-registered rule 2): V10 STAYS
- LF-only COMPLETE: cus +1.05 [-0.34, 2.44] n42; asy +0.05 [-0.66, 0.75] n42; ork +1.27 [-0.39, 2.94] n40; pooled +0.79 [0.03, 1.55].
- V10 (both): pooled +0.80 [-1.00, 2.60]; RI-only: -0.21 [-2.02, 1.60] (fails). Highest pooled E meeting the rule = V10 (+0.80 vs +0.79)
  -> no switch; switch_lf_only.sh NOT run. Note: LF-only has the same mean with much less spread (many identical pairs); RI adds spread
  and, alone, nothing. Interaction: E(V10) - E(LF) - E(RI) = 0.80 - 0.79 + 0.21 = +0.22 (RI only helps with LF on).
- V12 arms therefore use V10 as the base: C_full (no profile) and C_waaagh (FIX_R1_SUPPORT_ADVANCE=0); a V12 arm ships only if its
  pooled E > +0.80 and it meets the rule.
- 00:57 r4c08 (ork s7459) saved (archived): CLEAR r1 P1 Lootas advance-flip +4.83 [1.93,7.74]; promising r2 P2 Beast Snagga 28% charge +6.67 -> pr12 queue. Round-4 sweeps: only r4c14 left.
- 00:59 r5c12 (cus vs ork s7487) saved (archived): CLEAR r2 P2 Kommandos 28% charge +5.33 [0.96,9.70] -> pr12 queue (3 jobs). Charge findings growing (s7459 28%, s7487 28%).
- 01:00 CHECK-IN 9 done: 14 live sessions all WORKING (9 r5 sweeps, r4c14 at job 8/10, pr10_0..3). Benches all complete (V10 stays; V11 +0.23 -> V12 merge running). Check-in 10 at 02:01 (trig_011KA6hHLST2WYoQg31GzitY).
- 01:11 r5c15 (ork vs cus s7490) saved (archived): no clear; HARMFUL r1 P1 Lootas keep-hold alt (-3.83 [-7.04,-0.63]: AI right).
- 01:23 r4c14 (ork s7465) saved (archived): CLEAR r1 P2 Gretchin screen +5.50; CLEAR r2 P1 Stormboyz 2-target charge +6.75; HARMFUL r2 P2 Stormboyz 17% charge (-5.25: charging was right -> charge guardrail). ALL ROUND-4 SWEEPS DONE. pr12 queue: 5 jobs.
- 01:40 r5c13 (cus vs ork s7488) saved (archived): all 8 neutral (several 17% charges: no-charge alt not better -> charge guardrail evidence).
- 01:54 pr10_3 saved (archived): s7462 Lootas shooting FADED (+0.04); s7480 r2 Beta flip-advance FADED (+0.96).
- 02:02 V12 patch pushed (d14614d). 9 extra suites pass on V12. 22 bench prompts ready (r4v12f = C_full, r4v12w = C_waaagh/R1SA=0); creating sessions.
- 02:02 pr10_0 saved (archived): s7463 Kommandos -> centre advance CONFIRMED (+4.50 n24); s7475 r3 Beta leave centre -> obj_nml_1 CONFIRMED (+8.00 n24). Confirmed so far: 5.
- 02:05 V12 C_waaagh arm: 11 bench sessions created (r4v12w_*); C_full creator still running.
- 02:06 V12 C_full arm: 11 bench sessions created (r4v12f_*). V12 bench fully running (22 sessions). decide_all.sh now includes V12FvsV7D / V12WvsV7D.
- 02:13 ROUND-5 JUDGE PANELS: inputs pushed (fa935da: tools/ai_lab/r5_designs/fix_args_r5.json, measured_positions.json 507 positions). Clusters: marginal_oc (s7463 r1 +4.50, s7475 r3 +8.00, s7478 r3 +5.58, n24; 7 guardrails) and charge_target (s7480 r3 +5.75 n24 + 2 weaker; 4 guardrails). Screen cluster PARKED (screens need enemy reserves; bench fixtures have 0 units in reserve - verified 84/84 deployed). 6 designer sessions being created (r5design). Designers now also measure bench reach (1 full-game pair).
- 02:14 pr10_1 saved: s7463 r1 P2 Lootas BLOCK screen -> Advance centre CONFIRMED (+4.79 [2.50,7.09] n24); s7475 r2 P1 CG Alpha attack-move toward charge target -> Move centre CONFIRMED (+4.00 [1.04,6.96] n24). r5c11 (ork s7486) saved: 4 jobs, none clear. Both archived.
- 02:20 Corridor-block screens (T7-42) do NOT need enemy reserves (only deep-strike denial screens do). Block evidence: s7463 r1 P2 Lootas block -> Advance centre CONFIRMED +4.79 n24, but similar s7435 r1 Lootas block (+0.11 n36) and s7462 r1 (-0.58 n12) neutral -> no panel yet (single finding).
- 02:20 s7475 r2 P1 attack-move (toward charge target) -> Move centre CONFIRMED +4.00 n24: single finding of its kind on V10 -> no panel yet; extra evidence for later.
- 02:21 SIDE TRACK (bench coverage gap): workflow reserve-fixtures (wpztljl7y / wf_1a825299-b29) builds OPT-IN fixtures with the AI's own reserve picks
  (mirror_custodes/orks/asym *_2000_reserves_postdeploy) via a new opt-in flag in make_2000pt_fixture.gd; validate + smoke games + adversarial review.
  Purpose: measure reserve-dependent fixes (screens, reserve-backed keepers: s7467 +3.64 n36, s7477 +6.38 n24, s7453 +6.17 n36, s7454 r1 +4.83 n36) that the 3 bench fixtures cannot see.
  Not a change to the shipped bench protocol: the 3 existing fixtures stay the ship gate; a reserve fixture would be an ADDITIONAL bench for reserve-dependent fixes only.
- 02:17 r5c14 (ork vs cus s7489) saved (archived): no clear; HARMFUL r1 P1 Mek Beta reinforcing obj_center (1 unit committed) was RIGHT (-5.50 [-10.06,-0.94]) -> extra marginal_oc guardrail for the judge. Allarus 17% charge: no-charge -2.92 (neutral).
- 02:18 6 designer sessions created (marginal_oc__{narrow,root,game}, charge_target__{narrow,root,game}); prompts verified byte-identical to r5_panel/prompts in the creator's create_session calls.
- 02:26 r4v12w_cus_V7D#2 saved (archived): cus E -0.46 [-6.37,5.44] n14 so far. Note [WAAAGH_ADVANCE_CHARGE] fires in the Custodes mirror (31 lines/21 games): the game design's Normal-move-instead-of-Advance toward a charge target applies to any unit without an advance-and-charge effect, by design.
- 02:32 r4v12f_cus_V7D#1 saved (archived).
- 02:33 r5c09 (ork s7484) saved (archived): CLEAR r1 P1 Burna Boyz backfield-gap screen -> alt +5.33 [1.96,8.71] n12 -> pr12 queue (screen: reserve-fixture track). Stormboyz 28% charge: no-charge -2.08 (neutral).
- 02:34 r4v12f_cus_V7D#0 saved (archived).
- 02:34 r4v12f_cus_V7D#2 saved (archived): V12F cus COMPLETE.
- 02:39 r4v12w_cus_V7D#1 saved (archived).
- 02:40 r4v12w_cus_V7D#0 saved (archived): V12W cus COMPLETE.
### 02:48 pr10 RE-CHECK COMPLETE (11 jobs): 9 confirmed, 2 faded. pr10_2: s7462 r1 P2 Lootas Heavy-hold -> Advance centre CONFIRMED +5.63 [3.42,7.83]; s7480 r1 P1 Gamma sole-holder hold -> Move centre CONFIRMED weakly +2.38 [0.10,4.65] (marginal_oc extra finding).
- 02:50 Clusters 3+4 pushed (ranged_hold_vs_centre: s7462 r1 +5.63, s7463 r1 +4.79 n24; attack_move: s7475 r2 +4.00 n24, s7455 r2 +5.92 n36, s7421 r2 +9.81 n36). 6 more designer sessions being created (r5design2).

##################################################################
### 02:59 PROTOCOL v2 ADOPTED — PRE-REGISTRATION (before any v2 data)
##################################################################
# AI lab protocol v2 — pre-registration

Written 2026-10-31 ~02:58 UTC, BEFORE any v2 data was collected. Committed to git so the
commit time fixes the order. Applies to every new data collection from now on.

## Transition
- Finish under the v1 rules (unchanged): (a) the V12 confirmation bench and its 00:52 rule
  (ship an arm only if pooled E vs V7D > +0.80 and pooled E > 0 with no fixture 95% CI wholly
  below 0); (b) the 4 round-5 judge panels (marginal_oc, charge_target, ranged_hold_vs_centre,
  attack_move): 3 designs, 2 reviews each, judge; (c) the 4 round-5 sweeps still running
  (r5c06/07/08/10) finish their 12-seed value check.
- Everything else follows v2.

## V2-1 Bench-reach gate
- Reach run: the shipped AI in both seats, 1 pair per fixture = 6 games
  (--seed-base 91000 cus / 91100 asy / 91200 ork, --pairs 1, --rules11e).
  AI_LAB_KEEP_LOG_GREP keeps the lines that hold the decision-type text; count per game the
  "[GameEventLog]" lines that match (consecutive duplicate lines collapsed), both players.
- Cluster gate (before design or bench): decision-type count >= 1.0 per game, pooled over the
  6 games. Below -> PARK.
- Fix gate (before bench; applies now to the 4 round-5 panel winners and to every rules-audit
  fix): the fix's own log tag >= 1.0 line per game, pooled over 1 pair per fixture (6 games)
  with the fix in the candidate seat and the shipped AI as base. Below -> PARK (code kept,
  FIX_ param 0).
- Decision-type text for the round-5 clusters: marginal_oc = "already committed" |
  "holding under threat" | "capturing it (uncontrolled)"; charge_target = "targets picked after
  the roll"; ranged_hold_vs_centre = "holds for Heavy weapon bonus" | "approaching" (corridor
  block); attack_move = "moving toward charge target" | "advances to attack".

## V2-2 Bench power: sequential design (default for every new arm)
- Each new arm plays head-to-head against the AI shipped at that time (paired seeds, both seat
  assignments; E per seed = (M1 - M2)/2; pooled = equal weight per fixture). Few arms: one
  bundle arm per track (round-5 winners together; rules-audit fixes together). No switch-off
  arms unless the bundle crosses the efficacy boundary.
- Looks at 124 / 248 / 372 pairs; each look = 42 cus + 42 asy + 40 ork pairs:
  look 1: cus 95000/95020/95040 x14, asy 99000/99020/99040 x14, ork 94000..94080 step 20 x8;
  look 2: cus 95100/95120/95140, asy 99100/99120/99140, ork 94100..94180;
  look 3: cus 95200/95220/95240, asy 99200/99220/99240, ork 94200..94280.
- z = pooled E / pooled SE; pooled SE = sqrt(sum of se_f^2) / 3, se_f from the per-seed E
  values of fixture f (all pairs so far).
- Efficacy (ship): z >= 3.710 / 2.512 / 1.993 at looks 1 / 2 / 3 (Lan-DeMets O'Brien-Fleming
  spending, one-sided alpha 0.025; cumulative alpha 0.0001 / 0.0060 / 0.0250) AND no fixture
  95% CI wholly below 0 at that look.
- Futility (non-binding): stop at look 1 or 2 if pooled E <= 0. Look 3 without crossing the
  boundary = no ship (code kept, FIX_ params 0); E and CI are reported.
- Power (simulated, with the futility rule), true gain in units of the final SE: 1.0 -> 16%,
  2.0 -> 49%, 2.8 -> 78%, 3.24 -> 88%. The 124-pair benches had pooled SE 0.39-0.92 VP, so the
  final SE is about 0.23-0.53 VP: ~80% power for true gains of about 0.7-1.5 VP.
- A fixed ~300-pair design (target 95% CI about +-1.1 VP; ship if the pooled 95% CI lower bound
  > 0 and no fixture CI wholly below 0) may replace it only if registered for that arm before
  its first game.

## V2-3 Longer value check
- Before a finding enters a panel: rollout re-check at --horizon 2 (0 = to game end when the
  decision is in battle round 4 or 5), 24 seeds, --seed-base 5300. CONFIRMED-H2 only if the
  24-seed 95% CI lower bound > 0; otherwise FADED and dropped.
- First batch (pr12h2): the 6 pr12 jobs (s7459 r1 Lootas advance-flip; s7459 r2 Beast Snagga
  28% charge; s7487 r2 Kommandos 28% charge; s7465 r1 Gretchin screen; s7465 r2 Stormboyz
  2-target charge; s7484 r1 Burna Boyz screen), the parked screen finding s7477 r1, and the
  13 findings of the 4 running panels as INFORMATION ONLY (it does not change those panels;
  the result is reported next to each winner before its bench). Clear/promising findings from
  r5c06/07/08/10 go into a second batch.

## V2-4 11th-edition rules audit
- Workflow, per topic: charges and overwatch; Advance / [ASSAULT] / Heavy and other movement-
  relevant weapon keywords; army rules (Waaagh!, Custodes and Space Wolves army/detachment
  rules); reserves and deep strike; OC and objective-control timing; stratagems. List every
  rule assumption in AIDecisionMaker.gd (file:line), compare it with the engine (file:line)
  and the 11e core rules (link in CLAUDE.md), verify each mismatch adversarially, rank by
  confidence x decisions affected per game x estimated VP.
- Output: tools/ai_lab/rules_audit_11e.json and .md. Engine-vs-rules defects are listed
  separately and not fixed in this track.
- Clear AI-side mismatches: one fix each behind FIX_<NAME> (0 = old behaviour exactly), a
  failing-first unit test each, all in one bundle arm -> V2-1 fix gate per fix -> V2-2 bench.

## V2-5 Broader bench
- Reserve fixtures (workflow running): usable only after review verdict "usable", a
  fixture_check pass and smoke games with no errors. Then they are an extra gate for
  reserve-dependent fixes (parked: screen_vs_objective winner, keeper_reach winner, the
  s7477 / s7484 screen findings after V2-3): ship needs the V2-2 sequential test on the reserve
  fixtures AND no fixture 95% CI wholly below 0 on the 3 standard fixtures at 124 pairs.
- Proposal only (not run): one more faction fixture, a Space Wolves 2000 mirror from
  40k/armies/sw11e_gw_import_2000.json (mirror_spacewolves_2000_postdeploy).

## V2-6 Stop rule
- Round-5 gain = pooled E, head-to-head against the AI shipped before round 5 (V10, or V12 if
  it ships), of the round-5 bundle that ships under V2-2; 0 if nothing from round 5 ships.
- If the gain is <= +0.5 VP: no new critic sweeps or rounds. Instead propose (not run) a
  parameter-tuning track on the bench with cem_driver.py / sensitivity_screen.py, with cost
  and time estimates.

## Standing rules (unchanged)
No pull requests; push only to claude/awesome-clarke-31p54m; never claim a result that was
not run; never remove debug logs; wait on conditions, never a bare sleep; archive each sibling
session after its result is read.
##################################################################
- 03:05 V2 CLARIFICATION (before any reach data): the reach run uses --pairs 2 per fixture, not 1: with the same AI in both seats the two
  games of a pair are identical, so 2 pairs give the 6 DIFFERENT games V2-1 intends (2 per fixture); counts are per unique game.
- 03:05 V2 LAUNCHES:
  * V2-3: batch pr12h2 pushed (e4f759d): 20 jobs at horizon 2 x 24 seeds, seed-base 5300 (7 v2 findings + 13 panel findings info-only); 10 re-check sessions being created.
  * V2-1: reach run reach_v10 (V10 both seats, 2 pairs per fixture, [GameEventLog] decision-type counts) - 1 session being created.
  * V2-4: workflow rules-audit-11e (wjn0h0hal / wf_040c9458-7a8): 6 topic auditors -> 6 adversarial verifiers -> ranker. 11e core rules text: rules11e/core_rules_11e.txt (wahapedia, 267 KB).
  * V2-5: reserve-fixtures workflow (wpztljl7y) still running; review verdict gates its use.
  * Still under v1: V12 bench (16 shards left), 4 round-5 panels (12 designers), sweeps r5c06/07/08/10.
- 03:04 r4v12f_asy_V7D#1 saved (archived). DESIGN_DONE marginal_oc/root 3a9dd2a1: 2/3 findings flipped, 0 harmful, tests ok, bench_fires 0.5/game (designer's 1-pair estimate) (archived).
- 03:07 11 sessions created: pr12h2_0..9 (h2 re-check) + reach_v10; prompts checked against files in the creator's create_session calls.
- 03:09 CHECK-IN 11 done: 41 live sessions, all WORKING (none failed): 16 V12 shards (ork shards 2-8/16 games), 11 designers, 4 sweeps (r5c06 3/8, r5c07 3/7, r5c08 2/9, r5c10 4/9), 10 pr12h2, reach_v10. Charge separator: synthesis says NO SEPARATOR; skeptics running. Rules audit: auditors running (2 at a time). Reserve fixtures: build phase. Check-in 12 at 04:09 (trig_0115z3NL9xeeUspoh4qEHd5U).
- 03:09 r4v12f_ork_V7D#0 saved (archived).
- 03:10 r4v12w_ork_V7D#0 + r4v12f_ork_V7D#4 saved (archived).
- 03:12 DESIGN_DONE charge_target/root b5187e73: 1/1 flipped, 0 harmful, tests ok, bench_fires 104 (very broad trigger - check JSON) (archived).
- 03:17 r4v12f_asy_V7D#2 saved (archived).
- 03:17 NOTE: 40k/tests/make_2000pt_fixture.gd has uncommitted edits from the running reserve-fixtures workflow (build phase). Deliberately NOT committed until its review verdict (V2-5); stop-hook reminders about it are expected until then.
### 03:2x CHARGE SEPARATOR WORKFLOW DONE (w2qwqyerf / wf_ab35adca-413) -> charge_r5/brief.md
- Verdict: NO SEPARATOR (synthesis) and both skeptics (overfit, fidelity; high confidence) refute every floated separator
  (H1 round-2+Attached, card proxy, VP-exchange-as-rule). The s7470_1 harmful twin did NOT replicate on 12 fresh seeds (-0.83 [-3.81, 2.14]).
  -> No charge_low_odds panel (task #37 closed). Under protocol v2 a charge cluster needs h2-confirmed findings + reach first.
- Mechanisms with their own evidence -> routed to the V2-4 rules audit (charges topic), not to a panel:
  (a) the AI never declines the charge move after the roll (11e 11.02 allows it; engine accepts SKIP_CHARGE): post-roll re-pick at score 0.0 (s7457);
  (b) phantom 11e overwatch multiplier (T7-51) on every charge score; (c) FURY OF THE EMPEROR bought on every eligible Custodes declaration (constant ai_score 2.5 > bar 2.0), never priced;
  (d) gang-up from an earlier failed declaration (FIX_CHARGE_EV=0) decides 2 second-charge positions.
- ENGINE vs 11e (report only, not this track): Heroic Intervention Into the Fray costs 1 CP (11e: 2 CP); HI charge gives no Fights First (11e 11.04 does);
  HI target picked before the roll (11e: after); has_charged read but never written (saves allow a second declaration); rollouts replay a fixed secondary-deck order per position (E at card-driven positions is conditional on hidden draws).
- BENCH GAP (V2-5): the 3 bench fixtures have NO attached leaders (leader_attachments = {}) and no reserves; real games attach leaders. Attached-unit logic is unmeasurable on the bench.
- 03:19 r4v12f_ork_V7D#2 saved (archived). DESIGN_DONE charge_target/game 839bcdc2: 3/3 flipped (incl. 12-seed extras), 0 harmful, tests ok, bench_fires 245 (score-change lines) (archived).
- 03:25 r4v12w_ork_V7D#3 saved (archived).
- 03:25 r4v12w_ork_V7D#1 saved (archived).
- 03:26 r4v12w_ork_V7D#4 saved (archived).
- 03:26 r4v12w_ork_V7D#4 saved (archived): V12W ork 32 pairs -1.55. Tooling: decide_v2.py (V2-2 sequential decision: looks by seed range, z vs 3.710/2.512/1.993, fixture safety, futility) written and smoke-tested on V12F data (tooling test only; V12 stays under v1).
- 03:27 DESIGN_DONE marginal_oc/game 853efda0: 2/3 flipped, 0 harmful, tests ok, bench_fires 0 in its 1 bench pair (archived). marginal_oc: 2 of 3 designs (narrow pending).
- 03:27 r4v12f_ork_V7D#1 saved (archived).
- 03:28 DESIGN_DONE marginal_oc/narrow 658b6439: 2/3 flipped, 0 harmful, tests ok, bench_fires 0 (archived). marginal_oc: 3/3 designs -> judge panel.
- 03:28 JUDGE PANEL marginal_oc launched (wx6jn48qd / wf_dc9aab81-1b0; v1 rules: 2 reviewers per design + judge; read-only worktree wt_panel at origin tip). Extra evidence: s7489 r1 Mek reinforcement guardrail; s7480 r1 now +2.38 n24; v2 fix gate follows (designers' 1-pair bench fires: narrow 0, root 0.5, game 0).
- 03:29 pr12h2_6 saved: s7477 r1 screen [v2] FADED at h2 (+3.46 [-3.33,10.24]) -> dropped; s7475 r2 attack-move [info] h2 -3.00 [-9.10,3.10] (sign flips vs h1 +4.00). DESIGN_DONE attack_move/root 713f9eab: 3/3 flipped, 0 harmful, tests ok, bench_fires 0. Both archived.
- 03:30 r4v12w_ork_V7D#2 saved (archived): V12W ork COMPLETE.
- 03:32 r4v12w_asy_V7D#1 saved (archived).
- 03:33 V12W provisional +1.59 [-0.48,3.65] (asy 14/42 in). SHIP-PREP workflow launched (wv3f856yw / wf_63f8c343-00e): isolated worktree wt_ship_v12w; V12 patch + FIX_R1_SUPPORT_ADVANCE default 0, 2 tests, windowed K-card scenario ai_waaagh_advance_charge_s7468 + screenshot, version 1.56.8 draft; LOCAL COMMIT ONLY - nothing ships unless the pre-registered 00:52 rule passes on the complete bench.
- 03:33 DESIGN_DONE attack_move/game 07e5d839: 2/3 flipped, 0 harmful, tests ok, bench_fires 1 (archived). attack_move: 2/3 designs.
- 03:34 pr12h2_9 saved (archived): [info] s7478 r3 marginal_oc h2 +4.54 [-4.49,13.57] (not confirmed); [info] s7454 r3 attack_move extra h2 -3.42 [-9.62,2.78] (drift on V10).
- 03:34 r4v12w_asy_V7D#0 saved (archived).
### 03:35 — V12 C_waaagh (V12W) bench COMPLETE (124 pairs vs V7D, v1 rule)
- cus +1.49 [-2.01, 4.98] n42; asy +1.65 [-0.67, 3.98] n42; ork +0.38 [-2.48, 3.23] n40; POOLED +1.17 [-0.52, 2.86]; rule_pass (E>0, no fixture CI wholly < 0) = TRUE.
- Fires (lines/games with a fire): WAAAGH_ADVANCE_CHARGE cus 88/60, asy 82/46, ork 46/28; R1_SUPPORT_ADVANCE 0 (off in this arm).
- vs V10's pooled +0.80 on the same seeds: +1.17 > +0.80. The 00:52 rule picks the arm with the HIGHEST pooled E, so the decision waits for V12F's last 2 shards (asy#0, ork#3; V12F now +0.11 on 102 pairs).
- 03:42 DESIGN_DONE charge_target/narrow 45986f54 (archived). charge_target 3/3 -> judge panel (worktree wt_panel_ct).
- 03:42 JUDGE PANEL charge_target launched (wg3fd4l32 / wf_ca70d2a4-210; worktree wt_panel_ct). Extra evidence: charge separator brief (no separator; post-roll re-target leak, phantom overwatch, FURY, no attached leaders in bench), HI engine notes, v2 fix gate; designers' tag counts are score-change lines (narrow 45.5, root 104, game 245 per game).
- 03:43 pr12h2_8 saved (archived): [info] s7475 r3 marginal_oc h2 +6.67 [-0.34,13.67] (borderline, not confirmed); [info] s7421 r2 attack_move h2 +14.83 [7.13,22.53] CONFIRMED-H2.
- 03:45 DESIGN_DONE attack_move/narrow 9061bfb4 (archived). attack_move 3/3 -> judge panel (worktree wt_panel_am).
- 03:45 JUDGE PANEL attack_move launched (w3b89fsye / wf_31643e45-888; worktree wt_panel_am). Extra evidence: h2 info (s7421 confirmed +14.83; s7475 r2 flips -3.00; s7454 drift), V12 waaagh compatibility, v2 fix gate (designer bench fires narrow 0, root 0, game 1.0).
- 03:47 r4v12f_asy_V7D#0 saved (archived). V12F asy COMPLETE; only ork#3 left.
### 03:57 — V12 CONFIRMATION BENCH COMPLETE -> DECISION (pre-registered 00:52 rule, v1): SHIP V12 C_waaagh
- C_full  (V12F, R1SA on):  cus -0.98 [-4.63, 2.68] n42; asy -1.64 [-4.48, 1.19] n42; ork +2.46 [-1.28, 6.20] n40; POOLED -0.05 [-2.03, 1.93]; rule FAILS (E <= 0).
- C_waaagh (V12W, R1SA off): cus +1.49 [-2.01, 4.98] n42; asy +1.65 [-0.67, 3.98] n42; ork +0.38 [-2.48, 3.23] n40; POOLED +1.17 [-0.52, 2.86]; rule PASSES.
- Highest pooled E meeting the rule = C_waaagh (+1.17) > V10's own +0.80 on the same 124 seeds -> SHIP V12 with FIX_WAAAGH_ADVANCE_CHARGE on and
  FIX_R1_SUPPORT_ADVANCE off (code kept). Version 1.56.8. Package from the ship-prep workflow (wv3f856yw) once its review says ready.
- Honest note: the pooled CI includes 0 (z ~ 1.36); under protocol v2's sequential rule this would not yet cross the look-1 boundary (3.710).
  It ships because the V12 decision was pre-registered under v1 and the user said running work finishes under its existing rules.
### 04:13 — V2-1 REACH RUN (reach_v10; V10 both seats; 6 distinct games, 2 per fixture) -> r5_panel/reach_v10.txt
- Decision types per game (both players): marginal_oc 72.5; charge_target 12.3 (multi-target declarations: cus 16, asy 18, ork 3);
  ranged_hold_vs_centre 8.8 BUT "holds for Heavy weapon bonus" = 0 in all 6 games (only the corridor-block part fires: ork ~20, cus 2, asy 4.5);
  attack_move 44.2. All 4 clusters pass the cluster gate (>= 1.0/game) at the decision-type level.
- Binding gate is the FIX gate (the winner's own tag >= 1.0/game over 1 pair per fixture): designers' one-pair counts were 0-1/game for
  marginal_oc and attack_move designs. Heavy-hold fixes cannot fire on the bench at all (0 Heavy holds in 6 games).
- 04:15 SHIPPED 1.56.8 = V12 C_waaagh (commit e12e6e8): cherry-picked from ship-prep 54732ab (review: ready); scenario ai_waaagh_advance_charge_s7468 27/0 re-run in the main checkout at 04:15. Shipped AI base for round 5 is now V12W (FIX_WAAAGH_ADVANCE_CHARGE 1, FIX_R1_SUPPORT_ADVANCE 0). Round-5 panel winners must be rebased onto it.
- 04:17 1.56.8 pushed (e12e6e8, origin verified). Screenshots (main-checkout run 04:15): BEFORE .../test_results/scenarios/ai_waaagh_advance_charge_s7468_00_fix_off_before.png ("Stormboyz advances to attack Prosecutor Squad"),
  AFTER ..._01_fix_on_after.png ("Stormboyz moves to attack Prosecutor Squad"). V2-6 baseline for round 5 = V12W (1.56.8).
- Flags from the ship review (pre-existing, not caused by 1.56.8): tests/test_ai_objective_assignment_fixes.gd fails 6/1 on V10 too and is not in
  tests/ci/direct_known_failures.txt; IngressMove sets flags.no_moves_until_charge_phase and nothing clears it, so MovementController hides Move/Advance
  for units that arrived from reserves in every later turn (human-UI bug; MovementPhase does not enforce it, AI unaffected).
### 04:2x V2-5 RESERVE FIXTURES: smoke "usable" + review "usable" -> COMMITTED (72a14a5)
- Builder flags --reserves=ai (AI's own Formations reserve picks) and --base=<fixture>; default path unchanged (verified on 4 configs).
- mirror_custodes_2000_reserves_postdeploy (825/2000 pts DS per side), mirror_orks_2000_reserves_postdeploy (410/1975: 2 SR + 2 DS), asym_2000_reserves_postdeploy.
- Smoke: 7 full games, 0 SCRIPT ERRORs; Custodes reserves all arrive R2; [SCREEN] deep-strike logic fires 3-6x/game (vs 0-1 on standard fixtures).
- Use as the EXTRA gate for reserve-dependent fixes; prefer the Custodes + asym reserve fixtures (Ork Deffkopta confound).
- New defects found (report; not fixed): (1) ENGINE: destroyed reserve units keep IN_RESERVES (ScoringPhase P1-37) -> ghost arrivals in R4 and
  Rapid Ingress on a destroyed unit costs CP; (2) Rapid Ingress whose placement fails still costs 1 CP (no refund); (3) AI: Deep Strike / Rapid
  Ingress placements for oval-base Deffkoptas rejected for walls (_is_valid_reinforcement_position has no per-model wall/oval check) -> units
  destroyed end of R3; (4) AI: movement-order comparator not a strict weak ordering ("bad comparison function"); (5) bench logs carry MCP-bridge
  noise (run_lanes does not set GODOT_MCP_DISABLED=1); (6) bench fixtures' datasheets drifted from current army lists (pre-existing).
- 04:33 DESIGN_DONE ranged_hold_vs_centre/game ef26767a: 3/3 flipped, 0 harmful, tests ok, bench_fires 0 (archived). ranged_hold: 1/3 designs.
- 04:43 pr12h2_2 saved (archived): [v2] s7487 r2 Kommandos 28% charge FADED-H2 (-0.08) -> dropped; [info] s7461 r3 charge_target extra +0.08 (not confirmed).
### 04:4x JUDGE PANEL marginal_oc: WINNER NONE (6 reviews: 5 drop, 1 revise) -> tools/ai_lab/r5_designs/marginal_oc/panel.json
- All three (a) holder-release gates count an ATTACHED leader (Blade Champion C on Guard Beta) as staying when its bodyguard leaves; with
  leader-aware counting none fires at s7475; real games attach every Blade Champion, so the gates could tie/empty held objectives; bench can't see it.
- s7475 flip also a replay artifact (COORD-4 plans once per phase). Only gate (b) at s7478 is real but sends Beta to obj_nml_1, not the measured centre.
- Bench reach ~0 for all three (fails the V2-1 fix gate). Nothing merges.
- NEW GAP (V2-5): the 3 bench fixtures have 0 leader attachments; the AI attaches leaders in real games; the shipped KEEP-OC accounting has the same
  attached-leader miscount on held_safe objectives (base defect; -> rules/engine-fidelity audit). Proposal: an --attach=ai fixture option.
- 05:03 r5c07 (ork s7482) saved (archived): CLEAR r1 P1 Beast Snagga backfield-gap screen +4.58 [1.41,7.76] n12 -> h2 batch-2 queue (screen; reserve track). Others neutral (Heavy hold r1: identical 12/12).
### 05:0x JUDGE PANEL attack_move: WINNER narrow (with 7 required changes) -> tools/ai_lab/r5_designs/attack_move/panel.json
- Reviews: narrow revise/drop, root revise/revise, game drop/revise. Judge: narrow is the only design that becomes safe with small edits and
  applies cleanly on V12; expected to be PARKED by the V2-1 fix gate (~0.3 fires/game after the required limits; 0 in 6 Custodes bench games).
- Next (v1 panel finished; v2 gates apply): FIRST the h2 re-check of s7455 r2 (pending in pr12h2). If it FADES -> drop attack_move (s7475 r2 already
  faded). If it holds -> finalize narrow on V12W with the required changes -> V2-1 fix gate (1 pair per fixture).
- Uncovered: s7421 r2 (the only CONFIRMED-H2 finding, +14.83, centre denial) needs its own design (candidate cluster for a later round, v2 gates).
### 05:1x JUDGE PANEL charge_target: WINNER narrow (6 reviews all 'revise'; 5 required changes) -> tools/ai_lab/r5_designs/charge_target/panel.json
- Narrow = exact measured flip at s7480 r3 (Allarus charge Blade Champion Alpha alone). Required: depletion gate (<= 50% starting wounds) + 2x ratio;
  CHARACTER/kill-card exemption (else harmful guard s7431 r3 switches); Attached-unit folding; CT-COMBO only when the charger cannot engage both;
  decision-level log line for reach. Expected changed declarations after the gates ~0.5-2/game.
- Next: s7480 r3 h2 re-check (pr12h2 shard 1, pending) -> finalize on V12W (sibling finalizer) -> real-save guard checks -> V2-1 fix gate.
- attack_move next: s7455 r2 h2 re-check (pr12h2 shard 7, pending) -> drop cluster if it fades.
- 05:11 CHECK-IN 13 done: 1.56.8 shipped (e12e6e8); reserve fixtures committed (72a14a5); panels: marginal_oc none, attack_move narrow (cond.), charge_target narrow (cond.); 11 live sessions all WORKING (6 pr12h2, 2 ranged_hold designers, 3 sweeps); rules audit 8/13 agents done (verifying). Check-in 14 at ~06:11.
- 05:12 FINALIZER charge_target (narrow + judge's required changes, on 1.56.8; includes V2-1 fix gate 1 pair/fixture) being created. attack_move finalizer waits for s7455 r2 h2 (shard 7).
- 05:12 DESIGN_DONE ranged_hold_vs_centre/narrow d068d7a2: 2/2 flipped, 0 harmful, tests ok, bench_fires 0 (archived). ranged_hold: 2/3 (root pending).
- 05:14 final_charge_target session_012X5b5QQr3emAWrftmZR1bT created (prompt verified identical).
- 05:30 r5c06 (ork s7481) saved (archived): HARMFUL r1 P1 Lootas Gamma advance-capture nml_2 (-9.33) and r1 P2 Lootas Alpha advance-capture nml_1 (-18.50): AI's Lootas advances were RIGHT -> ranged_hold judge guardrails. Beast Snagga screen +4.42 [-0.34,9.17] (promising only).
- 05:36 DESIGN_DONE ranged_hold_vs_centre/root 06a688a7 (archived). 3/3 -> judge panel (wt_panel_rh).
- 05:36 JUDGE PANEL ranged_hold_vs_centre launched (whmvzluqp / wf_a272249f-849; worktree wt_panel_rh). Extra evidence: Heavy hold 0/6 bench games, corridor blocks ~20/game in Orks mirror; r5c06 Lootas advance-capture guardrails (-9.33, -18.50 for Normal move); v2 fix gate; 1.56.8 rebase.
- 05:37 pr12h2_0 saved (archived): [v2] s7459 r1 Lootas advance-flip (enemy home OC 15) CONFIRMED-H2 +4.58 [0.37,8.80] (alt Hold home) -> candidate new cluster; [info] s7480 r1 sole-holder -> centre CONFIRMED-H2 +5.71 [0.08,11.33].
### 05:39 pr12h2_7 saved (archived): s7455 r2 (attack_move) h2 +4.54 [-5.18, 14.26] -> NOT confirmed. Per the attack_move judge's extra check 1
    (s7475 r2 already faded at h2), the attack_move cluster is DROPPED: no finalizer, code stays unmerged. s7463 r1 (marginal_oc) h2 +4.88 [-0.07, 9.82] borderline.
- Uncovered CONFIRMED-H2 findings for a possible next design round (v2 gates: cluster reach first): s7421 r2 centre denial (+14.83), s7459 r1 Lootas
  advance-flip of enemy home vs hold own home (+4.58), s7480 r1 sole-holder home -> centre (+5.71).
- 06:05 r5c10 (ork s7485) saved (archived): 9 jobs, no clear; HARMFUL r1 P2 Burna Boyz backfield-gap screen was RIGHT (-2.92 [-5.75,-0.09]) -> screen guardrail (reserve track). Only r5c08 left.
- 06:12 CHECK-IN 14 done: 6 live sessions WORKING (pr12h2_1/3/4/5 ~3h in, r5c08 5/9, final_charge_target: tests pass, gate games running); rules audit at the rank step; ranged_hold panel reviewing (3/7). attack_move dropped; marginal_oc none. Check-in 15 at ~07:12.
- 06:4x V2-4 RULES AUDIT DONE (wf_040c9458-7a8; 13 agents, read-only, no games): 75 items (charges 13, movement/keywords 11, army 10, reserves 13, objectives 13, stratagems 15); 71 confirmed, 4 refuted; 51 ranked; 13 CLEAR fixes; 22 engine-vs-rules defects listed separately (not fixed in this track). Committed 585cbbc tools/ai_lab/rules_audit_11e.{json,md}.
  Clear fixes (rank order): FIX_OBJ_AREA_REACH (OC-01), FIX_CHARGE_OW_11E (CH-01 phantom 10e overwatch at charge), FIX_OBJ_AREA_ON_OBJ (OC-03), FIX_OBJ_AREA_HOLD (OC-04), FIX_EOG_TIMING (OC-02), FIX_MOVE_TERRAIN_11E (TER-01), FIX_HI_CHARGE_ODDS (CH-03), FIX_SECURED_AWARE (OC-05), FIX_CO_NEXT_PICK (CO-01), FIX_PILEIN_TARGETS_11E (CH-09), FIX_CHARGE_REROLL_ODDS (CH-05), FIX_ADV_ENGINE_PREDICATES (CH-02), FIX_WAAAGH_ADV_REROLL (AR-06).
  Harness facts from the audit (NOT fixed; flag to user): (a) FGL END_TURN_REDEPLOY for P2's unit is decided by P1's AI and evaluate_rapid_ingress never sets _current_player -> FGL fixes sign-inverted in A/B, profile arms read the opponent's params there; (c) Custodes mirror is NOT reserve-free after R1 (FGL / On Gilded Wings put Allarus into reserves, ~4 placements/game) -> V2-5 premise "bench cannot see reserves" is partly wrong; (d) Custodes faction aggression resolves to 1.0 (FACTION_AGGRESSION_CUSTODES unused); (e) AI defenders never get the reactive shooting-stratagem window (ShootingPhase.gd:2932-2933).
- 06:5x V2-4 CLEAR-FIX WORKFLOW launched (wf_194da67a-997, task w0t4tnh24): 5 groups in worktrees (G_OBJ 3, G_MISC 3, G_CHG 3, G_FIGHT 2, G_ADV 2) -> adversarial review per group (re-runs fail-first) -> repair -> merge into .ai_lab_work/audit_fix/bundle.patch (consts 0.0) + flip.sh -> V2-1 fix gate in the merge worktree (fixes ON vs SHIP e12e6e8, 1 pair per fixture, seeds 91000/91100/91200, per-tag lines/game). Only AIDecisionMaker.gd may change (bench swaps only that file). Bench plan after the gate: one bundle arm (fixes passing the gate ON via flip.sh) vs SHIP under V2-2 looks.
- Prep: tuning_track_draft.md (V2-6 proposal draft; costs from measured shard times + per-pair SD). Found: run_paired.py has no --rules11e and CEM/screen default difficulty 2 (bench uses 3) -> tools must be patched before any tuning run.
- 06:5x pr12h2_1 done: s7459 r2 Beast Snagga 28% charge CONFIRMED-H2 +5.21 [0.30,10.12]; s7480 r3 (charge_target finding) CONFIRMED-H2 +11.54 [5.53,17.55]. Archived.
- 06:4x FINAL_DONE charge_target (be845fa: tools/ai_lab/r5_designs/charge_target/final.{patch,json}; on 1.56.8; all 5 judge required changes applied; 30/30 unit tests, fails 6 on SHIP; decision check: s7480 r3 P2 flips to the measured alt (charge Blade Champion Alpha only); 8 guardrails unchanged incl. s7431 keep): V2-1 FIX GATE FAIL — decision-level [CHARGE_TARGET] changed declarations 0.33/game (cus 0.5, asy 0.5, ork 0.0); eval-level [CHARGE_TARGET_EVAL] lines cus 8.0, asy 4.5, ork 0 (pooled 4.17/game) for information. One changed declaration (cus M1) was followed by a failed charge move (CT-COMBO risk). Verdict not_ready -> PARKED (FIX_CHARGE_TARGET stays out of the shipped AI; code kept as the committed final.patch, not applied to AIDecisionMaker.gd so it does not collide with the audit bundle's charge-scoring fixes). Session archived.
- Round-5 status: marginal_oc NONE; attack_move DROPPED (h2 fade); charge_target PARKED (gate 0.33); ranged_hold_vs_centre panel still running -> it is the only round-5 bench candidate left.
- PRE-REGISTRATION (06:5x, before any audit gate data) — V2-1 fix-gate counting for the V2-4 audit fixes: each [FIX_<NAME>] tag prints once per evaluation where the fix changes a value the old code would have used (old != new); a fix passes with >= 1.0 such line per game pooled over the 6 gate games (seeds 91000/91100/91200, fixes ON in the candidate seat vs SHIP). This is looser than the decision-level count that the charge_target judge required (and that stays the basis of its PARK); both levels are reported where available. Reason: most audit fixes change values inside valuations used by many decisions, where a decision-level counterfactual is not computable without running the evaluation twice.
- 06:5x JUDGE PANEL ranged_hold_vs_centre DONE (wf_a272249f-849): winner GAME (scores game 4.14, narrow 3.43, root 2.71), 8 required changes (always Advance; not-alone + threat guard; exclude home duty; snapshot contract; narration; decision-level log; param-0 exactness; tests), 4 optional grafts. Judge expects PARK by the V2-1 gate (no [HEAVY] weapon in any bench list; corridor branch reaches only Prosecutors / Warbikers A/B; ~0-0.3 fires/game). Judge extra check 1 (BEFORE finalizing): read the h2 re-check of s7462 r1 P2 (shard 3), s7463 r1 P2 mov2_3 (shard 4), s7460 r1 P1 (shard 5): s7463 fades -> drop corridor branch; s7462 AND s7460 fade -> drop Heavy branch; all fade -> drop cluster, no finalizer. Committed panel.json. Finalizer HELD until shards 3/4/5 report.
- 07:06 pr12h2_4 done: s7465 r2 P1 Stormboyz 2-target charge FADED-H2 -1.13 [-8.35,6.10]; s7463 r1 P2 mov2_3 (ranged_hold F2 corridor) FADED-H2 -1.63 [-4.35,1.10] -> ranged_hold corridor branch DROPPED (judge rule); only the Heavy branch is left, which cannot fire on the bench (no [HEAVY] weapons). Archived.
- 07:1x VERIFIED (own run): base64+gzip-decoded bench saves mirror_custodes (22 units / 52 weapons), asym (28 / 85), mirror_orks (34 / 118): 0 occurrences of 'heavy' anywhere in each save -> the ranged_hold Heavy branch cannot fire on the bench (V2-1 fix gate would read 0.0 by construction). Plan: when shards 3 (s7462 r1 P2) and 5 (s7460 r1 P1) report: both fade -> DROP cluster; else PARK without a finalizer (code kept as the committed game.patch + panel.json; required changes not applied), because the gate outcome is fixed at 0 by the bench lists.
- 07:1x V2-6 PREP workflow launched (wf_a2eb71ab-c3d, task wswz82997; read-only, runs no games): tools gaps (incl. profile seat validity: get_param reads _player_profiles[_current_player]), parameter shortlist, noise/power simulation of CEM racing with measured CRN correlation (5 V12-round arms share seeds), cost model from shard sessions -> synthesis -> stats + engineering adversarial reviews -> tuning_track_proposal.md. Used only if the stop rule triggers.
- 07:14 CHECK-IN 15 done: live = r5c08 (5/9 jobs, job 6 running), pr12h2_3 (job 2 polling), pr12h2_5 (1 job done) — all WORKING, none stalled; all other sessions archived. Items 2-5 already handled (pr12h2_1/4 recorded; charge_target PARKED; ranged_hold verdict = game, finalizer held/likely park; audit saved + clear-fix workflow running). Check-in 16 at ~08:14.
- 07:55 pr12h2_3 done: s7465 r1 P2 Gretchin backfield-gap screen CONFIRMED-H2 +11.79 [6.87,16.72] (screen class -> reserve track); s7462 r1 P2 Lootas Heavy hold (ranged_hold F1) CONFIRMED-H2 +6.25 [3.48,9.02] -> Heavy branch kept -> ranged_hold_vs_centre PARKED (no finalizer: bench has 0 [HEAVY] weapons). KEY LESSON: sweep games use 40k/armies/Orks_2000.json (Lootas, Beast Snagga, Burna Boyz...) vs custodes_lions, but the bench uses Kult of Speed Orks + older Custodes lists -> confirmed findings often have ~0 bench reach. Archived.
- 07:58 VERIFIED: sweep rollout save s7462 (pr10) = Orks mirror from 40k/armies/Orks_2000.json (Lootas x3, Battlewagon x2, Beast Snagga, Beastboss, Snikrot, Burna Boyz x2, Kommandos, Mek x2, Stormboyz, Tankbustas, Warbikers x2, Zodgrod, Deffkilla Wartrike, Gretchin); bench Orks = recon_stomps (Speedwaaagh!) per fixture_check.py:72. -> fixture proposal for the report: an Orks_2000 mirror / Orks_2000 vs custodes_lions postdeploy bench fixture (where the critic findings come from), next to the Space Wolves proposal.
- 08:16 CHECK-IN 16 done: live = pr12h2_5 (~4.5h, 1/2 jobs, polling; updated 08:15) and r5c08 (job 7/9; updated 08:14) — both WORKING. Audit-fix workflow: G_OBJ.patch (07:25) + G_MISC.patch (07:55) written, 1 journal result; G_CHG/G_FIGHT/G_ADV implementing. Tuning-proposal workflow: 4 analysts done, synthesis running. Check-in 17 at ~09:16.
- 08:54 r5c08 (ork s7483) saved: 9 jobs, NO clear finding; HARMFUL r1 P2 Lootas Beta corridor screen (block Battlewagon -> obj_center) was RIGHT: alt -3.92 [-7.13,-0.70] (guardrail); 2 jobs no-op (12/12 identical). All 16 round-5 sweeps done. h2 batch 2 = only reserve-track screens (s7482 r1). -> ROUND 5 CLOSED with nothing to bench on the standard fixtures. Archived.
- 08:57 ROUND 5 CLOSED -> V2-6 STOP RULE TRIGGERED: round-5 shipped gain = 0 (marginal_oc none; attack_move dropped at h2; charge_target parked by gate 0.33; ranged_hold parked (corridor branch dropped at h2, Heavy branch 0 bench reach); r5c08 no clear finding). No new critic sweeps/rounds. Tuning proposal workflow (wswz82997) prepares the V2-6 proposal.
- 08:57 V2-3 BATCH 2 launched (pr13h2, commit 84d65b2 = 1.56.8 AI): s7482 r1 P1 Beast Snagga screen (r5c07 clear +4.58), s7481 r1 P1 Beast Snagga screen (r5c06 promising +4.42), s7482 r3 P2 Lootas 42% charge (r5c07 promising +1.75); 24 seeds, --horizon 2, --seed-base 5300; sessions pr13h2_0/1/2 (one job each).
- 09:0x CONTAINER RESTART stopped both workflows; resumed from cache: audit-fix (wgjyhkl8s, run wf_194da67a-997; 4/5 implementers cached: G_OBJ, G_MISC, G_CHG, G_FIGHT; G_ADV + reviews re-run) and tuning proposal (w4ofuus5y, run wf_a2eb71ab-c3d; only 'revise' re-runs).
- 09:1x V2-5 RESERVE TRACK: screen_vs_objective (round-4 winner 'narrow', parked) -> finalizer on 1.56.8 (prompt creator_dirs/resfinal_screen_vs_objective/final_screen_vs_objective.txt): apply judge RC1-5, decision checks incl. new screen evidence (s7465 h2 +11.79; s7484/s7482/s7481 h1), guardrails (s7485 -2.92, s7483 -3.92, s7408 -5.83), V2-1 gate on the 3 RESERVE fixtures (seeds 91000/91100/91200; pass >= 1.0 [SCREEN_VS_OBJECTIVE] decision lines/game) + standard fixtures for info. keeper_reach NOT run: it only acts inside _keeper_release_check, which is inert with FIX_KEEPER_RELEASE = 0 in 1.56.8 (judge merge_risk 1).
- 09:05 pr12h2_5 done (pr12h2 batch COMPLETE, 20/20 jobs): s7484 r1 P1 Burna screen CONFIRMED-H2 +8.00 [3.78,12.22] (reserve track); s7460 r1 P1 Lootas Heavy hold +6.00 [1.60,10.40] with DRIFT -> not confirmed (info; ranged_hold already parked). Archived.
- 09:17 CHECK-IN 17 done: live = pr13h2_0/1/2 + resfinal_screen_vs_objective (all started 08:57-09:10). Audit-fix workflow resumed: 4/5 implementers cached; G_ADV impl + review G_OBJ running (workflow concurrency is 2 agents on this 4-core box). Tuning proposal: only 'revise' left. Check-in 18 at ~10:17.
- 09:3x V2-6 TUNING PROPOSAL DONE (workflow wf_a2eb71ab-c3d; 8 agents, read-only, 0 games) -> committed tools/ai_lab/tuning_track_proposal.md. Recommendation HOLD: no tuning before the V2-4 bundle's V2-2 decision; then at most ONE one-generation probe (8 candidates x 8 dims, race 6 pairs, final 12 pairs for top 4, pick by best E over 18 pairs, then V2-2). Probe cost (E): 8.0 engineering h + 22.5-49.1 container-h (expected 31-36), 53-81 sibling sessions, ~$39-80, 3.4-6.6 h wall on 14 containers. P(ship & true gain > 0) (S): 0.10 at tau 0.5 VP, 0.31 at tau 1.0, <= 0.015 near null; V2-2 needs ~1.08 VP true gain for 50% power. Drafted multi-stage CEM track: 3.6x cost, +0.004..0.086 odds -> do not run.
  Tool findings (M, offline): cem_driver rates only the FIRST candidate per generation (shared season -> later candidates n=0); tuning tools play legacy (non-11e) rules at difficulty 2; ai_versions tag/season collision silently reports the first candidate's margins (our bench shards are safe: one arm per container season); Rapid Ingress / Epic Challenge never set _current_player (profile seat leak; extracted-base design avoids it).
- 10:18 CHECK-IN 18 done: live = pr13h2_0/1/2 (h2 rollouts running), resfinal_screen_vs_objective (tests pass; 45 final-code replays running) — all updated < 1 min ago. Audit-fix workflow: all 5 implementers done; reviews G_OBJ (3 approve, fail-first confirmed) and G_CHG (3 approve) done; G_MISC/G_FIGHT running, G_ADV next; then merge+gate. Check-in 19 at ~11:18.
- 10:2x V2-5 FIXTURE-PROPOSAL workflow launched (wf_15c5f8f0-6ed, task w4omnhu2u; read-only, nothing built): rosters (bench vs reserve vs sweep saves), findings reach (each clear/harmful position's unit on the bench?), build path for Orks_2000 mirror / custodes_lions vs Orks_2000 / SW mirror -> synthesis -> adversarial review -> fixture_proposal.md.
- 10:22 pr13h2_2 done: s7482 r3 P2 Lootas 42% charge FADED-H2 +0.75 [-2.06,3.56] -> dropped. Archived.
- 11:09 pr13h2_1 done: s7481 r1 P1 Beast Snagga screen FADED-H2 +0.96 [-7.39,9.31] -> dropped. Archived. Screen-class h2 tally so far: s7465 +11.79 CONFIRMED, s7484 +8.00 CONFIRMED, s7481 +0.96 faded, s7477 drift; s7482 r1 pending (pr13h2_0).
- 11:20 CHECK-IN 19 done: live = pr13h2_0 (s7482 r1 screen h2), resfinal_screen_vs_objective. Audit-fix reviews ALL DONE: 12/13 approve (fail-first confirmed), FIX_MOVE_TERRAIN_11E needs_changes -> repair:G_MISC running; then merge+gate. Fixture proposal: 3 analysts + synthesis done, review running. Check-in 20 at ~12:20.
- 11:24 pr13h2_0 done: s7482 r1 P1 Beast Snagga screen FADED-H2 +2.08 [-2.03,6.19] -> dropped. Archived. V2-3 BATCH 2 COMPLETE: 0/3 confirmed. Screen class at h2: CONFIRMED s7465 Gretchin +11.79, s7484 Burna +8.00; faded s7481 +0.96, s7482 +2.08; s7477 drift; guardrails (screen right) s7485 -2.92 (h1), s7483 corridor -3.92 (h1), s7408 -5.83 (h1).
- 11:5x V2-5 FIXTURE PROPOSAL DONE (wf_15c5f8f0-6ed; 6 agents, read-only, 0 games) -> committed tools/ai_lab/fixture_proposal.md. KEY FINDING (M): the 3 standard bench fixtures (and the 3 reserve fixtures) use OLD data (40kdc-data 1.0.19; custodes_lions at 4dea059 or earlier: 11 units/42 models, Custodian Guard x6 of 5, Allarus 5 models M5 T7 W4; recon_stomps old revision) while the sweeps and the shipped game use current lists (40kdc-data 1.4.5 + codex import: custodes_lions 9/22/1850 with 3 Blade Champion attachments, Allarus 3 models M7 T8 W6; Orks_2000 War Horde 20/106/1975 with 5 attachments; 29 official layouts vs the bench's single take_and_hold_mirror_1). At current profiles the bench reaches 0/44 clear and 0/42 harmful measured positions. The current recon_stomps.json sums to 2280 pts (over 2000). Recommendation: build asym_custodes_warhorde_2000_postdeploy (current custodes_lions P1 vs current Orks_2000 P2) as a SEPARATE extra gate (not pooled); pool only at a v3 with a rebuild of the stale standard fixtures; build cost <= ~5.5 h + 1.0-1.6 container-h validation; 40-pair look 3.3-5.3 container-h. No fixture can un-park ranged_hold's Heavy branch (needs a V2-1 amendment). Awaiting user decision (V2-5 says propose, don't run).
- 12:2x CHECK-IN 20: audit merge done (bundle.patch 11:33: AIDecisionMaker.gd + 13 tests; flip.sh); gate games done 0 SCRIPT ERROR; my own count (dups collapsed; 6 games): OBJ_AREA_REACH 221/g, OBJ_AREA_ON_OBJ 121, MOVE_TERRAIN_11E 90, OBJ_AREA_HOLD 48, CHARGE_OW_11E 41, ADV_ENGINE_PREDICATES 35, WAAAGH_ADV_REROLL 18, CHARGE_REROLL_ODDS 18, HI_CHARGE_ODDS 11.7, EOG_TIMING 4.8, PILEIN_TARGETS_11E 1.17 -> PASS (11); CO_NEXT_PICK 0.83, SECURED_AWARE 0 -> PARK (2). 1-pair margins (noise): cus E -11.0, asy -3.5, ork +12.0. Merge agent now running a param-0 identity check (DETB0/DETBASE arms, asym 91101). resfinal_screen_vs_objective still live.
- 12:3x V2-4 AUDIT BUNDLE COMMITTED ca913e2 (all 13 FIX_ consts 0.0; 23/23 tests pass fixes-off; param-0 identity verified asym 91101 both orders: same outcome / 695 actions / 330 decision records vs SHIP). Gate (merge agent count, dups collapsed): 11 PASS, PARKED FIX_SECURED_AWARE 0 & FIX_CO_NEXT_PICK 0.83. Caveat: with ALL fixes on, 6 unit-test files have failing checks (far_trip 4, held_dup 1, lone_flip 1, keeper_release 1, r1_home_capture 8, waaagh_adv_reroll 2) because each test switches only its own fix -> update before any ship. tools/ai_lab/audit_fixes/flip.sh (no args) flips the 11.
- 12:3x ARM AUD PRE-REGISTERED (544c693, tools/ai_lab/protocol_v2.md "Arm registrations") -> V2-2 LOOK 1 launched: 11 shards (aud_cus_SHIP#0-2 seeds 95001-95054 x14; aud_asy_SHIP#0-2 99001-99054; aud_ork_SHIP#0-4 94001-94088 x8), sha ca913e2 + flip.sh, base SHIP e12e6e8, decide_v2.py pattern 'aud_%s_SHIP_'. Creator agent creating sessions.
- 12:4x AUD look-1 sessions created: 11 (aud_cus/asy/ork_SHIP_*), FAILED none.
- 12:5x REPORT-UPDATE workflow launched (wf_48f30282-3ac, task w4qz74ls0): fetch artifact ff26c2b6 (v 1793360876-4088, 483 lines) -> fact sheet -> write report/next.html (STE, TLDR, pending blocks aud_look1 / screen_reserve) -> fact check + STE/page check -> revise. Not published; publish after the AUD look-1 and screen results fill the pending blocks.
- 13:04 AUD shard aud_cus_SHIP#1 saved (14 pairs); archived.
- 13:05 AUD shard aud_cus_SHIP#2 saved; archived.
- 13:07 AUD shard aud_cus_SHIP#0 saved; Custodes look-1 complete (42 pairs). archived.
- 13:23 CHECK-IN 21 done: AUD look 1: cus 3/3 shards saved (42 pairs, E -2.61 [-5.91,0.69]); asy 0/3, ork 0/5 running. resfinal_screen_vs_objective: reserve gate running (cus 0, asy 1 fire so far per its summary). Report workflow running. Check-in 22 at ~14:23.
- 13:34 AUD shard aud_asy_SHIP#1 saved; archived.
- 13:47 AUD shard aud_ork_SHIP#1 saved; archived.
- 13:49 AUD shard aud_ork_SHIP#4 saved; archived.
- 13:50 AUD shard aud_asy_SHIP#0 saved; archived.
- 13:54 AUD shard aud_ork_SHIP#2 saved; archived.
- 13:54 AUD shard aud_ork_SHIP#0 saved; archived.
- 13:56 FINAL_DONE screen_vs_objective (233bdd2: tools/ai_lab/r4_designs/screen_vs_objective/final.{patch,json}; on 1.56.8; tests ok; 45 guardrail replays: 0 moved toward harmful, 1 unmeasured fire s7436 r1 P1): V2-1 RESERVE-FIXTURE GATE FAIL 0.17 lines/game (rcus 0, rasy 0.5, rork 0; 1 fire in 6 games: asy Gretchin Beta skips a backfield gap for ADVANCE obj_nml_1); standard fixtures 0.0 -> PARKED (FIX_SCREEN_VS_OBJECTIVE stays out; code kept as final.patch). Findings flipped 1/5: only s7467; the 4 new screen findings (s7465 +11.79 h2, s7484 +8.00 h2, s7482, s7481) target obj_center while it is enemy-held / contested / a lost race = a different mechanism the judge's RC3 excludes (widening would cross measured-harmful centre positions s7408 1_1 -5.83, s7463 1_0 -3.75). V2-5 reserve track: nothing ships. Archived.
- 14:06 AUD shard aud_asy_SHIP#2 saved; asy look-1 complete. archived.
- 14:24 CHECK-IN 22 done. AUD look 1: 116/124 pairs saved (cus 42 E -2.61 [-5.91,0.69]; asy 42 E +1.45 [-1.94,4.84]; ork 32 E +7.19 [2.91,11.46]; pooled +2.01 se 1.08 z 1.86). Last shard aud_ork_SHIP_3 (8 pairs) still running (M2 arm). LOOK 2 LAUNCHED EARLY (operational, not a decision): the 8 remaining look-1 pairs cannot change the look-1 outcome unless their mean E <= -22.9 VP (futility) or >= +35.8 VP (efficacy); look-1 decision is recorded formally when the shard lands; if it were futility/efficacy, the look-2 games are discarded. Look 2 = creator_dirs/aud2 (seed bases +100), creator agent running. Check-in 23 at ~15:25.
- 14:29 AUD LOOK 1 FORMAL DECISION = CONTINUE (decide_v2_AUD_look1.json): 123/124 pairs (seed 94061 M2 timed out at the 2400 s cap, confirmed in the shard's transcript; pair dropped as incomplete; the decision does not depend on it). cus 42 E -2.61 se 1.68 [-5.91,0.69]; asy 42 E +1.45 se 1.73 [-1.94,4.84]; ork 39 E +8.73 se 2.12 [4.58,12.89]; pooled E +2.53 se 1.07 z 2.36 < 3.710 (no efficacy); pooled E > 0 (no futility); fixture-safe (no CI wholly < 0). Look 2 already running (launched 14:2x). Strong fixture heterogeneity: Orks mirror clearly positive, Custodes mirror leaning negative.
- 14:3x AUD LOOK 2 sessions created: 11 (aud_*_SHIP_L2_*), FAILED none.
- 14:3x AUD look-1 DIAGNOSTIC (information only, post hoc; no arm or decision changes): cand advantage per pair = cus primary -1.50 / secondary -1.11; asy +0.17 / +1.29; ork +5.83 / +3.21. Fix fires per game: cus OBJ_AREA_REACH 233, ON_OBJ 205, HOLD 104, CHARGE_REROLL_ODDS 69 (Custodes-only), CHARGE_OW_11E 37, MOVE_TERRAIN 0; ork MOVE_TERRAIN_11E 307 (Ork-only), OBJ_AREA_REACH 241, ADV_ENGINE_PREDICATES 54, WAAAGH_ADV_REROLL 34. Hypothesis for later (only testable with switch-off arms after efficacy, per the registration): Ork-specific fixes carry the Ork gain; CHARGE_REROLL_ODDS / OBJ_AREA_* may carry the Custodes loss. Worst Custodes-mirror cards (cand-base VP): outflank -36, overwhelming_force -29, forward_position -25, beacon -21.
- 14:59 AUD look-2 shard aud_cus_SHIP#L2_1 saved; archived. (Worker restart ~14:55 interrupted the report publish; resuming it.)
- 15:08 AUD look-2 shards aud_cus_SHIP#L2_2 and #L2_0 saved (cus look 2 complete); archived.
- 15:30 REPORT PUBLISHED: artifact https://claude.ai/artifact/YWRAdHeM7gBJTKAZJDnYZJ (slug ff26c2b6) version 1793460607-4fe6 (was 1793360876-4088; rounds 1-2 only). New page: rounds 1-5, protocol v2, h2 re-checks, rules audit, audit bundle + AUD look 1 (continue), reserve track (screen parked), stale-bench finding + fixture proposal, tuning proposal (hold), lessons, open decisions; STE, TLDR on top; fact-checked + STE/page-checked (375/1000 px, light/dark). I read the full text (base64 images stripped) before publishing.
- 15:31 CHECK-IN 23 done: AUD look 2: cus 3/3 shards saved; asy 0/3, ork 0/5 running. Check-in 24 at ~16:31.
- 15:3x AUD interim: Custodes mirror cumulative after look 2 (84 pairs; look-2 cus alone 42 pairs E -3.19 [-7.13,0.74]): E -2.90 se 1.30 CI [-5.45,-0.35] = WHOLLY BELOW 0 -> per the registered efficacy rule (no fixture CI wholly < 0), AUD cannot ship at look 2 regardless of z; continues to look 3 only if pooled E > 0 (futility otherwise). Formal look-2 decision when asy/ork L2 shards land. Possible later option (user decision, new registration): an Ork-specific sub-bundle.
- 15:31 AUD look-2 shards aud_asy_SHIP#L2_0, #L2_1 saved; archived.
- 15:37 AUD look-2 shard aud_asy_SHIP#L2_2 saved (asy look 2 complete); archived.
- 15:4x USER: complete running jobs, start nothing new. Check-in 24 deleted. Remaining: 5 AUD look-2 Ork shards (aud_ork_SHIP_L2_0-4). After they land: record the look-2 decision only; do NOT launch look 3 or anything else.
- 15:45 AUD look-2 shard aud_ork_SHIP#L2_4 saved; archived. 4 ork L2 shards left.
- 15:45 AUD look-2 shard aud_ork_SHIP#L2_3 saved; archived. 3 left.
- 15:53 AUD look-2 shard aud_ork_SHIP#L2_1 saved; archived. 2 left.
- 15:54 AUD look-2 shard aud_ork_SHIP#L2_0 saved; archived. 1 left (L2_2).
- 15:59 ALL JOBS COMPLETE (0 live sessions). AUD LOOK-2 DECISION (decide_v2_AUD_look2_manual.json; registered formula; decide_v2.py skips look 2 because look 1 has 39/40 ork pairs): cus 84 E -2.90 [-5.45,-0.35]; asy 84 E +2.89 [+0.51,+5.26]; ork 79 E +7.52 [+4.83,+10.21]; pooled E +2.50 se 0.75 z 3.34 >= 2.512 BUT Custodes CI wholly < 0 -> NOT fixture-safe -> NO SHIP at look 2; pooled E > 0 -> no futility; protocol says continue to look 3, NOT launched per user's freeze. All FIX_ params stay 0.
