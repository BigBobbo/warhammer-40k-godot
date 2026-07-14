# Fight Phase — 11th-Edition Cleanup & Gap-Closure Plan

**Date:** 2026-07-14
**Status:** Analysis + proposed plan (no code changes yet)
**Scope:** `40k/phases/FightPhase.gd`, `40k/scripts/FightController.gd`, `40k/scripts/rules/FightSequencer.gd`,
`40k/scripts/rules/movetypes/PileInMove.gd` + `ConsolidationMove.gd`, `40k/scripts/Main.gd`,
`40k/phases/BasePhase.gd`, the fight dialogs, and the AI fight path.

---

## TL;DR — this is a cleanup, not a rewrite

The 11th-edition Fight-phase **rules engine is already implemented, edition-gated, and tested**. The
step restructure that 11e requires — a **global Pile In step (12.02)**, a **FightSequencer**-driven
alternating **Fight step (12.04)** with Normal/Overrun typing (12.05/12.06), and a **global Consolidate
step (12.07)** with the three consolidation modes (12.08) plus the "new foes to face" forced-fight
interrupt — is all present in `FightPhase.gd` and covered by headless tests (`test_global_pile_in_11e.gd`,
`test_global_consolidation_11e.gd`, `test_iss050_fight_phase_11e.gd`, `test_fight_phase_scope_end_fight_11e.gd`)
and windowed scenarios (`iss050_fight_11e.json`, `global_consolidation_step_11e.json`,
`iss066_pile_in_consolidate_11e.json`). `docs/rules/11th_edition_doc_change_audit.md` item 15 records the
step-structure task as **CLOSED** (pile-in half 2026-07-04, consolidation half 2026-07-03).

So the "significant rewrite" the player-facing symptoms suggest is really **three separate, smaller jobs**:

1. **Fix the concrete bugs** the leftover 10e scaffolding causes (these are what the screenshot shows).
2. **Delete the 10e remnants** so the two code paths stop shadowing each other.
3. **Close a handful of genuine 11e correctness gaps** in the move templates and melee resolution.

Edition is controlled by `GameConstants.edition` (static int, default **11**; `GameConstants.gd:26`).
Real players always run 11 (`SettingsService.gd:150-155`); only the automated test harness pins 10.
The project's own note: *"This carve-out disappears when the 10e code paths are deleted"* (`SettingsService.gd:149`).

---

## What the screenshot actually shows (both verified against source)

### Bug A — "Fight action failed: Unknown error" (the red banners)
- `BasePhase.execute_action` returns `{"success": false, "errors": validation.errors}` — key **`errors`**
  (plural array) — on any validation rejection (`BasePhase.gd:96-98`).
- `Main._on_fight_action_requested` reads `result.get("error", "Unknown error")` — key **`error`**
  (singular) — at `Main.gd:9977`, then shows `"Fight action failed: %s"` at `Main.gd:9992`.
