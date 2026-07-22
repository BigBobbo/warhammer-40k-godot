# Game Controller Audit — Player-Facing Steps & Controls (2026-07-22)

Audit of the per-phase **controllers** — for every step where a player makes a
decision or gives input, what the control is, what action it dispatches, and
where there are **gaps, mismatches, irregularities, or improvement areas.**

- **Method:** parallel static source audit (7 phases), every claim cited to
  `file:line`. This is a **read-only** audit; findings are code-traced unless
  marked *(inferred)* or *(runtime repro recommended)*. No windowed run was done,
  so per-phase behavioural traps are reasoned from the handlers, not executed.
- **Backing detail:** full per-phase reports live in the session scratchpad
  (`audit_deployment.md`, `audit_command.md`, `audit_movement.md`,
  `audit_shooting.md`, `audit_charge.md`, `audit_fight.md`,
  `audit_scoring_prebattle.md`, `audit_infrastructure.md`).
- **Companion doc:** `40k/docs/CONTROLLER_CONTROLS_MAP.html` — the **gamepad
  source of truth**: every controller button at every decision point, per-state,
  with the "can the right panel be driven on the pad?" answer, live screenshots,
  and the controller-specific gaps. Its button tables are generated from
  `PadRouter.HINTS_*` and guarded by `tests/test_controller_controls_doc_sync.gd`.
  This audit covers phase↔action drift and AI-only abilities; that doc covers the
  button mapping.

---

## 0. Remediation status (living tracker)

Fixes are being worked through in priority order, **one merged PR per item**, each
validated against the running game with a new windowed scenario under
`40k/tests/scenarios/sp/` (dialogs are screenshot-confirmed). Update this list as
items land so any session can resume by reading it + `git log`.

**Workflow for each item** (so a fresh session can pick up):
1. `git fetch origin main && git checkout -B claude/game-controller-audit-ni0mip origin/main` (re-verify the item is still live — `main` moves fast).
2. Fix, following the proven recipe where it fits: a phase emits a `*_available` / `*_required` signal or gates on a `USE/DECLINE_*` action; the controller connects it in `set_phase` / `phase_signal_map` and shows a dialog for the local human (skip AI — `AIPlayer.is_ai_player(player)` — and non-owning MP seats to avoid a double-submit); the dialog dispatches the action.
3. Add a windowed scenario (model on an existing dialog scenario, e.g. `fight_moment_shackle_ui.json`); run `bash 40k/tests/run_scenarios.sh tests/scenarios/sp/<id>.json`; spot-check regressions on 1–2 neighbouring scenarios.
4. Bump `40k/data/version_history.json` for player-facing changes; commit; rebase onto `origin/main`; push `--force-with-lease`; open PR; merge.

Environment (first run in a fresh container): `export PATH="$HOME/bin:$PATH"; godot --headless --path 40k --import`. NDJSON bridge client at (session scratchpad)`/mcp.py`.

### ✅ Done (merged)
- **P0 #1 — Command battle-shock UI renders** — PR #742 (`command_battleshock_ui_renders.json`, 13/13).
- **P0 #2 — Fight Moment Shackle dialog** — PR #745 (`fight_moment_shackle_ui.json`, 14/14 + screenshot).
- **P0 #3 — Shooting Distraction Grot dialog** — PR #746 (`shooting_distraction_grot_ui.json`, 12/12 + screenshot).
- **P0 #4 — Redeployment soft-lock (End always valid; optional phase)** — PR #747 (`redeployment_optional_end.json`, 10/10).
- **P1 — Movement Bomb Squigs dialog** — PR #748 (`movement_bomb_squigs_ui.json`, 13/13 + screenshot).

### ⏳ Open (priority order)
- **P1 — AI-only abilities still needing a human control** (same dialog recipe for the reactive ones):
  - Movement: Deff From Above, Grot Oiler, Mekaniak, Sawbonez, Quicksilver, Da Jump (placement), Surge.
  - Shooting: Ammo Runt, Pulsa Rokkit, Shooty Power Trip, Swift as the Eagle, Wazblasta; Ritual / Terraform actions.
  - Command: Combat Doctrine, Martial Mastery/Ka'tah select, Issue Taktik, Da Kaptin, Psychic Veil, Unleash the Lions.
  - Fight: per-model weapon choice, split attacks across targets, `SELECT_MELEE_WEAPON` (deeper UX).
  - Charge: 11e declare-then-pick-targets-after-roll (deeper UX).
  - Deployment: Castellan's Mark redeploy; "Place in Reserves" (verify vs. Formations before acting).
