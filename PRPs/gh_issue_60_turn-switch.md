# Product Requirements Document: Turn Switch Implementation

## Issue Reference
GitHub Issue #60: Turn Switch

## Feature Description
Implement turn switching functionality after the fight phase is fully completed. This includes adding a "Scoring Phase" (placeholder), "End Turn" functionality, and battle round management to track player turns through a full 5-round Warhammer 40K game.

## Requirements

### Core Requirements
1. **End Fight Phase Button**: Complete the fight phase with all eligible units having fought, then allow transition via "End Fight Phase" button
2. **Scoring Phase**: Add a new placeholder Scoring Phase after Fight Phase with minimal functionality
3. **End Turn Button**: Provide "End Turn" button in Scoring Phase to switch control to the opposing player
4. **Player Turn Switch**: Switch active player control, cycling back to Movement Phase for the opposing player
5. **Battle Round Management**: Track complete battle rounds (Player 1 turn + Player 2 turn = 1 battle round)
6. **Game End Condition**: End game after 5 complete battle rounds

### UI Requirements
1. Clear right-hand panel when entering Scoring Phase
2. Display "End Turn" button prominently in Scoring Phase
3. Show current battle round number in UI
4. Display active player clearly during phase transitions
5. Visual feedback during turn transitions

## Implementation Context

### Current System Analysis

#### Phase Management Architecture
- **PhaseManager.gd** (`40k/autoloads/PhaseManager.gd:29-107`): Orchestrates phase transitions and manages current active phase
- **TurnManager.gd** (`40k/autoloads/TurnManager.gd:19-42`): Manages turn flow and phase transitions, but no battle round tracking
- **GameState.gd** (`40k/autoloads/GameState.gd:263-271`): Stores game state including turn_number and active_player

#### Fight Phase Implementation
- **FightController.gd** (`40k/scripts/FightController.gd:976-979`): Has "End Fight Phase" button that emits "END_FIGHT" signal
- **FightPhase.gd**: Emits `phase_completed` signal when fight sequence is finished

#### Current Phase Flow
```
DEPLOYMENT → MOVEMENT → SHOOTING → CHARGE → FIGHT → MORALE
```

### Required Changes

#### 1. GameState Enhancement
**File**: `40k/autoloads/GameState.gd`
- Add `battle_round` field to meta section 
- Add methods for battle round management:
  - `get_battle_round() -> int`
  - `advance_battle_round() -> void`
  - `is_game_complete() -> bool` (returns true after 5 battle rounds)

#### 2. Phase System Enhancement
**File**: `40k/autoloads/PhaseManager.gd`
- Add `GameStateData.Phase.SCORING` to phase enum
- Register ScoringPhase class in `register_phase_classes()`
- Update `_get_next_phase()` to: `FIGHT → SCORING → MORALE`
- Handle battle round advancement in phase transitions

#### 3. Create Scoring Phase
**New File**: `40k/phases/ScoringPhase.gd`
```gdscript
extends BasePhase
class_name ScoringPhase

# Placeholder phase for scoring functionality
# Currently just provides "End Turn" functionality

func enter_phase(game_state_snapshot: Dictionary) -> void:
    # Minimal setup - just prepare for turn end
    
func get_available_actions() -> Array:
    return [{"type": "END_TURN", "description": "End Turn"}]
    
func execute_action(action: Dictionary) -> Dictionary:
    match action.get("type", ""):
        "END_TURN":
            return _handle_end_turn()
        _:
            return {"success": false, "error": "Unknown action"}
            
func _handle_end_turn() -> Dictionary:
    # Switch players and advance battle round if needed
    var current_player = GameState.get_active_player()
    var next_player = 2 if current_player == 1 else 1
    
    GameState.set_active_player(next_player)
    
    # If Player 2 just finished their turn, advance battle round
    if current_player == 2:
        GameState.advance_battle_round()
    
    emit_signal("phase_completed")
    return {"success": true}
```

