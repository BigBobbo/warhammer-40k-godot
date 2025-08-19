Here’s a focused, end-to-end design doc for implementing the **Deployment Phase** only, inside your existing Godot 4.4 project. It keeps your PRP’s architecture (BoardState, Actions/Results, UI separation), but narrows logic, data, and UI to deployment, with precise Godot node trees, signals, input, and validation rules hooked to 10e Core Rules.

---

# Deployment Phase — Design Document (Godot 4.4)

## 1) Scope & Goals

**Goal:** Let two hotseat players deploy default attacker/defender forces on a 44″×60″ board, alternating legal unit setups until both sides are fully deployed.

**Out of scope (for now):** coherency enforcement, deep strike/reserves, alternating mission-specific oddities beyond “wholly within” deployment zones. (We will *warn* for coherency but not block.) In 10e, players alternate setting up units, starting with the Defender; models must be **wholly within** their deployment zone; coherency applies to setup but we’re not enforcing it in MVP, only hinting. ([Wahapedia][1])

---

## 2) Player-Facing UX

### 2.1 Board & Camera

* **Top-down board**; **+ / −** keys zoom in/out. Camera uses `Camera2D.zoom` (smaller = closer). Example: `zoom *= 0.9` for +, `zoom *= 1.1` for −, clamped within `[0.3, 3]`. ([Godot Engine Documentation][2])
* **Deployment zones**: tinted polygons on the board; hover shows tooltip (“Your zone”). Clicks outside your zone during placement show a red toast (“Must be wholly within deployment zone”).

### 2.2 HUDs

* **Bottom HUD (collapsible)**: phase banner (“Deployment”), alternating player indicator, “End Deployment” (disabled until all units placed), a small status line (e.g., “Placing: Intercessors — 0/5 models”).
* **Right HUD (collapsible)**: **Unit List Panel** filtered to *undeployed* units for the **active player**.

  * Selecting a unit shows its card (name, keywords, characteristics) and two dynamic buttons:

    * **Undo** — appears *after* you place any model of that unit; removes all its placed models and re-enables other units.
    * **Confirm** — appears when all models for that unit are placed; locks the unit and returns to the unit list.
  * Deactivate selecting other units while a unit is mid-placement until **Undo** or **Confirm** is pressed (as per your spec).

### 2.3 Placement Interaction

* Click a unit in the right HUD → the board shows a **ghost** of the model base under the cursor in the active player’s color.
* Click on the board to **stamp** each model one at a time:

  * **Validation** (blocking):

    * Position must be wholly inside the player’s deployment polygon.
  * **Warnings** (non-blocking, tiny yellow banner):

    * Coherency hint: “Some models >2″ from unit mates.” (informational during MVP).
* When the **last model** is placed, enable **Confirm**.
* **Alternate units**: After Confirm, switch active side if using true alternation (Defender starts). If one player runs out of units, the other continues placing until done. ([Wahapedia][1])

---

## 3) Rules & Legality (MVP)

* **Wholly within deployment zone**: every model’s **base** must lie wholly inside their zone polygon. Use a *circle-inside-polygon* test. ([Wahapedia][1])
* **Alternating deployment**: Defender places first, then players alternate unit-by-unit. If a side finishes deploying first, the other continues placing the remainder. ([Wahapedia][1])
* **Coherency**: 10e requires coherency at setup; we **don’t block** if incoherent (MVP), but show a warning. (2–6 models: within 2″ of ≥1 model; 7+: within 2″ of ≥2). ([Wahapedia][3])

---

## 4) Data & State

### 4.1 BoardState (deployment subset)

```json
{
  "phase": "DEPLOYMENT",
  "active_player": 1,              // 1 = Defender (MVP default)
  "deployment_zones": [
    {"player":1, "poly":[[...px]]},
    {"player":2, "poly":[[...px]]}
  ],
  "units": {
    "U_INTERCESSORS_A": {
      "owner": 1,
      "status": "undeployed|deploying|deployed",
      "models": [
        {"id":"m1","wounds":2,"base_mm":32,"pos":null},
        ...
      ],
      "meta":{"name":"Intercessor Squad","keywords":["INFANTRY"] }
    },
    "U_BOYZ_B": { "owner": 2, ... }
  }
}
```

### 4.2 Transient DeploymentState (UI-only)

```gdscript
var selected_unit_id: String = ""
var placing_model_index: int = -1        # 0..n-1 while deploying
var placed_positions: Array[Vector2] = []# for Undo before confirm
```

---

## 5) Scene & Scripts

### 5.1 Main Scene Tree

