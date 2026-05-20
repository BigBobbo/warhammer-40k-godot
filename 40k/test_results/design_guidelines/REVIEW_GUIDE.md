# Tier B visual review guide — T01–T45

All 45 design-guidelines tasks pass Tier A (machine-checkable) on this branch
(`claude/research-strategy-game-design-bYYdT`). What remains is the Tier B
visual review: a human walks each task in a windowed Godot session, ticks
the per-task observables in `.llm/todo.md`, and confirms the on-screen result
matches the design doc intent. This file is the walkthrough script for that
session.

## Pre-known refinement gaps (read before starting)

A cloud-session pre-pass through the artifacts identified objectively-
verifiable Tier B items and ticked 29 of 114 boxes in `.llm/todo.md`, plus
fully closed 5 tasks (T02, T27, T29, T32, T38). The remaining 85 items need
windowed eyes, including these known-incomplete behaviors that **will
fail review** unless implemented as follow-up `T##b` tasks:

| Task | Failing Tier B item | What's missing |
| --- | --- | --- |
| T06 | "ESC dismisses without committing" | WeaponOrderPanel has a Cancel button but no ESC binding in Main._input |
| T09 | "Roster card mirrors the dim state" | T09 ships TokenVisual modulate only — ArmyPanel/roster card dim is not wired |
| T13 | "Animation smooth (no jump)" | fit_view_to_board sets camera position/zoom instantly; no tween |
| T17 | "Hover expands chip to show the hidden statuses" | OverflowChip is a static Label; no hover-expand behavior |
| T20 | "ESC dismisses" | EpicChallengePanel has no ESC binding |
| T21 | "Allocation buttons functional" | WoundAllocationPanel.Commit is a stub — no real allocation logic |
| T36 | "ENTER fires the attack" | commit_targets() flips targets_committed=true but doesn't trigger resolution downstream |
| T42 | "Stripes visible on the warning overlay" | striped_pattern() exists but isn't applied to any overlay (ThreatOverlay still uses solid yellow) |

For each, file `T##b` in `.llm/todo.md` during the review and proceed.
Do NOT revert the parent commit — the Tier A is intact and the gap is
additive scope.

## Setup

```bash
cd /path/to/warhammer-40k-godot
git pull origin claude/research-strategy-game-design-bYYdT
# Fresh checkout? Populate Godot's class cache:
godot --headless --editor --path 40k --quit-after 2
# Smoke-check that the suite passes here too:
bash 40k/tests/run_scenarios.sh --visual   # exit 0, "baseline count: 45  passing: 45"
```

Open the Godot editor (`godot --editor --path 40k`) and run the scene. For
each task below, the "Demo" column lists either a fixture-driven scenario
to run, or the in-game action that exercises the feature.

## Review checklist format

For each T## task:

1. Open `.llm/todo.md` and find the task's `Acceptance — Tier B (visual
   checklist)` block (3–5 yes/no items).
2. Load the relevant fixture or run the scenario via the Godot editor's
   command palette (`godot --path 40k --scenario-file=tests/scenarios/visual/T##_*.json`).
3. Compare against `40k/test_results/design_guidelines/T##/T##_*after.png`
   (the screenshot the cloud session captured).
4. Tick each Tier B box that holds in the windowed session.
5. If any Tier B item fails, file a `T##b` follow-up task; do NOT revert the
   T## commit (the code shape and Tier A are validated).
6. When all Tier B items for T## are ticked, flip its line in `.llm/todo.md`
   from `- [ ]` to `- [x]` and commit `tick T##`.

## Walkthrough order

Walk in **task-number order** (T01, T02, T03, ..., T45). Tasks within
the same numeric block can share a session if they touch the same scene.

### Foundation (parallelizable, no fixture needed)

