# 🎯 Shooting Phase — Detailed Design Document (Godot 4.4, 40k 10e)

> Scope: hotseat MVP of the **Shooting** phase only, wired into the modular architecture you already have. Keeps previous invariants (top-down board, tokens, deterministic RNG, Light Cover MVP). All references to 10e rules are cited.

---

## 1) What counts as “correct” (10e core)

We implement the official attack sequence and targeting constraints:

* **Select targets for all ranged weapons before resolving any attacks**; a model may shoot different weapons at different targets but **cannot split a single weapon’s attacks** across multiple targets. At least one model in each target unit must be **visible** and **in range** of the attacking model/weapon. Models in the same unit may target different units. ([Wahapedia][1])
* **Allocate & resolve attacks** per the standard sequence: Hit → Wound → Allocate → Save → Inflict Damage. **If a model in the target unit already has lost wounds / had attacks allocated this phase, allocate to that model first**. ([Wahapedia][1])
* **Saving throws**: roll D6, modify by **AP**, **unmodified 1 fails**, **total save improvement capped at +1**; **invulnerable** may be chosen instead of normal and **is never modified by AP**. ([Wahapedia][1])
* **Benefit of Cover (Light Cover MVP)**: **+1 to armour** saves vs **ranged** attacks; **does not affect invulnerable**; non-cumulative; models with **3+ or better Save do not gain it vs AP 0**. ([Wahapedia][1])

> MVP simplifications (same spirit as your PRP):
> • Ignore Dense/Heavy cover effects; only “Benefit of Cover” (+1, cap +1 net).
> • Basic LoS (center-to-center segment vs “obscuring” rectangles).
> • No re-rolls, no special weapon keywords (Blast, Sustained Hits, etc.) yet.
> • Damage overflow **does not spill** between models (10e default). ([Wahapedia][1])

---

## 2) UX / UI

### 2.1 Board & Selection (existing BoardView)

* Click a **friendly unit** → becomes **Active Shooter**; board highlights:

  * **Eligible enemy units** in **green** (visible & in range by any model/weapon).
  * **Ineligible** in **grey** with tooltip explaining why (no LoS / out of range).
* Hover an enemy unit → line overlays from each firing model to that unit’s **closest visible model**; show **range** (inches) per weapon.

### 2.2 Right Side Panel (contextual)

* **Unit loadout list** (per model optional, per weapon aggregated). Use **Tree/ItemList** to render “Model(s) → Weapon profiles” with target pickers. ([Godot Engine Documentation][2])
* **Target basket**: shows current **target assignments** (“5x Bolt Rifles → Ork Boyz”, “1x Plasma → Trukk”).

  * Buttons: **\[Clear]** (reset this weapon), **\[Clear All]**, **\[Confirm Targets]**.
* After confirmation, panel switches to **Resolution View** with a stepper: Hit → Wound → Save → Damage.

  * **Dice Log** mirrors verbose breakdown (existing component).

### 2.3 Bottom HUD (collapsible)

* Phase controls: **\[Back to Movement]** (disabled), **\[End Shooting]** (enabled when all resolving is done).
* **Settings** (dice verbosity toggle).
* **Ruler** toggle to pre-measure ranges.

> Implementation notes: drive UI with Godot **signals**; weapons & targets chosen emit `targets_confirmed(actor_unit_id, selections)`. ([Godot Engine Documentation][3])

---

## 3) Data: intents & outcomes

### 3.1 User Intent (“ShootAction”)

```json
{
  "type": "SHOOT",
  "actor_unit_id": "ASTARTES_INTERCESSORS",
  "payload": {
    "assignments": [
      {
        "model_ids": ["m1","m2","m3","m4","m5"],     // optional if homogeneous
        "weapon_id": "bolt_rifle",
        "target_unit_id": "ORK_BOYZ",
        "attacks_override": null                     // null → use profile
      },
      {
        "model_ids": ["sarge"],
        "weapon_id": "plasma_pistol",
        "target_unit_id": "ORK_BOYZ"
      }
    ]
  }
}
```

RulesEngine validates that no weapon’s **single attack pool** is split across multiple targets as per core rules. ([Wahapedia][1])

### 3.2 Engine Result (authoritative)

