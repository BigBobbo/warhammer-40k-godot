# Design Guidelines Implementation — task list

Each task implements one slice of `40k/docs/design_guidelines_2d_topdown.md`. Format:
small, atomic, individually validated, individually revertable.

## How to work this list

- Run interactively via `do-one-task` for the first 5 tasks to stabilize the template,
  then batch via `do-all-tasks` in supervised sessions.
- **Each task MUST:**
  1. Add or extend a windowed scenario under `40k/tests/scenarios/visual/`.
  2. Pass that scenario via `bash 40k/tests/run_scenarios.sh tests/scenarios/visual/<file>.json`.
  3. Pass the full regression suite via `bash 40k/tests/run_scenarios.sh` (no failures vs. baseline).
  4. Capture a before/after screenshot pair to `40k/test_results/design_guidelines/T##/`.
  5. Commit with `[T##]` prefix and reference the doc section.
- **Parallelism:** tasks declare a `Lock:` tag. Two parallel sessions may run concurrently
  only on tasks with disjoint locks. Use `Agent` with `isolation: "worktree"` per session.
- **Visual review gate:** tasks remain marked `[ ]` until a human reviews the screenshot
  pair. Use the `[VISUAL-REVIEW]` flag in commit messages on cosmetic-only changes.
- **Order:** T01 → T02 must complete first (foundation). T03–T12 are the doc's top-10 quick
  wins. T13+ are remaining sub-question refinements, parallelizable.

Locks in use:
- `UIConstants` — touches the color slot autoload
- `Movement` — MovementController + MovementRangeVisual
- `Shooting` — ShootingController + dice surface
- `Charge` — ChargeController + Charge*Visual
- `Fight` — FightController + fight UI
- `HUD-Top` — top phase bar & action buttons
- `HUD-Right` — right column panels & modals→side conversions
- `HUD-Left` — game log & roster strip
- `TokenLayer` — TokenVisual & per-token chrome
- `BoardLayer` — terrain overlays, LOS lines, threat shading
- `Infra` — scenario harness, screenshot helper

---

## Foundation (sequential — must complete before anything below)

- [ ] **T01 — UIConstants color slot autoload**
  - **Lock:** UIConstants  • **Doc:** §9  • **Depends:** —
  - **Touches:** new `40k/autoloads/UIConstants.gd`, `40k/project.godot` (autoload registration)
  - **Change:** Add an autoload exposing the strict slot table from the doc:
    `FRIENDLY_PLAYER_TEAL`, `ENEMY_PLAYER_MAGENTA`, `WARNING_ORANGE`, `CONFIRMED_GREEN`,
    `MARGINAL_YELLOW`, `INVALID_RED`, `NEUTRAL_UI_PALE_WHITE`. Faction colors stay
    per-army (read from army data). Provide `striped_pattern(color)` for the yellow
    semantic / faction-yellow collision case.
  - **Scenario:** `tests/scenarios/visual/T01_uiconstants_present.json` — load any
    fixture, `execute_script` to read `UIConstants.FRIENDLY_PLAYER_TEAL` and assert non-null.
  - **Acceptance:** all slots resolve; full regression unaffected; design doc table
    matches the GDScript constants 1:1.

- [ ] **T02 — Visual-scenario harness scaffold**
  - **Lock:** Infra  • **Doc:** —  • **Depends:** —
  - **Touches:** new `40k/tests/scenarios/visual/_schema.md`, new
    `40k/tests/scenarios/visual/_template.json`, new helper section in
    `40k/tests/TESTING_METHODOLOGY.md` titled "Design-guidelines visual tasks"
  - **Change:** Document the convention: every T## task creates one JSON under
    `tests/scenarios/visual/T##_<slug>.json` following the existing scenario `steps`
    schema, with a mandatory `screenshot` step at start (label `T##_before`) and end
    (label `T##_after`). Add a tiny helper to `run_scenarios.sh` that, when given a
    `tests/scenarios/visual/T##_*` path, also copies the captured screenshots into
    `test_results/design_guidelines/T##/`.
  - **Scenario:** `tests/scenarios/visual/T02_harness_self_check.json` — minimal scenario
    that captures one screenshot of the main menu via the new convention.
  - **Acceptance:** harness produces the expected directory layout; methodology doc
    updated; no regression.