- **P2 — mismatches** (§4): dead buttons (`VOLUNTARY_DISCARD`, Movement "Embark"), stratagem-panel phase bypass, Fight dead emitters (`CONFIRM_ATTACKS` / `CLEAR_ALL_ASSIGNMENTS`), Charge overwatch/tank-shock missing `player`, Deployment Infiltrator 9" vs 8", `SWITCH_PLAYER` orphan, "Shoot All Remaining" skips allocation, Scout ">9"" vs 8".
- **P3 — irregularities / dead code** (§4): keybinding collisions, `get_available_actions()` not driving UI, inconsistent End-Phase ownership, dead dialogs/panels, discoverability.

> Note: `374_panoptispex_ignores_cover` fails on clean `main` (pre-existing, unrelated) — not introduced by any fix above.

---

## 1. How input flows (architecture primer)

| Layer | Role |
|---|---|
| **Phase** (`40k/phases/*.gd`, extends `BasePhase`) | The "model". `validate_action` / `get_available_actions` / `process_action`. Defines the action vocabulary (`{"type": ...}`). Reads live `GameState.state`. |
| **Controller** (`40k/scripts/*Controller.gd`, extends `PhaseControllerBase`) | The "view". Owns `board_view` / `hud_bottom` / `hud_right`. Turns clicks/keys/drags/dialogs into actions and dispatches them. |
| **Main.gd** (~14,400 lines) | Routes raw input, wires controller↔phase signals, owns some shared UI (notably the generic **End Phase** button), and for Deployment/Scout does much of the input handling itself. |
| **PhaseManager** | Owns phase lifecycle. Does **not** own controllers — Main.gd does. |

**The single most important structural fact (Finding X1, below): the human UI
is not generated from `get_available_actions()`.** That method is essentially an
**AI-facing API** (consumed by `AIPlayer.gd` / `AIDecisionMaker.gd`). Each
controller hardcodes its own buttons separately. So "the phase can legally do X"
and "a button exists for X" are maintained independently — which is the root
mechanism behind almost every *Gap* in this report: **the AI can make many
decisions a human player simply cannot.**

---

## 2. Cross-cutting findings (infrastructure)

| # | Finding | Evidence |
|---|---|---|
| **X1** | **UI not driven by `get_available_actions()`** — it is AI-facing; controllers hardcode buttons, so phase-modelled actions with no button are reachable only by the AI. Root cause of most Gaps below. | `AIPlayer.gd:703,1772,1809`; only partial reads in `ChargeController.gd:3813`, `CommandController.gd:579`, `FightController.gd:892`, `MovementController.gd:907`. |
| **X2** | **Each controller reinvents its action-request signal** (`command_action_requested`, `move_action_requested`, `shoot_action_requested`, `charge_action_requested`, `fight_action_requested`, `scoring_action_requested`) with 6 near-duplicate handlers in Main. No shared `action_requested` on the base. | `Main.gd:5221,5282,5318,5352,5393,5425`. |
| **X3** | **Deployment & Disembark are off-pattern.** Deployment has no request signal (talks to `PhaseManager.current_phase_instance` directly, Main dispatches). Disembark emits `disembark_completed/_canceled` and reports back to Movement. | `DeploymentController.gd:366-369,822,1152`; `DisembarkController.gd:432,534,593`. |
| **X4** | **"End Phase" ownership is inconsistent** — controller HUD button in Command/Charge/Shooting; Main.gd's generic phase-action button in Movement/Scoring; both in some. Only some paths show the "untested units" warning. | `CommandController.gd:160,981`; `ChargeController.gd:167`; `MovementController.gd:1376`; `ScoringController.gd:57`; `Main.gd:10254,10269,10294`. |
| **X5** | **Global keybindings with ad-hoc collisions.** Keys registered globally (no per-phase namespace): `E`=rotate-model **and** end-shooting; `F`=focus-P2 **and** fit-view; `G`=terrain **and** grid; `R`=ruler **and** replay-panel; `N`=labels **and** skip-shooter; `V`=rotate-board **and** VP-timeline; `S`=pan-down **and** stratagem-panel; `Tab`=threat **and** cycle-shooter. Some safe via context-gating; `find_conflict()` only guards the rebind UI, not built-in defaults. Only Shooting promoted its hotkeys into `KeybindingManager`; other phases use hardcoded keycode checks. | `KeybindingManager.gd:34-129,323`. |

---

## 3. Per-phase step maps & issues

Severity tags: **P0** player blocked / soft-lock · **P1** feature unreachable by humans · **P2** mismatch (dead/bypassed/wrong-arg) · **P3** irregularity / UX / dead code.

### 3.1 Pre-battle & setup phases

Only the 7 battle phases have controllers (`Main.gd:56-63`). The 5 pre-battle
phases are driven **inline from Main.gd + standalone dialogs** — a structural
inconsistency vs the rest of the game (X-prebattle).
Order: FORMATIONS → ROLL_OFF → DEPLOYMENT → REDEPLOYMENT → FIRST_TURN_ROLLOFF → SCOUT (`PhaseManager.gd:320-334`).

