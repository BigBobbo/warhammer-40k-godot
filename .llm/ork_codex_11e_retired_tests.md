# Codex: Orks (11e) — retired / rewritten tests

Data refresh of 2026-10-12 (dataset 1.4.5 + `scripts/40kdc/curated/orks_codex_11e.json`,
see `.llm/ork_codex_11e_design.md` §1-§2). The 10e-era Ork content below no longer
exists in Codex: Orks (11th edition): the More Dakka!, Freebooter Krew, Rollin' Deff
and Speedwaaagh! detachments are gone, and every Ork stratagem row is now one of the
40 codex stratagems. Each retired scenario was run against the new data before it
was deleted; the failure (or, for Speedwaaagh!, the dead-code pass) is noted.

## Deleted windowed scenarios (`40k/tests/scenarios/sp/`)

| file | reason |
|---|---|
| `more_dakka_bursts.json` | More Dakka! detachment removed; its LONG, UNCONTROLLED BURSTS is now a different Flyboyz stratagem. New data: 6 failed (panel row `faction_ork_more_dakka!_…` gone, 0 implemented). |
| `rollin_deff_devastating_drift.json` | Rollin' Deff detachment and DEVASTATING DRIFT removed. New data: 6 failed. |
| `speedwaaagh_turbo_boostas.json` | Speedwaaagh! detachment (Turbo Boostas rule) removed. Still passed 23/0 only because it flips the detachment itself and drives dead FactionAbilityManager code. |
| `da_big_hunt_drag_it_down.json` | DRAG IT DOWN (10e Da Big Hunt) not in the codex. New data: 7 failed. |
| `fight_proppa_choice.json` | FIGHT PROPPA (10e Taktikal Brigade) not in the codex. New data: 8 failed. |
| `green_tide_competitive_streak.json` | COMPETITIVE STREAK stratagem (10e Green Tide) not in the codex (the name is now a Kult of Speed enhancement). New data: 6 failed. |
| `taktikal_retreat_panel.json` | TAKTIKAL RETREAT (10e Taktikal Brigade) not in the codex. New data: 8 failed. |
| `blitz_brigade_mount_up_ladz.json` | MOUNT UP, LADZ (old Blitz Brigade six) replaced by the codex trio. New data: 6 failed. |
| `dread_mob_klankin_klaws.json` | KLANKIN' KLAWS (old Dread Mob six, push-it choice) replaced by the codex trio. New data: 10 failed. |
| `fullauto_fight_stratagems.json` | War Horde UNBRIDLED CARNAGE + 'ARD AS NAILS (10e stopgaps) removed; UNBRIDLED CARNAGE is now a Green Tide stratagem with a different effect. New data: 5 failed ("Unknown stratagem: faction_ork_war_horde_unbridled_carnage"). |

`40k/tests/coverage.json`: the 18 tiles that only described removed content were
dropped; 12 tiles whose engine/UI capability still exists but lost their only backing
scenario were set to `"status": "uncovered"` with a note (stratagem choice dialog,
friendly target picker, embark-via-stratagem, curated effects_json, minus-one-wound
defence, melee-scoped lethal hits, target-condition enforcement, and the
Blitz/Da Big Hunt/Dread Mob/Green Tide/Taktikal "loading" tiles). The windowed
`ork11e_<slug>` scenarios of the next step should re-cover them.

## Rewritten (content still exists)

| file | change |
|---|---|
| `scenarios/sp/fullauto_movement_stratagems.json` | Dropped the War Horde 'ERE WE GO half (10e stopgap; the codex moved 'ERE WE GO to Green Tide as +2 to advance rolls). The Da Jump half is unchanged. Covers tags `stratagems.war_horde.ere_we_go` and `autoloads.FactionStratagemLoader.curated_effects` removed. |
| `scenarios/sp/recon_stomps_base_army.json` | recon_stomps is migrated to Kult of Speed: asserts `Kult of Speed`, Smoky Gubbinz on Wartrike A, no enhancement on the Mek (Dakkamek is gone). |
| `scenarios/sp/taktikal_enhancements_load.json` | Stratagem-count step now asserts the 3 codex Taktikal Brigade rows are loaded (`get_faction_stratagems_for_player(2).size() == 3`) instead of 6 implemented 10e rows. Enhancement asserts unchanged. |
| `tests/test_loadout_resolution.gd` | New army `ork11e_codex_test.json` is excluded from the two Task C ratchet COUNTS only (its Flash Gitz / Killa Kans / Tankbustas multi-profile guns are data-limited over-counters); every per-unit invariant still runs on it. |
| `tests/test_fullauto_faction_rules.gd` (pretrigger) | War Horde half now asserts the 6 codex rows (custom:ork11e marker) instead of the 10e stopgaps' effects (UNBRIDLED CARNAGE crit 5+, MOB RULE, ORKS IS NEVER BEATEN swing-back). Shield Host half unchanged. |
| `tests/unit/test_plan_*.gd`, `tests/unit/test_ai_plan_*.gd`, `tests/fixtures/ai_plans/fixture_recon_stomps_rich.json`, `data/ai_plans/orks_free_grab_grip_hammer_anvil.json`, `tests/exams/slow/sc02_screen_covers_the_gap.json` | detachment `Speedwaaagh!` -> `Kult of Speed` (recon_stomps and the 2000-pt fixtures were migrated). |
| `tests/saves/{mirror_orks_2000,asym_2000}_{pre,post}deploy`, `staleboard_orks_2000_predeploy`, `bw_load_deploy_pretrigger` (+ `.meta`) | Ork side migrated like the army files (Kult of Speed / Blitz Brigade, enhancements, points). Boards untouched. |

