# Multiplayer Test Failures - Unresolved Issues PRD

**Date:** 2025-10-29
**Status:** Issues Identified, Solutions Proposed
**Priority:** High - Blocking Integration Tests

---

## Executive Summary

During investigation of multiplayer integration test failures, we identified and fixed one critical issue (port mismatch) but discovered several other blocking issues that prevent the tests from passing. This document details all unresolved issues that need to be addressed to achieve full test functionality.

---

## Issues Overview

| Issue | Severity | Impact | Tests Affected |
|-------|----------|--------|----------------|
| Unit ID Mismatches | Critical | Tests cannot find units to deploy | All deployment tests |
| Missing Test Infrastructure | Critical | Tests fail to compile/load | Fight phase tests |
| ArmyListManager Inheritance | High | Autoload initialization fails | All tests |
| JSON Parsing Errors | Medium | Test result verification fails | All multiplayer tests |
| Save File Dependencies | Medium | Tests depend on missing save files | Deployment tests |

---

## Issue 1: Unit ID Mismatches

### Problem Description
Tests are using hardcoded unit IDs that don't match the actual unit IDs in the game system.

### Current State
**Test Expects:**
```gdscript
"unit_id": "unit_p1_1"  # Line 104 in test_multiplayer_deployment.gd
"unit_id": "unit_p1_3"  # Line 271
"unit_id": "unit_p2_1"  # Line 218
```

**Game Actually Has:**
```
Player 1 Units:
- "unit_p1_blade_champion"
- "unit_p1_custodian_guard"
- "unit_p1_witchseekers"

Alternative IDs (from different save states):
- "U_INTERCESSORS_A"
- "U_TACTICAL_A"
- "U_BOYZ_A"
- "U_GRETCHIN_A"
```

### Error Messages
```
ERROR: GameManager: Unit not found: unit_p1_1
ERROR: GameManager: Available units: ["unit_p1_blade_champion", "unit_p1_custodian_guard", "unit_p1_witchseekers", "unit_p2_battlewagon", "unit_p2_boyz", "unit_p2_warboss"]
```

### Impact
- All deployment tests fail immediately
- Cannot test unit deployment functionality
- Blocks testing of deployment zones, turn alternation, and coherency

### Proposed Solution
1. **Option A: Update Test IDs**
   - Modify `test_multiplayer_deployment.gd` to use actual unit IDs
   - Map test cases to specific known units

2. **Option B: Dynamic Unit Discovery**
   - Query available units from GameManager before testing
   - Use first available unit for each player
   ```gdscript
   var available_units = await simulate_host_action("get_available_units", {})
   var test_unit = available_units.get("player_1_units", [])[0]
   ```

3. **Option C: Standardize Test Units**
   - Create dedicated test save files with predictable unit IDs
   - Ensure consistency across all test scenarios

### Files to Modify
- `/tests/integration/test_multiplayer_deployment.gd` - Lines 104, 144, 182, 218, 244, 271, 348

---

## Issue 2: Missing Test Infrastructure Functions

### Problem Description
Test base classes are missing the `add_child_autofree()` function that tests are trying to call.

### Current State
```
SCRIPT ERROR: Parse Error: Function "add_child_autofree()" not found in base self.
at: GDScript::reload (res://tests/integration/test_fight_phase_wound_application.gd:8)
```

### Affected Files
- `test_fight_phase_wound_application.gd:8`
- `test_fight_phase_alternation.gd:9`
- Multiple archived UI tests

### Impact
- Fight phase tests cannot load or run
- Test infrastructure is incomplete
- Prevents testing of critical combat mechanics

### Root Cause Analysis
The `add_child_autofree()` function appears to be a GUT testing framework helper that:
1. Adds a node to the scene tree for testing
2. Automatically frees it after the test completes
3. Prevents memory leaks in tests

### Proposed Solution
1. **Add Helper to GutTest Base Class**
   ```gdscript
   # In test base class or helper
   func add_child_autofree(node: Node) -> Node:
       add_child(node)
       autofree(node)  # GUT's autofree mechanism
       return node
   ```

2. **Update Test Imports**
   - Ensure tests extend the correct base class
   - Import necessary helpers

3. **Alternative: Remove Usage**
   - Refactor tests to use standard `add_child()` and `queue_free()`
   - Manage cleanup in `after_each()` methods

### Files to Modify
- Create `/tests/helpers/TestExtensions.gd` with missing functions
- Update affected test files to properly import/extend base classes

---

## Issue 3: ArmyListManager Autoload Error

### Problem Description
The ArmyListManager autoload doesn't inherit from Node, preventing it from being added to the scene tree.

### Current State
```
ERROR: Failed to instantiate an autoload, script 'res://autoloads/ArmyListManager.gd' does not inherit from 'Node'.
at: start (main/main.cpp:4335)
```

### Impact
- Autoload system partially broken
- Tests fall back to placeholder armies
- May cause inconsistent test behavior

### Root Cause
```gdscript
# Current (incorrect):
extends RefCounted  # or extends Resource

# Should be:
extends Node
```

### Proposed Solution
1. **Fix Inheritance**
   ```gdscript
   extends Node
   class_name ArmyListManager
   ```

2. **Verify Singleton Pattern**
   - Ensure proper singleton implementation
   - Check for any RefCounted-specific functionality that needs migration

3. **Update Project Settings**
   - Verify autoload configuration in project.godot
   - Ensure path and name are correct

### Files to Modify
- `/autoloads/ArmyListManager.gd` - Line 1 (extends declaration)

