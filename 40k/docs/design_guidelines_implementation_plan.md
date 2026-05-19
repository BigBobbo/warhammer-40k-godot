# Design Guidelines Implementation Playbook

How to execute the 45-task plan in `.llm/todo.md` over multiple sessions, with
parallelism, validation, and visual review.

## What you're working from

- **Design doc:** `40k/docs/design_guidelines_2d_topdown.md` — the *what* and *why*.
- **Task list:** `.llm/todo.md` — the *how* and *when*, split into 45 atomic tasks.
- **This doc:** the *workflow* for executing the list.

## Validation philosophy: no false positives

Every task carries two acceptance blocks:

- **Tier A — machine-checkable.** Gates `git commit`. Specific
  `expect_state` / `expect_action_result` / `execute_script` / pixel-diff
  assertions inside the visual scenario. If a Tier A bullet cannot be expressed
  in the scenario JSON, redesign the change so the relevant state IS observable
  — never weaken the assertion.
- **Tier B — human visual checklist.** 3–5 specific yes/no items per task.
  Gates the `- [x]` mark in `.llm/todo.md`, not the commit. Reviewers tick
  items, not "looks good".

**The four patterns that produce false positives, all banned:**

1. **Screenshot-only acceptance.** A `screenshot` step proves the harness ran,
   not that the feature rendered. Every visual claim in Tier A must pair the
   screenshot with a `pixel_diff` bound *or* a property-level read.
2. **Pin tests masquerading as validation.** "Node exists" and "child count
   matches" prove the code shape, not the rendered frame. CLAUDE.md explicitly
   warns about this — Tier A must read the property that controls the pixel
   (`modulate.a`, `color`, `visible`, `position`, `texture != null`).
3. **Subjective adjectives in Tier A.** "Visible", "readable", "smooth",
   "performant", "feels right" are Tier B language only. Tier A is numeric
   bounds and exact equality only.
4. **"Regression suite passes" with no baseline.** "Exit 0" is meaningless if
   the suite size shrinks. Every task's Tier A includes
   `passing_scenarios_count >= _baseline.json.count` (the baseline is
   snapshotted in T02).

## Per-task lifecycle

Every task — no exceptions — passes through this loop:

1. **Pick a task** via the `do-one-task` skill (or open `.llm/todo.md` and
   choose). Confirm its `Depends:` list is satisfied (all upstream tasks closed,
   i.e. `- [x]` ticked).
2. **Confirm the `Lock:` tag is free** — no in-flight session is editing the
   same files. Check `git log --oneline -5 origin/<branch>` for recent `[T##]`
   commits on overlapping locks.
3. **Capture a "before" baseline** — either reference an existing audit
   screenshot or run the scenario once on `HEAD` before changes and save the
   resulting `before.png` + `diff_report.json`.
4. **Make the code change** following the task body. One concern per task.
5. **Write the visual scenario** at `40k/tests/scenarios/visual/T##_<slug>.json`
   matching the schema in `40k/tests/scenarios/visual/_schema.md` (created in T02).
   It MUST contain at least one `expect_state` or `expect_action_result` step;
   screenshot-only scenarios are rejected.
6. **Validate Tier A:**
   ```bash
   bash 40k/tests/run_scenarios.sh tests/scenarios/visual/T##_<slug>.json
   #   exit 0 = scenario passed including all expect_* bullets
   #   exit 1 = an assertion failed -> fix the code
   #   exit 2 = infra error (Godot crash, missing fixture) -> investigate
   #   exit 3 = regression detected (passing count < baseline) -> fix the cause

   bash 40k/tests/run_scenarios.sh           # full sp regression
   #   must also exit 0; passing count must be >= baseline
   ```
   Both invocations must exit 0. If exit 3 appears, the task introduced a
   regression somewhere in the suite — investigate, don't mask.
7. **Verify pixel-diff bounds.** Open `40k/test_results/design_guidelines/T##/
   diff_report.json`. Each `regions[<name>].diff_pct` mentioned in the task's
   Tier A must satisfy its documented bound (`> N` or `< N`).
8. **Commit:**
   ```
   [T##] <short task title>

   Implements <doc-section>. See 40k/docs/design_guidelines_2d_topdown.md.
   Tier A: <one-line summary of which assertions hold>
   Before/after: 40k/test_results/design_guidelines/T##/
   Pixel diff: <copy the key region diff numbers from diff_report.json>

   Lock: <lock-tag>  [VISUAL-REVIEW]   # [VISUAL-REVIEW] flag if cosmetic-only
   ```
