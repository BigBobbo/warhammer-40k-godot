# PRP: Fix Phase Desynchronization in Multiplayer

## Problem Statement

When a client tries to end a phase in multiplayer (e.g., clicking "End Shooting Phase"), the action is rejected with "Unknown action type: END_SHOOTING". This occurs because the host and client are in different phases - the client UI shows SHOOTING phase, but the host's PhaseManager has already transitioned to CHARGE phase.

## Root Cause Analysis

### Current Flow (Broken)

**Host Side:**
1. Receives `END_SHOOTING` action from client
2. NetworkManager validates against current phase (SHOOTING) ✓
3. GameManager.process_end_shooting() executes:
   - Calls `_trigger_phase_completion()`
   - Emits `phase_completed` signal on ShootingPhase instance
   - PhaseManager._on_phase_completed() calls `advance_to_next_phase()`
   - **PhaseManager transitions to CHARGE locally**
   - PhaseManager.current_phase_instance = ChargePhase
4. Returns diff: `{"op": "set", "path": "meta.phase", "value": CHARGE}`
5. Broadcasts result to client

**Client Side:**
1. NetworkManager._broadcast_result() receives result
2. GameManager.apply_result() applies diff
3. `GameState.state.meta.phase` = CHARGE ✓
4. **PROBLEM**: PhaseManager is NOT notified!
5. **PhaseManager.current_phase_instance stays as ShootingPhase**
6. **Main.current_phase stays as SHOOTING** (only updated via _on_phase_changed)
7. Client UI still shows "End Shooting Phase" button

**Next Action:**
- Client sends `END_SHOOTING` again
- Host validates against ChargePhase (its current_phase_instance)
- ChargePhase doesn't recognize `END_SHOOTING`
- **Validation FAILS**: "Unknown action type: END_SHOOTING"

### Key Insight

When `GameState.state.meta.phase` is updated via a diff on the client, there's **no mechanism to notify PhaseManager** to transition its `current_phase_instance`. The host transitions correctly because `_trigger_phase_completion()` directly emits the signal locally, but clients only receive a state diff.

## Solution Design

### Approach: Detect Phase Changes in apply_result()

After applying diffs on the client, check if `meta.phase` changed. If so, call `PhaseManager.transition_to_phase()` to synchronize the client's phase instance.

### Implementation Location

