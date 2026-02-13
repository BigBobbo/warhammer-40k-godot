# Charge Phase Audit — Rules Compliance & Implementation Review

> Audit of `ChargePhase.gd` (934 lines) and `ChargeController.gd` (1,925 lines) against
> Warhammer 40,000 10th Edition core rules, with focus on online multiplayer.

---

## Executive Summary

The charge phase implementation covers the **core mechanical loop** well: unit selection, target declaration within 12", 2D6 charge roll, model-by-model movement with drag-and-drop, and engagement range validation. However, several **rules-required features are missing or incomplete**, and the **multiplayer integration has a significant gap** in client visual synchronization. There are also quality-of-life and visual improvements that would make the phase more usable.

---

## 1. Rules Compliance — What's Implemented Correctly

| Rule | Status | Location |
|------|--------|----------|
| Eligibility: cannot charge if Advanced | ✅ | `ChargePhase.gd:447` — checks `flags.advanced` |
| Eligibility: cannot charge if Fell Back | ✅ | `ChargePhase.gd:450` — checks `flags.fell_back` |
| Eligibility: cannot charge if already in engagement range | ✅ | `ChargePhase.gd:457` — `_is_unit_in_engagement_range()` |
| Eligibility: cannot charge twice per turn | ✅ | `ChargePhase.gd:453` — checks `flags.charged_this_turn` |
| Target must be within 12" (edge-to-edge, shape-aware) | ✅ | `ChargePhase.gd:503-534` — uses `Measurement.model_to_model_distance_inches()` |
| LOS not required for charge declaration | ✅ | No LOS check in `_validate_declare_charge()` |
| Multiple targets may be declared | ✅ | `target_unit_ids` is an Array, multi-select in UI |
| Charge roll is 2D6 | ✅ | `ChargePhase.gd:293` — `rng.roll_d6(2)` |
| Must end within engagement range (1") of ALL declared targets | ✅ | `ChargePhase.gd:614-690` — `_validate_engagement_range_constraints()` |
| Must NOT end within engagement range of non-target enemies | ✅ | `ChargePhase.gd:657-689` — checks all non-target enemy units |
| Unit coherency required at end of charge move | ✅ | `ChargePhase.gd:692-725` — `_validate_unit_coherency_for_charge()` |
| No model overlap validation | ✅ | `ChargePhase.gd:828-887` — `_validate_no_model_overlaps()` |
| Per-model path distance ≤ rolled distance | ✅ | `ChargePhase.gd:585-590` |
| Successful charge grants `charged_this_turn` flag | ✅ | `ChargePhase.gd:386-390` |
| Successful charge grants `fights_first` flag | ✅ | `ChargePhase.gd:391-395` |
| Fight phase reads `charged_this_turn` for fight priority | ✅ | `FightPhase.gd:1026-1041` — `_get_fight_priority()` |

---

## 2. Rules Compliance — What's Missing or Incomplete

### 2.1 CRITICAL: Overwatch (Fire Overwatch Stratagem) — Not Implemented

**Rule:** After a charge is declared (and charge roll made), the defending player may use the Fire Overwatch stratagem (1CP) to shoot at the charging unit with a friendly unit within 24". Hits only on unmodified 6s.

**Current state:** Not implemented at all. No stratagem system exists. No CP tracking. No opportunity for the defending player to react during the charge phase.

**Impact:** This is a significant tactical element. In multiplayer, the defending player has no opportunity to respond to charges, removing an entire layer of counter-play.

**Files affected:** Would need:
- A Stratagem system (new)
- CP tracking in GameState
- An interrupt/reaction window in the charge sequence between roll and move
- NetworkManager support for cross-player actions during charge phase

### 2.2 CRITICAL: Heroic Intervention — Placeholder Only

**Rule:** After all charges are resolved, the non-active player may use the Heroic Intervention stratagem (2CP) to counter-charge with a unit within 6" of a unit that just finished a charge move. Does NOT grant Fights First.

**Current state:** `FightPhase.gd:1020-1023` has a placeholder that returns `"not implemented"`. The action type exists but does nothing.

**Impact:** Another major tactical element missing for the defending player in multiplayer. Heroic Intervention is a key counter to aggressive charges.

### 2.3 HIGH: Failed Charge — Unit Doesn't Move But No Explicit "Do Not Move" Enforcement

**Rule:** If a charge fails (rolled distance insufficient), the unit does **not move at all**. It stays exactly where it was.

**Current state:** When a charge roll fails (in `ChargeController.gd:1601-1609`), the UI resets and the unit selection is cleared. However, there's no explicit state change applied to lock the unit from further charges, and the check is done locally in the controller's `_is_charge_successful()` rather than in the phase itself.

**Issue:** The success/failure determination happens in two places:
1. `ChargeController.gd:768-809` — `_is_charge_successful()` (client-side)
2. `ChargePhase.gd:337-348` — validation in `_process_apply_charge_move()` (server-side)

The phase only checks failure during APPLY_CHARGE_MOVE, not during CHARGE_ROLL itself. If the roll fails, the client-side controller handles it, but the phase doesn't record a failed charge attempt. This means:
- No state change is broadcast to the other player when a charge fails
- The defending player in multiplayer may not see that a charge was attempted and failed

### ~~2.4 HIGH: Base-to-Base Contact Enforcement — Stubbed~~ — FIXED

> **Resolved** — `_validate_base_to_base_possible()` now enforces the 10e rule: if a model ends within engagement range of a target but not in B2B contact, the validator checks whether a B2B position was reachable (within charge distance) and unblocked (no overlaps). If B2B was achievable, the placement is rejected with a `BASE_CONTACT` categorized error.
>
> **Implementation:** `ChargePhase.gd:784+` — For each model within ER but not in B2B, calculates a candidate B2B position along the direction toward the target model. Checks reachability (within rolled distance from start) and overlap-freedom. Uses shape-aware `Measurement` functions for accuracy with non-circular bases.

### 2.5 MEDIUM: Terrain Interaction During Charges — Not Implemented

**Rule:** Charging over terrain >2" high costs vertical distance that counts against the charge roll. Models cannot end mid-climb. FLY keyword allows diagonal measurement.

**Current state:** No terrain interaction code in ChargePhase.gd or ChargeController.gd. The PRD (`charge_phase.md:183-198`) explicitly designs terrain cost functions but they were not implemented.

**Impact:** Players can charge through/over terrain features without distance penalty, which is incorrect.

### 2.6 MEDIUM: AIRCRAFT Restriction — Not Checked

**Rule:** AIRCRAFT units cannot declare charges. Only units with FLY can declare charges against AIRCRAFT targets.

**Current state:** No keyword checks for AIRCRAFT or FLY in `_can_unit_charge()` or `_validate_declare_charge()`. The PRD mentions this at `charge_phase.md:204-206`.

### ~~2.7 LOW: Charge Move Direction Constraint — Not Enforced~~ — FIXED

> **Resolved** — Two-layer enforcement added:
> 1. **Server-side (authoritative):** `ChargePhase.gd:_validate_must_end_closer()` — Validates that each model's final position is closer (edge-to-edge, shape-aware) to at least one declared charge target than its start position. Runs as step 6 in `_validate_charge_movement_constraints()`. Failures produce `MUST_END_CLOSER` categorized errors with descriptive tooltips.
> 2. **Client-side (feedback):** `ChargeController.gd:_validate_charge_position()` — Soft check during drag that rejects placements where the model doesn't end closer to any target, giving immediate red ghost visual feedback.

### 2.8 LOW: Models Must Move Into B2B Before Others Move

**Rule:** When making charge moves, you should move a model into base-to-base contact with an enemy model first, then move remaining models. The order matters.

**Current state:** Players can move models in any order. No enforcement of move ordering.

---

## 3. Multiplayer Issues

### 3.1 ~~CRITICAL: No Charge Phase Signals in `_emit_client_visual_updates()`~~ — FIXED

> **Resolved in commit `63748bc`** — Added charge phase signal re-emission block in `NetworkManager.gd:1046-1117`.

**What was added:**
- `SELECT_CHARGE_UNIT` → re-emits `unit_selected_for_charge`
- `DECLARE_CHARGE` → re-emits `targets_declared`, `charge_targets_available`
- `CHARGE_ROLL` → re-emits `charge_roll_made`, `charge_path_tools_enabled` (plus existing generic `dice_rolled`)
- `APPLY_CHARGE_MOVE` → re-emits `charge_resolved` with success/failure inferred from position diffs

Clients now receive all charge phase visual updates through the standard signal re-emission path, matching the pattern used by movement, shooting, and fight phases.

### 3.2 HIGH: Charge Actions Not in DETERMINISTIC_ACTIONS

**File:** `NetworkManager.gd:42-59`

Only `END_CHARGE` is in `DETERMINISTIC_ACTIONS`. This means `SELECT_CHARGE_UNIT`, `DECLARE_CHARGE`, `SKIP_CHARGE`, and `COMPLETE_UNIT_CHARGE` are all treated as non-deterministic, requiring host round-trips.

While `CHARGE_ROLL` correctly requires host processing (involves dice), the purely deterministic actions like `SELECT_CHARGE_UNIT` and `DECLARE_CHARGE` could be optimistically executed on clients for better responsiveness.

### 3.3 MEDIUM: ChargePhase State Is Local (Not Synced)

The ChargePhase maintains local state that is not part of GameState:
- `active_charges` — Dictionary
- `pending_charges` — Dictionary
- `dice_log` — Array
- `units_that_charged` — Array
- `current_charging_unit` — variable
- `completed_charges` — Array

This state lives only on the host's phase instance. The client's phase instance has **separate, empty** copies. The `_get_charge_targets_from_phase()` function in ChargeController.gd:739-766 explicitly notes this: *"NOTE: This only works on the host where pending_charges is populated. Clients should use targets from dice_data instead."*

**Impact:** If the client needs to determine charge success/failure, it can't use the phase state and must rely on the dice_data workaround.

### 3.4 LOW: No Turn Timer Integration for Charge Phase

The charge phase involves multiple sub-steps (select, declare, roll, move models individually, confirm). The 90-second turn timer may expire mid-charge with no graceful handling.

---

## 4. Quality of Life Improvements

### 4.1 No Auto-Path / Suggested Placement

The PRD (`charge_phase.md:156-162`) designs an auto-path system that suggests valid charge positions. Currently only manual drag-and-drop is available.

**Suggestion:** Implement a "snap to nearest valid engagement" button that auto-places models in engagement range, respecting all constraints. This would significantly speed up gameplay, especially in multiplayer where time pressure exists.

### 4.2 No "Why Failed?" Explanation on Charge Failure

When a charge roll fails (insufficient distance), the UI shows "Failed! Rolled X" — not enough to reach target". But when charge movement validation fails, the specific constraint violation (coherency, non-target ER, etc.) is only logged to console, not shown to the player.

**Suggestion:** Display validation errors in the charge info label or as a popup, so players understand exactly why their placement was rejected.

### 4.3 No Engagement Range Visualization During Movement

During charge model placement, there are no visual indicators showing:
- The 1" engagement range ring around target models
- Whether the currently-dragged model is within engagement range
- Which targets still need engagement range contact

**Suggestion:** Draw engagement range circles (1" radius) around target models during charge movement. Color-code them: red if no charging model is in range yet, green if at least one is.

### 4.4 No Distance-to-Target Indicator During Drag

While dragging a model, the distance tracking shows total movement used vs available, but doesn't show the edge-to-edge distance to the nearest target model.

**Suggestion:** Add a live "Distance to target: X.X"" label that updates during drag, so players know exactly how close they are.

### 4.5 No Charge Range Indicator (12" Circle)

When selecting units for charging, there's no visual indicator of the 12" charge range around the unit.

**Suggestion:** Show a 12" range circle around the selected unit to help players quickly identify which enemies are within charge range.

### 4.6 Target Highlights Use Basic ColorRect

**File:** `ChargeController.gd:700-718` — `_highlight_unit()` uses `ColorRect` (32x32 squares) for target highlights.

**Suggestion:** Use circular highlights that match model base sizes, or pulsing outlines, for a more polished look consistent with the tabletop aesthetic. The movement phase likely has better highlight visuals that could be reused.

### 4.7 Charge Line Visual Is Basic

**File:** `ChargeController.gd:663-673` — Lines drawn between unit centers to selected targets.

**Suggestion:** Use dashed or animated lines with arrowheads pointing toward targets. Add a distance label on the line. This matches common tabletop helper tool aesthetics.

### 4.8 No Dice Roll Animation

The charge roll (2D6) result appears instantly in the dice log. There's no visual dice roll animation.

**Suggestion:** Add a brief dice roll animation (even simple bouncing numbers) before revealing the result. This adds drama and matches the tabletop experience.

### 4.9 Step-by-Step UI Could Be Clearer

The charge info label cycles through instructions, but the multi-step flow (Select Unit → Select Targets → Declare → Roll → Move Models → Confirm) could be made more explicit.

**Suggestion:** Add a progress indicator showing the current step (e.g., "Step 3/6: Roll 2D6 for charge distance"). Disable/grey out UI elements for steps that haven't been reached yet.

### 4.10 No Undo for Individual Model Placement

During charge movement, once a model is placed, there's no way to undo that placement and try again (short of dragging it again).

**Suggestion:** Add an "Undo Last Move" button that reverts the most recently placed model back to its original position, allowing re-placement.

---

## 5. Code Quality Observations

### 5.1 Excessive Debug Logging

Both `ChargePhase.gd` and `ChargeController.gd` contain extensive `print()` debug statements throughout. While the CLAUDE.md says not to remove debugging logs unless asked, this volume of logging (100+ print statements in ChargeController alone) will impact performance and clutter console output.

### 5.2 Duplicate Success/Failure Logic

Charge success is determined in two separate places with slightly different logic:
1. `ChargeController.gd:768-809` — `_is_charge_successful()` using pixel measurements
2. `ChargePhase.gd:337-348` — `_process_apply_charge_move()` using inch measurements

This duplication creates a risk of divergence. The controller's check uses `Measurement.model_to_model_distance_px()` while the phase uses `Measurement.model_to_model_distance_inches()`.

### 5.3 `_process()` Called Every Frame Unnecessarily

`ChargeController.gd:1731-1735` calls `current_phase.get_available_actions()` every frame in `_process()` but doesn't use the result. This is wasted computation.

### 5.4 GameState Direct Mutation in Controller

`ChargeController.gd:1196-1220` — `_update_model_position_in_gamestate()` directly mutates `GameState.state.units[unit_id].models[i].position`. In a multiplayer context, direct state mutations bypass the action→result→diff pipeline and can cause state desynchronization.

---

## 6. Priority Summary

### Must Fix (Rules/Multiplayer Correctness)
1. ~~**Add charge phase signal re-emission in NetworkManager**~~ — **DONE** (commit `63748bc`)
2. **Record failed charge attempts in phase state** — Broadcast failure to both players ← **RECOMMENDED NEXT**
3. ~~**Implement base-to-base enforcement**~~ — **DONE** — Full B2B validation with reachability and overlap checks

### Should Fix (Rules Compliance)
4. **Add Overwatch reaction window** — Major tactical element missing (requires Stratagem system)
5. **Add Heroic Intervention** — Major defensive element missing (requires Stratagem system)
6. **Add terrain interaction for charges** — Distance should account for terrain height
7. **Add AIRCRAFT charge restrictions** — Missing keyword checks
8. ~~**Enforce "must end closer to target" per model**~~ — **DONE** — Server + client enforcement with shape-aware distance

### Should Improve (QoL/Visual)
9. **Add engagement range visualization** during charge movement
10. **Add charge range (12") indicator** when selecting units
11. **Implement auto-path/snap-to-engagement** for faster gameplay
12. **Add "Why failed?" explanations** visible to the player
13. **Improve target highlights** from squares to proper base-sized circles
14. **Add distance-to-target indicator** during model drag
15. **Remove direct GameState mutation** in ChargeController — route through action pipeline

### Nice to Have
16. **Add dice roll animation** for charge rolls
17. **Add step progress indicator** for the charge flow
18. **Add undo for individual model placement**
19. **Add deterministic charge actions** to DETERMINISTIC_ACTIONS for faster client response
20. **Clean up unused `_process()` computation**

---

## Sources

Rules references:
- [Wahapedia Core Rules](https://wahapedia.ru/wh40k10ed/the-rules/core-rules/)
- [Goonhammer Ruleshammer — The Charge Phase](https://www.goonhammer.com/ruleshammer-the-charge-phase/)
- [WTC 10th Edition Charging Guide](https://worldteamchampionship.com/wp-content/uploads/2023/08/WTC-10th-Edition-Charging-Guide.pdf)
- [Official GW Core Rules PDF (Sept 2024)](https://assets.warhammer-community.com/warhammer40000_core&key_corerules_eng_24.09-5xfayxjekm.pdf)
