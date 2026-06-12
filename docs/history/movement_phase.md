I want to add the next phase to the app. As the design is intentionally modular this should not change the existing deployment phase code.
It should take the as code data object as input and output the updated data object. 

Here’s a focused, deeply detailed design doc for the **Movement Phase** only, fitting your MVP constraints and the architecture you already set. I’m baking in just enough 10e Core Rules to be faithful, but still scoped for a shippable implementation.

# 🎯 Movement Phase — Design Doc (Godot 4.4, 10e Core Rules)

## 1) Scope & Rule Alignment (MVP)

Supported move types this phase:

* **Remain Stationary** (implicit “do nothing” state).
* **Normal Move** — up to **M"**, must **not** move within Engagement Range (ER) of enemies. ([Wahapedia][1])
* **Advance** — roll **D6**, each model may move up to **M + D6"**; **cannot** end within ER; the **unit cannot shoot or declare a charge** later this turn. ([Wahapedia][1])
* **Fall Back** — each model may move up to **M"**; can **move through** enemy models *during* the move, but **cannot end** within ER. Unit **cannot shoot or charge** this turn. **Desperate Escape**: roll one D6 per model that moves through enemies (and per model if the unit is **Battle-shocked**); on **1–2**, **one model is destroyed** (chosen by controller). ([Wahapedia][1])

Terrain (MVP handling):

* “**Moving Over Terrain**”: cannot move **through** solid features (e.g., walls); models can pass over features **≤ 2" high** freely; vertical distance counts if > 2", and moves can’t end mid-climb. **MVP simplification**: treat “obscuring/light\_cover ruins” as **impassable solids** for pathing (no vertical), with a feature flag to upgrade later to true vertical counting. ([Wahapedia][1])

**Out of scope (MVP):** coherency enforcement (UI helper only), fly movement special casing, transports emb/dism, difficult ground penalties. (We leave hooks to add “FLY” and vertical/penalties later. The rules for FLY exist if you want to toggle it on: fly can move “over” models and measure “through the air,” but still cannot end within ER. ([Wahapedia][1]))

## 2) Player UX — Movement Phase

### 2.1 Phase flow

1. **Enter Movement Phase** (active player only). PhaseBar updates; right panel lists **that player’s units** with per-unit move status (Stationary / Moved / Advanced / Fell Back).
2. **Select a Unit** (right panel or board click).
3. Choose one of:

   * **Normal Move**: button lights up; BoardView enters **path mode**.
   * **Advance**: rolls D6 immediately (DiceLog), locks unit to **M + D6"** cap; enters path mode. (Unit UI gets “Advanced” tag & later-phase restrictions.)
   * **Fall Back**: allowed only if within ER; enters path mode with special rule (engine will later do Desperate Escape tests if any model crosses enemies). (Unit UI gets “Fell Back” tag & later-phase restrictions.)
   * **Remain Stationary**: mark complete without moving (for bookkeeping).
4. **Path mode (per-model placement)**:

   * Click a **model** → drag to destination; a **ruler line** and **polyline path** show **true inches** remaining.
   * HUD bottom shows: **M cap, inches used, inches left, illegal reasons**.
   * Drop not allowed if **end point in ER** (unless Fall Back pathing in-range but still must end out of ER), or **inside impassable**.
   * **Undo (model)** rewinds last model move; **Reset Unit** removes all placements this unit this phase.
   * **Confirm Unit Move** activates once all intended models are placed (you can also confirm early; un-moved models count as stationary).
5. Repeat for other units; then **End Phase** (PhaseBar).

### 2.2 Micro-interactions

* **Hover** a model: show ghost circle at current base radius; snap preview to **½"** increments (toggle in settings).
* **Shift while dragging**: straight-line constrain (good for measuring lanes).
* **Illegal feedback**: destination circle turns red with tooltip (“Would end in ER”, “Exceeds M”, “Inside terrain”).
* **DiceLog** (right panel tab): logs **Advance D6** and **Desperate Escape** individually per model (explicit rolls with outcomes).

## 3) Data & State

### 3.1 BoardState additions (movement flags)

Per unit:

```jsonc
"flags": {
  "moved": false,          // set true after confirm (any move)
  "advanced": false,       // set if chose Advance
  "fell_back": false,      // set if chose Fall Back
  "move_path": null        // transient during phase; cleared on confirm/reset
}
```

