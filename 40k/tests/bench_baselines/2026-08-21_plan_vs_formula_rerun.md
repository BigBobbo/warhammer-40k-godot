# Plan vs formula, re-run — the A/B the fixes were for

**Date:** 2026-08-21
**Branch:** `claude/plan-maker-todo-w0syuf` @ `c507424`
**Fixture:** `mirror_orks_2000_predeploy` (rebuilt under PM-F3; gate PASS, sha256 `69e30a89a221`)
**Plan under test:** `res://data/ai_plans/orks_recon_stomps_crucible.json` (re-authored under PM-F7 for the true triangle)
**Arms:** `plans_on.json` vs `plans_off.json`, same plan file on both seats; A/A control arm
**Difficulty:** 1 — Normal. `--min-pairs 6 --max-pairs 6 --batch 6` — one look, at the end.
**Season:** `seasons/2026-08-21_pmf_rerun` (user data dir)

This is the re-run the PM-10 report said its numbers needed: the original was
measured on a stale board no menu game can produce (PM-F3), with a consumer
that discarded placements (PM-F4), embarked plan units into transports
(PM-F5), and stalled a third of the sample (PM-F6). All four are fixed and
the plan itself was re-authored as a rehearsal (PM-F7). **The numbers below
are therefore NOT comparable to `2026-08-11_plan_vs_formula.md` — they
replace it as the baseline.**

---

## VERDICT

**The stall gate that failed in PM-10 now passes: 18 of 18 games completed,
zero stalls, zero timeouts, 6 usable pairs of 6 planned.** Seeds 9001 and
9005 — the two the original run lost, deterministically, on the plans-OFF
seat — completed in both paired arms and the A/A arm. That closes the second
half of PM-F6's validation gate.

**Adherence is total, in every game.** The plans-ON seat made 15 plan-sourced
deployment decisions (11 placements + 4 reserves) with **0 repaired** in all
12 paired games — every placement taken exactly as authored. The 2
formula-fallback decisions per game are the attached Wartrikes: a predeploy
fixture starts at DEPLOYMENT with FORMATIONS already gone, attachments cannot
be retrofitted (documented PM-2b behaviour), so on this fixture the Wartrikes
deploy by formula. Measured harmless — nothing they did cost a planned unit
its spot. In a from-the-menu game FORMATIONS runs, the attachments happen,
and the same plan measures 11/11 exact (`sp/pm10_shipped_plan_from_menu`).

**The VP effect is a null, at three times the old resolution:**

    E (plans_on − plans_off) = +0.92 VP/game   se 2.17   95% CI [−3.33, +5.16]   n = 6

The pre-registered rule (fixed before the run): accept at |E| ≥ 4.0 VP and
2 se; futile once se ≤ 1.60 with the interval inside ±4.0. E = +0.92 accepts
nothing; se = 2.17 is not yet futile; at max-pairs the formal verdict is
CONTINUE, which at the cap reads: **no measurable VP effect at a resolution
that would have flagged a 4-VP effect**. The old run could not see anything
smaller than ±13.7; this one resolves ±4.3. E is again not negative, which
is the sanity floor the gate asks for.

The honest case for plans is unchanged and now better evidenced: the AI does
exactly what the plan says (0 repairs, 12 of 12 games), on a board that is
now the real board, without the stall that used to eat the sample — and it
does not measurably win more.

## The numbers

Per-seed margins are `vp_diff_p2_minus_p1` as recorded; in M1 the plans-ON
seat is P2, in M2 it is P1, in AA both seats run plans_off.

| seed | M1 | M2 | AA | E_seed = (M1−M2)/2 |
|---|---|---|---|---|
| 9001 | −22 | −13 | −2 | −4.5 |
| 9002 | −31 | −41 | −31 | +5.0 |
| 9003 | 0 | 0 | +5 | 0.0 |
| 9004 | −10 | −5 | −28 | −2.5 |
| 9005 | +1 | −18 | −4 | +9.5 |
| 9006 | −17 | −13 | −29 | −2.0 |

    E = +0.92  (sd 5.31, se 2.17)
    F (structural bias, paired) = −14.08  se 5.05
    F (A/A arm)                 = −14.83
    harness guard |F_paired − F_AA| = 0.09 se  →  OK

F says the rebuilt fixture favours player 1 by ~14 VP whoever plans — about
what the old stepped board showed and consistent between the paired and A/A
arms, so the pairing is doing its job of cancelling it out of E.

All 18 games ran 5 full battle rounds, 679–844 actions, 367–743 s wall at
time-scale 6, lanes 2.

## What would move E off zero

Not deployment fidelity — that is now saturated (0 repairs). The plan's
remaining levers are the earmarks (PM-3 biases) and the plan CONTENT itself,
which is still a claude-draft nobody has played against. A content pass by a
player, measured against this baseline with the same pre-registered rule, is
the experiment this file exists to anchor.
