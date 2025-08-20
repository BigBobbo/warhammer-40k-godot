# PRP: Automated Testing Implementation for Warhammer 40k Godot Game

## Executive Summary

Implement comprehensive automated testing using GUT (Godot Unit Testing) framework to ensure existing functionality remains intact as new phases are added. The testing suite will cover unit tests, integration tests, UI interaction tests with mouse simulation, and regression tests.

## Context and Research Findings

### Current Testing State
The codebase currently has basic testing with:
- `tests/ModularSystemValidator.gd` - System validation tests (516 lines)
- `tests/MovementPhaseTest.gd` - Movement phase specific tests (100+ lines)
- Manual testing approach with comprehensive system checks

### Framework Selection: GUT 9.4.0
**Primary Choice: GUT (Godot Unit Testing)**
- **Documentation**: https://gut.readthedocs.io/en/latest/
- **GitHub**: https://github.com/bitwes/Gut
- **Godot 4.4 Compatible**: GUT 9.4.0 supports Godot 4.4
- **Asset Library**: https://godotengine.org/asset-library/asset/1709

**Why GUT over alternatives:**
- **WAT**: Not compatible with Godot 4 (deprecated)
- **gdUnit4**: More complex setup, primarily C# focused
- **GUT**: Active maintenance, GDScript native, extensive documentation

### Key GUT Features for This Project
- Mouse input simulation: `simulate_mouse_button_pressed()`, `simulate_mouse_button_press()`
- Scene runner for UI testing: `scene_runner("res://scenes/Main.tscn")`
- Extensive assertion library: `assert_true()`, `assert_eq()`, `assert_almost_eq()`
- Doubles and mocking support for isolation testing
- JUnit XML export for CI/CD integration

## Technical Architecture

### Existing Code Patterns to Follow

**Phase Testing Pattern** (from `tests/MovementPhaseTest.gd`):
```gdscript
extends Node

var test_results: Array = []
var phase: MovementPhase
var test_state: Dictionary

func setup_test_environment() -> void:
    phase = MovementPhase.new()
    test_state = {
        "meta": {"game_id": "test-game", "turn_number": 1},
        "units": {...}
    }
```

**System Validation Pattern** (from `tests/ModularSystemValidator.gd`):
```gdscript
func run_test(test_name: String) -> void:
    var result = {"passed": false, "message": "", "details": {}}
    match test_name:
        "test_specific_feature":
            result = test_specific_feature()
    
    validation_results.test_results[test_name] = result
```

**Action Testing Pattern** (from `phases/BasePhase.gd`):
```gdscript
func execute_action(action: Dictionary) -> Dictionary:
    var validation = validate_action(action)
    if not validation.valid:
        return {"success": false, "errors": validation.errors}
    
    var result = process_action(action)
    # Apply state changes and emit signals
```

### Mouse Input Testing Implementation

**GUT Mouse Simulation Example**:
```gdscript
func test_model_drag_movement():
    var runner = scene_runner("res://scenes/Main.tscn")
    
    # Setup: Select unit first
    var unit_list = runner.get_scene().find_child("UnitListPanel")
    runner.simulate_action_input("ui_accept") # Select first unit
    await await_input_processed()
    
    # Simulate drag operation
    runner.set_mouse_position(Vector2(400, 400)) # Model position
    runner.simulate_mouse_button_press(MOUSE_BUTTON_LEFT)
    await await_input_processed()
    
    runner.set_mouse_position(Vector2(500, 400)) # Drag destination
    runner.simulate_mouse_button_release(MOUSE_BUTTON_LEFT)
    await await_input_processed()
    
    # Verify model moved
    var unit = GameState.get_unit("test_unit_id")
    var model_pos = unit.models[0].position
    assert_almost_eq(model_pos.x, 500, 10, "Model should move to drag position")
```

## Implementation Blueprint

### Directory Structure
```
40k/
├── tests/
│   ├── unit/
│   │   ├── test_base_phase.gd
│   │   ├── test_game_state.gd
│   │   ├── test_phase_manager.gd
│   │   └── test_measurement.gd
│   ├── phases/
│   │   ├── test_deployment_phase.gd
│   │   ├── test_movement_phase.gd
│   │   ├── test_shooting_phase.gd
│   │   ├── test_charge_phase.gd
│   │   ├── test_fight_phase.gd
│   │   └── test_morale_phase.gd
│   ├── integration/
│   │   ├── test_phase_transitions.gd
│   │   ├── test_save_load_system.gd
│   │   └── test_action_flow.gd
│   ├── ui/
│   │   ├── test_mouse_interactions.gd
│   │   ├── test_button_functionality.gd
│   │   ├── test_unit_selection.gd
│   │   └── test_movement_controller.gd
│   ├── helpers/
│   │   ├── BasePhaseTest.gd
│   │   ├── BaseUITest.gd
│   │   └── TestDataFactory.gd
│   └── test_runner.cfg
```

