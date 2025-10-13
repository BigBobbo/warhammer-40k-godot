# Weapon Order Selection - Quick Reference

## Overview

Add tactical weapon sequencing to the shooting phase. When a unit has multiple weapon types, the attacker chooses the order they fire, with saves resolved after each weapon.

## Key User Experience

### Current Flow (Single Weapon)
```
Select unit → Assign target → Confirm → Roll dice → Make saves → Done
```

### New Flow (Multiple Weapons)
```
Select unit → Assign targets → Confirm → Choose weapon order →
For each weapon:
  → Roll dice → Make saves → [Reorder remaining] →
Done
```

## Core Features

1. **Weapon Order Dialog** (only when 2+ weapon types)
   - Default: Highest damage first
   - Reorderable with up/down arrows
   - "Fast Roll All" option (current behavior)
   - "Start Sequence" option (new tactical mode)

2. **Sequential Resolution**
   - Each weapon fires completely before next
   - Saves made after each weapon
   - Progress display shows status

3. **Dynamic Reordering**
   - After each weapon, attacker can reorder remaining weapons
   - Cannot change already-fired weapons
   - See previous results before deciding

4. **Enhanced Context**
   - Save dialog shows "Weapon 2 of 3"
   - Save dialog shows previous casualties
   - Progress tracker always visible

## Quick Design Decisions

| Question | Answer |
|----------|--------|
| When does dialog appear? | Only with 2+ weapon types |
| User setting for fast roll? | No - choice per shooting |
| Default weapon order? | Highest damage first |
| Can reorder mid-sequence? | Yes, after each weapon |
| Can change already-fired? | No, only remaining |
| Button between weapons? | "Continue to Next Weapon" |
| Spectator view? | Real-time with dice rolls |

## Implementation Priority

### Phase 1 (Week 1) - Core MVP
- WeaponOrderDialog with up/down arrows
- Basic sequential resolution
- Simple progress display
- Single-player testing

### Phase 2 (Week 2) - Full Features
- Fast roll option
- Mid-sequence reordering
- Enhanced progress UI
- Previous results display

### Phase 3 (Week 2-3) - Save Dialog
- "Weapon X of Y" in title
- Previous casualties summary
- Context-aware styling

### Phase 4 (Week 3) - Multiplayer
- Network synchronization
- Spectator view
- Player-specific dialogs
- Disconnection handling

### Phase 5 (Week 4) - Polish
- Edge cases (target destroyed, etc.)
- Save/load support
- Performance optimization
- Final testing

## Key Files to Create/Modify

### NEW Files
- `40k/scripts/WeaponOrderDialog.gd` - Weapon ordering UI (520 lines)
- `40k/tests/unit/test_weapon_ordering.gd` - Unit tests
- `40k/tests/unit/test_weapon_sequence.gd` - Integration tests

### MODIFY Files
- `40k/phases/ShootingPhase.gd` - Add sequential resolution logic (~400 new lines)
- `40k/scripts/ShootingController.gd` - Add progress UI & signal handlers (~200 new lines)
- `40k/scripts/SaveDialog.gd` - Add sequence context (~100 new lines)

## Data Structures

### Resolution State (ShootingPhase)
```gdscript
resolution_state = {
    "mode": "sequential",  # or "fast"
    "weapon_order": [...],  # Ordered assignments
    "current_index": 1,  # Currently resolving
    "completed_weapons": [...],  # Results so far
    "awaiting_saves": false,
    "awaiting_reorder": false
}
```

### New Actions
```gdscript
# Start sequence
{
    "type": "RESOLVE_WEAPON_SEQUENCE",
    "payload": {
        "weapon_order": [...],
        "fast_roll": false
    }
}

# Continue after reordering
{
    "type": "CONTINUE_WEAPON_SEQUENCE",
    "payload": {
        "updated_order": [...]  # Remaining weapons only
    }
}
```

## Testing Checklist

- [ ] Single weapon type - no dialog
- [ ] 2+ weapon types - dialog appears
- [ ] Up/down arrows reorder correctly
- [ ] Fast roll works (existing behavior)
- [ ] Sequential resolves one weapon at a time
- [ ] Saves after each weapon
- [ ] Reorder dialog appears after saves
- [ ] Cannot reorder completed weapons
- [ ] Can reorder remaining weapons
- [ ] Progress UI updates correctly
- [ ] Save dialog shows weapon number
- [ ] Save dialog shows previous results
- [ ] Target destroyed mid-sequence
- [ ] All targets destroyed
- [ ] Save/load during sequence
- [ ] Multiplayer synchronization
- [ ] Spectator view updates

## Estimated Scope

- **Core Implementation**: 16-20 hours
- **Testing & Bug Fixes**: 8-12 hours
- **Polish & Documentation**: 4-6 hours
- **Total**: ~30-40 hours (1 week with parallel work)

## Architecture Patterns

### Signal Flow
```
ShootingPhase → weapon_order_required → ShootingController
ShootingController → shoot_action_requested → Main → NetworkManager
NetworkManager → ShootingPhase._process_resolve_weapon_sequence()
ShootingPhase → saves_required → ShootingController
ShootingController → SaveDialog
SaveDialog → save_complete → APPLY_SAVES action
ShootingPhase._process_apply_saves() → weapon_reorder_required → ShootingController
ShootingController → WeaponOrderDialog (reorder mode)
... loop until all weapons complete ...
ShootingPhase → weapon_sequence_complete → ShootingController
```

### State Machine
```
IDLE → TARGET_SELECTION (unit selected)
TARGET_SELECTION → WEAPON_ORDERING (confirm, 2+ weapons)
WEAPON_ORDERING → RESOLVING_WEAPON (start sequence)
RESOLVING_WEAPON → AWAITING_SAVES (wounds caused)
AWAITING_SAVES → AWAITING_REORDER (saves done, more weapons)
AWAITING_REORDER → RESOLVING_WEAPON (order confirmed)
RESOLVING_WEAPON → SEQUENCE_COMPLETE (last weapon done)
SEQUENCE_COMPLETE → IDLE
```

## Questions to Ask During Implementation

1. **Performance**: How does sorting 20+ weapon types perform?
2. **UX**: Is the up/down arrow interface intuitive enough?
3. **Multiplayer**: Should non-attacker see order dialog at all?
4. **Save/Load**: Should we validate that saved weapon order still makes sense?
5. **Timeout**: Should there be a timeout for reordering to prevent stalling?

## Next Steps

1. Review this PRP with team
2. Get sign-off from Product Owner
3. Create GitHub issues for each phase
4. Start Phase 1 implementation
5. Test with real games
6. Iterate based on feedback
