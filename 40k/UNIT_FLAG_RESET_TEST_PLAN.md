# Unit Flag Reset - Testing & Validation Plan

## Implementation Complete ✅

The unit flag reset functionality has been implemented in `40k/phases/ScoringPhase.gd`.

**Changes Made:**
1. Added `_create_flag_reset_changes(player: int)` method that creates state changes to clear per-turn action flags
2. Modified `_handle_end_turn()` to call flag reset logic before switching players
3. Added comprehensive logging to track flag resets

## Manual Testing Instructions

### Test 1: Basic Movement Flag Reset

**Objective**: Verify units can move again after turn switches back to their owner.

**Steps:**
1. Launch the game and start a new game with 2 armies
2. Complete deployment phase
3. **Player 1's Turn:**
   - Move a unit (any unit will do)
   - Note which unit you moved
   - Open the Godot debug console and verify flag is set: Look for the unit in game state showing `flags.moved = true`
   - End Player 1's turn (go through all phases until Scoring → End Turn)
4. **Player 2's Turn:**
   - Perform any actions (or just end turn immediately)
   - End Player 2's turn
5. **Player 1's Turn (Round 2):**
   - Try to move the SAME unit you moved in step 3
   - ✅ **PASS**: Unit can move again
   - ❌ **FAIL**: Unit shows "already moved" error

**Expected Debug Output:**
```
ScoringPhase: Player 1 ending turn, switching to player 2
ScoringPhase: Resetting flags for N units owned by player 2
ScoringPhase:   Reset flags for <unit_name>: [moved]
...
[Later, when Player 2's turn ends]
ScoringPhase: Player 2 ending turn, switching to player 1
ScoringPhase: Resetting flags for N units owned by player 1
ScoringPhase:   Reset flags for <unit_name>: [moved]
```

### Test 2: Advance Movement Restrictions Reset

**Objective**: Verify Advance movement restrictions clear properly.