## Top-10 quick wins (parallelizable after T02 if locks are disjoint)

- [ ] **T03 — Drag-ruler with budget coloring during movement**
  - **Lock:** Movement  • **Doc:** §5 quick-win #1  • **Depends:** T01, T02
  - **Touches:** `40k/scripts/MovementController.gd`, `40k/scripts/MovementRangeVisual.gd`
  - **Change:** While dragging a model, paint the path from start → cursor as colored
    segments. Use `CONFIRMED_GREEN` for ≤ M, `MARGINAL_YELLOW` for ≤ M+Advance,
    `INVALID_RED` beyond. Cumulative inches label follows the cursor. SHIFT drops a
    waypoint; ENTER commits; ESC cancels. M and Advance sourced from RulesEngine, never
    hardcoded.
  - **Scenario:** `tests/scenarios/visual/T03_drag_ruler.json` — load a movement-phase
    fixture, dispatch `BEGIN_MODEL_DRAG`, move cursor to three test positions
    (≤M, ≤M+Advance, beyond), screenshot at each.
  - **Acceptance:** three segment colors visible in screenshots; existing movement
    scenarios pass unchanged.

- [ ] **T04 — Six-phase top-center bar with active highlight**
  - **Lock:** HUD-Top  • **Doc:** §4  • **Depends:** T01, T02
  - **Touches:** `40k/scenes/Main.tscn` (add PhaseBar PanelContainer), new
    `40k/scripts/PhaseBar.gd`, `40k/autoloads/PhaseManager.gd` (signal hook)
  - **Change:** Render six pills `Command → Movement → Shooting → Charge → Fight →
    Morale` along the top center. Active pill glows in active player's slot color;
    completed pills dim; future pills disabled. Click past pills is inert; click future
    shows a tooltip. Listen on `PhaseManager.phase_changed`.
  - **Scenario:** `tests/scenarios/visual/T04_phase_bar.json` — load a fixture in
    Command phase, screenshot; advance to Movement, screenshot; verify pill highlight
    moved via `get_node_info` on the PhaseBar node.
  - **Acceptance:** highlight follows phase transitions; screenshot pair shows the move.

- [ ] **T05 — Hover-forecast tooltip for shooting**
  - **Lock:** Shooting  • **Doc:** §7  • **Depends:** T01, T02
  - **Touches:** `40k/scripts/ShootingController.gd`, new `40k/scripts/HoverForecast.gd`
  - **Change:** When a shooter is selected and the cursor hovers an enemy unit, render
    a small tooltip near the cursor: weapon name → target name; attacks, BS, S vs T,
    AP, D; expected wounds. Math via `RulesEngine.preview_attack(...)` (add helper if
    not present) so modifiers (Oath of Moment, Heavy, cover) are reflected.
  - **Scenario:** `tests/scenarios/visual/T05_hover_forecast.json` — load a shooting
    fixture, dispatch `SELECT_SHOOTER`, simulate hover via `execute_script` setting the
    target id, screenshot, assert tooltip node exists.
  - **Acceptance:** tooltip renders within 50ms of hover; cover modifies reported BS.

- [ ] **T06 — Convert Weapon Order modal to side-anchored panel**
  - **Lock:** HUD-Right  • **Doc:** §3  • **Depends:** T01, T02
  - **Touches:** `40k/scripts/ShootingController.gd`, `40k/scenes/Main.tscn` (or whatever
    instantiates the modal)
  - **Change:** The Weapon Order surface currently opens as a centered modal covering
    the board. Convert it to a side panel anchored to the right column. Board stays
    visible. ESC cancels. Keep the existing "Start Sequence" action wiring.
  - **Scenario:** `tests/scenarios/visual/T06_weapon_order_panel.json` — load a
    shooting fixture with multi-weapon unit, dispatch `BEGIN_WEAPON_ORDER`, screenshot,
    assert the board is not occluded by checking the modal node anchor.
  - **Acceptance:** existing weapon-order regression scenarios still pass; new
    screenshot shows board visible.

