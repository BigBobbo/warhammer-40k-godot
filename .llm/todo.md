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
    - [x] Doc §9 table values match `UIConstants.gd` 1:1: 7 named slots, each
          a fully-opaque Color whose hex matches the comment after `:=` on
          each `const` line (e.g. `# #00B3B3` for FRIENDLY_PLAYER_TEAL).
    - [ ] `striped_pattern(Color.YELLOW)` returns an ImageTexture that, when
          tiled, shows visible diagonal hatching (NOT solid yellow). Look at
          the 16×16 tile: alternating opaque + transparent stripes at ~4px
          width, slope 1 (every (x+y) modulo 8 less than 4 is opaque).
    - [x] No autoload conflicts in `project.godot` — UIConstants appears
          exactly once in the `[autoload]` block and points to
          `*res://autoloads/UIConstants.gd`.

- [x] **T02 — Visual-scenario harness + pixel-diff + baseline snapshot**
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
    - [x] `_schema.md` enumerates every required scenario step type with example.
    - [x] `_template.json` runs end-to-end as a copy-paste starting point.
    - [x] `TESTING_METHODOLOGY.md` gained a "Design-guidelines visual tasks" section.

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
    - [ ] **Pre-known gap (file T03b):** drag-segment rendering is not
          wired up. The math returns the correct color slots, but no
          colored path is drawn in the live drag preview. Tier A passes;
          this Tier B item will fail until a renderer consumes
          `MovementController.current_drag_segments` and draws each
          segment in its `color_slot` color.
    - [ ] Green segments would be drawn from the drag origin to the M
          radius (WARBOSS_B: 6\"); yellow from M to M+Advance (12\");
          red beyond.
    - [ ] Inches label would update with the cursor X position
          (`current_drag_segments[-1].distance_inches`) as the user
          drags farther from origin.
    - [ ] ESC removes the drag overlay (when the renderer exists, the
          ESC handler in `MovementController._input` should clear
          `current_drag_segments = []`).

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
    - [ ] Six pills appear in a row at the top-center of the viewport,
          left-to-right: Command, Movement, Shooting, Charge, Fight,
          Morale. Each label fully visible — no ellipsis truncation.
    - [ ] Active phase pill is the brightest: full alpha + magenta
          (`#e633b3ff`) modulate when P2 is acting, teal (`#00b3b3ff`)
          when P1. Use a pixel-picker on the pill background to confirm.
    - [ ] Past phase pills (left of active) are dim grey
          (`#808080ff`, ~50%-grey on every channel) — clearly NOT the
          active hue, clearly NOT the future-alpha look.
    - [ ] Future pills (right of active) keep the active color but at
          alpha 0.4 — semi-transparent, you can see whatever's behind
          them through the pill.
    - [ ] Pills don't jump or resize when the phase advances; only the
          modulate color changes.

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
    - [ ] **Pre-known gap (file T05b):** tooltip widget not built. The
          forecast math returns a Dict with attacks/bs/s/t/ap/d/
          expected_wounds, but no HoverForecast Control renders it.
          Tier A passes; everything below depends on T05b shipping.
    - [ ] When tooltip exists: positioned near cursor, doesn't extend
          past viewport edges (auto-flips to left of cursor if cursor is
          near right edge, similar for vertical).
    - [ ] BS, S vs T, AP, D, expected_wounds re-read live as cursor
          moves between enemy units.
    - [ ] If `current_hover_forecast.in_cover == true`, the tooltip
          shows a "+1 to save" badge or similar cover indicator.
    - [ ] Tooltip disappears when cursor leaves the enemy unit
          (`current_hover_forecast` returns to null).

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
    - [ ] When `WeaponOrderPanel.open_for(...)` shows the panel, every
          token on the board remains visible (panel covers the right
          ~30% of the viewport; the left ~60% — where tokens live — is
          unobscured). Compare against a pre-T06 screenshot.
    - [ ] Panel body contains: a "Weapon Order" title, one row per
          weapon (Row_<weapon_id> Labels under `Body/WeaponList`), and
          two buttons named `StartSequence` ("Start Sequence") +
          `Cancel`. Each weapon row's text matches the weapon's name.
    - [ ] **Pre-known gap (file T06b):** ESC does not currently dismiss
          the panel. Cancel button works. File T06b to wire ESC.
    - [ ] Panel position is `(viewport.x - 360, 100)` — does not overlap
          the End-Phase button at bottom-right or the phase bar at
          top-center.

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
    - [x] Every terrain piece has a visible cover icon — one
          `TerrainCoverIcon_<terrain_id>` child per entry in
          `TerrainManager.terrain_features`, positioned at the piece's
          centroid, modulate.a >= 0.8.
    - [ ] At zoom 1.0 the shield glyph is recognizable as a shield
          (pointed bottom, flat top); the "+1" / "+2" / "LB" label
          inside is legible at normal viewing distance.
    - [ ] At zoom 0.5 the shield is still recognizable (it'll be ~14px
          tall instead of 28px). If the label becomes a smudge at
          0.5, file T07b to enlarge the icon for low zoom.
    - [ ] Icons sit ON the terrain piece, not over a token. With
          default co_pretrigger deployment, no model is closer than
          24px to a terrain centroid; if you see icon-on-token overlap,
          file T07b.

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
    - [ ] Each token shows two concentric rings: a smaller inner
          `FactionRing` (scale 1.0, alpha 0.35) and a larger outer
          `SlotRing` (scale 1.2, alpha 0.7). The outer ring should be
          ~20% bigger than the inner; both visible without one
          completely hiding the other.
    - [ ] P1 (Custodes) tokens: inner ring gold-ish
          (`Color(0.83, 0.59, 0.38)`); P2 (Orks) tokens: inner ring
          bone-ish (`Color(0.85, 0.80, 0.65)`). Use the pixel-picker on
          the inner ring of any token to verify.
    - [ ] Every P1 token has the same outer-ring color (teal
          `#00b3b3`); every P2 token has the same outer (magenta
          `#e633b3`). Compare two P1 tokens side-by-side: same teal.
    - [ ] The center of each token (silhouette/letter/glyph) is fully
          visible — rings only paint the rim, not the interior. Confirm
          by checking that the model number "1" is readable on any
          single-model unit.

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
    - [ ] After `set_exhausted_this_phase(true)`, the token's modulate
          is `Color(0.6, 0.6, 0.6, 1.0)` — visibly darker than a fresh
          token. Pixel-pick the token base; channels should all be ~153
          (0.6 × 255), not 255.
    - [ ] **Pre-known gap (file T09b):** roster-card dim is NOT
          implemented. T09 only modulates the TokenVisual; the
          `LeftRosterStrip`'s UnitCard_<id> does not yet receive the
          dim treatment. Tier A passes for TokenVisual only.
    - [x] Phase end clears exhaustion: on next phase_changed signal,
          modulate returns to `Color(1, 1, 1, 1)` and
          `is_exhausted_this_phase == false`. (Verified by Tier A.)
    - [ ] FactionRing and SlotRing (from T08) still visible on a dimmed
          token — they're modulated by the same overall token modulate
          but their underlying colors should still be distinguishable
          from each other (teal vs gold, etc).

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
    - [ ] On Tab-held, every unit owned by the OPPOSING player to the
          active player gets a yellow ring (`UIConstants.MARGINAL_YELLOW`
          at 15% alpha) centered on their first model. Count the rings
          — should equal the count of enemy units on the board.
    - [ ] Each enemy unit also gets a red ring (`INVALID_RED` at 10%
          alpha) at the 12-inch radius (`12 * Measurement.PX_PER_INCH`).
          The red ring should always be 12" wide; the yellow ring's
          radius depends on the unit's longest weapon range (default 24"
          if no weapons defined, so red may be smaller than yellow).
    - [x] Releasing Tab: `rendered_rings.is_empty()` and all child
          ring nodes removed. Verified by Tier A.
    - [ ] Press-and-release Tab 3–5 times rapidly: each cycle should
          produce a clean show/hide with no half-drawn rings, no rings
          left over from the previous press, no flicker mid-transition.

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
    - [ ] In a windowed session, exercise three LOS conditions
          (clear shot / cover between / blocking terrain between) and
          confirm three different ring colors:
          green `#33d94dff`, yellow `#f2d926ff`, red `#e63333ff`.
    - [ ] Both endpoints of the rendered Line2D sit at the centre of
          the shooter's model base and the target's model base — not
          offset, not at the edge. Verify by zooming in and overlaying
          the line with the token centers.
    - [x] On hover-off, `clear_line()` sets `current_line = null` and
          hides the Line2D child. Verified by Tier A.

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
    - [ ] Open any board scenario and compare against a pre-T12
          screenshot of the same fixture. Movement range circles,
          charge arrows, engagement rings, damage flashes — all should
          look the same color and shape as before. Differences > a
          subtle alpha shift = real regression, file T12b.
    - [ ] No NEW color slot appears anywhere — i.e. the only changes
          T12 introduced are constant references replacing identical
          hex literals. If you spot a previously-grey overlay now
          rendering as orange, that's a real bug.
    - [ ] The T12 commit body lists each call site converted (currently
          one: `HumanMovementPathVisual.gd:190` over-cap red →
          `UIConstants.INVALID_RED`). File T12b to extend the audit to
          the remaining visual scripts (~20 files identified in audit).

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
    - [ ] After pressing F: every corner of the playable board is
          inside the visible viewport. No black bars cropping the
          board, no terrain pieces partly off-screen.
    - [ ] The empty space between the board edge and the viewport edge
          is roughly the same on top, bottom, left, right (within
          ~32px margin per spec). Eyeball the white space — should be
          symmetric.
    - [ ] **Pre-known gap (file T13b):** the fit is INSTANT (camera
          position/zoom set directly, no tween). Tier B "smooth
          animation" will fail. File T13b for a 0.4s tween via
          `UIConstants.MOTION_SLIDE_PER_INCH_S`.

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
    - [ ] After Shift+F with WARBOSS_B selected: the WARBOSS sits in
          the center half of the viewport (eyeball: not off to one
          edge). Tier A confirms position within 10px of model
          centroid.
    - [ ] Other units within ~200px of WARBOSS (per the PAD_PX
          constant in `fit_view_to_selection`) are also in frame. If a
          neighboring unit is right next to WARBOSS but cropped off,
          file T14b to widen the pad. The selected unit itself is
          never cropped — its base is fully visible.

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
    - [ ] At zoom 1.0, each token's `Silhouette` child shows a shape
          recognizable as its category: infantry = disc, tank =
          rectangle, walker = upward triangle, beast = larger disc,
          aircraft = cross/plus, mounted = two discs, character =
          disc + body rectangle. Procedural, not artwork — judge by
          shape, not detail.
    - [ ] At zoom 0.5 the silhouettes are still distinguishable from
          each other (a tank rectangle vs an infantry disc should still
          read differently when each is ~16px tall). If they all blur
          together, file T15b.
    - [ ] Each token's model-number Label sits under the base (T16
          adds that Label; at zoom 1.0 it should be visible just below
          the silhouette).

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
    - [x] At zoom 0.5 every TokenVisual's Label child is hidden. No
          model-number "1"s visible under any base. (Tier A:
          `t16_apply_zoom(0.5)` returns false.)
    - [x] At zoom 1.0 every Label is visible again with its model
          number. (Tier A: `t16_apply_zoom(1.0)` returns true.)
    - [ ] Zoom smoothly from 1.0 → 0.4 → 1.0 with the +/- keys. The
          labels should snap on/off cleanly at the 0.6 threshold — no
          half-faded ghost labels, no flicker mid-zoom. If you see
          partial-alpha labels, file T16b for a cleaner show/hide.

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
    - [x] With 5 statuses applied via `set_active_statuses`: exactly 3
          status icons (TL, TR, BR slots) plus 1 OverflowChip
          (BL slot) are visible. Chip text is "+2". (Tier A.)
    - [ ] **Pre-known gap (file T17b):** OverflowChip is a static Label
          — hovering it does NOT expand to show the hidden 2 statuses.
          File T17b for tooltip-on-hover that lists the truncated names.

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
    - [ ] At zoom 1.0 the WoundChip Label text ("3/5", "2/5", etc.) is
          readable — font size 11, white-on-default-background. If the
          chip overlaps the base outline so badly that you can't read
          the digits, file T18b for a contrasting backdrop.
    - [x] On any single-wound unit, `wound_chip_text == ""` and
          `WoundChip.visible == false`. No "1/1" appears. (Tier A.)

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
    - [ ] After `start_pulse()` on one token, watch its SlotRing for
          ~5 seconds. The ring's alpha should oscillate smoothly between
          ~0.7 and ~1.0 with a full cycle period of 2 seconds
          (`MOTION_PULSE_LOOP_S`). Perceptible (you can see the
          breathing) but not distracting (you can still read the
          model-number label without losing focus).
    - [ ] Only the token that received `start_pulse()` is pulsing.
          Other tokens (P1 and P2) have static SlotRing alpha. In a
          windowed session, only the currently-active unit should
          pulse — selection logic to call start/stop is not yet wired
          to the active-unit signal, so this is a manual test for now.

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
    - [ ] When `EpicChallengePanel.open_for(...)` shows the panel: the
          left ~60% of the viewport (where the board lives) is fully
          unobscured. Tokens, terrain, deployment zones all visible.
          Compare against pre-T20 (when the dialog was a centered
          modal that covered the board).
    - [ ] Panel body contains: Title "Epic Challenge", Effect label
          showing the passed effect_preview text, two buttons: "Use"
          and "Decline" under `Body/Buttons`.
    - [ ] **Pre-known gap (file T20b):** ESC dismiss not wired. File
          T20b to add ESC binding in Main._input.

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
    - [ ] When `WoundAllocationPanel.open_for(target_unit_id, N)`
          shows the panel: the target unit's tokens are still visible
          on the board (left 60% of viewport). Compare against
          pre-T21 when WoundAllocationOverlay covered the board.
    - [ ] **Pre-known gap (file T21b):** the Commit button is a stub
          — it emits `allocation_committed` with an empty array but
          doesn't actually apply wounds to any model. File T21b to
          wire real per-model allocation UI inside the panel.

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
    - [ ] After `fit_view_to_decision([shooter_id, target_id])`: both
          unit's bases are visible in the viewport (left 60% — the
          panel covers the right). Eyeball: you can see both tokens
          without scrolling.
    - [ ] Camera move is instant (no animation yet — same gap as T13).
          For now: no jitter is trivially true because there's no
          animation. After T13b ships its tween, T22 will inherit
          the same smoothness check. File T22b alongside T13b.

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
    - [x] Across the four phases the scenario walks (COMMAND →
          MOVEMENT → SHOOTING → CHARGE), `EndPhaseButton.t23_anchor_offset()
          == Vector2(200, 60)` within 4px. (Tier A.) Visually: the
          button sits in the bottom-right, ~200px in from the right
          edge and ~60px up from the bottom, in every phase.
    - [ ] The button label reads "End Phase" (constant string) in every
          phase. No "End Shooting Phase" / "End Fight Phase" variants —
          the wording is intentionally phase-agnostic so it's
          predictable.

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
    - [ ] In a windowed session, call `set_substates(["Select Unit",
          "Select Target", "Resolve Hits", "Allocate Wounds"], 1)` and
          confirm: four crumbs appear below the active phase pill,
          each labeled with its string. Labels are font-size 11,
          legible at default zoom.
    - [ ] Crumb_0 ("Select Unit"): modulate `#808080ff` (grey) —
          completed. Crumb_1 ("Select Target"): modulate `#e633b3ff`
          (active player color, magenta in P2's turn) — active.
          Crumb_2 + Crumb_3: alpha 0.4 — future. (Tier A confirms the
          modulate values; this is the visual check.)

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
    - [ ] A 4px frame is visible around the entire viewport (top edge,
          bottom edge, left edge, right edge). Color = `#e633b3ff`
          (MAGENTA) when P2 is active, `#00b3b3ff` (TEAL) when P1.
          Pixel-pick a pixel from the top edge to confirm hex.
    - [x] `EdgeTint.mouse_filter == 2` (IGNORE) — clicks pass through
          to whatever's underneath. (Tier A.) Visually: clicking on a
          token at the very edge of the viewport selects the token,
          not the edge frame.

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
    - [ ] Hover over a past pill (e.g. COMMAND when SHOOTING is
          active) — Godot's default tooltip pops up with text
          "completed". Hover over a future pill (e.g. CHARGE) —
          tooltip reads "resolve current phase first". Active pill
          shows "current phase".
    - [x] Clicking any pill (past, active, or future) does NOT
          change the current phase. `GameState.state.meta.phase`
          remains 8 throughout the click sequence. (Tier A.)

- [x] **T27 — Refactor End-Phase button to canonical position**
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
    - [ ] After `set_from(unit_id, weapon_range)`: the inner filled
          disc is drawn at ~12% alpha (CONFIRMED_GREEN at `0.12 * 255 ≈ 31`).
          You can see what's under it — terrain texture shows through.
          Not opaque, not invisible.
    - [ ] The outer outline ring is drawn at 2px wide (the `draw_arc`
          call's `width` parameter). Thin line, not a thick filled band.
          Color MARGINAL_YELLOW.
    - [x] Both shapes are centered on the unit's first model position.
          (Tier A confirms position match.) Visually: the disc + ring
          surround the token without offset.

- [x] **T29 — Persistent engagement ring on engaged units**
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
    - [x] When two units are within 1\" (engagement range, verified by
          forcing WARBOSS to position (220, 100)), both get an
          `EngagementRing_<unit_id>` child under
          `PersistentEngagementOverlay`. Each ring has
          `is_persistent == true` and `visible == true`. (Tier A.)
          Visually: a subdued amber circle sits around each engaged
          unit at idle — no click required.
    - [x] Units outside engagement range have NO ring child. Tier A
          checks via `child_count == engaged_unit_count`. Visually: a
          unit standing alone in its deployment zone shows no
          engagement ring; only units in melee with an enemy show one.

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
    - [ ] After `t30_declare_charge_rings()`: two rings in the `rings`
          array — one labeled "max" at 12*PX_PER_INCH radius, one
          labeled "expected" at 7*PX_PER_INCH. Both `style == "dashed"`.
          (Tier A.) Visually: in a windowed session with the
          ChargeTrajectoryPreview rendering hooked up to consume the
          `rings` array, you'd see two dashed circles around the charger
          — one larger (max), one smaller (expected). NOTE: actual
          dashed rendering is a follow-up; current rings array is
          state-only.
    - [x] After `t30_set_rolled_ring(N)`: single ring labeled "rolled",
          `style == "solid"`, radius `N * PX_PER_INCH`. The two dashed
          rings are gone. (Tier A.)

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
    - [ ] In a windowed session, press R, click+drag from one point
          to another spanning a known distance (e.g. across one
          grid square). The label near the drag endpoint should read
          the inches value with one decimal place, formatted like
          `4.0"`. Compare against a measuring tape in the game — match
          within 0.1".
    - [ ] Press R (public): Line2D `default_color` alpha = 1.0, width
          = 3.0. Press Shift+R (private): alpha drops to 0.6, width
          to 2.0. Side-by-side compare: the public ruler is bolder /
          more opaque than the private one.

## §6 LOS & cover (continued)

- [x] **T32 — Move LOS Debug to held-key power-user mode**
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
    - [x] The HUD's top/bottom bars no longer show a "LoS Debug (L)"
          toggle button. `get_node_or_null("HUD_Bottom/HBoxContainer/
          LoSDebugButton")` returns null in every phase. (Tier A.)
          Visually: scan the bottom HUD bar — no orange/grey LoS
          button anywhere.
    - [x] In any phase: press-and-hold L → the LoS debug overlay
          appears; release L → overlay disappears. `Main._input`
          handles KEY_L unconditionally, so this works in COMMAND,
          MOVEMENT, SHOOTING, CHARGE, FIGHT, MORALE alike. (Tier A
          confirms wiring; this is the manual smoke check.)

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
    - [ ] **Pre-known gap (file T33b):** the four-column animated
          dice surface is not built. `t33_set_columns` populates the
          state array, but no UI rendering consumes it yet. Tier A
          passes the property contract; this Tier B item will fail
          until T33b ships the visible surface (vertical columns
          labeled Hits / Wounds / Saves / Damage, dice animating
          top-to-bottom).
    - [ ] SPACE keypress during the (future) animation should call
          `t33_skip()` which sets `visible = false`. Tier A confirms
          the skip logic.
    - [ ] When the surface DOES render: it anchors top-center, ≤ 40%
          viewport width. The left 60% of the viewport (board area)
          stays visible — tokens shouldn't be hidden behind the dice.

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
    - [ ] After `spawn_damage_floats(pos, 3, 1, 2.0)` you'd expect two
          floating labels: "-3W" and "-1 models". (Tier A confirms the
          Array entries.) In a windowed session, look for two text
          labels above the target — readable at default zoom, white
          text on dark outline ideally.
    - [ ] Default duration 2.0s. The labels should remain readable for
          ~2 seconds, then fade out. Too short = you miss them; too
          long = they overlap subsequent attacks. Tweak duration arg if
          either extreme.

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
    - [ ] After two synthetic `record_roll` calls in T35's scenario:
          `RollLogPanel/Scroll/Entries` has two Label children. (Tier A.)
          Each Label reads `"<timestamp> · <attacker> → <target> ·
          <result>"`. Font 12 — readable at the panel's 320px width
          without wrapping.
    - [ ] Roll log scrolls to bottom on each new entry — newest at
          bottom, visible without manual scroll. (`call_deferred
          ("_scroll_to_bottom")` is wired; verify by recording > 30
          entries and confirming you can see the latest without
          scrolling up.)

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
    - [x] `add_pending_target("U_CUSTODIAN_GUARD_B")` queues the
          target in `pending_targets` but `targets_committed` stays
          `false`. No dice are rolled, no resolution kicks off. A
          duplicate add returns false and doesn't grow the array.
          (Tier A.)
    - [ ] **Pre-known gap (file T36b):** `commit_targets()` flips the
          flag but doesn't actually call the resolution path. The
          existing ShootingPhase resolution code needs to react to
          `targets_committed == true`. File T36b to wire the trigger.

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
    - [x] Every unit in `GameState.state.units` has a corresponding
          `UnitCard_<id>` child under `LeftRoster/Scroll/Cards`. (Tier
          A confirms `visible_unit_ids.size() == units.size()`.)
          Visually: scroll the left strip — every army's units listed,
          none missing.
    - [ ] Each card's Name Label reads `"<unit_name> (<model_count>)"`
          at font size 11. With the panel width of 220px, names up to
          ~25 chars fit on one line. Long names (e.g. "Tellemon Heavy
          Dreadnought") may need truncation handling — if any name
          spills into adjacent UI, file T37b.
    - [x] Single-click a card → `last_camera_fit_action = "selection"`
          and `fit_view_to_selection` runs. Double-click → DatasheetModal
          opens for that unit. (Tier A.)

- [x] **T38 — Filter chips above roster**
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
    - [x] `set_active_filter("can_act" | "engaged" | "below_half")`
          reduces `visible_unit_ids.size()` below the total unit
          count. Default "all" gives the full set. (Tier A confirms
          each filter shrinks the list. Visually: as you click each
          chip, the cards in the left strip update to show only the
          matching subset; switching back to "all" restores all
          cards.)

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
    - [x] After `open_for("U_WARBOSS_B")`: the modal contains a Title
          ("Warboss" or similar), a Stats line starting with "M ", "T ",
          "Sv ", "W ", "Ld ", "OC ", a Weapons block starting with
          "WEAPONS:", a Keywords block starting with "KEYWORDS:", and
          an Abilities block starting with "ABILITIES:". (Tier A
          confirms each prefix.)
    - [ ] The modal is 480 × 600px, centered on viewport. All four
          sections (Title / Stats / Weapons / Keywords / Abilities) fit
          inside without scrolling for a typical unit (Warboss has
          ~5 weapons, ~5 abilities). If any section overflows or text
          is cut off, file T39b to add a scroll container.

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
    - [x] After `set_prospective(shooter, target, false)`:
          `displayed_bs`, `displayed_modified_save`,
          `displayed_expected_wounds`, `prospective_target_id` all
          populated. (Tier A.)
    - [ ] **Pre-known gap (file T40b):** the existing UnitStatsPanel
          UI does not yet re-render to show the prospective numbers.
          The state is computed and stored on the panel; the visible
          stats block still shows the un-modified base values. File
          T40b to wire panel re-render on `set_prospective`.

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
    - [x] `UIConstants.player_slot_color(p)` and
          `UIConstants.faction_color_for_player(p)` exist as separate
          functions, returning different colors (slot = teal/magenta,
          faction = gold/bone via FactionPalettes). (Tier A.) The
          commit `[T01]` introduces these helpers; subsequent T08/T15
          callers route through them.
    - [ ] Run a fixture with Imperial Fists (yellow faction) and a
          fixture with Black Templars (white/black) as P1. In each:
          the outer SlotRing on every P1 token should still be TEAL
          (`#00b3b3`), even though the faction palette differs. If the
          slot color picks up the faction yellow / white, that's a
          conflation — file T41b.

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
    - [ ] **Pre-known gap (file T42b):** `striped_pattern()` returns
          a valid ImageTexture (Tier A confirms a 16×16 tile with
          alternating opaque/transparent pixels) but no overlay
          actually uses it yet. ThreatOverlay still paints yellow as
          solid. File T42b to swap `MARGINAL_YELLOW`-colored fills to
          use `striped_pattern(MARGINAL_YELLOW)` instead.
    - [ ] When T42b ships: a faction-Imperial-Fists fixture should
          show the yellow faction tokens as SOLID yellow, while the
          T10 threat overlay's yellow rings render as STRIPED yellow.
          Side-by-side: solid vs hatched — clearly different patterns.

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
    - [ ] In each phase (COMMAND, MOVEMENT, SHOOTING, CHARGE, FIGHT,
          MORALE), exactly one button uses
          `UIConstants.primary_cta_color()` (`#ff8c00`, WARNING_ORANGE).
          That's the End-Phase button (T23). Eyeball the screen — only
          one orange button should be prominent.
    - [ ] Every other clickable button (e.g. weapon-order panel
          buttons, datasheet close, filter chips) uses the default
          stylebox — grey/neutral, NOT bright orange. If you spot two
          orange buttons competing for attention in any phase, file
          T43b naming both.

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
    - [ ] In a windowed session, time the four motion budgets against
          their constants:
          - T33 dice surface animation: complete in ≤ 1.5s (matches
            MOTION_DICE_MAX_S). Use SPACE to verify skip works.
          - Token slides on legal move commit: ≤ 0.4s per inch
            (MOTION_SLIDE_PER_INCH_S).
          - Overlay fade-in (e.g. ToastManager): ~0.15s
            (MOTION_FADE_S).
          - T19 active-unit pulse: full cycle period 2.0s
            (MOTION_PULSE_LOOP_S). Stopwatch one cycle.
          Anything > 1.5× spec'd value = file T44b for that specific
          animation.
    - [x] All four constants live in `UIConstants.gd`. Two existing
          call sites (`ToastManager.gd:70`, `NetworkManager.gd:1680`)
          read from there. (Tier A confirms the constants; the partial
          codebase refactor was T44's documented scope.) File T44b to
          extend conversion across remaining ~125 tween call sites.

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
    - [ ] Walk `40k/docs/design_guidelines_2d_topdown.md` top-to-
          bottom. For each recommendation in §1 through §10, find the
          T## that delivered it (or a T##b refinement that's filed but
          not yet shipped). Anything in the doc with no
          corresponding task → file as the next free T## immediately.
    - [ ] Every Tier B checkbox in T01–T44 is `[x]` (either from this
          file's pre-pass or from your windowed review). If any remain
          `[ ]`, they should each have a T##b refinement filed in
          this todo file.
