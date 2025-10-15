# Destroyed Model Visualization PRP
**Version**: 1.0
**Date**: 2025-10-14
**Scope**: Visual feedback for destroyed models during and after combat

## 1. Executive Summary

This PRP defines the implementation of proper visual feedback for destroyed models in the Warhammer 40K 10th edition game. Currently, when a model fails a save and is destroyed, the UI does not update to reflect this change immediately. This implementation will:

1. **Hide destroyed models** from the board view in both players' UIs
2. **Mark destruction positions** with red circles matching the model's base size
3. **Clean up markers** automatically at the end of the phase
4. **Synchronize visuals** across multiplayer connections

**Key Design Decisions:**
- **Immediate Visual Feedback**: Models disappear from board as soon as they're destroyed
- **Position Markers**: Red circles show where models died (same size as their bases)
- **Phase-Based Cleanup**: Markers persist through the phase for tactical awareness, then clear
- **Multiplayer Sync**: All players see the same visual state in real-time
- **Existing Pattern Reuse**: Leverage WoundAllocationBoardHighlights for marker system

---

## 2. Current State Analysis

### 2.1 Existing Behavior (Problem)

**From User Report:**
> "When a model fails a save and is destroyed, the UI is not updating to show that the model has been destroyed when it should be. When a model is destroyed they should be removed from the board in both players UI. The position of destroyed models should be marked with a red circle the same size as the models base. These markers should then be removed from the UI for both players at the end of the phase."

**Current Flow:**
```
1. Model fails save in WoundAllocationOverlay
2. GameState updated: model.alive = false
3. Model remains visible on board (BUG)
4. No visual marker at destruction position
5. Phase ends → markers don't exist to be cleaned up
```

**Problems:**
- ❌ Model tokens remain visible after destruction
- ❌ No visual indicator where models died
- ❌ Board state doesn't match GameState
- ❌ Players must manually track which models are dead
- ❌ Multiplayer clients may see different visual states

### 2.2 Existing Code to Leverage

**WoundAllocationOverlay.gd** (lines 705-730):
- Already handles `_apply_damage_to_model()` when saves fail
- Has `_show_model_death_effect()` stub (currently minimal)
- Has `_refresh_board_visuals()` method
- Updates GameState correctly with `model.alive = false`

**WoundAllocationBoardHighlights.gd** (lines 71-84):
- Already has `HighlightType.DEAD` enum value
- Creates gray semitransparent circles with skull markers
- Has `create_highlight()` method that works for destroyed models
- Has `clear_all()` method for cleanup

**TokenVisual.gd** (_draw() method):
- Draws model tokens on board based on `model_data`
- Uses `queue_redraw()` to refresh visuals
- No current logic to hide dead models

**PhaseManager.gd** (lines 32-41):
- Calls `_on_phase_exit()` when transitioning phases
- Existing pattern for phase cleanup

**NetworkManager.gd** (_broadcast_result pattern):
- Handles multiplayer synchronization via RPCs
- Broadcasts state diffs to all clients
- Clients apply diffs and trigger visual updates

---

## 3. Core Requirements

### 3.1 Functional Requirements

1. **Model Removal on Death**
   - When `model.alive` becomes `false`, model token must disappear from board
   - Must happen immediately after damage application
   - Must work in single-player and multiplayer
   - Must synchronize across all connected clients

2. **Death Position Markers**
   - Red circle appears at model's last position when destroyed
   - Circle diameter matches model's base size (32mm, 40mm, etc.)
   - Marker is visible to all players
   - Marker is semi-transparent (60% opacity) to not block terrain/other models
   - Marker persists until phase end

3. **Phase Cleanup**
   - All death markers are removed when phase exits
   - Cleanup happens before next phase enters
   - Works for all phases (Shooting, Fight, etc.)
   - Multiplayer: Host triggers cleanup, clients follow

4. **Multiplayer Synchronization**
   - Death markers appear identically for all players
   - Timing is synchronized (markers appear at same moment)
   - No desync between marker state and GameState
   - Reconnecting players see current marker state