- [ ] **T07 — Per-tile cover icons on terrain**
  - **Lock:** BoardLayer  • **Doc:** §6  • **Depends:** T01, T02
  - **Touches:** `40k/scripts/BoardVisual.gd` or new `40k/scripts/TerrainCoverOverlay.gd`,
    `40k/deployment_zones/` data files (read existing terrain definitions)
  - **Change:** For each terrain piece in the active layout, render a small shield
    glyph at the polygon centroid showing `+1` / `+2` / `LB`. Persistent. Hide only
    in a debug "clean board" mode.
  - **Scenario:** `tests/scenarios/visual/T07_terrain_cover_icons.json` — load a
    fixture with the default terrain layout, screenshot, assert N TerrainCoverIcon
    nodes exist where N = number of terrain pieces with cover.
  - **Acceptance:** icons visible at zoom 1.0; not occluding tokens at zoom ≥ 0.5.

- [ ] **T08 — Two-ring token (faction inner + player-slot outer)**
  - **Lock:** TokenLayer  • **Doc:** §2  • **Depends:** T01, T02
  - **Touches:** `40k/scripts/TokenVisual.gd` (or whatever renders tokens)
  - **Change:** Replace the single-color base ring with two concentric rings: inner =
    faction color (from army data), outer thin ring = player-slot color
    (`FRIENDLY_PLAYER_TEAL` for P1, `ENEMY_PLAYER_MAGENTA` for P2). Faction color and
    slot color now read from independent sources.
  - **Scenario:** `tests/scenarios/visual/T08_two_ring_token.json` — load fixture, take
    engagement-zoom screenshot, assert each TokenVisual has two CircleShape children.
  - **Acceptance:** P1 Custodes shows gold inner + teal outer; P2 Witchseekers shows
    blue inner + magenta outer. Existing engagement scenarios still pass.

- [ ] **T09 — Exhaustion grayscale for acted units**
  - **Lock:** TokenLayer + HUD-Left  • **Doc:** §8  • **Depends:** T01, T02, T08
  - **Touches:** `40k/scripts/TokenVisual.gd`, `40k/scripts/ArmyPanel.gd` (or roster
    panel), `40k/phases/MovementPhase.gd` and shooting/charge phases (signal on
    unit-completed-action)
  - **Change:** When a unit's "has acted this phase" flag flips true, set the token's
    modulate to grayscale (0.6, 0.6, 0.6, 1.0) and the roster card to a dimmer
    background. Reset on phase end.
  - **Scenario:** `tests/scenarios/visual/T09_exhaustion_grayscale.json` — load a
    movement-phase fixture, dispatch `END_UNIT_MOVE` for one unit, screenshot,
    `expect_state` modulate value via `get_node_info`.
  - **Acceptance:** acted unit visibly dim; phase-end restores full color.

- [ ] **T10 — Held-key threat overlay (Tab)**
  - **Lock:** BoardLayer  • **Doc:** §6  • **Depends:** T01, T02
  - **Touches:** `40k/scripts/Main.gd` (input handling), new `40k/scripts/ThreatOverlay.gd`
  - **Change:** On `Tab` key held, paint every enemy unit's shooting-range circle in
    `MARGINAL_YELLOW` at 15% alpha and the 12" charge-threat ring in `INVALID_RED` at
    10% alpha. On key release, remove. Off by default (preserves overlay budget).
  - **Scenario:** `tests/scenarios/visual/T10_threat_overlay.json` — load a fixture
    mid-game, simulate `Tab` press via `simulate_key_press`, screenshot, assert N
    ThreatRing nodes appear where N matches enemy unit count.
  - **Acceptance:** key release removes overlay completely; no performance regression
    on a 20-unit board.

