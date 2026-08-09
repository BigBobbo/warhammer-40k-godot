# Large-army AI overhaul — 2026-08-09

Owner ask: stop the small tweaks; from the foundations up, make the AI able
to deploy and play a FULL game with the 77-model Ork Speedwaaagh! list
(`recon_stomps`), including a mirror match, so training runs can use it.
Suggested directions: treat a squad as one thing and move what fits ("the
ones that succeed, deal with the rest after" — the human multi-select drag),
dense packing, transports, reserves.

## What the evidence said (mapped this session, three parallel deep-dives)

1. **The hang was never density or the enemy.** Root cause (commit e3d4b19):
   one boxed-in unit walks a ~78-rung fallback ladder inside ONE decision
   call — 6 strict fractions, 6 formation, 8 angles, 58+ relaxed-radius —
   and every rung demands EVERY model be placed. No memory between rungs, no
   "this unit cannot move" conclusion, no frame yielded, so no stall
   detector can see it. 280–400 s for one unit, repeated per sub-decision
   and per AIPlayer's 3-scale staging recompute.
2. **The engine already supported the human answer.** AIPlayer confirms
   partial staging ("un-staged models stay in place") — the all-or-nothing
   rule was self-imposed by the AI's mover.
3. **Deployment was AABB-blind.** Every generator/clamp used the zone's
   bounding box; the polygon was consulted only for wall retries. On
   Crucible of Battle (triangle; AABB is 2x the zone) 2/17 unit centroids
   landed OUTSIDE the polygon — engine rejections, retry ladders, and a
   possible deadlock (cap-rejected reserves fallback left END_DEPLOYMENT
   permanently invalid). Deploy order was army-JSON order: the 180mm Stompa
   went LAST into a fragmented zone (the fixture packer had already hit and
   fixed this exact failure).
4. **Transports and reserves were dead code.** All ~42 tuned embark/reserve
   parameters sat behind the Formations phase — which every fixture ships
   pre-confirmed, so it auto-completes before the AI can act. On top of
   that, the AI's embark keyword test used ANY-match where the engine
   demands ALL, so its first Stompa declaration would be rejected and the
   transport blacklisted for the game. And `sc01`'s status assertion
   compared against a string the engine never writes — the exam could not
   fail.

## What shipped (all parameters, baseline arm = `large_army_moves_off.json`)

Movement (`AIDecisionMaker.gd`):
- `MOVE_PARTIAL_SQUAD` (ON): per-rung, models that can move do move; blocked
  models hold position; the congestion bail stops paying the per-model
  search but keeps placing free movers; the final coherency gate checks the
  moved+stayed union. The ladder usually collapses to its first rung.
- `MOVE_STUCK_EARLY_EXIT` (ON): all strict fractions with zero movers ⇒
  skip the remaining ~60 rungs, memoise (unit, round) as stuck; the memo
  short-circuits every later ladder invocation that round. Cleared on round
  change and game load.
- `MOVE_SEARCH_BUDGET` (20k): deterministic ceiling on candidate positions
  per computation — work units, not wall clock, so identical inputs still
  produce identical decisions. The full-ladder-failed path also memoises.

Deployment (`AIDecisionMaker.gd`, `AIPlayer.gd`):
- `DEPLOY_LARGEST_FIRST` (ON): biggest base deploys first.
- `DEPLOY_POLYGON_AWARE` (ON): centre projected into the polygon; formation
  generator and collision resolver reject/project candidates not wholly
  inside it (centre + edge-distance test, engine-conservative for ovals);
  resolver reuses the movement spatial grid, queried per candidate.
- Retry ladder samples wholly-in-polygon centres; reserves fallback retries
  once with the P2-42 `auto_timeout` bypass — deployment can no longer
  deadlock.

Formations reachability (`Main.gd`, `make_2000pt_fixture.gd`, exams, lab):
- `--preformations` fixture mode (live phase 0, nothing confirmed);
  `mirror_orks_2000_preformations` committed and gated by `fixture_check`
  (which also learned phase 0 is pre-placement, fixing an `or -1` parse bug
  that collapsed FORMATIONS(0) to -1).
- Main no longer pops the human formations dialog over an AI active player.
- Embark keyword test is ALL-match, mirroring the engine.
- `sc01` runs the live Ork formations phase, asserts with the int status
  enum, and additionally asserts the phase ran.

## Measured so far (this session)

- `sc01`: PASS 2/2 — the AI embarked Gretchin Alpha+Beta into the Stompa
  (22/22 capacity) and kept declared reserves at 26% of points. First
  automated game in the repo's history where either code path executed.
- Live on the diagnosed unit (Ork postdeploy mirror, seed 7001):
  "Warbikers Delta: MOVE_SEARCH_BUDGET exhausted (40051 candidates);
  holding this round" — bounded and memoised where it used to be minutes
  inside one frame.
- Full-game runs and the paired Custodes A/B: see the bench records
  committed with this branch / the PR description for final numbers.

## Deliberate deviations

- Defaults ON (the repo convention for behaviour changes is OFF-until-gated).
  Reason: these are robustness fixes for a hang that makes the Ork mirror
  unusable — the state the owner explicitly asked to fix. The OFF profile
  reproduces the old behaviour for A/B, and the paired evaluator run is part
  of this same change, not deferred.
- The stuck-unit memo write on the full-ladder-failure path is unconditional
  (not parameter-gated): the outcome ({} → hold) is identical either way;
  only wasted recomputation is skipped. Decision-trajectory preserving.

## Still open (next sessions)

- Ork-mirror A/A baseline (10 seeds) to replace the UNUSABLE row, then
  restore the Ork mirror to `gate_candidate.MIRRORS` and un-park `sc02`.
- Paired A/B at full budget on both mirrors for the bundle (this session
  runs a first Custodes campaign; more pairs shrink the CI).
- Search and Destroy / Dawn of War fixtures: the fixture builder still
  inherits the shell's Crucible zones; polygon-aware deployment removes the
  AI-side blocker, but `make_2000pt_fixture._pack()` and `_summarise()`
  assume top/bottom rectangles, and Dawn of War's left/right strips still
  invert the AI's `is_top_zone` depth logic (documented, not fixed).
- Disembark placement on dense boards: P1's round-1 CONFIRM_DISEMBARK was
  rejected (positions overlapped its own line) and correctly blacklisted
  for the phase; a placement search like the reinforcement path's would
  let it out earlier.
- Tactical quality of partial moves (tail models holding) — a
  paired-evaluator question, now measurable at all.
