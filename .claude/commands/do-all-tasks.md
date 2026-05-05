---
argument-hint: [count] [parallel N] [nopush] [optional instructions]
description: Process all tasks automatically (validates + auto-pushes each task)
---

Process all tasks automatically.

Repeatedly work through incomplete tasks from the project task list. Each
task is validated by the headless regression suite and, if green, auto-pushed
to `origin` by the `do-task` agent before the next task starts. No user
input is required during the loop.

If the user provided arguments, they will appear here:

<arguments>
$ARGUMENTS
</arguments>

## Parsing arguments

The arguments may contain any combination of:

1. **A task count** — a leading positive integer sets the max number of tasks to process
2. **`parallel N`** — enables parallel mode, launching N agents simultaneously per batch (default: sequential, one at a time)
3. **`nopush`** — disables auto-push for this run (validation still runs; commits stay local). Pass via env: export `PUSH_DISABLED=1` before launching subagents.
4. **Everything else** — treated as additional instructions

Examples:
- `/do-all-tasks` — process ALL tasks sequentially, validate + push each
- `/do-all-tasks 3` — process up to 3 tasks sequentially
- `/do-all-tasks parallel 3` — process ALL tasks, 3 at a time in parallel
- `/do-all-tasks 6 parallel 3` — process up to 6 tasks, 3 at a time in parallel
- `/do-all-tasks 5 nopush` — process up to 5 tasks; commit locally only
- `/do-all-tasks 5 focus on UI tasks` — process up to 5 tasks sequentially, with instructions
- `/do-all-tasks parallel 2 fix only the battle logic` — process ALL tasks 2 at a time, with instructions

Parse the arguments as follows:
1. If the first word is a positive integer, use it as the **task limit** and consume it
2. Scan remaining words for `parallel N` (where N is a positive integer). If found, set **parallel count** to N and consume both words
3. Scan remaining words for the literal token `nopush`. If found, set **push enabled** to false and consume the word.
4. Any remaining text becomes the **instructions**
5. If no task limit is given, process ALL tasks
6. If no parallel count is given, default to sequential mode (parallel count = 1)
7. If `nopush` was found, run `export PUSH_DISABLED=1` before launching the first subagent so the `do-task` agent skips its push step.

---

## Sequential mode (parallel count = 1)

This is the original behavior.

1. Track attempt count, completed count, **consecutive failure count**, and previously attempted tasks to prevent infinite loops
2. Extract the first incomplete task from `.llm/todo.md`:
   ```bash
   python .claude/scripts/task_get.py .llm/todo.md
   ```
3. If a task is found:
   - Check if we have already attempted this task 1 time
   - If yes, mark it as blocked (with `- [!]`) by running `python .claude/scripts/task_complete.py --blocked .llm/todo.md` and continue to next task
   - If no, launch the `do-task` agent to implement it
   - **Do NOT add instructions to the agent prompt** - the agent is self-contained and follows its own workflow (validate + commit + push)
   - Do NOT mark the task as complete yourself - the `do-task` agent does this
   - After the agent returns, inspect its final report:
     - If it says validation failed, push was rejected, or task was marked blocked → increment the **consecutive failure count**
     - Otherwise → reset the consecutive failure count to 0 and increment the **completed count**
4. **Stop** when ANY of these conditions are met:
   - No incomplete tasks remain
   - The completed count has reached the task limit (if one was specified)
   - The user's instructions are met
   - **Consecutive failure count reaches 3** — a sustained failure streak signals the validation gate is rejecting work and we should not keep churning. Surface a clear summary to the user before exiting.
5. When stopping, archive the task list:
   ```bash
   python .claude/scripts/task_archive.py .llm/todo.md
   ```

---

## Parallel mode (parallel count > 1)

In parallel mode, tasks are processed in **batches**. Each batch launches multiple `do-task` agents simultaneously.

### Batch loop

Repeat until done:

1. **Calculate batch size**: `min(parallel_count, remaining_task_limit)` — don't exceed the task limit
2. **Extract a batch** of tasks:
   ```bash
   python .claude/scripts/task_get_batch.py .llm/todo.md <batch_size>
   ```
   This atomically marks the extracted tasks as in-progress `[>]` and returns them in a numbered format.

