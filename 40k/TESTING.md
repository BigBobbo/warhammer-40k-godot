# Warhammer 40k Godot Game - Testing Guide

This document provides comprehensive guidance on the automated testing framework implemented for the Warhammer 40k digital game.

## 📋 Overview

The testing framework uses **GUT 9.4.0** (Godot Unit Testing) to provide comprehensive test coverage across all game systems. Tests are organized into four main categories:

- **Unit Tests**: Core autoloads and class functionality
- **Phase Tests**: All 6 game phases (Deployment, Movement, Shooting, Charge, Fight, Morale)  
- **UI Tests**: Mouse interactions, drag-and-drop, button functionality
- **Integration Tests**: Cross-system coordination and data flow

## 🚀 Quick Start

### Running Tests Locally

```bash
# Navigate to the game directory
cd 40k

# Run all tests
godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests

# Run specific test category
godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests/unit
godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests/phases
godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests/ui
godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests/integration

# Run with XML output (for CI)
godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests -gjunit_xml_file=test_results.xml

# Run with detailed logging
godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests -glog=2
```

### GUI Test Runner

```bash
# Launch Godot with GUI test runner
cd 40k
godot
# Navigate to "Project" → "Tools" → "GUT" → "Run Tests"
```

## 🏗️ Test Architecture

### Directory Structure

```
40k/tests/
├── unit/                   # Unit tests for core systems
│   ├── test_game_state.gd       # GameState autoload tests
│   ├── test_phase_manager.gd    # PhaseManager autoload tests
│   ├── test_measurement.gd      # Measurement system tests
│   ├── test_turn_manager.gd     # TurnManager autoload tests
│   ├── test_action_logger.gd    # ActionLogger autoload tests
│   └── test_base_phase.gd       # BasePhase class tests
├── phases/                 # Game phase specific tests
│   ├── test_deployment_phase.gd  # Deployment phase tests
│   ├── test_movement_phase.gd    # Movement phase tests
│   ├── test_shooting_phase.gd    # Shooting phase tests
│   ├── test_charge_phase.gd      # Charge phase tests
│   ├── test_fight_phase.gd       # Fight phase tests
│   └── test_morale_phase.gd      # Morale phase tests
├── ui/                     # User interface tests
│   ├── test_mouse_interactions.gd # Mouse simulation tests
│   └── test_button_functionality.gd # Button interaction tests
├── integration/            # Cross-system integration tests
│   └── test_system_integration.gd # Multi-system coordination
└── helpers/                # Test utility classes
    ├── BasePhaseTest.gd         # Base class for phase tests
    ├── BaseUITest.gd            # Base class for UI tests
    └── TestDataFactory.gd       # Test data generation
```

### Base Classes

#### BasePhaseTest.gd
Base class for all phase-specific tests, providing:
- Standard phase initialization
- Game state setup and teardown
- Phase transition utilities
- Validation helpers

#### BaseUITest.gd  
Base class for UI interaction tests, providing:
- Scene runner setup
- Mouse simulation methods
- Screen coordinate conversion
- UI element interaction helpers

#### TestDataFactory.gd
Factory class for generating consistent test data:
- Game state creation
- Unit data generation
- Test scenario setup
- Mock object creation

## ✅ Writing Tests

### Basic Test Structure

```gdscript
extends GutTest

# Test class example
func before_each():
    # Setup before each test method
    pass

func after_each():
    # Cleanup after each test method
    pass

func test_example_functionality():
    # Arrange - Set up test data
    var test_value = 42
    
    # Act - Perform the action being tested
    var result = some_function(test_value)
    
    # Assert - Verify the expected outcome
    assert_eq(84, result, "Function should double the input")
```

### Phase Test Example

```gdscript
extends BasePhaseTest

func test_movement_phase_validation():
    # Setup test game state
    var test_state = TestDataFactory.create_test_game_state()
    setup_phase_test(test_state, GameStateData.Phase.MOVEMENT)
    
    # Test movement validation
    var unit = test_state.units["test_unit_1"]
    var from_pos = unit.position
    var to_pos = from_pos + Vector2(240, 0)  # 6 inches in pixels
    
    var validation = validate_movement(unit.id, from_pos, to_pos)
    assert_true(validation.valid, "6-inch movement should be valid")
```

### UI Test Example

```gdscript
extends BaseUITest

func test_model_drag_interaction():
    # Load main game scene
    var scene = load_main_scene()
    
    # Position cursor and drag model
    var from_pos = Vector2(100, 100)
    var to_pos = Vector2(340, 100)
    
    drag_model(from_pos, to_pos)
    
    # Verify model moved
    var model = find_model_at_position(to_pos)
    assert_not_null(model, "Model should be at target position")
```

