# PRP: Multiple Save States Menu System (GitHub Issue #19)

## Overview

Implement a comprehensive save/load menu system accessible via the ESC key, allowing users to create named save files, view existing saves with timestamps, and load previous game states. This feature extends the existing quicksave system with a full modal dialog interface.

**GitHub Issue:** #19 - Multiple save states  
**Priority:** Medium  
**Estimated Effort:** 2-4 hours  
**Complexity Score:** 7/10

## Context and Requirements

### User Requirements
- ESC key opens save/load menu (modal dialog)
- Text input field for naming new saves
- Save button to create new save files
- List of existing saves with Load buttons
- Timestamps on saves with user-editable names
- Uses existing save file format (.w40ksave/.meta)
- ESC key closes menu when open
- Support both saving current state and loading previous states

### Example User Flows

**Saving Flow:**
1. User presses ESC → Menu opens
2. User types save name in text field
3. User clicks "Save" button
4. Save is created and appears in saves list
5. User presses ESC → Menu closes

**Loading Flow:**
1. User presses ESC → Menu opens
2. User selects existing save from list
3. User clicks "Load" button
4. Game state loads from selected save
5. User presses ESC → Menu closes

## Current System Analysis

### Existing Save/Load Architecture

Based on codebase research, the save system has excellent architecture:

**Core Components:**
- `SaveLoadManager.gd` - High-level save/load interface with `save_game(file_name, metadata)` and `load_game(file_name)` methods
- `StateSerializer.gd` - JSON serialization/deserialization
- `GameState.gd` - Game state management
- Save format: JSON with `.w40ksave` (data) and `.meta` (metadata) files

**File Structure:**
```json
// .meta file structure (already includes user-friendly fields)
{
  "created_at": timestamp,
  "game_state": { "active_player": 1, "phase": 4, "turn": 1 },
  "save_info": {
    "description": "",      // User-editable description field
    "save_type": "manual",  // Will be "manual" for user saves
    "tags": []
  },
  "type": "manual",
  "version": "1.0.0"
}
```

**Existing Methods to Leverage:**
- `SaveLoadManager.save_game(file_name: String, metadata: Dictionary)` - Perfect for named saves
- `SaveLoadManager.load_game(file_name: String)` - Direct loading
- `SaveLoadManager.get_save_files()` - Lists all saves with metadata
- Save validation and error handling already implemented

### Current UI Patterns

The codebase uses:
- **No modal dialogs currently implemented** - This will be new
- Collapsible panels with toggle buttons as primary UI pattern
- Programmatic UI creation in controllers
- `_input()` handling in Main.gd for keyboard shortcuts
- **ESC key handling does not exist** - Needs implementation
- Signal-based communication between UI and controllers

## Implementation Blueprint

### 1. Modal Dialog System Architecture

Create a reusable modal dialog system since none exists:

```gdscript
# SaveLoadDialog.gd - New modal dialog for save/load operations
extends AcceptDialog

@onready var save_name_input: LineEdit = $VBoxContainer/SaveSection/SaveNameInput
@onready var save_button: Button = $VBoxContainer/SaveSection/SaveButton
@onready var saves_list: ItemList = $VBoxContainer/LoadSection/SavesList
@onready var load_button: Button = $VBoxContainer/LoadSection/LoadButton
@onready var delete_button: Button = $VBoxContainer/LoadSection/DeleteButton

signal save_requested(save_name: String)
signal load_requested(save_file: String)
signal delete_requested(save_file: String)

var save_files_data: Array = []  # Store save metadata for reference
```

### 2. ESC Key Handling Integration

Add ESC key support to Main.gd input handling:

```gdscript
# In Main.gd _input() method
func _input(event: InputEvent):
    # Add ESC key handling (new)
    if event.is_action_pressed("ui_cancel"):
        _toggle_save_load_menu()
        return
    
    # Existing save/load shortcuts
    if event.is_action_pressed("quick_save"):
        # ... existing code
```

### 3. UI Layout Structure