---

## Issue 4: JSON Parsing Errors in Test Results

### Problem Description
Test result JSON files are either malformed or being read incorrectly, causing parsing failures.

### Current State
```
ERROR: [Test] Failed to parse result JSON
at: push_error (core/variant/variant_utility.cpp:1024)
```

### Location in Code
`/tests/helpers/MultiplayerIntegrationTest.gd:317` - `_wait_for_result()` function

### Impact
- Cannot verify test action results
- Test assertions fail even when actions succeed
- Blocks proper test verification

### Root Cause Possibilities
1. Result file written incorrectly by TestModeHandler
2. Race condition - reading file before fully written
3. JSON structure mismatch between writer and reader
4. File permissions or lock issues

### Proposed Solution
1. **Add Robust Error Handling**
   ```gdscript
   func _wait_for_result(command_file: String, timeout: float) -> Dictionary:
       # ... existing code ...

       # Add retry logic for file reading
       var max_retries = 3
       for i in range(max_retries):
           var file = FileAccess.open(result_path, FileAccess.READ)
           if file:
               var json_string = file.get_as_text()
               file.close()

               if json_string.length() > 0:
                   var json = JSON.new()
                   var error = json.parse(json_string)
                   if error == OK:
                       return json.data.get("result", {})
                   else:
                       print("[Test] JSON parse attempt %d failed: %s" % [i+1, json_string])

               await wait_for_seconds(0.1)

       return {"success": false, "message": "Failed to parse result after retries"}
   ```

2. **Add JSON Validation**
   - Validate JSON structure before parsing
   - Log malformed JSON for debugging

3. **Fix Writer Side**
   - Ensure TestModeHandler writes valid JSON
   - Add file flush after writing

### Files to Modify
- `/tests/helpers/MultiplayerIntegrationTest.gd:279-344` - Result parsing logic
- `/autoloads/TestModeHandler.gd` - Result file writing

---

## Issue 5: Missing or Incorrect Save Files

### Problem Description
Tests are attempting to load save files that either don't exist or contain unexpected data.

### Current State
- Test tries to load `"deployment_start"` save file (line 87-90)
- Available saves have different unit configurations than expected
- Save file format may have changed

### Impact
- Tests cannot set up proper initial state
- Deployment phase tests start with wrong configuration
- Unit availability doesn't match test expectations

### Proposed Solution
1. **Generate Test-Specific Saves**
   ```gdscript
   # In test setup
   func generate_test_save():
       var save_data = {
           "phase": "Deployment",
           "units": {
               "player_1": ["unit_p1_1", "unit_p1_2", "unit_p1_3"],
               "player_2": ["unit_p2_1", "unit_p2_2", "unit_p2_3"]
           }
       }
       SaveLoadManager.save_game("test_deployment_start", save_data)
   ```

2. **Create Save File Documentation**
   - Document required save files for tests
   - Create script to generate all test saves
   - Add validation before test runs

3. **Use Save Generator Script**
   - The existing `/tests/run_save_generator.gd` script should be fixed and used
   - Ensure it generates saves with expected unit IDs

### Files to Create/Modify
- `/tests/saves/deployment_start.w40ksave` - Create with correct structure
- `/tests/helpers/TestSaveGenerator.gd` - Enhance save generation
- `/tests/run_save_generator.gd` - Fix and document

---

## Implementation Priority

### Phase 1: Critical Fixes (Blocks All Tests)
1. **Fix Unit ID Mismatches** - Without this, no deployment tests can pass
2. **Fix Test Infrastructure** - Required for fight phase tests
3. **Fix ArmyListManager** - Affects all test initialization

### Phase 2: Test Reliability (Improves Success Rate)
4. **Fix JSON Parsing** - Makes test results reliable
5. **Generate Proper Save Files** - Ensures consistent test state

### Phase 3: Long-term Improvements
- Add comprehensive test data management
- Create test fixture system
- Implement better error reporting
- Add test retry mechanisms

---

## Success Criteria

1. All multiplayer deployment tests pass consistently
2. Fight phase tests load and execute without errors
3. No autoload initialization errors during test runs
4. Test results are properly captured and verified
5. Tests can run independently without external save file dependencies

---

## Testing the Fixes

After implementing each fix:

```bash
# Test individual fixes
godot --path . -s addons/gut/gut_cmdln.gd \
    -gdir=res://tests/integration/ \
    -gfile=test_multiplayer_deployment.gd \
    -gtest=test_basic_multiplayer_connection \
    -gexit

# Run full integration suite
godot --path . -s addons/gut/gut_cmdln.gd \
    -gdir=res://tests/integration/ \
    -gexit

# Generate test report
./tests/run_multiplayer_tests.sh -f test_multiplayer_deployment.gd
```

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Breaking existing game functionality | Low | High | Run full regression tests |
| Test fixes introduce new bugs | Medium | Medium | Code review, incremental changes |
| Save file format changes | Medium | High | Version save files, migration scripts |
| Performance degradation | Low | Low | Monitor test execution times |

---

## Conclusion

The multiplayer test failures stem from multiple interconnected issues. While the port mismatch has been resolved, the remaining issues prevent the tests from running successfully. The most critical issue is the unit ID mismatch, which affects all deployment tests. A systematic approach to fixing these issues, starting with the most critical, will restore test functionality and improve overall code quality.

The fixes are straightforward but require careful implementation to avoid breaking existing functionality. Once resolved, these tests will provide valuable validation of the multiplayer system's correctness.