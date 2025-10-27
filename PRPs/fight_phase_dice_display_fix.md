# PRP: Fix Fight Phase Dice Roll Display - "Hit Roll Melee:[]" Empty Array Issue

## Summary

Fix the fight phase dice roll visualization where attack rolls are not being displayed correctly. Currently, the dice log shows "Hit Roll Melee:[]" with an empty array instead of showing the individual dice results at each step. This PRP aligns the fight phase dice display with the working shooting phase implementation to minimize code duplication and ensure consistent user experience.

## Problem Statement

**Observed Behavior:**
- When melee attacks are made in the fight phase, the dice log displays: `Hit Roll Melee:[]`
- No dice results are shown for hit rolls, wound rolls, or save rolls
- The empty array `[]` indicates no dice data is being passed to the display layer

**Expected Behavior:**
- Display individual dice results at each attack resolution step
- Show: Hit Rolls → Wound Rolls → Save Rolls → Damage Applied
- Format similar to shooting phase: `Hit Roll Melee: [4, 2, 5, 3, 6] → 4 successes`

**User Impact:**
- Players cannot see if their attacks succeeded or failed
- No transparency in combat resolution
- Impossible to verify correct rule application
- Poor gameplay experience compared to shooting phase

## Root Cause Analysis

### Technical Issue: Data Format Mismatch

**File:** `/Users/robertocallaghan/Documents/claude/godotv2/40k/autoloads/RulesEngine.gd:1770-1824`

The fight phase generates **individual** dice objects in a loop:

```gdscript
# Lines 1770-1782: Hit Roll Processing
var hit_rolls = rng.roll_d6(total_attacks)
var hits = 0
for roll in hit_rolls:
    var success = roll >= weapon_skill
    if success:
        hits += 1
    result.dice.append({
        "context": "hit_roll_melee",
        "roll": roll,              # ❌ Single value, not array
        "target": weapon_skill,
        "success": success,
        "weapon": weapon_id
    })
```

**Problem:** Each die creates a separate dictionary with `"roll": 4` (single integer), not `"rolls_raw": [4, 2, 5]` (array).

---

**File:** `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/FightController.gd:955-964`

The display handler expects **aggregated** dice arrays:

```gdscript
# Line 955-964: Display Handler
func _on_dice_rolled(dice_data: Dictionary) -> void:
    if not dice_log_display:
        return

    var context = dice_data.get("context", "")
    var rolls = dice_data.get("rolls_raw", [])  # ❌ Expects array, gets empty []
    var successes = dice_data.get("successes", 0)  # ❌ Field doesn't exist

    var log_text = "[b]%s:[/b] %s → %d successes\n" % [context.capitalize(), str(rolls), successes]
    dice_log_display.append_text(log_text)
```

**Result:** `dice_data.get("rolls_raw", [])` returns the default empty array `[]` because the field doesn't exist in the individual dice format.

---

### Reference: Working Shooting Phase Implementation

**File:** `/Users/robertocallaghan/Documents/claude/godotv2/40k/autoloads/RulesEngine.gd:297-305`

The shooting phase generates **aggregated** dice blocks:

```gdscript
# Lines 297-305: Hit Roll Processing
result.dice.append({
    "context": "to_hit",
    "threshold": str(bs) + "+",
    "rolls_raw": hit_rolls,           # ✅ Array of all dice [4, 2, 5, 1, 3]
    "rolls_modified": modified_rolls,  # ✅ After modifiers applied
    "rerolls": reroll_data,           # ✅ Shows re-roll history
    "modifiers_applied": hit_modifiers,
    "successes": hits                  # ✅ Aggregated success count
})
```

**File:** `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/ShootingController.gd:1028-1068`

The shooting phase display handler processes the aggregated format:

```gdscript
func _on_dice_rolled(dice_data: Dictionary) -> void:
    var rolls_raw = dice_data.get("rolls_raw", [])      # ✅ Gets array
    var rolls_modified = dice_data.get("rolls_modified", [])
    var rerolls = dice_data.get("rerolls", [])
    var successes = dice_data.get("successes", -1)
    var threshold = dice_data.get("threshold", "")

    var log_text = "[b]%s[/b] (need %s):\n" % [context.capitalize(), threshold]

    # Show re-rolls with strikethrough
    if not rerolls.is_empty():
        log_text += "  [color=yellow]Re-rolled:[/color] "
        for reroll in rerolls:
            log_text += "[s]%d[/s]→%d " % [reroll.original, reroll.rerolled_to]
        log_text += "\n"

    # Show all dice rolls
    var display_rolls = rolls_modified if not rolls_modified.is_empty() else rolls_raw
    log_text += "  Rolls: %s" % str(display_rolls)

    # Show success count
    if successes >= 0:
        log_text += " → [b][color=green]%d successes[/color][/b]" % successes

    dice_log_display.append_text(log_text + "\n")
```