- [ ] **T11 — LOS line tool**
  - **Lock:** BoardLayer  • **Doc:** §6  • **Depends:** T01, T02
  - **Touches:** `40k/scripts/ShootingController.gd`, new `40k/scripts/LOSLineVisual.gd`,
    reuse existing LOS math in `40k/autoloads/RulesEngine.gd` (or wherever LOS lives)
  - **Change:** When a shooter is selected and the cursor hovers a candidate target,
    draw a single line shooter-base → target-base. `CONFIRMED_GREEN` if clear,
    `MARGINAL_YELLOW` if obscured (cover saves apply), `INVALID_RED` if blocked.
  - **Scenario:** `tests/scenarios/visual/T11_los_line.json` — three sub-checks: clear
    LOS (open board), obscured LOS (through light cover), blocked LOS (behind blocking
    terrain). Screenshot each.
  - **Acceptance:** three different colors appear in the three sub-screenshots.

- [ ] **T12 — Refactor existing visual scripts to consume UIConstants**
  - **Lock:** UIConstants + all visual scripts (serial — blocks others)  • **Doc:** §9
  - **Depends:** T01
  - **Touches:** `40k/scripts/MovementRangeVisual.gd`, `EngagementRangeVisual.gd`,
    `CoherencyCircleVisual.gd`, `ChargeTrajectoryPreview.gd`, `DeepStrikeExclusionVisual.gd`,
    `DamageFeedbackVisual.gd`, `ChargeArrowVisual.gd`, `DeploymentZoneVisual.gd`,
    `AIMovementPathVisual.gd`
  - **Change:** Replace every ad-hoc `Color(...)` literal with the corresponding
    `UIConstants.<SLOT>`. Document each substitution in the commit body so reviewers
    can audit the slot choice.
  - **Scenario:** `tests/scenarios/visual/T12_color_audit.json` — load engagement-zoom
    fixture, full-board fixture; screenshot each. Visual diff against pre-refactor
    screenshot pair to verify no unintended visual changes (intentional changes get
    called out in commit).
  - **Acceptance:** every existing visual scenario passes; pixel-diff is either zero
    or matches the documented slot-substitution list.

## §1 Camera

- [ ] **T13 — Fit-board keybind (F)**
  - **Lock:** HUD-Top  • **Doc:** §1  • **Depends:** T02
  - **Touches:** `40k/scripts/Main.gd` (input)
  - **Change:** `F` keybind: zoom + center the Camera2D so the playable board fills
    the viewport.
  - **Scenario:** `tests/scenarios/visual/T13_fit_board.json` — pan camera off-board
    via `execute_script`, press `F`, screenshot, assert camera position matches the
    expected fit value.

- [ ] **T14 — Fit-selection keybind (Shift+F)**
  - **Lock:** HUD-Top  • **Doc:** §1  • **Depends:** T02
  - **Touches:** `40k/scripts/Main.gd`
  - **Change:** `Shift+F`: zoom + center on the currently-selected unit (or its
    bounding box for multi-model units).
  - **Scenario:** `tests/scenarios/visual/T14_fit_selection.json` — select a unit on
    the far edge of the board, press Shift+F, assert camera centered within 10px of
    unit centroid.

## §2 Tokens (continued)

- [ ] **T15 — Unit-type silhouette glyphs**
  - **Lock:** TokenLayer  • **Doc:** §2  • **Depends:** T08
  - **Touches:** `40k/scripts/TokenVisual.gd`, new `40k/assets/icons/unit_silhouettes/`
    (one monochrome SVG/PNG per major unit type)
  - **Change:** Replace the centered letter with a high-contrast silhouette glyph
    keyed off the unit's category (Infantry/Tank/Walker/Beast/Character/Aircraft/Mounted).
    Letter label moves under the base.
  - **Scenario:** `tests/scenarios/visual/T15_silhouettes.json` — load fixture with
    mixed unit types, screenshot, assert each token's child silhouette node exists
    and matches the category mapping.
  - **Acceptance:** silhouettes legible at 64px and at 32px zoom.

- [ ] **T16 — Auto-hide token labels below zoom threshold**
  - **Lock:** TokenLayer  • **Doc:** §2  • **Depends:** T15
  - **Touches:** `40k/scripts/TokenVisual.gd` (or TokenLayer parent)
  - **Change:** When camera zoom falls below 0.6, hide the under-base text label.
    Restore on zoom ≥ 0.6.
  - **Scenario:** `tests/scenarios/visual/T16_label_zoom_hide.json` — set zoom to 0.5
    via `execute_script`, screenshot; set to 1.0, screenshot.
  - **Acceptance:** labels absent in the 0.5 screenshot.

