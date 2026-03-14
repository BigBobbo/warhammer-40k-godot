# AI Creator Web App - Implementation Plan

## Overview
Expand the existing `ai-visualizer/index.html` into a full **AI Creator** web app where users can:
1. Tune all ~130 AI weight parameters via sliders
2. Build custom if/then rules that layer on top of the base AI
3. Save/load named AI profiles (e.g. "Aggressive Orks", "Defensive Guard")
4. Assign different AI profiles per player before a game starts

## Architecture

### Web App (`ai-creator/index.html`)
Single-file HTML app (no server needed). Tabs:

**Tab 1: Parameter Tuner**
- Grouped sliders for all ~130 constants (expand existing visualizer param editor)
- Each slider: name, current value, default value, description tooltip
- Category groups: Objective Weights, Threat Assessment, Efficiency, Faction Aggression, etc.
- "Reset to default" per-param and per-group
- Visual diff indicator showing deviation from default

**Tab 2: Rule Builder**
- Visual if/then rule editor (no code required)
- Condition builder: `IF [phase] AND [condition] THEN [modifier]`
- Available conditions:
  - Phase: Movement, Shooting, Charge, Fight
  - State: round number (gte/lte), VP differential (ahead/behind/by N), units remaining %, enemy distance
  - Unit properties: is_melee_unit, is_vehicle, has_keyword(X), points_cost > N
  - Board state: on_objective, in_cover, enemy_within(N inches), controlling_objective
- Available actions (modifiers):
  - Multiply weight: `WEIGHT_X *= 1.5`
  - Override weight: `WEIGHT_X = 20.0`
  - Add bonus: `WEIGHT_X += 5.0`
  - Priority override: "Always charge if able", "Never fall back", "Prefer shooting over melee"
- Rules have priority ordering (drag to reorder)
- Rules can be enabled/disabled individually

**Tab 3: Profile Manager**
- Save current config (params + rules) as a named profile
- Profile metadata: name, description, faction affinity, playstyle tag (aggressive/defensive/balanced)
- Load/edit/delete/duplicate profiles
- Export profile as JSON file / Import profile from JSON file
- Profiles stored in browser localStorage + exportable as files

**Tab 4: Decision Replay** (existing visualizer functionality preserved)
- Existing timeline/inspector from current visualizer
- Shows how the AI decided with the active profile's settings

### Profile JSON Format
```json
{
  "profile_name": "Aggressive Orks",
  "description": "Rush forward, charge everything, WAAAGH!",
  "faction_affinity": "Orks",
  "playstyle": "aggressive",
  "version": 1,
  "parameters": {
    "FACTION_AGGRESSION_DEFAULT": 1.8,
    "MELEE_AGGRESSION_CHARGE_RANGE_BONUS": 18.0,
    "WEIGHT_UNCONTROLLED_OBJ": 6.0
  },
  "rules": [
    {
      "id": "rule_1",
      "name": "Charge everything in range",
      "enabled": true,
      "priority": 1,
      "conditions": [
        {"type": "phase", "value": "CHARGE"},
        {"type": "enemy_within_inches", "value": 12}
      ],
      "actions": [
        {"type": "multiply", "param": "MELEE_AGGRESSION_CHARGE_RANGE_BONUS", "value": 2.0}
      ]
    }
  ]
}
```

### Godot Integration Changes

**1. AIDecisionMaker.gd:**
- Extend `load_config_overrides()` to load from profile path: `user://ai_profiles/<name>.json`
- Add `load_profile(profile_path: String)` method
- Add `_active_rules: Array` for conditional rules
- Add `evaluate_rules(context: Dictionary) -> Dictionary` that evaluates rule conditions against game state and returns modified param overrides
- Modify `get_param()` priority chain: `rule_overrides (dynamic) → config_overrides (static) → const default`
- Support per-player separate parameter sets via `set_player_overrides(player: int, params: Dictionary, rules: Array)`

**2. AIPlayer.gd:**
- Add `ai_profiles: Dictionary = {}` → `{player_id: profile_data}`
- Modify `configure()` to accept per-player profile paths
- Each AI player gets its own `_config_overrides` and `_active_rules`
- Add `load_player_profile(player: int, profile_path: String)`
- Add `get_available_profiles() -> Array` (scans `user://ai_profiles/`)

**3. Main.gd / Game Setup:**
- Add AI profile selector to game setup UI
- game_config gains: `player1_ai_profile`, `player2_ai_profile`
- Profile dropdown populated from `user://ai_profiles/` directory
- "Default" profile = no overrides (current behavior)

**4. New: ProfileManager.gd (autoload)**
- Scan `user://ai_profiles/` for available profiles
- Validate profile JSON schema
- Copy/manage profiles in user data directory

## Implementation Steps

### Step 1: AI Creator Web App (ai-creator/index.html)
Build the full single-file web app with all 4 tabs: Parameter Tuner (sliders grouped by category with descriptions), Rule Builder (visual if/then editor), Profile Manager (save/load/export/import), and Decision Replay (existing visualizer).

### Step 2: Profile Format & Storage (Godot side)
Create `user://ai_profiles/` directory management. Define profile JSON schema. Add `ProfileManager.gd` autoload for scanning/loading/validating profiles.

### Step 3: AIDecisionMaker Rule Engine
Add rule evaluation to AIDecisionMaker.gd. Extend `get_param()` chain to: rules → overrides → defaults. Build context gathering for rule conditions. Support per-player separate parameter sets.

### Step 4: Per-Player Profile Loading (AIPlayer.gd)
Separate config overrides per player. Load profiles per player on game init. Pass player-specific overrides to AIDecisionMaker on each `decide()` call.

### Step 5: Game Setup UI Integration
Add profile selector dropdown to game setup screen. Show profile summary. Wire into game_config and save/load system.

### Step 6: Decision Export Enhancement
Include active profile name + fired rules in decision log export, visible in the replay tab.