---

## Implementation Plan

### Phase 1: Aggregate Fight Phase Dice Data (RulesEngine.gd)

**File:** `/Users/robertocallaghan/Documents/claude/godotv2/40k/autoloads/RulesEngine.gd`

**Objective:** Modify `_resolve_melee_assignment()` to match shooting phase format.

#### Task 1.1: Aggregate Hit Rolls
**Location:** Lines 1770-1786

**Current Code:**
```gdscript
var hit_rolls = rng.roll_d6(total_attacks)
var hits = 0
for roll in hit_rolls:
    var success = roll >= weapon_skill
    if success:
        hits += 1
    result.dice.append({  # ❌ Individual dice objects
        "context": "hit_roll_melee",
        "roll": roll,
        "target": weapon_skill,
        "success": success,
        "weapon": weapon_id
    })
```

**Updated Code:**
```gdscript
var hit_rolls = rng.roll_d6(total_attacks)
var hits = 0
for roll in hit_rolls:
    if roll >= weapon_skill:
        hits += 1

# ✅ Single aggregated block (like shooting phase)
result.dice.append({
    "context": "hit_roll_melee",
    "threshold": str(weapon_skill) + "+",
    "rolls_raw": hit_rolls,      # Array of all dice
    "successes": hits,            # Total hits
    "weapon": weapon_id,
    "total_attacks": total_attacks
})
```

#### Task 1.2: Aggregate Wound Rolls
**Location:** Lines 1788-1807

**Current Code:**
```gdscript
var wound_rolls = rng.roll_d6(hits)
var wounds = 0
for roll in wound_rolls:
    var success = roll >= wound_target
    if success:
        wounds += 1
    result.dice.append({  # ❌ Individual dice objects
        "context": "wound_roll",
        "roll": roll,
        "target": wound_target,
        "success": success,
        "strength": strength,
        "toughness": toughness
    })
```

**Updated Code:**
```gdscript
var wound_rolls = rng.roll_d6(hits)
var wounds = 0
for roll in wound_rolls:
    if roll >= wound_target:
        wounds += 1

# ✅ Single aggregated block
result.dice.append({
    "context": "wound_roll",
    "threshold": str(wound_target) + "+",
    "rolls_raw": wound_rolls,    # Array of all dice
    "successes": wounds,          # Total wounds
    "strength": strength,
    "toughness": toughness
})
```

#### Task 1.3: Aggregate Save Rolls
**Location:** Lines 1809-1828

**Current Code:**
```gdscript
var save_rolls = rng.roll_d6(wounds)
var failed_saves = 0
for roll in save_rolls:
    var success = roll >= modified_save
    if not success:
        failed_saves += 1
    result.dice.append({  # ❌ Individual dice objects
        "context": "save_roll",
        "roll": roll,
        "target": modified_save,
        "success": success,
        "ap": ap,
        "original_save": armor_save
    })
```

**Updated Code:**
```gdscript
var save_rolls = rng.roll_d6(wounds)
var successful_saves = 0
for roll in save_rolls:
    if roll >= modified_save:
        successful_saves += 1

var failed_saves = wounds - successful_saves

# ✅ Single aggregated block
result.dice.append({
    "context": "save_roll",
    "threshold": str(modified_save) + "+",
    "rolls_raw": save_rolls,       # Array of all dice
    "successes": successful_saves,  # Saves that succeeded
    "failed": failed_saves,         # Saves that failed
    "ap": ap,
    "original_save": armor_save
})
```

---

### Phase 2: Update Fight Phase Display Handler (FightController.gd)

**File:** `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/FightController.gd`

**Objective:** Enhance display handler to match shooting phase functionality.

#### Task 2.1: Update _on_dice_rolled() Method
**Location:** Lines 955-964

**Current Code:**
```gdscript
func _on_dice_rolled(dice_data: Dictionary) -> void:
    if not dice_log_display:
        return

    var context = dice_data.get("context", "")
    var rolls = dice_data.get("rolls_raw", [])
    var successes = dice_data.get("successes", 0)

    var log_text = "[b]%s:[/b] %s → %d successes\n" % [context.capitalize(), str(rolls), successes]
    dice_log_display.append_text(log_text)
```

