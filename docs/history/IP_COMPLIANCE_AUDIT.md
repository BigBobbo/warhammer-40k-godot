# IP Compliance Audit: Warhammer 40K Godot Project

**Date:** 2026-03-10
**Scope:** Full codebase audit of `/home/user/warhammer-40k-godot`
**Purpose:** Identify all Games Workshop intellectual property that must be changed or removed before public release.

---

## Executive Summary

This project is a Godot 4.6 implementation of the Warhammer 40,000 10th Edition tabletop game. It contains **pervasive** Games Workshop (GW) IP throughout every layer: data files, game logic, UI, assets, tests, and documentation. However, the good news is that the *game engine and architecture* you've built -- the phase system, AI, multiplayer, dice resolution, line-of-sight, terrain, UI framework -- is entirely your own work and can be retained.

The audit is organized into three categories:

1. **MUST CHANGE** -- Direct GW IP that must be replaced before any public release
2. **COULD STAY (with modifications)** -- Generic game mechanics that need GW-specific names/values stripped
3. **CAN STAY AS-IS** -- Your original code, architecture, and generic game systems

---

## 1. MUST CHANGE -- Direct Games Workshop IP

### 1.1 Faction Names & Identities

Every GW faction name is trademarked and must be replaced. The following are referenced across the codebase:

| GW Faction Name | Files Affected | Notes |
|---|---|---|
| Space Marines / Adeptus Astartes / Primaris | `armies/space_marines.json`, `FactionStratagemLoader.gd`, 50+ scripts, tests | Core trademark |
| Orks | `armies/orks.json`, `Orks_2000.json`, multiple scripts/tests | GW-specific spelling ("Orks" not "Orcs") |
| Adeptus Custodes | `armies/adeptus_custodes.json`, multiple scripts | Wholly GW-owned |
| Chaos Space Marines | `FactionStratagemLoader.gd`, CSV data | Wholly GW-owned |
| Aeldari / Craftworld Eldar | `FactionStratagemLoader.gd`, CSV data | Wholly GW-owned |
| Necrons | CSV data, faction mappings | Wholly GW-owned |
| T'au Empire | `FactionStratagemLoader.gd`, CSV data | Wholly GW-owned |
| Tyranids | CSV data, faction mappings | Wholly GW-owned |
| Drukhari | `FactionStratagemLoader.gd`, CSV data | Wholly GW-owned |
| Death Guard | CSV data | Wholly GW-owned |
| Thousand Sons | CSV data | Wholly GW-owned |
| World Eaters | CSV data | Wholly GW-owned |
| Adepta Sororitas | CSV data | Wholly GW-owned |
| Genestealer Cults | CSV data | Wholly GW-owned |
| Imperial Knights / Chaos Knights | CSV data | Wholly GW-owned |
| Leagues of Votann | CSV data | Wholly GW-owned |
| Grey Knights | CSV data | Wholly GW-owned |
| Astra Militarum / Imperial Guard | CSV data | Wholly GW-owned |
| Adeptus Mechanicus | CSV data | Wholly GW-owned |
| Emperor's Children | CSV data | Wholly GW-owned |

**Key files to modify:**
- `40k/data/Factions.csv` -- All 27 faction entries
- `40k/autoloads/FactionStratagemLoader.gd` -- Lines 81-102, all faction aliases
- `40k/autoloads/FactionAbilityManager.gd` -- Faction ability mappings
- `40k/armies/*.json` -- All army list files (7+ files)

### 1.2 Unit Names & Datasheets

All named units, characters, and datasheet names are GW IP:

- **Space Marine units:** Intercessor Squad, Infernus Squad, Ballistus Dreadnought, Captain, etc.
- **Ork units:** Boyz, Warboss, Painboss, Weirdboy, Nob, etc.
- **Custodes units:** Custodian Guard, Blade Champion, Shield Captain, etc.
- **Named characters:** Ursula Creed, Fulgrim, etc.
- **All unit keywords:** PRIMARIS, IMPERIUM, ADEPTUS ASTARTES, INFANTRY (when faction-specific), etc.

**Key files:**
- `40k/armies/*.json` -- Unit definitions with names, keywords, stats
- `server/public/data/datasheets.json` -- Complete datasheet database
- `server/tools/wahapedia_csv/Datasheets*.csv` -- All datasheet CSV files (7 files)