| Phase | Steps & control | Action |
|---|---|---|
| **Formations** | Modal `FormationsDeclarationDialog`: leader attach, warlord, transports, reserves; "Confirm"/"Skip" (`Main.gd:8525-8593`) | `DECLARE_*` / `DESIGNATE_WARLORD` / `CONFIRM_FORMATIONS` |
| **Roll-off** | Animated `RollOffDialog`: "Roll" → winner picks "Deploy first/second"; tie→re-roll (`Main.gd:8362-8523`) | `ROLL_OFF_DEPLOYMENT`, `CHOOSE_DEPLOYMENT` |
| **First-turn roll-off** | Same dialog, "Roll" then "Continue" (no choice) (`Main.gd:8485-8494`) | `ROLL_OFF_FIRST_TURN`, `CONFIRM_FIRST_TURN` |
| **Redeployment** | **No UI** — auto-skips; only "End Redeployment" | `END_REDEPLOYMENT_PHASE` |
| **Scout** | Unit-list select → drag on board → card Confirm/Skip; reserves reuse DeploymentController (`Main.gd:7626,13756-13946,2615`) | `BEGIN_SCOUT_MOVE`, `SET_SCOUT_MODEL_DEST`, `CONFIRM/SKIP_SCOUT_MOVE`, `END_SCOUT_PHASE` |

**Issues**
- **P0 — Redeployment has no human UI.** `BEGIN/CONFIRM/SKIP_REDEPLOY` /
  `SEND_TO_STRATEGIC_RESERVES` are referenced only by an AI highlight map
  (`Main.gd:1847`). A human with a redeploy-capable unit can't act **and** can't
  end the phase (validation needs pending==0), so it silently advance-skips
  (`Main.gd:10328`). *Highest-impact pre-battle gap.*
- **P2 — Formations phase-button path confirms *without* declarations**
  (`Main.gd:8627`) — modal-shielded today, but a footgun.
- **P2 — Scout labels say ">9\"" but the phase uses 11e >8"** (`ScoutPhase.gd:132`) — same 8-vs-9 inconsistency as Deployment (below).
- **P3 — Dead duplicate scout impl** (`SCOUT_MOVES` click-to-place) still keyed in controller setup (`Main.gd:4759`).

### 3.2 Deployment (`DeploymentController.gd` + `DeploymentPhase.gd`)

| Step | Control (file:line) | Action |
|---|---|---|
| Select unit to deploy | Roster/bottom-panel row (`Main.gd:7604,7742`) → `begin_deploy()` | — |
| Combat Squads split | Auto `ConfirmationDialog` "Split"/"Deploy as 10" (`DeploymentController.gd:397-439`) | *(writes GameState directly)* |
| Pick model profile | `ModelTypePickerPanel` in card (`:2743`) | — |
| Place model | Left-click board; formation modes Single/Spread/Tight (`:114-136`, `Main.gd:4912`) | — |
| Rotate model | `Q`/`E` + mouse wheel (`:156-188`) | — |
| Reposition placed model | Shift+click pick up, click drop, right-click cancel (`:119-146,2373`) | — |
| Undo / Reset | "Undo" + `Ctrl+Z`; "Reset Unit" (`Main.gd:7875,7981`) | — |
| Confirm placement | "Confirm" when placed==total (`:815,989`) | `DEPLOY_UNIT` / `COMPOSITE_DEPLOY` |
| Embark at deployment | `TransportEmbarkDialog` on confirm (`:864`) | `EMBARK_UNITS_DEPLOYMENT` |
| Attach leaders | `CharacterAttachDialog` on confirm (`:855`) | `ATTACH_CHARACTER_DEPLOYMENT` |
| Alternate players | **Automatic** (`TurnManager.check_deployment_alternation`) — no manual control | — |
| End deployment | Top-right "End Deployment" → summary (`Main.gd:8685`) | `END_DEPLOYMENT` |

**Issues**
- **P1 — Castellan's Mark redeploy has no UI.** The phase fully models it and
  **holds the phase open awaiting it** (`DeploymentPhase.gd:45-49,1391-1523`), but
  there are zero `Castellan` refs in `scripts/` — only tests/bridge dispatch it.
- **P1 — "Place in Reserves" button is unreachable.** Created but `.visible`
  never set true (`Main.gd:2086` vs only `false` at `2089,6648,6723,6980`);
  `PLACE_IN_RESERVES` excluded from available actions (`DeploymentPhase.gd:1349`).
  Reserves moved to Formations, but the button is dead here with no fallback.
- **P2 — Infiltrator distance mismatch: controller hardcodes 9"**
  (`DeploymentController.gd:2648,2660`) while the phase is edition-aware **8"**
  (`DeploymentPhase.gd:312`). Controller wrongly blocks legal 8–9" placements.
