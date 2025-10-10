# PRP: Transport Deployment Embarkation Network Synchronization

**GitHub Issue**: #107 (TBD - to be created)
**Feature**: Fix multiplayer synchronization for units embarked during deployment
**Priority**: High (Blocks multiplayer deployment phase completion)
**Complexity**: Medium
**Estimated Time**: 3-5 hours
**Confidence Score**: 9/10

---

## 🎯 PROBLEM STATEMENT

### User-Reported Issue

When a transport is deployed during the deployment phase, the player can select units to deploy within it (embark). These units then count as being deployed. **This works correctly for the player that owns the transport, but this state is NOT syncing with the other player.**

For example:
- Client player deploys a transport and embarks 3 units inside it
- The client's game correctly marks those 3 units as deployed and embarked
- The host still thinks those 3 units are UNDEPLOYED
- This blocks the end of the deployment phase since the host thinks units remain undeployed

### Root Cause Analysis

The issue occurs in `DeploymentController._process_embarkation()` (lines 386-403):

```gdscript
func _process_embarkation(transport_id: String, unit_ids: Array) -> void:
    for unit_id in unit_ids:
        # Use TransportManager to handle the embarkation
        TransportManager.embark_unit(unit_id, transport_id)  # ❌ Direct GameState modification

        # Mark embarked units as deployed via PhaseManager
        if has_node("/root/PhaseManager"):
            var phase_manager = get_node("/root/PhaseManager")
            if phase_manager.current_phase_instance:
                phase_manager.apply_state_changes([{  # ❌ Local-only change
                    "op": "set",
                    "path": "units.%s.status" % unit_id,
                    "value": GameStateData.UnitStatus.DEPLOYED
                }])
```

**The Problem:**
1. `TransportManager.embark_unit()` directly modifies `GameState.state` (line 95-96 in TransportManager.gd)
2. `PhaseManager.apply_state_changes()` applies changes locally but doesn't go through network sync
3. Neither operation goes through `NetworkIntegration.route_action()` which handles multiplayer synchronization
4. Result: Changes only apply on the player's local game, not synchronized to opponent

---

## 🔍 CODEBASE ANALYSIS

### Current Flow (BROKEN in Multiplayer)

```
Player deploys transport
    ↓
DeploymentController.confirm() [line 290]
    ↓
Shows TransportEmbarkDialog
    ↓
User selects units to embark
    ↓
_on_embark_units_selected() [line 319]
    ↓
_complete_deployment() [line 333]
    ↓
NetworkIntegration.route_action(DEPLOY_UNIT) ✅ SYNCED
    ↓
[After deployment succeeds]
    ↓
_process_embarkation() [line 386]
    ↓
TransportManager.embark_unit() ❌ NOT SYNCED (direct GameState modification)
PhaseManager.apply_state_changes() ❌ NOT SYNCED (local only)
```

### How Deployment Phase Checks Work

In `DeploymentPhase._all_units_deployed()` (lines 322-350):

```gdscript
func _all_units_deployed() -> bool:
    var units = GameState.state.get("units", {})

    for unit_id in units:
        var unit = units[unit_id]
        # Skip embarked units (they're deployed when inside a transport)
        if unit.get("embarked_in", null) != null:  # ⚠️ Checks embarked_in
            continue

        var status = unit.get("status", 0)
        if status == GameStateData.UnitStatus.UNDEPLOYED:  # ⚠️ Checks status
            return false  # Still have undeployed units

    return true
```

**The Check Requires TWO Things:**
1. Unit must have `embarked_in` set to the transport ID, OR
2. Unit must have `status` set to `DEPLOYED`

**The Bug:** On the host, neither of these is set for units embarked by the client!

### Existing Network Sync Patterns

Looking at how other actions sync in multiplayer (`MovementPhase.gd:1718-1878`):

```gdscript
// Example: DISEMBARK_UNIT action
func _process_disembark_unit(action: Dictionary) -> Dictionary:
    var unit_id = action.unit_id
    var transport_id = action.transport_id

    // Create state changes
    var changes = []
    changes.append({
        "op": "set",
        "path": "units.%s.embarked_in" % unit_id,
        "value": null
    })
    // ... more changes ...

    // These changes go through GameManager and get synced!
    return create_result(true, changes)
```

