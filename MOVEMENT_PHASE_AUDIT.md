# Movement Phase Audit

## Completed Refactors

### 1. Consolidate disembark paths (DONE)

**Problem:** Two separate code paths called `TransportManager.disembark_unit()` directly,
bypassing the `CONFIRM_DISEMBARK` action handler that already existed in
`MovementPhase.process_action()`. This meant validation, state-snapshot refresh,
and post-disembark movement initialization were duplicated/inconsistent.

**Bypass sites removed:**

| Location | Line (approx) | What it did |
|---|---|---|
| `MovementPhase._on_disembark_placement_completed()` | ~1878 | Called `TransportManager.disembark_unit()` directly, then manually checked movement flags |
| `MovementController._on_disembark_completed()` | ~1694 | Called `TransportManager.disembark_unit()` directly, then refreshed visuals inline |

**Changes made:**

1. **MovementPhase._on_disembark_placement_completed()** now creates a
   `CONFIRM_DISEMBARK` action and calls `process_action()`, routing through
   validation (`_validate_confirm_disembark`) and the single authoritative
   handler (`_process_confirm_disembark`).

2. **MovementController._on_disembark_completed()** now emits the
   `move_action_requested` signal with a `CONFIRM_DISEMBARK` action, which
   Main.gd routes through `NetworkIntegration.route_action()` like every other
   movement action.

3. **MovementPhase._process_confirm_disembark()** was promoted to the single
   authoritative disembark path. It now:
   - Validates positions via `_validate_confirm_disembark()`
   - Calls `TransportManager.disembark_unit()` (sole call site in production code)
   - Refreshes `game_state_snapshot`
   - Checks post-disembark movement eligibility and defers
     `_initialize_movement_for_disembarked_unit()` when the transport hadn't moved

4. **MovementPhase._on_transport_manager_disembark_completed()** reduced to a
   no-op safety net. All logic now lives in `_process_confirm_disembark()`.

5. **MovementPhase._offer_movement_after_disembark()** removed as dead code
   (was only called from the old bypass in `_on_disembark_placement_completed`).

6. **Main.gd._on_movement_action_requested()** gained a `CONFIRM_DISEMBARK`
   branch that calls `_recreate_unit_visuals()` on success.

**Files changed:**
- `40k/phases/MovementPhase.gd`
- `40k/scripts/MovementController.gd`
- `40k/scripts/Main.gd`

---

## Open Items (prioritised)

### 2. Extract shared `_create_move_state()` helper (HIGH)

**Problem:** Five near-identical `active_moves[unit_id] = { ... }` dictionary
literals appear across the file, each with 12+ keys.

**Locations:**
- `_process_begin_normal_move()` (~line 467)
- `_process_begin_advance()` (~line 512)
- `_process_begin_fall_back()` (~line 558)
- `_process_remain_stationary()` (~line 899)
- `_initialize_movement_for_disembarked_unit()` (~line 1897)

**Risk:** When a new field is added to the move-state dict (e.g. a new tracking
flag), only some locations get updated, leading to subtle desyncs.

**Suggested fix:** Extract a `_create_move_state(mode: String, move_cap: float, opts: Dictionary = {}) -> Dictionary`
helper and call it from all five sites.

---

### 3. Consolidate engagement-range checkers (MEDIUM)

**Problem:** Four separate functions check engagement range with slightly
different logic (some shape-aware, some simple distance).

| Function | Line (approx) |
|---|---|
| `_is_position_in_engagement_range()` | ~1082 |
| `_check_engagement_range_at_position()` | ~1109 |
| `_model_in_engagement_range()` | ~1793 |
| `_position_in_engagement_range()` | ~1814 |

**Risk:** Logic divergence between callers; some use shape-aware measurement
while others use centre-to-centre distance.

**Suggested fix:** Consolidate into one or two functions (one for a full model
dict, one for a bare position) that always use shape-aware
`Measurement.model_to_model_distance_inches`.

---

### 4. Remove dead `validate_action_with_transport_check()` (LOW)

**Problem:** `validate_action_with_transport_check()` (~line 1706) duplicates
routing logic from `validate_action()` (~line 82) but is never called.

**Suggested fix:** Delete the function.

---

### 5. Remove dead group-movement stubs (LOW)

**Problem:** `_process_group_movement()`, `_validate_group_movement()`,
`_validate_individual_move_internal()`, `_check_group_unit_coherency()`,
`_check_terrain_collision()` (~lines 1416-1576) are unused stubs.
`_check_terrain_collision()` always returns `false`.

**Suggested fix:** Delete or move to a feature branch until group movement is
actually implemented.

---

## Recommended Next Task

**Extract shared `_create_move_state()` helper** (item 2 above).

This is the highest-impact refactor remaining in MovementPhase. It touches five
code paths that are already known to drift out of sync, and the fix is
straightforward: one new helper function plus five call-site updates. It also
naturally sets up the disembarked-unit initialization path to reuse
`_process_begin_normal_move()` logic, further reducing duplication.