**File**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/autoloads/NetworkManager.gd`
**Function**: `_broadcast_result()` (Line ~215-240)

### Changes Required

1. **Before applying diffs**, capture current phase:
   ```gdscript
   var phase_before = game_state.get_current_phase()
   ```

2. **After applying diffs**, check if phase changed:
   ```gdscript
   var phase_after = game_state.get_current_phase()
   if phase_after != phase_before:
       # Phase changed - sync PhaseManager
       var phase_manager = get_node_or_null("/root/PhaseManager")
       if phase_manager:
           phase_manager.transition_to_phase(phase_after)
   ```

### Why This Works

- Host already transitions correctly via `_trigger_phase_completion()`
- Host's diff broadcasts the new phase to clients
- Clients apply the diff to GameState
- NEW: Clients detect the phase change and call `PhaseManager.transition_to_phase()`
- PhaseManager.transition_to_phase() creates new phase instance
- PhaseManager emits `phase_changed` signal
- Main._on_phase_changed() updates UI
- Client and host are now synchronized!

## Implementation Plan

### Step 1: Modify NetworkManager._broadcast_result()

**Location**: `40k/autoloads/NetworkManager.gd:215`

```gdscript
@rpc("authority", "call_remote", "reliable")
func _broadcast_result(result: Dictionary) -> void:
	print("NetworkManager: _broadcast_result received, is_host = ", is_host())
	print("NetworkManager: Result keys: ", result.keys())
	print("NetworkManager: Action type: ", result.get("action_type", "NONE"))

	if is_host():
		return  # Host already applied locally

	# CRITICAL FIX: Capture phase BEFORE applying diffs
	var phase_before = game_state.get_current_phase()
	print("NetworkManager: Phase before applying diffs: ", GameStateData.Phase.keys()[phase_before])

	# Client applies the result (with diffs already computed by host)
	print("NetworkManager: Client applying result with %d diffs" % result.get("diffs", []).size())
	game_manager.apply_result(result)

	# CRITICAL FIX: Check if phase changed after applying diffs
	var phase_after = game_state.get_current_phase()
	print("NetworkManager: Phase after applying diffs: ", GameStateData.Phase.keys()[phase_after])

	if phase_after != phase_before:
		print("NetworkManager: 🔄 Phase changed from ", GameStateData.Phase.keys()[phase_before],
		      " to ", GameStateData.Phase.keys()[phase_after])
		print("NetworkManager: Synchronizing PhaseManager to new phase...")

		var phase_manager = get_node_or_null("/root/PhaseManager")
		if phase_manager:
			# Transition to new phase - this will:
			# 1. Exit old phase instance
			# 2. Create new phase instance
			# 3. Update GameState.set_phase() (already done via diff, but safe to call again)
			# 4. Emit phase_changed signal → Main._on_phase_changed() → UI updates
			phase_manager.transition_to_phase(phase_after)
			print("NetworkManager: ✅ PhaseManager synchronized to ", GameStateData.Phase.keys()[phase_after])
		else:
			push_error("NetworkManager: ERROR - PhaseManager not found for phase sync!")

	# Update phase snapshot so it stays in sync with GameState
	_update_phase_snapshot()

	# Re-emit phase-specific signals for client visual updates
	print("NetworkManager: Client calling _emit_client_visual_updates")
	_emit_client_visual_updates(result)

	print("NetworkManager: Client finished applying result")
```

### Step 2: Add Validation Logging (Optional but Recommended)

**Location**: `40k/autoloads/NetworkManager.gd:validate_action()` (Line ~540-607)

Add more detailed logging when validation fails due to phase mismatch:

```gdscript
func validate_action(action: Dictionary, peer_id: int) -> Dictionary:
	# ... existing code ...

	# Layer 4: Game rules validation (delegate to phase)
	var phase_mgr = get_node("/root/PhaseManager")
	if phase_mgr:
		var phase = phase_mgr.get_current_phase_instance()
		var game_state_phase = game_state.get_current_phase()

		# DIAGNOSTIC: Check for phase mismatch
		if phase:
			var phase_script_path = phase.get_script().resource_path if phase.get_script() else "unknown"
			var expected_phase = GameStateData.Phase.keys()[game_state_phase]
			print("NetworkManager: ⚠️ PHASE SYNC CHECK")
			print("NetworkManager:   GameState phase: ", expected_phase)
			print("NetworkManager:   PhaseManager instance: ", phase_script_path)

		if phase and phase.has_method("validate_action"):
			var phase_validation = phase.validate_action(action)

			# If validation fails, add diagnostic info
			if not phase_validation.valid:
				print("NetworkManager: ❌ Phase validation FAILED")
				print("NetworkManager:   Action type: ", action.get("type"))
				print("NetworkManager:   GameState phase: ", GameStateData.Phase.keys()[game_state_phase])
				if phase:
					print("NetworkManager:   Phase instance type: ", phase.get_script().resource_path)

			return phase_validation

	return {"valid": true}
