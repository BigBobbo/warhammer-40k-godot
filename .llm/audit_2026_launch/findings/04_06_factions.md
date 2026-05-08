# 04.06 — Factions, Rosters, and Datasheet Coverage — Findings

**Generated:** 2026-05-06
**Auditor:** general-purpose agent (Opus 4.7 1M)
**Output of prompt:** `.llm/audit_2026_launch/04_data_entities/06_factions_rosters.md`

---

## Headlines

| Number | Value |
|---|---:|
| **Launchable factions out of 26** | **3** (Adeptus Custodes, Orks, Space Marines) |
| **Launchable detachments out of 261 (203 non-Boarding)** | **3** (Shield Host, War Horde, Gladius Task Force) — 4th defined in code (`Freebooter Krew`) but no roster JSON exercises it |
| Detachment-ability rows in CSV | 284 |
| Detachment abilities implemented in code | **3 of 284 (~1.06%)** — `Combat Doctrines`, `Get Stuck In`, `Martial Mastery` |
| Catalog datasheets (Datasheets.csv) | 1,710 |
| Datasheets fielded across all 10 roster JSONs | 46 distinct (`(faction × unit_name)`); ~3% of catalog |
| Distinct rosters in `40k/armies/` | 10 JSON files, **all** for AC / Orks / SM |
| Wahapedia CSV files loaded by runtime code | 3 of 19 (`Factions.csv`, `Stratagems.csv`, `Detachments.csv` via `FactionStratagemLoader.gd`) |
| In-app army builder UI | **None** — flat dropdown of pre-existing JSON files; no faction picker, no detachment selector, no unit catalog browser |

The "launchable detachments out of 261" number deserves a footnote: even the 3 implemented detachments load only 6 stratagems each from CSV; the same 3 detachments are the only ones the codebase recognises as having a detachment army-rule effect (e.g. Combat Doctrines, Get Stuck In, Martial Mastery). The remaining 258 detachments fail the `≥80% bar` from `04_05_enhancements_detachments.md` because their detachment ability has no engine handler.

---

## Live-validation notes

- MCP bridge reachable (`ping` ok, engine `4.6-stable`). Game was mid-Fight in a P1=Custodes / P2=Orks match (`Main.tscn`).
- `ArmyListManager.get_available_armies()` returns 10 entries — confirmed live: `Orks_Upload_Mar7`, `adeptus_custodes_roster_stubs`, `orks`, `adeptus_custodes`, `Orks_2000_upload`, `space_marines`, `Orks_2000`, `A_C_test`, `ORK_test`, `Adeptus_Custodes_1995_Mar_7`.
- `FactionAbilityManager.DETACHMENT_ABILITIES.keys()` returns exactly `["Gladius Task Force", "War Horde", "Freebooter Krew", "Shield Host"]`.
- `FactionAbilityManager.FACTION_ABILITIES.keys()` returns exactly `["Oath of Moment", "Martial Ka'tah", "Waaagh!"]`.
- `FactionAbilityManager.detect_player_detachment(1)` → `"Shield Host"`; `(2)` → `"War Horde"`. Detachment is correctly persisted in `state.factions[player].detachment` and surfaced into `_player_detachment` on demand.
- `ArmyListManager.load_army_list("aeldari", 1)` and `load_army_list("tyranids", 1)` both return `{}` (file-not-found path). **No Aeldari roster can be loaded; no UI exists to construct one.** This is the failure mode the prompt asked us to flag.
- Screenshot of running game: `/Users/robertocallaghan/Library/Application Support/Godot/app_userdata/40k/test_screenshots/factions_audit_running_state.png` — shows P1 Adeptus Custodes vs P2 Orks Fight Phase, confirming the live game uses the 3 supported factions.
- `LIVE-VALIDATION SKIPPED` for: "build a roster from each playable faction in the army-builder UI" — there is no army-builder UI to drive (`MainMenu.gd:488` and `MultiplayerLobby.gd:756` only present a flat dropdown of JSON filenames and have no add/edit/build affordance).

---

## 1. Per-faction roll-up (26 factions in `Factions.csv`)

`Factions.csv` rows: 26 (the prompt says 26, while Stage 1 inventory says `Factions.csv` has 27 rows — that 27th row is the header line that Stage 1 counts as a row). Verified by hand: `Factions.csv:1-27` lists 26 `id|name|link` data rows.

Counts in the table below come from:
- `Datasheets.csv` filtered by `faction_id`
- `Detachments.csv` filtered by `faction_id`, with the Boarding-Actions subset called out
- `40k/armies/*.json` scan (`/Users/robertocallaghan/Documents/claude/godotv2/40k/armies/`) for "Datasheets in any roster"
- `FactionAbilityManager.DETACHMENT_ABILITIES` and `FACTION_ABILITIES` dictionaries

