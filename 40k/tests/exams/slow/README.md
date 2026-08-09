# Exams that are correct but do not fit the suite's time budget

An exam here is **not** aspirational — aspirational exams fail by design until
the task that owns them lands. These exercise real behaviour and would pass;
they are parked because a single run costs more wall clock than the whole
gated suite is allowed. They are excluded from `run_exams.sh --suite` and run
by name or with `--slow`.

Parking one is a debt, not a resolution. Each entry below names the measured
cost and the specific thing that would make it affordable again.

## `sc02_screen_covers_the_gap`

**Measured:** did not produce a verdict within 1500 s (niced, sharing 4 cores
with a 2-lane benchmark season). An earlier run at 700 s also timed out.

**Why it is here and not in the gated suite.** The behaviour is real — the log
shows `AIDecisionMaker: [SCREEN] Assigned Gretchin Alpha to SCREEN-PROTECT`,
which is exactly what the exam asserts about. It cannot run anywhere cheaper:

* On the **Custodes** mirror the branch is unreachable by construction.
  Screening is only offered to units still unassigned after objective
  assignment (`if assigned_unit_ids.has(unit_id): continue`), and 11 units
  across 5 objectives never leaves one spare — the objective pass absorbs
  everyone, including four units "reinforcing" a single marker.
* On the **Ork** mirror it is reachable — 17 units do leave cheap mobs
  surplus — but the movement phase there is pathologically slow.

**The actual cost driver, measured.** It is not the model count on its own, it
is how tightly `make_2000pt_fixture.gd` packs them:

```
mirror_orks_2000_postdeploy      77 models, 58.6% of the 44x14in zone
                                 nearest-neighbour gap: median 2.7px = 0.07 in
mirror_custodes_2000_postdeploy  42 models, 12.8% of the zone
                                 nearest-neighbour gap: median 4.1px = 0.10 in
```

Seventy-seven models at 0.07" spacing are effectively shoulder to shoulder, so
every model that tries to move is boxed in by neighbours and the mover grinds:
`INTRA_OBSTACLE_DEBUG ... FAILED to resolve collision`, repeatedly, for minutes.
The Custodes fixture is packed just as tightly but fills only an eighth of the
zone, so there is escape room around the block and it does not bite.

**What would fix it — and what does NOT.** Two hypotheses were tested and both
failed, so this is still open:

1. *Packing density.* The obvious read, and it is wrong. A rebuilt fixture with
   a **6x larger** median gap (0.42 in against 0.07 in) was still in BATTLE
   ROUND 1 after 14 minutes. Spacing is not the cause. Note also that the Ork
   list genuinely fills its zone: laid out as per-unit blocks, the blocks come
   to 80-87% of the 44x14in zone whichever layout is used, so there is not much
   room to spread even if it had helped.
2. *Moving the squad as a block* (`MOVE_RIGID_BLOCK_FIRST`, default off). A
   rigid translation of the whole unit, retried at shorter fractions — the
   player's drag-select-and-drag. It works on the Custodes fixture (82-88
   successful block moves per game) but scores **0 successes** here in a
   10-minute run: on a board this dense an all-or-nothing translation of 6+
   models past terrain essentially never has every model clear at once.

What that leaves is the per-model fallback itself. `_resolve_movement_collision`
runs a bounded search per colliding model against every other model on the
table, and the caller invokes it once per move fraction, so a congested unit
pays six full searches before anything cheap is tried — roughly 11 seconds for
a single unit's move on this fixture. The obstacle test is a linear scan over
all 154 models; a uniform-grid spatial index would cut it by a large constant
factor and is **behaviour-preserving**, which makes it the right next thing to
try. That is a profiling job, not a guess, and it has not been done.

**Until then:** the screening path has no automated guard. It is exercised in
real games (6 SCREEN plan lines in a 306-line 2000-pt game), so it is not
untested — it is unguarded against regression.