- Net: **every** validation-rejected fight action loses its human-readable reason and shows the literal
  "Unknown error". The real reason existed (e.g. *"The Pile In step must finish before units are
  selected to fight"* — `FightPhase.gd:684-685`, or the out-of-sequence 12.04 reason at `690-698`).
- **Not fight-specific:** the same `errors`/`error` mismatch exists in the Movement/Shooting/Charge
  handlers in `Main.gd` (`~9806, 9888, 9938, 9977`). Fix centrally.

### Bug B — dead per-unit "MOVEMENT ACTIONS: Pile In / Consolidate" panel
- Built unconditionally in `_setup_right_panel` (`FightController.gd:335-362`); both buttons created with
  `disabled = true`.
- They can only enable via `_can_pile_in()`/`_can_consolidate()` (`FightController.gd:720-728, 877-887`),
  which call `current_phase.can_unit_pile_in` / `can_unit_consolidate`. **Those methods do not exist on
  `FightPhase`** (grep-confirmed), so `has_method(...)` is false and the buttons are permanently greyed out.
- A backing 10e board-click path is still wired into `_input` (`_handle_movement_click`,
  `FightController.gd:1352-1395`) and dispatches a 10e payload shape (`actor_unit_id` + `position`) that
  the 11e validators reject (they expect `unit_id` + a `movements` dict —
  `_validate_pile_in_11e` `FightPhase.gd:5999`, `_validate_consolidate_11e` `6061`). Dormant only because
  the buttons can never fire — a latent re-break if anyone re-adds the missing phase methods.

---

## 10th-edition remnants inventory (the cleanup targets)

### In `FightPhase.gd` (dual state machine kept alive alongside 11e)
- `Subphase` enum + `FightPriority.FIGHTS_LAST` (`~92-104`); `_transition_subphase` (`~3210-3250`);
  `_get_fight_priority` computing FIGHTS_LAST from `status_effects.fights_last` (`~3034-3048`).
  11e (12.04) has only **Fights First** + untiered **Remaining**; `FightSequencer` has no fights-last tier
  (`FightSequencer.gd:55-58`), so a "fights last" unit is already treated as a normal Remaining unit.
- Tier lists `fights_first_sequence` / `normal_sequence` / `fights_last_sequence` (`~78-83`);
  `_build_alternating_sequence` (`~3252-3274`); legacy queue `fight_sequence` + `current_fight_index`
  consumed in `get_available_actions` (`~3975-3993`). Bypassed by the sequencer at 11e but still built
  every phase-enter and still read by `_scan_newly_eligible_units_after_consolidation` (`~4248-4340`) and by
  `_finish_fight_activation_11e` (bumps `current_fight_index` at `~2745`).
- Legacy per-unit validators/processors, `edition < 11` only: `_validate_pile_in` body (`~756-840`),
  `_process_consolidate` (`~2794-2897`), `_validate_consolidate` two-mode (`~938-1013`),
  `_determine_consolidate_mode` (`~992-1013`), `_can_unit_reach_engagement_range` (hard-codes 1" ER,
  `~1015-1050`), `_validate_consolidate_engagement_range`/`_validate_consolidate_objective`
  (`~1183-1294`), `_get_consolidation_distance` 3"/6" (`~2666-2694`, ignored at 11e),
  `_model_to_objective_distance_inches` (40 mm radius, disagrees with template's 20 mm).
- 10e defender-first default `current_selecting_player = _get_defending_player()` (`~301`), immediately
  overridden to active-player-first at 11e (`~311-316`).

### In `FightController.gd` (UI)
- The MOVEMENT ACTIONS panel + `pile_in_button`/`consolidate_button` (`335-362`), `pending_pile_in_unit` /
  `pending_consolidate_unit` (`22-23`), `_on_pile_in_pressed`/`_on_consolidate_pressed` (`1264-1276`),
  `_handle_movement_click` legacy branch (`1352-1395`), `_can_pile_in`/`_can_consolidate` (`720-728, 877-887`).
- Duplicate fight-sequence populator `_refresh_fight_sequence` (`503-547`) calling non-existent
  `get_fight_sequence`/`get_current_fight_index`, running in parallel to the live `_refresh_fighter_list`
  (`792-834`) with divergent row tags.
- **Keep** the shared `PileInDialog`/`ConsolidateDialog` and the `_on_pile_in_required`/`_on_consolidate_required`
  handlers — the 11e global-step pickers (`PileInStepDialog`/`ConsolidationStepDialog`) reuse them.
- "10e" comments to correct: `FightPhase.gd:7`, `FightController.gd:2282-2283`.

---

## Genuine 11e correctness gaps (engine, not just cleanup)

### Move templates (`PileInMove.gd` / `ConsolidationMove.gd`)
1. **"End engaged / in base contact if possible" dropped (12.03 & 12.08 Ongoing).** `model_move_allowed`
   enforces only base-contact-lock + strictly-closer (`PileInMove.gd:71-80`, `ConsolidationMove.gd:86-93`);
   nothing forces a model that *could* reach engagement to do so. The 10e path enforced this via
   `_validate_base_to_base_if_possible` (`FightPhase.gd:3458-3520`). Port it, using the **2" 11e ER**, not 1".
2. **"New foes to face" ownership (12.08 Engaging).** The drag-in *works* (via
   `_forced_fights_pending_11e`/sequencer, `FightPhase.gd:3764-3767, 2930-2962`) but the purpose-built
   `ConsolidationMove.forced_fights_after_engaging` (`ConsolidationMove.gd:148-153`) is **dead code**, and the
   rule's *"selected by the opponent"* clause is not explicitly enforced — the sequencer's leftover
   `picker`/`step` decides who picks. Either wire the helper up or make opponent-selection explicit.
3. **Objective mode "within range if possible" (12.08 Objective).** `after_moving_conditions` hard-requires
   ≥1 model in range and errors otherwise (`ConsolidationMove.gd:131-141`) instead of "in range *if possible*,
   else closer." Low impact (mode only auto-selected when a marker is already within 3") but technically wrong.
4. **6" consolidation abilities ignored at 11e.** `_validate_consolidate_11e` hard-codes `3.0`
   (`FightPhase.gd:6106`) and `ConsolidationMove.max_distance_inches` is fixed; `_get_consolidation_distance`
   (the 3"/6" ability source, `2666-2694`) feeds only the 10e path. Make the 11e cap context-aware or confirm
   no shipping 11e ability grants 6".
5. **Objective geometry source of truth.** Legacy path = 40 mm radius (`FightPhase.gd:1125`); template =
   `OBJECTIVE_RANGE_INCHES = 3.787` (3" + 20 mm) (`ConsolidationMove.gd:23-24`). Pick one.

### AI (`AIDecisionMaker.gd` / `AIPlayer.gd`) — mostly 11e already
- The AI drives pile-in/consolidate as **global 11e steps** (`AIDecisionMaker.gd` `END_PILE_IN` `13831-13840`,
  `END_CONSOLIDATION` `13821-13829`; `AIPlayer._get_fight_phase_selecting_player` `355-383`). Good.
- **Gap:** `_compute_pile_in_movements` (`AIDecisionMaker.gd:14471-14481`) still moves each model toward the
  **closest enemy model** (10e), not the 12.03 "closest *selected* pile-in target" (matters for the
  unengaged/overrun case). Caps 3" and locks base-contact correctly.

### Melee resolution parity (delta_audit Tier A — partly done / disputed in docs)
- Melee saves possibly still on the 10e `WoundAllocationOverlay` path (`FightController.gd:2856`) rather than
  the 11e allocation flow (`resolve_allocation_batch_11e`, mirror of `ShootingController.gd:2552`).
  `delta_audit.md:220/99` say 10e; `delta_audit.md:332` claims fixed 2026-06-23. **Needs a live check.**
- `[DEVASTATING WOUNDS]` melee still spillover, no cap (`RulesEngine.gd:10028`, `delta_audit.md:181`);
  `[PSYCHIC]` melee ignores hit-modifier rule (`delta_audit.md:229`); `[CLEAVE X]` adds no dice
  (`delta_audit.md:227`); attacker-choice prompts (DEV WOUNDS / LETHAL HITS) default-only, no UI
  (`delta_audit.md:237`). Several later claimed fixed in the same doc's §11 — reconcile by testing.
- `RulesEngine.get_fight_priority` Fights-First↔Fights-Last cancellation (`RulesEngine.gd:12208`) is 10e
  commentary with no basis in the 11e core doc — revisit.

---

## Recommended phased plan

### Phase 0 — Visible-bug quick wins (small, high value, low risk) ⟵ fixes the screenshot
- **0a.** Map `result.errors` (array) → a human message centrally so rejected actions show the real reason.
  Best at the `Main.gd` fight/shoot/charge/move handlers (or normalize in `BasePhase.execute_action` to also
  set `error`). Add a windowed scenario asserting a rejected `SELECT_FIGHTER` shows the 12.04 reason, not
  "Unknown error".
- **0b.** Delete the dead MOVEMENT ACTIONS buttons + `pending_*` vars + `_on_pile_in_pressed`/
  `_on_consolidate_pressed` + `_handle_movement_click` legacy branch + `_can_pile_in`/`_can_consolidate`.
  **Keep** `PileInDialog`/`ConsolidateDialog` and the `*_required` handlers (shared with the global steps).
- **0c.** Delete the duplicate `_refresh_fight_sequence`; keep `_refresh_fighter_list`.

### Phase 1 — 11e move-template correctness
- Restore "end engaged / base-contact if possible" (gap 1) in both templates, 2" ER.
- Wire or delete `forced_fights_after_engaging`; enforce opponent-selection for dragged-in fights (gap 2).
- Fix objective "within range if possible" (gap 3); reconcile objective geometry (gap 5).
- Decide 6" consolidation ability handling (gap 4).
- Fix AI `_compute_pile_in_movements` to target the selected pile-in target for unengaged/overrun (AI gap).

### Phase 2 — Delete the 10e scaffolding (the real "rewrite" cleanup) — needs test migration
- Remove the dual state machine (`Subphase`, `FightPriority.FIGHTS_LAST`, tier lists,
  `_build_alternating_sequence`, `fight_sequence`/`current_fight_index`, `_transition_subphase`,
  `_validate_pile_in`/`_process_consolidate`/`_determine_consolidate_mode` + the 10e-only validators).
- Re-home the 11e reads that still touch 10e structures: `_scan_newly_eligible_units_after_consolidation`,
  the `current_fight_index` bump in `_finish_fight_activation_11e`, and the banner's Subphase rendering
  (`FightPhaseStateBanner.gd`).
- **Decision required:** the ~70 legacy 10e scenarios pin `edition = 10`. Deleting 10e means migrating them
  to 11e (or retiring them). Until then, the harness carve-out stays.

### Phase 3 — Melee resolution 11e parity (separate track)
- Live-verify the melee save path; route through the 11e allocation flow if not already.
- DEV WOUNDS melee cap, PSYCHIC melee, CLEAVE X, attacker-choice prompts UI. Reconcile with delta_audit §7/§11.

### Phase 4 — Docs + labels + tests
- Correct the stale `delta_audit.md:22-33` headline and `doc_change_audit.md:130-135` PARTIAL rows.
- Fix "10e" comments in `FightPhase.gd:7`, `FightController.gd:2282-2283`.
- Version-history entry per phase that changes player-facing behavior.

---

---

## Verified findings & progress (2026-07-14 session)

### DONE — Phase 0 (committed cce8efa, pushed, windowed-validated)
- Fixed "Fight action failed: Unknown error": `BasePhase.execute_action` now populates a joined
  `error` string alongside `errors`. Also fixes Shooting/Charge rejections.
- Removed the dead per-unit "MOVEMENT ACTIONS: Pile In / Consolidate" panel and its legacy
  board-click path from `FightController`.
- Proof: `fight_reject_reason_11e.json` (9/9) — `result.error` is the real 12.02 reason, no
  `FightMovementButtons` node exists; `iss050_fight_11e.json` (21/21) — 11e fight flow unaffected.

### CORRECTED — Phase 1 re-assessment (two flagged "gaps" are NOT gaps)
- **Objective-mode "within range if possible"** is already correct: `ConsolidationMove.model_move_allowed`
  allows in-range-or-closer (`ConsolidationMove.gd:94-107`); the AFTER-move hard "must be in range"
  (`:131-141`) is exactly what 12.08 Objective requires.
- **Objective geometry** `OBJECTIVE_RANGE_INCHES = 3.787` (3" + 20 mm radius) is the CORRECT value for a
  40 mm marker; the legacy path's 40 mm-radius version is the wrong one (and is being deleted).
- The genuine Phase-1 item is the per-model **"engaged if possible"** rule (12.03 / 12.08 Ongoing). NOTE:
  the 10e helper `_validate_base_to_base_if_possible` enforces *base-to-base*, but 11e only requires
  *engagement range* (2"), so a direct port is too strict. This per-model "if possible" logic is also the
  source of prior "knife-edge rejection" bugs (v0.42.8) — implement carefully with the 2" threshold and
  thorough windowed validation, or document as a deliberate relaxation.

### CONFIRMED — Melee wound allocation is NOT on the 11e path (resolves the delta_audit §7↔§11 contradiction)
Verified by reading the code (not the docs):
- **Shooting (correct):** `ShootingController._on_saves_required` selects `AllocationGroupOverlay` (11e) vs
  `WoundAllocationOverlay` (10e) by edition — `ShootingController.gd:2722-2724`, var comment `:54`.
- **Fight (gap):** `FightController._on_melee_saves_required` creates `WoundAllocationOverlay`
  UNCONDITIONALLY — `FightController.gd:3031`, no edition branch. `resolve_allocation_batch_11e` is used
  NOWHERE in the fight path (grep-confirmed).
- The DEVASTATING WOUNDS *wound-side* choice (24.10) IS 11e-correct — it lives in the shared
  wound-resolution function (`RulesEngine.gd:2477-2480`, handles both melee Headwoppa `:2461` and ranged
  PURITY `:2468`). So the gap is specifically the SAVE/ALLOCATION overlay, not wound generation.
- **Impact (precise):** melee saves at e11 use the 10e allocation overlay instead of the 11e
  allocation-group path shooting uses. Whether specific outcomes differ depends on what
  `AllocationGroupOverlay` enforces that `WoundAllocationOverlay` does not (allocation grouping / MW
  handling) — needs a side-by-side before claiming wrong *results*.
- **Fix (recommended, medium, regression-prone):** mirror ShootingController — at e11 use
  `AllocationGroupOverlay` and route `APPLY_MELEE_SAVES` through `resolve_allocation_batch_11e`. Requires
  the melee wound data to be group-shaped and `_process_apply_melee_saves` to consume the 11e summary.
  Touches the working melee resolution flow — do as a focused, windowed-validated change.

### 10e deletion — scenario impact scoped (the prerequisite for deleting the fight 10e paths)
Only **8** fight scenarios run at the edition-10 baseline (19 are already e11). Deleting the 10e fight
code requires first migrating/retiring these:
- **Easy migrate** (add `"edition": 11`, no flow change): `custodes_lions_stratagems`,
  `fullauto_fight_stratagems`, `runner_smoke`, `fight_self_targeting`, `386_deadly_demise_vehicle`.
- **Hard** (drives the 10e per-unit `PILE_IN`→`CONSOLIDATE` flow): `co_offer_after_charge` — rewrite for
  the 11e global steps.
- **Retire/rewrite** (10e-only concept): `fights_last_select_fighter` — tests the FIGHTS_LAST subphase,
  which does not exist in 11e.
Plus: the player-facing `FightPhaseStateBanner` reads `current_subphase` / `fights_last_units`, and
helpers at `FightPhase.gd:3566, 4129, 4267` read `fights_last_sequence` on the 11e path — so deletion
requires rewiring the banner + get_current_fight_state off the `FightSequencer` first. GUT tests that
assert 10e fight behavior must also be migrated.

---

## Validation gate (per CLAUDE.md)
Every phase with a UI surface needs a **windowed scenario** driving the real player path against the running
game (MCP bridge: `simulate_click` real buttons, `verify_delivery` PASS, screenshot of the effect). Headless
GUT tests are necessary but not sufficient. Phases 0a/0b are directly windowed-testable (reproduce the
"Unknown error" and the removed buttons).

## Key risks
- **Two live state machines kept in sync** — removing 10e means re-homing every place the 11e path reads a
  10e structure (see Phase 2). Miss one and forced-fights / next-selection / the banner silently break.
- **Eligibility split across three sources** — `FightSequencer.eligible_to_fight` (point-in-time),
  `flags.was_eligible_to_fight` stamp (cumulative, six mutation sites), `PileInMove.eligible` (charge/overrun
  flags). Preserve every stamping moment.
- **`END_FIGHT` is overloaded** (`_process_end_fight` `FightPhase.gd:4932-4974`) — ends a pile-in half, ends
  fights handing over to the opponent, enters consolidate, ends a consolidate half. Reproduce exactly.
- **Templates use live-tree lookups** (`Engine.get_main_loop()...`) and simulated boards — keep them working
  headless.
