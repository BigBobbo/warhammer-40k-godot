# Wound Allocation Duplication Fix PRP
**Version**: 1.0
**Date**: 2025-10-14
**Scope**: Fix duplicate wound allocation overlays and improve visual feedback for dead models

## 1. Executive Summary

This PRP addresses critical bugs in the multiplayer wound allocation system where:
1. **Multiple overlays are created** from a single weapon hit (appears 3 times)
2. **Dead models can be re-selected** with no visual indication they're destroyed
3. **UI building fails** with shader property errors

The root cause is that the `saves_required` signal is being emitted multiple times in multiplayer due to both the host's initial emission and the client's re-emission during visual updates.

---

## 2. Problem Analysis

### 2.1 Current Behavior (Broken)

**From Defender's Output:**
```
◆◆◆ WoundAllocationOverlay.setup() CALLED ◆◆◆  [1st time - @Control@1415]
WoundAllocationOverlay: Mouse click detected...
WoundAllocationOverlay: Model clicked: m2
WoundAllocationOverlay: Save roll: 6 vs 3+ = SAVED
...
WoundAllocationOverlay: Closing

◆◆◆ WoundAllocationOverlay.setup() CALLED ◆◆◆  [2nd time - @Control@1403]
WoundAllocationOverlay: Mouse click detected...
WoundAllocationOverlay: Model clicked: m2  [SAME MODEL AGAIN]
WoundAllocationOverlay: Save roll: 1 vs 3+ = FAILED
WoundAllocationOverlay: Model m2 destroyed
...
WoundAllocationOverlay: Closing

◆◆◆ WoundAllocationOverlay.setup() CALLED ◆◆◆  [3rd time - @Control@1392]
WoundAllocationOverlay: Mouse click detected...
WoundAllocationOverlay: Model clicked: m1  [Dead model m2 still clickable]
```

**From Attacker's Output:**
```
ShootingController: _on_saves_required CALLED  [1st call]
========================================
========================================
ShootingController: _on_saves_required CALLED  [2nd call - DUPLICATE]
```

### 2.2 Root Cause Analysis

**Signal Emission Chain:**

```
MULTIPLAYER FLOW (Player 2 = Attacker, Player 1 = Defender):

1. Player 2 (client) confirms targets
   └─> Sends action to Host (Player 1)

2. Host (Player 1) processes CONFIRM_TARGETS
   ├─> ShootingPhase.gd line 444: emit_signal("saves_required", save_data_list)
   │   └─> ShootingController._on_saves_required() [1st call on HOST]
   │       └─> Creates overlay for defender (player 1 = host)
   └─> Broadcasts result back to client (Player 2)

3. Client (Player 2) receives result in NetworkManager._broadcast_result()
   ├─> Calls _emit_client_visual_updates() (line 217)
   └─> NetworkManager line 326: phase.emit_signal("saves_required", save_data_list)
       └─> ShootingController._on_saves_required() [2nd call on CLIENT]
           └─> Creates overlay (but should_show_dialog = false for attacker)
               └─> BUT the signal fires AGAIN somehow

4. PROBLEM: Signal is emitted AGAIN (3rd time)
   └─> Creates 3rd overlay
```

**Why 3 times?**
Looking at the logs more carefully:
- 1st emission: Host processes action, emits signal
- 2nd emission: Client re-emits for visual updates
- 3rd emission: Unknown - possibly a re-connection issue or duplicate broadcast

### 2.3 Secondary Issues

**UI Building Error (StyleBoxFlat):**
```gdscript
SCRIPT ERROR: Invalid assignment of property or key 'border_width_all'
on a base object of type 'StyleBoxFlat'.
```

This happens because `border_width_all` is not a valid property. The correct approach is to set individual border widths.

**Dead Model Selection:**
- Model m2 is destroyed after failing save
- But m2 is STILL clickable in subsequent overlays
- No visual indication that m2 is dead

