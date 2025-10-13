# Saves and Damage Allocation GUI Implementation PRP
**Version**: 1.0
**Date**: 2025-10-11
**Scope**: Interactive save rolls and damage allocation for defending player

## 1. Executive Summary

This PRP defines the implementation of an interactive saves and damage allocation system for the Warhammer 40K 10th edition game. Currently, the system auto-resolves all saves without player interaction. This implementation will transfer control to the defending player, allowing tactical decisions about save rolls, wound allocation, and defensive abilities.

**Key Decisions Made:**
- **Control Transfer**: System will pause and transfer control to defender when wounds are inflicted
- **Allocation Modes**: Both auto-allocation (rules-compliant) and manual allocation will be supported
- **Implementation Phases**: Three-phase approach from MVP to full implementation
- **Multiplayer First**: Design assumes networked play with proper state synchronization

## 2. Current State Analysis

### 2.1 Existing Implementation
- `RulesEngine.gd` contains save calculation logic (`_calculate_save_needed()`)
- Damage allocation happens automatically in `_resolve_assignment()`
- No player interaction during save phase
- Cover detection exists but is automated
- Invulnerable saves partially implemented but not exposed to UI

### 2.2 Gaps to Address
- No control transfer to defending player
- No manual allocation options
- No re-roll interface
- No Feel No Pain implementation
- No stratagem/ability integration
- Limited feedback on save results

## 3. Core Requirements

### 3.1 Rules Compliance (10th Edition)
- **Wound Allocation Priority**: Previously wounded models must be allocated wounds first
- **Save Characteristics**: Models use best available save (armor or invulnerable)
- **Damage Spillover**: Excess damage from multi-damage weapons carries to next model
- **Feel No Pain**: Rolled after failed saves, per wound
- **Mortal Wounds**: Cannot be saved against (except FNP)
- **Cover**: +1 to armor saves when in cover

### 3.2 Architecture Requirements
- Integrate with existing Phase-Controller pattern
- Full NetworkManager support for multiplayer
- Deterministic dice rolling through RNGService
- State preservation for save/load
- Clear handoff between attacker and defender

## 4. GUI Layout Design

### 4.1 Main Interface Structure

```
┌────────────────────────────────────────────────┐
│           INCOMING ATTACK - DEFEND!            │
├────────────────────────────────────────────────┤
│ Attacker: Space Marine Intercessors            │
│ Weapon: Bolt Rifles (AP-1, Damage 1)           │
│ Wounds to Save: 5                              │
├────────────────────────────────────────────────┤
│                SAVE OPTIONS                     │
│ ┌─────────────────────────────────────────────┐│
│ │ Unit: Ork Boyz (10 models, 2 wounded)       ││
│ │                                              ││
│ │ Save Stats:                                 ││
│ │ • Armor Save: 5+ (modified to 6+ by AP-1)   ││
│ │ • Invulnerable Save: None                    ││
│ │ • Feel No Pain: None                         ││
│ │ • Cover Bonus: +1 (if applicable)           ││
│ └─────────────────────────────────────────────┘│
├────────────────────────────────────────────────┤
│              ALLOCATION MODE                    │
│ ┌─────────────────────────────────────────────┐│
│ │ ○ Auto-Allocate (Rules Compliant)           ││
│ │ ● Manual Allocation                         ││
│ └─────────────────────────────────────────────┘│
├────────────────────────────────────────────────┤
│             WOUND ALLOCATION                    │
│ ┌─────────────────────────────────────────────┐│
│ │ Model Selection (Click to allocate):        ││
│ │                                              ││
│ │ [Boy #1] [Boy #2*] [Boy #3] [Boy #4]        ││
│ │ HP: 1/1   HP: 1/2   HP: 1/1  HP: 1/1        ││
│ │                                              ││
│ │ [Boy #5] [Boy #6] [Boy #7] [Boy #8]         ││
│ │ HP: 1/1   HP: 1/1   HP: 1/1  HP: 1/1        ││
│ │                                              ││
│ │ [Boy #9] [Boy #10]                           ││
│ │ HP: 1/1   HP: 1/1                            ││
│ │                                              ││
│ │ * = Previously wounded (must allocate first) ││
│ │ Selected: Boy #2                             ││
│ │ Wounds Allocated to This Model: 1/5         ││
│ └─────────────────────────────────────────────┘│
├────────────────────────────────────────────────┤
│              SAVE ROLL QUEUE                    │
│ ┌─────────────────────────────────────────────┐│
│ │ Save #1 → Boy #2                             ││
│ │ Need: 6+ | Roll: [ROLL] | □ Re-roll         ││
│ │                                              ││
│ │ Save #2 → [Select Model]                     ││
│ │ Save #3 → [Select Model]                     ││
│ │ Save #4 → [Select Model]                     ││
│ │ Save #5 → [Select Model]                     ││
│ └─────────────────────────────────────────────┘│
├────────────────────────────────────────────────┤
│                  ACTIONS                        │
│ [Roll All Saves] [Roll Next] [Apply Damage]    │
│ [Use Stratagem] [Use Command Re-roll]          │
└────────────────────────────────────────────────┤
│                 DICE LOG                        │
│ Save 1: Rolled 4 vs 6+ - FAILED               │
│ Boy #2 takes 1 damage (destroyed)              │
└────────────────────────────────────────────────┘
```

