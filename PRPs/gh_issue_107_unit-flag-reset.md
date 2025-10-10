# PRP: Unit Movement Flag Reset Between Turns

## Issue Summary
Unit movement and action flags (moved, advanced, fell_back, has_shot, charged_this_turn, etc.) are not resetting when a new player turn begins. This prevents units from acting again in subsequent player turns, breaking the core game loop.

**Issue Number**: 107
**Priority**: HIGH - Game-breaking bug
**Affected Systems**: Phase management, unit action tracking

## Problem Statement

### Current Behavior
- Units can perform actions (move, shoot, charge) during their owner's turn
- Flags are set when units perform actions (e.g., `flags.moved = true`)
- When the turn switches to the next player, these flags persist
- Units cannot perform actions again in their next turn because flags indicate they've already acted

### Expected Behavior
According to Warhammer 40k 10th Edition rules:
- Each player gets a full turn during each battle round
- Units can move, shoot, charge, and fight during their owner's turn
- When a new player turn begins, units should be able to act again
- Flags should reset at the start of each player's turn

### Root Cause
In `40k/phases/ScoringPhase.gd`, the `_handle_end_turn()` method (lines 47-77) switches the active player but does not clear unit action flags. These flags persist in the game state, preventing units from acting in subsequent turns.

## Research Findings

### Codebase Analysis

#### 1. **Unit Flags Requiring Reset**
Found in phases/MovementPhase.gd, ShootingPhase.gd, and ChargePhase.gd:

**Per-Turn Flags (MUST reset):**
- `flags.moved` - Unit has moved this turn
- `flags.advanced` - Unit used Advance move
- `flags.fell_back` - Unit used Fall Back move
- `flags.cannot_shoot` - Movement restriction (set by Advance/Fall Back)
- `flags.cannot_charge` - Movement restriction (set by Advance/Fall Back)
- `flags.cannot_move` - Disembark restriction
- `flags.remained_stationary` - Unit chose not to move
- `flags.has_shot` - Unit has shot this turn
- `flags.charged_this_turn` - Unit has charged this turn
- `flags.fights_first` - Unit fights first in Fight phase
- `flags.move_cap_inches` - Temporary movement cap (should be removed)

**Persistent Flags (do NOT reset):**
- Status effects (battle_shocked, etc.)
- Embarked status (embarked_in)
- Position/rotation data
- Wounds and casualties
- Transport-related data

#### 2. **Turn Transition Flow**
```
ScoringPhase.process_action("END_SCORING")
  ↓
_handle_end_turn()
  ↓
Switch active_player (1 → 2 or 2 → 1)
  ↓
If Player 2 finished: advance battle_round
  ↓
PhaseManager.advance_to_next_phase()
  ↓
Transition to CommandPhase (next player's turn)
```

**Location**: `40k/phases/ScoringPhase.gd:47-77`

#### 3. **Existing Pattern**
ChargePhase (lines 787-788) and ShootingPhase (line 448) show examples of clearing specific flags, but this is phase-specific cleanup, not turn-wide reset:

```gdscript
# ChargePhase cleanup (end of phase, not end of turn)
unit.flags.erase("charged_this_turn")
unit.flags.erase("fights_first")

# ShootingPhase cleanup (end of phase, not end of turn)
unit.flags.erase("has_shot")
```

These clear flags at phase end, but we need a turn-wide reset.

### Warhammer 40k Rules Reference

From https://wahapedia.ru/wh40k10ed/the-rules/core-rules/:

**Turn Structure:**
1. Each battle round consists of two player turns (Player 1, then Player 2)
2. Each player turn includes: Command → Movement → Shooting → Charge → Fight → Scoring phases
3. Units can act during their owner's turn
4. Restrictions apply fresh each turn (no carry-over from previous turn)

**Key Quote:**
> "Start your Movement phase by selecting one unit from your army that is on the battlefield to move"

This implies units can move each time it's their owner's turn, confirming flags must reset.

## Solution Design

### Implementation Location

**Primary Implementation: ScoringPhase._handle_end_turn()**

This is the optimal location because:
1. ✅ Centralized - All player turn endings go through this method
2. ✅ Explicit - Clear semantic meaning ("end of turn, clean up")
3. ✅ Safe - Happens after all phases are complete
4. ✅ Maintainable - Single place to manage flag lifecycle
5. ✅ Multiplayer-compatible - Synchronized through game state changes

### Pseudocode