| Faction (CSV id) | Datasheets in CSV | Datasheets in any roster | Detachments in CSV (non-BA / BA) | Detachments selectable in rosters | Faction army-rule implemented? | Roster engine-handler abilities (out of distinct named in roster) |
|---|---:|---:|---:|---:|:---:|:---:|
| Imperial Agents (AoI) | 46 | 0 | 5 / 2 | 0 | ❌ | n/a |
| Astra Militarum (AM) | 133 | 0 | 9 / 2 | 0 | ❌ | n/a |
| Genestealer Cults (GC) | 138 | 0 | 6 / 3 | 0 | ❌ | n/a |
| Necrons (NEC) | 64 | 0 | 9 / 4 | 0 | ❌ | n/a |
| Aeldari (AE) | 97 | 0 | 12 / 4 | 0 | ❌ | n/a |
| Adeptus Titanicus (TL) | 4 | 0 | 0 / 0 | 0 | ❌ | n/a |
| **Orks (ORK)** | 87 | 27 distinct names | 11 / 2 | **1 (`War Horde`)** + `Freebooter Krew` defined in code but no roster | ✅ `Waaagh!`, `Get Stuck In` (War Horde) | ~38 of ~50 named abilities seen in Ork rosters have entries in `UnitAbilityManager.ABILITY_EFFECTS` |
| Unaligned Forces (UN) | 20 | 0 | 0 / 0 | 0 | ❌ | n/a |
| Grey Knights (GK) | 31 | 0 | 6 / 2 | 0 | ❌ | n/a |
| T'au Empire (TAU) | 63 | 0 | 6 / 2 | 0 | ❌ | n/a |
| Leagues of Votann (LoV) | 22 | 0 | 7 / 2 | 0 | ❌ | n/a |
| Adeptus Mechanicus (AdM) | 39 | 0 | 7 / 3 | 0 | ❌ | n/a |
| Thousand Sons (TS) | 60 | 0 | 6 / 3 | 0 | ❌ | n/a |
| Death Guard (DG) | 71 | 0 | 7 / 3 | 0 | ❌ | n/a |
| Emperor's Children (EC) | 23 | 0 | 7 / 0 | 0 | ❌ | n/a |
| World Eaters (WE) | 58 | 0 | 6 / 2 | 0 | ❌ | n/a |
| Chaos Knights (QT) | 37 | 0 | 6 / 0 | 0 | ❌ | n/a |
| Chaos Daemons (CD) | 106 | 0 | 6 / 5 | 0 | ❌ | n/a |
| Imperial Knights (QI) | 28 | 0 | 6 / 0 | 0 | ❌ | n/a |
| **Space Marines (SM)** | 298 | 3 distinct names (Intercessor / Tactical / Infiltrator) | 40 / 4 | **1 (`Gladius Task Force`)** | ✅ `Oath of Moment`, `Combat Doctrines` (Gladius) | 2 of 5 named abilities seen (`Oath of Moment`, `Combat Squads`, `Objective Secured`, `Target Elimination`, `Omni-scramblers`) — `Objective Secured`, `Target Elimination`, `Combat Squads`, `Omni-scramblers` all defined in `UnitAbilityManager` |
| Tyranids (TYR) | 56 | 0 | 8 / 4 | 0 | ❌ | n/a |
| **Adeptus Custodes (AC)** | 31 | 16 distinct names | 6 / 2 | **1 (`Shield Host`)** | ✅ `Martial Ka'tah`, `Martial Mastery` (Shield Host) | ~24 of ~30 named abilities; `Sweeping Advance`, `Strategic Mastery`, `Master of the Stances`, `Daughters of the Abyss`, `Sanctified Flames`, `Stand Vigil`, `Sentinel Storm`, `Swift Onslaught`, `Martial Inspiration`, `Advanced Firepower`, `Guardian Eternal`, `Dread Foe` all in `UnitAbilityManager` |
| Adepta Sororitas (AS) | 38 | 0 | 5 / 2 | 0 | ❌ | n/a |
| Chaos Space Marines (CSM) | 112 | 0 | 15 / 3 | 0 | ❌ | n/a |
| Drukhari (DRU) | 47 | 0 | 6 / 4 | 0 | ❌ | n/a |
| Unbound Adversaries (UA) | 0 | 0 | 0 / 0 | 0 | ❌ | n/a |

> **Detachment counts** above sum to 203 non-Boarding + 58 Boarding = 261 (verified `awk` over `Detachments.csv:1-261` with type=="Boarding Actions"). Per-faction values were computed via `awk -F'|' 'NR>1 && $5!="Boarding Actions"' Detachments.csv | uniq -c`.

> **Roster-fielded distinct unit names**: 46 total — Custodes 16, Orks 27, SM 3 (computed from all 10 `40k/armies/*.json`).

---

## 2. Per-detachment depth (the 3 + 1 detachments the engine recognises)

For each detachment the engine recognises, I cross-referenced:
- `FactionAbilityManager.DETACHMENT_ABILITIES` (`40k/autoloads/FactionAbilityManager.gd:41-97`) for the army-rule effect
- `Stratagems.csv` filtered to that detachment for stratagem count
- `Enhancements.csv` filtered to that detachment for enhancement count
- The cross-reference findings file `04_05_enhancements_detachments.md` for `≥80%` launchability bar (this file is the canonical source for that judgment; this audit just reports the per-detachment numbers)

| Faction × Detachment | Detachment ability | Stratagems in CSV | Enhancements in CSV | Verdict |
|---|---|---:|---:|---|
| Adeptus Custodes × Shield Host | ✅ `Martial Mastery` (`FactionAbilityManager.gd:79-96`, `957-1085`) — start-of-round one of two effects (crit on 5+ melee or +1 AP melee) | 6 | 4 (per `Enhancements.csv` `detachment="Shield Host"`) | **Launchable.** The detachment ability, faction ability `Martial Ka'tah` (`FactionAbilityManager.gd:145-155`), and at least the 6 stratagems (Defensive Stance, Stoic Fortitude, etc.) are all wired into `StratagemManager` per `AUDIT_REPORT.md` 2026-05. Cross-check with `04_04_stratagems.md` and `04_05_enhancements_detachments.md` for ✅/⚠️ on the 4 enhancements. |
| Orks × War Horde | ✅ `Get Stuck In` (`FactionAbilityManager.gd:65-71`, `918-955`) — passive Sustained Hits 1 on melee | 6 | 4 | **Launchable.** Plus faction-level `Waaagh!` (`FactionAbilityManager.gd:156+`) including `Plant the Waaagh! Banner` (`FactionAbilityManager.gd:602-700`). |
| Space Marines × Gladius Task Force | ✅ `Combat Doctrines` (`FactionAbilityManager.gd:42-64`, `787-916`) — turn-of-doctrine selector (Devastator/Tactical/Assault) | 6 | 4 | **Launchable** but only 3 datasheet names exist in any SM roster (`Intercessor Squad`, `Tactical Squad`, `Infiltrator Squad`) so the breadth is anaemic — see Section 4. Faction ability `Oath of Moment` is implemented (`FactionAbilityManager.gd:137-144`, `293-365`). |
| Orks × Freebooter Krew | ✅ `Here Be Loot` defined (`FactionAbilityManager.gd:72-78`) plus 4 enhancements catalogued (`FACTION_ABILITY_MANAGER:106-132`) | 6 | 4 (`FACTION_ABILITY_MANAGER:106-132`) | **Code present, no roster JSON to exercise it.** No `40k/armies/*.json` declares `"detachment": "Freebooter Krew"`. C/W: `C` only — never wired into a real game flow. ⚠️ invisible-feature (see Section 6). |

For all other 257 detachments (203 non-Boarding − 4 = 199 plus 58 Boarding-Actions): the detachment army-rule has no entry in `FactionAbilityManager.DETACHMENT_ABILITIES`. `ArmyListManager.validate_army_construction_points` (`ArmyListManager.gd:1210-1244`) emits a non-blocking warning when a roster declares such a detachment ("Detachment '%s' is not recognized — detachment abilities will not activate") but loads the army anyway. The result is that any custom roster JSON declaring e.g. `"detachment": "Lions of the Emperor"` will load and play, but the detachment ability simply doesn't fire.

### Lions of the Emperor — explicit gap

