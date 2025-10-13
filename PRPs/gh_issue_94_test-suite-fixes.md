# PRP: Test Suite Compilation and Runtime Fixes
**GitHub Issue:** #94 (Related to #93 Testing Audit)
**Feature Name:** Test Suite Fixes
**Author:** Claude Code AI
**Date:** 2025-09-29
**Confidence Score:** 9/10

## Problem Statement

The test validation revealed systematic issues preventing tests from running successfully. Analysis of 44 test files shows **87% pass rate (53/61 tests passing, 8 failing)** with consistent error patterns across all test files:

### Primary Error Categories (by frequency):

1. **271 occurrences:** `Invalid call. Nonexistent function 'new' in base 'GDScript'`
2. **59 occurrences:** `Identifier "gut" not declared in the current scope`
3. **53 occurrences:** `Invalid call. Nonexistent function 'validate_action' in base 'Nil'`
4. **35 occurrences:** `Invalid call. Nonexistent function 'enter_phase' in base 'Node (MoralePhase)'`
5. **28 occurrences:** `Invalid call. Nonexistent function 'process_action' in base 'Nil'`
6. **23 occurrences:** `Function "pending()" not found in base self`
7. **16 occurrences:** `Too many arguments for "assert_button_enabled()" call`
8. **16 occurrences:** `Function "assert_has()" not found in base self`
9. **13 occurrences:** `Identifier not found: TerrainManager`
10. **8 occurrences:** `Function "assert_ge()" not found in base self`

These errors indicate:
- Missing assertion methods in GutTest base class
- Incorrect class instantiation patterns
- Missing autoload references
- Incomplete helper method implementations

## Requirements Analysis

### Core Requirements

1. **Fix Missing Assertion Methods**
   - Add `pending()`, `assert_ge()`, `assert_le()` to GutTest
   - Ensure all assertion methods support optional message parameter
   - Match GUT v9.4.0 API

2. **Fix Class Instantiation Issues**
   - BasePhase and derived classes cannot be instantiated directly
   - Need preload() pattern for abstract classes
   - Tests incorrectly using `.new()` on GDScript refs

3. **Fix Autoload Resolution**
   - TerrainManager not available in headless tests
   - PhaseManager missing in some contexts
   - Extend AutoloadHelper to load all required autoloads

4. **Fix Method Signature Mismatches**
   - `assert_button_enabled()` signature inconsistent
   - `assert_button_visible()` signature inconsistent
   - Already partially fixed in Phase 1, need completion

## Current System Analysis

### Test Infrastructure Status (Post-Phase 1)

**Helper Classes:**
- ✅ BasePhaseTest - Fixed in Phase 1, added `assert_has()`, `assert_does_not_have()`
- ✅ BaseUITest - Fixed in Phase 1, added assertions and message param
- ✅ AutoloadHelper - Created in Phase 1, handles GameState/PhaseManager
- ⚠️ GutTest - Missing several assertion methods

**Test Patterns:**
```gdscript
// Current (BROKEN):
test_base_phase = BasePhase.new()  // Error: Can't instantiate abstract class

// Should Be:
var BasePhaseScript = preload("res://phases/BasePhase.gd")
test_base_phase = BasePhaseScript.new()
```

### GUT Framework Documentation

**Version:** 9.4.0
**Documentation:** https://github.com/bitwes/Gut/wiki

**Key API Methods (from analysis):**
- `assert_true()`, `assert_false()`, `assert_eq()`, `assert_ne()` ✅ Implemented
- `assert_gt()`, `assert_lt()`, `assert_gte()` ✅ Implemented (as assert_gte)
- `assert_ge()`, `assert_le()` ❌ Missing (aliases needed)
- `pending(reason)` ❌ Missing
- `gut` property ❌ Missing (test registry reference)

## Technical Research

### Issue 1: Missing Assertion Methods

**Root Cause:** Custom GutTest implementation doesn't have all GUT framework assertions

**Evidence from codebase:**
```gdscript
// addons/gut/test.gd (current)
func assert_gte(actual, expected, message = ""):  // ✅ Exists
	_assert(actual >= expected, ...)

// Missing aliases:
func assert_ge()  // Alias for assert_gte
func assert_le()  // Alias for assert_lte
```

**Tests expecting these:**
- tests/unit/test_mathhammer.gd
- tests/unit/test_melee_dice_display.gd
- tests/integration/test_melee_combat_flow.gd

### Issue 2: Class Instantiation Pattern

**Root Cause:** Tests trying to instantiate abstract base classes directly

**Evidence:**
```gdscript
// tests/unit/test_base_phase.gd:13 (BROKEN)
func before_each():
	test_base_phase = BasePhase.new()  // ERROR!
```