- **P2 — `SWITCH_PLAYER` orphaned** — validated/processed/advertised by the phase
  (`:461,1045,1359`) but never dispatched by UI (TurnManager switches directly).
- **P2 — Combat Squads split bypasses the action pipeline** (writes GameState
  directly, `:397-439`) — replay/multiplayer risk.
- **P3 — Dead code:** `DeploymentTransportDialog.gd` / `DeploymentTransportUI.gd`
  never instantiated (call a nonexistent `get_available_transports_for_unit`).
- **P3 — Shift+click reposition is undiscoverable and likely broken for combined
  bodyguard+character deploys** — indexes bodyguard-only `models` while
  `temp_positions` is sized to combined models (`:2382,2434,2508`) *(inferred)*.

### 3.3 Command (`CommandController.gd` + `CommandPhase.gd`)

| Step | Control (file:line) | Action |
|---|---|---|
| CP gain | Automatic, read-only (`:202-229`) | — |
| Battle-shock roll | "Roll Battle-shock: <name>" button (`:626`) | `BATTLE_SHOCK_TEST` |
| Insane Bravery | "INSANE BRAVERY (1 CP)" (`:641`) | `USE_STRATAGEM` |
| Command Re-roll | `CommandRerollDialog` (`:987`) | `USE/DECLINE_COMMAND_REROLL` |
| Stratagems | "S" key / HUD → `StratagemPanel` "Use" (`StratagemPanel.gd:175`) | *(bypasses phase)* |
| Waaagh! / Plant Banner | Buttons (`:709,750`) | `CALL_WAAAGH`, `PLANT_WAAAGH_BANNER` |
| Oath of Moment | Per-target button (`:800`) | `SELECT_OATH_TARGET` |
| Review/Replace secondary | `SecondaryMissionReviewDialog` (`:1060`) | `REPLACE_SECONDARY_MISSION` |
| New Orders | Button (`:519`) | `USE_NEW_ORDERS` |
| GDM card dialogs (Marked for Death, Tempting Target, Beacon, Guards, Condemn, Relic) | Dialogs, "Pick on board" | `RESOLVE_*` / `DISMISS_*` |
| End phase | "End Command Phase [Enter]" **or** HUD button (two paths) | `END_COMMAND` |

