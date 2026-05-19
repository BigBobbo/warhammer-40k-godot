# Design Guidelines Implementation — task list

Each task implements one slice of `40k/docs/design_guidelines_2d_topdown.md`. Format:
small, atomic, individually validated, individually revertable, **falsifiable**.

## How to work this list

- Run interactively via `do-one-task` for the first 5 tasks to stabilize the template,
  then batch via `do-all-tasks` in supervised sessions.
- Every task carries:
  - **Acceptance — Tier A (machine):** bullets of `expect_*` / `execute_script` /
    pixel-diff assertions in the scenario. These gate `git commit`. If a Tier A bullet
    cannot be expressed in the scenario JSON, the task is rejected — design the change
    so the relevant state is observable.
  - **Acceptance — Tier B (visual checklist):** 3–5 yes/no items a human ticks during
    the visual review batch. Gates the `- [x]` mark in this file, NOT the commit.
- **No false-positive shortcuts:**
  - "Screenshot captured" is **never** acceptance on its own — the screenshot must
    be referenced by a pixel-diff assertion or paired with a property-level read.
  - "Node exists" / "child count == N" is **never** acceptance on its own — must be
    paired with a property assertion (modulate.a, color, position) proving the node
    actually contributes to the rendered frame.
  - "Looks correct" / "feels right" / "performant" never appear in Tier A.
- **Regression gate:** Tier A always includes
  `passing_scenarios_count >= _baseline.json.count`. The baseline is snapshotted in
  T02. A commit that drops the count fails — there is no "absolute exit 0" gate.
- **Parallelism:** tasks declare a `Lock:` tag. Two parallel sessions may run
  concurrently only on tasks with disjoint locks. Use `Agent` with
  `isolation: "worktree"` per session.

Locks in use:
- `UIConstants` — touches the color-slot autoload
- `Movement` — MovementController + MovementRangeVisual
- `Shooting` — ShootingController + dice surface
- `Charge` — ChargeController + Charge*Visual
- `Fight` — FightController + fight UI
- `HUD-Top` — top phase bar & action buttons
- `HUD-Right` — right column panels & modals→side conversions
- `HUD-Left` — game log & roster strip
- `TokenLayer` — TokenVisual & per-token chrome
- `BoardLayer` — terrain overlays, LOS lines, threat shading
- `Infra` — scenario harness, screenshot helper, pixel-diff

---

## Foundation (sequential — must complete before anything below)

- [ ] **T01 — UIConstants color slot autoload**
  - **Lock:** UIConstants  • **Doc:** §9  • **Depends:** —
  - **Touches:** new `40k/autoloads/UIConstants.gd`, `40k/project.godot` (autoload registration)
  - **Change:** Add an autoload exposing the strict slot table from the doc:
    `FRIENDLY_PLAYER_TEAL`, `ENEMY_PLAYER_MAGENTA`, `WARNING_ORANGE`, `CONFIRMED_GREEN`,
    `MARGINAL_YELLOW`, `INVALID_RED`, `NEUTRAL_UI_PALE_WHITE`. Faction colors stay
    per-army (read from army data). Provide `striped_pattern(color)` for the yellow
    semantic / faction-yellow collision case. Each constant exposed as a typed `Color`
    and as a named string slot via `slot_name(color: Color) -> String` for assertions.
  - **Scenario:** `tests/scenarios/visual/T01_uiconstants_present.json`
  - **Acceptance — Tier A (machine):**
    - `execute_script` returns: `UIConstants.FRIENDLY_PLAYER_TEAL` is a `Color` with
      `a == 1.0` and exact hex specified in doc §9 table.
    - Repeat for all 7 named slots; each `expect_action_result` returns `equals` on
      a deterministic hex string.
    - `execute_script`: `UIConstants.slot_name(UIConstants.WARNING_ORANGE) == "WARNING_ORANGE"`.
    - `execute_script`: `UIConstants.striped_pattern(Color.YELLOW)` returns a non-null
      `Texture2D` (or equivalent shader handle).
    - Regression: passing-scenario count ≥ `_baseline.json.count`.
  - **Acceptance — Tier B (visual checklist):**
    - [ ] Doc §9 table values match `UIConstants.gd` 1:1 (cross-check via diff).
    - [ ] `striped_pattern` output renders as visible stripes (eyeball one screenshot).
    - [ ] No autoload conflicts in `project.godot`.

- [ ] **T02 — Visual-scenario harness + pixel-diff + baseline snapshot**
  - **Lock:** Infra  • **Doc:** —  • **Depends:** —
  - **Touches:**
    - new `40k/tests/scenarios/visual/_schema.md`
    - new `40k/tests/scenarios/visual/_template.json`
    - new `40k/tests/scenarios/visual/_baseline.json` (snapshot of main's passing
      scenarios at fork point)
    - new `40k/tests/tools/pixel_diff.gd` (or `.py`) — compares two PNGs, returns
      JSON `{total_diff_pct, regions: {<name>: pct}}`
    - extension to `40k/tests/run_scenarios.sh` for visual scenarios
    - new section in `40k/tests/TESTING_METHODOLOGY.md` titled "Design-guidelines
      visual tasks"
  - **Change:**
    1. Snapshot the baseline: run `bash 40k/tests/run_scenarios.sh` on the current
       branch tip; capture the passing-scenario ID list and count to `_baseline.json`.
       Commit this file.
    2. Document the scenario convention: every T## task creates
       `tests/scenarios/visual/T##_<slug>.json` with mandatory steps:
       `screenshot label=T##_before` at start, `screenshot label=T##_after` at end,
       and ≥1 `expect_state` or `expect_action_result` clause that is falsifiable.
       Forbid scenarios that contain only screenshot steps.
    3. Build `pixel_diff.gd`: takes `before_path`, `after_path`, optional
       `regions: Array[Rect2i]` with names. Emits JSON to stdout.
    4. Extend `run_scenarios.sh`: when invoked on `tests/scenarios/visual/T##_*.json`:
       (a) copy captured screenshots to `40k/test_results/design_guidelines/T##/`,
       (b) run `pixel_diff` and write `diff_report.json` alongside,
       (c) compare passing-scenario count against `_baseline.json` — exit code 3 on
       regression (distinct from 1 for assertion failure, 2 for infra).
  - **Scenario:** `tests/scenarios/visual/T02_harness_self_check.json`
  - **Acceptance — Tier A (machine):**
    - `_baseline.json` exists and `len(passing) > 0`.
    - `bash 40k/tests/run_scenarios.sh tests/scenarios/visual/T02_harness_self_check.json`
      exits 0.
    - `pixel_diff` on two identical PNGs returns `total_diff_pct == 0.0`.
    - `pixel_diff` on a 100% black PNG vs 100% white PNG returns
      `total_diff_pct > 95.0`.
    - `run_scenarios.sh` exit code is 3 when passing-count < baseline (test by
      deliberately renaming one passing scenario before running, then restore).
    - `test_results/design_guidelines/T02/diff_report.json` is produced and parses
      as JSON.
  - **Acceptance — Tier B (visual checklist):**
    - [ ] `_schema.md` enumerates every required scenario step type with example.
    - [ ] `_template.json` runs end-to-end as a copy-paste starting point.
    - [ ] `TESTING_METHODOLOGY.md` gained a "Design-guidelines visual tasks" section.

## Top-10 quick wins (parallelizable after T02 if locks are disjoint)