Per model (existing): `{"id","pos":[x,y],"wounds",...}`

### 3.2 TurnManager contract (phase-specific)

* `TurnManager.phase == "MOVEMENT"`
* `TurnManager.active_player == 1|2`
* Emits `unit_completed_movement(unit_id)` on confirm/reset (affects “moved” bookkeeping).

## 4) Actions & Results (Atomic, Replayable)

**Actions (intents)**

* `BEGIN_NORMAL_MOVE {unit_id}`
* `BEGIN_ADVANCE {unit_id}`
* `BEGIN_FALL_BACK {unit_id}`
* `SET_MODEL_DEST {unit_id, model_id, dest_px:[x,y]}`  // one per model drop
* `UNDO_LAST_MODEL_MOVE {unit_id}`
* `RESET_UNIT_MOVE {unit_id}`
* `CONFIRM_UNIT_MOVE {unit_id}`

**Results (authoritative diffs)**

* For `BEGIN_ADVANCE`: `dice:[{context:"advance", n:1, rolls:[d6]}]`, `diff: set flags.advanced=true, flags.move_cap_in= M + d6`
* For `BEGIN_NORMAL_MOVE`: `diff: set move_cap_in=M`
* For `BEGIN_FALL_BACK`: `diff: set flags.fell_back=true, move_cap_in=M`
* For each `SET_MODEL_DEST`: engine validates; if legal → `diff: set units.X.models.mY.pos = dest`
* For `CONFIRM_UNIT_MOVE`:

  * If **Fall Back** and any model crossed enemy bases **or** unit is **Battle-shocked**: emit **Desperate Escape** rolls (one per affected model). On **1–2** → `remove units.X.models.mY` (you choose which; UI preselects candidates with a picker; your selection is sent in the action payload; engine validates eligibility). ([Wahapedia][1])
  * `diff: set flags.moved=true; clear flags.move_path/move_cap_in`

All Results carry a `phase:"MOVEMENT"` and append DiceLog entries for replays.

## 5) Legality & Validation

### 5.1 “Cap distance” per model

* Sum of path segment lengths (inches) **≤ move\_cap\_in**
* Move cap source: **M**, **M + D6** (Advance), **M** (Fall Back).

### 5.2 Engagement & proximity

* **Normal / Advance**: path may not **enter** ER (exception: path visualization allowed to overlap; drop forbidden), **end** must be **outside** ER. ([Wahapedia][1])
* **Fall Back**: path may **enter** ER and can **cross enemy bases**; **end** must be **outside** ER. Crossing enemy → mark model for **Desperate Escape**. ([Wahapedia][1])

### 5.3 Terrain (MVP)

* Treat “ruins/obscuring” polygons as **impassable solids** (no through-walls).
* **No vertical** counting in MVP; an option flag `vertical_movement=false`.
* If `vertical_movement=true`, engine counts vertical “over 2"” per rules; UI shows **climb cost** chunk. ([Wahapedia][1])

### 5.4 Side effects/locks

* After **Advance/Fall Back**, engine marks **shoot/charge prohibited** (to be read by later phases). ([Wahapedia][1])
* **Remain Stationary**: no flags set; unit still marked completed for this phase.

## 6) Algorithms

### 6.1 Measurement & inches

* Use `PX_PER_INCH` consistently; UI ruler uses **edge-to-edge** (center point + base radius corrections) for honesty.
* Movement cost = **polyline length** (center path) **minus** base radius adjustments at start/end (simple approach: treat center path; MVP ok).

### 6.2 Engagement Range test

* ER radius: **1"** (10e default). Compute **min distance** between circles (model bases) of moving model and **any enemy** at final position; must be **> ER** (Normal/Advance) or **> ER** at end (Fall Back). (ER constant lives in Settings.)

### 6.3 Crossing enemies (Fall Back)

* During `SET_MODEL_DEST` for Fall Back, check **path segment** vs enemy base circles (inflate enemy radius by your base radius + ER) — if **intersection occurs**, tag model `will_desperate_escape=true`.

### 6.4 Path legality vs terrain

* Treat each terrain polygon as **forbidden** region (expanded by model base radius to prevent edge penetration).
* For each path segment, test **segment vs polygon** intersection; forbid if any; draw red.

### 6.5 Desperate Escape roll resolution

* Build list:

  * All models in unit if **Battle-shocked**, **or**
  * Only those with `will_desperate_escape=true`.
