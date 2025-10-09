# PRP: Fix Transport Embarkation Dialog Not Showing
**GitHub Issue:** TBD
**Feature Name:** transport-embark-dialog-fix
**Author:** Claude Code AI
**Date:** 2025-10-09
**Confidence Score:** 9/10

## Problem Statement

When deploying a transport during the deployment phase, the TransportEmbarkDialog should automatically appear to allow the player to select which undeployed units to embark. Currently, this dialog is not showing up, preventing players from deploying units inside transports during deployment.

## Requirements Analysis

### Expected Behavior:
1. Deploy a transport unit (e.g., Battlewagon) on the board
2. TransportEmbarkDialog automatically pops up
3. Dialog shows all eligible undeployed units that can embark
4. Player selects units (with capacity validation)
5. Selected units are embarked and marked as DEPLOYED
6. Player can skip embarkation if desired

### Current Implementation Status:
- ✅ DeploymentPhase.gd calls `_show_transport_embark_dialog` after transport deployment (lines 227-230)
- ✅ TransportEmbarkDialog.gd exists and has proper UI logic
- ✅ TransportManager.gd exists with embark/disembark logic
- ✅ transport_data is created in ArmyListManager.gd (lines 138-174)
- ❌ Dialog may not be showing due to missing debug logs
- ❌ ArmyListManager has hardcoded "ORKS INFANTRY" keyword parsing (line 159)
- ❌ No ability to skip embarkation (forces player to close dialog)

## Root Cause Analysis

### Issue 1: Hardcoded Faction Keywords
**Location:** `/40k/autoloads/ArmyListManager.gd:159`

```gdscript
# Extract keywords (e.g., "ORKS INFANTRY")
if desc.contains("ORKS INFANTRY"):
    capacity_keywords = ["ORKS", "INFANTRY"]
```

**Problem:** Only Ork transports get capacity_keywords. Other factions (Space Marines, Custodes) have empty capacity_keywords arrays, which may cause filtering issues.

**Impact:** Non-Ork transports won't have proper keyword restrictions.

### Issue 2: Silent Failures
**Location:** Multiple files

**Problem:** No debug logging to diagnose why dialog isn't appearing:
- Is `_unit_has_transport_capacity` returning false?
- Is dialog showing but with no eligible units?
- Is dialog being created but not shown?

### Issue 3: No "Skip" Option
**Location:** `/40k/scripts/TransportEmbarkDialog.gd`

**Problem:** Dialog only has "Confirm Embarkation" button. No way to deploy transport without embarking units immediately.

## Current System Analysis

### Data Flow:
```
1. DeploymentPhase._process_deploy_unit(action)
   └─> Lines 227-230: Check if unit has transport capacity
   └─> call_deferred("_show_transport_embark_dialog", unit_id)

2. DeploymentPhase._show_transport_embark_dialog(transport_id)
   └─> Lines 362-373: Create TransportEmbarkDialog
   └─> dialog.setup(transport_id)
   └─> Connect signals
   └─> popup_centered()

3. TransportEmbarkDialog.setup(transport_id)
   └─> Get transport_data
   └─> _populate_available_units(player)
   └─> _create_unit_checkboxes()

4. TransportEmbarkDialog._populate_available_units(player)
   └─> Filter units by:
       - Same owner
       - Status == UNDEPLOYED
       - Not already a transport
       - Not already embarked
       - Has required keywords
       - Fits in capacity
```

### Transport Data Structure:
```gdscript
unit["transport_data"] = {
    "capacity": 22,  # Extracted via regex
    "capacity_keywords": ["ORKS", "INFANTRY"],  # HARDCODED FOR ORKS ONLY
    "embarked_units": [],
    "firing_deck": 22  # Extracted via regex
}
```

### Existing Patterns:

#### Dialog Pattern (from SaveLoadDialog.gd):
```gdscript
extends AcceptDialog

func _ready():
    # Create UI
    popup_centered()

func setup(data):
    # Configure dialog
    pass
```