```gdscript
func _handle_end_turn() -> Dictionary:
    var current_player = get_current_player()
    var next_player = 2 if current_player == 1 else 1

    # NEW: Reset unit flags for next player's turn
    var changes = _create_flag_reset_changes(next_player)

    # Switch player
    changes.append({
        "op": "set",
        "path": "meta.active_player",
        "value": next_player
    })

    # Advance battle round if Player 2 finished
    if current_player == 2:
        var new_battle_round = GameState.get_battle_round() + 1
        changes.append({
            "op": "set",
            "path": "meta.battle_round",
            "value": new_battle_round
        })

    return {
        "success": true,
        "changes": changes,
        "message": "Turn ended, control switched to player %d" % next_player
    }

func _create_flag_reset_changes(player: int) -> Array:
    """Create state changes to reset action flags for a player's units"""
    var changes = []
    var units = game_state_snapshot.get("units", {})

    for unit_id in units:
        var unit = units[unit_id]

        # Only reset flags for units belonging to the player whose turn is starting
        if unit.get("owner", 0) != player:
            continue

        # Skip embarked units (they don't act)
        if unit.get("embarked_in", null) != null:
            continue

        var flags = unit.get("flags", {})
        var flags_to_reset = [
            "moved", "advanced", "fell_back", "remained_stationary",
            "cannot_shoot", "cannot_charge", "cannot_move",
            "has_shot", "charged_this_turn", "fights_first"
        ]

        for flag in flags_to_reset:
            if flags.has(flag):
                changes.append({
                    "op": "remove",
                    "path": "units.%s.flags.%s" % [unit_id, flag]
                })

        # Also remove temporary caps
        if flags.has("move_cap_inches"):
            changes.append({
                "op": "remove",
                "path": "units.%s.flags.move_cap_inches" % unit_id
            })

    return changes
```

### Implementation Steps

1. **Modify ScoringPhase.gd**
   - Add `_create_flag_reset_changes(player: int) -> Array` helper method
   - Call this method in `_handle_end_turn()` before switching players
   - Ensure changes are returned and applied through normal state change flow

2. **Add Logging**
   - Log when flags are being reset
   - Log which units have flags reset
   - Use existing `print()` pattern for consistency

