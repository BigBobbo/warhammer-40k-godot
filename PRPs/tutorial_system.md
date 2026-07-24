# In-Game Tutorial System ("Basic Trainin'") — Research & Phased Implementation Plan

**Status:** PROPOSED (design doc — no implementation yet)
**Date:** 2026-07-24
**Owner ask:** a tutorial that teaches how *this app* controls — camera, selection,
phase panels, dialogs, transports, characters — for players who already know how
to play Warhammer 40k on the tabletop. Small Ork demo force (Battlewagon with
Boyz inside, a Warboss). Possibly split into several small tutorials. Controller
/ Steam Deck is an explicit design focus.
**Companion docs:** `PRPs/steam_deck_controller_support.md` (the pad scheme this
tutorial teaches; M0–M3 shipped), `CONTROLLER_AUDIT_2026-07.md` (per-phase
control map + known gaps), `40k/docs/CONTROLLER_CONTROLS_MAP.html` (gamepad
source of truth), `40k/tests/scenarios/_schema.md` (step vocabulary this design
reuses).

---

## 0. TL;DR

- **What:** a "Tutorial" entry on the main menu opening a lesson picker with
  **7 bite-size lessons (3–6 min each)**, all set in one small scripted
  skirmish: **Orks (Warboss + 10 Boyz + Battlewagon + 10 Gretchin) vs a small
  Space Marine patrol (AI)**. Lessons = the phases of that one battle, so the
  "Full Course" plays them back-to-back as a single continuous game, and each
  lesson is *also* individually launchable from a saved checkpoint.
- **How:** a data-driven **TutorialManager autoload** runs lesson scripts
  (JSON). Each step: show a short prompt (device-aware text + button glyphs),
  highlight the control (spotlight overlay with cutout), **allow-list** which
  actions may pass through the existing action pipeline, and advance when the
  player *does the thing* (outcome-based conditions, never a "Next" button for
  taught actions). The step/selector/condition vocabulary is deliberately the
  same one `ScenarioRunner` already proves across 362 windowed scenarios.
- **Why this shape:** research on comparable digital board-game adaptations
  (Root, Wingspan, Scythe, Battlesector, Blood Bowl 3, Into the Breach — §2)
  says: short revisitable lessons, player's hands on the controls at all times,
  prompts adjacent to the action, device-correct glyphs, never forced, never
  reload the board mid-lesson, and QA each step like a feature.
- **Controller:** the tutorial teaches the **already-shipped pad scheme**
  (PadRouter / VirtualCursor / hint bar). Every step is completable on pad and
  on mouse; prompts render glyph chips on pad and rebind-aware key names on
  keyboard. Steps advance on *outcomes* (unit moved, dialog closed), so both
  input devices satisfy the same lesson script.
- **Validation:** every lesson ships with windowed scenarios (mouse + pad
  variants) that drive the lesson's real player path end-to-end, plus a
  selector-lint tool so UI refactors that would break a lesson fail CI instead
  of failing a player.

---

## 1. Goal and guiding principles

**Goal:** a player who knows tabletop 40k but has never touched this app can,
in ~20–30 minutes (or by cherry-picking 2–3 lessons), operate every core
surface of the game — on mouse+keyboard or entirely on a gamepad/Steam Deck —
without reading external docs.

Principles (each traces to evidence in §2):

1. **Teach the app, not the rules.** No explanations of what an Advance *is* —
   only where the Advance button lives and that the mode must be confirmed
   before dragging. Root Digital is loved for serving exactly this
   "knows the tabletop, not the app" audience. Every lesson step must name a
   *control*, not a *rule*; that is the review checklist for lesson content.
