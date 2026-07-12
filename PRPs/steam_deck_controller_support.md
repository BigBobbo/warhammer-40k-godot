# Steam Deck / Controller Support — Research & Phased Implementation Plan

**Status:** IN PROGRESS — M0 shipped 2026-07-12 (v0.25.0, PR #571 merged); M1 shipped 2026-07-12 (v0.26.0 — a complete solo turn played pad-only); M2 shipped 2026-07-12 (v0.27.0; gates `pad_m2_unit_cycle` + `pad_m2_shooting_native` PASS — shooting phase completed with zero virtual-cursor use). Next: M3 (model carry — native stick movement).
**Branch:** `claude/steam-deck-controller-support-1tzorb`
**Date:** 2026-07-12 (game version at time of writing: 0.21.0)
**Goal:** Make the full game playable — and eventually *pleasant* — on a Steam Deck with no mouse or keyboard, without regressing the existing mouse/keyboard experience.

---

## 1. Goal and guiding principles

The game today is a mouse-first digital tabletop: free-form (not grid-based) model
positions, drag-to-move, click-to-select, hover previews, and dense side panels.
That is the hardest genre shape to bring to a controller — but also a solved one:
turn-based tactics games have converged on a small set of patterns that work.

Principles this plan follows:

1. **Two layers: a universal fallback, then native affordances.**
   A stick-driven *virtual cursor* that synthesizes real mouse events makes 100%
   of the game reachable on day one (nothing in the codebase needs to know a
   controller exists). Native affordances — unit cycling, target cycling,
   stick-driven model movement, focus-navigable panels — are then layered on
   phase by phase to make it *fast*. Games that shipped only the fallback layer
   (Tabletop Simulator) are rated at best "Playable" on Deck and widely
   considered miserable to play there; games that shipped native affordances
   (XCOM 2, Into the Breach) are the genre gold standard.
2. **The controller drives the same action pipeline as the mouse.** Every
   board mutation already flows through a phase-controller → action-dispatch
   path (the same one the MCP bridge drives programmatically via
   `dispatch_action` / `select_unit` / `get_legal_actions`). Pad input must
   call into that same pipeline — never a parallel one — so rules legality,
   multiplayer sync, replays, and the AI turn flow are automatically identical.
3. **Input-device agnosticism, not a "controller mode".** Mouse, keyboard and
   pad all stay live simultaneously; the UI adapts (glyphs, hint bar, focus
   ring, cursor visibility) based on which device was used last. This matches
   how the Deck itself behaves (trackpad = real mouse) and is what Deck
   Verified requires (glyphs must match the active input).
4. **Every milestone ends in a windowed scenario gate** (per
   `40k/tests/TESTING_METHODOLOGY.md`): a controller-only script drives the
   feature end-to-end via the MCP bridge with *injected joypad events*, and
   `verify_delivery` must PASS. Controller support is exactly the kind of
   feature where "the engine accepted the action" ≠ "a player holding a Deck
   can do it".

---

## 2. Research: how comparable games did it

### 2.1 The archetype — XCOM 2 (and its 40k descendants)

XCOM 2's console scheme is the template nearly every turn-based tactics game
now copies, and it matches the scheme you sketched (shoulder-cycle → select →
act):

- **LB/RB cycle through your squad** (and through valid targets once an
  ability is armed). No pixel-hunting for units, ever.
- **A confirms, B cancels** — universally, in every context.
- **Left stick moves a snapping cursor** on the battlefield; the camera
  follows. **Triggers zoom**, d-pad handles camera floors/rotation.
- **X/Y are context shortcuts** (reload / overwatch — i.e. the two most
  common actions get dedicated buttons).
- A persistent **ability hotbar along the bottom** is navigated left/right;
  every screen shows contextual **button-glyph hints**.

Warhammer 40,000: Battlesector, Mechanicus, and Chaos Gate — the three closest
official 40k analogues — all shipped console versions on this same skeleton
(cycle units, cycle targets, confirm/cancel, hotbar). Notably, Battlesector's
PC gamepad support is community-rated as *clunky* (a thin cursor-emulation
layer over the mouse UI, awkward HQ-ability selection) — a useful cautionary
tale that the fallback layer alone is not the destination.

### 2.2 The grid-tactics refinement — Into the Breach (Switch)

Into the Breach demonstrates the highest-polish version of "cursor on a
board": the **left stick moves a cursor that snaps to tiles**, with adjustable
snap strength, and **face/shoulder buttons issue discrete commands** (cycle
mechs, undo, end turn). Reviewers consistently note commands are issuable at
"near keyboard-and-mouse speed" — proof that cursor + snapping + cycling can
fully replace a mouse when the interactable set is discrete. Our board is
continuous, not tiled, but the *interactables* (units, models, objectives,
panel buttons) are discrete — so snap/cycle logic transfers.

### 2.3 The complex-PC-game lesson — Baldur's Gate 3 vs Divinity: Original Sin 2

Larian's two attempts are the best documented before/after in the genre:

- DOS2 kept the PC hotbar UI on controller and required players to manage it
  with a cursor — widely considered the weak point of an otherwise great port.
- BG3 rebuilt the controller UX around **radial menus** (weapons/spells/items
  on customizable wheels, triggers to page between wheels) and **direct
  character control**, with a fully separate controller UI layout. It is now
  frequently cited as *better* on controller than KB+M — and it's Deck
  Verified.

Lesson for us: we do **not** need BG3's budget-heavy "second UI", because a
Warhammer turn has a much narrower verb set per phase (move / shoot / charge /
fight / use stratagem), and our right-panel-per-phase design already enumerates
those verbs as buttons. Focus-navigable panels + a contextual hint bar gets us
the BG3 outcome (no cursor for verbs) without building radials. Radial menus
remain a *possible* later enhancement for stratagems/abilities if the panel
navigation feels slow in practice.

### 2.4 The cautionary tale — Tabletop Simulator on Steam Deck

TTS is the closest *shape* match to this project (free-form digital tabletop)
and it is the negative example: pure mouse emulation via trackpad, scripted UI
buttons that only respond to real mouse clicks, tiny-trackpad misclicks —
community consensus is "at best Playable, only with a heavily customized Steam
Input config". Every design choice below exists to avoid that outcome.

### 2.5 Steam Deck Verified — the actual requirements

From Valve's Steamworks guidance ("Getting your game ready for Steam Deck"):

- **Full controller support**: every in-game function reachable with the
  default controller config — including launchers/menus.
- **Correct on-screen glyphs** for the active device (Deck/Xbox-style).
- **Legible text at 1280×800**: rule of thumb — **no rendered text below
  ~9 px at 800p**.
- **On-screen keyboard**: any text field must either invoke the Steam OSK
  (Steamworks `ShowFloatingGamepadTextInput`, available in GodotSteam) or
  provide a built-in controller-navigable text entry.
- Default graphics settings that perform acceptably on Deck hardware.

Two practical notes for this project:

- **Godot + Deck**: a Godot Linux export that supports a standard Xbox-style
  controller works on Deck with no extra work — Steam Input presents the Deck
  controls as an Xbox controller by default. The Deck's extra inputs (back
  grips L4/L5/R4/R5, trackpads, gyro) are *not* visible as native joypad
  input; they arrive only via a Steam Input configuration, so they must be
  treated as optional extras, never required controls.
