# PRP: Fix Circular Collision Detection for Non-Circular Bases

## Issue Reference
**Priority**: #p1
**Title**: "The circles are back when trying to charge and move even for the caladius (caladius charge issue)"

## Problem Statement
Despite having a comprehensive BaseShape system (CircularBase, RectangularBase, OvalBase) already implemented, many parts of the codebase are still using circular approximations for collision detection and engagement range calculations. This causes incorrect behavior when models with non-circular bases (like the Caladius with an oval base or Battlewagon with a rectangular base) interact with walls, other models, and when checking engagement ranges.

**Symptoms**:
- Circular "halos" appearing around non-circular bases during movement and charging
- Incorrect collision detection with walls and terrain
- Engagement range checks treating oval/rectangular bases as circles
- Models appearing to collide when they shouldn't (or vice versa)

## Context and Research Findings

### Existing Infrastructure (Already Working)
The codebase has a **robust and well-tested** shape system:

1. **Base Shape Classes** (`40k/scripts/bases/`):
   - `BaseShape.gd` (lines 1-60): Abstract base with complete interface
   - `CircularBase.gd` (lines 1-98): Round base with optimized collision
   - `RectangularBase.gd` (lines 1-267): Vehicle bases with SAT collision
   - `OvalBase.gd` (lines 1-243): Elliptical bases with parametric collision

2. **Shape-Aware Functions** (`40k/autoloads/Measurement.gd`):
   - `create_base_shape()` (lines 56-80): ✅ Creates correct shape from model data
   - `models_overlap()` (lines 107-125): ✅ Uses shape collision detection
   - `model_overlaps_wall()` (lines 128-142): ✅ Uses shape-segment collision
   - `model_to_model_distance_px()` (lines 82-102): ✅ Uses shape edge points

3. **Test Coverage**:
   - `test_base_shapes_visual.gd`: Tests shape detection and creation
   - `test_model_overlap.gd`: Tests overlap with mixed shapes
   - `test_non_circular_deployment.gd`: Tests deployment
   - All tests passing ✅

### The Problem (What Needs Fixing)

**Legacy circular functions** are still being used in critical gameplay code:

#### 1. **ChargePhase.gd** - Multiple engagement range checks use circles
   - **Line 479-480**: `_is_unit_in_engagement_range()`
     ```gdscript
     var model_radius = Measurement.base_radius_px(model.get("base_mm", 32))
     var er_px = Measurement.inches_to_px(ENGAGEMENT_RANGE_INCHES)
     ```
   - **Line 497**: Edge distance calculation assumes circles
     ```gdscript
     var edge_distance = model_pos.distance_to(enemy_pos) - model_radius - enemy_radius
     ```
   - **Lines 522-538**: `_is_target_within_charge_range()` - Same circular logic
   - **Lines 636-690**: `_validate_engagement_range_constraints()` - Critical validation uses circles

#### 2. **MovementPhase.gd** - Movement validation uses circles
   - **Lines 1061-1086**: `_is_position_in_engagement_range()` - Circular approximation
   - **Lines 1100-1124**: `_path_crosses_enemy()` - Treats paths as circles
   - **Line 1192**: `_position_intersects_terrain()` - Uses circular radius for expansion

#### 3. **RulesEngine.gd** - Static helper uses circles
   - **Lines 1858-1865**: `is_in_engagement_range()` - Simple circular distance

### Warhammer 40k Rules Context
From https://wahapedia.ru/wh40k10ed/the-rules/core-rules/:
- **Engagement Range**: "Within 1" horizontally" between models
- **Distance Measurement**: "Measure between the closest points of the bases"
- **Base Shapes**: Rules don't specify different mechanics per shape, but accurate measurement requires actual base geometry

## Implementation Blueprint

### Core Approach
Replace all circular-based distance and engagement checks with shape-aware equivalents. The existing `Measurement` functions already provide the correct implementations - we just need to use them consistently.

### Pseudocode Strategy

```
For each engagement range check:
  OLD: Calculate center distance, subtract circular radii
  NEW: Use Measurement.model_to_model_distance_px() with full model data

For each overlap check:
  OLD: Simple circle-circle distance comparison
  NEW: Use Measurement.models_overlap() with full model data

For each wall collision:
  OLD: Point-to-segment with circular expansion
  NEW: Use Measurement.model_overlaps_wall() with shape data

For terrain intersection:
  CURRENT: Expand polygon by circular radius
  NEW: Use proper shape bounds from base_shape.get_bounds()
```