### 3.2 Non-Functional Requirements

- **Performance**: No frame drops when 10+ models die simultaneously
- **Reliability**: 100% visual consistency between GameState and board
- **Accessibility**: Red circles are color-blind friendly (use patterns/borders)
- **Maintainability**: Reuse existing WoundAllocationBoardHighlights pattern

---

## 4. Technical Design

### 4.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    WoundAllocationOverlay                    │
│  _apply_damage_to_model() → model.alive = false             │
│         ↓                                                     │
│  _show_model_death_effect() → create death marker           │
│         ↓                                                     │
│  _refresh_board_visuals() → hide model token                │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                       Main / BoardView                       │
│  _update_board_visuals() → iterate all models               │
│  For each model: check model.alive                           │
│    If alive: show TokenVisual                                │
│    If dead: hide TokenVisual + show death marker             │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│              WoundAllocationBoardHighlights                  │
│  create_highlight(pos, base_mm, DEAD) → red circle          │
│  Stores markers in: phase_death_markers dictionary           │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                         PhaseManager                         │
│  _on_phase_exit() → call phase._clear_death_markers()       │
│         ↓                                                     │
│  WoundAllocationBoardHighlights.clear_death_markers()        │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 Component Modifications

#### 4.2.1 WoundAllocationOverlay.gd

**Enhancement to `_show_model_death_effect()`** (line 732):

```gdscript
func _show_model_death_effect(model_id: String, model: Dictionary) -> void:
	"""Show visual effect when a model dies"""
	if not board_highlighter:
		return

	var model_pos = _get_model_position(model)
	if model_pos == Vector2.ZERO:
		return

	var base_mm = model.get("base_mm", 32)

	# ENHANCEMENT 1: Create persistent death marker (red circle)
	board_highlighter.create_death_marker(
		model_pos,
		base_mm,
		model_id
	)

	# ENHANCEMENT 2: Flash effect (yellow, temporary)
	board_highlighter.create_highlight(
		model_pos,
		base_mm,
		WoundAllocationBoardHighlights.HighlightType.SELECTED  # Yellow flash
	)

	# ENHANCEMENT 3: Trigger board to hide the model token
	_hide_destroyed_model_token(model_id)

	print("WoundAllocationOverlay: 💀 Model %s destroyed - marker created, token hidden" % model_id)
```

**New Method: `_hide_destroyed_model_token()`**:

```gdscript
func _hide_destroyed_model_token(model_id: String) -> void:
	"""Hide the visual token for a destroyed model"""
	# Get Main node which manages model visuals
	var main = get_node_or_null("/root/Main")
	if not main:
		return

	# Signal Main to update visuals for this unit
	var target_unit_id = save_data.get("target_unit_id", "")
	if main.has_method("update_unit_visuals"):
		main.update_unit_visuals(target_unit_id)
	else:
		# Fallback: full board redraw
		var board_view = get_node_or_null("/root/Main/BoardRoot/BoardView")
		if board_view:
			board_view.queue_redraw()
```

**Enhancement to `_refresh_board_visuals()`** (line 768):

```gdscript
func _refresh_board_visuals() -> void:
	"""Trigger board to refresh model visuals after damage"""
	if not board_view:
		return

	# Force board redraw to show/hide models based on alive status
	if board_view.has_method("queue_redraw"):
		board_view.queue_redraw()
		print("WoundAllocationOverlay: Triggered board visual refresh")

	# Also notify Main to update model tokens
	var main = get_node_or_null("/root/Main")
	if main and main.has_method("refresh_all_model_visuals"):
		main.refresh_all_model_visuals()

	# Refresh target unit reference to get latest state
	var target_unit_id = save_data.get("target_unit_id", "")
	target_unit = GameState.get_unit(target_unit_id)
```

#### 4.2.2 WoundAllocationBoardHighlights.gd

**New Data Structure for Death Markers**:

```gdscript
# Add to class variables
var death_markers: Dictionary = {}  # model_id -> Sprite2D (persistent markers)
```

