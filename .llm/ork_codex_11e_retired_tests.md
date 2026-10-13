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
| `test_ork_detachments_sweep.gd` | **rewritten 2026-10-13 (RG-F4)** — see the section below; now 194 passed / 0 failed | — |
| `test_p0_stratagems_375.gd` | rc=1 before AND after | Pre-existing failure ("expected PLUS_ATTACKS.value=2, got 1"); mixes Custodes parser checks with 10e War Horde stopgap text. |

## Windowed scenarios expected to fail until the Ork codex registry lands (NOT retired — the stratagem names still exist)

| file | status |
|---|---|
| `bully_boyz_armed_to_da_teef.json` | DELETED — rewritten as `ork11e_armed_to_da_teef.json` (unit_selected_to_fight window, re-roll hit rolls of 1). |
| `kult_of_speed_speediest_freeks.json` | DELETED — rewritten as `ork11e_speediest_freeks.json` (enemy_targets_unit_shooting fold-in, unmodified hit rolls of 1-3 fail). |

## Final clean-up (2026-10-13)

### `tests/test_ork_detachments_sweep.gd` — 10e stratagem sections removed (RG-F4)

Before: 250 passed / 43 failed (rc 1). After: **194 passed / 0 failed** (rc 0).
Removed 134 checks — all 43 failures plus 91 passing checks that drove the
legacy 10e handlers directly (`SM._apply_stratagem_effects(..., {"effects":
[{"type": "custom:<10e slug>"}]})`) or the RulesEngine/FallBackMove/MovementPhase
consumers of flags only those handlers set (no Codex: Orks 11e row can reach
them: Ork rows are `custom:ork11e` and dispatch by csv_id). The helpers
`_fight_vs` (DRAG IT DOWN) and `_shootback_board` (CALL DAT DAKKA?) went with
them. Each section now carries a one-line retirement note.

| section | removed checks (count) |
|---|---|
| Green Tide (14) | 6-row load/implemented + BULLDOZER target parse; BRAGGIN' RIGHTS x3, COME ON LADZ!, COMPETITIVE STREAK x3, TIDE OF MUSCLE x2, BULLDOZER BRUTALITY 3" melee eligibility x2 |
| More Dakka! (12) | 6-row load/implemented, GET STUCK IN LADZ! cost + handler x2, HUGE SHOW-OFFS target + handler, SPESHUL SHELLS x3, ORKS IS STILL ORKS, CALL DAT DAKKA? |
| Bully Boyz (14) | 6-row load/implemented, ARMED TO DA TEEF / HULKING BRUTES parses, Meganobz target match, legacy ARMED TO DA TEEF x2, ALWAYS LOOKIN' x2, CRUSHING IMPACT, TOO ARROGANT TO DIE flag, CUT' EM DOWN x3 (incl. FallBackMove `effect_cut_em_down`) |
| Da Big Hunt (15) | 6-row load/implemented, STALKIN' TAKTIKS / INSTINCTIVE HUNTERS parses, WHERE D'YA FINK straight-apostrophe lookup, DAT ONE'S EVEN BIGGA! x2, DRAG IT DOWN x2, legacy INSTINCTIVE HUNTERS, UNSTOPPABLE MOMENTUM x2, STALKIN' TAKTIKS x2 |
| Kult of Speed (20) | 6-row load/implemented, SPEEDIEST FREEKS / MORE GITZ parses + lookup, legacy SPEEDIEST FREEKS (5+/4+ invuln) x4, SQUIG FLINGIN' x2, BLITZA FIRE x3, DAKKASTORM (`effect_dakkastorm_kos`) x3, FULL THROTTLE!, MORE GITZ Scatter! window x2 |
| Dread Mob (27) | 6-row load/implemented, BIGGER SHELLS / DAKKA!x3 / EXTRA GUBBINZ parses + 4 target matches, BIGGER SHELLS x7, DAKKA!x3 x2, KLANKIN' KLAWS x3, EXTRA GUBBINZ / SUPERFUELLED BOILER effects_json, CONNIVING RUNTS x4 (incl. Scatter! window) |
| Blitz Brigade (20) | 6-row load/implemented, IMPERVIOUS / YOOZ / MOUNT UP parses + 2 target matches, ARMOURED DUELLISTS x3, IMPERVIOUS x2, MEKANISED BRUTALITY disembark, MOUNT UP LADZ x2, RUN 'EM DOWN x3, YOOZ IN TROUBLE NOW x2 |
| Rollin' Deff (12) | 5-row load/implemented, BRUTAL BROADSIDE, IMPENDING CRUNCH x2, DEVASTATING DRIFT x2, SPESHUL SHELLS (RD/MD) x4, LONG UNCONTROLLED BURSTS effects_json |

