# Stage 5 — Per-Faction Launchability Scorecard

**Generated:** 2026-05-06
**Scope override:** Adeptus Custodes + Orks only are evaluated against the launchability bar. Space Marines is **out of scope** for this pass; the other 23 factions are P2 catalog-deferred (counted, not enumerated). Synthesis only — no re-discovery; every claim is tagged with the sub-agent file it came from.

---

## Headline numbers

- **Factions launch-ready:** **0 / 26** at the strict bar (≥1 launchable detachment + faction-rule + ≥80 % P0 stratagems + ≥80 % P0 enhancements). 2 / 26 are **NEEDS WORK** (Custodes, Orks); 24 / 26 are **NOT STARTED** (no roster JSON or out-of-scope SM).
- **Detachments launchable:** **0 / 261** at the strict bar; **2 / 261** in scope are partial (Shield Host, War Horde) — both fail enhancement coverage. (`findings/04_05_enhancements_detachments.md` "Launchable-Detachment Table".)
- **Stratagems implemented and reachable in-scope:** **18 / 1,478** (12 core + 6 of 12 P0 detachment) — **1.2 %**. (`findings/04_04_stratagems.md` §Counts.)
- **Enhancements implemented and reachable in-scope:** **0 / 925** — zero P0 enhancements have effect handlers; only Freebooter Krew enhancements are wired and that detachment has no roster. (`findings/04_05_enhancements_detachments.md` §Enhancements P0=16.)
- **Named abilities implemented and reachable in-scope:** **9 ✅ + 3 ⚠️ / 70** (P0 only — Custodes/Orks active). (`findings/04_01_abilities.md` §A.)
- **Inline abilities (roster-fielded) implemented in-scope:** **~70 / ~111** distinct names; ~10 P0 are absent (Big Booms, Waaagh! Energy, Captain-General, Moment Shackle, Ramshackle but Rugged, From Golden Light, Slayers of Tyrants, Auric Aquilas, Quicksilver Execution, Daughters-of-the-Abyss FNP-flag-not-read). (`findings/04_01_abilities.md` §B + §G.2.)

**Confidence:** ~30 % of in-scope claims are depth-`L` (live-validated through MCP this audit pass or by 2026-05 audit fixtures); the rest are `W` from code-grep + cross-reference. Six items were live-validated **as bugs** during the fan-out (AP-sign, BGNT seam, Indirect-Fire mis-application, NBSP detachment-name, ARCHEOTECH double-keyword, Da Jump flag leak). These are evidence-grade.

---

## Table 1 — Per-faction launchability (26 rows)

In-scope rows are evaluated in detail; out-of-scope rows are summarised at the bottom per the scope override.

