# Fight Phase Alternating Turn Activation Fix - PRP

## Problem Statement

During the Fight Phase in multiplayer games, Player 2 cannot select units to fight during Player 1's turn, even though the fight phase requires alternating unit activation between both players. This breaks the core Fight Phase mechanic where both players take turns selecting units to fight within the same player turn.

### Current State Issues

**Symptom**: Player 2 sees "ERROR: NetworkManager: Action rejected: SELECT_FIGHTER - Not your turn" when trying to select their unit to fight during Player 1's fight phase.

**Root Cause**: NetworkManager's `validate_action()` function (line 651-655) enforces strict turn ownership:
```gdscript
var active_player = game_state.get_active_player()
if claimed_player != active_player:
    print("NetworkManager: VALIDATION FAILED - not player's turn")
    return {"valid": false, "reason": "Not your turn"}
```

This validation is correct for most phases (Movement, Shooting, etc.) but **breaks Fight Phase**, where players alternate selecting units to activate even though it remains one player's turn.

### Example Scenario

```
Turn: Player 1 (Active)
Phase: Fight

1. Player 1 charges Caladius into Player 2's Battlewagon (Charge Phase)
2. Game enters Player 1's Fight Phase
3. Fights First subphase:
   - Player 1's Caladius has "charged_this_turn" flag
   - Caladius fights (Player 1 selects, piles in, attacks, consolidates)
4. Remaining Combats subphase:
   - Battlewagon is still in engagement range
   - Player 2 SHOULD be able to select Battlewagon to fight back
   - ❌ BUG: NetworkManager rejects Player 2's SELECT_FIGHTER action
   - Error: "Not your turn"
   - Battlewagon cannot fight back
```

## Implementation Blueprint

### Solution Approach

Modify NetworkManager's `validate_action()` to recognize that **Fight Phase uses internal player turn management** and should bypass the standard active_player check for fight actions.

The fix involves:
1. Detecting when we're in the Fight Phase
2. Identifying fight-specific actions that require alternating player participation
3. Delegating turn validation to FightPhase itself (which maintains `current_selecting_player`)

### Critical Context for Implementation

#### Official Warhammer 40k 10th Edition Fight Phase Rules

From https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#FIGHT-PHASE:

**Fight Phase Structure**:
- Divided into two subphases: "Fights First" and "Remaining Combats"
- **Players alternate** selecting units to fight in each subphase
- The active player selects first, then players alternate back and forth
- This alternation happens WITHIN the active player's turn
- Both players can activate units during the active player's Fight Phase

**Key Rule**: "Players alternate selecting eligible units from their armies to fight with, one unit at a time, starting with the active player."

#### Existing Patterns in Codebase

**1. Reactive Actions Pattern** (from NetworkManager.gd:618-624)

NetworkManager already has precedent for **exempting reactive actions from turn validation**:

```gdscript
// NetworkManager.gd lines 618-624
var exempt_actions = [
    "END_DEPLOYMENT",
    "END_PHASE",
    "EMBARK_UNITS_DEPLOYMENT",
    "APPLY_SAVES"  // Reactive action - defender responds during attacker's turn
]
var is_exempt = action_type in exempt_actions

if is_exempt:
    print("NetworkManager: Exempt action '%s' - skipping turn validation (allows reactive actions)" % action_type)
    // Skip turn validation - go straight to game rules validation
```

**Pattern**: `APPLY_SAVES` allows the defender to respond during the attacker's turn because saving throws are reactive.

**Application**: Fight Phase SELECT_FIGHTER is similar - it's a **cross-turn action** where both players participate during one player's turn.

**2. Phase-Level Turn Management** (from FightPhase.gd:42-58, 128)

FightPhase already tracks which player can currently select:

```gdscript
// FightPhase.gd lines 42-43
var current_selecting_player: int = 2  // Which player is currently selecting

// Line 128 - Phase initialization
current_selecting_player = _get_defending_player()

// Lines 260-262 - Phase validates selecting player
if unit.owner != current_selecting_player:
    errors.append("Not your turn to select (Player %d's turn)" % current_selecting_player)
    return {"valid": false, "errors": errors}
```

**Pattern**: Phase maintains its own turn logic and validates it internally.

**Application**: NetworkManager should delegate fight turn validation to FightPhase.

#### Files Requiring Modification

**Primary Change**:
1. `40k/autoloads/NetworkManager.gd` - Expand exempt_actions to include fight actions

**Secondary Changes** (if needed for clarity):
2. `40k/phases/FightPhase.gd` - Ensure validation messages are clear
3. `40k/scripts/FightController.gd` - Ensure player ID is passed correctly in actions

#### External Documentation References

