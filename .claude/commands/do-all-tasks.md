---
argument-hint: optional instructions
description: Process all tasks automatically
---

Process all tasks automatically.

Repeatedly work through incomplete tasks from the project task list.

If the user provided additional instructions, they will appear here:

<instructions>
$ARGUMENTS
</instructions>

If the user did not provide instructions, work through ALL incomplete tasks until NONE remain.

## Steps

1. Track attempt count and previously attempted tasks to prevent infinite loops
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
4. Repeat until no incomplete tasks remain or the user's instructions are met
5. When all tasks are completed, archive the task list:
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

- "Starting task: [task description]"
- "Task completed successfully: [task description]"
- "Task failed: [task description]"
- "Skipping blocked task: [task description]"
- "All tasks completed - task list archived to .llm/YYYY-MM-DD-todo.md" or "Stopping due to failures"

At the end, if `TESTS_NEEDED.md` has entries, remind the user:

- "Note: Some tasks wrote tests that could not be run in this environment. See `TESTS_NEEDED.md` for details on what to verify locally."