3. **Parse the batch output** — each task is delimited by `=== TASK N ===` headers. For each task, extract:
   - The full task text (everything between headers)
   - The **task key** — the text on the first line after the checkbox marker (e.g., for `- [>] Fix melee logic`, the key is `Fix melee logic`)

4. **Launch all agents in parallel** — use the Task tool to launch one `do-task` agent per task **in a single message** (this is critical for parallelism). Each agent's prompt should include:

   ```
   <task-override>
   [full task text here]
   </task-override>

   <task-key>
   [task key text here]
   </task-key>
   ```

   **IMPORTANT**: You MUST launch all agents in a single message with multiple Task tool calls. This is what makes them run in parallel. Do NOT launch them one at a time.

5. **Collect results** — after all agents in the batch return, check which succeeded and which failed. Each agent marks its own task as `[x]` (done) or `[!]` (blocked). Count the successes. Track consecutive batch failure: if **every** task in a batch was blocked, increment a batch-failure counter; otherwise reset it to 0.

6. **Check stopping conditions**:
   - If completed count has reached the task limit, stop
   - If no more incomplete tasks remain, stop
   - **If the batch-failure counter reaches 2** (two consecutive all-blocked batches), stop and surface the failure summary — the validation gate is rejecting everything and human attention is needed
   - Otherwise, continue to the next batch

### After all batches

Archive the task list:
```bash
python .claude/scripts/task_archive.py .llm/todo.md
```

---

## Notes

- Each task is handled completely by a `do-task` agent (whether sequential or parallel)
- The `do-task` agent runs the validation gate (`bash .claude/scripts/run_validation.sh`), commits, and pushes — do NOT call any of those yourself
- The `do-task` agent marks tasks as complete - do NOT call `task_complete.py` yourself
- Each task gets its own commit + push for a clean per-task deploy history
- Headless GDScript regression tests **do** run in this environment via `40k/tests/run_pretrigger_tests.sh`. Tasks that touch gameplay logic should add or extend a headless test wired into that runner so the validation gate exercises them. Use `TESTS_NEEDED.md` only for genuinely UI/manual-only verification.
- **Auto-push policy:** push goes to `origin <current-branch>`. If the current branch is `main`, every successful task lands directly on `main`. To pause pushes for a run, pass `nopush` (the orchestrator sets `PUSH_DISABLED=1` for subagents).
- **Failure-streak abort:** sequential mode aborts after 3 consecutive blocked tasks; parallel mode aborts after 2 consecutive all-blocked batches. This prevents an indefinite churn when the validation gate is rejecting everything.
- Pushes never use `--force` and are not retried after non-fast-forward rejections — those are surfaced and the task is marked blocked.
- In parallel mode, agents may commit and push simultaneously. Local commits work fine if they touch different files; pushes to the same branch are serialized by git but the loser of a race will see a non-fast-forward and block — the orchestrator records that and continues.

## User feedback

Throughout the process, provide clear status updates:

- "Starting task [N/limit]: [task description]" (include the count and limit if one was specified)
- "Starting batch [B] with [N] parallel tasks: [task summaries]" (parallel mode)
- "Task completed and pushed: [task description]" (validation green + push succeeded)
- "Task failed validation: [task description] — marked blocked, NOT pushed" (validation red)
- "Task push rejected: [task description] — marked blocked" (non-fast-forward or remote rejection)
- "Skipping blocked task: [task description]"
- "Batch [B] complete: [succeeded]/[total] tasks succeeded"
- "Completed [N] tasks — task limit reached" (when stopped due to task limit)
- "Aborting: 3 consecutive task failures — validation gate is rejecting work, human needed" (failure-streak abort)
- "All tasks completed - task list archived to .llm/YYYY-MM-DD-todo.md"

At the end, if `TESTS_NEEDED.md` has entries, remind the user:

- "Note: Some tasks wrote tests that could not be run in this environment. See `TESTS_NEEDED.md` for details on what to verify locally."
