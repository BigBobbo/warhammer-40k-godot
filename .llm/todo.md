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

- [x] **T01 — UIConstants color slot autoload**
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
    - [x] Doc §9 table values match `UIConstants.gd` 1:1 (cross-check via diff).
      *(T01_after palette card shows live hex = doc hex, "match", on all 7 rows; a
      `diff` of the two tables is empty.)*
    - [x] `striped_pattern` output renders as visible stripes (eyeball one screenshot).
      *(1x and 4x swatches beside solid yellow in T01_after; row read-back: 63
      transitions, 50% yellow.)*
    - [x] No autoload conflicts in `project.godot`.
      *(60 entries, none duplicated, UIConstants once as `*res://…`, no class_name
      shadows an autoload. Checked by `tests/test_ui_constants_slots.gd`.)*
  - **Note (2026-10-30 audit):** the autoload, its registration and `striped_pattern`
    had already shipped. This pass closed the evidence gaps. Deviations from the
    wording above: (1) doc §9's table named hues only, so "exact hex specified in doc
    §9 table" could not be checked. The table now has Constant + Hex columns,
    cross-checked 1:1 by `tests/test_ui_constants_slots.gd` (in the gate) and by the
    scenario. (2) The scenario's single-line Expression path rejects `Color.YELLOW`
    (`Expected '('`), so the `striped_pattern(Color.YELLOW)` checks run as
    `multiline` steps. (3) No action is dispatched, so the hex checks are
    `execute_script` `equals` steps rather than `expect_action_result`.

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
      *(Every required step now has a JSON example: `screenshot` before/after,
      `expect_state`, `dispatch_action` + `expect_action_result`, `expect_phase`,
      `expect_node_property`, `expect_baseline_unchanged`. `execute_script`
      (single-line and `multiline`) and `pixel_diff` keep theirs. Before this
      pass the required steps were prose only.)*
    - [x] `_template.json` runs end-to-end as a copy-paste starting point.
      *(It used to FATAL at fixture load on its `<fixture_name_or_omit>`
      placeholder, exit 2. It now ships runnable values and keeps the guidance in
      its description: 14/14 in place, and a verbatim copy run as
      `visual/T00_template.json` passes and fills `design_guidelines/T00/`.
      T00_after shows "Unit: Blade Champion", "Move: 6.0"" and the move buttons
      lit; selected_unit_panel diff 11.0%, game_log 0.0%.)*
    - [x] `TESTING_METHODOLOGY.md` gained a "Design-guidelines visual tasks" section.
      *(The "Design-guidelines visual tasks (T01–T45)" section was already there.
      This pass added diff_report.json, the full-suite-only exit 3 and the CLI.)*
  - **Note (2026-10-30 audit):** the schema, template, baseline, `pixel_diff.gd`
    (+ unit test), the run_scenarios.sh post-processing and the methodology
    section had already shipped. Tier A, all checked on this pass:
    `_baseline.json` has 41 ids and count 41. The T02 scenario exits 0 (21/21).
    Identical PNGs give exactly 0.0, and 100% black vs 100% white gives 100.0
    (in the unit test, in the new CLI, and live in the scenario).
    `test_results/design_guidelines/T02/diff_report.json` parses. Exit 3 was
    proved on a shrunken `--visual` suite: 2 scenarios against a temporary
    baseline of 2 exit 0, renaming one exits 3, and the committed 41 against 2
    exits 3. visual/ was then restored byte-for-byte. Fixed on this pass:
    (1) the template could not run (see Tier B). (2) The T02 scenario never
    showed that pixel_diff can see a difference: it had only `expect_max`
    bounds, which a diff stuck at 0% passes. It now diffs a frame against
    itself (== 0.0) and a full-frame black probe against the same probe in
    white (> 95%; a mutation keeping both black fails it). Its `full_viewport`
    region was 1280x720 on a 1920x1080 frame. (3) The artifact copy used a
    `<id>_*.png` glob. That swept in stale labels, old FAIL shots and any
    scenario whose id starts with this one. After a FATAL exit (no results) it
    also re-reported the previous run's results JSON and passing diffs as this
    run's. It now copies exactly what this run wrote (the paths in the results
    JSON plus failed-step captures, mtime at or after launch), and a run with
    no results gets a diff_report.json with "error" and all_passed=false.
    (4) Change 3's "emits JSON to stdout" was missing. Added
    `tests/tools/pixel_diff_cli.gd`. (5) The pixel_diff unit test ran nowhere.
    It is now in run_pretrigger_tests.sh. Deviations from the wording above:
    (a) diff_report.json is built from the scenario's own `pixel_diff` steps
    (the runner holds the labels and regions) rather than by the shell
    re-running pixel_diff. The CLI covers ad-hoc diffs. (b) The schema accepts
    any falsifiable assertion (`execute_script` with a bound, `expect_phase`,
    `expect_node_property`, ...), not only `expect_state`/`expect_action_result`,
    because nearly every T## scenario asserts through `execute_script`.
    (c) Exit 3 fires only on a full-suite `--visual` run. A run of named files
    skips the baseline check by design. (d) `_baseline.json` was not
    re-snapshotted, because refreshing it is T45's job. The screenshot-only
    ban is documented, not enforced by the runner, and no current visual
    scenario breaks it.

## Top-10 quick wins (parallelizable after T02 if locks are disjoint)

