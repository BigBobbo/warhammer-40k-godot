# Mechanism fixes validation (SOAK-4 walls, SOAK-5 seek gate) — 2026-07-10

Validation lane: 10 seeds (2001–2010), Hard, standard fixture, pure defaults
(no profiles), code at commit `b8cd630`. 10/10 completed, zero stalls.

## What was fixed

- **SOAK-4:** AI movement destinations are now wall-tested with the engine's
  own `Measurement.model_overlaps_any_wall` at every candidate-acceptance
  point (placement, fallback, three resolver loops, formation).
- **SOAK-5:** melee-seek membership is melee-*focused* units only (single
  `_is_melee_seeker` gate replaces three divergent copies; the aggression
  expansion that captured shooty units is gone), and every seeker respects a
  chase cap (`MELEE_AGGRESSION_ADVANCE_THRESHOLD_INCHES`, ≥ own
  move+advance+charge reach). These apply to BOTH players.

## Behavior metrics (the primary lens — the fixes are symmetric)

| Metric | Before (soak) | After (this lane) |
|---|---|---|
| "Cannot end move overlapping a wall" | ~49 per game | **0.6 per game (6 total)** — −98.8% |
| Stuck-unit stationary fallbacks | ~18 per game (both sides) | **7.1 per game** (P1: 1.2, P2: 5.9) |
| P2 (Orks) primary VP | ≈ 6 per game | **12.6 per game** |
| P1 (Custodes) total VP | ≈ 61 per game | **74.9 per game** |

Remaining stuck-unit causes (residuals, next work items):
- **Wazbom Blastajet, 30 fallbacks** — "AIRCRAFT can only make ingress
  moves": the AI doesn't know the 11e AIRCRAFT movement rule and retries a
  normal move every round. Needs aircraft-aware movement decisions.
- **Boyz, 18 fallbacks** — horde congestion ("end on top of another model" /
  "through Monster or Vehicle" around the Battlewagon); placement usually
  recovers via the resolver, sometimes doesn't.

## Margins (secondary lens — cannot attribute symmetric changes)

Avg VP diff (P2−P1): **−49.4** vs −28.3 baseline / −15.1 Arm-A profile.
Per-seed: −47, −44, −56, −52, −55, −46, −53, −61, −58, −22.

The gap *widened* because the fixes helped the Custodes more: their two
most-stuck units in the soak were Caladius (67 fallbacks) and Witchseekers
(52) — both freed by the wall fix — and their own wasteful chases stopped
too, pushing P1 to 66–81 VP. The Orks' composition shifted (primary doubled,
incidental chase-driven secondaries fell ~4.5), netting roughly flat totals.

**Interpretation:** for the product (human vs AI), both AIs playing strictly
better is the goal and this delivers it. For AI-vs-AI margins, symmetric code
improvements shift the balance toward whichever army exploits them better —
use the per-player profile mechanism (as in the discipline A/B) when a
change must be attributed via margins.

## Follow-ups suggested by the residuals

1. AIRCRAFT movement handling (Wazbom does nothing all game — ~150 pts idle).
2. Horde placement congestion around friendly vehicles.
3. Consider an aggression-scaled chase cap (Orks may want board-spread back
   for engage-style secondaries — their secondary VP dropped when the chase
   behavior stopped producing it for free).