2. **Hands on the controls at all times.** Steps advance when the player
   performs the real action — never a "watch this" autoplay, never the tutorial
   making choices for the player (Terraforming Mars' documented failure).
   Pure-reading steps (rare) use an explicit Continue.
3. **Short, optional, revisitable.** Lessons are 3–6 minutes, individually
   launchable, replayable forever, with per-lesson completion checkmarks
   (Wingspan model). The tutorial is *suggested once*, never forced (Into the
   Breach model; BattleTech shows forced long tutorials read as friction to
   domain experts).
4. **One concept per step, very little text.** Target ≤ 2 short lines per
   prompt (George Fan's "fewer words" rule; Blood Bowl 3's wall-of-text is the
   documented failure). Flavor lives in titles and bark lines, not in
   instructions.
5. **Prompts sit next to the action** and point at it (spotlight + arrow), not
   parked at a screen edge while the player's eyes are mid-board (BB3 failure).
6. **Device-adaptive, controller-first.** Prompt text and glyphs are generated
   from the live input device (`InputDeviceManager.device_changed`), steps are
   completable by pad focus/cursor alone, and success conditions are
   outcome-based so the engine never cares which device did it. Showing
   keyboard prompts on pad is both a Battlesector-documented failure and a
   Steam Deck Verified failure.
7. **Wrong input nudges, never breaks.** The action gate rejects out-of-scope
   actions with a friendly toast; nothing the player can press may soft-lock a
   lesson (Scythe's documented failure). "Exit Tutorial" is always one click
   away and never gated.
8. **Never reload the board mid-lesson**, and keep the Full Course continuous
   (Scythe reloaded per-mechanic and reviewers called it jarring). Lesson
   boundaries coincide with the battle's own phase boundaries.
9. **Tutorials are features and rot like features.** Every lesson lands with
   windowed scenarios and a selector lint; a taught button that moves must
   break CI, not the player (Scythe/BB3 shipped broken steps a single scripted
   playthrough would have caught).
10. **Additive architecture.** No rewrites of Main.gd/controllers to ship this;
    the tutorial observes and gates the existing action pipeline at its one
    choke point and draws its own overlay on top.

Non-goals: teaching 40k rules; AI-vs-AI demo battles; multiplayer tutorials;
localization (app is English-only today); voice-over.

---

## 2. Research: how comparable games did it

Full sourced write-up in the research appendix at the end of this file (§9).
The distilled findings that shaped this design:

| Game | What it evidences |
|---|---|
| **Root: Digital Edition** (Dire Wolf) | The benchmark: tutorials menu + short per-faction guided missions; explicitly praised for "introducing the digital specific elements to players who are familiar with the original game" — our exact audience. Deck Verified. |
| **Wingspan** (digital) | "Refreshingly short" sectioned tutorial, **each section revisitable after completion** — the lesson-picker + checkmarks model. Its *Switch port* is the counter-example: inconsistent device-to-widget mappings sank it. |
| **W40k: Battlesector** | Closest comp (40k, turn-based, gamepad + Deck retrofit). Tutorial = "series of short missions," praised. Its pad failures are the ones to dodge: invisible selection/focus state, and tutorial prompts written for one input device that dead-end on another. |
| **Into the Breach** | Gold standard for optional onboarding: asks once on first play, checkbox to re-enable, skippable mid-stream; systemic UI (previews + tooltips) carries the rest. |
| **Scythe: Digital Edition** | Cautionary tale #1: board reloads between micro-lessons ("jarring"), wrong-click soft-locks, steps that force strategically bad moves. |
| **Blood Bowl 3** vs **BB2** | BB3: text boxes parked at screen edges in "tiny, tiny text" while the player watches mid-board; a step whose required action didn't work. BB2: instruction with personality (Jim & Bob commentators) integrated into real matches — beloved by the GW-license audience. |
| **Terraforming Mars** | Cautionary tale #2: tutorial too long, **plays the player's turn for them**, teaches bad habits, small-font complaints land on the tutorial first. |
| **BattleTech** (HBS) | Mandatory multi-mission tutorial prologue reads as friction for players who already know the domain. |
| **Baldur's Gate 3** | Controller bar-setter (not a tutorial): native pad presentation (radials + focus nav) beats mouse emulation for complex UIs on Deck. Our pad scheme already follows this philosophy; the tutorial teaches it rather than inventing anything. |
| **George Fan (GDC 2012), Bycer, Hodent, NN/g** | Do > read; "do it once = learned"; ≤ ~8 words on screen at a time as the ideal; spread learning over time (progressive disclosure); adaptive hints only for players who need them; contextual just-in-time beats front-loading. |
| **Steam Deck Verified criteria** | Glyphs must match the active device; no keyboard-only prompts; smallest font ≥ 9 px at 1280×800 (12 px recommended); full controller access to all content. No tutorial-specific criteria exist — onboarding is judged through these input/display rules. |
| **Godot ecosystem** | No established in-game coach-mark addon exists; GDQuest's Godot Tours (editor-targeted) validates the architecture: step queue + highlight overlay + *validate the user's real action* before advancing. Spotlight-with-cutout is a solved pattern (shader-with-rect-uniforms or four-rect dimmer). We roll our own thin engine — and we already own most of it (§3.5). |

**Design consequences:** bite-size lesson series (not one long mission) ✱ one
continuous battle for the Full Course (no per-lesson reloads) ✱ optional with
a one-time nudge ✱ outcome-advanced steps ✱ spotlight + adjacent caption ✱
device-generated prompts ✱ error-tolerant gating ✱ per-lesson scenario QA ✱
an Ork instructor voice for personality (BB2 evidence), kept out of the
instruction text itself.

---

## 3. Where the codebase stands today (audit)

All claims verified against source on 2026-07-24 (branch cut from `main`,
v0.94.0) — file:line refs below. Screenshots of the three relevant UI states
(main menu, in-game KBM, in-game pad mode with hint bar) were captured from the
running game while researching this doc.

### 3.1 Entry & boot paths a tutorial can reuse

- Main menu scene: `res://scenes/MainMenu.tscn` → `scripts/MainMenu.gd`.
  Buttons live in `$ScrollContainer/MenuContainer/ButtonSection` — `StartButton`,
  `MultiplayerButton`, `LoadButton`, `ReplayButton`, `SettingsButton`,
  `QuitButton` (`scripts/MainMenu.gd:42-47`). The menu is already pad-navigable
  (`follow_focus`, `start_button.grab_focus()` — `scripts/MainMenu.gd:161-162`)
  and shows a controller status label (`_create_controller_status`, `:310`).
- Game boot: `MainMenu._initialize_game_with_config(config)`
  (`scripts/MainMenu.gd:1328`) clears state, applies deployment/terrain/mission,
  loads armies via `ArmyListManager`, stamps `GameState.state.meta.game_config`
  + `meta.from_menu`, then `change_scene_to_file("res://scenes/Main.tscn")`
  (`:1303`). Config keys include `player{1,2}_type` (`"HUMAN"`/`"AI"`), AI
  difficulty + speed, and **fixed secondary missions**
  (`player*_secondary_mode: "fixed"` + 2 mission ids), which a tutorial config
  uses to keep the secondary-missions modal out of early lessons.
- Boot-from-fixture: exactly what `ScenarioRunner` does
  (`autoloads/ScenarioRunner.gd:83-186`): stage `.w40ksave` into
  `user://saves/`, `SaveLoadManager.load_game(name)`, set
  `GameState.state.meta.from_save = true`, change scene, wait for readiness +
  settle frames, then `PhaseManager.transition_to_phase(N)`. Seed determinism
  via `RulesEngine.set_test_seed(n)` and `SecondaryMissionManager.set_test_seed(n)`.
  **Gotcha (proven in ScenarioRunner `:145-170`):** the scene change re-reads
  `game_config` and re-applies AI enablement — any player-type override must be
  applied both before *and* after the scene swap.

### 3.2 The action pipeline — where a tutorial observes and gates

```
Controller (mouse/key/pad) → <phase>_action_requested → Main.gd handler
  → NetworkIntegration.route_action(action)          (utils/NetworkIntegration.gd:53)
      └─ single-player → PhaseManager.current_phase_instance.execute_action(action)
            → BasePhase.execute_action()             (phases/BasePhase.gd:91)  ★ gate here
                 validate_action() → process_action() → apply_state_changes()
                 → signal action_taken → PhaseManager.phase_action_taken       ★ observe here
```

- **Gate:** `BasePhase.execute_action` (`phases/BasePhase.gd:91`) is the one
  funnel — `ShootingPhase:251` and `FightPhase:305` override it but call
  `super` first, and AI, scenario `dispatch_action`, and all UI paths converge
  there. A ~5-line insertion immediately before `validate_action` (`:95`)
  returning the existing `{"success": false, "error": ..., "errors": [...]}`
  shape gives the tutorial a complete allow-list gate with zero per-controller
  surgery.
- **Observe:** `PhaseManager.phase_action_taken(action)`
  (`autoloads/PhaseManager.gd:17`, emitted at `:444`) fires for every
  *successful* action after diffs apply — the step engine's primary "did the
  player do it" signal, complemented by `phase_changed`, `turn_started`, etc.
  (`PhaseManager.gd:15-26`).
- **Known trap (audit X1, `CONTROLLER_AUDIT_2026-07.md` §2):** the human UI is
  *not* generated from `get_available_actions()`; controllers hardcode their
  buttons. So an allow-list alone cannot grey buttons out — the player can
  press a live button and be rejected. Design response (§4.3): strict steps
  *also* block stray pointer input via the spotlight overlay, and every
  rejection is a friendly, throttled nudge toast. No per-controller button
  surgery in v1.
- **Off-pattern paths to special-case (audit X3):** DeploymentController talks
  to the phase directly (no request signal), and Disembark runs through its own
  `DisembarkController`. Both still terminate in `execute_action`, so the gate
  holds; only *observation* of fine-grained pre-actions (model placement before
  `DEPLOY_UNIT`) needs controller signals or state polling.

### 3.3 UI building blocks that already exist

| Surface | Where | Tutorial use |
|---|---|---|
| Toasts | `autoloads/ToastManager.gd` (`show_toast/show_warning/...`, CanvasLayer **100**) | rejection nudges, step-complete celebrations |
| Pad hint bar | `autoloads/PadHintBar.gd` (layer 90, `set_hints`, `label_for(glyph_id)`, `current_hints`) | the thing lesson T1 *teaches players to read*; prompt text can quote it live |
| Glyph chips | `scripts/input/GlyphDB.gd` (semantic ids `a/b/x/y/lb/rb/lt/rt/ls/rs/l3/dpad/menu/view`, programmatic chips that scale with UI scale) | inline button glyphs in prompts; PS/Deck art later is "a table swap, not a caller change" (GlyphDB header) |
| Rebind-aware key names | `KeybindingManager.get_key_display_name(action_id)` (used by the hotkey help overlay, `Main.gd:13169`) | keyboard prompt text — never hardcode a key (X5: `E/F/G/R/N/V/S/Tab` are double-bound) |
| Focus ring | `autoloads/PadFocusRing.gd` | already provides visible pad focus; tutorial doesn't duplicate it |
| Hotkey help overlay | `Main.gd:13140` (`Shift+/`) | T1 points at it as the permanent reference layer |
| Phase banner, event log, dice log tabs | `PhaseTransitionBanner`, `GameEventLog`, left-panel tabs | taught surfaces, not new work |
| Node lookup | `autoloads/SceneRefs.gd` | tutorial resolves nodes through this, not hardcoded paths |
| Settings persistence pattern | `SettingsService` ConfigFile → `user://settings.cfg` (`:557-668`) | template for `user://tutorial_progress.cfg` |
| **Missing** | — | **No dimmer/spotlight/coach-mark overlay exists anywhere; it must be built** (per the ToastManager/PadHintBar CanvasLayer pattern, colors from `UIConstants` per design guidelines §9 — no new hex literals) |

### 3.4 Controller layer: shipped and documented — the tutorial teaches it

`PRPs/steam_deck_controller_support.md` M0–M3 are ✅ shipped (v0.25–v0.33):
`InputDeviceManager` (KBM⇄pad detection + runtime-registered `pad_*` actions),
`VirtualCursor` (left stick, warps the real cursor), `PadRouter` (102 KB
contextual state machine: bumper-only unit cycling, A select, B back, D-pad
menus, carry mode, per-context `HINTS_*` tables), `PadHintBar`/`PadActionBar`/
`PadFocusRing`. ~58 `pad_*` windowed scenarios pass. The generated
`40k/docs/CONTROLLER_CONTROLS_MAP.html` is the button-map source of truth,
sync-guarded by `tests/test_controller_controls_doc_sync.gd`.

**Implications:** (a) the tutorial adds **no new bindings** and must not touch
`PadRouter.HINTS_*` (doc-sync test); (b) pad `_input` ordering is load-bearing
— scene → VirtualCursor → PadRouter → PadHintBar → InputDeviceManager
(`PadRouter.gd:76-80`); the tutorial overlay blocks *pointer* input via
`mouse_filter`, not by consuming `_input`, precisely to stay out of that chain;
(c) `InputDeviceManager.claim_pad()` / `device_changed` give the tutorial live
device switching (verified working in this container via the MCP bridge — the
hint bar and glyph-swapped End Phase button render under `claim_pad()`).

### 3.5 The scenario engine is 80% of a tutorial step engine

`autoloads/ScenarioRunner.gd` + `tests/scenarios/_schema.md` already implement,
proven across 362 scenarios:

- **Selectors** the tutorial needs verbatim for anchors: token by `unit_id`
  (`_find_unit_token`, `:1757`), NodePath, **`button_text`** (first visible
  enabled button — survives procedurally-built panels, `:981`), board-px with
  live canvas-transform projection (`_node2d_to_screen`, `:1843`).
- **Wait/assert vocabulary** that becomes the step *done-condition* vocabulary:
  `expect_state` (dot path into `GameState.state`), `expect_node_visible`
  (polling + timeout), `expect_phase`, `execute_script` multiline predicates,
  `wait_for_tweens`.
- **Pad input simulation** for the lesson QA scenarios: `simulate_joy_button`,
  `simulate_joy_axis`, `pad_cursor_glide` (steers the real virtual cursor,
  camera-edge-push aware).
- **Drift detection:** `SCENARIO_SELECTOR_DRY_RUN=1` resolves every selector
  without running — the model for the lesson lint tool (§5.5).

The design reuses this vocabulary (same field names where sensible) so lesson
authors and scenario authors learn one language, and each lesson's QA scenario
is nearly a mechanical translation of the lesson script itself.

### 3.6 Armies, transports, characters — content readiness

- Ork ingredients exist in `40k/armies/orks.json`: Warboss (×3 variants +
  Ghazghkull), Boyz (10- and 20-model units), Battlewagon (`TRANSPORT`,
  `VEHICLE`), plus Gretchin in `battlewagons.json`. Marines opponent material
  in `space_marines.json`: Intercessors (5), Tactical Squad (5), Infiltrators
  (5). Army JSON schema 2 / edition 11, loaded by `ArmyListManager`
  (`load_army_for_game` `:485`, `apply_army_to_game_state` `:312`).
- Transports work end-to-end today: `TransportManager` (embark `:100` /
  disembark `:126` / capacity `:205`), deployment embark dialog
  (`TransportEmbarkDialog`, wired at `DeploymentController.gd:933`), movement
  disembark (`DisembarkController` + `DisembarkDialog`,
  `MovementController.gd:2794`), actions `EMBARK_UNITS_DEPLOYMENT`,
  `DECLARE_TRANSPORT_EMBARKATION`, `EMBARK_UNIT`, `DISEMBARK_UNIT`,
  `CONFIRM_DISEMBARK`. Committed fixtures + passing scenarios cover loaded
  Battlewagons (`audit_374_kunnin.w40ksave`, `iss058_disembark_11e.json`,
  `disembark_then_advance_11e.json`, `transport_deploy_shows_embarked_units.json`).
  **Residual risk:** Boyz specifically (20-model mobs, attached leader) have
  never been the fixtured passenger — TM1 starts with a smoke scenario for
  10 Boyz + Warboss in a Battlewagon before lesson authoring.
- Characters/leaders: `CharacterAttachmentManager` (attach `:171`), legal
  pairings from `LeaderPairingsLoader` + `data/Datasheets_leader.csv`,
  `CharacterAttachDialog` at deployment, `DECLARE_LEADER_ATTACHMENT` at
  Formations. Warboss→Boyz is a legal 11e pairing.
- Opponent: `AIPlayer` is a full bot on the same action pipeline (difficulty
  profiles, speed presets incl. `Fast (0ms)`, `is_ai_player()`), so the
  tutorial's P2 needs zero new AI code.

### 3.7 Known control gaps that intersect lesson content

From `CONTROLLER_AUDIT_2026-07.md` (remediation in progress, one PR per item):

| Audit item | Lesson impact | Design response |
|---|---|---|
| ✅ P0 #1 battle-shock UI never rendered (fixed, PR #742) | T7 teaches the roll button | none — fixed |
| P2 Movement "Advance" silent trap (mode radio ≠ locked until "Confirm Movement Mode", `MovementController.gd:1243`) | T3 | teach the confirm gate *explicitly* — turn the trap into a taught behavior |
| P2 dead "Embark" button (`Main.gd:4382`) | T3 | teach the real path (phase auto-prompt after move near transport); optionally land the button removal first |
| P1 Charge 11e declare-then-roll path unreachable | T5 | teach the implemented pre-roll-target flow; revisit lesson text when the audit item lands |
| P1 Fight per-model weapon choice / split attacks missing | T6 | not taught (not reachable); lesson teaches what exists |
| X5 keybinding collisions (`E/F/G/R/N/V/S/Tab`) | all | prompts prefer on-screen buttons; key names always via `KeybindingManager.get_key_display_name` |

The tutorial deliberately **does not block on** audit remediation; lessons teach
today's working paths and get a text touch-up when items land.

---

## 4. Proposed player experience

### 4.1 Entry points

1. **Main menu button** — `Tutorial` in `ButtonSection`, directly under
   `Start Game`. Opens the **lesson picker**: a panel listing the Full Course
   and the 7 lessons with completion checkmarks, per-lesson time estimates, and
   a `Reset progress` affordance. Fully pad-navigable (same M0 pattern as the
   menu: `follow_focus`, initial `grab_focus`, explicit focus neighbors).
2. **One-time nudge, never forced** — on menu load, if no lesson was ever
   completed *and* no real game was ever started, a small dismissible panel
   above the buttons: *"First time in da app? Basic Trainin' teaches the
   controls — you already know da rules."* Dismissal persists
   (`nudge_dismissed`). Into-the-Breach model; zero modality.
3. **Pad-aware suggestion** — if `InputDeviceManager.is_pad_active()` at menu
   time and the controller lessons were never completed, the nudge mentions the
   pad specifically ("Learn the gamepad controls in 5 minutes").

### 4.2 The battle and the curriculum

One scripted skirmish on the standard board, objectives near the center,
armies placed so every lesson's action happens within one screen of travel:

- **Player (Orks, ~495 pts):** `tutorial_orks.json` — Warboss (leads da Boyz),
  Boyz ×10, Battlewagon (Boyz + Warboss start embarked from T3 onward),
  Gretchin ×10 (cheap second squad: deployment formations + objective sitting).
- **Opponent (AI Space Marines, ~300 pts):** `tutorial_marines.json` —
  Intercessors ×5 (the shoot-at/charge target), Tactical Squad ×5 (holds an
  objective). Optional third: Infiltrators ×5 if T4 wants a hidden-target LoS
  beat. Marines rather than mirror Orks so "click the **enemy**" is visually
  unambiguous.

Both files: schema 2, edition 11, copied unit blocks from existing armies, plus
`faction.tutorial: true` so the normal army dropdowns can filter them out
(TutorialManager loads them explicitly).

**Lessons** (Ork title — plain subtitle; each = one phase of the same battle):

| # | Lesson | Teaches (controls only) | Starts from | Phase |
|---|---|---|---|---|
| T1 | **Scoutin' da Field** — camera, selection & reading the table | pan/zoom (WASD/wheel · RS/LT/RT), select via list + board + RB-cycling, unit card & datasheet (`I` / `Y`), log + dice-log tabs, hint bar & hotkey help (`Shift+/`), pause menu, where End Phase lives | `tutorial_postdeploy` fixture | MOVEMENT (look-only; one taster move at the end) |
| T2 | **Musterin' da Boyz** — deployment, transports & leaders | Formations dialog (attach Warboss→Boyz, embark Boyz→Battlewagon, warlord), roll-off dialog, placing models (click, `Q`/`E` rotate, Single/Spread/Tight formations), undo/reset, confirm, watching AI alternate, End Deployment + summary | fresh boot (tutorial config) | FORMATIONS→DEPLOYMENT |
| T3 | **Get Movin'** — movement phase | unit list → move menu (Normal/Advance/Remain/Fall Back), **the Confirm-Movement-Mode gate**, drag models (KBM) / carry mode (pad: `A` grab, `LS` place, `L3` next model), staged-move hints, undo model / reset unit, **disembark da Boyz** (3″ placement dialog), embark auto-prompt, confirm unit vs End Phase | `tutorial_postdeploy` | MOVEMENT |
| T4 | **Dakka Time** — shooting phase | eligible-shooter list & cycling, weapon tree, assign target (click enemy), quick-assign, LoS/range feedback, Confirm Targets, resolution dock (Roll to Hit → wounds → saves; Fast Roll All), dice log, skip unit, End Shooting | `tutorial_t4_shoot` | SHOOTING |
| T5 | **'Ere We Go!** — charge phase | charge-eligible list, declare target(s), roll 2D6 (seeded success), what failure looks like (text), charge-move drag + base snap + Snap to Contact, per-model undo, confirm | `tutorial_t5_charge` | CHARGE |
| T6 | **Krumpin'** — fight phase | pile-in dialog, fighter alternation panel, attack assignment dialog → Fight!, resolution dock, **defender wound allocation overlay** (AI hits back once), consolidate | `tutorial_t6_fight` | FIGHT |
| T7 | **Runnin' da Show** — command, stratagems & a full turn | CP readout, battle-shock button, stratagem panel (`S`/button), secondary-mission review & discard, objective-control panel, then a semi-free capstone turn (all End-Phase actions allowed) ending in scoring + VP timeline (`V`), save/load pointer | `tutorial_t7_round2` | COMMAND→SCORING |

**Full Course** = T1 → T7 in order. T1→T2 involves the course's single scene
reload (T1 previews the deployed battlefield, T2 starts the real deployment —
framed as "seen enough — now muster for da real fight"). T2→T7 then run as
**one continuous battle with zero reloads**: each lesson ends exactly where the
next fixture begins, and continuing simply keeps playing instead of loading.
Individual lesson launches load the corresponding checkpoint fixture. (Scythe's
reload-per-mechanic is the documented anti-pattern; two loads across a
~30-minute course is the deliberate compromise.)

Lesson end: a compact summary card — bark line, 3-bullet "wot you learned",
`Next lesson` / `Back to menu`, checkmark persisted.

### 4.3 In-lesson anatomy

Every step renders through four cooperating pieces:

1. **Instructor card** (the only persistent chrome): compact panel, top-center
   under the top bar by default, auto-relocating to bottom-center (above the
   pad hint bar) whenever its rect would cover the current anchor. Contents:
   Ork instructor portrait chip + bark title (flavor, ≤ 5 words), instruction
   body (≤ 2 lines, device-adaptive, inline glyph chips on pad / rebind-aware
   key names on KBM), step progress ("3/11"), and two always-available
   buttons: `Skip step` and `Exit Tutorial`. Body text ≥ 13 px at 1280×800
   equivalent (Deck floor is 9 px, recommendation 12 px; the pad UI-scale boost
   ×1.2 already applies on top).
2. **Spotlight** (new overlay, §5.1): three intensities per step —
   `none` (free step), `soft` (pulsing ring/underline around the anchor, no
   input blocking — the default), `strict` (screen dimmed except a cutout;
   pointer input outside the cutout blocked). Strict is reserved for steps
   where mis-clicks are likely and costly (e.g. first End Phase). Anchors
   resolve via the four scenario-proven selector kinds (§3.5) and re-project
   every frame for board tokens (camera can move).
3. **Action gate**: the step's `allow` list (plus a standing implicit-safe set:
   `DECLINE_*`, reroll declines, dialog-dismiss actions, and *everything from
   the AI player*) filters `BasePhase.execute_action`. A blocked attempt
   triggers a throttled warning toast written as a nudge, with the Ork
   instructor's voice ("Oi! Dat's later — first: <step title>"), plus a brief
   instructor-card shake. Camera, selection, datasheet, log reading, measuring
   tape are **never** gated (they dispatch no actions).
4. **Done-condition**: outcome-based (§5.3) — state path reached, action
   observed, dialog appeared/closed, phase changed. On completion: small
   success toast (occasionally a bark), advance. Optional `hint_after_s`
   (default 25 s): appends one extra helper line ("Da button's bottom-right,
   boss") — adaptive messaging per Fan tip #7, never auto-completes.

Failure-tolerance rules (Scythe-proofing): any state the player can reach with
allowed actions must satisfy some step's done-condition or be recoverable by
the step's own instructions; `Skip step` force-satisfies the current condition
via a scripted fallback (`skip_fallback`: dispatch the taught action
programmatically or jump the lesson state) so a broken step can never trap a
player; `Exit Tutorial` (card button + pause-menu entry) tears the tutorial
down unconditionally and returns to the menu.

### 4.4 Device adaptivity

- Prompt bodies are authored twice where the verb differs (`kbm` / `pad`) and
  once where it doesn't; glyph tokens (`{a}`, `{rb}`, `{key:rotate_left}`,
  `{hint:x}` = live hint-bar label for a glyph) render as chips/names for the
  active device. Live re-render on `InputDeviceManager.device_changed`
  mid-step (Battlesector's device-blind prompts are the documented failure).
- **Done-conditions are outcomes, so they are device-blind by construction** —
  "the unit ended ≥ 6″ from where it started" is satisfied by mouse drag or
  pad carry alike. Steps that teach a pad-only navigation verb (D-pad panel
  focus, carry-mode hops) are tagged `device: "pad"` and are skipped silently
  on KBM (and vice-versa for the few mouse-only flourishes). T1/T3 carry the
  bulk of the per-device steps.
- The tutorial teaches **reading the hint bar** as the durable skill (T1 step:
  "Da bar at the bottom always shows wot buttons do *right now*"), so later
  lessons can say "check da hint bar" instead of re-listing bindings — this is
  also what keeps lesson text short on pad.

### 4.5 What we deliberately do NOT build

- No rules text, no "what is a Waaagh" — flavor may wink, instructions never
  explain game rules (review checklist per lesson).
- No forced tutorial, no tutorial-on-first-boot modal, no gating of the real
  game behind completion.
- No autoplay demonstrations ("ghost hands") in v1 — do > watch; the spotlight
  + short text carries it. (Revisit only if playtests show a step failing.)
- No per-controller button disabling/hiding (X1 surgery) in v1 — gate + toast
  + strict spotlight cover it additively.
- No new input bindings, no `PadRouter.HINTS_*` changes (doc-sync test).
- No localization scaffolding (app is English-only throughout).
- No changes to `get_available_actions()` semantics (that's the audit's X1
  structural recommendation — a separate effort; the tutorial must not couple
  to it).

---

## 5. Technical architecture

### 5.1 New components (all additive)

| Component | Kind | Responsibility |
|---|---|---|
| `autoloads/TutorialManager.gd` | autoload (registered after `ScenarioRunner`) | lesson lifecycle (load script → boot fixture/config → run steps → persist), the `is_action_allowed(action)` allow-list, `notify_*` observers, progress store (`user://tutorial_progress.cfg`), Full-Course sequencing |
| `scripts/tutorial/TutorialOverlay.gd` (+ scene) | CanvasLayer **93** (above PadActionBar 92, below VirtualCursor 95 so the cursor stays visible, below ToastManager 100) | instructor card, spotlight (soft ring / strict dimmer-with-cutout as 4 blocking ColorRect strips + drawn ring), arrow/pulse, anchor re-projection each frame, device-adaptive prompt rendering |
| `scripts/tutorial/TutorialScript.gd` | RefCounted parser | loads/validates lesson JSON, resolves glyph/key tokens, exposes typed steps |
| `scripts/tutorial/AnchorResolver.gd` | static util | the four selector kinds (unit token / NodePath via SceneRefs / button-text / board-px), extracted to mirror `ScenarioRunner`'s proven resolvers |
| `data/tutorials/lessons/T1_basics.json` … `T7_command.json` | data | lesson scripts (schema §5.3) |
| `armies/tutorial_orks.json`, `armies/tutorial_marines.json` | data | tutorial armies (`faction.tutorial: true`; menu dropdowns filter them) |
| `data/tutorials/fixtures/*.w40ksave` (+ `.meta`) | data (shipped in export) | lesson checkpoints: `tutorial_postdeploy`, `tutorial_t4_shoot`, `tutorial_t5_charge`, `tutorial_t6_fight`, `tutorial_t7_round2` |
| `tools/gen_tutorial_fixtures.sh` + `tests/helpers/TutorialFixtureGenerator.gd` | tooling | regenerates all checkpoints by booting the tutorial config and replaying a committed, seeded action script through the real pipeline — fixtures stay reproducible across save-schema migrations |
| `tools/lint_tutorials.sh` | tooling / CI | boots each lesson's fixture headless-windowed, resolves every anchor + done-condition path (dry-run, no input), fails on drift — the lesson equivalent of `SCENARIO_SELECTOR_DRY_RUN` |
| `tests/scenarios/sp/tut_*.json` | QA | per-lesson windowed scenarios, mouse + pad variants (§5.5) |

### 5.2 Hooks into existing systems (the entire invasive surface)

1. `phases/BasePhase.gd:91 execute_action` — the gate, ~5 lines before
   `validate_action` (`:95`), returning the standard failure dict with a
   `tutorial_blocked: true` marker (controllers already surface failure
   errors; the overlay converts this marker into the nudge toast).
2. `scripts/MainMenu.gd` — `Tutorial` button + lesson picker + nudge panel
   (~150 lines, its own `scripts/tutorial/TutorialPickerPanel.gd`), army
   dropdown filter for `faction.tutorial`, and a `games_started` counter bump
   in `_initialize_game_with_config` for the nudge heuristic.
3. `autoloads/SaveLoadManager.gd` — one guard: skip autosaves while
   `GameState.state.meta.tutorial == true` (keeps slots clean).
4. `autoloads/ReplayManager.gd` — same one-line guard for recording.
5. Pause menu — add `Exit Tutorial` entry when active.
6. Optional (only if T2 needs finer observation than state polling):
   connect to existing controller signals (`DeploymentController` model-placed
   etc.) — read-only.

Everything else is observation via existing signals
(`PhaseManager.phase_action_taken`, `phase_changed`, `TransportManager.embark_completed`,
`CharacterAttachmentManager.attach_completed`, dialog `visibility_changed`) or
polling `GameState.state` paths at 10 Hz — both already proven by ScenarioRunner.

**Tutorial mode flags** stamped at launch: `meta.tutorial = true`,
`meta.tutorial_lesson = "t3"`, plus the standard `from_save`/`from_menu`
booting flags. AI config: P2 = AI Easy, speed Fast; applied before and after
the scene swap (§3.1 gotcha).

### 5.3 Lesson file format (v1)

```jsonc
{
  "id": "t3_get_movin",
  "title": "Get Movin'",
  "subtitle": "Movement phase controls",
  "est_minutes": 5,
  "boot": { "fixture": "tutorial_postdeploy", "phase": 7, "rng_seed": 4242 },
  // T2 instead uses: "boot": { "config": { ...tutorial game config... } }
  "steps": [
    {
      "id": "open_move_menu",
      "prompt": {
        "bark": "Time ta stomp!",
        "kbm": "Click [b]Boyz[/b] in the unit list, then pick [b]Normal[/b].",
        "pad": "Press {rb} until da [b]Boyz[/b] are picked, then {dpad} opens da move menu — choose [b]Normal[/b] with {a}."
      },
      "anchor": { "unit": "U_BOYZ_T" },              // or {"node": ...} | {"button_text": ...} | {"board": [x,y]}
      "spotlight": "soft",                            // none | soft | strict
      "allow": ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"],
      "done": { "any": [
        { "action": { "type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_BOYZ_T" } },
        { "state": "units.U_BOYZ_T.flags.move_mode", "exists": true }
      ]},
      "hint_after_s": 25,
      "hint": { "kbm": "Da list is on the right side.", "pad": "Hold {ls} to glide da cursor onto 'em." },
      "skip_fallback": { "dispatch": { "type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_BOYZ_T" } },
      "on_done": { "toast": "Sorted!" }
    },
    {
      "id": "read_hint_bar", "device": "pad",
      "prompt": { "bark": "Look 'ere!", "pad": "Da bar at the bottom always shows wot each button does [i]right now[/i]." },
      "anchor": { "node": "/root/PadHintBar" },
      "spotlight": "soft",
      "done": { "ack": true }                          // rare Continue-style step
    }
  ]
}
```

Done-condition vocabulary (deliberately mirrors `_schema.md` asserts):
`state` (+ `equals/not_equals/exists/expect_min/expect_max`), `action`
(matched against `phase_action_taken` payloads, subset-match on listed keys),
`node_visible` / `node_hidden`, `phase`, `signal` (autoload + signal name),
`script` (multiline GDScript predicate — escape hatch, used sparingly),
`ack`; combinators `any` / `all`. Glyph tokens: `{a}…{view}` (GlyphDB ids),
`{key:<keybinding_id>}` (KeybindingManager display name), `{hint:<glyph>}`
(live PadHintBar label).

### 5.4 Determinism & the opponent

- Every lesson sets `rng_seed` (RulesEngine + SecondaryMissionManager test
  seeds), so taught rolls behave: T3's Advance roll is respectable, T5's charge
  succeeds, T4's shooting kills at least one Intercessor. Seeds are chosen once
  while authoring the fixture and pinned in both the lesson file and its QA
  scenario. The player still presses every roll button themselves
  (anti-pattern #3: never roll for the player).
- AI turns inside lessons are minimized: fixtures bake completed enemy turns in
  wherever possible. Where an AI reaction is the lesson content (T6 defender
  allocation), the fixture + seed constrain it. Where an AI turn must actually
  run (T2 deployment alternation, T7 capstone), the director shows a passive
  "da enemy takes der turn" state (AI speed Fast) and re-arms on
  `turn_started` for the player. AI actions always bypass the allow-list.

### 5.5 Testing architecture (project gate compliance)

- **Windowed scenarios per lesson** — `tut_t<N>[_pad].json`: drive the lesson's
  real player path (clicks/drags on KBM variant; `simulate_joy_button` /
  `pad_cursor_glide` on pad variant), asserting after each beat: instructor
  card text advanced (node property), spotlight anchored (overlay state),
  gate blocks a disallowed action (`dispatch_action` → `success:false` +
  `tutorial_blocked`), lesson completes, progress file records it. Pad
  variants mandatory for T1 and T3 (the most pad-specific lessons), recommended
  for all.
- **Fixture regression** — one tiny scenario per checkpoint fixture that loads
  it and asserts phase/army integrity (catches save-schema migrations);
  regenerate via `tools/gen_tutorial_fixtures.sh` when they break, in the same
  PR as the migration.
- **Lesson lint in CI** — `tools/lint_tutorials.sh` (anchor + state-path
  dry-run per lesson): a UI refactor that renames a taught button fails the
  lint, not the player.
- **Unit tests** — lesson JSON schema validation, glyph/key token rendering
  (both devices), allow-list matcher (incl. implicit-safe set + AI bypass),
  progress store round-trip.
- **Chain-verify before each milestone close** — run the game, play the lesson
  by hand via the MCP bridge (pad-mode forced via `InputDeviceManager.claim_pad()`),
  screenshot the instructor card + spotlight over the real HUD, `verify_delivery`
  PASS. Per the project's validation rule, headless evidence alone never closes
  a tutorial task.

---

## 6. Phased roadmap

Sizes: S ≈ a session, M ≈ 2–4 sessions, L ≈ a week of sessions. Every
milestone that ships player-facing behavior bumps `40k/data/version_history.json`
and lands only with its scenarios green (`bash 40k/tests/run_scenarios.sh`).

### TM0 — Engine vertical slice + T1 (M)
`TutorialManager` (lifecycle, progress store, gate hook, fixture boot),
`TutorialScript` parser + schema doc, instructor card (device-adaptive text,
Skip/Exit, hint-after-timeout), **soft** spotlight only (pulsing ring via the
4 anchor kinds), menu button + minimal lesson picker, `tutorial_postdeploy`
fixture (hand-generated this once), **lesson T1 complete**, scenarios
`tut_t1` + `tut_t1_pad`, unit tests. *Gate:* finish T1 on mouse and on pad
(bridge-driven) with zero errors in the debug log; a disallowed action is
blocked with the nudge toast; completion checkmark survives restart.

### TM1 — Strict spotlight, armies, deployment lesson (L)
Strict dimmer-with-cutout + pointer blocking, board-anchor re-projection,
tutorial armies + menu filtering, **Boyz-in-Battlewagon smoke scenario**
(§3.6 residual risk) *before* lesson authoring, **lesson T2**
(Formations attach/embark → roll-off → deployment → summary), fixture
generator tool (regenerates `tutorial_postdeploy` from T2's script — replacing
the hand-made TM0 fixture — plus the T4–T7 checkpoints), lesson lint tool,
scenarios `tut_t2` (+pad). *Gate:* full T2 run on both devices; fixtures
regenerate byte-stable from the tool; lint green in CI.

### TM2 — Battle-round lessons I (M)
**T3 Movement** (incl. disembark, carry-mode pad steps, Confirm-Mode gate
teaching) and **T4 Shooting** (seeded resolution-dock walk), their fixtures +
scenarios. *Gate:* T3 pad variant proves carry mode teachable end-to-end.

### TM3 — Battle-round lessons II (M)
**T5 Charge**, **T6 Fight** (incl. one defender-allocation beat), **T7
Command/Stratagems/capstone turn**, Full-Course sequencing (lesson-to-lesson
continuation without reloads), completion celebration. *Gate:* Full Course
playable start-to-finish on pad via the bridge; all `tut_*` scenarios green.

### TM4 — Polish & Deck pass (S–M)
First-launch nudge (+ pad-aware copy), picker art/checkmarks polish, prompt
legibility audit at 1280×800 (≥ 12 px effective), bark-line pass, hint-timeout
tuning from self-playtests, itch/release notes. *Gate:* Deck-resolution
screenshot audit of every instructor card; nudge shows exactly once for a
fresh profile.

### TM5 (stretch, separate decision) — Contextual coach marks in real games
First-time-in-phase one-liners ("First shooting phase? `Tab` cycles eligible
shooters") with "don't show again" + a global hints toggle, reusing the same
overlay + token rendering. NN/g-style just-in-time help for tutorial skippers.
Explicitly out of v1 scope; listed so the overlay is built reusable.

Dependencies: none on the open pad milestones (M4–M6) — the tutorial teaches
shipped behavior; TM4 pairs naturally with the Steam-Deck M5/M6 fit-and-finish
work if both are in flight.

---

## 7. Risks & mitigations

| Risk | Mitigation |
|---|---|
| **Lesson rot** — UI refactors rename/move taught controls | lesson lint in CI (anchor dry-run) + per-lesson scenarios; anchors prefer `button_text`/SceneRefs over deep NodePaths |
| **Fixture drift** — save-schema migrations break checkpoints | fixtures regenerated by a committed generator script through the real pipeline; per-fixture load-regression scenarios catch breaks in the migrating PR |
| **Soft-locks** (Scythe failure) | allow-list always includes the implicit-safe set; `Skip step` has a scripted fallback; `Exit Tutorial` bypasses everything; QA scenarios include a "mash disallowed inputs" beat |
| **X1 mismatch** — live buttons the gate rejects confuse players | rejection is a designed nudge (toast + card shake, instructor voice), strict spotlight on the risky steps; if playtests still show confusion, escalate to per-step button disabling *then* |
| **AI nondeterminism** inside lessons | seeds pinned; AI turns baked into fixtures where possible; lessons never assert on AI choices, only on player-side outcomes |
| **Main.gd fragility** (14.4k lines) | invasive surface is §5.2's short list; everything else is signals + polling; no controller rewrites |
| **Pad input-chain interference** | overlay blocks via `mouse_filter` only; no `_input` consumption; layer 93 keeps VirtualCursor visible; verified against the `pad_native_nav_modal` conventions before TM0 closes |
| **Scope creep into rules-teaching** | per-lesson review checklist: every step names a control; bark lines carry the flavor budget |
| **Text length creep** | schema lints body length (warn > 160 chars); Fan's 8-words ideal cited in the authoring guide header of each lesson file |

---

## 8. Scoping decisions (proposed) & open questions

Decisions taken by this design (flag disagreement before TM0):

1. **Seven lessons, one shared battle**, Full Course = same lessons chained;
   two scene loads total in the course (menu→T1, T1→T2), zero from T2 on.
2. **Player side is fixed (Orks)** and the opponent is **AI Space Marines** —
   visual enemy contrast beats the mirror-match reading of "two small Ork
   forces"; the Ork force matches the requested Battlewagon + Boyz + Warboss
   exactly. (Mirror-Orks is a data-only change if preferred.)
3. **Tutorial armies ship as filtered army files**, checkpoints as shipped
   fixtures + regeneration tool.
4. **Gate at `BasePhase.execute_action`; no per-controller button surgery in v1.**
5. **Own progress file** (`user://tutorial_progress.cfg`), not `settings.cfg`.
6. **GlyphDB chips, not the Controller Icons addon** — the project already owns
   a semantic-id glyph system wired into the hint bar and its doc-sync test;
   device-specific glyph *art* remains a later table-swap exactly as GlyphDB's
   header planned. (Controller Icons stays noted as the off-the-shelf option
   if art-based glyphs are ever wanted: MIT code / CC0 art, auto device
   detection.)
7. **Restart-lesson granularity** — exiting mid-lesson records the lesson as
   started-not-completed; re-entry restarts the lesson from its checkpoint
   (steps are ≤ 6 min; mid-lesson resume isn't worth the save complexity).
8. **English only**, matching the rest of the app.

Open questions for the owner (none block TM0):

- **Tone check:** Ork instructor barks ("Oi! Wrong button, ya git!") — the
  research supports personality (BB2), but confirm the register is wanted in
  nudge/error copy, not just titles.
- **Menu label:** `Tutorial` (discoverable) with flavored lesson titles inside
  — or fully flavored (`Basic Trainin'`) on the menu button too?
- **Nudge default:** proposed = show once for fresh profiles until dismissed
  or any lesson/game is played. OK?
- **TM5 coach marks:** want it scheduled after TM4, or parked?

---

## 9. Appendix — full research notes (sourced)

<details>
<summary>Case studies, patterns, and Deck criteria with citations (research pass 2026-07-24)</summary>

### Digital board-game adaptations

- **Root Digital** — tutorials menu; base tutorial + per-faction missions; praised for serving players "familiar with the original game" (Big Boss Battle; Sprites and Dice; WayTooManyGames). Deck Verified per trackers (Steambase/ProtonDB). Exact guidance mechanics unverified.
- **Scythe Digital** — per-mechanic lessons with board reloads called "jarring"; "fails new players from the get-go" (Destructoid); Steam-forum-documented wrong-click progression block, unexplained mechanics, typos, forced bad moves.
- **Gloomhaven digital** — PC tutorial "brief and excellent," recommended even for tabletop veterans (EIP Gaming; Gamecritics); console port panned for inconsistent controller navigation (RPG Site; WayTooManyGames).
- **Wingspan** — short sectioned tutorial, sections revisitable after completion (Board Game Quest; Higher Plain Games); "you will know exactly where to look and where to click" (The Friendly Boardgamer). Switch port controls panned for device-widget inconsistency (Nintendo Life; TheGamer).
- **Terraforming Mars** — Steam-forum-documented: too long, makes choices for the player, teaches bad habits, tutorial font legibility complaints.
- **Blood Bowl 3** — OpenCritic 60; "big text boxes line the screen… tiny, tiny text" away from where the player looks (XboxEra); a tutorial step whose required action didn't work; "10 short tutorials that glance over the most basic actions" (Gamecritics). **BB2** — campaign-integrated teaching with Jim & Bob commentators, well liked (PC Gamer).
- **W40k Battlesector** — "series of short missions" tutorial praised (Explorminate); pad retrofit criticized: "fails to let you know what is currently selected" (Nerdburglars); Steam-forum report of pad tutorial instructions dead-ending; Deck patch 1.2.44 defaulted to gamepad controls + bigger fonts (GamingOnLinux; Slitherine).
- **BattleTech** — "Once past the lengthy tutorial missions, the universe opens up" (GameSpot) — mandatory length reads as friction.
- **Into the Breach** — tutorial offered on first play, checkbox + skip mid-stream + re-enable later (Steam discussions; Android Police); systemic UI (attack telegraphs, hover tooltips, Test Mech sandbox) minimizes tutorial need.
- **Baldur's Gate 3** — native controller presentation (radials, focus nav) called better than the mouse UI for complexity ("seems like the game was designed for it from the get-go" — SteamDeckHQ; GamesRadar).
- Thin/omitted: Mechanicus II ("short, yet incredibly helpful tutorial" — DualShockers), Gladius (skimpy tutorial + compendium as reference layer), XCOM 2 (text-heavy UI delayed pad support), Chaos Gate / Moonbreaker / TTS (not researched to citation standard).

### Pattern sources

- George Fan, GDC 2012 (PvZ): 10 tips incl. do > read, do-it-once, ≤ 8 words on screen, adaptive messaging, don't pause to talk, use visuals.
- Josh Bycer (Game Developer): every step answers what/how/why/when; strategy games need overt guidance; build the tutorial early.
- Celia Hodent, GDC 2016: cognitive-load distribution; teach only what isn't afforded.
- Extra Credits "Tutorials 101": don't front-load.
- NN/g: contextual just-in-time help beats up-front tutorials for retention; keep a reference layer.
- GDQuest Godot Tours: step queue + highlight + validate-real-action architecture (editor-targeted; reference, not dependency).

### Steam Deck Verified criteria touching tutorials (Steamworks docs)

- Default controller config must reach **all content**; on-screen glyphs must match the active device; K+M glyphs must not show on pad; smallest font ≥ **9 px** at 1280×800 (**12 px recommended**); text entry must summon the OSK. No tutorial-specific criteria exist.

### Godot techniques

- Spotlight cutout: fullscreen ColorRect + shader with rect uniforms, or four-rect dimmer (zero-shader), `mouse_filter` blocking outside the hole (Godot Forum; godotshaders "Blot cut mask").
- Focus navigation: per-Control focus neighbors + `ui_*` actions + `grab_focus()` on every panel open (Godot 4.4 GUI navigation docs); neighbors should be explicit (godot#77729).
- Device-glyph switching: last-input-wins device field + change signal (community pattern); rsubtil **Controller Icons** addon (MIT/CC0) auto-remaps icons per device incl. Steam Deck, if art-based glyphs are ever wanted.

</details>
