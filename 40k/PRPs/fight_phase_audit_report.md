# Fight Phase Audit Report

## Overview

This audit compares the Fight Phase implementation in the Godot Warhammer 40k project against the official 10th edition core rules. The focus is on the online multiplayer version of the game.

**Files Audited:**
- `phases/FightPhase.gd` - Core fight phase logic
- `scripts/FightController.gd` - UI controller
- `dialogs/FightSelectionDialog.gd` - Unit selection dialog
- `dialogs/AttackAssignmentDialog.gd` - Attack assignment dialog
- `dialogs/PileInDialog.gd` - Pile-in movement dialog
- `dialogs/ConsolidateDialog.gd` - Consolidation dialog
- `autoloads/RulesEngine.gd` - Melee attack resolution
- `autoloads/NetworkManager.gd` - Multiplayer sync
- `autoloads/GameManager.gd` - Action routing

**Rules Reference:** [Warhammer 40k 10th Edition Core Rules (Wahapedia)](https://wahapedia.ru/wh40k10ed/the-rules/core-rules/), [Goonhammer Ruleshammer](https://www.goonhammer.com/ruleshammer-when-can-my-unit-fight-how-do-pile-in-and-consolidate-moves-work/), [Spikey Bits](https://spikeybits.com/10th-edition-40k-core-rules-charge-fight-phases/)

---

## 1. RULES COMPLIANCE ISSUES (Bugs / Missing Rules)

### 1.1 ~~CRITICAL: Melee Weapon Abilities Not Implemented~~ **RESOLVED (2026-02-15)**

**Rule:** Melee weapons can have abilities like Lethal Hits, Sustained Hits, Devastating Wounds, Lance, Anti-X, Twin-linked, etc. These modify hit rolls, wound rolls, and saves identically to ranged weapons.

**Resolution:** `_resolve_melee_assignment()` at `RulesEngine.gd:3380-3778` now implements the full weapon ability pipeline:
- Lethal Hits: `has_lethal_hits()` at line 3466, auto-wounds at lines 3575-3577
- Sustained Hits: `get_sustained_hits_value()` at line 3467, bonus hits at lines 3528-3531
- Devastating Wounds: `has_devastating_wounds()` at line 3468, bypass saves at lines 3606-3610
- Critical hits tracked separately at line 3523 (`if unmodified_roll == 6`)

---

### 1.2 ~~HIGH: "Which Models Can Fight" Rule Not Enforced~~ **RESOLVED (2026-02-15)**

**Rule (10e):** A model can make melee attacks if, after the Pile In move, it is either:
1. In Engagement Range (within 1") of an enemy model, OR
2. In base-to-base contact with a friendly model that is itself in base-to-base contact with an enemy model

**Resolution:** `get_eligible_melee_model_indices()` at `RulesEngine.gd:3270-3335` implements a two-pass eligibility check: first for ER (1"), then for base-contact chain. Per-model filtering applied in `_resolve_melee_assignment()` at lines 3423-3440. Only eligible models' attacks are counted.

---

### 1.3 ~~HIGH: Pile-In Must End in Engagement Range~~ **RESOLVED (2026-02-15)**

**Rule (10e):** After a Pile In move, the unit must end within Engagement Range of at least one enemy unit. If it cannot, no models can Pile In (they stay in place).

**Resolution:** `FightPhase.gd:659-661` now validates that the unit ends within Engagement Range after movement via `_can_unit_maintain_engagement_after_movement()`. If the check fails, the error message "Unit must end within Engagement Range of at least one enemy" is returned.

---

### 1.4 HIGH: Pile-In Cannot Create New Engagements

**Rule (10e):** During Pile In, a model cannot move within Engagement Range of any enemy unit that it (or its unit) was not already within Engagement Range of at the start of the Pile In move.

**Current State:** No validation prevents models from moving into engagement range of new enemy units during pile-in. The only validation is "move closer to closest enemy" and "stay within 3 inches."

**Impact:** Players could abuse pile-in to engage additional enemy units they weren't fighting, potentially locking those units in combat unexpectedly.

**Recommendation:** Before pile-in, record which enemy units the piling-in unit is already engaged with. After pile-in, validate that no model has ended within 1" of any enemy unit that wasn't in the original engagement set.

---

### 1.5 HIGH: Consolidation Cannot Create New Engagements (Same Issue as Pile-In)

**Rule (10e):** Same restriction applies to consolidation moves - cannot end within Engagement Range of enemy units the consolidating unit was not already within Engagement Range of.

**Current State:** Same gap as pile-in. The consolidation validation (`_validate_consolidate_engagement_range`, FightPhase.gd:619-663) does not check for new engagements being created.

**Recommendation:** Same fix as pile-in - track initial engagements and prevent new ones.

---

### 1.6 ~~MEDIUM: Variable Attack Characteristics (D3, D6, etc.) Not Rolled~~ **RESOLVED (2026-02-15)**

**Rule (10e):** When a weapon has a variable number of attacks (e.g., "D6" or "D3+3"), the number is rolled before making hit rolls.

**Resolution:** `RulesEngine.gd:3444` calls `roll_variable_characteristic(attacks_raw, rng)` per model. Uses the shared `roll_variable_characteristic()` function at line 3160 which handles D3, D6, 2D6, D6+N, D3+N notation.

---

### 1.7 ~~MEDIUM: Variable Damage Characteristics Not Rolled~~ **RESOLVED (2026-02-15)**

**Rule (10e):** Damage characteristics can also be variable (D3, D6+1, etc.). Damage is rolled per attack sequence that causes an unsaved wound.

**Resolution:** `RulesEngine.gd:3708-3724` rolls `damage_raw` per unsaved wound using `roll_variable_characteristic()`. Each wound resolves damage independently.

---

### 1.8 MEDIUM: Heroic Intervention Not Implemented

**Rule (10e):** At the start of the Fight phase, the non-active player can declare Heroic Interventions. Eligible Characters within 6" of an enemy unit can make a 6" move to get within Engagement Range.

**Current State:** There is a stub in `_process_heroic_intervention()` (FightPhase.gd:1020-1023) that returns "not yet implemented." The validation (`_validate_heroic_intervention_action`, FightPhase.gd:1612-1640) has basic CHARACTER keyword checking but most rules are marked as TODO.

**Impact:** A core rule that affects fight phase sequencing is missing entirely.

**Recommendation:** Implement heroic intervention with:
- Timing: Before the first fight selection
- Eligibility: CHARACTER keyword, within 6" of enemy, not already in engagement range
- Movement: Up to 6" ending within engagement range of an enemy unit
- Limitation: Must end closer to closest enemy (same as pile-in direction rule)

---

### 1.9 ~~MEDIUM: Invulnerable Saves Not Checked in Melee~~ **RESOLVED (2026-02-15)**

**Rule (10e):** If a unit has an invulnerable save, the player uses whichever save is better (armor or invulnerable) after AP modification.

**Resolution:** `RulesEngine.gd:3659-3673` gets invuln from model or unit meta stats, then calls `_calculate_save_needed()` with the invuln parameter. The shared function at lines 1404-1406 ignores AP for invuln and uses the better save value.

---

### 1.10 ~~MEDIUM: Critical Hits (Unmodified 6s) Not Tracked in Melee~~ **RESOLVED (2026-02-15)**

**Rule (10e):** An unmodified hit roll of 6 is always a successful hit (Critical Hit). This is important for triggering Lethal Hits, Sustained Hits, and other abilities. Similarly, an unmodified wound roll of 6 is a Critical Wound.

**Resolution:** `RulesEngine.gd:3522-3526` tracks unmodified 6s separately as `critical_hits`. Dice blocks include critical tracking at lines 3544-3554. Critical hit data is used for Lethal Hits and Sustained Hits interactions in the melee pipeline.

---

### 1.11 LOW: Fights Last Subphase Not Implemented

**Rule (10e):** There are three fight tiers: Fights First, Normal (Remaining Combats), and Fights Last. Units with the Fights Last ability fight after all other units.

**Current State:** While the `FightPriority` enum includes `FIGHTS_LAST` (FightPhase.gd:51) and units are categorized into `fights_last_sequence` (FightPhase.gd:44), the subphase enum only has `FIGHTS_FIRST`, `REMAINING_COMBATS`, and `COMPLETE` (FightPhase.gd:55-59). There is no `FIGHTS_LAST` subphase. The `_transition_subphase()` method (FightPhase.gd:1150-1175) goes directly from `REMAINING_COMBATS` to completion without processing the fights_last_sequence.

**Impact:** Units with Fights Last (from abilities or debuffs) would be placed in the `fights_last_sequence` dictionary but never actually activated.

**Recommendation:** Add a `FIGHTS_LAST` subphase and update `_transition_subphase()` to progress through it before completing.

---

### 1.12 LOW: Fights First + Fights Last Cancellation Not Implemented

**Rule (10e):** If a unit has both Fights First and Fights Last (e.g., a charged unit that was hit by a Fights Last debuff), the two cancel out and the unit fights in the normal Remaining Combats step.

**Current State:** `_get_fight_priority()` (FightPhase.gd:1026-1041) checks conditions sequentially - charged_this_turn is checked before fights_last, so a charged unit would always get FIGHTS_FIRST even if it has a Fights Last debuff.

**Impact:** Cancellation interactions between Fights First and Fights Last don't work correctly.

**Recommendation:** Check for both conditions and if both are present, return `NORMAL` priority.

---

### 1.13 LOW: Counter-Offensive Stratagem Not Implemented

**Rule (10e):** Counter-Offensive (2 CP) allows the non-active player to select one of their eligible units to fight next, out of the normal alternation sequence, after the active player has selected a unit to fight.

**Current State:** No stratagem system exists for the fight phase.

**Impact:** A key tactical option is missing.

**Recommendation:** Implement as a special action available during the Remaining Combats subphase that lets the defender interrupt the normal alternation order.

---

## 2. MULTIPLAYER-SPECIFIC ISSUES

### 2.1 RESOLVED: NetworkManager Exempt Actions

The fight phase actions have been correctly added to the `exempt_actions` list in `NetworkManager.gd:1237-1252`. This allows cross-turn actions where the non-active player can select fighters during the active player's fight phase. This was previously identified as a critical blocker in the PRPs and appears to have been fixed.

### 2.2 RESOLVED: GameManager Action Registration

`GameManager.gd:108-126` now routes all modern fight phase actions (`SELECT_FIGHTER`, `PILE_IN`, `ASSIGN_ATTACKS`, `CONFIRM_AND_RESOLVE_ATTACKS`, `ROLL_DICE`, `CONSOLIDATE`, `SKIP_UNIT`, `HEROIC_INTERVENTION`, `END_FIGHT`) to the correct phase. This was previously a critical blocker.

### 2.3 MEDIUM: Race Condition in Sequential Dialog Actions

**Current State:** In `FightController._on_attacks_confirmed()` (FightController.gd:1357-1392), attack assignments are sent one at a time with `await get_tree().create_timer(0.05).timeout` between them, then CONFIRM and ROLL_DICE are sent with a 0.1s delay.

**Impact:** In multiplayer with network latency, these tiny fixed delays may not be sufficient. If actions arrive out of order, attacks could be confirmed before all assignments are processed, or dice could be rolled before confirmation completes.

**Recommendation:** Use proper action sequencing (wait for acknowledgment of each action before sending the next) rather than fixed time delays. Alternatively, batch all assignments into a single action.

### 2.4 MEDIUM: Fight Selection Dialog Not Properly Synced for Remote Player

**Current State:** The `FightSelectionDialog` is opened when the `fight_selection_required` signal fires. On the host, this happens naturally. On the client, it relies on `NetworkManager._emit_client_visual_updates()` detecting `trigger_fight_selection` in the action result metadata (FightPhase.gd:998-999). However, the initial fight selection when the phase enters may be missed because the signal fires during `enter_phase` before the client's controller is connected.

**Impact:** The client may not see the initial fight selection dialog, requiring the "re-trigger" workaround in `FightController.set_phase()` (line 346-350) which adds a 0.1s delay. This is fragile.

**Recommendation:** Store the pending dialog data in the phase state and have the controller explicitly request it when connecting, rather than relying on signal timing.

### 2.5 LOW: Pile-In/Consolidate Drag-and-Drop Not Synced Visually

**Current State:** During pile-in and consolidation, the active player drags model tokens around the battlefield. The remote player does not see this movement in real-time - they only see the final positions after the PILE_IN or CONSOLIDATE action is confirmed.

**Impact:** The remote player has no visual feedback of what the opponent is doing during pile-in/consolidation. They see models "teleport" to new positions.

**Recommendation:** Consider sending position update messages during drag to show the remote player what's happening, or at minimum show an animation of the models moving from old to new positions when the final action arrives.

---

## 3. QUALITY OF LIFE IMPROVEMENTS

### 3.1 Attack Assignment Dialog UX

**Current State:** The `AttackAssignmentDialog` (AttackAssignmentDialog.gd) requires the player to:
1. Select a weapon from a list
2. Select a target from a list
3. Click "Add Assignment"
4. Repeat for each weapon
5. Click "OK" to confirm

**Issues:**
- No "Assign All to Target" shortcut for the common case of all weapons attacking one target
- No visual preview of expected damage or odds
- Weapon stats shown in compact text format (A:3 S:5 AP:-2 D:2) rather than a formatted table
- No ability to remove individual assignments (only add)
- The dialog doesn't show which models have which weapons - it just lists unit-level weapons

**Recommendation:**
- Add an "All to Target" button that assigns all unassigned weapons to the selected target
- Add a "Clear Last" button to remove the most recent assignment
- Show a mathhammer-style expected damage prediction as assignments are made
- Format weapon stats in a readable table with column headers

### 3.2 Pile-In/Consolidate Movement Feedback

**Current State:** The pile-in and consolidate dialogs show textual status ("Movement valid" / error messages) and visual indicators (green/red lines, coherency dots). However:
- The dialog window can overlap the battlefield, obscuring models
- There's no distance indicator showing how many inches a model has moved
- No "snap to engagement range" helper
- The 3" range circle is drawn around the model's ORIGINAL position, not as a boundary the model must stay within

**Recommendation:**
- Make dialogs dockable/moveable to avoid obscuring the battlefield
- Show distance moved in inches next to each model being dragged
- Add a visual engagement range ring (1") around nearby enemy models to help players see where they need to reach
- Consider a "snap to base contact" feature that auto-positions a model in base contact with the nearest enemy

### 3.3 Fight Sequence Visibility

**Current State:** The fight sequence is displayed in a small `ItemList` in the right panel. During multiplayer, the non-selecting player may not have clear visibility into whose turn it is to select a fighter.

**Recommendation:**
- Add a prominent banner/overlay showing "Player X is selecting a unit to fight" (similar to how the FightSelectionDialog shows a colored panel, but visible even when the dialog is closed)
- Show the full fight sequence timeline with visual indicators for Fights First / Remaining Combats phases
- Highlight the alternation pattern so players understand the back-and-forth selection order

### 3.4 Combat Results Display

**Current State:** Dice results are shown in the right-panel combat log using BBCode formatting. The display includes color-coded dice (green for successes, gray for failures) and summary lines.

**Issues:**
- Results can scroll by quickly if there are multiple attack assignments
- No summary "scoreboard" showing total damage dealt
- No visual dice animation (results appear as text immediately)
- The combat log in the right panel is relatively small (230x100px minimum size)

**Recommendation:**
- Add a summary panel after all attacks resolve showing: total attacks → hits → wounds → failed saves → damage → casualties
- Consider a brief dice roll animation (even just a quick number randomization) for engagement
- Make the combat log resizable or add a "full log" popup for detailed review
- Show a floating damage number over damaged/destroyed units on the battlefield

### 3.5 No Visual Indication of Engaged Units on the Board

**Current State:** During the fight phase, there are engagement range circles drawn around the active fighter's models. However, there is no board-level indicator showing WHICH units across the entire battlefield are currently engaged in combat.

**Recommendation:**
- At the start of the fight phase, draw engagement indicators (colored borders, connecting lines, or highlighted bases) around all units that are in engagement range
- Use color coding to distinguish Fights First units from normal units
- Show a "crossed swords" icon over engaged unit tokens

### 3.6 No Confirmation Before Phase Ends

**Current State:** The END_FIGHT action is always valid and immediately ends the phase (FightPhase.gd:1642-1644). There's no confirmation dialog.

**Impact:** A player could accidentally end the fight phase before all their units have fought.

**Recommendation:** If there are eligible units that haven't fought yet, show a confirmation dialog: "X units have not yet fought. Are you sure you want to end the Fight Phase?"

---

## 4. VISUAL IMPROVEMENTS

### 4.1 Pile-In/Consolidate Movement Arrows

**Current State:** Direction lines (yellow/green/red) are drawn from model to closest enemy. These are functional but basic.

**Recommendation:**
- Replace plain lines with directional arrows
- Show the movement path (from original position to current drag position) as a dashed line
- Add a distance label on the movement path showing inches moved
- Use animated dashes or a "marching ants" pattern to indicate the valid movement envelope

### 4.2 Engagement Range Visualization

**Current State:** Engagement range circles are drawn as simple orange circles with transparent fill (FightController.gd:504-521).

**Recommendation:**
- Use a pulsing animation to draw attention to engaged models
- Show engagement BETWEEN units with connecting lines or highlighted overlap zones
- Color enemy engagement circles differently from friendly ones
- Add a subtle "combat zone" highlight covering the area where engaged units overlap

### 4.3 Fight Phase Header / State Banner

**Current State:** The phase label in the bottom HUD shows "Fight" with a basic phase indicator. The subphase transition is logged in the combat log with yellow text.

**Recommendation:**
- Add a prominent phase state banner showing: current subphase (FIGHTS FIRST / REMAINING COMBATS), whose turn to select, number of units remaining
- Animate subphase transitions with a brief overlay ("FIGHTS FIRST COMPLETE - REMAINING COMBATS")
- Use distinct color schemes for each subphase

### 4.4 Unit Tokens During Fight Phase

**Current State:** Model tokens are plain visual representations without fight-phase-specific indicators.

**Recommendation:**
- Add a visual "has fought" indicator (dimmed opacity, checkmark overlay, or grayed-out border)
- Show a "charging" indicator (flame/speed lines) on units that have the Fights First priority from charging
- During a unit's activation, highlight its models distinctly from all other models on the board
- Show a brief "attack" animation or flash when melee attacks resolve

### 4.5 Damage Application Visualization

**Current State:** Damage is applied via state diffs that update model `current_wounds` and `alive` flags. The visual update happens when tokens refresh from state, but there is no animation.

**Recommendation:**
- Show damage numbers floating up from wounded models
- Flash models red when they take wounds
- Show a brief "destroyed" animation (fade out, collapse, etc.) when a model dies
- Display a wound tracker on multi-wound models during combat

---

## 5. SUMMARY TABLE

*Last reviewed: 2026-02-15*

| # | Issue | Severity | Category | Status |
|---|-------|----------|----------|--------|
| 1.1 | Melee weapon abilities not implemented | CRITICAL | Rules | **RESOLVED** (Lethal Hits, Sustained Hits, Devastating Wounds all implemented in `_resolve_melee_assignment()` at RulesEngine.gd:3380-3778) |
| 1.2 | Per-model fight eligibility not checked | HIGH | Rules | **RESOLVED** (`get_eligible_melee_model_indices()` at RulesEngine.gd:3270-3335 with two-pass eligibility check) |
| 1.3 | Pile-in must end in engagement range | HIGH | Rules | **RESOLVED** (FightPhase.gd:659-661 validates unit ends in ER after movement) |
| 1.4 | Pile-in cannot create new engagements | HIGH | Rules | Missing |
| 1.5 | Consolidate cannot create new engagements | HIGH | Rules | Missing |
| 1.6 | Variable attack characteristics not rolled | MEDIUM | Rules | **RESOLVED** (`roll_variable_characteristic()` at RulesEngine.gd:3444) |
| 1.7 | Variable damage characteristics not rolled | MEDIUM | Rules | **RESOLVED** (RulesEngine.gd:3708-3724 rolls damage per unsaved wound) |
| 1.8 | Heroic Intervention not implemented | MEDIUM | Rules | Stub (FightPhase.gd:1020-1023 still returns "not yet implemented") |
| 1.9 | Invulnerable saves not checked in melee | MEDIUM | Rules | **RESOLVED** (RulesEngine.gd:3659-3673 checks invuln from model/unit meta, uses `_calculate_save_needed()` with invuln) |
| 1.10 | Critical hits not tracked in melee | MEDIUM | Rules | **RESOLVED** (RulesEngine.gd:3522-3526 tracks unmodified 6s, used for Lethal/Sustained Hits) |
| 1.11 | Fights Last subphase not implemented | LOW | Rules | Partial (enum and sequence dict exist, but no FIGHTS_LAST subphase in transition logic) |
| 1.12 | Fights First + Last cancellation | LOW | Rules | Missing |
| 1.13 | Counter-Offensive stratagem | LOW | Rules | Missing |
| 2.1 | NetworkManager exempt actions | - | Multiplayer | RESOLVED |
| 2.2 | GameManager action registration | - | Multiplayer | RESOLVED |
| 2.3 | Race condition in dialog sequencing | MEDIUM | Multiplayer | Partially Mitigated (still uses fixed delays 0.05-0.3s, not proper signal sync) |
| 2.4 | Initial dialog sync for client | MEDIUM | Multiplayer | Workaround (FightController recreates dialogs, fragile signal-based) |
| 2.5 | Drag movement not synced visually | LOW | Multiplayer | Missing (local visual only, remote sees teleport on confirm) |
| 3.1 | Attack assignment dialog UX | - | QoL | Suggested |
| 3.2 | Movement feedback improvements | - | QoL | Suggested |
| 3.3 | Fight sequence visibility | - | QoL | Suggested |
| 3.4 | Combat results display | - | QoL | Suggested |
| 3.5 | Engaged units board indicator | - | QoL | Suggested |
| 3.6 | End phase confirmation | - | QoL | Suggested |
| 4.1 | Movement arrows/paths | - | Visual | Suggested |
| 4.2 | Engagement range visualization | - | Visual | Suggested |
| 4.3 | Phase state banner | - | Visual | Suggested |
| 4.4 | Unit tokens during fight | - | Visual | Suggested |
| 4.5 | Damage application visualization | - | Visual | Suggested |

---

## 6. RECOMMENDED PRIORITY ORDER

*Updated 2026-02-15: Phase 1 fully complete, Phase 2 partially complete.*

### Phase 1: Core Rules Correctness — **COMPLETE**
1. ~~**1.1** - Melee weapon abilities (reuse shooting pipeline)~~ ✅
2. ~~**1.9** - Invulnerable saves in melee~~ ✅
3. ~~**1.10** - Critical hit tracking in melee~~ ✅
4. ~~**1.2** - Per-model fight eligibility~~ ✅
5. ~~**1.6 + 1.7** - Variable attack/damage characteristics~~ ✅

### Phase 2: Movement Rules Compliance — **PARTIALLY COMPLETE**
6. ~~**1.3** - Pile-in engagement range validation~~ ✅
7. **1.4 + 1.5** - No new engagements during pile-in/consolidate — **STILL OPEN**

### Phase 3: Multiplayer Stability
8. **2.3** - Fix race condition in sequential actions (partially mitigated with fixed delays)
9. **2.4** - Proper initial dialog sync

### Phase 4: Missing Rules
10. **1.8** - Heroic Intervention (still stub)
11. **1.11** - Fights Last subphase (partial — enum exists, no transition logic)
12. **1.12** - Fights First/Last cancellation

### Phase 5: QoL & Visual Polish
13. QoL improvements (3.1 - 3.6)
14. Visual improvements (4.1 - 4.5)