- **Distribution path matters for the OSK**: the Steamworks floating keyboard
  only exists when running under Steam. An itch.io build sideloaded as a
  non-Steam game still gets Steam Input and the overlay, but the safest
  baseline is a small **in-game pad-navigable keyboard** for the few text
  fields we have, with the GodotSteam call used when available.

### 2.6 Scheme synthesis

| Pattern | Source | Adopted? |
|---|---|---|
| LB/RB cycles eligible units; cycling follows activation eligibility, not raw list order | XCOM 2, Battlesector, ITB | ✅ core of the scheme |
| A = confirm/select, B = cancel/back, everywhere, no exceptions | all of them | ✅ |
| Stick-driven cursor with snap/magnetism to interactables | ITB (tiles), XCOM (grid) | ✅ as the fallback layer (continuous board → magnetism to tokens/buttons instead of tiles) |
| Cycle *targets* with the same buttons once an attack is armed | XCOM 2 | ✅ (shooting / charge declarations / fight) |
| Contextual button-hint bar always on screen | XCOM, BG3, every console port | ✅ |
| Dedicated context-shortcut buttons (X/Y) | XCOM (reload/overwatch) | ✅ X = phase-contextual action, Y = inspect/datasheet |
| Radial menus for large verb sets | BG3 | ⏸ deferred — phase panels are small enough for focus nav; revisit for stratagems |
| Separate controller-only UI layout | BG3, DOS2 | ❌ rejected — cost/benefit wrong for a solo-dev project; adapt the one UI |
| Direct character control on stick | BG3, DOS2 | ✅ *adapted*: stick directly drives the **model being moved** (the "carry" mode) — the tabletop equivalent |
| Pure mouse-emulation as the whole answer | TTS | ❌ rejected as end state; used only as the M1 fallback layer |

Sources:
- XCOM 2 controls: https://strategywiki.org/wiki/XCOM_2/Controls, https://xcom.com/news/controller-support-deployed-for-xcom-2-on-pc/
- Battlesector gamepad discussions: https://steamcommunity.com/app/1295500/discussions/0/3037102935218561481/ (and manual: https://ftp.matrixgames.com/pub/Warhammer40000Battlesector/Battlesector%20manual%20EBOOK.pdf)
- Into the Breach controller support: https://store.steampowered.com/news/app/590380/view/4039122238476235562, https://www.nintendolife.com/reviews/switch-eshop/into_the_breach
- BG3 controller design: https://blog.playstation.com/2023/09/05/how-baldurs-gate-3-adapts-its-expansive-rpg-gameplay-for-your-dualsense-controller/, https://medium.com/design-bootcamp/bridging-the-gap-overhauling-console-experience-in-baldurs-gate-3-43ef3578791b
- TTS on Deck: https://steamcommunity.com/app/286160/discussions/0/3185738755280108196/, https://www.protondb.com/app/286160?device=steamDeck
- Steam Deck requirements: https://partner.steamgames.com/doc/steamdeck/recommendations, https://www.steamdeck.com/en/verified
- GodotSteam OSK API: https://godotsteam.com/classes/utils/ (`showFloatingGamepadTextInput` + `GamepadTextInputDismissed` callback)
- Godot UI focus navigation: https://docs.godotengine.org/en/4.4/tutorials/ui/gui_navigation.html

---

## 3. Where the codebase stands today (audit)

*(Filled in from the 2026-07-12 architecture audit of this branch.)*

### 3.1 Verified engine/input facts

Checked against the live engine (`godot --headless -s` InputMap dump on this
project, 82 actions total):

