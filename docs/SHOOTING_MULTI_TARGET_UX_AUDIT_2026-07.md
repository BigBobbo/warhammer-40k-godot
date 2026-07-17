# Multi-Target Shooting — UX & Reliability Audit (2026-07)

**Scope**: the full player path for shooting one unit at MULTIPLE targets (split
fire): declaration → confirmation → weapon-order → staged dice → defender saves
→ next weapon → completion. Audited by reading `ShootingPhase.gd` /
`ShootingController.gd` / `WeaponOrderDialog.gd` end-to-end, then driving the
real windowed game via the scenario runner and reproducing the reported bug.

**Status (updated 2026-07-17)**: IMPLEMENTED on this branch. The three
correctness bugs (§1) are fixed, and the redesign (§4) shipped after the
owner's sign-off on the open questions: F3/F4 validation parity, B4 one-click
declaration + move picker, B1 target chips, B2 resolution dock (right-HUD
in-place swap; the separate weapon-order dialog is replaced by dock
reordering in single-player), and B3 pause policy (default "Every step").
B5 (expected-damage previews) remains future work — the existing
FORECAST/COMBINED FORECAST panels already cover part of it.
Full shooting scenario battery: 16/16 passing, plus new scenarios
`split_fire_move_picker`, `engaged_vehicle_confirm_split_11e`,
`pause_policy_never_auto_continues`, and a resurrected
`staged_shooting_reroll_ui` (was failing on the base branch).

**Follow-ups (tracked here)**:
1. **MP-safe fast-roll / dock port** (owner-approved): networked play still
   uses the combined single-batch fast roll and the dialog chain — port the
   per-weapon auto-continue design once its save broadcast/ack sync is
   adapted (`_process_resolve_weapon_sequence` network branch).
2. **Pre-existing broken scenarios** (fail on the clean base; terrain
   visibility fixture fallout, NOT this branch): `split_fire_per_model`,
   `split_fire_spinbox_commit`, `iss15_hidden_shot_stamp_11e` (its dialog
   steps are already converted to dock equivalents for when the fixture is
   repaired). Repair needs a fixture where the Kommandos/Witchseekers are
   not Hidden, or asserts updated to the hidden-visibility rules.
3. **F9 weapon-instance count**: "4x Big shoota" resolves as ONE weapon with
   3 attacks (verified live: 3 base + RF2). If multi-instance wargear should
   multiply attacks, that is a RulesEngine/army-parse issue — needs a rules
   decision, out of scope here.
4. **B5 previews**: per-assignment expected unsaved wounds in the dock rows
   and quick-assign buttons, with the modifier chain on hover.

---

## 1. Bugs found and fixed (this branch)

### 1.1 CRITICAL — "Shooting at two targets only rolls the first one"
`_process_apply_saves` classified the resolution mode with
`is_sequential = (mode == "sequential" or mode == "fast")`. Single-player
sequential resolution runs in mode **`"sequential_staged"`** — not in that list.
So the moment the FIRST weapon caused wounds and the defender resolved saves,
the code fell into the single-weapon completion branch: it emitted
`next_weapon_confirmation_required([])` (empty remaining list → the dialog
shows only "Complete Shooting") and every remaining assignment — including all
other declared targets — was silently dropped. If the first weapon *missed*,
the no-wounds path (which had the correct index bookkeeping) continued fine,
which made the bug feel intermittent.

**Fix**: include `sequential_staged` in the sequential check
(`ShootingPhase.gd:_process_apply_saves`).

### 1.2 CRITICAL — "Continue to Next Weapon" dead-ended the sequence
Even when the pause dialog *did* offer the next weapon,
`_validate_continue_sequence` rejected the resulting `CONTINUE_SEQUENCE` action
with *"Not in sequential mode"* (same missing mode string, also missing
`"fast"`). The rejection additionally triggered Main's reject→resync path,
which **rebuilt the weapon-assignment panel in the middle of resolution** —
the confusing "everything reset to (Click to Select)" state.
`get_available_actions`' AI safety-net had the same blindspot.

**Fix**: accept `sequential` / `sequential_staged` / `fast` in both places.

### 1.3 MAJOR — "Fast Roll All" double-rolled weapons and discarded wounds
The fast path resolved ALL weapons in one combined RulesEngine call, but the
save flow only ever applied the FIRST (weapon, target) batch — then offered
"Continue to Next Weapon", which **re-rolled the remaining weapons from
scratch**. Wounds the discarded rolls had caused were lost; a weapon that
missed got a fresh second roll. This affected any multi-weapon fast roll, not
just split fire.

**Fix**: in single-player, "Fast Roll All" now routes through the same
sequential-staged machinery with an `auto_continue` flag — each weapon rolls
hit+wound in one pass with no pauses, the defender resolves that weapon's
saves, and the next weapon fires automatically (deferred via
`CONTINUE_SEQUENCE` so the previous weapon's casualties are applied before
blast/rapid-fire counts and destroyed-target skipping are evaluated).
Networked fast roll keeps the old combined path — its save broadcast/ack sync
depends on the single batched `save_data_list` (flagged as follow-up).

