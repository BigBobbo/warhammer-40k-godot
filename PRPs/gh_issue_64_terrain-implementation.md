# PRP: Terrain Implementation for Warhammer 40k Game

## Issue Context
GitHub Issue #64: Add terrain to the battlefield to limit line of sight and provide cover. Implement terrain layout 2 from Chapter Approved with all terrain features classified as "Ruins".

## Research Findings

### Existing Codebase Architecture
1. **Board System**:
   - Board dimensions: 44"x60" (1760x2400 pixels) - 40px per inch
   - Visual board rendered in `BoardVisual.gd:1-29`
   - Board state managed in `BoardState.gd` (legacy) and `GameState.gd`

2. **Line of Sight Infrastructure**:
   - `RulesEngine.gd:_check_target_visibility()` checks weapon range and calls `_check_line_of_sight()`
   - `RulesEngine.gd:_check_line_of_sight()` has placeholder for terrain checking
   - Already checks for "obscuring" terrain type
   - `_segment_intersects_polygon()` function exists but needs implementation

3. **Visual Systems**:
   - Deployment zones use `Polygon2D` for area visualization (`DeploymentZoneVisual.gd:1-26`)
   - Z-index layering: Board (-10), Deployment Zones (-5), Models (0+)
   - Shooting phase has LoS visualization using Line2D

4. **Collision Detection**:
   - Model placement checks for overlaps (`DeploymentController.gd:_overlaps_with_existing_models()`)
   - Unit coherency checking exists

### Terrain Rules (Wahapedia)
Reference: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#Terrain-Features-1
Layout Reference: https://wahapedia.ru/wh40k10ed/the-rules/chapter-approved-2025-26/#Terrain-Layouts

**Terrain Layout 2 Components**:
- 4x pieces: 6" x 4" area terrain
- 2x pieces: 10" x 5" area terrain  
- 6x pieces: 12" x 6" area terrain
- All classified as "Ruins" terrain type

**Ruins Rules**:
1. **Cover**: Models within or behind ruins gain Benefit of Cover (+1 to saving throws against ranged attacks)
2. **Obscuring**: Blocks line of sight if terrain is 5" or taller
3. **Movement**: Infantry can move through walls, other units must go around
4. **True Line of Sight**: Can shoot through windows/gaps if line can be drawn

## Implementation Blueprint

### Phase 1: Core Terrain System

#### 1. Data Structure
```gdscript
# In GameState.gd or new TerrainManager.gd autoload
var terrain_features: Array = [
    {
        "id": "terrain_1",
        "type": "ruins",  # All terrain for MVP is ruins
        "polygon": PackedVector2Array([...]),  # Boundary points
        "height_category": "tall",  # "tall" (>5"), "medium" (2-5"), "low" (<2")
        "position": Vector2(x, y),
        "can_move_through": {
            "INFANTRY": true,
            "VEHICLE": false,
            "MONSTER": false
        }
    }
]
```

#### 2. Terrain Layout Definition
```gdscript
# New file: autoloads/TerrainLayouts.gd
const LAYOUT_2 = {
    "name": "Chapter Approved Layout 2",
    "features": [
        # 6" x 4" ruins (4 pieces)
        {"size": Vector2(240, 160), "positions": [Vector2(400, 600), ...]},
        # 10" x 5" ruins (2 pieces)  
        {"size": Vector2(400, 200), "positions": [Vector2(880, 400), ...]},
        # 12" x 6" ruins (6 pieces)
        {"size": Vector2(480, 240), "positions": [Vector2(200, 1200), ...]}
    ]
}
```

#### 3. Visual Representation
```gdscript
# New file: scripts/TerrainVisual.gd
extends Node2D

var terrain_pieces: Array = []

func _ready():
    z_index = -8  # Above board, below deployment zones
    
func add_terrain_piece(terrain_data: Dictionary):
    var piece = Polygon2D.new()
    piece.polygon = terrain_data.polygon
    piece.color = Color(0.4, 0.35, 0.3, 0.7)  # Semi-transparent brown
    
    # Add border for clarity
    var border = Line2D.new()
    border.points = terrain_data.polygon
    border.closed = true
    border.width = 2.0
    border.default_color = Color(0.3, 0.25, 0.2, 1.0)
    
    add_child(piece)
    piece.add_child(border)
```

#### 4. Line of Sight Implementation
```gdscript
# Update in RulesEngine.gd
static func _segment_intersects_polygon(seg_start: Vector2, seg_end: Vector2, poly: Array) -> bool:
    # Use Godot's Geometry2D for intersection testing
    var polygon_packed = PackedVector2Array(poly)
    
    for i in range(polygon_packed.size()):
        var edge_start = polygon_packed[i]
        var edge_end = polygon_packed[(i + 1) % polygon_packed.size()]
        
        if Geometry2D.segment_intersects_segment(
            seg_start, seg_end, edge_start, edge_end
        ):
            return true
    
    return false

static func _check_line_of_sight(from_pos: Vector2, to_pos: Vector2, board: Dictionary) -> bool:
    var terrain = board.get("terrain_features", [])
    
    for terrain_piece in terrain:
        # Check if terrain blocks LoS (tall ruins)
        if terrain_piece.get("height_category") == "tall":
            if _segment_intersects_polygon(from_pos, to_pos, terrain_piece.polygon):
                # Check if both models are outside the terrain
                if not _point_in_polygon(from_pos, terrain_piece.polygon) and \
                   not _point_in_polygon(to_pos, terrain_piece.polygon):
                    return false
    
    return true
```

