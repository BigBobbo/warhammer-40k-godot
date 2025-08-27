# 📝 Human-Readable Save Files - Implementation PRP

## Problem Statement
GitHub Issue #9: "Having the save files human readable and editable will allow for easier debugging. Update the save file so it is formatted in a user readable way but ensure it is fully compatible with the existing app."

### Current State Analysis
After thorough investigation of the save system:
- **Save files are minified JSON** - Currently all on one line, hard to read/debug
- **Metadata files are already pretty-printed** - Using `JSON.stringify(metadata, "\t")`
- **Infrastructure exists** - StateSerializer has `pretty_print` property but defaults to `false`
- **Backward compatibility ready** - Deserialization already handles both formats

## Implementation Blueprint

### Solution Approach
Enable pretty-printing for save files while maintaining full backward compatibility:
1. **Enable pretty_print by default** in StateSerializer
2. **Add user setting** to control formatting preference
3. **Ensure backward compatibility** - load both minified and pretty-printed saves
4. **Update tests** to verify both formats work

### Critical Context for Implementation

#### Existing Code Architecture

1. **StateSerializer Pattern** (40k/autoloads/StateSerializer.gd:14,29-32):
```gdscript
var pretty_print: bool = false  # Current default

func serialize_game_state(state: Dictionary = {}) -> String:
    # ... preparation code ...
    if pretty_print:
        json_string = JSON.stringify(serializable_state, "\t")  # Pretty format
    else:
        json_string = JSON.stringify(serializable_state)  # Minified format
```

2. **SaveLoadManager Pattern** (40k/autoloads/SaveLoadManager.gd:139,376):
```gdscript
# Main save file (currently minified)
file.store_string(serialized_data)

# Metadata file (already pretty-printed)
var json_string = JSON.stringify(metadata, "\t")
file.store_string(json_string)
```

3. **Settings Architecture** (40k/autoloads/SettingsService.gd):
```gdscript
# Currently only has board settings
# Need to add save/load settings section
```

#### Files to Modify

1. **40k/autoloads/StateSerializer.gd** - Change default, add initialization
2. **40k/autoloads/SettingsService.gd** - Add save format settings
3. **40k/tests/integration/test_save_load.gd** - Add compatibility tests

#### External Documentation References

- **Godot 4.4 JSON Pretty Print**: https://docs.godotengine.org/en/4.4/classes/class_json.html#class-json-method-stringify
  - `JSON.stringify(data, indent)` - indent string for formatting
  - Empty string = minified, "\t" = tab indentation

- **Save Format Best Practices**: https://kidscancode.org/godot_recipes/4.x/basics/file_io/index.html
  - JSON advantages: Human-readable, easy debugging, manual editing
  - JSON limitations: Type conversion needed for complex types (already handled)

- **Backward Compatibility Pattern**: https://www.gdquest.com/tutorial/godot/best-practices/save-game-formats/
  - Version management (already implemented)
  - Flexible deserialization (already implemented)

## Tasks to Complete (In Order)

### Task 1: Add Save Format Settings to SettingsService
**File**: 40k/autoloads/SettingsService.gd
**Location**: After existing settings (line 7)

```gdscript
# Save/Load Settings
var save_files_pretty_print: bool = true  # Human-readable by default
var save_files_compression: bool = false  # Keep disabled for readability

func get_save_pretty_print() -> bool:
    return save_files_pretty_print

func set_save_pretty_print(enabled: bool) -> void:
    save_files_pretty_print = enabled
    # Update StateSerializer immediately
    if StateSerializer:
        StateSerializer.set_pretty_print(enabled)

func _ready() -> void:
    # Initialize StateSerializer with settings
    if StateSerializer:
        StateSerializer.set_pretty_print(save_files_pretty_print)
        StateSerializer.set_compression_enabled(save_files_compression)
```

### Task 2: Update StateSerializer Default and Initialization
**File**: 40k/autoloads/StateSerializer.gd
**Location**: Line 14 and add _ready() method

```gdscript
# Change default to true for human-readable saves
var pretty_print: bool = true  # Changed from false

func _ready() -> void:
    # Check if SettingsService has preferences
    if SettingsService and SettingsService.has_method("get_save_pretty_print"):
        pretty_print = SettingsService.get_save_pretty_print()
    
    print("StateSerializer: Pretty print enabled: ", pretty_print)
```

### Task 3: Add Backward Compatibility Test
**File**: 40k/tests/integration/test_save_load.gd
**Location**: After existing tests (line 100+)

```gdscript
func test_backward_compatibility_minified_to_pretty():
    # Test loading old minified saves with new pretty-print system
    if not state_serializer:
        skip_test("StateSerializer not available")
        return
    
    # Create test state
    var test_state = {
        "_serialization": {"version": "1.0.0", "timestamp": 123456},
        "meta": {"phase": 2, "turn_number": 5},
        "units": {},
        "board": {},
        "players": {}
    }
    
    # Save as minified (old format)
    state_serializer.set_pretty_print(false)
    var minified_json = state_serializer.serialize_game_state(test_state)
    assert_false(minified_json.contains("\n"), "Minified JSON should be single line")
    
    # Load with pretty-print enabled (new format)
    state_serializer.set_pretty_print(true)
    var loaded_state = state_serializer.deserialize_game_state(minified_json)
    
    assert_not_null(loaded_state, "Should load minified save with pretty-print enabled")
    assert_eq(loaded_state.meta.phase, 2, "Phase should match")
    assert_eq(loaded_state.meta.turn_number, 5, "Turn should match")

func test_forward_compatibility_pretty_to_minified():
    # Test loading new pretty saves with old minified system
    if not state_serializer:
        skip_test("StateSerializer not available")
        return
    
    # Create test state
    var test_state = {
        "_serialization": {"version": "1.0.0", "timestamp": 123456},
        "meta": {"phase": 3, "turn_number": 7},
        "units": {},
        "board": {},
        "players": {}
    }
    
    # Save as pretty-printed (new format)
    state_serializer.set_pretty_print(true)
    var pretty_json = state_serializer.serialize_game_state(test_state)
    assert_true(pretty_json.contains("\n"), "Pretty JSON should have newlines")
    assert_true(pretty_json.contains("\t"), "Pretty JSON should have tabs")
    
    # Load with pretty-print disabled (old format)
    state_serializer.set_pretty_print(false)
    var loaded_state = state_serializer.deserialize_game_state(pretty_json)
    
    assert_not_null(loaded_state, "Should load pretty save with pretty-print disabled")
    assert_eq(loaded_state.meta.phase, 3, "Phase should match")
    assert_eq(loaded_state.meta.turn_number, 7, "Turn should match")
```

