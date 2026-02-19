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

3. **Handle tests that cannot be run in this environment**

   Godot tests cannot be launched in this headless/remote environment. If the task involves writing or running Godot tests:
   - Still **write the test code** as part of your implementation
   - Do NOT fail or block the task just because you cannot execute the tests
   - Append an entry to `TESTS_NEEDED.md` in the project root describing what needs to be verified locally (create the file if it doesn't exist):

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

4. **Verify and commit**
   - Verify the build/tests pass if applicable (skip Godot test execution — it is sufficient to have written the tests and logged them to `TESTS_NEEDED.md`)
   - Stage and commit your changes to git with a clear commit message

5. **Mark the task complete** - Run:
   ```bash
   python .claude/scripts/task_complete.py .llm/todo.md
   ```