- [ ] **T17 — Cap status icons at 3 with overflow chip**
  - **Lock:** TokenLayer  • **Doc:** §2
  - **Touches:** `40k/scripts/TokenVisual.gd`
  - **Change:** Token status icons live in three fixed slots (top-left army-status,
    top-right phase-status, bottom-right special). If >3 active statuses, render only
    the highest priority per slot and a `+N` chip at the bottom-left that expands the
    full list on hover.
  - **Scenario:** `tests/scenarios/visual/T17_status_overflow.json` — apply 5 statuses
    to a test unit via `execute_script`, screenshot, assert visible icon count = 3 + 1
    chip.

- [ ] **T18 — Wound chip on base edge (replace HP bar)**
  - **Lock:** TokenLayer  • **Doc:** §2
  - **Touches:** `40k/scripts/TokenVisual.gd`
  - **Change:** For multi-wound models, render a small `W/Wmax` numeric chip at the
    base edge instead of a thin HP bar. Single-wound models show no chip.
  - **Scenario:** `tests/scenarios/visual/T18_wound_chip.json` — load fixture with a
    damaged multi-wound unit; screenshot.

- [ ] **T19 — Active-unit pulsed ring**
  - **Lock:** TokenLayer  • **Doc:** §2
  - **Touches:** `40k/scripts/TokenVisual.gd`
  - **Change:** When a unit is the active actor (selected for movement/shoot/fight),
    its outer player-slot ring pulses at 2s loop, low amplitude.
  - **Scenario:** `tests/scenarios/visual/T19_active_pulse.json` — select a unit;
    over 2 seconds capture two screenshots and assert ring alpha differs.

## §3 Modals → side panels

- [ ] **T20 — Convert Epic Challenge modal to side panel**
  - **Lock:** HUD-Right  • **Doc:** §3
  - **Touches:** `40k/dialogs/EpicChallengeDialog.gd` (or wherever Epic Challenge
    UI is wired)
  - **Change:** Side-anchored. One-line preview of effect. Board visible.
  - **Scenario:** `tests/scenarios/visual/T20_epic_challenge_panel.json` — reuse
    `co_fixture_co_offer` save; open dialog; screenshot; assert panel anchor.

- [ ] **T21 — Convert Wound Allocation overlay to side panel**
  - **Lock:** HUD-Right  • **Doc:** §3
  - **Touches:** `40k/scenes/WoundAllocationOverlay.tscn`, its script
  - **Change:** Side-anchored. Board visible during wound allocation.
  - **Scenario:** `tests/scenarios/visual/T21_wound_panel.json` — drive a shooting
    resolution into wound-allocation; screenshot.

- [ ] **T22 — Auto-zoom-to-fit on in-tactical decision opens**
  - **Lock:** HUD-Right + HUD-Top  • **Doc:** §3  • **Depends:** T13, T14
  - **Touches:** centralized helper called from each dialog opener
  - **Change:** When a side panel opens for an in-tactical decision, camera animates
    to a fit-bounds of the affected tokens (active unit + targets).
  - **Scenario:** `tests/scenarios/visual/T22_auto_zoom_decision.json` — pan camera
    off; open Weapon Order; assert camera centered on shooter + targets.

- [ ] **T23 — Canonical End-Phase button placement bottom-right**
  - **Lock:** HUD-Top + HUD-Right  • **Doc:** §3
  - **Touches:** every phase-controls panel
  - **Change:** Ensure the End-Phase button sits at the same bottom-right pixel
    position regardless of phase. Audit current placements first; document drift
    in commit body.

## §4 Phase signaling (continued)

- [ ] **T24 — Sub-state breadcrumb under active phase pill**
  - **Lock:** HUD-Top  • **Doc:** §4  • **Depends:** T04
  - **Touches:** `40k/scripts/PhaseBar.gd`, each Phase autoload to expose
    `current_substate_index` and `substates` list
  - **Change:** Beneath the active pill, render the substate row for that phase
    (e.g. Shooting: Select Unit → Select Target → Hits → Wounds → Saves → Damage).
    Light each crumb as it becomes current.

