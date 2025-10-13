# Shooting Phase Enhanced Implementation PRP
**Version**: 1.2
**Date**: 2025-10-11
**Scope**: MVP implementation of Shooting Phase (excluding saves and damage allocation)

## 1. Executive Summary

This PRP defines the implementation of the Shooting Phase for the Warhammer 40K 10th edition game. The implementation will follow the existing Phase-Controller-RulesEngine architecture pattern and integrate with the current multiplayer system. This MVP version will handle target selection, attack rolls, and wound rolls, but defer save rolls and damage allocation to a future iteration.

**Key Decisions Made:**
- **Auto-targeting**: System will automatically assign targets when only one is available (Section 3.3)
- **Modifiers**: Phased approach starting with basic hit modifiers, expanding to wound modifiers, then advanced effects (Section 3.5)
- **Architecture**: Follows existing Phase-Controller-RulesEngine pattern for consistency
- **MVP Scope**: Focus on core shooting mechanics without saves/damage for initial release

## 2. Core Requirements

### 2.1 Rules Compliance (10th Edition)
- **Target Declaration**: All targets must be declared before any dice are rolled
- **Weapon Splitting**: A single weapon's attacks cannot be split between multiple targets
- **Visibility**: At least one model in target unit must be visible to the shooting model
- **Range**: Target must be within weapon range
- **Engagement Restrictions**: Units in engagement range cannot shoot (except Pistols/Big Guns Never Tire - future feature)

### 2.2 Architecture Requirements
- Follow existing Phase-Controller-RulesEngine pattern
- Integrate with NetworkManager for multiplayer support
- Support save/load functionality
- Use deterministic RNG with seed management
- Emit appropriate signals for UI updates

## 3. User Flow

### 3.1 Phase Entry
1. System transitions from Movement/Command Phase to Shooting Phase
2. ShootingController initializes and displays UI
3. System identifies all eligible shooting units for active player
4. If no eligible units, auto-advance to next phase

