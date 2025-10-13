# Deployment Button Diagnostic Guide

## Issue
The "End Deployment" button does not respond when clicked after all units are deployed.

## Enhanced Logging Added

The following logging has been added to track the button behavior:

### 1. Button Configuration (`update_ui_for_phase()`)
- Logs when button is configured for each phase
- Shows button text, visibility, and disabled state
- **Verification step**: Confirms signal connection succeeded

### 2. Deployment Status Checks (`update_ui()`)
- Logs deployment status before and after button state changes
- Shows `all_units_deployed` result
- Tracks button disabled state changes

### 3. Models Placed Signal (`_on_models_placed_changed()`)
- Logs when signal is received
- Shows post-update button state
- Confirms button text and visibility

### 4. Button Click Handler (`_on_phase_action_pressed()`)
- **CRITICAL**: Will show "⚠️⚠️⚠️ BUTTON WAS ACTUALLY CLICKED" if button press is registered
- Logs current phase, button text, and disabled state
- Includes timestamp

## How to Diagnose

### Step 1: Run the game and check logs

```bash
# Method 1: Use the test script (monitors logs in real-time)
./test_deployment_button.sh

# Method 2: Check logs after playing
./check_latest_log.sh
```

### Step 2: Deploy all units

1. Start a new game
2. Deploy all units for both players
3. Try to click the "End Deployment" button
4. Note what happens (or doesn't happen)

### Step 3: Analyze the logs

Look for these key indicators:

#### ✅ **If Button is Working Correctly:**
```
>>> Main: ⚠️ update_ui() - DEPLOYMENT phase - all_deployed: true
>>> Main: ⚠️ Button state AFTER enable - disabled: false
>>> Main: ⚠️⚠️⚠️ BUTTON WAS ACTUALLY CLICKED ⚠️⚠️⚠️
```

#### ❌ **If Button is Disabled:**
```
>>> Main: ⚠️ update_ui() - DEPLOYMENT phase - all_deployed: true
>>> Main: ⚠️ Button state AFTER enable - disabled: false
>>> [NO CLICK MESSAGE - button might be getting disabled again]
```

#### ❌ **If Signal Not Connected:**
```
>>> Phase button signal connected - is_now_connected: false
>>> [Button click will not trigger handler]
```

#### ❌ **If Click Not Registered:**
```
>>> Main: ⚠️ Button state AFTER enable - disabled: false
>>> [User clicks button but NO "BUTTON WAS ACTUALLY CLICKED" message]
>>> [This means signal not connected or button is intercepted]
```

### Step 4: Manual Log Location

If scripts don't work, manually check:

```bash
# Find the log directory
ls -la "$HOME/Library/Application Support/Godot/app_userdata/40k/logs/"

# View the most recent log
tail -100 "$HOME/Library/Application Support/Godot/app_userdata/40k/logs/debug_YYYYMMDD_HHMMSS.log"

# Search for specific patterns
grep -i "all_deployed\|BUTTON.*CLICKED\|button.*disabled" "$HOME/Library/Application Support/Godot/app_userdata/40k/logs/debug_YYYYMMDD_HHMMSS.log"
```

## Potential Root Causes

Based on the code analysis, here are the most likely issues:

### 1. **Signal Connection Timing Issue**
- `update_ui_for_phase()` connects the signal
- If this is called before button is ready, connection might fail
- **Look for**: `is_now_connected: false` in logs

### 2. **Button Getting Re-Disabled**
- `update_ui()` might be called again after enabling the button
- Something might be calling `phase_action_button.disabled = true` after deployment completes
- **Look for**: Multiple `update_ui()` calls where button goes from enabled→disabled

### 3. **UI Overlay/Z-Index Issue**
- Button might be visible but another UI element is on top
- Click events might be consumed by something else
- **Look for**: Button state shows enabled, but NO click message appears

### 4. **GameState.all_units_deployed() Returns False**
- The deployment check might be failing incorrectly
- **Look for**: `all_deployed: false` even after all units are placed

### 5. **Wrong Button Reference**
- The `@onready var phase_action_button` might not be getting the correct node
- **Look for**: `button_path` showing wrong path or null

## Expected Log Sequence (Working)

When everything works correctly, you should see:

```
1. Main: ========== UPDATE UI FOR PHASE ==========
2. Main: Current phase: DEPLOYMENT
3. Main: Phase button configured - text: 'End Deployment' visible: true disabled: true
4. Main: ⚠️ VERIFICATION - Button connected: true
5. [User deploys last unit]
6. Main: ⚠️ _on_models_placed_changed() called
7. Main: ⚠️ update_ui() - DEPLOYMENT phase - all_deployed: true
8. Main: ⚠️ Button state AFTER enable - disabled: false
9. [User clicks button]
10. Main: ⚠️⚠️⚠️ BUTTON WAS ACTUALLY CLICKED ⚠️⚠️⚠️
11. Main: Ending deployment phase via action system...
```

## Next Steps After Diagnosis

Once you've identified the issue from the logs, report back with:

1. The relevant log entries
2. What behavior you observed
3. Whether the "BUTTON WAS ACTUALLY CLICKED" message appears
4. The value of `all_units_deployed` after placing all units
5. The button connection verification result

This will allow me to pinpoint and fix the exact issue.

## Quick Fix Attempt

If you want to try a quick potential fix, you could try manually triggering the phase end by:

1. Opening the Godot console/debugger
2. Running: `get_node("/root/Main")._on_phase_action_pressed()`

If that works, it confirms the logic is fine but the button signal connection is the issue.