### 1.3 Weapon Names

GW-trademarked weapon names used throughout:

| Weapon | Context |
|---|---|
| Bolt rifle / Boltgun / Bolter / Heavy Bolter | Army JSON, datasheets, tests |
| Plasma gun / Plasma pistol / Plasma rifle | Army JSON, datasheets |
| Meltagun / Melta weapons | Army JSON, PRP docs, tests |
| Lascannon | Datasheets, CSV data |
| Chainsword / Astartes Chainsword | `TokenVisual.gd`, army JSON, tests |
| Power Sword / Power Fist | Army JSON, datasheets |
| Thunder Hammer | Datasheets |
| Guardian Spear / Sentinel Blade | `datasheets.json`, Custodes data |
| All other GW-specific weapon names | Various CSV/JSON data files |

### 1.4 Faction-Specific Abilities & Rules

These named abilities are GW IP:

| Ability | Faction | Files |
|---|---|---|
| Oath of Moment | Space Marines | 13 files including `FactionAbilityManager.gd`, `CommandPhase.gd`, `ShootingController.gd`, `AIDecisionMaker.gd`, tests |
| Waaagh! | Orks | `FactionAbilityManager.gd`, ability files |
| Martial Ka'tah | Adeptus Custodes | `datasheets.json`, ability files |
| Gladius Task Force | Space Marines (detachment) | `armies/space_marines.json` |
| All detachment names | All factions | `40k/data/Detachments.csv` (130KB of detachment rules) |

### 1.5 Stratagem Names & Descriptions

The entire stratagem system contains GW-copyrighted content:

- `40k/data/Stratagems.csv` (1MB) -- **Complete stratagem database** with names, descriptions, rules text
- All stratagem names (Command Re-roll, Insane Bravery, Counter-Offensive, Grenade, Fire Overwatch, etc.)
- All stratagem flavour text and rules descriptions
- Faction-specific stratagems for every faction

### 1.6 Wahapedia Data (Bulk GW IP)

The `server/tools/wahapedia_csv/` directory contains **21 CSV files** that are direct exports of GW game data via Wahapedia. **All must be removed or replaced:**

| File | Content |
|---|---|
| `Abilities.csv` | All unit abilities |
| `Datasheets.csv` | All unit datasheets |
| `Datasheets_abilities.csv` | Datasheet-ability mappings |
| `Datasheets_detachment_abilities.csv` | Detachment ability mappings |
| `Datasheets_enhancements.csv` | Enhancement options |
| `Datasheets_keywords.csv` | Unit keywords |
| `Datasheets_leader.csv` | Leader unit data |
| `Datasheets_models.csv` | Model data |
| `Datasheets_models_cost.csv` | Points costs |
| `Datasheets_options.csv` | Wargear options |
| `Datasheets_stratagems.csv` | Stratagem mappings |
| `Datasheets_unit_composition.csv` | Unit composition rules |
| `Datasheets_wargear.csv` | Weapon profiles |
| `Detachment_abilities.csv` | Detachment ability rules |
| `Detachments.csv` | All detachment definitions |
| `Enhancements.csv` | All enhancements |
| `Factions.csv` | All factions |
| `Source.csv` | Links to official GW PDFs |
| `Stratagems.csv` | All stratagems |
| `Last_update.csv` | Update metadata |

### 1.7 Visual Assets -- GW Logos & Mission Images

Located in `40k/deployment_zones/Chapter Approved 2025-26_files/`:

**26 Faction Logo PNGs** (all GW trademarks):
- `AdeptusMechanicus_logo2.png`, `AdeptaSororitas_logo2.png`, `AdeptusCustodes_logo2.png`, `AstraMilitarum_logo2.png`, `Aeldari_logo2.png`, `BlackTemplars_logo2.png`, `ChaosKnights_logo2.png`, `ChaosDaemons_logo2.png`, `ChaosSpaceMaines_logo2.png`, `DarkAngels_logo2.png`, `DeathGuard_logo2.png`, `Deathwatch_logo2.png`, `Drukhari_logo2.png`, `EmperorsChildren_logo2.png`, `GreyKnights_logo2.png`, `ImperialKnights_logo2.png`, `GenestealerCults_logo2.png`, `Necrons_logo2.png`, `Orks_logo2.png`, `TauEmpire_logo2.png`, `ThousandSons_logo2.png`, `WorldEaters_logo2.png`, `Tyranids_logo2.png`, `LeaguesOfVotann_logo2.png`, `Indomitus_logo2.png`, `FW_logo2.png`

