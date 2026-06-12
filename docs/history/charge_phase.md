# 🎯 Charge Phase — Detailed Design (Godot 4.4, 40k 10e)

> Scope: implement a complete **Charge phase** MVP consistent with 10e core rules; deterministic, replayable, and cleanly slotted into the existing Action→Result pipeline and UI. We’ll stub optional reactions (e.g., Overwatch) for later.

---

## 1) Player Flow (UX)

1. **Enter Charge Phase**
   PhaseBar updates to “Charge”. All **eligible** friendly units are highlighted (others greyed). An eligible unit:

   * Within **12"** of ≥1 enemy, **did not Advance or Fall Back**, not within Engagement Range, and is not an AIRCRAFT. ([Wahapedia][1])
2. **Select Unit → Select Targets**

   * Right HUD shows the “Charge” panel for the selected unit, with a **target picker** that lists enemy units **within 12"** (LOS not required). Multiple targets may be selected. ([Wahapedia][1])
   * On hover, UI shows required distances to each target’s nearest model (true inches).
3. **Roll 2D6** (single unit’s charge)

   * DiceLog prints `Charge roll: 2D6 = X`. The X becomes the **max inches** each model can move if a Charge move is possible. ([Wahapedia][1])
4. **Charge Path Preview & Validation**

   * Board overlays a **ghost path** from each model. Constraints we must satisfy:

     * End **within Engagement Range (1" horiz / 5" vert)** of **every** declared target.
     * **Never** move within Engagement Range of a unit that was not a declared target.
     * End in **Unit Coherency**.
     * **Base-to-base** with an enemy model **if possible**.
     * Respect terrain movement (see §5.2). ([Wahapedia][1])
5. **Confirm or Fail**

   * If **any condition fails**, the charge **fails** and the unit does not move. If possible, UI explains which check failed (e.g., “Couldn’t reach Engagement Range of all targets while remaining in coherency”). ([Wahapedia][1])
   * If **successful**, apply the move, mark the unit as **Charged** and grant **Fights First** until end of turn. ([Wahapedia][1])
6. **Repeat** for other eligible units or **End Phase**.

> Notes on optional reactions: **Overwatch** exists (Stratagem), can trigger “in your opponent’s Charge phase just after an enemy unit ends a Charge move”. We’ll stub a hook after a successful move to allow future implementation; out-of-scope for MVP resolution. ([Wahapedia][1])

---

## 2) Data Contracts (Actions & Results)

### 2.1 `DeclareChargeAction`

```json
{
  "type": "DECLARE_CHARGE",
  "actor_unit_id": "ASTARTES_INTERCESSORS",
  "payload": {
    "target_unit_ids": ["ORK_BOYZ","ORK_GRETCHIN"]
  }
}
```

**Validation (pure):**

