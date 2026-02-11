# Charge Phase Audit — 10e Core Rules Compliance

**Last Updated:** 2026-02-11
**Spec Reference:** [charge_phase.md](charge_phase.md) and [Wahapedia 10e Core Rules](https://wahapedia.ru/wh40k10ed/the-rules/core-rules/)

---

## Validation Tasks

### 1. Base-to-base if possible enforcement
**Status:** ✅ COMPLETE
**Files Changed:**
- `40k/phases/ChargePhase.gd` — `_validate_base_to_base_possible()` (line 727)
- `40k/autoloads/RulesEngine.gd` — `_validate_base_to_base_possible_rules()` (line 2813)

**Rule:** If a charging model CAN make base-to-base contact with an enemy model while satisfying all other constraints, it MUST.

**Implementation Details:**
- Checks if any charging model already has B2B (edge-to-edge distance ≤ 0.1") — passes immediately if so
- When no model has B2B, tests each charging model × each target model to see if B2B was achievable
- "Achievable" means the B2B position satisfies ALL of:
  1. Path distance from start ≤ rolled charge distance
  2. Unit coherency preserved (within 2" of at least one other model)
  3. No engagement range violation with non-target enemies
  4. No model base overlap
  5. Unit still has ER with every declared target
- Uses shape-aware distance calculations (circular, rectangular, oval bases)
- Wired into the existing `BASE_CONTACT` failure category, tooltip text, and UI display

---

### 2. Terrain movement cost integration
**Status:** ❌ NOT IMPLEMENTED
**Files Affected:** `40k/phases/ChargePhase.gd`, `40k/autoloads/Measurement.gd`

**Rule (§5.2):** Terrain ≤ 2" high costs no extra distance. Terrain > 2" requires vertical climb/descent distance to count against total charge inches. Models may not end mid-climb.

**Current State:** Path validation uses only `Measurement.distance_polyline_inches()` which calculates horizontal distance only. No elevation data model exists for terrain features. The spec explicitly defers this as "MVP treats vertical=0; data model supports elevations for future."

**What's Needed:**
- Terrain height data in the board state
- `cost(path)` function that adds vertical climb/descent for terrain > 2"
- Mid-climb end position validation
- Integration with path distance validation in `_validate_charge_movement_constraints()`

---

### 3. Vertical engagement range (5" vertical)
**Status:** ❌ NOT IMPLEMENTED (deferred by design)
**Files Affected:** `40k/phases/ChargePhase.gd`, `40k/autoloads/RulesEngine.gd`

**Rule (§5.3):** Engagement Range = within 1" horizontal AND 5" vertical.

**Current State:** Only 1" horizontal ER is checked. The spec notes: "We treat 2D MVP as ≤ 1" in plane (vertical=0), with hooks for vertical maps." No model elevation tracking exists.

**What's Needed:**
- Model elevation/height data
- Split ER check into horizontal (1") + vertical (5") components
- Update `Measurement.is_in_engagement_range_shape_aware()` to accept elevation

---

### 4. AIRCRAFT target validation (FLY requirement)
**Status:** ⚠️ PARTIAL
**Files Affected:** `40k/phases/ChargePhase.gd`, `40k/autoloads/RulesEngine.gd`

**Rule (§5.4):** AIRCRAFT units cannot charge (✅ implemented in RulesEngine.gd:2493). AIRCRAFT units can only be charged by units with the FLY keyword (❌ not implemented).

**Current State:** The charger-side AIRCRAFT block works. But target-side validation does not check if the target is AIRCRAFT and whether the charger has FLY.

**What's Needed:**
- In target eligibility (`_get_eligible_targets_for_unit`), filter out AIRCRAFT targets unless charger has FLY keyword
- FLY movement cost calculation (through-the-air distance vs ground path)

---

### 5. Non-target ER avoidance during path (not just end state)
**Status:** ⚠️ PARTIAL
**Files Affected:** `40k/phases/ChargePhase.gd`

**Rule:** A charging unit must never move within Engagement Range of a unit that was not a declared target — not just at the end position, but during the entire path.

**Current State:** `_validate_engagement_range_constraints()` only checks final positions, not intermediate path waypoints.

**What's Needed:**
- Sample intermediate positions along each model's path
- Check ER against non-targets at each waypoint
- This matters most for manual pathing where players draw curved paths

---

### 6. Multi-unit sequential charging (GitHub Issue #35)
**Status:** ❌ BUG — OPEN
**Files Affected:** `40k/phases/ChargePhase.gd`, `40k/scripts/ChargeController.gd`

**Rule:** Multiple eligible units can charge in sequence during a single Charge Phase.

**Current State:** After the first unit completes its charge, the UI only shows "End Charge Phase" — no option to select another unit.

---

### 7. Model position persistence after charge (GitHub Issue #33)
**Status:** ❌ BUG — OPEN
**Files Affected:** `40k/phases/ChargePhase.gd`

**Rule:** After a successful charge, model positions must be updated in the game state.

**Current State:** Models display at correct positions during the charge but positions are not persisted to `game_state_snapshot`. Multi-model units revert to pre-charge positions.

---

### 8. Defender charge feedback (GitHub Issue — defender sync)
**Status:** ❌ BUG — OPEN
**Files Affected:** `40k/scripts/ChargeController.gd`

**Issue:** Defending player always sees "charge failed" feedback even when the charge succeeds, because `ChargeController` uses local UI state (`selected_targets`) which is only populated on the active player's side.

---

### 9. Charge roll action type mismatch
**Status:** ❌ BUG — OPEN
**Files Affected:** GameManager / ChargePhase action routing

**Issue:** "Unknown action type: CHARGE_ROLL" — validation passes but GameManager rejects the action due to type naming mismatch.

---

### 10. Overwatch hook (post-MVP)
**Status:** 🔲 DEFERRED
**Files Affected:** `40k/phases/ChargePhase.gd`

**Rule:** After a successful charge move, there should be a window for the Overwatch stratagem.

**Current State:** Design doc (§1, §11) explicitly defers this. A hook point should exist after `APPLY_CHARGE_MOVE` succeeds.

---

## Implementation Priority (Suggested Order)

| Priority | Task | Effort | Impact |
|----------|------|--------|--------|
| 1 | **Model position persistence** (#33) | Medium | Critical — charges are visually correct but don't persist |
| 2 | **Multi-unit sequential charging** (#35) | Medium | High — blocks normal gameplay flow |
| 3 | **Charge roll action type mismatch** | Low | High — blocks charge roll resolution |
| 4 | **AIRCRAFT target + FLY validation** | Low | Medium — incorrect targeting allowed |
| 5 | **Non-target ER path-wide check** | Medium | Medium — only end-state checked today |
| 6 | **Defender feedback sync** | Low | Medium — multiplayer UX issue |
| 7 | **Terrain movement costs** | High | Low (deferred by spec, needs elevation model) |
| 8 | **Vertical ER** | High | Low (deferred by spec, needs elevation model) |
| 9 | **Overwatch hook** | Low | Low (post-MVP) |

---

## Completed Items

- ✅ Charge declaration & 12" range validation
- ✅ Charge roll (2D6) mechanics
- ✅ Engagement range validation (all targets, no non-targets) — end-state
- ✅ Unit coherency at end of charge move
- ✅ Model overlap detection
- ✅ Path distance ≤ rolled distance validation
- ✅ Fights First flag on successful charge
- ✅ AIRCRAFT charger blocking
- ✅ **Base-to-base if possible enforcement** (2026-02-11)
