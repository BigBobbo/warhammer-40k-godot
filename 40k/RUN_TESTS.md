# How to Run Tests - Quick Guide

## 🚀 Running the Deployment Test

### Option 1: Command Line (Fastest)

```bash
# Navigate to the project
cd /path/to/warhammer-40k-godot/40k

# Set PATH if needed (per CLAUDE.md)
export PATH="$HOME/bin:$PATH"

# Run the deployment test
godot --headless --script addons/gut/gut_cmdln.gd \
  -gtest=res://tests/integration/test_full_gameplay_sequence.gd \
  -gunit_test_name=test_complete_deployment_phase
```

### Option 2: Godot Editor GUI (Visual)

1. **Open Godot Editor**
   ```bash
   cd /path/to/warhammer-40k-godot/40k
   godot
   ```

2. **Open GUT Panel**
   - Look at the bottom panel tabs
   - Click on "GUT" tab
   - If you don't see it, go to: `Project → Tools → GUT`

3. **Find the Test**
   - In the GUT panel, you'll see a file tree
   - Navigate to: `tests/integration/test_full_gameplay_sequence.gd`
   - Expand it to see individual test methods

4. **Run the Test**
   - Click the "Run" button next to `test_complete_deployment_phase`
   - Watch the test execute in real-time
   - Results appear in the GUT output panel

### Option 3: Run All Integration Tests

```bash
cd /path/to/warhammer-40k-godot/40k
godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests/integration
```

---

## 📋 Running Other Tests

### Run Specific Test File
```bash
# Deployment test
godot --headless --script addons/gut/gut_cmdln.gd \
  -gtest=res://tests/integration/test_full_gameplay_sequence.gd

# Multiplayer test
godot --headless --script addons/gut/gut_cmdln.gd \
  -gtest=res://tests/network/test_multiplayer_gameplay.gd

# Model dragging test
godot --headless --script addons/gut/gut_cmdln.gd \
  -gtest=res://tests/ui/test_model_dragging.gd
```

### Run All Tests in a Category
```bash
# All integration tests
godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests/integration

# All UI tests
godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests/ui

# All network tests
godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests/network

# All unit tests
godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests/unit

# All phase tests
godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests/phases
```

### Run ALL Tests
```bash
godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests
```

---

## 🔍 Understanding Test Output

### Success Output
```
===============================
test_complete_deployment_phase
===============================
+ test_complete_deployment_phase
  PASSED

===============================
Tests finished
===============================
Totals:  1 run  1 passed  0 failed  0 pending  0 orphans
```

### Failure Output
```
===============================
test_complete_deployment_phase
===============================
- test_complete_deployment_phase
  FAILED:  Button should exist: ConfirmDeploymentButton
    at line 44 in test_complete_deployment_phase

===============================
Tests finished
===============================
Totals:  1 run  0 passed  1 failed  0 pending  0 orphans
```

---

## 🐛 Debugging Tests

### Run with Verbose Output
```bash
godot --headless --script addons/gut/gut_cmdln.gd \
  -gtest=res://tests/integration/test_full_gameplay_sequence.gd \
  -gunit_test_name=test_complete_deployment_phase \
  -glog=2
```

### Run with GUI (See What's Happening)
Remove `--headless` to watch the test execute:
```bash
godot --script addons/gut/gut_cmdln.gd \
  -gtest=res://tests/integration/test_full_gameplay_sequence.gd \
  -gunit_test_name=test_complete_deployment_phase
```

### Add Print Statements
Edit the test file and add debug prints:
```gdscript
func test_complete_deployment_phase():
    print("Starting deployment test...")
    transition_to_phase(GameStateData.Phase.DEPLOYMENT)
    print("Transitioned to deployment phase")

    select_unit_from_list(0)
    print("Selected first unit")

    # ... rest of test
```

---

## ⚙️ Customizing the Test

### Test with Different Units

Edit `tests/integration/test_full_gameplay_sequence.gd`:

```gdscript
func before_each():
    super.before_each()

    # Option 1: Use test data (default)
    var test_state = TestDataFactory.create_test_game_state()

    # Option 2: Load actual army list
    # var test_state = load_army_list("res://armies/my_space_marines.json")

    if Engine.has_singleton("GameState"):
        var game_state = Engine.get_singleton("GameState")
        game_state.load_from_snapshot(test_state)
```

### Test Specific Deployment Positions

Modify the positions in the test:
```gdscript
# Change these to match your deployment zone
var deployment_positions = [
    Vector2(200, 200),  # Adjust these coordinates
    Vector2(220, 200),
    Vector2(240, 200),
    Vector2(200, 220),
    Vector2(220, 220)
]
```

---

## 🎯 Quick Test Commands

Copy-paste these for quick testing:

```bash
# Set working directory
cd /home/user/warhammer-40k-godot/40k

# Test deployment only
godot --headless --script addons/gut/gut_cmdln.gd \
  -gtest=res://tests/integration/test_full_gameplay_sequence.gd \
  -gunit_test_name=test_complete_deployment_phase

# Test full turn sequence
godot --headless --script addons/gut/gut_cmdln.gd \
  -gtest=res://tests/integration/test_full_gameplay_sequence.gd \
  -gunit_test_name=test_complete_turn_sequence

# Test movement phase
godot --headless --script addons/gut/gut_cmdln.gd \
  -gtest=res://tests/integration/test_full_gameplay_sequence.gd \
  -gunit_test_name=test_complete_movement_phase

# Test shooting phase
godot --headless --script addons/gut/gut_cmdln.gd \
  -gtest=res://tests/integration/test_full_gameplay_sequence.gd \
  -gunit_test_name=test_complete_shooting_phase
```

---

## ❓ Troubleshooting

### "godot: command not found"
```bash
# Add Godot to PATH
export PATH="$HOME/bin:$PATH"

# Or use full path
/path/to/godot --headless --script addons/gut/gut_cmdln.gd ...
```

### "Cannot find scene res://scenes/Main.tscn"
```bash
# Import the project first
godot --headless --import
```

### Tests hang or timeout
- Increase timeout in `.gutconfig.json`
- Check for infinite loops in game code
- Run without `--headless` to see what's happening

### No output
- Remove `--headless` to see GUI
- Add `-glog=2` for verbose output
- Check that test file exists

---

## 📚 More Information

- Full testing guide: `TESTING.md`
- Test examples: `tests/` directory
- GUT documentation: https://github.com/bitwes/Gut

---

**Ready to test!** Start with the deployment test using Option 1 or 2 above.
