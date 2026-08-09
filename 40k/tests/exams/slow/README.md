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

3. *The obstacle scan being a linear pass over all 154 models.* Profiled and
   fixed — and it was real, but not sufficient. Eight seconds of one movement
   phase (~2 unit moves) was doing **3.08 million obstacle iterations**, of
   which 99.95% of the exact-overlap work was a distance pre-filter throwing
   the obstacle straight back out. A uniform spatial grid cut it 4.1x/4.4x and
   roughly halved the phase, verified behaviour-preserving (both Custodes seeds
   reproduce the pre-change margin and action count exactly). The fixture still
   does not leave battle round 1.

**Where it actually stands.** ~2x achieved against the ~20-50x this fixture
would need. The remaining cost is not the cost *per* query but the **number of
queries**: 14,153 collision tests and 8,783 exact-overlap tests for two unit
moves. That comes from the structure of the search — 6 move fractions x ~6
models x 28 candidate positions x several predicates each, with no memory
between attempts. Making that cheaper means changing the search, not the
lookup: cache a unit's failure so a boxed-in unit does not re-derive it six
times, cut the fraction ladder once a unit is known stuck, or compute a
free-space map once per phase instead of per candidate. That is a design change
with its own measurement, and it has not been attempted. The profiling counters
(`_dump_collision_profile`) are left in the code so the next attempt starts
from numbers rather than from a reading of it.

**Until then:** the screening path has no automated guard. It is exercised in
real games (6 SCREEN plan lines in a 306-line 2000-pt game), so it is not
untested — it is unguarded against regression.
