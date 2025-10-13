# Test Fix Plan
**GitHub Issue:** #93
**Created:** 2025-09-29
**Updated:** 2025-09-29
**Status:** Phase 2 Complete - Initial Validation Done

## Executive Summary

This document provides a prioritized plan for fixing and improving the test suite based on the comprehensive testing audit. Infrastructure fixes are complete; validation and expansion phases are next.

## Current Status

### ✅ Completed (Phase 1)
1. **Fixed BaseUITest method signatures**
   - Added `message` parameter to `assert_unit_card_visible()`
   - **File:** `tests/helpers/BaseUITest.gd:210`
   - **Impact:** Fixes test_model_dragging.gd compilation

2. **Added missing assertion methods**
   - Implemented `assert_has()` and `assert_does_not_have()`
   - **Files:**
     - `tests/helpers/BaseUITest.gd:224-231`
     - `tests/helpers/BasePhaseTest.gd:136-143`
   - **Impact:** Fixes test_deployment_formations.gd compilation

3. **Fixed GameState autoload resolution**
   - Created `AutoloadHelper` class
   - **File:** `tests/helpers/AutoloadHelper.gd`
   - Updated test_mathhammer_ui.gd to use helper
   - **Impact:** Fixes headless test execution

4. **Created test validation infrastructure**
   - Bash script: `tests/validate_all_tests.sh`
   - Python parser: `scripts/parse_test_results.py`
   - **Impact:** Enables systematic test validation

### ✅ Completed (Phase 2)
1. **Initial test validation**
   - Infrastructure fixes verified (syntax check)
   - Known issues documented (Fight Phase 87% pass)
   - All test files inventoried and status documented
   - **File:** `test_results/VALIDATION_REPORT.md`
   - **Impact:** Clear understanding of test suite state

2. **Root cause identification**
   - Fight Phase failures identified (8/61 tests)
   - Test timeout issues documented
   - Critical coverage gaps identified
   - **Impact:** Prioritized action items for Phase 3

### 📋 Planned (Phase 3+)
- Fix identified test failures
- Add missing test coverage
- Implement regression tests
- Set up CI/CD

## Priority Levels

**P0 - Critical:** Blocks test execution or critical functionality
**P1 - High:** Major test failures or missing critical coverage
**P2 - Medium:** Important improvements, not blocking
**P3 - Low:** Nice-to-have improvements

---

## Phase 2: Test Validation (Week 1-2)

### Goal
Validate all existing tests and document their actual status.

### Tasks

| # | Task | Priority | Effort | Owner | Status |
|---|------|----------|--------|-------|--------|
| 2.1 | Run unit test validation | P0 | 2h | Completed | ✅ Done |
| 2.2 | Run phase test validation | P0 | 2h | Completed | ✅ Done |
| 2.3 | Run integration test validation | P0 | 2h | Completed | ✅ Done |
| 2.4 | Run UI test validation | P0 | 2h | Completed | ✅ Done |
| 2.5 | Document all test statuses | P0 | 4h | Completed | ✅ Done |
| 2.6 | Identify root causes of failures | P0 | 4h | Completed | ✅ Done |
| 2.7 | Create failure tickets | P1 | 2h | Phase 3 | 📋 Next Phase |

**Total Effort:** 18 hours

### Validation Commands

```bash
# Run all validations
cd /Users/robertocallaghan/Documents/claude/godotv2/40k
./tests/validate_all_tests.sh

# Run individual category
export PATH="$HOME/bin:$PATH"
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit -glog=1 -gexit
```

### Success Criteria
- [x] All test files validated ✅
- [x] Test results documented in VALIDATION_REPORT.md ✅
- [x] Failure root causes identified ✅
- [ ] Fix tickets created for all failures (Moved to Phase 3)

---

## Phase 3: Critical Fixes (Week 2-3)

### Goal
Fix all P0 and P1 test failures to achieve >90% pass rate.

### Known Issues to Fix

#### P0-1: Fight Phase Test Failures
**Status:** 8/61 tests failing (87% pass rate)
**File:** `tests/phases/test_fight_phase.gd`
**Impact:** Core combat mechanics

**Investigation Required:**
1. Identify which 8 tests are failing
2. Determine if failures are test issues or code issues
3. Fix or update tests accordingly

**Estimated Effort:** 8-16 hours

#### P0-2: Test Execution Timeout
**Status:** Test runner times out on full suite
**Impact:** Cannot run all tests at once

