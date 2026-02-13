# Charge Phase Audit — Rules Compliance & Implementation Review

> **Audit v2** (2026-02-13) of `ChargePhase.gd` (1,013 lines) and `ChargeController.gd` (2,114 lines) against
> Warhammer 40,000 10th Edition core rules, with focus on online multiplayer.
>
> Previous audit: v1 (2026-02-11). Changes since v1 are marked with **[NEW]** or **[UPDATED]**.

---

## Executive Summary

The charge phase implementation covers the **core mechanical loop** well: unit selection, target declaration within 12", 2D6 charge roll, model-by-model movement with drag-and-drop, and engagement range validation. Structured failure reporting with categorised error tooltips has been added since v1, improving the player-facing feedback.

However, several **rules-required features are missing or incomplete**, and the **multiplayer integration still has gaps** — particularly around actions that are not re-emitted to clients (`COMPLETE_UNIT_CHARGE`, `SKIP_CHARGE`) and a `_clear_phase_flags()` call that may interfere with Fight phase integration. There are also quality-of-life and visual improvements that would make the phase more usable.

**Overall rules coverage: ~80% (15 core rules fully implemented, 10 missing/incomplete).**

---

## 1. Rules Compliance — What's Implemented Correctly

| Rule | Status | Location |
|------|--------|----------|
| Eligibility: cannot charge if Advanced | ✅ | `ChargePhase.gd:489` — checks `flags.advanced` |
| Eligibility: cannot charge if Fell Back | ✅ | `ChargePhase.gd:492` — checks `flags.fell_back` |
| Eligibility: cannot charge if already in engagement range | ✅ | `ChargePhase.gd:499` — `_is_unit_in_engagement_range()` |
| Eligibility: cannot charge twice per turn | ✅ | `ChargePhase.gd:495` — checks `flags.charged_this_turn` |
| Eligibility: cannot charge if `cannot_charge` flag set | ✅ | `ChargePhase.gd:486` — checks `flags.cannot_charge` |
| Eligibility: unit must have alive models | ✅ | `ChargePhase.gd:502-508` — iterates models for alive check |
| Target must be within 12" (edge-to-edge, shape-aware) | ✅ | `ChargePhase.gd:545-576` — uses `Measurement.model_to_model_distance_inches()` |
| LOS not required for charge declaration | ✅ | No LOS check in `_validate_declare_charge()` |
| Multiple targets may be declared | ✅ | `target_unit_ids` is an Array, `SELECT_MULTI` in UI |
| Charge roll is 2D6 | ✅ | `ChargePhase.gd:315` — `rng.roll_d6(2)` |
| Must end within engagement range (1") of ALL declared targets | ✅ | `ChargePhase.gd:671-747` — `_validate_engagement_range_constraints()` |
| Must NOT end within engagement range of non-target enemies | ✅ | `ChargePhase.gd:714-746` — checks all non-target enemy units |
| Unit coherency required at end of charge move | ✅ | `ChargePhase.gd:749-782` — `_validate_unit_coherency_for_charge()` (2" edge-to-edge) |
| No model overlap validation | ✅ | `ChargePhase.gd:885-944` — `_validate_no_model_overlaps()` |
| Per-model path distance ≤ rolled distance | ✅ | `ChargePhase.gd:627-635` |
| Successful charge grants `charged_this_turn` flag | ✅ | `ChargePhase.gd:428-432` — via diff |
| Successful charge grants `fights_first` flag | ✅ | `ChargePhase.gd:433-437` — via diff |
| Fight phase reads `charged_this_turn` for fight priority | ✅ | `FightPhase.gd:1026-1041` — `_get_fight_priority()` |
| **[NEW]** Structured failure records with categories | ✅ | `ChargePhase.gd:30-50` — `failed_charge_attempts`, `FAIL_CATEGORY_TOOLTIPS` |
| **[NEW]** Insufficient roll failure recorded in phase | ✅ | `ChargePhase.gd:973-988` — `record_insufficient_roll_failure()` called from controller |
| **[NEW]** Failed charges UI panel with category-coloured tooltips | ✅ | `ChargeController.gd:1586-1691` — `_create_failure_tooltip_entry()` |
| **[NEW]** Wall collision check during drag | ✅ | `ChargeController.gd:2038` — `Measurement.model_overlaps_any_wall()` |
| **[NEW]** Non-circular base rotation during charge drag (Q/E keys) | ✅ | `ChargeController.gd:2043-2073` — `_rotate_dragging_model()` |

---

## 2. Rules Compliance — What's Missing or Incomplete

### 2.1 CRITICAL: Overwatch (Fire Overwatch Stratagem) — Not Implemented

**Rule:** After a charge is declared, the defending player may use the Fire Overwatch stratagem (1CP) to shoot at the charging unit with a friendly unit within 24". Hits only on unmodified 6s. Can only be used once per turn. Cannot target TITANIC units with this stratagem.

**Current state:** Not implemented at all. No stratagem system exists. No CP tracking in actions. No opportunity for the defending player to react during the charge phase.

**Impact:** This is the most significant tactical element missing. In multiplayer, the defending player has no opportunity to respond to charges, removing an entire layer of counter-play.

**Files affected:** Would need:
- A Stratagem system (new)
- CP tracking in GameState (partially exists in `players.{1,2}.cp` but unused for stratagems)
- An interrupt/reaction window in the charge sequence between declaration and roll
- NetworkManager support for cross-player actions during charge phase

### 2.2 CRITICAL: Heroic Intervention — Placeholder Only

**Rule:** After an enemy unit makes a charge move, the non-active player may use the Heroic Intervention stratagem (2CP) to counter-charge with a friendly unit within 6" that is not already in engagement range. Only WALKER vehicles can use this among vehicles. Does NOT grant Fights First.

**Current state:** `FightPhase.gd:1020-1023` has a placeholder that returns `"not implemented"`. The action type exists but does nothing.

**Impact:** Another major tactical element missing for the defending player in multiplayer. Heroic Intervention is a key counter to aggressive charges.

### 2.3 HIGH: "Has Been Charged" Status — Not Tracked **[NEW]**

**Rule:** If a unit was the target of a successful charge during a turn, until the end of that turn, that unit and every model in it is said to "have been charged." This status matters for certain abilities and rules interactions.

**Current state:** No `has_been_charged` flag is set on the target unit(s) when a charge succeeds. Only the charging unit gets `charged_this_turn`. A search for `has_been_charged`, `been_charged`, or `was_charged` returns zero results across the codebase.

**Impact:** Any rules or abilities that trigger on "has been charged" status will not function. This is a data model gap.

### 2.4 HIGH: Base-to-Base Contact Enforcement — Stubbed

**Rule:** If it is possible for a charging model to end its move in base-to-base contact with an enemy model (while satisfying all other constraints), it **must** do so.

**Current state:** `ChargePhase.gd:784-788` — `_validate_base_to_base_possible()` returns `{"valid": true}` always. Comment says "For MVP, we'll implement a simplified check."

**Impact:** Players can legally place models within engagement range but not in base-to-base contact even when B2B is achievable. This is a rules violation.

### 2.5 HIGH: Failed Charge Handling — Split Between Client and Server **[UPDATED]**

**Rule:** If a charge fails (rolled distance insufficient), the unit does **not move at all**. It stays exactly where it was.

**Current state (improved since v1):** The controller now calls `current_phase.record_insufficient_roll_failure()` when a roll is insufficient (`ChargeController.gd:1765-1766`), and the phase records structured failure data in `failed_charge_attempts`. Failed charges are displayed in the UI with category-coloured tooltips.

**Remaining issue:** The success/failure determination still happens in two places with different measurement systems:
1. `ChargeController.gd:790-831` — `_is_charge_successful()` using `Measurement.model_to_model_distance_px()`
2. `ChargePhase.gd:359` — `_validate_charge_movement_constraints()` using `Measurement.model_to_model_distance_inches()`

The controller uses pixel-based measurements while the phase uses inch-based. While these should be equivalent through conversion, the different code paths create a risk of divergence. If they disagree, a client may allow movement for a charge the server will reject (or vice versa).

### 2.6 MEDIUM: Terrain Interaction During Charges — Not Implemented

**Rule:** Charging over terrain >2" high costs vertical distance that counts against the charge roll. Models cannot end mid-climb. FLY keyword allows diagonal measurement.

**Current state:** No terrain interaction code in ChargePhase.gd or ChargeController.gd. The PRD (`charge_phase.md:183-198`) explicitly designs terrain cost functions but they were not implemented.

**Impact:** Players can charge through/over terrain features without distance penalty, which is incorrect.

### 2.7 MEDIUM: AIRCRAFT Restriction — Not Checked

**Rule:** AIRCRAFT units cannot declare charges. Only units with FLY can declare charges against AIRCRAFT targets.

**Current state:** No keyword checks for AIRCRAFT or FLY in `_can_unit_charge()` or `_validate_declare_charge()`. The PRD mentions this at `charge_phase.md:204-206`.

### 2.8 MEDIUM: Barricade Engagement Range (2") — Not Implemented **[NEW]**

**Rule:** When charging a unit on the other side of a Barricade terrain feature, the engagement range is modified to 2" instead of the standard 1", since the thickness of the barricade makes it difficult to get within 1".

**Current state:** No barricade terrain type exists in the codebase. The engagement range is always 1". No search results for "barricade" in any game files.

**Impact:** Charges across barricades would be overly strict (requiring 1" instead of the correct 2").

### 2.9 LOW: Charge Move Direction Constraint — Not Enforced

**Rule:** Each model making a charge move must end that move **closer** to at least one of the charge targets than it started.

**Current state:** `_validate_charge_position()` in `ChargeController.gd:1265-1286` has a comment about being "lenient" for individual model validation. There's no explicit check that each model ends closer to a target. The server-side `_validate_charge_movement_constraints()` also does not enforce this.

### 2.10 LOW: Models Must Move Into B2B Before Others Move

**Rule:** When making charge moves, you should move a model into base-to-base contact with an enemy model first, then move remaining models. The controlling player chooses the order but B2B models should be prioritised.

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

### 3.2 HIGH: `COMPLETE_UNIT_CHARGE` and `SKIP_CHARGE` Not Re-emitted to Client **[NEW]**

**File:** `NetworkManager.gd:1046-1118`

The charge phase signal re-emission block handles `SELECT_CHARGE_UNIT`, `DECLARE_CHARGE`, `CHARGE_ROLL`, and `APPLY_CHARGE_MOVE` — but does NOT handle `COMPLETE_UNIT_CHARGE` or `SKIP_CHARGE`.

When the active player completes or skips a unit's charge:
- The host's ChargePhase adds the unit to `completed_charges` and resets `current_charging_unit`
- The client's ChargePhase does NOT receive these state updates
- The client's UI may not properly transition to the "select next unit" state

**Impact:** The defending player's client may show stale charge state. The host/client state for `completed_charges` and `current_charging_unit` will diverge.

### 3.3 HIGH: Charge Actions Not in DETERMINISTIC_ACTIONS

**File:** `NetworkManager.gd:42-59`

Only `END_CHARGE` is in `DETERMINISTIC_ACTIONS`. This means `SELECT_CHARGE_UNIT`, `DECLARE_CHARGE`, `SKIP_CHARGE`, and `COMPLETE_UNIT_CHARGE` are all treated as non-deterministic, requiring host round-trips.

While `CHARGE_ROLL` correctly requires host processing (involves dice), the purely deterministic actions like `SELECT_CHARGE_UNIT` and `DECLARE_CHARGE` could be optimistically executed on clients for better responsiveness.

### 3.4 MEDIUM: ChargePhase State Is Local (Not Synced)

The ChargePhase maintains local state that is not part of GameState:
- `active_charges` — Dictionary
- `pending_charges` — Dictionary
- `dice_log` — Array
- `units_that_charged` — Array
- `current_charging_unit` — variable
- `completed_charges` — Array
- `failed_charge_attempts` — Array **[NEW]**

This state lives only on the host's phase instance. The client's phase instance has **separate, empty** copies. The `_get_charge_targets_from_phase()` function in `ChargeController.gd:761-788` explicitly notes this: *"NOTE: This only works on the host where pending_charges is populated. Clients should use targets from dice_data instead."*

**Impact:** If the client needs to determine charge success/failure, it can't use the phase state and must rely on the dice_data workaround. The `failed_charge_attempts` array is also host-only, so the defending player's failed charges tooltip panel will always be empty.

### 3.5 MEDIUM: `_clear_phase_flags()` May Interfere with Fight Phase **[NEW]**

**File:** `ChargePhase.gd:67-70, 816-822`

`_on_phase_exit()` calls `_clear_phase_flags()`, which erases `charged_this_turn` and `fights_first` from the **local** `game_state_snapshot`. The Fight phase (which comes immediately after) relies on these flags via `_get_fight_priority()` at `FightPhase.gd:1028`.

**Analysis:** Since `_clear_phase_flags()` only mutates the local snapshot (not the real `GameState`), and the flags were already applied to `GameState` via diffs in `_process_apply_charge_move()`, the Fight phase should get a fresh snapshot with the correct flags. However:
1. This is confusing and fragile — a future refactor could easily break this
2. If any code path reads from the charge phase's snapshot after exit (e.g., during phase transition), it will see the wrong values
3. The intent of the clearing is ambiguous (the comment just says "Clear charge flags")

**Recommendation:** Remove `_clear_phase_flags()` from `_on_phase_exit()`. The `ScoringPhase.gd:93-97` already handles end-of-turn flag cleanup correctly, resetting `charged_this_turn` and `fights_first` at the proper time.

### 3.6 LOW: No Turn Timer Integration for Charge Phase

The charge phase involves multiple sub-steps (select, declare, roll, move models individually, confirm). The 90-second turn timer may expire mid-charge with no graceful handling.

### 3.7 LOW: `APPLY_CHARGE_MOVE` Client Re-emission Loses Failure Detail **[NEW]**

**File:** `NetworkManager.gd:1097-1117`

When re-emitting `charge_resolved` for `APPLY_CHARGE_MOVE`, the code infers success/failure by checking for position diffs. On failure, it emits a generic `{"reason": "Charge movement validation failed"}` instead of the rich `failure_record` with categorised errors that the host emits.

**Impact:** The defending player sees a plain "Charge movement validation failed" message, missing the structured error categories and tooltips that the host player sees.

---

## 4. Quality of Life Improvements

### 4.1 No Auto-Path / Suggested Placement

The PRD (`charge_phase.md:156-162`) designs an auto-path system that suggests valid charge positions. Currently only manual drag-and-drop is available.

**Suggestion:** Implement a "snap to nearest valid engagement" button that auto-places models in engagement range, respecting all constraints. This would significantly speed up gameplay, especially in multiplayer where time pressure exists.

### ~~4.2 No "Why Failed?" Explanation on Charge Failure~~ — PARTIALLY ADDRESSED **[UPDATED]**

Since v1, structured failure reporting has been added:
- `ChargePhase.gd:30-50` defines failure categories (`FAIL_INSUFFICIENT_ROLL`, `FAIL_DISTANCE`, etc.) with human-readable tooltips
- `ChargeController.gd:1586-1691` renders colour-coded failure entries in a "Failed Charges" panel
- Insufficient roll failures are now explicitly recorded via `record_insufficient_roll_failure()`

**Remaining gap:** During the drag-and-drop model placement, real-time validation feedback is still limited to ghost colour (green/red). The specific reason a position is invalid (distance exceeded, overlap, etc.) is only logged to console, not shown in-UI during the drag.

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

**File:** `ChargeController.gd:722-739` — `_highlight_unit()` uses `ColorRect` (32x32 squares) for target highlights.

**Suggestion:** Use circular highlights that match model base sizes, or pulsing outlines, for a more polished look consistent with the tabletop aesthetic. The movement phase likely has better highlight visuals that could be reused.

### 4.7 Charge Line Visual Is Basic

**File:** `ChargeController.gd:686-692` — Lines drawn between unit centers to selected targets.

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

### 4.11 Defending Player Has No Charge Phase Visibility **[NEW]**

When the opponent is charging, the defending player has minimal feedback:
- No indication of which unit was selected for charging
- No indication of which targets were declared
- Charge roll results are visible via `dice_rolled` signal, but failure context is lost (see 3.7)
- No visual feedback during the opponent's model movement (models just teleport to final positions)

**Suggestion:** For the defending player, show:
1. A "Your opponent is charging..." status indicator
2. Highlight the charging unit and declared targets on the board
3. Show the charge roll result prominently
4. Animate model movements rather than teleporting them

### 4.12 Confirm Button Sends Two Actions Sequentially Without Waiting **[NEW]**

**File:** `ChargeController.gd:1288-1335`

`_on_confirm_charge_moves()` emits `APPLY_CHARGE_MOVE` and then immediately emits `COMPLETE_UNIT_CHARGE` without waiting for the first action's result. If `APPLY_CHARGE_MOVE` fails validation server-side, `COMPLETE_UNIT_CHARGE` will still be sent, potentially corrupting the charge sequence state.

**Suggestion:** Wait for the `charge_resolved` signal from the phase before sending `COMPLETE_UNIT_CHARGE`, or have the server handle completion automatically on successful charge move.

---

## 5. Code Quality Observations

### 5.1 Excessive Debug Logging

Both `ChargePhase.gd` and `ChargeController.gd` contain extensive `print()` debug statements throughout. While the CLAUDE.md says not to remove debugging logs unless asked, this volume of logging (100+ print statements in ChargeController alone) will impact performance and clutter console output.

### 5.2 Duplicate Success/Failure Logic

Charge success is determined in two separate places with slightly different logic:
1. `ChargeController.gd:790-831` — `_is_charge_successful()` using pixel measurements
2. `ChargePhase.gd:359` — `_validate_charge_movement_constraints()` using inch measurements

This duplication creates a risk of divergence. The controller's check uses `Measurement.model_to_model_distance_px()` while the phase uses `Measurement.model_to_model_distance_inches()`.

### 5.3 `_process()` Called Every Frame Unnecessarily

`ChargeController.gd:1921-1925` calls `current_phase.get_available_actions()` every frame in `_process()` but doesn't use the result. This is wasted computation.

### 5.4 GameState Direct Mutation in Controller

`ChargeController.gd:1239-1263` — `_update_model_position_in_gamestate()` directly mutates `GameState.state.units[unit_id].models[i].position` and `.rotation`. In a multiplayer context, direct state mutations bypass the action→result→diff pipeline and can cause state desynchronization.

This is especially concerning because the mutation happens during drag-and-drop, before the server validates the move. If the server rejects the charge, the client's GameState will have stale position data that was never reverted.

### 5.5 `_clear_phase_flags()` Mutates Snapshot Unnecessarily **[NEW]**

`ChargePhase.gd:816-822` — `_clear_phase_flags()` erases `charged_this_turn` and `fights_first` from the local `game_state_snapshot` on phase exit. Since these flags were applied to the real GameState via diffs, this clearing has no practical effect but creates confusion. The ScoringPhase already handles proper end-of-turn cleanup. This function should be removed or the code should be clearly documented as snapshot-only cleanup.

### 5.6 Duplicate Charge Roll Processing Logic **[NEW]**

`ChargeController.gd` has two nearly identical charge roll handlers:
1. `_on_charge_roll_made()` (lines 1720-1773) — Primary handler on host
2. `_on_dice_rolled()` (lines 1775-1850) — Fallback handler for client via `dice_rolled` signal

Both contain the same success/failure logic, UI updates, and failure recording. The deduplication check at line 1796 (using `last_processed_charge_roll`) works but is fragile. A single handler with a clear entry point would be cleaner.

---

## 6. Priority Summary

### Must Fix (Rules/Multiplayer Correctness)
1. ~~**Add charge phase signal re-emission in NetworkManager**~~ — **DONE** (commit `63748bc`)
2. **[NEW] Add `COMPLETE_UNIT_CHARGE` / `SKIP_CHARGE` signal re-emission** — Client state diverges without this
3. **[NEW] Track "has been charged" flag on target units** — Required by rules for ability interactions
4. **Implement base-to-base enforcement** — Currently stubbed, rules require it
5. **[NEW] Fix confirm button firing two actions without waiting** — Can corrupt charge sequence state

### Should Fix (Rules Compliance)
6. **Add Overwatch reaction window** — Major tactical element missing (requires Stratagem system)
7. **Add Heroic Intervention** — Major defensive element missing (requires Stratagem system)
8. **Add terrain interaction for charges** — Distance should account for terrain height
9. **Add AIRCRAFT charge restrictions** — Missing keyword checks
10. **Enforce "must end closer to target" per model** — Currently not validated
11. **[NEW] Add barricade engagement range (2") support** — Missing terrain type

### Should Improve (Multiplayer/QoL/Visual)
12. **[NEW] Add defending player charge phase visibility** — Opponent currently sees almost nothing
13. **Add engagement range visualization** during charge movement
14. **Add charge range (12") indicator** when selecting units
15. **Implement auto-path/snap-to-engagement** for faster gameplay
16. **Improve real-time drag validation feedback** — Show specific reasons in-UI, not just red/green ghost
17. **Improve target highlights** from squares to proper base-sized circles
18. **Add distance-to-target indicator** during model drag
19. **Remove direct GameState mutation** in ChargeController — route through action pipeline
20. **[NEW] Fix client `charge_resolved` re-emission to include failure detail** — Currently loses structured error data

### Nice to Have
21. **Add dice roll animation** for charge rolls
22. **Add step progress indicator** for the charge flow
23. **Add undo for individual model placement**
24. **Add deterministic charge actions** to DETERMINISTIC_ACTIONS for faster client response
25. **Clean up unused `_process()` computation**
26. **[NEW] Remove `_clear_phase_flags()` from `_on_phase_exit()`** — ScoringPhase handles cleanup correctly
27. **[NEW] Consolidate duplicate charge roll handlers** — `_on_charge_roll_made` and `_on_dice_rolled`

---

## Appendix A: File Inventory

| File | Lines | Purpose |
|------|-------|---------|
| `40k/phases/ChargePhase.gd` | 1,013 | Server-side phase logic: validation, processing, rules enforcement |
| `40k/scripts/ChargeController.gd` | 2,114 | Client-side UI controller: drag-and-drop, targeting, visual feedback |
| `40k/autoloads/NetworkManager.gd` | 1,522 | Multiplayer networking (charge signals: lines 1046-1118) |
| `40k/autoloads/GameState.gd` | 495 | Game state (unit flags: `charged_this_turn`, `fights_first`) |
| `40k/phases/FightPhase.gd` | ~1,700 | Fight phase (reads charge flags, heroic intervention placeholder) |
| `40k/phases/ScoringPhase.gd` | ~120 | End-of-turn flag cleanup (lines 93-97) |
| `charge_phase.md` | 333 | Design specification / PRD |

---

## Sources

Rules references:
- [Wahapedia Core Rules](https://wahapedia.ru/wh40k10ed/the-rules/core-rules/)
- [Goonhammer Ruleshammer — The Charge Phase](https://www.goonhammer.com/ruleshammer-the-charge-phase/)
- [WTC 10th Edition Charging Guide](https://worldteamchampionship.com/wp-content/uploads/2023/08/WTC-10th-Edition-Charging-Guide.pdf)
- [Official GW Core Rules PDF (Sept 2024)](https://assets.warhammer-community.com/warhammer40000_core&key_corerules_eng_24.09-5xfayxjekm.pdf)