| Task | What to look at | Cloud screenshot |
| --- | --- | --- |
| T01 | UIConstants autoload color slots; striped_pattern texture | T01/T01_uiconstants_present_T01_after.png |
| T02 | The harness machinery itself — `bash run_scenarios.sh --visual` exits 0 | T02/T02_harness_self_check_T02_after.png |

### HUD overlays — main scene

Run `co_pretrigger` fixture in the editor (Movement/Shooting/Charge/Fight
phase 7/8/9/10). All overlays self-install on Main._ready.

| Task | What to look at | Demo / cloud screenshot |
| --- | --- | --- |
| T03 | Drag a model — colored segments green/yellow/red by budget | exec compute_drag_segments in console |
| T04 | Top-center phase bar, six pills, active one in active-player color | T04/T04_phase_bar_T04_command.png |
| T05 | Hover an enemy with shooter selected → tooltip with BS/S/T/AP/D | T05/T05_hover_forecast_T05_after.png |
| T06 | Trigger weapon-order — side panel (right column), board still visible | T06/T06_weapon_order_panel_T06_after.png |
| T07 | Shield-shaped cover icons on every terrain piece (+1/+2/LB) | T07/T07_terrain_cover_icons_T07_overlay_on.png |
| T08 | Each token has two concentric rings (faction inner + slot outer) | T08/T08_two_ring_token_T08_after.png |
| T09 | After a unit acts, its token + roster card dim to grey | T09/T09_exhaustion_grayscale_T09_after.png |
| T10 | Hold Tab — yellow/red threat rings on every enemy unit | T10/T10_threat_overlay_T10_after.png |
| T11 | Hover an enemy with shooter selected → green/yellow/red LOS line | T11/T11_los_line_T11_after.png |
| T12 | Existing overlays still use the same visible color palette | T12/T12_color_audit_T12_after.png |

### Camera & navigation

| Task | What to look at | Demo |
| --- | --- | --- |
| T13 | Press F → whole board fits with margin | T13/T13_fit_board_T13_after.png |
| T14 | Select a unit, press Shift+F → camera zooms+centers on it | T14/T14_fit_selection_T14_after.png |
| T22 | Open any side panel (T06/T20/T21) → camera auto-zooms | T22/T22_auto_zoom_decision_T22_after.png |

### Token chrome (TokenVisual extensions)

| Task | What to look at | Demo |
| --- | --- | --- |
| T15 | Each token shows a silhouette (infantry/tank/walker/...) | T15/T15_silhouettes_T15_after.png |
| T16 | Zoom out to <0.6 → token labels disappear | T16/T16_label_zoom_hide_T16_after.png |
| T17 | Apply 5 statuses to a unit → 3 icons + "+2" overflow chip | T17/T17_status_overflow_T17_after.png |
| T18 | Multi-wound model → "N/M" chip at base edge; single-wound: nothing | T18/T18_wound_chip_T18_after.png |
| T19 | Active unit's outer slot ring pulses (2s loop, subtle) | T19/T19_active_pulse_T19_after.png |

### Side panels & canonical buttons

| Task | What to look at | Demo |
| --- | --- | --- |
| T20 | Epic Challenge prompt as a right-column panel, not centered modal | T20/T20_epic_challenge_panel_T20_after.png |
| T21 | Wound Allocation as a right-column panel | T21/T21_wound_panel_T21_after.png |
| T23 | End-Phase button bottom-right, same position across every phase | T23/T23_end_phase_position_T23_after.png |
| T27 | Same as T23 (re-asserts in Fight phase) | T27/T27_end_phase_refactor_T27_after.png |

### Phase bar features

| Task | What to look at | Demo |
| --- | --- | --- |
| T24 | Active phase pill has a substate breadcrumb row beneath | T24/T24_substate_breadcrumb_T24_with_breadcrumb.png |
| T25 | 4px frame around the play area in active-player color | T25/T25_edge_tint_T25_p2_active.png |
| T26 | Click a past pill → tooltip "completed", no phase change | T26/T26_phase_pill_clicks_T26_after.png |