Rewritten / added: a `CODEX: ORKS (11e) STRATAGEM ROWS` section (35 checks): each
of the 15 codex detachments loads its codex row count (War Horde 6, Madcap Meks 1,
Wurrband 0, Brute Bosses 0, every other 3; 40 in total), every row is
`custom:ork11e` and implemented by the codex registry, and More Dakka! / Rollin'
Deff / Freebooter Krew / Speedwaaagh! load none. One kept label was reworded
("unit_counts_as_10 true via the effect_counts_as_10 flag (Raucous Warcaller)" —
BRAGGIN' RIGHTS no longer sets it).

Kept (unchanged): every detachment-rule and enhancement check (Prey, Mob
Mentality, keyword grants, Dakka!x3, Adrenaline Junkies, Eager for the Fight,
Thundering Wagons, Try Dat Button!, Taktiks + Gob Boomer, Turbo Boostas, Da Boss
Is Watchin', and the enhancement helpers of every section), the hazard-roll
modifier primitive (now used by WHERE D'YA FINK YOU'RE GOING?'s extra hazard
rolls) and the `effect_improve_leadership` consumer. Note: the More Dakka!,
Rollin' Deff and Speedwaaagh! rule/enhancement checks that stay pin helpers that
no shipped detachment reaches any more (same status as the deleted Speedwaaagh!
tests above) — candidates for a later retirement. Pre-existing, unchanged: the
"Boss Watchin: used-latch survives save/load" check never runs —
`FactionAbilityManager.save_state()` does not exist, so `_detachment_rules`
stops at that line with a SCRIPT ERROR (same on base e28e4f7).

### Windowed scenarios with a stale `'ARD AS NAILS` decline (RG-F1)

`aao_lions_isolated_plus_one`, `cover_hit_label_wound_reroll_11e`,
`game_log_armour_saves_11e` (and `game_log_armour_saves_no_kill_11e`, whose decline
step had no assert) use fixture `custodes_lions_pretrigger` (P2 = War Horde Orks).
They dispatched `DECLINE_REACTIVE_STRATAGEM` after `CONFIRM_TARGETS` to dismiss
the 10e War Horde 'ARD AS NAILS reactive window. Codex: Orks (11e) has no War
Horde stratagem in `enemy_targets_unit_shooting`, so no window opens
(`get_window_offers(P2, enemy_targets_unit_shooting) -> 0 offer(s)`) and the
decline failed with "Not waiting for reactive stratagem decision". The step is
now a conditional `execute_script` that declines only while
`awaiting_reactive_stratagem` is true. Every other assertion is unchanged; all
four pass (29/0, 37/0, 48/0, 39/0).

### `tests/coverage.json`

- Repointed: `fight.stratagem.armed_to_da_teef`, `stratagems.bully_boyz.loading`
  → `ork11e_armed_to_da_teef`; `fight.stratagem.speediest_freeks`,
  `stratagems.kult_of_speed.loading` → `ork11e_speediest_freeks`;
  `ui.StratagemPanel.faction_rows` → `ork11e_armed_to_da_teef`,
  `ork11e_no_stale_boot_stratagems`.
- Re-covered (10 of the 12 tiles d3e1296 marked uncovered; the tile id is now in
  the scenario's `covers`): `stratagems.blitz_brigade.loading` +
  `transport.embark_via_stratagem` → `ork11e_keep_it_runnin`;
  `stratagems.da_big_hunt.loading` → `ork11e_instinctive_hunters`;
  `stratagems.dread_mob.loading` → `ork11e_crazed_rampage`;
  `stratagems.green_tide.loading` → `ork11e_unbridled_carnage`;
  `stratagems.taktikal_brigade.loading` → `ork11e_mind_mostly_on_the_mission`;
  `ui.Main.stratagem_choice_dialog` → `ork11e_dubious_restraint`;
  `ui.StratagemPanel.friendly_target_picker` +
  `autoloads.StratagemManager.target_condition_enforcement` → `ork11e_dread_power`;
  `rules.melee_scoped_lethal_hits` → `ork11e_hit_em_harder_own_turn`.
- Still uncovered (no ork11e scenario exercises them; note added to the tile):
  `autoloads.FactionStratagemLoader.curated_effects` (Ork rows are
  `custom:ork11e`, so curated EffectPrimitives effects_json now only backs other
  factions) and `autoloads.EffectPrimitives.minus_one_wound_defense` (HULKING
  BRUTES uses its own `ork11e_hulking_brutes` flag).
- `sync_coverage.py` logic run for the cover tags the ork11e scenarios declare:
  141 DECLARED tiles added. A plain `python3 40k/tests/sync_coverage.py` would also
  add ~414 tiles for pre-existing non-Ork scenario drift; that was left out of
  this branch. `check_coverage.py` prints OK.
