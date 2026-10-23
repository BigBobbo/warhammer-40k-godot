# Codex: Space Marines (11e) — generic datasheets, detachments, army rules — plan

Status: ACTIVE (2026-10-23). Owner ask: "update all of the generic Space Marine
datasheets, strats and abilities similar to how you did with the Space Wolves".
Follows PLAN_SPACE_WOLVES.md (shipped) and the contract IMPLEMENTATION.md —
read both; this file lists only what differs.

## Rules source
- `space-marines/SPACE_MARINES_GENERIC.md` — every rule in scope, printed text:
  army rules, the 15 generic detachments (rule, enhancements, stratagems) and
  the abilities / wargear options of the 87 generic datasheets.
- `space-marines/RULES.md`, `space-marines/wahapedia/*.csv` — the full export.
- Stratagem rows: `scripts/40kdc/curated/space_marines_codex_11e.json` (48
  stratagems, `custom:sm11e`, windows INFERRED — confirm or fix).

## Scope decisions
| # | Decision |
|---|---|
| SM-D1 | The codex rules apply to every Space Marine army: faction Space Marines / Adeptus Astartes or any chapter (`SWCommon.is_sm_army(player)`). Space Wolves specifics keep `is_sw_army`. |
| SM-D2 | Datasheets in scope: the 87 of source "Space Marines" + "Space Marines (Forge World)" (incl. named characters printed there: Roboute Guilliman, Marneus Calgar, Kor'sarro Khan, ...). Other chapters' own datasheets (Blood Angels, Dark Angels, Black Templars, Deathwatch) stay on 40kdc records — out of scope. |
| SM-D3 | Detachments in scope: the 15 generic ones. Chapter-only detachments (other than Space Wolves, already shipped) and Boarding Actions: out of scope. |
| SM-D4 | Oath of Moment is gone for every Space Marine army (data + FactionAbilityManager guard, WP-M1). |

## Shipped: WP-M1 data (commit fe653cf + follow-up)
- Import: 108 datasheets (87 generic + 21 SW), 15 generic detachments under
  `adeptus-astartes` (index ones + 168 chapter copies superseded).
- Stratagems.csv: 48 `SM|` rows (`custom:sm11e`). A chapter army taking a
  generic detachment gets the SM rows (FactionStratagemLoader fallback).
- `armies/sm11e_codex_test.json` (all 87 datasheets, faction Space Marines,
  Gladius Task Force + Assault Brethren), `tests/test_sm11e_codex_data.gd`.
- `SWCommon.is_sm_army(player)`; `has_combat_doctrines` now true for every
  Space Marine army's units with the ability (doctrine STATE works for all;
  the selection UI / effects still gate on is_sw_army in SWArmyRules11e — M2a
  generalises them).

## Packages (parallel)
| WP | Scope | Owns (new files under `40k/scripts/codex/space_marines/`) |
|---|---|---|
| **M2a** | Army rules for every SM army: generalise Combat Doctrines (selection UI, effects, AI), Transhuman Strategist, Librarius (psyker budget for SM PSYKER units), Special Move Types if any datasheet/rule uses them; delete the 10e Gladius doctrine path for 11e. Detachment rules + enhancements of **Gladius Task Force (Codex Discipline), Ironstorm Spearhead, Stormlance Task Force, Gauntlet Task Force, Phobos Shadow Force, Tacticus Attack Force, Phobos Shock Force** | `SMArmyRules11e.gd` (or generalise `space_wolves/SWArmyRules11e.gd` in place), `SMDetachmentsA.gd` |
| **M2b** | Detachment rules + enhancements of **Terminator Storm Force, Assault Brethren, Gravis Linebreaker Force, Devastator Brethren, Gravis Siege Force, Tactical Brethren, Ironclad Champions, Tacticus Firestorm Force** | `SMDetachmentsB.gd` |
| **M3a** | Stratagems of the M2a detachments (Gladius 6 + 6 x 3 = 24). Owns the dispatcher `SMCodex11e.gd` (`custom:sm11e`, same API as `SWCodex11e.gd`) which delegates to group scripts `SMCodexA*.gd` AND, when the file exists, `SMCodexB.gd` (M3b) | `SMCodex11e.gd`, `SMCodexA*.gd` |
| **M3b** | Stratagems of the M2b detachments (8 x 3 = 24) in `SMCodexB.gd` exposing the group-script API M3a's dispatcher calls (read `space_wolves/SWCodex11e.gd` + its group scripts: the same static functions) | `SMCodexB.gd` (+ `SMCodexB*.gd`) |
| **M4a/b/c** | Datasheet + wargear abilities of the generic datasheets, split by list below | `SMAbilitiesA.gd` / `SMAbilitiesB.gd` / `SMAbilitiesC.gd` |