### Movement & charge ranges

| Task | What to look at | Demo |
| --- | --- | --- |
| T28 | Selected unit → green inner disc + yellow outer ring | T28/T28_two_layer_range_T28_after.png |
| T29 | Engaged units always show a faint orange ring (no selection needed) | T29/T29_persistent_engagement_T29_after.png |
| T30 | Declare a charge → two dashed rings (12" + 7"); roll → solid ring | T30/T30_charge_dashed_rings_T30_after.png |
| T31 | Press R → ruler tool active; drag a line; ESC exits | T31/T31_ruler_tool_T31_drawn.png |

### Debug, dice, damage

| Task | What to look at | Demo |
| --- | --- | --- |
| T32 | Hold L → LoS debug visible; release → gone. Top bar has no LoS button | T32/T32_los_debug_held_T32_after.png |
| T33 | Resolve shooting → compact top-center dice surface, board visible | T33/T33_resolution_surface_T33_after.png |
| T34 | Wounds applied → "-NW" / "-N models" floats over target | T34/T34_floating_damage_T34_after.png |
| T35 | Right-column roll log always visible; new entries append | T35/T35_roll_log_T35_two_entries.png |
| T36 | Click enemy → highlighted as pending; ENTER → resolution fires | T36/T36_explicit_commit_T36_after.png |

### Roster & datasheet

| Task | What to look at | Demo |
| --- | --- | --- |
| T37 | Left-edge vertical strip with one card per unit; click pans | T37/T37_roster_strip_T37_after.png |
| T38 | Filter chips (All / Can Act / Engaged / Below Half) above roster | T38/T38_filter_chips_T38_after.png |
| T39 | Press `i` with unit selected → centered datasheet modal; ESC dismisses | T39/T39_datasheet_modal_T39_open.png |
| T40 | Stats panel updates on enemy hover (cover delta visible) | T40/T40_prospective_panel_T40_after.png |

### Color & motion audits

| Task | What to look at | Demo |
| --- | --- | --- |
| T41 | Faction colors and slot colors are visually distinct everywhere | T41/T41_faction_vs_slot_T41_after.png |
| T42 | Warning yellow renders as stripes (not solid) | T42/T42_striped_yellow_T42_after.png |
| T43 | At most one bright-orange CTA per screen | T43/T43_orange_audit_T43_after.png |
| T44 | No animation feels too long; pulse is ~2s; dice ≤1.5s | T44/T44_motion_budget_T44_after.png |
| T45 | Final pass — every overlay node is wired into /root/Main | T45/T45_final_audit_T45_after.png |

## What to do if a Tier B item fails

- **Visual choice mismatch** (color, position, sizing): open a `T##b` task
  in `.llm/todo.md` describing the refinement. Don't revert.
- **Behavioral bug** (e.g. F doesn't actually fit the board on this dev
  machine): run the scenario with `--scenario-file=...` and see if Tier A
  still passes. If yes, it's a host-input pipeline issue; the test-seam
  pattern documented in `40k/tests/scenarios/visual/_schema.md` is the
  fallback.
- **Performance regression** (e.g. roster strip pegs CPU at 100%):
  immediate revert of the offending commit (`git revert <hash>`) is
  warranted; refile with a new task that addresses the perf concern.

## What to do once Tier B is complete for all 45 tasks

1. Every line in `.llm/todo.md` is `- [x]`.
2. Update `_baseline.json._last_refreshed_commit` to the tick-batch commit.
3. Update the design doc's Status header with the closure summary (T45's
   "non-machine" Tier B bullet).
4. Open a PR titled "Design guidelines 2D top-down: T01-T45" with the
   change-summary from each `[T##]` commit body collated.

Reference: `40k/docs/design_guidelines_implementation_plan.md` for the
playbook; `.llm/todo.md` for the per-task Tier B checklists.
