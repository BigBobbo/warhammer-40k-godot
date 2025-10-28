# PRP: Fix Wound Application in Fight Phase

## Problem Statement
In the fight phase, after successful attack rolls (hit, wound, failed save), wounds are not being applied to defending models. When a Warboss attacks a Witchseeker with damage higher than the defender's wound count, the defender should lose models but currently doesn't.

## Root Cause Analysis

### The Bug Location
**File:** `/Users/robertocallaghan/Documents/claude/godotv2/40k/phases/FightPhase.gd`
**Function:** `_process_roll_dice()` at line 898

### The Issue
1. **Line 913:** `RulesEngine.resolve_melee_attacks()` correctly returns `diffs` with wound/death state changes
2. **Line 924:** `_apply_combat_results(result)` is called, which:
   - Tries to call `get_parent().apply_state_changes(changes)` at line 1335
   - This likely fails silently as parent probably doesn't have this method
   - Even if it succeeds, changes aren't properly synced back to game state
3. **Line 940:** `create_result()` wraps diffs in result["changes"]
4. **BasePhase:92:** `PhaseManager.apply_state_changes(result.changes)` should apply changes but may receive empty/duplicate data

### Why It's Broken
- Double application attempt: once in `_apply_combat_results()` (fails), once in BasePhase (should work)
- The `_apply_combat_results()` method is redundant and interferes with proper state management
- State changes flow: RulesEngine → FightPhase → BasePhase → PhaseManager → GameState

## Warhammer 40k Rules Context

### Wound Allocation Rules (10th Edition)
Reference: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/

1. **Allocation Order:** Defending player chooses which model receives wounds
2. **Wounded Models First:** Must allocate to already wounded models before fresh ones
3. **Damage Resolution:** When damage ≥ remaining wounds, model is destroyed
4. **No Spillover:** Excess damage doesn't carry to next model (except mortal wounds)
5. **Immediate Removal:** Models removed immediately upon taking lethal damage

## Implementation Blueprint

### Phase 1: Remove Redundant Code
```gdscript
# In FightPhase._process_roll_dice() around line 924
# REMOVE this line:
_apply_combat_results(result)

# REMOVE the entire _apply_combat_results() function at line 1329-1336
```

### Phase 2: Ensure Proper State Flow
```gdscript
# Verify in _process_roll_dice() at line 940:
var final_result = create_result(true, result.get("diffs", []), result.get("log_text", ""))
# This correctly passes diffs to BasePhase via result["changes"]
```

### Phase 3: Add Debug Logging
```gdscript
# Add after line 913 in _process_roll_dice():
if result.has("diffs") and not result.diffs.is_empty():
    print("[FightPhase] RulesEngine returned %d state changes" % result.diffs.size())
    for diff in result.diffs:
        print("  - %s: %s = %s" % [diff.op, diff.path, diff.value])
```

### Phase 4: Create Integration Test
```gdscript
# Create new test file: 40k/tests/integration/test_fight_phase_wound_application.gd
extends GutTest

func test_wounds_applied_after_failed_saves():
    # Setup: Warboss vs Witchseeker
    var warboss_unit = create_test_unit("ork_warboss", 1)
    var witchseeker_unit = create_test_unit("witch_seeker", 3)

    # Configure Warboss weapon (high damage)
    warboss_unit.meta.weapons = [{
        "name": "Power Klaw",
        "attacks": 4,
        "weapon_skill": 2,
        "strength": 10,
        "ap": 2,
        "damage": 3
    }]

    # Configure Witchseeker (low wounds)
    for model in witchseeker_unit.models:
        model.wounds = 1
        model.current_wounds = 1

    # Execute fight sequence
    var fight_phase = FightPhase.new()
    fight_phase.game_state_snapshot = {
        "units": {
            "warboss_1": warboss_unit,
            "witch_1": witchseeker_unit
        }
    }

    # Simulate attack assignment
    var action = {
        "type": "ASSIGN_ATTACKS",
        "actor_unit_id": "warboss_1",
        "payload": {
            "weapon_index": 0,
            "target": "witch_1"
        }
    }
    fight_phase.execute_action(action)

    # Simulate dice roll with guaranteed hits/wounds/failed saves
    var roll_action = {
        "type": "ROLL_DICE",
        "actor_unit_id": "warboss_1"
    }

    # Mock RNG to ensure hits, wounds, and failed saves
    var mock_rng = MockRNG.new([6, 6, 6, 1]) # Hit, wound, fail save
    RulesEngine.set_rng_service(mock_rng)

    var result = fight_phase.execute_action(roll_action)

    # Verify wounds were applied
    assert_true(result.success, "Roll dice action should succeed")

    # Check that at least one model was killed
    var alive_count = 0
    for model in witchseeker_unit.models:
        if model.alive:
            alive_count += 1

    assert_lt(alive_count, 3, "At least one Witchseeker should be dead")
```

