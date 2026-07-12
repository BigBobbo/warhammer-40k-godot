# AI benchmark baseline — 2026-07-11 coordination rework soak (Normal + Hard)

Fixture `audit_baseline_postdeploy` (Custodes P1 vs Orks P2, Take and Hold,
Search and Destroy), seeds 2001–2010 per lane, `BENCH_MAX_SECONDS=420`,
time scale 3, pure defaults (no profiles). Both lanes run in parallel.

Code at commit `72f06a5` — the persistent-battle-plan build
(`docs/AI_REVIEW_2026-07-11.md` has the full review):

- COORD-4 persistent movement plan (announced plan == executed plan,
  consume/replan semantics, melee attack intents planned + narrated)
- COORD-4 support spreading (`SUPPORT_STACK_PENALTY`) and need backfill
- COORD-5 projected contest pressure (`PROJECTED_NEED_CAP`)
- COORD-6 reserves board-presence guard (SR comfort line at 25% points)
- Roll-off `_ai_player_override` (no more ~200-action cap burns)
- Shooting-UI re-entrancy fix (deferred auto-assign) — seeds 2001/2003
  hard-crashed (segfault / wedged main loop) on this build's parent with
  default seeds at Hard; both were used as deterministic repros for the fix

Reference baselines (committed in this directory):

- `2026-07-10_soak_normal_hard.md` — Normal avg (P2−P1) **−31.9**
  (P1 8/8 completed), Hard avg **−27.3** (P1 9/9), 3 stalls pre-SOAK-fix.
- `2026-07-10_mechanism_fixes.md` (commit b8cd630, Hard, defaults — the
  immediate parent lane of this build): avg **−49.4**, P1 sweep
  (per-seed −47, −44, −56, −52, −55, −46, −53, −61, −58, −22).

## Lane: Normal (difficulty 1)

Games: 10 (completed 10, stalled/error 0) · P1 wins 9, P2 wins 0, draws 1 · Avg VP diff (P2−P1): **−19.3**

| seed | status | winner | VP P1 | VP P2 | rounds | actions | wall s |
|---|---|---|---|---|---|---|---|
| 2001 | completed | 1 | 65 | 42 | 5 | 515 | 189.4 |
| 2002 | completed | 1 | 65 | 49 | 5 | 496 | 199.1 |
| 2003 | completed | draw | 52 | 52 | 5 | 558 | 201.0 |
| 2004 | completed | 1 | 70 | 36 | 5 | 532 | 216.8 |
| 2005 | completed | 1 | 79 | 34 | 5 | 506 | 191.7 |
| 2006 | completed | 1 | 67 | 55 | 5 | 530 | 201.2 |
| 2007 | completed | 1 | 58 | 42 | 5 | 553 | 209.1 |
| 2008 | completed | 1 | 58 | 44 | 5 | 559 | 197.7 |
| 2009 | completed | 1 | 68 | 52 | 5 | 540 | 203.1 |
| 2010 | completed | 1 | 62 | 45 | 5 | 582 | 204.2 |

## Lane: Hard (difficulty 2)

Games: 10 (completed 10, stalled/error 0) · P1 wins 8, P2 wins 1, draws 1 · Avg VP diff (P2−P1): **−7.2**

| seed | status | winner | VP P1 | VP P2 | rounds | actions | wall s |
|---|---|---|---|---|---|---|---|
| 2001 | completed | 1 | 55 | 52 | 5 | 538 | 213.7 |
| 2002 | completed | 1 | 55 | 54 | 5 | 542 | 211.3 |
| 2003 | completed | **2** | 47 | 49 | 5 | 518 | 190.2 |
| 2004 | completed | 1 | 52 | 46 | 5 | 552 | 200.7 |
| 2005 | completed | 1 | 60 | 40 | 5 | 529 | 190.6 |
| 2006 | completed | 1 | 65 | 54 | 5 | 595 | 232.1 |
| 2007 | completed | 1 | 70 | 57 | 5 | 594 | 221.7 |
| 2008 | completed | 1 | 57 | 55 | 5 | 589 | 217.9 |
| 2009 | completed | draw | 57 | 57 | 5 | 539 | 205.0 |
| 2010 | completed | 1 | 59 | 41 | 5 | 483 | 188.3 |

## Conclusions

1. **Stall gate: 0/20.** Every game completed all 5 rounds. The equivalent
   2026-07-10 soak had 3 stalls in 20, and this build's parent hard-crashed
   deterministically on 2 of the 3 smoke seeds at Hard before the
   shooting-UI fix. Wall times unchanged (~190–230 s at time scale 3).
2. **Margins tightened dramatically, most at Hard.** Normal −31.9 → −19.3;
   Hard −27.3 (or −49.4 on the parent build) → **−7.2**, with the first
   default-settings Ork win (seed 2003) and a dead draw (2009). Six of ten
   Hard games finished within 6 VP. The fixture matchup moved from
   one-sided to competitive.
3. **Attribution caveat:** the coordination rework is symmetric — both AIs
   got the persistent plan, spreading, and projected-need sizing — so the
   margin shift measures the matchup becoming less lopsided, not one side
   being buffed. That is consistent with the review's diagnosis: the Ork
   side was bleeding primary VP to uncoordinated play (plan thrash,
   stacking, silent chases), so fixing coordination for everyone helped
   the previously-worse-coordinated side more.
4. **Cross-difficulty signal:** Hard is now much closer than Normal
   (−7.2 vs −19.3). Hard's extra planning features (multi-phase planning,
   threat awareness) compound with the persistent battle plan; Normal
   skips them and stays more lopsided. If a future pass wants Normal
   tighter too, that gap is the lever to look at.
5. **Gate for future runs:** stalls remain a hard 0. Treat margin swings
   under ~10 VP / 2 games as noise at n=10 per lane.