---

## 3. Solution Design

### 3.1 Fix 1: Debounce Signal Emission

**Location:** `ShootingController.gd:1016-1208`

**Problem:** The `_on_saves_required()` handler doesn't properly prevent duplicate signals for the same weapon/target combination.

**Current Debounce Logic:**
```gdscript
# Line 1091-1108
if save_dialog_showing:
    var same_context = (
        current_save_context.get("target_unit_id") == new_context.get("target_unit_id") and
        current_save_context.get("weapon_id") == new_context.get("weapon_id")
    )

    if same_context:
        print("❌ Already processing saves, ignoring duplicate")
        return
```

**Issues:**
1. `save_dialog_showing` flag is only set AFTER all the checks, so rapid duplicates slip through
2. `weapon_id` comparison may not match (could be empty string vs actual ID)
3. Flag is cleared on `allocation_complete`, but overlays queue_free() immediately, causing race conditions

**Solution:**
Add **instance tracking** in addition to flag-based debouncing:

```gdscript
# New instance variable at top of ShootingController
var active_allocation_overlay: WoundAllocationOverlay = null

func _on_saves_required(save_data_list: Array) -> void:
    # ... existing checks ...

    # ENHANCED DEBOUNCE: Check if overlay already exists AND is same context
    if active_allocation_overlay != null and is_instance_valid(active_allocation_overlay):
        var existing_context = {
            "target_unit_id": active_allocation_overlay.save_data.get("target_unit_id", ""),
            "weapon_name": active_allocation_overlay.save_data.get("weapon_name", "")
        }
        var new_context = {
            "target_unit_id": save_data.get("target_unit_id", ""),
            "weapon_name": save_data.get("weapon_name", "")
        }

        if existing_context == new_context:
            print("ShootingController: ❌ Overlay already active for this weapon/target")
            print("  - Ignoring duplicate signal emission")
            return

    # ... rest of function ...

    # After creating overlay:
    active_allocation_overlay = overlay
    overlay.allocation_complete.connect(func(_summary):
        active_allocation_overlay = null  # Clear reference
        # ... existing cleanup ...
    )
```

### 3.2 Fix 2: Prevent Client Re-Emission on Non-Defender

**Location:** `NetworkManager.gd:221-340` (`_emit_client_visual_updates`)

**Problem:** Client re-emits `saves_required` signal even when the client is the attacker (not defender).

**Current Logic:**
```gdscript
# Line 317-326
if action_type == "CONFIRM_TARGETS" or ...:
    var save_data_list = result.get("save_data_list", [])
    if not save_data_list.is_empty() and phase.has_signal("saves_required"):
        print("✅ Client re-emitting saves_required signal")
        phase.emit_signal("saves_required", save_data_list)
```

**Issue:** This always re-emits, regardless of who the defender is.

**Solution:**
Only re-emit if the local player is the defender:

```gdscript
if action_type == "CONFIRM_TARGETS" or ...:
    var save_data_list = result.get("save_data_list", [])

    if not save_data_list.is_empty() and phase.has_signal("saves_required"):
        # NEW: Check if local player is the defender before re-emitting
        var first_save_data = save_data_list[0]
        var target_unit_id = first_save_data.get("target_unit_id", "")
        var target_unit = GameState.get_unit(target_unit_id)
        var defender_player = target_unit.get("owner", -1)

        var local_peer_id = multiplayer.get_unique_id()
        var local_player = peer_to_player_map.get(local_peer_id, -1)

        if local_player == defender_player:
            print("✅ Client (defender) re-emitting saves_required signal")
            phase.emit_signal("saves_required", save_data_list)
        else:
            print("ℹ️ Client (attacker) skipping saves_required re-emission")
```

### 3.3 Fix 3: Fix StyleBoxFlat Border Width

**Location:** `WoundAllocationOverlay.gd:253-256`

