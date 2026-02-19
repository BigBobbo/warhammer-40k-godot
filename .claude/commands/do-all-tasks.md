---
argument-hint: [count] [optional instructions]
description: Process all tasks automatically
---

Process all tasks automatically.

Repeatedly work through incomplete tasks from the project task list.

If the user provided arguments, they will appear here:

<arguments>
$ARGUMENTS
</arguments>

## Parsing arguments

The first argument may be a **number** indicating how many tasks to process. Everything else is treated as instructions.

Examples:
- `/do-all-tasks` — process ALL tasks
- `/do-all-tasks 3` — process up to 3 tasks
- `/do-all-tasks 5 focus on UI tasks` — process up to 5 tasks, with additional instructions
- `/do-all-tasks fix only the battle logic` — process ALL tasks, with additional instructions

Parse the arguments as follows:
1. If the first word of `$ARGUMENTS` is a positive integer, use it as the **task limit** and treat the rest as instructions
2. Otherwise, there is no task limit (process ALL tasks) and the entire argument string is treated as instructions
3. If no arguments are provided, process ALL tasks with no additional instructions

## Steps

1. Parse arguments to determine the task limit (if any) and instructions (if any)
2. Track attempt count, completed count, and previously attempted tasks to prevent infinite loops
3. Extract the first incomplete task from `.llm/todo.md`:
   ```bash
   python .claude/scripts/task_get.py .llm/todo.md
   ```
4. If a task is found:
   - Check if we have already attempted this task 1 time
   - If yes, mark it as blocked (with `- [!]`) by running `python .claude/scripts/task_complete.py --blocked .llm/todo.md` and continue to next task
   - If no, launch the `do-task` agent to implement it
   - **Do NOT add instructions to the agent prompt** - the agent is self-contained and follows its own workflow (including commit)
   - Do NOT mark the task as complete yourself - the `do-task` agent does this
   - After each task completes, increment the completed count
5. **Stop** when ANY of these conditions are met:
   - No incomplete tasks remain
   - The completed count has reached the task limit (if one was specified)
   - The user's instructions are met
6. When stopping, archive the task list:
   ```bash
   python .claude/scripts/task_archive.py .llm/todo.md
   ```

## Notes

- Each task is handled completely by the `do-task` agent before moving to the next
- The `do-task` agent marks tasks as complete - do NOT call `task_complete.py` yourself
- Each task gets its own commit for clear history
- After each agent returns, check the task list again to see if more tasks remain
- Godot tests cannot be executed in this environment. The `do-task` agent will write test code but log tests that need local execution to `TESTS_NEEDED.md` in the project root. Tasks should NOT be blocked just because Godot tests could not be run.

## User feedback

Throughout the process, provide clear status updates:

- "Starting task [N/limit]: [task description]" (include the count and limit if one was specified)
- "Task completed successfully: [task description]"
- "Task failed: [task description]"
- "Skipping blocked task: [task description]"
- "Completed [N] tasks — task limit reached" (when stopped due to task limit)
- "All tasks completed - task list archived to .llm/YYYY-MM-DD-todo.md" or "Stopping due to failures"

At the end, if `TESTS_NEEDED.md` has entries, remind the user:

- "Note: Some tasks wrote tests that could not be run in this environment. See `TESTS_NEEDED.md` for details on what to verify locally."
