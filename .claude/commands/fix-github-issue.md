Please analyze and fix the GitHub issue: $ARGUMENTS.

Follow these steps:

1. Use `gh issue view` to get the issue details
2. Understand the problem described in the issue
3. Search the codebase for relevant files
4. Make a clear plan to fix the issue and ask the user whether to proceed
5. If yes implement the necessary changes to fix the issue
6. Write and run tests to verify the fix
7. Ensure code passes linting and type checking
8. Create a descriptive commit message
9. Ask the user for approval to commit and if they approve then commit
10. Do not close the issue but instead add a "claude-completed" label/tag to it

Remember to use the GitHub CLI (`gh`) for all GitHub-related tasks.