# PRP: Debug Mode Implementation

## Issue Information
- **Issue Number**: #14
- **Title**: Create debug mode
- **Priority**: Medium
- **Confidence Score**: 8/10

## Executive Summary
Implement a debug mode accessible via the "9" key that allows unrestricted clicking and dragging of any models from either army without range restrictions or phase constraints. The mode should provide visual feedback when active and restore the previous phase state when exited.

## Requirements Analysis

### Core Requirements
1. **Toggle Access**: Press "9" key to enter debug mode
2. **Unrestricted Movement**: Click and drag any models without range/phase restrictions
3. **Army Agnostic**: Allow moving models from both player armies
4. **State Preservation**: Remember and restore the phase that was active before entering debug mode
5. **Exit Mechanism**: Press "9" again to exit debug mode
6. **Visual Feedback**: Clear indication that debug mode is active

### User Experience Flow
```
Normal Game → Press 9 → Debug Mode → Move Any Models → Press 9 → Return to Previous Phase
```

## Current State Analysis

### Existing Input System
- `scripts/Main.gd` handles global input via `_input()` method (lines 293-331)
- Current key bindings: `[` for save, `]` for load, WASD for camera
- Input actions defined in `project.godot` (lines 38-59)

### Current Movement System  
- `scripts/MovementController.gd` handles model dragging with phase restrictions
- Uses `_unhandled_input()` for drag detection (line 486)
- Validates movements against phase rules and range limitations
- Drag workflow: `_start_model_drag()` → `_update_model_drag()` → `_end_model_drag()`

### Phase Management
- `autoloads/PhaseManager.gd` manages phase transitions
- `phases/BasePhase.gd` defines phase interface with validation methods
- Current phase stored in GameState with `get_current_phase()` and `set_phase()`

### Visual System
- `scripts/TokenVisual.gd` renders model tokens with player colors
- `token_layer` in Main.gd manages all model visuals
- Models have visual feedback for preview states

## Implementation Design

### Architecture Overview

```
DebugManager (Autoload)
├── Debug State Management
├── Input Handling (9 key toggle)
├── Model Movement Override
├── Visual Feedback System
└── Phase State Preservation

Main.gd Integration
├── Debug Input Detection
├── DebugManager Integration
└── Visual Overlay Management

TokenVisual Enhancement
├── Debug Visual State
└── Unrestricted Drag Mode
```

### Core Components

#### 1. DebugManager Autoload
**Path**: `autoloads/DebugManager.gd`

```gdscript
extends Node

signal debug_mode_changed(active: bool)

var debug_mode_active: bool = false
var previous_phase: GameStateData.Phase
var previous_phase_instance: BasePhase = null
var debug_overlay: Control = null

# Main API
func toggle_debug_mode() -> void
func enter_debug_mode() -> void  
func exit_debug_mode() -> void
func is_debug_active() -> bool
```

**Key Features**:
- Manages debug state globally
- Preserves previous phase information
- Provides signals for UI/visual updates
- Coordinates with PhaseManager for smooth transitions

#### 2. Debug Input Handling
**Integration Point**: `scripts/Main.gd._input()`

```gdscript
# Add to existing _input method
if event is InputEventKey and event.pressed and event.keycode == KEY_9:
    DebugManager.toggle_debug_mode()
    get_viewport().set_input_as_handled()
    return
```

**Features**:
- Highest priority input handling (before phase-specific input)
- Prevents key from propagating to other systems
- Uses direct keycode check (more reliable than input actions)

#### 3. Debug Movement Controller
**Integration**: Extend `scripts/MovementController.gd`

```gdscript
func _start_model_drag(mouse_pos: Vector2) -> void:
    if DebugManager.is_debug_active():
        _start_debug_model_drag(mouse_pos)
        return
    # Existing logic continues...

func _start_debug_model_drag(mouse_pos: Vector2) -> void:
    # Bypass all phase/ownership/range restrictions
    # Allow dragging any visible model token
```

