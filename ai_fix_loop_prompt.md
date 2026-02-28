# AI vs AI Competitive Improvement Loop

You are one iteration of an automated improvement loop. Your job is to:
1. Fix any stalls or bugs preventing games from completing all 5 rounds
2. Improve each AI to play competitively — maximize its OWN score while minimizing its opponent's
3. Ensure secondary objectives are working and being scored
4. Run one or more AI vs AI games and report structured results

Be EXTREMELY verbose in your logging — every observation, hypothesis, and action should be logged.

## CRITICAL RULE: Competitive AI Only

Each AI (Adeptus Custodes and Orks) must play to WIN. Every improvement you make must:
- Maximize that army's own VP score (primary + secondary objectives)
- Minimize the opponent's scoring opportunities (deny objectives, kill scoring units, screen key areas)
- NEVER make an AI "help" the opponent score (e.g. don't move units onto objectives the opponent needs)
- NEVER make both AIs cooperatively inflate scores — they must be adversarial

If one army is consistently losing, improve THAT army's strategy rather than weakening the winner.

## Step 0: Read context from previous iterations

Read `AI_STALL_FIXES.md` if it exists — it contains notes from previous iterations. Do NOT repeat fixes already documented there. Build on what was learned.

Read `ai_loop_tracker.json` if it exists — it contains the win/loss/VP tracking across all iterations. Understand what has already been achieved and what still needs work.

Also check `ai_loop_status.txt` for the last iteration's result.

## Step 1: Check army configuration

Player 1 army must be **Adeptus Custodes** (NOT "A C Test").
Player 2 army must be **Orks** (NOT "ORK Test").

Find where army names are configured for test/AI mode and verify they are correct. Fix if wrong.

## Step 2: Investigate and improve BEFORE launching

Before running a game, look at what previous iterations identified as problems and:

### If games are stalling:
- Fix the stall first (see Common Stall Patterns below)

### If games complete but scores are low:
- Analyze why VP is low — are primary objectives being scored? Secondary?
- Check if the AI actively moves to capture/hold objectives
- Check if the AI selects and pursues secondary missions effectively
- Improve objective-seeking behavior for the underperforming army

### If one army never wins:
- Study that army's specific strengths (Custodes = elite few models, high damage; Orks = many models, board control)
- Improve that army's strategy to leverage its strengths
- Do NOT nerf the winning army — improve the losing one

### Secondary objectives specifically:
- Search for secondary mission/objective related code
- Check if the AI has logic to SELECT secondary objectives wisely
- Check if the AI has logic to PURSUE and SCORE secondary objectives during gameplay
- Check if secondary objectives are being presented and tracked during the game
- If secondary objectives are broken or missing AI support, fix them

## Step 3: Launch a game

```bash
export PATH="$HOME/bin:$PATH"
godot --path /Users/robertocallaghan/Documents/claude/godotv2/40k --test-mode --ai-vs-ai --deployment=search_and_destroy > /tmp/godot_ai_output.txt 2>&1 &
```

Record the PID so you can kill it later.

## Step 4: Monitor for stalls

Wait 60 seconds for the game to get going, then check if the debug log is still growing by comparing line counts 10 seconds apart. The debug log will be the newest file matching:
`/Users/robertocallaghan/Library/Application Support/Godot/app_userdata/40k/logs/debug_20*.log`

If the line count stops increasing, the game has stalled.

Also periodically check if the godot process is still running — if it crashed, that's different from a stall.

## Step 5: Diagnose a stall

1. Read the LAST 50 lines of the debug log to see what phase/action the game stopped on
2. Read the LAST 200 lines of `/tmp/godot_ai_output.txt` for print() output including errors, warnings, and "No decision made" or "No available actions" messages
3. The stall pattern is always: the game is waiting for an action that the AI never submits. Find which action type is expected by tracing the phase code.

## Common stall patterns
- A phase emits a signal (e.g. epic_challenge_opportunity, katah_stance_required) expecting a response, but AIPlayer.gd has no handler for that signal. Fix: connect to the signal in `_connect_phase_stratagem_signals()` and add a handler that submits the appropriate action via `_submit_reactive_action()`.
- `get_available_actions()` in a phase file doesn't offer an action type that the game is waiting for. Fix: add the missing action to `get_available_actions()` and add handling in the corresponding `AIDecisionMaker._decide_*` method.
- An action fails validation (check `/tmp/godot_ai_output.txt` for "Action failed" errors) and AIPlayer has no recovery logic. Fix: add a fallback in `_execute_next_action()` error handling that sends a SKIP or DECLINE action so the game can continue.

## Key files
- `40k/autoloads/AIPlayer.gd` — AI controller, signal connections, action submission
- `40k/scripts/AIDecisionMaker.gd` — decision logic per phase
- `40k/phases/FightPhase.gd` — fight phase actions and signals
- `40k/phases/ChargePhase.gd` — charge phase actions and signals
- `40k/phases/CommandPhase.gd` — command phase, secondary objective selection
- `40k/autoloads/NetworkIntegration.gd` — action routing
- Look for any files related to secondary missions/objectives

## Step 6: Fix and relaunch

After fixing code:
1. Kill the old game process
2. Relaunch with the same command
3. Monitor again
4. Repeat until the game completes all 5 rounds

## Step 7: Extract game results

After each completed game, extract these metrics from the debug log and `/tmp/godot_ai_output.txt`:

1. **Winner**: Which player won (or draw)
2. **Player 1 (Custodes) VP**: Total victory points scored
3. **Player 2 (Orks) VP**: Total victory points scored
4. **Units destroyed**: Total units destroyed across both sides
5. **Secondary objectives**: Were any scored? How many per player?

Search for patterns like:
- "Victory Points", "VP", "score", "final score"
- "UNIT DESTROYED", "Model killed", "models destroyed", "casualties"
- "secondary", "objective scored", "mission"
- "winner", "game over", "Round 5"

## Step 8: Run multiple games if time permits

If the game completes successfully and you still have context budget, run additional games to gather more data points. Each game provides evidence of whether the AI is competitive.

## Step 9: Write results

Update `AI_STALL_FIXES.md` with:
- Date and iteration context
- What you investigated
- What bugs you found
- What you fixed (with file names and line numbers)
- Game results for each game played this iteration
- What still needs fixing (if anything)
- Competitive analysis: is one army dominant? What could the losing army do better?

Write structured results to `ai_loop_status.txt` using this EXACT format (one line per game played, then a summary line):

```
GAME: winner=<P1|P2|DRAW> p1_vp=<number> p2_vp=<number> kills=<number> p1_secondaries=<number> p2_secondaries=<number>
GAME: winner=<P1|P2|DRAW> p1_vp=<number> p2_vp=<number> kills=<number> p1_secondaries=<number> p2_secondaries=<number>
SUMMARY: <brief description of what was fixed/improved this iteration>
```

If the game stalled or crashed instead of completing:
```
STALL: <phase where it stalled> — <what was attempted>
SUMMARY: <brief description>
```

Use 0 for any metric you couldn't extract from logs.

## IMPORTANT REMINDERS
- Be extremely verbose in your logging. Print every hypothesis, every file you read, every grep result.
- Do NOT claim something is working without evidence from actual game output.
- Kill any leftover godot processes before AND after your work.
- If you make code changes, always relaunch and verify they work.
- COMPETITIVE PLAY: Never improve one AI in a way that benefits the opponent. Each army fights to win.
- The goal is BOTH armies being strong enough to win games and score 60+ VP with 5+ kills. Improve the weaker army, don't weaken the stronger one.
