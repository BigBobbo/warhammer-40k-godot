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

## Two lists, on purpose

`exams/*.json` are **probes of real capability**: the current AI is expected to
pass them, and a failure is a regression. `exams/aspirational/*.json` are the
opposite — positions the AI is expected to get *wrong* today, written down as
the falsifiable target for a specific future task (each names its owner task).
Keeping them apart is what stops the suite from decaying into a wishlist that
is always red and therefore never read.

## Writing one

The assertion scripts are GDScript bodies with `tree` bound (the SceneTree);
autoloads are reachable by name. Return a value and declare `equals`,
`expect_min` or `expect_max`. A compile error or a runtime error is a FAILED
exam, never a skipped one — an exam that cannot run has not passed.

Two rules learned the expensive way:

1. **Assert the decision, not the dice.** `unit U ends movement within control
   range of obj_center` is a decision. `unit U killed the Battlewagon` is a
   dice roll wearing a decision's clothes, and it will flake.
2. **No exam may reward degenerate play.** If an exam can be passed by an AI
   that does nothing else, it is measuring the wrong thing.
