# Fight Phase Audit — Rules Compliance & Implementation Review

> Audit of `FightPhase.gd` (1,752 lines), `FightController.gd` (2,048 lines),
> `FightSelectionDialog.gd`, `AttackAssignmentDialog.gd`, `PileInDialog.gd`,
> `ConsolidateDialog.gd`, and `RulesEngine.gd` (melee resolution) against
> Warhammer 40,000 10th Edition core rules, with focus on online multiplayer.

---

## Executive Summary

The fight phase implementation covers the **core combat loop** well: alternating unit activation with Fights First / Remaining Combats subphases, pile-in movement with drag-and-drop, attack assignment with weapon selection, melee combat resolution via `RulesEngine._resolve_melee_assignment()`, and consolidation with dual engagement/objective modes. The melee resolution pipeline has been significantly improved since the prior PRP audit — it now includes **Lethal Hits, Sustained Hits, Devastating Wounds, variable attacks/damage, invulnerable saves, critical hit tracking, and Feel No Pain**. However, several **rules-required features remain missing**, and the **multiplayer integration has meaningful gaps** in dialog synchronization and action sequencing. There are also quality-of-life and visual improvements that would make the phase more usable.

> **NOTE:** This audit supersedes and corrects the earlier `40k/PRPs/fight_phase_audit_report.md`. Several issues from that report (1.1, 1.6, 1.7, 1.9, 1.10) have been resolved in the current codebase.

---

## 1. Rules Compliance — What's Implemented Correctly