**17 Mission Scenario PNGs** (from Chapter Approved, GW publication):
- All `CA6_Ass_*.png`, `CA6_Inc_*.png`, `CA6_SF_*.png` files

**Terrain Layout PNGs:**
- `CA_TerrainLayout1.png` through `CA_TerrainLayout8.png`

**Warhammer 40K Logo:**
- `wh40k9_logo2.png`

### 1.8 Project Naming

| Item | Current Value | Must Change |
|---|---|---|
| Project name | `config/name="40k"` in `project.godot` | Yes |
| Repository name | `warhammer-40k-godot` | Yes |
| Save file extension | `.w40ksave` | Yes |
| Wahapedia references | In `CLAUDE.md` and docs | Yes |

### 1.9 Mission & Deployment Zone Names

GW-trademarked mission/deployment names:
- "Hammer and Anvil", "Dawn of War", "Crucible of Battle", "Search and Destroy", "Sweeping Engagement" -- in `40k/deployment_zones/*.json`
- "Chapter Approved" -- folder name and references
- All GW-specific scenario names (Last Stand, Defensive Line, Breakout, Pincer Attack, etc.)

### 1.10 Documentation Containing GW IP

- `CLAUDE.md` -- References wahapedia.ru for WH40K rules
- `ABILITIES_AUDIT.md` -- Lists all GW abilities by name
- All files in `docs/PRP/` -- Reference GW rules, mechanics names, unit names
- All files in `PRPs/` -- Reference GW-specific content

---

## 2. COULD STAY (with name/value changes)

These are game *mechanics* that are common to tabletop wargaming but currently use GW-specific terminology or exact values. The underlying code logic can remain; only the naming and specific numeric values need to change.

### 2.1 Core Stat Line

The stat block structure (Move, Toughness, Save, Wounds, Leadership, OC) is a specific GW format. Generic alternatives exist:

| GW Term | Generic Alternative | Code Impact |
|---|---|---|
| Ballistic Skill (BS) | Ranged Accuracy / Shooting Skill | Variable names, JSON keys |
| Weapon Skill (WS) | Melee Accuracy / Fighting Skill | Variable names, JSON keys |
| Toughness (T) | Durability / Resilience | Variable names, JSON keys |
| Objective Control (OC) | Zone Control / Capture Power | Variable names, JSON keys |
| Leadership (Ld) | Morale / Resolve | Variable names, JSON keys |
| Armour Save | Defence / Armour | Variable names, JSON keys |
| Invulnerable Save | Ward Save / Energy Shield | Variable names, JSON keys |
| Feel No Pain (FNP) | Damage Reduction / Shrug | Variable names, logic |

**Note:** Individual stat *names* are not copyrightable, but the specific combination and the way they interact mechanically as a system is what GW could claim.

### 2.2 Weapon Keyword System

The keyword names are GW-specific but the underlying mechanics are generic:

| GW Keyword | Mechanic (Retainable) | Rename To |
|---|---|---|
| Lethal Hits | Auto-wound on critical hit | Critical Wounds |
| Devastating Wounds | Bypass saves on critical wound | Piercing Criticals |
| Sustained Hits | Extra hits on critical | Bonus Hits |
| Anti-X | Improved wound rolls vs keyword | Type Bane |
| Melta | Bonus damage at half range | Close-range Boost |
| Hazardous | Risk of self-damage | Volatile / Unstable |
| Torrent | Auto-hit | Spray / Area |
| Blast | Extra attacks vs large units | Explosive |
| Assault | Shoot after advancing | Mobile Fire |
| Heavy | +1 to hit if stationary | Braced |
| Rapid Fire | Bonus attacks at half range | Rapid Fire (generic enough) |
| Pistol | Shoot in engagement | Sidearm |
| Twin-linked | Re-roll wounds | Linked |

