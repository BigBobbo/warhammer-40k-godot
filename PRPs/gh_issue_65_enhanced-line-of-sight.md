# PRP: Enhanced Line of Sight - Base-to-Any-Point Visibility

## Issue Information
- **Issue Number**: #65
- **Title**: Line of sight not just midpoint
- **Priority**: Enhancement (Core Mechanics)
- **Confidence Score**: 9/10

## Executive Summary
Implement enhanced line of sight checking that follows Warhammer 40k 10th Edition true line of sight rules. Instead of simple midpoint-to-midpoint checking, the system will check visibility from any point on the shooting model's base to any point on the target model's base, including base circumferences. This provides more accurate and gameplay-faithful visibility determination for models with larger bases (5+ inch bases).

## Issue Analysis

### Problem Statement
The current implementation uses simple midpoint-to-midpoint line of sight checking in `RulesEngine._check_line_of_sight()` (line 468). This oversimplifies visibility calculations, especially for larger models where edge-to-edge visibility is crucial for tactical gameplay.

**Current Implementation:**
```gdscript
# RulesEngine.gd:468 - Current simple LoS check
static func _check_line_of_sight(from_pos: Vector2, to_pos: Vector2, board: Dictionary) -> bool:
    # Single line segment check between center points
```

### Warhammer 40k 10th Edition Rules Context
From official sources and community clarification:

**True Line of Sight:** Check from behind the observing model to gain a "model's perspective" view. If any part of a target model (including its base) can be seen from any part of the shooting model, it is considered visible.

**Key Rule:** "A model's base is also part of that model" - bases count for visibility purposes.

**Distance Measurement:** "Distances measured between models are done from base to base or (if a model doesn't have a base) from the closest part of the model to their intended target."

## Current State Analysis

### Existing Foundation Assets

**Line of Sight Infrastructure (LoSDebugVisual.gd:60-115):**
- Complete terrain intersection detection with `_check_line_intersects_terrain()`
- Polygon-based terrain blocking with height categories
- Visual debugging system with intersection point calculation
- Integration with board state and GameState snapshots

**Model Base System (Measurement.gd:20-22):**
```gdscript
func base_radius_px(base_mm: int) -> float:
    return mm_to_px(base_mm) / 2.0
```
- Existing base size tracking in model data (`base_mm` field)
- Conversion utilities for mm to pixels at 40px/inch scale
- Edge-to-edge distance calculations already implemented

**Terrain Integration (TerrainManager.gd:121-134):**
- Robust polygon intersection detection
- Height-based line of sight blocking ("tall" terrain blocks LoS)
- PackedVector2Array polygon handling with Geometry2D integration

**RulesEngine Integration Points:**
- `_check_target_visibility()` (line 427) - Main validation entry point
- `check_benefit_of_cover()` (line 538) - Cover determination system
- Weapon range validation and eligibility checking

### Current Limitations
1. **Single Point Check:** Only checks center-to-center visibility
2. **No Base Awareness:** Ignores model base sizes in visibility calculations  
3. **Missed Tactical Opportunities:** Large models can't utilize base edges for shooting
4. **Inconsistent with Rules:** Doesn't match 10th edition true line of sight

## Technical Approach

### Enhanced Line of Sight Algorithm

The solution implements a **progressive sampling approach** that balances accuracy with performance:

```gdscript
# Enhanced LoS checking with base-aware visibility
static func check_enhanced_line_of_sight(shooter_model: Dictionary, target_model: Dictionary, board: Dictionary) -> Dictionary:
    var shooter_pos = _get_model_position(shooter_model)
    var target_pos = _get_model_position(target_model)
    var shooter_radius = Measurement.base_radius_px(shooter_model.get("base_mm", 32))
    var target_radius = Measurement.base_radius_px(target_model.get("base_mm", 32))
    
    # Progressive sampling: center, edges, then circumference points
    var sample_points = _generate_base_sample_points(shooter_pos, shooter_radius, target_pos, target_radius)
    
    for shooter_point in sample_points.shooter:
        for target_point in sample_points.target:
            if _check_single_line_of_sight(shooter_point, target_point, board):
                return {"has_los": true, "sight_line": [shooter_point, target_point]}
    
    return {"has_los": false, "blocked_by": _get_blocking_terrain(sample_points, board)}
```

### Sampling Strategy

**Phase 1: Center Points (Fast Path)**
```gdscript
# Quick center-to-center check for most common cases
if _check_single_line_of_sight(shooter_center, target_center, board):
    return {"has_los": true, "sight_line": [shooter_center, target_center]}
```

**Phase 2: Edge Points (Tactical Cases)**
```gdscript
# Check 4 cardinal directions on each base edge
var edge_points = [
    shooter_pos + Vector2(shooter_radius, 0),  # Right edge
    shooter_pos + Vector2(-shooter_radius, 0), # Left edge  
    shooter_pos + Vector2(0, shooter_radius),  # Bottom edge
    shooter_pos + Vector2(0, -shooter_radius)  # Top edge
]
```