9. **Push:** `git push -u origin claude/research-strategy-game-design-bYYdT`.
10. **Visual review (later).** Do NOT tick `- [x]` in `.llm/todo.md` on commit.
    The `[ ]` stays until a human walks the Tier B checklist and ticks each
    bullet on the task. Push a separate commit `tick T##` when all Tier B
    items pass.

## What Tier A looks like in a scenario

The schema enforces structure but the *bounds* are per-task. Example for T03
(drag-ruler) showing every category:

```json
{
  "id": "T03_drag_ruler",
  "covers": ["movement.drag_ruler", "design_guidelines.T03"],
  "fixture": "movement_phase_basic",
  "transition_to_phase": 2,
  "steps": [
    { "act": "screenshot", "label": "T03_before" },

    { "act": "dispatch_action", "action": {
      "type": "BEGIN_MODEL_DRAG",
      "actor_unit_id": "U_INTERCESSORS_A",
      "payload": { "model_id": "m1" }
    }},
    { "act": "expect_action_result", "path": "success", "equals": true },

    { "act": "execute_script", "script":
      "return MovementController.current_drag_segments.size()",
      "expect_min": 0 },

    { "act": "execute_script", "script":
      "return MovementController.set_drag_cursor(Vector2(<within_M>))",
      "expect_action_result": "success" },
    { "act": "execute_script", "script":
      "return MovementController.current_drag_segments[-1].color_slot",
      "equals": "CONFIRMED_GREEN" },
    { "act": "screenshot", "label": "T03_at_M" },

    { "act": "execute_script", "script":
      "return MovementController.set_drag_cursor(Vector2(<within_advance>))",
      "expect_action_result": "success" },
    { "act": "execute_script", "script":
      "return MovementController.current_drag_segments[-1].color_slot",
      "equals": "MARGINAL_YELLOW" },
    { "act": "screenshot", "label": "T03_at_advance" },

    { "act": "execute_script", "script":
      "return MovementController.set_drag_cursor(Vector2(<beyond>))",
      "expect_action_result": "success" },
    { "act": "execute_script", "script":
      "return MovementController.current_drag_segments[-1].color_slot",
      "equals": "INVALID_RED" },
    { "act": "screenshot", "label": "T03_after" },

    { "act": "pixel_diff",
      "before": "T03_before", "after": "T03_after",
      "region": "drag_path", "expect_min_pct": 5.0 },
    { "act": "pixel_diff",
      "before": "T03_at_M", "after": "T03_at_advance",
      "region": "drag_path", "expect_min_pct": 3.0 },

    { "act": "expect_baseline_unchanged" }
  ]
}
```

Three new step types are introduced in T02:
- `execute_script` with `equals` / `expect_min` / `expect_max` bounds.
- `pixel_diff` with `before` / `after` labels, optional `region` name, and an
  `expect_min_pct` or `expect_max_pct` bound.
- `expect_baseline_unchanged` — asserts the current passing-scenario count
  >= `_baseline.json.count`.

Every task's Tier A bullets in `.llm/todo.md` map 1:1 to these step types.

## Tier A failure modes (do NOT mask)

| Symptom | Likely cause | Required response |
| --- | --- | --- |
| `execute_script` returns null | Property not exposed yet | Add the property to the controller; this is intentional — task design requires testable state |
| `pixel_diff` returns 0% when bound was `> N` | Feature didn't render | Real bug. Don't lower the bound; fix the rendering. |
| `expect_baseline_unchanged` fails | A previously-passing scenario now fails | Real regression. Don't update the baseline. Investigate the breaking change. |
| `expect_state` path returns unexpected value | Logic doesn't match design | Real bug. |
| Scenario passes but `diff_report.json` shows `region.diff_pct == 0.0` on a region you expected to change | Region coordinates are wrong OR feature didn't render | Inspect screenshots manually; fix region coordinates in the scenario OR fix the rendering. |

**Never:**
- Update `_baseline.json` to lower the floor mid-task.
- Loosen `expect_min_pct` / `expect_max_pct` bounds to make a failing test pass.
- Remove a Tier A bullet because it's "redundant".
- Mark a task `[x]` with `[VISUAL-REVIEW]` still unresolved.

## Parallelism (worktree-isolated streams)