### Task 4: Add Format Verification Test
**File**: 40k/tests/integration/test_save_load.gd
**Location**: After compatibility tests

```gdscript
func test_save_file_readability():
    # Verify save files are human-readable
    if not save_manager or not state_serializer:
        skip_test("Save components not available")
        return
    
    # Enable pretty print
    state_serializer.set_pretty_print(true)
    
    # Create and save game state
    game_state.set_phase(GameStateData.Phase.MOVEMENT)
    game_state.advance_turn()
    
    var test_file = "user://test_readable_" + str(Time.get_unix_time_from_system()) + ".save"
    save_manager.save_game(test_file, {"description": "Readability test"})
    
    # Read raw file content
    var file = FileAccess.open(test_file, FileAccess.READ)
    assert_not_null(file, "Should open save file")
    
    var content = file.get_as_text()
    file.close()
    
    # Verify human-readable format
    assert_true(content.contains("\n"), "Should have line breaks")
    assert_true(content.contains("\t"), "Should have indentation")
    assert_true(content.contains('"phase":'), "Should have readable keys")
    assert_true(content.contains('"turn_number":'), "Should have readable values")
    
    # Clean up
    DirAccess.remove_absolute(test_file)
```

### Task 5: Optional - Add UI Toggle for Format Preference
**File**: Create new settings UI or add to existing settings
**Location**: Optional enhancement

```gdscript
# In a settings menu script
func _on_pretty_saves_toggled(button_pressed: bool) -> void:
    SettingsService.set_save_pretty_print(button_pressed)
    
    # Show feedback
    var format = "human-readable" if button_pressed else "compact"
    print("Save format changed to: ", format)
```

## Validation Gates

```bash
# Run Godot syntax check
godot --check-only

# Run save/load integration tests
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/integration/test_save_load.gd

# Manual validation:
# 1. Save a game with the new system
# 2. Open the .w40ksave file in a text editor
# 3. Verify it's formatted with indentation and line breaks
# 4. Load the save to verify it works
# 5. Load an old minified save to verify backward compatibility
```

## Error Handling Strategy

1. **Deserialization Flexibility**: JSON parser handles both formats automatically
2. **Version Checking**: Existing version system ensures compatibility
3. **Fallback Mode**: If pretty-print causes issues, can disable via settings
4. **File Size Monitoring**: Pretty files are larger but still reasonable for game saves

## Common Pitfalls to Avoid

1. **Don't break existing saves** - Deserialization must handle both formats
2. **Consider file size** - Pretty format increases size by ~30-40%
3. **Maintain type conversion** - Vector2, etc. already handled correctly
4. **Keep compression optional** - Compression defeats readability purpose
5. **Test cross-format loading** - Minified->Pretty and Pretty->Minified

## Implementation Verification Checklist

- [ ] New saves are human-readable with proper indentation
- [ ] Old minified saves still load correctly
- [ ] Metadata files remain pretty-printed
- [ ] File size increase is acceptable (<50% larger)
- [ ] Can manually edit save files in text editor
- [ ] Tests pass for both format directions
- [ ] Setting can be toggled if needed
- [ ] No performance degradation on save/load

## Expected File Format Comparison

### Before (Minified):
```json
{"_serialization":{"version":"1.0.0","timestamp":123456},"meta":{"phase":2,"turn_number":1},"units":{"U_TACTICAL_A":{"id":"U_TACTICAL_A","models":[{"alive":true,"position":{"x":100,"y":200}}]}}}
```

### After (Human-Readable):
```json
{
	"_serialization": {
		"version": "1.0.0",
		"timestamp": 123456
	},
	"meta": {
		"phase": 2,
		"turn_number": 1
	},
	"units": {
		"U_TACTICAL_A": {
			"id": "U_TACTICAL_A",
			"models": [
				{
					"alive": true,
					"position": {
						"x": 100,
						"y": 200
					}
				}
			]
		}
	}
}
```

## Confidence Score: 9/10

High confidence due to:
- **Minimal changes required** - Just enable existing functionality
- **Infrastructure already exists** - Pretty-print code already implemented
- **Backward compatibility assured** - JSON parser handles both formats
- **Tested approach** - Metadata files already use this format
- **Clear implementation path** - Simple property change with settings

Points deducted for:
- **File size increase** - Pretty format uses more disk space

## Additional Notes

This implementation follows Godot's recommended approach using `JSON.stringify(data, "\t")` for human-readable JSON. The solution prioritizes debugging and manual editing capabilities over file size optimization, which aligns with the issue's goals.

The backward compatibility is automatic because Godot's JSON parser ignores whitespace when parsing, so both formats deserialize identically. This makes the change risk-free for existing saves.

Consider adding a user preference in the game's settings menu to let advanced users choose between "Readable (Larger files)" and "Compact (Smaller files)" formats based on their needs.