- [ ] **T25 — Active-player edge tint**
  - **Lock:** HUD-Top  • **Doc:** §4
  - **Touches:** `40k/scenes/Main.tscn` (new edge frame), `40k/scripts/Main.gd`
  - **Change:** Outer 4px of the play area tinted in the active player's slot color.
    Cheap, always-on. Listens to `PhaseManager.active_player_changed`.

- [ ] **T26 — Phase pill click affordance for past/future**
  - **Lock:** HUD-Top  • **Doc:** §4  • **Depends:** T04
  - **Change:** Past pills: click is inert but tooltip shows "completed". Future
    pills: tooltip "resolve current phase first".

- [ ] **T27 — Refactor End-Phase button to canonical position**
  - **Lock:** HUD-Right  • **Doc:** §4  • **Depends:** T23
  - **Change:** Implementation of T23 audit.

## §5 Movement & range (continued)

- [ ] **T28 — Two-layer movement range shading**
  - **Lock:** Movement  • **Doc:** §5  • **Depends:** T03
  - **Touches:** `40k/scripts/MovementRangeVisual.gd`
  - **Change:** On selected unit, fill within-Move-distance area at 12% alpha (where
    I can stand) and draw a thin outline ring at Move + selected-weapon-range (where
    I can shoot from). Weapon selector in panel switches the outer ring.

- [ ] **T29 — Persistent engagement ring on engaged units**
  - **Lock:** Movement  • **Doc:** §5
  - **Touches:** `40k/scripts/EngagementRangeVisual.gd` (likely already wired; just
    make it always-on for engaged units)

- [ ] **T30 — Charge max/expected dashed rings**
  - **Lock:** Charge  • **Doc:** §5
  - **Touches:** `40k/scripts/ChargeController.gd`, `ChargeTrajectoryPreview.gd`
  - **Change:** At charge declaration, draw dashed ring at 12" (max 2D6) and brighter
    dashed ring at 7" (expected). On roll, replace with actual distance ring.

- [ ] **T31 — Standalone ruler tool (R key) with public/private toggle**
  - **Lock:** BoardLayer  • **Doc:** §5
  - **Touches:** new `40k/scripts/RulerTool.gd`, `40k/scripts/Main.gd` (input)
  - **Change:** `R` enters ruler mode. Click + drag draws a line with inches label.
    Default public (broadcast in multiplayer); SHIFT-R for private. ESC exits.

## §6 LOS & cover (continued)

- [ ] **T32 — Move LOS Debug to held-key power-user mode**
  - **Lock:** BoardLayer  • **Doc:** §6
  - **Touches:** wherever the `LoS Debug (L)` toggle lives
  - **Change:** Currently a toggle button always visible in top bar. Demote to a
    held-key power-user mode (e.g. hold `L`); remove the persistent button or move
    it under a debug menu.

## §7 Selection / dice surfacing

- [ ] **T33 — Center-screen resolution surface (compact, non-blocking)**
  - **Lock:** Shooting + Fight  • **Doc:** §7
  - **Touches:** `40k/scripts/DiceRollVisual.gd` (or its container), shooting/fight
    resolution UI
  - **Change:** Resolution shows four animated columns Hits → Wounds → Saves → Damage
    in a compact center-screen surface that does NOT block the board (anchor at top
    center, ~40% screen width). SPACE skips animation.

- [ ] **T34 — Floating damage numbers on target tokens**
  - **Lock:** TokenLayer + Shooting  • **Doc:** §7
  - **Touches:** `40k/scripts/DamageFeedbackVisual.gd` (likely already exists)
  - **Change:** On wound application, float `-NW` (wounds) and `-N models` (model
    losses) over the target token; fade after 2s. Primary feedback; log becomes audit.

- [ ] **T35 — Persistent right-side roll log refinement**
  - **Lock:** HUD-Right  • **Doc:** §7
  - **Touches:** `40k/autoloads/DiceHistoryPanel.gd`
  - **Change:** Make the dice/roll log persistently visible on the right column.
    Format: timestamp · attacker → target · result. Auditable.