**Updated Code:**
```gdscript
func _on_dice_rolled(dice_data: Dictionary) -> void:
    if not dice_log_display:
        return

    var context = dice_data.get("context", "")
    var rolls_raw = dice_data.get("rolls_raw", [])
    var successes = dice_data.get("successes", 0)
    var threshold = dice_data.get("threshold", "")
    var weapon = dice_data.get("weapon", "")

    # Format context name
    var context_name = context.capitalize().replace("_", " ")

    # Build display text
    var log_text = "[b]%s[/b]" % context_name

    # Add weapon info if present
    if weapon != "":
        var weapon_profile = RulesEngine.get_weapon_profile(weapon)
        if weapon_profile:
            log_text += " (%s)" % weapon_profile.get("name", weapon)

    # Add threshold
    if threshold != "":
        log_text += " (need %s)" % threshold

    log_text += ":\n"

    # Color-code individual dice results
    if not rolls_raw.is_empty():
        var target_num = int(threshold.replace("+", "")) if threshold != "" else 4
        var colored_rolls = []
        for roll in rolls_raw:
            if roll >= target_num:
                colored_rolls.append("[color=green]%d[/color]" % roll)
            else:
                colored_rolls.append("[color=gray]%d[/color]" % roll)

        log_text += "  Rolls: [%s]" % ", ".join(colored_rolls)
    else:
        log_text += "  Rolls: %s" % str(rolls_raw)

    # Add success count
    log_text += " → [b][color=green]%d successes[/color][/b]\n" % successes

    dice_log_display.append_text(log_text)
```

---

### Phase 3: Add Comprehensive Testing

**File:** `/Users/robertocallaghan/Documents/claude/godotv2/40k/tests/unit/test_melee_dice_display.gd`

**Objective:** Verify dice data format matches expected structure.

#### Task 3.1: Create Dice Format Validation Tests

```gdscript
extends GutTest

func test_hit_roll_dice_format():
    # Arrange
    var action = create_mock_fight_action()
    var board = create_mock_board()
    var rng = load("res://40k/autoloads/RNGService.gd").new()

    # Act
    var result = RulesEngine.resolve_melee_attacks(action, board, rng)

    # Assert
    assert_gt(result.dice.size(), 0, "Should have dice results")

    var hit_dice = null
    for dice_block in result.dice:
        if dice_block.context == "hit_roll_melee":
            hit_dice = dice_block
            break

    assert_not_null(hit_dice, "Should have hit roll dice block")
    assert_has(hit_dice, "rolls_raw", "Should have rolls_raw field")
    assert_has(hit_dice, "successes", "Should have successes field")
    assert_has(hit_dice, "threshold", "Should have threshold field")
    assert_typeof(hit_dice.rolls_raw, TYPE_ARRAY, "rolls_raw should be array")
    assert_typeof(hit_dice.successes, TYPE_INT, "successes should be int")

func test_wound_roll_dice_format():
    # Similar test for wound_roll context
    pass

func test_save_roll_dice_format():
    # Similar test for save_roll context
    pass

func test_dice_display_integration():
    """Test that FightController can display dice data correctly"""
    var fight_controller = preload("res://40k/scripts/FightController.gd").new()

    var mock_dice_data = {
        "context": "hit_roll_melee",
        "threshold": "3+",
        "rolls_raw": [4, 2, 5, 1, 3],
        "successes": 3,
        "weapon": "chainsword"
    }

    # Create mock dice log display
    var dice_log = RichTextLabel.new()
    fight_controller.dice_log_display = dice_log

    # Act
    fight_controller._on_dice_rolled(mock_dice_data)

    # Assert
    var log_text = dice_log.text
    assert_string_contains(log_text, "[4, 2, 5, 1, 3]", "Should show dice rolls")
    assert_string_contains(log_text, "3 successes", "Should show success count")
    assert_string_contains(log_text, "3+", "Should show threshold")
```

---

## Validation Gates

### Pre-Implementation Checks
```bash
# 1. Verify current code structure
cd /Users/robertocallaghan/Documents/claude/godotv2/40k

# Check fight phase dice generation
grep -n "hit_roll_melee" autoloads/RulesEngine.gd

# Check display handler
grep -n "rolls_raw" scripts/FightController.gd

# 2. Compare with shooting phase reference
grep -n "to_hit" autoloads/RulesEngine.gd | head -5
grep -n "rolls_raw" scripts/ShootingController.gd | head -10
```

