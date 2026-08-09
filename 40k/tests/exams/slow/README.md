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

**ROOT CAUSE FOUND (2026-08-09).** It is none of the above. It is a single
boxed-in unit walking an enormous fallback ladder.

The owner pointed out that two armies cannot collide with each other in round
one — they deploy 20-30 inches apart — so the Orks had to be obstructing
themselves, and asked why that does not happen in `asym_2000_postdeploy`,
which holds the same 77 Orks. Both halves of that turned out to be right, and
chasing the second half found the bug.

Deleting the opposing army entirely (`40k/tests/make_probe_fixture.gd`) and
running the Orks alone:

| Orks alone, no enemy | packing | result | collision failures |
|---|---|---|---|
| deployment zone 1 | back-packed | stuck in round 1 at 280 s | 184 |
| deployment zone 1 | front-packed | stuck in round 1 at 400 s | 369 |
| deployment zone 2 | front-packed | **all 5 rounds in 131 s** | 23 |

So it is not the enemy, not the army, and not base ordering (front-packing
made it worse). It is also not the board: all 44 terrain pieces have an exact
180-degree twin, and each zone holds 5 pieces of identical area.

The action counts give it away:

| probe | actions | move decisions | succeeded |
|---|---|---|---|
| zone 2 | 782 | 99 | 99 |
| zone 1 | — | **1** | **0** |

One unit. One decision. 280 seconds. Warbikers Delta at (734, 358), 6 models
on 75mm bases, targeting `obj_home_2` at (880, 2240). Models m4, m5 and m6
cannot be placed, the unit early-bails at 3/6 failed — and then the same
attempt repeats with the same obstacles and the same result, 54 times before
the process was killed.

Those 54 are not a loop. They are rungs of the fallback ladder inside ONE call
to `_get_unit_move_destinations`, which tries, in order:

    6  move fractions            (1.0 .. 0.1)
    6  formation moves           (same fractions)
    8  alternate angles          (4 angles x 2 fractions)
   15  relaxed collision 0.85x   (5 angles x 3 fractions)
   15  relaxed collision 0.70x   (5 angles x 3 fractions)
   28+ relaxed collision 0.50x   (7+ angles x 4 fractions)
   ----
   ~78 full attempts, each a per-model search against every model on the table

On a crowded board each rung costs seconds, so one genuinely stuck unit
consumes minutes. There is no early exit that concludes "this unit cannot
move, leave it and move on". Worse, it all happens inside a single decision
call, so the engine never gets another frame — which is why neither the
90-second stall detector nor the benchmark's own `max_seconds` fired.

**This is an AI robustness bug, not a fixture defect.** Any unit that gets
boxed in — by its own army, in a real player's game — will hang the turn the
same way. The fixture merely makes it reproducible.

**The fix is an early exit, not a faster search.** Once a unit has failed the
strict modes with the same models failing for the same reason, the remaining
~60 rungs cannot succeed; they differ only in how far and at what angle it
tries to go, and the blocker is adjacent. Detect "no model can be placed at
any fraction" once and return `remain_stationary`. That is a behaviour change
(a stuck unit would hold instead of eventually finding a relaxed 0.5x-radius
placement), so it needs the paired evaluator — but it should be cheap and it
removes a hang.

**Where the earlier work stands.** ~2x achieved against the ~20-50x this fixture
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

**TRIGGER FOUND AND FIXED (2026-08-09, second session).** The open question
above — why player 1's army hangs while player 2's exact 180° rotation
completes — is answered, and it was neither the AI's geometry nor the board.
Every step below is measured, not reasoned.

1. **The fixture deployed 19 of its 34 units OUT OF COHERENCY.**
   `make_2000pt_fixture.gd::_pack` packed the 77 MODELS individually, sorted
   by base size across the whole army, ignoring unit membership — so units'
   models interleaved. Warbikers Delta's six bikes spanned **36 inches**
   (m2 at x=191, m3 at x=1621); all 11 Gretchin Alpha models had no
   squadmate within 2". Both zones identically (the mirror was geometrically
   perfect — all 77 model pairs match under rotation to 0.01px).