**Key Insight:** Actions return state changes that GameManager broadcasts to all players.

---

## 🎬 IMPLEMENTATION PLAN

### Solution: Create EMBARK_UNITS_DEPLOYMENT Action

Instead of directly calling `TransportManager.embark_unit()` and `PhaseManager.apply_state_changes()`, we need to:
1. Create a new action type `"EMBARK_UNITS_DEPLOYMENT"`
2. Send it through `NetworkIntegration.route_action()` for synchronization
3. Process it in `DeploymentPhase` to apply changes to all players

### Architecture

```
Player selects units to embark
    ↓
_on_embark_units_selected() stores pending units
    ↓
_complete_deployment() sends DEPLOY_UNIT action ✅
    ↓
[DEPLOY_UNIT completes successfully]
    ↓
Send EMBARK_UNITS_DEPLOYMENT action ✅ NEW!
    ↓
NetworkIntegration.route_action() ✅ SYNCED
    ↓
DeploymentPhase.validate_action() validates embarkation
    ↓
DeploymentPhase.process_action() creates state changes:
    - Set embarked_in for each unit
    - Set status to DEPLOYED for each unit
    - Add units to transport's embarked_units array
    ↓
GameManager broadcasts changes to all players ✅
```

---

## 📝 IMPLEMENTATION STEPS

### Step 1: Update DeploymentController._complete_deployment()

**File:** `40k/scripts/DeploymentController.gd`
**Location:** Lines 333-384

**Change:** Don't call `_process_embarkation()` directly. Instead, send an action after deployment succeeds.

```gdscript
func _complete_deployment() -> void:
    # Create deployment action for PhaseManager
    var model_positions = []
    for pos in temp_positions:
        model_positions.append(pos)

    var deployment_action = {
        "type": "DEPLOY_UNIT",
        "unit_id": unit_id,
        "model_positions": model_positions,
        "model_rotations": temp_rotations,
        "phase": GameStateData.Phase.DEPLOYMENT,
        "player": GameState.get_active_player(),
        "timestamp": Time.get_unix_time_from_system()
    }

    # Route through NetworkIntegration (handles multiplayer and single-player)
    var result = NetworkIntegration.route_action(deployment_action)

    if result.success:
        print("[DeploymentController] Deployment successful for unit: ", unit_id)

        # 🆕 NEW: If units need to embark, send embarkation action
        if pending_embark_units.size() > 0:
            DebugLogger.info("Sending embarkation action for transport", {
                "transport_id": unit_id,
                "units_to_embark": pending_embark_units
            })
            _send_embarkation_action(unit_id, pending_embark_units)
            pending_embark_units = []
    else:
        print("[DeploymentController] ERROR - Deployment failed for unit: ", unit_id)
        print("[DeploymentController] Errors: ", result.get("errors", []))
        push_error("Deployment failed: " + str(result.get("error", "Unknown error")))

    _finalize_tokens()
    _clear_previews()
    _remove_ghost()

    unit_id = ""
    model_idx = -1
    temp_positions.clear()
    temp_rotations.clear()

    emit_signal("unit_confirmed")

    if GameState.all_units_deployed():
        emit_signal("deployment_complete")

# 🆕 NEW FUNCTION
func _send_embarkation_action(transport_id: String, unit_ids: Array) -> void:
    """Send embarkation action through network sync"""
    var embark_action = {
        "type": "EMBARK_UNITS_DEPLOYMENT",
        "transport_id": transport_id,
        "unit_ids": unit_ids,
        "phase": GameStateData.Phase.DEPLOYMENT,
        "player": GameState.get_active_player(),
        "timestamp": Time.get_unix_time_from_system()
    }

    var result = NetworkIntegration.route_action(embark_action)

    if not result.success:
        push_error("Embarkation action failed: " + str(result.get("error", "Unknown")))
```

**Remove:** Delete the `_process_embarkation()` function (lines 386-403) - no longer needed.

---