```json
{
  "success": true,
  "phase": "SHOOTING",
  "diffs": [
    {"op":"set","path":"units.ORK_BOYZ.models.m2.wounds","value":0},
    {"op":"remove","path":"units.ORK_BOYZ.models.m2"}
  ],
  "dice": [
    {"context":"to_hit","threshold":"3+","rolls_raw":[6,5,4,2,1],"successes":3},
    {"context":"to_wound","threshold":"4+","rolls_raw":[6,2,3],"successes":1},
    {"context":"save","sv":"6+","ap":0,"cover":"+1 (capped)","rolls_raw":[2],"fails":1}
  ],
  "log_text":"Intercessors → Ork Boyz: 3 hits, 1 wound, 1 failed save → 1 slain."
}
```

---

## 4) Validation & rules logic

### 4.1 Target eligibility

For each `(attacking model, weapon, target unit)`:

1. **Visibility**: LoS segment from attacker center to **any** model in the target unit is unobstructed by “obscuring” terrain (MVP rectangle intersection).
2. **Range**: distance to that **visible model** ≤ weapon range.
3. **Engagement**: (MVP) if the **attacker’s unit** is within Engagement Range of enemies, it **cannot** shoot (Pistols/Monsters/Vehicles handling is future).
4. Aggregate: a target is **eligible** if **at least one** attacking model with that weapon has LoS **and** range. ([Wahapedia][1])

### 4.2 Attack generation

For each assignment:

* Compute **attacks** = sum of weapon A profiles across assigned models (flat integer in MVP).
* Record **S, AP, D, BS** from profile; pull **defender T** from the **unit** (10e wounds vs **unit Toughness**). ([Reddit][4])

### 4.3 Sequence & maths (MVP)

* **To-Hit**: roll `n = attacks` × d6; success on `>= BS` (apply future modifiers here).
* **To-Wound**: use S vs T table (standard ≥ / ≤ relation).
* **Allocate**: defender allocates each successful wound to **a model**; if a model already had wounds/allocations this phase, it **must** continue receiving them. (MVP allocates front-most model for automation; keep hook for later manual allocation). ([Wahapedia][1])
* **Save**:

  * Base: compare to **Sv**; apply **AP** as negative modifier.
  * **Cover**: if target model has Benefit of Cover, add **+1** to **armour** save only; **never** to invuln; note **save improvements capped at +1 total**. ([Wahapedia][1])
  * **Invuln**: choose better of (modified armour, invuln). Invuln **ignores AP**. ([Wahapedia][1])
* **Damage**: each failed save inflicts `D` wounds; if model hits 0, remove; **excess is lost**. ([Wahapedia][1])

---

## 5) Systems & APIs

### 5.1 `RulesEngine.gd` (new/expanded)

```gdscript
# Public entry:
static func resolve_shoot(action: Dictionary, board: Dictionary, rng: RNGService) -> Dictionary

# Helpers:
static func validate_shoot(action, board) -> ValidationReport
static func compute_visible_models(attacker_model, target_unit, terrain) -> Array
static func attacks_for_assignment(assignment, board) -> AttackPool
static func bs_success(roll:int, bs:int, mods:int) -> bool
static func wound_threshold(str:int, tough:int) -> int        # returns 2..6
static func compute_cover(model, pos, terrain) -> bool        # MVP Light Cover
static func save_needed(sv:int, ap:int, cover:bool, inv:int) -> { "armour":int, "inv":int, "cap":2 }
```

> **Save cap rule**: after applying AP and (maybe) +1 for cover, clamp improvement so that **net modifiers cannot exceed +1**, and saves cannot be better than **2+**. Both clauses are from core rules/cover. ([Wahapedia][1])

### 5.2 `GameManager.gd`

* `request_action(action)` → `RulesEngine.validate_shoot` → `resolve_shoot` → `apply_result(diffs)`; emit `result_applied`.

### 5.3 `BoardView.gd`

* `highlight_targets(actor_unit_id)`; draws per-weapon range halos for hovered targets; displays LoS lines.
* Emits `target_chosen(weapon_id, target_unit_id)`; uses **signals** to sync with Right Panel. ([Godot Engine Documentation][3])

### 5.4 `SidePanel.gd` (Shooting mode)

* Renders **Tree**:

  * Node: *Weapon* (count of models with that weapon).
  * Child: *Target selector* (dropdown of eligible enemy units).
