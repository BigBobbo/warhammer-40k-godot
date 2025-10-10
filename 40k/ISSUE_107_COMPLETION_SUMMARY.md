# Issue #107: Unit Flag Reset Between Turns - IMPLEMENTATION COMPLETE ✅

## Summary

Successfully implemented unit flag reset functionality to allow units to act in subsequent player turns. Previously, action flags (moved, has_shot, charged_this_turn, etc.) were persisting across turns, preventing units from acting again.

## What Was Fixed

**Problem**: Unit action flags were not resetting when a new player turn began, causing units to be unable to move, shoot, or charge in their next turn.

**Solution**: Added flag reset logic in `ScoringPhase._handle_end_turn()` that clears all per-turn action flags for the player whose turn is starting.

## Implementation Details

### Files Modified

**`40k/phases/ScoringPhase.gd`**

1. **Added new method: `_create_flag_reset_changes(player: int) -> Array`**
   - Lines 80-132
   - Creates state changes to reset per-turn action flags
   - Only resets flags for units belonging to the player whose turn is starting
   - Skips embarked units (they can't act while inside transports)
   - Includes comprehensive logging for debugging

2. **Modified: `_handle_end_turn()`**
   - Line 54: Added call to `_create_flag_reset_changes(next_player)`
   - Flag reset happens BEFORE player switch to ensure clean state

### Flags Reset Each Turn

The following flags are cleared at the start of each player's turn:

**Movement-related:**
- `moved` - Unit has moved this turn
- `advanced` - Unit used Advance move
- `fell_back` - Unit used Fall Back move
- `remained_stationary` - Unit chose not to move
- `move_cap_inches` - Temporary movement cap
- `cannot_move` - Disembark restriction

**Action restrictions:**
- `cannot_shoot` - Set by Advance/Fall Back
- `cannot_charge` - Set by Advance/Fall Back

**Combat actions:**
- `has_shot` - Unit has shot this turn
- `charged_this_turn` - Unit has charged this turn
- `fights_first` - Unit fights first in Fight phase

### Flags NOT Reset (Persistent)

- Status effects (battle_shocked, etc.)
- Embarked status (embarked_in)
- Position/rotation data
- Wounds and casualties
- Transport-related data

## How It Works

```
Player 1 ends turn
  ↓
ScoringPhase._handle_end_turn() called
  ↓
_create_flag_reset_changes(player=2) called
  ↓
Creates state changes to remove flags from Player 2's units
  ↓
Player switches from 1 to 2
  ↓
State changes applied via PhaseManager
  ↓
Player 2's turn begins with clean unit flags
  ↓
Player 2's units can now act normally
```

## Testing Required

**IMPORTANT**: The implementation is complete, but manual testing is required to validate functionality.

📋 **Test Plan**: See `/40k/UNIT_FLAG_RESET_TEST_PLAN.md` for detailed testing instructions

### Quick Validation Test

1. Start game, complete deployment
2. **Player 1 Turn**: Move a unit, end turn
3. **Player 2 Turn**: End turn
4. **Player 1 Turn**: Try to move the same unit again
5. ✅ Should work (if implementation is correct)

### Debug Log Validation

**Log Location:**
```bash
~/Library/Application Support/Godot/app_userdata/40k/logs/debug_YYYYMMDD_HHMMSS.log
```

**Expected Output:**
```
ScoringPhase: Player 1 ending turn, switching to player 2
ScoringPhase: Resetting flags for N units owned by player 2
ScoringPhase:   Reset flags for <unit_name>: [moved, has_shot]
...
```

## Code Changes Summary

### Before (ScoringPhase.gd lines 47-77)
```gdscript
func _handle_end_turn() -> Dictionary:
    var current_player = get_current_player()
    var next_player = 2 if current_player == 1 else 1

    print("ScoringPhase: Player %d ending turn, switching to player %d" % [current_player, next_player])

    # Create state changes to switch player
    var changes = [
        {
            "op": "set",
            "path": "meta.active_player",
            "value": next_player
        }
    ]

    # ... rest of method
```

### After
```gdscript
func _handle_end_turn() -> Dictionary:
    var current_player = get_current_player()
    var next_player = 2 if current_player == 1 else 1

    print("ScoringPhase: Player %d ending turn, switching to player %d" % [current_player, next_player])

    # Reset unit flags for the player whose turn is starting (NEW!)
    var changes = _create_flag_reset_changes(next_player)

    # Create state changes to switch player
    changes.append({
        "op": "set",
        "path": "meta.active_player",
        "value": next_player
    })

    # ... rest of method
```

### New Method Added (lines 80-132)
```gdscript
func _create_flag_reset_changes(player: int) -> Array:
    """Create state changes to reset per-turn action flags for a player's units"""
    var changes = []
    var units = game_state_snapshot.get("units", {})

    # ... (see ScoringPhase.gd for full implementation)

    return changes
```

## Design Decisions

### Why ScoringPhase?

1. **Centralized**: All player turn endings go through ScoringPhase
2. **Explicit**: Clear semantic meaning ("end of turn cleanup")
3. **Safe**: Happens after all phases complete
4. **Maintainable**: Single place to manage flag lifecycle
5. **Multiplayer-compatible**: Uses standard state change system

### Why Reset for Next Player (Not Current Player)?

- Flags are cleared for the player whose turn is STARTING, not ending
- This ensures units have clean state when they become active
- Prevents race conditions or timing issues

### Why Skip Embarked Units?

- Embarked units can't perform actions while inside transports
- No need to reset flags they can't use
- Slight performance optimization

## Known Limitations

1. **Embarked Units**: Flags not reset (intentional - they can't act anyway)
2. **Destroyed Units**: Flags still reset (harmless but unnecessary)
3. **Manual Testing Required**: Automated tests not included in this implementation

## Next Steps

1. ✅ Implementation complete
2. ⏳ Manual testing required (see test plan)
3. ⏳ Verify debug logs show correct behavior
4. ⏳ Test multiple turn cycles
5. ⏳ Test all action types (move, shoot, charge)
6. ⏳ Validate in multiplayer (if applicable)

## Success Criteria

- [x] Code implemented and compiles
- [x] Comprehensive PRP documentation created
- [x] Detailed test plan created
- [ ] Manual testing passes all test cases
- [ ] Debug logs confirm flag resets
- [ ] No regressions in existing functionality
- [ ] Game flow feels correct and natural

## Related Documentation

- **PRP Document**: `/PRPs/gh_issue_107_unit-flag-reset.md`
- **Test Plan**: `/40k/UNIT_FLAG_RESET_TEST_PLAN.md`
- **Modified File**: `/40k/phases/ScoringPhase.gd`

## Rollback Instructions

If issues arise, revert ScoringPhase.gd to git HEAD:

```bash
cd /Users/robertocallaghan/Documents/claude/godotv2
git checkout HEAD -- 40k/phases/ScoringPhase.gd
```

## Contact / Issues

If you encounter issues during testing:

1. Check debug logs for errors
2. Verify state changes are being applied
3. Review test plan for troubleshooting steps
4. Check git diff to ensure changes were applied correctly

---

**Implementation Date**: 2025-10-10
**Implemented By**: Claude Code
**Status**: ✅ COMPLETE - Ready for Testing
**Confidence**: 9/10 - High confidence in implementation
**Risk Level**: LOW - Isolated change, easy to test and rollback