**Problem:**
```gdscript
instruction_panel_style.border_width_all = 1  # ❌ NOT A VALID PROPERTY
```

**Solution:**
```gdscript
# Replace line 255 with:
instruction_panel_style.set_border_width_all(1)  # ✅ Use method instead
```

### 3.4 Fix 4: Visual Feedback for Dead Models

**Location:** `WoundAllocationOverlay.gd:497-533`

**Problem:** Dead models can still be clicked and have no visual indication.

**Current Highlight Logic:**
```gdscript
for i in range(all_models.size()):
    var model = all_models[i]
    if not model.get("alive", true):
        continue  # Skips dead models from highlights
```

**Issue:** This correctly skips highlighting, but doesn't provide visual feedback that the model is dead.

**Solution:**
Add a **dead model overlay** that marks destroyed models:

```gdscript
func _highlight_valid_models():
    board_highlighter.clear_all()

    var wounded_models = _get_wounded_models()
    var all_models = target_unit.get("models", [])

    for i in range(all_models.size()):
        var model = all_models[i]
        var model_id = model.get("id", "m%d" % i)
        var model_pos = _get_model_position(model)
        var base_mm = model.get("base_mm", 32)

        if model_pos == Vector2.ZERO:
            continue

        # NEW: Mark dead models with X overlay
        if not model.get("alive", true):
            board_highlighter.create_highlight(
                model_pos, base_mm,
                WoundAllocationBoardHighlights.HighlightType.DEAD  # NEW TYPE
            )
            continue

        # Existing highlight logic for alive models
        if model_id in wounded_models:
            board_highlighter.create_highlight(
                model_pos, base_mm,
                WoundAllocationBoardHighlights.HighlightType.PRIORITY
            )
        elif wounded_models.is_empty():
            board_highlighter.create_highlight(
                model_pos, base_mm,
                WoundAllocationBoardHighlights.HighlightType.SELECTABLE
            )
```

**Add DEAD type to WoundAllocationBoardHighlights.gd:**
```gdscript
enum HighlightType {
    PRIORITY,    # Red pulsing - must select
    SELECTABLE,  # Green steady - can select
    SELECTED,    # Yellow flash - just selected
    DEAD         # Gray X marker - model destroyed (NEW)
}

func create_highlight(model_pos: Vector2, base_mm: float, type: HighlightType, model_id: String = "") -> void:
    # ... existing code ...

    match type:
        # ... existing cases ...

        HighlightType.DEAD:
            # Gray semitransparent circle with X
            var dead_marker = Node2D.new()
            dead_marker.position = model_pos

            # Draw gray circle
            var circle = ColorRect.new()
            circle.custom_minimum_size = Vector2(base_px * 2, base_px * 2)
            circle.position = Vector2(-base_px, -base_px)
            circle.color = Color(0.3, 0.3, 0.3, 0.5)
            dead_marker.add_child(circle)

            # Draw X marker
            var x_marker = Label.new()
            x_marker.text = "💀"  # Skull emoji or red X
            x_marker.add_theme_font_size_override("font_size", int(base_px * 1.5))
            x_marker.position = Vector2(-base_px * 0.5, -base_px * 0.5)
            dead_marker.add_child(x_marker)

            add_child(dead_marker)
```

---

## 4. Implementation Tasks

### 4.1 Task Breakdown

**Task 1: Enhanced Debouncing in ShootingController**
- [ ] Add `active_allocation_overlay` instance variable
- [ ] Update `_on_saves_required()` to check instance validity
- [ ] Compare contexts using overlay reference
- [ ] Clear reference on allocation_complete
- [ ] Test: Verify only one overlay created per weapon/target
- **Files**: `ShootingController.gd`
- **Lines**: 19-20 (add variable), 1016-1208 (update function)
- **Estimated Time**: 2 hours