M4 split (datasheet names as printed in SPACE_MARINES_GENERIC.md):
- **M4a**: Apothecary Biologis, Land Raider, Land Raider Crusader, Bladeguard Veteran Squad, Captain, Lieutenant with Combi-weapon, Librarian in Terminator Armour, Captain with Jump Pack, Firestrike Servo-turrets, Drop Pod, Ballistus Dreadnought, Chaplain on Bike, Chaplain with Jump Pack, Storm Speeder Hammerstrike, Chaplain in Terminator Armour, Terminator Assault Squad, Librarian in Phobos Armour, Storm Speeder Hailstrike, Inceptor Squad, Infernus Squad, Iron Father Feirros, Infiltrator Squad, Captain in Terminator Armour, Brutalis Dreadnought, Roboute Guilliman, Thunderhawk Gunship, Techmarine, Vanguard Veteran Squad with Jump Packs, Invictor Tactical Warsuit
- **M4b**: Intercessor Squad, Incursor Squad, Scout Squad, Bladeguard Ancient, Captain in Gravis Armour, Chaplain, Heavy Intercessor Squad, Terminator Squad, Lieutenant, Assault Intercessor Squad, Storm Speeder Thunderstrike, Chief Librarian Tigurius, Gladiator Reaper, Eliminator Squad, Gladiator Valiant, Hellblaster Squad, Aggressor Squad, Adrax Agatone, Darnath Lysander, Land Raider Redeemer, Sternguard Veteran Squad, Librarian, Desolation Squad, Tor Garadon, Lieutenant in Phobos Armour, Impulsor, Ancient in Terminator Armour, Astraeus, Captain in Phobos Armour
- **M4c**: Captain on Bike, Gladiator Lancer, Judiciar, Kayvaan Shrike, Kor'sarro Khan, Land Speeder, Outrider Squad, Redemptor Dreadnought, Reiver Squad, Repulsor, Repulsor Executioner, Rhino, Vulkan He'stan, Company Heroes, Apothecary, Ancient, Assault Intercessors with Jump Packs, Aethon Shaan, Caanok Var, Suboden Khan, Cato Sicarius, Victrix Honour Guard, Captain Titus, Wardens of Ultramar, Eradicator Squad with Heavy Bolters, Marneus Calgar, Invader ATVs, Kaius Konorius, Eradicator Squad with Melta Rifles

Shared rules for all packages:
- Gate everything on `SWCommon.is_sm_army` (11e). Read doctrines only via
  `SWCommon.active_doctrines / doctrine_active`. Append helpers to SWCommon
  only at the END of the file. Preload SWCommon, never another package's module.
- Logic in your own files; engine files get one-line commented hooks. Several
  packages add a line at the same hook (RulesEngine `ork11e_ab_mods` aggregator,
  BasePhase `enter_phase` phase-start entries, StratagemManager dispatch):
  add your own line, never edit another package's.
- Flags `sm11e_<slug>`. Windowed ports: M2a 9881, M2b 9882, M3a 9883,
  M3b 9884, M4a 9885, M4b 9886, M4c 9887; every windowed launch under
  `flock /tmp/codex11e_godot_window.lock`. Scenarios
  `40k/tests/scenarios/sp/sm11e_*.json`. Rulings: `## WP-M<n>` in RULINGS.md.
  Changelog bullets: `changelog/WP-M<n>.md`. Never edit version_history.json.
- Test fixtures: `armies/sm11e_codex_test.json` (generic), build save
  fixtures with a helper like `tests/helpers/gen_sw11e_s2_fixtures.gd`.
- The Space Wolves work (S2/S3/S4 modules + tests) must keep passing.

## Integration (M5)
Merge all packages; full gate; every `sm11e_*` + `sw11e_*` scenario;
AI-vs-AI games with a generic Space Marine army; live screenshots; one
version_history entry; push.