| Faction | Has Roster | Datasheets in roster | Detachments selectable | Detachments launchable | Faction ability | Stratagems P0 ✅ / total | Enhancements P0 ✅ / total | Notable gaps | Launch verdict |
|---|---|---:|---:|---:|---|---|---|---|---|
| Adeptus Custodes | ✅ (4 JSONs incl. stubs) | 16 / 31 (52 %) | 2 (`Shield Host`, `Lions of the Emperor` via NBSP roster) | 0 strict; **1 partial** (Shield Host) | ✅ Martial Ka'tah + Martial Mastery (`findings/03_03_command.md` row 17, `findings/04_06_factions.md` Section 2) | **3 ✅ / 6** Shield Host: ARCANE GENETIC ALCHEMY, ARCHEOTECH MUNITIONS 🐛, UNWAVERING SENTINELS ⚠️, MULTIPOTENTIALITY 🐛, AVENGE THE FALLEN ❌, VIGILANCE ETERNAL ❌ (`findings/04_04_stratagems.md` §Custodes Shield Host) | **0 ✅ / 4** Auric Mantle, Castellan's Mark, Hall of Armouries, Panoptispex — all display-only labels (`findings/04_05_enhancements_detachments.md` §Enhancements) | NBSP detachment-name silently drops Lions stratagems (live-confirmed); `Against All Odds` ability absent in code; Caladius/Telemon/Contemptor missing invuln in roster stats; Telemon over-priced 265 vs 225, Custodian Guard 170 vs 160; battle-shock Ld test uses bodyguard Ld only; Daughters-of-the-Abyss FNP-flag never read in damage path | **NEEDS WORK** |
| Orks | ✅ (5 JSONs incl. tests) | 27 / 87 (31 %) | 2 (`War Horde` real + `Strike Force` fake — 3 rosters) | 0 strict; **1 partial** (War Horde) | ✅ Waaagh! + Get Stuck In + Plant Waaagh! Banner (`findings/03_03_command.md` row 15, `findings/04_06_factions.md` Section 2) | **2 ✅ / 6** War Horde: 'ARD AS NAILS, UNBRIDLED CARNAGE, MOB RULE ❌🐛, 'ERE WE GO ❌, CAREEN! ❌, ORKS IS NEVER BEATEN ❌ (`findings/04_04_stratagems.md` §Orks War Horde) | **0 ✅ / 4** Follow Me Ladz, Headwoppa's Killchoppa, Kunnin' But Brutal, Supa-Cybork Body — all display-only labels (`findings/04_05_enhancements_detachments.md` §Enhancements) | `da_jump_used_this_turn` flag leaks across turn boundaries (live-confirmed, `findings/03_08_end_of_turn.md` row 8); `Strike Force` fake-detachment in 3 rosters drops every stratagem; Wazbom Blastajet AIRCRAFT min-move/edge/Hover unenforced (`findings/03_04_movement.md` M14-M16); Big Booms (Battlewagon supa-kannon) + Waaagh! Energy ('Eadbanger size scaling) `implemented:false` (`findings/04_01_abilities.md` §B.2); Da Jump placement validation skips coherency/board/ER (`findings/03_04_movement.md` M23); 'ERE WE GO +2-charge silently dropped (`findings/03_06_charge.md` row 6); Ghazghkull/Kaptin Badrukk/Nob with Banner all `can_lead=[]` despite canonical pairings (`findings/03_11_leader.md` §Roster errors); Kaptin Badrukk roster invents weapons + 100 vs canonical 80 pts; Ghazghkull missing MAKARI model line | **NEEDS WORK** |
| Space Marines | ✅ (1 JSON, 3 datasheets) | OUT OF SCOPE | — | — | — | — | — | Out of scope per launch-scope override | OUT OF SCOPE |
| 23 catalog-only factions (CSM, Aeldari, Necrons, Tyranids, AM, CD, DG, AdM, DRU, LoV, GC, TS, T'au, WE, GK, EC, AoI, AS, QI, QT, SM Black/Deathwatch sub-trees, Drukhari, Imperial Knights, Adeptus Titanicus) | ❌ none | 0 / total | 0 | 0 | ❌ none — `Dark Pacts`, `Synapse`, `Reanimation Protocols`, `Battle Focus`, `Acts of Faith`, `For the Greater Good`, `Power from Pain`, `Doctrina Imperatives`, `Voice of Command`, `Code Chivalric`, etc. all absent from `FactionAbilityManager` (`findings/04_01_abilities.md` §A and §F) | 0 / hundreds | 0 / hundreds | No roster JSONs; no army-builder UI to construct one; ~258 of 261 detachments have no `DETACHMENT_ABILITIES` entry; `Datasheets_leader.csv` not consumed (`findings/03_11_leader.md` row 1); 16 of 19 Wahapedia CSVs unloaded (`findings/04_06_factions.md` Headlines) | **NOT STARTED** (×24 incl. SM-out-of-scope) |

---

## Table 2 — Per-phase scorecard (13 rows)

Counts from per-finding "Audit table" rows; correctness symbols rolled up.

| Phase | Rules audited | ✅ % | ⚠️ % | ❌ % | 🐛 % | Top gap | Top invisible feature |
|---|---:|---:|---:|---:|---:|---|---|
| 03_01 Pre-game / Setup | 26 | 65 | 12 | 12 | 4 | No pre-deployment attacker/defender roll-off; deployment alternation always starts P1 (CA 25-26 says defender first) — `findings/03_01_pregame.md` row "Determining attacker/defender" | DESIGNATE_WARLORD action exists but no UI button (multi-CHARACTER rosters cannot fix Warlord) — `findings/03_01_pregame.md` row 3 |
| 03_02 Core Concepts | 33 | 67 | 9 | 0 | 12 (incl. AP-sign live-confirmed) | **AP sign bug in `_calculate_save_needed`** — `armour_save = base_save + ap` with negative AP improves saves (`findings/03_07_fight.md` "AP applied", live-confirmed: 2+ vs AP-2 returns 2+ instead of 4+) | `_apply_damage_to_unit:9103` — 50-line dead helper with naive allocation; latent regression net (`findings/03_02_core.md` row "Dead-code helper") |
| 03_03 Command | 23 | 78 | 9 | 9 | 4 | CP-grant rule diverges from current Wahapedia ("both players gain 1CP", no first-Command exception) — `findings/03_03_command.md` row 1 | Infiltrator Comms Array `regain_cp_on_5plus` declared `implemented:true` but zero callers (`findings/03_03_command.md` row 19) |
| 03_04 Movement | 40 | 70 | 8 | 13 | 10 | AIRCRAFT min-move 20" + board-edge end + Hover not enforced (Wazbom in active roster) — `findings/03_04_movement.md` M14-M16 | Da Jump placement skips coherency / board / ER / strict-9 (`findings/03_04_movement.md` M23); 2026-05 closed on pin test only |
| 03_05 Shooting | 36 | 78 | 8 | 0 | 11 | **NEW-S1 BGNT seam: validate_shoot rejects BGNT vehicles in ER even though eligibility allows them** (live-confirmed via execute_script; `findings/03_05_shooting.md` NEW-S1) | Wound modifier infrastructure wired (+1/-1 wound flag) but no UI affordance to toggle (`findings/03_05_shooting.md` §invisible-features) |
| 03_06 Charge | 33 | 73 | 12 | 9 | 6 | **Charge-roll modifiers not wired**: 'ERE WE GO +2 / Furious Dedication / Tide of Muscle / re-roll-charge stratagems all custom:unmapped → silently rejected (`findings/03_06_charge.md` row "Charge-roll modifiers", live-confirmed `'ere_we_go` rejection) | StratagemPanel surfaces `implemented:false` faction stratagems with rejection text (`findings/03_06_charge.md` §Top invisible features) |
| 03_07 Fight | 26 | 81 | 8 | 0 | 11 (incl. AP-sign live) | **AP sign bug** (single fix-point shared with shooting save resolution) — `findings/03_07_fight.md` row "Save calculation" | Fights Last subphase exists but no UI banner (`findings/03_07_fight.md` §Top invisible features) |
| 03_08 End of Turn | 25 | 76 | 4 | 12 | 8 | **`da_jump_used_this_turn` never resets** — Weirdboys crippled after one Da Jump (live-confirmed across 2 turn boundaries; `findings/03_08_end_of_turn.md` row 8) + SP/MP divergence in flag-reset list (multiplayer drops 7 of 18 cleanups + skips Round-3 reserves destroy) | 9 of 10 "end of opponent's turn" datasheet abilities unwired (only Acrobatic Escape fires; From Golden Light is in active Custodes roster) |
| 03_09 Terrain | 33 | 64 | 9 | 12 | 15 | Aircraft / Towering wall-LoS exception not honoured (live-confirmed: AIRCRAFT with `keywords:["AIRCRAFT"]` blocked by ruin walls; `findings/03_09_terrain.md` row "Ruins LoS — Aircraft") + `state.board.terrain` empty so impassable check is permanent no-op | Four divergent LoS implementations (`LineOfSightManager`, `EnhancedLineOfSight`, `LineOfSightCalculator`, `RulesEngine._check_legacy_line_of_sight`) with different wall-handling — same model can be visible by one calculator and blocked by another |
| 03_10 Objectives | 47 | 70 | 9 | 11 | 11 | Tipping Point deployment missing (4 of 7 CA scenarios use it); Hidden Supplies stub falls through to Take and Hold; Burden of Trust mission absent — `findings/03_10_objectives.md` rules 14, 15, 17 | Ritual / Terraform actions: missions selectable, scoring helpers reference `_pending_*` dicts, but no UI affordance and no phase code populates ritual/terraform completion |
| 03_11 Leader | 23 | 65 | 13 | 13 | 9 | **`Datasheets_leader.csv` is never consumed** — 1,884 of 1,899 canonical pairings invisible; Ghazghkull/Kaptin Badrukk/Nob with Banner all `can_lead=[]` despite canonical pairings (live-confirmed rejections); Warboss in Mega Armour `["BOYZ"]` blocks canonical Meganobz pairing | Battle-shock test reads only bodyguard Ld, never `max(bodyguard_ld, leader_ld)` — accidentally correct for current AC/Ork rosters but wrong for cross-faction parity |
| 03_12 Battle Shock | 22 | 73 | 5 | 14 | 9 (incl. cannot-shoot live-confirmed) | **`validate_shoot` blocks battle-shocked from shooting** — Wahapedia 10e BS list is exactly 3 effects (OC=0, Desperate Escape, no Stratagems); the cannot-shoot rule is a `SHOOTING_PHASE_AUDIT.md §2.8` carryover that is wrong RAW (live-confirmed: `Unit cannot shoot (battle-shocked)`) | "Cannot perform Actions while Battle-shocked" unenforced — actor's BS flag never checked when starting Establish Locus / Cleanse / Deploy Teleport Homer / Recover Assets / Ritual / Scorched Earth / Terraform |
| 03_13 Save / Load | 14 | 71 | 7 | 14 | 7 | MissionManager runtime state not persisted (sticky objectives, kill counters, supply-drop flag, `_units_alive_at_round_start`) — sticky resets every load (`findings/03_13_save_load.md` SL-NEW-1) | `UnitAbilityManager.get_state_for_save()` exists but is **never called** — once-per-battle / once-per-round ability locks reset on save/load (same shape as #338; `findings/03_13_save_load.md` SL-NEW-3) |

---

## Table 3 — Cross-cutting data scorecard

| Entity | Total | P0 ✅ at U or L | P0 ⚠️/❌ | P1 catalog-only | P2 deferred |
|---|---:|---:|---:|---:|---:|
| Abilities (named) | 70 | 9 ✅ + 3 ⚠️ (Custodes/Orks) | 0 | 1 (Assigned Agents — AoI/SM) | 57 (catalog-only factions) |
| Abilities (inline, roster-fielded) | ~111 distinct | ~70 ✅ (Custodes ~13/17 + Orks ~50/60) | ~10 ❌ (Big Booms, Waaagh! Energy, Captain-General, Moment Shackle, From Golden Light, Slayers of Tyrants, Auric Aquilas, Quicksilver Execution, Ramshackle but Rugged, Daughters-of-the-Abyss FNP) | (varies) | (most) |
| Weapon rules | 37 tokens (19 P0, 18 P2) | 14 ✅ | 4 ⚠️ + 1 🐛 (Indirect Fire 1-3 auto-fail not in 10e) | 0 | 17 |
| Keywords (rules-bearing) | 21 audited | 11 ✅ (incl. 5 L) | 4 ⚠️ + 3 ❌ + 3 🐛 (PSYKER absent, BATTLELINE not in scoring, EPIC HERO not gated for enhancements) | — | 1,399 flavor (all data-tag only — verified via 20-keyword orphan check, 0 hits) |
| Stratagems | 1,478 | **18 / 30 surfaced** = 12 core + 6 of 12 P0 detachment effects-mapped | 6 P0 unimplemented (AVENGE THE FALLEN, VIGILANCE ETERNAL, MOB RULE, 'ERE WE GO, CAREEN!, ORKS IS NEVER BEATEN) | 38 (AC) + 68 (ORK) detachment-gated, unreachable today | 1,077 catalog-only factions |
| Enhancements | 925 | **0 / 8 in-scope** (4 Shield Host + 4 War Horde) — all display-only labels in UnitStatsCardPopup; only Freebooter Krew enhancements wired but no roster | 8 in-scope ❌ | (varies) | 909 catalog |
| Detachment abilities | 283 | 3 / 4 in-scope wired (Martial Mastery ✅, Get Stuck In ✅, Combat Doctrines ✅) | 1 (Lions of the Emperor / Against All Odds — absent in code AND blocked by NBSP) | (varies) | 279 |

---

## Table 4 — Invisible-feature shortlist (top 25, in-scope)

Sorted by frequency-of-use across active rosters and end-to-end player impact. Each tag ➜ source file.

1. **`DESIGNATE_WARLORD` action has no UI button** — multi-CHARACTER rosters cannot designate (`findings/03_01_pregame.md` row 3).
2. **`Datasheets_leader.csv` never consumed** — 1,884 / 1,899 canonical leader pairings invisible (`findings/03_11_leader.md` row 1; live-confirmed for Ghazghkull, Kaptin Badrukk, Nob with Banner).
3. **`UnitAbilityManager.get_state_for_save()` exists but never called** — once-per-battle ability locks reset on save/load (`findings/03_13_save_load.md` SL-NEW-3).
4. **`MissionManager` runtime state not persisted** — sticky objectives reset on every load (`findings/03_13_save_load.md` SL-NEW-1).
5. **9 of 10 "end of opponent's turn" datasheet abilities unwired** — only Acrobatic Escape fires; From Golden Light is in active Custodes roster (`findings/03_08_end_of_turn.md` row 12).
6. **Big Booms** (Battlewagon supa-kannon concussive wave) `implemented:false` — Battlewagon in active Ork roster (`findings/04_01_abilities.md` §B.2 OA-50 open).
7. **Waaagh! Energy** ('Eadbanger size scaling) `implemented:false` — Weirdboy in active roster (`findings/04_01_abilities.md` §B.2).
8. **Daughters of the Abyss FNP-vs-Psychic flag set but never read** in `RulesEngine.get_unit_fnp` — Witchseekers/Prosecutors in active Custodes rosters (`findings/04_01_abilities.md` §E divergence #1).
9. **Witchseekers Scouts ability stored as `name:"Core"`** — `_unit_has_scout_own` checks `name.to_lower().begins_with("scout")`, never matches (data fix; `findings/04_01_abilities.md` §E divergence #2).
10. **0 of 16 P0 enhancements have effect handlers** in `UnitAbilityManager.ABILITY_EFFECTS` — display-only labels in UnitStatsCardPopup (`findings/04_05_enhancements_detachments.md` §Enhancements).
11. **`get_proactive_stratagems_for_phase` orphan** — defined in `StratagemManager.gd:2189`, zero callers — proactive faction stratagems (UNBRIDLED CARNAGE, ARCHEOTECH MUNITIONS, UNWAVERING SENTINELS) never auto-offered (`findings/04_04_stratagems.md` F7).
12. **`get_available_stratagems_for_trigger` orphan** — `StratagemManager.gd:811-856` never called (`findings/04_04_stratagems.md` F8).
13. **StratagemPanel doesn't gate by phase/trigger** — accepts `phase_id` parameter but only uses it for the title; players can fire SMOKESCREEN in SCORING phase (live-confirmed) (`findings/04_04_stratagems.md` F1).
14. **Strategic Reserves UI shows points budget but not unit-count budget** — players hit "exceeds 50 % unit limit" without seeing the cap (`findings/03_01_pregame.md` §Top invisible features).
15. **Combat Squads / Patrol Squad UI prompt missing** — `GameState.split_unit_at_deployment` exists but no Deployment-phase UI (`findings/04_01_abilities.md` §D, T-026 wedge).
16. **Mixed-save defender choice not surfaced** — `_calculate_save_needed` auto-picks better save; defender cannot deliberately fail for "when destroyed" effects (`findings/03_02_core.md` §Top invisible features).
17. **Fight-phase has zero weapon-keyword icons** — Twin-linked, Lethal Hits, Sustained Hits, Anti-X, Devastating Wounds, Precision, Hazardous, Lance, Extra Attacks invisible during melee (`findings/04_02_weapon_rules.md` §Top 10 invisible features).
18. **`recommended_deployments` metadata loaded but never displayed** in MainMenu (`findings/03_09_terrain.md` §Top invisible features).
19. **Barricade engagement-range (1"→2") code path is dead in shipped data** — 12 call sites, 0 layout files include barricade pieces (`findings/03_09_terrain.md`).
20. **Ritual / Terraform mission actions** — missions selectable, `_pending_rituals` / `_pending_terraforms` dicts referenced, no UI affordance (`findings/03_10_objectives.md` rules 12, 13).
21. **Battle Ready Army painting bonus (10 VP)** + **Challenger Cards (12 VP comeback)** — CA tops out at 100 VP; current cap is 90 (`findings/03_10_objectives.md` rules 39, 40).
22. **Auric Armour Vehicle-OC interaction** — Caladius/Contemptor/Telemon don't get +2 OC while at Starting Strength (`findings/03_12_battle_shock.md` row "Auric Armour").
23. **`game_ended` autoload state not restored from `meta.game_ended`** on load — finishing then loading freezes the loaded game (`findings/03_13_save_load.md` SL-NEW-4).
24. **`StratagemPanel.populate(player, phase_id)` accepts `phase_id` but uses it only for the title** (`findings/03_06_charge.md` row "StratagemPanel filters").
25. **'ERE WE GO +2 charge modifier silently dropped** for active Ork roster — StratagemPanel surfaces it then rejection reason "is not yet mechanically implemented" (`findings/03_06_charge.md` NEW launch-blocker #1, live-confirmed via `can_use_stratagem`).

---

## Table 5 — Divergence shortlist (top 25 🐛, in-scope)

Tests pass; players can't tell the engine fires the wrong rule. Each tag ➜ source file.

1. **AP sign bug in `_calculate_save_needed`** — `armour_save = base_save + ap` with AP stored negative; live-confirmed Custodian Guard 2+ vs AP-2 Power klaw returns save_needed:2 instead of 4+ (`findings/03_07_fight.md` row "Save calculation"; shared with all 4 resolver paths via `findings/03_02_core.md` row "Hit/wound/save resolution").
2. **NEW-S1 BGNT seam** — `validate_shoot` rejects BGNT MONSTER/VEHICLE in ER even though eligibility allows them; live-confirmed (`findings/03_05_shooting.md` NEW-S1).
3. **Indirect Fire applies penalties unconditionally** — RAW only when target invisible; current code always -1 hit / 1-3 fail / cover (`findings/03_05_shooting.md` NEW-S2). Compounds with `findings/04_02_weapon_rules.md` §Top divergences #1: the "1-3 always fail" doesn't exist in 10e at all.
4. **NBSP in `Adeptus_Custodes_1995_Mar_7.json` detachment name** — exact-string match drops every Lions stratagem (live-confirmed: `"Lions of the Emperor" == "Lions of the Emperor"` returns `false`) (`findings/04_05_enhancements_detachments.md` §Top divergences #1).
5. **GRENADE: no 8" range or visibility check** — any GRENADES unit can throw at any target (`findings/04_04_stratagems.md` F2).
6. **ARCHEOTECH MUNITIONS grants both LETHAL HITS and SUSTAINED HITS** — Wahapedia "either / or"; live-confirmed both flags applied to Contemptor-Achillus (`findings/04_04_stratagems.md` F3, `findings/04_05_enhancements_detachments.md` §Top divergences #2).
7. **MULTIPOTENTIALITY expires `end_of_phase`** instead of `end_of_turn` — Custodes player pays 1 CP for nothing (`findings/04_04_stratagems.md` F5).
8. **`da_jump_used_this_turn` never resets** — live-confirmed across 2 turn boundaries; Weirdboy permanently locked (`findings/03_08_end_of_turn.md` row 8).
9. **CP-grant rule diverges from Wahapedia** — code skips first-Command-phase CP for first-turn player and never grants opponent in your Command phase; "both players gain 1CP" (`findings/03_03_command.md` row 1).
10. **Battle-shock test uses bodyguard Ld only**, never `max(bodyguard_ld, leader_ld)` — accidentally correct for AC/Ork rosters today (`findings/03_11_leader.md` row "Battle-shock test").
11. **Battle-shocked unit cannot shoot** — Wahapedia 10e BS list is exactly 3 effects; cannot-shoot is a `SHOOTING_PHASE_AUDIT.md §2.8` carryover (live-confirmed) (`findings/03_12_battle_shock.md` row "cannot shoot").
12. **MOB RULE target parser inverts negation** — "not Below Half-strength" is parsed as positive `below_starting_strength` condition (`findings/04_04_stratagems.md` F6).
13. **UNWAVERING SENTINELS -1 to hit applies to ranged AND melee** — Wahapedia text is melee-only (`findings/04_04_stratagems.md` F4).
14. **Aircraft / Towering wall-LoS exception not honoured** — wall fall-back at `EnhancedLineOfSight.gd:381-390` ignores Aircraft/Towering exemptions (live-confirmed AIRCRAFT blocked by ruin wall) (`findings/03_09_terrain.md` §Top launch-blockers #1).
15. **`state.board.terrain` permanently empty** — impassable-terrain placement check is a no-op; OA-28/OA-29 ignore-terrain-≤4" guards unreachable for the same reason (`findings/03_09_terrain.md` rule "Models cannot end on impassable terrain").
16. **Ruins `can_move_through` only enumerates INFANTRY/VEHICLE/MONSTER** — BEAST/SWARM default to "blocked" (no roster impact today) (`findings/03_04_movement.md` M12, `findings/04_03_keywords.md` divergence #2).
17. **Da Jump placement skips coherency / board / ER / strict-9** — uses center-to-center, not edge-to-edge; T-105 closed on pin test only (`findings/03_04_movement.md` M23).
18. **Scorched Earth `_get_player_home_zone()` returns `playerN_zone`** while JSON uses `playerN` — burning your own home objective wrongly scores +10 enemy_burn VP (`findings/03_10_objectives.md` rule 10).
19. **Sites of Power character claim uses center-to-center distance** — inconsistent with shape-aware OC measurement; large-base characters can't claim (`findings/03_10_objectives.md` rule 11).
20. **Storm Hostile Objective main 5 VP condition is too broad** — counts contested-at-start as "opponent-controlled" (`findings/03_10_objectives.md` rule 28).
21. **`_apply_damage_to_unit_pool` may violate DEVASTATING WOUNDS / HAZARDOUS "stops on model destroyed" exception** — DW currently spills like ordinary mortal wounds (`findings/03_02_core.md` row "Mortal-wound spillover" + Top blockers #2).
22. **`get_anti_keyword_data` returns duplicated entries** — scans both `special_rules` text and parsed keyword-array; behaviour correct (uses lowest threshold) but display strings wrong (`findings/04_02_weapon_rules.md` divergence #3).
23. **Stealth ability checked at unit-level, not "all models"** — non-Stealth attached leader joining a Stealth bodyguard still grants -1 to hit (`findings/03_05_shooting.md` NEW-S6).
24. **Pistol-firing unit can target multiple enemy units in ER** — RAW restricts to one (`findings/03_05_shooting.md` NEW-S5).
25. **Single-player vs multiplayer end-of-turn flag-reset divergence** — MP path resets 11 of 18 flags + skips Round-3 reserves destroy (`findings/03_08_end_of_turn.md` row 10, row 25).

---

## Cross-audit themes (consolidated synthesis)

These six themes recurred across the 19 findings — synthesised here for the next stage.

1. **Data → code translation gap.** 16 of 19 Wahapedia CSVs unloaded; `Datasheets_leader.csv` ignored despite being copied; NBSP variants in detachment names silently drop entire stratagem sets; `Strike Force` is not a real detachment but 3 Ork rosters declare it; `_map_effects` silently drops unmapped effects to `custom:unmapped` and marks `implemented:false`. Roster JSONs are ~38 % out-of-sync with canonical points data. Source files: `findings/01_inventory.md` §1.3, `findings/03_11_leader.md` row 1, `findings/04_05_enhancements_detachments.md` §Top divergences, `findings/04_06_factions.md` §3.

2. **Auto / interactive seam drift.** Four duplicated ~3,300-line hit→wound→save pipelines (`_resolve_assignment_until_wounds` interactive shoot, `_resolve_assignment` auto-resolve shoot, `_resolve_overwatch_assignment`, `_resolve_melee_assignment`). Concrete divergences manifest at the seams: (a) AP-sign in shared `_calculate_save_needed` (single fix-point), (b) `flags.save_modifier` consulted in 3 of 4 paths but ignored in interactive, (c) BGNT MONSTER/VEHICLE exempt at eligibility but rejected at `validate_shoot`, (d) Indirect Fire mis-applied in all four paths, (e) battle-shock cascade flag-set bypasses `PhaseManager.apply_state_changes`. Refactor estimate: 3-5 days for shared `_resolve_attack_sequence`. Source files: `findings/03_02_core.md` row "Hit/wound/save resolution", `findings/03_05_shooting.md` NEW-S1/S2/S3.

3. **Pin-test masking.** `Infiltrator Comms Array` declared `implemented:true, once_per_turn:true` with zero callers; `Da Jump` T-105 closed on a pin test then live placement still skips coherency/board/ER/strict-9; `Witchseekers` Scouts data tagged `name:"Core"` causing the regex match to silently fail; `OA-46 Plant Waaagh! Banner` task-file checkboxes are stale relative to the actual implemented state. Source files: `findings/03_03_command.md` row 19, `findings/03_04_movement.md` M23, `findings/04_01_abilities.md` §E divergences.

4. **Zero P0 detachments meet the launchability bar.** 0 of 16 P0 enhancements have effect handlers; 12 of 24 P0 detachment stratagems load as `implemented:false`; Lions of the Emperor detachment ability `Against All Odds` absent from code; `Freebooter Krew` is fully wired in code but no roster JSON exercises it; Lions roster blocked by NBSP detachment-name. Source files: `findings/04_05_enhancements_detachments.md` headline + Launchable-Detachment Table, `findings/04_04_stratagems.md` §Counts.

5. **SP / MP divergence.** End-of-scoring flag-reset asymmetry (SP resets 18 flags; MP resets 11; MP skips Round-3 reserves destroy entirely); battle-shock flag set/clear bypasses `PhaseManager.apply_state_changes` so peers don't see flag transitions. Source files: `findings/03_08_end_of_turn.md` row 10 + row 25, `findings/03_03_command.md` row 5.

6. **Cover-cap dispute.** `findings/03_02_core.md` row 41 says ❓ Wahapedia text not verifiable; `findings/03_05_shooting.md` NEW-S7 says ❓ same; `findings/04_03_keywords.md` divergence #1 says 🐛 "regression vs 2026-05 verified-✅ state"; `findings/03_09_terrain.md` row "Benefit of Cover 3+ cap" says ✅ universal is RAW-correct. All four note the Wahapedia core-rules page truncated for them. **Needs a fresh source pull** — the 2026-05-05 commit `6958cff` flipped from keyword-gated (INFANTRY/BEAST/SWARM) to universal; if the keyword-gated form is correct, every 3+-save VEHICLE/MONSTER currently loses cover at AP 0 vs RAW.

---

## Targeted Live-Validation Pass — recommended next-stage scenarios (8 items)

Each item has genuinely-low audit confidence (sub-agent reported `LIVE-VALIDATION SKIPPED` AND the finding is load-bearing for a Custodes/Orks launch). Items already live-validated (AP-sign, BGNT seam, Indirect Fire, NBSP detachment-name drop, GRENADE 8" check, ARCHEOTECH double-keyword, StratagemPanel phase-gating, `da_jump_used_this_turn` flag leak, MultiPotentiality expiry mismatch) are **excluded** per the constraint.

### TLV-1 — Da Jump placement bounds (coherency / board / engagement-range / strict-9)

**Why low-confidence:** `findings/03_04_movement.md` M23 says T-105 was closed by 2026-05 on a pin test; the live audit was skipped because the running session was past Movement phase. `_validate_place_reinforcement` does edge-to-edge + coherency + board + ER; `MovementPhase.gd:2084-2183` Da Jump validation uses `pv.distance_to(ev) < nine_inches_px` (center-to-center, strict `<`).

**MCP scenario.** Fixture: `co_pretrigger.w40ksave` (or any save with Weirdboy at full strength). 
1. `dispatch_action({type:"USE_DA_JUMP", actor_unit_id:"U_WEIRDBOY_J"})` — should succeed (D6 roll path).
2. Probe four illegal placements via `dispatch_action({type:"PLACE_DA_JUMP", positions:[{model_id:"m0", pos:{x,y}}, ...]})`:
   - **Bounds A:** position exactly 9.000" edge-to-edge from nearest enemy model (Custodian Guard) — assert `success:false` if rule is "more than 9".
   - **Bounds B:** position with one model off-board (`x > board.size_x`) — assert `success:false`.
   - **Bounds C:** positions with model 1 at (100,100) and model 2 at (300,300) (>2" coherency) — assert `success:false, reason:"coherency"`.
   - **Bounds D:** position inside enemy unit's ER (within 1" of enemy model) — assert `success:false, reason:"engagement range"`.
3. Capture screenshot of the rejection toast for each + `execute_script` reading the resulting unit position to confirm no partial placement.

### TLV-2 — Heroic Intervention edge timing on charge declaration

**Why low-confidence:** `findings/03_06_charge.md` row "Heroic Intervention" cites 2026-05 verification via `hi_pretrigger.w40ksave`; the live audit only state-checked. Multiple subtle conditions (1 CP, after_enemy_charge_move trigger, eligible-to-charge, no fights_first grant, no charge bonus) interact with the Telemon HI candidate that was loaded.

**MCP scenario.** Fixture: `hi_pretrigger.w40ksave`.
1. `dispatch_action({type:"DECLARE_CHARGE", actor_unit_id:"U_WARBOSS_B", target_unit_ids:["U_CUSTODIAN_GUARD_B"]})` — confirm charge declared.
2. `dispatch_action({type:"CHARGE_ROLL", actor_unit_id:"U_WARBOSS_B"})` then `APPLY_CHARGE_MOVE` to engage.
3. After APPLY_CHARGE_MOVE: probe `is_heroic_intervention_available(1)` and `get_heroic_intervention_eligible_units(1)`. Confirm Telemon eligible.
4. `dispatch_action({type:"USE_HEROIC_INTERVENTION", actor_unit_id:"U_TELEMON_HEAVY_DREADNOUGHT_I", target_unit_id:"U_WARBOSS_B"})` — assert P1 CP -1, charge_roll fires.
5. `execute_script` reading `flags.charged_this_turn` (should be true) and `flags.heroic_intervention` (should be true) and `flags.fights_first` (should be **false** — HI doesn't grant fights_first).
6. Capture screenshot of fight sequence panel showing Telemon NOT in `fights_first_sequence`.

### TLV-3 — Formations leader-attachment UI flow + Lone Operative guard

**Why low-confidence:** `findings/03_11_leader.md` rows "Attach declared at army-list time" and "Lone Operative attachment guard at FormationsPhase declaration" — the latter is flagged as missing (`_validate_declare_leader_attachment` does NOT call `CharacterAttachmentManager.can_attach`). Live audit was read-only.

**MCP scenario.** Fresh game start, load `adeptus_custodes.json` for P1 + `orks.json` for P2.
1. Drive through `FORMATIONS` phase via `play_main_scene` then `simulate_click` on the FormationsDeclarationDialog.
2. Test **happy path:** `DECLARE_LEADER_ATTACHMENT` Blade Champion → Custodian Guard. Assert success, `attached_to` set.
3. Test **Lone Op guard:** spawn a synthetic CHARACTER with `meta.abilities=[{name:"Lone Operative"}]` AND `meta.leader_data.can_lead=["BOYZ"]` via `execute_script`; dispatch `DECLARE_LEADER_ATTACHMENT` with that character → Boyz unit.
   - **Expectation per rule:** rejected with "Lone Operative cannot be attached as Leader".
   - **Audit prediction:** **succeeds** because FormationsPhase doesn't call `can_attach` (per `findings/03_11_leader.md`). Confirms 🐛.
4. Test **multi-CHARACTER warlord designation UI:** load a fresh game with two CHARACTER units, attempt `CONFIRM_FORMATIONS` — expect "no Warlord designated" rejection. Confirm via `simulate_click` that **no DESIGNATE_WARLORD button exists** in the dialog (player cannot fix the rejection from UI).
5. Capture screenshot of FormationsDeclarationDialog showing the missing warlord button + the Lone-Op-attached state.

### TLV-4 — Deployment alternation: defender deploys first per CA 25-26

**Why low-confidence:** `findings/03_01_pregame.md` row "Deployment alternation" calls this a launch-blocker — `TurnManager.gd:176-184` always biases toward Player 1; defender-first is not modelled. Live audit was post-deployment so could not drive.

**MCP scenario.** Fresh game start.
1. After mission/map/layout selection, force the pre-deployment roll-off via `execute_script` setting `meta.attacker = 2, meta.defender = 1, meta.first_turn_player = 1` (P1 wins first turn, but P2 is the Attacker).
2. Enter DEPLOYMENT phase. Probe `TurnManager.get_current_player_for_deployment()`.
   - **Expectation per CA 25-26:** defender (P1) deploys first.
   - **Audit prediction:** P1 by coincidence (always P1 first); but if `meta.attacker` is reversed (`attacker=1, defender=2`), the engine should flip to P2 first — and won't.
3. Run with `meta.attacker = 1, meta.defender = 2` and assert `current_player == 2` for the first deployment.
4. Capture screenshot of the deployment HUD active-player indicator showing the wrong player taking the first deployment slot.

### TLV-5 — Battle-shock attached-unit Ld test uses `max(bodyguard_ld, leader_ld)`

**Why low-confidence:** `findings/03_11_leader.md` row "Battle-shock test" + `findings/03_12_battle_shock.md` (regression spot-check only). Wahapedia: "greater than or equal to the **best Leadership** characteristic in that unit". Code reads `unit.meta.stats.leadership` only — bodyguard's. AC/Ork rosters happen to all have bodyguard Ld ≥ leader Ld so it's accidentally correct, but rule is divergent.

**MCP scenario.** Fixture: any save with attached units, mid-game.
1. `execute_script` mutate Custodian Guard `meta.stats.leadership = 5` (worse) and Blade Champion `meta.stats.leadership = 8` (better) on the attached pair.
2. Force unit below half-strength: `execute_script` set `current_wounds=0, alive=false` on enough Custodian Guard models to drop below half.
3. `transition_to_phase(COMMAND, player_id=1)` and `dispatch_action({type:"BEGIN_BATTLE_SHOCK_TEST", unit_id:"U_CUSTODIAN_GUARD_B"})`.
4. `execute_script` read the test threshold the engine used.
   - **Expectation per Wahapedia:** Ld 8 (Blade Champion's, the best).
   - **Audit prediction:** Ld 5 (bodyguard's). Confirms 🐛.
5. Capture screenshot of BattleShockTestDialog showing the wrong threshold.

### TLV-6 — Cover save 3+ cap scope (Wahapedia re-fetch + controlled save-arithmetic drive)

**Why low-confidence:** Four findings flag conflicting interpretations and Wahapedia core-rules page truncated for all four (`findings/03_02_core.md` row 41, `findings/03_05_shooting.md` NEW-S7, `findings/04_03_keywords.md` divergence #1, `findings/03_09_terrain.md` row "Benefit of Cover 3+ cap"). Commit `6958cff` (2026-05-05) flipped from keyword-gated to universal.

**MCP scenario.** Pre-step: `WebFetch` against fresh Wahapedia core-rules URL + Designers' Commentary URL until the Terrain / Benefit of Cover section returns non-truncated. Ground truth is now establishable.
1. **Math drive:** `execute_script` calling `RulesEngine._calculate_save_needed(3, 0, true, 0, {meta:{keywords:["VEHICLE"]}})` — assert behaviour matches resolved RAW (3+ if universal cap; 2+ if keyword-gated).
2. Repeat for `keywords:["INFANTRY"]`, `keywords:["BEAST"]`, `keywords:["SWARM"]`, `keywords:["MONSTER"]`, `keywords:["MOUNTED"]`.
3. **In-game drive:** load fixture with Caladius Grav-tank (VEHICLE, Sv3+) inside ruins terrain, AP 0 weapon shooting at it.
4. Trigger shooting through `dispatch_action({type:"DECLARE_TARGETS"...})` and observe WoundAllocationOverlay's `model_save_profiles[0].save_needed`.
5. Capture screenshot of the save dialog with Caladius's resolved save-needed value.
6. Cross-reference numeric result with the ground truth from step 0 — flag ✅ or 🐛.

### TLV-7 — 'ERE WE GO +2 charge modifier (Ork active roster, currently silently dropped)

**Why low-confidence:** `findings/03_06_charge.md` row "Charge-roll modifiers" + NEW launch-blocker #1. `_map_effects` doesn't parse "add N to Charge rolls"; live audit only confirmed the rejection. The full feature path (parser + EffectPrimitive + ChargePhase reader) is missing.

**MCP scenario.** Fixture: any Ork-active save mid-game pre-Charge phase.
1. `dispatch_action({type:"USE_STRATAGEM", stratagem_id:"faction_ork_war_horde_ere_we_go", actor_unit_id:"U_BOYZ_E", player:2})` BEFORE charge declaration.
   - **Audit prediction:** rejected with "is not yet mechanically implemented" (live-confirmed already in fan-out, this scenario is the **regression net post-fix**).
2. After implementing fix: same call should succeed; CP -1; `flags.effect_plus_charge=2` set on the unit.
3. `dispatch_action({type:"DECLARE_CHARGE", target_unit_ids:["U_CUSTODIAN_GUARD_B"]})` and `CHARGE_ROLL` with `rng_seed` set to a low-end roll (rolls=[2,2], total=4) at edge-distance 5".
4. Assert `effective_distance == 4 + 2 = 6` (passes the 5" charge); without the modifier the same roll would fail.
5. Capture screenshot of the charge dice display showing rolled value 4 + modifier 2 = 6 effective.

### TLV-8 — Save/load round-trip for `MissionManager` runtime state (sticky objectives)

**Why low-confidence:** `findings/03_13_save_load.md` SL-NEW-1 — `MissionManager` has 17+ gameplay-bearing member vars (sticky objectives, supply-drop resolution, kill counters) but **no `get_save_data` / `load_save_data` API**. The headless test `test_save_load_audit_roundtrip.gd` confirms the gap shape but doesn't cover sticky-objective semantics specifically.

**MCP scenario.** Fixture: any save mid-game with at least one objective.
1. `dispatch_action` to make a Boyz unit (with `Get Da Good Bitz` ability) score a sticky objective. Probe `MissionManager._sticky_objectives` — confirm entry exists.
2. `SaveLoadManager.save_game("test_sticky.w40ksave")` then `load_game("test_sticky.w40ksave")`.
3. Probe `MissionManager._sticky_objectives` after load.
   - **Expectation per Wahapedia sticky rule:** entry persists.
   - **Audit prediction:** dict is empty / re-initialised (confirms SL-NEW-1).
4. Drive a `MissionManager.check_objective_control()` call; observe whether the sticky objective resolves to player 2's control or to physical-OC contest.
5. Capture screenshot of objective marker visualisation — sticky markers should show locked colour pre-load and revert to neutral post-load if the bug is present.

---

## What it would take to ship a 4th faction (in scope after Custodes/Orks)

(Per scope override SM is excluded; the next ROI faction in code-shape priority is the one whose detachment ability is the simplest to wire.)

1. **Pick a faction whose detachment ability shares an existing primitive** — e.g. Tyranids `Synapse` re-uses Battle-shock immunity (~1 day). Aeldari `Strands of Fate` would need a new dice-pool autoload (~1 week).
2. **Author 1 roster JSON** with 10-15 datasheets (~2-3 days hand-curated against `Datasheets_*.csv` since the Wahapedia data is **not loaded**).
3. **Add `FactionAbilityManager.FACTION_ABILITIES` + `DETACHMENT_ABILITIES` entries** (~1-2 days).
4. **Wire 6 detachment stratagems** through `_map_effects` extensions where possible; hand-implement 2-3 (~2-3 days).
5. **Wire 4 detachment enhancements** as `UnitAbilityManager.ABILITY_EFFECTS` entries (most use existing primitives like `grant_invuln`, `set_effect_fnp` — ~1 day).
6. **Live-validate** through deploy → 1 full battle round (~1 day per CLAUDE.md feature-validation rule).

**Per-faction baseline:** ~12-20 days. Cross-cutting cleanup needed first (~1 week): NBSP normaliser, `_map_effects` charge-roll/+N-attacks/fights-on-death primitives, `Datasheets_leader.csv` consumer, MissionManager save API, `da_jump_used_this_turn` reset, AP-sign fix, BGNT seam fix, Indirect Fire visibility gate, Heavy Cover melee +1, EPIC HERO enhancement gate, PSYKER keyword routing.

## What it would take to ship every faction (26-faction goal)

1. **Engine plumbing:** ~1.5 person-months for the 12 cross-cutting items above + the in-app army-builder UI (`MainMenu.gd` / `MultiplayerLobby.gd` only present a flat dropdown today — `findings/04_06_factions.md` Headlines: "no faction picker, no detachment selector, no unit catalog browser").
2. **Per-faction data + code (24 remaining factions × ~12-20 days each):** ~280-460 person-days. Heavier for novel mechanics: Tyranids Synapse, Necrons Reanimation, Drukhari Power From Pain, Aeldari Strands of Fate, AdMech Doctrina Imperatives, T'au For the Greater Good, Imperial Knights single-model armies, AS Acts of Faith / Miracle Dice, CSM Dark Pacts.
3. **Data-pipeline closure:** consume `Datasheets.csv` + `Datasheets_models.csv` + `Datasheets_wargear.csv` + `Datasheets_abilities.csv` + `Datasheets_keywords.csv` + `Datasheets_models_cost.csv` + `Datasheets_leader.csv` + `Detachment_abilities.csv` + `Enhancements.csv` at runtime instead of hand-curating roster JSONs (~2 weeks engineering + ongoing maintenance).
4. **Tournament-pack closure:** Tipping Point deployment, Hidden Supplies + Burden of Trust missions, Battle Ready Army painting bonus, Challenger Cards, Sabotage / Recover Assets / Investigate Signals action missions (~2-3 weeks).
5. **Headline estimate:** **1.5-3 person-years** to take launchability from 0 / 26 (strict bar) to 26 / 26.

## Confidence statement

This audit is ~30 % live-validated and ~70 % depth-`W` (code-grep + cross-reference). The 9 items live-validated as bugs during fan-out (AP-sign, BGNT seam, Indirect-Fire mis-application, NBSP detachment-name drop, GRENADE 8" check, ARCHEOTECH double-keyword, StratagemPanel phase-gating, `da_jump_used_this_turn` flag leak, MultiPotentiality expiry mismatch) are evidence-grade and should drive the launch-blocker shortlist for Stage 6. The 8 items in the Targeted Live-Validation Pass above represent the highest-confidence next steps to convert depth-`W` claims to depth-`L` evidence — those scenarios should be driven before Stage 6 synthesis to upgrade the next layer of audit findings to evidence-grade.