* Buttons: **Confirm Targets**, **Clear**, **Clear All**. Uses **Tree/TreeItem** buttons API. ([Godot Engine Documentation][2])

---

## 6) LoS & Cover (MVP geometry)

* **LoS**: segment `(attacker_pos → closest point of any target model)`; **false** if intersects any terrain with tag `obscuring`.
* **Benefit of Cover**: **true** if target model’s position is **inside** a terrain polygon tagged `light_cover` **or** the LoS segment crosses such terrain with the target **behind** it (simple “shield” heuristic). When true, attempt +1 to armour save, then apply **cap**. **Never** modify invuln. ([Wahapedia][1])

---

## 7) State machine (Shooting Phase)

1. **Enter**: set `phase="SHOOTING"`, compute & cache eligibility map.
2. **Select Shooter**: player picks a friendly unit with ranged weapons and not disallowed.
3. **Assign Targets**: per weapon (no intra-weapon split). UI enforces rule. ([Wahapedia][1])
4. **Confirm**: build `SHOOT` action (deterministic order: by target, then weapon id).
5. **Resolve**:

   * For each assignment (resolve **one target at a time**): roll Hit → Wound → Save → Damage; append dice blocks; produce diffs.
6. **Apply & Log**: `apply_result`, DiceLog update.
7. **Repeat / End**: player may select another shooter; or **End Shooting** to advance phase.

---

## 8) Edge cases (handled now)

* **Mixed Saves** in target: per-model Sv / invuln; choose best each time. ([Wahapedia][1])
* **AP 0 vs Save 3+ with Cover**: **no cover benefit** per rule text. ([Wahapedia][1])
* **Previously wounded model**: further allocations must go to it first this phase. (We track `allocation_focus_model_id` transiently per unit for the current phase.) ([Wahapedia][1])
* **Save improvement cap**: any combo (cover, other future buffs) cumulatively **≤ +1**. ([Wahapedia][1])

---

## 9) Dice log format (verbose → compact toggle)

* **To-Hit**: threshold, raw rolls, rerolls (future), successes.
* **To-Wound**: S, T, threshold table outcome, rolls, successes.
* **Saves**: for each allocated wound → which model, armour vs invuln chosen, AP, **cover applied? (Y/N)**, **cap applied? (Y/N)**, result.
* **Damage**: wounds lost, model removed.

---

## 10) Godot scene wiring

```
ui/
  ├── ShootingPanel.tscn (extends SidePanel)
  │   └── Tree (targets)
  ├── DiceLogPanel.tscn
  └── PhaseBar.tscn
```

Signal graph (examples):
`BoardView.unit_clicked → GameManager.set_active_shooter`
`ShootingPanel.targets_confirmed → GameManager.request_action(SHOOT)`
`GameManager.result_applied → BoardView.refresh_tokens, DiceLogPanel.append`

Use Godot **UI tutorials** for control layout, and **signals** to keep code decoupled. ([Godot Engine Documentation][5])

---

## 11) Testing

### Unit tests (pure logic)

* **wound\_threshold(S,T)** matrix (2+/3+/4+/5+/6+).
* **save\_needed**: AP stacks, cover +1, **cap** enforced; invuln choice.
* **cover\_applicability**: inside polygon vs through-cover heuristic.
* **allocation rule**: previously wounded model continues to receive allocations. ([Wahapedia][1])

### Integration tests

* **AP 0 vs Save 3+ in Cover** → no bonus. ([Wahapedia][1])
* **Invuln present** → AP ignored if invuln chosen. ([Wahapedia][1])
* **No LoS** → target not offered.
* **Multiple weapons, single target & multi-target**; prevent **splitting a single weapon** pool. ([Wahapedia][1])

---

## 12) Pseudocode (critical paths)