### Step 2: Add Validation to DeploymentPhase

**File:** `40k/phases/DeploymentPhase.gd`
**Location:** Add to `validate_action()` match statement (around line 60)

```gdscript
func validate_action(action: Dictionary) -> Dictionary:
    var action_type = action.get("type", "")

    match action_type:
        "DEPLOY_UNIT":
            return _validate_deploy_unit_action(action)
        "SWITCH_PLAYER":
            return _validate_switch_player_action(action)
        "END_DEPLOYMENT":
            return _validate_end_deployment_action(action)
        "EMBARK_UNITS_DEPLOYMENT":  # 🆕 NEW
            return _validate_embark_units_deployment(action)
        _:
            return {"valid": false, "errors": ["Unknown action type: " + action_type]}
```

**Add new validation function:**

```gdscript
func _validate_embark_units_deployment(action: Dictionary) -> Dictionary:
    """Validate that units can embark in a transport during deployment"""
    var errors = []

    # Check required fields
    if not action.has("transport_id"):
        errors.append("Missing transport_id")
    if not action.has("unit_ids"):
        errors.append("Missing unit_ids")

    if errors.size() > 0:
        return {"valid": false, "errors": errors}

    var transport_id = action.transport_id
    var unit_ids = action.unit_ids

    # Check if transport exists and is deployed
    var transport = get_unit(transport_id)
    if transport.is_empty():
        errors.append("Transport not found: " + transport_id)
        return {"valid": false, "errors": errors}

    if transport.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
        errors.append("Transport must be deployed before embarking units")
        return {"valid": false, "errors": errors}

    # Check if transport has transport_data
    if not transport.has("transport_data"):
        errors.append("Unit is not a transport: " + transport_id)
        return {"valid": false, "errors": errors}

    var capacity = transport.transport_data.get("capacity", 0)
    var capacity_keywords = transport.transport_data.get("capacity_keywords", [])
    var currently_embarked = transport.transport_data.get("embarked_units", [])

    # Count current embarked models
    var current_count = 0
    for embarked_id in currently_embarked:
        var embarked_unit = get_unit(embarked_id)
        if not embarked_unit.is_empty():
            current_count += _count_alive_models(embarked_unit)

    # Validate each unit to embark
    var active_player = get_current_player()
    var total_new_models = 0

    for unit_id in unit_ids:
        var unit = get_unit(unit_id)

        if unit.is_empty():
            errors.append("Unit not found: " + unit_id)
            continue

        # Must be undeployed
        if unit.get("status", 0) != GameStateData.UnitStatus.UNDEPLOYED:
            errors.append("Unit must be undeployed to embark during deployment: " + unit_id)
            continue

        # Must belong to active player
        if unit.get("owner", 0) != active_player:
            errors.append("Unit does not belong to active player: " + unit_id)
            continue

        # Check keywords if required
        if capacity_keywords.size() > 0:
            if not _unit_has_keywords(unit, capacity_keywords):
                errors.append("Unit missing required keywords %s: %s" % [str(capacity_keywords), unit_id])
                continue

        # Count models
        var model_count = _count_alive_models(unit)
        total_new_models += model_count

    # Check capacity
    if current_count + total_new_models > capacity:
        errors.append("Insufficient capacity: %d/%d (adding %d)" % [current_count + total_new_models, capacity, total_new_models])

    return {"valid": errors.size() == 0, "errors": errors}

func _unit_has_keywords(unit: Dictionary, required_keywords: Array) -> bool:
    """Check if unit has all required keywords"""
    if not unit.has("meta") or not unit.meta.has("keywords"):
        return false

    var unit_keywords = unit.meta.keywords
    for keyword in required_keywords:
        if not keyword in unit_keywords:
            return false
    return true

func _count_alive_models(unit: Dictionary) -> int:
    """Count alive models in a unit"""
    var count = 0
    if unit.has("models"):
        for model in unit.models:
            if model.get("alive", true):
                count += 1
    return count
```

---

### Step 3: Add Processing to DeploymentPhase

**File:** `40k/phases/DeploymentPhase.gd`
**Location:** Add to `process_action()` match statement (around line 173)