```
Main.tscn
└── CanvasLayer
    ├── BoardRoot (Node2D)
    │   ├── Camera2D (current = true)         # zoom with +/- 
    │   ├── BoardView (Node2D)                # table, objectives, terrain
    │   ├── DeploymentZones (Node2D)
    │   │   ├── P1Zone (Polygon2D, modulate=blue, 0.2 alpha)
    │   │   └── P2Zone (Polygon2D, modulate=red, 0.2 alpha)
    │   ├── TokenLayer (Node2D)               # placed models
    │   └── GhostLayer (Node2D)               # ghost preview while placing
    ├── HUD_Bottom (PanelContainer, collapsible)
    │   └── HBoxContainer
    │       ├── PhaseLabel
    │       ├── ActivePlayerBadge
    │       ├── StatusLabel
    │       └── EndDeploymentButton (disabled until done)
    └── HUD_Right (PanelContainer, collapsible)
        └── VBoxContainer
            ├── UnitListPanel (ItemList or Tree)
            └── UnitCard (stats + Undo/Confirm)
```

* We use **Polygon2D** for deployment zones and fill with semi-transparent tints. ([Godot Engine Documentation][4])
* **PanelContainer** for HUD chrome; collapsible behavior implemented with a toggle button that hides/shows the child container. ([Godot Engine Documentation][5])
* **UnitListPanel** can be **ItemList** (simple list) or **Tree** (group by Battlefield Role, Owner). Either is fine—ItemList is lighter; Tree is richer. ([Godot Engine Documentation][6])

### 5.2 Autoloads (Singletons)

* `BoardState.gd` — serializable data (phase, units, zones).
* `Measurement.gd` — inches↔px helpers.
* `GameManager.gd` — applies diffs (Action/Result).
* `TurnManager.gd` — **DeploymentPhase** controller / alternation.
* `SettingsService.gd` — PX\_PER\_INCH, etc.

---

## 6) Input & Camera

* Add two actions in **Project → Project Settings → Input Map**: `zoom_in` bound to `+` and `zoom_out` bound to `-`. Handle in `_unhandled_input` or `_process`:

  * `if Input.is_action_just_pressed("zoom_in")` → `camera.zoom *= 0.9`
  * `if Input.is_action_just_pressed("zoom_out")` → `camera.zoom *= 1.1`
* Prefer actions (via **InputMap**) over hard-coding scancodes; it’s future-proof for remapping/controllers. ([Godot Engine Documentation][7])

---

## 7) Signals & Flow

**Key signals (Godot 4.4 has first-class signals):** ([Godot Engine Documentation][8])

* `UnitListPanel.unit_selected(unit_id: String)`
* `DeploymentController.model_placed(unit_id: String, model_index: int, pos: Vector2)`
* `DeploymentController.undo_requested(unit_id: String)`
* `DeploymentController.confirm_requested(unit_id: String)`
* `TurnManager.deployment_side_changed(player: int)`
* `DeploymentController.deployment_complete()`

**Wiring:**

* `UnitListPanel` → `DeploymentController.on_unit_selected`
* Board (mouse click) → `DeploymentController.try_place_current_model_at(mouse_world_pos)`
* Buttons (Undo/Confirm) → `DeploymentController.on_undo` / `on_confirm`
* `DeploymentController` → `GameManager.apply_result(diffs)` when Confirmed
* `TurnManager` listens for `unit_confirmed` to alternate sides

---

## 8) Algorithms (core checks)

### 8.1 Circle wholly inside polygon (blocking)

* Model base radius in pixels: `r_px = Measurement.base_radius_px(base_mm)`.
* Test: every point of the circle must be inside polygon → *approximate* by ensuring **circle center** is inside polygon and the **closest distance** from center to polygon edge ≥ `r_px`. (Use point-in-polygon and distance to edges.)
* Polygons come from preset **deployment\_zones** (already in pixels).

### 8.2 Coherency warning (non-blocking)

* After each placement, compute **nearest-neighbor** distances among this unit’s model centers; if any model in a 2–6 model unit has all neighbors >2″, warn; for ≥7 models, each must have at least **two** neighbors ≤2″. (Distance in inches via Measurement.) ([Wahapedia][3])

### 8.3 Alternation

* Start `active_player = Defender (1)`.
* On **Confirm**, mark unit `status="deployed"`, append diffs to BoardState, and:

  * If **both sides** still have `undeployed` units: flip `active_player`.
  * Else if **one side** has none: keep the remaining side active until their units finish. ([Wahapedia][1])
* When **no undeployed units remain** (both sides), emit `deployment_complete`.

---

## 9) Action/Result (deterministic, replay-safe)

### 9.1 Action

