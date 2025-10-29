# Fight Phase Implementation Analysis
## Warhammer 40k 10th Edition Rules Compliance Review

**Date:** 2025-10-23
**Author:** Claude (Sonnet 4.5)
**Status:** Comprehensive Analysis with Proposed Solutions

---

## Executive Summary

The fight phase implementation is **functionally complete for single-player** with excellent code quality and architecture. However, it suffers from **CRITICAL multiplayer synchronization issues** due to action type mismatches in GameManager, and is **missing key 10e features** like heroic intervention. The core mechanics (pile-in, consolidate, attack resolution) are well-implemented and follow the phase-controller pattern used throughout the codebase.

**Overall Assessment:** 7.5/10
- Single-player functionality: 9/10
- Multiplayer readiness: 2/10 (BROKEN)
- Rules compliance: 7/10
- Code quality: 9/10

---

## 1. Official 10th Edition Fight Phase Rules

### 1.1 Phase Structure
```
Fight Phase Sequence:
├── Step 1: Fights First
│   ├── Units that charged this turn
│   ├── Units with "Fights First" abilities
│   └── Players alternate selecting units
├── Step 2: Remaining Combats
│   ├── All other eligible units
│   └── Players alternate selecting units
└── Resolution: If Fights First AND Fights Last → Normal priority
```

### 1.2 Engagement Range Definition
- **Horizontal:** Within 1" of enemy model
- **Vertical:** Within 5" vertically (for multi-level terrain)
- **Effect:** Units in engagement range cannot shoot (except pistols), cannot be shot, and must Fight

### 1.3 Combat Sequence (Per Unit)
```
For each fighting unit:
1. PILE IN (3" max toward closest enemy)
2. MAKE MELEE ATTACKS
   - Select eligible models
   - Select melee weapons
   - Resolve hit rolls, wound rolls, saves, damage
3. CONSOLIDATE (3" max toward closest enemy OR objective)
```

### 1.4 Pile-In Rules
- **Distance:** Up to 3" movement
- **Direction:** Must end move closer to **closest enemy model**
- **Restrictions:**
  - Cannot move within engagement range of new enemy units (unless already in engagement range of them)
  - Must maintain unit coherency
  - Cannot overlap other models or terrain
- **Timing:** Before making attacks

### 1.5 Consolidate Rules
- **Distance:** Up to 3" movement
- **Direction:** Must end move closer to **closest enemy model** (10e allows moving toward objectives as exception)
- **Restrictions:** Same as pile-in
- **Timing:** After making attacks

### 1.6 Heroic Intervention
- **Who:** CHARACTER units only
- **When:** At start of fight phase, before any units fight
- **Range:** 6" move toward enemy units
- **Restriction:** Must end closer to closest enemy, cannot already be in engagement range

### 1.7 Fight Priority Resolution
- **Fights First + Fights First** = Both fight first (alternate)
- **Fights First + Fights Last** = Normal priority (cancels out)
- **Fights Last + Fights Last** = Both fight last
- **Charged units** = Always Fights First

---

## 2. Current Implementation Analysis

### 2.1 Core Files
| File | Lines | Purpose | Status |
|------|-------|---------|--------|
| `FightPhase.gd` | 1,132 | Phase logic, validation, rules | ✅ Complete |
| `FightController.gd` | 1,135 | UI controller, visual indicators | ✅ Complete |
| `RulesEngine.gd` | ~1800 | Melee attack resolution | ✅ Complete |
| `Measurement.gd` | ~100 | Distance/collision utilities | ✅ Complete |
| `GameManager.gd` | 400+ | **Action routing (BROKEN)** | ❌ Broken |

### 2.2 Implemented Features ✅