```gdscript
# Resolve one assignment (weapon → target)
func resolve_assignment(pool: AttackPool, board: Dictionary, rng: RNGService) -> AssignmentResult:
    var hit_rolls = rng.roll_d6(pool.attacks)
    var hits = hit_rolls.filter(func(r): return r >= pool.bs)  # mods later

    var wound_th = wound_threshold(pool.str, pool.target_t)
    var wound_rolls = rng.roll_d6(hits.size())
    var wounds = wound_rolls.filter(func(r): return r >= wound_th)

    var diffs := []
    var save_events := []
    for i in wounds.size():
        var target_model = select_allocation_model(pool.target_unit_id)  # respects "continue allocating"
        var has_cover = compute_cover(target_model, target_model.pos, board.terrain)
        var armour_needed = pool.target_sv - pool.ap - (has_cover ? 1 : 0)
        armour_needed = clamp(armour_needed, 2, 7) # 2+ best, 7 means impossible
        # Cap: overall improvement ≤ +1 is enforced by subtracting only up to +1 net above baseline
        var inv_needed = pool.target_inv if pool.target_inv > 0 else 99
        var use_inv = inv_needed < armour_needed
        var roll = rng.roll_d6(1)[0]
        var saved = use_inv ? roll >= inv_needed : roll >= armour_needed
        save_events.append({ ... context ... })

        if not saved:
            diffs += apply_damage(target_model, pool.damage) # remove if <= 0
    return { "diffs": diffs, "dice": build_dice_blocks(hit_rolls, wound_rolls, save_events) }
```

> Note: the **“+1 cap”** is enforced at the **total** save modifier level (cover and future buffs cannot exceed +1); implement by computing the baseline (`sv - ap`) and then allowing at most **+1** net improvement over that baseline. ([Wahapedia][1])

---

## 13) Sprint checklist (Shooting slice)

**S-S1 — Targeting UI & validation**

* Compute eligibility map; UI affordances to pick targets per weapon; prevent intra-weapon split. ([Wahapedia][1])

**S-S2 — Resolver & DiceLog**

* Implement attack pipeline; detailed log; apply diffs; selection automatically clears dead models.

**S-S3 — Cover & Cap**

* Light Cover detection; add +1 armour only; implement global **+1 save cap**; invuln choice. ([Wahapedia][1])

**S-S4 — Tests & polish**

* Unit + integration tests above; performance pass for large dice pools.

---

## 14) Future toggles (post-MVP)

* Weapon keywords (Blast, Sustained Hits, Lethal Hits, Twin-linked), **rerolls**, **Precision**, **Hazardous**, **Devastating Wounds**, **Mortal Wounds timing** (already scaffolded by dice blocks). ([Wahapedia][1])
* Pistol exceptions, Monsters/Vehicles shooting while engaged. ([Wahapedia][1])
* Dense/Heavy/Obscuring fidelity; ignore-cover rules taxonomy. ([Wahapedia][6])
* Manual defender allocation UI (models behind walls can still die; defender chooses). ([Wahapedia][1])

---

### References

* **Core Rules — 10e**: targeting & weapon assignment; save sequence; invulnerable/cover; allocation and caps. ([Wahapedia][1])
* **Wahapedia quick start / context**. ([Wahapedia][7])
* **Godot 4.4 UI/Signals/Tree/ItemList docs**. ([Godot Engine Documentation][5])

If you want, I can turn this into a scaffolded `ShootingPanel.tscn + ShootingPanel.gd` and the corresponding `RulesEngine.resolve_shoot()` stub so you can drop it straight in.

[1]: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/ "Core Rules"
[2]: https://docs.godotengine.org/en/4.4/classes/class_tree.html?utm_source=chatgpt.com "Tree — Godot Engine (4.4) documentation in English"
[3]: https://docs.godotengine.org/en/4.4/getting_started/step_by_step/signals.html?utm_source=chatgpt.com "Using signals — Godot Engine (4.4) documentation in English"
[4]: https://www.reddit.com/r/WarhammerCompetitive/comments/1caa104/weekly_question_thread_rules_comp_qs/?utm_source=chatgpt.com "Weekly Question Thread - Rules & Comp Qs - Reddit"
[5]: https://docs.godotengine.org/en/4.4/tutorials/ui/index.html?utm_source=chatgpt.com "User interface (UI) — Godot Engine (4.4) documentation in English"
[6]: https://wahapedia.ru/wh40k10ed/the-rules/rules-appendix/?utm_source=chatgpt.com "Rules Appendix - Wahapedia"
[7]: https://wahapedia.ru/wh40k10ed/the-rules/quick-start-guide/?utm_source=chatgpt.com "Quick Start Guide - Wahapedia"