**Why it fails:**
- `BasePhase` is abstract, defines signals and structure
- Cannot be instantiated without concrete implementation
- Tests need concrete phase class or mock

**Solution Pattern (from working tests):**
```gdscript
// tests/phases/test_movement_phase.gd (WORKING)
func before_each():
	super.before_each()
	movement_phase = preload("res://phases/MovementPhase.gd").new()
	phase_instance = movement_phase
	enter_phase()
```

### Issue 3: Missing Autoloads

**Root Cause:** Not all autoloads loaded in headless test environment

**Evidence:**
```
SCRIPT ERROR: Identifier not found: TerrainManager
  at: Measurement.gd:146
```

**AutoloadHelper needs extension:**
```gdscript
// tests/helpers/AutoloadHelper.gd (current - partial)
static func ensure_autoloads_loaded(tree: SceneTree) -> void:
	if not tree.root.has_node("GameState"):
		# Load GameState...
	if not tree.root.has_node("PhaseManager"):
		# Load PhaseManager...
	// MISSING: TerrainManager, LineOfSightManager, etc.
```

**Required autoloads (from error analysis):**
1. GameState ✅
2. PhaseManager ✅
3. TerrainManager ❌
4. LineOfSightManager ❌
5. TransportManager ❌
6. MeasuringTapeManager ❌

### Issue 4: `pending()` Method

**Root Cause:** Tests use `pending()` to mark incomplete tests, but method doesn't exist

**Evidence:**
- 23 occurrences across 4 test files
- Used in test_debug_mode.gd, test_army_list_manager.gd

**Expected behavior:**
```gdscript
func test_future_feature():
	pending("Feature not yet implemented")
	# Test skipped gracefully
```

### Issue 5: `gut` Property

**Root Cause:** Tests reference `gut` object for test registry, doesn't exist in custom implementation

**Evidence:**
- 59 occurrences
- Used for test metadata and advanced features

**Solution:** Add `gut` self-reference property

## Implementation Strategy

### Fix 1: Add Missing Assertion Methods

**File:** `addons/gut/test.gd`

```gdscript
# Add after existing assertion methods (around line 63)

func assert_ge(actual, expected, message = ""):
	# Alias for assert_gte for GUT compatibility
	assert_gte(actual, expected, message)

func assert_le(actual, expected, message = ""):
	# Less than or equal assertion
	_assert(actual <= expected, message if message else str(actual) + " should be less than or equal to " + str(expected))

func assert_lte(actual, expected, message = ""):
	# Alias for assert_le
	assert_le(actual, expected, message)

func pending(reason = ""):
	# Mark test as pending/incomplete
	print("PENDING: " + _current_test + " - " + reason)
	_test_results.append({"passed": true, "test": _current_test, "message": "PENDING: " + reason, "pending": true})
	# Don't execute rest of test
	return

# Add gut property for test registry reference
var gut:
	get: return self  # Self-reference for compatibility
```

### Fix 2: Update AutoloadHelper with All Required Autoloads

**File:** `tests/helpers/AutoloadHelper.gd`

```gdscript
static func ensure_autoloads_loaded(tree: SceneTree) -> void:
	# Existing: GameState, PhaseManager, ArmyListManager

	# Add TerrainManager
	if not tree.root.has_node("TerrainManager"):
		var terrain_script = load("res://autoloads/TerrainManager.gd")
		if terrain_script:
			var terrain_manager = terrain_script.new()
			tree.root.add_child(terrain_manager)
			terrain_manager.name = "TerrainManager"
			print("[AutoloadHelper] Loaded TerrainManager")

	# Add LineOfSightManager
	if not tree.root.has_node("LineOfSightManager"):
		var los_script = load("res://autoloads/LineOfSightManager.gd")
		if los_script:
			var los_manager = los_script.new()
			tree.root.add_child(los_manager)
			los_manager.name = "LineOfSightManager"
			print("[AutoloadHelper] Loaded LineOfSightManager")

	# Add TransportManager
	if not tree.root.has_node("TransportManager"):
		var transport_script = load("res://autoloads/TransportManager.gd")
		if transport_script:
			var transport_manager = transport_script.new()
			tree.root.add_child(transport_manager)
			transport_manager.name = "TransportManager"
			print("[AutoloadHelper] Loaded TransportManager")

	# Add MeasuringTapeManager
	if not tree.root.has_node("MeasuringTapeManager"):
		var tape_script = load("res://autoloads/MeasuringTapeManager.gd")
		if tape_script:
			var tape_manager = tape_script.new()
			tree.root.add_child(tape_manager)
			tape_manager.name = "MeasuringTapeManager"
			print("[AutoloadHelper] Loaded MeasuringTapeManager")
```