### Integration Test Example

```gdscript
extends GutTest

func test_phase_transition_integration():
    # Test complete phase cycle
    var game_state = get_game_state_instance()
    var phase_manager = get_phase_manager_instance()
    
    # Start in deployment
    phase_manager.transition_to_phase(GameStateData.Phase.DEPLOYMENT)
    
    # Complete deployment and verify automatic advancement
    complete_current_phase()
    await get_tree().process_frame
    
    var current_phase = game_state.get_current_phase()
    assert_eq(GameStateData.Phase.MOVEMENT, current_phase, 
        "Should automatically advance to movement phase")
```

## 🧪 Test Categories

### Unit Tests

**Purpose**: Test individual components in isolation
- Autoload functionality
- Core class methods
- Data structures
- Utility functions

**Characteristics**:
- Fast execution
- No dependencies on other systems
- Mock external dependencies
- High code coverage

### Phase Tests  

**Purpose**: Test each game phase's complete functionality
- Phase initialization and cleanup
- Action validation rules
- State transitions
- Phase-specific business logic

**Characteristics**:
- Phase-focused testing
- Game state integration
- Rule validation
- Edge case coverage

### UI Tests

**Purpose**: Test user interface interactions
- Mouse input simulation
- Drag-and-drop functionality
- Button interactions
- Visual feedback validation

**Characteristics**:
- Scene runner usage
- Input simulation
- Visual element testing
- User workflow validation

### Integration Tests

**Purpose**: Test system coordination and data flow
- Multi-system interactions
- Signal propagation
- State synchronization
- Error handling across systems

**Characteristics**:
- Cross-system validation
- Complex scenarios
- Performance testing
- Error recovery testing

## 🎯 Testing Best Practices

### Test Naming Conventions

```gdscript
# Good test names - descriptive and specific
func test_movement_validation_rejects_excessive_distance()
func test_shooting_phase_calculates_hit_probability_correctly()
func test_deployment_zone_validation_enforces_boundaries()

# Poor test names - vague and unclear
func test_movement()
func test_validation()
func test_stuff()
```

### Assertion Best Practices

```gdscript
# Use descriptive messages
assert_eq(expected, actual, "Clear description of what should happen")
assert_true(condition, "Explanation of what condition should be true")
assert_not_null(object, "Explanation of what object should exist")

# Use appropriate assertion methods
assert_almost_eq(6.0, distance_inches, 0.1, "Distance should be approximately 6 inches")
assert_gt(health, 0, "Unit should have positive health")
assert_has_method(object, "method_name", "Object should implement required method")
```

### Test Data Management

```gdscript
# Use TestDataFactory for consistent test data
func test_unit_combat():
    var attacker = TestDataFactory.create_test_unit_1()  # Consistent data
    var defender = TestDataFactory.create_test_unit_2()  # Consistent data
    
    # Test combat resolution
    var result = resolve_combat(attacker, defender)
    assert_not_null(result, "Combat should produce a result")

# Clean up test data
func after_each():
    TestDataFactory.cleanup_test_data()
    if scene_runner:
        scene_runner.clear_scene()
```

### Error Testing

```gdscript
func test_error_handling():
    # Test invalid input handling
    var result = some_function(null)
    assert_false(result.success, "Function should handle null input gracefully")
    
    # Test edge cases
    var edge_result = some_function("")
    assert_not_null(edge_result, "Function should handle empty string")
```

## 🔧 Configuration

### .gutconfig.json

```json
{
  "dirs": ["res://tests"],
  "include_subdirs": true,
  "log_level": 1,
  "should_maximize": false,
  "should_exit": true,
  "should_exit_on_success": true,
  "junit_xml_file": "",
  "junit_xml_timestamp": false
}
```

### test_runner.cfg

```ini
[gut]
dirs=res://tests
include_subdirs=true
log_level=1
should_exit=true
should_exit_on_success=true
```

## 🚨 Troubleshooting

### Common Issues

#### Tests Not Found
```
Error: No test files found
```
**Solution**: Verify test files follow naming convention `test_*.gd` and are in the correct directories.

#### Scene Loading Failures
```
Error: Cannot load scene
```
**Solution**: 
- Ensure scene files exist and paths are correct
- Import project before running tests: `godot --headless --import`
- Check for missing dependencies

#### Memory Issues
```
Error: Out of memory or excessive object creation
```
**Solution**:
- Implement proper cleanup in `after_each()` methods
- Use `scene_runner.clear_scene()` after UI tests
- Free test objects manually if needed

