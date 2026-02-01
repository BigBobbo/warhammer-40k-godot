# Manual UI Test Checklist

This checklist covers UI interactions that cannot be reliably automated due to Godot's input system architecture. Each section should be tested manually before releases.

## Why Manual Testing?

Godot's `DisplayServer.mouse_get_position()` cannot be mocked, meaning automated tests cannot reliably simulate mouse interactions. The game code queries the viewport for mouse position, which always returns the *real* mouse position, not simulated positions.

Manual testing with this checklist ensures complete coverage of user interactions.

---

## Test Setup

Before testing:
1. Launch the game normally (not in headless mode)
2. Ensure debug logging is enabled to capture any errors
3. Have this checklist open for marking progress
4. Take screenshots at key steps (optional but recommended)

---

## 1. Deployment Phase

### 1.1 Unit Selection
- [ ] Click a unit in the unit list → Unit name highlights
- [ ] Click same unit again → Unit deselects
- [ ] Click different unit → Previous unit deselects, new unit highlights
- [ ] Verify unit stats panel shows correct stats for selected unit

### 1.2 Unit Placement
- [ ] With unit selected, click in valid deployment zone → Ghost preview appears
- [ ] Move mouse → Ghost follows cursor
- [ ] Click to confirm → Unit deploys at clicked position
- [ ] Verify all models appear in formation

### 1.3 Deployment Zone Validation
- [ ] Try clicking outside deployment zone → Placement rejected (feedback shown)
- [ ] Try clicking in enemy deployment zone → Placement rejected
- [ ] Try clicking on terrain obstacle → Placement rejected
- [ ] Try clicking where models would overlap existing unit → Placement rejected

### 1.4 Repositioning
- [ ] Click on deployed unit → Unit selects
- [ ] Drag unit to new position → Unit follows mouse
- [ ] Release in valid position → Unit repositions
- [ ] Release outside deployment zone → Unit returns to original position

### 1.5 Formation
- [ ] Deploy multi-model unit → Models appear in coherent formation
- [ ] Verify all models within 2" of another model (coherency)
- [ ] For 6+ model units, verify models within 2" of 2 other models

### 1.6 Turn Flow
- [ ] Player 1 deploys unit → Turn switches to Player 2
- [ ] Player 2 deploys unit → Turn switches back to Player 1
- [ ] Continue until all units deployed

### 1.7 End Deployment
- [ ] Click "End Deployment" button → Phase transitions to Command Phase

**Screenshot checkpoints:**
- After first unit deployed
- With all units deployed
- Error message when invalid placement attempted

---

## 2. Movement Phase

### 2.1 Unit Selection
- [ ] Click on friendly unit → Unit selects, movement range shown
- [ ] Click on enemy unit → No selection (or shows info only)
- [ ] Click empty area → Deselects current unit

### 2.2 Normal Movement
- [ ] With unit selected, click destination → Unit moves
- [ ] Verify movement doesn't exceed movement characteristic
- [ ] Verify path avoids other units
- [ ] Verify unit can't move through enemy models

### 2.3 Model-by-Model Movement (Multi-model units)
- [ ] Click individual model → Model highlights
- [ ] Drag model to new position → Model follows cursor
- [ ] Release model → Model moves (if valid)
- [ ] Verify coherency maintained after each model moves

### 2.4 Advance
- [ ] Click "Advance" button with unit selected → D6 roll shown
- [ ] Move unit with advance bonus → Distance includes advance
- [ ] Verify "Advanced" flag set on unit
- [ ] Verify unit cannot shoot regular weapons this turn

### 2.5 Fall Back
- [ ] Select unit in engagement range → "Fall Back" option available
- [ ] Click "Fall Back" → Unit can move away from engagement
- [ ] Verify unit cannot shoot or charge this turn

### 2.6 Movement Restrictions
- [ ] Try moving through impassable terrain → Movement blocked
- [ ] Try ending movement on another model → Rejected
- [ ] Try breaking coherency → Warning shown or movement rejected

### 2.7 Undo
- [ ] Move a model → Click "Undo" → Model returns to previous position
- [ ] Multiple undos work sequentially

**Screenshot checkpoints:**
- Movement range indicator showing
- Unit mid-movement
- Coherency warning (if applicable)

---

## 3. Shooting Phase

### 3.1 Shooter Selection
- [ ] Click friendly unit with ranged weapons → Shooting options appear
- [ ] Verify weapon profiles displayed correctly
- [ ] Units that moved/advanced show correct weapon restrictions

### 3.2 Target Selection
- [ ] Click "Select Target" → Valid targets highlight
- [ ] Click enemy unit in range/LoS → Target selected
- [ ] Try clicking unit out of range → Rejected with feedback
- [ ] Try clicking unit out of LoS → Rejected with feedback

### 3.3 Weapon Selection
- [ ] Click weapon from weapon list → Weapon selected
- [ ] Verify weapon stats shown (range, S, AP, D, keywords)
- [ ] Select multiple weapons (if allowed) → All selected weapons shown

### 3.4 Model Assignment
- [ ] Assign specific models to shoot → Models highlight
- [ ] Verify model count matches unit roster

### 3.5 Roll to Hit
- [ ] Click "Roll to Hit" → Dice animation plays
- [ ] Results show hits/misses clearly
- [ ] Critical hits (6s) highlighted
- [ ] Re-roll options available if applicable

### 3.6 Roll to Wound
- [ ] Click "Roll to Wound" → Wound rolls shown
- [ ] Strength vs Toughness calculation correct
- [ ] Critical wounds (6s) highlighted

### 3.7 Save Rolls
- [ ] Enemy makes save rolls → Results shown
- [ ] AP modifier applied correctly
- [ ] Invulnerable saves offered when applicable