```json
{
  "type": "DEPLOY_UNIT",
  "actor_player": 1,
  "unit_id": "U_INTERCESSORS_A",
  "models": [
    {"id": "m1", "pos": [x1,y1]},
    {"id": "m2", "pos": [x2,y2]},
    ...
  ]
}
```

### 9.2 Result (diffs)

```json
{
  "success": true,
  "phase": "DEPLOYMENT",
  "diffs": [
    {"op":"set","path":"units.U_INTERCESSORS_A.status","value":"deployed"},
    {"op":"set","path":"units.U_INTERCESSORS_A.models.m1.pos","value":[x1,y1]},
    ...
  ],
  "log_text": "Deployed Intercessor Squad (5 models) wholly within DZ."
}
```

Apply only on **Confirm**. **Undo** never mutates BoardState; it clears the transient `DeploymentState` and UI ghosts.

---

## 10) UI Details

### 10.1 UnitListPanel

* **ItemList** showing remaining units for `active_player`.

  * Item text = `Unit Name (N models)`.
  * Disabled while a unit is mid-placement.
* **UnitCard** shows characteristics, keywords, model count; **Undo** (visible after ≥1 placed), **Confirm** (visible when placed = total models).

### 10.2 Ghost & Token Rendering

* **Ghost**: draw a semi-transparent filled circle for the base at cursor; turns **red** when outside DZ (or overlapping table edges/terrain if you want), **yellow** when coherency warning would trigger if stamped.
* **Placed model**: solid token circle with colored rim (owner), center label (`#1`, `#2`, … or short label).

---

## 11) Default Content (MVP)

Populate with 2–3 standard sized units per side (e.g., **Intercessors 5×32mm** vs **Boyz 10×32mm**), and one **T5/Titanic**-sized example later if you want to test edge deployment (skip “Titanic skips next turn” nuance until post-MVP). Preset deployment zones for **Dawn of War** and **Hammer & Anvil**. (Zones are just polygons; reuse your MapGenerator.) ([Wahapedia][1])

---

## 12) Godot Implementation Notes

* **Polygon zones**: `Polygon2D.polygon = PackedVector2Array(points_px)`; `modulate.a = 0.25`. ([Godot Engine Documentation][4])
* **HUD panels**: use `PanelContainer` + `VBoxContainer/HBoxContainer`. Collapse with a `Button` that toggles `visible` or animates `custom_minimum_size`. ([Godot Engine Documentation][5])
* **Signals**: define custom signals in `DeploymentController.gd`, connect from UI in `_ready()` (or via the Editor). ([Godot Engine Documentation][8])
* **Input actions**: bind `zoom_in`/`zoom_out` in **InputMap**; query via `Input.is_action_just_pressed`. ([Godot Engine Documentation][7])
* **Camera2D**: adjust `zoom` vector uniformly; clamp; optionally center on board. ([Godot Engine Documentation][2])
* **UI list**: If you need columns (unit name, models left, keywords), prefer **Tree** with multiple columns; otherwise **ItemList** is simpler. ([Godot Engine Documentation][6])
* **Scene organization & autoloads**: follow Godot best practices for scene vs script roles and autoload singletons (`BoardState`, `GameManager`, `TurnManager`). ([Godot Engine Documentation][9])

---

## 13) Pseudocode (key parts)

### 13.1 DeploymentController.gd (core)

```gdscript
signal deployment_complete()

var unit_id := ""
var model_idx := -1
var temp_positions := [] # Vector2 per model index

func begin_deploy(_unit_id:String) -> void:
    unit_id = _unit_id
    model_idx = 0
    temp_positions.resize(BoardState.get_model_count(unit_id))
    GhostLayer.show()

func try_place_at(world_pos:Vector2) -> void:
    if not _circle_wholly_in_polygon(world_pos, _radius_px(unit_id), _active_zone()):
        _toast("Must be wholly within your deployment zone")
        return
    temp_positions[model_idx] = world_pos
    _spawn_preview_token(unit_id, model_idx, world_pos)
    model_idx += 1
    _update_coherency_warning(temp_positions)

func undo() -> void:
    _clear_previews_for(unit_id)
    temp_positions.fill(null)
    model_idx = 0

func confirm() -> void:
    var diffs = []
    for i in temp_positions.size():
        diffs.append({"op":"set","path":"units.%s.models.%s.pos" % [unit_id, BoardState.model_id(unit_id,i)], "value": temp_positions[i]})
    diffs.append({"op":"set","path":"units.%s.status" % unit_id,"value":"deployed"})
    GameManager.apply_result({"success":true,"phase":"DEPLOYMENT","diffs":diffs,"dice":[]})
    _clear_previews_for(unit_id)
    unit_id = ""; model_idx = -1; temp_positions.clear()
    if BoardState.all_units_deployed():
        emit_signal("deployment_complete")
```