`Detachment_abilities.csv:000009986` declares `Against All Odds` for detachment `Lions of the Emperor`. `Adeptus_Custodes_1995_Mar_7.json` (`40k/armies/`) hardcodes `"detachment": "Lions of the Emperor"` and is built around this rule. Verified absent from code:

```
$ grep -rn "Lions of the Emperor\|Against All Odds" 40k/autoloads/ 40k/scripts/ 40k/phases/
(no results)
```

Confirms `LIONS_ARMY_AUDIT.md:46-60` finding that `Against All Odds` is a no-op in code today. C/W/U/L: ❌.

---

## 3. Per-datasheet spot check (20 datasheets across the 3 playable factions)

Matrix below: for each unit picked from active rosters, the columns are
- **Stat** = comparison of `(M, T, Sv, W, Ld, OC, inv, base)` between roster JSON `meta.stats` and `Datasheets_models.csv` row for that datasheet
- **Wpn** = weapon list (`name`, `range`, `A`, `BS/WS`, `S`, `AP`, `D`) compared against `Datasheets_wargear.csv`
- **Abil** = abilities listed compared against `Datasheets_abilities.csv` (named only — inline abilities require deeper diffing not done here)
- **Kw** = keywords compared against `Datasheets_keywords.csv` (model-level rows treated as unit-level here)
- **Cost** = points compared against `Datasheets_models_cost.csv`

Symbols: ✅ matches; ⚠️ matches with minor drift; 🐛 diverges; ❌ absent. `file:line` evidence cited per row.