### 4.2 Component Breakdown

#### Attack Summary Panel
- Displays attacking unit and weapon stats
- Shows AP, Damage, and special rules
- Total wounds requiring saves

#### Save Options Panel
- Base save value with modifiers
- Invulnerable save (if applicable)
- Feel No Pain value (if applicable)
- Cover status and bonus
- Special defensive rules

#### Allocation Mode Toggle
- **Auto-Allocate**: System follows rules strictly
- **Manual Allocation**: Player tactical choice

#### Model Grid View
- Visual representation of each model
- Current/max wounds display
- Wounded model indicators (*)
- Cover status indicators
- Click-to-select interface
- Death animations on model removal

#### Save Roll Queue
- Ordered list of saves to make
- Model assignment for each save
- Individual roll controls
- Re-roll checkboxes
- Pass/fail indicators

#### Action Buttons
- **Roll All Saves**: Batch resolution
- **Roll Next**: Individual resolution
- **Apply Damage**: Confirm allocation
- **Use Stratagem**: Defensive abilities
- **Command Re-roll**: CP spending

#### Results Log
- Dice roll history
- Damage application tracking
- Model casualty reports
- Special rule triggers

## 5. User Flow

### 5.1 Phase 1: Attack Notification
1. Attacker completes wound rolls
2. System calculates total wounds
3. Control transfers to defender
4. Defender sees incoming attack details

### 5.2 Phase 2: Allocation Setup
1. System identifies wounded models
2. Wounded models highlighted as priority
3. Player selects allocation mode
4. If manual, player assigns wounds to models

### 5.3 Phase 3: Save Resolution
For each allocated wound:
1. Display save requirement (with modifiers)
2. Player triggers dice roll
3. Apply any re-rolls
4. Show pass/fail result
5. Queue failed saves for damage

### 5.4 Phase 4: Damage Application
For each failed save:
1. Apply damage to allocated model
2. Check for model destruction
3. Handle spillover damage
4. Trigger Feel No Pain (if applicable)
5. Update visual state

### 5.5 Phase 5: Completion
1. Display casualty summary
2. Return control to attacker
3. Continue shooting sequence

## 6. Technical Implementation

### 6.1 New Components

```gdscript
# SaveController.gd - Main save resolution controller
extends Node2D
class_name SaveController

signal saves_resolved(casualties: int)
signal control_returned()

var defending_unit_id: String
var incoming_wounds: int
var weapon_profile: Dictionary
var allocation_queue: Array = []

# SaveDialog.gd - Modal dialog for save interface
extends PopupPanel
class_name SaveDialog

var model_grid: GridContainer
var save_queue: ItemList
var dice_log: RichTextLabel

# ModelAllocationGrid.gd - Visual model selector
extends GridContainer
class_name ModelAllocationGrid

signal model_selected(model_index: int)
var model_cards: Array = []

# SaveRollQueue.gd - Manages save order
extends VBoxContainer
class_name SaveRollQueue

var pending_saves: Array = []
var completed_saves: Array = []
```

### 6.2 Integration Points

#### RulesEngine Extensions
```gdscript
# Add interactive save resolution
static func begin_interactive_saves(wounds: int, target_unit: Dictionary, weapon: Dictionary) -> Dictionary:
    return {
        "wounds_to_save": wounds,
        "save_profile": _calculate_save_needed(...),
        "allocation_requirements": _get_allocation_requirements(target_unit)
    }

# Validate allocation choices
static func validate_allocation(allocation: Array, unit: Dictionary) -> Dictionary:
    # Check wounded model priority
    # Verify legal targets
    return {"valid": bool, "errors": Array}
```

#### ShootingPhase Modifications
```gdscript
# Add defender interaction state
var awaiting_defender: bool = false
var defender_allocation: Dictionary = {}

# New action types
"BEGIN_SAVES": _process_begin_saves,
"ALLOCATE_WOUND": _process_allocate_wound,
"ROLL_SAVE": _process_roll_save,
"APPLY_DAMAGE": _process_apply_damage
```

#### NetworkManager Protocol
```gdscript
# New RPC calls for defender actions
@rpc("any_peer", "call_local", "reliable")
func request_save_allocation(wounds: int, defender_id: int):
    # Transfer control to defender

@rpc("any_peer", "call_local", "reliable")
func submit_allocation(allocation: Dictionary):
    # Validate and apply allocation
```

### 6.3 State Management

