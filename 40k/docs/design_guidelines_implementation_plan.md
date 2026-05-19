# Design Guidelines Implementation Playbook

How to execute the 45-task plan in `.llm/todo.md` over multiple sessions, with
parallelism, validation, and visual review.

## What you're working from

- **Design doc:** `40k/docs/design_guidelines_2d_topdown.md` — the *what* and *why*.
- **Task list:** `.llm/todo.md` — the *how* and *when*, split into 45 atomic tasks.
- **This doc:** the *workflow* for executing the list.

## Per-task lifecycle

Every task — no exceptions — passes through this loop:

1. **Pick a task** via the `do-one-task` skill (or manually open `.llm/todo.md` and
   choose). Confirm its `Depends:` list is satisfied (all upstream tasks closed).
2. **Confirm the `Lock:` tag is free** — no other in-flight session is editing the
   same files. If unsure, check `git log --oneline -5 origin/<branch>` for recent
   `[T##]` commits.
3. **Capture a "before" screenshot** — either reference an existing audit screenshot
   (`40k/test_results/audit_2026_05/screenshots/...` or `playthrough_*.png`) or run
   the scenario once on `HEAD` before changes.
4. **Make the code change** following the task body. One concern per task.
5. **Write the visual scenario** at `40k/tests/scenarios/visual/T##_<slug>.json`
   matching the schema in `40k/tests/scenarios/visual/_schema.md` (created in T02).
   Mandatory steps: an `T##_before` screenshot (if not pre-captured) and `T##_after`.
6. **Validate:**
   ```bash
   bash 40k/tests/run_scenarios.sh tests/scenarios/visual/T##_<slug>.json
   bash 40k/tests/run_scenarios.sh           # full regression
   ```
   Both must pass.
7. **Copy screenshot pair** to `40k/test_results/design_guidelines/T##/` (the harness
   from T02 does this automatically; if hand-running, copy manually).
8. **Commit:**
   ```
   [T##] <short task title>

   Implements <doc-section>. See 40k/docs/design_guidelines_2d_topdown.md.
   Before/after screenshots: 40k/test_results/design_guidelines/T##/

   Lock: <lock-tag>  [VISUAL-REVIEW]   # add [VISUAL-REVIEW] only for cosmetic-only
   ```
9. **Push:** `git push -u origin claude/research-strategy-game-design-bYYdT`.
10. **Mark the task `[x]`** in `.llm/todo.md` *only after* the visual review gate is
    cleared (see below). Until then leave `[ ]` even if commit landed.

## Validation tiers

Every task must clear **Tier A** before commit:
- New scenario passes.
- Full regression suite passes (no baseline degradation).
- No new compile warnings.

Cosmetic-only tasks additionally need **Tier B** before being marked `[x]`:
- A human flips through the `T##/before.png` vs `T##/after.png` pair and approves.
- This is *async* — commits can land flagged `[VISUAL-REVIEW]` and be reviewed in
  batches of 5–10.

Tasks that surface new player-facing affordances (drag-ruler, phase bar, threat
overlay, etc.) must also have their scenarios stay green in CI on subsequent runs —
they become part of the regression baseline.

## Parallelism (worktree-isolated streams)

For independent tasks (disjoint `Lock:` tags), spawn parallel agents in worktrees:

```
# In the main session, launch two streams in parallel:
Agent(description: "T07 cover icons",
      subagent_type: "do-task",
      isolation: "worktree",
      prompt: "Execute task T07 from .llm/todo.md following the playbook in
               40k/docs/design_guidelines_implementation_plan.md. Lock: BoardLayer.
               Push when done.")
Agent(description: "T08 two-ring token",
      subagent_type: "do-task",
      isolation: "worktree",
      prompt: "Execute task T08 from .llm/todo.md following the playbook in
               40k/docs/design_guidelines_implementation_plan.md. Lock: TokenLayer.
               Push when done.")
```

**Constraints on parallel runs:**
- Both worktrees must branch from the same commit (typically tip of
  `claude/research-strategy-game-design-bYYdT`).
