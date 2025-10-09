# Left Panel Hide by Default - Implementation Summary

**Date:** 2025-10-09
**Feature:** Hide left panel (Mathhammer UI) by default with toggle button

## Summary

Implemented functionality to hide the left panel (HUD_Left) by default when the game starts, with a toggle button in the top panel to show/hide it.

## Changes Implemented

### What the Left Panel Contains
- Mathhammer UI (damage calculator and probability tool)
- VBoxContainer for future expandability

### Implementation Details

**New Variables:**
```gdscript
var left_panel_toggle_button: Button
var is_left_panel_visible: bool = false
```

**New Functions:**
1. `_setup_left_panel_toggle()` - Creates and adds toggle button to top HUD
2. `_hide_left_panel()` - Hides the left panel on game start
3. `_on_left_panel_toggle_pressed()` - Toggles panel visibility

**Button Placement:**
- Toggle button added to `HUD_Bottom/HBoxContainer` (top panel)
- Positioned at the beginning (index 0) before phase label
- Text changes based on state: "Show Mathhammer" / "Hide Mathhammer"

**Default State:**
- Left panel hidden when game starts
- `is_left_panel_visible = false`
- Button shows "Show Mathhammer"

### User Interaction

1. **On Game Start:**
   - Left panel is hidden automatically
   - Toggle button shows "Show Mathhammer"

2. **Clicking Toggle Button:**
   - Panel visibility toggles
   - Button text updates accordingly
   - State tracked in `is_left_panel_visible`

### Files Modified

1. **40k/scripts/Main.gd**
   - Added variables for toggle button and visibility state (lines 26-27)
   - Added setup calls in `_ready()` (lines 126-127)
   - Added three new functions at end of file (lines 3019-3063)

### Code Structure

```gdscript
# In _ready()
_setup_left_panel_toggle()  # Create and add toggle button
_hide_left_panel()           # Hide panel by default

# New functions
func _setup_left_panel_toggle() -> void:
    # Creates button with "Show Mathhammer" text
    # Adds to top HUD at beginning
    # Connects to toggle handler

func _hide_left_panel() -> void:
    # Sets HUD_Left.visible = false
    # Sets is_left_panel_visible = false

func _on_left_panel_toggle_pressed() -> void:
    # Toggles panel visibility
    # Updates button text
    # Tracks state
```

## Benefits

1. **Cleaner Default Interface:** Less clutter when starting the game
2. **Easy Access:** One-click toggle to show Mathhammer when needed
3. **Persistent State:** State tracked during gameplay session
4. **Clear Labeling:** Button text clearly indicates panel content and action

## Technical Notes

- Panel uses Godot's built-in `visible` property
- Toggle button created dynamically in code
- No scene file changes needed
- Panel maintains all functionality when shown

## Future Enhancements

Possible improvements:
1. Save toggle state to preferences
2. Keyboard shortcut for toggle (e.g., 'M' key)
3. Animation for panel show/hide
4. Allow panel to be docked to right side instead

---

**Completed by:** Claude Code
**Date:** 2025-10-09