```

## Validation Plan

### Test Case 1: Single Player (Baseline)
1. Start game in single player mode
2. End deployment phase
3. End command phase
4. End movement phase
5. Click "End Shooting Phase"
6. **Verify**: Phase transitions to CHARGE
7. **Verify**: UI shows "End Charge Phase" button

### Test Case 2: Multiplayer - Host
1. Start multiplayer game as host
2. Complete deployment, command, movement phases
3. Click "End Shooting Phase"
4. **Verify**: Phase transitions to CHARGE
5. **Verify**: UI shows "End Charge Phase" button
6. **Verify**: No error in logs

### Test Case 3: Multiplayer - Client (THE CRITICAL TEST)
1. Start multiplayer game as client
2. Complete deployment (alternating with host)
3. When it's your turn:
   - End command phase ✓
   - End movement phase ✓
   - Click "End Shooting Phase"
4. **BEFORE FIX**: Gets error "Unknown action type: END_SHOOTING", button doesn't work
5. **AFTER FIX**:
   - Phase transitions to CHARGE
   - UI updates to show "End Charge Phase" button
   - No validation errors in logs
   - Client and host stay synchronized

### Test Case 4: Multiple Phase Transitions
1. Start multiplayer game
2. Go through entire turn sequence: DEPLOYMENT → COMMAND → MOVEMENT → SHOOTING → CHARGE → FIGHT → SCORING
3. **Verify**: Both client and host stay synchronized through all transitions
4. **Verify**: No "Unknown action type" errors

### Validation Commands

```bash
# Start headless test server
export PATH="$HOME/bin:$PATH"
cd /Users/robertocallaghan/Documents/claude/godotv2/40k

# Run unit tests
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

# Run integration tests (includes phase transitions)
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration -gexit

# Check debug logs for phase sync
tail -f "/Users/robertocallaghan/Library/Application Support/Godot/app_userdata/40k/logs/debug_*.log" | grep -E "Phase|END_SHOOTING|validation"
```

## Code References

### Key Files

- **NetworkManager.gd:215-240** - _broadcast_result() function (NEEDS FIX)
- **NetworkManager.gd:540-607** - validate_action() function (ADD LOGGING)
- **GameManager.gd:376-380** - process_end_shooting() (WORKING CORRECTLY)
- **GameManager.gd:570-580** - _trigger_phase_completion() (HOST ONLY)
- **PhaseManager.gd:32-85** - transition_to_phase() (WILL BE CALLED BY FIX)
- **PhaseManager.gd:149-163** - _on_phase_completed() (HOST ONLY)
- **Main.gd:2530-2555** - _on_phase_changed() (NEEDS TO BE CALLED ON CLIENT)

### Similar Patterns in Codebase

- **MULTIPLAYER_STATE_SYNC_PATTERN.md** - Documents state sync patterns
- **ISSUE_102_COMPLETION_SUMMARY.md** - Previous multiplayer sync fix
- **gh_issue_89_multiplayer_*.md** - Multiple PRPs about multiplayer sync

## Edge Cases to Consider

1. **Phase changes during action processing**
   - Example: Shooting phase ends, but client is still processing save rolls
   - Solution: Phase snapshot is updated, but active phase UI stays stable

2. **Race conditions**
   - Multiple clients sending END_PHASE simultaneously
   - Solution: Host processes sequentially, only active player's action succeeds

3. **Network lag**
   - Phase transition broadcast delayed
   - Solution: Validation will fail gracefully, client retries

4. **Load game in different phase**
   - Saved game loaded in CHARGE phase
   - Solution: SaveLoadManager already handles phase sync via snapshot

## Success Criteria

- [ ] Client can successfully end shooting phase in multiplayer
- [ ] No "Unknown action type: END_SHOOTING" errors
- [ ] Client PhaseManager stays synchronized with host
- [ ] Main UI updates correctly when phase changes
- [ ] All phase transitions work (DEPLOYMENT → COMMAND → MOVEMENT → SHOOTING → CHARGE → FIGHT → SCORING)
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Manual multiplayer testing passes

## Implementation Score: 9/10

**Confidence Level**: Very High

**Reasoning**:
- Root cause clearly identified
- Solution is minimal and targeted
- Follows existing patterns in codebase
- Low risk of side effects
- Easy to test and validate

**Risk**: Minor - Could have edge cases with rapid phase transitions, but the existing phase snapshot mechanism should handle it.
