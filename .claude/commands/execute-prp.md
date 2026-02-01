# Execute PRP

Implement a feature using the specified PRP (Product Requirement Prompt) file.

## PRP File: $ARGUMENTS

---

## Execution Process

### 1. Load & Analyze PRP
- Read the specified PRP file completely
- Identify the **Problem Statement** and **Solution Overview**
- Note all **Dependencies** - check if prerequisite PRPs are implemented
- Review **Acceptance Criteria** as your success checklist
- Review **Constraints** as hard requirements that cannot be violated

### 2. Check Dependencies
- If the PRP lists dependencies (e.g., "Requires PRP-031"):
  - Check if those features exist in the codebase
  - If missing, STOP and inform the user which PRPs must be done first
  - Suggest implementing dependencies first

### 3. Gather Context
- Read all **Related Files** listed in the PRP
- Search for existing patterns in the codebase that match the feature
- If the PRP references external rules (e.g., Wahapedia), fetch that documentation
- Understand how the feature integrates with existing systems

### 4. ULTRATHINK - Create Implementation Plan
- Think deeply about the implementation before writing any code
- Create a detailed plan addressing ALL requirements from the PRP
- Use **TodoWrite** to break down the **Implementation Tasks** from the PRP
- Identify potential edge cases and how to handle them
- Consider multiplayer sync implications if applicable
- Plan your test cases based on the PRP's test scenarios

### 5. Implement
- Follow the plan step by step
- Update todos as you complete each task
- Follow existing code patterns and conventions
- Add appropriate logging (but respect PRP-033 guidelines if implemented)
- Write code that matches the examples in the PRP where provided

### 6. Validate
Run validation in this order:

**a) Syntax Check:**
```bash
timeout 30 $HOME/bin/godot --headless --path /Users/robertocallaghan/Documents/claude/godotv2/40k --check-only
```

**b) Run Related Tests (if they exist):**
```bash
# Run unit tests for the feature
$HOME/bin/godot --headless --path /Users/robertocallaghan/Documents/claude/godotv2/40k -s addons/gut/gut_cmdln.gd -gfile res://tests/unit/test_[feature_name].gd -gexit

# Run integration tests for the feature (if they exist)
$HOME/bin/godot --headless --path /Users/robertocallaghan/Documents/claude/godotv2/40k -s addons/gut/gut_cmdln.gd -gfile res://tests/integration/test_[feature_name]_integration.gd -gexit
```
Note: Use `-gfile` to run only the specified test file. Do NOT run the full test suite.

**c) Check Debug Logs:**
- Primary: `/Users/robertocallaghan/Library/Application Support/Godot/app_userdata/40k/logs/debug_YYYYMMDD_HHMMSS.log`
- If not found, use: `print(DebugLogger.get_real_log_file_path())`
- Look for errors, warnings, or unexpected behavior

**d) Manual Validation:**
- If automated tests don't cover the feature, describe manual test steps
- Alert user if manual testing is required

### 7. Verify Acceptance Criteria
- Go through EACH acceptance criterion in the PRP
- Mark as verified or identify gaps
- Fix any gaps before completing

### 8. Complete
- Ensure ALL **Implementation Tasks** checkboxes are addressed
- Run final validation suite
- Re-read the PRP to confirm nothing was missed
- Report completion status with:
  - Summary of changes made
  - Files modified/created
  - Any deviations from the PRP (and why)
  - Known limitations or future work

---

## Error Handling

**If validation fails:**
1. Read the error message carefully
2. Check if the PRP has error patterns/solutions
3. Fix the issue
4. Re-run validation
5. Repeat until passing

**If blocked by missing dependency:**
1. STOP implementation
2. Report which dependency is missing
3. Suggest implementing the dependency first

**If PRP requirements are ambiguous:**
1. State your interpretation
2. Ask the user to confirm before proceeding
3. Document the decision

**If external documentation is needed:**
1. Use WebFetch to get Wahapedia or Godot docs
2. Extract relevant rules
3. Verify implementation matches rules exactly

---

## Quality Checklist

Before marking complete, verify:
- [ ] All acceptance criteria met
- [ ] All implementation tasks addressed
- [ ] No regressions in existing functionality
- [ ] Code follows project conventions
- [ ] Appropriate logging added
- [ ] Multiplayer sync considered (if applicable)
- [ ] Edge cases handled
- [ ] PRP re-read for final verification

---

## Notes

- You can reference the PRP at any time during implementation
- Use `@docs/PRP/shooting_phase/[path]` to reference other PRPs
- If the feature is complex, consider implementing in phases
- Always prioritize correctness over speed
