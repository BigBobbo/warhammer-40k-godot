# GUT Plugin Installation Fix

## Issue
The GUT tab was not appearing in the Godot editor.

## Root Cause
The `plugin.cfg` file was pointing to the wrong script file (`plugin.gd` instead of `gut_plugin.gd`).

## Fix Applied
Changed `40k/addons/gut/plugin.cfg` line 7 from:
```
script="plugin.gd"
```
to:
```
script="gut_plugin.gd"
```

## Verification Steps
To verify the GUT tab now appears in the Godot editor:

1. Open the Godot editor:
   ```bash
   export PATH="$HOME/bin:$PATH"
   cd 40k
   godot --editor
   ```

2. Look for the "GUT" tab at the bottom of the editor (in the bottom panel area, next to "Output", "Debugger", etc.)

3. If you don't see it immediately:
   - Check Project > Project Settings > Plugins
   - Ensure "Gut" is enabled (checkbox should be checked)
   - If it's not enabled, enable it and restart the editor

## Expected Result
You should now see a "GUT" button/tab in the bottom panel of the Godot editor. Clicking it will show the GUT testing interface where you can:
- Run all tests
- Run individual test scripts
- View test results
- Configure test settings

## Plugin Details
- **Location**: `40k/addons/gut/`
- **Version**: 9.4.0
- **Enabled in**: `40k/project.godot` (line 51)
- **Main Script**: `gut_plugin.gd`
- **UI Component**: `gui/GutBottomPanel.tscn`

## Troubleshooting
If the GUT tab still doesn't appear:

1. Check for errors in the Godot editor console (Output tab)
2. Verify all required files exist:
   - `addons/gut/gut_plugin.gd`
   - `addons/gut/gui/GutBottomPanel.tscn`
   - `addons/gut/gui/GutEditorWindow.tscn`
   - `addons/gut/version_conversion.gd`
   - `addons/gut/gut_menu.gd`
   - `addons/gut/gui/editor_globals.gd`

3. Try disabling and re-enabling the plugin in Project Settings > Plugins

4. If all else fails, try reimporting the project (Project > Reload Current Project)