- [x] **T03 — Drag-ruler with budget coloring during movement**
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
    - [x] Green segments visible from origin to Move boundary.
      *(T03_a/b/c: green from the pickup dot to the 6" Move boundary, which sits
      under the clamped ghost in b and c. Run 0 is CONFIRMED_GREEN 6.0".)*
    - [x] Yellow segment between Move and Move+Advance boundaries.
      *(T03_b: yellow from 6" to the 9" cursor. T03_c: yellow from 6" to 12",
      with a tick where it turns red.)*
    - [x] Red segment beyond Move+Advance.
      *(T03_c: red from 12" to 14", ending in a red dot on the cursor.)*
    - [x] Inches label updates as cursor moves.
      *(Beside the cursor: 4.0" in green, then 9.0" Advance in yellow, then
      14.0" out of reach in red. The scenario asserts each text.)*
    - [x] ESC removes the drag overlay cleanly.
      *(T03_after_esc looks the same as T03_before: no ghost, ruler, label or
      reach circle, and no Settings menu. drag_path diff against the static
      before is 0.52%. At HEAD, ESC opened Settings and left the drag live.)*
  - **Note (2026-10-30 audit):** what had shipped was `current_drag_segments` and a
    `compute_drag_segments()` what-if helper: one straight line, the controller's own
    copy of M, and `T03_ADVANCE_INCHES = 6`. The live drag never called it, and the
    scenario only tested that helper. A real 14" drag at HEAD left the segments empty
    and drew the old white line to the clamped ghost. There were no waypoints, ENTER
    did nothing, and there was no `BEGIN_MODEL_DRAG`. Changed on this pass:
    (1) Every drag update now runs `_refresh_drag_ruler()`. It splits pickup →
    waypoints → cursor into budget runs (`_split_path_by_budget`). Each band edge is
    found with the over-range clamp's own ray search, so terrain is costed the way
    the drop is validated. `MovementRangeVisual.DragRuler` paints the runs, just
    under the ghost, with band ticks, waypoint rings and the label. For single-model
    drags it replaces the old yellow path line and white ruler. (2) The budget comes
    from the new `RulesEngine.movement_drag_budget(move_data)`, fed the phase's active
    move. Normal: M plus the D6 maximum. Advance: M plus the rolled value. Fall Back,
    Surge and reactive moves: no Advance. (3) The drag claims SHIFT, ENTER and ESC in
    `MovementController._input`, so Main's ESC pause menu and a focused button's
    ENTER no longer fire underneath it. ENTER stages the path leg by leg, and
    MovementPhase sums re-staged legs (T-082): 3" + 3" records 6.0", not the 4.24"
    straight line. (4) New `BEGIN_MODEL_DRAG` phase action: validated, changes no
    state, and its `model_drag_requested` signal calls `begin_model_drag`. Tier A:
    scenario 71/71. drag_path diffs: (a) vs (c) 38.7% (bound > 5), before vs (a)
    18.7% (bound > 2). Visual suite: 41 passing, equal to the baseline. New gated
    test `tests/test_drag_ruler_budget.gd` (49 checks) fails at HEAD. Deviations:
    (a) The work also touched MovementPhase.gd, because the Tier A dispatch needs a
    real phase action, and RulesEngine.gd, which had no movement API. M itself still
    comes from MovementPhase (`get_unit_movement` / the active move's cap, which carry
    every codex modifier). RulesEngine combines it with the mode and the roll into
    M + Advance. (b) Before an Advance is rolled, the yellow band is the D6 maximum
    (6"). (c) The scenario fixture moved from co_pretrigger to
    audit_baseline_postdeploy. WARBOSS_B is not the active player's unit, so it
    cannot be dragged. The Blade Champion has a terrain-free lane. (d) A SHIFT
    waypoint lands on the ghost (the cursor held to the budget), not the raw cursor,
    so every corner is a spot the model can stand on. (e) Multi-model group drags
    keep their reach circles and get no ruler, matching the task's "while dragging a
    model". (f) Known gap, not new: after a waypoint commit, the staged-path preview
    draws only the last leg, because MovementPhase keeps one staged entry per model
    (true of any re-staged model). The recorded distance is right.

- [x] **T04 — Six-phase top-center bar with active highlight**
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
    - [x] Six pills readable, labels not truncated.
      *(T04_command_before, _movement, _shooting_after, _p2_command, _p2_movement: all
      six words read in full in every state, 16 px Rajdhani Bold in 94 px pills. The
      scenario checks each label is at least as wide as its rendered word.)*
    - [x] Active pill is visually the brightest.
      *(A solid chip in the slot colour, with a glow. Rendered CIE L* sampled inside
      each pill: TEAL 65.8 and MAGENTA 54.5, against 43.2 for a completed pill and 5.6
      inside a future one. Five scenario steps assert it with `"equals": "ok"`: in every
      captured frame the lit pill must be more than 8 above every other pill, P2 Movement
      included.)*
    - [x] Completed pills are distinguishable from future pills.
      *(Completed: a solid grey chip with dark text. Future: a hollow outline with faded
      text. L* 43.2 against 5.6. The same steps assert completed pills are more than 20
      from each future pill.)*
    - [x] No layout shift in the rest of the HUD when phase advances.
      *(The strip, the bar, every pill and arrow, GameLogPanel, HUD_Right and HUD_Bottom
      keep their Command-phase rects in Movement, Shooting and P2 Movement. Every pill is
      one size in every state. The old strip drew the active word at 19 px and the rest
      at 17 px, so its row re-centred on every phase change.)*
  - **Note (2026-10-30 audit):** no pills existed. `Main._setup_phase_strip()` built the
    bottom PhaseStrip from six unnamed Labels: the active word gold and larger, completed
    words barely visible, no modulate states and no player colour. Changed on this pass:
    (1) New `40k/scripts/PhaseBar.gd` builds six pills named `PhasePill_<Phase key>` and
    sets each pill's `modulate`: active = `UIConstants.player_slot_color(active player)`,
    completed = `Color(0.5, 0.5, 0.5, 1.0)`, future = alpha 0.4. Each state also has its
    own pill style (solid glowing chip, solid grey chip, hollow outline). The bar connects
    to `PhaseManager.phase_changed` when it enters the tree and disconnects when it leaves.
    (2) Main hosts the bar inside the PhaseStrip and now only decides whether the strip
    shows. The strip's margins keep the 21 px pill row above the 6 px PlayerTurnBorder,
    which paints over the strip's bottom edge. (3) The strip now shows as soon as Main
    builds it. Main._ready restores a loaded save's phase before the strip exists, so
    after loading a mid-battle save the strip stayed hidden for a whole phase. Probe:
    `PhaseStrip.visible` read false after loading audit_baseline_postdeploy on the old
    Main.gd and true now. The T04 scenario now starts on that load path. Tier A: scenario
    71/71, reaching Movement and Shooting by real clicks on the End Phase button, its
    confirm, and Decline on P2's War Cry offer. phase_bar diffs: Command to Movement
    14.2%, Movement to Shooting 14.6%. Visual suite: 42 passing (baseline 41: the same 41
    plus T04), with T23, T27 and T39 failing as before and T45 XFAIL. New gated
    test `tests/test_phase_bar.gd` (35 checks) fails at HEAD. Deviations: (a) Placement:
    the pills live in the existing bottom PhaseStrip, not a new top-center bar. The strip
    was moved to the bottom on purpose, and `visual/T_phase_strip_bottom.json` (still
    passing) pins it there. Pill paths are `/root/Main/PhaseStrip/PhaseBar/PhasePill_<NAME>`,
    not `/root/Main/PhaseBar/...`. (b) Phase list: the sixth pill is Score
    (`PhasePill_SCORING`), the game's real sixth phase. Morale is not a phase here: MORALE
    is a deprecated enum slot that PhaseManager remaps to COMMAND (ISS-034). (c) Touches:
    Main.tscn is unchanged because the strip is built in code. PhaseManager.gd is
    unchanged because `phase_changed` already existed. (d) The P2 colour is checked by
    setup privilege (`set_active_player(2)` plus a transition), since reaching P2's turn by
    clicks means playing out all of P1's turn. (e) The diff bound is 11%, not the task's
    3%. A change to one pill alone (the P1-to-P2 recolour) measures 8.3% of the pill rows,
    about 7% of the 30-row phase_bar region, so 11% also fails a bar where only one pill
    changed.
  - **Audit fix (2026-10-30):** the five rendered-L* steps (17, 33, 49, 59, 69) had no
    expectation key, so ScenarioRunner passed them whatever they returned: the L* margins
    above were measured but never asserted. Each step now returns exactly "ok" and carries
    `"equals": "ok"`. The values go to the debug log, and a failure returns its verdict
    with every pill's L*. The margins are strict: the lit pill more than 8 above every
    other, completed pills more than 20 from future ones. A scratch probe on the same
    fixture (not committed) passes the real frame and fails both sabotages: lit pill forced
    hollow gives "active not brightest"; a future pill forced grey gives "completed vs
    future too close". Scenario 71/71.

- [x] **T05 — Hover-forecast tooltip for shooting**
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
    - [x] Tooltip readable, not clipped by viewport edges.
      *(T05_after, _hover_battlewagon, _hover_boyz, _no_cover, _cover: a dark card with a
      gold border, 15-18 px text, every row legible. It sits above-right of the cursor. On
      the Battlewagon, Main's stats card opened under the cursor, so the forecast flipped
      above-left with no overlap. The scenario asserts the card is on screen after every
      hover and when anchored at each of the four viewport corners.)*
    - [x] Numbers update when hover moves between targets.
      *(Caladius: Boyz E T5 shows "Twin iliastus accelerator cannon, A 8, ≈ 13.0 damage
      (≈ 4.3 models)". The Battlewagon shows T12, the blaze cannon and ≈ 9.2 damage. Back on
      Boyz E it shows the Boyz numbers again. Contemptor with one gun: Boyz E reads BS 2+,
      0.8 hits; Kommandos H reads BS 3+, 0.7 hits.)*
    - [x] Cover icon / cover delta surfaced in the tooltip.
      *(T05_after / _cover: a yellow shield row "Benefit of cover: BS 2+ → 3+", and BS 3+
      in yellow on the profile row. T05_no_cover (target in the open) has neither.)*
    - [x] Tooltip disappears on hover-off.
      *(T05_hover_off: no card, no LoS line, no stats card. current_hover_forecast is null,
      and the card's rect differs 0.0% from the no-hover T05_before. Moving onto the
      right-hand HUD panel also clears it.)*
  - **Note (2026-10-31 audit):** what had shipped was `current_hover_forecast` and a
    `compute_hover_forecast()` what-if helper with its own naive maths. It used the first
    datasheet weapon, even a melee one. It treated cover as +1 to the save (the 10e rule;
    11e 13.08 worsens BS) and applied no modifiers. Nothing called it on hover. There was
    no tooltip, no `HoverForecast.gd`, no `preview_attack` and no `test_hover_target_id`.
    The scenario only called the helper. Changed on this pass: (1) New
    `RulesEngine.preview_attack(shooter, target, weapon, board, opts)`. It holds the maths
    of the P3-114 forecast (`ShootingController._calc_weapon_expected_damage`, now a
    one-line wrapper), so the hover card, the Forecast panel, the Quick Assign buttons, the
    resolution dock and T40's panel all read one forecast. Fixes that came with the move:
    die probabilities come from the live evaluators (`AttackSequence.evaluate_hit_roll` /
    `evaluate_wound_roll`, every face and re-roll face enumerated); +1/-1 cancel as in the
    live roll; the 11e ModifierStack adds [HEAVY] (24.16), plunging fire and the
    close-quarters penalties; cover worsens BS per firing model, sampling at most 4 per
    weapon; [TORRENT] never crits; Sustained Hits Dx uses its average; the hit display
    includes cover; "kills" drop damage beyond a model's Wounds. (2) Hovering an eligible
    enemy (shooter selected, cursor not over the HUD) fills `current_hover_forecast` and
    shows the new `HoverForecast` card. The card describes the selected weapon row, or
    else the weapon that takes the most wounds off the target. The hover clears on
    hover-off, deselect, shooter change, resolution start and phase end. (3) The
    `test_hover_target_id` seam (task name) calls `t05_set_hover_target`, which runs the
    production hover path anchored at the unit's centre. (4) Cost: about 5-9 ms per weapon
    forecast against 4.5 ms for the old maths, using a per-frame cover cache and memoised
    probability tables. A first cut without sampling ran 15-19 ms per call for a 20-model
    mob. Tier A: scenario 82/82. It covers SELECT_SHOOTER, the seam, bs == 3 (BS 2+ in
    cover, also recomputed from the weapon profile), expected_wounds > 0, the card visible
    with its cover row, a tooltip_area diff of 99.96% (bound 4%), real mouse hovers, the
    HUD and empty-board hover-off (0.0% diff back to the before frame, bound 2%), and one
    gun against an open target and a target in cover. Visual suite: 42 passing (baseline
    41); T23, T27 and T39 fail as before, and T45 is XFAIL. New gated test
    `tests/test_hover_forecast.gd` (67 checks) fails at HEAD. Gate: 178/178 (known XFAIL
    only). The 12 sp scenarios that read the forecast or hover in Shooting pass.
    Deviations: (a) Oath of Moment does not exist in this 11e build: Codex: Space Marines
    replaced it (FactionAbilityManager.gd). The preview counts what the engine does apply:
    the re-roll and +1 effect flags that army rules and stratagems set, [HEAVY] and cover.
    (b) 11e cover is one rule, the benefit of cover. It worsens BS by 1 against any target
    that has it: INFANTRY/BEASTS/SWARM in a terrain area, any unit not fully visible to
    the firing model, STEALTH, or the stratagem. There is no light/heavy cover. The
    expected value is BS 2+ guns worsened to 3+, read off the weapon profile and confirmed
    by `TerrainManager.unit_has_cover_11e`. (c) `expected_wounds` means successful wound
    rolls, as "wounds" does on the P3-114 card and in the dock. The hook also carries
    `expected_damage` and `expected_models_killed`. (d) The tooltip node is
    `/root/Main/ShootingController/HoverForecast`, so it goes away with the phase. (e) The
    scenario fixture is `audit_383_battleshock_shoot`, not co_pretrigger: no P2 unit has
    an eligible target in co_pretrigger.

- [x] **T06 — Convert Weapon Order modal to side-anchored panel**
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
    - [x] Tokens at original positions visible while panel is open.
      *(T06_after next to T06_before: every token is where it was and the camera has not
      moved (view_zoom / view_offset asserted). Only the [A] target chip and the fire line
      differ, 0.36% of the left 60%. Pointing at the Witchseekers still draws the LoS line,
      with no Control under the cursor.)*
    - [x] Panel has all controls the old modal had.
      *(T06_after: one row per gun naming its target, each with ▲▼; Roll to Hit ▶ is
      Start Sequence (same RESOLVE_WEAPON_SEQUENCE, fast_roll false); Fast Roll All ⏩;
      plus ◀ Back to Targets (Esc), which the modal never had. The modal's "Dmg | Atks |
      Total Potential" line is the dock's expected-damage figure (B5), and its log is the
      Dice Log tab (B2).)*
    - [x] ESC dismisses without committing.
      *(T06_esc matches T06_before: right panel 0.0% different, the same three assignments,
      nothing rolled, shooter still active. T06_locked: after the defender's SMOKESCREEN the
      button is greyed out and Esc only explains why.)*
    - [x] No layout overlap with the existing right-side phase controls.
      *(T06_after / T06_locked / T06_rolling: the dock sits inside HUD_Right under SHOOTING
      CONTROLS and clear of the End Shooting Phase button, the top bar and the phase strip,
      all asserted by rect.)*
  - **Note (2026-10-31 audit):** what had shipped was `WeaponOrderPanel.gd`, a panel at
    `/root/Main/WeaponOrderPanel` that nothing opened. Its Start Sequence emitted a signal
    nobody heard, its rows were bare labels, and it was pinned over the HUD_Right column
    (x 1560), where the shooting controls live. The scenario only called `open_for()`. By
    then B2 (audit 2026-07) had already moved single-player weapon ordering out of the
    centred WeaponOrderDialog and into the right HUD, as the shooting resolution dock's
    "queued" state, with the board visible. What was missing was Esc and any way back. Esc
    and pad B deselected the shooter while the dock kept the phase waiting on an order (a
    half-state), and a board click could re-aim guns or pick another shooter behind the
    dock. Changed on this pass: (1) New `CANCEL_WEAPON_ORDER` action. ShootingPhase keeps
    the declaration from CONFIRM_TARGETS and hands it back unchanged: nothing rolled, the
    shooter still selected. It is refused once the targets are locked in: a stratagem used
    since the declaration (new `StratagemManager.usage_count`), or an Unpredictable Genius
    roll. (2) The dock's ordering step has "◀ Back to Targets (Esc)", greyed out with the
    reason when locked. Esc and pad B send the same action, never deselect while the dock is
    up, and do nothing once dice roll. A board click while ordering no longer re-aims or
    switches shooter; the panel tells the player to press Esc. After Back, the declaration
    panel looks as it did before Confirm, including the COMBINED FORECAST card.
    (3) `SceneRefs.board_screen_rect()`, moved out of ReservesTray, backs the
    no-intersection check. (4) The dead stub is gone, and T45's existence check now points
    at the dock's Back button. Tier A: scenario 104/104. It covers: the Confirm click
    reaching awaiting_weapon_order; dock left edge / viewport width 0.79; HUD_Right anchors
    1/1; no intersection with the board rect; pixel_diff board_left 0.36% (< 1), board rect
    0.56% (< 1), right_panel 53.6% (> 10); a dispatched CONFIRM_TARGETS returning success
    and weapon_order_required. New gated test `tests/test_weapon_order_cancel.gd` (47
    checks) fails at HEAD. Gate: 179/179 (known XFAIL only). Visual suite: 42 passing
    (baseline 41); T23, T27 and T39 fail as before, and T45 is XFAIL. Of the 23 sp scenarios
    that reach the dock, Esc, pad B or the reserves tray, 18 pass; the other 5 are the
    T4-tutorial XFAILs, which fail before the dock opens.
    Deviations: (a) The panel is the B2 dock (`.../ShootingPanel/ResolutionDock`), not a
    node renamed `WeaponOrderPanel`. Renaming it would break the 30 scenarios that address
    the dock, and the dock is the whole resolution surface; a second panel would duplicate
    it. (b) There is no BEGIN_WEAPON_ORDER action. CONFIRM_TARGETS with two or more weapon
    types is what begins the weapon order. (c) "anchor_left >= 0.6" is read as the dock's
    left edge over the viewport width. The dock sits in containers; its HUD_Right column
    carries the right anchors. (d) Networked play still uses the WeaponOrderDialog, popped
    at the bottom centre, and its Esc only hides it. Moving MP onto the dock is the B2
    follow-up that needs the save broadcast/ack sync
    (docs/SHOOTING_MULTI_TARGET_UX_AUDIT_2026-07.md) and cannot be checked by a
    single-player scenario. (e) The lock case gives the Witchseekers SMOKE as a setup step
    (as iss15_smokescreen_reactive_11e does), so the defender is offered SMOKESCREEN.

- [x] **T07 — Per-tile cover icons on terrain**
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
    - [x] Every terrain piece has a visible cover icon.
      *(T07_overlay_on, fitted view: 36 shields for the fixture's 44 pieces. The other 8
      are area boundaries whose single feature has the identical footprint
      (area-short-line-23/catwalk-25, area-long-line-27/gantry-29, area-medium-35/
      generator-37, area-short-line-39/pipe-41 and their mirrors): each pair stacks two
      identical shields on one centroid and reads as one. The scenario asserts every icon
      is_visible_in_tree with modulate.a >= 0.8.)*
    - [x] Icons readable at zoom 1.0 and still recognizable at zoom 0.5.
      *(T07_zoom_1_0 / T07_zoom_0_5: the shield is 30x34 px on screen with 17 px LB / +2
      text at both zooms, upright. The scenario asserts on-screen scale 1.0 at the fitted
      view, zoom 1.0, zoom 0.5 and with the board rotated 90 degrees. At the zoom-0.3 view
      the fixture opens at, the three +2 shields of the top-left corner ruins (2" apart)
      touch each other but stay legible.)*
    - [x] Icons don't overlap tokens at default deployment positions.
      *(T07_overlay_on and the zoom-0.3 opening view: the nearest shield is ~10 px below
      the Caladius base on the top edge, and the bottom-edge Ork tokens are clear. The
      scenario tests every icon footprint against every token base (BaseShape overlap) at
      the fitted view: none. Icons now also draw below the tokens (z 2 vs 10).)*
  - **Note (2026-10-31 audit):** what had shipped was `TerrainCoverOverlay.gd`, one
    `TerrainCoverIcon_<id>` per piece, made opt-in by a later decision (Settings > Visual >
    Terrain Cover Labels, OFF by default). Gaps: (1) icons were 28 board px, so ~8 px at
    the zoom-0.3 view the fixture opens at; the overlay on/off diff was 0.05% (Tier A
    wants > 1%), the scenario's bound was 0.015% and its "board" region the whole frame.
    (2) The scenario checked child(0) only, against `position`, not every terrain_id by
    name against its polygon centroid. (3) No terrain carries a `cover_type`; the overlay
    derived one from height (obscuring or tall -> LB, medium -> +2, else +1), labelled
    "10e rules". The game is 11e only, where cover follows the category: a light tall ruin
    read LB and a light medium one +2 under identical rules. (4) z_index 50 drew the icons
    over the tokens (10), contrary to its own comment. (5) The fallback centroid was the
    vertex average (up to 47 px off on the trapezoids). (6) A terrain reload queue_free'd
    the old icons, so all 44 new ones came back as `@Node2D@N` and no
    `TerrainCoverIcon_<id>` lookup worked (probed at HEAD). Changed on this pass:
    (1) `TerrainManager.cover_type_of(piece)`: the 11e category on the doc's
    light/heavy/blocking ladder (exposed +1, light +2, dense LB; height ignored), which
    the overlay labels from. (2) Icons keep a constant 30x34 px upright size on screen
    (counter-scaled and counter-rotated against BoardRoot's zoom and rotation), with a
    pale rim and outlined 17 px text, at z_index 2: above the terrain art, below the
    movement/threat/engagement overlays and the tokens. (3) `centroid_of()` is the
    polygon area centroid. (4) Rebuilds free the old icons at once. (5) A legend under the
    Settings checkbox explains +1 / +2 / LB. Tier A: scenario 66/66. Per terrain_id: the
    node, <= 8 px from its polygon centroid (computed in the step), modulate.a >= 0.8,
    label == cover_type_of == the legend for its category. The chips are switched on and
    off through the real Settings menu (Escape, Visual, checkbox, Escape). pixel_diff
    total 1.58% (> 1.0) and board region [574,100,772,950] 4.47% (> 1.0). On-screen scale
    1 at every tested zoom, no icon/token overlap, icons below the tokens, and the same
    checks after `TerrainManager.DEFAULT_LAYOUT` is loaded. New gated test
    `tests/test_terrain_cover_overlay.gd` (34 checks; 3 of 4 fail at HEAD). Gate 180/180
    (known XFAIL only). 17 reachable sp/visual scenarios pass; terrain_11e_layouts is a
    listed XFAIL; terrain_11e_menu_matchup fails identically at HEAD without this change
    (main-menu matchup dropdown and objective positions, unrelated).
    Deviations: (a) The opt-in decision stands, so the icons are not on by default; the
    scenario turns them on through Settings. (b) `cover_type` is derived
    (`TerrainManager.cover_type_of`), not stored on the terrain, and follows the 11e
    categories, so "+2" means light terrain (cover, and its area blocks sight lines), not
    a +2 modifier: 11e cover always worsens BS by 1. The Settings legend says what each
    glyph means. (c) co_pretrigger plays on legacy_fallback_mirror_1 (its layout_2 was
    deleted), the frozen copy of the default take_and_hold_mirror_1, so the scenario also
    loads `TerrainManager.DEFAULT_LAYOUT` and re-asserts nodes, centroids and labels.
    (d) The diff is taken at the fitted whole-board view, after closing P2's
    drawn-secondaries review, which otherwise covers the board. (e) The 8 coincident
    area/feature pairs keep both nodes (Tier A wants one per id) but render as one shield.

- [x] **T08 — Two-ring token (faction inner + player-slot outer)**
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
    - [x] Two rings visually distinct (different hue and thickness).
      *(T08_after, engagement zoom x3: a thin teal (P1) / magenta (P2) ring on the rim, a
      thicker crimson or gold band inside it, slate between them. Widths at zoom 1: 40mm
      base 3.5 vs 5.7 px, 32mm 2.8 vs 4.5 px; on an oval base (T08_oval_closeup) both rings
      follow the outline.)*
    - [x] Faction inner ring matches the army's chosen color.
      *(T08_army_panel: each unit's inner ring is the colour of its swatch in the Army
      Overview (U), the army-data colour from the faction palette; the scenario checks all 36
      tokens against their swatch. T08_change_color: after Pale gold is picked for the
      Custodian Guard in that panel, their four inner rings repaint pale gold. One colour per
      squad, not one per army — deviation (a).)*
    - [x] Player-slot outer ring is the same color across all units of that player.
      *(T08_p1_row / T08_p2_row: every P1 token — infantry, both dreadnoughts, the oval
      Caladius, both Witchseekers squads — wears the teal ring and every P2 token the magenta
      one; the scenario asserts SlotRing == the owner's slot colour on all 36 tokens.)*
    - [x] Rings do not occlude the central glyph/letter.
      *(T08_after: both rings sit in the outer quarter of the base and are painted beneath
      the art, so the Custodian sprite and the Witchseekers' WI* letter are untouched;
      glyph_p1 / glyph_p2 pixel_diff against the pre-T08 token: 0.0%.)*
  - **Note (2026-10-31 audit):** what had shipped were `FactionRing` / `SlotRing` as empty
    Node2D markers: they painted nothing (the only ring on screen was the letter style's
    single unit-colour ring), rested at alpha 0.35 / 0.7, and SlotRing was scaled 1.2, i.e.
    outside the base. The scenario (co_pretrigger, Custodes vs Orks) checked only that
    child(0) had both nodes, alpha > 0 and the scale order, so it passed with no ring drawn.
    T19's pulse tweened the invisible SlotRing, and MA-20's model-type ring sat on the rim
    where the outer ring belongs. Changed on this pass: the letter style (the default)
    paints both rings beneath the art (Layer 2c, replacing `_draw_unit_color_ring`), read
    from the ring nodes at paint time: modulate = colour, scale.x = mid-line radius / base
    radius (FactionRing 0.74, SlotRing 0.94), visible = painted. Widths max(3.5, 0.18r) and
    max(2.5, 0.11r), the outer edge held on the rim, both at alpha 1.0. FactionRing = the
    unit's stored army-data colour, SlotRing = `UIConstants.player_slot_color(owner)`; both
    re-read on every repaint, so Change Color and an owner change show. In the other unit
    styles and in debug mode the rings are not painted and the nodes report visible=false.
    `stop_pulse()` returns SlotRing to the resting alpha and the letter style repaints
    while it pulses (T19). The MA-20 ring moved just inside the slot ring. Tier A: scenario
    41/41 on mirror_custodes_postdeploy. All 36 tokens: SlotRing == the owner's slot
    colour, FactionRing == the unit's army-data colour (in the owner's faction palette),
    SlotRing.scale > FactionRing.scale, both alpha >= 0.9, both painted. A P1 Custodes
    token has FactionRing d9b333 (the Custodes gold, FactionPalettes primary) with SlotRing
    == FRIENDLY_PLAYER_TEAL. All 8 P2 Witchseekers have SlotRing == ENEMY_PLAYER_MAGENTA
    and FactionRing == their own army colour. Sampling the live frame on each ring's
    mid-line shows the node colours painted (slot 29-32/32 hits, faction 24-31/32; art and
    labels cover the rest). pixel_diff token_swatch 26.1% (> 8.0) against the pre-T08 token.
    The HEAD build and six scratch sabotage probes (constant slot colour, nothing painted,
    slot ring painted in the faction colour, inner band over the centre, no repaint sync,
    one colour per army) each turned a different set of checks red. New gated test
    `tests/test_two_ring_token.gd` (81 checks; 21 fail at HEAD). Gate 181/181 (known XFAIL
    only). Visual suite: 42 pass (baseline 41), failures only T23 / T27 / T39 (known) and
    T45 (XFAIL). 22 token sp scenarios: 19 pass, 3 listed XFAILs with their recorded counts.
    Deviations: (a) The inner ring is the unit's colour from the army data (a faction
    palette colour, auto-assigned per squad and changed with Right-click > Change Color or
    the army panel swatch), not one colour per army. The later Ring Only decision
    (v0.41.0 / v0.42.1) uses that ring to tell squads apart, and the roster cards show the
    same per-unit colour; one army colour would have erased both. The first squad of an army
    gets the palette primary (Custodes gold d9b333). A token with no unit falls back to
    `UIConstants.faction_color_for_player` (T41). (b) The only fixture with P1 Custodes +
    P2 Witchseekers is mirror_custodes_postdeploy: Witchseekers are an Anathema Psykana unit
    of the Custodes army (keyword ADEPTUS CUSTODES), so P2's colours come from the Custodes
    palette too and no "Witchseekers blue" exists in army data. The scenario asserts their
    own army colour plus MAGENTA instead, and that the mirror's shared inner colours are told
    apart by the slot ring. Setup privilege moves the P2 Witchseekers beside the P1
    Custodian Guard for one engagement-zoom frame. (c) Painted by the letter style only (the
    default, and the only style that had the single unit-colour ring); classic / enhanced /
    style_a / style_b keep their own rims. (d) The pre-T08 baseline is rebuilt in the run (no
    slot ring, one unit-colour band at the old ring's geometry); it matches the old build's
    render of the same frame at 0.0% in token_swatch, and old build vs new also diffs 26.1%.
    (e) T19's scenario now expects `stop_pulse()` to return the ring to `T08_RING_ALPHA`
    (1.0), not 0.7.

- [x] **T09 — Exhaustion grayscale for acted units**
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
    - [x] Acted unit is clearly dimmer than un-acted.
      *(T09_exhausted: the Shield-Captain and the Blade Champion, both ended this phase, are
      uniformly darker - base, art, rings, name plaque, wound bar - beside the full-brightness
      Custodian Guard row; their regions diff 80% against the same tokens lit in T09_after.)*
    - [x] Roster card mirrors the dim state.
      *(T09_exhausted: in the Roster strip (Roster button / B), "Blade Champion (1)" and
      "Shield-Captain (1)" are grey on a darker band and every other card is white; both card
      rows diff 100% against T09_before and T09_after, the Custodian Guard card 0.0%.)*
    - [x] Phase end resets both.
      *(T09_after, Shooting phase after End Movement Phase + its confirm prompt: both tokens and
      both cards are back to full brightness; all 25 tokens (1, 1, 1, 1), no card dim.)*
    - [x] Color rings (T08) still distinguishable on dimmed token.
      *(T09_exhausted: the dimmed tokens keep the teal rim and a gold (Shield-Captain) / crimson
      (Blade Champion) band. Sampled on the frame, the rings read 0.6 x their colours (slot
      28-32/32, faction 24/32 hits) and the two stay 0.54-0.61 apart in RGB.)*
  - **Note (2026-10-31 audit):** what had shipped was `TokenVisual.is_exhausted_this_phase`,
    `set_exhausted_this_phase()` and a reset on `phase_changed`, but nothing ever called the
    setter. No `unit_acted_in_phase` signal existed, so a confirmed move left the token at
    ffffffff (probed live at HEAD). Tokens Main rebuilds would have lost the state anyway, the
    roster strip had no dim state, and T38's Can Act filter read `flags.acted_this_phase`, which
    nothing set. The scenario called the setter by hand and emitted `phase_changed` itself: no
    END_UNIT_MOVE, screenshot, pixel_diff or roster check. Changed on this pass: `BasePhase`
    declares `unit_acted_in_phase(unit_id)` and `has_unit_acted_this_phase(unit_id)` (default
    false), and `execute_action()` emits the signal once per flip to true, before
    `action_taken` (not from an instance the action already swapped out). Each phase answers
    from synced flags. Movement: `flags.moved` of the active player's units (End This Unit's
    Move, Remain Stationary, ingress; a unit mid-move is not dim). Shooting: `flags.has_shot`
    of the active player's units. Charge: `units_that_charged` / `completed_charges` or
    `flags.charged_this_turn`. Fight: `units_that_fought` or `flags.has_fought`, either player.
    The new `UnitExhaustionTracker` (/root/Main/UnitExhaustionTracker, installed with the
    design-guidelines overlays) binds to the current phase's signal. It re-syncs every token and
    roster card on that signal, on `phase_action_taken`, on `GameManager.result_applied` (the
    network client path) and on `phase_changed`. `TokenVisual.refresh_exhaustion()` also runs
    in `_ready`, so rebuilt tokens start dim. It puts the dim back when another controller
    resets the modulate (the fight overlap feedback writes white when a consolidation drag
    ends). `LeftRosterStrip`: a dim card gets a darker StyleBoxFlat (0.05 grey, against the
    default 0.1) plus the 0.6 modulate (`is_card_exhausted()`). Can Act lists exactly the cards
    that are not dim. `refresh()` now detaches old cards before freeing them; a rebuild used to
    auto-rename the new `UnitCard_<id>`, and the name kept resolving to the dead card. Tier A:
    scenario 70/70 on audit_baseline_postdeploy. `expect_action_result` success for
    CONFIRM_UNIT_MOVE. The acted token is (0.6, 0.6, 0.6, 1) within 0.02 and exhausted, the other
    24 tokens (1, 1, 1, 1) and not. After End Movement Phase every token is (1, 1, 1, 1).
    pixel_diff acted_token 80.5% (> 15; 80.0% without the 2.6% of the region the Shooting
    phase's range line covers), the un-acted control token 0.0% (< 1). It also drives a second
    unit through the real End This Unit's Move button, the roster cards, the rebuild, and the
    rings on the dimmed frame. New gated test `tests/test_unit_exhaustion.gd` (62 checks: all four
    phases, the opponent's left-over flags, the attached character, the client path, the
    rebuild, Can Act, the reset). The scenario and the test each went red under scratch sabotage
    probes: no emit, no tracker, no owner check, no card dim, the wrong flag in Shooting, a 0.8
    dim, no `_ready` refresh, no `result_applied`, no rebind on phase change, no `remove_child`.
    Gate 182/182 (known XFAIL only). Visual suite: 42 pass (baseline 41), failures only T23 /
    T27 / T39 (known) and T45 (XFAIL). 20 related sp scenarios: 19 pass, and tut_t3_get_movin
    (a listed known failure) fails at its geometry step 101 (XFAIL). Deviations: (a) There is
    no END_UNIT_MOVE action. The action behind the End This Unit's Move button is
    CONFIRM_UNIT_MOVE, which the scenario
    dispatches (Tier A `expect_action_result`) and also reaches with a real click on that button
    for a second unit. (b) The roster card is the T37 LeftRoster strip card (the strip in doc §8,
    HUD-Left lock), not `ArmyPanel.gd`: that is the U modal colour and label editor, and its
    swatches must keep the true unit colours. The strip is hidden by default, so the scenario
    opens it with the Roster button. (c) The signal is declared once on `BasePhase` and emitted by
    its `execute_action()` from each phase's own answer (Movement, Shooting, Charge, Fight), not
    by hand in each phase file. Every path that ends a unit's step is covered: the button, AI,
    END_MOVEMENT's remain-stationary sweep. (d) "Grayscale" is the task's 0.6 modulate, a dim,
    not a desaturation. (e) Known gaps: on a network client a failed or skipped charge does not
    dim, since `units_that_charged` is host-only (a successful charge does, via
    `charged_this_turn`). An opponent's reactive move in your Movement phase does not dim either,
    because its `flags.moved` is left over from its own turn. The client path is verified
    headless only (`GameManager.apply_result`), not in a two-instance game.

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

- [x] **T35 — Persistent right-side roll log** *(removed — superseded by
  per-phase `dice_log_display` in ShootingController / FightController /
  MovementController, which render the same `DiceHistoryPanel` rolls
  inline. RollLogPanel was redundant.)*

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

## Follow-up: Tutorials — re-author for the rotated 11e layouts (2026-10-26)

- [ ] The 11e terrain layouts and deployment zones were rotated to the official
  orientation (branch `claude/friendly-mccarthy-f4c0ws`; the 40kdc converter
  used to transpose = mirror them). The tutorials pin `take_and_hold_mirror_1`
  (`40k/data/tutorials/lessons/T2_deployment.json`) and their lessons/fixtures
  (`40k/data/tutorials/fixtures/*.w40ksave`) script positions and left/right
  wording against the old mirrored geometry, so the guidance is now wrong for
  players. Mirror the lesson coordinates and fixture unit positions
  (x -> 1760 - x px / 44 - x in), swap left/right wording, then delist
  `tut_t2_*`, `tut_t3_*`, `tut_t4_*` and `pad_nested_panel_walk` from
  `40k/tests/scenarios/_known_failures.txt` once their scenarios pass.
