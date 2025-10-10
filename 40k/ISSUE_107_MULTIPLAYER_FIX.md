# Issue #107: Multiplayer Flag Reset Fix

## Problem Diagnosis

The original fix in `ScoringPhase.gd` worked correctly for **single-player** games, but **failed in multiplayer** because multiplayer games use a different code path:

### Single-Player Path
```
User clicks "End Turn"
  ↓
ScoringPhase._handle_end_turn() is called
  ↓
_create_flag_reset_changes() clears flags  ✅
  ↓
Player switches
```

### Multiplayer Path (Was Broken)
```
User clicks "End Turn"
  ↓
Action routed through NetworkManager
  ↓
GameManager.process_end_scoring() is called
  ↓
Player switches (NO FLAG RESET ❌)
```

### Log Evidence

From `godot.log`:
```
GameManager: Processing END_SCORING action
GameManager: Player 1 ending turn, switching to player 2
```

Notice: **No "Resetting flags" messages** because GameManager.process_end_scoring() didn't have the flag reset logic!

## Solution

Added the same flag reset logic to **GameManager** that was originally added to **ScoringPhase**, ensuring both code paths reset flags correctly.

## Files Modified

### 1. `40k/autoloads/GameManager.gd`

**Added:**
- Line 215: Support for "remove" operation in `apply_diff()`
- Lines 263-305: New `remove_value_at_path()` function
- Lines 518-570: New `_create_flag_reset_diffs()` helper method
- Line 399: Call to `_create_flag_reset_diffs()` in `process_end_scoring()`

**Changes Summary:**
```gdscript
func process_end_scoring(action: Dictionary) -> Dictionary:
    # ... existing code ...

    # NEW: Reset unit flags for the player whose turn is starting
    var diffs = _create_flag_reset_diffs(next_player)

    # Add phase transition
    diffs.append({ "op": "set", "path": "meta.phase", "value": next_phase })

    # Add player switch
    diffs.append({ "op": "set", "path": "meta.active_player", "value": next_player })

    # ... rest of method ...
```

### 2. `40k/phases/ScoringPhase.gd` (Original Fix - Still Valid)

This file already had the fix for single-player mode, which remains unchanged and functional.

## Technical Details

### Flag Reset Logic

Both `GameManager._create_flag_reset_diffs()` and `ScoringPhase._create_flag_reset_changes()` perform the same operation:

1. **Iterate through all units** in the game state
2. **Filter for units** belonging to the player whose turn is starting
3. **Skip embarked units** (can't act while inside transports)
4. **Remove these flags** from each qualifying unit:
   - Movement: `moved`, `advanced`, `fell_back`, `remained_stationary`, `cannot_move`, `move_cap_inches`
   - Restrictions: `cannot_shoot`, `cannot_charge`
   - Combat: `has_shot`, `charged_this_turn`, `fights_first`

### Diff Operation Support

Added "remove" operation support to GameManager:

```gdscript
func apply_diff(diff: Dictionary) -> void:
    match op:
        "set":
            set_value_at_path(path, value)
        "remove":          # NEW!
            remove_value_at_path(path)
```

This allows flag removal diffs to be processed correctly:
```gdscript
{
    "op": "remove",
    "path": "units.U_BLADE_CHAMPION_A.flags.moved"
}
```

## Expected Debug Output (After Fix)

When a player ends their turn in multiplayer, you should now see:

```
GameManager: Processing END_SCORING action
GameManager: Player 1 ending turn, switching to player 2
GameManager: Resetting flags for 3 units owned by player 2
GameManager:   Reset flags for Blade Champion: [moved]
GameManager:   Reset flags for Witchseekers: [has_shot]
GameManager:   Reset flags for Caladius Grav-tank: [advanced, cannot_shoot, cannot_charge]
GameManager: Removing units.U_BLADE_CHAMPION_A.flags.moved
GameManager: Removing units.U_WITCHSEEKERS_C.flags.has_shot
...
```

## Testing Instructions

### Quick Test (Multiplayer)

1. Start a multiplayer game
2. **Player 1's Turn:**
   - Move a unit
   - Note which unit moved
   - End turn (through all phases to Scoring → End Turn)
3. **Player 2's Turn:**
   - Perform some actions (or just end turn)
   - End turn
4. **Player 1's Turn Again:**
   - Try to move the same unit from step 2
   - ✅ **PASS**: Unit can move
   - ❌ **FAIL**: "Unit has already moved" error

### Debug Log Verification

Check log at:
```
~/Library/Application Support/Godot/app_userdata/40k/logs/godot.log
```

Look for:
```bash
grep "Resetting flags" godot.log
grep "Reset flags for" godot.log
grep "Removing units" godot.log
```

You should see these messages appearing when turns end.

## Why Two Implementations?

**Q:** Why maintain flag reset logic in both GameManager AND ScoringPhase?

**A:** Because they serve different game modes:
- **ScoringPhase**: Used in single-player and local testing
- **GameManager**: Used in multiplayer (host and client sync)

Both code paths must have the same logic to ensure consistent behavior across all game modes.

## Comparison: Before vs After

### Before Fix
```gdscript
func process_end_scoring(action: Dictionary) -> Dictionary:
    var diffs = [
        { "op": "set", "path": "meta.phase", "value": next_phase },
        { "op": "set", "path": "meta.active_player", "value": next_player }
    ]
    return {"success": true, "diffs": diffs}
```

### After Fix
```gdscript
func process_end_scoring(action: Dictionary) -> Dictionary:
    # Reset flags first!
    var diffs = _create_flag_reset_diffs(next_player)

    # Then add phase/player changes
    diffs.append({ "op": "set", "path": "meta.phase", "value": next_phase })
    diffs.append({ "op": "set", "path": "meta.active_player", "value": next_player })

    return {"success": true, "diffs": diffs}
```

## Related Files

- **PRP Document**: `/PRPs/gh_issue_107_unit-flag-reset.md`
- **Test Plan**: `/40k/UNIT_FLAG_RESET_TEST_PLAN.md`
- **Original Completion Summary**: `/40k/ISSUE_107_COMPLETION_SUMMARY.md`
- **Modified Files**:
  - `/40k/autoloads/GameManager.gd` (NEW - Multiplayer fix)
  - `/40k/phases/ScoringPhase.gd` (Original - Single-player fix)

---

**Fix Applied**: 2025-10-10
**Issue**: Units couldn't act in subsequent turns in multiplayer
**Root Cause**: GameManager.process_end_scoring() didn't reset flags
**Solution**: Added flag reset logic to both GameManager and ScoringPhase
**Status**: ✅ FIXED - Ready for testing in multiplayer