### 13.2 Camera zoom (in Main.gd)

```gdscript
func _unhandled_input(e):
    if Input.is_action_just_pressed("zoom_in"):
        $BoardRoot/Camera2D.zoom *= Vector2(0.9,0.9)
    if Input.is_action_just_pressed("zoom_out"):
        $BoardRoot/Camera2D.zoom *= Vector2(1.1,1.1)
    $BoardRoot/Camera2D.zoom = $BoardRoot/Camera2D.zoom.clamp(Vector2(0.3,0.3), Vector2(3,3))
```

---

## 14) Tests & Acceptance

### 14.1 Unit Tests (pure logic)

* **Polygon inclusion**: known points just inside/outside zone; circle-inside-polygon with radii at boundaries.
* **Alternation**: scripted unit counts per side; asserts active player toggles correctly and sticks when one side finishes.
* **Coherency hint**: synthetic layouts verifying warning triggers.

### 14.2 Integration Tests (in-engine)

* Select a unit → place N models inside zone → **Confirm** produces `status="deployed"` and all `pos` filled.
* Place a model outside zone → rejected with toast; preview turns red.
* Begin unit, place some, hit **Undo** → all previews cleared; can select another unit.
* Full alternation until all units deployed → `deployment_complete` fired; **End Deployment** enabled.

**Acceptance =** All above pass; both HUDs collapse/expand; zoom works via +/−; BoardState diffs reflect final positions.

---

## 15) Incremental Build Plan (1–2 days of work)

1. **Zones & Camera**: draw polygon zones, hook +/− zoom. ([Godot Engine Documentation][4])
2. **Right HUD**: UnitListPanel → select unit; UnitCard with disabled buttons initially. ([Godot Engine Documentation][6])
3. **Ghost & Placement**: cursor-following ghost; click → validate → stamp preview; Undo/Confirm logic; non-blocking coherency hints.
4. **Alternation & Diffs**: Confirm → diffs → active side flips until all done. ([Wahapedia][1])
5. **Bottom HUD**: phase banner, active side, status text, End Deployment enablement.
6. **Polish**: tooltips, small sounds, error toasts; save/load BoardState snapshot.

---

## 16) References (key behaviors)

* **Deployment rules / alternation / wholly within**: Wahapedia 10e Core/Pariah/Chapter Approved summaries. ([Wahapedia][1])
* **Unit coherency thresholds**: 10e core rules. ([Wahapedia][3])
* **Godot 4.4**: `Camera2D.zoom`, `InputMap` actions, `Polygon2D`, `PanelContainer`, `ItemList/Tree`, Signals & Control. ([Godot Engine Documentation][2])

---

### What you’ll end up with

A crisp, replay-safe **Deployment Phase** that:

* Alternates sides correctly.
* Prevents illegal placements outside DZs.
* Lets players **Undo** per-unit and **Confirm** when complete.
* Locks UI to a single deploying unit at a time (per your spec).
* Writes deterministic diffs to `BoardState` for the rest of your game loop.

If you want, I can turn this into a scaffold (folders, empty scripts, and minimal scenes) next.

[1]: https://wahapedia.ru/wh40k10ed/the-rules/pariah-nexus-battles/?utm_source=chatgpt.com "Pariah Nexus Battles - Wahapedia"
[2]: https://docs.godotengine.org/en/4.4/classes/class_camera2d.html?utm_source=chatgpt.com "Camera2D — Godot Engine (4.4) documentation in English"
[3]: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/?utm_source=chatgpt.com "Core Rules - Wahapedia"
[4]: https://docs.godotengine.org/en/4.4/classes/class_polygon2d.html?utm_source=chatgpt.com "Polygon2D — Godot Engine (4.4) documentation in English"
[5]: https://docs.godotengine.org/en/4.4/classes/class_panelcontainer.html?utm_source=chatgpt.com "PanelContainer — Godot Engine (4.4) documentation in English"
[6]: https://docs.godotengine.org/en/4.4/classes/class_itemlist.html?utm_source=chatgpt.com "ItemList — Godot Engine (4.4) documentation in English"
[7]: https://docs.godotengine.org/en/4.4/classes/class_inputmap.html?utm_source=chatgpt.com "InputMap — Godot Engine (4.4) documentation in English"
[8]: https://docs.godotengine.org/en/4.4/getting_started/step_by_step/signals.html?utm_source=chatgpt.com "Using signals — Godot Engine (4.4) documentation in English"
[9]: https://docs.godotengine.org/en/4.4/tutorials/best_practices/index.html?utm_source=chatgpt.com "Best practices — Godot Engine (4.4) documentation in English"