| # | Faction | Datasheet | Roster JSON entry | Stat | Wpn | Abil | Kw | Cost | Notes |
|---:|---|---|---|:---:|:---:|:---:|:---:|:---:|---|
| 1 | AC | Custodian Guard (`Datasheets.csv:000000882`) | `adeptus_custodes.json` U_CUSTODIAN_GUARD_B; `Adeptus_Custodes_1995_Mar_7.json` U_CUSTODIAN_GUARD_A..E | ✅ | ✅ for the 5 weapons listed (Guardian spear ranged/melee, Sentinel blade ranged/melee, Misericordia melee). | ⚠️ `adeptus_custodes.json` lists 6 named (Deep Strike, Martial Ka'tah, Praesidium Shield, Vexilla, Stand Vigil, Sentinel Storm). CSV inline rows show 2 `Core` rows (likely Deep Strike + 1 more) plus the named four. Minor noise but no false positives. | ✅ ADEPTUS CUSTODES, BATTLELINE, CUSTODIAN GUARD, IMPERIUM, INFANTRY all match `Datasheets_keywords.csv`. | 🐛 `adeptus_custodes.json` lists 170 pts for U_CUSTODIAN_GUARD_B (4 models). Canonical `Datasheets_models_cost.csv:000000882`: 4 models = 160 pts, 5 models = 200 pts. The roster's **170 is invalid** — neither composition matches. Variant `Adeptus_Custodes_1995_Mar_7.json` lists `190` and `150`, also invalid. Munitorum Field Manual v4.2 (per `Source.csv` 22.04.2026) is the source-of-truth. |
| 2 | AC | Shield-captain (`Datasheets.csv:000001447`) | `adeptus_custodes.json` U_SHIELD_CAPTAIN_A | ✅ | ⚠️ Roster lists Sentinel blade ranged + melee only. CSV has 4 ranged options (Castellan axe, Guardian spear, Pyrithite spear, Sentinel blade) and 4 melee. The roster has chosen one wargear option, which is legal — flag only because there's no captured "wargear option" record in the JSON to confirm intentional. | ⚠️ Roster: Deep Strike, Martial Ka'tah, Master of the Stances, Strategic Mastery, Praesidium Shield. Canonical adds 2 `Core` rows (likely Deep Strike + Leader). The presence of `Praesidium Shield` (a Wargear ability) implies the Shield wargear was chosen — legal. | ✅ all 5 keywords match. | ✅ 120 pts matches. |
| 3 | AC | Blade Champion (`Datasheets.csv:000002518`) | `adeptus_custodes.json` U_BLADE_CHAMPION_A; `Adeptus_Custodes_1995_Mar_7.json` U_BLADE_CHAMPION_A/B | ✅ stats match (M6, T6, Sv2+, W6, Ld6+, OC2, inv4). | ✅ all three Vaultswords (Behemor / Hurricanus / Victus) match canonical. | ✅ Deep Strike, Martial Ka'tah, Swift Onslaught, Martial Inspiration. | ✅ all match. | 🐛 `adeptus_custodes.json` lists 145 pts; canonical (`Datasheets_models_cost.csv:000002518`) = 120 pts. `Adeptus_Custodes_1995_Mar_7.json` = 120 (correct). |
| 4 | AC | Witchseekers (`Datasheets.csv:000002523`) | `adeptus_custodes.json` U_WITCHSEEKERS_C/D; `Adeptus_Custodes_1995_Mar_7.json` U_WITCHSEEKERS_A/B | ✅ M6, T3, Sv3+, W1, Ld6+, OC1; **inv = "-" (none) per CSV — both rosters omit the field**, ✅. | ✅ Witchseeker flamer (Pistol/Torrent in description), Close combat weapon. Special-rule keywords on weapon (TORRENT/IGNORES COVER) are stored in CSV `description` field but **the roster JSON does not propagate them**. ⚠️ Tactical impact: any IGNORES COVER on the canonical flamer is unenforceable from JSON-only data. | ⚠️ Roster lists Scouts 6"/Scouts (mismatched between files), Daughters of the Abyss, Sanctified Flames. Canonical has Scouts (no value), Daughters of the Abyss, Sanctified Flames. ⚠️ "Scouts 6\"" is a Scout 6" Core ability name — naming inconsistency in active rosters: `adeptus_custodes.json` uses `Scouts 6"`; `Adeptus_Custodes_1995_Mar_7.json` uses `Scouts`. | ✅ ADEPTUS CUSTODES, ANATHEMA PSYKANA, IMPERIUM, INFANTRY, WITCHSEEKERS. | 🐛 `adeptus_custodes.json` lists 50 pts (U_WITCHSEEKERS_C, 4 models) and 65 pts (U_WITCHSEEKERS_D); canonical = 45 / 55 / 90 / 100 pts for 4 / 5 / 9 / 10 models. **65 is not a valid Witchseekers point cost.** `Adeptus_Custodes_1995_Mar_7.json` lists 45 pts (4 models) — correct. |
| 5 | AC | Caladius Grav-tank (`Datasheets.csv:000001460`) | `adeptus_custodes.json` U_CALADIUS_GRAV-TANK_E | 🐛 Roster: T11. Canonical: T11 ✅. Inv missing in roster stats — canonical has `inv_sv=5`. **🐛 missing 5+ invuln save** (Caladius has 5+ invuln per Wahapedia 10e). | ✅ Twin arachnus heavy blaze cannon, Twin iliastus accelerator cannon, Twin lastrum bolt cannon, Armoured hull all match canonical stats. | ✅ Deadly Demise D3, Martial Ka'tah, Advanced Firepower, Damaged: 1-5 Wounds Remaining (canonical also has Damaged ability for `1-5` wounds). | ✅ ADEPTUS CUSTODES, FLY, VEHICLE, CALADIUS GRAV-TANK, IMPERIUM. | ✅ 215 pts matches. |
| 6 | AC | Telemon Heavy Dreadnought (`Datasheets.csv:000001479`) | `adeptus_custodes.json` U_TELEMON_HEAVY_DREADNOUGHT_I | 🐛 Roster: M=8, T=12, Sv2, W12, Ld6+, OC5. Canonical: M=8, T=10, Sv2+, W12, Ld6+, OC4, inv=4. **Roster has T=12 (canonical 10), OC=5 (canonical 4), no invuln (canonical 4+).** Three stat divergences. | 🐛 Roster weapons include `Telemon Caestus, Spiculus bolt launcher, Iliastus accelerator culverin, Telemon Caestus, Telemon Storm Cannon, Twin arachnus las-blaze`. Canonical has: Arachnus storm cannon, Iliastus accelerator culverin (note 2x in equipped), Spiculus bolt launcher, Twin plasma projector, Armoured feet, Telemon caestus. Roster invents `Telemon Storm Cannon` and `Twin arachnus las-blaze` (likely an old name); also lists `Telemon Caestus` twice. ⚠️ Several weapon names diverge from current Wahapedia data. | ⚠️ Roster: Deadly Demise D3, Martial Ka'tah, Guardian Eternal, Damaged 1-4. Canonical: Deadly Demise (the dice value comes from the inline core-ability description), Martial Ka'tah, Guardian Eternal, Devoted to Destruction. **Roster missing `Devoted to Destruction`.** | ✅ keywords match. | 🐛 Roster: 265 pts. Canonical: 225 pts. **+40 pts overspent in the roster — wrong by 18%.** |
| 7 | AC | Contemptor-Achillus Dreadnought (`Datasheets.csv:000001458`) | `adeptus_custodes.json` U_CONTEMPTOR-ACHILLUS_DREADNOUGHT_H | ✅ M6, T9, Sv2+, W10, Ld6+, OC3. **🐛 missing inv 5+ in roster stats**. | ⚠️ Roster: Achillus dreadspear, Infernus incinerator, Twin adrathic destructor, Achillus dreadspear (melee). Canonical adds: Lastrum storm bolter (the standard equipped weapon per Datasheets.csv loadout). **Roster missing Lastrum storm bolter.** | ⚠️ Roster: Deadly Demise 1, Martial Ka'tah, Dread Foe. Canonical adds inline core abilities (Damaged + Deadly Demise inline). | ✅ keywords match. | 🐛 Roster: 155 pts (correct? canonical = 155). ✅ matches. |
| 8 | ORK | Boyz (`Datasheets.csv:000000016`) | `orks.json` U_BOYZ_E/F/K | 🐛 Roster has 1 model line (Boyz). Canonical has 2 model lines: BOY (W1) and BOSS NOB (W2). Roster collapses both into one stat row, losing the BOSS NOB W2 distinction. **🐛** | ⚠️ Roster lists 9 weapons. Canonical 9 weapons match by name. ✅ stats per weapon are identical. | ⚠️ Roster: Waaagh!, Get Da Good Bitz, BODYGUARD (special). Canonical: 1 Core, 1 Faction (Waaagh!), Get Da Good Bitz Datasheet. The "BODYGUARD" entry in roster is a `Special (правая колонка)` — Cyrillic comment indicates a stale fixture from data scraping; it's not a Wahapedia ability row. | ✅ ORKS, BATTLELINE, BOYZ, GRENADES, INFANTRY, MOB. | ✅ 80 pts (10 models). Canonical = 80 / 170. ✅. |
| 9 | ORK | Warboss (`Datasheets.csv:000000001`) | `orks.json` U_WARBOSS_B/C | ✅ M6, T5, Sv4+, W6, Ld6+, OC1. **🐛 missing inv 5+ in roster stats** (Warboss has 5+ invuln from 'Ard As Nails per Wahapedia). | ⚠️ Roster: Kombi-weapon, Twin slugga, Attack squig, Big choppa, Power klaw. Canonical also has all of these — but roster has only chosen one combo of options. Legal. | ✅ Core, Waaagh!, Might is Right, Da Biggest and da Best — all four match canonical. | ✅ ORKS, CHARACTER, INFANTRY, WARBOSS, GRENADES. | ✅ 75 pts matches. |
| 10 | ORK | Beastboss (`Datasheets.csv:000002489`) | `Orks_2000.json` U_BEASTBOSS_A | ✅ M6, T5, Sv4+, W6, Ld6+, OC1, inv=5. ✅ all match. | ✅ Shoota, Beast Snagga klaw, Beastchoppa match canonical. | ✅ Feel No Pain, Leader, Waaagh!, Beastboss, Beastly Rage. | ✅ ORKS, INFANTRY, CHARACTER, BEAST SNAGGA, BEASTBOSS, WARBOSS. | ✅ 80 pts matches. |
| 11 | ORK | Battlewagon (`Datasheets.csv:000000039`) | `orks.json` U_BATTLEWAGON_G | ✅ M10, T10, Sv3+, W16, Ld7+, OC5; canonical also has inv=6 — **🐛 missing inv 6+ in roster stats**. | ✅ All 10 weapons listed match canonical. | ⚠️ Roster: Deadly Demise D6, FIRING DECK, Waaagh!, Ramshackle, Damaged 1-5, 'Ard Case (wargear), TRANSPORT (Special). Canonical equivalents are present; the FIRING DECK and TRANSPORT entries are uppercase placeholders rather than real ability names. | ✅ ORKS, VEHICLE, TRANSPORT, BATTLEWAGON. | ✅ 160 pts matches. |
| 12 | ORK | Lootas (`Datasheets.csv:000000044`) | `orks.json` U_LOOTAS_A; `Orks_2000.json/Orks_2000_upload.json/Orks_Upload_Mar7.json` U_LOOTAS_A/B/C | ✅ M6, T5, Sv5+, W1, Ld7+, OC1; no invuln per canonical ✅. | ⚠️ Roster: Deffgun, Kustom mega-blasta, Close combat weapon. Canonical also has Big shoota and Rokkit launcha (Spanner options). The roster has chosen a weapon loadout — legal. | ✅ Waaagh!, Dat's Our Loot!. | ✅ ORKS, LOOTAS, INFANTRY. | ✅ 100 pts (the 2 Spanners + 8 Lootas option, canonical = 100 pts) ✅. The 1+4 option (50 pts) is not used in the roster. |
| 13 | ORK | Kommandos (`Datasheets.csv:000000025`) | `orks.json` U_KOMMANDOS_H; `Orks_2000.json/...` U_KOMMANDOS_A | ✅ M6, T5, Sv5+, W1, Ld7+, OC1. ✅. | ⚠️ Different rosters list different weapon subsets — both legal. | ✅ Infiltrators, Stealth, Scout 6", Waaagh!, Throat Slittas, Sneaky Surprise, Patrol Squad, Distraction Grot (wargear), Bomb Squigs (wargear). Canonical matches. | ✅ ORKS, INFANTRY, GRENADES, SMOKE, KOMMANDOS. | 🐛 `orks.json` lists 135 pts; `Orks_2000.json` lists 120 pts. Canonical (10 models) = 120 pts. **`orks.json:135` is +15 over canonical**. |
| 14 | ORK | Stormboyz (`Datasheets.csv:000000027`) | `Orks_2000.json/upload/Mar7.json` U_STORMBOYZ_A | ✅ M12, T5, Sv5+, W1, Ld7+, OC1. | ✅ Slugga, Choppa. Canonical also lists Power klaw — roster doesn't use it (legal — wargear option). | ✅ Deep Strike, Waaagh!, Full Throttle. | ✅ ORKS, STORMBOYZ, GRENADES, FLY, JUMP PACK, INFANTRY. | ✅ 130 pts (10 models) matches canonical. |
| 15 | ORK | Meganobz (`Datasheets.csv:000000024`) | `orks.json` U_MEGANOBZ_L | ✅ M5, T6, Sv2+, W3, Ld7+, OC1. ✅. | ⚠️ Roster: Kustom shoota, Power klaw, Killsaws (note: canonical has separate `Killsaw` and `Twin killsaw`). | ✅ Waaagh!, Krumpin' Time. | ✅ ORKS, MEGA ARMOUR, INFANTRY, MEGANOBZ, GRENADES. | 🐛 Roster: 160 pts. Canonical 5-model = 160 pts ✅, but roster spec says 5 models so this is correct ✅. |
| 16 | ORK | Ghazghkull Thraka (`Datasheets.csv:000000008`) | `orks.json` U_GHAZGHKULL_THRAKA_A | 🐛 Roster: M6, T9, Sv2+, W12, Ld6+, OC2. Canonical has 2 model rows: GHAZGHKULL (M5, T6, Sv2+, W10, Ld6+, OC4, inv4, 80mm) + MAKARI (M5, T6, Sv7+, W1, Ld8+, OC1, inv2, 25mm). **Roster's stats are wrong on every line: M=6 vs 5, T=9 vs 6, W=12 vs 10, OC=2 vs 4, no MAKARI line, no invuln.** This is the unit's per-model stats divergence cited in Stage 1 inventory's "data unloaded" caveat. | 🐛 Roster: Gork's Klaw, Mork's Roar, Makari's Stabba (3 weapons). Canonical: Mork's Roar (ranged), Gork's Klaw - strike (melee), Gork's Klaw - sweep (melee), Makari's stabba (melee) — 4 weapon profiles. **Roster missing the strike/sweep split for Gork's Klaw.** | ⚠️ Roster: Core, Waaagh!, Prophet of Da Great Waaagh!, Ghazghkull's Waaagh! Banner (Aura). Canonical adds inline `Damaged: 1-5 Wounds Remaining` Datasheet ability. | ⚠️ Roster: ORKS, MONSTER, CHARACTER, EPIC HERO, WARBOSS, GHAZGHKULL THRAKA. Canonical (model-level): just `Orks` for unit-level, with model-specific keywords. Acceptable consolidation. | 🐛 Roster: 300 pts. Canonical (1 GHAZGHKULL + 1 MAKARI) = 235 pts. **+65 pts wrong**. |
| 17 | ORK | Wazbom Blastajet (`Datasheets.csv:000000032`) | `orks.json` U_WAZBOM_BLASTAJET | 🐛 Roster: M=20, T=9, Sv3+, W12, Ld7+, OC0, inv6. Canonical: `M=20+"`, T=9, Sv3+, W12, Ld7+, OC0, inv6 ✅. ✅ matches (Move "20+" parsed as 20). | ⚠️ Roster: Smasha gun, Twin wazbom mega-kannon, Armoured hull. Canonical adds Twin supa-shoota, Twin tellyport mega-blasta. **Roster missing 2 of 4 ranged options** (legal as wargear choice). | ✅ Deadly Demise, Waaagh!, Blastajet Attack Run. | ✅ WAZBOM BLASTAJET, ORKS, GRENADES, AIRCRAFT, VEHICLE, SPEED FREEKS, FLY. | ✅ 175 pts matches. |
| 18 | ORK | Kaptin Badrukk (`Datasheets.csv:000000009`) | `orks.json` U_KAPTIN_BADRUKK_A | ✅ M6, T5, Sv4+, W6, Ld6+, OC1, inv4. | ⚠️ Roster: Da Rippa, Kustom mega-blasta, Power klaw. Canonical: Da Rippa (standard + supercharge variants), Slugga, Choppa. Roster invents `Kustom mega-blasta` and `Power klaw` not on canonical Datasheet for Badrukk! 🐛 | ✅ Core, Waaagh!, Flashiest Gitz, Ded Glowy Ammo (Aura), Leader. | ✅ ORKS, EPIC HERO, CHARACTER, INFANTRY, KAPTIN BADRUKK. | 🐛 Roster: 100 pts. Canonical: 80 pts. **+20 pts wrong**. |
| 19 | SM | Intercessor Squad (`Datasheets.csv:000001157`) | `space_marines.json` U_INTERCESSORS_A | ✅ M6, T4, Sv3+, W2, Ld6+, OC2. No invuln canonical ✅. | ⚠️ Roster: Bolt rifle, Bolt pistol, Close combat weapon, Power fist. Canonical has 7 ranged + 5 melee; roster picked a small subset (legal). | ⚠️ Roster: Oath of Moment, Objective Secured, Target Elimination. Canonical Intercessors don't have `Objective Secured` as a Datasheet row — this looks like a 9e carryover (Objective Secured was a Codex Marines bonus pre-10e). 🐛 9e CARRYOVER candidate. **`Target Elimination`** (`UnitAbilityManager.gd` defines it) is on the canonical Wahapedia datasheet (Squad Leader Intercessor Sergeant ability). ✅. | ⚠️ Roster: INFANTRY, PRIMARIS, IMPERIUM, ADEPTUS ASTARTES. Canonical: Adeptus Astartes, Intercessor Squad, Tacticus, Imperium, Grenades, Battleline, Infantry. **Roster missing TACTICUS, GRENADES, BATTLELINE, INTERCESSOR SQUAD** keywords. 🐛 | 🐛 Roster: 100 pts (5 models). Canonical: 80 pts (5) / 160 pts (10). **+20 pts off**. |
| 20 | SM | Tactical Squad (`Datasheets.csv:000000070`) | `space_marines.json` U_TACTICAL_A | ✅ M6, T4, Sv3+, W2, Ld6+, OC2. | ⚠️ Roster: Boltgun, Bolt pistol, Close combat weapon. Canonical has 26 weapon profiles (extensive options); roster covers only the basic loadout. Legal. | ⚠️ Roster: Oath of Moment, Combat Squads. Canonical: Faction (Oath of Moment), Combat Squads Datasheet. ✅. | 🐛 Roster: INFANTRY, IMPERIUM, ADEPTUS ASTARTES. Canonical: Adeptus Astartes, Battleline, Grenades, Tactical Squad, Imperium, Infantry. **Roster missing BATTLELINE, GRENADES, TACTICAL SQUAD**. | 🐛 Roster: 90 pts (10 models). Canonical: 140 pts (10 models). **−50 pts under-priced — significantly cheaper than legal**. |
| 21 | SM | Infiltrator Squad (`Datasheets.csv:000000128`) | `space_marines.json` U_INFILTRATORS_A | ✅ M6, T4, Sv3+, W2, Ld6+, OC1. | ✅ Bolt pistol, Marksman bolt carbine, Close combat weapon match canonical. | ⚠️ Roster: Infiltrators, Scout 6", Oath of Moment, Omni-scramblers, Scout 6" (twice). Canonical: Infiltrators, Scout 6" (parameter "6\""), Omni-scramblers (datasheet ability per Wahapedia), Faction (Oath of Moment). Duplicate Scout 6" entry is a roster-side bug. ⚠️ | 🐛 Roster: INFANTRY, PRIMARIS, PHOBOS, IMPERIUM, ADEPTUS ASTARTES. Canonical: Adeptus Astartes, Infantry, Grenades, Smoke, Imperium, Infiltrator Squad, Phobos. **Roster missing GRENADES, SMOKE, INFILTRATOR SQUAD**. | 🐛 Roster: 100 pts (5 models). Canonical: 100 / 200 pts. ✅ matches at 5 models. |

