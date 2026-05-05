---
name: do-task
description: Use this agent to find and implement the next incomplete task from the project's task list in `.llm/todo.md`
model: inherit
color: purple
permissionMode: acceptEdits
---

Find and implement a task from the project task list.

## Workflow

### 1. Determine the task

Check if your launch prompt contains a `<task-override>` block. This is used when running in parallel mode.

- **If `<task-override>` is present:** Use the task description from that block. The task text (first line after the checkbox) will also be available in a `<task-key>` block — you'll need this for marking the task complete.
- **If no `<task-override>`:** Extract the next task from the file:
  ```bash
  python .claude/scripts/task_get.py .llm/todo.md
  ```

### 2. Implement the task

- Think hard about the plan before coding
- Focus ONLY on this specific task
- Ignore TODO/TASK comments in source code - they are not your concern
- Work through the implementation methodically
- Run appropriate tests and validation

### 3. Write tests that exercise the change

Headless GDScript regression tests **do** run in this environment via
`bash 40k/tests/run_pretrigger_tests.sh`. Pattern reference:
`40k/tests/TESTING_METHODOLOGY.md`.

For tasks that touch gameplay/rules logic:
- Add or extend a headless test under `40k/tests/test_<area>.gd` that fails
  before your change and passes after it
- Wire the new test into `40k/tests/run_pretrigger_tests.sh` so the
  validation gate (step 4) actually exercises it

For non-gameplay tasks (UI-only, content data, docs) where headless tests
are not feasible, append an entry to `TESTS_NEEDED.md` describing what to
verify manually. Use this **only** when headless coverage genuinely doesn't
fit — not as a way to skip validation. Format:

```markdown
## <Short description of what was implemented>

**Task:** <the original task description, condensed to one line>
**Files changed:** <list of files you created or modified>
**Tests to run:**
- <test file path and how to run it>
- <what each test verifies>

**What to look for:**
- <specific things the user should verify pass>
- <any edge cases or scenarios covered>
```

### 4. Validation gate (REQUIRED — do not skip)

Run the project's regression suite from the repo root:

```bash
bash .claude/scripts/run_validation.sh
```

Interpret the result:

- **Exit 0 (all tests pass):** proceed to step 5.
- **Exit non-zero:** treat the task as **failed**. Do NOT commit. Do NOT
  push. Skip to step 7 and mark the task blocked. Capture the relevant
  failure output in your final report so the user can see why.

Per project policy (`CLAUDE.md`): never claim a feature works without a
successful test result. `implemented: true` flags and code-grep are not
validation — only a green run of the suite is.

### 5. Mark the task in `.llm/todo.md`

This step happens **before** the commit so the task-list state ships in the
same commit as the code change. That keeps remote/local task state in sync
and prevents a second agent from re-picking a task whose code was already
pushed.

**On validation pass:**

- Parallel mode: `python .claude/scripts/task_complete_specific.py .llm/todo.md --task "<task-key text>"`
- Sequential mode: `python .claude/scripts/task_complete.py .llm/todo.md`

**On validation fail (or any earlier failure):**

- Parallel mode: `python .claude/scripts/task_complete_specific.py .llm/todo.md --task "<task-key text>" --blocked`
- Sequential mode: `python .claude/scripts/task_complete.py .llm/todo.md --blocked`

> **CRITICAL — read carefully.** The `task_complete*.py` script edits
> `.llm/todo.md` in place, leaving it dirty in your working tree. The
> orchestrator does **not** clean this up for you. **You** must stage
> `.llm/todo.md` in step 6's commit alongside your code. If your commit
> ships without `.llm/todo.md`, local and remote task-list state diverge
> — a second agent can re-pick a task whose code was already pushed.
> This has happened before; do not let it happen again. After running
> the script, run `git status .llm/todo.md` and confirm you see ` M`
> before proceeding.

### 6. Commit (allow-listed paths only)

The repo's working tree is routinely dirty with files unrelated to your
task — saved games, screenshots, `.uid` files, `project.godot`,
in-progress edits to other scripts. These must NEVER end up in your commit.

**Forbidden:** `git add -A`, `git add .`, `git add -u`, or any pattern that
sweeps in files you didn't intentionally edit. Reviewers cannot un-mix a
contaminated commit.

**Required:** stage files by explicit path. The complete allowed set is:

1. **`.llm/todo.md` — ALWAYS, NO EXCEPTIONS.** It carries the `[x]`/`[!]`
   mark that step 5 wrote. The orchestrator does NOT stage this for you.
   If you skip it, the local/remote task-list state diverges and your
   commit ships in an invalid half-state. Run `git status .llm/todo.md`
   first; it must show ` M` before you stage it. The `git add` line
   for this step MUST literally include `.llm/todo.md` as a path —
   audit your own bash command before pressing enter.
2. The source files you intentionally edited to implement the task
3. Any new or extended test files (typically under `40k/tests/`)
4. The `40k/tests/run_pretrigger_tests.sh` runner if you added a new test
   that needs to be wired in

If the validation gate failed and you have no implementation worth keeping,
stage **only** `.llm/todo.md` so the `[!]` mark propagates as a "BLOCKED"
record. Leave any partial implementation in the working tree for the human
to inspect — do not commit broken code.

Before staging, double-check with `git status` that you understand which
files are *yours* vs which were already dirty. If unsure, list them in your
final report and proceed conservatively.

Commit with a HEREDOC message ending in the `Co-Authored-By: Claude`
trailer per repo convention. Subject line should describe the change in
imperative mood; on a blocked outcome, prefix with `BLOCKED:`.

### 7. Push to remote (auto-deploy)

This skill is wired to auto-publish each task — both successful commits
and `BLOCKED:` commits — so remote task-list state stays current.

```bash
git push origin HEAD
```

Push runs **unless** `PUSH_DISABLED` is set in the environment (escape
hatch from the orchestrator's `nopush` flag). If `PUSH_DISABLED=1`, skip
the push entirely and note "push skipped — nopush mode" in your report.

If the push fails (e.g., remote rejected, non-fast-forward), do NOT force.
Report the failure verbatim. Do not attempt to resolve a non-fast-forward
by rebasing or resetting — surface it to the orchestrator and stop.

### 8. Final report

Your final returned message must state:

- Validation result (exit code + which tests passed/failed)
- Files staged in the commit (list every path explicitly)
- Commit SHA + subject line
- Push status (succeeded / skipped / failed-with-reason)
- Final task status in `.llm/todo.md` (`[x]` or `[!]`)
- Anything in the working tree that's still dirty and why

The orchestrator uses this report to decide whether to continue the loop
or abort.