- [ ] **T36 — Explicit commit step on target selection (ENTER to roll)**
  - **Lock:** Shooting + Fight  • **Doc:** §7
  - **Change:** Target click highlights only. ENTER (or explicit Confirm button)
    triggers the resolution. Prevents misclick-fires.

## §8 Roster & panels (continued)

- [ ] **T37 — Left-edge vertical roster strip**
  - **Lock:** HUD-Left  • **Doc:** §8
  - **Touches:** `40k/scripts/ArmyPanel.gd` (or whatever renders the right-side roster
    today); move + redesign to left vertical strip
  - **Change:** Vertical card per unit: portrait (or silhouette from T15) + faction
    color + name + model-count badge + tiny wound chip. Scrollable >12 units. Click
    pans camera + selects; double-click opens datasheet (T39).

- [ ] **T38 — Filter chips above roster**
  - **Lock:** HUD-Left  • **Doc:** §8  • **Depends:** T37
  - **Change:** Chips `All / Can Act / Engaged / Below Half` filter the roster strip.

- [ ] **T39 — Datasheet modal on `i` key**
  - **Lock:** HUD-Right  • **Doc:** §8
  - **Touches:** new `40k/scenes/DatasheetModal.tscn`, its script
  - **Change:** `i` opens a Wahapedia-style full datasheet (M/T/Sv/W/Ld/OC plus all
    weapon profiles, keywords, abilities, lore). Read-only. ESC dismisses. Does NOT
    auto-open.

- [ ] **T40 — Prospective stat panel (recompute on enemy hover)**
  - **Lock:** HUD-Right  • **Doc:** §8  • **Depends:** T05
  - **Touches:** `40k/scripts/UnitStatsPanel.gd`
  - **Change:** When an enemy is hovered while a friendly unit is selected, recompute
    and display: BS after cover, S vs T comparison, AP vs Sv, expected wounds. Mirrors
    T05's tooltip but in a persistent panel for the selected unit, not a hover popup.

## §9 Color & motion (continued)

- [ ] **T41 — Separate faction vs. player-slot color throughout codebase**
  - **Lock:** UIConstants + multiple  • **Doc:** §9  • **Depends:** T08, T12
  - **Touches:** any script that currently reads "player color" — disambiguate every
    callsite into either faction (from army data) or slot (from `UIConstants`)
  - **Change:** Grep `player_color`, `team_color`, hex literals in UI code; replace
    with the explicit slot or faction lookup. Commit per file for review.

- [ ] **T42 — Striped pattern for semantic yellow**
  - **Lock:** UIConstants  • **Doc:** §9
  - **Touches:** `UIConstants.gd` `striped_pattern()` helper, anywhere semantic
    yellow is drawn
  - **Change:** Implement a 4px hatched/striped fill so semantic yellow is
    distinguishable from a faction yellow (Imperial Fists, Lamenters) by texture, not
    hue.

- [ ] **T43 — Audit and remove redundant orange highlights**
  - **Lock:** HUD-Top + HUD-Right + HUD-Left  • **Doc:** §9
  - **Change:** Grep for the current bright-orange "clickable" stylebox; reserve it
    for the single primary call-to-action per screen. All other buttons revert to
    the default chrome.

- [ ] **T44 — Motion budget enforcement**
  - **Lock:** Infra + multiple  • **Doc:** §9
  - **Change:** Audit tween durations. Cap: dice ≤1.5s (already SPACE-skippable in
    T33), token slides ≤0.4s/inch, overlay fades 150ms, active-unit pulse 2s loop.
    Add a `UIConstants.MOTION_*` block; replace ad-hoc duration literals.

- [ ] **T45 — Visual review pass + final design-guidelines compliance audit**
  - **Lock:** Infra  • **Doc:** all
  - **Change:** After T01–T44 complete, walk the design doc top-to-bottom. For each
    recommendation, verify a corresponding task closed it or document why deferred.
    Update the doc's "Status" header with completion summary. No code changes;
    documentation only.
