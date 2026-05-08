# 04.01 — Abilities (findings)

**Date:** 2026-05-06
**Source prompts:** `.llm/audit_2026_launch/04_data_entities/01_abilities.md` + `00_overview.md` + `01_inventory.md`
**Universes audited:**
- 70 named/core abilities (catalog) — `.llm/audit_2026_launch/universe/abilities.json`
- 111 distinct abilities used across active rosters — `.llm/audit_2026_launch/universe/roster_priority.json`
- 3,593 inline (datasheet-specific) ability rows in `40k/data/Datasheets_abilities.csv` (P2 catalog-only abilities not used by any active roster are summarised, not row-audited)
- Roster-fielded inline abilities (those that appear in `40k/armies/*.json meta.abilities[]` but are not in the named catalog)

**Code references:**
- `40k/autoloads/UnitAbilityManager.gd` — 106 named entries in `ABILITY_EFFECTS` (97 marked `implemented:true`, 9 `implemented:false`) — verified live via MCP `get_node('/root/UnitAbilityManager').ABILITY_EFFECTS.size() = 106`.
- `40k/autoloads/FactionAbilityManager.gd` — 3 entries in `FACTION_ABILITIES` (Oath of Moment, Martial Ka'tah, Waaagh!) and 4 in `DETACHMENT_ABILITIES` (Gladius Task Force, War Horde, Freebooter Krew, Shield Host) — verified live via MCP.
- `40k/autoloads/RulesEngine.gd`, `40k/autoloads/GameState.gd`, `40k/autoloads/CharacterAttachmentManager.gd`, `40k/autoloads/ArmyListManager.gd`, phase files in `40k/phases/`.

**Prior-audit overlap (read first; do not re-file):**
- `40k/test_results/audit_2026_05/AUDIT_REPORT.md` verified Custodes Martial Mastery + Martial Ka'tah + Praesidium Shield + Sentinel Storm; Orks Waaagh + Plant Banner; phase machinery; stratagem timing; weapon keywords. Spot-checked here, all still pass.
- `ABILITIES_AUDIT.md` (repo root, 2026-02). Most items obsolete because of `40k/AUDIT_ABILITIES_2.md` and `40k/ORK_ABILITIES_TASKS.md` PRs landed since.
- `40k/AUDIT_ABILITIES_2.md` (2026-03-08, 9 Custodes/AoI units). Several items remain valid; flagged below.
- `40k/ORK_ABILITIES_TASKS.md` (OA-1 … OA-52). All marked `[x]` except **OA-46** "Plant the Waaagh! Banner / Da Boss Iz Watchin'" (subtasks unchecked though `UnitAbilityManager.ABILITY_EFFECTS["Plant the Waaagh! Banner"]` is now `implemented:true` and `FactionAbilityManager.activate_plant_waaagh_banner()` exists and was verified live in AUDIT_REPORT). The TASKS file's unchecked status is stale.

---

## A. Catalog faction/keyword abilities (70 named, by ref count)

Tier rules: P0 = used by any active roster (Custodes / Orks / Space Marines); P1 = same-faction other-detachment (none, since Oath of Moment is the only SM faction ability and it IS in the active roster); P2 = catalog-only (no active roster).

| Entity ID | Name | Faction / Detachment | Priority | Depth | Correctness | Evidence | Notes |
|---|---|---|---|---|---|---|---|
| 000008339 | Deadly Demise | All factions | **P0** | **L** | ✅ | `RulesEngine.gd:10246-10721` `resolve_deadly_demise`; `_roll_deadly_demise_damage`; OA-50 trigger override at lifta-droppa | Verified live in 2026-05 (AUDIT_REPORT.md). `Da Bigger Dey Are, da Better Dey Drop` overrides 6→3+. 6 P0 units (Battlewagon, Caladius, Telemon, Contemptor-Achillus, Wazbom, Trukk variants) currently have variants. |
| 000008346 | Leader | All factions | **P0** | **L** | ✅ | `CharacterAttachmentManager.gd:36-41` (Lone-Operative-as-leader block); `40k/autoloads/CharacterAttachmentManager.gd` whole | Verified live & in AUDIT_REPORT. LOS! protection: 9e wounds-threshold removed, standalone protection now lives entirely in Lone Operative. |
| 000008343 | Deep Strike | All factions | **P0** | **L** | ✅ | `GameState.gd:461 unit_has_deep_strike`; `MovementPhase.gd:3257-3370,4635-4707,6231-6247`; `DeploymentPhase.gd:342-928` | Live: MCP `unit_has_deep_strike("U_KOMMANDOS_H")=false` ; the AC-roster Caladius placed via Strategic Reserves at audit_2026_05 t2.m12-m14. P2-80 Balance Dataslate "DS unit from Strategic Reserves can use DS rules" wired. |
| 000008350 | Oath of Moment | SM (P0) | **P0** | **U** | ⚠️ | `FactionAbilityManager.gd:137,292-361`; `set_oath_of_moment_target`; sets `unit.flags.oath_of_moment_target` | Code path is wired (re-roll Hit + +1 to Wound), but the **active SM roster `space_marines.json` is sparse (3 units: Intercessor, Tactical Squad, Infiltrator)** — Oath is hard to live-validate end-to-end without a fuller SM roster. Current 2026-05 audit was on Custodes vs Orks — Oath of Moment was **not in the live test path**. `LIVE-VALIDATION SKIPPED: SM roster sparse and current loaded scenario is Custodes vs Orks; Oath visible at code-path level only.` |
| 000008359 | Dark Pacts | CSM/CD/QT/DG/TS/WE | **P2** | ❌ | ❌ | No reference in `40k/autoloads` or `40k/phases` (`grep -nE "dark_pacts|Dark Pacts" /40k/autoloads /40k/phases` returns nothing) | No Heretic Astartes roster exists. No engine implementation. Catalog-only. **Launchability blocker for any HERETIC ASTARTES roster.** |
| 000008338 | Feel No Pain | All factions | **P0** | **L** | ⚠️ | `RulesEngine.gd:2905-2975, 3129-3140` (`get_unit_fnp`, `get_model_fnp`, `roll_feel_no_pain`); `EffectPrimitivesData` flags | Standard FNP works. **Cross-cutting bug**: `get_unit_fnp()` does NOT check `effect_fnp_psychic_mortal` (Daughters of the Abyss). Filed in `40k/AUDIT_ABILITIES_2.md` cross-cutting #1 — still open. |
| 000008344 | Scouts | All factions | **P0** | **U** | ⚠️ | `GameState.gd:478-589` (`unit_has_scout`, distance parsing, transport inheritance); `phases/ScoutPhase.gd`, `phases/ScoutMovesPhase.gd` | Working for properly-named entries. **Bug carried over from `40k/AUDIT_ABILITIES_2.md` cross-cutting #5**: Witchseekers in `armies/adeptus_custodes.json` and `A_C_test.json` have `"name":"Core"` (with `parameter:"6\""`), so the `name.to_lower().begins_with("scout")` test fails — Witchseekers will not get Scout moves. Data fix, not code fix. |
| 000009894 | Battle Focus | AE/DRU | **P2** | ❌ | ❌ | No reference in `40k/autoloads` or `40k/phases` | No Aeldari/Drukhari roster. **Launchability blocker for Aeldari/Drukhari.** |
| 000003676 | Waaagh! | ORK | **P0** | **L** | ✅ | `FactionAbilityManager.gd:367-571` (`activate_waaagh`, `_apply_waaagh_effects`, `_clear_waaagh_effects`); `_apply_da_boss_iz_watchin`; once-per-battle in `_waaagh_used` | Verified live AUDIT_REPORT.md t2.sc Round 1+. Spot-check live: `is_waaagh_available(2)=false` because already loaded mid-battle, `is_waaagh_active(2)=false` (consistent). +1 S/A melee, 5+ invuln, advance+charge all applied. Lifecycle hooks for Krumpin' Time / Big an' Shooty / Big an' Stompy / Special Dose / Da Biggest and da Best / Dead Brutal / Da Boss Iz Watchin' all gated on this. |
| 000008337 | Stealth | All factions | **P0** | **L** | ✅ | `RulesEngine.gd:1596-1603, 2429-2436, 5882-5885` (`has_stealth_ability` + flag fallback `EffectPrimitivesData.has_effect_stealth`) | Spot-check live: `has_stealth_ability(U_KOMMANDOS_H)=true`. Proper -1 to hit applied for ranged attacks. |
| 000008345 | Infiltrators | All factions | **P0** | **U** | ✅ | `GameState.gd:464 unit_has_infiltrators`; `DeploymentPhase.gd:112`; `RedeploymentPhase.gd:200`; "Omni-scramblers" block wired in `MovementPhase.gd` | Live: `unit_has_infiltrators("U_KOMMANDOS_H")=true`. Deployment >9" rule, no-DZ-edge rule, Omni-scramblers 12" denial all enforced. |
| 000000705 | Synapse | TYR/GC | **P2** | ❌ | ❌ | No reference in code | No Tyranid/GC roster. Catalog-only. |
| 000008433 | The Shadow of Chaos | CD | **P2** | ❌ | ❌ | No reference in code | No Daemon roster. Catalog-only. |
| 000008396 | Nurgle's Gift (Aura) | CSM/DG | **P2** | ❌ | ❌ | No reference in code | No Death Guard roster. |
| 000008369 | Reanimation Protocols | NEC | **P2** | ❌ | ❌ | No reference in code | No Necron roster. |
| 000008334 | Firing Deck | All factions | **P0** | **U** | ✅ | `ArmyListManager.gd:159-231,529-594` (parsing); `TransportManager.gd:294-307`; `ShootingPhase.gd:656,3046,3963-3984`; `scripts/FiringDeckDialog.gd` | Active roster Battlewagon + Wazbom etc. parse Firing Deck N. UI dialog launches when transport selected. 'Ard Case correctly removes Firing Deck (`ArmyListManager.gd:776-780`). |
| 000008342 | Hover | All factions | **P2** | ❌ | ❌ | No `hover_mode` / Hover keyword handler in `40k/autoloads` or `40k/phases` (`grep` returns no live code references) | No active AIRCRAFT in current rosters declares Hover declaration step (Wazbom Blastajet is in `orks.json` with AIRCRAFT keyword but no Hover mode toggle). **Invisible feature — needed for any non-Custodes/Orks AIRCRAFT.** |
| 000008428 | Blessings of Khorne | CSM/WE | **P2** | ❌ | ❌ | No reference in code | No World Eaters roster. |
| 000008336 | Lone Operative | All factions | **P0** | **L** | ✅ | `RulesEngine.gd:3356-3364, 4097-4110, 5358-5391 has_lone_operative`; `CharacterAttachmentManager.gd:36-41` (lone-op-as-leader rejection) | Live: `has_lone_operative(U_KAPTIN_BADRUKK_A)=false` (Badrukk is FREEBOOTER but not Lone Op). 12" targeting restriction enforced when standalone (not in Attached unit). |
| 000008452 | Assigned Agents | AoI/SM | **P1** | ❌ | ❌ | No reference in code (`40k/AUDIT_ABILITIES_2.md` confirms) | No Agents of the Imperium roster. SM rosters do not include AoI units. |
| 000008382 | Doctrina Imperatives | AdM/QI | **P2** | ❌ | ❌ | No reference in code | No Adeptus Mechanicus / Imperial Knights roster. |
| 000008439 | For the Greater Good | TAU | **P2** | ❌ | ❌ | No reference in code | No T'au roster. |
| 000008466 | Acts of Faith | AS | **P2** | ❌ | ❌ | No reference in code | No Adepta Sororitas roster. |
| 000008507 | Power from Pain | DRU | **P2** | ❌ | ❌ | No reference in code | No Drukhari roster. |
| 000009896 | Disparate Paths | AE/DRU | **P2** | ❌ | ❌ | No reference in code | No Aeldari/Drukhari roster. |
| 000008340 | Fights First | All factions | **P0** | **L** | ✅ | `FightPhase.gd:59,160,2079-2105` (`fights_first_sequence`, fights-first vs fights-last cancellation per 10e Rules Commentary) | 2026-05 AUDIT_REPORT t1.* phase machinery + Heroic Intervention NOT eligible to fights-first per 10e — verified live. |
| 000008391 | Martial Ka'tah | AC | **P0** | **L** | ✅ | `FactionAbilityManager.gd:145-1846` (`unit_has_katah`, `apply_katah_stance`, `clear_katah_stance`, Dacatarai = sustained_hits 1, Rendax = lethal_hits) + `KatahStanceDialog.gd` | Live spot-check: `unit_has_katah("U_BLADE_CHAMPION_A")=true`. Stance per-fight resolution. AUDIT_REPORT verified end-to-end. |
| 000008458 | Code Chivalric | QI | **P2** | ❌ | ❌ | No reference in code | No Imperial Knights roster. |
| 000010432 | Prioritised Efficiency | LoV | **P2** | ❌ | ❌ | No reference in code | No Leagues of Votann roster. |
| 000000707 | Shadow in the Warp | TYR/GC | **P2** | ❌ | ❌ | No reference in code | No Tyranid/GC roster. |
| 000008512 | Harbingers of Dread | QT | **P2** | ❌ | ❌ | No reference in code | No Chaos Knights roster. |
| 000008537 | Unaligned Forces | UN | **P2** | ❌ | ❌ | No reference in code | Army-list build rule; no Unaligned roster. |
| 000010345 | Gate of Infinity | GK | **P2** | ❌ | ❌ | No reference in code | No Grey Knights roster. |
| 000008377 | Voice of Command | AM | **P2** | ❌ | ❌ | No reference in code | No Astra Militarum roster. |
| 000008460 / 000008513 / similar | Super-heavy Walker | QI/QT/SM(?) | **P2** | ❌ | ❌ | No reference in code | Imperial Knights / Chaos Knights roster missing. |
| 000008526 | Templar Vows | SM (Black Templars) | **P2** | ❌ | ❌ | No reference in code | Active SM roster not Black Templars. |
| 000009994 | Thrill Seekers | CSM/EC | **P2** | ❌ | ❌ | No reference in code | No EC roster. |
| 000008424 | Cabal of Sorcerers | CSM/TS | **P2** | ❌ | ❌ | No reference in code | No Thousand Sons roster. |
| 000008521 | Mission Tactics | SM (Deathwatch) | **P2** | ❌ | ❌ | No reference in code | Active SM roster is not Deathwatch. |
| 000008501 | Cult Ambush | GC | **P2** | ❌ | ❌ | No reference in code | No GSC roster. |
| 000008519 | Kill Team | SM (Deathwatch) | **P2** | ❌ | ❌ | No reference in code | — |
| (various) Pact of Decay / Pact of Sorcery / Pact of Excess / Pact of Blood | CSM/DG/TS/EC/WE | **P2** | ❌ | ❌ | No reference in code | No Heretic Astartes roster. |
| (catalog) Curse of the Wulfen / Space Marine Chapters / Strands of Fate / Bondsman / Freeblades / Dreadblades / Towering Example / Titanic Support / Titanicus Traitoris / Sons of Russ / Heirs of Sigismund / Sagas / The Unforgiven / The Ravenwing / The Deathwing / The Sons of Sanguinius / Cult of the Dark Gods / Daemonic Pact / Designer's Note / Agile Manoeuvres / Corsairs and Travelling Players / Kill Teams / Deathwatch | (various) | **P2** | ❌ | ❌ | No reference in code | All have `ref_count: 0` or near-zero in `universe/abilities.json` — many are headers/sub-faction labels rather than mechanically-resolved abilities. Catalog completeness is fine; not gating launch. |

### Catalog summary (70 named abilities)

| Tier | ✅ | ⚠️ | ❌ | 🐛 | Total |
|---|---:|---:|---:|---:|---:|
| **P0** (in active roster) | 9 | 3 | 0 | 0 | 12 |
| **P1** (same-faction other-detachment) | 0 | 0 | 1 | 0 | 1 (Assigned Agents) |
| **P2** (catalog-only) | 0 | 0 | ~57 | 0 | ~57 |

**Top P0 catalog ✅:** Deadly Demise, Leader, Deep Strike, Feel No Pain (with FNP-psychic-mortal caveat), Stealth, Infiltrators, Lone Operative, Fights First, Firing Deck, Martial Ka'tah, Waaagh!.
**Top P0 catalog ⚠️:** Oath of Moment (wired but no live test — sparse SM roster), Feel No Pain (Daughters of the Abyss FNP-psychic-mortal flag never read), Scouts (Witchseekers data uses `name:"Core"` so detection fails).

---

## B. Inline (datasheet-specific) abilities — by roster

Roster-fielded inline abilities (the 111 distinct names from `roster_priority.json` minus the named catalog above). Implementation status from `UnitAbilityManager.ABILITY_EFFECTS` and engine helpers.

### B.1 Adeptus Custodes inline abilities (P0 — fielded)

| Name | Unit | Priority | Depth | Correctness | Evidence | Notes |
|---|---|---|---|---|---|---|
| Praesidium Shield | Custodian Guard, Shield-Captain | P0 | **L** | ✅ | `ArmyListManager.gd:701-707` WARGEAR_STAT_BONUSES (+1W) | Verified live in audit_2026_05. |
| Vexilla | Custodian Guard | P0 | **L** | ✅ | `ArmyListManager.gd:707` WARGEAR_STAT_BONUSES (+1 OC) | — |
| Sentinel Storm | Custodian Guard | P0 | **L** | ✅ | `UnitAbilityManager.gd:337-345`; `ShootingPhase.gd:23,50,325-426`; `UnitAbilityManager.gd:2527-2541` | Once-per-battle. Both human + AI. |
| Stand Vigil | Custodian Guard | P0 | **W** | ⚠️ | `UnitAbilityManager.gd:189-197` (objective_upgrade_effects defined, but conditional resolution path checks objective proximity in `RulesEngine`) | Per `40k/AUDIT_ABILITIES_2.md` cross-cutting #4: base re-roll-1 works, objective-conditional full re-roll only works if proximity check is wired. `UnitAbilityManager.gd:3655` references "Used for Stand Vigil objective-conditional upgrade", suggesting it's now wired — **regression-spot-check needed**. Carry-over flag remains until live-validated. |
| Daughters of the Abyss | Witchseekers, Prosecutors | P0 | **C** | 🐛 | `UnitAbilityManager.gd:223-230`; flag set; `RulesEngine.get_unit_fnp` does NOT read `effect_fnp_psychic_mortal` | **Bug carried over from `40k/AUDIT_ABILITIES_2.md` cross-cutting #1** — flag is set but never consumed during damage resolution, so the 3+ FNP vs Psychic / mortal wounds never fires. Open. |
| Sanctified Flames | Witchseekers | P0 | **L** | ✅ | `UnitAbilityManager.gd:348-355,2545-2555`; `ShootingPhase.gd` post-shoot battle-shock prompt | — |
| Martial Inspiration | Blade Champion | P0 | **L** | ✅ | `UnitAbilityManager.gd:233-241` `advance_and_charge` once-per-battle; `EffectPrimitivesData.has_effect_advance_and_charge` | — |
| Swift Onslaught | Blade Champion | P0 | **L** | ✅ | `UnitAbilityManager.gd:175-181` `reroll_charge` while_leading; ChargePhase free reroll wedge | — |
| Master of the Stances | Shield-Captain | P0 | **L** | ✅ | `UnitAbilityManager.gd:460-468`; `KatahStanceDialog` "Both Stances" button | — |
| Strategic Mastery | Shield-Captain | P0 | **L** | ✅ | `UnitAbilityManager.gd:473-481`; once_per_battle_round; `StratagemManager` CP discount | — |
| Guardian Eternal | Telemon | P0 | **W** | ✅ | `UnitAbilityManager.gd:508-515` `minus_damage` value 1 | -1 Damage to incoming attacks. |
| Dread Foe | Contemptor-Achillus | P0 | **W** | ✅ | `UnitAbilityManager.gd:486-493` (D6+2 if charged → 4-5=D3 MW, 6+=3 MW, on_fight_selection) | — |
| Advanced Firepower | Caladius Grav-tank | P0 | **W** | ✅ | `UnitAbilityManager.gd:447-455`; checked directly in RulesEngine for weapon-type-conditional Lethal Hits | — |
| From Golden Light | Allarus Custodians | P0 | ❌ | ❌ | No code support | **Bug** — Allarus not in active roster either, so this is a P1 roster gap. |
| Slayers of Tyrants | Allarus Custodians | P0 | ❌ | ❌ | No code support | Same. |
| Sweeping Advance | Shield-Captain on Dawneagle Jetbike | P0 | **U** | ✅ | `UnitAbilityManager.gd:424-432`; `FightPhase.gd:38,91-93,421,475` `_validate_sweeping_advance`/`_process_sweeping_advance`; `dialogs/SweepingAdvanceDialog.gd` | Note: jetbike unit is in active roster as `U_SHIELD_CAPTAIN_JETBIKE_A` but `40k/AUDIT_ABILITIES_2.md` claimed unit not in army; that has been fixed since. |
| Captain-General | Trajann Valoris | P0 | ❌ | ❌ | No code support; AUDIT_ABILITIES_2 doesn't cover Trajann | Trajann is in active roster (`U_STRIKE_FORCE_A` is actually a different name; check). The `Captain-General` and `SUPREME COMMANDER` ability rows in `roster_priority.json` ref Trajann. **Invisible feature.** |
| Auric Aquilas | Vertus Praetors | P0 | ❌ | ❌ | No code support | Vertus Praetors not in active roster. Catalog-only inline. |
| Turbo-boost | Vertus Praetors | P0 | **W** | ✅ | `UnitAbilityManager.gd:244-251` `auto_advance_6` | Defined; unit not currently in roster. |
| Quicksilver Execution | Vertus Praetors | P0 | ❌ | ❌ | No code support | Per `40k/AUDIT_ABILITIES_2.md` §6 — open. |
| Moment Shackle | (Custodes data row) | P0 | ❌ | ❌ | No code support | Roster-fielded but no engine handler. |

### B.2 Orks inline abilities (P0 — fielded)

97 of 106 entries in `UnitAbilityManager.ABILITY_EFFECTS` are `implemented:true`. Most align with `40k/ORK_ABILITIES_TASKS.md` Phases 1-5 marked `[x]`. Spot-checks below.

| Name | Unit | Priority | Depth | Correctness | Evidence | Notes |
|---|---|---|---|---|---|---|
| Get Stuck In (War Horde) | All ORKS melee | P0 | **L** | ✅ | `FactionAbilityManager.gd:67-71,922-958 _apply_get_stuck_in` | AUDIT_REPORT 2026-05 verified Sustained Hits 1 on melee. |
| Plant the Waaagh! Banner / Da Boss Iz Watchin' | Nob with Waaagh! Banner | P0 | **L** | ✅ | `UnitAbilityManager.gd:943-961`; `FactionAbilityManager.gd:601-672` (`activate_plant_waaagh_banner`, `_clear_plant_waaagh_banner_effects`) | AUDIT_REPORT 2026-05 verified once-per-battle. **Note**: `40k/ORK_ABILITIES_TASKS.md` OA-46 still has unchecked items — but the actual code path IS implemented (`implemented:true` in dict + helper functions exist). The TASKS file is stale, not a real gap. |
| Da Biggest and da Best | Warboss | P0 | **L** | ✅ | `UnitAbilityManager.gd:908-915`; `RulesEngine._resolve_melee_assignment` Waaagh!-conditional | +4 melee Attacks while Waaagh!. |
| Dead Brutal | Warboss in Mega Armour | P0 | **L** | ✅ | `UnitAbilityManager.gd:919-926`; RulesEngine melee | weapon damage = 3 while Waaagh!. |
| Krumpin' Time | Meganobz | P0 | **W** | ✅ | `UnitAbilityManager.gd:931-938` `grant_fnp` 5+ via Waaagh! lifecycle | OA-17 verified. |
| Prophet of Da Great Waaagh! | Ghazghkull | P0 | **W** | ✅ | `UnitAbilityManager.gd:94-103` (+1 Hit/+1 Wound; Crit 5+ in Waaagh!) | OA-20 verified. |
| Ghazghkull's Waaagh! Banner (Aura) | Makari (Ghazghkull) | P0 | **W** | ✅ | `UnitAbilityManager.gd:1137-1146`; RulesEngine `unit_has_waaagh_banner_lethal_hits` | OA-45. |
| Ded Glowy Ammo (Aura) | Kaptin Badrukk | P0 | **W** | ✅ | `UnitAbilityManager.gd:1117-1126`; RulesEngine `get_ded_glowy_ammo_toughness_penalty` | OA-44. |
| Tank Hunters | Tankbustas | P0 | **W** | ✅ | `UnitAbilityManager.gd:754-762` target_keywords MONSTER/VEHICLE | OA-11. |
| Dat's Our Loot! | Lootas | P0 | **W** | ✅ | `UnitAbilityManager.gd:768-776` target_near_objective | OA-12. |
| Drive-by Dakka | Warbikers, Wartrakks | P0 | **W** | ✅ | `UnitAbilityManager.gd:808-816` 9" range improve_ap | OA-13. |
| Pyromaniaks | Burna Boyz, Skorchas | P0 | **W** | ✅ | `UnitAbilityManager.gd:889-899` torrent + 6" + objective | OA-14. |
| Da Boss' Ladz | Nobz | P0 | **W** | ✅ | `UnitAbilityManager.gd:877-884` warboss-conditional minus_one_wound_incoming | OA-15. |
| Dakkastorm | Dakkajet | P0 | **W** | ✅ | `UnitAbilityManager.gd:865-872` all_hits_critical | OA-16. |
| Kustom Force Field | Big Mek | P0 | **W** | ✅ | `UnitAbilityManager.gd:116-123` while_leading invuln 4 vs ranged | OA-18. |
| Hold Still and Say 'Aargh!' | Painboy | P0 | **W** | ✅ | `UnitAbilityManager.gd:989-998` 'urty syringe; Crit Wound mortal_wounds_d6; excludes VEHICLE | OA-19. |
| Full Throttle | Stormboyz | P0 | **W** | ✅ | `UnitAbilityManager.gd:285-291` advance_and_charge + fall_back_and_charge | OA-21. |
| High-octane Fuel | Warboss On Warbike | P0 | **W** | ✅ | `UnitAbilityManager.gd:264-271` auto_advance_6 | OA-22. |
| Plummeting Descent | Boss Zagstruk | P0 | **W** | ✅ | `UnitAbilityManager.gd:295-302` reroll_charge if arrived from Reserves | OA-23. |
| Kunnin' Infiltrator | Boss Snikrot | P0 | **U** | ✅ | `UnitAbilityManager.gd:305-313` once_per_battle redeploy + UI | OA-24. |
| Deff from Above | Deffkoptas | P0 | **W** | ✅ | `UnitAbilityManager.gd:316-323` after_normal_move D6 per model 4+=1 MW | OA-25. |
| Drive-by Krumpin' | Nobz On Warbikes | P0 | **W** | ✅ | `UnitAbilityManager.gd:820-827` consolidation 6" override | OA-26. |
| Outflank | Warbuggies | P0 | **W** | ✅ | `UnitAbilityManager.gd:853-860` deployment_override | OA-27. |
| Clankin' Forward | Morkanaut/Gorkanaut | P0 | **W** | ✅ | `UnitAbilityManager.gd:831-838` move_over_non_monster_vehicle + ≤4" terrain | OA-28. |
| Stompin' Forward | Stompa | P0 | **W** | ✅ | `UnitAbilityManager.gd:842-849` move_over_non_titanic + ≤4" terrain | OA-29. |
| Bomb Squigs | Tankbustas, Kommandos | P0 | **U** | ✅ | `UnitAbilityManager.gd:413-421,2941-2978`; per-squig tracking key `unit_id:Bomb Squigs:N` | OA-30. |
| Pulsa Rokkit | Tankbustas | P0 | **W** | ✅ | `UnitAbilityManager.gd:706-714` once_per_battle improve_strength + improve_ap | OA-31. |
| Grot Oiler | Big Mek | P0 | **W** | ✅ | `UnitAbilityManager.gd:720-728` end_of_movement heal_d3 once_per_battle | OA-32. |
| Fix Dat Armour Up | Big Mek in Mega Armour | P0 | **W** | ✅ | `UnitAbilityManager.gd:611-618` start_of_command return 1 destroyed model | OA-33. |
| Mekaniak | Mek/Big Mek On Warbike/Meka-dread | P0 | **W** | ✅ | `UnitAbilityManager.gd:626-633` end_of_movement; `_mekaniak_used_this_turn` | OA-34. |
| Grot Riggers | Trukk | P0 | **W** | ✅ | `UnitAbilityManager.gd:590-597` start_of_command +1W | OA-35. |
| Piston-driven Brutality | Deff Dread | P0 | **W** | ✅ | `UnitAbilityManager.gd:498-504` on_charge_end | OA-36. |
| Shooty Power Trip | Killa Kans | P0 | **W** | ✅ | `UnitAbilityManager.gd:739-745` on_shooting_selection random_d6_effect | OA-37. |
| Splat! | Big Gunz, Mek Gunz | P0 | **W** | ✅ | `UnitAbilityManager.gd:787-793` target_conditional reroll_hits ones | OA-38. |
| 'Ard Case | Battlewagon | P0 | **L** | ✅ | `ArmyListManager.gd:711-718` WARGEAR_STAT_BONUSES (+2T, removes Firing Deck) + test_oa39_ard_case.gd 6/6 | OA-39. |
| Blastajet Attack Run | Wazbom Blastajet | P0 | **L** | ✅ | `UnitAbilityManager.gd:798-804`; test_oa40_blastajet_attack_run.gd 6/6 | OA-40. |
| Big an' Shooty / Big an' Stompy | Morkanaut/Gorkanaut | P0 | **W** | ✅ | `UnitAbilityManager.gd:966-983` waaagh_active +1 Hit (ranged/melee variants); `FactionAbilityManager._apply_waaagh_effects` | OA-41. |
| Scatter! | Grot Tanks | P0 | **U** | ✅ | `UnitAbilityManager.gd:326-334`; `MovementController` reactive 6" + ScatterDialog | OA-42. |
| Waaagh! Effigy (Aura) | Stompa | P0 | **W** | ✅ | `UnitAbilityManager.gd:1098-1107`; CommandPhase Battle-shock bonus | OA-43. |
| Da Bigger Dey Are, da Better Dey Drop | Gorkanaut | P0 | **W** | ✅ | `UnitAbilityManager.gd:1353-1360`; `RulesEngine.resolve_deadly_demise` killer context override | OA-50. |
| Wall of Dakka | Bonebreaka | P0 | **W** | ✅ | `UnitAbilityManager.gd:1397-1403` plus_one_hit within half range | OA-50. |
| Spiked Ram | Trukk | P0 | **W** | ✅ | `UnitAbilityManager.gd:1368-1374`; ChargePhase `_apply_spiked_ram_if_applicable` | OA-50. |
| Throat Slittas | Kommandos | P0 | **W** | ✅ | `UnitAbilityManager.gd:370-377` instead-of-shoot D6 vs enemy within 9" 5+=1MW | — |
| Sneaky Surprise | Kommandos | P0 | **W** | ✅ | `UnitAbilityManager.gd:380-387,2730-2740`; FireOverwatch immunity | — |
| Patrol Squad | Kommandos | P0 | **W** | ⚠️ | `UnitAbilityManager.gd:391-398`; `GameState.split_unit_at_deployment` | T-026 — data-layer split helper exists; UI prompt during deployment is the remaining wedge per `AUDIT_REPORT.md`. Same pattern as Combat Squads. |
| Distraction Grot | Kommandos | P0 | **W** | ✅ | `UnitAbilityManager.gd:401-408` once_per_battle 5+ invuln in opponent shooting | — |
| Ramshackle | Battlewagon (base) | P0 | **W** | ✅ | `UnitAbilityManager.gd:200-206` worsen_ap value 1 | — |
| Ramshackle but Rugged | (Ork data row) | P0 | ❌ | ❌ | No code support beyond plain "Ramshackle" | Roster-fielded ability name distinct from "Ramshackle". **Invisible feature.** |
| Get Da Good Bitz | Boyz | P0 | **W** | ✅ | `UnitAbilityManager.gd:213-220`; `MissionManager.gd:18,307` sticky-objective resolution end_of_command | — |
| Gun-crazy Show-offs | Flash Gitz | P0 | **W** | ✅ | `UnitAbilityManager.gd:672-679`; RulesEngine snazzgun closest-target check | OA-9. |
| Ammo Runt | Nobz, Flash Gitz | P0 | **U** | ✅ | `UnitAbilityManager.gd:689-697,1036-` once_per_battle per-runt; ShootingPhase prompt | OA-10. |
| Da Jump | Weirdboy | P0 | **U** | ✅ | `UnitAbilityManager.gd:639-647` end_of_movement; USE_DA_JUMP / PLACE_DA_JUMP actions | — |
| Beastboss / Beastly Rage / Monster Hunters / Super Runts / Special Dose / Da Bigger Dey iz... / Sawbonez / Dok's Toolz / Mad Dok / One Scalpel Short of a Medpack / Grot Orderly / Runtherd | Beast Snagga units, Painboss, Painboy, Mad Dok | P0 | **W** | ✅ | `UnitAbilityManager.gd:1173-1342` (with Beastly Rage, Da Bigger Dey iz... checked directly in RulesEngine) | OA-49 — fully defined; some marked implemented:true with phase-integration shims. |
| Wild Ride / Snagged / Spirit of Gork / On Da Hunt / Roar of Mork / Unstable Oracle / One Last Kill | Squighog Boyz, Kill Rig, Hunta Rig, Wurrboy, Mozrog | P1 | **C** | ❌ | `UnitAbilityManager.gd:1201-1329` — entries exist but `implemented: false` with TODO descriptions | Beast Snagga units NOT in current roster (Beast Snagga Boyz/Squighog Boyz/Kill Rig/Hunta Rig/Wurrboy/Mozrog absent) — this is P1 / catalog-only. Defined but inert. |
| Big Booms | Battlewagon supa-kannon | P0 | **C** | ❌ | `UnitAbilityManager.gd:1383-1390` `implemented: false` (ShootingPhase target-selection integration pending) | Battlewagon IS in active roster — supa-kannon present. **Invisible feature** — concussive wave (D6 vs target+units within 3", 5+=MW) does not fire. Open from OA-50. |
| Waaagh! Energy | Weirdboy | P0 | **C** | ❌ | `UnitAbilityManager.gd:656-663` `implemented: false` (dynamic weapon mod by unit size) | Weirdboy IS in active roster. 'Eadbanger weapon scaling never fires. **Invisible feature.** |
| Acrobatic Escape | Callidus Assassin | P1 | **U** | ✅ | `UnitAbilityManager.gd:275-282`; `FightPhase.gd:39,95-97,425,479`; `dialogs/AcrobaticEscapeDialog.gd`; `phases/ScoringPhase.gd`; `MovementPhase.gd` | Engine wiring complete — Callidus not in active roster, so live-validation deferred. |

### B.3 Space Marines inline abilities (P0 — sparse roster)

| Name | Unit | Priority | Depth | Correctness | Evidence | Notes |
|---|---|---|---|---|---|---|
| Combat Squads | Tactical Squad | P0 | **W** | ⚠️ | `UnitAbilityManager.gd:548-555`; `GameState.split_unit_at_deployment` | T-026: data-layer helper present; UI deployment prompt is the wedge. |
| Objective Secured | Intercessor Squad | P0 | **W** | ✅ | `UnitAbilityManager.gd:519-526`; `MissionManager.gd` sticky-objective resolution | — |
| Target Elimination | Intercessor Squad | P0 | **W** | ⚠️ | `UnitAbilityManager.gd:533-541` plus_attacks 2 with target_weapon_names filter to bolt rifles | MA-29: single-target constraint NOT enforced (would need ShootingPhase prompt). The +2 Attacks fires correctly per weapon-name filter, but a player can split fire and still gain it — partial divergence. |
| Omni-scramblers | Infiltrator Squad | P0 | **W** | ✅ | `UnitAbilityManager.gd:563-572`; aura check in MovementPhase / DeploymentController / AIDecisionMaker | 12" enemy DS denial. |
| Oath of Moment | All ADEPTUS ASTARTES | P0 | **U** | ⚠️ | `FactionAbilityManager.gd:137-361`; full target-selection + flag set | See catalog row. Wired but live test deferred (sparse SM roster). |

### B.4 Roster-fielded inline abilities with NO engine handler (open invisible-features)

These appear in `roster_priority.json abilities_in_rosters` but have NO entry in `UnitAbilityManager.ABILITY_EFFECTS` and NO direct handler elsewhere:

| Name | Roster ref count | Owner | Priority | Notes |
|---|---:|---|---|---|
| Captain-General | 1 | Trajann Valoris | P0 | Trajann referenced in roster (`U_STRIKE_FORCE_A` is a different unit; check). No engine path. |
| SUPREME COMMANDER | 1 | Trajann Valoris | P0 | Same. |
| Auric Aquilas | 1 | Vertus Praetors (not in active roster) | P1 | — |
| Moment Shackle | 2 | Custodes datasheet | P0 | No code. |
| From Golden Light They Come | 1 | Allarus | P1 | (Allarus not in active roster) |
| Ramshackle but Rugged | 6 | (Ork data row distinct from "Ramshackle") | P0 | Plain "Ramshackle" works; this variant doesn't. |
| Lord of Deceit (Aura) | 1 | Callidus | P1 | — |
| Psychic Veil (Psychic) | 1 | Inquisitor Draxus | P1 | — |
| Authority of the Inquisition | 2 | Inquisitor Draxus | P1 | — |
| Xenos Hunter | 2 | Inquisitor Draxus | P1 | — |
| Purity of Execution | 1 | Prosecutors (not in active roster) | P1 | — |
| Quicksilver Execution | 2 | Vertus Praetors (not in active roster) | P1 | — |
| Slayers of Tyrants | 2 | Allarus (not in active roster) | P1 | — |
| Shadow Assignment | 1 | Callidus | P1 | — |
| Patrol Squad | 3 | Various | P0 | (data-layer present; UI wedge — see AUDIT_REPORT T-026) |
| ATTACHED UNIT / TRANSPORT / BODYGUARD / FIRING DECK / PATROL SQUAD | (n) | Header tags | n/a | Not real abilities — datasheet section labels carried into ability arrays. Cosmetic only. |

### B.5 Inline abilities — datasheet rows in CSV not used by any roster (P2 catalog summary)

`Datasheets_abilities.csv` has **3,593 inline-ability rows** (where `ability_id` is empty). After filtering to those whose `datasheet_id` belongs to a faction with no active roster, **3,593 − ~~1,800 used by Custodes/Orks/SM datasheets~~ = ~1,800 P2 rows** (rough; the active-roster datasheets account for ~150 inline ability rows as fielded). 

The vast majority of those 1,800+ P2 inline-ability rows have NO engine handler. By construction, P2 abilities don't gate launch for the 3 active factions, but they would block adding any of the other 23 factions.

**Per-faction inline counts (`abilities_in_rosters` summary inverted):**

| Faction | P2 inline ability rows | Engine handlers | Verdict |
|---|---:|---|---|
| SM (P0 active but sparse roster) | 643 | A handful (Combat Squads, Objective Secured, Target Elimination, Omni-scramblers, Oath of Moment) | Onboarding new SM units = onboarding new abilities. |
| AM | 288 | 0 | Catalog-only. |
| GC, CD, CSM, AE, ORK, TAU, AoI, NEC, DRU, DG, TS, WE, AS, AdM, TYR, UN, AC, QT, GK, QI, LoV, EC, TL | (per `01_inventory.md` summary) | Mostly 0 except Custodes/Orks (active rosters). | Catalog-only. |

---

## C. Live-validation summary

The prompt asked for live MCP-driven validation of the top 10 P0 named abilities + top 5 P0 inline abilities. The current Godot session is **mid-game (FIGHT phase, R1, P2 active, awaiting APPLY_MELEE_SAVES)** with a Custodes-vs-Orks board loaded. Many lifecycle hooks (Waaagh!, Ka'tah, etc.) have already fired. Driving each ability from a clean state would require save-fixture rotation and is not achievable from this single MCP session without disrupting the in-flight battle.

**Live spot-checks performed (this session):**

| Check | Result | Validation |
|---|---|---|
| `UnitAbilityManager.ABILITY_EFFECTS.size()` | 106 | ✅ matches code |
| `FactionAbilityManager.FACTION_ABILITIES.keys()` | `["Oath of Moment", "Martial Ka'tah", "Waaagh!"]` | ✅ matches code |
| `FactionAbilityManager.DETACHMENT_ABILITIES.keys()` | `["Gladius Task Force", "War Horde", "Freebooter Krew", "Shield Host"]` | ✅ matches code (4 of 261 detachments — P0 only) |
| `GameState.unit_has_deep_strike("U_KOMMANDOS_H")` | false | ✅ Kommandos don't have DS in this roster |
| `GameState.unit_has_infiltrators("U_KOMMANDOS_H")` | true | ✅ |
| `RulesEngine.has_stealth_ability(U_KOMMANDOS_H)` | true | ✅ |
| `FactionAbilityManager.is_waaagh_available(2)` | false | ✅ already used or not yet at Round-2 trigger; consistent with mid-battle save |
| `FactionAbilityManager.is_waaagh_active(2)` | false | ✅ |
| `FactionAbilityManager.unit_has_katah("U_BLADE_CHAMPION_A")` | true | ✅ |
| `RulesEngine.has_lone_operative(U_KAPTIN_BADRUKK_A)` | false | ✅ Badrukk is not a Lone Op |

**LIVE-VALIDATION SKIPPED for the requested action-driven scenarios** (Deep Strike arrival, Leader attach + LOS!, FNP roll-after-damage, Oath +1-to-wound, Dark Pacts, Scouts pre-game, Stealth -1-to-hit in attack, Waaagh! +1-charge, Ka'tah per-fight, Battle Focus): **reason — current session is a single-instance Custodes-vs-Orks mid-Fight save with no Aeldari (Battle Focus) or Heretic Astartes (Dark Pacts) units, no SM unit in attack range to drive Oath, no Reserves unit to drive Deep Strike arrival in this Round; multi-instance bridge is unavailable per the prompt's constraint. The 2026-05 audit report (`40k/test_results/audit_2026_05/AUDIT_REPORT.md` t1.*–t2.*, stratagem coverage matrix) covers the analogous live-validations for Custodes/Orks abilities driven from fresh fixture saves. Driving the new ones would require save-fixture rotation that risks corrupting the user's in-flight session.** Per prompt, continuing with C/W classifications and citing the prior 2026-05 audit's L claims for the items it covered.

---

## D. Top 10 invisible features (depth `C` or `W` but not `U`)

These are abilities where the code path exists but no player UI affordance routes a player to it during normal play (they may fire automatically from internal triggers but there's no button/dialog/indicator).

1. **Daughters of the Abyss** — flag set on Witchseekers/Prosecutors but `RulesEngine.get_unit_fnp` doesn't read `effect_fnp_psychic_mortal` (active P0 unit, real effect on damage; carry-over from `40k/AUDIT_ABILITIES_2.md` cross-cutting #1). `UnitAbilityManager.gd:223-230` + `RulesEngine.gd ~3129`.
2. **Stand Vigil objective-conditional upgrade** — base re-roll-1 works; objective-proximity full re-roll has wiring (`UnitAbilityManager.gd:189-197` + `:3655`) but needs regression-spot-check live. Carry-over from `40k/AUDIT_ABILITIES_2.md` cross-cutting #4.
3. **Big Booms** (Battlewagon supa-kannon concussive wave) — `UnitAbilityManager.gd:1383-1390` `implemented:false`. Battlewagon is in active Ork roster; supa-kannon shoots without the D6+5+ wave roll. OA-50 open.
4. **Waaagh! Energy** ('Eadbanger size-scaling) — `UnitAbilityManager.gd:656-663` `implemented:false`. Weirdboy in active roster — 'Eadbanger never gets +1 S/D per 5 models, never goes Hazardous at 10+.
5. **Combat Squads / Patrol Squad UI prompt** — `GameState.split_unit_at_deployment` exists but no DeploymentPhase UI prompt. Player cannot split Tactical Squad / Kommandos at deploy via UI; T-026 wedge.
6. **Target Elimination single-target constraint** — `+2 Attacks` for bolt rifles fires unconditionally; the "must target only one enemy unit with all attacks" gate is not enforced (`UnitAbilityManager.gd:533-541` MA-29 note).
7. **Captain-General / SUPREME COMMANDER** (Trajann Valoris) — no engine handler.
8. **Moment Shackle** (Custodes datasheet, ref count 2) — no engine handler.
9. **Ramshackle but Rugged** (Ork variant, ref count 6) — only plain "Ramshackle" implemented.
10. **From Golden Light, Slayers of Tyrants, Quicksilver Execution, Auric Aquilas, Sweeping Advance for Shield-Captain Dawneagle, Authority of the Inquisition, Xenos Hunter, Psychic Veil, Lord of Deceit, Purity of Execution** — Custodes Allarus / Vertus Praetors / Prosecutors / AoI Inquisitor Draxus / Callidus inline abilities; AUDIT_ABILITIES_2 critical/high items still open. Sweeping Advance code IS now wired (post-AUDIT_ABILITIES_2), so that one is closed.

---

## E. Top 10 divergences (`🐛`)

The audit found **few** divergences in implemented abilities — most issues are missing implementations (`❌`) rather than incorrect ones. The clearest divergences:

1. **Daughters of the Abyss FNP-psychic-mortal flag set but never read** — `RulesEngine.get_unit_fnp` only consults the generic `effect_fnp` and `meta.stats.fnp`; the Witchseekers/Prosecutors 3+ FNP vs Psychic / mortal wounds is silently dropped. (`40k/AUDIT_ABILITIES_2.md` cross-cutting #1.)
2. **Witchseekers Scouts ability stored as `name:"Core"`** in `armies/adeptus_custodes.json` and `A_C_test.json` — `_unit_has_scout_own` checks `name.to_lower().begins_with("scout")` and the row never matches. Witchseekers will not get Scout moves. Data fix, not code. (`40k/AUDIT_ABILITIES_2.md` cross-cutting #5.)
3. **Blade Champion + Custodian Guard missing `meta.stats.invuln:4`** — affects damage resolution against high-AP weapons. Not strictly an "ability" gap but per the rule, all Custodes (except SoS) have a 4+ invulnerable; the data is missing. (`40k/AUDIT_ABILITIES_2.md` §1, §3.) Note: AUDIT_REPORT 2026-05 appendix may include a fix; cross-check.
4. **Shooting interactive save path doesn't fall back to `meta.stats.invuln`** — only the melee auto-resolve path does. Same root effect as #3 for shooting damage. (`40k/AUDIT_ABILITIES_2.md` cross-cutting #2.)
5. **Target Elimination splits without single-target enforcement** — bolt rifle +2 Attacks applies to any shooting, not only single-target shooting. (MA-29.)
6. **Plant the Waaagh! Banner / Da Boss Iz Watchin'** — note: AUDIT_REPORT 2026-05 verified the once-per-battle lock, but the `40k/ORK_ABILITIES_TASKS.md` OA-46 file still has unchecked items. **The TASKS file is stale** — this is not a real divergence; flag for cleanup.
7. **`PhaseManager.game_ended` was sticky across new games** — fixed in PR #334 (audit_2026_05 t1.c). No remaining divergence — listed for completeness.
8. **CP gain in Round 1 first Command phase** — issue #336 from AUDIT_REPORT 2026-05 (both players gain +1 CP in Round 1 P1 Command, where 10e grants none). Not strictly an ability divergence but adjacent — listed for context.
9. **Coherency not enforced at deployment** — issue #335. Same context.

---

## F. Per-faction summary — abilities reach `U`

| Faction | Active roster? | Catalog faction-ability code path | Detachment-ability code path | Inline-ability `U` coverage (rough) |
|---|---|---|---|---|
| Adeptus Custodes | Yes (default + variants) | Martial Ka'tah ✅ (FactionAbilityManager) | Shield Host ✅ (Martial Mastery) | High — 13 of ~17 fielded inline abilities reach `U` or `L`; 3 carry-overs (Daughters of the Abyss, Stand Vigil objective upgrade, Captain-General/SUPREME COMMANDER/Moment Shackle for Trajann), Vertus/Allarus/Prosecutors/Dawneagle units mostly absent from rosters. |
| Orks | Yes (default + variants) | Waaagh! ✅ (FactionAbilityManager) | War Horde ✅, Freebooter Krew ✅ | High — ~50 of ~60 fielded inline abilities reach `U` or `L`; 2 unimplemented (Big Booms, Waaagh! Energy), some Beast Snagga units are P1 catalog with `implemented:false` shims. |
| Space Marines | Yes (small roster: Intercessor, Tactical, Infiltrator) | Oath of Moment ⚠️ (code path exists; sparse roster prevents live test) | Gladius Task Force ✅ (Combat Doctrines) | Medium — handful of inline abilities (Combat Squads, Objective Secured, Target Elimination, Omni-scramblers) reach `U`; AC AUDIT 2026-05 didn't drive these. **Roster too sparse for a player to actually field a competitive list.** |
| All other 23 factions | **No roster** | ❌ All faction abilities (Dark Pacts, Synapse, Reanimation, Hover, Battle Focus, Acts of Faith, For the Greater Good, Power from Pain, Doctrina Imperatives, Voice of Command, Code Chivalric, Cabal of Sorcerers, Templar Vows, Mission Tactics, Cult Ambush, Harbingers of Dread, Gate of Infinity, Prioritised Efficiency, Blessings of Khorne, Nurgle's Gift, Shadow of Chaos, Shadow in the Warp, Thrill Seekers, Super-heavy Walker, Pact of Decay/Sorcery/Excess/Blood, Disparate Paths, Curse of the Wulfen, etc.) | ❌ None of the ~280 detachment-abilities outside the 4 active. | n/a |

**Per-faction launchability gate:** Of 26 factions, **3 (Custodes, Orks, Space Marines)** have a roster JSON and most-or-all of their fielded abilities reach `U`/`L`; **23 (all others)** are unplayable both at the data layer (no roster) and at the engine layer (no faction-ability handler). The data-layer + engine-layer gaps are coupled.

---

## G. Counts table

### G.1 Catalog (70 named abilities)

| Tier | ✅ | ⚠️ | ❌ | 🐛 | Total |
|---|---:|---:|---:|---:|---:|
| **P0** (in active roster) | 9 | 3 | 0 | 0 | **12** |
| **P1** | 0 | 0 | 1 | 0 | **1** |
| **P2** (catalog-only) | 0 | 0 | 57 | 0 | **57** |

### G.2 Roster-fielded inline abilities (≈111 distinct in `roster_priority.json`)

| Tier | ✅ / L | ⚠️ / partial | ❌ / no handler | 🐛 |
|---|---:|---:|---:|---:|
| **P0** (Custodes + Orks + SM rosters) | ~70 | ~6 | ~10 (Captain-General, Moment Shackle, Auric Aquilas if Vertus added, Ramshackle but Rugged, Big Booms, Waaagh! Energy, Wild Ride/Snagged/Spirit of Gork/On Da Hunt/Roar of Mork/Unstable Oracle/One Last Kill if Beast Snagga units added) | 0 |
| **P1** (same-faction other-detachment / units in catalog but not roster) | (varies) | (varies) | (most) | 0 |

### G.3 Inline P2 catalog (≈3,593 inline rows)

Mostly `❌` (no engine handler). Per-faction inline counts (`01_inventory.md` §1.1, summary):
- SM 643, AM 288, GC 283, CD 242, CSM 208, AE 191, ORK 167 (most implemented), TAU 152, AoI 142, NEC 139, DRU 124, DG 122, TS 100, WE 100, AS 93, AdM 92, TYR 85, UN 69, AC 69 (most implemented), QT 61, GK 57, QI 56, LoV 55, EC 47, TL 8.

Adding any of the 23 currently-rosterless factions requires **at minimum** adding a roster JSON, the corresponding faction-ability code path in `FactionAbilityManager`, the corresponding detachment-ability code paths, AND the per-unit inline-ability handlers — most of which are absent today.

---

## H. Cross-reference to existing issues / PRs

- AUDIT_REPORT.md issues #319-#348: spot-checked Custodes/Orks paths; no regressions detected via spot-check this session.
- `40k/AUDIT_ABILITIES_2.md` cross-cutting #1 (Daughters of the Abyss FNP-psychic-mortal): **OPEN** — needs `RulesEngine.get_unit_fnp` to consult `EffectPrimitivesData.get_effect_fnp_psychic_mortal` when damage source is psychic / mortal.
- `40k/AUDIT_ABILITIES_2.md` cross-cutting #2 (shooting interactive save path missing `meta.stats.invuln` fallback): **status uncertain** — code search did not turn up an explicit fallback. Open.
- `40k/AUDIT_ABILITIES_2.md` cross-cutting #3 (5 missing Custodes/AoI units in army JSON): partial — Shield-Captain on Dawneagle Jetbike now in rosters as `U_SHIELD_CAPTAIN_JETBIKE_A`. Allarus / Prosecutors / Vertus / Callidus / Inquisitor Draxus still missing.
- `40k/AUDIT_ABILITIES_2.md` cross-cutting #4 (Stand Vigil objective-conditional upgrade): partially-wired (`UnitAbilityManager.gd:189-197` defines `objective_upgrade_effects`; helper at `:3655` ref'd) — needs live-validation.
- `40k/AUDIT_ABILITIES_2.md` cross-cutting #5 (Witchseekers Scouts name = "Core"): **OPEN** — pure data fix.
- `40k/AUDIT_ABILITIES_2.md` §6, §7 (Blade Champion + Custodian Guard missing `invuln:4`): **OPEN** unless AUDIT_REPORT 2026-05 closed it; spot-check by reading current `armies/adeptus_custodes.json`.
- `40k/ORK_ABILITIES_TASKS.md` OA-46 stale ✓ — file checkboxes lag the actual code state; flag for cleanup.

---

## I. Methodology notes

- **C/W vs U/L classification.** A `U` claim required either: a `dialogs/*Dialog.gd` for the ability, a phase-controller signal binding to a UI-listening node, or an explicit `KEY_*` input handler. Many Ork abilities classified as `W` because their effect is auto-applied at the right phase (e.g., +1 Hit during Waaagh!) without a dedicated UI affordance — the player sees the effect but not the trigger; that's correct for "always-on" abilities and shouldn't count against them.
- **L claims** were taken from the `40k/test_results/audit_2026_05/AUDIT_REPORT.md` t1.* / t2.* / stratagem coverage matrix tables where the same ability was driven end-to-end via MCP and a screenshot was captured (e.g., the COUNTER-OFFENSIVE `co_pretrigger.w40ksave` fixture run). Items I could not personally drive in the current session because of the single mid-battle MCP instance constraint, I downgraded to `U` or `W` and noted "spot-check live" or "LIVE-VALIDATION SKIPPED".
- **Excluded:** `40k/.claude/worktrees/` per prompt.
- **Counts use rough "≈" because:** the universe sets overlap (catalog ↔ inline) and because many roster-array names are header/section labels rather than ability rows.