2. **That is why Warbikers Delta could not move.** The AI's placement search
   (correctly) enforces the same coherency the engine validates at CONFIRM:
   each moved model must land within coherency range of an already-placed
   squadmate. A unit whose models start 5-15" apart, wedged between OTHER
   units' models at 0.07" gaps, has ZERO legal placements — it would have to
   contract 300-700px through a packed crowd inside one 12" move. The
   instrumented failure census (`RESOLVE_FAIL` log lines, added this session)
   names it: per failing model, all 392 candidates rejected —
   `rej={board:176 cap:111 collide:65 wall:7 terrain:6 overlap:4 coh:23}`,
   nearest obstacles `U_GRETCHIN_B/m11@72px, U_GRETCHIN_A/m9@101px` — models
   of OTHER units parked around the bike. The ~78-rung ladder then re-derives
   that impossibility for minutes inside ONE decision call (no frame yield,
   which is why neither the stall detector nor --bench-max-seconds fired).

3. **Why player 2's "exact mirror" completed anyway: the engine amputated its
   army first.** ISS-042 (11e 03.03) destroys the most-isolated models of any
   incoherent unit at every End of Turn — BOTH players' units. In the
   P2-only probe, the sweep at the end of player 1's (empty) turn removed
   **31 of player 2's 77 models** (10 of 11 Gretchin Alpha, 8 Gretchin Bravo,
   both Deffkopta squads pruned, three Stormboyz squads pruned) BEFORE player
   2 ever planned a move. Player 2 then played a smaller, legal army on a
   thinner board: its objective evaluations differed (friendly_oc 5 vs 9 at
   the mirrored home objective, VP estimates 2.5 vs 4.5), its plan differed
   (Wazdakka HOLDs; jump-pack Stormboyz get the 47" trek instead of the
   Warbikers), and every move succeeded. Player 1 never got that "help"
   because the sweep runs at End of Turn and player 1's first movement phase
   never ended. **Turn order converted a symmetric defect into the asymmetric
   outcome.** The asym_2000_postdeploy result ("same Orks finish in 266s")
   is the same artifact: there the Orks are player 2, so every asym game
   quietly played Custodes vs Orks-minus-~31-models. Its A/A baseline
   measured a fixture the rules had already amputated.

**The fix.** `_pack` now packs each UNIT as a contiguous near-square block
(largest unit first, same deterministic scan), and `_build` refuses to write
any fixture whose units fail the ENGINE's own
`AttackSequence.check_unit_coherency` — the exact predicate ISS-042 enforces.
`mirror_orks_2000_postdeploy` was rebuilt (sha256 76b7e123…): 0 incoherent
units, 0 ISS-042 removals in play, and the game now **leaves battle round 1**
— player 1's full turn, the thing that never finished before, completes in
~4 minutes and the game keeps going. The movement
ladder also gained `MOVE_LADDER_FAIL_BUDGET` (default 0 = off, same gating
convention as MOVE_RIGID_BLOCK_FIRST): when set, a unit that keeps failing
placement stops burning rungs after N failed attempts and holds instead —
the robustness fix for a unit genuinely boxed in mid-game. Turning it on
changes behaviour and needs the paired evaluator first.

**Still true, and still open:**

* `asym_2000_postdeploy` (and its A/A baseline, and the gate grid that uses
  it) were built by the scattered packer and measured with the amputation
  distortion. The fixture should be rebuilt with the fixed builder and its
  baseline re-established — NOT silently, since numbers derived from the old
  one are not comparable. Left to the owner to schedule.
* The per-model collision search is still expensive when a legal move is
  crowded (a failing model costs a 392-candidate search per rung). The
  rebuilt mirror completes but remains the slowest fixture. The search-design
  notes in the section above still apply.
* Found in passing, PRE-EXISTING (fires in the historical baseline runs too —
  both custodes seeds reproduce their margins exactly WITH it firing):
  `_assess_engage_on_all_fronts` (AIDecisionMaker.gd:18231) indexes the
  return of `_get_covered_quarters` as a Dictionary, but that function
  returns an Array — `SCRIPT ERROR: Invalid access to property or key 'true'
  on a base object of type 'Array'`, and the mission is then scored 0.0 and
  discarded as unachievable whenever this path runs. Fixing it changes which
  secondaries the AI keeps, so it needs the paired evaluator; not fixed here.
