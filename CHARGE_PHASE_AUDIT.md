# Charge Phase Audit

Audit of the Charge Phase implementation against the design spec in `charge_phase.md` and 10e core rules.

## Implementation Status

### Core Flow
| Item | Status | Notes |
|------|--------|-------|
| Enter Charge Phase / eligible unit highlighting | Done | `_initialize_charge()`, `_can_unit_charge()` |
| Select Unit -> Select Targets (within 12") | Done | `DECLARE_CHARGE` action, `_is_target_within_charge_range()` |
| Roll 2D6 for charge distance | Done | `_process_charge_roll()` with RNG service |
| Charge path preview & validation | Done | Movement constraints validated in `_validate_charge_movement_constraints()` |
| Confirm / Fail with reason | Done | `_process_apply_charge_move()` with structured errors |
| Repeat for other units or End Phase | Done | `COMPLETE_UNIT_CHARGE`, `END_CHARGE` actions |
| Overwatch hook (stub) | Not started | Future hook mentioned in design; no implementation yet |

### Data Contracts (Actions & Results)
| Action | Status | Notes |
|--------|--------|-------|
| `DECLARE_CHARGE` | Done | Validates ownership, 12" range, target validity |
| `CHARGE_ROLL` (resolve) | Done | 2D6 roll, stores distance, now detects insufficient rolls |
| `APPLY_CHARGE_MOVE` | Done | Full path + constraint validation |
| `SELECT_CHARGE_UNIT` | Done | Extra action beyond spec for UI flow |
| `COMPLETE_UNIT_CHARGE` | Done | Extra action beyond spec for UI flow |
| `SKIP_CHARGE` | Done | Allows skipping a unit's charge |
| `END_CHARGE` | Done | Ends the phase |

### Validation Constraints
| Constraint | Status | Notes |
|------------|--------|-------|
| Path distance <= rolled distance | Done | Per-model polyline distance check |
| No model overlaps | Done | Shape-aware overlap check against all models |
| Engagement range with ALL declared targets | Done | Shape-aware ER check (1" horizontal) |
| No ER with non-target enemies | Done | Checks all non-target enemy units |
| Unit coherency at end of move | Done | 2" edge-to-edge check between all models |
| Base-to-base if possible | Stub | Returns valid always (MVP placeholder) |
| Terrain interactions (>2" climb etc.) | Not started | |
| FLY pathing | Not started | |
| Aircraft constraints | Not started | |

### Phase State & Telemetry
| Item | Status | Notes |
|------|--------|-------|
| Track pending charges | Done | `pending_charges` dictionary |
| Track completed charges | Done | `completed_charges` array |
| Track units that attempted charges | Done | `units_that_charged` array |
| Dice log | Done | `dice_log` array with full roll metadata |
| **Record failed charge attempts in phase state** | **Done** | `failed_charge_attempts` array with structured failure data |
| Failed charge summary on phase end | Done | Logs category counts when ending phase |
| "Why failed?" tooltip on UI errors | Not started | UI-side feature for future |

### UI Components
| Item | Status | Notes |
|------|--------|-------|
| Charge Panel (right HUD) | Done | `ChargeController.gd` |
| Eligible targets list with distance preview | Done | |
| Declare / Roll / Skip / Confirm buttons | Done | |
| Auto-Path (greedy heuristic) | Partial | Basic movement, no auto-snap |
| Manual Path (drag models) | Done | Full drag-and-drop with distance tracking |
| Board overlays (ER rings, path tool) | Partial | Movement lines shown, no ER ring overlays |
| PhaseBar with eligible counter | Done | |
| DiceLog entries for charge actions | Done | |

### Multiplayer
| Item | Status | Notes |
|------|--------|-------|
| Dice roll sync via `dice_rolled` signal | Done | |
| Charge resolution sync via `charge_resolved` | Done | |
| Client-side charge success detection | Done | Uses targets from dice_data |

---

## Completed Task: Record Failed Charge Attempts in Phase State

**Branch:** `claude/record-failed-charge-attempts-U2eki`

### What was done

Previously, failed charge attempts were only logged as text messages and shown in the UI. There was no structured record of failures in the phase state for telemetry, replay, or programmatic access.

### Changes made to `40k/phases/ChargePhase.gd`

1. **New state variable:** `failed_charge_attempts: Array` - stores structured records of every failed charge attempt during the phase, cleared on phase enter.

2. **Insufficient distance detection in `_process_charge_roll()`:** The phase now checks feasibility after rolling (via `_is_charge_roll_sufficient()`). If the rolled distance can't reach any declared target, the failure is recorded immediately and the unit is marked as having attempted, without waiting for movement.

3. **Movement validation failure recording in `_process_apply_charge_move()`:** When movement constraints fail, the error is categorized and recorded before emitting the `charge_resolved` signal.

4. **New helper methods:**
   - `_record_failed_charge()` - Creates a structured failure record with unit info, targets, dice, category, and detail.
   - `_categorize_movement_failure()` - Maps error strings to standard categories: `path_distance_exceeded`, `model_overlap`, `non_target_engagement`, `target_engagement_not_reached`, `coherency_broken`, `base_to_base_unmet`, `movement_validation_failed`.
   - `_is_charge_roll_sufficient()` - Pure check: can any alive model reach ER of any target given the rolled distance?

5. **New accessor methods:**
   - `get_failed_charge_attempts()` - Returns the full array of failure records.
   - `get_failed_charge_count()` - Returns the count of failures.
   - `get_failed_charges_by_reason()` - Returns a dictionary of `{category: count}` for telemetry.

6. **Phase end summary:** `_process_end_charge()` now logs a summary of failure counts by category before ending.

### Failure record structure

Each entry in `failed_charge_attempts` contains:
```
{
  "unit_id": String,
  "unit_name": String,
  "target_ids": Array[String],
  "target_names": Array[String],
  "rolled_distance": int,
  "dice_rolls": Array[int],
  "fail_category": String,       # e.g. "insufficient_distance", "coherency_broken"
  "fail_detail": String,         # Human-readable explanation
  "timestamp": float
}
```

### Failure categories
| Category | Trigger |
|----------|---------|
| `insufficient_distance` | 2D6 roll too low to reach any declared target |
| `path_distance_exceeded` | Model path longer than rolled distance |
| `model_overlap` | Final position overlaps another model |
| `target_engagement_not_reached` | Didn't end within ER of all declared targets |
| `non_target_engagement` | Ended within ER of a non-declared-target enemy |
| `coherency_broken` | Unit coherency violated at end of move |
| `base_to_base_unmet` | Could have made base-to-base but didn't (future) |
| `movement_validation_failed` | Catch-all for unrecognized errors |

---

## Suggested Next Task

**"Why failed?" tooltip on UI errors** (from Section 10 of `charge_phase.md`)

This is the natural follow-up to recording failed charge attempts. Now that failures are captured with structured categories and detail strings, the UI can surface them as explanatory tooltips. The work would involve:

1. Reading `get_failed_charge_attempts()` from the ChargePhase when a charge fails
2. Displaying the `fail_detail` string in a tooltip or info panel in the ChargeController UI
3. Optionally showing the `fail_category` as a short tag (e.g., "[DISTANCE]", "[COHERENCY]") alongside the detailed message

Other candidates for next priority:
- **Base-to-base if possible** validation (currently a stub returning always-valid)
- **Overwatch hook** after successful charge move (post-MVP, but important for completeness)
- **Auto-Path improvement** with engagement range snapping
