# Warhammer 40,000 — 10th → 11th Edition Rules Delta Audit

**Date:** 2026-06-10
**Branch:** `claude/read-this-g3wm44`
**Source of truth (target spec):** the uploaded 11th-edition Core Rules PDF
(`warhammer40k_core_rules8.txt`). Rule numbers below (e.g. `12.06`) reference
that document.
**Audited codebase:** `/home/user/warhammer-40k-godot/40k` (implements 10th edition).

---

## 0. How to read this document

Each delta is a self-contained work item with a stable ID (`CMD-1`, `MOV-2`, …)
containing:

- **Rule** — the 11th-edition rule reference.
- **Severity** — rules-correctness impact (see legend).
- **Current behavior** — what the code does today, with `file:line` evidence.
- **Required behavior (11th ed)** — the target spec.
- **Proposed solution** — concrete implementation approach.
- **Validation criteria** — how we prove it's fixed. Per the project gate
  (`CLAUDE.md`, `tests/TESTING_METHODOLOGY.md`): pure-math/state changes may be
  validated headless (`tests/unit/test_*.gd`, `tests/run_pretrigger_tests.sh`);
  **anything with a UI affordance must add/extend a windowed scenario**
  (`tests/scenarios/sp/<id>.json`, run via `bash 40k/tests/run_scenarios.sh …`)
  and pass the in-game MCP `verify_delivery` gate.

### Severity legend

| Severity | Meaning |
|----------|---------|
| 🔴 **Critical** | Produces wrong game outcomes in common situations (wins/losses differ). Fix first. |
| 🟠 **High** | New core mechanic or a rule used most games; absence/wrongness is frequently visible. |
| 🟡 **Medium** | Real rules gap but situational, or a rename/edge interaction. |
| 🟢 **Low** | Cosmetic, rare edge case, or naming only. |

### Scope caveat

The provided PDF differs from the public 10th-edition core rules in a number of
places (new keywords `MOBILE`/`TOWERING`/`SUPPORT`, reworked terrain categories,
mode-based fall-back/disembark/consolidation, `[CLEAVE]`, `[CLOSE-QUARTERS]`,
overrun fights, surge moves, renamed/changed stratagems, and a changed
Benefit-of-Cover mechanic). This audit treats the PDF as authoritative and flags
every place the code diverges from it — including rules the code currently
implements "correctly for 10th."

---

## 1. Executive summary

**28 deltas** identified across 9 subsystems. Headline items:

| # | Delta | Severity |
|---|-------|----------|
| WPN-1 | `[DEVASTATING WOUNDS]` mortal wounds **spill across models** (should cap one model per critical wound) | 🔴 Critical |
| CMD-1 | Battle-shock **does not persist / recover** across turns (cleared each Command phase) | 🔴 Critical |
| TER-2 | Benefit of Cover **improves save +1** instead of **worsening attack BS by 1** | 🟠 High |
| TER-1 | No **Exposed/Light/Dense** terrain categories (only height tiers) — blocks MOBILE, cover, hidden | 🟠 High |
| MOV-1 | Fall-back has no **Ordered Retreat / Desperate Escape** modes; uses death rolls not hazard rolls | 🟠 High |
| SHO-1 | No **`[CLOSE-QUARTERS]`** keyword or close-quarters shooting type (only legacy `[PISTOL]`) | 🟠 High |
| FGT-1 | **Overrun fight** (12.06) entirely missing | 🟠 High |
| FGT-2 | **Engaging Consolidation** does not pull newly-engaged units into the fight | 🟠 High |
| TRN-1 | **Disembark modes** (Rapid/Tactical/Combat 6"+battle-shock) missing | 🟠 High |
| TRN-3 | **SUPPORT** unit ability — second attachment slot alongside Leader — missing | 🟠 High |

**Already compliant (verified, no action):** Gain Core CP both players (08.02),
Leadership roll uses best Ld (01.06), half-strength math incl. attached units
(Appendix), Advance/Normal/Remain Stationary basics, FLY through models/terrain,
Pile-in (12.03), Fights First ordering (12.04), Charge basics (11.02–11.04),
Embark (18.02), Firing Deck (24.14), attached-unit Toughness selection &
destroy-trigger (19.02–19.04), snap shooting (15.09), and the bulk of section-24
weapon abilities (`[ANTI]`, `[BLAST]`, `[LETHAL HITS]`, `[SUSTAINED HITS]`,
`[RAPID FIRE]`, `[MELTA]`, `[TORRENT]`, `[TWIN-LINKED]`, `[LANCE]`, `[PRECISION]`,
`[HAZARDOUS]`, `[HEAVY]`, `[IGNORES COVER]`, `[INDIRECT FIRE]`, FNP, `[ONE SHOT]`,
`[EXTRA ATTACKS]`, Deadly Demise, Deep Strike, Infiltrators, Scouts, Stealth,
Lone Operative, Leader).

---

## 2. Command phase & battle-shock

### CMD-1 — Battle-shock must persist and be recovered (not cleared each turn)
- **Rule:** 08.03 / 01.07
- **Severity:** 🔴 Critical
- **Current behavior:** Battle-shocked flags are **cleared at the start of every
  Command phase** (`phases/CommandPhase.gd:204-222`, `_clear_battle_shocked_flags()`),
  then tests are run only for below-half-strength units
  (`CommandPhase.gd:92-96`, `_identify_units_needing_tests()` →
  `GameState.is_below_half_strength_combined()`). There is no recovery roll for
  an already-shocked unit because the status never survives into the next turn.
- **Required behavior (11th ed):** A battle-shocked unit **stays** battle-shocked
  across turns. In the Battle-shock step the active player rolls **2D6 ≥ Ld** for
  every unit that is **either** currently battle-shocked **or** at/below
  half-strength. A unit that was battle-shocked at the start of the step and
  *passes* its roll stops being battle-shocked; an eligible unit that *fails*
  becomes (or stays) battle-shocked.
- **Proposed solution:**
  1. Delete/disable `_clear_battle_shocked_flags()`.
  2. In `_identify_units_needing_tests()` include units where
     `flags.battle_shocked == true` **OR** `is_below_half_strength_combined()`.
  3. On roll: pass → set `battle_shocked = false`; fail → set `battle_shocked = true`.
     (A currently-shocked unit that fails simply remains shocked.)
  4. Keep the flag in saved/serialized state (verify `StateSerializer` round-trips it).
- **Validation criteria:**
  - Headless `tests/unit/test_battleshock_persistence.gd`: shock a unit, advance a
    full turn cycle, assert flag still `true` at next Command phase; force a passing
    roll, assert flag clears; force a failing roll on a healthy-but-shocked unit,
    assert it stays shocked.
  - Save/load round-trip test: shock a unit, save, load, assert flag preserved.
  - Windowed scenario `tests/scenarios/sp/<id>_battleshock_persists.json`: drive
    two Command phases and assert OC/flag state via `get_node_info`.

### CMD-2 — Battle-shocked units cannot start/complete actions
- **Rule:** 01.07 (also Actions 16.01)
- **Severity:** 🟡 Medium
- **Current behavior:** OC→'-' is enforced (`MissionManager.gd:206-209`) and
  stratagem-targeting is blocked (`StratagemManager.gd:672-687`), but **no check
  prevents a battle-shocked unit from starting or completing an action**.
- **Required behavior:** A battle-shocked unit is not eligible to start an action,
  and any action it has started cannot be completed.
- **Proposed solution:** Add `flags.battle_shocked` to the action-eligibility
  predicate wherever actions are started (search the actions/secondary-mission
  flow, e.g. `SecondaryMissionManager.gd` and any `start_action` validators), and
  fail completion if the unit became shocked mid-action.
- **Validation criteria:** Headless test: shock a unit eligible for an action,
  assert `can_start_action == false`; start an action then shock the unit, assert
  it does not complete and yields no reward.

---

## 3. Movement phase

### MOV-1 — Fall-back modes: Ordered Retreat vs Desperate Escape (hazard rolls)
- **Rule:** 09.07 (hazard roll 06.03)
- **Severity:** 🟠 High
- **Current behavior:** Single unconditional fall-back
  (`MovementPhase.gd:894-923` validate, `3912-3972` process). "Desperate Escape"
  exists (`MovementPhase.gd:5262-5370`) but is a **binary death roll** (model
  destroyed on 1-2, or 1-3 if battle-shocked) applied only to models that crossed
  enemies / when shocked. No mode selection; no mortal-wound hazard roll; no
  post-move battle-shock roll.
- **Required behavior (11th ed):** Before moving, select a mode:
  - **Ordered Retreat** — only if the unit is *not* battle-shocked; no penalty.
  - **Desperate Escape** — mandatory otherwise. Make a **hazard roll per model**
    (D6: 1-2 → unit suffers 1 mortal wound; 3 MW if every model is MONSTER/VEHICLE).
    Models may move through enemy models. After moving, if the unit is not
    battle-shocked it must make a battle-shock roll.
- **Proposed solution:**
  1. Add a mode-selection step (UI: two buttons gated on `battle_shocked`).
  2. Replace the death-roll loop with `RulesEngine.hazard_roll()` per model
     accumulating mortal wounds (reuse the mortal-wound application path so FNP etc.
     apply), with the MONSTER/VEHICLE ×3 branch.
  3. After a Desperate Escape move on a non-shocked unit, trigger a battle-shock roll.
- **Validation criteria:**
  - Headless `test_fall_back_modes.gd`: non-shocked unit can pick Ordered Retreat
    (no MW); shocked unit forced into Desperate Escape; assert hazard MW count and
    that an all-MONSTER unit takes 3 MW per failed roll; assert post-move
    battle-shock roll fires.
  - Windowed scenario driving a real fall-back and asserting the mode dialog +
    resulting wounds via `capture_screenshot` / `get_node_info`.

### MOV-2 — Surge move must force movement toward the surge target
- **Rule:** 21.01-21.02
- **Severity:** 🟡 Medium
- **Current behavior:** Surge exists with correct eligibility (once/phase, not
  battle-shocked, unengaged) and D6 distance (`MovementPhase.gd:5856-5999`), but
  **no targeting constraint** — models may move freely within the cap. Comment at
  `:5920` acknowledges the missing "as close as possible to closest enemy" rule.
- **Required behavior:** Select the **closest** enemy unit as surge target; each
  model must end engaged with it if possible, otherwise as close as possible; the
  unit cannot end engaged with non-target units.
- **Proposed solution:** Compute closest enemy at surge start; constrain/auto-path
  per-model end positions toward it (mirror the charge "must end closer / engaged
  if able" validators in `ChargePhase.gd`).
- **Validation criteria:** Headless `test_surge_move_targeting.gd`: assert each
  moved model's end distance to target ≤ start distance and engagement achieved
  when geometrically possible; assert rejection if a model ends engaged with a
  non-target unit.

### MOV-3 — `MOBILE` keyword + Dense-terrain horizontal movement
- **Rule:** 13.06, 24.35 (depends on TER-1)
- **Severity:** 🟠 High
- **Current behavior:** No reference to `MOBILE` anywhere. Terrain traversal is
  hardcoded by model type (`TerrainManager.gd:279-295`,
  `can_move_through: {INFANTRY:true, VEHICLE:false, MONSTER:false}`) with no
  density concept.
- **Required behavior:** `INFANTRY/BEASTS/SWARM/MOBILE` may move **horizontally**
  through Dense terrain; other models only if the crossed sections are ≤2" tall
  (else must move vertically). `MOBILE` is a grantable keyword (see WPN-4).
- **Proposed solution:** After TER-1 lands (density on terrain pieces), rewrite the
  traversal predicate to test density + model keywords incl. `MOBILE`, and the
  ≤2" section-height rule for non-infantry.
- **Validation criteria:** Headless `test_dense_terrain_movement.gd`: INFANTRY and
  a MOBILE-tagged vehicle pass through a Dense piece horizontally; a plain vehicle
  is blocked by a >2" Dense section but may climb. Windowed scenario moving a model
  through a ruin.

### MOV-4 — FLY "take to the skies" −2" distance
- **Rule:** 21.03
- **Severity:** 🟡 Medium
- **Current behavior:** FLY correctly ignores vertical distance and moves through
  models/terrain (`MovementPhase.gd:963/1108/1125`, `TerrainManager.gd:389`), but
  **does not subtract 2"** from the max distance when flying.
- **Required behavior:** When a unit declares it takes to the skies, subtract 2"
  from that move's maximum distance (unless it has HOVER — see WPN-5).
- **Proposed solution:** Add a "take to the skies" declaration per move; when set,
  reduce the cap by 2" (skip the reduction if HOVER). Note: today FLY traversal is
  always-on; 11th ed makes the model/terrain pass-through *conditional* on the
  declaration — consider gating it on the declaration for full correctness.
- **Validation criteria:** Headless `test_fly_take_to_skies.gd`: cap reduced by 2";
  HOVER unit unaffected. Windowed scenario optional.

---

## 4. Shooting phase

### SHO-1 — `[CLOSE-QUARTERS]` keyword + close-quarters shooting type (replaces `[PISTOL]`)
- **Rule:** 10.06, 24.07, 24.27
- **Severity:** 🟠 High
- **Current behavior:** Only `[PISTOL]` is recognized
  (`RulesEngine.gd:4886`, `is_pistol_weapon()`; consumed at
  `ShootingController.gd:1031`). Engaged non-MONSTER/VEHICLE units may fire pistols
  at any engaged target (`ShootingPhase.gd:643-651`). No `[CLOSE-QUARTERS]`
  keyword; no notion of selectable "shooting types."
- **Required behavior:** `[PISTOL]` is superseded by and **identical to**
  `[CLOSE-QUARTERS]`. "Close-quarters shooting" (10.06) is a distinct shooting type
  available to engaged units (and MONSTER/VEHICLE units), restricting targets to
  units you're engaged with; non-MONSTER/VEHICLE models may only fire
  `[CLOSE-QUARTERS]` weapons.
- **Proposed solution:**
  1. Make `is_pistol_weapon()` (rename to `is_close_quarters_weapon()`, keep alias)
     match **either** `PISTOL` or `CLOSE-QUARTERS`/`CLOSE_QUARTERS`.
  2. Keep the existing engaged-target restriction (already correct at `:643-651`),
     swap the keyword gate to the new predicate.
  3. (Design) introduce an explicit `shooting_type` selection so Assault / Indirect
     / Close-quarters are chosen rather than inferred (also helps SHO-2/SHO-3).
- **Validation criteria:** Headless `test_close_quarters_keyword.gd`: a weapon
  tagged `CLOSE-QUARTERS` behaves identically to one tagged `PISTOL` (engaged unit
  may fire it only at engaged targets; non-CQ weapons disabled). Windowed scenario:
  open the shooting UI with an engaged unit and confirm only CQ weapons are
  selectable (extend existing `sp/*engagement*` scenarios).

### SHO-2 — Shooting **at** an engaged MONSTER/VEHICLE: −1 to hit + `[BLAST]` ban
- **Rule:** 17.03
- **Severity:** 🟡 Medium
- **Current behavior:** The shooter-side "Big Guns Never Tire" penalty exists
  (`RulesEngine.gd:5202-5226`), but there is **no −1-to-hit when the target is an
  engaged MONSTER/VEHICLE**, and no rule preventing `[BLAST]` from targeting an
  engaged unit.
- **Required behavior:** Each ranged attack targeting an engaged MONSTER/VEHICLE
  gets −1 to hit (except `[CLOSE-QUARTERS]` attacks by a unit engaged with the
  target). `[BLAST]` weapons can never target a unit that is engaged.
- **Proposed solution:** In hit-modifier assembly, add −1 when the target unit is
  engaged and is MONSTER/VEHICLE (with the CQ exception). In target-eligibility,
  reject `[BLAST]` weapons against any engaged target unit.
- **Validation criteria:** Headless `test_shoot_engaged_mv.gd`: −1 applied;
  CQ-from-engaged exempt; `[BLAST]` rejected vs engaged target but allowed vs an
  unengaged one.

### SHO-3 — Indirect fire: stationary-and-visible relaxes 1-5 → 1-3
- **Rule:** 10.07
- **Severity:** 🟢 Low
- **Current behavior:** Indirect applies cover, no hit re-rolls, and unmodified
  1-3 fail (`RulesEngine.gd:1725-1726`). But the rule's two-tier threshold isn't
  modeled: when *not* meeting the stationary+visible condition, unmodified **1-5**
  should fail.
- **Required behavior:** Default unmodified **1-5 fail** for indirect attacks on a
  non-visible target; **1-3 fail** only if the firing unit remained stationary and
  the target is visible to ≥1 friendly unit.
- **Proposed solution:** Branch the indirect fail-threshold on
  `remained_stationary AND target_visible_to_any_friendly`.
- **Validation criteria:** Headless `test_indirect_thresholds.gd` covering both
  branches.

---

## 5. Charge & fight phases

### FGT-1 — Overrun fight
- **Rule:** 12.06
- **Severity:** 🟠 High
- **Current behavior:** No `overrun` logic anywhere (`FightPhase.gd`). Only the
  10th-ed pile-in → fight → consolidate flow exists.
- **Required behavior:** A unit that is unengaged but **was engaged at the start of
  the Fight step (or became engaged during the phase)** may make an overrun fight:
  one **additional pile-in move**, then fight. Such units must be selectable in the
  Fight sequence.
- **Proposed solution:** Track per-unit "engaged at start of Fight step" and
  "became engaged this phase" state. Add an overrun fight type that grants an extra
  pile-in before the attack resolution, and include these units in fight
  eligibility/ordering.
- **Validation criteria:** Headless `test_overrun_fight.gd`: a unit whose target
  died (leaving it unengaged) but was engaged at step start can overrun-pile-in
  into a new enemy and fight it. Windowed scenario reproducing the PDF's example
  (12.05/12.06 figure).

### FGT-2 — Consolidation modes (esp. Engaging Consolidation pulling units into the fight)
- **Rule:** 12.07-12.08
- **Severity:** 🟠 High
- **Current behavior:** A 2-mode approximation exists
  (`FightPhase.gd:833-854`, `_determine_consolidate_mode()` → `ENGAGEMENT` /
  `OBJECTIVE` / `NONE`). Newly-eligible units are scanned **after** consolidation
  (`:3089-3102`), not selected-to-fight *as a consequence of* the consolidation
  move.
- **Required behavior:** Three ordered, mutually-exclusive modes:
  - **Ongoing Consolidation** (if engaged) — move toward closest selected enemy;
    base-contact models can't move.
  - **Engaging Consolidation** (else if within 3" of enemy) — must end engaged with
    selected enemies; **any newly-engaged unit that hasn't fought becomes eligible
    and is immediately selected to fight.**
  - **Objective Consolidation** (else if within 3" of objective) — end within range.
- **Proposed solution:** Implement explicit mode selection in the documented order;
  for Engaging Consolidation, after the move enqueue each newly-engaged,
  not-yet-fought enemy into the fight sequence (opponent selects order) per 12.08.
- **Validation criteria:** Headless `test_consolidation_modes.gd`: assert correct
  mode chosen by the priority ladder; assert Engaging Consolidation adds a new
  enemy to the active fight queue and it then fights. Windowed scenario for the
  "new foes to face" case.

### FGT-3 — "Eligible to fight but unable to fight" pass
- **Rule:** Appendix (Eligible to Fight, But Unable to Fight)
- **Severity:** 🟢 Low
- **Current behavior:** No pass mechanism found in `FightPhase.gd`.
- **Required behavior:** If all of a player's fight-eligible units are >5" from all
  enemies, that player may pass and hand the sequence back; if both pass in
  succession (or one passes with the opponent having no eligible units) the Fight
  step ends.
- **Proposed solution:** Add a "pass" branch in the alternating fight selection when
  every eligible unit is >5" from all enemies; end the step on mutual pass.
- **Validation criteria:** Headless `test_fight_pass.gd`: construct the >5" stalemate
  and assert the step terminates without forcing an impossible fight.

### CHG-1 / STR-3 — Heroic Intervention two modes ("Leap to Defend" / "Into the Fray")
- **Rule:** 15.11
- **Severity:** 🟡 Medium
- **Current behavior:** Single-mode counter-charge that always targets only the
  charging enemy with a plain 2D6 roll (`ChargePhase.gd:2785-3063`;
  `StratagemManager.gd:302-328`). CP already correctly 1CP; WALKER restriction
  present.
- **Required behavior:** Before the charge roll, pick a mode:
  - **Leap to Defend** — may only select enemy units that *charged this phase* and
    are within max distance.
  - **Into the Fray** — cap the charge roll at 6 (after modifiers); may select any
    enemy within 6" and within max distance.
- **Proposed solution:** Add mode selection to the Heroic Intervention flow; apply
  the target-eligibility filter (charged-this-phase vs within-6") and the roll cap
  for Into the Fray.
- **Validation criteria:** Headless `test_heroic_intervention_modes.gd` for both
  modes (target filter + 6" cap). Windowed scenario exercising the stratagem UI.

---

## 6. Weapon & core abilities (section 24)

### WPN-1 — `[DEVASTATING WOUNDS]` must cap one model per critical wound (no spillover)
- **Rule:** 24.10
- **Severity:** 🔴 Critical
- **Current behavior:** DW mortal wounds **spill across models**. `has_devastating_wounds()`
  at `RulesEngine.gd:5461`; application via `apply_save_damage()` `:10523` and
  `_apply_damage_to_unit_pool()` `:10649` which loops distributing total damage
  across multiple models. The behavior is *asserted* by
  `tests/.../test_devastating_wounds.gd:122-129` ("3 DW mortal wounds should kill
  all 3 single-wound models via spillover").
- **Required behavior (11th ed):** On a critical wound the attack sequence ends and
  the target suffers mortal wounds equal to the weapon's **D**, but **a maximum of
  one model may be damaged per critical wound — any remaining MW from that attack
  are lost.** (PDF example: D3 weapon, crit → 3 MW, kills one 2W model, the 3rd MW
  is lost.)
- **Proposed solution:** Route DW critical wounds through a dedicated path that
  applies up to D MW to a **single** allocated model and discards the remainder,
  rather than the shared spillover pool. Update the existing test to assert
  **non-spillover** (this is a behavior change, not a new test only).
- **Validation criteria:**
  - Rewrite `test_devastating_wounds.gd`: D3 crit vs unit of 2W models destroys
    exactly **one** model and loses 1 MW; assert remaining models untouched.
  - Add multi-crit case: N critical wounds damage at most N models.
  - Cross-check interaction with FNP (each MW still rolls FNP) and with the
    "resolve normal damage before mortal wounds" ordering (06.02).
  - Windowed regression on `sp/374_headwoppa_devastating_wounds.json`.

### WPN-2 — `[CLEAVE X]` (new)
- **Rule:** 24.06
- **Severity:** 🟡 Medium
- **Current behavior:** Not implemented (no `CLEAVE` anywhere).
- **Required behavior:** When gathering attack dice, **if the weapon's attacks are
  all directed at a single target unit**, add X dice for every 5 models that were
  in the target unit at the Select Targets step (round down).
- **Proposed solution:** Add `get_cleave_value()` (parse `CLEAVE X`); in the
  attack-dice gather step, when the weapon has a single target, add
  `floor(target_models / 5) * X` dice. Mirror the existing `[BLAST]` gather logic
  (`RulesEngine.gd:6466`/`:1436-1450`) but gate on single-target.
- **Validation criteria:** Headless `test_cleave.gd`: `CLEAVE 1`, A3, vs 16-model
  single target → +3 dice (total 6); assert no bonus when the weapon splits across
  two targets.

### WPN-4 — `SUPER-HEAVY WALKER` (new) + grantable `MOBILE`
- **Rule:** 24.35
- **Severity:** 🟡 Medium
- **Current behavior:** Not implemented.
- **Required behavior:** On a normal/advance/fall-back move, models may move through
  other models (incl. MONSTER/VEHICLE, excl. TITANIC) and horizontally through
  terrain sections ≤4" tall; optionally gain `MOBILE` for the move (on a 1 after the
  move, the unit is battle-shocked).
- **Proposed solution:** Add a unit-ability check; extend the movement traversal
  rules (depends on TER-1/MOV-3) with the ≤4" section allowance and the
  pass-through-models exception; implement the optional MOBILE grant + post-move
  D6 battle-shock.
- **Validation criteria:** Headless `test_super_heavy_walker.gd`: pass-through and
  ≤4" traversal allowed; MOBILE grant rolls a 1 → battle-shocked.

### WPN-5 — `HOVER` (new)
- **Rule:** 24.17
- **Severity:** 🟢 Low
- **Current behavior:** Not implemented.
- **Required behavior:** When the unit takes to the skies, do **not** subtract 2"
  (ties to MOV-4).
- **Proposed solution:** Add `has_hover()` and skip the MOV-4 −2" reduction.
- **Validation criteria:** Covered by `test_fly_take_to_skies.gd` HOVER branch.

> **Note — `[SUPPORT]` disambiguation:** the weapon-abilities sweep flagged a
> "`SUPPORT` weapon ability," but 24.34 defines **SUPPORT** as a *unit* ability
> (attaches units, "See Attached Units (19)"). It is tracked as **TRN-3**, not a
> weapon ability.

> **Firing Deck (24.14):** confirmed implemented end-to-end
> (`ShootingPhase.gd:1070-1124`, `FiringDeckDialog.gd`, embarked units marked
> `has_shot`). No action.

---

## 7. Terrain & visibility

### TER-1 — Terrain categories: Exposed / Light / Dense
- **Rule:** 13.02-13.06
- **Severity:** 🟠 High (foundational — TER-2/TER-3, MOV-3, WPN-4 depend on it)
- **Current behavior:** Terrain classified by **height** (`TerrainManager.gd:18-22`,
  `LOW/MEDIUM/TALL`) plus a free-form `traits` array (`obscuring`, `difficult_ground`).
  Layout JSON pieces (`terrain_layouts/*.json`) carry `type` (`ruins`), `height`
  (`tall`), and `walls[].blocks_los` — but **no Exposed/Light/Dense category**.
- **Required behavior:** Each terrain feature belongs to a category — **Exposed**
  (no effect), **Light** (cover, no movement hindrance), **Dense** (cover + blocks
  movement/sight, has Solid). Movement and cover/visibility rules key off category.
- **Proposed solution:** Add a `category: exposed|light|dense` field to terrain
  pieces (default-map current data: ruins/woods → `dense`, barricades/low walls →
  `light`, craters/debris → `exposed`). Update `TerrainManager` to expose
  `get_category()` and migrate `is_terrain_obscuring()`, cover, and movement
  predicates to consume category. Provide a back-compat shim mapping legacy
  height/traits → category so existing layouts keep working.
- **Validation criteria:** Headless `test_terrain_categories.gd`: every piece in
  each `terrain_layouts/*.json` resolves to a category; Dense blocks vehicle
  horizontal movement, Light/Exposed do not; Dense/Light are obscuring, Exposed is
  not. Windowed visual regression on a layout (`tests/scenarios/visual`).

### TER-2 — Benefit of Cover worsens attack BS by 1 (not improve save)
- **Rule:** 13.08
- **Severity:** 🟠 High
- **Current behavior:** Cover **improves the target's save by 1**
  (`RulesEngine.gd:4174-4175` and save calc `:1169-1172/2996-3003`;
  `check_benefit_of_cover()` `:4048`).
- **Required behavior (11th ed):** Cover **worsens the attacking weapon's BS by 1**
  (a hit-roll penalty), not a save bonus.
- **Proposed solution:** Move the cover effect from the save step to the hit-modifier
  step (−1 BS / worsen hit). Re-point dependent rules accordingly:
  `[IGNORES COVER]` (24.18) must cancel the BS penalty; Stealth (24.33), Smokescreen
  (15.10) and Indirect (10.07) grant cover → now a BS penalty. Audit AI cover
  scoring (`scripts/AI*`, `test_ai_cover_scoring.gd`) which assumes save-based cover.
- **Validation criteria:** Headless `test_cover_worsens_bs.gd`: same attack vs a
  target in cover loses ~1/6 more hits (not saves); `[IGNORES COVER]` removes the
  penalty; assert save value is unchanged by cover. Update/replace any test that
  asserted +1 save from cover. Windowed scenario confirming hit-count delta.

  > ⚠️ **Balance-significant behavior change** — touches every shooting attack into
  > terrain and several abilities/stratagems. Recommend a feature flag
  > (`FeatureFlags.gd`) to stage rollout and A/B the AI impact.

### TER-3 — Hidden + detection range (15")
- **Rule:** 13.09
- **Severity:** 🟡 Medium
- **Current behavior:** No `hidden`/`detection range` concept; no tracking of
  "unit did not shoot this/previous turn" for visibility.
- **Required behavior:** An `INFANTRY/BEASTS/SWARM` model in a terrain area
  containing Dense terrain, whose unit did not make ranged attacks this or the
  previous turn, is **hidden** — visible only to enemies within detection range
  (default 15").
- **Proposed solution:** Track per-unit `last_shot_turn`. Add a `is_hidden()`
  predicate (keywords + in-dense-area + not-shot-window) and gate LoS/target
  eligibility on enemy-within-detection-range when the target is hidden.
- **Validation criteria:** Headless `test_hidden_detection.gd`: hidden infantry in a
  dense area not targetable from >15"; becomes targetable after it shoots or when an
  enemy closes within 15".

### TER-4 — Solid (no LoS through enclosed gaps ≤3" from ground)
- **Rule:** 13.11
- **Severity:** 🟢 Low
- **Current behavior:** Walls carry `blocks_los` but there's no height-of-gap rule;
  no "Solid" concept tied to Dense terrain (`EnhancedLineOfSight.gd`).
- **Required behavior:** Dense terrain has Solid: LoS cannot be drawn through any
  enclosed gap ≤3" above ground level (doors/windows don't grant sight).
- **Proposed solution:** After TER-1, treat Dense pieces as Solid up to 3" and
  block LoS through sub-3" openings in the LoS sampler.
- **Validation criteria:** Headless `test_solid_los.gd` reproducing the PDF's
  window example (ground-level blocked, >3" gap allowed).

### TER-5 — Plunging Fire (+1 BS) and `TOWERING` within 12"
- **Rule:** 22.05
- **Severity:** 🟡 Medium
- **Current behavior:** `TOWERING` keyword affects LoS (`LineOfSightCalculator.gd:26-34`,
  `EnhancedLineOfSight.gd:115-119/350-351`) but **no Plunging Fire +1 BS** is applied
  and there's no "attacker on ≥3" terrain section" detection or 12" TOWERING gate.
- **Required behavior:** +1 BS when the attacker is on a terrain section ≥3" tall,
  **or** has `TOWERING` and the target (containing ground-level models) is within
  12". No effect for/against AIRCRAFT (23.03).
- **Proposed solution:** Add a plunging-fire hit-modifier: detect attacker elevation
  ≥3" (needs per-model elevation from terrain) or TOWERING-within-12"; +1 BS; exclude
  AIRCRAFT.
- **Validation criteria:** Headless `test_plunging_fire.gd`: elevated attacker and
  TOWERING-within-12" each grant +1 hit; no effect beyond 12" for TOWERING; AIRCRAFT
  exempt.

---

## 8. Transports, reserves & attached units

### TRN-1 — Disembark modes: Rapid / Tactical / Combat (6" + battle-shock)
- **Rule:** 18.04
- **Severity:** 🟠 High
- **Current behavior:** Single 3" disembark with a moved/not-moved gate
  (`TransportManager.gd:151-158`; `DisembarkController.gd:88-89` hardcodes 3";
  `DisembarkDialog.gd:73-98` describes only the 3" rule).
- **Required behavior:** Select a mode in order:
  - **Rapid** (3") — if transport made a normal/ingress move this phase; unit can't
    charge after.
  - **Tactical** (3") — if transport is stationary/not yet moved; the unit then
    makes a normal or advance move.
  - **Combat** (6") — otherwise; **hazard roll per model**, may set up engaged with
    enemies the transport is engaged with, unit becomes **battle-shocked** and can't
    charge.
- **Proposed solution:** Add mode resolution (matching the documented order) with the
  6" Combat path (per-model hazard rolls → mortal wounds, battle-shock flag,
  engaged set-up allowance) and the Tactical follow-up normal/advance move.
- **Validation criteria:** Headless `test_disembark_modes.gd`: each mode selected by
  the correct precondition; Combat applies hazard MW + `battle_shocked` and allows a
  6" bubble. Windowed scenario driving a disembark and asserting the mode + range
  ring.

### TRN-2 — Emergency disembark applies battle-shock
- **Rule:** 18.05
- **Severity:** 🟡 Medium
- **Current behavior:** 6" placement + D6-per-model casualties + can't move/charge
  (`TransportManager.gd:309-450`), but the death-roll model differs from a hazard
  roll and **no `battle_shocked`** is applied.
- **Required behavior:** Hazard roll per model (mortal wounds, not auto-death),
  set up within 6" as close as possible (un-place-able models destroyed), unit
  becomes battle-shocked and can't charge.
- **Proposed solution:** Swap the casualty roll for `hazard_roll()` MW; add the
  `battle_shocked` flag.
- **Validation criteria:** Headless `test_emergency_disembark.gd`: hazard MW applied,
  `battle_shocked == true`, un-placeable models destroyed.

### TRN-3 — `SUPPORT` unit ability (second attachment slot)
- **Rule:** 19.01 / 24.34
- **Severity:** 🟠 High
- **Current behavior:** Only Leader attachment; one character per bodyguard
  (`CharacterAttachmentManager.gd:15-91`, single `attached_characters` list; error at
  `:82-85` "Unit already has an attached leader"). No `SUPPORT` concept.
- **Required behavior:** SUPPORT units lead bodyguard units like leaders; a bodyguard
  may have **one Leader and one Support** attached simultaneously.
- **Proposed solution:** Recognize `support_data`/SUPPORT ability; track leader and
  support as separate slots; allow both on one bodyguard; ensure attached-unit rules
  (T-selection, destroy-trigger, ability sourcing 19.02-19.04) treat the support
  component like a leader component.
- **Validation criteria:** Headless `test_support_attachment.gd`: a bodyguard accepts
  both a leader and a support; rejecting a second leader/second support; ability and
  destroy-trigger behavior correct for each component. Windowed scenario extending
  `sp/378_leader_pairing_formations.json`.

### TRN-4 — Strategic reserves: ≤50% points cap + end-of-round-3 destruction
- **Rule:** 20.01, 20.03-20.04
- **Severity:** 🟡 Medium
- **Current behavior:** Ingress geometry mostly correct (round ≥2, >9" from enemies,
  within 6" of edge, not in enemy DZ pre-round-3) at
  `MovementPhase.gd:3253-3330`. **Missing:** the ≤50%-points reserve cap at
  declaration, and destruction of un-arrived reserves at end of round 3.
  (Note: code enforces >9"; the rule is **>8" horizontally** — verify/justify.)
- **Required behavior:** Combined reserve points ≤50% of the army limit; any reserve
  unit that has not arrived by end of battle round 3 is destroyed (with the
  TRANSPORT/repositioned exceptions).
- **Proposed solution:** Validate reserve points in the Formations step; add an
  end-of-round-3 sweep destroying un-arrived reserves. Reconcile the 8" vs 9"
  ingress distance with the PDF (20.04 says >8").
- **Validation criteria:** Headless `test_reserves_rules.gd`: >50% reserves rejected;
  un-arrived reserve destroyed at end of round 3; ingress distance matches 8".

### TRN-5 — Repositioned units retain ongoing effects
- **Rule:** 20.02
- **Severity:** 🟢 Low
- **Current behavior:** Pre-game redeploy exists (`RedeploymentPhase.gd`); no
  mid-battle "remove to reserves while preserving effects (e.g. battle-shock)".
- **Required behavior:** A unit removed to reserves mid-battle keeps duration/condition
  effects (e.g. remains battle-shocked) when it makes its ingress move.
- **Proposed solution:** When a rule repositions a unit, preserve its `flags`/effect
  timers across the remove→ingress transition.
- **Validation criteria:** Headless `test_repositioned_units.gd`: a battle-shocked
  unit repositioned and re-ingressed in the same turn is still battle-shocked.

---

## 9. Core stratagems (section 15)

> Core stratagems are defined in `autoloads/StratagemManager.gd:69-414`
> (`_load_core_stratagems`) with parallel rows in `data/Stratagems.csv:16-26`.
> Both must be updated together to avoid version skew.

### STR-1 — Rename `GRENADE` → `EXPLOSIVES`
- **Rule:** 15.05 — **Severity:** 🟢 Low
- **Current:** id `grenade` / name "GRENADE" (`StratagemManager.gd:215-241`,
  `Stratagems.csv:25`). Mechanic already correct (6D6, 4+ → 1 MW, target within 8",
  visible, EXPLOSIVES/GRENADES).
- **Required/solution:** Rename id+display to `explosives`/"EXPLOSIVES"; keep an alias
  so saved games referencing `grenade` still resolve.
- **Validation:** Headless: stratagem resolves under the new id; alias maps old id.

### STR-2 — Rename + rework `TANK SHOCK` → `CRUSHING IMPACT`
- **Rule:** 15.06 — **Severity:** 🟡 Medium
- **Current:** id `tank_shock` / "TANK SHOCK" (`StratagemManager.gd:243-269`,
  `Stratagems.csv:22`), **VEHICLE-only**, rolls D6 = Toughness, each 5+ → enemy 1 MW
  (max 6). **Missing self-damage and MONSTER scope.**
- **Required:** MONSTER **or** VEHICLE, after a charge move; roll D6 = the model's
  Toughness — **each 1 → your unit suffers 1 MW**, each 5+ → enemy suffers 1 MW (max
  6 per unit).
- **Solution:** Rename id+display; broaden target to MONSTER/VEHICLE; add the
  self-MW-on-1 branch.
- **Validation:** Headless `test_crushing_impact.gd`: self-MW on 1s, enemy MW on 5+
  capped at 6, MONSTER eligible.

### STR-4 — `GO TO GROUND` not in 11th core list
- **Rule:** §15 core list (15.02-15.12) — **Severity:** 🟢 Low
- **Current:** implemented as a core stratagem (`StratagemManager.gd:129-156`,
  `Stratagems.csv:16`).
- **Required:** Not present in the 11th-ed **core** stratagem list.
- **Solution:** Remove from the core set (or gate behind a 10th-ed compatibility
  flag); verify nothing in the AI/UI hard-depends on it.
- **Validation:** Headless: core stratagem enumeration no longer includes
  `go_to_ground`; no loader/AI references break.

*(Heroic Intervention modes are tracked as CHG-1/STR-3 in §5. Command Re-roll,
Epic Challenge, Insane Bravery, Rapid Ingress, Fire Overwatch, Smokescreen,
Counteroffensive are confirmed correct.)*

---

## 10. Prioritized roadmap

**Wave 1 — correctness-critical (do first):**
WPN-1 (DEVASTATING WOUNDS spillover) · CMD-1 (battle-shock persistence).

**Wave 2 — foundational, unblocks others:**
TER-1 (terrain categories) → then TER-2 (cover→BS), MOV-3 (MOBILE/dense), WPN-4
(Super-Heavy Walker), TER-3/4/5.

**Wave 3 — high-frequency core mechanics:**
MOV-1 (fall-back modes) · SHO-1 (close-quarters) · FGT-1 (overrun) · FGT-2
(engaging consolidation) · TRN-1 (disembark modes) · TRN-3 (Support units).

**Wave 4 — situational / polish:**
SHO-2, SHO-3, MOV-2, MOV-4, CHG-1, FGT-3, WPN-2 (Cleave), WPN-5 (Hover), TRN-2,
TRN-4, TRN-5, CMD-2, STR-1/2/4.

### Delta index

| ID | Title | Severity |
|----|-------|----------|
| CMD-1 | Battle-shock persistence/recovery | 🔴 |
| CMD-2 | Battle-shock blocks actions | 🟡 |
| MOV-1 | Fall-back modes + hazard rolls | 🟠 |
| MOV-2 | Surge move targeting | 🟡 |
| MOV-3 | MOBILE + dense terrain movement | 🟠 |
| MOV-4 | FLY take-to-skies −2" | 🟡 |
| SHO-1 | `[CLOSE-QUARTERS]` keyword + shooting type | 🟠 |
| SHO-2 | −1 vs engaged MONSTER/VEHICLE + BLAST ban | 🟡 |
| SHO-3 | Indirect 1-5/1-3 thresholds | 🟢 |
| FGT-1 | Overrun fight | 🟠 |
| FGT-2 | Consolidation modes (Engaging pull-in) | 🟠 |
| FGT-3 | Eligible-but-unable-to-fight pass | 🟢 |
| CHG-1 | Heroic Intervention two modes | 🟡 |
| WPN-1 | DEVASTATING WOUNDS no-spillover | 🔴 |
| WPN-2 | `[CLEAVE X]` | 🟡 |
| WPN-4 | SUPER-HEAVY WALKER + MOBILE grant | 🟡 |
| WPN-5 | HOVER | 🟢 |
| TER-1 | Exposed/Light/Dense categories | 🟠 |
| TER-2 | Cover worsens BS (not save) | 🟠 |
| TER-3 | Hidden + detection range | 🟡 |
| TER-4 | Solid (≤3" gap) | 🟢 |
| TER-5 | Plunging Fire + TOWERING 12" | 🟡 |
| TRN-1 | Disembark modes | 🟠 |
| TRN-2 | Emergency disembark battle-shock | 🟡 |
| TRN-3 | SUPPORT attachment slot | 🟠 |
| TRN-4 | Reserves 50% cap + round-3 destruction | 🟡 |
| TRN-5 | Repositioned units keep effects | 🟢 |
| STR-1 | Rename Grenade→Explosives | 🟢 |
| STR-2 | Tank Shock→Crushing Impact (+self-dmg/MONSTER) | 🟡 |
| STR-4 | Remove Go to Ground from core | 🟢 |

---

## 11. Validation methodology (project gate)

For every delta:

1. **Headless first** — add/adjust `tests/unit/test_*.gd`; run via
   `40k/tests/run_pretrigger_tests.sh` (or GUT). Establishes engine-level correctness.
2. **Windowed scenario** for any UI-facing change — add
   `tests/scenarios/sp/<id>_<name>.json` driving real buttons via the
   `addons/godot_mcp` bridge; run `bash 40k/tests/run_scenarios.sh tests/scenarios/sp/<id>.json`.
3. **MCP gate** — run the game (the container can: `godot --headless --import`
   then `godot --path 40k --rendering-method gl_compatibility`), drive the path via
   `dispatch_action`/`execute_script`/`simulate_click`, `capture_screenshot` the
   feature effect, and finish with `verify_delivery` (`verdict: PASS`,
   `log.no_errors`).
4. **Regression** — re-run affected existing scenarios (e.g.
   `sp/374_headwoppa_devastating_wounds.json`, `sp/383_battleshock_can_shoot.json`,
   `sp/378_leader_pairing_formations.json`, `test_ai_cover_scoring.gd`).

Behavior changes that alter outcomes for existing content (WPN-1, CMD-1, TER-2)
should land behind a `FeatureFlags.gd` toggle so 10th-ed saves/scenarios and AI
tuning can be migrated deliberately.