### 3.8 Damage Application
- [ ] Wounds applied to target unit
- [ ] Models removed when wounds exceed remaining
- [ ] Remaining wounds tracked correctly

### 3.9 Keywords in Action
- [ ] Assault weapon: Can shoot after advancing (with -1 to hit)
- [ ] Heavy weapon: +1 to hit if remained stationary
- [ ] Pistol weapon: Can shoot in engagement range
- [ ] Rapid Fire: Extra attacks at half range
- [ ] Torrent: No hit roll needed

**Screenshot checkpoints:**
- Target selection overlay
- Dice roll results
- Damage allocation

---

## 4. Charge Phase

### 4.1 Charger Selection
- [ ] Click unit eligible to charge → Charge options appear
- [ ] Units that fell back cannot charge
- [ ] Units that advanced can only charge if they have assault weapons

### 4.2 Target Declaration
- [ ] Select enemy units within 12" → Targets declared
- [ ] Multiple targets can be selected
- [ ] Verify all targets displayed

### 4.3 Charge Roll
- [ ] Click "Roll Charge" → 2D6 rolled
- [ ] Result shown clearly
- [ ] Compare to distance needed

### 4.4 Charge Movement
- [ ] If roll successful, move models into engagement range
- [ ] Verify at least one model reaches engagement range
- [ ] Verify unit ends in coherency

### 4.5 Failed Charge
- [ ] If roll insufficient → Charge fails
- [ ] Unit does not move
- [ ] Appropriate feedback shown

### 4.6 Overwatch
- [ ] Defender can use Overwatch (1 CP)
- [ ] Hits on 6s only
- [ ] Can interrupt charge

**Screenshot checkpoints:**
- Charge distance indicator
- Successful charge position

---

## 5. Fight Phase

### 5.1 Fight Order
- [ ] Chargers fight first
- [ ] Then alternating activation (defender first)
- [ ] UI shows whose turn to select

### 5.2 Fighter Selection
- [ ] Defending player selects unit first
- [ ] Click eligible unit → Selected for fighting
- [ ] Wrong player cannot select

### 5.3 Pile In
- [ ] Move up to 3" towards nearest enemy
- [ ] Each model must end closer to nearest enemy
- [ ] Verify pile-in movement shown

### 5.4 Attack Allocation
- [ ] Select melee weapons
- [ ] Assign attacks to enemy models
- [ ] Verify attack count matches weapon profiles

### 5.5 Fight Resolution
- [ ] Roll to hit (using WS)
- [ ] Roll to wound
- [ ] Save rolls
- [ ] Damage application

### 5.6 Consolidation
- [ ] After fighting, move up to 3"
- [ ] Must end closer to nearest enemy (if possible)
- [ ] Can consolidate into new combat

**Screenshot checkpoints:**
- Pile-in movement
- Attack allocation
- Consolidation

---

## 6. Morale Phase

### 6.1 Battle-shock Test
- [ ] Units that lost models roll 2D6
- [ ] Compare to Leadership characteristic
- [ ] Fail = Battle-shocked

### 6.2 Battle-shocked Effects
- [ ] Cannot use Stratagems
- [ ] Objective Control reduced to 0
- [ ] Visual indicator shown on unit

**Screenshot checkpoints:**
- Battle-shock test result
- Battle-shocked unit indicator

---

## 7. Camera and UI Controls

### 7.1 Camera Movement
- [ ] WASD or arrow keys → Camera pans
- [ ] Middle mouse drag → Camera pans
- [ ] Mouse wheel → Zoom in/out
- [ ] Zoom limits enforced (not too close/far)

### 7.2 Camera Reset
- [ ] Press Home or click reset button → Camera returns to default

### 7.3 UI Panels
- [ ] Unit panel shows selected unit info
- [ ] Phase indicator shows current phase
- [ ] Turn indicator shows current player
- [ ] Resource display shows CP/VP

### 7.4 Tooltips
- [ ] Hover over weapon → Stats tooltip appears
- [ ] Hover over ability → Description shows
- [ ] Tooltips dismiss when mouse moves

---

## 8. Save/Load

### 8.1 Save Game
- [ ] Click Save → Save dialog appears
- [ ] Enter name → Game saves
- [ ] Verify save file created

### 8.2 Load Game
- [ ] Click Load → Load dialog appears
- [ ] Select save file → Game loads
- [ ] Verify state restored correctly (units, phase, resources)

---

## 9. Multiplayer

### 9.1 Host Game
- [ ] Click "Host" → Server starts
- [ ] Port shown for client connection

### 9.2 Join Game
- [ ] Enter host IP/port → Click "Join"
- [ ] Connection established
- [ ] Both players see same state

### 9.3 Synchronization
- [ ] Player 1 action → Visible on Player 2's screen
- [ ] Turn changes sync correctly
- [ ] Dice rolls sync correctly

---

## Test Results Template

| Test Section | Pass | Fail | Notes |
|--------------|------|------|-------|
| Deployment | | | |
| Movement | | | |
| Shooting | | | |
| Charge | | | |
| Fight | | | |
| Morale | | | |
| Camera/UI | | | |
| Save/Load | | | |
| Multiplayer | | | |

**Tester:** ________________
**Date:** ________________
**Build Version:** ________________

---

## Reporting Issues

When a test fails:
1. Note the exact step that failed
2. Capture a screenshot
3. Check the debug log for errors
4. Create a GitHub issue with:
   - Steps to reproduce
   - Expected behavior
   - Actual behavior
   - Screenshot
   - Log excerpt

---

## Notes

- This checklist should be run before each release
- Critical paths (deployment, basic combat) should be tested after any significant changes
- Multiplayer tests require two computers or two game instances