### Post-Implementation Validation
```bash
# 1. Syntax check (Godot project validation)
export PATH="$HOME/bin:$PATH"
godot --headless --check-only --path /Users/robertocallaghan/Documents/claude/godotv2

# 2. Run unit tests
godot --headless --path /Users/robertocallaghan/Documents/claude/godotv2 \
      --script res://addons/gut/gut_cmdln.gd \
      -gtest=res://40k/tests/unit/test_melee_dice_display.gd

# 3. Integration test - Start game and verify dice display
# - Load save: /Users/robertocallaghan/Documents/claude/godotv2/40k/saves/start.w40ksave
# - Enter fight phase
# - Make melee attack
# - Verify dice log shows: "Hit Roll Melee: [4, 2, 5, 3] → 3 successes"
# - Verify wound rolls and save rolls also display correctly

# 4. Compare fight and shooting phase output
# - Perform shooting attack
# - Perform melee attack
# - Verify both show similar formatting and detail level
```

### Success Criteria
- [ ] No empty arrays `[]` in dice log
- [ ] Individual dice values visible: `[4, 2, 5, 3]`
- [ ] Success count shown: `→ 3 successes`
- [ ] Threshold displayed: `(need 3+)`
- [ ] All three roll types visible: Hit, Wound, Save
- [ ] Format consistent with shooting phase
- [ ] All unit tests pass
- [ ] No Godot syntax errors

---

## File Reference Summary

### Files to Modify
1. **RulesEngine.gd** (Lines 1770-1830)
   - Path: `/Users/robertocallaghan/Documents/claude/godotv2/40k/autoloads/RulesEngine.gd`
   - Changes: Aggregate dice data instead of individual rolls
   - Pattern: Follow shooting phase format (lines 297-327)

2. **FightController.gd** (Lines 955-964)
   - Path: `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/FightController.gd`
   - Changes: Enhanced display formatting with color-coding
   - Pattern: Follow ShootingController format (lines 1028-1068)

### Files for Reference (DO NOT MODIFY)
3. **ShootingController.gd** (Lines 1028-1068)
   - Path: `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/ShootingController.gd`
   - Purpose: Reference implementation for dice display

4. **RulesEngine.gd** (Lines 297-327)
   - Path: `/Users/robertocallaghan/Documents/claude/godotv2/40k/autoloads/RulesEngine.gd`
   - Purpose: Reference implementation for dice aggregation

### Test Files to Create
5. **test_melee_dice_display.gd**
   - Path: `/Users/robertocallaghan/Documents/claude/godotv2/40k/tests/unit/test_melee_dice_display.gd`
   - Purpose: Validate dice data format and display integration

---

## Context for AI Agent

### Warhammer 40K 10th Edition Rules Context
- **Core Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- **Fight Phase Section**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#FIGHT-PHASE
- **Attack Sequence**: Hit Roll → Wound Roll → Save Roll → Damage

### Godot 4.x Documentation
- **GDScript Syntax**: https://docs.godotengine.org/en/4.4/tutorials/scripting/gdscript/gdscript_basics.html
- **Signals**: https://docs.godotengine.org/en/4.4/getting_started/step_by_step/signals.html
- **RichTextLabel BBCode**: https://docs.godotengine.org/en/4.4/tutorials/ui/bbcode_in_richtextlabel.html

### Codebase Patterns
- **Dice Rolling**: All dice use `RNGService.roll_d6(count)` which returns Array[int]
- **Signal Flow**: Phase → emits `dice_rolled` → Controller displays
- **Multiplayer Sync**: NetworkManager re-emits signals to both players
- **Logging**: ActionLogger records all actions to session file

### Key Implementation Notes
1. **Array vs Single Value**: The root issue is `"roll": 4` vs `"rolls_raw": [4, 2, 5]`
2. **Backward Compatibility**: The display handler already expects the correct format
3. **Minimal Changes**: Only need to move dice aggregation outside the loop
4. **Code Reuse**: Shooting phase implementation is proven and tested
5. **Multiplayer Safe**: Changes are in resolution logic, multiplayer sync unaffected

---

## Common Pitfalls and Gotchas