#### Phase Action Pattern (from DeploymentPhase.gd):
```gdscript
func _process_deploy_unit(action: Dictionary) -> Dictionary:
    # ... deployment logic ...

    if _unit_has_transport_capacity(unit_id):
        call_deferred("_show_transport_embark_dialog", unit_id)
```

## Implementation Strategy

### Phase 1: Add Comprehensive Debug Logging

#### 1.1 DeploymentPhase.gd Logging
**Location:** Lines 227-232, 358-373

Add logging to trace execution:
```gdscript
# After deployment
if _unit_has_transport_capacity(unit_id):
    DebugLogger.info("Transport deployed - showing embark dialog", {
        "unit_id": unit_id,
        "transport_name": unit.get("meta", {}).get("name", unit_id)
    })
    call_deferred("_show_transport_embark_dialog", unit_id)
else:
    DebugLogger.debug("Unit is not a transport or has no capacity", {
        "unit_id": unit_id,
        "has_transport_data": unit.has("transport_data"),
        "capacity": unit.get("transport_data", {}).get("capacity", 0)
    })

func _unit_has_transport_capacity(unit_id: String) -> bool:
    var unit = get_unit(unit_id)
    var has_data = unit.has("transport_data")
    var capacity = unit.get("transport_data", {}).get("capacity", 0)

    DebugLogger.debug("Checking transport capacity", {
        "unit_id": unit_id,
        "has_transport_data": has_data,
        "capacity": capacity
    })

    return has_data and capacity > 0
```

#### 1.2 TransportEmbarkDialog.gd Logging
**Location:** Lines 52-79, 81-115

Add logging to track dialog lifecycle:
```gdscript
func setup(p_transport_id: String) -> void:
    transport_id = p_transport_id
    var transport = GameState.get_unit(transport_id)

    DebugLogger.info("TransportEmbarkDialog.setup called", {
        "transport_id": transport_id,
        "transport_exists": transport != null,
        "has_transport_data": transport.has("transport_data") if transport else false
    })

    # ... existing setup code ...

    _populate_available_units(transport.owner)

    DebugLogger.info("Available units for embarkation", {
        "transport_id": transport_id,
        "player": transport.owner,
        "available_count": available_units.size(),
        "capacity": capacity,
        "capacity_keywords": capacity_keywords
    })

    _create_unit_checkboxes()

func _populate_available_units(player: int) -> void:
    available_units.clear()
    var all_units = GameState.state.units
    var filtered_out = []

    for unit_id in all_units:
        var unit = all_units[unit_id]
        var reason = ""

        # Filter checks with reason tracking
        if unit.owner != player:
            reason = "wrong_owner"
        elif unit.status != GameStateData.UnitStatus.UNDEPLOYED:
            reason = "already_deployed"
        elif unit.has("transport_data"):
            reason = "is_transport"
        elif unit.get("embarked_in", null) != null:
            reason = "already_embarked"
        elif capacity_keywords.size() > 0 and not _has_required_keywords(unit, capacity_keywords):
            reason = "missing_keywords"
        elif _get_alive_model_count(unit) > capacity:
            reason = "too_large"
        else:
            # Unit is eligible
            available_units.append({
                "unit": unit,
                "model_count": _get_alive_model_count(unit)
            })
            continue

        filtered_out.append({"unit_id": unit_id, "reason": reason})

    DebugLogger.debug("Unit filtering complete", {
        "total_units": all_units.size(),
        "eligible_units": available_units.size(),
        "filtered_out": filtered_out
    })
```

### Phase 2: Fix Hardcoded Keyword Parsing

#### 2.1 Enhance ArmyListManager.gd
**Location:** Lines 158-160