* For each, `roll d6`; on **1–2**, **destroy one model**. (UI lets player pre-nominate which specific models are eligible to be removed; engine validates they belong to the unit and are not already removed.) ([Wahapedia][1])

## 7) Godot Scenes & UI (4.4)

### 7.1 Board & Camera

* **`BoardView.tscn`** (CanvasLayer + Node2D)

  * `Camera2D` with zoom controls mapped to `ui_zoom_in` / `ui_zoom_out` (**+/-** keys via `InputMap`).
  * Use `Camera2D.zoom` changes (multiply by 0.9 / 1.1 per press). ([Godot Engine Documentation][2])
  * Path ghosting via `Line2D` (no antialias issues at zoom; keep widths proportional).

### 7.2 HUDs

* **Bottom HUD** (collapsible): `HSplitContainer`/`PanelContainer`; shows:

  * Current move cap, inches used/left, tooltips for illegality.
  * Buttons: **Undo (model)**, **Reset Unit**, **Confirm Unit Move**.
  * Collapse toggle stored in Settings. (Use SplitContainer/PanelContainer.) ([Godot Engine Documentation][3])
* **Right Panel** (collapsible): `VSplitContainer`

  * Unit list (active player only) with status tags.
  * Action buttons: **Normal**, **Advance**, **Fall Back**, **Remain Stationary** (disabled/enabled by context).
  * DiceLog tab for rolls in this phase. ([Godot Engine Documentation][4])

### 7.3 Signals (clean flow)

Custom signals you’ll likely emit:

* `unit_move_begun(unit_id, mode)` — begins cap & UI mode
* `model_drop_preview(unit_id, model_id, path_px, inches_used, legal)`
* `model_drop_committed(unit_id, model_id, dest_px)`
* `unit_move_confirmed(unit_id, result_summary)`
* `unit_move_reset(unit_id)`
  (Use Godot signals; connect in `Main` or `GameManager` as appropriate.) ([Godot Engine Documentation][5])

## 8) Core Code Contracts (concise)

### 8.1 MovementPhase.gd (UI → Actions)

```gdscript
# Called when player clicks "Advance"
func on_advance_pressed(unit_id:String) -> void:
    var action = {"type":"BEGIN_ADVANCE","actor_unit_id":unit_id,"payload":{}}
    GameManager.request_action(action)

# Called when model is dropped on board
func on_model_drop(unit_id:String, model_id:String, dest:Vector2) -> void:
    var action = {"type":"SET_MODEL_DEST","actor_unit_id":unit_id,"payload":{"model_id":model_id,"dest":[dest.x, dest.y]}}
    GameManager.request_action(action)

func on_confirm_unit_move(unit_id:String) -> void:
    GameManager.request_action({"type":"CONFIRM_UNIT_MOVE", "actor_unit_id":unit_id, "payload": {}})
```

### 8.2 RulesEngine.gd (movement slice)

```gdscript
static func resolve(action:Dictionary, board:Dictionary, rng) -> Dictionary:
    match action.type:
        "BEGIN_ADVANCE": return _resolve_begin_advance(action, board, rng)
        "BEGIN_NORMAL_MOVE": return _resolve_begin_normal(action, board)
        "BEGIN_FALL_BACK": return _resolve_begin_fallback(action, board)
        "SET_MODEL_DEST": return _resolve_set_model_dest(action, board)
        "CONFIRM_UNIT_MOVE": return _resolve_confirm_unit_move(action, board, rng)
        # ...
```

Key helpers:

* `_cap_for(unit)` → inches
* `_is_end_in_engagement(dest, model_radius, enemies)` → bool
* `_path_crosses_enemy(path, model_radius, enemies)` → bool
* `_path_hits_impassable(path, model_radius, terrain_polys)` → bool
* `_do_desperate_escape(unit)` → diffs + dice

### 8.3 Measurement.gd (already planned)

* `in_to_px()`, `px_to_in()`, `distance_polyline_px(points:Array[Vector2]) -> float`
* `base_radius_px(base_mm:int) -> float`

## 9) DiceLog Examples (exactness)

* **Advance**
  `Advance: Intercessor Squad → D6 = 4 → Move cap = 10" (M 6" + 4")`. ([Wahapedia][1])

