# AI vs AI Stall Fixes (2026-02-26)

## Problem
AI vs AI games would stall during the Fight Phase, preventing completion of all 5 rounds.

## Root Causes Found

### Stall 1: ASSIGN_ATTACKS fails — "Units are not within engagement range"
**File:** `40k/scripts/AIDecisionMaker.gd` (line ~9528)

The AI's `_assign_fight_attacks()` method would find no enemies in engagement range, then fall back to targeting ALL enemies. This caused the FightPhase to reject the ASSIGN_ATTACKS action with "Units are not within engagement range". With no error recovery, the AI would re-evaluate and hit the same dead end forever.

**Fix:** When no enemies are in engagement range, return a CONSOLIDATE action instead of falling back to all enemies. This lets the fighter skip attacks and move on.

### Stall 2: SELECT_FIGHTER fails — "Unit not in engagement range"
**File:** `40k/phases/FightPhase.gd` (line ~2069)

The fight_sequence is built at the start of the fight phase based on which units are in engagement range. But as units fight, enemies can be destroyed or consolidate away. When the FightPhase offers SELECT_FIGHTER for a unit whose enemies are all gone, the validation fails. With no error recovery, the game stalls.

**Fix (root cause):** In `get_available_actions()`, before offering a unit as SELECT_FIGHTER, check if it's still in combat. Skip units that are no longer in engagement range and advance the fight index past them.

**Fix (safety net):** In `AIPlayer._execute_next_action()`, added error recovery for failed SELECT_FIGHTER that sends END_FIGHT to unstick the game.

### Stall 3: Failed ASSIGN_ATTACKS with no recovery
**File:** `40k/autoloads/AIPlayer.gd` (line ~1147)

The error recovery in `_execute_next_action()` handled failed DEPLOY_UNIT, APPLY_CHARGE_MOVE, and SHOOT, but not ASSIGN_ATTACKS. A failed fight attack had no fallback.

**Fix:** Added error recovery for failed ASSIGN_ATTACKS that sends CONSOLIDATE so the game can continue to the next fighter.

## Files Modified
- `40k/scripts/AIDecisionMaker.gd` — Return CONSOLIDATE when no enemies in engagement range instead of targeting unreachable enemies
- `40k/phases/FightPhase.gd` — Skip disengaged units in `get_available_actions()` fight sequence
- `40k/autoloads/AIPlayer.gd` — Added error recovery for failed SELECT_FIGHTER and ASSIGN_ATTACKS

## Test Results
- 4 consecutive successful runs completing all 5 rounds
- Fixes confirmed triggered in logs: "skipping attacks — will consolidate" and "Skipping from fight sequence — no longer in engagement range"
- Adeptus Custodes vs Orks, search_and_destroy deployment