- **Warhammer 40k Core Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#FIGHT-PHASE
  - Fight phase alternating activation rules
  - Fights First vs Remaining Combats subphases

- **Godot 4.4 Multiplayer**: https://docs.godotengine.org/en/4.4/tutorials/networking/high_level_multiplayer.html
  - Authority patterns in multiplayer games
  - When to allow cross-player actions

## Tasks to Complete (In Order)

### Task 1: Add SELECT_FIGHTER to Exempt Actions

**File**: `40k/autoloads/NetworkManager.gd`
**Location**: Lines 618-624
**Change Type**: Expand exempt_actions array

**Current Code**:
```gdscript
var exempt_actions = [
    "END_DEPLOYMENT",
    "END_PHASE",
    "EMBARK_UNITS_DEPLOYMENT",
    "APPLY_SAVES"  // Reactive action - defender responds during attacker's turn
]
```

**Modified Code**:
```gdscript
var exempt_actions = [
    "END_DEPLOYMENT",
    "END_PHASE",
    "EMBARK_UNITS_DEPLOYMENT",
    "APPLY_SAVES",  // Reactive action - defender responds during attacker's turn
    "SELECT_FIGHTER"  // Fight Phase - players alternate during active player's turn
]
```

**Rationale**:
- `SELECT_FIGHTER` is the only action that requires cross-turn participation
- Other fight actions (PILE_IN, ROLL_DICE, CONSOLIDATE) happen during the unit's own activation
- FightPhase.gd line 260-262 validates that the selecting player owns the selected unit
- This delegates authority to the phase, which is consistent with the reactive action pattern

**Verification**:
```bash
# Check syntax
export PATH="$HOME/bin:$PATH"
godot --headless --check-only 40k/autoloads/NetworkManager.gd 2>&1
```

### Task 2: Update Validation Comment for Clarity

**File**: `40k/autoloads/NetworkManager.gd`
**Location**: Line 627
**Change Type**: Update comment to reflect new exemption

**Current Code**:
```gdscript
if is_exempt:
    print("NetworkManager: Exempt action '%s' - skipping turn validation (allows reactive actions)" % action_type)
```

**Modified Code**:
```gdscript
if is_exempt:
    print("NetworkManager: Exempt action '%s' - skipping turn validation (allows reactive/cross-turn actions)" % action_type)
```

**Rationale**: Comment should indicate exemptions cover both reactive actions (APPLY_SAVES) and cross-turn actions (SELECT_FIGHTER).

### Task 3: Ensure FightController Passes Player ID

**File**: `40k/scripts/FightController.gd`
**Location**: Lines 1192-1208
**Verification**: Confirm player ID is included in SELECT_FIGHTER action

**Current Code** (lines 1192-1208):
```gdscript
func _on_fighter_selected_from_dialog(unit_id: String) -> void:
    """Submit SELECT_FIGHTER action when unit selected from dialog"""
    // Get the unit's owner as the player, not the active player
    // In Fight Phase, the selecting player may not be the active player
    var unit = GameState.get_unit(unit_id)
    var player_id = unit.get("owner", GameState.get_active_player())

    // Store for subsequent actions in this activation
    current_fighter_id = unit_id
    current_fighter_owner = player_id

    var action = {
        "type": "SELECT_FIGHTER",
        "unit_id": unit_id,
        "player": player_id  // ✅ CRITICAL: Player ID is passed
    }
    emit_signal("fight_action_requested", action)
```

**Status**: ✅ Already correct - no changes needed

**Verification**: The action includes the unit owner's player ID, which FightPhase validates against `current_selecting_player`.

### Task 4: Add Defensive Logging in FightPhase

**File**: `40k/phases/FightPhase.gd`
**Location**: Lines 245-263
**Change Type**: Add debug logging for validation

**Current Code** (lines 260-262):
```gdscript
if unit.owner != current_selecting_player:
    errors.append("Not your turn to select (Player %d's turn)" % current_selecting_player)
    return {"valid": false, "errors": errors}
```

**Modified Code**:
```gdscript
if unit.owner != current_selecting_player:
    var error_msg = "Not your turn to select (Player %d's turn, you are Player %d)" % [current_selecting_player, unit.owner]
    errors.append(error_msg)
    log_phase_message("VALIDATION FAILED: %s tried to select unit owned by Player %d during Player %d's selection" % [
        unit.owner, unit.owner, current_selecting_player
    ])
    return {"valid": false, "errors": errors}
```

**Rationale**: Clearer error messages help debug multiplayer issues if validation still fails after NetworkManager fix.

### Task 5: Test in Multiplayer

**Test Scenario**:

```
Setup:
- Host (Player 1): Adeptus Custodes with Caladius
- Client (Player 2): Orks with Battlewagon
- Units in engagement range (1" apart)

Steps:
1. Host charges Caladius into Battlewagon (Charge Phase)
2. Enter Fight Phase (still Player 1's turn)
3. Fights First Subphase:
   - FightSelectionDialog appears
   - Shows Caladius with "Fights First" indicator
   - Host (Player 1) selects Caladius
   - ✅ PASS: Unit selected successfully
   - Caladius completes activation (pile-in, attack, consolidate)

4. Remaining Combats Subphase:
   - FightSelectionDialog appears again
   - Shows Battlewagon available for Player 2
   - Client (Player 2) attempts to select Battlewagon
   - ✅ PASS: NO "Not your turn" error (fixed by Task 1)
   - ✅ PASS: FightPhase validates unit owner matches current_selecting_player
   - ✅ PASS: Battlewagon activates and fights back
```

**Expected Logs (After Fix)**:
```
NetworkManager: submit_action called for type: SELECT_FIGHTER
NetworkManager: is_networked() = true
NetworkManager: Host mode - validating and applying
NetworkManager: claimed_player=2, peer_player=2 (from peer_to_player_map)
NetworkManager: Exempt action 'SELECT_FIGHTER' - skipping turn validation (allows reactive/cross-turn actions)
NetworkManager: Calling phase.validate_action()
FightPhase: Validating SELECT_FIGHTER for unit U_BATTLEWAGON
FightPhase: Unit owner (2) matches current_selecting_player (2) ✅
FightPhase: VALIDATION PASSED
NetworkManager: Host applied action, result.success = true
FightPhase: Player 2 selects U_BATTLEWAGON to fight
FightPhase: Emitting pile_in_required signal
```

## Validation Gates

### Automated Testing

```bash
# 1. Syntax check
export PATH="$HOME/bin:$PATH"
cd /Users/robertocallaghan/Documents/claude/godotv2/40k
godot --headless --check-only autoloads/NetworkManager.gd 2>&1
godot --headless --check-only phases/FightPhase.gd 2>&1
godot --headless --check-only scripts/FightController.gd 2>&1

# 2. Unit tests (if they exist)
godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://40k/tests/unit/test_fight_subphases.gd -gexit

# 3. Integration tests
godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://40k/tests/integration/test_fight_phase_alternation.gd -gexit
```

### Manual Validation Checklist

**Pre-Fix State** (Verify Bug Exists):
- [ ] Start multiplayer game (host + client)
- [ ] Progress to Fight Phase
- [ ] Client attempts to select unit
- [ ] ❌ FAILS: "Not your turn" error appears

**Post-Fix State** (Verify Fix Works):
- [ ] Apply NetworkManager.gd changes
- [ ] Restart game instances
- [ ] Progress to Fight Phase
- [ ] **Test 1**: Host selects unit in Fights First
  - [ ] ✅ Unit activates successfully
- [ ] **Test 2**: Client selects unit in Remaining Combats
  - [ ] ✅ NO "Not your turn" error
  - [ ] ✅ Unit activates successfully
  - [ ] ✅ Both players see dice results
  - [ ] ✅ Damage applied on both sides
- [ ] **Test 3**: Players alternate multiple times
  - [ ] ✅ Selection switches back and forth correctly
  - [ ] ✅ Each player can only select their own units
  - [ ] ✅ FightPhase validation catches wrong-player selections

## Error Handling Strategy

### Validation Flow After Fix

```
┌─────────────────────────────────────────────────────────────┐
│ NetworkManager.validate_action()                            │
│                                                              │
│ 1. Check if action is in exempt_actions                    │
│    - SELECT_FIGHTER? YES → Skip turn validation            │
│                                                              │
│ 2. Check player authority (always enforced)                │
│    - Does peer_id map to claimed player_id? ✅              │
│                                                              │
│ 3. Delegate to phase validation                             │
│    FightPhase.validate_action()                             │
│    - Is unit in eligible list? ✅                            │
│    - Does unit owner match current_selecting_player? ✅      │
│    - Is unit already fought? ❌ → Reject                    │
│    - Is unit in engagement range? ✅                         │
│                                                              │
│ 4. Execute action if valid                                  │
│    FightPhase._process_select_fighter()                     │
│    - Set active_fighter_id                                  │
│    - Emit pile_in_required signal                           │
│    - Return success with diffs                              │
└─────────────────────────────────────────────────────────────┘
```

### Edge Cases Handled

1. **Wrong Player Selects Enemy Unit**:
   - NetworkManager passes (exempt action)
   - FightPhase validates unit.owner == current_selecting_player
   - ❌ Rejects with clear error message