**Key Differences from Normal Movement**:
- No phase validation
- No ownership validation (can move enemy units)
- No range restrictions
- No engagement range checks
- Immediate position updates without confirmation

#### 4. Visual Feedback System
**Components**:
- **Debug Overlay**: Semi-transparent overlay with "DEBUG MODE" text
- **Token Highlighting**: All tokens show drag-ready state
- **Different Colors**: Debug tokens use distinct visual style

```gdscript
# TokenVisual.gd enhancement
var debug_mode: bool = false

func set_debug_mode(active: bool) -> void:
    debug_mode = active
    queue_redraw()

func _draw() -> void:
    var fill_color: Color
    var border_color: Color
    
    if debug_mode:
        # Use distinct debug colors (bright yellow/orange)
        fill_color = Color.YELLOW
        border_color = Color.ORANGE
    else:
        # Existing player color logic
```

#### 5. Debug Overlay UI
**Path**: `ui/DebugOverlay.tscn` + `ui/DebugOverlay.gd`

```gdscript
extends Control

@onready var debug_label: Label = $DebugLabel
@onready var instructions_label: Label = $InstructionsLabel

func show_debug_overlay() -> void:
    visible = true
    debug_label.text = "DEBUG MODE ACTIVE"
    instructions_label.text = "Press 9 to exit | Drag any model freely"
```

**Visual Design**:
- CanvasLayer with layer = 128 (highest)
- Semi-transparent dark background
- Bright text indicating debug status
- Corner positioning to avoid gameplay interference

## Implementation Tasks

### Task 1: Create DebugManager Autoload
1. Create `autoloads/DebugManager.gd`
2. Implement core state management
3. Add phase preservation logic
4. Connect to PhaseManager signals
5. Add to `project.godot` autoloads

### Task 2: Add Debug Input Handling  
1. Add debug input handling to `scripts/Main.gd._input()`
2. Integrate with DebugManager
3. Ensure proper input event handling order

### Task 3: Create Debug Movement System
1. Extend `scripts/MovementController.gd` with debug overrides
2. Implement unrestricted model selection
3. Add debug-specific drag handling
4. Bypass all movement validation in debug mode

### Task 4: Implement Visual Feedback
1. Create debug overlay UI (`ui/DebugOverlay.tscn`)
2. Enhance `scripts/TokenVisual.gd` with debug styling
3. Connect visual updates to DebugManager signals
4. Test visual state transitions

### Task 5: Integration Testing
1. Test debug mode from all phases
2. Verify state preservation on exit
3. Test model dragging from both armies
4. Validate visual feedback system

### Task 6: Add Input Action (Optional Enhancement)
1. Add `debug_mode_toggle` action to `project.godot`
2. Map to KEY_9 for consistency
3. Update input handling to use action

## Technical Implementation Details

### Phase State Preservation
```gdscript
# DebugManager.enter_debug_mode()
func enter_debug_mode() -> void:
    if PhaseManager.current_phase_instance:
        previous_phase = GameState.get_current_phase()
        previous_phase_instance = PhaseManager.current_phase_instance
        # Don't transition to a new phase, just override behavior
    
    debug_mode_active = true
    emit_signal("debug_mode_changed", true)
    _show_debug_overlay()

# DebugManager.exit_debug_mode()  
func exit_debug_mode() -> void:
    debug_mode_active = false
    emit_signal("debug_mode_changed", false)
    _hide_debug_overlay()
    
    # Phase restoration is automatic since we never changed it
    # Just need to restore normal input handling
```

### Model Selection Algorithm
```gdscript
# Debug-specific model finding
func _find_model_at_position_debug(world_pos: Vector2) -> Dictionary:
    var closest_model = {}
    var closest_distance = INF
    
    # Check ALL models from ALL units (no ownership filtering)
    for unit_id in GameState.state.units:
        var unit = GameState.state.units[unit_id]
        for model in unit.get("models", []):
            var model_pos = Vector2(model.get("position", {}).get("x", 0), 
                                  model.get("position", {}).get("y", 0))
            var distance = world_pos.distance_to(model_pos)
            
            if distance < closest_distance and distance < TOKEN_CLICK_RADIUS:
                closest_distance = distance
                closest_model = {
                    "unit_id": unit_id,
                    "model_id": model.get("id", ""),
                    "model": model,
                    "position": model_pos
                }
    
    return closest_model
```