- [ ] **T03 — Drag-ruler with budget coloring during movement**
  - **Lock:** Movement  • **Doc:** §5 quick-win #1  • **Depends:** T01, T02
  - **Touches:** `40k/scripts/MovementController.gd`, `40k/scripts/MovementRangeVisual.gd`
  - **Change:** While dragging a model, paint the path from start → cursor as colored
    segments. Use `CONFIRMED_GREEN` for ≤ M, `MARGINAL_YELLOW` for ≤ M+Advance,
    `INVALID_RED` beyond. Cumulative inches label follows cursor. SHIFT drops a
    waypoint; ENTER commits; ESC cancels. M and Advance sourced from RulesEngine.
    **Required new public state:** `MovementController.current_drag_segments :
    Array[Dictionary]` where each entry is `{from: Vector2, to: Vector2,
    color_slot: String, distance_inches: float}`. This is the testability hook.
  - **Scenario:** `tests/scenarios/visual/T03_drag_ruler.json` — load fixture in
    movement phase. `BEGIN_MODEL_DRAG`. Sequentially set cursor at three positions:
    (a) within Move, (b) within Move+Advance, (c) beyond. Screenshot at each.
  - **Acceptance — Tier A (machine):**
    - `expect_action_result success=true` for `BEGIN_MODEL_DRAG`.
    - At cursor position (a): `execute_script` returns
      `MovementController.current_drag_segments[-1].color_slot == "CONFIRMED_GREEN"`.
    - At cursor position (b): same property `== "MARGINAL_YELLOW"`.
    - At cursor position (c): same property `== "INVALID_RED"`.
    - Each `distance_inches` value within ±0.1" of the expected drag distance.
    - `pixel_diff` between screenshot (a) and (c) in the path region:
      `regions["drag_path"].diff_pct > 5.0` (path visibly changed).
    - `pixel_diff` between screenshot (a) and a static "before" of the same fixture
      with no drag: `regions["drag_path"].diff_pct > 2.0` (path is drawn).
    - Regression count ≥ baseline.
  - **Acceptance — Tier B (visual checklist):**
    - [ ] Green segments visible from origin to Move boundary.
    - [ ] Yellow segment between Move and Move+Advance boundaries.
    - [ ] Red segment beyond Move+Advance.
    - [ ] Inches label updates as cursor moves.
    - [ ] ESC removes the drag overlay cleanly.

- [ ] **T04 — Six-phase top-center bar with active highlight**
  - **Lock:** HUD-Top  • **Doc:** §4  • **Depends:** T01, T02
  - **Touches:** `40k/scenes/Main.tscn` (add `PhaseBar` PanelContainer), new
    `40k/scripts/PhaseBar.gd`, `40k/autoloads/PhaseManager.gd` (signal hook)
  - **Change:** Render six pills `Command → Movement → Shooting → Charge → Fight →
    Morale` along the top center. Active pill modulated by active player's slot
    color; completed pills modulate to `Color(0.5, 0.5, 0.5, 1.0)`; future pills
    disabled (`modulate.a == 0.4`). Each pill node named exactly `PhasePill_<NAME>`
    so tests can read it. Listen on `PhaseManager.phase_changed`.
  - **Scenario:** `tests/scenarios/visual/T04_phase_bar.json` — load fixture in
    Command phase, screenshot, advance to Movement, screenshot, advance to Shooting,
    screenshot.
  - **Acceptance — Tier A (machine):**
    - In Command screenshot: `execute_script` returns
      `get_node("/root/Main/PhaseBar/PhasePill_COMMAND").modulate == <active_color>`
      AND `get_node(".../PhasePill_MOVEMENT").modulate.a == 0.4`.
    - In Movement screenshot: `PhasePill_COMMAND.modulate` matches the dim grey
      tuple (within 0.05 per channel) AND `PhasePill_MOVEMENT.modulate == <active_color>`.
    - Same pattern verified for Shooting transition.
    - All six `PhasePill_<NAME>` nodes exist (via `get_node` non-null).
    - `pixel_diff` in the PhaseBar region between Command and Movement screenshots:
      `regions["phase_bar"].diff_pct > 3.0` (highlight actually moved on-screen).
    - Regression count ≥ baseline.
  - **Acceptance — Tier B (visual checklist):**
    - [ ] Six pills readable, labels not truncated.
    - [ ] Active pill is visually the brightest.
    - [ ] Completed pills are distinguishable from future pills.
    - [ ] No layout shift in the rest of the HUD when phase advances.

- [ ] **T05 — Hover-forecast tooltip for shooting**
  - **Lock:** Shooting  • **Doc:** §7  • **Depends:** T01, T02
  - **Touches:** `40k/scripts/ShootingController.gd`, new `40k/scripts/HoverForecast.gd`,
    `40k/autoloads/RulesEngine.gd` (add `preview_attack(shooter, target, weapon)`
    helper if not present)
  - **Change:** When a shooter is selected and the cursor hovers an enemy unit,
    render a tooltip near the cursor: weapon name → target name; attacks, BS, S vs
    T, AP, D; expected wounds. Math via `RulesEngine.preview_attack(...)` so
    modifiers (Oath of Moment, Heavy, cover) are reflected.
    **Required testability hook:** `ShootingController.current_hover_forecast :
    Dictionary` with keys `{weapon_id, target_id, bs, s, t, ap, d, expected_wounds}`,
    or `null` when no hover. Tooltip node named `HoverForecast`.
  - **Scenario:** `tests/scenarios/visual/T05_hover_forecast.json` — shooting
    fixture; `SELECT_SHOOTER`; set `ShootingController.test_hover_target_id` to a
    target with cover; screenshot.
  - **Acceptance — Tier A (machine):**
    - `expect_action_result success=true` for `SELECT_SHOOTER`.
    - `execute_script`: `ShootingController.current_hover_forecast != null`.
    - `execute_script`: `current_hover_forecast.bs == <expected_value_with_cover_applied>`
      (compute the expected BS from the fixture data — e.g., BS 3+ shooter behind
      light cover firing at non-INFANTRY = unchanged 3+; behind heavy cover at
      INFANTRY enemy = 4+).
    - `execute_script`: `current_hover_forecast.expected_wounds > 0`.
    - `get_node("HoverForecast").visible == true`.
    - `pixel_diff` in tooltip region vs a no-hover baseline screenshot:
      `regions["tooltip_area"].diff_pct > 4.0`.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B (visual checklist):**
    - [ ] Tooltip readable, not clipped by viewport edges.
    - [ ] Numbers update when hover moves between targets.
    - [ ] Cover icon / cover delta surfaced in the tooltip.
    - [ ] Tooltip disappears on hover-off.

- [ ] **T06 — Convert Weapon Order modal to side-anchored panel**
  - **Lock:** HUD-Right  • **Doc:** §3  • **Depends:** T01, T02
  - **Touches:** wherever the Weapon Order modal instantiates today
    (likely `ShootingController.gd` + a dialog scene)
  - **Change:** Convert centered modal to right-column panel. Board stays visible.
    ESC cancels. Keep existing "Start Sequence" action wiring. Panel node renamed
    `WeaponOrderPanel`; anchor `right` set; `mouse_filter` must NOT cover the board
    region.
  - **Scenario:** `tests/scenarios/visual/T06_weapon_order_panel.json` — shooting
    fixture with multi-weapon unit; `BEGIN_WEAPON_ORDER`; screenshot; assert state.
  - **Acceptance — Tier A (machine):**
    - `expect_action_result success=true` for `BEGIN_WEAPON_ORDER`.
    - `execute_script`: `get_node("WeaponOrderPanel").anchor_left >= 0.6` (panel
      lives in the right ~40% of the screen).
    - `execute_script`: `get_node("WeaponOrderPanel").get_rect()` does NOT intersect
      `get_node("BoardRoot").get_used_rect()` (assertion encoded as a helper).
    - `pixel_diff` between the new screenshot and the pre-T06 baseline of the same
      fixture in the **board region (left 60%)**: `regions["board_left"].diff_pct
      < 1.0` (board content unchanged) AND in the **right panel region**:
      `regions["right_panel"].diff_pct > 10.0` (panel content changed).
    - All existing weapon-order regression scenarios still pass.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B (visual checklist):**
    - [ ] Tokens at original positions visible while panel is open.
    - [ ] Panel has all controls the old modal had.
    - [ ] ESC dismisses without committing.
    - [ ] No layout overlap with the existing right-side phase controls.

