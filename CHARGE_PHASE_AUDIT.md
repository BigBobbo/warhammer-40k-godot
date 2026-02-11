# Charge Phase Audit — Implementation Tracker

Tracks the implementation status of charge phase features against the design spec in `charge_phase.md` (Sections 10-13).

---

## Telemetry & UX Polish (Section 10)

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | Record fail reasons counts (insufficient distance, non-target ER, coherency fail, base-to-base unmet) | **DONE** | `ChargePhase.failed_charge_attempts` stores structured records with `primary_category`, `categorized_errors[]`, roll data, and timestamps. Categories: `INSUFFICIENT_ROLL`, `DISTANCE`, `ENGAGEMENT`, `NON_TARGET_ER`, `COHERENCY`, `OVERLAP`, `BASE_CONTACT`. |
| 2 | "Why failed?" tooltip on UI errors | **DONE** | `ChargeController` displays a "Failed Charges" panel in the right HUD. Each failure shows color-coded `[CATEGORY]` tags with detail text. Hover tooltips explain the 10e rule behind each category (`FAIL_CATEGORY_TOOLTIPS` in `ChargePhase.gd`). Dice log also shows structured `[CATEGORY]` tags inline. |

## Core Flow (Sections 1-2)

| # | Item | Status | Notes |
|---|------|--------|-------|
| 3 | Declare charge with target selection | **DONE** | Multi-target selection, 12" range validation |
| 4 | Roll 2D6 charge distance | **DONE** | With dice log and multiplayer sync |
| 5 | Charge path preview & manual movement | **DONE** | Drag-to-move with ghost visual, distance tracking |
| 6 | Validate all movement constraints | **DONE** | Distance, engagement range, non-target ER, coherency, overlap |
| 7 | Confirm / fail charge | **DONE** | Applies position changes, grants charged_this_turn + fights_first flags |
| 8 | Multi-unit sequencing (repeat for other units) | **DONE** | Completed charges tracked, UI refreshes for next unit |

## Validation Rules (Section 4.3 / 8)

| # | Item | Status | Notes |
|---|------|--------|-------|
| 9  | All-target engagement range | **DONE** | Must end within 1" of every declared target |
| 10 | No non-target engagement range | **DONE** | Cannot end within 1" of non-declared enemies |
| 11 | Unit coherency post-move | **DONE** | 2" coherency check on all models |
| 12 | Base-to-base if possible | **STUB** | `_validate_base_to_base_possible()` returns valid (stub). Needs full implementation to check if B2B is achievable and enforce it. |
| 13 | Model overlap detection | **DONE** | Shape-aware overlap checks including same-unit models |
| 14 | Path distance <= rolled distance | **DONE** | Per-model polyline distance validation |

## UI Components (Section 3)

| # | Item | Status | Notes |
|---|------|--------|-------|
| 15 | Right HUD charge panel | **DONE** | Unit selector, target list, dice log, action buttons, distance tracking, failed charges |
| 16 | Board overlays (charge lines, highlights) | **DONE** | Lines to targets, color-coded target/eligible highlights |
| 17 | Engagement range rings on board | **TODO** | 1" aura rings around targets during pathing not yet drawn |
| 18 | Auto-path suggestion | **TODO** | Only manual pathing implemented; no auto-path heuristic |
| 19 | PhaseBar eligible counter | **DONE** | Status label shows completed/eligible counts |

## Engine Integration (Section 6)

| # | Item | Status | Notes |
|---|------|--------|-------|
| 20 | Deterministic replay support | **TODO** | RNG seeds logged but no replay mechanism wired |
| 21 | Overwatch hook after successful charge | **TODO** | No hook emitted post-charge for Overwatch stratagem |

## Testing (Section 9)

| # | Item | Status | Notes |
|---|------|--------|-------|
| 22 | Unit tests for eligibility, roll, validation | **ARCHIVED** | Tests exist in `tests_archived_disabled/` but are not running |
| 23 | Integration tests (terrain, FLY, aircraft) | **TODO** | No integration tests for charge-specific scenarios |
| 24 | Golden replay test | **TODO** | Not implemented |

---

## Suggested Next Task

**#12 — Base-to-base if possible enforcement**

This is the most impactful remaining validation gap. The current `_validate_base_to_base_possible()` is a stub that always returns valid. Per 10e core rules, if any charging model *can* make base-to-base contact with an enemy while satisfying all other constraints, it *must* do so. Implementing this requires:

1. For each charging model at its final position, check if it could be repositioned to touch an enemy base while still satisfying distance, coherency, engagement range, and no-overlap constraints.
2. If such a position exists and the model is not in B2B, the validation should fail with a `BASE_CONTACT` category error (already wired into the structured failure system).
3. Consider a "snap to B2B" helper that suggests valid B2B positions during manual movement.

This directly builds on the structured failure reporting just implemented — the `BASE_CONTACT` category, tooltip text, and UI display are already in place and will surface these errors automatically once the validation logic is added.

**Alternative next tasks (by priority):**
- **#17 — Engagement range ring overlays**: Visual aid showing 1" ER circles around targets during charge movement. Improves UX significantly for manual pathing.
- **#18 — Auto-path charge movement**: Implement the greedy geometric heuristic from Section 4.3A to auto-suggest compliant paths. Major UX improvement but complex.
- **#21 — Overwatch hook**: Emit a signal/hook after successful charge for future Overwatch stratagem implementation.