**Code impact:** These are referenced across `ShootingPhase.gd`, `ShootingController.gd`, `FightPhase.gd`, `FightController.gd`, `Mathhammer.gd`, `MathhammerUI.gd`, `AIDecisionMaker.gd`, and many test files. The *logic* stays; only string constants and variable names change.

### 2.3 Phase Names

The turn structure (Command -> Movement -> Shooting -> Charge -> Fight -> Morale) closely mirrors GW's phase system. While turn-based phase systems are generic, the exact phase names and order are recognizably GW's.

| GW Phase | Generic Alternative |
|---|---|
| Command Phase | Orders Phase / Tactics Phase |
| Movement Phase | Movement Phase (generic enough) |
| Shooting Phase | Ranged Phase / Fire Phase |
| Charge Phase | Charge Phase (generic enough) |
| Fight Phase | Melee Phase / Combat Phase |
| Morale Phase | Morale Phase (generic enough) |
| Battle-shock | Suppression / Pinning |

### 2.4 Game Concepts

| GW Concept | Generic Alternative |
|---|---|
| Command Points (CP) | Tactical Points / Strategy Points |
| Stratagems | Tactics / Gambits / Maneuvers |
| Detachments | Doctrines / Battle Plans |
| Enhancements | Upgrades / Traits |
| Deep Strike | Reserves / Reinforcements |
| Overwatch | Reactive Fire / Opportunity Fire |
| Battle Round | Game Round |
| Engagement Range | Melee Range / Contact Range |

### 2.5 Terrain Rules

GW's specific terrain trait names should change, but the mechanical concepts are standard wargaming:

| GW Terrain Rule | Generic Alternative |
|---|---|
| Obscuring | Blocks Line of Sight |
| Light Cover / Heavy Cover | Partial Cover / Full Cover |
| Defensible | Fortified |
| Breachable | Passable |

---

## 3. CAN STAY AS-IS -- Your Original Work

The following are entirely your own creation and have **no IP concerns**:

### 3.1 Game Engine & Architecture
- **Phase system framework** (`BasePhase.gd` and all phase controllers) -- the *code structure* is yours
- **Turn management** (`TurnManager.gd`, `PhaseManager.gd`, `GameManager.gd`)
- **Game state management** (`GameState.gd`, `BoardState.gd`, `StateSerializer.gd`)
- **All autoload singletons** (as code architecture)

### 3.2 AI System (679KB+ of original code)
- `AIDecisionMaker.gd` -- Your entire AI decision engine
- `AIPlayer.gd` -- AI controller
- `AIAbilityAnalyzer.gd` -- Ability evaluation
- All AI utility/scoring logic
- AI visualization tools (`AIActionLogOverlay.gd`, `AITurnReplayPanel.gd`, etc.)