#### Fight Sequencing (95% Complete)
```gdscript
// FightPhase.gd:31-36
var fights_first_sequence: Dictionary = {"1": [], "2": []}
var normal_sequence: Dictionary = {"1": [], "2": []}
var fights_last_sequence: Dictionary = {"1": [], "2": []}
```
- ✅ Three-tier priority system
- ✅ Alternating player activation
- ✅ Charged units get Fights First
- ✅ Ability-based priority checking
- ⚠️ Vertical engagement range not checked (5" rule)

#### Engagement Range Checking (90% Complete)
```gdscript
// FightPhase.gd:867-915
func _units_in_engagement_range(unit1, unit2) -> bool:
    // Checks 1" horizontal distance
    // Uses shape-aware base collision
```
- ✅ 1" horizontal distance
- ✅ Edge-to-edge measurement
- ✅ Multiple base shapes (circular, oval, rectangular)
- ❌ No vertical distance check (5" rule missing)

#### Pile-In Movement (85% Complete)
```gdscript
// FightPhase.gd:264-307
func _validate_pile_in(action) -> Dictionary:
    // 3" max, toward closest enemy, coherency check
```
- ✅ 3" maximum distance enforced
- ✅ Must move toward closest enemy
- ✅ Unit coherency validation
- ✅ Model overlap prevention
- ⚠️ Restriction on "entering engagement range of new units" not explicitly enforced

#### Consolidate Movement (85% Complete)
- ✅ Same validation as pile-in (3", coherency, overlap)
- ✅ Toward closest enemy direction check
- ❌ Optional move toward objectives not implemented (10e rule)

#### Attack Resolution (95% Complete)
```gdscript
// FightPhase.gd:494-532
func _process_roll_dice(action) -> Dictionary:
    // Delegates to RulesEngine
    var result = RulesEngine.resolve_melee_attacks(...)
```
- ✅ Weapon selection
- ✅ Target assignment
- ✅ Hit/wound/save sequence
- ✅ Damage application
- ✅ Dice logging and display
- ⚠️ Mathhammer predictions (placeholder only)

### 2.3 Missing Features ❌

#### Heroic Intervention (0% Complete)
```gdscript
// FightPhase.gd:603-606
func _process_heroic_intervention(action):
    log_phase_message("Heroic intervention not yet implemented")
    return create_result(false, [], "Heroic intervention not implemented")
```
**Status:** Placeholder only, validation stub exists

#### Mathhammer for Melee (20% Complete)
```gdscript
// FightPhase.gd:534-558
func _show_mathhammer_predictions():
    // Shows basic text, no actual calculation
```
**Status:** UI signal exists, calculation missing

#### Counter-Offensive Stratagem (0% Complete)
**Status:** Not implemented (requires stratagem system integration)

#### Fight on Death Abilities (0% Complete)
**Status:** Not implemented (requires ability trigger system)

---

## 3. CRITICAL ISSUE: Multiplayer Action Mismatch

### 3.1 The Problem

**GameManager.gd** (lines 94-100) only registers 3 fight actions:
```gdscript
match action["type"]:
    // ... other actions ...
    "SELECT_FIGHT_TARGET":  // ❌ Used by GameManager
        return process_fight_target(action)
    "RESOLVE_FIGHT":        // ❌ Used by GameManager
        return process_resolve_fight(action)
    "END_FIGHT":            // ✅ Matches FightPhase
        return process_end_fight(action)
```

**FightPhase.gd** expects 10 different action types:
```gdscript
match action_type:
    "SELECT_FIGHTER":                   // ❌ NOT in GameManager
    "SELECT_MELEE_WEAPON":              // ❌ NOT in GameManager
    "PILE_IN":                          // ❌ NOT in GameManager
    "ASSIGN_ATTACKS":                   // ❌ NOT in GameManager
    "CONFIRM_AND_RESOLVE_ATTACKS":      // ❌ NOT in GameManager
    "ROLL_DICE":                        // ❌ NOT in GameManager
    "CONSOLIDATE":                      // ❌ NOT in GameManager
    "SKIP_UNIT":                        // ❌ NOT in GameManager
    "HEROIC_INTERVENTION":              // ❌ NOT in GameManager
    "END_FIGHT":                        // ✅ Matches!
```

### 3.2 Impact Analysis

**Severity:** CRITICAL 🔴
**Impact:** 10/10 - **Fight phase is completely broken in multiplayer**

#### What Breaks:
1. **Client Actions Silently Fail:** When client sends `SELECT_FIGHTER`, GameManager returns "Unknown action type"
2. **No State Synchronization:** Pile-in, consolidate, attack assignments never sync across network
3. **Dice Results Missing:** `ROLL_DICE` action doesn't propagate to clients
4. **Host May Work:** If Main.gd routes directly to phase for host (bypassing GameManager), single-player works

#### Similar Bug Reference:
This is **identical to the charge phase bug** documented in:
- `PRPs/gh_issue_charge_roll_action_type_mismatch.md`

### 3.3 Why This Wasn't Caught

**Hypothesis:** The fight phase was developed/tested in single-player mode where:
```
User Input → FightController → Main.gd → FightPhase (direct)
```

But in multiplayer mode:
```
User Input → FightController → Main.gd → NetworkManager
    → GameManager (FAILS HERE) → ❌ Unknown action
```

---

## 4. Rules Compliance Gaps

### 4.1 Engagement Range Vertical Component
**Rule:** Models are in engagement range if within 1" horizontally AND 5" vertically
**Current:** Only checks 1" horizontal distance
**Impact:** Low (most battles on flat terrain)
**Feasibility:** 8/10 (needs 3D position tracking)

### 4.2 Consolidate Toward Objectives
**Rule:** 10e allows consolidate moves toward objectives as alternative to moving toward enemies
**Current:** Only enforces "toward closest enemy"
**Impact:** Medium (affects objective play)
**Feasibility:** 7/10 (needs objective proximity check)

### 4.3 Pile-In Engagement Restriction
**Rule:** Cannot pile in to within engagement range of enemy units you weren't already in engagement range of
**Current:** Not explicitly validated
**Impact:** Medium (prevents illegal engagements)
**Feasibility:** 6/10 (needs tracking of "original engagement targets")

### 4.4 Fights First + Fights Last Cancellation
**Rule:** If a unit has both Fights First and Fights Last, they cancel → Normal priority
**Current:** Unknown (would need to test with both abilities)
**Impact:** Low (rare edge case)
**Feasibility:** 9/10 (simple logic change)

---

## 5. Multiplayer Considerations

### 5.1 Information Visibility

**Current Approach:** Both players see all units, ranges, and combat options

#### What Each Player Should See:

| Game Element | Active Player | Opponent | Notes |
|-------------|---------------|----------|-------|
| Fight Sequence Order | ✅ Full visibility | ✅ Full visibility | Both players need to know order |
| Engagement Ranges | ✅ All ranges | ✅ All ranges | Public information |
| Pile-In Preview | ✅ Own units | ❓ Should see? | **Design decision needed** |
| Attack Assignments | ✅ Own assignments | ❌ Hidden until resolved | Prevents meta-gaming |
| Dice Results | ✅ All results | ✅ All results | Public information |
| Model Health | ✅ All units | ✅ All units | Public after damage |
| Mathhammer Predictions | ✅ Own attacks | ❌ Hidden | Don't reveal intent |

### 5.2 Action Synchronization Points

Critical moments requiring network sync:

1. **Fight Sequence Determination** (phase start)
   - Both clients must agree on fight order
   - Priority calculation must be deterministic

2. **Unit Selection** (each activation)
   - Active player selects fighter
   - Opponent sees selection + visual highlight

3. **Pile-In Movement** (before attacks)
   - Active player moves models
   - Opponent sees final positions
   - Both clients validate collision/coherency

4. **Attack Assignment** (during activation)
   - Active player assigns weapons→targets
   - **Opponent should NOT see assignments yet**
   - Revealed when dice are rolled

5. **Dice Rolling** (attack resolution)
   - Dice results must use same RNG seed
   - Both clients show identical dice
   - Damage applied simultaneously

6. **Consolidate Movement** (after attacks)
   - Same sync as pile-in

### 5.3 Synchronization Failure Modes

**Without proper GameManager registration:**
- ❌ Pile-in on client → Host never sees movement
- ❌ Attack assignment on client → Host has no target data
- ❌ Dice roll on client → Host never resolves combat
- ❌ Consolidate on client → Host has stale positions

**Result:** Complete desynchronization, game state diverges

---

## 6. Proposed Solutions

### 6.1 🔴 CRITICAL: Fix GameManager Action Registration

**Problem:** Fight actions not registered in GameManager
**Feasibility:** 10/10 (simple mapping)
**Impact:** 10/10 (enables multiplayer)
**Effort:** 1-2 hours

**Solution:**
```gdscript
// In GameManager.gd process_action():
match action["type"]:
    // Add fight action routing
    "SELECT_FIGHTER", "SELECT_MELEE_WEAPON", "PILE_IN":
        return _delegate_to_current_phase(action)
    "ASSIGN_ATTACKS", "CONFIRM_AND_RESOLVE_ATTACKS", "ROLL_DICE":
        return _delegate_to_current_phase(action)
    "CONSOLIDATE", "SKIP_UNIT", "HEROIC_INTERVENTION":
        return _delegate_to_current_phase(action)

    // Keep END_FIGHT separate if it needs special handling
    "END_FIGHT":
        return process_end_fight(action)
```

**Testing Required:**
- [ ] Host can see client pile-in movements
- [ ] Client can see host attack results
- [ ] Dice results sync correctly
- [ ] Fight sequence order matches on both clients

---

### 6.2 🟠 HIGH: Implement Heroic Intervention

**Problem:** CHARACTER units cannot perform 6" intervention at fight start
**Feasibility:** 7/10 (medium complexity)
**Impact:** 8/10 (core 10e rule)
**Effort:** 4-6 hours

**Implementation Steps:**

1. **Add Pre-Fight Phase Check** (FightPhase.gd:47-60)
```gdscript
func _on_phase_enter() -> void:
    // ... existing code ...
    _check_for_heroic_interventions()  // NEW
    _initialize_fight_sequence()
    _check_for_combats()

func _check_for_heroic_interventions() -> void:
    """Check for eligible CHARACTER units for heroic intervention"""
    var eligible_characters = []
    var all_units = game_state_snapshot.get("units", {})

    for unit_id in all_units:
        var unit = all_units[unit_id]

        // Must be a CHARACTER
        if not _is_character(unit):
            continue

        // Must NOT already be in engagement range
        if _is_unit_in_combat(unit):
            continue

        // Must be within 6" of enemy units
        if _has_enemy_within_range(unit, 6.0):
            eligible_characters.append(unit_id)

    if eligible_characters.size() > 0:
        emit_signal("heroic_interventions_available", eligible_characters)
```

2. **Validate Movement** (_validate_heroic_intervention_action)
```gdscript
func _validate_heroic_intervention_action(action) -> Dictionary:
    // Check is CHARACTER
    // Check not in engagement range
    // Check 6" max movement
    // Check ends closer to closest enemy
    // Check no model overlaps
```

3. **UI Integration** (FightController)
- Show "Heroic Intervention Available" notification
- Allow player to select CHARACTER and destination
- Show 6" range indicator

**Multiplayer Considerations:**
- Each player's heroic interventions resolve before any fights
- Alternating activation if both players have characters to intervene

---

### 6.3 🟠 MEDIUM: Add Vertical Engagement Range

**Problem:** Only checks 1" horizontal, missing 5" vertical rule
**Feasibility:** 6/10 (requires Z-axis tracking)
**Impact:** 3/10 (rarely matters on flat boards)
**Effort:** 2-4 hours

**Current Issue:**
```gdscript
// FightPhase.gd:867-915 - only checks X/Y distance
var edge_distance_inches = Measurement.px_to_inches(edge_distance_px)
if edge_distance_inches <= 1.0:  // Missing Z check
    return true
```

**Solution Requires:**
1. Add `position.z` to model data structure
2. Modify `_units_in_engagement_range()`:
```gdscript
// Check horizontal (X/Y) distance <= 1"
var horizontal_distance = ... // existing code
// Check vertical (Z) distance <= 5"
var z1 = model1.get("position", {}).get("z", 0.0)
var z2 = model2.get("position", {}).get("z", 0.0)
var vertical_distance_inches = abs(z1 - z2) * Z_SCALE_FACTOR

if horizontal_distance <= 1.0 and vertical_distance_inches <= 5.0:
    return true
```

3. Update deployment/movement to set Z values for models on terrain

**Decision Point:** Is multi-level terrain important for this game?
If NO → Skip this (not worth complexity)
If YES → Needs broader 3D terrain system

---

### 6.4 🟡 MEDIUM: Consolidate Toward Objectives

**Problem:** Can only consolidate toward closest enemy, not objectives
**Feasibility:** 7/10 (straightforward logic)
**Impact:** 6/10 (important for competitive play)
**Effort:** 2-3 hours

**Rule:** In 10e, units can consolidate toward closest objective marker instead of enemy

**Implementation:**
```gdscript
func _validate_consolidate(action) -> Dictionary:
    var unit_id = action.get("unit_id", "")
    var movements = action.get("movements", {})
    var errors = []

    for model_id in movements:
        var old_pos = _get_model_position(unit_id, model_id)
        var new_pos = movements[model_id]

        // NEW: Check if moving toward enemy OR objective
        var moving_toward_enemy = _is_moving_toward_closest_enemy(...)
        var moving_toward_objective = _is_moving_toward_closest_objective(...)

        if not (moving_toward_enemy or moving_toward_objective):
            errors.append("Model must consolidate toward enemy or objective")

    return {"valid": errors.is_empty(), "errors": errors}
```

**UI Addition:**
- Radio buttons: "Consolidate toward [ Enemy / Objective ]"
- Show objective markers with distance indicators

---

### 6.5 🟡 LOW: Pile-In Engagement Restriction

**Problem:** Can pile in to engage new units not originally engaged
**Feasibility:** 6/10 (requires state tracking)
**Impact:** 5/10 (prevents some exploits)
**Effort:** 3-4 hours

**Rule:** Cannot pile in to within engagement range of enemy units you weren't already in engagement range of at the start of this unit's fight activation

**Implementation:**
```gdscript
func _process_select_fighter(action) -> Dictionary:
    active_fighter_id = action.unit_id

    // NEW: Record original engagement targets
    var unit = get_unit(active_fighter_id)
    var original_targets = _find_enemies_in_engagement_range(unit)
    resolution_state[active_fighter_id] = {
        "original_engagement_targets": original_targets
    }

    return create_result(true, [])

func _validate_pile_in(action) -> Dictionary:
    // ... existing validation ...

    // NEW: Check not engaging new units
    var new_engagements = _check_for_new_engagements(unit_id, movements)
    if not new_engagements.is_empty():
        errors.append("Cannot pile in to engage new units: " + str(new_engagements))
```

---

### 6.6 🟢 LOW: Complete Mathhammer Integration

**Problem:** Mathhammer predictions show placeholder text
**Feasibility:** 8/10 (mathhammer module exists)
**Impact:** 4/10 (nice-to-have for players)
**Effort:** 2-3 hours

**Current State:**
```gdscript
// FightPhase.gd:534-558 - placeholder
var prediction_text = "Expected: Calculating melee predictions..."
```

**Solution:**
```gdscript
func _show_mathhammer_predictions() -> void:
    for attack in confirmed_attacks:
        var attacker = get_unit(attack.attacker)
        var defender = get_unit(attack.target)
        var weapon = RulesEngine.get_weapon_profile(attack.weapon)

        // Use existing mathhammer module
        var prediction = MathhammerService.calculate_melee_expected_wounds(
            attacker, defender, weapon, game_state_snapshot
        )

        emit_signal("dice_rolled", {
            "context": "mathhammer_prediction",
            "message": "Expected: %.1f wounds (%.0f%% chance to kill)" % [
                prediction.expected_wounds,
                prediction.kill_probability * 100
            ]
        })
```

**Multiplayer:** Only show predictions to active player, hide from opponent

---

### 6.7 🟢 LOW: Fights First + Last Cancellation

**Problem:** May not handle simultaneous Fights First and Fights Last correctly
**Feasibility:** 9/10 (simple logic)
**Impact:** 2/10 (rare edge case)
**Effort:** 1 hour

**Rule:** If unit has both Fights First and Fights Last abilities, they cancel → Normal priority

**Implementation:**
```gdscript
func _get_fight_priority(unit) -> int:
    var has_fights_first = false
    var has_fights_last = false

    // Check charged
    if unit.get("flags", {}).get("charged_this_turn", false):
        has_fights_first = true

    // Check abilities
    var abilities = unit.get("meta", {}).get("abilities", [])
    for ability in abilities:
        var ability_lower = str(ability).to_lower()
        if "fights_first" in ability_lower or "fights first" in ability_lower:
            has_fights_first = true
        if "fights_last" in ability_lower or "fights last" in ability_lower:
            has_fights_last = true

    // NEW: Cancellation rule
    if has_fights_first and has_fights_last:
        return FightPriority.NORMAL  // They cancel out
    elif has_fights_first:
        return FightPriority.FIGHTS_FIRST
    elif has_fights_last:
        return FightPriority.FIGHTS_LAST
    else:
        return FightPriority.NORMAL
```

---

## 7. Feasibility & Impact Matrix

| Issue | Feasibility | Impact | Priority | Effort |
|-------|-------------|--------|----------|--------|
| **GameManager Action Registration** | 10/10 | 10/10 | 🔴 CRITICAL | 1-2h |
| **Heroic Intervention** | 7/10 | 8/10 | 🟠 HIGH | 4-6h |
| **Consolidate to Objectives** | 7/10 | 6/10 | 🟡 MEDIUM | 2-3h |
| **Pile-In Engagement Restriction** | 6/10 | 5/10 | 🟡 LOW | 3-4h |
| **Vertical Engagement Range** | 6/10 | 3/10 | 🟢 OPTIONAL | 2-4h |
| **Mathhammer Completion** | 8/10 | 4/10 | 🟢 LOW | 2-3h |
| **Fights First+Last Cancel** | 9/10 | 2/10 | 🟢 LOW | 1h |

**Recommended Implementation Order:**
1. Fix GameManager (BLOCKS multiplayer)
2. Implement Heroic Intervention (core rule)
3. Test multiplayer thoroughly
4. Add consolidate to objectives (competitive play)
5. Complete mathhammer (polish)
6. Remaining items as time permits

---

## 8. Testing Requirements

### 8.1 Unit Tests Needed
- [ ] Heroic intervention eligibility checks
- [ ] Consolidate toward objective validation
- [ ] Pile-in engagement restriction
- [ ] Fights First + Last cancellation

### 8.2 Integration Tests Needed
- [ ] Full fight sequence with alternating activation
- [ ] Multiple units fighting in same activation round
- [ ] Pile in → attacks → consolidate full flow
- [ ] Heroic intervention before fights

### 8.3 Multiplayer Tests Needed
- [ ] Host pile-in visible to client
- [ ] Client attack assignments sync to host
- [ ] Dice results show identically on both
- [ ] Fight sequence order matches
- [ ] Engagement range calculations match

### 8.4 Edge Cases to Test
- [ ] Unit destroyed before pile-in
- [ ] Unit destroyed after pile-in, before attacks
- [ ] Last model removed during combat
- [ ] Consolidate moves unit out of combat
- [ ] Multiple units with Fights First
- [ ] Unit with both Fights First and Fights Last

---

## 9. Code Quality Assessment

### 9.1 Strengths ✅
1. **Clean Architecture:** Follows BasePhase pattern consistently
2. **Comprehensive Validation:** All actions validated before processing
3. **Good Separation of Concerns:** Phase logic vs UI controller
4. **Extensive Logging:** Helpful debug output
5. **Signal-Based Coupling:** Phase and controller loosely coupled
6. **Test Coverage:** Multiple test files for different aspects

### 9.2 Areas for Improvement ⚠️
1. **Action Type Naming:** Use phase-specific prefixes (e.g., `FIGHT_SELECT_UNIT` instead of `SELECT_FIGHTER`)
2. **Magic Numbers:** Extract 3", 1", 6" distances to constants
3. **TODO Comments:** Several "TODO" comments for mathhammer, heroic intervention
4. **Duplicate Code:** Pile-in and consolidate validation nearly identical (could refactor)
5. **Error Messages:** Some errors could be more user-friendly

### 9.3 Recommended Refactoring
```gdscript
// FightPhase.gd - Extract constants
const PILE_IN_DISTANCE_INCHES = 3.0
const CONSOLIDATE_DISTANCE_INCHES = 3.0
const ENGAGEMENT_RANGE_HORIZONTAL_INCHES = 1.0
const ENGAGEMENT_RANGE_VERTICAL_INCHES = 5.0
const HEROIC_INTERVENTION_DISTANCE_INCHES = 6.0

// Refactor movement validation
func _validate_combat_movement(action: Dictionary, movement_type: String) -> Dictionary:
    // Shared logic for pile-in and consolidate
    // Differs only in direction validation and timing
```

---

## 10. Conclusion

The fight phase implementation demonstrates **solid engineering** with good architecture and comprehensive single-player functionality. The **CRITICAL multiplayer bug** (GameManager action mismatch) is a simple fix that blocks all multiplayer use. Once fixed, the system should work well with minor rules gaps.

**Priority 1:** Fix GameManager registration (1-2 hours) → Unblocks multiplayer
**Priority 2:** Implement Heroic Intervention (4-6 hours) → Core rule compliance
**Priority 3:** Test multiplayer thoroughly → Ensure stability
**Priority 4:** Polish and fill gaps as time permits

The codebase is well-positioned for these improvements due to its clean architecture and existing test coverage. Estimated total effort for Priority 1-3: **8-12 hours of development + testing**.

---

## Appendix A: Multiplayer Visibility Recommendations

### Information Flow Design

```
┌─────────────────────────────────────────────────────┐
│              FIGHT PHASE - MULTIPLAYER              │
├─────────────────────────────────────────────────────┤
│                                                      │
│  Phase Start: BOTH players see                      │
│    ✓ Fight sequence order                           │
│    ✓ Which units are in engagement range            │
│    ✓ Current subphase (Fights First / Normal)       │
│                                                      │
│  Active Player's Turn:                               │
│    ✓ Shows: Own unit selected (highlighted)         │
│    ✓ Shows: Available melee weapons                 │
│    ✓ Shows: Eligible targets                        │
│    ✓ Shows: Pile-in range indicator                 │
│    ✗ Hides: Weapon/target assignments (until roll)  │
│                                                      │
│  Opponent Sees:                                      │
│    ✓ Active unit highlighted                        │
│    ✓ Pile-in movement (final positions)             │
│    ✗ Cannot see weapon selections                   │
│    ✗ Cannot see target assignments                  │
│    ⏳ Waits for active player to roll dice          │
│                                                      │
│  Dice Roll: BOTH players see                        │
│    ✓ Revealed: Weapon used                          │
│    ✓ Revealed: Target unit                          │
│    ✓ Shown: All dice rolls (hit/wound/save)         │
│    ✓ Shown: Damage applied                          │
│    ✓ Shown: Models removed                          │
│                                                      │
│  Consolidate: BOTH players see                      │
│    ✓ Final model positions                          │
│    ✓ New engagement ranges                          │
│                                                      │
└─────────────────────────────────────────────────────┘
```

This prevents "telegraph" where opponent can react to target selection before dice are rolled.

---

## Appendix B: Action Type Registration Fix

**File:** `/Users/robertocallaghan/Documents/claude/godotv2/40k/autoloads/GameManager.gd`

**Current Code (lines 94-100):**
```gdscript
# Fight actions
"SELECT_FIGHT_TARGET":
    return process_fight_target(action)
"RESOLVE_FIGHT":
    return process_resolve_fight(action)
"END_FIGHT":
    return process_end_fight(action)
```

**Required Fix:**
```gdscript
# Fight actions - NEW ROUTING
"SELECT_FIGHTER", "SELECT_MELEE_WEAPON":
    return _delegate_to_current_phase(action)
"PILE_IN", "CONSOLIDATE":
    return _delegate_to_current_phase(action)
"ASSIGN_ATTACKS", "CONFIRM_AND_RESOLVE_ATTACKS":
    return _delegate_to_current_phase(action)
"ROLL_DICE", "SKIP_UNIT":
    return _delegate_to_current_phase(action)
"HEROIC_INTERVENTION":
    return _delegate_to_current_phase(action)
"END_FIGHT":
    return process_end_fight(action)  # Keep if special handling needed

# Legacy fight actions (DEPRECATED - remove after migration)
# "SELECT_FIGHT_TARGET":
#     return process_fight_target(action)
# "RESOLVE_FIGHT":
#     return process_resolve_fight(action)
```

This allows all FightPhase actions to route through GameManager to PhaseManager, enabling multiplayer synchronization.

---

**End of Analysis Document**