- [ ] **T07 — Per-tile cover icons on terrain**
  - **Lock:** BoardLayer  • **Doc:** §6  • **Depends:** T01, T02
  - **Touches:** `40k/scripts/BoardVisual.gd` or new
    `40k/scripts/TerrainCoverOverlay.gd`, `40k/deployment_zones/` data files (read
    existing terrain definitions)
  - **Change:** For each terrain piece in the active layout, render a shield glyph
    at the polygon centroid showing `+1` / `+2` / `LB`. Each icon node named
    `TerrainCoverIcon_<terrain_id>`.
  - **Scenario:** `tests/scenarios/visual/T07_terrain_cover_icons.json` — load
    fixture with the default terrain layout; screenshot.
  - **Acceptance — Tier A (machine):**
    - `execute_script`: for each `terrain_id` in fixture data,
      `get_node("BoardRoot/TerrainCoverOverlay/TerrainCoverIcon_" + terrain_id)`
      is non-null AND its `position` is within 8px of the polygon centroid.
    - `execute_script`: each icon's `modulate.a >= 0.8` (actually visible).
    - `execute_script`: each icon's `Label` text matches the terrain's `cover_type`
      (`"+1"`, `"+2"`, `"LB"`).
    - `pixel_diff` between this screenshot and a baseline with overlay disabled:
      `total_diff_pct > 1.0` AND `regions["board"].diff_pct > 1.0`.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B (visual checklist):**
    - [ ] Every terrain piece has a visible cover icon.
    - [ ] Icons readable at zoom 1.0 and still recognizable at zoom 0.5.
    - [ ] Icons don't overlap tokens at default deployment positions.

- [ ] **T08 — Two-ring token (faction inner + player-slot outer)**
  - **Lock:** TokenLayer  • **Doc:** §2  • **Depends:** T01, T02
  - **Touches:** `40k/scripts/TokenVisual.gd`
  - **Change:** Replace single-color base ring with two concentric rings: inner =
    faction color (from army data), outer thin ring = player-slot color from
    `UIConstants`. Inner node named `FactionRing`, outer node named `SlotRing`.
  - **Scenario:** `tests/scenarios/visual/T08_two_ring_token.json` — load fixture
    with P1 Custodes + P2 Witchseekers; engagement-zoom screenshot.
  - **Acceptance — Tier A (machine):**
    - `execute_script`: any P1 Custodes token has
      `FactionRing.modulate == <custodes_gold_hex_from_army_data>` AND
      `SlotRing.modulate == UIConstants.FRIENDLY_PLAYER_TEAL`.
    - `execute_script`: any P2 Witchseekers token has
      `FactionRing.modulate == <witchseekers_blue_hex>` AND
      `SlotRing.modulate == UIConstants.ENEMY_PLAYER_MAGENTA`.
    - `execute_script`: `SlotRing.scale > FactionRing.scale` (outer larger).
    - `execute_script`: both rings have `modulate.a >= 0.9`.
    - `pixel_diff` between this engagement-zoom and the pre-T08 baseline of the
      same fixture in the **token region**: `regions["token_swatch"].diff_pct > 8.0`.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B (visual checklist):**
    - [ ] Two rings visually distinct (different hue and thickness).
    - [ ] Faction inner ring matches the army's chosen color.
    - [ ] Player-slot outer ring is the same color across all units of that player.
    - [ ] Rings do not occlude the central glyph/letter.

