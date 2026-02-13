---
description: Find and implement the next incomplete task from the project task list
---

Find and implement the next incomplete task from the project task list.

## Task Implementation Workflow

### Steps

1. **Extract the task** - Run:

   ```bash
   python .claude/scripts/task_get.py .llm/todo.md
   ```

2. **Implement the task**
   - Think hard about the plan
   - Focus ONLY on implementing this specific task
   - Ignore TODO/TASK comments in source code
   - Work through the implementation methodically
   - Run appropriate tests and validation

3. **Verify and commit**
   - Verify the build/tests pass if applicable
   - Stage and commit your changes to git with a clear commit message

4. **Mark the task complete** - Run:
   ```bash
   python .claude/scripts/task_complete.py .llm/todo.md
   ```
