# Multiplayer State Synchronization Pattern

**Date:** 2025-10-09
**Context:** Discovered during Movement Phase bug fix (Issue #102)

## The Problem

Phase instances have **local state** that is **NOT automatically synchronized** across the network in multiplayer games. This can cause validation and UI issues where host and client see different states.

## Example Bug

**Scenario:** In MovementPhase, the `active_moves` dictionary tracked which units had completed their moves:

```gdscript
# MovementPhase.gd
var active_moves: Dictionary = {}  # LOCAL to this phase instance!

func _process_confirm_unit_move(action: Dictionary) -> Dictionary:
    var unit_id = action.get("actor_unit_id", "")
    var move_data = active_moves[unit_id]
    # ... process move ...
    move_data["completed"] = true  # ❌ Only sets in LOCAL instance!
    return create_result(true, changes)
```

**What Happens:**
1. **Host** confirms a move → Host's `active_moves[unit_id].completed = true`
2. **Changes sync to client** via GameState diffs (model positions, flags, etc.)
3. **Client's `active_moves[unit_id].completed`** stays `false` (never synced!)
4. Client tries to end phase → Validation fails because client sees incomplete move

## The Solution

**Always use synchronized GameState for validation logic**, not local phase state.

### ❌ WRONG (Breaks in Multiplayer)

```gdscript
func _validate_end_movement(action: Dictionary) -> Dictionary:
    for unit_id in active_moves:
        var move_data = active_moves[unit_id]
        if not move_data.get("completed", false):  # Local state only!
            return {"valid": false, "errors": ["Active moves remain"]}
    return {"valid": true, "errors": []}
```

### ✅ CORRECT (Works in Multiplayer)

```gdscript
func _validate_end_movement(action: Dictionary) -> Dictionary:
    for unit_id in active_moves:
        var unit = get_unit(unit_id)  # Get from synced GameState
        var has_moved = unit.get("flags", {}).get("moved", false)  # Synced flag!
        if not has_moved:
            return {"valid": false, "errors": ["Active moves remain"]}
    return {"valid": true, "errors": []}
```

## Understanding State Types

### 1. GameState (Synchronized)

**Location:** `autoloads/GameState.gd`
**Synchronized:** ✅ YES - via action diffs
**Access:** `GameState.state` or `phase.get_unit(unit_id)`

**What's Stored:**
- Unit positions, health, flags
- Game rules state (battle round, active player)
- Any data in the `changes` array returned by action processors

**Usage:**
```gdscript
var unit = get_unit(unit_id)
var has_moved = unit.get("flags", {}).get("moved", false)  # ✅ Synced!
var position = unit.get("position", Vector2.ZERO)  # ✅ Synced!
```

### 2. Phase State (NOT Synchronized)

**Location:** Phase instance variables (e.g., `MovementPhase.gd`)
**Synchronized:** ❌ NO - each instance has its own copy
**Examples:** `active_moves`, `dice_log`, local tracking variables

**What's Stored:**
- Temporary/ephemeral state during action processing
- UI-related tracking
- Intermediate calculations

**Usage:**
```gdscript
# OK for temporary tracking:
var move_data = active_moves[unit_id]
var staged_moves = move_data.staged_moves  # Fine for host processing

# NOT OK for validation:
if not move_data.get("completed", false):  # ❌ Breaks in multiplayer!
```

## Best Practices

### Rule #1: Validation Must Use GameState

**Any validation logic** (`_validate_*` functions) must check **only** GameState, never local phase state.

```gdscript
# ✅ GOOD
func _validate_shoot(action: Dictionary) -> Dictionary:
    var unit = get_unit(unit_id)
    if unit.get("flags", {}).get("cannot_shoot", false):
        return {"valid": false, "errors": ["Unit cannot shoot"]}
    return {"valid": true, "errors": []}

# ❌ BAD
func _validate_shoot(action: Dictionary) -> Dictionary:
    if local_shoot_tracker[unit_id].disabled:  # Not synced!
        return {"valid": false, "errors": ["Unit cannot shoot"]}
    return {"valid": true, "errors": []}
```

### Rule #2: Store Important State in GameState

If state needs to survive phase transitions or work in multiplayer, **put it in GameState via changes**:

```gdscript
func _process_confirm_move(action: Dictionary) -> Dictionary:
    # ... process move ...

    var changes = [
        {
            "op": "set",
            "path": "units.%s.flags.moved" % unit_id,
            "value": true  # ✅ Will be synced!
        }
    ]

    # Local tracking is OK too (for UI, etc.) but can't be used for validation
    active_moves[unit_id]["completed"] = true  # OK for host UI only

    return create_result(true, changes)
```

### Rule #3: Debug Multiplayer State Issues

When something works for host but not client:

1. **Check what you're validating against:**
   - Local phase variable? → ❌ Problem!
   - GameState? → ✅ Probably OK

2. **Add logging:**
```gdscript
print("Validating on peer_id: ", multiplayer.get_unique_id())
print("active_moves: ", active_moves)  # Will differ host vs client
print("GameState flags: ", unit.flags)  # Should be same
```

3. **Verify changes are applied:**
```gdscript
# In _process_* function, ensure changes are returned:
return create_result(true, changes)  # changes = diffs to sync
```

## Common Patterns

### Pattern: Track Active Operations

**Use Case:** Track units currently performing an action (moving, shooting, etc.)

```gdscript
# Local tracking dictionary (OK, not synced)
var active_shoots: Dictionary = {}  # unit_id -> shoot_data

func _process_begin_shoot(action: Dictionary) -> Dictionary:
    var unit_id = action.get("actor_unit_id", "")

    # Local tracking for UI/state management
    active_shoots[unit_id] = {
        "weapons": [],
        "targets": []
    }

    # But mark in GameState for validation/sync
    var changes = [{
        "op": "set",
        "path": "units.%s.flags.shooting_started" % unit_id,
        "value": true  # ✅ Synced!
    }]

    return create_result(true, changes)

func _validate_end_shooting(action: Dictionary) -> Dictionary:
    # ✅ Check synced GameState, not local active_shoots
    var current_player = get_current_player()
    var units = get_units_for_player(current_player)

    for unit_id in units:
        var unit = units[unit_id]
        var started = unit.get("flags", {}).get("shooting_started", false)
        var finished = unit.get("flags", {}).get("shot", false)

        if started and not finished:
            return {"valid": false, "errors": ["Active shoots remain"]}

    return {"valid": true, "errors": []}
```

### Pattern: Phase Completion Check

**Use Case:** Determine if phase can end

```gdscript
func _validate_end_phase(action: Dictionary) -> Dictionary:
    var current_player = get_current_player()
    var units = get_units_for_player(current_player)

    # ✅ Check ALL units via GameState, not local tracking
    for unit_id in units:
        var unit = units[unit_id]

        # Check synced flags
        if not unit.get("flags", {}).get("acted", false):
            return {"valid": false, "errors": ["Not all units have acted"]}

    return {"valid": true, "errors": []}
```

## Testing Multiplayer Validation

1. **Test as host** - should work
2. **Test as client** - if it fails here but works for host → check for local state usage
3. **Add logging** to see what each peer sees
4. **Verify GameState is identical** on both peers after actions

## Related Files

- `autoloads/GameState.gd` - Synchronized game state
- `autoloads/NetworkManager.gd` - Handles action validation and sync
- `phases/MovementPhase.gd` - Example of correct pattern (after fix)
- `40k/ISSUE_102_COMPLETION_SUMMARY.md` - Bug that revealed this pattern

## Key Takeaway

> **In multiplayer games, validation logic must ONLY use synchronized GameState.**
> **Local phase state is fine for UI and temporary tracking, but NEVER for validation.**

---

**Pattern Established:** 2025-10-09
**Applies To:** All phase implementations in multiplayer mode
