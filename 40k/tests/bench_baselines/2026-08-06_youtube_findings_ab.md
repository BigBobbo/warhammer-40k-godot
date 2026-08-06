# YouTube-corpus findings A/B — 2026-08-06

**What is being tested.** The four high-priority general findings mined from
1,029 Warhammer 40k 11th-edition YouTube transcripts
(`research/youtube/ai_learnings.json`), as implemented in commit
`af999b8`:

| finding | change |
|---|---|
| F001 | `WEIGHT_HIDDEN_GAINED` 4.0 — movement prefers destinations that leave INFANTRY/BEASTS/SWARM Hidden (13.09), scaled by the fraction of enemy shooters the position actually hides from |
| F002 | `HIDDEN_FORFEIT_PENALTY` 3.0 — a Hidden unit prices the two-turn cost of shooting and declines chip shots |
| F003 | `HIDDEN_WINDOW_BONUS` 1.25 — enemies about to regain Hidden get a modest target-priority boost |
| F004 | `OVERWATCH_EXPOSURE_PENALTY` 0.35 — movement pays for the Overwatch exposure it *creates*, weighted by incoming shot volume |
| F007 | deep-strike denial radius derived from `GameConstants.reinforcement_min_enemy_distance_inches()` (11e: >8") instead of a hardcoded 9", and tightened by any enemy reserve advertising a shorter arrival |
| F009 | `BATTLE_SHOCK_DENIAL_WEIGHT` 1.0 — battle-shock scored as a route to flipping objectives, priced in swung VP × real failure probability |

F006 was deliberately **not** implemented as written — its "gap must be under
enemy base + 2 inches" mechanism is a 10th-edition rule. See the commit
message and the `SCREEN GAP GEOMETRY` block in `AIDecisionMaker.gd`.

## Method

Same shape as the 2026-07-10 Ork discipline baseline: P2-only profiles, fixture
`audit_baseline_postdeploy` (Custodes P1 vs Orks P2, round 1 Command,
post-deployment), **Hard** (difficulty 2), seeds 2001–2010, `BENCH_TIME_SCALE=3`,
`BENCH_MAX_SECONDS=600`.

```bash
# control arm — P2 plays the pre-change AI
BENCH_SEED_BASE=2000 BENCH_DIFFICULTY=2 bash 40k/tests/run_ai_benchmark.sh \
  10 audit_baseline_postdeploy "" res://tests/bench_profiles/yt_findings_off.json

# treatment arm — P2 plays the findings
BENCH_SEED_BASE=2000 BENCH_DIFFICULTY=2 bash 40k/tests/run_ai_benchmark.sh \
  10 audit_baseline_postdeploy "" res://tests/bench_profiles/yt_findings_on.json
```

**What the two arms actually compare.** The findings ship as code *defaults*, so
player 1 has them in both arms. The control arm is therefore
**old-AI-as-P2 vs new-AI-as-P1**, and the treatment arm is **new vs new**. The
difference between the arms is exactly the effect of upgrading P2 from the old
behaviour to the new one, head to head against an identical opponent.

**Why the margin is the wrong headline here.** `vp_diff_p2_minus_p1` is a
*relative* metric, and it was the right one for the Ork discipline test because
that change was asymmetric (an Orks-only constant). These findings are
general — they help whoever holds them — so a margin that barely moves is the
expected signature of a change that is symmetric in kind even when it is applied
to one side. The metrics that isolate the treated player (P2 primary VP, P2
total VP, stall rate) are reported alongside and are more sensitive.

**Control-arm validity.** A control arm is only worth reporting if it is really a
control. `tests/scenarios/sp/ai_hidden_awareness_11e.json` (steps 21–22) loads
`yt_findings_off.json` and replays an identical shooting decision: with the
profile the AI returns `SHOOT`, and with it cleared the same decision returns
`SKIP_UNIT`. The kill-switch demonstrably disables the behaviour.

> Note for anyone re-running these: the two arms were run concurrently and Godot
> interleaved both processes into the same `user://logs/` file, so per-arm
> attribution of `print()` lines from those logs is unreliable. Run the arms
> sequentially, or attribute from the per-game JSON under
> `test_results/bench/`, which is stamped per run.

## Results

### Aggregate (10 seeds per arm, Hard)

| arm | games | completed | stalled | avg VP diff (P2−P1) | sd | P2 primary/game | P2 total/game | P1 total/game |
|---|---|---|---|---|---|---|---|---|
| **OFF** (P2 = pre-change AI) | 10 | 9 | 1 | **−44.5** | 8.7 | 17.2 | 31.3 | 75.8 |
| **ON** (P2 = findings) | 10 | 10 | 0 | **−43.7** | 6.2 | 19.0 | 36.2 | 79.9 |

### Per seed

| seed | OFF | ON | delta (ON−OFF) |
|---|---|---|---|
| 2001 | −44 | −44 | 0 |
| 2002 | −30 * | −49 | −19 |
| 2003 | −57 | −48 | +9 |
| 2004 | −33 | −43 | −10 |
| 2005 | −41 | −36 | +5 |
| 2006 | −58 | −49 | +9 |
| 2007 | −44 | −31 | +13 |
| 2008 | −40 | −41 | −1 |
| 2009 | −48 | −43 | +5 |
| 2010 | −50 | −53 | −3 |

`*` = seed 2002 in the OFF arm stalled at round 4 ("no progress for 90s"); its
margin is from the state reached, which flatters the OFF arm because the game
ended before P1 could finish scoring.

**Paired delta: +0.8 VP, sd 9.7, se 3.1 — 0.26 standard errors from zero.**
Six seeds improved, three worsened, one tied.

## Conclusions

1. **The margin did not move. This A/B does not demonstrate that the findings
   win more games.** +0.8 ± 3.1 VP is indistinguishable from noise, and honesty
   requires saying so plainly rather than reaching for the secondary metrics.
   At the observed per-seed spread (sd ≈ 9.7 on the paired delta), detecting a
   5 VP effect at 2 standard errors would need roughly 60 seeds per arm — about
   8 hours of wall clock at this fixture's ~2.5 min/game. The 10-seed run that
   settled the Ork discipline question could resolve it only because that effect
   was ~14 VP; these findings are not that size in this matchup.

2. **What did move, weakly and with a caveat.** P2's primary VP rose 17.2 → 19.0
   (+10%) and its total 31.3 → 36.2 (+16%). But P1's total rose too
   (75.8 → 79.9), which is why the margin is flat — so this is *not* clean
   evidence of a one-sided gain, and should not be quoted as if it were.

3. **One robustness result that is not noise-shaped.** The OFF arm stalled once
   in ten games; the ON arm stalled zero times in ten, and its margin spread is
   narrower (sd 8.7 → 6.2). The F002 hold-fire path adds a new `SKIP_UNIT`
   return to the shooting loop, so "does it hang?" was a live risk — it does not.

4. **The mechanisms are verified even though the win-rate is not.** Correctness
   evidence lives in `tests/scenarios/sp/ai_hidden_awareness_11e.json` (24/24):
   the AI's Hidden verdict matches TerrainManager's, the probe discriminates
   cover from open ground, the denial radius resolves to 8" not 9", the real
   "Suggest (K)" button surfaces the hold-fire reasoning to the player, and the
   control (`shot_recently=true`) flips the same decision back to SHOOT. F007's
   9"→8" correction in particular is a straight bug fix against a rule the
   engine already implements — it needs no win-rate evidence to justify.

5. **Why this fixture may be the wrong instrument.** `audit_baseline_postdeploy`
   is a lopsided matchup (P1 wins by ~44 VP in both arms). Hidden rewards
   infantry that can reach dense terrain and survive there; an Ork list being
   ground down from round 2 rarely gets to bank two clean turns of
   untargetability. A closer fixture, or one with more dense terrain in the Ork
   half, would test these findings more fairly. Recommended before tuning any
   of these constants further.

6. **Not tuned.** The shipped values are the corpus-suggested starting points,
   not benchmark-optimised ones. Nothing here justifies raising them; if
   anything, a fixture that can resolve the effect should come first.