### 3.2 Unit Selection
1. Display list of eligible shooting units in right panel
2. Player selects a unit to shoot with
3. System validates unit can shoot (not engaged, has ranged weapons, hasn't shot)
4. Display selected unit's weapon loadout

### 3.3 Target Assignment

#### Attack Panel Structure
The right panel displays:

```
┌─────────────────────────┐
│ Shooting Controls       │
├─────────────────────────┤
│ Select Shooter:         │
│ [Unit List]             │
├─────────────────────────┤
│ Weapon Assignments:     │
│ ┌─────────────────────┐ │
│ │ Weapon | Target | M │ │
│ ├─────────────────────┤ │
│ │ Bolt Rifle x5       │ │
│ │ [Select Target ▼]   │ │
│ │ Modifiers:          │ │
│ │ [□ Re-Roll 1s Hit]  │ │
│ │ [□ +1 To Hit]       │ │
│ │ [□ -1 To Hit]       │ │
│ ├─────────────────────┤ │
│ │ Plasma Gun x1       │ │
│ │ [Select Target ▼]   │ │
│ │ Modifiers:          │ │
│ │ [□ Re-Roll 1s Hit]  │ │
│ │ [□ +1 To Hit]       │ │
│ │ [□ -1 To Hit]       │ │
│ └─────────────────────┘ │
├─────────────────────────┤
│ [Clear All] [Confirm]   │
├─────────────────────────┤
│ Dice Log:               │
│ [Results appear here]   │
└─────────────────────────┘
```

#### Target Selection Rules
- Each weapon type gets ONE target selection dropdown
- Dropdown populated with eligible targets only (in range + visible)
- Weapons of same type are grouped (e.g., "Bolt Rifle x5")
- Cannot proceed until all weapons have targets assigned
- Visual feedback on board: eligible targets highlighted green, ineligible gray

#### Auto-Target Assignment
The system provides intelligent target suggestions to reduce tedious clicking while preserving tactical player choice:

**Auto-Assignment Levels:**
```gdscript
enum TargetSuggestionLevel {
    NONE,           # No suggestion
    OBVIOUS,        # Auto-assign (only one target)
    SUGGESTED,      # Highlight but don't assign
    MULTIPLE        # Multiple valid options, no suggestion
}
```

**Criteria for Auto-Assignment (in priority order):**

1. **Single Eligible Target** (OBVIOUS)
   - When only ONE enemy unit is both visible and in range
   - Auto-assigns immediately with green flash
   - Shows tooltip: "Auto-selected: Only eligible target"
   - Player can still change if desired

2. **Previously Engaged Target** (SUGGESTED)
   - If unit already shot at a target with other weapons this phase
   - Highlights with star icon ⭐ in dropdown
   - Tooltip: "Suggested: Continue focusing fire"
   - Requires player confirmation

3. **Damaged Unit** (SUGGESTED)
   - Prioritizes units with wounded models
   - Only suggests if single wounded unit in range
   - Tooltip: "Suggested: Finish wounded unit"
   - Requires player confirmation

4. **Multiple Options** (NONE)
   - No auto-assignment when multiple tactical choices exist
   - Dropdown sorted by distance for convenience
   - Preserves full player agency

**Implementation:**
```gdscript
func get_target_suggestion(weapon_id, eligible_targets, context):
    # Case 1: Only one possible target
    if eligible_targets.size() == 1:
        return {
            "level": TargetSuggestionLevel.OBVIOUS,
            "target": eligible_targets.keys()[0],
            "reason": "Only eligible target"
        }

    # Case 2: Unit already shooting at something
    if context.has_existing_assignments:
        for existing in context.existing_assignments:
            if existing.target_id in eligible_targets:
                return {
                    "level": TargetSuggestionLevel.SUGGESTED,
                    "target": existing.target_id,
                    "reason": "Continue focusing fire"
                }

    # Case 3: Previously wounded target available
    var wounded_targets = eligible_targets.filter(func(t):
        return t.has_wounded_models)
    if wounded_targets.size() == 1:
        return {
            "level": TargetSuggestionLevel.SUGGESTED,
            "target": wounded_targets[0],
            "reason": "Finish wounded unit"
        }

    # Case 4: Multiple options - no suggestion
    return {
        "level": TargetSuggestionLevel.MULTIPLE,
        "target": null,
        "reason": "Multiple tactical options"
    }
```

**User Settings:**
```gdscript
enum AutoTargeting {
    OFF,          # Never auto-assign
    OBVIOUS_ONLY, # Only when 1 target available (DEFAULT)
    SMART,        # Include tactical suggestions
}
```

Default setting is `OBVIOUS_ONLY` to eliminate tedious clicks without making tactical decisions for the player.

### 3.4 Target Confirmation
1. Player assigns target for each weapon type
2. Player selects applicable modifiers (see Section 3.5 for modifier system)
3. Player clicks "Confirm Target Allocation"
4. System validates all assignments
5. UI transitions to "Making Attacks" mode

### 3.5 Modifier System

The shooting phase implements a phased approach to modifiers, starting simple and adding complexity over time:

#### Phase 1 Modifiers (Core MVP)
These are the most common modifiers that significantly impact gameplay:

**Hit Roll Modifiers:**
- **Re-roll 1s to Hit** - Very common ability (Captains, etc.)
- **+1 to Hit** - Common buff from abilities/stratagems
- **-1 to Hit** - Common penalty from cover/movement

**Implementation:**
```gdscript
enum HitModifier {
    NONE = 0,
    REROLL_ONES = 1,
    PLUS_ONE = 2,
    MINUS_ONE = 4,
}

func apply_hit_modifiers(roll: int, modifiers: int) -> int:
    var modified_roll = roll

    # Apply re-rolls first (before modifiers per rules)
    if modifiers & HitModifier.REROLL_ONES and roll == 1:
        modified_roll = roll_d6()  # Re-roll

    # Then apply modifiers (capped at +1/-1 net)
    var net_modifier = 0
    if modifiers & HitModifier.PLUS_ONE:
        net_modifier += 1
    if modifiers & HitModifier.MINUS_ONE:
        net_modifier -= 1
    net_modifier = clamp(net_modifier, -1, 1)

    return modified_roll + net_modifier
```

#### Phase 2 Modifiers (Enhanced MVP)
Add wound modifiers and common weapon keywords:

**Wound Roll Modifiers:**
- **Re-roll 1s to Wound** - Lieutenant abilities
- **+1 to Wound** - Various abilities
- **-1 to Wound** - Defensive abilities

**Weapon Keywords:**
- **Twin-linked** - Re-roll wound rolls
- **Blast** - Bonus attacks vs 6+ model units
- **Heavy** - +1 to hit if didn't move

**Implementation:**
```gdscript
func calculate_blast_bonus(target_unit_size: int, base_attacks: int) -> int:
    if target_unit_size >= 6:
        return base_attacks + min(3, base_attacks)  # Add up to 3 attacks
    return base_attacks

func apply_weapon_keywords(weapon: Dictionary, context: Dictionary) -> Dictionary:
    var modifiers = {}

    if weapon.has("twin_linked"):
        modifiers.wound_reroll = RerollType.ALL_FAILED

    if weapon.has("heavy") and not context.unit_moved:
        modifiers.hit_bonus = 1

    if weapon.has("blast"):
        modifiers.attack_multiplier = 1.5  # Simplified for MVP

    return modifiers
```

#### Phase 3 Modifiers (Full Implementation)
Advanced mechanics for complete rules compliance:

**Critical Effects:**
- **Critical Hits on 6s** - Unmodified 6s trigger special effects
- **Critical Wounds on 6s** - Unmodified 6s to wound
- **Lethal Hits** - Critical hits automatically wound
- **Sustained Hits X** - Critical hits generate X additional hits
- **Devastating Wounds** - Critical wounds become mortal wounds

**Advanced Keywords:**
- **Ignores Cover** - Target gets no save bonus
- **Indirect Fire** - Can shoot without LoS (-1 to hit)
- **Precision** - Can target specific models
- **Full Re-rolls** - Re-roll all failed rolls

**Architecture Consideration:**
The modifier system must be extensible to add new modifiers without refactoring:
```gdscript
class ModifierRegistry:
    var registered_modifiers = {}

    func register_modifier(name: String, effect: Callable):
        registered_modifiers[name] = effect

    func apply_modifiers(roll_type: String, base_value: int, active_modifiers: Array):
        var result = base_value
        for mod in active_modifiers:
            if mod in registered_modifiers:
                result = registered_modifiers[mod].call(result)
        return result
```

### 3.6 Making Attacks Sub-phase

For each weapon assignment (in deterministic order):

#### 3.6.1 Establish Number of Attacks
- Fixed attacks: Sum all attacks (e.g., 2 guns with 5 shots = 10 total)
- Variable attacks: Roll D3/D6 per weapon, display results, sum total
- Apply Blast bonus if applicable (Phase 2+)
- Display: "Bolt Rifles: 10 attacks total"

#### 3.6.2 Roll to Hit
- Roll D6 for each attack
- Compare to BS (Ballistic Skill) value
- Apply modifiers in order:
  1. Re-rolls (if applicable) - BEFORE modifiers
  2. Modifiers (+1/-1, capped at net +1/-1)
- Count successes (and track unmodified 6s for Phase 3)
- Display: "Hit Rolls: [6,5,4,3,2,1] vs BS 3+ → 4 hits"

#### 3.6.3 Roll to Wound
- Roll D6 for each hit
- Compare Strength vs Toughness:
  ```
  S < T/2:     6+ wounds
  S < T:       5+ wounds
  S = T:       4+ wounds
  S > T:       3+ wounds
  S ≥ T×2:     2+ wounds
  ```
- Apply modifiers (Phase 2+):
  1. Re-rolls (Twin-linked, etc.)
  2. Modifiers (+1/-1, capped)
- Count successful wounds
- Display: "Wound Rolls: [5,4,3,2] vs T4 (S4 = 4+) → 2 wounds"

### 3.7 Resolution Complete
- Display summary: "Bolt Rifles → Ork Boyz: 10 shots, 4 hits, 2 wounds"
- Mark unit as having shot
- Return to unit selection or end phase

## 4. UI Components

### 4.1 ShootingController (Right Panel)
Extends existing controller pattern:
- Unit selector (ItemList)
- Weapon tree (Tree with target dropdowns)
- Modifier toggles per weapon
- Action buttons (Clear All, Confirm Targets, Make Attacks)
- Dice log (RichTextLabel with BBCode)

### 4.2 Board Visualization
- Range circles for selected shooter's weapons
- LoS lines from shooter to potential targets
- Target highlighting:
  - Green: Eligible (in range + visible)
  - Yellow: Selected
  - Gray: Ineligible
  - Red: Enemy units in engagement range

### 4.3 Bottom HUD Integration
- Use existing PhaseActionButton
- States: "Select Shooter", "Assign Targets", "Roll Dice", "End Phase"

## 5. Data Structures

### 5.1 Shooting Action
```gdscript
{
  "type": "SHOOT",
  "actor_unit_id": "U_INTERCESSORS_1",
  "payload": {
    "assignments": [
      {
        "weapon_id": "bolt_rifle",
        "target_unit_id": "U_ORK_BOYZ_1",
        "model_ids": ["m1", "m2", "m3", "m4", "m5"],
        "modifiers": {
          "hit": {
            "reroll_ones": true,
            "plus_one": false,
            "minus_one": false
          },
          "wound": {  // Phase 2+
            "reroll_ones": false,
            "plus_one": false,
            "minus_one": false
          }
        }
      }
    ]
  }
}
```

### 5.2 Resolution Result
```gdscript
{
  "success": true,
  "phase": "SHOOTING",
  "diffs": [
    // State changes (flags, etc.)
  ],
  "dice": [
    {
      "context": "attacks",
      "weapon": "bolt_rifle",
      "rolls": [5, 5],  // If D6 weapons
      "total": 10
    },
    {
      "context": "to_hit",
      "threshold": 3,
      "rolls_raw": [6,5,4,3,2,1],
      "rerolls": [1],  // Indices of rerolled dice
      "reroll_results": [4],
      "successes": 5
    },
    {
      "context": "to_wound",
      "strength": 4,
      "toughness": 4,
      "threshold": 4,
      "rolls_raw": [5,4,3,2,1],
      "successes": 2
    }
  ],
  "log_text": "Intercessors → Ork Boyz: 10 shots, 5 hits, 2 wounds"
}
```

## 6. State Management

### 6.1 Phase State
ShootingPhase maintains:
- `active_shooter_id`: Currently selected unit
- `pending_assignments`: Targets being configured
- `confirmed_assignments`: Locked-in targets
- `units_that_shot`: Units that have completed shooting
- `resolution_state`: Current step in resolution

### 6.2 Multiplayer Synchronization
- All actions validated by host via NetworkManager
- Dice rolls generated on host with deterministic seed
- State changes applied via diffs on both host and client
- Resolution results broadcast to all players

### 6.3 Save/Load Support
- Phase state serialized with game state
- On load, validate and restore:
  - Active shooter still eligible
  - Assigned targets still valid
  - Resolution state consistency

## 7. Validation Rules

### 7.1 Target Eligibility
```gdscript
func validate_target(shooter_unit, weapon, target_unit):
  # Check visibility (at least one model)
  if not has_los(shooter_unit, target_unit):
    return {"valid": false, "reason": "No line of sight"}

  # Check range
  if distance_to_target > weapon.range:
    return {"valid": false, "reason": "Out of range"}

  # Check engagement
  if shooter_unit.in_engagement and not weapon.is_pistol:
    return {"valid": false, "reason": "Engaged - cannot shoot"}

  return {"valid": true}
```

### 7.2 Assignment Validation
- Each weapon must have a target assigned
- Cannot split a weapon's attacks
- Cannot assign to friendly units
- Target must be eligible when confirmed

## 8. Implementation Priority

### Phase 1: Core Flow (MVP)
- [x] Existing: Phase structure, basic UI
- [ ] Enhanced target selection UI
- [ ] Weapon grouping display
- [ ] Auto-assign obvious targets (single eligible target only)
- [ ] Basic hit modifiers (Re-roll 1s, +1/-1 to hit)
- [ ] Attack/Hit/Wound resolution (basic)
- [ ] Dice logging

### Phase 2: Enhanced MVP
- [ ] Wound modifiers (Re-roll 1s, +1/-1 to wound)
- [ ] Common weapon keywords (Twin-linked, Blast, Heavy)
- [ ] Smart target suggestions (wounded units, focus fire)
- [ ] Visual feedback improvements
- [ ] Fast rolling option
- [ ] Detailed tooltips
- [ ] User settings for auto-targeting behavior

### Phase 3: Full Implementation (Future)
- [ ] Save rolls and damage allocation
- [ ] Critical hits/wounds (unmodified 6s)
- [ ] Advanced weapon keywords (Lethal Hits, Sustained Hits, Devastating Wounds)
- [ ] Full re-rolls (all failed hits/wounds)
- [ ] Special rules (Ignores Cover, Indirect Fire, Precision)
- [ ] Pistols in engagement
- [ ] Big Guns Never Tire
- [ ] Extensible modifier registry system

## 9. Testing Requirements

### 9.1 Unit Tests
- Wound threshold calculations (S vs T matrix)
- Modifier application order (re-rolls before modifiers)
- Modifier stacking and caps (+1/-1 maximum)
- Dice probability distributions
- Target eligibility logic
- Auto-target suggestion logic (obvious vs suggested vs none)
- Blast attack calculations (6+ model units)
- Twin-linked re-roll mechanics

### 9.2 Integration Tests
- Complete shooting flow
- Multiplayer synchronization
- Save/load during shooting
- Edge cases:
  - No valid targets
  - All enemies out of range
  - Variable attack weapons
  - Mixed weapon profiles

### 9.3 UI Tests
- Target selection prevents splitting
- Auto-assign works for single target scenarios
- Suggested targets display with proper visual indicators
- Player can override auto-assigned targets
- Modifier checkboxes work correctly
- Multiple modifiers can be selected appropriately
- Modifiers apply correctly to dice rolls
- Re-rolls happen before modifiers are applied
- Dice log displays accurately with modifier effects
- State persistence across phase transitions

## 10. Edge Cases

### 10.1 No Valid Targets
- Display message: "No eligible targets in range"
- Allow unit to skip shooting
- Option to end phase early

### 10.2 Mixed Weapon Units
- Group identical weapons
- Display special weapons separately
- Handle different ranges/profiles

### 10.3 Variable Attacks
- Roll D3/D6 before hit rolls
- Display dice results clearly
- Sum totals for fast rolling

### 10.4 Partial Resolution
- Save state after each weapon resolves
- Allow continuation after disconnect
- Support undo for misclicks (single-player only)

## 11. Performance Considerations

- Batch dice rolls for efficiency
- Cache LoS calculations during target selection
- Limit visual effects for large units
- Progressive UI updates during resolution

## 12. Success Metrics

- Target selection takes < 30 seconds per unit
- Attack resolution takes < 10 seconds per weapon
- Zero invalid target assignments pass validation
- Multiplayer stays synchronized 100% of time
- Save/load preserves complete shooting state

## 13. Open Questions for Product Owner

The following questions have been addressed through collaborative discussion and are now resolved:

### Resolved Questions:
1. ~~**Default Modifiers**: Start with just Re-roll 1s and +1 to hit, or include more?~~
   - **RESOLVED**: Phased approach with basic hit modifiers in Phase 1, wound modifiers in Phase 2, and advanced effects in Phase 3 (see Section 3.5)

2. ~~**Auto-Assignment**: Should system suggest/auto-assign obvious targets?~~
   - **RESOLVED**: System will auto-assign when only one target available, with user setting to control behavior (see Section 3.3)

### Remaining Open Questions:
1. **Save Resolution Scope**: Calculate wounds but don't apply damage, or stop at wound rolls?
   - *Recommendation*: Stop at wound rolls for MVP, defer save/damage to next iteration

2. **Phase End Trigger**: Require all units to shoot or allow early phase end?
   - *Recommendation*: Allow early phase end with "End Shooting Phase" button always available

3. **Fast Rolling Toggle**: Always fast roll or provide option?
   - *Recommendation*: Always fast roll for MVP, add toggle in Phase 2

4. **Undo Support**: Allow undo during target selection? After dice rolls?
   - *Recommendation*: Allow undo during target selection only, not after dice rolls (maintains game integrity)

## 14. Appendix: Rules References

- Core Rules: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- Making Attacks: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#Making-Attacks
- Shooting Phase: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#SHOOTING-PHASE

## 15. Version History

- **v1.0** (2025-10-11): Initial PRP creation
- **v1.1** (2025-10-11): Added auto-target assignment logic (Section 3.3)
- **v1.2** (2025-10-11): Added phased modifier system (Section 3.5) and reorganized open questions with recommendations

## 16. Sign-off

- [ ] Product Owner
- [ ] Tech Lead
- [ ] QA Lead
- [ ] UX Designer