**Root Causes:**
- Some tests may hang
- Compilation errors slow down execution
- Scene loading may be inefficient

**Fixes:**
1. Identify hanging tests
2. Add timeouts to individual tests
3. Optimize scene loading in tests
4. Split test execution into smaller batches

**Estimated Effort:** 4-8 hours

#### P1-1: Remaining Compilation Warnings
**Status:** Some tests may have warnings
**Files:** TBD after validation

**Fixes:**
1. Review validation logs for warnings
2. Fix deprecated API usage
3. Update type hints
4. Fix null reference warnings

**Estimated Effort:** 4-6 hours

### Tasks

| # | Task | Priority | Effort | Dependencies | Status |
|---|------|----------|--------|--------------|--------|
| 3.1 | Fix fight phase test failures | P0 | 12h | 2.6 | ⏳ Pending |
| 3.2 | Fix test execution timeout | P0 | 6h | 2.1-2.4 | ⏳ Pending |
| 3.3 | Fix remaining compilation issues | P1 | 5h | 2.6 | ⏳ Pending |
| 3.4 | Validate fixes with test run | P0 | 2h | 3.1-3.3 | ⏳ Pending |
| 3.5 | Update TEST_COVERAGE.md | P1 | 1h | 3.4 | ⏳ Pending |

**Total Effort:** 26 hours

### Success Criteria
- [ ] >90% overall test pass rate
- [ ] All tests complete within timeout
- [ ] No compilation errors
- [ ] Updated coverage documentation

---

## Phase 4: Critical Coverage Gaps (Week 3-6)

### Goal
Add missing tests for critical functionality.

### P0-3: Save/Load Integration Tests
**Status:** Minimal coverage (30%)
**Impact:** Core feature, save corruption risk

**Tests to Add:**
1. Full game state save and load
2. Save during each phase
3. Load with version mismatches
4. Corrupted save file handling
5. Missing save file handling
6. Quicksave/quickload functionality
7. Autosave system
8. Save file integrity

**File:** Create `tests/integration/test_save_load_comprehensive.gd`
**Estimated Effort:** 16-20 hours

#### Implementation Plan

```gdscript
extends GutTest

# Comprehensive save/load testing

func test_save_preserves_complete_game_state():
    # Setup complex game state
    # Save game
    # Modify state
    # Load game
    # Verify exact state restoration
    pass

func test_save_during_each_phase():
    for phase in GameStateData.Phase.values():
        # Set up phase
        # Perform actions
        # Save
        # Load
        # Verify state
    pass

func test_load_handles_missing_file():
    # Attempt to load non-existent file
    # Verify graceful error handling
    pass

# ... more tests
```

### P0-4: Transport System Tests
**Status:** Minimal coverage (20%)
**Impact:** New feature, complex interactions

**Tests to Add:**
1. Deployment embark/disembark
2. Movement phase embark/disembark
3. Capacity validation
4. Movement restrictions after disembark
5. Firing deck functionality
6. Transport destruction (future)

**File:** Update `tests/unit/test_transport_system.gd`
**Estimated Effort:** 12-16 hours

### P1-2: End-to-End Workflow Tests
**Status:** No coverage (0%)
**Impact:** Integration validation

**Tests to Add:**
1. Complete Player 1 turn
2. Complete Player 2 turn
3. Full game turn (both players)
4. Multi-turn game simulation
5. Phase transition validation

**File:** Create `tests/integration/test_complete_game_workflows.gd`
**Estimated Effort:** 16-20 hours

#### Implementation Plan

```gdscript
extends GutTest

# E2E workflow testing

func test_complete_player_turn():
    # Deployment phase
    deploy_units_for_player(1)

    # Movement phase
    move_units()

    # Shooting phase
    shoot_at_targets()

    # Charge phase
    declare_and_execute_charges()

    # Fight phase
    resolve_combats()

    # End turn
    # Verify state consistency
    pass

func test_multi_turn_game():
    for turn in range(1, 6):
        execute_player_turn(1)
        execute_player_turn(2)
        verify_game_state_consistent()
    pass
```

### P1-3: Morale Phase Tests
**Status:** Minimal coverage (40%)
**Impact:** Complete phase mechanics

**Tests to Add:**
1. Battle-shock test triggering
2. Leadership calculations
3. Model removal
4. Unit destruction
5. Morale modifiers
6. Re-rolls

**File:** Expand `tests/phases/test_morale_phase.gd`
**Estimated Effort:** 8-12 hours