That's 21 spot checks (one extra to cover both Witchseeker rosters). Summary:
- **Stat divergences (🐛 stat block):** 5 of 21 (Caladius missing inv, Telemon T/OC/inv, Contemptor-Achillus missing inv, Boyz collapsed BOSS NOB, Warboss missing inv, Battlewagon missing inv, Ghazghkull all-stats wrong + missing MAKARI). **The most pervasive divergence is missing invulnerable saves on stat blocks** (already flagged in `LIONS_ARMY_AUDIT.md:115` and `:151` and `:307`).
- **Weapon divergences (🐛 wargear):** 4 of 21 (Telemon invented weapons, Contemptor-Achillus missing storm bolter, Ghazghkull missing strike/sweep split, Kaptin Badrukk extra weapons not on canonical sheet).
- **Points divergences (🐛 cost):** **8 of 21 spot-checks** had **wrong points cost in at least one roster JSON**. Custodian Guard (170 vs 160), Blade Champion (145 vs 120), Witchseekers (50 vs 45 / 65 invalid), Telemon (265 vs 225), Kommandos `orks.json` (135 vs 120), Ghazghkull (300 vs 235), Kaptin Badrukk (100 vs 80), Intercessor (100 vs 80), Tactical (90 vs 140 — under-priced!). Total **net under/over by 8/21 = 38%** of spot-checked unit cards. **This is the breadth audit's biggest red flag**: the roster JSONs (which are what the engine uses) are systematically out of sync with the Munitorum Field Manual data the CSVs encode.
- **Keyword divergences (🐛 keywords):** SM rosters missing standard keywords (BATTLELINE, GRENADES, faction-specific keyword) on Intercessors / Tactical / Infiltrators. **This breaks any rule that keys off keywords** (e.g., GRENADES Strategic Reserves stratagem, BATTLELINE detachment-ability bonuses) for those units.