Replace hardcoded keywords with generic parsing:
```gdscript
# Extract keywords (e.g., "22 ORKS INFANTRY models" or "10 INFANTRY models")
# Pattern: "capacity of <num> <KEYWORD1> <KEYWORD2>... models"
var keyword_regex = RegEx.new()
keyword_regex.compile("capacity of \\d+ ([A-Z ]+) models")
var keyword_match = keyword_regex.search(desc)
if keyword_match:
    var keywords_str = keyword_match.get_string(1).strip_edges()
    # Split by spaces and filter out common words
    var raw_keywords = keywords_str.split(" ")
    for keyword in raw_keywords:
        keyword = keyword.strip_edges()
        if keyword.length() > 0:
            capacity_keywords.append(keyword)

    DebugLogger.debug("Parsed transport capacity keywords", {
        "unit_id": unit_id,
        "description": desc,
        "keywords": capacity_keywords
    })
```

### Phase 3: Add "Skip" Option to Dialog

#### 3.1 Modify TransportEmbarkDialog.gd
**Location:** Lines 22-28

Add cancel button to allow skipping embarkation:
```gdscript
func _ready() -> void:
    # Set dialog properties
    title = "Select Units to Embark"
    dialog_hide_on_ok = false
    get_ok_button().text = "Confirm Embarkation"
    get_ok_button().pressed.connect(_on_confirm_pressed)

    # Add "Skip" button - using add_cancel_button for built-in cancel functionality
    get_cancel_button().text = "Deploy Without Embarking"
    # AcceptDialog already handles cancel button - just need to connect to it
    cancelled.connect(_on_skip_pressed)

    # ... rest of _ready ...

func _on_skip_pressed() -> void:
    DebugLogger.info("User skipped embarkation", {
        "transport_id": transport_id
    })
    # Emit empty array to signal no embarkation
    emit_signal("units_selected", [])
    hide()
    queue_free()
```

### Phase 4: Handle Empty Embarkation List

#### 4.1 Update DeploymentPhase.gd
**Location:** Line 375-396

Handle case where user skips or no units selected:
```gdscript
func _on_deployment_embark_selected(unit_ids: Array, transport_id: String) -> void:
    if unit_ids.is_empty():
        log_phase_message("No units selected for embarkation in transport: %s" % transport_id)
        DebugLogger.info("Embarkation skipped", {"transport_id": transport_id})
        return

    log_phase_message("Processing embark for %d units into transport %s" % [unit_ids.size(), transport_id])

    # ... existing embark logic ...
```

## Implementation Tasks (In Order)

1. **Add Debug Logging** ✓
   - [ ] Add logging to DeploymentPhase._unit_has_transport_capacity
   - [ ] Add logging to DeploymentPhase._show_transport_embark_dialog
   - [ ] Add logging to TransportEmbarkDialog.setup
   - [ ] Add logging to TransportEmbarkDialog._populate_available_units
   - [ ] Add logging to TransportEmbarkDialog._create_unit_checkboxes

2. **Fix Keyword Parsing** ✓
   - [ ] Replace hardcoded "ORKS INFANTRY" check in ArmyListManager.gd
   - [ ] Use regex to extract keywords generically from description
   - [ ] Add debug logging for parsed keywords
   - [ ] Test with multiple factions (Orks, Space Marines, Custodes)

3. **Add Skip Option** ✓
   - [ ] Modify TransportEmbarkDialog._ready to add cancel button
   - [ ] Add _on_skip_pressed handler
   - [ ] Update DeploymentPhase._on_deployment_embark_selected to handle empty array

4. **Testing & Validation** ✓
   - [ ] Deploy Battlewagon (Ork transport)
   - [ ] Verify dialog appears
   - [ ] Verify eligible Ork units shown
   - [ ] Verify capacity validation works
   - [ ] Verify "Skip" button works
   - [ ] Check debug logs for complete flow
   - [ ] Test with Space Marine transports (if available)

## Validation Plan

### Godot Debug Log Validation:
```bash
# Check for dialog creation
grep "TransportEmbarkDialog.setup called" <log_file>

# Check available units
grep "Available units for embarkation" <log_file>

# Check filtering
grep "Unit filtering complete" <log_file>

# Check embarkation result
grep "Processing embark" <log_file>
```