**Task 2: Conditional Re-Emission in NetworkManager**
- [ ] Check local player ID before re-emitting saves_required
- [ ] Only re-emit if local player is defender
- [ ] Add debug logging for skipped re-emissions
- [ ] Test: Verify attacker doesn't get duplicate overlays
- **Files**: `NetworkManager.gd`
- **Lines**: 221-340
- **Estimated Time**: 1.5 hours

**Task 3: Fix StyleBoxFlat Border Width**
- [ ] Replace `border_width_all` property assignment with method call
- [ ] Verify UI builds without errors
- [ ] Test: Overlay displays correctly
- **Files**: `WoundAllocationOverlay.gd`
- **Lines**: 253-256
- **Estimated Time**: 0.5 hours

**Task 4: Add Dead Model Visual Feedback**
- [ ] Add `DEAD` highlight type to enum
- [ ] Implement dead model highlighting in _highlight_valid_models()
- [ ] Create visual representation (gray circle + skull/X)
- [ ] Prevent clicks on dead model positions
- [ ] Test: Dead models show gray X, cannot be clicked
- **Files**: `WoundAllocationOverlay.gd` (lines 497-533), `WoundAllocationBoardHighlights.gd` (new lines)
- **Estimated Time**: 3 hours

**Task 5: Integration Testing**
- [ ] Test single-player: One overlay per weapon
- [ ] Test multiplayer (2 players): Defender sees one overlay, attacker sees none
- [ ] Test sequential weapons: Each weapon creates only one overlay
- [ ] Test dead model clicking: Cannot select, visual feedback clear
- [ ] Test UI building: No shader errors
- **Estimated Time**: 2 hours

---

## 5. Testing Strategy

### 5.1 Unit Tests

**Test: Single Overlay Per Signal**
```gdscript
func test_single_overlay_per_weapon():
    # Given: saves_required signal is emitted twice rapidly
    # When: Both emissions have same target_unit_id and weapon_name
    # Then: Only one overlay is created
    # And: Second emission is ignored with log message
```

**Test: Dead Model Not Selectable**
```gdscript
func test_dead_model_not_selectable():
    # Given: Model m2 is marked as alive=false
    # When: _highlight_valid_models() is called
    # Then: m2 gets DEAD highlight (gray X)
    # And: m2 does not get PRIORITY or SELECTABLE highlight
    # And: Clicking m2's position returns empty string from _find_model_at_position()
```

**Test: Attacker Doesn't Re-Emit**
```gdscript
func test_attacker_skips_re_emission():
    # Given: Client is the attacker (not defender)
    # When: _emit_client_visual_updates receives CONFIRM_TARGETS result
    # Then: saves_required signal is NOT re-emitted
    # And: Log shows "Client (attacker) skipping saves_required re-emission"
```

### 5.2 Integration Tests

**Scenario 1: Multiplayer Shooting**
```
Setup:
- Player 1 (host, defenders with Witchseekers unit)
- Player 2 (client, attackers with Battlewagon)

Steps:
1. Player 2 confirms targets for Big shoota
2. Host processes and emits saves_required [1st emission]
3. Host creates overlay for Player 1 (defender)
4. Host broadcasts result to Player 2
5. Player 2 receives result and calls _emit_client_visual_updates
6. Player 2 checks: local_player (2) != defender_player (1)
7. Player 2 SKIPS re-emission
8. Player 1 (defender) sees ONE overlay
9. Player 2 (attacker) sees ZERO overlays

Expected:
- Exactly 1 overlay appears (on defender's screen)
- No duplicate overlays
- No errors in console
```

**Scenario 2: Dead Model Visual Feedback**
```
Setup:
- Defender has 3-model unit (m1, m2, m3)
- Attacker causes 2 wounds

Steps:
1. Defender allocates wound #1 to m2
2. m2 fails save, takes 1 damage
3. m2 is destroyed (alive=false)
4. Overlay advances to wound #2
5. _highlight_valid_models() is called
6. m2 should have DEAD highlight (gray X)
7. m1 and m3 should have SELECTABLE highlights (green)
8. Defender clicks m2's position
9. _find_model_at_position() returns "" (no model)
10. No action taken, defender must click m1 or m3

Expected:
- m2 shows gray X marker
- m2 cannot be selected
- m1 and m3 are selectable
- Clear visual distinction between alive and dead
```