**New Method: `create_death_marker()`**:

```gdscript
func create_death_marker(model_pos: Vector2, base_radius_mm: float, model_id: String) -> void:
	"""Create a persistent red circle marker at model's death position"""
	# Create marker sprite
	var marker = Sprite2D.new()
	marker.name = "DeathMarker_" + model_id

	# Create circle texture
	var texture = _create_circle_texture(64)
	marker.texture = texture
	marker.position = model_pos

	# Scale based on base size
	var base_px = Measurement.base_radius_px(base_radius_mm)
	var scale_factor = (base_px + 5.0) / 32.0  # Slightly larger than base
	marker.scale = Vector2(scale_factor, scale_factor)

	# Apply red semi-transparent material
	var material = ShaderMaterial.new()
	material.shader = highlight_shader

	# Red circle, 60% opacity, no pulse
	material.set_shader_parameter("base_color", Color(1.0, 0.1, 0.1, 0.6))
	material.set_shader_parameter("pulse", false)

	marker.material = material
	marker.z_index = 5  # Below models (z=10) but above terrain

	add_child(marker)

	# Store reference for cleanup
	death_markers[model_id] = marker

	print("WoundAllocationBoardHighlights: Created death marker for %s at %s" % [model_id, model_pos])
```

**New Method: `clear_death_markers()`**:

```gdscript
func clear_death_markers() -> void:
	"""Remove all death markers (called at phase end)"""
	for model_id in death_markers:
		var marker = death_markers[model_id]
		if marker and is_instance_valid(marker):
			marker.queue_free()

	death_markers.clear()
	print("WoundAllocationBoardHighlights: Cleared all death markers")
```

**Update to `clear_all()`** (line 92):

```gdscript
func clear_all() -> void:
	"""Remove all highlights from the board (but NOT death markers)"""
	for child in get_children():
		# Skip death markers - they persist until phase end
		if child.name.begins_with("DeathMarker_"):
			continue

		child.queue_free()

	# Clear only active_highlights, not death_markers
	active_highlights.clear()
	# death_markers remain until clear_death_markers() is called
```

#### 4.2.3 Main.gd / BoardView Integration

**New Method in Main.gd: `update_unit_visuals()`**:

```gdscript
func update_unit_visuals(unit_id: String) -> void:
	"""Update visual tokens for a specific unit"""
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return

	# Iterate through model tokens in BoardView
	var board_view = $BoardRoot/BoardView
	if not board_view:
		return

	var models = unit.get("models", [])
	for i in range(models.size()):
		var model = models[i]
		var model_id = model.get("id", "m%d" % i)

		# Find token visual for this model
		var token = board_view.get_node_or_null("Token_" + unit_id + "_" + model_id)

		if token:
			if model.get("alive", true):
				# Model is alive → ensure visible
				token.visible = true
			else:
				# Model is dead → hide token
				token.visible = false
				print("Main: Hidden token for destroyed model %s/%s" % [unit_id, model_id])
```

**New Method in Main.gd: `refresh_all_model_visuals()`**:

```gdscript
func refresh_all_model_visuals() -> void:
	"""Refresh visual state of all model tokens based on GameState"""
	var units = GameState.state.get("units", {})

	for unit_id in units:
		update_unit_visuals(unit_id)

	print("Main: Refreshed all model visuals")
```

#### 4.2.4 Phase Exit Cleanup

**Enhancement to ShootingPhase._on_phase_exit()** (line 39):

```gdscript
func _on_phase_exit() -> void:
	log_phase_message("Exiting Shooting Phase")

	# Close any open SaveDialog before exiting
	_close_save_dialogs()

	# Clear all shooting visuals BEFORE controller is freed
	_clear_shooting_visuals()

	# NEW: Clear death markers from board
	_clear_death_markers()

	# Clear shooting flags
	_clear_phase_flags()

	# Clear pending save data
	pending_save_data.clear()
```

**New Method in ShootingPhase: `_clear_death_markers()`**:

```gdscript
func _clear_death_markers() -> void:
	"""Clear all death markers from the board at phase end"""
	var main = get_node_or_null("/root/Main")
	if not main:
		print("ShootingPhase: Warning - Main node not found for death marker cleanup")
		return

	var board_view = main.get_node_or_null("BoardRoot/BoardView")
	if not board_view:
		print("ShootingPhase: Warning - BoardView not found for death marker cleanup")
		return

	# Find WoundAllocationBoardHighlights instance
	var highlighter = board_view.get_node_or_null("WoundHighlights")
	if highlighter and is_instance_valid(highlighter):
		if highlighter.has_method("clear_death_markers"):
			highlighter.clear_death_markers()
			print("ShootingPhase: Cleared death markers via highlighter")
		else:
			print("ShootingPhase: Warning - highlighter has no clear_death_markers method")
	else:
		print("ShootingPhase: No highlighter found to clear death markers")
```

**Same pattern applies to FightPhase, ChargePhase, etc.**

### 4.3 Multiplayer Synchronization

**Network Flow:**

```
HOST:
1. Model destroyed → GameState updated (model.alive = false)
2. Generate state diff: {"op": "set", "path": "units.X.models.Y.alive", "value": false}
3. Broadcast diff to all clients via NetworkManager._broadcast_result.rpc(result)

CLIENT:
4. Receive RPC → apply diff to local GameState
5. NetworkManager._emit_client_visual_updates() called
6. Client's Main.refresh_all_model_visuals() triggered
7. Token hidden, death marker created (same as host)

PHASE END (HOST):
8. Phase transition → _on_phase_exit() called
9. clear_death_markers() removes all red circles
10. Broadcast phase change → clients follow

RESULT:
- All players see identical visual state
- Death markers appear simultaneously
- Markers cleaned up simultaneously
```

**No New Network Messages Needed:**
- Existing state diff system handles `model.alive` changes
- Existing visual update system triggers marker creation
- Existing phase transition system handles cleanup

---

## 5. Implementation Plan

### Phase 1: Core Death Visualization (Week 1)

**Tasks:**
1. Enhance `_show_model_death_effect()` to create persistent red circle
2. Add `create_death_marker()` to WoundAllocationBoardHighlights
3. Add `death_markers` dictionary to track persistent markers
4. Update `clear_all()` to preserve death markers (only clear temp highlights)
5. Implement `_hide_destroyed_model_token()` in WoundAllocationOverlay
6. Add `update_unit_visuals()` to Main.gd
7. Test in single-player: model dies → token hides, red circle appears

**Deliverable:** Single-player visual feedback working

### Phase 2: Phase Cleanup (Week 1)

**Tasks:**
1. Add `clear_death_markers()` to WoundAllocationBoardHighlights
2. Add `_clear_death_markers()` to ShootingPhase
3. Call `_clear_death_markers()` in `_on_phase_exit()`
4. Copy pattern to FightPhase, ChargePhase
5. Test: markers persist during phase, clear on exit

**Deliverable:** Death markers clean up correctly

### Phase 3: Multiplayer Sync (Week 2)

**Tasks:**
1. Test existing state diff broadcast for `model.alive = false`
2. Verify NetworkManager triggers visual updates on clients
3. Add `refresh_all_model_visuals()` call in client visual update path
4. Test with 2 players: defender sees death → attacker sees death
5. Test phase transition cleanup across network
6. Handle edge case: client joins mid-phase (show existing markers)

**Deliverable:** Multiplayer synchronization working

### Phase 4: Polish & Edge Cases (Week 2)

**Tasks:**
1. Add fade-in animation for death markers (0.3s)
2. Add subtle border pattern to red circles for color-blind accessibility
3. Handle case: all models in unit destroyed (markers still show)
4. Handle case: model token doesn't exist (graceful failure)
5. Performance test: 20 models die simultaneously
6. Visual consistency test: markers match base sizes exactly
7. Edge case: death marker at board edge (ensure visible)

**Deliverable:** Production-ready quality

---

## 6. Testing Requirements

### 6.1 Unit Tests