### 3.3 Combat Resolution Engine
- Dice rolling logic and visualization (`DiceRollVisual.gd`)
- Hit/wound/save resolution pipelines (the *code*, not the exact formulas if they replicate GW's wound chart)
- Wound allocation system (`WoundAllocationOverlay.gd`)
- Mathhammer probability calculator (the *tool*, not GW-specific stat values)

### 3.4 Line of Sight & Measurement Systems
- `LineOfSightCalculator.gd`, `EnhancedLineOfSight.gd`, `LineOfSightManager.gd`
- `MeasuringTapeManager.gd`, `Measurement.gd`
- All LoS visualization and debugging tools

### 3.5 Multiplayer & Networking
- `NetworkManager.gd` -- Entire networking layer
- `MultiplayerLobby.gd`, `WebLobby.gd` -- Lobby systems
- `server/relay-server.js` -- Your relay server
- Cloud storage integration (`CloudStorage.gd`)

### 3.6 Save/Load System
- `SaveLoadManager.gd`, `SaveLoadDialog.gd`
- State serialization/deserialization
- File format design (rename extension from `.w40ksave`)

### 3.7 UI Framework
- All dialog systems (`dialogs/*.gd` -- 28 files)
- Settings menu system (`SettingsMenu.gd`, `SettingsService.gd`)
- Main menu framework (`MainMenu.gd`)
- Token visualization system (`TokenVisual.gd`, `TokenDrawUtils.gd`)
- Ghost/preview visuals (`GhostVisual.gd`)
- All overlay systems

### 3.8 Visual Effects
- All 3 shader files (CRT, felt texture, model highlight)
- Projectile and effect visualizations
- Board rendering

### 3.9 Testing Infrastructure
- GUT test framework integration
- All test *structure* and helpers (test content referencing GW units/names would need updating)

### 3.10 Deployment & DevOps
- GitHub Actions workflows
- Docker configuration
- Fly.io deployment
- Build scripts

### 3.11 Data Loading Architecture
- CSV parser in `FactionStratagemLoader.gd`
- Army list JSON parser in `ArmyListManager.gd`
- Mission/deployment zone data loaders
- The entire data-driven architecture (just needs different data)

---

## 4. The Wound Chart Question

One specific mechanical concern: the GW wound chart (comparing Strength vs Toughness to determine the D6 roll needed to wound) is a distinctive GW mechanic. If your `RulesEngine.gd` or combat resolution code replicates the exact S vs T comparison table from WH40K 10th Edition, this is likely protectable as a specific creative expression of game rules.

**Recommendation:** Modify the wound probability curve. You could use a different formula (e.g., a linear differential, percentage-based system, or your own custom table) while keeping the general concept of "attack power vs. target durability."

---

## 5. Recommended Approach for De-Identification

### Phase 1: Data Layer (Highest priority, cleanest separation)
1. **Delete** `server/tools/wahapedia_csv/` entirely (21 files of raw GW data)
2. **Delete** `40k/deployment_zones/Chapter Approved 2025-26_files/` (all GW logos and mission images)
3. **Replace** `40k/data/Factions.csv`, `Detachments.csv`, `Stratagems.csv` with your own original faction/ability data
4. **Replace** `server/public/data/datasheets.json` with original unit data
5. **Replace** all `40k/armies/*.json` files with original army lists

### Phase 2: Code Constants & Naming
6. Rename all faction string constants in `FactionStratagemLoader.gd`, `FactionAbilityManager.gd`
7. Rename weapon keywords (Lethal Hits -> your term) across all phase/controller scripts
8. Rename game concept terms (Stratagems -> Tactics, etc.)
9. Rename stat line terms (BS -> Ranged Accuracy, etc.) in JSON schemas and code

### Phase 3: Project Identity
10. Rename project from "40k" in `project.godot`
11. Change save file extension from `.w40ksave`
12. Remove all Wahapedia URL references from documentation
13. Create your own lore, faction names, and universe

### Phase 4: Mechanical Differentiation
14. Review and modify the wound chart formula if it exactly replicates GW's
15. Consider tweaking the phase structure (e.g., combining or splitting phases)
16. Add or modify mechanics to differentiate from WH40K (alternate activation, resource systems, etc.)

### Phase 5: Content Creation
17. Create original faction identities with distinct themes
18. Design original unit archetypes with your own stat profiles
19. Write original ability/stratagem/enhancement text
20. Create or source original faction iconography
21. Design original mission scenarios and deployment zones

---

## 6. Scale of Work Estimate

| Category | Files Affected | Severity |
|---|---|---|
| Data files (CSV/JSON) | ~35 files | Delete & recreate |
| Image assets | ~45 files | Delete & recreate |
| GDScript string constants | ~100+ files | Find & replace |
| Test files | ~50+ files | Update test data |
| Documentation | ~30+ files | Rewrite references |
| Architecture/engine code | 0 files | No changes needed |

The architecture is well-designed and data-driven, which actually makes this *feasible*. Because unit stats, abilities, and faction data are loaded from external CSV/JSON files rather than hardcoded, the primary work is:
1. Creating original game data to replace GW content
2. A large but mechanical find-and-replace for terminology in code
3. Creating original visual assets

---

## 7. What You'd Be Left With

After de-identification, you would have a **fully functional sci-fi tabletop wargame engine** featuring:
- Phase-based turn system with a complete rules engine
- Sophisticated AI opponent (679KB+ of decision-making logic)
- Multiplayer support with relay server and web lobby
- Save/load system with cloud storage
- Mathhammer probability calculator
- Line-of-sight and terrain systems
- Comprehensive test suite framework
- Deployment and CI/CD pipeline

This is a substantial and impressive piece of engineering. The GW IP is the *content layer* sitting on top of a generic wargame engine you've built. The separation is achievable.
