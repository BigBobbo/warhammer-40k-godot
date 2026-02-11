# Deployment Phase Audit

**Status:** In Progress
**Last Updated:** 2026-02-11

## Overview

Audit of the deployment phase implementation against 10th Edition Warhammer 40,000 core rules. The deployment system handles unit placement, zone validation, formation modes, transport embarkation, and character attachment during the Deployment step.

## Completed Items

### 1. Coherency Warning Display
**Status:** DONE
**Priority:** High (most impactful)
**Files Changed:** `DeploymentController.gd`, `Main.gd`

Per 10th edition core rules, units must maintain unit coherency:
- **2-6 model units:** Every model must be within 2" of at least 1 other model in the unit
- **7+ model units:** Every model must be within 2" of at least 2 other models in the unit

**What was implemented:**
- Upgraded `_check_coherency_warning()` to use proper **edge-to-edge** (shape-aware) distance via `Measurement.model_to_model_distance_inches()` instead of center-to-center distance
- Added `coherency_warning_changed` signal on `DeploymentController` to communicate coherency state to the UI
- Created a non-blocking **yellow warning banner** (`PanelContainer`) displayed at the top of the screen when models are placed out of coherency
- Banner automatically hides when coherency is restored, when the unit is confirmed, or when placement is undone
- Banner is cleaned up on phase transition (deployment controller teardown)
- Correctly applies the 2-model neighbor rule for 7+ model units

**Key code locations:**
- `DeploymentController.gd:841` - `_check_coherency_warning()` with shape-aware distance
- `DeploymentController.gd:8` - `coherency_warning_changed` signal declaration
- `Main.gd:1041` - `_setup_coherency_banner()` UI creation
- `Main.gd:1103` - `_on_coherency_warning_changed()` handler

---

## Remaining Items (Priority Order)

### 2. Deployment Zone Shape Validation (Non-Rectangular Zones)
**Status:** TODO
**Priority:** High
**Effort:** Medium

The current deployment zone system uses `Polygon2D` which supports arbitrary shapes, but the zone definitions in `BoardState` may not cover all 10th edition deployment map layouts (e.g., diagonal splits, dawn of war, hammer and anvil). Verify all Leviathan mission pack deployment maps are supported.

**Key files:** `BoardState.gd`, `DeploymentZoneVisual.gd`

### 3. Deployment Order Enforcement (Alternating Units)
**Status:** TODO
**Priority:** High
**Effort:** Medium

Per core rules, players alternate deploying one unit at a time. The current system handles turn switching via `TurnManager.deployment_side_changed`, but should validate that exactly one unit is deployed per turn before switching to the opponent. Verify edge cases like "deploy all remaining" when one player finishes first.

**Key files:** `DeploymentPhase.gd`, `TurnManager.gd`

### 4. Strategic Reserves / Reinforcements Declaration
**Status:** TODO
**Priority:** Medium
**Effort:** High

Units can be placed in Strategic Reserves instead of deploying on the battlefield. This requires:
- UI for declaring reserves during deployment
- Tracking reserved units in `GameState`
- Bringing them in during later battle rounds (round 2+)

**Key files:** `DeploymentPhase.gd`, `GameState.gd`

### 5. First Turn Determination
**Status:** TODO
**Priority:** Medium
**Effort:** Low

After deployment, the player who finished deploying first chooses who goes first. This should be a dialog/prompt after all units are deployed.

**Key files:** `DeploymentPhase.gd`, `Main.gd`

### 6. Deployment Phase Server-Side Validation (Multiplayer)
**Status:** TODO
**Priority:** Medium
**Effort:** Medium

Currently, deployment validation runs on the client side in `DeploymentPhase.validate_action()`. For multiplayer integrity, the server/host should also validate placement positions, coherency, and zone boundaries before accepting actions.

**Key files:** `DeploymentPhase.gd`, `NetworkIntegration.gd`

### 7. Ghost Preview Coherency Indicator
**Status:** TODO
**Priority:** Low
**Effort:** Low

Enhance the ghost preview system to tint the ghost yellow/orange when placing a model that would break coherency (before clicking to place). Currently the ghost only shows red for invalid positions (out of zone, overlapping). This would give real-time feedback as the player moves the cursor.

**Key files:** `DeploymentController.gd` (`_process`), `GhostVisual.gd`

### 8. Coherency Enforcement on Confirm
**Status:** TODO
**Priority:** Low
**Effort:** Low

Currently coherency violations during deployment produce a non-blocking warning. Consider adding an optional "strict mode" that blocks confirmation when coherency is violated, or at minimum a confirmation dialog ("Unit is out of coherency. Deploy anyway?").

**Key files:** `DeploymentController.gd` (`confirm()`), `Main.gd`

---

## Suggested Next Task

**Item #2: Deployment Order Enforcement** or **Item #7: Ghost Preview Coherency Indicator** are the best next candidates:
- Item #7 builds directly on the coherency work just completed and is low effort
- Item #2 is higher priority for rules correctness