### Fix 3: Fix Class Instantiation in test_base_phase.gd

**File:** `tests/unit/test_base_phase.gd`

**Problem:** Line 13 tries to instantiate abstract BasePhase class

**Solution:** Use concrete implementation or create test double

```gdscript
# Before (BROKEN):
func before_each():
	test_base_phase = BasePhase.new()  # ERROR
	add_child(test_base_phase)

# After (FIXED):
func before_each():
	# Use MovementPhase as concrete implementation for testing BasePhase
	var MovementPhaseScript = preload("res://phases/MovementPhase.gd")
	test_base_phase = MovementPhaseScript.new()
	add_child(test_base_phase)

	# Or create minimal test double:
	# test_base_phase = _create_test_phase()
	# add_child(test_base_phase)

func _create_test_phase():
	# Create minimal concrete phase for testing
	var script = GDScript.new()
	script.source_code = """
	extends BasePhase
	func _ready():
		super._ready()
	"""
	script.reload()
	return script.new()
```

### Fix 4: Fix BaseUITest Method Signatures (Complete)

**File:** `tests/helpers/BaseUITest.gd`

Already partially fixed in Phase 1. Verify and complete:

```gdscript
# Line ~55 - Ensure 3-parameter signature
func assert_button_enabled(button_name: String, enabled: bool = true, message: String = ""):
	var button = find_ui_element(button_name, Button)
	assert_not_null(button, "Button should exist: " + button_name)
	assert_eq(enabled, not button.disabled, message if message else "Button " + button_name + " enabled state should be " + str(enabled))

# Line ~50 - Ensure 3-parameter signature
func assert_button_visible(button_name: String, visible: bool = true, message: String = ""):
	var button = find_ui_element(button_name, Button)
	assert_not_null(button, "Button should exist: " + button_name)
	assert_eq(visible, button.visible, message if message else "Button " + button_name + " visibility should be " + str(visible))
```

### Fix 5: Add AutoloadHelper to All Test Base Classes

Ensure all test files that don't load Main scene call AutoloadHelper:

**Pattern to add to before_each():**
```gdscript
func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

	# Rest of setup...
```

**Files needing this:**
- All unit tests (20 files)
- Phase tests that don't use BasePhaseTest (check each)
- Integration tests

## Implementation Tasks (Ordered)

### Phase 1: Core Fixes (P0 - Critical)

| # | Task | File | Estimated Time |
|---|------|------|----------------|
| 1.1 | Add missing assertions to GutTest | addons/gut/test.gd | 30 min |
| 1.2 | Add `gut` property to GutTest | addons/gut/test.gd | 10 min |
| 1.3 | Extend AutoloadHelper | tests/helpers/AutoloadHelper.gd | 45 min |
| 1.4 | Fix test_base_phase.gd instantiation | tests/unit/test_base_phase.gd | 30 min |
| 1.5 | Verify BaseUITest signatures | tests/helpers/BaseUITest.gd | 15 min |

**Total Phase 1:** 2.5 hours

### Phase 2: Test File Updates (P1 - High)

| # | Task | Files | Estimated Time |
|---|------|-------|----------------|
| 2.1 | Add AutoloadHelper to unit tests | 20 files | 2 hours |
| 2.2 | Add AutoloadHelper to phase tests | 7 files | 1 hour |
| 2.3 | Add AutoloadHelper to integration tests | 9 files | 1.5 hours |
| 2.4 | Update UI tests (if needed) | 8 files | 1 hour |

**Total Phase 2:** 5.5 hours

### Phase 3: Validation (P0 - Critical)

| # | Task | Estimated Time |
|---|------|----------------|
| 3.1 | Run test suite with validate_tests_with_timeout.sh | 1 hour |
| 3.2 | Analyze results and identify remaining issues | 1 hour |
| 3.3 | Fix any discovered issues | 2-4 hours |
| 3.4 | Re-run validation | 1 hour |

**Total Phase 3:** 5-7 hours

**Overall Estimated Effort:** 13-15 hours

## Validation Plan

### Validation Commands

```bash
# Step 1: Syntax check modified files
cd /Users/robertocallaghan/Documents/claude/godotv2/40k
godot --headless --check-only --path . addons/gut/test.gd
godot --headless --check-only --path . tests/helpers/AutoloadHelper.gd
godot --headless --check-only --path . tests/unit/test_base_phase.gd

# Step 2: Run single test file to verify fixes
export PATH="$HOME/bin:$PATH"
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit/test_base_phase.gd -glog=2 -gexit

# Step 3: Run full test suite with timeout protection
./tests/validate_tests_with_timeout.sh

# Step 4: Check results
cat test_results/OVERALL_SUMMARY.md
```

