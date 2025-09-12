# PRP: Measuring Tape Tool (GitHub Issue #17)

## Overview

Implement a measuring tape tool that allows users to draw measurement lines between two points with distance displayed in inches (Warhammer 40K standard). The tool will be accessible via keyboard shortcut ('t' key) and support multiple persistent measurement lines that can be cleared with another key ('y' key). This tool will be available across all game phases to assist with tactical planning and movement decisions.

**GitHub Issue:** #17 - Measuring Tape  
**Priority:** Medium  
**Estimated Effort:** 3-5 hours  
**Complexity Score:** 7/10

## Context and Requirements

### User Requirements
- Draw a line between two points with length shown in inches
- Available in any phase of the game
- Triggered by holding 't' key and dragging between two points
- Lines remain visible until cleared with 'y' key
- Multiple lines can be visible simultaneously
- Consider saving lines in game save data (assess feasibility)

### Warhammer 40K Context
In tabletop Warhammer 40K, measuring tape is essential for:
- Checking weapon ranges (e.g., 24" for bolters)
- Planning movement distances (e.g., 6" normal move)
- Verifying charge distances (2d6" charge range)
- Ensuring unit coherency (models within 2" of each other)
- Checking objective control (within 3" of objective)

Reference: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/

### Example User Flows

**Creating Measurement:**
1. User holds 't' key → Enters measurement mode
2. User clicks and drags from point A to point B
3. Line appears with distance label (e.g., "12.5"")
4. User releases 't' key → Line persists on screen
5. User can create additional measurements

**Clearing Measurements:**
1. User presses 'y' key → All measurement lines cleared
2. Screen returns to clean state

## Current System Analysis

### Input Handling Architecture

Based on codebase research:

**Main.gd Input Handler (40k/scripts/Main.gd:847+):**
- `_input(event)` function handles all keyboard/mouse input
- Uses pattern: `if event is InputEventKey and event.pressed and event.keycode == KEY_X`
- Mouse dragging handled via `InputEventMouseMotion` and button states
- `get_viewport().set_input_as_handled()` prevents event propagation

**Debug Visualization Pattern (LoSDebugVisual.gd):**
- Extends Node2D with `_draw()` function for custom rendering
- Uses `draw_line()`, `draw_circle()`, `draw_arc()` for visuals
- `queue_redraw()` triggers redraw when data changes
- Temporary visuals with auto-cleanup timers
- Z-index management for layering (z_index = 10 for debug)

### Distance Measurement System

**Measurement.gd Autoload (40k/autoloads/Measurement.gd):**
```gdscript
const PX_PER_INCH: float = 40.0  # Board scale conversion
func distance_inches(pos1: Vector2, pos2: Vector2) -> float
func px_to_inches(pixels: float) -> float
```

### Visual Rendering Patterns

**Line Drawing Examples:**
- LoSDebugVisual.gd: Persistent debug lines with colors
- MovementController.gd: Movement path visualization
- RangeCircle.gd: Range indicators

**Common Pattern:**
```gdscript
extends Node2D
var lines_to_draw: Array = []

func _draw():
    for line_data in lines_to_draw:
        draw_line(line_data.from, line_data.to, line_data.color, line_data.width)
        # Draw distance label
        var mid_point = (line_data.from + line_data.to) / 2
        draw_string(font, mid_point, line_data.label, ...)
```

### Save System Integration

**SaveLoadManager.gd Analysis:**
- Uses `GameState.create_snapshot()` for serialization
- JSON format with nested dictionaries
- Metadata system for additional data
- Custom data can be added to game state

**Persistence Considerations:**
- Adding to save increases file size (minimal for line data)
- Need to handle save version compatibility
- Optional feature - can be toggled in settings

## Implementation Blueprint

### 1. MeasuringTapeManager Autoload

Create new autoload for managing measurement state:

```gdscript
# 40k/autoloads/MeasuringTapeManager.gd
extends Node

signal measurement_added(measurement: Dictionary)
signal measurements_cleared()

var measurements: Array = []  # Array of measurement dictionaries
var is_measuring: bool = false
var measurement_start: Vector2 = Vector2.ZERO
var current_preview: Dictionary = {}  # Preview line while dragging
var save_measurements: bool = false  # Toggle for persistence

func start_measurement(start_pos: Vector2) -> void:
    is_measuring = true
    measurement_start = start_pos
    current_preview = {
        "from": start_pos,
        "to": start_pos,
        "distance": 0.0,
        "timestamp": Time.get_ticks_msec()
    }

func update_measurement(current_pos: Vector2) -> void:
    if not is_measuring:
        return
    
    current_preview.to = current_pos
    current_preview.distance = Measurement.distance_inches(measurement_start, current_pos)

func complete_measurement(end_pos: Vector2) -> void:
    if not is_measuring:
        return
    
    var measurement = {
        "from": measurement_start,
        "to": end_pos,
        "distance": Measurement.distance_inches(measurement_start, end_pos),
        "timestamp": Time.get_ticks_msec()
    }
    
    measurements.append(measurement)
    emit_signal("measurement_added", measurement)
    
    is_measuring = false
    measurement_start = Vector2.ZERO
    current_preview = {}

func clear_all_measurements() -> void:
    measurements.clear()
    emit_signal("measurements_cleared")

func get_save_data() -> Dictionary:
    if not save_measurements:
        return {}
    
    var save_data = []
    for m in measurements:
        save_data.append({
            "from": {"x": m.from.x, "y": m.from.y},
            "to": {"x": m.to.x, "y": m.to.y},
            "distance": m.distance
        })
    
    return {"measuring_tape": save_data}

func load_save_data(data: Dictionary) -> void:
    if not data.has("measuring_tape"):
        return
    
    measurements.clear()
    for m in data.measuring_tape:
        measurements.append({
            "from": Vector2(m.from.x, m.from.y),
            "to": Vector2(m.to.x, m.to.y),
            "distance": m.distance,
            "timestamp": Time.get_ticks_msec()
        })
```

### 2. MeasuringTapeVisual Node

Visual rendering component:

```gdscript
# 40k/scripts/MeasuringTapeVisual.gd
extends Node2D

const LINE_COLOR = Color(0.0, 1.0, 1.0, 0.8)  # Cyan
const LINE_WIDTH = 2.0
const FONT_SIZE = 14
const LABEL_OFFSET = Vector2(10, -10)

var font: Font = preload("res://assets/fonts/default_font.tres")

func _ready() -> void:
    z_index = 15  # Above most game elements
    name = "MeasuringTapeVisual"
    
    # Connect to manager signals
    MeasuringTapeManager.measurement_added.connect(_on_measurement_added)
    MeasuringTapeManager.measurements_cleared.connect(_on_measurements_cleared)

func _draw() -> void:
    # Draw all stored measurements
    for measurement in MeasuringTapeManager.measurements:
        _draw_measurement(measurement)
    
    # Draw preview if measuring
    if MeasuringTapeManager.is_measuring:
        _draw_measurement(MeasuringTapeManager.current_preview, true)

func _draw_measurement(measurement: Dictionary, is_preview: bool = false) -> void:
    var color = LINE_COLOR if not is_preview else Color(1.0, 1.0, 0.0, 0.6)
    var width = LINE_WIDTH if not is_preview else LINE_WIDTH * 0.8
    
    # Draw the line
    draw_line(measurement.from, measurement.to, color, width)
    
    # Draw endpoints
    draw_circle(measurement.from, width * 2, color)
    draw_circle(measurement.to, width * 2, color)
    
    # Draw distance label at midpoint
    var midpoint = (measurement.from + measurement.to) / 2
    var label_text = "%.1f\"" % measurement.distance
    
    # Draw background for label
    var text_size = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
    var label_rect = Rect2(midpoint + LABEL_OFFSET - Vector2(2, text_size.y), text_size + Vector2(4, 4))
    draw_rect(label_rect, Color(0, 0, 0, 0.7))
    
    # Draw the text
    draw_string(font, midpoint + LABEL_OFFSET, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
    
    # Draw ruler ticks every inch along the line
    _draw_ruler_ticks(measurement.from, measurement.to, color, width)

func _draw_ruler_ticks(from: Vector2, to: Vector2, color: Color, width: float) -> void:
    var direction = (to - from).normalized()
    var perpendicular = Vector2(-direction.y, direction.x)
    var total_distance = from.distance_to(to)
    var inches = Measurement.px_to_inches(total_distance)
    
    # Draw tick marks at each inch
    for i in range(1, int(inches)):
        var tick_pos = from + direction * Measurement.inches_to_px(i)
        var tick_size = 5.0 if i % 5 == 0 else 3.0  # Longer ticks every 5 inches
        draw_line(tick_pos - perpendicular * tick_size, tick_pos + perpendicular * tick_size, color, width * 0.5)

func _on_measurement_added(_measurement: Dictionary) -> void:
    queue_redraw()

func _on_measurements_cleared() -> void:
    queue_redraw()

func _process(_delta: float) -> void:
    # Redraw if actively measuring
    if MeasuringTapeManager.is_measuring:
        queue_redraw()
```

### 3. Input Handler Integration

Modify Main.gd to handle measuring tape input:

```gdscript
# Add to Main.gd _ready():
var measuring_tape_visual = preload("res://scripts/MeasuringTapeVisual.gd").new()
$BoardRoot.add_child(measuring_tape_visual)

# Add to Main.gd _input():
# Measuring tape controls
if event is InputEventKey:
    # Start/stop measuring with 't' key
    if event.keycode == KEY_T:
        if event.pressed and not MeasuringTapeManager.is_measuring:
            var mouse_pos = get_viewport().get_mouse_position()
            var world_pos = screen_to_world_position(mouse_pos)
            MeasuringTapeManager.start_measurement(world_pos)
            get_viewport().set_input_as_handled()
        elif not event.pressed and MeasuringTapeManager.is_measuring:
            var mouse_pos = get_viewport().get_mouse_position()
            var world_pos = screen_to_world_position(mouse_pos)
            MeasuringTapeManager.complete_measurement(world_pos)
            get_viewport().set_input_as_handled()
        return
    
    # Clear all measurements with 'y' key
    if event.pressed and event.keycode == KEY_Y:
        MeasuringTapeManager.clear_all_measurements()
        print("Measurements cleared")
        get_viewport().set_input_as_handled()
        return

# Update measurement while dragging
if event is InputEventMouseMotion and MeasuringTapeManager.is_measuring:
    var world_pos = screen_to_world_position(event.position)
    MeasuringTapeManager.update_measurement(world_pos)
```

### 4. Save System Integration (Optional)

Modify GameState to include measuring tape data:

```gdscript
# In GameState.create_snapshot():
if MeasuringTapeManager.save_measurements:
    snapshot["measuring_tape"] = MeasuringTapeManager.get_save_data()

# In GameState.load_from_snapshot():
if data.has("measuring_tape"):
    MeasuringTapeManager.load_save_data(data.measuring_tape)
```

### 5. Settings Integration

Add toggle in SettingsService:

```gdscript
# Add to default settings
"save_measurements": false  # Whether to persist measurement lines in saves
```

## Implementation Tasks

1. **Create MeasuringTapeManager autoload** (40k/autoloads/MeasuringTapeManager.gd)
   - State management for measurements
   - Signal system for UI updates
   - Save/load data methods

2. **Create MeasuringTapeVisual node** (40k/scripts/MeasuringTapeVisual.gd)
   - Custom drawing for measurement lines
   - Distance labels with formatting
   - Ruler tick marks for visual reference

3. **Update Main.gd input handling**
   - Add 't' key hold detection for measurement mode
   - Add 'y' key press for clearing measurements
   - Mouse motion tracking during measurement

4. **Add to autoload configuration** (project.godot)
   - Register MeasuringTapeManager as autoload

5. **Optional: Save system integration**
   - Modify GameState snapshot methods
   - Add settings toggle for persistence

6. **Create unit tests** (40k/tests/unit/test_measuring_tape.gd)
   - Test measurement calculations
   - Test input handling
   - Test save/load if implemented

## Validation Gates

```bash
# Syntax check and formatting
cd 40k
godot --headless --script tests/unit/test_measuring_tape.gd

# Manual testing checklist:
# 1. Hold 't' and drag to create measurement line
# 2. Verify distance shown in inches matches expected
# 3. Create multiple measurement lines
# 4. Press 'y' to clear all lines
# 5. Test in different phases (deployment, movement, shooting)
# 6. Test save/load if persistence implemented
```

## Error Handling Strategy

1. **Invalid positions:** Clamp to board boundaries
2. **Performance:** Limit maximum number of measurements (e.g., 10)
3. **Save compatibility:** Version check for older saves without measurements
4. **Visual overlap:** Semi-transparent lines with different colors for clarity

## Assessment: Save Data Persistence

**Recommendation:** Make persistence optional (disabled by default)

**Pros:**
- Useful for planning complex multi-turn strategies
- Minimal file size impact (~100 bytes per line)
- Existing save system supports custom data

**Cons:**
- Not essential for core gameplay
- Adds complexity to save/load process
- May clutter saves with temporary data

**Implementation:** Add settings toggle, only save if explicitly enabled

## Related Files for Reference

- **40k/scripts/LoSDebugVisual.gd** - Debug line drawing patterns
- **40k/scripts/Main.gd:847+** - Input handling integration point
- **40k/autoloads/Measurement.gd** - Distance calculation utilities
- **40k/autoloads/SaveLoadManager.gd** - Save system integration
- **40k/project.godot** - Autoload registration

## Success Metrics

- Measurements accurate to 0.1" precision
- No performance impact with up to 10 lines
- Clear visual distinction from game elements
- Intuitive keyboard controls
- Clean integration with existing systems

## Confidence Score: 8/10

High confidence due to:
- Clear patterns in existing debug visualization code
- Robust measurement utilities already available
- Well-defined input handling system
- Optional save integration reduces risk

Minor challenges:
- First persistent visual tool (others are temporary)
- Balancing visual clarity with gameplay visibility
- Ensuring proper cleanup on phase transitions