### 1. Loop Variable Reuse
**Issue:** Don't reuse `roll` variable name in multiple loops
```gdscript
# ❌ Bad - variable name collision
for roll in hit_rolls:
    # ...
for roll in wound_rolls:  # Reusing 'roll'
    # ...
```

**Solution:** Use descriptive names or reuse safely
```gdscript
# ✅ Good
for hit_roll in hit_rolls:
    # ...
for wound_roll in wound_rolls:
    # ...
```

### 2. Save Roll Success Logic
**Issue:** Save rolls succeed when die >= threshold (models survive)
- Fight phase counts `failed_saves` (models die)
- Shooting phase counts `successful_saves` (models survive)

**Solution:** Stay consistent with one metric
```gdscript
# ✅ Count successes, calculate failures
var successful_saves = 0
for roll in save_rolls:
    if roll >= modified_save:
        successful_saves += 1
var failed_saves = wounds - successful_saves
```

### 3. Empty Dice Array Edge Case
**Issue:** If no attacks/hits/wounds, don't append empty dice blocks

**Solution:** Only append if dice were rolled
```gdscript
# ✅ Check before appending
if total_attacks > 0:
    result.dice.append({
        "context": "hit_roll_melee",
        "rolls_raw": hit_rolls,
        ...
    })
```

### 4. Threshold String Format
**Issue:** Weapon skill is stored as int (3), but threshold expects "3+"

**Solution:** Format as string with "+"
```gdscript
# ✅ Format threshold consistently
"threshold": str(weapon_skill) + "+"  # "3+"
```

### 5. Display Handler Null Check
**Issue:** `dice_log_display` may not be initialized in tests

**Solution:** Always check before accessing
```gdscript
# ✅ Guard against null
if not dice_log_display:
    return
```

---

## Task Execution Order

### Step 1: Modify RulesEngine.gd
1. Backup current file
2. Update hit roll aggregation (Task 1.1)
3. Update wound roll aggregation (Task 1.2)
4. Update save roll aggregation (Task 1.3)
5. Syntax check

### Step 2: Update FightController.gd
1. Enhance _on_dice_rolled() method (Task 2.1)
2. Add color-coding for dice results
3. Add weapon name display
4. Syntax check

### Step 3: Create Tests
1. Create test_melee_dice_display.gd
2. Implement format validation tests (Task 3.1)
3. Run tests and verify pass

### Step 4: Integration Testing
1. Launch Godot
2. Load save state
3. Enter fight phase
4. Execute melee attack
5. Verify dice display shows arrays
6. Compare with shooting phase output

### Step 5: Validation
1. Run all unit tests
2. Test multiplayer sync
3. Verify debug logs
4. Check no regressions in shooting phase

---

## Related Issues and PRPs

- **Similar Issue:** `/Users/robertocallaghan/Documents/claude/godotv2/PRPs/gh_issue_32_melee-dice-resolution.md`
  - Addresses the same root cause
  - This PRP provides more explicit shooting phase comparison
  - Implementation plan is more detailed with specific line numbers

- **Reference Implementation:** `/Users/robertocallaghan/Documents/claude/godotv2/PRPs/shooting-phase-resolution.md`
  - Shooting phase implementation guide
  - Dice display patterns established here

---

## Expected Outcome

### Before Fix:
```
Hit Roll Melee: [] → 0 successes
```

### After Fix:
```
Hit Roll Melee (Chainsword) (need 3+):
  Rolls: [4, 2, 5, 1, 3] → 3 successes

Wound Roll (need 2+):
  Rolls: [4, 3, 5] → 3 successes

Save Roll (need 4+):
  Rolls: [2, 5, 3] → 1 successes
```

---

## PRP Quality Score: 9/10

### Strengths:
- ✅ Clear root cause analysis with code examples
- ✅ Direct reference to working implementation (shooting phase)
- ✅ Specific file paths and line numbers
- ✅ Executable validation gates
- ✅ Comprehensive test plan
- ✅ Gotchas and pitfalls documented
- ✅ Step-by-step task execution order
- ✅ Success criteria clearly defined

### Minor Gaps:
- ⚠️ Assumes RNGService behavior (should verify it returns Array[int])
- ⚠️ Could include more edge cases (0 attacks, 0 hits scenarios)

### Confidence Level:
**9/10** - High confidence in one-pass implementation success. The issue is well-understood, the reference implementation is proven, and the changes are minimal and localized. The only uncertainty is potential edge cases in damage calculation or model removal that might interact with the dice display.
