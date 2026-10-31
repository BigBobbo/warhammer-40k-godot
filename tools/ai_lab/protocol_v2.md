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

## Arm registrations

### AUD — V2-4 rules-audit bundle (registered 2026-10-31 12:27 UTC, before its first bench game)
- Candidate: commit ca913e2 with `bash tools/ai_lab/audit_fixes/flip.sh` (no arguments) applied in the worker, which
  turns ON the 11 fixes that passed the V2-1 fix gate: FIX_OBJ_AREA_REACH, FIX_OBJ_AREA_ON_OBJ, FIX_OBJ_AREA_HOLD,
  FIX_EOG_TIMING, FIX_MOVE_TERRAIN_11E, FIX_CHARGE_OW_11E, FIX_HI_CHARGE_ODDS, FIX_CHARGE_REROLL_ODDS,
  FIX_PILEIN_TARGETS_11E, FIX_ADV_ENGINE_PREDICATES, FIX_WAAAGH_ADV_REROLL. Parked (stay 0): FIX_SECURED_AWARE (0 lines
  per game), FIX_CO_NEXT_PICK (0.83). Base: SHIP = e12e6e8 (1.56.8), extracted with ai_versions.py.
- Fix-gate counting (registered 06:5x, before the gate data): a fix's [FIX_<NAME>] line prints once per evaluation where
  the fix changes a value the old code used; pass = >= 1.0 line per game over the 6 gate games.
- Design: V2-2 as above (looks 124/248/372 pairs on the registered seeds; --rules11e; difficulty 3; --max-seconds 1800,
  2400 for the Orks mirror; --lanes = nproc; one arm per container season). Decision by .ai_lab_work/decide_v2.py with
  file pattern 'aud_%s_SHIP_'.
- Ship only on efficacy (z >= 3.710 / 2.512 / 1.993 at looks 1 / 2 / 3 AND no fixture 95% CI wholly below 0).
  Futility (non-binding): stop at look 1 or 2 if pooled E <= 0. No switch-off arms unless efficacy is crossed.
- No extra fixture gate for this arm: the proposed current-list fixture (tools/ai_lab/fixture_proposal.md) is not built;
  if it is built later, its result is information only for AUD.
- Per-tag fire counts are reported for information. If AUD ships: the 11 consts become 1.0, a version_history.json entry,
  a windowed scenario + live screenshot, and the 6 unit-test checks that fail with all fixes on are updated (they assume
  the other new fixes are off).
