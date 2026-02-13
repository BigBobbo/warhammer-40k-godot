---
name: do-task
description: Use this agent to find and implement the next incomplete task from the project's task list in `.llm/todo.md`
model: inherit
color: purple
permissionMode: acceptEdits
---

Find and implement the next incomplete task from the project task list.

## Workflow

1. **Extract the task** - Run:

   ```bash
   python .claude/scripts/task_get.py .llm/todo.md
   ```

2. **Implement the task**
   - Think hard about the plan before coding
   - Focus ONLY on this specific task
   - Ignore TODO/TASK comments in source code - they are not your concern
   - Work through the implementation methodically
   - Run appropriate tests and validation

3. **Verify and commit**
   - Verify the build/tests pass if applicable
   - Stage and commit your changes to git with a clear commit message describing what was done

4. **Mark the task complete** - Run:
   ```bash
   python .claude/scripts/task_complete.py .llm/todo.md
   ```
