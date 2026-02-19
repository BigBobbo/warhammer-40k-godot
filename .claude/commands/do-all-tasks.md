---
argument-hint: [count] [parallel N] [optional instructions]
description: Process all tasks automatically
---

Process all tasks automatically.

Repeatedly work through incomplete tasks from the project task list.

If the user provided arguments, they will appear here:

<arguments>
$ARGUMENTS
</arguments>

## Parsing arguments

The arguments may contain any combination of:

1. **A task count** — a leading positive integer sets the max number of tasks to process
2. **`parallel N`** — enables parallel mode, launching N agents simultaneously per batch (default: sequential, one at a time)
3. **Everything else** — treated as additional instructions

Examples:
- `/do-all-tasks` — process ALL tasks sequentially
- `/do-all-tasks 3` — process up to 3 tasks sequentially
- `/do-all-tasks parallel 3` — process ALL tasks, 3 at a time in parallel
- `/do-all-tasks 6 parallel 3` — process up to 6 tasks, 3 at a time in parallel
- `/do-all-tasks 5 focus on UI tasks` — process up to 5 tasks sequentially, with instructions
- `/do-all-tasks parallel 2 fix only the battle logic` — process ALL tasks 2 at a time, with instructions

Parse the arguments as follows:
1. If the first word is a positive integer, use it as the **task limit** and consume it
2. Scan remaining words for `parallel N` (where N is a positive integer). If found, set **parallel count** to N and consume both words
3. Any remaining text becomes the **instructions**
4. If no task limit is given, process ALL tasks
5. If no parallel count is given, default to sequential mode (parallel count = 1)

---

## Sequential mode (parallel count = 1)

This is the original behavior.

1. Track attempt count, completed count, and previously attempted tasks to prevent infinite loops
2. Extract the first incomplete task from `.llm/todo.md`:
   ```bash
   python .claude/scripts/task_get.py .llm/todo.md
   ```
3. If a task is found:
   - Check if we have already attempted this task 1 time
   - If yes, mark it as blocked (with `- [!]`) by running `python .claude/scripts/task_complete.py --blocked .llm/todo.md` and continue to next task
   - If no, launch the `do-task` agent to implement it
   - **Do NOT add instructions to the agent prompt** - the agent is self-contained and follows its own workflow (including commit)
   - Do NOT mark the task as complete yourself - the `do-task` agent does this
   - After each task completes, increment the completed count
4. **Stop** when ANY of these conditions are met:
   - No incomplete tasks remain
   - The completed count has reached the task limit (if one was specified)
   - The user's instructions are met
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

5. **Collect results** — after all agents in the batch return, check which succeeded and which failed. Each agent marks its own task as `[x]` (done) or `[!]` (blocked). Count the successes.

6. **Check stopping conditions**:
   - If completed count has reached the task limit, stop
   - If no more incomplete tasks remain, stop
   - Otherwise, continue to the next batch

### After all batches

Archive the task list:
```bash
python .claude/scripts/task_archive.py .llm/todo.md
```

---

## Notes

- Each task is handled completely by a `do-task` agent (whether sequential or parallel)
- The `do-task` agent marks tasks as complete - do NOT call `task_complete.py` yourself
- Each task gets its own commit for clear history
- Godot tests cannot be executed in this environment. The `do-task` agent will write test code but log tests that need local execution to `TESTS_NEEDED.md` in the project root. Tasks should NOT be blocked just because Godot tests could not be run.
- In parallel mode, agents may commit to git simultaneously. This works fine for local commits as long as they touch different files. If git conflicts occur, the agent will handle them.

## User feedback

Throughout the process, provide clear status updates:

- "Starting task [N/limit]: [task description]" (include the count and limit if one was specified)
- "Starting batch [B] with [N] parallel tasks: [task summaries]" (parallel mode)
- "Task completed successfully: [task description]"
- "Task failed: [task description]"
- "Skipping blocked task: [task description]"
- "Batch [B] complete: [succeeded]/[total] tasks succeeded"
- "Completed [N] tasks — task limit reached" (when stopped due to task limit)
- "All tasks completed - task list archived to .llm/YYYY-MM-DD-todo.md" or "Stopping due to failures"

At the end, if `TESTS_NEEDED.md` has entries, remind the user:

- "Note: Some tasks wrote tests that could not be run in this environment. See `TESTS_NEEDED.md` for details on what to verify locally."