### 9e carryover sweep (per the prompt)

I found **one** roster-cited rule that appears to be a 9e carryover: **`Objective Secured`** as a Datasheet ability on Intercessor Squad in `space_marines.json` (`U_INTERCESSORS_A`). 10e Intercessors do not have an Objective Secured datasheet ability — Battleline OC count is determined by their OC characteristic and the standard objective rules (`MissionManager.gd:175`+ for 10e OC scoring). The 10e Intercessor datasheet (`Datasheets_abilities.csv` for ds_id `000001157`) lists `Target Elimination` and inline core abilities, no `Objective Secured`. Per `feedback_10e_rule_verification.md`, I'm flagging it **❓ ambiguous (single-source claim)** rather than a hard 🐛: confirm against the Wahapedia Intercessors page (`https://wahapedia.ru/wh40k10ed/factions/space-marines/Intercessor-Squad`) before treating as removable.

No other clear 9e carryovers in the spot-check sample (the abilities present in the rosters all map to current 10e datasheet abilities, including legacy-named ones like "Patrol Squad" and "PATROL SQUAD" which are present on the current Wahapedia Kommandos sheet).

---

## 4. Per-faction roster completeness (the 3 playable factions)

| Faction | Datasheets in catalog | Datasheets in any roster | Roster coverage % | Datasheets in roster but missing from catalog |
|---|---:|---:|---:|---|
| Adeptus Custodes | 31 | 16 distinct names | **52%** | 0 — every roster name maps to a `Datasheets.csv` entry |
| Orks | 87 | 27 distinct names | **31%** | 0 — every roster name maps to a `Datasheets.csv` entry (although some are stat-divergent per Section 3) |
| Space Marines | 298 | 3 distinct names | **1.0%** | 0 — but the SM roster is **so anaemic** (3 of 298 datasheets) that it cannot model any real Space Marine list. The `space_marines.json` file is 11.6 KB; the AC/Orks files are 30-120 KB. |