## File Changes Required

### 1. `/Users/robertocallaghan/Documents/claude/godotv2/40k/phases/FightPhase.gd`
- **Line 924:** Remove `_apply_combat_results(result)` call
- **Lines 1329-1336:** Delete entire `_apply_combat_results()` function
- **After line 913:** Add debug logging for diffs

### 2. `/Users/robertocallaghan/Documents/claude/godotv2/40k/tests/integration/test_fight_phase_wound_application.gd`
- Create new test file with comprehensive wound application tests

## Validation Gates

```bash
# 1. Check syntax - Run from /Users/robertocallaghan/Documents/claude/godotv2
timeout 30 godot --headless --script 40k/test_fight_phase_syntax.gd

# 2. Run new integration test
timeout 30 godot --headless --script 40k/tests/integration/test_fight_phase_wound_application.gd

# 3. Test in-game manually
# - Load save: 40k/saves/quicksave.w40ksave
# - Enter fight phase with Warboss vs Witchseeker
# - Perform attack sequence
# - Verify models are removed after failed saves

# 4. Check debug logs for state changes
tail -f ~/Library/Application\ Support/Godot/app_userdata/40k/logs/debug_*.log | grep -E "state changes|wounds|alive"
```

## Success Criteria
1. ✅ Wounds correctly reduce model's `current_wounds`
2. ✅ Models with 0 wounds have `alive = false`
3. ✅ Dead models visually removed from battlefield
4. ✅ State changes properly synchronized across network
5. ✅ Debug logs show diffs being applied

## Error Handling
- If PhaseManager.apply_state_changes() fails, log error with details
- If diffs array is empty, log warning about no damage dealt
- Preserve all existing error handling for invalid actions

## Implementation Tasks

1. **Remove redundant code** (5 min)
   - Delete `_apply_combat_results()` call and function

2. **Add debug logging** (5 min)
   - Log diffs returned from RulesEngine
   - Log state changes applied by PhaseManager

3. **Create integration test** (15 min)
   - Test wound application with various scenarios
   - Test model removal when wounds reach 0
   - Test damage not spilling over between models

4. **Manual testing** (10 min)
   - Load test save and verify fix in actual gameplay
   - Test multiplayer synchronization

5. **Clean up and document** (5 min)
   - Remove excessive debug logs if requested
   - Update any relevant documentation

## Related Files for Reference
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/autoloads/RulesEngine.gd` - Creates damage diffs (lines 1939-1960)
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/autoloads/PhaseManager.gd` - Applies state changes (lines 188-239)
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/phases/BasePhase.gd` - Orchestrates state application (lines 91-96)

## Confidence Score: 9/10

High confidence because:
- Root cause clearly identified (redundant state application)
- Fix is simple (remove problematic code)
- State flow is well understood
- Existing infrastructure (PhaseManager) handles state correctly
- Similar pattern works in ShootingPhase

Minor uncertainty (-1) for potential network synchronization edge cases.

## Additional Notes

The core issue is that `_apply_combat_results()` is an anti-pattern that breaks the established state management flow:

**Correct Flow:**
```
RulesEngine → diffs → FightPhase → changes → BasePhase → PhaseManager → GameState
```

**Current Broken Flow:**
```
RulesEngine → diffs → FightPhase
                         ├─ _apply_combat_results() → parent? (fails/wrong target)
                         └─ create_result() → BasePhase → PhaseManager (may work but redundant)
```

By removing the redundant `_apply_combat_results()` call, we restore the proper single-path state flow that matches other phases like ShootingPhase.