- They must hold disjoint `Lock:` tags — check the table at the top of `.llm/todo.md`.
- When both complete, merge sequentially: the second push will likely need a rebase
  on the first. Resolve any conflicts in the *non-locked* areas (`.llm/todo.md`
  checkbox tick-offs, scenario screenshot file paths) — there should be no code
  conflicts because the locks were disjoint.
- Realistic safe parallelism: **3 streams**. Beyond that, scenario harness contention
  on shared fixtures becomes the bottleneck.

**When NOT to parallelize:**
- Foundation tasks (T01, T02) — sequential, must complete first.
- T12 (UIConstants migration) — holds every visual-script lock, so it serializes by
  definition. Park other visual-layer streams while T12 runs.
- T45 (final compliance audit) — purely sequential, runs after everything.

## Multi-session continuity

The branch `claude/research-strategy-game-design-bYYdT` is the running state. To
resume in a new session:

```bash
git fetch origin claude/research-strategy-game-design-bYYdT
git checkout claude/research-strategy-game-design-bYYdT
git pull
grep -c '^- \[x\]' .llm/todo.md     # progress count
grep '^- \[ \]' .llm/todo.md | head # next available tasks
```

Use the `do-one-task` skill to auto-pick the next ready task (it should walk the
list, skip tasks whose `Depends:` aren't satisfied, and avoid tasks whose `Lock:`
appears in any uncommitted local change).

## Failure modes & recovery

| Symptom | Likely cause | Recovery |
| --- | --- | --- |
| Scenario hangs >5min | Backgrounded Godot window on macOS | Foreground via `osascript -e 'tell application "Godot" to activate'`. Re-run. |
| Screenshot is byte-identical to previous frame | Same as above | Same. |
| `run_scenarios.sh` exit code 2 | Infra error (Godot crash, missing fixture) | Check `~/Library/Application Support/Godot/app_userdata/40k/logs/debug_*.log`. Don't mask with retries. |
| Regression suite has new failure not present on `main` | Real regression | Revert the task commit, narrow the change, re-attempt. Don't merge a task with regressions. |
| Two parallel worktrees both edited the same file | Lock tags weren't disjoint | First push wins. Second rebases, manually re-applies. Update the affected task's `Lock:` tag in `.llm/todo.md` to prevent recurrence. |
| Visual screenshot looks wrong but Tier A passed | Tier B caught it (good) | Open a follow-up task to refine the visual; don't tick the original until both gates pass. |

## Visual review batching

Every ~10 tasks, run a review session:

1. `git log --oneline --grep='\[VISUAL-REVIEW\]'` — list flagged commits.
2. For each, open `40k/test_results/design_guidelines/T##/before.png` and `after.png`
   side by side.
3. If approved: tick `- [x]` in `.llm/todo.md`, push the tick.
4. If rejected: open a follow-up task `T##b` with the specific refinement, leave
   original `- [ ]`, do not revert the commit (the code shape is fine, only the
   visual choice is being iterated).

## What NOT to do

- **Don't skip the windowed scenario.** Pin tests and headless-only validation are
  explicitly called out as insufficient in `CLAUDE.md`. Every task drives the real
  UI.
- **Don't batch multiple task changes into one commit.** One task = one commit. The
  visual review and revert paths depend on this.
- **Don't auto-tick `- [x]` on commit.** Only after Tier B visual review passes.
- **Don't push `--no-verify`.** Pre-commit hooks gate the regression suite for a
  reason.
- **Don't add features beyond the task body.** Drift between the doc and what
  shipped is exactly what produces design-guideline rot. If the task is wrong, open
  a follow-up rather than expanding scope mid-task.
- **Don't run the loop unattended.** `/loop /do-all-tasks` may sound appealing but
  each task commits irreversibly and pushes to a shared branch. Supervise.

## Where things live

```
.llm/todo.md                                     # task list (the queue)
40k/docs/design_guidelines_2d_topdown.md         # the design doc (the why)
40k/docs/design_guidelines_implementation_plan.md # this file (the how)
40k/tests/scenarios/visual/                      # new per-task scenarios
40k/tests/scenarios/visual/_schema.md            # written in T02
40k/tests/scenarios/visual/_template.json        # written in T02
40k/test_results/design_guidelines/T##/          # before/after screenshot pairs
40k/autoloads/UIConstants.gd                     # written in T01 — the color slot truth
```