---

## 6. Code Changes

### 6.1 ShootingController.gd

**Add at line 19-20:**
```gdscript
var selected_weapon_id: String = ""  # Currently selected weapon for modifier display
var save_dialog_showing: bool = false  # Prevent multiple dialogs
var current_save_context: Dictionary = {}  # Track what we're showing dialog for (weapon, target)
var active_allocation_overlay: WoundAllocationOverlay = null  # NEW: Track active overlay instance
```

**Replace lines 1016-1208 with:**
```gdscript
func _on_saves_required(save_data_list: Array) -> void:
    """Show WoundAllocationOverlay when defender needs to make saves"""
    print("========================================")
    print("ShootingController: _on_saves_required CALLED")
    print("ShootingController: Saves required for %d targets" % save_data_list.size())

    if save_data_list.is_empty():
        print("ShootingController: Warning - empty save data list")
        return

    var save_data = save_data_list[0]

    # ENHANCED DEBOUNCE: Check if overlay already exists for this weapon/target
    if active_allocation_overlay != null and is_instance_valid(active_allocation_overlay):
        var existing_target = active_allocation_overlay.save_data.get("target_unit_id", "")
        var existing_weapon = active_allocation_overlay.save_data.get("weapon_name", "")
        var new_target = save_data.get("target_unit_id", "")
        var new_weapon = save_data.get("weapon_name", "")

        if existing_target == new_target and existing_weapon == new_weapon:
            print("ShootingController: ❌ Overlay already active for this weapon/target")
            print("  - Existing: %s @ %s" % [existing_weapon, existing_target])
            print("  - Duplicate: %s @ %s" % [new_weapon, new_target])
            print("  - Ignoring duplicate signal emission")
            print("========================================")
            return

    # Get defender
    var target_unit_id = save_data.get("target_unit_id", "")
    if target_unit_id == "":
        push_error("ShootingController: No target_unit_id in save data")
        return

    var target_unit = GameState.get_unit(target_unit_id)
    if target_unit.is_empty():
        push_error("ShootingController: Target unit not found: " + target_unit_id)
        return

    var defender_player = target_unit.get("owner", 0)

    # Determine if this local player should see the dialog
    var should_show_dialog = false

    if NetworkManager.is_networked():
        var local_peer_id = multiplayer.get_unique_id()
        var local_player = NetworkManager.peer_to_player_map.get(local_peer_id, -1)
        should_show_dialog = (local_player == defender_player)
    else:
        should_show_dialog = true

    if not should_show_dialog:
        print("ShootingController: Not showing dialog - not the defending player (attacker)")
        print("========================================")
        return

    print("ShootingController: ✅ Showing WoundAllocationOverlay for defender")

    # Temporarily disable ShootingController's input processing
    set_process_input(false)
    set_process_unhandled_input(false)

    # Create WoundAllocationOverlay
    var overlay = WoundAllocationOverlay.new()

    # Store reference to active overlay
    active_allocation_overlay = overlay

    # Connect to allocation_complete signal to clear the reference
    overlay.allocation_complete.connect(func(_summary):
        print("ShootingController: Wound allocation complete, clearing overlay reference")
        active_allocation_overlay = null  # Clear reference
        set_process_input(true)
        set_process_unhandled_input(true)
    )

    # Add to scene tree
    var main = get_node_or_null("/root/Main")
    if not main:
        push_error("ShootingController: /root/Main not found!")
        return

    main.add_child(overlay)

    # Wait one frame to ensure _ready() has been called
    await get_tree().process_frame

    # Setup with save data
    overlay.setup(save_data, defender_player)

    print("========================================")
```