- [ ] **T09 — Exhaustion grayscale for acted units**
  - **Lock:** TokenLayer + HUD-Left  • **Doc:** §8  • **Depends:** T01, T02, T08
  - **Touches:** `40k/scripts/TokenVisual.gd`, `40k/scripts/ArmyPanel.gd`,
    `40k/phases/MovementPhase.gd` (and shooting/charge equivalents) — emit
    `unit_acted_in_phase(unit_id)` signal
  - **Change:** When a unit's "has acted this phase" flag flips true, set the
    token's modulate to `Color(0.6, 0.6, 0.6, 1.0)` and the roster card to a dimmer
    stylebox. Reset on phase end. Expose `TokenVisual.is_exhausted_this_phase:
    bool` for assertion.
  - **Scenario:** `tests/scenarios/visual/T09_exhaustion_grayscale.json` —
    movement-phase fixture; `END_UNIT_MOVE` for one unit; screenshot; advance phase;
    screenshot.
  - **Acceptance — Tier A (machine):**
    - `expect_action_result success=true` for `END_UNIT_MOVE`.
    - `execute_script` on acted unit's token: `modulate ==
      Color(0.6, 0.6, 0.6, 1.0)` (each channel within 0.02 tolerance) AND
      `is_exhausted_this_phase == true`.
    - `execute_script` on un-acted unit's token: `modulate == Color(1, 1, 1, 1)`
      AND `is_exhausted_this_phase == false`.
    - After phase advance: acted unit's `modulate` back to `Color(1, 1, 1, 1)`.
    - `pixel_diff` of acted-unit token region between screenshot 1 and 2:
      `regions["acted_token"].diff_pct > 15.0`.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B (visual checklist):**
    - [ ] Acted unit is clearly dimmer than un-acted.
    - [ ] Roster card mirrors the dim state.
    - [ ] Phase end resets both.
    - [ ] Color rings (T08) still distinguishable on dimmed token.

- [ ] **T10 — Held-key threat overlay (Tab)**
  - **Lock:** BoardLayer  • **Doc:** §6  • **Depends:** T01, T02
  - **Touches:** `40k/scripts/Main.gd` (input handling), new
    `40k/scripts/ThreatOverlay.gd`
  - **Change:** On `Tab` held, paint each enemy unit's shooting-range circle in
    `MARGINAL_YELLOW` at 15% alpha and 12" charge-threat ring in `INVALID_RED` at
    10% alpha. On key release, remove. Off by default. Expose
    `ThreatOverlay.active: bool` and `ThreatOverlay.rendered_rings: Array[Dictionary]`
    where each entry is `{unit_id, kind: "shoot"|"charge", color_slot, radius_px}`.
  - **Scenario:** `tests/scenarios/visual/T10_threat_overlay.json` — load fixture;
    screenshot (baseline); `simulate_key_press("Tab", hold=true)` (or set
    `ThreatOverlay.active = true` via execute_script for harness reliability);
    screenshot; release; screenshot.
  - **Acceptance — Tier A (machine):**
    - Baseline `ThreatOverlay.active == false` and `rendered_rings.is_empty()`.
    - Tab-held: `ThreatOverlay.active == true`.
    - Tab-held: `rendered_rings.size() == 2 * enemy_unit_count` (one shoot + one
      charge per enemy unit).
    - Tab-held: every entry where `kind == "shoot"` has `color_slot ==
      "MARGINAL_YELLOW"`; every `kind == "charge"` has `color_slot == "INVALID_RED"`.
    - After release: `ThreatOverlay.active == false`, `rendered_rings.is_empty()`.
    - `pixel_diff` baseline vs held: `total_diff_pct > 2.0`.
    - `pixel_diff` baseline vs released: `total_diff_pct < 0.5` (overlay cleanly
      removed).
    - Regression count ≥ baseline.
  - **Acceptance — Tier B (visual checklist):**
    - [ ] Yellow rings visible around every enemy unit.
    - [ ] Red rings (charge threat) larger than yellow (shooting range may be
          larger or smaller depending on weapon, but each ring distinct).
    - [ ] Released → board returns to pre-Tab state exactly.
    - [ ] No flicker during repeated Tab press/release.

- [ ] **T11 — LOS line tool**
  - **Lock:** BoardLayer  • **Doc:** §6  • **Depends:** T01, T02
  - **Touches:** `40k/scripts/ShootingController.gd`, new `40k/scripts/LOSLineVisual.gd`,
    reuse existing LOS math
  - **Change:** When shooter selected and cursor hovers a candidate target, draw a
    single line shooter-base → target-base. `CONFIRMED_GREEN` if clear,
    `MARGINAL_YELLOW` if obscured, `INVALID_RED` if blocked. Expose
    `LOSLineVisual.current_line : {from, to, color_slot, los_state}`.
  - **Scenario:** `tests/scenarios/visual/T11_los_line.json` — three sub-checks
    using a fixture with curated terrain:
    (a) clear LOS (open ground between shooter and target),
    (b) obscured LOS (light cover terrain between),
    (c) blocked LOS (blocking-LOS terrain between).
  - **Acceptance — Tier A (machine):**
    - (a): `LOSLineVisual.current_line.color_slot == "CONFIRMED_GREEN"` AND
      `los_state == "clear"`.
    - (b): `color_slot == "MARGINAL_YELLOW"` AND `los_state == "obscured"`.
    - (c): `color_slot == "INVALID_RED"` AND `los_state == "blocked"`.
    - `pixel_diff` in the line region between (a) and (b): `regions["los_line"]
      .diff_pct > 5.0`.
    - `pixel_diff` between (b) and (c): `regions["los_line"].diff_pct > 5.0`.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B (visual checklist):**
    - [ ] Three distinct colors in three screenshots.
    - [ ] Line endpoints anchored to base centers.
    - [ ] Line disappears on hover-off.

- [ ] **T12 — Refactor existing visual scripts to consume UIConstants**
  - **Lock:** UIConstants + all visual scripts (serial — blocks other visual streams)
  - **Doc:** §9  • **Depends:** T01
  - **Touches:** `40k/scripts/MovementRangeVisual.gd`, `EngagementRangeVisual.gd`,
    `CoherencyCircleVisual.gd`, `ChargeTrajectoryPreview.gd`,
    `DeepStrikeExclusionVisual.gd`, `DamageFeedbackVisual.gd`, `ChargeArrowVisual.gd`,
    `DeploymentZoneVisual.gd`, `AIMovementPathVisual.gd`
  - **Change:** Replace every ad-hoc `Color(...)` literal with the corresponding
    `UIConstants.<SLOT>`. Document each substitution in commit body (file:line
    old=hex new=SLOT_NAME).
  - **Scenario:** `tests/scenarios/visual/T12_color_audit.json` — load
    engagement-zoom fixture; full-board fixture; screenshot each.
  - **Acceptance — Tier A (machine):**
    - `execute_script`: for each named visual script class, every Color property
      reachable via inspection is either a faction color (from army data) or
      `== UIConstants.<some_slot>`. Use a grep helper that walks
      `MovementRangeVisual.get_property_list()` etc. and asserts no
      `Color(0.5, 0.5, 0.5, 0.5)`-style literals remain.
    - `grep -rn "Color(" 40k/scripts/*Visual.gd` returns 0 matches (or matches only
      inside comments / debug-only blocks documented in the commit).
    - `pixel_diff` between pre-T12 and post-T12 screenshots of the same fixtures:
      `total_diff_pct < 2.0` (intentional only — colors should look equivalent unless
      a substitution was wrong, in which case `total_diff_pct` will spike and we'll
      catch it).
    - Regression count ≥ baseline.
  - **Acceptance — Tier B (visual checklist):**
    - [ ] All visible overlays look perceptually identical to pre-refactor.
    - [ ] No new color appearing where one didn't exist.
    - [ ] Commit body lists every substitution.

## §1 Camera

- [ ] **T13 — Fit-board keybind (F)**
  - **Lock:** HUD-Top  • **Doc:** §1  • **Depends:** T02
  - **Touches:** `40k/scripts/Main.gd` (input)
  - **Change:** `F` keybind: animate Camera2D so the playable board fills the
    viewport, with 32px margin. Expose `Main.last_camera_fit_action : String`
    (e.g. `"board"`).
  - **Scenario:** `tests/scenarios/visual/T13_fit_board.json` — pan camera to a
    deliberate offset via `execute_script` (e.g. `Camera2D.position = Vector2(0, 0)`,
    zoom 0.3); press `F`; screenshot.
  - **Acceptance — Tier A (machine):**
    - After `F`: `Camera2D.position` is within 8px of board-center, and `zoom` is
      within 0.02 of the computed fit-zoom for the current viewport size.
    - `Main.last_camera_fit_action == "board"`.
    - `pixel_diff` between pre-F and post-F screenshots: `total_diff_pct > 10.0`.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] Whole board visible.
    - [ ] Margin uniform on all four sides.
    - [ ] Animation smooth (no jump).

- [ ] **T14 — Fit-selection keybind (Shift+F)**
  - **Lock:** HUD-Top  • **Doc:** §1  • **Depends:** T02
  - **Touches:** `40k/scripts/Main.gd`
  - **Change:** `Shift+F`: zoom + center on selected unit (bounding box for
    multi-model). Set `Main.last_camera_fit_action = "selection"`.
  - **Scenario:** `tests/scenarios/visual/T14_fit_selection.json` — select a unit
    near the far edge; pan camera to the opposite edge; press `Shift+F`; screenshot.
  - **Acceptance — Tier A (machine):**
    - After `Shift+F`: `Camera2D.position` is within 10px of the selected unit's
      centroid.
    - `Main.last_camera_fit_action == "selection"`.
    - `pixel_diff` between pre and post: `total_diff_pct > 8.0`.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] Selected unit centered.
    - [ ] Other units in frame if they fit; never crops the selection.

## §2 Tokens (continued)

- [ ] **T15 — Unit-type silhouette glyphs**
  - **Lock:** TokenLayer  • **Doc:** §2  • **Depends:** T08
  - **Touches:** `40k/scripts/TokenVisual.gd`, new
    `40k/assets/icons/unit_silhouettes/{infantry,tank,walker,beast,character,aircraft,mounted}.svg`
  - **Change:** Replace centered letter with a high-contrast silhouette glyph
    keyed off the unit's category. Letter label moves under the base. Expose
    `TokenVisual.silhouette_category : String`.
  - **Scenario:** `tests/scenarios/visual/T15_silhouettes.json` — fixture with
    mixed unit types; screenshot.
  - **Acceptance — Tier A (machine):**
    - For each unit on the board: `execute_script` returns the token's
      `silhouette_category` matches the expected mapping for that unit's keywords.
      E.g. an `INFANTRY` Intercessor token returns `"infantry"`; a `VEHICLE` Caladius
      returns `"tank"`.
    - `get_node("Silhouette").texture != null` for every token.
    - `pixel_diff` between the token-center region of pre-T15 (letter) vs post-T15
      (silhouette) on the same token: `regions["token_center"].diff_pct > 25.0`.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] Silhouettes recognizable at zoom 1.0.
    - [ ] Silhouettes still recognizable at zoom 0.5 (32px).
    - [ ] Letter labels visible under the base.

- [ ] **T16 — Auto-hide token labels below zoom threshold**
  - **Lock:** TokenLayer  • **Doc:** §2  • **Depends:** T15
  - **Touches:** `40k/scripts/TokenVisual.gd`
  - **Change:** When camera zoom falls below 0.6, set every token's label
    `visible = false`. Restore at zoom ≥ 0.6.
  - **Scenario:** `tests/scenarios/visual/T16_label_zoom_hide.json` — set zoom 0.5;
    screenshot; set zoom 1.0; screenshot.
  - **Acceptance — Tier A (machine):**
    - At zoom 0.5: `execute_script` returns
      `get_node("TokenLayer").get_child(0).get_node("Label").visible == false` for
      every child.
    - At zoom 1.0: same path returns `visible == true`.
    - `pixel_diff` of token-label region across the two screenshots:
      `regions["label_strip"].diff_pct > 10.0`.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] Labels absent at 0.5.
    - [ ] Labels back at 1.0.
    - [ ] No flicker as zoom crosses threshold.

- [ ] **T17 — Cap status icons at 3 with overflow chip**
  - **Lock:** TokenLayer  • **Doc:** §2
  - **Touches:** `40k/scripts/TokenVisual.gd`
  - **Change:** Status icons in three fixed slots (TL army, TR phase, BR special).
    >3 active: render highest-priority per slot + `+N` chip at BL that expands on
    hover. Expose `TokenVisual.visible_status_icon_count : int` and
    `overflow_chip_count : int`.
  - **Scenario:** `tests/scenarios/visual/T17_status_overflow.json` — apply 5
    statuses to a test unit via `execute_script` setting flags; screenshot.
  - **Acceptance — Tier A (machine):**
    - `execute_script`: `visible_status_icon_count == 3` AND
      `overflow_chip_count == 2`.
    - `execute_script`: TL/TR/BR icon nodes all have `visible == true`.
    - `execute_script`: BL chip node `visible == true` AND its Label text matches
      `"+2"`.
    - `pixel_diff` token region: `regions["token"].diff_pct > 5.0` vs pre-T17 baseline.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] Exactly 3 status icons + 1 chip visible.
    - [ ] Hover expands chip to show the hidden statuses.

- [ ] **T18 — Wound chip on base edge (replace HP bar)**
  - **Lock:** TokenLayer  • **Doc:** §2
  - **Touches:** `40k/scripts/TokenVisual.gd`
  - **Change:** Multi-wound models: small `W/Wmax` numeric chip at base edge.
    Single-wound: no chip. Expose `TokenVisual.wound_chip_text : String` (`""`
    when hidden).
  - **Scenario:** `tests/scenarios/visual/T18_wound_chip.json` — load fixture with
    a damaged multi-wound unit + a 1-wound unit.
  - **Acceptance — Tier A (machine):**
    - Multi-wound token: `wound_chip_text == "<current>/<max>"` and chip node
      `visible == true`.
    - Single-wound token: `wound_chip_text == ""` and chip node `visible == false`.
    - `pixel_diff` of HP-bar region (pre-T18 had a bar): `regions["hp_bar_area"]
      .diff_pct > 8.0`.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] Chip readable at zoom 1.0.
    - [ ] Single-wound models truly have nothing in that slot.

- [ ] **T19 — Active-unit pulsed ring**
  - **Lock:** TokenLayer  • **Doc:** §2
  - **Touches:** `40k/scripts/TokenVisual.gd`
  - **Change:** Active actor's outer slot ring pulses at 2s loop, low amplitude
    (alpha 0.7 → 1.0 → 0.7). Expose `TokenVisual.is_pulsing : bool`.
  - **Scenario:** `tests/scenarios/visual/T19_active_pulse.json` — select unit;
    capture two screenshots ~1s apart.
  - **Acceptance — Tier A (machine):**
    - `is_pulsing == true` for selected; `false` for others.
    - `execute_script` reads ring alpha at t=0 and t=1.0s: |alpha_t1 - alpha_t0| > 0.1.
    - `pixel_diff` of active token's ring region between t=0 and t=1: `regions[
      "active_ring"].diff_pct > 2.0`.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] Pulse perceptible but not distracting.
    - [ ] Only the active unit pulses.

## §3 Modals → side panels

- [ ] **T20 — Convert Epic Challenge modal to side panel**
  - **Lock:** HUD-Right  • **Doc:** §3
  - **Touches:** Epic Challenge dialog script + scene
  - **Change:** Side-anchored. Board visible. One-line effect preview.
  - **Scenario:** `tests/scenarios/visual/T20_epic_challenge_panel.json` — reuse
    `co_fixture_co_offer` save; open dialog; screenshot.
  - **Acceptance — Tier A (machine):**
    - `get_node("EpicChallengePanel").anchor_left >= 0.6`.
    - Panel rect does NOT intersect `BoardRoot` rect.
    - `pixel_diff` board region (left 60%) vs pre-T20 baseline of same fixture:
      `regions["board_left"].diff_pct < 1.0`.
    - `pixel_diff` right panel region: `regions["right_panel"].diff_pct > 8.0`.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] Board fully visible during decision.
    - [ ] All controls present (Use, Decline).
    - [ ] ESC dismisses.

- [ ] **T21 — Convert Wound Allocation overlay to side panel**
  - **Lock:** HUD-Right  • **Doc:** §3
  - **Touches:** `40k/scenes/WoundAllocationOverlay.tscn` + script
  - **Change:** Side-anchored. Board visible.
  - **Scenario:** `tests/scenarios/visual/T21_wound_panel.json` — drive a shooting
    resolution into wound-allocation; screenshot.
  - **Acceptance — Tier A (machine):**
    - `WoundAllocationPanel.anchor_left >= 0.6`.
    - Rect does NOT intersect BoardRoot.
    - `pixel_diff` board region vs pre-T21 baseline: `< 1.0`.
    - `pixel_diff` right panel region: `> 8.0`.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] Affected target tokens visible during allocation.
    - [ ] Allocation buttons functional.

- [ ] **T22 — Auto-zoom-to-fit on in-tactical decision opens**
  - **Lock:** HUD-Right + HUD-Top  • **Doc:** §3  • **Depends:** T13, T14
  - **Touches:** shared helper invoked by each side-panel opener
  - **Change:** When a side panel opens for an in-tactical decision, camera
    animates to fit-bounds of affected tokens. Expose
    `Main.last_camera_fit_action == "decision"` after.
  - **Scenario:** `tests/scenarios/visual/T22_auto_zoom_decision.json` — pan camera
    off; open Weapon Order; assert camera moved.
  - **Acceptance — Tier A (machine):**
    - After dialog open: `Camera2D.position` within 16px of centroid of (shooter +
      its targets).
    - `Main.last_camera_fit_action == "decision"`.
    - `pixel_diff` of full frame vs pre-open: `total_diff_pct > 5.0` (camera moved).
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] Shooter and at least one target visible after auto-zoom.
    - [ ] No camera jitter.

- [ ] **T23 — Canonical End-Phase button placement bottom-right**
  - **Lock:** HUD-Top + HUD-Right  • **Doc:** §3
  - **Touches:** every phase-controls panel script + scene
  - **Change:** All "End Phase" / "End <Phase> Phase" buttons sit at the same
    bottom-right pixel position. Audit current placements; document drift in commit.
    Each button must have node name `EndPhaseButton`.
  - **Scenario:** `tests/scenarios/visual/T23_end_phase_position.json` — load
    fixtures in each of the six phases; for each, capture the button's
    global_position.
  - **Acceptance — Tier A (machine):**
    - For all six phases: `get_node(".../EndPhaseButton").global_position` is within
      4px of a single reference value `(viewport.size.x - 200, viewport.size.y - 60)`
      (or whatever bottom-right anchor is chosen — documented in commit).
    - No phase has a missing `EndPhaseButton` node.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] Button at same position across all phases (eyeball overlay).
    - [ ] Button label clear in each phase.

## §4 Phase signaling (continued)

- [ ] **T24 — Sub-state breadcrumb under active phase pill**
  - **Lock:** HUD-Top  • **Doc:** §4  • **Depends:** T04
  - **Touches:** `40k/scripts/PhaseBar.gd`, each Phase autoload to expose
    `current_substate_index : int` and `substates : Array[String]`
  - **Change:** Beneath active pill, render the substate row for that phase. Light
    each crumb as it becomes current.
  - **Scenario:** `tests/scenarios/visual/T24_substate_breadcrumb.json` —
    shooting-phase fixture; advance through substates via dispatched actions;
    screenshot at each.
  - **Acceptance — Tier A (machine):**
    - For each substate transition: `ShootingPhase.current_substate_index`
      increments AND the corresponding breadcrumb node's `modulate ==
      <active_color>` (UIConstants slot).
    - Previous breadcrumb's `modulate == <dim_grey>`.
    - `pixel_diff` breadcrumb region across two substates: `regions[
      "breadcrumb"].diff_pct > 4.0`.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] Crumbs labeled clearly (Select Unit / Select Target / etc.).
    - [ ] Active crumb visually distinct from completed and future.

- [ ] **T25 — Active-player edge tint**
  - **Lock:** HUD-Top  • **Doc:** §4
  - **Touches:** `40k/scenes/Main.tscn` (new `EdgeTint` ColorRect or Frame),
    `40k/scripts/Main.gd`
  - **Change:** Outer 4px of play area tinted in active player's slot color.
    Listens to `PhaseManager.active_player_changed`.
  - **Scenario:** `tests/scenarios/visual/T25_edge_tint.json` — load fixture with
    P1 active; screenshot; switch to P2 active; screenshot.
  - **Acceptance — Tier A (machine):**
    - P1 active: `get_node("EdgeTint").modulate ==
      UIConstants.FRIENDLY_PLAYER_TEAL`.
    - P2 active: same node's modulate `== UIConstants.ENEMY_PLAYER_MAGENTA`.
    - `EdgeTint.size.x == viewport.size.x` (covers full width).
    - `pixel_diff` outer 4px frame between P1 and P2 screenshots: `regions[
      "edge"].diff_pct > 30.0`.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] Edge clearly visible at top, bottom, both sides.
    - [ ] Doesn't occlude tokens at the edge.

- [ ] **T26 — Phase pill click affordance for past/future**
  - **Lock:** HUD-Top  • **Doc:** §4  • **Depends:** T04
  - **Change:** Past pills: click inert; tooltip "completed". Future pills:
    tooltip "resolve current phase first". Expose
    `PhaseBar.last_pill_click_result : String`.
  - **Scenario:** `tests/scenarios/visual/T26_phase_pill_clicks.json` — load
    Movement-phase fixture; click past pill (Command); click future pill
    (Shooting); assert.
  - **Acceptance — Tier A (machine):**
    - After past click: `PhaseBar.last_pill_click_result == "past_inert"`.
    - After future click: `last_pill_click_result == "future_blocked"`.
    - `PhaseManager.current_phase` unchanged in both cases.
    - Tooltip nodes appear and have expected text content (read via
      `execute_script`).
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] Tooltips readable.
    - [ ] No accidental phase change.

- [ ] **T27 — Refactor End-Phase button to canonical position**
  - **Lock:** HUD-Right  • **Doc:** §4  • **Depends:** T23
  - **Change:** Implementation of the T23 audit findings.
  - **Acceptance — Tier A:** identical to T23.

## §5 Movement & range (continued)

- [ ] **T28 — Two-layer movement range shading**
  - **Lock:** Movement  • **Doc:** §5  • **Depends:** T03
  - **Touches:** `40k/scripts/MovementRangeVisual.gd`
  - **Change:** Solid fill within Move at 12% alpha; thin outline ring at
    Move + selected-weapon-range. Weapon selector switches outer ring. Expose
    `MovementRangeVisual.inner_fill_radius_px` and `outer_outline_radius_px`.
  - **Scenario:** `tests/scenarios/visual/T28_two_layer_range.json` — select unit;
    screenshot; switch weapon; screenshot.
  - **Acceptance — Tier A (machine):**
    - `inner_fill_radius_px` equals (Move inches × pixels_per_inch) within 1px.
    - `outer_outline_radius_px` equals ((Move + selected weapon range) × pixels_per_inch)
      within 1px.
    - Switching weapon changes `outer_outline_radius_px` to the new value.
    - `pixel_diff` outline region between two weapons: `regions["outer_ring"]
      .diff_pct > 3.0`.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] Inner fill visibly translucent.
    - [ ] Outer outline visibly thin.
    - [ ] Both centered on selected unit.

- [ ] **T29 — Persistent engagement ring on engaged units**
  - **Lock:** Movement  • **Doc:** §5
  - **Touches:** `40k/scripts/EngagementRangeVisual.gd`
  - **Change:** Always-on (not just when relevant action selected) for any unit
    in engagement range of an enemy. Expose
    `EngagementRangeVisual.is_persistent : bool`.
  - **Scenario:** `tests/scenarios/visual/T29_persistent_engagement.json` — load
    `co_fixture_engagement_zoom` save; idle screenshot (no selection).
  - **Acceptance — Tier A (machine):**
    - With no unit selected: every engaged unit's
      `EngagementRangeVisual.visible == true` AND `is_persistent == true`.
    - Non-engaged units' EngagementRangeVisual `visible == false`.
    - `pixel_diff` between this and pre-T29 baseline (where rings only show on
      select): `total_diff_pct > 2.0` AND specifically in engaged-units region.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] Engaged units have a visible faint ring at idle.
    - [ ] Non-engaged units have no ring at idle.

- [ ] **T30 — Charge max/expected dashed rings**
  - **Lock:** Charge  • **Doc:** §5
  - **Touches:** `40k/scripts/ChargeController.gd`,
    `40k/scripts/ChargeTrajectoryPreview.gd`
  - **Change:** At charge declaration: dashed ring at 12" (max 2D6) AND brighter
    dashed ring at 7" (expected). On roll, replace with actual-distance solid ring.
    Expose `ChargeTrajectoryPreview.rings : Array[Dictionary]` with `{radius_px,
    label, style}`.
  - **Scenario:** `tests/scenarios/visual/T30_charge_dashed_rings.json` — load
    charge-phase fixture; declare charge; screenshot; roll; screenshot.
  - **Acceptance — Tier A (machine):**
    - After declare: `rings.size() == 2`; one entry has `label == "max"` and
      `radius_px == 12*ppi±1`; another `label == "expected"` and `radius_px == 7*ppi±1`.
    - Each entry's `style == "dashed"`.
    - After roll: `rings.size() == 1`; entry has `style == "solid"` and `radius_px
      == <rolled_distance>*ppi±1`.
    - `pixel_diff` ring region pre/post-roll: `regions["charge_ring"].diff_pct > 8.0`.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] Two dashed rings clearly visible at declare.
    - [ ] One solid ring after roll, sized to the result.

- [ ] **T31 — Standalone ruler tool (R) with public/private toggle**
  - **Lock:** BoardLayer  • **Doc:** §5
  - **Touches:** new `40k/scripts/RulerTool.gd`, `40k/scripts/Main.gd` (input)
  - **Change:** `R` enters ruler mode. Click + drag draws a line with inches
    label. Default public (broadcast in multiplayer); `Shift+R` for private. ESC
    exits. Expose `RulerTool.active : bool`, `RulerTool.current_line :
    {from, to, distance_inches}`, `RulerTool.is_private : bool`.
  - **Scenario:** `tests/scenarios/visual/T31_ruler.json` — press `R`; draw line
    between two known board positions; screenshot.
  - **Acceptance — Tier A (machine):**
    - `RulerTool.active == true` after `R`.
    - `RulerTool.current_line.distance_inches` matches the geometric distance
      between the two endpoints (within 0.1").
    - `RulerTool.is_private == false` (default public).
    - After `Shift+R`: `is_private == true`.
    - ESC: `RulerTool.active == false`.
    - `pixel_diff` line region between idle and ruler-active: `regions["ruler"]
      .diff_pct > 1.0`.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] Distance label readable and accurate.
    - [ ] Public/private visually distinct (e.g. dashed vs solid).

## §6 LOS & cover (continued)

- [ ] **T32 — Move LOS Debug to held-key power-user mode**
  - **Lock:** BoardLayer  • **Doc:** §6
  - **Touches:** wherever the `LoS Debug (L)` toggle lives
  - **Change:** Demote from always-visible top-bar toggle to held-key (hold `L`)
    debug mode. Expose `LOSDebugOverlay.active : bool` and remove the persistent
    button (or move to a debug submenu).
  - **Scenario:** `tests/scenarios/visual/T32_los_debug_held.json` — idle
    screenshot; hold `L`; screenshot; release; screenshot.
  - **Acceptance — Tier A (machine):**
    - Idle: `LOSDebugOverlay.active == false`.
    - Held: `LOSDebugOverlay.active == true` AND overlay visible (diff > 1%).
    - Released: `LOSDebugOverlay.active == false` AND `pixel_diff` vs idle < 0.5%.
    - The persistent `LoSDebugToggle` button node is removed from `Main.tscn`
      (assert `get_node_or_null(...) == null`).
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] Top bar no longer shows the persistent toggle.
    - [ ] Held-key works in every phase.

## §7 Selection / dice surfacing

- [ ] **T33 — Center-screen resolution surface (compact, non-blocking)**
  - **Lock:** Shooting + Fight  • **Doc:** §7
  - **Touches:** `40k/scripts/DiceRollVisual.gd`, shooting/fight resolution UI
  - **Change:** Four animated columns Hits → Wounds → Saves → Damage in a compact
    surface anchored top-center, ≤40% screen width. Does NOT block board. SPACE
    skips. Expose `DiceRollVisual.is_skippable_with_space : bool`,
    `DiceRollVisual.columns : Array`.
  - **Scenario:** `tests/scenarios/visual/T33_resolution_surface.json` — drive a
    shooting resolution; screenshot during animation; SPACE; screenshot.
  - **Acceptance — Tier A (machine):**
    - During animation: `DiceRollVisual.visible == true`; surface anchor_top < 0.1
      (top of screen); surface width < viewport.size.x * 0.45.
    - Board rect NOT intersected by surface rect.
    - SPACE press: `DiceRollVisual.visible == false` within 100ms.
    - `columns.size() == 4` and each column has a final value.
    - `pixel_diff` board region while surface is open vs idle baseline:
      `regions["board"].diff_pct < 1.0` (board unchanged).
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] All four columns animate.
    - [ ] SPACE skips cleanly.
    - [ ] Board visible during resolution.

- [ ] **T34 — Floating damage numbers on target tokens**
  - **Lock:** TokenLayer + Shooting  • **Doc:** §7
  - **Touches:** `40k/scripts/DamageFeedbackVisual.gd`
  - **Change:** On wound application: `-NW` and `-N models` float over target,
    fade after 2s. Expose `DamageFeedbackVisual.active_floats : Array[Dictionary]`.
  - **Scenario:** `tests/scenarios/visual/T34_floating_damage.json` — resolve a
    shooting attack with known wounds; screenshot mid-float; screenshot at
    t=2.5s (post-fade).
  - **Acceptance — Tier A (machine):**
    - Mid-float: `active_floats.size() == 2` (wounds float + model-losses float).
    - Each float has `text` matching `"-<N>W"` or `"-<N> models"`.
    - Each float's `position` is within 64px of the target token center.
    - Post-fade: `active_floats.is_empty()`.
    - `pixel_diff` target region mid-float vs pre-attack: `regions["target"]
      .diff_pct > 3.0`.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] Numbers readable.
    - [ ] Fade timing feels right (not too fast/slow).

- [ ] **T35 — Persistent right-side roll log**
  - **Lock:** HUD-Right  • **Doc:** §7
  - **Touches:** `40k/autoloads/DiceHistoryPanel.gd`
  - **Change:** Make persistently visible on right column. Format:
    `<timestamp> · <attacker> → <target> · <result>`. Expose
    `DiceHistoryPanel.entries : Array[Dictionary]`.
  - **Scenario:** `tests/scenarios/visual/T35_roll_log.json` — drive two
    resolutions; assert log entries.
  - **Acceptance — Tier A (machine):**
    - `DiceHistoryPanel.visible == true` at idle (post-load).
    - After two resolutions: `entries.size() == 2`.
    - Each entry has keys `{timestamp, attacker, target, result}` all non-null.
    - `pixel_diff` log region after resolutions vs at idle: `regions["log"]
      .diff_pct > 5.0`.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] Entries readable.
    - [ ] Auto-scrolls to newest.

- [ ] **T36 — Explicit commit step on target selection (ENTER to roll)**
  - **Lock:** Shooting + Fight  • **Doc:** §7
  - **Change:** Click on enemy = highlight as target. ENTER (or explicit Confirm
    button) triggers resolution. Expose
    `ShootingController.pending_targets : Array` and `targets_committed : bool`.
  - **Scenario:** `tests/scenarios/visual/T36_explicit_commit.json` — select
    shooter; click target (should NOT fire); assert pending; ENTER; assert fired.
  - **Acceptance — Tier A (machine):**
    - After target click: `pending_targets.size() >= 1` AND
      `targets_committed == false` AND no dice rolled (state unchanged on RulesEngine).
    - After ENTER: `targets_committed == true` AND resolution started
      (e.g. `DiceRollVisual.visible == true` OR a new `DiceHistoryPanel.entries` entry).
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] Click-only does nothing destructive.
    - [ ] ENTER (or Confirm button) fires the attack.

## §8 Roster & panels (continued)

- [ ] **T37 — Left-edge vertical roster strip**
  - **Lock:** HUD-Left  • **Doc:** §8
  - **Touches:** `40k/scripts/ArmyPanel.gd` (or whatever renders the roster); move
    + redesign to left vertical strip
  - **Change:** Vertical card per unit: silhouette (T15) + faction color + name +
    model-count badge + wound chip. Scrollable. Click pans + selects;
    double-click opens datasheet (T39). Each card node named
    `UnitCard_<unit_id>`.
  - **Scenario:** `tests/scenarios/visual/T37_roster_strip.json` — load fixture
    with N units; screenshot; click one card; assert camera moved + unit selected.
  - **Acceptance — Tier A (machine):**
    - Strip rect: `anchor_right <= 0.2` (lives in left ~20% of screen).
    - For each unit_id in fixture, `get_node("LeftRoster/UnitCard_" + unit_id)`
      is non-null.
    - After click on a card: `Main.selected_unit_id == <that_unit_id>` AND
      `Main.last_camera_fit_action == "selection"` (T14 hook).
    - `pixel_diff` left strip region vs pre-T37 (where roster was right-side):
      `regions["left_strip"].diff_pct > 20.0`.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] All units listed.
    - [ ] Cards readable; nothing truncated.
    - [ ] Click + double-click work as specified.

- [ ] **T38 — Filter chips above roster**
  - **Lock:** HUD-Left  • **Doc:** §8  • **Depends:** T37
  - **Change:** Chips `All / Can Act / Engaged / Below Half`. Expose
    `LeftRoster.active_filter : String` and `LeftRoster.visible_unit_ids : Array`.
  - **Scenario:** `tests/scenarios/visual/T38_filter_chips.json` — fixture with
    mixed unit states; click each chip; assert filtered count.
  - **Acceptance — Tier A (machine):**
    - For "All": `visible_unit_ids.size() == total_units`.
    - For "Can Act": `visible_unit_ids.size() == unacted_unit_count`.
    - For "Engaged": `visible_unit_ids == engaged_unit_ids` (set equality).
    - For "Below Half": all entries' current wounds < max/2.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] Filter visibly reduces card count.

- [ ] **T39 — Datasheet modal on `i` key**
  - **Lock:** HUD-Right  • **Doc:** §8
  - **Touches:** new `40k/scenes/DatasheetModal.tscn` + script
  - **Change:** `i` opens full datasheet (M/T/Sv/W/Ld/OC + weapon profiles +
    keywords + abilities). Read-only. ESC dismisses. Does NOT auto-open.
  - **Scenario:** `tests/scenarios/visual/T39_datasheet.json` — select unit;
    press `i`; screenshot; assert; ESC; assert dismissed.
  - **Acceptance — Tier A (machine):**
    - Before `i`: `get_node_or_null("DatasheetModal") == null` OR
      `.visible == false`.
    - After `i`: `DatasheetModal.visible == true` AND its labels include the
      unit's M, T, Sv, W, Ld, OC values from `GameState`.
    - After ESC: `DatasheetModal.visible == false`.
    - At no point during normal phase progression does the modal auto-open
      (verified by running a non-T39 scenario like T04 and asserting
      `DatasheetModal.visible == false` throughout).
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] All datasheet sections present (stats, weapons, keywords, abilities).
    - [ ] Readable; not clipped.

- [ ] **T40 — Prospective stat panel (recompute on enemy hover)**
  - **Lock:** HUD-Right  • **Doc:** §8  • **Depends:** T05
  - **Touches:** `40k/scripts/UnitStatsPanel.gd`
  - **Change:** When enemy hovered while friendly selected, panel recomputes and
    shows modified BS after cover, S-vs-T comparison, AP vs Sv, expected wounds.
    Expose `UnitStatsPanel.prospective_target_id : String` and
    `UnitStatsPanel.displayed_bs : int`.
  - **Scenario:** `tests/scenarios/visual/T40_prospective_panel.json` — select
    friendly with BS 3+; hover enemy with no cover; assert panel shows 3+; hover
    same enemy after enabling cover; assert panel shows 4+.
  - **Acceptance — Tier A (machine):**
    - No-cover hover: `UnitStatsPanel.displayed_bs == 3`.
    - In-cover hover: `displayed_bs == 4`.
    - `UnitStatsPanel.prospective_target_id` matches the hovered enemy's id.
    - `pixel_diff` panel region between two hovers: `regions["stat_panel"]
      .diff_pct > 2.0`.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] Panel numbers update on hover.
    - [ ] Modifiers (cover delta) clearly indicated.

## §9 Color & motion (continued)

- [ ] **T41 — Separate faction vs. player-slot color throughout codebase**
  - **Lock:** UIConstants + multiple  • **Doc:** §9  • **Depends:** T08, T12
  - **Touches:** every script reading "player color" — disambiguate every callsite
  - **Change:** Grep `player_color`, `team_color`, hex literals in UI code; replace
    with explicit slot or faction lookup. Commit per file.
  - **Acceptance — Tier A (machine):**
    - `grep -rn 'player_color\|team_color' 40k/scripts 40k/scenes` returns 0 lines
      (or only inside this task's documented exceptions list).
    - `execute_script`: for each test fixture, `Player1.faction_color !=
      Player1.slot_color` is structurally enforceable (two distinct lookups).
    - All existing scenarios that previously passed still pass.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] Codebase-wide audit committed.
    - [ ] No regressions when running each player as a different faction palette.

- [ ] **T42 — Striped pattern for semantic yellow**
  - **Lock:** UIConstants  • **Doc:** §9
  - **Touches:** `UIConstants.gd` `striped_pattern()`, every site drawing semantic
    yellow
  - **Change:** Implement 4px hatched fill for semantic yellow so it's
    distinguishable from a faction yellow (Imperial Fists). Expose helper.
  - **Scenario:** `tests/scenarios/visual/T42_striped_yellow.json` — load fixture
    where opponent is Imperial Fists (yellow faction); trigger a warning overlay
    (e.g. T10 Tab threat); screenshot.
  - **Acceptance — Tier A (machine):**
    - `execute_script`: `UIConstants.striped_pattern(Color.YELLOW)` returns a
      Texture2D / shader handle that is NOT a solid color.
    - In threat-overlay screenshot with yellow-faction opponent: `pixel_diff`
      between a 16×16 sample of the overlay vs a 16×16 sample of the faction
      token: `regions["overlay_vs_faction"].diff_pct > 25.0` (texture is
      distinguishable from solid).
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] Stripes visible on the warning overlay.
    - [ ] Faction yellow remains solid (not striped).

- [ ] **T43 — Audit and remove redundant orange highlights**
  - **Lock:** HUD-Top + HUD-Right + HUD-Left  • **Doc:** §9
  - **Change:** Grep for the bright-orange "clickable" stylebox; reserve for the
    single primary CTA per screen. Other buttons revert to default chrome.
  - **Acceptance — Tier A (machine):**
    - `grep -rn '<orange-hex>' 40k/scenes 40k/scripts` returns ≤ 1 result per
      scene (the primary CTA only).
    - For each phase screenshot in the regression suite: visible orange-styled
      buttons count (via `execute_script` walking the scene) ≤ 1.
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] One CTA stands out per phase.
    - [ ] Other buttons read as secondary chrome.

- [ ] **T44 — Motion budget enforcement**
  - **Lock:** Infra + multiple  • **Doc:** §9
  - **Change:** Add `UIConstants.MOTION_DICE_MAX_S = 1.5`, `MOTION_SLIDE_PER_INCH_S
    = 0.4`, `MOTION_FADE_S = 0.15`, `MOTION_PULSE_LOOP_S = 2.0`. Refactor every
    Tween call site to use these constants.
  - **Acceptance — Tier A (machine):**
    - `grep -rn 'create_tween\|tween_property' 40k/scripts` — every result either
      has a literal numeric duration that matches one of the `UIConstants.MOTION_*`
      values, or imports the constant explicitly. Document each exception in commit.
    - `execute_script`: T33 dice animation total duration ≤ 1.5s.
    - `execute_script`: T19 pulse cycle measured ≈ 2.0s (±0.1s).
    - Regression count ≥ baseline.
  - **Acceptance — Tier B:**
    - [ ] No animation feels "too long".
    - [ ] Constants referenced from a single source of truth.

- [ ] **T45 — Final design-guidelines compliance audit**
  - **Lock:** Infra  • **Doc:** all
  - **Change:** After T01–T44 close, walk the design doc top-to-bottom. For each
    recommendation, link to the task that delivered it OR document why deferred.
    Update doc Status header. No code changes.
  - **Acceptance — Tier A (machine):**
    - `grep -c '^- \[x\]' .llm/todo.md` == 44 (T01–T44 closed).
    - `_baseline.json.count` updated to current passing count (new floor).
    - Design doc Status header updated with the closure summary.
  - **Acceptance — Tier B:**
    - [ ] Every doc recommendation has a corresponding closed task OR explicit
          deferral rationale.
    - [ ] No "Tier B" checkboxes left unticked across T01–T44.
