# Drag Ghost Debug Guide

## Issue: Blade Champion showing 32mm base instead of 40mm

## Debug Logging Added

Comprehensive logging has been added at every step of the ghost creation process:

1. **ChargeController._handle_mouse_down()** (lines 174-181)
   - Logs complete model data from GameState when you click to drag

2. **ChargeController._start_model_drag()** (lines 893-897)
   - Logs model properties being passed to ghost creation

3. **GhostVisual.set_model_data()** (lines 43-50)
   - Logs what data the ghost receives
   - Logs the base shape that gets created

4. **Measurement.create_base_shape()** (lines 61-84)
   - Logs input parameters and shape creation details

## Testing Steps

1. **Start the game**
   ```bash
   cd /Users/robertocallaghan/Documents/claude/godotv2/40k
   godot --path . project.godot
   ```

2. **Load game with Blade Champion**
   - Load a save with Blade Champion deployed, OR
   - Start new game with Adeptus Custodes
   - Deploy Blade Champion

3. **Enter charge phase**
   - Advance through phases to Charge Phase
   - Select unit with Blade Champion
   - Declare and roll charge successfully

4. **Click on Blade Champion to start dragging**
   - This will trigger all the debug logging

5. **Check the debug log file**
   ```bash
   # Logs are at:
   ~/Library/Application Support/Godot/app_userdata/40k/logs/debug_YYYYMMDD_HHMMSS.log

   # Find the latest log:
   ls -lt ~/Library/Application\ Support/Godot/app_userdata/40k/logs/ | head -5

   # Read the latest log:
   tail -100 ~/Library/Application\ Support/Godot/app_userdata/40k/logs/debug_*.log
   ```

## What to Look For in Logs

### Expected Log Sequence (Blade Champion with 40mm base):

```
DEBUG: Clicked on model m1
DEBUG: Retrieved unit from GameState: Blade Champion
DEBUG: Model data from GameState:
  id: m1
  base_mm: 40                    ← SHOULD BE 40
  base_type: NOT SET              ← This is OK (defaults to circular)
  base_dimensions: NOT SET        ← This is OK (not needed for circular)
  rotation: 0.0
  position: {x: ..., y: ...}
  Full model keys: [id, wounds, current_wounds, base_mm, position, alive, status_effects, ...]

Starting drag for model m1
DEBUG: Model base_type: NOT SET
DEBUG: Model base_mm: 40          ← SHOULD BE 40
DEBUG: Model base_dimensions: NOT SET
DEBUG: Model rotation: 0.0

DEBUG GhostVisual.set_model_data() called with data: [...]
  base_type: circular             ← Defaults to circular (correct)
  base_mm: 40                     ← SHOULD BE 40
  base_dimensions: {}

DEBUG Measurement.create_base_shape:
  base_type: circular
  base_mm: 40                     ← SHOULD BE 40
  base_dimensions: {}
  Creating CircularBase with radius: 63.0px (from 40mm)  ← 40mm → 63px radius
```

### Problem Indicators:

If you see any of these, we've found the issue:

1. **GameState has wrong data:**
   ```
   DEBUG: Model data from GameState:
     base_mm: 32    ← WRONG! Should be 40
   ```
   **Solution:** Model data in GameState is incorrect, need to check army loading

2. **Data loss during pass to ghost:**
   ```
   DEBUG: Model base_mm: 40       ← Correct here
   ...
   DEBUG GhostVisual.set_model_data() called with data: [...]
     base_mm: 32                  ← WRONG! Lost during transfer
   ```
   **Solution:** Issue in _start_model_drag passing data

3. **Wrong calculation in Measurement:**
   ```
   DEBUG Measurement.create_base_shape:
     base_mm: 40                  ← Input is correct
     Creating CircularBase with radius: 50.4px  ← WRONG! Should be 63px
   ```
   **Solution:** Bug in mm_to_px conversion

## Base Size Reference

For verification:
- **32mm base** → radius = 50.4px (diameter 100.8px)
- **40mm base** → radius = 63.0px (diameter 126px)
- **60mm base** → radius = 94.5px (diameter 189px)
- **170mm oval** (Caladius) → 267px x 165px

Formula: `radius_px = (base_mm / 25.4) * 40 / 2`

## Caladius Grav-tank Test

After fixing Blade Champion, test Caladius:

```
DEBUG: Model data from GameState:
  base_mm: 170
  base_type: oval                 ← Should be set
  base_dimensions: {length: 170, width: 105}  ← Should be set

DEBUG Measurement.create_base_shape:
  base_type: oval
  base_mm: 170
  base_dimensions: {length: 170, width: 105}
  Creating OvalBase: 267.72px x 165.35px  ← 170mm × 105mm
```

## Next Steps After Testing

1. **Share the debug log output** - Copy the relevant section from the log file
2. **Identify where data is lost/wrong** - Based on the log pattern above
3. **Apply targeted fix** - Once we know where the issue is
4. **Remove debug logging** - After verification

## Common Issues and Solutions

### Issue 1: base_mm not in model data at all
**Symptom:** `base_mm: NOT SET` in GameState logs
**Fix:** Army JSON file is missing base_mm field

### Issue 2: model is a reference that gets modified
**Symptom:** base_mm changes between GameState read and ghost creation
**Fix:** Use `model.duplicate()` when passing to ghost

### Issue 3: Default value being used instead of actual value
**Symptom:** Always see 32mm even when base_mm=40 in GameState
**Fix:** Check Dictionary.get() defaults in the data flow
