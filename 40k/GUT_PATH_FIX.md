# GUT Plugin Path Reference Fix

## Issue
After installing the GUT testing framework, Godot was displaying errors about being unable to open files with the path prefix `res://addons/Gut-9.4.0/addons/gut/` instead of the correct `res://addons/gut/`.

## Errors Encountered
```
ERROR: Cannot open file 'res://addons/Gut-9.4.0/addons/gut/gui/BottomPanelShortcuts.tscn'.
ERROR: Failed loading resource: res://addons/Gut-9.4.0/addons/gut/gui/BottomPanelShortcuts.tscn.
ERROR: Cannot open file 'res://addons/Gut-9.4.0/addons/gut/gui/RunAtCursor.tscn'.
ERROR: Failed loading resource: res://addons/Gut-9.4.0/addons/gut/gui/RunAtCursor.tscn.
ERROR: Failed loading resource: res://addons/Gut-9.4.0/addons/gut/gui/play.png.
ERROR: Cannot open file 'res://addons/Gut-9.4.0/addons/gut/gui/RunResults.tscn'.
ERROR: Failed loading resource: res://addons/Gut-9.4.0/addons/gut/gui/RunResults.tscn.
ERROR: Cannot open file 'res://addons/Gut-9.4.0/addons/gut/gui/OutputText.tscn'.
ERROR: Failed loading resource: res://addons/Gut-9.4.0/addons/gut/gui/OutputText.tscn.
ERROR: Cannot open file 'res://addons/Gut-9.4.0/addons/gut/gui/NormalGui.tscn'.
ERROR: Failed loading resource: res://addons/Gut-9.4.0/addons/gut/gui/
```

## Root Cause
The Godot editor had cached the old installation path from when GUT was originally extracted from the zip file as `Gut-9.4.0`. Even though the files were moved to the correct location at `addons/gut/`, the editor cache still referenced the old paths.

## Solution
1. Cleared the Godot editor cache by removing the `.godot/editor` directory
2. Rebuilt the editor cache by running Godot in headless mode with the `--editor` flag
3. Added the newly created GUT GUI files to git:
   - `addons/gut/gui/BottomPanelShortcuts.gd`
   - `addons/gut/gui/BottomPanelShortcuts.gd.uid`
   - `addons/gut/gui/BottomPanelShortcuts.tscn`
   - `addons/gut/gui/script_text_editor_controls.gd`
   - `addons/gut/gui/script_text_editor_controls.gd.uid`

## Commands Used
```bash
# Remove editor cache
rm -rf 40k/.godot/editor

# Rebuild cache
cd 40k && godot --headless --quit --editor

# Verify no errors
godot --headless --quit --editor 2>&1 | grep -i "error\|failed"
```

## Verification
After clearing and rebuilding the cache, running Godot in headless editor mode produces no errors related to GUT file paths. The plugin is now properly configured at `res://addons/gut/` as specified in `project.godot`.

## Date
October 23, 2025
