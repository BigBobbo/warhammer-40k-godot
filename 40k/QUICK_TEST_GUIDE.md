# Interactive Save System - Quick Test Guide

## 🚀 5-Minute Test

### Prerequisites
- Game running
- Two armies deployed (any units)
- In Shooting Phase

### Steps

1. **Select Shooter**
   - Click unit in right panel unit list

2. **Assign Target**
   - Click weapon in weapon tree
   - Click enemy unit on board (or use auto-assign button)

3. **Confirm Attack**
   - Click "Confirm Targets" button
   - Watch dice log for hit/wound rolls

4. **🆕 SaveDialog Should Appear**
   - Shows attack info (attacker, weapon, AP, damage)
   - Shows save stats (base save, modifiers)
   - Shows model grid with HP
   - Auto-allocated to follow 10e rules

5. **Roll Saves**
   - Click "Roll All Saves" button
   - Watch dice log fill with results
   - Green = save passed
   - Red = save failed

6. **Apply Damage**
   - Click "Apply Damage" button
   - Dialog closes
   - Damage applied to target unit
   - Models removed if HP = 0

### ✅ Success Indicators

- Dialog appears after wound rolls
- Models show correct HP
- Dice results match expectations (d6 >= save value)
- Damage applied to correct models
- Shooting continues normally

### ❌ Failure Indicators

- Dialog never appears (check console)
- Saves don't roll (check for errors)
- Damage not applied (check action processing)
- Game crashes (check stack trace)

### 🐛 Quick Debug

**Dialog doesn't show:**
```bash
# Check console for:
"ShootingPhase: Awaiting defender to make saves..."
"ShootingController: SaveDialog shown for..."
```

**Action fails:**
```bash
# Check console for:
"NetworkManager: Validating action type=APPLY_SAVES"
"ShootingPhase: Save resolution complete"
```

**Damage not applied:**
```bash
# Check console for:
"ShootingPhase: [unit]: X saves passed, Y failed → Z casualties"
```

## 📊 Test Scenarios

### Scenario 1: All Saves Pass
- **Setup**: High save (2+), low AP (0)
- **Expected**: All saves passed, no damage
- **Verify**: Models keep full HP

### Scenario 2: All Saves Fail
- **Setup**: Low save (6+), high AP (-3)
- **Expected**: All saves failed, casualties
- **Verify**: Models destroyed

### Scenario 3: Mixed Results
- **Setup**: Medium save (4+), medium AP (-1)
- **Expected**: Some pass, some fail
- **Verify**: Partial damage

### Scenario 4: Wounded Model Priority
- **Setup**: Target unit has a model with reduced HP
- **Expected**: That model allocated first
- **Verify**: Wounded model marked with *

## 🎯 Key Things to Verify

1. ✅ Dialog UI looks correct
2. ✅ Save calculation is accurate
3. ✅ Dice rolling works
4. ✅ Damage applies correctly
5. ✅ Models die at 0 HP
6. ✅ Phase continues normally

## 📝 Report Template

If you find bugs, report them like this:

```
**Bug**: [Brief description]
**Steps**:
1. [How to reproduce]
2. ...

**Expected**: [What should happen]
**Actual**: [What happened]
**Console**: [Relevant console output]
**Screenshot**: [If applicable]
```

## 🎉 When Test Passes

Mark Phase 1 MVP as COMPLETE in:
- `PRPs/saves_and_damage_allocation_prp.md` (Section 7)
- `40k/SAVE_SYSTEM_COMPLETE.md` (Success Criteria)

## 📚 Full Documentation

For detailed info, see:
- `40k/SAVE_SYSTEM_COMPLETE.md` - Full implementation guide
- `40k/SAVE_SYSTEM_IMPLEMENTATION_STATUS.md` - Architecture details
- `PRPs/saves_and_damage_allocation_prp.md` - Original requirements

---

**Good luck testing! 🚀**