```gdscript
func process_action(action: Dictionary) -> Dictionary:
    var action_type = action.get("type", "")

    match action_type:
        "DEPLOY_UNIT":
            return _process_deploy_unit(action)
        "SWITCH_PLAYER":
            return _process_switch_player(action)
        "END_DEPLOYMENT":
            return _process_end_deployment(action)
        "EMBARK_UNITS_DEPLOYMENT":  # 🆕 NEW
            return _process_embark_units_deployment(action)
        _:
            return create_result(false, [], "Unknown action type: " + action_type)
```

**Add new processing function:**

```gdscript
func _process_embark_units_deployment(action: Dictionary) -> Dictionary:
    """Process units embarking in a transport during deployment"""
    var transport_id = action.transport_id
    var unit_ids = action.unit_ids
    var changes = []

    DebugLogger.info("Processing embarkation during deployment", {
        "transport_id": transport_id,
        "unit_ids": unit_ids,
        "count": unit_ids.size()
    })

    # For each unit to embark
    for unit_id in unit_ids:
        # Set embarked_in field
        changes.append({
            "op": "set",
            "path": "units.%s.embarked_in" % unit_id,
            "value": transport_id
        })

        # Set status to DEPLOYED (embarked units count as deployed)
        changes.append({
            "op": "set",
            "path": "units.%s.status" % unit_id,
            "value": GameStateData.UnitStatus.DEPLOYED
        })

        var unit = get_unit(unit_id)
        var unit_name = unit.get("meta", {}).get("name", unit_id)
        log_phase_message("Unit %s embarked in transport %s" % [unit_name, transport_id])

    # Update transport's embarked_units list
    var transport = get_unit(transport_id)
    var current_embarked = transport.get("transport_data", {}).get("embarked_units", []).duplicate()
    current_embarked.append_array(unit_ids)

    changes.append({
        "op": "set",
        "path": "units.%s.transport_data.embarked_units" % transport_id,
        "value": current_embarked
    })

    # Apply changes through PhaseManager
    if get_parent() and get_parent().has_method("apply_state_changes"):
        get_parent().apply_state_changes(changes)

    # Update local snapshot
    _apply_changes_to_local_state(changes)

    log_phase_message("Embarked %d units in transport %s" % [unit_ids.size(), transport_id])

    return create_result(true, changes)
```

---

## 🧪 TESTING STRATEGY

### Manual Testing Steps

1. **Setup:**
   - Start a multiplayer game (host and client)
   - Load armies with transports (e.g., Imperial Guard with Chimera)

2. **Test Case 1: Client Embarkation**
   - Client deploys transport
   - Client selects 2 units to embark
   - **Expected:** Host sees units as deployed/embarked
   - **Expected:** Phase can complete on both sides

3. **Test Case 2: Host Embarkation**
   - Host deploys transport
   - Host selects 2 units to embark
   - **Expected:** Client sees units as deployed/embarked
   - **Expected:** Phase can complete on both sides

4. **Test Case 3: Mixed Deployment**
   - Host deploys transport with embarked units
   - Client deploys transport with embarked units
   - Both deploy remaining units normally
   - **Expected:** Both players see all units as deployed
   - **Expected:** Phase completes successfully

### Validation Commands

```bash
# Check debug logs for synchronization
tail -f ~/Library/Application\ Support/Godot/app_userdata/40k/logs/debug_*.log | grep -i "embark"

# Look for these log messages:
# - "Sending embarkation action for transport"
# - "Processing embarkation during deployment"
# - "Unit [name] embarked in transport [id]"
# - "Embarked [count] units in transport [id]"
```

### Unit Test (Optional - for post-implementation)

