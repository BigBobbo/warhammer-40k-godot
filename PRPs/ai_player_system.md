# PRP: AI Player System for Warhammer 40K Godot

**Feature**: In-process GDScript AI Player for Single-Player Games
**Status**: Planning
**Confidence Score**: 7/10
**Date**: 2026-02-14

---

## Executive Summary

Add an AI player system that allows a human to play against a computer opponent (or spectate AI vs AI). The AI runs entirely within Godot as GDScript, uses per-action heuristic decision trees, has full board knowledge, is army-agnostic, and handles all game phases. The human player chooses which side they play (Player 1 or Player 2). The AI submits actions through the existing `NetworkIntegration.route_action()` pipeline — identical to how human controllers submit actions.

---

## Table of Contents

1. [Design Decisions](#1-design-decisions)
2. [Architecture Overview](#2-architecture-overview)
3. [File Changes Summary](#3-file-changes-summary)
4. [Detailed Implementation](#4-detailed-implementation)
5. [Phase-by-Phase AI Logic](#5-phase-by-phase-ai-logic)
6. [Task List](#6-task-list)
7. [Validation Gates](#7-validation-gates)
8. [Risks and Mitigations](#8-risks-and-mitigations)
9. [Codebase Reference](#9-codebase-reference)

---

## 1. Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Runtime | In-process GDScript | No external deps, works offline, simpler deployment |
| Difficulty | Single level | Start with competent heuristics; expand later |
| Timing | Fully instant | No artificial delays; fastest game experience |
| Player side | Player chooses | AI fills whichever slot the human doesn't |
| Army support | Army-agnostic | Works with any army loaded by ArmyListManager |
| Board knowledge | Full | AI reads complete GameState; simpler implementation |
| Decision approach | Per-action heuristics | Each action evaluated independently with scoring |
| Phase scope | All phases | Deployment, Command, Movement, Shooting, Charge, Fight, Scoring |
| AI turn visibility | Action log summary | Show text summary of what AI did, not animated playback |
| AI vs AI | Supported | Both players can be AI for testing/spectating |

---

## 2. Architecture Overview

### 2.1 High-Level Data Flow

```
PhaseManager.phase_changed signal (or GameState.state_changed)
    ↓
AIPlayer._on_state_changed()
    ↓
Check: Is active_player an AI player?
    ↓ YES
AIPlayer._begin_ai_turn()
    ↓
Query: PhaseManager.get_available_actions()
    + GameState queries for board analysis
    ↓
AIDecisionMaker.decide(phase, game_state, available_actions)
    ↓
Returns: action Dictionary
    ↓
NetworkIntegration.route_action(action)
    ↓
GameManager processes → diffs applied → state_changed emitted
    ↓
Loop: AIPlayer checks if more actions needed in this phase
    ↓ NO MORE
Phase completes (either auto or via END_* action)
```

### 2.2 Key Design Principle: Signal-Driven, Non-Blocking

The AI **must not** block the main thread. Each action is submitted one at a time, and the AI waits for the `result_applied` signal before deciding its next action. This is critical because:

1. Deployment alternates between players after each unit — the AI must wait for its turn to come back
2. Shooting resolution involves multi-step dice rolling (CONFIRM_TARGETS → APPLY_SAVES)
3. Fight phase alternates between attacker and defender
4. The UI needs time to process state changes between actions

**Implementation**: Use `call_deferred` to schedule AI evaluation after each state change, ensuring the Godot engine completes its current frame processing first.

### 2.3 Component Diagram

```
┌─────────────────────────────────────────────────────────┐
│ AIPlayer.gd (Autoload)                                  │
│                                                         │
│  - Monitors signals: phase_changed, state_changed,      │
│    result_applied                                       │
│  - Checks if active_player is AI                        │
│  - Orchestrates action sequencing per phase             │
│  - Maintains AI action log for summary display          │
│  - Delegates decisions to AIDecisionMaker               │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │ AIDecisionMaker.gd (inner class or separate file) │  │
│  │                                                   │  │
│  │  - Pure logic: no signals, no scene tree access   │  │
│  │  - Takes game state snapshot + available actions   │  │
│  │  - Returns chosen action Dictionary               │  │
│  │  - Phase-specific heuristic methods               │  │
│  │  - Utility scoring functions                      │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## 3. File Changes Summary

### New Files

| File | Purpose |
|------|---------|
| `40k/autoloads/AIPlayer.gd` | Main AI controller autoload — signal monitoring, action sequencing, turn orchestration |
| `40k/scripts/AIDecisionMaker.gd` | Pure decision logic — heuristics, scoring, action selection for each phase |

### Modified Files

| File | Changes |
|------|---------|
| `40k/project.godot` | Add `AIPlayer` to autoload list (after NetworkManager) |
| `40k/scripts/MainMenu.gd` | Add player type dropdowns (Human/AI) for each player |
| `40k/scenes/MainMenu.tscn` | Add Player1Type and Player2Type dropdown UI nodes |
| `40k/scripts/Main.gd` | Initialize AIPlayer with config from GameState.meta on game start |

---

## 4. Detailed Implementation

### 4.1 AIPlayer.gd — The Controller

**Location**: `40k/autoloads/AIPlayer.gd`

This is the orchestration layer. It does NOT contain game logic heuristics — those live in AIDecisionMaker.

```gdscript
extends Node

# Configuration
var ai_players: Dictionary = {}  # player_id -> true/false (is AI)
var enabled: bool = false
var _processing_turn: bool = false  # Guard against re-entrant calls
var _action_log: Array = []  # Log of AI actions for summary display

# Signals for UI
signal ai_turn_started(player: int)
signal ai_turn_ended(player: int, action_summary: Array)
signal ai_action_taken(player: int, action: Dictionary, description: String)

func _ready() -> void:
    # Connect to signals - use call_deferred to avoid acting during signal emission
    GameManager.result_applied.connect(_on_result_applied)
    PhaseManager.phase_changed.connect(_on_phase_changed)

func configure(player_types: Dictionary) -> void:
    """
    Called from Main.gd during initialization.
    player_types: {"1": "HUMAN" or "AI", "2": "HUMAN" or "AI"}
    """
    ai_players.clear()
    for player_id in player_types:
        ai_players[int(player_id)] = (player_types[player_id] == "AI")
    enabled = ai_players.values().has(true)
    print("AIPlayer: Configured - P1=%s, P2=%s, enabled=%s" % [
        player_types.get("1", "HUMAN"), player_types.get("2", "HUMAN"), enabled])

func is_ai_player(player: int) -> bool:
    return enabled and ai_players.get(player, false)

func _on_phase_changed(_new_phase) -> void:
    if not enabled:
        return
    call_deferred("_evaluate_and_act")

func _on_result_applied(_result: Dictionary) -> void:
    if not enabled:
        return
    # After any action result, check if AI should act next
    call_deferred("_evaluate_and_act")

func _evaluate_and_act() -> void:
    if _processing_turn:
        return  # Already processing, avoid re-entrancy

    var active_player = GameState.get_active_player()
    if not is_ai_player(active_player):
        return  # Not AI's turn

    if not PhaseManager.current_phase_instance:
        return  # No active phase

    _processing_turn = true
    _execute_next_action(active_player)
    _processing_turn = false
```

**Key Methods** (pseudocode — see Task List for exact implementation):

```gdscript
func _execute_next_action(player: int) -> void:
    var phase = GameState.get_current_phase()
    var snapshot = GameState.create_snapshot()
    var available = PhaseManager.get_available_actions()

    # Ask decision maker what to do
    var decision = AIDecisionMaker.decide(phase, snapshot, available, player)

    if decision.is_empty():
        push_warning("AIPlayer: No decision made for phase %s" % phase)
        return

    # Ensure player field is set
    decision["player"] = player

    # Log for summary
    _action_log.append({
        "phase": phase,
        "action": decision,
        "description": decision.get("_ai_description", str(decision.type))
    })
    emit_signal("ai_action_taken", player, decision, decision.get("_ai_description", ""))

    # Submit through standard pipeline
    var result = NetworkIntegration.route_action(decision)

    if not result.get("success", false):
        push_error("AIPlayer: Action failed: %s" % result.get("error", "Unknown"))
```

### 4.2 AIDecisionMaker.gd — The Brain

**Location**: `40k/scripts/AIDecisionMaker.gd`

This is a static/utility class with pure functions. No scene tree access, no signals. Takes data in, returns action dictionaries out.

```gdscript
class_name AIDecisionMaker
extends RefCounted

# Constants
const PIXELS_PER_INCH: float = 40.0
const ENGAGEMENT_RANGE_INCHES: float = 1.0
const CHARGE_RANGE_INCHES: float = 12.0
const BOARD_WIDTH_PX: float = 1760.0   # 44 inches
const BOARD_HEIGHT_PX: float = 2400.0  # 60 inches
const DEPLOYMENT_DEPTH_PX: float = 480.0  # 12 inches

static func decide(phase: int, snapshot: Dictionary,
                    available_actions: Array, player: int) -> Dictionary:
    """Main entry point. Returns an action dictionary to submit."""
    match phase:
        GameStateData.Phase.DEPLOYMENT:
            return _decide_deployment(snapshot, available_actions, player)
        GameStateData.Phase.COMMAND:
            return _decide_command(snapshot, available_actions, player)
        GameStateData.Phase.MOVEMENT:
            return _decide_movement(snapshot, available_actions, player)
        GameStateData.Phase.SHOOTING:
            return _decide_shooting(snapshot, available_actions, player)
        GameStateData.Phase.CHARGE:
            return _decide_charge(snapshot, available_actions, player)
        GameStateData.Phase.FIGHT:
            return _decide_fight(snapshot, available_actions, player)
        GameStateData.Phase.SCORING:
            return _decide_scoring(snapshot, available_actions, player)
        _:
            return {}
```

### 4.3 MainMenu.gd Changes

Add player type selection (Human vs AI) for each player.

**New UI nodes** to add to `MainMenu.tscn` (inside `ArmySection`):

```
Player1Container/
  Player1Label: "Player 1 Army:"
  Player1Dropdown: (army selection)
  Player1TypeDropdown: (NEW - "Human" / "AI")

Player2Container/
  Player2Label: "Player 2 Army:"
  Player2Dropdown: (army selection)
  Player2TypeDropdown: (NEW - "Human" / "AI")
```

**New code in MainMenu.gd**:

```gdscript
# Add to @onready vars
@onready var player1_type_dropdown: OptionButton = $MenuContainer/ArmySection/Player1Container/Player1TypeDropdown
@onready var player2_type_dropdown: OptionButton = $MenuContainer/ArmySection/Player2Container/Player2TypeDropdown

var player_type_options = [
    {"id": "HUMAN", "name": "Human"},
    {"id": "AI", "name": "AI"}
]

# In _setup_dropdowns():
for option in player_type_options:
    player1_type_dropdown.add_item(option.name)
    player2_type_dropdown.add_item(option.name)

# In _on_start_button_pressed(), add to config:
config["player1_type"] = player_type_options[player1_type_dropdown.selected].id
config["player2_type"] = player_type_options[player2_type_dropdown.selected].id

# In _initialize_game_with_config():
GameState.state.meta["player1_type"] = config.get("player1_type", "HUMAN")
GameState.state.meta["player2_type"] = config.get("player2_type", "HUMAN")
```

### 4.4 Main.gd Changes

After phase initialization, configure AIPlayer:

```gdscript
# Add after line ~118 (after PhaseManager.transition_to_phase(DEPLOYMENT)):

# Initialize AI Player if configured
if AIPlayer:
    var player_types = {
        "1": GameState.state.meta.get("player1_type", "HUMAN"),
        "2": GameState.state.meta.get("player2_type", "HUMAN")
    }
    AIPlayer.configure(player_types)
```

### 4.5 project.godot Changes

Add AIPlayer autoload after NetworkManager (line 51):

```ini
AIPlayer="*res://autoloads/AIPlayer.gd"
```

---

## 5. Phase-by-Phase AI Logic

### 5.1 DEPLOYMENT Phase

**Goal**: Place all units within the deployment zone, spread across objectives.

**Action sequence for ONE unit**:
1. Pick an undeployed unit (prioritize: characters last, transports before infantry)
2. Calculate formation positions within deployment zone
3. Submit `DEPLOY_UNIT` action
4. Wait — active_player may switch to opponent for alternating deployment
5. When active_player returns to AI, repeat from step 1

**Heuristic: Position Selection**:
```
For each undeployed unit:
  1. Find objectives within or near deployment zone
  2. Calculate centroid position near the closest objective
  3. If no objectives nearby, use center of deployment zone
  4. Add small random offset to avoid stacking
  5. Generate formation positions for all models around centroid
     - Use grid layout with base_mm spacing + 5mm gap
     - Ensure all positions are within deployment zone bounds
```

**Key constraints**:
- Player 1 deployment zone: y in [0, 480] pixels (bottom of board)
- Player 2 deployment zone: y in [1920, 2400] pixels (top of board)
- These are defaults for Hammer & Anvil; other deployment types use `GameState.state.board.deployment_zones`
- All model positions must be within the zone polygon
- Models cannot overlap (check base_mm for radius)

**Action format**:
```gdscript
{
    "type": "DEPLOY_UNIT",
    "unit_id": "U_INTERCESSORS_A",
    "model_positions": [Vector2(200, 200), Vector2(260, 200), Vector2(320, 200), ...],
    "model_rotations": [0.0, 0.0, 0.0, ...],
    "_ai_description": "Deployed Intercessor Squad near Objective 1"
}
```

**When all AI units are deployed**: The phase auto-completes when `_all_units_deployed()` returns true (DeploymentPhase line 663). If the AI finishes deploying before the human, the active_player will stay on the human until they finish. No explicit END_DEPLOYMENT action is needed from the AI during alternating deployment — only `DEPLOY_UNIT` for each unit.

**Edge case — all AI units deployed but human hasn't finished**: AI does nothing; waits for human.

**Edge case — AI has no more units but phase isn't complete**: The `DEPLOY_UNIT` handler in GameManager (line 253-278) handles player switching. If one player has no more undeployed units, it switches to the other player.

### 5.2 COMMAND Phase

**Goal**: Complete battle-shock tests and end the phase.

**Action sequence**:
1. For each unit in `get_available_actions()` with type `BATTLE_SHOCK_TEST`:
   - Submit `BATTLE_SHOCK_TEST` action (dice are rolled automatically by the phase)
2. Submit `END_COMMAND`

**Action format**:
```gdscript
# Battle-shock test (dice auto-rolled by CommandPhase)
{"type": "BATTLE_SHOCK_TEST", "unit_id": "U_INTERCESSORS_A"}

# End command phase
{"type": "END_COMMAND"}
```

**Heuristic**: None needed — just process all required tests then end phase. The CommandPhase handles CP generation and flag clearing automatically in `_on_phase_enter()`.

### 5.3 MOVEMENT Phase

**Goal**: Move units toward objectives and/or into shooting range of enemies.

**Action sequence for ONE unit**:
1. Select a unit that hasn't moved
2. Decide movement mode:
   - **Normal Move**: Default choice
   - **Advance**: If unit has Assault weapons and is far from objectives
   - **Fall Back**: If engaged and unit is ranged-focused
   - **Remain Stationary**: If already on objective or has Heavy weapons
3. Submit `BEGIN_NORMAL_MOVE` (or `BEGIN_ADVANCE`, `BEGIN_FALL_BACK`)
4. For each alive model in the unit:
   - Calculate destination position
   - Submit `SET_MODEL_DEST` with destination
   - Submit `STAGE_MODEL_MOVE`
5. Submit `CONFIRM_UNIT_MOVE`
6. Repeat for next unit
7. Submit `END_MOVEMENT`

**Heuristic: Destination Calculation**:
```
Priority scoring for each unit:
  1. If not holding an objective and an unclaimed objective is within move range:
     → Move toward that objective (highest priority)
  2. If holding an objective:
     → Remain stationary or adjust position slightly
  3. If assault-focused unit and enemies within 12+move inches:
     → Move toward closest enemy (to set up charge)
  4. If ranged unit:
     → Move to maintain optimal shooting distance (stay in range but not in engagement)
  5. Default:
     → Move toward the nearest objective

For multi-model units, move the unit leader toward the target,
then position other models in coherency (within 2" of another model).
```

**Action format**:
```gdscript
# Begin move
{"type": "BEGIN_NORMAL_MOVE", "unit_id": "U_INTERCESSORS_A"}

# Set each model destination
{
    "type": "SET_MODEL_DEST",
    "unit_id": "U_INTERCESSORS_A",
    "model_id": "m1",
    "destination": Vector2(500, 600),  # pixels
    "inches_moved": 5.2
}

# Stage model move (confirms the individual model move)
{
    "type": "STAGE_MODEL_MOVE",
    "unit_id": "U_INTERCESSORS_A",
    "model_id": "m1"
}

# Confirm the entire unit move
{"type": "CONFIRM_UNIT_MOVE", "unit_id": "U_INTERCESSORS_A"}

# After all units, end phase
{"type": "END_MOVEMENT"}
```

**Key constraints**:
- Movement distance: `unit.meta.stats.move` inches (typically 5-14)
- Convert inches to pixels: `inches * 40.0`
- Cannot end within 1" (40px) of enemy models (engagement range) unless charging
- Must maintain unit coherency: every model within 2" (80px) of at least one other model
- If engaged, can only Fall Back (half movement) or Remain Stationary

### 5.4 SHOOTING Phase

**Goal**: Shoot enemies with all eligible units, prioritizing high-value targets.

**Action sequence for ONE unit**:
1. Submit `SELECT_SHOOTER` with unit_id
2. For each ranged weapon the unit has:
   - Evaluate all eligible targets
   - Pick best target based on expected damage
   - Submit `ASSIGN_TARGET` with unit_id, target_id, weapon_id
3. Submit `CONFIRM_TARGETS` — this triggers dice resolution
4. Wait for resolution result
5. If `APPLY_SAVES` is needed (save data returned), submit it
6. If sequential weapon resolution (`CONTINUE_SEQUENCE`), submit it
7. Repeat for next unit
8. Submit `END_SHOOTING`

**Heuristic: Target Selection**:
```
For each weapon, score each eligible target:
  expected_damage = attacks * hit_probability * wound_probability * (1 - save_probability) * damage

  Where:
    hit_probability = (7 - BS) / 6.0   (BS is the required roll, e.g., 3+ → 4/6)
    wound_probability = based on S vs T table from 40K rules
    save_probability = based on target save modified by AP

  Bonus scoring:
    +50% if target is below half strength (finish it off)
    +30% if target is on an objective
    +20% if target is a CHARACTER
    -50% if target is already being shot by another unit

  Pick target with highest score
```

**Action format**:
```gdscript
{"type": "SELECT_SHOOTER", "unit_id": "U_INTERCESSORS_A"}

{
    "type": "ASSIGN_TARGET",
    "unit_id": "U_INTERCESSORS_A",
    "target_id": "U_BOYZ_A",
    "weapon_id": "bolt_rifle"
}

{"type": "CONFIRM_TARGETS"}

# After dice roll, if saves needed:
{"type": "APPLY_SAVES"}

# End phase
{"type": "END_SHOOTING"}
```

### 5.5 CHARGE Phase

**Goal**: Charge assault-focused units into melee range of enemies.

**Action sequence for ONE unit**:
1. Evaluate: should this unit charge? (Is it assault-focused? Are targets in range?)
2. If yes: Submit `DECLARE_CHARGE` with target_ids
3. Wait for `CHARGE_ROLL` result (2D6 automatic)
4. If charge succeeds, submit `APPLY_CHARGE_MOVE` with model positions
5. Submit `COMPLETE_UNIT_CHARGE`
6. If no: Submit `SKIP_CHARGE` for this unit
7. After all units: Submit `END_CHARGE`

**Heuristic: Charge Decision**:
```
Should charge if:
  1. Unit has melee weapons with higher damage than ranged weapons
  2. OR unit has "charged_bonus" type abilities (fights first, extra attacks)
  3. AND at least one enemy within 12" (CHARGE_RANGE_INCHES)
  4. AND expected charge success > 50% (need roll >= distance/inch)

  Expected success: 2D6 average is 7, check distance to nearest target model
  - Distance 2-6": very likely (>70%)
  - Distance 7-9": moderate (40-60%)
  - Distance 10-12": unlikely (<30%)

  Don't charge if:
  - Unit is ranged-focused (e.g., long-range heavy weapons)
  - Unit is already in a strong position on an objective
  - All targets are much tougher than the charging unit
```

**Action format**:
```gdscript
{
    "type": "DECLARE_CHARGE",
    "unit_id": "U_BOYZ_A",
    "target_ids": ["U_INTERCESSORS_A"]
}

# Charge roll is automatic - phase processes it
# If successful, apply move:
{
    "type": "APPLY_CHARGE_MOVE",
    "unit_id": "U_BOYZ_A",
    "model_positions": {
        "m1": Vector2(x, y),
        "m2": Vector2(x, y),
        ...
    }
}

{"type": "COMPLETE_UNIT_CHARGE", "unit_id": "U_BOYZ_A"}

# Or skip:
{"type": "SKIP_CHARGE", "unit_id": "U_BOYZ_A"}

# End phase
{"type": "END_CHARGE"}
```

### 5.6 FIGHT Phase

**Goal**: Resolve melee combat for all engaged units.

The fight phase is more complex because **both players' units fight**, and the order alternates (defender picks first in fights_first, then attacker, etc). The AI needs to handle being asked to select fighters for its units during the opponent's turn phase.

**Action sequence for ONE unit**:
1. Submit `SELECT_FIGHTER` with unit_id
2. Submit `SELECT_MELEE_WEAPON` with best weapon for current targets
3. Submit `PILE_IN` with model movements (move each model up to 3" toward nearest enemy)
4. Submit `ASSIGN_ATTACKS` with attack allocations
5. Submit `CONFIRM_AND_RESOLVE_ATTACKS` — triggers dice resolution
6. Submit `CONSOLIDATE` with model movements (move up to 3" toward nearest enemy)
7. Repeat for next unit in sequence

**Heuristic: Weapon Selection**:
```
Score each melee weapon against current targets:
  expected_damage = attacks * hit_probability * wound_probability * unsaved_probability * damage
  Pick weapon with highest expected_damage
```

**Heuristic: Attack Allocation**:
```
For each attack:
  Allocate to the target model that:
    1. Is most likely to die from this attack (finish off wounded models)
    2. Or is in a high-priority target unit (characters, heavy weapons)
```

**Action format**:
```gdscript
{"type": "SELECT_FIGHTER", "unit_id": "U_BOYZ_A"}

{"type": "SELECT_MELEE_WEAPON", "unit_id": "U_BOYZ_A", "weapon_id": "choppa"}

{
    "type": "PILE_IN",
    "unit_id": "U_BOYZ_A",
    "model_movements": {
        "m1": Vector2(x, y),
        "m2": Vector2(x, y)
    }
}

{
    "type": "ASSIGN_ATTACKS",
    "unit_id": "U_BOYZ_A",
    "assignments": [
        {"attacker_model": "m1", "target_unit": "U_INTERCESSORS_A", "target_model": "m1"},
        {"attacker_model": "m2", "target_unit": "U_INTERCESSORS_A", "target_model": "m2"}
    ]
}

{"type": "CONFIRM_AND_RESOLVE_ATTACKS", "unit_id": "U_BOYZ_A"}

{
    "type": "CONSOLIDATE",
    "unit_id": "U_BOYZ_A",
    "model_movements": {
        "m1": Vector2(x, y),
        "m2": Vector2(x, y)
    }
}
```

### 5.7 SCORING Phase

**Goal**: End the turn.

**Action sequence**: Submit `END_SCORING`. That's it — scoring is automatic.

```gdscript
{"type": "END_SCORING"}
```

---

## 6. Task List

Tasks are ordered for incremental implementation. Each task should be completable independently and testable.

### Task 1: Create AIDecisionMaker.gd — Utility/Scoring Functions

**File**: `40k/scripts/AIDecisionMaker.gd`

Create the decision maker class with all utility functions needed by the heuristics:

```gdscript
class_name AIDecisionMaker
extends RefCounted

# --- Constants ---
const PIXELS_PER_INCH: float = 40.0
const ENGAGEMENT_RANGE_PX: float = 40.0  # 1 inch
const CHARGE_RANGE_PX: float = 480.0     # 12 inches
const COHERENCY_RANGE_PX: float = 80.0   # 2 inches
const BOARD_WIDTH_PX: float = 1760.0
const BOARD_HEIGHT_PX: float = 2400.0

# --- Utility Functions ---

static func inches_to_px(inches: float) -> float:
    return inches * PIXELS_PER_INCH

static func px_to_inches(px: float) -> float:
    return px / PIXELS_PER_INCH

static func get_model_position(model: Dictionary) -> Vector2:
    """Extract Vector2 position from model dictionary."""
    var pos = model.get("position", null)
    if pos == null:
        return Vector2.INF  # Sentinel for "no position"
    if pos is Vector2:
        return pos
    return Vector2(float(pos.get("x", 0)), float(pos.get("y", 0)))

static func get_alive_models(unit: Dictionary) -> Array:
    """Return array of alive models with valid positions."""
    var alive = []
    for model in unit.get("models", []):
        if model.get("alive", true) and model.get("position", null) != null:
            alive.append(model)
    return alive

static func get_unit_centroid(unit: Dictionary) -> Vector2:
    """Average position of all alive models in the unit."""
    var alive = get_alive_models(unit)
    if alive.is_empty():
        return Vector2.INF
    var sum = Vector2.ZERO
    for model in alive:
        sum += get_model_position(model)
    return sum / alive.size()

static func distance_between_units(unit_a: Dictionary, unit_b: Dictionary) -> float:
    """Minimum distance between any two alive models of two units (in pixels)."""
    var min_dist = INF
    for model_a in get_alive_models(unit_a):
        var pos_a = get_model_position(model_a)
        for model_b in get_alive_models(unit_b):
            var pos_b = get_model_position(model_b)
            var dist = pos_a.distance_to(pos_b)
            # Subtract base radii for edge-to-edge distance
            var radius_a = (model_a.get("base_mm", 32) / 2.0) * (40.0 / 25.4)
            var radius_b = (model_b.get("base_mm", 32) / 2.0) * (40.0 / 25.4)
            dist -= (radius_a + radius_b)
            min_dist = min(min_dist, dist)
    return max(0.0, min_dist)

static func get_objectives(snapshot: Dictionary) -> Array:
    """Return array of objective positions as Vector2."""
    var objectives = []
    for obj in snapshot.get("board", {}).get("objectives", []):
        var pos = obj.get("position", null)
        if pos:
            if pos is Vector2:
                objectives.append(pos)
            else:
                objectives.append(Vector2(float(pos.get("x", 0)), float(pos.get("y", 0))))
    return objectives

static func get_units_for_player(snapshot: Dictionary, player: int) -> Dictionary:
    """Return units owned by player."""
    var result = {}
    for unit_id in snapshot.get("units", {}):
        var unit = snapshot.units[unit_id]
        if unit.get("owner", 0) == player:
            result[unit_id] = unit
    return result

static func get_enemy_units(snapshot: Dictionary, player: int) -> Dictionary:
    """Return units NOT owned by player that are alive and deployed."""
    var result = {}
    for unit_id in snapshot.get("units", {}):
        var unit = snapshot.units[unit_id]
        if unit.get("owner", 0) != player:
            var status = unit.get("status", 0)
            if status != GameStateData.UnitStatus.UNDEPLOYED and status != GameStateData.UnitStatus.IN_RESERVES:
                # Check if unit has alive models
                var has_alive = false
                for model in unit.get("models", []):
                    if model.get("alive", true):
                        has_alive = true
                        break
                if has_alive:
                    result[unit_id] = unit
    return result

# Warhammer 40K wound probability table
# Returns probability of wounding based on Strength vs Toughness
static func wound_probability(strength: int, toughness: int) -> float:
    if strength >= toughness * 2:
        return 5.0 / 6.0  # 2+
    elif strength > toughness:
        return 4.0 / 6.0  # 3+
    elif strength == toughness:
        return 3.0 / 6.0  # 4+
    elif strength * 2 <= toughness:
        return 1.0 / 6.0  # 6+
    else:
        return 2.0 / 6.0  # 5+

static func hit_probability(skill: int) -> float:
    """Probability of hitting given BS or WS (e.g., 3 means 3+)."""
    if skill <= 1:
        return 1.0
    if skill >= 7:
        return 0.0
    return (7.0 - skill) / 6.0

static func save_probability(save: int, ap: int) -> float:
    """Probability of passing a save. save is the base value (e.g., 3), ap is positive (e.g., 1 for AP-1)."""
    var modified_save = save + ap
    if modified_save >= 7:
        return 0.0  # Can't save
    if modified_save <= 1:
        return 1.0
    return (7.0 - modified_save) / 6.0

static func expected_damage_per_weapon(weapon: Dictionary, target_unit: Dictionary) -> float:
    """Calculate expected damage from a weapon profile against a target."""
    var attacks = float(weapon.get("attacks", 1))
    var bs = weapon.get("bs", weapon.get("ws", 4))
    var strength = weapon.get("strength", 4)
    var ap = weapon.get("ap", 0)
    var damage = float(weapon.get("damage", 1))

    var toughness = target_unit.get("meta", {}).get("stats", {}).get("toughness", 4)
    var target_save = target_unit.get("meta", {}).get("stats", {}).get("save", 4)

    var p_hit = hit_probability(bs)
    var p_wound = wound_probability(strength, toughness)
    var p_unsaved = 1.0 - save_probability(target_save, ap)

    return attacks * p_hit * p_wound * p_unsaved * damage

static func generate_formation_positions(centroid: Vector2, num_models: int,
                                          base_mm: int, zone_bounds: Dictionary) -> Array:
    """
    Generate grid formation positions around a centroid.
    Returns Array of Vector2 positions.
    zone_bounds: {"min_y": float, "max_y": float, "min_x": float, "max_x": float}
    """
    var positions = []
    var base_radius_px = (base_mm / 2.0) * (PIXELS_PER_INCH / 25.4)
    var spacing = base_radius_px * 2.0 + 10.0  # Base diameter + small gap

    # Grid layout: rows of up to 5 models
    var cols = min(5, num_models)
    var rows = ceili(float(num_models) / cols)

    var start_x = centroid.x - (cols - 1) * spacing / 2.0
    var start_y = centroid.y - (rows - 1) * spacing / 2.0

    for i in range(num_models):
        var row = i / cols
        var col = i % cols
        var pos = Vector2(start_x + col * spacing, start_y + row * spacing)

        # Clamp to zone bounds
        pos.x = clamp(pos.x, zone_bounds.get("min_x", base_radius_px) + base_radius_px,
                       zone_bounds.get("max_x", BOARD_WIDTH_PX - base_radius_px) - base_radius_px)
        pos.y = clamp(pos.y, zone_bounds.get("min_y", base_radius_px) + base_radius_px,
                       zone_bounds.get("max_y", BOARD_HEIGHT_PX - base_radius_px) - base_radius_px)

        positions.append(pos)

    return positions
```

**Implement these additional static methods in AIDecisionMaker**:
- `_decide_deployment()` — See Section 5.1
- `_decide_command()` — See Section 5.2
- `_decide_movement()` — See Section 5.3
- `_decide_shooting()` — See Section 5.4
- `_decide_charge()` — See Section 5.5
- `_decide_fight()` — See Section 5.6
- `_decide_scoring()` — See Section 5.7

### Task 2: Create AIPlayer.gd — Autoload Controller

**File**: `40k/autoloads/AIPlayer.gd`

Implement the full AIPlayer autoload as described in Section 4.1:

- Signal connections: `GameManager.result_applied`, `PhaseManager.phase_changed`, `GameState.state_changed`
- `configure()` method for setup from Main.gd
- `_evaluate_and_act()` with re-entrancy guard
- `_execute_next_action()` that calls `AIDecisionMaker.decide()`
- Action log tracking for summary display
- `ai_turn_started` / `ai_turn_ended` / `ai_action_taken` signals

**Critical implementation detail**: Use `call_deferred("_evaluate_and_act")` in all signal handlers to avoid acting during signal emission chains. This prevents issues where the AI tries to act before the GameState has finished updating.

**Critical implementation detail**: The `_processing_turn` guard must be released even if an error occurs. Use a pattern like:
```gdscript
func _evaluate_and_act() -> void:
    if _processing_turn:
        return
    var active_player = GameState.get_active_player()
    if not is_ai_player(active_player):
        return
    if not PhaseManager.current_phase_instance:
        return
    _processing_turn = true
    _execute_next_action(active_player)
    _processing_turn = false
```

### Task 3: Implement Deployment Decision Logic

**In AIDecisionMaker.gd**, implement `_decide_deployment()`:

```gdscript
static func _decide_deployment(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
    # Filter to DEPLOY_UNIT actions for this player
    var deploy_actions = available_actions.filter(func(a): return a.get("type") == "DEPLOY_UNIT")

    if deploy_actions.is_empty():
        # No units to deploy - check if we can end deployment
        for action in available_actions:
            if action.get("type") == "END_DEPLOYMENT":
                return {"type": "END_DEPLOYMENT"}
        return {}  # Nothing to do (opponent may be deploying)

    # Pick first undeployed unit
    var action_template = deploy_actions[0]
    var unit_id = action_template.get("unit_id", "")
    var unit = snapshot.get("units", {}).get(unit_id, {})

    if unit.is_empty():
        return {}

    # Calculate deployment zone bounds
    var zone_bounds = _get_deployment_zone_bounds(snapshot, player)

    # Calculate centroid near an objective (if any in/near zone)
    var objectives = get_objectives(snapshot)
    var zone_center = Vector2(
        (zone_bounds.min_x + zone_bounds.max_x) / 2.0,
        (zone_bounds.min_y + zone_bounds.max_y) / 2.0
    )

    var best_pos = zone_center
    var best_dist = INF
    for obj_pos in objectives:
        # Find objective closest to deployment zone
        var clamped = Vector2(
            clamp(obj_pos.x, zone_bounds.min_x, zone_bounds.max_x),
            clamp(obj_pos.y, zone_bounds.min_y, zone_bounds.max_y)
        )
        var dist = clamped.distance_to(obj_pos)
        if dist < best_dist:
            best_dist = dist
            best_pos = clamped

    # Generate model positions in formation
    var models = unit.get("models", [])
    var alive_count = 0
    for m in models:
        if m.get("alive", true):
            alive_count += 1

    var base_mm = models[0].get("base_mm", 32) if models.size() > 0 else 32
    var positions = generate_formation_positions(best_pos, models.size(), base_mm, zone_bounds)
    var rotations = []
    for i in range(models.size()):
        rotations.append(0.0)

    return {
        "type": "DEPLOY_UNIT",
        "unit_id": unit_id,
        "model_positions": positions,
        "model_rotations": rotations,
        "_ai_description": "Deployed %s near zone center" % unit.get("meta", {}).get("name", unit_id)
    }

static func _get_deployment_zone_bounds(snapshot: Dictionary, player: int) -> Dictionary:
    """Get deployment zone as min/max bounds."""
    var zones = snapshot.get("board", {}).get("deployment_zones", [])
    for zone in zones:
        if zone.get("player", 0) == player:
            # Zone might be polygon vertices or simple bounds
            var vertices = zone.get("vertices", [])
            if not vertices.is_empty():
                var min_x = INF
                var max_x = -INF
                var min_y = INF
                var max_y = -INF
                for v in vertices:
                    var vx = float(v.get("x", v.x if v is Vector2 else 0))
                    var vy = float(v.get("y", v.y if v is Vector2 else 0))
                    min_x = min(min_x, vx)
                    max_x = max(max_x, vx)
                    min_y = min(min_y, vy)
                    max_y = max(max_y, vy)
                return {"min_x": min_x, "max_x": max_x, "min_y": min_y, "max_y": max_y}

    # Fallback: standard Hammer and Anvil zones
    if player == 1:
        return {"min_x": 40.0, "max_x": 1720.0, "min_y": 10.0, "max_y": 470.0}
    else:
        return {"min_x": 40.0, "max_x": 1720.0, "min_y": 1930.0, "max_y": 2390.0}
```

### Task 4: Implement Command Phase Decision Logic

**In AIDecisionMaker.gd**, implement `_decide_command()`:

```gdscript
static func _decide_command(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
    # First, take any pending battle-shock tests
    for action in available_actions:
        if action.get("type") == "BATTLE_SHOCK_TEST":
            return {
                "type": "BATTLE_SHOCK_TEST",
                "unit_id": action.get("unit_id", ""),
                "_ai_description": "Battle-shock test for %s" % action.get("description", "unit")
            }

    # All tests done, end command phase
    return {"type": "END_COMMAND", "_ai_description": "End Command Phase"}
```

### Task 5: Implement Movement Phase Decision Logic

**In AIDecisionMaker.gd**, implement `_decide_movement()`:

This is the most complex movement logic. The AI needs to handle the multi-step movement sequence (BEGIN → SET_MODEL_DEST → STAGE → CONFIRM) and then END_MOVEMENT.

The `_decide_movement()` method needs to be **stateful-aware**: it must look at the available actions to determine what step of the movement sequence we're in.

```gdscript
static func _decide_movement(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
    # Check if there are units available to move
    var move_actions = available_actions.filter(
        func(a): return a.get("type") in ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "BEGIN_FALL_BACK", "REMAIN_STATIONARY"]
    )

    # If a move is already in progress (SET_MODEL_DEST available), continue it
    var set_dest_actions = available_actions.filter(func(a): return a.get("type") == "SET_MODEL_DEST")
    var confirm_actions = available_actions.filter(func(a): return a.get("type") == "CONFIRM_UNIT_MOVE")

    # Priority 1: If we can confirm a move, do it
    if not confirm_actions.is_empty():
        var action = confirm_actions[0]
        return {
            "type": "CONFIRM_UNIT_MOVE",
            "unit_id": action.get("unit_id", action.get("actor_unit_id", "")),
            "_ai_description": "Confirmed unit move"
        }

    # Priority 2: If no units left to begin moving, end phase
    if move_actions.is_empty() and set_dest_actions.is_empty():
        return {"type": "END_MOVEMENT", "_ai_description": "End Movement Phase"}

    # Priority 3: Begin a new unit movement
    if not move_actions.is_empty():
        return _select_movement_action(snapshot, move_actions, player)

    return {"type": "END_MOVEMENT", "_ai_description": "End Movement Phase"}
```

**Note**: The movement phase action sequence (BEGIN → SET_MODEL_DEST for each model → STAGE_MODEL_MOVE for each model → CONFIRM_UNIT_MOVE) requires multiple round-trips. The `_decide_movement()` method is called once per round-trip. The available_actions from `get_available_actions()` tells the AI what step it's on.

**IMPORTANT**: The `get_available_actions()` implementation for MovementPhase may not return `SET_MODEL_DEST` actions with specific model IDs. The AI may need to construct the action itself by reading the active_moves state from the phase or by iterating through models in the unit. **The implementer should read MovementPhase.gd carefully** (especially the `get_available_actions()` at line ~1570 and the `validate_action` / `process_action` methods for SET_MODEL_DEST and STAGE_MODEL_MOVE) to understand the exact expected action format.

### Task 6: Implement Shooting Phase Decision Logic

**In AIDecisionMaker.gd**, implement `_decide_shooting()`:

Similar multi-step approach — check available_actions to determine what step of shooting we're in.

```gdscript
static func _decide_shooting(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
    var action_types = available_actions.map(func(a): return a.get("type", ""))

    # Step 1: If APPLY_SAVES is available, submit it
    if "APPLY_SAVES" in action_types:
        return {"type": "APPLY_SAVES", "_ai_description": "Applying saves"}

    # Step 2: If CONTINUE_SEQUENCE is available (multi-weapon resolution), continue
    if "CONTINUE_SEQUENCE" in action_types:
        return {"type": "CONTINUE_SEQUENCE", "_ai_description": "Continue weapon sequence"}

    # Step 3: If CONFIRM_TARGETS is available, confirm
    if "CONFIRM_TARGETS" in action_types:
        return {"type": "CONFIRM_TARGETS", "_ai_description": "Confirming shooting targets"}

    # Step 4: If we have a selected shooter, assign targets
    # (Look for ASSIGN_TARGET in available actions)
    if "ASSIGN_TARGET" in action_types:
        return _select_shooting_target(snapshot, available_actions, player)

    # Step 5: Select a new shooter
    var select_actions = available_actions.filter(func(a): return a.get("type") == "SELECT_SHOOTER")
    if not select_actions.is_empty():
        # Pick first available shooter
        var action = select_actions[0]
        return {
            "type": "SELECT_SHOOTER",
            "unit_id": action.get("unit_id", action.get("actor_unit_id", "")),
            "_ai_description": "Selected %s for shooting" % action.get("description", "unit")
        }

    # No shooters left, end phase
    return {"type": "END_SHOOTING", "_ai_description": "End Shooting Phase"}
```

### Task 7: Implement Charge Phase Decision Logic

**In AIDecisionMaker.gd**, implement `_decide_charge()`.

Evaluate which units should charge, declare charges, and handle the multi-step charge sequence.

### Task 8: Implement Fight Phase Decision Logic

**In AIDecisionMaker.gd**, implement `_decide_fight()`.

Handle the alternating fight sequence. The AI needs to act when `current_selecting_player` matches the AI player.

### Task 9: Implement Scoring Phase Decision Logic

**In AIDecisionMaker.gd**, implement `_decide_scoring()`.

Simply returns `{"type": "END_SCORING"}`.

### Task 10: Modify MainMenu.gd and MainMenu.tscn — Add Player Type Selection

**MainMenu.tscn changes**:
- Add `Player1TypeDropdown` (OptionButton) to `Player1Container`
- Add `Player2TypeDropdown` (OptionButton) to `Player2Container`

**MainMenu.gd changes**:
- Add `@onready` references for new dropdowns
- Populate with "Human" / "AI" options in `_setup_dropdowns()`
- Include `player1_type` and `player2_type` in config dictionary
- Store in `GameState.state.meta` during `_initialize_game_with_config()`

### Task 11: Modify Main.gd — Initialize AIPlayer on Game Start

**Main.gd changes**:
- After `PhaseManager.transition_to_phase(DEPLOYMENT)`, call `AIPlayer.configure(player_types)`
- Read player types from `GameState.state.meta.player1_type` and `player2_type`
- Default to "HUMAN" if not set (backward compatibility with saves/direct launch)

### Task 12: Modify project.godot — Register AIPlayer Autoload

Add to `[autoload]` section:
```ini
AIPlayer="*res://autoloads/AIPlayer.gd"
```

Place after NetworkManager (line 51) to ensure all dependencies are ready.

### Task 13: Add AI Action Log Summary Panel

Add a simple UI element to display AI action summaries during/after the AI turn:

- Connect to `AIPlayer.ai_action_taken` signal in Main.gd
- Display action descriptions in the existing `status_label` or a new panel
- Show a brief toast/notification for each AI action (e.g., "AI deployed Intercessor Squad")
- After AI turn ends, show a summary of all actions taken

### Task 14: Testing — AI vs Human Game Verification

Manual testing checklist:
- [ ] Start game with Player 2 as AI, Player 1 as Human
- [ ] Verify AI deploys all its units during deployment phase
- [ ] Verify deployment alternation works correctly
- [ ] Verify AI completes command phase
- [ ] Verify AI moves units during movement phase
- [ ] Verify AI shoots during shooting phase
- [ ] Verify AI handles charge phase (charges or skips)
- [ ] Verify AI handles fight phase
- [ ] Verify AI ends its turn in scoring phase
- [ ] Verify human can play their full turn after AI
- [ ] Verify game progresses through multiple battle rounds
- [ ] Start game with Player 1 as AI, verify AI goes first
- [ ] Start game with both players as AI, verify game plays through
- [ ] Load a saved game, verify AI configuration persists

---

## 7. Validation Gates

Since this is a Godot/GDScript project, validation is primarily manual and through the game's existing test framework.

### Syntax Validation
```bash
# Check GDScript files parse correctly (Godot headless)
cd 40k && godot --headless --check-only --script res://autoloads/AIPlayer.gd
cd 40k && godot --headless --check-only --script res://scripts/AIDecisionMaker.gd
```

### Runtime Validation
```bash
# Run the game and verify no errors in console output
cd 40k && godot --headless --quit-after 5
```

### Functional Validation (Manual)
1. Launch game from MainMenu with Player 2 set to "AI"
2. Observe AI completes deployment phase
3. AI completes full turn cycle (Command → Movement → Shooting → Charge → Fight → Scoring)
4. Human completes their turn
5. Game progresses to battle round 2

---

## 8. Risks and Mitigations

### Risk 1: Movement Action Sequence Complexity
**Risk**: The movement phase requires a specific multi-step action sequence (BEGIN → SET_MODEL_DEST → STAGE_MODEL_MOVE → CONFIRM_UNIT_MOVE) that the `get_available_actions()` method may not fully expose.

**Mitigation**: Read MovementPhase.gd thoroughly. The AI may need to construct actions directly rather than relying solely on `get_available_actions()`. Use `validate_action()` to verify actions before submission.

### Risk 2: Shooting Resolution Multi-Step Flow
**Risk**: The shooting phase has complex multi-step resolution (CONFIRM_TARGETS → dice → APPLY_SAVES → CONTINUE_SEQUENCE). The AI must handle asynchronous results.

**Mitigation**: The signal-driven approach handles this naturally. After each action, the AI re-evaluates available actions and picks the next step. If APPLY_SAVES is available, submit it. If CONTINUE_SEQUENCE is available, submit it.

### Risk 3: Fight Phase Alternating Player Selection
**Risk**: The fight phase allows both players to select fighters in an alternating order. The AI must act during the opponent's fight phase when it's the AI's turn to select.

**Mitigation**: The AI monitors `active_player` via signals. During fight phase, `current_selecting_player` determines who picks next. The AI should check `get_available_actions()` which already accounts for whose selection turn it is.

### Risk 4: Deployment Zone Format Variations
**Risk**: Different deployment types (Hammer & Anvil, Dawn of War, etc.) have different zone shapes stored as polygon vertices.

**Mitigation**: Start with bounding-box approximation for zone bounds. This works for all deployment types (just finds the axis-aligned bounding box of the polygon). Precise polygon containment can be added later.

### Risk 5: Re-entrant Signal Handling
**Risk**: `state_changed` and `result_applied` signals may fire multiple times during a single action, causing the AI to act multiple times.

**Mitigation**: The `_processing_turn` boolean guard prevents re-entrancy. Using `call_deferred` ensures the AI only acts after the current signal chain completes.

### Risk 6: Charge/Fight Model Positioning
**Risk**: APPLY_CHARGE_MOVE and PILE_IN/CONSOLIDATE require specific model positions that satisfy complex geometric constraints (engagement range, coherency, base contact).

**Mitigation**: For initial implementation, use simple "move toward nearest enemy model" logic with a small offset to avoid overlap. If charge movement validation fails, fall back to skipping the charge. The AI doesn't need perfect positioning to be functional — it just needs to be valid.

---

## 9. Codebase Reference

### Key Files to Read Before Implementation

| File | Why | Key Lines |
|------|-----|-----------|
| `40k/autoloads/GameManager.gd` | Action processing pipeline | `apply_action()` L9-35, `process_action()` L37-154, `_delegate_to_current_phase()` L655-675 |
| `40k/autoloads/PhaseManager.gd` | Phase lifecycle, available actions | `transition_to_phase()` L34-86, `get_available_actions()` L318-322, `_on_phase_completed()` L151-165 |
| `40k/autoloads/GameState.gd` | State structure, helper methods | `Phase` enum L7, `UnitStatus` enum L8, `get_active_player()` L206, `get_units_for_player()` L217, `get_unit()` L225 |
| `40k/phases/BasePhase.gd` | Phase interface | `execute_action()` L81-112, `get_available_actions()` L71, `validate_action()` L56 |
| `40k/utils/NetworkIntegration.gd` | Action routing (AI uses this) | `route_action()` L11-88, adds player/timestamp fields |
| `40k/phases/DeploymentPhase.gd` | Deployment actions, zone validation | `get_available_actions()` L620+, `_all_units_deployed()` L697+ |
| `40k/phases/CommandPhase.gd` | Battle-shock tests | `get_available_actions()` L139+, `_on_phase_enter()` L25-49 |
| `40k/phases/MovementPhase.gd` | Movement action sequence | `validate_action()` L82+, `get_available_actions()` L1570+ |
| `40k/phases/ShootingPhase.gd` | Shooting resolution flow | `get_available_actions()` L1205+, `_can_unit_shoot()` L1009+ |
| `40k/phases/ChargePhase.gd` | Charge declaration and resolution | `get_available_actions()` L824+, `_can_unit_charge()` L475+ |
| `40k/phases/FightPhase.gd` | Fight sequencing, alternation | `get_available_actions()` L1364+, `_is_unit_in_combat()` L1479+ |
| `40k/phases/ScoringPhase.gd` | Simple end-turn action | `get_available_actions()` L18-25 |
| `40k/scripts/MainMenu.gd` | Where to add AI selection UI | `_setup_dropdowns()` L54+, `_on_start_button_pressed()` L167+, `_initialize_game_with_config()` L193+ |
| `40k/scenes/MainMenu.tscn` | Scene tree for UI modifications | Player1Container L92-103, Player2Container L104-114 |
| `40k/scripts/Main.gd` | Game initialization, where to init AI | `_ready()` L57+, phase init L114-118 |
| `40k/project.godot` | Autoload registration | `[autoload]` section L22-52 |
| `40k/autoloads/TurnManager.gd` | Turn/phase flow | `_on_phase_completed()` L21-45, `check_deployment_alternation()` L68-93 |

### GameState.state Structure (for AI queries)

```
state.meta.active_player → int (1 or 2) — WHOSE TURN IS IT
state.meta.phase → Phase enum — WHAT PHASE ARE WE IN
state.meta.battle_round → int (1-5) — WHICH ROUND
state.meta.player1_type → "HUMAN" or "AI" (NEW)
state.meta.player2_type → "HUMAN" or "AI" (NEW)

state.units[unit_id].owner → int (1 or 2)
state.units[unit_id].status → UnitStatus enum
state.units[unit_id].meta.name → String
state.units[unit_id].meta.stats → {move, toughness, save, leadership}
state.units[unit_id].meta.keywords → Array[String]
state.units[unit_id].models[i].position → {x, y} or null
state.units[unit_id].models[i].alive → bool
state.units[unit_id].models[i].base_mm → int
state.units[unit_id].models[i].current_wounds → int
state.units[unit_id].flags → {moved, advanced, fell_back, has_shot, etc.}

state.board.objectives → Array of {position: {x, y}, ...}
state.board.deployment_zones → Array of {player: int, vertices: Array}

state.players["1"].cp → int (command points)
state.players["1"].vp → int (victory points)
```

### Action Format Quick Reference

All actions submitted via `NetworkIntegration.route_action(action)`:

```gdscript
# DEPLOYMENT
{"type": "DEPLOY_UNIT", "unit_id": str, "model_positions": Array[Vector2], "model_rotations": Array[float]}
{"type": "PLACE_IN_RESERVES", "unit_id": str, "reserve_type": str}
{"type": "END_DEPLOYMENT"}

# COMMAND
{"type": "BATTLE_SHOCK_TEST", "unit_id": str}
{"type": "END_COMMAND"}

# MOVEMENT
{"type": "BEGIN_NORMAL_MOVE", "unit_id": str}
{"type": "BEGIN_ADVANCE", "unit_id": str}
{"type": "BEGIN_FALL_BACK", "unit_id": str}
{"type": "REMAIN_STATIONARY", "unit_id": str}
{"type": "SET_MODEL_DEST", "unit_id": str, "model_id": str, "destination": Vector2, "inches_moved": float}
{"type": "STAGE_MODEL_MOVE", "unit_id": str, "model_id": str}
{"type": "CONFIRM_UNIT_MOVE", "unit_id": str}
{"type": "END_MOVEMENT"}

# SHOOTING
{"type": "SELECT_SHOOTER", "unit_id": str}
{"type": "ASSIGN_TARGET", "unit_id": str, "target_id": str, "weapon_id": str}
{"type": "CONFIRM_TARGETS"}
{"type": "APPLY_SAVES"}
{"type": "CONTINUE_SEQUENCE"}
{"type": "SKIP_UNIT", "unit_id": str}
{"type": "END_SHOOTING"}

# CHARGE
{"type": "DECLARE_CHARGE", "unit_id": str, "target_ids": Array[str]}
{"type": "CHARGE_ROLL", "unit_id": str}
{"type": "APPLY_CHARGE_MOVE", "unit_id": str, "model_positions": Dictionary}
{"type": "COMPLETE_UNIT_CHARGE", "unit_id": str}
{"type": "SKIP_CHARGE", "unit_id": str}
{"type": "END_CHARGE"}

# FIGHT
{"type": "SELECT_FIGHTER", "unit_id": str}
{"type": "SELECT_MELEE_WEAPON", "unit_id": str, "weapon_id": str}
{"type": "PILE_IN", "unit_id": str, "model_movements": Dictionary}
{"type": "ASSIGN_ATTACKS", "unit_id": str, "assignments": Array}
{"type": "CONFIRM_AND_RESOLVE_ATTACKS", "unit_id": str}
{"type": "CONSOLIDATE", "unit_id": str, "model_movements": Dictionary}
{"type": "END_FIGHT"}

# SCORING
{"type": "END_SCORING"}
```

### External Documentation References

- **Godot 4.4 GDScript**: https://docs.godotengine.org/en/4.4/tutorials/scripting/gdscript/
- **Godot Autoloads**: https://docs.godotengine.org/en/4.4/tutorials/scripting/singletons_autoload.html
- **Godot Signals**: https://docs.godotengine.org/en/4.4/getting_started/step_by_step/signals.html
- **Warhammer 40K 10e Core Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- **40K Wound Table**: S >= 2T → 2+, S > T → 3+, S == T → 4+, S < T → 5+, 2S <= T → 6+

---

## Confidence Score: 7/10

**Why 7 and not higher**:

1. **Movement action sequence complexity** (Risk 1): The multi-step movement flow (BEGIN → SET_MODEL_DEST → STAGE → CONFIRM) may have undocumented constraints in MovementPhase.gd that only surface during implementation. The exact `get_available_actions()` return format for mid-move states needs careful testing.

2. **Charge/Fight model positioning** (Risk 6): Calculating valid positions for charge moves, pile-in, and consolidation requires understanding geometric constraints that are validated by the phase code. Getting this right on the first pass is uncertain.

3. **Fight phase alternation** (Risk 3): The fight phase has complex state with `current_selecting_player`, subphases (FIGHTS_FIRST, REMAINING_COMBATS), and both players' units fighting. Getting the AI to respond correctly at every step requires careful integration with FightPhase.gd's internal state.

4. **Signal timing** (Risk 5): The exact order of signal emissions (result_applied vs state_changed vs phase_changed) may cause unexpected behavior. The `call_deferred` pattern mitigates this, but edge cases may surface.

**Why not lower**:

1. The **architecture is clean and well-understood** — action routing through `NetworkIntegration.route_action()` is identical for AI and human players
2. **`get_available_actions()`** exists on all phases and returns a structured format the AI can parse
3. **Simple phases work immediately**: Command, Scoring, and Deployment are straightforward
4. The **signal-driven approach** is idiomatic Godot and matches how multiplayer already works
5. Each phase is **independently implementable** — if one phase's AI fails, the others still work (can fall back to END_PHASE)