**Phase 3: Circumference Sampling (Precision Cases)**
```gdscript
# For large bases (>60mm), sample circumference points
if shooter_model.get("base_mm", 32) > 60 or target_model.get("base_mm", 32) > 60:
    var sample_count = 8  # 45-degree increments
    for i in range(sample_count):
        var angle = (i * 2 * PI) / sample_count
        var shooter_circ = shooter_pos + Vector2(cos(angle), sin(angle)) * shooter_radius
        # Check visibility to target circumference points
```

### Performance Optimization

**Intelligent Sampling:**
- Start with center points (85% of cases resolve here)
- Use edge points for medium bases (32-60mm)
- Only use circumference sampling for large bases (>60mm)

**Early Termination:**
- Return immediately on first successful sight line
- Cache terrain intersection results per line segment

**Spatial Optimization:**
- Pre-filter obviously blocked cases using bounding box checks
- Skip terrain pieces that don't intersect the sight corridor

## Implementation Plan

### Phase 1: Core Algorithm (4-6 hours)

**File: `40k/autoloads/EnhancedLineOfSight.gd`** (New)
```gdscript
extends Node

# Main enhanced LoS checking function
static func check_enhanced_visibility(shooter_model: Dictionary, target_model: Dictionary, board: Dictionary) -> Dictionary

# Sample point generation for different base sizes  
static func _generate_base_sample_points(shooter_pos: Vector2, shooter_radius: float, target_pos: Vector2, target_radius: float) -> Dictionary

# Progressive sampling implementation
static func _check_progressive_sampling(sample_points: Dictionary, board: Dictionary) -> Dictionary

# Terrain intersection checking (reuse existing)
static func _check_single_line_of_sight(from: Vector2, to: Vector2, board: Dictionary) -> bool
```

**Integration Points:**
- Extend `RulesEngine._check_line_of_sight()` to use enhanced algorithm
- Add configuration flag for legacy vs enhanced mode
- Integrate with `LoSDebugVisual` for visualization

### Phase 2: RulesEngine Integration (2-3 hours)

**Modify `RulesEngine.gd:468`:**
```gdscript
static func _check_line_of_sight(from_pos: Vector2, to_pos: Vector2, board: Dictionary, shooter_model: Dictionary = {}, target_model: Dictionary = {}) -> bool:
    # Enhanced mode with model data
    if not shooter_model.is_empty() and not target_model.is_empty():
        var result = EnhancedLineOfSight.check_enhanced_visibility(shooter_model, target_model, board)
        return result.has_los
    
    # Fallback to legacy point-to-point for backward compatibility
    return _check_legacy_line_of_sight(from_pos, to_pos, board)
```

**Update `_check_target_visibility()` (line 427):**
- Pass model data to enhanced LoS checking
- Maintain backward compatibility for existing calls
- Add performance metrics logging

### Phase 3: Visual Debug Enhancement (2-3 hours)

**Extend `LoSDebugVisual.gd:60-115`:**
```gdscript
func visualize_enhanced_los(shooter_model: Dictionary, target_model: Dictionary, board: Dictionary) -> void:
    var result = EnhancedLineOfSight.check_enhanced_visibility(shooter_model, target_model, board)
    
    if result.has_los:
        # Draw successful sight line in green
        add_los_line(result.sight_line[0], result.sight_line[1], LOS_COLOR_CLEAR)
        # Draw base circles to show sample areas
        _draw_base_outline(shooter_model, Color.GREEN)
        _draw_base_outline(target_model, Color.GREEN)
    else:
        # Draw blocked attempts in red, show blocking terrain
        _draw_blocked_sight_attempts(result.attempted_lines, result.blocked_by)
        _draw_base_outline(shooter_model, Color.RED)
        _draw_base_outline(target_model, Color.RED)
```

### Phase 4: Performance Optimization (1-2 hours)

**Caching System:**
```gdscript
# Cache terrain intersection results
var _terrain_intersection_cache: Dictionary = {}

func _check_cached_terrain_intersection(from: Vector2, to: Vector2, terrain_id: String) -> bool:
    var key = "%s_%s_%s" % [from, to, terrain_id]
    if _terrain_intersection_cache.has(key):
        return _terrain_intersection_cache[key]
    
    var result = _calculate_terrain_intersection(from, to, terrain_id)
    _terrain_intersection_cache[key] = result
    return result
```

**Adaptive Sampling:**
```gdscript
func _determine_sample_density(distance_inches: float, base_size_mm: int) -> int:
    # Use fewer samples for distant or small targets
    if distance_inches > 24.0 or base_size_mm <= 32:
        return 4  # Cardinal directions only
    elif base_size_mm <= 60:
        return 6  # Include diagonal points
    else:
        return 8  # Full circumference sampling for large bases
```