### Base Test Classes

**BasePhaseTest.gd**:
```gdscript
extends GutTest
class_name BasePhaseTest

var phase_instance
var test_state: Dictionary

func before_each():
    test_state = TestDataFactory.create_test_game_state()
    setup_phase_instance()

func setup_phase_instance():
    # Override in subclasses
    pass

func assert_valid_action(action: Dictionary, message: String = ""):
    var result = phase_instance.validate_action(action)
    assert_true(result.valid, message if message else "Action should be valid: " + str(action))

func assert_invalid_action(action: Dictionary, message: String = ""):
    var result = phase_instance.validate_action(action)
    assert_false(result.valid, message if message else "Action should be invalid: " + str(action))
```

**BaseUITest.gd**:
```gdscript
extends GutTest
class_name BaseUITest

var scene_runner
var main_scene

func before_each():
    scene_runner = scene_runner("res://scenes/Main.tscn")
    main_scene = scene_runner.get_scene()
    await wait_for_signal(main_scene.ready, 2)

func after_each():
    scene_runner.queue_free()

func click_button(button_name: String):
    var button = main_scene.find_child(button_name)
    assert_not_null(button, "Button should exist: " + button_name)
    
    var button_pos = button.global_position + button.size / 2
    scene_runner.set_mouse_position(button_pos)
    scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
    await await_input_processed()

func drag_model(from_pos: Vector2, to_pos: Vector2):
    scene_runner.set_mouse_position(from_pos)
    scene_runner.simulate_mouse_button_press(MOUSE_BUTTON_LEFT)
    await await_input_processed()
    
    scene_runner.set_mouse_position(to_pos)
    scene_runner.simulate_mouse_button_release(MOUSE_BUTTON_LEFT)
    await await_input_processed()
```

## Task Implementation Order

### Phase 1: Foundation Setup
1. **Install GUT Framework**
   - Download from Asset Library: https://godotengine.org/asset-library/asset/1709
   - Configure in `project.godot`
   - Create test directory structure

2. **Create Base Test Infrastructure**
   - `BasePhaseTest.gd` - Common phase testing utilities
   - `BaseUITest.gd` - UI testing helpers with mouse simulation
   - `TestDataFactory.gd` - Generate consistent test game states

### Phase 2: Core Unit Tests
3. **Test Autoload Systems**
   - `test_game_state.gd` - GameState functionality
   - `test_phase_manager.gd` - Phase transitions
   - `test_measurement.gd` - Distance calculations

4. **Test Base Phase Functionality**
   - `test_base_phase.gd` - Abstract phase interface
   - Action validation framework
   - State snapshot handling

### Phase 3: Phase-Specific Tests
5. **Movement Phase Tests** (extend existing)
   - Convert `MovementPhaseTest.gd` to GUT format
   - Add comprehensive action testing
   - Test movement restrictions and validation

6. **Deployment Phase Tests**
   - Unit placement validation
   - Deployment zone restrictions
   - Model positioning rules

7. **Remaining Phase Tests**
   - Shooting, Charge, Fight, Morale phases
   - Stub testing for unimplemented phases
   - Action availability testing

### Phase 4: UI and Integration Tests
8. **Mouse Interaction Tests**
   - Model drag and drop simulation
   - Click position accuracy
   - Multi-model selection

9. **Button Functionality Tests**
   - Movement buttons (Undo, Reset, Confirm)
   - Phase transition buttons
   - UI state consistency

10. **Integration Tests**
    - Full game flow testing
    - Save/load system validation
    - Phase transition sequences

### Phase 5: CI/CD and Documentation
11. **GitHub Actions Integration**
    - Automated test execution
    - Test result reporting
    - Coverage tracking

12. **Documentation**
    - Test writing guidelines
    - Running tests locally
    - Contribution guidelines

## Validation Gates

### Local Testing
```bash
# Run all tests
godot --headless --script res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit

# Run specific test suite
godot --headless --script res://addons/gut/gut_cmdln.gd -gtest=res://tests/phases/test_movement_phase.gd -gexit

# Run with XML output for CI
godot --headless --script res://addons/gut/gut_cmdln.gd -gdir=res://tests -gxmlfile=res://test_results.xml -gexit

# Run tests with specific pattern
godot --headless --script res://addons/gut/gut_cmdln.gd -gdir=res://tests -gpattern="*movement*" -gexit
```

