# Fix Character-Unit Selection in Movement Phase

## Problem Summary

When a CHARACTER is attached to a bodyguard unit, they should function as a single unit for movement purposes. Currently:

1. **Right panel unit list (Main.gd `refresh_unit_list`)**: During the MOVEMENT phase (line 4176-4192), the list shows ALL deployed units including attached characters as separate entries. Players can see and click on the attached character independently. The DEPLOYMENT phase already handles this correctly (lines 4100-4110) by appending `" + CharacterName"` to the bodyguard unit display.

2. **MovementController unit list (`_refresh_unit_list`)**: This secondary unit list uses `get_available_actions()` from `MovementPhase.gd`, which correctly skips characters with `attached_to != null` (line 3766). So the MovementController's list is fine.

3. **Board click selection**: When clicking a character model on the board during movement, `_get_model_at_position` returns the character's unit_id. If the active_unit_id is the bodyguard, the click is rejected ("Model belongs to different unit"). The character model should be treated as part of the bodyguard unit for selection/dragging purposes.

4. **Right panel display (`_update_selected_unit_display`)**: When a bodyguard unit is selected, the display shows only the bodyguard name, not the attached character name (line 490).

## Approach

### Change 1: Main.gd `refresh_unit_list` — MOVEMENT phase section (lines 4176-4192)
- Skip units where `attached_to != null` (same as deployment phase logic)
- For bodyguard units with attached characters, append the character name(s) to the display text (same pattern as deployment phase at lines 4100-4110)
- Include attached character model counts in the total

### Change 2: MovementController `_update_selected_unit_display` (line 484-491)
- When displaying the selected unit name, also check for attached characters
- If the unit has attached characters, append their names: e.g., "Intercessors + Captain"

### Change 3: MovementController `_start_model_drag` (line 1336-1338)
- When a clicked model's `unit_id` doesn't match `active_unit_id`, check if the clicked model belongs to a character that is attached to the active unit (bodyguard)
- If so, treat the click as valid — but **do NOT allow dragging** the character model independently. Instead, either:
  - Option A: Ignore the click (character moves automatically with bodyguard) — simplest, clearest
  - Option B: Redirect to select the bodyguard unit — adds complexity
- **Recommendation: Option A** — show a brief message like "Character moves with bodyguard unit" when clicking on an attached character model. This is the most rules-accurate behavior.

### Change 4: MovementController `_get_model_at_position` / click handling
- When clicking on a character model that is attached to a bodyguard, and no unit is currently active, auto-select the bodyguard unit instead
- This handles the case where the user clicks on the character token on the board expecting to select the combined unit

### Change 5: Main.gd `_on_unit_selected` for movement phase
- When a user clicks on an attached character in the right panel list (if we somehow still show it), redirect selection to the bodyguard unit
- Actually, with Change 1, attached characters won't appear in the list, so this is a safety net

## Concerns & Edge Cases

1. **Drag-box selection**: When using shift+drag to select multiple models, the box might include character models. Need to ensure character models attached to the active bodyguard unit are included in the selection for group movement (they already move automatically via `_move_attached_characters`, but visually they should be included).

2. **Movement distance**: The bodyguard unit's movement characteristic applies to the whole combined unit. The character's M stat is irrelevant while attached. This is already handled correctly — `_move_attached_characters` applies the same delta to character models.

3. **Advance rolls**: When the bodyguard advances, the character advances too. Already handled by `_move_attached_characters`.

4. **Fall Back**: Same — character falls back with bodyguard. Already handled.

5. **"Moved" flag**: `_move_attached_characters` already sets `flags.moved = true` on the character (line 4720-4724). This is correct.

6. **Unit coherency**: The character model should maintain coherency with the bodyguard unit. The current `_move_attached_characters` just applies a delta offset, which maintains relative positioning. This is acceptable.

7. **Multiple attached characters**: The code supports arrays of attached characters, so multiple leaders are handled.

## Files to Modify

1. `40k/scripts/Main.gd` — `refresh_unit_list()` MOVEMENT case (~line 4176)
2. `40k/scripts/MovementController.gd` — `_update_selected_unit_display()` (~line 484), `_start_model_drag()` (~line 1336), `_handle_single_model_selection()` interaction