## Testing Strategy

### Unit Tests (`40k/tests/unit/test_enhanced_line_of_sight.gd`)

**Test Cases:**
```gdscript
func test_center_to_center_visibility():
    # Standard case - should match legacy behavior
    
func test_edge_to_edge_visibility():
    # Large models with blocked centers but clear edges
    
func test_circumference_visibility():
    # Models with 5+ inch bases requiring circumference sampling
    
func test_terrain_blocking():
    # Verify terrain still blocks sight lines correctly
    
func test_performance_scaling():
    # Ensure algorithm scales appropriately with base sizes
```

**Integration Tests (`40k/tests/integration/test_enhanced_visibility_integration.gd`):**
```gdscript
func test_shooting_phase_integration():
    # Verify enhanced LoS works in shooting phase workflow
    
func test_weapon_range_with_enhanced_los():
    # Test weapon range + enhanced visibility combination
    
func test_cover_interaction():
    # Ensure cover system works with enhanced LoS
```

### Visual Validation
- Use `LoSDebugVisual` to verify sight lines match expectations
- Test with different base sizes: 25mm, 32mm, 40mm, 60mm, 80mm+
- Validate against known tactical scenarios from tabletop

### Performance Benchmarks
```gdscript
func benchmark_enhanced_vs_legacy():
    # Compare performance of enhanced vs legacy algorithms
    # Target: <2x performance cost for 95% of cases
    
func benchmark_large_base_scenarios():
    # Test performance with multiple large models
    # Target: <100ms for complex 8-model visibility checks
```

## Validation Gates

### Functionality Validation
```bash
# Run enhanced LoS test suite
cd 40k && godot --headless --script tests/unit/test_enhanced_line_of_sight.gd

# Integration tests  
cd 40k && godot --headless --script tests/integration/test_enhanced_visibility_integration.gd
```

### Performance Validation
```bash
# Performance benchmark suite
cd 40k && godot --headless --script tests/performance/benchmark_enhanced_los.gd
```

### Visual Validation
1. Enable LoS debug mode in shooting phase
2. Test scenarios with large bases vs small bases
3. Verify sight lines show appropriate base-to-base checking
4. Confirm terrain blocking still works correctly

## Risk Assessment

### Technical Risks
- **Performance Impact (Medium):** Enhanced algorithm could slow down shooting phase
  - *Mitigation:* Progressive sampling, caching, early termination
- **Complexity Increase (Low):** More complex debugging and maintenance
  - *Mitigation:* Comprehensive test suite, visual debugging tools

### Gameplay Risks  
- **Rule Accuracy (Low):** Implementation might not perfectly match tabletop
  - *Mitigation:* Reference official 10th edition rules, community validation
- **Balance Changes (Low):** Enhanced LoS might affect game balance
  - *Mitigation:* Configuration flag to enable/disable, extensive testing

## Success Criteria

### Must Have
1. **Functional:** Enhanced LoS correctly identifies base-to-base visibility
2. **Performance:** <2x performance cost vs legacy for 95% of scenarios  
3. **Compatible:** Backward compatibility with existing LoS calls
4. **Visual:** Debug visualization shows base-aware sight lines

### Should Have
1. **Optimized:** Intelligent sampling reduces unnecessary calculations
2. **Configurable:** Option to toggle enhanced vs legacy mode
3. **Tested:** Comprehensive test coverage for edge cases

### Could Have
1. **Analytics:** Performance metrics and usage statistics
2. **Advanced:** Additional sampling strategies for special cases
3. **UI:** User setting to adjust sampling density

## Dependencies and Prerequisites

### Code Dependencies
- `Measurement.gd` - Base size calculations and coordinate conversions
- `RulesEngine.gd` - Core combat and visibility validation systems  
- `LoSDebugVisual.gd` - Visual debugging infrastructure
- `TerrainManager.gd` - Terrain intersection and polygon handling

### External Dependencies
- Godot 4.3+ Geometry2D API for polygon/line intersection
- Existing game state management and model data structures

### Testing Dependencies
- GutTest framework for unit testing
- Performance profiling tools for benchmarking
- Visual debugging for validation

## Implementation Timeline

**Phase 1 (4-6 hours):** Core enhanced LoS algorithm
**Phase 2 (2-3 hours):** RulesEngine integration and compatibility
**Phase 3 (2-3 hours):** Visual debugging enhancement  
**Phase 4 (1-2 hours):** Performance optimization and caching
**Testing (2-3 hours):** Comprehensive test suite and validation

**Total Effort:** 11-17 hours

**Confidence Level:** 9/10 - Well-defined problem with clear technical approach, building on solid existing foundation. Low risk of unexpected complications due to thorough analysis of current codebase patterns.