* **Desperate Escape**
  `Fell Back: 5 models crossed enemy → rolls: [1,2,4,4,6] → models lost: 2`. ([Wahapedia][1])

## 10) Edge Cases & Rules Notes

* **Start in ER and choose Normal/Advance**: illegal; UI disables those buttons (Fall Back or Remain Stationary only). (Normal/Advance may not move within ER.) ([Wahapedia][1])
* **Cannot end Fall Back out of ER**: then **cannot Fall Back** (engine rejects on confirm; UI message). ([Wahapedia][1])
* **Battle-shocked Fall Back**: Desperate Escape applied to **every model** in the unit (even if not crossing enemies). ([Wahapedia][1])
* **Advance/Fall Back restrictions** persist to later phases (Shooting/Charge). ([Wahapedia][1])
* **Vertical / ≤ 2" free** is deferred unless `vertical_movement=true`. ([Wahapedia][1])

## 11) Tests

### 11.1 Unit tests (pure logic)

* **Cap**: `M=6`, no advance → exactly 6" allowed; with `D6=4` → 10".
* **ER**: End position just **inside** ER → illegal; just **outside** → legal.
* **Impassable**: segment intersects polygon → illegal.
* **Fall Back**:

  * End in ER → illegal.
  * Cross enemy base markers → flag Desperate Escape N times; apply removals on 1–2.
  * Battle-shocked → N rolls for entire unit even if no crossing.

### 11.2 Integration tests

* **Advance lockouts**: After confirming, verify engine marks `advanced=true` and **shoot/charge** disabled.
* **Fallback impossible**: Enclosed by enemies so no legal end point out of ER → `BEGIN_FALL_BACK` ok, but `CONFIRM` rejected.
* **Replay**: Fixed seed makes Advance=4; applying log reconstructs same final positions & casualties.

## 12) Acceptance Criteria (Movement Phase “Done”)

* Can complete a Movement Phase hotseat with:

  * Normal moves respecting **M** and ER.
  * Advance with D6 cap, DiceLog, and **shoot/charge** lockouts later.
  * Fall Back from ER with correct **end-out-of-ER** validation and **Desperate Escape** rolls/removals.
* Terrain solids prevent illegal pathing; visual feedback is clear.
* Right panel unit list reflects per-unit move state (Stationary/Moved/Advanced/Fell Back).
* Bottom HUD shows cap, inches used, remaining, and actionable **Undo/Reset/Confirm**.
* All actions produce **Results** with diffs; **Replay** re-applies deterministically.

---

## 13) Implementation Notes (Godot 4.4 niceties)

* **InputMap**: define `ui_zoom_in` (`+`) and `ui_zoom_out` (`-`) and use `Input.is_action_just_pressed`. ([Godot Engine Documentation][6])
* **Camera2D.zoom**: multiply vector (e.g., `zoom *= 0.9`) to zoom in/out smoothly. ([Godot Engine Documentation][2])
* **Containers**: use `SplitContainer` / `VSplitContainer` plus `PanelContainer` for crisp collapsible HUD frames. ([Godot Engine Documentation][3])
* **Signals**: keep UI decoupled by emitting signals from BoardView and handling in `GameManager`/`MovementPhase`. ([Godot Engine Documentation][5])

---

If you want, I can follow this with a **scaffolded Godot scene tree + stub GDScript files** for just the Movement Phase (BoardView, MovementPhase.gd, and the Action/Result handlers) so you can paste them in and iterate.

[1]: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/ "Core Rules"
[2]: https://docs.godotengine.org/en/4.4/classes/class_camera2d.html?utm_source=chatgpt.com "Camera2D — Godot Engine (4.4) documentation in English"
[3]: https://docs.godotengine.org/en/4.4/classes/class_splitcontainer.html?utm_source=chatgpt.com "SplitContainer — Godot Engine (4.4) documentation in English"
[4]: https://docs.godotengine.org/en/4.4/classes/class_vsplitcontainer.html?utm_source=chatgpt.com "VSplitContainer — Godot Engine (4.4) documentation in English"
[5]: https://docs.godotengine.org/en/4.4/getting_started/step_by_step/signals.html?utm_source=chatgpt.com "Using signals — Godot Engine (4.4) documentation in English"
[6]: https://docs.godotengine.org/en/4.4/classes/class_inputmap.html?utm_source=chatgpt.com "InputMap — Godot Engine (4.4) documentation in English"
