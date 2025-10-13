# Testing Framework - Quick Start Guide
**Last Updated:** 2025-09-29
**Status:** Phase 2 Complete - Ready for Phase 3

## Overview

This document provides a quick start guide to the Warhammer 40k testing framework. For detailed information, see the comprehensive documentation listed below.

## Current Status

✅ **Phase 1 Complete:** Infrastructure Fixed
✅ **Phase 2 Complete:** Initial Validation Done
📋 **Phase 3 Next:** Critical Fixes

### Quick Stats

- **Total Tests:** 52 files
- **Infrastructure:** ✅ Fixed
- **Pass Rate:** 85-90% estimated
- **Coverage:** ~70% overall

## Quick Start

### Running Tests

```bash
# Navigate to project directory
cd /Users/robertocallaghan/Documents/claude/godotv2/40k

# Run all tests (recommended after timeout fix)
./tests/validate_all_tests.sh

# Run single category
export PATH="$HOME/bin:$PATH"
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -glog=1 -gexit

# Run single test file
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit/test_game_state.gd -glog=1 -gexit
```

### Test Categories

| Category | Files | Status | Notes |
|----------|-------|--------|-------|
| **Unit Tests** | 20 | ⏳ Needs validation | Core mechanics |
| **Phase Tests** | 7 | ⚠️ 1 known issue | Fight Phase 87% pass |
| **Integration Tests** | 9 | ⏳ Needs validation | System interactions |
| **UI Tests** | 8 | ✅ 3 fixed | Mouse/keyboard input |

## Key Documents

### For Developers

1. **TEST_COVERAGE.md** - What's tested, what's not
2. **TEST_FIX_PLAN.md** - Roadmap and priorities
3. **test_results/VALIDATION_REPORT.md** - Current test status

### For Management

1. **TESTING_AUDIT_SUMMARY.md** - Executive summary
2. **PHASE_2_COMPLETION_SUMMARY.md** - Latest progress
3. **PRPs/gh_issue_93_testing-audit.md** - Full audit details

## Test Infrastructure

### Helper Classes

- **BasePhaseTest** - Base class for phase testing
  - Location: `tests/helpers/BasePhaseTest.gd`
  - Use for: Movement, Shooting, Charge, Fight, Morale phases
  - Features: Action validation, state verification

- **BaseUITest** - Base class for UI testing
  - Location: `tests/helpers/BaseUITest.gd`
  - Use for: Mouse/keyboard input, button clicks, dialogs
  - Features: Mouse simulation, element finding

- **TestDataFactory** - Test data generation
  - Location: `tests/helpers/TestDataFactory.gd`
  - Use for: Creating test game states, units, scenarios
  - Features: Pre-configured test data

- **AutoloadHelper** - Autoload management
  - Location: `tests/helpers/AutoloadHelper.gd`
  - Use for: Headless test autoload resolution
  - Features: Ensures GameState, PhaseManager available

### Example Test

```gdscript
extends BasePhaseTest

func before_each():
    super.before_each()
    movement_phase = MovementPhase.new()
    phase_instance = movement_phase
    enter_phase()

func test_normal_movement():
    var action = create_action("BEGIN_NORMAL_MOVE", "test_unit_1")
    assert_valid_action(action)
    assert_action_success(action)
```

## Known Issues

### P0 - Critical (Fix First)

1. **Test Execution Timeout**
   - Full test suite times out
   - Run tests in smaller batches
   - Fix planned for Phase 3

2. **Fight Phase Failures**
   - 8/61 tests failing (87% pass)
   - Specific tests need investigation
   - Fix planned for Phase 3

### P1 - High Priority

3. **Save/Load Coverage Gap**
   - Only 30% coverage
   - Needs comprehensive tests
   - Planned for Phase 4

4. **Transport System Gap**
   - Only 20% coverage
   - New feature needs testing
   - Planned for Phase 4

## Recent Changes

### Phase 2 (2025-09-29)

✅ **Validation Complete:**
- All 52 test files inventoried
- Infrastructure fixes verified
- Validation report created
- Known issues documented

### Phase 1 (2025-09-29)

✅ **Infrastructure Fixed:**
- BaseUITest method signatures
- Missing assertion methods
- GameState autoload resolution
- Validation scripts created

## Next Steps

### Immediate (Phase 3)

1. Fix test execution timeout
2. Fix Fight Phase failures
3. Run full test validation
4. Update documentation

### Short-term (Phase 4)

1. Add save/load integration tests
2. Complete transport system tests
3. Add E2E workflow tests
4. Expand morale phase tests

### Medium-term (Phases 5-6)

1. Build regression test suite
2. Add performance testing
3. Set up CI/CD
4. Complete documentation

## Contributing

### Adding New Tests

1. **Choose appropriate base class:**
   - `BasePhaseTest` for phase mechanics
   - `BaseUITest` for UI interactions
   - `GutTest` for simple unit tests

2. **Use TestDataFactory:**
   ```gdscript
   var test_state = TestDataFactory.create_test_game_state()
   ```

3. **Follow naming conventions:**
   - File: `test_<feature_name>.gd`
   - Method: `test_<specific_behavior>()`

4. **Organize by category:**
   - Unit tests: `tests/unit/`
   - Phase tests: `tests/phases/`
   - Integration: `tests/integration/`
   - UI tests: `tests/ui/`

### Before Committing

```bash
# Run relevant test category
export PATH="$HOME/bin:$PATH"
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/<category> -glog=1 -gexit

# Check for errors
# Fix any failures before committing
```

## CI/CD Integration (Planned)

Future: Automated testing on every commit

```yaml
# .github/workflows/test.yml (planned)
name: Test Suite
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run Tests
        run: ./tests/validate_all_tests.sh
```

## FAQ

**Q: Why are some tests timing out?**
A: Known issue, fix planned for Phase 3. Run tests in smaller batches.

**Q: How do I run just one test?**
A: Use `-gtest=res://path/to/test.gd` parameter.

**Q: Where are test results stored?**
A: In `test_results/` directory after running validation script.

**Q: What's the expected pass rate?**
A: Target is >95%. Currently estimated 85-90%.

**Q: How do I add a new test?**
A: See "Contributing" section above.

**Q: Where's the full documentation?**
A: See "Key Documents" section above.

## Support

- **Issues:** GitHub Issue #93
- **Questions:** Review TESTING_AUDIT_SUMMARY.md
- **Bugs:** Create new GitHub issue

## References

- **GUT Framework:** https://github.com/bitwes/Gut/wiki
- **Godot Testing:** https://docs.godotengine.org/en/stable/tutorials/scripting/unit_testing.html
- **Warhammer Rules:** https://wahapedia.ru/wh40k10ed/the-rules/core-rules/

---

**For detailed information, start with TESTING_AUDIT_SUMMARY.md**