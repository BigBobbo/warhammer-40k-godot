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

**What would fix it.** The packer uses a fixed 10 px step and first-fit from
the top edge, which minimises area used and therefore maximises contact. The
zone is only 58.6% full — there is room to spread. Packing to a target gap of
~0.5-1" instead of "as tight as legal" would both make this exam affordable and
produce a deployment a player might actually field. That is a fixture rebuild,
so it invalidates the A/A numbers measured on the current packing and should be
done deliberately, not mid-season.

**Until then:** the screening path has no automated guard. It is exercised in
real games (6 SCREEN plan lines in a 306-line 2000-pt game), so it is not
untested — it is unguarded against regression.