```gdscript
# test_death_visualization.gd

func test_model_token_hides_on_death():
	# Given: Model token visible on board
	# When: model.alive = false
	# Then: Token.visible = false

func test_death_marker_created():
	# Given: Model destroyed at position (100, 200)
	# When: _show_model_death_effect() called
	# Then: Red circle created at (100, 200)

func test_death_marker_size_matches_base():
	# Given: Model with 40mm base destroyed
	# When: Death marker created
	# Then: Marker diameter = 40mm base + 5px padding

func test_death_markers_persist_during_phase():
	# Given: 3 models destroyed in Shooting Phase
	# When: Still in Shooting Phase
	# Then: 3 red circles visible

func test_death_markers_cleared_on_phase_exit():
	# Given: 3 death markers on board
	# When: Phase transitions to Charge
	# Then: All death markers removed

func test_temporary_highlights_dont_affect_death_markers():
	# Given: Death marker for model A exists
	# When: clear_all() called (for selection highlights)
	# Then: Death marker for model A still visible
```

### 6.2 Integration Tests

**Scenarios:**

1. **Single Model Death**
   - Wound allocation → model fails save
   - Verify: Token hides, red circle appears
   - Verify: Marker persists until phase end
   - Verify: Marker clears on phase transition

2. **Multiple Models Death (Same Phase)**
   - 5 models destroyed in Shooting Phase
   - Verify: 5 tokens hidden
   - Verify: 5 red circles appear
   - Verify: All 5 markers clear on phase exit

3. **Model Death Across Phases**
   - 2 models die in Shooting Phase
   - Phase changes to Charge
   - Verify: Shooting death markers cleared
   - 1 model dies in Fight Phase
   - Verify: Only Fight death marker shows

4. **Multiplayer Synchronization**
   - Host: Model destroyed
   - Client: Verify token hides + red circle appears
   - Timing: Within 100ms of host
   - Phase end: Both players see markers clear

5. **Reconnection Edge Case**
   - Client disconnects mid-phase (3 models dead)
   - Client reconnects
   - Verify: Client sees 3 death markers immediately

### 6.3 Visual Consistency Tests