```gdscript
# Save resolution state
var save_state = {
    "phase": "awaiting_defender",  # awaiting_defender, allocating, rolling, applying
    "wounds_remaining": 0,
    "wounds_allocated": [],
    "saves_made": [],
    "casualties": [],
    "defender_id": -1
}
```

## 7. Implementation Phases

### Phase 1: MVP (Week 1-2)
- [x] Basic wound allocation UI
- [ ] Rules-compliant auto-allocation
- [ ] Batch save rolling
- [ ] Simple damage application
- [ ] Network control transfer
- [ ] Result display

### Phase 2: Enhanced (Week 3-4)
- [ ] Manual allocation mode
- [ ] Individual save control
- [ ] Command re-rolls
- [ ] Cover detection and display
- [ ] Visual model health bars
- [ ] Animation feedback

### Phase 3: Complete (Week 5-6)
- [ ] Invulnerable saves
- [ ] Feel No Pain rolls
- [ ] Stratagem integration
- [ ] CP spending interface
- [ ] Mortal wound handling
- [ ] Complex damage spillover
- [ ] Saving throw modifiers

## 8. Testing Requirements

### 8.1 Unit Tests
- Allocation validation logic
- Save calculation with all modifiers
- Damage spillover mechanics
- FNP roll sequences
- Cover detection accuracy

### 8.2 Integration Tests
- Control handoff in multiplayer
- State synchronization
- Save/load during resolution
- Timeout handling
- Disconnection recovery

### 8.3 UI Tests
- Model selection responsiveness
- Dice animation timing
- Queue management
- Visual state updates
- Touch/click accuracy

### 8.4 Gameplay Tests
- Rules compliance verification
- Edge case handling (last model, etc.)
- Performance with large units
- Network latency tolerance

## 9. Performance Considerations

- Batch network messages for allocation
- Optimize model grid rendering for 20+ models
- Cache save calculations
- Preload dice animations
- Limit visual effects on low-end devices

## 10. Multiplayer Considerations

### 10.1 Control Flow
- Smooth handoff with loading indicator
- "Waiting for Defender" message
- Configurable timeout (30-60 seconds)
- Auto-resolution fallback

### 10.2 Synchronization
- Host validates all allocations
- Deterministic dice on host
- Broadcast results to all clients
- Spectator view updates

### 10.3 Disconnection Handling
- Store partial allocation state
- Allow reconnection resume
- AI takeover option
- Timeout auto-resolution

## 11. Configuration Options

```gdscript
# User settings
var save_settings = {
    "auto_allocate": true,  # Default to auto
    "batch_rolling": true,  # Roll similar saves together
    "show_animations": true,
    "timeout_seconds": 45,
    "quick_resolve": false  # Skip to results
}
```

## 12. Success Metrics

- Allocation decision time < 30 seconds average
- Save resolution < 10 seconds per unit
- Zero desync issues in multiplayer
- Rules violations = 0
- Player satisfaction > 4/5

## 13. Open Questions

1. **Quick Resolve**: Should there be an instant resolution option that uses optimal allocation?
   - *Recommendation*: Yes, for casual play

2. **Batch Rolling**: Allow grouping identical saves or force individual?
   - *Recommendation*: User preference setting

3. **Undo Support**: Allow allocation changes before damage?
   - *Recommendation*: Yes, until "Apply Damage" clicked

4. **Competitive Timer**: Enforce time limits?
   - *Recommendation*: Optional tournament mode

5. **Notification System**: How to alert defender?
   - *Recommendation*: Audio cue + visual flash + OS notification

## 14. Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Network latency causes poor UX | High | Local prediction with rollback |
| Complex UI overwhelming | Medium | Progressive disclosure, tutorials |
| Rules edge cases | Medium | Extensive testing, rules reference |
| Performance with hordes | Low | LOD system for large units |

## 15. Dependencies

- Existing RulesEngine save calculation
- NetworkManager RPC system
- GameState unit/model tracking
- UI theme and components
- Dice animation system

## 16. Migration Path

1. Keep existing auto-resolution as fallback
2. Add feature flag for new system
3. Beta test with subset of players
4. Gradual rollout with feedback
5. Full deployment with auto-resolve option

## 17. Documentation Requirements

- Player guide for allocation strategies
- Video tutorial for UI interaction
- Rules reference integration
- Tooltips for all stats/modifiers
- Changelog for updates

## 18. Future Enhancements

- Battle record tracking (saves made/failed)
- Tactical advisor suggestions
- Replay system for save sequences
- Custom death animations per faction
- Achievement system for epic saves

## 19. Appendix: Rules References

- Core Rules: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- Saving Throws: Core Rules Section 18
- Damage Allocation: Core Rules Section 19
- Feel No Pain: Core Rules Section 20

## 20. Version History

- **v1.0** (2025-10-11): Initial PRP creation

## 21. Sign-off

- [ ] Product Owner
- [ ] Tech Lead
- [ ] UX Designer
- [ ] QA Lead
- [ ] Network Engineer