### 6.2 NetworkManager.gd

**Replace lines 310-326 with:**
```gdscript
# Handle shooting phase saves_required signal
print("NetworkManager:   Checking for saves_required...")
if action_type == "CONFIRM_TARGETS" or action_type == "RESOLVE_SHOOTING" or action_type == "RESOLVE_WEAPON_SEQUENCE" or action_type == "APPLY_SAVES":
    var save_data_list = result.get("save_data_list", [])

    if not save_data_list.is_empty() and phase.has_signal("saves_required"):
        # NEW: Only re-emit if local player is the defender
        var first_save_data = save_data_list[0]
        var target_unit_id = first_save_data.get("target_unit_id", "")

        if target_unit_id != "":
            var target_unit = GameState.get_unit(target_unit_id)
            var defender_player = target_unit.get("owner", -1)

            var local_peer_id = multiplayer.get_unique_id()
            var local_player = peer_to_player_map.get(local_peer_id, -1)

            print("NetworkManager:   Defender check: local=%d, defender=%d" % [local_player, defender_player])

            if local_player == defender_player:
                print("NetworkManager: ✅ Client (defender) re-emitting saves_required signal")
                phase.emit_signal("saves_required", save_data_list)
            else:
                print("NetworkManager: ℹ️ Client (attacker) skipping saves_required re-emission")
        else:
            print("NetworkManager:   ⚠️ No target_unit_id, skipping saves_required check")
```

### 6.3 WoundAllocationOverlay.gd

**Replace line 255 with:**
```gdscript
instruction_panel_style.set_border_width_all(1)
```

**Replace lines 497-533 with:**
```gdscript
func _highlight_valid_models() -> void:
    """Add visual highlights to models based on allocation rules"""
    if not board_highlighter:
        return

    board_highlighter.clear_all()

    var wounded_models = _get_wounded_models()
    var all_models = target_unit.get("models", [])

    for i in range(all_models.size()):
        var model = all_models[i]
        var model_id = model.get("id", "m%d" % i)
        var model_pos = _get_model_position(model)
        if model_pos == Vector2.ZERO:
            continue

        var base_mm = model.get("base_mm", 32)

        # NEW: Mark dead models with gray X overlay
        if not model.get("alive", true):
            board_highlighter.create_highlight(
                model_pos, base_mm,
                WoundAllocationBoardHighlights.HighlightType.DEAD,
                model_id
            )
            continue

        # Highlight alive models
        if model_id in wounded_models:
            # MUST SELECT - Red pulsing highlight
            board_highlighter.create_highlight(
                model_pos, base_mm,
                WoundAllocationBoardHighlights.HighlightType.PRIORITY,
                model_id
            )
        elif wounded_models.is_empty():
            # CAN SELECT - Green highlight (only if no wounded models)
            board_highlighter.create_highlight(
                model_pos, base_mm,
                WoundAllocationBoardHighlights.HighlightType.SELECTABLE,
                model_id
            )
```

### 6.4 WoundAllocationBoardHighlights.gd

**Add DEAD to enum (after line 7):**
```gdscript
enum HighlightType {
    PRIORITY,    # Red pulsing - must select
    SELECTABLE,  # Green steady - can select
    SELECTED,    # Yellow flash - just selected
    DEAD         # Gray X marker - model destroyed (NEW)
}
```