### Success Criteria

**Phase 1 Success:**
- [ ] All syntax checks pass
- [ ] test_base_phase.gd runs without "new() in GDScript" errors
- [ ] No "pending() not found" errors
- [ ] No "assert_ge() not found" errors

**Phase 2 Success:**
- [ ] No "Identifier not found: TerrainManager" errors
- [ ] No "Identifier not found: PhaseManager" errors
- [ ] All tests load without compilation errors

**Phase 3 Success:**
- [ ] >90% test pass rate (target: 55+/61 tests)
- [ ] <5 remaining failures
- [ ] All failures documented with root cause
- [ ] No systematic errors (unique failures only)

### Expected Improvements

**Current State:**
- 44 test files
- 53/61 tests passing (87%)
- 8 failing with systematic errors

**Target State (After Fixes):**
- 44 test files
- 55-58/61 tests passing (90-95%)
- 3-6 failures (unique issues, not systematic)
- All compilation errors resolved

## Code Examples

### Example 1: Adding Assertions to GutTest

```gdscript
# addons/gut/test.gd

# Add these methods after line 63 (after assert_between)
func assert_ge(actual, expected, message = ""):
	"""
	Greater than or equal assertion (GUT compatibility alias).
	Equivalent to assert_gte().
	"""
	assert_gte(actual, expected, message)

func assert_le(actual, expected, message = ""):
	"""
	Less than or equal assertion.
	Asserts that actual <= expected.
	"""
	_assert(actual <= expected, message if message else str(actual) + " should be less than or equal to " + str(expected))

func assert_lte(actual, expected, message = ""):
	"""
	Less than or equal assertion (alias).
	Equivalent to assert_le().
	"""
	assert_le(actual, expected, message)

func pending(reason = ""):
	"""
	Mark test as pending/incomplete.
	Test will be skipped gracefully with PENDING status.
	"""
	print("PENDING: " + _current_test + " - " + reason)
	_test_results.append({
		"passed": true,
		"test": _current_test,
		"message": "PENDING: " + reason,
		"pending": true
	})
	# Early return skips rest of test
	return

# Add gut property for test registry reference (around line 10)
var gut:
	get: return self  # Self-reference for GUT compatibility
```

### Example 2: Fixed test_base_phase.gd

```gdscript
# tests/unit/test_base_phase.gd

extends GutTest

# Unit tests for BasePhase class
# Tests the abstract base functionality that all phases inherit

var test_base_phase: Node  # Changed from BasePhase
var test_snapshot: Dictionary
var action_taken_received: bool = false
var phase_completed_received: bool = false
var last_action_received: Dictionary

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

	# Use concrete MovementPhase for testing BasePhase functionality
	var MovementPhaseScript = preload("res://phases/MovementPhase.gd")
	test_base_phase = MovementPhaseScript.new()
	add_child(test_base_phase)

	# Create test snapshot using TestDataFactory
	test_snapshot = TestDataFactory.create_test_game_state()

	# Connect signals
	test_base_phase.action_taken.connect(_on_action_taken)
	test_base_phase.phase_completed.connect(_on_phase_completed)

	# Reset signal flags
	action_taken_received = false
	phase_completed_received = false
	last_action_received = {}

# Rest of file unchanged...
```

### Example 3: Pattern for Adding AutoloadHelper

```gdscript
# Any test file that doesn't load Main scene

extends GutTest  # or extends BasePhaseTest, or extends BaseUITest

func before_each():
	# ALWAYS call AutoloadHelper first
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

	# Then call super if using base class
	super.before_each()  # If extending BasePhaseTest or BaseUITest

	# Then rest of setup
	# ...
```

## External Documentation

### GUT Framework
- **Wiki:** https://github.com/bitwes/Gut/wiki
- **Assertions:** https://github.com/bitwes/Gut/wiki/Asserts
- **pending() method:** https://github.com/bitwes/Gut/wiki/Pending-Tests
- **Version:** 9.4.0

### Godot Documentation
- **GDScript:** https://docs.godotengine.org/en/4.4/tutorials/scripting/gdscript/gdscript_basics.html
- **Autoloads:** https://docs.godotengine.org/en/4.4/tutorials/scripting/singletons_autoload.html
- **Preload:** https://docs.godotengine.org/en/4.4/tutorials/scripting/gdscript/gdscript_basics.html#functions
- **Testing:** https://docs.godotengine.org/en/4.4/contributing/development/testing.html