- The project defines only **four custom InputMap actions** — `zoom_in` (=),
  `zoom_out` (-), `quick_save` ([), `quick_load` — plus an override of
  `ui_cancel` (Escape). **Everything else is hardcoded event checks in
  scripts.**
- Godot's built-in focus-navigation actions `ui_up/down/left/right` **already
  carry D-pad and left-stick bindings by default** — directional focus
  movement with a pad works "for free" once a Control has focus.
- **`ui_accept` has NO joypad binding by default** (Enter/Kp Enter/Space
  only), and `ui_cancel` is Escape-only. This is the single cheapest,
  highest-leverage gap: until Joypad A/B are added to these two actions, a pad
  can move focus but can never press a button. (Verified live — not assumed;
  stock Godot 4.4 genuinely ships `ui_accept` without a joypad event.)
- `ui_select` defaults include Joypad Y (button 3) — mostly irrelevant, but it
  means stray pad presses already reach the UI today.

### 3.2 Existing assets that make this easier than it looks

- **`KeybindingManager` autoload** (`40k/autoloads/KeybindingManager.gd`):
  a central registry of ~35 rebindable, categorized keyboard actions with
  ConfigFile persistence and a `binding_changed` signal — camera pan/zoom,
  rotate model (Q/E), measuring tape, save slots, panel toggles, and —
  crucially — an already-shipped **Shooting-phase cycling vocabulary**
  (`shoot_cycle_eligible_unit` = Tab, `shoot_confirm_targets`,
  `shoot_skip_unit`, `shoot_end_phase`). The pad scheme below is largely
  "bind joypad inputs to semantics this registry already names".
  Limitation: its matcher is typed to `InputEventKey`, so it cannot express
  joypad bindings today — see §5.2 for the migration.
- **A programmatic action API already exists and is battle-tested**: the MCP
  bridge drives the entire game headlessly via `select_unit`,
  `dispatch_action`, `get_legal_actions`, `move_unit_to`, `simulate_click`,
  and `simulate_action`. Controller code will be "just another caller" of the
  same seams, and the same bridge gives us automated controller tests
  (§6, M6).
- **`UIConstants` slot table + design guidelines** (`40k/docs/design_guidelines_2d_topdown.md`
  §9): the focus ring, cycle highlight, and hint bar must take colors from the
  slot table (no new hex literals) — the design system already anticipates
  overlay/indicator work.
- **Settings + overlay surfaces exist**: `SettingsService`, a rebinding UI
  fed by KeybindingManager, and a shortcut overlay (`shortcut_overlay`,
  Shift+/) that can grow glyph columns for pad bindings.

### 3.3 Input handling map (mouse/keyboard today)

- **Hub-and-spoke across ~11 production handlers.** `Main.gd:5067 _input` is
  the global hub (ESC/overlay stack, all global hotkeys, right-click unit
  menus, measuring-tape input); `Main.gd:5530 _process` polls held camera
  keys (WASD/arrows pan, `=`/`-` zoom). Each phase controller then owns its
  board interaction: `MovementController._unhandled_input` (:1878 — click
  select, single/group model drag, Q/E rotate, Ctrl+A, drag-box),
  `DeploymentController` (:88 — ghost placement, wheel/Q/E rotate,
  formations, Ctrl+Z), `ChargeController._input` (:143), `FightController`
  (:1348 — pile-in/consolidate moves + melee target clicks),
  `ShootingController` (:4168 — shooter/target clicks, LoS hover, the
  Tab/Space/N/E cycling keys), `DisembarkController` (:364).
  **`CommandController` and `ScoringController` have no input handlers at
  all** — pure button phases, confirming the §4.3 claim that they need only
  focus navigation.
- **Board picking is manual everywhere — there are no `Area2D`s on tokens.**
  Every controller converts screen→world through the `BoardRoot` transform
  and distance-tests `SceneRefs.token_layer()` children by
  `unit_id`/`model_id` metadata (e.g.
  `MovementController._get_model_at_position:2312`). Pad-native cycling
  (§4.2) sidesteps pixel-hunting entirely and just reuses the *result* of
  that lookup: board click-select already funnels into
  `_select_unit_in_list_by_id` — the same entry point the right-panel
  ItemList uses, so `BoardCycler` can drive it directly.
- **One action pipeline (verified end-to-end):** controller builds an action
  dict (e.g. `STAGE_MODEL_MOVE`) → `emit_signal("<phase>_action_requested")`
  → `Main._on_*_action_requested` (`Main.gd:9536`) →
  `NetworkIntegration.route_action` (`NetworkIntegration.gd:53`) →
  `BasePhase.execute_action` (`BasePhase.gd:91`): validate → process →
  `PhaseManager.apply_state_changes`. The MCP bridge's `dispatch_action`
  enters at the very same `BasePhase.execute_action`. This is the seam
  principle #2 (§1) relies on — it already exists and is multiplayer-routed,
  so pad input inherits MP sync and replay logging by construction.
- Misc surfaces: measuring tape is fully input-wired in `Main` (T/Y + mouse
  motion preview); `WoundAllocationOverlay._input:798` resolves wound
  allocation by clicking models on the board; `LineOfSightManager` previews
  LoS to the live cursor while G is held; `DebugManager` free-drags models in
  debug mode. (Side-finding: the newer `RulerTool`'s click-drag is only
  reachable from test seams today — its production input was never wired.)
- **Joypad code: none.** No `InputEventJoypad*`, no `Input.get_vector`, no
  joypad events in any action (game code; only the GUT test addon mentions
  joypads).
- **Deliberate key collisions exist** (edge-triggered `_input` vs held-poll
  `_process`: A/S/W/V/G/R each mean two things) — reinforcing that new pad
  bindings must land in one registry rather than as more scattered keycode
  checks.
- **Critical detail for the virtual-cursor layer:** several handlers hit-test
  the *live OS pointer*, not the event's position —
  `board_root.get_local_mouse_position()` (`FightController.gd:1366`,
  `ShootingController.gd:4215`, `WoundAllocationOverlay.gd:812`),
  `get_viewport().get_mouse_position()` (`Main.gd:5422`). A synthetic-mouse
  layer must therefore `Input.warp_mouse()` the real pointer **and**
  `Input.parse_input_event()` the clicks. The codebase already ships the
  proven recipe in production: the MCP `select_unit` handler does exactly
  this (`40k/addons/godot_mcp/handlers/wh40k_handlers.gd:305–322`).

### 3.4 UI surface inventory & focus readiness

- **Focus navigation today is effectively zero.** No `focus_neighbor_*`
  anywhere in the project; the only scene-set focus is `FOCUS_CLICK` (mode 1
  — *not* reachable by keyboard/pad) on four `Main.tscn` nodes
  (`UnitListPanel`, `UndoButton`, `ResetButton`, `ConfirmButton`);
  `grab_focus()` is used only for text fields (chat, save-name). There is no
  Tab/arrow traversal of any panel.
- **The HUD is a thin scene skeleton; panels are procedurally rebuilt per
  phase** by controllers via `SceneRefs`/`PhaseControllerBase`
  (`_setup_bottom_hud`/`_setup_right_panel`, `PhaseControllerBase.gd:22–49`).
  Static skeleton: bottom bar (End Phase, stratagem button, overwatch
  auto-decline CheckButton, labels), 400 px right panel (unit ItemList +
  unit card with Undo/Reset/Confirm), empty 400 px left panel, code-built top
  scoreboard. Widget volume: **~220 procedurally created button-family
  Controls across 37 files** (Command 19, Shooting 18 + slider/spinbox,
  Movement 13, Scoring 10, Charge 9, Fight 8, ~25 in `Main.gd`), ~66
  list/option/spin/lineedit widgets, **95 hover tooltips**, **37 right-click
  handlers**. Consequence: focus wiring cannot be authored in the editor —
  it must be a code helper applied after each panel rebuild (§5.2.4). The
  all-procedural style actually makes that *cheaper*: one shared helper, ~7
  call sites.
- **Dialogs: 37 files in `40k/dialogs/`, all `AcceptDialog`** (true Windows,
  so Godot's modal focus containment comes free) — but none set a
  first-focused control, and many hide the native OK button in favor of
  custom buttons, so a pad user currently lands in a modal with nothing
  focused. The fix is mechanical (focus the first actionable control on
  `about_to_popup`, one shared helper). A handful of overlays are *not*
  Windows (`MathhammerUI` ~123 KB with sliders/spinboxes, `DatasheetModal`,
  `WoundAllocationOverlay` ~88 KB which resolves by board clicks,
  `GameLogPanel` ~72 KB, `StratagemPanel`, `SaveLoadDialog` ~51 KB with the
  save-name LineEdit) — these need the `PadContext` MODAL/UI_FOCUS treatment
  explicitly.
- **Menus:** MainMenu = 7 OptionButtons + 6 Buttons (no text entry);
  MultiplayerLobby has **IP + port LineEdits**; WebLobby a **6-char code
  LineEdit**; SettingsMenu is tabbed (sliders, checkboxes, OptionButtons)
  with a click-to-rebind Controls tab that captures **keyboard keys only**.
- **Theme/fonts:** global font Rajdhani-SemiBold via `[gui] custom_font`; no
  global Theme resource and no global default font size (engine 16 px
  applies unless overridden); chrome is applied procedurally by
  `WhiteDwarfTheme.gd` — which **already defines and applies a focus
  StyleBox** (`create_button_focus`, `WhiteDwarfTheme.gd:81`, applied at
  `:113/:151/:166`). The visual half of focus support exists; nothing
  keyboard-focusable can show it yet.
- **Dead lever, high value:** Settings already has a persisted **"UI Scale"
  slider** (0.5–2.0; `SettingsMenu.gd:159`, `SettingsService.ui_scale` with a
  `ui_scale_changed` signal) — **but no consumer applies it** (verified: zero
  `content_scale_factor` references in game code). Wiring it is a near-free
  legibility win for the Deck and is pulled into M0.
- The two fixed 400 px side panels consume 800 of 1920 base px; on the
  Deck-scaled canvas the remaining board window gets tight. Collapse
  affordances already exist (left-panel hide, `LeftRosterStrip` L-toggle) —
  M5 evaluates defaults for small screens.

### 3.5 Display & legibility baseline (Deck math)

`project.godot` ships `viewport 1920×1080`, `stretch/mode = canvas_items`,
`aspect = expand`. On a Deck panel (1280×800, 16:10) that renders the canvas
at a **⅔ scale factor** (1280/1920 = 0.667; the extra vertical space extends
the canvas to 1920×1200 logical, so we gain board real estate rather than
letterboxing — good). Consequence for Valve's ~9 px text floor:

> **Any font sized below ~14 px in the 1080p design space renders below 9 px
> physical on Deck and fails the legibility bar.**

The audit found representative inline sizes of **12 px body text (≈8 px
physical on Deck) and 10 px captions (≈6.7 px)** — both below the bar — plus
11 px CP labels; headers (14–32 px) are fine. The M5 milestone includes a font
audit against that threshold, with the newly-wired UI-Scale setting (§3.4) as
a partial mitigation. (Scale math to be confirmed empirically in M5 by running
the game at 1280×800 and measuring a screenshot — per project rules this is a
claim until validated windowed.)

---

## 4. Proposed control scheme

Designed for the Deck's Xbox-style layout (A bottom / B right / X left / Y
top, LB/RB bumpers, LT/RT triggers, Menu ≡ Start, View ⧉ Select). One scheme,
re-skinned by glyphs for other pads.

### 4.1 The context model (what makes one scheme cover seven phases)

All pad input is interpreted through a small explicit state machine
(`PadContext`), which also drives the hint bar:

```
BOARD_FREE      – nothing armed; browsing the battle
UI_FOCUS        – focus is inside a panel/dialog (d-pad moves focus)
CARRY_MODEL     – a model is "picked up" (deployment placement, movement,
                  charge move, pile-in, consolidate)
TARGET_SELECT   – an attack/charge/ability is armed and wants a target
MODAL           – a blocking dialog owns all input
```

The same physical buttons keep one *semantic* meaning across contexts
("cycle the current list", "confirm", "cancel") — the context defines what the
list *is* (units → models → targets). This is exactly XCOM 2's trick and it is
what keeps the scheme learnable.

### 4.2 Global mapping

| Input | BOARD_FREE | UI_FOCUS | CARRY_MODEL | TARGET_SELECT |
|---|---|---|---|---|
| **Left stick** | move virtual cursor (fallback layer) | — (reserved) | **drive the carried model** (analog speed; budget-capped) | move cursor between candidates (optional fine aim) |
| **Right stick** | pan camera | pan camera | pan camera | pan camera |
| **R3 (click)** | center camera on active unit |〃 | center on carried model | center on current target |
| **LT / RT** | zoom out / in (analog) | 〃 | 〃 | 〃 |
| **LB / RB** | **cycle eligible units** ◀ ▶ (auto-pans camera, highlights) | cycle tabs/pages where a panel has them | **rotate model / formation** ↺ ↻ (Q/E parity) | **cycle eligible targets** ◀ ▶ |
| **A** | select highlighted unit (→ phase flow starts) | press focused control | **drop / commit model position** (legality-checked) | assign / toggle-declare target |
| **B** | deselect / step back | leave panel focus → board (or close dialog) | cancel carry, snap model back | back out of targeting |
| **X** | phase-contextual secondary (see §4.3) | 〃 | undo last placed model / reset unit move | clear assignment |
| **Y** | inspect: datasheet/unit card of highlighted unit | 〃 | toggle range/coherency overlays | inspect target's card |
| **D-pad** | enter UI focus (▼ = phase panel, ▲ = top bar) | **move focus** (`ui_*`, already pad-bound) | ◀ ▶ switch model within unit; ▲ ▼ switch mode where applicable | ◀ ▶ alt target-cycle; ▲ ▼ switch weapon row |
| **Menu (Start)** | end-phase / phase-action menu (with confirm) | 〃 | confirm the whole unit's move (= Confirm button) | confirm targets (= existing `shoot_confirm_targets`) |
| **View (Select)** | controls/shortcut overlay (glyph edition) | 〃 | 〃 | 〃 |

**While the virtual-cursor layer is active** (all of M1; any not-yet-native
corner afterwards) the face buttons simplify to pointer semantics: **A = left
click (hold = drag), X = right click, B = Escape**, left stick = pointer.
That single mapping keeps all 37 right-click context handlers and 95 hover
tooltips (§3.4) working with zero code changes.

Deck-only extras (shipped as a **Steam Input config**, never required):
back grips → quick save / quick load / measuring tape / mathhammer toggle;
right trackpad remains true mouse (the whole mouse path stays alive, so the
trackpad is always a 100% escape hatch); gyro off by default.

Modal dialogs: **A = default/confirm, B = cancel/dismiss**, focus trapped
inside the dialog, first actionable control auto-focused on popup. All other
contexts are suspended while `MODAL` is active.

### 4.3 Per-phase walkthroughs (the player-visible result)

**Deployment** — RB cycles undeployed units (camera jumps to deployment
zone) → A picks the unit up → `CARRY_MODEL`: stick places the ghost, LB/RB
rotates (models *and* formation), d-pad ◀ ▶ steps through formation presets,
A drops each model (zone-legality enforced by the existing pipeline), X undoes
the last drop, Menu confirms the unit. Transport embark prompts are ordinary
modals (A/B).

**Command** — pure `UI_FOCUS`: battle-shock tests, CP spends, secondary
mission cards are all panel buttons and modals already; d-pad + A/B covers the
whole phase once focus navigation lands (M2).

**Movement** — RB cycles units with moves remaining → A selects → move-type
choice (Normal/Advance/Fall Back/Remain Stationary) is a 4-button focus group
→ `CARRY_MODEL` per model: stick drives the model with a **live budget
readout** (used/remaining inches — same numbers the drag path computes today),
d-pad ◀ ▶ hops between models in the unit, A commits a model, X resets,
Menu confirms the unit (Advance/Desperate-Escape dice arrive as modals).
Embark/disembark are panel buttons.

**Shooting** — RB = `shoot_cycle_eligible_unit` (this cycling already exists
on Tab!) → A selects shooter → weapon list gets focus; per weapon row,
`TARGET_SELECT`: LB/RB walks eligible targets (LoS/range-filtered by the
existing legality query), camera pans to each, A assigns, Menu = confirm
targets → dice modals. X = `shoot_skip_unit`.

**Charge** — RB cycles charge-capable units → `TARGET_SELECT` to declare one
or more targets (A toggles each) → Menu rolls 2D6 → `CARRY_MODEL` with the
rolled budget and the engagement-range end-constraint the pipeline already
enforces → Menu confirms.

**Fight** — alternating activations: RB cycles the units that must fight →
pile-in (3" `CARRY_MODEL`) → melee weapon/target via `TARGET_SELECT` → dice →
consolidate (3" `CARRY_MODEL`).

**Wound/attack allocation** (today: click defending models on the board via
`WoundAllocationOverlay`) — becomes a `TARGET_SELECT` ring: LB/RB cycles the
candidate models (they are already highlighted by
`WoundAllocationBoardHighlights`), A allocates the next wound, hold-A repeats.

**Scoring / end of turn** — panels and modals; `UI_FOCUS` only.

**Anywhere**: Y opens the highlighted unit's datasheet; measuring tape stays
usable via the virtual cursor (drag) — a native "measure from token to token"
(pick A, cycle B) can come later as polish.

### 4.4 What we deliberately did NOT map

- No radial menus in v1 (see §2.6) — stratagem/ability counts per decision
  point are small enough for list focus; revisit after playtesting.
- No gyro aiming, no trackpad-required interactions, no touch: Deck extras
  stay optional.
- No "hold to preview" cursor gestures: hover-only affordances (LoS preview,
  tooltips) get explicit equivalents instead (Y inspect; overlays toggled in
  `CARRY_MODEL`) — hover exists for the virtual cursor but native flows must
  not depend on it.

---

## 5. Technical architecture

### 5.1 New components (all additive; no existing file changes required to ship M0–M1 except registered hooks)

| Component | Kind | Responsibility |
|---|---|---|
| `autoloads/InputDeviceManager.gd` | autoload | Detects last-used device (KBM ⇄ pad) with hysteresis; `signal device_changed(mode)`; joypad hot-plug (`Input.joy_connection_changed`); exposes `is_pad_active()`. Everything visual (glyphs, cursor, hint bar, focus ring) keys off this one signal. |
| `scripts/input/VirtualCursor.gd` (+ CanvasLayer scene) | autoload | Stick-driven pointer that **warps the real pointer (`Input.warp_mouse`) and synthesizes `InputEventMouseMotion`/`InputEventMouseButton` via `Input.parse_input_event()`** — every existing click/drag/hover path works untouched, *including* the handlers that hit-test the live cursor (§3.3). This is the exact production-proven recipe of the MCP `select_unit` handler (`wh40k_handlers.gd:305–322`). Accel curve, zoom-aware speed, A/X → L/R click, auto-hide when a real mouse moves. Optional later: magnetism that eases toward tokens/buttons (ITB-style snap adapted to a continuous board). |
| `scripts/input/PadRouter.gd` | autoload | Owns the `PadContext` state machine (§4.1); translates pad actions into calls on the active phase controller / UI; publishes `context_changed` for the hint bar. Phase controllers *push* context transitions at the same places they already flip their internal mouse modes. |
| `scripts/input/BoardCycler.gd` | service (owned by PadRouter) | Eligibility-ordered rings of unit/target IDs built from the same legality queries the MCP `get_legal_actions` command uses; stable ordering + wraparound; camera auto-pan on step; selection goes through the exact click-selection entry point. |
| `scripts/input/ModelCarryController.gd` | service | Native stick-drive for every "drag a model" flow: per-frame displacement → the phase's existing staged-move preview → commit via the same action dispatch the mouse drop uses. Budget/legality/coherency stay in the pipeline where they live today. |
| `ui/PadHintBar.tscn` + `.gd` | HUD strip | Bottom glyph+label chips rendered from `PadContext` (e.g. `LB/RB Cycle Units · A Select · Y Datasheet · Menu End Phase`). Hidden in KBM mode. Colors/typography per design guidelines §9. |
| `scripts/input/GlyphDB.gd` + assets | helper + art | Action → glyph texture for the active device. Use **Kenney Input Prompts (CC0)** or the `controller_icons` Godot addon (MIT) — both cover Deck/Xbox/PS/Switch glyph sets. Feeds hint bar, shortcut overlay, and inline button labels. |
| In-game OSK scene (M4/M5) | dialog | Pad-navigable keyboard for the few text fields (save names, lobby address, army names); on Steam builds, prefer GodotSteam `showFloatingGamepadTextInput` and fall back to the in-game scene. |

### 5.2 Changes to existing systems

1. **`project.godot` `[input]`**: add Joypad A to `ui_accept`, Joypad B to
   `ui_cancel`; add the new `pad_*`-facing actions (cycle, confirm-unit,
   inspect, camera axes, zoom) — *actions named by semantics, not by device*,
   with keyboard equivalents kept alongside so KB shortcuts and pad bindings
   are one list.
2. **`KeybindingManager` → device-agnostic**: migrate the registry to create
   real runtime `InputMap` actions (`InputMap.add_action` +
   `action_add_event`) instead of matching raw `InputEventKey`s, keeping the
   ConfigFile persistence and adding an optional joypad event per action.
   Call sites move from `matches_action(event, id)` to
   `event.is_action_pressed(id)` — mechanical change, and the rebinding UI
   gains a controller column for free.
3. **Phase controllers** (`MovementController`, `ShootingController`,
   `ChargeController`, `FightController`, `DeploymentController`,
   `CommandController`, …): each gains a thin *pad adapter* section —
   (a) report context transitions to `PadRouter`, (b) expose the small verbs
   the router needs (`cycle_next_eligible()`, `arm_targeting(weapon)`,
   `carry_model(idx)` …) — implemented by delegating to code paths that
   already exist for mouse + MCP. **No rules logic moves.**
4. **Focus pass over the UI**: ensure every interactive Control is
   `focus_mode = ALL` with sane neighbors (Godot auto-resolves most; manual
   `focus_neighbor_*` only where layout confuses it), every dialog grabs focus
   on popup, and a **visible focus ring** ships in the theme (slot-table
   color). This is bulk-but-shallow work; the audit in §3.4 sizes it.
5. **Settings**: a "Controller" section (cursor speed, cycle order
   preference, hint bar on/off, rumble on/off, rebinding).

### 5.3 Testing architecture (project gate compliance)

- **Extend `addons/godot_mcp`** with `simulate_joy_button` /
  `simulate_joy_axis` (thin wrappers over `Input.parse_input_event()` with
  `InputEventJoypadButton/Motion`), alongside the existing `simulate_click` /
  `simulate_key_press` / `simulate_action`. `simulate_action` already covers
  anything routed through InputMap actions.
- Each milestone lands with **windowed scenarios under `40k/tests/scenarios/`**
  that play controller-only: inject joypad events → assert focus owner /
  selection / model positions via `get_node_info` + `diff_snapshot` → capture
  screenshots showing the pad UI (hint bar, focus ring, cycle highlight) →
  `verify_delivery` PASS with no ERROR log lines.
- A KBM regression scenario re-runs per milestone to prove mouse play is
  untouched.

---

## 6. Phased roadmap

Each milestone is independently shippable and ends with its windowed-scenario
gate + a `version_history.json` entry (these are player-facing changes).

### M0 — Foundations (small) — ✅ SHIPPED 2026-07-12 (v0.25.0)
InputMap additions (incl. `ui_accept`/`ui_cancel` joypad events),
`InputDeviceManager`, glyph chips (`scripts/input/GlyphDB.gd` — programmatic
chips rather than a texture pack, so they scale with UI Scale; swappable for
textures later), focus-ring visibility (the `WhiteDwarfTheme` focus StyleBox
already existed — §3.4), hint-bar shell (`PadHintBar` autoload), camera on
right stick + trigger zoom in `Main._process`, **the dead UI-Scale setting
wired to `content_scale_factor`** (§3.4), `simulate_joy_button`/
`simulate_joy_axis` in both the MCP bridge and the scenario runner.
**Gate (met):** windowed scenarios `pad_m0_menu_nav` (19/0 — D-pad walks the
main menu, A opens Settings, focus lands on Close, A closes, focus restored)
and `pad_m0_camera` (20/0 — right-stick pan moved the board ≥30 px, RT zoom,
hint bar visible in pad mode, UI-Scale drives `content_scale_factor` and is
restored) both PASS; KBM regression scenario unaffected.

### M1 — Whole-game fallback: the virtual cursor (medium) — ✅ SHIPPED 2026-07-12 (v0.26.0)
Shipped: `VirtualCursor` autoload — left stick drives the REAL pointer
(`Input.warp_mouse` + synthesized motion/button events, per the §3.3 recipe),
A/X = left/right click (hold-A = drag), with a visible cursor ring,
quadratic response curve, **edge-push camera panning** (driving the cursor
against the screen edge pans the board — how off-screen targets stay
reachable), and an explicit CURSOR ⇄ FOCUS mode split (stick → cursor owns
A/X; D-pad or a dialog popup → parks the cursor so A/B act on the focused
control — this is what prevents one press double-activating a hovered token
AND a focused button). `InputDeviceManager` gained **propagation-proof
device detection** (a `pad_probe_buttons` InputMap action polled in
`_process`, because scene `_input` runs before autoloads and exclusive
dialog Windows swallow events entirely — discovered the hard way), a
synthetic-mouse handshake so the cursor's own warps don't read as "mouse
used", and a **dialog watcher**: every `AcceptDialog` that pops in pad mode
gets its confirm-ish button focused (custom-button dialogs order
[Go Back, Confirm…], so first-button focus would make A cancel), with a
guard that withholds focus until ui_accept is released (no chained
double-confirms). Menu/Start = phase action behind a ConfirmationDialog;
SettingsMenu closes on `ui_cancel` (Esc + pad B).
**Gate (met):** `pad_m1_cursor_basics` (24/0 — stick moves the real pointer,
glide+A click-selects a unit, hold-A drag stages a model move, clicking
"Confirm Move" lands it in GameState) and `pad_m1_full_turn_cursor` (73/0 —
a complete solo turn command → movement (real cursor drag) → shooting
(summary dialog) → charge → fight (unfought-units dialog) → scoring
(mission-discard dialog) → player 2's command phase, pad-only, incl. B
natively cancelling the end-phase confirm); M0 scenarios + KBM baseline
re-run green. Deployment-by-cursor uses the same click/drag paths but has no
dedicated windowed scenario yet — explicit coverage lands with M3's
deployment carry work.

### M2 — Cycling, selection & panel focus (medium) — ✅ SHIPPED 2026-07-12 (v0.27.0)
Shipped: `PadRouter` autoload — LB/RB cycles whichever list is live (the
right-panel unit list generically, driven through `item_selected` exactly
like a mouse row-click; eligible shooters then eligible targets in the
shooting phase, reusing the `shoot_*` keyboard semantics), with camera
centering on the cycled unit/target. A assigns the highlighted target (after
syncing SELECT_SHOOTER to the phase — the controller's auto-select is
cosmetic and the phase would reject the assignment otherwise), X skips the
shooter, B deselects/releases focus, Y toggles the datasheet, D-pad enters
panel focus when nothing is focused, and Start is context-dependent in
shooting (Confirm Targets while assignments pend). The hint bar is now
contextual (board / targeting / panel-focus sets). WoundAllocationOverlay
(a plain Control, invisible to the AcceptDialog watcher) gets its own
focus hook. The planned bulk `FocusWiring.apply()` pass proved unnecessary
for M2: procedural Buttons default to `FOCUS_ALL` already — only the four
`FOCUS_CLICK` nodes in Main.tscn needed flipping; a fuller per-phase
focus-order audit moves into M4.
**Gate (met):** `pad_m2_shooting_native` (35/0 — an entire shooting
activation with zero virtual-cursor use: cycle shooter → cycle targets →
assign → Confirm Targets via Start → defender's stratagem window → staged
dice + wound allocation walked with A → X skips remaining weapons →
`has_shot` verified in GameState) and `pad_m2_unit_cycle` (26/0 — movement
phase bumper cycling, Y datasheet toggle, D-pad panel-focus entry, B
release). All M0/M1 pad scenarios + the KBM baseline re-run green (7/7).

### M3 — Model carry: native movement (large — the heart of the feature)
`ModelCarryController` for Deployment and Movement first (budget readout,
rotation on bumpers, formation presets, per-model d-pad hop, undo/reset), then
the same mode reused for Charge moves, pile-in, consolidate. **Gate:**
Deployment + full Movement phase + a charge executed pad-native
(`pad_m3_carry_*.json` suite); positions/legality byte-identical to the same
actions performed by `dispatch_action` (diff against the action log).

### M4 — Full native sweep + stratagems + text entry (medium)
Command/Scoring flows, stratagem & reactive prompts (overwatch etc.), save/load
+ army selection + multiplayer lobby on pad, in-game OSK, Controller settings
tab, KeybindingManager migration (§5.2.2) with pad rebinding. **Gate:**
new-game-to-turn-2 played pad-only including a save/load round-trip
(`pad_m4_full_game.json`).

### M5 — Steam Deck fit & finish (medium)
1280×800 run-through; font audit vs the ≥14 px design floor (§3.5); hit-target
sizing; hint-bar/glyph correctness audit; Steam Input config (back-grip
extras) authored and exported; performance sanity at 800p; suspend-safety
(autosave on window unfocus). If a Steam build exists by now: GodotSteam OSK +
controller glyph check under Steam Input. **Gate:** windowed scenario run at
1280×800 + screenshot review checklist; every text ≥9 px physical.

### M6 — Controller-only validation suite & release (small)
Consolidate the per-milestone scenarios into a pad-only regression suite in
`run_scenarios.sh`; KBM regression suite green; EXPORT_GUIDE.md gains a Deck
section (Linux export, controller config, itch sideload instructions);
changelog entry; optional: creating the Steam page / depot is out of scope
here.

Sequencing rationale: M1 before M2/M3 so the game is *fully* playable on Deck
at the earliest possible date (worst-case controls everywhere beat best-case
controls somewhere); M3 is the largest and rides on interaction patterns
proven in M2; M5 is deliberately late so the legibility pass measures the
final UI, not a moving target.

---

## 7. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Hover-dependent affordances (95 tooltip sites, LoS hover preview, measuring tape) invisible to native pad flows | Virtual cursor keeps them reachable; native flows get explicit equivalents (Y inspect, overlay toggles in `CARRY_MODEL`); §3.3/§3.4 enumerate the hover paths |
| Drag logic reads the live OS pointer, not event positions (`get_local_mouse_position()` in Fight/Shooting/WoundAllocation — §3.3) | Virtual cursor **warps the real pointer** (the proven `select_unit` recipe) rather than only synthesizing events; M3's carry mode feeds the *staged-move pipeline*, not the mouse layer |
| Two-pointer fights (Deck trackpad = real mouse vs virtual cursor) | Warping means there is only ever **one true pointer position**; `InputDeviceManager` hysteresis parks the virtual layer the instant real mouse motion arrives |
| Focus navigation dead-ends in procedurally built panels | Panels are rebuilt per phase, so focus wiring must run *after* build — one shared `FocusWiring.apply(panel)` helper called from each controller's panel-refresh; scenario per phase asserts a full d-pad walk visits every control |
| `ui_*` actions leaking into gameplay (stick scrolls a list while also moving cursor) | `PadContext` gates consumption: board contexts consume stick input before GUI, UI_FOCUS releases it; explicit `set_input_as_handled()` discipline at the router |
| Text entry on Deck (lobby address, save names) | In-game OSK baseline (works for itch sideloads), GodotSteam floating OSK when under Steam |
| Multiplayer: pad player vs mouse player desync assumptions | Nothing to do — pad drives the same dispatched actions; add one MP smoke scenario in M4 |
| Scheme overload (LB/RB meaning 3 things) | One semantic ("cycle/rotate the current thing"), hint bar always names the current meaning, and contexts are mutually exclusive by construction |
| Font/UI too small on Deck even after scaling | §3.5 math gives a measurable floor; M5 audits against it with screenshots at 1280×800 |

---

## 8. Scoping decisions (recorded 2026-07-12)

1. **Distribution target: design for both** (itch.io sideload *and* a possible
   later Steam release). Consequence: the in-game pad-navigable OSK is the
   baseline text-entry path (M4) and nothing may hard-depend on Steamworks;
   GodotSteam (floating keyboard, official Steam Input config, Deck Verified
   checklist) stays an optional M5 enhancement behind a feature check.
2. **First shippable slice: M0 + M1 (fallback-first).** Iteration 2 delivers
   foundations + the virtual cursor so the entire game is Deck-playable at the
   earliest date; native cycling/carry (M2/M3) follow.
3. **Multiplayer priority: solo-vs-AI + hotseat first.** Lobby screens and the
   OSK remain in M4; a multiplayer smoke scenario still lands there to prove
   the shared action pipeline holds.
4. **Testing hardware: a Steam Deck is available.** Every milestone gate gains
   a hands-on Deck feel-check (sideloaded build) alongside the automated
   MCP joypad-injection scenarios; M5's legibility/performance numbers are
   measured on the real device, not only the 1280×800 emulated window.

---

*Reference docs consulted: `40k/tests/TESTING_METHODOLOGY.md`, `SESSION_PLAYBOOK.md`, `40k/docs/design_guidelines_2d_topdown.md`, `40k/addons/godot_mcp/README.md`, `CLAUDE.md` validation gates.*
