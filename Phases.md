To keep the game as modular as possible I would like a standard data object that is passed between phases. This is the **core game state contract** 
  that each phase will consume and produce.
  This is the backbone for:

  * **Phase modularity** (each phase only needs to know about the state + return its deltas).
  * **Replay system** (all actions logged in a standardized way).
  * **Future AI integration** (AI just reads game state + chooses actions).
  * **Networking** (server validates state transitions).

  Here’s a detailed plan 👇

  ---

  # 📦 Standard Game State & Phase Output Contract

  ## 🔑 Principles

  1. **Immutable input, explicit output** → Each phase receives the `GameState` snapshot + applies changes via an **Action log**.
  2. **Replayable** → All actions are logged in a sequential `actions[]` array with metadata (actor, type, params, results).
  3. **Serializable** → Full state can be dumped to JSON for Save/Load or Replay.
  4. **Extensible** → Future rules can add more fields without breaking older data.

  ---

  ## 🗺️ Data Structure (JSON / Dictionary-like)

  ```json
  {
    "meta": {
      "game_id": "uuid-1234",
      "turn_number": 2,
      "active_player": "player_1",
      "phase": "movement"
    },
    "board": {
      "size": { "width": 44, "height": 60 },
      "objectives": [
        { "id": "obj1", "x": 12, "y": 30, "controlled_by": "player_2" },
        { "id": "obj2", "x": 32, "y": 15, "controlled_by": null }
      ],
      "terrain": [
        { "id": "t1", "type": "ruins", "x": 20, "y": 20, "radius": 6 }
      ]
    },
    "units": [
      {
        "id": "p1_u1_m1",
        "squad_id": "p1_u1",
        "owner": "player_1",
        "name": "Intercessor",
        "stats": { "move": 6, "toughness": 4, "wounds": 2, "save": 3 },
        "position": { "x": 5, "y": 10 },
        "current_wounds": 2,
        "status_effects": [],
        "alive": true
      }
    ],
    "players": {
      "player_1": { "cp": 3, "vp": 10 },
      "player_2": { "cp": 2, "vp": 5 }
    },
    "phase_log": [
      {
        "phase": "movement",
        "actor": "p1_u1_m1",
        "action": "move",
        "params": { "from": { "x": 5, "y": 10 }, "to": { "x": 9, "y": 10 } },
        "result": { "distance": 4, "valid": true },
        "timestamp": "2025-08-17T14:35:00Z"
      }
    ],
    "history": [
      { "turn": 1, "phase": "shooting", "actions": ["..."] },
      { "turn": 1, "phase": "charge", "actions": ["..."] }
    ]
  }
  ```

  ---

  ## 📋 Breakdown

  * **`meta`**
    Tracks whose turn it is, current phase, and game ID.

  * **`board`**
    Static properties of the battlefield (size, terrain, objectives).

  * **`units`**
    Flat list of all models/tokens on the board.
    Each has:

    * `id` (unique per model)
    * `squad_id` (group link)
    * `owner` (which player)
    * `stats` (base profile)
    * `position` (x,y coordinates)
    * `current_wounds`, `status_effects`, `alive`

  * **`players`**
    CP, VP, command limits.

  * **`phase_log`**
    The *delta of this phase only* (actions just performed).
    Used for replay step-by-step.

  * **`history`**
    The *cumulative log of past phases*, enabling full replay of entire game.

  ---

  ## 📝 Prompt Spec (to use with devs / AI coding agents)

  > **Prompt:**
  >
  > We need a **modular game state data structure** for a turn-based tabletop simulator in Godot.
  > Requirements:
  >
  > * It must fully represent the battlefield, units, players, and objectives.
  > * Each **phase module** (Deployment, Movement, Shooting, etc.) should **receive a snapshot of `GameState` as input** and **return an updated `GameState` with a `phase_log` 
  of actions performed**.
  > * All actions must be stored in a **standardized format**:
  >
  >   * `actor` (unit ID or player ID)
  >   * `action` (e.g., "move", "shoot", "roll\_dice")
  >   * `params` (inputs: positions, dice rolled, modifiers)
  >   * `result` (outcome: distance moved, wounds lost, save passed/failed)
  >   * `timestamp`
  > * The structure must be **serializable to JSON** for save/load and replays.
  > * It must be **extensible** so future rules (like aura effects, advanced terrain, or AI intent flags) can be added without breaking backwards compatibility.
  >
  > Output: Provide a JSON-like schema for this `GameState`, with examples for at least one movement action and one shooting action.

  ---