### Step-by-Step Implementation Tasks

#### Task 1: Refactor ChargePhase.gd Engagement Checks

**File**: `40k/phases/ChargePhase.gd`

**Function**: `_is_unit_in_engagement_range()` (lines 465-502)
- Replace circular radius calculations with `Measurement.model_to_model_distance_px()`
- Build complete model dictionaries with base_type and base_dimensions
- Use the shape-aware distance function instead of center-radius approximation

**Function**: `_is_target_within_charge_range()` (lines 504-538)
- Same approach as above
- Ensure all model data (base_type, base_dimensions, position, rotation) is included

**Function**: `_validate_engagement_range_constraints()` (lines 617-694)
- Most critical function for charge validation
- Replace all circular radius logic with shape-aware distance checks
- Pass complete model data to distance functions
- This will fix the "circles showing during charge" issue

**Example Transformation**:
```gdscript
# BEFORE (line 636)
var model_radius = Measurement.base_radius_px(model.get("base_mm", 32))
var edge_distance = final_pos.distance_to(target_pos) - model_radius - target_radius

# AFTER
var model_at_pos = model.duplicate()
model_at_pos["position"] = final_pos
var edge_distance_px = Measurement.model_to_model_distance_px(model_at_pos, target_model)
```

#### Task 2: Refactor MovementPhase.gd Engagement Checks

**File**: `40k/phases/MovementPhase.gd`

**Function**: `_is_position_in_engagement_range()` (lines 1061-1086)
- Create temporary model dict with proposed position
- Use `Measurement.model_to_model_distance_px()` for shape-aware distance
- Compare against engagement range

**Function**: `_path_crosses_enemy()` (lines 1100-1124)
- This is more complex - involves checking if movement path intersects bases
- Options:
  1. Sample points along path and check overlap at each point (simple)
  2. Use line-shape intersection from BaseShape classes (optimal)
- Recommend approach 1 for MVP, approach 2 for future enhancement

**Function**: `_position_intersects_terrain()` (lines 1189-1200)
- Use `base_shape.get_bounds()` instead of circular radius for expansion
- More accurate terrain collision for rectangular/oval bases

#### Task 3: Add Helper Function to Measurement.gd

**File**: `40k/autoloads/Measurement.gd`

Add a convenience function for engagement range checks:
```gdscript
func is_in_engagement_range_shape_aware(model1: Dictionary, model2: Dictionary, er_inches: float = 1.0) -> bool:
	var distance_px = model_to_model_distance_px(model1, model2)
	var er_px = inches_to_px(er_inches)
	return distance_px <= er_px
```

This provides a single, consistent interface for all engagement range checks.

#### Task 4: Update RulesEngine.gd (Optional - Low Priority)

**File**: `40k/autoloads/RulesEngine.gd`

**Function**: `is_in_engagement_range()` (lines 1858-1865)
- This static helper is less used but should be updated for consistency
- Could delegate to `Measurement.is_in_engagement_range_shape_aware()`
- Check all call sites first to ensure no breaking changes

#### Task 5: Verify Model Data Completeness

Ensure all model dictionaries passed to collision functions include:
- `base_mm` (or equivalent dimension)
- `base_type` ("circular", "rectangular", "oval")
- `base_dimensions` (for non-circular: {length: X, width: Y})
- `position` (Vector2 or {x, y})
- `rotation` (float in radians, defaults to 0.0)

Check these locations:
- ChargePhase model queries: `_get_model_in_unit()`
- MovementPhase model queries: `_get_model_in_unit()`
- Any place models are constructed for validation

## Error Handling & Edge Cases

1. **Missing base_type**: `Measurement.create_base_shape()` already defaults to circular
2. **Legacy save files**: Models without rotation default to 0.0 (already handled)
3. **Dictionary vs Vector2 positions**: `Measurement` functions already handle both formats
4. **Dead/destroyed models**: Always check `model.get("alive", true)` before distance checks (already done)
5. **Invalid rotations**: Clamp or normalize rotation values if needed

## Testing Strategy

### Existing Tests to Run (Should Still Pass)
```bash
# Shape overlap tests
godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://40k/tests/unit/test_model_overlap.gd

# Base shape tests
godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://40k/tests/unit/test_base_shapes_visual.gd

# Non-circular deployment
godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://40k/tests/unit/test_non_circular_deployment.gd

# Disembark with shapes
godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://40k/tests/unit/test_disembark_shapes.gd
```