```gdscript
# tests/network/test_deployment_embarkation_sync.gd
extends GutTest

func test_embarkation_syncs_to_both_players():
    # Setup: Create transport and units
    var transport_id = "transport_1"
    var unit_ids = ["unit_1", "unit_2"]

    # Create embarkation action
    var action = {
        "type": "EMBARK_UNITS_DEPLOYMENT",
        "transport_id": transport_id,
        "unit_ids": unit_ids,
        "player": 1
    }

    # Validate action
    var validation = deployment_phase.validate_action(action)
    assert_true(validation.valid, "Embarkation should be valid")

    # Process action
    var result = deployment_phase.process_action(action)
    assert_true(result.success, "Embarkation should succeed")

    # Verify state changes
    for unit_id in unit_ids:
        var unit = GameState.get_unit(unit_id)
        assert_eq(unit.embarked_in, transport_id, "Unit should be embarked")
        assert_eq(unit.status, GameStateData.UnitStatus.DEPLOYED, "Unit should be deployed")
```

---

## 📋 VALIDATION GATES

Before considering this implementation complete:

- [ ] Code compiles without errors
- [ ] Manual test: Client embarkation syncs to host
- [ ] Manual test: Host embarkation syncs to client
- [ ] Manual test: Phase completes after mixed embarkations
- [ ] Debug logs show embarkation actions being sent/received
- [ ] No regression in single-player embarkation
- [ ] No regression in normal deployment (without transports)

---

## 🎯 SUCCESS CRITERIA

**Definition of Done:**
1. Units embarked during deployment are correctly synchronized to both players
2. The deployment phase can complete when units are embarked in transports
3. Both players see the same deployment state (all units deployed/embarked)
4. Single-player gameplay is not affected (no regression)
5. Network logs show embarkation actions being synchronized

**Acceptance Test:**
```
Given: A multiplayer game in deployment phase
When: Player 1 deploys a transport and embarks 2 units
Then: Player 2 sees those 2 units as deployed and embarked
And: The deployment phase can complete successfully
And: Both players transition to the next phase together
```

---

## 📊 ESTIMATED IMPACT

- **Files Modified:** 2 (DeploymentController.gd, DeploymentPhase.gd)
- **Lines Added:** ~150
- **Lines Removed:** ~20
- **Complexity:** Medium (new action type + validation + processing)
- **Risk:** Low (follows existing patterns, feature-flagged by multiplayer)

---

## 🔗 REFERENCES

### Key Code Locations

1. **DeploymentController._complete_deployment()** - `40k/scripts/DeploymentController.gd:333-384`
   - Where deployment action is sent
   - Where we need to add embarkation action

2. **DeploymentPhase.validate_action()** - `40k/phases/DeploymentPhase.gd:48-73`
   - Where action validation happens
   - Where we add EMBARK_UNITS_DEPLOYMENT validation

3. **DeploymentPhase.process_action()** - `40k/phases/DeploymentPhase.gd:170-181`
   - Where actions are processed
   - Where we add EMBARK_UNITS_DEPLOYMENT processing

4. **TransportManager.embark_unit()** - `40k/autoloads/TransportManager.gd:76-99`
   - Reference for embarkation logic
   - We're replacing direct calls with action-based approach

5. **NetworkIntegration.route_action()** - `40k/utils/NetworkIntegration.gd:11-79`
   - How actions are routed in single/multiplayer
   - The key to synchronization

### Related Documentation

- Warhammer 40K Core Rules (Transports): https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- Godot Networking Docs: https://docs.godotengine.org/en/4.4/tutorials/networking/high_level_multiplayer.html
- Project Multiplayer Implementation: `PRPs/gh_issue_89_multiplayer_FINAL_v4s.md`

---

## 🏆 CONFIDENCE ASSESSMENT

**Score: 9/10**

**Reasoning:**
- ✅ Root cause clearly identified (no network sync)
- ✅ Solution follows existing patterns (DISEMBARK_UNIT action)
- ✅ All necessary code locations identified
- ✅ Validation and processing logic is straightforward
- ✅ No architectural changes needed
- ⚠️ Minor risk: Ensuring state changes apply atomically

**Potential Challenges:**
1. Ensuring the embarkation action fires after deployment completes (timing)
2. Handling edge cases (e.g., transport destroyed before embarkation completes)

**Mitigation:**
- Use result.success check before sending embarkation action
- Add comprehensive logging for debugging
- Test thoroughly in both single-player and multiplayer

---

**END OF PRP**