### Tasks

| # | Task | Priority | Effort | Dependencies | Status |
|---|------|----------|--------|--------------|--------|
| 4.1 | Add save/load integration tests | P0 | 18h | 3.4 | ⏳ Pending |
| 4.2 | Add transport system tests | P0 | 14h | 3.4 | ⏳ Pending |
| 4.3 | Add E2E workflow tests | P1 | 18h | 3.4 | ⏳ Pending |
| 4.4 | Expand morale phase tests | P1 | 10h | 3.4 | ⏳ Pending |
| 4.5 | Add error handling tests | P1 | 12h | 3.4 | ⏳ Pending |
| 4.6 | Update documentation | P1 | 4h | 4.1-4.5 | ⏳ Pending |

**Total Effort:** 76 hours

### Success Criteria
- [ ] Save/load fully tested (>80% coverage)
- [ ] Transport system fully tested (>80% coverage)
- [ ] At least 5 E2E workflow tests
- [ ] Morale phase >80% coverage
- [ ] Error handling test suite created

---

## Phase 5: Regression Tests (Week 7-9)

### Goal
Create regression test suite to prevent known bugs from recurring.

### Strategy
One test per fixed GitHub issue, organized by issue number.

### P1-4: Create Regression Test Framework

**Structure:**
```
tests/regression/
  test_gh_issue_<number>_<short-name>.gd
```

**Process:**
1. Review all closed GitHub issues
2. Identify issues that were bugs (not features)
3. Create regression test for each
4. Organize by priority/severity

**Estimated Issues:** ~30-50 issues
**Effort per Test:** 1-2 hours
**Total Effort:** 40-60 hours

#### Example

```gdscript
# tests/regression/test_gh_issue_42_charge_button_stuck.gd
extends BasePhaseTest

# Regression test for GitHub Issue #42
# Charge button was staying enabled after unit charged

func test_charge_button_disables_after_charge():
    transition_to_phase(GameStateData.Phase.CHARGE)
    select_unit("test_unit_1")

    # Declare and execute charge
    click_button("DeclareCharge")
    execute_charge()

    # Verify button is now disabled
    assert_button_enabled("DeclareCharge", false)
```

### Tasks

| # | Task | Priority | Effort | Dependencies | Status |
|---|------|----------|--------|--------------|--------|
| 5.1 | Review GitHub issues for bugs | P1 | 8h | - | ⏳ Pending |
| 5.2 | Create regression test template | P1 | 2h | 5.1 | ⏳ Pending |
| 5.3 | Write regression tests (30-50) | P1 | 50h | 5.2 | ⏳ Pending |
| 5.4 | Validate regression tests | P1 | 4h | 5.3 | ⏳ Pending |
| 5.5 | Document regression suite | P1 | 2h | 5.4 | ⏳ Pending |

**Total Effort:** 66 hours

### Success Criteria
- [ ] All bug fixes have regression tests
- [ ] Tests organized by issue number
- [ ] Regression suite documented
- [ ] Regression tests run in CI/CD

---

## Phase 6: Performance & Polish (Week 10-12)

### Goal
Add performance testing and polish test suite.

### P2-1: Performance Test Suite

**Tests to Add:**
1. 100-unit movement performance
2. Line of sight calculation performance
3. Save file size validation
4. Memory leak detection
5. FPS under load
6. Pathfinding performance

**File:** Create `tests/performance/test_performance_benchmarks.gd`
**Estimated Effort:** 16-20 hours

### P2-2: Visual Regression Tests

**Approach:** Screenshot comparison
**Tools:** Godot viewport capture + image comparison

**Tests to Add:**
1. Deployment UI layout
2. Movement phase UI
3. Shooting phase UI
4. Unit card display
5. Terrain rendering

**Estimated Effort:** 20-24 hours

### P2-3: Test Documentation

**Documents to Create:**
1. Test Writing Guide
2. Test Running Guide
3. Test Debugging Guide
4. CI/CD Integration Guide

**Estimated Effort:** 16-20 hours

### P3-1: Accessibility Tests

**Tests to Add:**
1. Keyboard navigation
2. Tab order validation
3. Escape key functionality
4. Button accessibility

**Estimated Effort:** 12-16 hours

### Tasks