#### 5. Cover System
```gdscript
# Add to RulesEngine.gd
static func check_benefit_of_cover(target_pos: Vector2, shooter_pos: Vector2, board: Dictionary) -> bool:
    var terrain = board.get("terrain_features", [])
    
    for terrain_piece in terrain:
        if terrain_piece.type != "ruins":
            continue
            
        # Target within terrain gets cover
        if _point_in_polygon(target_pos, terrain_piece.polygon):
            return true
            
        # Target behind terrain (LoS crosses terrain)
        if _segment_intersects_polygon(shooter_pos, target_pos, terrain_piece.polygon):
            return true
    
    return false
```

#### 6. Movement Through Terrain
```gdscript
# Add to MovementController.gd validation
func _is_valid_move_position(unit_id: String, model_pos: Vector2) -> bool:
    var unit = GameState.get_unit(unit_id)
    var keywords = unit.meta.keywords
    
    # Check terrain traversal
    for terrain in GameState.terrain_features:
        if _segment_intersects_polygon(current_pos, model_pos, terrain.polygon):
            # Infantry can move through ruins
            if "INFANTRY" in keywords:
                continue
            # Others must go around
            else:
                return false
    
    return true
```

### Phase 2: UI and Interaction

#### 1. Terrain Toggle
```gdscript
# Add to HUD
var terrain_visibility_button: Button
terrain_visibility_button.text = "Toggle Terrain"
terrain_visibility_button.toggled.connect(_on_terrain_visibility_toggled)
```

#### 2. Cover Indicators
```gdscript
# Visual feedback for units in cover
func show_cover_indicator(unit_id: String):
    var icon = Sprite2D.new()
    icon.texture = preload("res://icons/cover_icon.png")
    # Position above unit
```

### Testing Strategy

#### Unit Tests
```gdscript
# tests/unit/test_terrain.gd
func test_line_of_sight_blocked_by_tall_terrain()
func test_infantry_can_move_through_ruins()
func test_vehicles_cannot_move_through_ruins()
func test_benefit_of_cover_within_terrain()
func test_benefit_of_cover_behind_terrain()
```

#### Integration Tests  
```gdscript
# tests/integration/test_terrain_integration.gd
func test_shooting_with_terrain_blocking()
func test_movement_with_terrain_obstacles()
func test_terrain_layout_2_setup()
```

## Implementation Tasks (in order)

1. **Create TerrainManager autoload**
   - Define terrain data structure
   - Implement Layout 2 configuration
   - Add terrain to board state

2. **Implement TerrainVisual rendering**
   - Create Polygon2D-based terrain pieces
   - Add to scene with proper z-ordering
   - Style to differentiate from deployment zones

3. **Update RulesEngine line of sight**
   - Implement `_segment_intersects_polygon()`
   - Update `_check_line_of_sight()` to use terrain
   - Add `_point_in_polygon()` helper

4. **Add cover system**
   - Implement `check_benefit_of_cover()`
   - Integrate with shooting resolution
   - Apply +1 save modifier when in cover

5. **Update movement validation**
   - Check terrain traversal rules
   - Block non-infantry from moving through walls
   - Update pathfinding visualization

6. **Add UI elements**
   - Terrain visibility toggle
   - Cover status indicators
   - Update unit info panels

7. **Testing**
   - Write comprehensive unit tests
   - Integration testing with existing systems
   - Manual playtesting of Layout 2

## Validation Gates

```bash
# Check Godot project loads without errors
$HOME/bin/godot --headless --path 40k --script tests/unit/test_terrain.gd

# Run terrain-specific tests
$HOME/bin/godot --headless --path 40k --script tests/integration/test_terrain_integration.gd

# Verify no regression in existing tests
$HOME/bin/godot --headless --path 40k --script tests/run_all_tests.gd
```

## Files to Reference
- `40k/autoloads/RulesEngine.gd` - Line of sight logic
- `40k/autoloads/BoardState.gd` - Board state management
- `40k/scripts/BoardVisual.gd` - Board rendering
- `40k/scripts/DeploymentZoneVisual.gd` - Example of Polygon2D usage
- `40k/scripts/ShootingController.gd` - Shooting UI and targeting
- `40k/scripts/MovementController.gd` - Movement validation
- `40k/autoloads/GameState.gd` - Game state management

## External References
- Ruins rules: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#Terrain-Features-1
- Terrain layouts: https://wahapedia.ru/wh40k10ed/the-rules/chapter-approved-2025-26/#Terrain-Layouts
- Godot Geometry2D: https://docs.godotengine.org/en/4.4/classes/class_geometry2d.html
- Godot Polygon2D: https://docs.godotengine.org/en/4.4/classes/class_polygon2d.html

## Potential Gotchas
1. **Coordinate System**: Ensure terrain polygons use board coordinates (pixels), not inches
2. **Z-ordering**: Terrain must render above board but below models
3. **Save/Load**: Terrain state must be serialized with game saves
4. **Performance**: Large polygons may impact collision detection - consider spatial partitioning if needed
5. **True LoS**: Windows/gaps in terrain require additional logic (Phase 2 enhancement)

## Success Criteria
- [ ] Terrain Layout 2 renders correctly on board
- [ ] Line of sight is blocked by tall terrain (>5")
- [ ] Units in/behind terrain receive Benefit of Cover
- [ ] Infantry can move through ruins, vehicles cannot
- [ ] Shooting phase correctly applies cover saves
- [ ] All existing tests still pass
- [ ] Save/load preserves terrain state

## Confidence Score: 8/10

The implementation path is clear with existing patterns to follow. The main complexity is in polygon intersection math, but Godot provides helpers. The RulesEngine already has hooks for terrain, making integration straightforward.