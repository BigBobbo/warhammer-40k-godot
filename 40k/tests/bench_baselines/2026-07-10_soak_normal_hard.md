# AI benchmark baseline — 2026-07-10 soak (Normal + Hard)

Fixture `audit_baseline_postdeploy` (Custodes P1 vs Orks P2, Take and Hold,
Search and Destroy), seeds 2001–2010 per lane, `BENCH_MAX_SECONDS=420`,
time scale 3. Deterministic dice **and** secondary-deck draws (both seeded).

The soak ran on the coordinated-movement build (commit `8ca6183`); the three
stalls it found were fixed in the same session (SOAK-1..3, committed with
this report) and each failing seed was re-run to completion — post-fix rows
below. **Stall gate for future runs: 0.**

## Lane: Normal (difficulty 1)

Games: 10 (8 completed, 2 stalled) · P1 wins 8/8 completed · Avg VP diff (P2−P1): −31.9

| seed | status | winner | VP P1 | VP P2 | rounds | wall s | note |
|---|---|---|---|---|---|---|---|
| 2001 | completed | 1 | 54 | 34 | 5 | 215.5 | |
| 2002 | completed | 1 | 75 | 46 | 5 | 218.5 | |
| 2003 | completed | 1 | 76 | 22 | 5 | 185.6 | |
| 2004 | completed | 1 | 58 | 29 | 5 | 237.8 | |
| 2005 | completed | 1 | 63 | 32 | 5 | 227.0 | |
| 2006 | completed | 1 | 51 | 32 | 5 | 224.9 | |
| 2007 | **stalled** | — | 44 | 31 | 5 | 258.8 | R5 movement — action-cap + Sawbonez window (SOAK-1) |
| 2008 | completed | 1 | 71 | 32 | 5 | 200.7 | |
| 2009 | completed | 1 | 68 | 34 | 5 | 208.1 | |
| 2010 | **stalled** | — | 58 | 28 | 4 | 233.1 | R4 movement — same freeze (SOAK-1) |

## Lane: Hard (difficulty 2)

Games: 10 (9 completed, 1 stalled) · P1 wins 9/9 completed · Avg VP diff (P2−P1): −27.3

| seed | status | winner | VP P1 | VP P2 | rounds | wall s | note |
|---|---|---|---|---|---|---|---|
| 2001 | completed | 1 | 54 | 22 | 5 | 193.4 | |
| 2002 | completed | 1 | 68 | 56 | 5 | 223.9 | |
| 2003 | **stalled** | — | 37 | 8 | 4 | 348.7 | R4 fight — cap after wrong-player stratagem rejections (SOAK-1/2) |
| 2004 | completed | 1 | 57 | 29 | 5 | 245.2 | |
| 2005 | completed | 1 | 65 | 19 | 5 | 243.6 | |
| 2006 | completed | 1 | 69 | 32 | 5 | 239.7 | |
| 2007 | completed | 1 | 55 | 48 | 5 | 200.1 | |
| 2008 | completed | 1 | 46 | 39 | 5 | 210.9 | |
| 2009 | completed | 1 | 67 | 32 | 5 | 234.8 | |
| 2010 | completed | 1 | 66 | 24 | 5 | 221.8 | |

## Post-fix re-runs of the failing seeds (SOAK-1..3 applied)

| seed | lane | status | winner | VP P1 | VP P2 | rounds | wall s |
|---|---|---|---|---|---|---|---|
| 2007 | Normal | completed | 1 | 63 | 44 | 5 | 191.6 |
| 2010 | Normal | completed | 1 | 61 | 53 | 5 | 205.0 |
| 2003 | Hard | completed | 1 | 66 | 29 | 5 | 196.5 |

## Root causes fixed (details in commit)

- **SOAK-1** — `AIPlayer` action cap measured volume (every model stage
  counted), so big late-round phases hit 200 legitimately; the cap escape
  only knew `END_*`, so sub-states (Sawbonez heal window, fight selection)
  froze the game. Counter now resets on every successful phase action
  (consecutive non-progress detector) and the escape is tiered
  (END → DECLINE/SKIP → any offered action).
- **SOAK-2** — `FightPhase` validated/processed `USE_STRATAGEM` against the
  turn owner, rejecting every legal opponent's-turn fight stratagem; the AI
  burned its budget retrying. Now uses the action's submitting player.
- **SOAK-3** — the fight-order plan was one shared static both AIs consumed
  (second AI picked units it doesn't own → rejection → premature
  `END_FIGHT`); now per-player, and only units actually offered are chosen.
- Also: AI Sawbonez heals previously dropped `target_model_index` (silent
  no-op heal); the decide branch now picks the most-wounded offered target.

## Observations (signals, not gates)

- **P1 (Custodes) sweeps both lanes** (17/17 completed games pre-fix). Avg
  VP margin is *smaller* at Hard (−27.3) than Normal (−31.9), and Hard
  produced the closest games (−7 twice). Likely a mix of matchup imbalance
  in this fixture (elite Custodes vs Orks), first-turn advantage, and Ork AI
  underperformance — separating those needs a mirror-match fixture and/or
  side-swapped runs. Candidate follow-up for the next AI-quality pass.
- Wall clock ~185–260 s/game at time scale 3 → a 10-game lane ≈ 35–40 min;
  two lanes run comfortably in parallel on 4 cores.