### New Test Cases to Add

Create: `40k/tests/unit/test_engagement_range_shapes.gd`

```gdscript
extends GutTest

# Test engagement range with mixed base shapes
func test_circular_to_oval_engagement_range():
	var infantry = {
		"id": "m1",
		"base_mm": 32,
		"base_type": "circular",
		"position": Vector2(0, 0),
		"rotation": 0.0,
		"alive": true
	}

	var caladius = {
		"id": "m1",
		"base_mm": 170,
		"base_type": "oval",
		"base_dimensions": {"length": 170, "width": 105},
		"position": Vector2(200, 0),  # Position to be within 1" edge-to-edge
		"rotation": 0.0,
		"alive": true
	}

	var distance_inches = Measurement.model_to_model_distance_inches(infantry, caladius)
	assert_lt(distance_inches, 1.0, "Should be in engagement range")

func test_rectangular_to_circular_engagement_range():
	var battlewagon = {
		"id": "m1",
		"base_type": "rectangular",
		"base_dimensions": {"length": 180, "width": 110},
		"position": Vector2(0, 0),
		"rotation": 0.0,
		"alive": true
	}

	var marine = {
		"id": "m1",
		"base_mm": 32,
		"base_type": "circular",
		"position": Vector2(300, 0),
		"rotation": 0.0,
		"alive": true
	}

	var distance_inches = Measurement.model_to_model_distance_inches(battlewagon, marine)
	# Distance should be measured from edge of rectangle to edge of circle
	assert_gt(distance_inches, 0, "Distance should be positive")

func test_rotated_oval_engagement_range():
	var caladius1 = {
		"id": "m1",
		"base_mm": 170,
		"base_type": "oval",
		"base_dimensions": {"length": 170, "width": 105},
		"position": Vector2(0, 0),
		"rotation": 0.0,
		"alive": true
	}

	var caladius2 = caladius1.duplicate()
	caladius2["position"] = Vector2(250, 0)
	caladius2["rotation"] = PI / 2  # 90 degrees

	var distance = Measurement.model_to_model_distance_px(caladius1, caladius2)
	# With rotation, the distance should change
	assert_gt(distance, 0, "Distance should account for rotation")
```

### Manual Testing Checklist

#### Charge Phase Testing
1. ✅ Load Custodes vs Orks (Caladius vs Boyz)
2. ✅ Position Caladius within 12" of Ork unit
3. ✅ Declare charge with Caladius
4. ✅ Roll charge dice
5. ✅ Move Caladius toward target
6. ✅ **Verify NO circular halo appears** (main bug symptom)
7. ✅ Verify charge succeeds when oval base is within 1" of target
8. ✅ Verify charge fails when oval base is NOT within 1" of target
9. ✅ Rotate Caladius 90° and repeat - verify collision detection still works

#### Movement Phase Testing
1. ✅ Move Caladius near a wall
2. ✅ **Verify oval base (not circle) is used for wall collision**
3. ✅ Move Caladius near enemy models
4. ✅ Verify movement stops when actual oval base would overlap enemy
5. ✅ Test with Battlewagon (rectangular) near walls
6. ✅ Verify rectangular base is used for collision, not circle

#### Engagement Range Testing
1. ✅ Position Caladius exactly 1.1" from enemy (edge-to-edge using oval)
2. ✅ Verify NOT in engagement range
3. ✅ Position Caladius exactly 0.9" from enemy
4. ✅ Verify IN engagement range
5. ✅ Repeat with Caladius rotated 45°, 90°, 180°

## Validation Gates

```bash
# 1. Run all existing tests - must pass
cd /Users/robertocallaghan/Documents/claude/godotv2
godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://40k/tests/unit/

# 2. Check for remaining circular approximations
grep -n "base_radius_px" 40k/phases/ChargePhase.gd
grep -n "base_radius_px" 40k/phases/MovementPhase.gd
# Should return no results after fix (or only legitimate circular base cases)

# 3. Verify shape-aware functions are used
grep -n "model_to_model_distance" 40k/phases/ChargePhase.gd
grep -n "models_overlap" 40k/phases/ChargePhase.gd
# Should show multiple uses

# 4. Run new engagement range tests
godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://40k/tests/unit/test_engagement_range_shapes.gd

# 5. Manual gameplay test (scripted)
# Load save with Caladius, attempt charge, verify no circular halo
```

## Implementation Order

Execute in this sequence:

1. **Add helper function to Measurement.gd** (safest, no breaking changes)
   - Add `is_in_engagement_range_shape_aware()`
   - Add any other missing convenience functions

2. **Refactor ChargePhase.gd** (highest priority - main bug)
   - Update `_is_unit_in_engagement_range()`
   - Update `_is_target_within_charge_range()`
   - Update `_validate_engagement_range_constraints()` (CRITICAL)
   - Update `_validate_no_model_overlaps()` if needed

3. **Refactor MovementPhase.gd** (second priority)
   - Update `_is_position_in_engagement_range()`
   - Update `_position_overlaps_other_models()` (verify using shape-aware already)
   - Update `_position_intersects_terrain()`

4. **Create and run engagement range tests**
   - Create `test_engagement_range_shapes.gd`
   - Verify all tests pass

5. **Manual testing with Caladius charge scenario**
   - Test charge movement with oval base
   - Verify no circular halos
   - Test at various rotations

6. **Update RulesEngine.gd** (optional polish)
   - Refactor static `is_in_engagement_range()` if needed

7. **Regression testing**
   - Run full test suite
   - Test with circular bases (marines, orks) to ensure no regression
   - Test with rectangular bases (Battlewagon)
   - Test with oval bases (Caladius)

## Gotchas and Known Issues

1. **Performance**: Shape-aware collision is more expensive than circles
   - Current implementation already uses sampling (24 points for ovals)
   - Performance should be acceptable but monitor in large battles
   - Consider caching shape instances if needed

2. **Rotation handling**: All shape functions expect rotation in radians
   - Verify models have `rotation` field (defaults to 0.0)
   - Ensure rotation is preserved through all validation steps

3. **Model dictionary completeness**: Functions need full model data
   - When creating temporary models for "what-if" positions, ensure all fields are copied
   - Use `.duplicate()` to avoid modifying source data

4. **Path validation complexity**: Checking entire movement path is expensive
   - Current approach checks only endpoints
   - Future enhancement could add mid-path validation

5. **Terrain collision**: Currently uses expanded polygons
   - Shape bounds give better approximation than circles
   - Full shape-polygon intersection would be ideal future enhancement

## References

### Code References
- **Base Shape System**: `/40k/scripts/bases/` (CircularBase.gd, RectangularBase.gd, OvalBase.gd)
- **Measurement Utilities**: `/40k/autoloads/Measurement.gd` (lines 56-152)
- **Charge Phase**: `/40k/phases/ChargePhase.gd` (lines 465-694)
- **Movement Phase**: `/40k/phases/MovementPhase.gd` (lines 1061-1200)
- **Test Patterns**: `/40k/tests/unit/test_model_overlap.gd`

### External References
- **Warhammer 40k Core Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
  - Engagement Range: 1" horizontal between models
  - Distance Measurement: Closest points of bases
- **Godot Geometry2D**: https://docs.godotengine.org/en/4.4/classes/class_geometry2d.html
  - Segment intersection methods (already used in BaseShape classes)

### Previous Related PRPs
- **gh_issue_71_non-circular-models.md**: Initial implementation of BaseShape system
- **gh_issue_91_base-shape-issue.md**: Fixed rendering of non-circular bases
- Both PRPs established the infrastructure this PRP will fully utilize

## Expected Outcomes

After successful implementation:

1. ✅ **No circular halos during charge movement** with non-circular bases
2. ✅ **Accurate collision detection** using actual base shapes
3. ✅ **Correct engagement range** calculations for all base types
4. ✅ **Proper wall collision** with rectangular/oval bases
5. ✅ **All existing tests pass** (no regression)
6. ✅ **New engagement range tests pass**
7. ✅ **Gameplay feels more accurate** to tabletop rules

## Confidence Score

**9/10** - Very high confidence for one-pass implementation

**Reasons for high confidence**:
- ✅ All infrastructure already exists and is tested
- ✅ Clear identification of problem locations (specific line numbers)
- ✅ Existing functions provide correct implementations
- ✅ No new features needed - just consistent usage of existing code
- ✅ Comprehensive test coverage already in place
- ✅ Clear validation gates and manual test procedures
- ✅ Well-understood problem domain (shape collision detection)

**Minor uncertainty**:
- Path crossing validation may need iterative refinement
- Performance impact in large battles (unlikely to be significant)
- Potential edge cases with rotated bases near walls (existing code should handle)

**This PRP should enable successful one-pass implementation with Claude Code.**