#### Autoload Access Issues
```
Error: Cannot access autoload
```
**Solution**:
- Check if autoload is registered in project.godot
- Use `Engine.has_singleton()` before accessing
- Create mock instances if autoload unavailable

### Debug Techniques

#### Verbose Logging
```bash
# Enable detailed logging
godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests -glog=2
```

#### Single Test Execution
```bash
# Run specific test class
godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests -gselect="TestClassName"

# Run specific test method
godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests -gselect="TestClassName.test_method_name"
```

#### Print Debugging
```gdscript
func test_debug_example():
    var test_value = get_test_value()
    print("Debug - test_value: ", test_value)
    gut.p("GUT Debug - test_value: ", test_value)  # GUT's print method
    
    # Continue with test assertions
    assert_not_null(test_value)
```

## 📊 Test Coverage

### Current Coverage Areas

✅ **Core Systems (Unit Tests)**
- GameState autoload - 25+ test methods
- PhaseManager autoload - 20+ test methods  
- Measurement system - 15+ test methods
- TurnManager autoload - 15+ test methods
- ActionLogger autoload - 10+ test methods

✅ **Game Phases (Phase Tests)**
- Deployment Phase - Boundary validation, unit placement
- Movement Phase - Distance validation, terrain checks
- Shooting Phase - Hit calculations, line of sight
- Charge Phase - Distance rules, target validation
- Fight Phase - Combat resolution, casualty handling
- Morale Phase - Leadership tests, unit removal

✅ **User Interface (UI Tests)**
- Mouse input simulation and drag-and-drop
- Button functionality (Undo, Reset, Confirm, phase buttons)
- Scene transitions and UI state management

✅ **System Integration (Integration Tests)**
- Cross-system data flow and signal propagation
- Phase transition coordination
- State synchronization across systems
- Error handling and recovery

### Coverage Goals

- **Unit Tests**: 80%+ coverage of autoload methods
- **Phase Tests**: 100% coverage of game rule validation
- **UI Tests**: All major user interactions covered
- **Integration Tests**: Critical system boundaries tested

## 📈 Performance Testing

### Performance Test Guidelines

```gdscript
func test_performance_example():
    var start_time = Time.get_time_dict_from_system()
    
    # Perform operations being tested
    for i in range(1000):
        perform_operation()
    
    var end_time = Time.get_time_dict_from_system() 
    var elapsed = calculate_elapsed_time(start_time, end_time)
    
    # Assert performance requirements
    assert_lt(elapsed, 5.0, "Operations should complete within 5 seconds")
```

### Memory Testing

```gdscript
func test_memory_usage():
    var initial_objects = Engine.get_process_frames()
    
    # Perform operations that create/destroy objects
    create_and_destroy_objects()
    
    var final_objects = Engine.get_process_frames()
    var object_difference = final_objects - initial_objects
    
    # Verify no memory leaks
    assert_lt(object_difference, 10, "Should not leak excessive objects")
```

## 🔄 Continuous Integration

The testing framework integrates with GitHub Actions to provide:
- **Automated Testing**: All test categories on every push/PR
- **Build Verification**: Ensure project builds successfully
- **Performance Monitoring**: Track test execution times
- **Quality Gates**: Prevent merging if tests fail
- **Multi-Platform Testing**: Linux, Windows, macOS validation

See `.github/README.md` for detailed CI/CD documentation.

## 📚 Additional Resources

### GUT Framework Documentation
- [GUT GitHub Repository](https://github.com/bitwes/Gut)
- [GUT Documentation](https://bitwes.github.io/Gut/)
- [Godot Testing Best Practices](https://docs.godotengine.org/en/stable/tutorials/scripting/unit_testing.html)

### Game-Specific Resources
- `PRPs/automated-testing-implementation.md` - Complete implementation plan
- `.github/README.md` - CI/CD workflow documentation
- Game autoload source files for understanding system architecture

## 🆘 Getting Help

1. **Check test logs**: Review detailed output from test runs
2. **Examine test artifacts**: Download XML results from CI runs
3. **Review existing tests**: Look at similar test implementations
4. **Verify setup**: Ensure GUT is properly installed and configured
5. **Check project structure**: Validate directory organization and file naming

For persistent issues, review the GitHub Actions workflow logs and test result artifacts to identify specific failure points.

---

This testing framework ensures the Warhammer 40k digital game maintains quality and functionality as new features are added. Regular test execution prevents regression bugs and maintains confidence in the codebase.