### Error Handling Strategy
1. **Invalid State Recovery**: If debug mode encounters errors, safely exit to previous phase
2. **Model Position Validation**: Ensure moved positions are within board boundaries  
3. **State Corruption Prevention**: Never modify permanent game state during debug mode
4. **Input Conflict Resolution**: Debug input has highest priority

### Performance Considerations
1. **Minimal Overhead**: Debug systems only active when enabled
2. **Event Filtering**: Use `get_viewport().set_input_as_handled()` to prevent event propagation
3. **Visual Updates**: Only redraw affected tokens, not entire board
4. **Memory Management**: Debug overlay created/destroyed on demand

## Validation Gates

```bash
# Test debug mode toggle
godot --headless -s tests/integration/test_debug_mode.gd

# Test model movement in debug mode  
godot --headless -s tests/unit/test_debug_movement.gd

# Test phase preservation
godot --headless -s tests/unit/test_debug_phase_preservation.gd

# Visual regression test
godot --headless -s tests/integration/test_debug_visuals.gd
```

## External References

- **Godot Input Handling**: https://docs.godotengine.org/en/4.4/tutorials/inputs/index.html
- **Godot Debug Tools**: https://docs.godotengine.org/en/4.4/tutorials/scripting/debug/overview_of_debugging_tools.html  
- **Drag and Drop Best Practices**: https://generalistprogrammer.com/godot/godot-drag-and-drop-tutorial/
- **Warhammer 40k Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/

## Existing Code Patterns

- **Input Handling Pattern**: `scripts/Main.gd:293-331` (existing _input method)
- **Movement Controller Pattern**: `scripts/MovementController.gd:486-630` (drag handling)
- **Phase Management Pattern**: `autoloads/PhaseManager.gd:29-66` (phase transitions)
- **Token Visual Pattern**: `scripts/TokenVisual.gd:11-36` (rendering and state)
- **Autoload Pattern**: `autoloads/SettingsService.gd` (global service structure)

## Success Criteria

- [ ] Press 9 key toggles debug mode from any game phase
- [ ] Can drag any model from either army without restrictions  
- [ ] Visual feedback clearly indicates debug mode is active
- [ ] Debug mode preserves and restores previous phase correctly
- [ ] Model positions update immediately during debug dragging
- [ ] No interference with normal game input/functionality
- [ ] Performance impact is negligible when debug mode is inactive

## Risk Assessment

**Low Risk**:
- Input handling conflicts (well-established patterns exist)
- Visual system integration (existing token system is extensible)

**Medium Risk**:  
- Phase state preservation complexity (requires careful integration with PhaseManager)
- Model selection algorithm performance (mitigated by efficient spatial queries)

**Mitigation Strategies**:
1. Implement debug mode as overlay system rather than new phase
2. Use existing movement infrastructure with validation bypassed
3. Extensive integration testing across all phases
4. Fallback mechanisms for state corruption

## Implementation Order

1. **DebugManager Foundation** - Core state management and API
2. **Input Integration** - Hook into Main.gd input system  
3. **Movement Override** - Extend MovementController for debug behavior
4. **Visual System** - Debug overlay and token highlighting
5. **Integration Testing** - End-to-end functionality validation
6. **Polish & Performance** - Optimization and edge case handling

## Confidence Score: 8/10

**High Confidence Factors**:
- Clear, well-defined requirements
- Solid existing codebase patterns to follow
- Godot has excellent input and visual systems
- Non-intrusive implementation approach

**Risk Factors**:
- Complex integration with existing phase system
- Need to ensure no gameplay state corruption
- Visual feedback must be clear but non-intrusive

The implementation leverages existing systems effectively while maintaining clean separation between debug and production code paths.