**Steps:**
1. **Player 1's Turn:**
   - Use "Advance" with a unit (gets extra movement but can't shoot/charge)
   - Verify unit has `flags.advanced`, `flags.cannot_shoot`, `flags.cannot_charge` set
   - End turn
2. **Player 2's Turn:**
   - End turn
3. **Player 1's Turn (Round 2):**
   - Select the same unit that Advanced
   - Try to shoot with it → ✅ Should work (flags cleared)
   - Try to charge with it → ✅ Should work (flags cleared)

**Expected Flags Reset:**
- `advanced`
- `cannot_shoot`
- `cannot_charge`

### Test 3: Shooting Flag Reset

**Objective**: Verify units can shoot again in subsequent turns.

**Steps:**
1. **Player 1's Turn:**
   - Shoot with a unit
   - Verify `flags.has_shot = true`
   - End turn
2. **Player 2's Turn:**
   - End turn
3. **Player 1's Turn (Round 2):**
   - Try to shoot with the same unit → ✅ Should work

### Test 4: Charge Flag Reset

**Objective**: Verify charge flags reset properly.

**Steps:**
1. **Player 1's Turn:**
   - Charge with a unit
   - Verify `flags.charged_this_turn` and `flags.fights_first` are set
   - End turn
2. **Player 2's Turn:**
   - End turn
3. **Player 1's Turn (Round 2):**
   - Try to charge with the same unit → ✅ Should work

### Test 5: Fall Back Restrictions Reset

**Objective**: Verify Fall Back restrictions clear.

**Steps:**
1. **Player 1's Turn:**
   - Use "Fall Back" with an engaged unit
   - Verify `flags.fell_back`, `flags.cannot_shoot`, `flags.cannot_charge` are set
   - End turn
2. **Player 2's Turn:**
   - End turn
3. **Player 1's Turn (Round 2):**
   - Unit should be able to shoot and charge normally

### Test 6: Remain Stationary Flag Reset

**Objective**: Verify units that remained stationary can move next turn.

**Steps:**
1. **Player 1's Turn:**
   - Choose "Remain Stationary" for a unit
   - Verify `flags.remained_stationary = true` and `flags.moved = true`
   - End turn
2. **Player 2's Turn:**
   - End turn
3. **Player 1's Turn (Round 2):**
   - Try to move the unit → ✅ Should work

### Test 7: Multiple Turn Cycles

**Objective**: Verify flags reset correctly over multiple battle rounds.

**Steps:**
1. Complete a full battle round (Player 1 turn → Player 2 turn)
2. Complete another battle round (Player 1 turn → Player 2 turn)
3. Complete a third battle round
4. Verify units can continue to act normally in each of their turns
5. ✅ **PASS**: Units act normally in all turns
6. ❌ **FAIL**: Units get stuck or can't act after certain turns

### Test 8: Embarked Units

**Objective**: Verify embarked units don't have flags incorrectly reset.

**Steps:**
1. **Player 1's Turn:**
   - Embark a unit in a transport
   - End turn
2. **Player 2's Turn:**
   - End turn
3. **Verify in logs:**
   - Embarked units should be skipped in flag reset
   - Look for: "Skip embarked units" logic working correctly

## Debug Log Validation

### Finding the Debug Log

**Option 1: Check standard location**
```bash
# macOS
ls -lht ~/Library/Application\ Support/Godot/app_userdata/40k/logs/

# Look for most recent file:
# debug_YYYYMMDD_HHMMSS.log
```

**Option 2: Print log path in-game**
In Godot editor console, run:
```gdscript
print(DebugLogger.get_real_log_file_path())
```

### Expected Log Patterns

**When Player 1 ends turn (switching to Player 2):**
```
ScoringPhase: Player 1 ending turn, switching to player 2
ScoringPhase: Resetting flags for X units owned by player 2
ScoringPhase:   Reset flags for <Unit Name 1>: [moved, has_shot]
ScoringPhase:   Reset flags for <Unit Name 2>: [advanced, cannot_shoot, cannot_charge]
...
```

**When Player 2 ends turn (switching to Player 1):**
```
ScoringPhase: Player 2 ending turn, switching to player 1
ScoringPhase: Resetting flags for Y units owned by player 1
ScoringPhase:   Reset flags for <Unit Name 3>: [charged_this_turn, fights_first]
ScoringPhase:   Reset flags for <Unit Name 4>: [fell_back, cannot_charge]
...
```

**If no flags to reset:**
```
ScoringPhase: No flags to reset for player X units
```

### What to Look For

✅ **Good Signs:**
- "Resetting flags for N units" messages appear each turn
- Specific unit names and flag lists are shown
- No errors or warnings about missing units or flags
- Game state changes are applied successfully

❌ **Bad Signs:**
- No "Resetting flags" messages (flag reset not running)
- Errors about missing game_state_snapshot
- Errors about invalid paths
- Units still showing "already moved" errors in subsequent turns

## Quick Validation Test

If you want a quick smoke test:

1. Start game, deploy armies
2. **Player 1 Turn**: Move unit A, shoot with unit B, end turn
3. **Player 2 Turn**: Move unit C, end turn
4. **Player 1 Turn**: Try to move unit A and shoot with unit B
5. ✅ **PASS**: Both work
6. ❌ **FAIL**: Either shows "already acted" error

## Known Limitations

- **Embarked Units**: Flags are not reset for embarked units (they can't act while embarked anyway)
- **Status Effects**: Persistent status effects (battle_shocked, etc.) are intentionally NOT reset
- **Destroyed Units**: Destroyed units still have flags reset (harmless since they can't act)

## Troubleshooting

### Issue: Units still can't act in subsequent turns

**Check:**
1. Is the log showing flag reset messages?
2. Are the flags actually being cleared in the game state?
3. Are the state changes being applied through PhaseManager?

**Solution:**
- Check debug logs for errors
- Verify ScoringPhase._create_flag_reset_changes() is being called
- Verify state changes are being returned and applied

### Issue: No log messages about flag reset

**Possible Causes:**
1. ScoringPhase not being used (old turn system active?)
2. game_state_snapshot not populated correctly
3. Logging not configured properly

**Solution:**
- Verify you're going through all phases including Scoring
- Check that END_SCORING/END_TURN action is being processed
- Add extra debug prints if needed

### Issue: Wrong player's flags being reset

**Check:**
- Log should say "Resetting flags for player X" where X is the NEXT player
- Verify `next_player` calculation is correct

## Success Criteria Summary

All tests should pass:
- ✅ Units can move in subsequent turns
- ✅ Advance restrictions clear properly
- ✅ Shooting flags reset
- ✅ Charge flags reset
- ✅ Fall Back restrictions clear
- ✅ Multiple turn cycles work correctly
- ✅ Debug logs show correct flag resets
- ✅ No errors or warnings in logs

## Reporting Issues

If tests fail, please provide:
1. Which test failed
2. Debug log excerpt showing the failure
3. Steps to reproduce
4. Expected vs actual behavior

---

**Implementation Date**: 2025-10-10
**Status**: Ready for Testing
**Files Modified**: `40k/phases/ScoringPhase.gd`