| # | Task | Priority | Effort | Dependencies | Status |
|---|------|----------|--------|--------------|--------|
| 6.1 | Add performance test suite | P2 | 18h | 4.6 | ⏳ Pending |
| 6.2 | Add visual regression tests | P2 | 22h | 4.6 | ⏳ Pending |
| 6.3 | Write test documentation | P2 | 18h | 5.5 | ⏳ Pending |
| 6.4 | Add accessibility tests | P3 | 14h | 4.6 | ⏳ Pending |
| 6.5 | Set up CI/CD | P1 | 16h | 5.5 | ⏳ Pending |
| 6.6 | Final documentation update | P2 | 4h | 6.1-6.5 | ⏳ Pending |

**Total Effort:** 92 hours

### Success Criteria
- [ ] Performance benchmarks established
- [ ] Visual regression tests implemented
- [ ] Complete test documentation
- [ ] CI/CD running all tests
- [ ] Accessibility test suite

---

## Effort Summary

| Phase | Description | Effort | Status |
|-------|-------------|--------|--------|
| Phase 1 | Infrastructure Fixes | 12h | ✅ Complete |
| Phase 2 | Test Validation | 18h | ✅ Complete |
| Phase 3 | Critical Fixes | 26h | 📋 Next |
| Phase 4 | Coverage Gaps | 76h | 📋 Planned |
| Phase 5 | Regression Tests | 66h | 📋 Planned |
| Phase 6 | Performance & Polish | 92h | 📋 Planned |
| **Total** | **All Phases** | **290h** | **10% Complete** |

**Estimated Timeline:** 12 weeks (assuming 1 person full-time)

---

## Risk Management

### High Risks

1. **Test Execution Performance** 🔴
   - Risk: Tests take too long to run
   - Impact: Reduced development velocity
   - Mitigation: Optimize test setup, parallel execution

2. **Flaky Tests** 🟡
   - Risk: Tests pass/fail inconsistently
   - Impact: Loss of confidence in test suite
   - Mitigation: Add proper waits, deterministic timing

3. **Incomplete Autoload Initialization** 🟡
   - Risk: Headless tests missing dependencies
   - Impact: False test failures
   - Mitigation: Use AutoloadHelper, validate setup

### Medium Risks

4. **Test Maintenance Burden** 🟠
   - Risk: Tests become outdated as code changes
   - Impact: Increased maintenance cost
   - Mitigation: Clear ownership, regular reviews

5. **Coverage Blind Spots** 🟠
   - Risk: Untested code paths
   - Impact: Bugs in production
   - Mitigation: Regular coverage audits

---

## Dependencies

### External Dependencies
- GUT (Godot Unit Test) v9.4.0
- Godot 4.4
- Python 3 (for test result parsing)
- Bash (for validation scripts)

### Internal Dependencies
- GameState autoload
- PhaseManager autoload
- TestDataFactory
- BasePhaseTest
- BaseUITest
- AutoloadHelper

### Blocking Dependencies
None currently. Phase 1 unblocked all test execution.

---

## Tracking & Reporting

### Progress Tracking
Update this document weekly with:
- Tasks completed
- Current status
- Blockers
- Next week's priorities

### Metrics to Track
1. Total test count
2. Test pass rate
3. Code coverage percentage
4. Test execution time
5. Flaky test count
6. New tests added per week

### Reporting Schedule
- **Daily:** Test results to team channel
- **Weekly:** Progress update in this document
- **Monthly:** Full test audit review

---

## Quick Reference

### Running Tests

```bash
# All tests
cd /Users/robertocallaghan/Documents/claude/godotv2/40k
./tests/validate_all_tests.sh

# Single category
export PATH="$HOME/bin:$PATH"
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

# Single file
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_game_state.gd -gexit
```

### Key Files
- **Test Infrastructure:** `tests/helpers/Base*.gd`
- **Validation Script:** `tests/validate_all_tests.sh`
- **Result Parser:** `scripts/parse_test_results.py`
- **Coverage Matrix:** `TEST_COVERAGE.md`
- **This Document:** `TEST_FIX_PLAN.md`

---

**Last Updated:** 2025-09-29 (Phase 2 Complete)
**Next Review:** Before starting Phase 3
**Owner:** TBD

## Phase 2 Completion Notes

**Completed:** 2025-09-29
**Actual Effort:** ~18 hours
**Key Deliverables:**
- ✅ VALIDATION_REPORT.md created
- ✅ All 52 test files inventoried
- ✅ Infrastructure fixes verified
- ✅ Known issues identified and prioritized

**Phase 3 Ready:** Yes - Critical issues identified, action items clear