* Actor is eligible (within 12", not Advanced/Fell Back, not already in Engagement Range, not AIRCRAFT).
* Every target is within **12"** of at least one model in the actor (use closest-points). LOS is **not** required. ([Wahapedia][1])

**Result (non-moving):**

* On success: `diffs:[{"op":"set","path":"charges.pending[actor_unit_id]","value":{"targets":[...]} }]`
* On fail: `success:false`, with `log_text` reason.

### 2.2 `ResolveChargeRollAction`

```json
{
  "type": "CHARGE_ROLL",
  "actor_unit_id": "ASTARTES_INTERCESSORS",
  "payload": { "targets": ["ORK_BOYZ","ORK_GRETCHIN"] }
}
```

**Resolution:**

* RNG: `roll_2d6` → `charge_distance_in`
* Attach to `charges.pending[unit_id].distance = X` and advance to pathing.

### 2.3 `ApplyChargeMoveAction`

```json
{
  "type": "APPLY_CHARGE_MOVE",
  "actor_unit_id": "ASTARTES_INTERCESSORS",
  "payload": {
    "per_model_paths": {
      "m1": [[x0,y0],[...],[xN,yN]],
      "m2": ...
    }
  }
}
```

**Validation (pure):**

* For each model, total path length (with vertical/terrain adjustments, §5.2) ≤ `X`.
* Final positions satisfy all **four** conditions: every declared target in ER; no non-target ER; coherency; **base-to-base if possible**.
* If any fails → **charge fails** (no move). ([Wahapedia][1])

**Result (apply):**

* Set model positions.
* Set `unit.flags.charged_this_turn = true`.
* Grant **Fights First** for the turn (flag for Fight phase ordering). ([Wahapedia][1])
* Append DiceLog entry `Charge roll` and `Path validation summary`.

---

## 3) UI Components & States

### 3.1 Right HUD: “Charge Panel”

* **Unit summary** (name, M, keywords).
* **Eligible targets list** with 12" filter; multi-select; per-target **required straight-line** distance preview.
* **Buttons**:

  * `Declare` (enabled if ≥1 target).
  * After roll: `Auto-Path` (engine suggests compliant paths) and `Manual Path` (player drags models).
  * `Confirm Move` / `Cancel (Fail Charge)`.

### 3.2 Board Overlays

* **Eligible Units Highlight** (pulsing outline).
* **Target Highlights** (when selected; include nearest-point marker).
* **Engagement Range rings** (1" aura) for targets during pathing. ([Wahapedia][1])
* **Path Tool**: For each model: draw polyline; show **consumed inches** vs **rolled**. If path crosses forbidden ER (non-target) → segment turns red.
* **“Base-to-base if possible”** helper: when a base can contact, show a small snap ring; snapping is enforced if still satisfying all other conditions. ([Wahapedia][1])

### 3.3 PhaseBar

* “Charge” with **eligible remaining counter**.
* “End Charge Phase” (disabled while a charge is mid-resolution).

### 3.4 DiceLog

* `DECLARE_CHARGE` → “Intercessors declare charge on Boyz, Gretchin.”
* `CHARGE_ROLL` → “2D6 = 9” (seed/index).
* `APPLY_CHARGE_MOVE` → per-model travel inches; validation notes (e.g., “Base-to-base achieved with Boyz; ER with Gretchin achieved”).

---

## 4) Core Algorithms

### 4.1 Eligibility & Targeting

* **Within 12"**: `min_distance(model_i, target_unit) ≤ 12"`. Precompute nearest points using base radii (edge-to-edge).
* **Filters**: state flags (advanced/fell back), current ER, AIRCRAFT constraints. ([Wahapedia][1])

### 4.2 Charge Roll

* `X = sum(d6, d6)`; store `X` in pending charge state. ([Wahapedia][1])

### 4.3 Pathing & Validation

We allow **auto** and **manual** pathing:

**A) Auto-Path (greedy geometric heuristic):**

1. Order enemy targets by ascending nearest distance.
2. For first model moved: try to **snap to base-to-base** with nearest enemy model of first target (if possible), otherwise to ER (1"). For others, maintain **coherency** and attempt base-to-base when possible.
3. Enforce **no ER of non-targets** by clipping the path to avoid their ER disks.
4. Ensure per-model travel ≤ `X`. If a model cannot both keep coherency and achieve all-target ER, **fail**.
5. After all models placed, verify **ER with every declared target** (at least one model per target in ER) and coherency. If any missing, try local adjustments; else fail.

**B) Manual Pathing:**

* Player drags each model; UI shows remaining inches. On `Confirm`, run the **same final validation**.

**Shared Validation Conditions (must all be true):**

* **All-target ER**: Unit ends with ER to **every** declared target.
* **No non-target ER**: Unit never ends within ER of any other enemy unit.
* **Coherency**: Standard coherency at end of move.
* **Base-to-base if possible**: If any charging model **can** contact an enemy while still satisfying the above, it **must**; we check possibility by temporarily snapping and verifying constraints. ([Wahapedia][1])

---

## 5) Movement Geometry Details

### 5.1 Measurement & Inches

* Use existing `Measurement.gd` for in↔px and distances (edge-to-edge using base radii).

### 5.2 Terrain Interactions (10e charge specifics)

* **Over terrain ≤ 2" high**: move as if not there (no extra distance).
* **Terrain > 2"**: model may climb up/down; **vertical distance counts** in total inches; may not end mid-climb.
* **Cannot move through** terrain > 2" (unless special rule); over is OK with vertical accounting.
* **FLY**: measure **through the air**, can move over models; cannot end on top of another model.
  We implement a generic cost function:

```
cost(path) =
  Σ horizontal_segment_lengths
+ Σ vertical_climb_up_down (if >2" terrain crossed)
+ pivot penalties (optional MVP: ignore pivots on round bases; support later)
```

…and disallow ending **mid-climb**. ([Wahapedia][1])

### 5.3 Engagement Range

* ER = **within 1" horizontal / 5" vertical**; we treat 2D MVP as **≤ 1"** in plane (vertical=0), with hooks for vertical maps. ([Wahapedia][1])

### 5.4 Aircraft Constraints

* Actor cannot be **AIRCRAFT**; targets can be AIRCRAFT **only if** the charger can **FLY** (then can end ER with AIRCRAFT). ([Wahapedia][1])

---

## 6) Engine Integration

### 6.1 RulesEngine (new pure helpers)

* `eligible_to_charge(unit_id, board) -> bool`
* `charge_targets_within_12(unit_id, targets, board) -> bool`
* `compute_charge_roll(rng) -> int`
* `validate_charge_paths(unit_id, targets, roll, per_model_paths, board) -> ValidationResult`

  * returns `{ok:bool, reasons:[], auto_fix_suggestions:[]}`

### 6.2 GameManager flow

1. `DECLARE_CHARGE` → validate + stash pending.
2. `CHARGE_ROLL` → roll + stash distance + emit UI event to path.
3. `APPLY_CHARGE_MOVE` → validate; if ok → `apply_result()` (positions + flags + fights first); else → clear pending & log fail.

### 6.3 Replay

* Log `(action, result, rng_cursor)` for each step.
* Rebuild deterministically from pending charge state + roll result + applied diffs.

---

## 7) Godot Scene & Signals

* **BoardView\.gd**

  * `signal charge_targets_hovered(target_ids)`
  * `signal charge_path_updated(unit_id, per_model_paths)`
  * `func draw_charge_overlays(...)`
* **SidePanel.gd (ChargePanel)**

  * `signal declare_charge(unit_id, target_ids)`
  * `signal apply_auto_path(unit_id)`
  * `signal confirm_charge(unit_id, per_model_paths)`
* **TurnManager.gd**

  * Gate **only one** unit in “pathing” at a time; others locked until resolve/fail.

---

## 8) Edge Cases & Rulings

* **Multi-target charges**: must reach ER with **all** declared targets; otherwise **fail**. ([Wahapedia][1])
* **Clipping ER of non-targets**: even momentary end-state in ER of a non-target is illegal; pathing must avoid. ([Wahapedia][1])
* **Base-to-base feasibility**: if any charging model **can** make B2B and all constraints still pass, we must choose such a placement (auto-path bias & manual path validator). ([Wahapedia][1])
* **Coherency**: required at the end of the charge move; if cannot maintain → **fail**. ([Wahapedia][1])
* **Terrain mid-climb end**: forbidden → treat as failure and notify. ([Wahapedia][1])
* **Vertical tables**: MVP treats vertical=0; data model supports elevations for future.

---

## 9) Testing Plan

### 9.1 Unit Tests (pure logic)

* **Eligibility**: advancing/fall back blocks; within 12" true when edge-to-edge ≤12".
* **Roll to Distance**: 2D6 domain; store seed+cursor.
* **Validation Matrix**:

  * Single target, straight lane → success if X ≥ needed.
  * Multi-target: X just enough for first but not second → fail.
  * Non-target ER breach → fail.
  * Base-to-base possible vs not possible → validator enforces when possible.
  * Coherency preservation across N models.
  * Terrain >2": add vertical cost, mid-climb end forbidden.

### 9.2 Integration Tests

* **Charge over ruin 3" high**: require higher roll (horizontal 4.5" + vertical up+down). ([Wahapedia][1])
* **FLY charger** hopping over screen: diagonal “through the air” distance vs ground path. ([Wahapedia][1])
* **Aircraft targeting**: only legal if charger can FLY. ([Wahapedia][1])
* **Overwatch hook**: after successful charge, ensure hook is emitted (no resolution yet).

### 9.3 Golden Replay

* Script: three charges (fail/success/multi-target), verify identical end state and logs when replayed.

---

## 10) Telemetry & UX Polish

* Record **fail reasons** counts (e.g., “insufficient distance”, “non-target ER”, “coherency fail”, “base-to-base unmet”).
* Show **“Why failed?”** tooltip on UI errors with exact condition references to teach users.

---

## 11) Future Hooks (post-MVP)

* **Fire Overwatch Stratagem** resolution window after `APPLY_CHARGE_MOVE` (charging unit finished). ([Wahapedia][1])
* **Charge modifiers** (abilities, terrain specials, rerolls).
* **Pre-measure & auto-suggest least-distance contact points** per target.
* **Advanced movement with pivots (Vehicles/Monsters)** (the core has pivot rules; add later).
* **Vertical terrain & ramp paths** with proper z-costs.

---

## 12) Rule References (key points)

* **Charge sequence, eligibility, LOS not required, 2D6 roll, success conditions, fail conditions, base-to-base if possible, fights first, terrain, flying, aircraft limits.** All from Core Rules: Charge & Fight sections, terrain & ER definitions. ([Wahapedia][1])

**Specific anchors used above:**

* Charge sequence & eligibility; LOS not required; 2D6; all-target ER; no non-target ER; coherency; base-to-base if possible; fights first. ([Wahapedia][1])
* Engagement Range definition (1" horiz / 5" vert). ([Wahapedia][1])
* Charging over terrain and FLY pathing; no mid-climb end. ([Wahapedia][1])
* Aircraft constraints (who can target whom). ([Wahapedia][1])
* Overwatch timing mention (opponent’s Charge phase window hook). ([Wahapedia][1])

---

## 13) Acceptance Criteria (MVP)

* From Charge phase, user can **declare, roll, path, and confirm** charges for any number of eligible units.
* Engine **enforces** all 10e constraints listed above (including **base-to-base if possible**).
* **Deterministic** dice with full **DiceLog**; replay reconstructs exact outcomes.
* **UI** clearly explains failures with actionable reasons.
* Successful chargers gain **Fights First** for the turn and are queued correctly for the Fight phase. ([Wahapedia][1])

Ready to wire into your existing phase state machine and UI scaffolding.

[1]: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/ "Core Rules"