#### 4. Update TurnManager
**File**: `40k/autoloads/TurnManager.gd`
- Add battle round change signal: `signal battle_round_advanced(round: int)`
- Handle end of battle round logic in `_on_phase_completed()`
- Add game end detection after 5 battle rounds

#### 5. Create Scoring Controller
**New File**: `40k/scripts/ScoringController.gd`
```gdscript
extends Node2D
class_name ScoringController

# UI controller for Scoring Phase
signal scoring_action_requested(action: Dictionary)

func setup_ui():
    # Clear right panel
    # Add "End Turn" button
    # Show current battle round info
    
func _on_end_turn_pressed():
    emit_signal("scoring_action_requested", {"type": "END_TURN"})
```

#### 6. Update Main.gd
**File**: `40k/scripts/Main.gd`
- Add scoring_controller setup in `setup_phase_controllers()`
- Add SCORING case in phase UI updates
- Connect scoring controller signals

### Technical Implementation Details

#### Battle Round Management
```gdscript
# In GameState.gd
func advance_battle_round() -> void:
    if get_active_player() == 2:  # Player 2 just finished
        state["meta"]["battle_round"] = get_battle_round() + 1
        
func is_game_complete() -> bool:
    return get_battle_round() > 5
    
func get_battle_round() -> int:
    return state["meta"].get("battle_round", 1)
```

#### Phase Transition Logic
```gdscript
# In PhaseManager.gd
func _on_phase_completed() -> void:
    var completed_phase = get_current_phase()
    
    # Check for game end before advancing
    if completed_phase == GameStateData.Phase.SCORING and GameState.is_game_complete():
        _handle_game_end()
        return
        
    emit_signal("phase_completed", completed_phase)
    advance_to_next_phase()
```

### Implementation Tasks

1. **GameState Enhancement** 
   - Add battle_round field and methods
   - Update initialization to include battle_round = 1

2. **Add Scoring Phase to Enum**
   - Update GameStateData.Phase enum
   - Add to PhaseManager registration

3. **Create ScoringPhase Class**
   - Extend BasePhase
   - Implement minimal turn-switching functionality
   - Handle player switching logic

4. **Create ScoringController**
   - UI management for scoring phase
   - End Turn button implementation
   - Battle round display

5. **Update Main Controller**
   - Add scoring controller setup
   - Handle scoring phase UI transitions
   - Clear right panel appropriately

6. **Update TurnManager**
   - Battle round advancement logic
   - Game end detection after 5 rounds
   - Signal emission for UI updates

7. **UI Integration**
   - Phase label updates for "Scoring Phase"
   - Battle round counter display
   - Player turn transition feedback

### Validation Gates

```bash
# Test phase transitions
cd 40k/
godot --headless --script test_turn_switching.gd

# Verify game state persistence
cd 40k/
godot --headless --script test_battle_round_tracking.gd
```

### External Resources

- **Warhammer 40K Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- **Godot Phase Management**: https://docs.godotengine.org/en/4.4/tutorials/scripting/singletons_autoload.html

### Implementation Risks & Considerations

1. **Save/Load Compatibility**: Ensure battle_round field is properly serialized
2. **UI State Management**: Right panel cleanup between phase controllers
3. **Signal Connection Cleanup**: Proper controller disposal to prevent memory leaks
4. **Battle Round Reset**: Consider reset functionality for testing

### Success Criteria

- [ ] Fight phase completes and transitions to Scoring phase
- [ ] Scoring phase shows "End Turn" button
- [ ] Turn switching alternates between Player 1 and Player 2
- [ ] Battle rounds advance correctly (1→2→3→4→5)
- [ ] Game ends after 5 complete battle rounds
- [ ] All existing functionality remains intact
- [ ] Save/load system works with new battle round tracking

### Confidence Score: 8/10

This PRP provides comprehensive context for implementing turn switching with clear technical specifications, existing code patterns to follow, and specific file locations. The modular phase architecture makes this implementation straightforward by following established patterns.