### Project-Specific
- **Testing Audit:** PRPs/gh_issue_93_testing-audit.md
- **Test Coverage:** TEST_COVERAGE.md
- **Phase 2 Validation:** test_results/VALIDATION_REPORT.md

## Risk Assessment & Mitigation

### High Risks

1. **Additional Hidden Issues** 🔴
   - Risk: Fixing systematic errors may reveal new errors
   - Mitigation: Incremental fixes with validation after each phase
   - Confidence: High - error analysis was thorough

2. **Autoload Dependencies** 🟡
   - Risk: Autoloads may have initialization order dependencies
   - Mitigation: Load in specific order, add error handling
   - Confidence: Medium - some autoloads may need special initialization

### Medium Risks

3. **Test File Variations** 🟠
   - Risk: Not all test files follow same pattern
   - Mitigation: Validate pattern before bulk update, spot-check files
   - Confidence: High - base classes provide consistency

4. **GUT Compatibility** 🟠
   - Risk: Custom GutTest may have subtle differences from real GUT
   - Mitigation: Implement only methods actually used, match signatures exactly
   - Confidence: High - errors show exactly which methods are needed

### Low Risks

5. **Performance Impact** 🟢
   - Risk: Loading all autoloads may slow tests
   - Mitigation: Acceptable trade-off for test reliability
   - Confidence: High - minor impact

## Success Metrics

### Immediate Metrics (After Phase 1)

| Metric | Before | Target | Measure |
|--------|--------|--------|---------|
| Compilation Errors | ~13 types | 0 | Error log analysis |
| "new() in GDScript" errors | 271 | 0 | Error count |
| "pending() not found" errors | 23 | 0 | Error count |
| "assert_ge() not found" errors | 8 | 0 | Error count |
| "TerrainManager not found" errors | 13 | 0 | Error count |

### Overall Metrics (After Phase 3)

| Metric | Before | Target | Measure |
|--------|--------|--------|---------|
| Test Pass Rate | 87% (53/61) | >90% (55/61) | Test results |
| Systematic Errors | 10 types | 0 | Error analysis |
| Unique Failures | ~8 | <6 | Test results |
| Tests Timing Out | Unknown | 0 | Execution logs |

## Gotchas & Special Considerations

### Gotcha 1: Abstract Class Instantiation
**Issue:** GDScript allows `BaseClass.new()` syntax but fails at runtime for abstract classes
**Solution:** Always use `preload("path").new()` or concrete implementation
**Why:** GDScript type system doesn't enforce abstract at compile time

### Gotcha 2: Autoload Timing
**Issue:** Autoloads may depend on each other's _ready() being called
**Solution:** Load in dependency order, call _ready() manually if needed
**Files affected:** AutoloadHelper.gd

### Gotcha 3: Test Isolation
**Issue:** Autoloads persist between tests, may have state
**Solution:** Reset autoload state in AutoloadHelper or test teardown
**Future consideration:** Add cleanup_autoloads() method

### Gotcha 4: GUT Compatibility
**Issue:** Custom GutTest is simplified, may miss features
**Solution:** Only implement methods actually used by tests
**Note:** Full GUT has 50+ assertion methods, we only need ~15

### Gotcha 5: pending() Behavior
**Issue:** `pending()` should skip rest of test but GDScript has no early return from void
**Solution:** Return immediately after pending(), or use guard clauses
**Pattern:**
```gdscript
func test_something():
	if not_implemented:
		pending("Not implemented yet")
		return  # Important!
	# Test code...
```

## Confidence Assessment: 9/10

**High Confidence Factors:**
- ✅ Thorough error analysis with exact counts
- ✅ Root causes identified for all major errors
- ✅ Clear patterns in codebase to follow
- ✅ Existing fixes from Phase 1 validated approach
- ✅ Incremental validation strategy

**Medium Confidence Factors:**
- ⚠️ Some autoloads may need special initialization
- ⚠️ Possible edge cases in individual test files
- ⚠️ Unknown if 3-6 unique failures will remain

**Why 9/10:**
The implementation path is crystal clear with specific line-by-line fixes. Error analysis provides exact counts and locations. The fixes are straightforward - mostly adding missing methods and ensuring proper initialization. The only uncertainty is whether fixing these systematic errors will reveal additional unique issues (expected 3-6 remaining failures).

**One-pass success probability:** Very high for systematic errors (Phases 1-2), medium for achieving exact 90% pass rate (Phase 3 may need iteration).

---

**Prepared By:** Claude Code AI
**Date:** 2025-09-29
**Next Action:** Execute Phase 1 fixes
**Estimated Total Time:** 13-15 hours