**Checklist:**
- [ ] Red circle diameter exactly matches model base size
- [ ] Red circle position matches model's last position (not offset)
- [ ] Red circles are semi-transparent (don't fully block terrain)
- [ ] Red circles have subtle border pattern for color-blind users
- [ ] Model tokens completely disappear (not just fade)
- [ ] Death markers don't interfere with LoS visualization
- [ ] Death markers render below alive model tokens (z-index < 10)

### 6.4 Performance Tests

**Stress Test:**
```
Scenario: 20 models die simultaneously (e.g., devastating attack)
Actions:
  1. Create 20-model unit
  2. Trigger 20 failed saves at once
  3. Measure:
     - Frame time during death (target: < 16ms for 60 FPS)
     - Memory usage delta (target: < 10MB)
     - Network bandwidth (target: < 50KB for diffs)
Expected: No frame drops, smooth animation
```

---

## 7. Data Structures

### 7.1 Death Marker Storage

```gdscript
# In WoundAllocationBoardHighlights.gd
death_markers: Dictionary = {
	"m1": Sprite2D,  # Death marker for model m1
	"m3": Sprite2D,  # Death marker for model m3
	"m7": Sprite2D,  # Death marker for model m7
	# ... more as models die
}
```

### 7.2 Network State Diff (Existing)

```gdscript
# Generated by RulesEngine.apply_save_damage()
{
	"op": "set",
	"path": "units.U_BOYZ_A.models.2.alive",
	"value": false
}

# Broadcasted in result
{
	"success": true,
	"diffs": [
		{"op": "set", "path": "units.U_BOYZ_A.models.2.alive", "value": false},
		{"op": "set", "path": "units.U_BOYZ_A.models.2.current_wounds", "value": 0}
	]
}
```

---

## 8. Edge Cases & Special Scenarios

### 8.1 All Models in Unit Destroyed

**Scenario**: Last model in 5-model unit dies

**Handling:**
```
1. Model token hides
2. Red circle appears
3. Unit is now "destroyed" but markers remain
4. Phase ends → red circles cleared
5. Next phase: Unit has no alive models, entire unit removed from available actions
```

### 8.2 Model Token Doesn't Exist

**Scenario**: Token wasn't created (bug) or already freed

**Handling:**
```gdscript
var token = board_view.get_node_or_null("Token_" + unit_id + "_" + model_id)
if token:
	token.visible = false  # Safe
else:
	print("Warning: Token not found for %s, skipping hide" % model_id)
	# Still create death marker
```

### 8.3 Death Marker at Board Edge

**Scenario**: Model destroyed at board boundary, marker might be clipped

**Handling:**
- Death markers use screen-space coordinates
- Godot automatically clips to viewport
- If position is off-screen, marker won't render (expected behavior)
- Most boards have padding, so edge cases are rare

### 8.4 Rapid Phase Transitions

**Scenario**: Player immediately ends phase after model dies

**Handling:**
```
1. Model destroyed (marker created)
2. Player clicks "End Phase" 0.1s later
3. _on_phase_exit() → clear_death_markers()
4. Marker removed (expected, markers only persist during phase)
```

### 8.5 Save/Load Mid-Phase

**Scenario**: Game saved with 3 death markers on board

**Save Data:**
```json
{
	"phase": "SHOOTING",
	"death_markers": [
		{"model_id": "m1", "position": {"x": 100, "y": 200}, "base_mm": 32},
		{"model_id": "m3", "position": {"x": 150, "y": 250}, "base_mm": 40},
		{"model_id": "m7", "position": {"x": 200, "y": 300}, "base_mm": 32}
	]
}
```

**On Load:**
```
1. Phase re-created (ShootingPhase)
2. Markers not in save format → not restored (acceptable)
3. Models with alive=false won't show tokens (correct)
4. Optional future enhancement: Restore markers on load
```

**Decision**: MVP does NOT restore death markers on load. Models stay hidden (correct), markers appear blank (acceptable). Future enhancement can store marker positions in save.

---

## 9. Success Metrics

### 9.1 Functional Metrics
- **Visual Accuracy**: 100% of destroyed models show red circles
- **Token Hiding**: 100% of destroyed models have hidden tokens
- **Cleanup Rate**: 100% of markers cleared at phase end
- **Multiplayer Sync**: < 100ms delay between host and client

### 9.2 Performance Metrics
- **Frame Time**: < 16ms during 20-model simultaneous death
- **Memory**: < 10MB increase for 50 death markers
- **Network Bandwidth**: < 50KB per model death (state diff)

### 9.3 User Experience Metrics
- **Clarity**: 95%+ users immediately understand red circles = dead models
- **Distraction**: < 5% users report markers "blocking view"
- **Satisfaction**: 90%+ users prefer new system over no visual feedback

---

## 10. Risk Mitigation

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| TokenVisual refactor breaks hiding logic | High | Low | Test thoroughly, use feature flag during rollout |
| Death markers persist after phase (bug) | Medium | Medium | Comprehensive phase transition tests, logging |
| Multiplayer desync (tokens vs markers) | High | Low | Existing NetworkManager handles this well, add visual consistency check |
| Performance issues with many markers | Medium | Low | Use GPU-accelerated shaders, object pooling if needed |
| Red circles hard to see on red terrain | Low | Medium | Add subtle white border, 60% opacity ensures blending |
| Save/load doesn't restore markers | Low | High | Document as known limitation, add to future enhancements |

---

## 11. Dependencies

### 11.1 Existing Systems
- **WoundAllocationOverlay.gd**: Death detection and damage application
- **WoundAllocationBoardHighlights.gd**: Marker creation system (DEAD type exists)
- **TokenVisual.gd**: Model token rendering
- **Main.gd**: Board view management
- **PhaseManager.gd**: Phase transition hooks
- **NetworkManager.gd**: Multiplayer state synchronization
- **GameState.gd**: `model.alive` flag storage

### 11.2 New Assets Needed

**None** - All assets already exist:
- ✅ Red circle shader in WoundAllocationBoardHighlights
- ✅ `_create_circle_texture()` method
- ✅ Skull emoji for death marker (optional, already in DEAD type)

---

## 12. Migration Path

### 12.1 Feature Flag Approach

**During Development:**
```gdscript
# In GameSettings or FeatureFlags
var enable_death_markers: bool = false  # Default off

# In WoundAllocationOverlay._show_model_death_effect()
if FeatureFlags.enable_death_markers:
	board_highlighter.create_death_marker(...)
else:
	# Old behavior (no marker)
	pass
```

**Rollout Plan:**
1. **Week 1**: Flag = false, code merged but inactive
2. **Week 2**: Flag = true for dev/testing builds
3. **Week 3**: Flag = true for beta users, collect feedback
4. **Week 4**: Flag = true by default for all users
5. **Week 5+**: Remove flag, delete old code

### 12.2 Backward Compatibility

**Old Save Files:**
- No death marker data in saves → no markers on load (expected)
- Models with `alive=false` still hidden correctly
- No breaking changes to save format

---

## 13. Future Enhancements (Post-MVP)

### 13.1 Quality of Life
- **Death Marker Persistence in Saves**: Store marker positions, restore on load
- **Animated Death Effects**: Model fades out with particle explosion
- **Death Sound Effects**: Audio cue when model destroyed
- **Death Statistics**: Track which models died when (battle report)

### 13.2 Advanced Features
- **Model Drag Away**: Click death marker → shows ghost of dead model (for reference)
- **Death Marker Color Options**: User setting for color (red, black, white)
- **Death Marker Shapes**: Circle, X, skull icon (user preference)
- **Phase-Specific Markers**: Different colors for Shooting (red) vs Fight (orange)

### 13.3 Analytics
- **Death Heatmap**: Visualize where most deaths occur on board
- **Casualty Timeline**: Show order of deaths with timestamps
- **Export to Battle Report**: Include death markers in PDF export

---

## 14. Documentation Requirements

### 14.1 User Documentation
- **Visual Guide**: Screenshot showing before/after model destruction
- **FAQ**:
  - What do red circles mean? (Destroyed model positions)
  - Why did the red circles disappear? (Phase ended)
  - Can I disable death markers? (No, core feature)
- **Tutorial**: "Understanding Model Destruction" (10-second clip)

### 14.2 Developer Documentation
- **Architecture Doc**: How death visualization integrates with WoundAllocationOverlay
- **Multiplayer Protocol**: State diff for `model.alive` changes
- **Phase Cleanup Pattern**: How to add death marker cleanup to new phases
- **API Reference**: `create_death_marker()`, `clear_death_markers()`

---

## 15. Open Questions & Decisions

### 15.1 Resolved

✅ **Marker Shape**: Circle (matches base shape)
✅ **Marker Color**: Red (standard for casualties)
✅ **Marker Persistence**: Until phase end (tactical awareness)
✅ **Token Hiding**: Immediate (on death, not after phase)
✅ **Multiplayer Sync**: Existing state diff system
✅ **Save/Load**: Don't restore markers (acceptable limitation)

### 15.2 Remaining

❓ **Marker Border Pattern**:
- Should red circles have striped/dashed border for color-blind users?
- **Recommendation**: Add subtle white border (2px) for contrast

❓ **Marker Stacking**:
- If 3 models die at same spot, show 3 overlapping circles or 1 circle with "x3"?
- **Recommendation**: Show overlapping circles (more accurate)

❓ **Marker Z-Index**:
- Should death markers render above or below terrain features?
- **Recommendation**: Below models (z=10), above terrain (z=0), at z=5

❓ **Marker Fade-In**:
- Instant appearance or 0.3s fade-in animation?
- **Recommendation**: 0.3s fade-in (less jarring)

---

## 16. Validation Gates

### 16.1 Code Quality
```bash
# Godot GDScript validation (manual, no linter in this project)
# Check: No errors, no warnings
# Check: Follows existing code style
# Check: Comments added for new methods
```

### 16.2 Functional Tests
```bash
# Run all existing tests to ensure no regression
godot --headless --path /path/to/40k -s addons/gut/gut_cmdln.gd -gdir=res://tests/

# Expected: All tests pass (or same failures as before)
```

### 16.3 Visual Review
- [ ] Death markers appear at correct positions
- [ ] Death markers match base sizes
- [ ] Tokens hide when models destroyed
- [ ] Markers clear on phase transition
- [ ] Multiplayer sync < 100ms delay

---

## 17. Appendix: Visual Mockups

### 17.1 Before (Current Buggy Behavior)

```
┌──────────────────────────────────────────────────┐
│  GAME BOARD (After Model Destroyed)             │
│                                                   │
│  🔵 Marine #1 (alive)                            │
│  🔵 Marine #2 (alive but SHOWS as alive)  ← BUG │
│      (Actually dead, alive=false in GameState)   │
│  🔵 Marine #3 (alive)                            │
│                                                   │
│  No visual feedback that #2 is destroyed         │
└──────────────────────────────────────────────────┘
```

### 17.2 After (Fixed Behavior)

```
┌──────────────────────────────────────────────────┐
│  GAME BOARD (After Model Destroyed)             │
│                                                   │
│  🔵 Marine #1 (alive, token visible)            │
│  🔴 [Red Circle] (destroyed, token hidden)      │
│      ↑ Death marker at #2's position             │
│  🔵 Marine #3 (alive, token visible)            │
│                                                   │
│  Clear visual: #2 is destroyed                   │
└──────────────────────────────────────────────────┘
```

### 17.3 Death Marker Detail

```
DEATH MARKER VISUAL:
┌─────────────────┐
│   🔴 Circle     │  ← Semi-transparent red (60% opacity)
│   ╱▔▔▔▔▔╲       │  ← Diameter = model's base size + 5px
│  │  (X)  │      │  ← Optional: Subtle X or skull icon
│   ╲_____╱       │  ← White border (2px) for contrast
│                  │
│   Z-Index: 5    │  ← Below models (10), above terrain (0)
└─────────────────┘
```

---

## 18. Version History

- **v1.0** (2025-10-14): Initial PRP for destroyed model visualization

---

## 19. Sign-off

- [ ] Product Owner
- [ ] Tech Lead
- [ ] UX Designer
- [ ] QA Lead
- [ ] Network Engineer

---

## 20. References

- **Core Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- **Casualty Removal**: Core Rules Section 19.4
- **Existing PRPs**:
  - `wound_allocation_prp.md` - Wound allocation system (where deaths occur)
  - `shooting_phase_enhanced_prp.md` - Shooting mechanics
- **Existing Code**:
  - `WoundAllocationOverlay.gd:732` - Death effect method
  - `WoundAllocationBoardHighlights.gd:71` - DEAD highlight type
  - `TokenVisual.gd:13` - Model rendering
  - `PhaseManager.gd:36` - Phase exit hooks

---

## 21. Confidence Score

**Implementation Success Probability: 9/10**

**Rationale:**
- ✅ All required components already exist (WoundAllocationBoardHighlights)
- ✅ Clear integration points identified (WoundAllocationOverlay, Main.gd)
- ✅ Existing multiplayer sync system handles this automatically
- ✅ Phase cleanup pattern well-established
- ✅ No new network protocol needed
- ⚠️ Minor risk: Token visibility management across different board view implementations
- ⚠️ Minor risk: Performance with 50+ simultaneous deaths (mitigated by shader-based rendering)

**Why 9/10:**
This is a straightforward enhancement to existing systems. The hardest parts (wound allocation, death detection, marker rendering) are already implemented. Main challenge is ensuring token hiding works correctly across all view modes, which is testable and low-risk.

**Recommended Approach:**
Start with Phase 1 (core visualization) in single-player, validate thoroughly, then extend to multiplayer. Use feature flag during development to enable safe rollback if issues arise.

---