## Deleted headless tests (`40k/tests/`, `40k/tests/unit/`, with their `.uid`)

| file | reason |
|---|---|
| `test_speedwaaagh_stratagems.gd` | Speedwaaagh! stratagems (SPESHUL AMMO, DED KILLY CONSTRUCTION) — detachment removed. Passed 9/0 only on its own fixture (dead code). |
| `test_speedwaaagh_enhancements.gd` | Speedwaaagh! enhancements (Kustom Shokk Box, Supa-burny Fuel, Dakkamek, Master Meknologist) — detachment removed. Passed 14/0 (dead code). |
| `test_evasive_manoova.gd` | EVASIVE MANOOVA (Speedwaaagh!) — removed. Passed 6/0 (dead code). |
| `test_mobile_dakkastorm.gd` | MOBILE DAKKASTORM (Speedwaaagh!) — removed. Passed 7/0 (dead code). |
| `test_dakkamek.gd` | Dakkamek enhancement (Speedwaaagh!) — removed. Passed 5/0 (dead code). |
| `test_kustom_shokk_box.gd` | Kustom Shokk Box enhancement (Speedwaaagh!) — removed. Passed 8/0 (dead code). |
| `test_careen_resolve_390.gd` | CAREEN! (10e War Horde stopgap) — not in the codex War Horde. Passed 6/0 on its own fixture (dead code). |
| `test_taktikal_stratagems.gd` | FIGHT PROPPA / KRUNCHIN' DESCENT / DAT'S OURS / TAKTIKAL RETREAT / ON TO DA NEXT / DED SNEAKY (10e Taktikal Brigade) — replaced by the codex trio. New data: 31 passed / 31 failed. |
| `unit/test_boardin_rush_stratagem.gd` (GUT) | BOARDIN' RUSH (Freebooter Krew) — detachment removed. New data: 5 failing tests. |
| `unit/test_deck_fraggers_stratagem.gd` (GUT) | DECK FRAGGERS (Freebooter Krew) — removed. New data: 9 failing tests. |
| `unit/test_rolling_loot_heap_stratagem.gd` (GUT) | ROLLING LOOT-HEAP (Freebooter Krew) — removed. New data: 9 failing tests. |

Rewritten GUT tests in `unit/test_faction_stratagems.gd`:
`test_shipped_detachment_stratagems_fully_implemented` (War Horde half now asserts the
six codex rows + custom:ork11e marker; Shield Host half unchanged) and
`test_careen_timing_column_overrides_epic_deed_default` ->
`test_epic_deed_timing_column_overrides_once_per_battle_default` (same loader
behaviour, pinned on ONLY IN DEATH DOES DUTY END since CAREEN! is gone).

## Kept, failing because of removed content (not gated: outside run_pretrigger_tests.sh and the GUT dirs)

| file | status | why kept |
|---|---|---|
| `test_ork_detachments_sweep.gd` | 250 passed / 43 failed (was 293/0) | Every failure is a 10e stratagem check (Green Tide/More Dakka!/Bully Boyz/Da Big Hunt/Kult of Speed/Dread Mob rows that the codex replaced). Its passing half still pins detachment-rule and enhancement code that runs in game today; superseded by the per-group `test_ork_codex_<group>.gd` of the next step. |
| `test_p0_stratagems_375.gd` | rc=1 before AND after | Pre-existing failure ("expected PLUS_ATTACKS.value=2, got 1"); mixes Custodes parser checks with 10e War Horde stopgap text. |

## Windowed scenarios expected to fail until the Ork codex registry lands (NOT retired — the stratagem names still exist)

| file | status |
|---|---|
| `bully_boyz_armed_to_da_teef.json` | 11 passed / 5 failed: asserts the 10e S-panel flow (`get_implemented_faction_stratagems_for_player == 6`, target picker, `effect_reroll_hits == ones`). The codex ARMED TO DA TEEF is a `unit_selected_to_shoot/fight` window stratagem and is not implemented yet (custom:ork11e). Needs rewriting as `ork11e_armed_to_da_teef`. |
| `kult_of_speed_speediest_freeks.json` | 13 passed / 6 failed: same — 10e panel flow + 5+ invuln effect; the codex SPEEDIEST FREEKS is an `enemy_targets_unit_shooting` window stratagem ("fail on unmodified 1-3"). Needs rewriting as `ork11e_speediest_freeks`. |
