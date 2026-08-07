# Regression check — engine changes of 2026-08-07

Run after: the Heroic Intervention deadlock fix, the seeded AI-layer RNG, the
`vp_diff` rewire, and 22 coefficient promotions.

**25 windowed scenarios, 799 assertions, 0 failures.**

Selected by `covers` tag over exactly the systems touched — `phases.ChargePhase`,
`scripts.AIDecisionMaker`, `autoloads.AIPlayer`, `scripts.ChargeController`.

| scenario | assertions |
|---|---|
| attached_char_charge_drag_leader | 58 |
| charge_click_board_target / charge_multi_step_movement | 54 each |
| charge_drag_clamps_to_roll / charge_group_drag_multi_select | 53 each |
| charge_per_model_range_rings | 38 |
| ai_shooting_stall_defender_lock / charge_move_model_rotation_visual | 35 each |
| auto_consolidate_closest_opponents | 33 |
| hi_attached_char_not_offered_11e / iss15_heroic_intervention_fray_11e | 31 each |
| tut_t5_click_board_target | 29 |
| auto_pile_in_closest_opponents | 27 |
| attached_char_untargetable_11e / hi_window_ai_must_not_hijack_11e | 26 each |
| **hi_abort_move_releases_phase** (new) | **25** |
| iss042c_coherency_ai_turn_no_hijack_11e | 24 |
| memops_ai_vs_ai_bounded | 23 |
| charge_units_filtered_by_target_in_range | 21 |
| iss049_charge_11e | 19 |
| attached_char_charge_no_overlap | 18 |
| iss15_heroic_intervention_decline_11e | 17 |
| ai_thinking_dupe_display_names | 14 |
| iss062_ai_11e | 13 |
| ai_moment_shackle_window | 12 |

## Two false alarms, both mine

- `iss062_ai_11e` first reported "1 passed, 3 failed". It contains 150 s of
  scripted `wait_seconds`, and I had wrapped each scenario in a 200 s timeout —
  the kill truncated it. With headroom it passes 13/13.
- The batch runner appeared to hang on `ai_moment_shackle_window`. It was not
  hung; `run_scenarios.sh` has **no per-scenario timeout**, so a slow scenario
  (~2–3 min) is indistinguishable from a stuck one in its output. It passes 12/12.

Worth fixing in the runner itself: a per-scenario timeout would have made both
of these obvious immediately.
