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

3. **Handle tests that cannot be run in this environment**

   Godot tests cannot be launched in this headless/remote environment. This is a known limitation. If the task involves writing or running Godot tests:
   - Still **write the test code** as part of your implementation
   - Do NOT fail or block the task just because you cannot execute the tests
   - Instead, append an entry to `TESTS_NEEDED.md` in the project root describing what needs to be verified locally

   **Format for `TESTS_NEEDED.md`** (create the file if it doesn't exist, append if it does):

   ```markdown
   ## <Short description of what was implemented>

   **Task:** <the original task description, condensed to one line>
   **Files changed:** <list of files you created or modified>
   **Tests to run:**
   - <test file path and how to run it, e.g. "Run `test_deployment_phase.gd` via the Godot test runner">
   - <what each test verifies>

   **What to look for:**
   - <specific things the user should verify pass>
   - <any edge cases or scenarios covered>
   ```

   This ensures the user can run the tests locally later.

4. **Verify and commit**
   - Verify the build/tests pass if applicable (skip Godot test execution — it is sufficient to have written the tests and logged them to `TESTS_NEEDED.md`)
   - Stage and commit your changes to git with a clear commit message describing what was done

5. **Mark the task complete** - Run:
   ```bash
   python .claude/scripts/task_complete.py .llm/todo.md
   ```