For independent tasks (disjoint `Lock:` tags), spawn parallel agents in worktrees:

```
Agent(description: "T07 cover icons",
      subagent_type: "do-task",
      isolation: "worktree",
      prompt: "Execute task T07 from .llm/todo.md following the playbook in
               40k/docs/design_guidelines_implementation_plan.md. Lock: BoardLayer.
               Honor both Tier A and Tier B. Push when Tier A passes; leave Tier B
               for the next review batch.")
Agent(description: "T08 two-ring token",
      subagent_type: "do-task",
      isolation: "worktree",
      prompt: "Execute task T08 from .llm/todo.md. Lock: TokenLayer. Same playbook
               rules.")
```

**Constraints:**
- Branch from the same commit (typically tip of
  `claude/research-strategy-game-design-bYYdT`).
- Tasks must hold **disjoint `Lock:` tags**.
- On merge: each push refreshes `_baseline.json` — the second worktree must
  `git pull --rebase` before pushing so its Tier A regression check uses the
  freshest baseline. If `_baseline.json` was modified by the first push, the
  second task's commit message should note the rebase.
- Safe parallelism: **3 streams**. Beyond that, scenario harness contention on
  shared fixtures becomes a bottleneck.

**When NOT to parallelize:**
- T01, T02 (foundation, sequential).
- T12 (holds every visual-script lock; serializes by definition).
- T41, T44 (broad codebase touches).
- T45 (final audit).

## Multi-session continuity

```bash
git fetch origin claude/research-strategy-game-design-bYYdT
git checkout claude/research-strategy-game-design-bYYdT
git pull
grep -c '^- \[x\]' .llm/todo.md     # progress count
grep '^- \[ \]' .llm/todo.md | head # next available tasks
cat 40k/tests/scenarios/visual/_baseline.json | head -3   # current floor
```

`do-one-task` walks the list, skips tasks whose `Depends:` aren't satisfied,
and avoids tasks whose `Lock:` appears in any uncommitted local change.

## Visual review batching

Every ~10 closed-with-`[VISUAL-REVIEW]` commits, run a review session:

1. `git log --oneline --grep='\[VISUAL-REVIEW\]'` — list flagged commits.
2. For each `T##`:
   a. Open `40k/test_results/design_guidelines/T##/before.png` and `after.png`
      side-by-side.
   b. Open `diff_report.json`.
   c. Walk the **Tier B checklist** in `.llm/todo.md` for that task. Tick each
      box `[x]` only if the observable is actually visible.
3. If every Tier B box ticks → mark task line `- [x]` and commit
   `tick T##` (or batch multiple ticks in one commit).
4. If a Tier B box fails → open a follow-up task `T##b` with the specific
   refinement; do NOT revert the original commit (the code shape and Tier A are
   fine; only the visual choice needs iteration).

## What NOT to do

- **Don't skip the visual scenario.** Per CLAUDE.md, player-facing changes need
  windowed-scenario proof. Headless tests are necessary but never sufficient.
- **Don't combine multiple tasks per commit.** One T## = one commit.
- **Don't auto-tick `[x]` on commit.** Tier B review is asynchronous and human.
- **Don't push `--no-verify`.** Pre-commit hooks gate the regression suite.
- **Don't lower `expect_min_pct` to make a test pass.** Either the feature
  renders or the bound is wrong because the region is wrong — fix the cause.
- **Don't update `_baseline.json` mid-task.** Only T02 establishes it and T45
  refreshes it as part of the final audit.
- **Don't add features beyond the task body.** Drift between doc and ship is
  exactly what produces design-guideline rot.
- **Don't run `/loop /do-all-tasks` unattended.** Each task is a commit on a
  shared branch.

## Where things live

```
.llm/todo.md                                      # task queue
40k/docs/design_guidelines_2d_topdown.md          # the why
40k/docs/design_guidelines_implementation_plan.md # this file (the how)
40k/tests/scenarios/visual/                       # per-task scenarios
40k/tests/scenarios/visual/_schema.md             # written in T02
40k/tests/scenarios/visual/_template.json         # written in T02
40k/tests/scenarios/visual/_baseline.json         # passing-scenario floor
40k/tests/tools/pixel_diff.gd                     # written in T02
40k/test_results/design_guidelines/T##/           # before/after + diff_report
40k/autoloads/UIConstants.gd                      # color slot truth (T01)
```