### CI/CD Integration
```yaml
# .github/workflows/test.yml
name: Run Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    container:
      image: barichello/godot-ci:4.4
    
    steps:
    - uses: actions/checkout@v3
    - name: Run Tests
      run: |
        cd 40k
        godot --headless --script res://addons/gut/gut_cmdln.gd -gdir=res://tests -gxmlfile=res://test_results.xml -gexit
    
    - name: Upload Test Results
      uses: actions/upload-artifact@v3
      if: always()
      with:
        name: test-results
        path: 40k/test_results.xml
```

## Error Handling and Gotchas

### Common Issues and Solutions

**Mouse Position Accuracy**:
```gdscript
# WRONG: Using global coordinates
scene_runner.set_mouse_position(Vector2(100, 100))

# RIGHT: Account for camera and zoom
var camera = main_scene.find_child("Camera2D")
var world_pos = camera.global_position + Vector2(100, 100) * camera.zoom
scene_runner.set_mouse_position(world_pos)
```

**Async Operation Handling**:
```gdscript
# WRONG: Not waiting for processing
scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
assert_true(some_condition) # May fail due to timing

# RIGHT: Wait for input processing
scene_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_LEFT)
await await_input_processed()
assert_true(some_condition)
```

**State Isolation**:
```gdscript
# WRONG: Tests affecting each other
func test_movement():
    GameState.set_active_player(1)
    # Test logic...

func test_deployment():
    # Assumes player 1 but previous test may have changed it
    
# RIGHT: Reset state in before_each
func before_each():
    GameState.load_from_snapshot(TestDataFactory.create_clean_state())
```

## Files to Create/Reference

### New Files
1. **Test Configuration**
   - `40k/tests/test_runner.cfg` - GUT configuration
   - `40k/.gutconfig.json` - GUT settings

2. **Base Test Classes**
   - `40k/tests/helpers/BasePhaseTest.gd`
   - `40k/tests/helpers/BaseUITest.gd` 
   - `40k/tests/helpers/TestDataFactory.gd`

3. **Test Suites** (15+ files following the directory structure above)

4. **CI/CD Configuration**
   - `.github/workflows/test.yml`
   - `docs/TESTING.md`

### Files to Reference
- `40k/tests/ModularSystemValidator.gd` - Existing pattern reference
- `40k/tests/MovementPhaseTest.gd` - Phase testing pattern
- `40k/phases/BasePhase.gd` - Action validation interface
- `40k/scripts/MovementController.gd` - UI interaction patterns
- `40k/autoloads/GameState.gd` - State management patterns

## Success Criteria

### Quantitative Metrics
- **Test Coverage**: 80%+ for phase classes, 60%+ for UI controllers
- **Test Performance**: Full suite runs in < 30 seconds
- **Test Reliability**: 95%+ pass rate on clean runs
- **Regression Detection**: Catches 90%+ of introduced bugs

### Qualitative Metrics
- All existing manual tests automated
- Mouse interactions fully testable
- New developers can add tests easily
- CI/CD pipeline prevents broken deployments
- Test suite serves as living documentation

## Risk Assessment and Mitigation

### High Risk: Mouse Input Simulation Accuracy
- **Risk**: Tests pass but don't reflect real user interactions
- **Mitigation**: Test with multiple screen resolutions and zoom levels
- **Validation**: Manual verification of test scenarios

### Medium Risk: Test Suite Performance
- **Risk**: Tests become too slow, developers skip them
- **Mitigation**: Parallel test execution, selective test running
- **Monitoring**: Track test execution time trends

### Low Risk: Framework Dependency
- **Risk**: GUT framework becomes unmaintained
- **Mitigation**: Well-documented patterns allow framework migration
- **Monitoring**: Track GUT project activity and community health

## Confidence Score: 8/10

**Reasoning**: High confidence due to:
- ✅ Existing test patterns in codebase to build upon
- ✅ Well-documented, actively maintained testing framework (GUT)
- ✅ Clear mouse simulation capabilities for UI testing
- ✅ Strong understanding of codebase architecture
- ✅ Proven patterns from ModularSystemValidator

**Risk factors reducing confidence**:
- ⚠️ Mouse input testing complexity in game environments
- ⚠️ Potential timing issues with async operations

The comprehensive research, existing code patterns, and proven testing framework provide a solid foundation for one-pass implementation success.