---
name: plan-tasks
description: Capture conversation planning into self-contained tasks at end of discussion
---

# Plan Tasks

Transform conversation planning and requirements into a markdown task list where each task is completely self-contained with all necessary context inline.

## Task Format

The task list is in `.llm/todo.md`.

NEVER use the `Read` tool on `.llm/todo.md`. Always interact with the task list exclusively through the Python scripts.

### Task States

- `[ ]` - Not started (ready to work on)
- `[x]` - Completed
- `[!]` - Blocked after failed attempt

### Standalone Context

Each task is extracted and executed in isolation. The `task_get.py` script extracts only one task at a time - it cannot see other tasks in the file. Therefore:

1. Every task must contain ALL context needed to implement it
2. Repeat shared context in every related task - if 5 tasks share the same background, repeat it 5 times
3. Never reference other tasks - phrases like "similar to task above" are useless
4. Include the full picture - source of inspiration, files involved, patterns to follow

## When to Use

Use this command at the **end of a planning conversation** when you have discussed requirements, approaches, and implementation details but have not started coding yet. This captures the conversation context into actionable tasks in `.llm/todo.md`.

## Input

The input is the current conversation where planning and requirements have been discussed. Transform the plans, ideas, and requirements from the discussion into self-contained tasks in a markdown checklist format, appended to `.llm/todo.md`.

## Task Writing Guidelines

Each task should be written so it can be read independently from `- [ ]` to the next `- [ ]` and contain:

1. **Full absolute paths** - Never use relative paths
2. **Exact class/function names** - Specify exact names of code elements
3. **Analogies to existing code** - Reference similar existing implementations
4. **Specific implementation details** - List concrete methods or operations
5. **Module/package context** - State which module or package the work belongs to
6. **Dependencies and prerequisites** - Note what needs to exist or be imported
7. **Expected outcomes** - Describe what success looks like

## Adding Tasks

Use the script to add each task:

```bash
python .claude/scripts/task_add.py .llm/todo.md "Task description
  Context line 1
  Context line 2"
```

## Example

```markdown
- [ ] Create a new test for the deployment phase in `/home/user/warhammer-40k-godot/40k/tests/test_deployment_phase.gd`. The test should verify that units can be placed in valid deployment zones during the deployment phase. Similar to how movement phase tests work in `test_movement_phase.gd`, this should use the test framework to set up a game state, place units, and verify positions. Include tests for: valid deployment zone placement, invalid zone rejection, and unit overlap prevention.
```
