# AI Gameplay Visualizer — Web App Plan

## Context & Problem

The game has a sophisticated AI system (~15,500 lines in `AIDecisionMaker.gd` alone, plus ~2,500 lines in `AIPlayer.gd`, `AIAbilityAnalyzer.gd`, and `AIDifficultyConfig.gd`) that makes hundreds of tactical decisions per game. Currently, users can only see brief action summaries via in-game overlays (`AIActionLogOverlay`, `AITurnSummaryPanel`, `AITurnReplayPanel`). The decision-making process — **why** the AI chose a specific target, movement position, charge, etc. — is completely opaque. Users who want to understand, tune, or improve the AI have no way to do so without reading 15,000+ lines of GDScript.

## Research Findings

### What exists in other games:

1. **XCOM 2 Behavior Tree Visualizer** ([SterlingVix/xcom2ai](https://github.com/SterlingVix/xcom2ai)) — An open-source web app that parses XCOM 2's `.ini` config files into an interactive tree view. XCOM uses a utility-based scoring system similar to this game (rating each ability for each alien based on offensive/defensive/intangible benefits). This is the closest precedent to what we're building.

2. **Dave Mark's Utility AI / IAUS** ([gameai.com](https://www.gameai.com/iaus.php)) — Dave Mark, author of *Behavioral Mathematics for Game AI*, built the Infinite Axis Utility System which uses response curves to map inputs to utility scores. His GDC talks demonstrate how modular, data-driven design lets designers construct AI behavior packages in minutes. His "clearing house" concept — a central place to query game data in normalized form — is relevant for our decision log export.

3. **Unreal Engine Visual Logger** — UE's built-in debugging tool lets developers record and replay AI decisions frame-by-frame, showing utility scores and behavior tree state. This is developer-only and engine-integrated.

4. **Chess Engine Parameter Tuning** ([Optuna Game Parameter Tuner](https://github.com/fsmosca/Optuna-Game-Parameter-Tuner)) — Exposes engine evaluation weights (piece values, pruning margins, reduction factors) and auto-tunes them via the Optuna optimization framework.

5. **Tabletop Games (TAG) Framework** ([tabletopgames.ai](https://tabletopgames.ai/wiki/games/creating/game_tuning.html)) — Provides an `ITunableParameters` interface for game parameter optimization. Directly relevant as a precedent for exposing tabletop game AI parameters.

6. **Total War: Warhammer** — Despite a large modding community, no mod exists that visualizes AI decision-making. Mods like "AI Army Tasks and Strategy" modify behavior but don't explain it. Creative Assembly has published blog posts about their "Desired Attitudes" system (faction aggression scoring), which is remarkably similar to our `FACTION_AGGRESSION_*` constants.

7. **MATLAB Real-Time Parameter Tuning** — Provides slider/knob/toggle UIs for live parameter adjustment, which is the gold standard for interactive tuning interfaces.

### Key insight:
**No one has built a user-facing AI decision transparency web app for a turn-based tactical game.** This would be genuinely novel. The closest precedent is the XCOM 2 behavior tree visualizer, but that only shows the behavior structure, not runtime decisions or scoring. What we're proposing goes further: showing every decision with full score breakdowns AND letting users tune parameters.

### This game's AI architecture:

- **Utility-based scoring system** — every possible action is scored numerically, highest score wins
- **Phase-based decision routing** — `AIDecisionMaker.decide()` dispatches to 12+ phase-specific functions:
  - Formations, Deployment, Redeployment, Scout, Roll-Off, Command, Movement, Shooting, Charge, Fight, Scoring
- **~120 tunable constants** in logical groups:
  - Focus fire (3 constants)
  - Weapon-target efficiency matching (9 constants)
  - Weapon keyword scoring (3 constants)
  - Range-band optimization (3 constants)
  - Firing position weights (4 constants)
  - Heavy weapon stationary bonus (2 constants)
  - Movement objective weights (8 constants)
  - Threat awareness (8 constants)
  - Deep strike denial / screening (5 constants)
  - Corridor blocking (4 constants)
  - Multi-phase planning (6 constants)
  - Trade and tempo (10 constants)
  - Late-game strategy pivot (10 constants)
  - Secondary mission awareness (6 constants)
  - Faction aggression (5 constants)
  - Melee aggression (4 constants)
  - Engaged unit survival (4 constants)
  - Target priority framework (9 constants)
  - Probability math utilities (referenced throughout)
- **4 difficulty levels** (Easy/Normal/Hard/Competitive) controlling 15 feature toggles + noise + iterations
- **Focus fire coordination** across all shooter units
- **Multi-phase planning** (movement→shooting→charge look-ahead at Hard+)
- **Faction-specific behavior** (Orks rush, Custodes elite engage, World Eaters always charge)
- **Existing `_thinking_steps` system** — captures reasoning text per decision, already attached to results
- **Existing `_action_log` + `_turn_history`** — tracks every action with descriptions, organized by round

## Proposed Solution: Standalone Web App

A self-contained web app that communicates with the Godot game via JSON files:

1. **Reads AI decision logs** exported from the game as JSON
2. **Visualizes every decision** with full scoring breakdowns
3. **Exposes all tunable parameters** with sliders/inputs
4. **Exports modified parameters** back as a config file the game can load

### Data Flow

```
Godot Game                              Web App (browser)
    │                                        │
    ├── AIDecisionMaker.decide()             │
    │   emits structured scoring data        │
    │   via _thinking_steps                  │
    │                                        │
    ├── AIPlayer._action_log                 │
    │   stores full decision records         │
    │                                        │
    ├── [F10 key or menu] ──────────────────►│
    │   exports ai_decision_log.json         │
    │   to user:// directory                 │
    │                                        │
    │   ai_decision_log.json ───────────────►│ Import & Visualize
    │                                        │
    │                                        │ Parameter Editor
    │   ai_config.json ◄────────────────────│ Export Config
    │                                        │
    ├── On next game start:                  │
    │   AIDecisionMaker loads overrides      │
    │   from user://ai_config.json           │
    └────────────────────────────────────────┘
```

### Part 1: Enhanced AI Logging in Godot

Modify `AIDecisionMaker` to emit **structured decision records** alongside existing text thinking steps. Each key decision function will append a structured dictionary to `_thinking_steps` containing:

- `decision_type`: "movement", "shooting_target", "charge_target", "fight_target", "deployment", etc.
- `unit_id`, `unit_name`: which unit is deciding
- `candidates`: Array of all evaluated options, each with:
  - `id` / `description`: what this option is
  - `score`: final numerical score
  - `score_breakdown`: Dictionary of named components (e.g., `{objective: 8.0, threat: -2.0, firing: 3.0}`)
- `chosen`: index/id of selected candidate
- `parameters_used`: which tuning constants were active (by name + value)
- `difficulty`: current difficulty level
- `context`: phase, round, battle state

Modify `AIPlayer` to:
- Add `export_decision_log()` function serializing `_turn_history` + enriched `_action_log` to JSON
- Wire export to a keyboard shortcut (F10) or menu button
- Include game metadata (armies, mission, difficulty, round)

### Part 2: Web App — Decision Visualizer

**Technology**: Single HTML file with embedded CSS + JS. No dependencies, no build tools. Warhammer 40k themed (dark background, gold accents — matching the in-game `WhiteDwarfTheme`).

#### Tab 1: Game Timeline
- Vertical timeline showing Battle Rounds 1-5
- Each round expands to show phases (Command → Movement → Shooting → Charge → Fight → Scoring)
- Each phase shows a summary card per player: "Player 1 (AI): Moved 5 units, shot 4 targets, charged 2 units"
- Expandable to show each individual action as a card
- Color-coded by player (blue/red matching in-game)
- Click any action card to open the Decision Inspector

#### Tab 2: Decision Inspector
When a decision is selected from the Timeline:
- **Context bar**: Round 3, Movement Phase, Player 2 (Orks)
- **Unit card**: Name, M/T/Sv/W/Ld/OC stats, weapons list, abilities, current wounds remaining
- **Decision summary**: "Moved toward Objective 2 (uncontrolled)" with chosen destination highlighted
- **All candidates evaluated**: Sortable table showing every option the AI considered
  - Each row: candidate description, total score, expandable score breakdown
  - Top candidate highlighted in green, others in grey
- **Score breakdown visualization**: Horizontal stacked bar chart for the top 3 candidates
  - Each bar segment represents a scoring component (objective priority, threat penalty, firing position, etc.)
  - Positive components stack right (green), negative stack left (red)
  - Makes it immediately obvious why one candidate beat another
- **Difficulty impact**: Shows which features were active and how difficulty affected this decision
- **Parameters used**: Lists the specific constants that influenced this decision, with current values

#### Tab 3: Parameter Editor
Organized into collapsible sections matching the code:

**Movement & Positioning**
| Parameter | Description | Default | Current | Range |
|---|---|---|---|---|
| WEIGHT_UNCONTROLLED_OBJ | Priority for unclaimed objectives | 10.0 | [slider] | 0-20 |
| WEIGHT_CONTESTED_OBJ | Priority for contested objectives | 8.0 | [slider] | 0-20 |
| ... | ... | ... | ... | ... |

Each parameter has:
- Name (matching GDScript constant name exactly)
- Human-readable description (from code comments)
- Default value
- Current value (editable via slider + number input)
- Reasonable min/max range
- Reset-to-default button per parameter

Section categories:
1. **Objective Priorities** (8 constants)
2. **Threat Assessment** (8 constants)
3. **Weapon Efficiency Matching** (9 constants)
4. **Focus Fire Tuning** (3 constants)
5. **Weapon Keywords** (6 constants)
6. **Heavy Weapons** (2 constants)
7. **Charge Evaluation** (referenced in multiple functions)
8. **Multi-Phase Planning** (6 constants)
9. **Trade & Tempo** (10 constants)
10. **Late-Game Strategy** (10 constants)
11. **Secondary Mission Awareness** (6 constants)
12. **Faction Aggression** (5 constants)
13. **Melee Aggression** (4 constants)
14. **Survival Assessment** (4 constants)
15. **Target Priority Framework** (9 constants)
16. **Screening & Denial** (5 constants)
17. **Corridor Blocking** (4 constants)

Actions:
- **Export Config** → downloads `ai_config.json` (only changed values, with metadata)
- **Import Config** → loads a previously exported config
- **Reset All to Defaults** → clears all overrides
- **Reset Section** → per-section reset

#### Tab 4: Difficulty Comparison
- Side-by-side comparison of all 4 difficulty levels
- Feature toggle matrix (which features are enabled at which level)
- Parameter differences table (noise, iterations, charge threshold)
- Description of each difficulty's "personality"

### Part 3: Godot Config Loader

Add to `AIDecisionMaker.gd`:

```gdscript
# Config override system
static var _config_overrides: Dictionary = {}
static var _config_loaded: bool = false

static func load_config_overrides() -> void:
    var path = "user://ai_config.json"
    if not FileAccess.file_exists(path):
        return
    var file = FileAccess.open(path, FileAccess.READ)
    var json = JSON.new()
    if json.parse(file.get_as_text()) == OK:
        _config_overrides = json.data.get("parameters", {})
        _config_loaded = true
        print("AIDecisionMaker: Loaded %d config overrides" % _config_overrides.size())

static func get_param(param_name: String, default_value: float) -> float:
    if _config_overrides.has(param_name):
        return float(_config_overrides[param_name])
    return default_value
```

Key decision functions will use `get_param("WEIGHT_UNCONTROLLED_OBJ", WEIGHT_UNCONTROLLED_OBJ)` instead of referencing the constant directly, allowing runtime override.

## File Changes

### New files:
1. **`ai-visualizer/index.html`** — The complete web app (~2000-3000 lines of HTML/CSS/JS)

### Modified files:
1. **`40k/scripts/AIDecisionMaker.gd`** — Add:
   - Config override system (`_config_overrides`, `load_config_overrides()`, `get_param()`)
   - Structured decision records in 6 key functions: `_select_movement_action()`, `_decide_shooting()`, `_evaluate_best_charge()`, `_assign_fight_attacks()`, `_decide_deployment()`, `_decide_scoring()`
   - Use `get_param()` for all tunable constants (~120 call sites)

2. **`40k/autoloads/AIPlayer.gd`** — Add:
   - `export_decision_log()` function
   - F10 keybind for export
   - Call `AIDecisionMaker.load_config_overrides()` on startup
   - Enrich `_action_log` entries with structured decision data from `_ai_thinking_steps`

## Scope

### This PR (Phase 1): Full Working System
- Complete web app with all 4 tabs
- Enhanced structured logging in the 6 core decision functions
- All ~120 parameters exposed in the editor
- JSON export/import working in both directions
- Config override system in Godot

### Future (Phase 2): Live Connection
- WebSocket or HTTP bridge for real-time decision streaming
- Live parameter hot-reload without restarting

### Future (Phase 3): AI Training & Analytics
- Record game outcomes per parameter set
- A/B comparison dashboard
- Win-rate tracking and auto-tuning suggestions

## Design Principles

1. **No information loss**: Every decision the AI makes should be capturable and inspectable
2. **Zero performance impact when not exporting**: Structured logging adds negligible overhead (dictionaries are cheap in GDScript)
3. **Standalone**: Web app works offline, no server needed, just open the HTML file
4. **Faithful to the code**: Parameter names, descriptions, and organization match the source exactly
5. **Warhammer themed**: Dark UI with gold/parchment accents matching the game's WhiteDwarfTheme
6. **Non-destructive**: Config overrides are optional; game works identically without them