**Add DEAD case to create_highlight method:**
```gdscript
func create_highlight(model_pos: Vector2, base_mm: float, type: HighlightType, model_id: String = "") -> void:
    # ... existing code ...

    match type:
        # ... existing PRIORITY, SELECTABLE, SELECTED cases ...

        HighlightType.DEAD:
            # Gray semitransparent circle with skull marker
            var dead_marker = Node2D.new()
            dead_marker.position = model_pos
            dead_marker.name = "DeadMarker_" + model_id

            # Calculate base size in pixels
            var base_radius_px = Measurement.base_radius_px(base_mm)

            # Draw gray circle background
            var bg_circle = ColorRect.new()
            bg_circle.custom_minimum_size = Vector2(base_radius_px * 2, base_radius_px * 2)
            bg_circle.position = Vector2(-base_radius_px, -base_radius_px)
            bg_circle.color = Color(0.2, 0.2, 0.2, 0.6)
            bg_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
            dead_marker.add_child(bg_circle)

            # Draw skull marker
            var skull_label = Label.new()
            skull_label.text = "💀"
            skull_label.add_theme_font_size_override("font_size", int(base_radius_px * 1.2))
            skull_label.add_theme_color_override("font_color", Color(0.8, 0.1, 0.1))
            skull_label.position = Vector2(-base_radius_px * 0.6, -base_radius_px * 0.6)
            skull_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
            dead_marker.add_child(skull_label)

            add_child(dead_marker)
```

---

## 7. Validation Gates

### 7.1 Pre-Commit Validation

```bash
# Ensure Godot scripts have no syntax errors
cd /Users/robertocallaghan/Documents/claude/godotv2/40k
godot --check-only --path . scripts/ShootingController.gd
godot --check-only --path . autoloads/NetworkManager.gd
godot --check-only --path . scripts/WoundAllocationOverlay.gd
godot --check-only --path . scripts/WoundAllocationBoardHighlights.gd

# If syntax is valid, print success
echo "✓ All scripts have valid syntax"
```

### 7.2 Runtime Validation

```bash
# Start Godot in headless mode and run automated tests
godot --headless --path /Users/robertocallaghan/Documents/claude/godotv2/40k

# Look for test results in debug log
tail -f /Users/robertocallaghan/Library/Application\ Support/Godot/app_userdata/40k/logs/debug_*.log | grep -E "(PASS|FAIL|ERROR)"

# Manual testing checklist:
# 1. Single overlay per weapon ✓
# 2. Dead models show gray X ✓
# 3. Dead models not clickable ✓
# 4. No shader errors ✓
# 5. Multiplayer sync works ✓
```

### 7.3 Success Criteria

- [ ] **No duplicate overlays**: Only 1 overlay per weapon/target in multiplayer
- [ ] **Dead models marked**: Gray X marker appears on dead models
- [ ] **Dead models not selectable**: Clicking dead model does nothing
- [ ] **No shader errors**: UI builds without "border_width_all" error
- [ ] **Attacker sees nothing**: Attacker doesn't get unwanted overlays
- [ ] **Defender sees one**: Defender sees exactly one overlay per weapon

---

## 8. References

- **Core Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- **Existing PRPs**:
  - `wound_allocation_prp.md` - Original wound allocation implementation
  - `shooting_phase_enhanced_prp.md` - Shooting mechanics
- **Related Files**:
  - `40k/scripts/ShootingController.gd` (lines 1016-1208)
  - `40k/autoloads/NetworkManager.gd` (lines 221-340)
  - `40k/scripts/WoundAllocationOverlay.gd` (lines 255, 497-533)
  - `40k/scripts/WoundAllocationBoardHighlights.gd` (enum + create_highlight)

---

## 9. Confidence Score

**8/10** - High confidence for one-pass implementation

**Reasoning:**
- ✅ Root cause identified with concrete logs
- ✅ Clear solution with specific line numbers
- ✅ All affected files identified
- ✅ Testable validation gates
- ⚠️ Potential edge case: What if signal fires during overlay creation? (mitigated by instance check)
- ⚠️ Potential edge case: What if overlay queue_free() doesn't complete before next signal? (mitigated by is_instance_valid check)

**Risks:**
- Godot's signal system may have subtle timing issues
- Multiplayer race conditions are hard to test exhaustively

**Mitigation:**
- Extensive logging to debug any remaining issues
- Instance validity checks prevent stale references
- Conditional re-emission reduces signal traffic
