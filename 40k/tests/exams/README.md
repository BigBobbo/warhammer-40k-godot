# Tactical exams — the cheap, sharp signal

A full benchmark game is a noisy, expensive way to ask a question. Per-seed
margin SD is 9-15 VP and a game costs 48 s (Custodes) to 487 s (Ork), so a
change worth +2 VP needs dozens of games before anyone can see it. Meanwhile
most regressions and most capability gains are visible **in seconds** in a
constructed position:

> does the AI walk onto the uncontested objective 4″ away, or wander off?
> does it finish the Knight on 5 wounds instead of spreading damage?
> does it screen the deep-strike zone?
> does it keep reserves under the cap against a fast army?

Chess engines call these test suites, and this project's own design brief asked
for exactly this cheap proxy. An exam is:

* a **fixture** (a committed save) plus an optional `setup` snippet that
  constructs the position,
* the **phase** to run and the **player** under test,
* a set of **machine-checkable assertions** over the resulting `GameState` or
  the AI's own decision records — never over pixels,
* a **`rationale`** citing the rule or the VP arithmetic that makes the
  expected play correct.

## Running them

```bash
bash 40k/tests/run_exams.sh                     # the whole suite
bash 40k/tests/run_exams.sh movement_take_free_objective
bash 40k/tests/run_exams.sh --aspirational      # the ones that fail BY DESIGN
```

Exit 0 iff every exam in the batch passed.

`run_exams.sh` runs `tools/ai_lab/check_exams.py` first — a ~1 s static
pre-flight that verifies each exam's fixture exists, every `U_*` id it names is
actually in that fixture, and a phase-1 exam is pointed at a fixture that starts
at deployment. Without it a bad unit id costs you a two-minute run per broken
exam before it surfaces as ERROR-with-no-verdict. Run it directly while
editing:

```bash
python3 tools/ai_lab/check_exams.py
```

## Three lists, on purpose

`exams/*.json` are **probes of real capability**: the current AI is expected to
pass them, and a failure is a regression. `exams/aspirational/*.json` are the
opposite — positions the AI is expected to get *wrong* today, written down as
the falsifiable target for a specific future task (each names its owner task).
Keeping them apart is what stops the suite from decaying into a wishlist that
is always red and therefore never read.

`exams/slow/*.json` is a third, smaller list: exams that are **correct and
would pass** but cost more wall clock than the whole gated suite is allowed.
They are excluded from `--suite` and run with `--slow` or by name. Parking one
is a debt, not a resolution — `exams/slow/README.md` records each one's
measured cost and the specific thing that would make it affordable again. The
pre-flight still checks them, because an exam nobody runs is exactly the one
whose unit ids rot unnoticed.

## The fixtures they run on (changed 2026-08-08)

The suite used to run entirely on `mirror_custodes_postdeploy` — 1335 points
of an army no player can pick. It now runs on the 2000-point fixtures built
from the shipped lists (`tools/ai_lab/README.md` has the table), which
changed three things worth knowing before you write an exam:

* **Unit ids moved.** Player 2's units are `U_..._P2`, not `MIR_U_...`, and
  the datasheets are whatever `custodes_lions` / `recon_stomps` actually
  field. There is no Caladius, Telemon or Witchseekers unit any more.
* **Pick the fixture for the behaviour, not for habit.** `sc02` screens on
  the Ork mirror because screening is only offered to units left *unassigned*
  after objective assignment, and 11 Custodes units across 5 objectives never
  leaves one spare — the branch is unreachable on that fixture by
  construction. 17 Ork units do leave cheap mobs surplus.
* **Do not teleport whole armies on the Ork fixture.** The old habit of
  parking every non-exam unit in a corner grid costs minutes there: 77 models
  including a 180 mm Stompa base do not fit a 40 px cell, and the mover
  retries placement 40 rings deep for each one. Move only the units the exam
  is actually about; the rest are already legally deployed. Ork exams get a
  larger timeout automatically (`EXAM_TIMEOUT_ORKS`, default 720 s).

`dp01_deployment_is_recorded` runs on `mirror_custodes_2000_predeploy`, which
starts at `Phase.DEPLOYMENT` with nothing on the table. It replaces the
aspirational `_a6_deployment_records` probe, whose note ("the two mirror
fixtures start post-deployment and can never exercise them") stopped being
true when that fixture landed.

## Writing one

The assertion scripts are GDScript bodies with `tree` bound (the SceneTree);
autoloads are reachable by name. Return a value and declare `equals`,
`expect_min` or `expect_max`. A compile error or a runtime error is a FAILED
exam, never a skipped one — an exam that cannot run has not passed.

Three rules learned the expensive way:

1. **Assert the decision, not the dice.** `unit U ends movement within control
   range of obj_center` is a decision. `unit U killed the Battlewagon` is a
   dice roll wearing a decision's clothes, and it will flake.
2. **No exam may reward degenerate play.** If an exam can be passed by an AI
   that does nothing else, it is measuring the wrong thing.
3. **Measure with the engine, against the fixture you actually load.** `mv01`
   and `mv03` hard-coded `obj_nml_1` at (400, 880) and a 3" centre-to-centre
   radius. The fixture was rebuilt on 2026-08-21 (38cbaa3) and mirrored on
   2026-10-25 (6f07340), which put `obj_nml_1` at (1500, 750) inside a ruin
   (in range once a base touches the area, 14.02), and both exams went on
   grading a squad 28" from the objective. Find objectives in
   `GameState.state.board.objectives`, measure with
   `MissionManager.model_in_objective_range` /
   `model_gap_to_objective_range_px`, and open with a **precondition**
   assertion that re-checks the position's premises on the engine (see `mv01`,
   `mv06`), so a fixture change fails the exam loudly instead of quietly
   testing something else.

## Determinism (EXAM-DET-1, 2026-11-07)

Same code + same fixture + same seed gives the same verdict and the same
decision records, on an idle box or a loaded one. Two things used to break
that, and both are fixed in the runner (`autoloads/AIBenchmarkRunner.gd`):

* **The graded moment.** The AI is never told an exam is over; it plays on
  into the next phase and the opponent's turn. The runner used to notice the
  phase change on a poll and grade 20 frames later, so a load-dependent amount
  of later play was graded too (`mv04` read 54, 59 or 94 on identical code).
  It now stops the AI synchronously inside `PhaseManager.phase_changed` (or at
  the action cap), and the result's `stopped` block says where. A wall-clock
  overrun grades nothing: it reports `TIMEOUT` and run_exams.sh lists the exam
  as ERROR, never as a PASS or FAIL.
* **The loaded board.** The fixture is copied into `user://saves/` from
  `tests/saves/` whenever the copy there is missing **or differs**; it used to
  be first-copy-wins (`cp -n`, the legacy save migration), so a user dir that
  outlived a fixture change kept the old board and the verdict depended on the
  machine's history. The result's `fixture.sha256` names the board graded.

Each run also writes `user://test_results/exams/<id>.trace.json` — the
decision batches, action log and final positions the verdict was computed
from — and puts `records_sha256` / `units_sha256` in the result, so checking
two runs for determinism is a string compare, and finding where they part is a
diff. `EXAM_KEEP_LOGS=1` keeps the per-exam godot logs as well.