2. **Player Selects Unit Out of Turn** (within subphase):
   - NetworkManager passes (exempt action)
   - FightPhase validates unit is in current subphase's eligible list
   - ❌ Rejects: "Unit not eligible in this subphase"

3. **Player Selects Already-Fought Unit**:
   - NetworkManager passes (exempt action)
   - FightPhase checks `units_that_fought` list
   - ❌ Rejects: "Unit has already fought"

4. **Single-Player Mode**:
   - NetworkManager.is_networked() = false
   - Action bypasses NetworkManager entirely
   - Goes directly to PhaseManager → FightPhase
   - ✅ Works as before (no regression)

## Common Pitfalls to Avoid

1. **Don't Exempt All Fight Actions**: Only SELECT_FIGHTER needs exemption. Other actions (PILE_IN, ROLL_DICE) happen during the unit's own activation and use the unit owner's player ID.

2. **Don't Remove Phase Validation**: FightPhase must still validate that the selecting player owns the selected unit.

3. **Don't Confuse Active Player vs Selecting Player**:
   - `active_player` = whose turn it is (e.g., Player 1)
   - `current_selecting_player` = who can select units right now (may be Player 2)
   - Fight Phase alternates `current_selecting_player` while `active_player` stays the same

4. **Test Both Subphases**: Verify alternation works in both Fights First AND Remaining Combats.

5. **Verify Subsequent Actions**: After selecting a unit, ensure PILE_IN, ASSIGN_ATTACKS, ROLL_DICE, and CONSOLIDATE still work for the selecting player.

## Implementation Verification Checklist

### Core Functionality
- [ ] SELECT_FIGHTER added to exempt_actions
- [ ] NetworkManager skips turn validation for SELECT_FIGHTER
- [ ] FightPhase validates unit owner matches current_selecting_player
- [ ] Players alternate selecting units correctly
- [ ] Both Fights First and Remaining Combats work

### Multiplayer Synchronization
- [ ] Host validates SELECT_FIGHTER from client
- [ ] Client receives and applies SELECT_FIGHTER results
- [ ] Both players see same unit highlighted
- [ ] Both players see same dice results
- [ ] Game state stays synchronized

### Error Handling
- [ ] Wrong-player selection rejected by FightPhase
- [ ] Clear error messages appear in logs
- [ ] UI shows feedback when selection fails
- [ ] No silent failures or hangs

### Regression Testing
- [ ] Single-player fight phase still works
- [ ] Other phases (Movement, Shooting) unaffected
- [ ] APPLY_SAVES still works (other exempt action)
- [ ] END_PHASE, END_DEPLOYMENT still work

## Success Metrics

- Player 2 can select units during Player 1's Fight Phase
- No "Not your turn" errors for SELECT_FIGHTER
- Players alternate correctly in both subphases
- FightPhase validation catches invalid selections
- Multiplayer synchronization maintained
- No regressions in other phases or single-player mode

## Confidence Score: 9/10

**High confidence due to**:
- Clear root cause identified in NetworkManager line 653-655
- Existing pattern for exempt actions (APPLY_SAVES)
- FightPhase already has correct validation logic
- Minimal code changes (1 line addition + 1 comment update)
- Well-tested FightPhase implementation
- Clear success/failure criteria

**Point deducted for**:
- Need to verify subsequent actions (PILE_IN, etc.) still work correctly
- Potential for edge cases in player alternation with disconnects

## Additional Notes

### Key Design Decisions

1. **Why SELECT_FIGHTER and not all fight actions?**
   - SELECT_FIGHTER is the only action that crosses player boundaries
   - PILE_IN, ROLL_DICE, CONSOLIDATE all use the activated unit's owner
   - Keeps exemption list minimal and security-focused

2. **Why delegate to phase validation?**
   - Phase knows the internal state (current_selecting_player, subphase)
   - Maintains separation of concerns
   - Follows existing pattern from APPLY_SAVES

3. **Why not change the active_player during Fight Phase?**
   - Would break turn structure (Player 1's turn should remain Player 1's turn)
   - Would confuse UI (top bar shows whose turn it is)
   - Would break phase transitions (next phase should be Player 1's phase)

### Integration Points

- **NetworkManager**: Exempts SELECT_FIGHTER from active_player check
- **FightPhase**: Validates unit owner matches current_selecting_player
- **FightController**: Passes correct player ID in action
- **GameManager**: Already delegates fight actions to phase (no changes needed)

### Future Enhancements

- Add visual indicator showing whose turn to select (green highlight)
- Show "Waiting for opponent..." message when not your selection turn
- Add spectator-friendly overlay explaining alternating activation
- Consider extending pattern to other phases if needed (unlikely)

This PRP provides a minimal, targeted fix that enables fight phase alternating activation while maintaining security and validation integrity.
