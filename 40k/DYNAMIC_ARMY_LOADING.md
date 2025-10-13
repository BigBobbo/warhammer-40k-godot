# Dynamic Army Loading

## Overview
The MainMenu now dynamically loads available armies from the `armies/` directory instead of using a hardcoded list. This allows new armies to be added simply by placing a JSON file in the armies folder.

## Changes Made

### Before
- Army options were hardcoded in `MainMenu.gd`:
  ```gdscript
  var army_options = [
    {"id": "adeptus_custodes", "name": "Adeptus Custodes"},
    {"id": "space_marines", "name": "Space Marines"},
    {"id": "orks", "name": "Orks"}
  ]
  ```
- Adding a new army required modifying code in two places:
  1. Creating the JSON file in `armies/`
  2. Adding entry to `army_options` array in `MainMenu.gd`

### After
- Army options are dynamically populated from `ArmyListManager`:
  ```gdscript
  var army_options = []  # Populated at runtime
  ```
- Adding a new army only requires:
  1. Creating the JSON file in `armies/`
  - The menu will automatically detect and list it

## Implementation Details

### New Functions in MainMenu.gd

**`_load_available_armies()`**
- Calls `ArmyListManager.get_available_armies()`
- Converts army IDs to display names
- Sorts armies alphabetically
- Handles missing ArmyListManager gracefully

**`_format_army_name(army_id: String)`**
- Converts snake_case IDs to Title Case names
- Example: `"adeptus_custodes"` → `"Adeptus Custodes"`

**`_set_default_army_selections()`**
- Intelligently selects default armies
- Prefers Adeptus Custodes for Player 1
- Prefers Orks for Player 2
- Ensures different armies for each player when possible

### Features

✅ **Automatic Discovery**: Scans both `res://armies/` and `user://armies/`
✅ **Alphabetical Sorting**: Armies displayed in A-Z order
✅ **Smart Defaults**: Maintains existing default behavior (Custodes vs Orks)
✅ **Graceful Fallback**: Handles missing armies gracefully
✅ **User-Friendly Names**: Converts file names to readable display names

## Adding a New Army

### Step 1: Create Army JSON File
Create `armies/your_army_name.json` with proper structure:

```json
{
  "faction": {
    "name": "Your Army Name",
    "points": 1000,
    "detachment": "Your Detachment",
    "player_name": "",
    "team_name": ""
  },
  "units": {
    "UNIT_ID": {
      "id": "UNIT_ID",
      "meta": {
        "name": "Unit Name",
        "keywords": ["INFANTRY"],
        "stats": { ... },
        "weapons": [ ... ]
      },
      "models": [ ... ]
    }
  }
}
```

### Step 2: That's It!
The army will automatically appear in the main menu dropdowns on next launch.

## Testing

The implementation can be tested by:

1. **Adding a new army**:
   ```bash
   # Copy an existing army as a template
   cp armies/space_marines.json armies/necrons.json
   # Edit to change faction name and units
   ```

2. **Launch the game**:
   - The new army should appear in both dropdown menus
   - Armies should be sorted alphabetically
   - Existing defaults should still work

3. **Remove all armies** (edge case test):
   - Menu should show "No Armies Available"
   - Game should handle gracefully

## Benefits

1. **Easier Army Addition**: No code changes needed
2. **Modding Support**: Users can add custom armies in exported games (via `user://armies/`)
3. **Maintainability**: Single source of truth (file system)
4. **Flexibility**: Works for any number of armies
5. **User Experience**: Alphabetically sorted, properly formatted names

## Code Location

- **Modified File**: `40k/scripts/MainMenu.gd`
- **Key Functions**:
  - `_load_available_armies()` (line 72)
  - `_format_army_name()` (line 98)
  - `_set_default_army_selections()` (line 112)
- **Army Files**: `40k/armies/*.json`
- **ArmyListManager**: `40k/autoloads/ArmyListManager.gd`
