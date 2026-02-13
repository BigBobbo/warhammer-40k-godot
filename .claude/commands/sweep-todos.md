---
description: Find all TODO and TASK comments and add them to the project task list
model: haiku
---

Find all TODO and TASK comments and add them to the project task list.

Search the codebase for all TODO and TASK comments and add them to `.llm/todo.md`. Each TODO or TASK found in the code will be converted to a task in the markdown task list.

## Steps

1. Find all occurrences of "TODO" in the codebase using grep/search
2. For each occurrence, gather:
   - File path
   - Line number
   - Full TODO comment text
3. Strip comment markers (`//`, `#`, `/* */`) from the TODO/TASK text
4. Add each TODO or TASK as a new task entry to `.llm/todo.md` using:
   ```bash
   python .claude/scripts/task_add.py .llm/todo.md "Implement TODO from filepath:line: description"
   ```

## Example output

```markdown
- [ ] Implement TODO from scenes/game/combat.gd:87: Add line of sight calculation
- [ ] Implement TODO from scripts/unit.gd:103: Handle multi-model unit coherency
```