```
AcceptDialog (SaveLoadDialog)
├── VBoxContainer
    ├── Label ("Save & Load Game")
    ├── SaveSection (HBoxContainer)
    │   ├── LineEdit (save name input)
    │   └── Button ("Save")
    ├── HSeparator
    ├── LoadSection (VBoxContainer)
    │   ├── Label ("Existing Saves")
    │   ├── ScrollContainer
    │   │   └── ItemList (saves with timestamps)
    │   └── HBoxContainer
    │       ├── Button ("Load")
    │       ├── Button ("Delete") 
    │       └── Button ("Cancel")
```

### 4. Save File Naming Convention

Extend existing patterns:
- User saves: `{user_name}.w40ksave` + `{user_name}.meta`
- Default naming: `save_YYYY-MM-DD_HH-MM-SS` if no name provided
- Validate against existing names to prevent overwrites
- Store user's original name in metadata `save_info.description`

## Technical Implementation Details

### Key Integration Points

1. **Input Map Addition:**
   ```
   # Add to project.godot input map
   ui_cancel = ["escape"]
   ```

2. **SaveLoadManager Integration:**
   ```gdscript
   # Use existing methods - no changes needed to SaveLoadManager
   SaveLoadManager.save_game(save_name, {
       "save_type": "manual",
       "description": user_provided_name
   })
   
   var saves = SaveLoadManager.get_save_files()  # Returns Array of metadata
   SaveLoadManager.load_game(selected_save_name)
   ```

3. **Error Handling Pattern:**
   ```gdscript
   # Follow existing notification pattern from Main.gd
   SaveLoadManager.save_completed.connect(_on_save_completed)
   SaveLoadManager.save_failed.connect(_on_save_failed) 
   SaveLoadManager.load_completed.connect(_on_load_completed)
   SaveLoadManager.load_failed.connect(_on_load_failed)
   ```

### UI Behavior Specifications

**Modal Dialog Properties:**
- `dialog_close_on_escape = true` (built-in ESC handling)
- `exclusive = false` (allow clicking outside to close)
- Center on screen with reasonable size (600x400)
- Process mode: `PROCESS_MODE_WHEN_PAUSED` for pause compatibility

**Save Input Validation:**
- Sanitize filename (remove invalid characters: `/\:*?"<>|`)
- Check for existing files and prompt for overwrite
- Default timestamp-based names if field empty
- Max length validation (platform dependent, ~255 chars)

**Saves List Display:**
- Format: `{description} - {formatted_timestamp}` 
- Sort by creation date (newest first)
- Visual selection feedback
- Double-click to load (optional enhancement)
- Show game state info (turn, phase) as subtitle

## Required Files and Changes

### New Files
1. **`40k/scenes/SaveLoadDialog.tscn`** - UI scene definition
2. **`40k/scripts/SaveLoadDialog.gd`** - Dialog logic and controller

### Modified Files
1. **`40k/scripts/Main.gd`** - Add ESC key handling and dialog management
2. **`project.godot`** - Add ui_cancel input action if not exists

### Integration Pattern
```gdscript
# In Main.gd
var save_load_dialog: SaveLoadDialog

func _ready():
    # ... existing code ...
    _setup_save_load_dialog()

func _setup_save_load_dialog():
    save_load_dialog = preload("res://scenes/SaveLoadDialog.tscn").instantiate()
    add_child(save_load_dialog)
    save_load_dialog.save_requested.connect(_on_save_requested)
    save_load_dialog.load_requested.connect(_on_load_requested)
    save_load_dialog.delete_requested.connect(_on_delete_requested)

func _toggle_save_load_menu():
    if save_load_dialog.visible:
        save_load_dialog.hide()
    else:
        save_load_dialog.refresh_saves_list()
        save_load_dialog.popup_centered()
```

## Validation Gates