**Issues**
- **P0 — The entire battle-shock roll UI never renders.**
  `_setup_battle_shock_section` early-returns on null `current_phase`
  (`CommandController.gd:574`); its only call site runs during `_ready`/`add_child`
  (`Main.gd:5200`), and `set_phase` sets the phase **afterward** (`Main.gd:5213`);
  `_refresh_ui` never rebuilds it. So the roll button + Insane Bravery button are
  never shown. Tests pass only because battle-shock **auto-resolves on phase end**
  (`CommandPhase.gd:2588). ✅ Code-confirmed; runtime repro recommended.*
- **P1 — Faction command choices are AI-only.** Combat Doctrine, Martial
  Mastery/Ka'tah, Issue Taktik, Here-Be-Loot, Da Kaptin, Psychic Veil, Unleash the
  Lions — all handled by the phase but dispatched only by `AIDecisionMaker.gd`.
  Worst case: the progress indicator shows "Step 2/3 — Choose Martial Mastery"
  (`:2258`) for a step a human Custodes player **cannot complete**.
- **P2 — "Discard (+1 CP)" is a dead button.** It dispatches `VOLUNTARY_DISCARD`,
  which CommandPhase does not handle → "Unknown action type" (moved to Scoring;
  `tests/test_secondary_missions.gd:415`).
- **P2 — Stratagem panel bypasses the phase** — calls `strat_manager.use_stratagem`
  directly (`Main.gd:13054`), skipping phase validation/side-effects, no target.
- **P3 — Two "[Enter]" end-phase controls** (X4); only the HUD one shows the
  untested-units warning. "S" collides (pan-down + stratagem panel, X5).

### 3.4 Movement (`MovementController.gd` + `MovementPhase.gd` + `DisembarkController.gd`)

| Step | Control (file:line) | Action |
|---|---|---|
| Select unit | ItemList row (`:444`); deployed unit auto-fires (`:1101`) | `BEGIN_NORMAL_MOVE` |
| Choose mode | 4 radios; Normal/Advance/Remain → "Confirm Movement Mode"; Fall Back fires on press (`:519,1273,1421`) | `BEGIN_ADVANCE/…`, `REMAIN_STATIONARY`, `LOCK_MOVEMENT_MODE` |
| Advance roll / re-roll | Phase rolls D6; `command_reroll_opportunity` dialog (`:4856`) | `USE/DECLINE_COMMAND_REROLL` |
| Move models | Left-drag; group via Ctrl/Shift/Ctrl+A (`:2033,2358`) | `STAGE_MODEL_MOVE` |
| Pivot | Right-drag or `Q`/`E`, non-circular bases (`:3411`) | `APPLY_PIVOT_COST` (auto) |
| Disembark | Embarked row → `DisembarkDialog` → board clicks (`:2730`) | `CONFIRM_DISEMBARK` |
| Embark | Phase auto-prompt after confirm (`MovementPhase.gd:4997`) | `EMBARK_UNIT` |
| Reserves / Deep Strike / Rapid Ingress | Reserve rows → Main + DeploymentController (`Main.gd:2444,2833`) | `PLACE_REINFORCEMENT`, `PLACE_RAPID_INGRESS_REINFORCEMENT` |
| Undo / Reset / End-unit | 3 buttons (`:694`) | `UNDO_LAST_MODEL_MOVE`, `RESET_UNIT_MOVE`, `CONFIRM_UNIT_MOVE` |
| Kunnin' Infiltrator | Dedicated button/popup (`:1292`) | `ACTIVATE_KUNNIN_INFILTRATOR` |
| End phase | Main's generic button (`Main.gd:10254`) | `END_MOVEMENT` |

**Issues**
- **P1 — Movement abilities are AI-only.** `BEGIN_SURGE_MOVE` (controller whitelist
  hardcoded to Kunnin, `:5239`), Da Jump (`USE/PLACE_DA_JUMP`, zero controller
  refs), Bomb Squigs / Deff From Above / Grot Oiler (phase emits signals but
  `set_phase` `:832-853` never connects them — only `AIPlayer` does), and
  Mekaniak / Sawbonez / Quicksilver (no signal declared at all).
- **P2 — Dead "Embark" button** (`Main.gd:4382`) is a no-op; embark only happens
  via the phase's auto-prompt.
- **P2 — Fall Back skips the confirm gate and never sends `LOCK_MOVEMENT_MODE`**
  (`:1273,1421`) despite it being the mode that can destroy models (desperate escape).
- **P2 — Advance silent trap:** picking the Advance radio then dragging moves under
  the **Normal** cap until "Confirm Movement Mode" is clicked (`:1243`).
- **P3 — Disembark logic is split** across `DisembarkController` (human) vs phase
  `DISEMBARK_UNIT` (AI); combat-disembark state is duplicated in both
  (`MovementController.gd:22`, `MovementPhase.gd:47`).
- **P3 — Pivot/rotation is undiscoverable** (no hint; cost shown only post-hoc,
  `:491,3126`); right-click is overloaded (rotate vs context menu vs disembark undo,
  `Main.gd:13243`); two confusable buttons "Confirm Movement Mode" vs "End This
  Unit's Move" (flagged in-code, `:710`).
- ✅ Every controller-dispatched type has a matching phase handler (no orphans).

### 3.5 Shooting (`ShootingController.gd` + `ShootingPhase.gd`)

| Step | Control (file:line) | Action |
|---|---|---|
| Select shooter | List / board-click / Tab-cycle (`:3775,4981`) | `SELECT_SHOOTER` |
| Shooting-type (11e) | **Auto, no UI** (`ShootingPhase.gd:956`) | — |
| Pick weapon | `weapon_tree` row; illegal greyed (`:3843`) | — |
| Assign target | Click enemy (weapon) / click enemy (none→quick-assign all) (`:5140,5285`) | `ASSIGN_TARGET` |
| Split / move-and-fire | SpinBox pickers (`:5413,5492`) | `ASSIGN_TARGET` + model_ids |
| Clear / undo | "Clear All" / "Undo Last" (`:4003,4044`) | `CLEAR_ALL_ASSIGNMENTS`, `CLEAR_ASSIGNMENT` |
| Confirm targets | "Confirm Targets" / Space (`:4092`) | `CONFIRM_TARGETS` |
| Order weapons + roll | Dock ▲▼ + "Roll to Hit ▶" / "Fast Roll All" (`ShootingResolutionDock.gd:218`) | `RESOLVE_WEAPON_SEQUENCE` |
| Hits→wounds→saves | Dock primary button (`:1514`) | `CONTINUE_TO_WOUNDS`, `CONTINUE_TO_SAVES`, `FAST_FINISH_SHOOTING` |
| Command re-roll | Dock die chips | `USE_SHOOTING_REROLL` |
| Saves + allocation | `AllocationGroupOverlay`: order ▲▼, Precision, save-reroll, click bases (`:3050`) | `APPLY_SAVES` |
| Next / Complete | "Next Weapon ▶" / "Complete Shooting" | `CONTINUE_SEQUENCE`, `COMPLETE_SHOOTING_FOR_UNIT` |
| Grenade | Button (`:6242`) | `USE_GRENADE_STRATAGEM` |
| Reactive stratagem (defender) | StratagemDialog (`:3428`) | `USE/DECLINE_REACTIVE_STRATAGEM` |
| Perform / Start / Burn action | Buttons | `PERFORM_SECONDARY_ACTION`, `START_ACTION`, `BURN_OBJECTIVE` |
| Skip unit | **"N" key only, no button** | `SKIP_UNIT` |
| End phase | "E" / global button | `END_SHOOTING` |

**Issues**
- **P0 — Distraction Grot can soft-lock.** The faction reactive decisions
  (Distraction Grot, Ammo Runt, Pulsa Rokkit, Shooty Power Trip) are connected only
  in `AIPlayer`, **not** the controller's `phase_signal_map`. For Distraction Grot
  there is no `END_SHOOTING` escape while pending (`ShootingPhase.gd:4979-4996`,
  *code-traced*) → a human on the wrong side of it is stuck.
- **P1 — Ritual & Terraform actions and faction abilities are AI-only.**
  `PERFORM_RITUAL_ACTION` / `PERFORM_TERRAFORM_ACTION` and Swift-as-the-Eagle /
  Wazblasta (no signal at all) have no human button (`AIDecisionMaker` only).
- **P1 — No in-panel Skip/End buttons** (keyboard-only, discoverability); no 11e
  shooting-type chooser.
- **P2 — StratagemPanel bypasses the phase's `USE_STRATAGEM` handler** (same as X1/Command).
- **P2/P3 — "Shoot All Remaining" atomic path skips defender allocation** (`:4249`);
  ShootingPhase handles a cross-phase `END_MOVEMENT` no-op.
- **P3 — Dead code:** `WeaponOrderPanel` / `WoundAllocationPanel` installed but unused;
  single-player vs networked use divergent resolution UIs (dock vs WeaponOrderDialog).

### 3.6 Charge (`ChargeController.gd` + `ChargePhase.gd`)

| Step | Control (file:line) | Action |
|---|---|---|
| Select unit | "UNITS THAT CAN CHARGE" row (`:843`) — local only | — |
| Declare target(s) | Click / Ctrl+Click multi-select, then "Declare Charge" (`:1408,3163`) | `DECLARE_CHARGE` |
| Roll 2D6 | "Roll 2D6" (`:3207`) | `CHARGE_ROLL` |
| Re-roll | CommandReroll / ability dialogs (`:4073`) | `USE/DECLINE_ABILITY_REROLL`, `USE/DECLINE_COMMAND_REROLL` |
| Overwatch (defender) | `FireOverwatchDialog` (`:4231`) | `USE/DECLINE_FIRE_OVERWATCH` |
| Skip | "Skip Charge" (`:3219`) | `SKIP_CHARGE` |
| Charge move | Board drag gated by `awaiting_movement`; multi-select, Q/E, base-snap, "Snap to Contact", "Undo Last Model" (`:2312`) | — |
| Confirm | "Confirm Charge Moves" (`:2945`) | `APPLY_CHARGE_MOVE`, then `COMPLETE_UNIT_CHARGE` |
| Tank Shock | `TankShockDialog` (`:4425`) | `USE/DECLINE_TANK_SHOCK` |
| Heroic Intervention (defender) | End-of-phase `HeroicInterventionDialog` (`:4313`) | `USE/DECLINE_HEROIC_INTERVENTION`, `APPLY_HEROIC_INTERVENTION_MOVE` |
| End phase | Main's generic button (`Main.gd:10269`) | `END_CHARGE` |

**Issues**
- **P1 — The 11e "declare, roll, *then* pick targets" path is unreachable.** The
  controller forces pre-roll target selection (`:3164`; `can_declare` needs targets
  `:1276`) even though the phase supports empty declaration (`ChargePhase.gd:326`).
- **P2 — Overwatch/Tank-Shock actions omit `player`** (rely on phase stored-state
  fallback — fragile for network).
- **P2 — Dead code:** `_on_end_phase_pressed` (`:3238`) never connected; duplicate
  roll-result handlers `_on_charge_roll_made` / `_on_dice_rolled` (`:3566,3610`).
- **P1/P2 — `SELECT_CHARGE_UNIT`** (phase action) is never dispatched from UI
  (selection is local-only); `HEROIC_INTERVENTION_CHARGE_ROLL` is a dead no-op;
  `USE_STRATAGEM` only via the cross-phase panel, not the charge panel.
- **P3 — UX:** roll button stays enabled during the Overwatch pause; "Skip" can
  un-declare a committed charge; "Snap to Contact" can place models that still fail
  the confirm.
- ✅ Failure/ALL-targets comms are strong: pre-roll "Needs 2D6 ≥ N to reach ALL
  targets", per-target ER requirement, red INSUFFICIENT_ROLL, categorized failure
  panel with rule tooltips (`:1687,3446`).

### 3.7 Fight (`FightController.gd` + `FightPhase.gd`)

| Step | Control (file:line) | Action |
|---|---|---|
| Pile-In (12.02) | `PileIn_<id>` buttons + PileInDialog drag/pivot/Auto/Reset (`:2485`) | `PILE_IN`, `END_PILE_IN` |
| Select fighter (alternation) | `FightSelectionPanel` `Fight_<id>` buttons, subphase-gated (`:1679`) | `SELECT_FIGHTER` |
| Epic Challenge | EpicChallengeDialog (`:1905`) | `USE/DECLINE_EPIC_CHALLENGE` |
| Ka'tah stance (Custodes) | KatahStanceDialog (`:2041`) | `SELECT_KATAH_STANCE` |
| Assign attacks | AttackAssignmentDialog + "Fight!" (`:2181`) | `BATCH_FIGHT_ACTIONS` |
| Hits→wounds | FightResolutionDock / Space (`:1514`) | `CONTINUE_TO_WOUNDS`, `CONTINUE_TO_SAVES`, `USE_FIGHT_REROLL` |
| Saves/allocation (defender) | WoundAllocationOverlay (`:3910`) | `APPLY_MELEE_SAVES` |
| Counter-Offensive (inactive player) | CounterOffensiveDialog (`:1955`) | `USE/DECLINE_COUNTER_OFFENSIVE` |
| Consolidate (12.07) | `Consolidate_<id>` + ConsolidateDialog (`:2584`) | `CONSOLIDATE`, `END_CONSOLIDATION` |
| Sweeping Advance / Acrobatic Escape | Dialogs w/ board-drag (`:4069`) | `SWEEPING_ADVANCE`, `ACROBATIC_ESCAPE` |
| End phase | Global button (`Main.gd:10270`) | `END_FIGHT` |

**Issues**
- **P0 — Moment Shackle has no human UI.** `get_available_actions()` short-circuits
  and returns **only** `USE/DECLINE_MOMENT_SHACKLE` while a unit is pending
  (`FightPhase.gd:3334-3355`), but FightController has **zero** `MOMENT_SHACKLE`
  refs and no dialog. A human Blade Champion can never make the choice; the
  AI-driven gate makes a hard soft-lock likely *(needs live repro to confirm it
  also blocks `validate_action` for other actions)*.
- **P1 — No per-model weapon choice.** AttackAssignmentDialog forces the whole unit
  onto one weapon (empty `models`, single assignment; `AttackAssignmentDialog.gd:423`).
- **P1 — Cannot split attacks across targets** (single-select target).
- **P1 — `SELECT_MELEE_WEAPON` unreachable** — `_on_select_melee_weapon_pressed`
  never connected (`:930`).
- **P2 — Dead emitters:** `CONFIRM_ATTACKS` (`:1435`) and `CLEAR_ALL_ASSIGNMENTS`
  (`:1487`) have no phase handler; `ASSIGN_ATTACKS_UI` is offered
  (`FightPhase.gd:3466`) but not processable; `_on_auto_fight_pressed` builds a
  wrong-shaped `ASSIGN_ATTACKS` (payload vs top-level).
- **P3 — Dead `attack_tree` / `target_basket` subsystem still in the input path**
  (`target_basket.add_item` at `:1635` would null-crash if reached); an
  "informational" FIGHT SEQUENCE list also dispatches a parallel `SELECT_FIGHTER`
  (`:350,1050`); per-event debug `print_stack()` in hot paths.

### 3.8 Scoring (`ScoringController.gd` + `ScoringPhase.gd`)

| Step | Control (file:line) | Action |
|---|---|---|
| Primary objectives | **Auto**, no confirmation (`ScoringPhase.gd:459`) | — |
| Secondary missions | **Auto** on phase enter (`:105-138`) | — |
| 11e card action (Triangulate/Decoy…) | Dialog target buttons + Skip (`:825-951`) | `RESOLVE_CARD_ACTION`, `SKIP_CARD_ACTION` |
| Discard secondary | Right-panel "Discard (+1 CP)" **and** MissionDiscardDialog on End Turn (`:576`, `Main.gd:10957`) | `DISCARD_SECONDARY` |
| Coherency removal (03.03) | Dialog "Remove <model>" (`:722`) | `REMOVE_MODEL_FOR_COHERENCY` |
| End-turn redeploy / Acrobatic Escape | Dialogs (`:976,1102`) | `END_TURN_REDEPLOY`, `ACROBATIC_ESCAPE_VANISH` (+DECLINE) |
| End Turn | Phase-action button "End Turn" (`Main.gd:10294`) | `END_SCORING` |

**Issues**
- **P1/P3 — Scoring is fully automatic, no player confirmation** — acceptable, but
  worth a visible "scored X VP" acknowledgement step.
- **P2 — `END_TURN` vs `END_SCORING`** — controller dispatches `END_TURN`, Main's
  button dispatches `END_SCORING` (both handled; cosmetic dual vocabulary).
- **P3 — Two discard UIs** (right-panel buttons + dialog); dead
  `ScoringController._on_end_turn_pressed`; redeploy/Acrobatic dialogs say
  "15 seconds"/"60s" mismatched timer labels.

---

## 4. Master prioritized issue list

### P0 — A human player gets stuck or a core step never appears
1. **Command: battle-shock roll UI never renders** (`CommandController.gd:574` + `Main.gd:5200/5213`). *(code-confirmed)*
2. **Fight: Moment Shackle unreachable / likely soft-lock** (`FightPhase.gd:3334-3355`; no controller refs). *(gate confirmed; hard-lock inferred)*
3. **Shooting: Distraction Grot reactive can soft-lock** (no `END_SHOOTING` escape; `ShootingPhase.gd:4979-4996`). *(code-traced)*
4. **Redeployment phase: no human UI; silently auto-skips** (`Main.gd:1847,10328`).

### P1 — Feature modelled but reachable only by the AI (human parity gap)
5. **Command faction choices:** Combat Doctrine, Martial Mastery/Ka'tah, Issue Taktik, Here-Be-Loot, Da Kaptin, Psychic Veil, Unleash the Lions (AI-only; progress bar even shows an uncompletable step).
6. **Movement abilities:** Surge, Da Jump, Bomb Squigs, Deff From Above, Grot Oiler, Mekaniak, Sawbonez, Quicksilver (AI-only or no signal).
7. **Shooting:** Ritual/Terraform actions, Ammo Runt, Pulsa Rokkit, Shooty Power Trip, Swift as the Eagle, Wazblasta (AI-only).
8. **Fight:** per-model weapon choice, splitting attacks across targets, `SELECT_MELEE_WEAPON`.
9. **Deployment:** Castellan's Mark redeploy (phase holds open for it), "Place in Reserves".
10. **Charge:** 11e declare-then-target-after-roll path.

### P2 — Mismatch: dead button, bypassed pipeline, or wrong args
11. **Command "Discard (+1 CP)"** dispatches `VOLUNTARY_DISCARD` the phase rejects.
12. **Stratagem panel bypasses phase validation** in Command & Shooting (`Main.gd:13054`).
13. **Movement dead "Embark" button** (`Main.gd:4382`); **Fall Back skips confirm + `LOCK_MOVEMENT_MODE`**.
14. **Fight dead emitters:** `CONFIRM_ATTACKS`, `CLEAR_ALL_ASSIGNMENTS`, `ASSIGN_ATTACKS_UI`, mis-shaped auto-fight `ASSIGN_ATTACKS`.
15. **Charge** overwatch/tank-shock omit `player`; `SELECT_CHARGE_UNIT` never dispatched.
16. **Deployment Infiltrator 9" vs phase 8"**; `SWITCH_PLAYER` orphaned; Combat Squads split bypasses the action pipeline.
17. **Shooting "Shoot All Remaining"** skips defender allocation; **Scout ">9"" vs 8"**; **Formations confirm-without-declarations**.

### P3 — Irregularities, discoverability, dead code
18. **Keybinding collisions** (E/F/G/R/N/V/S/Tab), resolved ad hoc; only Shooting is rebindable (X5).
19. **Inconsistent "End Phase" ownership** (X4) and **6 bespoke action-request signals** (X2).
20. **Pre-battle phases have no controllers** (X-prebattle) — a whole class of UI lives inline in Main.gd.
21. **Dead code:** `DeploymentTransportDialog/UI`, `WeaponOrderPanel`/`WoundAllocationPanel`, Fight `attack_tree`/`target_basket`, duplicate scout impl, several never-connected `_on_*_pressed`.
22. **Discoverability:** pivot/rotation hints, Shift+click reposition, keyboard-only Skip (Shooting), two-discard-UI / two-end-button confusion.
23. **Disembark split** between `DisembarkController` (human) and phase `DISEMBARK_UNIT` (AI) with duplicated state.

### Structural recommendation
The recurring theme (P0-#1/#2/#3, all of P1, several P2) is **X1: the human UI is
not generated from `get_available_actions()`.** The single highest-leverage fix is
to make each controller render its available player actions **from the phase's
`get_available_actions()`** (at least as a fallback "pending decision" surface),
so any action the phase can gate on always has a corresponding control. That alone
would convert every "AI-only" gap and every soft-lock into a reachable button, and
close the phase↔controller drift at its source. Pair it with a shared
`action_requested` signal on `PhaseControllerBase` (X2) and per-phase keybinding
namespacing (X5).