### Manual Test Cases:

#### Test Case 1: Deploy Ork Battlewagon with Available Units
1. Start new game with Orks vs Custodes
2. Deploy Battlewagon for Player 2
3. **Expected:** Dialog appears with list of undeployed Ork Infantry units
4. **Expected:** Can select multiple units up to capacity (22 models)
5. **Expected:** "Confirm Embarkation" marks units as deployed and embarked

#### Test Case 2: Deploy Battlewagon with No Available Units
1. Start new game with Orks vs Custodes
2. Deploy all Ork Infantry units first
3. Deploy Battlewagon
4. **Expected:** Dialog appears with message "No eligible units available for embarking"
5. **Expected:** Can click "Deploy Without Embarking" to close dialog

#### Test Case 3: Skip Embarkation
1. Start new game with Orks vs Custodes
2. Deploy Battlewagon
3. **Expected:** Dialog appears with eligible units
4. Click "Deploy Without Embarking"
5. **Expected:** Dialog closes, no units embarked, continue deployment

## External Documentation References

- **Warhammer 40k Transport Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#Transports
- **Godot AcceptDialog**: https://docs.godotengine.org/en/4.4/classes/class_acceptdialog.html
- **Godot Signals**: https://docs.godotengine.org/en/4.4/getting_started/step_by_step/signals.html
- **DebugLogger Pattern**: /40k/autoloads/DebugLogger.gd

## Success Criteria

1. ✅ Dialog appears automatically after deploying a transport
2. ✅ All eligible undeployed units are shown in the dialog
3. ✅ Capacity validation prevents over-embarking
4. ✅ "Skip" button allows deploying transport without embarking
5. ✅ Selected units are properly embarked and marked as DEPLOYED
6. ✅ Debug logs provide complete visibility into dialog lifecycle
7. ✅ Keyword parsing works for all factions (not just Orks)

## Risk Mitigation

1. **Dialog Not Appearing**: Extensive debug logging will show exactly where the flow stops
2. **No Eligible Units**: Clear message shown in dialog, skip button available
3. **Keyword Parsing Errors**: Fallback to empty keywords array (allows all units)
4. **Save/Load Compatibility**: No changes to data structure, only parsing improvements

## Confidence Assessment: 9/10

High confidence due to:
- Clear issue identification (hardcoded keywords + missing logging)
- Existing code structure is sound
- Changes are minimal and focused
- Extensive debug logging will reveal any remaining issues

Minor uncertainty around:
- Whether there are additional edge cases causing dialog not to show
- Testing with all factions in the codebase

## Notes for AI Agent

### Critical Implementation Points:

1. **Use DebugLogger everywhere**: This is the key to diagnosing the issue. Add logs at every decision point.

2. **Regex for keyword parsing**: Use a generic regex pattern that works for all factions:
   ```gdscript
   keyword_regex.compile("capacity of \\d+ ([A-Z ]+) models")
   ```

3. **Handle empty arrays gracefully**: When no units selected, just log and return - don't error.

4. **Test the flow manually**: After implementing, deploy a Battlewagon and check the logs to see the complete flow.

5. **Validation via logs**: The debug log file location is:
   - `/Users/.../Library/Application Support/Godot/app_userdata/40k/logs/debug_YYYYMMDD_HHMMSS.log`
   - Or use: `print(DebugLogger.get_real_log_file_path())`

### Files to Modify:
1. `/40k/autoloads/ArmyListManager.gd` (lines 158-160)
2. `/40k/phases/DeploymentPhase.gd` (lines 227-232, 358-373, 375-396)
3. `/40k/scripts/TransportEmbarkDialog.gd` (lines 22-28, 52-79, 81-115, add new _on_skip_pressed)

### Expected Code Diff Size:
- ~50 lines added (mostly debug logging)
- ~5 lines modified (keyword parsing)
- ~10 lines added (skip button)

Total: ~65 line changes across 3 files