| Rule | Status | Location |
|------|--------|----------|
| Unit eligibility: must be in engagement range (1") of enemy | ✅ | `FightPhase.gd:1479-1496` — `_is_unit_in_combat()` uses shape-aware edge-to-edge distance |
| Fight order: charged units get Fights First priority | ✅ | `FightPhase.gd:1026-1029` — checks `flags.charged_this_turn` |
| Fight order: abilities grant Fights First | ✅ | `FightPhase.gd:1032-1035` — checks unit abilities for "fights_first" |
| Alternating activation: defending player selects first | ✅ | `FightPhase.gd:131` — `current_selecting_player = _get_defending_player()` |
| Player alternation after each unit fights | ✅ | `FightPhase.gd:987,1012` — `_switch_selecting_player()` after consolidation or skip |
| Subphase transition: Fights First → Remaining Combats | ✅ | `FightPhase.gd:1150-1175` — `_transition_subphase()` |
| Pile-in: 3" maximum movement | ✅ | `FightPhase.gd:315-317` — `Measurement.distance_inches()` check |
| Pile-in: must move toward closest enemy | ✅ | `FightPhase.gd:320-321` — `_is_moving_toward_closest_enemy()` with edge-to-edge |
| Pile-in: unit coherency required (2") | ✅ | `FightPhase.gd:328-331` — `_validate_unit_coherency()` |
| Pile-in: no model overlaps | ✅ | `FightPhase.gd:324-326` — `_validate_no_overlaps_for_movement()` with wall check |
| Consolidation: 3" movement limit | ✅ | `FightPhase.gd:641-643` — distance check in engagement mode |
| Consolidation: toward closest enemy (engagement mode) | ✅ | `FightPhase.gd:645-647` — direction validation |
| Consolidation: toward closest objective (objective fallback) | ✅ | `FightPhase.gd:696-698` — `_is_moving_toward_closest_objective()` |
| Consolidation: dual mode (engagement → objective → none) | ✅ | `FightPhase.gd:438-457` — `_determine_consolidate_mode()` |
| Melee targets must be in engagement range | ✅ | `FightPhase.gd:371-373` — `_units_in_engagement_range()` |
| Engagement range: shape-aware edge-to-edge 1" | ✅ | `FightPhase.gd:1530-1532` — `Measurement.is_in_engagement_range_shape_aware()` |
| Attack assignment: weapon must be melee type | ✅ | `FightPhase.gd:379-380` — checks `weapon.type == "melee"` |
| Attack splitting: can assign different weapons to different targets | ✅ | `AttackAssignmentDialog.gd` — multiple assignments supported |
| Hit rolls use WS (not BS) | ✅ | `RulesEngine.gd:3095` — `ws = weapon_profile.get("ws", 4)` |
| Critical hits: unmodified 6 to hit tracked | ✅ | `RulesEngine.gd:3134-3136` — tracks `critical_hits` count |
| Lethal Hits: critical hits auto-wound | ✅ | `RulesEngine.gd:3174-3183` — auto-wounds skipping wound rolls |
| Sustained Hits: critical hits generate bonus hits (including D3/D6 variants) | ✅ | `RulesEngine.gd:3150-3153` — calls `roll_sustained_hits()` |
| Devastating Wounds: critical wounds bypass saves | ✅ | `RulesEngine.gd:3215-3216` — separates critical from regular wounds |
| Variable attacks (D3, D6, D6+1) rolled per model | ✅ | `RulesEngine.gd:3077-3090` — `roll_variable_characteristic()` per model |
| Variable damage (D3, D6) rolled per unsaved wound | ✅ | `RulesEngine.gd:3259-3275` — per-wound variable damage rolling |
| Invulnerable saves checked (uses better of armor/invuln) | ✅ | `RulesEngine.gd:3228-3240` — `_calculate_save_needed()` with invuln |
| Feel No Pain rolls after saves | ✅ | `RulesEngine.gd:3284-3294` — `roll_feel_no_pain()` |
| Torrent weapons auto-hit in melee | ✅ | `RulesEngine.gd:3112-3125` — auto-hit path for torrent |
| Unmodified 1 always misses (hit roll) | ✅ | `RulesEngine.gd:3129` — explicit auto-miss check |
| Unmodified 1 always fails (save roll) | ✅ | `RulesEngine.gd:3247` — `roll > 1 and roll >= save_threshold` |
| Wound threshold calculated correctly (S vs T table) | ✅ | `RulesEngine.gd:3166` — `_calculate_wound_threshold()` |
| No cover in melee | ✅ | `RulesEngine.gd:3238` — passes `false` for cover param |
| Unit marked as fought after consolidation | ✅ | `FightPhase.gd:973-979` — sets `has_fought` flag |

---

## 2. Rules Compliance — What's Missing or Incomplete

### 2.1 HIGH: Per-Model Fight Eligibility Not Enforced

**Rule (10e):** A model can make melee attacks if, after the Pile In move, it is either:
1. In Engagement Range (within 1") of an enemy model, OR
2. In base-to-base contact with a friendly model that is itself in base-to-base contact with an enemy model

**Current State:** The code checks whether the *unit* is in engagement range (`_is_unit_in_combat`, `_units_in_engagement_range`) but does not filter individual models that are eligible to attack. In `_resolve_melee_assignment()` (RulesEngine.gd:3077-3090), ALL alive models in the unit contribute their weapon attacks, regardless of whether they are individually within engagement range or connected through the base-contact chain.

**Impact:** A unit of 10 models where only 3 are in engagement range would incorrectly make attacks with all 10 models. This inflates damage output significantly. This is one of the most impactful rules discrepancies.

**Recommendation:** After pile-in, compute per-model eligibility. For each model, verify it is either within 1" of an enemy OR in base contact with a friendly model that is in base contact with an enemy. Only eligible models should contribute their attacks to the `attacking_models` array passed to RulesEngine.

---

### 2.2 HIGH: Pile-In Must End with Unit in Engagement Range

**Rule (10e):** "A Pile-in Move is a 3" move that, if made, must result in the unit being in Unit Coherency and within Engagement Range of one or more enemy units." If it cannot, no models can pile in.

**Current State:** The pile-in validation (`_validate_pile_in`, FightPhase.gd:290-333) checks that each individual model moves closer to the closest enemy and stays within 3", maintains coherency, and doesn't overlap. But it does NOT validate that the **unit as a whole** ends in engagement range after the pile-in completes. A unit could theoretically pile-in in ways that take all models outside 1" of any enemy.

**Impact:** Invalid pile-in positions would be accepted, potentially allowing a unit to "pile in" away from engagement.

**Recommendation:** Add a final validation step after all model movements: verify that at least one model in the unit is within 1" of an enemy model after pile-in.

---

### 2.3 HIGH: Base-to-Base Contact Not Enforced in Pile-In/Consolidation

**Rule (10e):** "Each model that makes a Pile-in move must end closer to the closest enemy model, **and in base-to-base contact with it if possible.**" Same requirement for consolidation in engagement mode.

**Current State:** The "move toward closest enemy" direction is checked, but there is no validation that models end in base-to-base contact when it would be achievable within the 3" movement limit. The PileInDialog shows "if possible" in the instructions but doesn't enforce it. Similarly, `ConsolidateDialog.gd` mentions base contact as a goal but doesn't validate.

**Impact:** Players can place models close to but not touching enemies even when base contact is achievable, gaining a positional advantage that the rules don't allow.

**Recommendation:** After pile-in/consolidate, for each model that moved, check if it could have ended in base contact (i.e., the base-to-base position is reachable within 3"). If so, warn or reject the placement.

---

### 2.4 HIGH: Consolidation Into New Enemies Doesn't Trigger New Fights

**Rule (10e):** "After an enemy unit has finished its Consolidation move, if previously ineligible units are now eligible to Fight — these units can then be selected to fight." This is a key mechanic: consolidating into a new enemy unit gives that enemy the right to fight back.

**Current State:** After consolidation (`_process_consolidate`, FightPhase.gd:959-1001), the code switches selecting player and re-emits fight selection. However, it does NOT re-check which units have newly become eligible to fight. Units that were NOT in engagement range before consolidation but ARE now would not be added to the normal_sequence or fights_first_sequence. The fight sequences are built once during `_initialize_fight_sequence()` and never rebuilt.

**Impact:** A charging unit that consolidates into a new enemy gives that enemy no chance to fight back this phase. This removes a major tactical risk of aggressive consolidation.

**Recommendation:** After each consolidation, re-scan all units for fight eligibility. Any unit that is now in engagement range but wasn't listed in any fight sequence should be added to the current subphase's sequence as eligible.

---

### 2.5 MEDIUM: Heroic Intervention Not Implemented

**Rule (10e):** Heroic Intervention is a stratagem (2CP) that allows the non-active player to counter-charge with a CHARACTER unit within 6" of an enemy unit that made a charge move. It does NOT grant Fights First.

**Current State:** `FightPhase.gd:1020-1023` has a placeholder that returns `"not implemented"`. The validation (`_validate_heroic_intervention_action`, FightPhase.gd:1612-1640) has basic CHARACTER keyword checking but most rules are marked as TODO.

**Impact:** A core defensive option is missing for the non-active player. In multiplayer, this significantly favors aggressive charge strategies.

**Recommendation:** Implement as a reaction window at the start of the fight phase, before the first unit is selected:
- Eligibility: CHARACTER keyword, within 6" of enemy, not already in engagement range
- Movement: Up to 6" ending within engagement range of an enemy unit
- Does NOT grant Fights First (fights in Remaining Combats)
- Requires stratagem/CP system (not yet implemented)

---

### 2.6 MEDIUM: Fights Last Subphase Not Processed

**Rule (10e):** There are three fight tiers: Fights First, Remaining Combats, and Fights Last. Units with the Fights Last ability or debuff fight after all other units.

**Current State:** The `FightPriority` enum includes `FIGHTS_LAST` (FightPhase.gd:51) and units are categorized into `fights_last_sequence` (FightPhase.gd:44), but the `Subphase` enum only has `FIGHTS_FIRST`, `REMAINING_COMBATS`, and `COMPLETE` (FightPhase.gd:55-59). The `_transition_subphase()` method (FightPhase.gd:1150-1175) goes directly from `REMAINING_COMBATS` to waiting for END_FIGHT without processing the fights_last_sequence.

**Impact:** Units with Fights Last (from abilities or debuffs) would be placed in the `fights_last_sequence` dictionary but never actually activated for fighting.

**Recommendation:** Add a `FIGHTS_LAST` subphase to the enum. Update `_transition_subphase()` to progress from `REMAINING_COMBATS` to `FIGHTS_LAST` before completing.

---

### 2.7 MEDIUM: Fights First + Fights Last Cancellation Not Handled

**Rule (10e):** If a unit has both Fights First and Fights Last (e.g., a charged unit with a Fights Last debuff), the two cancel out and the unit fights in the normal Remaining Combats step.

**Current State:** `_get_fight_priority()` (FightPhase.gd:1026-1041) checks conditions sequentially — `charged_this_turn` is checked before `fights_last`, so a charged unit would always get FIGHTS_FIRST even if it also has a Fights Last debuff.

**Impact:** Units with both effects would incorrectly fight in the wrong tier.

**Recommendation:** Check for both conditions first. If both FIGHTS_FIRST and FIGHTS_LAST conditions are present, return `NORMAL` priority.

---

### 2.8 MEDIUM: Extra Attacks Weapon Ability Not Handled

**Rule (10e):** Some melee weapons have the "Extra Attacks" ability. A model with this weapon makes attacks with it **in addition to** whichever other melee weapon it selects, rather than choosing between them.

**Current State:** The attack assignment dialog allows selecting individual weapons and assigning targets, but there is no indication or enforcement that "Extra Attacks" weapons must be used alongside another weapon. A model with a Power Fist and a "Teeth and Claws (Extra Attacks)" weapon should use BOTH, but the UI presents them as alternatives.

**Impact:** Players may miss using Extra Attacks weapons, or conversely use them as their only weapon (which is also incorrect — Extra Attacks can only be used IN ADDITION to another weapon).

**Recommendation:** During attack assignment, detect weapons with the Extra Attacks keyword. Auto-include them in the assignments whenever the model is fighting, and show them as mandatory additions in the UI.

---

### 2.9 LOW: Counter-Offensive Stratagem Not Implemented

**Rule (10e):** Counter-Offensive (2 CP) allows the non-active player to select one of their eligible units to fight next, out of the normal alternation sequence, after the active player has selected a unit to fight.

**Current State:** No stratagem system exists for the fight phase.

**Impact:** A key tactical option is missing. Combined with the absence of Heroic Intervention, the defender's reactive options are very limited.

**Recommendation:** Implement as a special action available during the Remaining Combats subphase that lets the defender interrupt the normal alternation order.

---

### 2.10 LOW: Aircraft Restrictions Not Checked

**Rule (10e):** Aircraft cannot Pile In or Consolidate, and can only fight against units that can Fly. Unless a model can Fly, ignore Aircraft when determining the closest enemy model during Pile In or Consolidate.

**Current State:** No checks for AIRCRAFT or FLY keywords in any fight phase code. The pile-in and consolidation "closest enemy" calculations consider all enemy models regardless of keywords.

**Impact:** Aircraft could incorrectly pile in/consolidate, and non-FLY models could be directed toward Aircraft as their closest enemy.

**Recommendation:** Add keyword checks to filter out AIRCRAFT when calculating closest enemy for non-FLY models. Prevent AIRCRAFT units from being added to fight sequences (unless they have FLY opponents in engagement range).

---

### 2.11 LOW: Models Already in Base Contact Should Not Be Moved During Pile-In

**Rule (10e):** "Models that are already in base-to-base contact with an enemy model are not moved" during pile-in.

**Current State:** All models in the unit are available for drag-and-drop movement during pile-in, including those already in base contact with enemies. While moving them wouldn't help (they must end closer to the enemy), there is no enforcement preventing it.

**Impact:** Minor — a model in base contact moved even slightly would violate the "must end closer" rule and be reverted. But the rule is technically not enforced proactively.

**Recommendation:** During pile-in setup, identify models already in base contact and lock them from being dragged.

---

## 3. Multiplayer Issues

### 3.1 RESOLVED: NetworkManager Exempt Actions

The fight phase actions have been correctly added to the `exempt_actions` list in `NetworkManager.gd`. This allows cross-turn actions where the non-active player can select fighters during the active player's fight phase.

### 3.2 RESOLVED: GameManager Action Registration

`GameManager.gd` now routes all fight phase actions (`SELECT_FIGHTER`, `PILE_IN`, `ASSIGN_ATTACKS`, `CONFIRM_AND_RESOLVE_ATTACKS`, `ROLL_DICE`, `CONSOLIDATE`, `SKIP_UNIT`, `HEROIC_INTERVENTION`, `END_FIGHT`) to the correct phase.

### 3.3 MEDIUM: Race Condition in Sequential Dialog Actions

**Current State:** In `FightController._on_attacks_confirmed()` (FightController.gd:1357-1392), attack assignments are sent one at a time with `await get_tree().create_timer(0.05).timeout` between them, then CONFIRM and ROLL_DICE are sent with a 0.1s delay.

**Impact:** In multiplayer with network latency, these tiny fixed delays may not be sufficient. If actions arrive out of order, attacks could be confirmed before all assignments are processed, or dice could be rolled before confirmation completes. On a slow connection, 50ms between actions is not enough for a server round-trip.

**Recommendation:** Use proper action sequencing (wait for acknowledgment of each action before sending the next) rather than fixed time delays. Alternatively, batch all assignments + confirmation + roll into a single composite action.

---

### 3.4 MEDIUM: Fight Selection Dialog Not Properly Synced for Remote Player

**Current State:** The `FightSelectionDialog` is opened when the `fight_selection_required` signal fires. On the host, this happens during phase entry. On the client, it relies on `NetworkManager._emit_client_visual_updates()` detecting `trigger_fight_selection` in the action result metadata. However, the **initial** fight selection when the phase enters may be missed because the signal fires during `enter_phase` before the client's controller is connected.

The workaround in `FightController.set_phase()` (lines 345-350) re-triggers the signal after a 0.1s delay, which is fragile.

**Impact:** The client may not see the initial fight selection dialog on phase entry.

**Recommendation:** Store the pending dialog data in the phase state. Have the controller explicitly request it when connecting, rather than relying on signal timing and fixed delays.

---

### 3.5 MEDIUM: Pile-In/Consolidate Validation Feedback Missing

**Current State:** The PileInDialog and ConsolidateDialog both defer validation to FightPhase. Comments in PileInDialog state: "Don't validate here - let FightPhase do it when processing the action." If the FightPhase validation rejects the movement, no feedback is shown in the dialog — the action is silently rejected.

**Impact:** In multiplayer, a player could confirm movements that get rejected server-side, with no error message shown. The player sees the confirm button working but nothing happens.

**Recommendation:** Either validate in the dialog before confirming (client-side preview validation), or propagate validation errors back to the dialog/controller for display.

---

### 3.6 LOW: Pile-In/Consolidate Drag Movement Not Synced Visually

**Current State:** During pile-in and consolidation, the active player drags model tokens around the battlefield. The remote player does not see this movement in real-time — they only see the final positions after the PILE_IN or CONSOLIDATE action is confirmed.

**Impact:** The remote player has no visual feedback of what the opponent is doing during pile-in/consolidation. Models appear to teleport to new positions.

**Recommendation:** Consider sending position update messages during drag (even at reduced frequency) to show the remote player what's happening, or at minimum animate models moving from old to new positions when the final action arrives.

---

## 4. Quality of Life Improvements

### 4.1 Attack Assignment Dialog UX

**Current State:** The `AttackAssignmentDialog` requires manual weapon selection, target selection, and clicking "Add Assignment" for each pair. Issues:
- No "Assign All to Target" shortcut for the common case of all weapons attacking one target
- No visual preview of expected damage or hit probability
- Weapon stats shown in compact format (A:3 S:5 AP:-2 D:2) rather than a readable table
- No ability to remove individual assignments (only add new ones; no clear-last)
- No cap on number of assignments per weapon — the dialog allows assigning a weapon more times than its attacks value would allow

**Recommendation:**
- Add an "All to Target" button that assigns all unassigned weapons to the selected target
- Add a "Clear Last" button to remove the most recent assignment
- Show expected damage prediction as assignments are made
- Format weapon stats in a readable table with column headers
- Enforce maximum assignments per weapon based on attack count

---

### 4.2 Pile-In/Consolidate Movement Feedback

**Current State:** Dialogs show textual status and visual indicators (green/red lines, coherency dots). However:
- The dialog window can overlap the battlefield, obscuring models
- No distance indicator showing how many inches a model has moved
- No "snap to engagement range" or "snap to base contact" helper
- No engagement range rings drawn around nearby enemy models

**Recommendation:**
- Make dialogs dockable/moveable to avoid obscuring the battlefield
- Show distance moved in inches next to each model being dragged
- Draw engagement range circles (1" radius) around nearby enemy models
- Add a "snap to base contact" button that auto-positions a model in base contact with the nearest enemy

---

### 4.3 Fight Sequence Visibility in Multiplayer

**Current State:** The fight sequence is displayed in a small `ItemList` in the right panel. During multiplayer, the non-selecting player may not have clear visibility into whose turn it is.

**Recommendation:**
- Add a prominent banner/overlay showing "Player X is selecting a unit to fight"
- Show the full fight sequence timeline with visual indicators for Fights First / Remaining Combats phases
- Highlight the alternation pattern so players understand the back-and-forth selection

---

### 4.4 Combat Results Display

**Current State:** Dice results are shown in a right-panel combat log using BBCode formatting. Color-coded dice (green/gray) and summary lines are shown. Issues:
- Results can scroll by quickly with multiple attack assignments
- No summary "scoreboard" showing total damage dealt per activation
- No visual dice animation (results appear as text immediately)
- The combat log has a minimum size of 230x100px, which is small

**Recommendation:**
- Add a summary panel after all attacks resolve showing: total attacks → hits → wounds → failed saves → damage → casualties
- Consider a brief dice roll animation for engagement
- Make the combat log resizable or add a "full log" popup
- Show floating damage numbers over damaged/destroyed units on the battlefield

---

### 4.5 No Visual Indication of Engaged Units on the Board

**Current State:** During the fight phase, engagement range circles are drawn around the active fighter's models. But there is no board-level indicator showing which units across the battlefield are currently engaged.

**Recommendation:**
- At the start of the fight phase, draw engagement indicators around all engaged unit pairs
- Use color coding to distinguish Fights First units from normal units
- Show a "crossed swords" icon over engaged unit tokens

---

### 4.6 No Confirmation Before Phase Ends

**Current State:** The END_FIGHT action is always valid and immediately ends the phase (FightPhase.gd:1642-1644). No confirmation dialog is shown.

**Impact:** A player could accidentally end the fight phase before all their units have fought.

**Recommendation:** If there are eligible units that haven't fought yet, show a confirmation dialog: "X units have not yet fought. Are you sure you want to end the Fight Phase?"

---

### 4.7 No "Auto-Fight" for Single-Target Combats

**Current State:** Even when a unit has only one melee weapon and one eligible target, the player must go through the full pile-in → weapon selection → target assignment → confirm → dice roll → consolidate flow. This is 3-4 dialog interactions per unit.

**Recommendation:** When a unit has exactly one melee weapon type and one eligible target, offer an "Auto-Resolve" button that skips pile-in, auto-assigns all attacks to the single target, and prompts only for consolidation.

---

## 5. Visual Improvements

### 5.1 Pile-In/Consolidate Movement Arrows

**Current State:** Direction lines (yellow/green/red) are drawn from model position to closest enemy. These are functional but basic.

**Recommendation:**
- Replace plain lines with directional arrows
- Show the movement path (from original to current drag position) as a dashed line
- Add a distance label showing inches moved
- Use animated dashes or "marching ants" to indicate the valid movement envelope

---

### 5.2 Engagement Range Visualization

**Current State:** Engagement range circles are drawn as simple orange circles with transparent fill (FightController.gd:504-521).

**Recommendation:**
- Use a pulsing animation to draw attention to engaged models
- Show engagement between units with connecting lines or highlighted overlap zones
- Color enemy engagement circles differently from friendly ones
- Add a "combat zone" highlight covering the area where engaged units overlap

---

### 5.3 Fight Phase Header / State Banner

**Current State:** The phase label in the bottom HUD shows "Fight" with a basic phase indicator. Subphase transitions are logged with yellow text in the combat log.

**Recommendation:**
- Add a prominent phase state banner showing: current subphase, whose turn to select, number of units remaining
- Animate subphase transitions with a brief overlay ("FIGHTS FIRST COMPLETE — REMAINING COMBATS")
- Use distinct color schemes for each subphase

---

### 5.4 Unit Tokens During Fight Phase

**Current State:** Model tokens are plain visual representations without fight-phase-specific indicators.

**Recommendation:**
- Add a "has fought" indicator (dimmed opacity, checkmark, or grayed border)
- Show a "charging" indicator on units with Fights First from charging
- During activation, highlight the active unit's models distinctly from all others
- Show a brief "attack" animation or flash when melee attacks resolve

---

### 5.5 Damage Application Visualization

**Current State:** Damage is applied via state diffs that update model `current_wounds` and `alive` flags. Visual updates happen when tokens refresh from state, but there is no animation.

**Recommendation:**
- Show damage numbers floating up from wounded models
- Flash models red when they take wounds
- Show a "destroyed" animation (fade out, collapse) when a model dies
- Display a wound tracker on multi-wound models during combat

---

## 6. Code Quality Observations

### 6.1 Legacy Fight Sequence Maintained Alongside New System

`FightPhase.gd` maintains both the old `fight_sequence` array and index system AND the new `fights_first_sequence`/`normal_sequence`/`fights_last_sequence` dictionary system. The `_build_alternating_sequence()` at line 1177 builds the old array from the new dictionaries. Several methods still reference `current_fight_index` and the legacy array.

This dual tracking creates confusion about which system is authoritative and increases the risk of desynchronization.

### 6.2 Player Owner Value Inconsistency

Throughout the fight phase code, player ownership values are inconsistently typed. Sometimes compared as integers (0, 1, 2), sometimes as strings ("1", "2"). The `_build_alternating_sequence()` (line 1185) checks `owner == 0` but `_initialize_fight_sequence()` converts to string keys via `str(int(owner_val))`. The `_get_defending_player()` returns 1 or 2, while some unit owners are stored as 0 or 1.

### 6.3 Unused `advance_to_next_fighter()` Method

`FightPhase.gd:1694-1752` contains `advance_to_next_fighter()` which duplicates logic from `_switch_selecting_player()` and `_transition_subphase()` but appears to not be called from the main fight flow (which uses `_build_fight_selection_dialog_data()` instead). This dead code could cause confusion.

### 6.4 Excessive Debug Logging

Both `FightPhase.gd` and `FightController.gd` contain extensive `print()` statements (50+ in each file). While the project's CLAUDE.md says not to remove debug logging unless asked, this volume impacts performance and clutters output. Many are stack traces (`print_stack()`) in normal flow paths.

### 6.5 Deferred Signal Emission Anti-Pattern

The fight phase uses a pattern where `_process_*` methods emit signals AND embed trigger metadata in the result dictionary for NetworkManager to re-emit on clients. This dual-signal approach is necessary for multiplayer but creates a risk of duplicate signal handling if both paths fire on the host.

---

## 7. Status of Previously Reported Issues

The earlier audit at `40k/PRPs/fight_phase_audit_report.md` reported several issues. Here is their current status:

| Prior Issue | Prior Severity | Current Status | Notes |
|-------------|---------------|----------------|-------|
| 1.1 Melee weapon abilities not implemented | CRITICAL | **RESOLVED** | `_resolve_melee_assignment()` now implements Lethal Hits, Sustained Hits, Devastating Wounds, Torrent |
| 1.2 Per-model fight eligibility | HIGH | **STILL OPEN** | See §2.1 above |
| 1.3 Pile-in must end in engagement range | HIGH | **STILL OPEN** | See §2.2 above |
| 1.4 Pile-in cannot create new engagements | HIGH | **INCORRECT** | In 10e, pile-in CAN create new engagements. No restriction exists. |
| 1.5 Consolidate cannot create new engagements | HIGH | **INCORRECT** | In 10e, consolidate CAN create new engagements. But newly engaged enemies should get to fight back (see §2.4). |
| 1.6 Variable attack characteristics not rolled | MEDIUM | **RESOLVED** | `roll_variable_characteristic()` now used for attacks |
| 1.7 Variable damage characteristics not rolled | MEDIUM | **RESOLVED** | `roll_variable_characteristic()` now used for damage |
| 1.8 Heroic Intervention | MEDIUM | **STILL OPEN** | See §2.5 above |
| 1.9 Invulnerable saves not checked in melee | MEDIUM | **RESOLVED** | `_calculate_save_needed()` now called with invuln parameter |
| 1.10 Critical hits not tracked in melee | MEDIUM | **RESOLVED** | `critical_hits` count tracked, used for Lethal/Sustained/DW |
| 1.11 Fights Last subphase | LOW | **STILL OPEN** | See §2.6 above |
| 1.12 Fights First + Last cancellation | LOW | **STILL OPEN** | See §2.7 above |
| 1.13 Counter-Offensive stratagem | LOW | **STILL OPEN** | See §2.9 above |
| 2.1 NetworkManager exempt actions | CRITICAL | **RESOLVED** | |
| 2.2 GameManager action registration | CRITICAL | **RESOLVED** | |
| 2.3 Race condition in dialog sequencing | MEDIUM | **STILL OPEN** | See §3.3 above |
| 2.4 Initial dialog sync for client | MEDIUM | **STILL OPEN** | See §3.4 above |
| 2.5 Drag movement not synced visually | LOW | **STILL OPEN** | See §3.6 above |

---

## 8. Summary Table

| # | Issue | Severity | Category | Status |
|---|-------|----------|----------|--------|
| 2.1 | Per-model fight eligibility not checked | HIGH | Rules | Open |
| 2.2 | Pile-in must end with unit in engagement range | HIGH | Rules | Open |
| 2.3 | Base-to-base contact not enforced in pile-in/consolidate | HIGH | Rules | Open |
| 2.4 | Consolidation into new enemies doesn't trigger new fights | HIGH | Rules | Open |
| 2.5 | Heroic Intervention not implemented | MEDIUM | Rules | Stub |
| 2.6 | Fights Last subphase not processed | MEDIUM | Rules | Partial |
| 2.7 | Fights First + Last cancellation not handled | MEDIUM | Rules | Open |
| 2.8 | Extra Attacks weapon ability not handled | MEDIUM | Rules | Open |
| 2.9 | Counter-Offensive stratagem not implemented | LOW | Rules | Open |
| 2.10 | Aircraft restrictions not checked | LOW | Rules | Open |
| 2.11 | Models in base contact should not be moved in pile-in | LOW | Rules | Open |
| 3.1 | NetworkManager exempt actions | - | Multiplayer | **RESOLVED** |
| 3.2 | GameManager action registration | - | Multiplayer | **RESOLVED** |
| 3.3 | Race condition in dialog sequencing | MEDIUM | Multiplayer | Open |
| 3.4 | Initial dialog sync for client | MEDIUM | Multiplayer | Workaround |
| 3.5 | Pile-in/consolidate validation feedback missing | MEDIUM | Multiplayer | Open |
| 3.6 | Drag movement not synced visually | LOW | Multiplayer | Open |
| 4.1 | Attack assignment dialog UX | - | QoL | Suggested |
| 4.2 | Movement feedback improvements | - | QoL | Suggested |
| 4.3 | Fight sequence visibility in multiplayer | - | QoL | Suggested |
| 4.4 | Combat results display | - | QoL | Suggested |
| 4.5 | Engaged units board indicator | - | QoL | Suggested |
| 4.6 | End phase confirmation | - | QoL | Suggested |
| 4.7 | Auto-fight for single-target combats | - | QoL | Suggested |
| 5.1 | Movement arrows/paths | - | Visual | Suggested |
| 5.2 | Engagement range visualization | - | Visual | Suggested |
| 5.3 | Phase state banner | - | Visual | Suggested |
| 5.4 | Unit tokens during fight | - | Visual | Suggested |
| 5.5 | Damage application visualization | - | Visual | Suggested |

---

## 9. Recommended Priority Order

### Phase 1: Core Rules Correctness
1. **2.1** — Per-model fight eligibility (HIGH, high gameplay impact)
2. **2.3** — Base-to-base contact enforcement (HIGH, rules compliance)
3. **2.2** — Pile-in unit engagement range validation (HIGH)
4. **2.4** — Consolidation triggering new fights (HIGH, tactical impact)

### Phase 2: Fight Order Completeness
5. **2.6** — Fights Last subphase
6. **2.7** — Fights First + Last cancellation
7. **2.8** — Extra Attacks weapon ability

### Phase 3: Multiplayer Stability
8. **3.3** — Fix race condition in sequential actions (batch actions)
9. **3.4** — Proper initial dialog sync
10. **3.5** — Validation feedback in dialogs

### Phase 4: Missing Mechanics
11. **2.5** — Heroic Intervention (requires stratagem system)
12. **2.9** — Counter-Offensive stratagem
13. **2.10** — Aircraft restrictions

### Phase 5: QoL & Visual Polish
14. QoL improvements (4.1 — 4.7)
15. Visual improvements (5.1 — 5.5)

---

## Sources

Rules references:
- [Wahapedia Core Rules](https://wahapedia.ru/wh40k10ed/the-rules/core-rules/)
- [Goonhammer Ruleshammer — When Can My Unit Fight?](https://www.goonhammer.com/ruleshammer-when-can-my-unit-fight-how-do-pile-in-and-consolidate-moves-work/)
- [Spikey Bits — 10th Edition Charge & Fight Phases](https://spikeybits.com/10th-edition-40k-core-rules-charge-fight-phases/)
- [Age of Miniatures — Warhammer 40k Rules Explained](https://ageofminiatures.com/warhammer-40k-rules-explained/)
- [Sprues & Brews — 10th Edition Core Rules Deep Dive](https://spruesandbrews.com/2023/06/02/warhammer-40k-10th-edition-core-rules-deep-dive/)