### 1.4 Dialog clarity fixes
- FIRING ORDER rows never showed **who each weapon was shooting at** — the one
  fact that matters when ordering a multi-target volley. Rows now carry a green
  `→ target` line (`2× Ork Boyz | 1× Nobz` for splits).
- The single-weapon auto-start header claimed the whole weapon was "firing at
  ‹first target›" when it was split across several. It now announces
  "Split fire: ‹weapon› at ‹all targets›."
- During staged resolution the hidden order list's ScrollContainer kept its
  220px minimum — a large dead gray block mid-dialog. The whole section now
  hides.

**Regression coverage added**:
- `tests/scenarios/sp/split_fire_two_targets_resolve_both.json` — full windowed
  path: declare 2 targets → order dialog → staged hit/wound → 11e allocation
  overlay → *continue offered* → weapon 2 resolves → complete; asserts
  `current_index` advances and the phase log records 2 targets / 2 weapons.
- `tests/scenarios/sp/fast_roll_two_targets_all_resolve.json` — fast roll with
  2 targets resolves every weapon exactly once.
- `tests/test_shooting_sequential_pause.gd` — headless APPLY_SAVES continuation
  block (36/36).

**Known pre-existing failures (NOT this branch, needs separate repair)**:
`staged_shooting_reroll_ui`, `split_fire_per_model`, `split_fire_spinbox_commit`
fail on the clean base too — their fixture's Kommandos became untargetable
after the 11e terrain-visibility change (they assert on a target that is now
Hidden).

---

## 2. The current flow, as a player experiences it

Declaration (right HUD): select shooter → weapon tree row → click enemy → (if
several bearers) a **SpinBox modal** asks "Send N of M" → repeat per weapon →
CURRENT TARGETS basket lists assignments → **Confirm Targets**.

Resolution (center modals): possible defender stratagem prompt → **Weapon Order
dialog** (or auto-start for one weapon type) → per weapon: hit roll → pause
("Roll to Wound ▶") → wound roll → pause ("Continue to Saving Throws ▶") →
**allocation overlay** (defender rolls saves, picks casualties) → **Next Weapon
dialog** (attack summary + remaining list) → … → "Complete Shooting".

For a 3-weapon, 2-target activation that's roughly **12–16 clicks across 4
different UI surfaces**, with the board hidden behind a large center modal most
of the time.

### Friction inventory (ranked)