3. **Consider Edge Cases**
   - Embarked units: Don't reset (they're not on battlefield)
   - Destroyed units: Still reset (for consistency, though they can't act)
   - Status effects: Don't reset (these persist across turns)

## Validation Strategy

### Manual Testing Approach

1. **Setup Test Scenario**
   - Start new game with 2 armies
   - Complete deployment phase

2. **Test Movement Flags**
   - Player 1's turn: Move a unit → verify `flags.moved = true`
   - End Player 1's turn → switch to Player 2
   - Check Player 1's units: verify `flags.moved` is cleared
   - Player 2's turn: End turn → switch back to Player 1
   - Try to move the same Player 1 unit → should work

3. **Test Advance Flags**
   - Player 1: Advance with unit → verify `flags.advanced`, `flags.cannot_shoot`, `flags.cannot_charge` are set
   - End turn → switch to Player 2 → end turn → switch back to Player 1
   - Verify all advance-related flags are cleared
   - Verify unit can shoot and charge normally

4. **Test Shooting Flags**
   - Player 1: Shoot with unit → verify `flags.has_shot = true`
   - End turn → switch to Player 2 → end turn → switch back to Player 1
   - Try to shoot with same unit → should work

5. **Test Charge Flags**
   - Player 1: Charge with unit → verify `flags.charged_this_turn`, `flags.fights_first` are set
   - End turn → switch to Player 2 → end turn → switch back to Player 1
   - Verify charge flags are cleared

### Debug Log Validation

**Log File Location:**
```
~/Library/Application Support/Godot/app_userdata/40k/logs/debug_YYYYMMDD_HHMMSS.log
```

Or dynamically find:
```gdscript
print(DebugLogger.get_real_log_file_path())
```

**Expected Log Patterns:**

```
ScoringPhase: Player 1 ending turn, switching to player 2
ScoringPhase: Resetting flags for 2 units owned by player 2
ScoringPhase:   Reset flags for unit <unit_name_1>: [moved, has_shot]
ScoringPhase:   Reset flags for unit <unit_name_2>: [advanced, cannot_shoot, cannot_charge]
[GameState changes applied]
PhaseManager: Transitioning to Command phase
```

### Automated Testing (if time permits)

Create test: `40k/tests/phases/test_scoring_phase_flag_reset.gd`

```gdscript
extends BasePhaseTest

func test_movement_flags_reset_on_turn_end():
    # Setup: Set movement flags on Player 1 units
    var unit = get_test_unit("test_unit_1")
    unit.flags.moved = true
    unit.flags.advanced = true

    # Action: End turn (switch to Player 2)
    scoring_phase.process_action(create_action("END_SCORING"))

    # End Player 2's turn (switch back to Player 1)
    scoring_phase.process_action(create_action("END_SCORING"))

    # Assert: Flags should be cleared
    unit = get_test_unit("test_unit_1")
    assert_false(unit.flags.has("moved"), "moved flag should be reset")
    assert_false(unit.flags.has("advanced"), "advanced flag should be reset")
```

### Godot Test Execution

```bash
# Run all tests
cd 40k
godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests

# Run only scoring phase tests
godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests/phases -gselect="*scoring*"
```

## Error Handling

### Potential Issues

1. **Missing units dictionary**
   - Check `game_state_snapshot.has("units")` before iterating
   - Return empty array if no units

2. **Invalid unit structure**
   - Check `unit.has("owner")` before accessing
   - Skip units with missing required fields

3. **Null/missing flags dictionary**
   - Check `unit.has("flags")` before accessing
   - Skip if no flags to reset

4. **Multiplayer sync issues**
   - All changes go through standard state change system
   - PhaseManager.apply_state_changes() handles sync
   - NetworkManager should handle propagation automatically

## Implementation Checklist

- [ ] Add `_create_flag_reset_changes(player: int) -> Array` method to ScoringPhase.gd
- [ ] Modify `_handle_end_turn()` to call flag reset logic
- [ ] Add debug logging for flag resets
- [ ] Test manually with multiple turn cycles
- [ ] Verify flags reset for movement actions
- [ ] Verify flags reset for shooting actions
- [ ] Verify flags reset for charge actions
- [ ] Verify embarked units are skipped
- [ ] Verify persistent flags are not affected
- [ ] Check debug logs for confirmation
- [ ] Test in multiplayer scenario (if possible)
- [ ] Create automated test (optional but recommended)

## Files to Modify

1. **40k/phases/ScoringPhase.gd** (PRIMARY)
   - Add flag reset logic to `_handle_end_turn()`
   - Add `_create_flag_reset_changes()` helper method

2. **40k/tests/phases/test_scoring_phase.gd** (OPTIONAL)
   - Add test for flag reset functionality

## Success Criteria

✅ **Phase 1: Core Functionality**
- Units can perform actions in their first turn (baseline)
- After turn ends and switches back, units can perform actions again
- Movement flags reset correctly
- Shooting flags reset correctly
- Charge flags reset correctly

✅ **Phase 2: Edge Cases**
- Embarked units don't have flags reset (they shouldn't act anyway)
- Persistent status effects are preserved
- Multiple turn cycles work correctly (Turn 1 → Turn 2 → Turn 3, etc.)

✅ **Phase 3: Validation**
- Debug logs show flag resets happening
- No errors or warnings in logs
- Game flow feels natural and correct

## Related Documentation

- **Warhammer 40k Core Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- **Godot Documentation**: https://docs.godotengine.org/en/4.4/
- **Testing Guide**: `/40k/TESTING.md`
- **Phase System**: `/40k/phases/BasePhase.gd`
- **Turn Management**: `/40k/autoloads/TurnManager.gd`
- **Game State**: `/40k/autoloads/GameState.gd`

## Implementation Timeline

- **Research & Planning**: ✅ COMPLETE
- **Implementation**: 30-45 minutes (straightforward change)
- **Testing**: 15-30 minutes (manual testing + log review)
- **Total**: ~1 hour

## Risk Assessment

**Risk Level**: LOW

- ✅ Well-understood problem
- ✅ Clear solution path
- ✅ Isolated change (single file)
- ✅ Easy to test
- ✅ Easy to rollback if needed
- ✅ Uses existing patterns (state changes)

**Potential Risks:**
- ⚠️ Multiplayer sync (mitigated by using standard state change system)
- ⚠️ Performance (minimal - only runs once per turn)
- ⚠️ Accidentally resetting wrong flags (mitigated by explicit flag list)

## PRP Confidence Score

**9/10** - High confidence for one-pass implementation

**Reasoning:**
- Clear problem with obvious solution
- Well-researched with examples from codebase
- Comprehensive validation strategy
- Low complexity, low risk
- Follows existing patterns
- Only point deducted for potential multiplayer edge cases

---

**Generated**: 2025-10-10
**Author**: Claude Code
**Status**: Ready for Implementation