The 23 unplayable factions all have **0%** roster coverage.

### Estimate for adding each of the 23 unplayable factions

Each unplayable faction needs all of:
1. **Roster JSON files** for at least one detachment per faction (the user's army-builder UX is JSON-only — no in-app builder; see `MainMenu.gd:488` and `MultiplayerLobby.gd:756`). Format observed: `{"faction": {"name", "points", "detachment", ...}, "units": {"<U_id>": {...meta...}, ...}}` — see `40k/armies/orks.json` for a 71 KB / 17-unit example.
2. **`FactionAbilityManager.DETACHMENT_ABILITIES`** entry per detachment they want playable, plus the engine wiring (e.g., the `War Horde` `Get Stuck In` passive is wired into RulesEngine via `FactionAbilityManager._apply_get_stuck_in_effects`).
3. **`FactionAbilityManager.FACTION_ABILITIES`** entry for the faction-level army-rule (e.g., `Oath of Moment`, `Waaagh!`, `Martial Ka'tah`).
4. **`StratagemManager`** wiring for that detachment's 6 stratagems (catalog lives in `Stratagems.csv`; loader is `FactionStratagemLoader.load_faction_stratagems` `40k/autoloads/FactionStratagemLoader.gd:127-163`, but the loader only emits structured rows — the **effects** are wired in `StratagemManager.gd` per stratagem).
5. **Per-datasheet ability handlers** in `UnitAbilityManager.ABILITY_EFFECTS` for any new units' named abilities (currently 106 distinct abilities defined).
6. **Per-detachment enhancement handlers** for that detachment's 4 enhancements (Custodes / Orks / SM Gladius all have these wired today; cross-reference `04_05_enhancements_detachments.md`).

**Per-faction effort estimate** (assumes 1 detachment per faction is enough to flag "launchable"):

| Component | Effort per faction (1 detachment) | Notes |
|---|---:|---|
| Author roster JSON (~10–20 datasheets, full stat+weapon+ability+keyword data) | **2–3 days** | Manual curation against `Datasheets_*.csv` since the Wahapedia data is **not loaded** by the engine. |
| `FactionAbilityManager` faction-rule + detachment-rule code | **2–4 days** | Proportional to rule complexity. Custodes Martial Mastery is ~120 lines; Orks Waaagh! is ~250 lines (`FactionAbilityManager.gd:368-555`); a complex rule like Necrons Reanimation Protocols is multi-week. |
| `StratagemManager` wiring for 6 detachment stratagems + 28 core stratagems already exist | **3–5 days** | Each stratagem averages ~40–80 lines including effect wiring. |
| 4 enhancement handlers | **1–2 days** | Most enhancements are passive stat overlays. |
| Per-unit datasheet abilities (avg ~3 named abilities per datasheet × ~10 unique datasheets per starter roster = ~30 ability handlers) | **3–5 days** | Most fall into stock effect types (`reroll_hits`, `grant_fnp`, `crit_hit_on`, `plus_one_wound`, `grant_invuln`, etc., per `UnitAbilityManager.ABILITY_EFFECTS`). Novel mechanic abilities (e.g. Tyranids Synapse) are weeks. |
| Live validation through deploy → 1 full battle round | **1 day** | Required by CLAUDE.md "Feature validation rule". |
| **Per-faction total (1 detachment, baseline)** | **~12–20 days** | Heavier for factions with novel mechanics (Tyranids Synapse, Necrons Reanimation, Drukhari Power From Pain, Aeldari Strands of Fate, Adeptus Mechanicus Doctrina Imperatives, T'au For the Greater Good, Imperial Knights single-model armies). |

For **all 23 factions × 1 detachment each** at the baseline rate: **~280–460 person-days**. If each faction needs 2–3 detachments to be a real product, multiply by ~2x. **Headline estimate: 1.5–3 person-years to make the launchability number go from 3/26 to 26/26.**

This excludes the **invisible-feature fixup** and **points-data drift** (Section 3) which need ~1 week to clean across the existing 3 factions before adding more.

---

## 5. Top-3 launch-blocker gaps

1. **23 of 26 factions have no roster JSON and no UI to construct one** (`40k/armies/` listing). `MainMenu.gd:488-516` and `MultiplayerLobby.gd:756-815` only list pre-existing JSON filenames; selecting a faction not on disk is not possible. Estimated work: ~280–460 person-days as detailed in §4.
2. **258 of 261 detachments have no engine handler for their detachment ability.** `FactionAbilityManager.DETACHMENT_ABILITIES` (`40k/autoloads/FactionAbilityManager.gd:41-97`) defines only `Gladius Task Force`, `War Horde`, `Freebooter Krew`, `Shield Host`. Loading any other detachment emits a non-blocking warning (`ArmyListManager.gd:1240`) but the rule never fires — silent rules failure. **The most impactful single example is `Lions of the Emperor / Against All Odds`** (`Detachment_abilities.csv:000009986`), which gates the entire `Adeptus_Custodes_1995_Mar_7.json` 1995-pt army's combat math (`LIONS_ARMY_AUDIT.md:46-60`).
3. **Roster JSONs are ~38% out-of-sync with canonical Munitorum Field Manual points and Wahapedia stats** (Section 3 spot-check). The engine doesn't load Datasheets/Wargear/Models/Cost CSVs (`01_inventory.md:91-105`), so the curated roster JSONs are the single source of truth for unit play and they have drifted. Specific divergence examples: Telemon at 265 pts vs canonical 225 (`adeptus_custodes.json`), Tactical Squad at 90 pts vs canonical 140 (`space_marines.json` — under-priced by 36%), Ghazghkull missing the MAKARI model line (`orks.json`), every Custodian Guard / Blade Champion roster JSON missing the invulnerable save field, Intercessors / Tactical / Infiltrator squads all missing standard keywords (BATTLELINE, GRENADES, faction-specific keyword).

## 6. Top-3 invisible features

1. **`Freebooter Krew` detachment** (`FactionAbilityManager.gd:72-78`) — full code path defined including `Here Be Loot` plus 4 enhancements `Da Kaptin / Git-spotter Squig / Bionik Workshop / Razgit's Magik Map` (`FactionAbilityManager.gd:106-132`), but **no Ork roster JSON declares `"detachment": "Freebooter Krew"`**, so the entire Freebooter Krew code path is **C** (code present) but unreachable from the faction selector. Players cannot pick it.
2. **Detachment selection itself is not a UI affordance.** A roster JSON's `faction.detachment` is hardcoded at JSON-author time. There is no dropdown, no setting, no override path that lets a player pick `Lions of the Emperor` vs `Shield Host` at runtime. `MainMenu.gd` and `MultiplayerLobby.gd` only let you pick the JSON file. **The Custodes faction has 8 catalog detachments; the engine only renders effects for 1.** From a player's perspective the other 7 (`Talons Of The Emperor`, `Null Maiden Vigil`, `Auric Champions`, `Voyagers in Darkness`, `Black Ship Guardians`, `Solar Spearhead`, `Lions of the Emperor`) are invisible.
3. **`adeptus_custodes_roster_stubs.json`** (`40k/armies/adeptus_custodes_roster_stubs.json`) is in the army dropdown (verified live: `get_available_armies()` includes it) but every unit is `_STUB`-suffixed and has `"_status": "stub-pending-review"`. It will load and present a non-functional army; failure mode is that the unit shells exist but never deploy correctly (the file's own `_README` calls them "stubs").

---

## 7. Per-detachment launchability map (sorted by completeness)

| Faction × Detachment | Rule wired | Stratagems | Enhancements | Roster JSON exists? | Verdict |
|---|:---:|:---:|:---:|:---:|---|
| Adeptus Custodes × Shield Host | ✅ Martial Mastery | 6 (per AUDIT_REPORT 2026-05) | 4 | ✅ `adeptus_custodes.json`, `A_C_test.json` | **Launchable** |
| Orks × War Horde | ✅ Get Stuck In | 6 | 4 | ✅ `orks.json`, `ORK_test.json` | **Launchable** |
| Space Marines × Gladius Task Force | ✅ Combat Doctrines | 6 | 4 | ✅ `space_marines.json` (only 3 datasheets) | **Launchable but anaemic roster (3 of 298 SM datasheets)** |
| Orks × Freebooter Krew | ✅ Here Be Loot (code-only) | 6 (would load via FactionStratagemLoader) | 4 (defined in code) | ❌ no roster JSON | Code complete, no roster — invisible feature |
| Adeptus Custodes × Lions of the Emperor | ❌ Against All Odds | 6 (CSV only) | 4 (CSV only) | ✅ `Adeptus_Custodes_1995_Mar_7.json` | **NOT launchable — flagship roster, rule absent** |
| 257 other (faction × detachment) combos | ❌ | (loaded from CSV but stratagems may not have `StratagemManager` effects wired) | (loaded from CSV) | ❌ | **NOT launchable** |

---

## 8. Cross-references to other findings

- `04_04_stratagems.md` (separate audit) holds the per-stratagem implementation depth. This audit assumes the 3+1 detachments that have a wired army-rule also have their 6 stratagems wired (per `AUDIT_REPORT.md` 2026-05 spot checks for Custodes Defensive Stance, Stoic Fortitude; Ork Insane Bravery, Da Boyz Iz Gettin' Stuck In; SM Adaptive Strategy, Storm of Fire). For the 257 unwired detachments, every stratagem in `Stratagems.csv` for that detachment is `C/W/U/L = ❌` because there is no detachment context to apply them.
- `04_05_enhancements_detachments.md` holds the per-enhancement implementation depth.
- `LIONS_ARMY_AUDIT.md` (existing 2026-03-07 audit) covers the Lions of the Emperor gap in detail; this audit confirms its findings still hold as of 2026-05-06.
- `40k/test_results/audit_2026_05/AUDIT_REPORT.md` (2026-05 audit, closed) verified Custodes Martial Mastery + Ka'tah, Orks War Horde + Waaagh! + Plant Banner, weapon keywords (Twin-linked, Sustained Hits, Blast, Hazardous), and core movement/charge/fight machinery to spec. This audit does not refile those.

---

## 9. File:line evidence index

- **Faction code map:** `40k/data/Factions.csv:1-27` (26 factions; 27th line is the header).
- **Detachment data:** `40k/data/Detachments.csv:1-261`.
- **Detachment-ability data:** `40k/data/Detachment_abilities.csv:1-284`.
- **Roster files:** `/Users/robertocallaghan/Documents/claude/godotv2/40k/armies/` — 10 JSON files, 3 distinct factions, 4 distinct detachment values (`Shield Host`, `War Horde`, `Strike Force`, `Lions of the Emperor`, `Gladius Task Force`).
- **Army loader / detachment validator:** `40k/autoloads/ArmyListManager.gd:1210-1244` — non-blocking warning when detachment is unrecognised; the engine still loads the army.
- **Detachment-ability dictionary:** `40k/autoloads/FactionAbilityManager.gd:41-97` — exactly 4 keys.
- **Faction-ability dictionary:** `40k/autoloads/FactionAbilityManager.gd:136-172` — exactly 3 keys (Oath of Moment, Martial Ka'tah, Waaagh!).
- **Combat Doctrines (Gladius):** `40k/autoloads/FactionAbilityManager.gd:787-916`.
- **Get Stuck In (War Horde):** `40k/autoloads/FactionAbilityManager.gd:918-955`.
- **Martial Mastery (Shield Host):** `40k/autoloads/FactionAbilityManager.gd:957-1085`.
- **Waaagh! and Plant the Waaagh! Banner:** `40k/autoloads/FactionAbilityManager.gd:368-700`.
- **Oath of Moment:** `40k/autoloads/FactionAbilityManager.gd:293-365`.
- **`UnitAbilityManager.ABILITY_EFFECTS` (106 distinct abilities):** `40k/autoloads/UnitAbilityManager.gd:57-...`.
- **`FactionStratagemLoader` reads `Factions.csv`, `Stratagems.csv`, `Detachments.csv`:** `40k/autoloads/FactionStratagemLoader.gd:69-104, 127-163`.
- **MainMenu army selection (no faction picker, no detachment picker):** `40k/scripts/MainMenu.gd:488-559`.
- **MultiplayerLobby army selection (same shape):** `40k/scripts/MultiplayerLobby.gd:756-880`.
- **Live MCP evidence:** `ping → ok` at start of audit; `ArmyListManager.get_available_armies()` returns the 10 expected names; `FactionAbilityManager.DETACHMENT_ABILITIES.keys()` returns 4; `load_army_list("aeldari", 1)` returns `{}`. Screenshot saved at `user://test_screenshots/factions_audit_running_state.png`.