| # | Severity | Issue |
|---|----------|-------|
| F1 | High | **Modal fatigue**: WeaponOrderDialog → 2 staged pauses → save overlay → NextWeaponDialog *per weapon*. Buttons move between surfaces; each weapon costs ~4 dialogs. |
| F2 | High | **Assignment state is split across three displays** (weapon-tree column 2, CURRENT TARGETS basket, board lines that only appear on confirm) and they can disagree — e.g. auto-assign writes "→ Battlewagon" into the tree, engine rejects it (pistol rule), basket stays empty, Confirm says "(1 weapons, 1 unassigned)". |
| F3 | High | **Declaration-time vs confirm-time validation disagree**: `ASSIGN_TARGET` accepts targets that `CONFIRM_TARGETS` then rejects wholesale (e.g. engaged units' close-quarters restriction — observed live with the Telemon: both assignments accepted, confirm failed with "Unit is in engagement — can only target engaged units"). Player builds a full plan, then gets a blanket "no". |
| F4 | Medium | **Auto-assign triggers rule-violating assignments** and surfaces the engine rejection as a red error banner the player never caused (pistol/non-pistol exclusivity). |
| F5 | Medium | **No board anchor during resolution**: shooting lines draw for all targets at confirm, but nothing on the battlefield indicates *which target the current weapon is resolving against*. All progress context lives in modal text. |
| F6 | Medium | **Right HUD stays in "declaration mode" during resolution** — weapon tree resets to "(Click to Select)", QUICK ASSIGN buttons remain visible/clickable, CURRENT TARGETS empties. Looks like the assignments vanished. |
| F7 | Medium | The same dice information renders in **three places** (dialog resolution log, right-HUD DICE LOG, left Game Log) while the board is obscured. |
| F8 | Low | The split-fire **SpinBox modal** for bearer counts is heavyweight for a routine choice, and grabs focus mid-flow. |
| F9 | Low | Weapon tree counts bearers, not weapon instances ("Big shoota ×1" on a wagon carrying 4). |
| F10 | Low | Ordering is per weapon *type*; the slices of a split weapon can't be interleaved with other weapons (rules allow any order). Acceptable simplification — but should be a stated one. |

---

## 3. What comparable games do (research digest)

Full sources in the session notes; key takeaways:

- **BattleTech (HBS)** is the reference for split fire: a persistent weapon
  panel where each row shows its per-target hit%; multi-target mode flags
  enemies **A/B/C on the battlefield** and each weapon row carries its target
  letter — click a row to cycle its target. One commit, one volley, no
  intermediate confirms. Their default is deliberately "everything at one
  target"; splitting is the opt-in exception.
- **Battlesector / Gladius**: two-click "preview → same-click confirm", zero
  dialogs; criticized for hiding the modifier math and (Battlesector) for
  unskippable own-turn animations.
- **Solasta**: interrupt prompts (their Command-Re-roll analogue) appear **only
  when the decision can change the outcome** — the direct model for re-roll
  pauses. On-screen dice praised; results vanishing too fast criticized.
- **Baldur's Gate 3**: multiple attacks chain with zero dialogs; every roll is
  auditable afterwards in an expandable combat log; reaction interrupts are
  per-trigger configurable (Always / Ask / Never).
- **Anti-patterns** with hard evidence: outcome text shown before the dice
  animation (Blood Bowl 3); per-attack modal ceremony that scales with attack
  count (Phoenix Point); unskippable resolution (Necromunda); previews that
  omit a defensive stage and so read as lies (Mordheim).

---

## 4. Proposed redesign (for discussion)

Constraints kept: 40k's declare-all-targets-then-resolve sequencing, per-weapon
sequential resolution, Command Re-roll pauses, interactive defender saves.

### Phase B1 — "Targets are chips, not dialog text" (board + panel identity)
- On declaration, each declared target gets a **letter + color chip** (A/B/C…)
  rendered on the battlefield next to the unit and reused everywhere that
  target is mentioned: weapon-tree rows (`→ B Witchseekers`), CURRENT TARGETS
  basket, order rows, resolution header, save overlay title.
- Hovering a weapon row highlights its line + target chip; hovering a target
  highlights the weapons assigned to it.
- During resolution, the current target's chip pulses / the line brightens —
  the battlefield itself shows "weapon 2 of 3 → B".

### Phase B2 — One resolution surface instead of three dialogs
Replace WeaponOrderDialog + NextWeaponDialog with a **docked resolution panel**
(side or bottom, board stays visible):
- Queue of rows: `✔ Big shoota → A (1 slain)` / `▶ Zzap gun → B` / `· Lobba → A`,
  reorderable before start (drag or ▲▼) — this *replaces* the separate
  ordering step.
- ONE primary button in a fixed position ("Roll to Hit ▶ / Roll to Wound ▶ /
  Continue ▶"), Space/Enter to advance — rip through steps by muscle memory.
- Dice results render inline in the dock and mirror to the existing Game Log;
  drop the third copy.
- The right HUD's declaration widgets (weapon tree, QUICK ASSIGN, Confirm)
  hide while the dock is active (fixes F6).

### Phase B3 — Interrupt policy (Solasta/BG3 pattern)
Setting: **Pauses: Every step / Only decisions / Never**.
- "Only decisions" (proposed default): pause only when Command Re-roll is
  actually available AND the roll has a failure worth re-rolling, and for
  defender saves with a real allocation choice. Everything else auto-flows.
- "Never" = current Fast Roll (now correct), still stopping for human-defender
  saves.

### Phase B4 — Declaration ergonomics
- **First enemy click assigns ALL eligible weapons** to that target (the
  majority case becomes one click); individual weapons are then peeled off to
  other targets via the existing per-weapon flow. (QUICK ASSIGN already
  approximates this; make it the default click semantics.)
- Replace the SpinBox modal with **inline +/- steppers** on the weapon row
  (or shift-click = one bearer at a time).
- Auto-assign must **pre-filter illegal combinations** (pistol exclusivity,
  shooting-type restrictions) instead of dispatching and surfacing engine
  rejections (F4).
- Align `ASSIGN_TARGET` validation with `CONFIRM_TARGETS` validation so a plan
  that assembles is a plan that confirms (F3).

### Phase B5 — Trustworthy previews (existing FORECAST panels, extended)
Per assignment row: expected hits → wounds → **unsaved wounds / models slain**
(explicitly staged, so saves are never silently omitted — the Mordheim
lesson), with the modifier chain on hover.

**Suggested order**: B1 → B2 → B3 (each independently shippable and windowed-testable);
B4/B5 opportunistically alongside.

---

## 5. Open questions

1. Dock position for B2 — extend the right HUD (replace declaration widgets in
   place) or a new bottom strip? Right-HUD reuse avoids new layout work.
2. Keep a separate ordering step at all, or is "reorder rows in the dock before
   pressing Roll" enough? (Default order = declaration order.)
3. Networked fast roll still uses the combined single-batch path — schedule the
   MP-safe port of the auto-continue design?
4. Repair plan for the three pre-existing broken split-fire/reroll scenarios
   (fixture terrain fallout) — fold into this workstream?
