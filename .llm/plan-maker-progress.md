# AI Plan Maker — progress log

One line per task: status, key result, timestamp (UTC). Companion to
`.llm/plan-maker-todo.md`.

| Task | Status | Key result | When |
|---|---|---|---|
| PM-5 | DONE | `PlanRecorder.gd` serialises a live deployment into a valid plan (order from `phase_log`, px→inches, reserves/embark/attach lifted out, anchors derived) + a `Save as Plan` dialog that refuses invalid plans in-place. Headless 47/47 with an exact record→consume round trip for both seats; windowed `sp/pm5_record_and_save_plan` 49/49 recording all 17 units at 0.0056" fidelity and round-tripping the saved FILE at 5.4e-06". Version 1.31.0 | 2026-08-11 |
| PM-4 | DONE | Main-menu "Plan Editor" opens a solo sandbox: own zone picker, `plan_editor` in `meta.game_config`, P2 units deleted, real FORMATIONS for the target army with the absent seat auto-confirmed, roll-off auto-resolved with P1 as Defender, hotseat handoff suppressed, and one guard in `PhaseManager._on_phase_completed` holds DEPLOYMENT open. Windowed `sp/pm4_plan_editor_session` 55/55 from the main menu with a negative control proving the hold comes from the flag; 0 log errors. Version 1.30.0 | 2026-08-11 |
| PM-0 | DONE | `wh40k_ai_plan` v1 schema + `PlanValidator.gd` + 2 fixtures + 65-assertion headless test (65 passed, 0 failed) | 2026-08-11 |
| PM-3 | DONE | Five verbs bias real machinery (HOLD/PUSH via `_t_add`, SCREEN withholds into the screening pass, HUNT adds to all three target scorers), release-on-damage decay, fragment layering with explicit-profile precedence. Headless 35/35 incl. a real assignment differential; windowed `sp/pm3_earmarks_bias_assignment` 72/72 with 0 earmark records in the plans-off control. Version 1.29.2 | 2026-08-11 |
| PM-2b | DONE | Plan drives FORMATIONS: reserves (plan owns them, over-cap trimmed in plan order), embarkations, attachments; PLACE_IN_RESERVES retrofit for post-formations games. Headless 27/27, windowed `sp/pm2b_formations_from_plan` 36/36 with both seats exact. Version 1.29.1 | 2026-08-11 |
| PM-2a | DONE | AI follows a plan's deployment order + per-model placement, mirroring `[44-x, 60-y]` at seat 2, degrading per unit to the formula. Headless 34/34; windowed `sp/pm2a_ai_deploys_from_plan` 41/41 with 22/22 units at 0.000" and 11 plan records per seat; `BENCH_P1_PLAN`/`BENCH_P2_PLAN` plumbing. Version 1.29.0 | 2026-08-11 |
| PM-8a | DONE | Spike: in-session multi-game reset VIABLE. 3 from-menu AI-vs-AI games in one process, ~10-14s each; two same-seed games byte-identical — but only after extending the reset list (AI quiesce first, FactionAbilityManager, global RNG as a 4th seed channel, log accumulators). Report: `tests/bench_baselines/2026-08-11_pm8a_inline_reset_spike.md` | 2026-08-11 |
| PM-1 | DONE | `PlanManager.gd` storage/listing/matching; game_config + faction-fallback identity; `_P<player>` mirror re-key resolution (55 passed, 0 failed) | 2026-08-11 |