### Functional Testing
```bash
# Manual test cases to verify
1. ESC key opens dialog
2. ESC key closes dialog  
3. Save with custom name works
4. Save with empty name creates timestamped save
5. Load existing save restores game state
6. Invalid characters in save names are handled
7. Overwrite confirmation works
8. Delete save file works
9. Cancel buttons work properly
10. Dialog behaves properly when clicking outside
```

### Code Quality
```bash
# Run Godot's built-in validation
godot --check-only
```

### Integration Testing
- Verify saves created through dialog work with quickload ([/] keys)
- Ensure existing autosave functionality unaffected
- Test with existing save files (backward compatibility)
- Verify UI doesn't interfere with game input when closed

## Implementation Tasks (In Order)

1. **Create UI Scene** - Build SaveLoadDialog.tscn with proper layout
2. **Implement Dialog Script** - SaveLoadDialog.gd with all functionality
3. **Add ESC Key Handling** - Modify Main.gd for input processing  
4. **Integrate Dialog** - Connect signals and instantiate in Main scene
5. **Add Input Map Entry** - Ensure ui_cancel action exists in project
6. **Implement Save Logic** - Connect to SaveLoadManager.save_game()
7. **Implement Load Logic** - Connect to SaveLoadManager.load_game()
8. **Add Save List Refresh** - Populate saves list from metadata
9. **Add Delete Functionality** - File deletion with confirmation
10. **Polish and Error Handling** - User feedback, validation, edge cases
11. **Manual Testing** - Test all user flows and edge cases

## Architecture Benefits

**Leverages Existing Systems:**
- Uses proven SaveLoadManager API (no changes needed)
- Follows established file format and metadata structure
- Integrates with existing notification system
- Maintains backward compatibility

**Extends Patterns:**
- Introduces modal dialog system for future features
- Follows existing input handling conventions
- Uses established signal-based communication
- Maintains UI consistency with programmatic creation

**Quality Assurance:**
- Builds on tested save/load infrastructure
- Reuses validation and error handling
- Follows existing code conventions and patterns

## Design Resources and References

**Godot 4 Documentation:**
- AcceptDialog: https://docs.godotengine.org/en/4.4/classes/class_acceptdialog.html
- PopupMenu: https://docs.godotengine.org/en/4.4/classes/class_popupmenu.html
- InputEvent: https://docs.godotengine.org/en/4.4/tutorials/inputs/inputevent.html

**Game UI Best Practices:**
- Visual hierarchy with primary actions emphasized
- Consistent button placement (Save/Load/Cancel pattern)
- Clear grouping of save vs load functionality
- Responsive feedback for all user actions
- Forgiving design with easy cancellation

**Warhammer 40K Rules Reference:**
- https://wahapedia.ru/wh40k10ed/the-rules/core-rules/

## Success Criteria

- [ ] ESC key opens/closes save/load menu
- [ ] Users can create named saves
- [ ] Users can load existing saves
- [ ] Save list shows timestamps and custom names
- [ ] Invalid input is handled gracefully
- [ ] Integration doesn't break existing save/load features
- [ ] UI follows established visual patterns
- [ ] All error states provide user feedback

## Risk Mitigation

**Integration Risks:**
- **Existing shortcuts conflict:** Solution - Test and document interaction
- **Save format changes:** Solution - Use existing metadata fields only
- **UI performance:** Solution - Lazy load saves list, limit displayed items

**User Experience Risks:**
- **Confusing UI:** Solution - Follow established game menu patterns
- **Data loss:** Solution - Implement confirmation dialogs for destructive actions
- **ESC key conflicts:** Solution - Proper input event handling priority

## PRP Confidence Score: 8/10

**High Confidence Because:**
- Excellent existing save/load architecture to build upon
- Clear requirements and user flows
- Leverages proven Godot modal dialog patterns
- No need to modify core save/load logic
- Well-established UI integration patterns

**Moderate Risk Factors:**
- First modal dialog in codebase (new pattern)
- ESC key handling integration complexity
- File deletion requires careful implementation

This PRP provides comprehensive context for one-pass implementation success through detailed research, clear technical specifications, and leveraging of existing robust systems.